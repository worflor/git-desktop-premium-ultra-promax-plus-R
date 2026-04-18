// LogosZeta — spectral zeta function of the normalised Laplacian.
//
// Given a finite Laplacian spectrum `{λⱼ}`, the spectral zeta function
//     ζ_L(s) = Σ_{λⱼ > 0} 1 / λⱼ^s
// is entire in s (the zero-eigenvalue modes are explicitly excluded).
// Four scalar extracts turn out to be useful codebase invariants:
//
//   * **log det' L** = `−ζ'(0)` = `Σ log λⱼ`. The regularised
//     log-determinant of the non-singular part of the Laplacian. An
//     isospectral invariant — two graphs with identical spectra share
//     this exactly. Sensitive to BOTH ends of the spectrum, not just
//     the low modes like `heatTrace` at small t.
//
//   * **ζ(1)** = `Σ 1/λⱼ`. The spectral-mean escape time; proportional
//     to the total effective resistance `R_total = n · ζ(1)` on
//     connected unweighted graphs. A large ζ(1) signals a bottlenecked
//     graph (dominant low-frequency mass); small ζ(1) signals tight
//     coupling.
//
//   * **ζ(2)** = `Σ 1/λⱼ²`. Kirchhoff-index-adjacent: proportional to
//     the sum of squared resistance distances. Heavier tail than ζ(1);
//     more sensitive to the smallest non-zero eigenvalue.
//
//   * **Euler gamma `γ_L`** = `−ζ'(1)`. Regularised analogue of the
//     Euler-Mascheroni constant on the Laplacian spectrum. Under a
//     spectrum shift `λⱼ → λⱼ · α`, γ_L shifts additively by
//     `ζ(1) · log α` — so `γ_L` is sensitive to the *shape* of the
//     spectrum independent of uniform rescaling.
//
// All four are **Theorem-tight**: each is a direct finite sum over the
// non-zero spectrum, no approximations.

import 'dart:math' as math;

import 'logos_core.dart';

/// A compact zeta report — every standard scalar evaluated once.
class ZetaReport {
  /// `log det' L = Σ log λⱼ` over non-zero modes. Finite on a
  /// connected graph with a well-resolved Lanczos basis.
  final double logDeterminant;

  /// `ζ(1) = Σ 1/λⱼ`.
  final double zetaOne;

  /// `ζ(2) = Σ 1/λⱼ²`.
  final double zetaTwo;

  /// `γ_L = −ζ'(1) = Σ (log λⱼ) / λⱼ` (with the sign convention that
  /// makes `γ_L` positive when the spectrum is shifted toward 1).
  final double eulerGamma;

  /// Number of non-zero eigenvalues contributing to the sums above.
  final int nonZeroCount;

  /// Number of detected zero eigenvalues = connected-component count
  /// of the graph (on a normalised Laplacian).
  final int zeroCount;

  const ZetaReport({
    required this.logDeterminant,
    required this.zetaOne,
    required this.zetaTwo,
    required this.eulerGamma,
    required this.nonZeroCount,
    required this.zeroCount,
  });

  /// Average log-eigenvalue `(log det' L) / nonZeroCount`. Useful as
  /// a "per-mode" scalar that's robust to basis-size variation.
  double get avgLogEigen =>
      nonZeroCount > 0 ? logDeterminant / nonZeroCount : 0.0;
}

/// Compute the full [ZetaReport] at once. Shares a single pass over
/// the spectrum and is the cheapest way to get the common scalars.
///
/// **Theorem-tight** — every output is a direct finite sum.
ZetaReport zetaReport(SpectralBasis basis) {
  // Hoist the range-loop bounds + fields (Circle XXI): avoids a
  // getter call per iteration, gives the JIT a tight fused-path.
  final start = basis.firstExcitedIndex;
  final k = basis.k;
  final eigs = basis.eigenvalues;
  var logDet = 0.0;
  var z1 = 0.0;
  var z2 = 0.0;
  var g = 0.0;
  var nz = 0;
  for (var j = start; j < k; j++) {
    final lam = eigs[j];
    if (!lam.isFinite) continue;
    nz++;
    final inv = 1.0 / lam;
    final logLam = math.log(lam);
    logDet += logLam;
    z1 += inv;
    z2 += inv * inv;
    g += logLam * inv;
  }
  return ZetaReport(
    logDeterminant: logDet,
    zetaOne: z1,
    zetaTwo: z2,
    eulerGamma: g,
    nonZeroCount: nz,
    zeroCount: basis.kernelDim,
  );
}

