// Tests for the emergent review-scoring pipeline.
//
// Each axis gets its own group. The assertions are **relative** —
// grounded claims score higher than hallucinated ones, hub claims
// reach further than leaf claims — rather than pinning absolute
// thresholds. That keeps the tests resilient to spectrum tuning
// while still catching any regression that erases the signal.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_git_stats.dart';
import 'package:git_desktop/backend/review_logos.dart';
import 'package:git_desktop/backend/review_ratchet.dart';

/// Two-cluster engine: `left.*` files couple tightly with each
/// other, `right.*` files couple tightly with each other, and the
/// two halves share a single bridge edge `left/a ↔ right/a`. This
/// geometry gives us both clear "same-cluster coherence" and clear
/// "cross-cluster incoherence" signals — the tests rely on that.
LogosGit _dumbbellEngine() {
  final matrix = FileCouplingMatrix(
    jaccard: {
      'left/a.dart': {
        'left/b.dart': 0.8,
        'left/c.dart': 0.6,
        'right/a.dart': 0.15,
      },
      'left/b.dart': {'left/a.dart': 0.8, 'left/c.dart': 0.7},
      'left/c.dart': {'left/a.dart': 0.6, 'left/b.dart': 0.7},
      'right/a.dart': {
        'right/b.dart': 0.8,
        'right/c.dart': 0.6,
        'left/a.dart': 0.15,
      },
      'right/b.dart': {'right/a.dart': 0.8, 'right/c.dart': 0.7},
      'right/c.dart': {'right/a.dart': 0.6, 'right/b.dart': 0.7},
    },
    headHash: 'dumbbell',
    commitsAnalyzed: 200,
  );
  final paths = [
    'left/a.dart',
    'left/b.dart',
    'left/c.dart',
    'right/a.dart',
    'right/b.dart',
    'right/c.dart',
  ];
  return LogosGit.buildFromStats(LogosGitStats(
    touches: {for (final p in paths) p: 10},
    totalCommits: 200,
    volatility: {for (final p in paths) p: 1.0},
    volMean: 1.0,
    volStddev: 0.5,
    coupling: matrix,
    perFileCommitIndices: {
      for (final p in paths)
        p: const [10, 40, 70, 100, 130, 160, 190],
    },
  ));
}

