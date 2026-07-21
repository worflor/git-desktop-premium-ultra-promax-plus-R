// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Tests for the Atlas-facing multi-axis relatedness surface on
// `FileClusters` — the axis pill on each card depends on these
// invariants, so we pin them here.
//
// Specifically:
//   1. Transport-lane pairs (manifest↔lockfile, source↔test) cluster
//      on their own and carry `axis = transport`.
//   2. Historical co-change pairs cluster with `axis = coChange`.
//   3. Spectral-profile pairs cluster with `axis = spectralProfile`.
//   4. A cluster bonded by mixed evidence picks the axis with the
//      highest summed score, with priority `spectral > transport >
//      spectralProfile > hunk > coChange > pathAffinity` breaking
//      ties between distinct axes.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';

FileCouplingMatrix _matrix({
  Map<String, Map<String, double>> jaccard = const {},
  Map<String, Map<String, double>> spectral = const {},
  int commitsAnalyzed = 200,
}) =>
    FileCouplingMatrix(
      jaccard: jaccard,
      spectral: spectral,
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

    test('spectral overlap (no history) yields spectralProfile axis', () {
      final matrix = _matrix(spectral: {
        'lib/x.dart': {'lib/y.dart': 0.8},
        'lib/y.dart': {'lib/x.dart': 0.8},
      });
      final clusters = clusterFiles(
        ['lib/x.dart', 'lib/y.dart'],
        matrix,
      );
      final id = clusters.byPath['lib/x.dart']!;
      expect(clusters.dominantAxisByCluster[id],
          equals(RelatednessAxis.spectralProfile));
    });

    test('equal-score jaccard+spectral pair keeps first-recorded axis', () {
      // Same pair fires on both jaccard (coChange) and spectral
      // (spectralProfile) at an identical 0.5. recordPair promotes only
      // on a strictly-greater score, so the first-recorded axis survives
      // as the pair's single _PairScore — and the jaccard CSR is walked
      // before the spectral CSR, so coChange wins. The _axisPriority
      // tiebreak never engages here: only one axis ever reaches the
      // per-cluster vote tally.
      final matrix = _matrix(
        jaccard: {
          'lib/a.dart': {'lib/b.dart': 0.5},
          'lib/b.dart': {'lib/a.dart': 0.5},
        },
        spectral: {
          'lib/a.dart': {'lib/b.dart': 0.5},
          'lib/b.dart': {'lib/a.dart': 0.5},
        },
      );
      final clusters = clusterFiles(
        ['lib/a.dart', 'lib/b.dart'],
        matrix,
      );
      final id = clusters.byPath['lib/a.dart']!;
      // Deterministic: the first-recorded axis (coChange) wins the tie.
      expect(clusters.dominantAxisByCluster[id],
          equals(RelatednessAxis.coChange));
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
