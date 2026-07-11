// Pins ShadowCouplingCacheData's 60-minute freshness boundary with a
// FakeClock. The freshness rule is `now - discoveredAt < 60 whole minutes`
// (integer-minute truncation), so the entry is fresh at 59m59s, and stale
// the instant the elapsed time reaches a full 60 minutes.
//
// Pure in-memory value-object check — no disk, no network. The clock is
// injected through `isFreshAt(Clock)`, the testable twin of the production
// `isFresh` getter (which reads the real clock).

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/shadow_coupling_cache.dart';

import '../support/fake_clock.dart';

ShadowCouplingCacheData _dataAt(DateTime discoveredAt) => ShadowCouplingCacheData(
      headHash: 'deadbeef',
      discoveredAt: discoveredAt,
      shadowCommitCount: 3,
      jaccardEdges: const {},
    );

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 9, 0, 0);

  test('fresh just under 60 minutes, stale at/after exactly 60 minutes', () {
    final data = _dataAt(t0);
    final clock = FakeClock(t0);

    // t0: trivially fresh.
    expect(data.isFreshAt(clock), isTrue);

    // 59m59s: still fresh (elapsed truncates to 59 whole minutes).
    clock.set(t0.add(const Duration(minutes: 59, seconds: 59)));
    expect(data.isFreshAt(clock), isTrue,
        reason: 'fresh at 59m59s (< 60 whole minutes)');

    // Exactly 60m00s: stale (elapsed is 60 whole minutes, not < 60).
    clock.set(t0.add(const Duration(minutes: 60)));
    expect(data.isFreshAt(clock), isFalse,
        reason: 'stale at exactly 60m00s');

    // 60m01s: stale.
    clock.set(t0.add(const Duration(minutes: 60, seconds: 1)));
    expect(data.isFreshAt(clock), isFalse);
  });

  test('isFreshAt matches the wall-clock isFresh getter at a live instant', () {
    // A cache discovered "now" must read fresh through both the injected
    // and the production code paths — proves the SystemClock default is the
    // same behaviour, not a divergent branch.
    final data = _dataAt(DateTime.now());
    expect(data.isFresh, isTrue);
    expect(data.isFreshAt(FakeClock(DateTime.now())), isTrue);
  });
}
