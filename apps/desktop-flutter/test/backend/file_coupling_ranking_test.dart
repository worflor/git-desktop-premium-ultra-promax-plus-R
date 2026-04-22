// Tests for the canonical ranking API on FileCouplingMatrix.
// These methods are the single source of truth for "who are this
// file's co-change partners?" and "how central is each file in the
// co-change graph?" — call sites in changes_page.dart and
// commit_tagger.dart route through them instead of hand-rolling
// thresholded sorts or Σ-jaccard loops.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';

FileCouplingMatrix _matrix(Map<String, Map<String, double>> jaccard) =>
    FileCouplingMatrix(
      jaccard: jaccard,
      headHash: 'test',
      commitsAnalyzed: 200,
    );

void main() {
  group('FileCouplingMatrix.fullJaccardRowOf', () {
    test('sees neighbours from both triangles', () {
      // `a.dart` is the lex-smallest path; it holds the upper-triangle
      // row for the a↔b and a↔c edges. The row for `c.dart` (stored
      // upper-triangle) is empty of a/b, so naive `jaccardEntriesOf`
      // misses them — `fullJaccardRowOf` recovers them.
      final m = _matrix({
        'a.dart': {'b.dart': 0.8, 'c.dart': 0.3},
      });

      final neighboursOfC =
          m.fullJaccardRowOf('c.dart').map((e) => e.key).toSet();
      expect(neighboursOfC, contains('a.dart'));

      final scoredOfC = {
        for (final e in m.fullJaccardRowOf('c.dart')) e.key: e.value,
      };
      expect(scoredOfC['a.dart'], closeTo(0.3, 1e-12));
    });

    test('unknown path yields empty', () {
      final m = _matrix({
        'a.dart': {'b.dart': 0.5},
      });
      expect(m.fullJaccardRowOf('missing.dart'), isEmpty);
    });

    test('symmetric: A lists B iff B lists A with same score', () {
      final m = _matrix({
        'alpha.dart': {'omega.dart': 0.42},
      });
      final fromAlpha = {
        for (final e in m.fullJaccardRowOf('alpha.dart')) e.key: e.value,
      };
      final fromOmega = {
        for (final e in m.fullJaccardRowOf('omega.dart')) e.key: e.value,
      };
      expect(fromAlpha['omega.dart'], closeTo(0.42, 1e-12));
      expect(fromOmega['alpha.dart'], closeTo(0.42, 1e-12));
    });
  });

  group('FileCouplingMatrix.topJaccardNeighbours', () {
    test('ranks descending and respects limit', () {
      final m = _matrix({
        'a.dart': {'b.dart': 0.9, 'c.dart': 0.3, 'd.dart': 0.6},
      });
      final top2 = m.topJaccardNeighbours('a.dart', limit: 2);
      expect(top2.length, equals(2));
      expect(top2[0].key, equals('b.dart'));
      expect(top2[1].key, equals('d.dart'));
    });

    test('minScore filters below threshold', () {
      final m = _matrix({
        'a.dart': {'b.dart': 0.2, 'c.dart': 0.05, 'd.dart': 0.5},
      });
      final filtered = m.topJaccardNeighbours('a.dart', minScore: 0.15);
      expect(filtered.map((e) => e.key).toList(), equals(['d.dart', 'b.dart']));
    });

    test('symmetric for lex-late paths too', () {
      // The bug in the old hand-rolled code: `zz.dart`'s upper-triangle
      // row is empty of a/b, so jaccardEntriesOf returned nothing.
      final m = _matrix({
        'a.dart': {'zz.dart': 0.7},
        'b.dart': {'zz.dart': 0.4},
      });
      final topForZz = m.topJaccardNeighbours('zz.dart');
      expect(topForZz.length, equals(2));
      expect(topForZz[0].key, equals('a.dart'));
      expect(topForZz[1].key, equals('b.dart'));
    });

    test('empty when all neighbours below minScore', () {
      final m = _matrix({
        'a.dart': {'b.dart': 0.05},
      });
      expect(m.topJaccardNeighbours('a.dart', minScore: 0.5), isEmpty);
    });
  });

  group('FileCouplingMatrix.jaccardMaxNeighborMap', () {
    test('max over both triangles for every path', () {
      final m = _matrix({
        'a.dart': {'b.dart': 0.5, 'c.dart': 0.3},
        'b.dart': {'c.dart': 0.8},
      });
      final mx = m.jaccardMaxNeighborMap();
      // a sees 0.5 (a-b) and 0.3 (a-c) → 0.5
      // b sees 0.5 (a-b) and 0.8 (b-c) → 0.8
      // c sees 0.3 (a-c) and 0.8 (b-c) → 0.8
      expect(mx['a.dart'], closeTo(0.5, 1e-12));
      expect(mx['b.dart'], closeTo(0.8, 1e-12));
      expect(mx['c.dart'], closeTo(0.8, 1e-12));
    });

    test('symmetric for lex-late paths (no upper-triangle bug)', () {
      final m = _matrix({
        'a.dart': {'zz.dart': 0.7},
        'b.dart': {'zz.dart': 0.4},
      });
      final mx = m.jaccardMaxNeighborMap();
      expect(mx['zz.dart'], closeTo(0.7, 1e-12));
      expect(mx['a.dart'], closeTo(0.7, 1e-12));
      expect(mx['b.dart'], closeTo(0.4, 1e-12));
    });

    test('restrict requires BOTH endpoints in the subset', () {
      final m = _matrix({
        'a.dart': {'b.dart': 0.9, 'c.dart': 0.1},
        'b.dart': {'c.dart': 0.5},
      });
      // Subset {a, c}: only the a↔c edge (0.1) has both endpoints
      // in the subset. a-b and b-c both reach out of the subset
      // through b and do not contribute. This matches the
      // _rankedByImpact semantic "max jaccard to an in-diff peer."
      final mx = m.jaccardMaxNeighborMap(restrict: {'a.dart', 'c.dart'});
      expect(mx['a.dart'], closeTo(0.1, 1e-12));
      expect(mx['c.dart'], closeTo(0.1, 1e-12));
      expect(mx['b.dart'], equals(0.0)); // out-of-subset → 0
    });

    test('parity with per-path subset-filtered fullJaccardRowOf', () {
      // Regression pin: no matter which subset we pick,
      // jaccardMaxNeighborMap(restrict: S) must match the brute-force
      // "max over S ∩ neighbours(p)" computation that the old
      // _rankedByImpact loop was performing.
      final m = _matrix({
        'a.dart': {'b.dart': 0.9, 'c.dart': 0.3, 'd.dart': 0.1},
        'b.dart': {'c.dart': 0.2, 'd.dart': 0.6},
        'c.dart': {'d.dart': 0.8},
      });
      final subset = {'a.dart', 'b.dart', 'c.dart'};
      final mx = m.jaccardMaxNeighborMap(restrict: subset);
      for (final p in subset) {
        var expected = 0.0;
        for (final e in m.fullJaccardRowOf(p)) {
          if (!subset.contains(e.key)) continue;
          if (e.value > expected) expected = e.value;
        }
        expect(mx[p], closeTo(expected, 1e-12),
            reason: 'subset-max parity for $p');
      }
    });

    test('restrict with single path yields 0 (no in-subset partner)', () {
      // A singleton subset has no in-subset partner for its one member,
      // so the "both endpoints in subset" rule forces best[a] = 0.
      // The returned map still covers every path in the matrix.
      final m = _matrix({
        'a.dart': {'b.dart': 0.5},
        'b.dart': {'c.dart': 0.5},
      });
      final mx = m.jaccardMaxNeighborMap(restrict: {'a.dart'});
      expect(mx.containsKey('a.dart'), isTrue);
      expect(mx.containsKey('b.dart'), isTrue);
      expect(mx.containsKey('c.dart'), isTrue);
      expect(mx['a.dart'], equals(0.0));
      expect(mx['b.dart'], equals(0.0));
      expect(mx['c.dart'], equals(0.0));
    });

    test('matches per-path max from fullJaccardRowOf', () {
      // Regression pin: whatever jaccardMaxNeighborMap returns must
      // equal the per-path max derived from the canonical full-row
      // iterator, because that's exactly what _rankedByImpact was
      // computing before the optimization.
      final m = _matrix({
        'a.dart': {'b.dart': 0.9, 'c.dart': 0.3, 'd.dart': 0.1},
        'b.dart': {'c.dart': 0.2, 'd.dart': 0.6},
        'c.dart': {'d.dart': 0.8},
      });
      final mx = m.jaccardMaxNeighborMap();
      for (final path in ['a.dart', 'b.dart', 'c.dart', 'd.dart']) {
        var expected = 0.0;
        for (final e in m.fullJaccardRowOf(path)) {
          if (e.value > expected) expected = e.value;
        }
        expect(mx[path], closeTo(expected, 1e-12),
            reason: 'max parity for $path');
      }
    });

    test('restrict with unknown paths just filters them silently', () {
      final m = _matrix({
        'a.dart': {'b.dart': 0.5},
      });
      // `ghost.dart` doesn't exist in the matrix, so the effective
      // subset is {a.dart} — a singleton with no in-subset partner.
      final mx = m.jaccardMaxNeighborMap(restrict: {'a.dart', 'ghost.dart'});
      expect(mx['a.dart'], equals(0.0));
      expect(mx['b.dart'], equals(0.0));
    });
  });

  group('FileCouplingMatrix.jaccardCentralityMap', () {
    test('sums incident jaccard weights for every path', () {
      final m = _matrix({
        'a.dart': {'b.dart': 0.5, 'c.dart': 0.3},
        'b.dart': {'c.dart': 0.2},
      });
      final cent = m.jaccardCentralityMap();
      // a: 0.5 (a-b) + 0.3 (a-c) = 0.8
      // b: 0.5 (a-b) + 0.2 (b-c) = 0.7
      // c: 0.3 (a-c) + 0.2 (b-c) = 0.5
      expect(cent['a.dart'], closeTo(0.8, 1e-12));
      expect(cent['b.dart'], closeTo(0.7, 1e-12));
      expect(cent['c.dart'], closeTo(0.5, 1e-12));
    });

    test('isolated paths present with zero', () {
      final m = _matrix({
        'a.dart': {'b.dart': 0.5},
        // 'island.dart' appears as a path via symbol overlay or…
        // well here we just add it in jaccard but with no partners:
        // the constructor collects union of keys + sub-keys so we
        // include it via a self-free edge set.
        'island.dart': <String, double>{},
      });
      final cent = m.jaccardCentralityMap();
      // When the inner map is empty there's no edge materialised, but
      // the path still appears in the universe because the outer key
      // was present.
      expect(cent.containsKey('island.dart'), isTrue);
      expect(cent['island.dart'], equals(0.0));
    });

    test('matches per-path full row sum', () {
      final m = _matrix({
        'a.dart': {'b.dart': 0.5, 'c.dart': 0.3},
        'b.dart': {'c.dart': 0.2},
      });
      final cent = m.jaccardCentralityMap();
      for (final path in ['a.dart', 'b.dart', 'c.dart']) {
        var perPath = 0.0;
        for (final e in m.fullJaccardRowOf(path)) {
          perPath += e.value;
        }
        expect(cent[path], closeTo(perPath, 1e-12),
            reason: 'centrality for $path should equal its full row sum');
      }
    });
  });
}
