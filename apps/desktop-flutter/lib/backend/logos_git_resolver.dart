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

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'engram_bootstrap.dart';
import 'shadow_coupling.dart';
import 'shadow_coupling_cache.dart';
import 'shadow_history.dart';
import 'engram_brain.dart';
import 'engram_file_index.dart';
import 'engram_file_index_cache.dart';
import 'engram_file_ktable.dart';
import 'engram_hunk_encoder.dart';
import 'file_coupling.dart';
import 'git.dart';
import 'logos_git.dart';
import 'logos_git_diagnostics.dart';
import 'git_result.dart';
import 'logos_git_stats.dart';
import 'remote_types.dart' show detectAllForges;
import 'perf_span.dart' show perfSpan;
import 'logos_vis_events.dart';
import 'lru_cache.dart';

class _ResolverEntry {
  final String headHash;
  final LogosGit engine;
  const _ResolverEntry(this.headHash, this.engine);
}

class _HeadSnapshot {
  final String headHash;
  final DateTime fetchedAt;

  const _HeadSnapshot({
    required this.headHash,
    required this.fetchedAt,
  });
}

/// Hard cap on retained engines. 5 covers the active repo + a few
/// IPC-warmed repos without unbounded growth.
const int _kMaxEngines = 5;

final LruCache<String, _ResolverEntry> _engines =
    LruCache<String, _ResolverEntry>(maxSize: _kMaxEngines);
final Map<String, Future<LogosGit?>> _inflight = {};
final Map<String, _HeadSnapshot> _headSnapshots = {};
final Map<String, DateTime> _lastAccess = {};
const Duration _kHeadProbeTtl = Duration(seconds: 2);
const Duration _kEngineDecayTtl = Duration(minutes: 15);

/// Hard ceiling on the cheap `git rev-parse HEAD` probe that precedes
/// every engine refresh. Without a bound, a hung git (network drive
/// unmount, ref-lock held by a crashed tool, malformed repo) would pin
/// the `_inflight` entry for this repo forever and prevent any later
/// refresh. Chosen generously: a healthy rev-parse returns in a few ms
/// even on large repos; 8 s is far past the tail of normal behaviour.
const Duration _kHeadProbeTimeout = Duration(seconds: 8);

void _emitHyperbolicIfPresent(LogosGit engine) {
  if (engine.hyperbolicEmbedding != null) {
    LogosVisBus.instance.emitInSession(
      (sid) => LogosVisHyperbolicLayout(
        sid,
        coordinates: engine.hyperbolicCoordinates,
      ),
    );
  }
}

/// Drop `_headSnapshots` entries for repos that are no longer in the
/// `_engines` LRU. Called after each insert so the head-snapshot map
/// can never outgrow the engine cache. Cheap — the LRU holds ≤ 3
/// entries and `_headSnapshots` is typically the same size.
void _pruneHeadSnapshotsForEngines() {
  if (_headSnapshots.length <= _kMaxEngines) return;
  final live = <String>{
    for (final entry in _engines.entries) entry.key,
  };
  _headSnapshots.removeWhere((key, _) => !live.contains(key));
}

