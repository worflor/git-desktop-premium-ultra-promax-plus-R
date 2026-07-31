// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_target_test.dart — resolving a review subject against real history.
//
// Every test here builds an actual git repository with a deliberately shaped
// history and asserts what `resolveReviewTarget` produces from it. Nothing is
// mocked: the traps this guards against are all git BEHAVIOURS (a merge shows
// no diff, a reversed range shows a perfectly valid inverted one, a shallow
// boundary claims to be a root), and a fake git would have to reproduce the
// very behaviour under test to be useful.
//
// The history every test shares:
//
//   r0 ── c1 ── c2 ── c3 ─── M     (main)
//          \               /
//           f1 ───────────       (feature)
//
//   r0  root commit: a.txt="1"
//   c1  a.txt="2", b.txt="x"
//   c2  b.txt="y"                 <- changed away
//   c3  b.txt="x", a.txt="3"      <- and back again
//   f1  c.txt="f"                 (branched from c1)
//   M   merge feature into main
//
// c2 and c3 are shaped so b.txt's change CANCELS across c1..c3. That is the
// property that makes a range a tree pair rather than a pile of commits, and
// it is asserted directly rather than assumed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_commit_axis.dart';
import 'package:git_desktop/backend/logos_git_stats.dart';
import 'package:git_desktop/backend/review_target.dart';

import '../support/scratch_repo.dart';

class _History {
  final ScratchRepo repo;
  final String r0, c1, c2, c3, f1, m;
  const _History(this.repo,
      {required this.r0,
      required this.c1,
      required this.c2,
      required this.c3,
      required this.f1,
      required this.m});
}

Future<_History> _buildHistory() async {
  final repo = await ScratchRepo.create(name: 'review_target');

  await repo.writeFile('a.txt', '1\n');
  final r0 = await repo.commitAll('root: seed a');

  await repo.writeFile('a.txt', '2\n');
  await repo.writeFile('b.txt', 'x\n');
  final c1 = await repo.commitAll('add b, bump a');

  await repo.gitOk(['checkout', '-b', 'feature']);
  await repo.writeFile('c.txt', 'f\n');
  final f1 = await repo.commitAll('feature: add c');

  await repo.gitOk(['checkout', 'main']);
  await repo.writeFile('b.txt', 'y\n');
  final c2 = await repo.commitAll('flip b to y');

  await repo.writeFile('b.txt', 'x\n');
  await repo.writeFile('a.txt', '3\n');
  final c3 = await repo.commitAll('flip b back, bump a');

  await repo.gitOk(['merge', '--no-ff', 'feature', '-m', 'merge feature']);
  final m = (await repo.head())!;

  return _History(repo, r0: r0, c1: c1, c2: c2, c3: c3, f1: f1, m: m);
}

