// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Deterministic subprocess-spawn budgets for common git flows.
//
// These are contracts, not aspirations: each number was MEASURED once on a
// ScratchRepo (see the harness this file replaces — a throwaway
// `_measure_scratch.dart` run) and pinned here. A failure means a caller
// started spawning a different number of git subprocesses for the same
// logical flow — either a new (possibly redundant) subprocess landed, or an
// existing one was coalesced/removed. Either way the number changing is the
// signal to go find out why; see docs/architecture/wiring-redundancy-audit.md
// for the shape of bug this class of test already caught (a double
// `git rev-parse HEAD`, item Tier 1 #1).
//
// Never wall-clock. GitSpawn.runCount/startCount are incremented by every
// subprocess spawn through the seam (see backend/git.dart's GitSpawn doc
// comment) — a deterministic, machine-independent proxy for "how much work
// did this flow actually do."
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';

import '../support/scratch_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('openRepository', () {
    tearDown(GitSpawn.reset);

    test('spawns exactly 1 subprocess on a healthy repo', () async {
      final repo = await ScratchRepo.create(name: 'budget_open_repo');
      addTearDown(repo.dispose);
      // create() itself spawns several git processes (init, identity
      // config append (no spawn — see ScratchRepo._writeIdentityConfig),
      // commit --allow-empty) — reset AFTER create() so only the call
      // under test is counted.
      GitSpawn.reset();

      final result = await openRepository(repo.dir.path);

      expect(result.ok, isTrue);
      expect(GitSpawn.totalCount, 1,
          reason: 'openRepository does one `git rev-parse --git-dir` probe '
              'and nothing else (measured on ScratchRepo). A change here '
              'means a subprocess was added to or removed from the open '
              'path — a costly one to regress since it runs on every '
              'repo-picker click.');
    });
  });

  group('single non-coalesced read', () {
    tearDown(GitSpawn.reset);

    test('a single runGit(status --porcelain) call spawns exactly 1',
        () async {
      final repo = await ScratchRepo.create(name: 'budget_single_status');
      addTearDown(repo.dispose);
      GitSpawn.reset();

      final result =
          await runGit(repo.dir.path, ['status', '--porcelain']);

      expect(result.exitCode, 0);
      expect(GitSpawn.runCount, 1,
          reason: 'one runGit call with no concurrent sibling must spawn '
              'exactly one subprocess — no dedup partner to coalesce with.');
    });
  });

  group('read coalescing', () {
    tearDown(GitSpawn.reset);

    test(
        'two IDENTICAL concurrent reads (same argv) coalesce into 1 spawn',
        () async {
      final repo = await ScratchRepo.create(name: 'budget_coalesce_same');
      addTearDown(repo.dispose);
      GitSpawn.reset();

      // Bare runGit (not repo.git) — repo.git sets extraEnv, which
      // _git's dedup path explicitly skips (see git.dart:792-797:
      // "A call carrying extraEnv ... always skips the dedup path").
      final results = await Future.wait([
        runGit(repo.dir.path, ['status', '--porcelain']),
        runGit(repo.dir.path, ['status', '--porcelain']),
      ]);

      expect(results[0].exitCode, 0);
      expect(results[1].exitCode, 0);
      expect(GitSpawn.runCount, 1,
          reason: 'two callers asking for the identical (workingDir, args) '
              'read in the same instant must share ONE subprocess via the '
              '_inflightGitReads dedup cache (git.dart:798-809). A change '
              'to 2 means the coalescing seam broke for this subcommand.');
    });

    test('two DIFFERENT concurrent reads spawn 2 (no false coalescing)',
        () async {
      final repo = await ScratchRepo.create(name: 'budget_coalesce_diff');
      addTearDown(repo.dispose);
      GitSpawn.reset();

      final results = await Future.wait([
        runGit(repo.dir.path, ['status', '--porcelain']),
        runGit(repo.dir.path, ['rev-parse', '--verify', 'HEAD']),
      ]);

      expect(results[0].exitCode, 0);
      expect(results[1].exitCode, 0);
      expect(GitSpawn.runCount, 2,
          reason: 'different argv must never share a dedup-cache entry — '
              'if this drops to 1, two logically different git reads are '
              'being conflated and one caller would silently receive the '
              "other's answer.");
    });
  });

  group('real read flows', () {
    tearDown(GitSpawn.reset);

    test('git log -5 spawns exactly 1', () async {
      final repo = await ScratchRepo.create(name: 'budget_flow_log');
      addTearDown(repo.dispose);
      GitSpawn.reset();

      final result =
          await runGit(repo.dir.path, ['log', '--oneline', '-5']);

      expect(result.exitCode, 0);
      expect(GitSpawn.runCount, 1,
          reason: 'a single `git log` read, uncontended, is one spawn.');
    });

    test('git diff (working-tree) spawns exactly 1', () async {
      final repo = await ScratchRepo.create(name: 'budget_flow_diff');
      addTearDown(repo.dispose);
      GitSpawn.reset();

      final result = await runGit(repo.dir.path, ['diff']);

      expect(result.exitCode, 0);
      expect(GitSpawn.runCount, 1,
          reason: 'a single `git diff` read, uncontended, is one spawn.');
    });

    test('git rev-parse HEAD spawns exactly 1', () async {
      final repo = await ScratchRepo.create(name: 'budget_flow_revparse');
      addTearDown(repo.dispose);
      GitSpawn.reset();

      final result = await runGit(repo.dir.path, ['rev-parse', 'HEAD']);

      expect(result.exitCode, 0);
      expect(GitSpawn.runCount, 1,
          reason: 'a single `git rev-parse` read, uncontended, is one '
              'spawn.');
    });

    test(
        'three sequential DIFFERENT reads (log, diff, rev-parse) spawn '
        'exactly 3 — no cross-call dedup leakage', () async {
      final repo = await ScratchRepo.create(name: 'budget_flow_sequence');
      addTearDown(repo.dispose);
      GitSpawn.reset();

      await runGit(repo.dir.path, ['log', '--oneline', '-5']);
      await runGit(repo.dir.path, ['diff']);
      await runGit(repo.dir.path, ['rev-parse', 'HEAD']);

      expect(GitSpawn.runCount, 3,
          reason: 'sequential (non-concurrent) reads never share the '
              'in-flight dedup cache — each has already completed and been '
              'evicted before the next starts — so three different reads '
              'must cost three spawns, not fewer.');
    });
  });
}
