import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../backend/git.dart';
import '../backend/dtos.dart';

class RepositoryState extends ChangeNotifier {
  String? _activePath;
  RepositoryStatus? _status;
  bool _statusLoading = false;
  String? _statusError;
  List<String> _recentPaths = [];
  int _statusRequestId = 0;
  Timer? _statusLoadingPublish;

  /// Threshold before a loading state is published. Most `git status`
  /// probes complete in a few ms on a warm repo; publishing
  /// `_statusLoading = true` immediately would flash a spinner in
  /// every consumer on each refresh. This delay folds the common
  /// fast-path down to a single `notifyListeners()` (data only), while
  /// still surfacing a spinner on legitimately slow probes.
  static const Duration _loadingPublishDelay = Duration(milliseconds: 120);

  String? get activePath => _activePath;
  RepositoryStatus? get status => _status;
  bool get statusLoading => _statusLoading;
  String? get statusError => _statusError;
  List<String> get recentPaths => _recentPaths;

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

  Future<void> _saveRecents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_repos', _recentPaths);
  }

  /// Opens a repository path as the active repo.
  /// [addToRecents] controls whether the path is tracked in the recent
  /// repositories sidebar. Worktree ("desk") switches within the same repo
  /// pass `false` so individual desks don't clutter the project list —
  /// only the primary worktree gets added on initial open.
  Future<String?> setActivePath(
    String path, {
    bool addToRecents = true,
  }) async {
    try {
      final result = await openRepository(path);
      if (!result.ok || result.data == null) {
        return result.error ?? 'Failed to open repository.';
      }

      final resolvedPath = result.data!;
      _activePath = resolvedPath;
      _status = null;
      _statusLoading = false;
      _statusError = null;

      if (addToRecents && !_recentPaths.contains(resolvedPath)) {
        _recentPaths = [resolvedPath, ..._recentPaths].take(20).toList();
        await _saveRecents();
      }

      notifyListeners();
      await refreshStatus();

      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<void> refreshStatus() async {
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
      if (_activePath != path || requestId != _statusRequestId) return;
      if (!_statusLoading) return; // already resolved — no spinner
      notifyListeners();
    });

    try {
      final result = await getRepositoryStatus(path);
      if (_activePath != path || requestId != _statusRequestId) {
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
      if (_activePath != path || requestId != _statusRequestId) {
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
    notifyListeners();
  }

  @override
  void dispose() {
    _statusLoadingPublish?.cancel();
    _statusLoadingPublish = null;
    // Clear the in-flight loading flag so any late observer that
    // reads state after dispose (possible when an ancestor provider
    // outlives its widget tree by a frame) sees a coherent "not
    // loading" state instead of a permanent spinner-trigger.
    _statusLoading = false;
    super.dispose();
  }
}
