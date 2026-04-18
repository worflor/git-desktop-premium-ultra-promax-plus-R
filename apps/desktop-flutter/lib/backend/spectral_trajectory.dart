// SPECTRAL TRAJECTORY — the repo as a path through shape-space.
//
// Every existing observable in this engine is STATIC: it reads the
// graph at HEAD and returns a scalar. But HEAD is a reduction, not
// the repo. The repo is the TRAJECTORY — an ordered sequence of
// [LogosState]s, one per commit (or per relevant revision), with the
// current state as the tip.
//
// Two ratchets frame this engine:
//
//   [LogosRatchet]       private forward-only evolution, old state
//                        explicitly forgotten, used for sync
//                        discipline.
//   [SpectralTrajectory] public forward-only shape evolution, old
//                        state preserved, used for visibility.
//
// Same primitive (monotonic state advance); opposite policy on "do
// we remember." A SpectralTrajectory is what LogosRatchet would be
// if it stopped throwing away history.
//
// Clay metaphor: the current pot remembers every pinch. Commits are
// operators that reshape the clay; the trajectory is the full record
// of every operator applied. Temporal observables (drift rate,
// regime changes, path length) are properties of the HAND that shaped
// the clay, not the pot at any instant.
//
// ── Design constraints ────────────────────────────────────────────
//
// * Immutable by construction. Append-only via [appended]; the list
//   is not rebuilt every call, but mutation of an existing trajectory
//   isn't exposed.
// * Agnostic about WHERE the points come from. A git-history walker
//   is a separate concern; this primitive only knows "here is an
//   ordered list of (revision, state) points."
// * Every observable degrades gracefully on short / heterogeneous
//   trajectories (different k across points, NaN inputs, single
//   point). No throw on "not enough data" — returns NaN or an empty
//   list so downstream UI doesn't have to guard.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';
import 'logos_hypercomplex.dart';
import 'logos_signature.dart';
import 'spectral_state.dart';

/// One anchored point on a [SpectralTrajectory]. Holds the engine's
/// structural snapshot ([state]) plus enough metadata to identify
/// the point in the host VCS (`commitSha`, `revision`, optional
/// `timestamp`).
///
/// Points compare equal iff their states compare equal (via
/// [LogosState.signature]); metadata is informational, not
/// load-bearing for identity.
class TrajectoryPoint {
  const TrajectoryPoint({
    required this.revision,
    required this.state,
    this.commitSha,
    this.timestamp,
  });

  /// Monotonic revision counter (e.g. git topological depth from
  /// genesis, or the [LogosRatchet] revision at the moment the
  /// snapshot was taken). Trajectories assume `revision` is strictly
  /// increasing along the point list.
  final int revision;

  /// Optional VCS-layer identifier for the commit that produced this
  /// state. Null for synthetic / test fixtures.
  final String? commitSha;

  /// Optional wall-clock of the commit (author or committer time).
  /// Lets callers plot temporal observables against calendar time
  /// instead of revision index. Null when not available.
  final DateTime? timestamp;

  /// The engine's spectral snapshot at this revision.
  final LogosState state;

  /// Convenience — the file-spectrum's [SpectralBasis.spectralRigidity]
  /// at this point, or `NaN` if the file spectrum is absent.
  double get rigidity => state.fileSpectrum?.spectralRigidity ?? double.nan;

  /// Convenience — the file-spectrum's [SpectralBasis.spectralGap]
  /// at this point, or `0.0` if the file spectrum is absent.
  double get spectralGap => state.fileSpectrum?.spectralGap ?? 0.0;

  /// Convenience — the file-spectrum's [SpectralBasis.vonNeumannEntropy]
  /// at this point, or `0.0` if the file spectrum is absent.
  double get vonNeumannEntropy =>
      state.fileSpectrum?.vonNeumannEntropy ?? 0.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrajectoryPoint && state == other.state);

  @override
  int get hashCode => state.hashCode;

  @override
  String toString() =>
      'TrajectoryPoint(rev=$revision, sig=0x${state.signature.toHex()}'
      '${commitSha == null ? '' : ', sha=${commitSha!.substring(0, commitSha!.length.clamp(0, 8))}'})';
}

/// The central primitive this file introduces — an ordered, immutable
/// sequence of [TrajectoryPoint]s representing a repository's evolution
/// through shape-space. The last point is the "current" shape; the
/// full path is the repo's history.
///
/// ## Observables
///
/// Static properties query the trajectory as a whole:
/// * [pathLength] — cumulative spectral distance traversed
/// * [trajectorySignature] — identity fingerprint of the whole path
///
/// Curve getters return one value per point or per transition:
/// * [rigidityCurve], [gapCurve], [vonNeumannCurve] — per-point scalars
/// * [eigenvalueStepDistances] — per-transition deformation magnitude
/// * [signatureStepDistances] — per-transition fingerprint distance
///
/// Temporal methods fit across multiple points:
/// * [regimeChanges] — indices where a scalar curve crosses a z-score
///   threshold (change-point detection)
/// * [forecastScalar] — linear-regression extrapolation of a curve
///
/// Mutation is append-only: [appended] returns a new trajectory with
/// one additional point. Existing instances are never mutated.
///
/// ## Relationship to LogosRatchet
///
/// A trajectory is the *history* that a [LogosRatchet] deliberately
/// forgets. When a ratchet advances through N events, it keeps only
/// the final state; if you want to see the arc, snapshot states
/// at each advance and feed them into a trajectory. The two primitives
/// are duals — forward-secret sync vs. forward-visible chronicle.
class SpectralTrajectory {
  SpectralTrajectory({required List<TrajectoryPoint> points})
      : points = List.unmodifiable(points),
        assert(
          _isMonotoneRevisions(points),
          'points must have strictly increasing revisions',
        );

