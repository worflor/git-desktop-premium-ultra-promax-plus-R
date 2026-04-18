// LogosSpectroGeometry — unified geometric fingerprint of a repo.
//
// This module doesn't introduce new math. It's the *synthesis* of the
// four standalone diagnostic modules shipped during the overnight R&D
// session:
//
//   * RMT classification           — `logos_rmt.dart`
//   * Persistent homology          — `logos_persistence.dart`
//   * Spectral dimension + γ(t)    — `logos_chaos.dart`
//   * Spectral zeta invariants     — `logos_zeta.dart`
//
// Individually each module reads the spectrum through one lens. Together
// they form a **geometric fingerprint**: four independent views of the
// same underlying object, each sensitive to different spectral
// features. When they AGREE (a path: quasi-1d d_s, crystalline RMT
// class, tree-like persistence with zero β₁), the repo's geometry is
// coherent — the spectrum sits cleanly in a single universality class.
// When they DISAGREE (e.g. chaotic RMT but low spectral dimension),
// the repo is geometrically unusual — some axis dominates the spectrum
// in a way that doesn't match its topology.
//
// The derived **coherence score** `∈ [0, 1]` is a single scalar
// summarising that agreement. High coherence = every lens tells the
// same story; low coherence = the repo's geometry is layered or
// adversarial across scales.

import 'dart:math' as math;

import 'logos_core.dart';
import 'logos_chaos.dart';
import 'logos_persistence.dart';
import 'logos_rmt.dart';
import 'logos_signature.dart';
import 'logos_zeta.dart';

/// A point in canonical-graph space — distances to every known
/// universality archetype, each in `[0, 1]` (0 = match, 1 = far).
/// This is the *vector* analogue of a scalar coherence: no collapse,
/// every axis remains distinguishable.
///
/// Six archetypes span the geometric territory the engine has
/// observed so far:
///
///   * `crystalline` — path / cycle / regular-lattice Laplacians
///     with smoothly-varying level spacings.
///   * `poisson` — uncorrelated levels: random regular graphs,
///     integrable systems.
///   * `goe` — GOE-class random matrices, chaotic real-symmetric
///     operators.
///   * `tree` — dendritic topology: one dominant persistence bar,
///     quasi-1d spectral dimension.
///   * `bulk` — dense graphs, high spectral dimension (≥ 3).
///   * `modular` — clustered graphs: multiple dominant bars,
///     intermediate dimension.
///
/// Each distance is computed from the lens that's most natural for
/// that archetype; some archetypes use multiple lenses combined.
class UniversalityVector {
  final double toCrystalline;
  final double toPoisson;
  final double toGoe;
  final double toTree;
  final double toBulk;
  final double toModular;

  const UniversalityVector({
    required this.toCrystalline,
    required this.toPoisson,
    required this.toGoe,
    required this.toTree,
    required this.toBulk,
    required this.toModular,
  });

  /// Nearest archetype by minimum distance.
  ({String name, double distance}) get nearest {
    final entries = <({String name, double distance})>[
      (name: 'crystalline', distance: toCrystalline),
      (name: 'poisson', distance: toPoisson),
      (name: 'goe', distance: toGoe),
      (name: 'tree', distance: toTree),
      (name: 'bulk', distance: toBulk),
      (name: 'modular', distance: toModular),
    ];
    entries.sort((a, b) => a.distance.compareTo(b.distance));
    return entries.first;
  }

  /// Canonical-ness: how close is the repo to *some* canonical
  /// archetype? Returns `1 − min(distance)`, clamped to `[0, 1]`.
  /// High = the repo fits a known class cleanly; low = it lives
  /// between archetypes.
  double get canonicality =>
      (1.0 - nearest.distance).clamp(0.0, 1.0).toDouble();

  /// Inter-lens agreement: the repo is "coherent" when exactly one
  /// archetype dominates (nearest is decisively closer than runner-
  /// up). Returns `1 − nearest / runner_up` clamped to `[0, 1]`.
  /// Approaches 1 when one archetype is much closer than any other;
  /// approaches 0 when two archetypes tie for nearest.
  double get decisiveness {
    final sorted = <double>[
      toCrystalline, toPoisson, toGoe, toTree, toBulk, toModular,
    ]..sort();
    final d1 = sorted[0];
    final d2 = sorted[1];
    if (d2 <= 1e-12) return 0.0;
    return (1.0 - d1 / d2).clamp(0.0, 1.0).toDouble();
  }
}

/// Compact, fully-derived geometric fingerprint of a graph. Every
/// field here is a direct read-off of the spectrum / graph.
class SpectroGeometry {
  /// Random-matrix-theory classification. `null` when the spectrum was
  /// too short for the r-ratio statistics to converge.
  final RmtReport? rmt;

