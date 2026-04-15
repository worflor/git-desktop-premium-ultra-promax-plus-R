import 'package:flutter/foundation.dart';

import '../backend/file_coupling.dart';
import '../backend/git.dart';

/// Owns the co-change matrix per repo, cached by HEAD hash.
/// Unlike RepositoryXrayState this one is background-only: UI never waits on
/// it. If the matrix isn't ready yet the changes list renders without
/// cluster stripes; a notify on load fades them in.
class FileCouplingState extends ChangeNotifier {
  final Map<String, FileCouplingMatrix> _matrixByRepo = {};
  final Set<String> _loading = {};
  final Map<String, String?> _errors = {};

  FileCouplingMatrix? matrixFor(String repoPath) => _matrixByRepo[repoPath];

  bool isLoading(String repoPath) => _loading.contains(repoPath);

  String? errorFor(String repoPath) => _errors[repoPath];

  void invalidateAllExcept(String? repoPath) {
    if (repoPath == null) {
      _matrixByRepo.clear();
      _loading.clear();
      _errors.clear();
      notifyListeners();
      return;
    }
    final hadOthers = _matrixByRepo.keys.any((k) => k != repoPath) ||
        _loading.any((k) => k != repoPath);
    _matrixByRepo.removeWhere((k, _) => k != repoPath);
    _loading.removeWhere((k) => k != repoPath);
    _errors.removeWhere((k, _) => k != repoPath);
    if (hadOthers) notifyListeners();
  }

  /// Kick off a compute. If the cached matrix is still fresh (same HEAD),
  /// this is a no-op and returns immediately.
  Future<void> loadForRepo(String repoPath, {bool forceRefresh = false}) async {
    if (_loading.contains(repoPath)) return;

    final cached = _matrixByRepo[repoPath];
    if (!forceRefresh && cached != null) {
      // Cheap staleness check — same HEAD? then skip the expensive log pass.
      // One rev-parse is ~10ms; avoids recomputing the whole matrix on every
      // page visit when nothing has changed.
      try {
        final head = await runGitProbe(repoPath, ['rev-parse', 'HEAD']);
        if (head.exitCode == 0 &&
            head.stdout.toString().trim() == cached.headHash) {
          return;
        }
      } catch (_) {
        // Fall through: recompute if we can't verify.
      }
    }

    _loading.add(repoPath);
    _errors.remove(repoPath);
    notifyListeners();

    try {
      final result = await computeFileCoupling(repoPath);
      if (result.ok && result.data != null) {
        _matrixByRepo[repoPath] = result.data!;
        _errors.remove(repoPath);
      } else {
        _errors[repoPath] = result.error ?? 'failed to compute coupling';
      }
    } catch (e) {
      _errors[repoPath] = e.toString();
    } finally {
      _loading.remove(repoPath);
      notifyListeners();
    }
  }

  /// Drop any cached matrix for this repo so the next [loadForRepo] recomputes.
  /// Called when HEAD advances (new commit, checkout, etc.).
  void invalidateRepo(String repoPath) {
    if (_matrixByRepo.remove(repoPath) != null) {
      notifyListeners();
    }
  }
}
