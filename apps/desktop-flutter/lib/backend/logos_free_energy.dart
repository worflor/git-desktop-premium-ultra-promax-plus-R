// LogosFreeEnergy — the engine's single health scalar.
//
// Given the repo's Laplacian as a prior (the GFF with precision
// `L + m²I`) and an observed field over the graph, the **variational
// free energy** F measures how surprising the observation is under
// that prior. Lower F = the observation aligns with the physics; high
// F = the repo is in a state its own model considers improbable.
//
// Concretely, we compute the Dirichlet (quadratic) energy of the
// observation under `L + m²I`:
//
//     F(ρ) = (1/2) · ⟨ρ, (L + m²I) ρ⟩
//          = (1/2) · Σⱼ (λⱼ + m²) · cⱼ²      where c = Uᵀρ
//
// This is exactly the negative log-likelihood of the GFF at ρ, up to
// constants that don't depend on the observation. It unifies:
//
// * Friston's free-energy principle (brain-style active inference)
// * Thermodynamic free energy (physics)
// * Variational autoencoder "reconstruction error" (modern ML)
// * Dirichlet energy of a Sobolev space (classical PDE)
//
// All four cash out to the same number here. See
// `docs/architecture/spectral-free-energy.md` for the derivation.
//
// Per-mode attribution breaks F down into which eigenmodes carry the
// most surprise — the handle that refactor proposers and anomaly
// detectors hook into downstream.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_field.dart';
import 'logos_git.dart';

/// Decomposition of a field's free energy across spectral modes.
/// Each element of [perMode] is `(λⱼ + m²) · cⱼ²` — the energy
/// contribution of mode j to the total.
class FreeEnergyAttribution {
  /// Length-k array; element j is that mode's contribution to F.
  final Float64List perMode;

  /// Total free energy `Σⱼ (λⱼ + m²) cⱼ²` (half-factor pulled out).
  final double total;

  /// Mass term `m²` used when computing the attribution.
  final double mass;

  const FreeEnergyAttribution({
    required this.perMode,
    required this.total,
    required this.mass,
  });

  /// Index of the mode carrying the single largest contribution.
  int get dominantMode {
    var best = 0;
    var bestVal = -1.0;
    for (var j = 0; j < perMode.length; j++) {
      if (perMode[j] > bestVal) {
        bestVal = perMode[j];
        best = j;
      }
    }
    return best;
  }

  /// Fraction of F that lives on the top-K modes. Useful as a
  /// "concentration" metric — high = F is focused, low = F is diffuse.
  double topKFraction(int k) {
    if (total <= 0 || perMode.isEmpty) return 0.0;
    final sorted = Float64List.fromList(perMode);
    final sortedList = sorted.toList()..sort((a, b) => b.compareTo(a));
    var taken = 0.0;
    for (var i = 0; i < k && i < sortedList.length; i++) {
      taken += sortedList[i];
    }
    return (taken / total).clamp(0.0, 1.0).toDouble();
  }
}

/// One-shot free energy of a field on the basis. Mass regularises the
/// zero mode; default `m² = 0.01` keeps λ₀ from blowing up divergences.
///
/// Works for pure-spatial (`commitCount == 1`) or spacetime fields.
/// For spacetime the free energy is summed across commit slots — each
/// slot's ρ is evaluated under the spatial Laplacian independently.
double freeEnergy(LogosField field, {double mass = 0.1}) {
  final attr = freeEnergyAttribution(field, mass: mass);
  return attr.total;
}

/// Full attribution — returns both the scalar and the per-mode split.
/// Cost: one projection per commit slot (`O(k·n)` each).
FreeEnergyAttribution freeEnergyAttribution(
  LogosField field, {
  double mass = 0.1,
}) {
  final basis = field.basis;
  final k = basis.k;
  final n = basis.n;
  final m2 = mass * mass;
  final perMode = Float64List(k);
  var total = 0.0;
  for (var kc = 0; kc < field.commitCount; kc++) {
    final slotStart = kc * n;
    final slice = Float64List.view(
        field.primal.buffer, field.primal.offsetInBytes + slotStart * 8, n);
    final coeffs = basis.project(slice);
    for (var j = 0; j < k; j++) {
      final contribution = (basis.eigenvalues[j] + m2) * coeffs[j] * coeffs[j];
      perMode[j] += contribution;
      total += contribution;
    }
  }
  return FreeEnergyAttribution(
    perMode: perMode,
    total: 0.5 * total,
    mass: mass,
  );
}

/// Build the repo's "recent activity" observation field from the
/// engine's cached volatility map, then compute its free energy.
///
/// The field is spatial (`commitCount == 1`) — each node's amplitude
/// is the normalised volatility. Represents "what part of the repo is
/// currently restless". Low F = restlessness sits on low-λ modes
/// (structural, healthy work); high F = restlessness is scattering
/// across many high-λ modes (chaotic, fragmented work).
///
/// Returns `null` when the engine has no spectral basis (tiny repo).
FreeEnergyAttribution? repoFreeEnergy(
  LogosGit engine, {
  double mass = 0.1,
}) {
  final basis = engine.spectralBasis();
  if (basis == null) return null;
  final activity = engine.stats.volatility;
  if (activity.isEmpty) return null;
  final primal = Float64List(basis.n);
  // Normalise by max volatility so the field is bounded — keeps F
  // comparable across repos of different sizes / ages.
  var maxV = 0.0;
  for (final v in activity.values) {
    if (v.abs() > maxV) maxV = v.abs();
  }
  if (maxV <= 0) return null;
  activity.forEach((path, vol) {
    final id = engine.pathToId[path];
    if (id == null) return;
    primal[id] = vol / maxV;
  });
  final field = LogosField.fromPrimal(
    basis: basis,
    primal: primal,
    commitCount: 1,
  );
  return freeEnergyAttribution(field, mass: mass);
}

