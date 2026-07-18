// wick_enabled_gate_test.dart — the wick integration's hard on/off.
//
// The toggle exists to stop CPU, so the laws are about WORK, not labels: a
// disabled integration never reports itself live (the single gate every
// consumer reads), never indexes, never queries, and restores from settings
// without probing. `available` composes enabled + detected + installed —
// these pin that composition so a future consumer can't route around it by
// reading a rawer flag.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/wick_state.dart';

void main() {
  test('disabled state is never available, and cannot index or query', () async {
    final wick = WickState()..setEnabled(false);
    expect(wick.enabled, isFalse);
    expect(wick.available, isFalse);

    // Both work entry points must no-op. If either spawned the binary, it
    // would be observable as a repo state appearing.
    await wick.indexRepo(r'C:\nonexistent\repo');
    expect(wick.stateFor(r'C:\nonexistent\repo'), isNull);
    expect(await wick.query(r'C:\nonexistent\repo', 'anything'), isNull);
  });

  test('restore(enabled: false) stores the path but never probes', () {
    final wick = WickState()
      ..restore(path: r'C:\tools\wick.exe', enabled: false);
    expect(wick.enabled, isFalse);
    expect(wick.customPath, r'C:\tools\wick.exe',
        reason: 'a later enable must probe the configured binary, not PATH');
    expect(wick.detected, isFalse, reason: 'disabled must not run detection');
    expect(wick.available, isFalse);
  });

  test('toggling off drops per-repo state so a re-enable starts clean', () {
    final wick = WickState();
    expect(wick.enabled, isTrue, reason: 'defaults on');
    wick.setEnabled(false);
    expect(wick.stateFor(r'C:\any\repo'), isNull);
    expect(wick.available, isFalse);
  });

  test('enabling without a detected binary still reports unavailable', () async {
    final wick = WickState()..setEnabled(false);
    wick.setEnabled(true);
    expect(wick.enabled, isTrue);
    // Detection has not resolved (and would fail for a bogus path anyway):
    // `available` must stay false until detection actually confirms.
    expect(wick.available, isFalse);
  });

  test('detectWick is a no-op while disabled', () async {
    // The chokepoint contract: detection is where the binary would be spawned,
    // so the enabled gate lives there. Calling it directly on a disabled wick
    // must not probe — detected/available stay false. Awaited directly, so no
    // timing race: if the gate regressed, this would run isWickInstalled and
    // flip detected true.
    final wick = WickState()..setEnabled(false);
    await wick.detectWick();
    expect(wick.detected, isFalse);
    expect(wick.available, isFalse);
  });

  test('setCustomPath while disabled stores the path but never probes',
      () async {
    // The exact reported escape hatch: a disabled integration whose custom
    // path changes (via the settings file picker) must not launch detection.
    final wick = WickState()..setEnabled(false);
    wick.setCustomPath(r'C:\tools\wick.exe');
    expect(wick.customPath, r'C:\tools\wick.exe',
        reason: 'stored so a later enable probes the configured binary');
    // Give the (gated) async detection block time to run had it fired.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(wick.detected, isFalse,
        reason: 'disabled must not probe on a path change');
    expect(wick.available, isFalse);
  });

  test('setEnabled is idempotent', () {
    final wick = WickState();
    var notifications = 0;
    wick.addListener(() => notifications++);
    wick.setEnabled(true); // already enabled
    expect(notifications, 0, reason: 'no-op must not churn listeners');
    wick.setEnabled(false);
    expect(notifications, 1);
  });
}