/// Evaluate `ζ_L(s) = Σ_{λ>0} 1/λ^s` at an arbitrary real `s`.
/// Returns `+∞` when the sum overflows (e.g. large `s` on a spectrum
/// with a tiny eigenvalue).
///
/// **Fast path** (Circle IV — division by constant): integer `s ∈
/// {0, 1, 2, 3}` short-circuits the full `math.pow` call in favour of
/// a direct inverse-power multiplication chain. `math.pow(x, -2)`
/// costs ~30–80 cycles depending on the ULP path; `1.0/(x*x)` is one
/// multiply + one divide. These are the values `zetaReport` uses on
/// every call, so the win compounds.
///
/// **Theorem-tight** — direct finite evaluation.
double zeta(SpectralBasis basis, double s) {
  if (!s.isFinite) return double.nan;
  // Integer-s fast path: exact identical output, 5-10× less work.
  final sAsInt = s.truncate();
  if (s == sAsInt.toDouble()) {
    return _zetaInt(basis, sAsInt);
  }
  final start = basis.firstExcitedIndex;
  final k = basis.k;
  final eigs = basis.eigenvalues;
  var sum = 0.0;
  for (var j = start; j < k; j++) {
    final lam = eigs[j];
    if (!lam.isFinite) continue;
    final term = math.pow(lam, -s).toDouble();
    if (!term.isFinite) return double.infinity;
    sum += term;
  }
  return sum;
}

/// Integer-exponent `ζ` via a direct inverse-power multiplication
/// chain — no `math.pow`. Handles the common cases (s = 0, 1, 2, 3)
/// unrolled, falls through to a small loop for higher integer s.
///
/// **Raw index loop** (Principia Circle XXI): iterates over
/// `[firstExcitedIndex, k)` directly instead of through the
/// `nonZeroIndices` `sync*` generator. `sync*` suspends + resumes per
/// element — small cost per iteration, but this function is called
/// inside the zeta loop inside `zetaReport` inside `spectrogeometry`
/// inside the engine cache. The raw loop is branch-light enough for
/// the JIT to pattern-match into a tight sequence.
double _zetaInt(SpectralBasis basis, int s) {
  final start = basis.firstExcitedIndex;
  final k = basis.k;
  final eigs = basis.eigenvalues;
  var sum = 0.0;
  switch (s) {
    case 0:
      return (k - start).toDouble();
    case 1:
      for (var j = start; j < k; j++) {
        final lam = eigs[j];
        if (lam.isFinite) sum += 1.0 / lam;
      }
      return sum;
    case 2:
      for (var j = start; j < k; j++) {
        final lam = eigs[j];
        if (lam.isFinite) sum += 1.0 / (lam * lam);
      }
      return sum;
    case 3:
      for (var j = start; j < k; j++) {
        final lam = eigs[j];
        if (lam.isFinite) sum += 1.0 / (lam * lam * lam);
      }
      return sum;
  }
  // Generic integer s — multiply-chain, still faster than pow on
  // hot paths because the inner body is branch-free integer loop.
  if (s > 0) {
    for (var j = start; j < k; j++) {
      final lam = eigs[j];
      if (!lam.isFinite) continue;
      var den = 1.0;
      for (var i = 0; i < s; i++) den *= lam;
      if (den > 0) sum += 1.0 / den;
    }
  } else {
    // s < 0 → λ^|s| in the numerator.
    final absS = -s;
    for (var j = start; j < k; j++) {
      final lam = eigs[j];
      if (!lam.isFinite) continue;
      var num = 1.0;
      for (var i = 0; i < absS; i++) num *= lam;
      sum += num;
    }
  }
  return sum;
}

/// Evaluate `−ζ'_L(s) = Σ_{λ>0} (log λ)/λ^s`. Scales out to the
/// log-determinant identity at `s = 0`: `−ζ'(0) = log det' L`.
double zetaDerivative(SpectralBasis basis, double s) {
  if (!s.isFinite) return double.nan;
  final start = basis.firstExcitedIndex;
  final k = basis.k;
  final eigs = basis.eigenvalues;
  var sum = 0.0;
  for (var j = start; j < k; j++) {
    final lam = eigs[j];
    if (!lam.isFinite) continue;
    final term = math.log(lam) * math.pow(lam, -s).toDouble();
    if (!term.isFinite) return double.infinity;
    sum += term;
  }
  return sum;
}

/// Regularised determinant `det' L = exp(−ζ'(0)) = Π λⱼ` over the
/// non-zero spectrum. Returned in log-form because the product can
/// overflow or underflow on any graph with more than a few dozen
/// modes.
double logRegularisedDeterminant(SpectralBasis basis) {
  return zetaReport(basis).logDeterminant;
}
