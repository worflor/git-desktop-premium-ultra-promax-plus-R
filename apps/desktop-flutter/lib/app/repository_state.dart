import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../backend/git.dart';
import '../backend/dtos.dart';
import '../backend/git_result.dart';

class RepositoryState extends ChangeNotifier {
  RepositoryState({
    Future<GitResult<String>> Function(String path)? openRepositoryFn,
    Future<GitResult<RepositoryStatus>> Function(String path)? statusLoader,
    Duration switchDebounce = const Duration(milliseconds: 80),
  })  : _openRepository = openRepositoryFn ?? openRepository,
        _loadRepositoryStatus = statusLoader ?? getRepositoryStatus,
        _switchDebounceDuration = switchDebounce;

  final Future<GitResult<String>> Function(String path) _openRepository;
  final Future<GitResult<RepositoryStatus>> Function(String path)
      _loadRepositoryStatus;
  final Duration _switchDebounceDuration;

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

  String? get activePath => _activePath;
  RepositoryStatus? get status => _status;
  bool get statusLoading => _statusLoading;
  String? get statusError => _statusError;
  List<String> get recentPaths => _recentPaths;
  int get userRefreshEpoch => _userRefreshEpoch;

  String? get activeRepoName {
    final p = _activePath;
    if (p == null) return null;
    final parts =
        p.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.last : p;
  }

  Future<void> loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('recent_repos') ?? [];
    // Purge any Manifold-managed worktree paths that leaked into recents
    // before desk switches stopped touching the list. Worktrees are not
    // distinct projects — they're desks of their parent repo.
    final cleaned = stored
        .where(
            (p) => !p.replaceAll('\\', '/').contains('/.manifold/worktrees/'))
        .toList();
    _recentPaths = cleaned;
    if (cleaned.length != stored.length) {
      // Persist the purge so the migration only runs once.
      await _saveRecents();
    }
    notifyListeners();
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
  Future<String?> setActivePath(
    String path, {
    bool addToRecents = true,
  }) {
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
      _statusLoading = false;
      _statusError = null;
      if (nextRecentPaths != null) {
        _recentPaths = nextRecentPaths;
      }

      notifyListeners();
      await refreshStatus();

      return null;
    } catch (error) {
      return error.toString();
    }
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
        _statusError = null;
      } else {
        _status = null;
        _statusError = result.error;
      }
    } catch (error) {
      if (_disposed || _activePath != path || requestId != _statusRequestId) {
        return;
      }
      _statusLoading = false;
      _status = null;
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
    super.dispose();
  }
}
