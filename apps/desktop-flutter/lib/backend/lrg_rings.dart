// LRG structural rings — read a code graph's intrinsic structural scales from
// the heat-kernel diffusion-time axis (the Laplacian Renormalization Group),
// NOT from the size of a commit window.
//
// The physics (Villegas, Gili, Caldarelli & Gabrielli, *Nature Physics* 2023;
// density-matrix groundwork in De Domenico & Biamonte, *PRX* 2016): put the
// graph Laplacian's spectrum on a Gibbs measure at inverse-temperature τ —
//     μⱼ(τ) = e^{−τλⱼ} / Z(τ),   Z(τ) = Σⱼ e^{−τλⱼ}
// the *softmax* of −τλ over the modes — and sweep τ. Each τ is a "scale head":
// a soft attention over spectral modes at temperature 1/τ. Small τ attends to
// every mode (fine structure); large τ collapses onto the slowest modes (whole-
// repo structure). The rate at which that attention re-concentrates as τ grows
// is the network *specific heat*
//     C(τ) = −dS/d(log τ) = −τ² d⟨λ⟩τ/dτ = τ² · Varτ(λ),
// and its peaks land exactly on the graph's characteristic structural scales.
// Those peaks are the rings. The τ² is load-bearing: coarse (low-λ) scales have
// intrinsically small spectral variance, and the τ² is precisely what restores
// them to visibility so module-level rings aren't drowned by fine-structure.
//
// Why τ and not "last-W-commits": the diffusion time sweeps a FIXED graph, so
// it reads structural *scale* without confounding scale against the amount of
// accumulated history. An expanding commit window conflates the two; τ does not.
//
// "Never fabricate a ring": even a featureless graph (a star, an Erdős–Rényi
// blob) produces ONE specific-heat peak — its single trivial scale. So a lone
// peak is the baseline, not an event. Genuine hierarchy shows as MULTIPLE
// well-separated, prominent peaks. Peak *height* is size-dependent (it diverges
// with N), so rings are detected on peak *location* (τ*) and topographic
// prominence, never on absolute magnitude. A graph whose relaxation barely
// moves across the whole sweep has no resolvable scale, and the detector
// abstains rather than read rings out of numerical noise.
//
// Built entirely on the existing heat-kernel stack: relaxationRate(basis, τ) is
// ⟨λ⟩τ over the non-zero modes, logspace supplies the grid. No eigensolve
// beyond the basis the snapshot already carries.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_chaos.dart' show relaxationRate;
import 'logos_core.dart';
import 'logos_curve.dart' show logspace;

/// One structural-scale ring: a characteristic diffusion scale τ* at which a
/// band of the graph's modes "freezes out" — a level of the module hierarchy.
class LrgRing {
  /// The characteristic diffusion time (the scale). Larger τ = coarser scale.
  final double tau;

  /// Specific-heat prominence of the peak, normalised to the dominant peak's
  /// prominence (so the strongest ring is 1.0). Dimensionless and compared by
  /// ratio — never the raw, size-dependent peak height.
  final double strength;

  /// Effective number of structural pieces the graph resolves into at this
  /// scale — the modal perplexity exp(S(τ*)) of the Gibbs attention, rounded.
  /// Reads as "how many parts" the repo splits into when viewed at this scale.
  final int partsAtScale;

  const LrgRing({
    required this.tau,
    required this.strength,
    required this.partsAtScale,
  });
}

/// The structural-scale profile of one graph snapshot: the specific-heat curve
/// over the diffusion-time axis and the rings (well-separated prominent peaks)
/// read off it.
class LrgRingProfile {
  /// The scale heads — log-spaced diffusion times τ the profile was read at.
  final Float64List tauGrid;

  /// Network specific heat C(τ) = τ²·Varτ(λ) over [tauGrid]. Peaks are scales.
  final Float64List specificHeat;

  /// Relaxation rate γ(τ) = ⟨λ⟩τ over the non-zero modes — the raw signal the
  /// specific heat differentiates. Monotone-decreasing for a connected graph.
  final Float64List relaxation;

