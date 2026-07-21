// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// End-to-end tests for [GitDirWatcher]. These are REAL filesystem-watch
// tests: each spins up a temp git repo, points a live watcher at it,
// mutates `.git` with shell `git`, and asserts the coalesced callback
// fires (or doesn't). Filesystem event delivery — especially on Windows
// via ReadDirectoryChangesW — is asynchronous and latent, so every
// assertion is *eventual*: we poll a counter with a generous bounded
// timeout rather than sleeping a fixed amount and hoping. A "settle"
// window (a few debounce periods) is used to confirm a burst has fully
// coalesced or that no further callback is coming.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git_dir_watcher.dart';

const _debounce = Duration(milliseconds: 400);

/// Per-row scratch state for the signal-completeness matrix. Each row gets a
/// fresh repo plus a place to register any extra temp dirs (bare remotes,
/// clones, worktrees) so the harness can tear them all down, and a tiny string
/// map to hand a value from a row's `setup` phase to its `act` phase (the two
/// are separate closures and can't share locals).
class _MatrixCtx {
  _MatrixCtx(this.repo) {
    temps.add(repo);
  }
  final Directory repo;
  final List<Directory> temps = [];
  final Map<String, String> data = {};
  Future<Directory> newTemp(String prefix) async {
    final d = await Directory.systemTemp.createTemp(prefix);
    temps.add(d);
    return d;
  }
}

typedef _MatrixPhase = Future<void> Function(_MatrixCtx ctx);

Future<void> _noPhase(_MatrixCtx ctx) async {}

