// Real-behavior tests for the hardened git exec layer in backend/git.dart:
//   • the non-interactive environment (GIT_TERMINAL_PROMPT / GIT_OPTIONAL_LOCKS)
//     is actually applied to spawned subprocesses,
//   • a transient `index.lock` collision is retried rather than surfaced on the
//     first attempt (and the retry is bounded, not an infinite hang),
//   • static repo geometry (`rev-parse --git-dir` / `--git-path`) is memoized
//     and the memoized value matches a fresh shell-out.
//
// Every test drives a real temp git repo through the public layer and observes
// git's actual behaviour — no mocks. Windows-friendly cleanup mirrors the
// desk_pr_store_test harness.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/diagnostics/diagnostics_state.dart';

Future<Directory> _newRepo() async {
  final dir = await Directory.systemTemp.createTemp('git_exec_env_');
  await Process.run('git', ['init', '-q', '-b', 'main'],
      workingDirectory: dir.path);
  await Process.run('git', ['config', 'user.name', 'test'],
      workingDirectory: dir.path);
  await Process.run('git', ['config', 'user.email', 'test@local'],
      workingDirectory: dir.path);
  await Process.run('git', ['commit', '--allow-empty', '-m', 'root'],
      workingDirectory: dir.path);
  return dir;
}

/// Tolerant cleanup — Windows briefly holds file handles after spawned `git`
/// processes exit, racing our recursive delete for ~100ms. Swallow it; the
/// assertions already ran.
Future<void> _safeCleanup(Directory dir) async {
  try {
    await dir.delete(recursive: true);
  } on FileSystemException {
    // Ignored — see docstring.
  }
}

File _indexLock(Directory repo) =>
    File('${repo.path}${Platform.pathSeparator}.git'
        '${Platform.pathSeparator}index.lock');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(clearRepoGeometryCacheForTesting);

  group('non-interactive environment', () {
    test('GIT_TERMINAL_PROMPT and GIT_OPTIONAL_LOCKS are set on spawns',
        () async {
      final repo = await _newRepo();
      try {
        // A `!`-alias shells out via git's bundled sh with the exact
        // environment we handed the subprocess, so echoing the two vars
        // proves they reached the child. runGit routes through the same
        // _git → _gitRaw path every real call takes.
        await Process.run(
          'git',
          [
            'config',
            'alias.echoenv',
            r'!echo TP=$GIT_TERMINAL_PROMPT LOCKS=$GIT_OPTIONAL_LOCKS'
          ],
          workingDirectory: repo.path,
        );
        final r = await runGit(repo.path, ['echoenv']);
        expect(r.exitCode, 0, reason: r.stderr.toString());
        expect(r.stdout.toString(), contains('TP=0'));
        expect(r.stdout.toString(), contains('LOCKS=0'));
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('index.lock transient retry', () {
    test('a mutation retries past a lock that clears mid-backoff', () async {
      final repo = await _newRepo();
      try {
        await File('${repo.path}${Platform.pathSeparator}a.txt')
            .writeAsString('hi\n');
        int lockEvents() => DiagnosticsState.instance.commandLifecycleEvents
            .where((e) => e.errorCode == 'git.index_lock_contended')
            .length;
        final before = lockEvents();

        // Hold the lock until the layer has recorded its FIRST retry, then
        // release it. This makes the collision deterministic regardless of
        // Windows subprocess-spawn latency — a retry is guaranteed to have
        // happened, and a later attempt (within the 3-try budget) then wins.
        final lock = _indexLock(repo);
        await lock.create();
        final poll = Timer.periodic(const Duration(milliseconds: 10), (t) {
          if (lockEvents() > before) {
            if (lock.existsSync()) lock.deleteSync();
            t.cancel();
          }
        });

        final res = await stagePaths(repo.path, ['a.txt']);
        poll.cancel();
        expect(res.ok, isTrue, reason: res.error);

        // The retry path fired at least once — deterministic proof the layer
        // didn't just happen to run after the lock cleared.
        expect(lockEvents(), greaterThan(before));

        // And the file really landed in the index.
        final staged = await Process.run(
            'git', ['diff', '--cached', '--name-only'],
            workingDirectory: repo.path);
        expect(staged.stdout.toString(), contains('a.txt'));
      } finally {
        await _safeCleanup(repo);
      }
    });

    test('a lock that never clears fails bounded, without hanging', () async {
      final repo = await _newRepo();
      try {
        await File('${repo.path}${Platform.pathSeparator}b.txt')
            .writeAsString('yo\n');
        await _indexLock(repo).create(); // never deleted

        // If the retry were unbounded this future never completes and the
        // test-level timeout below fails loudly instead.
        final res = await stagePaths(repo.path, ['b.txt'])
            .timeout(const Duration(seconds: 10));
        expect(res.ok, isFalse);
        expect(res.error, contains('index.lock'));
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('repo geometry memo', () {
    test('memoized rev-parse matches a fresh shell-out and is cached',
        () async {
      final repo = await _newRepo();
      try {
        for (final args in const [
          ['rev-parse', '--git-dir'],
          ['rev-parse', '--git-path', 'rebase-merge'],
        ]) {
          final fresh = await Process.run('git', args,
              workingDirectory: repo.path);
          final first = await revParseGeometryForTesting(repo.path, args);
          expect(first.exitCode, 0);
          // Byte-for-byte identical to what git prints directly.
          expect(first.stdout.toString(), fresh.stdout.toString());
          // A second call is a memo hit: the SAME ProcessResult instance,
          // never a re-spawn.
          final second = await revParseGeometryForTesting(repo.path, args);
          expect(identical(first, second), isTrue);
        }
      } finally {
        await _safeCleanup(repo);
      }
    });
  });
}
