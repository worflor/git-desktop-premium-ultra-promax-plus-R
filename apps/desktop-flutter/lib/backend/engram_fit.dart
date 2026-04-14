// ═════════════════════════════════════════════════════════════════════════
// engram_fit.dart — Whisper Engram AR(2) oscillator fit (real specialization)
//
// Direct port of Engram's `fit_pair` kernel: five dot products + a 2×2
// Cramer solve. The Whisper codec tower's central finding is that the
// memory depth of a trajectory is derivable from the signal itself via
// |λ| (spectral radius of the AR(2) characteristic polynomial).
//
//   z[n] = K · z[n-1] − G · z[n-2]
//
//   λ² − K·λ + G = 0
//   |λ| < 1 → decay, |λ| = 1 → sustained orbit, |λ| > 1 → divergent
//
// For our git codec, the "trajectory" is the sequence of consecutive-
// commit file-set similarities: a scalar time series that tells us how
// fast the working set turns over. Fit the AR(2) to it and the half-
// life falls out: k_½ = −ln(2) / ln|λ|. No human-picked constants.
//
// This file is real-only (we only need the 1D specialization). Complex
// generalization would be a direct port; we don't need it for now.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// AR(2) model order: three parameters (K, G, constant term absorbed by
/// centring) over a Cramer system with two unknowns; each row of the
/// least-squares system consumes three samples (z[i-2], z[i-1], z[i]),
/// so one fit row costs 3 samples.
const int _ar2ModelOrder = 2;
const int _ar2SamplesPerRow = 3;

/// Minimum samples for a meaningful AR(2) fit: model order plus the
/// samples one row of the least-squares system consumes plus one extra
/// for least-squares conditioning (matches Engram's `SEED_COUNT + 1`).
/// Falls out to 6 — not chosen, derived. Exposed as [engramMinSamples]
/// for callers that need to pre-gate their inputs to the same threshold.
const int _engramMinSamples =
    _ar2ModelOrder + _ar2SamplesPerRow + 1;
const int engramMinSamples = _engramMinSamples;

/// Ridge regularization scale — lifted from Engram. Tames near-singular
/// normal equations when the input is a flat line / constant signal.
/// ~sqrt(f64 machine epsilon) — the "numerical noise floor" magnitude.
const double _engramRidgeScale = 1e-8;

/// IEEE 754 f64 machine epsilon (2^-52). Named explicitly so the fit's
/// near-singular determinant check reads as a unit-scaled tolerance
/// rather than a mystery constant.
const double _engramMachineEps = 2.2204460492503131e-16;


/// Fallback K when the signal isn't fittable — matches Engram's
/// LINEAR_K (2, 0) which corresponds to a first-order extrapolation.
/// Use this to detect "non-orbital" signals downstream.
const double linearFallbackK = 2.0;
const double linearFallbackG = 0.0;

/// Result of an Engram-style AR(2) fit on a real-valued sequence.
@immutable
class EngramFit {
  /// Lead coefficient: K = 2r·cos(ω₀) for an orbit with radius r and
  /// angular frequency ω₀.
  final double k;

  /// Damping coefficient: G = r². `spectralRadius == sqrt(g)` for the
  /// complex-conjugate-pair case; for over-damped signals use the
  /// formula inside [spectralRadius].
  final double g;

  /// RMS prediction error — how well the fit explains the sequence.
  /// Small relative to the signal magnitude = good fit.
  final double rms;

  /// True when the fit degenerated to the linear-extrapolation fallback
  /// (short input, singular normal equations, etc.). Callers that
  /// derive half-life from the fit should treat this as "no signal."
  final bool isLinearFallback;

  const EngramFit({
    required this.k,
    required this.g,
    required this.rms,
    required this.isLinearFallback,
  });

  /// Default fallback result for sequences that can't be fitted.
  static const linear = EngramFit(
    k: linearFallbackK,
    g: linearFallbackG,
    rms: double.infinity,
    isLinearFallback: true,
  );

  /// Spectral radius |λ_max| of the characteristic polynomial. Values
  /// near 1 = sustained orbit; <1 = decay; >1 = divergent.
  double get spectralRadius {
    // λ² − K·λ + G = 0 → λ = (K ± √(K² − 4G)) / 2
    final disc = k * k - 4 * g;
    if (disc >= 0) {
      // Over-damped: two real roots. Take the larger magnitude.
      final sd = math.sqrt(disc);
      final l1 = ((k + sd) / 2).abs();
      final l2 = ((k - sd) / 2).abs();
      return l1 > l2 ? l1 : l2;
    }
    // Under-damped: complex-conjugate pair. |λ| = sqrt(G) (algebra: the
    // pair is (K ± i√|D|)/2, |·|² = (K² + |D|) / 4 = G).
    return math.sqrt(g.abs());
  }

