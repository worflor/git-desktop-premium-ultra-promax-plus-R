// disposable_slot_test.dart — the resource-handoff laws.
//
// The changes page holds spool-backed documents (each owning a temp dir + a
// file handle) in slots that are replaced on every load, across single-file,
// multi-file and cache-hit paths. A missed release on ONE branch leaks a temp
// dir silently; a release of the value just installed blanks a live view.
// Neither throws, so only these laws catch them.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/disposable_slot.dart';

class _Res {
  _Res(this.id);
  final String id;
  int disposals = 0;
  void dispose() => disposals++;
}

DisposableSlot<_Res> _slot(List<String> log) =>
    DisposableSlot<_Res>((r) {
      r.dispose();
      log.add(r.id);
    });

void main() {
  test('installing a value into an empty slot disposes nothing', () {
    final log = <String>[];
    final slot = _slot(log);
    final a = _Res('a');
    slot.install(a);
    expect(slot.value, same(a));
    expect(a.disposals, 0);
    expect(log, isEmpty);
  });

  test('installing a replacement disposes exactly the previous value', () {
    final log = <String>[];
    final slot = _slot(log);
    final a = _Res('a');
    final b = _Res('b');
    slot.install(a);
    slot.install(b);
    expect(slot.value, same(b));
    expect(a.disposals, 1, reason: 'the replaced value must be freed');
    expect(b.disposals, 0, reason: 'the live value must never be freed');
    expect(log, ['a']);
  });

  test('re-installing the SAME value is a no-op, not a self-dispose', () {
    final log = <String>[];
    final slot = _slot(log);
    final a = _Res('a');
    slot.install(a);
    slot.install(a);
    expect(slot.value, same(a));
    expect(a.disposals, 0, reason: 'disposing the live value blanks the view');
    expect(log, isEmpty);
  });

  test('clear disposes the held value and empties the slot', () {
    final log = <String>[];
    final slot = _slot(log);
    final a = _Res('a');
    slot.install(a);
    slot.clear();
    expect(slot.value, isNull);
    expect(slot.isEmpty, isTrue);
    expect(a.disposals, 1);
    expect(log, ['a']);
  });

  test('clearing an empty slot is safe and disposes nothing', () {
    final log = <String>[];
    final slot = _slot(log)..clear()..clear();
    expect(slot.isEmpty, isTrue);
    expect(log, isEmpty);
  });

  test('a long interleaved run leaks nothing and frees only replaced values',
      () {
    // The reported risk shape: single → multi → single handoffs interleaved
    // with cache-hit clears. Every value except the last must end freed
    // exactly once — that is the whole contract.
    final log = <String>[];
    final slot = _slot(log);
    final made = <_Res>[];
    for (var i = 0; i < 20; i++) {
      final r = _Res('r$i');
      made.add(r);
      slot.install(r);
      if (i % 3 == 2) slot.clear(); // a load that produced no spool doc
    }
    slot.clear();
    for (final r in made) {
      expect(r.disposals, 1, reason: '${r.id} must be freed exactly once');
    }
    expect(slot.isEmpty, isTrue);
    expect(log.length, made.length);
  });
}
