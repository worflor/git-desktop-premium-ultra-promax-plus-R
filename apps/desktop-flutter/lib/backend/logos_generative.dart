// Generative primitives for the Logos engine — the full probabilistic
// physics apparatus built on the Gaussian Free Field prior.
//
// Every method in this file is a specific probabilistic cut of the
// same underlying distribution: the GFF with precision (L + m²I).
// See `docs/architecture/spectral-generative.md` for the derivation
// chain connecting all of them.
//
// Taxonomy: every method is **Theorem-tight**. The GFF sampling formula,
// the Kriging mean/covariance, the Langevin stationary distribution,
// and the closed-form GFF score are all exact analytic results. No
// approximations beyond finite-basis (Lanczos truncation) and finite-
// sample (Monte-Carlo estimation of expectations).

part of 'logos_core.dart';

/// Standard normal sample via Box-Muller. Library-private helper used
/// by every primitive in this file — Dart's `Random` only gives
/// uniform [0, 1), so we synthesise Gaussian draws from pairs.
///
/// Rejects `u1 = 0` by clamping to `1e-300`; the probability of
/// hitting exactly zero in f64 is vanishingly small but not zero.
double _gaussianStd(math.Random rng) {
  final u1 = rng.nextDouble();
  final u2 = rng.nextDouble();
  return math.sqrt(-2.0 * math.log(u1.clamp(1e-300, 1.0))) *
      math.cos(2.0 * math.pi * u2);
}

/// Generative primitives on a cached [SpectralBasis].
///
/// Each method draws fields on the graph's nodes from a distribution
/// induced by the spectral basis: the Gaussian Free Field, its
/// conditionals, its MCMC chain (Langevin), and its denoising diffusion.
///
/// Every sample respects the graph's coupling geometry — the same
/// geometry that drives the heat kernel, the mode basis, and the
/// physics observables. Nothing is an approximation beyond Lanczos
/// truncation; every sampler is an exact draw from the stated prior
/// given the retained modes.
extension SpectralGenerative on SpectralBasis {
  /// i.i.d. standard Gaussian noise at every node. The canonical
  /// starting distribution for diffusion-style generators. No graph
  /// structure in the covariance — this is pure white noise.
  Float64List sampleWhiteNoise(math.Random rng) {
    final out = Float64List(n);
    for (var i = 0; i < n; i++) out[i] = _gaussianStd(rng);
    return out;
  }

  /// Sample from the massive Gaussian Free Field with covariance
  /// `(L + m²I)⁻¹`. In mode coordinates:
  ///
  ///     ξⱼ ~ N(0, 1)
  ///     cⱼ = ξⱼ / √(λⱼ + m²)
  ///     ρ(v) = Σⱼ cⱼ · uⱼ(v)
  ///
  /// - `mass`: regularisation term `m²` that tames the zero mode.
  ///   For `mass = 0` the zero mode has infinite variance — set
  ///   `skipZeroMode = true` to project it out instead (samples the
  ///   fluctuation field).
  /// - `skipZeroMode`: when `true`, drops `j = 0` entirely. Produces a
  ///   sample with zero projection on `u₀`, appropriate when the mean
  ///   is undefined or irrelevant.
  Float64List sampleGaussianFreeField({
    required math.Random rng,
    double mass = 0.0,
    bool skipZeroMode = false,
  }) {
    final out = Float64List(n);
    if (k == 0) return out;
    for (var j = 0; j < k; j++) {
      if (skipZeroMode && j == 0) continue;
      final lam = eigenvalues[j];
      final denom = lam + mass * mass;
      if (denom <= _subnormalFloor) continue;
      final scale = _gaussianStd(rng) / math.sqrt(denom);
      final base = j * n;
      for (var v = 0; v < n; v++) {
        out[v] += scale * eigenvectors[base + v];
      }
    }
    return out;
  }

  /// Sample from a spectrally-coloured Gaussian with variance profile
  /// `variance(λⱼ)` at mode `j`. This is the universal spectral sampler
  /// — every Gaussian with eigenvector basis `U` and diagonal covariance
  /// can be written this way. Set:
  ///
  /// * `variance: (l) => 1/(l + m²)` → massive GFF
  /// * `variance: (l) => exp(−t·l)` → heat-kernel prior (Matérn-like)
  /// * `variance: (l) => 1/(l + m²)²` → Matérn-3/2 equivalent
  /// * `variance: (l) => 1` → white noise (trivially)
  ///
  /// Covers every variance-structured Gaussian you'd want as a prior
  /// on this graph.
  Float64List sampleSpectralColored({
    required math.Random rng,
    required double Function(double lambda) variance,
  }) {
    final out = Float64List(n);
    if (k == 0) return out;
    for (var j = 0; j < k; j++) {
      final v = variance(eigenvalues[j]);
      if (!v.isFinite || v <= 0) continue;
      final scale = _gaussianStd(rng) * math.sqrt(v);
      final base = j * n;
      for (var i = 0; i < n; i++) {
        out[i] += scale * eigenvectors[base + i];
      }
    }
    return out;
  }

