// End-to-end tests for [GitDirWatcher]. These are REAL filesystem-watch
// tests: each spins up a temp git repo, points a live watcher at it,
// mutates `.git` with shell `git`, and asserts the coalesced callback
// fires (or doesn't). Filesystem event delivery — especially on Windows
// via ReadDirectoryChangesW — is asynchronous and latent, so every
// assertion is *eventual*: we poll a counter with a generous bounded
// timeout rather than sleeping a fixed amount and hoping. A "settle"
// window (a few debounce periods) is used to confirm a burst has fully
// coalesced or that no further callback is coming.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git_dir_watcher.dart';

const _debounce = Duration(milliseconds: 400);

Future<Directory> _newRepo() async {
  final dir = await Directory.systemTemp.createTemp('gitwatch_test_');
  await _git(dir, ['init', '-q', '-b', 'main']);
  await _git(dir, ['config', 'user.name', 'test']);
  await _git(dir, ['config', 'user.email', 'test@local']);
  await _git(dir, ['commit', '--allow-empty', '-m', 'root']);
  return dir;
}

Future<ProcessResult> _git(Directory dir, List<String> args) =>
    Process.run('git', args, workingDirectory: dir.path);

/// Tolerant cleanup — Windows briefly holds handles after `git` exits.
Future<void> _safeCleanup(Directory dir) async {
  try {
    await dir.delete(recursive: true);
  } on FileSystemException {
    // The handles drop on their own; the tmp dir is the OS's problem.
  }
}

/// Poll [cond] until true or [timeout] elapses. Eventual assertions ride
/// on this so tests don't hinge on a single fixed sleep.
Future<void> _waitFor(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 6),
  Duration poll = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(poll);
  }
}

/// Let a burst settle: long enough that any pending debounce has fired
/// and no further coalesced callback is in flight.
Future<void> _settle() =>
    Future<void>.delayed(_debounce * 3 + const Duration(milliseconds: 200));