  /// Lower bound on the orbit's spectral radius. Below this the signal
  /// decays so fast (< 3 samples to half-life) that AR(2) is no better
  /// than a linear fit — not worth treating as an orbit.
  ///   |λ| = 0.3 ⇒ half-life ≈ -ln(2)/ln(0.3) ≈ 0.58 samples.
  static const double _orbitalFloor = 0.3;

  /// Upper bound on the orbit's spectral radius. The mathematical
  /// divergence threshold is exactly 1.0, but we allow a tiny tolerance
  /// above it to absorb the Cramer-solve's numerical error without
  /// misclassifying near-sustained orbits as divergent. The tolerance
  /// is sqrt(machine epsilon) × 10⁶ — several orders above
  /// f64 noise, still far below any genuinely divergent |λ|.
  static const double _orbitalCeiling = 1.02;

  /// True when the fit found a genuine orbit (|λ| close to 1 and lower
  /// than the divergence ceiling). Engram's block segmenter uses the
  /// same idea: keep the orbit until |λ| exceeds the cutoff, then cut.
  bool get isOrbital {
    if (isLinearFallback) return false;
    final r = spectralRadius;
    return r >= _orbitalFloor && r <= _orbitalCeiling;
  }

  /// Half-life of the signal in samples, derived from the fit. Returns
  /// null when the fit doesn't decay (sustained or divergent orbit) or
  /// degenerated to the linear fallback.
  ///
  /// k_½ where |λ|^k = 0.5, i.e. k_½ = −ln(2) / ln|λ|.
  double? get halfLifeSamples {
    if (isLinearFallback) return null;
    final r = spectralRadius;
    if (r <= 0 || r >= 1.0) return null;
    final logR = math.log(r);
    if (logR >= 0 || !logR.isFinite) return null;
    return -math.ln2 / logR;
  }

  /// Natural oscillation period of the orbit, in samples. The
  /// AR(2) characteristic polynomial λ² − K·λ + G = 0 has, for the
  /// under-damped case, a complex-conjugate pair λ = r·e^{±iω₀} with
  /// |λ| = r = √G and angular frequency ω₀ = arccos(K / 2r). The
  /// period in samples is 2π/ω₀ — the "natural rhythm" of the
  /// underlying signal.
  ///
  /// Returns null when:
  ///   • the fit degenerated to linear fallback
  ///   • the roots are real (over-damped — no oscillation)
  ///   • |K / 2r| ≥ 1 (numerical edge: would be acos out-of-domain)
  ///   • the period is degenerate (ω₀ ≈ 0 → infinite period)
  ///
  /// Used by callers that want to reason about the *cadence* of a
  /// signal, not just its decay. Example: commit-rate AR(2) fits
  /// expose this as the repo's "natural commit rhythm" in samples
  /// (days, given how the series is constructed).
  double? get oscillationPeriodSamples {
    if (isLinearFallback) return null;
    final disc = k * k - 4 * g;
    if (disc >= 0) return null; // over-damped → no oscillation
    final r = spectralRadius;
    if (r <= 0) return null;
    final ratio = k / (2 * r);
    if (ratio.abs() >= 1.0) return null; // acos domain guard
    final omega = math.acos(ratio);
    if (omega <= 1e-9 || !omega.isFinite) return null;
    return 2 * math.pi / omega;
  }
}