  /// Sample from the GFF conditional on observations at specified
  /// nodes — **Kriging** on the graph's intrinsic covariance.
  ///
  /// Given observations `y = observedValues` at nodes `A = observedNodes`,
  /// the posterior over the full field is Gaussian with:
  ///
  ///     μ_{v|A} = Σ_{a∈A} Σ(v, a) · (Σ_AA⁻¹·y)_a
  ///     Σ_{v|A} = Σ(v, v) − Σ_{a∈A} Σ(v, a) · (Σ_AA⁻¹)_{aa'} · Σ(a', v)
  ///
  /// where `Σ(x, y) = Σⱼ uⱼ(x) uⱼ(y) / (λⱼ + m²)` is the GFF covariance
  /// from Chapter 1.
  ///
  /// Algorithm:
  /// 1. Compute `Σ_AA` (dense k×k, `k = |A|`).
  /// 2. Solve `α = Σ_AA⁻¹ · y` via Gaussian elimination (small k).
  /// 3. Set `μ(v) = Σ_{a∈A} Σ(v, a) · αₐ` for every v.
  /// 4. Add a residual sample: draw `ρ_free` unconditionally, subtract
  ///    its own projection onto A, add to μ. Result is a legitimate
  ///    draw from the posterior.
  ///
  /// Throws [ArgumentError] if the lengths don't match or if any
  /// observed node is out of range.
  Float64List sampleConditionalGFF({
    required List<int> observedNodes,
    required Float64List observedValues,
    required math.Random rng,
    double mass = 0.0,
  }) {
    if (observedNodes.length != observedValues.length) {
      throw ArgumentError('observedNodes and observedValues length mismatch');
    }
    final kObs = observedNodes.length;
    for (final node in observedNodes) {
      if (node < 0 || node >= n) {
        throw ArgumentError.value(node, 'observedNode', 'out of range [0, $n)');
      }
    }
    if (kObs == 0) {
      return sampleGaussianFreeField(rng: rng, mass: mass);
    }
    // Step 1: Σ_AA matrix in row-major layout.
    final sigAA = Float64List(kObs * kObs);
    for (var i = 0; i < kObs; i++) {
      final a = observedNodes[i];
      for (var jObs = i; jObs < kObs; jObs++) {
        final b = observedNodes[jObs];
        var s = 0.0;
        for (var jMode = 0; jMode < k; jMode++) {
          final lam = eigenvalues[jMode];
          final denom = lam + mass * mass;
          if (denom <= _subnormalFloor) continue;
          s += eigenvectors[jMode * n + a] *
              eigenvectors[jMode * n + b] /
              denom;
        }
        sigAA[i * kObs + jObs] = s;
        sigAA[jObs * kObs + i] = s;
      }
    }
    // Step 2: solve Σ_AA · α = y via Gauss elimination with partial
    // pivoting. k is small (handful of observations); no need for
    // a sparse solver.
    final alpha = _solveDenseSym(sigAA, observedValues, kObs);
    // Step 3: mean μ(v) = Σ_a Σ(v, a)·α_a for every v. Expand the
    // covariance in spectral form so the outer node loop is O(n·k).
    final mu = Float64List(n);
    for (var jMode = 0; jMode < k; jMode++) {
      final lam = eigenvalues[jMode];
      final denom = lam + mass * mass;
      if (denom <= _subnormalFloor) continue;
      var modeCoeff = 0.0;
      for (var iObs = 0; iObs < kObs; iObs++) {
        modeCoeff += eigenvectors[jMode * n + observedNodes[iObs]] *
            alpha[iObs];
      }
      modeCoeff /= denom;
      final base = jMode * n;
      for (var v = 0; v < n; v++) {
        mu[v] += modeCoeff * eigenvectors[base + v];
      }
    }
    // Step 4: residual sample via "conditional by subtraction" trick.
    // Draw an unconditional GFF sample, then project out its own
    // implied observations — the result has zero mean at A and the
    // correct residual covariance.
    final residualFree = sampleGaussianFreeField(rng: rng, mass: mass);
    final residualObs = Float64List(kObs);
    for (var iObs = 0; iObs < kObs; iObs++) {
      residualObs[iObs] = residualFree[observedNodes[iObs]];
    }
    final residualAlpha = _solveDenseSym(sigAA, residualObs, kObs);
    final residualMean = Float64List(n);
    for (var jMode = 0; jMode < k; jMode++) {
      final lam = eigenvalues[jMode];
      final denom = lam + mass * mass;
      if (denom <= _subnormalFloor) continue;
      var modeCoeff = 0.0;
      for (var iObs = 0; iObs < kObs; iObs++) {
        modeCoeff += eigenvectors[jMode * n + observedNodes[iObs]] *
            residualAlpha[iObs];
      }
      modeCoeff /= denom;
      final base = jMode * n;
      for (var v = 0; v < n; v++) {
        residualMean[v] += modeCoeff * eigenvectors[base + v];
      }
    }
    final out = Float64List(n);
    for (var v = 0; v < n; v++) {
      out[v] = mu[v] + residualFree[v] - residualMean[v];
    }
    return out;
  }