/// Build the per-file engram K-vector index with disk caching +
/// parallel encoding. Runs on the main isolate so we can fan out to
/// multiple worker isolates via `Isolate.run`; isolates can't nest
/// cleanly, so doing this before the build isolate spawn is the right
/// shape.
/// Steps:
///   1. Load the brain (cheap, ~5ms — needed for pairs + well names).
///   2. Load the disk cache for this repo path.
///   3. stat() every node-path and classify as (hit, miss).
///   4. Fan out misses across up to [_kMaxEncodeIsolates] isolates.
///   5. Merge + persist cache.
///   6. Wrap the merged map into a dense [EngramFileKTable] for the
///      engine — kills the Map<String, HunkKVector> shape on the
///      hot path; LogosGit then reads K-vectors as flat-array slices.
Future<EngramFileKTable?> _buildEngramFileIndexFast({
  required String repoPath,
  required LogosGitStats stats,
  required EngramAssets assets,
}) async {
  // Load the brain to get pairs + the well name table. The well
  // names get baked into the EngramFileKTable so downstream callers
  // (`wellOf(path)`) don't need a brain reference.
  late EngramBrain brain;
  try {
    brain = EngramBrain.loadBytes(assets.brainBytes);
  } on Object {
    return null;
  }
  final pairs = brain.pairs;

  // Union of all node paths (same set buildFromStats uses). Reads
  // from the CSR's interned path list directly, no lazy-map
  // materialisation triggered.
  final repoRelPaths = <String>{
    ...stats.touches.keys,
    ...stats.volatility.keys,
    ...stats.coupling.paths,
  };
  if (repoRelPaths.isEmpty) return null;

  // Disk cache keyed by absolute path (what buildEngramFileIndex
  // passes to stat). We also read the cache's entries once and reuse
  // them below when classifying paths as cache hits or misses.
  final cache = await EngramFileIndexCache.load(
    repoPath: repoPath,
    expectedPairs: pairs,
  );

  final hits = <String, HunkKVector>{};
  final missPaths = <String>[];
  final freshMeta = <String, ({int mtimeMs, int size})>{};

  // Classify every path. A `stat` is ~5–10µs — 1000 files = ~10ms
  // total, parallelism-free. Worth it to skip a full read + encode
  // for files whose mtime+size haven't moved.
  for (final rel in repoRelPaths) {
    try {
      final file = File(_join(repoPath, rel));
      final stat = file.statSync();
      // Directories / missing files have FileSystemEntityType.notFound
      // — they were in stats' key set but aren't on disk right now.
      // Skip silently; the engine can still work without them.
      if (stat.type != FileSystemEntityType.file) continue;
      final mtimeMs = stat.modified.millisecondsSinceEpoch;
      final size = stat.size;
      freshMeta[rel] = (mtimeMs: mtimeMs, size: size);

      final cached = cache.get(rel);
      if (cached != null && cached.mtimeMs == mtimeMs && cached.size == size) {
        hits[rel] = cached.kVector;
      } else {
        missPaths.add(rel);
      }
    } on FileSystemException {
      // Unreadable file — neither cached nor will encode.
      continue;
    }
  }

  // Parallel encode on misses. Each chunk is wrapped in its own
  // try-catch so a single bad isolate (e.g. corrupt brain bytes on one
  // thread) contributes an empty map rather than aborting Future.wait
  // and discarding all cache hits from the other chunks.
  final encoded = <String, HunkKVector>{};
  if (missPaths.isNotEmpty) {
    final chunks = _splitPaths(missPaths);
    final futures = <Future<Map<String, HunkKVector>>>[];
    for (final chunk in chunks) {
      futures.add(
        Isolate.run<Map<String, HunkKVector>>(
          () => engramEncodeChunk(EngramEncodeJob(
            brainBytes: assets.brainBytes,
            gloveBytes: assets.gloveBytes,
            repoPath: repoPath,
            paths: chunk,
          )),
          debugName: 'engram.encodeChunk',
        ).catchError((_) => const <String, HunkKVector>{}),
      );
    }
    final results = await Future.wait(futures);
    for (final r in results) {
      encoded.addAll(r);
    }
  }

  // Merge hits + fresh encoded → final map.
  final merged = <String, HunkKVector>{}
    ..addAll(hits)
    ..addAll(encoded);

  // Persist the updated cache (fire-and-forget). We write the full
  // cache including both prior hits and new misses so stale entries
  // for files that moved out of the node set eventually get flushed
  // when the user opens a different repo that causes a rewrite.
  unawaited(_persistCache(
    repoPath: repoPath,
    pairs: pairs,
    merged: merged,
    freshMeta: freshMeta,
  ));

  if (merged.isEmpty) return null;
  return EngramFileKTable.fromMap(
    pairs: pairs,
    encodings: merged,
    wellNamesByOriginalIndex: brain.wellNamesByOriginalIndex,
  );
}

/// Hard cap on encoding isolates. Beyond 8 the coordination + spawn
/// overhead eats the parallel gain — and most machines the app runs
/// on have 4–16 logical cores anyway. Derived from `numberOfProcessors`
/// with a pragmatic ceiling.
final int _kMaxEncodeIsolates =
    math.min(8, math.max(2, Platform.numberOfProcessors));

/// Minimum paths per chunk. Below this the isolate spawn cost (~20ms
/// per spawn) dominates the encode cost. Keeps tiny repos on a
/// single isolate where they belong.
const int _kMinPathsPerChunk = 64;

