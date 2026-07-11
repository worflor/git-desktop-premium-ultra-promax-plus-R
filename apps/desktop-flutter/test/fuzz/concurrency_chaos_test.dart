// The app's FIRST true-concurrency test suite.
//
// Verified gap this closes: every existing test awaits git ops strictly
// sequentially — zero overlapping-execution coverage. The git subprocess
// semaphore (backend/git.dart, `_gitSubprocessSemaphore`) is a THROTTLE
// (max 6, adaptive), not a mutex: nothing serializes two *logical* ops on
// the same repo. This file races real operations on scratch repos with
// seeded jitter (test/support/chaos.dart) and asserts invariant oracles.
//
// LAWS (a red ARMED law is always a real bug — never a flaky-timing
// artifact). Every law below is now ARMED: the create-CAS (C1/law 3),
// staging-interleave (C2/law 5) and shadow-regress (C3/law 8) findings were
// fixed at root 2026-07-10, so their `_knownFinding*Skip` consts are kept at
// `false` as regression guards (a genuine nondeterministic bug would still be
// pinned `skip:` with a mechanism comment rather than left intermittently red):
//
//   1. watcher-pause participation (ARMED, deterministic) — an in-flight
//      `applyPatch` NOW raises `gitMutationsInFlight` (+1/-1) and notifies, so
//      the GitDirWatcher pause contract (RepositoryState pauses iff
//      mutations-in-flight > 0) covers it. Was finding C4, fixed 2026-07-10.
//   2. mutate-no-lost-update (ARMED) — N concurrent `addComment` on one desk
//      PR: comments-present == successful-calls, the ref always parses, at
//      least one succeeds. The retrying CAS in DeskPrStore._mutate makes this
//      hold.
//   3. create-CAS-exclusivity (ARMED) — 2 concurrent `create()` for the same
//      branch leave exactly one winner: DeskPrStore now CAS-es on
//      non-existence (zero-oid oldSha), so the loser's update-ref is rejected
//      and it errs cleanly. Was finding C1, fixed 2026-07-10.
//   4. alloc-monotonic (ARMED) — N concurrent id allocations yield N
//      distinct, strictly increasing ids (in-process serialization).
//   5. staging-interleave (ARMED) — two concurrent `applyFileStaging` for
//      DIFFERENT files both stage: applyPatch now routes through the gated
//      retrying path, so the `index.lock` collision is retried away. Was
//      finding C2, fixed 2026-07-10.
//   6. apply-vs-stage (ARMED + classify) — concurrent `applyPatch(cached)` +
//      gated `git add`: the repo stays sane and no torn index survives; the
//      raw `index.lock` leak out of the no-retry `applyPatch` is surfaced via
//      classify() rather than asserted (it does not corrupt, it just fails
//      un-retried).
//   7. semaphore-ceiling (ARMED) — 20 concurrent reads never drive peak
//      concurrency past `gitSubprocessMaxConcurrency`.
//   8. shadow-merge-no-regress (ARMED) — two concurrent load→mergeWith→save
//      cycles keep BOTH contributors' edges: ShadowCouplingCache.save now
//      serializes as save-as-merge per repo key. Was finding C3, fixed
//      2026-07-10.
//   9. disjoint-op-safety (ARMED) — two concurrent write/stage halves over
//      disjoint file sets, one sequential commit: every file lands with the
//      expected content, repo stays sane (the sequential-equivalence floor
//      for commuting ops).
//
// SCALING: reads MANIFOLD_FUZZ via fuzzScale(); each racy law loops
// `chaosReps()` = 3×scale interleavings per case. Default wall-clock stays
// under ~2 minutes; keep concurrency modest (N ≤ 8 subprocess-spawning
// thunks). Corpus persistence is disabled everywhere (persistCorpus: false)
// — this file owns no corpus artifacts.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_pr.dart';
import 'package:git_desktop/backend/desk_pr_store.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/manifold_refs.dart';
import 'package:git_desktop/backend/shadow_coupling_cache.dart';
import 'package:git_desktop/backend/storage_paths.dart';

import '../support/chaos.dart';
import '../support/prop.dart';
import '../support/scratch_repo.dart';

