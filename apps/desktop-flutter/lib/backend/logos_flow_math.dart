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

// ── K-G Walsh residual ───────────────────────────────────────────────
//
// The theoretical K-G model (flowKG) computes per-axis multipliers
// independently. Its Walsh decomposition is the predicted interaction
// spectrum. The SSE lattice's Walsh decomposition is the empirical
// one. The difference is the model correction signal — which axis
// combinations the product formula gets wrong.

/// Walsh decomposition of the theoretical K-G model: compute K_r at
/// every lattice address and return the 256 Walsh coefficients.
/// This is the "prediction" — what the factored per-axis model says
/// about each interaction mode.
Float64List flowKGWalshSpectrum() {
  final f = Float64List(256);
  for (var a = 0; a < 256; a++) {
    final (kr, _, _) = flowKG(a);
    f[a] = kr;
  }
  walshHadamard(f, 8);
  return f;
}

/// Walsh-space residual between the theoretical K-G model and the
/// empirical SSE lattice. Each coefficient residual[S] measures how
/// much the |S|-way interaction between axes in S deviates from the
/// per-axis product formula's prediction.
///
/// Large residual at high-order S = the axes in S genuinely interact
/// in a way the factored model doesn't capture. This is the
/// physics-derived correction signal: no knobs, no tuning — the
/// data tells you what's missing.
///
/// Returns (walshAddress, theoreticalCoeff, empiricalCoeff, residual)
/// sorted by descending |residual|.
List<({int mode, double theoretical, double empirical, double residual})>
    flowKGResidual(FlowSseLattice lattice, {int maxCount = 32}) {
  final theoretical = flowKGWalshSpectrum();
  final empirical = lattice.walshSpectrum;

  final hits =
      <({int mode, double theoretical, double empirical, double residual})>[];
  for (var s = 1; s < 256; s++) {
    final t = theoretical[s];
    final e = empirical[s];
    final r = e - t;
    if (r.abs() < 1e-12) continue;
    hits.add((mode: s, theoretical: t, empirical: e, residual: r));
  }
  hits.sort((a, b) => b.residual.abs().compareTo(a.residual.abs()));
  if (hits.length > maxCount) return hits.sublist(0, maxCount);
  return hits;
}

