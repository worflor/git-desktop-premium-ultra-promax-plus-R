import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../backend/git.dart' show ensureManifoldExcluded;
import '../backend/repo_head_cache.dart';
import '../backend/wick.dart';

class WickRepoState {
  bool indexing = false;
  bool indexed = false;
  String? indexError;
  String? lastIndexedHead;
}

class WickState extends ChangeNotifier {
  bool _available = false;
  bool _detected = false;
  bool _enabled = true;
  String _customPath = '';
  final Map<String, WickRepoState> _repos = {};
  String? _activeRepoPath;
  final _queryHandle = WickQueryHandle();

  /// The ONE gate. Every path that spends CPU on wick — indexing, querying,
  /// and the UI's live state — reads this, so disabling the integration
  /// cannot leave work running behind a stale check.
  bool get available => _enabled && _detected && _available;
  bool get detected => _detected;

  /// User's hard on/off for the integration. Off = the wick binary is never
  /// invoked, regardless of whether it is installed and detected.
  bool get enabled => _enabled;
  String get customPath => _customPath;

  WickRepoState? stateFor(String repoPath) => _repos[repoPath];

  void cancelActiveQuery() => _queryHandle.cancel();

  String? get _cp => _customPath.isEmpty ? null : _customPath;

  void setActiveRepo(String? repoPath) {
    _activeRepoPath = repoPath;
  }

  /// Restore persisted settings at startup. Sets the fields with no side
  /// effects, then probes ONLY when enabled — a disabled integration must
  /// not spawn so much as a detection probe. The path is stored either way,
  /// so a later enable probes the configured binary, not a bare PATH lookup.
  void restore({required String path, required bool enabled}) {
    _customPath = path;
    _enabled = enabled;
    if (!enabled) {
      _detected = false;
      _available = false;
      notifyListeners();
      return;
    }
    unawaited(detectWick());
  }

  /// Flip the integration on/off. Turning it off cancels any in-flight query
  /// and drops per-repo index state, so nothing is left mid-flight and a
  /// re-enable re-indexes from a clean slate.
  void setEnabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (!value) {
      _queryHandle.cancel();
      _repos.clear();
      notifyListeners();
      return;
    }
    notifyListeners();
    unawaited(() async {
      if (!_detected) await detectWick();
      if (available && _activeRepoPath != null) {
        unawaited(indexRepo(_activeRepoPath!));
      }
    }());
  }

  void setCustomPath(String path) {
    if (path == _customPath) return;
    _customPath = path;
    _detected = false;
    _available = false;
    _repos.clear();
    notifyListeners();
    if (path.isNotEmpty) {
      unawaited(() async {
        await detectWick();
        if (available && _activeRepoPath != null) {
          unawaited(indexRepo(_activeRepoPath!));
        }
      }());
    } else {
      _detected = true;
      notifyListeners();
    }
  }

  Future<void> detectWick() async {
    // The enabled gate lives HERE, at the single detection chokepoint, not in
    // each caller. A disabled integration must never spawn the wick binary,
    // and isWickInstalled below does exactly that — so any path in
    // (setCustomPath, restore, setEnabled, future callers) is gated once and
    // a probe-while-disabled is unrepresentable. Callers that flip the
    // integration on set _enabled BEFORE calling in, so enabling still probes.
    if (!_enabled) return;
    _available = await isWickInstalled(customPath: _cp);
    _detected = true;
    notifyListeners();
    if (available && _activeRepoPath != null) {
      unawaited(indexRepo(_activeRepoPath!));
    }
  }

  Future<void> indexRepo(String repoPath) async {
    if (!available) return;
    final state = _repos.putIfAbsent(repoPath, WickRepoState.new);
    if (state.indexing) return;
    state.indexing = true;

    final head = await _currentHead(repoPath);
    if (state.indexed && state.lastIndexedHead == head) {
      state.indexing = false;
      return;
    }
    notifyListeners();

    final dbFile = File(wickDbPath(repoPath));
    if (await dbFile.exists() && !state.indexed) {
      state.indexed = true;
      state.lastIndexedHead = head;
      notifyListeners();
    }

    await ensureManifoldExcluded(repoPath);
    // Re-check across the awaits: the user can disable the integration while
    // this is still deciding, and spawning the indexer after that is exactly
    // the CPU the toggle exists to stop.
    if (!available) {
      state.indexing = false;
      return;
    }
    final result = await wickIndex(repoPath, customPath: _cp);

    state.indexing = false;
    if (result.ok) {
      state.indexed = true;
      state.indexError = null;
      state.lastIndexedHead = head;
    } else {
      state.indexError = result.error;
      if (!await dbFile.exists()) state.indexed = false;
    }
    notifyListeners();
  }

  Future<WickQueryResponse?> query(String repoPath, String q) async {
    if (!available) return null;
    final state = _repos[repoPath];
    if (state == null || !state.indexed) return null;
    final result = await wickQuery(repoPath, q, customPath: _cp, handle: _queryHandle);
    if (!result.ok) return null;
    return result.data;
  }

  Future<String?> _currentHead(String repoPath) =>
      RepoHeadCache.instance.head(repoPath);
}
