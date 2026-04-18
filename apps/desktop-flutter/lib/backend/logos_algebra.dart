// LogosAlgebra — formal composition rules for spectra.
//
// The engine has been accumulating observables (heatTrace, zeta,
// dimension, persistence, ...) without a common vocabulary for HOW
// they compose under natural graph operations. This module fixes
// that by defining the two simplest structural compositions and the
// corresponding observable-level identities they induce.
//
// Two operations are covered here:
//
//   * **Direct sum** `A ⊕ B` — the disjoint union of two graphs.
//     Nodes: `n_A + n_B`. Edges: independent. Spectrum:
//     `σ(A ⊕ B) = σ(A) ∪ σ(B)` (with multiplicity). Every extensive
//     spectral observable is ADDITIVE under this operation:
//
//       heatTrace_{A⊕B}(t) = heatTrace_A(t) + heatTrace_B(t)
//       zeta_{A⊕B}(s)      = zeta_A(s)     + zeta_B(s)
//       logDet_{A⊕B}       = logDet_A      + logDet_B
//
//     The direct sum is the "external" composition — repos that know
//     nothing about each other. A refactor that splits one repo into
//     two independent packages moves the observables from one side
//     of this identity to the other.
//
//   * **Coarse-graining** — cluster nodes, rebuild reduced Laplacian.
//     This is the "internal" composition: zooming out without
//     changing what the graph IS, only what you count as one node.
//     The reduced spectrum satisfies interlacing with the original,
//     preserving spectral-gap dominance while compressing the
//     high-frequency tail. Not additive on ANY observable — it's
//     a compression, not a composition — but it commutes with the
//     partition-function integral in a specific way documented on
//     `coarsenByPartition`.
//
// Together these two operations + the sum/product rules on
// observables are the beginnings of an **observable algebra**: given
// a repo's spectrum and a transformation on its graph, predict the
// observable's new value without recomputing.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';

/// The direct sum `A ⊕ B` — a single graph with two disconnected
/// components. Node IDs from `B` are shifted by `A.n`; edges are
/// concatenated and re-fused under the new combined D^{-1/2}.
///
/// **Operational** — the fused weights re-normalise because the
/// joint degree vector is the concatenation, which means the
/// normalisation factor per node is unchanged (degrees don't mix
/// across components). So the fused values are the original fused
/// values reused verbatim. That fact is what makes every EXTENSIVE
/// observable additive under direct sum.
CsrGraph directSum(CsrGraph a, CsrGraph b) {
  final nA = a.n;
  final nB = b.n;
  final n = nA + nB;
  final mA = a.values.length;
  final mB = b.values.length;
  final m = mA + mB;

  final indptr = Int32List(n + 1);
  // Row 0..nA-1 from A, then nA..n-1 from B shifted.
  for (var i = 0; i <= nA; i++) {
    indptr[i] = a.indptr[i];
  }
  for (var i = 0; i <= nB; i++) {
    indptr[nA + i] = mA + b.indptr[i];
  }

  final indices = Int32List(m);
  for (var p = 0; p < mA; p++) {
    indices[p] = a.indices[p];
  }
  for (var p = 0; p < mB; p++) {
    indices[mA + p] = b.indices[p] + nA;
  }

  final values = Float64List(m);
  for (var p = 0; p < mA; p++) {
    values[p] = a.values[p];
  }
  for (var p = 0; p < mB; p++) {
    values[mA + p] = b.values[p];
  }

  // Optional rank-1 metadata preserved only when both sides supply it.
  Float64List? degreeInvSqrt;
  Float64List? rawWeights;
  if (a.supportsRankOneUpdates && b.supportsRankOneUpdates) {
    degreeInvSqrt = Float64List(n);
    for (var i = 0; i < nA; i++) degreeInvSqrt[i] = a.degreeInvSqrt[i];
    for (var i = 0; i < nB; i++) degreeInvSqrt[nA + i] = b.degreeInvSqrt[i];

    rawWeights = Float64List(m);
    for (var p = 0; p < mA; p++) rawWeights[p] = a.rawWeights[p];
    for (var p = 0; p < mB; p++) rawWeights[mA + p] = b.rawWeights[p];
  }

  return CsrGraph(
    n: n,
    indptr: indptr,
    indices: indices,
    values: values,
    degreeInvSqrt: degreeInvSqrt,
    rawWeights: rawWeights,
  );
}

