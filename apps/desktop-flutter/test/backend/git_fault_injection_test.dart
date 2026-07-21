// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Exercises the retry/decode/recovery paths inside `_gitRaw` and `_git`
// (lib/backend/git.dart) by scripting failures at the `GitSpawn` seam — see
// test/support/git_faults.dart. Nothing here spawns a real failing process;
// the index.lock contention race in particular can only be forced this way,
// since a real machine only hits it under a genuine race.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';

import '../support/git_faults.dart';
import '../support/scratch_repo.dart';

/// A working directory string used by tests where the script never
/// delegates to real git — no filesystem access ever occurs on this path,
/// it is only threaded through as an opaque argument.
const _kFakeRepoDir = 'C:/fake-repo';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(GitSpawn.reset);

  group('index.lock retry loop', () {
    test(
      'actually retries: two contended attempts then a real success',
      () async {
        final repo = await ScratchRepo.create(name: 'lock_retry_succeeds');
        addTearDown(repo.dispose);
        await repo.writeFile('a.txt', 'hello\n');
        await repo.stageAll();

        final script = GitFaultScript.failWhile(
          (args) => args.isNotEmpty && args.first == 'commit',
          times: 2,
          result: indexLockContention,
        );

        // `create()` + `stageAll()` above already spawned real git processes
        // (init, the root commit, add) — reset so only the commit under test
        // is counted, matching the pattern in git_spawn_seam_test.dart.
        GitSpawn.reset();

        late ProcessResult result;
        var spawnCount = -1;
        await withGitFaults(script, () async {
          result = await repo.git([
            'commit',
            '-m',
            'retried through fault injection',
          ]);
          spawnCount = GitSpawn.runCount;
        });

        expect(
          result.exitCode,
          0,
          reason:
              'the commit should succeed once the 3rd attempt reaches '
              'the real git binary — the first two were scripted '
              'index.lock failures',
        );
        expect(
          spawnCount,
          3,
          reason:
              '2 injected index.lock failures + 1 real success = 3 '
              'spawns for one logical runGit call — this is the first test '
              'in the repo\'s history to exercise the retry loop actually '
              'retrying',
        );
        expect(script.invocations.length, 3);
        expect(
          script.invocations.every((inv) => inv.args.first == 'commit'),
          isTrue,
        );
      },
    );

    test('gives up after maxLockRetries = 5', () async {
      final script = GitFaultScript.always((_) => indexLockContention());

      late ProcessResult result;
      var spawnCount = -1;
      await withGitFaults(script, () async {
        result = await runGit(_kFakeRepoDir, [
          'commit',
          '-m',
          'always contended',
        ]);
        spawnCount = GitSpawn.runCount;
      });

      expect(
        result.exitCode,
        isNot(0),
        reason:
            'every attempt was scripted to fail, so the call must '
            'ultimately surface a failure once retries are exhausted',
      );
      expect(
        spawnCount,
        6,
        reason:
            'pins maxLockRetries = 5 as a contract: 1 initial attempt '
            '+ 5 exponentially backed-off retries = 6 spawns, then give '
            'up. The lock is held for the duration of the competing git '
            'process — which stretches with system load — so the window '
            'must escalate rather than exhaust at a fixed ~450ms.',
      );
    });

    test('a non-mutating command never retries', () async {
      final script = GitFaultScript.always((_) => indexLockContention());

      late ProcessResult result;
      var spawnCount = -1;
      await withGitFaults(script, () async {
        result = await runGit(_kFakeRepoDir, ['status', '--porcelain']);
        spawnCount = GitSpawn.runCount;
      });

      expect(
        result.exitCode,
        isNot(0),
        reason: 'the scripted failure must surface immediately',
      );
      expect(
        spawnCount,
        1,
        reason:
            '`status` is in _kDedupableSubcommands, so '
            '_isMutatingGitCall is false and the index.lock retry loop '
            'must never fire even though the stderr shape matches',
      );
    });

    test('a non-lock failure never retries', () async {
      final script = GitFaultScript.always(
        (_) => gitFail(128, 'fatal: not a git repository'),
      );

      late ProcessResult result;
      var spawnCount = -1;
      await withGitFaults(script, () async {
        result = await runGit(_kFakeRepoDir, ['commit', '-m', 'irrelevant']);
        spawnCount = GitSpawn.runCount;
      });

      expect(result.exitCode, 128);
      expect(
        spawnCount,
        1,
        reason:
            'a mutating command CAN retry, but only on the '
            'documented index.lock stderr shape — an unrelated failure '
            'must return on the first attempt',
      );
    });

    // Parameterized over the documented stderr shapes _isIndexLockContention
    // matches (all three of index.lock + File exists / Unable to create /
    // Another git process) and two near-misses that must NOT retry (only
    // one of the two required fragments present).
    final retryCases = <String, bool>{
      "fatal: index.lock: File exists": true,
      "fatal: Unable to create '.git/index.lock'": true,
      "fatal: Another git process seems to be running (index.lock)": true,
      "fatal: index.lock": false,
      "fatal: File exists": false,
    };

    for (final entry in retryCases.entries) {
      final stderrText = entry.key;
      final shouldRetry = entry.value;
      test('retry only fires on the documented stderr shape: '
          '"$stderrText" -> ${shouldRetry ? "retries" : "no retry"}', () async {
        final script = GitFaultScript.always((_) => gitFail(128, stderrText));

        var spawnCount = -1;
        await withGitFaults(script, () async {
          await runGit(_kFakeRepoDir, ['commit', '-m', 'x']);
          spawnCount = GitSpawn.runCount;
        });

        expect(
          spawnCount,
          shouldRetry ? 6 : 1,
          reason: shouldRetry
              ? 'stderr "$stderrText" contains "index.lock" AND one of '
                    'the required companion fragments — must retry to '
                    'exhaustion (6 spawns)'
              : 'stderr "$stderrText" is missing a required fragment — '
                    'must never retry (1 spawn)',
        );
      });
    }
  });

  group('read-coalescing', () {
    test('collapses identical concurrent reads, never mutations', () async {
      final repo = await ScratchRepo.create(name: 'read_coalescing');
      addTearDown(repo.dispose);

      // Deliberately calling `runGit` directly (not `repo.git`, which
      // always layers a non-null extraEnv) — coalescing only applies when
      // extraEnv is null, so this must bypass ScratchRepo's convenience
      // wrapper to exercise the real dedup path.
      GitSpawn.reset();
      final f1 = runGit(repo.dir.path, ['status', '--porcelain']);
      final f2 = runGit(repo.dir.path, ['status', '--porcelain']);
      final results = await Future.wait([f1, f2]);

      expect(
        GitSpawn.runCount,
        1,
        reason:
            'two IDENTICAL concurrent reads fired without awaiting '
            'the first must coalesce into exactly one subprocess spawn',
      );
      expect(results[0].exitCode, results[1].exitCode);
      expect(
        results[0].stdout.toString(),
        results[1].stdout.toString(),
        reason:
            'both callers must observe the same bytes — the shared '
            'in-flight future',
      );

      GitSpawn.reset();
      final r1 = await runGit(repo.dir.path, ['status', '--porcelain']);
      final r2 = await runGit(repo.dir.path, ['rev-parse', 'HEAD']);
      expect(r1.exitCode, 0);
      expect(r2.exitCode, 0);
      expect(
        GitSpawn.runCount,
        2,
        reason: 'two DIFFERENT read commands must never coalesce',
      );

      GitSpawn.reset();
      await repo.git(['commit', '--allow-empty', '-m', 'dup a']);
      await repo.git(['commit', '--allow-empty', '-m', 'dup a']);
      expect(
        GitSpawn.runCount,
        2,
        reason:
            'two IDENTICAL mutating commands (commit) must never be '
            'coalesced — each one always spawns fresh',
      );
    });
  });

  group('decode leniency', () {
    test('garbage on stdout never throws', () async {
      final script = GitFaultScript.always(
        (_) => ProcessResult(0, 0, const <int>[
          0xFF,
          0xFE,
          0x00,
          0x80,
        ], const <int>[]),
      );

      ProcessResult? result;
      await withGitFaults(script, () async {
        result = await runGit(_kFakeRepoDir, ['log']);
      });

      expect(
        result,
        isNotNull,
        reason:
            'runGit must return normally, not throw, when stdout is '
            'invalid UTF-8 — `log` is not in _kStrictDecodeSubcommands so '
            'the lenient (U+FFFD substitution) decode path applies',
      );
      expect(result!.exitCode, 0);
      expect(
        result!.stdout,
        isA<String>(),
        reason:
            'the malformed bytes must have been leniently decoded '
            'into a String, not left as raw bytes or thrown as a '
            'FormatException',
      );
    });
  });

  group('spawn-level failure', () {
    test('a thrown ProcessException propagates cleanly, not hangs', () async {
      GitSpawn.runOverride = (args, {workingDirectory, environment}) async {
        throw ProcessException('git', args);
      };

      final future = runGit(_kFakeRepoDir, ['status']);
      await expectLater(future, throwsA(isA<ProcessException>()));

      expect(
        GitSpawn.runCount,
        1,
        reason:
            '_spawnRunRaw increments the counter before invoking the '
            'override, so even a throwing override still counts as one '
            'spawn attempt',
      );
    });
  });

  group('recovery', () {
    test('a real repo survives a faulted operation', () async {
      final repo = await ScratchRepo.create(name: 'fault_recovery');
      addTearDown(repo.dispose);
      await repo.writeFile('x.txt', 'content\n');

      final script = GitFaultScript.failWhile(
        (args) => args.isNotEmpty && args.first == 'add',
        times: 1,
        result: () => gitFail(1, 'fatal: injected add failure'),
      );

      late ProcessResult addResult;
      await withGitFaults(script, () async {
        addResult = await repo.git(['add', '-A']);
      });

      expect(
        addResult.exitCode,
        isNot(0),
        reason:
            'the injected `git add` failure must surface to the '
            'caller, not be silently swallowed or retried (add is '
            'mutating but the stderr shape is not an index.lock '
            'contention, so no retry is expected either)',
      );

      final fsck = await repo.git(['fsck', '--full', '--no-dangling']);
      expect(
        fsck.exitCode,
        0,
        reason:
            'a failed git operation must never corrupt the repo — '
            'fsck must still pass cleanly afterward, using the real git '
            'binary (the fault script has been uninstalled by now)',
      );
    });
  });
}
