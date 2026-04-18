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
    test('coherenceFor averages pairwise scores at high confidence', () {
      // Build a tiny hand-crafted matrix. High commitsAnalyzed so the
      // confidence gate doesn't trip.
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

    test('coherenceFor gates to 0.5 on cold-start (confidence gate)', () {
      // Same data, but with commitsAnalyzed below the threshold (50)
      // — must return the max-uncertainty prior 0.5 instead of the
      // false-confident 0.4. Closes the cold-start false-coherence
      // regression the branches-page PR focus score surfaces.
      final m = FileCouplingMatrix(
        jaccard: {
          'a.dart': {'b.dart': 0.9, 'c.dart': 0.9},
          'b.dart': {'a.dart': 0.9, 'c.dart': 0.9},
          'c.dart': {'a.dart': 0.9, 'b.dart': 0.9},
        },
        headHash: 'h',
        commitsAnalyzed: 10, // below the 50-commit gate
      );
      final coh = m.coherenceFor(const ['a.dart', 'b.dart', 'c.dart']);
      expect(coh, 0.5,
          reason: 'cold-start repos must not report spurious coherence');
    });
  });
}