  /// Qualifying rings, ascending in τ (coarsest last). Always contains at least
  /// the dominant scale when the spectrum has resolvable excited structure.
  final List<LrgRing> rings;

  /// τ of the most prominent peak. Always finite when [rings] is non-empty.
  final double dominantTau;

  /// True when only the single trivial scale survives the gate — the honest
  /// "one characteristic scale, no module hierarchy" verdict. NOT "no rings":
  /// the graph still has its one scale; it just isn't layered.
  final bool singleScale;

  /// True when no single scale dominates — relaxation spread across the τ axis
  /// (self-similarity / a power-law spectrum) rather than a clean characteristic
  /// scale. Reported honestly alongside the lone dominant ring.
  final bool scaleInvariant;

  const LrgRingProfile({
    required this.tauGrid,
    required this.specificHeat,
    required this.relaxation,
    required this.rings,
    required this.dominantTau,
    required this.singleScale,
    required this.scaleInvariant,
  });

  /// A graph with genuine multi-level structure: two or more well-separated
  /// structural scales survived the gate.
  bool get hasHierarchy => rings.length >= 2;

  bool get isEmpty => rings.isEmpty;

  static final LrgRingProfile empty = LrgRingProfile(
    tauGrid: Float64List(0),
    specificHeat: Float64List(0),
    relaxation: Float64List(0),
    rings: const [],
    dominantTau: double.nan,
    singleScale: false,
    scaleInvariant: false,
  );
}