/// Start a watcher and give the OS a beat to actually register the
/// watches before we start mutating.
Future<GitDirWatcher> _startWatching(
  String path,
  void Function() onChanged,
) async {
  final w = GitDirWatcher(path, onChanged, debounce: _debounce);
  await w.start();
  await Future<void>.delayed(const Duration(milliseconds: 400));
  return w;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an external commit fires exactly one coalesced callback', () async {
    final repo = await _newRepo();
    var count = 0;
    final w = await _startWatching(repo.path, () => count++);
    try {
      await _git(repo, ['commit', '--allow-empty', '-m', 'external']);
      await _waitFor(() => count >= 1);
      await _settle();
      expect(count, 1, reason: 'one commit should coalesce to one callback');
    } finally {
      w.dispose();
      await _safeCleanup(repo);
    }
  });

  test('branch create then delete fires', () async {
    final repo = await _newRepo();
    var count = 0;
    final w = await _startWatching(repo.path, () => count++);
    try {
      await _git(repo, ['branch', 'feature']);
      await _waitFor(() => count >= 1);
      await _settle();
      final afterCreate = count;
      expect(afterCreate, greaterThanOrEqualTo(1));

      await _git(repo, ['branch', '-D', 'feature']);
      await _waitFor(() => count > afterCreate);
      await _settle();
      expect(count, greaterThan(afterCreate),
          reason: 'the delete is a distinct external change');
    } finally {
      w.dispose();
      await _safeCleanup(repo);
    }
  });

  test('refs/ absent at start is recovered when the directory appears',
      () async {
    final repo = await _newRepo();
    // A refs-less repo is unreachable from outside — git refuses to run
    // without `refs/` (it's part of git-dir detection), so start()'s
    // rev-parse would fail before any watch landed. The real-world gap is
    // the refs watch failing to ESTABLISH (permissions, network FS) while
    // the common-dir watch is live; `debugSkipInitialRefsWatch` simulates
    // exactly that, and raw FS ops stand in for whatever recreates the
    // tree — the watcher only ever sees filesystem events anyway.
    await _git(repo, ['pack-refs', '--all']);
    final refsDir = Directory('${repo.path}/.git/refs');

    var count = 0;
    final w = GitDirWatcher(repo.path, () => count++, debounce: _debounce)
      ..debugSkipInitialRefsWatch = true;
    try {
      await w.start();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      // Loose-ref activity is invisible while the refs watch is down; the
      // `refs` directory being re-made is the recovery cue.
      if (await refsDir.exists()) await refsDir.delete(recursive: true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final headsDir = Directory('${refsDir.path}/heads')
        ..createSync(recursive: true);
      await _waitFor(() => count >= 1);
      await _settle();
      expect(count, greaterThanOrEqualTo(1),
          reason: 'refs/ created after start() must still be watched');

      // And the recovered watch stays live for later loose-ref activity.
      final before = count;
      File('${headsDir.path}/reborn')
          .writeAsStringSync('0000000000000000000000000000000000000000\n');
      await _waitFor(() => count > before);
      expect(count, greaterThan(before),
          reason: 'coverage must persist after the late install');
    } finally {
      w.dispose();
      await _safeCleanup(repo);
    }
  });

  test('packed-refs rewrite survives rename-over and keeps firing',
      () async {
    // pack-refs writes a temp file and renames it over `packed-refs`.
    // A watch bound to the file inode would die on the first rename;
    // our directory watch must survive it and report the SECOND pack
    // too — that's the empirical proof the parent-dir strategy works.
    final repo = await _newRepo();
    var count = 0;
    final w = await _startWatching(repo.path, () => count++);
    try {
      await _git(repo, ['branch', 'b1']);
      await _git(repo, ['pack-refs', '--all']);
      await _waitFor(() => count >= 1);
      await _settle();
      final afterFirstPack = count;
      expect(afterFirstPack, greaterThanOrEqualTo(1));

      // Second rename-over of packed-refs. If the watch had died with the
      // first rename this would never fire.
      await _git(repo, ['branch', 'b2']);
      await _git(repo, ['pack-refs', '--all']);
      await _waitFor(() => count > afterFirstPack);
      await _settle();
      expect(count, greaterThan(afterFirstPack),
          reason: 'packed-refs watch survived the first rename-over');
    } finally {
      w.dispose();
      await _safeCleanup(repo);
    }
  });

  test('events during pause() coalesce into exactly one fire on resume()',
      () async {
    final repo = await _newRepo();
    var count = 0;
    final w = await _startWatching(repo.path, () => count++);
    try {
      w.pause();
      await _git(repo, ['commit', '--allow-empty', '-m', 'while paused']);
      await _git(repo, ['branch', 'ghost']);
      await _settle();
      expect(count, 0, reason: 'no callbacks while paused');

      // Everything that arrived while paused collapses to ONE debounced
      // fire — the pause exists to coalesce bulk churn, not to lose it.
      w.resume();
      await _waitFor(() => count >= 1);
      await _settle();
      expect(count, 1,
          reason: 'paused-time events must fire once, not per-event');

      // A fresh change after resume is seen normally.
      await _git(repo, ['commit', '--allow-empty', '-m', 'after resume']);
      await _waitFor(() => count >= 2);
      expect(count, greaterThanOrEqualTo(2));
    } finally {
      w.dispose();
      await _safeCleanup(repo);
    }
  });

  test('resume() without paused-time events does not fire', () async {
    final repo = await _newRepo();
    var count = 0;
    final w = await _startWatching(repo.path, () => count++);
    try {
      w.pause();
      await _settle();
      w.resume();
      await _settle();
      expect(count, 0, reason: 'nothing happened — nothing to report');
    } finally {
      w.dispose();
      await _safeCleanup(repo);
    }
  });

  test('dispose() stops events', () async {
    final repo = await _newRepo();
    var count = 0;
    final w = await _startWatching(repo.path, () => count++);
    try {
      w.dispose();
      await _git(repo, ['commit', '--allow-empty', '-m', 'post dispose']);
      await _git(repo, ['branch', 'later']);
      await _settle();
      expect(count, 0, reason: 'a disposed watcher never fires');
    } finally {
      await _safeCleanup(repo);
    }
  });

  test('a burst of 10 rapid commits coalesces to few callbacks', () async {
    final repo = await _newRepo();
    var count = 0;
    final w = await _startWatching(repo.path, () => count++);
    try {
      for (var i = 0; i < 10; i++) {
        await _git(repo, ['commit', '--allow-empty', '-m', 'burst $i']);
      }
      await _waitFor(() => count >= 1);
      await _settle();
      expect(count, lessThanOrEqualTo(3),
          reason: '10 commits must not produce 10 callbacks (got $count)');
      expect(count, greaterThanOrEqualTo(1));
    } finally {
      w.dispose();
      await _safeCleanup(repo);
    }
  });

  test('a linked worktree HEAD move fires', () async {
    final repo = await _newRepo();
    final wtParent = await Directory.systemTemp.createTemp('gitwatch_wt_');
    final wtPath = '${wtParent.path}/desk';
    var count = 0;
    GitDirWatcher? w;
    try {
      // A branch to check out in the linked worktree.
      await _git(repo, ['branch', 'feature']);
      final add = await _git(repo, ['worktree', 'add', wtPath, 'feature']);
      expect(add.exitCode, 0, reason: add.stderr.toString());

      // Watch the LINKED worktree: its git dir (.git/worktrees/desk) holds
      // its own HEAD, distinct from the common dir.
      final wtDir = Directory(wtPath);
      w = await _startWatching(wtDir.path, () => count++);

      // A checkout inside the linked worktree moves its own HEAD.
      final co = await Process.run(
          'git', ['switch', '--create', 'feature2'],
          workingDirectory: wtPath);
      expect(co.exitCode, 0, reason: co.stderr.toString());

      await _waitFor(() => count >= 1);
      expect(count, greaterThanOrEqualTo(1),
          reason: 'the linked worktree HEAD move should be seen');
    } finally {
      w?.dispose();
      await _safeCleanup(wtParent);
      await _safeCleanup(repo);
    }
  });
}
