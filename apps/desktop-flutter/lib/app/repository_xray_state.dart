import 'package:flutter/foundation.dart';

import '../backend/dtos.dart';
import '../backend/git.dart';

class RepositoryXrayState extends ChangeNotifier {
  final Map<String, RepositoryXraySnapshotData> _snapshots = {};
  final Map<String, String> _fingerprints = {};
  final Map<String, DateTime> _computedAt = {};
  final Map<String, String?> _errors = {};
  final Set<String> _loading = {};

  RepositoryXraySnapshotData? snapshotFor(String repoPath) =>
      _snapshots[repoPath];

  String? errorFor(String repoPath) => _errors[repoPath];

  bool isLoading(String repoPath) => _loading.contains(repoPath);

  DateTime? computedAtFor(String repoPath) => _computedAt[repoPath];

  void invalidateAllExcept(String? repoPath) {
    if (repoPath == null) {
      _snapshots.clear();
      _fingerprints.clear();
      _computedAt.clear();
      _errors.clear();
      _loading.clear();
      notifyListeners();
      return;
    }

    final removedAny = _snapshots.keys.any((key) => key != repoPath) ||
        _fingerprints.keys.any((key) => key != repoPath) ||
        _errors.keys.any((key) => key != repoPath) ||
        _loading.any((key) => key != repoPath);
    _snapshots.removeWhere((key, _) => key != repoPath);
    _fingerprints.removeWhere((key, _) => key != repoPath);
    _computedAt.removeWhere((key, _) => key != repoPath);
    _errors.removeWhere((key, _) => key != repoPath);
    _loading.removeWhere((key) => key != repoPath);
    if (removedAny) {
      notifyListeners();
    }
  }

  Future<void> loadForRepo(String repoPath, {bool forceRefresh = false}) async {
    if (_loading.contains(repoPath)) {
      return;
    }

    if (!forceRefresh && _snapshots.containsKey(repoPath)) {
      final fingerprintResult = await getRepositoryXrayFingerprint(repoPath);
      if (fingerprintResult.ok &&
          fingerprintResult.data != null &&
          _fingerprints[repoPath] == fingerprintResult.data) {
        return;
      }
    }

    _loading.add(repoPath);
    _errors[repoPath] = null;
    notifyListeners();

    try {
      final result = await getRepositoryXray(repoPath, forceRefresh: forceRefresh);
      if (result.ok && result.data != null) {
        _snapshots[repoPath] = result.data!;
        _fingerprints[repoPath] = result.data!.header.fingerprint;
        final parsedComputedAt =
            DateTime.tryParse(result.data!.header.computedAt);
        if (parsedComputedAt != null) {
          _computedAt[repoPath] = parsedComputedAt;
        }
        _errors.remove(repoPath);
      } else {
        _errors[repoPath] = result.error ?? 'Failed to compute Repo X-Ray.';
      }
    } catch (error) {
      _errors[repoPath] = error.toString();
    } finally {
      _loading.remove(repoPath);
      notifyListeners();
    }
  }
}
