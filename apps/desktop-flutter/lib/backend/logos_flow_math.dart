// Filament math primitives — oscillator, Born mixing, lattice constants.

part of 'logos_core.dart';

// ── Lattice constants ────────────────────────────────────────────────

const int kFlowMutates      = 1 << 0;
const int kFlowAsync        = 1 << 1;
const int kFlowResource     = 1 << 2;
const int kFlowLifecycle    = 1 << 3;
const int kFlowIO           = 1 << 4;
const int kFlowPure         = 1 << 5;
const int kFlowError        = 1 << 6;
const int kFlowRestabilizes = 1 << 7;

// Derived physical constants (computed once, used in every kg() call).
final double _sinPi8Sq  = math.sin(math.pi / 8) * math.sin(math.pi / 8);
final double _sinPi16Sq = math.sin(math.pi / 16) * math.sin(math.pi / 16);
final double _sinPi4    = math.sin(math.pi / 4);
final double _inv2Pi    = 1.0 / (2 * math.pi);
final double _inv8Pi    = 1.0 / (8 * math.pi);

// ── K-G spectrum ─────────────────────────────────────────────────────

/// K-G coefficients from lattice address + Lyapunov.
///
/// Returns (K_real, K_imag, G_real). The imaginary part of K encodes
/// phase rotation from temporal context shifts.
(double, double, double) flowKG(int address,
    {double lyapunov = 0.0, double restabCoverage = 0.0}) {
  var kr = 1.0;
  var ki = 0.0;
  var gr = 0.0;

  if (address & kFlowAsync != 0) {
    kr *= math.exp(-lyapunov * lyapunov);
    ki += lyapunov * _sinPi4 * _inv2Pi;
    gr = 0.0;
  }
  if (address & kFlowLifecycle != 0) {
    gr += _sinPi8Sq;
  }
  if (address & kFlowMutates != 0) {
    kr *= 7.0 / 8.0;
  }
  if (address & kFlowIO != 0) {
    kr *= 3.0 / 4.0;
  }
  if (address & kFlowError != 0) {
    kr *= 8.0 / 7.0;
    ki += _inv8Pi;
  }
  if (address & kFlowResource != 0) {
    gr += _sinPi16Sq;
  }
  if (address & kFlowPure != 0 && address & ~kFlowPure == 0) {
    kr = 1.0;
    gr = 0.0;
  }
  if (address & kFlowRestabilizes != 0) {
    final f = math.max(restabCoverage, 0.25);
    final fClamped = math.min(f, 0.95);
    kr = math.max(kr, 1.0 / (1.0 - fClamped));
    gr = -fClamped / 4.0;
  }

  return (kr, ki, gr);
}

// ── Hamming distance ─────────────────────────────────────────────────

/// Hamming distance between two 8-bit lattice addresses.
/// This IS the edge impedance in the Boolean hypercube.
int flowHamming(int a, int b) {
  var x = a ^ b;
  // Kernighan's bit-count (popcount for small ints)
  var count = 0;
  while (x != 0) {
    x &= x - 1;
    count++;
  }
  return count;
}

/// Axis overlap between restabilizer and resource.
double flowCoverage(int restabAddr, int resourceAddr) {
  final bits = _popcount8(resourceAddr);
  if (bits == 0) return 1.0;
  return _popcount8(restabAddr & resourceAddr) / bits;
}

int _popcount8(int x) {
  var count = 0;
  var v = x & 0xFF;
  while (v != 0) {
    v &= v - 1;
    count++;
  }
  return count;
}

// ── AR(2) oscillator ─────────────────────────────────────────────────

/// AR(2) oscillator. |z| = certainty, arg(z) = phase.
class FlowOscillator {
  double _kr, _ki, _gr;
  double _z1r, _z1i; // z[n-1] real, imag
  double _z0r, _z0i; // z[n-2] real, imag

  FlowOscillator()
      : _kr = 1.0, _ki = 0.0, _gr = 0.0,
        _z1r = 1.0, _z1i = 0.0,
        _z0r = 1.0, _z0i = 0.0;

