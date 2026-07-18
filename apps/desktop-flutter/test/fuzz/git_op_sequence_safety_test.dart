// Deep git-safety fuzz suite, built on top of the shared ScratchRepo/RepoOp
// harness (test/support/scratch_repo.dart). The harness's own self-test
// (scratch_repo_self_test.dart) already checks fsck+HEAD-valid for 6 fixed
// seeds — this file expands on that: many more seeds, explicit named laws,
// and a dedicated Manifold-namespace-isolation law.
//
// LAWS (never violated, regardless of which random ops ran):
//   1. Repository never corrupts (`git fsck --full` exits 0).
//   2. HEAD is always resolvable to a real 40-hex sha once history exists.
//   3. No stray refs — every ref lives under an expected namespace.
//   4. The current branch (or detached HEAD) always points at a real commit.
//   5. genRepoOpSequence(seed) is deterministic.
//   6. Working-tree ops never damage `.git` itself (fsck is the oracle).
//   7. Manifold namespace writes (DeskPrStore / DeskIssueStore, real app
//      code) never mutate a byte of any real refs/heads/* or refs/remotes/*.
//   8. Hostile branch names (unicode, spaces, near-collisions, Windows
//      device names, path-traversal attempts, MAX_PATH-busting depth) never
//      corrupt the repo or escape the repository directory — git either
//      rejects them cleanly or creates them safely.
//
// A violation of a law is a real bug: it must not be papered over by
// weakening the assertion. The failing case is captured with its exact
// seed + op list.
//
// SCALING: reads MANIFOLD_FUZZ (default 1) and scales SEED COUNT only
// (maxOps stays fixed) so default wall-clock stays well under ~90s:
//   MANIFOLD_FUZZ=1  (default) -> 40 seeds  @ maxOps 40
//   MANIFOLD_FUZZ=10 (deep)    -> 400 seeds @ maxOps 40

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_issue_store.dart';
import 'package:git_desktop/backend/desk_pr_store.dart';
import 'package:git_desktop/backend/manifold_refs.dart';

import '../support/prop.dart' show fuzzTimeout;
import '../support/scratch_repo.dart';
import '../support/must.dart';

/// `MANIFOLD_FUZZ` env multiplier — scales seed count, not per-sequence
/// op count, so a "deep" run explores far more independent sequences
/// without any single sequence's runtime blowing up.
final int _fuzzMultiplier =
    int.tryParse(Platform.environment['MANIFOLD_FUZZ'] ?? '') ?? 1;
final int _seedCount = 40 * (_fuzzMultiplier < 1 ? 1 : _fuzzMultiplier);
const int _maxOps = 40;

final RegExp _shaPattern = RegExp(r'^[0-9a-f]{40}$');

/// Ref namespaces this suite considers legitimate. `refs/manifold/*` and
/// `refs/manifold-remote/*` are only ever expected in the groups that
/// deliberately exercise Manifold writes — the base fuzz-sequence group
/// never touches them, so a leak there would itself be a stray-ref bug.
/// `refs/remotes/*` is likewise only expected where a test deliberately
/// seeds remote-tracking refs (the base fuzz sequence and the adversarial-
/// name group never create any) — kept opt-in for the same reason.
bool _isExpectedRef(
  String ref, {
  required bool allowManifold,
  bool allowRemotes = false,
}) {
  if (ref.startsWith('refs/heads/')) return true;
  if (ref.startsWith('refs/tags/')) return true;
  if (ref == 'refs/stash') return true;
  if (allowRemotes && ref.startsWith('refs/remotes/')) return true;
  if (allowManifold &&
      (ref.startsWith('refs/manifold/') ||
          ref.startsWith('refs/manifold-remote/'))) {
    return true;
  }
  return false;
}

String _repro(int seed, List<RepoOp> ops, List<RepoOpResult> results) {
  final buf = StringBuffer('seed=$seed maxOps=$_maxOps\n');
  for (var i = 0; i < results.length; i++) {
    buf.writeln('  [$i] ${results[i]}');
  }
  return buf.toString();
}

