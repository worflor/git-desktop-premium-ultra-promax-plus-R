import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/backend/merge_session.dart';
import 'package:git_desktop/features/changes/merge_conflict_flow.dart'
    show gatherConflictFiles;

/// End-to-end tests for the unified merge engine against real git repos.
/// They prove the headline claim: a pull into a dirty working tree is
/// reconciled with `git merge-file` and finalised with plain plumbing —
/// never a stash — and that history topology comes out correct.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String origin;
  late String work;

  Future<ProcessResult> git(String repo, List<String> args) => Process.run(
        'git',
        args,
        workingDirectory: repo,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

  Future<void> config(String repo) async {
    await git(repo, ['config', 'user.email', 'a@b.c']);
    await git(repo, ['config', 'user.name', 'test']);
    await git(repo, ['config', 'core.autocrlf', 'false']);
    await git(repo, ['config', 'commit.gpgsign', 'false']);
  }

  File wf(String repo, String path) =>
      File('$repo${Platform.pathSeparator}$path');

  /// origin: base (README l1..l5) → advance l2→REMOTE2.
  /// work: clone, reset one commit back so it is *behind*. When [diverged],
  /// add a local commit touching a far line (l4) so HEAD is not an ancestor
  /// of upstream — a merge-commit topology that does not itself conflict.
  Future<void> seed({required bool diverged}) async {
    root = await Directory.systemTemp.createTemp('gdpu_merge_');
    origin = '${root.path}${Platform.pathSeparator}origin';
    work = '${root.path}${Platform.pathSeparator}work';
    await Directory(origin).create(recursive: true);
    await git(origin, ['init', '-q', '-b', 'main']);
    await config(origin);
    await wf(origin, 'README.md').writeAsString('l1\nl2\nl3\nl4\nl5\n');
    await wf(origin, 'other.txt').writeAsString('keep\n');
    await git(origin, ['add', '-A']);
    await git(origin, ['commit', '-qm', 'base']);
    await wf(origin, 'README.md').writeAsString('l1\nREMOTE2\nl3\nl4\nl5\n');
    await git(origin, ['commit', '-qam', 'remote']);

    await git(root.path, ['clone', '-q', origin, 'work']);
    await config(work);
    // Put work one commit behind origin's tip.
    await git(work, ['reset', '-q', '--hard', 'HEAD~1']);
    if (diverged) {
      await wf(work, 'README.md').writeAsString('l1\nl2\nl3\nLOCALCOMMIT\nl5\n');
      await git(work, ['commit', '-qam', 'local work']);
    }
  }

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  Future<String> head(String repo) async =>
      (await git(repo, ['rev-parse', 'HEAD'])).stdout.toString().trim();

  Future<int> parentCount(String repo) async => (await git(
              repo, ['rev-list', '--parents', '-n', '1', 'HEAD']))
          .stdout
          .toString()
          .trim()
          .split(' ')
          .length -
      1;

  test('dirty fast-forward pull: merge-file reconcile, reset finalize, no stash',
      () async {
    await seed(diverged: false);
    // Overlapping dirty edit on the same line the incoming commit changed.
    await wf(work, 'README.md').writeAsString('l1\nLOCAL2\nl3\nl4\nl5\n');

    final prep = await prepareMergePull(work);
    expect(prep.error, isNull);
    expect(prep.upToDate, isFalse);
    expect(prep.dirty, isTrue, reason: 'README is locally modified + incoming');
    expect(prep.topology, MergeTopology.fastForward);
    expect(prep.blockingPaths, ['README.md']);

    final reconciled = await reconcileDirtyMerge(work, prep);
    final conflicted = reconciled.where((f) => f.conflicted).toList();
    expect(conflicted, hasLength(1));
    expect(conflicted.single.path, 'README.md');
    expect(conflicted.single.mergedText, contains('<<<<<<<'));
    expect(conflicted.single.mergedText, contains('REMOTE2'));
    expect(conflicted.single.mergedText, contains('LOCAL2'));

    // Simulate the editor: write the resolved file + stage it.
    await wf(work, 'README.md').writeAsString('l1\nMERGED2\nl3\nl4\nl5\n');
    await git(work, ['add', '--', 'README.md']);

    final fin = await finalizeReconciledMerge(work, prep, reconciled);
    expect(fin.ok, isTrue, reason: fin.error ?? '');

    // Branch advanced to the incoming tip; resolution kept; nothing stashed.
    final upstream =
        (await git(work, ['rev-parse', 'origin/main'])).stdout.toString().trim();
    expect(await head(work), upstream);
    expect(await File('$work${Platform.pathSeparator}.git'
            '${Platform.pathSeparator}MERGE_HEAD').exists(),
        isFalse);
    final stash = (await git(work, ['stash', 'list'])).stdout.toString().trim();
    expect(stash, isEmpty);
    final status =
        (await git(work, ['status', '--porcelain'])).stdout.toString();
    expect(status, contains('README.md'),
        reason: 'kept resolution shows as a working-tree modification');
    expect(await wf(work, 'README.md').readAsString(),
        'l1\nMERGED2\nl3\nl4\nl5\n');
  });

  test('dirty non-overlapping pull auto-resolves with no conflicts', () async {
    await seed(diverged: false);
    // Local edit to a far line (l5); incoming changed l2 → no overlap.
    await wf(work, 'README.md').writeAsString('l1\nl2\nl3\nl4\nLOCAL5\n');

    final prep = await prepareMergePull(work);
    expect(prep.dirty, isTrue);
    final reconciled = await reconcileDirtyMerge(work, prep);
    expect(reconciled.where((f) => f.conflicted), isEmpty,
        reason: 'non-overlapping edits merge cleanly');
    // merge-file produced the union: incoming REMOTE2 + local LOCAL5.
    expect(reconciled.single.mergedText, contains('REMOTE2'));
    expect(reconciled.single.mergedText, contains('LOCAL5'));

    final fin = await finalizeReconciledMerge(work, prep, reconciled);
    expect(fin.ok, isTrue, reason: fin.error ?? '');
    expect(await wf(work, 'README.md').readAsString(),
        'l1\nREMOTE2\nl3\nl4\nLOCAL5\n');
  });

  test('dirty merge-commit pull records a two-parent commit, keeps unrelated edits',
      () async {
    await seed(diverged: true);
    // Overlap on README + an unrelated dirty edit that must NOT be committed.
    await wf(work, 'README.md')
        .writeAsString('l1\nLOCAL2\nl3\nLOCALCOMMIT\nl5\n');
    await wf(work, 'other.txt').writeAsString('keep\nUNRELATED\n');

    final prep = await prepareMergePull(work);
    expect(prep.topology, MergeTopology.mergeCommit);
    expect(prep.dirty, isTrue);

    final reconciled = await reconcileDirtyMerge(work, prep);
    expect(reconciled.where((f) => f.conflicted), hasLength(1));

    // Editor resolves README to a merged form.
    await wf(work, 'README.md')
        .writeAsString('l1\nMERGED2\nl3\nLOCALCOMMIT\nl5\n');
    await git(work, ['add', '--', 'README.md']);

    final fin = await finalizeReconciledMerge(work, prep, reconciled);
    expect(fin.ok, isTrue, reason: fin.error ?? '');

    expect(await parentCount(work), 2, reason: 'merge commit has two parents');
    final committed =
        (await git(work, ['show', 'HEAD:README.md'])).stdout.toString();
    expect(committed, contains('MERGED2'));
    // The unrelated edit stayed in the working tree, out of the merge commit.
    final status =
        (await git(work, ['status', '--porcelain'])).stdout.toString();
    expect(status, contains('other.txt'));
  });

  test('dirty merge-commit does NOT sweep pre-staged unrelated changes',
      () async {
    await seed(diverged: true);
    await wf(work, 'README.md')
        .writeAsString('l1\nLOCAL2\nl3\nLOCALCOMMIT\nl5\n');
    // The user has an UNRELATED file staged before pulling.
    await wf(work, 'other.txt').writeAsString('keep\nSTAGED-UNRELATED\n');
    await git(work, ['add', 'other.txt']);

    final prep = await prepareMergePull(work);
    expect(prep.topology, MergeTopology.mergeCommit);
    final reconciled = await reconcileDirtyMerge(work, prep);
    // Resolve README (the only incoming path).
    await wf(work, 'README.md')
        .writeAsString('l1\nMERGED2\nl3\nLOCALCOMMIT\nl5\n');
    await git(work, ['add', '--', 'README.md']);

    final fin = await finalizeReconciledMerge(work, prep, reconciled);
    expect(fin.ok, isTrue, reason: fin.error ?? '');

    expect(await parentCount(work), 2);
    // The merge commit must contain HEAD's other.txt, NOT the staged edit.
    final committed =
        (await git(work, ['show', 'HEAD:other.txt'])).stdout.toString();
    expect(committed, 'keep\n',
        reason: 'pre-staged unrelated change must NOT be in the merge commit');
    // …the user's edit survives in the working tree…
    expect(await wf(work, 'other.txt').readAsString(), 'keep\nSTAGED-UNRELATED\n');
    // …AND the curated staging selection survives the merge.
    final staged =
        (await git(work, ['diff', '--cached', '--name-only'])).stdout.toString();
    expect(staged, contains('other.txt'),
        reason: 'pre-staged unrelated change stays staged');
    expect((await git(work, ['show', ':other.txt'])).stdout.toString(),
        'keep\nSTAGED-UNRELATED\n',
        reason: 'the staged content is the user\'s edit, not HEAD');
  });

  test('dirty fast-forward preserves an unrelated pre-staged file', () async {
    await seed(diverged: false); // behind-only → fast-forward
    await wf(work, 'README.md').writeAsString('l1\nLOCAL2\nl3\nl4\nl5\n');
    await wf(work, 'other.txt').writeAsString('keep\nSTAGED\n');
    await git(work, ['add', 'other.txt']);

    final prep = await prepareMergePull(work);
    expect(prep.topology, MergeTopology.fastForward);
    final reconciled = await reconcileDirtyMerge(work, prep);
    await wf(work, 'README.md').writeAsString('l1\nMERGED2\nl3\nl4\nl5\n');
    await git(work, ['add', '--', 'README.md']);

    final fin = await finalizeReconciledMerge(work, prep, reconciled);
    expect(fin.ok, isTrue, reason: fin.error ?? '');

    final staged =
        (await git(work, ['diff', '--cached', '--name-only'])).stdout.toString();
    expect(staged, contains('other.txt'),
        reason: 'unrelated staged file survives the FF reset');
    expect(staged, isNot(contains('README.md')),
        reason: 'the merged incoming file is left unstaged on the FF tip');
  });

  test('clean tree: native merge surfaces conflicts, commit concludes them',
      () async {
    await seed(diverged: false); // behind + clean working tree
    // A committed local edit to the SAME line incoming changed → diverged AND
    // overlapping, so the clean-tree native merge genuinely conflicts.
    await wf(work, 'README.md').writeAsString('l1\nLOCAL2C\nl3\nl4\nl5\n');
    await git(work, ['commit', '-qam', 'local edit l2']);

    final prep = await prepareMergePull(work);
    expect(prep.dirty, isFalse);
    expect(prep.topology, MergeTopology.mergeCommit);

    final outcome = await runNativeMerge(work, prep);
    expect(outcome, isA<MergeConflicted>());
    expect((outcome as MergeConflicted).paths, contains('README.md'));

    // git left MERGE_HEAD + markers; resolve + conclude.
    await wf(work, 'README.md').writeAsString('l1\nMERGED2\nl3\nl4\nl5\n');
    await git(work, ['add', '--', 'README.md']);
    final c = await commitResolvedMerge(work);
    expect(c.ok, isTrue, reason: c.error ?? '');
    expect(await parentCount(work), 2);
  });

  test('reconcileDirtyMerge keeps the tree pristine — cancelling loses nothing',
      () async {
    await seed(diverged: false);
    // The user's uncommitted overlapping edit.
    await wf(work, 'README.md').writeAsString('l1\nLOCAL2\nl3\nl4\nl5\n');
    final indexBefore =
        (await git(work, ['ls-files', '--stage'])).stdout.toString();
    final headBefore = await head(work);

    final prep = await prepareMergePull(work);
    final reconciled = await reconcileDirtyMerge(work, prep);
    expect(reconciled.where((f) => f.conflicted), isNotEmpty,
        reason: 'the overlap produces an in-memory conflict');

    // The reconcile is IN MEMORY only — this is what makes cancelling safe.
    // Working tree still holds the user's pristine edit (no markers written),
    // the index is untouched, HEAD has not moved, and no merge is in progress.
    expect(await wf(work, 'README.md').readAsString(),
        'l1\nLOCAL2\nl3\nl4\nl5\n',
        reason: 'reconcile must not write merged markers to the working tree');
    expect((await git(work, ['ls-files', '--stage'])).stdout.toString(),
        indexBefore,
        reason: 'reconcile must not touch the index');
    expect(await head(work), headBefore, reason: 'reconcile must not move HEAD');
    expect(
        await File('$work${Platform.pathSeparator}.git'
                '${Platform.pathSeparator}MERGE_HEAD')
            .exists(),
        isFalse,
        reason: 'no merge is persisted until finalize');
  });

  test('multi-conflict rebase: a halt at the next conflict is UU, not failure',
      () async {
    final repo = (await Directory.systemTemp.createTemp('gdpu_reb_')).path;
    await git(repo, ['init', '-qb', 'main']);
    await config(repo);
    await wf(repo, 'f.txt').writeAsString('l1\nl2\nl3\n');
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'base']);
    await git(repo, ['checkout', '-qb', 'feat']);
    await wf(repo, 'f.txt').writeAsString('A1\nl2\nl3\n'); // c1 touches line1
    await git(repo, ['commit', '-qam', 'c1']);
    await wf(repo, 'f.txt').writeAsString('A1\nl2\nB3\n'); // c2 touches line3
    await git(repo, ['commit', '-qam', 'c2']);
    await git(repo, ['checkout', '-q', 'main']);
    await wf(repo, 'f.txt').writeAsString('M1\nl2\nM3\n'); // conflicts both
    await git(repo, ['commit', '-qam', 'main2']);
    await git(repo, ['checkout', '-q', 'feat']);

    final reb = await git(repo, ['rebase', 'main']);
    expect(reb.exitCode, isNot(0), reason: 'c1 conflicts');
    expect(await isRebaseInProgress(repo), isTrue);

    // Resolve step 1, then continue — git HALTS at c2's conflict.
    await wf(repo, 'f.txt').writeAsString('RES1\nl2\nM3\n');
    await git(repo, ['add', 'f.txt']);
    final cont1 = await continueRebase(repo);
    expect(cont1.ok, isFalse, reason: 'continue halts at c2, exit != 0');
    expect(await isRebaseInProgress(repo), isTrue);
    // THE FIX'S PREMISE: a fresh UU set means "next conflict", not failure.
    expect(await hasUnmergedPaths(repo), isTrue);

    // Resolve step 2 → the rebase completes cleanly.
    await wf(repo, 'f.txt').writeAsString('RES1\nl2\nRES3\n');
    await git(repo, ['add', 'f.txt']);
    final cont2 = await continueRebase(repo);
    expect(cont2.ok, isTrue, reason: 'final continue completes the rebase');
    expect(await isRebaseInProgress(repo), isFalse);
    expect(await hasUnmergedPaths(repo), isFalse);
    await Directory(repo).delete(recursive: true);
  });

  test('up-to-date pull is a no-op', () async {
    await seed(diverged: false);
    // Advance work to the upstream so nothing is incoming.
    await git(work, ['merge', '--ff-only', 'origin/main']);
    final prep = await prepareMergePull(work);
    expect(prep.upToDate, isTrue);
  });

  test('rebase topology treats an unrelated tracked edit as blocking; '
      'merge does not', () async {
    await seed(diverged: false); // behind-only, clean
    // Edit a tracked file the incoming commit does NOT touch (incoming = README).
    await wf(work, 'other.txt').writeAsString('keep\nUNRELATED\n');

    final asRebase = await prepareMergePull(work, rebase: true);
    expect(asRebase.topology, MergeTopology.rebase);
    expect(asRebase.dirty, isTrue,
        reason: 'rebase refuses ANY tracked modification');
    expect(asRebase.blockingPaths, contains('other.txt'));

    final asMerge = await prepareMergePull(work, rebase: false);
    expect(asMerge.topology, MergeTopology.fastForward);
    expect(asMerge.dirty, isFalse,
        reason: 'merge only balks on an overlapping incoming path');
  });

  test('untracked files do not block a rebase', () async {
    await seed(diverged: false);
    await wf(work, 'brand-new.txt').writeAsString('untracked\n');
    final prep = await prepareMergePull(work, rebase: true);
    expect(prep.dirty, isFalse,
        reason: 'an untracked file does not stop git rebase');
  });

  test('dirty pull takes an unmodified incoming binary as raw bytes (no '
      'corruption)', () async {
    // origin: text + a binary asset; advance the binary upstream.
    root = await Directory.systemTemp.createTemp('gdpu_bin_');
    origin = '${root.path}${Platform.pathSeparator}origin';
    work = '${root.path}${Platform.pathSeparator}work';
    await Directory(origin).create(recursive: true);
    await git(origin, ['init', '-qb', 'main']);
    await config(origin);
    await wf(origin, 'README.md').writeAsString('l1\nl2\n');
    final binV1 = List<int>.generate(300, (i) => i % 256); // contains NUL
    await File('$origin${Platform.pathSeparator}asset.bin').writeAsBytes(binV1);
    await git(origin, ['add', '-A']);
    await git(origin, ['commit', '-qm', 'base']);
    final binV2 = List<int>.generate(300, (i) => (i * 7) % 256);
    await File('$origin${Platform.pathSeparator}asset.bin').writeAsBytes(binV2);
    await git(origin, ['commit', '-qam', 'bump binary']);

    await git(root.path, ['clone', '-q', origin, 'work']);
    await config(work);
    await git(work, ['reset', '-q', '--hard', 'HEAD~1']); // behind by the binary bump
    await git(work, ['fetch', '-q', 'origin']);
    // Dirty an UNRELATED text file so the dirty path is taken.
    await wf(work, 'README.md').writeAsString('l1\nLOCAL\n');

    final prep = await prepareMergePull(work);
    expect(prep.incomingPaths, contains('asset.bin'));
    final reconciled = await reconcileDirtyMerge(work, prep);
    final bin = reconciled.firstWhere((f) => f.path == 'asset.bin');
    expect(bin.binary, isTrue);
    expect(bin.conflicted, isFalse, reason: 'binary unmodified locally');
    expect(bin.binaryBytes, binV2, reason: 'exact incoming bytes, not decoded');

    final fin = await finalizeReconciledMerge(work, prep, reconciled);
    expect(fin.ok, isTrue, reason: fin.error ?? '');
    final onDisk =
        await File('$work${Platform.pathSeparator}asset.bin').readAsBytes();
    expect(onDisk, binV2, reason: 'binary written byte-exact, not corrupted');
  });

  test('dirty pull blocks on a binary changed on both sides', () async {
    root = await Directory.systemTemp.createTemp('gdpu_binc_');
    origin = '${root.path}${Platform.pathSeparator}origin';
    work = '${root.path}${Platform.pathSeparator}work';
    await Directory(origin).create(recursive: true);
    await git(origin, ['init', '-qb', 'main']);
    await config(origin);
    await File('$origin${Platform.pathSeparator}a.bin')
        .writeAsBytes([1, 0, 2, 0, 3]);
    await git(origin, ['add', '-A']);
    await git(origin, ['commit', '-qm', 'base']);
    await File('$origin${Platform.pathSeparator}a.bin')
        .writeAsBytes([1, 0, 9, 0, 3]); // upstream change
    await git(origin, ['commit', '-qam', 'theirs']);

    await git(root.path, ['clone', '-q', origin, 'work']);
    await config(work);
    await git(work, ['reset', '-q', '--hard', 'HEAD~1']);
    await git(work, ['fetch', '-q', 'origin']);
    // Local (uncommitted) change to the SAME binary → both-sides-changed.
    await File('$work${Platform.pathSeparator}a.bin')
        .writeAsBytes([1, 0, 7, 0, 3]);

    final prep = await prepareMergePull(work);
    final reconciled = await reconcileDirtyMerge(work, prep);
    final bin = reconciled.firstWhere((f) => f.path == 'a.bin');
    expect(bin.binary, isTrue);
    expect(bin.conflicted, isTrue, reason: 'binary changed both sides');
    // The working tree must be untouched (reconcile is non-mutating).
    expect(await File('$work${Platform.pathSeparator}a.bin').readAsBytes(),
        [1, 0, 7, 0, 3]);
  });

  test('dirty pull materializes a clean incoming add under a NEW directory',
      () async {
    root = await Directory.systemTemp.createTemp('gdpu_newdir_');
    origin = '${root.path}${Platform.pathSeparator}origin';
    work = '${root.path}${Platform.pathSeparator}work';
    final sep = Platform.pathSeparator;
    await Directory(origin).create(recursive: true);
    await git(origin, ['init', '-qb', 'main']);
    await config(origin);
    await wf(origin, 'README.md').writeAsString('a\nb\n');
    await git(origin, ['add', '-A']);
    await git(origin, ['commit', '-qm', 'base']);
    // Upstream: change README AND add a file under a brand-new folder.
    await wf(origin, 'README.md').writeAsString('a\nUP\n');
    await Directory('$origin${sep}new${sep}sub').create(recursive: true);
    await File('$origin${sep}new${sep}sub${sep}added.txt')
        .writeAsString('hello\n');
    await git(origin, ['add', '-A']);
    await git(origin, ['commit', '-qm', 'add under new dir']);

    await git(root.path, ['clone', '-q', origin, 'work']);
    await config(work);
    await git(work, ['reset', '-q', '--hard', 'HEAD~1']);
    await git(work, ['fetch', '-q', 'origin']);
    await wf(work, 'README.md').writeAsString('a\nLOCAL\n'); // overlap → dirty

    final prep = await prepareMergePull(work);
    expect(prep.incomingPaths, contains('new/sub/added.txt'));
    final reconciled = await reconcileDirtyMerge(work, prep);
    expect(
        reconciled.firstWhere((f) => f.path == 'new/sub/added.txt').conflicted,
        isFalse);
    // Resolve the README overlap.
    await wf(work, 'README.md').writeAsString('a\nMERGED\n');
    await git(work, ['add', '--', 'README.md']);

    final fin = await finalizeReconciledMerge(work, prep, reconciled);
    expect(fin.ok, isTrue, reason: fin.error ?? '');
    expect(await File('$work${sep}new${sep}sub${sep}added.txt').readAsString(),
        'hello\n', reason: 'parent dir created, file written');
  });

  test('failed finalize rolls back: staged selection restored, clean adds '
      'removed, no MERGE_HEAD', () async {
    await seed(diverged: true); // → mergeCommit
    final sep = Platform.pathSeparator;
    // Add a clean incoming file upstream (under a new dir) + an unrelated
    // pre-staged file locally.
    await Directory('$origin${sep}pkg').create(recursive: true);
    await File('$origin${sep}pkg${sep}new.txt').writeAsString('incoming\n');
    await git(origin, ['add', '-A']);
    await git(origin, ['commit', '-qm', 'incoming add']);
    await git(work, ['fetch', '-q', 'origin']);

    await wf(work, 'README.md')
        .writeAsString('l1\nLOCAL2\nl3\nLOCALCOMMIT\nl5\n'); // overlap
    await wf(work, 'other.txt').writeAsString('keep\nSTAGED\n');
    await git(work, ['add', 'other.txt']); // unrelated staged

    // A pre-commit hook that always rejects, to force the commit step to fail.
    // POSIX git skips non-executable hooks (git-for-Windows execs via sh
    // regardless), so the chmod is what makes this test real on Linux.
    final rejectHook = File('$work$sep.git${sep}hooks${sep}pre-commit');
    await rejectHook.writeAsString('#!/bin/sh\nexit 1\n');
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', rejectHook.path]);
    }

    final prep = await prepareMergePull(work);
    expect(prep.topology, MergeTopology.mergeCommit);
    final reconciled = await reconcileDirtyMerge(work, prep);
    await wf(work, 'README.md')
        .writeAsString('l1\nMERGED2\nl3\nLOCALCOMMIT\nl5\n');
    await git(work, ['add', '--', 'README.md']);

    final fin = await finalizeReconciledMerge(work, prep, reconciled);
    expect(fin.ok, isFalse, reason: 'pre-commit hook rejects the commit');

    // Rollback guarantees:
    expect(await File('$work$sep.git${sep}MERGE_HEAD').exists(), isFalse,
        reason: 'no half-merge state left behind');
    final staged =
        (await git(work, ['diff', '--cached', '--name-only'])).stdout.toString();
    expect(staged, contains('other.txt'),
        reason: 'unrelated staged selection restored');
    expect(await File('$work${sep}pkg${sep}new.txt').exists(), isFalse,
        reason: 'the clean incoming add was rolled back off the working tree');
  });

  test('dirty pull treats a non-UTF-8 file (no NUL byte) as binary, '
      'never empty text', () async {
    root = await Directory.systemTemp.createTemp('gdpu_u8_');
    origin = '${root.path}${Platform.pathSeparator}origin';
    work = '${root.path}${Platform.pathSeparator}work';
    final sep = Platform.pathSeparator;
    await Directory(origin).create(recursive: true);
    await git(origin, ['init', '-qb', 'main']);
    await config(origin);
    // 0xFF/0xFE are never valid UTF-8 and contain no NUL — the exact case the
    // NUL-only heuristic would have mis-classified as text.
    await File('$origin${sep}data.dat').writeAsBytes([0xFF, 0xFE, 0x41]);
    await wf(origin, 'README.md').writeAsString('a\nb\n');
    await git(origin, ['add', '-A']);
    await git(origin, ['commit', '-qm', 'base']);
    await File('$origin${sep}data.dat').writeAsBytes([0xFF, 0xFE, 0x42]);
    await git(origin, ['commit', '-qam', 'bump']);

    await git(root.path, ['clone', '-q', origin, 'work']);
    await config(work);
    await git(work, ['reset', '-q', '--hard', 'HEAD~1']);
    await git(work, ['fetch', '-q', 'origin']);
    await wf(work, 'README.md').writeAsString('a\nLOCAL\n'); // unrelated dirty

    final prep = await prepareMergePull(work);
    expect(prep.incomingPaths, contains('data.dat'));
    final reconciled = await reconcileDirtyMerge(work, prep);
    final dat = reconciled.firstWhere((f) => f.path == 'data.dat');
    expect(dat.binary, isTrue, reason: 'non-UTF-8 without NUL is still binary');
    expect(dat.conflicted, isFalse);
    expect(dat.binaryBytes, [0xFF, 0xFE, 0x42]);

    final fin = await finalizeReconciledMerge(work, prep, reconciled);
    expect(fin.ok, isTrue, reason: fin.error ?? '');
    expect(await File('$work${sep}data.dat').readAsBytes(), [0xFF, 0xFE, 0x42],
        reason: 'byte-exact incoming, not blanked/corrupted');
  });

  test('gatherConflictFiles skips a binary UU in a mixed conflict set '
      '(so a text-only resolve leaves the binary unresolved)', () async {
    final repo = (await Directory.systemTemp.createTemp('gdpu_mix_')).path;
    final sep = Platform.pathSeparator;
    await git(repo, ['init', '-qb', 'main']);
    await config(repo);
    await wf(repo, 't.txt').writeAsString('a\nb\nc\n');
    await File('$repo${sep}asset.bin').writeAsBytes([1, 0, 2, 0, 3]);
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'base']);
    await git(repo, ['checkout', '-qb', 'feature']);
    await wf(repo, 't.txt').writeAsString('a\nFEAT\nc\n');
    await File('$repo${sep}asset.bin').writeAsBytes([1, 0, 9, 0, 3]);
    await git(repo, ['commit', '-qam', 'feat']);
    await git(repo, ['checkout', '-q', 'main']);
    await wf(repo, 't.txt').writeAsString('a\nMAIN\nc\n');
    await File('$repo${sep}asset.bin').writeAsBytes([1, 0, 7, 0, 3]);
    await git(repo, ['commit', '-qam', 'main2']);

    final merge = await git(repo, ['merge', 'feature']);
    expect(merge.exitCode, isNot(0), reason: 'both files conflict');
    final uu = (await git(repo, ['diff', '--diff-filter=U', '--name-only']))
        .stdout
        .toString()
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    expect(uu, containsAll(<String>['t.txt', 'asset.bin']));

    // The text editor can only show t.txt; the binary UU is skipped — so
    // after the editor finishes, asset.bin is still UU and the checkout/
    // sequencer gate (_hasRemainingConflicts) must NOT report "resolved".
    final gathered = await gatherConflictFiles(repo, uu);
    expect(gathered.map((f) => f.path).toList(), ['t.txt'],
        reason: 'binary UU skipped, text conflict kept');
    await Directory(repo).delete(recursive: true);
  });

  test('stashDropByHash drops the right entry after the stash list shifts',
      () async {
    final repo = (await Directory.systemTemp.createTemp('gdpu_stash_')).path;
    await git(repo, ['init', '-qb', 'main']);
    await config(repo);
    await wf(repo, 'f.txt').writeAsString('base\n');
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'base']);
    // stash A, then B → stash@{0}=B, stash@{1}=A.
    await wf(repo, 'f.txt').writeAsString('A\n');
    await git(repo, ['stash', 'push', '-q']);
    await wf(repo, 'f.txt').writeAsString('B\n');
    await git(repo, ['stash', 'push', '-q']);

    final aHash = await stashHashAt(repo, 1); // pin A while it's at index 1
    expect(aHash, isNotNull);

    // A new stash C shifts everything: C@0, B@1, A@2.
    await wf(repo, 'f.txt').writeAsString('C\n');
    await git(repo, ['stash', 'push', '-q']);

    final drop = await stashDropByHash(repo, aHash!);
    expect(drop.ok, isTrue, reason: drop.error ?? '');

    final list = await listStashes(repo);
    expect(list.data!.map((s) => s.hash), isNot(contains(aHash)),
        reason: 'A was dropped despite its index having shifted 1→2');
    expect(list.data!.length, 2, reason: 'C and B remain');
    await Directory(repo).delete(recursive: true);
  });

  test('index snapshot/restore round-trips staged content and absence',
      () async {
    final repo = (await Directory.systemTemp.createTemp('gdpu_idx_')).path;
    await git(repo, ['init', '-qb', 'main']);
    await config(repo);
    await wf(repo, 'f.txt').writeAsString('A\n');
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'base']);

    // f.txt: stage version B; g.txt: untracked (not in index).
    await wf(repo, 'f.txt').writeAsString('B\n');
    await git(repo, ['add', 'f.txt']);
    await wf(repo, 'g.txt').writeAsString('G\n');

    final snap = await snapshotIndexEntries(repo, ['f.txt', 'g.txt']);
    expect(snap['f.txt'], isNotNull, reason: 'f.txt is staged');
    expect(snap['g.txt'], isNull, reason: 'g.txt is not in the index');

    // Mutate the index the way an AI patch-apply would: restage f.txt as C,
    // and stage the previously-untracked g.txt.
    await wf(repo, 'f.txt').writeAsString('C\n');
    await git(repo, ['add', 'f.txt', 'g.txt']);
    expect((await git(repo, ['show', ':f.txt'])).stdout.toString(), 'C\n');

    await restoreIndexEntries(repo, snap);

    // f.txt index entry rolled back to B; g.txt force-removed from the index.
    expect((await git(repo, ['show', ':f.txt'])).stdout.toString(), 'B\n');
    final gStaged =
        (await git(repo, ['ls-files', '--', 'g.txt'])).stdout.toString().trim();
    expect(gStaged, isEmpty, reason: 'g.txt unstaged back to untracked');
    await Directory(repo).delete(recursive: true);
  });

  test('checkout -m carries a dirty overlapping edit across the switch',
      () async {
    final repo = (await Directory.systemTemp.createTemp('gdpu_co_')).path;
    await git(repo, ['init', '-qb', 'main']);
    await config(repo);
    await wf(repo, 'f.txt').writeAsString('l1\nl2\nl3\n');
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'base']);
    await git(repo, ['checkout', '-qb', 'feature']);
    await wf(repo, 'f.txt').writeAsString('l1\nFEAT2\nl3\n');
    await git(repo, ['commit', '-qam', 'feat']);
    await git(repo, ['checkout', '-q', 'main']);
    // Dirty, overlapping edit on main.
    await wf(repo, 'f.txt').writeAsString('l1\nLOCAL2\nl3\n');

    // Plain checkout refuses; checkoutMerge carries it across with markers.
    final plain = await checkoutBranch(repo, 'feature');
    expect(plain.ok, isFalse);
    expect(plain.error, contains('overwritten'));

    final m = await checkoutMerge(repo, 'feature');
    expect(m.ok, isTrue, reason: m.error ?? '');
    final branch =
        (await git(repo, ['branch', '--show-current'])).stdout.toString().trim();
    expect(branch, 'feature');
    final content = await wf(repo, 'f.txt').readAsString();
    expect(content, contains('<<<<<<<'));
    expect(content, contains('FEAT2'));
    expect(content, contains('LOCAL2'));
    await Directory(repo).delete(recursive: true);
  });

  test('cherry-pick conflict concludes via continueCherryPick', () async {
    final repo = (await Directory.systemTemp.createTemp('gdpu_cp_')).path;
    await git(repo, ['init', '-qb', 'main']);
    await config(repo);
    await wf(repo, 'f.txt').writeAsString('l1\nl2\nl3\n');
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'base']);
    await git(repo, ['checkout', '-qb', 'side']);
    await wf(repo, 'f.txt').writeAsString('l1\nSIDE2\nl3\n');
    await git(repo, ['commit', '-qam', 'side']);
    await git(repo, ['checkout', '-q', 'main']);
    await wf(repo, 'f.txt').writeAsString('l1\nMAIN2\nl3\n');
    await git(repo, ['commit', '-qam', 'main2']);

    final cp = await git(repo, ['cherry-pick', 'side']);
    expect(cp.exitCode, isNot(0), reason: 'overlap should conflict');
    // Resolve + conclude through the shared backend helper.
    await wf(repo, 'f.txt').writeAsString('l1\nRESOLVED2\nl3\n');
    await git(repo, ['add', 'f.txt']);
    final cont = await continueCherryPick(repo);
    expect(cont.ok, isTrue, reason: cont.error ?? '');
    final tip = (await git(repo, ['log', '--oneline', '-1'])).stdout.toString();
    expect(tip, contains('side'));
    final clean = (await git(repo, ['status', '--porcelain'])).stdout.toString();
    expect(clean.trim(), isEmpty, reason: 'cherry-pick concluded cleanly');
    await Directory(repo).delete(recursive: true);
  });
}
