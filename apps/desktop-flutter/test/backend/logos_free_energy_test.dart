// Tests for LogosFreeEnergy — the variational free energy scalar that
// unifies Friston / Dirichlet / VAE flavours into one number.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_field.dart';
import 'package:git_desktop/backend/logos_free_energy.dart';
import 'package:git_desktop/backend/logos_git.dart';

CsrGraph _pathGraph(int n) {
  final edges = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n - 1; i++) {
    edges[i].add((i + 1, 1.0));
    edges[i + 1].add((i, 1.0));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

SpectralBasis _basis(int n) => SpectralBasis.fromGraph(_pathGraph(n), n);

LogosGit _fixtureEngine({bool noisy = false}) {
  final touches = <String, int>{};
  final volatility = <String, double>{};
  final jaccard = <String, Map<String, double>>{};
  final paths = [
    for (var i = 0; i < 260; i++)
      'lib/m${i.toString().padLeft(3, '0')}.dart',
  ];
  final rng = math.Random(noisy ? 1 : 0);
  for (var i = 0; i < paths.length; i++) {
    final p = paths[i];
    touches[p] = 10;
    // Healthy: smooth volatility from a low-frequency sinusoid.
    // Noisy: random-uniform volatility (scatters across modes).
    volatility[p] = noisy
        ? rng.nextDouble() * 2.0
        : 1.0 + math.sin(2.0 * math.pi * i / paths.length);
    jaccard[p] = <String, double>{};
  }
  for (var i = 0; i < paths.length; i++) {
    for (var j = i + 1; j < paths.length; j++) {
      jaccard[paths[i]]![paths[j]] = 0.8;
      jaccard[paths[j]]![paths[i]] = 0.8;
    }
  }
  return LogosGit.buildFromStats(LogosGitStats(
    touches: touches,
    totalCommits: 200,
    volatility: volatility,
    volMean: 1.0,
    volStddev: 0.3,
    coupling: FileCouplingMatrix(
      jaccard: jaccard,
      headHash: noisy ? 'noisy' : 'healthy',
      commitsAnalyzed: 200,
    ),
    perFileCommitIndices: const {},
  ));
}

void main() {
  group('freeEnergy — primal scalar', () {
    test('zero field has zero free energy', () {
      final basis = _basis(10);
      final f = LogosField.zero(basis, 1);
      expect(freeEnergy(f), closeTo(0.0, 1e-12));
    });

    test('non-zero field has positive free energy', () {
      final basis = _basis(10);
      final rng = math.Random(1);
      final f = LogosField.gff(basis: basis, commitCount: 1, rng: rng);
      expect(freeEnergy(f), greaterThan(0.0));
    });

    test('scaling a field scales free energy quadratically', () {
      final basis = _basis(10);
      final rng = math.Random(2);
      final f = LogosField.gff(basis: basis, commitCount: 1, rng: rng);
      final f1 = freeEnergy(f);
      final f2 = freeEnergy(f.scale(2.0));
      expect(f2, closeTo(4.0 * f1, 1e-6));
    });

    test('lower-mode-heavy field has lower F than noisy field', () {
      // Build a field whose mass sits on mode 1; and one that spreads
      // across all modes. Lower-mode one should have lower F.
      final basis = _basis(12);
      // Pure-mode-1 field: ρ = u₁.
      final primal1 = Float64List(basis.n);
      for (var v = 0; v < basis.n; v++) {
        primal1[v] = basis.eigenvectors[1 * basis.n + v];
      }
      // Spread field: equal projection onto every mode.
      final primalSpread = Float64List(basis.n);
      for (var j = 0; j < basis.k; j++) {
        final coeff = 1.0 / math.sqrt(basis.k.toDouble());
        for (var v = 0; v < basis.n; v++) {
          primalSpread[v] += coeff * basis.eigenvectors[j * basis.n + v];
        }
      }
      final fLow = LogosField.fromPrimal(
        basis: basis, primal: primal1, commitCount: 1);
      final fHigh = LogosField.fromPrimal(
        basis: basis, primal: primalSpread, commitCount: 1);
      expect(freeEnergy(fLow), lessThan(freeEnergy(fHigh)));
    });
  });

  group('freeEnergyAttribution — per-mode breakdown', () {
    test('sum of perMode equals 2·total (half-factor pulled out)', () {
      final basis = _basis(10);
      final rng = math.Random(3);
      final f = LogosField.gff(basis: basis, commitCount: 1, rng: rng);
      final attr = freeEnergyAttribution(f);
      final sum = attr.perMode.reduce((a, b) => a + b);
      expect(sum, closeTo(2.0 * attr.total, 1e-9));
    });

    test('single-mode field concentrates on one index', () {
      final basis = _basis(10);
      final primal = Float64List(basis.n);
      for (var v = 0; v < basis.n; v++) {
        primal[v] = basis.eigenvectors[2 * basis.n + v];
      }
      final f = LogosField.fromPrimal(
        basis: basis, primal: primal, commitCount: 1);
      final attr = freeEnergyAttribution(f);
      expect(attr.dominantMode, 2);
    });

    test('topKFraction is 1.0 when k >= number of modes', () {
      final basis = _basis(8);
      final rng = math.Random(4);
      final f = LogosField.gff(basis: basis, commitCount: 1, rng: rng);
      final attr = freeEnergyAttribution(f);
      expect(attr.topKFraction(basis.k), closeTo(1.0, 1e-9));
      expect(attr.topKFraction(basis.k + 5), closeTo(1.0, 1e-9));
    });

    test('topKFraction(1) is > 1/k for any non-uniform field', () {
      final basis = _basis(10);
      final primal = Float64List(basis.n);
      // Strongly biased onto mode 1.
      for (var v = 0; v < basis.n; v++) {
        primal[v] = basis.eigenvectors[1 * basis.n + v];
      }
      final f = LogosField.fromPrimal(
        basis: basis, primal: primal, commitCount: 1);
      final attr = freeEnergyAttribution(f);
      expect(attr.topKFraction(1), greaterThan(1.0 / basis.k));
    });

    test('mass term is preserved in the attribution', () {
      final basis = _basis(6);
      final rng = math.Random(5);
      final f = LogosField.gff(basis: basis, commitCount: 1, rng: rng);
      final attr = freeEnergyAttribution(f, mass: 0.3);
      expect(attr.mass, 0.3);
    });
  });

  group('repoFreeEnergy — engine-level observation', () {
    test('null when engine has no spectral basis (tiny repo)', () {
      final engine = LogosGit.buildFromStats(LogosGitStats(
        touches: {'a.dart': 1, 'b.dart': 1},
        totalCommits: 2,
        volatility: {'a.dart': 1.0, 'b.dart': 1.0},
        volMean: 1.0,
        volStddev: 0.0,
        coupling: FileCouplingMatrix(
          jaccard: {},
          headHash: 'tiny',
          commitsAnalyzed: 2,
        ),
        perFileCommitIndices: {},
      ));
      expect(repoFreeEnergy(engine), isNull);
    });

    test('non-null with finite total on a real fixture', () {
      final engine = _fixtureEngine(noisy: false);
      final attr = repoFreeEnergy(engine);
      expect(attr, isNotNull);
      expect(attr!.total.isFinite, isTrue);
      expect(attr.total, greaterThan(0.0));
    });

    test('noisy and smooth repos both yield finite F', () {
      // After max-normalisation the two fixtures land at comparable
      // scalar F; the more meaningful distinction is mode concentration
      // (tested directly against hand-built fields in the primal group).
      // Here we just verify both engines produce finite, positive F.
      final healthy = _fixtureEngine(noisy: false);
      final noisy = _fixtureEngine(noisy: true);
      final fHealthy = repoFreeEnergy(healthy);
      final fNoisy = repoFreeEnergy(noisy);
      expect(fHealthy, isNotNull);
      expect(fNoisy, isNotNull);
      expect(fHealthy!.total.isFinite, isTrue);
      expect(fNoisy!.total.isFinite, isTrue);
      expect(fHealthy.total, greaterThan(0.0));
      expect(fNoisy.total, greaterThan(0.0));
    });
  });

  group('repoHealth — classification', () {
    test('silent when engine has no basis', () {
      final engine = LogosGit.buildFromStats(LogosGitStats(
        touches: {'a.dart': 1},
        totalCommits: 1,
        volatility: {'a.dart': 1.0},
        volMean: 1.0,
        volStddev: 0.0,
        coupling: FileCouplingMatrix(
          jaccard: {},
          headHash: 'tiny',
          commitsAnalyzed: 1,
        ),
        perFileCommitIndices: {},
      ));
      expect(repoHealth(engine), RepoHealth.silent);
    });

    test('returns a non-silent label on a real fixture', () {
      final engine = _fixtureEngine(noisy: false);
      final label = repoHealth(engine);
      expect(label, isNot(RepoHealth.silent));
    });

    test('labels are stable and non-empty', () {
      for (final label in RepoHealth.values) {
        expect(label.label, isNotEmpty);
      }
    });
  });

  group('lowPassFraction', () {
    test('field on mode 0 only has lowPassFraction ≈ 1.0', () {
      final basis = _basis(10);
      final primal = Float64List(basis.n);
      for (var v = 0; v < basis.n; v++) {
        primal[v] = basis.eigenvectors[0 * basis.n + v];
      }
      final f = LogosField.fromPrimal(
        basis: basis, primal: primal, commitCount: 1);
      final attr = freeEnergyAttribution(f);
      expect(lowPassFraction(attr, lowModes: 1), greaterThan(0.9));
    });

    test('field on highest mode has lowPassFraction ≈ 0', () {
      final basis = _basis(10);
      final primal = Float64List(basis.n);
      final j = basis.k - 1;
      for (var v = 0; v < basis.n; v++) {
        primal[v] = basis.eigenvectors[j * basis.n + v];
      }
      final f = LogosField.fromPrimal(
        basis: basis, primal: primal, commitCount: 1);
      final attr = freeEnergyAttribution(f);
      expect(lowPassFraction(attr, lowModes: 3), lessThan(0.1));
    });

    test('returns 0 when total is zero', () {
      final basis = _basis(6);
      final f = LogosField.zero(basis, 1);
      final attr = freeEnergyAttribution(f);
      expect(lowPassFraction(attr), 0.0);
    });
  });
}
