// Tests for LogosRMT — the random-matrix-theory spectral classifier.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_rmt.dart';

CsrGraph _path(int n) {
  final edges = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n - 1; i++) {
    edges[i].add((i + 1, 1.0));
    edges[i + 1].add((i, 1.0));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

CsrGraph _er(int n, double p, int seed) {
  // Erdős-Rényi random graph — expected GOE statistics at large n.
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
  // Guarantee connectedness with a spanning path so Lanczos has
  // something to work with.
  for (var i = 0; i < n - 1; i++) {
    edges[i].add((i + 1, 0.1));
    edges[i + 1].add((i, 0.1));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

void main() {
  group('rmtReport', () {
    test('returns null on tiny bases', () {
      final basis = SpectralBasis.fromGraph(_path(3), 3);
      expect(rmtReport(basis), isNull);
    });

    test('path spectrum classifies as crystalline (very regular)', () {
      // Path eigenvalues λⱼ ≈ 1 − cos(jπ/(n−1)) have smoothly-varying
      // spacings; consecutive spacings are very similar → high meanR
      // pushing into the crystalline band (> 0.70). Documented-lesson
      // regression: our first attempt got this wrong.
      final basis = SpectralBasis.fromGraph(_path(64), 64);
      final r = rmtReport(basis);
      expect(r, isNotNull);
      expect(r!.classification, RmtClass.crystalline,
          reason: 'path meanR should land in the crystalline band, '
              'got ${r.meanR} → ${r.classification}');
    });

    test('ER meanR is closer to GOE value than path meanR is', () {
      final pathBasis = SpectralBasis.fromGraph(_path(64), 64);
      final erBasis = SpectralBasis.fromGraph(_er(64, 0.2, 7), 64);
      final rPath = rmtReport(pathBasis);
      final rEr = rmtReport(erBasis);
      expect(rPath, isNotNull);
      expect(rEr, isNotNull);
      final erDist = (rEr!.meanR - kGoeMeanR).abs();
      final pathDist = (rPath!.meanR - kGoeMeanR).abs();
      expect(erDist, lessThan(pathDist),
          reason: 'ER (chaotic) should sit closer to GOE ${kGoeMeanR} than '
              'a path (${rPath.meanR}); ER gave ${rEr.meanR}');
    });

    test('numberVariance null on tiny spectra', () {
      final basis = SpectralBasis.fromGraph(_path(6), 6);
      expect(numberVariance(basis, 2.0), isNull);
    });
  });
}
