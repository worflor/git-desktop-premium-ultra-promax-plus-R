// The DETERMINISTIC concurrency suite — the pin-grade upgrade to the chaos
// harness (test/fuzz/concurrency_chaos_test.dart).
//
// The chaos suite races real ops with random jitter, so its findings
// reproduce only probabilistically (~60% on the best one). This suite proves
// the SAME findings with certainty. Every git operation's only yield points
// are its subprocess spawns, and the app owns that boundary
// (`GitSpawn.runOverride` / `startOverride`, lib/backend/git.dart). The
// GitBarrier (test/support/git_barrier.dart) parks a chosen spawn BEFORE its
// real subprocess is created and releases it on command, so the interleaving
// is not sampled — it is CHOSEN. No jitter, no reps, no timing: every law
// here is fully deterministic and pins fail on EVERY run when unskipped.
//
// WHAT THE SEAM SEES (load-bearing, verified against the source): calls that
// route through `runGit`/`applyPatch` (`update-ref`, `commit-tree`,
// `rev-parse`, `cat-file`, `for-each-ref`, `config`, `apply`, `reset`) are
// gate-able. `ManifoldRefs.writeBlob`/`mkTree` call `Process.start` DIRECTLY
// (manifold_refs.dart:229-286), bypassing the seam entirely — the barrier
// cannot gate them, so D2 gates the `update-ref` that DOES pass through.
//
// LAWS (a red ARMED law is a real bug, never a timing artifact). Every law
// below is now ARMED: the D1/D2/D4 findings were fixed at root 2026-07-10 and
// stand as deterministic regression guards (their `_knownFinding*Skip` consts
// are kept at `false` so a regression is a one-line flip from reproduction):
//
//   D1. index.lock retry symmetry — BOTH the gated path (`git add`) and
//       `applyPatch` RETRY a one-shot index.lock and succeed: applyPatch now
//       routes through the gated retrying path (_gitRawStdin). Two armed,
//       symmetric halves. Was finding C2/D1, fixed 2026-07-10.
//   D2. create-CAS exclusivity — two DeskPrStore.create() for one branch,
//       barrier-ordered so the held creator's `update-ref` lands AFTER the
//       other fully created the ref. The late writer's zero-oid CAS on the
//       now-existing ref is rejected: it errs cleanly, the first survives.
//       Was finding C1/D2, fixed 2026-07-10 (ARMED).
//   D3. index-write serialization — while one applyFileStaging child is in
//       flight, the second op cannot even spawn (git.dart's per-repo
//       index-write lock); both stage correctly once released. Replaces the
//       original 6-schedule commutativity enumeration: serial schedules all
//       commuted, but git's index.lock never made the whole RMW atomic, so
//       OVERLAP lost updates (chaos law 5) — overlap is now unrepresentable
//       in-process, and that is the armed law.
//   D4. cross-process CAS — two Isolate.run batches of allocSequentialId
//       against one .git (each isolate = its own git.dart statics = a faithful
//       second app process). The fresh-ref allocation now CAS-es on
//       non-existence (zero-oid via createRef) and a lost CAS retries onto
//       next+1, so all 6 ids are DISTINCT — the clean 1..6 range with no gaps.
//       Was finding C1/D4, fixed 2026-07-10 (ARMED).
//   D5. semaphore escape — an isolate git read completes while a main-isolate
//       runGit call is parked mid-spawn holding a semaphore slot, proving
//       isolate spawns live outside this process's throttle (ARMED
//       documentation, like chaos law 1).
//
// This file uses no randomness (nothing to seed) and no forAllAsync (so no
// corpus). Default wall stays well under ~90s.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_pr.dart';
import 'package:git_desktop/backend/desk_pr_store.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/manifold_refs.dart';

import '../support/chaos.dart' show assertRepoSane;
import '../support/git_barrier.dart';
import '../support/git_faults.dart';
import '../support/scratch_repo.dart';

// Regression breadcrumbs — D1/D2/D4 were once deterministic findings, all fixed
// at root 2026-07-10 (dossier docs/architecture/test-hardening-crash-chaos-
// config.md) and now armed. Kept (false) so the fix history stays greppable and
// a regression is a one-line flip from reproduction.
const bool _knownFindingApplyNoRetrySkip =
    false; // D1 (C2) — applyPatch now retries
const bool _knownFindingCreateCasSkip =
    false; // D2 (C1) — zero-oid CAS on create
const bool _knownFindingAllocCasSkip = false; // D4 (C1) — zero-oid CAS on alloc

const Timeout _timeout = Timeout(Duration(minutes: 2));

