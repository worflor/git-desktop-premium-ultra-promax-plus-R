// LogosChaos — diffusion-based "chaos" diagnostics on the repo's
// Laplacian spectrum.
//
// The heat kernel `K_t = exp(−t·L_sym)` captures how a perturbation
// spreads through the graph. Two classical scalars summarise its
// geometry at a given resolution:
//
//   * **Spectral dimension** `d_s` — from the short-t asymptotic of
//     the heat-kernel trace. On a d-dimensional Euclidean manifold,
//       Z(t) = tr K_t ≈ n · (4πt)^{-d/2}   →   log Z ≈ C − (d/2)·log t
//     so d_s is extracted from the slope of `log Z(t)` vs `log t`.
//     On a path or a tree the graph is effectively 1-d (small d_s);
//     on a cycle / 2-lattice d_s ≈ 2; on a random graph or hypercube
//     d_s reflects the expander geometry.
//
//   * **Relaxation rate** `γ(t) = −d log Z / dt` — the instantaneous
//     exponential decay rate of the heat trace. At large t this
//     asymptotes to the spectral gap `λ₁` (the Fiedler eigenvalue);
//     at small t it reflects the "average temperature" of the
//     spectrum. A smoothly-decaying `γ(t)` is a signature of
//     spectrally-rich graphs; a quickly-saturating `γ` signals a
//     gap-dominated spectrum (e.g. one dominant cluster).
//
// Why this matters for a git client: a repo's spectral dimension is a
// coarse read of its connectivity topology — how "many-dimensional" is
// its dependency graph? A 1-d read means chain-like modules; 2-d reads
// mean grid-like or ring-like coupling; higher reads mean densely
// interlinked. The relaxation rate `γ(t)` tells us how quickly a
// localized architectural change (a PR's mass impulse) fades into the
// global system — the repo's "memory length" in coupling units.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';
import 'logos_curve.dart';

/// Summary of a log-log fit of `Z(t)` vs `t`. Slope · (−2) = spectral
/// dimension.
class SpectralDimensionReport {
  /// Estimated spectral dimension `d_s` from the log-log slope of
  /// `Z(t) = Σⱼ e^{−t·λⱼ}`.
  final double dS;

  /// Coefficient of determination (R²) of the linear regression —
  /// how close the heat-trace data is to a true power law on the
  /// chosen fitting window. R² ≈ 1 means the repo's spectrum is
  /// cleanly power-lawish there; R² ≪ 1 means no single dimension
  /// describes its diffusion behaviour.
  final double rSquared;

  /// The t values at which Z was sampled.
  final Float64List tSamples;

  /// `log Z(tᵢ)` at each sample.
  final Float64List logZ;

  /// Left/right edges of the fitting window in t.
  final double tMin;
  final double tMax;

  const SpectralDimensionReport({
    required this.dS,
    required this.rSquared,
    required this.tSamples,
    required this.logZ,
    required this.tMin,
    required this.tMax,
  });

  /// Informal classification of `d_s`. Useful for UI chrome.
  String get label {
    if (!dS.isFinite) return 'undefined';
    if (dS < 1.2) return 'quasi-1d · chain-like';
    if (dS < 1.8) return 'fractal · tree-like';
    if (dS < 2.3) return 'planar · surface-like';
    if (dS < 3.2) return 'bulk · 3d-ish';
    return 'high-dim · dense';
  }
}

/// Estimate the spectral dimension from the heat-kernel trace.
///
/// Samples `Z(t) = tr exp(−t·L_sym)` at [samples] log-spaced t values
/// between [tMin] and [tMax], then fits a linear regression of
/// `log Z` vs `log t`. Returns the slope times −2 as `d_s`.
///
/// Returns `null` when the basis has fewer than 4 eigenvalues (the fit
/// degenerates) or when the heat trace collapses before the sweep
/// completes.
///
/// **Theorem-tight** — `d_s` is the standard small-t exponent of the
/// heat-kernel trace on a manifold; the identity
/// `Z(t) ~ C · t^{-d_s/2}` follows from the heat-kernel expansion.
///
/// Implementation note: composes over the [ObservableCurve] primitive
/// from `logos_curve.dart`. The log-log linear fit that used to live
/// inline here is now a single `.logLogSlope()` call; the goodness-
/// of-fit derivation stays local because it uses intermediate sums
/// the curve doesn't surface.
SpectralDimensionReport? spectralDimension(
  SpectralBasis basis, {
  double tMin = 0.1,
  double tMax = 3.0,
  int samples = 24,
}) {
  if (basis.k < 4) return null;
  if (!(tMax > tMin) || tMin <= 0) return null;
  if (samples < 4) return null;

  // Sample the heat trace on a log grid, dropping any t where the
  // trace underflows — the curve primitive demands strictly finite
  // positive y-values for logLogSlope to succeed.
  final ts = logspace(tMin, tMax, samples);
  final validTs = <double>[];
  final validZs = <double>[];
  for (var i = 0; i < samples; i++) {
    final z = basis.heatTrace(ts[i]);
    if (z.isFinite && z > 1e-300) {
      validTs.add(ts[i]);
      validZs.add(z);
    }
  }
  if (validTs.length < 4) return null;

  final curve = ObservableCurve.sampled(
    xs: Float64List.fromList(validTs),
    ys: Float64List.fromList(validZs),
    xLabel: 't',
    yLabel: 'Z(t)',
  );
  // One-pass log-log regression: slope + R² together (Circle XXI).
  final fit = curve.logLogFit();
  if (fit == null) return null;

  // Derive log Z(t) once for the report; cheap O(n) pass.
  final n = curve.xs.length;
  final logZs = Float64List(n);
  for (var i = 0; i < n; i++) {
    logZs[i] = math.log(curve.ys[i]);
  }

  return SpectralDimensionReport(
    dS: -2.0 * fit.slope,
    rSquared: fit.rSquared,
    tSamples: Float64List.fromList(validTs),
    logZ: logZs,
    tMin: tMin,
    tMax: tMax,
  );
}