/// Runs the three cheap, always-applicable checks (fsck, HEAD, branch/
/// detached-HEAD integrity) against [repo] and returns a description of any
/// stray ref found (empty if none) — factored out so both the main
/// seed-sweep and the adversarial-name group share one implementation of
/// laws 1/2/4/6.
Future<void> _assertCoreInvariants(
  ScratchRepo repo, {
  required bool allowManifold,
  bool allowRemotes = false,
  required String Function() reason,
}) async {
  // Law 1 + 6: the object database and `.git` itself are never corrupted.
  final fsck = await repo.git(['fsck', '--full', '--no-dangling']);
  expect(
    fsck.exitCode,
    0,
    reason:
        'git fsck --full reported corruption.\n${reason()}\n'
        'stdout: ${fsck.stdout}\nstderr: ${fsck.stderr}',
  );

  // Law 2: HEAD always resolves to a real commit (ScratchRepo.create seeds
  // a root commit before any fuzzed op runs, so history always exists).
  final head = await repo.head();
  expect(head, isNotNull, reason: 'HEAD did not resolve.\n${reason()}');
  expect(
    _shaPattern.hasMatch(head!),
    isTrue,
    reason: 'HEAD is not a 40-hex sha: $head\n${reason()}',
  );

  // Law 4: current branch (if any) points at a real commit; detached HEAD
  // still resolves (already proven by the head() check above).
  final symbolic = await repo.git(['symbolic-ref', '-q', 'HEAD']);
  if (symbolic.exitCode == 0) {
    final branchRef = symbolic.stdout.toString().trim();
    final resolved = await repo.git(['rev-parse', '--verify', branchRef]);
    expect(
      resolved.exitCode,
      0,
      reason: 'current branch $branchRef does not resolve.\n${reason()}',
    );
  }

  // Law 3: no stray refs outside the expected namespaces.
  final refs = await repo.allRefs();
  for (final ref in refs) {
    expect(
      _isExpectedRef(
        ref,
        allowManifold: allowManifold,
        allowRemotes: allowRemotes,
      ),
      isTrue,
      reason: 'stray ref outside expected namespaces: $ref\n${reason()}',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('git op sequence safety fuzz (laws 1-4, 6)', () {
    for (var seed = 1; seed <= _seedCount; seed++) {
      test('seed $seed: repo never corrupts, HEAD/refs stay valid', () async {
        final repo = await ScratchRepo.create(name: 'fuzz_$seed');
        try {
          final ops = genRepoOpSequence(seed, maxOps: _maxOps);
          final results = <RepoOpResult>[];
          for (final op in ops) {
            results.add(await applyOp(repo, op));
          }
          await _assertCoreInvariants(
            repo,
            allowManifold: false,
            reason: () => _repro(seed, ops, results),
          );
        } finally {
          await repo.dispose();
        }
      });
    }
  });

  group('generator determinism (law 5)', () {
    test('genRepoOpSequence(seed) returns identical ops across calls', () {
      for (final seed in [0, 1, 2, 7, 42, 12345, 999999, -99, 1 << 40]) {
        final a = genRepoOpSequence(seed, maxOps: 40).map((o) => o.toString());
        final b = genRepoOpSequence(seed, maxOps: 40).map((o) => o.toString());
        expect(
          a.toList(),
          equals(b.toList()),
          reason: 'seed $seed was non-deterministic across two calls',
        );
      }
    });
  });

  group('manifold ref isolation (law 7)', () {
    test('DeskPrStore/DeskIssueStore writes never mutate a real refs/heads or '
        'refs/remotes sha', () async {
      final repo = await ScratchRepo.create(name: 'manifold_isolation');
      try {
        // Build several real branches with distinct, diverged history —
        // exactly the shape a real user's repo has before Manifold ever
        // touches it.
        await repo.writeFile('a.txt', 'v1\n');
        await repo.commitAll('a v1');
        for (final name in [
          'feature/alpha',
          'feature/beta',
          'release-1.0',
          'hotfix_x',
        ]) {
          await repo.gitOk(['branch', name]);
        }
        await repo.gitOk(['checkout', 'feature/alpha']);
        await repo.writeFile('a.txt', 'v2 on alpha\n');
        await repo.commitAll('alpha work');
        await repo.gitOk(['checkout', 'main']);
        // Simulate a remote-tracking namespace too — `refs/remotes/*` is
        // just as untouchable as `refs/heads/*`.
        await repo.gitOk([
          'update-ref',
          'refs/remotes/origin/main',
          (await repo.head())!,
        ]);
        await repo.gitOk([
          'update-ref',
          'refs/remotes/origin/feature/alpha',
          (await repo.gitOk(['rev-parse', 'feature/alpha'])),
        ]);

        // Snapshot every refs/heads/* and refs/remotes/* sha BEFORE any
        // Manifold write.
        final before = <String, String>{};
        for (final ref in await repo.allRefs()) {
          if (ref.startsWith('refs/heads/') ||
              ref.startsWith('refs/remotes/')) {
            before[ref] = await repo.gitOk(['rev-parse', ref]);
          }
        }
        expect(
          before.length,
          greaterThanOrEqualTo(6),
          reason: 'snapshot setup did not create the expected real refs',
        );

        // Drive REAL app code (not a hand-rolled `update-ref`): DeskPrStore
        // backs onto ManifoldRefs exactly as the app's DeskPrState does,
        // pointed at this scratch repo's path. This exercises the actual
        // production write path — blob/tree/commit-tree/update-ref plumbing
        // in lib/backend/manifold_refs.dart — under refs/manifold/desks/*.
        final refs = ManifoldRefs(
          repoPath: repo.dir.path,
          authorName: 'fuzz-bot',
          authorEmail: 'fuzz-bot@manifold.local',
        );
        final prStore = DeskPrStore(refs);
        final issueStore = DeskIssueStore(refs);

        for (final branch in ['feature/alpha', 'feature/beta']) {
          final created = await prStore.create(
            branch: branch,
            title: 'PR for $branch',
            body: 'fuzz body',
            baseRef: 'main',
            authorIdentity: 'fuzz-bot',
          );
          expect(created.ok, isTrue, reason: created.error);
          await expectOk(
            prStore.addComment(
              branch: branch,
              author: 'fuzz-bot',
              body: 'a comment',
            ),
          );
          await expectOk(prStore.setState(branch: branch, state: 'MERGED'));
        }
        for (var i = 0; i < 3; i++) {
          final created = await issueStore.create(
            title: 'issue $i',
            body: 'body $i',
            authorIdentity: 'fuzz-bot',
          );
          expect(created.ok, isTrue, reason: created.error);
        }

        // Sanity: the Manifold writes actually landed under their own
        // namespace (otherwise "real refs untouched" would be vacuous).
        final refsAfter = await repo.allRefs();
        expect(
          refsAfter.any((r) => r.startsWith('refs/manifold/desks/')),
          isTrue,
          reason: 'DeskPrStore.create did not land a desks/ ref',
        );
        expect(
          refsAfter.any((r) => r.startsWith('refs/manifold/issues/')),
          isTrue,
          reason: 'DeskIssueStore.create did not land an issues/ ref',
        );

        // LAW 7: every real ref's sha is byte-identical to the snapshot —
        // the Manifold writes touched refs/manifold/* only.
        for (final entry in before.entries) {
          final now = await repo.gitOk(['rev-parse', entry.key]);
          expect(
            now,
            equals(entry.value),
            reason:
                'Manifold write mutated real ref ${entry.key} '
                '(was ${entry.value}, now $now)',
          );
        }
        // And no real ref was deleted or a new one of that kind added.
        final realRefsAfter = refsAfter
            .where(
              (r) =>
                  r.startsWith('refs/heads/') || r.startsWith('refs/remotes/'),
            )
            .toSet();
        expect(
          realRefsAfter,
          equals(before.keys.toSet()),
          reason:
              'the set of real refs changed shape after Manifold '
              'writes',
        );

        await _assertCoreInvariants(
          repo,
          allowManifold: true,
          allowRemotes: true,
          reason: () => 'manifold ref isolation test',
        );
      } finally {
        await repo.dispose();
      }
      // Dozens of real CAS-retrying git chains; sibling deep suites in a
      // MANIFOLD_FUZZ run multiply the machine-wide contention, so the
      // deadline scales with the run depth rather than fixing at 30s.
    }, timeout: fuzzTimeout());
  });

  group('adversarial branch names (law 8)', () {
    // Deliberately hostile branch names: unicode, spaces, git-grammar
    // violations, argument-injection shapes, Windows-reserved device names,
    // a case-only near-collision (Windows/NTFS is case-insensitive, unlike
    // git's own ref semantics), and a MAX_PATH-busting deeply nested name —
    // Windows paths under `.git` are subject to MAX_PATH, a real constraint
    // on this platform.
    const names = <String>[
      'café-☃-日本語-brânch', // valid unicode — git should accept
      'branch with spaces', // space is illegal in a refname
      'weird..dotdot', // ".." anywhere is illegal
      'trailing-dot.', // trailing "." is illegal
      'lockfile.lock', // ".lock" suffix is illegal
      '-leading-dash', // ambiguous with a CLI flag
      'weird~tilde',
      'weird^caret',
      'weird:colon',
      'weird?question',
      'weird*star',
      'weird[bracket',
      r'weird\backslash', // meaningful path separator on Windows
      '../../escape-attempt', // path traversal shape
      r'..\..\escape-attempt', // path traversal, Windows separators
      'CON', // reserved Windows device name
      'NUL',
      'nested/CON/leaf',
      'CaseCollide', // paired with the next entry
      'casecollide', // case-only near-collision on a case-insensitive FS
    ];

    test('hostile CreateBranchOp/CheckoutOp names never corrupt the repo '
        'or escape it', () async {
      final repo = await ScratchRepo.create(name: 'adversarial_names');
      try {
        // Escape check: nothing outside the repo's own temp dir should ever
        // be created or modified by a hostile ref name.
        final parent = Directory(repo.dir.parent.path);
        final siblingsBefore = parent.listSync().map((e) => e.path).toSet();

        final log = StringBuffer();
        for (final name in names) {
          final createResult = await applyOp(repo, CreateBranchOp(name));
          log.writeln('create($name) -> $createResult');
          if (createResult.ok) {
            // If git accepted the name, it must be checkout-able and must
            // resolve through git's OWN ref lookup (not a hand-rolled path
            // check) to a real commit — i.e. created safely, no namespace
            // escape.
            final resolved = await repo.git([
              'rev-parse',
              '--verify',
              'refs/heads/$name',
            ]);
            log.writeln(
              '  rev-parse refs/heads/$name -> '
              'exit=${resolved.exitCode} out=${resolved.stdout}',
            );
            final checkoutResult = await applyOp(repo, CheckoutOp(name));
            log.writeln('  checkout($name) -> $checkoutResult');
            if (checkoutResult.ok) {
              await repo.git(['checkout', 'main']);
            }
          }
        }

        // Deeply nested MAX_PATH-busting name, generated separately since
        // it's algorithmic rather than a fixed literal.
        final deepName = List.generate(
          40,
          (i) => 'segment$i-of-a-very-long-branch-path',
        ).join('/');
        final deepCreate = await applyOp(repo, CreateBranchOp(deepName));
        log.writeln('create(<deep $deepName>) -> $deepCreate');

        // LAWS: whatever happened above (accepted or cleanly rejected),
        // the repo must still be whole and every ref legitimate.
        await _assertCoreInvariants(
          repo,
          allowManifold: false,
          reason: () => log.toString(),
        );

        // No file/directory appeared next to the repo's own temp dir — a
        // hostile name never escapes the repository it was created in.
        final siblingsAfter = parent.listSync().map((e) => e.path).toSet();
        expect(
          siblingsAfter,
          equals(siblingsBefore),
          reason:
              'a hostile branch name left evidence outside the repo '
              'directory.\n${log.toString()}',
        );
      } finally {
        await repo.dispose();
      }
      // Same class as law 7: ~20 create/checkout chains against real git,
      // under whatever machine-wide load the fuzz depth implies.
    }, timeout: fuzzTimeout());
  });
}
