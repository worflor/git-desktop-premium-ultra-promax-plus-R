import 'package:flutter/foundation.dart';

import '../backend/file_coupling.dart';
import '../backend/logos_git.dart';
import '../backend/logos_git_resolver.dart' as resolver;

/// Owns the [LogosGit] engine per repo, cached by HEAD hash.
/// Mirror of [FileCouplingState]'s shape so the provider tree treats it
/// the same way. Background-only — UI never blocks on the build. When
/// the engine arrives, a `notifyListeners()` fans out to consumers.
/// The engine layers ON TOP of the file-coupling matrix: it reuses the
/// matrix when provided (via [loadForRepo]'s optional `coupling` arg)
/// so the two stores share the same cold-path cost. Without a coupling
/// matrix we fall back to building one inline.
class LogosGitState extends ChangeNotifier {
  // The state class is a thin reactive wrapper around the shared
  // resolver. The resolver owns the real cache; we hold references to
  // what's been resolved so far, plus `isLoading` / `errorFor` for the
  // UI's benefit. One cache, one source of truth, no race with ai.dart.
  final Map<String, LogosGit> _engineByRepo = {};
  final Set<String> _loading = {};
  final Map<String, String?> _errors = {};

  LogosGit? engineFor(String repoPath) => _engineByRepo[repoPath];

  bool isLoading(String repoPath) => _loading.contains(repoPath);

  String? errorFor(String repoPath) => _errors[repoPath];

  void invalidateAllExcept(String? repoPath) {
    if (repoPath == null) {
      _engineByRepo.clear();
      _loading.clear();
      _errors.clear();
      resolver.invalidateAllLogosGit();
      notifyListeners();
      return;
    }
    final hadOthers = _engineByRepo.keys.any((k) => k != repoPath) ||
        _loading.any((k) => k != repoPath);
    _engineByRepo.removeWhere((k, _) => k != repoPath);
    _loading.removeWhere((k) => k != repoPath);
    _errors.removeWhere((k, _) => k != repoPath);
    if (hadOthers) notifyListeners();
  }

  /// Kick off (or share) a build. Staleness check lives in the shared
  /// resolver — `resolveLogosGit` short-circuits when HEAD hasn't moved.
  /// Pass a warm [coupling] matrix to skip one `git log` walk.
  Future<void> loadForRepo(
    String repoPath, {
    FileCouplingMatrix? coupling,
  }) async {
    if (_loading.contains(repoPath)) return;

    _loading.add(repoPath);
    _errors.remove(repoPath);
    notifyListeners();

    try {
      final engine =
          await resolver.resolveLogosGit(repoPath, coupling: coupling);
      if (engine == null) {
        _errors[repoPath] = 'engine resolution failed';
      } else {
        _engineByRepo[repoPath] = engine;
        _errors.remove(repoPath);
      }
    } catch (e) {
      _errors[repoPath] = e.toString();
    } finally {
      _loading.remove(repoPath);
      notifyListeners();
    }
  }

  void invalidateRepo(String repoPath) {
    resolver.invalidateLogosGit(repoPath);
    final removed = _engineByRepo.remove(repoPath) != null;
    if (removed) notifyListeners();
  }
}
