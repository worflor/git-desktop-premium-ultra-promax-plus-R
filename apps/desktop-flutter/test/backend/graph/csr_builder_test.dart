import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/graph/csr_builder.dart';

void main() {
  group('buildSymmetricCsrGraph', () {
    test('empty edge list yields isolated nodes', () {
      final g = buildSymmetricCsrGraph(n: 3, edges: const []);
      expect(g.n, 3);
      expect(g.indptr.toList(), [0, 0, 0, 0]);
      expect(g.indices.length, 0);
      expect(g.values.length, 0);
      expect(g.degreeInvSqrt.toList(), [0.0, 0.0, 0.0]);
    });

    test('stores every edge in both rows (symmetric)', () {
      final g = buildSymmetricCsrGraph(
        n: 3,
        edges: const [CsrEdge(0, 1, 2.0), CsrEdge(1, 2, 1.0)],
      );
      // Row 0: [1], row 1: [0, 2] (sorted), row 2: [1].
      expect(g.indptr.toList(), [0, 1, 3, 4]);
      expect(g.indices.toList(), [1, 0, 2, 1]);
      expect(g.rawWeights.toList(), [2.0, 2.0, 1.0, 1.0]);
    });

    test('fuses D^{-1/2} W D^{-1/2} normalisation', () {
      // Single edge between two nodes, weight 4.
      // deg(0) = deg(1) = 4, D^{-1/2} = 0.5.
      // Fused value = 0.5 * 4 * 0.5 = 1.0.
      final g = buildSymmetricCsrGraph(
        n: 2, edges: const [CsrEdge(0, 1, 4.0)],
      );
      expect(g.values[0], closeTo(1.0, 1e-12));
      expect(g.values[1], closeTo(1.0, 1e-12));
      expect(g.degreeInvSqrt[0], closeTo(0.5, 1e-12));
    });

    test('drops self-loops, zero, and non-finite weights', () {
      final g = buildSymmetricCsrGraph(
        n: 3,
        edges: [
          const CsrEdge(0, 0, 1.0),          // self-loop
          const CsrEdge(0, 1, 0.0),          // zero weight
          const CsrEdge(0, 2, double.nan),   // NaN
          const CsrEdge(1, 2, -0.5),         // negative
          const CsrEdge(0, 1, 3.0),          // keeper
        ],
      );
      expect(g.indptr.toList(), [0, 1, 2, 2]);
      expect(g.indices.toList(), [1, 0]);
      expect(g.rawWeights.toList(), [3.0, 3.0]);
    });

    test('sums duplicate edges', () {
      final g = buildSymmetricCsrGraph(
        n: 2,
        edges: const [CsrEdge(0, 1, 1.0), CsrEdge(1, 0, 2.0)],
      );
      // Both submissions name the same undirected edge → sum to 3.
      expect(g.rawWeights.toList(), [3.0, 3.0]);
    });

    test('out-of-range edge throws', () {
      expect(
        () => buildSymmetricCsrGraph(
          n: 2, edges: const [CsrEdge(0, 3, 1.0)],
        ),
        throwsRangeError,
      );
    });

    test('row slices are sorted ascending by column id', () {
      // Node 0 connects to 3, 1, 2 in that order of submission.
      final g = buildSymmetricCsrGraph(
        n: 4,
        edges: const [
          CsrEdge(0, 3, 1.0), CsrEdge(0, 1, 1.0), CsrEdge(0, 2, 1.0),
        ],
      );
      // Row 0's slice must be [1, 2, 3].
      final start = g.indptr[0];
      final end = g.indptr[1];
      final slice = g.indices.sublist(start, end);
      expect(slice, [1, 2, 3]);
    });
  });
}
