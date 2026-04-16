import 'package:flutter/foundation.dart';

import '../backend/file_coupling.dart';
import '../backend/git.dart';

/// Owns the corpus-wide identifier-frequency index per repo, cached by
/// HEAD hash. Background-only: UI never waits. Until the index is warm,
/// `computeSymbolCoupling` falls back to change-set-local IDF — correct
/// but less effective at suppressing language-specific stop-words.
/// Mirrors [FileCouplingState]'s shape so the provider tree treats it
/// the same way.
class SymbolFrequencyState extends ChangeNotifier {
  final Map<String, SymbolFrequencyIndex> _indexByRepo = {};
  final Set<String> _loading = {};
  final Map<String, String?> _errors = {};

  SymbolFrequencyIndex? indexFor(String repoPath) => _indexByRepo[repoPath];

  bool isLoading(String repoPath) => _loading.contains(repoPath);

  String? errorFor(String repoPath) => _errors[repoPath];

  void invalidateAllExcept(String? repoPath) {
    if (repoPath == null) {
      _indexByRepo.clear();
      _loading.clear();
      _errors.clear();
      notifyListeners();
      return;
    }
    final hadOthers = _indexByRepo.keys.any((k) => k != repoPath) ||
        _loading.any((k) => k != repoPath);
    _indexByRepo.removeWhere((k, _) => k != repoPath);
    _loading.removeWhere((k) => k != repoPath);
    _errors.removeWhere((k, _) => k != repoPath);
    if (hadOthers) notifyListeners();
  }

  /// Kick off a build. If the cached index is still fresh (same HEAD),
  /// this returns immediately. Expensive first run (full-repo scan); the
  /// rev-parse staleness check keeps subsequent loads cheap.
  Future<void> loadForRepo(String repoPath, {bool forceRefresh = false}) async {
    if (_loading.contains(repoPath)) return;

    final cached = _indexByRepo[repoPath];
    if (!forceRefresh && cached != null && cached.headHash.isNotEmpty) {
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
      final result = await computeSymbolFrequencyIndex(repoPath);
      if (result.ok && result.data != null) {
        _indexByRepo[repoPath] = result.data!;
        _errors.remove(repoPath);
      } else {
        _errors[repoPath] = result.error ?? 'failed to build corpus index';
      }
    } catch (e) {
      _errors[repoPath] = e.toString();
    } finally {
      _loading.remove(repoPath);
      notifyListeners();
    }
  }

  /// Drop any cached index for this repo so the next [loadForRepo] recomputes.
  /// Called when HEAD advances.
  void invalidateRepo(String repoPath) {
    if (_indexByRepo.remove(repoPath) != null) {
      notifyListeners();
    }
  }
}
