// Tests for the claim-grounding report rendering and the lightweight
// ClaimGroundingData ↔ ClaimShape round-trip the UI relies on when
// recording an outcome into the ratchet.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/review_grounding.dart';
import 'package:git_desktop/backend/review_logos.dart';
import 'package:git_desktop/backend/review_ratchet.dart';

GroundedFinding _grounded({
  required String id,
  required double grounding,
}) {
  final shape = ClaimShape(
    grounding: grounding,
    verifiability: 1.0,
    reach: 0.4,
    coherence: 1.0,
    symbolCount: 2,
    textLength: 120,
  );
  final score = composeReviewScore(shape: shape, ratchet: ClaimOutcomeRatchet());
  final finding = AiCommitReviewFindingData(
    id: id,
    severity: 'warn',
    title: 'title',
    evidence: 'evidence',
    whyItMatters: 'why',
    origin: 'draft',
  );
  return GroundedFinding(finding, score);
}

void main() {
  group('formatClaimGroundingBlock', () {
    test('empty in, empty out', () {
      expect(formatClaimGroundingBlock(const []), '');
    });

    test('renders per-finding axes', () {
      final block = formatClaimGroundingBlock([
        _grounded(id: 'F1', grounding: 0.82),
      ]);
      expect(block, contains('F1 grounding=0.82'));
      expect(block, contains('verifiability=1.00'));
      expect(block, contains('reach=0.40'));
    });

    test('marks a finding whose symbols barely reach the diff', () {
      final weak = formatClaimGroundingBlock([
        _grounded(id: 'F1', grounding: 0.05),
      ]);
      expect(weak, contains('←'));
      final strong = formatClaimGroundingBlock([
        _grounded(id: 'F1', grounding: 0.90),
      ]);
      expect(strong, isNot(contains('←')));
    });
  });

  group('ClaimGroundingData round-trip', () {
    test('reconstructed ClaimShape hashes to the same bucket', () {
      const shape = ClaimShape(
        grounding: 0.7,
        verifiability: 1.0,
        reach: 0.3,
        coherence: 0.9,
        symbolCount: 3,
        textLength: 200,
      );
      // Mirror what review_grounding attaches and what the UI rebuilds.
      const g = ClaimGroundingData(
        grounding: 0.7,
        verifiability: 1.0,
        reach: 0.3,
        coherence: 0.9,
        symbolCount: 3,
        textLength: 200,
        composite: 0.5,
        ratchetPrior: 0.5,
      );
      final rebuilt = ClaimShape(
        grounding: g.grounding,
        verifiability: g.verifiability,
        reach: g.reach,
        coherence: g.coherence,
        symbolCount: g.symbolCount,
        textLength: g.textLength,
      );
      expect(rebuilt.shapeHash(), shape.shapeHash());
    });

    test('the rebuilt shape drives the ratchet the same way', () {
      const g = ClaimGroundingData(
        grounding: 0.7,
        verifiability: 1.0,
        reach: 0.3,
        coherence: 0.9,
        symbolCount: 3,
        textLength: 200,
        composite: 0.5,
        ratchetPrior: 0.5,
      );
      final rebuilt = ClaimShape(
        grounding: g.grounding,
        verifiability: g.verifiability,
        reach: g.reach,
        coherence: g.coherence,
        symbolCount: g.symbolCount,
        textLength: g.textLength,
      );
      final ratchet = ClaimOutcomeRatchet();
      ratchet.observe(shape: rebuilt, verified: true);
      ratchet.observe(shape: rebuilt, verified: true);
      // Two accepts → prior tilts above the 0.5 max-uncertainty default.
      expect(ratchet.priorFor(rebuilt), greaterThan(0.5));
    });
  });
}
