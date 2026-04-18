// SPECTRAL RICCI — Ollivier-Ricci edge curvature field.
//
//   κ(u, v) = 1 − W₁(μ_u, μ_v) / d(u, v)
//
// where μ_u is the one-hop random-walk distribution from u, W₁ is
// the 1-Wasserstein distance, and d is graph hop-count distance.
// Negative κ marks bottleneck / bridge edges; positive κ marks
// locally tree-like / community edges; κ ≈ 0 is expander-like.
//
// W₁ is optimal transport. Exact LP is O(n³) per edge; this module
// uses Sinkhorn-Knopp entropic regularisation — matrix-vector only,
// O(d_u · d_v · K_iter). Sinkhorn is run in LOG DOMAIN
// (log-sum-exp) to stay numerically honest on costs much larger
// than epsilon, where raw-domain would underflow.
//
// Empirical reference: `tmp_ice_walls.py §3` — on a dumbbell graph,
// bridge edges score κ ≈ −1.4 while off-bridge edges score κ ≈ +0.44.
// A ~1.87 separation. Fiedler sees the global gap but cannot point
// at which edges carry the bottleneck; Ricci can.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';
import 'logos_signature.dart';

/// Immutable Ollivier-Ricci curvature field over the edges of a graph.
/// Stored as parallel (u, v, κ) arrays plus a signature hash over the
/// curvature values. Edges are in canonical order `u < v`.
class RicciField {
  RicciField({
    required this.graphSignatureHint,
    required this.edgeU,
    required this.edgeV,
    required this.curvatures,
    Signature? signature,
  })  : assert(edgeU.length == edgeV.length),
        assert(edgeU.length == curvatures.length),
        signature = signature ?? _fingerprintFloat64(curvatures);

  /// Hint of the underlying graph's identity — we don't have a
  /// `CsrGraph.signature` yet, so this is a caller-supplied tag
  /// (usually the SpectralBasis signature of the same graph, or
  /// [Signature.zero]).
  final Signature graphSignatureHint;

  /// Parallel edge endpoints (u, v) with u < v.
  final Int32List edgeU;
  final Int32List edgeV;

  /// Signed Ollivier-Ricci curvature, one per edge.
  final Float64List curvatures;

  /// FNV-style hash over curvature bit patterns. Two fields with
  /// identical curvature vectors compare equal.
  final Signature signature;

  int get length => edgeU.length;

  /// Minimum curvature — the deepest bottleneck. Also known as the
  /// graph's "Ricci depth." A negative depth signals the presence of
  /// at least one edge acting as a bridge.
  double get depth {
    if (curvatures.isEmpty) return 0.0;
    var m = curvatures[0];
    for (var i = 1; i < curvatures.length; i++) {
      if (curvatures[i] < m) m = curvatures[i];
    }
    return m;
  }

  double get max {
    if (curvatures.isEmpty) return 0.0;
    var m = curvatures[0];
    for (var i = 1; i < curvatures.length; i++) {
      if (curvatures[i] > m) m = curvatures[i];
    }
    return m;
  }

  double get mean {
    if (curvatures.isEmpty) return 0.0;
    var s = 0.0;
    for (var i = 0; i < curvatures.length; i++) {
      s += curvatures[i];
    }
    return s / curvatures.length;
  }