  /// Propagate through an edge to a node with given K, G.
  /// The edge's Hamming distance provides impedance.
  /// Returns the new certainty.
  double step(double kr, double ki, double gr, int edgeHamming) {
    // Same lattice address → same point on the Boolean hypercube.
    // No structural boundary crossed, so suppress the damping term.
    if (edgeHamming == 0) gr = 0.0;

    _kr = kr;
    _ki = ki;
    _gr = gr;

    var zr = kr * _z1r - ki * _z1i - gr * _z0r;
    var zi = kr * _z1i + ki * _z1r - gr * _z0i;

    if (edgeHamming > 0) {
      final hNorm = edgeHamming / 8.0;
      final r = hNorm * hNorm;
      final t = 1.0 - r;
      zr *= t;
      zi *= t;
    }

    _z0r = _z1r;
    _z0i = _z1i;
    _z1r = zr;
    _z1i = zi;
    return certainty;
  }

  /// Interpolate toward baseline.
  void restabilize(double strength) {
    _z1r += strength * (1.0 - _z1r);
    _z1i += strength * (0.0 - _z1i);
    _z0r += strength * (1.0 - _z0r);
    _z0i += strength * (0.0 - _z0i);
  }

  /// Current certainty: |z[n-1]|, clamped to [0, 1].
  double get certainty {
    final mag = math.sqrt(_z1r * _z1r + _z1i * _z1i);
    return mag < 1.0 ? mag : 1.0;
  }

  /// Phase angle in radians.
  double get phase {
    if (_z1r.abs() < 1e-15 && _z1i.abs() < 1e-15) return 0.0;
    return math.atan2(_z1i, _z1r);
  }

  /// Clone for branch exploration.
  FlowOscillator clone() {
    final o = FlowOscillator();
    o._kr = _kr; o._ki = _ki; o._gr = _gr;
    o._z1r = _z1r; o._z1i = _z1i;
    o._z0r = _z0r; o._z0i = _z0i;
    return o;
  }
}

// ── AR(2) SSE lattice ────────────────────────────────────────────────
//
// Self-calibrating layer for the oscillator. The 8-bit lattice address
// indexes 256 cells, each accumulating Welford online statistics on the
// certainty values the oscillator actually produces. After a warmup
// period, findings are gated by z-score against the learned baseline —
// only statistically anomalous certainty drops survive.
//
// Analogous to LogosSseCell on the Logos side: observe → learn → gate.

/// Single Welford accumulator for one lattice address.
class FlowSseCell {
  int n = 0;
  double _mean = 0.0;
  double _m2 = 0.0;

  void observe(double certainty) {
    n++;
    final delta = certainty - _mean;
    _mean += delta / n;
    final delta2 = certainty - _mean;
    _m2 += delta * delta2;
  }

  double get mean => _mean;
  double get variance => n > 1 ? _m2 / (n - 1) : 1.0;
  double get stddev => math.sqrt(variance);

  /// How many σ below the cell mean this observation sits.
  /// Positive = worse than average. Returns 0 during warmup.
  double zBelow(double certainty) {
    if (n < _kWarmup) return 0.0;
    final s = stddev;
    if (s < 1e-15) return 0.0;
    return (_mean - certainty) / s;
  }

  static const int _kWarmup = 8;
}

/// 256-cell lattice on the 8-bit address. Accumulates across a repo scan,
/// then gates findings via [isAnomalous].
class FlowSseLattice {
  final _cells = List<FlowSseCell>.generate(256, (_) => FlowSseCell());

  /// Feed an observation from the oscillator.
  void observe(int address, double certainty) {
    _cells[address & 0xFF].observe(certainty);
  }

  /// After warmup, returns true when the certainty at this address is
  /// statistically anomalous (> [sigma] standard deviations below mean).
  bool isAnomalous(int address, double certainty, {double sigma = 1.5}) {
    final cell = _cells[address & 0xFF];
    if (cell.n < FlowSseCell._kWarmup) return true;
    return cell.zBelow(certainty) > sigma;
  }

  /// Total observations across all cells.
  int get totalObservations => _cells.fold(0, (s, c) => s + c.n);
}

// ── Branch amplification ─────────────────────────────────────────────

