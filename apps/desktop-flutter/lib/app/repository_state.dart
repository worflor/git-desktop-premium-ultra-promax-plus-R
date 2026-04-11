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
    _recentPaths = prefs.getStringList('recent_repos') ?? [];
    notifyListeners();
  }

  Future<void> _saveRecents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_repos', _recentPaths);
  }

  Future<String?> setActivePath(String path) async {
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

      if (!_recentPaths.contains(resolvedPath)) {
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

    _statusLoading = true;
    _statusError = null;
    notifyListeners();

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
    notifyListeners();
  }
}
