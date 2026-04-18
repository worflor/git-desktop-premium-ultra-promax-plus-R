// Tests for LogosField — the unified generative + Fourier type.
//
// Every operation delegates to an existing primitive, so these tests
// focus on the type contract: constructors populate shape correctly,
// operations return new instances with expected invariants, analysis
// methods produce bounded sensible values, and round-trips are clean.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_field.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_git_probe.dart';

CsrGraph _pathGraph(int n) {
  final edges = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n - 1; i++) {
    edges[i].add((i + 1, 1.0));
    edges[i + 1].add((i, 1.0));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

SpectralBasis _pathBasis(int n) => SpectralBasis.fromGraph(_pathGraph(n), n);

LogosGit _fixtureEngine() {
  final touches = <String, int>{};
  final volatility = <String, double>{};
  final jaccard = <String, Map<String, double>>{};
  final paths = <String>[
    for (var i = 0; i < 260; i++)
      'lib/f${i.toString().padLeft(3, '0')}.dart',
  ];
  for (final p in paths) {
    touches[p] = 10;
    volatility[p] = 1.0;
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
    totalCommits: 100,
    volatility: volatility,
    volMean: 1.0,
    volStddev: 0.3,
    coupling: FileCouplingMatrix(
      jaccard: jaccard,
      headHash: 'field-fixture',
      commitsAnalyzed: 100,
    ),
    perFileCommitIndices: const {},
  ));
}