/// Certainty restoration gain at a branch point with the given fanout.
/// Uses sin²(π/16) — the resource-axis spectral gap — scaled by the
/// information content log₂(fanout). Saturated through a tanh envelope
/// with asymptote 0.25 so the gain curve is C∞ — no discontinuous
/// derivative at the cap, and deeply nested switches still produce
/// distinguishable (if diminishing) gains.
double flowBranchGain(int fanout) {
  if (fanout <= 1) return 0.0;
  final raw = _sinPi16Sq * math.log(fanout.toDouble()) / math.ln2;
  final x = raw / 0.25;
  final e2x = math.exp(2.0 * x);
  return 0.25 * (e2x - 1.0) / (e2x + 1.0);
}

// ── Phase coherence ─────────────────────────────────────────────────

/// Resultant length of unit phasors — measures how much the arriving
/// paths agree on phase. 1.0 = perfect agreement, 0.0 = uniform scatter.
double flowPhaseCoherence(List<(double, double)> arrivals) {
  if (arrivals.length <= 1) return 1.0;
  var cosSum = 0.0, sinSum = 0.0;
  for (final (_, phase) in arrivals) {
    cosSum += math.cos(phase);
    sinSum += math.sin(phase);
  }
  final n = arrivals.length.toDouble();
  return math.sqrt(cosSum * cosSum + sinSum * sinSum) / n;
}

/// Detect contradictory flow: arrivals that split into two confident,
/// near-antipodal phase clusters. Returns true when k=2 means on the
/// unit circle produces two groups with:
///   - mean certainty > [certFloor] in each cluster
///   - inter-cluster phase gap > [gapMin] radians
///   - at least [minPerCluster] arrivals per cluster
///
/// This distinguishes genuine logical contradiction (bimodal, high
/// certainty per path) from uniform noise (low certainty, scattered).
bool flowIsContradictory(
  List<(double, double)> arrivals, {
  double certFloor = 0.15,
  double gapMin = 1.8,
  int minPerCluster = 2,
}) {
  if (arrivals.length < 2 * minPerCluster) return false;

  // k-means with k=2 on the unit circle. Seed: the two arrivals with
  // the largest phase difference.
  var bestGap = 0.0;
  var seedA = 0.0, seedB = 0.0;
  for (var i = 0; i < arrivals.length; i++) {
    for (var j = i + 1; j < arrivals.length; j++) {
      var d = (arrivals[i].$2 - arrivals[j].$2).abs();
      if (d > math.pi) d = 2 * math.pi - d;
      if (d > bestGap) {
        bestGap = d;
        seedA = arrivals[i].$2;
        seedB = arrivals[j].$2;
      }
    }
  }
  if (bestGap < gapMin) return false;

  // Assign arrivals to nearest seed by circular distance.
  var nA = 0, nB = 0;
  var certSumA = 0.0, certSumB = 0.0;
  for (final (cert, phase) in arrivals) {
    var dA = (phase - seedA).abs();
    if (dA > math.pi) dA = 2 * math.pi - dA;
    var dB = (phase - seedB).abs();
    if (dB > math.pi) dB = 2 * math.pi - dB;
    if (dA <= dB) {
      nA++;
      certSumA += cert;
    } else {
      nB++;
      certSumB += cert;
    }
  }

  if (nA < minPerCluster || nB < minPerCluster) return false;
  final meanCertA = certSumA / nA;
  final meanCertB = certSumB / nB;
  return meanCertA >= certFloor && meanCertB >= certFloor;
}

// ── Filament saturation ──────────────────────────────────────────────

/// Gap → [0, 1) fragility. `1 - e^{-x/4}`.
/// Scaled so gaps in the real range (0–16) spread across the full [0, 1).
double filamentSat(double gap) => 1.0 - math.exp(-gap / 4.0);

// ── Born rule mixing ─────────────────────────────────────────────────

/// Born-rule mixing of path arrivals → (certainty, phase).
(double, double) flowBornMix(List<(double, double)> arrivals) {
  var a0 = 0.0, a1 = 0.0, ps = 0.0, cs = 0.0;
  for (final (cert, phase) in arrivals) {
    final c = cert.clamp(1e-10, 1.0 - 1e-10);
    a0 += math.sqrt(c);
    a1 += math.sqrt(1.0 - c);
    ps += phase * c;
    cs += c;
  }
  final s0 = a0 * a0, s1 = a1 * a1;
  final d = s0 + s1;
  return (
    d > 1e-30 ? s0 / d : 0.5,
    cs > 1e-15 ? ps / cs : 0.0,
  );
}
