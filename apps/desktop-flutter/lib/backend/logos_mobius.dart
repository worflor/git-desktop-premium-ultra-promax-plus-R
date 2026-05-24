// MÖBIUS INCIDENCE ALGEBRA — Boolean lattice transforms for the Logos engine.
//
// Three readings of one algebraic structure:
//
//   Zeta transform    ζ :  f(S) → Z(S) = Σ_{T⊆S} f(T)
//   Möbius inversion  μ :  Z(S) → f(S) = Σ_{T⊆S} (-1)^{|S\T|} Z(T)
//   Walsh-Hadamard    W :  f(S) ↔ f̂(S) = Σ_T (-1)^{|S∩T|} f(T)
//
// On the Boolean lattice 2^[n], these are O(n·2^n) butterfly transforms.
// On n=8 (the Filament address space) that's 2048 multiply-adds.
// On n=16 (Kizuna's product space) that's ~1M ops.
//
// The deep structural fact: Walsh-Hadamard diagonalizes the hypercube
// Laplacian L_cube. Its eigenvectors are Walsh functions W_S(T) =
// (-1)^{|S∩T|}, with eigenvalue λ_S = 2|S|/n. So on the Boolean
// lattice, the heat kernel is closed-form:
//
//   (exp(-t·L_cube)·f)(T) = Σ_S f̂(S)·exp(-2t|S|/n)·W_S(T)
//
// = inverse-WHT of { exp(-2t|S|/n) · f̂(S) }.
//
// The Chebyshev expansion on arbitrary file graphs CONVERGES to this
// closed-form when restricted through the spectral fingerprint map
// to the cube. That is the mathematical relationship between the
// two diffusion paths — one is exact, the other is polynomial
// approximation on a richer topology.

part of 'logos_core.dart';

// ── Popcount ────────────────────────────────────────────────────────

int _popcount(int x) {
  var v = x;
  v = v - ((v >> 1) & 0x55555555);
  v = (v & 0x33333333) + ((v >> 2) & 0x33333333);
  return ((v + (v >> 4) & 0x0F0F0F0F) * 0x01010101) >> 24;
}

// ── Core transforms on 2^[n] ───────────────────────────────────────
//
// All three transforms share the same butterfly structure. Each bit
// position b induces a partition of 2^[n] into pairs (S, S∪{b}) where
// b ∉ S. The sweep over all n bit positions visits every pair exactly
// once. The only difference is the update rule:
//
//   Zeta:  f[S∪{b}] += f[S]           (accumulate upward)
//   Möbius: f[S∪{b}] -= f[S]          (subtract downward)
//   WHT:   (f[S], f[S∪{b}]) = (f[S] + f[S∪{b}], f[S] - f[S∪{b}])
//
// In-place, O(n·2^n), no allocation.

/// Zeta transform (subset sum) on 2^[n]. In-place.
/// After: f[S] = Σ_{T⊆S} f_original[T].
void mobiusZeta(Float64List f, int n) {
  final size = 1 << n;
  assert(f.length >= size);
  for (var b = 0; b < n; b++) {
    final mask = 1 << b;
    for (var s = 0; s < size; s++) {
      if (s & mask != 0) {
        f[s] += f[s ^ mask];
      }
    }
  }
}

/// Möbius inversion on 2^[n]. In-place. Exact inverse of [mobiusZeta].
/// After: f[S] = the value with all sub-subset contributions removed.
void mobiusInvert(Float64List f, int n) {
  final size = 1 << n;
  assert(f.length >= size);
  for (var b = 0; b < n; b++) {
    final mask = 1 << b;
    for (var s = 0; s < size; s++) {
      if (s & mask != 0) {
        f[s] -= f[s ^ mask];
      }
    }
  }
}

/// Walsh-Hadamard transform on 2^[n]. In-place. Self-inverse up to
/// scaling by 2^n: WHT(WHT(f)) = 2^n · f.
///
/// After: f̂[S] = Σ_T (-1)^{|S∩T|} f[T].
///
/// Each coefficient f̂[S] is the irreducible |S|-way interaction
/// between exactly the axes in S. Single-axis coefficients (|S|=1)
/// are marginal effects. Pair coefficients (|S|=2) are pairwise
/// interactions net of marginals. And so on through all orders.
void walshHadamard(Float64List f, int n) {
  final size = 1 << n;
  assert(f.length >= size);
  for (var b = 0; b < n; b++) {
    final mask = 1 << b;
    for (var s = 0; s < size; s++) {
      if (s & mask != 0) continue;
      final lo = f[s];
      final hi = f[s | mask];
      f[s] = lo + hi;
      f[s | mask] = lo - hi;
    }
  }
}