/// Read the structural-scale ring profile of a single [basis] (one snapshot of
/// the co-change graph) along the diffusion-time axis.
///
/// [samples] — number of scale heads (log-spaced τ). [minProminence] — a
/// secondary peak must reach this fraction of the dominant peak's prominence to
/// count as a ring. [minLogSeparation] — two rings must sit at least this far
/// apart in ln τ (≈ 0.55 ⇒ ~1.7× in τ) so one broad scale isn't split in two.
LrgRingProfile detectLrgRings(
  SpectralBasis basis, {
  int samples = 48,
  double minProminence = 0.15,
  double minLogSeparation = 0.55,
}) {
  // Need a resolved excited spectrum (at least two non-zero modes) for any
  // scale structure to exist — otherwise abstain rather than invent.
  final start = basis.firstExcitedIndex;
  if (basis.isGroundOnly || basis.k - start < 2) return LrgRingProfile.empty;

  final lamGap = basis.eigenvalues[start]; // λ₁ — the spectral gap
  final lamMax = basis.eigenvalues[basis.k - 1]; // largest resolved λ
  if (!(lamGap > kGroundStateEps) || !(lamMax > lamGap * 1.0000001)) {
    return LrgRingProfile.empty;
  }

  // τ spans the scales: the finest at ~1/λmax, the coarsest a few times 1/λgap.
  // Clamps keep a near-disconnected graph's tiny gap from blowing the grid out
  // to absurd τ (and a dense graph's window from collapsing).
  final tauMin = (0.25 / lamMax).clamp(1e-3, 1.0).toDouble();
  final tauMax = (4.0 / lamGap).clamp(tauMin * 8.0, 1e6).toDouble();
  final taus = logspace(tauMin, tauMax, samples);

  // γ(τ) = ⟨λ⟩τ over the non-zero modes (reuse). γ decreases as τ grows (modes
  // freeze out), asymptoting to the spectral gap.
  final gamma = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    gamma[i] = relaxationRate(basis, taus[i]) ?? (i > 0 ? gamma[i - 1] : 0.0);
  }

  // Anti-fabrication floor: if the relaxation barely moves across the whole
  // sweep there is no resolvable scale. Abstain rather than read rings out of
  // numerical noise. (A flat / near-degenerate spectrum lands here.)
  final dGammaTotal = gamma.first - gamma.last;
  final gammaScale = gamma.first.abs();
  if (!(dGammaTotal > 0) ||
      dGammaTotal < 0.08 * (gammaScale < 1e-9 ? 1.0 : gammaScale)) {
    return LrgRingProfile.empty;
  }

  // Network specific heat C(τ) = −τ² dγ/dτ = τ²·Varτ(λ), via the central
  // difference of γ on the uniform log grid: C = −τ · dγ/d(log τ). The τ²
  // weighting (one τ from −τ²dγ/dτ, the other folded into d/dlog) is what gives
  // coarse, low-λ scales the visibility their small variance would otherwise
  // deny them.
  final logTau = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    logTau[i] = math.log(taus[i]);
  }
  final cHeat = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    final lo = i == 0 ? 0 : i - 1;
    final hi = i == samples - 1 ? samples - 1 : i + 1;
    final dLog = logTau[hi] - logTau[lo];
    final dGdLog = dLog > 0 ? (gamma[hi] - gamma[lo]) / dLog : 0.0;
    final c = -taus[i] * dGdLog;
    cHeat[i] = c.isFinite && c > 0 ? c : 0.0;
  }

  // Topographic prominence of every local maximum (endpoints included). Per the
  // LRG result, a scale is read off the peak LOCATION and its prominence above
  // the flanking saddles — never its absolute height (which is size-dependent).
  final peaks = _prominentPeaks(taus, cHeat);
  if (peaks.isEmpty) {
    // A perfectly flat specific heat that still cleared the relaxation floor —
    // a single scale spread across the axis. Report it honestly.
    var arg = 0;
    for (var i = 1; i < samples; i++) {
      if (cHeat[i] > cHeat[arg]) arg = i;
    }
    return LrgRingProfile(
      tauGrid: taus,
      specificHeat: cHeat,
      relaxation: gamma,
      rings: [
        LrgRing(
          tau: taus[arg],
          strength: 1.0,
          partsAtScale: _partsAtScale(basis, taus[arg]),
        ),
      ],
      dominantTau: taus[arg],
      singleScale: true,
      scaleInvariant: true,
    );
  }

  peaks.sort((a, b) => b.prominence.compareTo(a.prominence));
  final promMax = peaks.first.prominence;
  final dominantTau = peaks.first.tau;

  // Greedy accept by prominence: the dominant scale always, then any secondary
  // that clears the prominence floor AND sits far enough (in ln τ) from every
  // accepted ring. This refuses both to split one broad scale and to promote a
  // tail-noise wiggle into a structural ring.
  final accepted = <_Peak>[];
  for (final p in peaks) {
    if (accepted.isNotEmpty && p.prominence < minProminence * promMax) continue;
    final tooClose = accepted.any(
      (q) => (math.log(p.tau) - math.log(q.tau)).abs() < minLogSeparation,
    );
    if (tooClose) continue;
    accepted.add(p);
  }
  accepted.sort((a, b) => a.tau.compareTo(b.tau));

  final rings = [
    for (final p in accepted)
      LrgRing(
        tau: p.tau,
        strength: promMax > 0 ? (p.prominence / promMax).clamp(0.0, 1.0) : 1.0,
        partsAtScale: _partsAtScale(basis, p.tau),
      ),
  ];

  // Scale-invariance: the dominant peak barely rises above the curve's own mean
  // — relaxation spread across scales rather than a clean single one.
  var meanC = 0.0;
  for (final c in cHeat) {
    meanC += c;
  }
  meanC /= samples;
  final scaleInvariant =
      rings.length <= 1 && (meanC <= 0 || promMax < 0.5 * meanC);

  return LrgRingProfile(
    tauGrid: taus,
    specificHeat: cHeat,
    relaxation: gamma,
    rings: rings,
    dominantTau: dominantTau,
    singleScale: rings.length == 1,
    scaleInvariant: scaleInvariant,
  );
}

class _Peak {
  final double tau;
  final double height;
  final double prominence;
  const _Peak(this.tau, this.height, this.prominence);
}

