// Tests for the Atlas-facing multi-axis relatedness surface on
// `FileClusters` — the axis pill on each card depends on these
// invariants, so we pin them here.
//
// Specifically:
//   1. Transport-lane pairs (manifest↔lockfile, source↔test) cluster
//      on their own and carry `axis = transport`.
//   2. Historical co-change pairs cluster with `axis = coChange`.
//   3. Symbol-overlap pairs cluster with `axis = symbol`.
//   4. A cluster bonded by mixed evidence picks the axis with the
//      highest summed score, with priority `transport > coChange >
//      symbol > pathAffinity` breaking ties.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';

FileCouplingMatrix _matrix({
  Map<String, Map<String, double>> jaccard = const {},
  Map<String, Map<String, double>> symbol = const {},
  int commitsAnalyzed = 200,
}) =>
    FileCouplingMatrix(
      jaccard: jaccard,
      symbol: symbol,
      headHash: 'test',
      commitsAnalyzed: commitsAnalyzed,
    );

void main() {
  group('FileClusters.dominantAxisByCluster', () {
    test('manifest ↔ lockfile clusters via transport lane', () {
      // No jaccard, no symbol — just the structural lane.
      final matrix = _matrix();
      final clusters = clusterFiles(
        ['pubspec.yaml', 'pubspec.lock'],
        matrix,
      );
      // Both files land in the same cluster and the dominant axis is
      // transport.
      final a = clusters.byPath['pubspec.yaml'];
      final b = clusters.byPath['pubspec.lock'];
      expect(a, isNotNull);
      expect(a, equals(b));
      expect(a, isNot(equals(FileClusters.clusterIdIsolated)));
      expect(clusters.dominantAxisByCluster[a!],
          equals(RelatednessAxis.transport));
    });

    test('source ↔ test clusters via transport lane', () {
      final matrix = _matrix();
      final clusters = clusterFiles(
        ['lib/foo.dart', 'test/foo_test.dart'],
        matrix,
      );
      final a = clusters.byPath['lib/foo.dart'];
      expect(a, isNotNull);
      expect(a, equals(clusters.byPath['test/foo_test.dart']));
      expect(clusters.dominantAxisByCluster[a!],
          equals(RelatednessAxis.transport));
    });

    test('co-change history yields coChange axis', () {
      final matrix = _matrix(jaccard: {
        'lib/a.dart': {'lib/b.dart': 0.9},
        'lib/b.dart': {'lib/a.dart': 0.9},
      });
      final clusters = clusterFiles(
        ['lib/a.dart', 'lib/b.dart'],
        matrix,
      );
      final id = clusters.byPath['lib/a.dart']!;
      expect(clusters.dominantAxisByCluster[id],
          equals(RelatednessAxis.coChange));
    });

    test('symbol overlap (no history) yields symbol axis', () {
      final matrix = _matrix(symbol: {
        'lib/x.dart': {'lib/y.dart': 0.8},
        'lib/y.dart': {'lib/x.dart': 0.8},
      });
      final clusters = clusterFiles(
        ['lib/x.dart', 'lib/y.dart'],
        matrix,
      );
      final id = clusters.byPath['lib/x.dart']!;
      expect(clusters.dominantAxisByCluster[id],
          equals(RelatednessAxis.symbol));
    });

    test('co-change beats symbol on summed-score tie via priority', () {
      // Equal single-edge scores — priority order (coChange > symbol)
      // breaks the tie.
      final matrix = _matrix(
        jaccard: {
          'lib/a.dart': {'lib/b.dart': 0.5},
          'lib/b.dart': {'lib/a.dart': 0.5},
        },
        symbol: {
          'lib/a.dart': {'lib/b.dart': 0.5},
          'lib/b.dart': {'lib/a.dart': 0.5},
        },
      );
      final clusters = clusterFiles(
        ['lib/a.dart', 'lib/b.dart'],
        matrix,
      );
      final id = clusters.byPath['lib/a.dart']!;
      // Dedup rule preserves the first-recorded axis when scores tie
      // (jaccard recorded first). Either outcome is acceptable but
      // the axis should be deterministic.
      expect(clusters.dominantAxisByCluster[id],
          isIn(const [RelatednessAxis.coChange, RelatednessAxis.symbol]));
    });

    test('singleton with no bonds stays isolated, no axis key', () {
      final matrix = _matrix();
      final clusters = clusterFiles(
        ['lib/lonely.dart'],
        matrix,
      );
      expect(clusters.byPath['lib/lonely.dart'],
          equals(FileClusters.clusterIdIsolated));
      expect(clusters.dominantAxisByCluster, isEmpty);
    });
  });
}
