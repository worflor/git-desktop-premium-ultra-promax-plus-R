// ═════════════════════════════════════════════════════════════════════════
// LOGOS CORE — shared geometric primitives
// ═════════════════════════════════════════════════════════════════════════
//
// The math substrate every Logos engine in this codebase composes over.
// Three engines (file-graph in `logos_git.dart`, intra-file chunk graph
// in `logos_chunks.dart`, intra-diff hunk graph in `logos_hunks.dart`)
// previously reimplemented the same primitives with slight drift. This
// module is the single source of truth for:
//
//   • Compressed sparse-row graph storage with normalised Laplacian
//     application (`L_sym = I − D^{-1/2} W D^{-1/2}`, fused into the
//     stored values so the matvec is `y = v − W_norm·v`).
//   • Modified Bessel coefficients `c_k(t) = 2·e^{-t}·I_k(-t)` for the
//     heat-kernel Chebyshev expansion. Numerically stable forward
//     recurrence in log-space; NaN-safe; overflow-guarded for any
//     reasonable t.
//   • Adaptive Chebyshev truncation — prune tail terms whose
//     coefficients are below the noise floor.
//   • Heat-kernel diffusion `φ(t) = exp(−t·L_sym)·ρ` — both one-shot
//     ([chebyshevDiffuse]) and basis-cached for multi-temperature
//     recombination ([chebyshevBasis] + [recombineHeatPhi]).
//
// The pattern matches the whisper codec library's `Loup ⊗ Loup` factor-
// isation: shared geometric core, scale-specific composition. Every
// engine here builds its own graph (its own axis blend, its own edge
// construction) and then defers to this module for diffusion.

import 'dart:math' as math;
import 'dart:typed_data';

// ─────────────────────────────────────────────────────────────────────────
// Constants — pinned by the math, not by tuning
// ─────────────────────────────────────────────────────────────────────────

/// Default Chebyshev truncation order. K=20 gives relative error <1e-8
/// on the normalised-Laplacian spectrum [0, 2] for diffusion times
/// t ∈ [0, 10]. Bessel coefficient `|c_k(t)|` decays past `k ≈ e·t/2`
/// (Abramowitz–Stegun asymptotic); for t up to 10 the useful band is
/// `k ≤ 14`, so K=20 leaves comfortable headroom. [adaptiveK] prunes
/// the unused tail at runtime — pure perf win, no accuracy loss.
const int kDefaultChebyshevK = 20;

/// Chebyshev order for the small-graph engines (intra-file chunks,
/// intra-diff hunks). One step above [kDefaultChebyshevK] because
/// smaller graphs can have sharper spectra and the per-call cost of
/// 4 extra matvecs is negligible at adaptive K. Both small-graph
/// engines also use a three-temperature geometric-mean blend, which
/// benefits from the headroom.
const int kChebyshevSmallGraph = 24;

/// Default power-iteration depth for spectral-radius diagnostics.
/// Rayleigh-quotient convergence is geometric at rate `|λ₂/λ₁|`, where
/// `λ₂ < λ₁ ≤ 2` on a normalised Laplacian. 24 iterations gets us 2-3
/// significant figures on any realistic graph.
const int kDefaultPowerIterations = 24;

/// Hard ceiling on diffusion time before the Bessel computation
/// becomes numerically untrustworthy. The recurrence for `I_k(t)` uses
/// `(t/2)^2` per term — at t=30 that's 225 per step, near the f64
/// inner-loop overflow cliff. We clamp inputs to this and document it
/// rather than silently returning NaN.
const double _maxSafeT = 30.0;

/// Cap on the Bessel-series inner loop. The series converges in
/// `O(t)` terms in practice — 200 is well past convergence for t ≤ 30
/// at the [_besselConvergenceEps] floor, and bounds the cost in case
/// the convergence check fails on edge inputs.
const int _besselSeriesTermCap = 200;

/// Convergence floor for the Bessel series summation, measured as a
/// fraction of the running sum. `1e-20` is well below f64 ULP for
/// typical sums in [1e-10, 1e+5].
const double _besselConvergenceEps = 1e-20;

