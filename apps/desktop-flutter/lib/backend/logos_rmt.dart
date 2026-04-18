// LogosRMT — Random Matrix Theory diagnostics on the repo's Laplacian
// spectrum.
//
// The normalised graph Laplacian `L_sym` is real symmetric. RMT
// classifies such spectra into three canonical universality lines:
//
//   * **GOE** (Gaussian Orthogonal Ensemble) — chaotic/random
//     structure. Mean Mehta-Dyson ratio ≈ 0.5359.
//   * **GUE** (Gaussian Unitary Ensemble) — chaotic + time-reversal
//     broken. ≈ 0.6027.
//   * **Poisson** — integrable/structured (paths, trees, regular
//     lattices). Uncorrelated levels. ≈ 0.3863.
//
// For a git client this becomes a direct read of "how structured is
// this repo?". Tightly organised modular code reads as partly-Poisson;
// spaghetti reads closer to GOE; hybrid repos fall between.
//
// Three observables:
//
//   * Mehta-Dyson r-ratio (mean, distribution)
//   * Level-spacing distribution P(s) compared to Wigner surmise
//   * Number variance Σ²(L)

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';

/// Classification of the spectral ensemble.
///
/// Three canonical RMT classes (poisson/goe/gue) sit in meanR ≈
/// `[0.39, 0.60]`. Outside that band we add two shoulder classes —
/// crystalline spectra (very-smooth spacings, meanR → 1) and sub-
/// Poisson anti-correlated spectra (meanR ≪ 0.39) — so the classifier
/// has somewhere to put real-world graphs like paths and cycles whose
/// ladders don't fit the classical ensembles.
enum RmtClass {
  /// ⟨r⟩ < 0.30 — very anti-correlated; spacings alternate between
  /// big and small. Unusual for Laplacians; flag as structural oddity.
  subPoisson,

  /// 0.30 ≤ ⟨r⟩ < 0.45 — Poisson-like, random spacings. Integrable
  /// systems with independent levels.
  poisson,

  /// 0.45 ≤ ⟨r⟩ < 0.56 — intermediate; partial mixing.
  intermediate,

  /// 0.56 ≤ ⟨r⟩ < 0.58 — GOE, chaotic (typical for "real" random graphs).
  goe,

  /// 0.58 ≤ ⟨r⟩ < 0.70 — GUE, chaotic + broken time-reversal symmetry.
  gue,

  /// ⟨r⟩ ≥ 0.70 — crystalline: consecutive spacings are very similar,
  /// the ladder is nearly arithmetic. Typical for path / cycle
  /// Laplacians whose eigenvalues smoothly follow `1 − cos(πj/n)`.
  crystalline,
}

/// Reference means for the three universality classes.
const double kGoeMeanR = 0.5359;
const double kGueMeanR = 0.6027;
const double kPoissonMeanR = 0.3863;

/// Compact RMT report for a spectrum.
class RmtReport {
  /// Mean of the Mehta-Dyson r-ratios across adjacent level triplets.
  final double meanR;

  /// Classified universality class from [meanR].
  final RmtClass classification;

  /// Full distribution of r-ratios (one value per adjacent pair of
  /// level spacings). Empty when the spectrum is too short.
  final Float64List rValues;

  /// Normalised (unfolded) level spacings `sₙ / ⟨s⟩`. Feed these into
  /// the Wigner-surmise comparison below.
  final Float64List unfoldedSpacings;

  /// Goodness-of-fit scalar: integrated absolute difference between
  /// the empirical CDF of unfolded spacings and the Wigner-Dyson CDF.
  /// 0 = perfect Wigner-Dyson match; higher = further.
  final double wignerDeviation;

  /// Goodness-of-fit scalar against the Poisson CDF. Same scale as
  /// [wignerDeviation]. Compare both: the smaller one wins.
  final double poissonDeviation;

  const RmtReport({
    required this.meanR,
    required this.classification,
    required this.rValues,
    required this.unfoldedSpacings,
    required this.wignerDeviation,
    required this.poissonDeviation,
  });

  /// Short human-readable label — "poisson (structured)" / "goe (chaotic)"
  /// / etc. Useful for UI chrome.
  String get label {
    switch (classification) {
      case RmtClass.subPoisson:
        return 'sub-poisson · anti-correlated';
      case RmtClass.poisson:
        return 'poisson · integrable';
      case RmtClass.intermediate:
        return 'intermediate';
      case RmtClass.goe:
        return 'goe · chaotic';
      case RmtClass.gue:
        return 'gue · chaotic·broken-T';
      case RmtClass.crystalline:
        return 'crystalline · regular';
    }
  }
}

