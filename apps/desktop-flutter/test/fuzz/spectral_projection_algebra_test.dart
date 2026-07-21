// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Fuzz tests for the SpectralProjection algebra (lib/backend/logos_core.dart,
// class SpectralProjection ~line 4034).
//
// test/backend/spectral_observables_test.dart and
// test/backend/spectral_generative_test.dart already pin the same methods
// down with hand-built fixtures (`_pathBasis`, `_cycleBasis`, single delta
// vectors) at fixed sizes. That coverage is real but example-based: one
// graph, one or two projections, one set of mode cuts. The value this file
// adds is fuzzing the same algebraic laws across MANY random connected
// graphs (via `buildSymmetricCsrGraph` + `SpectralBasis.fromGraph`) and many
// random coefficient vectors, plus properties that are awkward to hand-pick
// examples for (monotonicity across every keepK from 0..k, partition-of-unity
// over random mode-cut sets, Gram-Schmidt span reconstruction). Scenarios
// that are already thoroughly pinned (e.g. the exact Parseval identity
// `err² = Σ discarded²`, the thermal-prior "low modes get more energy"
// property) are intentionally not repeated here.
//
// All laws are asserted with tolerances, never golden numbers, and every
// `forAll` call goes through the shared seed-driven harness in
// test/support/prop.dart, so a failure prints a reproducible seed + index.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/graph/csr_builder.dart';
import 'package:git_desktop/backend/logos_core.dart';

import '../support/gen.dart';
import '../support/prop.dart';

// ---------------------------------------------------------------------------
// Fixtures — build a random SpectralBasis + one or more SpectralProjections
// from a random connected TestGraph, all threaded through a single per-case
// Rng so every case is deterministically reproducible from its seed+index.
// ---------------------------------------------------------------------------

SpectralBasis _basisFromGraph(TestGraph g, int k) {
  final csr = buildSymmetricCsrGraph(
    n: g.n,
    edges: [for (final (a, b, w) in g.edges) CsrEdge(a, b, w)],
  );
  return SpectralBasis.fromGraph(csr, math.min(k, g.n));
}

Float64List _randRho(Rng rng, int n) {
  return Float64List.fromList([
    for (var i = 0; i < n; i++) rng.nextDouble() * 2 - 1,
  ]);
}

/// One basis + one random projection on it.
class _Basis1 {
  const _Basis1(this.basis, this.proj);
  final SpectralBasis basis;
  final SpectralProjection proj;
}

Gen<_Basis1> _genProj({int maxNodes = 24, int k = 8}) {
  final gGen = genConnectedGraph(maxNodes: maxNodes);
  return (rng) {
    final g = gGen(rng);
    final basis = _basisFromGraph(g, k);
    return _Basis1(basis, basis.projectSource(_randRho(rng, g.n)));
  };
}

/// One basis + one random projection + a random `keepK` in `[0, basis.k]`.
class _Basis1WithKeepK {
  const _Basis1WithKeepK(this.basis, this.proj, this.keepK);
  final SpectralBasis basis;
  final SpectralProjection proj;
  final int keepK;
}

Gen<_Basis1WithKeepK> _genProjWithKeepK({int maxNodes = 24, int k = 8}) {
  final base = _genProj(maxNodes: maxNodes, k: k);
  return (rng) {
    final b1 = base(rng);
    final keepK = rng.intBetween(0, b1.basis.k);
    return _Basis1WithKeepK(b1.basis, b1.proj, keepK);
  };
}

/// One basis + one random projection + a random valid `modeCuts` list
/// (possibly empty; always strictly increasing and inside `[1, k-1]`).
class _Basis1WithCuts {
  const _Basis1WithCuts(this.basis, this.proj, this.cuts);
  final SpectralBasis basis;
  final SpectralProjection proj;
  final List<int> cuts;
}

Gen<_Basis1WithCuts> _genProjWithCuts({int maxNodes = 24, int k = 8}) {
  final base = _genProj(maxNodes: maxNodes, k: k);
  return (rng) {
    final b1 = base(rng);
    final kk = b1.basis.k;
    var cuts = const <int>[];
    if (kk >= 2) {
      final validRange = List<int>.generate(kk - 1, (i) => i + 1); // [1,k-1]
      final numCuts = rng.intBetween(0, validRange.length);
      cuts = rng.sample(validRange, numCuts)..sort();
    }
    return _Basis1WithCuts(b1.basis, b1.proj, cuts);
  };
}

