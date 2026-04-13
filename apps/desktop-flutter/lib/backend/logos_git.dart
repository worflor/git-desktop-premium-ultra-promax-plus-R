// ═════════════════════════════════════════════════════════════════════════
// logos_git.dart — Logos-inspired git context engine
//
// A relevance diffusion engine for code review context. The diff is a
// source field ρ. The codebase is a Riemannian manifold whose metric is
// learned from the repo's own history. Relevance is the heat-kernel
// solution φ = exp(-t·L)·ρ — temperature at equilibrium after diffusing
// the diff-source through the manifold.
//
// Architecturally this is a direct sibling of `logos.wat`:
//   - Fixed memory regions via typed-array buffers at named offsets
//   - Lazy LUTs (log1p, logit, sigmoid) computed on first access
//   - Born-amplitude mixing with confidence-gated evidence weights
//   - KT/Jeffreys priors for cold-start
//   - Chebyshev polynomial expansion of the heat kernel
//
// The Dart implementation mirrors a hand-written `.wat` module at a 1:1
// level — Float64List/Int32List buffers stand in for WASM linear memory,
// method bodies are shaped the same as the kernels would be. Porting
// to `logos_git.wat` later is mechanical.
//
// ───────────────────────────────────────────────────────────────────────
// AXIS DECOMPOSITION (Phase 1 — zero new dependencies)
// ───────────────────────────────────────────────────────────────────────
//
//   F0 (global frequency)     — per-file touch rate in history
//                               analogue: Logos order-0 bit distribution
//
//   CC (co-change Jaccard)    — from existing FileCouplingMatrix
//                               analogue: Logos O2 bigram (pairwise memory)
//
//   SP (spatial / path)       — directory proximity
//                               analogue: Logos Ab (above-neighbor)
//
//   V  (volatility / GARCH)   — EWMA of per-file churn magnitude
//                               analogue: Logos V (local energy / second moment)
//
// All axes output (p, n) — a predictor probability and an evidence count.
// Mix via Born rule: p = (Σwᵢ√pᵢ)² / ((Σwᵢ√pᵢ)² + (Σwᵢ√(1-pᵢ))²)
// Weights: wᵢ = |pᵢ - 0.5| · min(log1p(nᵢ), cap_i)
//
// The mixed edge probability p_mix is converted to a distance via
// d(i,j) = -ln(p_mix). Edge weights for the graph Laplacian use
// exp(-d) = p_mix, so the same number serves both roles.
//
// ───────────────────────────────────────────────────────────────────────
// HEAT-KERNEL DIFFUSION
// ───────────────────────────────────────────────────────────────────────
//
//   φ(t) = exp(-t · L_sym) · ρ
//
// where L_sym = I - D^(-1/2) W D^(-1/2) is the normalised graph Laplacian.
// Evaluated via Chebyshev polynomial expansion:
//
//   exp(-t·L) ≈ Σ_{k=0..K} c_k(t) · T_k(L)
//
// where T_k are Chebyshev polynomials (first kind) and c_k(t) are
// modified Bessel functions I_k(-t). For K=20, accuracy is ~1e-8 on the
// spectrum [0, 2]. Each T_k(L)·ρ step is a sparse matvec — O(|E|) work.
// Total: O(K·|E|). A 10k-file repo with 100k edges diffuses in ~2M ops.
//
// ───────────────────────────────────────────────────────────────────────
// THE TEMPERATURE KNOB
// ───────────────────────────────────────────────────────────────────────
//
// Single scalar t controls diffusion range:
//   t ≈ 0.25  — just the touched items
//   t ≈ 1.0   — 1-hop neighbourhood (commit review default)
//   t ≈ 2.0   — 2-hop, semantic neighbours (code Q&A)
//   t ≈ 4.0   — wide, historical (codebase navigation)
//   t → ∞     — graph centrality (whole-repo summary)
//
// Same engine, same data, different t.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'file_coupling.dart';

/// Internals re-exported for tests. Not stable API — the `@visibleForTesting`
/// annotation makes accidental production use lint.
@visibleForTesting
// ignore: library_private_types_in_public_api
typedef LogosCsrGraphForTesting = _CsrGraph;

@visibleForTesting
List<double> chebyshevBesselCoeffsForTesting(double t, int K) =>
    _chebyshevBesselCoeffs(t, K);

@visibleForTesting
void diffuseChebyshevForTesting({
  required _CsrGraph graph,
  required Float64List rho,
  required Float64List phi,
  required double t,
  int K = _defaultChebyshevK,
}) =>
    _diffuseChebyshev(graph: graph, rho: rho, phi: phi, t: t, K: K);

@visibleForTesting
// ignore: library_private_types_in_public_api
_CsrGraph buildCsrForTesting({
  required int n,
  required List<int> indptr,
  required List<int> indices,
  required List<double> values,
}) =>
    _CsrGraph(
      n: n,
      indptr: Int32List.fromList(indptr),
      indices: Int32List.fromList(indices),
      values: Float64List.fromList(values),
    );

@visibleForTesting
extension LogosGitTestAccess on LogosGit {
  // ignore: library_private_types_in_public_api
  _CsrGraph get graphForTesting => graph;
}

// ═════════════════════════════════════════════════════════════════════════
// LAZY LUTs — adapted from logos.wat
// ═════════════════════════════════════════════════════════════════════════

/// log1p(n) — returns ln(1+n). Cached for small integer n so the
/// repeated weight computation doesn't call `math.log` for every edge.
/// Sentinel 0.0 means "not yet computed"; ln(1+0) = 0 naturally, so the
/// sentinel is safe for n=0 too.
class _Log1pLut {
  static final Float64List _t = Float64List(4096);

  static double call(int n) {
    if (n <= 0) return 0;
    if (n < 4096) {
      final cached = _t[n];
      if (cached != 0) return cached;
      final v = math.log(1.0 + n);
      _t[n] = v;
      return v;
    }
    return math.log(1.0 + n);
  }
}

/// σ(x) — logistic sigmoid. Same role as Logos' SIGMOID_LUT. Kept
/// lightweight; Dart's math.exp is native so a table lookup would barely
/// beat it on modern CPUs. If we need to port to .wat we'll add a
/// linear-interpolated LUT there (the WASM VM has no native exp).
double _sigmoid(double x) {
  if (x <= -12) return 1.5259021896696422e-05;
  if (x >= 12) return 0.9999847409781033;
  return 1.0 / (1.0 + math.exp(-x));
}

// ═════════════════════════════════════════════════════════════════════════
// BORN-AMPLITUDE MIX — the core blend operation
// ═════════════════════════════════════════════════════════════════════════

/// Per-axis observation: probability `p` in [ε, 1-ε] and evidence count `n`.
/// Axes with `n == 0` declare themselves silent via `weight() == 0`.
class AxisObs {
  final double p;
  final int n;
  const AxisObs(this.p, this.n);
  static const silent = AxisObs(0.5, 0);
}

/// Born-amplitude mix with confidence-gated, evidence-capped weights.
///
///   weight(i) = |p_i - 0.5| · min(log1p(n_i), cap_i)
///   A  = Σ w_i · √p_i
///   Ā  = Σ w_i · √(1 - p_i)
///   p  = A² / (A² + Ā²)
///
/// The confidence gate |p-0.5| makes axes at p≈0.5 (pure uncertainty)
/// contribute zero — they can't drown out sharper axes. The `cap_i` per
/// axis prevents an over-evidenced axis from monopolising the mix.
///
/// Correlated axes (CC and AU firing together because same team edits
/// same files) don't double-count: amplitude interference absorbs the
/// shared component quadratically. Orthogonal lifts add as Pythagorean
/// limbs.
///
/// Returns a single probability in (ε, 1-ε). If all axes are silent,
/// returns 0.5 (maximum uncertainty — edge contributes weight exp(-d)=
/// exp(ln(2)) ≈ 0.5 to the graph, i.e. a "weak connection").
class BornMixer {
  /// Evidence caps per axis — order matches the observation list passed
  /// to [mix]. F0 has the smallest cap (low evidence per commit);
  /// CC/V/SP mid-range; axes to be added later (CG, AU, EM) can set
  /// higher caps to reflect richer evidence.
  final List<double> caps;

