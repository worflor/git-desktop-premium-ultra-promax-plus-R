// SPECTRAL SPACETIME — the file graph tensored with the commit graph.
//
// Our engine diffuses mass over files (spatial graph). OG Logos
// diffuses mass over byte-time (temporal stream). The codebase is both
// at once: a file lives in architectural space AND in commit-history
// time. This module forms the joint eigenbasis — the spectral
// decomposition of `L_joint = L_file ⊗ I + I ⊗ L_time` — which is
// exactly the Kronecker-sum structure that lets us reuse the two
// separate eigenbases without ever materialising the joint Laplacian.
//
// Key algebraic identity (Kronecker-sum eigendecomposition):
//   If L_file·uᵢ = λᵢ·uᵢ and L_time·vⱼ = μⱼ·vⱼ,
//   then L_joint·(uᵢ⊗vⱼ) = (λᵢ + μⱼ)·(uᵢ⊗vⱼ).
//
// Meaning: the joint basis is simply the outer product of the two
// per-level bases, and its spectrum is the pairwise sum. We never
// form an `(n_file · n_time) × (n_file · n_time)` matrix. Every joint
// observable factors into independent space and time computations
// stitched with a small grid of (i, j) eigenvalue pairs.
//
// This is the bridge OG Logos's LUMEN-LOGOS fusion was pointing at —
// combining a spatial codec with a temporal one in a single operator
// algebra.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';
import 'logos_signature.dart';

/// Spectrum of a Kronecker-sum operator over two `SpectralBasis`
/// factors. Holds both factor bases plus the materialised grid of
/// pairwise eigenvalue sums (k_A · k_B scalars) — the full joint
/// spectrum without the full joint eigenvector matrix.
class SpacetimeBasis {
  /// Spatial factor (file graph).
  final SpectralBasis space;

  /// Temporal factor (commit-history graph or any time-like graph).
  final SpectralBasis time;

  const SpacetimeBasis({
    required this.space,
    required this.time,
  });

  /// Number of spatial eigenmodes.
  int get kSpace => space.k;

  /// Number of temporal eigenmodes.
  int get kTime => time.k;

  /// Joint dimension.
  int get nJoint => space.n * time.n;

  /// Eigenvalue of the (i, j)-th joint mode: `λ_file[i] + λ_time[j]`.
  double eigenvalue(int i, int j) =>
      space.eigenvalues[i] + time.eigenvalues[j];

  /// Heat trace of the joint operator at scale t:
  /// `Σᵢⱼ e^{−t(λᵢ+μⱼ)} = (Σᵢ e^{−tλᵢ}) · (Σⱼ e^{−tμⱼ}) = Z_space(t)·Z_time(t)`.
  /// The joint partition factors into the product of factor partitions —
  /// the codebase's spatial fingerprint and its temporal fingerprint
  /// evolve independently under the joint operator.
  double heatTrace(double t) => space.heatTrace(t) * time.heatTrace(t);

  /// Project a joint source onto the joint basis. `rho` is laid out
  /// row-major: `rho[i * n_time + j]` is mass at space node i, time
  /// node j. Returns a coefficient grid `C[i, j]` of size
  /// `k_space · k_time`, laid out row-major as a flat Float64List.
  ///
  /// The projection factors: `C[a, b] = (Uᵀ_space · ρ · U_time)[a, b]`
  /// — one space-projection step + one time-projection step, no joint
  /// materialisation. Cost: O(k_space·n_space·n_time + k_time·k_space·n_time).
  Float64List project(Float64List rho) {
    assert(rho.length == nJoint, 'rho must have length space.n * time.n');
    final nS = space.n;
    final nT = time.n;
    // Step 1: project each time-slice of rho onto the spatial basis.
    // Output shape: k_space × n_time.
    final partial = Float64List(kSpace * nT);
    for (var a = 0; a < kSpace; a++) {
      final uBase = a * nS;
      for (var j = 0; j < nT; j++) {
        var s = 0.0;
        for (var i = 0; i < nS; i++) {
          s += space.eigenvectors[uBase + i] * rho[i * nT + j];
        }
        partial[a * nT + j] = s;
      }
    }
    // Step 2: project each k_space-row onto the temporal basis. Output
    // shape: k_space × k_time, laid out row-major.
    final coeffs = Float64List(kSpace * kTime);
    for (var a = 0; a < kSpace; a++) {
      for (var b = 0; b < kTime; b++) {
        final vBase = b * nT;
        var s = 0.0;
        for (var j = 0; j < nT; j++) {
          s += time.eigenvectors[vBase + j] * partial[a * nT + j];
        }
        coeffs[a * kTime + b] = s;
      }
    }
    return coeffs;
  }

