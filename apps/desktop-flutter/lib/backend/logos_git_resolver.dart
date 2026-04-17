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
import 'engram_brain.dart';
import 'engram_file_index.dart';
import 'engram_file_index_cache.dart';
import 'engram_file_ktable.dart';
import 'engram_hunk_encoder.dart';
import 'file_coupling.dart';
import 'git.dart';
import 'logos_git.dart';
import 'logos_git_diagnostics.dart';
import 'logos_git_stats.dart';
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

/// Hard cap on the number of engines the resolver retains. Each engine
/// can be tens of MB; without a ceiling, every repo a user opens stays
/// pinned in memory forever. 3 covers the typical "active repo plus
/// one or two recently-visited" pattern; the rest get evicted LRU.
const int _kMaxEngines = 3;

final LruCache<String, _ResolverEntry> _engines =
    LruCache<String, _ResolverEntry>(maxSize: _kMaxEngines);
final Map<String, Future<LogosGit?>> _inflight = {};
final Map<String, _HeadSnapshot> _headSnapshots = {};
const Duration _kHeadProbeTtl = Duration(seconds: 2);

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
  // Visualisation event: start of engine resolution. If we're inside
  // a review session (runInSession scope), the canvas narrates the
  // "terrain materialising" frame while we work below. Outside a
  // session (e.g. sidebar refresh), no-op.
  LogosVisBus.instance.emitInSession(
    (sid) => LogosVisEngineResolving(sid, repoPath: repoPath),
  );
  try {
    final cached = _engines.get(repoPath);
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
      return cached.engine;
    }

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

    final engine = await Isolate.run<LogosGit>(
      () => LogosGit.buildFromStats(
        stats,
        perFileKVectors: perFileKVectors,
      ),
      debugName: 'LogosGit.buildFromStats',
    );

    _engines.put(repoPath, _ResolverEntry(hash, engine));
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
    return engine;
  } catch (e, st) {
    log.recordFailure(repoPath, 'build threw: $e', sw.elapsed, st);
    return null;
  }
}
