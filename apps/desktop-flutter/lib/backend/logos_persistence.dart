// LogosPersistence — persistent homology on the coupling filtration.
//
// We sweep a decreasing coupling threshold θ from max(weight) down to
// 0. As θ falls, edges of the graph enter one at a time (highest-weight
// first). Two topological features of the 1-skeleton evolve:
//
//   * **β₀** (connected components) — decreases by one every time an
//     edge merges two previously-disconnected components.
//   * **β₁** (independent cycles) — increases by one every time an edge
//     is added between two already-connected nodes.
//
// Each event opens or closes a "bar" in the persistence diagram:
//
//   * Merge event: a β₀ class **dies** at weight `w`. Its bar runs from
//     birth at θ = 1 (all nodes present from the start of the filtration,
//     in normalised coupling-distance coordinates `t = 1 − w/wMax`) to
//     death at `w`. One component — the "eldest" by size per the
//     standard elder rule — survives; the younger one closes its bar.
//   * Cycle-closing event: a β₁ class is **born** at weight `w`. In the
//     1-skeleton, β₁ features never die, so the bar is essential.
//
// What you get: a persistence diagram that summarises the repo's entire
// topological history under a decoupling sweep in one data structure.
// Three derived scalars are enough to rank repos against each other:
//
//   * **totalPersistence** — Σ (birth − death) over finite pairs. Large
//     when the repo has many long-lived isolated subsystems.
//   * **maxPersistence** — the single longest-lived finite feature.
//   * **persistenceEntropy** — Shannon entropy of normalised
//     persistences. Low ≈ 0 when one feature dominates; high → log(k)
//     when persistence is spread uniformly across k features.
//
// Unlike `fragmentationCurve` (which samples β₀/β₁ at a grid of
// thresholds), a persistence diagram records the EXACT threshold of
// every merge/birth event — a single-linkage dendrogram falls out for
// free from the β₀ bars.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';

/// A single (birth, death) pair in the persistence diagram.
///
/// Coordinates are the **normalised filtration parameter** `t ∈ [0, 1]`:
/// `t = 1 − w/wMax`, where `wMax` is the largest edge weight in the
/// graph. So `t = 0` corresponds to the tightest coupling; `t = 1`
/// corresponds to fully decoupled.
///
/// * For β₀ (components): `birth = 0` (every node is present from
///   t = 0), `death = 1 − wMerge/wMax`. A component that merges at a
///   tight coupling (high `wMerge`) has a short bar; one that survives
///   to very loose coupling (low `wMerge`) has a long bar. The one
///   component that survives to `t = 1` is flagged [essential].
/// * For β₁ (cycles): `birth = 1 − wCycle/wMax`, `death = 1` (never
///   dies in a 1-skeleton). All β₁ pairs are [essential]; their
///   "persistence" is recorded as `1 − birth` for ranking.
class PersistencePair {
  /// Homology dimension: `0` for components, `1` for cycles.
  final int dimension;

  /// Birth time in `[0, 1]`.
  final double birth;

  /// Death time in `[0, 1]`, or `double.infinity` for essential pairs.
  final double death;

  /// `true` when the feature never dies within the filtration window
  /// (the one surviving β₀ class + every β₁ class in a 1-skeleton).
  final bool essential;

  const PersistencePair({
    required this.dimension,
    required this.birth,
    required this.death,
    required this.essential,
  });

  /// Length of the persistence bar. Essentials report `double.infinity`.
  double get persistence {
    if (essential) return double.infinity;
    return (death - birth).abs();
  }

  @override
  String toString() => 'Pair(β${dimension == 0 ? '₀' : '₁'}, '
      '${birth.toStringAsFixed(3)}→'
      '${essential ? "∞" : death.toStringAsFixed(3)})';
}

/// Summary of a persistence diagram.
class PersistenceDiagram {
  /// Every pair emitted during the sweep — finite β₀ merges followed by
  /// essential β₀ (one per eventual connected component) followed by
  /// essential β₁ (one per independent cycle surviving at `t = 1`).
  final List<PersistencePair> pairs;

  /// Sum of finite persistences across all dimensions.
  final double totalPersistence;

  /// Longest finite bar. `0.0` when every pair is essential.
  final double maxPersistence;

  /// Shannon entropy of normalised finite persistences. Low → one
  /// dominant feature; high → persistence spread uniformly.
  final double persistenceEntropy;

  /// Normalisation factor used for the filtration: `wMax` before mapping
  /// to `t = 1 − w/wMax`. Useful for callers that want to map birth /
  /// death values back to raw edge-weight coordinates.
  final double wMax;

  const PersistenceDiagram({
    required this.pairs,
    required this.totalPersistence,
    required this.maxPersistence,
    required this.persistenceEntropy,
    required this.wMax,
  });

  /// Number of connected components at the end of the filtration
  /// (`t = 1`, θ = 0). Equal to the number of essential β₀ bars.
  int get finalComponents =>
      pairs.where((p) => p.dimension == 0 && p.essential).length;

  /// Number of independent cycles at the end of the filtration
  /// (`t = 1`, θ = 0). Equal to the number of essential β₁ bars
  /// (there's no β₁ death in a 1-skeleton).
  int get finalCycles =>
      pairs.where((p) => p.dimension == 1 && p.essential).length;

  /// Finite β₀ bars, sorted longest-first — the most "isolated"
  /// subsystems of the repo in decoupling order.
  List<PersistencePair> get topB0 {
    final b0 = pairs
        .where((p) => p.dimension == 0 && !p.essential)
        .toList()
      ..sort((a, b) => b.persistence.compareTo(a.persistence));
    return b0;
  }
}

