// Thermodynamic observables of the Logos engine — partition functions,
// free energy, entropy, heat capacity, Von Neumann entropy, and the
// grand thermodynamic-pantheon record that packages them all at one
// temperature.
//
// This is a part of `logos_core.dart` (see `part of` below), not a
// standalone library. That lets these observables remain methods on
// [SpectralBasis] / [SpectralProjection] (via extensions) with full
// access to library-private helpers like `_subnormalFloor` — zero
// consumer-side import churn, physical separation of concerns.
//
// Taxonomy: every method here is **Theorem-tight**. These quantities
// are definitions from classical statistical mechanics on a discrete
// spectrum; their identities (Helmholtz relation, Jensen convexity of
// log Z, third-law behaviour) are proven and verified as tests.

part of 'logos_core.dart';

/// Thermodynamic observables on a cached [SpectralBasis].
///
/// Every quantity here is a direct function of the Laplacian spectrum
/// `{λⱼ}`. Consistent with the Helmholtz identity
///     F(β) = ⟨E⟩(β) − (1/β)·S(β)
/// and all standard derivative relations (`⟨E⟩ = −∂log Z/∂β`, etc.).
extension SpectralThermo on SpectralBasis {
  /// Heat trace `Z(t) = tr(e^{−t·L_sym}) = Σⱼ e^{−t·λⱼ}`.
  ///
  /// **Reading**: an isospectral invariant of the codebase. Two graphs
  /// with the same heat trace at every t share the same Laplacian
  /// spectrum (modulo Lanczos truncation); they "sound the same"
  /// (Kac, "Can one hear the shape of a drum?"). A PR that significantly
  /// shifts the trace is changing architectural shape, not just file
  /// contents. With `k = n` this is exact; with truncated `k` it
  /// captures the low-frequency contribution that dominates at
  /// any non-trivial `t`.
  double heatTrace(double t) {
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      s += math.exp(-t * eigenvalues[j]);
    }
    return s;
  }

  /// Partition function of `ρ` under the heat operator at temperature
  /// `t`: `Z(ρ, t) = ⟨ρ | e^{−t·L_sym} | ρ⟩ = Σⱼ e^{−t·λⱼ}·cⱼ²`,
  /// where `cⱼ = uⱼ·ρ` are the projection coefficients.
  ///
  /// **Reading**: how much of `ρ`'s mass survives after diffusing for
  /// time `t`. Concentrated sources on tightly-coupled clusters keep
  /// most of their mass; diffuse sources scatter into the low-mass
  /// regime. Substrate for [freeEnergy] and [spectralEntropy].
  double partitionFunction(Float64List rho, double t) {
    final coeffs = project(rho);
    var z = 0.0;
    for (var j = 0; j < k; j++) {
      z += math.exp(-t * eigenvalues[j]) * coeffs[j] * coeffs[j];
    }
    return z;
  }

  /// Helmholtz free energy of `ρ` at temperature `t`:
  /// `F(ρ, t) = −log Z(ρ, t)`.
  ///
  /// **Reading**: the natural information-theoretic cost of the
  /// source. Low free energy = `ρ` aligns with the operator's
  /// low-frequency modes (focused, well-coupled). High free energy =
  /// `ρ` lives in the high-frequency tail (scattered, poorly coupled).
  /// The minimum-free-energy `ρ` over a constraint set is the
  /// principled "minimum description length" emission set for that
  /// constraint — replaces ad-hoc budget knobs with a thermodynamic
  /// stationarity condition.
  double freeEnergy(Float64List rho, double t) {
    final z = partitionFunction(rho, t);
    if (z <= _subnormalFloor) return double.infinity;
    return -math.log(z);
  }

  /// Spectral participation entropy of `ρ` at temperature `t`:
  /// `S(ρ, t) = −Σⱼ pⱼ·log pⱼ` where `pⱼ = e^{−t·λⱼ}·cⱼ² / Z(ρ, t)`.
  ///
  /// **Reading**: how many spectral modes the source meaningfully
  /// occupies *after* thermal weighting. Bounded above by `log(k)`
  /// (uniform across modes — maximally diffuse focus); minimum 0
  /// (a single mode — maximally sharp focus). The natural scalar
  /// readout of "how focused is this PR / query / commit?". Free —
  /// it just reads off the projection we already cached.
  double spectralEntropy(Float64List rho, double t) {
    final coeffs = project(rho);
    var z = 0.0;
    final weighted = Float64List(k);
    for (var j = 0; j < k; j++) {
      final w = math.exp(-t * eigenvalues[j]) * coeffs[j] * coeffs[j];
      weighted[j] = w;
      z += w;
    }
    if (z <= _subnormalFloor) return 0.0;
    final invZ = 1.0 / z;
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      final p = weighted[j] * invZ;
      if (p > _subnormalFloor) s -= p * math.log(p);
    }
    return s;
  }

  /// **The thermodynamic pantheon** — every classical statistical-
  /// mechanics quantity derivable from the partition function
  /// `Z(β) = Σⱼ e^{-βλⱼ} = heatTrace(β)`, in one shot.
  ///
  /// Returns a record containing:
  /// * `partitionFunction` — `Z(β)`
  /// * `freeEnergy` — Helmholtz `F = −(1/β)·log Z`
  /// * `internalEnergy` — `⟨E⟩ = −∂log(Z)/∂β = Σⱼ λⱼ·e^{−βλⱼ} / Z`
  /// * `entropy` — thermodynamic entropy `S = β·(⟨E⟩ − F)` (k_B = 1)
  /// * `heatCapacity` — `C = β² · (⟨E²⟩ − ⟨E⟩²) = β²·Var(E)`
  ///
  /// ## The Grand Identity (verified by test)
  ///
  ///     F(β) = ⟨E⟩(β) − T · S(β)        with T = 1/β
  ///
  /// This is the **Helmholtz relation** — the defining identity of
  /// classical thermodynamics. It reduces to a statement about
  /// logarithmic derivatives of Z and is why we get the same
  /// physics no matter which potential we compute first.
  ///
  /// Your repo has a temperature, a heat capacity, a free energy,
  /// and an entropy. The partition function `heatTrace` contains
  /// all of them; this method unpacks.
  ///
  /// Returns NaN fields when the basis is trivial or β ≤ 0.
  ({
    double partitionFunction,
    double freeEnergy,
    double internalEnergy,
    double entropy,
    double heatCapacity,
  }) thermodynamics(double beta) {
    if (k == 0 || beta <= 0) {
      return (
        partitionFunction: double.nan,
        freeEnergy: double.nan,
        internalEnergy: double.nan,
        entropy: double.nan,
        heatCapacity: double.nan,
      );
    }
    var z = 0.0;
    var expectE = 0.0;
    var expectE2 = 0.0;
    for (var j = 0; j < k; j++) {
      final w = math.exp(-beta * eigenvalues[j]);
      z += w;
      expectE += eigenvalues[j] * w;
      expectE2 += eigenvalues[j] * eigenvalues[j] * w;
    }
    if (z <= _subnormalFloor) {
      return (
        partitionFunction: 0.0,
        freeEnergy: double.nan,
        internalEnergy: double.nan,
        entropy: double.nan,
        heatCapacity: double.nan,
      );
    }
    final f = -(1.0 / beta) * math.log(z);
    final uEnergy = expectE / z;
    final varEnergy = (expectE2 / z) - uEnergy * uEnergy;
    final entropy = beta * (uEnergy - f);
    final cap = beta * beta * varEnergy;
    return (
      partitionFunction: z,
      freeEnergy: f,
      internalEnergy: uEnergy,
      entropy: entropy,
      heatCapacity: cap,
    );
  }

  /// Von Neumann entropy of the normalized Laplacian treated as a
  /// density matrix: `S = −Σ p_j log p_j` where `p_j = λ_j / Σ λ`
  /// (zero mode excluded). Maximal value `log(k − 1)` is achieved by
  /// `K_n` (complete graph); regular expanders approach it; path and
  /// highly-structured graphs sit below.
  ///
  /// **Reading**: a single-scalar quantum-information readout of how
  /// *spectrally diverse* the graph is. Analogous to the density
  /// matrix entropy in quantum statistical mechanics; here the
  /// "microstates" are eigenmodes weighted by their Laplacian energy.
  double get vonNeumannEntropy {
    if (k < 2) return 0.0;
    // Sum of positive eigenvalues (skip zero mode(s)).
    var total = 0.0;
    for (var j = 0; j < k; j++) {
      if (eigenvalues[j] > _subnormalFloor) {
        total += eigenvalues[j];
      }
    }
    if (total <= _subnormalFloor) return 0.0;
    final invT = 1.0 / total;
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      if (eigenvalues[j] > _subnormalFloor) {
        final p = eigenvalues[j] * invT;
        s -= p * math.log(p);
      }
    }
    return s;
  }

  /// Bernstein projection of spectral energy onto three content basins.
  /// Returns ratios summing to 1 by the Bernstein identity:
  ///   ctx + meta + nbhd = 1.
  ///
  /// Each eigenmode's energy E_j = c_j² exp(−2tλ_j) is weighted by
  /// degree-2 Bernstein polynomials at spectral address s_j = λ_j/λ_max:
  ///   nbhd ← B₀(s) = (1−s)²      (low-freq, global reach)
  ///   meta ← B₁(s) = 2s(1−s)     (mid-freq, structural seams)
  ///   ctx  ← B₂(s) = s²          (high-freq, local detail)
  ///
  /// Returns null when the projection is degenerate (k < 3, λ_max ≈ 0,
  /// or Z ≈ 0). Callers should fall back to ctx-only allocation.
  ({double ctx, double meta, double nbhd})?
      bernsteinBasins(Float64List coeffs, double t) {
    if (k < 3) return null;
    final lamMax = eigenvalues[k - 1];
    if (lamMax <= _subnormalFloor) return null;
    final invLamMax = 1.0 / lamMax;

    var z = 0.0;
    var rCtx = 0.0;
    var rMeta = 0.0;
    var rNbhd = 0.0;

    for (var j = 0; j < k; j++) {
      final e = coeffs[j] * coeffs[j] * math.exp(-2.0 * t * eigenvalues[j]);
      final s = eigenvalues[j] * invLamMax;
      rNbhd += e * (1.0 - s) * (1.0 - s);
      rMeta += e * 2.0 * s * (1.0 - s);
      rCtx += e * s * s;
      z += e;
    }
    if (z <= _subnormalFloor) return null;

    final invZ = 1.0 / z;
    return (ctx: rCtx * invZ, meta: rMeta * invZ, nbhd: rNbhd * invZ);
  }

  /// Heat capacity at temperature t: the second derivative of the
  /// log-partition `log Z(t)` with respect to t. Equals the variance
  /// of `λ` under the thermal probability `pⱼ(t) = e^{−tλⱼ} / Z(t)`.
  ///
  /// **Reading**: spikes in heat capacity mark **phase transitions**
  /// — temperatures at which the codebase's effective structure changes
  /// character. Sweep t; peaks identify the codebase's natural scales
  /// (e.g. t ≈ 1.3 method-level, t ≈ 4.7 module-level). This is the
  /// diagnostic that tells you *which t to pick* for any query that
  /// wants a specific structural scale.
  double heatCapacity(double t) {
    if (k == 0) return 0.0;
    var z = 0.0;
    var zLam = 0.0;
    var zLam2 = 0.0;
    for (var j = 0; j < k; j++) {
      final w = math.exp(-t * eigenvalues[j]);
      z += w;
      zLam += w * eigenvalues[j];
      zLam2 += w * eigenvalues[j] * eigenvalues[j];
    }
    if (z <= _subnormalFloor) return 0.0;
    final mean = zLam / z;
    final meanSq = zLam2 / z;
    final variance = meanSq - mean * mean;
    return variance < 0.0 ? 0.0 : variance; // floating-point safety
  }
}