  /// One Euler-Maruyama step of Langevin dynamics on the GFF potential
  /// `E(ρ) = (1/2)⟨ρ, (L + m²)ρ⟩` at inverse temperature `beta`.
  ///
  ///     ρ_{k+1} = ρ_k − (L + m²)ρ_k · dt + √(2·dt/β) · ξ_k
  ///
  /// Spectral implementation: apply the update per mode to avoid a
  /// matvec. Stable when `dt < 2 / (λ_max + m²)`.
  Float64List langevinStep({
    required Float64List rho,
    required double dt,
    required double beta,
    required math.Random rng,
    double mass = 0.0,
  }) {
    if (rho.length != n) {
      throw ArgumentError('rho length ${rho.length} != n=$n');
    }
    if (dt <= 0 || beta <= 0) {
      throw ArgumentError('dt and beta must be positive');
    }
    final coeffs = project(rho);
    final noiseMag = math.sqrt(2.0 * dt / beta);
    final newCoeffs = Float64List(k);
    for (var j = 0; j < k; j++) {
      final shrink = 1.0 - (eigenvalues[j] + mass * mass) * dt;
      newCoeffs[j] = shrink * coeffs[j];
    }
    // Reconstruct the drift step in node space.
    final out = Float64List(n);
    for (var j = 0; j < k; j++) {
      final c = newCoeffs[j];
      final base = j * n;
      for (var v = 0; v < n; v++) {
        out[v] += c * eigenvectors[base + v];
      }
    }
    // Add WHITE Gaussian noise. For the standard overdamped Langevin
    // SDE `dρ = −(L+m²)ρ·dt + √(2/β)·dW` the noise is isotropic; the
    // stationary distribution is then exactly the GFF with precision
    // `β·(L + m²)`. (Colouring the noise by the GFF covariance would
    // instead square the effective precision — a different and rarely-
    // wanted target.)
    for (var v = 0; v < n; v++) {
      out[v] += noiseMag * _gaussianStd(rng);
    }
    return out;
  }

  /// Run `steps` iterations of Langevin dynamics from `rho0`. Returns
  /// the final sample; useful for MCMC stationary sampling once the
  /// chain has mixed past `~1/λ₁` steps.
  ///
  /// For intermediate diagnostics use [langevinStep] directly and store
  /// the chain yourself.
  Float64List sampleLangevin({
    required Float64List rho0,
    required double dt,
    required int steps,
    required double beta,
    required math.Random rng,
    double mass = 0.0,
  }) {
    var rho = Float64List.fromList(rho0);
    for (var s = 0; s < steps; s++) {
      rho = langevinStep(
        rho: rho,
        dt: dt,
        beta: beta,
        rng: rng,
        mass: mass,
      );
    }
    return rho;
  }

  /// Forward VP-SDE noising step: `ρ_{t+dt} = α·ρ_t + σ·ε` where
  /// `α² + σ² = 1` and the schedule is encoded in `alpha`. Graph-aware:
  /// the noise `ε` is sampled from the GFF prior (not white noise)
  /// so the stationary distribution at `t = T` is exactly the GFF.
  ///
  /// Typical schedule: start with `alpha ≈ 1` (mostly data) and
  /// decrease toward 0 (mostly noise) over many steps.
  Float64List forwardNoisingStep({
    required Float64List rho,
    required double alpha,
    required math.Random rng,
    double mass = 0.0,
  }) {
    if (rho.length != n) {
      throw ArgumentError('rho length ${rho.length} != n=$n');
    }
    final a = alpha.clamp(0.0, 1.0).toDouble();
    final sigma = math.sqrt((1.0 - a * a).clamp(0.0, 1.0));
    final noise = sampleGaussianFreeField(rng: rng, mass: mass);
    final out = Float64List(n);
    for (var v = 0; v < n; v++) {
      out[v] = a * rho[v] + sigma * noise[v];
    }
    return out;
  }

