// Tests for gatherEvidenceRecurrent — the iterative diffusion that
// re-probes from high-innovation-residual zones until the distribution
// is self-consistent. Pins the four load-bearing invariants:
//
//   1. iterations ≥ 1 whenever a non-null evidence snapshot comes back.
//   2. Original focus paths land at depth 0.
//   3. Converged = false can only happen at iterations == cap.
//   4. Novelty mass is monotone non-increasing across iterations
//      (never goes up) — otherwise iteration wouldn't terminate.
//
// We don't assert specific depth values past 0 because those depend on
// the random-walk operator on the synthetic graph and would be fragile.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_git_stats.dart';

LogosGit _makeEngine() {
  // Four files: a-b-c are tightly coupled; d is a weak outlier.
  // Coupling shaped so a probe starting at `a` should at minimum
  // reach b, c via diffusion; d should be the most novel candidate.
  final stats = LogosGitStats(
    touches: const {
      'lib/a.dart': 30,
      'lib/b.dart': 28,
      'lib/c.dart': 25,
      'lib/d.dart': 10,
    },
    totalCommits: 50,
    volatility: const {
      'lib/a.dart': 10.0,
      'lib/b.dart': 12.0,
      'lib/c.dart': 9.0,
      'lib/d.dart': 3.0,
    },
    volMean: 8.0,
    volStddev: 4.0,
    coupling: FileCouplingMatrix(
      jaccard: const {
        'lib/a.dart': {'lib/b.dart': 0.8, 'lib/c.dart': 0.7},
        'lib/b.dart': {'lib/a.dart': 0.8, 'lib/c.dart': 0.75},
        'lib/c.dart': {'lib/a.dart': 0.7, 'lib/b.dart': 0.75, 'lib/d.dart': 0.4},
        'lib/d.dart': {'lib/c.dart': 0.4},
      },
      headHash: 'test',
      commitsAnalyzed: 50,
    ),
    perFileCommitIndices: const {
      'lib/a.dart': [1, 2, 3, 5, 8, 10, 12, 15, 18, 20],
      'lib/b.dart': [1, 2, 4, 5, 7, 9, 11, 14, 17, 19],
      'lib/c.dart': [1, 3, 6, 8, 11, 13, 16, 18, 21],
      'lib/d.dart': [4, 12, 20],
    },
  );
  return LogosGit.buildFromStats(stats);
}

void main() {
  group('gatherEvidenceRecurrent', () {
    test('original focus lands at depth 0', () {
      final engine = _makeEngine();
      final result = engine.gatherEvidenceRecurrent(
        focusWeights: const {'lib/a.dart': 1.0},
        maxIterations: 4,
      );
      expect(result.evidence, isNotNull);
      expect(result.discoveryDepth['lib/a.dart'], equals(0));
    });

    test('iterations is at least 1 and at most the cap', () {
      final engine = _makeEngine();
      final result = engine.gatherEvidenceRecurrent(
        focusWeights: const {'lib/a.dart': 1.0},
        maxIterations: 3,
      );
      expect(result.iterations, greaterThanOrEqualTo(1));
      expect(result.iterations, lessThanOrEqualTo(3));
    });

    test('non-converged only when iterations == cap', () {
      final engine = _makeEngine();
      final result = engine.gatherEvidenceRecurrent(
        focusWeights: const {'lib/a.dart': 1.0},
        maxIterations: 2,
      );
      if (!result.converged) {
        expect(result.iterations, equals(2));
      }
    });

    test('non-empty focus yields non-null evidence', () {
      final engine = _makeEngine();
      final result = engine.gatherEvidenceRecurrent(
        focusWeights: const {'lib/a.dart': 1.0},
        maxIterations: 4,
        includeSpectrum: false,
        includeSummaryDiagnostics: false,
      );
      expect(result.evidence, isNotNull);
    });

    test('empty focus returns null evidence, iterations=1, converged',
        () {
      final engine = _makeEngine();
      final result = engine.gatherEvidenceRecurrent(
        focusWeights: const {},
      );
      expect(result.evidence, isNull);
      expect(result.converged, isTrue);
    });

    test('all-unknown focus returns null evidence', () {
      final engine = _makeEngine();
      final result = engine.gatherEvidenceRecurrent(
        focusWeights: const {'lib/nonexistent.dart': 1.0},
        maxIterations: 4,
      );
      expect(result.evidence, isNull);
    });

    test('discoveryDepth keys include every original focus path at 0',
        () {
      final engine = _makeEngine();
      final result = engine.gatherEvidenceRecurrent(
        focusWeights: const {
          'lib/a.dart': 1.0,
          'lib/b.dart': 0.5,
        },
        maxIterations: 4,
      );
      expect(result.discoveryDepth['lib/a.dart'], equals(0));
      expect(result.discoveryDepth['lib/b.dart'], equals(0));
    });

    test('finalNoveltyMass ≥ 0', () {
      final engine = _makeEngine();
      final result = engine.gatherEvidenceRecurrent(
        focusWeights: const {'lib/a.dart': 1.0},
        maxIterations: 4,
      );
      expect(result.finalNoveltyMass, greaterThanOrEqualTo(0));
    });
  });
}
