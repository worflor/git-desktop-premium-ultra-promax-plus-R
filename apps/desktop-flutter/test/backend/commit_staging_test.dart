import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
      'untracked file inside a brand-new directory commits when included '
      '(dir-collapse regression)', () async {
    await seedAndCommit({'a.txt': 'a1\n'});

    // Both files live in a directory git has never seen. Without -uall,
    // `status --porcelain` collapses them into one "?? newdir/" record,
    // the included FILE path matches nothing, and the commit silently
    // ships without it — the exact bug this test pins.
    final inc = wf('newdir/included_test.dart');
    final exc = wf('newdir/excluded_scratch.txt');
    await inc.parent.create(recursive: true);
    await inc.writeAsString('void main() {}\n');
    await exc.writeAsString('scratch\n');

    final plan = await prepareCommitStaging(repo, ['newdir/included_test.dart']);
    expect(plan.ok, isTrue, reason: plan.error ?? '');
    final commit = await createCommit(repo, 'new-dir file', plan: plan.data!);
    expect(commit.ok, isTrue, reason: commit.error ?? '');
    final restore =
        await restoreStagedSelections(repo, plan.data!.excludedEntries);
    expect(restore.ok, isTrue, reason: restore.error ?? '');

    expect(await headTouchedPaths(), {'newdir/included_test.dart'});
    expect(await show('HEAD', 'newdir/included_test.dart'), 'void main() {}\n');

    // The excluded sibling stays untracked — exactness cuts both ways.
    final status =
        (await git(['status', '--porcelain', '-uall'])).stdout as String;
    expect(status, contains('?? newdir/excluded_scratch.txt'));
    final stagedNow =
        (await git(['diff', '--cached', '--name-only'])).stdout as String;
    expect(stagedNow.trim(), isEmpty);
  });

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
    final commit = await createCommit(repo, 'exact staging', plan: plan.data!);
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
    final commit =
        await createCommit(repo, 'literal pathspecs', plan: plan.data!);
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
    final commit = await createCommit(repo, 'hostile names', plan: plan.data!);
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
    final commit =
        await createCommit(repo, 'rename excluded', plan: plan.data!);
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
    final commit =
        await createCommit(repo, 'deletion excluded', plan: plan.data!);
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
    final commit = await createCommit(repo, 'should fail', plan: plan.data!);
    expect(commit.ok, isFalse);
    final restore =
        await restoreStagedSelections(repo, plan.data!.excludedEntries);
    expect(restore.ok, isTrue, reason: restore.error ?? '');

    final after = await indexSnapshot();
    expect(after['b.txt'], before['b.txt']);
  });

  // --- Rename halves under --no-renames (item 4) -------------------------
  //
  // `git mv old new` stages a rename. prepareCommitStaging walks status
  // with --no-renames, so the rename is two independent records — `D old`
  // and `A new` — and unstagePaths(...) likewise probes with --no-renames.
  // The documented contract (see unstagePaths' comment) is that each half
  // is handled on its own: including exactly ONE half commits exactly that
  // half and holds the other back. These pin that behavior; they do not
  // assert an invented "rename should move atomically".

  test(
      'rename half-included (new path only): commits only the add; the '
      'deletion half is held back and re-staged (documented --no-renames)',
      () async {
    await seedAndCommit({'old.txt': 'o1\n', 'a.txt': 'a1\n'});
    await git(['mv', 'old.txt', 'renamed.txt']);

    final plan = await prepareCommitStaging(repo, ['renamed.txt']);
    expect(plan.ok, isTrue, reason: plan.error ?? '');
    final commit =
        await createCommit(repo, 'rename new-half only', plan: plan.data!);
    expect(commit.ok, isTrue, reason: commit.error ?? '');
    final restore =
        await restoreStagedSelections(repo, plan.data!.excludedEntries);
    expect(restore.ok, isTrue, reason: restore.error ?? '');

    // The commit added renamed.txt and did NOT delete old.txt.
    expect(await headTouchedPaths(), {'renamed.txt'});
    expect(await show('HEAD', 'old.txt'), 'o1\n');
    expect(await show('HEAD', 'renamed.txt'), 'o1\n');
    // The deletion half is restored as a staged deletion for a later commit.
    final status =
        (await git(['status', '--porcelain', '--no-renames'])).stdout as String;
    expect(status, contains('D  old.txt'));
  });

  test(
      'rename half-included (old path only): commits only the deletion; the '
      'add half is restored byte-identically (documented --no-renames)',
      () async {
    await seedAndCommit({'old.txt': 'o1\n', 'a.txt': 'a1\n'});
    await git(['mv', 'old.txt', 'renamed.txt']);
    final before = await indexSnapshot();
    expect(before.containsKey('renamed.txt'), isTrue);

    final plan = await prepareCommitStaging(repo, ['old.txt']);
    expect(plan.ok, isTrue, reason: plan.error ?? '');
    final commit =
        await createCommit(repo, 'rename old-half only', plan: plan.data!);
    expect(commit.ok, isTrue, reason: commit.error ?? '');
    final restore =
        await restoreStagedSelections(repo, plan.data!.excludedEntries);
    expect(restore.ok, isTrue, reason: restore.error ?? '');

    // The commit removed old.txt; the add half was NOT committed.
    expect(await headTouchedPaths(), {'old.txt'});
    expect((await git(['cat-file', '-e', 'HEAD:old.txt'])).exitCode, isNot(0));
    expect(
        (await git(['cat-file', '-e', 'HEAD:renamed.txt'])).exitCode, isNot(0));
    // The add half is restored to the index byte-identically.
    final after = await indexSnapshot();
    expect(after['renamed.txt'], before['renamed.txt']);
  });

  // --- Generative exactness (item 1) -------------------------------------

  test(
      'GENERATIVE exactness: commit touches exactly the includable subset; '
      'excluded index entries and all worktree bytes survive byte-for-byte',
      timeout: const Timeout(Duration(minutes: 4)), () async {
    const cases = 25;
    for (var i = 0; i < cases; i++) {
      final rng = math.Random(_kStagingSeed + i);
      final repo = await _newTempRepo();
      try {
        final specs = await _buildCase(repo, rng);
        final all = specs.map((s) => s.path).toList();

        // Pick an included subset: sometimes empty, sometimes everything,
        // sometimes only the brand-new-dir files, otherwise a coin-flip mix.
        final mode = rng.nextInt(5);
        Set<String> included;
        switch (mode) {
          case 0:
            included = <String>{};
            break;
          case 1:
            included = all.toSet();
            break;
          case 2:
            included = specs
                .where((s) => s.kind == _K.untrackedNew)
                .map((s) => s.path)
                .toSet();
            break;
          default:
            included = all.where((_) => rng.nextBool()).toSet();
        }
        // Keep the brand-new-dir ingredient (the real dir-collapse bug shape)
        // well exercised: often force those files into the included set.
        if (rng.nextBool()) {
          included.addAll(specs
              .where((s) => s.kind == _K.untrackedNew)
              .map((s) => s.path));
        }

        final tag = 'seed=$_kStagingSeed case=$i mode=$mode '
            'included=${(included.toList()..sort())}';

        // Snapshots + oracle, taken from git plumbing BEFORE the flow.
        final beforeIdx = await _idx(repo);
        final beforeDisk = await _diskBytes(repo, all);
        final expected = await _committable(repo, included);

        // Run the real flow exactly as changes_page does.
        final planRes = await prepareCommitStaging(repo, included.toList());
        expect(planRes.ok, isTrue, reason: 'prepare failed: ${planRes.error} [$tag]');
        final plan = planRes.data!;
        final commitRes = await createCommit(repo, 'case $i', plan: plan);
        final restore =
            await restoreStagedSelections(repo, plan.excludedEntries);
        expect(restore.ok, isTrue, reason: 'restore failed: ${restore.error} [$tag]');

        if (expected.isEmpty) {
          // Nothing includable → nothing to commit → the commit must fail
          // and HEAD must be untouched.
          expect(commitRes.ok, isFalse,
              reason: 'commit of an empty includable set should fail [$tag]');
        } else {
          expect(commitRes.ok, isTrue,
              reason: 'commit failed: ${commitRes.error} [$tag]');
          // (a) HEAD's diff-tree touched set == the includable subset.
          expect(await _headTouched(repo), expected,
              reason: '(a) commit touched-set mismatch [$tag]');
          // Content exactness on a bounded sample: the committed blob is the
          // STAGED content (proves partial staging commits v2 not worktree
          // v3, and that CRLF/unicode bytes are not mangled).
          var checked = 0;
          for (final s in specs) {
            if (checked >= 5) break;
            if (!expected.contains(s.path) || s.committedBytes == null) continue;
            final shown = await _showBytes(repo, s.path);
            expect(shown, isNotNull, reason: '(content) show ${s.path} [$tag]');
            expect(_bytesEq(shown, s.committedBytes), isTrue,
                reason: '(content) committed blob mismatch ${s.path} [$tag]');
            checked++;
          }
        }

        // (b) every EXCLUDED path's index entry is byte-identical (an absent
        // entry byte-identical to absent counts).
        final afterIdx = await _idx(repo);
        for (final s in specs) {
          if (included.contains(s.path)) continue;
          expect(afterIdx[s.path], beforeIdx[s.path],
              reason: '(b) excluded index entry changed: ${s.path} [$tag]');
        }

        // (c) NO worktree file bytes changed for any touched path.
        final afterDisk = await _diskBytes(repo, all);
        for (final path in all) {
          expect(_bytesEq(afterDisk[path], beforeDisk[path]), isTrue,
              reason: '(c) worktree bytes changed: $path [$tag]');
        }

        // (d) the repo is not left in a corrupt state — a follow-up commit
        // of whatever remains still succeeds.
        await _rg(repo, ['add', '-A']);
        final stagedNow =
            (await _rg(repo, ['diff', '--cached', '--name-only'])).stdout
                as String;
        if (stagedNow.trim().isNotEmpty) {
          final c2 = await _rg(repo, ['commit', '-qm', 'second']);
          expect(c2.exitCode, 0,
              reason: '(d) second commit failed [$tag]: ${c2.stderr}');
        }
      } finally {
        await _rmRepo(repo);
      }
    }
  });

  // --- Idempotence / reentrancy (item 2) ---------------------------------

  test(
      'GENERATIVE idempotence: a second prepare and a second restore never '
      'change the index', timeout: const Timeout(Duration(minutes: 3)),
      () async {
    for (var i = 0; i < 6; i++) {
      final rng = math.Random(_kStagingSeed + 500 + i);
      final repo = await _newTempRepo();
      try {
        final specs = await _buildCase(repo, rng);
        final all = specs.map((s) => s.path).toList();
        final included = all.where((_) => rng.nextBool()).toList();
        final tag = 'seed=$_kStagingSeed case=$i';

        final p1 = await prepareCommitStaging(repo, included);
        expect(p1.ok, isTrue, reason: '${p1.error} [$tag]');
        final idxAfterFirst = await _idx(repo);
        final p2 = await prepareCommitStaging(repo, included);
        expect(p2.ok, isTrue, reason: '${p2.error} [$tag]');
        final idxAfterSecond = await _idx(repo);
        expect(idxAfterSecond, idxAfterFirst,
            reason: 'second prepare mutated the index [$tag]');
        // The snapshot is UNCONDITIONAL now (it IS the commit contract, not
        // an optimization for the has-exclusions case): even a redundant
        // second prepare with nothing left to exclude still freezes the
        // arranged index, so a concurrent add can never leak into a commit
        // built from it. (Pre-fix this asserted isNull — the old gate that
        // left an unstaged-but-excluded path exposed to the TOCTOU race.)
        expect(p2.data!.snapshotIndexPath, isNotNull, reason: tag);

        final r1 = await restoreStagedSelections(repo, p1.data!.excludedEntries);
        expect(r1.ok, isTrue, reason: '${r1.error} [$tag]');
        final idxAfterRestore1 = await _idx(repo);
        final r2 = await restoreStagedSelections(repo, p1.data!.excludedEntries);
        expect(r2.ok, isTrue, reason: '${r2.error} [$tag]');
        final idxAfterRestore2 = await _idx(repo);
        expect(idxAfterRestore2, idxAfterRestore1,
            reason: 'second restore duplicated/changed index entries [$tag]');
      } finally {
        await _rmRepo(repo);
      }
    }
  });

  // --- Failure-path rollback (item 3) ------------------------------------

  test(
      'GENERATIVE failure paths: an empty-includable commit and a failing '
      'commit hook both roll back to a byte-identical index and worktree',
      timeout: const Timeout(Duration(minutes: 3)), () async {
    for (var i = 0; i < 6; i++) {
      final rng = math.Random(_kStagingSeed + 700 + i);
      final repo = await _newTempRepo();
      try {
        final specs = await _buildCase(repo, rng);
        final all = specs.map((s) => s.path).toList();
        final hookMode = i.isOdd;

        List<String> included;
        if (hookMode) {
          // Install a repo-local pre-commit hook that fails. Include only
          // paths that are ALREADY staged, so prepare adds nothing and a
          // full byte-identity assertion is the true contract (prepare only
          // unstages the excluded halves, which restore puts back).
          final hooks = Directory(
              '$repo${Platform.pathSeparator}.githooks');
          await hooks.create(recursive: true);
          final hookFile =
              File('${hooks.path}${Platform.pathSeparator}pre-commit');
          await hookFile.writeAsString('#!/bin/sh\nexit 1\n');
          await _markHookExecutable(hookFile);
          await _rg(repo, ['config', 'core.hooksPath', hooks.path]);
          included = specs
              .where((s) => s.kind == _K.staged || s.kind == _K.partial)
              .map((s) => s.path)
              .toList();
        } else {
          included = <String>[]; // nothing includable → nothing to commit
        }

        final tag = 'seed=$_kStagingSeed case=$i hook=$hookMode';
        final beforeIdx = await _idx(repo);
        final beforeDisk = await _diskBytes(repo, all);

        final planRes = await prepareCommitStaging(repo, included);
        expect(planRes.ok, isTrue, reason: '${planRes.error} [$tag]');
        final plan = planRes.data!;
        final commitRes =
            await createCommit(repo, 'must fail $i', plan: plan);
        expect(commitRes.ok, isFalse, reason: 'commit should have failed [$tag]');
        final restore =
            await restoreStagedSelections(repo, plan.excludedEntries);
        expect(restore.ok, isTrue, reason: '${restore.error} [$tag]');

        expect(await _idx(repo), beforeIdx,
            reason: 'index not byte-identical after rollback [$tag]');
        final afterDisk = await _diskBytes(repo, all);
        for (final path in all) {
          expect(_bytesEq(afterDisk[path], beforeDisk[path]), isTrue,
              reason: 'worktree changed during a failed flow: $path [$tag]');
        }
        // No commit was created.
        expect((await _rg(repo, ['rev-list', '--count', 'HEAD'])).stdout,
            startsWith('1'),
            reason: 'a failed flow created a commit [$tag]');
      } finally {
        await _rmRepo(repo);
      }
    }
  });

  // --- Concurrent-mutation smoke (item 5) --------------------------------
  //
  // Regression pin for the hermetic-commit fix: an out-of-band `git add` of
  // an EXCLUDED file landing while the flow runs must never enter the
  // commit. Before the fix (`createCommit` reading the live index) the
  // mid-window add leaked 100% of the time; committing against the frozen
  // index snapshot makes it unrepresentable. Either the external add wins
  // (its change persists for later) or it loses — never does the commit
  // contain a non-included path, whichever way the race falls.

  test(
      'concurrent external add of an excluded file never enters the commit',
      timeout: const Timeout(Duration(minutes: 2)), () async {
    for (var i = 0; i < 5; i++) {
      final repo = await _newTempRepo();
      try {
        await _rf(repo, 'a.txt').writeAsString('a1\n');
        await _rf(repo, 'b.txt').writeAsString('b1\n');
        await _rg(repo, ['add', '-A']);
        await _rg(repo, ['commit', '-qm', 'base']);
        await _rf(repo, 'a.txt').writeAsString('a2\n');
        await _rf(repo, 'b.txt').writeAsString('b2\n');
        await _rg(repo, ['add', 'a.txt', 'b.txt']);

        final phase = i % 3; // 0 before prepare, 1 mid-window, 2 vs commit
        final tag = 'seed=$_kStagingSeed case=$i phase=$phase';

        if (phase == 0) await _rg(repo, ['add', 'b.txt']);
        final planRes = await prepareCommitStaging(repo, ['a.txt']);
        expect(planRes.ok, isTrue, reason: '${planRes.error} [$tag]');
        final plan = planRes.data!;

        if (phase == 1) {
          await _rf(repo, 'b.txt').writeAsString('b3\n');
          await _rg(repo, ['add', 'b.txt']);
        }
        Future<ProcessResult>? racer;
        if (phase == 2) racer = _rg(repo, ['add', 'b.txt']);

        final commitRes =
            await createCommit(repo, 'concurrent $i', plan: plan);
        if (racer != null) await racer;
        await restoreStagedSelections(repo, plan.excludedEntries);

        expect(commitRes.ok, isTrue,
            reason: 'commit failed: ${commitRes.error} [$tag]');
        final touched = await _headTouched(repo);
        expect(touched.difference({'a.txt'}), isEmpty,
            reason: 'excluded path leaked into the commit [$tag] '
                'touched=$touched');
      } finally {
        await _rmRepo(repo);
      }
    }
  });

  // --- Unconditional-snapshot TOCTOU (fix 1) -----------------------------
  //
  // The snapshot used to be gated on `excluded.isNotEmpty`. A path
  // excluded from the commit purely by being UNSTAGED (modified but never
  // `git add`ed — the common case) leaves nothing for the exclusion walk
  // to unstage, so under the old gate NO snapshot was taken and `git
  // commit` read the LIVE index. A concurrent `git add` of that unstaged
  // path in the prepare->commit window then leaked it into the commit.
  // Snapshotting unconditionally makes that unrepresentable.

  test(
      'unstaged-exclusion TOCTOU: a concurrent stage of an '
      'excluded-because-unstaged path never enters the commit; the '
      'external stage is preserved for later (design decision)', () async {
    final repo = await _newTempRepo();
    try {
      await _rf(repo, 'a.txt').writeAsString('a1\n');
      await _rf(repo, 'b.txt').writeAsString('b1\n');
      await _rg(repo, ['add', '-A']);
      await _rg(repo, ['commit', '-qm', 'base']);

      // Both modified, BOTH left UNSTAGED. b.txt is out of the commit
      // purely by being unstaged — nothing for prepare to unstage, so the
      // pre-fix gated snapshot would never have been taken.
      await _rf(repo, 'a.txt').writeAsString('a2\n');
      await _rf(repo, 'b.txt').writeAsString('b2\n');

      final planRes = await prepareCommitStaging(repo, ['a.txt']);
      expect(planRes.ok, isTrue, reason: planRes.error ?? '');
      final plan = planRes.data!;
      // The snapshot IS taken even though nothing was excluded/unstaged.
      expect(plan.snapshotIndexPath, isNotNull,
          reason: 'snapshot must be unconditional');
      // b.txt was never staged, so it was never captured as excluded.
      expect(plan.excludedEntries, isEmpty);

      // Out-of-band stage of the excluded, unstaged b.txt — a different
      // tool racing the commit window. Straight Process.run, NOT through
      // git.dart's wrapper, to faithfully simulate an external actor.
      final add =
          await Process.run('git', ['add', 'b.txt'], workingDirectory: repo);
      expect(add.exitCode, 0, reason: add.stderr.toString());

      final commitRes = await createCommit(repo, 'a only', plan: plan);
      expect(commitRes.ok, isTrue, reason: commitRes.error ?? '');
      final restore = await finalizeCommitStaging(repo, plan, commitRes);
      expect(restore.ok, isTrue, reason: restore.error ?? '');

      // FIX 1: the commit contains EXACTLY a.txt — b.txt's concurrent
      // stage was invisible to the frozen snapshot the commit was built
      // from. Pre-fix (live-index commit) this leaked b.txt 100% of time.
      expect(await _headTouched(repo), {'a.txt'});
      expect((await _rg(repo, ['show', 'HEAD:a.txt'])).stdout, 'a2\n');
      expect((await _rg(repo, ['show', 'HEAD:b.txt'])).stdout, 'b1\n');

      // DESIGN DECISION (observed, not assumed): the out-of-band stage of
      // b.txt is PRESERVED, not clobbered. finalizeCommitStaging restores
      // only plan.excludedEntries (empty here), and reconcile resets only
      // the committed path (a.txt) with --literal-pathspecs; b.txt is
      // orthogonal to both, so the external stager's work survives in the
      // live index for a later commit. This is the "external add wins"
      // branch of the race — the flow neither commits b.txt nor destroys
      // the concurrent actor's staging.
      final staged =
          ((await _rg(repo, ['diff', '--cached', '--name-only', '-z']))
                  .stdout as String)
              .split('\x00')
              .where((s) => s.isNotEmpty)
              .toSet();
      expect(staged, {'b.txt'},
          reason: 'the concurrent external stage of b.txt must survive');
      expect((await _rg(repo, ['show', ':b.txt'])).stdout, 'b2\n');
    } finally {
      await _rmRepo(repo);
    }
  });

  // --- Hostile committed name through the reconcile path (fix 3) ---------
  //
  // A committed file literally named `[bracket].txt` drives the post-
  // commit live-index reconcile (`reset -- '[bracket].txt'`). Without
  // --literal-pathspecs that `[bracket]` is a character class matching any
  // single-char name (`b`, `a`, ...), so the reset glob-unstages an
  // unrelated live-index entry it happens to match, desyncing the index.
  // A look-alike `b.txt` staged out-of-band is the witness: it must
  // survive a literal reconcile and would be wrongly unstaged by a glob
  // one. The full snapshot+capture+restore machinery also runs via an
  // excluded staged a.txt.

  test(
      'hostile committed name [bracket].txt reconciles literally: it does '
      'not glob-unstage a look-alike live-index entry, and excluded a.txt '
      'restores byte-identically', () async {
    final repo = await _newTempRepo();
    try {
      await _rf(repo, 'a.txt').writeAsString('a1\n');
      await _rf(repo, 'b.txt').writeAsString('b1\n');
      await _rf(repo, '[bracket].txt').writeAsString('br1\n');
      await _rg(repo, ['add', '-A']);
      await _rg(repo, ['commit', '-qm', 'base']);

      // [bracket].txt: modified, INCLUDED -> committed -> drives reconcile.
      await _rf(repo, '[bracket].txt').writeAsString('br2\n');
      // a.txt: modified + STAGED + EXCLUDED -> exercises capture/restore.
      await _rf(repo, 'a.txt').writeAsString('a2\n');
      await _rg(repo, ['--literal-pathspecs', 'add', '--', 'a.txt']);
      final beforeA = (await _idx(repo))['a.txt'];

      final planRes = await prepareCommitStaging(repo, ['[bracket].txt']);
      expect(planRes.ok, isTrue, reason: planRes.error ?? '');
      final plan = planRes.data!;
      expect(plan.excludedEntries.map((e) => e.path), contains('a.txt'));

      // Out-of-band stage of b.txt AFTER prepare. `[bracket]` as a glob
      // matches the single-char name `b`, so a reconcile reset WITHOUT
      // --literal-pathspecs would unstage b.txt. This is the fix-3 witness.
      await _rf(repo, 'b.txt').writeAsString('b2\n');
      final add =
          await Process.run('git', ['add', 'b.txt'], workingDirectory: repo);
      expect(add.exitCode, 0, reason: add.stderr.toString());

      final commitRes = await createCommit(repo, 'bracket only', plan: plan);
      expect(commitRes.ok, isTrue, reason: commitRes.error ?? '');
      final restore = await finalizeCommitStaging(repo, plan, commitRes);
      expect(restore.ok, isTrue, reason: restore.error ?? '');

      // The commit contains exactly the bracket file's content — nothing
      // leaked via glob-matching at any layer.
      expect(await _headTouched(repo), {'[bracket].txt'});
      expect((await _rg(repo, ['show', 'HEAD:[bracket].txt'])).stdout, 'br2\n');
      expect((await _rg(repo, ['show', 'HEAD:a.txt'])).stdout, 'a1\n');

      // FIX 3: reconcile reset the bracket file ONLY. b.txt's look-alike
      // out-of-band stage survived — a plain (globbing) reset would have
      // matched the single-char `b` and reset it to HEAD, unstaging it.
      expect((await _rg(repo, ['show', ':b.txt'])).stdout, 'b2\n',
          reason: 'a glob reconcile reset would have unstaged look-alike b');

      // Live index reconciled for the bracket file only (no phantom staged
      // diff for it); the survivors are the excluded a.txt and the
      // out-of-band b.txt.
      final staged =
          ((await _rg(repo, ['diff', '--cached', '--name-only', '-z']))
                  .stdout as String)
              .split('\x00')
              .where((s) => s.isNotEmpty)
              .toSet();
      expect(staged, {'a.txt', 'b.txt'});

      // a.txt's excluded staged entry restored byte-identically.
      expect((await _idx(repo))['a.txt'], beforeA);
    } finally {
      await _rmRepo(repo);
    }
  });

  // --- Snapshot-mutating pre-commit hook reconciliation -------------------
  //
  // The snapshot commits against `GIT_INDEX_FILE` so a hook that mutates
  // the index (format-then-`git add`, the lint-staged pattern) mutates the
  // SNAPSHOT, not the live `.git/index`. Left alone, that produces a
  // phantom staged diff on success (live index stale for the hook-touched
  // path) or silently discards the hook's staging work on failure (the
  // snapshot is deleted). `createCommit` now reconciles/replays across
  // that boundary; these pin the exact contracts.

  Future<void> installHook(String repo, String script) async {
    final hooks = Directory('$repo${Platform.pathSeparator}.githooks');
    await hooks.create(recursive: true);
    final hookFile = File('${hooks.path}${Platform.pathSeparator}pre-commit');
    await hookFile.writeAsString(script);
    await _markHookExecutable(hookFile);
    await _rg(repo, ['config', 'core.hooksPath', hooks.path]);
  }

  test(
      'hook stages a fix and SUCCEEDS: HEAD gets the hook version, live '
      'index is reconciled (no phantom staged diff), excluded staging '
      'still restores byte-identically', () async {
    final repo = await _newTempRepo();
    try {
      await _rf(repo, 'tracked.txt').writeAsString('orig\n');
      await _rf(repo, 'excluded.txt').writeAsString('e1\n');
      await _rg(repo, ['add', '-A']);
      await _rg(repo, ['commit', '-qm', 'base']);

      await _rf(repo, 'tracked.txt').writeAsString('user-edit\n');
      await _rg(repo, ['add', 'tracked.txt']);
      await _rf(repo, 'excluded.txt').writeAsString('e2\n');
      await _rg(repo, ['add', 'excluded.txt']);
      final beforeExcluded = (await _idx(repo))['excluded.txt'];

      await installHook(repo, '#!/bin/sh\n'
          'printf "formatted\\n" > tracked.txt\n'
          'git add tracked.txt\n'
          'exit 0\n');

      final planRes = await prepareCommitStaging(repo, ['tracked.txt']);
      expect(planRes.ok, isTrue, reason: planRes.error ?? '');
      final plan = planRes.data!;
      final commitRes = await createCommit(repo, 'hook success', plan: plan);
      expect(commitRes.ok, isTrue, reason: commitRes.error ?? '');
      final restore =
          await restoreStagedSelections(repo, plan.excludedEntries);
      expect(restore.ok, isTrue, reason: restore.error ?? '');

      // HEAD carries the hook's rewrite, not the pre-hook staged content.
      expect(await _headTouched(repo), {'tracked.txt'});
      final headContent = (await _rg(repo, ['show', 'HEAD:tracked.txt']))
          .stdout as String;
      expect(headContent, 'formatted\n');

      // No phantom staged diff: the live index for tracked.txt now equals
      // HEAD, so `git diff --cached` shows only the restored excluded set.
      final staged = ((await _rg(repo, ['diff', '--cached', '--name-only', '-z']))
              .stdout as String)
          .split('\x00')
          .where((s) => s.isNotEmpty)
          .toSet();
      expect(staged, {'excluded.txt'});

      // The excluded entry survived the whole flow byte-identically.
      expect((await _idx(repo))['excluded.txt'], beforeExcluded);
    } finally {
      await _rmRepo(repo);
    }
  });

  test('hook stages a brand-new file and succeeds: it lands in HEAD with '
      'a clean live index', () async {
    final repo = await _newTempRepo();
    try {
      await _rf(repo, 'tracked.txt').writeAsString('orig\n');
      await _rg(repo, ['add', '-A']);
      await _rg(repo, ['commit', '-qm', 'base']);

      await _rf(repo, 'tracked.txt').writeAsString('edit\n');
      await _rg(repo, ['add', 'tracked.txt']);

      await installHook(repo, '#!/bin/sh\n'
          'printf "generated\\n" > generated.txt\n'
          'git add generated.txt\n'
          'exit 0\n');

      final planRes = await prepareCommitStaging(repo, ['tracked.txt']);
      expect(planRes.ok, isTrue, reason: planRes.error ?? '');
      final plan = planRes.data!;
      final commitRes = await createCommit(repo, 'hook adds file', plan: plan);
      expect(commitRes.ok, isTrue, reason: commitRes.error ?? '');
      await restoreStagedSelections(repo, plan.excludedEntries);

      expect(await _headTouched(repo), {'tracked.txt', 'generated.txt'});
      final headContent =
          (await _rg(repo, ['show', 'HEAD:generated.txt'])).stdout as String;
      expect(headContent, 'generated\n');

      // Clean: the new file is not left staged against its own HEAD blob.
      final staged = ((await _rg(repo, ['diff', '--cached', '--name-only']))
              .stdout as String)
          .trim();
      expect(staged, isEmpty);
    } finally {
      await _rmRepo(repo);
    }
  });

  test(
      'hook stages a fix and FAILS: commit absent, but the hook\'s staged '
      'entry survives in the live index; rollback still holds for '
      'everything else', () async {
    final repo = await _newTempRepo();
    try {
      await _rf(repo, 'tracked.txt').writeAsString('orig\n');
      await _rf(repo, 'excluded.txt').writeAsString('e1\n');
      await _rg(repo, ['add', '-A']);
      await _rg(repo, ['commit', '-qm', 'base']);

      await _rf(repo, 'tracked.txt').writeAsString('user-edit\n');
      await _rg(repo, ['add', 'tracked.txt']);
      await _rf(repo, 'excluded.txt').writeAsString('e2\n');
      await _rg(repo, ['add', 'excluded.txt']);
      final beforeExcluded = (await _idx(repo))['excluded.txt'];

      await installHook(repo, '#!/bin/sh\n'
          'printf "formatted\\n" > tracked.txt\n'
          'git add tracked.txt\n'
          'exit 1\n');

      final planRes = await prepareCommitStaging(repo, ['tracked.txt']);
      expect(planRes.ok, isTrue, reason: planRes.error ?? '');
      final plan = planRes.data!;
      final beforeHeadCount =
          (await _rg(repo, ['rev-list', '--count', 'HEAD'])).stdout as String;

      final commitRes = await createCommit(repo, 'hook failure', plan: plan);
      expect(commitRes.ok, isFalse, reason: 'commit should have failed');
      final restore =
          await restoreStagedSelections(repo, plan.excludedEntries);
      expect(restore.ok, isTrue, reason: restore.error ?? '');

      // No commit was created.
      expect((await _rg(repo, ['rev-list', '--count', 'HEAD'])).stdout,
          beforeHeadCount);

      // The hook's staged fix survived into the live index — replayed from
      // the snapshot before it was deleted.
      final trackedContent =
          (await _rg(repo, ['cat-file', '-p', ':tracked.txt'])).stdout
              as String;
      expect(trackedContent, 'formatted\n');
      final staged = ((await _rg(repo, ['diff', '--cached', '--name-only', '-z']))
              .stdout as String)
          .split('\x00')
          .where((s) => s.isNotEmpty)
          .toSet();
      expect(staged, {'tracked.txt', 'excluded.txt'});

      // Everything else rolled back exactly as the pre-existing contract
      // requires: excluded.txt's entry is byte-identical.
      expect((await _idx(repo))['excluded.txt'], beforeExcluded);
    } finally {
      await _rmRepo(repo);
    }
  });

  // --- Restore-precedence: a hook touching an EXCLUDED path -------------
  //
  // Regression pin for the ordering hole in the snapshot-commit fix: the
  // hook runs against the snapshot, so it can stage a path prepare had
  // already excluded (unstaged) from that same snapshot. Whatever it does
  // there is newer than the stale pre-commit capture restoreStagedSelections
  // would otherwise blindly write back. finalizeCommitStaging (not a bare
  // restoreStagedSelections call) is required to route around that.

  test(
      'hook stages an EXCLUDED path and the commit SUCCEEDS: HEAD gets the '
      'hook version (git semantics — a hook may stage anything, and '
      'whatever the index holds when `git commit` reads it lands in '
      'HEAD), the live index shows no phantom staged diff for it, the '
      'stale captured blob never reappears in the index, and the OTHER '
      'excluded entry still restores byte-identically', () async {
    final repo = await _newTempRepo();
    try {
      await _rf(repo, 'tracked.txt').writeAsString('orig\n');
      await _rf(repo, 'excluded.txt').writeAsString('e1\n');
      await _rf(repo, 'excluded_other.txt').writeAsString('o1\n');
      await _rg(repo, ['add', '-A']);
      await _rg(repo, ['commit', '-qm', 'base']);

      await _rf(repo, 'tracked.txt').writeAsString('user-edit\n');
      await _rg(repo, ['add', 'tracked.txt']);
      // A distinctive pre-commit blob so we can prove it never reappears.
      await _rf(repo, 'excluded.txt').writeAsString('STALE-CAPTURE\n');
      await _rg(repo, ['add', 'excluded.txt']);
      await _rf(repo, 'excluded_other.txt').writeAsString('o2\n');
      await _rg(repo, ['add', 'excluded_other.txt']);
      final beforeOther = (await _idx(repo))['excluded_other.txt'];

      // The hook runs with GIT_INDEX_FILE pointed at the snapshot, where
      // excluded.txt was already unstaged by prepare — the hook re-stages
      // it there itself.
      await installHook(repo, '#!/bin/sh\n'
          'printf "hook-version\\n" > excluded.txt\n'
          'git add excluded.txt\n'
          'exit 0\n');

      final planRes = await prepareCommitStaging(repo, ['tracked.txt']);
      expect(planRes.ok, isTrue, reason: planRes.error ?? '');
      final plan = planRes.data!;
      final commitRes =
          await createCommit(repo, 'hook stages excluded, success', plan: plan);
      expect(commitRes.ok, isTrue, reason: commitRes.error ?? '');
      final restore = await finalizeCommitStaging(repo, plan, commitRes);
      expect(restore.ok, isTrue, reason: restore.error ?? '');

      // The hook's re-staging of excluded.txt got committed — same
      // semantics as a hook staging any other path against a live index:
      // `git commit` commits whatever the index holds when it reads it.
      expect(await _headTouched(repo), {'tracked.txt', 'excluded.txt'});
      final headExcluded =
          (await _rg(repo, ['show', 'HEAD:excluded.txt'])).stdout as String;
      expect(headExcluded, 'hook-version\n');

      // No phantom staged diff: only the untouched excluded_other.txt is
      // staged; excluded.txt's live entry was reconciled to HEAD and the
      // stale capture was never written back over it.
      final staged =
          ((await _rg(repo, ['diff', '--cached', '--name-only', '-z']))
                  .stdout as String)
              .split('\x00')
              .where((s) => s.isNotEmpty)
              .toSet();
      expect(staged, {'excluded_other.txt'});

      // The stale captured blob never reappears in the index at all —
      // the index's excluded.txt entry is the hook's blob, not the stale
      // pre-commit one.
      final indexBlob =
          (await _rg(repo, ['show', ':excluded.txt'])).stdout as String;
      expect(indexBlob, isNot('STALE-CAPTURE\n'));
      expect(indexBlob, 'hook-version\n');

      // The OTHER excluded entry — untouched by the hook — still restores
      // byte-identically.
      expect((await _idx(repo))['excluded_other.txt'], beforeOther);
    } finally {
      await _rmRepo(repo);
    }
  });

  test(
      'hook stages an EXCLUDED path and the commit FAILS: the hook\'s '
      'staged entry (mode+oid) survives in the live index — not the '
      'stale captured entry — and the OTHER excluded entry restores '
      'normally', () async {
    final repo = await _newTempRepo();
    try {
      await _rf(repo, 'tracked.txt').writeAsString('orig\n');
      await _rf(repo, 'excluded.txt').writeAsString('e1\n');
      await _rf(repo, 'excluded_other.txt').writeAsString('o1\n');
      await _rg(repo, ['add', '-A']);
      await _rg(repo, ['commit', '-qm', 'base']);

      await _rf(repo, 'tracked.txt').writeAsString('user-edit\n');
      await _rg(repo, ['add', 'tracked.txt']);
      await _rf(repo, 'excluded.txt').writeAsString('STALE-CAPTURE\n');
      await _rg(repo, ['add', 'excluded.txt']);
      await _rf(repo, 'excluded_other.txt').writeAsString('o2\n');
      await _rg(repo, ['add', 'excluded_other.txt']);
      final beforeOther = (await _idx(repo))['excluded_other.txt'];

      await installHook(repo, '#!/bin/sh\n'
          'printf "hook-version\\n" > excluded.txt\n'
          'git add excluded.txt\n'
          'exit 1\n');

      final planRes = await prepareCommitStaging(repo, ['tracked.txt']);
      expect(planRes.ok, isTrue, reason: planRes.error ?? '');
      final plan = planRes.data!;
      final beforeHeadCount =
          (await _rg(repo, ['rev-list', '--count', 'HEAD'])).stdout as String;

      final commitRes =
          await createCommit(repo, 'hook stages excluded, failure', plan: plan);
      expect(commitRes.ok, isFalse, reason: 'commit should have failed');
      final restore = await finalizeCommitStaging(repo, plan, commitRes);
      expect(restore.ok, isTrue, reason: restore.error ?? '');

      // No commit was created.
      expect((await _rg(repo, ['rev-list', '--count', 'HEAD'])).stdout,
          beforeHeadCount);

      // The hook's staged entry for excluded.txt survives in the live
      // index — the stale capture must not have overwritten it.
      final indexBlob =
          (await _rg(repo, ['show', ':excluded.txt'])).stdout as String;
      expect(indexBlob, isNot('STALE-CAPTURE\n'));
      expect(indexBlob, 'hook-version\n');

      // The OTHER excluded entry — untouched by the hook — restores
      // exactly as the pre-existing contract requires.
      expect((await _idx(repo))['excluded_other.txt'], beforeOther);
    } finally {
      await _rmRepo(repo);
    }
  });

  // --- The operation-delta oracle: amend, root commit, message-only ------
  //
  // _reconcileLiveIndexAfterSnapshotCommit used to derive "what did this
  // commit touch" from `git diff-tree --no-commit-id HEAD` — no explicit
  // base, i.e. "diff HEAD against its own parent". That answers the wrong
  // question for two shapes:
  //   * AMEND — the amended commit's parent is the PRE-amend commit's
  //     parent (amend never moves the parent pointer), so diffing against
  //     it reports the ENTIRE amended commit, including content carried
  //     over untouched from the pre-amend commit, as "just committed".
  //     finalizeCommitStaging then skips restoring an excluded staged
  //     selection on any such untouched file, silently dropping it.
  //   * ROOT COMMIT — no parent exists at all, so the single-rev
  //     `diff-tree HEAD` emits nothing and the live index is never
  //     reconciled after a repo's first commit.
  // The fix diffs the PRE-OPERATION tip (or the empty-tree oid when there
  // is none) against the post-operation tip — "what did this operation
  // land" — which is correct for all three shapes below.

  test(
      'AMEND regression (reviewer scenario): an excluded staged selection '
      'on a file already in the commit being amended survives the amend '
      'byte-identically, and only the newly-included file is folded in',
      () async {
    await seedAndCommit({'base.txt': 'b1\n'});
    await wf('x.txt').writeAsString('x1\n');
    await git(['add', 'x.txt']);
    await git(['commit', '-qm', 'commit X']);

    // Stage a selection on x.txt — EXCLUDED from the amend plan below.
    // Under the old HEAD-vs-parent oracle, x.txt reads as part of the
    // amended commit (true relative to its grandparent) and this
    // selection's restore gets skipped — the exact bug this pins.
    await wf('x.txt').writeAsString('x2\n');
    await git(['add', 'x.txt']);
    final beforeX = (await indexSnapshot())['x.txt'];

    // Only y.txt is folded into the amend.
    await wf('y.txt').writeAsString('y1\n');

    final plan = await prepareCommitStaging(repo, ['y.txt']);
    expect(plan.ok, isTrue, reason: plan.error ?? '');
    expect(plan.data!.excludedEntries.map((e) => e.path), contains('x.txt'));

    final commit = await createCommit(repo, 'amend folds in y',
        amend: true, plan: plan.data!);
    expect(commit.ok, isTrue, reason: commit.error ?? '');
    final restore = await finalizeCommitStaging(repo, plan.data!, commit);
    expect(restore.ok, isTrue, reason: restore.error ?? '');

    // The amended commit carries x.txt forward UNCHANGED (x1) and adds
    // y.txt — the plan's snapshot resets excluded paths to HEAD before the
    // commit runs, so the amend's real content delta is exactly {y.txt}.
    expect(await show('HEAD', 'x.txt'), 'x1\n');
    expect(await show('HEAD', 'y.txt'), 'y1\n');
    // THE FIX: committedPaths comes from the pre-amend-tip base, so it is
    // exactly {y.txt} — not {x.txt, y.txt} as the old single-rev oracle
    // would have reported.
    expect(commit.committedPaths, {'y.txt'});

    // THE FIX, restore side: x.txt's excluded staged selection (x2)
    // restores byte-identically.
    final after = await indexSnapshot();
    expect(after['x.txt'], beforeX);
    final staged = ((await git(['diff', '--cached', '--name-only', '-z']))
            .stdout as String)
        .split('\x00')
        .where((s) => s.isNotEmpty)
        .toSet();
    expect(staged, {'x.txt'},
        reason: 'y.txt must be reconciled to HEAD (no phantom staged '
            'diff); x.txt must be the only surviving staged selection');
  });

  test(
      'ROOT commit: the live index is reconciled after a repo\'s very '
      'first commit via the empty-tree base — an excluded staged '
      'selection restores, and the included file is not left '
      'phantom-staged', () async {
    // Deliberately no seedAndCommit — a fresh repo, zero commits, so HEAD
    // is unborn. Under the old oracle, `diff-tree --no-commit-id HEAD`
    // (no parent to diff against) emits nothing at all here, so the live
    // index reconcile short-circuits on an empty path set and never runs.
    await wf('a.txt').writeAsString('a1\n');
    await wf('staged-b.txt').writeAsString('b1\n');
    await git(['add', '-A']);
    final beforeB = (await indexSnapshot())['staged-b.txt'];

    final plan = await prepareCommitStaging(repo, ['a.txt']);
    expect(plan.ok, isTrue, reason: plan.error ?? '');
    expect(plan.data!.excludedEntries.map((e) => e.path),
        contains('staged-b.txt'));

    final commit = await createCommit(repo, 'root commit', plan: plan.data!);
    expect(commit.ok, isTrue, reason: commit.error ?? '');
    final restore = await finalizeCommitStaging(repo, plan.data!, commit);
    expect(restore.ok, isTrue, reason: restore.error ?? '');

    // Not `headTouchedPaths()` here — that closure's own oracle is the
    // single-rev `diff-tree HEAD` (no explicit base), which is exactly
    // the shape that returns NOTHING on a root commit (no parent to diff
    // against) and would make this assertion vacuously pass. Read the
    // committed tree directly instead: `ls-tree` against the actual root
    // commit, independent of any oracle this fix touches.
    final rootTree = ((await git(['ls-tree', '--name-only', '-r', 'HEAD']))
            .stdout as String)
        .split('\n')
        .where((s) => s.isNotEmpty)
        .toSet();
    expect(rootTree, {'a.txt'});
    expect(await show('HEAD', 'a.txt'), 'a1\n');
    // THE FIX: the empty-tree base makes the first commit's content
    // delta visible as {a.txt}, matching what actually landed.
    expect(commit.committedPaths, {'a.txt'});

    // THE FIX, restore side: `git diff --cached` shows ONLY the restored
    // excluded entry, never the just-committed a.txt (which pre-fix would
    // have stayed phantom-staged forever, since no reconcile ever ran on
    // a repo's first commit).
    final staged = ((await git(['diff', '--cached', '--name-only', '-z']))
            .stdout as String)
        .split('\x00')
        .where((s) => s.isNotEmpty)
        .toSet();
    expect(staged, {'staged-b.txt'});
    final after = await indexSnapshot();
    expect(after['staged-b.txt'], beforeB);
  });

  test(
      'message-only amend yields an empty operation-delta: nothing is '
      'reconciled and no reconcileWarning is raised, and the excluded '
      'staged selection restores exactly as before the amend', () async {
    await seedAndCommit({'x.txt': 'x1\n'});
    await wf('x.txt').writeAsString('x2\n');
    await git(['add', 'x.txt']);
    final beforeX = (await indexSnapshot())['x.txt'];

    // Nothing included — this amend only rewrites the commit message; the
    // pre-amend tip and the post-amend tip have an IDENTICAL tree (the
    // plan's snapshot resets the one excluded path back to HEAD).
    final plan = await prepareCommitStaging(repo, <String>[]);
    expect(plan.ok, isTrue, reason: plan.error ?? '');
    final commit = await createCommit(repo, 'new message only',
        amend: true, plan: plan.data!);
    expect(commit.ok, isTrue, reason: commit.error ?? '');
    // THE FIX must reason this through correctly: a message-only amend has
    // no content delta, so committedPaths is empty and there is nothing to
    // warn about — this is the CORRECT outcome, not a missed reconcile.
    expect(commit.committedPaths, isEmpty);
    expect(commit.reconcileWarning, isNull);

    final restore = await finalizeCommitStaging(repo, plan.data!, commit);
    expect(restore.ok, isTrue, reason: restore.error ?? '');

    expect(await show('HEAD', 'x.txt'), 'x1\n');
    final after = await indexSnapshot();
    expect(after['x.txt'], beforeX);
  });

  // --- Reset-failure surface: RESET HONESTY -------------------------------
  //
  // A failed post-commit live-index reset must never be reported as a
  // silent success, but also must never fail a commit that already
  // landed. Provoked deterministically (not mocked): a pre-existing
  // `.git/index.lock` makes `git reset` against the LIVE index fail every
  // time, verified empirically to produce the exact
  // "Unable to create ... File exists" shape `_isIndexLockContention`
  // recognizes (so the exec layer's retry loop genuinely exhausts, rather
  // than this being an artificial error injection). The commit itself is
  // unaffected: it runs against the snapshot's OWN `GIT_INDEX_FILE`, an
  // unrelated lock path, verified empirically to succeed even while the
  // live `.git/index.lock` is held.

  test(
      'reset-failure surface: a held live index.lock demotes the post-'
      'commit reconcile failure to a non-fatal reconcileWarning — the '
      'commit stands, and finalizeCommitStaging restore still succeeds',
      () async {
    await seedAndCommit({'a.txt': 'a1\n'});
    await wf('a.txt').writeAsString('a2\n');
    final plan = await prepareCommitStaging(repo, ['a.txt']);
    expect(plan.ok, isTrue, reason: plan.error ?? '');

    final lockFile = File(
        '$repo${Platform.pathSeparator}.git${Platform.pathSeparator}index.lock');
    await lockFile.writeAsString('');
    try {
      final commit =
          await createCommit(repo, 'lock contention', plan: plan.data!);
      expect(commit.ok, isTrue, reason: commit.error ?? '');
      // The diff-tree READ is unaffected by the lock (reads never touch
      // index.lock) — committedPaths is still correct.
      expect(commit.committedPaths, {'a.txt'});
      // THE FIX: the failed reset is surfaced, not swallowed.
      expect(commit.reconcileWarning, isNotNull,
          reason: 'the reset step should have failed against the held '
              'lock');
      expect(commit.reconcileWarning, contains('a.txt'));

      // finalizeCommitStaging's skip-set is computed from committedPaths
      // (a read), not from whether the reset succeeded — the disjointness
      // argument holds regardless, so restore still reports ok even
      // though the live index for a.txt is left stale.
      final restore = await finalizeCommitStaging(repo, plan.data!, commit);
      expect(restore.ok, isTrue, reason: restore.error ?? '');
    } finally {
      if (await lockFile.exists()) await lockFile.delete();
    }
  });

  // --- Replay-failure surface: REPLAY HONESTY (failure-path mirror) ------
  //
  // The mirror of the reset-honesty fix above, other branch — and the exact
  // scenario Manifold's own review flagged: same setup as "hook stages an
  // EXCLUDED path and the commit FAILS" above (a hook rewrites an EXCLUDED,
  // already-captured path inside the snapshot, then the hook itself fails),
  // except this time the replay of that rewrite onto the LIVE index is ALSO
  // forced to fail — a held `.git/index.lock`, the same deterministic
  // mechanism the reset-honesty test above uses, verified there to make a
  // live-index-targeting git call fail every time. Pre-fix,
  // _replayHookIndexMutations ignored its `update-index` calls' exit codes
  // and always reported the full touched set regardless, so
  // finalizeCommitStaging would skip restoring the OLDER captured entry for
  // excluded.txt even though the hook's rewrite never actually reached the
  // live index — neither version would survive. The fix: a failed replay
  // must not be reported as touched, so finalizeCommitStaging falls back to
  // the older capture instead of skipping it.

  test(
      'replay-failure surface (reviewer scenario): hook stages a fix to an '
      'EXCLUDED path, the commit FAILS, and a held live index.lock also '
      'fails the replay onto the live index — the OLDER captured excluded '
      'entry is restored (not skipped), the failure surfaces via '
      'hookReplayWarning, and the unrelated excluded entry is untouched',
      () async {
    final repo = await _newTempRepo();
    try {
      await _rf(repo, 'tracked.txt').writeAsString('orig\n');
      await _rf(repo, 'excluded.txt').writeAsString('e1\n');
      await _rf(repo, 'excluded_other.txt').writeAsString('o1\n');
      await _rg(repo, ['add', '-A']);
      await _rg(repo, ['commit', '-qm', 'base']);

      await _rf(repo, 'tracked.txt').writeAsString('user-edit\n');
      await _rg(repo, ['add', 'tracked.txt']);
      // A distinctive pre-commit blob so we can prove it survives (and that
      // the hook's version, which never lands live under the held lock,
      // does not silently take its place).
      await _rf(repo, 'excluded.txt').writeAsString('STALE-CAPTURE\n');
      await _rg(repo, ['add', 'excluded.txt']);
      await _rf(repo, 'excluded_other.txt').writeAsString('o2\n');
      await _rg(repo, ['add', 'excluded_other.txt']);
      final beforeOther = (await _idx(repo))['excluded_other.txt'];

      // The hook runs with GIT_INDEX_FILE pointed at the snapshot, where
      // excluded.txt was already unstaged by prepare — the hook re-stages
      // it there itself, then fails.
      await installHook(repo, '#!/bin/sh\n'
          'printf "hook-version\\n" > excluded.txt\n'
          'git add excluded.txt\n'
          'exit 1\n');

      final planRes = await prepareCommitStaging(repo, ['tracked.txt']);
      expect(planRes.ok, isTrue, reason: planRes.error ?? '');
      final plan = planRes.data!;
      final beforeHeadCount =
          (await _rg(repo, ['rev-list', '--count', 'HEAD'])).stdout as String;

      final lockFile = File(
          '$repo${Platform.pathSeparator}.git${Platform.pathSeparator}index.lock');
      await lockFile.writeAsString('');
      CommitAttemptResult commitRes;
      try {
        // Held only across createCommit itself, long enough to exhaust the
        // replay's `update-index` retries against the live index. Released
        // before finalizeCommitStaging runs below — restoreStagedSelections
        // is itself a live-index write with real work to do here (both
        // excluded paths need restoring), so holding the lock across it
        // would fail the restore for an unrelated reason and defeat the
        // point of this test.
        commitRes = await createCommit(repo, 'hook + replay failure',
            plan: plan);
      } finally {
        if (await lockFile.exists()) await lockFile.delete();
      }
      expect(commitRes.ok, isFalse, reason: 'commit should have failed');

      // THE FIX: the replay's update-index call lost the race for the live
      // index.lock, so excluded.txt's hook rewrite was never actually
      // recovered onto the live index — hookTouchedPaths must NOT claim
      // it, and the failure must be surfaced rather than swallowed.
      expect(commitRes.hookTouchedPaths, isEmpty,
          reason: 'the replay never landed, so nothing should be reported '
              'as successfully replayed');
      expect(commitRes.hookReplayWarning, isNotNull,
          reason: 'a failed replay must surface, not be swallowed');
      expect(commitRes.hookReplayWarning, contains('excluded.txt'));

      final restore = await finalizeCommitStaging(repo, plan, commitRes);
      expect(restore.ok, isTrue, reason: restore.error ?? '');

      // No commit was created.
      expect((await _rg(repo, ['rev-list', '--count', 'HEAD'])).stdout,
          beforeHeadCount);

      // THE FIX: since hookTouchedPaths correctly excludes excluded.txt
      // (the replay didn't land), finalizeCommitStaging did NOT skip
      // restoring it — the OLDER captured selection (STALE-CAPTURE) is
      // what ends up in the live index, never the hook's unreplayed
      // "hook-version" (which never reached the live index while the lock
      // was held) and never nothing.
      final indexBlob =
          (await _rg(repo, ['show', ':excluded.txt'])).stdout as String;
      expect(indexBlob, 'STALE-CAPTURE\n',
          reason: 'the older captured selection must be restored when the '
              'hook replay could not land — never neither version');

      // The OTHER excluded entry — untouched by the hook or the lock —
      // still restores exactly as the pre-existing contract requires.
      expect((await _idx(repo))['excluded_other.txt'], beforeOther);
    } finally {
      await _rmRepo(repo);
    }
  });
}

