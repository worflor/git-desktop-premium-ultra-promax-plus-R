// Unit tests for the aperture-sweep primitive's pure analysis
// functions. The sweep COLLECTOR hits git and requires a real repo;
// those paths are covered by integration probes in test/research/.
// Here we pin the mathematical contract on synthetic [ApertureSample]
// sequences so the event-detection / trajectory / classification
// logic is deterministic.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/aperture_sweep.dart';

ApertureSample _mk({
  required int window,
  int nodeCount = 100,
  int edgeCount = 200,
  double fiedler = 0.05,
  int componentCount = 1,
  int cycleCount = 50,
  double spectralDim = 1.5,
  double spectralEntropy = 2.0,
  String nearestArchetype = 'poisson',
  double nearestDistance = 0.3,
  double decisiveness = 0.5,
  String topHousekeepingPath = 'a.dart',
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
      computedAt: DateTime(2026, 1, 1),
      headHash: 'test',
    );

void main() {
  group('detectCompoundEvents', () {
    test('empty sweep returns empty event list', () {
      expect(detectCompoundEvents(_sweep(const [])), isEmpty);
    });

    test('single-sample sweep returns empty event list', () {
      expect(detectCompoundEvents(_sweep([_mk(window: 100)])), isEmpty);
    });

    test('constant observables produce no events', () {
      // Five samples with identical observables → no transitions.
      final s = _sweep([
        _mk(window: 60),
        _mk(window: 80),
        _mk(window: 100),
        _mk(window: 140),
        _mk(window: 200),
      ]);
      expect(detectCompoundEvents(s), isEmpty);
    });

    test('single-observable flip does not count when minFlipped=2', () {
      // Only `nodeCount` jumps between bin 3→4; every other signal
      // is constant. With minFlipped=2 this shouldn't register.
      final s = _sweep([
        _mk(window: 60),
        _mk(window: 80),
        _mk(window: 100),
        _mk(window: 140, nodeCount: 500),
        _mk(window: 200, nodeCount: 500),
      ]);
      expect(detectCompoundEvents(s), isEmpty);
    });

    test('two observables flipping in the same bin produce an event', () {
      // Both nodeCount AND componentCount spike between bin 3→4.
      final s = _sweep([
        _mk(window: 60),
        _mk(window: 80),
        _mk(window: 100),
        _mk(window: 140, nodeCount: 500, componentCount: 10),
        _mk(window: 200, nodeCount: 500, componentCount: 10),
      ]);
      final events = detectCompoundEvents(s);
      expect(events, hasLength(greaterThanOrEqualTo(1)));
      final primary = events.first;
      expect(primary.fromWindow, 100);
      expect(primary.toWindow, 140);
      expect(primary.flippedObservables, containsAll(['n', 'beta0']));
      expect(primary.magnitude, greaterThan(0));
      expect(primary.apertureMid, closeTo(118.32, 0.1));
    });

    test('minFlipped=3 suppresses events where only 2 observables flip', () {
      final s = _sweep([
        _mk(window: 60),
        _mk(window: 80),
        _mk(window: 100),
        _mk(window: 140, nodeCount: 500, componentCount: 10),
        _mk(window: 200, nodeCount: 500, componentCount: 10),
      ]);
      expect(detectCompoundEvents(s, minFlipped: 3), isEmpty);
    });

    test('events sort by ascending toWindow', () {
      final s = _sweep([
        _mk(window: 60),
        _mk(window: 80, nodeCount: 300, componentCount: 5),
        _mk(window: 100, nodeCount: 300, componentCount: 5),
        _mk(window: 140, nodeCount: 500, componentCount: 10),
        _mk(window: 200, nodeCount: 500, componentCount: 10),
      ]);
      final events = detectCompoundEvents(s);
      for (var i = 1; i < events.length; i++) {
        expect(events[i].toWindow, greaterThanOrEqualTo(events[i - 1].toWindow));
      }
    });
  });

  group('centerOfGravityTrajectory', () {
    test('empty sweep returns empty list', () {
      expect(centerOfGravityTrajectory(_sweep(const [])), isEmpty);
    });

    test('dedupes consecutive repeats of the same path', () {
      final s = _sweep([
        _mk(window: 60, topHousekeepingPath: 'a.dart'),
        _mk(window: 80, topHousekeepingPath: 'a.dart'),
        _mk(window: 100, topHousekeepingPath: 'b.dart'),
        _mk(window: 140, topHousekeepingPath: 'b.dart'),
        _mk(window: 200, topHousekeepingPath: 'c.dart'),
      ]);
      final t = centerOfGravityTrajectory(s);
      expect(t.length, 3);
      expect(t[0].window, 60);
      expect(t[0].path, 'a.dart');
      expect(t[1].window, 100);
      expect(t[1].path, 'b.dart');
      expect(t[2].window, 200);
      expect(t[2].path, 'c.dart');
    });

    test('skips samples with empty top path', () {
      final s = _sweep([
        _mk(window: 60, topHousekeepingPath: ''),
        _mk(window: 80, topHousekeepingPath: 'a.dart'),
        _mk(window: 100, topHousekeepingPath: ''),
        _mk(window: 140, topHousekeepingPath: 'b.dart'),
      ]);
      final t = centerOfGravityTrajectory(s);
      expect(t.map((x) => x.path).toList(), ['a.dart', 'b.dart']);
    });

    test('carries the archetype observed at that stratum', () {
      final s = _sweep([
        _mk(window: 60, topHousekeepingPath: 'a.dart', nearestArchetype: 'goe'),
        _mk(
            window: 100,
            topHousekeepingPath: 'b.dart',
            nearestArchetype: 'poisson'),
      ]);
      final t = centerOfGravityTrajectory(s);
      expect(t[0].nearestArchetype, 'goe');
      expect(t[1].nearestArchetype, 'poisson');
    });
  });

  group('classifyObservables', () {
    test('too-short sweep returns empty map', () {
      expect(classifyObservables(_sweep([_mk(window: 60)])), isEmpty);
    });

    test('constant observable classifies as invariant', () {
      final s = _sweep([
        _mk(window: 60, nodeCount: 100),
        _mk(window: 100, nodeCount: 100),
        _mk(window: 200, nodeCount: 100),
        _mk(window: 500, nodeCount: 100),
      ]);
      expect(classifyObservables(s)['n'], 'invariant');
    });

    test('monotonic increasing observable classifies as running', () {
      final s = _sweep([
        _mk(window: 60, nodeCount: 100),
        _mk(window: 100, nodeCount: 200),
        _mk(window: 200, nodeCount: 350),
        _mk(window: 500, nodeCount: 700),
      ]);
      expect(classifyObservables(s)['n'], 'running');
    });

    test('high-variance non-monotonic observable classifies as artifact', () {
      // Values: 100, 500, 120, 480. High CV, no monotonic trend.
      final s = _sweep([
        _mk(window: 60, nodeCount: 100),
        _mk(window: 100, nodeCount: 500),
        _mk(window: 200, nodeCount: 120),
        _mk(window: 500, nodeCount: 480),
      ]);
      expect(classifyObservables(s)['n'], 'artifact');
    });
  });

  group('ApertureEvent.apertureMid', () {
    test('returns geometric mean of bin boundaries', () {
      const e = ApertureEvent(
        fromWindow: 100,
        toWindow: 400,
        flippedObservables: ['n', 'fiedler'],
        magnitude: 1.0,
      );
      expect(e.apertureMid, closeTo(200.0, 1e-9));
    });
  });

  group('ApertureSweep.empty', () {
    test('exposes a reusable empty instance', () {
      expect(ApertureSweep.empty.isEmpty, isTrue);
      expect(ApertureSweep.empty.length, 0);
    });
  });
}
