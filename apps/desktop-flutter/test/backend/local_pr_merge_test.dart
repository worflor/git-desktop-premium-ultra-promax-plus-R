import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/backend/merge_session.dart';

/// End-to-end tests for the local-PR merge engine ([mergeBranchIntoBase])
/// against real temp repos. The headline claims under test:
///   • the merge runs WHERE the base is already checked out and never
///     switches another worktree's HEAD;
///   • a base checked out nowhere advances purely at the ref level
///     (merge-tree → commit-tree → CAS update-ref) with no working tree
///     touched, and a ref-level conflict leaves every ref unmoved;
///   • merged state is verified from git, and the CAS guard makes a raced
///     base-move a clean typed failure rather than corruption.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String repo;

  Future<ProcessResult> git(String at, List<String> args) => Process.run(
        'git',
        args,
        workingDirectory: at,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

  Future<void> config(String at) async {
    await git(at, ['config', 'user.email', 'a@b.c']);
    await git(at, ['config', 'user.name', 'test']);
    await git(at, ['config', 'core.autocrlf', 'false']);
    await git(at, ['config', 'commit.gpgsign', 'false']);
  }

  File wf(String at, String path) =>
      File('$at${Platform.pathSeparator}$path');

  Future<String> tip(String ref) async =>
      (await git(repo, ['rev-parse', ref])).stdout.toString().trim();

  Future<String> headBranch(String at) async =>
      (await git(at, ['symbolic-ref', '--short', 'HEAD']))
          .stdout
          .toString()
          .trim();

  Future<int> parentCount(String ref) async =>
      (await git(repo, ['rev-list', '--parents', '-n', '1', ref]))
          .stdout
          .toString()
          .trim()
          .split(' ')
          .length -
      1;

  Future<bool> isAncestor(String a, String b) async =>
      (await git(repo, ['merge-base', '--is-ancestor', a, b])).exitCode == 0;

  Future<bool> isClean(String at) async =>
      (await git(at, ['status', '--porcelain'])).stdout.toString().trim().isEmpty;

  /// Repo `repo` on branch `main` with one commit (README="A"). A `base`
  /// branch is forked off main (identical), then `feature` is forked off main
  /// and given a commit adding feat.txt. So base has no unique commits and
  /// feature is one ahead — a merge that itself never conflicts. When
  /// [diverge] is set, base ALSO edits README so a merge into base conflicts
  /// on README.
  Future<void> seed({bool diverge = false}) async {
    root = await Directory.systemTemp.createTemp('gdpu_localpr_');
    repo = '${root.path}${Platform.pathSeparator}repo';
    await Directory(repo).create(recursive: true);
    await git(repo, ['init', '-q', '-b', 'main']);
    await config(repo);
    await wf(repo, 'README.md').writeAsString('A\n');
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'root']);

    await git(repo, ['branch', 'base']);
    await git(repo, ['checkout', '-q', '-b', 'feature']);
    await wf(repo, 'feat.txt').writeAsString('feature payload\n');
    if (diverge) await wf(repo, 'README.md').writeAsString('FEATURE\n');
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'feature work']);
    await git(repo, ['checkout', '-q', 'main']);

    if (diverge) {
      // Give base a conflicting edit to README on top of root.
      await git(repo, ['checkout', '-q', 'base']);
      await wf(repo, 'README.md').writeAsString('BASE\n');
      await git(repo, ['commit', '-qam', 'base edit']);
      await git(repo, ['checkout', '-q', 'main']);
    }
  }

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  test('mergeCommit runs in the worktree that holds base, never moving main',
      () async {
    await seed();
    // Check base out in a LINKED worktree; main worktree stays on `main`.
    final wtBase = '${root.path}${Platform.pathSeparator}wt-base';
    await git(repo, ['worktree', 'add', '-q', wtBase, 'base']);
    final baseBefore = await tip('base');

    final result = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.mergeCommit,
    );

    expect(result.outcome, isA<MergeClean>());
    expect(result.conflictWorktree, isNull);
    // base advanced with a real two-parent merge commit.
    expect(await tip('base'), isNot(baseBefore));
    expect(await parentCount('base'), 2);
    expect(await isAncestor('feature', 'base'), isTrue);
    // The main worktree's HEAD did NOT move — no hijack.
    expect(await headBranch(repo), 'main');
    expect(await tip('main'), await tip('HEAD'));
    // The merge landed in the base worktree; its tree has feat.txt.
    expect(await wf(wtBase, 'feat.txt').exists(), isTrue);

    await git(repo, ['worktree', 'remove', '--force', wtBase]);
  });

  test('zero-checkout mergeCommit: base checked out nowhere advances via refs',
      () async {
    await seed();
    // No worktree holds base (main worktree is on `main`).
    final baseBefore = await tip('base');
    final mainBefore = await tip('main');

    final result = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.mergeCommit,
    );

    expect(result.outcome, isA<MergeClean>());
    expect(result.conflictWorktree, isNull);
    expect(await tip('base'), isNot(baseBefore));
    expect(await parentCount('base'), 2);
    expect(await isAncestor('feature', 'base'), isTrue);
    // Nothing else moved and no working tree was touched.
    expect(await tip('main'), mainBefore);
    expect(await headBranch(repo), 'main');
    expect(await isClean(repo), isTrue);
    // main worktree never received feat.txt (its ref never advanced).
    expect(await wf(repo, 'feat.txt').exists(), isFalse);
  });

  test('zero-checkout conflict: MergeConflicted, refs unmoved, tree untouched',
      () async {
    await seed(diverge: true);
    final baseBefore = await tip('base');

    final result = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.mergeCommit,
    );

    expect(result.outcome, isA<MergeConflicted>());
    expect((result.outcome as MergeConflicted).paths, contains('README.md'));
    expect(result.conflictWorktree, isNull,
        reason: 'ref-level conflict never touched a working tree');
    // The base ref is exactly where it was — a pure prediction.
    expect(await tip('base'), baseBefore);
    expect(await isAncestor('feature', 'base'), isFalse);
    expect(await isClean(repo), isTrue);
  });

  test('squash: single-parent commit with the merged tree and subject',
      () async {
    await seed();
    final result = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.squash,
      squashSubject: 'Squash feature',
    );

    expect(result.outcome, isA<MergeClean>());
    // One parent (a squash collapses history), not a merge commit.
    expect(await parentCount('base'), 1);
    // The squash's tree equals feature's tree (base had no unique changes).
    expect(await tip('base^{tree}'), await tip('feature^{tree}'));
    final subject =
        (await git(repo, ['log', '-1', '--format=%s', 'base'])).stdout.toString().trim();
    expect(subject, 'Squash feature');
    // Verified via cherry: feature's patch is now present in base.
    expect(await wf(repo, 'feat.txt').exists(), isFalse); // main worktree
  });

  test('CAS: a raced base move is a clean typed failure, not corruption',
      () async {
    await seed();
    // A second head to merge concurrently into the same base.
    await git(repo, ['checkout', '-q', '-b', 'feature2', 'feature']);
    await wf(repo, 'feat2.txt').writeAsString('second payload\n');
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'feature2 work']);
    await git(repo, ['checkout', '-q', 'main']);
    final baseBefore = await tip('base');

    // Both read the same base tip, then race on update-ref. Exactly one CAS
    // write wins; the loser fails cleanly with no ref corruption.
    final results = await Future.wait([
      mergeBranchIntoBase(
          repoPath: repo,
          branch: 'feature',
          baseRef: 'base',
          method: BranchMergeMethod.mergeCommit),
      mergeBranchIntoBase(
          repoPath: repo,
          branch: 'feature2',
          baseRef: 'base',
          method: BranchMergeMethod.mergeCommit),
    ]);

    final cleans = results.where((r) => r.outcome is MergeClean).toList();
    final failures = results.where((r) => r.outcome is MergeFailed).toList();
    expect(cleans, hasLength(1), reason: 'one writer wins the CAS');
    expect(failures, hasLength(1), reason: 'the loser fails, does not clobber');
    expect((failures.single.outcome as MergeFailed).message,
        contains('moved'));
    // Base is a single valid two-parent merge commit — never corrupted, never
    // left at the pre-merge tip.
    expect(await tip('base'), isNot(baseBefore));
    expect(await parentCount('base'), 2);
    expect((await git(repo, ['cat-file', '-t', await tip('base')]))
            .stdout
            .toString()
            .trim(),
        'commit');
  });

  test('verified merged state: clean merge is an ancestor; conflict never is',
      () async {
    await seed();
    final clean = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.mergeCommit,
    );
    expect(clean.outcome, isA<MergeClean>());
    expect(await isAncestor('feature', 'base'), isTrue);

    // A deliberately-conflicting merge must NOT report clean/merged.
    await seed(diverge: true);
    final conflicted = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.mergeCommit,
    );
    expect(conflicted.outcome, isNot(isA<MergeClean>()));
    expect(await isAncestor('feature', 'base'), isFalse);
  });

  test('squash of a MULTI-commit branch verifies (tree equality, not cherry)',
      () async {
    // The exact repro that failed: cherry-based verification rejected a squash
    // of N≥2 commits because per-commit patch-ids match nothing. Feature here
    // is three commits ahead; verification must pass via tree equality.
    await seed();
    final wtBase = '${root.path}${Platform.pathSeparator}wt-base';
    await git(repo, ['worktree', 'add', '-q', wtBase, 'base']);
    // Two more commits on feature so the squash folds THREE commits into one.
    await git(repo, ['checkout', '-q', 'feature']);
    await wf(repo, 'feat2.txt').writeAsString('more\n');
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'feature work 2']);
    await wf(repo, 'feat3.txt').writeAsString('even more\n');
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'feature work 3']);
    await git(repo, ['checkout', '-q', 'main']);
    final baseBefore = await tip('base');

    final result = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.squash,
      squashSubject: 'Squash 3-commit feature',
    );

    expect(result.outcome, isA<MergeClean>(),
        reason: 'a clean 3-commit squash must verify, not report MergeFailed');
    // Base advanced to a single-parent squash commit whose tree equals
    // feature's tree (base had no unique changes).
    expect(await tip('base'), isNot(baseBefore));
    expect(await parentCount('base'), 1);
    expect(await tip('base^{tree}'), await tip('feature^{tree}'));

    await git(repo, ['worktree', 'remove', '--force', wtBase]);
  });

  test('squash of a SINGLE-commit branch still verifies (no regression)',
      () async {
    await seed();
    final wtBase = '${root.path}${Platform.pathSeparator}wt-base';
    await git(repo, ['worktree', 'add', '-q', wtBase, 'base']);
    final baseBefore = await tip('base');

    final result = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.squash,
      squashSubject: 'Squash 1-commit feature',
    );

    expect(result.outcome, isA<MergeClean>());
    expect(await tip('base'), isNot(baseBefore));
    expect(await parentCount('base'), 1);
    expect(await tip('base^{tree}'), await tip('feature^{tree}'));

    await git(repo, ['worktree', 'remove', '--force', wtBase]);
  });

  test('untracked scratch file in target worktree does NOT block a merge',
      () async {
    await seed();
    final wtBase = '${root.path}${Platform.pathSeparator}wt-base';
    await git(repo, ['worktree', 'add', '-q', wtBase, 'base']);
    // A stray untracked file that does not collide with anything incoming.
    await wf(wtBase, 'scratch.tmp').writeAsString('junk\n');
    final baseBefore = await tip('base');

    final result = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.mergeCommit,
    );

    expect(result.outcome, isA<MergeClean>(),
        reason: 'an untracked file must not gate the merge');
    expect(await tip('base'), isNot(baseBefore));
    expect(await isAncestor('feature', 'base'), isTrue);
    // The scratch file rode along untouched.
    expect(await wf(wtBase, 'scratch.tmp').exists(), isTrue);

    await git(repo, ['worktree', 'remove', '--force', wtBase]);
  });

  test('untracked file in the rebase worktrees does NOT block the rebase',
      () async {
    await seed();
    // Rebase needs both refs checked out in worktrees.
    final wtBase = '${root.path}${Platform.pathSeparator}wt-base';
    final wtFeature = '${root.path}${Platform.pathSeparator}wt-feature';
    await git(repo, ['worktree', 'add', '-q', wtBase, 'base']);
    await git(repo, ['worktree', 'add', '-q', wtFeature, 'feature']);
    await wf(wtFeature, 'scratch.tmp').writeAsString('junk\n');
    await wf(wtBase, 'other.tmp').writeAsString('junk\n');

    final result = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.rebase,
    );

    expect(result.outcome, isA<MergeClean>(),
        reason: 'untracked files must not gate the rebase');
    expect(await isAncestor('feature', 'base'), isTrue);

    await git(repo, ['worktree', 'remove', '--force', wtFeature]);
    await git(repo, ['worktree', 'remove', '--force', wtBase]);
  });

  test('a branch add over an untracked file → typed block, worktree unharmed',
      () async {
    await seed();
    final wtBase = '${root.path}${Platform.pathSeparator}wt-base';
    await git(repo, ['worktree', 'add', '-q', wtBase, 'base']);
    // feature adds feat.txt; plant a colliding untracked feat.txt on base.
    await wf(wtBase, 'feat.txt').writeAsString('squatter content\n');
    final baseBefore = await tip('base');

    final result = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.mergeCommit,
    );

    expect(result.outcome, isA<MergeBlockedByLocalChanges>(),
        reason: 'git refuses to overwrite an untracked file; map it typed');
    expect((result.outcome as MergeBlockedByLocalChanges).paths,
        contains('feat.txt'));
    // Nothing landed and the squatter file is exactly as it was.
    expect(await tip('base'), baseBefore);
    expect(await wf(wtBase, 'feat.txt').readAsString(), 'squatter content\n');

    await git(repo, ['worktree', 'remove', '--force', wtBase]);
  });

  test('a TRACKED modification still blocks with MergeBlockedByLocalChanges',
      () async {
    await seed();
    final wtBase = '${root.path}${Platform.pathSeparator}wt-base';
    await git(repo, ['worktree', 'add', '-q', wtBase, 'base']);
    // Modify a TRACKED file in the base worktree.
    await wf(wtBase, 'README.md').writeAsString('locally edited\n');
    final baseBefore = await tip('base');

    final result = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.mergeCommit,
    );

    expect(result.outcome, isA<MergeBlockedByLocalChanges>());
    expect((result.outcome as MergeBlockedByLocalChanges).paths,
        contains('README.md'));
    expect(await tip('base'), baseBefore);

    await git(repo, ['worktree', 'remove', '--force', wtBase]);
  });

  test('rebase with base checked out nowhere yields MergeNeedsCheckout',
      () async {
    await seed();
    final baseBefore = await tip('base');
    final featureBefore = await tip('feature');

    final result = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.rebase,
    );

    expect(result.outcome, isA<MergeNeedsCheckout>());
    expect((result.outcome as MergeNeedsCheckout).message,
        contains('checked out'));
    // Nothing moved — the engine refused rather than conjuring a worktree.
    expect(await tip('base'), baseBefore);
    expect(await tip('feature'), featureBefore);
  });
}
