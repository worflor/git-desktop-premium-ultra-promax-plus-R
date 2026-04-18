// LogosSensitivity — Hellmann-Feynman derivatives of observables
// with respect to edge-weight perturbations.
//
// The engine's observables (heatTrace, zeta, logDet, ...) are
// functions of the Laplacian spectrum; the spectrum is a function of
// the graph's edge weights. For every (observable, edge) pair there
// is a CLOSED-FORM derivative that tells us "if I nudge this edge's
// weight by δw, how much does this observable change?" — without
// re-running Lanczos.
//
// The fundamental identity is Hellmann-Feynman:
//     dλⱼ/dθ = ⟨uⱼ, (∂L/∂θ) uⱼ⟩
// for any parameter θ that appears in L, evaluated at fixed uⱼ.
// Applied to a single-edge weight perturbation in the combinatorial
// Laplacian L_comb = D − W, the right-hand side collapses to
//     dλⱼ/dw_{ab} = (uⱼ[a] − uⱼ[b])².
//
// This module exposes two API levels:
//
//   1. **Per-edge functions** (this file's top section) for single-
//      query questions: "what's the sensitivity of *this one edge*?"
//      Each is a direct O(k) computation. No caching needed.
//
//   2. **[SensitivityField]** (bottom section) for full-graph queries
//      that need every edge's sensitivity sorted by magnitude. One
//      class bound to a (graph, basis) pair. The eigenvector
//      transpose is built once on first access and reused. Each
//      observable's full field is computed once on first call and
//      cached — subsequent calls on the same field return the same
//      sorted list without rescanning.
//
// Taxonomy:
//   * The per-eigenvalue formula is **Theorem-tight** on the
//     combinatorial Laplacian.
//   * For the normalised Laplacian (what the engine stores fused)
//     the same formula is an **Analogy** — exact when the degree
//     vector D is held fixed during the perturbation (fixed-degree
//     approximation). Standard in spectral-sensitivity literature
//     and order-preserving for ranking.
//   * Every observable derivative is **Theorem-tight** given the
//     per-eigenvalue sensitivity.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';

/// Sensitivity of eigenvalue `λⱼ` to a perturbation of edge `(a, b)`:
///     dλⱼ / dw_{ab}  ≈  (uⱼ[a] − uⱼ[b])².
///
/// Returns 0 when `j` is out of range or either node index invalid.
double eigenvalueSensitivity(
    SpectralBasis basis, int a, int b, int j) {
  if (j < 0 || j >= basis.k) return 0.0;
  if (a < 0 || b < 0 || a >= basis.n || b >= basis.n) return 0.0;
  final base = j * basis.n;
  final d = basis.eigenvectors[base + a] - basis.eigenvectors[base + b];
  return d * d;
}

/// Sensitivity of `heatTrace(t)` to edge `(a, b)`:
///     dZ(t) / dw_{ab}  =  −t · Σⱼ e^{−t·λⱼ} · (uⱼ[a] − uⱼ[b])².
///
/// Strictly non-positive — strengthening any edge dissipates heat
/// faster. Magnitude encodes which edges carry the most diffusion
/// mass at temperature `t`.
double heatTraceSensitivity(
    SpectralBasis basis, int a, int b, double t) {
  if (a < 0 || b < 0 || a >= basis.n || b >= basis.n) return 0.0;
  if (!t.isFinite) return 0.0;
  var sum = 0.0;
  for (var j = 0; j < basis.k; j++) {
    final base = j * basis.n;
    final d =
        basis.eigenvectors[base + a] - basis.eigenvectors[base + b];
    final d2 = d * d;
    sum += math.exp(-t * basis.eigenvalues[j]) * d2;
  }
  return -t * sum;
}

/// Sensitivity of `log det' L` to edge `(a, b)`:
///     d(logDet) / dw_{ab}  =  Σ_{λⱼ > 0} (uⱼ[a] − uⱼ[b])² / λⱼ.
///
/// Strictly non-negative.
double logDetSensitivity(SpectralBasis basis, int a, int b) {
  if (a < 0 || b < 0 || a >= basis.n || b >= basis.n) return 0.0;
  final start = basis.firstExcitedIndex;
  final k = basis.k;
  final n = basis.n;
  final eigs = basis.eigenvalues;
  final vecs = basis.eigenvectors;
  var sum = 0.0;
  for (var j = start; j < k; j++) {
    final base = j * n;
    final d = vecs[base + a] - vecs[base + b];
    sum += (d * d) / eigs[j];
  }
  return sum;
}

