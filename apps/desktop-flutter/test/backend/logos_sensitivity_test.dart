// Tests for LogosSensitivity — per-edge Hellmann-Feynman functions
// and the unified SensitivityField.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_sensitivity.dart';
import 'package:git_desktop/backend/logos_zeta.dart';

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
  // Spanning path guarantees connectedness.
  for (var i = 0; i < n - 1; i++) {
    edges[i].add((i + 1, 0.1));
    edges[i + 1].add((i, 0.1));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

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

/// Barbell: two triangles connected by a single bridge edge.
CsrGraph _barbell() {
  final edges = List<List<(int, double)>>.generate(6, (_) => []);
  void add(int a, int b, double w) {
    edges[a].add((b, w));
    edges[b].add((a, w));
  }
  add(0, 1, 1.0); add(1, 2, 1.0); add(0, 2, 1.0);
  add(3, 4, 1.0); add(4, 5, 1.0); add(3, 5, 1.0);
  add(2, 3, 0.5); // the bridge
  return CsrGraph.fromRawEdges(n: 6, edgesPerNode: edges);
}

void main() {
  group('per-edge functions — sanity', () {
    test('eigenvalueSensitivity returns 0 on out-of-range indices', () {
      final basis = SpectralBasis.fromGraph(_path(16), 16);
      expect(eigenvalueSensitivity(basis, -1, 5, 0), equals(0.0));
      expect(eigenvalueSensitivity(basis, 0, 100, 0), equals(0.0));
      expect(eigenvalueSensitivity(basis, 0, 1, 200), equals(0.0));
    });

    test('heatTraceSensitivity non-positive for any positive t', () {
      final basis = SpectralBasis.fromGraph(_cycle(12), 12);
      for (final t in [0.1, 1.0, 5.0]) {
        for (var a = 0; a < 12; a++) {
          for (var b = a + 1; b < 12; b++) {
            expect(heatTraceSensitivity(basis, a, b, t),
                lessThanOrEqualTo(1e-12));
          }
        }
      }
    });

    test('zetaSensitivity sign matches −s for s > 0', () {
      final basis = SpectralBasis.fromGraph(_path(16), 16);
      for (final s in [0.5, 1.0, 2.0, 3.0]) {
        for (var a = 0; a < 16; a++) {
          for (var b = a + 1; b < 16; b++) {
            expect(zetaSensitivity(basis, a, b, s),
                lessThanOrEqualTo(1e-9));
          }
        }
      }
    });

    test('spectralGapSensitivity is null on a ground-only basis', () {
      final g = CsrGraph.fromRawEdges(
        n: 3,
        edgesPerNode: const [[], [], []],
      );
      final basis = SpectralBasis.fromGraph(g, 3);
      if (basis.isGroundOnly) {
        expect(spectralGapSensitivity(basis, 0, 1), isNull);
      }
    });
  });

  group('SensitivityField — construction & caching', () {
    test('caches the transpose across observables', () {
      // The first call to any field observable builds the transpose.
      // The second call (different observable) reuses it. We can't
      // directly observe "reuse", but we CAN verify the results
      // stay consistent regardless of call order.
      final g = _path(32);
      final basis = SpectralBasis.fromGraph(g, 32);

      final f1 = SensitivityField(g, basis);
      final heat1 = f1.heatTrace(t: 1.0);
      final log1 = f1.logDet();

      final f2 = SensitivityField(g, basis);
      final log2 = f2.logDet();
      final heat2 = f2.heatTrace(t: 1.0);

      // Same inputs, reversed call order → identical output.
      expect(heat1.length, equals(heat2.length));
      expect(log1.length, equals(log2.length));
      for (var i = 0; i < heat1.length; i++) {
        expect(heat1[i].a, equals(heat2[i].a));
        expect(heat1[i].b, equals(heat2[i].b));
      }
    });

    test('repeated calls return the same cached list instance', () {
      final g = _path(20);
      final basis = SpectralBasis.fromGraph(g, 20);
      final f = SensitivityField(g, basis);
      final a = f.logDet();
      final b = f.logDet();
      // Same identity: cache hit returns the same reference.
      expect(identical(a, b), isTrue);
    });

    test('heatTrace caches per temperature (distinct t → distinct result)',
        () {
      final g = _cycle(16);
      final basis = SpectralBasis.fromGraph(g, 16);
      final f = SensitivityField(g, basis);
      final atOne = f.heatTrace(t: 1.0);
      final atFive = f.heatTrace(t: 5.0);
      expect(identical(atOne, atFive), isFalse);
      // Magnitudes differ at different temperatures.
      expect(atOne.first.value.abs(),
          isNot(closeTo(atFive.first.value.abs(), 1e-9)));
      // Same t returns the same cached instance.
      expect(identical(atOne, f.heatTrace(t: 1.0)), isTrue);
    });

    test('invalidate() clears observable caches but keeps transpose', () {
      final g = _path(20);
      final basis = SpectralBasis.fromGraph(g, 20);
      final f = SensitivityField(g, basis);
      final before = f.gap();
      f.invalidate();
      final after = f.gap();
      // Post-invalidate call recomputes; different instance.
      expect(identical(before, after), isFalse);
      // Values still agree (pure function of inputs).
      expect(before.length, equals(after.length));
      for (var i = 0; i < before.length; i++) {
        expect(before[i].a, equals(after[i].a));
        expect(before[i].b, equals(after[i].b));
        expect(before[i].value, closeTo(after[i].value, 1e-12));
      }
    });
  });

  group('SensitivityField — observable invariants', () {
    test('gap ranks the barbell bridge first', () {
      final g = _barbell();
      final basis = SpectralBasis.fromGraph(g, g.n);
      final f = SensitivityField(g, basis).gap();
      expect(f, isNotEmpty);
      final top = f.first;
      expect(
          (top.a == 2 && top.b == 3) || (top.a == 3 && top.b == 2),
          isTrue,
          reason: 'bridge (2,3) should dominate; got ($top.a,$top.b)');
    });

    test('all fields sorted by |value| descending', () {
      final g = _er(40, 0.15, 11);
      final basis = SpectralBasis.fromGraph(g, g.n);
      final f = SensitivityField(g, basis);
      for (final field in [f.heatTrace(t: 1.0), f.logDet(), f.gap()]) {
        for (var i = 1; i < field.length; i++) {
          expect(field[i].value.abs(),
              lessThanOrEqualTo(field[i - 1].value.abs() + 1e-12));
        }
      }
    });

  });

  group('magnitude ordering — Fiedler dominance on path', () {
    test('Fiedler sign-change edge has largest λ₁ sensitivity', () {
      final g = _path(10);
      final basis = SpectralBasis.fromGraph(g, g.n);
      final j = basis.firstExcitedIndex;
      double best = 0.0;
      var bestEdge = -1;
      for (var i = 0; i < 9; i++) {
        final s = eigenvalueSensitivity(basis, i, i + 1, j);
        if (s > best) {
          best = s;
          bestEdge = i;
        }
      }
      expect(bestEdge, greaterThanOrEqualTo(3));
      expect(bestEdge, lessThanOrEqualTo(6));
    });
  });

  group('cross-check with zetaReport', () {
    test('sum over edges of logDetSensitivity ≤ 2·tr(L⁻¹)', () {
      final g = _cycle(12);
      final basis = SpectralBasis.fromGraph(g, g.n);
      var total = 0.0;
      for (var u = 0; u < g.n; u++) {
        final p0 = g.indptr[u];
        final p1 = g.indptr[u + 1];
        for (var p = p0; p < p1; p++) {
          final v = g.indices[p];
          if (v <= u) continue;
          total += logDetSensitivity(basis, u, v);
        }
      }
      final zetaOne = zetaReport(basis).zetaOne;
      expect(total, lessThanOrEqualTo(2.0 * zetaOne + 1e-6));
    });
  });
}
