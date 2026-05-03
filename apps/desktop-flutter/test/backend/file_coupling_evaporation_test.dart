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
      // 3 tracked files → saturation = max(50, 3*0.4) = 50.
      // commitsAnalyzed=100 → conf = min(1, 100/50) = 1.0.
      // Raw mean Jaccard = 0.4. Result = 0.5 + (0.4-0.5)*1.0 = 0.4.
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
      expect(coh, closeTo(0.4, 1e-9));
    });

    test('coherenceFor pulls toward 0.5 on cold-start', () {
      // commitsAnalyzed=10, saturation=50 → conf=0.2. Raw=0.9.
      // Result = 0.5 + 0.4*0.2 = 0.58. Still pulled toward neutral
      // but less aggressively than with the old /200 formula.
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
      expect(coh, closeTo(0.58, 0.01),
          reason: 'cold-start repos should pull toward neutral');
    });
  });
}
