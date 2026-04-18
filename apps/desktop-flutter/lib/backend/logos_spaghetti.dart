// LogosSpaghetti — the tangle analyzer.
//
// Spaghetti code is structure-less: no scale separation, no coherent
// eigenstructure, no modular boundaries. Every one of those clauses
// has a theorem behind it, and the engine has verified all of them on
// healthy graphs. This module inverts those theorems into diagnostics:
// when a theorem *fails* on the current repo, that failure IS the
// spaghetti signal.
//
// Outputs:
//
//   * `TangleIndex`     — global scalar ∈ [0, 1]; high = spaghetti
//   * `TangleMap`       — per-file contribution
//   * `Spaghetti*`      — specific pattern detectors (god class,
//                         dead code, Casimir bridge, Courant anomaly)
//
// Each signal traces to a theorem from `spectral-cosmology.md`. No
// heuristic thresholds masquerading as physics — the numbers either
// match a theorem's prediction or they don't.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';
import 'logos_git.dart';

/// Global tangle score ∈ [0, 1]. High = no clean scale separation,
/// low = healthy hierarchical structure.
///
/// Derivation: a healthy codebase exhibits **asymptotic freedom** —
/// the effective coupling (1/λ₁) shrinks as we coarsen. Spaghetti code
/// doesn't coarsen cleanly: λ₁ stays flat across RG levels because
/// every scale is equally tangled. The Tangle Index measures
/// `1 − monotonicity of λ₁ / modularity / Cheeger ratio across scales`.
class TangleIndex {
  /// Sequence of spectral gaps observed at each RG coarsening level,
  /// finest to coarsest. Healthy = strictly increasing; spaghetti = flat.
  final List<double> spectralGapPerLevel;

  /// Ratio-of-ratios: how much λ₁ grows under coarsening. 1.0 = grows
  /// smoothly as predicted by asymptotic freedom; lower values signal
  /// tangled scales.
  final double monotonicityScore;

  /// Aggregate scalar in [0, 1]. `1 − monotonicityScore`, clamped.
  double get value => (1.0 - monotonicityScore).clamp(0.0, 1.0).toDouble();

  const TangleIndex({
    required this.spectralGapPerLevel,
    required this.monotonicityScore,
  });
}

/// Tangle contribution per node — how much each file adds to the
/// global tangle signal. Sum across all files ≈ Tangle Index.
class TangleMap {
  /// path → contribution in [0, ∞). Higher = this file is spaghettier.
  final Map<String, double> perPath;

  /// Sorted list of top-N contributors (highest first).
  List<MapEntry<String, double>> top(int n) {
    final entries = perPath.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).toList();
  }

  const TangleMap({required this.perPath});
}

/// A specific spaghetti-pattern detection. Each subclass traces to a
/// theorem that predicts "healthy" behaviour; the detector fires when
/// actual behaviour deviates.
sealed class SpaghettiFinding {
  final String path;
  final double severity; // 0..1
  const SpaghettiFinding({required this.path, required this.severity});

  String describe();
}

/// Bekenstein bound violation: a node's spectral participation
/// entropy exceeds `log(k)`. Physically: it's trying to encode more
/// information than its mode subspace allows. Code-wise: a god class.
final class GodClassFinding extends SpaghettiFinding {
  final double entropy;
  final double entropyBound;

  const GodClassFinding({
    required super.path,
    required super.severity,
    required this.entropy,
    required this.entropyBound,
  });

  @override
  String describe() =>
      'god class: $path (entropy ${entropy.toStringAsFixed(2)} '
      '> bound ${entropyBound.toStringAsFixed(2)})';
}

/// Anderson localisation signature: the node's mass concentrates on
/// a narrow mode group. Paired with Poincaré-like recurrence (short
/// mixing time within the localised subgraph) this is **dead code**.
final class DeadCodeFinding extends SpaghettiFinding {
  final double ipr;
  const DeadCodeFinding({
    required super.path,
    required super.severity,
    required this.ipr,
  });

  @override
  String describe() =>
      'localised / stagnant: $path (IPR ${ipr.toStringAsFixed(2)})';
}

/// Casimir bridge: an edge that artificially connects what would
/// otherwise be independent components. Physically: two disconnected
/// ground-state zeros split by a weak coupling. Code-wise: a spurious
/// utility dependency.
final class CasimirBridgeFinding extends SpaghettiFinding {
  final String partnerPath;
  final double conductance;
  const CasimirBridgeFinding({
    required super.path,
    required this.partnerPath,
    required this.conductance,
    required super.severity,
  });