/// Summary: what fraction of the SSE lattice's Walsh energy lives at
/// interaction orders ≥2? This is the "non-factoredness" of the
/// empirical observations. Zero means the axes are truly independent
/// (the K-G product formula is perfect). Closer to 1 means the
/// higher-order interactions dominate.
double flowKGInteractionStrength(FlowSseLattice lattice) {
  final spectrum = lattice.orderSpectrum;
  var higher = 0.0;
  for (var k = 2; k <= 8; k++) {
    higher += spectrum[k];
  }
  return higher;
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

  /// Merge another Welford accumulator into this one, preserving
  /// both means AND variances. Chan et al. parallel algorithm.
  void merge(FlowSseCell other) {
    if (other.n == 0) return;
    if (n == 0) {
      n = other.n;
      _mean = other._mean;
      _m2 = other._m2;
      return;
    }
    final combined = n + other.n;
    final delta = other._mean - _mean;
    _m2 += other._m2 + delta * delta * (n * other.n) / combined;
    _mean = (_mean * n + other._mean * other.n) / combined;
    n = combined;
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

/// 256-cell lattice on the 8-bit Boolean hypercube Q₈. Accumulates
/// Welford statistics per lattice address, then exposes the full
/// incidence algebra: Walsh decomposition (irreducible interactions),
/// zeta cumulative (inherited behavior), Möbius inversion (intrinsic
/// contribution), and closed-form heat kernel on the cube.
class FlowSseLattice {
  final _cells = List<FlowSseCell>.generate(256, (_) => FlowSseCell());

  // Cached decompositions — invalidated on every observe().
  Float64List? _walshCache;
  Float64List? _zetaCache;
  Float64List? _mobiusCache;
  Float64List? _orderSpectrumCache;

  void _invalidate() {
    _walshCache = null;
    _zetaCache = null;
    _mobiusCache = null;
    _orderSpectrumCache = null;
  }

  /// Feed an observation from the oscillator.
  void observe(int address, double certainty) {
    _cells[address & 0xFF].observe(certainty);
    _invalidate();
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

  double zBelowForAddress(int address, double certainty) {
    return _cells[address & 0xFF].zBelow(certainty);
  }

  double cellMean(int address) => _cells[address & 0xFF].mean;
  double cellStddev(int address) => _cells[address & 0xFF].stddev;
  int cellCount(int address) => _cells[address & 0xFF].n;

  /// Merge another lattice's cell into this one at [address],
  /// preserving both mean and variance (Chan et al.).
  void mergeCell(int address, FlowSseLattice other) {
    _cells[address & 0xFF].merge(other._cells[address & 0xFF]);
    _invalidate();
  }

  // ── Incidence algebra views ─────────────────────────────────────

  /// Raw cell means as a function on 2^[8]. The input to all three
  /// transforms. Warm cells carry their Welford mean; cold cells
  /// carry 0.5 (uninformative prior).
  Float64List _meanFunction() {
    final f = Float64List(256);
    for (var a = 0; a < 256; a++) {
      f[a] = _cells[a].n >= FlowSseCell._kWarmup ? _cells[a].mean : 0.5;
    }
    return f;
  }

  /// Walsh spectrum of the cell means. Each coefficient f̂(S) is the
  /// irreducible |S|-way interaction between the axes in S.
  ///
  /// Order 0 (S=∅): grand mean certainty across all addresses.
  /// Order 1 (|S|=1): marginal effect of each axis in isolation.
  /// Order 2 (|S|=2): pairwise interaction net of marginals.
  /// Higher orders: genuine multi-axis interactions.
  ///
  /// On a perfectly factored model (independent axes), all energy
  /// concentrates at orders 0 and 1. Energy at order ≥2 means the
  /// axes interact in ways the per-axis K-G formula doesn't capture.
  Float64List get walshSpectrum {
    if (_walshCache != null) return _walshCache!;
    final f = _meanFunction();
    walshHadamard(f, 8);
    _walshCache = f;
    return f;
  }

  /// Cumulative view: Z(S) = Σ_{T⊆S} mean(T). The total certainty
  /// behavior from all sub-roles of address S.
  Float64List get zetaView {
    if (_zetaCache != null) return _zetaCache!;
    final f = _meanFunction();
    mobiusZeta(f, 8);
    _zetaCache = f;
    return f;
  }

  /// Intrinsic view: μ(S) = the part of mean(S) NOT explained by any
  /// strict sub-address. The genuine irreducible contribution of
  /// exactly this combination of bits.
  Float64List get mobiusView {
    if (_mobiusCache != null) return _mobiusCache!;
    final f = _meanFunction();
    mobiusInvert(f, 8);
    _mobiusCache = f;
    return f;
  }

  /// Energy by interaction order: how much of the lattice's total
  /// variance lives at each order (0=DC, 1=marginal, 2=pairwise, ...).
  /// Normalized so the entries sum to 1.
  Float64List get orderSpectrum {
    if (_orderSpectrumCache != null) return _orderSpectrumCache!;
    final raw = walshOrderSpectrum(walshSpectrum, 8);
    var total = 0.0;
    for (var k = 0; k <= 8; k++) {
      total += raw[k];
    }
    if (total > 0) {
      final inv = 1.0 / total;
      for (var k = 0; k <= 8; k++) {
        raw[k] *= inv;
      }
    }
    _orderSpectrumCache = raw;
    return raw;
  }

  /// Fraction of the lattice's spectral energy living at orders 0 and 1
  /// (DC + marginals). A "factored" lattice has all its structure in
  /// per-axis effects — no genuine multi-axis interactions. As the
  /// engine accumulates consistent observations, higher-order Walsh
  /// modes average toward zero (uncorrelated random contributions
  /// cancel) and the spectrum collapses onto the factored subspace.
  /// `factoredness → 1` means the lattice has converged to a state
  /// describable by 8 independent axes; further observations won't
  /// change its shape, only sharpen it. Free — reads the cached
  /// [orderSpectrum].
  double get factoredness {
    final s = orderSpectrum;
    return s[0] + s[1];
  }

  /// True when the lattice has converged: factoredness exceeds the
  /// noise floor expected from finite-sample Welford statistics.
  /// The threshold is `1 - 1/sqrt(N)` where N is total observations —
  /// physics-derived from the standard error of Welford means, not a
  /// tuning knob. Pre-warmup (N < 64) returns false unconditionally.
  bool get isFactored {
    final n = totalObservations;
    if (n < 64) return false;
    return factoredness > 1.0 - 1.0 / math.sqrt(n);
  }

  /// Intrinsic contribution at a single address — non-destructive
  /// read from the cached Möbius view.
  double intrinsicAt(int address) => mobiusView[address & 0xFF];

  /// Dominant Walsh interactions up to [maxOrder]-way, sorted by
  /// descending magnitude.
  List<(int address, double coefficient)> dominantInteractions({
    int maxOrder = 4,
    int maxCount = 32,
  }) =>
      walshDominant(walshSpectrum, 8,
          maxOrder: maxOrder, maxCount: maxCount);

  /// Shannon entropy of the warm-cell occupancy distribution.
  /// High entropy = observations spread across many addresses
  /// (complex lattice, needs more exploration). Low entropy =
  /// concentrated in a few cells (converges fast).
  double entropy(Set<int> warmSet) {
    if (warmSet.isEmpty) return 0.0;
    var total = 0;
    for (final a in warmSet) total += _cells[a].n;
    if (total == 0) return 0.0;
    var h = 0.0;
    final invTotal = 1.0 / total;
    for (final a in warmSet) {
      final p = _cells[a].n * invTotal;
      if (p > 0) h -= p * math.log(p);
    }
    return h;
  }

  /// Apply the exact heat kernel on Q₈ to the cell means at
  /// temperature [t]. Returns a 256-element diffused certainty
  /// landscape — what the lattice "wants to look like" at thermal
  /// equilibrium. High-order interactions decay exponentially with
  /// temperature; at t→∞ only the DC mode survives.
  Float64List thermalEquilibrium(double t) =>
      cubeHeatKernel(_meanFunction(), 8, t);

  /// Walsh-space anomaly detection: identify interaction modes whose
  /// squared coefficient exceeds [sigma] standard deviations above
  /// the mean squared coefficient at their interaction order.
  /// Returns (address, coefficient, z-score) triples.
  List<(int, double, double)> anomalousInteractions({double sigma = 2.0}) {
    final spec = walshSpectrum;
    final orderEnergy = Float64List(9);
    final orderCount = List<int>.filled(9, 0);
    for (var s = 0; s < 256; s++) {
      final order = _popcount(s);
      orderEnergy[order] += spec[s] * spec[s];
      orderCount[order]++;
    }
    // Per-order mean and stddev of squared coefficients.
    final orderMean = Float64List(9);
    final orderStd = Float64List(9);
    for (var k = 0; k <= 8; k++) {
      if (orderCount[k] == 0) continue;
      orderMean[k] = orderEnergy[k] / orderCount[k];
    }
    for (var s = 0; s < 256; s++) {
      final order = _popcount(s);
      final diff = spec[s] * spec[s] - orderMean[order];
      orderStd[order] += diff * diff;
    }
    for (var k = 0; k <= 8; k++) {
      if (orderCount[k] > 1) {
        orderStd[k] = math.sqrt(orderStd[k] / (orderCount[k] - 1));
      }
    }

    final hits = <(int, double, double)>[];
    for (var s = 1; s < 256; s++) {
      final order = _popcount(s);
      final sq = spec[s] * spec[s];
      final std = orderStd[order];
      if (std < 1e-15) continue;
      final z = (sq - orderMean[order]) / std;
      if (z > sigma) hits.add((s, spec[s], z));
    }
    hits.sort((a, b) => b.$3.compareTo(a.$3));
    return hits;
  }
}

// ── Binary heap ─────────────────────────────────────────────────────

class BinaryHeap<T> {
  final List<T> _data = [];
  final int Function(T, T) _compare;

  BinaryHeap(this._compare);

  bool get isEmpty => _data.isEmpty;
  bool get isNotEmpty => _data.isNotEmpty;
  T get first => _data.first;
  int get length => _data.length;

  void push(T value) {
    _data.add(value);
    _siftUp(_data.length - 1);
  }

  T pop() {
    final top = _data.first;
    if (_data.length == 1) {
      _data.removeLast();
    } else {
      _data[0] = _data.removeLast();
      _siftDown(0);
    }
    return top;
  }

  void replaceFirst(T value) {
    _data[0] = value;
    _siftDown(0);
  }

  void _siftUp(int i) {
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_compare(_data[i], _data[p]) >= 0) break;
      final tmp = _data[i]; _data[i] = _data[p]; _data[p] = tmp;
      i = p;
    }
  }

  void _siftDown(int i) {
    while (true) {
      var target = i;
      final l = 2 * i + 1, r = 2 * i + 2;
      if (l < _data.length && _compare(_data[l], _data[target]) < 0) {
        target = l;
      }
      if (r < _data.length && _compare(_data[r], _data[target]) < 0) {
        target = r;
      }
      if (target == i) break;
      final tmp = _data[i]; _data[i] = _data[target]; _data[target] = tmp;
      i = target;
    }
  }
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

// ── Quantum walk weight vector ──────────────────────────────────────
//
// Each walker carries a priority weight on the 3-simplex
// (anomaly, structure, certainty). The priority scalar is the dot
// product w · (anomaly²·structure, anomaly·structure², certainty²·structure),
// continuously interpolating what discrete strands (alpha/beta/delta)
// sampled at the vertices. After each step, the walker absorbs: the
// weight component aligned with the local observation decreases,
// rotating the walker toward under-explored dimensions. The walk is
// a spectroscopic scan — the walker's remaining spectrum encodes what
// it still doesn't understand about the graph.

class WalkerWeight {
  double wAnomaly, wStructure, wCertainty;

  WalkerWeight(this.wAnomaly, this.wStructure, this.wCertainty);

  /// Evenly-spaced points on the 2-simplex. N=3 recovers the
  /// alpha/beta/delta vertices exactly.
  static List<WalkerWeight> simplex(int n) {
    if (n <= 0) return [];
    if (n == 1) {
      return [WalkerWeight(1.0 / 3, 1.0 / 3, 1.0 / 3)];
    }
    if (n <= 3) {
      return [
        WalkerWeight(1.0, 0.0, 0.0),
        WalkerWeight(0.0, 1.0, 0.0),
        WalkerWeight(0.0, 0.0, 1.0),
      ].sublist(0, n);
    }
    var k = 1;
    while ((k + 1) * (k + 2) ~/ 2 < n) k++;
    final points = <WalkerWeight>[];
    final invK = 1.0 / k;
    for (var i = 0; i <= k && points.length < n; i++) {
      for (var j = 0; j <= k - i && points.length < n; j++) {
        points.add(WalkerWeight(i * invK, j * invK, 1.0 - i * invK - j * invK));
      }
    }
    return points;
  }

  /// Beer-Lambert absorption: reduce weights aligned with what the
  /// walker observed, proportional to 1/maxDepth per step. After a
  /// full-depth walk the absorbed axis drops to ~1/e of its original
  /// weight. No free parameters — the rate is the walk geometry.
  void absorb(double anomaly, double structure, double certainty,
      int maxDepth) {
    if (maxDepth <= 0) return;
    final a = anomaly.clamp(0.0, 1.0);
    final s = structure / (1.0 + structure);
    final c = certainty.clamp(0.0, 1.0);
    final rate = 1.0 / maxDepth;
    wAnomaly *= 1.0 - rate * a * a;
    wStructure *= 1.0 - rate * s * s;
    wCertainty *= 1.0 - rate * c * c;
    _renormalize();
  }

  void _renormalize() {
    const floor = 1e-6;
    if (wAnomaly < floor) wAnomaly = floor;
    if (wStructure < floor) wStructure = floor;
    if (wCertainty < floor) wCertainty = floor;
    final sum = wAnomaly + wStructure + wCertainty;
    final inv = 1.0 / sum;
    wAnomaly *= inv;
    wStructure *= inv;
    wCertainty *= inv;
  }

  WalkerWeight clone() => WalkerWeight(wAnomaly, wStructure, wCertainty);

  /// Walkers biased by a prior novelty score in [0, 1].
  /// Familiar addresses (novelty→0) get anomaly-heavy walkers (hunt
  /// for what changed). Novel addresses (novelty→1) get certainty-heavy
  /// walkers (map the territory first). At novelty=0 this recovers
  /// the three simplex vertices exactly.
  static List<WalkerWeight> withPrior(double novelty) {
    final n = novelty.clamp(0.0, 1.0);
    return [
      WalkerWeight(1.0 - 0.5 * n, 0.25 * n, 0.25 * n),
      WalkerWeight(0.0, 1.0, 0.0),
      WalkerWeight(0.25 * n, 0.25 * n, 1.0 - 0.5 * n),
    ];
  }
}

// ── Search priority (dot product on the simplex) ────────────────────

double flowSearchPriority({
  required double certainty,
  required double phaseVelocity,
  required int spectralDistance,
  required int fanout,
  required double ssePrior,
  required int depth,
  required int maxDepth,
  required WalkerWeight weight,
}) {
  if (maxDepth <= 0) return 0.0;
  final anomaly = phaseVelocity * (1.0 - certainty);
  final structure = (1.0 + spectralDistance / 8.0)
      * math.log(math.max(2, fanout)) / math.ln2;
  final attention = (1.0 + ssePrior)
      * (maxDepth - depth) / maxDepth.toDouble();
  return (weight.wAnomaly * anomaly * anomaly * structure
        + weight.wStructure * anomaly * structure * structure
        + weight.wCertainty * certainty * certainty * structure)
      * attention;
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

// ── Lattice fingerprint ─────────────────────────────────────────────

/// 8-bit fingerprint of a lattice state. Splits the 256 cells into 8
/// octants (32 cells each); bit j = 1 iff octant j's mean exceeds the
/// global mean. Two lattices with similar distributions get nearby
/// fingerprints (low Hamming distance).
int latticeFingerprint(FlowSseLattice lattice) {
  var globalSum = 0.0;
  var globalCount = 0;
  for (var a = 0; a < 256; a++) {
    if (lattice.cellCount(a) >= FlowSseCell._kWarmup) {
      globalSum += lattice.cellMean(a);
      globalCount++;
    }
  }
  if (globalCount == 0) return 0;
  final globalMean = globalSum / globalCount;

  var fp = 0;
  for (var bit = 0; bit < 8; bit++) {
    var octantSum = 0.0;
    var octantCount = 0;
    final start = bit * 32;
    for (var a = start; a < start + 32; a++) {
      if (lattice.cellCount(a) >= FlowSseCell._kWarmup) {
        octantSum += lattice.cellMean(a);
        octantCount++;
      }
    }
    if (octantCount > 0 && (octantSum / octantCount) > globalMean) {
      fp |= (1 << bit);
    }
  }
  return fp;
}

// ── Eigenfrequency tokenizer ────────────────────────────────────────
//
// Self-emergent tokenizer: treat each code line as a vibrating string
// with variable tension. The tension at each point is the coupling
// strength between adjacent characters, learned from the source text's
// own co-occurrence statistics. The eigenfrequencies of this string
// encode the line's structural rhythm. The eigenvalue spectrum
// quantized to 8 bits IS the lattice address.
//
// No keywords. No grammar. No language knowledge. The character
// statistics teach the engine where tokens are (weak couplings =
// boundaries) and what they look like (eigenfrequency profile).

/// Character-pair coupling weights learned from source text.
/// The (i, j) entry counts how often character i appears immediately
/// before character j. Normalized to [0, 1]. Built once per file.
class CharCoupling {
  final Float64List _weights; // 128 × 128, row-major

  CharCoupling._(this._weights);

  factory CharCoupling.fromSource(String source) =>
      CharCoupling.fromSources([source]);

  /// Build a CharCoupling from many sources by summing raw bigram counts
  /// across all of them, then log-normalising once. This is the canonical
  /// repo-global coupling: lines from any file share a single basis, so
  /// `eigenAddress` produces addresses with stable repo-wide meaning
  /// (cell `0x47` means the same thing in every file). With a single
  /// source this is identical to the legacy per-file build.
  factory CharCoupling.fromSources(Iterable<String> sources) {
    final w = Float64List(128 * 128);
    for (final source in sources) {
      for (var i = 0; i < source.length - 1; i++) {
        final a = source.codeUnitAt(i) & 0x7F;
        final b = source.codeUnitAt(i + 1) & 0x7F;
        w[a * 128 + b] += 1;
      }
    }
    // Log-scale normalization: log(1 + count) preserves contrast
    // between rare and common pairs instead of compressing everything
    // below the dominant pair to near-zero.
    for (var i = 0; i < w.length; i++) {
      w[i] = math.log(1 + w[i]);
    }
    var maxW = 0.0;
    for (var i = 0; i < w.length; i++) {
      if (w[i] > maxW) maxW = w[i];
    }
    if (maxW > 0) {
      final inv = 1.0 / maxW;
      for (var i = 0; i < w.length; i++) {
        w[i] *= inv;
      }
    }
    return CharCoupling._(w);
  }

  /// Raw access to the 128×128 weight matrix — used by snapshot
  /// serialisation so a repo-global coupling can travel with the
  /// GYAT lattice rather than being rebuilt on every load.
  Float64List get rawWeights => _weights;

  /// Reconstruct from a previously-serialised weight matrix.
  factory CharCoupling.fromWeights(Float64List weights) {
    if (weights.length != 128 * 128) {
      throw ArgumentError('CharCoupling weights must be 128*128');
    }
    return CharCoupling._(Float64List.fromList(weights));
  }

  double weight(int a, int b) => _weights[(a & 0x7F) * 128 + (b & 0x7F)];
}

/// Eigenfrequency address for a single code line. Builds a weighted
/// path graph from character adjacency, eigendecomposes it, and
/// quantizes the eigenvalue spectrum to 8 bits.
///
/// Lines with the same eigenfrequency profile have the same structural
/// rhythm — same alternation of tightly-coupled characters (inside
/// tokens) and loosely-coupled characters (at boundaries).
/// Returns -1 for degenerate lines (too short, disconnected graph,
/// no excited modes) so callers can distinguish from legitimate
/// eigenAddr=0 (flat spectrum).
int eigenAddress(String line, CharCoupling coupling) {
  final n = line.length;
  if (n < 4) return -1;

  // Build weighted path graph: node i = character i, edge weight =
  // coupling strength between adjacent characters.
  final edgesPerNode = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n - 1; i++) {
    final a = line.codeUnitAt(i);
    final b = line.codeUnitAt(i + 1);
    final w = coupling.weight(a, b);
    if (w > 1e-10) {
      edgesPerNode[i].add((i + 1, w));
      edgesPerNode[i + 1].add((i, w));
    }
  }

  final csr = CsrGraph.fromRawEdges(n: n, edgesPerNode: edgesPerNode);
  final k = math.min(9, n);
  final basis = SpectralBasis.fromGraph(csr, k);

  if (basis.k < 2) return -1;

  // Quantize eigenvalue spectrum to 8 bits. Each bit encodes whether
  // eigenvalue j is above the line's median eigenvalue. Lines with
  // similar spectral structure get nearby addresses.
  final eigs = basis.eigenvalues;
  final start = basis.firstExcitedIndex;
  final count = basis.k - start;
  if (count < 1) return -1;

  var sum = 0.0;
  for (var j = start; j < basis.k; j++) {
    sum += eigs[j];
  }
  final mean = sum / count;

  var addr = 0;
  for (var b = 0; b < math.min(8, count); b++) {
    if (eigs[start + b] > mean) addr |= (1 << b);
  }
  return addr;
}

// ── Lattice snapshot ────────────────────────────────────────────────

extension FlowSseLatticeSnapshot on FlowSseLattice {
  /// Serialize to 768 doubles: 256 × (count, mean, m2).
  Float64List toSnapshot() {
    final out = Float64List(768);
    for (var a = 0; a < 256; a++) {
      final c = _cells[a];
      out[a * 3] = c.n.toDouble();
      out[a * 3 + 1] = c._mean;
      out[a * 3 + 2] = c._m2;
    }
    return out;
  }
}

extension FlowSseLatticeRestore on FlowSseLattice {
  /// Restore Welford state from a snapshot produced by [toSnapshot].
  void restoreFrom(Float64List data) {
    if (data.length < 768) return;
    for (var a = 0; a < 256; a++) {
      final c = _cells[a];
      c.n = data[a * 3].toInt();
      c._mean = data[a * 3 + 1];
      c._m2 = data[a * 3 + 2];
    }
    _invalidate();
  }
}