  /// Empty trajectory — zero points. Useful as the initial value before
  /// the first snapshot has been taken, and as the neutral element for
  /// [appended].
  factory SpectralTrajectory.empty() =>
      SpectralTrajectory(points: const <TrajectoryPoint>[]);

  /// Ordered list of points from earliest (index 0) to most recent
  /// (index `points.length - 1`). Unmodifiable; to extend, use
  /// [appended].
  final List<TrajectoryPoint> points;

  /// Number of points in this trajectory.
  int get length => points.length;

  /// True iff the trajectory holds zero points.
  bool get isEmpty => points.isEmpty;

  /// The most-recent point, a.k.a. the current shape of the repo.
  /// Returns null on an empty trajectory.
  TrajectoryPoint? get head => points.isEmpty ? null : points.last;

  /// The earliest point — genesis of the observable history.
  TrajectoryPoint? get genesis => points.isEmpty ? null : points.first;

  /// Produce a new trajectory with [point] appended as the new tip.
  /// The returned instance shares no mutable state with `this`.
  SpectralTrajectory appended(TrajectoryPoint point) {
    return SpectralTrajectory(points: [...points, point]);
  }

  /// Time-reversed trajectory — the mirror image in the temporal
  /// axis. Points are enumerated in reverse order; revisions are
  /// re-stamped monotonically so the result satisfies the
  /// strictly-increasing-revision invariant.
  ///
  /// ## Symmetry theorems (verified in tests)
  ///
  /// * [pathLength] is reversal-invariant: `reversed().pathLength ==
  ///   pathLength` (sum of edge distances is orientation-free).
  /// * [dirichletAction] is reversal-invariant: same sum of
  ///   squared tangents.
  /// * [turbulence] is reversal-invariant: angle between consecutive
  ///   tangents is symmetric under pair-swap.
  /// * `reversed().tangentAt(i) == −tangentAt(N − 2 − i)` (direction
  ///   flip but magnitude preserved).
  /// * `reversed().trajectorySignature` differs from `trajectorySignature`
  ///   except on palindromic trajectories — the signature is order-
  ///   sensitive, so reversal is a genuine transformation.
  ///
  /// ## Duality interpretation
  ///
  /// Reversal is the trajectory's version of time-reversal in
  /// physics: scalar observables (energy, action) are T-invariant;
  /// vector observables (tangent, momentum) flip sign. Matches the
  /// physics-on-graphs framing where the heat kernel is non-
  /// time-reversible (forgetful) but the unitary Schrödinger evolution
  /// IS — `unitaryDiffuse(−t)` is the conjugate of `unitaryDiffuse(t)`.
  SpectralTrajectory reversed() {
    if (points.isEmpty) return SpectralTrajectory.empty();
    final reversedPoints = <TrajectoryPoint>[];
    for (var i = points.length - 1; i >= 0; i--) {
      final orig = points[i];
      reversedPoints.add(TrajectoryPoint(
        revision: points.length - 1 - i + 1, // monotone re-stamping
        state: orig.state,
        commitSha: orig.commitSha,
        timestamp: orig.timestamp,
      ));
    }
    return SpectralTrajectory(points: reversedPoints);
  }

  /// Slice the trajectory to the contiguous index range `[start, end)`.
  /// Clamped to valid bounds. Returns a new trajectory.
  SpectralTrajectory slice(int start, int end) {
    final lo = start.clamp(0, points.length);
    final hi = end.clamp(lo, points.length);
    return SpectralTrajectory(points: points.sublist(lo, hi));
  }

  // ── Per-point scalar curves ───────────────────────────────────────

  /// `[p.rigidity for p in points]` — the spectral-rigidity curve.
  /// Points whose file spectrum is null contribute `NaN`.
  List<double> rigidityCurve() =>
      [for (final p in points) p.rigidity];

  /// `[p.spectralGap for p in points]` — the λ₁ curve. Disconnected or
  /// missing spectra contribute `0.0`.
  List<double> gapCurve() =>
      [for (final p in points) p.spectralGap];

  /// `[p.vonNeumannEntropy for p in points]` — the spectral-diversity
  /// curve. Missing spectra contribute `0.0`.
  List<double> vonNeumannCurve() =>
      [for (final p in points) p.vonNeumannEntropy];

  // ── Per-transition curves (length = points.length − 1) ────────────

