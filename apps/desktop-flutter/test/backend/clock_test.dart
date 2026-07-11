// Unit test for the clock seam itself: SystemClock tracks the wall clock,
// FakeClock is fully controllable and does not drift.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/clock.dart';

import '../support/fake_clock.dart';

void main() {
  test('SystemClock.now() tracks the real wall clock', () {
    const clock = SystemClock();
    final before = DateTime.now();
    final n = clock.now();
    final after = DateTime.now();
    // now() lands within the bracketing wall-clock reads.
    expect(n.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
    expect(n.isAfter(after.add(const Duration(seconds: 1))), isFalse);
  });

  test('SystemClock is const-constructible (zero-cost default arg)', () {
    expect(identical(const SystemClock(), const SystemClock()), isTrue);
  });

  test('FakeClock returns exactly what was set and never drifts', () {
    final t = DateTime.utc(2026, 5, 5, 5, 5, 5);
    final clock = FakeClock(t);
    expect(clock.now(), t);
    // Reading twice returns the identical instant — no wall-clock leak.
    expect(clock.now(), clock.now());
  });

  test('FakeClock.advance moves forward and backward', () {
    final t = DateTime.utc(2026, 1, 1);
    final clock = FakeClock(t);
    clock.advance(const Duration(hours: 3));
    expect(clock.now(), t.add(const Duration(hours: 3)));
    clock.advance(const Duration(hours: -1));
    expect(clock.now(), t.add(const Duration(hours: 2)));
  });

  test('FakeClock.set jumps to an absolute instant', () {
    final clock = FakeClock(DateTime.utc(2026, 1, 1));
    final target = DateTime.utc(2030, 12, 31, 23, 59, 59);
    clock.set(target);
    expect(clock.now(), target);
  });

  test('FakeClock default start is deterministic', () {
    expect(FakeClock().now(), DateTime.utc(2026, 1, 1, 0, 0, 0));
  });
}