/// Local maxima of [ys] (over [xs]) with topographic prominence. A point is a
/// maximum if it's ≥ both neighbours and strictly greater than at least one;
/// endpoints count when they beat their single neighbour. Prominence is the
/// drop from the peak to the highest saddle separating it from any taller peak.
List<_Peak> _prominentPeaks(Float64List xs, Float64List ys) {
  final n = ys.length;
  if (n < 2) return const [];
  final maxima = <int>[];
  for (var i = 0; i < n; i++) {
    final l = i > 0 ? ys[i - 1] : double.negativeInfinity;
    final r = i < n - 1 ? ys[i + 1] : double.negativeInfinity;
    if (ys[i] >= l && ys[i] >= r && (ys[i] > l || ys[i] > r)) {
      maxima.add(i);
    }
  }
  final out = <_Peak>[];
  for (final i in maxima) {
    var leftFloor = ys[i];
    for (var j = i - 1; j >= 0; j--) {
      if (ys[j] > ys[i]) break;
      if (ys[j] < leftFloor) leftFloor = ys[j];
    }
    var rightFloor = ys[i];
    for (var j = i + 1; j < n; j++) {
      if (ys[j] > ys[i]) break;
      if (ys[j] < rightFloor) rightFloor = ys[j];
    }
    final prominence = ys[i] - math.max(leftFloor, rightFloor);
    if (prominence > 0) out.add(_Peak(xs[i], ys[i], prominence));
  }
  return out;
}

// ── Axis B: how the rings evolve over history ───────────────────────────────
//
// Axis A reads the structural scales of ONE snapshot. Axis B walks a sequence of
// historical snapshots (the trajectory's cumulative co-change graph at each
// commit) and watches the scales appear and dissolve — the genuine "growth
// rings over the tree's life". A scale *emerging* is a module crystallising; a
// scale *dissolving* is one melting back into the bulk. Each event is anchored
// to the commit where it stabilised, so it is datable and attributable.
//
// "Never fabricate a transition": a structural ring must resolve ≥ [minParts]
// pieces to count (the trivial whole-graph scale is excluded), and the scale
// count is median-smoothed before events are read, so a single-snapshot flicker
// never becomes a reported transition.

/// A structural transition over history — a scale level appearing or dissolving.
enum LrgEventKind { scaleEmerged, scaleDissolved }

/// One snapshot's structural-scale reading along history.
class LrgHistoryPoint {
  final String commitSha;
  final DateTime timestamp;

  /// Number of structural scales (rings resolving ≥ minParts pieces) here.
  final int scaleCount;

  /// The dominant structural scale and how many pieces it resolves.
  final double dominantTau;
  final int dominantParts;

  const LrgHistoryPoint({
    required this.commitSha,
    required this.timestamp,
    required this.scaleCount,
    required this.dominantTau,
    required this.dominantParts,
  });
}

/// A datable structural transition — a scale level emerged or dissolved.
class LrgHistoryEvent {
  final String commitSha;
  final DateTime timestamp;
  final LrgEventKind kind;
  final int fromCount;
  final int toCount;

  const LrgHistoryEvent({
    required this.commitSha,
    required this.timestamp,
    required this.kind,
    required this.fromCount,
    required this.toCount,
  });
}

/// The structural-scale history of a repository: the current scale profile
/// (Axis A on the latest snapshot), the per-snapshot scale count over history,
/// and the datable transitions where a scale level emerged or dissolved.
class LrgRingHistory {
  /// Per-snapshot scale readings, oldest first.
  final List<LrgHistoryPoint> points;

  /// Structural transitions over history, oldest first.
  final List<LrgHistoryEvent> events;

  /// The latest snapshot's full scale profile — the repo's structure *now*.
  final LrgRingProfile current;

  /// The current structural scales (rings resolving ≥ minParts pieces),
  /// ascending in τ. The whole-graph trivial scale is already excluded.
  final List<LrgRing> currentScales;

  const LrgRingHistory({
    required this.points,
    required this.events,
    required this.current,
    required this.currentScales,
  });

