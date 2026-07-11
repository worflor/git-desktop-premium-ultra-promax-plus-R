// Two independent pins on CommandTelemetryStore:
//
//  1. RETENTION BOUNDARY (clock-driven, no real sleep) — a sample whose
//     createdAt is one second before the maxAge cutoff is dropped; one at
//     exactly the cutoff instant, and one a second after, are retained.
//     A FakeClock injected via CommandTelemetryStore.clock drives the
//     cutoff, so the boundary is hit deterministically instead of by
//     ageing real files.
//
//  2. AGGREGATION MATH (time-independent) — p50/p95 percentile selection,
//     failure counting, and scope:command grouping over a known set of
//     samples. Pure computation reached through the public
//     recordSample + getSnapshot path; previously unpinned.
//
// Hermetic: StoragePaths.debugOverrideDir points every read/write at a
// fresh temp dir per test (fresh empty settings → default 30-day policy).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/clock.dart';
import 'package:git_desktop/backend/command_telemetry_store.dart';
import 'package:git_desktop/backend/storage_paths.dart';

import '../support/fake_clock.dart';

void main() {
  late Directory dataDir;

  setUp(() async {
    dataDir = await Directory.systemTemp.createTemp('telemetry_time_');
    StoragePaths.debugOverrideDir = dataDir;
  });

  tearDown(() async {
    StoragePaths.debugOverrideDir = null;
    CommandTelemetryStore.clock = const SystemClock();
    try {
      await dataDir.delete(recursive: true);
    } catch (_) {}
  });

  String line({
    required String id,
    required String command,
    required bool ok,
    required int durationMs,
    required String createdAt,
  }) =>
      jsonEncode({
        'id': id,
        'scope': 'backend',
        'command': command,
        'ok': ok,
        'durationMs': durationMs,
        'createdAt': createdAt,
      });

  test('retention drops samples strictly before the maxAge cutoff, keeps '
      'the cutoff instant and newer (exact boundary, 30-day default)',
      () async {
    // Freeze "now". Default policy is 30 days, so cutoff == now - 30d.
    final now = DateTime.utc(2026, 6, 1, 12, 0, 0);
    CommandTelemetryStore.clock = FakeClock(now);
    final cutoff = now.toUtc().subtract(const Duration(days: 30));

    final file = File(
        '${dataDir.path}${Platform.pathSeparator}command_telemetry.jsonl');
    await file.writeAsString([
      // 1s before cutoff → isBefore(cutoff) → dropped.
      line(
        id: 'a1',
        command: 'too_old',
        ok: true,
        durationMs: 5,
        createdAt:
            cutoff.subtract(const Duration(seconds: 1)).toIso8601String(),
      ),
      // exactly the cutoff instant → NOT before → retained.
      line(
        id: 'a2',
        command: 'exactly_cutoff',
        ok: true,
        durationMs: 6,
        createdAt: cutoff.toIso8601String(),
      ),
      // 1s after cutoff → retained.
      line(
        id: 'a3',
        command: 'fresh_enough',
        ok: true,
        durationMs: 7,
        createdAt: cutoff.add(const Duration(seconds: 1)).toIso8601String(),
      ),
    ].join('\n'));

    final snap = await CommandTelemetryStore.getSnapshot();
    final commands = snap.recentSamples.map((s) => s.command).toSet();

    expect(commands.contains('too_old'), isFalse,
        reason: 'a sample 1s before the cutoff must be dropped');
    expect(commands.contains('exactly_cutoff'), isTrue,
        reason: 'a sample AT the cutoff instant is not "before" → kept');
    expect(commands.contains('fresh_enough'), isTrue,
        reason: 'a sample after the cutoff must be kept');
    expect(snap.sampleCount, 2);
  });

  test('aggregation computes p50/p95, failureCount and grouping correctly',
      () async {
    // Group "backend:op": durations 10,20,30,40,50 with two failures.
    // sorted = [10,20,30,40,50]
    //   p50: rank = ceil(5*50/100)=3 → index 2 → 30
    //   p95: rank = ceil(5*95/100)=5 → index 4 → 50
    final durations = [10, 20, 30, 40, 50];
    final failures = {10, 40}; // two of them fail
    for (final d in durations) {
      await CommandTelemetryStore.recordSample(
        scope: 'backend',
        command: 'op',
        ok: !failures.contains(d),
        durationMs: d.toDouble(),
      );
    }
    // A second group to prove grouping/sorting keeps them separate.
    await CommandTelemetryStore.recordSample(
      scope: 'backend',
      command: 'other',
      ok: true,
      durationMs: 99.0,
    );

    final snap = await CommandTelemetryStore.getSnapshot();
    final op = snap.summaries.firstWhere((s) => s.command == 'op');
    final other = snap.summaries.firstWhere((s) => s.command == 'other');

    expect(op.sampleCount, 5);
    expect(op.failureCount, 2);
    expect(op.p50Ms, 30);
    expect(op.p95Ms, 50);
    expect(op.lastDurationMs, 50, reason: 'last recorded duration in group');

    expect(other.sampleCount, 1);
    expect(other.failureCount, 0);
    expect(other.p50Ms, 99);
    expect(other.p95Ms, 99);

    // Summaries are sorted by scope then command → 'op' before 'other'.
    final commands = snap.summaries.map((s) => s.command).toList();
    expect(commands, ['op', 'other']);
  });
}