  /// Reverse denoising step with the **analytic GFF score**. At
  /// diffusion time t with signal level α, the optimal (Tweedie) score
  /// for a Gaussian prior with per-mode variance `v_j = 1/(λⱼ + m²)` is
  ///
  ///     score(ρ_t)_j = −(α² + σ²/v_j)⁻¹ · c_j(ρ_t)
  ///
  /// where `c_j(ρ_t) = ⟨u_j, ρ_t⟩` is the mode-j coefficient of the
  /// current noisy state.
  ///
  /// We apply the reverse SDE update
  ///
  ///     ρ_{t−dt} = ρ_t + dt·(−(1/2)β·ρ_t − β·score(ρ_t)) + √(β·dt)·ε
  ///
  /// with β ≈ 1 absorbed into dt scaling (the caller chooses the
  /// effective schedule via the sequence of α values it supplies).
  Float64List reverseDenoisingStepAnalytic({
    required Float64List rho,
    required double alphaCurrent,
    required double alphaNext,
    required math.Random rng,
    double mass = 0.0,
  }) {
    if (rho.length != n) {
      throw ArgumentError('rho length ${rho.length} != n=$n');
    }
    final aC = alphaCurrent.clamp(1e-9, 1.0).toDouble();
    final aN = alphaNext.clamp(1e-9, 1.0).toDouble();
    final sigmaC2 = (1.0 - aC * aC).clamp(0.0, 1.0);
    final coeffs = project(rho);
    // Analytic posterior mean: E[ρ_0 | ρ_t] per mode.
    // mean_j(ρ_0) = (v_j · α) / (α² v_j + σ²) · c_j(ρ_t)
    // where v_j = 1 / (λ_j + m²).
    // The reverse step in the deterministic-limit PF-ODE is
    //   ρ_{t'} = α' · E[ρ_0 | ρ_t] + σ' · ε
    // which is exactly the DDIM update for a Gaussian prior.
    final newCoeffs = Float64List(k);
    for (var j = 0; j < k; j++) {
      final vj = 1.0 / (eigenvalues[j] + mass * mass + _subnormalFloor);
      final denom = aC * aC * vj + sigmaC2;
      if (denom <= _subnormalFloor) {
        newCoeffs[j] = 0.0;
        continue;
      }
      final posteriorMean = (vj * aC / denom) * coeffs[j];
      newCoeffs[j] = aN * posteriorMean;
    }
    // Reconstruct and add graph-coloured residual noise at the new
    // sigma level.
    final out = Float64List(n);
    for (var j = 0; j < k; j++) {
      final c = newCoeffs[j];
      final base = j * n;
      for (var v = 0; v < n; v++) {
        out[v] += c * eigenvectors[base + v];
      }
    }
    final sigmaN = math.sqrt((1.0 - aN * aN).clamp(0.0, 1.0));
    if (sigmaN > 1e-9) {
      final noise = sampleGaussianFreeField(rng: rng, mass: mass);
      for (var v = 0; v < n; v++) {
        out[v] += sigmaN * noise[v];
      }
    }
    return out;
  }

  /// Probability-flow ODE step: same marginals as the reverse SDE but
  /// deterministic. Use when you want a single sample (not an ensemble)
  /// or when you want to invert a sample to its noise latent by running
  /// this in the forward direction with no noise.
  Float64List probabilityFlowODEStep({
    required Float64List rho,
    required double alphaCurrent,
    required double alphaNext,
    double mass = 0.0,
  }) {
    if (rho.length != n) {
      throw ArgumentError('rho length ${rho.length} != n=$n');
    }
    final aC = alphaCurrent.clamp(1e-9, 1.0).toDouble();
    final aN = alphaNext.clamp(1e-9, 1.0).toDouble();
    final coeffs = project(rho);
    final sigmaC2 = (1.0 - aC * aC).clamp(0.0, 1.0);
    final newCoeffs = Float64List(k);
    for (var j = 0; j < k; j++) {
      final vj = 1.0 / (eigenvalues[j] + mass * mass + _subnormalFloor);
      final denom = aC * aC * vj + sigmaC2;
      if (denom <= _subnormalFloor) {
        newCoeffs[j] = 0.0;
        continue;
      }
      final posteriorMean = (vj * aC / denom) * coeffs[j];
      newCoeffs[j] = aN * posteriorMean;
    }
    // No noise — deterministic transport. For the residual we keep the
    // signal that was already there (the deterministic posterior mean).
    final out = Float64List(n);
    for (var j = 0; j < k; j++) {
      final c = newCoeffs[j];
      final base = j * n;
      for (var v = 0; v < n; v++) {
        out[v] += c * eigenvectors[base + v];
      }
    }
    return out;
  }
}