/// Sensitivity of `ζ(s)` to edge `(a, b)`:
///     dζ(s) / dw_{ab}  =  −s · Σ_{λⱼ > 0} (uⱼ[a] − uⱼ[b])² / λⱼ^{s+1}.
double zetaSensitivity(
    SpectralBasis basis, int a, int b, double s) {
  if (a < 0 || b < 0 || a >= basis.n || b >= basis.n) return 0.0;
  if (!s.isFinite) return 0.0;
  final start = basis.firstExcitedIndex;
  final k = basis.k;
  final n = basis.n;
  final eigs = basis.eigenvalues;
  final vecs = basis.eigenvectors;
  // Circle IV — integer-s fast path without `math.pow`.
  final sAsInt = s.truncate();
  if (s == sAsInt.toDouble()) {
    var sum = 0.0;
    if (sAsInt == 1) {
      for (var j = start; j < k; j++) {
        final lam = eigs[j];
        final base = j * n;
        final d = vecs[base + a] - vecs[base + b];
        sum += (d * d) / (lam * lam);
      }
    } else if (sAsInt == 2) {
      for (var j = start; j < k; j++) {
        final lam = eigs[j];
        final base = j * n;
        final d = vecs[base + a] - vecs[base + b];
        sum += (d * d) / (lam * lam * lam);
      }
    } else {
      for (var j = start; j < k; j++) {
        final lam = eigs[j];
        final base = j * n;
        final d = vecs[base + a] - vecs[base + b];
        sum += (d * d) * math.pow(lam, -s - 1).toDouble();
      }
    }
    return -s * sum;
  }
  var sum = 0.0;
  for (var j = start; j < k; j++) {
    final lam = eigs[j];
    final base = j * n;
    final d = vecs[base + a] - vecs[base + b];
    sum += (d * d) * math.pow(lam, -s - 1).toDouble();
  }
  return -s * sum;
}

/// Sensitivity of the spectral gap (smallest non-zero eigenvalue, λ₁)
/// to edge `(a, b)`: `(u₁[a] − u₁[b])²`.
///
/// Returns `null` on a ground-only basis.
double? spectralGapSensitivity(SpectralBasis basis, int a, int b) {
  if (basis.isGroundOnly) return null;
  return eigenvalueSensitivity(basis, a, b, basis.firstExcitedIndex);
}

// ── Field-level queries ───────────────────────────────────────────
//
// One class, one set of methods, one cache layer. A [SensitivityField]
// represents the full per-edge derivative field of a (graph, basis)
// pair. Each observable's complete ranking is computed once on first
// access and cached. The eigenvector transpose (the cache-geometry
// primitive behind every scan) is also built once lazily.
//
// No sync/async split per observable. No separate top-K path. No
// worker-count knobs. Callers just construct a field and ask what
// they want; repeated queries hit the cache.

/// One row of an edge-sensitivity ranking.
class EdgeSensitivity {
  final int a;
  final int b;
  final double value;

  /// The raw fused edge weight at `(a, b)` at the time of the scan.
  final double weight;

  const EdgeSensitivity({
    required this.a,
    required this.b,
    required this.value,
    required this.weight,
  });

  @override
  String toString() =>
      'EdgeSensitivity($a↔$b, w=$weight, dOdw=$value)';
}

/// Full sensitivity field over a (graph, basis). Lazily computes each
/// observable's complete per-edge ranking on first access and caches
/// it; later calls return the same sorted list without re-scanning.
///
/// The eigenvector matrix is transposed to node-major layout on first
/// use so every inner loop walks memory at stride 1 (Principia Circle
/// XIV: AoSoA-ish). The transpose is also cached across observables
/// — heat-trace and log-det scans on the same basis share it.
///
/// Usage:
/// ```dart
/// final field = SensitivityField(graph, basis);
/// final byGap = field.gap();              // Fiedler-mode ranking
/// final byHeat = field.heatTrace(t: 1.0); // heat-trace ranking
/// final byLog = field.logDet();           // log-det ranking
/// final topTen = field.gap().take(10);    // prefix of cached result
/// ```
///
/// Bind one field per (graph, basis) pair and reuse it across
/// queries. Dropping the reference garbage-collects the cache.
class SensitivityField {
  SensitivityField(this.graph, this.basis);

  final CsrGraph graph;
  final SpectralBasis basis;

  /// Node-major eigenvector layout, lazily built on first observable
  /// access. `_vecsT[u * k + j]` = node `u`'s `j`-th mode value.
  /// Stride-1 across modes for any fixed node → cache-hot inner loops.
  Float64List? _vecsT;

