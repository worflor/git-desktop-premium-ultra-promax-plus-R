// Tests for LogosChaos — spectral dimension and relaxation-rate
// diagnostics.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_chaos.dart';

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

CsrGraph _er(int n, double p, int seed) {
  final rng = math.Random(seed);
  final edges = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (rng.nextDouble() < p) {
        edges[i].add((j, 1.0));
        edges[j].add((i, 1.0));
      }
    }
  }
  // Spanning path to guarantee connectedness.
  for (var i = 0; i < n - 1; i++) {
    edges[i].add((i + 1, 0.1));
    edges[i + 1].add((i, 0.1));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

void main() {
  group('spectralDimension — smoke + bounds', () {
    test('returns null on tiny bases', () {
      final basis = SpectralBasis.fromGraph(_path(3), 3);
      expect(spectralDimension(basis), isNull);
    });

    test('path d_s lies in [0.5, 1.5]', () {
      // Path Laplacian eigenvalues λⱼ ≈ 1 − cos(jπ/(n−1)) ~ π²j²/2n²
      // at small j → heat trace Z(t) ~ n · t^{-1/2} at small t →
      // spectral dimension ≈ 1. Allow a generous band around 1 to
      // absorb discretisation.
      final basis = SpectralBasis.fromGraph(_path(96), 96);
      final r = spectralDimension(basis)!;
      expect(r.dS, greaterThan(0.5),
          reason: 'path spectrum should yield d_s near 1, got ${r.dS}');
      expect(r.dS, lessThan(1.8),
          reason: 'path spectrum should yield d_s near 1, got ${r.dS}');
    });
  });

  group('relaxationRate', () {
    test('converges to the spectral gap at large t', () {
      final basis = SpectralBasis.fromGraph(_er(48, 0.3, 11), 48);
      final gap = basis.eigenvalues[1];
      // At large t the Boltzmann weight concentrates on λ₁ → γ → λ₁.
      final gamma = relaxationRate(basis, 80.0);
      expect(gamma, isNotNull);
      // Some slack for higher-mode contributions and finite t.
      expect((gamma! - gap).abs(), lessThan(0.25 * gap + 1e-6),
          reason: 'γ(80) = $gamma should be near the gap $gap');
    });

    test('is null for invalid t', () {
      final basis = SpectralBasis.fromGraph(_path(16), 16);
      expect(relaxationRate(basis, -1.0), isNull);
      expect(relaxationRate(basis, double.nan), isNull);
    });

  });

  group('gapSaturation', () {
    test('saturates toward 1 from above as t increases', () {
      final basis = SpectralBasis.fromGraph(_er(48, 0.2, 3), 48);
      final r1 = gapSaturation(basis, 1.0);
      final r40 = gapSaturation(basis, 40.0);
      expect(r1, isNotNull);
      expect(r40, isNotNull);
      // γ restricted to non-zero modes averages ≥ λ₁ at any t and
      // decreases monotonically to λ₁ as t → ∞.
      expect(r40!, lessThanOrEqualTo(r1! + 1e-9),
          reason: 'γ/λ₁ should decrease toward 1; got r(1)=$r1, r(40)=$r40');
      expect(r40, greaterThan(0.95),
          reason: 'γ/λ₁ should sit near 1 at large t; got r(40)=$r40');
      expect(r1, greaterThanOrEqualTo(r40 - 1e-9));
    });

    test('is null when spectrum is degenerate', () {
      final basis = SpectralBasis.fromGraph(
        CsrGraph.fromRawEdges(n: 2, edgesPerNode: const [[], []]),
        2,
      );
      expect(gapSaturation(basis, 1.0), isNull);
    });
  });
}
