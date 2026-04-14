// ═════════════════════════════════════════════════════════════════════════
// logos_git_resolver.dart — single source of truth for engine lifecycle
//
// One resolver. Any caller — UI state class, AI context builder, tests —
// routes through here. Keyed by repo path; HEAD hash determines whether
// the cached engine is fresh. Single in-flight build per repo (duplicate
// requests await the same Future).
//
// CACHE POLICY: an LRU bounded at [_kMaxEngines]. Each engine is a
// 5–50 MB object graph (CSR + per-file maps), so an unbounded cache
// turns every repo the user has ever opened into a permanent memory
// pin. The LRU keeps the working set hot and lets the rest go.
//
// COMPUTE POLICY: `LogosGit.buildFromStats` is hundreds of ms to
// seconds of pure CPU on a real repo. It runs on a background isolate
// via `Isolate.run` so the UI never freezes during a cold build.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'file_coupling.dart';
import 'git.dart';
import 'logos_git.dart';
import 'logos_git_diagnostics.dart';
import 'logos_git_stats.dart';

class _ResolverEntry {
  final String headHash;
  final LogosGit engine;
  const _ResolverEntry(this.headHash, this.engine);
}

/// Hard cap on the number of engines the resolver retains. Each engine
/// can be tens of MB; without a ceiling, every repo a user opens stays
/// pinned in memory forever. 3 covers the typical "active repo plus
/// one or two recently-visited" pattern; the rest get evicted LRU.
const int _kMaxEngines = 3;

/// LinkedHashMap iteration order is insertion order, so we can use it
/// as an LRU by deleting + re-inserting on access. Cheap and sufficient
/// for a 3-entry cache.
final LinkedHashMap<String, _ResolverEntry> _engines = LinkedHashMap();
final Map<String, Future<LogosGit?>> _inflight = {};

/// Resolve the [LogosGit] engine for [repoPath]. Returns the cached
/// engine when HEAD hasn't moved; otherwise builds, caches, returns.
/// Two simultaneous callers for the same repo share a single build.
/// Pass a warm [coupling] matrix to skip one 1000-commit log walk.
Future<LogosGit?> resolveLogosGit(
  String repoPath, {
  FileCouplingMatrix? coupling,
}) {
  final pending = _inflight[repoPath];
  if (pending != null) return pending;

  final future = _resolveImpl(repoPath, coupling);
  _inflight[repoPath] = future;
  future.whenComplete(() => _inflight.remove(repoPath));
  return future;
}

/// Drop any cached engine for [repoPath]. Next [resolveLogosGit] call
/// rebuilds from scratch. Use when HEAD obviously moved and you want
/// the rebuild eager rather than next-lookup-lazy.
void invalidateLogosGit(String repoPath) {
  _engines.remove(repoPath);
}

/// Drop every cached engine. Repo closed, user cleared caches, etc.
void invalidateAllLogosGit() {
  _engines.clear();
}

Future<LogosGit?> _resolveImpl(
  String repoPath,
  FileCouplingMatrix? coupling,
) async {
  final sw = Stopwatch()..start();
  final log = LogosGitDiagnostics.instance;
  try {
    // Staleness check — cheap rev-parse, bail if HEAD unchanged.
    final head = await runGitProbe(
      repoPath,
      const ['rev-parse', 'HEAD'],
    );
    if (head.exitCode != 0) {
      log.recordFailure(repoPath, 'rev-parse HEAD failed', sw.elapsed);
      return null;
    }
    final hash = head.stdout.toString().trim();
    if (hash.isEmpty) {
      log.recordFailure(repoPath, 'empty HEAD hash', sw.elapsed);
      return null;
    }

    final cached = _engines[repoPath];
    if (cached != null && cached.headHash == hash) {
      // LRU touch: re-insert moves to the most-recently-used end.
      _engines
        ..remove(repoPath)
        ..[repoPath] = cached;
      log.recordCacheHit(repoPath, sw.elapsed);
      return cached.engine;
    }

    final statsResult =
        await collectLogosGitStats(repoPath, coupling: coupling);
    if (!statsResult.ok || statsResult.data == null) {
      log.recordFailure(
        repoPath,
        statsResult.error ?? 'stats collection failed',
        sw.elapsed,
      );
      return null;
    }

    // Off-load the pure-CPU build to a background isolate so the UI
    // never freezes during cold load. The stats object is sendable
    // (Maps + typed lists + scalars), and so is the resulting engine —
    // both cross the isolate port via copy serialisation. For a 10k-
    // file engine the copy cost is a few ms versus hundreds-of-ms of
    // build cost, so the trade is firmly net-positive.
    final stats = statsResult.data!;
    final engine = await Isolate.run<LogosGit>(
      () => LogosGit.buildFromStats(stats),
      debugName: 'LogosGit.buildFromStats',
    );

    // Insert + LRU-evict in one step. `entries.first` is the
    // least-recently-used because LinkedHashMap is insertion-ordered.
    _engines[repoPath] = _ResolverEntry(hash, engine);
    while (_engines.length > _kMaxEngines) {
      _engines.remove(_engines.keys.first);
    }
    log.recordBuild(
      repoPath: repoPath,
      nodes: engine.nodePaths.length,
      duration: sw.elapsed,
    );
    return engine;
  } catch (e, st) {
    log.recordFailure(repoPath, 'build threw: $e', sw.elapsed, st);
    return null;
  }
}
