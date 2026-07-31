// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../backend/analysis_admission.dart';
import '../backend/git.dart';
import '../backend/dtos.dart';
import '../backend/git_result.dart';
import '../backend/git_dir_watcher.dart';

class RepositoryState extends ChangeNotifier {
  RepositoryState({
    Future<GitResult<String>> Function(String path)? openRepositoryFn,
    Future<GitResult<RepositoryStatus>> Function(String path)? statusLoader,
    Duration switchDebounce = const Duration(milliseconds: 80),
    GitDirWatcher Function(String repoPath, void Function() onRepoChanged)?
    gitWatcherFactory,
    Duration externalRefreshThrottle = const Duration(milliseconds: 1500),
  }) : _openRepository = openRepositoryFn ?? openRepository,
       _loadRepositoryStatus = statusLoader ?? getRepositoryStatus,
       _switchDebounceDuration = switchDebounce,
       _gitWatcherFactory =
           gitWatcherFactory ??
           ((path, onChanged) => GitDirWatcher(path, onChanged)),
       _externalRefreshThrottle = externalRefreshThrottle {
    // Pause the .git watcher while the app itself is mutating the repo
    // (any in-flight mutating git subprocess via the shared exec layer).
    // Our own commit/merge/checkout ref churn then coalesces into ONE
    // post-operation watcher fire instead of racing the operation with
    // per-write refreshes; nothing is dropped — the watcher remembers
    // paused-time events and fires once on resume.
    addGitMutationListener(_onGitMutationsChanged);
  }

  final Future<GitResult<String>> Function(String path) _openRepository;
  final Future<GitResult<RepositoryStatus>> Function(String path)
  _loadRepositoryStatus;
  final Duration _switchDebounceDuration;

  /// Builds the `.git` watcher for the active repo. Injectable so tests
  /// can drive the coalesced-change callback without a real filesystem
  /// watch; production builds a real [GitDirWatcher].
  final GitDirWatcher Function(String repoPath, void Function() onRepoChanged)
  _gitWatcherFactory;

  /// Minimum spacing between refreshes triggered by *external* `.git`
  /// mutations. The watcher already debounces raw events into one
  /// coalesced callback, but a stream of distinct external changes
  /// (someone fetching in a loop, a long rebase) must not spam the heavy
  /// downstream recompute chain. This throttle fires leading-edge and
  /// guarantees one trailing refresh so the final state is never missed.
  final Duration _externalRefreshThrottle;

  String? _activePath;
  RepositoryStatus? _status;
  bool _statusLoading = false;
  String? _statusError;
  List<String> _recentPaths = [];
  int _statusRequestId = 0;
  Timer? _statusLoadingPublish;
  Timer? _switchDebounce;
  Completer<String?>? _switchCompleter;
  bool _disposed = false;

  /// The `.git` watcher for the active repo, recreated on every repo
  /// switch and disposed with the old one. Null before the first repo
  /// opens (and whenever a switch is still resolving).
  GitDirWatcher? _gitWatcher;
  Timer? _externalRefreshTimer;
  DateTime? _lastExternalRefresh;

  /// Threshold before a loading state is published. Most `git status`
  /// probes complete in a few ms on a warm repo; publishing
  /// `_statusLoading = true` immediately would flash a spinner in
  /// every consumer on each refresh. This delay folds the common
  /// fast-path down to a single `notifyListeners()` (data only), while
  /// still surfacing a spinner on legitimately slow probes.
  static const Duration _loadingPublishDelay = Duration(milliseconds: 120);

  /// Monotonically increasing counter bumped whenever the user takes
  /// an explicit "show me what's new" action — a refresh button tap,
  /// a pull, etc. Implicit internal refreshes (post-staging reloads,
  /// automatic reconciliation) do NOT bump it, so consumers that want
  /// to draw a before/after boundary on deliberate user attention
  /// events (e.g. dimming files that have persisted unchanged across
  /// an explicit refresh) have a clean signal to key on.
  int _userRefreshEpoch = 0;

  /// Bumped on every `setActivePath` completion — including same-path
  /// re-activations. Consumers that need to reset drill state when
  /// the user intentionally re-selects a repo (e.g. clicking the
  /// sidebar on the already-active project) watch this counter.
  int _activationEpoch = 0;

  /// Monotonic counter bumped on EVERY [_status] assignment (data, null,
  /// clear). Status codes alone are too coarse an identity for cached
  /// derivations: a file edited again stays `M`, so any cache keyed only on
  /// path|status serves the previous edit's parse. Every status snapshot is
  /// driven by a real change signal (GitDirWatcher, post-mutation reload,
  /// explicit refresh), so folding this revision into a cache key makes
  /// "content changed underneath the cached view" unrepresentable — the key
  /// can't survive the refresh the change itself triggered.
  int _statusRevision = 0;