/// Fit an AR(2) oscillator to a real-valued 1D time series.
///
/// Minimises Σ (z[n] − (K·z[n-1] − G·z[n-2]))². Returns the fit
/// parameters plus an RMS. Singular/short inputs return
/// [EngramFit.linear].
///
/// Accepts a [List<double>] or a [Float64List]; the latter avoids boxing.
EngramFit engramFit(List<double> z) {
  final t = z.length;
  if (t < _engramMinSamples) return EngramFit.linear;

  final n = t - 2;
  double sAa = 0.0; // Σ a²  (a = z[i+1])
  double sBb = 0.0; // Σ b²  (b = z[i])
  double sTt = 0.0; // Σ t²  (t = z[i+2])
  double sAb = 0.0; // Σ a·b
  double sTa = 0.0; // Σ t·a
  double sTb = 0.0; // Σ t·b

  for (var i = 0; i < n; i++) {
    final a = z[i + 1];
    final b = z[i];
    final x = z[i + 2];
    sAa += a * a;
    sBb += b * b;
    sTt += x * x;
    sAb += a * b;
    sTa += x * a;
    sTb += x * b;
  }

  // Ridge regularization guards against a singular normal equation on
  // constant/linear inputs. Lifted directly from Engram's solve.
  final trace = sAa + sBb;
  final ridge =
      _engramMachineEps > _engramRidgeScale * trace * 0.5
          ? _engramMachineEps
          : _engramRidgeScale * trace * 0.5;
  final sAaR = sAa + ridge;
  final sBbR = sBb + ridge;
  final det = sAaR * sBbR - sAb * sAb;
  if (det.abs() < _engramMachineEps * trace * trace) {
    return EngramFit.linear;
  }
  final invDet = 1.0 / det;

  // Cramer solve: K = (s_ta · s_bb − s_ab · s_tb) / det
  //               G = (s_ab · s_ta − s_aa · s_tb) / det
  final kFit = (sTa * sBbR - sAb * sTb) * invDet;
  final gFit = (sAb * sTa - sAaR * sTb) * invDet;

  // Algebraic RMS — avoids a second pass through z.
  final errSq = sTt +
      kFit * kFit * sAa +
      gFit * gFit * sBb -
      2 * kFit * sTa +
      2 * gFit * sTb -
      2 * kFit * gFit * sAb;
  final rms = math.sqrt((errSq < 0 ? 0 : errSq) / n);

  if (!kFit.isFinite || !gFit.isFinite) return EngramFit.linear;

  return EngramFit(k: kFit, g: gFit, rms: rms, isLinearFallback: false);
}

/// Fit an AR(2) to a [Float64List] directly — same math, avoids the
/// `List<double>` dispatch overhead on tight loops.
EngramFit engramFitF64(Float64List z) => engramFit(z);

/// Shared helper: build the sequence of consecutive-commit file-set
/// Jaccard similarities. The "trajectory" every downstream Engram
/// integration is asking about.
///
///   sim[i] = |C_i ∩ C_{i+1}| / |C_i ∪ C_{i+1}|
///
/// `commitFileSets` is ordered oldest→newest; output length is N-1.
/// Empty/single-commit inputs return an empty list. Extracted to a
/// single location so the half-life derivation, branch-orbit fit, and
/// AI commit-shape probe all read the same math.
List<double> consecutiveJaccardSeries(List<Set<String>> commitFileSets) {
  final n = commitFileSets.length;
  if (n < 2) return const [];
  final sims = List<double>.filled(n - 1, 0);
  for (var i = 0; i < n - 1; i++) {
    final a = commitFileSets[i];
    final b = commitFileSets[i + 1];
    if (a.isEmpty && b.isEmpty) {
      sims[i] = 0;
      continue;
    }
    final inter = a.intersection(b).length;
    final union = a.union(b).length;
    sims[i] = union == 0 ? 0 : inter / union;
  }
  return sims;
}

// ═════════════════════════════════════════════════════════════════════════
// BRANCH ORBIT — user-facing classification of a commit sequence
// ═════════════════════════════════════════════════════════════════════════
//
// Reuses the AR(2) fit to ask a question developers actually have:
//   "Is this branch *converging* (commits narrowing on a theme), or
//    *diverging* (commits sprawling across unrelated files)?"
//
// Signal: consecutive-commit file-set Jaccard similarity. The fit's
// spectral radius tells us whether the pattern persists; a linear
// regression on the series tells us whether it's trending up (higher
// overlap = converging) or down (lower overlap = diverging). The two
// together classify the orbit.

/// Minimum per-commit trend-slope magnitude to call a chain "converging"
/// or "diverging". Anything inside ±[_trendThreshold] is noise-level
/// and maps to [branchLabelSteady] (or null when there's no orbit).
/// Tuned empirically: ~1.5% per step comfortably clears day-to-day jitter.
const double _trendThreshold = 0.015;

/// Canonical branch-trajectory labels. Exposed so consumers (AI prompts,
/// UI pills, audit logs) can match against the same literals the fit
/// produces without rebuilding the vocabulary each time. Authoritative
/// source of truth — any other place comparing to 'converging' / etc.
/// should import these instead.
const String branchLabelConverging = 'converging';
const String branchLabelDiverging = 'diverging';
const String branchLabelSteady = 'steady';