  /// Reconstruct a diffused joint field from its projection coefficients
  /// and a temperature t. Applies thermal damping per (a, b) mode pair,
  /// then recombines. Returns a flat rho-shaped Float64List of length
  /// `n_space · n_time`.
  Float64List recombineFromProjection(Float64List coeffs, double t) {
    assert(coeffs.length == kSpace * kTime, 'coeffs shape mismatch');
    final nS = space.n;
    final nT = time.n;
    // Damp each coefficient by e^{-t(λ_space[a] + λ_time[b])}.
    final damped = Float64List(kSpace * kTime);
    for (var a = 0; a < kSpace; a++) {
      for (var b = 0; b < kTime; b++) {
        damped[a * kTime + b] = coeffs[a * kTime + b] *
            math.exp(-t * (space.eigenvalues[a] + time.eigenvalues[b]));
      }
    }
    // Step 1: recombine along the time axis. Output: k_space × n_time.
    final partial = Float64List(kSpace * nT);
    for (var a = 0; a < kSpace; a++) {
      for (var j = 0; j < nT; j++) {
        var s = 0.0;
        for (var b = 0; b < kTime; b++) {
          s += damped[a * kTime + b] * time.eigenvectors[b * nT + j];
        }
        partial[a * nT + j] = s;
      }
    }
    // Step 2: recombine along the space axis. Output: n_space × n_time.
    final phi = Float64List(nS * nT);
    for (var i = 0; i < nS; i++) {
      for (var j = 0; j < nT; j++) {
        var s = 0.0;
        for (var a = 0; a < kSpace; a++) {
          s += partial[a * nT + j] * space.eigenvectors[a * nS + i];
        }
        phi[i * nT + j] = s;
      }
    }
    return phi;
  }

  /// One-shot joint diffusion: project, damp, recombine.
  Float64List diffuse(Float64List rho, double t) =>
      recombineFromProjection(project(rho), t);

  /// Joint signature — deterministic from the two factor signatures.
  /// A spacetime basis is identity-equal to another iff both factors
  /// match, so combining the factor signatures with a stable mixer
  /// gives the composite identity.
  Signature get signature {
    const mask = 0x7fffffff;
    var hLo = 0x811c9dc5 ^ space.signature.lo;
    var hHi = 0xdeadbeef ^ space.signature.hi;
    hLo = (hLo ^ space.signature.hi) & mask;
    hLo = ((hLo * 0x01000193) ^ (hLo >> 13)) & mask;
    hLo = (hLo ^ time.signature.lo) & mask;
    hLo = ((hLo * 0x01000193) ^ (hLo >> 13)) & mask;
    hLo = (hLo ^ time.signature.hi) & mask;
    hLo = ((hLo * 0x01000193) ^ (hLo >> 13)) & mask;
    hHi = (hHi ^ space.signature.lo ^ 0x5a5a5a5a) & mask;
    hHi = ((hHi * 0x01000193) ^ (hHi >> 13)) & mask;
    hHi = (hHi ^ time.signature.hi) & mask;
    hHi = ((hHi * 0x01000193) ^ (hHi >> 13)) & mask;
    hHi = (hHi ^ time.signature.lo) & mask;
    hHi = ((hHi * 0x01000193) ^ (hHi >> 13)) & mask;
    return Signature(lo: hLo, hi: hHi);
  }
}

/// Kronecker-sum tensor product of two spectral identities. The
/// mathematical definition:
///   L_joint = L_a ⊗ I + I ⊗ L_b
/// with eigenvalues (λᵢ + μⱼ) and eigenvectors (uᵢ ⊗ vⱼ). This is
/// the natural product structure of two independent diffusion
/// operators living on orthogonal axes (e.g. file × commit-time).
///
/// `SpectralBasis × SpectralBasis → SpacetimeBasis` — the first
/// first-class morphism on spectral identities. Tower composition
/// is now a single function call: `filesBasis.tensor(commitsBasis)`.
SpacetimeBasis tensorSpectral(SpectralBasis space, SpectralBasis time) =>
    SpacetimeBasis(space: space, time: time);