/// A unified diff turning a single-line file [path] from `$from\n` to `$to\n`.
/// `applyFileStaging` resets the index entry to HEAD (`$from`) then applies
/// this against the index.
String _replaceLineDiff(String path, String from, String to) =>
    '--- a/$path\n'
    '+++ b/$path\n'
    '@@ -1 +1 @@\n'
    '-$from\n'
    '+$to\n';

/// A traditional unified diff that adds [path] as a brand-new one-line file.
String _newFileDiff(String path, String line) =>
    '--- /dev/null\n'
    '+++ b/$path\n'
    '@@ -0,0 +1,1 @@\n'
    '+$line\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  // LAW D1 — index.lock retry: the gated path retries, applyPatch does not.
  // -------------------------------------------------------------------------
  group('law D1 — index.lock retry symmetry (gated + applyPatch both retry)', () {
    test('CONTROL (armed): a gated `git add` retries a one-shot index.lock and '
        'succeeds', () async {
      final repo = await ScratchRepo.create(name: 'd1_control');
      try {
        await repo.writeFile('gated.txt', 'hello\n');
        // The FIRST `add` call is served a canned index.lock contention; the
        // gated path (_gitRaw) recognizes the shape and retries, delegating
        // the retry to real git → success. Proves the retry mechanism is live
        // (the control for the finding below).
        final r = await withGitFaults(
          GitFaultScript.failWhile(
            (args) => args.isNotEmpty && args.first == 'add',
            times: 1,
            result: indexLockContention,
          ),
          () => repo.git(['add', '--', 'gated.txt']),
        );
        expect(
          r.exitCode,
          0,
          reason:
              'the gated path must retry a transient index.lock and '
              'succeed (control proving the retry exists)',
        );
        // The blob really staged.
        final staged = await repo.git(['diff', '--cached', '--name-only']);
        expect(staged.stdout.toString().trim(), 'gated.txt');
      } finally {
        await repo.dispose();
      }
    }, timeout: _timeout);

    test(
      'ARMED: applyPatch retries a one-shot index.lock and succeeds '
      '(symmetric with the gated control)',
      () async {
        final repo = await ScratchRepo.create(name: 'd1_apply');
        final fault = GitStartFault.install(
          predicate: (args) => args.isNotEmpty && args.first == 'apply',
          result: indexLockContention,
          times: 1,
        );
        try {
          final patch = _newFileDiff('applied.txt', 'via apply');
          final r = await applyPatch(repo.dir.path, patch, cached: true);

          // The one-shot fault is served exactly once (times: 1), then applyPatch
          // RETRIES — a second `apply` spawn, delegated to real git — exactly
          // like the gated `git add` control above. matchCount counts only the
          // faults served, so it stays 1 while the underlying spawn happened
          // twice (first faulted, then real).
          expect(
            fault.matchCount,
            1,
            reason: 'the one-shot index.lock fault must be served exactly once',
          );

          // THE CONTRACT: applyPatch now routes through the gated retrying path
          // (_gitRawStdin), so a transient index.lock is retried away instead of
          // leaking raw. A red here means the retry regressed.
          expect(
            r.ok,
            isTrue,
            reason:
                'applyPatch must retry the transient index.lock and '
                'succeed like the gated control: ${r.error}',
          );

          // The retry landed the real staged blob.
          final staged = await repo.git(['show', ':applied.txt']);
          expect(staged.exitCode, 0);
          expect(staged.stdout.toString(), 'via apply\n');
        } finally {
          fault.dispose();
          await repo.dispose();
        }
      },
      timeout: _timeout,
      skip: _knownFindingApplyNoRetrySkip
          ? 'was finding D1 (applyPatch had no index.lock retry); fixed '
                '2026-07-10 — now armed'
          : false,
    );
  });

  // -------------------------------------------------------------------------
  // LAW D2 — create-CAS clobber (deterministic no-CAS repro).
  // -------------------------------------------------------------------------
  group('law D2 — two create() for one branch: the late writer is rejected', () {
    test(
      'ARMED: held creator A is rejected by the zero-oid CAS on the '
      'now-existing ref; B survives',
      () async {
        final repo = await ScratchRepo.create(name: 'd2_create');
        final barrier = GitBarrier.install();
        try {
          final refs = ManifoldRefs(
            repoPath: repo.dir.path,
            authorName: 'd2-bot',
            authorEmail: 'd2@manifold.local',
          );
          final store = DeskPrStore(refs);
          const branch = 'feature/d2';

          // Hold the NEXT `update-ref` that targets the desk PR ref (NOT the
          // id-counter ref — that one carries `refs/manifold/_id-counter`). This
          // is A's FINAL step; by the time it parks, A has already resolved the
          // ref as absent (oldSha == null) and minted its commit.
          final gate = barrier.holdWhere(
            (inv) =>
                !inv.isStart &&
                inv.args.isNotEmpty &&
                inv.args.first == 'update-ref' &&
                inv.args.any((a) => a.startsWith('refs/manifold/desks/')),
          );

          // Start A and freeze it at that update-ref.
          final heldA = await barrier.runToHold<GitResult<DeskPr>>(
            () => store.create(
              branch: branch,
              title: 'A',
              body: 'creator A',
              baseRef: 'main',
              authorIdentity: 'creator-A',
            ),
            gate,
          );

          // B runs to completion while A is parked. B's read()-precheck sees no
          // ref (A hasn't written it), so B allocs its own id and creates the
          // ref unconditionally too.
          final bRes = await store.create(
            branch: branch,
            title: 'B',
            body: 'creator B',
            baseRef: 'main',
            authorIdentity: 'creator-B',
          );
          expect(
            bRes.ok,
            isTrue,
            reason: 'B must complete fully: ${bRes.error}',
          );

          // Release A: its `update-ref <desk-ref> <sha>` now carries the zero-oid
          // as old-oid (CAS on non-existence). The ref already exists (B created
          // it), so the CAS is rejected and A errs cleanly.
          gate.release();
          final aRes = await heldA.future;

          // THE CONTRACT: the late writer A must FAIL — the zero-oid CAS rejects
          // the second create. B, which created the ref first, survives intact.
          // A green aRes.ok would mean create regressed to an unconditional
          // update-ref (oldSha:null).
          expect(
            aRes.ok,
            isFalse,
            reason: "A's zero-oid CAS on the now-existing ref must be rejected",
          );
          expect(
            aRes.error,
            isNotNull,
            reason: 'the rejected create must surface a clean error, not throw',
          );

          // The stored PR is B (the surviving first writer), not A.
          final stored = await store.read(branch);
          expect(stored.ok, isTrue, reason: stored.error);
          expect(stored.data, isNotNull);
          expect(
            stored.data!.authorIdentity,
            'creator-B',
            reason: 'B created the ref first; A was rejected, not merged',
          );
          expect(
            bRes.data!.deskId,
            isPositive,
            reason: "B's allocated id must be a real positive desk id",
          );
        } finally {
          barrier.dispose();
          await repo.dispose();
        }
      },
      timeout: _timeout,
      skip: _knownFindingCreateCasSkip
          ? 'was finding D2 (create used oldSha:null, no CAS); fixed '
                '2026-07-10 — now armed'
          : false,
    );
  });

  // -------------------------------------------------------------------------
  // LAW D3 — same-repo index writers serialize in-process (ARMED).
  //
  // HISTORY: this law originally enumerated all 6 spawn interleavings of two
  // applyFileStaging ops and proved every SERIAL schedule commutes — which
  // held. What it could not make safe is genuine child OVERLAP: git's own
  // index.lock only makes the index WRITE exclusive, not the whole
  // read-modify-write, so two overlapping index writers can commit an index
  // built from a stale snapshot and silently revert each other (chaos law 5
  // caught this live). The root fix is the per-repo index-write lock in
  // git.dart (_withRepoIndexWriteLock): overlap is now unrepresentable
  // in-process, and THAT is the law this test arms. The serial-commutativity
  // oracle (both files stage exactly, repo sane) is retained.
  // -------------------------------------------------------------------------
  group('law D3 — same-repo index writers serialize in-process', () {
    test('while one applyFileStaging child is in flight, the second op cannot '
        'even spawn; both stage once released', () async {
      final repo = await ScratchRepo.create(name: 'd3_staging');
      await repo.writeFile('fileA.txt', 'baseA\n');
      await repo.writeFile('fileB.txt', 'baseB\n');
      await repo.commitAll('d3 base');

      final barrier = GitBarrier.install();
      try {
        // Park op A's FIRST index-writing child (its `reset`) at the spawn
        // seam — the repo's index-write lock is held while it is parked.
        final gate = barrier.holdWhere((inv) => inv.tag == 'A');

        final aFut = runTagged<Future<GitResult<void>>>(
          'A',
          () => applyFileStaging(
            repo.dir.path,
            'fileA.txt',
            _replaceLineDiff('fileA.txt', 'baseA', 'stagedA'),
          ),
        );
        await gate.held;

        // Start op B while A is parked. THE LAW: B's children must not
        // arrive at the spawn seam while A holds the repo's write lock —
        // arrival would mean two index writers can overlap, which is the
        // exact lost-update mechanism chaos law 5 observed.
        final bFut = runTagged<Future<GitResult<void>>>(
          'B',
          () => applyFileStaging(
            repo.dir.path,
            'fileB.txt',
            _replaceLineDiff('fileB.txt', 'baseB', 'stagedB'),
          ),
        );
        // Give B every chance to (wrongly) spawn: real wall-clock, not just
        // a microtask turn, since spawning is async I/O.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(
          barrier.invocations.where((inv) => inv.tag == 'B'),
          isEmpty,
          reason:
              'op B spawned a git child while op A held the repo '
              'index-write lock — index writers are overlapping again',
        );

        // Release A; both ops must now drain to success, in lock order.
        gate.release();
        final aRes = await aFut;
        final bRes = await bFut;
        expect(aRes.ok, isTrue, reason: 'fileA staging failed: ${aRes.error}');
        expect(bRes.ok, isTrue, reason: 'fileB staging failed: ${bRes.error}');

        // Serial-commutativity oracle (retained from the original law): both
        // files staged with the exact expected bytes, repo sane.
        final showA = await repo.git(['show', ':fileA.txt']);
        final showB = await repo.git(['show', ':fileB.txt']);
        expect(showA.exitCode, 0, reason: 'fileA absent from index');
        expect(showB.exitCode, 0, reason: 'fileB absent from index');
        expect(
          showA.stdout.toString(),
          'stagedA\n',
          reason: 'fileA content wrong',
        );
        expect(
          showB.stdout.toString(),
          'stagedB\n',
          reason: 'fileB content wrong',
        );
        await assertRepoSane(repo, because: 'D3 serialized staging');

        // NOTE deliberately NOT asserted: "every A child before any B child".
        // The lock is per CALL, so B's reset legally enters the FIFO chain
        // (queued while A was parked) ahead of A's apply — [A,B,A,B] is a
        // correct serial schedule, and serial schedules commute (the original
        // D3 enumeration proved all 6). Only OVERLAP is illegal, and the
        // parked-B probe above is the direct test of that.
      } finally {
        barrier.dispose();
        await repo.dispose();
      }
    }, timeout: _timeout);
  });

  // -------------------------------------------------------------------------
  // LAW D4 — cross-"process" CAS via isolates (ARMED).
  // -------------------------------------------------------------------------
  group('law D4 — concurrent alloc across two isolates never duplicates an id', () {
    test(
      'ARMED: two Isolate.run batches of allocSequentialId → distinct, '
      'gap-free 1..N ids',
      () async {
        final repo = await ScratchRepo.create(name: 'd4_alloc');
        try {
          final ref = LiveManifoldRef.parse('refs/manifold/_d4-counter');
          const n = 3;
          // Capture a plain String, never the ScratchRepo — an Isolate.run
          // closure must be sendable.
          final repoPath = repo.dir.path;
          // Two isolates = two independent copies of git.dart/manifold_refs
          // statics (own semaphore, own _allocChains) against ONE .git — a
          // faithful two-app-process race. The git ref CAS is the only net.
          final results = await Future.wait(<Future<_AllocBatch>>[
            Isolate.run(() => _isoAllocBatch(repoPath, ref, n)),
            Isolate.run(() => _isoAllocBatch(repoPath, ref, n)),
          ]);

          final allIds = <int>[...results[0].ids, ...results[1].ids];
          // Every allocation across both processes succeeds — a lost CAS retries
          // onto next+1 rather than erroring out.
          expect(
            results[0].errors,
            0,
            reason:
                'isolate 0 lost an allocation (${results[0].errors} errors)',
          );
          expect(
            results[1].errors,
            0,
            reason:
                'isolate 1 lost an allocation (${results[1].errors} errors)',
          );
          expect(
            allIds.length,
            2 * n,
            reason: 'every allocation across both processes must succeed',
          );
          expect(
            allIds.every((id) => id > 0),
            isTrue,
            reason: 'every allocated id is a positive integer',
          );

          // THE CONTRACT: the shared counter serializes all 2*n allocations into
          // the clean, gap-free range 1..2n. The fresh-ref create CAS-es on
          // non-existence (zero-oid via createRef, manifold_refs.dart:613); on a
          // lost CAS the alloc re-reads the winner's value and retries onto
          // next+1, so two processes never win the same id (the old bug produced
          // e.g. [1,2,4,1,3,5]).
          expect(
            allIds.toSet().length,
            allIds.length,
            reason:
                'duplicate id across isolates — the fresh-ref CAS or its '
                'lost-CAS retry regressed. ids=$allIds',
          );
          expect(
            allIds..sort(),
            equals(List<int>.generate(2 * n, (i) => i + 1)),
            reason:
                'the two processes must allocate exactly 1..${2 * n} with '
                'no gaps or duplicates. ids=$allIds',
          );
        } finally {
          await repo.dispose();
        }
      },
      timeout: _timeout,
      skip: _knownFindingAllocCasSkip
          ? 'was finding D4 (fresh-ref alloc used oldSha:null, no CAS); '
                'fixed 2026-07-10 — now armed'
          : false,
    );
  });

  // -------------------------------------------------------------------------
  // LAW D5 — isolate spawns escape this process's semaphore (ARMED doc).
  // -------------------------------------------------------------------------
  group('law D5 — an isolate git read completes despite a held main-isolate '
      'spawn', () {
    test('a parked main-isolate mutation (semaphore slot held) does not block '
        'an isolate read', () async {
      final repo = await ScratchRepo.create(name: 'd5_escape');
      final barrier = GitBarrier.install();
      try {
        // Park a main-isolate mutating spawn. The semaphore is acquired in
        // _gitRaw BEFORE the spawn, so while parked this call occupies a slot
        // of THIS process's throttle.
        final gate = barrier.holdWhere(
          (inv) =>
              !inv.isStart && inv.args.isNotEmpty && inv.args.first == 'commit',
        );
        final heldMain = await barrier.runToHold<ProcessResult>(
          () => repo.git(['commit', '--allow-empty', '-m', 'held-main']),
          gate,
        );

        // While the main call is frozen mid-spawn, a git read inside a fresh
        // isolate completes: its spawn goes through the isolate's OWN git.dart
        // statics (own semaphore), entirely outside this process's throttle.
        final repoPath = repo.dir.path;
        final isoHead = await Isolate.run(() => _isoReadHead(repoPath));
        expect(
          isoHead,
          isNotNull,
          reason:
              'the isolate read must complete despite the main-isolate '
              'hold — isolate spawns are not subject to this process\'s '
              'semaphore (documented class, like chaos law 1)',
        );
        expect(isoHead, isNotEmpty);

        // Release the held main mutation and confirm it lands cleanly.
        gate.release();
        final mainRes = await heldMain.future;
        expect(
          mainRes.exitCode,
          0,
          reason: 'the released main commit must succeed: ${mainRes.stderr}',
        );
      } finally {
        barrier.dispose();
        await repo.dispose();
      }
    }, timeout: _timeout);
  });
}

