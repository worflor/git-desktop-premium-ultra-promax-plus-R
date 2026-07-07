// Integration tests for the unified forge-PR checkout path.
//
// The whole point of `checkoutPrHead` is that it speaks pure git for
// every forge — no `gh`/`glab` binary required — so these tests build
// the full PR-ref scenario with real git and zero network:
//
//   * a bare repo stands in for the forge;
//   * clone #1 is the working repo we run checkout against;
//   * clone #2 pushes a feature commit to `refs/pull/<n>/head` (GitHub /
//     Gitea) or `refs/merge-requests/<n>/head` (GitLab) — exactly how a
//     forge exposes a PR/MR head.
//
// They also pin the ProcessException containment in `runForgeCli`: a
// missing CLI binary must degrade to a clean non-zero result, never a
// thrown exception tearing through the GitResult-returning call sites.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/gh.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/remote_pr_provider.dart';
import 'package:git_desktop/backend/merge_preflight.dart'
    show classifyMergeTreeProbe, mergeTreeStderrIsUnknownOption;

/// Human-readable label for a checkout outcome, used as an expectation
/// `reason` so a surprising variant prints its detail instead of a bare
/// type mismatch.
String _outcomeLabel(PrCheckoutOutcome o) => switch (o) {
      PrCheckoutOk() => 'ok',
      PrCheckoutFailed(:final error) => 'failed: $error',
      PrCheckoutWouldClobber(:final localRef, :final localTip, :final remoteTip) =>
        'would-clobber $localRef ($localTip → $remoteTip)',
    };

