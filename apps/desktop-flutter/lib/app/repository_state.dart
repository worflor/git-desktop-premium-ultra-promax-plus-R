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
    final result = await openRepository(path);
    if (!result.ok) return result.error;

    _activePath = path;
    _status = null;
    _statusError = null;

    if (!_recentPaths.contains(path)) {
      _recentPaths = [path, ..._recentPaths].take(20).toList();
      await _saveRecents();
    }

    notifyListeners();
    await refreshStatus();
    return null;
  }

  Future<void> refreshStatus() async {
    final path = _activePath;
    if (path == null) return;

    _statusLoading = true;
    _statusError = null;
    notifyListeners();

    final result = await getRepositoryStatus(path);
    _statusLoading = false;
    if (result.ok) {
      _status = result.data;
      _statusError = null;
    } else {
      _statusError = result.error;
    }
    notifyListeners();
  }
}
