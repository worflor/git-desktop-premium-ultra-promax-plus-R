// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/merge_session.dart';
import 'package:path/path.dart' as p;

import '../support/scratch_repo.dart';
import '../support/repo_topology.dart';
import '../support/git_faults.dart';

/// Behavioural witnesses for the irreversible / data-destroying git mutations
/// that had ZERO coverage: discardFile, the stash family, pushRemote (incl.
/// --force-with-lease), the worktree family, and the cheap single-call
/// mutations (createBranch / renameBranch / tags / cherry-pick / revert /
/// finishLocalPrRebase / init / clone).
///
/// Every assertion is against REAL git state (through [ScratchRepo.git] or a
/// manual temp harness), never a reimplementation. LAW-style comments pin the
/// non-obvious invariants (e.g. "a lease push must NOT downgrade to a naked
/// force").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── discardFile ─────────────────────────────────────────────────────────
  //
  // discardFile is DESTRUCTIVE by design (deletes untracked files, unstages +
  // deletes a staged addition, reverts a tracked edit). Its whole contract is
  // "destroy exactly the named file and nothing else". These pin that it
  // targets the right path AND leaves siblings byte-identical — including for
  // adversarial paths (spaces, non-ASCII, and a name that looks like a CLI
  // flag, which only survives because every git leg passes `--`).

  group('discardFile', () {
    // A file the user never staged: pure filesystem delete, no git call.
    test('untracked → deletes the file, sibling untouched', () async {
      final r = await ScratchRepo.create(name: 'discard_untracked');
      addTearDown(r.dispose);
      await r.writeFile('keep.txt', 'committed\n');
      await r.commitAll('seed');
      await r.writeFile('scratch.txt', 'junk\n');

      final res = await discardFile(r.dir.path,
          const RepositoryStatusFile(path: 'scratch.txt', staged: '?', unstaged: '?'));
      expect(res.ok, isTrue, reason: res.error ?? '');

      expect(File(p.join(r.dir.path, 'scratch.txt')).existsSync(), isFalse);
      // The committed sibling is byte-for-byte what it was.
      expect(await File(p.join(r.dir.path, 'keep.txt')).readAsString(),
          'committed\n');
      await assertFsckClean(r, because: 'discard untracked');
    });

    // A brand-new file the user `git add`ed: must be `rm --cached` (leaving
    // git with no record of it) AND removed from disk.
    test('staged addition → rm --cached + delete, sibling stays staged',
        () async {
      final r = await ScratchRepo.create(name: 'discard_staged_add');
      addTearDown(r.dispose);
      await r.writeFile('keep.txt', 'v1\n');
      await r.commitAll('seed');

      // Two brand-new staged additions; discard exactly one.
      await r.writeFile('added.txt', 'new content\n');
      await r.writeFile('sibling-add.txt', 'sibling\n');
      await r.stage(['added.txt', 'sibling-add.txt']);

      final res = await discardFile(r.dir.path,
          const RepositoryStatusFile(path: 'added.txt', staged: 'A', unstaged: ''));
      expect(res.ok, isTrue, reason: res.error ?? '');

      // File gone from disk AND from the index (no phantom staged addition).
      expect(File(p.join(r.dir.path, 'added.txt')).existsSync(), isFalse);
      final staged = await r.gitOk(['diff', '--cached', '--name-only']);
      expect(staged.split('\n'), isNot(contains('added.txt')));
      // The other staged addition survives, still staged, still on disk.
      expect(staged.split('\n'), contains('sibling-add.txt'));
      expect(await File(p.join(r.dir.path, 'sibling-add.txt')).readAsString(),
          'sibling\n');
      await assertFsckClean(r, because: 'discard staged addition');
    });

    // A tracked file the user edited: revert to HEAD, siblings untouched.
    test('tracked modification → checkout HEAD restores, sibling byte-identical',
        () async {
      final r = await ScratchRepo.create(name: 'discard_tracked_mod');
      addTearDown(r.dispose);
      await r.writeFile('tracked.txt', 'original\n');
      await r.writeFile('sibling.txt', 'sibling original\n');
      await r.commitAll('seed');

      // Edit BOTH; discard only tracked.txt.
      await r.writeFile('tracked.txt', 'edited\n');
      await r.writeFile('sibling.txt', 'sibling edited\n');

      final res = await discardFile(r.dir.path,
          const RepositoryStatusFile(path: 'tracked.txt', staged: '', unstaged: 'M'));
      expect(res.ok, isTrue, reason: res.error ?? '');

      // tracked.txt is back to HEAD; the sibling edit is left exactly alone.
      expect(await File(p.join(r.dir.path, 'tracked.txt')).readAsString(),
          'original\n');
      expect(await File(p.join(r.dir.path, 'sibling.txt')).readAsString(),
          'sibling edited\n',
          reason: 'discard must not revert an unrelated sibling');
      await assertFsckClean(r, because: 'discard tracked modification');
    });

    // LAW: a path that begins with `-`, contains spaces, or non-ASCII must be
    // discarded correctly — never mis-parsed as a flag, never mangled. All
    // three git legs pass `--`, so a `-foo.txt` staged addition is unstaged +
    // deleted rather than swallowed as an option.
    test('adversarial paths (spaces, non-ASCII, flag-like) discard cleanly',
        () async {
      for (final hostile in const ['a file.txt', 'café ☃.txt', '-foo.txt']) {
        final r = await ScratchRepo.create(name: 'discard_hostile');
        addTearDown(r.dispose);
        await r.writeFile('anchor.txt', 'anchor\n');
        await r.commitAll('seed');

        // Staged-addition form exercises the `rm --cached -- <path>` leg,
        // which is the one that would break on a flag-like name without `--`.
        await r.writeFile(hostile, 'hostile body\n');
        await r.stage([hostile]);
        final res = await discardFile(
            r.dir.path,
            RepositoryStatusFile(path: hostile, staged: 'A', unstaged: ''));
        expect(res.ok, isTrue,
            reason: 'discard failed for ${jsonEncode(hostile)}: ${res.error}');
        expect(File(p.join(r.dir.path, hostile)).existsSync(), isFalse,
            reason: 'file ${jsonEncode(hostile)} not deleted');
        final staged = await r.gitOk(['diff', '--cached', '--name-only']);
        expect(staged.contains('hostile') || staged.trim().isEmpty, isTrue);
        // The committed anchor is untouched.
        expect(await File(p.join(r.dir.path, 'anchor.txt')).readAsString(),
            'anchor\n');
        await assertFsckClean(r, because: 'discard hostile ${jsonEncode(hostile)}');
      }
    });
  });

  // ── stash family ──────────────────────────────────────────────────────────

  group('stash', () {
    test('push / list / apply / pop round-trip restores the working tree',
        () async {
      final r = await ScratchRepo.create(name: 'stash_roundtrip');
      addTearDown(r.dispose);
      await r.writeFile('f.txt', 'base\n');
      await r.commitAll('base');

      // push reverts the working tree to HEAD and records the entry.
      await r.writeFile('f.txt', 'dirty edit\n');
      final push = await stashPush(r.dir.path,
          message: 'wip', includeUntracked: true);
      expect(push.ok, isTrue, reason: push.error ?? '');
      expect(await File(p.join(r.dir.path, 'f.txt')).readAsString(), 'base\n');
      final list = await listStashes(r.dir.path);
      expect(list.ok, isTrue);
      expect(list.data, hasLength(1));
      expect(list.data!.single.message, contains('wip'));

      // pop restores the edit AND drops the entry.
      final popped = await stashPop(r.dir.path, index: 0);
      expect(popped.ok, isTrue, reason: popped.error ?? '');
      expect(await File(p.join(r.dir.path, 'f.txt')).readAsString(),
          'dirty edit\n');
      expect((await listStashes(r.dir.path)).data, isEmpty);

      // A second round exercises apply (keeps the entry) + stashDrop by index.
      // apply is asserted on a CLEAN tree so it never double-applies.
      await r.gitOk(['checkout', '--', 'f.txt']);
      await r.writeFile('f.txt', 'second edit\n');
      final push2 = await stashPush(r.dir.path,
          message: 'wip2', includeUntracked: true);
      expect(push2.ok, isTrue, reason: push2.error ?? '');
      expect(await File(p.join(r.dir.path, 'f.txt')).readAsString(), 'base\n');

      final applied = await stashApply(r.dir.path, index: 0);
      expect(applied.ok, isTrue, reason: applied.error ?? '');
      expect(await File(p.join(r.dir.path, 'f.txt')).readAsString(),
          'second edit\n');
      expect((await listStashes(r.dir.path)).data, hasLength(1),
          reason: 'apply must NOT drop the entry');

      // stashDrop removes the entry without touching the working tree.
      final dropped = await stashDrop(r.dir.path, index: 0);
      expect(dropped.ok, isTrue, reason: dropped.error ?? '');
      expect((await listStashes(r.dir.path)).data, isEmpty);
      expect(await File(p.join(r.dir.path, 'f.txt')).readAsString(),
          'second edit\n', reason: 'stashDrop leaves the working tree alone');
    });

    // LAW: a conflicted `stash pop` must surface as a clean error AND keep the
    // stash entry — silently losing the stash on conflict is the incident this
    // guards ("I popped and my work vanished").
    test('pop-with-conflict returns err and does NOT lose the stash', () async {
      final r = await ScratchRepo.create(name: 'stash_pop_conflict');
      addTearDown(r.dispose);
      await r.writeFile('f.txt', 'l1\nl2\nl3\n');
      await r.commitAll('base');

      // Stash a change to line 2, then commit a DIFFERENT change to line 2, so
      // popping the stash conflicts.
      await r.writeFile('f.txt', 'l1\nSTASH2\nl3\n');
      await stashPush(r.dir.path, message: 'conflicting', includeUntracked: true);
      await r.writeFile('f.txt', 'l1\nHEAD2\nl3\n');
      await r.commitAll('head change on the same line');

      final popped = await stashPop(r.dir.path, index: 0);
      expect(popped.ok, isFalse, reason: 'a conflicted pop is an error');

      final list = await listStashes(r.dir.path);
      expect(list.ok, isTrue);
      expect(list.data, hasLength(1),
          reason: 'the stash entry survives a conflicted pop');
      expect(list.data!.single.message, contains('conflicting'));
    });

    // LAW: stashDropByHash resolves list→index→drop, so it drops the entry it
    // was armed on even after the list shifts underneath it (a positional drop
    // would delete the wrong stash).
    test('stashDropByHash drops the armed entry after the list shifts',
        () async {
      final r = await ScratchRepo.create(name: 'stash_drop_by_hash');
      addTearDown(r.dispose);
      await r.writeFile('f.txt', 'base\n');
      await r.commitAll('base');

      // Push ALPHA (index 0), pin its hash, then push BETA so ALPHA slides to 1.
      await r.writeFile('f.txt', 'alpha\n');
      await stashPush(r.dir.path, message: 'ALPHA', includeUntracked: true);
      final alphaHash = await stashHashAt(r.dir.path, 0);
      expect(alphaHash, isNotNull);

      await r.writeFile('f.txt', 'beta\n');
      await stashPush(r.dir.path, message: 'BETA', includeUntracked: true);

      final drop = await stashDropByHash(r.dir.path, alphaHash!);
      expect(drop.ok, isTrue, reason: drop.error ?? '');

      final list = await listStashes(r.dir.path);
      expect(list.data, hasLength(1));
      expect(list.data!.single.message, contains('BETA'),
          reason: 'a positional stash@{0} drop would have killed BETA');
      expect(list.data!.map((s) => s.hash), isNot(contains(alphaHash)));
    });

    test('stashDropByHash is a no-op success when the entry is already gone',
        () async {
      final r = await ScratchRepo.create(name: 'stash_drop_gone');
      addTearDown(r.dispose);
      await r.writeFile('f.txt', 'base\n');
      await r.commitAll('base');
      await r.writeFile('f.txt', 'edit\n');
      await stashPush(r.dir.path, message: 'once', includeUntracked: true);
      final hash = await stashHashAt(r.dir.path, 0);
      await r.gitOk(['stash', 'drop', 'stash@{0}']);

      final drop = await stashDropByHash(r.dir.path, hash!);
      expect(drop.ok, isTrue, reason: 'intent (entry absent) already holds');
    });
  });

  // ── pushRemote (local bare remote, no network) ────────────────────────────

  group('pushRemote', () {
    // Manual multi-repo harness: a bare "remote", a "work" clone, and (for the
    // lease test) a second clone that moves the remote underneath work. Raw
    // Process.run for setup mirrors merge_session_test's house style; the call
    // UNDER TEST is always the real pushRemote.
    late Directory sandbox;

    Future<ProcessResult> rawGit(String at, List<String> args) => Process.run(
          'git',
          args,
          workingDirectory: at,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );

    Future<void> config(String at) async {
      await rawGit(at, ['config', 'user.email', 'a@b.c']);
      await rawGit(at, ['config', 'user.name', 'test']);
      await rawGit(at, ['config', 'commit.gpgsign', 'false']);
      await rawGit(at, ['config', 'core.autocrlf', 'false']);
    }

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('gdpu_push_');
    });
    tearDown(() async {
      try {
        await sandbox.delete(recursive: true);
      } catch (_) {}
    });

    Future<String> makeWorkWithRemote() async {
      final bare = p.join(sandbox.path, 'bare.git');
      final work = p.join(sandbox.path, 'work');
      await rawGit(sandbox.path, ['init', '-q', '--bare', bare]);
      await rawGit(bare, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
      await Directory(work).create();
      await rawGit(work, ['init', '-q', '-b', 'main']);
      await config(work);
      await File(p.join(work, 'f.txt')).writeAsString('l1\n');
      await rawGit(work, ['add', '-A']);
      await rawGit(work, ['commit', '-qm', 'base']);
      await rawGit(work, ['remote', 'add', 'origin', bare]);
      return work;
    }

    test('plain push updates the bare remote', () async {
      final work = await makeWorkWithRemote();
      final res = await pushRemote(work, setUpstream: true, branch: 'main');
      expect(res.ok, isTrue, reason: res.error ?? '');
      final bare = p.join(sandbox.path, 'bare.git');
      final remoteTip =
          (await rawGit(bare, ['rev-parse', 'main'])).stdout.toString().trim();
      final localTip =
          (await rawGit(work, ['rev-parse', 'HEAD'])).stdout.toString().trim();
      expect(remoteTip, localTip);
    });

    // LAW: --force-with-lease must NEVER silently degrade to a naked --force.
    // The proof is behavioural: when the remote moved since work last fetched,
    // a lease push must be REJECTED (stale info) and the remote tip must be
    // exactly what the other writer left — a naked --force would have clobbered
    // it. This is the corruption class the flag exists to prevent.
    test('--force-with-lease is rejected when the remote moved underneath',
        () async {
      final work = await makeWorkWithRemote();
      final bare = p.join(sandbox.path, 'bare.git');
      await pushRemote(work, setUpstream: true, branch: 'main');

      // A second clone advances the remote; work never fetches, so its
      // origin/main is stale.
      final other = p.join(sandbox.path, 'other');
      await rawGit(sandbox.path, ['clone', '-q', bare, other]);
      await config(other);
      await File(p.join(other, 'f.txt')).writeAsString('l1\nOTHER\n');
      await rawGit(other, ['commit', '-qam', 'other advance']);
      await rawGit(other, ['push', '-q', 'origin', 'main']);
      final movedTip =
          (await rawGit(bare, ['rev-parse', 'main'])).stdout.toString().trim();

      // work makes its own (non-fast-forward) commit and force-with-lease pushes.
      await File(p.join(work, 'f.txt')).writeAsString('l1\nWORK\n');
      await rawGit(work, ['commit', '-qam', 'work advance']);

      final res = await pushRemote(work,
          branch: 'main', forceWithLease: true);
      expect(res.ok, isFalse,
          reason: 'a stale lease MUST fail, not overwrite');
      expect(res.error, contains('stale'));
      // The other writer\'s commit is intact on the remote.
      final afterTip =
          (await rawGit(bare, ['rev-parse', 'main'])).stdout.toString().trim();
      expect(afterTip, movedTip,
          reason: 'lease protected the moved remote from a clobber');
    });

    // Argv-shape guards: prove the exact flags reach git\'s argv via the spawn
    // recorder, independent of any remote. This catches "lease downgraded to
    // force" (or dropped entirely) at the wire level.
    test('argv carries the intended flags in canonical order', () async {
      final work = await makeWorkWithRemote();

      Future<List<String>> argvFor(Future<GitResult<SyncData>> Function() call) async {
        final script = GitFaultScript.always((_) => gitOk());
        List<String>? pushArgs;
        await withGitFaults(script, () async {
          await call();
          pushArgs = script.invocations
              .map((i) => i.args)
              .firstWhere((a) => a.isNotEmpty && a.first == 'push');
        });
        return pushArgs!;
      }

      expect(
          await argvFor(
              () => pushRemote(work, branch: 'main', forceWithLease: true)),
          ['push', '--force-with-lease', 'origin', 'main']);
      expect(
          await argvFor(() => pushRemote(work, branch: 'main', setUpstream: true)),
          ['push', '--set-upstream', 'origin', 'main']);
      // Both flags together: lease precedes the --set-upstream refspec.
      expect(
          await argvFor(() => pushRemote(work,
              branch: 'main', setUpstream: true, forceWithLease: true)),
          ['push', '--force-with-lease', '--set-upstream', 'origin', 'main']);
    });
  });

  // ── worktree family ───────────────────────────────────────────────────────

  group('worktree', () {
    test('addWorktree checks the branch out and excludes .manifold/', () async {
      final r = await ScratchRepo.create(name: 'wt_add');
      addTearDown(r.dispose);
      await r.writeFile('f.txt', 'base\n');
      await r.commitAll('base');
      await r.gitOk(['branch', 'wt-branch']);

      final wtPath = p.join(r.dir.parent.path, 'linked_wt');
      final res = await addWorktree(r.dir.path, wtPath, 'wt-branch');
      addTearDown(() async {
        await r.git(['worktree', 'remove', '--force', wtPath]);
      });
      expect(res.ok, isTrue, reason: res.error ?? '');
      expect(Directory(wtPath).existsSync(), isTrue);
      // The exclude choreography ran exactly once.
      final excludeFile =
          File(p.join(r.dir.path, '.git', 'info', 'exclude'));
      final excludeBody = await excludeFile.readAsString();
      expect('\n$excludeBody'.split('\n').where((l) => l.trim() == '.manifold/'),
          hasLength(1),
          reason: '.manifold/ present exactly once, never duplicated');
      await assertFsckClean(r, because: 'addWorktree');
    });

    // LAW: `git worktree remove` refuses a dirty worktree unless force; force
    // discards the dirt. This is a destroy-data path, so the gate matters.
    test('removeWorktree refuses a dirty worktree; force discards it', () async {
      final r = await ScratchRepo.create(name: 'wt_remove');
      addTearDown(r.dispose);
      await r.writeFile('f.txt', 'base\n');
      await r.commitAll('base');
      await r.gitOk(['branch', 'wt-branch']);
      final wtPath = p.join(r.dir.parent.path, 'dirty_wt');
      await r.gitOk(['worktree', 'add', wtPath, 'wt-branch']);
      // Dirty it with an uncommitted edit.
      await File(p.join(wtPath, 'f.txt')).writeAsString('dirty\n');

      final refused = await removeWorktree(r.dir.path, wtPath);
      expect(refused.ok, isFalse,
          reason: 'a dirty worktree must not be silently discarded');
      expect(Directory(wtPath).existsSync(), isTrue);

      final forced = await removeWorktree(r.dir.path, wtPath, force: true);
      expect(forced.ok, isTrue, reason: forced.error ?? '');
      expect(Directory(wtPath).existsSync(), isFalse);
      await assertFsckClean(r, because: 'removeWorktree force');
    });

    test('pruneWorktrees clears a stale registration after a manual delete',
        () async {
      final r = await ScratchRepo.create(name: 'wt_prune');
      addTearDown(r.dispose);
      await r.writeFile('f.txt', 'base\n');
      await r.commitAll('base');
      await r.gitOk(['branch', 'wt-branch']);
      final wtPath = p.join(r.dir.parent.path, 'prunable_wt');
      await r.gitOk(['worktree', 'add', wtPath, 'wt-branch']);
      // Rip the directory out from under git (the "moved/deleted a worktree
      // in Finder" case), leaving a stale administrative entry.
      await Directory(wtPath).delete(recursive: true);

      final pruned = await pruneWorktrees(r.dir.path);
      expect(pruned.ok, isTrue, reason: pruned.error ?? '');
      final list = await r.gitOk(['worktree', 'list']);
      expect(list, isNot(contains('prunable_wt')));
    });
  });

  // ── cheap single-call mutations ───────────────────────────────────────────

  group('branch / tag / cherry-pick / revert', () {
    test('createBranch lands on HEAD and switches to it', () async {
      final r = await ScratchRepo.create(name: 'create_branch');
      addTearDown(r.dispose);
      await r.writeFile('f.txt', 'base\n');
      final head = await r.commitAll('base');

      final res = await createBranch(r.dir.path, 'feature');
      expect(res.ok, isTrue, reason: res.error ?? '');
      expect(await r.currentBranch(), 'feature');
      expect(await r.gitOk(['rev-parse', 'feature']), head);
    });

    // LAW: a non-force rename onto an existing branch must fail (never clobber
    // the collision target); force (-M) replaces it.
    test('renameBranch refuses a collision unless forced', () async {
      final r = await ScratchRepo.create(name: 'rename_branch');
      addTearDown(r.dispose);
      await r.writeFile('f.txt', 'base\n');
      await r.commitAll('base');
      await r.gitOk(['branch', 'src']);
      await r.gitOk(['branch', 'dst']);

      final collide = await renameBranch(r.dir.path, 'src', 'dst');
      expect(collide.ok, isFalse, reason: 'dst already exists');
      // Both refs survive the refused rename.
      expect(await refTip(r.dir.path, 'refs/heads/src'), isNotNull);
      expect(await refTip(r.dir.path, 'refs/heads/dst'), isNotNull);

      final forced = await renameBranch(r.dir.path, 'src', 'dst', force: true);
      expect(forced.ok, isTrue, reason: forced.error ?? '');
      expect(await refTip(r.dir.path, 'refs/heads/src'), isNull);
      expect(await refTip(r.dir.path, 'refs/heads/dst'), isNotNull);
    });

    // LAW: createTag lands the tag on the intended target; re-tagging the same
    // name at a different target is refused (git\'s "tag already exists" guard),
    // so an existing tag is never silently re-pointed.
    test('createTag lands on target; deleteTag removes; retag is refused',
        () async {
      final r = await ScratchRepo.create(name: 'create_tag');
      addTearDown(r.dispose);
      await r.writeFile('f.txt', 'v1\n');
      final first = await r.commitAll('first');
      await r.writeFile('f.txt', 'v2\n');
      final second = await r.commitAll('second');

      // Annotated tag on the FIRST commit.
      final made = await createTag(r.dir.path, 'v1', first, message: 'release 1');
      expect(made.ok, isTrue, reason: made.error ?? '');
      expect(await r.gitOk(['rev-parse', 'v1^{commit}']), first);
      expect(await r.gitOk(['cat-file', '-t', 'v1']), 'tag',
          reason: 'annotated tag points at a tag object');

      // Re-tagging v1 at `second` must be refused; v1 stays on `first`.
      final retag = await createTag(r.dir.path, 'v1', second);
      expect(retag.ok, isFalse, reason: 'existing tag must not be re-pointed');
      expect(await r.gitOk(['rev-parse', 'v1^{commit}']), first);

      final del = await deleteTag(r.dir.path, 'v1');
      expect(del.ok, isTrue, reason: del.error ?? '');
      expect(await refTip(r.dir.path, 'refs/tags/v1'), isNull);
    });

    test('cherryPickCommit lands a disjoint commit onto HEAD', () async {
      final r = await ScratchRepo.create(name: 'cherry_pick');
      addTearDown(r.dispose);
      await r.writeFile('base.txt', 'base\n');
      await r.commitAll('base');
      await r.gitOk(['checkout', '-b', 'side']);
      await r.writeFile('side.txt', 'side payload\n');
      final sideTip = await r.commitAll('side work');
      await r.gitOk(['checkout', 'main']);
      await r.writeFile('main.txt', 'main advance\n');
      await r.commitAll('main advance');

      final res = await cherryPickCommit(r.dir.path, sideTip);
      expect(res.ok, isTrue, reason: res.error ?? '');
      // The cherry-picked file is present, on a NEW commit (not sideTip).
      expect(File(p.join(r.dir.path, 'side.txt')).existsSync(), isTrue);
      expect(await r.head(), isNot(sideTip));
      expect(await r.gitOk(['log', '-1', '--format=%s']), 'side work');
      await assertFsckClean(r, because: 'cherry-pick');
    });

    test('revertCommit adds an inverse commit', () async {
      final r = await ScratchRepo.create(name: 'revert');
      addTearDown(r.dispose);
      await r.writeFile('f.txt', 'original\n');
      await r.commitAll('base');
      await r.writeFile('f.txt', 'changed\n');
      final target = await r.commitAll('the change to undo');

      final res = await revertCommit(r.dir.path, target);
      expect(res.ok, isTrue, reason: res.error ?? '');
      // The revert commit restored the file and is a NEW commit on top.
      expect(await File(p.join(r.dir.path, 'f.txt')).readAsString(),
          'original\n');
      expect(await r.head(), isNot(target));
      expect(await r.gitOk(['log', '-1', '--format=%s']),
          startsWith('Revert'));
      await assertFsckClean(r, because: 'revert');
    });
  });

  // ── finishLocalPrRebase ───────────────────────────────────────────────────

  group('finishLocalPrRebase', () {
    test('fast-forwards the base worktree to the rebased head', () async {
      final r = await ScratchRepo.create(name: 'finish_rebase_ok');
      addTearDown(r.dispose);
      // main is the base (held by the main worktree). feature is one ahead —
      // the post-rebase shape, ready to fast-forward.
      await r.writeFile('f.txt', 'base\n');
      await r.commitAll('base');
      await r.gitOk(['checkout', '-b', 'feature']);
      await r.writeFile('feat.txt', 'feature payload\n');
      final featTip = await r.commitAll('feature work');
      await r.gitOk(['checkout', 'main']);

      final res = await finishLocalPrRebase(r.dir.path, 'feature', 'main');
      expect(res.outcome, isA<MergeClean>(), reason: 'base ff-only succeeds');
      // base (main) advanced to feature\'s tip; nothing else moved.
      expect(await r.gitOk(['rev-parse', 'main']), featTip);
      await assertFsckClean(r, because: 'finishLocalPrRebase');
    });

    test('base checked out nowhere yields MergeNeedsCheckout, moves nothing',
        () async {
      final r = await ScratchRepo.create(name: 'finish_rebase_needs_co');
      addTearDown(r.dispose);
      await r.writeFile('f.txt', 'base\n');
      await r.commitAll('base');
      // ghost-base exists but is checked out in no worktree.
      await r.gitOk(['branch', 'ghost-base']);
      await r.gitOk(['checkout', '-b', 'feature']);
      await r.writeFile('feat.txt', 'payload\n');
      await r.commitAll('feature work');
      await r.gitOk(['checkout', 'main']);
      final ghostBefore = await r.gitOk(['rev-parse', 'ghost-base']);

      final res =
          await finishLocalPrRebase(r.dir.path, 'feature', 'ghost-base');
      expect(res.outcome, isA<MergeNeedsCheckout>());
      expect(await r.gitOk(['rev-parse', 'ghost-base']), ghostBefore,
          reason: 'a refused finish must not move the base');
    });
  });

  // ── init / clone (single-repo / local source, no network) ─────────────────

  group('init / clone', () {
    test('initRepository creates a real git repository', () async {
      final sandbox = await Directory.systemTemp.createTemp('gdpu_init_');
      addTearDown(() async {
        try {
          await sandbox.delete(recursive: true);
        } catch (_) {}
      });
      final target = p.join(sandbox.path, 'fresh');

      final res = await initRepository(target);
      expect(res.ok, isTrue, reason: res.error ?? '');
      expect(Directory(p.join(target, '.git')).existsSync(), isTrue);
      final inside = await Process.run('git', ['rev-parse', '--is-inside-work-tree'],
          workingDirectory: target, stdoutEncoding: utf8);
      expect((inside.stdout as String).trim(), 'true');
    });

    test('cloneRepository copies a local source repo (no network)', () async {
      final src = await ScratchRepo.create(name: 'clone_src');
      addTearDown(src.dispose);
      await src.writeFile('f.txt', 'cloned content\n');
      final srcHead = await src.commitAll('seed');

      final sandbox = await Directory.systemTemp.createTemp('gdpu_clone_');
      addTearDown(() async {
        try {
          await sandbox.delete(recursive: true);
        } catch (_) {}
      });
      final dst = p.join(sandbox.path, 'dst');

      final res = await cloneRepository(src.dir.path, dst);
      expect(res.ok, isTrue, reason: res.error ?? '');
      final dstHead = (await Process.run('git', ['rev-parse', 'HEAD'],
              workingDirectory: dst, stdoutEncoding: utf8))
          .stdout
          .toString()
          .trim();
      expect(dstHead, srcHead);
      expect(File(p.join(dst, 'f.txt')).existsSync(), isTrue);
    });
  });
}