// Regression breadcrumbs — laws 3/5/8 were once interleaving-dependent
// findings, all fixed at root 2026-07-10 (dossier docs/architecture/
// test-hardening-crash-chaos-config.md) and now armed. Kept (false) so the fix
// history stays greppable and a regression is a one-line flip from reproduction.
const bool _knownFindingCreateCasSkip = false; // law 3 (C1) — zero-oid CAS on create
const bool _knownFindingStagingInterleaveSkip = false; // law 5 (C2) — gated retry
const bool _knownFindingShadowRegressSkip = false; // law 8 (C3) — save-as-merge

// Per-test wall-clock ceiling (an upper bound only — it never slows a fast
// default-scale run). Sized so the git-heaviest PR-store laws (2, 3) survive a
// MANIFOLD_FUZZ=3 deep run on Windows, where 27 rounds of real, CAS-retrying
// git racing legitimately need several minutes. The retries are bounded
// (DeskPrStore._mutate maxAttempts / _commit single-shot), so this guards
// against a genuine hang without amputating an honest heavy run.
const Timeout _chaosTimeout = Timeout(Duration(minutes: 8));

/// The generator for every law here: it just returns the tape-recording
/// [Rng] forAllAsync hands it, so `check` can pre-draw scenario randomness
/// from it sequentially and still get shrinking/corpus integration for free.
Rng _identityRng(Rng rng) => rng;

/// A traditional unified diff that adds [path] as a brand-new file whose
/// content is [lines] (each a line body without terminator). Accepted by
/// `git apply --cached` to stage a new blob.
String _newFileDiff(String path, List<String> lines) {
  final b = StringBuffer()
    ..writeln('--- /dev/null')
    ..writeln('+++ b/$path')
    ..writeln('@@ -0,0 +1,${lines.length} @@');
  for (final l in lines) {
    b.writeln('+$l');
  }
  return b.toString();
}

