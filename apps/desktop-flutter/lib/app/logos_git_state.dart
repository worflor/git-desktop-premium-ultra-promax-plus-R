// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:async';

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
  final Set<String> _loadingWithCoupling = {};
  final Map<String, String?> _errors = {};

  /// Bumped (never removed) for a repo whenever it's evicted or
  /// explicitly invalidated. [loadForRepo] captures the generation
  /// before its awaits and only installs its result if it's unchanged
  /// after — so a build in flight when the repo gets evicted can't
  /// resurrect a stale engine into `_engineByRepo`.
  final Map<String, int> _generation = {};

  LogosGit? engineFor(String repoPath) => _engineByRepo[repoPath];

  /// Test-only seam: when set, [loadForRepo] resolves the engine through
  /// this instead of the real git-driven [resolver.resolveLogosGit], so
  /// the per-repo cache/eviction contract can be exercised headless with
  /// no subprocess. Mirrors [RepositoryState]'s injectable-loader pattern.
  @visibleForTesting
  Future<LogosGit?> Function(String repoPath, {FileCouplingMatrix? coupling})?
      resolveOverride;

  bool isLoading(String repoPath) => _loading.contains(repoPath);

  String? errorFor(String repoPath) => _errors[repoPath];

  void invalidateAllExcept(String? repoPath) {
    resolver.invalidateAllLogosGitExcept(repoPath);
    if (repoPath == null) {
      for (final key in {..._engineByRepo.keys, ..._loading, ..._errors.keys}) {
        _generation[key] = (_generation[key] ?? 0) + 1;
      }
      _engineByRepo.clear();
      _loading.clear();
      _loadingWithCoupling.clear();
      _errors.clear();
      notifyListeners();
      return;
    }
    final evicted = {..._engineByRepo.keys, ..._loading, ..._errors.keys}
      ..remove(repoPath);
    final hadOthers = evicted.isNotEmpty;
    for (final key in evicted) {
      _generation[key] = (_generation[key] ?? 0) + 1;
    }
    _engineByRepo.removeWhere((k, _) => k != repoPath);
    _loading.removeWhere((k) => k != repoPath);
    _loadingWithCoupling.removeWhere((k) => k != repoPath);
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
    final wantsCoupling = coupling != null;
    if (_loading.contains(repoPath) &&
        (!wantsCoupling || _loadingWithCoupling.contains(repoPath))) {
      return;
    }

    final gen = _generation[repoPath] ?? 0;
    _loading.add(repoPath);
    if (wantsCoupling) {
      _loadingWithCoupling.add(repoPath);
    }
    _errors.remove(repoPath);
    notifyListeners();

    try {
      final resolve = resolveOverride;
      final engine = resolve != null
          ? await resolve(repoPath, coupling: coupling)
          : await resolver.resolveLogosGit(repoPath, coupling: coupling);
      // Stale if this repo was evicted or explicitly invalidated while
      // the resolve was in flight — don't let a late result resurrect
      // an engine for a repo the shell has already moved on from.
      if ((_generation[repoPath] ?? 0) != gen) return;
      if (engine == null) {
        _errors[repoPath] = 'engine resolution failed';
      } else {
        _engineByRepo[repoPath] = engine;
        _errors.remove(repoPath);
      }
    } catch (e) {
      if ((_generation[repoPath] ?? 0) != gen) return;
      _errors[repoPath] = e.toString();
    } finally {
      if (wantsCoupling) {
        _loadingWithCoupling.remove(repoPath);
      }
      if (!_loadingWithCoupling.contains(repoPath)) {
        _loading.remove(repoPath);
      }
      notifyListeners();
    }
  }

  /// Staleness-aware awaited accessor: the engine for [repoPath], fresh
  /// at HEAD granularity, or null when it could not be resolved within
  /// [timeout].
  ///
  /// Routes through [loadForRepo] on EVERY call — the shared resolver's
  /// HEAD probe makes that a single cheap (TTL-deduped) rev-parse when
  /// history hasn't moved, and a rebuild when it has. This is the
  /// accessor for callers that need the current repo's engine NOW (the
  /// CLI bridge); [engineFor] stays the UI's non-blocking probe.
  /// Probe-then-return was the CLI staleness bug: the first call's
  /// engine snapshot served every later call unrefreshed.
  ///
  /// [timeout] bounds the WHOLE call — including a cold build this call
  /// itself starts (a first cut bounded only the concurrent-load wait,
  /// so a slow rebuild hung the CLI bridge unboundedly; caught by
  /// Manifold's own review). On timeout the build keeps running in the
  /// background (next call reaps it) and whatever engine is currently
  /// cached — possibly stale, possibly none — is returned.
  Future<LogosGit?> freshEngineFor(
    String repoPath, {
    FileCouplingMatrix? coupling,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final sw = Stopwatch()..start();
    try {
      await loadForRepo(repoPath, coupling: coupling).timeout(timeout);
    } on TimeoutException {
      return _engineByRepo[repoPath];
    }
    if (!_loading.contains(repoPath)) return _engineByRepo[repoPath];
    final remaining = timeout - sw.elapsed;
    if (remaining <= Duration.zero) return _engineByRepo[repoPath];
    final completer = Completer<void>();
    void listener() {
      if (!_loading.contains(repoPath) && !completer.isCompleted) {
        completer.complete();
      }
    }
    addListener(listener);
    try {
      // Re-check after subscribing — the load may have finished between
      // the gate check above and addListener.
      if (!_loading.contains(repoPath)) return _engineByRepo[repoPath];
      await completer.future.timeout(remaining, onTimeout: () {});
    } finally {
      removeListener(listener);
    }
    return _engineByRepo[repoPath];
  }

  void invalidateRepo(String repoPath) {
    resolver.invalidateLogosGit(repoPath);
    _generation[repoPath] = (_generation[repoPath] ?? 0) + 1;
    final removed = _engineByRepo.remove(repoPath) != null;
    final wasLoading = _loading.remove(repoPath);
    final hadCoupledLoading = _loadingWithCoupling.remove(repoPath);
    final hadError = _errors.remove(repoPath) != null;
    if (removed || wasLoading || hadCoupledLoading || hadError) {
      notifyListeners();
    }
  }
}