/// Split missing-paths into up to [_kMaxEncodeIsolates] roughly equal
/// chunks. Chunks are stable for a given input order (not randomised)
/// so the on-disk cache's write ordering stays deterministic.
List<List<String>> _splitPaths(List<String> paths) {
  if (paths.length <= _kMinPathsPerChunk) return [paths];
  final nChunks = math.min(
    _kMaxEncodeIsolates,
    (paths.length / _kMinPathsPerChunk).ceil(),
  );
  final chunkSize = (paths.length / nChunks).ceil();
  final out = <List<String>>[];
  for (var start = 0; start < paths.length; start += chunkSize) {
    final end = math.min(start + chunkSize, paths.length);
    out.add(paths.sublist(start, end));
  }
  return out;
}

/// Cross-platform path join without pulling in `package:path` up here.
/// This is only used for the on-disk file lookup; the engram encoder
/// does its own path joining internally.
String _join(String base, String rel) {
  final sep = Platform.pathSeparator;
  if (base.endsWith(sep) || base.endsWith('/')) return '$base$rel';
  return '$base$sep$rel';
}

Future<void> _persistCache({
  required String repoPath,
  required int pairs,
  required Map<String, HunkKVector> merged,
  required Map<String, ({int mtimeMs, int size})> freshMeta,
}) async {
  try {
    final entries = <String, EngramFileIndexCacheEntry>{};
    for (final e in merged.entries) {
      final meta = freshMeta[e.key];
      if (meta == null) continue; // couldn't stat → don't cache
      entries[e.key] = EngramFileIndexCacheEntry(
        mtimeMs: meta.mtimeMs,
        size: meta.size,
        kVector: e.value,
      );
    }
    await EngramFileIndexCache.save(
      repoPath: repoPath,
      pairs: pairs,
      entries: entries,
    );
  } catch (_) {
    // Cache write is best-effort. Next run just pays the cold cost.
  }
}

/// Resolve the [LogosGit] engine for [repoPath]. Returns the cached
/// engine when HEAD hasn't moved; otherwise builds, caches, returns.
/// Two simultaneous callers for the same repo share a single build.
/// Pass a warm [coupling] matrix to skip one 1000-commit log walk.
Future<LogosGit?> resolveLogosGit(
  String repoPath, {
  FileCouplingMatrix? coupling,
}) {
  final exactKey = _inflightKey(repoPath, coupling: coupling);
  final pending = _inflight[exactKey];
  if (pending != null) return pending;

  if (coupling == null) {
    final coupledPending = _findInflightForRepo(
      repoPath,
      preferCoupled: true,
    );
    if (coupledPending != null) return coupledPending;
  }

  final future = _resolveImpl(repoPath, coupling);
  _inflight[exactKey] = future;
  future.whenComplete(() => _inflight.remove(exactKey));
  return future;
}

String? peekResolvedLogosGitHeadHash(
  String repoPath, {
  FileCouplingMatrix? coupling,
}) {
  final snapshot = _headSnapshots[repoPath];
  if (snapshot != null) return snapshot.headHash;
  final cached = _engines.get(repoPath);
  if (cached != null) return cached.headHash;
  return coupling?.headHash;
}

/// Drop any cached engine for [repoPath]. Next [resolveLogosGit] call
/// rebuilds from scratch. Use when HEAD obviously moved and you want
/// the rebuild eager rather than next-lookup-lazy.
void invalidateLogosGit(String repoPath) {
  _engines.remove(repoPath);
  _headSnapshots.remove(repoPath);
}

/// Drop every cached engine. Repo closed, user cleared caches, etc.
void invalidateAllLogosGit() {
  _engines.clear();
  _headSnapshots.clear();
  _lastAccess.clear();
}

void _pruneDecayedEngines() {
  final now = DateTime.now();
  final stale = <String>[];
  for (final entry in _lastAccess.entries) {
    if (now.difference(entry.value) > _kEngineDecayTtl) {
      stale.add(entry.key);
    }
  }
  for (final key in stale) {
    _engines.remove(key);
    _headSnapshots.remove(key);
    _lastAccess.remove(key);
  }
}

