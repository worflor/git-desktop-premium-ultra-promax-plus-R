// Tests for Ollivier-Ricci edge curvature field.
//
// Load-bearing invariant: on a dumbbell graph (two tight communities
// joined by a narrow bridge), the bridge edges should have the most
// negative curvatures in the field. Python reference in
// `tmp_ice_walls.py` §3: bridge OR ≈ -1.4, off-bridge OR ≈ +0.44.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/spectral_ricci.dart';

// ── Graph builders ────────────────────────────────────────────────

CsrGraph _graphFromEdges(int n, List<(int, int, double)> edges) {
  final nbrs = List<List<(int, double)>>.generate(n, (_) => []);
  for (final (u, v, w) in edges) {
    if (u == v) continue;
    nbrs[u].add((v, w));
    nbrs[v].add((u, w));
  }
  final ptr = <int>[0];
  final idx = <int>[];
  final vals = <double>[];
  for (var i = 0; i < n; i++) {
    for (final (j, w) in nbrs[i]) {
      idx.add(j);
      vals.add(w);
    }
    ptr.add(idx.length);
  }
  return CsrGraph(
    n: n,
    indptr: Int32List.fromList(ptr),
    indices: Int32List.fromList(idx),
    values: Float64List.fromList(vals),
  );
}

/// Dumbbell: two cliques of size [clusterSize] joined by [bridgeCount]
/// edges. Returns (graph, bridgeEdges).
(CsrGraph, List<(int, int)>) _dumbbell({
  required int clusterSize,
  required int bridgeCount,
}) {
  final edges = <(int, int, double)>[];
  for (var i = 0; i < clusterSize; i++) {
    for (var j = i + 1; j < clusterSize; j++) {
      edges.add((i, j, 1.0));
    }
  }
  for (var i = clusterSize; i < 2 * clusterSize; i++) {
    for (var j = i + 1; j < 2 * clusterSize; j++) {
      edges.add((i, j, 1.0));
    }
  }
  final bridges = <(int, int)>[];
  for (var k = 0; k < bridgeCount; k++) {
    final u = clusterSize - 1 - k;
    final v = clusterSize + k;
    edges.add((u, v, 1.0));
    bridges.add((u, v));
  }
  return (_graphFromEdges(2 * clusterSize, edges), bridges);
}

/// Complete graph K_n — expander extreme. Every edge should have
/// strongly positive Ricci.
CsrGraph _complete(int n) {
  final edges = <(int, int, double)>[];
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      edges.add((i, j, 1.0));
    }
  }
  return _graphFromEdges(n, edges);
}

/// 4-cycle — every edge is a "bridge" in that cutting it disconnects
/// the graph. Ricci should be uniform (by symmetry).
CsrGraph _cycle(int n) {
  final edges = <(int, int, double)>[
    for (var i = 0; i < n; i++) (i, (i + 1) % n, 1.0),
  ];
  return _graphFromEdges(n, edges);
}

// ── Tests ─────────────────────────────────────────────────────────

