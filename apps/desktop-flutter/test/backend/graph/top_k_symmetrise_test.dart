// Tests for the shared per-row top-K trim + symmetric-union
// sparsifier used by logos_hunks and logos_chunks before handing
// edges to csr_builder.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/graph/csr_builder.dart';
import 'package:git_desktop/backend/graph/top_k_symmetrise.dart';

Map<int, Map<int, double>> _symEdges(List<(int, int, double)> pairs) {
  final out = <int, Map<int, double>>{};
  for (final (a, b, w) in pairs) {
    (out[a] ??= <int, double>{})[b] = w;
    (out[b] ??= <int, double>{})[a] = w;
  }
  return out;
}

// Lookup a (u, v) edge in a CsrEdge list regardless of endpoint
// order. Returns null when absent.
double? _edgeWeight(List<CsrEdge> edges, int u, int v) {
  for (final e in edges) {
    final match = (e.u == u && e.v == v) || (e.u == v && e.v == u);
    if (match) return e.weight;
  }
  return null;
}

void main() {
  group('topKSymmetriseEdges', () {
    test('empty edges → empty output', () {
      final out = topKSymmetriseEdges(edges: const {}, topK: 5);
      expect(out, isEmpty);
    });

    test('under-budget rows keep every edge', () {
      final edges = _symEdges([
        (0, 1, 0.9),
        (0, 2, 0.4),
        (1, 2, 0.3),
      ]);
      final out = topKSymmetriseEdges(edges: edges, topK: 10);
      expect(out.length, equals(3));
      expect(_edgeWeight(out, 0, 1), closeTo(0.9, 1e-12));
      expect(_edgeWeight(out, 0, 2), closeTo(0.4, 1e-12));
      expect(_edgeWeight(out, 1, 2), closeTo(0.3, 1e-12));
    });

    test('per-row top-K keeps heaviest edges', () {
      // Node 0 has three neighbours; topK=2 keeps the two heaviest.
      // Nodes 1, 2, 3 only know node 0, so their rows are each size
      // 1 and survive unconditionally — but they also vote on which
      // of 0's edges stays (symmetric union).
      final edges = _symEdges([
        (0, 1, 0.9),
        (0, 2, 0.5),
        (0, 3, 0.1),
      ]);
      final out = topKSymmetriseEdges(edges: edges, topK: 2);
      // All three edges still survive because nodes 2/3 kept them
      // from their own row (degree-1 rows).
      expect(out.length, equals(3));
      // Sanity: every edge weight is the edge's original weight.
      expect(_edgeWeight(out, 0, 1), closeTo(0.9, 1e-12));
      expect(_edgeWeight(out, 0, 2), closeTo(0.5, 1e-12));
      expect(_edgeWeight(out, 0, 3), closeTo(0.1, 1e-12));
    });

    test('symmetric union: edge survives if either endpoint keeps it', () {
      // Node 0 has three neighbours ranked 0.9, 0.5, 0.1. Node 3
      // ALSO has three neighbours: 0 at 0.1, 4 at 0.95, 5 at 0.95.
      // Under topK=2: node 0 drops 0-3 (0.1 ranks lowest). Node 3
      // also drops 3-0 (0.1 ranks lowest vs 0.95 × 2). Neither
      // endpoint keeps it → the edge dies.
      final edges = _symEdges([
        (0, 1, 0.9),
        (0, 2, 0.5),
        (0, 3, 0.1),
        (3, 4, 0.95),
        (3, 5, 0.95),
      ]);
      final out = topKSymmetriseEdges(edges: edges, topK: 2);
      expect(_edgeWeight(out, 0, 3), isNull,
          reason: 'edge dropped by both endpoints must not survive');
      // Heaviest edges from each node remain.
      expect(_edgeWeight(out, 0, 1), isNotNull);
      expect(_edgeWeight(out, 0, 2), isNotNull);
      expect(_edgeWeight(out, 3, 4), isNotNull);
      expect(_edgeWeight(out, 3, 5), isNotNull);
    });

    test('each undirected edge appears exactly once', () {
      // Constructor sets both (a,b) and (b,a); the helper must
      // de-dupe so the same pair doesn't enter the CSR builder
      // twice (which would sum duplicates — we want identity).
      final edges = _symEdges([
        (0, 1, 0.5),
        (1, 2, 0.5),
      ]);
      final out = topKSymmetriseEdges(edges: edges, topK: 5);
      expect(out.length, equals(2));
    });

    test('weight preserved by symmetry, not halved or doubled', () {
      final edges = _symEdges([(3, 7, 0.42)]);
      final out = topKSymmetriseEdges(edges: edges, topK: 5);
      expect(out.length, equals(1));
      expect(_edgeWeight(out, 3, 7), closeTo(0.42, 1e-12));
    });

    test('topK=0 drops all edges from the keep list', () {
      // Degenerate limit. Useful for tests pinning that the policy
      // is read correctly, though production code never calls this.
      final edges = _symEdges([
        (0, 1, 0.9),
        (1, 2, 0.3),
      ]);
      final out = topKSymmetriseEdges(edges: edges, topK: 0);
      expect(out, isEmpty);
    });
  });
}