  /// `eigenvalueStepDistances[i]` = [SpectralBasis.eigenvalueDistance]
  /// between `points[i]` and `points[i+1]`, truncated to the smaller k
  /// when the two bases disagree on dimension.
  ///
  /// Returns an empty list for trajectories shorter than two points.
  /// Gaps where either side's file spectrum is null contribute `NaN`.
  List<double> eigenvalueStepDistances() {
    if (points.length < 2) return const <double>[];
    final out = List<double>.filled(points.length - 1, double.nan);
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i].state.fileSpectrum;
      final b = points[i + 1].state.fileSpectrum;
      if (a == null || b == null) continue;
      out[i] = _truncatedEigenvalueDistance(a, b);
    }
    return out;
  }

  /// `signatureStepDistances[i]` = Hamming-like distance between the
  /// two states' signatures at step `i`. Uses a byte-level popcount
  /// on the XOR of the two 62-bit signatures, returning an integer in
  /// `[0, 62]`.
  ///
  /// Empty when length < 2. NaN never occurs here — signatures are
  /// always defined on a LogosState, even an empty one.
  List<int> signatureStepDistances() {
    if (points.length < 2) return const <int>[];
    return [
      for (var i = 0; i < points.length - 1; i++)
        _signatureHammingDistance(
          points[i].state.signature,
          points[i + 1].state.signature,
        ),
    ];
  }

  // ── Whole-path observables ────────────────────────────────────────

  /// Total spectral path length — `Σᵢ eigenvalueStepDistance(i)`. A
  /// large value means the repo's spectrum has moved a lot through
  /// shape-space over its history. Small = nearly isospectral
  /// trajectory (cosmetic changes only).
  ///
  /// NaN contributions are skipped so the sum is always finite.
  double get pathLength {
    var s = 0.0;
    for (final d in eigenvalueStepDistances()) {
      if (d.isFinite) s += d;
    }
    return s;
  }

  /// Moving-window path speed — sum of step distances over the last
  /// `window` steps, divided by `window`. Returns `NaN` when the
  /// trajectory has fewer than `window + 1` points.
  ///
  /// Units: spectral-distance per step. Large values after a refactor
  /// commit, small during stable maintenance windows.
  double pathSpeed({int window = 10}) {
    if (window < 1) return double.nan;
    final steps = eigenvalueStepDistances();
    if (steps.length < window) return double.nan;
    var s = 0.0;
    var count = 0;
    for (var i = steps.length - window; i < steps.length; i++) {
      if (steps[i].isFinite) {
        s += steps[i];
        count += 1;
      }
    }
    return count == 0 ? double.nan : s / count;
  }

  /// Content fingerprint of the trajectory. Derived from the ordered
  /// sequence of per-point state signatures via the shared
  /// [fingerprintFloat64] primitive — so two trajectories compare
  /// equal iff they pass through the same states in the same order.
  ///
  /// This is the "hand that shaped the clay" fingerprint: two repos
  /// can arrive at the same current HEAD via different histories; this
  /// signature distinguishes them.
  Signature get trajectorySignature {
    if (points.isEmpty) return Signature.zero;
    // Pack sig.lo + sig.hi as a Float64 pair per point via a
    // deterministic encoding, then fingerprintFloat64 over the packed
    // block. This reuses the engine's canonical hash primitive; no
    // parallel hashing logic.
    final buf = Float64List(points.length * 2);
    for (var i = 0; i < points.length; i++) {
      final sig = points[i].state.signature;
      // Interpret each 31-bit half as a double. Mantissa has 53 bits
      // of precision so 31 bits fit exactly; loss-free round-trip.
      buf[i * 2] = sig.lo.toDouble();
      buf[i * 2 + 1] = sig.hi.toDouble();
    }
    return fingerprintFloat64(buf);
  }

  // ── Regime-change detection ───────────────────────────────────────

  /// Detect **regime changes** in an arbitrary scalar curve using a
  /// rolling-window z-score on the first difference. An index `i`
  /// appears in the output iff the step `curve[i+1] − curve[i]` is
  /// more than `sensitivity` standard deviations outside the rolling
  /// mean of recent steps.
  ///
  /// * [curve] — the scalar timeline to analyse (e.g. [rigidityCurve]).
  /// * [window] — number of recent steps to use for the rolling
  ///   baseline. Default 8.
  /// * [sensitivity] — z-score threshold. 2.0 is "notable", 3.0 is
  ///   "sharp".
  ///
  /// Returns a list of `(index, zScore)` pairs, sorted by index.
  /// Indices point to the step's right-hand endpoint — i.e. a change
  /// at index `i` means "the jump going into point `i` was anomalous."
  ///
  /// Empty output when the curve has fewer than `window + 2` values or
  /// when all steps are identical.
  List<({int index, double zScore})> regimeChanges({
    required List<double> curve,
    int window = 8,
    double sensitivity = 2.0,
  }) {
    if (curve.length < window + 2) return const [];
    final diffs = Float64List(curve.length - 1);
    for (var i = 0; i < diffs.length; i++) {
      diffs[i] = curve[i + 1] - curve[i];
      if (!diffs[i].isFinite) diffs[i] = 0.0;
    }
    final out = <({int index, double zScore})>[];
    for (var i = window; i < diffs.length; i++) {
      var mean = 0.0;
      for (var k = i - window; k < i; k++) {
        mean += diffs[k];
      }
      mean /= window;
      var variance = 0.0;
      for (var k = i - window; k < i; k++) {
        final d = diffs[k] - mean;
        variance += d * d;
      }
      variance /= window;
      final std = math.sqrt(variance);
      if (std <= 1e-12) continue; // flat baseline, can't score
      final z = (diffs[i] - mean) / std;
      if (z.abs() >= sensitivity) {
        out.add((index: i + 1, zScore: z));
      }
    }
    return out;
  }

  // ── Tangent vectors and curvature (differential geometry of the path) ─

  /// Tangent vector at step `i` — the per-mode spectral velocity going
  /// from `points[i]` to `points[i + 1]`:
  ///
  ///     tangent_i[j] = λ_j^(i+1) − λ_j^(i)
  ///
  /// Truncated to the smaller k when the two bases disagree on
  /// dimension. Returns an empty `Float64List` when either side's
  /// file spectrum is null or `i` is out of range.
  ///
  /// **Reading**: the direction the spectrum is moving at this step,
  /// mode by mode. A positive value in component j means "mode j's
  /// eigenvalue grew" — structurally, that mode became *stiffer* (less
  /// diffusive). Negative = mode loosened (more diffusive).
  ///
  /// The sum of absolute values across modes is the step's contribution
  /// to [pathLength].
  Float64List tangentAt(int i) {
    if (i < 0 || i >= points.length - 1) return Float64List(0);
    final a = points[i].state.fileSpectrum;
    final b = points[i + 1].state.fileSpectrum;
    if (a == null || b == null) return Float64List(0);
    final k = a.k < b.k ? a.k : b.k;
    final out = Float64List(k);
    for (var j = 0; j < k; j++) {
      out[j] = b.eigenvalues[j] - a.eigenvalues[j];
    }
    return out;
  }

  /// Scalar curvature at step `i` — how abruptly the trajectory
  /// changes DIRECTION between the tangent at `i − 1` and the tangent
  /// at `i`. Computed as the angle (in radians) between consecutive
  /// tangent vectors, in the range `[0, π]`.
  ///
  /// * 0 = trajectory is straight at this step (consecutive tangents
  ///   point the same way — the repo is trending consistently).
  /// * π/2 = orthogonal turn (the trend rotated 90° in mode-space).
  /// * π = full reversal (the trend flipped direction).
  ///
  /// Requires at least two consecutive tangents — the first interior
  /// index is `i = 1`. Returns NaN when either tangent has zero norm
  /// (degenerate) or when `i` is out of range.
  double curvatureAt(int i) {
    if (i < 1 || i >= points.length - 1) return double.nan;
    final tPrev = tangentAt(i - 1);
    final tCurr = tangentAt(i);
    if (tPrev.isEmpty || tCurr.isEmpty) return double.nan;
    final k = tPrev.length < tCurr.length ? tPrev.length : tCurr.length;
    var dot = 0.0;
    var nP = 0.0;
    var nC = 0.0;
    for (var j = 0; j < k; j++) {
      dot += tPrev[j] * tCurr[j];
      nP += tPrev[j] * tPrev[j];
      nC += tCurr[j] * tCurr[j];
    }
    if (nP <= 1e-300 || nC <= 1e-300) return double.nan;
    final cosTheta = (dot / (math.sqrt(nP) * math.sqrt(nC))).clamp(-1.0, 1.0);
    return math.acos(cosTheta);
  }

  /// Architectural turbulence — the mean interior curvature over the
  /// whole trajectory. A scalar in `[0, π]`.
  ///
  /// Interpretation:
  /// * Near 0 — the repo has been trending consistently in the same
  ///   spectral direction. Whatever it's becoming, it's becoming it
  ///   smoothly.
  /// * Near π/2 — each commit bends the trajectory 90° from the last.
  ///   Chaotic / thrashing: refactors undoing each other, merges
  ///   fighting each other, decisions reversing.
  /// * Near π — pure oscillation: the repo keeps reversing direction.
  ///
  /// Returns NaN when the trajectory is too short (< 3 points) for
  /// any interior curvature to be defined.
  ///
  /// This is the "hand quality" observable: two repos can have the
  /// same [pathLength] (equal total motion) but radically different
  /// turbulence — one team shapes the clay with steady deliberate
  /// strokes, the other with frantic reversals.
  double get turbulence {
    if (points.length < 3) return double.nan;
    var s = 0.0;
    var count = 0;
    for (var i = 1; i < points.length - 1; i++) {
      final c = curvatureAt(i);
      if (c.isFinite) {
        s += c;
        count += 1;
      }
    }
    return count == 0 ? double.nan : s / count;
  }

  /// Full curvature curve — one value per interior index, suitable
  /// for plotting against the trajectory timeline. Length is
  /// `points.length − 2` (or empty for short trajectories). NaN
  /// entries indicate steps where curvature couldn't be computed.
  List<double> curvatureCurve() {
    if (points.length < 3) return const <double>[];
    return [for (var i = 1; i < points.length - 1; i++) curvatureAt(i)];
  }

  // ── Per-node Poincaré animation trace ─────────────────────────────

  /// `poincareTraceOfNode(nodeId)` returns the `(x, y, revision)` of
  /// node `nodeId` across every point of the trajectory, suitable for
  /// animating a single file's migration through the hyperbolic
  /// embedding over commits.
  ///
  /// Points whose file spectrum is null, whose `nodeId` is out of
  /// range, or whose basis has k < 2 contribute a row with
  /// `(NaN, NaN, revision)` — callers can skip/interpolate as needed.
  ///
  /// This is the trajectory's cinematic primitive: a repo's rigidity
  /// curve is a plottable line, but a per-node Poincaré trace lets a
  /// UI show WHERE each file drifted as the architecture evolved —
  /// clustering tightening, one file migrating from community A to
  /// community B, etc.
  List<({double x, double y, int revision})> poincareTraceOfNode(
    int nodeId, {
    int magnitudeDims = 6,
    double targetRadius = 0.92,
  }) {
    final out = <({double x, double y, int revision})>[];
    for (final p in points) {
      final basis = p.state.fileSpectrum;
      if (basis == null || nodeId < 0 || nodeId >= basis.n || basis.k < 2) {
        out.add((x: double.nan, y: double.nan, revision: p.revision));
        continue;
      }
      final c = basis.poincareCoordinates(
        nodeId,
        magnitudeDims: magnitudeDims,
        targetRadius: targetRadius,
      );
      out.add((x: c.x, y: c.y, revision: p.revision));
    }
    return out;
  }

  // ── Trajectory-to-trajectory distance ─────────────────────────────

  /// Element-wise spectral distance between this trajectory and
  /// [other], returning the mean eigenvalue distance at matched
  /// revision indices. Only the overlap `[0, min(length, other.length))`
  /// is considered — trailing points of the longer trajectory are
  /// ignored.
  ///
  /// Use case: fork comparison. Two trajectories starting from a
  /// common genesis diverge as their histories accumulate different
  /// commits; this gives a continuous "how far have the forks drifted"
  /// scalar.
  ///
  /// Returns 0.0 iff the two trajectories are pointwise-isospectral
  /// over their overlap. Returns `double.nan` when either trajectory
  /// is empty.
  double distanceTo(SpectralTrajectory other) {
    final n = math.min(points.length, other.points.length);
    if (n == 0) return double.nan;
    var s = 0.0;
    var count = 0;
    for (var i = 0; i < n; i++) {
      final a = points[i].state.fileSpectrum;
      final b = other.points[i].state.fileSpectrum;
      if (a == null || b == null) continue;
      s += _truncatedEigenvalueDistance(a, b);
      count += 1;
    }
    if (count == 0) return double.nan;
    return s / count;
  }

  // ── Forecasting ───────────────────────────────────────────────────

  /// Linear-regression forecast of a scalar curve `steps` revisions
  /// into the future. Fits `y = a + b·x` over the last [fitWindow]
  /// finite values and evaluates at `x = curve.length − 1 + steps`.
  ///
  /// Returns NaN when fewer than 3 finite samples are available in
  /// the fit window — below that, regression coefficients aren't
  /// meaningful.
  ///
  /// Intended for observables the engine understands — rigidity, gap,
  /// von-Neumann entropy. The caller picks which curve to forecast.
  static double forecastScalar(
    List<double> curve, {
    int fitWindow = 12,
    int steps = 1,
  }) {
    final xs = <double>[];
    final ys = <double>[];
    final start = math.max(0, curve.length - fitWindow);
    for (var i = start; i < curve.length; i++) {
      final y = curve[i];
      if (y.isFinite) {
        xs.add(i.toDouble());
        ys.add(y);
      }
    }
    if (xs.length < 3) return double.nan;
    final n = xs.length;
    var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
    for (var i = 0; i < n; i++) {
      sumX += xs[i];
      sumY += ys[i];
      sumXY += xs[i] * ys[i];
      sumX2 += xs[i] * xs[i];
    }
    final denom = n * sumX2 - sumX * sumX;
    if (denom.abs() < 1e-12) return double.nan;
    final b = (n * sumXY - sumX * sumY) / denom;
    final a = (sumY - b * sumX) / n;
    final xTarget = (curve.length - 1 + steps).toDouble();
    return a + b * xTarget;
  }

  // ── Quantum-flavour observables on scalar curves ──────────────────

  /// Weighted mean and variance of a curve treated as a probability
  /// density over its index axis. Returned in record `{mean, variance}`.
  ///
  /// Forms one half of the [heisenbergUncertainty] pair — the
  /// "position" moment in time-domain. Mass = `|x[k]|²`; zero-mass
  /// curves return `(NaN, NaN)`.
  static ({double mean, double variance}) curveTemporalMoments(
      List<double> curve) {
    var mass = 0.0;
    var firstMoment = 0.0;
    for (var k = 0; k < curve.length; k++) {
      if (!curve[k].isFinite) continue;
      final m = curve[k] * curve[k];
      mass += m;
      firstMoment += k * m;
    }
    if (mass <= 1e-300) {
      return (mean: double.nan, variance: double.nan);
    }
    final mean = firstMoment / mass;
    var secondMoment = 0.0;
    for (var k = 0; k < curve.length; k++) {
      if (!curve[k].isFinite) continue;
      final d = k - mean;
      secondMoment += d * d * curve[k] * curve[k];
    }
    return (mean: mean, variance: secondMoment / mass);
  }

  /// Weighted mean and variance of the DFT magnitude spectrum,
  /// treated as a probability density over frequency bins. Forms
  /// the "momentum" moment dual to [curveTemporalMoments].
  ///
  /// Measured as bin index, so values are in `[0, N/2]` (the useful
  /// range below Nyquist).
  static ({double mean, double variance}) curveSpectralMoments(
      List<double> curve) {
    final mag = SpectralTrajectory.magnitudeSpectrum(curve);
    final n = mag.length;
    if (n == 0) return (mean: double.nan, variance: double.nan);
    // Focus on [0, N/2] — the non-aliased half — to get a cleaner
    // frequency interpretation.
    final limit = n ~/ 2 + 1;
    var mass = 0.0;
    var firstMoment = 0.0;
    for (var k = 0; k < limit; k++) {
      final m = mag[k] * mag[k];
      mass += m;
      firstMoment += k * m;
    }
    if (mass <= 1e-300) {
      return (mean: double.nan, variance: double.nan);
    }
    final mean = firstMoment / mass;
    var secondMoment = 0.0;
    for (var k = 0; k < limit; k++) {
      final d = k - mean;
      secondMoment += d * d * mag[k] * mag[k];
    }
    return (mean: mean, variance: secondMoment / mass);
  }

  /// The **Heisenberg time-frequency uncertainty product** of a
  /// scalar curve — `Δk · Δω`, where Δk is the standard deviation of
  /// the index distribution weighted by `|x[k]|²` and Δω is the
  /// standard deviation of the (non-aliased) magnitude spectrum
  /// weighted by `|X̂[ω]|²`.
  ///
  /// ## Theorem (discrete analogue of Heisenberg)
  ///
  /// For any real-valued curve x with finite energy:
  ///
  ///     Δk · Δω ≥ N / (4π)     (asymptotic bound)
  ///
  /// A Gaussian bump saturates this up to discrete-lattice corrections;
  /// sharper-than-Gaussian bumps (Dirac deltas, steps) overshoot on
  /// one side but the product bound still holds.
  ///
  /// ## Why this is classically quantum
  ///
  /// The DFT is a unitary map; inner products are preserved on both
  /// sides. "Position" variance in time-domain and "momentum"
  /// variance in frequency-domain are canonically conjugate. Their
  /// product can't go below the lattice-discrete minimum. Same math,
  /// different name, every time.
  ///
  /// Returns `NaN` if the curve has zero energy or is too short.
  static double heisenbergUncertainty(List<double> curve) {
    final t = curveTemporalMoments(curve);
    final f = curveSpectralMoments(curve);
    if (!t.variance.isFinite || !f.variance.isFinite) return double.nan;
    return math.sqrt(t.variance * f.variance);
  }

  // ── Discrete calculus on scalar curves ────────────────────────────
  //
  // Three operations that together form a honest discrete calculus
  // on any trajectory-derived scalar curve (rigidity, gap, path
  // speed, HKS-at-a-node, …):
  //
  //   D[x][i] = x[i+1] − x[i]                      (first derivative)
  //   D²[x][i] = x[i+1] − 2·x[i] + x[i−1]          (second derivative)
  //   I[x][a,b] = Σ_{k=a}^{b−1} x[k]               (indefinite integral)
  //
  // The discrete Fundamental Theorem of Calculus holds exactly:
  //
  //     I[D[x]][0, N] = x[N] − x[0]
  //
  // — verified in `spectral_trajectory_test.dart`. This turns every
  // observable into a first-class calculus object: derivatives tell
  // us rates, integrals tell us totals, and the action functional
  // below turns trajectories into variational objects.

  /// Forward finite difference `x[i+1] − x[i]`, one entry shorter
  /// than [curve]. NaN entries propagate as NaN.
  static List<double> derivativeOfCurve(List<double> curve) {
    if (curve.length < 2) return const <double>[];
    return [
      for (var i = 0; i < curve.length - 1; i++) curve[i + 1] - curve[i]
    ];
  }

  /// Second forward difference `x[i+1] − 2·x[i] + x[i−1]`. Length is
  /// `curve.length − 2`; indexed from 1 in the original curve's
  /// frame, so `result[i]` corresponds to `curve[i + 1]`.
  static List<double> secondDerivativeOfCurve(List<double> curve) {
    if (curve.length < 3) return const <double>[];
    return [
      for (var i = 1; i < curve.length - 1; i++)
        curve[i + 1] - 2 * curve[i] + curve[i - 1]
    ];
  }

  /// Riemann-like sum `Σ_{k=a}^{b-1} curve[k]`. Defaults span the
  /// whole curve. Raises on out-of-range bounds.
  static double integralOfCurve(List<double> curve, {int? from, int? to}) {
    final start = from ?? 0;
    final end = to ?? curve.length;
    if (start < 0 || end > curve.length || start > end) {
      throw RangeError(
          'integralOfCurve: invalid range [$start, $end) for length '
          '${curve.length}');
    }
    var s = 0.0;
    for (var k = start; k < end; k++) {
      if (curve[k].isFinite) s += curve[k];
    }
    return s;
  }

  /// **Dirichlet-energy action** of the trajectory — a scalar measure
  /// of how much structural work the repo has accumulated.
  ///
  ///     S[γ] = (1/2) · Σ_k ‖γ̇_k‖²
  ///
  /// where `γ̇_k = tangentAt(k)` is the per-step spectral velocity
  /// vector. Two trajectories with the same endpoints can have
  /// different actions; the trajectory that minimises S (given its
  /// endpoints) is the shortest-path geodesic in spectral space.
  ///
  /// Euler-Lagrange on this action yields `γ̈ = 0` — i.e., consecutive
  /// tangents parallel, i.e., `curvatureAt(k) = 0`, i.e., zero
  /// [turbulence]. So:
  ///
  ///     argmin S[γ] = { γ : turbulence(γ) = 0 }
  ///
  /// **a repo with zero turbulence is acting under the principle of
  /// least action** — its development has been, variationally, the
  /// smoothest path through shape-space.
  ///
  /// NaN/empty inputs collapse cleanly to 0.0.
  double get dirichletAction {
    if (points.length < 2) return 0.0;
    var s = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final tangent = tangentAt(i);
      for (final v in tangent) {
        if (v.isFinite) s += v * v;
      }
    }
    return 0.5 * s;
  }

  // ── The ω-axis: temporal DFT of scalar curves ──────────────────────
  //
  // Companion to the Logos Transform
  //
  //     Ŝ(j, ω) = (1/√(nN)) · Σ_{v,k} u_j(v) · S(v, k) · e^{-2πi·ω·k/N}
  //
  // whose spatial half (`j`) already lives on [SpectralBasis]. This
  // block provides the temporal half (`ω`): given any scalar curve
  // the trajectory exposes (rigidity, gap, turbulence, HKS at a
  // fixed node, per-mode coefficient time-series, ...) compute its
  // DFT over the commit axis and surface the dominant period.
  //
  // Use case: "does this repo breathe?" A weekly release rhythm
  // shows up as a spike at ω ≈ N/7 in the rigidity spectrum. A
  // gradually-ossifying codebase has an ω=0 bias with no higher
  // peaks. A codebase oscillating between refactor and
  // re-introduction of tech debt produces a low-ω harmonic.

  /// Discrete Fourier transform of a scalar curve. Returns
  /// `(real, imaginary)` Float64Lists, each of length `curve.length`.
  ///
  /// Unitary normalisation:
  ///
  ///     X[k] = (1/√N) · Σⱼ x[j] · e^{-2πi·k·j/N}
  ///
  /// so Parseval's identity `‖x‖² = ‖X‖²` holds verbatim. Non-finite
  /// inputs are treated as zero so the transform is safe over curves
  /// with sparse NaN entries (common when the trajectory has some
  /// points with missing file spectra).
  ///
  /// Cost: `O(N²)`. Fine for trajectories with N up to a few thousand
  /// commits. Callers wanting FFT speeds on ultra-long histories can
  /// plug in an external FFT routine — the interface is stable.
  ///
  /// Thin wrapper over [realDftForward] in `logos_hypercomplex.dart`
  /// — the shared DFT used by the 2-axis Logos Transform. Keeping
  /// a trajectory-scoped entry point makes call sites read well;
  /// the math is done in one place.
  static ({Float64List real, Float64List imaginary}) dftOfCurve(
    List<double> curve,
  ) =>
      realDftForward(curve);

  /// Inverse DFT — the symmetric companion to [dftOfCurve]. Given a
  /// real + imaginary pair in the frequency domain, reconstructs
  /// the time-domain real-valued curve. Satisfies
  /// `inverseDftOfCurve(dftOfCurve(x).real, dftOfCurve(x).imaginary)` ≈ x
  /// to f64 precision.
  ///
  /// The unitary normalisation `X[k] = (1/√N)·Σⱼ x[j]e^{-2πi·k·j/N}`
  /// makes forward and inverse symmetric: both multiply by `1/√N`.
  /// Parseval holds by construction.
  static Float64List inverseDftOfCurve({
    required Float64List real,
    required Float64List imaginary,
  }) =>
      realDftInverse(real: real, imaginary: imaginary);

  /// Magnitude spectrum `|X[k]| = √(X_re² + X_im²)` at each frequency
  /// bin. Same length as the input.
  static Float64List magnitudeSpectrum(List<double> curve) {
    final dft = dftOfCurve(curve);
    final out = Float64List(dft.real.length);
    for (var k = 0; k < out.length; k++) {
      final re = dft.real[k];
      final im = dft.imaginary[k];
      out[k] = math.sqrt(re * re + im * im);
    }
    return out;
  }

  /// **Dream a scalar curve forward in time** — DFT-based harmonic
  /// extrapolation, the "reverse compression" operation.
  ///
  /// Takes a scalar observation curve of length `N`, forwards it
  /// through [realDftForward], keeps only the top-[keepOmegaBins]
  /// frequency components by magnitude (plus DC), and phase-continues
  /// those harmonics for [stepsAhead] additional steps. Returns a
  /// length-`(N + stepsAhead)` curve whose first `N` entries closely
  /// approximate the input and whose last [stepsAhead] entries are
  /// the **harmonic prediction**.
  ///
  /// This is the engine's natural "dream" primitive — compression
  /// (DFT truncation) followed by continuation (evaluate the kept
  /// harmonics at future time indices). A sinusoid is continued
  /// phase-coherently; a linear trend keeps trending; random noise
  /// reproduces only its training region.
  ///
  /// The DC component (ω=0, the mean) is always retained so constant
  /// offsets carry through. Setting [keepOmegaBins] = 0 keeps only
  /// DC — the prediction is a flat mean.
  ///
  /// Cost: O(N² + N·(N + stepsAhead)·K) where K = keepOmegaBins.
  /// Fine for up to a few thousand commits.
  static List<double> dreamCurveForward({
    required List<double> curve,
    required int stepsAhead,
    int keepOmegaBins = 4,
  }) {
    final n = curve.length;
    if (n == 0 || stepsAhead < 0) return const <double>[];
    if (stepsAhead == 0) {
      return [for (final v in curve) v.isFinite ? v : 0.0];
    }
    final dft = realDftForward(curve);
    // Rank non-DC bins by magnitude; keep top-K.
    final magIdx = <({int bin, double mag})>[];
    for (var k = 1; k < n; k++) {
      final m = math.sqrt(dft.real[k] * dft.real[k] +
          dft.imaginary[k] * dft.imaginary[k]);
      magIdx.add((bin: k, mag: m));
    }
    magIdx.sort((a, b) => b.mag.compareTo(a.mag));
    final keep = <int>{0}; // always retain DC
    for (var i = 0; i < keepOmegaBins && i < magIdx.length; i++) {
      keep.add(magIdx[i].bin);
    }

    // Inverse-evaluate the kept harmonics at t = 0 .. N + stepsAhead − 1.
    final extendedN = n + stepsAhead;
    final out = List<double>.filled(extendedN, 0.0);
    final invSqrtN = 1.0 / math.sqrt(n);
    for (var t = 0; t < extendedN; t++) {
      var sum = 0.0;
      for (final k in keep) {
        final phase = 2.0 * math.pi * k * t / n;
        sum += dft.real[k] * math.cos(phase) -
            dft.imaginary[k] * math.sin(phase);
      }
      out[t] = sum * invSqrtN;
    }
    return out;
  }

  /// **Stochastic** forward forecast — the generative sibling of
  /// [dreamCurveForward]. Same deterministic top-K spine; the *dropped*
  /// harmonics are replaced by fresh noise whose per-bin variance
  /// matches the empirical residual spectrum.
  ///
  /// Reading: `dreamCurveForward` returns the *mean* forecast. This
  /// method returns a **sample** from the full posterior path
  /// distribution — one of many plausible futures consistent with the
  /// past. Run it many times to build an uncertainty envelope.
  ///
  /// Derivation (see `docs/architecture/spectral-generative.md`):
  ///
  /// 1. DFT the input curve to get complex coefficients `X[k]`.
  /// 2. Rank bins by magnitude; keep top-K plus DC (deterministic spine).
  /// 3. Compute the empirical noise variance per dropped bin:
  ///      `v_k = |X[k]|² / n` (Parseval normaliser).
  /// 4. At every dropped bin, sample a fresh complex Gaussian with
  ///    that variance — respects conjugate symmetry so the output is
  ///    real.
  /// 5. Inverse-evaluate the combined (deterministic + stochastic)
  ///    spectrum at `t = 0 .. n + stepsAhead − 1`.
  ///
  /// `noiseScale` = 1.0 uses the empirical residual variance verbatim.
  /// `noiseScale` = 0.0 recovers [dreamCurveForward] deterministically.
  /// Values in between interpolate between deterministic forecast and
  /// full-residual sampling.
  static List<double> sampleDreamCurveForward({
    required List<double> curve,
    required int stepsAhead,
    required math.Random rng,
    int keepOmegaBins = 4,
    double noiseScale = 1.0,
  }) {
    final n = curve.length;
    if (n == 0 || stepsAhead < 0) return const <double>[];
    if (stepsAhead == 0) {
      return [for (final v in curve) v.isFinite ? v : 0.0];
    }
    final dft = realDftForward(curve);
    final magIdx = <({int bin, double mag})>[];
    for (var k = 1; k < n; k++) {
      final m = math.sqrt(dft.real[k] * dft.real[k] +
          dft.imaginary[k] * dft.imaginary[k]);
      magIdx.add((bin: k, mag: m));
    }
    magIdx.sort((a, b) => b.mag.compareTo(a.mag));
    final keep = <int>{0};
    for (var i = 0; i < keepOmegaBins && i < magIdx.length; i++) {
      keep.add(magIdx[i].bin);
    }

    // Build the stochastic spectrum: keep retained bins, replace
    // dropped bins by a fresh complex Gaussian with variance that
    // matches the empirical magnitude.
    final stochRe = Float64List(n);
    final stochIm = Float64List(n);
    double g() {
      final u1 = rng.nextDouble();
      final u2 = rng.nextDouble();
      return math.sqrt(-2.0 * math.log(u1.clamp(1e-300, 1.0))) *
          math.cos(2.0 * math.pi * u2);
    }

    for (var k = 0; k < n; k++) {
      if (keep.contains(k)) {
        stochRe[k] = dft.real[k];
        stochIm[k] = dft.imaginary[k];
        continue;
      }
      if (noiseScale <= 0) continue;
      // Match empirical magnitude at bin k; draw phase uniformly.
      final empMag = math.sqrt(dft.real[k] * dft.real[k] +
          dft.imaginary[k] * dft.imaginary[k]);
      final scale = empMag * noiseScale / math.sqrt(2.0);
      final re = g() * scale;
      final im = g() * scale;
      // Respect conjugate symmetry for real output: only fill the
      // "lower half" and mirror. Skip if this bin is the mirror of a
      // lower one we've already set.
      final mirror = (n - k) % n;
      if (mirror == k || mirror > k) {
        stochRe[k] = re;
        stochIm[k] = im;
        if (mirror != k) {
          stochRe[mirror] = re;
          stochIm[mirror] = -im;
        }
      }
    }

    final extendedN = n + stepsAhead;
    final out = List<double>.filled(extendedN, 0.0);
    final invSqrtN = 1.0 / math.sqrt(n);
    for (var t = 0; t < extendedN; t++) {
      var sum = 0.0;
      for (var k = 0; k < n; k++) {
        if (stochRe[k] == 0.0 && stochIm[k] == 0.0) continue;
        final phase = 2.0 * math.pi * k * t / n;
        sum += stochRe[k] * math.cos(phase) -
            stochIm[k] * math.sin(phase);
      }
      out[t] = sum * invSqrtN;
    }
    return out;
  }

  /// Dominant **non-DC** frequency of [curve] — the bin with the
  /// largest magnitude among `k ∈ [1, N/2]` (Nyquist-bounded).
  /// Returns `null` when the curve is too short (< 4 samples) or
  /// when every non-DC bin has negligible energy.
  ///
  /// Fields in the returned record:
  /// * `bin` — frequency index `k`, in `[1, N/2]`.
  /// * `magnitude` — `|X[k]|` at that bin.
  /// * `periodCommits` — `N / k`, the dominant period expressed in
  ///   commit steps. A value of 7 means "oscillates every 7 commits."
  /// * `magnitudeRatioToDC` — `|X[k]| / max(|X[0]|, ε)`, lets callers
  ///   tell cyclical signal from a trivial trend.
  ///
  /// Use this to ask: does this repo have a breathing period? What
  /// is it?
  ({int bin, double magnitude, double periodCommits, double magnitudeRatioToDC})?
      dominantFrequency(List<double> curve) {
    if (curve.length < 4) return null;
    final mag = magnitudeSpectrum(curve);
    final nyquist = mag.length ~/ 2;
    if (nyquist < 1) return null;
    var bestBin = 1;
    var bestMag = mag[1];
    for (var k = 2; k <= nyquist; k++) {
      if (mag[k] > bestMag) {
        bestMag = mag[k];
        bestBin = k;
      }
    }
    if (bestMag <= 1e-12) return null;
    final dc = mag[0] <= 1e-12 ? 1e-12 : mag[0];
    return (
      bin: bestBin,
      magnitude: bestMag,
      periodCommits: curve.length / bestBin,
      magnitudeRatioToDC: bestMag / dc,
    );
  }

  @override
  String toString() {
    if (points.isEmpty) return 'SpectralTrajectory(empty)';
    final first = points.first;
    final last = points.last;
    return 'SpectralTrajectory(n=${points.length}, '
        'from=rev${first.revision}, to=rev${last.revision}, '
        'path=${pathLength.toStringAsFixed(3)}, '
        'sig=0x${trajectorySignature.toHex()})';
  }
}

