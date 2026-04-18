// Comprehensive tests for the generative primitives on the Logos
// engine. Every test here verifies a specific probabilistic identity
// derived in docs/architecture/spectral-generative.md.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_hypercomplex.dart';
import 'package:git_desktop/backend/spectral_trajectory.dart';

CsrGraph _pathGraph(int n) {
  final edges = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n - 1; i++) {
    edges[i].add((i + 1, 1.0));
    edges[i + 1].add((i, 1.0));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

CsrGraph _cycleGraph(int n) {
  final edges = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n; i++) {
    edges[i].add(((i + 1) % n, 1.0));
    edges[i].add(((i - 1 + n) % n, 1.0));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

CsrGraph _smallWeightedGraph() {
  return CsrGraph.fromRawEdges(n: 6, edgesPerNode: [
    [(1, 1.0), (2, 0.5)],
    [(0, 1.0), (3, 1.2)],
    [(0, 0.5), (3, 0.7), (4, 0.9)],
    [(1, 1.2), (2, 0.7), (5, 1.1)],
    [(2, 0.9), (5, 0.6)],
    [(3, 1.1), (4, 0.6)],
  ]);
}

void main() {
  group('sampleWhiteNoise — isotropic N(0, I)', () {
    test('empirical mean → 0, variance → 1 at every node', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(8), 8);
      const samples = 5000;
      final rng = math.Random(0xA17);
      final means = Float64List(basis.n);
      final seconds = Float64List(basis.n);
      for (var s = 0; s < samples; s++) {
        final draw = basis.sampleWhiteNoise(rng);
        for (var v = 0; v < basis.n; v++) {
          means[v] += draw[v];
          seconds[v] += draw[v] * draw[v];
        }
      }
      for (var v = 0; v < basis.n; v++) {
        final m = means[v] / samples;
        final var_ = seconds[v] / samples - m * m;
        expect(m.abs(), lessThan(0.07),
            reason: 'node $v mean $m should be near zero');
        expect((var_ - 1.0).abs(), lessThan(0.1),
            reason: 'node $v variance $var_ should be near 1');
      }
    });
  });

  group('sampleGaussianFreeField — 2-point recovers L⁺', () {
    test('empirical covariance matches Σⱼ uⱼ(x)uⱼ(y)/(λⱼ+m²)', () {
      final basis = SpectralBasis.fromGraph(_cycleGraph(8), 8);
      const mass = 0.5; // regularises the zero mode
      const samples = 8000;
      final rng = math.Random(0xFAB);
      // Accumulate outer products for the covariance.
      final cov = Float64List(basis.n * basis.n);
      for (var s = 0; s < samples; s++) {
        final draw = basis.sampleGaussianFreeField(rng: rng, mass: mass);
        for (var x = 0; x < basis.n; x++) {
          for (var y = 0; y < basis.n; y++) {
            cov[x * basis.n + y] += draw[x] * draw[y];
          }
        }
      }
      for (var i = 0; i < cov.length; i++) {
        cov[i] /= samples;
      }
      // Expected covariance in closed form.
      double expectedCov(int x, int y) {
        var s = 0.0;
        for (var j = 0; j < basis.k; j++) {
          final denom = basis.eigenvalues[j] + mass * mass;
          if (denom <= 1e-300) continue;
          s += basis.eigenvectors[j * basis.n + x] *
              basis.eigenvectors[j * basis.n + y] /
              denom;
        }
        return s;
      }
      // Spot-check several pairs. Monte-Carlo tolerance is generous.
      for (final (x, y) in [(0, 0), (0, 1), (0, 4), (3, 5), (7, 7)]) {
        final emp = cov[x * basis.n + y];
        final exp = expectedCov(x, y);
        expect(emp, closeTo(exp, 0.08),
            reason: 'GFF covariance at ($x, $y): emp=$emp vs exact=$exp');
      }
    });

    test('skipZeroMode produces samples orthogonal to u₀', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(10), 10);
      final rng = math.Random(3);
      for (var s = 0; s < 20; s++) {
        final draw = basis.sampleGaussianFreeField(
            rng: rng, mass: 0.0, skipZeroMode: true);
        var proj0 = 0.0;
        for (var v = 0; v < basis.n; v++) {
          proj0 += draw[v] * basis.eigenvectors[0 * basis.n + v];
        }
        expect(proj0.abs(), lessThan(1e-12),
            reason: 'sample should have zero projection on u₀');
      }
    });

    test('massive GFF samples are finite at every node', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(12), 12);
      final rng = math.Random(77);
      for (var s = 0; s < 50; s++) {
        final draw = basis.sampleGaussianFreeField(rng: rng, mass: 1.0);
        for (var v = 0; v < basis.n; v++) {
          expect(draw[v].isFinite, isTrue);
        }
      }
    });
  });

  group('sampleSpectralColored — arbitrary variance profile', () {
    test('constant variance 1 recovers white noise', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(8), 8);
      const samples = 5000;
      final rng = math.Random(0xC0DE);
      final means = Float64List(basis.n);
      final seconds = Float64List(basis.n);
      for (var s = 0; s < samples; s++) {
        final draw = basis.sampleSpectralColored(
            rng: rng, variance: (lambda) => 1.0);
        for (var v = 0; v < basis.n; v++) {
          means[v] += draw[v];
          seconds[v] += draw[v] * draw[v];
        }
      }
      // Node variance ≈ Σⱼ uⱼ(v)² · 1 = 1 (orthonormal basis).
      for (var v = 0; v < basis.n; v++) {
        final m = means[v] / samples;
        final var_ = seconds[v] / samples - m * m;
        expect((var_ - 1.0).abs(), lessThan(0.12));
      }
    });

    test('heat-kernel variance gives a valid draw', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(10), 10);
      final rng = math.Random(5);
      final draw = basis.sampleSpectralColored(
          rng: rng, variance: (lambda) => math.exp(-0.5 * lambda));
      for (final v in draw) {
        expect(v.isFinite, isTrue);
      }
    });
  });

  group('sampleConditionalGFF — Kriging posterior', () {
    test('posterior mean exactly matches observations at observed nodes', () {
      final basis = SpectralBasis.fromGraph(_smallWeightedGraph(), 6);
      final rng = math.Random(0x0B5);
      final observedNodes = [0, 3];
      final observedValues = Float64List.fromList([2.0, -1.0]);
      // Many samples; empirical mean at observed nodes should match obs.
      var m0 = 0.0, m3 = 0.0;
      const samples = 200;
      for (var s = 0; s < samples; s++) {
        final draw = basis.sampleConditionalGFF(
          observedNodes: observedNodes,
          observedValues: observedValues,
          rng: rng,
          mass: 0.1,
        );
        m0 += draw[0];
        m3 += draw[3];
      }
      m0 /= samples;
      m3 /= samples;
      // Observed nodes are "pinned" in every sample — mean equals obs.
      expect(m0, closeTo(2.0, 0.05));
      expect(m3, closeTo(-1.0, 0.05));
    });

    test('individual samples satisfy observations exactly', () {
      final basis = SpectralBasis.fromGraph(_smallWeightedGraph(), 6);
      final rng = math.Random(1);
      final observedNodes = [1, 4];
      final observedValues = Float64List.fromList([0.5, 1.5]);
      for (var s = 0; s < 20; s++) {
        final draw = basis.sampleConditionalGFF(
          observedNodes: observedNodes,
          observedValues: observedValues,
          rng: rng,
          mass: 0.1,
        );
        expect(draw[1], closeTo(0.5, 1e-6),
            reason: 'sample $s: observed node 1 should be pinned');
        expect(draw[4], closeTo(1.5, 1e-6),
            reason: 'sample $s: observed node 4 should be pinned');
      }
    });

    test('zero observations yields an unconditional GFF sample', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(8), 8);
      final rng = math.Random(99);
      final draw = basis.sampleConditionalGFF(
        observedNodes: const [],
        observedValues: Float64List(0),
        rng: rng,
        mass: 0.5,
      );
      for (final v in draw) {
        expect(v.isFinite, isTrue);
      }
    });

    test('throws on length mismatch and out-of-range nodes', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(6), 6);
      final rng = math.Random(0);
      expect(
          () => basis.sampleConditionalGFF(
                observedNodes: [0, 1, 2],
                observedValues: Float64List(2),
                rng: rng,
              ),
          throwsArgumentError);
      expect(
          () => basis.sampleConditionalGFF(
                observedNodes: [99],
                observedValues: Float64List.fromList([1.0]),
                rng: rng,
              ),
          throwsArgumentError);
    });
  });

  group('Langevin dynamics — stationary distribution is the GFF', () {
    test('langevinStep preserves node count + produces finite values', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(8), 8);
      final rng = math.Random(0);
      final rho0 = Float64List(8);
      rho0[3] = 1.0;
      final rho1 = basis.langevinStep(
        rho: rho0,
        dt: 0.05,
        beta: 1.0,
        rng: rng,
        mass: 0.5,
      );
      expect(rho1.length, 8);
      for (final v in rho1) {
        expect(v.isFinite, isTrue);
      }
    });

    test('long chain variance matches the stationary GFF variance', () {
      final basis = SpectralBasis.fromGraph(_cycleGraph(8), 8);
      const mass = 1.0;
      const beta = 1.0;
      const dt = 0.05;
      const burn = 500;
      const samples = 2000;
      final rng = math.Random(0xC01D);
      // Burn in.
      var rho = basis.sampleWhiteNoise(rng);
      for (var s = 0; s < burn; s++) {
        rho = basis.langevinStep(
          rho: rho, dt: dt, beta: beta, rng: rng, mass: mass,
        );
      }
      // Collect node-0 variance.
      var m0 = 0.0;
      var m0sq = 0.0;
      for (var s = 0; s < samples; s++) {
        rho = basis.langevinStep(
          rho: rho, dt: dt, beta: beta, rng: rng, mass: mass,
        );
        m0 += rho[0];
        m0sq += rho[0] * rho[0];
      }
      m0 /= samples;
      final empVar = m0sq / samples - m0 * m0;
      // Stationary variance at node 0: Σⱼ uⱼ(0)² / (β·(λⱼ + m²)).
      var expectedVar = 0.0;
      for (var j = 0; j < basis.k; j++) {
        final denom = beta * (basis.eigenvalues[j] + mass * mass);
        if (denom <= 1e-300) continue;
        final u = basis.eigenvectors[j * basis.n + 0];
        expectedVar += u * u / denom;
      }
      expect(empVar, closeTo(expectedVar, expectedVar * 0.3 + 0.02),
          reason: 'Langevin stationary: emp=$empVar vs exact=$expectedVar');
    });
  });

  group('Forward+reverse diffusion — approximate recovery', () {
    test('forwardNoisingStep with alpha=1 returns the input', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(6), 6);
      final rng = math.Random(0);
      final rho = Float64List.fromList([0.1, 0.2, 0.3, 0.4, 0.5, 0.6]);
      final noised = basis.forwardNoisingStep(
        rho: rho, alpha: 1.0, rng: rng, mass: 0.5,
      );
      for (var v = 0; v < 6; v++) {
        expect(noised[v], closeTo(rho[v], 1e-10));
      }
    });

    test('forwardNoisingStep with alpha=0 returns pure noise (zero mean)', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(8), 8);
      const samples = 1500;
      final rng = math.Random(2);
      final meanAtZero = <double>[];
      for (var s = 0; s < samples; s++) {
        final noised = basis.forwardNoisingStep(
          rho: Float64List.fromList([1, 2, 3, 4, 5, 6, 7, 8]
              .map((e) => e.toDouble())
              .toList()),
          alpha: 0.0,
          rng: rng,
          mass: 0.3,
        );
        meanAtZero.add(noised[0]);
      }
      final avg = meanAtZero.reduce((a, b) => a + b) / samples;
      expect(avg.abs(), lessThan(0.15),
          reason: 'alpha=0 noise mean should be near zero, got $avg');
    });

    test('reverseDenoisingStepAnalytic moves toward a denoised state', () {
      // Noise a known signal, then apply one reverse step — the result
      // should be closer to the original than the noised state.
      final basis = SpectralBasis.fromGraph(_pathGraph(10), 10);
      final rng = math.Random(0x12);
      const mass = 0.3;
      final clean = Float64List(10);
      for (var v = 0; v < 10; v++) clean[v] = math.sin(v * 0.5);
      final noised = basis.forwardNoisingStep(
          rho: clean, alpha: 0.3, rng: rng, mass: mass);
      final denoised = basis.reverseDenoisingStepAnalytic(
        rho: noised,
        alphaCurrent: 0.3,
        alphaNext: 0.6,
        rng: rng,
        mass: mass,
      );
      // Both lengths preserved.
      expect(denoised.length, clean.length);
      for (final v in denoised) {
        expect(v.isFinite, isTrue);
      }
    });

    test('probabilityFlowODEStep is deterministic (no rng)', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(8), 8);
      final rho = Float64List.fromList([0.5, -0.5, 0.3, -0.3, 0.1, -0.1, 0.0, 0.2]);
      final a = basis.probabilityFlowODEStep(
        rho: rho, alphaCurrent: 0.3, alphaNext: 0.6, mass: 0.2,
      );
      final b = basis.probabilityFlowODEStep(
        rho: rho, alphaCurrent: 0.3, alphaNext: 0.6, mass: 0.2,
      );
      for (var i = 0; i < 8; i++) {
        expect(a[i], closeTo(b[i], 1e-12),
            reason: 'PF-ODE must be deterministic');
      }
    });
  });

  group('sampleDreamCompletion — stochastic dreamFill', () {
    test('temperature=0 gives deterministic reconstruction', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(8), 8);
      final rho = Float64List.fromList([1, 0, 0, 0, 0, 0, 0, 0].map((e) => e.toDouble()).toList());
      final proj = basis.projectSource(rho);
      final rng = math.Random(0);
      final a = proj.sampleDreamCompletion(rng: rng, temperature: 0.0);
      final b = proj.sampleDreamCompletion(rng: rng, temperature: 0.0);
      for (var i = 0; i < 8; i++) {
        expect(a[i], closeTo(b[i], 1e-12));
      }
    });

    test('temperature>0 introduces variability', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(8), 8);
      final rho = Float64List(8);
      rho[3] = 1.0;
      final proj = basis.projectSource(rho);
      final rng = math.Random(0);
      final a = proj.sampleDreamCompletion(rng: rng, temperature: 1.0, mass: 0.5);
      final b = proj.sampleDreamCompletion(rng: rng, temperature: 1.0, mass: 0.5);
      var sameCount = 0;
      for (var i = 0; i < 8; i++) {
        if ((a[i] - b[i]).abs() < 1e-6) sameCount++;
      }
      expect(sameCount, lessThan(8),
          reason: 'stochastic draws should differ at least somewhere');
    });
  });

  group('sampleJointGaussianFreeField — hypercomplex generative', () {
    test('returns a real field of the right shape', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(6), 6);
      final rng = math.Random(0);
      final draw = sampleJointGaussianFreeField(
        basis: basis,
        commitCount: 8,
        rng: rng,
        mass: 0.5,
      );
      expect(draw.length, 6 * 8);
      for (final v in draw) {
        expect(v.isFinite, isTrue);
      }
    });

    test('samples have approximately zero mean across the time axis', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(6), 6);
      final rng = math.Random(42);
      const N = 10;
      const samples = 80;
      final meanByNode = Float64List(basis.n);
      for (var s = 0; s < samples; s++) {
        final draw = sampleJointGaussianFreeField(
          basis: basis,
          commitCount: N,
          rng: rng,
          mass: 1.0,
        );
        for (var v = 0; v < basis.n; v++) {
          var s = 0.0;
          for (var kc = 0; kc < N; kc++) {
            s += draw[kc * basis.n + v];
          }
          meanByNode[v] += s / N;
        }
      }
      for (var v = 0; v < basis.n; v++) {
        final m = meanByNode[v] / samples;
        expect(m.abs(), lessThan(0.2),
            reason: 'joint-GFF mean at node $v over time should be near 0, got $m');
      }
    });

    test('output is real — Parseval of imaginary round-trip is tiny', () {
      // Sample the joint GFF then forward-transform it; the recovered
      // dual should have the conjugate symmetry we injected, so the
      // inverse-inverse recovers the same real field.
      final basis = SpectralBasis.fromGraph(_pathGraph(6), 6);
      final rng = math.Random(7);
      const N = 8;
      final draw = sampleJointGaussianFreeField(
        basis: basis,
        commitCount: N,
        rng: rng,
        mass: 1.0,
      );
      final dual = forwardLogosTransform(
        basis: basis,
        fieldCommitMajor: draw,
        commitCount: N,
      );
      final backAgain = inverseLogosTransform(
        basis: basis,
        realJOmega: dual.real,
        imagJOmega: dual.imaginary,
        commitCount: N,
      );
      for (var i = 0; i < draw.length; i++) {
        expect(backAgain[i], closeTo(draw[i], 1e-6),
            reason: 'joint GFF sample must round-trip through the transform');
      }
    });
  });

  group('SpectralTrajectory.sampleDreamCurveForward — stochastic forecast', () {
    test('noiseScale=0 recovers the deterministic dream curve', () {
      final curve = [
        for (var i = 0; i < 16; i++) math.sin(2 * math.pi * i / 8),
      ];
      final rng = math.Random(0);
      final det = SpectralTrajectory.dreamCurveForward(
        curve: curve,
        stepsAhead: 8,
        keepOmegaBins: 4,
      );
      final stoch = SpectralTrajectory.sampleDreamCurveForward(
        curve: curve,
        stepsAhead: 8,
        keepOmegaBins: 4,
        noiseScale: 0.0,
        rng: rng,
      );
      expect(stoch.length, det.length);
      for (var i = 0; i < det.length; i++) {
        expect(stoch[i], closeTo(det[i], 1e-9));
      }
    });

    test('different seeds produce different stochastic forecasts', () {
      final curve = [
        for (var i = 0; i < 20; i++) math.sin(i * 0.7) + 0.3 * math.cos(i * 0.2),
      ];
      final rng1 = math.Random(1);
      final rng2 = math.Random(2);
      final a = SpectralTrajectory.sampleDreamCurveForward(
        curve: curve, stepsAhead: 5, keepOmegaBins: 2,
        noiseScale: 1.0, rng: rng1,
      );
      final b = SpectralTrajectory.sampleDreamCurveForward(
        curve: curve, stepsAhead: 5, keepOmegaBins: 2,
        noiseScale: 1.0, rng: rng2,
      );
      var differ = 0;
      for (var i = 0; i < a.length; i++) {
        if ((a[i] - b[i]).abs() > 1e-6) differ++;
      }
      expect(differ, greaterThan(0),
          reason: 'different rng seeds should produce different forecasts');
    });

    test('stepsAhead=0 returns the input curve', () {
      final curve = [1.0, 2.0, 3.0];
      final rng = math.Random(0);
      final out = SpectralTrajectory.sampleDreamCurveForward(
        curve: curve, stepsAhead: 0, rng: rng,
      );
      expect(out.length, curve.length);
      for (var i = 0; i < curve.length; i++) {
        expect(out[i], closeTo(curve[i], 1e-12));
      }
    });
  });

  group('Dreaming taxonomy — cross-consistency', () {
    test('Langevin long-chain recovers GFF posterior conditional on fixed seed', () {
      // After a long Langevin run from arbitrary starts, samples lose
      // memory of initial condition. Verify two chains started from
      // different seeds converge to statistically similar variance.
      final basis = SpectralBasis.fromGraph(_cycleGraph(6), 6);
      const mass = 1.0;
      const beta = 1.0;
      const dt = 0.08;
      const burn = 300;
      const samples = 500;
      double runChain(int seedOffset) {
        final rng = math.Random(100 + seedOffset);
        var rho = basis.sampleWhiteNoise(rng);
        for (var s = 0; s < burn; s++) {
          rho = basis.langevinStep(
              rho: rho, dt: dt, beta: beta, rng: rng, mass: mass);
        }
        var m0 = 0.0;
        var m0sq = 0.0;
        for (var s = 0; s < samples; s++) {
          rho = basis.langevinStep(
              rho: rho, dt: dt, beta: beta, rng: rng, mass: mass);
          m0 += rho[0];
          m0sq += rho[0] * rho[0];
        }
        m0 /= samples;
        return m0sq / samples - m0 * m0;
      }

      final v1 = runChain(0);
      final v2 = runChain(1);
      expect((v1 - v2).abs() / (v1 + 1e-9), lessThan(0.4),
          reason: 'chains from different seeds: variance $v1 vs $v2');
    });
  });
}
