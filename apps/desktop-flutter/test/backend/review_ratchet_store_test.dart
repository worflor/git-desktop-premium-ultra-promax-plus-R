// Concurrency regression test for the claim-outcome ratchet *store*.
//
// The store's observe path is a load → mutate → persist read-modify-write.
// Without serialisation, two findings actioned in rapid succession each load
// the pre-observation state and the second persist clobbers the first's
// observation — one (or more) observations silently lost. `recordObservation`
// runs the whole RMW under a single-writer lock; these tests fire many
// concurrent observations and assert that none are lost.
//
// Hermetic when run with GDPU_DATA_DIR pointed at a temp dir; otherwise it
// resets a uniquely-named test repo's ratchet to empty in setUp/tearDown so it
// never disturbs the developer's real ratchets.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/review_logos.dart';
import 'package:git_desktop/backend/review_ratchet.dart';
import 'package:git_desktop/backend/review_ratchet_store.dart';

ClaimShape _shape({double grounding = 0.5}) => ClaimShape(
      grounding: grounding,
      verifiability: 1.0,
      reach: 0.5,
      coherence: 0.5,
      symbolCount: 2,
      textLength: 128,
    );

void main() {
  // A path that won't collide with a real repo, so the store's FNV-keyed file
  // is exclusive to this test.
  const testRepo = '__ratchet_store_concurrency_test__/repo';

  setUp(() => ReviewRatchetStore.persist(testRepo, ClaimOutcomeRatchet()));
  tearDown(() => ReviewRatchetStore.persist(testRepo, ClaimOutcomeRatchet()));

  test('concurrent same-shape observations are all recorded', () async {
    const n = 25;
    // Fire every observation WITHOUT awaiting in between — this is exactly the
    // interleaving window the bare load+persist lost writes in. Each call
    // enqueues on the store's single-writer lock and runs its RMW in turn.
    final futures = <Future<void>>[
      for (var i = 0; i < n; i++)
        ReviewRatchetStore.recordObservation(
          testRepo,
          (r) => r.observe(shape: _shape(), verified: i.isEven),
        ),
    ];
    await Future.wait(futures);

    final loaded = await ReviewRatchetStore.load(testRepo);
    expect(
      loaded.totalObservations,
      n,
      reason: 'all $n observations must survive the concurrent RMW; a lower '
          'count means a load/persist race dropped some',
    );
  });

  test('concurrent distinct-shape observations each survive', () async {
    const n = 16;
    final futures = <Future<void>>[
      for (var i = 0; i < n; i++)
        ReviewRatchetStore.recordObservation(
          testRepo,
          // Distinct grounding per call → distinct shape buckets; the race
          // drops whole-ratchet writes, so totalObservations is the invariant.
          (r) => r.observe(shape: _shape(grounding: i / n), verified: true),
        ),
    ];
    await Future.wait(futures);

    final loaded = await ReviewRatchetStore.load(testRepo);
    expect(loaded.totalObservations, n);
  });
}