String _inflightKey(
  String repoPath, {
  FileCouplingMatrix? coupling,
}) =>
    coupling == null
        ? '$repoPath|base'
        : '$repoPath|coupling:${coupling.headHash}';

Future<LogosGit?>? _findInflightForRepo(
  String repoPath, {
  required bool preferCoupled,
}) {
  for (final entry in _inflight.entries) {
    if (!entry.key.startsWith('$repoPath|')) continue;
    final isCoupled = entry.key.contains('|coupling:');
    if (preferCoupled && !isCoupled) continue;
    return entry.value;
  }
  return null;
}

Future<LogosGit?> _resolveImpl(
  String repoPath,
  FileCouplingMatrix? coupling,
) async {
  final sw = Stopwatch()..start();
  final log = LogosGitDiagnostics.instance;
  LogosVisBus.instance.emitInSession(
    (sid) => LogosVisEngineResolving(sid, repoPath: repoPath),
  );
  // Prune engines untouched for 15+ minutes before resolving so
  // idle IPC-warmed repos don't hold memory indefinitely.
  _pruneDecayedEngines();
  try {
    final cached = _engines.get(repoPath);
    _lastAccess[repoPath] = DateTime.now();
    final now = DateTime.now();
    final headSnapshot = _headSnapshots[repoPath];
    if (cached != null &&
        headSnapshot != null &&
        now.difference(headSnapshot.fetchedAt) <= _kHeadProbeTtl &&
        cached.headHash == headSnapshot.headHash) {
      log.recordCacheHit(repoPath, sw.elapsed);
      LogosVisBus.instance.emitInSession(
        (sid) => LogosVisEngineReady(
          sid,
          nodeCount: cached.engine.nodePaths.length,
          cached: true,
        ),
      );
      _emitHyperbolicIfPresent(cached.engine);
      return cached.engine;
    }

    // Staleness check — cheap rev-parse, bail if HEAD unchanged.
    // Bounded by [_kHeadProbeTimeout] so a hung git can't pin the
    // `_inflight` slot for this repo indefinitely (the subprocess call
    // itself has no internal deadline).
    final ProcessResult head;
    try {
      head = await runGitProbe(
        repoPath,
        const ['rev-parse', 'HEAD'],
      ).timeout(_kHeadProbeTimeout);
    } on TimeoutException {
      log.recordFailure(repoPath,
          'rev-parse HEAD timed out after ${_kHeadProbeTimeout.inSeconds}s',
          sw.elapsed);
      return null;
    }
    if (head.exitCode != 0) {
      log.recordFailure(repoPath, 'rev-parse HEAD failed', sw.elapsed);
      return null;
    }
    final hash = head.stdout.toString().trim();
    if (hash.isEmpty) {
      log.recordFailure(repoPath, 'empty HEAD hash', sw.elapsed);
      return null;
    }
    _headSnapshots[repoPath] = _HeadSnapshot(
      headHash: hash,
      fetchedAt: now,
    );

    if (cached != null && cached.headHash == hash) {
      // LRU touch via re-insertion. `put` promotes to most-recently-used.
      _engines.put(repoPath, cached);
      log.recordCacheHit(repoPath, sw.elapsed);
      // Cache-hit path. Canvas snaps to the ready frame with no
      // warming linger since the engine was already built.
      LogosVisBus.instance.emitInSession(
        (sid) => LogosVisEngineReady(
          sid,
          nodeCount: cached.engine.nodePaths.length,
          cached: true,
        ),
      );
      _emitHyperbolicIfPresent(cached.engine);
      return cached.engine;
    }

    final topology = await detectAllForges(repoPath);
    final forge = topology.primary;
    // All three calls are I/O-bound (git subprocesses + optional network).
    // Start all before awaiting so they run concurrently.
    final reviewFut = collectReviewedCommitsAllForges(repoPath, topology);
    final statsFut = collectLogosGitStats(repoPath, coupling: coupling,
        forge: forge.name);
    final shadowFut = _resolveShadowCoupling(repoPath);
    final results = await Future.wait([reviewFut, statsFut, shadowFut]);
    final reviewedCommits = results[0] as Map<String, Set<String>>;
    final statsResultRaw = results[1] as GitResult<LogosGitStats>;
    final shadowCoupling = results[2] as FileCouplingMatrix?;
    // Merge review data into the stats post-hoc — tag hyperedges with
    // reviewer identities now that both results are available.
    var mergedStats = statsResultRaw.ok && statsResultRaw.data != null
        ? _mergeReviewData(statsResultRaw.data!, reviewedCommits)
        : null;
    if (mergedStats != null && shadowCoupling != null) {
      mergedStats = mergedStats.copyWith(shadowCoupling: shadowCoupling);
    }
    final statsResult = mergedStats != null
        ? GitResult.ok(mergedStats)
        : statsResultRaw;
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

    //
    // The expensive part of engram integration used to be a single
    // isolate walking every node-path on disk, reading + encoding
    // each file. On a thousand-file repo that was 5–15 seconds of
    // pure serial work.
    //
    // Now:
    //   1. Check a disk cache keyed by (file path, mtime, size).
    //      Unchanged files reuse their previously-encoded K-vectors —
    //      a stat() call per file instead of a full read + encode.
    //      On a warm reload this is ~50ms total for a kilo-file repo.
    //   2. Split the remaining (cache-miss) paths across N isolates,
    //      one per CPU core up to a cap. Each runs `engramEncodeChunk`
    //      independently and returns a Map<path, HunkKVector>.
    //      4–8× speedup on cold builds.
    //   3. Merge results, write the updated cache back to disk
    //      asynchronously so it's available on next launch.
    //
    // Done BEFORE the LogosGit build isolate so the engine build gets
    // the K-vectors as a pre-computed Map (cheap to cross the isolate
    // boundary — typed lists sendable as bulk bytes).
    final engramAssets = await EngramRuntime.instance.assets();
    EngramFileKTable? perFileKVectors;
    if (engramAssets != null) {
      try {
        perFileKVectors = await _buildEngramFileIndexFast(
          repoPath: repoPath,
          stats: stats,
          assets: engramAssets,
        );
      } catch (_) {
        // Engram is best-effort — any failure falls through to the
        // legacy 4-axis engine.
        perFileKVectors = null;
      }
    }

    // Phase: engine.build — the isolate hop that dominates cold
    // engine resolution (graph construction + Lanczos warm-up).
    // Marshalling + actual build visible as one span so the
    // telemetry dashboard can distinguish repo-size-bound cost from
    // git-subprocess cost upstream.
    final engine = await perfSpan(
      'logos.engine.build',
      () => Isolate.run<LogosGit>(
        () {
          final built = LogosGit.buildFromStats(
            stats,
            perFileKVectors: perFileKVectors,
          );
          // Warm the spectral basis inside the worker so the first
          // [gatherEvidence] call on the UI isolate never pays the
          // one-time Lanczos cost. The basis lives inside the engine's
          // cache (`_spectralCache`) and is copied across the isolate
          // boundary with the engine on return — turning a UI-freeze
          // into a background build.
          built.spectralBasis();
          return built;
        },
        debugName: 'LogosGit.buildFromStats',
      ),
    );

    _engines.put(repoPath, _ResolverEntry(hash, engine));
    _lastAccess[repoPath] = DateTime.now();
    _pruneHeadSnapshotsForEngines();
    log.recordBuild(
      repoPath: repoPath,
      nodes: engine.nodePaths.length,
      duration: sw.elapsed,
    );
    // Fresh-build path. Canvas crystallises the topology dots here.
    LogosVisBus.instance.emitInSession(
      (sid) => LogosVisEngineReady(
        sid,
        nodeCount: engine.nodePaths.length,
        cached: false,
      ),
    );
    _emitHyperbolicIfPresent(engine);
    return engine;
  } catch (e, st) {
    log.recordFailure(repoPath, 'build threw: $e', sw.elapsed, st);
    return null;
  }
}

