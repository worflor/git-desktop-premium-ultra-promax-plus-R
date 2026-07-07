// Real-behavior tests for the AI backend's git-execution parity with the
// hardened backend/git.dart layer:
//   • throttling is real — a burst of git runs launched through ai.dart's own
//     runner contends for the SAME shared subprocess semaphore, so peak
//     concurrency never exceeds git.dart's ceiling (it used to burst unbounded
//     and defeat the AIMD controller),
//   • the shared permit is released on every exit path — an exception thrown
//     inside `withGitSubprocessLimit`, and a genuine command timeout — never
//     strand a permit,
//   • the Windows stdin-via-tempfile path leaves no `.tmp`/`.bat` residue,
//     including when the child is force-killed on timeout.
//
// Every test drives real subprocesses; no mocks. Windows-tolerant cleanup
// mirrors the git_exec_env_test harness.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart';
import 'package:git_desktop/backend/git.dart';

Future<Directory> _newRepo() async {
  final dir = await Directory.systemTemp.createTemp('ai_git_exec_');
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
/// processes exit, racing our recursive delete. Swallow it; assertions ran.
Future<void> _safeCleanup(Directory dir) async {
  try {
    await dir.delete(recursive: true);
  } on FileSystemException {
    // Ignored — see docstring.
  }
}

/// Names of the stdin scratch files the Windows exec path drops in the system
/// temp dir. Both the payload (`ai_stdin_*.tmp`) and its `.bat` sibling share
/// the `ai_stdin_` prefix.
Set<String> _stdinScratch() {
  return Directory.systemTemp
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((name) => name.startsWith('ai_stdin_'))
      .toSet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shared-semaphore throttling', () {
    test('a burst of git runs never exceeds the shared ceiling', () async {
      final repo = await _newRepo();
      try {
        resetGitSubprocessPeakForTesting();
        // Fire far more than the ceiling at once. `.toList()` forces the map so
        // all acquires happen in the same synchronous burst, before any child
        // completes — the high-water mark reflects the real cap, not luck.
        final futures = List.generate(
          12,
          (_) => runGitCommandForTesting(repo.path, const ['rev-parse', 'HEAD']),
        ).toList();
        final results = await Future.wait(futures);

        for (final r in results) {
          expect(r.ok, isTrue, reason: r.error);
        }
        final peak = gitSubprocessPeakForTesting();
        // Throttle is real: 12 requested, at most the ceiling ran together.
        expect(peak, lessThanOrEqualTo(gitSubprocessMaxConcurrency));
        // ...and they really did overlap (not silently serialized to 1).
        expect(peak, greaterThan(1));
        // Every permit handed back afterward.
        expect(gitSubprocessActiveForTesting(), 0);
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('permit release on every exit path', () {
    test('an exception inside withGitSubprocessLimit still releases', () async {
      expect(gitSubprocessActiveForTesting(), 0);
      await expectLater(
        withGitSubprocessLimit<void>(() async {
          throw StateError('boom');
        }),
        throwsStateError,
      );
      // The finally in withGitSubprocessLimit ran despite the throw.
      expect(gitSubprocessActiveForTesting(), 0);
    });

    test('a git command that times out releases its permit', () async {
      final repo = await _newRepo();
      try {
        expect(gitSubprocessActiveForTesting(), 0);
        // A 1µs budget can't outrun even the fastest process spawn, so the
        // observed run hits its timeout branch (kill tree, return null →
        // GitResult.err). The load-bearing check is that the permit comes
        // back regardless of which branch won.
        final res = await runGitCommandForTesting(
          repo.path,
          const ['rev-parse', 'HEAD'],
          timeout: const Duration(microseconds: 1),
        );
        expect(res.ok, isFalse);
        expect(res.error, contains('timed out'));
        expect(gitSubprocessActiveForTesting(), 0);
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('stdin temp-file hygiene (Windows)', () {
    test('a completed stdin command leaves no scratch files', () async {
      if (!Platform.isWindows) return;
      final before = _stdinScratch();
      // findstr reads redirected stdin, prints matching lines, exits 0.
      final r = await runObservedProcessForTesting(
        'findstr',
        const ['x'],
        stdinPayload: 'xylophone\nno match here\n',
        timeout: const Duration(seconds: 10),
      );
      expect(r, isNotNull);
      expect(r!.exitCode, 0);
      expect(r.stdout, contains('xylophone'));
      expect(_stdinScratch().difference(before), isEmpty);
    });

    test('a stdin command killed on timeout leaves no scratch files', () async {
      if (!Platform.isWindows) return;
      final before = _stdinScratch();
      // ping ignores stdin and runs for ~30s; the tiny timeout forces the
      // kill-tree path. killProcessTree confirms exit before the finally
      // unlinks, so the .tmp/.bat must still be gone afterward.
      final r = await runObservedProcessForTesting(
        'ping',
        const ['-n', '30', '127.0.0.1'],
        stdinPayload: 'ignored payload\n',
        timeout: const Duration(milliseconds: 300),
      );
      expect(r, isNull); // null == genuine timeout
      expect(_stdinScratch().difference(before), isEmpty);
    });
  });
}