Future<ProcessResult> _git(String cwd, List<String> args) => Process.run(
      'git',
      args,
      workingDirectory: cwd,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

Future<void> _identity(String cwd) async {
  await _git(cwd, ['config', 'user.name', 'tester']);
  await _git(cwd, ['config', 'user.email', 'tester@manifold.local']);
}

Future<String> _revParse(String cwd, String rev) async =>
    (await _git(cwd, ['rev-parse', rev])).stdout.toString().trim();

Future<String> _currentBranch(String cwd) async =>
    (await _git(cwd, ['symbolic-ref', '--short', 'HEAD']))
        .stdout
        .toString()
        .trim();

/// Tolerant cleanup — Windows briefly holds file handles after spawned
/// `git` processes exit, which can race with `delete(recursive:)` for
/// ~100ms. The handles drop on their own; swallowing the error keeps the
/// test signal honest (the assertions already ran).
Future<void> _safeCleanup(Directory dir) async {
  try {
    await dir.delete(recursive: true);
  } on FileSystemException {
    // Ignored — see docstring.
  }
}

class _Scenario {
  final Directory root;
  final String clone1;
  final String clone2;
  final String headSha;
  const _Scenario({
    required this.root,
    required this.clone1,
    required this.clone2,
    required this.headSha,
  });
}

/// Builds a bare "forge" with `main`, two clones, and a PR head pushed
/// to [refPath] carrying a single feature commit. Returns the working
/// clone plus the feature commit's SHA so tests can assert exact tips.
Future<_Scenario> _scenarioWithPrRef(String refPath) async {
  final root = await Directory.systemTemp.createTemp('manifold_pr_');
  final bare = '${root.path}/forge.git';
  await _git(root.path, ['init', '-q', '--bare', '-b', 'main', 'forge.git']);

  // clone #1 — the working repo we run checkout against. It seeds `main`.
  final clone1 = '${root.path}/clone1';
  await _git(root.path, ['clone', '-q', bare, 'clone1']);
  await _identity(clone1);
  await File('$clone1/README.md').writeAsString('root\n');
  await _git(clone1, ['add', '.']);
  await _git(clone1, ['commit', '-qm', 'root']);
  await _git(clone1, ['push', '-q', 'origin', 'HEAD:refs/heads/main']);

  // clone #2 — pushes the PR head exactly like a forge exposes it.
  final clone2 = '${root.path}/clone2';
  await _git(root.path, ['clone', '-q', bare, 'clone2']);
  await _identity(clone2);
  await _git(clone2, ['checkout', '-qb', 'feature']);
  await File('$clone2/feature.txt').writeAsString('pr work\n');
  await _git(clone2, ['add', '.']);
  await _git(clone2, ['commit', '-qm', 'pr commit']);
  final sha = await _revParse(clone2, 'HEAD');
  await _git(clone2, ['push', '-q', 'origin', 'HEAD:$refPath']);

  return _Scenario(root: root, clone1: clone1, clone2: clone2, headSha: sha);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('checkoutPrHead — pure-git forge checkout', () {
    test('GitHub-shaped pull/<n>/head fetches to pr-<n> and checks it out',
        () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        final r = await checkoutPrHead(scn.clone1, 7, 'pull/7/head');
        expect(r, isA<PrCheckoutOk>(), reason: _outcomeLabel(r));
        // Local branch materialised at the PR head SHA...
        expect(await _revParse(scn.clone1, 'pr-7'), scn.headSha);
        // ...and it is the checked-out branch.
        expect(await _revParse(scn.clone1, 'HEAD'), scn.headSha);
        expect(await _currentBranch(scn.clone1), 'pr-7');
      } finally {
        await _safeCleanup(scn.root);
      }
    });

    test('GitLab-shaped merge-requests/<n>/head lands on the same pr-<n> ref',
        () async {
      final scn = await _scenarioWithPrRef('refs/merge-requests/7/head');
      try {
        final r =
            await checkoutPrHead(scn.clone1, 7, 'merge-requests/7/head');
        expect(r, isA<PrCheckoutOk>(), reason: _outcomeLabel(r));
        // The local-branch convention is forge-independent: `pr-<n>`.
        expect(await _revParse(scn.clone1, 'pr-7'), scn.headSha);
        expect(await _currentBranch(scn.clone1), 'pr-7');
      } finally {
        await _safeCleanup(scn.root);
      }
    });

    test('re-checkout fast-forwards an existing pr-<n> to the new remote tip',
        () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        final first = await checkoutPrHead(scn.clone1, 7, 'pull/7/head');
        expect(first, isA<PrCheckoutOk>(), reason: _outcomeLabel(first));

        // Step off pr-7 so the re-run mirrors the realistic case (ref kept
        // from a prior desk, user now sitting elsewhere).
        await _git(scn.clone1, ['checkout', '-q', 'main']);

        // The PR head advances on the forge by ADDING a commit — the old
        // local tip stays an ancestor, so this is a clean fast-forward.
        await File('${scn.clone2}/feature.txt').writeAsString('pr work v2\n');
        await _git(scn.clone2, ['add', '.']);
        await _git(scn.clone2, ['commit', '-qm', 'pr commit 2']);
        final sha1 = await _revParse(scn.clone2, 'HEAD');
        await _git(scn.clone2, ['push', '-q', 'origin', 'HEAD:refs/pull/7/head']);
        expect(sha1, isNot(scn.headSha));

        // Fast-forward: pr-7 advances to the new tip silently, no clobber.
        final second = await checkoutPrHead(scn.clone1, 7, 'pull/7/head');
        expect(second, isA<PrCheckoutOk>(), reason: _outcomeLabel(second));
        expect(await _revParse(scn.clone1, 'pr-7'), sha1);
        expect(await _currentBranch(scn.clone1), 'pr-7');
      } finally {
        await _safeCleanup(scn.root);
      }
    });

    test('a nonexistent ref returns a typed failure and does not throw',
        () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        final r = await checkoutPrHead(scn.clone1, 99, 'pull/99/head');
        expect(r, isA<PrCheckoutFailed>());
        expect((r as PrCheckoutFailed).error, isNotEmpty);
      } finally {
        await _safeCleanup(scn.root);
      }
    });

    test('falls back to the CLI checkout when the pure-git fetch fails',
        () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        var fallbackRan = false;
        final r = await checkoutPrHead(
          scn.clone1,
          99,
          'pull/99/head',
          cliFallback: () async {
            fallbackRan = true;
            return const GitResult<void>.ok(null);
          },
        );
        expect(fallbackRan, isTrue);
        expect(r, isA<PrCheckoutOk>(), reason: _outcomeLabel(r));
      } finally {
        await _safeCleanup(scn.root);
      }
    });

    test('names both paths when pure git AND the CLI fallback fail',
        () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        final r = await checkoutPrHead(
          scn.clone1,
          99,
          'pull/99/head',
          cliFallback: () async => const GitResult<void>.err('gh not found'),
        );
        expect(r, isA<PrCheckoutFailed>());
        final err = (r as PrCheckoutFailed).error;
        expect(err, contains('pure-git fetch failed'));
        expect(err, contains('gh not found'));
      } finally {
        await _safeCleanup(scn.root);
      }
    });
  });

  group('checkoutPrHead — clobber safety', () {
    // Advance local pr-7 with an unpushed commit AND move the remote head
    // onto a divergent commit, so the two tips are no longer ancestor-related.
    Future<String> divergeLocalAndRemote(_Scenario scn) async {
      // Local unpushed work on pr-7 (currently checked out after the first
      // checkout landed it).
      await File('${scn.clone1}/local.txt').writeAsString('local only\n');
      await _git(scn.clone1, ['add', '.']);
      await _git(scn.clone1, ['commit', '-qm', 'local unpushed']);
      // Step off so the branch is not the checked-out one during the probe.
      await _git(scn.clone1, ['checkout', '-q', 'main']);
      // Remote advances independently → divergence.
      await File('${scn.clone2}/feature.txt').writeAsString('remote v2\n');
      await _git(scn.clone2, ['add', '.']);
      await _git(scn.clone2, ['commit', '-qm', 'remote commit 2']);
      final remoteSha = await _revParse(scn.clone2, 'HEAD');
      await _git(
          scn.clone2, ['push', '-q', 'origin', 'HEAD:refs/pull/7/head']);
      return remoteSha;
    }

    test('(a) local pr-<n> with unpushed commits + moved remote → would-clobber, '
        'branch untouched', () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        final first = await checkoutPrHead(scn.clone1, 7, 'pull/7/head');
        expect(first, isA<PrCheckoutOk>(), reason: _outcomeLabel(first));
        final localBefore = await _revParse(scn.clone1, 'pr-7');

        final remoteSha = await divergeLocalAndRemote(scn);
        final localTip = await _revParse(scn.clone1, 'pr-7');
        expect(localTip, isNot(localBefore)); // local moved forward

        final r = await checkoutPrHead(scn.clone1, 7, 'pull/7/head');
        expect(r, isA<PrCheckoutWouldClobber>(), reason: _outcomeLabel(r));
        final wc = r as PrCheckoutWouldClobber;
        expect(wc.localRef, 'pr-7');
        expect(wc.localTip, localTip);
        expect(wc.remoteTip, remoteSha);
        // The branch was NOT moved — the local commit is still reachable.
        expect(await _revParse(scn.clone1, 'pr-7'), localTip);
      } finally {
        await _safeCleanup(scn.root);
      }
    });

    test('(b) force overrides the guard and updates the branch to the remote tip',
        () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        final first = await checkoutPrHead(scn.clone1, 7, 'pull/7/head');
        expect(first, isA<PrCheckoutOk>(), reason: _outcomeLabel(first));
        final remoteSha = await divergeLocalAndRemote(scn);

        final r =
            await checkoutPrHead(scn.clone1, 7, 'pull/7/head', force: true);
        expect(r, isA<PrCheckoutOk>(), reason: _outcomeLabel(r));
        expect(await _revParse(scn.clone1, 'pr-7'), remoteSha);
        expect(await _currentBranch(scn.clone1), 'pr-7');
      } finally {
        await _safeCleanup(scn.root);
      }
    });

    test('(c) pr-<n> ancestor of the remote head → silent fast-forward, no flag',
        () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        final first = await checkoutPrHead(scn.clone1, 7, 'pull/7/head');
        expect(first, isA<PrCheckoutOk>(), reason: _outcomeLabel(first));
        await _git(scn.clone1, ['checkout', '-q', 'main']);

        // Remote adds a commit on top → old local tip stays an ancestor.
        await File('${scn.clone2}/feature.txt').writeAsString('pr v2\n');
        await _git(scn.clone2, ['add', '.']);
        await _git(scn.clone2, ['commit', '-qm', 'pr commit 2']);
        final sha1 = await _revParse(scn.clone2, 'HEAD');
        await _git(
            scn.clone2, ['push', '-q', 'origin', 'HEAD:refs/pull/7/head']);

        final r = await checkoutPrHead(scn.clone1, 7, 'pull/7/head');
        expect(r, isA<PrCheckoutOk>(), reason: _outcomeLabel(r));
        expect(await _revParse(scn.clone1, 'pr-7'), sha1);
      } finally {
        await _safeCleanup(scn.root);
      }
    });

    test('(d) pr-<n> absent → normal create + checkout', () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        // No prior pr-7 exists in clone1.
        final before = await _git(scn.clone1, ['rev-parse', '--verify', 'pr-7']);
        expect(before.exitCode, isNot(0));

        final r = await checkoutPrHead(scn.clone1, 7, 'pull/7/head');
        expect(r, isA<PrCheckoutOk>(), reason: _outcomeLabel(r));
        expect(await _revParse(scn.clone1, 'pr-7'), scn.headSha);
        expect(await _currentBranch(scn.clone1), 'pr-7');
      } finally {
        await _safeCleanup(scn.root);
      }
    });
  });

  group('fetchPrHeadToBranch — desk-opening flavour (no HEAD move)', () {
    test('(1) fresh: lands pr-<n> at the remote tip and leaves HEAD on main',
        () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        // clone1 seeds and stays on `main`; assert that before and after.
        expect(await _currentBranch(scn.clone1), 'main');

        final r = await fetchPrHeadToBranch(scn.clone1, 7, 'pull/7/head');
        expect(r, isA<PrCheckoutOk>(), reason: _outcomeLabel(r));
        // pr-7 materialised at the remote tip...
        expect(await _revParse(scn.clone1, 'pr-7'), scn.headSha);
        // ...but the checkout never moved — the whole point of this flavour.
        expect(await _currentBranch(scn.clone1), 'main');
        expect(await _revParse(scn.clone1, 'HEAD'),
            await _revParse(scn.clone1, 'main'));
      } finally {
        await _safeCleanup(scn.root);
      }
    });

    test('(2) fast-forward: pr-<n> ancestor of new tip advances, HEAD untouched',
        () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        final first = await fetchPrHeadToBranch(scn.clone1, 7, 'pull/7/head');
        expect(first, isA<PrCheckoutOk>(), reason: _outcomeLabel(first));
        final mainBefore = await _revParse(scn.clone1, 'main');

        // Remote advances by ADDING a commit — old tip stays an ancestor.
        await File('${scn.clone2}/feature.txt').writeAsString('pr work v2\n');
        await _git(scn.clone2, ['add', '.']);
        await _git(scn.clone2, ['commit', '-qm', 'pr commit 2']);
        final sha1 = await _revParse(scn.clone2, 'HEAD');
        await _git(
            scn.clone2, ['push', '-q', 'origin', 'HEAD:refs/pull/7/head']);
        expect(sha1, isNot(scn.headSha));

        final r = await fetchPrHeadToBranch(scn.clone1, 7, 'pull/7/head');
        expect(r, isA<PrCheckoutOk>(), reason: _outcomeLabel(r));
        expect(await _revParse(scn.clone1, 'pr-7'), sha1);
        // HEAD/main never moved.
        expect(await _currentBranch(scn.clone1), 'main');
        expect(await _revParse(scn.clone1, 'main'), mainBefore);
      } finally {
        await _safeCleanup(scn.root);
      }
    });

    test('(3) clobber guard: local-only commit on pr-<n> → would-clobber, '
        'ref not moved', () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        final first = await fetchPrHeadToBranch(scn.clone1, 7, 'pull/7/head');
        expect(first, isA<PrCheckoutOk>(), reason: _outcomeLabel(first));

        // Put a local-only commit on pr-7 without ever checking it out —
        // `git branch -f pr-7 <newsha>` after committing on a temp branch.
        await _git(scn.clone1, ['checkout', '-q', '-b', '_scratch', 'pr-7']);
        await File('${scn.clone1}/local.txt').writeAsString('local only\n');
        await _git(scn.clone1, ['add', '.']);
        await _git(scn.clone1, ['commit', '-qm', 'local unpushed']);
        final localTip = await _revParse(scn.clone1, 'HEAD');
        await _git(scn.clone1, ['branch', '-f', 'pr-7', localTip]);
        await _git(scn.clone1, ['checkout', '-q', 'main']);
        await _git(scn.clone1, ['branch', '-q', '-D', '_scratch']);

        // Remote diverges independently.
        await File('${scn.clone2}/feature.txt').writeAsString('remote v2\n');
        await _git(scn.clone2, ['add', '.']);
        await _git(scn.clone2, ['commit', '-qm', 'remote commit 2']);
        final remoteSha = await _revParse(scn.clone2, 'HEAD');
        await _git(
            scn.clone2, ['push', '-q', 'origin', 'HEAD:refs/pull/7/head']);

        final r = await fetchPrHeadToBranch(scn.clone1, 7, 'pull/7/head');
        expect(r, isA<PrCheckoutWouldClobber>(), reason: _outcomeLabel(r));
        final wc = r as PrCheckoutWouldClobber;
        expect(wc.localRef, 'pr-7');
        expect(wc.localTip, localTip);
        expect(wc.remoteTip, remoteSha);
        // The ref was NOT moved — local commit still reachable.
        expect(await _revParse(scn.clone1, 'pr-7'), localTip);
      } finally {
        await _safeCleanup(scn.root);
      }
    });

    test('(4) force overrides the guard and resets pr-<n> to the remote tip',
        () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        final first = await fetchPrHeadToBranch(scn.clone1, 7, 'pull/7/head');
        expect(first, isA<PrCheckoutOk>(), reason: _outcomeLabel(first));

        await _git(scn.clone1, ['checkout', '-q', '-b', '_scratch', 'pr-7']);
        await File('${scn.clone1}/local.txt').writeAsString('local only\n');
        await _git(scn.clone1, ['add', '.']);
        await _git(scn.clone1, ['commit', '-qm', 'local unpushed']);
        await _git(scn.clone1,
            ['branch', '-f', 'pr-7', await _revParse(scn.clone1, 'HEAD')]);
        await _git(scn.clone1, ['checkout', '-q', 'main']);
        await _git(scn.clone1, ['branch', '-q', '-D', '_scratch']);

        await File('${scn.clone2}/feature.txt').writeAsString('remote v2\n');
        await _git(scn.clone2, ['add', '.']);
        await _git(scn.clone2, ['commit', '-qm', 'remote commit 2']);
        final remoteSha = await _revParse(scn.clone2, 'HEAD');
        await _git(
            scn.clone2, ['push', '-q', 'origin', 'HEAD:refs/pull/7/head']);

        final r =
            await fetchPrHeadToBranch(scn.clone1, 7, 'pull/7/head', force: true);
        expect(r, isA<PrCheckoutOk>(), reason: _outcomeLabel(r));
        expect(await _revParse(scn.clone1, 'pr-7'), remoteSha);
        // Still on main — force resets the ref, never the checkout.
        expect(await _currentBranch(scn.clone1), 'main');
      } finally {
        await _safeCleanup(scn.root);
      }
    });

    test('(5) pr-<n> checked out in a worktree → branch -f refuses, typed failure',
        () async {
      final scn = await _scenarioWithPrRef('refs/pull/7/head');
      try {
        final first = await fetchPrHeadToBranch(scn.clone1, 7, 'pull/7/head');
        expect(first, isA<PrCheckoutOk>(), reason: _outcomeLabel(first));

        // Check pr-7 out in a linked worktree — `branch -f` refuses to move a
        // branch that is the HEAD of any worktree.
        final wtPath = '${scn.root.path}/wt-pr7';
        final add = await _git(scn.clone1, ['worktree', 'add', wtPath, 'pr-7']);
        expect(add.exitCode, 0, reason: add.stderr.toString());

        // Make the update non-trivial so it must actually move the ref.
        await File('${scn.clone2}/feature.txt').writeAsString('pr work v2\n');
        await _git(scn.clone2, ['add', '.']);
        await _git(scn.clone2, ['commit', '-qm', 'pr commit 2']);
        await _git(
            scn.clone2, ['push', '-q', 'origin', 'HEAD:refs/pull/7/head']);

        // force:true clears the guard, but `branch -f` still can't move a
        // checked-out branch — the documented failure mode.
        final r =
            await fetchPrHeadToBranch(scn.clone1, 7, 'pull/7/head', force: true);
        expect(r, isA<PrCheckoutFailed>(), reason: _outcomeLabel(r));
        expect((r as PrCheckoutFailed).error, isNotEmpty);
      } finally {
        await _safeCleanup(scn.root);
      }
    });

    test('(6) no remote configured → typed failure', () async {
      final root = await Directory.systemTemp.createTemp('manifold_noremote_');
      final repo = '${root.path}/repo';
      try {
        await _git(root.path, ['init', '-q', '-b', 'main', 'repo']);
        await _identity(repo);
        await File('$repo/README.md').writeAsString('root\n');
        await _git(repo, ['add', '.']);
        await _git(repo, ['commit', '-qm', 'root']);

        final r = await fetchPrHeadToBranch(repo, 7, 'pull/7/head');
        expect(r, isA<PrCheckoutFailed>(), reason: _outcomeLabel(r));
        expect((r as PrCheckoutFailed).error, isNotEmpty);
      } finally {
        await _safeCleanup(root);
      }
    });
  });

  group('classifyMergeTreeProbe — pure conflict classifier', () {
    test('exit 0 → clean, available, no conflicts', () {
      final p = classifyMergeTreeProbe(0, 'deadbeef\n', '');
      expect(p.mergeable, isTrue);
      expect(p.available, isTrue);
      expect(p.conflictingPaths, isEmpty);
      expect(p.versionUnsupported, isFalse);
    });

    test('exit 1 → conflicts parsed from lines after the tree SHA', () {
      final p = classifyMergeTreeProbe(
          1, 'treesha\nsrc/a.dart\nsrc/b.dart\n\n', '');
      expect(p.mergeable, isFalse);
      expect(p.available, isTrue);
      expect(p.conflictingPaths, ['src/a.dart', 'src/b.dart']);
    });

    test('unknown-option stderr → unavailable AND version-diagnosed', () {
      final p = classifyMergeTreeProbe(
          129, '', "error: unknown option `write-tree'");
      expect(p.available, isFalse);
      expect(p.versionUnsupported, isTrue);
    });

    test('unrelated failure → unavailable but NOT version-diagnosed', () {
      final p = classifyMergeTreeProbe(
          128, '', 'fatal: not something we can merge');
      expect(p.available, isFalse);
      expect(p.versionUnsupported, isFalse);
    });

    test('stderr classifier isolates the unknown-option signature', () {
      expect(mergeTreeStderrIsUnknownOption('error: unknown option `x`'),
          isTrue);
      expect(mergeTreeStderrIsUnknownOption('unknown switch \x60w\x60'), isTrue);
      expect(mergeTreeStderrIsUnknownOption('fatal: bad revision'), isFalse);
      expect(mergeTreeStderrIsUnknownOption('index.lock exists'), isFalse);
    });
  });

  group('runForgeCli — process-spawn containment', () {
    test('a missing binary degrades to a non-zero result, never a throw',
        () async {
      final dir = await Directory.systemTemp.createTemp('manifold_bin_');
      try {
        // Would throw ProcessException without the containment; the test
        // failing to complete (rather than asserting) would signal a leak.
        final r = await runForgeCli(
          'gh-does-not-exist-xyz',
          dir.path,
          ['pr', 'list'],
        );
        expect(r.exitCode, isNot(0));
        expect(r.stderr.toString(), contains('not found on PATH'));
      } finally {
        await _safeCleanup(dir);
      }
    });
  });
}