/// Compute the persistent homology of the coupling filtration.
///
/// Returns a [PersistenceDiagram] containing every birth/death event
/// as edges are added in decreasing weight order. Cost: `O(m log m)`
/// for the sort plus `O((m + n) · α(n))` for the union-find sweep.
///
/// Returns `null` when `graph.n < 2` or the graph has no edges — the
/// diagram is degenerate in those cases.
PersistenceDiagram? computeCouplingPersistence(CsrGraph graph) {
  final n = graph.n;
  if (n < 2) return null;
  final totalNonZeros = graph.indptr[n];
  if (totalNonZeros == 0) return null;

  // Collect undirected edges (u < v, w) with the fused-normalised
  // weight as the filtration value. Using `values` directly (the fused
  // D^{-1/2}·W·D^{-1/2} coefficients) keeps the persistence diagram
  // consistent with the rest of the engine — same coupling strength
  // as everything else in logos_core.
  final edgeU = <int>[];
  final edgeV = <int>[];
  final edgeW = <double>[];
  for (var u = 0; u < n; u++) {
    final p0 = graph.indptr[u];
    final p1 = graph.indptr[u + 1];
    for (var p = p0; p < p1; p++) {
      final v = graph.indices[p];
      if (v <= u) continue; // undirected — take each edge once
      final w = graph.values[p];
      if (!w.isFinite || w <= 0) continue;
      edgeU.add(u);
      edgeV.add(v);
      edgeW.add(w);
    }
  }
  final m = edgeU.length;
  if (m == 0) return null;

  // Weight normalisation — map wMax to birthDistance = 0 so the
  // filtration parameter `t = 1 − w/wMax` sits cleanly in [0, 1].
  var wMax = edgeW[0];
  for (var i = 1; i < m; i++) {
    if (edgeW[i] > wMax) wMax = edgeW[i];
  }
  if (wMax <= 0 || !wMax.isFinite) return null;

  // Sort edge indices by weight descending. Using an index-sort keeps
  // all three arrays in sync without a permutation pass.
  final order = List<int>.generate(m, (i) => i);
  order.sort((a, b) => edgeW[b].compareTo(edgeW[a]));

  // Union-find with size-based elder rule. The *larger* component
  // "absorbs" the smaller; the smaller's β₀ class dies at this weight.
  final parent = Int32List(n);
  final size = Int32List(n);
  for (var i = 0; i < n; i++) {
    parent[i] = i;
    size[i] = 1;
  }
  int find(int x) {
    var root = x;
    while (parent[root] != root) {
      root = parent[root];
    }
    var cur = x;
    while (parent[cur] != root) {
      final next = parent[cur];
      parent[cur] = root;
      cur = next;
    }
    return root;
  }

  final pairs = <PersistencePair>[];

  for (final idx in order) {
    final w = edgeW[idx];
    final t = 1.0 - (w / wMax); // filtration parameter for this edge
    final ru = find(edgeU[idx]);
    final rv = find(edgeV[idx]);
    if (ru == rv) {
      // Cycle-closing edge → β₁ birth, essential bar.
      pairs.add(PersistencePair(
        dimension: 1,
        birth: t,
        death: double.infinity,
        essential: true,
      ));
    } else {
      // Merge event → a β₀ class dies at t.
      pairs.add(PersistencePair(
        dimension: 0,
        birth: 0.0,
        death: t,
        essential: false,
      ));
      // Elder rule — smaller tree joins larger; on ties break by id.
      if (size[ru] < size[rv]) {
        parent[ru] = rv;
        size[rv] += size[ru];
      } else {
        parent[rv] = ru;
        size[ru] += size[rv];
      }
    }
  }

  // Essential β₀ classes — one per final connected component.
  final seen = <int>{};
  for (var i = 0; i < n; i++) {
    final r = find(i);
    if (seen.add(r)) {
      pairs.add(const PersistencePair(
        dimension: 0,
        birth: 0.0,
        death: double.infinity,
        essential: true,
      ));
    }
  }

  // Derived scalars over the finite bars. Large repos produce
  // thousands of persistence pairs; naive accumulation loses low-bit
  // precision as the running sum grows. Kahan compensation (Principia
  // Circle XI) keeps error bounded independent of N at ~zero cost.
  var total = 0.0;
  var totalComp = 0.0; // ghost accumulator — absorbs rounding residue
  var maxP = 0.0;
  final finiteLifespans = <double>[];
  for (final p in pairs) {
    if (p.essential) continue;
    final lp = p.persistence;
    if (!lp.isFinite || lp <= 0) continue;
    finiteLifespans.add(lp);
    // Kahan step: re-inject lost low-order bits before adding.
    final y = lp - totalComp;
    final t = total + y;
    totalComp = (t - total) - y;
    total = t;
    if (lp > maxP) maxP = lp;
  }
  // Entropy — shorter sum but still worth guarding.
  double entropy = 0.0;
  if (total > 1e-300 && finiteLifespans.length > 1) {
    var entComp = 0.0;
    for (final lp in finiteLifespans) {
      final pi = lp / total;
      if (pi > 1e-300) {
        final term = -pi * math.log(pi);
        final y = term - entComp;
        final t = entropy + y;
        entComp = (t - entropy) - y;
        entropy = t;
      }
    }
  }

  return PersistenceDiagram(
    pairs: pairs,
    totalPersistence: total,
    maxPersistence: maxP,
    persistenceEntropy: entropy,
    wMax: wMax,
  );
}
