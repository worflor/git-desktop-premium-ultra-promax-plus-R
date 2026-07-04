import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';

/// Witness for the exact-staging commit contract (prepareCommitStaging /
/// restoreStagedSelections / stagePaths / unstagePaths):
///
///   1. The commit contains EXACTLY the included paths — a hand-built
///      partial index entry survives commit untouched, and nothing outside
///      the included set is ever staged (including via pathspec-glob
///      expansion of hostile filenames like `[bracket].txt`).
///   2. Excluded staged state — content entries, deletions, rename halves —
///      is restored BYTE-FOR-BYTE, proven by `git ls-files -s` index
///      snapshot equality (mode + blob OID + stage + path), not by helper
///      return values.
///
/// All assertions read git plumbing directly so the tests cannot be
/// satisfied by the helpers lying about their own success.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String repo;

  Future<ProcessResult> git(List<String> args) => Process.run(
        'git',
        args,
        workingDirectory: repo,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

  File wf(String path) => File('$repo${Platform.pathSeparator}$path');

  Future<String> show(String rev, String path) async =>
      (await git(['show', '$rev:$path'])).stdout as String;

  /// Full index snapshot: path → "mode oid stage" from `git ls-files -s`.
  /// The strongest restore proof available: byte-identical index entries.
  Future<Map<String, String>> indexSnapshot() async {
    final out =
        (await git(['ls-files', '-s', '-z'])).stdout as String;
    final map = <String, String>{};
    for (final rec in out.split('\x00')) {
      if (rec.isEmpty) continue;
      final tab = rec.indexOf('\t');
      if (tab < 0) continue;
      map[rec.substring(tab + 1)] = rec.substring(0, tab);
    }
    return map;
  }

  /// Paths touched by HEAD relative to its parent — proves what the commit
  /// actually contains, straight from the object database.
  Future<Set<String>> headTouchedPaths() async {
    final out = (await git(
            ['diff-tree', '--no-commit-id', '--name-only', '-z', '-r', 'HEAD']))
        .stdout as String;
    return out.split('\x00').where((p) => p.isNotEmpty).toSet();
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('gdpu_staging_');
    repo = root.path;
    await git(['init', '-q', '-b', 'main']);
    await git(['config', 'user.email', 'a@b.c']);
    await git(['config', 'user.name', 'test']);
    await git(['config', 'core.autocrlf', 'false']);
    await git(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> seedAndCommit(Map<String, String> files) async {
    for (final e in files.entries) {
      final f = wf(e.key);
      await f.parent.create(recursive: true);
      await f.writeAsString(e.value);
    }
    await git(['add', '-A']);
    await git(['commit', '-qm', 'base']);
  }

  test(
      'commit takes staged content exactly; excluded staging restored to '
      'byte-identical index entries', () async {
    await seedAndCommit({'a.txt': 'a1\n', 'b.txt': 'b1\n', 'c.txt': 'c1\n'});

    // a.txt: stage "a2", keep editing to "a3" — index and worktree differ.
    await wf('a.txt').writeAsString('a2\n');
    await git(['add', 'a.txt']);
    await wf('a.txt').writeAsString('a3\n');

    // b.txt: fully staged but EXCLUDED — must round-trip untouched.
    await wf('b.txt').writeAsString('b2\n');
    await git(['add', 'b.txt']);

    // c.txt: plain unstaged modification, included.
    await wf('c.txt').writeAsString('c2\n');

    final before = await indexSnapshot();

    final plan = await prepareCommitStaging(repo, ['a.txt', 'c.txt']);
    expect(plan.ok, isTrue, reason: plan.error ?? '');
    final commit = await createCommit(repo, 'exact staging');
    expect(commit.ok, isTrue, reason: commit.error ?? '');
    final restore =
        await restoreStagedSelections(repo, plan.data!.excludedEntries);
    expect(restore.ok, isTrue, reason: restore.error ?? '');

    // Commit content: staged a2 (NOT worktree a3), c2; b untouched.
    expect(await headTouchedPaths(), {'a.txt', 'c.txt'});
    expect(await show('HEAD', 'a.txt'), 'a2\n');
    expect(await show('HEAD', 'c.txt'), 'c2\n');
    expect(await show('HEAD', 'b.txt'), 'b1\n');

    // Worktree: the unstaged a3 edit survived the commit.
    expect(await wf('a.txt').readAsString(), 'a3\n');

    // Byte-identical restore: b.txt's index entry (mode+oid+stage) is
    // exactly what it was before the flow ran, and it still differs
    // from HEAD (i.e. it is genuinely still staged).
    final after = await indexSnapshot();
    expect(after['b.txt'], before['b.txt']);
    final stagedNow =
        (await git(['diff', '--cached', '--name-only'])).stdout as String;
    expect(stagedNow.trim(), 'b.txt');
  });

  test(
      'glob-metachar filenames stage literally: [bracket].txt cannot drag '
      'a.txt into the commit via character-class expansion', () async {
    // `[bracket].txt` as a PATHSPEC is a char class matching a.txt —
    // verified live against git before this suite existed. Both files are
    // modified; only the bracket file is included. If any layer of the
    // staging chain interprets names as globs, a.txt leaks into the
    // commit and this test fails.
    await seedAndCommit({'a.txt': 'a1\n', '[bracket].txt': 'x1\n'});
    await wf('a.txt').writeAsString('a2\n');
    await wf('[bracket].txt').writeAsString('x2\n');

    final plan = await prepareCommitStaging(repo, ['[bracket].txt']);
    expect(plan.ok, isTrue, reason: plan.error ?? '');
    final commit = await createCommit(repo, 'literal pathspecs');
    expect(commit.ok, isTrue, reason: commit.error ?? '');
    await restoreStagedSelections(repo, plan.data!.excludedEntries);

    expect(await headTouchedPaths(), {'[bracket].txt'});
    expect(await show('HEAD', '[bracket].txt'), 'x2\n');
    expect(await show('HEAD', 'a.txt'), 'a1\n');
    // a.txt's edit is still a plain unstaged modification — not silently
    // staged, not committed, not lost.
    expect(await wf('a.txt').readAsString(), 'a2\n');
    final stagedNow =
        (await git(['diff', '--cached', '--name-only'])).stdout as String;
    expect(stagedNow.trim(), isEmpty);
  });

  test('hostile-but-valid names round-trip: spaces, unicode, nested dirs',
      () async {
    const spaced = 'spaces in name.txt';
    const uni = 'uni-cödé-✓.txt';
    const nested = 'sub/dir/nested file.txt';
    await seedAndCommit({spaced: 's1\n', uni: 'u1\n', nested: 'n1\n'});

    // All three modified + staged; only `spaced` is included. The other
    // two must survive as byte-identical excluded index entries.
    for (final e in {spaced: 's2\n', uni: 'u2\n', nested: 'n2\n'}.entries) {
      await wf(e.key).writeAsString(e.value);
    }
    await git(['add', '-A']);
    final before = await indexSnapshot();

    final plan = await prepareCommitStaging(repo, [spaced]);
    expect(plan.ok, isTrue, reason: plan.error ?? '');
    final commit = await createCommit(repo, 'hostile names');
    expect(commit.ok, isTrue, reason: commit.error ?? '');
    final restore =
        await restoreStagedSelections(repo, plan.data!.excludedEntries);
    expect(restore.ok, isTrue, reason: restore.error ?? '');

    expect(await headTouchedPaths(), {spaced});
    expect(await show('HEAD', spaced), 's2\n');
    final after = await indexSnapshot();
    expect(after[uni], before[uni]);
    expect(after[nested], before[nested]);
    // And they are still staged (index differs from HEAD for both).
    final stagedNow =
        (await git(['diff', '--cached', '--name-only', '-z'])).stdout as String;
    final stagedSet =
        stagedNow.split('\x00').where((p) => p.isNotEmpty).toSet();
    expect(stagedSet, {uni, nested});
  });

  test('excluded staged RENAME round-trips both halves', () async {
    await seedAndCommit({'old.txt': 'o1\n', 'a.txt': 'a1\n'});
    await git(['mv', 'old.txt', 'renamed.txt']);
    await wf('a.txt').writeAsString('a2\n');

    final before = await indexSnapshot();
    expect(before.containsKey('renamed.txt'), isTrue);
    expect(before.containsKey('old.txt'), isFalse);

    final plan = await prepareCommitStaging(repo, ['a.txt']);
    expect(plan.ok, isTrue, reason: plan.error ?? '');
    final commit = await createCommit(repo, 'rename excluded');
    expect(commit.ok, isTrue, reason: commit.error ?? '');
    final restore =
        await restoreStagedSelections(repo, plan.data!.excludedEntries);
    expect(restore.ok, isTrue, reason: restore.error ?? '');

    // The commit touched only a.txt — the rename stayed out entirely.
    expect(await headTouchedPaths(), {'a.txt'});
    expect(await show('HEAD', 'old.txt'), 'o1\n');

    // The staged rename is fully rebuilt: old gone from the index,
    // renamed present with the identical entry.
    final after = await indexSnapshot();
    expect(after.containsKey('old.txt'), isFalse);
    expect(after['renamed.txt'], before['renamed.txt']);
  });

  test('excluded staged DELETION is re-recorded after commit', () async {
    await seedAndCommit({'gone.txt': 'g1\n', 'a.txt': 'a1\n'});
    await git(['rm', '-q', 'gone.txt']);
    await wf('a.txt').writeAsString('a2\n');

    final plan = await prepareCommitStaging(repo, ['a.txt']);
    expect(plan.ok, isTrue, reason: plan.error ?? '');
    final commit = await createCommit(repo, 'deletion excluded');
    expect(commit.ok, isTrue, reason: commit.error ?? '');
    final restore =
        await restoreStagedSelections(repo, plan.data!.excludedEntries);
    expect(restore.ok, isTrue, reason: restore.error ?? '');

    // HEAD still has the file; the index does not: staged deletion intact.
    expect(await headTouchedPaths(), {'a.txt'});
    expect(await show('HEAD', 'gone.txt'), 'g1\n');
    final after = await indexSnapshot();
    expect(after.containsKey('gone.txt'), isFalse);
    final status =
        (await git(['status', '--porcelain', '--no-renames'])).stdout as String;
    expect(status, contains('D  gone.txt'));
  });

  test('failed commit restores excluded staging and leaves index intact',
      () async {
    await seedAndCommit({'a.txt': 'a1\n', 'b.txt': 'b1\n'});
    await wf('b.txt').writeAsString('b2\n');
    await git(['add', 'b.txt']);
    final before = await indexSnapshot();

    final plan = await prepareCommitStaging(repo, ['a.txt']);
    expect(plan.ok, isTrue, reason: plan.error ?? '');
    // a.txt unchanged → nothing staged → empty commit fails.
    final commit = await createCommit(repo, 'should fail');
    expect(commit.ok, isFalse);
    final restore =
        await restoreStagedSelections(repo, plan.data!.excludedEntries);
    expect(restore.ok, isTrue, reason: restore.error ?? '');

    final after = await indexSnapshot();
    expect(after['b.txt'], before['b.txt']);
  });
}