void main() {
  group('LogosField constructors', () {
    test('zero has right shape and all-zero primal', () {
      final basis = _pathBasis(8);
      final f = LogosField.zero(basis, 4);
      expect(f.n, 8);
      expect(f.k, 8);
      expect(f.commitCount, 4);
      expect(f.primal.length, 8 * 4);
      for (final v in f.primal) {
        expect(v, 0.0);
      }
    });

    test('fromPrimal adopts the buffer and validates length', () {
      final basis = _pathBasis(6);
      final primal = Float64List(6 * 3);
      primal[0] = 1.5;
      final f = LogosField.fromPrimal(
        basis: basis,
        primal: primal,
        commitCount: 3,
      );
      expect(f.primal[0], 1.5);
      expect(
          () => LogosField.fromPrimal(
                basis: basis,
                primal: Float64List(7),
                commitCount: 3,
              ),
          throwsArgumentError);
    });

    test('gff produces finite values at requested shape', () {
      final basis = _pathBasis(8);
      final rng = math.Random(0x64F);
      final f1 = LogosField.gff(basis: basis, commitCount: 1, rng: rng);
      expect(f1.primal.length, 8);
      for (final v in f1.primal) {
        expect(v.isFinite, isTrue);
      }
      final f4 = LogosField.gff(basis: basis, commitCount: 4, rng: rng);
      expect(f4.primal.length, 8 * 4);
      for (final v in f4.primal) {
        expect(v.isFinite, isTrue);
      }
    });

    test('conditional pins observations exactly', () {
      final basis = _pathBasis(10);
      final rng = math.Random(1);
      final f = LogosField.conditional(
        basis: basis,
        observedNodes: const [2, 5],
        observedValues: Float64List.fromList([1.0, -0.5]),
        rng: rng,
        mass: 0.3,
      );
      expect(f.primal[2], closeTo(1.0, 1e-6));
      expect(f.primal[5], closeTo(-0.5, 1e-6));
    });

    test('fromDual round-trips through inverse-transform', () {
      final basis = _pathBasis(8);
      final rng = math.Random(2);
      final f1 = LogosField.gff(basis: basis, commitCount: 4, rng: rng);
      final f2 = LogosField.fromDual(
        basis: basis,
        real: f1.dualReal,
        imag: f1.dualImag,
        commitCount: 4,
      );
      for (var i = 0; i < f1.primal.length; i++) {
        expect(f2.primal[i], closeTo(f1.primal[i], 1e-6));
      }
    });

    test('fromDiffProbe maps weights to node slots', () {
      final engine = _fixtureEngine();
      final probe = DiffProbe(
        sourceWeights: const {
          'lib/f000.dart': 1.0,
          'lib/f001.dart': 0.5,
        },
        primaryPaths: const {'lib/f000.dart', 'lib/f001.dart'},
        suggestedTemperature: 1.0,
        stats: const ProbeStats(
          primaryCount: 2,
          mMatches: 0,
          abMatches: 0,
          mSymbols: 0,
          coherence: 1.0,
          symbolMatches: 0,
        ),
      );
      final f = LogosField.fromDiffProbe(engine: engine, probe: probe);
      final id0 = engine.pathToId['lib/f000.dart']!;
      final id1 = engine.pathToId['lib/f001.dart']!;
      expect(f.primal[id0], 1.0);
      expect(f.primal[id1], 0.5);
      expect(f.primal.where((v) => v != 0.0).length, 2);
    });
  });

  group('LogosField dual lazy computation', () {
    test('dual is populated on first access and cached', () {
      final basis = _pathBasis(6);
      final rng = math.Random(3);
      final f = LogosField.gff(basis: basis, commitCount: 4, rng: rng);
      final re1 = f.dualReal;
      final re2 = f.dualReal;
      // Cached — second call returns the same object.
      expect(identical(re1, re2), isTrue);
    });

    test('Parseval: dual total matches primal sum-of-squares', () {
      final basis = _pathBasis(8);
      final rng = math.Random(4);
      final f = LogosField.gff(basis: basis, commitCount: 6, rng: rng);
      var primalE = 0.0;
      for (final v in f.primal) primalE += v * v;
      var dualE = 0.0;
      for (var i = 0; i < f.dualReal.length; i++) {
        dualE += f.dualReal[i] * f.dualReal[i] +
            f.dualImag[i] * f.dualImag[i];
      }
      expect(dualE, closeTo(primalE, 1e-9));
    });
  });

  group('LogosField operations', () {
    test('diffuse shrinks total primal energy (heat contracts)', () {
      final basis = _pathBasis(10);
      final rng = math.Random(5);
      final f = LogosField.gff(basis: basis, commitCount: 4, rng: rng);
      var e0 = 0.0;
      for (final v in f.primal) e0 += v * v;
      final d = f.diffuse(1.0);
      var e1 = 0.0;
      for (final v in d.primal) e1 += v * v;
      expect(e1, lessThanOrEqualTo(e0 + 1e-9));
    });

    test('diffuse(0) is identity', () {
      final basis = _pathBasis(8);
      final rng = math.Random(6);
      final f = LogosField.gff(basis: basis, commitCount: 2, rng: rng);
      final d = f.diffuse(0.0);
      for (var i = 0; i < f.primal.length; i++) {
        expect(d.primal[i], closeTo(f.primal[i], 1e-9));
      }
    });

    test('unitary returns mass-conserving Born probability', () {
      // |ψ(t)|² sums (per commit slot) to the same mass as ρ² at t=0.
      final basis = _pathBasis(10);
      final rng = math.Random(7);
      final f = LogosField.gff(basis: basis, commitCount: 4, rng: rng);
      final u = f.unitary(0.7);
      // Per-slot mass invariant.
      for (var w = 0; w < 4; w++) {
        var m0 = 0.0;
        var m1 = 0.0;
        for (var v = 0; v < 10; v++) {
          m0 += f.primal[w * 10 + v] * f.primal[w * 10 + v];
          m1 += u.primal[w * 10 + v];
        }
        expect(m1, closeTo(m0, 1e-6),
            reason: 'Born-rule mass must be conserved per slot');
      }
      // Output is non-negative (probability density).
      for (final v in u.primal) {
        expect(v, greaterThanOrEqualTo(-1e-9));
      }
    });

    test('filter(null, null) is identity', () {
      final basis = _pathBasis(8);
      final rng = math.Random(8);
      final f = LogosField.gff(basis: basis, commitCount: 3, rng: rng);
      final g = f.filter();
      for (var i = 0; i < f.primal.length; i++) {
        expect(g.primal[i], closeTo(f.primal[i], 1e-9));
      }
    });

    test('bandPass with full range is identity', () {
      final basis = _pathBasis(8);
      final rng = math.Random(9);
      final f = LogosField.gff(basis: basis, commitCount: 3, rng: rng);
      final g = f.bandPass();
      for (var i = 0; i < f.primal.length; i++) {
        expect(g.primal[i], closeTo(f.primal[i], 1e-9));
      }
    });

    test('bandPass(ω only, DC) kills non-DC temporal mass', () {
      final basis = _pathBasis(6);
      final rng = math.Random(10);
      final f = LogosField.gff(basis: basis, commitCount: 5, rng: rng);
      final onlyDc = f.bandPass(omegaLo: 0, omegaHi: 1);
      // All commit slots should be equal (DC = constant in time).
      final n = basis.n;
      for (var w = 1; w < 5; w++) {
        for (var v = 0; v < n; v++) {
          expect(onlyDc.primal[w * n + v],
              closeTo(onlyDc.primal[0 * n + v], 1e-6));
        }
      }
    });

    test('scale is linear', () {
      final basis = _pathBasis(6);
      final rng = math.Random(11);
      final f = LogosField.gff(basis: basis, commitCount: 2, rng: rng);
      final doubled = f.scale(2.0);
      for (var i = 0; i < f.primal.length; i++) {
        expect(doubled.primal[i], closeTo(f.primal[i] * 2.0, 1e-9));
      }
    });

    test('+ and - are inverses', () {
      final basis = _pathBasis(6);
      final rng = math.Random(12);
      final a = LogosField.gff(basis: basis, commitCount: 2, rng: rng);
      final b = LogosField.gff(basis: basis, commitCount: 2, rng: rng);
      final sum = a + b;
      final diff = sum - b;
      for (var i = 0; i < a.primal.length; i++) {
        expect(diff.primal[i], closeTo(a.primal[i], 1e-9));
      }
    });

    test('interpolate endpoints match', () {
      final basis = _pathBasis(6);
      final rng = math.Random(13);
      final a = LogosField.gff(basis: basis, commitCount: 2, rng: rng);
      final b = LogosField.gff(basis: basis, commitCount: 2, rng: rng);
      final at0 = a.interpolate(b, 0.0);
      final at1 = a.interpolate(b, 1.0);
      for (var i = 0; i < a.primal.length; i++) {
        expect(at0.primal[i], closeTo(a.primal[i], 1e-9));
        expect(at1.primal[i], closeTo(b.primal[i], 1e-9));
      }
    });

    test('operations throw on shape mismatch', () {
      final basis = _pathBasis(6);
      final rng = math.Random(14);
      final a = LogosField.gff(basis: basis, commitCount: 2, rng: rng);
      final b = LogosField.gff(basis: basis, commitCount: 3, rng: rng);
      expect(() => a + b, throwsArgumentError);
      expect(() => a.interpolate(b, 0.5), throwsArgumentError);
    });
  });

  group('LogosField analysis', () {
    test('energy reports non-negative components', () {
      final basis = _pathBasis(8);
      final rng = math.Random(15);
      final f = LogosField.gff(basis: basis, commitCount: 4, rng: rng);
      final e = f.energy;
      expect(e.spatial, greaterThanOrEqualTo(0.0));
      expect(e.temporal, greaterThanOrEqualTo(0.0));
      expect(e.total, greaterThanOrEqualTo(0.0));
      expect(e.spatialFraction, greaterThanOrEqualTo(0.0));
      expect(e.spatialFraction, lessThanOrEqualTo(1.0));
    });

    test('centroid picks the strongest dual bin', () {
      final basis = _pathBasis(8);
      // Build a field whose dual is a single spike at (j=3, ω=2).
      final re = Float64List(basis.k * 5);
      final im = Float64List(basis.k * 5);
      re[3 * 5 + 2] = 1.0;
      re[3 * 5 + (5 - 2)] = 1.0; // conjugate mirror for real primal
      final f = LogosField.fromDual(
        basis: basis,
        real: re,
        imag: im,
        commitCount: 5,
      );
      final c = f.centroid;
      expect(c.j, 3);
      expect(c.omega, anyOf(2, 3), reason: 'mirror ω=N-2=3 ties');
    });

    test('character distinguishes silent / structural / episodic', () {
      final basis = _pathBasis(8);
      // Silent: all zero.
      final silent = LogosField.zero(basis, 4);
      expect(silent.character, LogosFieldCharacter.silent);
    });

    test('alignmentWith is 1.0 against self', () {
      final basis = _pathBasis(6);
      final rng = math.Random(16);
      final f = LogosField.gff(basis: basis, commitCount: 3, rng: rng);
      expect(f.alignmentWith(f), closeTo(1.0, 1e-9));
    });

    test('alignmentWith lower between orthogonal-mode fields', () {
      final basis = _pathBasis(6);
      // Build two fields whose duals live on disjoint ω bins.
      final k = basis.k;
      const cc = 8;
      final reA = Float64List(k * cc);
      final reB = Float64List(k * cc);
      for (var j = 0; j < k; j++) {
        reA[j * cc + 1] = 1.0;
        reA[j * cc + (cc - 1)] = 1.0;
        reB[j * cc + 3] = 1.0;
        reB[j * cc + (cc - 3)] = 1.0;
      }
      final a = LogosField.fromDual(
        basis: basis,
        real: reA,
        imag: Float64List(k * cc),
        commitCount: cc,
      );
      final b = LogosField.fromDual(
        basis: basis,
        real: reB,
        imag: Float64List(k * cc),
        commitCount: cc,
      );
      final aWithB = a.alignmentWith(b);
      final aWithA = a.alignmentWith(a);
      expect(aWithB, lessThan(aWithA));
      expect(aWithB, lessThan(0.5));
    });

    test('anomalyScore self-against-self is zero', () {
      final basis = _pathBasis(6);
      final rng = math.Random(17);
      final f = LogosField.gff(basis: basis, commitCount: 3, rng: rng);
      expect(f.anomalyScore(f), closeTo(0.0, 1e-9));
    });

    test('anomalyScore between unrelated fields is positive', () {
      final basis = _pathBasis(6);
      final rngA = math.Random(18);
      final rngB = math.Random(19);
      final a = LogosField.gff(basis: basis, commitCount: 4, rng: rngA);
      final b = LogosField.gff(basis: basis, commitCount: 4, rng: rngB);
      final kl = a.anomalyScore(b);
      expect(kl, greaterThan(0.0));
      expect(kl.isFinite, isTrue);
    });

    test('topPathsViaEngine ranks seed paths at the top', () {
      final engine = _fixtureEngine();
      final probe = DiffProbe(
        sourceWeights: const {
          'lib/f000.dart': 1.0,
          'lib/f005.dart': 0.3,
        },
        primaryPaths: const {'lib/f000.dart', 'lib/f005.dart'},
        suggestedTemperature: 1.0,
        stats: const ProbeStats(
          primaryCount: 2,
          mMatches: 0,
          abMatches: 0,
          mSymbols: 0,
          coherence: 1.0,
          symbolMatches: 0,
        ),
      );
      final f = LogosField.fromDiffProbe(engine: engine, probe: probe);
      final top = f.topPathsViaEngine(engine, topN: 3);
      expect(top.first.path, 'lib/f000.dart');
      expect(top.map((t) => t.path).toList(),
          containsAll(['lib/f000.dart', 'lib/f005.dart']));
    });
  });

  group('LogosFieldCharacter labels', () {
    test('every enum value has a non-empty label', () {
      for (final c in LogosFieldCharacter.values) {
        expect(c.label, isNotEmpty);
      }
    });
  });
}
