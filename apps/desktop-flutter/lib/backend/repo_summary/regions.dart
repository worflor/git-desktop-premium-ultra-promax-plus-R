// regions.dart — spectral community detection + centrality on the
// active file-coupling subgraph.
//
// We build a weighted graph over the active files using the engine's
// co-change Jaccard matrix as edge weights, then route through the
// engine's spectral primitives:
//
//   buildSymmetricCsrGraph  →  SpectralBasis.fromGraph
//                           →  (eigengap on eigenvalues)       k
//                           →  spectralCommunityLabels(k)
//                           →  stationaryDistribution
//
// The community count `k` is chosen by the **eigengap heuristic**:
// walk the sorted eigenvalues starting from `firstExcitedIndex`, find
// the index `i` where `λ_{i+1} - λ_i` is largest — that's the natural
// cut-point between the "within-community" and "between-community"
// spectrum. Zero tuning, one pass over the eigenvalue list.

import 'dart:math' as math;

import '../file_coupling.dart';
import '../graph/csr_builder.dart';
import '../logos_core.dart';
import 'curves.dart';

/// Output of the region pass.
class RegionResult {
  const RegionResult({
    required this.regions,
    required this.fileCentrality,
    required this.activePaths,
    required this.graph,
    required this.basis,
  });

  /// The partition, in presentation order (largest first).
  final List<RegionCluster> regions;

  /// Per-path centrality scalar in [0, 1]. Derived from the spectral
  /// stationary distribution (squared ground-state eigenvector).
  final Map<String, double> fileCentrality;

  /// Active paths, matching the node id space of the graph.
  final List<String> activePaths;

  /// The coupling graph that drove clustering. Null when there were
  /// no edges (degenerate single-region case).
  final CsrGraph? graph;

  /// The spectral basis computed on [graph]. Null when the basis
  /// couldn't be built (too-small graph, Lanczos failure, no edges).
  final SpectralBasis? basis;
}

/// One community of files.
class RegionCluster {
  const RegionCluster({
    required this.id,
    required this.paths,
    required this.neighborIds,
    required this.internalWeight,
    required this.externalWeight,
  });

  final int id;
  final List<String> paths;
  final List<int> neighborIds;
  final double internalWeight;
  final double externalWeight;

  double get cohesion {
    final total = internalWeight + externalWeight;
    if (total <= 0.0) return 0.0;
    return internalWeight / total;
  }
}