/// One basis + `count` random projections sharing it (for gramSchmidt /
/// decomposeAgainst / reconstructionErrorTo, which all take a second
/// projection on the SAME basis).
class _BasisN {
  const _BasisN(this.basis, this.queries);
  final SpectralBasis basis;
  final List<SpectralProjection> queries;
}

Gen<_BasisN> _genProjN({int maxNodes = 20, int k = 6, int count = 3}) {
  final gGen = genConnectedGraph(maxNodes: maxNodes);
  return (rng) {
    final g = gGen(rng);
    final basis = _basisFromGraph(g, k);
    final queries = [
      for (var i = 0; i < count; i++) basis.projectSource(_randRho(rng, g.n)),
    ];
    return _BasisN(basis, queries);
  };
}

/// Two INDEPENDENT random bases (almost always different signatures) — for
/// the "throws on basis mismatch" laws.
class _TwoBasis {
  const _TwoBasis(this.a, this.b);
  final SpectralBasis a;
  final SpectralBasis b;
}

Gen<_TwoBasis> _genTwoBasis({int maxNodes = 20, int k = 6}) {
  final gGen = genConnectedGraph(maxNodes: maxNodes);
  return (rng) {
    final ga = gGen(rng);
    final gb = gGen(rng);
    return _TwoBasis(_basisFromGraph(ga, k), _basisFromGraph(gb, k));
  };
}