  /// Persistent homology of the coupling filtration. `null` when the
  /// graph had fewer than 2 nodes or no edges.
  final PersistenceDiagram? persistence;

  /// Spectral dimension from the heat-trace log-log slope. `null` when
  /// the basis was too small or the heat trace underflowed.
  final SpectralDimensionReport? spectralDim;

  /// Zeta-function scalars (log det', ζ(1), ζ(2), γ_L). Always
  /// computable from any non-empty basis.
  final ZetaReport zeta;

  /// Per-archetype distances in `[0, 1]`. Replaces the old scalar
  /// coherence: no collapse, each axis remains interpretable on its
  /// own terms.
  final UniversalityVector universality;

  /// 62-bit content hash over the four scalar summaries. Two graphs
  /// with byte-identical fingerprints share geometry modulo collision;
  /// suitable for caching, diffing, CRDT merge fast-paths.
  final Signature fingerprint;

  const SpectroGeometry({
    required this.rmt,
    required this.persistence,
    required this.spectralDim,
    required this.zeta,
    required this.universality,
    required this.fingerprint,
  });

  /// Short human-readable summary — includes the nearest archetype
  /// and decisiveness. Used for UI chrome.
  String get label {
    final n = universality.nearest;
    return '${n.name} (d=${n.distance.toStringAsFixed(2)}) · '
        'decisive=${universality.decisiveness.toStringAsFixed(2)}';
  }
}

/// Compute the full geometric fingerprint in one pass. Designed to be
/// called after the spectral basis is already cached — never builds
/// the basis itself.
SpectroGeometry spectrogeometry(CsrGraph graph, SpectralBasis basis) {
  final rmt = rmtReport(basis);
  final persistence = computeCouplingPersistence(graph);
  final sd = spectralDimension(basis);
  final zetaR = zetaReport(basis);

  final universality = _universalityVector(
    rmt: rmt,
    persistence: persistence,
    spectralDim: sd,
    zeta: zetaR,
  );

  final fingerprint = _fingerprint(
    rmt: rmt,
    persistence: persistence,
    spectralDim: sd,
    zeta: zetaR,
  );

  return SpectroGeometry(
    rmt: rmt,
    persistence: persistence,
    spectralDim: sd,
    zeta: zetaR,
    universality: universality,
    fingerprint: fingerprint,
  );
}

/// Basis-only geometric fingerprint. Computes every spectral report
/// that needs only the basis (RMT, spectral dim, ζ, universality) and
/// leaves `persistence` null — persistence requires the full coupling
/// graph, which isn't available in every context (e.g. historical
/// trajectory snapshots that stored the basis but not the graph).
///
/// The universality vector is still meaningful: only the `toTree` and
/// parts of `toCrystalline` / `toModular` distances consume the
/// persistence signal. Those fall back to the spectral-dim and RMT
/// lenses alone and remain bounded in `[0, 1]`.
SpectroGeometry spectrogeometryFromBasis(SpectralBasis basis) {
  final rmt = rmtReport(basis);
  final sd = spectralDimension(basis);
  final zetaR = zetaReport(basis);

  final universality = _universalityVector(
    rmt: rmt,
    persistence: null,
    spectralDim: sd,
    zeta: zetaR,
  );

  final fingerprint = _fingerprint(
    rmt: rmt,
    persistence: null,
    spectralDim: sd,
    zeta: zetaR,
  );

  return SpectroGeometry(
    rmt: rmt,
    persistence: null,
    spectralDim: sd,
    zeta: zetaR,
    universality: universality,
    fingerprint: fingerprint,
  );
}

