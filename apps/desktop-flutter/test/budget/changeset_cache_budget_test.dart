// Cluster-cache invalidation budget for ChangesetController.
//
// docs/architecture/wiring-redundancy-audit.md, Tier 1 finding #3:
// "`effectiveMatrix`/`logosEngine` get fresh identities every frame,
// defeating the `identical()`-keyed `_clustersFor` cache → O(n^2)
// `clusterFiles` per frame when spectral coupling is warm ... `withSpectral`
// ... always allocate[s]." That finding predates the ChangesetController
// extraction (see MEMORY: "Changeset controller ... build() no longer
// orchestrates"), but the same failure mode lives on inside the controller:
// `_fuse()` (changeset_controller.dart) increments `couplingVersion`
// UNCONDITIONALLY on every call, and `_maybeDeriveClusters` folds
// `couplingVersion` into `_clusterKey`. A coupling matrix arriving with a
// new object identity — even when its CONTENT is bit-identical to the one
// already fused — therefore forces a full cluster re-derivation.
//
// `clusterCacheMisses` (changeset_controller.dart, @visibleForTesting) counts
// exactly those re-derivations. This file turns the audit finding into an
// assertable, deterministic (no wall-clock) contract: a content-identical
// coupling matrix arriving with a fresh identity should NOT cost a cluster
// cache miss. Per the task spec, if the controller still invalidates on
// identity alone (the bug is still live), this test is left FAILING with a
// reason quoting the audit — the controller is NOT touched beyond the one
// counter field.
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/features/changes/changeset_controller.dart';

import '../support/scratch_repo.dart';

