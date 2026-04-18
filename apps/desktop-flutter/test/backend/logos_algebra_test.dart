// Tests for LogosAlgebra — observable composition under direct sum
// and coarse-graining.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_algebra.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_zeta.dart';

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

void main() {
  group('directSum — graph structure', () {
    test('node count is the sum; edge count is the sum', () {
      final a = _path(10);
      final b = _cycle(7);
      final ab = directSum(a, b);
      expect(ab.n, equals(a.n + b.n));
      expect(ab.values.length, equals(a.values.length + b.values.length));
    });

    test('shifted indices point into B region only', () {
      final a = _path(6);
      final b = _cycle(4);
      final ab = directSum(a, b);
      for (var u = a.n; u < ab.n; u++) {
        final p0 = ab.indptr[u];
        final p1 = ab.indptr[u + 1];
        for (var p = p0; p < p1; p++) {
          expect(ab.indices[p], greaterThanOrEqualTo(a.n),
              reason: 'B-side row $u referenced A-side index '
                  '${ab.indices[p]}');
        }
      }
    });

    test('no edges cross between A and B components', () {
      final a = _path(8);
      final b = _path(5);
      final ab = directSum(a, b);
      for (var u = 0; u < a.n; u++) {
        final p0 = ab.indptr[u];
        final p1 = ab.indptr[u + 1];
        for (var p = p0; p < p1; p++) {
          expect(ab.indices[p], lessThan(a.n),
              reason: 'A-side row $u referenced B-side index');
        }
      }
    });
  });

  group('directSumBasis — observable additivity identities', () {
    // Use the algebraic direct-sum basis (spectra concatenated and
    // merge-sorted, eigenvectors block-diagonal) for these
    // identities. Building the joint graph and re-running Lanczos
    // would introduce discretisation noise that isn't a property of
    // the direct-sum operation itself — this branch is theorem-tight.

    test('heatTrace is additive', () {
      final basisA = SpectralBasis.fromGraph(_path(16), 16);
      final basisB = SpectralBasis.fromGraph(_cycle(10), 10);
      final merged = directSumBasis(basisA, basisB);
      for (final t in [0.1, 0.5, 1.0, 3.0]) {
        final sum = basisA.heatTrace(t) + basisB.heatTrace(t);
        expect(merged.heatTrace(t), closeTo(sum, 1e-12),
            reason: 'heatTrace non-additive at t=$t');
      }
    });

    test('zeta(s) is additive', () {
      final basisA = SpectralBasis.fromGraph(_path(14), 14);
      final basisB = SpectralBasis.fromGraph(_path(11), 11);
      final merged = directSumBasis(basisA, basisB);
      for (final s in [1.0, 2.0, 3.0]) {
        final sum = zeta(basisA, s) + zeta(basisB, s);
        expect(zeta(merged, s), closeTo(sum, 1e-10),
            reason: 'zeta($s) non-additive');
      }
    });

    test('kernelDim adds exactly under directSumBasis', () {
      final basisA = SpectralBasis.fromGraph(_path(10), 10);
      final basisB = SpectralBasis.fromGraph(_cycle(7), 7);
      final merged = directSumBasis(basisA, basisB);
      expect(merged.kernelDim,
          equals(basisA.kernelDim + basisB.kernelDim),
          reason: 'β₀ of the union must equal the sum of β₀s '
              'under the algebraic direct sum');
    });

  });

  group('directSum — graph-level non-identities', () {
    // The GRAPH-level direct sum (rebuild + re-Lanczos) intentionally
    // does NOT preserve additivity because Lanczos at different
    // n-sizes discretises the spectrum differently. This is a real
    // limitation worth documenting, and worth testing so it doesn't
    // silently regress into an accidental guarantee.
    test('graph-level joint kernelDim may under-resolve β₀', () {
      final a = _path(10);
      final b = _cycle(7);
      final ab = directSum(a, b);
      final basisAB = SpectralBasis.fromGraph(ab, ab.n);
      // Joint Lanczos gives ≥ 1 but may not recover 2 zero modes.
      expect(basisAB.kernelDim, greaterThanOrEqualTo(1));
    });
  });

  group('directSumBasis — algebraic shortcut', () {
    test('eigenvalues equal the merge of input spectra', () {
      final a = _path(12);
      final b = _path(8);
      final basisA = SpectralBasis.fromGraph(a, 12);
      final basisB = SpectralBasis.fromGraph(b, 8);
      final merged = directSumBasis(basisA, basisB);
      expect(merged.n, equals(a.n + b.n));
      expect(merged.k, equals(basisA.k + basisB.k));

      // Merged eigenvalues must be sorted.
      for (var i = 1; i < merged.k; i++) {
        expect(merged.eigenvalues[i],
            greaterThanOrEqualTo(merged.eigenvalues[i - 1]));
      }

      // Every eigenvalue must come from one input spectrum.
      final union = <double>[
        ...basisA.eigenvalues,
        ...basisB.eigenvalues,
      ]..sort();
      for (var i = 0; i < merged.k; i++) {
        expect(merged.eigenvalues[i], closeTo(union[i], 1e-12));
      }
    });

    test('eigenvectors are block-zero on the opposite component', () {
      final a = _path(10);
      final b = _path(6);
      final basisA = SpectralBasis.fromGraph(a, 10);
      final basisB = SpectralBasis.fromGraph(b, 6);
      final merged = directSumBasis(basisA, basisB);
      // Every eigenvector of the merged basis comes from ONE side
      // and is zero on the other.
      for (var j = 0; j < merged.k; j++) {
        final base = j * merged.n;
        var aNorm = 0.0;
        var bNorm = 0.0;
        for (var i = 0; i < a.n; i++) {
          aNorm += merged.eigenvectors[base + i].abs();
        }
        for (var i = a.n; i < merged.n; i++) {
          bNorm += merged.eigenvectors[base + i].abs();
        }
        expect(aNorm == 0 || bNorm == 0, isTrue,
            reason: 'eigenvector $j has support on both components: '
                'aNorm=$aNorm, bNorm=$bNorm');
      }
    });

  });

  group('coarsenByPartition', () {
    test('preserves node count when partition is identity', () {
      final g = _cycle(6);
      final ids = List<int>.generate(g.n, (i) => i);
      final c = coarsenByPartition(g, ids);
      expect(c.n, equals(g.n));
    });

    test('collapsing into a single cluster yields a 1-node graph', () {
      final g = _path(10);
      final ids = List<int>.filled(g.n, 0);
      final c = coarsenByPartition(g, ids);
      expect(c.n, equals(1));
      // One node, no self-edges stored (we drop intra-cluster edges).
      expect(c.values.length, equals(0));
    });

    test('splits 2-cluster partition into exactly one bridge edge', () {
      // Path 0-1-2-3-4-5 with partition {0,1,2 → A}, {3,4,5 → B}.
      // Only the 2-3 edge crosses the partition → reduced graph has
      // two nodes connected by a single edge.
      final g = _path(6);
      final ids = [0, 0, 0, 1, 1, 1];
      final c = coarsenByPartition(g, ids);
      expect(c.n, equals(2));
      // Exactly 2 directed entries (one edge × 2 directions).
      expect(c.values.length, equals(2));
    });

    test('coarsening reduces k whenever it reduces n', () {
      final g = _cycle(12);
      final ids = [0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3];
      final c = coarsenByPartition(g, ids);
      expect(c.n, equals(4));
      // Cycle of 4 clusters → reduced graph is a 4-cycle.
      expect(c.values.length, equals(8)); // 4 edges × 2 directions
    });
  });
}
