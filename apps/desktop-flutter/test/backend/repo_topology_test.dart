// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Verifies every deterministic DAG-shape builder in
// test/support/repo_topology.dart actually builds the shape it claims —
// each test asserts the specific structural property (parent count, merge
// base count, ref kind, ...) that makes that shape interesting, then
// confirms the repo is still whole (`git fsck`).
//
// Also proves test/support/scratch_repo.dart's `ScratchRepo.create()` speedup
// (four `git config` subprocess calls collapsed into one `.git/config` file
// write) is behaviourally identical to the four separate calls it replaced.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/repo_topology.dart';
import '../support/scratch_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScratchRepo.create identity config (Task B behaviour parity)', () {
    Future<void> assertIdentity(ScratchRepo repo, {required bool autocrlf}) async {
      expect(await repo.gitOk(['config', '--get', 'user.name']),
          equals('Scratch Repo'));
      expect(await repo.gitOk(['config', '--get', 'user.email']),
          equals('scratch@example.invalid'));
      expect(await repo.gitOk(['config', '--get', 'commit.gpgsign']),
          equals('false'));
      expect(await repo.gitOk(['config', '--get', 'core.autocrlf']),
          equals(autocrlf ? 'true' : 'false'));
    }

    test('autocrlf: false — matches what 4 discrete `git config` calls '
        'would have produced', () async {
      final repo = await ScratchRepo.create(name: 'identity_false');
      addTearDown(repo.dispose);
      await assertIdentity(repo, autocrlf: false);
    });

    test('autocrlf: true — matches what 4 discrete `git config` calls '
        'would have produced', () async {
      final repo = await ScratchRepo.create(name: 'identity_true', autocrlf: true);
      addTearDown(repo.dispose);
      await assertIdentity(repo, autocrlf: true);
    });
  });

  group('buildDiamond', () {
    test('merge has 2 parents; mergeBase(b, c) == [a]', () async {
      final repo = await ScratchRepo.create(name: 'diamond');
      addTearDown(repo.dispose);

      final shape = await buildDiamond(repo);
      final parents = await parentsOf(repo, shape.merge);
      expect(parents, hasLength(2));
      expect(parents, containsAll([shape.b, shape.c]));

      final bases = await mergeBases(repo, shape.b, shape.c);
      expect(bases, equals([shape.a]));

      await assertFsckClean(repo, because: 'buildDiamond');
    });
  });

  group('buildCrissCross', () {
    test('mergeBases(leftMerge, rightMerge) returns exactly 2 bases',
        () async {
      final repo = await ScratchRepo.create(name: 'criss_cross');
      addTearDown(repo.dispose);

      final shape = await buildCrissCross(repo);
      final bases =
          await mergeBases(repo, shape.leftMerge, shape.rightMerge);
      expect(bases, hasLength(2),
          reason: 'expected an ambiguous (2-candidate) merge base; got '
              '$bases — the criss-cross construction collapsed to a '
              'single, unambiguous base');

      final leftParents = await parentsOf(repo, shape.leftMerge);
      final rightParents = await parentsOf(repo, shape.rightMerge);
      expect(leftParents, hasLength(2));
      expect(rightParents, hasLength(2));

      await assertFsckClean(repo, because: 'buildCrissCross');
    });
  });

  group('buildOctopus', () {
    test('octopus merge has exactly 3 parents', () async {
      final repo = await ScratchRepo.create(name: 'octopus');
      addTearDown(repo.dispose);

      final shape = await buildOctopus(repo);
      expect(shape.parents, hasLength(3));

      final parents = await parentsOf(repo, shape.octopus);
      expect(parents, hasLength(3));
      expect(parents.toSet(), equals(shape.parents.toSet()));

      await assertFsckClean(repo, because: 'buildOctopus');
    });
  });

  group('buildOrphanBranch', () {
    test('git merge-base main <orphan> fails — no common ancestor',
        () async {
      final repo = await ScratchRepo.create(name: 'orphan');
      addTearDown(repo.dispose);

      final shape = await buildOrphanBranch(repo);
      final result =
          await repo.git(['merge-base', 'main', shape.orphanHead]);
      expect(result.exitCode, isNot(0),
          reason: 'expected merge-base to fail (no common ancestor); got '
              'exit ${result.exitCode}, stdout: ${result.stdout}');

      // Both heads independently still resolve to real commits.
      expect(
          (await repo.git(['rev-parse', '--verify', shape.mainHead]))
              .exitCode,
          0);
      expect(
          (await repo.git(['rev-parse', '--verify', shape.orphanHead]))
              .exitCode,
          0);

      await assertFsckClean(repo, because: 'buildOrphanBranch');
    });
  });

  group('buildUnrelatedHistories', () {
    test('merge has 2 parents and exactly 2 root commits are reachable',
        () async {
      final repo = await ScratchRepo.create(name: 'unrelated');
      addTearDown(repo.dispose);

      final shape = await buildUnrelatedHistories(repo);
      final parents = await parentsOf(repo, shape.merge);
      expect(parents, hasLength(2));

      final roots = await repo
          .gitOk(['rev-list', '--max-parents=0', 'HEAD']);
      final rootLines =
          roots.split('\n').where((l) => l.trim().isNotEmpty).toList();
      expect(rootLines, hasLength(2),
          reason: 'expected exactly 2 root commits reachable from HEAD, '
              'got: $rootLines');

      await assertFsckClean(repo, because: 'buildUnrelatedHistories');
    });
  });

  group('buildDetachedHead', () {
    test('HEAD is detached; rev-parse HEAD still resolves', () async {
      final repo = await ScratchRepo.create(name: 'detached');
      addTearDown(repo.dispose);

      final shape = await buildDetachedHead(repo);

      final symbolic = await repo.git(['symbolic-ref', '-q', 'HEAD']);
      expect(symbolic.exitCode, isNot(0),
          reason: 'HEAD should be detached (no symbolic ref), got exit '
              '${symbolic.exitCode}: ${symbolic.stdout}');

      final resolved = await repo.gitOk(['rev-parse', 'HEAD']);
      expect(resolved, equals(shape.detachedAt));
      expect(resolved, isNot(equals(shape.branchTip)));

      await assertFsckClean(repo, because: 'buildDetachedHead');
    });
  });

  group('buildTags', () {
    test('annotated tag is a tag object; lightweight tag is a commit',
        () async {
      final repo = await ScratchRepo.create(name: 'tags');
      addTearDown(repo.dispose);

      final shape = await buildTags(repo);

      final annotatedType =
          await repo.gitOk(['cat-file', '-t', shape.annotated]);
      expect(annotatedType, equals('tag'));

      final lightweightType =
          await repo.gitOk(['cat-file', '-t', shape.lightweight]);
      expect(lightweightType, equals('commit'));

      await assertFsckClean(repo, because: 'buildTags');
    });
  });

  group('buildLinkedWorktree', () {
    test('git worktree list shows 2 entries; worktree HEAD differs from '
        'main', () async {
      final repo = await ScratchRepo.create(name: 'linked_worktree');
      addTearDown(repo.dispose);

      final shape = await buildLinkedWorktree(repo);
      addTearDown(() async {
        // Best-effort: `git worktree remove` deletes the directory itself
        // on success; the manual delete is only a backstop.
        await repo.git(['worktree', 'remove', '--force', shape.worktreePath]);
        try {
          await Directory(shape.worktreePath).delete(recursive: true);
        } catch (_) {
          // Already gone, or `remove` succeeded — not an error.
        }
      });

      final list = await repo.gitOk(['worktree', 'list', '--porcelain']);
      final worktreeBlocks =
          list.split('\n\n').where((b) => b.trim().isNotEmpty).toList();
      expect(worktreeBlocks, hasLength(2),
          reason: 'expected main + 1 linked worktree, got:\n$list');

      final mainHead = await repo.gitOk(['rev-parse', 'main']);
      final worktreeHead = await repo.git(
          ['-C', shape.worktreePath, 'rev-parse', 'HEAD']).then((r) {
        expect(r.exitCode, 0, reason: r.stderr.toString());
        return r.stdout.toString().trim();
      });
      expect(worktreeHead, isNot(equals(mainHead)));

      await assertFsckClean(repo, because: 'buildLinkedWorktree');
    });
  });

  group('buildSubmodule', () {
    test('.gitmodules is tracked; ls-files shows mode 160000', () async {
      final repo = await ScratchRepo.create(name: 'submodule_outer');
      addTearDown(repo.dispose);

      ({String subPath, ScratchRepo inner})? shape;
      try {
        shape = await buildSubmodule(repo);
      } on StateError catch (e) {
        // Windows + git submodule against a `file://` URL is a documented
        // sharp edge (see buildSubmodule's doc comment on
        // protocol.file.allow) — if the local git/OS combination still
        // refuses it even with the override, don't fail the whole suite;
        // surface it loudly instead so it's visible in output.
        // ignore: avoid_print
        print('[repo_topology_test] buildSubmodule failed on this platform: '
            '$e');
        rethrow;
      }
      addTearDown(shape.inner.dispose);

      final gitmodulesTracked =
          await repo.gitOk(['ls-files', '--', '.gitmodules']);
      expect(gitmodulesTracked, equals('.gitmodules'));
      expect(await File('${repo.dir.path}/.gitmodules').exists(), isTrue);

      final lsFiles = await repo.gitOk(['ls-files', '-s', '--', shape.subPath]);
      expect(lsFiles, startsWith('160000'),
          reason: 'expected a gitlink (mode 160000) for ${shape.subPath}, '
              'got: $lsFiles');

      await assertFsckClean(repo, because: 'buildSubmodule');
    });
  });

  group('buildRenameWithEdit', () {
    test('git diff --find-renames reports R<score> >= requested similarity',
        () async {
      final repo = await ScratchRepo.create(name: 'rename_edit');
      addTearDown(repo.dispose);

      const requested = 80;
      final shape =
          await buildRenameWithEdit(repo, similarityPercent: requested);

      final diff = await repo.gitOk([
        'diff',
        '--find-renames',
        '--name-status',
        'HEAD~1',
        'HEAD',
      ]);
      final renameLine = diff
          .split('\n')
          .firstWhere((l) => l.startsWith('R'), orElse: () => '');
      expect(renameLine, isNot(isEmpty),
          reason: 'git did not report a rename at all; full diff:\n$diff');

      final scoreMatch = RegExp(r'^R(\d+)').firstMatch(renameLine);
      expect(scoreMatch, isNotNull, reason: 'unparseable rename line: $renameLine');
      final score = int.parse(scoreMatch!.group(1)!);
      expect(score, greaterThanOrEqualTo(shape.similarity),
          reason: 'rename score $score fell below the requested '
              '${shape.similarity}% (full diff:\n$diff)');
      expect(renameLine, contains(shape.from));
      expect(renameLine, contains(shape.to));

      await assertFsckClean(repo, because: 'buildRenameWithEdit');
    });
  });

  group('buildStagedVsWorktreeSkew', () {
    test('git diff --cached and git diff are both non-empty and differ',
        () async {
      final repo = await ScratchRepo.create(name: 'staged_skew');
      addTearDown(repo.dispose);

      final shape = await buildStagedVsWorktreeSkew(repo);

      final cached = await repo.gitOk(['diff', '--cached']);
      final worktree = await repo.gitOk(['diff']);
      expect(cached, isNotEmpty);
      expect(worktree, isNotEmpty);
      expect(cached, isNot(equals(worktree)));
      expect(cached, contains(shape.staged.trim()));
      expect(worktree, contains(shape.worktree.trim()));

      await assertFsckClean(repo, because: 'buildStagedVsWorktreeSkew');
    });
  });

  group('buildHostileContentCommit', () {
    test('fsck clean; commit message roundtrips through git log -1 '
        '--format=%B (modulo git\'s own trailing-newline normalisation)',
        () async {
      final repo = await ScratchRepo.create(name: 'hostile_content');
      addTearDown(repo.dispose);

      final shape = await buildHostileContentCommit(repo);

      // Two independent normalisations stack here, checked empirically
      // against the installed git (2.52) with exactly this hostile message
      // (see the probe that produced these findings — reproduced in the
      // report, not committed):
      //
      //  1. `git commit -m` does NOT store the `-m` string byte-for-byte —
      //     it runs its default "strip" cleanup first. The ONE
      //     normalisation that actually fires on THIS message is
      //     CRLF -> LF: a `\r` counts as "trailing whitespace" (and is
      //     stripped) only when it directly precedes a `\n`; a lone `\r`
      //     NOT immediately followed by `\n` (this message's
      //     "lone CR\r here") is untouched because it isn't at the end of
      //     a line. Cleanup then ensures the STORED object ends in exactly
      //     one `\n` (confirmed directly via `git cat-file -p`, bypassing
      //     any log/show formatting). No other byte is altered — the
      //     control chars, the astral emoji, and the RTL marks all
      //     round-trip untouched.
      //  2. `git log --format=<x>` (no `--pretty=` prefix) is a synonym for
      //     `--pretty=tformat:<x>`, NOT `format:<x>` — and `tformat`
      //     unconditionally appends its own terminating `\n` after each
      //     commit's rendered output, on top of whatever `%B` itself
      //     produced. So the raw stdout of `git log -1 --format=%B` carries
      //     TWO trailing newlines here: the one already stored in the
      //     object (normalisation #1) plus `tformat`'s own terminator —
      //     confirmed by comparing byte-for-byte against `git cat-file -p`
      //     (single trailing `\n`) and against this same `git log` call
      //     (double).
      final gitStripCleanup = shape.message.replaceAll('\r\n', '\n');
      final storedMessage = gitStripCleanup.endsWith('\n')
          ? gitStripCleanup
          : '$gitStripCleanup\n';

      final logResult =
          await repo.git(['log', '-1', '--format=%B', shape.sha]);
      expect(logResult.exitCode, 0, reason: logResult.stderr.toString());
      expect(logResult.stdout.toString(), equals('$storedMessage\n'),
          reason: '`git log --format=%B` is tformat, not format — it adds '
              'its own trailing newline on top of the stored message');

      // The object's stored bytes, independent of any log/show formatting
      // quirk: `git cat-file -p` prints the raw commit object, so its
      // message tail must be exactly `storedMessage` (one trailing `\n`,
      // no tformat terminator).
      final catFile =
          await repo.gitOk(['cat-file', '-p', shape.sha]);
      expect(catFile, endsWith(storedMessage.trimRight()));

      await assertFsckClean(repo, because: 'buildHostileContentCommit');
    });
  });
}
