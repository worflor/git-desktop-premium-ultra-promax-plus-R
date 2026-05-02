// Tests for time-weighted Jaccard (exponential decay on commit age).
//
// These tests don't shell out to git — they synthesise commit lists
// and verify the weighting math by comparing expected and actual
// Jaccard scores. The git invocation path is covered by integration
// tests elsewhere.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Time-weighted Jaccard (computeFileCoupling decay semantics)', () {
    test('coherenceFor averages pairwise scores scaled by confidence', () {
      // commitsAnalyzed=100 → confidence=0.5. Raw mean Jaccard = 0.4.
      // Result = 0.5 + (0.4 - 0.5) * 0.5 = 0.45
      final m = FileCouplingMatrix(
        jaccard: {
          'a.dart': {'b.dart': 0.6, 'c.dart': 0.4},
          'b.dart': {'a.dart': 0.6, 'c.dart': 0.2},
          'c.dart': {'a.dart': 0.4, 'b.dart': 0.2},
        },
        headHash: 'h',
        commitsAnalyzed: 100,
      );
      final coh = m.coherenceFor(const ['a.dart', 'b.dart', 'c.dart']);
      expect(coh, closeTo(0.45, 1e-9));
    });

    test('coherenceFor pulls toward 0.5 on cold-start', () {
      // commitsAnalyzed=10 → confidence=0.05. Even with 0.9 Jaccard
      // everywhere, the result stays near 0.5 (the max-uncertainty
      // prior) because the evidence is too sparse to trust.
      final m = FileCouplingMatrix(
        jaccard: {
          'a.dart': {'b.dart': 0.9, 'c.dart': 0.9},
          'b.dart': {'a.dart': 0.9, 'c.dart': 0.9},
          'c.dart': {'a.dart': 0.9, 'b.dart': 0.9},
        },
        headHash: 'h',
        commitsAnalyzed: 10,
      );
      final coh = m.coherenceFor(const ['a.dart', 'b.dart', 'c.dart']);
      expect(coh, closeTo(0.5, 0.03),
          reason: 'cold-start repos must pull toward neutral');
    });
  });
}