// ===========================================================================
// Generative harness for the exact-staging contract. Fixed literal seed so a
// failure is exactly replayable — every assertion carries `seed=... case=...`
// (and the derived included set) so the offending case can be rebuilt with
// `math.Random(_kStagingSeed + case)`.
// ===========================================================================

const int _kStagingSeed = 0x5EED2026;

Future<ProcessResult> _rg(String repo, List<String> args) => Process.run(
      'git',
      args,
      workingDirectory: repo,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

/// POSIX git silently SKIPS a hook without the executable bit (git-for-Windows
/// execs hooks via sh regardless), so every test-written hook must be chmod'd
/// or the whole hook scenario is vacuously green on Windows and red on Linux.
Future<void> _markHookExecutable(File hook) async {
  if (Platform.isWindows) return;
  await Process.run('chmod', ['+x', hook.path]);
}

Future<ProcessResult> _rgBytes(String repo, List<String> args) => Process.run(
      'git',
      args,
      workingDirectory: repo,
      stdoutEncoding: null,
      stderrEncoding: null,
    );

Future<String> _newTempRepo() async {
  final dir = await Directory.systemTemp.createTemp('gdpu_prop_');
  final repo = dir.path;
  await _rg(repo, ['init', '-q', '-b', 'main']);
  await _rg(repo, ['config', 'user.email', 'a@b.c']);
  await _rg(repo, ['config', 'user.name', 'test']);
  await _rg(repo, ['config', 'core.autocrlf', 'false']);
  await _rg(repo, ['config', 'commit.gpgsign', 'false']);
  return repo;
}

Future<void> _rmRepo(String repo) async {
  try {
    await Directory(repo).delete(recursive: true);
  } catch (_) {
    // Windows briefly holds git handles; the OS reaps the temp dir. See
    // desk_pr_store_test's _safeCleanup for the same tolerated race.
  }
}

File _rf(String repo, String rel) => File(
    '$repo${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}');

/// Index snapshot: path → "mode oid stage", read straight from git.
Future<Map<String, String>> _idx(String repo) async {
  final out = (await _rg(repo, ['ls-files', '-s', '-z'])).stdout as String;
  final map = <String, String>{};
  for (final rec in out.split('\x00')) {
    if (rec.isEmpty) continue;
    final tab = rec.indexOf('\t');
    if (tab < 0) continue;
    map[rec.substring(tab + 1)] = rec.substring(0, tab);
  }
  return map;
}

/// Paths touched by HEAD vs its parent, from the object database.
Future<Set<String>> _headTouched(String repo) async {
  final out = (await _rg(repo,
          ['diff-tree', '--no-commit-id', '--name-only', '-z', '-r', 'HEAD']))
      .stdout as String;
  return out.split('\x00').where((p) => p.isNotEmpty).toSet();
}

/// Raw bytes of `HEAD:<path>`, or null if the blob is absent.
Future<List<int>?> _showBytes(String repo, String path) async {
  final r = await _rgBytes(repo, ['show', 'HEAD:$path']);
  if (r.exitCode != 0) return null;
  return r.stdout as List<int>;
}

Future<Map<String, List<int>?>> _diskBytes(
    String repo, List<String> paths) async {
  final map = <String, List<int>?>{};
  for (final path in paths) {
    final f = _rf(repo, path);
    map[path] = await f.exists() ? await f.readAsBytes() : null;
  }
  return map;
}

bool _bytesEq(List<int>? a, List<int>? b) {
  if (a == null || b == null) return identical(a, b) || (a == null && b == null);
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The INDEPENDENT oracle for the includable subset — derived purely from
/// `git status`, never from the helpers under test. A path in [included] is
/// includable exactly when git reports it as a non-conflicted change that
/// will end up in the commit:
///   * already staged (X ∈ {A,M,D,...}, not '?'/' ') → stays staged → in;
///   * unstaged/untracked → stagePaths must `git add` it, which SKIPS a
///     gitignored path and a path missing from disk (an unstaged deletion),
///     so it is includable only when it exists and is not ignored;
///   * absent from `status -uall` (clean, or inside a gitignored dir) → out;
///   * conflicted (U*, AA, DD) → the walk skips it → out.
/// This is the exact "commit-exactly-the-included-paths, minus what git
/// itself refuses to stage" contract the suite verifies.
Future<Set<String>> _committable(String repo, Set<String> included) async {
  final st = (await _rg(
          repo, ['status', '--porcelain', '-z', '--no-renames', '-uall']))
      .stdout as String;
  final xy = <String, String>{};
  for (final rec in st.split('\x00')) {
    if (rec.length < 4) continue;
    xy[rec.substring(3)] = rec.substring(0, 2);
  }
  final out = <String>{};
  for (final path in included) {
    final code = xy[path];
    if (code == null) continue;
    final x = code[0], y = code[1];
    final conflicted =
        x == 'U' || y == 'U' || (x == 'A' && y == 'A') || (x == 'D' && y == 'D');
    if (conflicted) continue;
    final staged = x != ' ' && x != '?';
    if (staged) {
      out.add(path);
      continue;
    }
    if (!await _rf(repo, path).exists()) continue; // unstaged deletion dropped
    if ((await _rg(repo, ['check-ignore', '--', path])).exitCode == 0) {
      continue; // gitignored path filtered by stagePaths
    }
    out.add(path);
  }
  return out;
}

enum _K {
  modified,
  staged,
  partial,
  stagedDel,
  unstagedDel,
  untrackedExisting,
  untrackedNew,
  ignored,
}

/// One generated file in a case: its path, ingredient kind, and — when the
/// commit is expected to contain it — the EXACT bytes the committed blob
/// must hold (the staged content, which for a partially-staged file is v2,
/// NOT the later worktree v3).
class _Spec {
  final String path;
  final _K kind;
  final List<int>? committedBytes;
  _Spec(this.path, this.kind, this.committedBytes);
}

List<int> _content(math.Random rng, String tag) {
  final crlf = rng.nextBool();
  final nl = crlf ? '\r\n' : '\n';
  final sb = StringBuffer();
  final lines = 1 + rng.nextInt(4);
  for (var i = 0; i < lines; i++) {
    sb.write('line$i-$tag-${rng.nextInt(100000)}$nl');
  }
  if (rng.nextBool()) sb.write('ünïçödé-✓-$tag$nl'); // NFC unicode + checkmark
  return utf8.encode(sb.toString());
}

/// Build a randomized repo state exercising every ingredient (several of
/// each, mixed), plus hostile filenames (spaces, NFC unicode, [brackets],
/// an apostrophe, a 150-char name, and a strict-prefix pair) and CRLF/LF
/// content. Returns the specs; the repo is left with the mutations applied
/// and one base commit behind them.
Future<List<_Spec>> _buildCase(String repo, math.Random rng) async {
  var uid = 0;
  String u() => (uid++).toString();
  var shape = 0;
  // Root-level hostile-name factory: cycles through the required shapes so
  // every case exercises all of them.
  String hostile(String t) {
    switch (shape++ % 6) {
      case 0:
        return 'plain_$t.txt';
      case 1:
        return 'spaces here $t.txt';
      case 2:
        return 'café_ñ_$t.txt'; // NFC (é U+00E9, ñ U+00F1)
      case 3:
        return '[br_$t].txt';
      case 4:
        return "it's_$t.txt";
      default:
        final head = 'long_${t}_';
        return head + 'a' * (150 - head.length); // 150-char name
    }
  }

  // Short names for nested-dir files, to stay well under Windows MAX_PATH.
  String short(String t) => 'n_$t.txt';

  final specs = <_Spec>[];
  final base = <String, List<int>>{}; // tracked files present at base commit
  base['existing_dir/anchor.txt'] = utf8.encode('anchor\n');
  base['.gitignore'] = utf8.encode('ignored_dir/\n');

  final modified = <String>[]; // unstaged worktree edit
  final staged = <String>[]; // staged edit, not re-touched
  final partialV2 = <String, List<int>>{}; // staged content
  final partialV3 = <String, List<int>>{}; // later worktree content
  final stagedDel = <String>[];
  final unstagedDel = <String>[];
  final untrackedWrites = <String, List<int>>{};
  final ignoredWrites = <String, List<int>>{};
  final worktreeAfter = <String, List<int>>{}; // for modified/staged writes

  void tracked(String path, _K kind) {
    base[path] = _content(rng, 'b$path');
    switch (kind) {
      case _K.modified:
        final v2 = _content(rng, 'v2');
        worktreeAfter[path] = v2;
        modified.add(path);
        specs.add(_Spec(path, kind, v2));
        break;
      case _K.staged:
        final v2 = _content(rng, 'v2');
        worktreeAfter[path] = v2;
        staged.add(path);
        specs.add(_Spec(path, kind, v2));
        break;
      case _K.partial:
        partialV2[path] = _content(rng, 'v2');
        partialV3[path] = _content(rng, 'v3');
        // Committed blob is the STAGED v2, not the worktree v3.
        specs.add(_Spec(path, kind, partialV2[path]));
        break;
      case _K.stagedDel:
        stagedDel.add(path);
        specs.add(_Spec(path, kind, null));
        break;
      case _K.unstagedDel:
        unstagedDel.add(path);
        specs.add(_Spec(path, kind, null));
        break;
      default:
        break;
    }
  }

  // Strict-prefix pair (both modified): `stem_N` is a strict prefix of
  // `stem_Nx` — a pathspec of the shorter must not drag the longer in.
  final pt = u();
  tracked('stem_$pt', _K.modified);
  tracked('stem_${pt}x', _K.modified);
  // The rest of the tracked ingredients, hostile-named.
  tracked(hostile(u()), _K.modified);
  tracked(hostile(u()), _K.staged);
  tracked(hostile(u()), _K.staged);
  tracked(hostile(u()), _K.partial);
  tracked(hostile(u()), _K.partial);
  tracked('del_staged_${u()}.txt', _K.stagedDel);
  tracked('del_unstaged_${u()}.txt', _K.unstagedDel);

  // Untracked in an already-tracked directory.
  for (var k = 0; k < 2; k++) {
    final path = 'existing_dir/${hostile(u())}';
    final c = _content(rng, 'ue');
    untrackedWrites[path] = c;
    specs.add(_Spec(path, _K.untrackedExisting, c));
  }
  // Untracked in brand-new directories — one at depth 1, one nested two
  // levels deep (the exact dir-collapse regression shape).
  {
    final p1 = 'brandnew_${u()}/${short(u())}';
    final c1 = _content(rng, 'un1');
    untrackedWrites[p1] = c1;
    specs.add(_Spec(p1, _K.untrackedNew, c1));
    final p2 = 'brandnew_${u()}/lvl1/lvl2/${short(u())}';
    final c2 = _content(rng, 'un2');
    untrackedWrites[p2] = c2;
    specs.add(_Spec(p2, _K.untrackedNew, c2));
  }
  // Files inside a gitignored directory (never committable).
  {
    final p1 = 'ignored_dir/${short(u())}';
    final c1 = _content(rng, 'ig1');
    ignoredWrites[p1] = c1;
    specs.add(_Spec(p1, _K.ignored, null));
    final p2 = 'ignored_dir/sub/${short(u())}';
    final c2 = _content(rng, 'ig2');
    ignoredWrites[p2] = c2;
    specs.add(_Spec(p2, _K.ignored, null));
  }

  // Seed the base commit.
  for (final e in base.entries) {
    final f = _rf(repo, e.key);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(e.value);
  }
  await _rg(repo, ['add', '-A']);
  await _rg(repo, ['commit', '-qm', 'base']);

  // Apply the mutations.
  for (final path in modified) {
    await _rf(repo, path).writeAsBytes(worktreeAfter[path]!);
  }
  for (final path in staged) {
    await _rf(repo, path).writeAsBytes(worktreeAfter[path]!);
  }
  for (final path in partialV2.keys) {
    await _rf(repo, path).writeAsBytes(partialV2[path]!);
  }
  final toStage = [...staged, ...partialV2.keys];
  if (toStage.isNotEmpty) {
    await _rg(repo, ['--literal-pathspecs', 'add', '--', ...toStage]);
  }
  // Now re-edit the partials so index (v2) != worktree (v3).
  for (final path in partialV3.keys) {
    await _rf(repo, path).writeAsBytes(partialV3[path]!);
  }
  if (stagedDel.isNotEmpty) {
    await _rg(repo, ['--literal-pathspecs', 'rm', '-q', '--', ...stagedDel]);
  }
  for (final path in unstagedDel) {
    final f = _rf(repo, path);
    if (await f.exists()) await f.delete();
  }
  for (final e in untrackedWrites.entries) {
    final f = _rf(repo, e.key);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(e.value);
  }
  for (final e in ignoredWrites.entries) {
    final f = _rf(repo, e.key);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(e.value);
  }
  return specs;
}
