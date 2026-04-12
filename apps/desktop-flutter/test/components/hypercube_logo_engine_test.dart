import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/components/hypercube_logo_engine.dart';

void main() {
  test('pose/state table mirrors TS source exactly', () {
    const expected = <List<double>>[
      [0.35, 0.35, 0.1, 0.35, 0.1, 0.1],
      [0.5, 0.8, 0.2, 1.2, 0.5, 0.1],
      [1.5, 0.3, 2.1, 0.1, 0.9, 0.6],
      [2.1, 1.5, 0.8, 3.1, 0.4, 1.2],
      [3.14, 2.1, 1.5, 0.8, 0.1, 3.14],
      [0.8, 1.6, 3.2, 0.4, 4.0, 1.2],
      [1.57, 0, 1.57, 0, 1.57, 0],
      [0, 0.785, 0, 0, 0.785, 0],
      [0.4, 0.2, 3.142, 3.142, 0.2, 0.4],
      [0.1, 0.1, 2.356, 0.1, 2.356, 2.356],
      [0, 0.4, 3.142, 0, 3.142, 0],
      [0.785, 0, 0, 0, 0, 0.785],
      [0, 0, 1.57, 0, 1.57, 0],
    ];
    expect(hypercubeStates, expected);
  });

  test('hypercube engine exposes canonical vertex and edge topology', () {
    expect(hypercubeVertices.length, 16);
    expect(hypercubeEdges.length, 32);
  });

  test('rotation plane chain preserves 4D vector norm', () {
    const coords = <double>[1, -1, 1, -1];
    const angles = <double>[0.35, 0.8, 0.25, 1.2, 0.4, 0.1];
    final rotated = rotate4D(coords, angles);
    final before = _norm(coords);
    final after = _norm(rotated);
    expect((before - after).abs(), lessThan(1e-9));
  });

  test('next pose selection is deterministic for fixed seed', () {
    final a = HypercubeLogoEngine(seed: 123456);
    final b = HypercubeLogoEngine(seed: 123456);

    final seqA = <int>[];
    final seqB = <int>[];
    for (int i = 0; i < 8; i++) {
      final nextA = a.pickNextIndex();
      final nextB = b.pickNextIndex();
      seqA.add(nextA);
      seqB.add(nextB);
      a.targetIndex = nextA;
      b.targetIndex = nextB;
    }

    expect(seqA, seqB);
    expect(seqA.first, isNot(anyOf(0, 1)));
  });

  test('step advances transition with TS distance multiplier formula', () {
    final engine = HypercubeLogoEngine(seed: 42);
    engine.near = 0;
    engine.dragging = false;
    engine.smoothBoost = 1;
    engine.transition = 0;
    const dt = 0.016;

    final start = hypercubeStates[engine.currentIndex];
    final end = hypercubeStates[engine.targetIndex];
    double distSquared = 0;
    for (int i = 0; i < start.length; i++) {
      final d = start[i] - end[i];
      distSquared += d * d;
    }
    final distMult =
        0.9 + (math.sqrt(distSquared) * 0.1).clamp(0, 0.1).toDouble();
    final expectedTransition = 0.095 * dt * 1 * distMult;

    engine.step(dt, speed: 0.85);
    expect((engine.transition - expectedTransition).abs(), lessThan(1e-9));
  });

  test('step preserves transition overshoot when rolling to the next pose', () {
    final engine = HypercubeLogoEngine(seed: 42)
      ..near = 0
      ..dragging = false
      ..smoothBoost = 1
      ..transition = 0.9995;

    const dt = 0.016;
    final start = hypercubeStates[engine.currentIndex];
    final end = hypercubeStates[engine.targetIndex];
    double distSquared = 0;
    for (int i = 0; i < start.length; i++) {
      final d = start[i] - end[i];
      distSquared += d * d;
    }
    final distMult =
        0.9 + (math.sqrt(distSquared) * 0.1).clamp(0, 0.1).toDouble();
    final delta = 0.095 * dt * distMult;

    final previousTarget = engine.targetIndex;
    engine.step(dt, speed: 0.85);

    expect(engine.currentIndex, previousTarget);
    expect(engine.transition, closeTo(0.9995 + delta - 1, 1e-9));
  });

  test('step applies spring-damped warp return while not dragging', () {
    final engine = HypercubeLogoEngine(seed: 7)
      ..dragging = false
      ..warpX = 8
      ..warpY = -4
      ..warpVx = 0
      ..warpVy = 0;

    engine.step(0.016, speed: 0.85);

    expect(engine.warpX.abs(), lessThan(8));
    expect(engine.warpY.abs(), lessThan(4));
    expect(engine.warpVx, isNot(0));
    expect(engine.warpVy, isNot(0));
  });

  test('step snaps an effectively settled warp back to zero', () {
    final engine = HypercubeLogoEngine(seed: 9)
      ..dragging = false
      ..near = 0
      ..warpX = 0.002
      ..warpY = -0.002
      ..warpVx = 0.001
      ..warpVy = -0.001;

    engine.step(0.016, speed: 0.85);

    expect(engine.warpX, 0);
    expect(engine.warpY, 0);
    expect(engine.warpVx, 0);
    expect(engine.warpVy, 0);
  });

  test('projected vertices are deterministic for fixed state snapshot', () {
    HypercubeProjectedData projectOnce() {
      final engine = HypercubeLogoEngine(seed: 77)
        ..currentIndex = 2
        ..targetIndex = 7
        ..transition = 0.42
        ..time = 1.234
        ..near = 0.67
        ..dragging = true
        ..tiltX = 0.12
        ..tiltY = -0.08
        ..warpX = 3.5
        ..warpY = -2.25
        ..warpVx = 0
        ..warpVy = 0;
      return engine.projectedData(48);
    }

    final first = projectOnce();
    final second = projectOnce();
    expect(first.main.length, 16);
    expect(first.home.length, 16);
    expect(first.ghost.length, 16);

    for (int i = 0; i < 16; i++) {
      expect(_pointsClose(first.main[i], second.main[i]), isTrue);
      expect(_pointsClose(first.home[i], second.home[i]), isTrue);
      expect(_pointsClose(first.ghost[i], second.ghost[i]), isTrue);
    }
  });

  test('projected data skips secondary passes when they would not be visible', () {
    final engine = HypercubeLogoEngine(seed: 77)
      ..currentIndex = 2
      ..targetIndex = 7
      ..transition = 0.42
      ..time = 1.234
      ..near = 0
      ..dragging = false
      ..tiltX = 0
      ..tiltY = 0
      ..warpX = 0
      ..warpY = 0
      ..warpVx = 0
      ..warpVy = 0;

    final projected = engine.projectedData(48);
    expect(projected.main.length, 16);
    expect(projected.home, isEmpty);
    expect(projected.ghost, isEmpty);
  });

  test('dragging keeps the home projection available for connector rendering', () {
    final engine = HypercubeLogoEngine(seed: 77)
      ..currentIndex = 2
      ..targetIndex = 7
      ..transition = 0.42
      ..time = 1.234
      ..near = 0
      ..dragging = true
      ..tiltX = 0.12
      ..tiltY = -0.08
      ..warpX = 3.5
      ..warpY = -2.25
      ..warpVx = 0
      ..warpVy = 0;

    final projected = engine.projectedData(48);
    expect(projected.home.length, 16);
  });
}

double _norm(List<double> values) {
  double total = 0;
  for (final value in values) {
    total += value * value;
  }
  return total;
}

bool _pointsClose(HypercubeProjectedPoint a, HypercubeProjectedPoint b) {
  return (a.point.dx - b.point.dx).abs() < 1e-9 &&
      (a.point.dy - b.point.dy).abs() < 1e-9 &&
      (a.z - b.z).abs() < 1e-9 &&
      (a.w - b.w).abs() < 1e-9;
}
