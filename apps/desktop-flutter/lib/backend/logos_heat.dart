// Heat-kernel observables — the Feynman-Kac path propagator, its Wick-
// rotated Schrödinger twin, heat-kernel signatures (Sun-Ovsjanikov-
// Guibas 2009), diffusion distance, emergent gravitational potential,
// and Debye correlation length. All pure functions of the Laplacian
// spectrum — no SpMV, O(k) per call (or O(k·n·m) for the bulk table).
//
// Taxonomy note: every method here is **Theorem-tight** (the spectral
// forms are equivalent-by-definition to their operator counterparts).
// The "gravitational potential" name is a **physically exact metaphor**
// — the quantity IS the Wentzell-Freidlin effective action in the
// long-β limit, which reduces to the classical action along the
// least-action path, which IS a gravitational potential in the sense
// of general relativity on a manifold whose metric is induced by the
// Laplacian spectrum. The theorem is real; only the biographical
// connection to Einstein's equations requires a Wick rotation and a
// change of variables to make exact.

part of 'logos_core.dart';

/// Heat-kernel-derived observables on a cached [SpectralBasis].
///
/// These methods package the Feynman-Kac path integral (= heat kernel =
/// matrix exponential of the graph Laplacian) into named observables:
/// propagator, gravitational potential, correlation length, HKS.
extension SpectralHeat on SpectralBasis {
  /// Diffusion distance between two graph nodes at scale `t`:
  /// `d_t²(x, y) = ||p_t(x, ·) − p_t(y, ·)||² = Σⱼ e^{−2tλⱼ}·(uⱼ[x] − uⱼ[y])²`.
  ///
  /// **Reading**: a true metric on the graph induced by the heat
  /// kernel — small `t` recovers the graph's local geometry, large
  /// `t` recovers macroscopic cluster structure. Unlike shortest-path
  /// distance, it averages over *all* paths weighted by their thermal
  /// likelihood, so two nodes connected by many medium-strength paths
  /// are closer than two nodes connected by a single strong path.
  /// Use this for "how close is file X to file Y in the codebase's
  /// natural geometry?".
  double diffusionDistance(int srcId, int dstId, double t) {
    if (srcId == dstId) return 0.0;
    var sumSq = 0.0;
    for (var j = 0; j < k; j++) {
      final base = j * n;
      final delta = eigenvectors[base + srcId] - eigenvectors[base + dstId];
      sumSq += math.exp(-2.0 * t * eigenvalues[j]) * delta * delta;
    }
    return math.sqrt(sumSq);
  }