void main() {
  group('compressToTopK — monotonic optimality across keepK', () {
    test('reconstructionErrorTo(original) is non-increasing as keepK grows 0..k', () {
      forAll<_Basis1>(
        _genProj(maxNodes: 24, k: 8),
        check: (fx) {
          final p = fx.proj;
          final k = fx.basis.k;
          if (k == 0) return;
          var prevErr = double.infinity;
          for (var keepK = 0; keepK <= k; keepK++) {
            final err = p.reconstructionErrorTo(p.compressToTopK(keepK));
            expect(
              err,
              lessThanOrEqualTo(prevErr + 1e-9),
              reason: 'error increased going from keepK=${keepK - 1} '
                  'to keepK=$keepK',
            );
            prevErr = err;
          }
        },
        count: 60 * fuzzScale(),
        seed: 0xF00D0001,
        describe: 'compressToTopK monotonic error',
      );
    });

    test('keepK=k reconstructs the original within epsilon; keepK=0 is the '
        'zero projection', () {
      forAll<_Basis1>(
        _genProj(maxNodes: 24, k: 8),
        check: (fx) {
          final p = fx.proj;
          final k = fx.basis.k;
          if (k == 0) return;
          expect(
            p.reconstructionErrorTo(p.compressToTopK(k)),
            closeTo(0.0, 1e-9),
            reason: 'compressToTopK(k) (all modes) must reproduce the input',
          );
          expect(
            p.compressToTopK(0).squaredNorm,
            closeTo(0.0, 1e-18),
            reason: 'compressToTopK(0) must be the zero projection',
          );
        },
        count: 60 * fuzzScale(),
        seed: 0xF00D0002,
        describe: 'compressToTopK boundary behavior',
      );
    });

    test('kept coefficients are never smaller in magnitude than dropped ones '
        '(the kept set IS the top-|coefficient| set)', () {
      forAll<_Basis1WithKeepK>(
        _genProjWithKeepK(maxNodes: 24, k: 8),
        check: (fx) {
          final p = fx.proj;
          final k = fx.basis.k;
          if (k == 0) return;
          final c = p.compressToTopK(fx.keepK);
          var minKept = double.infinity;
          var maxDropped = 0.0;
          for (var j = 0; j < k; j++) {
            final mag = p.coefficients[j].abs();
            if (c.coefficients[j] != 0.0) {
              if (mag < minKept) minKept = mag;
            } else {
              if (mag > maxDropped) maxDropped = mag;
            }
          }
          if (minKept.isFinite) {
            expect(
              minKept,
              greaterThanOrEqualTo(maxDropped - 1e-12),
              reason: 'compressToTopK(${fx.keepK}) kept |$minKept| while '
                  'dropping a larger |$maxDropped|',
            );
          }
        },
        count: 100 * fuzzScale(),
        seed: 0xF00D0003,
        describe: 'compressToTopK top-K magnitude ordering',
      );
    });
  });

  group('gramSchmidt — orthogonality + span preservation', () {
    test('outputs are pairwise orthogonal and every input is reconstructible '
        'from the output span', () {
      forAll<_BasisN>(
        _genProjN(maxNodes: 20, k: 6, count: 4),
        check: (fx) {
          final b = fx.basis;
          if (b.k == 0) return;
          final gs = SpectralProjection.gramSchmidt(fx.queries);
          expect(gs.length, fx.queries.length);

          for (var i = 0; i < gs.length; i++) {
            for (var j = i + 1; j < gs.length; j++) {
              expect(
                gs[i].dot(gs[j]).abs(),
                lessThan(1e-6),
                reason: 'gramSchmidt outputs $i and $j must be orthogonal',
              );
            }
          }

          // Span preservation: since the outputs are mutually orthonormal
          // and span(outputs[0..i]) == span(queries[0..i]) by construction,
          // every query is exactly its projection onto the FULL output
          // family (terms beyond its own index contribute zero because
          // those later outputs are built orthogonal to everything before
          // them).
          for (var i = 0; i < fx.queries.length; i++) {
            final q = fx.queries[i];
            var recon =
                SpectralProjection(basis: b, coefficients: Float64List(b.k));
            for (final o in gs) {
              recon = recon + o.scale(q.dot(o));
            }
            expect(
              q.reconstructionErrorTo(recon),
              lessThan(1e-6),
              reason: 'query $i must be reconstructible from the '
                  'gramSchmidt span',
            );
          }
        },
        count: 40 * fuzzScale(),
        seed: 0xF00D0010,
        describe: 'gramSchmidt orthogonality + span',
      );
    });
  });

  group('bandDecompose — partition of unity', () {
    test('bands sum back to the original with no mode double-counted or '
        'dropped', () {
      forAll<_Basis1WithCuts>(
        _genProjWithCuts(maxNodes: 24, k: 8),
        check: (fx) {
          final p = fx.proj;
          final k = fx.basis.k;
          if (k == 0) return;
          final bands = p.bandDecompose(fx.cuts);
          expect(bands.length, fx.cuts.length + 1);
          for (var j = 0; j < k; j++) {
            var sum = 0.0;
            var nonzeroBands = 0;
            for (final band in bands) {
              if (band.coefficients[j] != 0.0) nonzeroBands++;
              sum += band.coefficients[j];
            }
            expect(
              sum,
              closeTo(p.coefficients[j], 1e-9),
              reason: 'mode $j must sum back to the original across bands',
            );
            expect(
              nonzeroBands,
              lessThanOrEqualTo(1),
              reason: 'mode $j must not be assigned to more than one band',
            );
          }
        },
        count: 100 * fuzzScale(),
        seed: 0xF00D0020,
        describe: 'bandDecompose partition of unity',
      );
    });

    test('throws StateError on out-of-range or non-monotone cuts', () {
      forAll<_Basis1>(
        _genProj(maxNodes: 24, k: 8),
        check: (fx) {
          final p = fx.proj;
          final k = fx.basis.k;
          if (k < 2) return;
          expect(() => p.bandDecompose([0]), throwsStateError);
          expect(() => p.bandDecompose([k]), throwsStateError);
          expect(() => p.bandDecompose([-1]), throwsStateError);
          expect(() => p.bandDecompose([1, 1]), throwsStateError);
          if (k >= 3) {
            expect(() => p.bandDecompose([k - 1, 1]), throwsStateError);
          }
        },
        count: 60 * fuzzScale(),
        seed: 0xF00D0021,
        describe: 'bandDecompose invalid cuts throw',
      );
    });
  });

  group('decomposeAgainst — orthogonal decomposition', () {
    test('parallel+orthogonal reconstruct the original; alignment in '
        '[-1,1]; self-decompose is exact', () {
      forAll<_BasisN>(
        _genProjN(maxNodes: 20, k: 6, count: 2),
        check: (fx) {
          final b = fx.basis;
          if (b.k == 0) return;
          final p = fx.queries[0];
          final q = fx.queries[1];
          final d = p.decomposeAgainst(q);

          final recon = d.parallel + d.orthogonal;
          for (var j = 0; j < b.k; j++) {
            expect(
              recon.coefficients[j],
              closeTo(p.coefficients[j], 1e-8),
              reason: 'parallel + orthogonal must reconstruct the original',
            );
          }
          expect(d.alignment, inInclusiveRange(-1.0 - 1e-9, 1.0 + 1e-9));
          expect(
            d.parallel.dot(d.orthogonal).abs(),
            lessThan(1e-6),
            reason: 'parallel and orthogonal components must be orthogonal',
          );

          if (p.squaredNorm > 1e-9) {
            final selfD = p.decomposeAgainst(p);
            expect(selfD.alignment, closeTo(1.0, 1e-9));
            expect(selfD.orthogonal.squaredNorm, closeTo(0.0, 1e-9));
            for (var j = 0; j < b.k; j++) {
              expect(
                selfD.parallel.coefficients[j],
                closeTo(p.coefficients[j], 1e-8),
              );
            }
          }
        },
        count: 80 * fuzzScale(),
        seed: 0xF00D0030,
        describe: 'decomposeAgainst reconstruction + bounds',
      );
    });
  });

  group('dreamFill — determinism + locality', () {
    test('deterministic under a fixed seed, and preserves the kept '
        '(top-keepK) coefficients exactly', () {
      forAll<_Basis1WithKeepK>(
        _genProjWithKeepK(maxNodes: 24, k: 8),
        check: (fx) {
          final p = fx.proj;
          final k = fx.basis.k;
          if (k == 0) return;
          final compressed = p.compressToTopK(fx.keepK);
          final a = compressed.dreamFill(seed: 12321, priorVariance: 0.05);
          final c = compressed.dreamFill(seed: 12321, priorVariance: 0.05);
          for (var j = 0; j < k; j++) {
            expect(
              a.coefficients[j],
              equals(c.coefficients[j]),
              reason: 'dreamFill must be bit-deterministic under a fixed '
                  'seed',
            );
            if (compressed.coefficients[j] != 0.0) {
              expect(
                a.coefficients[j],
                equals(compressed.coefficients[j]),
                reason: 'kept coefficient $j must survive dreamFill '
                    'unchanged',
              );
            }
          }
        },
        count: 100 * fuzzScale(),
        seed: 0xF00D0040,
        describe: 'dreamFill determinism + locality',
      );
    });
  });

  group('reconstructionErrorTo — metric-ish properties', () {
    test('non-negative, symmetric (‖a-b‖=‖b-a‖ from the L² formula), and '
        'self-distance is zero', () {
      // Symmetry is not stated in the doc comment, but the implementation
      // is `sqrt(Σ (c_i - o_i)²)`, which is manifestly symmetric in its two
      // arguments — verified by reading logos_core.dart before asserting.
      forAll<_BasisN>(
        _genProjN(maxNodes: 20, k: 6, count: 2),
        check: (fx) {
          final b = fx.basis;
          if (b.k == 0) return;
          final p = fx.queries[0];
          final q = fx.queries[1];
          final dPQ = p.reconstructionErrorTo(q);
          final dQP = q.reconstructionErrorTo(p);
          expect(dPQ, greaterThanOrEqualTo(0.0));
          expect(dQP, greaterThanOrEqualTo(0.0));
          expect(
            dPQ,
            closeTo(dQP, 1e-9),
            reason: 'reconstructionErrorTo must be symmetric',
          );
          expect(p.reconstructionErrorTo(p), closeTo(0.0, 1e-9));
          // p and q come from independent random rho draws, so — outside a
          // measure-zero coincidence — their coefficients differ somewhere.
          expect(
            dPQ,
            greaterThan(0.0),
            reason: 'independently-drawn projections should not coincide',
          );
        },
        count: 80 * fuzzScale(),
        seed: 0xF00D0050,
        describe: 'reconstructionErrorTo metric properties',
      );
    });
  });

  group('cross-basis operations throw StateError on signature mismatch', () {
    test('reconstructionErrorTo, decomposeAgainst, bandAlignmentWith, '
        'gramSchmidt', () {
      forAll<_TwoBasis>(
        _genTwoBasis(maxNodes: 20, k: 6),
        check: (fx) {
          // Vanishingly rare signature collision between two independently
          // random graphs — skip rather than flake if it ever happens.
          if (fx.a.signature == fx.b.signature) return;
          if (fx.a.k == 0 || fx.b.k == 0) return;
          final pa = fx.a.projectSource(Float64List(fx.a.n)..[0] = 1.0);
          final pb = fx.b.projectSource(Float64List(fx.b.n)..[0] = 1.0);
          expect(() => pa.reconstructionErrorTo(pb), throwsStateError);
          expect(() => pa.decomposeAgainst(pb), throwsStateError);
          expect(() => pa.bandAlignmentWith(pb, const []), throwsStateError);
          expect(
            () => SpectralProjection.gramSchmidt([pa, pb]),
            throwsStateError,
          );
        },
        count: 60 * fuzzScale(),
        seed: 0xF00D0060,
        describe: 'cross-basis signature mismatch throws',
      );
    });
  });
}