  String? get activePath => _activePath;
  int get activationEpoch => _activationEpoch;
  int get statusRevision => _statusRevision;
  RepositoryStatus? get status => _status;
  bool get statusLoading => _statusLoading;
  String? get statusError => _statusError;
  List<String> get recentPaths => _recentPaths;
  int get userRefreshEpoch => _userRefreshEpoch;

  String? get activeRepoName {
    final p = _activePath;
    if (p == null) return null;
    final parts = p
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isNotEmpty ? parts.last : p;
  }

  Future<void> loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('recent_repos') ?? [];
    // Purge any Manifold-managed worktree paths that leaked into recents
    // before desk switches stopped touching the list. Worktrees are not
    // distinct projects — they're desks of their parent repo.
    // Collapse the same repository stored under two spellings. One list can
    // legitimately hold both `C:\Users\...` (from the picker) and
    // `C:/Users/...` (derived from git's own output), and they name one
    // project. Runs here as well as at the write gate so a list that already
    // grew a duplicate heals on load rather than showing it forever.
    final seen = <String>{};
    final cleaned = stored
        .where(
          (path) =>
              !path.replaceAll('\\', '/').contains('/.manifold/worktrees/'),
        )
        .where((path) => seen.add(p.canonicalize(p.normalize(path))))
        .map(p.normalize)
        .toList();
    _recentPaths = cleaned;
    if (cleaned.length != stored.length) {
      // Persist the purge so the migration only runs once.
      await _saveRecents();
    }
    notifyListeners();
  }

  /// Add a path to the recents list without otherwise changing the repo
  /// session — no active-repo switch, no analysis-scope bump.
  ///
  /// The inverse of [forgetRecent], and deliberately NOT [setActivePath]:
  /// registering a repo from the CLI must not yank the window the user is
  /// looking at over to a different project, and must not bump
  /// `repoAnalysisScope` (which would supersede analysis already queued for
  /// whatever they actually have open).
  ///
  /// Whether [path] names a repository already in the recents list.
  ///
  /// The single authority for that question, canonically rather than by
  /// string equality — the same repo arrives spelled `C:\Users\...` from the
  /// picker and `C:/Users/...` from git's own output. Callers must not
  /// re-implement this with `recentPaths.contains`: doing so is what let a
  /// repo be reported "new" by one code path and stored as a duplicate by
  /// another.
  bool knowsRecent(String path) {
    if (path.isEmpty) return false;
    final key = p.canonicalize(p.normalize(path));
    return _recentPaths.any((existing) => p.canonicalize(existing) == key);
  }

  /// Returns true when the path was newly added, false when already known.
  ///
  /// "Already known" is decided CANONICALLY, not by string equality. The same
  /// repository reaches this from two directions with two spellings: the
  /// picker hands over a native `C:\Users\...`, while a path derived from
  /// git's own output (`rev-parse --git-common-dir`) comes back with forward
  /// slashes. Compared literally those are different strings, and the project
  /// list grows a second entry for a repo it already had — observed the first
  /// time `manifold index` ran against a repo the window was already open on.
  Future<bool> rememberRecent(String path) async {
    if (_disposed || path.isEmpty || knowsRecent(path)) return false;
    _recentPaths = [p.normalize(path), ..._recentPaths].take(20).toList();
    await _saveRecents();
    notifyListeners();
    return true;
  }

  /// Remove a path from the recents list without otherwise changing the
  /// repo session. Used by the sidebar's per-project "forget" action.
  Future<void> forgetRecent(String path) async {
    final before = _recentPaths.length;
    _recentPaths = _recentPaths.where((p) => p != path).toList();
    if (_recentPaths.length != before) {
      await _saveRecents();
      notifyListeners();
    }
  }

  Future<void> _saveRecents([List<String>? paths]) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_repos', paths ?? _recentPaths);
  }

  /// Opens a repository path as the active repo.
  /// [addToRecents] controls whether the path is tracked in the recent
  /// repositories sidebar. Worktree ("desk") switches within the same repo
  /// pass `false` so individual desks don't clutter the project list —
  /// only the primary worktree gets added on initial open.
  ///
  /// Rapid successive calls (user spam-clicking repos) are debounced:
  /// only the last path wins. Intermediate calls resolve with null
  /// (success) without spawning any git work.
  Future<String?> setActivePath(String path, {bool addToRecents = true}) {
    if (_disposed) return Future.value(null);
    _switchDebounce?.cancel();
    final prev = _switchCompleter;
    final completer = Completer<String?>();
    _switchCompleter = completer;
    // Complete the superseded caller as success — it never ran, but
    // from the caller's perspective the switch was overtaken, not failed.
    if (prev != null && !prev.isCompleted) prev.complete(null);

    _switchDebounce = Timer(_switchDebounceDuration, () {
      _doSetActivePath(
        path,
        addToRecents: addToRecents,
        switchCompleter: completer,
      ).then(
        (value) {
          if (!completer.isCompleted) {
            completer.complete(value);
          }
          if (identical(_switchCompleter, completer)) {
            _switchCompleter = null;
          }
        },
        onError: (Object e) {
          if (!completer.isCompleted) {
            completer.complete(e.toString());
          }
          if (identical(_switchCompleter, completer)) {
            _switchCompleter = null;
          }
        },
      );
    });
    return completer.future;
  }

  Future<String?> _doSetActivePath(
    String path, {
    required bool addToRecents,
    required Completer<String?> switchCompleter,
  }) async {
    try {
      final result = await _openRepository(path);
      // If another switch arrived while we awaited, bail.
      if (_switchWasSuperseded(switchCompleter)) return null;
      if (!result.ok || result.data == null) {
        return result.error ?? 'Failed to open repository.';
      }

      final resolvedPath = result.data!;
      final nextRecentPaths =
          addToRecents && !_recentPaths.contains(resolvedPath)
          ? [resolvedPath, ..._recentPaths].take(20).toList()
          : null;

      if (nextRecentPaths != null) {
        await _saveRecents(nextRecentPaths);
        if (_switchWasSuperseded(switchCompleter)) return null;
      }

      _activePath = resolvedPath;
      _status = null;
      _statusRevision++;
      _statusLoading = false;
      _statusError = null;
      _activationEpoch++;
      // Drop analysis still QUEUED for the previous repo before it reads a
      // byte (running work drains under the admission budget). Without this,
      // a switch away from a heavy repo stacked its pending reads on top of
      // the new repo's pipeline spin-up.
      repoAnalysisScope.bump();
      if (nextRecentPaths != null) {
        _recentPaths = nextRecentPaths;
      }

      _rebuildGitWatcher(resolvedPath);

      notifyListeners();
      await refreshStatus();

      return null;
    } catch (error) {
      return error.toString();
    }
  }

  /// Tear down the watcher for the previous repo and stand one up for
  /// [resolvedPath]. The old watcher is disposed so its subscriptions and
  /// debounce timer are released; the external-refresh throttle is reset
  /// so the new repo starts with a clean leading edge. A watch that can't
  /// be established (permissions, network FS, non-repo path) degrades to
  /// inert inside [GitDirWatcher.start] — the app is unaffected.
  void _rebuildGitWatcher(String resolvedPath) {
    _gitWatcher?.dispose();
    _externalRefreshTimer?.cancel();
    _externalRefreshTimer = null;
    _lastExternalRefresh = null;
    final watcher = _gitWatcherFactory(resolvedPath, _onExternalRepoChange);
    _gitWatcher = watcher;
    // A watcher born mid-mutation must start paused — the listener only
    // fires on transitions, so the current state is applied here.
    if (gitMutationsInFlight > 0) watcher.pause();
    // start() is async and self-guards against a dispose that lands while
    // it resolves the git dirs; we deliberately don't await it here so the
    // repo switch isn't blocked on spawning `git rev-parse`.
    unawaited(watcher.start());
  }

  /// Pause/resume the watcher as the app's own mutating git subprocesses
  /// start and drain (see the constructor comment). Trivial by contract —
  /// this runs synchronously inside the git exec path.
  void _onGitMutationsChanged() {
    if (_disposed) return;
    final w = _gitWatcher;
    if (w == null) return;
    if (gitMutationsInFlight > 0) {
      w.pause();
    } else {
      w.resume();
    }
  }

  /// Coalesced "the `.git` changed under us" signal from [GitDirWatcher].
  /// Runs the same status-refresh path a manual refresh uses (so all
  /// listeners — including WorktreeState, which re-lists on our
  /// notifications behind its own throttle — fan out), but throttled:
  /// external churn can arrive faster than a status probe and its
  /// downstream recompute chain should run. This is NOT a user-attention
  /// event, so it deliberately does not bump [userRefreshEpoch].
  void _onExternalRepoChange() {
    if (_disposed) return;
    final now = DateTime.now();
    final last = _lastExternalRefresh;
    if (last == null || now.difference(last) >= _externalRefreshThrottle) {
      _lastExternalRefresh = now;
      refreshStatus();
      return;
    }
    // Inside the cooldown: schedule a single trailing refresh so the
    // final external state is never dropped, and coalesce further changes
    // into that one pending run.
    if (_externalRefreshTimer != null) return;
    final wait = _externalRefreshThrottle - now.difference(last);
    _externalRefreshTimer = Timer(wait, () {
      _externalRefreshTimer = null;
      if (_disposed) return;
      _lastExternalRefresh = DateTime.now();
      refreshStatus();
    });
  }

  bool _switchWasSuperseded(Completer<String?> completer) {
    return _disposed ||
        completer.isCompleted ||
        !identical(_switchCompleter, completer);
  }

  /// Bump [userRefreshEpoch] then run [refreshStatus]. Call this from
  /// user-facing refresh affordances (repo title refresh icon, manual
  /// refresh shortcuts, post-pull flows) so listeners that distinguish
  /// explicit-attention events from background reconciliations see a
  /// single authoritative tick. Internal callers that are merely
  /// reconciling after their own side-effect (e.g. post-staging)
  /// should continue to call [refreshStatus] directly — their work
  /// isn't a "show me what's new" signal from the user.
  Future<void> userRefresh() {
    if (_disposed) return Future.value();
    _userRefreshEpoch++;
    // Notify listeners synchronously so UI subscribers can observe the
    // epoch change before the async status probe lands. That ordering
    // matters for consumers that snapshot state on epoch change.
    notifyListeners();
    return refreshStatus();
  }

  /// True iff [path] is the active repo — so [status] currently reflects it.
  /// Async flows that mutate a SPECIFIC repo use this to decide whether the
  /// active [status]/[refreshStatus] is even about the repo they touched.
  bool isActive(String path) => !_disposed && _activePath == path;

  /// Refresh status only when [path] is still active. [refreshStatus] and
  /// [status] are single-slot, keyed to [activePath]; a long async flow
  /// (palette mutation, force-push confirm, stash conflict editor, the global
  /// undo pill) can mutate repo A while the user switches to repo B, and an
  /// unguarded refresh would then reload B — leaving A stale and masking B's
  /// real state. Skipping is safe: a switched-away repo re-reads its status
  /// when it becomes active again (setActivePath calls refreshStatus).
  Future<void> refreshStatusIfActive(String path) {
    if (!isActive(path)) return Future.value();
    return refreshStatus();
  }

  Future<void> refreshStatus() async {
    if (_disposed) return;
    final path = _activePath;
    if (path == null) return;
    final requestId = ++_statusRequestId;

    // Flip `_statusLoading` internally but don't broadcast yet — if
    // the probe resolves within [_loadingPublishDelay], consumers
    // never see the transient loading state and the whole refresh
    // collapses into a single `notifyListeners()`. Previously the
    // loading flip fired on every tick and caused every widget
    // subscribed to `RepositoryState` to rebuild twice per refresh.
    _statusLoading = true;
    _statusError = null;
    _statusLoadingPublish?.cancel();
    _statusLoadingPublish = Timer(_loadingPublishDelay, () {
      _statusLoadingPublish = null;
      if (_disposed) return;
      if (_activePath != path || requestId != _statusRequestId) return;
      if (!_statusLoading) return; // already resolved — no spinner
      notifyListeners();
    });

    try {
      final result = await _loadRepositoryStatus(path);
      if (_disposed || _activePath != path || requestId != _statusRequestId) {
        return;
      }
      _statusLoading = false;
      if (result.ok) {
        _status = result.data;
        _statusRevision++;
        _statusError = null;
      } else {
        _status = null;
        _statusRevision++;
        _statusError = result.error;
      }
    } catch (error) {
      if (_disposed || _activePath != path || requestId != _statusRequestId) {
        return;
      }
      _statusLoading = false;
      _status = null;
      _statusRevision++;
      _statusError = error.toString();
    }
    // Cancel the pending loading-publish: if we beat the threshold
    // this is the ONLY notify consumers see; otherwise it's the
    // second (data-arrived) notify and the timer already fired once.
    _statusLoadingPublish?.cancel();
    _statusLoadingPublish = null;
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    removeGitMutationListener(_onGitMutationsChanged);
    _statusRequestId++;
    _switchDebounce?.cancel();
    _switchDebounce = null;
    final pendingSwitch = _switchCompleter;
    _switchCompleter = null;
    if (pendingSwitch != null && !pendingSwitch.isCompleted) {
      pendingSwitch.complete(null);
    }
    _statusLoadingPublish?.cancel();
    _statusLoadingPublish = null;
    _statusLoading = false;
    _gitWatcher?.dispose();
    _gitWatcher = null;
    _externalRefreshTimer?.cancel();
    _externalRefreshTimer = null;
    super.dispose();
  }
}