/// Waits until [controller] stops firing `notifyListeners()` for [quiet],
/// up to [timeout]. `update()`'s async chain (weights + per-file flow
/// analysis, each hopping to a real `Isolate.run`) genuinely waits on OS
/// isolate-spawn latency — `pumpEventQueue()`'s fixed 20 event-loop turns is
/// not a reliable proxy for that, so this polls with real delays instead.
/// Not a wall-clock ASSERTION (nothing here is timed and graded) — purely
/// synchronization so the counters below are read only once the controller
/// has genuinely settled.
Future<void> _settle(
  ChangesetController controller, {
  Duration quiet = const Duration(milliseconds: 40),
  Duration timeout = const Duration(seconds: 20),
}) async {
  final sw = Stopwatch()..start();
  var notifications = 0;
  void listener() => notifications++;
  controller.addListener(listener);
  try {
    var lastSeen = -1;
    var stableSince = DateTime.now();
    while (sw.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (notifications != lastSeen) {
        lastSeen = notifications;
        stableSince = DateTime.now();
      } else if (notifications > 0 &&
          DateTime.now().difference(stableSince) >= quiet) {
        // At least one notification fired, and none since — settled.
        return;
      }
    }
  } finally {
    controller.removeListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChangesetController cluster-cache misses', () {
    test(
        'a content-identical coupling matrix with a NEW object identity '
        'should not cost another cluster-cache miss '
        '(wiring-redundancy-audit.md Tier 1 #3)', () async {
      final repo = await ScratchRepo.create(name: 'changeset_cache_budget');
      addTearDown(repo.dispose);
      await repo.writeFile('a.txt', 'a\n');
      await repo.writeFile('b.txt', 'b\n');
      await repo.commitAll('seed a.txt + b.txt');

      final controller = ChangesetController();
      addTearDown(controller.dispose);

      const paths = ['a.txt', 'b.txt'];

      // Two separate FileCouplingMatrix instances built from IDENTICAL
      // constructor arguments — same headHash, same commitsAnalyzed, same
      // jaccard map content — but never `identical()` to one another
      // (the factory constructor always allocates fresh CSR arrays). This
      // is exactly the "fresh identity, same content" shape the audit
      // describes for `withSpectral`, reproduced here at the matrix-input
      // boundary rather than requiring a live spectral overlay pass (which
      // needs real file reads + an isolate hop) — the root cause inside
      // `_fuse()` is identical either way: `couplingVersion` bumps on
      // object-identity change, not content change.
      FileCouplingMatrix freshMatrix() => FileCouplingMatrix(
            jaccard: const {
              'a.txt': {'b.txt': 0.5},
            },
            headHash: 'deadbeef',
            commitsAnalyzed: 3,
          );

      // 1) Establish a settled baseline with no coupling matrix yet.
      controller.update(
        repoPath: repo.dir.path,
        paths: paths,
        couplingMatrix: null,
        statsVolatility: null,
        statsIntegrity: null,
      );
      await _settle(controller);
      final missesAfterNull = controller.clusterCacheMisses;
      expect(missesAfterNull, 1,
          reason: 'the first-ever derivation is always a genuine miss — '
              'there is no prior _clusterKey to compare against.');

      // 2) A real coupling matrix arrives for the first time — a genuine
      // content change (null -> populated), so a miss here is legitimate.
      final matrixB = freshMatrix();
      controller.update(
        repoPath: repo.dir.path,
        paths: paths,
        couplingMatrix: matrixB,
        statsVolatility: null,
        statsIntegrity: null,
      );
      await _settle(controller);
      final missesAfterB = controller.clusterCacheMisses;
      expect(missesAfterB, missesAfterNull + 1,
          reason: 'matrix went from absent to present — real content '
              'change, one legitimate additional miss.');
      final clustersAfterB = controller.clusters;

      // 3) A SECOND matrix instance arrives — bit-identical content to
      // matrixB, but a different object. Nothing about the changeset
      // actually changed. This should be a no-op for the cluster cache.
      final matrixC = freshMatrix();
      expect(identical(matrixB, matrixC), isFalse,
          reason: 'sanity: these must be two distinct objects for the '
              'identity-vs-content distinction to mean anything.');
      controller.update(
        repoPath: repo.dir.path,
        paths: paths,
        couplingMatrix: matrixC,
        statsVolatility: null,
        statsIntegrity: null,
      );
      await _settle(controller);
      final missesAfterC = controller.clusterCacheMisses;

      // The clusters produced from matrixC are content-identical to the
      // ones already produced from matrixB — proving any recompute here is
      // wasted work, not a correctness fix.
      expect(controller.clusters.byPath, clustersAfterB.byPath,
          reason: 'matrixB and matrixC are content-identical, so the '
              'clustering output must be identical regardless of whether '
              'a recompute ran.');
      expect(controller.clusters.orderedPaths, clustersAfterB.orderedPaths);

      expect(missesAfterC, missesAfterB,
          reason:
              'wiring-redundancy-audit.md Tier 1 #3: a coupling matrix that '
              'is CONTENT-identical to the one already fused, but arrives '
              'under a new object identity, must not cost another cluster '
              'cache miss. ChangesetController._fuse() currently bumps '
              'couplingVersion unconditionally on every call (it never '
              'compares the new effectiveMatrix\'s content against the '
              'previous one), and _maybeDeriveClusters folds couplingVersion '
              'into _clusterKey — so an upstream producer that hands the '
              'controller a fresh-but-equal FileCouplingMatrix (exactly '
              'what withSpectral() does on every _fuse() call once spectral '
              'coupling is warm) forces a full clusterFiles re-derivation '
              'for no output change. If this assertion now passes, the live '
              'inefficiency was fixed: couplingVersion (or effectiveMatrix '
              'itself) started gating on content, not identity.');
    });

    test(
        'a coupling matrix with the SAME headHash but DIFFERENT content MUST '
        'invalidate the cluster cache (content key, not head key)', () async {
      // The dual of the test above, and a regression guard for an
      // over-correction: keying the cluster cache on the matrix's `headHash`
      // (the git HEAD) alone is TOO COARSE. The same HEAD legitimately
      // produces different coupling content across refreshes — a deeper log
      // walk changing `commitsAnalyzed`, merged shadow-coupling, or changed
      // jaccard edges. If the cache key doesn't move when the CONTENT moves,
      // `_maybeDeriveClusters` returns early and the changes view keeps
      // clusters derived from the STALE matrix. Here two matrices share a
      // headHash but differ in their jaccard edges AND commit depth; the
      // second must cost a real miss (a re-derivation), or clustering is
      // stale. This passes only because the key is `effectiveMatrix
      // .contentHash` (fingerprints the CSR edge data), not `headHash`.
      final repo = await ScratchRepo.create(name: 'changeset_cache_content');
      addTearDown(repo.dispose);
      await repo.writeFile('a.txt', 'a\n');
      await repo.writeFile('b.txt', 'b\n');
      await repo.writeFile('c.txt', 'c\n');
      await repo.commitAll('seed a/b/c');

      final controller = ChangesetController();
      addTearDown(controller.dispose);
      const paths = ['a.txt', 'b.txt', 'c.txt'];

      // Sanity: the two matrices really do share a headHash while differing
      // in content — so a headHash-only key would (wrongly) collide them.
      final weak = FileCouplingMatrix(
        jaccard: const {
          'a.txt': {'b.txt': 0.1},
        },
        headHash: 'samehead',
        commitsAnalyzed: 3,
      );
      final strong = FileCouplingMatrix(
        jaccard: const {
          'a.txt': {'b.txt': 0.9, 'c.txt': 0.8},
          'b.txt': {'c.txt': 0.7},
        },
        headHash: 'samehead',
        commitsAnalyzed: 40,
      );
      expect(weak.headHash, strong.headHash,
          reason: 'the whole point: identical HEAD, different content.');
      expect(weak.contentHash, isNot(strong.contentHash),
          reason: 'contentHash must distinguish different edge data even at '
              'the same headHash — otherwise the cluster cache cannot.');

      controller.update(
        repoPath: repo.dir.path,
        paths: paths,
        couplingMatrix: weak,
        statsVolatility: null,
        statsIntegrity: null,
      );
      await _settle(controller);
      final missesAfterWeak = controller.clusterCacheMisses;

      controller.update(
        repoPath: repo.dir.path,
        paths: paths,
        couplingMatrix: strong,
        statsVolatility: null,
        statsIntegrity: null,
      );
      await _settle(controller);

      expect(controller.clusterCacheMisses, missesAfterWeak + 1,
          reason: 'a same-HEAD matrix with materially different coupling '
              'edges + commit depth changed what clusterFiles consumes, so it '
              'MUST re-derive — a headHash-only key would have skipped this '
              'and left the changes view showing stale clusters.');
    });
  });
}