  /// Ricci surgery fragmentation — at each curvature threshold [θ],
  /// drop every edge with `κ ≤ θ` and report the resulting
  /// `(threshold, n_components, largest_fraction)` on the graph
  /// defined by [graphNodeCount] nodes and this field's `(edgeU, edgeV)`.
  ///
  /// Theory: Ollivier-Ricci is negative on bridge-like edges (see
  /// `mostNegativeEdges`), so raising θ from very negative up through
  /// zero surfaces the graph's community structure one bottleneck at
  /// a time. The surgery curve is the **Ricci analogue** of
  /// [CsrGraph.fragmentationCurve]: fragmentation-by-edge-weight says
  /// "at what coupling does this decompose?"; fragmentation-by-Ricci
  /// says "along which structural bottlenecks does it decompose?"
  ///
  /// Cost: `O(|thresholds| · (n + edges))` via union-find. Edges are
  /// iterated once per threshold; we don't pre-sort because typical
  /// threshold lists are short (3–10 entries).
  ///
  /// Empirical reference: `tmp_ice_walls_deeper.py §6` — on a 3-block
  /// SBM (sizes 7/6/11), a single θ ≈ +0.10 cut decomposes the graph
  /// into components matching the planted block structure.
  ///
  /// Returns records with the same shape as [CsrGraph.fragmentationCurve]
  /// for consistency between the two surgery families.
  /// See [CsrGraph.fragmentationCurve] for the meaning of each field,
  /// including `cycleRank` (β₁ of the surviving 1-skeleton).
  List<FragmentationRow> surgeryFragmentation(
    int graphNodeCount,
    List<double> thresholds,
  ) {
    return [
      for (final theta in thresholds)
        computeFragmentationRow(
          n: graphNodeCount,
          threshold: theta,
          sweepEdges: (emit) {
            for (var ei = 0; ei < curvatures.length; ei++) {
              if (curvatures[ei] <= theta) continue;
              emit(edgeU[ei], edgeV[ei]);
            }
          },
        )
    ];
  }

  /// **One step of discrete Ricci flow** on the graph that produced
  /// this field. Returns a new [CsrGraph] with edge weights updated
  /// according to the Hamilton-Ricci flow analogue:
  ///
  ///     W_{uv}(t + Δt) = W_{uv}(t) · (1 − Δt · κ_{uv})
  ///
  /// Positive-κ edges (community/expander) get **weaker**;
  /// negative-κ edges (bridges/bottlenecks) get **stronger**. The
  /// flow is a contraction on curvature: iterate enough steps and
  /// the graph evolves toward a curvature-balanced state where
  /// every edge carries the same κ.
  ///
  /// ## The repo interpretation
  ///
  /// "What does this codebase look like if you let its coupling
  /// self-adjust under its own curvature-stress for Δt?" Bridges
  /// between loosely-coupled modules get reinforced; redundant
  /// coupling inside tight communities gets slackened. The
  /// equilibrium is the repo's **natural balance** — what the
  /// architecture "wants" to be structurally.
  ///
  /// ## Caveats
  ///
  /// * Output values are clamped to `[0, +∞)` — a single step
  ///   cannot flip an edge negative. For stability, keep Δt small
  ///   relative to `1 / max|κ|`.
  /// * The updated graph preserves CSR topology (edge count and
  ///   node count unchanged); only [CsrGraph.values] changes.
  /// * Rank-one update metadata (`rawWeights`, `degreeInvSqrt`) is
  ///   *not* carried through — the caller rebuilds if needed.
  ///
  /// Empirical reference: `tmp_ice_walls_deeper.py §2` — on a
  /// dumbbell, one Ricci-flow step raises the bridge from κ ≈ −1.4
  /// toward 0 over ~14 iterations at Δt = 0.1.
  CsrGraph ricciFlowStep(CsrGraph graph, {double dt = 0.1}) {
    if (graph.indptr.length != edgeU.length + 1 &&
        graph.values.length != edgeU.length * 2) {
      // Graph encodes each undirected edge twice; fields store each once.
    }
    final newValues = Float64List.fromList(graph.values);
    // Build a quick (u, v) → curvature lookup.
    final curvLookup = <int, double>{};
    for (var ei = 0; ei < edgeU.length; ei++) {
      final a = edgeU[ei], b = edgeV[ei];
      curvLookup[_pairKey(a, b)] = curvatures[ei];
      curvLookup[_pairKey(b, a)] = curvatures[ei];
    }
    for (var u = 0; u < graph.n; u++) {
      for (var p = graph.indptr[u]; p < graph.indptr[u + 1]; p++) {
        final v = graph.indices[p];
        final kappa = curvLookup[_pairKey(u, v)];
        if (kappa == null) continue;
        final factor = 1.0 - dt * kappa;
        final updated = graph.values[p] * factor;
        newValues[p] = updated < 0 ? 0 : updated;
      }
    }
    return CsrGraph(
      n: graph.n,
      indptr: graph.indptr,
      indices: graph.indices,
      values: newValues,
    );
  }

