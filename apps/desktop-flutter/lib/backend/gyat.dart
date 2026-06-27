// GYAL — Geometric Yielded Adaptive Lattice (formerly "GYAT, Tokenizer").
//
// The repo's structural feature prior. A 256-cell Welford lattice on Q₈
// holding per-address cell statistics for the filament walker's certainty
// observations. Not a tokenizer in the BPE/WordPiece sense — it does not
// emit token streams. It is a **lattice prior** with stable repo-wide
// address semantics, derived deterministically from git's own contents.
//
// Two design rules:
//   1. Born adult, in-memory only. The lattice is bootstrapped from git
//      on first use of a repo each session — never an empty cold-start.
//      No disk persistence: the lattice is a function of git contents,
//      and git already stores those. Caching the derivation would be
//      redundant spam. Bootstrap runs in an isolate so the UI doesn't
//      block; subsequent requests in the same session hit an in-memory
//      cache. When the app quits, the lattice evaporates — next session
//      reproduces it deterministically from the same commit.
//   2. Coherent addresses. The eigenfrequency basis (CharCoupling) is
//      a **single repo-wide bigram distribution**, summed from every
//      blob. Address `0x47` means the same thing in every file in this
//      repo, so per-cell Welford accumulators aren't averaging
//      semantically unrelated observations.

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';
import 'logos_flow.dart' show extractFlowGraph, optimizeGraph, simulateFlow;
import 'peek_warm_cache.dart';
import 'repo_blob_walk.dart';

// Cap on files scanned during bootstrap. Huge repos (10k+ files)
// don't need every blob — a sampled subset gives the same lattice
// shape since CharCoupling stats converge after a few hundred blobs.
const int _kBootstrapFileCap = 800;
// Skip blobs over this size — multi-megabyte files are usually
// generated/vendored and pollute the bigram basis.
const int _kBootstrapMaxBytes = 256 * 1024;

const _kBootstrapWalkOptions = RepoBlobWalkOptions(
  fileCap: _kBootstrapFileCap,
  maxBytes: _kBootstrapMaxBytes,
);

/// Shared instance cache — one lattice per repo, shared across all
/// consumers (DiffShell, FilamentPanel, etc.) for the lifetime of
/// the session. Switching repos evicts the previous instance; the
/// new repo bootstraps on first request.
///
/// Backed by [PeekWarmCache] — the cache also enforces a per-bootstrap
/// timeout so a hung sync file read inside the isolate can't leave
/// the cache permanently wedged in the in-flight state.
final PeekWarmCache<GyatLattice> _gyatCache = PeekWarmCache<GyatLattice>(
  bootstrap: GyatLattice.bootstrap,
  matchesKey: (cached, key) => cached.repoPath == key,
  label: 'gyat',
);

/// Return the GYAT lattice for [repoPath]. First call per repo
/// triggers bootstrap from git contents in an isolate; subsequent
/// calls return the cached instance instantly. Concurrent calls
/// for the same repo share a single bootstrap future.
///
/// Use this when the caller can afford to wait for cold-start
/// (filament panel, explicit user-initiated scans). For caller-paths
/// that should never block on a cold lattice (the AI muse pipeline,
/// the diff shell), use [peekGyatForRepo] + [warmGyatForRepo]
/// instead — fast peek for "do you have it now?", fire-and-forget
/// warm-up for "have it ready for next time."
Future<GyatLattice> gyatForRepo(String repoPath) =>
    _gyatCache.loadOrAwait(repoPath);

/// Synchronous peek into the cache. Returns the cached lattice for
/// [repoPath] when it's already warm; null otherwise. NEVER triggers
/// bootstrap — the caller must not assume a non-null return after a
/// null one without also calling [warmGyatForRepo].
///
/// Use in latency-critical pipelines (muse, diff shell) so the cold-
/// start cost doesn't surface as perceived AI latency. The pipeline
/// degrades gracefully when the peek returns null: the spectral
/// enhancements (lattice priors, factoredness signal, structural
/// context) skip for this call; the next call after warm-up
/// completes picks them up.
GyatLattice? peekGyatForRepo(String repoPath) => _gyatCache.peek(repoPath);

/// Fire-and-forget warm-up. Kicks GYAT bootstrap in the background
/// when nothing matching [repoPath] is cached or already warming.
/// Idempotent: safe to call from multiple lifecycle hooks
/// (repo-open, panel-mount, pre-fire) — duplicate calls collapse
/// into the single in-flight bootstrap future.
///
/// Pair with [peekGyatForRepo] in caller-paths that want the lattice
/// if it's ready but can't wait for cold start. Workspace lifecycle
/// (repo selection, filament-panel mount) calls this proactively so
/// the lattice is usually warm by the time downstream consumers
/// (muse, diff annotation) need it.
void warmGyatForRepo(String repoPath) => _gyatCache.warm(repoPath);

/// Per-repo GYAT lattice — in-memory only, derived from git contents.
class GyatLattice {
  final FlowSseLattice lattice;
  final String repoPath;
  CharCoupling? _globalCoupling;

  GyatLattice._(this.lattice, this.repoPath, this._globalCoupling);

  factory GyatLattice.fresh(String repoPath) =>
      GyatLattice._(FlowSseLattice(), repoPath, null);

  /// The repo-global character coupling — the canonical eigenfrequency
  /// basis. Built during bootstrap from every blob's bigram statistics.
  /// Null for a fresh (un-bootstrapped) lattice.
  CharCoupling? get globalCoupling => _globalCoupling;

