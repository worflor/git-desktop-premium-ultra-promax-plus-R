// Tests for SpectralOperator — the commuting ring of functions of L.
//
// Target invariants (all proven in `tmp_primitive_operators.py`):
//   - H_t · H_s = H_{t+s}                          (semigroup)
//   - R_z − R_w = (z − w) · R_z · R_w              (resolvent identity)
//   - waveCos² + waveSin² = identity               (Pythagoras)
//   - bandProjection² = bandProjection             (idempotent)
//   - fromFunction(f) · fromFunction(g) = fromFunction(λ ↦ f·g) (ring)
//   - A · A.inverse() = identity   (when A is non-vanishing)

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/spectral_operator.dart';

SpectralBasis _cycleBasis(int n) {
  final rows = <List<(int, double)>>[];
  final dis = 1.0 / math.sqrt(2.0);
  for (var i = 0; i < n; i++) {
    rows.add([((i - 1 + n) % n, dis * dis), ((i + 1) % n, dis * dis)]);
  }
  final ptr = <int>[0];
  final idx = <int>[];
  final vals = <double>[];
  for (final row in rows) {
    for (final (j, v) in row) {
      idx.add(j);
      vals.add(v);
    }
    ptr.add(idx.length);
  }
  final g = CsrGraph(
    n: n,
    indptr: Int32List.fromList(ptr),
    indices: Int32List.fromList(idx),
    values: Float64List.fromList(vals),
  );
  return SpectralBasis.fromGraph(g, math.min(n, 20));
}

bool _profilesClose(SpectralOperator a, SpectralOperator b, double tol) {
  if (a.profile.length != b.profile.length) return false;
  for (var j = 0; j < a.profile.length; j++) {
    if ((a.profile[j] - b.profile[j]).abs() > tol) return false;
  }
  return true;
}