  /// Return the `k` most negative (bridge-like) edges as (u, v, κ)
  /// triples, sorted most negative first. For ranking review salience
  /// / refactor candidates.
  List<(int, int, double)> mostNegativeEdges({int k = 10}) {
    final n = curvatures.length;
    if (n == 0) return const [];
    final indices = List<int>.generate(n, (i) => i);
    indices.sort((a, b) => curvatures[a].compareTo(curvatures[b]));
    final limit = k < n ? k : n;
    return [
      for (var i = 0; i < limit; i++)
        (edgeU[indices[i]], edgeV[indices[i]], curvatures[indices[i]])
    ];
  }

  /// Look up the curvature of a specific edge. Returns null when the
  /// edge isn't in the field.
  double? curvatureOf(int u, int v) {
    final lo = u < v ? u : v;
    final hi = u < v ? v : u;
    // Linear scan — fine for small fields. For hot-path lookups a
    // pre-built Map<int, double> keyed by `lo * n + hi` would be
    // O(1); deferred until the field has a consumer that needs it.
    for (var i = 0; i < edgeU.length; i++) {
      if (edgeU[i] == lo && edgeV[i] == hi) return curvatures[i];
    }
    return null;
  }

  /// Eager: compute the Ollivier-Ricci field of every edge in [graph]
  /// via Sinkhorn-Knopp entropic regularization for the Wasserstein-1
  /// inner problem.
  ///
  /// **Cost warning.** Materialises an all-pairs hop-count matrix of
  /// size `n²` as `Int32List`. For n=5000 that's ~100 MB; for n=10000
  /// it's ~400 MB. This factory is the right path for tests, offline
  /// analysis, or full-field UI overlays on small graphs. For a UI
  /// that only needs a handful of edges at a time, use
  /// [RicciField.curvatureOfEdge] instead — it runs a bounded local
  /// BFS per query and avoids the n² allocation entirely.
  ///
  /// Parameters:
  /// - [epsilon] — entropic regularization strength. Smaller values
  ///   approach the true W₁ more closely but converge slower. Sinkhorn
  ///   runs in log domain so `C/epsilon` can be arbitrarily large
  ///   without underflow.
  /// - [iterations] — number of Sinkhorn iterations per edge. 100 is
  ///   overkill for most graphs but cheap.
  /// - [graphSignatureHint] — opaque tag carried through to the
  ///   field's [graphSignatureHint] so consumers can invalidate
  ///   cached fields when the graph changes.
  factory RicciField.sinkhorn(
    CsrGraph graph, {
    double epsilon = 0.05,
    int iterations = 100,
    Signature graphSignatureHint = Signature.zero,
  }) {
    final n = graph.n;
    final ptr = graph.indptr;
    final idx = graph.indices;
    final vals = graph.values;

    // ── 1. Collect edges in canonical order (u < v). ────────────────
    final edgeU = <int>[];
    final edgeV = <int>[];
    for (var u = 0; u < n; u++) {
      for (var p = ptr[u]; p < ptr[u + 1]; p++) {
        final v = idx[p];
        if (u < v && vals[p] != 0.0) {
          edgeU.add(u);
          edgeV.add(v);
        }
      }
    }

    // ── 2. Hop-count shortest-path distances via multi-source BFS. ──
    final dist = _allPairsHopCount(graph);

    // ── 3. Per-edge Sinkhorn OT. ────────────────────────────────────
    final curv = Float64List(edgeU.length);
    for (var ei = 0; ei < edgeU.length; ei++) {
      final u = edgeU[ei];
      final v = edgeV[ei];
      final (nbU, wU) = _neighborDist(graph, u);
      final (nbV, wV) = _neighborDist(graph, v);
      if (nbU.isEmpty || nbV.isEmpty) {
        curv[ei] = 0.0;
        continue;
      }
      final C = _costMatrix(nbU, nbV, dist, n);
      final w1 = _sinkhornW1(wU, wV, C, epsilon: epsilon, iterations: iterations);
      final duv = dist[u * n + v];
      final effectiveD = duv > 0 ? duv.toDouble() : 1.0;
      curv[ei] = 1.0 - w1 / effectiveD;
    }

    return RicciField(
      graphSignatureHint: graphSignatureHint,
      edgeU: Int32List.fromList(edgeU),
      edgeV: Int32List.fromList(edgeV),
      curvatures: curv,
    );
  }

