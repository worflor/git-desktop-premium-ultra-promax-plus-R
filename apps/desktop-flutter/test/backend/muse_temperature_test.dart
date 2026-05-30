// Unit tests for [modulateMuseTemperature] — the geometric-mean-of-
// calm modulation that drives the muse synthesis temperature in
// `_spectrallyModulatedTemperature`. The math is load-bearing: an
// off-by-one in the floor or a wrong root would skew every muse run
// silently. These tests pin the boundary cases so a future tweak
// can't drift the modulation surface without an explicit failure.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart' show modulateMuseTemperature;

void main() {
  group('modulateMuseTemperature', () {
    test('empty signals returns base unchanged', () {
      expect(modulateMuseTemperature(base: 1.0, calmSignals: const []),
          equals(1.0));
      expect(modulateMuseTemperature(base: 0.7, calmSignals: const []),
          equals(0.7));
      // Even an extreme base passes through untouched when there's no
      // engine reading to modulate against.
      expect(modulateMuseTemperature(base: 1.4, calmSignals: const []),
          equals(1.4));
    });

    test('single-element signal: geometric mean equals the element', () {
      // With one signal s, the geometric mean is s itself, so
      // modulation = 2/(1+s). Pin a few points.
      // base = 1.0, s = 1.0 (fully calm) → modulation = 1.0
      expect(modulateMuseTemperature(base: 1.0, calmSignals: const [1.0]),
          closeTo(1.0, 1e-12));
      // base = 1.0, s = 0.0 (fully chaotic, hits 1e-3 floor) →
      // modulation = 2/(1+1e-3) ≈ 1.998
      final chaotic =
          modulateMuseTemperature(base: 1.0, calmSignals: const [0.0]);
      expect(chaotic, closeTo(2.0 / 1.001, 1e-9));
      // base = 1.0, s = 0.5 → modulation = 2/(1+0.5) ≈ 1.333
      expect(modulateMuseTemperature(base: 1.0, calmSignals: const [0.5]),
          closeTo(4.0 / 3.0, 1e-12));
    });

    test('1e-3 floor prevents zero-product collapse on a single axis', () {
      // One chaotic axis at 0 alongside two calm axes at 1 would
      // produce geometricMean = (1e-3 · 1 · 1)^(1/3) ≈ 0.1.
      final calm =
          modulateMuseTemperature(base: 1.0, calmSignals: const [0.0, 1.0, 1.0]);
      // Modulation = 2 / (1 + 0.1) ≈ 1.818. Same base, the chaotic
      // axis pulls the composite low — exactly the weakest-link
      // behaviour the geometric mean is chosen for.
      final geomMean = math.pow(1e-3 * 1.0 * 1.0, 1.0 / 3.0).toDouble();
      expect(calm, closeTo(2.0 / (1.0 + geomMean), 1e-9));
      // Confirm the floor is doing the work: a single literal 0 with
      // no floor would zero the product and saturate modulation at 2.0
      // exactly. We're below saturation.
      expect(calm, lessThan(1.99));
    });

    test('all-calm signals leave temperature at base', () {
      // GeometricMean = 1.0 → modulation = 1.0 → returns base.
      expect(
          modulateMuseTemperature(base: 1.1, calmSignals: const [1.0, 1.0, 1.0]),
          closeTo(1.1, 1e-12));
    });

    test('all-zero signals saturate at the 1e-3 floor', () {
      // Every signal hits the floor → geometricMean = 1e-3 → modulation
      // = 2 / 1.001 ≈ 1.998 → base * 1.998 then clamped to 2.0.
      // base = 1.0 gives a result just under 2.0 (no clamp).
      final under = modulateMuseTemperature(
          base: 1.0, calmSignals: const [0.0, 0.0, 0.0]);
      expect(under, closeTo(2.0 / 1.001, 1e-9));
      // base = 1.2 would produce 1.2 × 1.998 ≈ 2.398 — clamped to 2.0.
      final overClamp = modulateMuseTemperature(
          base: 1.2, calmSignals: const [0.0, 0.0, 0.0]);
      expect(overClamp, equals(2.0));
    });

    test('output is clamped to [0.5, 2.0] for pathological bases', () {
      // base = 5.0 with calm = 1 (modulation 1) clamps to 2.0.
      expect(
          modulateMuseTemperature(base: 5.0, calmSignals: const [1.0]),
          equals(2.0));
      // base = 0.1 with calm = 1 (modulation 1) → 0.1, clamped to 0.5.
      expect(modulateMuseTemperature(base: 0.1, calmSignals: const [1.0]),
          equals(0.5));
    });

    test('geometric mean: order independence', () {
      // (a · b · c)^(1/3) is symmetric in a, b, c — reordering the
      // calm signals must not change the result.
      final a = modulateMuseTemperature(
          base: 1.0, calmSignals: const [0.2, 0.7, 0.95]);
      final b = modulateMuseTemperature(
          base: 1.0, calmSignals: const [0.95, 0.2, 0.7]);
      final c = modulateMuseTemperature(
          base: 1.0, calmSignals: const [0.7, 0.95, 0.2]);
      expect(a, closeTo(b, 1e-12));
      expect(b, closeTo(c, 1e-12));
    });

    test('monotonicity: lower composite → higher modulation', () {
      // Holding the count fixed at 3, lower-calm inputs should
      // produce strictly higher temperatures (more exploration).
      final hot = modulateMuseTemperature(
          base: 1.0, calmSignals: const [0.2, 0.2, 0.2]);
      final mid = modulateMuseTemperature(
          base: 1.0, calmSignals: const [0.5, 0.5, 0.5]);
      final cool = modulateMuseTemperature(
          base: 1.0, calmSignals: const [0.8, 0.8, 0.8]);
      expect(hot, greaterThan(mid));
      expect(mid, greaterThan(cool));
    });
  });
}
