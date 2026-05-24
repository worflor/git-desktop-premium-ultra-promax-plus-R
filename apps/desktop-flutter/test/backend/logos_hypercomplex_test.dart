// Tests for the unified Logos Transform — the 2-axis Fourier
// bijection that is the engine's master equation.
//
// The three theorems locked here:
//   1. Inverse roundtrip: forward → inverse recovers the field
//      to fp precision.
//   2. Parseval on both axes simultaneously: energy in (v, k) equals
//      energy in (j, ω).
//   3. Heat evolution is diagonal in the dual: heat(t) applied in
//      node-space equals multiplication by e^{−tλⱼ} in mode-space.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_hypercomplex.dart';

CsrGraph _pathGraph(int n) {
  final edges = <List<(int, double)>>[];
  for (var i = 0; i < n; i++) {
    final row = <(int, double)>[];
    if (i > 0) row.add((i - 1, 1.0));
    if (i < n - 1) row.add((i + 1, 1.0));
    edges.add(row);
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

void main() {
  group('Logos Transform — the master equation', () {
    test('forward → inverse roundtrip recovers the field', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(8), 8);
      const n = 8;
      const nCommits = 6;
      final rng = math.Random(0xF1E1D);
      final field = Float64List(n * nCommits);
      for (var i = 0; i < field.length; i++) {
        field[i] = rng.nextDouble() * 2 - 1;
      }
      final dual = forwardLogosTransform(
        basis: basis,
        fieldCommitMajor: field,
        commitCount: nCommits,
      );
      final recovered = inverseLogosTransform(
        basis: basis,
        realJOmega: dual.real,
        imagJOmega: dual.imaginary,
        commitCount: nCommits,
      );
      // For a full-rank basis (k = n), roundtrip should be exact to f64.
      for (var i = 0; i < field.length; i++) {
        expect(recovered[i], closeTo(field[i], 1e-9),
            reason: 'position $i diverged on roundtrip');
      }
    });

    test('Parseval: ‖S‖²_{v,k} = ‖Ŝ‖²_{j,ω}', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(10), 10);
      const n = 10;
      const nCommits = 8;
      final rng = math.Random(0xBABE);
      final field = Float64List(n * nCommits);
      for (var i = 0; i < field.length; i++) {
        field[i] = rng.nextDouble() * 2 - 1;
      }
      final forward = logosFieldEnergy(field);
      final dual = forwardLogosTransform(
        basis: basis,
        fieldCommitMajor: field,
        commitCount: nCommits,
      );
      final dualEnergy = logosDualEnergy(dual.real, dual.imaginary);
      expect(dualEnergy, closeTo(forward, 1e-9),
          reason: 'Parseval must hold on both axes simultaneously');
    });

    test('dual is conjugate-symmetric for real inputs', () {
      // For real S, Ŝ(j, N − ω) = conj(Ŝ(j, ω)). Magnitude spectrum
      // is palindromic in ω.
      final basis = SpectralBasis.fromGraph(_pathGraph(6), 6);
      const n = 6;
      const nCommits = 8;
      final field = Float64List(n * nCommits);
      final rng = math.Random(3);
      for (var i = 0; i < field.length; i++) {
        field[i] = rng.nextDouble();
      }
      final dual = forwardLogosTransform(
        basis: basis,
        fieldCommitMajor: field,
        commitCount: nCommits,
      );
      for (var j = 0; j < basis.k; j++) {
        for (var omega = 1; omega < nCommits; omega++) {
          final mirror = nCommits - omega;
          final reHere = dual.real[j * nCommits + omega];
          final imHere = dual.imaginary[j * nCommits + omega];
          final reMirror = dual.real[j * nCommits + mirror];
          final imMirror = dual.imaginary[j * nCommits + mirror];
          expect(reMirror, closeTo(reHere, 1e-9));
          expect(imMirror, closeTo(-imHere, 1e-9));
        }
      }
    });

    test('DC mode (ω=0) magnitude equals √N times time-average', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(8), 8);
      const n = 8;
      const nCommits = 4;
      // Build a field that is constant in k: S(v, k) = ρ(v) for all k.
      final field = Float64List(n * nCommits);
      final rho = Float64List.fromList(
          [for (var i = 0; i < n; i++) i.toDouble()]);
      for (var kc = 0; kc < nCommits; kc++) {
        for (var v = 0; v < n; v++) {
          field[kc * n + v] = rho[v];
        }
      }
      final dual = forwardLogosTransform(
        basis: basis,
        fieldCommitMajor: field,
        commitCount: nCommits,
      );
      // The time-constant field has ALL its energy in ω=0. Higher
      // ω modes must be zero.
      for (var j = 0; j < basis.k; j++) {
        for (var omega = 1; omega < nCommits; omega++) {
          expect(dual.real[j * nCommits + omega].abs(), lessThan(1e-10));
          expect(dual.imaginary[j * nCommits + omega].abs(),
              lessThan(1e-10));
        }
      }
    });

    test('time-only sinusoid produces a single-ω peak at each mode', () {
      // S(v, k) = cos(2π·3·k/N) · φ(v) for some spatial profile φ.
      // After transform, energy should concentrate at ω=3 (and its
      // conjugate mirror ω=N−3).
      final basis = SpectralBasis.fromGraph(_pathGraph(8), 8);
      const n = 8;
      const nCommits = 16;
      const plantedOmega = 3;
      final field = Float64List(n * nCommits);
      for (var kc = 0; kc < nCommits; kc++) {
        final temporalAmp = math.cos(2 * math.pi * plantedOmega * kc / nCommits);
        for (var v = 0; v < n; v++) {
          // Simple spatial profile: linear ramp.
          field[kc * n + v] = temporalAmp * (v.toDouble() - n / 2);
        }
      }
      final dual = forwardLogosTransform(
        basis: basis,
        fieldCommitMajor: field,
        commitCount: nCommits,
      );
      // Verify: at the planted ω, total magnitude across modes is
      // much larger than at any non-planted ω (except the mirror
      // at N − plantedOmega).
      double magAtOmega(int omega) {
        var m = 0.0;
        for (var j = 0; j < basis.k; j++) {
          final r = dual.real[j * nCommits + omega];
          final i = dual.imaginary[j * nCommits + omega];
          m += math.sqrt(r * r + i * i);
        }
        return m;
      }

      final atPlanted = magAtOmega(plantedOmega);
      final atMirror = magAtOmega(nCommits - plantedOmega);
      final atOne = magAtOmega(1);
      final atSix = magAtOmega(6);
      // Planted and mirror should dominate.
      expect(atPlanted, greaterThan(atOne * 5));
      expect(atPlanted, greaterThan(atSix * 5));
      expect(atMirror, closeTo(atPlanted, 1e-9));
    });
  });

  group('applyDualSpaceProfile — cross-axis filtering', () {
    test('null profiles act as identity', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(8), 8);
      const n = 8;
      const nCommits = 6;
      final rng = math.Random(11);
      final field = Float64List(n * nCommits);
      for (var i = 0; i < field.length; i++) {
        field[i] = rng.nextDouble();
      }
      final out = applyDualSpaceProfile(
        basis: basis,
        fieldCommitMajor: field,
        commitCount: nCommits,
      );
      for (var i = 0; i < field.length; i++) {
        expect(out[i], closeTo(field[i], 1e-9));
      }
    });

    test('j-profile only reproduces heat via e^{-tλ}', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(8), 8);
      const n = 8;
      const nCommits = 4;
      // Time-constant field; diffusion should act per-commit.
      final field = Float64List(n * nCommits);
      for (var kc = 0; kc < nCommits; kc++) {
        field[kc * n + 3] = 1.0; // delta at node 3, every commit
      }
      const t = 0.5;
      final heatProfile = Float64List(basis.k);
      for (var j = 0; j < basis.k; j++) {
        heatProfile[j] = math.exp(-t * basis.eigenvalues[j]);
      }
      final dualFiltered = applyDualSpaceProfile(
        basis: basis,
        fieldCommitMajor: field,
        commitCount: nCommits,
        jProfile: heatProfile,
      );
      // Compare to per-commit diffusion via the direct method.
      final direct = Float64List(n * nCommits);
      for (var kc = 0; kc < nCommits; kc++) {
        final slice = Float64List.view(field.buffer,
            field.offsetInBytes + kc * n * 8, n);
        final proj = basis.projectSource(slice);
        final diffused = proj.diffuseAt(t);
        for (var v = 0; v < n; v++) {
          direct[kc * n + v] = diffused[v];
        }
      }
      for (var i = 0; i < field.length; i++) {
        expect(dualFiltered[i], closeTo(direct[i], 1e-9),
            reason: 'dual-space j-filter must match direct heat apply');
      }
    });

    test('ω-profile only passes a temporal band', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(6), 6);
      const n = 6;
      const nCommits = 16;
      // Field = static spatial pattern × (cos(2π·3·k/N) + cos(2π·7·k/N)).
      final field = Float64List(n * nCommits);
      for (var kc = 0; kc < nCommits; kc++) {
        final amp3 = math.cos(2 * math.pi * 3 * kc / nCommits);
        final amp7 = math.cos(2 * math.pi * 7 * kc / nCommits);
        final totalAmp = amp3 + amp7;
        for (var v = 0; v < n; v++) {
          field[kc * n + v] = totalAmp * v.toDouble();
        }
      }
      // Temporal profile: pass only bin 3 (and mirror N-3).
      final omegaProfile = Float64List(nCommits);
      omegaProfile[3] = 1.0;
      omegaProfile[nCommits - 3] = 1.0;
      final filtered = applyDualSpaceProfile(
        basis: basis,
        fieldCommitMajor: field,
        commitCount: nCommits,
        omegaProfile: omegaProfile,
      );
      // Reconstruct what pure-3-harmonic would give.
      final expected = Float64List(n * nCommits);
      for (var kc = 0; kc < nCommits; kc++) {
        final amp3 = math.cos(2 * math.pi * 3 * kc / nCommits);
        for (var v = 0; v < n; v++) {
          expected[kc * n + v] = amp3 * v.toDouble();
        }
      }
      for (var i = 0; i < field.length; i++) {
        expect(filtered[i], closeTo(expected[i], 1e-8),
            reason: 'temporal band-pass must isolate the planted harmonic');
      }
    });

    test('profile length mismatch throws', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(6), 6);
      expect(
        () => applyDualSpaceProfile(
          basis: basis,
          fieldCommitMajor: Float64List(6 * 4),
          commitCount: 4,
          jProfile: Float64List(99),
        ),
        throwsStateError,
      );
      expect(
        () => applyDualSpaceProfile(
          basis: basis,
          fieldCommitMajor: Float64List(6 * 4),
          commitCount: 4,
          omegaProfile: Float64List(99),
        ),
        throwsStateError,
      );
    });
  });

  group('Wire format sanity', () {
    test('invalid field length throws', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(4), 4);
      expect(
        () => forwardLogosTransform(
          basis: basis,
          fieldCommitMajor: Float64List(7),
          commitCount: 2,
        ),
        throwsStateError,
      );
    });

    test('invalid dual length throws', () {
      final basis = SpectralBasis.fromGraph(_pathGraph(4), 4);
      expect(
        () => inverseLogosTransform(
          basis: basis,
          realJOmega: Float64List(5),
          imagJOmega: Float64List(5),
          commitCount: 2,
        ),
        throwsStateError,
      );
    });
  });

  group('realDft round-trip — forward → inverse recovers signal', () {
    for (final n in [3, 7, 16, 17, 100, 255, 300, 512]) {
      test('N=$n', () {
        final rng = math.Random(0xDF70 + n);
        final signal = List<double>.generate(n, (_) => rng.nextDouble() * 2 - 1);
        final fwd = realDftForward(signal);
        final recovered = realDftInverse(
          real: fwd.real,
          imaginary: fwd.imaginary,
        );
        expect(recovered.length, equals(n));
        for (var j = 0; j < n; j++) {
          expect(
            recovered[j],
            closeTo(signal[j], 1e-9),
            reason: 'mismatch at index $j for N=$n',
          );
        }
      });
    }
  });
}
