// Tests for the engine-hardening pass:
//   - Bessel coefficient stability at extreme t
//   - Spectral radius diagnostic (power iteration ≤ 2)
//   - Axial attribution sums and provenance
//   - SSE deep-saturation rescue

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_git_calibration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bessel coefficient numerical safety', () {
    test('large t (boundary 30) yields finite coefficients', () {
      final coeffs = chebyshevBesselCoeffsForTesting(30, 32);
      for (final c in coeffs) {
        expect(c.isFinite, isTrue,
            reason: 'all coefficients must be finite at t=30');
      }
    });

    test('above-cap t (e.g. 100) silently clamps to safe value', () {
      // Should not throw; should not produce NaN/Inf. The actual
      // numbers are clamped to t=30 internally — diffusion at t≫30 is
      // indistinguishable from the stationary distribution anyway.
      final coeffs = chebyshevBesselCoeffsForTesting(100, 16);
      for (final c in coeffs) {
        expect(c.isFinite, isTrue);
      }
    });

    test('t=0 returns identity coefficients (c_0=1, rest=0)', () {
      final coeffs = chebyshevBesselCoeffsForTesting(0, 8);
      expect(coeffs[0], closeTo(1.0, 1e-12));
      for (var k = 1; k < coeffs.length; k++) {
        expect(coeffs[k], closeTo(0.0, 1e-12));
      }
    });

    test('reference values at t=1 match analytic I_k(-1)', () {
      // c_0(t) = e^{-t} · I_0(-t);  c_k(t) = 2·e^{-t} · I_k(-t) for k≥1.
      // I_k(-1) = (-1)^k · I_k(1). Known modified Bessel values:
      //   I_0(1) = 1.2660658732…
      //   I_1(1) = 0.5651591040…
      //   I_2(1) = 0.1357476698…
      //   I_3(1) = 0.0221684250…
      // e^{-1} = 0.3678794412…
      // 1e-4 tolerance — more than tight enough (the Chebyshev
      // reconstruction error downstream is < 1e-8 on the full spectrum).
      final coeffs = chebyshevBesselCoeffsForTesting(1.0, 4);
      expect(coeffs[0], closeTo(0.465759607, 1e-4));
      expect(coeffs[1], closeTo(-0.415820831, 1e-4));
      expect(coeffs[2], closeTo(0.099915897, 1e-4));
      expect(coeffs[3], closeTo(-0.016303737, 1e-4));
    });

    test('reference values at t=5 stay within closed-form tolerance', () {
      // I_0(5) = 27.23987182…, I_1(5) = 24.33564214…
      // c_0 = exp(-5)·I_0(5) = 0.18354081…
      // c_1 = -2·exp(-5)·I_1(5) = -0.32794453…
      // 1e-4 tolerance accommodates the Bessel-series truncation at 200
      // terms — plenty for the downstream Chebyshev reconstruction error
      // (< 1e-8 on the full spectrum).
      final coeffs = chebyshevBesselCoeffsForTesting(5.0, 2);
      expect(coeffs[0], closeTo(0.183540812, 1e-4));
      expect(coeffs[1], closeTo(-0.327944534, 1e-4));
    });
  });

  group('Spectral radius diagnostic', () {
    LogosGit buildSimpleEngine() {
      // 4-node ring: a-b, b-c, c-d, d-a — should have a well-bounded
      // spectrum. Use Jaccard so the engine reads it.
      final matrix = FileCouplingMatrix(
        jaccard: {
          'a': {'b': 0.7, 'd': 0.7},
          'b': {'a': 0.7, 'c': 0.7},
          'c': {'b': 0.7, 'd': 0.7},
          'd': {'a': 0.7, 'c': 0.7},
        },
        headHash: 'h',
        commitsAnalyzed: 100,
      );
      final stats = LogosGitStats(
        touches: const {'a': 5, 'b': 5, 'c': 5, 'd': 5},
        totalCommits: 50,
        volatility: const {'a': 1.0, 'b': 1.0, 'c': 1.0, 'd': 1.0},
        volMean: 1.0,
        volStddev: 0.5,
        coupling: matrix,
        perFileCommitIndices: const {},
      );
      return LogosGit.buildFromStats(stats);
    }

    test('estimated spectral radius ≤ 2 on small ring graph', () {
      final engine = buildSimpleEngine();
      final r = engine.estimateSpectralRadius();
      expect(r, lessThanOrEqualTo(2.0 + 1e-6),
          reason: 'normalised Laplacian spectrum is bounded by 2');
      expect(r, greaterThan(0));
    });
  });

  group('Per-axis attribution (diffuseWithAttribution)', () {
    LogosGit buildEngine() {
      final matrix = FileCouplingMatrix(
        jaccard: {
          'lib/a.dart': {'lib/b.dart': 0.6, 'lib/c.dart': 0.4},
          'lib/b.dart': {'lib/a.dart': 0.6, 'lib/c.dart': 0.5},
          'lib/c.dart': {'lib/a.dart': 0.4, 'lib/b.dart': 0.5},
          'lib/d.dart': {'lib/e.dart': 0.7},
          'lib/e.dart': {'lib/d.dart': 0.7},
        },
        headHash: 'h',
        commitsAnalyzed: 100,
      );
      final stats = LogosGitStats(
        touches: const {
          'lib/a.dart': 10,
          'lib/b.dart': 8,
          'lib/c.dart': 6,
          'lib/d.dart': 4,
          'lib/e.dart': 4,
        },
        totalCommits: 50,
        volatility: const {
          'lib/a.dart': 1.0,
          'lib/b.dart': 1.2,
          'lib/c.dart': 0.8,
          'lib/d.dart': 1.5,
          'lib/e.dart': 1.4,
        },
        volMean: 1.18,
        volStddev: 0.3,
        coupling: matrix,
        perFileCommitIndices: const {},
      );
      return LogosGit.buildFromStats(stats);
    }

    test('combined φ equals elementwise sum of per-axis φ', () {
      final engine = buildEngine();
      final attr = engine.diffuseWithAttribution(
        weightsByPath: const {'lib/a.dart': 1.0, 'lib/d.dart': 0.5},
        axisLabelByPath: const {
          'lib/a.dart': 'primary',
          'lib/d.dart': 'm',
        },
      );
      expect(attr, isNotNull);
      // For each path in combined, phi must equal the sum of per-axis
      // shares (modulo float epsilon).
      for (final score in attr!.combined) {
        final shares = attr.shareByAxis[score.path];
        if (shares == null) continue;
        final fracSum = shares.values.fold<double>(0, (a, b) => a + b);
        expect(fracSum, closeTo(1.0, 1e-9),
            reason: 'per-axis shares must sum to 1 for path ${score.path}');
      }
    });

    test('single-axis seed → that axis is dominant for related nodes', () {
      final engine = buildEngine();
      final attr = engine.diffuseWithAttribution(
        weightsByPath: const {'lib/d.dart': 1.0},
        axisLabelByPath: const {'lib/d.dart': 'primary'},
      );
      expect(attr, isNotNull);
      // Every non-source result should have 'primary' as dominant axis
      // (only one axis bucket has any mass).
      for (final entry in attr!.dominantAxis.entries) {
        expect(entry.value, 'primary');
      }
    });

    test('axisMassFractions sums to 1', () {
      final engine = buildEngine();
      final attr = engine.diffuseWithAttribution(
        weightsByPath: const {'lib/a.dart': 1.0, 'lib/d.dart': 1.0},
        axisLabelByPath: const {
          'lib/a.dart': 'primary',
          'lib/d.dart': 'm',
        },
      );
      expect(attr, isNotNull);
      final fracs = attr!.axisMassFractions();
      final sum = fracs.values.fold<double>(0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('combined φ equals elementwise sum across all per-axis φ', () {
      // Stronger than the per-path-share test: validates the full
      // linearity invariant the attribution claims. If this ever drifts,
      // the "why this file surfaced" provenance becomes meaningless.
      final engine = buildEngine();
      final attr = engine.diffuseWithAttribution(
        weightsByPath: const {
          'lib/a.dart': 1.0,
          'lib/b.dart': 0.5,
          'lib/d.dart': 0.3,
        },
        axisLabelByPath: const {
          'lib/a.dart': 'primary',
          'lib/b.dart': 'primary',
          'lib/d.dart': 'm',
        },
      );
      expect(attr, isNotNull);
      for (var i = 0; i < attr!.nodePaths.length; i++) {
        double axisSum = 0;
        for (final phi in attr.perAxisPhi.values) {
          axisSum += phi[i];
        }
        // combined[i] is emitted only for nodes that weren't excluded
        // AND have positive φ; compare via the nodePaths index.
        final path = attr.nodePaths[i];
        final combined =
            attr.combined.firstWhere((s) => s.path == path, orElse: () => RelevanceScore(path, 0.0));
        // Sources are excluded by default — their combined φ is 0 but
        // the per-axis sum still includes their ρ contribution. Skip
        // source paths (they're in weightsByPath).
        if (const {'lib/a.dart', 'lib/b.dart', 'lib/d.dart'}.contains(path)) continue;
        expect(combined.phi, closeTo(axisSum, 1e-9),
            reason: 'combined φ must equal sum of per-axis φ at $path');
      }
    });

    test('null on out-of-graph weights only', () {
      final engine = buildEngine();
      final attr = engine.diffuseWithAttribution(
        weightsByPath: const {'unknown/path.dart': 1.0},
        axisLabelByPath: const {'unknown/path.dart': 'primary'},
      );
      expect(attr, isNull);
    });
  });

  group('diffuseStability confidence primitive', () {
    LogosGit buildStableEngine() {
      final matrix = FileCouplingMatrix(
        jaccard: {
          'lib/a.dart': {'lib/b.dart': 0.8, 'lib/c.dart': 0.7, 'lib/d.dart': 0.6},
          'lib/b.dart': {'lib/a.dart': 0.8, 'lib/c.dart': 0.5},
          'lib/c.dart': {'lib/a.dart': 0.7, 'lib/b.dart': 0.5, 'lib/d.dart': 0.6},
          'lib/d.dart': {'lib/a.dart': 0.6, 'lib/c.dart': 0.6},
        },
        headHash: 'h',
        commitsAnalyzed: 100,
      );
      final stats = LogosGitStats(
        touches: const {
          'lib/a.dart': 10,
          'lib/b.dart': 8,
          'lib/c.dart': 9,
          'lib/d.dart': 7,
        },
        totalCommits: 50,
        volatility: const {
          'lib/a.dart': 1.0,
          'lib/b.dart': 1.0,
          'lib/c.dart': 1.0,
          'lib/d.dart': 1.0,
        },
        volMean: 1.0,
        volStddev: 0.1,
        coupling: matrix,
        perFileCommitIndices: const {},
      );
      return LogosGit.buildFromStats(stats);
    }

    test('single-source diffusion is trivially stable', () {
      final engine = buildStableEngine();
      final s = engine.diffuseStability(
        const {'lib/a.dart': 1.0},
        t: 1.0,
      );
      // Perturbing a single weight never changes the ranking (it's a
      // monotonic scalar), so stability must be ~1.
      expect(s, greaterThanOrEqualTo(0.9));
    });

    test('strongly-coupled neighbourhood yields high stability', () {
      final engine = buildStableEngine();
      final s = engine.diffuseStability(
        const {'lib/a.dart': 1.0, 'lib/c.dart': 0.8},
        t: 1.0,
        topK: 3,
        epsilon: 0.1,
      );
      expect(s, greaterThan(0.5),
          reason: 'tight neighbourhood should resist small perturbations');
    });

    test('empty graph short-circuits to 1.0', () {
      final emptyStats = LogosGitStats(
        touches: const {},
        totalCommits: 0,
        volatility: const {},
        volMean: 0,
        volStddev: 0,
        coupling: FileCouplingMatrix.empty,
        perFileCommitIndices: const {},
      );
      final engine = LogosGit.buildFromStats(emptyStats);
      final s = engine.diffuseStability(
        const {'x.dart': 1.0},
        t: 1.0,
      );
      expect(s, 1.0);
    });
  });

  group('SSE deep-saturation rescue', () {
    test('emitted ≫ 1024 sqrt-pulls back near 256 in one call', () {
      final c = LogosSseCell(emitted: 4096, cited: 1024);
      c.evaporateIfSaturated();
      // sqrt(256/4096) = 0.25 — emitted goes 4096 → 1024, cited 1024 → 256.
      expect(c.emitted, closeTo(1024, 1e-6));
      expect(c.cited, closeTo(256, 1e-6));
      // Ratio (cited/emitted) preserved exactly: 1024/4096 = 256/1024 = 0.25.
      expect(c.cited / c.emitted, closeTo(0.25, 1e-9));
    });

    test('soft-trigger band (256 ≤ emitted < 1024) still halves', () {
      final c = LogosSseCell(emitted: 512, cited: 200);
      c.evaporateIfSaturated();
      expect(c.emitted, 256);
      expect(c.cited, 100);
    });

    test('utility ratio invariant across deep rescue', () {
      final c = LogosSseCell(emitted: 8192, cited: 4096);
      final ratioBefore = c.cited / c.emitted;
      c.evaporateIfSaturated();
      final ratioAfter = c.cited / c.emitted;
      expect(ratioAfter, closeTo(ratioBefore, 1e-12));
    });
  });
}