  /// Compute Ollivier-Ricci curvature for a single edge (u, v) without
  /// building the full field. Uses a local BFS from the neighborhood
  /// of u and v out to [maxHops] steps, building a local distance
  /// matrix just for those nodes. O((|N(u)| + |N(v)|) * local graph)
  /// in the worst case; with a 2-3 hop cap it's O(local degree²)
  /// typically.
  ///
  /// Returns null when the edge doesn't exist or has zero weight.
  static double? curvatureOfEdge(
    CsrGraph graph,
    int u,
    int v, {
    double epsilon = 0.05,
    int iterations = 100,
    int maxHops = 4,
  }) {
    // Verify the edge exists with non-zero weight.
    final ptr = graph.indptr;
    final idx = graph.indices;
    final vals = graph.values;
    var edgeExists = false;
    for (var p = ptr[u]; p < ptr[u + 1]; p++) {
      if (idx[p] == v && vals[p] != 0.0) {
        edgeExists = true;
        break;
      }
    }
    if (!edgeExists) return null;

    // ── 1. One-hop neighbor distributions of u and v. ───────────────
    final (nbU, wU) = _neighborDist(graph, u);
    final (nbV, wV) = _neighborDist(graph, v);
    if (nbU.isEmpty || nbV.isEmpty) return null;

    // ── 2. Collect the local node set: N(u) ∪ N(v). ─────────────────
    final localSet = <int>{...nbU, ...nbV};

    // ── 3. BFS from every node in the local set up to maxHops. ──────
    // localDist[node] is a map: target → hop count.
    // We only need distances among nodes in localSet.
    final localDistMap = <int, Map<int, int>>{};
    for (final src in localSet) {
      localDistMap[src] = _localBFS(graph, src, maxHops);
    }

    // ── 4. Compute d(u, v) via local BFS from u. ────────────────────
    // The direct edge exists (checked above), so hop count is always 1
    // unless the CSR encodes a filtered graph. Use BFS to be safe.
    final uvDist = _localBFS(graph, u, maxHops)[v] ?? 1;

    // ── 5. Build cost matrix over N(u) × N(v). ──────────────────────
    // Reuse already-computed localDistMap; if a source isn't cached,
    // run a fresh BFS.
    final m = nbU.length;
    final k = nbV.length;
    final C = Float64List(m * k);
    for (var i = 0; i < m; i++) {
      final srcDist = localDistMap[nbU[i]] ?? _localBFS(graph, nbU[i], maxHops);
      for (var j = 0; j < k; j++) {
        final d = srcDist[nbV[j]];
        C[i * k + j] = d != null ? d.toDouble() : 1e6;
      }
    }

    // ── 6. Log-domain Sinkhorn and Ricci formula. ────────────────────
    final w1 = _sinkhornW1(wU, wV, C, epsilon: epsilon, iterations: iterations);
    final effectiveD = uvDist > 0 ? uvDist.toDouble() : 1.0;
    return 1.0 - w1 / effectiveD;
  }
}

