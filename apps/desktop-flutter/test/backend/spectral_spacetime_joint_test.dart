// Tests for the joint-operator observables on SpacetimeBasis —
// jointKernelDim, excitedHeatTrace, jointLogDeterminant, jointZeta.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/spectral_spacetime.dart';

CsrGraph _path(int n) {
  final edges = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n - 1; i++) {
    edges[i].add((i + 1, 1.0));
    edges[i + 1].add((i, 1.0));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

CsrGraph _cycle(int n) {
  final edges = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    edges[i].add((j, 1.0));
    edges[j].add((i, 1.0));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

void main() {
  group('jointKernelDim', () {
    test('connected × connected → exactly one joint zero mode', () {
      final a = SpectralBasis.fromGraph(_path(12), 12);
      final b = SpectralBasis.fromGraph(_cycle(8), 8);
      final st = tensorSpectral(a, b);
      // Each factor has exactly one zero mode; the tensor-sum kernel
      // is the OUTER PRODUCT of the factor kernels, which is a single
      // pair (0, 0) → one joint zero eigenvalue.
      expect(st.jointKernelDim, equals(1));
      expect(st.jointNonZeroCount,
          equals(a.k * b.k - 1));
    });

  });

  group('excitedHeatTrace', () {
    test('equals heatTrace − jointKernelDim', () {
      final a = SpectralBasis.fromGraph(_path(10), 10);
      final b = SpectralBasis.fromGraph(_cycle(8), 8);
      final st = tensorSpectral(a, b);
      for (final t in [0.1, 1.0, 5.0, 20.0]) {
        expect(st.heatTrace(t) - st.excitedHeatTrace(t),
            closeTo(st.jointKernelDim.toDouble(), 1e-10),
            reason: 'at t=$t');
      }
    });

    test('decays monotonically and stays non-negative', () {
      final a = SpectralBasis.fromGraph(_path(10), 10);
      final b = SpectralBasis.fromGraph(_path(7), 7);
      final st = tensorSpectral(a, b);
      final samples = [0.1, 0.3, 1.0, 3.0, 10.0, 50.0];
      var last = double.infinity;
      for (final t in samples) {
        final v = st.excitedHeatTrace(t);
        expect(v, lessThanOrEqualTo(last + 1e-9));
        expect(v, greaterThanOrEqualTo(-1e-9));
        last = v;
      }
    });
  });

  group('jointLogDeterminant — NOT a factorisation', () {
    test('differs from the sum of factor logDets', () {
      // The joint logDet is Σ log(λ+μ), which is strictly not
      // log(λ) + log(μ) summed. So for non-trivial factors we
      // expect a measurable difference. This is the test that
      // validates: "the joint carries genuinely new information."
      final a = SpectralBasis.fromGraph(_path(12), 12);
      final b = SpectralBasis.fromGraph(_cycle(8), 8);
      final st = tensorSpectral(a, b);
      // Compute Σ log λ over non-zero space modes; same for time.
      var logSpace = 0.0;
      for (final j in a.nonZeroIndices) {
        logSpace += math.log(a.eigenvalues[j]);
      }
      var logTime = 0.0;
      for (final j in b.nonZeroIndices) {
        logTime += math.log(b.eigenvalues[j]);
      }
      // If the factorisation held, joint = k_time · logSpace +
      // k_space · logTime (the product formula for a Kronecker
      // PRODUCT, not SUM). The joint for a Kronecker SUM is
      // Σᵢⱼ log(λᵢ+μⱼ), which is NOT a simple linear combination.
      final naiveProductGuess = b.k * logSpace + a.k * logTime;
      expect((st.jointLogDeterminant - naiveProductGuess).abs(),
          greaterThan(0.5),
          reason: 'joint=${st.jointLogDeterminant}, '
              'naive product-formula guess=$naiveProductGuess — '
              'they MUST differ since L is a Kronecker sum, not product');
    });
  });

  group('jointZeta', () {
    test('ζ_joint(0) equals jointNonZeroCount', () {
      final a = SpectralBasis.fromGraph(_path(10), 10);
      final b = SpectralBasis.fromGraph(_path(6), 6);
      final st = tensorSpectral(a, b);
      expect(st.jointZeta(0.0),
          closeTo(st.jointNonZeroCount.toDouble(), 1e-9));
    });

    test('ζ_joint(s) is convex in s', () {
      // Same identity as the non-joint zeta: d²/ds² (1/λ^s) > 0.
      final a = SpectralBasis.fromGraph(_path(10), 10);
      final b = SpectralBasis.fromGraph(_cycle(8), 8);
      final st = tensorSpectral(a, b);
      final ss = [1.0, 1.5, 2.0, 2.5, 3.0];
      final values = ss.map(st.jointZeta).toList();
      for (var i = 1; i < values.length - 1; i++) {
        final d2 = values[i + 1] - 2 * values[i] + values[i - 1];
        expect(d2, greaterThanOrEqualTo(-1e-6),
            reason: 'joint ζ(s) must be convex; d² at i=$i was $d2');
      }
    });
  });

  group('integer-s fast path equivalence', () {
    // Same Circle IV test as logos_zeta — the integer branch must
    // agree with the general path on sensible integers.
    test('jointZeta(integer) is consistent with jointZeta(non-integer)',
        () {
      final a = SpectralBasis.fromGraph(_path(14), 14);
      final b = SpectralBasis.fromGraph(_cycle(10), 10);
      final st = tensorSpectral(a, b);
      // Sample the general path at s ever-so-slightly off an integer.
      for (final target in [1, 2]) {
        final integerPath = st.jointZeta(target.toDouble());
        final perturbedPath = st.jointZeta(target + 1e-9);
        // Both should be finite and within a small relative band —
        // the ULP difference between `pow(λ, -2)` and `1/(λ*λ)` is
        // single-digit ULPs in total.
        expect(integerPath.isFinite, isTrue);
        expect(perturbedPath.isFinite, isTrue);
        final rel =
            (integerPath - perturbedPath).abs() / integerPath.abs();
        expect(rel, lessThan(1e-6),
            reason: 'integer path=$integerPath, '
                'perturbed=$perturbedPath, rel=$rel at s=$target');
      }
    });

  });

  group('sanity — factor heatTrace product', () {
    test('preserves the documented identity heatTrace = Z_A · Z_B', () {
      // This is the pre-existing `heatTrace` identity; reaffirm it
      // wasn't accidentally broken by the additions.
      final a = SpectralBasis.fromGraph(_path(10), 10);
      final b = SpectralBasis.fromGraph(_cycle(6), 6);
      final st = tensorSpectral(a, b);
      for (final t in [0.2, 1.0, 3.0]) {
        expect(st.heatTrace(t),
            closeTo(a.heatTrace(t) * b.heatTrace(t), 1e-10));
      }
    });
  });
}
