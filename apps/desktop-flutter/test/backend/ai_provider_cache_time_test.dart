// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Pins the ai.dart provider-cache TTL boundaries with a FakeClock.
//
// The freshness checks for the resolution/availability/model-discovery
// caches, and the 24h on-disk model cache, are private and sit behind
// network-gated discovery calls — they can't be driven end-to-end without
// a real provider binary / HTTP round-trip. So the migration extracted the
// pure time predicates (`_providerCacheFresh`, `_diskModelCacheExpired`)
// and exposed them through minimal @visibleForTesting entry points
// (`debugProviderCacheFresh`, `debugDiskModelCacheExpired`) that route
// through the SAME module clock the production caches read. Driving those
// pins the boundary logic exactly, with no faked network.
//
// (Reported as a deviation: the boundary is proven at the predicate the
// production caches call, not through a live discovery call.)

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart';
import 'package:git_desktop/backend/clock.dart';

import '../support/fake_clock.dart';

void main() {
  tearDown(() => debugSetProviderCacheClock(const SystemClock()));

  test('30-minute model-discovery cache is fresh at 29m59s, stale at 30m01s',
      () {
    final t0 = DateTime.utc(2026, 3, 1, 8, 0, 0);
    final clock = FakeClock(t0);
    debugSetProviderCacheClock(clock);

    final ttl = debugModelDiscoveryCacheTtl; // Duration(minutes: 30)
    expect(ttl, const Duration(minutes: 30));

    // Entry stamped at t0.
    expect(debugProviderCacheFresh(t0, ttl), isTrue);

    // 29m59s later: still fresh.
    clock.set(t0.add(const Duration(minutes: 29, seconds: 59)));
    expect(debugProviderCacheFresh(t0, ttl), isTrue,
        reason: 'fresh just inside the 30-minute TTL');

    // Exactly 30m00s: stale (not strictly < ttl).
    clock.set(t0.add(const Duration(minutes: 30)));
    expect(debugProviderCacheFresh(t0, ttl), isFalse,
        reason: 'stale at exactly the TTL');

    // 30m01s: stale.
    clock.set(t0.add(const Duration(minutes: 30, seconds: 1)));
    expect(debugProviderCacheFresh(t0, ttl), isFalse);
  });

  test('24h on-disk model cache: valid through 24h, expired past 24h', () {
    final t0 = DateTime.utc(2026, 3, 1, 8, 0, 0);
    final clock = FakeClock(t0);
    debugSetProviderCacheClock(clock);

    // Stamp written at t0. Expiry rule is `elapsed.inHours > 24` (whole
    // hours), so it stays valid for the entire 24th hour and only expires
    // once a full 25th hour of wall time has elapsed.
    expect(debugDiskModelCacheExpired(t0), isFalse);

    clock.set(t0.add(const Duration(hours: 24)));
    expect(debugDiskModelCacheExpired(t0), isFalse,
        reason: 'inHours == 24 is not > 24 → still valid');

    clock.set(t0.add(const Duration(hours: 24, minutes: 59)));
    expect(debugDiskModelCacheExpired(t0), isFalse,
        reason: 'inHours truncates 24h59m to 24 → still valid');

    clock.set(t0.add(const Duration(hours: 25)));
    expect(debugDiskModelCacheExpired(t0), isTrue,
        reason: 'inHours == 25 > 24 → expired');
  });
}