void main() {
  group('primitive constructors', () {
    test('identity is all-ones', () {
      final basis = _cycleBasis(10);
      final I = SpectralOperator.identity(basis);
      for (final v in I.profile) {
        expect(v, equals(1.0));
      }
    });

    test('zero is all-zeros', () {
      final basis = _cycleBasis(10);
      final Z = SpectralOperator.zero(basis);
      for (final v in Z.profile) {
        expect(v, equals(0.0));
      }
    });

    test('heat(0) = identity', () {
      final basis = _cycleBasis(12);
      expect(_profilesClose(
        SpectralOperator.heat(basis, 0.0),
        SpectralOperator.identity(basis),
        1e-12,
      ), isTrue);
    });

    test('waveCos(0) = identity', () {
      final basis = _cycleBasis(12);
      expect(_profilesClose(
        SpectralOperator.waveCos(basis, 0.0),
        SpectralOperator.identity(basis),
        1e-12,
      ), isTrue);
    });
  });

  group('ring algebra', () {
    test('heat semigroup: H_t · H_s = H_{t+s}', () {
      final basis = _cycleBasis(16);
      final h3 = SpectralOperator.heat(basis, 3.0);
      final h5 = SpectralOperator.heat(basis, 5.0);
      final h8 = SpectralOperator.heat(basis, 8.0);
      expect(_profilesClose(h3 * h5, h8, 1e-10), isTrue);
    });

    test('heat inverse: H_{-t} · H_t = identity', () {
      final basis = _cycleBasis(12);
      final h = SpectralOperator.heat(basis, 2.5);
      final hInv = SpectralOperator.heat(basis, -2.5);
      expect(_profilesClose(
        h * hInv,
        SpectralOperator.identity(basis),
        1e-9,
      ), isTrue);
    });

    test('Pythagoras: waveCos² + waveSin² = identity', () {
      final basis = _cycleBasis(12);
      for (final t in [0.5, 1.0, 3.7, 10.0]) {
        final c = SpectralOperator.waveCos(basis, t);
        final s = SpectralOperator.waveSin(basis, t);
        final sum = (c * c) + (s * s);
        expect(_profilesClose(sum, SpectralOperator.identity(basis), 1e-10),
            isTrue,
            reason: 'Pythagoras failed at t=$t');
      }
    });

    test('bandProjection is idempotent (P · P = P)', () {
      final basis = _cycleBasis(20);
      final mid = basis.eigenvalues[basis.k ~/ 2];
      final P = SpectralOperator.bandProjection(basis, 0.0, mid);
      expect(_profilesClose(P * P, P, 1e-12), isTrue);
    });

    test('resolvent identity: R_z − R_w = (z − w) · R_z · R_w', () {
      final basis = _cycleBasis(16);
      // Pick z and w well off the spectrum.
      const z = 3.7;
      const w = 5.2;
      final rZ = SpectralOperator.resolvent(basis, z);
      final rW = SpectralOperator.resolvent(basis, w);
      final lhs = rZ - rW;
      final rhs = (rZ * rW).scale(z - w);
      expect(_profilesClose(lhs, rhs, 1e-10), isTrue);
    });

    test('composition of fromFunction is pointwise product', () {
      final basis = _cycleBasis(12);
      final f = SpectralOperator.fromFunction(basis, (l) => 2.0 * l + 1.0);
      final g = SpectralOperator.fromFunction(basis, (l) => l * l - 0.3);
      final fg = f * g;
      final expected = SpectralOperator.fromFunction(
        basis,
        (l) => (2.0 * l + 1.0) * (l * l - 0.3),
      );
      expect(_profilesClose(fg, expected, 1e-10), isTrue);
    });

    test('addition is commutative', () {
      final basis = _cycleBasis(10);
      final a = SpectralOperator.heat(basis, 1.2);
      final b = SpectralOperator.waveCos(basis, 0.7);
      expect(_profilesClose(a + b, b + a, 1e-12), isTrue);
    });

    test('multiplication is commutative (this is a COMMUTING algebra)', () {
      final basis = _cycleBasis(10);
      final a = SpectralOperator.heat(basis, 1.2);
      final b = SpectralOperator.fractionalLaplacian(basis, 1.5);
      expect(_profilesClose(a * b, b * a, 1e-12), isTrue);
    });

    test('inverse: A · A.inverse() = identity when A is non-vanishing', () {
      final basis = _cycleBasis(12);
      final a = SpectralOperator.heat(basis, 0.5); // strictly positive
      final aInv = a.inverse();
      expect(_profilesClose(a * aInv, SpectralOperator.identity(basis), 1e-9),
          isTrue);
    });

    test('scale distributes over composition', () {
      final basis = _cycleBasis(10);
      final A = SpectralOperator.heat(basis, 0.8);
      final B = SpectralOperator.waveCos(basis, 1.3);
      final lhs = (A * B).scale(2.5);
      final rhs = A.scale(2.5) * B;
      expect(_profilesClose(lhs, rhs, 1e-12), isTrue);
    });
  });

  group('action on projections', () {
    test('heat on a projection equals SpectralProjection.diffuseAt', () {
      final basis = _cycleBasis(16);
      final rho = Float64List(basis.n);
      rho[0] = 1.0;
      final p = basis.projectSource(rho);
      final H = SpectralOperator.heat(basis, 1.5);
      final viaOp = H.applyTo(p);
      final viaDirect = basis.recombineFromProjection(p.coefficients, 1.5);
      final outOp = basis.recombineFromProjection(viaOp.coefficients, 0.0);
      for (var i = 0; i < basis.n; i++) {
        expect(outOp[i], closeTo(viaDirect[i], 1e-10),
            reason: 'heat operator action at node $i');
      }
    });

    test('identity on a projection returns it unchanged', () {
      final basis = _cycleBasis(12);
      final rho = Float64List(basis.n);
      rho[0] = 1.0;
      rho[3] = 0.5;
      final p = basis.projectSource(rho);
      final I = SpectralOperator.identity(basis);
      final q = I.applyTo(p);
      for (var j = 0; j < basis.k; j++) {
        expect(q.coefficients[j], closeTo(p.coefficients[j], 1e-12));
      }
    });

    test('applyToRho round-trips through identity', () {
      final basis = _cycleBasis(14);
      final rho = Float64List(basis.n);
      for (var i = 0; i < basis.n; i++) {
        rho[i] = (i % 3) - 1.0;
      }
      final I = SpectralOperator.identity(basis);
      final out = I.applyToRho(rho);
      // Reconstruction through the basis may lose components outside
      // the k-dim truncation; check the projection agrees.
      final pIn = basis.project(rho);
      final pOut = basis.project(out);
      for (var j = 0; j < basis.k; j++) {
        expect(pOut[j], closeTo(pIn[j], 1e-10));
      }
    });
  });

  group('scalar observables', () {
    test('identity trace equals k', () {
      final basis = _cycleBasis(12);
      final I = SpectralOperator.identity(basis);
      expect(I.trace, equals(basis.k.toDouble()));
    });

    test('heat trace equals Σ e^{−tλ} (reproduces SpectralBasis.heatTrace)',
        () {
      final basis = _cycleBasis(16);
      for (final t in [0.5, 1.0, 2.5]) {
        final H = SpectralOperator.heat(basis, t);
        expect(H.trace, closeTo(basis.heatTrace(t), 1e-12));
      }
    });

    test('spectral norm of a band projection is 1', () {
      final basis = _cycleBasis(16);
      final mid = basis.eigenvalues[basis.k ~/ 2];
      final P = SpectralOperator.bandProjection(basis, 0.0, mid);
      expect(P.spectralNorm, closeTo(1.0, 1e-12));
    });
  });

  group('error paths', () {
    test('cross-basis composition throws StateError', () {
      final basisA = _cycleBasis(8);
      final basisB = _cycleBasis(10);
      final a = SpectralOperator.heat(basisA, 1.0);
      final b = SpectralOperator.heat(basisB, 1.0);
      expect(() => a + b, throwsA(isA<StateError>()));
      expect(() => a - b, throwsA(isA<StateError>()));
      expect(() => a * b, throwsA(isA<StateError>()));
    });

    test('applyTo on wrong basis throws StateError', () {
      final basisA = _cycleBasis(8);
      final basisB = _cycleBasis(10);
      final op = SpectralOperator.heat(basisA, 1.0);
      final rho = Float64List(basisB.n);
      rho[0] = 1.0;
      final p = basisB.projectSource(rho);
      expect(() => op.applyTo(p), throwsA(isA<StateError>()));
    });
  });
}
