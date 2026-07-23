// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_lifecycle_fuzz_test.dart — randomized end-to-end review runs.
//
// Each seed drives a full multi-author review lifecycle (edits, round
// cuts, draft batches, verdicts, robot findings, replies from both
// sides, resolutions, interleaved syncs) on a REAL two-clone team
// through the REAL store, with the scenario engine's model-based
// invariants (I1–I7) asserted at every settle. A failure prints the
// seed and the complete op log — rerun the seed for a deterministic
// repro. MANIFOLD_FUZZ=N deepens the run.

import 'package:flutter_test/flutter_test.dart';

import '../support/prop.dart';
import '../support/review_scenario.dart';

void main() {
  final seeds = [for (var i = 0; i < 4 * fuzzScale(); i++) 20260722 + i];

  for (final seed in seeds) {
    test('lifecycle seed $seed converges under every invariant', () async {
      final result = await runReviewScenario(seed: seed);
      // The run IS the assertion (invariants throw); minimal shape
      // checks confirm the scenario actually exercised the machinery.
      expect(result.finalState.threads, isNotEmpty,
          reason: 'a scenario with no threads tested nothing');
      expect(result.log.where((l) => l == 'settle').length,
          greaterThanOrEqualTo(2));
    }, timeout: fuzzTimeout(const Duration(minutes: 4)));
  }
}
