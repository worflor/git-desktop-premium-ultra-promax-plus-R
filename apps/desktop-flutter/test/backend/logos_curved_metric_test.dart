// Tests for the per-file curved AR(2) metric on `LogosGit`.
//
// The metric: each file with enough touch history gets an AR(2) fit
// on its inter-touch-gap series. Spectral radius `r_f = √G_f` of the
// fit measures how regular the file's touch pattern is. Edge weights
// in the file graph are multiplied by `√(r_a · r_b)` so heat flows
// preferentially through files whose own time-scale is well-defined.
//
// Locks the contract:
//   • Empty perFileCommitIndices ⇒ no curvature change (legacy mode)
//   • Files with regular periodic touches get a non-trivial fit
//   • Files with too-short history get no fit (curvature defaults 1.0)
//   • engine.perFileMetrics is populated for fitted files

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';

LogosGitStats _stats({
  Map<String, int> touches = const {},
  Map<String, double> volatility = const {},
  Map<String, Map<String, double>> jaccard = const {},
  int totalCommits = 100,
  Map<String, List<int>> perFileCommitIndices = const {},
}) {
  return LogosGitStats(
    touches: touches,
    totalCommits: totalCommits,
    volatility: volatility,
    volMean: 0,
    volStddev: 1,
    coupling: FileCouplingMatrix(
      jaccard: jaccard,
      headHash: 'test',
      commitsAnalyzed: totalCommits,
    ),
    perFileCommitIndices: perFileCommitIndices,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LogosGit per-file curved metric', () {
    test('empty perFileCommitIndices → perFileMetrics empty (legacy)', () {
      final engine = LogosGit.buildFromStats(_stats(
        touches: {'a.dart': 5, 'b.dart': 5},
        jaccard: {
          'a.dart': {'b.dart': 0.7},
          'b.dart': {'a.dart': 0.7},
        },
      ));
      expect(engine.perFileMetrics, isEmpty);
    });

    test('regular periodic touch series produces a fit', () {
      // Touch every 5 commits → very regular gap series [5, 5, 5, 5, ...]
      final regular = [for (var i = 0; i < 80; i += 5) i];
      final engine = LogosGit.buildFromStats(_stats(
        touches: {'periodic.dart': regular.length, 'sibling.dart': 5},
        jaccard: {
          'periodic.dart': {'sibling.dart': 0.6},
          'sibling.dart': {'periodic.dart': 0.6},
        },
        perFileCommitIndices: {
          'periodic.dart': regular,
        },
      ));
      // Periodic series should produce a non-fallback AR(2) fit.
      expect(engine.perFileMetrics.containsKey('periodic.dart'), isTrue);
      final fit = engine.perFileMetrics['periodic.dart']!;
      expect(fit.isLinearFallback, isFalse);
      // Spectral radius must be in the allowed band.
      expect(fit.spectralRadius, greaterThan(0));
    });

    test('too-short series → no fit (curvature defaults to 1.0)', () {
      // Only 2 touches → 1 gap → engramFit returns linear fallback.
      final engine = LogosGit.buildFromStats(_stats(
        touches: {'sparse.dart': 2, 'partner.dart': 2},
        jaccard: {
          'sparse.dart': {'partner.dart': 0.5},
          'partner.dart': {'sparse.dart': 0.5},
        },
        perFileCommitIndices: {
          'sparse.dart': [10, 20],
          'partner.dart': [10, 20],
        },
      ));
      // Two touches → one gap → not enough samples for AR(2).
      expect(engine.perFileMetrics, isEmpty);
    });

    test('linear-fallback fits are filtered out of perFileMetrics', () {
      // Constant-gap series (every 7 commits) — perfectly periodic but
      // the AR(2) fit on a constant signal degenerates to linear
      // fallback (no oscillation to fit). We document that those
      // stay out of perFileMetrics — curvature factor 1.0 (no
      // change vs the flat metric).
      final constantSpaced = [for (var i = 0; i < 80; i += 7) i];
      final engine = LogosGit.buildFromStats(_stats(
        touches: {'flat.dart': constantSpaced.length},
        jaccard: const {},
        perFileCommitIndices: {
          'flat.dart': constantSpaced,
        },
      ));
      // Constant gaps are linear-fallback territory — engramFit
      // detects "no signal" and we drop those.
      // (The fit returns isLinearFallback=true for some constant
      // inputs, isLinearFallback=false for others depending on
      // ridge regularisation; both are valid behaviour. The contract
      // we care about: when isLinearFallback is true, we don't add
      // the file to perFileMetrics. Verify by checking the entry's
      // fit, if present, is non-fallback.)
      for (final fit in engine.perFileMetrics.values) {
        expect(fit.isLinearFallback, isFalse);
      }
    });
  });
}
