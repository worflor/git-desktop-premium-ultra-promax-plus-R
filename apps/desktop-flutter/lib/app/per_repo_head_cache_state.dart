// per_repo_head_cache_state.dart — base class for the per-repo,
// HEAD-keyed, background-only state class pattern.
//
// Before this, FileCouplingState (and an observable family of future
// siblings) all hand-rolled the same
// scaffolding: `Map<repo, T>` cache, `Set<String> loading`, error
// map, invalidate-all-except, load-with-staleness-check. Same shape,
// same control flow, only the value type and compute function
// differed. This class names the pattern once; subclasses provide
// just the compute function, the head-hash extractor, and an error
// label. Adding a new sibling becomes 20 lines, not 80.

import 'package:flutter/foundation.dart';

import '../backend/repo_head_cache.dart';

/// One compute result. Subclasses' compute functions return this
/// shape; the base maps it to cache / error state transitions.
class ComputeOutcome<T> {
  final bool ok;
  final T? data;
  final String? error;
  const ComputeOutcome({required this.ok, this.data, this.error});

  const ComputeOutcome.success(T value)
      : ok = true,
        data = value,
        error = null;

  const ComputeOutcome.failure(String message)
      : ok = false,
        data = null,
        error = message;
}

/// Base class for "compute T from a repo, cache it, refresh on HEAD
/// change" state notifiers. Background-only — UI never blocks on the
/// load; cached values just fade in when ready.
///
/// Subclasses implement three small hooks:
///   • [compute] — does the work for [repoPath].
///   • [headHashOf] — pulls the HEAD hash out of a cached value so
///     the base can decide whether the cache is still fresh.
///   • [computeFailureLabel] — human-readable fallback error message.
abstract class PerRepoHeadCacheState<T> extends ChangeNotifier {
  final Map<String, T> _byRepo = {};
  final Set<String> _loading = {};
  final Map<String, String?> _errors = {};
  final Map<String, int> _generation = {};

  /// The cached value for [repoPath], or null if none. Subclasses
  /// typically expose this through a domain-named getter
  /// (`matrixFor`, `indexFor`, etc.) — calling through the typed
  /// alias reads better at the use site.
  T? valueFor(String repoPath) => _byRepo[repoPath];

  bool isLoading(String repoPath) => _loading.contains(repoPath);

  String? errorFor(String repoPath) => _errors[repoPath];

  /// Implementing subclass: compute the value for [repoPath].
  @protected
  Future<ComputeOutcome<T>> compute(String repoPath);

  /// Implementing subclass: extract the HEAD hash from a cached value
  /// so the base can run an inexpensive freshness check via
  /// [RepoHeadCache]. Return an empty string to disable the staleness
  /// shortcut and always recompute when [loadForRepo] is invoked.
  @protected
  String headHashOf(T value);

  /// Implementing subclass: fallback error label when [compute]
  /// returns ok=false with no specific error string.
  @protected
  String get computeFailureLabel;

  /// Drop every repo's cache except [repoPath]. Used by the workspace
  /// shell on repo switch to evict siblings while keeping the
  /// just-loaded one warm. Pass null to clear everything.
  ///
  /// Generation is bumped for every evicted repo, never removed —
  /// [loadForRepo] captures `_generation[repoPath]` before its awaits;
  /// removing the entry resets the read-back to the default 0, so an
  /// in-flight compute started at gen 0 would see `0 != 0 → false`
  /// after eviction and re-insert the evicted repo's value. Bumping
  /// instead guarantees the post-await check always observes a change.
  void invalidateAllExcept(String? repoPath) {
    if (repoPath == null) {
      if (_byRepo.isEmpty && _loading.isEmpty && _errors.isEmpty) return;
      for (final key in {..._byRepo.keys, ..._loading, ..._errors.keys}) {
        _generation[key] = (_generation[key] ?? 0) + 1;
      }
      _byRepo.clear();
      _loading.clear();
      _errors.clear();
      notifyListeners();
      return;
    }
    final evicted = {..._byRepo.keys, ..._loading, ..._errors.keys}
      ..remove(repoPath);
    if (evicted.isEmpty) return;
    for (final key in evicted) {
      _generation[key] = (_generation[key] ?? 0) + 1;
    }
    _byRepo.removeWhere((k, _) => k != repoPath);
    _loading.removeWhere((k) => k != repoPath);
    _errors.removeWhere((k, _) => k != repoPath);
    notifyListeners();
  }

  /// Drop the cached value for one repo; the next [loadForRepo] will
  /// recompute. Called when HEAD advances or after a destructive
  /// operation that invalidates the previous result.
  void invalidateRepo(String repoPath) {
    _generation[repoPath] = (_generation[repoPath] ?? 0) + 1;
    if (_byRepo.remove(repoPath) != null) {
      notifyListeners();
    }
  }

  /// Kick off a compute for [repoPath]. If a cached value exists and
  /// HEAD hasn't moved, returns immediately without recomputing.
  /// Concurrent calls de-dupe via the [_loading] gate on every path but
  /// one: when a cached value exists AND HEAD has moved, two calls can
  /// race the `matches` await before either sets the gate, and both
  /// recompute. The per-repo [_generation] check below makes that
  /// harmless — both writes carry identical data — so the only cost is a
  /// redundant compute on that rare path.
  Future<void> loadForRepo(String repoPath,
      {bool forceRefresh = false}) async {
    if (_loading.contains(repoPath)) return;

    final cached = _byRepo[repoPath];
    if (!forceRefresh && cached != null) {
      final hash = headHashOf(cached);
      if (hash.isNotEmpty &&
          await RepoHeadCache.instance.matches(repoPath, hash)) {
        return;
      }
    }

    final gen = _generation[repoPath] ?? 0;
    _loading.add(repoPath);
    _errors.remove(repoPath);
    notifyListeners();

    try {
      final result = await compute(repoPath);
      if ((_generation[repoPath] ?? 0) != gen) return;
      if (result.ok && result.data != null) {
        _byRepo[repoPath] = result.data as T;
        _errors.remove(repoPath);
      } else {
        _errors[repoPath] = result.error ?? computeFailureLabel;
      }
    } catch (e) {
      if ((_generation[repoPath] ?? 0) != gen) return;
      _errors[repoPath] = e.toString();
    } finally {
      _loading.remove(repoPath);
      notifyListeners();
    }
  }
}
