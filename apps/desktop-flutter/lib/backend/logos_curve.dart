// ObservableCurve — a thin, composable type for the engine's
// parameterised scalars.
//
// Most Logos observables are really functions of a control parameter,
// not scalars: `heatTrace(t)`, `zeta(s)`, `γ(t)`, `spectralDimension
// window(tMin, tMax)`, etc. Callers that want an "at-a-glance" number
// usually end up either picking an ad-hoc parameter value, or
// re-sampling the function themselves.
//
// This module gives that pattern a shared vocabulary: sample the
// function on a caller-chosen grid once, then ask for the useful
// derived quantities (slope at a point, integral, peak, half-life,
// log-log slope for power-law diagnostics). One call, one grid, many
// scalars.
//
// All operations are **Operational** — the curve's interpolation
// kernel is linear, its derivative is central-differenced, its
// integral is trapezoidal. These are the lowest-order choices; they
// compose correctly and keep the interface predictable. Higher-order
// schemes can drop in behind the same surface without breaking
// callers.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';
import 'logos_zeta.dart';

/// A sampled scalar function `f(x)` on a monotone-increasing grid.
///
/// Invariants (checked by [ObservableCurve.sampled] constructor):
///   * `xs.length == ys.length > 0`
///   * `xs` strictly monotonic in increasing order
///   * every value is finite
///
/// All queries use linear interpolation and central differences.
class ObservableCurve {
  final Float64List xs;
  final Float64List ys;
  final String xLabel;
  final String yLabel;

  ObservableCurve._(this.xs, this.ys, this.xLabel, this.yLabel);

  /// Build a curve from aligned samples. Validates monotonicity and
  /// finiteness up-front so every subsequent query stays cheap.
  factory ObservableCurve.sampled({
    required Float64List xs,
    required Float64List ys,
    String xLabel = 'x',
    String yLabel = 'y',
  }) {
    assert(xs.length == ys.length, 'xs/ys length mismatch');
    assert(xs.isNotEmpty, 'cannot build curve from empty samples');
    for (var i = 1; i < xs.length; i++) {
      assert(xs[i] > xs[i - 1],
          'xs must be strictly monotone increasing (idx $i)');
    }
    for (final v in ys) {
      assert(v.isFinite, 'y samples must be finite');
    }
    return ObservableCurve._(xs, ys, xLabel, yLabel);
  }