// ── Internals ──────────────────────────────────────────────────────

/// One-hop lazy walk distribution: μ_u[w] = weight(u,w) / sum of
/// weights at u. Returns (neighbor ids, probabilities) with matching
/// lengths.
(List<int>, Float64List) _neighborDist(CsrGraph graph, int u) {
  final ptr = graph.indptr;
  final idx = graph.indices;
  final vals = graph.values;
  final start = ptr[u];
  final end = ptr[u + 1];
  final nbrs = <int>[];
  final ws = <double>[];
  var total = 0.0;
  for (var p = start; p < end; p++) {
    final v = idx[p];
    final w = vals[p];
    if (w <= 0.0) continue;
    nbrs.add(v);
    ws.add(w);
    total += w;
  }
  if (total <= 0.0) {
    return (const [], Float64List(0));
  }
  final out = Float64List(ws.length);
  final inv = 1.0 / total;
  for (var i = 0; i < ws.length; i++) {
    out[i] = ws[i] * inv;
  }
  return (nbrs, out);
}

/// Cost matrix of hop-count distances between neighbor sets,
/// flattened row-major. `flat[i * lenV + j] = dist[nbU[i], nbV[j]]`.
Float64List _costMatrix(List<int> nbU, List<int> nbV, Int32List dist, int n) {
  final m = nbU.length;
  final k = nbV.length;
  final out = Float64List(m * k);
  for (var i = 0; i < m; i++) {
    final rowBase = nbU[i] * n;
    final outBase = i * k;
    for (var j = 0; j < k; j++) {
      final d = dist[rowBase + nbV[j]];
      out[outBase + j] = d == _hopUnreachable ? 1e6 : d.toDouble();
    }
  }
  return out;
}

/// Numerically stable log-sum-exp over a list of log-domain values.
/// Subtracts the max before exponentiating to avoid overflow/underflow.
/// Returns -inf when [logVals] is empty or all values are -inf.
double _logSumExp(List<double> logVals) {
  if (logVals.isEmpty) return double.negativeInfinity;
  var maxVal = double.negativeInfinity;
  for (final x in logVals) {
    if (x > maxVal) maxVal = x;
  }
  if (maxVal == double.negativeInfinity) return double.negativeInfinity;
  var sum = 0.0;
  for (final x in logVals) {
    sum += math.exp(x - maxVal);
  }
  return maxVal + math.log(sum);
}

