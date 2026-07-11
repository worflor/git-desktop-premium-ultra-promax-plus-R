// fake_clock.dart — the test-side companion to lib/backend/clock.dart.
//
// A [FakeClock] returns a fixed instant that the test controls via
// [set] / [advance]. Because every migrated TTL/retention site reads its
// time through `Clock.now()` (never a real `Timer`/`Stopwatch`), driving
// this fake is enough to hit a freshness boundary EXACTLY — no real
// sleeping, no wall-clock flakiness.
//
// Only reach for `package:fake_async` when a site awaits a real `Timer`;
// the wall-clock caches here just re-read `now()`, so a plain instant
// source is the right, lighter tool.

import 'package:git_desktop/backend/clock.dart';

/// A [Clock] whose `now()` is whatever the test last set. Not `const`:
/// its instant is mutable state the test advances.
class FakeClock extends Clock {
  FakeClock([DateTime? start])
      : _now = start ?? DateTime.utc(2026, 1, 1, 0, 0, 0);

  DateTime _now;

  @override
  DateTime now() => _now;

  /// Jump the clock to an absolute instant.
  void set(DateTime instant) => _now = instant;

  /// Move the clock forward (or backward, with a negative duration) by
  /// [delta]. The typical way to step across a TTL boundary.
  void advance(Duration delta) => _now = _now.add(delta);
}