void main() {
  group('RicciField.sinkhorn', () {
    test('dumbbell: bridge edges are the most negative', () {
      final (graph, bridges) = _dumbbell(clusterSize: 8, bridgeCount: 1);
      final field = RicciField.sinkhorn(graph);
      // The single bridge should be in the top-1 most-negative position.
      final ranked = field.mostNegativeEdges(k: 3);
      final (u, v, kappa) = ranked.first;
      expect((u, v), equals(bridges.first));
      expect(kappa, lessThan(0.0),
          reason: 'bridge edge should have negative Ricci');
      // Other edges should be considerably less negative or positive.
      final otherKappas = <double>[
        for (var i = 0; i < field.length; i++)
          if (!(field.edgeU[i] == bridges.first.$1 &&
              field.edgeV[i] == bridges.first.$2))
            field.curvatures[i],
      ];
      final otherMean = otherKappas.reduce((a, b) => a + b) / otherKappas.length;
      expect(otherMean, greaterThan(kappa + 0.3),
          reason: 'off-bridge edges (mean $otherMean) should sit meaningfully '
              'above the bridge ($kappa)');
    });

    test('dumbbell: depth scalar identifies the bottleneck', () {
      final (graph, _) = _dumbbell(clusterSize: 6, bridgeCount: 1);
      final field = RicciField.sinkhorn(graph);
      expect(field.depth, lessThan(0.0));
      // Tight community edges on K_6 cliques should push the max well up.
      expect(field.max, greaterThan(0.0));
      // Separation: max - depth should be > 0.5 on a dumbbell.
      expect(field.max - field.depth, greaterThan(0.5));
    });

    test('complete graph: Ricci is uniform and close to 1', () {
      final field = RicciField.sinkhorn(_complete(8));
      // K_n: every edge is locally interchangeable; Ricci should be
      // tightly clustered.
      final curv = field.curvatures;
      final mean = field.mean;
      var maxDev = 0.0;
      for (var i = 0; i < curv.length; i++) {
        final d = (curv[i] - mean).abs();
        if (d > maxDev) maxDev = d;
      }
      expect(maxDev, lessThan(0.2),
          reason: 'K_n should have near-uniform curvature; max dev $maxDev');
      // On K_n the true Ricci of every edge is +1 (μ_u = μ_v up to
      // laziness), so Sinkhorn mean should land well above 0.
      expect(mean, greaterThan(0.4));
    });

    test('cycle: symmetric curvature', () {
      final field = RicciField.sinkhorn(_cycle(6));
      final curv = field.curvatures;
      // All 6 edges are in the same equivalence class by cycle symmetry.
      final first = curv[0];
      for (var i = 1; i < curv.length; i++) {
        expect(curv[i], closeTo(first, 0.05),
            reason: 'cycle edge $i should match edge 0 by symmetry');
      }
    });

    test('mostNegativeEdges returns the expected k', () {
      final (graph, _) = _dumbbell(clusterSize: 6, bridgeCount: 3);
      final field = RicciField.sinkhorn(graph);
      final top3 = field.mostNegativeEdges(k: 3);
      expect(top3.length, equals(3));
      // Ranking is non-decreasing by curvature.
      expect(top3[0].$3, lessThanOrEqualTo(top3[1].$3));
      expect(top3[1].$3, lessThanOrEqualTo(top3[2].$3));
    });

    test('k > |E| clamps to all edges', () {
      final field = RicciField.sinkhorn(_cycle(4));
      expect(field.length, equals(4));
      final top = field.mostNegativeEdges(k: 100);
      expect(top.length, equals(4));
    });

    test('curvatureOf returns the same value regardless of endpoint order', () {
      final field = RicciField.sinkhorn(_complete(5));
      final kAB = field.curvatureOf(1, 3);
      final kBA = field.curvatureOf(3, 1);
      expect(kAB, isNotNull);
      expect(kBA, isNotNull);
      expect(kAB, equals(kBA));
    });

    test('curvatureOf returns null for a non-edge', () {
      final (graph, _) = _dumbbell(clusterSize: 4, bridgeCount: 1);
      final field = RicciField.sinkhorn(graph);
      // Two nodes in opposite clusters that aren't the bridge ends:
      // no direct edge → null.
      expect(field.curvatureOf(0, 7), isNull);
    });

    test('signature changes with curvature values', () {
      final field1 = RicciField.sinkhorn(_complete(6));
      final field2 = RicciField.sinkhorn(_cycle(6));
      expect(field1.signature, isNot(equals(field2.signature)));
    });

    test('deterministic — two identical builds give equal fields', () {
      final (g, _) = _dumbbell(clusterSize: 5, bridgeCount: 2);
      final a = RicciField.sinkhorn(g);
      final b = RicciField.sinkhorn(g);
      expect(a.signature, equals(b.signature));
      for (var i = 0; i < a.length; i++) {
        expect(a.curvatures[i], equals(b.curvatures[i]));
      }
    });
  });

  group('RicciField scale invariance sanity', () {
    test('larger cluster with same topology preserves depth sign', () {
      final (small, _) = _dumbbell(clusterSize: 5, bridgeCount: 1);
      final (big, _) = _dumbbell(clusterSize: 10, bridgeCount: 1);
      final smallField = RicciField.sinkhorn(small);
      final bigField = RicciField.sinkhorn(big);
      expect(smallField.depth, lessThan(0));
      expect(bigField.depth, lessThan(0));
      // Larger clusters isolate the bridge more strongly.
      expect(bigField.depth, lessThanOrEqualTo(smallField.depth + 0.1));
    });
  });

  group('log-domain Sinkhorn — underflow regression', () {
    // Build a "barbell" graph: two K_6 cliques connected by a long path
    // of 12 intermediate nodes. Cross-clique hop distances reach 14+,
    // meaning C_ij / epsilon > 280, which underflows raw-domain Sinkhorn
    // (exp(-280) ≈ 0) but is exact in log-domain.
    //
    // Layout:
    //   Clique A: nodes 0..5
    //   Chain:    nodes 6..17  (12 nodes, path 6-7-...-17)
    //   Clique B: nodes 18..23
    //   Attach:   edge (5, 6) and edge (17, 18)
    test('barbell with long chain: neck edges are negative, log-domain stable',
        () {
      const cliqueSize = 6;
      const chainLen = 12;
      const total = 2 * cliqueSize + chainLen;
      // 0..cliqueSize-1 = clique A
      // cliqueSize..cliqueSize+chainLen-1 = chain
      // cliqueSize+chainLen..total-1 = clique B
      final edges = <(int, int, double)>[];
      // Clique A.
      for (var i = 0; i < cliqueSize; i++) {
        for (var j = i + 1; j < cliqueSize; j++) {
          edges.add((i, j, 1.0));
        }
      }
      // Chain.
      const chainStart = cliqueSize;
      for (var i = chainStart; i < chainStart + chainLen - 1; i++) {
        edges.add((i, i + 1, 1.0));
      }
      // Clique B.
      const bStart = cliqueSize + chainLen;
      for (var i = bStart; i < total; i++) {
        for (var j = i + 1; j < total; j++) {
          edges.add((i, j, 1.0));
        }
      }
      // Neck edges.
      const neckU = cliqueSize - 1; // 5
      const neckV = chainStart; // 6
      const neckU2 = chainStart + chainLen - 1; // 17
      const neckV2 = bStart; // 18
      edges.add((neckU, neckV, 1.0));
      edges.add((neckU2, neckV2, 1.0));

      final graph = _graphFromEdges(total, edges);
      final field = RicciField.sinkhorn(graph);

      // Both neck edges should have negative curvature (bridge-like).
      final k1 = field.curvatureOf(neckU, neckV);
      final k2 = field.curvatureOf(neckU2, neckV2);
      expect(k1, isNotNull);
      expect(k2, isNotNull);
      expect(k1!, lessThan(0.0),
          reason: 'neck edge ($neckU,$neckV) must be negative; got κ=$k1');
      expect(k2!, lessThan(0.0),
          reason: 'neck edge ($neckU2,$neckV2) must be negative; got κ=$k2');

      // Clique A internal edges should be positive.
      final kClique = field.curvatureOf(0, 1);
      expect(kClique, isNotNull);
      expect(kClique!, greaterThan(0.0),
          reason: 'clique-interior edge must be positive; got κ=$kClique');
    });
  });

  group('RicciField.curvatureOfEdge — lazy single-edge query', () {
    test('bridge edge: single-query κ matches full-field within 5%', () {
      final (graph, bridges) = _dumbbell(clusterSize: 8, bridgeCount: 1);
      final (bu, bv) = bridges.first;

      // Full-field reference.
      final field = RicciField.sinkhorn(graph);
      final fullKappa = field.curvatureOf(bu, bv)!;

      // Single-edge lazy query.
      final lazyKappa = RicciField.curvatureOfEdge(graph, bu, bv);
      expect(lazyKappa, isNotNull,
          reason: 'curvatureOfEdge should find the bridge');

      // Within 5% of absolute value (bridge κ ≈ -1.4, so 5% ≈ 0.07).
      final absDiff = (lazyKappa! - fullKappa).abs();
      final tol = fullKappa.abs() * 0.05 + 0.05; // 5% relative + 0.05 floor
      expect(absDiff, lessThanOrEqualTo(tol),
          reason: 'single-edge query ($lazyKappa) should be within 5% of '
              'full-field value ($fullKappa); diff=$absDiff tol=$tol');
    });

    test('K_n internal edge: single-query κ is positive', () {
      final graph = _complete(8);
      // K_8 — pick any edge, e.g. (0, 1).
      final kappa = RicciField.curvatureOfEdge(graph, 0, 1);
      expect(kappa, isNotNull);
      expect(kappa!, greaterThan(0.0),
          reason: 'K_n edges are expander-like; Ricci should be positive');
    });

    test('non-existent edge returns null', () {
      final (graph, _) = _dumbbell(clusterSize: 4, bridgeCount: 1);
      // Nodes 0 and 7 are in opposite clusters with no direct edge.
      final kappa = RicciField.curvatureOfEdge(graph, 0, 7);
      expect(kappa, isNull);
    });
  });
}
