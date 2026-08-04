// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

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

/// Private scratch dir the exec path is pointed at for the hygiene group, set
/// up in that group's setUp.
///
/// It used to scan [Directory.systemTemp] and diff the `ai_stdin_*` names
/// before against after. That was wrong twice over. It is a shared namespace,
/// so a concurrently running suite doing its own stdin run lands in the diff
/// and fails a test that leaked nothing; and enumerating it is O(everything on
/// the machine), which on a box with a large temp dir costs seconds per call,
/// twice per test, which is what pushed these past the 30s deadline under load.
/// A private directory answers the real question, and enumerating it is O(2).
late Directory _scratchDir;

/// Everything currently sitting in the injected scratch dir.
Set<String> _stdinScratch() {
  return _scratchDir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
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
        // The deadline is enforced by awaiting exitCode with a timeout, so a
        // command that FINISHES before that await begins returns ok even with
        // a 1µs budget — `rev-parse HEAD` did exactly that on Linux tmpfs and
        // the timeout branch never ran. `git daemon --port=0` blocks in the
        // foreground indefinitely on every OS, so the timeout branch (kill
        // tree, return null → GitResult.err) fires deterministically. The
        // load-bearing check is that the permit comes back.
        final res = await runGitCommandForTesting(
          repo.path,
          const ['daemon', '--port=0', '--base-path=.'],
          timeout: const Duration(milliseconds: 300),
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
    setUp(() async {
      _scratchDir = await Directory.systemTemp.createTemp('ai_stdin_scratch_');
      debugStdinScratchDirOverride = _scratchDir;
    });

    tearDown(() async {
      debugStdinScratchDirOverride = null;
      await _safeCleanup(_scratchDir);
    });

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

    test('a batch of stdin runs cleans up after itself', () async {
      if (!Platform.isWindows) return;
      final before = _stdinScratch();
      await Future.wait(
        List.generate(
          6,
          (i) => runObservedProcessForTesting(
            'findstr',
            const ['marker'],
            stdinPayload: 'marker_$i\n',
            timeout: const Duration(seconds: 20),
          ),
        ).toList(),
      );
      expect(_stdinScratch().difference(before), isEmpty);
    });
  });

  group('stdin scratch naming', () {
    test('names are unique even when derived in the same millisecond', () {
      // The name was `ai_stdin_<epochMs>_<commandLabel.hashCode>`: both halves
      // are shared by concurrent runs of the same command, so any two deriving
      // a name inside one millisecond got the SAME path and silently shared a
      // file. Racing real subprocesses does not reliably reproduce that — the
      // synchronous payload writes drift past the millisecond boundary on
      // their own, so the collision window rarely lands and a timing test
      // passes while the defect is present.
      //
      // The invariant is what is worth pinning, and it is exact: names must be
      // distinct. Deriving a batch in a tight loop pins every one of them to
      // the same millisecond by construction, which is precisely the case that
      // used to collapse.
      const label = 'ai.same-command';
      final names = <String>{};
      final sw = Stopwatch()..start();
      var derived = 0;
      while (sw.elapsedMilliseconds < 2) {
        names.add(debugStdinScratchName(label));
        derived++;
      }
      expect(derived, greaterThan(1),
          reason: 'need at least two names inside the same millisecond band '
              'for this to be testing anything');
      expect(names.length, derived,
          reason: 'derived $derived names but only ${names.length} distinct; '
              'equal names mean two concurrent runs share one scratch file');
    });
  });
}