/// Thermodynamic observables that reuse a cached [SpectralProjection]'s
/// coefficients — avoiding the extra `project()` pass that the
/// [SpectralBasis]-level methods would do.
extension SpectralProjectionThermo on SpectralProjection {
  /// Spectral participation entropy at temperature [t]. See
  /// [SpectralThermo.spectralEntropy] for semantics; this variant
  /// reuses the cached projection instead of re-running `project`.
  double entropy(double t) {
    final k = basis.k;
    if (k == 0) return 0.0;
    var z = 0.0;
    final weighted = Float64List(k);
    for (var j = 0; j < k; j++) {
      final w = math.exp(-t * basis.eigenvalues[j]) *
          coefficients[j] *
          coefficients[j];
      weighted[j] = w;
      z += w;
    }
    if (z <= _subnormalFloor) return 0.0;
    final invZ = 1.0 / z;
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      final p = weighted[j] * invZ;
      if (p > _subnormalFloor) s -= p * math.log(p);
    }
    return s;
  }

  /// Free energy at temperature [t]: `F = −log Z(ρ, t)` where
  /// `Z(ρ, t) = Σⱼ e^{−t·λⱼ}·cⱼ²`. Reuses the cached coefficients
  /// — no re-projection.
  double freeEnergy(double t) {
    final k = basis.k;
    var z = 0.0;
    for (var j = 0; j < k; j++) {
      z += math.exp(-t * basis.eigenvalues[j]) *
          coefficients[j] *
          coefficients[j];
    }
    if (z <= _subnormalFloor) return double.infinity;
    return -math.log(z);
  }
}