/// Log-domain Sinkhorn-Knopp entropic Wasserstein-1 distance.
///
/// Keeps log_u and log_v to avoid underflow when C_ij / epsilon >> 1.
/// Update rules:
///   log K_ij  = -C_ij / eps
///   log_v_j   = log ν_j − logsumexp_i(log K_ij + log_u_i)
///   log_u_i   = log μ_i − logsumexp_j(log K_ij + log_v_j)
///   T_ij      = exp(log_u_i + log K_ij + log_v_j)
///   W₁        ≈ Σ_ij T_ij · C_ij
///
/// Zero masses in mu/nu are mapped to -inf in log space.
double _sinkhornW1(
  Float64List mu,
  Float64List nu,
  Float64List C, {
  required double epsilon,
  required int iterations,
}) {
  final m = mu.length;
  final k = nu.length;

  // Precompute log K (static per call).
  final logK = Float64List(m * k);
  for (var i = 0; i < m * k; i++) {
    logK[i] = -C[i] / epsilon;
  }

  // Log-domain scaling vectors; init to 0 (i.e. u_i = 1, v_j = 1).
  final logU = Float64List(m); // log u_i, init 0
  final logV = Float64List(k); // log v_j, init 0

  // Precompute log mu and log nu; handle zero mass as -inf.
  final logMu = Float64List(m);
  final logNu = Float64List(k);
  for (var i = 0; i < m; i++) {
    logMu[i] = mu[i] > 0.0 ? math.log(mu[i]) : double.negativeInfinity;
  }
  for (var j = 0; j < k; j++) {
    logNu[j] = nu[j] > 0.0 ? math.log(nu[j]) : double.negativeInfinity;
  }

  final scratch = <double>[];
  for (var it = 0; it < iterations; it++) {
    // Update log_v_j = log nu_j − logsumexp_i(log K_ij + log_u_i)
    for (var j = 0; j < k; j++) {
      scratch.clear();
      for (var i = 0; i < m; i++) {
        final lku = logK[i * k + j] + logU[i];
        if (lku.isFinite) scratch.add(lku);
      }
      final lse = scratch.isEmpty ? double.negativeInfinity : _logSumExp(scratch);
      logV[j] = logNu[j] == double.negativeInfinity
          ? double.negativeInfinity
          : logNu[j] - lse;
    }
    // Update log_u_i = log mu_i − logsumexp_j(log K_ij + log_v_j)
    for (var i = 0; i < m; i++) {
      scratch.clear();
      for (var j = 0; j < k; j++) {
        final lkv = logK[i * k + j] + logV[j];
        if (lkv.isFinite) scratch.add(lkv);
      }
      final lse = scratch.isEmpty ? double.negativeInfinity : _logSumExp(scratch);
      logU[i] = logMu[i] == double.negativeInfinity
          ? double.negativeInfinity
          : logMu[i] - lse;
    }
  }

  // W₁ ≈ Σ_ij T_ij · C_ij  where T_ij = exp(log_u_i + log K_ij + log_v_j).
  var w = 0.0;
  for (var i = 0; i < m; i++) {
    for (var j = 0; j < k; j++) {
      final logT = logU[i] + logK[i * k + j] + logV[j];
      if (logT.isFinite) {
        w += math.exp(logT) * C[i * k + j];
      }
    }
  }
  return w;
}

const int _hopUnreachable = 1 << 30;

/// All-pairs hop-count distances (ignoring edge weights). Stored
/// row-major in a length-n² Int32List. Uses multi-source BFS; O(n·(n+m)).
Int32List _allPairsHopCount(CsrGraph graph) {
  final n = graph.n;
  final ptr = graph.indptr;
  final idx = graph.indices;
  final vals = graph.values;
  final out = Int32List(n * n);
  out.fillRange(0, n * n, _hopUnreachable);
  final queue = Int32List(n);
  for (var src = 0; src < n; src++) {
    var head = 0;
    var tail = 0;
    out[src * n + src] = 0;
    queue[tail++] = src;
    while (head < tail) {
      final u = queue[head++];
      final d = out[src * n + u];
      for (var p = ptr[u]; p < ptr[u + 1]; p++) {
        final v = idx[p];
        if (vals[p] <= 0.0) continue;
        if (out[src * n + v] == _hopUnreachable) {
          out[src * n + v] = d + 1;
          queue[tail++] = v;
        }
      }
    }
  }
  return out;
}

/// BFS from [src] up to [maxHops] steps. Returns a map from reachable
/// node id to hop-count distance. Only traverses edges with positive weight.
Map<int, int> _localBFS(CsrGraph graph, int src, int maxHops) {
  final ptr = graph.indptr;
  final idx = graph.indices;
  final vals = graph.values;
  final dist = <int, int>{src: 0};
  final queue = <int>[src];
  var head = 0;
  while (head < queue.length) {
    final u = queue[head++];
    final d = dist[u]!;
    if (d >= maxHops) continue;
    for (var p = ptr[u]; p < ptr[u + 1]; p++) {
      final v = idx[p];
      if (vals[p] <= 0.0) continue;
      if (!dist.containsKey(v)) {
        dist[v] = d + 1;
        queue.add(v);
      }
    }
  }
  return dist;
}

Signature _fingerprintFloat64(Float64List values) => fingerprintFloat64(values);

int _pairKey(int a, int b) => a * 0x10000 + b;
