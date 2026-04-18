// Tests for LogosSpectroGeometry — unified geometric fingerprint.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_spectrogeometry.dart';

CsrGraph _path(int n) {
  final edges = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n - 1; i++) {
    edges[i].add((i + 1, 1.0));
    edges[i + 1].add((i, 1.0));
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
  for (var i = 0; i < n - 1; i++) {
    edges[i].add((i + 1, 0.1));
    edges[i + 1].add((i, 0.1));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

void main() {
  group('spectrogeometry — smoke', () {
    test('returns a fully-populated report on a workable graph', () {
      final g = _path(64);
      final basis = SpectralBasis.fromGraph(g, 64);
      final sg = spectrogeometry(g, basis);
      expect(sg.rmt, isNotNull);
      expect(sg.persistence, isNotNull);
      expect(sg.spectralDim, isNotNull);
      expect(sg.zeta.nonZeroCount, greaterThan(0));
      expect(sg.fingerprint.isZero, isFalse);
      // Every universality distance lives in [0, 1].
      final u = sg.universality;
      for (final d in [
        u.toCrystalline, u.toPoisson, u.toGoe, u.toTree,
        u.toBulk, u.toModular,
      ]) {
        expect(d, greaterThanOrEqualTo(0.0));
        expect(d, lessThanOrEqualTo(1.0));
      }
    });

  });

  group('universality — archetype assignment', () {
    test('path graph lands closest to crystalline', () {
      final g = _path(80);
      final basis = SpectralBasis.fromGraph(g, 80);
      final sg = spectrogeometry(g, basis);
      expect(sg.universality.nearest.name, equals('crystalline'),
          reason: 'path should classify as crystalline; '
              'got ${sg.universality.nearest}');
    });

    test('dense ER graph does NOT land closest to crystalline', () {
      final g = _er(48, 0.5, 7);
      final basis = SpectralBasis.fromGraph(g, 48);
      final sg = spectrogeometry(g, basis);
      expect(sg.universality.nearest.name, isNot(equals('crystalline')),
          reason: 'dense random graph should not classify as '
              'crystalline; got ${sg.universality.nearest}');
    });

  });

  group('fingerprint — reproducibility', () {
    test('identical graphs produce identical fingerprints', () {
      final g1 = _path(32);
      final g2 = _path(32);
      final b1 = SpectralBasis.fromGraph(g1, 32);
      final b2 = SpectralBasis.fromGraph(g2, 32);
      final sg1 = spectrogeometry(g1, b1);
      final sg2 = spectrogeometry(g2, b2);
      expect(sg1.fingerprint, equals(sg2.fingerprint));
    });

    test('structurally-distinct graphs have distinct fingerprints', () {
      final gPath = _path(32);
      final gEr = _er(32, 0.3, 9);
      final sgPath = spectrogeometry(
          gPath, SpectralBasis.fromGraph(gPath, 32));
      final sgEr = spectrogeometry(gEr, SpectralBasis.fromGraph(gEr, 32));
      expect(sgPath.fingerprint, isNot(equals(sgEr.fingerprint)));
    });
  });

  group('degenerate inputs', () {
    test('graph with no edges yields a report without crashing', () {
      final g = CsrGraph.fromRawEdges(
        n: 5,
        edgesPerNode: const [[], [], [], [], []],
      );
      final b = SpectralBasis.fromGraph(g, 5);
      final sg = spectrogeometry(g, b);
      // Persistence is null (no edges to filter on); the other three
      // modules return whatever their degenerate-spectrum branches
      // produce. We only require no crash + finite zeta scalars.
      expect(sg.persistence, isNull);
      expect(sg.zeta.logDeterminant.isFinite, isTrue);
      expect(sg.universality.canonicality.isFinite, isTrue);
    });
  });
}