/// Build the relaxation-rate curve `γ(t)` over a log grid. Peak +
/// half-life of this curve give "when does the repo's energy mostly
/// escape its highest modes?"
///
/// Relocated from `logos_curve.dart` to break the import cycle —
/// the curve primitive is now a pure dependency; every source-module
/// factory lives next to its backing function.
ObservableCurve relaxationCurve(
  SpectralBasis basis, {
  double tMin = 0.1,
  double tMax = 50.0,
  int samples = 32,
}) {
  final ts = logspace(tMin, tMax, samples);
  final ys = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    ys[i] = relaxationRate(basis, ts[i]) ?? 0.0;
  }
  return ObservableCurve.sampled(
    xs: ts,
    ys: ys,
    xLabel: 't',
    yLabel: 'γ(t)',
  );
}

/// Relaxation rate of the heat trace toward its ground state at
/// time `t`. Defined as the Boltzmann average of `λ` restricted to
/// **non-zero modes**:
///     γ(t) = Σⱼ (λⱼ > ε) λⱼ e^{−t·λⱼ} / Σⱼ (λⱼ > ε) e^{−t·λⱼ}.
///
/// Equivalently, `γ(t) = −d log (Z(t) − Z_∞) / dt` where
/// `Z_∞ = dim ker L_sym` is the number of connected components.
///
/// The zero-mode exclusion is essential: on a connected graph,
/// `e^{-t·0} = 1` dominates Z at large t and would drive a naive
/// `γ_naive = ⟨λ⟩_t` toward 0 (the ground-state energy) — which is
/// mathematically correct but physically uninformative. What we want
/// is how fast the NON-ground part of the distribution relaxes; that
/// rate asymptotes to the spectral gap `λ₁` as `t → ∞`.
///
/// Returns `null` when the spectrum has no non-zero modes above the
/// detection threshold, or when the restricted trace collapses at the
/// requested t (underflow).
///
/// **Theorem-tight** — direct identity once the ground-state subspace
/// is projected out.
double? relaxationRate(SpectralBasis basis, double t) {
  if (basis.k == 0) return null;
  if (t < 0 || !t.isFinite) return null;
  // Raw range loop — avoids sync* generator overhead (Circle XXI).
  final start = basis.firstExcitedIndex;
  final k = basis.k;
  final eigs = basis.eigenvalues;
  var z = 0.0;
  var zw = 0.0;
  for (var j = start; j < k; j++) {
    final lam = eigs[j];
    final e = math.exp(-t * lam);
    z += e;
    zw += lam * e;
  }
  if (z <= 1e-300) return null;
  return zw / z;
}

/// Gap saturation ratio `γ(t) / λ₁` — how close the relaxation rate is
/// to its asymptotic floor. Values near 1 mean the trace has settled
/// into the slowest mode; values ≫ 1 mean many modes still contribute.
///
/// Returns `null` when [basis] has fewer than 2 eigenvalues (no gap
/// defined) or the relaxation rate is indeterminate.
double? gapSaturation(SpectralBasis basis, double t) {
  if (basis.k < 2 || basis.isGroundOnly) return null;
  // First non-zero eigenvalue = spectral gap. The ground-space
  // extension guarantees `firstExcitedIndex` points to it.
  final gap = basis.eigenvalues[basis.firstExcitedIndex];
  if (gap <= kGroundStateEps) return null;
  final gamma = relaxationRate(basis, t);
  if (gamma == null) return null;
  return gamma / gap;
}