/// One-shot repo health classification from the free energy and its
/// mode concentration. Returned by [repoHealth] as a summary for UI
/// chrome — a single-chip read of "is this repo stable, drifting, or
/// in crisis".
enum RepoHealth {
  /// No basis or no activity — the engine has nothing to say.
  silent,

  /// F is low and concentrated on low-λ modes. The repo's activity
  /// aligns with its own natural geometry.
  stable,

  /// F is moderate. Some structural stress; within the healthy band.
  drifting,

  /// F is high OR it's concentrated on high-λ modes. The repo is in
  /// an unusual state by its own prior.
  anomalous,

  /// F is both high and heavily concentrated on high-λ modes. A
  /// regime change is in progress (phase transition, major refactor,
  /// architectural break).
  critical,
}

extension RepoHealthLabel on RepoHealth {
  String get label {
    switch (this) {
      case RepoHealth.silent:
        return 'silent';
      case RepoHealth.stable:
        return 'stable';
      case RepoHealth.drifting:
        return 'drifting';
      case RepoHealth.anomalous:
        return 'anomalous';
      case RepoHealth.critical:
        return 'critical';
    }
  }
}

/// Classify the repo's current state from its free energy attribution.
///
/// Heuristic but stable: labels use fractional thresholds on (total F,
/// top-3 mode concentration, fraction of F on upper half of spectrum)
/// rather than absolute magnitudes, so the thresholds are repo-agnostic.
RepoHealth repoHealth(LogosGit engine, {double mass = 0.1}) {
  final attr = repoFreeEnergy(engine, mass: mass);
  if (attr == null) return RepoHealth.silent;
  if (attr.total <= 1e-9) return RepoHealth.silent;
  final k = attr.perMode.length;
  if (k == 0) return RepoHealth.silent;
  // Fraction of F carried by the upper half of the spectrum (high-λ,
  // "scattered" modes). Healthy repos keep low-F there.
  var upperHalf = 0.0;
  for (var j = k ~/ 2; j < k; j++) {
    upperHalf += attr.perMode[j];
  }
  final highFraction = attr.total > 0 ? upperHalf / (attr.total * 2.0) : 0.0;
  final concentration = attr.topKFraction(3);
  // Tiered classification:
  if (highFraction > 0.55 && concentration > 0.6) return RepoHealth.critical;
  if (highFraction > 0.45 || concentration > 0.7) return RepoHealth.anomalous;
  if (concentration > 0.5 || highFraction > 0.3) return RepoHealth.drifting;
  return RepoHealth.stable;
}

/// Continuous anomaly level in `[0, 1]` — the fraction of the repo's
/// free energy carried by the **upper half** of the spectrum (high-λ,
/// scattered modes). Clean, continuous, monotone in "how unhealthy":
///
/// * `0.0` — all energy on low-λ structural modes (pure-stable repo)
/// * `~0.25` — mild drift, occasional high-mode involvement
/// * `~0.50` — balanced; typical of active repos mid-refactor
/// * `~0.75` — anomalous; sustained scattering
/// * `~1.0`  — chaotic; no coherent structure holds the F
///
/// Returns `null` when the engine has no basis (tiny repo) or when F
/// is numerically zero (empty / silent observation).
///
/// This is the scalar downstream UIs bind to for *continuous*
/// visualisations (sheen strength, color intensity, etc.) — use this
/// instead of [repoHealth]'s discrete enum when you want a gradient.
double? repoAnomalyLevel(LogosGit engine, {double mass = 0.1}) {
  final attr = repoFreeEnergy(engine, mass: mass);
  if (attr == null) return null;
  if (attr.total <= 1e-9) return null;
  final k = attr.perMode.length;
  if (k == 0) return null;
  var upper = 0.0;
  for (var j = k ~/ 2; j < k; j++) {
    upper += attr.perMode[j];
  }
  // perMode sums to 2·total (half-factor pulled out in attribution),
  // so normalise by 2·total to land in [0, 1].
  return (upper / (2.0 * attr.total)).clamp(0.0, 1.0).toDouble();
}

/// Low-pass bias: fraction of free energy carried by the k-smallest
/// eigenvalues. Read as "how much of the work lives in structural
/// (low-frequency) modes vs scattered (high-frequency) ones".
///
/// 1.0 = all energy on the zero / lowest modes = pure structural work.
/// 0.0 = all energy on the highest mode = pure noise / scattering.
double lowPassFraction(FreeEnergyAttribution attr, {int lowModes = 4}) {
  if (attr.total <= 1e-9) return 0.0;
  final upperBound = math.min(lowModes, attr.perMode.length);
  var low = 0.0;
  for (var j = 0; j < upperBound; j++) {
    low += attr.perMode[j];
  }
  return (low / attr.total).clamp(0.0, 1.0).toDouble();
}