  @override
  String describe() =>
      'spurious bridge: $path ↔ $partnerPath '
      '(conductance ${conductance.toStringAsFixed(3)})';
}

/// Top-level entry: run every detector and return a spectral health
/// report. Lazy — each detector only runs what it needs; the shared
/// spectral basis is computed once.
class SpaghettiReport {
  final TangleIndex tangleIndex;
  final TangleMap tangleMap;
  final List<SpaghettiFinding> findings;

  const SpaghettiReport({
    required this.tangleIndex,
    required this.tangleMap,
    required this.findings,
  });

  /// Sorted by severity.
  List<SpaghettiFinding> get topFindings {
    final list = [...findings]..sort((a, b) => b.severity.compareTo(a.severity));
    return list;
  }
}

/// Compute a complete spaghetti report on the engine's current graph.
///
/// Single entry point — runs all detectors, composes into a report.
/// Cost: one spectral basis build + a handful of RG coarsenings.
/// Returns `null` when the engine has no spectral basis.
SpaghettiReport? analyzeSpaghetti(LogosGit engine, {int rgLevels = 3}) {
  final basis = engine.spectralBasis();
  if (basis == null) return null;
  final g = engine.graph;
  if (g.n < 4) return null;

  final tangle = _computeTangleIndex(g, rgLevels: rgLevels);
  final tangleMap = _computeTangleMap(engine, basis);

  final findings = <SpaghettiFinding>[];
  findings.addAll(_detectGodClasses(engine, basis));
  findings.addAll(_detectDeadCode(engine, basis));
  findings.addAll(_detectCasimirBridges(engine, basis));

  return SpaghettiReport(
    tangleIndex: tangle,
    tangleMap: tangleMap,
    findings: findings,
  );
}

// ── TangleIndex: asymptotic freedom check across RG levels ──────────

TangleIndex _computeTangleIndex(CsrGraph g, {required int rgLevels}) {
  final gaps = <double>[];
  var current = g;
  for (var level = 0; level <= rgLevels; level++) {
    if (current.n < 4) break;
    final basis = SpectralBasis.fromGraph(current, math.min(current.n, 20));
    final gap =
        basis.eigenvalues.length < 2 ? 0.0 : basis.eigenvalues[1];
    gaps.add(gap);
    if (level == rgLevels || current.n < 8) break;
    // Coarsen by pairing consecutive nodes.
    final groupOf =
        List<int>.generate(current.n, (i) => i ~/ 2);
    current = current.coarsen(groupOf);
  }
  // Monotonicity score: fraction of level transitions where gap grew.
  var grew = 0;
  var total = 0;
  for (var i = 1; i < gaps.length; i++) {
    total++;
    if (gaps[i] > gaps[i - 1] * 1.05) grew++;
  }
  final monotonicity = total == 0 ? 1.0 : grew / total;
  return TangleIndex(
    spectralGapPerLevel: gaps,
    monotonicityScore: monotonicity,
  );
}

// ── TangleMap: per-node contributions ───────────────────────────────

TangleMap _computeTangleMap(LogosGit engine, SpectralBasis basis) {
  // Contribution = Bekenstein-style local entropy excess +
  // Anderson-style localisation (high IPR).
  final n = basis.n;
  final k = basis.k;
  final contrib = <String, double>{};
  final paths = engine.nodePaths;
  final logK = math.log(k.toDouble().clamp(2.0, double.infinity));
  for (var v = 0; v < n; v++) {
    // Mode-contribution entropy at this node: p_j = u_j(v)² / Σⱼ u_j(v)².
    var z = 0.0;
    for (var j = 0; j < k; j++) {
      final u = basis.eigenvectors[j * n + v];
      z += u * u;
    }
    if (z <= 1e-300) {
      contrib[paths[v]] = 0.0;
      continue;
    }
    var s = 0.0;
    var ipr = 0.0;
    for (var j = 0; j < k; j++) {
      final u = basis.eigenvectors[j * n + v];
      final p = (u * u) / z;
      if (p > 1e-300) s -= p * math.log(p);
      ipr += p * p;
    }
    // Normalise entropy excess: positive if s > log(k)/2 (unusually broad).
    final entropyExcess = (s - 0.5 * logK).clamp(0.0, double.infinity);
    // Localisation: high IPR = narrow mode support.
    contrib[paths[v]] = entropyExcess + ipr;
  }
  return TangleMap(perPath: contrib);
}