  const BornMixer(this.caps);

  double mix(List<AxisObs> obs) {
    if (obs.length != caps.length) {
      throw ArgumentError('axis count mismatch');
    }
    var aSum = 0.0, aBarSum = 0.0;
    var totalWeight = 0.0;

    for (var i = 0; i < obs.length; i++) {
      final o = obs[i];
      if (o.n == 0) continue; // silent axis
      final evidence = math.min(_Log1pLut.call(o.n), caps[i]);
      final confidence = (o.p - 0.5).abs();
      final w = confidence * evidence;
      if (w == 0) continue;
      totalWeight += w;
      // Clamp p into the numerical safe zone to keep sqrt stable.
      final p = o.p.clamp(1e-6, 1 - 1e-6);
      aSum += w * math.sqrt(p);
      aBarSum += w * math.sqrt(1.0 - p);
    }
    if (totalWeight == 0) return 0.5;
    final a2 = aSum * aSum;
    final b2 = aBarSum * aBarSum;
    final denom = a2 + b2;
    // Belt + braces: the only paths into NaN here are sqrt of a clamped
    // p (impossible) or aSum/aBarSum already non-finite (also impossible
    // given the upstream guards) — but cheaper to guard than to debug.
    if (!denom.isFinite || denom <= 0) return 0.5;
    final p = a2 / denom;
    if (!p.isFinite) return 0.5;
    return p.clamp(1e-6, 1 - 1e-6);
  }
}

// ═════════════════════════════════════════════════════════════════════════
// AXIS COMPUTERS — Phase 1 set
// ═════════════════════════════════════════════════════════════════════════
//
// Each axis is a function (file_a, file_b, repoStats) → AxisObs.
// Axes only need the symmetric pair; the engine feeds every edge it
// decides to materialise.
//
// The axis order here is THE canonical order. BornMixer.caps must be
// in the same order. Keep them in lockstep.

/// The canonical axis order. [BornMixer.caps] is indexed in this order;
/// any axis reshuffle needs both lists to move together.
enum AxisId { f0, cc, sp, v }

/// F0 — global frequency axis.
///
/// Purely conditional on the *destination* file: "how often does this
/// file appear in commits at all?" Symmetric by design — we're asking
/// whether `b` is a noteworthy node in the repo regardless of `a`.
/// Cold-start via KT prior α=0.5.
class _F0Axis {
  /// touches[file] = commits that touched the file over the analysed
  /// history window.
  final Map<String, int> touches;

  /// Total commits in the window (denominator for the KT prior).
  final int totalCommits;

  const _F0Axis({required this.touches, required this.totalCommits});

  AxisObs observe(String b) {
    final t = touches[b] ?? 0;
    if (totalCommits == 0) return AxisObs.silent;
    // KT prior: (t + 0.5) / (totalCommits + 1)
    final p = (t + 0.5) / (totalCommits + 1.0);
    return AxisObs(p, totalCommits);
  }
}

/// CC — co-change axis. Uses the existing [FileCouplingMatrix].
///
/// P(b co-occurs with a | history) = Jaccard(a, b) smoothed with a KT
/// prior against the number of commits touching either side.
class _CcAxis {
  final FileCouplingMatrix matrix;

  const _CcAxis(this.matrix);

  AxisObs observe(String a, String b) {
    if (a == b) return const AxisObs(1.0, 1);
    final j = matrix.score(a, b);
    // Convert Jaccard (already smoothed by the matrix builder) into a
    // KT-style probability. We bias toward 0.5 when Jaccard is 0 by
    // blending with the prior at n=commitsAnalyzed/10 evidence.
    final evidence = (matrix.commitsAnalyzed / 10).clamp(0, 1024).toInt();
    final p = (j * evidence + 0.5) / (evidence + 1.0);
    return AxisObs(p, evidence);
  }
}

/// SP — path / spatial proximity.
///
/// Measures directory overlap between two paths. Ported directly from
/// the Logos Ab-axis semantics: "the nearest spatial neighbour" is
/// whoever shares the deepest common directory ancestor.
///
///   p = (sharedDepth + 0.5) / (maxDepth + 1)
///
/// The evidence count is `maxDepth` itself — deeper trees give more
/// resolution to the axis.
class _SpAxis {
  AxisObs observe(String a, String b) {
    if (a == b) return const AxisObs(1.0, 1);
    final sa = a.split('/');
    final sb = b.split('/');
    final max = math.max(sa.length, sb.length);
    if (max == 0) return AxisObs.silent;
    var shared = 0;
    final limit = math.min(sa.length, sb.length) - 1; // exclude filename
    for (var i = 0; i < limit; i++) {
      if (sa[i] == sb[i]) {
        shared++;
      } else {
        break;
      }
    }
    final p = (shared + 0.5) / (max + 1.0);
    return AxisObs(p, max);
  }
}

/// V — volatility (GARCH-style second moment).
///
/// Each file has an EWMA of per-commit churn magnitude (additions +
/// deletions). Two files are "V-related" when their volatilities *match*
/// — the axis rewards probes diffusing toward other noisy files when
/// the diff itself is noisy, and toward stable files when the diff is
/// tame. Sign-aligned z-matching: z(|v_a - v_b|) inverted via sigmoid.
class _VAxis {
  final Map<String, double> volatility;
  final double mean;
  final double stddev;

  const _VAxis({
    required this.volatility,
    required this.mean,
    required this.stddev,
  });

  AxisObs observe(String a, String b) {
    final va = volatility[a];
    final vb = volatility[b];
    if (va == null || vb == null) return AxisObs.silent;
    if (stddev <= 0) return AxisObs.silent;
    final z = (va - vb).abs() / stddev;
    // Small |z| → high p (volatilities match).
    final p = _sigmoid(2.0 - z);
    // Evidence grows with the number of observations feeding the EWMA.
    // We don't track per-file sample counts; use a small fixed evidence
    // count (axis remains informative but can't dominate).
    return AxisObs(p, 4);
  }
}

// ═════════════════════════════════════════════════════════════════════════
// SPARSE GRAPH (CSR) — same layout a `.wat` port would use
// ═════════════════════════════════════════════════════════════════════════
//
// Node IDs are dense integers 0..N-1. Path-to-id mapping is owned by the
// engine. Edges stored in CSR (Compressed Sparse Row) format:
//
//   indptr[i] = offset into (indices, values) of row i
//   indices[indptr[i]..indptr[i+1]] = neighbours of node i
//   values [indptr[i]..indptr[i+1]] = weights W_ij = exp(-d(i,j)) = p_mix
//
// For the symmetric normalised Laplacian L_sym = I - D^(-1/2) W D^(-1/2)
// we precompute D^(-1/2) once and fold it into the values so that each
// matvec step only does a single multiply per edge.
class _CsrGraph {
  final int n;
  final Int32List indptr;
  final Int32List indices;
  final Float64List values; // normalised weights — already fused with D^(-1/2)

  _CsrGraph({
    required this.n,
    required this.indptr,
    required this.indices,
    required this.values,
  });