// ─────────────────────────────────────────────────────────────────────────
// CsrGraph — the data structure every engine builds
// ─────────────────────────────────────────────────────────────────────────

/// Compressed sparse-row graph with a fused-D⁻¹ᐟ² edge weight encoding.
///
/// Each engine constructs one of these from its own axis-mixed edge
/// weights, then hands it to the diffusion primitives. The values
/// stored in [values] are already `D^{-1/2}[i] · W[i,j] · D^{-1/2}[j]`
/// — so applying the symmetric normalised Laplacian `L_sym = I − W_norm`
/// reduces to `y[i] = v[i] − Σ_j values[i,j] · v[indices[i,j]]`.
class CsrGraph {
  CsrGraph({
    required this.n,
    required this.indptr,
    required this.indices,
    required this.values,
  });

  /// Number of nodes.
  final int n;

  /// CSR row pointers — `indptr[i]` is the start of row `i`'s edges,
  /// `indptr[n]` is the total non-zero count.
  final Int32List indptr;

  /// CSR column indices for each non-zero edge.
  final Int32List indices;

  /// Pre-fused normalised edge weights (`D^{-1/2}·W·D^{-1/2}`).
  final Float64List values;

  /// Apply `L_sym = I − D^{-1/2} W D^{-1/2}` to vector `v`. Since
  /// [values] is pre-fused with `D^{-1/2}` on both sides, the matvec
  /// is simply `y[i] = v[i] − (W_norm · v)[i]`. `out` is overwritten;
  /// must have length [n].
  void applyLsym(Float64List v, Float64List out) {
    for (var i = 0; i < n; i++) {
      double s = 0;
      final start = indptr[i];
      final end = indptr[i + 1];
      for (var k = start; k < end; k++) {
        s += values[k] * v[indices[k]];
      }
      out[i] = v[i] - s;
    }
  }

  /// Batched [applyLsym] — applies `L_sym` to `B` vectors at once.
  /// Input and output are AoSoA: length `n * B`, indexed by `i*B + b`
  /// so the `B` values for each node are contiguous in memory. A
  /// single pass over the edge arrays (indptr, indices, values)
  /// updates all `B` accumulators, amortising graph-array memory
  /// traffic — the dominant cost of SpMV — across the batch.
  ///
  /// For `B=4` on the review path, graph traffic drops 4× vs. running
  /// four independent [applyLsym] calls. The per-edge arithmetic is
  /// `B` scalar FMAs; small fixed `B` lets the compiler keep the
  /// accumulator registers hot.
  void applyLsymBatch(Float64List v, Float64List out, int B) {
    if (B == 1) {
      applyLsym(v, out);
      return;
    }
    // Four stack-allocated accumulators cover the review path's
    // 4-axis workload without heap allocation. Larger B falls back to
    // a per-call list.
    final s = Float64List(B);
    for (var i = 0; i < n; i++) {
      for (var b = 0; b < B; b++) {
        s[b] = 0.0;
      }
      final start = indptr[i];
      final end = indptr[i + 1];
      for (var k = start; k < end; k++) {
        final col = indices[k] * B;
        final w = values[k];
        for (var b = 0; b < B; b++) {
          s[b] += w * v[col + b];
        }
      }
      final iOff = i * B;
      for (var b = 0; b < B; b++) {
        out[iOff + b] = v[iOff + b] - s[b];
      }
    }
  }