/// Convergence/divergence classification for a sequence of commits.
/// The user-visible payload: a label plus the underlying metrics so
/// downstream code can customise messaging without re-deriving them.
@immutable
class BranchOrbit {
  final EngramFit fit;
  /// Slope of a least-squares linear fit on the centred similarity
  /// series (indexed so the most recent step has the highest index).
  /// Positive slope = file overlap is *rising* toward the tip → the
  /// author is narrowing their working set.
  final double trendSlope;
  /// Number of consecutive-commit similarities the fit consumed.
  final int samples;
  /// Mean of the raw Jaccard series — useful context for downstream
  /// messaging ("high-overlap chain" vs "bursty chain").
  final double meanSimilarity;

  const BranchOrbit({
    required this.fit,
    required this.trendSlope,
    required this.samples,
    required this.meanSimilarity,
  });

  /// Trivial orbit for inputs too short to analyse. All classification
  /// getters return false so callers degrade silently.
  static const insufficient = BranchOrbit(
    fit: EngramFit.linear,
    trendSlope: 0,
    samples: 0,
    meanSimilarity: 0,
  );

  /// Signal-validity threshold: at least as many similarity samples as
  /// the fit itself needed rows. Below this the slope estimate is
  /// undetermined even if the fit technically returned parameters.
  static const int _minSamplesForSignal = _engramMinSamples - _ar2ModelOrder;

  bool get hasSignal =>
      !fit.isLinearFallback &&
      samples >= _minSamplesForSignal &&
      fit.rms.isFinite;

  /// Converging: stable orbit AND trend slope ≥ +ε. The author's recent
  /// commits share more files than their older ones — narrowing scope.
  bool get isConverging {
    if (!hasSignal) return false;
    if (!fit.isOrbital) return false;
    return trendSlope > _trendThreshold;
  }

  /// Diverging: stable orbit with negative trend, OR non-orbital with a
  /// strong negative trend. File overlap eroding toward the tip — scope
  /// sprawling. We gate on |slope| so mild noise doesn't trip it.
  bool get isDiverging {
    if (!hasSignal) return false;
    return trendSlope < -_trendThreshold;
  }

  /// Short label suitable for a UI pill or AI prompt line. Null when
  /// the orbit has no signal — callers should suppress the annotation
  /// entirely rather than render "unknown".
  String? get characterLabel {
    if (!hasSignal) return null;
    if (isConverging) return branchLabelConverging;
    if (isDiverging) return branchLabelDiverging;
    if (fit.isOrbital) return branchLabelSteady;
    return null;
  }
}

/// Compute a [BranchOrbit] from an ordered list of per-commit file
/// sets. `commitFileSets[0]` should be the *oldest* commit, last is
/// the tip — this matches how the tagger already iterates chains.
///
/// Returns [BranchOrbit.insufficient] for < 6 commits (AR(2) needs a
/// handful of samples to mean anything).
BranchOrbit computeBranchOrbit(List<Set<String>> commitFileSets) {
  final n = commitFileSets.length;
  // Same minimum as the fit itself — the Jaccard series will have
  // n-1 samples, so n = _engramMinSamples guarantees at least one
  // least-squares row beyond the AR(2) model's own row count.
  if (n < _engramMinSamples) return BranchOrbit.insufficient;

  // Consecutive-commit Jaccard series — same shared helper the repo-
  // wide half-life derivation and the AI branch-trajectory probe use.
  final sims = consecutiveJaccardSeries(commitFileSets);

  // Mean and centred series.
  var mean = 0.0;
  for (final s in sims) {
    mean += s;
  }
  mean /= sims.length;
  final centred = List<double>.generate(sims.length, (i) => sims[i] - mean);

  // Least-squares slope on the (index, sims[i]) series. Indexing by i
  // so positive slope ⇒ similarity rises toward the tip (converging).
  final m = sims.length;
  var sumI = 0.0, sumI2 = 0.0, sumS = 0.0, sumIS = 0.0;
  for (var i = 0; i < m; i++) {
    sumI += i;
    sumI2 += i * i;
    sumS += sims[i];
    sumIS += i * sims[i];
  }
  final denom = m * sumI2 - sumI * sumI;
  final slope = denom == 0 ? 0.0 : (m * sumIS - sumI * sumS) / denom;

  final fit = engramFit(centred);
  return BranchOrbit(
    fit: fit,
    trendSlope: slope,
    samples: m,
    meanSimilarity: mean,
  );
}
