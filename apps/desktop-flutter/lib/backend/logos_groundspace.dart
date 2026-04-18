// Ground-space primitives on [SpectralBasis].
//
// The normalised graph Laplacian `L_sym` has a kernel of dimension
// equal to the number of connected components — the "ground state"
// subspace. Every physical quantity the engine computes implicitly
// decomposes as
//
//     observable(ρ) = observable_ground(ρ) + observable_excited(ρ)
//
// where the ground part is whatever the repo's connectivity structure
// forces. For most analysis we care about the EXCITED part — what's
// happening *on top of* the repo existing as a whole.
//
// Before this module existed every caller that cared about this
// separation re-invented an `eigenvalues[j] <= 1e-10` check with a
// locally-defined threshold. Five overnight modules had the pattern.
// This file centralises:
//
//   * [kGroundStateEps] — the one threshold, pinned.
//   * `basis.kernelDim` — count of zero modes.
//   * `basis.nonZeroIndices` — iterable of excited-mode indices.
//   * `basis.nonZeroEigenvalues` — the excited spectrum as a list.
//   * `basis.projectOutGround(ρ)` — zero out ρ's ground component.
//   * `basis.groundComponent(ρ)` — the ground-state-only part of ρ.
//
// None of these are new math; they're the missing vocabulary for a
// pattern already present in every observable. Consumers migrate
// piecemeal.
//
// Taxonomy: **Theorem-tight** for the projections (exact on the
// resolved basis); **Operational** for the threshold itself (the
// eigenvalue-zero detection cutoff is a numerical choice).

part of 'logos_core.dart';

/// Pinned threshold for zero-eigenvalue detection. Any eigenvalue at
/// or below this value is treated as a ground-state (kernel) mode.
///
/// Why `1e-10`: Lanczos residuals on a well-conditioned normalised
/// Laplacian sit around `1e-13` to `1e-12` for the handful of nodes
/// that seed the Krylov basis. `1e-10` sits four orders above that
/// noise floor — no false positives — while staying well below any
/// genuine non-zero eigenvalue produced by real graph structure
/// (smallest non-zero on a 2-node graph with unit weight is `1`).
const double kGroundStateEps = 1e-10;

/// Ground-space operations on a [SpectralBasis]. Every method here
/// assumes `eigenvalues` is sorted ascending (which the Lanczos
/// solver guarantees).
extension SpectralGroundSpace on SpectralBasis {
  /// Number of eigenvalues at or below [kGroundStateEps]. Equals the
  /// dimension of the kernel of `L_sym`, which on a connected graph
  /// is 1 and in general equals the number of connected components
  /// *that the current Lanczos run successfully resolved*.
  ///
  /// **Caveat**: a single-pass Lanczos with a random start vector
  /// may under-resolve the ground-state multiplicity on highly-
  /// disconnected graphs. For topologically-exact β₀ counting use
  /// union-find on the graph's edges instead of reading it off the
  /// basis — see `CsrGraph.fragmentationCurve`.
  int get kernelDim {
    var c = 0;
    for (var j = 0; j < k; j++) {
      if (eigenvalues[j] <= kGroundStateEps) c++;
      else break; // sorted ascending — first non-zero ends the run
    }
    return c;
  }

  /// Index of the first excited (non-zero) mode. Equal to [kernelDim]
  /// on a sorted-ascending spectrum. `k` when the spectrum is
  /// entirely ground-state (degenerate).
  int get firstExcitedIndex => kernelDim;

  /// True when every resolved eigenvalue is a zero mode — the basis
  /// captures no excited structure. Typical on edge-free graphs.
  bool get isGroundOnly => kernelDim == k;

  /// Excited spectrum: the eigenvalues strictly above the ground
  /// threshold. Ownership: the returned list is a COPY, not a view —
  /// safe for downstream sorting / rescaling.
  Float64List get nonZeroEigenvalues {
    final start = firstExcitedIndex;
    final out = Float64List(k - start);
    for (var j = 0; j < out.length; j++) {
      out[j] = eigenvalues[start + j];
    }
    return out;
  }

  /// Range of excited-mode indices `[firstExcitedIndex, k)`, suitable
  /// for direct iteration. Returned as a typed iterable so callers
  /// can e.g. `for (final j in basis.nonZeroIndices) { ... }`.
  Iterable<int> get nonZeroIndices sync* {
    final start = firstExcitedIndex;
    for (var j = start; j < k; j++) yield j;
  }

  /// Return a new vector equal to `ρ` with its projection onto the
  /// ground-state subspace zeroed out. On a connected graph the
  /// ground state is the constant function `1/√n`, so this amounts
  /// to subtracting off the mean. On a disconnected graph each
  /// component's constant mode is projected out independently.
  ///
  /// The result satisfies `⟨u₀ᵢ, ρ_excited⟩ = 0` for every resolved
  /// ground-state eigenvector `u₀ᵢ` — i.e. it lives entirely in the
  /// excited subspace.
  ///
  /// **Theorem-tight** — exact projection on the resolved basis.
  Float64List projectOutGround(Float64List rho) {
    assert(rho.length == n,
        'rho length ${rho.length} must equal basis n $n');
    final out = Float64List(n);
    out.setAll(0, rho);
    final kernel = kernelDim;
    for (var j = 0; j < kernel; j++) {
      // Project rho onto u_j and subtract.
      var dot = 0.0;
      final base = j * n;
      for (var i = 0; i < n; i++) {
        dot += eigenvectors[base + i] * rho[i];
      }
      for (var i = 0; i < n; i++) {
        out[i] -= dot * eigenvectors[base + i];
      }
    }
    return out;
  }

  /// Inverse companion to [projectOutGround]: return the ground-state
  /// projection alone. Invariant: `rho == projectOutGround(rho) +
  /// groundComponent(rho)` up to floating-point roundoff.
  Float64List groundComponent(Float64List rho) {
    assert(rho.length == n,
        'rho length ${rho.length} must equal basis n $n');
    final out = Float64List(n);
    final kernel = kernelDim;
    for (var j = 0; j < kernel; j++) {
      var dot = 0.0;
      final base = j * n;
      for (var i = 0; i < n; i++) {
        dot += eigenvectors[base + i] * rho[i];
      }
      for (var i = 0; i < n; i++) {
        out[i] += dot * eigenvectors[base + i];
      }
    }
    return out;
  }

  /// Helmholtz-style excited partition function: the heat trace
  /// with the ground modes removed.
  ///
  ///     Z_exc(t) = Σ_{λⱼ > 0} e^{−t·λⱼ}  =  heatTrace(t) − kernelDim.
  ///
  /// At large `t` this collapses to 0 (all excited modes dissipate);
  /// the plateau `heatTrace(t) - Z_exc(t)` is the repo's topological
  /// "ground mass". Exposed here because every thermodynamic
  /// observable that wants to measure excited-mode relaxation needs
  /// this decomposition.
  double excitedHeatTrace(double t) {
    var s = 0.0;
    final start = firstExcitedIndex;
    for (var j = start; j < k; j++) {
      s += math.exp(-t * eigenvalues[j]);
    }
    return s;
  }
}
