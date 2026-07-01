// Round-trip + debounce test for the coupling-nudge outcome ledger.
//
// Pure IO: write shown/accepted events to a temp dir, read them back,
// assert the JSONL survives the round-trip and that `shown` is debounced
// per (path, anchor) per ledger while `accepted` never is. No engine
// claims here — the ledger records ground truth, it doesn't judge it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/nudge_ledger.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nudge_ledger_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  // The ledger's appends are fire-and-forget on a static single-writer
  // chain; a tiny settle lets the queued writes flush before we read.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  test('shown + accepted events round-trip through the JSONL', () async {
    final ledger = NudgeLedger('/repo/a', storageDirOverride: tempDir);
    ledger.recordShown(
        path: 'lib/a.dart', anchor: 'lib/b.dart', score: 0.42, receipts: true);
    ledger.recordAccepted(
        path: 'lib/a.dart', anchor: 'lib/b.dart', score: 0.42, receipts: true);
    await settle();

    final events = await ledger.readAll();
    expect(events, hasLength(2));

    expect(events[0].kind, 'shown');
    expect(events[0].path, 'lib/a.dart');
    expect(events[0].anchor, 'lib/b.dart');
    expect(events[0].score, closeTo(0.42, 1e-9));
    expect(events[0].receipts, isTrue);
    expect(events[0].ts, isNotEmpty);

    expect(events[1].kind, 'accepted');
    expect(events[1].path, 'lib/a.dart');
  });

  test('shown is debounced per (path, anchor); accepted is not', () async {
    final ledger = NudgeLedger('/repo/b', storageDirOverride: tempDir);
    // Same (path, anchor) shown three times — a scroll rebuild storm.
    for (var i = 0; i < 3; i++) {
      ledger.recordShown(
          path: 'x.dart', anchor: 'y.dart', score: 0.3, receipts: false);
    }
    // A different anchor is a distinct exposure and must not be debounced.
    ledger.recordShown(
        path: 'x.dart', anchor: 'z.dart', score: 0.3, receipts: false);
    // Every accept is ground truth — no debounce.
    ledger.recordAccepted(
        path: 'x.dart', anchor: 'y.dart', score: 0.3, receipts: false);
    ledger.recordAccepted(
        path: 'x.dart', anchor: 'y.dart', score: 0.3, receipts: false);
    await settle();

    final events = await ledger.readAll();
    final shown = events.where((e) => e.kind == 'shown').toList();
    final accepted = events.where((e) => e.kind == 'accepted').toList();

    expect(shown, hasLength(2),
        reason: 'three shows of (x,y) collapse to one; (x,z) is distinct');
    expect(shown.map((e) => e.anchor).toSet(), {'y.dart', 'z.dart'});
    expect(accepted, hasLength(2),
        reason: 'accepts are ground truth and never debounced');
  });

  test('readAll on an untouched repo yields empty', () async {
    final ledger = NudgeLedger('/repo/never-written', storageDirOverride: tempDir);
    expect(await ledger.readAll(), isEmpty);
  });
}