  /// Snapshot of cell means as a 256-element Float64List. Passed into
  /// worker isolates to construct a priorNovelty function without
  /// shipping the full lattice object.
  Float64List get cellMeansSnapshot {
    final out = Float64List(256);
    for (var a = 0; a < 256; a++) {
      out[a] = lattice.cellMean(a);
    }
    return out;
  }

  /// Snapshot of cell counts. Companion to [cellMeansSnapshot] for
  /// novelty derivation (cold cells are maximally novel; warm cells
  /// with high counts are familiar).
  Int32List get cellCountsSnapshot {
    final out = Int32List(256);
    for (var a = 0; a < 256; a++) {
      out[a] = lattice.cellCount(a);
    }
    return out;
  }

  /// Accumulate a scan's observations into the lattice. Uses Chan et al.
  /// parallel Welford merge to preserve both mean AND variance.
  /// Refinements live only for the current session — when the app
  /// quits the lattice evaporates and the next session re-bootstraps
  /// from git. That's intentional: bootstrap state is canonical;
  /// session-scoped refinement is informational decoration.
  void absorb(FlowSseLattice scanLattice) {
    for (var a = 0; a < 256; a++) {
      if (scanLattice.cellCount(a) == 0) continue;
      lattice.mergeCell(a, scanLattice);
    }
  }

  /// Replace the canonical global coupling.
  void setGlobalCoupling(CharCoupling coupling) {
    _globalCoupling = coupling;
  }

  /// Information surprise of a single address against the prior.
  /// High value = the lattice hasn't settled on this phoneme.
  /// Low value = well-known structural pattern.
  double surprise(int address, double certainty) {
    final z = lattice.zBelowForAddress(address, certainty);
    return z > 0 ? z : 0.0;
  }

  /// File surprise: mean information content of a file's phoneme
  /// distribution against the repo-wide prior. Higher = more novel.
  double fileSurprise(Map<int, int> addressCounts) {
    if (addressCounts.isEmpty) return 0.0;
    var total = 0.0;
    var n = 0;
    for (final entry in addressCounts.entries) {
      final addr = entry.key;
      final count = entry.value;
      final mean = lattice.cellMean(addr);
      final z = lattice.zBelowForAddress(addr, mean);
      total += z.abs() * count;
      n += count;
    }
    return n > 0 ? total / n : 0.0;
  }

  /// Negative log of the lattice's partition function at temperature
  /// `t`. Low = regular/predictable repo. High = novel/complex.
  /// (This is `−log Z`, not the Helmholtz free energy `F = −T·log Z`;
  /// the rename clarifies which quantity we're returning.)
  double negLogPartition({double t = 1.0}) {
    var z = 0.0;
    for (var a = 0; a < 256; a++) {
      if (lattice.cellCount(a) < 8) continue;
      z += math.exp(-t * lattice.cellMean(a));
    }
    return z > 0 ? -math.log(z) : 0.0;
  }

  // ── Bootstrap ───────────────────────────────────────────────────

  /// Walk the repo's HEAD tree, derive the canonical CharCoupling
  /// from every blob's bigram statistics, run a synthetic filament
  /// scan over each blob using the global basis, and merge every
  /// scan's lattice into a fresh GYAT.
  ///
  /// Deterministic: two users on the same commit get the same
  /// bootstrapped lattice (modulo file-order, which is `ls-files`
  /// alphabetical). The entire pipeline — `git ls-files`, per-file
  /// read/binary-filter/decode, CharCoupling sum, and lattice
  /// synthesis — runs inside a single worker isolate. The main thread
  /// is never blocked on file I/O even for cold-cache or network-
  /// mounted repos at the 800-file cap.
  static Future<GyatLattice> bootstrap(String repoPath) async {
    final result = await Isolate.run(() => _bootstrapInIsolate(repoPath));
    return GyatLattice._(result.lattice, repoPath, result.coupling);
  }
}

class _BootstrapResult {
  final FlowSseLattice lattice;
  final CharCoupling coupling;
  _BootstrapResult(this.lattice, this.coupling);
}

/// Top-level so it can run in an isolate (closures can't cross).
/// Lists the repo with `Process.runSync`, reads every surviving blob
/// sync, builds the canonical CharCoupling, then synthetically scans
/// each source against that basis and merges into the lattice.
_BootstrapResult _bootstrapInIsolate(String repoPath) {
  final walk = walkRepoBlobsSync(repoPath, options: _kBootstrapWalkOptions);
  if (walk.blobs.isEmpty) {
    return _BootstrapResult(
        FlowSseLattice(), CharCoupling.fromSources(const []));
  }
  final sources = [for (final b in walk.blobs) b.text];
  // Repo-wide character coupling — returned for the engine's lattice. (Flow
  // graphs themselves now address by scope geometry, not this basis.)
  final coupling = CharCoupling.fromSources(sources);
  final lattice = FlowSseLattice();
  for (final source in sources) {
    try {
      final graph = optimizeGraph(extractFlowGraph(source));
      if (graph.nodes.length < 2) continue;
      final scan = FlowSseLattice();
      simulateFlow(graph, threshold: 1.0, sseLattice: scan);
      for (var a = 0; a < 256; a++) {
        if (scan.cellCount(a) > 0) {
          lattice.mergeCell(a, scan);
        }
      }
    } catch (_) {
      // One bad blob doesn't kill the bootstrap.
    }
  }
  return _BootstrapResult(lattice, coupling);
}