  /// **Feynman-Kac path propagator** from node [source] to node
  /// [target] over "time" [tau]. Returns the heat kernel matrix
  /// element `K(a, b, τ) = [exp(−τL)]_{a,b}`.
  ///
  /// ## What it represents
  ///
  /// The propagator is the **sum over all paths** from [source] to
  /// [target] of length ∝ τ, weighted by `exp(−S[γ]/β)` where
  /// S is the Dirichlet action and β = τ. This is Feynman-Kac made
  /// literal: the heat kernel IS the path integral of the
  /// Schrödinger operator Wick-rotated to imaginary time.
  ///
  ///     K(a, b, τ) = Σ_{paths γ: a → b} exp(−½ ∫|γ̇|² dt)
  ///                = Σⱼ uⱼ(a) · uⱼ(b) · exp(−τλⱼ)   ← spectral form
  ///
  /// The two forms are equivalent by the heat kernel's eigenvector
  /// expansion. The path-integral form makes the quantum-classical
  /// correspondence visible: **classical trajectories = stationary
  /// points of S** dominate when the gap is large (low temperature);
  /// **all paths contribute** when the gap is small (high
  /// temperature).
  ///
  /// ## Theorems this respects
  ///
  /// * **Chapman-Kolmogorov composition**:
  ///   `K(a, c, τ₁ + τ₂) = Σ_b K(a, b, τ₁) · K(b, c, τ₂)` — the
  ///   semigroup property. Every propagator is a sum over
  ///   intermediate path points.
  /// * **Symmetry**: `K(a, b, τ) = K(b, a, τ)` (graph Laplacian
  ///   is self-adjoint, U is orthogonal).
  /// * **Diagonal = HKS**: `K(v, v, τ) = heatKernelSignature(v, τ)`.
  /// * **Trace = heatTrace**: `Σ_v K(v, v, τ) = heatTrace(τ)`.
  /// * **Wick rotation**: [pathPropagatorQuantum] is the analytic
  ///   continuation `τ → iτ` of this propagator.
  ///
  /// Cost: `O(k)`. The whole kernel matrix element computed from
  /// the spectral decomposition.
  double pathPropagator(int source, int target, double tau) {
    if (source < 0 || source >= n || target < 0 || target >= n) {
      throw RangeError(
          'pathPropagator: node indices out of range [0, $n)');
    }
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      final ua = eigenvectors[j * n + source];
      final ub = eigenvectors[j * n + target];
      s += ua * ub * math.exp(-tau * eigenvalues[j]);
    }
    return s;
  }

  /// **Theorem-tight** (the value IS the Wentzell-Freidlin effective
  /// action). **Analogy** (the "gravity" naming): the potential has the
  /// right shape and sign for an emergent gravitational interaction
  /// under Wick rotation, but the connection to Einstein's equations
  /// requires a further change of variables. Use the value freely;
  /// treat the "gravity" intuition as pedagogy.
  ///
  /// **Emergent gravitational potential** between two files — the
  /// Wentzell-Freidlin large-deviations effective action for a
  /// heat-kernel path from [source] to [target] at inverse temperature
  /// [beta]:
  ///
  ///     V(a, b, β) = −(1/β) · log K(a, b, β)
  ///
  /// In the long-β (low-temperature) limit this is the classical
  /// action of the least-action path from $a$ to $b$. Files with a
  /// direct coupling edge have a SHALLOWER potential well (higher
  /// heat-kernel amplitude ⇒ less negative log); files separated by
  /// graph distance have DEEPER wells (smaller amplitude ⇒ more
  /// negative log).
  ///
  /// **Claim**: well-coupled files are GRAVITATIONALLY BOUND under
  /// this potential. Refactors that tighten coupling literally
  /// lower the potential between the files. Decoupling raises it.
  /// `ricciFlowStep` IS motion under this emergent gravity.
  ///
  /// Returns `double.infinity` when the two nodes are in disconnected
  /// components (the heat kernel is exactly zero, log diverges).
  double gravitationalPotential(int source, int target, double beta) {
    final k = pathPropagator(source, target, beta);
    if (k <= 1e-300) return double.infinity;
    return -math.log(k) / beta;
  }

  /// **Debye correlation length** — the characteristic distance over
  /// which spatial fluctuations in the repo's state decay.
  ///
  ///     ξ = 1 / √(λ₁)
  ///
  /// where λ₁ is the normalised-Laplacian spectral gap. A low-gap
  /// repo (strongly coupled) has a LONG correlation length: a
  /// perturbation at one file ripples across many files before
  /// decaying. A high-gap repo (well-mixed, expander-like) has a
  /// SHORT correlation length: perturbations damp quickly.
  ///
  /// Direct transposition of Debye screening in condensed matter:
  /// at low temperature the correlation length diverges (approaching
  /// critical behaviour); at high temperature it saturates at ~1
  /// (nearest-neighbour only).
  ///
  /// Returns `double.infinity` on disconnected graphs (zero gap).
  double get correlationLength {
    final gap = spectralGap;
    if (gap <= _subnormalFloor) return double.infinity;
    return 1.0 / math.sqrt(gap);
  }

  /// Complex Wick-rotated propagator: the Schrödinger kernel
  /// `K_quantum(a, b, τ) = Σⱼ uⱼ(a)·uⱼ(b)·exp(−iτλⱼ)`.
  ///
  /// The same spectral sum as [pathPropagator] but with imaginary
  /// time: real decay → phase rotation. Returns a record with
  /// `real` and `imaginary` components.
  ///
  /// The quantum-classical correspondence: analytic continuation
  /// `τ → iτ` takes the real heat propagator to the complex
  /// Schrödinger propagator. Same eigenbasis, same eigenvalues,
  /// different exponent. This is the **Wick rotation** that lets
  /// quantum mechanics and statistical mechanics be the same math
  /// on different sides of the complex plane.
  ({double real, double imaginary}) pathPropagatorQuantum(
    int source,
    int target,
    double tau,
  ) {
    if (source < 0 || source >= n || target < 0 || target >= n) {
      throw RangeError(
          'pathPropagatorQuantum: node indices out of range [0, $n)');
    }
    var sRe = 0.0;
    var sIm = 0.0;
    for (var j = 0; j < k; j++) {
      final ua = eigenvectors[j * n + source];
      final ub = eigenvectors[j * n + target];
      final uaUb = ua * ub;
      final phase = tau * eigenvalues[j];
      sRe += uaUb * math.cos(phase);
      sIm -= uaUb * math.sin(phase);
    }
    return (real: sRe, imaginary: sIm);
  }

  /// Heat-kernel signature at node [i] evaluated at scale [t].
  /// Returns `0.0` when `i` is out of range or the basis is empty.
  /// `O(k)` per call.
  ///
  /// Classical shape-analysis observable (Sun-Ovsjanikov-Guibas 2009).
  /// Each node is characterised by the heat RETAINED at itself over
  /// time. A spectrum-preserving map between graphs preserves HKS, so
  /// two isospectral-equivalent nodes have the same profile.
  double heatKernelSignature(int i, double t) {
    if (i < 0 || i >= n || k == 0) return 0.0;
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      final u = eigenvectors[j * n + i];
      s += math.exp(-t * eigenvalues[j]) * u * u;
    }
    return s;
  }

  /// Per-node HKS profile at every element of [times] — a length-m
  /// feature vector for node [i]. Compact "structural fingerprint"
  /// of the node across multiple scales.
  ///
  /// Two nodes with very similar profiles are multi-scale structural
  /// twins; two nodes with different profiles occupy different
  /// structural niches. Clustering nodes by this profile recovers
  /// a finer community structure than any single-t heat-diagonal.
  Float64List heatKernelProfile(int i, List<double> times) {
    final out = Float64List(times.length);
    if (i < 0 || i >= n || k == 0) return out;
    for (var m = 0; m < times.length; m++) {
      final t = times[m];
      var s = 0.0;
      for (var j = 0; j < k; j++) {
        final u = eigenvectors[j * n + i];
        s += math.exp(-t * eigenvalues[j]) * u * u;
      }
      out[m] = s;
    }
    return out;
  }

  /// L2 distance between two nodes' HKS profiles — a structural-role
  /// distance. Zero iff the two nodes have identical multi-scale
  /// heat signatures (they occupy equivalent roles in the graph's
  /// structure).
  ///
  /// **Reading**: two files with `hksDistance = 0` are indistinguishable
  /// by any heat-diffusion observable at the sampled scales. Two files
  /// with a large distance occupy structurally distinct niches.
  ///
  /// Paired with [heatKernelProfileTable] + k-means, this gives a
  /// structural-role clustering complementary to the community
  /// clustering from `spectralCommunityLabels`. Communities group
  /// nodes by eigenvector-space proximity; HKS-roles group nodes by
  /// how heat retains at each scale — two different lenses on the
  /// same underlying graph.
  double hksDistance(int a, int b, List<double> times) {
    if (a == b) return 0.0;
    final pa = heatKernelProfile(a, times);
    final pb = heatKernelProfile(b, times);
    var s = 0.0;
    for (var m = 0; m < times.length; m++) {
      final d = pa[m] - pb[m];
      s += d * d;
    }
    return math.sqrt(s);
  }

  /// Bulk variant — row-major `n × times.length` table of per-node
  /// HKS profiles. One pass over modes, accumulating into every node
  /// and every time simultaneously; `O(k · n · m)` total, better
  /// cache locality than calling [heatKernelProfile] n times.
  ///
  /// Invariant: `Σᵢ HKS(i, t) = Σⱼ e^{-tλⱼ} = heatTrace(t)` —
  /// the per-node diagonals sum to the global heat trace, because
  /// eigenvectors are orthonormal (`Σᵢ |uⱼ[i]|² = 1`).
  Float64List heatKernelProfileTable(List<double> times) {
    final m = times.length;
    final out = Float64List(n * m);
    if (n == 0 || k == 0 || m == 0) return out;
    for (var j = 0; j < k; j++) {
      final base = j * n;
      final lambda = eigenvalues[j];
      for (var tIdx = 0; tIdx < m; tIdx++) {
        final decay = math.exp(-times[tIdx] * lambda);
        for (var i = 0; i < n; i++) {
          final u = eigenvectors[base + i];
          out[i * m + tIdx] += decay * u * u;
        }
      }
    }
    return out;
  }
}