/// Compute a full RMT report on a basis's eigenvalue ladder. Returns
/// `null` when the spectrum is too short (< 4 levels) for stats.
RmtReport? rmtReport(SpectralBasis basis) {
  if (basis.k < 4) return null;
  final eigs = Float64List.fromList(basis.eigenvalues)..sort();
  // Spacings sₙ = λ_{n+1} − λ_n.
  final n = eigs.length;
  if (n < 4) return null;
  final spacings = Float64List(n - 1);
  for (var i = 0; i < n - 1; i++) {
    spacings[i] = eigs[i + 1] - eigs[i];
  }
  // Mean spacing — used to unfold so the series is dimensionless.
  var sumS = 0.0;
  for (final s in spacings) sumS += s;
  final meanS = sumS / spacings.length;
  if (meanS <= 1e-300) return null;
  final unfolded = Float64List(spacings.length);
  for (var i = 0; i < spacings.length; i++) {
    unfolded[i] = spacings[i] / meanS;
  }
  // Mehta-Dyson r-ratios (bounded in [0, 1], self-normalising).
  final rValues = Float64List(spacings.length - 1);
  for (var i = 0; i < rValues.length; i++) {
    final s1 = spacings[i];
    final s2 = spacings[i + 1];
    final mx = math.max(s1, s2);
    if (mx <= 1e-300) {
      rValues[i] = 0.0;
      continue;
    }
    rValues[i] = math.min(s1, s2) / mx;
  }
  var sumR = 0.0;
  for (final r in rValues) sumR += r;
  final meanR = rValues.isEmpty ? 0.0 : sumR / rValues.length;
  // CDF distances vs Wigner and Poisson shapes.
  final wigner = _cdfDeviation(unfolded, _wignerCdf);
  final poisson = _cdfDeviation(unfolded, _poissonCdf);
  // Classify from meanR. Thresholds spaced so the three canonical RMT
  // means (Poisson 0.39, GOE 0.54, GUE 0.60) sit at the centres of
  // their bands; crystalline / sub-Poisson catch the shoulders.
  final RmtClass cls;
  if (meanR < 0.30) {
    cls = RmtClass.subPoisson;
  } else if (meanR < 0.45) {
    cls = RmtClass.poisson;
  } else if (meanR < 0.56) {
    cls = RmtClass.intermediate;
  } else if (meanR < 0.58) {
    cls = RmtClass.goe;
  } else if (meanR < 0.70) {
    cls = RmtClass.gue;
  } else {
    cls = RmtClass.crystalline;
  }
  return RmtReport(
    meanR: meanR,
    classification: cls,
    rValues: rValues,
    unfoldedSpacings: unfolded,
    wignerDeviation: wigner,
    poissonDeviation: poisson,
  );
}

/// Wigner surmise CDF for GOE:
///     P(s < x) = 1 − exp(−π x² / 4)
double _wignerCdf(double x) => 1.0 - math.exp(-math.pi * x * x / 4.0);

/// Poisson CDF:
///     P(s < x) = 1 − exp(−x)
double _poissonCdf(double x) => 1.0 - math.exp(-x);

/// Integrated absolute difference between the empirical CDF of
/// [sorted] samples and [reference]. A normalised Kolmogorov-ish
/// distance.
double _cdfDeviation(Float64List samples, double Function(double) reference) {
  if (samples.isEmpty) return 0.0;
  final sorted = Float64List.fromList(samples)..sort();
  // Sample the difference at a uniform grid of 64 points.
  const gridN = 64;
  final xMax = sorted.last;
  if (xMax <= 1e-9) return 0.0;
  var maxDiff = 0.0;
  for (var i = 1; i <= gridN; i++) {
    final x = (i / gridN) * xMax;
    // Empirical CDF at x.
    var k = 0;
    for (final s in sorted) {
      if (s <= x) k++;
    }
    final emp = k / sorted.length;
    final ref = reference(x);
    final d = (emp - ref).abs();
    if (d > maxDiff) maxDiff = d;
  }
  return maxDiff;
}

/// Number variance Σ²(L) — the variance of the number of eigenvalues
/// that fall in an interval of length L drawn from a random position
/// in the unfolded spectrum. Chaotic spectra: `Σ²(L) ~ log(L) / π²`.
/// Poisson: `Σ²(L) = L`. One of the classical RMT discriminators.
///
/// Returns `null` when the spectrum is too short to support the
/// chosen `L` (need at least L + 2 levels per window).
double? numberVariance(SpectralBasis basis, double L, {int windows = 32}) {
  if (basis.k < 8) return null;
  final eigs = Float64List.fromList(basis.eigenvalues)..sort();
  final n = eigs.length;
  if (n < 6) return null;
  // Normalise the spectrum to mean spacing 1 (unfolding).
  final mean = (eigs.last - eigs.first) / (n - 1);
  if (mean <= 1e-300) return null;
  final unfolded = Float64List(n);
  for (var i = 0; i < n; i++) {
    unfolded[i] = (eigs[i] - eigs.first) / mean;
  }
  // Sample `windows` intervals of length L at random-ish positions.
  final fullRange = unfolded.last - L;
  if (fullRange <= 1) return null;
  final rng = math.Random(0xA11CE); // deterministic
  final counts = <int>[];
  for (var w = 0; w < windows; w++) {
    final start = rng.nextDouble() * fullRange;
    final end = start + L;
    var c = 0;
    for (final x in unfolded) {
      if (x >= start && x < end) c++;
    }
    counts.add(c);
  }
  // Sample mean and variance.
  var sum = 0.0;
  for (final c in counts) sum += c;
  final m = sum / counts.length;
  var v = 0.0;
  for (final c in counts) {
    final d = c - m;
    v += d * d;
  }
  return v / counts.length;
}
