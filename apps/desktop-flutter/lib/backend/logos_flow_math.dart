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
    _kr = kr;
    _ki = ki;
    _gr = gr;

    var zr = kr * _z1r - ki * _z1i - gr * _z0r;
    var zi = kr * _z1i + ki * _z1r - gr * _z0i;

    if (edgeHamming > 0) {
      final r = (1.0 - math.cos(math.pi * edgeHamming / 8)) / 2;
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

// ── Filament saturation ──────────────────────────────────────────────

/// Gap → [0, 1) fragility. `1 - e^{-x}`.
double filamentSat(double gap) => 1.0 - math.exp(-gap);

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