  // Cached observable fields. One entry per distinct observable
  // query. Key is a stable Object (String or Record) keyed by
  // observable kind + parameters.
  final Map<Object, List<EdgeSensitivity>> _cache = {};

  /// Ensure the transpose is built; return it.
  Float64List _transpose() {
    final cached = _vecsT;
    if (cached != null) return cached;
    final k = basis.k;
    final n = basis.n;
    final src = basis.eigenvectors;
    final out = Float64List(n * k);
    for (var j = 0; j < k; j++) {
      final srcBase = j * n;
      for (var i = 0; i < n; i++) {
        out[i * k + j] = src[srcBase + i];
      }
    }
    return _vecsT = out;
  }

  /// Full heat-trace sensitivity field at temperature `t`. Every
  /// edge, sorted by `|dZ/dw|` descending.
  ///
  /// Cached per `t`. Calls with the same `t` return the same list.
  List<EdgeSensitivity> heatTrace({double t = 1.0}) {
    final key = ('heat', t);
    final cached = _cache[key];
    if (cached != null) return cached;
    final k = basis.k;
    final weights = Float64List(k);
    for (var j = 0; j < k; j++) {
      weights[j] = math.exp(-t * basis.eigenvalues[j]);
    }
    final scale = -t;
    final vecsT = _transpose();
    final result = _scan((u, v) {
      final uBase = u * k;
      final vBase = v * k;
      var sum = 0.0;
      for (var j = 0; j < k; j++) {
        final d = vecsT[uBase + j] - vecsT[vBase + j];
        sum += weights[j] * d * d;
      }
      return scale * sum;
    });
    _cache[key] = result;
    return result;
  }

  /// Full log-det sensitivity field. Every edge, sorted by
  /// `|d(logDet)/dw|` descending.
  ///
  /// Cached. Subsequent calls return the same list.
  List<EdgeSensitivity> logDet() {
    const key = 'logDet';
    final cached = _cache[key];
    if (cached != null) return cached;
    final start = basis.firstExcitedIndex;
    final k = basis.k;
    if (k <= start) {
      return _cache[key] = const [];
    }
    final invLambda = Float64List(k);
    for (var j = start; j < k; j++) {
      invLambda[j] = 1.0 / basis.eigenvalues[j];
    }
    final vecsT = _transpose();
    final result = _scan((u, v) {
      final uBase = u * k;
      final vBase = v * k;
      var sum = 0.0;
      for (var j = start; j < k; j++) {
        final d = vecsT[uBase + j] - vecsT[vBase + j];
        sum += invLambda[j] * d * d;
      }
      return sum;
    });
    _cache[key] = result;
    return result;
  }

  /// Full spectral-gap sensitivity field — single-mode (Fiedler)
  /// ranking. Edges with large values are connectivity bottlenecks.
  ///
  /// Returns an empty list on a ground-only basis (no spectral gap
  /// defined). Cached.
  List<EdgeSensitivity> gap() {
    const key = 'gap';
    final cached = _cache[key];
    if (cached != null) return cached;
    if (basis.isGroundOnly) return _cache[key] = const [];
    // Single-mode scan — no need to transpose the whole matrix for
    // one eigenvector. Read directly from the row-major storage.
    final j = basis.firstExcitedIndex;
    final base = j * basis.n;
    final vecs = basis.eigenvectors;
    final result = _scan((u, v) {
      final d = vecs[base + u] - vecs[base + v];
      return d * d;
    });
    _cache[key] = result;
    return result;
  }

  /// Drop all cached observables. The transpose stays cached (it's
  /// a pure function of the basis). Use after the underlying graph
  /// changes — though in that case you should build a new field.
  void invalidate() {
    _cache.clear();
  }

  /// Common scan skeleton — iterates undirected edges, calls
  /// `perEdge` for each, sorts by `|value|` descending.
  List<EdgeSensitivity> _scan(double Function(int u, int v) perEdge) {
    final out = <EdgeSensitivity>[];
    final n = graph.n;
    for (var u = 0; u < n; u++) {
      final p0 = graph.indptr[u];
      final p1 = graph.indptr[u + 1];
      for (var p = p0; p < p1; p++) {
        final v = graph.indices[p];
        if (v <= u) continue;
        out.add(EdgeSensitivity(
          a: u,
          b: v,
          value: perEdge(u, v),
          weight: graph.values[p],
        ));
      }
    }
    out.sort((x, y) => y.value.abs().compareTo(x.value.abs()));
    return out;
  }
}
