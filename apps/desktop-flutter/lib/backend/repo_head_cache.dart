// repo_head_cache.dart — process-wide cache of `git rev-parse HEAD`
// keyed by repo path, with a short TTL so concurrent staleness checks
// collapse into a single subprocess.
//
// Before this existed, FileCouplingState, WickState, LogosGitResolver,
// and a handful of other call sites each
// hand-rolled their own `runGit(repoPath, ['rev-parse', 'HEAD'])`
// staleness check. On any repo switch, half a dozen subprocess calls
// fired in parallel for the same answer. `runGit`'s built-in
// dedup catches concurrent calls but doesn't help the case where five
// caches each check HEAD a few ms apart.
//
// One call site, one TTL. Every staleness check becomes a memory
// lookup that occasionally falls back to a real subprocess.

import 'git.dart' show runGit;

/// Default freshness window. Long enough that a wave of post-repo-switch
/// staleness checks across N state classes collapses to one subprocess;
/// short enough that a manual HEAD movement (commit, checkout) is seen
/// almost immediately on the next access.
const Duration _kDefaultTtl = Duration(seconds: 2);

class _CachedHead {
  final String hash;
  final DateTime fetchedAt;
  const _CachedHead(this.hash, this.fetchedAt);
}

class RepoHeadCache {
  final Map<String, _CachedHead> _entries = {};
  final Map<String, Future<String?>> _inflight = {};
  /// Generation counter per repo — bumped on each fetch start, also
  /// bumped on evict. The in-flight `_fetch` captures the gen at
  /// launch and only commits its result to [_entries] if its gen is
  /// still the live one. Closes the race where an evict landed while
  /// a rev-parse was airborne and the late result silently overwrote
  /// the fresh state.
  final Map<String, int> _fetchGen = {};
  int _genCounter = 0;
  final Duration ttl;

  RepoHeadCache({this.ttl = _kDefaultTtl});

  /// Singleton — every consumer should share one instance so the TTL
  /// actually deduplicates across subsystems.
  static final RepoHeadCache instance = RepoHeadCache();

  /// Most-recent HEAD hash for [repoPath], or null when git isn't
  /// reachable. Cached for [ttl]; concurrent calls share a single
  /// in-flight future per repo.
  Future<String?> head(String repoPath, {bool forceRefresh = false}) {
    if (!forceRefresh) {
      final cached = _entries[repoPath];
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt) < ttl) {
        return Future.value(cached.hash);
      }
    }
    final existing = _inflight[repoPath];
    if (existing != null) return existing;
    final myGen = ++_genCounter;
    _fetchGen[repoPath] = myGen;
    final future = _fetch(repoPath, myGen);
    _inflight[repoPath] = future;
    future.whenComplete(() {
      if (identical(_inflight[repoPath], future)) {
        _inflight.remove(repoPath);
      }
    });
    return future;
  }

  /// Check whether [repoPath]'s HEAD matches [expectedHash]. The
  /// canonical "is my cache still fresh?" form: returns true iff the
  /// repo is reachable AND its HEAD equals [expectedHash]. Returns
  /// false on any disagreement or git error — callers can then safely
  /// recompute their downstream cache.
  Future<bool> matches(String repoPath, String expectedHash) async {
    if (expectedHash.isEmpty) return false;
    final h = await head(repoPath);
    return h != null && h == expectedHash;
  }

  void evict(String repoPath) {
    _entries.remove(repoPath);
    _inflight.remove(repoPath);
    // Bump the generation so any in-flight fetch that lands AFTER
    // this evict won't quietly re-populate _entries with a hash
    // that was already invalidated. The fetch sees gen mismatch
    // and skips its write.
    _fetchGen[repoPath] = ++_genCounter;
  }

  Future<String?> _fetch(String repoPath, int myGen) async {
    try {
      final probe = await runGit(repoPath, ['rev-parse', 'HEAD']);
      if (probe.exitCode != 0) return null;
      final hash = probe.stdout.toString().trim();
      if (hash.isEmpty) return null;
      // Only commit to the cache if this fetch is still the live
      // in-flight for this repo. If evict ran (or a newer fetch
      // started) between launch and landing, our gen is stale and
      // we discard the write without losing the return value.
      if (_fetchGen[repoPath] == myGen) {
        _entries[repoPath] = _CachedHead(hash, DateTime.now());
      }
      return hash;
    } catch (_) {
      return null;
    }
  }
}