  /// Estimate the spectral radius `|λ_max|` of `L_sym` via power
  /// iteration with Rayleigh-quotient readout. The normalised
  /// Laplacian has a proven spectrum in [0, 2]; this method is a
  /// diagnostic — useful for verifying the bound holds on a given
  /// graph and for catching numerical-error drift on pathological
  /// inputs.
  ///
  /// Cost: `O(iterations · |E|)`. 24 iterations gives 2-3 significant
  /// figures on any realistic graph.
  double estimateSpectralRadius({
    int iterations = kDefaultPowerIterations,
    int? seed,
  }) {
    if (n == 0) return 0;
    // Deterministic seed-based init so tests/diagnostics are
    // reproducible.
    final rng = math.Random(seed ?? 0xC0DE5EED);
    final a = Float64List(n);
    final b = Float64List(n);
    for (var i = 0; i < n; i++) {
      a[i] = rng.nextDouble() - 0.5;
    }
    var lambda = 0.0;
    var src = a;
    var dst = b;
    for (var it = 0; it < iterations; it++) {
      // Renormalise src to unit length to keep numerics in scale.
      var norm = 0.0;
      for (var i = 0; i < n; i++) {
        norm += src[i] * src[i];
      }
      norm = math.sqrt(norm);
      if (norm == 0 || !norm.isFinite) return 0;
      for (var i = 0; i < n; i++) {
        src[i] /= norm;
      }
      applyLsym(src, dst);
      // Rayleigh quotient: λ ≈ src · L·src (src is unit-norm).
      lambda = 0;
      for (var i = 0; i < n; i++) {
        lambda += src[i] * dst[i];
      }
      // Next iteration's input is L·src; ping-pong the buffers.
      final tmp = src;
      src = dst;
      dst = tmp;
    }
    return lambda.abs();
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Bessel coefficients — `c_k(t) = 2·e^{-t}·I_k(-t)` with `c_0` halved
// ─────────────────────────────────────────────────────────────────────────

/// Modified Bessel coefficients for the heat-kernel Chebyshev
/// expansion: `c_k(t) = (k==0 ? 1 : 2) · e^{-t} · I_k(-t)`.
///
/// `I_k(-t) = (-1)^k · I_k(t)`. We compute `I_k(t)` via the ascending
/// power series in log-space (overflow-safe for any t) with an inner-
/// loop convergence check.
///
/// Numerical safety:
///   • NaN input → returns coefficients for t=0 (degenerate identity).
///   • t > [_maxSafeT] → clamped to the safe ceiling.
///   • Non-finite intermediate values → coerced to 0 (truncates the
///     expansion early; never propagates non-finite into the recurrence).
List<double> besselCoeffs(double t, int k) {
  final result = Float64List(k + 1);
  final tSafe = t.isNaN ? 0.0 : t.clamp(0.0, _maxSafeT);
  if (tSafe == 0) {
    // c_0 = e^0 · I_0(0) = 1; c_k = 0 for k≥1.
    result[0] = 1.0;
    return result;
  }
  final expNegT = math.exp(-tSafe);
  final half = tSafe / 2.0;
  final halfSq = half * half;
  final logHalf = math.log(half);
  for (var kk = 0; kk <= k; kk++) {
    // log of first term in log-space — overflow-safe for any t.
    var logTerm0 = kk * logHalf;
    for (var i = 1; i <= kk; i++) {
      logTerm0 -= math.log(i);
    }
    var term = math.exp(logTerm0);
    var sum = term;
    for (var m = 0; m < _besselSeriesTermCap; m++) {
      term *= halfSq / ((m + 1) * (kk + m + 1));
      sum += term;
      if (term.abs() < _besselConvergenceEps * sum.abs()) break;
    }
    final ik = (kk & 1) == 0 ? sum : -sum;
    final c = kk == 0 ? expNegT * ik : 2 * expNegT * ik;
    result[kk] = c.isFinite ? c : 0.0;
  }
  return result;
}

/// Adaptive Chebyshev truncation: pick the smallest `K* ≤ maxK` where
/// `|c_{K*}(t)| < eps · ||c||_∞`. Bessel coefficients decay super-
/// exponentially past `k ≈ t·e/2`; for small t the tail is already
/// negligible at `K = 8–10` while large t needs more. Hardcoding K=20
/// wastes matvecs at low t and starves accuracy at high t.
int adaptiveK(List<double> coeffs, double eps) {
  var maxAbs = 0.0;
  for (final c in coeffs) {
    final a = c.abs();
    if (a > maxAbs) maxAbs = a;
  }
  if (maxAbs == 0) return coeffs.length - 1;
  final threshold = eps * maxAbs;
  for (var k = coeffs.length - 1; k >= 2; k--) {
    if (coeffs[k].abs() >= threshold) return k;
  }
  return 1;
}

// ─────────────────────────────────────────────────────────────────────────
// Heat-kernel diffusion — one-shot and basis-cached forms
// ─────────────────────────────────────────────────────────────────────────

/// Apply the heat kernel to source ρ at temperature t using the
/// Chebyshev expansion. Writes result into [phi]. Pure — no hidden
/// state. Allocates two scratch vectors internally.
///
/// Internally calls [adaptiveK] to skip the coefficient-tail past the
/// noise floor, so the effective polynomial order is `≤ K`.
void chebyshevDiffuse({
  required CsrGraph graph,
  required Float64List rho,
  required Float64List phi,
  required double t,
  int K = kDefaultChebyshevK,
}) {
  final n = graph.n;
  assert(rho.length == n);
  assert(phi.length == n);
  final fullCoeffs = besselCoeffs(t, K);
  final effectiveK = adaptiveK(fullCoeffs, 1e-8);
  final coeffs =
      effectiveK == K ? fullCoeffs : fullCoeffs.sublist(0, effectiveK + 1);

  // We expand in the shifted spectrum [-1, 1]. The normalised
  // Laplacian L_sym has spectrum [0, 2]; the shift x = L − I moves it
  // to [-1, 1]. For the matvec we compute y = L_sym·v − v.
  //
  // T_0(x)·ρ = ρ
  // T_1(x)·ρ = x·ρ = L_sym·ρ − ρ
  // T_{k+1}(x)·ρ = 2·x·(T_k·ρ) − T_{k-1}·ρ

  final t0 = Float64List.fromList(rho);
  final t1 = Float64List(n);
  final t2 = Float64List(n);
  final scratch = Float64List(n);

  // T_1·ρ = L_sym·ρ − ρ
  graph.applyLsym(t0, scratch);
  for (var i = 0; i < n; i++) {
    t1[i] = scratch[i] - t0[i];
  }

  // Initialise φ with c_0·T_0 + c_1·T_1.
  for (var i = 0; i < n; i++) {
    phi[i] = coeffs[0] * t0[i] + coeffs[1] * t1[i];
  }

  // Recurrence for k = 2..effectiveK.
  for (var k = 2; k <= effectiveK; k++) {
    // 2·x·T_{k-1} = 2·(L_sym·T_{k-1} − T_{k-1})
    graph.applyLsym(t1, scratch);
    for (var i = 0; i < n; i++) {
      t2[i] = 2 * (scratch[i] - t1[i]) - t0[i];
      phi[i] += coeffs[k] * t2[i];
    }
    // Shift: T_{k-1} ← T_k ; T_{k-2} ← T_{k-1}.
    t0.setAll(0, t1);
    t1.setAll(0, t2);
  }
}

/// Build the Chebyshev basis `T_k(L_sym − I)·ρ` for `k = 0..K`. Each
/// row of the returned `(K+1) × n` flat layout is a basis vector;
/// row `k` starts at offset `k·n`. Cache once, then call
/// [recombineHeatPhi] at any temperature in O(K·n) instead of
/// rerunning O(K·|E|) Chebyshev matvecs.
///
/// Useful for multi-temperature blends (e.g. the three-temperature
/// geometric-mean trick used by the chunk and hunk engines) and any
/// future temperature-sweep analysis.
Float64List chebyshevBasis({
  required CsrGraph graph,
  required Float64List rho,
  int K = kDefaultChebyshevK,
}) {
  final n = graph.n;
  final basis = Float64List((K + 1) * n);
  // T_0·ρ = ρ
  for (var i = 0; i < n; i++) {
    basis[i] = rho[i];
  }
  final scratch = Float64List(n);
  final t0 = Float64List.fromList(rho);
  final t1 = Float64List(n);
  // T_1·ρ = L_sym·ρ − ρ
  graph.applyLsym(t0, scratch);
  for (var i = 0; i < n; i++) {
    t1[i] = scratch[i] - t0[i];
    basis[n + i] = t1[i];
  }
  final t2 = Float64List(n);
  for (var k = 2; k <= K; k++) {
    graph.applyLsym(t1, scratch);
    final base = k * n;
    for (var i = 0; i < n; i++) {
      t2[i] = 2 * (scratch[i] - t1[i]) - t0[i];
      basis[base + i] = t2[i];
    }
    t0.setAll(0, t1);
    t1.setAll(0, t2);
  }
  return basis;
}

/// Batched Chebyshev diffusion — runs `B` heat-kernel solutions
/// simultaneously on the same graph. `rhoBatch` is AoSoA-packed:
/// `rhoBatch[i*B + b]` is the initial mass at node `i` for batch `b`.
/// Returns `phiBatch` in the same layout.
///
/// One pass over the edge arrays per Chebyshev step services all `B`
/// matvecs, so graph-array memory traffic scales as `O(K·|E|)` rather
/// than `O(B·K·|E|)`. The arithmetic still scales with `B` (each
/// edge contributes `B` multiply-adds), but arithmetic is cheap; the
/// graph load was the bottleneck.
Float64List chebyshevDiffuseBatch({
  required CsrGraph graph,
  required Float64List rhoBatch,
  required int B,
  required double t,
  int K = kDefaultChebyshevK,
}) {
  final n = graph.n;
  final stride = n * B;
  final phiBatch = Float64List(stride);
  if (n == 0 || B == 0) return phiBatch;
  final coeffs = besselCoeffs(t, K);

  // Chebyshev recurrence in AoSoA space. Scratch buffers hold T_{k-1},
  // T_k, T_{k+1} — each of length n*B.
  final t0 = Float64List.fromList(rhoBatch);
  final t1 = Float64List(stride);
  final scratch = Float64List(stride);

  // φ += c_0 · T_0
  final c0 = coeffs[0];
  if (c0.abs() >= 1e-12) {
    for (var i = 0; i < stride; i++) {
      phiBatch[i] += c0 * t0[i];
    }
  }
  if (K == 0) return phiBatch;

  // T_1 = L_sym·T_0 − T_0
  graph.applyLsymBatch(t0, scratch, B);
  for (var i = 0; i < stride; i++) {
    t1[i] = scratch[i] - t0[i];
  }
  final c1 = coeffs[1];
  if (c1.abs() >= 1e-12) {
    for (var i = 0; i < stride; i++) {
      phiBatch[i] += c1 * t1[i];
    }
  }

  // T_{k+1} = 2·(L_sym·T_k − T_k) − T_{k-1}
  final t2 = Float64List(stride);
  for (var k = 2; k <= K; k++) {
    graph.applyLsymBatch(t1, scratch, B);
    for (var i = 0; i < stride; i++) {
      t2[i] = 2 * (scratch[i] - t1[i]) - t0[i];
    }
    final ck = coeffs[k];
    if (ck.abs() >= 1e-12) {
      for (var i = 0; i < stride; i++) {
        phiBatch[i] += ck * t2[i];
      }
    }
    t0.setAll(0, t1);
    t1.setAll(0, t2);
  }
  return phiBatch;
}

/// Recombine a pre-computed Chebyshev [basis] at temperature [t].
/// Returns `φ(t) = Σ_{k=0..K} c_k(t) · (T_k·ρ)` — the heat-kernel
/// solution at t, evaluated as a linear combination of the basis
/// vectors. Cost is O(K·n), regardless of `|E|`. Coefficients below
/// `1e-12` are skipped (no observable accuracy impact).
Float64List recombineHeatPhi({
  required CsrGraph graph,
  required Float64List basis,
  required double t,
  int K = kDefaultChebyshevK,
}) {
  final n = graph.n;
  final coeffs = besselCoeffs(t, K);
  final phi = Float64List(n);
  for (var k = 0; k <= K; k++) {
    final c = coeffs[k];
    if (c.abs() < 1e-12) continue;
    final base = k * n;
    for (var i = 0; i < n; i++) {
      phi[i] += c * basis[base + i];
    }
  }
  return phi;
}
