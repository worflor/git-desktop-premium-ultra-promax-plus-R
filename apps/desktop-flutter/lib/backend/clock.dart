// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// clock.dart — the one testable time seam for the backend.
//
// Every time-dependent behaviour in the app (cache freshness, retry
// backoff, retention windows, throttles) historically read the wall clock
// directly via `DateTime.now()`. That hard-wires the behaviour to real
// elapsed time, so none of it can be tested without sleeping — which is
// slow, flaky, and can't hit an exact TTL boundary.
//
// This file introduces a minimal injectable clock so any TTL/retention
// site can be pinned deterministically:
//
//   1. Depend on a [Clock] instead of calling `DateTime.now()` directly.
//   2. Default the dependency to `const SystemClock()` so production
//      behaviour is bit-identical to the old code (the default IS
//      `DateTime.now()`).
//   3. In a test, inject a `FakeClock` (see test/support/fake_clock.dart)
//      and `advance()` / `set()` it to drive the boundary exactly.
//
// The injection idiom mirrors how the rest of the backend already takes
// its temporal knobs as constructor parameters (e.g. RepositoryState's
// injected durations, GitDirWatcher's injected debounce): a migrated
// class accepts an optional `Clock clock = const SystemClock()`, or — for
// process-wide singletons — exposes a `@visibleForTesting` settable clock
// field. Either way the default is the real clock and no consumer needs
// to change.
//
// Deliberately dependency-free: a ~30-line local abstraction rather than
// `package:clock`, so nothing new enters the dependency graph. Wall-clock
// `now()` is the only primitive every current site needs; no monotonic
// elapsed accessor is exposed until a site genuinely requires one (none
// yet — the TTL/retention sites all compare wall-clock instants).
//
// FUTURE TTLs: adopt this seam instead of re-hardwiring `DateTime.now()`.
// Take a `Clock`, default it to `const SystemClock()`, read `clock.now()`.
// That keeps the seam the path of least resistance and stops the
// untestable-time bug class from growing back.

/// A source of the current wall-clock instant.
///
/// Production code uses [SystemClock] (the default everywhere). Tests
/// inject a fake so freshness/retention boundaries are deterministic.
abstract class Clock {
  const Clock();

  /// The current instant. Production reads the real wall clock; a fake
  /// returns whatever instant the test set.
  DateTime now();
}

/// The production clock: `now()` is exactly `DateTime.now()`.
///
/// `const` so it can be a zero-cost default constructor argument
/// (`Clock clock = const SystemClock()`), guaranteeing the migrated code
/// behaves identically to the pre-seam `DateTime.now()` code path.
class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
