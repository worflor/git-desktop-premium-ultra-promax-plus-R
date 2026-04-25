// Tests for the claim-outcome ratchet (axis 5 of the review
// pipeline). The ratchet's job is to turn "the user accepted /
// rejected this finding" into a posterior `p(accept | shape)`
// that future compositions can blend into the composite score.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/review_logos.dart';
import 'package:git_desktop/backend/review_ratchet.dart';

/// Tiny ClaimShape builder so tests can vary one axis at a time.
/// Quantisation in [ClaimShape.shapeHash] happens at 4-bit precision
/// per axis, so two fields within ~0.067 of each other land in the
/// same bucket. Tests stay well outside that tolerance.
ClaimShape _shape({
  double grounding = 0.5,
  double verifiability = 1.0,
  double reach = 0.5,
  double coherence = 0.5,
  int symbolCount = 2,
  int textLength = 128,
}) {
  return ClaimShape(
    grounding: grounding,
    verifiability: verifiability,
    reach: reach,
    coherence: coherence,
    symbolCount: symbolCount,
    textLength: textLength,
  );
}

void main() {
  group('ClaimOutcomeRatchet', () {
    test('unseen shape returns 0.5 (max-uncertainty prior)', () {
      final ratchet = ClaimOutcomeRatchet();
      expect(ratchet.priorFor(_shape()), equals(0.5));
      expect(ratchet.observationCountFor(_shape()), equals(0));
    });

    test('single accept pushes prior above 0.5', () {
      final ratchet = ClaimOutcomeRatchet();
      final shape = _shape();
      ratchet.observe(shape: shape, verified: true);
      final prior = ratchet.priorFor(shape);
      expect(prior, greaterThan(0.5),
          reason: 'one accept should pull the posterior toward 1');
      expect(prior, lessThan(1.0),
          reason: 'Laplace smoothing keeps it strictly below 1');
    });

    test('single reject pushes prior below 0.5', () {
      final ratchet = ClaimOutcomeRatchet();
      final shape = _shape();
      ratchet.observe(shape: shape, verified: false);
      final prior = ratchet.priorFor(shape);
      expect(prior, lessThan(0.5));
      expect(prior, greaterThan(0.0));
    });

    test('many observations converge toward observed accept rate', () {
      final ratchet = ClaimOutcomeRatchet();
      final shape = _shape();
      // 70 accepts, 30 rejects → expected ≈ 0.70 under Laplace
      // smoothing with denominator (100 + 2).
      for (var i = 0; i < 70; i++) {
        ratchet.observe(shape: shape, verified: true);
      }
      for (var i = 0; i < 30; i++) {
        ratchet.observe(shape: shape, verified: false);
      }
      final prior = ratchet.priorFor(shape);
      expect(prior, closeTo(71.0 / 102.0, 1e-9));
    });

    test('different shapes have independent buckets', () {
      final ratchet = ClaimOutcomeRatchet();
      final a = _shape(grounding: 0.9, reach: 0.9);
      final b = _shape(grounding: 0.1, reach: 0.1);
      ratchet.observe(shape: a, verified: true);
      ratchet.observe(shape: b, verified: false);
      expect(ratchet.priorFor(a), greaterThan(0.5));
      expect(ratchet.priorFor(b), lessThan(0.5));
      expect(ratchet.bucketCount, equals(2));
    });

    test('near-identical shapes share a bucket', () {
      final ratchet = ClaimOutcomeRatchet();
      // Within one 4-bit quantisation step of each other — same
      // shape hash by construction.
      final a = _shape(grounding: 0.50, reach: 0.50);
      final b = _shape(grounding: 0.51, reach: 0.51);
      ratchet.observe(shape: a, verified: true);
      ratchet.observe(shape: b, verified: true);
      expect(ratchet.bucketCount, equals(1),
          reason: 'quantisation should collapse nearby shapes');
      expect(ratchet.observationCountFor(a), equals(2));
    });

    test('JSON round-trip preserves counts', () {
      final a = _shape(grounding: 0.9);
      final b = _shape(reach: 0.1);
      final src = ClaimOutcomeRatchet();
      src.observe(shape: a, verified: true);
      src.observe(shape: a, verified: true);
      src.observe(shape: b, verified: false);

      final restored = ClaimOutcomeRatchet.fromJsonString(src.toJsonString());
      expect(restored.priorFor(a), equals(src.priorFor(a)));
      expect(restored.priorFor(b), equals(src.priorFor(b)));
      expect(restored.bucketCount, equals(src.bucketCount));
      expect(restored.totalObservations, equals(src.totalObservations));
    });

    test('fromJsonString tolerates malformed input', () {
      // Empty string → empty ratchet (clean cold-start).
      expect(ClaimOutcomeRatchet.fromJsonString('').bucketCount, equals(0));
      // Non-integer keys are silently dropped.
      expect(
        ClaimOutcomeRatchet.fromJsonString('{"notaNumber":{"a":1}}').bucketCount,
        equals(0),
      );
      // Fully garbled input is tolerated — we return an empty ratchet
      // rather than crashing the app on startup with a corrupted
      // persistence file.
      expect(
        ClaimOutcomeRatchet.fromJsonString('!!! not json !!!').bucketCount,
        equals(0),
      );
    });

    test('clear() empties every bucket', () {
      final ratchet = ClaimOutcomeRatchet();
      ratchet.observe(shape: _shape(), verified: true);
      expect(ratchet.bucketCount, equals(1));
      ratchet.clear();
      expect(ratchet.bucketCount, equals(0));
      expect(ratchet.totalObservations, equals(0));
    });
  });

  group('Ratchet integration with ReviewScore', () {
    test('learned prior nudges composite when it has evidence', () {
      final shape = _shape(
        grounding: 0.6,
        verifiability: 1.0,
        reach: 0.4,
        coherence: 0.6,
        symbolCount: 3,
        textLength: 500,
      );

      // Fresh ratchet — prior is 0.5, composite reflects only the
      // spectral axes.
      final fresh = ClaimOutcomeRatchet();
      final scoreFresh = composeReviewScore(shape: shape, ratchet: fresh);

      // After 100 accepts on this shape, the prior → 1.0 and the
      // composite should rise.
      final trained = ClaimOutcomeRatchet();
      for (var i = 0; i < 100; i++) {
        trained.observe(shape: shape, verified: true);
      }
      final scoreTrained = composeReviewScore(shape: shape, ratchet: trained);

      expect(scoreTrained.composite, greaterThan(scoreFresh.composite),
          reason:
              'a shape with 100 accepts should out-score a fresh shape');
      expect(scoreTrained.ratchetPrior, closeTo(101.0 / 102.0, 1e-6));
    });
  });
}
