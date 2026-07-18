// Regression test for the telemetry append path's torn-write guard.
//
// The append optimization writes one line in the common case instead of
// rewriting the whole .jsonl. `writeAsString(append)` is not atomic, so a crash
// mid-append can leave a partial last line with no trailing newline. Without a
// guard, the NEXT append concatenates onto it (`{partial}{latest}\n`) → an
// unparseable line that loses `latest` too. The guard prepends a newline when
// the file doesn't already end in one, so a torn write costs at most the
// already-torn line — never the next sample. This test reproduces that exact
// scenario through the public `recordSample` path.
//
// Hermetic via StoragePaths.debugOverrideDir: the store persists to a single
// fixed <gdpuDataDir>/command_telemetry.jsonl, and under a parallel full-suite
// run OTHER test processes emit real telemetry into that same file (every
// backend command records a sample) — a concurrent full rewrite there can drop
// the sample this test appends. The override pins this test to its own temp
// dir so neither cross-process traffic nor the developer's real telemetry is
// ever involved.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/command_telemetry_store.dart';
import 'package:git_desktop/backend/storage_paths.dart';

void main() {
  late Directory scratch;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('gdpu_telemetry_test');
    StoragePaths.debugOverrideDir = scratch;
  });

  tearDown(() async {
    StoragePaths.debugOverrideDir = null;
    await StoragePaths.deleteIfExists(scratch);
  });

  test(
    'append after a torn (newline-less) last line preserves the new sample',
    () async {
      final dir = await StoragePaths.gdpuDataDir();
      await dir.create(recursive: true);
      final file = File(
        '${dir.path}${Platform.pathSeparator}command_telemetry.jsonl',
      );

      // A fresh, valid sample (recent so retention keeps it → the append path is
      // exercised, not a full rewrite), followed by a TORN partial line with no
      // trailing newline — the signature of a crash mid-append.
      final now = DateTime.now().toUtc().toIso8601String();
      final clean =
          '{"id":"aaaaaaaa-bbbbbbbb","scope":"backend","command":"clean_before",'
          '"ok":true,"durationMs":5,"createdAt":"$now"}';
      await file.writeAsString('$clean\n{"id":"torn","scope":"back');

      // Append a new sample via the public path → hits _appendSample.
      await CommandTelemetryStore.recordSample(
        scope: 'backend',
        command: 'after_torn',
        ok: true,
        durationMs: 7.0,
      );

      final snap = await CommandTelemetryStore.getSnapshot();
      final commands = snap.recentSamples.map((s) => s.command).toSet();
      // The new sample survives on its own parseable line; only the torn partial
      // is dropped (skipped on read). Without the guard, 'after_torn' would have
      // been concatenated into the torn line and lost.
      expect(
        commands.contains('after_torn'),
        isTrue,
        reason: 'torn last line swallowed the new sample',
      );
      expect(
        commands.contains('clean_before'),
        isTrue,
        reason: 'the prior clean sample should remain',
      );
    },
  );
}