/// Build a sparse commit graph from a `perFileCommitIndices` mapping
/// (file path → list of commit indices that touched it). Nodes are
/// commits, edge weights are a Jaccard-overlap measure of the file
/// sets two commits touched, attenuated by temporal distance so that
/// co-change between neighbouring commits outweighs coincidental
/// overlap between commits far apart.
///
/// **Reading**: commits are the temporal atoms of a repo; this graph
/// is the inverse of the file graph — each commit "feels" the commits
/// that touched overlapping files. The [SpacetimeBasis] uses this as
/// its temporal factor; file × commit joint diffusion then surfaces
/// things like "this focus has always co-evolved with that file" or
/// "this PR's shape has no historical twin."
///
/// Sparsification: top-[topK] neighbours per node by weight, standard
/// CSR dedup + symmetrisation as in [CsrGraph.fromRawEdges]. Temporal
/// attenuation follows `exp(−timeDecay·|i − j|)` — co-change within a
/// 1/timeDecay window carries full weight; beyond it, decays fast.
CsrGraph buildCommitGraph({
  required Map<String, List<int>> perFileCommitIndices,
  required int totalCommits,
  int topK = 16,
  double timeDecay = 0.1,
}) {
  if (totalCommits <= 0) {
    return CsrGraph(
      n: 0,
      indptr: Int32List(1),
      indices: Int32List(0),
      values: Float64List(0),
    );
  }
  // Invert perFileCommitIndices → commit → list of file-path ids. We
  // don't actually need the file identity; we just need each commit's
  // size to compute Jaccard denominators. So: track commit file-set
  // size, and for every pair of commits that share a file, accumulate
  // a +1 numerator. This is the classic "inverted index pair iterator"
  // (same pattern as logos_hunks' token bucket → pair walk).
  final commitSize = List<int>.filled(totalCommits, 0);
  final numerator = <int, Map<int, double>>{};

  void addPair(int a, int b) {
    if (a == b) return;
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    final row = numerator.putIfAbsent(lo, () => <int, double>{});
    row[hi] = (row[hi] ?? 0.0) + 1.0;
  }

  for (final entry in perFileCommitIndices.entries) {
    final list = entry.value;
    // Filter to in-range indices and count commit sizes.
    for (final c in list) {
      if (c >= 0 && c < totalCommits) commitSize[c]++;
    }
    // Pairwise add for every pair of commits in this file's list.
    for (var i = 0; i < list.length; i++) {
      final ci = list[i];
      if (ci < 0 || ci >= totalCommits) continue;
      for (var j = i + 1; j < list.length; j++) {
        final cj = list[j];
        if (cj < 0 || cj >= totalCommits) continue;
        addPair(ci, cj);
      }
    }
  }

  // Build weighted edges with Jaccard denom + temporal decay, then
  // top-K sparsify per node and hand to CsrGraph.fromRawEdges.
  final edgesPerNode =
      List<List<(int, double)>>.generate(totalCommits, (_) => []);
  numerator.forEach((lo, row) {
    row.forEach((hi, shared) {
      final denom = commitSize[lo] + commitSize[hi] - shared;
      if (denom <= 0) return;
      final jaccard = shared / denom;
      final dt = (hi - lo).abs().toDouble();
      final decay = math.exp(-timeDecay * dt);
      final w = jaccard * decay;
      if (w <= 0.0) return;
      edgesPerNode[lo].add((hi, w));
      edgesPerNode[hi].add((lo, w));
    });
  });

  // Top-K per node.
  for (var i = 0; i < totalCommits; i++) {
    final row = edgesPerNode[i];
    if (row.length <= topK) continue;
    row.sort((a, b) => b.$2.compareTo(a.$2));
    edgesPerNode[i] = row.sublist(0, topK);
  }

  return CsrGraph.fromRawEdges(
    n: totalCommits,
    edgesPerNode: edgesPerNode,
  );
}