/// Distance to each canonical archetype, computed from the lens that
/// best discriminates for that archetype. Each distance sits in
/// `[0, 1]` — 0 = exact match to the archetype's canonical scalars,
/// 1 = maximally unlike.
///
/// Anchoring:
///   * **crystalline**: meanR near 1; d_s near 1; near-zero
///     persistence entropy.
///   * **poisson**: meanR near `kPoissonMeanR` (0.39); persistence
///     entropy > log(n)/2; spectral dim moderate.
///   * **goe**: meanR near `kGoeMeanR` (0.54); persistence entropy
///     high.
///   * **tree**: dominant persistence (one very long bar); d_s near
///     4/3 (Alexander-Orbach on critical trees).
///   * **bulk**: d_s ≥ 3; meanR intermediate.
///   * **modular**: multiple tied persistence bars; d_s near 2.
UniversalityVector _universalityVector({
  RmtReport? rmt,
  PersistenceDiagram? persistence,
  SpectralDimensionReport? spectralDim,
  required ZetaReport zeta,
}) {
  // Helper — compute a clamped [0, 1] "how far from target T?"
  // distance using a half-range scale so |value − T| / scale ≥ 1
  // saturates to 1.
  double dist(double value, double target, double scale) {
    if (!value.isFinite || scale <= 0) return 1.0;
    return ((value - target).abs() / scale).clamp(0.0, 1.0).toDouble();
  }

  // Combine two distances with equal weight — useful when an
  // archetype is defined by more than one lens.
  double avg(double a, double b) => 0.5 * (a + b);

  final meanR = rmt?.meanR;
  final dS = spectralDim?.dS;
  final dominance =
      (persistence != null && persistence.totalPersistence > 0)
          ? persistence.maxPersistence / persistence.totalPersistence
          : null;
  final phEntropy = persistence?.persistenceEntropy;

  // Crystalline: meanR → 1, d_s → 1, near-zero persistence entropy.
  final crystR = meanR != null ? dist(meanR, 1.0, 0.45) : 1.0;
  final crystDs = dS != null ? dist(dS, 1.0, 1.5) : 1.0;
  final crystPh = phEntropy != null ? dist(phEntropy, 0.0, 2.0) : 1.0;
  final toCrystalline = (crystR + crystDs + crystPh) / 3.0;

  // Poisson: meanR → 0.39. Single-lens archetype (RMT is the
  // canonical discriminator).
  final toPoisson = meanR != null
      ? dist(meanR, kPoissonMeanR, 0.15)
      : 1.0;

  // GOE: meanR → 0.54. Same lens as Poisson, different target.
  final toGoe = meanR != null
      ? dist(meanR, kGoeMeanR, 0.10)
      : 1.0;

  // Tree: dominant persistence + low-ish d_s.
  final treeDom = dominance != null
      ? dist(dominance, 1.0, 0.8)
      : 1.0;
  final treeDs = dS != null ? dist(dS, 4.0 / 3.0, 1.0) : 1.0;
  final toTree = avg(treeDom, treeDs);

  // Bulk: d_s ≥ 3. Distance saturates past d_s = 3.
  final toBulk = dS != null ? dist(math.max(0.0, 3.0 - dS), 0.0, 2.5) : 1.0;

  // Modular: d_s near 2 + moderate persistence entropy.
  final modDs = dS != null ? dist(dS, 2.0, 1.0) : 1.0;
  final modPh = phEntropy != null ? dist(phEntropy, 1.5, 1.5) : 1.0;
  final toModular = avg(modDs, modPh);

  return UniversalityVector(
    toCrystalline: toCrystalline,
    toPoisson: toPoisson,
    toGoe: toGoe,
    toTree: toTree,
    toBulk: toBulk,
    toModular: toModular,
  );
}

/// Stable 62-bit fingerprint over the coarse-grained report scalars.
/// Coarse-grains to 4 decimal places so tiny Lanczos-convergence
/// fluctuations don't perturb the fingerprint.
Signature _fingerprint({
  RmtReport? rmt,
  PersistenceDiagram? persistence,
  SpectralDimensionReport? spectralDim,
  required ZetaReport zeta,
}) {
  final acc = StringBuffer();
  acc.write('rmt=');
  acc.write(rmt?.meanR.toStringAsFixed(4) ?? 'none');
  acc.write('|ph=');
  acc.write(persistence?.maxPersistence.toStringAsFixed(4) ?? 'none');
  acc.write('/');
  acc.write(persistence?.totalPersistence.toStringAsFixed(4) ?? 'none');
  acc.write('|ds=');
  acc.write(spectralDim?.dS.toStringAsFixed(4) ?? 'none');
  acc.write('|z=');
  acc.write(zeta.logDeterminant.toStringAsFixed(4));
  acc.write('/');
  acc.write(zeta.zetaOne.toStringAsFixed(4));
  return _signatureFromString(acc.toString());
}

/// FNV-1a-style 62-bit hash over a UTF-16 string's code units, packed
/// into a [Signature] with the same construction discipline as
/// `fingerprintFloat64` in `logos_signature.dart`.
Signature _signatureFromString(String s) {
  if (s.isEmpty) return Signature.zero;
  const mask = 0x7fffffff;
  var hLo = 0x811c9dc5 ^ s.length;
  var hHi = 0xdeadbeef ^ s.length;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    hLo = (hLo ^ c) & mask;
    hLo = ((hLo * 0x01000193) ^ (hLo >> 13)) & mask;
    hHi = (hHi ^ (c ^ 0x5a5a5a5a)) & mask;
    hHi = ((hHi * 0x01000193) ^ (hHi >> 13)) & mask;
  }
  return Signature(lo: hLo, hi: hHi);
}
