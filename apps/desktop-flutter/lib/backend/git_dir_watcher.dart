import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'git.dart' as git;

/// Watches a repository's `.git` metadata for *external* mutations —
/// a commit from a terminal, a branch created by another tool, a fetch,
/// a checkout in a linked worktree — and fires a single coalesced
/// callback so the app can refresh state it would otherwise only learn
/// about on a manual refresh.
///
/// The design is deliberately narrow. Watching the whole `.git` tree is
/// a trap: `index`, `index.lock`, `FETCH_HEAD`, `ORIG_HEAD`,
/// `COMMIT_EDITMSG`, `objects/`, and `logs/` all churn constantly (much
/// of it driven by the app's OWN git commands), which would turn the
/// watcher into a feedback storm. Instead we whitelist the handful of
/// paths that actually encode reachable repository state:
///
///  * the common dir's `HEAD` — the current branch of the main worktree,
///  * `packed-refs` — where git stores the bulk of refs after a pack,
///  * `refs/` — loose branch/tag/remote refs (create, delete, move),
///  * the active worktree's own `HEAD` (for linked worktrees, whose
///    `HEAD` lives in the per-worktree git dir, not the common dir).
///
/// Together those cover commits, branch/tag lifecycle, fetches, and
/// checkouts without ever waking on index or object churn.
///
/// Every raw filesystem event is fed through a quiet-period debounce:
/// the callback fires once, [debounce] after the LAST event in a burst,
/// so a flurry of writes (a rebase, a fetch, our own multi-step git
/// pipelines) collapses into a single "repo changed" notification.
///
/// Establishing a watch can fail for mundane reasons — permissions, an
/// exotic or network filesystem, a path that isn't a git repo at all.
/// Every failure degrades silently to inert: the watcher simply never
/// fires, and the app behaves exactly as it did before watching existed.
class GitDirWatcher {
  GitDirWatcher(
    this.repoPath,
    this.onRepoChanged, {
    this.debounce = const Duration(milliseconds: 500),
  });

  /// A path inside the repository (its root, or any worktree). The git
  /// dir and common dir are resolved from here via `git rev-parse`.
  final String repoPath;

  /// Fired once per coalesced burst of external `.git` mutations. Never
  /// called after [dispose], nor for events that arrive while paused.
  final void Function() onRepoChanged;

  /// Quiet period after the last raw event before the coalesced callback
  /// fires. Long enough to absorb a multi-step git pipeline, short enough
  /// that an external commit surfaces promptly.
  final Duration debounce;

  final List<StreamSubscription<FileSystemEvent>> _subs = [];
  Timer? _debounceTimer;
  bool _started = false;
  bool _disposed = false;
  bool _paused = false;
  bool _pendingWhilePaused = false;

  /// Resolve the git dirs and establish the watches. Safe to await; any
  /// failure leaves the watcher inert. Calling twice is a no-op.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    final dirs = await _resolveGitDirs();
    if (dirs == null || _disposed) return;
    final (gitDir, commonDir) = dirs;

    // The common dir itself, watched non-recursively: this is how HEAD
    // and packed-refs updates arrive. Crucially we watch the *directory*
    // and filter by filename rather than watching the files directly —
    // git frequently updates `packed-refs` (and sometimes HEAD) by
    // writing a temp file and renaming it over the target, which would
    // silently kill a watch bound to the file inode. A directory watch
    // survives the rename-over and reports it as an event on the child.
    // This watch is also the recovery path for a missing `refs/`: it sees
    // the `refs` directory being created and installs the refs watch then
    // (see [_onCommonDirEvent]).
    _watch(commonDir, recursive: false,
        accept: _isCommonDirRefFile, onEvent: _onCommonDirEvent);

    // Loose refs. On Windows (ReadDirectoryChangesW) and macOS (FSEvents)
    // a recursive directory watch is supported, so one watch on `refs/`
    // catches every branch/tag/remote ref at any nesting depth. On Linux
    // inotify has no native recursion, so we emulate it (see
    // [_watchTreeEmulatingRecursion]): watch `refs/` and every directory
    // beneath it, adding a watch for each subdirectory as it is created.
    // That closes the nested-namespace gap — a branch named `feature/foo`
    // lives in `refs/heads/feature/foo`, and once the `feature/` subdir
    // exists, later siblings created under it are seen just like top-level
    // refs, not missed until the next `git pack-refs`.
    _refsDir = p.join(commonDir, 'refs');
    if (!debugSkipInitialRefsWatch) _installRefsWatch();