/// Inverse Walsh-Hadamard: WHT followed by scaling by 1/2^n.
void walshHadamardInverse(Float64List f, int n) {
  walshHadamard(f, n);
  final inv = 1.0 / (1 << n);
  final size = 1 << n;
  for (var i = 0; i < size; i++) {
    f[i] *= inv;
  }
}

// ── Superset-sum (dual zeta) ────────────────────────────────────────

/// Superset-sum transform: f[S] → Σ_{T⊇S} f[T]. The dual of [mobiusZeta].
void mobiusZetaSuper(Float64List f, int n) {
  final size = 1 << n;
  assert(f.length >= size);
  for (var b = 0; b < n; b++) {
    final mask = 1 << b;
    for (var s = 0; s < size; s++) {
      if (s & mask == 0) {
        f[s] += f[s | mask];
      }
    }
  }
}

/// Superset Möbius inversion: exact inverse of [mobiusZetaSuper].
void mobiusInvertSuper(Float64List f, int n) {
  final size = 1 << n;
  assert(f.length >= size);
  for (var b = 0; b < n; b++) {
    final mask = 1 << b;
    for (var s = 0; s < size; s++) {
      if (s & mask == 0) {
        f[s] -= f[s | mask];
      }
    }
  }
}

// ── Graded structure ────────────────────────────────────────────────

/// Interaction order of Walsh coefficient S = popcount(S).
/// Order 0 = DC (grand mean). Order 1 = marginal effects.
/// Order 2 = pairwise interactions. Etc.
int walshOrder(int s) => _popcount(s);

/// Extract Walsh coefficients up to a given interaction order.
/// Returns a sparse list of (address, coefficient) pairs sorted by
/// descending |coefficient|. O(2^n) scan + sort.
List<(int, double)> walshDominant(Float64List spectrum, int n,
    {int maxOrder = 8, int maxCount = 64}) {
  final size = 1 << n;
  final hits = <(int, double)>[];
  for (var s = 0; s < size; s++) {
    if (_popcount(s) > maxOrder) continue;
    final v = spectrum[s];
    if (v.abs() < 1e-15) continue;
    hits.add((s, v));
  }
  hits.sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));
  if (hits.length > maxCount) return hits.sublist(0, maxCount);
  return hits;
}

/// Partition a Walsh spectrum by interaction order: returns a list
/// where element [k] is the sum of squared coefficients at order k.
/// This is the "energy" at each interaction order — a graded power
/// spectrum. On a factored model (independent axes), all energy is
/// at order 1. Multi-axis interactions push energy to higher orders.
Float64List walshOrderSpectrum(Float64List spectrum, int n) {
  final clampedN = n > 30 ? 30 : n;
  final size = 1 << clampedN;
  final safeSize = size > spectrum.length ? spectrum.length : size;
  final energy = Float64List(clampedN + 1);
  for (var s = 0; s < safeSize; s++) {
    final v = spectrum[s];
    final order = _popcount(s);
    if (order <= clampedN) energy[order] += v * v;
  }
  return energy;
}

// ── Closed-form heat kernel on the Boolean hypercube ────────────────
//
// On Q_n, the normalised Laplacian has eigenvalue λ_S = 2|S|/n for
// Walsh mode S. The heat kernel at temperature t damps each mode by
// exp(-t·λ_S) = exp(-2t|S|/n). High-order interactions decay faster.
//
// This is ANALYTIC — no Chebyshev needed. The Chebyshev expansion on
// arbitrary graphs converges to this when restricted to the cube.

/// Apply the exact heat kernel on Q_n to a function in Walsh space.
/// In-place: f̂[S] *= exp(-2t|S|/n). Call [walshHadamardInverse]
/// after to return to real space.
void cubeHeatDamp(Float64List walshSpectrum, int n, double t) {
  if (t <= 0) return;
  final size = 1 << n;
  final inv = 2.0 * t / n;
  for (var s = 0; s < size; s++) {
    walshSpectrum[s] *= math.exp(-inv * _popcount(s));
  }
}

/// Full closed-form heat kernel on Q_n: real-space input → real-space
/// output. Allocates a working copy.
///
///   result[T] = Σ_S f̂(S) · exp(-2t|S|/n) · W_S(T) / 2^n
///
/// Cost: O(n·2^n) for WHT + O(2^n) for damping + O(n·2^n) for inverse.
Float64List cubeHeatKernel(Float64List f, int n, double t) {
  final size = 1 << n;
  final work = Float64List(size);
  for (var i = 0; i < size; i++) {
    work[i] = f[i];
  }
  walshHadamard(work, n);
  cubeHeatDamp(work, n, t);
  walshHadamardInverse(work, n);
  return work;
}

