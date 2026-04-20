// Tests for `ApertureSweep.sampleAt(int window)` — the continuous-
// domain interpolation used by the history scrubber. Pins the
// load-bearing invariants:
//
//   1. Empty sweep → null (scrubber UI must handle this).
//   2. Query at a real sample's window returns that sample's fields
//      exactly (no drift from log-space rounding).
//   3. Below-range queries clamp to the first sample; above-range
//      clamp to the last. No extrapolation.
//   4. Intermediate queries interpolate scalars linearly in log-
//      window space (geometric midpoint = value midpoint).
//   5. Discrete fields (archetype, top path) snap to the nearer
//      endpoint — never hybridise.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/aperture_sweep.dart';

ApertureSample _sample({
  required int window,
  double fiedler = 0.1,
  int componentCount = 1,
  int cycleCount = 5,
  double spectralDim = 1.5,
  double spectralEntropy = 2.0,
  String nearestArchetype = 'poisson',
  double nearestDistance = 0.3,
  double decisiveness = 0.5,
  String topHousekeepingPath = 'lib/a.dart',
  int nodeCount = 100,
  int edgeCount = 200,
}) =>
    ApertureSample(
      window: window,
      nodeCount: nodeCount,
      edgeCount: edgeCount,
      fiedler: fiedler,
      componentCount: componentCount,
      cycleCount: cycleCount,
      spectralDim: spectralDim,
      spectralEntropy: spectralEntropy,
      nearestArchetype: nearestArchetype,
      nearestDistance: nearestDistance,
      decisiveness: decisiveness,
      topHousekeepingPath: topHousekeepingPath,
    );

ApertureSweep _sweep(List<ApertureSample> samples) => ApertureSweep(
      samples: samples,
      computedAt: DateTime.now(),
      headHash: 'test',
    );

void main() {
  group('ApertureSweep.sampleAt', () {
    test('empty sweep returns null', () {
      final sweep = _sweep(const []);
      expect(sweep.sampleAt(100), isNull);
    });

    test('query at a real sample window returns that sample exactly', () {
      final s1 = _sample(window: 100, fiedler: 0.2);
      final s2 = _sample(window: 400, fiedler: 0.8);
      final sweep = _sweep([s1, s2]);
      final hit = sweep.sampleAt(100);
      expect(hit, isNotNull);
      expect(hit!.window, 100);
      expect(hit.fiedler, 0.2);
    });

    test('below-range clamps to first sample', () {
      final s1 = _sample(window: 100, fiedler: 0.2);
      final s2 = _sample(window: 400, fiedler: 0.8);
      final sweep = _sweep([s1, s2]);
      final out = sweep.sampleAt(50);
      expect(out, isNotNull);
      expect(out!.fiedler, 0.2);
    });

    test('above-range clamps to last sample', () {
      final s1 = _sample(window: 100, fiedler: 0.2);
      final s2 = _sample(window: 400, fiedler: 0.8);
      final sweep = _sweep([s1, s2]);
      final out = sweep.sampleAt(2000);
      expect(out, isNotNull);
      expect(out!.fiedler, 0.8);
    });

    test('log-space interpolation: geometric midpoint = value midpoint',
        () {
      final s1 = _sample(window: 100, fiedler: 0.2);
      final s2 = _sample(window: 400, fiedler: 0.8);
      final sweep = _sweep([s1, s2]);
      // Geometric midpoint of 100 and 400 is sqrt(40000) = 200.
      // Linear interpolation at t=0.5 → fiedler = 0.5.
      final mid = sweep.sampleAt(200);
      expect(mid, isNotNull);
      expect(mid!.fiedler, closeTo(0.5, 1e-9));
    });

    test('integer counts interpolate-and-round', () {
      final s1 = _sample(window: 100, componentCount: 2);
      final s2 = _sample(window: 400, componentCount: 8);
      final sweep = _sweep([s1, s2]);
      final mid = sweep.sampleAt(200);
      expect(mid, isNotNull);
      // t=0.5 → (2+8)/2 = 5
      expect(mid!.componentCount, 5);
    });

    test('discrete field snaps to closer endpoint', () {
      final s1 = _sample(window: 100, nearestArchetype: 'poisson');
      final s2 = _sample(window: 400, nearestArchetype: 'goe');
      final sweep = _sweep([s1, s2]);
      // Geometric midpoint is 200 → t=0.5 → snaps to b (the tie goes
      // to the later sample; never hybridises).
      final mid = sweep.sampleAt(200);
      expect(mid!.nearestArchetype, isIn(['poisson', 'goe']));
      // Closer to 100 → a
      final early = sweep.sampleAt(110);
      expect(early!.nearestArchetype, 'poisson');
      // Closer to 400 → b
      final late = sweep.sampleAt(390);
      expect(late!.nearestArchetype, 'goe');
    });

    test('topHousekeepingPath snaps, never blends', () {
      final s1 = _sample(window: 100, topHousekeepingPath: 'lib/a.dart');
      final s2 = _sample(window: 400, topHousekeepingPath: 'lib/b.dart');
      final sweep = _sweep([s1, s2]);
      final early = sweep.sampleAt(110);
      final late = sweep.sampleAt(390);
      expect(early!.topHousekeepingPath, 'lib/a.dart');
      expect(late!.topHousekeepingPath, 'lib/b.dart');
    });

    test('three samples: binary search picks the correct bracket', () {
      final s1 = _sample(window: 100, fiedler: 0.1);
      final s2 = _sample(window: 400, fiedler: 0.5);
      final s3 = _sample(window: 1600, fiedler: 0.9);
      final sweep = _sweep([s1, s2, s3]);
      // Between s1 and s2 — geometric midpoint of 100 and 400 is 200.
      final midLow = sweep.sampleAt(200);
      expect(midLow!.fiedler, closeTo(0.3, 1e-9));
      // Between s2 and s3 — geometric midpoint of 400 and 1600 is 800.
      final midHigh = sweep.sampleAt(800);
      expect(midHigh!.fiedler, closeTo(0.7, 1e-9));
    });
  });
}