    // A linked worktree keeps its own HEAD in the per-worktree git dir,
    // which differs from the common dir. Watch it so a checkout in this
    // desk is seen even though it never touches the common dir's HEAD.
    if (!_samePath(gitDir, commonDir)) {
      _watch(gitDir, recursive: false, accept: _isHeadFile);
    }
  }

  /// Stop firing the callback. Events that arrive while paused are NOT
  /// dropped — they collapse into a single pending flag that [resume]
  /// turns into one debounced fire. Use around bulk app-initiated
  /// operations: N ref writes coalesce into one trailing refresh instead
  /// of N, and an external change that happens to land mid-operation is
  /// still surfaced rather than silently lost (dropping would make "a
  /// flow forgot to refresh after itself" an invisible stale-state bug).
  void pause() {
    _paused = true;
    // A pending debounce means events already arrived and never fired —
    // carry them into the paused-pending flag instead of losing them.
    if (_debounceTimer != null) _pendingWhilePaused = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Resume reacting to events. Anything that arrived while paused fires
  /// exactly once (debounced), no matter how many raw events it was.
  void resume() {
    _paused = false;
    if (_pendingWhilePaused) {
      _pendingWhilePaused = false;
      _scheduleFire();
    }
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
  }

  // ---- internals ------------------------------------------------------

  bool get _supportsRecursiveWatch => Platform.isWindows || Platform.isMacOS;

  /// The common dir's `refs/` path, resolved in [start]. Kept so the refs
  /// watch can be (re)installed lazily when the directory appears later.
  String? _refsDir;

  /// True once a refs watch is live. Guards against double-installing when
  /// the common-dir watch reports several events for the new `refs` dir.
  bool _refsWatchLive = false;

  /// Test seam: simulate the initial refs-watch establishment failing (a
  /// permissions error, a network FS hiccup). A live repo can't present
  /// this state from outside — git refuses to run at all without `refs/`,
  /// so [start]'s rev-parse would fail first — which is why the recovery
  /// path needs a hook to be exercised end-to-end at all.
  @visibleForTesting
  bool debugSkipInitialRefsWatch = false;

  bool _acceptAll(String _) => true;

  bool _isHeadFile(String basename) => basename == 'HEAD';

  bool _isCommonDirRefFile(String basename) =>
      basename == 'HEAD' || basename == 'packed-refs';

  /// Install the platform-appropriate watch on `refs/`, if it exists. A
  /// freshly-initialized or unusual repo can lack `refs/` entirely when
  /// [start] runs; then this is a no-op and [_onCommonDirEvent] retries the
  /// moment the directory is created, so loose-ref coverage recovers instead
  /// of staying dead for the watcher's lifetime.
  void _installRefsWatch() {
    final refsDir = _refsDir;
    if (_refsWatchLive || _disposed || refsDir == null) return;
    if (!Directory(refsDir).existsSync()) return;
    if (_supportsRecursiveWatch) {
      _refsWatchLive = _watch(refsDir, recursive: true, accept: _acceptAll);
    } else {
      _watchTreeEmulatingRecursion(refsDir);
      _refsWatchLive = true;
    }
  }

  /// Common-dir events: HEAD / packed-refs churn feeds the normal refresh
  /// path; anything touching a child named `refs` is additionally the cue
  /// to (re)install the refs watch when it wasn't available at [start].
  void _onCommonDirEvent(FileSystemEvent event) {
    if (!_refsWatchLive && p.basename(event.path) == 'refs') {
      _installRefsWatch();
      // The directory being born implies ref activity we may have missed
      // in the gap — fire a refresh rather than assume nothing changed.
      if (_refsWatchLive) _scheduleFire();
    }
    _onRawEvent(event, _isCommonDirRefFile);
  }

  /// Returns true when the subscription was established; false when the
  /// directory is missing or unwatchable (the caller may retry later, as
  /// [_installRefsWatch] does).
  bool _watch(
    String dir,
    {
    required bool recursive,
    required bool Function(String basename) accept,
    void Function(FileSystemEvent event)? onEvent,
  }) {
    try {
      // `Directory.watch` throws synchronously if the directory does not
      // exist (e.g. a repo with no `refs/tags` yet) or the platform can't
      // watch it; a subscription can still error later. Both are inert.
      final stream = Directory(dir).watch(recursive: recursive);
      final sub = stream.listen(
        onEvent ?? (event) => _onRawEvent(event, accept),
        onError: (_) {},
        cancelOnError: false,
      );
      _subs.add(sub);
      return true;
    } catch (_) {
      // Degrade silently — this watch simply won't contribute events.
      return false;
    }
  }

  /// Emulate a recursive directory watch where the platform's native
  /// watcher (Linux inotify) only reports a directory's direct children.
  /// Watches [root] and every directory currently beneath it, then — because
  /// inotify does not descend into directories created after a watch is
  /// installed — adds a watch for each new subdirectory as it appears. Every
  /// watch feeds the same accept-all ref filter and is registered in [_subs],
  /// so [dispose] tears the whole tree of watches down.
  void _watchTreeEmulatingRecursion(String root) {
    _watchDirEmulated(root);
    try {
      for (final entity
          in Directory(root).listSync(recursive: true, followLinks: false)) {
        if (entity is Directory) _watchDirEmulated(entity.path);
      }
    } catch (_) {
      // The tree may be shallow or absent yet (a repo with no ref subdirs);
      // the root watch still covers whatever appears at the top level, and
      // new subdirectories get watched as their create events arrive.
    }
  }

  void _watchDirEmulated(String dir) {
    try {
      final stream = Directory(dir).watch(recursive: false);
      final sub = stream.listen(
        (event) {
          _onRawEvent(event, _acceptAll);
          // A subdirectory born after this watch was installed needs its own
          // watch — inotify won't descend into it for us. The create event
          // already scheduled a refresh, so a ref written before this watch
          // lands is still reflected by that fire; the new watch then catches
          // that subdir's later siblings.
          if (event is FileSystemCreateEvent && event.isDirectory) {
            _watchDirEmulated(event.path);
          }
        },
        onError: (_) {},
        cancelOnError: false,
      );
      _subs.add(sub);
    } catch (_) {
      // Degrade silently — this directory simply won't contribute events.
    }
  }

  void _onRawEvent(FileSystemEvent event, bool Function(String) accept) {
    if (_disposed) return;
    // A rename carries TWO names, and git's atomic-write pattern puts the
    // watched one on the DESTINATION side (`HEAD.lock` → `HEAD` on checkout).
    // Linux inotify surfaces that as one move event whose `path` is the
    // .lock source, so filtering on `path` alone made checkouts invisible to
    // the watcher on Linux (Windows delivers per-name events and passed).
    final touchesWatched = accept(p.basename(event.path)) ||
        (event is FileSystemMoveEvent &&
            event.destination != null &&
            accept(p.basename(event.destination!)));
    if (!touchesWatched) return;
    if (_paused) {
      _pendingWhilePaused = true;
      return;
    }
    _scheduleFire();
  }

  void _scheduleFire() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      if (_disposed || _paused) return;
      onRepoChanged();
    });
  }

  /// Returns `(gitDir, commonDir)` as absolute paths, or null on failure.
  /// For the main worktree the two are equal; for a linked worktree the
  /// git dir is `.../.git/worktrees/<name>` while the common dir is the
  /// shared `.../.git`.
  Future<(String, String)?> _resolveGitDirs() async {
    try {
      final result = await git.runGit(
        repoPath,
        const [
          'rev-parse',
          '--path-format=absolute',
          '--git-dir',
          '--git-common-dir',
        ],
      );
      if (result.exitCode != 0) return null;
      final lines = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.length < 2) return null;
      return (lines[0], lines[1]);
    } catch (_) {
      return null;
    }
  }

  bool _samePath(String a, String b) {
    String norm(String s) {
      final n = p.normalize(s).replaceAll('\\', '/');
      return Platform.isLinux ? n : n.toLowerCase();
    }

    return norm(a) == norm(b);
  }
}