/// Synthetic "diff" text that names the given files in git's usual
/// `diff --git` header form. Sufficient for
/// [extractDiffTouchedPaths] to pick the touched set up without us
/// needing a real working tree.
String _syntheticDiffFor(Iterable<String> paths) {
  final buf = StringBuffer();
  for (final p in paths) {
    buf
      ..writeln('diff --git a/$p b/$p')
      ..writeln('--- a/$p')
      ..writeln('+++ b/$p')
      ..writeln('@@ -1,1 +1,1 @@')
      ..writeln('-old line')
      ..writeln('+new line');
  }
  return buf.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Axis 1 — grounding via counter-diffusion', () {
    test('grounded claim scores higher than hallucinated claim', () {
      final engine = _dumbbellEngine();
      final diffText = _syntheticDiffFor(['left/a.dart', 'left/b.dart']);
      final diffPaths = {'left/a.dart', 'left/b.dart'};

      // A grounded claim names symbols from the same cluster as the
      // diff — should cosine high.
      final grounded = groundingConsistency(
        engine: engine,
        claimPaths: {'left/c.dart'},
        diffTouchedPaths: diffPaths,
      );

      // A hallucinated claim names symbols from the opposite cluster
      // (only weakly connected via one bridge edge) — should cosine low.
      final hallucinated = groundingConsistency(
        engine: engine,
        claimPaths: {'right/b.dart', 'right/c.dart'},
        diffTouchedPaths: diffPaths,
      );

      expect(grounded, greaterThan(hallucinated + 0.15),
          reason:
              'grounded($grounded) should be meaningfully greater than '
              'hallucinated($hallucinated).');
      expect(diffText.isNotEmpty, isTrue); // sanity — diffText parsed elsewhere
    });

    test('empty claim set yields exactly zero', () {
      final engine = _dumbbellEngine();
      final score = groundingConsistency(
        engine: engine,
        claimPaths: const {},
        diffTouchedPaths: {'left/a.dart'},
      );
      expect(score, equals(0.0));
    });

    test('claim paths unknown to engine produce zero grounding', () {
      final engine = _dumbbellEngine();
      final score = groundingConsistency(
        engine: engine,
        claimPaths: const {'nonexistent/file.dart', 'fake/other.dart'},
        diffTouchedPaths: {'left/a.dart'},
      );
      expect(score, equals(0.0));
    });

    test('self-grounding (claim == diff) approaches 1.0', () {
      final engine = _dumbbellEngine();
      final paths = {'left/a.dart', 'left/b.dart'};
      final score = groundingConsistency(
        engine: engine,
        claimPaths: paths,
        diffTouchedPaths: paths,
      );
      expect(score, greaterThan(0.9));
    });
  });

  group('Axis 2 — structural diff verifiability', () {
    test('clean text diff with hunks for every touched path → 1.0', () {
      final diff = _syntheticDiffFor(['lib/foo.dart', 'lib/bar.dart']);
      expect(wholeDiffVerifiability(diff), equals(1.0));
    });

    test(
        'binary diff (touched path declared but no hunks emitted) → 0.0',
        () {
      // Git emits a `Binary files … differ` section for binary files.
      // The header declares the path was touched (extractDiffTouchedPaths
      // finds it), but no hunk bodies are produced → verifiability
      // collapses to 0 by STRUCTURE, not by pattern-matching the marker.
      const diff =
          'diff --git a/image.png b/image.png\nBinary files a/image.png and b/image.png differ\n';
      expect(wholeDiffVerifiability(diff), equals(0.0));
    });

    test('mixed text + binary → fraction of readable paths', () {
      // Two paths declared touched, only one has hunk content.
      final buf = StringBuffer()
        ..write(_syntheticDiffFor(['lib/foo.dart']))
        ..write(
            'diff --git a/image.png b/image.png\nBinary files a/image.png and b/image.png differ\n');
      expect(wholeDiffVerifiability(buf.toString()), closeTo(0.5, 1e-9));
    });

    test('empty diff → 1.0 (trivially verifiable)', () {
      expect(wholeDiffVerifiability(''), equals(1.0));
    });

    test('diff with no declared paths → 1.0 (nothing to verify)', () {
      // Free-form text that doesn't match the diff-header regex.
      expect(wholeDiffVerifiability('this is not a diff'), equals(1.0));
    });
  });

  group('Axis 3 — downstream reach via participation ratio', () {
    test('hub claim reaches further than single-node claim', () {
      final engine = _dumbbellEngine();
      // `left/a.dart` is the bridge hub — couples to both clusters.
      final hubReach = downstreamReach(
        engine: engine,
        claimPaths: {'left/a.dart'},
      );
      // `right/c.dart` sits on the far side with no bridge role.
      final leafReach = downstreamReach(
        engine: engine,
        claimPaths: {'right/c.dart'},
      );
      expect(hubReach, greaterThan(leafReach),
          reason: 'hub reach ($hubReach) should exceed leaf reach ($leafReach)');
    });

    test('empty claim produces zero reach', () {
      final engine = _dumbbellEngine();
      expect(
        downstreamReach(engine: engine, claimPaths: const {}),
        equals(0.0),
      );
    });

    test('reach is bounded to [0, 1]', () {
      final engine = _dumbbellEngine();
      for (final p in engine.nodePaths) {
        final r = downstreamReach(engine: engine, claimPaths: {p});
        expect(r, greaterThanOrEqualTo(0.0));
        expect(r, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('Axis 4 — intra-claim coherence', () {
    test('single-symbol claim is trivially coherent (1.0)', () {
      final engine = _dumbbellEngine();
      final score = intraClaimCoherence(
        engine: engine,
        claimPaths: const ['left/a.dart'],
      );
      expect(score, equals(1.0));
    });

    test('same-cluster symbols score high', () {
      final engine = _dumbbellEngine();
      final score = intraClaimCoherence(
        engine: engine,
        claimPaths: const ['left/a.dart', 'left/b.dart', 'left/c.dart'],
      );
      expect(score, greaterThan(0.7));
    });

    test('cross-cluster symbols score lower than same-cluster', () {
      final engine = _dumbbellEngine();
      final sameCluster = intraClaimCoherence(
        engine: engine,
        claimPaths: const ['left/b.dart', 'left/c.dart'],
      );
      final crossCluster = intraClaimCoherence(
        engine: engine,
        claimPaths: const ['left/b.dart', 'right/c.dart'],
      );
      expect(sameCluster, greaterThan(crossCluster),
          reason:
              'same-cluster ($sameCluster) must exceed cross-cluster '
              '($crossCluster)');
    });

    test('unknown paths fall through without erroring', () {
      final engine = _dumbbellEngine();
      final score = intraClaimCoherence(
        engine: engine,
        claimPaths: const ['ghost/a.dart', 'ghost/b.dart'],
      );
      // Both unknown → both filtered → single-symbol fallback (1.0).
      expect(score, equals(1.0));
    });
  });

  group('ClaimShape + ReviewScore composition', () {
    test('composite in [0, 1] for every reasonable input', () {
      final engine = _dumbbellEngine();
      final ratchet = ClaimOutcomeRatchet();
      final shapes = [
        computeClaimShape(
          engine: engine,
          claimText: 'Possible bug in left/a.dart touching left/b.dart',
          diffText: _syntheticDiffFor(['left/a.dart']),
        ),
        computeClaimShape(
          engine: engine,
          claimText: 'Imaginary bug in nowhere.dart',
          diffText: _syntheticDiffFor(['left/a.dart']),
        ),
        computeClaimShape(
          engine: engine,
          claimText: 'right/c.dart smells off — possibly related to right/b.dart',
          diffText: _syntheticDiffFor(['right/a.dart', 'right/b.dart']),
        ),
      ];
      for (final s in shapes) {
        final score = composeReviewScore(shape: s, ratchet: ratchet);
        expect(score.composite, greaterThanOrEqualTo(0.0));
        expect(score.composite, lessThanOrEqualTo(1.0));
      }
    });

    test('grounded claim composite exceeds hallucinated composite', () {
      final engine = _dumbbellEngine();
      final ratchet = ClaimOutcomeRatchet();

      final grounded = computeClaimShape(
        engine: engine,
        claimText: 'Bug in left/a.dart, cascades into left/b.dart',
        diffText: _syntheticDiffFor(['left/a.dart', 'left/b.dart']),
      );
      final hallu = computeClaimShape(
        engine: engine,
        claimText: 'Bug in nowhere/nonexistent.dart',
        diffText: _syntheticDiffFor(['left/a.dart', 'left/b.dart']),
      );

      final sg = composeReviewScore(shape: grounded, ratchet: ratchet);
      final sh = composeReviewScore(shape: hallu, ratchet: ratchet);
      expect(sg.composite, greaterThan(sh.composite + 0.1),
          reason:
              'grounded composite (${sg.composite}) should be clearly '
              'above hallucinated composite (${sh.composite})');
    });

    test('binary-diff shape gets verifiability=0 and dampens composite', () {
      final engine = _dumbbellEngine();
      final ratchet = ClaimOutcomeRatchet();
      final cleanShape = computeClaimShape(
        engine: engine,
        claimText: 'left/a.dart looks wrong relative to left/b.dart',
        diffText: _syntheticDiffFor(['left/a.dart', 'left/b.dart']),
      );
      final binaryShape = computeClaimShape(
        engine: engine,
        claimText: 'left/a.dart looks wrong relative to left/b.dart',
        diffText:
            'diff --git a/left/a.dart b/left/a.dart\nBinary files a/left/a.dart and b/left/a.dart differ\n',
      );
      final cleanScore = composeReviewScore(shape: cleanShape, ratchet: ratchet);
      final binScore = composeReviewScore(shape: binaryShape, ratchet: ratchet);
      expect(binaryShape.verifiability, equals(0.0));
      expect(binScore.composite, lessThan(cleanScore.composite),
          reason:
              'binary-diff composite (${binScore.composite}) must be below '
              'clean-diff composite (${cleanScore.composite}).');
    });
  });

  group('Entity extraction', () {
    test('extractClaimPathsFromText finds in-graph paths, rejects unknowns',
        () {
      final engine = _dumbbellEngine();
      final extracted = extractClaimPathsFromText(
        'The bug is in left/a.dart and maybe ghost/fake.dart',
        engine.pathToId,
      );
      expect(extracted, contains('left/a.dart'));
      expect(extracted, isNot(contains('ghost/fake.dart')));
    });

    test('extractClaimPathsFromText ignores text without path-like tokens',
        () {
      final engine = _dumbbellEngine();
      final extracted = extractClaimPathsFromText(
        'nothing to see here folks',
        engine.pathToId,
      );
      expect(extracted, isEmpty);
    });
  });
}
