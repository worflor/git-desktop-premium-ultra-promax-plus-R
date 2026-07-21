// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/backend/merge_session.dart';
import 'package:path/path.dart' as p;

import '../support/scratch_repo.dart';
import '../support/repo_topology.dart';
import '../support/git_faults.dart';

/// Choreography-crash sweep for the multi-step destructive mutations. Each
/// test builds a real repo NORMALLY, then wraps ONLY the operation under test
/// in [withGitFaults] so one interior git step "crashes" (nonzero exit). The
/// invariants asserted after the crash:
///   • the error surfaces as a GitResult.err / typed failure — NEVER a throw;
///   • the repo is left SANE — `git fsck --full` clean, no half-applied index,
///     no orphaned/registered worktree, no lost stash;
///   • idempotent choreography (exclude write) is not corrupted or duplicated.
///
/// The step is targeted by ARGV via [GitFaultScript.failWhile] rather than by a
/// raw 1-based call index: several of these operations route an early leg
/// through the memoized geometry probe ([revParseGeometryForTesting]'s cache),
/// so the absolute call index of "the mutating step" is not stable, but its
/// argv is. `times` is set generously so even a transient-retry path stays
/// failed. Non-matching calls delegate to real git, so setup-equivalent reads
/// inside the operation still work.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Every geometry memo is per-process; clear it between tests so a cached
  // git-common-dir from one temp repo can't leak into the next.
  tearDown(clearRepoGeometryCacheForTesting);

  GitFaultScript failStep(bool Function(List<String> args) match) =>
      GitFaultScript.failWhile(
        match,
        times: 8,
        result: () => gitFail(128, 'fatal: simulated crash at this step'),
      );

  // ── stashDropByHash: the `stash drop` step crashes ────────────────────────
  //
  // LAW: if the drop leg fails, stashDropByHash reports err and BOTH stash
  // entries survive — a crashed drop must never half-delete or lose a stash.
  test('stashDropByHash: a crash in `stash drop` loses no stash', () async {
    final r = await ScratchRepo.create(name: 'fault_stash_drop');
    addTearDown(r.dispose);
    await r.writeFile('f.txt', 'base\n');
    await r.commitAll('base');
    await r.writeFile('f.txt', 'alpha\n');
    await stashPush(r.dir.path, message: 'ALPHA', includeUntracked: true);
    final alphaHash = await stashHashAt(r.dir.path, 0);
    await r.writeFile('f.txt', 'beta\n');
    await stashPush(r.dir.path, message: 'BETA', includeUntracked: true);

    final res = await withGitFaults(
      failStep((a) => a.length >= 2 && a[0] == 'stash' && a[1] == 'drop'),
      () => stashDropByHash(r.dir.path, alphaHash!),
    );
    expect(res.ok, isFalse, reason: 'a crashed drop surfaces as err, not throw');

    // Both entries intact after the failed drop.
    final list = await listStashes(r.dir.path);
    expect(list.ok, isTrue);
    expect(list.data, hasLength(2),
        reason: 'no stash entry was lost by the crash');
    expect(list.data!.map((s) => s.hash), contains(alphaHash));
    await assertFsckClean(r, because: 'crashed stashDropByHash');
  });

  // ── addWorktree: `worktree add` crashes AFTER the exclude write ───────────
  //
  // LAW: the exclude-then-add choreography is crash-safe and idempotent. When
  // the add crashes, the operation errs, no worktree is registered, the
  // `.manifold/` exclude entry is present EXACTLY ONCE (not corrupted, not
  // duplicated), and a subsequent successful add reuses it without doubling.
  test('addWorktree: a crash in `worktree add` leaves no orphan, exclude sane',
      () async {
    final r = await ScratchRepo.create(name: 'fault_wt_add');
    addTearDown(r.dispose);
    await r.writeFile('f.txt', 'base\n');
    await r.commitAll('base');
    await r.gitOk(['branch', 'wt-branch']);
    final wtPath = p.join(r.dir.parent.path, 'faulted_wt');

    final res = await withGitFaults(
      failStep((a) => a.length >= 2 && a[0] == 'worktree' && a[1] == 'add'),
      () => addWorktree(r.dir.path, wtPath, 'wt-branch'),
    );
    expect(res.ok, isFalse, reason: 'crashed add surfaces as err, not throw');

    // No worktree directory, no administrative registration.
    expect(Directory(wtPath).existsSync(), isFalse);
    final listAfterCrash = await r.gitOk(['worktree', 'list']);
    expect(listAfterCrash, isNot(contains('faulted_wt')));

    // The exclude write DID happen (it precedes the add) and is well-formed.
    Future<int> manifoldExcludeLines() async {
      final f = File(p.join(r.dir.path, '.git', 'info', 'exclude'));
      if (!await f.exists()) return 0;
      final body = await f.readAsString();
      return body.split('\n').where((l) => l.trim() == '.manifold/').length;
    }

    expect(await manifoldExcludeLines(), 1,
        reason: '.manifold/ written once, uncorrupted, by the crashed op');
    // The exclude entry never dirties the working tree.
    expect(await r.isClean(), isTrue);
    await assertFsckClean(r, because: 'crashed addWorktree');

    // Recovery: a real add now succeeds and does NOT duplicate the exclude.
    final wtPath2 = p.join(r.dir.parent.path, 'recovered_wt');
    final ok = await addWorktree(r.dir.path, wtPath2, 'wt-branch');
    addTearDown(() async {
      await r.git(['worktree', 'remove', '--force', wtPath2]);
    });
    expect(ok.ok, isTrue, reason: ok.error ?? '');
    expect(await manifoldExcludeLines(), 1,
        reason: 'idempotent — the second add did not re-append .manifold/');
  });

  // ── removeWorktree: `worktree remove` crashes ─────────────────────────────
  //
  // LAW: a crashed remove errs cleanly and leaves the worktree fully intact
  // (directory present, still registered) — never a half-removed limbo.
  test('removeWorktree: a crash leaves the worktree intact', () async {
    final r = await ScratchRepo.create(name: 'fault_wt_remove');
    addTearDown(r.dispose);
    await r.writeFile('f.txt', 'base\n');
    await r.commitAll('base');
    await r.gitOk(['branch', 'wt-branch']);
    final wtPath = p.join(r.dir.parent.path, 'kept_wt');
    await r.gitOk(['worktree', 'add', wtPath, 'wt-branch']);
    addTearDown(() async {
      await r.git(['worktree', 'remove', '--force', wtPath]);
    });

    final res = await withGitFaults(
      failStep((a) => a.length >= 2 && a[0] == 'worktree' && a[1] == 'remove'),
      () => removeWorktree(r.dir.path, wtPath, force: true),
    );
    expect(res.ok, isFalse, reason: 'crashed remove surfaces as err');

    expect(Directory(wtPath).existsSync(), isTrue,
        reason: 'the worktree survives a crashed remove');
    final list = await r.gitOk(['worktree', 'list']);
    expect(list, contains('kept_wt'));
    await assertFsckClean(r, because: 'crashed removeWorktree');
  });

  // ── finishLocalPrRebase: the `merge --ff-only` step crashes ───────────────
  //
  // LAW: a crash in the base fast-forward yields a typed MergeFailed (never a
  // throw), and the base ref does NOT move — no partial advance.
  test('finishLocalPrRebase: a crashed ff-only is MergeFailed, base unmoved',
      () async {
    final r = await ScratchRepo.create(name: 'fault_finish_rebase');
    addTearDown(r.dispose);
    await r.writeFile('f.txt', 'base\n');
    final mainBefore = await r.commitAll('base');
    await r.gitOk(['checkout', '-b', 'feature']);
    await r.writeFile('feat.txt', 'payload\n');
    await r.commitAll('feature work');
    await r.gitOk(['checkout', 'main']);

    final res = await withGitFaults(
      failStep((a) => a.contains('merge') && a.contains('--ff-only')),
      () => finishLocalPrRebase(r.dir.path, 'feature', 'main'),
    );
    expect(res.outcome, isA<MergeFailed>(),
        reason: 'a crashed ff-only is a typed failure, not a throw');
    expect(await r.gitOk(['rev-parse', 'main']), mainBefore,
        reason: 'base must not partially advance on a crashed ff');
    await assertFsckClean(r, because: 'crashed finishLocalPrRebase');
  });

  // ── initRepository: `git init` crashes ────────────────────────────────────
  //
  // LAW: a crashed init errs cleanly and leaves no half-initialized `.git`.
  test('initRepository: a crashed init errs, no partial .git', () async {
    final sandbox = await Directory.systemTemp.createTemp('gdpu_fault_init_');
    addTearDown(() async {
      try {
        await sandbox.delete(recursive: true);
      } catch (_) {}
    });
    final target = p.join(sandbox.path, 'fresh');

    final res = await withGitFaults(
      failStep((a) => a.isNotEmpty && a.first == 'init'),
      () => initRepository(target),
    );
    expect(res.ok, isFalse, reason: 'crashed init surfaces as err, not throw');
    expect(Directory(p.join(target, '.git')).existsSync(), isFalse,
        reason: 'no half-initialized repository left behind');
  });
}
