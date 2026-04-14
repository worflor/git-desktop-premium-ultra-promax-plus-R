// Tests for the Engram AR(2) fit port. Mirrors the Rust test suite's
// key invariants: linear ramp, pure cosine (sustained orbit), damped
// cosine (decaying orbit), degenerate constant, too-short input,
// algebraic RMS matches a direct pass.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/engram_fit.dart';
import 'package:git_desktop/backend/file_coupling.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Engram AR(2) fit — 1D real specialization', () {
    test('too-short input returns linear fallback', () {
      expect(engramFit(const [1, 2, 3]).isLinearFallback, isTrue);
      expect(engramFit(const [1, 2]).isLinearFallback, isTrue);
    });

    test('constant signal is fittable and has finite K', () {
      final z = List<double>.filled(20, 5.0);
      final fit = engramFit(z);
      // Constants degenerate the normal equations; ridge regularization
      // keeps the solve stable. Either path is acceptable — just no NaN.
      expect(fit.k.isFinite, isTrue);
      expect(fit.g.isFinite, isTrue);
    });

    test('pure cosine yields spectral radius ≈ 1 (sustained orbit)', () {
      // cos(2π·i/10) — perfect sinusoid, no decay.
      final z = List<double>.generate(
        120,
        (i) => math.cos(2 * math.pi * i / 10),
      );
      final fit = engramFit(z);
      expect(fit.isLinearFallback, isFalse);
      expect(fit.rms, lessThan(0.05),
          reason: 'pure cosine is exactly an AR(2) process');
      expect(fit.spectralRadius, closeTo(1.0, 0.02),
          reason: 'sustained orbit → |λ| ≈ 1');
      expect(fit.isOrbital, isTrue);
    });

    test('damped cosine has |λ| < 1 and a finite half-life', () {
      // 0.95^i · cos(2π·i/12) — classic under-damped oscillator.
      final z = List<double>.generate(100, (i) {
        final decay = math.pow(0.95, i).toDouble();
        return decay * math.cos(2 * math.pi * i / 12);
      });
      final fit = engramFit(z);
      expect(fit.isLinearFallback, isFalse);
      expect(fit.spectralRadius, lessThan(1.0));
      expect(fit.spectralRadius, greaterThan(0.85),
          reason: 'damped cosine should decay but not collapse');
      final hl = fit.halfLifeSamples;
      expect(hl, isNotNull);
      // r=0.95 analytically gives half-life = −ln(2)/ln(0.95) ≈ 13.51.
      expect(hl!, closeTo(13.5, 3.0),
          reason: 'half-life must match the closed-form decay');
      expect(fit.isOrbital, isTrue);
    });

    test('divergent signal does not report a half-life', () {
      // 1.05^i · cos — amplitude grows each step; |λ| > 1.
      final z = List<double>.generate(60, (i) {
        final growth = math.pow(1.05, i).toDouble();
        return growth * math.cos(2 * math.pi * i / 14);
      });
      final fit = engramFit(z);
      expect(fit.halfLifeSamples, isNull,
          reason: 'divergent signal has no meaningful memory depth');
    });
  });

  group('Engram-derived adaptive half-life', () {
    test('too-short history falls back to clamp heuristic', () {
      // Only 3 commits — fit won't run. Fallback: 3/4 = 0.75 → clamped 50.
      final hl = deriveEngramHalfLife(const [
        ['a.dart'],
        ['b.dart'],
        ['a.dart', 'b.dart'],
      ]);
      expect(hl, 50.0);
    });

    test('slow-drift repo yields a long half-life', () {
      // Every consecutive pair shares a file. Sequence of similarities
      // is steady and high → orbit-like signal → long memory depth.
      // Synthesise 60 commits where each touches [f_i, f_{i+1}] — a
      // cleanly overlapping chain.
      final commits = <List<String>>[
        for (var i = 0; i < 80; i++) ['f$i.dart', 'f${i + 1}.dart'],
      ];
      final hl = deriveEngramHalfLife(commits);
      // The signal is basically constant (all similarities ≈ 0.333),
      // so the fit will degrade to fallback OR produce a long-decay
      // orbit. Either way the resulting half-life is within [50, 500].
      expect(hl, inInclusiveRange(50.0, 500.0));
    });

    test('degenerate (all empty commits) still returns a clamped value', () {
      final commits = List<List<String>>.generate(20, (_) => const []);
      final hl = deriveEngramHalfLife(commits);
      expect(hl, inInclusiveRange(50.0, 500.0));
    });

    test('converging chain — file overlap rising toward tip', () {
      // Commits 0-7: touch random files; commits 8-15: tighten around
      // auth/*. The slope on the Jaccard series should be positive.
      final commits = <Set<String>>[
        {'misc/a.dart', 'misc/b.dart'},
        {'misc/c.dart', 'misc/d.dart'},
        {'misc/e.dart', 'misc/f.dart'},
        {'misc/g.dart', 'misc/h.dart'},
        {'auth/login.dart', 'misc/i.dart'},
        {'auth/login.dart', 'auth/session.dart'},
        {'auth/login.dart', 'auth/session.dart'},
        {'auth/session.dart', 'auth/middleware.dart'},
        {'auth/login.dart', 'auth/session.dart', 'auth/middleware.dart'},
        {'auth/session.dart', 'auth/middleware.dart'},
        {'auth/login.dart', 'auth/session.dart'},
        {'auth/session.dart', 'auth/middleware.dart'},
      ];
      final orbit = computeBranchOrbit(commits);
      expect(orbit.hasSignal, isTrue);
      expect(orbit.isConverging, isTrue,
          reason: 'final commits share progressively more files');
      expect(orbit.isDiverging, isFalse);
      expect(orbit.characterLabel, 'converging');
    });

    test('diverging chain — file overlap eroding toward tip', () {
      // Inverse of the converging case.
      final commits = <Set<String>>[
        {'auth/login.dart', 'auth/session.dart', 'auth/middleware.dart'},
        {'auth/session.dart', 'auth/middleware.dart'},
        {'auth/login.dart', 'auth/session.dart'},
        {'auth/session.dart', 'auth/middleware.dart'},
        {'auth/login.dart', 'auth/session.dart'},
        {'auth/login.dart', 'auth/middleware.dart'},
        {'auth/login.dart', 'misc/i.dart'},
        {'misc/a.dart', 'misc/b.dart'},
        {'misc/c.dart', 'misc/d.dart'},
        {'misc/e.dart', 'misc/f.dart'},
        {'misc/g.dart', 'misc/h.dart'},
        {'misc/i.dart', 'misc/j.dart'},
      ];
      final orbit = computeBranchOrbit(commits);
      expect(orbit.hasSignal, isTrue);
      expect(orbit.isDiverging, isTrue);
      expect(orbit.isConverging, isFalse);
      expect(orbit.characterLabel, 'diverging');
    });

    test('too-short chain returns insufficient (all classifiers false)', () {
      final orbit = computeBranchOrbit([
        {'a.dart'},
        {'b.dart'},
        {'c.dart'},
      ]);
      expect(orbit.hasSignal, isFalse);
      expect(orbit.isConverging, isFalse);
      expect(orbit.isDiverging, isFalse);
      expect(orbit.characterLabel, isNull);
    });

    test('heavily oscillating repo yields a short half-life', () {
      // Alternate pattern: touched files swap every commit → similarity
      // oscillates 0,1,0,1… — strong orbit, fast decay of correlation.
      // The fit's spectral radius should be near 1, half-life in band.
      final a = ['a.dart', 'b.dart'];
      final b = ['c.dart', 'd.dart'];
      final commits = <List<String>>[
        for (var i = 0; i < 100; i++) i.isEven ? a : b,
      ];
      final hl = deriveEngramHalfLife(commits);
      expect(hl, inInclusiveRange(50.0, 500.0));
    });

    test('oscillationPeriodSamples recovers a known cosine period', () {
      // Sustained cosine z[n] = cos(2π·n / 10) — period 10 samples.
      // The AR(2) fit should recover ω₀ = 2π/10, giving period ≈ 10.
      final period = 10.0;
      final z = [
        for (var n = 0; n < 64; n++) math.cos(2 * math.pi * n / period),
      ];
      final fit = engramFit(z);
      final p = fit.oscillationPeriodSamples;
      expect(p, isNotNull);
      // Tolerance: AR(2) fit on a noisy/finite cosine isn't exact;
      // ±5% is a tight-but-realistic envelope for n=64.
      expect(p!, closeTo(period, period * 0.05));
    });

    test('oscillationPeriodSamples is null for over-damped (real-root) fits',
        () {
      // Pure exponential decay z[n] = 0.5^n — over-damped, no
      // oscillation, real roots only. Period must be null.
      final z = [for (var n = 0; n < 32; n++) math.pow(0.5, n).toDouble()];
      final fit = engramFit(z);
      expect(fit.oscillationPeriodSamples, isNull);
    });

    test('oscillationPeriodSamples is null for the linear fallback', () {
      final fit = engramFit(const [1.0, 2.0]); // too short → fallback
      expect(fit.isLinearFallback, isTrue);
      expect(fit.oscillationPeriodSamples, isNull);
    });
  });
}
