// Tests for LogosPersistence — persistent homology on the coupling
// filtration.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_persistence.dart';

CsrGraph _path(int n) {
  final edges = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n - 1; i++) {
    edges[i].add((i + 1, 1.0));
    edges[i + 1].add((i, 1.0));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

CsrGraph _cycle(int n) {
  final edges = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    edges[i].add((j, 1.0));
    edges[j].add((i, 1.0));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

/// Two triangles connected by a single bridging edge. Exactly 2 β₁
/// features (one per triangle) and no β₀ merges that leave residues.
CsrGraph _twoTrianglesBridged() {
  // Nodes 0-1-2 form one triangle; 3-4-5 form the other; 2↔3 bridges.
  final edges = List<List<(int, double)>>.generate(6, (_) => []);
  void add(int a, int b, double w) {
    edges[a].add((b, w));
    edges[b].add((a, w));
  }
  // Strong triangles, weaker bridge so it enters last.
  add(0, 1, 1.0);
  add(1, 2, 1.0);
  add(0, 2, 1.0);
  add(3, 4, 1.0);
  add(4, 5, 1.0);
  add(3, 5, 1.0);
  add(2, 3, 0.3);
  return CsrGraph.fromRawEdges(n: 6, edgesPerNode: edges);
}

/// Two well-separated components — one big and one small — joined by a
/// single weak edge. Designed to test that the LONG β₀ bar corresponds
/// to the merge weight of the inter-component bridge.
CsrGraph _twoClustersWithBridge() {
  // 0..4 is one clique (weights 1.0); 5..9 is another (weights 1.0);
  // a single 4↔5 bridge of weight 0.05.
  final edges = List<List<(int, double)>>.generate(10, (_) => []);
  void add(int a, int b, double w) {
    edges[a].add((b, w));
    edges[b].add((a, w));
  }
  for (var i = 0; i < 5; i++) {
    for (var j = i + 1; j < 5; j++) {
      add(i, j, 1.0);
    }
  }
  for (var i = 5; i < 10; i++) {
    for (var j = i + 1; j < 10; j++) {
      add(i, j, 1.0);
    }
  }
  add(4, 5, 0.05);
  return CsrGraph.fromRawEdges(n: 10, edgesPerNode: edges);
}

void main() {
  group('computeCouplingPersistence — smoke + degenerate', () {
    test('null on 0 or 1 node graphs', () {
      expect(
        computeCouplingPersistence(
          CsrGraph.fromRawEdges(n: 0, edgesPerNode: const []),
        ),
        isNull,
      );
      expect(
        computeCouplingPersistence(
          CsrGraph.fromRawEdges(n: 1, edgesPerNode: const [[]]),
        ),
        isNull,
      );
    });

    test('null on edge-free graph', () {
      final d = computeCouplingPersistence(
        CsrGraph.fromRawEdges(n: 5, edgesPerNode: const [[], [], [], [], []]),
      );
      expect(d, isNull);
    });
  });

  group('path graph → tree (β₁ = 0, β₀ = 1)', () {
    test('path has exactly n-1 finite β₀ pairs and 1 essential β₀', () {
      final d = computeCouplingPersistence(_path(8))!;
      final b0Finite =
          d.pairs.where((p) => p.dimension == 0 && !p.essential).length;
      final b0Essential =
          d.pairs.where((p) => p.dimension == 0 && p.essential).length;
      final b1 = d.pairs.where((p) => p.dimension == 1).length;
      expect(b0Finite, equals(7));
      expect(b0Essential, equals(1));
      expect(b1, equals(0), reason: 'a path has no cycles');
      expect(d.finalComponents, equals(1));
      expect(d.finalCycles, equals(0));
    });
  });

  group('cycle graph → one β₁', () {
    test('n-cycle has exactly one β₁ essential pair', () {
      final d = computeCouplingPersistence(_cycle(6))!;
      final b1 = d.pairs.where((p) => p.dimension == 1).toList();
      expect(b1.length, equals(1));
      expect(b1.first.essential, isTrue);
      // β₀: n-1 finite merges + 1 essential.
      final b0Finite =
          d.pairs.where((p) => p.dimension == 0 && !p.essential).length;
      expect(b0Finite, equals(5));
      expect(d.finalCycles, equals(1));
    });
  });

  group('Euler-characteristic invariant: β₀ - β₁ = n - m', () {
    test('path satisfies the graph Euler relation', () {
      final d = computeCouplingPersistence(_path(10))!;
      final finalB0 = d.finalComponents;
      final finalB1 = d.finalCycles;
      // path(n): n-1 edges, 1 component, 0 cycles. Euler: 1 - 0 = 10 - 9.
      expect(finalB0 - finalB1, equals(10 - 9));
    });

    test('two triangles + bridge satisfies Euler relation', () {
      final d = computeCouplingPersistence(_twoTrianglesBridged())!;
      final finalB0 = d.finalComponents;
      final finalB1 = d.finalCycles;
      // 6 nodes, 7 edges, 1 component, 2 cycles. 1 - 2 = 6 - 7 = -1.
      expect(finalB0 - finalB1, equals(6 - 7));
    });
  });

  group('elder rule + bridge persistence', () {
    test('the longest β₀ bar dies at the bridge weight', () {
      // With a small bridge, the two clusters merge last. The longer of
      // the two β₀ bars associated with the two clusters should die
      // with t ≈ 1 − (0.05/wMax) after normalisation.
      final g = _twoClustersWithBridge();
      final d = computeCouplingPersistence(g)!;
      final finiteB0 = d.topB0;
      expect(finiteB0.length, equals(9));
      final longest = finiteB0.first;
      // Bridge weight 0.05; wMax is the fused value of a clique edge.
      // After wMax normalisation the bridge maps to some t close to 1;
      // any other cluster-internal merge dies at t closer to 0. So the
      // longest bar's death must exceed 0.5 comfortably.
      expect(longest.death, greaterThan(0.5),
          reason: 'cluster-spanning β₀ must die late in the filtration '
              '(got t=${longest.death}).');
    });

  });

  group('derived scalars are finite and self-consistent', () {
    test('totalPersistence equals sum of finite bar lengths', () {
      final d = computeCouplingPersistence(_twoTrianglesBridged())!;
      var handSum = 0.0;
      for (final p in d.pairs) {
        if (!p.essential) handSum += (p.death - p.birth).abs();
      }
      expect(d.totalPersistence, closeTo(handSum, 1e-12));
      expect(d.totalPersistence.isFinite, isTrue);
    });

    test('persistence entropy is in [0, log(k)]', () {
      final d = computeCouplingPersistence(_path(20))!;
      final finiteCount =
          d.pairs.where((p) => !p.essential).length;
      expect(d.persistenceEntropy, greaterThanOrEqualTo(0.0));
      // Entropy of k samples is bounded above by log(k).
      if (finiteCount > 1) {
        expect(d.persistenceEntropy,
            lessThanOrEqualTo(math.log(finiteCount.toDouble()) + 1e-9));
      }
    });
  });

  group('bar count invariants', () {
    test('finite β₀ count equals (n − finalComponents)', () {
      final d = computeCouplingPersistence(_twoTrianglesBridged())!;
      final finiteB0 =
          d.pairs.where((p) => p.dimension == 0 && !p.essential).length;
      expect(finiteB0, equals(6 - d.finalComponents));
    });

  });
}
