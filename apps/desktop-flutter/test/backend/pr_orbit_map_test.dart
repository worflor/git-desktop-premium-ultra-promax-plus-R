// Tests for PrOrbitMap — the canonical pairwise PR cosine matrix.
// Replaces the hand-rolled `_prCosineMap` in branches_page.dart.
// These tests pin the symmetry, sparsity (zero-cosine omission), and
// sorted-descending partner shape that the branches list sort relies
// on.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/pr_shape.dart';

const _flatFlow = LogosFlowDiagnostics(
  gradientMass: 0.0,
  curlMass: 0.0,
  harmonicMass: 0.0,
  structuralStress: 0.0,
  witnessEntropy: 0.0,
  confidence: 0.0,
);

PrShape _shapeWithPhi(Float64List phi) => PrShape(
      phi: phi,
      topK: const [],
      coherence: 0.5,
      stability: 0.5,
      metabolismRisk: 0.0,
      fieldAlignment: null,
      flow: _flatFlow,
      orientation: null,
      axisMassFractions: const {'_pr': 1.0},
      computedAt: DateTime(2026),
    );

void main() {
  group('PrOrbitMap.fromShapes', () {
    test('empty or single shape yields empty map', () {
      expect(PrOrbitMap.fromShapes(const {}).isEmpty, isTrue);
      final one = PrOrbitMap.fromShapes({
        1: _shapeWithPhi(Float64List.fromList([1, 0, 0])),
      });
      expect(one.isEmpty, isTrue);
      expect(one.partnersOf(1), isEmpty);
    });

    test('orthogonal shapes produce no entry', () {
      final map = PrOrbitMap.fromShapes({
        1: _shapeWithPhi(Float64List.fromList([1, 0, 0])),
        2: _shapeWithPhi(Float64List.fromList([0, 1, 0])),
      });
      expect(map.isEmpty, isTrue);
      expect(map.cosine(1, 2), equals(0.0));
      expect(map.hasPartner(1), isFalse);
    });

    test('aligned shapes produce symmetric cosine entries', () {
      // Identical vectors → cosine 1.
      final phi = Float64List.fromList([1.0, 2.0, 3.0]);
      final map = PrOrbitMap.fromShapes({
        10: _shapeWithPhi(Float64List.fromList([1.0, 2.0, 3.0])),
        20: _shapeWithPhi(Float64List.fromList([1.0, 2.0, 3.0])),
      });
      expect(map.cosine(10, 20), closeTo(1.0, 1e-12));
      expect(map.cosine(20, 10), closeTo(1.0, 1e-12));
      // Unused here; silences unused-var warning for the phi template.
      expect(phi.length, equals(3));
    });

    test('partial overlap yields cosine in (0, 1)', () {
      final map = PrOrbitMap.fromShapes({
        1: _shapeWithPhi(Float64List.fromList([1, 1, 0])),
        2: _shapeWithPhi(Float64List.fromList([0, 1, 1])),
      });
      final c = map.cosine(1, 2);
      expect(c, greaterThan(0.0));
      expect(c, lessThan(1.0));
      expect(map.cosine(2, 1), equals(c));
    });

    test('different-length phi pairs are skipped', () {
      final map = PrOrbitMap.fromShapes({
        1: _shapeWithPhi(Float64List.fromList([1, 0, 0])),
        2: _shapeWithPhi(Float64List.fromList([1, 0, 0, 0])),
      });
      expect(map.cosine(1, 2), equals(0.0));
    });
  });

  group('PrOrbitMap.partnersOf', () {
    test('returns partners sorted by cosine descending', () {
      // PR 1 partners with PR 2 strongly and PR 3 weakly.
      final strong = Float64List.fromList([1.0, 1.0, 0.0]);
      final weak = Float64List.fromList([1.0, 0.1, 0.0]);
      final center = Float64List.fromList([1.0, 1.0, 0.0]);
      final map = PrOrbitMap.fromShapes({
        1: _shapeWithPhi(center),
        2: _shapeWithPhi(strong),
        3: _shapeWithPhi(weak),
      });
      final partners = map.partnersOf(1);
      expect(partners.length, equals(2));
      expect(partners[0].key, equals(2));
      expect(partners[1].key, equals(3));
      expect(partners[0].value, greaterThan(partners[1].value));
    });

    test('empty list for unknown or partnerless PR', () {
      final map = PrOrbitMap.fromShapes({
        1: _shapeWithPhi(Float64List.fromList([1, 0])),
        2: _shapeWithPhi(Float64List.fromList([0, 1])),
      });
      expect(map.partnersOf(999), isEmpty);
      expect(map.partnersOf(1), isEmpty); // orthogonal → no entry
    });
  });

  group('PrOrbitMap.cosine', () {
    test('self-cosine is 1', () {
      final map = PrOrbitMap.fromShapes({
        7: _shapeWithPhi(Float64List.fromList([1, 2, 3])),
      });
      expect(map.cosine(7, 7), equals(1.0));
    });

    test('unknown pair returns 0', () {
      expect(PrOrbitMap.empty.cosine(1, 2), equals(0.0));
    });
  });
}