// ── Interaction decomposition ───────────────────────────────────────

/// Decompose a function f on 2^[n] into its irreducible interaction
/// terms. Returns the Möbius-inverted form: result[S] is the part of
/// f(S) that is NOT explained by any strict sub-address.
///
/// Equivalent to: copy f, apply [mobiusInvert]. But exposed as a
/// non-destructive call that returns a new array.
Float64List mobiusDecompose(Float64List f, int n) {
  final size = 1 << n;
  final out = Float64List(size);
  for (var i = 0; i < size; i++) {
    out[i] = f[i];
  }
  mobiusInvert(out, n);
  return out;
}

/// The cumulative view: for each address S, the total signal from all
/// sub-roles of S. Non-destructive.
Float64List zetaCumulative(Float64List f, int n) {
  final size = 1 << n;
  final out = Float64List(size);
  for (var i = 0; i < size; i++) {
    out[i] = f[i];
  }
  mobiusZeta(out, n);
  return out;
}

// ── Product-space factored WHT ──────────────────────────────────────
//
// For the Kizuna 16-bit address space = 2^[8] × 2^[8], the WHT
// factors as WHT_8 ⊗ WHT_8. This is cheaper than a monolithic WHT_16
// when only one factor changes (e.g. re-scoring with a new commit
// fingerprint table while the file fingerprints are cached).

/// Factored WHT on a product lattice 2^[a] × 2^[b] stored as a flat
/// array of length 2^(a+b) with layout f[(x << b) | y].
/// Applies WHT_a along the first factor, then WHT_b along the second.
/// In-place, total cost O((a+b)·2^(a+b)).
void walshHadamardProduct(Float64List f, int a, int b) {
  final sizeB = 1 << b;
  final sizeA = 1 << a;
  final total = sizeA * sizeB;
  assert(f.length >= total);
  // WHT along factor A: for each fixed y, transform f[* << b | y]
  // with stride sizeB.
  for (var bit = 0; bit < a; bit++) {
    final mask = 1 << bit;
    for (var x = 0; x < sizeA; x++) {
      if (x & mask != 0) continue;
      final x0 = x * sizeB;
      final x1 = (x | mask) * sizeB;
      for (var y = 0; y < sizeB; y++) {
        final lo = f[x0 + y];
        final hi = f[x1 + y];
        f[x0 + y] = lo + hi;
        f[x1 + y] = lo - hi;
      }
    }
  }
  // WHT along factor B: for each fixed x, transform f[x << b | *]
  // in-place on a contiguous block.
  for (var x = 0; x < sizeA; x++) {
    final base = x * sizeB;
    for (var bit = 0; bit < b; bit++) {
      final mask = 1 << bit;
      for (var y = 0; y < sizeB; y++) {
        if (y & mask != 0) continue;
        final lo = f[base + y];
        final hi = f[base + (y | mask)];
        f[base + y] = lo + hi;
        f[base + (y | mask)] = lo - hi;
      }
    }
  }
}

/// Inverse of [walshHadamardProduct]. Self-inverse up to 2^(a+b).
void walshHadamardProductInverse(Float64List f, int a, int b) {
  walshHadamardProduct(f, a, b);
  final inv = 1.0 / (1 << (a + b));
  final total = (1 << a) * (1 << b);
  for (var i = 0; i < total; i++) {
    f[i] *= inv;
  }
}

// ── Graded projection (Kizuna-compatible) ───────────────────────────
//
// Extract Walsh coefficients at specific interaction orders from a
// product lattice. Kizuna's 25 masks are the order-1 marginals
// (L0..L7, U0..U7) plus the diagonal order-2 terms (X0..X7) plus
// the global parity — a specific graded projection.

