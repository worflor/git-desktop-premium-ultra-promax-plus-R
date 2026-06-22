import 'dart:math' as math;
import 'dart:typed_data';

/// Unfolded Adjacency Spectral Embedding (UASE) — the root fix for the Orrery's
/// frame-to-frame "teleport". Instead of embedding each commit-snapshot
/// independently (which lets the eigenbasis rotate/sign-flip between frames and
/// makes a stable file appear to jump), UASE embeds the WHOLE time series in
/// one shared basis: a single decomposition of the stacked snapshots. A node
/// behaving the same across time then keeps the same coordinate *by
/// construction* — there is only one basis, so sign flips can't happen.
///
/// Method (Gallagher, Jones & Rubin-Delanchy, NeurIPS 2021): for the unfolded
/// matrix M = [A₁ | A₂ | … | A_T], the shared left basis U is the top-d
/// eigenvectors of G = M Mᵀ = Σₜ Aₜ² (each Aₜ symmetric). Snapshot t's
/// coordinates are then Ŷₜ = Aₜ · U · S^{-1/2}, with S = √(eigenvalues of G).
///
/// Self-contained and matrix-free: G is never materialised (we apply it as
/// Σₜ Aₜ(Aₜx) on the trial block), so cost is O(iterations · T · nnz · d) and
/// memory is O(n·d). Returns one n×d row-major embedding per snapshot.

typedef UaseEdge = ({int a, int b, double w});

class UaseResult {
  /// One n×d row-major embedding per snapshot (node i, dim j → `[i*d + j]`).
  final List<Float64List> frames;
  final int dims;
  const UaseResult({required this.frames, required this.dims});
}

UaseResult unfoldedSpectralEmbedding(
  List<List<UaseEdge>> snapshots,
  int n,
  int requestedDims, {
  int iterations = 40,
}) {
  final d = math.max(1, math.min(requestedDims, n));
  if (n == 0 || snapshots.isEmpty) {
    return UaseResult(
      frames: [for (final _ in snapshots) Float64List(0)],
      dims: d,
    );
  }

  // Subspace (orthogonal) iteration for the top-d eigenvectors of G = Σ Aₜ².
  var u = _initBasis(n, d);
  for (var it = 0; it < iterations; it++) {
    final z = _applyG(snapshots, u, n, d);
    _orthonormalizeColumns(z, n, d);
    u = z;
  }

  // Singular values S[j] = √(Rayleigh quotient of G on column j).
  final gu = _applyG(snapshots, u, n, d);
  final invSqrtS = Float64List(d);
  for (var j = 0; j < d; j++) {
    var rayleigh = 0.0;
    for (var i = 0; i < n; i++) {
      rayleigh += u[i * d + j] * gu[i * d + j];
    }
    final s = math.sqrt(rayleigh.abs()); // S[j]
    invSqrtS[j] = s > 1e-9 ? 1.0 / math.sqrt(s) : 0.0; // S^{-1/2}
  }

  // Ŷₜ = Aₜ · U · S^{-1/2} (Aₜ symmetric ⇒ Aₜᵀ = Aₜ).
  final frames = <Float64List>[];
  for (final snap in snapshots) {
    final au = _spmm(snap, u, n, d);
    final y = Float64List(n * d);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < d; j++) {
        y[i * d + j] = au[i * d + j] * invSqrtS[j];
      }
    }
    frames.add(y);
  }
  return UaseResult(frames: frames, dims: d);
}

Float64List _initBasis(int n, int d) {
  final x = Float64List(n * d);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < d; j++) {
      // Deterministic, non-degenerate start (avoids the Math.random ban and
      // keeps the embedding reproducible across runs).
      x[i * d + j] = math.sin((i + 1) * (j + 1) * 0.7) + 0.013 * (j + 1);
    }
  }
  _orthonormalizeColumns(x, n, d);
  return x;
}

/// Z = G X = Σₜ Aₜ(Aₜ X). G is never formed.
Float64List _applyG(
  List<List<UaseEdge>> snapshots,
  Float64List x,
  int n,
  int d,
) {
  final acc = Float64List(n * d);
  for (final snap in snapshots) {
    final ax = _spmm(snap, x, n, d);
    final aax = _spmm(snap, ax, n, d);
    for (var t = 0; t < n * d; t++) {
      acc[t] += aax[t];
    }
  }
  return acc;
}

/// Y = A·X for a symmetric sparse A given as an edge list (no self-loops).
/// X is n×d row-major.
Float64List _spmm(List<UaseEdge> edges, Float64List x, int n, int d) {
  final y = Float64List(n * d);
  for (final e in edges) {
    final ab = e.a * d;
    final bb = e.b * d;
    final w = e.w;
    for (var j = 0; j < d; j++) {
      y[ab + j] += w * x[bb + j];
      y[bb + j] += w * x[ab + j];
    }
  }
  return y;
}

/// Modified Gram–Schmidt orthonormalisation of the d columns (each length n)
/// of a row-major n×d matrix, in place.
void _orthonormalizeColumns(Float64List m, int n, int d) {
  for (var j = 0; j < d; j++) {
    for (var p = 0; p < j; p++) {
      var dot = 0.0;
      for (var i = 0; i < n; i++) {
        dot += m[i * d + j] * m[i * d + p];
      }
      for (var i = 0; i < n; i++) {
        m[i * d + j] -= dot * m[i * d + p];
      }
    }
    var norm = 0.0;
    for (var i = 0; i < n; i++) {
      norm += m[i * d + j] * m[i * d + j];
    }
    norm = math.sqrt(norm);
    if (norm > 1e-12) {
      final inv = 1.0 / norm;
      for (var i = 0; i < n; i++) {
        m[i * d + j] *= inv;
      }
    }
  }
}
