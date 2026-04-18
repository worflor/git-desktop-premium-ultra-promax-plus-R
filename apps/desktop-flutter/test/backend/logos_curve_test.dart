// Tests for ObservableCurve + the engine curve constructors.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_chaos.dart' show relaxationCurve;
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_curve.dart';

CsrGraph _path(int n) {
  final edges = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n - 1; i++) {
    edges[i].add((i + 1, 1.0));
    edges[i + 1].add((i, 1.0));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

void main() {
  group('ObservableCurve — core ops', () {
    test('valueAt interpolates linearly', () {
      final c = ObservableCurve.sampled(
        xs: Float64List.fromList([0.0, 1.0, 2.0]),
        ys: Float64List.fromList([0.0, 10.0, 20.0]),
      );
      expect(c.valueAt(0.0), closeTo(0.0, 1e-12));
      expect(c.valueAt(0.5), closeTo(5.0, 1e-12));
      expect(c.valueAt(1.5), closeTo(15.0, 1e-12));
      expect(c.valueAt(2.0), closeTo(20.0, 1e-12));
    });

    test('valueAt clamps outside the sampled range', () {
      final c = ObservableCurve.sampled(
        xs: Float64List.fromList([0.0, 1.0]),
        ys: Float64List.fromList([3.0, 7.0]),
      );
      expect(c.valueAt(-5.0), equals(3.0));
      expect(c.valueAt(10.0), equals(7.0));
    });

    test('slopeAt matches analytical derivative of y = 2x + 1', () {
      final xs = Float64List.fromList([0.0, 1.0, 2.0, 3.0, 4.0]);
      final ys = Float64List.fromList([1.0, 3.0, 5.0, 7.0, 9.0]);
      final c = ObservableCurve.sampled(xs: xs, ys: ys);
      for (final x in [0.5, 1.5, 2.5, 3.5]) {
        expect(c.slopeAt(x), closeTo(2.0, 1e-10));
      }
    });

    test('integral of y = 2x + 1 over [0, 4] is 20', () {
      final xs = Float64List.fromList([0.0, 1.0, 2.0, 3.0, 4.0]);
      final ys = Float64List.fromList([1.0, 3.0, 5.0, 7.0, 9.0]);
      final c = ObservableCurve.sampled(xs: xs, ys: ys);
      // ∫₀⁴ (2x + 1) dx = x² + x |₀⁴ = 16 + 4 = 20. Trapezoidal is
      // exact on linear functions.
      expect(c.integral(), closeTo(20.0, 1e-10));
    });

    test('peak finds the maximum sample', () {
      final c = ObservableCurve.sampled(
        xs: Float64List.fromList([0.0, 1.0, 2.0, 3.0]),
        ys: Float64List.fromList([1.0, 5.0, 7.0, 2.0]),
      );
      final p = c.peak();
      expect(p.x, equals(2.0));
      expect(p.y, equals(7.0));
    });

    test('halfLife interpolates to the half-peak crossing', () {
      // Peak 10 at x=0; linearly drops to 0 at x=10. Half-life crossing
      // (y=5) should sit at x=5.
      final xs = Float64List.fromList([0.0, 5.0, 10.0]);
      final ys = Float64List.fromList([10.0, 5.0, 0.0]);
      final c = ObservableCurve.sampled(xs: xs, ys: ys);
      expect(c.halfLife(), closeTo(5.0, 1e-10));
    });

    test('halfLife returns null when the curve never drops to half', () {
      final xs = Float64List.fromList([0.0, 1.0, 2.0]);
      final ys = Float64List.fromList([10.0, 9.0, 8.0]);
      final c = ObservableCurve.sampled(xs: xs, ys: ys);
      expect(c.halfLife(), isNull);
    });

    test('logLogSlope recovers y = x^2 exponent (=2)', () {
      final xs = logspace(1.0, 100.0, 16);
      final ys = Float64List(xs.length);
      for (var i = 0; i < xs.length; i++) {
        ys[i] = xs[i] * xs[i];
      }
      final c = ObservableCurve.sampled(xs: xs, ys: ys);
      expect(c.logLogSlope()!, closeTo(2.0, 1e-10));
    });

    test('logLogSlope returns null on non-positive data', () {
      final c = ObservableCurve.sampled(
        xs: Float64List.fromList([1.0, 2.0, 3.0]),
        ys: Float64List.fromList([1.0, -1.0, 2.0]),
      );
      expect(c.logLogSlope(), isNull);
    });
  });

  group('heatTraceCurve', () {
    test('is monotone decreasing in t', () {
      final basis = SpectralBasis.fromGraph(_path(32), 32);
      final c = heatTraceCurve(basis, tMin: 0.1, tMax: 10.0, samples: 24);
      for (var i = 1; i < c.ys.length; i++) {
        expect(c.ys[i], lessThanOrEqualTo(c.ys[i - 1] + 1e-9),
            reason: 'Z(t) must be non-increasing; '
                'violation at i=$i (${c.ys[i]} > ${c.ys[i - 1]})');
      }
    });

    test('log-log slope near ≈ −d_s/2 on a path', () {
      // Path: d_s ≈ 1 → slope ≈ −0.5. Generous band for Lanczos
      // discretisation.
      final basis = SpectralBasis.fromGraph(_path(96), 96);
      final c = heatTraceCurve(basis, tMin: 0.2, tMax: 2.0, samples: 24);
      final slope = c.logLogSlope();
      expect(slope, isNotNull);
      expect(slope!, lessThan(-0.1));
      expect(slope, greaterThan(-1.0));
    });
  });

  group('zetaCurve', () {
    test('is log-convex in s (d²ζ/ds² > 0 everywhere)', () {
      // ζ(s) = Σ 1/λ^s → d²/ds² = Σ (log λ)² / λ^s ≥ 0. Monotonicity
      // direction depends on the smallest eigenvalue, so we test
      // convexity instead — it always holds.
      final basis = SpectralBasis.fromGraph(_path(40), 40);
      final c = zetaCurve(basis, sMin: 1.0, sMax: 3.0, samples: 24);
      for (var i = 1; i < c.ys.length - 1; i++) {
        final d2 = c.ys[i + 1] - 2 * c.ys[i] + c.ys[i - 1];
        expect(d2, greaterThanOrEqualTo(-1e-6),
            reason: 'ζ(s) must be convex; d² at i=$i was $d2');
      }
    });
  });

}
