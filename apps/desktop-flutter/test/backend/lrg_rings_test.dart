import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/lrg_rings.dart';

/// Build a basis from a handcrafted ascending spectrum. The ring detector reads
/// only the eigenvalues (via relaxationRate), so the eigenvectors are inert —
/// this lets us drive it with exactly the spectral structure we want to test.
SpectralBasis basisFromEigs(List<double> eigs) {
  final k = eigs.length;
  return SpectralBasis(
    n: k,
    k: k,
    eigenvalues: Float64List.fromList(eigs),
    eigenvectors: Float64List(k * k),
  );
}

void main() {
  group('LRG structural rings', () {
    test('three spectral bands (two gaps) → a two-level hierarchy', () {
      // Two relaxation steps need three clusters separated by genuinely wide
      // gaps. Each diffusion step is ~2 e-folds wide in log τ, so two scales
      // only resolve when their spectral gap is ≳ e² ≈ 8–10× — exactly what a
      // clearly-modular graph (well-separated module band + bulk) looks like.
      final basis =
          basisFromEigs([0.0, 0.012, 0.014, 0.15, 0.16, 1.75, 1.85]);
      final profile = detectLrgRings(basis);

      expect(profile.isEmpty, isFalse);
      expect(profile.hasHierarchy, isTrue,
          reason: 'three separated bands (two gaps) should yield ≥2 rings');
      expect(profile.rings.length, greaterThanOrEqualTo(2));
      expect(profile.singleScale, isFalse);

      // Rings ascend in τ; the coarse (large-τ) ring resolves into no more parts
      // than the fine (small-τ) ring.
      for (var i = 1; i < profile.rings.length; i++) {
        expect(profile.rings[i].tau, greaterThan(profile.rings[i - 1].tau));
      }
      expect(profile.rings.last.partsAtScale,
          lessThanOrEqualTo(profile.rings.first.partsAtScale));

      // Strengths are prominences relative to the dominant ring: each in (0, 1],
      // and the strongest is exactly the unit reference.
      var strongest = 0.0;
      for (final r in profile.rings) {
        expect(r.strength, greaterThan(0.0));
        expect(r.strength, lessThanOrEqualTo(1.0));
        if (r.strength > strongest) strongest = r.strength;
      }
      expect(strongest, closeTo(1.0, 1e-9));
    });

    test('a single tight band → one characteristic scale, no hierarchy', () {
      final basis =
          basisFromEigs([0.0, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80]);
      final profile = detectLrgRings(basis);

      expect(profile.isEmpty, isFalse);
      expect(profile.rings.length, 1);
      expect(profile.singleScale, isTrue);
      expect(profile.hasHierarchy, isFalse);
    });

    test('never fabricates: a near-flat band stays at ≤1 ring', () {
      // Non-zero modes nearly degenerate — no real scale structure. The
      // detector must NOT manufacture multiple rings.
      final basis = basisFromEigs([0.0, 0.50, 0.51, 0.52, 0.53, 0.54]);
      final profile = detectLrgRings(basis);

      expect(profile.hasHierarchy, isFalse,
          reason: 'a featureless spectrum must not invent a hierarchy');
      expect(profile.rings.length, lessThanOrEqualTo(1));
    });

    test('degenerate non-zero spectrum (no scale range) → abstains', () {
      // Every non-zero mode identical: λmax == λgap, no diffusion-time range to
      // sweep. Honest answer is no profile at all, not a fabricated ring.
      final basis = basisFromEigs([0.0, 0.5, 0.5, 0.5, 0.5]);
      final profile = detectLrgRings(basis);
      expect(profile.isEmpty, isTrue);
    });

    test('ground-only spectrum (edgeless graph) → abstains', () {
      final basis = basisFromEigs([0.0, 0.0, 0.0]);
      final profile = detectLrgRings(basis);
      expect(profile.isEmpty, isTrue);
    });

    test('geometric (self-similar) spectrum → does not fabricate a hierarchy',
        () {
      // Constant-ratio eigenvalues = no dominant gap, scale-free structure.
      // Every adjacent ratio is a mere shoulder, so the detector must NOT read
      // a deep ring stack out of it.
      final basis =
          basisFromEigs([0.0, 0.02, 0.05, 0.125, 0.31, 0.78, 1.95]);
      final profile = detectLrgRings(basis);
      expect(profile.rings.length, lessThanOrEqualTo(2),
          reason: 'self-similar spectra have no well-separated scales');
    });
  });

  group('LRG ring history (Axis B)', () {
    final single = [0.0, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80];
    final twoLevel = [0.0, 0.012, 0.014, 0.15, 0.16, 1.75, 1.85];

    ({String commitSha, DateTime timestamp, SpectralBasis basis}) snap(
        int i, List<double> eigs) {
      return (
        commitSha: 'c$i',
        timestamp: DateTime.fromMillisecondsSinceEpoch(i * 86400000),
        basis: basisFromEigs(eigs),
      );
    }

    test('a scale emerging over history is one datable transition', () {
      final snaps = [
        for (var i = 0; i < 3; i++) snap(i, single),
        for (var i = 3; i < 6; i++) snap(i, twoLevel),
      ];
      final h = lrgRingHistory(snaps, minParts: 1);

      expect(h.points, hasLength(6));
      expect(h.events, hasLength(1));
      expect(h.events.single.kind, LrgEventKind.scaleEmerged);
      expect(h.events.single.fromCount, 1);
      expect(h.events.single.toCount, 2);
      expect(h.events.single.commitSha, 'c3');
      // "Now" reflects the latest snapshot.
      expect(h.current.hasHierarchy, isTrue);
      expect(h.currentScales.length, greaterThanOrEqualTo(2));
    });

    test('a single-snapshot flicker is smoothed away, not reported', () {
      final snaps = [
        snap(0, single),
        snap(1, single),
        snap(2, twoLevel), // lone blip
        snap(3, single),
        snap(4, single),
      ];
      final h = lrgRingHistory(snaps, minParts: 1);
      expect(h.events, isEmpty,
          reason: 'a one-commit blip must not become a transition');
    });

    test('empty input → empty history', () {
      final h = lrgRingHistory(const [], minParts: 1);
      expect(h.isEmpty, isTrue);
    });
  });
}
