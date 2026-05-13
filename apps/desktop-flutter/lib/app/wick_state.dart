import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../backend/git.dart' show ensureManifoldExcluded;
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
  String _customPath = '';
  final Map<String, WickRepoState> _repos = {};
  String? _activeRepoPath;
  final _queryHandle = WickQueryHandle();

  bool get available => _detected && _available;
  bool get detected => _detected;
  String get customPath => _customPath;

  WickRepoState? stateFor(String repoPath) => _repos[repoPath];

  void cancelActiveQuery() => _queryHandle.cancel();

  String? get _cp => _customPath.isEmpty ? null : _customPath;

  void setActiveRepo(String? repoPath) {
    _activeRepoPath = repoPath;
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
        if (_available && _activeRepoPath != null) {
          unawaited(indexRepo(_activeRepoPath!));
        }
      }());
    } else {
      _detected = true;
      notifyListeners();
    }
  }

  Future<void> detectWick() async {
    _available = await isWickInstalled(customPath: _cp);
    _detected = true;
    notifyListeners();
    if (_available && _activeRepoPath != null) {
      unawaited(indexRepo(_activeRepoPath!));
    }
  }

  Future<void> indexRepo(String repoPath) async {
    if (!_available) return;
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
    if (!_available) return null;
    final state = _repos[repoPath];
    if (state == null || !state.indexed) return null;
    final result = await wickQuery(repoPath, q, customPath: _cp, handle: _queryHandle);
    if (!result.ok) return null;
    return result.data;
  }

  Future<String?> _currentHead(String repoPath) async {
    try {
      final r = await Process.run(
        'git', ['rev-parse', 'HEAD'],
        workingDirectory: repoPath,
      );
      if (r.exitCode == 0) return (r.stdout as String).trim();
    } catch (_) {}
    return null;
  }
}