// ── Internals ───────────────────────────────────────────────────────

/// Truncated Wasserstein-1 distance between two eigenvalue
/// distributions, matching by rank up to the smaller k. Degrades
/// gracefully when two bases disagree on dimension — the common case
/// on trajectories that span file additions.
double _truncatedEigenvalueDistance(SpectralBasis a, SpectralBasis b) {
  final k = a.k < b.k ? a.k : b.k;
  if (k == 0) return 0.0;
  var s = 0.0;
  for (var j = 0; j < k; j++) {
    final d = a.eigenvalues[j] - b.eigenvalues[j];
    s += d < 0 ? -d : d;
  }
  return s / k;
}

/// Popcount of `a.lo ^ b.lo` plus popcount of `a.hi ^ b.hi` — the
/// Hamming distance between two [Signature]s taken as 62-bit bit
/// strings. Result is in `[0, 62]`.
int _signatureHammingDistance(Signature a, Signature b) {
  return _popcount31(a.lo ^ b.lo) + _popcount31(a.hi ^ b.hi);
}

/// 31-bit popcount via four mask-add passes. Analogous to [popcount8]
/// in logos_core but extended to the 31-bit half used by [Signature].
int _popcount31(int v) {
  v = (v & 0x55555555) + ((v >> 1) & 0x55555555);
  v = (v & 0x33333333) + ((v >> 2) & 0x33333333);
  v = (v & 0x0f0f0f0f) + ((v >> 4) & 0x0f0f0f0f);
  v = (v & 0x00ff00ff) + ((v >> 8) & 0x00ff00ff);
  return ((v & 0x0000ffff) + ((v >> 16) & 0x0000ffff)) & 0x3f;
}

bool _isMonotoneRevisions(List<TrajectoryPoint> points) {
  for (var i = 1; i < points.length; i++) {
    if (points[i].revision <= points[i - 1].revision) return false;
  }
  return true;
}
