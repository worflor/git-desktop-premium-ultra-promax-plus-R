// SPECTRAL TRAJECTORY BUILDER — derives a real [SpectralTrajectory]
// from a repo's git history.
//
// The dual companion to [GyatLattice]:
//   GYAT       = canonical structural prior at HEAD (one snapshot).
//   Trajectory = ordered sequence of LogosStates across recent
//                commits, with the corresponding [SpectralTrajectory]
//                observables (turbulence, weather, Berry phase,
//                archetype transitions, dominant frequency).
//
// Why: prior to this builder, the only "past-aware" signal in the
// muse pipeline came from the LLM inferring history from current code
// plus a GHOST/Archivist prompt. That's improv, not measurement. The
// trajectory produces real spectra from real prior commits so temporal
// claims have ground truth — turbulence, drift, breathing period,
// regime changes all measured from the same git history the user
// can verify.
//
// Cost shape:
//   * One `git log --name-only` subprocess for the whole walk.
//   * Per snapshot point: SpectralBasis.fromGraph on the accumulated
//     file co-touch graph (Lanczos pass, 200ms-2s depending on graph).
//   * Time-budget capped: stops early at [_kBudget] regardless of
//     requested depth so even huge repos return a useful trajectory.

import 'dart:async';
import 'dart:convert' show LineSplitter, Utf8Codec;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'graph/csr_builder.dart' show CsrEdge, buildSymmetricCsrGraph;
import 'logos_core.dart' show SpectralBasis;
import 'peek_warm_cache.dart';
import 'spectral_state.dart';
import 'spectral_trajectory.dart';

const Duration _kBudget = Duration(seconds: 45);
const int _kMaxDepth = 32;
const int _kMinDepth = 4;
const int _kHistoryWindow = 256;
const int _kSpectralK = 16;

const _lenientUtf8 = Utf8Codec(allowMalformed: true);

/// Per-repo trajectory cache. Backed by [PeekWarmCache] — the cache
/// also enforces a per-bootstrap timeout so a hung sync read inside
/// the isolate (symlink loop, network-mount stall) can't permanently
/// wedge the cache in its in-flight state.
final PeekWarmCache<SpectralTrajectory> _trajectoryCache =
    PeekWarmCache<SpectralTrajectory>(
  bootstrap: (repoPath) => Isolate.run(() => _bootstrapInIsolate(repoPath)),
  // Empty trajectories don't track their source repo; the cache slot
  // is single-key, so identity-match is fine — peek() already
  // verifies the cachedKey matches the lookup key.
  matchesKey: (cached, key) => true,
  label: 'spectral_trajectory',
);

/// Return the SpectralTrajectory for [repoPath]. First call per repo
/// triggers an isolate-backed bootstrap; subsequent calls return the
/// cached value instantly. Concurrent callers for the same repo share
/// a single bootstrap future.
///
/// Use when the caller can afford to wait for cold-start. For caller-
/// paths that must never block on cold (the AI muse pipeline), use
/// [peekTrajectoryForRepo] + [warmTrajectoryForRepo] instead — the
/// same peek/warm/await split used by GyatLattice.
Future<SpectralTrajectory> trajectoryForRepo(String repoPath) =>
    _trajectoryCache.loadOrAwait(repoPath);

/// Synchronous peek. Returns the cached trajectory for [repoPath]
/// when warm, null otherwise. Never triggers bootstrap.
SpectralTrajectory? peekTrajectoryForRepo(String repoPath) =>
    _trajectoryCache.peek(repoPath);

/// Fire-and-forget warm-up. Kicks the bootstrap in the background if
/// nothing matching [repoPath] is cached or already warming.
/// Idempotent and silently swallows errors — this is a background
/// optimisation; the next caller's peek returns null and the pipeline
/// degrades gracefully.
void warmTrajectoryForRepo(String repoPath) =>
    _trajectoryCache.warm(repoPath);

/// One commit's worth of metadata we hold in memory during the walk.
class _CommitRecord {
  _CommitRecord({
    required this.sha,
    required this.timestamp,
    required this.paths,
  });
  final String sha;
  final DateTime timestamp;
  final List<String> paths;
}

/// Top-level so it can run in an isolate (closures can't cross).
/// One git log subprocess yields the whole history window; the
/// in-isolate walker accumulates the file co-touch graph and
/// snapshots a spectral basis at stride-evenly-spaced points.
SpectralTrajectory _bootstrapInIsolate(String repoPath) {
  final commits = _readHistoryWindow(repoPath, _kHistoryWindow);
  if (commits.length < 2) return SpectralTrajectory.empty();

  // Decide stride so we land roughly _kMaxDepth snapshots across the
  // commits we got. Smaller windows naturally take denser points.
  final desired = math.min(_kMaxDepth, commits.length);
  final stride = math.max(1, (commits.length / desired).ceil());

  // Allocate stable file ids as we walk oldest-first. The CSR graph
  // grows as new files appear; each snapshot sees the graph as it
  // stands at that point.
  final pathToId = <String, int>{};
  final coTouchCounts = <int, Map<int, int>>{};
  final deadline = DateTime.now().add(_kBudget);

  final points = <TrajectoryPoint>[];
  var snapshotRevision = 0;

  for (var i = 0; i < commits.length; i++) {
    final commit = commits[i];
    _ingestCommit(commit.paths, pathToId, coTouchCounts);

    final isStridePoint = (i % stride == 0);
    final isLast = (i == commits.length - 1);
    if (!isStridePoint && !isLast) continue;

    // Time budget guard. Honor the floor first; past that, stop if
    // we've blown the wall-clock budget. SpectralTrajectory degrades
    // gracefully on short trajectories — every observable handles
    // length < required-window by returning NaN or [].
    if (points.length >= _kMinDepth && DateTime.now().isAfter(deadline)) {
      break;
    }

    final basis = _buildSnapshotBasis(pathToId, coTouchCounts);
    final state = LogosState(
      fileSpectrum: basis,
      commitSpectrum: null,
      joint: null,
      revision: snapshotRevision,
    );
    points.add(TrajectoryPoint(
      revision: snapshotRevision,
      state: state,
      commitSha: commit.sha,
      timestamp: commit.timestamp,
    ));
    snapshotRevision += 1;
  }

  return SpectralTrajectory(points: points);
}