/// Extract the graded Walsh spectrum from a product 2^[a] × 2^[b]
/// in Walsh space. Returns coefficients partitioned by:
///   - lower marginals (order 1 in factor B, order 0 in factor A)
///   - upper marginals (order 0 in factor B, order 1 in factor A)
///   - diagonal cross-terms (order 1 in both factors, matched bit)
///   - global parity (all bits)
///
/// This is the algebraically-motivated generalization of the 25
/// Kizuna masks. When a=b=8, the output is compatible with
/// [KizunaBond25D].
({
  Float64List lower,
  Float64List upper,
  Float64List cross,
  double global,
}) gradedProjectProduct(Float64List walshSpectrum, int a, int b) {
  final sizeB = 1 << b;
  final lower = Float64List(b);
  final upper = Float64List(a);
  final crossDim = math.min(a, b);
  final cross = Float64List(crossDim);

  // Lower marginals: (factorA = 0, factorB = single bit)
  for (var i = 0; i < b; i++) {
    lower[i] = walshSpectrum[1 << i];
  }
  // Upper marginals: (factorA = single bit, factorB = 0)
  for (var i = 0; i < a; i++) {
    upper[i] = walshSpectrum[(1 << i) * sizeB];
  }
  // Diagonal cross-terms: (factorA = bit i, factorB = bit i)
  for (var i = 0; i < crossDim; i++) {
    cross[i] = walshSpectrum[((1 << i) * sizeB) | (1 << i)];
  }
  // Global parity: all bits in both factors
  final globalAddr = ((1 << a) - 1) * sizeB + ((1 << b) - 1);
  final global = walshSpectrum[globalAddr];

  return (lower: lower, upper: upper, cross: cross, global: global);
}

// ── Intertwining deviation ──────────────────────────────────────────
//
// Given a restriction map φ: V_graph → 2^[n] (the spectral fingerprint),
// measure how well the graph Laplacian intertwines with the cube
// Laplacian through φ.
//
// The deviation Δ = ||R·L_graph·P - L_cube|| in Walsh space tells you
// which interaction modes the graph topology distorts relative to the
// ideal hypercube structure.

/// Compute the intertwining deviation between a graph's diffusion and
/// the hypercube's exact diffusion at temperature [t].
///
/// Process:
/// 1. Diffuse a probe function on the graph via Chebyshev, restrict
///    to the cube via the fingerprint map.
/// 2. Diffuse the same probe on the cube via closed-form WHT.
/// 3. Return the Walsh-space residual (per mode).
///
/// The probe is the uniform function ρ=1/n — diffusion of uniform
/// mass reveals the graph's structural deviation from the cube because
/// on the cube exp(-tL)·uniform = uniform (the DC mode is preserved).
/// Any deviation from uniform in the restricted result IS the
/// intertwining error.
Float64List intertwiningDeviation({
  required CsrGraph graph,
  required Uint8List fingerprints,
  required int n,
  required double t,
  int chebyshevK = kDefaultChebyshevK,
}) {
  final nGraph = graph.n;
  final cubeSize = 1 << n;
  if (nGraph == 0) return Float64List(cubeSize);

  // Count fibers: how many graph nodes map to each cube address.
  final fiberCount = Float64List(cubeSize);
  for (var i = 0; i < nGraph; i++) {
    fiberCount[fingerprints[i]]++;
  }

  // Probe: uniform mass on the graph.
  final rho = Float64List(nGraph);
  final inv = 1.0 / nGraph;
  for (var i = 0; i < nGraph; i++) {
    rho[i] = inv;
  }

  // Path 1: Chebyshev diffusion on graph, then restrict to cube.
  final phiGraph = Float64List(nGraph);
  chebyshevDiffuse(graph: graph, rho: rho, phi: phiGraph, t: t, K: chebyshevK);
  final restricted = Float64List(cubeSize);
  for (var i = 0; i < nGraph; i++) {
    restricted[fingerprints[i]] += phiGraph[i];
  }
  // Normalize by fiber size to get the average per cube cell.
  for (var a = 0; a < cubeSize; a++) {
    if (fiberCount[a] > 0) restricted[a] /= fiberCount[a];
  }

  // Path 2: exact diffusion on cube from the restricted initial mass.
  final cubeMass = Float64List(cubeSize);
  for (var a = 0; a < cubeSize; a++) {
    cubeMass[a] = fiberCount[a] > 0 ? inv * fiberCount[a] : 0.0;
  }
  // Normalize cube mass.
  var cubeTot = 0.0;
  for (var a = 0; a < cubeSize; a++) {
    cubeTot += cubeMass[a];
  }
  if (cubeTot > 0) {
    final ci = 1.0 / cubeTot;
    for (var a = 0; a < cubeSize; a++) {
      cubeMass[a] *= ci;
    }
  }
  final cubeResult = cubeHeatKernel(cubeMass, n, t);

  // Residual in real space, then transform to Walsh space.
  final residual = Float64List(cubeSize);
  for (var a = 0; a < cubeSize; a++) {
    residual[a] = restricted[a] - cubeResult[a];
  }
  walshHadamard(residual, n);
  return residual;
}