Future<FileCouplingMatrix?> _resolveShadowCoupling(String repoPath) async {
  try {
    final headResult = await Process.run(
      'git', ['rev-parse', 'HEAD'],
      workingDirectory: repoPath,
    );
    final currentHead = headResult.exitCode == 0
        ? (headResult.stdout as String).trim()
        : '';

    final cached = await ShadowCouplingCache.load(repoPath);
    final cacheValid = cached != null &&
        cached.isFresh &&
        cached.jaccardEdges.isNotEmpty &&
        currentHead.isNotEmpty &&
        cached.headHash == currentHead;
    if (cacheValid) {
      return FileCouplingMatrix(
        jaccard: cached.jaccardEdges,
        headHash: 'shadow:${cached.headHash}',
        commitsAnalyzed: cached.shadowCommitCount,
      );
    }

    final shadows = await discoverShadowHistory(repoPath)
        .timeout(const Duration(seconds: 5), onTimeout: () {
      return ShadowHistoryResult(
        commits: const [],
        discoveredAt: DateTime.now(),
        headHash: '',
      );
    });
    if (shadows.commits.isEmpty) {
      // Only fall back to stale cache if HEAD still matches — prevents
      // using coupling from a prior branch after checkout/reset.
      if (cached != null &&
          cached.jaccardEdges.isNotEmpty &&
          (currentHead.isEmpty || cached.headHash == currentHead)) {
        return FileCouplingMatrix(
          jaccard: cached.jaccardEdges,
          headHash: 'shadow:${cached.headHash}',
          commitsAnalyzed: cached.shadowCommitCount,
        );
      }
      return null;
    }

    final matrix = computeShadowCoupling(shadows);
    if (matrix == null) return null;

    final typeCounts = <String, int>{};
    for (final c in shadows.commits) {
      final key = c.type.name;
      typeCounts[key] = (typeCounts[key] ?? 0) + 1;
    }

    final newData = ShadowCouplingCacheData(
      headHash: shadows.headHash,
      discoveredAt: shadows.discoveredAt,
      shadowCommitCount: shadows.commits.length,
      jaccardEdges: matrix.jaccard,
      edgeTypeCounts: typeCounts,
    );
    final merged = cached != null ? cached.mergeWith(newData) : newData;
    await ShadowCouplingCache.save(repoPath, merged);

    return FileCouplingMatrix(
      jaccard: merged.jaccardEdges,
      headHash: 'shadow:${merged.headHash}',
      commitsAnalyzed: merged.shadowCommitCount,
    );
  } catch (e) {
    LogosGitDiagnostics.instance.recordFailure(
      repoPath,
      'shadow discovery: ${e.runtimeType}',
      Duration.zero,
    );
    return null;
  }
}