/// One git mutation per row, each asserting exactly one coalesced callback.
/// `setup` runs BEFORE the watcher starts (so its churn isn't counted); `act`
/// is the single trigger performed while watching.
final List<({String name, _MatrixPhase setup, _MatrixPhase act})> _matrixRows =
    [
  (
    name: 'commit',
    setup: _noPhase,
    act: (ctx) async {
      await _git(ctx.repo, ['commit', '--allow-empty', '-m', 'matrix commit']);
    },
  ),
  (
    name: 'branch create',
    setup: _noPhase,
    act: (ctx) async {
      await _git(ctx.repo, ['branch', 'created']);
    },
  ),
  (
    name: 'branch delete',
    setup: (ctx) async {
      await _git(ctx.repo, ['branch', 'doomed']);
    },
    act: (ctx) async {
      await _git(ctx.repo, ['branch', '-D', 'doomed']);
    },
  ),
  (
    name: 'tag create',
    setup: _noPhase,
    act: (ctx) async {
      await _git(ctx.repo, ['tag', 'v1']);
    },
  ),
  (
    name: 'checkout / HEAD change',
    setup: (ctx) async {
      await _git(ctx.repo, ['branch', 'other']);
    },
    act: (ctx) async {
      await _git(ctx.repo, ['checkout', '-q', 'other']);
    },
  ),
  (
    name: 'fetch updates a remote-tracking ref',
    setup: (ctx) async {
      // A bare repo stands in for the remote; the watched repo pushes `main`
      // to establish refs/remotes/origin/main, then a throwaway clone advances
      // the remote so the later fetch has a real ref update to deliver.
      final bare = await ctx.newTemp('gitwatch_bare_');
      await _git(bare, ['init', '-q', '--bare', '-b', 'main']);
      await _git(ctx.repo, ['remote', 'add', 'origin', bare.path]);
      await _git(ctx.repo, ['push', '-q', 'origin', 'main']);
      final other = await ctx.newTemp('gitwatch_clone_');
      await _git(other, ['clone', '-q', bare.path, '.']);
      await _git(other, ['config', 'user.name', 'test']);
      await _git(other, ['config', 'user.email', 'test@local']);
      await _git(other, ['commit', '--allow-empty', '-m', 'remote advance']);
      await _git(other, ['push', '-q', 'origin', 'main']);
    },
    act: (ctx) async {
      await _git(ctx.repo, ['fetch', '-q', 'origin']);
    },
  ),
  (
    name: 'commit inside a linked worktree',
    setup: (ctx) async {
      // The linked worktree keeps its OWN HEAD, but its branch ref lives in
      // the shared common dir — so a commit made inside it must wake a watcher
      // pointed at the ORIGINAL repo.
      final wtParent = await ctx.newTemp('gitwatch_wt_');
      final wtPath = '${wtParent.path}/desk';
      final add = await Process.run(
          'git', ['worktree', 'add', '-b', 'wtbranch', wtPath, 'HEAD'],
          workingDirectory: ctx.repo.path);
      expect(add.exitCode, 0, reason: add.stderr.toString());
      ctx.data['wt'] = wtPath;
    },
    act: (ctx) async {
      final r = await Process.run(
          'git', ['commit', '--allow-empty', '-m', 'in worktree'],
          workingDirectory: ctx.data['wt']!);
      expect(r.exitCode, 0, reason: r.stderr.toString());
    },
  ),
  (
    name: 'branch update after pack-refs (loose→packed transition)',
    setup: (ctx) async {
      // Fold every ref into packed-refs and drop the loose copies first, so
      // `act` exercises the post-pack loose-ref path specifically: a fresh
      // loose ref written after the refs tree was packed must still be seen.
      await _git(ctx.repo, ['branch', 'b1']);
      await _git(ctx.repo, ['pack-refs', '--all']);
    },
    act: (ctx) async {
      await _git(ctx.repo, ['branch', 'afterpack']);
    },
  ),
  (
    name: 'manifold refs update (refs/manifold/…)',
    setup: _noPhase,
    act: (ctx) async {
      // The app writes its own issue-tracking refs under refs/manifold/ and
      // must be able to observe its own writes.
      final sha =
          (await _git(ctx.repo, ['rev-parse', 'HEAD'])).stdout.toString().trim();
      await _git(ctx.repo, ['update-ref', 'refs/manifold/issues/999', sha]);
    },
  ),
];

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
      // Under the FULL suite these commits contend with every other
      // git-heavy test for the process-global subprocess semaphore, so
      // "rapid" is not guaranteed — a gap longer than the quiet period
      // legitimately produces an extra callback, and a fixed ceiling
      // bakes in a wall-clock assumption that flakes under load. Derive
      // the ceiling from the burst's OBSERVED spacing instead: each
      // inter-commit gap that outlives the debounce window can add at
      // most one fire, plus the trailing fire, plus one slack for a fire
      // landing exactly on a window boundary.
      final stamps = <DateTime>[];
      for (var i = 0; i < 10; i++) {
        await _git(repo, ['commit', '--allow-empty', '-m', 'burst $i']);
        stamps.add(DateTime.now());
      }
      var longGaps = 0;
      for (var i = 1; i < stamps.length; i++) {
        if (stamps[i].difference(stamps[i - 1]) > _debounce) longGaps++;
      }
      final ceiling = longGaps + 2;
      await _waitFor(() => count >= 1);
      await _settle();
      expect(count, lessThanOrEqualTo(ceiling),
          reason: '10 commits with $longGaps over-debounce gaps must '
              'coalesce to <= $ceiling callbacks (got $count)');
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

  // ---- lifecycle races ------------------------------------------------

  test('start() then immediate dispose() before resolution never fires',
      () async {
    // dispose() lands while start()'s `git rev-parse` is still in flight —
    // start() must notice `_disposed` after the await and install no watches,
    // completing without throwing and never firing.
    final repo = await _newRepo();
    var count = 0;
    Object? asyncError;
    await runZonedGuarded(() async {
      final w = GitDirWatcher(repo.path, () => count++, debounce: _debounce);
      final starting = w.start(); // NOT awaited — race dispose against setup
      w.dispose();
      await starting; // must resolve cleanly, not throw
      await _git(repo, ['commit', '--allow-empty', '-m', 'after race']);
      await _settle();
      w.dispose(); // idempotent second dispose is harmless
    }, (Object e, StackTrace _) => asyncError = e);
    try {
      expect(asyncError, isNull,
          reason: 'a start/dispose race must not throw ($asyncError)');
      expect(count, 0, reason: 'a watcher disposed mid-start never fires');
    } finally {
      await _safeCleanup(repo);
    }
  });

  test('rapid create/dispose storm across repos: only the live watcher fires',
      () async {
    // No retarget mechanism exists (repoPath is final), so "switching" is
    // create+dispose. Cycle 10 watchers over 3 repos, disposing every one but
    // the last mid-flight, then mutate ONLY the last repo. The live watcher
    // must fire; every disposed watcher — including earlier ones that watched
    // the SAME repo we mutate — must stay silent, proving dispose truly
    // cancels the subscriptions.
    final repos = [await _newRepo(), await _newRepo(), await _newRepo()];
    final counts = List<int>.filled(10, 0);
    GitDirWatcher? live;
    var liveRepo = 0;
    try {
      for (var i = 0; i < 10; i++) {
        final idx = i;
        final repoIndex = i % 3;
        final w = GitDirWatcher(
            repos[repoIndex].path, () => counts[idx]++,
            debounce: _debounce);
        final starting = w.start();
        if (i < 9) {
          w.dispose(); // race dispose against start for all but the last
          await starting;
        } else {
          await starting;
          await Future<void>.delayed(const Duration(milliseconds: 400));
          live = w;
          liveRepo = repoIndex;
        }
      }
      await _git(repos[liveRepo],
          ['commit', '--allow-empty', '-m', 'only the live repo']);
      await _waitFor(() => counts[9] >= 1);
      await _settle();
      expect(counts[9], greaterThanOrEqualTo(1),
          reason: 'the surviving watcher must see its repo change');
      for (var i = 0; i < 9; i++) {
        expect(counts[i], 0,
            reason: 'disposed watcher $i must never fire (got ${counts[i]})');
      }
    } finally {
      live?.dispose();
      for (final r in repos) {
        await _safeCleanup(r);
      }
    }
  });

  // ---- pause/resume under randomized interleaving ---------------------

  test('randomized pause/resume interleaving keeps the channel live',
      () async {
    // NOTE ON SEMANTICS: the source does NOT drop paused-time events — it
    // collapses them into a single flag that resume() turns into one debounced
    // fire (see pause()/resume() and _onRawEvent). So the assertion here is the
    // ACTUAL behavior: while paused nothing surfaces, and after resume the
    // paused burst yields at most one fire — never a per-event burst. The final
    // fresh mutation proves no subscription died across the pause churn.
    final repo = await _newRepo();
    var count = 0;
    final w = await _startWatching(repo.path, () => count++);
    final rng = Random(1234);
    try {
      for (var i = 0; i < 6; i++) {
        final paused = rng.nextBool();
        final before = count;
        if (paused) w.pause();
        await _git(repo, ['commit', '--allow-empty', '-m', 'mut $i']);
        if (paused) {
          await _settle();
          expect(count, before,
              reason: 'no callback may surface while paused (iter $i)');
          w.resume();
          // Coalesced paused events fire at most once, not per raw event.
          await _waitFor(() => count > before);
          await _settle();
          expect(count, before + 1,
              reason: 'paused burst must resume as exactly one fire (iter $i)');
        } else {
          await _waitFor(() => count > before);
          await _settle();
          expect(count, before + 1,
              reason: 'a live mutation fires once (iter $i)');
        }
      }
      // The underlying watches survived every pause/resume cycle.
      final before = count;
      await _git(repo, ['commit', '--allow-empty', '-m', 'final']);
      await _waitFor(() => count > before);
      await _settle();
      expect(count, before + 1,
          reason: 'subscription stayed live through pause/resume churn');
    } finally {
      w.dispose();
      await _safeCleanup(repo);
    }
  });

  // ---- degradation contract -------------------------------------------

  test('deleting the watched repo out from under the watcher stays inert',
      () async {
    // The documented contract is "failures degrade to inert". Wipe the entire
    // repo (working tree AND .git) mid-watch and assert nothing escapes: no
    // synchronous throw, no unhandled async error from the now-dead watch
    // streams, and dispose() still completes cleanly afterward.
    final repo = await _newRepo();
    var count = 0;
    final w = await _startWatching(repo.path, () => count++);
    Object? escaped;
    var deleteThrew = false;
    await runZonedGuarded(() async {
      try {
        repo.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may briefly hold the watch handle; the point of the test is
        // that the WATCHER stays inert, not that the OS lets us delete
        // instantly. Either way no watcher error must escape.
        deleteThrew = true;
      }
      await _settle();
      w.dispose(); // must not throw even though its dirs vanished
    }, (Object e, StackTrace _) => escaped = e);
    try {
      expect(escaped, isNull,
          reason: 'a vanished repo must not surface an error ($escaped)');
      // dispose() is idempotent and safe to call again post-mortem.
      w.dispose();
    } finally {
      // Best-effort cleanup regardless of whether the mid-watch delete landed.
      if (deleteThrew) await _safeCleanup(repo);
    }
  });

  // ---- signal completeness matrix -------------------------------------

  for (final row in _matrixRows) {
    test('signal matrix — ${row.name} fires exactly one callback', () async {
      final ctx = _MatrixCtx(await _newRepo());
      var count = 0;
      GitDirWatcher? w;
      try {
        await row.setup(ctx);
        w = await _startWatching(ctx.repo.path, () => count++);
        await row.act(ctx);
        await _waitFor(() => count >= 1);
        await _settle();
        expect(count, 1,
            reason: '${row.name}: exactly one coalesced callback (got $count)');
      } finally {
        w?.dispose();
        for (final d in ctx.temps) {
          await _safeCleanup(d);
        }
      }
    });
  }

  // ---- non-signals -----------------------------------------------------

  test('a pure working-tree edit does NOT fire the watcher', () async {
    // The watcher covers .git metadata only. Editing a file in the working
    // tree with no `git add`/`commit` touches nothing it watches.
    final repo = await _newRepo();
    var count = 0;
    final w = await _startWatching(repo.path, () => count++);
    try {
      File('${repo.path}/scratch.txt')
          .writeAsStringSync('a pure working-tree edit\n');
      // Wait several detection latencies; silence must persist.
      await _settle();
      await _settle();
      expect(count, 0,
          reason: 'working-tree edits are not .git metadata (got $count)');
    } finally {
      w.dispose();
      await _safeCleanup(repo);
    }
  });
}
