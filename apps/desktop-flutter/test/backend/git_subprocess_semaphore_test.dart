// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';

void main() {
  test('production git subprocess cap preserves parallel probe headroom', () {
    expect(gitSubprocessMaxConcurrency, greaterThan(4));
  });

  test('squash probes leave a permit for foreground git work', () {
    expect(squashProbeMaxConcurrency, greaterThan(0));
    expect(squashProbeMaxConcurrency, lessThan(gitSubprocessMaxConcurrency));
  });

  test('GitSubprocessSemaphore reserves released permits for queued waiters',
      () async {
    final semaphore = GitSubprocessSemaphore(1);

    await semaphore.acquire();
    expect(semaphore.activeCount, 1);
    expect(semaphore.queuedCount, 0);

    var waiterStarted = false;
    final waiter = semaphore.acquire().then((_) {
      waiterStarted = true;
    });
    expect(semaphore.activeCount, 1);
    expect(semaphore.queuedCount, 1);

    semaphore.release();
    expect(semaphore.activeCount, 1);
    expect(semaphore.queuedCount, 0);

    await waiter;
    expect(waiterStarted, isTrue);
    expect(semaphore.activeCount, 1);

    semaphore.release();
    expect(semaphore.activeCount, 0);
    expect(semaphore.queuedCount, 0);
  });

  test('GitSubprocessSemaphore rejects over-release', () {
    final semaphore = GitSubprocessSemaphore(1);
    expect(semaphore.release, throwsStateError);
  });

  test('GitConcurrencyController holds at the ceiling under headroom, shrinks '
      'under contention', () {
    final c = GitConcurrencyController(8); // ceiling = initial = 8 (the rail)
    // Latency pinned at the floor (no contention) — the limit must NOT climb
    // above the safety ceiling; going past the rail is unvalidated.
    for (var i = 0; i < 120; i++) {
      c.observe(const Duration(microseconds: 100));
    }
    expect(c.limit, 8); // held at the rail

    // Sustained contention: latency at 5× the floor (well past the ρ=½
    // set-point of 2×) — the limit must contract below the ceiling.
    for (var i = 0; i < 120; i++) {
      c.observe(const Duration(microseconds: 500));
    }
    expect(c.limit, lessThan(8));
    expect(c.limit, greaterThanOrEqualTo(1));
  });

  test('GitConcurrencyController recovers toward the ceiling on release nudges',
      () {
    final c = GitConcurrencyController(8);
    // Establish a low uncontended floor, then depress under sustained
    // contention (8× the floor).
    c.observe(const Duration(microseconds: 100));
    for (var i = 0; i < 200; i++) {
      c.observe(const Duration(microseconds: 800));
    }
    final depressed = c.limit;
    expect(depressed, lessThan(8));

    // Ordinary traffic (recover nudges only, no latency observed) must lift the
    // limit back to the rail — the no-recovery-path bug this guards against.
    for (var i = 0; i < 400; i++) {
      c.recover();
    }
    expect(c.limit, greaterThan(depressed));
    expect(c.limit, lessThanOrEqualTo(8));
  });

  test('GitSubprocessSemaphore drains waiters when the controller raises the '
      'limit', () async {
    final s = GitSubprocessSemaphore(1, controller: GitConcurrencyController(8));
    await s.acquire(); // active 1, at the initial max of 1
    var w1 = false, w2 = false;
    final f1 = s.acquire().then((_) => w1 = true);
    final f2 = s.acquire().then((_) => w2 = true);
    expect(s.queuedCount, 2);

    // A fast observed call lifts the controller's derived limit above 1, so
    // the queued waiters get permits instead of starving at the stale cap.
    s.observe(const Duration(microseconds: 100));
    s.release();
    await Future.wait([f1, f2]);
    expect(w1 && w2, isTrue);
  });
}