/// Partition [activePaths] into regions using the co-change coupling
/// matrix. When [coupling] is null or yields no edges, falls back to
/// a single region covering every active file.
RegionResult findRegions({
  required List<String> activePaths,
  FileCouplingMatrix? coupling,
  int seed = 0xC005C0DE,
}) {
  final n = activePaths.length;
  if (n == 0) {
    return const RegionResult(
      regions: [], fileCentrality: {}, activePaths: [],
      graph: null, basis: null,
    );
  }

  if (n == 1) {
    return RegionResult(
      regions: [
        RegionCluster(
          id: 0,
          paths: [activePaths.first],
          neighborIds: const [],
          internalWeight: 0.0,
          externalWeight: 0.0,
        ),
      ],
      fileCentrality: {activePaths.first: 1.0},
      activePaths: List<String>.unmodifiable(activePaths),
      graph: null,
      basis: null,
    );
  }

  // Build the weighted edge list from coupling, restricted to active.
  final pathToId = <String, int>{
    for (var i = 0; i < n; i++) activePaths[i]: i,
  };

  final edges = <CsrEdge>[];
  if (coupling != null) {
    for (var i = 0; i < n; i++) {
      final path = activePaths[i];
      if (!coupling.containsPath(path)) continue;
      for (final entry in coupling.jaccardEntriesOf(path)) {
        final j = pathToId[entry.key];
        if (j == null) continue;
        if (j <= i) continue;
        if (entry.value <= 0.0) continue;
        edges.add(CsrEdge(i, j, entry.value));
      }
    }
  }

  if (edges.isEmpty) {
    return RegionResult(
      regions: [
        RegionCluster(
          id: 0,
          paths: List<String>.of(activePaths),
          neighborIds: const [],
          internalWeight: 0.0,
          externalWeight: 0.0,
        ),
      ],
      fileCentrality: {
        for (final p in activePaths) p: 1.0 / n,
      },
      activePaths: List<String>.unmodifiable(activePaths),
      graph: null,
      basis: null,
    );
  }

  // Build the CSR graph.
  final graph = buildSymmetricCsrGraph(n: n, edges: edges);

  // Ask Lanczos for as many eigenpairs as the graph can yield. We use
  // them both to pick `k` (via eigengap) and to embed into k-1 axes
  // for the Shi-Malik clustering.
  final kRequested = n - 1;
  late final SpectralBasis basis;
  try {
    basis = SpectralBasis.fromGraph(graph, kRequested, nodePaths: activePaths);
  } on Object {
    return RegionResult(
      regions: [
        RegionCluster(
          id: 0,
          paths: List<String>.of(activePaths),
          neighborIds: const [],
          internalWeight: _sumEdgeWeights(edges),
          externalWeight: 0.0,
        ),
      ],
      fileCentrality: {
        for (final p in activePaths) p: 1.0 / n,
      },
      activePaths: List<String>.unmodifiable(activePaths),
      graph: graph,
      basis: null,
    );
  }

  // Community count: knee of the excited eigenvalue curve, detected
  // by reversing into descending order and calling `kneeIndex`. The
  // ascending spectrum has k small eigenvalues (one per intra-cluster
  // mode) followed by a climb into the bulk — so the reversed curve
  // is a flat-then-steep descent whose elbow lands at exactly
  // (n − k), which recovers `k` via the subtraction below. This is
  // equivalent to the classical eigengap heuristic's argmax-gap when
  // the gap is sharp, and more robust when gaps grow gradually.
  final start = basis.firstExcitedIndex;
  final excited = <double>[
    for (var i = start; i < basis.k; i++) basis.eigenvalues[i],
  ];
  // kneeIndex wants descending — reverse and remap.
  final desc = excited.reversed.toList();
  final kneeFromTail = kneeIndex(desc);
  final kRegions = math.max(2, excited.length - kneeFromTail);

  // Spectral community labels.
  final labels = basis.spectralCommunityLabels(kRegions, seed: seed);
  // Stationary distribution (squared ground-state eigenvector).
  final pi = basis.stationaryDistribution();

  // Aggregate per-region intra / cross weights. `labels` can contain
  // repeats and holes in the label space (if a community has zero
  // members after embedding), so we dedupe via a sorted copy of the
  // distinct values directly — no Set intermediate needed.
  final distinctLabels = <int>{...labels}.toList()..sort();
  final labelRemap = <int, int>{
    for (var i = 0; i < distinctLabels.length; i++) distinctLabels[i]: i,
  };
  final kEffective = distinctLabels.length;

  final internal = List<double>.filled(kEffective, 0.0);
  final cross = List<Map<int, double>>.generate(
    kEffective, (_) => <int, double>{}, growable: false,
  );
  for (final e in edges) {
    final la = labelRemap[labels[e.u]]!;
    final lb = labelRemap[labels[e.v]]!;
    if (la == lb) {
      internal[la] += e.weight;
    } else {
      cross[la][lb] = (cross[la][lb] ?? 0.0) + e.weight;
      cross[lb][la] = (cross[lb][la] ?? 0.0) + e.weight;
    }
  }

  final membersByLabel = List<List<int>>.generate(
    kEffective, (_) => <int>[], growable: false,
  );
  for (var i = 0; i < n; i++) {
    final l = labelRemap[labels[i]]!;
    membersByLabel[l].add(i);
  }

  // Normalise centrality to [0, 1].
  final centrality = <String, double>{
    for (var i = 0; i < n; i++) activePaths[i]: pi[i],
  };
  var piMax = 0.0;
  for (final v in pi) {
    if (v > piMax) piMax = v;
  }
  if (piMax > 0.0) {
    final scale = 1.0 / piMax;
    centrality.updateAll((_, v) => v * scale);
  }

  final clusters = <RegionCluster>[];
  for (var l = 0; l < kEffective; l++) {
    final nodes = membersByLabel[l]
      ..sort((a, b) => pi[b].compareTo(pi[a]));
    final paths = [for (final i in nodes) activePaths[i]];
    final crossEntries = cross[l].entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final neighborIds = [for (final e in crossEntries) e.key];
    var externalTotal = 0.0;
    for (final e in crossEntries) {
      externalTotal += e.value;
    }
    clusters.add(RegionCluster(
      id: l,
      paths: List<String>.unmodifiable(paths),
      neighborIds: List<int>.unmodifiable(neighborIds),
      internalWeight: internal[l],
      externalWeight: externalTotal,
    ));
  }

  // Presentation order: largest region first.
  clusters.sort((a, b) => b.paths.length.compareTo(a.paths.length));

  // Reassign presentation ids and remap neighbor ids.
  final oldToPresent = <int, int>{
    for (var i = 0; i < clusters.length; i++) clusters[i].id: i,
  };
  final finalRegions = <RegionCluster>[];
  for (var i = 0; i < clusters.length; i++) {
    final c = clusters[i];
    final remappedNeighbors = <int>[];
    for (final nid in c.neighborIds) {
      final mapped = oldToPresent[nid];
      if (mapped != null && mapped != i) remappedNeighbors.add(mapped);
    }
    finalRegions.add(RegionCluster(
      id: i,
      paths: c.paths,
      neighborIds: List<int>.unmodifiable(remappedNeighbors),
      internalWeight: c.internalWeight,
      externalWeight: c.externalWeight,
    ));
  }

  return RegionResult(
    regions: List<RegionCluster>.unmodifiable(finalRegions),
    fileCentrality: Map<String, double>.unmodifiable(centrality),
    activePaths: List<String>.unmodifiable(activePaths),
    graph: graph,
    basis: basis,
  );
}

double _sumEdgeWeights(List<CsrEdge> edges) {
  var acc = 0.0;
  for (final e in edges) {
    acc += e.weight;
  }
  return acc;
}