/// Coarse-graining via node partitioning. Each input node is assigned
/// a cluster ID in `clusterIds`; the reduced graph has one node per
/// unique ID, with edge weights summed across inter-cluster edges.
///
/// Weight convention: the reduced-graph edge between cluster `C₁` and
/// cluster `C₂` is the sum of RAW weights (not fused) across all
/// inter-cluster edges. This preserves the physical meaning of
/// coupling strength: a cluster with many incident edges ties
/// strongly to its neighbour clusters regardless of internal
/// structure.
///
/// **Operational** — coarse-graining is not uniquely specified; this
/// is the "Graph Laplacian projection" discretisation (Kron
/// reduction). Consumers that want a different convention (e.g.
/// Cheeger cut, spectral clustering) should build the partition
/// themselves and call this with it.
CsrGraph coarsenByPartition(CsrGraph graph, List<int> clusterIds) {
  assert(clusterIds.length == graph.n,
      'clusterIds length ${clusterIds.length} must equal graph.n ${graph.n}');

  // Map cluster IDs to compact indices [0, numClusters).
  final idMap = <int, int>{};
  for (final id in clusterIds) {
    idMap.putIfAbsent(id, () => idMap.length);
  }
  final numClusters = idMap.length;

  // Accumulate inter-cluster edge weights. We need RAW weights, so
  // un-fuse on the way in when the metadata is available. Fall back
  // to the fused values when raw weights aren't stored.
  final hasRaw = graph.supportsRankOneUpdates;
  final accum = <int, Map<int, double>>{};
  for (var u = 0; u < graph.n; u++) {
    final cu = idMap[clusterIds[u]]!;
    final p0 = graph.indptr[u];
    final p1 = graph.indptr[u + 1];
    for (var p = p0; p < p1; p++) {
      final v = graph.indices[p];
      if (v <= u) continue; // undirected — each edge once
      final cv = idMap[clusterIds[v]]!;
      if (cu == cv) continue; // drop intra-cluster edges
      // Raw weight: values[p] = D^{-1/2}[u] · W[u,v] · D^{-1/2}[v],
      // so W = values[p] / (D^{-1/2}[u] · D^{-1/2}[v]). Use raw when
      // available, else the fused value as a proxy.
      final w = hasRaw
          ? graph.rawWeights[p]
          : graph.values[p];
      (accum[cu] ??= <int, double>{}).update(
        cv,
        (existing) => existing + w,
        ifAbsent: () => w,
      );
      (accum[cv] ??= <int, double>{}).update(
        cu,
        (existing) => existing + w,
        ifAbsent: () => w,
      );
    }
  }

  // Build edgesPerNode structure for CsrGraph.fromRawEdges.
  final edgesPerNode =
      List<List<(int, double)>>.generate(numClusters, (_) => []);
  for (var c = 0; c < numClusters; c++) {
    final neighbours = accum[c];
    if (neighbours == null) continue;
    final sorted = neighbours.keys.toList()..sort();
    for (final n in sorted) {
      edgesPerNode[c].add((n, neighbours[n]!));
    }
  }

  return CsrGraph.fromRawEdges(n: numClusters, edgesPerNode: edgesPerNode);
}

/// Return the direct-sum spectrum built by concatenating and sorting
/// the eigenvalues of two bases. This is the *spectral* companion to
/// [directSum]: when you only need the spectrum (not the graph), this
/// is O(k_A + k_B) instead of a fresh Lanczos run.
///
/// **Theorem-tight** — `σ(A ⊕ B) = σ(A) ∪ σ(B)` with multiplicity is
/// an algebraic identity on the block-diagonal Laplacian.
SpectralBasis directSumBasis(SpectralBasis a, SpectralBasis b) {
  final nA = a.n;
  final nB = b.n;
  final kA = a.k;
  final kB = b.k;
  final kTotal = kA + kB;

  // Merge-sort eigenvalues since both inputs are sorted.
  final mergedEigs = Float64List(kTotal);
  final sourceTags = Int32List(kTotal); // 0 = from A, 1 = from B
  final sourceIndex = Int32List(kTotal);
  var ia = 0, ib = 0, out = 0;
  while (ia < kA && ib < kB) {
    if (a.eigenvalues[ia] <= b.eigenvalues[ib]) {
      mergedEigs[out] = a.eigenvalues[ia];
      sourceTags[out] = 0;
      sourceIndex[out] = ia;
      ia++;
    } else {
      mergedEigs[out] = b.eigenvalues[ib];
      sourceTags[out] = 1;
      sourceIndex[out] = ib;
      ib++;
    }
    out++;
  }
  while (ia < kA) {
    mergedEigs[out] = a.eigenvalues[ia];
    sourceTags[out] = 0;
    sourceIndex[out] = ia;
    ia++;
    out++;
  }
  while (ib < kB) {
    mergedEigs[out] = b.eigenvalues[ib];
    sourceTags[out] = 1;
    sourceIndex[out] = ib;
    ib++;
    out++;
  }

  // Build block-diagonal eigenvectors. Each merged eigenpair picks
  // from one source and is zero-padded on the other component.
  final nTotal = nA + nB;
  final vecs = Float64List(kTotal * nTotal);
  for (var j = 0; j < kTotal; j++) {
    final base = j * nTotal;
    if (sourceTags[j] == 0) {
      final srcBase = sourceIndex[j] * nA;
      for (var i = 0; i < nA; i++) {
        vecs[base + i] = a.eigenvectors[srcBase + i];
      }
      // nA..nTotal stays zero (already initialised).
    } else {
      final srcBase = sourceIndex[j] * nB;
      for (var i = 0; i < nB; i++) {
        vecs[base + nA + i] = b.eigenvectors[srcBase + i];
      }
    }
  }

  // Concatenate labels if both sides have them; else drop.
  List<String>? nodePaths;
  if (a.nodePaths != null && b.nodePaths != null) {
    nodePaths = [...a.nodePaths!, ...b.nodePaths!];
  }

  return SpectralBasis(
    n: nTotal,
    k: kTotal,
    eigenvalues: mergedEigs,
    eigenvectors: vecs,
    nodePaths: nodePaths,
  );
}