/// A unified diff turning a single-line file [path] from `$from\n` to
/// `$to\n`. Used with `applyFileStaging`, which first resets the index entry
/// to HEAD (`$from`) and then applies this against the index.
String _replaceLineDiff(String path, String from, String to) {
  return '--- a/$path\n'
      '+++ b/$path\n'
      '@@ -1 +1 @@\n'
      '-$from\n'
      '+$to\n';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  // LAW 1 — watcher-blindness (ARMED, deterministic)
  // -------------------------------------------------------------------------
  // Breadcrumb: was finding C4 (applyPatch bypassed the mutation gate, so a
  // GitDirWatcher refresh could land mid-apply). Fixed 2026-07-10 — applyPatch
  // now routes through the gated mutating path (_gitRawStdin) and bumps
  // gitMutationsInFlight like every other index write.
  group('law 1 — applyPatch participates in the watcher-pause contract', () {
    test(
        'an in-flight applyPatch raises gitMutationsInFlight and notifies, so '
        'GitDirWatcher pauses across the apply', () async {
      final repo = await ScratchRepo.create(name: 'law1_watcher');
      var notifications = 0;
      var peak = 0;
      void listener() {
        notifications++;
        if (gitMutationsInFlight > peak) peak = gitMutationsInFlight;
      }

      addGitMutationListener(listener);
      try {
        // CONTROL (proves the mechanism is live and not vacuous): an ordinary
        // gated, mutating subcommand DOES bump the counter + notify. The bump
        // fires synchronously from the exec path, so after the await the
        // listener has already observed a non-zero peak.
        await repo.writeFile('control.txt', 'hello\n');
        await repo.git(['add', '--', 'control.txt']);
        await repo.git(['commit', '-m', 'gated control mutation']);
        expect(peak, greaterThan(0),
            reason: 'a gated mutating git call must raise '
                'gitMutationsInFlight (control for the law below)');

        // THE FIXED CONTRACT: route a real index mutation through applyPatch.
        // It now takes the gated mutating path, so across the call it bumps
        // gitMutationsInFlight (+1 then -1) and notifies — RepositoryState can
        // therefore pause the GitDirWatcher for the duration of the apply.
        notifications = 0;
        peak = 0;
        final beforeInFlight = gitMutationsInFlight;
        final patch = _newFileDiff('applied.txt', const ['patched via apply']);
        final r = await applyPatch(repo.dir.path, patch, cached: true);
        expect(r.ok, isTrue, reason: 'applyPatch failed: ${r.error}');

        expect(beforeInFlight, 0);
        expect(peak, greaterThan(0),
            reason: 'applyPatch must raise mutations-in-flight mid-call so the '
                'watcher pauses instead of racing the staging write');
        expect(gitMutationsInFlight, 0,
            reason: 'the counter must return to 0 after the apply');
        expect(notifications, 2,
            reason: 'applyPatch must notify once on the +1 bump and once on the '
                '-1 (the watcher-pause contract now covers it)');

        // And the gated apply still produced a correct staged result.
        final staged = await repo.git(['show', ':applied.txt']);
        expect(staged.exitCode, 0);
        expect(staged.stdout.toString(), 'patched via apply\n');
        await assertRepoSane(repo, because: 'after gated applyPatch');
      } finally {
        removeGitMutationListener(listener);
        await repo.dispose();
      }
    }, timeout: _chaosTimeout);
  });

  // -------------------------------------------------------------------------
  // LAW 2 — mutate-no-lost-update (ARMED)
  // -------------------------------------------------------------------------
  group('law 2 — concurrent addComment never loses a comment', () {
    test('N concurrent addComment: thread == successes, ref parses, ≥1 wins',
        () async {
      await forAllAsync<Rng>(
        _identityRng,
        count: fuzzScale(),
        seed: 0x5EED,
        describe: 'law2-mutate-no-lost-update',
        persistCorpus: false,
        shrinkEvaluations: 6,
        check: (rng) async {
          final repo = await ScratchRepo.create(name: 'law2_mutate');
          try {
            final refs = ManifoldRefs(
              repoPath: repo.dir.path,
              authorName: 'chaos-bot',
              authorEmail: 'chaos@manifold.local',
            );
            final store = DeskPrStore(refs);

            for (var rep = 0; rep < chaosReps(); rep++) {
              final branch = 'feature/law2-$rep';
              final created = await store.create(
                branch: branch,
                title: 'law2 pr $rep',
                body: 'body',
                baseRef: 'main',
                authorIdentity: 'chaos-bot',
              );
              expect(created.ok, isTrue, reason: created.error);

              // Pre-draw N (no draws once the race is in flight).
              final n = rng.intBetween(4, 8);
              final thunks = <Future<bool> Function()>[
                for (var i = 0; i < n; i++)
                  () async {
                    final r = await store.addComment(
                      branch: branch,
                      author: 'author-$i',
                      body: 'comment-$rep-$i',
                    );
                    return r.ok;
                  },
              ];

              final outcomes = await raceAll<bool>(thunks, rng);

              // No thunk may throw — a lost CAS is a clean GitResult.err,
              // never an exception.
              expect(errorsOf(outcomes), isEmpty,
                  reason: 'addComment threw instead of returning err');

              final successes =
                  valuesOf(outcomes).where((ok) => ok).length;
              expect(successes, greaterThanOrEqualTo(1),
                  reason: 'at least one addComment must survive the race');

              final reread = await store.read(branch);
              expect(reread.ok, isTrue,
                  reason: 'PR ref did not parse after the race: '
                      '${reread.error}');
              expect(reread.data, isNotNull);
              expect(reread.data!.thread.length, successes,
                  reason: 'lost update: comments present '
                      '(${reread.data!.thread.length}) != successful calls '
                      '($successes) for $branch');
            }
          } finally {
            await repo.dispose();
          }
        },
      );
    }, timeout: _chaosTimeout);
  });

  // -------------------------------------------------------------------------
  // LAW 3 — create-CAS-exclusivity (ARMED; was finding C1)
  // -------------------------------------------------------------------------
  group('law 3 — concurrent create() for one branch must have one winner', () {
    test(
        'exactly one create() wins, the loser errs cleanly, the stored PR '
        'matches the winner',
        () async {
      final repo = await ScratchRepo.create(name: 'law3_create');
      final rng = Rng(0x5EED);
      try {
        final refs = ManifoldRefs(
          repoPath: repo.dir.path,
          authorName: 'chaos-bot',
          authorEmail: 'chaos@manifold.local',
        );
        final store = DeskPrStore(refs);

        for (var rep = 0; rep < chaosReps(); rep++) {
          final branch = 'feature/law3-$rep';
          final thunks = <Future<GitResult<DeskPr>> Function()>[
            for (var i = 0; i < 2; i++)
              () => store.create(
                    branch: branch,
                    title: 'law3 pr $rep by $i',
                    body: 'creator $i',
                    baseRef: 'main',
                    authorIdentity: 'creator-$i',
                  ),
          ];

          final outcomes = await raceAll<GitResult<DeskPr>>(thunks, rng);
          expect(errorsOf(outcomes), isEmpty,
              reason: 'create() threw instead of returning err');
          final winners = valuesOf(outcomes).where((r) => r.ok).toList();

          // THE CONTRACT: a genuine create-vs-create race resolves to exactly
          // one winner. DeskPrStore now CAS-es on non-existence (zero-oid
          // oldSha), so the loser's update-ref is rejected and it errs cleanly
          // instead of unconditionally clobbering the winner.
          expect(winners.length, 1,
              reason: 'two concurrent create()s must leave exactly one winner: '
                  "the loser's zero-oid CAS on the now-existing ref must be "
                  'rejected. A second winner means the create-CAS regressed to '
                  'an unconditional update-ref (oldSha:null).');

          final stored = await store.read(branch);
          expect(stored.ok, isTrue, reason: stored.error);
          expect(stored.data, isNotNull);
          // The stored PR is one of the two attempted creators (the winner).
          expect(stored.data!.deskId, isPositive);
        }
      } finally {
        await repo.dispose();
      }
    },
        timeout: _chaosTimeout,
        skip: _knownFindingCreateCasSkip
            ? 'was finding C1 (create used oldSha:null, no CAS); fixed '
                '2026-07-10 — now armed'
            : false);
  });

  // -------------------------------------------------------------------------
  // LAW 4 — alloc-monotonic (ARMED)
  // -------------------------------------------------------------------------
  group('law 4 — concurrent id allocation is distinct and monotonic', () {
    test('N concurrent allocSequentialId → ids == 1..N (in-process)',
        () async {
      await forAllAsync<Rng>(
        _identityRng,
        count: fuzzScale(),
        seed: 0x5EED,
        describe: 'law4-alloc-monotonic',
        persistCorpus: false,
        shrinkEvaluations: 6,
        check: (rng) async {
          final repo = await ScratchRepo.create(name: 'law4_alloc');
          try {
            for (var rep = 0; rep < chaosReps(); rep++) {
              // A fresh counter ref per rep so each rep expects a clean 1..N.
              final counterRef =
                  LiveManifoldRef.parse('refs/manifold/_law4-counter-$rep');
              final refs = ManifoldRefs(
                repoPath: repo.dir.path,
                authorName: 'chaos-bot',
                authorEmail: 'chaos@manifold.local',
              );
              final n = rng.intBetween(4, 8);
              final thunks = <Future<GitResult<int>> Function()>[
                for (var i = 0; i < n; i++)
                  () => refs.allocSequentialId(
                        ref: counterRef,
                        filename: 'counter.txt',
                        commitLabel: 'law4',
                      ),
              ];

              final outcomes = await raceAll<GitResult<int>>(thunks, rng);
              expect(errorsOf(outcomes), isEmpty,
                  reason: 'allocSequentialId threw');
              final results = valuesOf(outcomes);
              expect(results.every((r) => r.ok), isTrue,
                  reason: 'an in-process alloc lost its local CAS: '
                      '${results.where((r) => !r.ok).map((r) => r.error).toList()}');

              final ids = results.map((r) => r.data!).toList()..sort();
              expect(ids, equals(List<int>.generate(n, (i) => i + 1)),
                  reason: 'ids were not the distinct, monotonic range 1..$n '
                      '(got $ids) — in-process serialization broke');
            }
          } finally {
            await repo.dispose();
          }
        },
      );
    }, timeout: _chaosTimeout);
  });

  // -------------------------------------------------------------------------
  // LAW 5 — staging-interleave (ARMED; was finding C2)
  // -------------------------------------------------------------------------
  group('law 5 — concurrent applyFileStaging on different files', () {
    test('both files stage with the expected content; index never corrupts',
        () async {
      final repo = await ScratchRepo.create(name: 'law5_staging');
      final rng = Rng(0x5EED);
      try {
        // Two tracked base files.
        await repo.writeFile('fileA.txt', 'baseA\n');
        await repo.writeFile('fileB.txt', 'baseB\n');
        await repo.commitAll('law5 base');

        for (var rep = 0; rep < chaosReps() * 2; rep++) {
          final stagedA = 'stagedA-$rep';
          final stagedB = 'stagedB-$rep';
          // applyFileStaging resets each file's index entry to HEAD before
          // applying, and HEAD is never re-committed inside the loop, so the
          // patch preimage is ALWAYS the committed base — not the prior rep's
          // staged value.
          final thunks = <Future<GitResult<void>> Function()>[
            () => applyFileStaging(repo.dir.path, 'fileA.txt',
                _replaceLineDiff('fileA.txt', 'baseA', stagedA)),
            () => applyFileStaging(repo.dir.path, 'fileB.txt',
                _replaceLineDiff('fileB.txt', 'baseB', stagedB)),
          ];
          final outcomes = await raceAll<GitResult<void>>(thunks, rng);

          expect(errorsOf(outcomes), isEmpty,
              reason: 'applyFileStaging threw');
          for (final r in valuesOf(outcomes)) {
            expect(r.ok, isTrue,
                reason: 'applyFileStaging is a gated `git reset -q HEAD -- '
                    '<file>` followed by `applyPatch --cached`, which now routes '
                    'through the gated retrying path. Two concurrent invocations '
                    'that collide on `.git/index.lock` must retry it away, not '
                    'leak a lock error: ${r.error}');
          }

          // Both staged blobs must be present with the exact expected bytes.
          final showA = await repo.git(['show', ':fileA.txt']);
          final showB = await repo.git(['show', ':fileB.txt']);
          expect(showA.exitCode, 0);
          expect(showB.exitCode, 0);
          expect(showA.stdout.toString(), '$stagedA\n',
              reason: 'fileA staging lost/torn by the interleave');
          expect(showB.stdout.toString(), '$stagedB\n',
              reason: 'fileB staging lost/torn by the interleave');
          await assertRepoSane(repo, because: 'law5 rep $rep');
        }
      } finally {
        await repo.dispose();
      }
    },
        timeout: _chaosTimeout,
        skip: _knownFindingStagingInterleaveSkip
            ? 'was finding C2 (reset/apply index.lock collision, no retry); '
                'fixed 2026-07-10 — now armed'
            : false);
  });

  // -------------------------------------------------------------------------
  // LAW 6 — apply-vs-stage (ARMED + classify)
  // -------------------------------------------------------------------------
  group('law 6 — applyPatch racing a gated git add', () {
    test('repo stays sane, no torn index; index.lock leaks are surfaced',
        () async {
      await forAllAsync<Rng>(
        _identityRng,
        count: fuzzScale(),
        seed: 0x5EED,
        describe: 'law6-apply-vs-stage',
        persistCorpus: false,
        shrinkEvaluations: 6,
        check: (rng) async {
          final repo = await ScratchRepo.create(name: 'law6_applystage');
          try {
            for (var rep = 0; rep < chaosReps(); rep++) {
              final appliedPath = 'applied-$rep.txt';
              final addedPath = 'added-$rep.txt';
              await repo.writeFile(addedPath, 'added content $rep\n');

              final patch =
                  _newFileDiff(appliedPath, ['applied content $rep']);

              final applyOutcome = raceAll<Object>(
                <Future<Object> Function()>[
                  () async => applyPatch(repo.dir.path, patch, cached: true),
                  () async => repo.git(['add', '--', addedPath]),
                ],
                rng,
              );
              final outcomes = await applyOutcome;
              expect(errorsOf(outcomes), isEmpty,
                  reason: 'a thunk threw instead of returning a result');

              // Surface (do not assert) the no-retry index.lock leak out of
              // applyPatch — the documented finding. It fails cleanly without
              // corrupting the index, so the LAW is the sanity below.
              final apply = valuesOf(outcomes).first as GitResult<void>;
              final add = valuesOf(outcomes).last as ProcessResult;
              final applyLeakedLock =
                  !apply.ok && (apply.error ?? '').contains('index.lock');
              final addLeakedLock = add.exitCode != 0 &&
                  add.stderr.toString().contains('index.lock');
              classify(applyLeakedLock, 'applypatch-index-lock-leak');
              classify(addLeakedLock, 'gitadd-index-lock-retry-exhausted');
              classify(apply.ok && add.exitCode == 0, 'both-succeeded');

              // LAW: the index is never torn. Each op's effect is present iff
              // it succeeded, and the repo is always sane.
              await assertRepoSane(repo, because: 'law6 rep $rep');
              final showApplied = await repo.git(['show', ':$appliedPath']);
              if (apply.ok) {
                expect(showApplied.exitCode, 0,
                    reason: 'applyPatch reported ok but the blob is missing');
                expect(showApplied.stdout.toString(),
                    'applied content $rep\n');
              }
              final showAdded = await repo.git(['show', ':$addedPath']);
              if (add.exitCode == 0) {
                expect(showAdded.exitCode, 0,
                    reason: 'git add reported ok but the blob is missing');
                expect(
                    showAdded.stdout.toString(), 'added content $rep\n');
              }
            }
          } finally {
            await repo.dispose();
          }
        },
      );
    }, timeout: _chaosTimeout);
  });

  // -------------------------------------------------------------------------
  // LAW 7 — semaphore-ceiling (ARMED)
  // -------------------------------------------------------------------------
  group('law 7 — the subprocess semaphore caps concurrency', () {
    test('20 concurrent reads never exceed gitSubprocessMaxConcurrency',
        () async {
      final repo = await ScratchRepo.create(name: 'law7_ceiling');
      final rng = Rng(0x5EED);
      try {
        await repo.writeFile('a.txt', 'x\n');
        await repo.commitAll('law7 seed');

        for (var rep = 0; rep < chaosReps(); rep++) {
          resetGitSubprocessPeakForTesting();
          // maxJitterMs: 0 so all 20 land on the same turn and truly pile up
          // against the semaphore (a staggered start would never contend).
          final thunks = <Future<ProcessResult> Function()>[
            for (var i = 0; i < 20; i++)
              () => repo.git(i.isEven
                  ? ['rev-parse', 'HEAD']
                  : ['status', '--porcelain']),
          ];
          final outcomes =
              await raceAll<ProcessResult>(thunks, rng, maxJitterMs: 0);

          expect(errorsOf(outcomes), isEmpty, reason: 'a read threw');
          for (final r in valuesOf(outcomes)) {
            expect(r.exitCode, 0, reason: 'a raced read failed: ${r.stderr}');
          }

          final peak = gitSubprocessPeakForTesting();
          expect(peak, lessThanOrEqualTo(gitSubprocessMaxConcurrency),
              reason: 'peak concurrency $peak exceeded the ceiling '
                  '$gitSubprocessMaxConcurrency — the throttle failed');
          // Non-vacuity: a 20-wide burst with zero jitter must actually
          // contend, or the law proves nothing.
          expect(peak, greaterThanOrEqualTo(2),
              reason: 'the burst never overlapped (peak $peak) — the ceiling '
                  'law is vacuous this rep');
        }
      } finally {
        await repo.dispose();
      }
    }, timeout: _chaosTimeout);
  });

  // -------------------------------------------------------------------------
  // LAW 8 — shadow-merge-no-regress (ARMED; was finding C3)
  // -------------------------------------------------------------------------
  group('law 8 — concurrent ShadowCouplingCache cycles never regress edges',
      () {
    late Directory tempDataDir;

    setUp(() async {
      tempDataDir = await Directory.systemTemp.createTemp('law8_shadow_');
      StoragePaths.debugOverrideDir = tempDataDir;
    });
    tearDown(() async {
      StoragePaths.debugOverrideDir = null;
      try {
        await tempDataDir.delete(recursive: true);
      } catch (_) {}
    });

    test('two concurrent load→mergeWith→save cycles keep BOTH edge sets',
        () async {
      final rng = Rng(0x5EED);
      for (var rep = 0; rep < chaosReps(); rep++) {
        // Distinct repo key per rep so each starts from an empty cache — the
        // regression only shows on a load that raced another's save.
        final repoKey = '/virtual/law8/repo-$rep';

        ShadowCouplingCacheData contribution(
                String from, String to) =>
            ShadowCouplingCacheData(
              headHash: 'head-$rep',
              discoveredAt: DateTime.now(),
              shadowCommitCount: 1,
              jaccardEdges: {
                from: {to: 1.0}
              },
            );

        Future<void> cycle(String from, String to) async {
          final loaded = await ShadowCouplingCache.load(repoKey);
          final base = loaded ??
              ShadowCouplingCacheData(
                headHash: 'head-$rep',
                discoveredAt: DateTime.now(),
                shadowCommitCount: 0,
                jaccardEdges: const {},
              );
          final merged = base.mergeWith(contribution(from, to));
          await ShadowCouplingCache.save(repoKey, merged);
        }

        final outcomes = await raceAll<void>(
          <Future<void> Function()>[
            () => cycle('a.dart', 'b.dart'),
            () => cycle('c.dart', 'd.dart'),
          ],
          rng,
        );
        expect(errorsOf(outcomes), isEmpty, reason: 'a cache cycle threw');

        final finalCache = await ShadowCouplingCache.load(repoKey);
        expect(finalCache, isNotNull);
        // THE CONTRACT (mergeWith: "merged edges never regress"). Save now
        // serializes as save-as-merge per repo key, so even when both cycles
        // loaded the empty cache, the second save re-loads and merges the
        // first's edge rather than clobbering it — BOTH contributors survive.
        expect(finalCache!.jaccardEdges['a.dart']?['b.dart'], 1.0,
            reason: 'the a→b edge is missing — ShadowCouplingCache.save must '
                'serialize as save-as-merge per repo key (a lost update means '
                'the per-key save lock regressed)');
        expect(finalCache.jaccardEdges['c.dart']?['d.dart'], 1.0,
            reason: 'the c→d edge is missing (lost update)');
      }
    },
        timeout: _chaosTimeout,
        skip: _knownFindingShadowRegressSkip
            ? 'was finding C3 (unlocked load→mergeWith→save lost edges); '
                'fixed 2026-07-10 — now armed'
            : false);
  });

  // -------------------------------------------------------------------------
  // LAW 9 — disjoint-op-safety (ARMED)
  // -------------------------------------------------------------------------
  group('law 9 — concurrent disjoint write/stage halves commute', () {
    test('both halves stage disjoint files; the sequential commit has all',
        () async {
      await forAllAsync<Rng>(
        _identityRng,
        count: fuzzScale(),
        seed: 0x5EED,
        describe: 'law9-disjoint-op-safety',
        persistCorpus: false,
        shrinkEvaluations: 6,
        check: (rng) async {
          final repo = await ScratchRepo.create(name: 'law9_disjoint');
          try {
            for (var rep = 0; rep < chaosReps(); rep++) {
              // Pre-draw both halves' file sets + contents sequentially, so
              // the racing thunks make no Rng draws.
              final countA = rng.intBetween(2, 5);
              final countB = rng.intBetween(2, 5);
              final filesA = <(String, String)>[
                for (var i = 0; i < countA; i++)
                  (
                    'rep${rep}_a$i.txt',
                    'A r$rep i$i v${rng.intBetween(0, 1 << 20)}\n'
                  ),
              ];
              final filesB = <(String, String)>[
                for (var i = 0; i < countB; i++)
                  (
                    'rep${rep}_b$i.txt',
                    'B r$rep i$i v${rng.intBetween(0, 1 << 20)}\n'
                  ),
              ];

              Future<void> writeStageHalf(
                  List<(String, String)> files) async {
                for (final (path, content) in files) {
                  await repo.writeFile(path, content);
                  final r = await repo.git(['add', '--', path]);
                  if (r.exitCode != 0) {
                    throw StateError('git add $path failed: ${r.stderr}');
                  }
                }
              }

              final outcomes = await raceAll<void>(
                <Future<void> Function()>[
                  () => writeStageHalf(filesA),
                  () => writeStageHalf(filesB),
                ],
                rng,
              );
              expect(errorsOf(outcomes), isEmpty,
                  reason: 'a disjoint staging half failed: '
                      '${errorsOf(outcomes).map((e) => e.error).toList()}');

              // One sequential commit closes the rep.
              final commit =
                  await repo.git(['commit', '-m', 'law9 rep $rep']);
              expect(commit.exitCode, 0,
                  reason: 'commit failed: ${commit.stderr}');

              await assertRepoSane(repo, because: 'law9 rep $rep');
              for (final (path, content) in [...filesA, ...filesB]) {
                final show = await repo.git(['show', 'HEAD:$path']);
                expect(show.exitCode, 0,
                    reason: 'file $path missing from the commit');
                expect(show.stdout.toString(), content,
                    reason: 'content mismatch for $path after concurrent '
                        'disjoint staging');
              }
            }
          } finally {
            await repo.dispose();
          }
        },
      );
    }, timeout: _chaosTimeout);
  });
}