// ---------------------------------------------------------------------------
// Isolate bodies (top-level so they are sendable). Each runs the REAL git path
// in a fresh isolate — its own git.dart statics, its own semaphore. Wrapped in
// runZonedGuarded so the app's fire-and-forget telemetry persistence (which
// touches SharedPreferences and has no platform channel in a bare isolate)
// cannot surface as an unhandled async error and fail the isolate.
// ---------------------------------------------------------------------------

typedef _AllocBatch = ({List<int> ids, int errors});

Future<_AllocBatch> _isoAllocBatch(String repoPath, String ref, int n) {
  final completer = Completer<_AllocBatch>();
  runZonedGuarded(
    () async {
      final refs = ManifoldRefs(
        repoPath: repoPath,
        authorName: 'd4-bot',
        authorEmail: 'd4@manifold.local',
      );
      final ids = <int>[];
      var errors = 0;
      // [ref] crossed the isolate boundary as a plain sendable String;
      // parse it back into the typed ref at this trust boundary.
      final counterRef = LiveManifoldRef.parse(ref);
      for (var i = 0; i < n; i++) {
        final r = await refs.allocSequentialId(
          ref: counterRef,
          filename: 'counter.txt',
          commitLabel: 'd4',
        );
        if (r.ok) {
          ids.add(r.data!);
        } else {
          errors++;
        }
      }
      if (!completer.isCompleted) {
        completer.complete((ids: ids, errors: errors));
      }
    },
    (error, stack) {
      // Swallow detached telemetry errors; complete with what we have only if
      // the batch itself never finished (a genuine failure).
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  return completer.future;
}

Future<String?> _isoReadHead(String repoPath) {
  final completer = Completer<String?>();
  runZonedGuarded(
    () async {
      final r = await runGit(repoPath, ['rev-parse', 'HEAD']);
      final sha = r.stdout.toString().trim();
      if (!completer.isCompleted) {
        completer.complete(r.exitCode == 0 && sha.isNotEmpty ? sha : null);
      }
    },
    (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  return completer.future;
}