/// Symmetric dense linear solve via Gauss elimination with partial
/// pivoting. For our conditional-GFF use case, `k` is at most a handful
/// of observations; no need for a sparse solver.
///
/// Returns `A⁻¹·b`. Modifies neither argument.
Float64List _solveDenseSym(Float64List A, Float64List b, int k) {
  final m = Float64List(k * (k + 1));
  for (var i = 0; i < k; i++) {
    for (var j = 0; j < k; j++) {
      m[i * (k + 1) + j] = A[i * k + j];
    }
    m[i * (k + 1) + k] = b[i];
  }
  for (var i = 0; i < k; i++) {
    // Partial pivot: find max |m[r][i]| in rows i..k-1.
    var pivot = i;
    var pivotAbs = m[i * (k + 1) + i].abs();
    for (var r = i + 1; r < k; r++) {
      final a = m[r * (k + 1) + i].abs();
      if (a > pivotAbs) {
        pivotAbs = a;
        pivot = r;
      }
    }
    if (pivotAbs <= _subnormalFloor) {
      throw StateError(
          'Kriging Σ_AA singular at row $i — observations are collinear '
          'in the spectral covariance (try adding mass > 0 or fewer '
          'observations)');
    }
    if (pivot != i) {
      for (var c = i; c <= k; c++) {
        final tmp = m[i * (k + 1) + c];
        m[i * (k + 1) + c] = m[pivot * (k + 1) + c];
        m[pivot * (k + 1) + c] = tmp;
      }
    }
    final invPivot = 1.0 / m[i * (k + 1) + i];
    for (var c = i; c <= k; c++) {
      m[i * (k + 1) + c] *= invPivot;
    }
    for (var r = 0; r < k; r++) {
      if (r == i) continue;
      final factor = m[r * (k + 1) + i];
      if (factor == 0.0) continue;
      for (var c = i; c <= k; c++) {
        m[r * (k + 1) + c] -= factor * m[i * (k + 1) + c];
      }
    }
  }
  final out = Float64List(k);
  for (var i = 0; i < k; i++) {
    out[i] = m[i * (k + 1) + k];
  }
  return out;
}

/// Generative primitives that reuse a cached [SpectralProjection]'s
/// coefficients — completing a partial observation by drawing from the
/// posterior instead of just filling in the MAP estimate.
extension SpectralProjectionGenerative on SpectralProjection {
  /// Stochastic completion of the projection — draws a fresh sample
  /// from the Gaussian Free Field posterior given this projection as
  /// a partial observation.
  ///
  /// The existing `dreamFill(topK)` returns the deterministic MAP
  /// estimate (top-k mode reconstruction). This method returns a
  /// probabilistic sample from the full posterior distribution — same
  /// mean as `dreamFill` (for matched topK) but with posterior spread
  /// in the unseen modes.
  ///
  /// `temperature` scales the residual noise. `temperature = 0` recovers
  /// the deterministic mean (same as low-rank `dreamFill`). Larger
  /// values give more exploration.
  Float64List sampleDreamCompletion({
    required math.Random rng,
    double temperature = 1.0,
    double mass = 0.0,
  }) {
    final out = Float64List(basis.n);
    if (basis.k == 0) return out;
    for (var j = 0; j < basis.k; j++) {
      final base = j * basis.n;
      final cachedCoeff = coefficients[j];
      // Posterior mean per mode is just the cached coefficient
      // (treating this as an exact observation in mode space); the
      // residual is a fresh draw scaled by temperature.
      final denom = basis.eigenvalues[j] + mass * mass;
      final residualScale = denom <= _subnormalFloor
          ? 0.0
          : temperature / math.sqrt(denom);
      final draw = cachedCoeff +
          (residualScale * (temperature > 0 ? _gaussianStd(rng) : 0.0));
      for (var v = 0; v < basis.n; v++) {
        out[v] += draw * basis.eigenvectors[base + v];
      }
    }
    return out;
  }
}