LogosGitStats _mergeReviewData(
  LogosGitStats stats,
  Map<String, Set<String>> reviewedCommits,
) {
  if (reviewedCommits.isEmpty) return stats;
  final taggedHyperedges = <String, List<LogosCommitHyperedge>>{};
  final reviewersByPath = <String, Set<String>>{};
  for (final entry in stats.hyperedgesByPath.entries) {
    final tagged = <LogosCommitHyperedge>[];
    for (final edge in entry.value) {
      final hash = edge.commitHash;
      if (edge.observers.isEmpty && hash != null && reviewedCommits.containsKey(hash)) {
        final observers = reviewedCommits[hash]!;
        tagged.add(LogosCommitHyperedge(
          paths: edge.paths,
          weight: edge.weight,
          summary: edge.summary,
          commitHash: hash,
          observers: observers,
        ));
        for (final path in edge.paths) {
          (reviewersByPath[path] ??= <String>{}).addAll(observers);
        }
      } else {
        tagged.add(edge);
        if (edge.observers.isNotEmpty) {
          for (final path in edge.paths) {
            (reviewersByPath[path] ??= <String>{}).addAll(edge.observers);
          }
        }
      }
    }
    taggedHyperedges[entry.key] = tagged;
  }
  return LogosGitStats(
    touches: stats.touches,
    totalCommits: stats.totalCommits,
    rawTouches: stats.rawTouches,
    rawTotalCommits: stats.rawTotalCommits,
    touchMass: stats.touchMass,
    semanticCommitMass: stats.semanticCommitMass,
    volatility: stats.volatility,
    volMean: stats.volMean,
    volStddev: stats.volStddev,
    coupling: stats.coupling,
    perFileCommitIndices: stats.perFileCommitIndices,
    perFileCommitClock: stats.perFileCommitClock,
    ritualnessByPath: stats.ritualnessByPath,
    integrityByPath: stats.integrityByPath,
    integrityReasonsByPath: stats.integrityReasonsByPath,
    hyperedgesByPath: taggedHyperedges,
    forge: stats.forge,
    reviewedCommits: reviewedCommits,
    reviewersByPath: reviewersByPath,
  );
}