/// Run `git log` once for the recent history window. Output is parsed
/// into oldest-first order so the walker accumulates the graph
/// chronologically. Non-merge commits only — merge commits don't
/// change the file set and would inflate path overlap statistics
/// without adding real structural signal.
List<_CommitRecord> _readHistoryWindow(String repoPath, int maxCommits) {
  final result = Process.runSync(
    'git',
    [
      'log',
      '--no-merges',
      '--name-only',
      '--pretty=format:__C__%H %ct',
      '-n',
      '$maxCommits',
      'HEAD',
    ],
    workingDirectory: repoPath,
    stdoutEncoding: _lenientUtf8,
  );
  if (result.exitCode != 0) return const <_CommitRecord>[];

  final raw = result.stdout as String;
  final records = <_CommitRecord>[];
  String? currentSha;
  DateTime? currentTs;
  var currentPaths = <String>[];

  void flushCurrent() {
    final sha = currentSha;
    final ts = currentTs;
    if (sha != null && ts != null) {
      records.add(_CommitRecord(
        sha: sha,
        timestamp: ts,
        paths: currentPaths,
      ));
    }
  }

  for (final line in const LineSplitter().convert(raw)) {
    if (line.startsWith('__C__')) {
      flushCurrent();
      final header = line.substring(5);
      final spaceIdx = header.indexOf(' ');
      if (spaceIdx <= 0) {
        currentSha = null;
        currentTs = null;
        currentPaths = <String>[];
        continue;
      }
      currentSha = header.substring(0, spaceIdx);
      final tsSecs = int.tryParse(header.substring(spaceIdx + 1).trim()) ?? 0;
      currentTs =
          DateTime.fromMillisecondsSinceEpoch(tsSecs * 1000, isUtc: true);
      currentPaths = <String>[];
      continue;
    }
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    currentPaths.add(trimmed.replaceAll('\\', '/'));
  }
  flushCurrent();
  return records.reversed.toList(growable: false);
}

/// Allocate ids for any new paths in [commitPaths] and increment the
/// co-touch counter for every unordered file pair touched together
/// in this commit. Symmetric — we only store the canonical (lo, hi)
/// entry so each pair counts once.
void _ingestCommit(
  List<String> commitPaths,
  Map<String, int> pathToId,
  Map<int, Map<int, int>> coTouchCounts,
) {
  if (commitPaths.isEmpty) return;
  final ids = <int>{};
  for (final path in commitPaths) {
    final id = pathToId.putIfAbsent(path, () => pathToId.length);
    ids.add(id);
  }
  if (ids.length < 2) return;
  final sorted = ids.toList()..sort();
  for (var i = 0; i < sorted.length; i++) {
    final lo = sorted[i];
    final row = coTouchCounts.putIfAbsent(lo, () => <int, int>{});
    for (var j = i + 1; j < sorted.length; j++) {
      final hi = sorted[j];
      row[hi] = (row[hi] ?? 0) + 1;
    }
  }
}

/// Materialise a [SpectralBasis] from the current co-touch matrix.
/// The basis n is `pathToId.length` (all files seen so far); files
/// with zero edges remain isolated nodes and contribute zero
/// eigenmodes (trajectory observables tolerate that gracefully).
SpectralBasis _buildSnapshotBasis(
  Map<String, int> pathToId,
  Map<int, Map<int, int>> coTouchCounts,
) {
  final n = pathToId.length;
  if (n < 2) {
    return SpectralBasis(
      n: n,
      k: 0,
      eigenvalues: Float64List(0),
      eigenvectors: Float64List(0),
    );
  }
  final edges = <CsrEdge>[];
  coTouchCounts.forEach((lo, row) {
    row.forEach((hi, count) {
      edges.add(CsrEdge(lo, hi, count.toDouble()));
    });
  });
  final graph = buildSymmetricCsrGraph(n: n, edges: edges);
  final k = math.min(_kSpectralK, n);
  // Attach path labels (ids are dense 0..n-1 from putIfAbsent) so labeled
  // queries resolve. reshapedEchoes' cited-path loading reads eigenvector
  // amplitudes per file through these; without them every snapshot basis
  // is math-only and the reshape weight silently collapses to zero.
  final nodePaths = List<String>.filled(n, '');
  pathToId.forEach((path, id) => nodePaths[id] = path);
  return SpectralBasis.fromGraph(graph, k, nodePaths: nodePaths);
}