  bool get isEmpty => points.isEmpty;

  static final LrgRingHistory empty = LrgRingHistory(
    points: const [],
    events: const [],
    current: LrgRingProfile.empty,
    currentScales: const [],
  );
}

/// Walk [snapshots] (oldest first; each a cumulative co-change basis at a commit)
/// and read the structural-scale history. A ring counts as a structural scale
/// only when it resolves ≥ [minParts] pieces, which drops the trivial whole-graph
/// scale. The scale-count series is median-of-three smoothed before transitions
/// are read, so single-snapshot flicker never becomes an event.
LrgRingHistory lrgRingHistory(
  List<({String commitSha, DateTime timestamp, SpectralBasis basis})> snapshots, {
  int minParts = 2,
}) {
  if (snapshots.isEmpty) return LrgRingHistory.empty;

  final profiles = <LrgRingProfile>[];
  final structural = <List<LrgRing>>[];
  for (final s in snapshots) {
    final p = detectLrgRings(s.basis);
    profiles.add(p);
    structural.add(
      p.rings.where((r) => r.partsAtScale >= minParts).toList(),
    );
  }

  final rawCounts = [for (final s in structural) s.length];
  // Median-of-three smoothing kills single-snapshot flicker before any event is
  // read — a scale must hold for more than one commit to count as a transition.
  final counts = List<int>.generate(rawCounts.length, (i) {
    if (i == 0 || i == rawCounts.length - 1) return rawCounts[i];
    final a = rawCounts[i - 1], b = rawCounts[i], c = rawCounts[i + 1];
    return math.max(math.min(a, b), math.min(math.max(a, b), c)); // median
  });

  final points = <LrgHistoryPoint>[];
  for (var i = 0; i < snapshots.length; i++) {
    final dom = structural[i].isNotEmpty
        ? structural[i].reduce((a, b) => a.strength >= b.strength ? a : b)
        : null;
    points.add(LrgHistoryPoint(
      commitSha: snapshots[i].commitSha,
      timestamp: snapshots[i].timestamp,
      scaleCount: counts[i],
      dominantTau: dom?.tau ?? profiles[i].dominantTau,
      dominantParts: dom?.partsAtScale ?? 0,
    ));
  }

  final events = <LrgHistoryEvent>[];
  var last = counts.isNotEmpty ? counts.first : 0;
  for (var i = 1; i < counts.length; i++) {
    if (counts[i] == last) continue;
    events.add(LrgHistoryEvent(
      commitSha: snapshots[i].commitSha,
      timestamp: snapshots[i].timestamp,
      kind: counts[i] > last
          ? LrgEventKind.scaleEmerged
          : LrgEventKind.scaleDissolved,
      fromCount: last,
      toCount: counts[i],
    ));
    last = counts[i];
  }

  return LrgRingHistory(
    points: points,
    events: events,
    current: profiles.last,
    currentScales: structural.last,
  );
}

/// Effective number of structural pieces at scale τ — the modal perplexity
/// exp(S(τ)) of the Gibbs attention μⱼ(τ) = e^{−τλⱼ}/Z over the resolved modes.
/// At a coarse ring few modes are active (a handful of big modules); at a fine
/// ring many are. Computed directly from the eigenvalues; capped by the basis's
/// resolved mode count.
int _partsAtScale(SpectralBasis basis, double tau) {
  final eigs = basis.eigenvalues;
  final k = basis.k;
  var z = 0.0;
  final w = Float64List(k);
  for (var j = 0; j < k; j++) {
    final e = math.exp(-tau * eigs[j]);
    w[j] = e;
    z += e;
  }
  if (z <= 1e-300) return 1;
  var entropy = 0.0;
  for (var j = 0; j < k; j++) {
    final p = w[j] / z;
    if (p > 1e-12) entropy -= p * math.log(p);
  }
  final perplexity = math.exp(entropy);
  return perplexity.isFinite ? math.max(1, perplexity.round()) : 1;
}