  /// Sample the curve at arbitrary `x` via linear interpolation.
  /// Clamps to the endpoints outside `[xs.first, xs.last]`.
  double valueAt(double x) {
    if (x <= xs.first) return ys.first;
    if (x >= xs.last) return ys.last;
    // Binary search for the enclosing bracket.
    var lo = 0;
    var hi = xs.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (xs[mid] <= x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final t = (x - xs[lo]) / (xs[hi] - xs[lo]);
    return ys[lo] + t * (ys[hi] - ys[lo]);
  }

  /// Central-difference slope at `x`. Falls back to forward/backward
  /// difference at the endpoints.
  double slopeAt(double x) {
    if (xs.length < 2) return 0.0;
    if (x <= xs.first) return (ys[1] - ys[0]) / (xs[1] - xs[0]);
    if (x >= xs.last) {
      final n = xs.length;
      return (ys[n - 1] - ys[n - 2]) / (xs[n - 1] - xs[n - 2]);
    }
    var lo = 0;
    var hi = xs.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (xs[mid] <= x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    // Central difference using the two enclosing intervals:
    //   left slope  = (ys[lo] − ys[lo−1]) / (xs[lo] − xs[lo−1])
    //   right slope = (ys[hi+1] − ys[hi]) / (xs[hi+1] − xs[hi])
    // When only one neighbour exists, fall back to that side.
    if (lo == 0) {
      return (ys[hi] - ys[lo]) / (xs[hi] - xs[lo]);
    }
    if (hi == xs.length - 1) {
      return (ys[hi] - ys[lo]) / (xs[hi] - xs[lo]);
    }
    final ls = (ys[lo] - ys[lo - 1]) / (xs[lo] - xs[lo - 1]);
    final rs = (ys[hi + 1] - ys[hi]) / (xs[hi + 1] - xs[hi]);
    return 0.5 * (ls + rs);
  }

  /// Trapezoidal integral `∫ f(x) dx` over the sampled range.
  double integral() {
    if (xs.length < 2) return 0.0;
    var s = 0.0;
    for (var i = 1; i < xs.length; i++) {
      s += 0.5 * (ys[i] + ys[i - 1]) * (xs[i] - xs[i - 1]);
    }
    return s;
  }

  /// `(xPeak, yPeak)` — sample with the maximum y value. Returns the
  /// first maximum on ties (leftmost).
  ({double x, double y}) peak() {
    var idx = 0;
    for (var i = 1; i < ys.length; i++) {
      if (ys[i] > ys[idx]) idx = i;
    }
    return (x: xs[idx], y: ys[idx]);
  }

  /// First `x > xs.first` at which `y` drops to half the peak value,
  /// or `null` when the curve never falls to half within the sampled
  /// range. Useful for measuring relaxation timescales.
  double? halfLife() {
    final p = peak();
    final target = p.y / 2.0;
    for (var i = 0; i < ys.length; i++) {
      if (xs[i] <= p.x) continue;
      if (ys[i] <= target) {
        if (i == 0) return xs[i];
        // Linear interpolate between samples i-1 and i.
        final dy = ys[i] - ys[i - 1];
        if (dy.abs() < 1e-300) return xs[i];
        final t = (target - ys[i - 1]) / dy;
        return xs[i - 1] + t * (xs[i] - xs[i - 1]);
      }
    }
    return null;
  }

  /// Log-log slope over the whole sampled range. Useful for power-
  /// law fitting (`y ~ x^α` → slope → α).
  ///
  /// Returns `null` when any x or y sample is ≤ 0 (log undefined) or
  /// when the fit is degenerate.
  double? logLogSlope() => logLogFit()?.slope;

  /// Full log-log linear fit — slope and coefficient of determination
  /// (R²) in one pass. Use this when callers need both numbers; it
  /// avoids the duplicated log-transformation that two separate calls
  /// would pay (Principia Circle XXI: loop fusion).
  ///
  /// Returns `null` on non-positive samples (log undefined) or
  /// degenerate fits.
  ({double slope, double rSquared})? logLogFit() {
    final n = xs.length;
    if (n < 2) return null;
    // Single pass: compute sums and sums-of-squares in log space.
    var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0;
    for (var i = 0; i < n; i++) {
      if (xs[i] <= 0 || ys[i] <= 0) return null;
      final lx = math.log(xs[i]);
      final ly = math.log(ys[i]);
      sx += lx;
      sy += ly;
    }
    final mx = sx / n;
    final my = sy / n;
    for (var i = 0; i < n; i++) {
      final dx = math.log(xs[i]) - mx;
      final dy = math.log(ys[i]) - my;
      sxx += dx * dx;
      syy += dy * dy;
      sxy += dx * dy;
    }
    if (sxx <= 1e-300) return null;
    final slope = sxy / sxx;
    final r2 = (syy > 1e-300) ? (sxy * sxy) / (sxx * syy) : 0.0;
    return (
      slope: slope,
      rSquared: r2.clamp(0.0, 1.0).toDouble(),
    );
  }
}

/// Log-space sampling helper — produces `n` points on `[a, b]`
/// spaced uniformly in log x. Returns an increasing Float64List.
Float64List logspace(double a, double b, int n) {
  assert(a > 0 && b > a && n >= 2);
  final out = Float64List(n);
  final la = math.log(a);
  final lb = math.log(b);
  for (var i = 0; i < n; i++) {
    out[i] = math.exp(la + (lb - la) * (i / (n - 1)));
  }
  return out;
}

/// Linear sampling helper.
Float64List linspace(double a, double b, int n) {
  assert(b > a && n >= 2);
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = a + (b - a) * (i / (n - 1));
  }
  return out;
}

/// Convenience: build the heat-trace curve `Z(t)` over a log grid.
/// The returned curve's `logLogSlope()` directly yields `−d_s/2`.
ObservableCurve heatTraceCurve(
  SpectralBasis basis, {
  double tMin = 0.1,
  double tMax = 3.0,
  int samples = 24,
}) {
  final ts = logspace(tMin, tMax, samples);
  final ys = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    ys[i] = basis.heatTrace(ts[i]);
  }
  return ObservableCurve.sampled(
    xs: ts,
    ys: ys,
    xLabel: 't',
    yLabel: 'Z(t)',
  );
}

/// Convenience: build the excited-heat-trace curve `Z_exc(t) = Z(t) −
/// kernelDim` over a log grid. This curve's `logLogSlope` is the
/// spectral-dimension exponent on the ORTHOGONAL COMPLEMENT of the
/// ground state — a cleaner read of the repo's excited geometry than
/// the full `heatTrace` when `kernelDim > 1`.
ObservableCurve excitedHeatTraceCurve(
  SpectralBasis basis, {
  double tMin = 0.1,
  double tMax = 3.0,
  int samples = 24,
}) {
  final ts = logspace(tMin, tMax, samples);
  final ys = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    ys[i] = basis.excitedHeatTrace(ts[i]);
  }
  return ObservableCurve.sampled(
    xs: ts,
    ys: ys,
    xLabel: 't',
    yLabel: 'Z_exc(t)',
  );
}

/// Convenience: build the zeta function curve `ζ(s)` over a linear
/// grid. `ζ(s)` is finite for s > abscissa-of-convergence on the
/// resolved basis (which, for a finite spectrum, is `−∞`).
ObservableCurve zetaCurve(
  SpectralBasis basis, {
  double sMin = 0.5,
  double sMax = 3.0,
  int samples = 24,
}) {
  final ss = linspace(sMin, sMax, samples);
  final ys = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    final v = zeta(basis, ss[i]);
    ys[i] = v.isFinite ? v : double.maxFinite;
  }
  return ObservableCurve.sampled(
    xs: ss,
    ys: ys,
    xLabel: 's',
    yLabel: 'ζ(s)',
  );
}