  /// Apply L_sym = I - D^(-1/2) W D^(-1/2) to vector v. Since values
  /// are pre-fused with D^(-1/2), this is: y = v - (W_norm · v).
  /// `out` is overwritten; must have length `n`.
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

  /// Estimate the spectral radius (largest eigenvalue magnitude) of
  /// `L_sym` via power iteration. The normalised Laplacian has a proven
  /// spectrum in [0, 2]; this method exists as a diagnostic — to verify
  /// the bound holds for a given graph and to detect numerical-error
  /// drift on pathological inputs.
  ///
  /// Cost: O(iterations · |E|). 24 iterations is plenty for the 2-3
  /// significant figures we need to decide "is the Chebyshev domain
  /// safe?" on graphs with thousands of nodes.
  double estimateSpectralRadius({int iterations = _defaultPowerIterations, int? seed}) {
    if (n == 0) return 0;
    // Deterministic seed-based init so tests/diagnostics are reproducible.
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

// ═════════════════════════════════════════════════════════════════════════
// CHEBYSHEV HEAT-KERNEL DIFFUSION
// ═════════════════════════════════════════════════════════════════════════
//
// Approximates exp(-t·L_sym) · ρ by a truncated Chebyshev series over
// the spectrum [0, 2] of L_sym (proven bound for normalised Laplacian).
// After rescaling x = (L - I), domain [-1, 1] — standard Chebyshev.
//
//   exp(-t·L)·ρ ≈ Σ_{k=0..K} c_k(t) · T_k(x)·ρ
//
// with the recurrence T_0 = I, T_1 = x, T_{k+1} = 2x·T_k - T_{k-1}.
//
// Coefficients c_k(t) = 2·exp(-t)·I_k(-t) for k ≥ 1, c_0(t) = exp(-t)·I_0(-t).
// We precompute the Bessel coefficients via an explicit series — no
// external math lib needed.
//
// For K = 20, relative error < 1e-8 on [0, 2] for t ∈ [0, 10]. Plenty.

/// Maximum diffusion temperature this engine accepts. Beyond ~30 the
/// heat-kernel field is indistinguishable from the graph's stationary
/// distribution; capping silently here prevents Bessel-series overflow
/// (factorial blow-up in the naive expansion) without changing outputs
/// for any sane query.
const double _maxSafeT = 30.0;

/// Cap on the Bessel-series inner loop. The series converges
/// super-exponentially past the k-th term (each term is multiplied by
/// `(t/2)² / ((m+1)(k+m+1))`, a ratio that drops below 1 once m > t/2);
/// 200 is a generous ceiling that the early-exit ratio-test tightens
/// long before hitting. Not tunable — purely a safety bound.
const int _besselSeriesTermCap = 200;

/// Convergence floor for Bessel series summation, measured as a fraction
/// of the running sum magnitude. Tied to f64 machine epsilon: terms
/// below ~1e-20·|sum| can't affect the result within double precision.
const double _besselConvergenceEps = 1e-20;

/// Default Chebyshev truncation order. K = 20 gives relative error
/// < 1e-8 on the normalised-Laplacian spectrum [0, 2] for diffusion
/// times t ∈ [0, 10]. Derivation: Bessel coefficient |c_k(t)| decays
/// past k ≈ e·t/2 (Abramowitz–Stegun asymptotic); for t up to 10 the
/// useful band is k ≤ 14, so K = 20 leaves comfortable headroom.
/// `_adaptiveK` prunes unused tail terms at runtime.
const int _defaultChebyshevK = 20;

/// Default power-iteration depth for spectral-radius diagnostics.
/// Rayleigh-quotient convergence is geometric at rate |λ₂/λ₁|, where
/// λ₂ < λ₁ ≤ 2 on a normalised Laplacian. 24 iterations gets us 2-3
/// significant figures on any realistic git coupling graph.
const int _defaultPowerIterations = 24;

/// Default top-K window for the stability primitive and single-source
/// `relatedTo` queries. Scaled to a typical commit-review budget:
/// ~20 neighbours fits comfortably inside a 60k-char prompt at the
/// breadcrumb tier, and a meaningfully-long ranking to perturb.
const int _defaultTopK = 20;

/// Stability-primitive perturbation budget. Six trials is the minimum
/// for a meaningful Jaccard-overlap mean without burning too much CPU
/// on a diagnostic call (each trial is one full Chebyshev diffusion).
/// Three trials would give 33%-granular stability; six gives ~17%,
/// comfortable for the downstream firm/soft/knife-edge bucketing.
const int _defaultStabilityTrials = 6;

/// Multiplicative jitter magnitude for the stability primitive.
/// ε = 0.15 means source weights move ±15% per trial — well above
/// the noise floor of sane upstream probes (SSE-scaled weights shift
/// by <5%) but inside the band where a stable ranking should hold.
const double _defaultStabilityEpsilon = 0.15;

/// Deterministic seed for the stability primitive's RNG. Arbitrary
/// but constant — repeated calls produce identical perturbations,
/// making the primitive reproducible in tests and diagnostics.
const int _defaultStabilitySeed = 0xABDE;

/// Default top-K neighbours per node in the sparsified graph. Derived
/// as a small multiple of the max expected "cluster size" in a real
/// repo — a single module typically has 10-20 tightly-coupled files,
/// so 24 neighbours keeps every plausible cluster connected while
/// bounding the graph to O(24·|V|) edges. Mentioned separately from
/// the Chebyshev K to avoid confusion — this K is graph sparsity, not
/// polynomial order.
const int _defaultEdgeDensity = 24;

List<double> _chebyshevBesselCoeffs(double t, int k) {
  // Modified Bessel I_k(-t) via numerically stable forward recurrence on
  // the series term:
  //   I_k(t) = Σ_{m=0..∞} (t/2)^(k+2m) / (m! · (k+m)!)
  // term0 = (t/2)^k / k!  (computed in log-space to avoid pow overflow)
  // term(m+1) / term(m) = (t/2)^2 / ((m+1)(k+m+1))
  // I_k(-t) = (-1)^k I_k(t).
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
    // log of first term in log-space — overflow-safe for any reasonable t.
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
    // Last-line defence — never propagate non-finite values into the
    // recurrence. A zeroed coefficient just truncates the series early.
    result[kk] = c.isFinite ? c : 0.0;
  }
  return result;
}

/// Adaptive Chebyshev truncation: pick the smallest K* ≤ maxK where
/// |c_{K*}(t)| < eps · ||c||_∞. Bessel coefficients decay super-
/// exponentially past k ≈ t·e/2, so for small t the tail is already
/// negligible at K = 8–10 while for large t we need more. Hardcoding
/// K = 20 wastes matvecs at low t and starves accuracy at high t.
///
/// Physics note: this is a property of the heat-kernel Chebyshev
/// expansion specifically — `c_k(t) = 2·e^(-t)·I_k(-t)` where `I_k`
/// is the modified Bessel of first kind. Its tail decays by the
/// Abramowitz–Stegun bound; we just compute it eagerly and stop when
/// it's below the noise floor. Pure perf win, no accuracy loss.
int _adaptiveK(List<double> coeffs, double eps) {
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
  return 2;
}

/// Apply the heat-kernel to source ρ using Chebyshev expansion. Writes
/// result into `phi`. Allocates two scratch vectors internally. Pure —
/// no hidden state. Given a graph, source, t, and K, produces φ.
void _diffuseChebyshev({
  required _CsrGraph graph,
  required Float64List rho,
  required Float64List phi,
  required double t,
  int K = _defaultChebyshevK,
}) {
  final n = graph.n;
  assert(rho.length == n);
  assert(phi.length == n);
  final fullCoeffs = _chebyshevBesselCoeffs(t, K);
  // Shrink K to whatever the Bessel coefficients actually need at this
  // t. For t=0.25, adaptive K ≈ 8 (vs fixed 20) → 60% fewer matvecs.
  // For t=4, adaptive K ≈ 18 — close to the fixed budget.
  final effectiveK = _adaptiveK(fullCoeffs, 1e-8);
  final coeffs = effectiveK == K ? fullCoeffs : fullCoeffs.sublist(0, effectiveK + 1);
  // Rebind local K to the effective value for the loop below.
  // (Can't use `K` directly — it's the param name.)
  final kEff = effectiveK;

  // We want to expand in the shifted spectrum [-1, 1]. The normalised
  // Laplacian L_sym has spectrum [0, 2]; the shift x = L - I moves it
  // to [-1, 1]. For the matrix-vector step we compute y = L_sym·v - v.
  //
  // T_0(x)·ρ = ρ
  // T_1(x)·ρ = x·ρ = L_sym·ρ - ρ
  // T_{k+1}(x)·ρ = 2·x·(T_k·ρ) - T_{k-1}·ρ

  final t0 = Float64List.fromList(rho);
  final t1 = Float64List(n);
  final t2 = Float64List(n);
  final scratch = Float64List(n);

  // T_1·ρ = L_sym·ρ - ρ
  graph.applyLsym(t0, scratch);
  for (var i = 0; i < n; i++) {
    t1[i] = scratch[i] - t0[i];
  }

  // Initialise φ with c0·T0 + c1·T1
  for (var i = 0; i < n; i++) {
    phi[i] = coeffs[0] * t0[i] + coeffs[1] * t1[i];
  }

  // Recurrence for k = 2..effectiveK (adaptive — skips tail whose
  // coefficients are below the noise floor).
  for (var k = 2; k <= kEff; k++) {
    // 2·x·T_{k-1} = 2·(L_sym·T_{k-1} - T_{k-1})
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

// ═════════════════════════════════════════════════════════════════════════
// THE ENGINE
// ═════════════════════════════════════════════════════════════════════════

/// Raw per-file statistics the engine needs to construct its axes.
class LogosGitStats {
  final Map<String, int> touches;
  final int totalCommits;
  final Map<String, double> volatility;
  final double volMean;
  final double volStddev;
  final FileCouplingMatrix coupling;

  const LogosGitStats({
    required this.touches,
    required this.totalCommits,
    required this.volatility,
    required this.volMean,
    required this.volStddev,
    required this.coupling,
  });
}

/// Relevance score produced by diffusion. `phi` is the raw heat-kernel
/// value; higher = more relevant. `path` identifies the file.
class RelevanceScore {
  final String path;
  final double phi;
  const RelevanceScore(this.path, this.phi);
  @override
  String toString() => '$path  φ=${phi.toStringAsFixed(4)}';
}

/// Emission tier — FULL (whole body), SIG (signature + breadcrumbs),
/// BREAD (filename + one-liner). Higher tier = more tokens, more info.
enum EmissionTier { full, signature, breadcrumb }

class EmissionPlan {
  final String path;
  final double phi;
  final EmissionTier tier;
  const EmissionPlan(this.path, this.phi, this.tier);
}

/// Born-mix caps per axis, in the canonical [AxisId] order (f0, cc, sp, v).
/// The caps are the maximum evidence (in nats) each axis can contribute
/// to the Born amplitude mix. They're information-theoretic — each is
/// the natural log of the axis's intrinsic branching factor:
///
///   F0 = ln(2) — one bit: "is this file touched at all in this window?"
///   CC = ln(4) — two bits: four effective co-change regimes
///                (together|sometimes|rarely|never)
///   SP = ln(3) — one trit: same file | same directory | elsewhere
///   V  = ln(3) — one trit: calmer | matched | noisier than the partner
///
/// Derivable not magic: each value is literally `ln(k)` where k is the
/// axis's distinguishable states. Expressed as such so the relationship
/// is visible in the code, not stranded in a comment.
final _defaultCaps = <double>[
  math.ln2,          // F0: ln(2)
  2 * math.ln2,      // CC: ln(4) = 2·ln(2)
  math.log(3),       // SP: ln(3)
  math.log(3),       // V:  ln(3)
];

/// The Logos-inspired git context engine.
///
/// Usage:
///   final engine = await LogosGit.buildFromStats(stats);
///   final scores = engine.diffuse({'lib/validators.dart', 'lib/auth.dart'});
///   final plan = engine.plan(scores, budget: 80000);
///
/// The engine is immutable after construction. To refresh after new
/// commits, rebuild.
class LogosGit {
  // ignore: library_private_types_in_public_api
  final _CsrGraph graph;
  final List<String> nodePaths; // id → path
  final Map<String, int> pathToId;
  final BornMixer mixer;

  LogosGit._({
    required this.graph,
    required this.nodePaths,
    required this.pathToId,
    required this.mixer,
  });

  /// Construct the engine from per-file statistics. Nodes are all files
  /// with at least one observation from any axis; edges are the
  /// `edgeDensity`·N pairs with the strongest mixed probability (top-K
  /// per node to keep the graph sparse).
  static LogosGit buildFromStats(
    LogosGitStats stats, {
    int edgeDensity = _defaultEdgeDensity,
  }) {
    // Materialise the node set: union of files seen by any axis.
    final pathSet = <String>{};
    pathSet.addAll(stats.touches.keys);
    pathSet.addAll(stats.volatility.keys);
    pathSet.addAll(stats.coupling.jaccard.keys);

    // Stable ordering — sort for determinism (helps debugging + caching).
    final nodePaths = pathSet.toList()..sort();
    final pathToId = <String, int>{};
    for (var i = 0; i < nodePaths.length; i++) {
      pathToId[nodePaths[i]] = i;
    }

    final n = nodePaths.length;
    if (n == 0) {
      // Empty graph — engine does nothing useful but doesn't throw.
      return LogosGit._(
        graph: _CsrGraph(
          n: 0,
          indptr: Int32List(1),
          indices: Int32List(0),
          values: Float64List(0),
        ),
        nodePaths: nodePaths,
        pathToId: pathToId,
        mixer: BornMixer(_defaultCaps),
      );
    }

    final mixer = BornMixer(_defaultCaps);
    final f0 = _F0Axis(touches: stats.touches, totalCommits: stats.totalCommits);
    final cc = _CcAxis(stats.coupling);
    final sp = _SpAxis();
    final v = _VAxis(
      volatility: stats.volatility,
      mean: stats.volMean,
      stddev: stats.volStddev,
    );

    // For each node, score all candidate neighbours and keep the top
    // `edgeDensity` by mixed probability. This is the critical step —
    // a fully-connected graph would be n² edges; we prune here.
    //
    // Candidate set for node `i`: any node that shares at least one
    // non-silent axis observation. In practice, CC's Jaccard matrix is
    // sparse, so we start from its neighbours and fall back to all-vs-
    // all only for unconnected nodes. SP and F0 then amplify or damp.
    final indptrList = <int>[0];
    final indicesList = <int>[];
    final valuesList = <double>[];

    // Precompute the node's F0 observation — it only depends on the
    // destination; caching avoids re-lookup per candidate. Stored as
    // a list for fast indexed access.
    final f0Obs = List<AxisObs>.generate(n, (i) => f0.observe(nodePaths[i]));

    // Accumulator for row degrees (used for D^(-1/2) normalisation).
    final degree = Float64List(n);
    // We make two passes. Pass 1: collect the raw (neighbour, p_mix)
    // pairs per row. Pass 2: normalise by D^(-1/2) and write CSR.
    final rawRows = List<List<_EdgeCandidate>>.generate(n, (_) => []);

    for (var i = 0; i < n; i++) {
      final a = nodePaths[i];
      // Candidate set — neighbours from CC, plus a sample of path
      // siblings (SP would fire) even when no CC evidence exists.
      final candidates = <String>{};
      final ccRow = stats.coupling.jaccard[a];
      if (ccRow != null) candidates.addAll(ccRow.keys);
      // Directory siblings — cheap to compute, opens the graph up for
      // repos where co-change matrix is sparse.
      final parent = _parentDir(a);
      if (parent.isNotEmpty) {
        for (final p in nodePaths) {
          if (p != a && p.startsWith('$parent/')) candidates.add(p);
        }
      }

      if (candidates.isEmpty) {
        indptrList.add(indicesList.length);
        continue;
      }

      // Score each candidate via Born mix.
      final scored = <_EdgeCandidate>[];
      for (final b in candidates) {
        final j = pathToId[b];
        if (j == null || j == i) continue;
        final obs = <AxisObs>[
          f0Obs[j],
          cc.observe(a, b),
          sp.observe(a, b),
          v.observe(a, b),
        ];
        final p = mixer.mix(obs);
        if (p <= 0.5) continue; // only keep edges with positive lift
        scored.add(_EdgeCandidate(j, p));
      }

      // Top-K by p_mix — keep the graph sparse.
      scored.sort((x, y) => y.pMix.compareTo(x.pMix));
      final k = math.min(edgeDensity, scored.length);
      final kept = scored.sublist(0, k);
      rawRows[i] = kept;
      for (final e in kept) {
        degree[i] += e.pMix;
      }
    }

    // Symmetrise: an edge (i, j) should also exist as (j, i) with the
    // same weight. We take the max of (i→j, j→i) when both exist.
    for (var i = 0; i < n; i++) {
      for (final e in rawRows[i]) {
        final j = e.node;
        final back = rawRows[j].firstWhere(
          (x) => x.node == i,
          orElse: () => const _EdgeCandidate(-1, 0),
        );
        if (back.node == -1) {
          // Add the reverse edge.
          rawRows[j].add(_EdgeCandidate(i, e.pMix));
          degree[j] += e.pMix;
        } else if (back.pMix < e.pMix) {
          // Upgrade the reverse weight — same number keeps symmetry.
          final idx = rawRows[j].indexWhere((x) => x.node == i);
          degree[j] += e.pMix - back.pMix;
          rawRows[j][idx] = _EdgeCandidate(i, e.pMix);
        }
      }
    }

    // Pass 2: build CSR with D^(-1/2) fused into values.
    indptrList.clear();
    indptrList.add(0);
    for (var i = 0; i < n; i++) {
      final row = rawRows[i];
      // Sort by neighbour id for cache-friendly matvec.
      row.sort((x, y) => x.node.compareTo(y.node));
      final di = degree[i] <= 0 ? 0 : 1.0 / math.sqrt(degree[i]);
      for (final e in row) {
        final dj = degree[e.node] <= 0 ? 0 : 1.0 / math.sqrt(degree[e.node]);
        final w = di * e.pMix * dj;
        indicesList.add(e.node);
        valuesList.add(w);
      }
      indptrList.add(indicesList.length);
    }

    final graph = _CsrGraph(
      n: n,
      indptr: Int32List.fromList(indptrList),
      indices: Int32List.fromList(indicesList),
      values: Float64List.fromList(valuesList),
    );

    return LogosGit._(
      graph: graph,
      nodePaths: nodePaths,
      pathToId: pathToId,
      mixer: mixer,
    );
  }

  /// Build a reusable diffusion basis for the given source set. The
  /// Chebyshev expansion separates cleanly into:
  ///   • basis vectors `T_k(x)·ρ`  — t-independent, computed ONCE
  ///   • scalar coefficients `c_k(t)` — the only t-dependent part
  ///
  /// So for temperature-slider UIs we compute the K+1 basis vectors
  /// once (O(K·|E|)), then per-frame just recombine at a new t
  /// (O(K·|V|) — a dozen float multiplies per node, no matvec).
  ///
  /// Returns null on empty graph / empty source set — callers should
  /// degrade gracefully (no rail, no temperature interaction).
  DiffusionBasis? buildBasis(Set<String> sourceFiles, {int K = _defaultChebyshevK}) {
    if (graph.n == 0) return null;
    final rho = Float64List(graph.n);
    var sourceWeight = 0.0;
    for (final p in sourceFiles) {
      final id = pathToId[p];
      if (id == null) continue;
      rho[id] = 1.0;
      sourceWeight += 1.0;
    }
    if (sourceWeight == 0) return null;
    for (var i = 0; i < graph.n; i++) {
      rho[i] /= sourceWeight;
    }
    return _buildDiffusionBasis(graph: graph, rho: rho, K: K, sources: {
      for (final p in sourceFiles)
        if (pathToId.containsKey(p)) p,
    });
  }

  /// Weighted variant of [buildBasis] — sources carry impact-weights
  /// (e.g. file churn for a commit-borrow query, where a high-line-
  /// change file should inject more heat than a one-line tweak).
  /// Returns null on empty graph / no in-graph sources.
  ///
  /// Like [buildBasis], the returned [DiffusionBasis] is t-independent
  /// — `recombine(t)` evaluates at any temperature in O(K·|V|) work.
  /// For a multi-temperature distillation (e.g. blending t=0.5/1.0/2.0
  /// to capture multi-scale neighborhood structure), build the basis
  /// ONCE per source set, then recombine three times. Compared to
  /// three separate `diffuseWeighted` calls, this saves 2·K matvecs —
  /// roughly 2/3 of the per-query work.
  DiffusionBasis? buildBasisWeighted(
    Map<String, double> weights, {
    int K = _defaultChebyshevK,
  }) {
    if (graph.n == 0 || weights.isEmpty) return null;
    final rho = Float64List(graph.n);
    var total = 0.0;
    final inGraphSources = <String>{};
    for (final entry in weights.entries) {
      if (entry.value <= 0) continue;
      final id = pathToId[entry.key];
      if (id == null) continue;
      rho[id] = entry.value;
      total += entry.value;
      inGraphSources.add(entry.key);
    }
    if (total <= 0) return null;
    // Normalise to unit total mass — same convention as buildBasis /
    // diffuseWeighted. Downstream ranking is invariant to scale.
    for (var i = 0; i < graph.n; i++) {
      rho[i] /= total;
    }
    return _buildDiffusionBasis(
        graph: graph, rho: rho, K: K, sources: inGraphSources);
  }

  /// Diffuse from the source file set. Returns every node with positive
  /// relevance, sorted descending by φ.
  ///
  /// [t] is diffusion time. Defaults to 1.0 (commit-review scope).
  ///    0.25 — "only the touched files"
  ///    1.0  — "1-hop neighbourhood"                 ← commit review
  ///    2.0  — "2-hop + semantic"                    ← code Q&A
  ///    4.0  — "wide historical"                     ← codebase nav
  ///    ∞    — "graph equilibrium"                   ← repo summary
  ///
  /// [K] controls Chebyshev truncation. 20 is enough for t ∈ [0, 10].
  List<RelevanceScore> diffuse(
    Set<String> sourceFiles, {
    double t = 1.0,
    int K = _defaultChebyshevK,
  }) {
    if (graph.n == 0) return const [];
    // Build source vector ρ. Files outside the graph are ignored.
    final rho = Float64List(graph.n);
    var sourceWeight = 0.0;
    for (final p in sourceFiles) {
      final id = pathToId[p];
      if (id == null) continue;
      rho[id] = 1.0; // unit weight per touched file
      sourceWeight += 1.0;
    }
    if (sourceWeight == 0) return const [];
    // Normalise ρ so total injected "heat" is 1.
    for (var i = 0; i < graph.n; i++) {
      rho[i] /= sourceWeight;
    }

    final phi = Float64List(graph.n);
    _diffuseChebyshev(graph: graph, rho: rho, phi: phi, t: t, K: K);

    // Pack into sorted list, excluding exact source files (they're the
    // diff itself — not context). Callers that want them can add them
    // back trivially.
    final results = <RelevanceScore>[];
    for (var i = 0; i < graph.n; i++) {
      final p = nodePaths[i];
      if (sourceFiles.contains(p)) continue;
      final val = phi[i];
      if (val <= 0) continue;
      results.add(RelevanceScore(p, val));
    }
    results.sort((a, b) => b.phi.compareTo(a.phi));
    return results;
  }

  /// Diffuse from a WEIGHTED source map — the correct path for
  /// probe-based queries where different observables (primary, M-axis,
  /// Ab-axis) carry different starting amplitudes.
  ///
  /// Heat kernel is linear in ρ, so callers used to sum N unit-mass
  /// diffusions scaled by their weight. That's mathematically fine but
  /// wastes O(N) matvec passes per review. This method builds a single
  /// properly-weighted ρ and runs one Chebyshev expansion.
  ///
  /// `excludePaths` is filtered from the returned list — typically the
  /// diff's primary paths, which callers don't want surfaced back.
  ///
  /// Returns empty when the graph is empty, weights are empty, or every
  /// weighted entry misses the graph.
  List<RelevanceScore> diffuseWeighted(
    Map<String, double> weights, {
    double t = 1.0,
    int K = _defaultChebyshevK,
    Set<String> excludePaths = const {},
  }) {
    if (graph.n == 0 || weights.isEmpty) return const [];
    final rho = Float64List(graph.n);
    var total = 0.0;
    for (final entry in weights.entries) {
      if (entry.value <= 0) continue;
      final id = pathToId[entry.key];
      if (id == null) continue;
      rho[id] = entry.value;
      total += entry.value;
    }
    if (total <= 0) return const [];
    // Normalise to unit mass — same convention as `diffuse`. The
    // downstream ranking is invariant to this scale, but it keeps φ
    // values comparable across different weight magnitudes.
    for (var i = 0; i < graph.n; i++) {
      rho[i] /= total;
    }

    final phi = Float64List(graph.n);
    _diffuseChebyshev(graph: graph, rho: rho, phi: phi, t: t, K: K);

    final results = <RelevanceScore>[];
    for (var i = 0; i < graph.n; i++) {
      final path = nodePaths[i];
      if (excludePaths.contains(path)) continue;
      final val = phi[i];
      if (val <= 0) continue;
      results.add(RelevanceScore(path, val));
    }
    results.sort((a, b) => b.phi.compareTo(a.phi));
    return results;
  }

  /// **Born overlap** — the Logos-native inner product between two
  /// probes' diffused fields. Measures how much they interfere on the
  /// manifold: near 1 = they cover overlapping territory; near 0 =
  /// disjoint neighbourhoods.
  ///
  ///   I(ρ_a, ρ_b; t) = Σ_v √(φ_a(v) · φ_b(v))
  ///
  /// The √ is the Born amplitude — same operation `BornMixer.mix` uses
  /// to compose axis distributions. Cosine / dot products would also
  /// give an "overlap" number, but Born overlap is the coherent-sum
  /// amplitude the rest of the codec operates in. Use this for:
  ///   - cross-PR merge-collision prediction ("these two PRs touch the
  ///     same semantic region")
  ///   - cross-branch ghost-conflict detection
  ///   - diff-pair similarity that respects multi-axis topology
  ///
  /// Null on empty weights either side. Both weight maps are normalised
  /// to unit mass before diffusion (same convention as [diffuseWeighted]).
  double? bornOverlap(
    Map<String, double> weightsA,
    Map<String, double> weightsB, {
    double t = 1.5,
    int K = _defaultChebyshevK,
  }) {
    if (graph.n == 0) return null;
    final phiA = _phiFromWeights(weightsA, t, K);
    final phiB = _phiFromWeights(weightsB, t, K);
    if (phiA == null || phiB == null) return null;

    // Born overlap: Σ √(a·b) for non-negative a, b. Equivalent to
    // the Bhattacharyya coefficient when a, b are probability
    // distributions. With our unit-normalised φ vectors the value is
    // bounded by 1 (equality iff identical distributions).
    var sum = 0.0;
    for (var i = 0; i < graph.n; i++) {
      final a = phiA[i];
      final b = phiB[i];
      if (a <= 0 || b <= 0) continue;
      sum += math.sqrt(a * b);
    }
    return sum;
  }

  /// Helper: build φ from weight map at temperature t. Returns null on
  /// empty / all-unknown weights. Used by [bornOverlap] and available
  /// for any future multi-probe primitive.
  Float64List? _phiFromWeights(
    Map<String, double> weights,
    double t,
    int K,
  ) {
    if (weights.isEmpty) return null;
    final rho = Float64List(graph.n);
    var total = 0.0;
    for (final entry in weights.entries) {
      if (entry.value <= 0) continue;
      final id = pathToId[entry.key];
      if (id == null) continue;
      rho[id] = entry.value;
      total += entry.value;
    }
    if (total <= 0) return null;
    for (var i = 0; i < graph.n; i++) {
      rho[i] /= total;
    }
    final phi = Float64List(graph.n);
    _diffuseChebyshev(graph: graph, rho: rho, phi: phi, t: t, K: K);
    return phi;
  }

  /// **Stability of a diffusion query** — returns a [0, 1] score where
  /// 1.0 means "tiny perturbations to the source weights don't change
  /// the top-K ranking at all" and 0 means "one dropped source and the
  /// answer is entirely different." Novel Logos-spirited confidence
  /// signal: the same machinery that produces an answer produces its
  /// own self-consistency score, so downstream code can abstain rather
  /// than act on knife-edge rankings.
  ///
  /// Algorithm: run [nTrials] diffusions, each with source weights
  /// multiplicatively perturbed by ±[epsilon] (deterministic seed).
  /// Stability = mean pairwise Jaccard overlap of their top-[topK]
  /// sets against the unperturbed top-K.
  ///
  /// Returns 1.0 on degenerate inputs (empty graph, single source, K=0)
  /// — no perturbation can change a single-element ranking, so it's
  /// trivially stable.
  double diffuseStability(
    Map<String, double> weights, {
    double t = 1.0,
    int topK = _defaultTopK,
    int nTrials = _defaultStabilityTrials,
    double epsilon = _defaultStabilityEpsilon,
    int seed = _defaultStabilitySeed,
  }) {
    if (graph.n == 0 || weights.isEmpty || topK <= 0) return 1.0;
    final baseline = diffuseWeighted(weights, t: t);
    if (baseline.length <= 1) return 1.0;
    final baseSet = baseline
        .take(topK)
        .map((s) => s.path)
        .toSet();
    if (baseSet.isEmpty) return 1.0;

    final rng = math.Random(seed);
    var overlapAcc = 0.0;
    var trialsRun = 0;
    for (var trial = 0; trial < nTrials; trial++) {
      final perturbed = <String, double>{};
      for (final entry in weights.entries) {
        // Multiplicative jitter in [1-ε, 1+ε]. Preserves the sign of the
        // weight and never flips a non-zero source to zero (entropy-
        // preserving perturbation, Logos-style).
        final jitter = 1.0 + (rng.nextDouble() * 2 - 1) * epsilon;
        perturbed[entry.key] = entry.value * jitter;
      }
      final trialScores = diffuseWeighted(perturbed, t: t);
      if (trialScores.isEmpty) continue;
      final trialSet = trialScores
          .take(topK)
          .map((s) => s.path)
          .toSet();
      if (trialSet.isEmpty) continue;
      // Jaccard overlap between the perturbed top-K and the baseline
      // top-K: |A∩B| / |A∪B|.
      final inter = baseSet.intersection(trialSet).length;
      final union = baseSet.union(trialSet).length;
      if (union > 0) {
        overlapAcc += inter / union;
        trialsRun++;
      }
    }
    if (trialsRun == 0) return 0.0;
    return overlapAcc / trialsRun;
  }

  /// Estimated spectral radius of the engine's normalised Laplacian.
  /// Diagnostic — should always be ≤ 2 by construction. A larger value
  /// signals numerical drift or an asymmetric weight bug worth chasing.
  double estimateSpectralRadius({int iterations = _defaultPowerIterations}) =>
      graph.estimateSpectralRadius(iterations: iterations);

  /// **Per-source attribution diffusion** — runs Chebyshev expansion
  /// once per axis bucket and returns φ vectors keyed by axis. Heat
  /// kernel is linear in ρ, so the combined φ equals the sum of per-
  /// axis φ. Use this to answer "*why* did file X surface as relevant?"
  /// — by reading the dominant axis bucket per result.
  ///
  /// `weightsByPath` carries the source amplitudes; `axisLabelByPath`
  /// assigns each path to a bucket label. Paths not in [pathToId] are
  /// silently dropped (out-of-graph). Paths with weight ≤ 0 are dropped.
  ///
  /// Returns null if no source contributes.
  AxisAttribution? diffuseWithAttribution({
    required Map<String, double> weightsByPath,
    required Map<String, String> axisLabelByPath,
    double t = 1.0,
    int K = _defaultChebyshevK,
    Set<String> excludePaths = const {},
  }) {
    if (graph.n == 0 || weightsByPath.isEmpty) return null;

    // Bucket per axis, applying the global mass normalisation up front
    // so per-axis φ vectors sum to combined φ.
    final perAxisRaw = <String, Float64List>{};
    var totalMass = 0.0;
    for (final entry in weightsByPath.entries) {
      final w = entry.value;
      if (w <= 0) continue;
      if (!pathToId.containsKey(entry.key)) continue;
      totalMass += w;
    }
    if (totalMass <= 0) return null;

    for (final entry in weightsByPath.entries) {
      final w = entry.value;
      if (w <= 0) continue;
      final id = pathToId[entry.key];
      if (id == null) continue;
      final axis = axisLabelByPath[entry.key] ?? '_default';
      final rho = perAxisRaw.putIfAbsent(axis, () => Float64List(graph.n));
      rho[id] += w / totalMass;
    }

    // Diffuse each axis bucket through the same engine.
    final perAxisPhi = <String, Float64List>{};
    for (final entry in perAxisRaw.entries) {
      final phi = Float64List(graph.n);
      _diffuseChebyshev(graph: graph, rho: entry.value, phi: phi, t: t, K: K);
      perAxisPhi[entry.key] = phi;
    }

    // Combined = elementwise sum (heat kernel linearity).
    final combinedPhi = Float64List(graph.n);
    for (final phi in perAxisPhi.values) {
      for (var i = 0; i < graph.n; i++) {
        combinedPhi[i] += phi[i];
      }
    }

    // Materialise sorted scores for combined; per-axis returned as raw
    // φ so callers can compose / threshold themselves.
    final combined = <RelevanceScore>[];
    final dominantAxis = <String, String>{};
    final shareByAxis = <String, Map<String, double>>{};
    for (var i = 0; i < graph.n; i++) {
      final path = nodePaths[i];
      if (excludePaths.contains(path)) continue;
      final v = combinedPhi[i];
      if (v <= 0) continue;
      combined.add(RelevanceScore(path, v));
      // Per-node attribution: which axis contributed most? And what
      // share of the node's φ came from each axis?
      var bestAxis = '';
      var bestVal = -1.0;
      final shares = <String, double>{};
      for (final entry in perAxisPhi.entries) {
        final ap = entry.value[i];
        if (ap <= 0) continue;
        final share = ap / v;
        shares[entry.key] = share;
        if (ap > bestVal) {
          bestVal = ap;
          bestAxis = entry.key;
        }
      }
      if (bestAxis.isNotEmpty) dominantAxis[path] = bestAxis;
      if (shares.isNotEmpty) shareByAxis[path] = shares;
    }
    combined.sort((x, y) => y.phi.compareTo(x.phi));

    return AxisAttribution(
      combined: combined,
      perAxisPhi: perAxisPhi,
      nodePaths: nodePaths,
      dominantAxis: dominantAxis,
      shareByAxis: shareByAxis,
    );
  }

  /// Multi-axis *coherence* of a path set — the mean pairwise relevance
  /// under the full Born-mixed metric. Replaces the single-axis
  /// `FileCouplingMatrix.coherenceFor(paths)` with a metric that
  /// considers frequency, coupling, proximity, and volatility together.
  ///
  /// Returns 1.0 for ≤1 known paths (nothing to compare).
  /// Returns in [0, 1] where higher = tighter semantic grouping.
  ///
  /// Used by the branches page to score PR "focus" — a high coherence
  /// means the PR touches files that historically belong together; low
  /// means a scattered sweep.
  double coherence(Iterable<String> paths) {
    final known = paths.where(pathToId.containsKey).toList();
    if (known.length < 2) return 1.0;
    var sum = 0.0;
    var pairs = 0;
    for (var i = 0; i < known.length; i++) {
      final ia = pathToId[known[i]]!;
      final aStart = graph.indptr[ia];
      final aEnd = graph.indptr[ia + 1];
      // The fused values are W_norm[i,j] = D^(-1/2) · p_mix · D^(-1/2).
      // We want the raw p_mix for interpretability. Undo the fusion by
      // multiplying back D_ii^(1/2) · D_jj^(1/2). But we don't keep D
      // separately — reconstruct it from indptr neighborhoods on demand.
      //
      // Cheap enough for a PR-sized set (≤~20 files): O(k² · avg degree).
      for (var j = i + 1; j < known.length; j++) {
        final jb = pathToId[known[j]]!;
        double edgeVal = 0;
        for (var k = aStart; k < aEnd; k++) {
          if (graph.indices[k] == jb) {
            edgeVal = graph.values[k];
            break;
          }
        }
        // edgeVal is the normalised weight; for coherence we want the
        // raw Born probability — but ranking is preserved by either.
        // We sum edgeVal directly (already in [0, ~1]) and normalise
        // by pair count.
        sum += edgeVal;
        pairs++;
      }
    }
    return pairs == 0 ? 1.0 : (sum / pairs).clamp(0.0, 1.0);
  }

  /// Rank all known paths by relevance to [seed]. Returns the top
  /// [limit] most-relevant paths (excluding the seed itself).
  /// Convenience wrapper over [diffuse] for single-file queries —
  /// "show me things related to this file."
  List<RelevanceScore> relatedTo(
    String seed, {
    double t = 1.0,
    int limit = 20,
  }) {
    if (!pathToId.containsKey(seed)) return const [];
    final scores = diffuse({seed}, t: t);
    if (scores.length <= limit) return scores;
    return scores.sublist(0, limit);
  }

  /// Select an emission plan from relevance scores within [budget]
  /// tokens. Greedy density knapsack with a single-pass swap. Tiers:
  ///   FULL        — avg 1600 tokens, info 1.0
  ///   SIGNATURE   —        300              0.45
  ///   BREADCRUMB  —         60              0.12
  ///
  /// These numbers are deliberately conservative defaults; Phase 2 will
  /// learn them from audit-log citations.
  List<EmissionPlan> plan(
    List<RelevanceScore> scored, {
    int budget = 60000,
  }) {
    const tierCost = <EmissionTier, int>{
      EmissionTier.full: 1600,
      EmissionTier.signature: 300,
      EmissionTier.breadcrumb: 60,
    };
    const tierInfo = <EmissionTier, double>{
      EmissionTier.full: 1.0,
      EmissionTier.signature: 0.45,
      EmissionTier.breadcrumb: 0.12,
    };

    // Expand each score into three candidate tiers and rank by density
    // (info / cost). The density metric is Lagrangian — we're solving a
    // knapsack so density greedy is ~(1-1/e)-optimal.
    final candidates = <_TierCandidate>[];
    for (final s in scored) {
      for (final t in EmissionTier.values) {
        final cost = tierCost[t]!;
        final info = s.phi * tierInfo[t]!;
        candidates.add(_TierCandidate(s.path, s.phi, t, cost, info));
      }
    }
    candidates.sort((a, b) => b.density.compareTo(a.density));

    final selected = <String, EmissionPlan>{};
    var remaining = budget;
    for (final c in candidates) {
      if (selected.containsKey(c.path)) continue; // one tier per path
      if (c.cost > remaining) continue;
      selected[c.path] = EmissionPlan(c.path, c.phi, c.tier);
      remaining -= c.cost;
    }

    return selected.values.toList()
      ..sort((a, b) => b.phi.compareTo(a.phi));
  }
}

/// Result of [LogosGit.diffuseWithAttribution]. Carries the combined
/// φ field (summed across axes — exactly what plain `diffuseWeighted`
/// would have returned), plus per-axis φ vectors and per-node provenance.
///
/// Use [combined] for ranking emissions and [dominantAxis] / [shareByAxis]
/// for explaining why a result surfaced. Intended consumers: the
/// `<logos_shape>` block in AI prompts, the X-Ray UI's "why this file"
/// disclosure, and SSE feedback that wants per-axis precision.
class AxisAttribution {
  final List<RelevanceScore> combined;
  final Map<String, Float64List> perAxisPhi;
  /// id-to-path lookup matching the engine's internal node ordering
  /// (so consumers can index per-axis vectors without re-deriving it).
  final List<String> nodePaths;
  /// path → label of the axis that contributed the most φ at that node.
  final Map<String, String> dominantAxis;
  /// path → axis-label → fraction of φ contributed by that axis (sums
  /// to 1 per path, modulo silent axes which omit their entry).
  final Map<String, Map<String, double>> shareByAxis;

  const AxisAttribution({
    required this.combined,
    required this.perAxisPhi,
    required this.nodePaths,
    required this.dominantAxis,
    required this.shareByAxis,
  });

  /// Sum of φ contributed by [axisLabel] across all nodes. Useful for
  /// "this axis carried 38% of the total mass."
  double totalMassFor(String axisLabel) {
    final phi = perAxisPhi[axisLabel];
    if (phi == null) return 0;
    var s = 0.0;
    for (var i = 0; i < phi.length; i++) {
      s += phi[i];
    }
    return s;
  }

  /// Map of axis label → fractional total mass. Sums to 1.
  Map<String, double> axisMassFractions() {
    final raw = <String, double>{};
    var total = 0.0;
    for (final entry in perAxisPhi.entries) {
      final m = totalMassFor(entry.key);
      raw[entry.key] = m;
      total += m;
    }
    if (total <= 0) return raw;
    return raw.map((k, v) => MapEntry(k, v / total));
  }
}

class _EdgeCandidate {
  final int node;
  final double pMix;
  const _EdgeCandidate(this.node, this.pMix);
}

class _TierCandidate {
  final String path;
  final double phi;
  final EmissionTier tier;
  final int cost;
  final double info;
  const _TierCandidate(this.path, this.phi, this.tier, this.cost, this.info);
  double get density => info / cost;
}

String _parentDir(String p) {
  final slash = p.lastIndexOf('/');
  return slash < 0 ? '' : p.substring(0, slash);
}

// ═════════════════════════════════════════════════════════════════════════
// DiffusionBasis — cached Chebyshev basis for temperature-slider UIs.
//
// The heat kernel φ(t) = exp(-t·L)·ρ factors into
//
//   φ(t) = Σ_{k=0..K} c_k(t) · (T_k(x) · ρ)
//
// where the `T_k(x)·ρ` vectors are INDEPENDENT of t. Precompute them
// once (O(K·|E|)) and every subsequent "move the slider" is a simple
// weighted sum: O(K·|V|), ~10µs for 5k nodes on a modern CPU.
//
// Exposed on the engine as `engine.buildBasis(sources)`. UI code holds
// the basis as long as the source set is stable and calls
// `basis.recombine(t)` per frame.
// ═════════════════════════════════════════════════════════════════════════

class DiffusionBasis {
  final int n;
  final int K;
  /// Basis vectors stored as a row-major f64 matrix of shape (K+1, n).
  /// basis[k * n + i] = (T_k(x) · ρ)[i].
  final Float64List basis;
  /// The source paths the basis was built from — useful for UI labelling
  /// and diagnostics.
  final Set<String> sources;

  DiffusionBasis._({
    required this.n,
    required this.K,
    required this.basis,
    required this.sources,
  });

  /// Recombine the cached basis at temperature [t]. Output is a fresh
  /// Float64List of length n. Fast enough to call every animation frame.
  ///
  /// Adaptive truncation: at low t the Bessel tail is already below
  /// 1e-8; we skip those terms. At high t we use the full K.
  Float64List recombine(double t) {
    final coeffs = _chebyshevBesselCoeffs(t, K);
    final kEff = _adaptiveK(coeffs, 1e-8);
    final phi = Float64List(n);
    for (var k = 0; k <= kEff; k++) {
      final c = coeffs[k];
      if (c == 0) continue;
      final base = k * n;
      for (var i = 0; i < n; i++) {
        phi[i] += c * basis[base + i];
      }
    }
    return phi;
  }

  /// Recombine AND rank into sorted scores, excluding [sources]. Useful
  /// for UI code that wants the same shape `diffuse()` returns.
  List<RelevanceScore> recombineAndRank(
    double t, {
    required List<String> idToPath,
  }) {
    final phi = recombine(t);
    final results = <RelevanceScore>[];
    for (var i = 0; i < phi.length; i++) {
      final path = idToPath[i];
      if (sources.contains(path)) continue;
      final v = phi[i];
      if (v <= 0) continue;
      results.add(RelevanceScore(path, v));
    }
    results.sort((a, b) => b.phi.compareTo(a.phi));
    return results;
  }
}

DiffusionBasis _buildDiffusionBasis({
  required _CsrGraph graph,
  required Float64List rho,
  required int K,
  required Set<String> sources,
}) {
  final n = graph.n;
  final basis = Float64List((K + 1) * n);

  // T_0·ρ = ρ
  for (var i = 0; i < n; i++) {
    basis[i] = rho[i];
  }

  // T_1·ρ = x·ρ = L_sym·ρ - ρ
  final scratch = Float64List(n);
  final t0 = Float64List.fromList(rho);
  final t1 = Float64List(n);
  graph.applyLsym(t0, scratch);
  for (var i = 0; i < n; i++) {
    t1[i] = scratch[i] - t0[i];
    basis[n + i] = t1[i];
  }

  // Recurrence: T_{k+1} = 2·x·T_k - T_{k-1}
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

  return DiffusionBasis._(n: n, K: K, basis: basis, sources: sources);
}
