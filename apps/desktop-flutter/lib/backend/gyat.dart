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
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'git.dart' show runGitProbe;
import 'logos_core.dart';
import 'logos_flow.dart' show extractFlowGraph, optimizeGraph, simulateFlow;

// Cap on files scanned during bootstrap. Huge repos (10k+ files)
// don't need every blob — a sampled subset gives the same lattice
// shape since CharCoupling stats converge after a few hundred blobs.
const int _kBootstrapFileCap = 800;
// Skip blobs over this size — multi-megabyte files are usually
// generated/vendored and pollute the bigram basis.
const int _kBootstrapMaxBytes = 256 * 1024;

/// Shared instance cache — one lattice per repo, shared across all
/// consumers (DiffShell, FilamentPanel, etc.) for the lifetime of
/// the session. Switching repos evicts the previous instance; the
/// new repo bootstraps on first request.
GyatLattice? _cachedInstance;
Future<GyatLattice>? _inflightBootstrap;
String? _inflightRepoPath;

/// Return the GYAT lattice for [repoPath]. First call per repo
/// triggers bootstrap from git contents in an isolate; subsequent
/// calls return the cached instance instantly. Concurrent calls
/// for the same repo share a single bootstrap future.
Future<GyatLattice> gyatForRepo(String repoPath) async {
  final cached = _cachedInstance;
  if (cached != null && cached.repoPath == repoPath) return cached;
  if (_inflightBootstrap != null && _inflightRepoPath == repoPath) {
    return _inflightBootstrap!;
  }
  _inflightRepoPath = repoPath;
  final future = GyatLattice.bootstrap(repoPath);
  _inflightBootstrap = future;
  try {
    final loaded = await future;
    _cachedInstance = loaded;
    return loaded;
  } finally {
    if (_inflightRepoPath == repoPath) {
      _inflightBootstrap = null;
      _inflightRepoPath = null;
    }
  }
}

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
  /// alphabetical). Runs in an isolate so the main thread stays
  /// responsive.
  static Future<GyatLattice> bootstrap(String repoPath) async {
    final lsProbe = await runGitProbe(repoPath, ['ls-files']);
    if (lsProbe.exitCode != 0) {
      return GyatLattice.fresh(repoPath);
    }
    final allPaths = (lsProbe.stdout as String)
        .split('\n')
        .where((l) => l.isNotEmpty)
        .toList(growable: false);
    if (allPaths.isEmpty) return GyatLattice.fresh(repoPath);

    // Sample if the repo is huge. Stride keeps the sample uniform
    // across the alphabetical path order so the bigram basis reflects
    // the whole repo, not just `a*` files.
    final paths = allPaths.length <= _kBootstrapFileCap
        ? allPaths
        : <String>[
            for (var i = 0;
                i < allPaths.length;
                i += (allPaths.length / _kBootstrapFileCap).ceil())
              allPaths[i],
          ];

    final result =
        await Isolate.run(() => _bootstrapInIsolate(repoPath, paths));
    return GyatLattice._(result.lattice, repoPath, result.coupling);
  }
}

class _BootstrapResult {
  final FlowSseLattice lattice;
  final CharCoupling coupling;
  _BootstrapResult(this.lattice, this.coupling);
}

/// Top-level so it can run in an isolate (closures can't cross).
/// Reads each blob, sums its bigram counts into the repo-global
/// CharCoupling, then synthetically scans each blob with the global
/// basis and merges into the lattice.
_BootstrapResult _bootstrapInIsolate(String repoPath, List<String> paths) {
  // Two passes: first sum bigram counts to build the canonical basis,
  // then scan each blob against the basis. The basis HAS to be
  // built first because the scan depends on it.
  final sources = <String>[];
  for (final rel in paths) {
    try {
      final file = File(p.join(repoPath, rel));
      if (!file.existsSync()) continue;
      final stat = file.statSync();
      if (stat.size <= 0 || stat.size > _kBootstrapMaxBytes) continue;
      // Skip likely-binary by checking for nulls in the first 8KB.
      final probe = file.openSync();
      try {
        final head = probe.readSync(math.min(8192, stat.size));
        var nullSeen = false;
        for (var i = 0; i < head.length; i++) {
          if (head[i] == 0) {
            nullSeen = true;
            break;
          }
        }
        if (nullSeen) continue;
      } finally {
        probe.closeSync();
      }
      final source = file.readAsStringSync();
      if (source.length < 16) continue;
      sources.add(source);
    } catch (_) {
      // Unreadable / non-UTF-8 — skip.
    }
  }
  if (sources.isEmpty) {
    return _BootstrapResult(
        FlowSseLattice(), CharCoupling.fromSources(const []));
  }

  final coupling = CharCoupling.fromSources(sources);

  // Second pass: scan each source with the canonical basis and
  // accumulate into a single lattice.
  final lattice = FlowSseLattice();
  for (final source in sources) {
    try {
      final graph = optimizeGraph(
          extractFlowGraph(source, globalCoupling: coupling));
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