void main() {
  late _History h;

  setUpAll(() async => h = await _buildHistory());
  tearDownAll(() async => h.repo.dispose());

  String path(String p) => p;

  Future<ResolvedReviewScope> resolveOk(
    ReviewTarget target, {
    List<String> paths = const [],
    LogosCommitAxis axis = LogosCommitAxis.emptyAxis,
  }) async {
    final r = await resolveReviewTarget(
      repositoryPath: h.repo.dir.path,
      target: target,
      scopedPaths: paths,
      axis: axis,
    );
    expect(r.ok, isTrue, reason: 'resolution failed: ${r.error}');
    return r.data!;
  }

  Future<String> resolveErr(ReviewTarget target,
      {List<String> paths = const []}) async {
    final r = await resolveReviewTarget(
      repositoryPath: h.repo.dir.path,
      target: target,
      scopedPaths: paths,
    );
    expect(r.ok, isFalse,
        reason: 'expected a refusal, got a scope over ${r.data?.paths}');
    return r.error!;
  }

  // ── single commits ──────────────────────────────────────────────

  test('T1: a commit resolves to exactly its own change', () async {
    final s = await resolveOk(CommitTarget(h.c2));
    expect(s.paths, [path('b.txt')]);
    expect(s.diffText, contains('-x'));
    expect(s.diffText, contains('+y'));
    expect(s.label, contains('flip b to y'));
    expect(s.branchName, h.c2.substring(0, 7));
    expect(s.isRetrospective, isTrue);
  });

  test('T2: a revspec is resolved, not just a raw OID', () async {
    final byName = await resolveOk(const CommitTarget('main~1'));
    final byOid = await resolveOk(CommitTarget(h.c3));
    expect(byName.paths, byOid.paths);
    expect(byName.diffText, byOid.diffText);
  });

  test('T3: the ROOT commit diffs against the empty tree, not nothing',
      () async {
    // No parent to name. Without `--root` git emits an empty patch and the
    // review would report a clean bill on the commit that created the repo.
    final s = await resolveOk(CommitTarget(h.r0));
    expect(s.paths, contains('a.txt'));
    expect(s.diffText, contains('new file mode'));
    expect(s.diffText, contains('+1'));
  });

  test('T4: a MERGE resolves to its first-parent diff and says so', () async {
    // `git show <merge>` and `git diff-tree -p <merge>` both emit NOTHING.
    // Reviewing that empty patch would have reported "no findings" — a clean
    // bill on an unreviewed merge.
    final raw = await h.repo.git(['diff-tree', '-p', '--no-commit-id', h.m]);
    expect((raw.stdout as String).trim(), isEmpty,
        reason: 'guard: git itself must still show a merge as empty, '
            'otherwise this test is no longer testing anything');

    final s = await resolveOk(CommitTarget(h.m));
    expect(s.paths, [path('c.txt')],
        reason: 'the merge brought c.txt in from the feature branch');
    expect(s.label, contains('first-parent'));
    expect(s.diffText, contains('c.txt'));
  });

  // ── ranges ──────────────────────────────────────────────────────

  test('T5: a range is a TREE PAIR — cancelled changes do not appear',
      () async {
    // b.txt goes x -> y in c2 and y -> x in c3. Each commit's own diff touches
    // it; the range's does not. This is why a range can never be assembled
    // from its commits' patches.
    final perCommit = await resolveOk(CommitTarget(h.c2));
    expect(perCommit.paths, contains('b.txt'));

    final s = await resolveOk(
        RangeTarget(base: h.c1, tip: h.c3, mergeBase: false));
    expect(s.paths, ['a.txt'],
        reason: 'b.txt changed and changed back, so the range does not touch '
            'it — got ${s.paths}');
    expect(s.label, contains('2 commits'));
  });

  test('T6: two-dot compares endpoints, three-dot compares from the merge base',
      () async {
    // Compared against c3 — main's tip BEFORE the merge. Against `main`
    // itself the three-dot range is legitimately empty, because merging is
    // exactly what makes a branch contribute nothing further.
    //  - two-dot c3..feature shows feature's addition AND main's advance,
    //    inverted, because it is a straight tree comparison.
    //  - three-dot shows only what feature added.
    final twoDot = await resolveOk(
        RangeTarget(base: h.c3, tip: 'feature', mergeBase: false));
    final threeDot = await resolveOk(
        RangeTarget(base: h.c3, tip: 'feature', mergeBase: true));

    expect(threeDot.paths, ['c.txt'],
        reason: 'only what feature added — got ${threeDot.paths}');
    expect(twoDot.paths, contains('a.txt'),
        reason: 'a straight comparison also sees main advancing a.txt');
    expect(twoDot.paths.length, greaterThan(threeDot.paths.length));
    expect(threeDot.label, contains('...'));
  });

  test('T7: branchDelta is the three-dot comparison', () async {
    final sugar = await resolveOk(
        RangeTarget.branchDelta('feature', against: h.c3));
    final explicit = await resolveOk(
        RangeTarget(base: h.c3, tip: 'feature', mergeBase: true));
    expect(sugar.paths, explicit.paths);
    expect(sugar.diffText, explicit.diffText);
  });

  test('T7b: a branch already merged in contributes nothing further',
      () async {
    // The three-dot range main...feature after the merge. Refusing is the
    // honest answer — there is genuinely no delta left to review.
    final err = await resolveErr(
        const RangeTarget(base: 'main', tip: 'feature', mergeBase: true));
    expect(err, contains('same commit'));
  });

  test('T8: a REVERSED range is refused, never silently inverted', () async {
    // git produces a perfectly valid patch for this; every addition in it is
    // a deletion. Nothing downstream could tell, and every finding would be
    // exactly backwards.
    final valid = await h.repo.git(['diff', '${h.c3}..${h.c1}']);
    expect((valid.stdout as String).trim(), isNotEmpty,
        reason: 'guard: git must still happily emit the inverted patch');

    final err =
        await resolveErr(RangeTarget(base: h.c3, tip: h.c1, mergeBase: false));
    expect(err, contains('backwards'));
    expect(err, contains('Did you mean'));
  });

  test('T9: divergent revisions are a legitimate two-dot comparison', () async {
    // feature and c3 are on different branches; neither is an ancestor of the
    // other. That is a comparison, not a reversal, and must pass.
    final s = await resolveOk(
        RangeTarget(base: h.c3, tip: h.f1, mergeBase: false));
    expect(s.paths, isNotEmpty);
  });

  test('T10: an empty range is refused with its own message', () async {
    final err =
        await resolveErr(
            const RangeTarget(base: 'main', tip: 'main', mergeBase: false));
    expect(err, contains('same commit'));
  });

  // ── refusals ────────────────────────────────────────────────────

  test('T11: an unknown revision names itself', () async {
    final err = await resolveErr(const CommitTarget('no-such-ref'));
    expect(err, contains('Unknown revision'));
    expect(err, contains('no-such-ref'));
  });

  test('T12: an EMPTY commit is refused rather than reviewed', () async {
    await h.repo.gitOk(['commit', '--allow-empty', '-m', 'nothing at all']);
    final empty = (await h.repo.head())!;
    final err = await resolveErr(CommitTarget(empty));
    expect(err, contains('no file changes'));
    // Leave history as we found it for the tests that share it.
    await h.repo.gitOk(['reset', '--hard', 'HEAD~1']);
  });

  test('T13: a BINARY-only commit is refused rather than reviewed as blank',
      () async {
    final bin = File('${h.repo.dir.path}${Platform.pathSeparator}blob.bin');
    await bin.writeAsBytes([0, 1, 2, 3, 0, 255, 7, 9]);
    await h.repo.commitAll('add a binary blob');
    final binCommit = (await h.repo.head())!;

    final err = await resolveErr(CommitTarget(binCommit));
    expect(err, contains('binary'));

    await h.repo.gitOk(['reset', '--hard', 'HEAD~1']);
  });

  // ── scoping ─────────────────────────────────────────────────────

  test('T14: path scoping narrows a range to the paths asked for', () async {
    final all =
        await resolveOk(RangeTarget(base: h.r0, tip: h.c3, mergeBase: false));
    expect(all.paths, containsAll(<String>['a.txt', 'b.txt']));

    final scoped = await resolveOk(
      RangeTarget(base: h.r0, tip: h.c3, mergeBase: false),
      paths: ['a.txt'],
    );
    expect(scoped.paths, ['a.txt']);
    expect(scoped.diffText, isNot(contains('b.txt')));
  });

  test('T15: a path that the range never touches is a refusal, not an '
      'empty success', () async {
    final err = await resolveErr(
      RangeTarget(base: h.c2, tip: h.c3, mergeBase: false),
      paths: ['c.txt'],
    );
    expect(err, contains('no file changes'));
  });

  // ── shallow clones ──────────────────────────────────────────────

  test('T14b: a pathspec far past the argv limit is CHUNKED, not refused',
      () async {
    // This used to be a flat refusal above ~24 KB of pathspec — a ceiling
    // standing in for the work of chunking, on exactly the input a big
    // scoped sweep produces. The pathspec below is several times the
    // Windows command-line limit on its own.
    final many = <String>[];
    for (var i = 0; i < 4000; i++) {
      many.add('generated/deep/nested/path/segment/file_$i.dart');
    }
    // The real changed path is buried in the middle, so a truncating
    // implementation would silently lose it rather than fail.
    many.insert(2000, 'b.txt');
    final scopeBytes =
        many.fold<int>(0, (sum, p) => sum + p.length + 3);
    expect(scopeBytes, greaterThan(120000),
        reason: 'guard: this must exceed one command line by a wide margin');

    final s = await resolveOk(CommitTarget(h.c2), paths: many);
    expect(s.paths, ['b.txt'],
        reason: 'the one real path was found across chunk boundaries');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('T15b: a SHALLOW boundary commit is refused, not diffed as a root',
      () async {
    // The trap: git hides a grafted commit's parents, so `rev-list --parents`
    // reports none — exactly like a genuine root commit. Diffing it with
    // --root would render every file in the tree as newly added and hand the
    // reviewer a fabricated change to review.
    final host = Directory.systemTemp.createTempSync('shallow_host_');
    try {
      final url = Uri.file(h.repo.dir.path).toString();
      final dest = '${host.path}${Platform.pathSeparator}clone';
      final cloned = await Process.run(
        'git',
        ['clone', '--depth', '1', '--no-local', url, dest],
        environment: const {'GIT_TERMINAL_PROMPT': '0'},
      );
      expect(cloned.exitCode, 0,
          reason: 'clone --depth 1 failed: ${cloned.stderr}');

      final isShallow = await Process.run(
          'git', ['rev-parse', '--is-shallow-repository'],
          workingDirectory: dest);
      expect((isShallow.stdout as String).trim(), 'true',
          reason: 'guard: the clone must actually be shallow');

      // The boundary commit reports no parents...
      final parents = await Process.run(
          'git', ['rev-list', '--parents', '-n', '1', 'HEAD'],
          workingDirectory: dest);
      expect((parents.stdout as String).trim().split(RegExp(r'\s+')).length, 1,
          reason: 'guard: git must still hide the grafted parent');

      // ...but is refused rather than treated as a root.
      final r = await resolveReviewTarget(
        repositoryPath: dest,
        target: const CommitTarget('HEAD'),
      );
      expect(r.ok, isFalse,
          reason: 'a grafted boundary was diffed as a root, inventing '
              '${r.data?.paths.length} newly-added files');
      expect(r.error, contains('shallow'));
      expect(r.error, contains('deepen'));
    } finally {
      try {
        host.deleteSync(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('T15c: a NON-ASCII path is reported as its real name', () async {
    // git's core.quotePath defaults to true, so a path with an accent in it
    // arrives C-quoted and full of octal escapes. Passed through verbatim it
    // reaches the prompt and every --files comparison as a string that
    // matches nothing on disk.
    const name = 'café-ü.txt';
    await h.repo.writeFile(name, 'accented\n');
    await h.repo.commitAll('add an accented path');
    final commit = (await h.repo.head())!;
    try {
      final raw = await h.repo
          .git(['diff-tree', '-r', '--raw', '--no-commit-id', commit]);
      expect((raw.stdout as String), contains(r'\303'),
          reason: 'guard: git must still be quoting this path, otherwise the '
              'test proves nothing');

      final s = await resolveOk(CommitTarget(commit));
      expect(s.paths, [name]);
      expect(s.paths.first, isNot(contains(r'\3')));
    } finally {
      await h.repo.gitOk(['reset', '--hard', 'HEAD~1']);
    }
  });

  // ── the prepared-diff variant ───────────────────────────────────

  test('T16: a prepared diff keeps the label it was given', () async {
    final s = await resolveOk(const PreparedDiffTarget(
      diffText: 'diff --git a/x.dart b/x.dart\n+++ b/x.dart\n',
      label: 'pull request #12',
      branchName: 'feature/thing',
      statusSummary: 'M\tx.dart',
    ));
    expect(s.label, 'pull request #12');
    expect(s.branchName, 'feature/thing',
        reason: 'the old override path hard-coded "(pr)" into every prompt');
    expect(s.paths, ['x.dart']);
  });

  test('T17: an empty prepared diff is refused', () async {
    final err = await resolveErr(
        const PreparedDiffTarget(diffText: '   \n', label: 'x'));
    expect(err, contains('empty'));
  });

  test('T18: the working tree is not this resolver\'s job', () async {
    final err = await resolveErr(const WorkingTreeTarget(
        includeStaged: true, includeUnstaged: true));
    expect(err, contains('review gather'));
  });

  // ── auditing code that exists ───────────────────────────────────

  group('region audit', () {
    test('R1: a region renders as a readable all-additions patch', () async {
      final s = await resolveOk(const RegionTarget(
        paths: ['a.txt', 'b.txt'],
        label: 'the txt files',
      ));

      expect(s.paths, containsAll(<String>['a.txt', 'b.txt']));
      expect(s.label, 'the txt files');

      // The transport has to be a patch a diff parser accepts, or every
      // producer downstream sees nothing.
      expect(s.diffText, contains('diff --git a/a.txt b/a.txt'));
      expect(s.diffText, contains('--- /dev/null'));
      expect(s.diffText, contains('+++ b/a.txt'));
      expect(s.diffText, contains('@@ -0,0 +1,'));
      // ...carrying the CURRENT content, not a historical one.
      expect(s.diffText, contains('+3'), reason: 'a.txt is "3" at HEAD');
    });

    test('R2: hunk headers state the real line count', () async {
      // A wrong count makes the patch unparseable partway through, which
      // would silently truncate what the auditor sees.
      await h.repo.writeFile('counted.txt', 'l1\nl2\nl3\nl4\nl5\n');
      await h.repo.commitAll('add a five-line file');
      try {
        final s = await resolveOk(
            const RegionTarget(paths: ['counted.txt'], label: 'counted'));
        expect(s.diffText, contains('@@ -0,0 +1,5 @@'));
        expect('+l1\n+l2\n+l3\n+l4\n+l5', isNotNull);
        for (final l in const ['+l1', '+l2', '+l3', '+l4', '+l5']) {
          expect(s.diffText, contains(l));
        }
      } finally {
        await h.repo.gitOk(['reset', '--hard', 'HEAD~1']);
      }
    });

    test('R3: the audit reads the OBJECT STORE, not the working tree',
        () async {
      // The fidelity guarantee. An audit of HEAD whose answer changed because
      // you had an unsaved edit open would be worthless — and reading from
      // disk is the obvious, wrong way to build this.
      final clean = await resolveOk(
          const RegionTarget(paths: ['a.txt'], label: 'a'));
      expect(clean.diffText, contains('+3'));

      await h.repo.writeFile('a.txt', 'UNCOMMITTED SCRIBBLE\n');
      try {
        final s = await resolveOk(
            const RegionTarget(paths: ['a.txt'], label: 'a'));
        expect(s.diffText, isNot(contains('UNCOMMITTED SCRIBBLE')),
            reason: 'the working tree leaked into an audit of HEAD');
        expect(s.diffText, contains('+3'));
        expect(s.diffText, clean.diffText);
      } finally {
        await h.repo.gitOk(['checkout', '--', 'a.txt']);
      }
    });

    test('R4: a region can be audited at any revision', () async {
      // a.txt is "2" at c1 and "3" at c3.
      final atC1 = await resolveOk(
          RegionTarget(paths: const ['a.txt'], label: 'a', revision: h.c1));
      expect(atC1.diffText, contains('+2'));
      expect(atC1.diffText, isNot(contains('+3')));
      expect(atC1.branchName, h.c1);
    });

    test('R5: binary and empty files are skipped, not rendered as garbage',
        () async {
      final bin =
          File('${h.repo.dir.path}${Platform.pathSeparator}blob.bin');
      await bin.writeAsBytes([0, 1, 2, 3, 0, 255]);
      await h.repo.writeFile('empty.txt', '');
      await h.repo.commitAll('binary and empty');
      try {
        final s = await resolveOk(const RegionTarget(
          paths: ['a.txt', 'blob.bin', 'empty.txt'],
          label: 'mixed',
        ));
        expect(s.paths, ['a.txt'],
            reason: 'only the file with readable text was covered, and the '
                'others are absent rather than counted');
        expect(s.diffText, isNot(contains('blob.bin')));
      } finally {
        await h.repo.gitOk(['reset', '--hard', 'HEAD~1']);
      }
    });

    test('R6: a region of only unreadable files is refused', () async {
      final bin =
          File('${h.repo.dir.path}${Platform.pathSeparator}only.bin');
      await bin.writeAsBytes([0, 1, 2, 3, 0, 255]);
      await h.repo.commitAll('binary only');
      try {
        final err = await resolveErr(
            const RegionTarget(paths: ['only.bin'], label: 'bin'));
        expect(err, contains('no readable text'));
      } finally {
        await h.repo.gitOk(['reset', '--hard', 'HEAD~1']);
      }
    });

    test('R7: paths absent at the revision are refused, not invented',
        () async {
      final err = await resolveErr(const RegionTarget(
          paths: ['does/not/exist.dart'], label: 'ghost'));
      expect(err, contains('exist'));
    });

    test('R8: an empty region is refused', () async {
      final err =
          await resolveErr(const RegionTarget(paths: [], label: 'nothing'));
      expect(err, contains('no files'));
    });

    test('R9: settled code is its own stance, not a change', () {
      // The fork that decides whether an audit hunts or merely comments.
      expect(
          const RegionTarget(paths: ['x'], label: 'x').stance,
          ReviewStance.settled);
      expect(const CommitTarget('HEAD').stance, isNot(ReviewStance.settled));
    });
  });

  // ── the raw-record grammar ──────────────────────────────────────

  group('raw records', () {
    // Paths and blob OIDs were once read by two functions walking this same
    // grammar independently — the shape where a rename's destination-wins
    // rule gets applied in one and forgotten in the other, and the two then
    // disagree about which file a size belongs to.
    test('W1: a modification yields both sides', () {
      final r = parseRawDiffRecords(
          ':100644 100644 aaa111 bbb222 M\tlib/thing.dart');
      expect(r, hasLength(1));
      expect(r.first.path, 'lib/thing.dart');
      expect(r.first.blobOids, ['aaa111', 'bbb222']);
    });

    test('W2: an addition and a deletion drop the all-zero side', () {
      final added = parseRawDiffRecords(
          ':000000 100644 0000000000 ccc333 A\tnew.dart');
      expect(added.first.blobOids, ['ccc333']);

      final deleted = parseRawDiffRecords(
          ':100644 000000 ddd444 0000000000 D\tgone.dart');
      expect(deleted.first.blobOids, ['ddd444']);
    });

    test('W3: a RENAME is about its destination', () {
      final r = parseRawDiffRecords(
          ':100644 100644 eee555 fff666 R100\told/place.dart\tnew/place.dart');
      expect(r.first.path, 'new/place.dart',
          reason: 'the review is about where the file IS, and the size that '
              'goes with it must agree');
      expect(r.first.blobOids, ['eee555', 'fff666']);
    });

    test('W4: a non-ASCII path is decoded, not left C-quoted', () {
      final r = parseRawDiffRecords(
          ':100644 100644 aaa bbb M\t"caf\\303\\251.dart"');
      expect(r.first.path, 'café.dart');
    });

    test('W5: repeated blobs are PRESERVED, because the patch prints each',
        () {
      // The admission declaration multiplies by occurrence; collapsing here
      // would under-reserve for every repository with copied files.
      final r = parseRawDiffRecords(
        ':100644 100644 same111 same222 M\ta.dart\n'
        ':100644 100644 same111 same222 M\tb.dart',
      );
      expect(r, hasLength(2));
      expect(blobOidsOf(r), ['same111', 'same222', 'same111', 'same222']);
    });

    test('W6: noise between records is ignored', () {
      final r = parseRawDiffRecords(
        'not a record\n'
        ':100644 100644 aaa bbb M\tkeep.dart\n'
        '\n'
        ':malformed\n',
      );
      expect([for (final x in r) x.path], ['keep.dart']);
    });
  });

  // ── spec parsing ────────────────────────────────────────────────

  test('T19: revision specs parse to the target they name', () {
    expect(parseReviewTargetSpec(commit: 'abc'), isA<CommitTarget>());

    final twoDot = parseReviewTargetSpec(range: 'a..b')! as RangeTarget;
    expect(twoDot.mergeBase, isFalse);
    expect(twoDot.base, 'a');
    expect(twoDot.tip, 'b');

    final threeDot = parseReviewTargetSpec(range: 'a...b')! as RangeTarget;
    expect(threeDot.mergeBase, isTrue,
        reason: 'three dots means "from the merge base"; conflating it with '
            'two reviews a different change set');
    expect(threeDot.base, 'a');
    expect(threeDot.tip, 'b');

    // A bare revision in the range slot is the commit it names.
    expect(parseReviewTargetSpec(range: 'HEAD'), isA<CommitTarget>());
    expect(parseReviewTargetSpec(), isNull);
    expect(parseReviewTargetSpec(commit: '  '), isNull);
  });

  // ── what tense the reviewer reads in ────────────────────────────

  test('T19b: every target knows whether its change has landed', () {
    // The prompt used to assert "you are reviewing a proposed commit
    // immediately before it is created" for ALL of these. For the middle two
    // that is false, and it steers the reviewer into arguing against work
    // that already shipped.
    expect(
        const WorkingTreeTarget(includeStaged: true, includeUnstaged: true)
            .stance,
        ReviewStance.pending);
    expect(const CommitTarget('HEAD').stance, ReviewStance.landed);
    expect(
        const RangeTarget(base: 'a', tip: 'b', mergeBase: false).stance,
        ReviewStance.landed);
    expect(
        const PreparedDiffTarget(diffText: 'x', label: 'PR #1').stance,
        ReviewStance.proposed,
        reason: 'a pull request is proposed, not landed — it is not in this '
            'history at all');
  });

  test('T19c: revisits count later commits per path, heaviest first', () {
    final touches = {
      'hot.dart': const [1, 2, 5, 8, 9],
      'cold.dart': const [1, 2],
      'never.dart': const [7],
    };
    final r = revisitsAfter(
      paths: const ['hot.dart', 'cold.dart', 'never.dart', 'absent.dart'],
      afterIndex: 4,
      perFileCommitIndices: touches,
    );
    expect(r.map((e) => e.key), ['hot.dart', 'never.dart'],
        reason: 'cold.dart was never touched after index 4 and absent.dart '
            'has no history — neither is evidence of anything');
    expect(r.first.value, 3);

    // Pending work has no "after", so there is nothing to report and no
    // temptation to invent some.
    expect(
      revisitsAfter(
          paths: touches.keys,
          afterIndex: null,
          perFileCommitIndices: touches),
      isEmpty,
    );
  });

  // ── anchoring on the engine's axis ──────────────────────────────

  group('axis anchoring', () {
    late LogosCommitAxis axis;

    setUpAll(() async {
      final stats = await collectLogosGitStats(h.repo.dir.path);
      expect(stats.ok, isTrue, reason: 'stats: ${stats.error}');
      axis = stats.data!.commitAxis;
    });

    test('T20: the axis indexes the commits the walk visited', () {
      expect(axis.isNotEmpty, isTrue);
      expect(axis.indexOf(h.c2), isNotNull);
      expect(axis.indexOf(h.c3), isNotNull);
      expect(axis.indexOf(h.c2)! < axis.indexOf(h.c3)!, isTrue,
          reason: 'index 0 is the OLDEST commit');
      expect(axis.hashes.length, axis.stepAt.length);
      expect(axis.hashes.length, axis.clockAt.length);
    });

    test('T21: a located commit anchors at its index', () async {
      final s = await resolveOk(CommitTarget(h.c2), axis: axis);
      expect(s.anchor, isA<CommitAnchor>());
      final a = s.anchor as CommitAnchor;
      expect(a.oid, h.c2);
      expect(a.index, axis.indexOf(h.c2));
      expect(s.isRetrospective, isTrue);
    });

    test('T22: a MERGE is off-axis for the reason that it is a merge',
        () async {
      // The stats walk runs --no-merges, so NO merge is ever on the axis —
      // including HEAD right after merging. Modelled as a null index this
      // would be indistinguishable from "ancient commit" and from "no engine".
      expect(axis.indexOf(h.m), isNull);

      final s = await resolveOk(CommitTarget(h.m), axis: axis);
      expect(s.anchor, isA<OffAxisAnchor>());
      final a = s.anchor as OffAxisAnchor;
      expect(a.reason, OffAxisReason.mergeCommit);
      expect(a.nearestIndex, axis.indexOf(h.c3),
          reason: 'evidence bisects at the first parent instead');
    });

    test('T23: no engine is its own reason, not a missing index', () async {
      final s = await resolveOk(CommitTarget(h.c2));
      expect(s.anchor, isA<OffAxisAnchor>());
      expect((s.anchor as OffAxisAnchor).reason, OffAxisReason.engineCold);
    });

    test('T24: a range anchors on the SET of commits it contains', () async {
      final s = await resolveOk(
        RangeTarget(base: h.c1, tip: h.c3, mergeBase: false),
        axis: axis,
      );
      expect(s.anchor, isA<RangeAnchor>());
      final a = s.anchor as RangeAnchor;
      expect(a.total, 2);
      expect(a.indices, {axis.indexOf(h.c2)!, axis.indexOf(h.c3)!});
      expect(a.oldest, axis.indexOf(h.c2));
    });

    test('T25: a range spanning a merge counts it but cannot locate it',
        () async {
      final s = await resolveOk(
        RangeTarget(base: h.c3, tip: h.m, mergeBase: false),
        axis: axis,
      );
      final a = s.anchor as RangeAnchor;
      expect(a.total, greaterThan(a.indices.length),
          reason: 'the merge is in the range but never on the axis, so the '
              'located set is necessarily smaller than the true count');
    });

    test('T26: future churn is counted by binary search, exclusive of the '
        'anchor itself', () {
      // The one thing hindsight is for: how often the reviewed file was
      // rewritten afterwards.
      expect(futureTouchCount(const [1, 3, 5, 7], 3), 2);
      expect(futureTouchCount(const [1, 3, 5, 7], 0), 4);
      expect(futureTouchCount(const [1, 3, 5, 7], 7), 0);
      expect(futureTouchCount(const [], 3), 0);
      expect(futureTouchCount(const [4], 3), 1,
          reason: 'strictly after, so an equal index does not count');
    });
  });
}