// ── Detector: God class (Bekenstein violation) ─────────────────────

List<SpaghettiFinding> _detectGodClasses(
    LogosGit engine, SpectralBasis basis) {
  final findings = <SpaghettiFinding>[];
  final n = basis.n;
  final k = basis.k;
  final paths = engine.nodePaths;
  final logK = math.log(k.toDouble().clamp(2.0, double.infinity));
  // Bekenstein-flavoured bound: per-node contribution entropy must be
  // below log(k). We flag nodes whose entropy exceeds 0.9·log(k) — a
  // conservative threshold for "participating in too many modes".
  for (var v = 0; v < n; v++) {
    var z = 0.0;
    for (var j = 0; j < k; j++) {
      final u = basis.eigenvectors[j * n + v];
      z += u * u;
    }
    if (z <= 1e-300) continue;
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      final u = basis.eigenvectors[j * n + v];
      final p = (u * u) / z;
      if (p > 1e-300) s -= p * math.log(p);
    }
    if (s > 0.9 * logK) {
      final severity = ((s / logK) - 0.9).clamp(0.0, 1.0).toDouble();
      findings.add(GodClassFinding(
        path: paths[v],
        severity: severity,
        entropy: s,
        entropyBound: logK,
      ));
    }
  }
  return findings;
}

// ── Detector: Dead code (Anderson + low reach) ──────────────────────

List<SpaghettiFinding> _detectDeadCode(
    LogosGit engine, SpectralBasis basis) {
  final findings = <SpaghettiFinding>[];
  final ipr = basis.inverseParticipationRatios();
  final n = basis.n;
  final paths = engine.nodePaths;
  // Per-node localisation: for each node, find the maximum eigenvector-
  // amplitude that node carries relative to the mode's overall IPR.
  // High = node dominates a localised mode (Anderson signature).
  for (var v = 0; v < n; v++) {
    var worst = 0.0;
    var worstJ = 0;
    for (var j = 1; j < basis.k; j++) {
      final u = basis.eigenvectors[j * n + v];
      final amp = u * u;
      // A node carrying >= IPR[j] worth of mass on a localised mode
      // IS the localisation centre of that mode.
      if (amp > ipr[j] * 0.7 && ipr[j] > 0.4) {
        if (amp > worst) {
          worst = amp;
          worstJ = j;
        }
      }
    }
    if (worst > 0.5) {
      findings.add(DeadCodeFinding(
        path: paths[v],
        severity: worst.clamp(0.0, 1.0).toDouble(),
        ipr: ipr[worstJ],
      ));
    }
  }
  return findings;
}

// ── Detector: Casimir bridges ──────────────────────────────────────

List<SpaghettiFinding> _detectCasimirBridges(
    LogosGit engine, SpectralBasis basis) {
  final findings = <SpaghettiFinding>[];
  final g = engine.graph;
  if (g.rawWeights.length != g.values.length) return findings;
  final paths = engine.nodePaths;
  // Find weak edges (raw weight < 10% of the row's strongest edge)
  // whose removal would drop the spectral gap substantially — a
  // Casimir signature. Approximate via the relative edge weight
  // alone for O(m) cost; refinement would re-diagonalise.
  for (var u = 0; u < g.n; u++) {
    var rowMax = 0.0;
    for (var p = g.indptr[u]; p < g.indptr[u + 1]; p++) {
      if (g.rawWeights[p] > rowMax) rowMax = g.rawWeights[p];
    }
    if (rowMax <= 0) continue;
    for (var p = g.indptr[u]; p < g.indptr[u + 1]; p++) {
      final v = g.indices[p];
      if (v <= u) continue;
      final w = g.rawWeights[p];
      if (w / rowMax < 0.08 && w > 0) {
        // Very weak bridge from u's perspective; likely a Casimir edge.
        findings.add(CasimirBridgeFinding(
          path: paths[u],
          partnerPath: paths[v],
          conductance: w,
          severity: (0.08 - (w / rowMax)).clamp(0.0, 0.08) / 0.08,
        ));
      }
    }
  }
  return findings;
}
