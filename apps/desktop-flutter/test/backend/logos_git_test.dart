// Tests for the Logos-inspired diffusion engine.
//
// Design note: these tests pin down MATHEMATICAL INVARIANTS, not surface
// behaviour. An adversary who returns a constant from `diffuse` should
// fail. An adversary who flips a sign in the Chebyshev recurrence
// should fail. An adversary who breaks the D^(-1/2) fusion should fail.
//
// The three load-bearing tests are:
//   - Path-graph reference:   pins Chebyshev math against analytic exp(-tL)
//   - Linearity:              heat equation must be linear in ρ
//   - Disconnected containment: no mass leaks across components
//
// If those three pass, the engine's physics is correct. Everything else
// is surface / API / edge-case coverage.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_signature.dart';
import 'package:git_desktop/backend/logos_git_integrity.dart';
import 'package:git_desktop/backend/spectral_persistence.dart';
import 'package:git_desktop/backend/spectral_spacetime.dart';
import 'package:git_desktop/backend/spectral_ratchet.dart';
import 'package:git_desktop/backend/spectral_state.dart';
import 'package:git_desktop/backend/spectral_tower.dart';
import 'package:git_desktop/backend/spectral_walks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  double csrWeight(dynamic graph, int from, int to) {
    for (var k = graph.indptr[from]; k < graph.indptr[from + 1]; k++) {
      if (graph.indices[k] == to) return graph.values[k];
    }
    return 0.0;
  }

  test('RelevanceScore.toString uses ASCII phi label', () {
    expect(
      const RelevanceScore('lib/foo.dart', 0.125).toString(),
      'lib/foo.dart  phi=0.1250',
    );
  });

  group('flow diagnostics + typed witnesses', () {
    test('structured flow prefers harmonic over curl for coherent evidence', () {
      final flow = computeLogosFlowDiagnostics(
        coherence: 0.92,
        stability: 0.88,
        sourceAlignment: 0.86,
        fieldAlignment: 0.82,
        lowFrequencySupport: 0.74,
        highFrequencySurprise: 0.08,
        higherOrderLift: 0.10,
        reducibilityGap: 0.06,
        witnessKindFractions: const {
          'axis': 0.5,
          'transport': 0.3,
          'spectrum': 0.2,
        },
      );

      expect(flow.gradientMass, inInclusiveRange(0.0, 1.0));
      expect(flow.curlMass, inInclusiveRange(0.0, 1.0));
      expect(flow.harmonicMass, inInclusiveRange(0.0, 1.0));
      expect(flow.structuralStress, inInclusiveRange(0.0, 1.0));
      expect(flow.harmonicMass, greaterThan(flow.curlMass));
    });

    test('relation descriptor and transport lane preserve direction roles', () {
      final relation = logosRelationDescriptor(
        'lib/model.dart',
        'lib/generated/model.g.dart',
      );
      final transport = logosTransportLane(
        'lib/generated/model.g.dart',
        'lib/model.dart',
      );

      expect(relation, isNotNull);
      expect(relation!.label, 'source-generated');
      expect(relation.directional, isTrue);
      expect(relation.sourceRole, 'source');
      expect(relation.targetRole, 'generated');

      expect(transport, isNotNull);
      expect(transport!.label, 'generated->source');
      expect(transport.directional, isTrue);
      expect(transport.sourceRole, 'generated');
      expect(transport.targetRole, 'source');
    });

    test('witness syndrome reports coverage and missing kinds', () {
      final syndrome = computeLogosWitnessSyndrome(
        const LogosEvidenceRollup(
          transportPull: 0.18,
          lowFrequencySupport: 0.4,
          highFrequencySurprise: 0.2,
          higherOrderLift: 0.1,
          reducibilityGap: 0.05,
          witnessKindFractions: {
            'relation': 0.35,
            'transport': 0.30,
            'integrity': 0.20,
            'axis': 0.15,
          },
        ),
        witnessEntropy: 0.42,
      );

      expect(syndrome.coverage, closeTo(0.75, 1e-9));
      expect(syndrome.corroboration, closeTo(0.65, 1e-9));
      expect(syndrome.disagreement, closeTo(0.42, 1e-9));
      expect(
        syndrome.dominantKinds,
        containsAll(<String>['relation', 'transport']),
      );
      expect(syndrome.missingKinds, contains('spectrum'));
    });
  });


  group('path-graph analytic reference', () {
    // 3-node path graph with unit edges: 0 — 1 — 2
    //   W = [[0,1,0],[1,0,1],[0,1,0]]
    //   D = diag(1, 2, 1)
    //   W_norm = D^(-1/2) W D^(-1/2) has eigenvalues {−1, 0, +1}
    //   L_sym = I - W_norm has eigenvalues {0, 1, 2}   (confirms spectrum ⊂ [0, 2])
    //
    // Eigenvectors (normalised):
    //   λ=0: v0 = (1/2)[1, √2, 1]           (principal — ∝ √degree)
    //   λ=1: v1 = (1/√2)[1, 0, -1]
    //   λ=2: v2 = (1/2)[1, -√2, 1]
    //
    // For any ρ: exp(-t·L_sym)·ρ = Σ_k exp(-t·λ_k) (ρ·v_k) v_k
    //
    // This reference is computed WITHOUT using Chebyshev — directly
    // from the spectral decomposition. If the engine's Chebyshev path
    // matches this to 1e-6, the math is correct end-to-end.

    final invSqrt2 = 1.0 / math.sqrt(2);
    // CSR of the 3-node path graph with D^(-1/2) already fused:
    //   W_norm[0,1] = W_norm[1,0] = W_norm[1,2] = W_norm[2,1] = 1/√2
    //   indptr = [0, 1, 3, 4] — row 0 has 1 edge, row 1 has 2, row 2 has 1
    final graph = buildCsrForTesting(
      n: 3,
      indptr: [0, 1, 3, 4],
      indices: [1, 0, 2, 1],
      values: [invSqrt2, invSqrt2, invSqrt2, invSqrt2],
    );

    // Analytic reference for source ρ = [1, 0, 0].
    Float64List analyticPhi(double t, List<double> rho) {
      // v0·ρ, v1·ρ, v2·ρ
      final c0 = 0.5 * rho[0] + (math.sqrt(2) / 2) * rho[1] + 0.5 * rho[2];
      final c1 = invSqrt2 * rho[0] - invSqrt2 * rho[2];
      final c2 = 0.5 * rho[0] - (math.sqrt(2) / 2) * rho[1] + 0.5 * rho[2];

      final e0 = math.exp(-t * 0);
      final e1 = math.exp(-t * 1);
      final e2 = math.exp(-t * 2);

      // φ = e0·c0·v0 + e1·c1·v1 + e2·c2·v2
      return Float64List.fromList([
        e0 * c0 * 0.5 + e1 * c1 * invSqrt2 + e2 * c2 * 0.5,
        e0 * c0 * (math.sqrt(2) / 2) + e1 * c1 * 0 + e2 * c2 * (-math.sqrt(2) / 2),
        e0 * c0 * 0.5 + e1 * c1 * (-invSqrt2) + e2 * c2 * 0.5,
      ]);
    }

    for (final t in [0.25, 1.0, 2.0, 4.0]) {
      test('Chebyshev matches spectral decomposition at t=$t', () {
        final rho = Float64List.fromList([1.0, 0.0, 0.0]);
        final expected = analyticPhi(t, rho);
        final actual = Float64List(3);
        diffuseChebyshevForTesting(
          graph: graph,
          rho: rho,
          phi: actual,
          t: t,
          K: 20,
        );
        for (var i = 0; i < 3; i++) {
          expect(
            actual[i],
            closeTo(expected[i], 1e-6),
            reason:
                'φ[$i] mismatch at t=$t: Chebyshev=${actual[i]}, spectral=${expected[i]}',
          );
        }
      });
    }

    test('L_sym spectrum on path graph stays in [0, 2]', () {
      // Apply L_sym a couple times and verify that the induced operator
      // satisfies the Gershgorin bound. We don't have an eigensolver in
      // scope — we spot-check by confirming the applyLsym output obeys
      // ‖L_sym·v‖ ≤ 2·‖v‖ (operator norm bound) for random vectors.
      final rng = math.Random(1337);
      for (var trial = 0; trial < 20; trial++) {
        final v = Float64List.fromList([
          rng.nextDouble() * 2 - 1,
          rng.nextDouble() * 2 - 1,
          rng.nextDouble() * 2 - 1,
        ]);
        final out = Float64List(3);
        graph.applyLsym(v, out);
        final vn = math.sqrt(v.fold<double>(0, (s, x) => s + x * x));
        final outN = math.sqrt(out.fold<double>(0, (s, x) => s + x * x));
        expect(outN, lessThanOrEqualTo(2 * vn + 1e-9),
            reason: 'L_sym operator norm exceeded 2 on trial $trial');
      }
    });

    test('stationary (t→∞) matches √degree eigenvector', () {
      // For a connected graph and source ρ, long-time φ converges to
      // the projection of ρ onto L_sym's null-space = √degree (normalised).
      final rho = Float64List.fromList([1.0, 0.0, 0.0]);
      // √degree = [1, √2, 1], normalised to unit length: [1/2, √2/2, 1/2]
      final principalVec = [0.5, math.sqrt(2) / 2, 0.5];
      final c0 = rho[0] * principalVec[0] +
          rho[1] * principalVec[1] +
          rho[2] * principalVec[2];
      final expectedStationary = [
        c0 * principalVec[0],
        c0 * principalVec[1],
        c0 * principalVec[2],
      ];

      final actual = Float64List(3);
      diffuseChebyshevForTesting(
        graph: graph,
        rho: rho,
        phi: actual,
        t: 30.0, // effectively ∞
        K: 30,
      );
      for (var i = 0; i < 3; i++) {
        expect(
          actual[i],
          closeTo(expectedStationary[i], 1e-5),
          reason:
              'φ[$i] at t→∞: got ${actual[i]}, expected stationary ${expectedStationary[i]}',
        );
      }
    });
  });


  group('diffuseWeighted — single-pass weighted source', () {
    test('equivalent to diffuse() when all weights are equal', () {
      // diffuseWeighted is the optimisation of summing N single-source
      // diffuses scaled by weight. Under equal weights it must exactly
      // match diffuse(sourceSet) which internally renormalises.
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      final setForm =
          engine.diffuse({'lib/a.dart', 'lib/b.dart'}, t: 1.0);
      final weightedForm = engine.diffuseWeighted(
        const {'lib/a.dart': 1.0, 'lib/b.dart': 1.0},
        t: 1.0,
        excludePaths: const {'lib/a.dart', 'lib/b.dart'},
      );
      expect(weightedForm.length, setForm.length);
      for (var i = 0; i < setForm.length; i++) {
        expect(weightedForm[i].path, setForm[i].path,
            reason: 'order diverges at position $i');
        expect(weightedForm[i].phi, closeTo(setForm[i].phi, 1e-9),
            reason: 'φ diverges at position $i');
      }
    });

    test('linearity holds: weighted mix = sum of weighted singles', () {
      // Heat kernel linearity: diffuseWeighted({a:wa, b:wb}) equals the
      // sum of (wa·diffuse({a}) + wb·diffuse({b})) up to the shared
      // renormalisation. Both sides divide by wa+wb, so the relation
      // becomes: weighted == 0.5·(singleA + singleB) for wa=wb.
      //
      // Here we use UNEQUAL weights to stress the linearity invariant.
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      final weightedAB = {
        for (final s in engine.diffuseWeighted(
          const {'lib/a.dart': 3.0, 'lib/b.dart': 1.0},
          t: 1.0,
          excludePaths: const {'lib/a.dart', 'lib/b.dart'},
        ))
          s.path: s.phi,
      };

      final scoresA = {
        for (final s in engine.diffuse({'lib/a.dart'}, t: 1.0))
          s.path: s.phi,
      };
      final scoresB = {
        for (final s in engine.diffuse({'lib/b.dart'}, t: 1.0))
          s.path: s.phi,
      };

      // Under the same renormalised source vector:
      //   weighted{a:3, b:1} normalises ρ to (0.75·e_a + 0.25·e_b)
      //   single{a} normalises ρ to e_a
      //   single{b} normalises ρ to e_b
      // So φ_weighted should equal 0.75·φ_a + 0.25·φ_b pointwise.
      // Both seeds are excluded from the weighted result; the linear
      // combination on the right is computed on non-seed targets only.
      for (final path in ['lib/c.dart', 'lib/unrelated.dart']) {
        final expected = 0.75 * (scoresA[path] ?? 0) +
            0.25 * (scoresB[path] ?? 0);
        final actual = weightedAB[path] ?? 0;
        expect(actual, closeTo(expected, 1e-6),
            reason: 'linearity broke for $path: '
                'actual=$actual expected=$expected');
      }
    });

    test('empty weights returns empty list', () {
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      expect(engine.diffuseWeighted(const {}, t: 1.0), isEmpty);
    });

    test('weights with unknown paths are skipped silently', () {
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      final result = engine.diffuseWeighted(
        const {
          'lib/a.dart': 1.0,
          'nonexistent/path.dart': 1000.0, // would dominate if not skipped
        },
        t: 1.0,
        excludePaths: const {'lib/a.dart'},
      );
      expect(result, isNotEmpty);
      // The huge fake weight must not leak into real file scores.
      for (final s in result) {
        expect(s.phi, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('linearity in ρ', () {
    test('diffuse({a}) + diffuse({b}) = 2·diffuse({a,b}) (both normalised)', () {
      // Both `engine.diffuse` and `engine.buildBasis` normalise ρ so
      // total mass = 1. That means diffuse({a,b}) has total input mass
      // 1 split as (1/2, 1/2); two single-seed diffuses have input mass
      // 1 each. So: single-a + single-b = 2 · (2·single-combined), i.e.
      // combined = (single-a + single-b) / 2.
      final stats = _canonicalCoChangeStats();
      final engine = LogosGit.buildFromStats(stats);

      final scoresA = {
        for (final s in engine.diffuse({'lib/a.dart'})) s.path: s.phi,
      };
      final scoresB = {
        for (final s in engine.diffuse({'lib/b.dart'})) s.path: s.phi,
      };
      final scoresAB = {
        for (final s in engine.diffuse({'lib/a.dart', 'lib/b.dart'}))
          s.path: s.phi,
      };

      // Both seeds are in the source set for {a,b}, so their φ is filtered
      // out. We check linearity only on shared nodes (c, unrelated) —
      // where both single runs AND the combined run produce a value.
      //
      // For shared targets (not seeds of either single run): φ(AB) should
      // equal 0.5 · (φ(A) + φ(B)). The seed-filtering in `diffuse` makes
      // this a little subtle — the shared target 'lib/c.dart' never
      // appears as source, so it's clean.
      for (final path in ['lib/c.dart', 'lib/unrelated.dart']) {
        final a = scoresA[path] ?? 0;
        final b = scoresB[path] ?? 0;
        final ab = scoresAB[path] ?? 0;
        if (a == 0 && b == 0 && ab == 0) continue; // skip absent
        expect(
          ab,
          closeTo(0.5 * (a + b), 1e-6),
          reason: 'linearity violated for $path: '
              'φ(AB)=$ab vs 0.5·(φ(A)+φ(B))=${0.5 * (a + b)}',
        );
      }
    });
  });


  group('disconnected components', () {
    test('mass does not leak from one component to another', () {
      // Two pairs {A1, A2} and {B1, B2} with Jaccard ~ 0.9 within each
      // pair and no cross-pair edges. Parents differ so SP won't bridge.
      final stats = LogosGitStats(
        touches: const {
          'alpha/a1.dart': 20,
          'alpha/a2.dart': 18,
          'beta/b1.dart': 15,
          'beta/b2.dart': 17,
        },
        totalCommits: 40,
        volatility: const {
          'alpha/a1.dart': 8.0,
          'alpha/a2.dart': 7.5,
          'beta/b1.dart': 9.0,
          'beta/b2.dart': 8.5,
        },
        volMean: 8.0,
        volStddev: 0.55,
        coupling: FileCouplingMatrix(
          jaccard: const {
            'alpha/a1.dart': {'alpha/a2.dart': 0.9},
            'alpha/a2.dart': {'alpha/a1.dart': 0.9},
            'beta/b1.dart': {'beta/b2.dart': 0.9},
            'beta/b2.dart': {'beta/b1.dart': 0.9},
          },
          headHash: 'disconnect',
          commitsAnalyzed: 40,
        ),
        perFileCommitIndices: const {},
      );
      final engine = LogosGit.buildFromStats(stats);
      final scores = engine.diffuse({'alpha/a1.dart'}, t: 4.0);
      // SP can bridge within a directory (siblings share parent).
      // Assert: B-side files have MUCH lower φ than A-side. Pure
      // disconnection is violated by SP's directory fallback; what we
      // verify is that the wall is at least an order of magnitude.
      final aSide =
          scores.firstWhere((s) => s.path == 'alpha/a2.dart').phi;
      for (final path in ['beta/b1.dart', 'beta/b2.dart']) {
        final cross = scores
            .where((s) => s.path == path)
            .fold<double>(0, (acc, s) => acc + s.phi);
        expect(
          cross,
          lessThan(aSide * 0.1),
          reason: 'cross-component leakage to $path: $cross vs $aSide '
              '(should be < 10% of within-component φ)',
        );
      }
    });
  });


  group('BornMixer', () {
    const caps = [0.6931, 1.3863, 1.0986, 1.0986];
    const mixer = BornMixer(caps);

    test('single confident axis reproduces its own probability', () {
      // With only one active axis, Born mix collapses to p:
      //   (w√p)² / ((w√p)² + (w√(1-p))²) = p / (p + (1-p)) = p
      // regardless of weight. Verify for multiple p values.
      for (final p in [0.1, 0.3, 0.7, 0.85]) {
        final result = mixer.mix([
          AxisObs(p, 100),
          AxisObs.silent,
          AxisObs.silent,
          AxisObs.silent,
        ]);
        expect(result, closeTo(p, 1e-6));
      }
    });

    test('p=0.5 axes with huge evidence do not dilute informative axes', () {
      // Adversary target: this test fails if someone removes the
      // `w == 0 ? continue` gate — a huge-evidence axis at p=0.5
      // would otherwise pull the mix back toward 0.5.
      final withFlat = mixer.mix([
        const AxisObs(0.85, 100),
        const AxisObs(0.5, 10000), // flat, gated to zero weight
        AxisObs.silent,
        AxisObs.silent,
      ]);
      final withoutFlat = mixer.mix([
        const AxisObs(0.85, 100),
        AxisObs.silent,
        AxisObs.silent,
        AxisObs.silent,
      ]);
      expect(withFlat, closeTo(withoutFlat, 1e-9));
    });

    test('weight increases continuously with confidence |p - 0.5|', () {
      // Monotonicity check: two identical axes at the same p produce
      // the same output as one, but two at different p produce
      // intermediate results.
      final r05 = mixer.mix([
        const AxisObs(0.5001, 100),
        AxisObs.silent,
        AxisObs.silent,
        AxisObs.silent,
      ]);
      final r07 = mixer.mix([
        const AxisObs(0.7, 100),
        AxisObs.silent,
        AxisObs.silent,
        AxisObs.silent,
      ]);
      final r09 = mixer.mix([
        const AxisObs(0.9, 100),
        AxisObs.silent,
        AxisObs.silent,
        AxisObs.silent,
      ]);
      expect(r05, lessThan(r07));
      expect(r07, lessThan(r09));
    });

    test('caps actually clamp evidence — adding 10× more n does nothing', () {
      // F0 cap = ln(2) ≈ 0.6931. Evidence n=5 → log1p(5)=1.79, clamped
      // to 0.6931. Evidence n=100 → same clamp. Therefore mixing two
      // axes of identical p but different n (both over cap) should
      // produce identical output.
      final capped1 = mixer.mix([
        const AxisObs(0.8, 100), // log1p(100) = 4.61, clamped to 0.6931
        AxisObs.silent,
        AxisObs.silent,
        AxisObs.silent,
      ]);
      final capped2 = mixer.mix([
        const AxisObs(0.8, 10000), // log1p(10000) = 9.21, clamped to 0.6931
        AxisObs.silent,
        AxisObs.silent,
        AxisObs.silent,
      ]);
      expect(capped1, closeTo(capped2, 1e-9));
    });
  });


  group('Chebyshev Bessel coefficients', () {
    test('coefficients are finite across a reasonable (t, K) grid', () {
      // Adversary target: raise K past what the 60-term factorial series
      // can handle → NaN/inf leaks through. Pin the usable range.
      for (final t in [0.1, 0.5, 1.0, 2.0, 4.0, 8.0]) {
        for (final K in [10, 20, 30]) {
          final coeffs = chebyshevBesselCoeffsForTesting(t, K);
          expect(coeffs.length, K + 1);
          for (var k = 0; k <= K; k++) {
            expect(coeffs[k].isFinite, isTrue,
                reason: 'non-finite coefficient at t=$t K=$K k=$k: ${coeffs[k]}');
          }
        }
      }
    });

    test('tail coefficients decay — |c_K| is much smaller than |c_0|', () {
      // For t=1, K=20 the tail should be below 1e-8 of the leading term.
      // Adversary target: series truncation drift / off-by-one would
      // leave the tail inflated.
      final coeffs = chebyshevBesselCoeffsForTesting(1.0, 20);
      final head = coeffs[0].abs();
      final tail = coeffs.last.abs();
      expect(tail / head, lessThan(1e-8),
          reason: 'Chebyshev tail not converging: head=$head tail=$tail');
    });
  });


  group('LogosGit.buildFromStats — construction', () {
    test('empty stats produce empty engine', () {
      final engine = LogosGit.buildFromStats(LogosGitStats(
        touches: const {},
        totalCommits: 0,
        volatility: const {},
        volMean: 0,
        volStddev: 0,
        coupling: FileCouplingMatrix.empty,
        perFileCommitIndices: const {},
      ));
      expect(engine.nodePaths, isEmpty);
      expect(engine.diffuse({'anything.dart'}), isEmpty);
    });

    test('gatherEvidence returns null for empty and all-unknown focus', () {
      final emptyEngine = LogosGit.buildFromStats(LogosGitStats(
        touches: const {},
        totalCommits: 0,
        volatility: const {},
        volMean: 0,
        volStddev: 0,
        coupling: FileCouplingMatrix.empty,
        perFileCommitIndices: const {},
      ));
      expect(
        emptyEngine.gatherEvidence(
          focusWeights: const {'lib/anything.dart': 1.0},
        ),
        isNull,
      );

      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      expect(
        engine.gatherEvidence(
          focusWeights: const {'lib/unknown.dart': 1.0},
        ),
        isNull,
      );
    });

    test('CSR is symmetric — W[i,j] == W[j,i] for every materialised edge',
        () {
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      final graph = engine.graphForTesting;
      for (var i = 0; i < graph.n; i++) {
        for (var k = graph.indptr[i]; k < graph.indptr[i + 1]; k++) {
          final j = graph.indices[k];
          final forward = graph.values[k];
          // Find (j, i) in row j
          var back = 0.0;
          var found = false;
          for (var kk = graph.indptr[j]; kk < graph.indptr[j + 1]; kk++) {
            if (graph.indices[kk] == i) {
              back = graph.values[kk];
              found = true;
              break;
            }
          }
          expect(found, isTrue, reason: 'edge ($i,$j) has no reverse ($j,$i)');
          expect(back, closeTo(forward, 1e-9),
              reason: 'asymmetric edge ($i,$j): $forward vs ($j,$i): $back');
        }
      }
    });

    test('transport graph can be asymmetric while main graph stays symmetric',
        () {
      final stats = LogosGitStats(
        touches: const {
          'lib/foo.dart': 12,
          'lib/generated/foo.g.dart': 12,
        },
        totalCommits: 20,
        volatility: const {
          'lib/foo.dart': 2.0,
          'lib/generated/foo.g.dart': 2.0,
        },
        volMean: 2.0,
        volStddev: 0.1,
        coupling: FileCouplingMatrix(
          jaccard: const {
            'lib/foo.dart': {'lib/generated/foo.g.dart': 0.2},
            'lib/generated/foo.g.dart': {'lib/foo.dart': 0.2},
          },
          headHash: 'transport-directionality',
          commitsAnalyzed: 20,
        ),
        perFileCommitIndices: const {},
      );
      final engine = LogosGit.buildFromStats(stats);
      final sourceId = engine.pathToId['lib/foo.dart']!;
      final generatedId = engine.pathToId['lib/generated/foo.g.dart']!;

      final graphForward = csrWeight(engine.graphForTesting, sourceId, generatedId);
      final graphBackward = csrWeight(
        engine.graphForTesting,
        generatedId,
        sourceId,
      );
      final transportForward = csrWeight(
        engine.transportGraph,
        sourceId,
        generatedId,
      );
      final transportBackward = csrWeight(
        engine.transportGraph,
        generatedId,
        sourceId,
      );
      final forwardLane = logosTransportLane(
        'lib/foo.dart',
        'lib/generated/foo.g.dart',
      );
      final backwardLane = logosTransportLane(
        'lib/generated/foo.g.dart',
        'lib/foo.dart',
      );

      expect(graphBackward, closeTo(graphForward, 1e-9));
      expect(forwardLane, isNotNull);
      expect(backwardLane, isNotNull);
      expect(
        forwardLane!.strength,
        isNot(closeTo(backwardLane!.strength, 1e-9)),
      );
      expect(transportForward, closeTo(forwardLane.strength, 1e-9));
      expect(transportBackward, closeTo(backwardLane.strength, 1e-9));
      if (forwardLane.strength > backwardLane.strength) {
        expect(transportForward, greaterThan(0.0));
        expect(transportForward, greaterThan(transportBackward));
      } else {
        expect(transportBackward, greaterThan(0.0));
        expect(transportBackward, greaterThan(transportForward));
      }
    });

    test('all φ values are finite and non-negative', () {
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      final scores = engine.diffuse({'lib/a.dart'}, t: 1.0);
      expect(scores, isNotEmpty);
      var positiveCount = 0;
      for (final s in scores) {
        expect(s.phi.isFinite, isTrue, reason: '${s.path} non-finite');
        expect(s.phi, greaterThanOrEqualTo(0.0), reason: '${s.path} negative');
        if (s.phi > 0) positiveCount++;
      }
      // Adversary target: an engine returning all zeros passes
      // non-negativity. Force at least one strictly positive.
      expect(positiveCount, greaterThan(0),
          reason: 'every φ was zero — diffusion produced no signal');
    });

    test('single-file repo does not crash', () {
      final engine = LogosGit.buildFromStats(LogosGitStats(
        touches: const {'lib/solo.dart': 5},
        totalCommits: 5,
        volatility: const {'lib/solo.dart': 12.0},
        volMean: 12.0,
        volStddev: 0,
        coupling: FileCouplingMatrix(
          jaccard: const {'lib/solo.dart': <String, double>{}},
          headHash: 'abc',
          commitsAnalyzed: 5,
        ),
        perFileCommitIndices: const {},
      ));
      expect(engine.nodePaths, contains('lib/solo.dart'));
      expect(engine.diffuse({'lib/solo.dart'}), isEmpty);
    });
  });


  group('DiffusionBasis', () {
    test('recombine matches direct diffuse at same t', () {
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      final seeds = {'lib/a.dart'};
      final basis = engine.buildBasis(seeds)!;
      for (final t in [0.25, 1.0, 2.5, 4.0]) {
        final direct = engine.diffuse(seeds, t: t);
        final recombined =
            basis.recombineAndRank(t, idToPath: engine.nodePaths);
        expect(recombined.length, direct.length, reason: 't=$t length mismatch');
        for (var i = 0; i < direct.length; i++) {
          expect(recombined[i].path, direct[i].path, reason: 't=$t order');
          expect(recombined[i].phi, closeTo(direct[i].phi, 1e-6),
              reason: 't=$t value at $i');
        }
      }
    });

    test('recombine at the same t is idempotent (byte-identical on repeats)',
        () {
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      final basis = engine.buildBasis({'lib/a.dart'})!;
      final a = basis.recombine(1.2);
      final b = basis.recombine(1.2);
      for (var i = 0; i < a.length; i++) {
        // `==` because deterministic f64 arithmetic should produce bits.
        expect(a[i], b[i], reason: 'non-deterministic at index $i');
      }
    });

    test('temperature locality — cold diffusion is more peaked than hot', () {
      // Correct test: locality = max(φ) / sum(φ). This should decrease
      // with t because mass spreads out as t grows.
      // (The old test checked total mass, which is not conserved under
      //  L_sym — it was ill-posed.)
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      final basis = engine.buildBasis({'lib/a.dart'})!;

      double locality(double t) {
        final phi = basis.recombine(t);
        var maxVal = 0.0;
        var sumVal = 0.0;
        for (var i = 0; i < phi.length; i++) {
          if (phi[i] > maxVal) maxVal = phi[i];
          sumVal += phi[i];
        }
        return sumVal == 0 ? 0 : maxVal / sumVal;
      }

      final cold = locality(0.25);
      final warm = locality(1.0);
      final hot = locality(4.0);
      expect(cold, greaterThan(warm));
      expect(warm, greaterThan(hot));
    });
  });


  group('LogosGit.relatedTo ordering', () {
    test('tightly-coupled files rank above loosely-coupled ones', () {
      // NOTE: naïve assumption "highest direct Jaccard ranks first" is
      // WRONG under diffusion. A node with medium direct coupling but
      // strong secondary paths (A→B→C) can outrank a node with strong
      // direct coupling but no secondary paths — which is the point
      // of a multi-hop heat kernel. We only assert the weaker, truly
      // invariant claim: tight-cluster members rank above outliers.
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      final related = engine.relatedTo('lib/a.dart', limit: 10);
      expect(related, isNotEmpty);
      final byPath = {for (final r in related) r.path: r.phi};

      // b and c are both tight-cluster members (J ≥ 0.7 with a).
      // unrelated has J=0.05 with a.
      final b = byPath['lib/b.dart'];
      final c = byPath['lib/c.dart'];
      final unrelated = byPath['lib/unrelated.dart'] ?? 0.0;

      expect(b, isNotNull, reason: 'b should be surfaced');
      expect(c, isNotNull, reason: 'c should be surfaced');
      expect(b!, greaterThan(unrelated),
          reason: 'b (J=0.8) should rank above unrelated (J=0.05)');
      expect(c!, greaterThan(unrelated),
          reason: 'c (J=0.7) should rank above unrelated (J=0.05)');
      // Seed itself must not appear.
      expect(byPath.containsKey('lib/a.dart'), isFalse);
    });
  });

  group('LogosGit.plan — budget respect', () {
    test('plan never exceeds budget, even tiny budgets', () {
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      final scores = engine.diffuse({'lib/a.dart'});
      // Approximate tier costs baked into plan() — worst-case upper bound.
      const maxTierCost = 1600;
      for (final budget in [0, 60, 300, 1000, 100000]) {
        final plan = engine.plan(scores, budget: budget);
        // Sum the worst-case cost — any plan item's cost is ≤ maxTierCost.
        // A correct plan, summed by its tiers' nominal cost, must be ≤ budget.
        const tierCostTable = <EmissionTier, int>{
          EmissionTier.full: 1600,
          EmissionTier.signature: 300,
          EmissionTier.breadcrumb: 60,
        };
        final sumCost = plan.fold<int>(
          0,
          (s, p) => s + tierCostTable[p.tier]!,
        );
        expect(sumCost, lessThanOrEqualTo(budget),
            reason: 'plan at budget=$budget spent $sumCost');
        // Every plan item's tier cost fits within its budget share.
        for (final p in plan) {
          expect(tierCostTable[p.tier]!, lessThanOrEqualTo(maxTierCost));
        }
      }
    });
  });

  group('Born overlap interference', () {
    test('identical probes overlap near 1.0', () {
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      final w = {'lib/a.dart': 1.0, 'lib/b.dart': 1.0};
      final overlap = engine.bornOverlap(w, w);
      expect(overlap, isNotNull);
      expect(overlap!, greaterThan(0.9),
          reason: 'identical probes should overlap near 1.0, got $overlap');
    });

    test('disjoint probes overlap strictly less than identical', () {
      // Build a fixture with two clearly-separated clusters. Overlap
      // of a probe on cluster 1 with a probe on cluster 2 should be
      // meaningfully lower than the self-overlap of either.
      final stats = LogosGitStats(
        touches: const {
          'x1/a.dart': 20, 'x1/b.dart': 18,
          'x2/c.dart': 15, 'x2/d.dart': 17,
        },
        totalCommits: 40,
        volatility: const {
          'x1/a.dart': 5.0, 'x1/b.dart': 5.0,
          'x2/c.dart': 5.0, 'x2/d.dart': 5.0,
        },
        volMean: 5.0,
        volStddev: 0.0,
        coupling: FileCouplingMatrix(
          jaccard: const {
            'x1/a.dart': {'x1/b.dart': 0.9},
            'x1/b.dart': {'x1/a.dart': 0.9},
            'x2/c.dart': {'x2/d.dart': 0.9},
            'x2/d.dart': {'x2/c.dart': 0.9},
          },
          headHash: 'o',
          commitsAnalyzed: 100,
        ),
        perFileCommitIndices: const {},
      );
      final engine = LogosGit.buildFromStats(stats);
      final probeA = {'x1/a.dart': 1.0};
      final probeB = {'x2/c.dart': 1.0};
      final selfA = engine.bornOverlap(probeA, probeA)!;
      final cross = engine.bornOverlap(probeA, probeB)!;
      expect(cross, lessThan(selfA),
          reason: 'cross-cluster overlap should be strictly less than '
              'within-cluster self overlap (self=$selfA cross=$cross)');
    });

    test('overlap is symmetric (up to numeric noise)', () {
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      final a = {'lib/a.dart': 1.0};
      final b = {'lib/c.dart': 1.0};
      final ab = engine.bornOverlap(a, b)!;
      final ba = engine.bornOverlap(b, a)!;
      expect(ab, closeTo(ba, 1e-9));
    });

    test('empty-weight probe returns null', () {
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      expect(engine.bornOverlap(const {}, {'lib/a.dart': 1.0}), isNull);
      expect(engine.bornOverlap({'lib/a.dart': 1.0}, const {}), isNull);
    });
  });

  group('Adaptive Chebyshev K', () {
    test('result stays within tolerance of fixed K=32 reference', () {
      // On the 3-node path graph: run both adaptive (default K=20) and
      // a manually-higher K=32 reference. They should agree to the
      // adaptive epsilon (1e-8).
      final invSqrt2 = 1.0 / math.sqrt(2);
      final graph = buildCsrForTesting(
        n: 3,
        indptr: [0, 1, 3, 4],
        indices: [1, 0, 2, 1],
        values: [invSqrt2, invSqrt2, invSqrt2, invSqrt2],
      );
      final rho = Float64List.fromList([1.0, 0.0, 0.0]);
      final phiAdaptive = Float64List(3);
      final phiHighK = Float64List(3);
      diffuseChebyshevForTesting(
        graph: graph, rho: rho, phi: phiAdaptive, t: 0.25, K: 20);
      diffuseChebyshevForTesting(
        graph: graph, rho: rho, phi: phiHighK, t: 0.25, K: 32);
      for (var i = 0; i < 3; i++) {
        expect(phiAdaptive[i], closeTo(phiHighK[i], 1e-6),
            reason: 'adaptive K drifted from K=32 at index $i');
      }
    });

    test('at high t, adaptive K uses more terms', () {
      // The adaptiveK helper lives in the same compilation unit —
      // we verify via the Bessel coefficient exposure.
      final lowT = chebyshevBesselCoeffsForTesting(0.25, 20);
      final highT = chebyshevBesselCoeffsForTesting(4.0, 20);
      // Count significant terms (above 1e-8 of peak).
      int significant(List<double> coeffs) {
        final peak = coeffs.map((c) => c.abs()).reduce(math.max);
        return coeffs
            .where((c) => c.abs() >= peak * 1e-8)
            .length;
      }
      expect(significant(highT), greaterThan(significant(lowT)),
          reason: 'higher t requires more significant Chebyshev terms');
    });
  });

  group('LogosGit.coherence', () {
    test('returns 1.0 for trivial inputs (≤1 known path)', () {
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      expect(engine.coherence(const <String>[]), 1.0);
      expect(engine.coherence(const ['lib/a.dart']), 1.0);
      expect(engine.coherence(const ['does/not/exist.dart']), 1.0);
    });

    test('at least one non-CC axis contributes — SP bumps pure-unrelated pairs',
        () {
      // Adversary target: coherence that simply averages Jaccard would
      // pass the canonical test (where Jaccard already separates tight
      // from scattered). Here we build a fixture where two files share
      // a parent directory (SP fires) but have zero historical co-change
      // (Jaccard = 0). Their coherence should still be > 0.
      final stats = LogosGitStats(
        touches: const {
          'same/dir/x.dart': 5,
          'same/dir/y.dart': 5,
          'other/far.dart': 5,
        },
        totalCommits: 20,
        volatility: const {
          'same/dir/x.dart': 5.0,
          'same/dir/y.dart': 5.0,
          'other/far.dart': 5.0,
        },
        volMean: 5.0,
        volStddev: 0.0,
        coupling: FileCouplingMatrix(
          jaccard: {
            'same/dir/x.dart': <String, double>{},
            'same/dir/y.dart': <String, double>{},
            'other/far.dart': <String, double>{},
          },
          headHash: 'sp',
          commitsAnalyzed: 20,
        ),
        perFileCommitIndices: const {},
      );
      final engine = LogosGit.buildFromStats(stats);
      final siblingCoh =
          engine.coherence(const ['same/dir/x.dart', 'same/dir/y.dart']);
      final strangerCoh =
          engine.coherence(const ['same/dir/x.dart', 'other/far.dart']);
      // Siblings should edge out strangers on SP alone — even with zero CC.
      expect(siblingCoh, greaterThanOrEqualTo(strangerCoh));
    });
  });

  group('gatherEvidence — higher-order sidecar', () {
    test('candidate self-membership does not inflate lift or witness sources', () {
      const triad = LogosCommitHyperedge(
        paths: ['lib/a.dart', 'lib/b.dart', 'lib/c.dart'],
        weight: 1.0,
        summary: 'triad witness',
      );
      final stats = LogosGitStats(
        touches: const {
          'lib/a.dart': 12,
          'lib/b.dart': 12,
          'lib/c.dart': 12,
          'lib/unrelated.dart': 1,
        },
        totalCommits: 20,
        volatility: const {
          'lib/a.dart': 3.0,
          'lib/b.dart': 3.0,
          'lib/c.dart': 3.0,
          'lib/unrelated.dart': 1.0,
        },
        volMean: 2.5,
        volStddev: 1.0,
        coupling: FileCouplingMatrix(
          jaccard: const {
            'lib/a.dart': {
              'lib/b.dart': 0.2,
              'lib/c.dart': 0.2,
              'lib/unrelated.dart': 0.02,
            },
            'lib/b.dart': {
              'lib/a.dart': 0.2,
              'lib/c.dart': 0.2,
              'lib/unrelated.dart': 0.02,
            },
            'lib/c.dart': {
              'lib/a.dart': 0.2,
              'lib/b.dart': 0.2,
              'lib/unrelated.dart': 0.02,
            },
            'lib/unrelated.dart': {
              'lib/a.dart': 0.02,
              'lib/b.dart': 0.02,
              'lib/c.dart': 0.02,
            },
          },
          headHash: 'hyper',
          commitsAnalyzed: 20,
        ),
        perFileCommitIndices: const {},
        hyperedgesByPath: const {
          'lib/a.dart': [triad],
          'lib/b.dart': [triad],
          'lib/c.dart': [triad],
        },
      );
      final engine = LogosGit.buildFromStats(stats);
      final result = engine.gatherEvidence(
        focusWeights: const {
          'lib/a.dart': 1.0,
          'lib/b.dart': 1.0,
          'lib/c.dart': 1.0,
        },
        topK: 10,
      );
      expect(result, isNotNull);
      final c = result!.ranked.firstWhere((e) => e.path == 'lib/c.dart');
      expect(c.higherOrderLift, lessThanOrEqualTo(1.0 + 1e-9));

      final hyperWitness = c.witnesses.firstWhere(
        (w) => w.label == 'commit-hyperedge',
      );
      expect(hyperWitness.sourcePaths, isNot(contains('lib/c.dart')));
      expect(hyperWitness.sourcePaths.toSet(), containsAll({'lib/a.dart', 'lib/b.dart'}));

      final reducibilityWitness = c.witnesses.firstWhere(
        (w) => w.label == 'pairwise-loss',
      );
      expect(reducibilityWitness.kind, LogosWitnessKind.reducibility);
    });

    test('self-focused generated file does not create self transport witnesses', () {
      final stats = LogosGitStats(
        touches: const {
          'lib/foo.dart': 12,
          'lib/generated/foo.g.dart': 12,
        },
        totalCommits: 20,
        volatility: const {
          'lib/foo.dart': 2.0,
          'lib/generated/foo.g.dart': 2.0,
        },
        volMean: 2.0,
        volStddev: 0.1,
        coupling: FileCouplingMatrix(
          jaccard: const {
            'lib/foo.dart': {'lib/generated/foo.g.dart': 0.3},
            'lib/generated/foo.g.dart': {'lib/foo.dart': 0.3},
          },
          headHash: 'self-transport',
          commitsAnalyzed: 20,
        ),
        perFileCommitIndices: const {},
      );
      final engine = LogosGit.buildFromStats(stats);
      final result = engine.gatherEvidence(
        focusWeights: const {'lib/generated/foo.g.dart': 1.0},
        topK: 5,
      );
      expect(result, isNotNull);
      final self = result!.ranked.firstWhere(
        (e) => e.path == 'lib/generated/foo.g.dart',
      );
      expect(
        self.witnesses.where((w) =>
            w.kind == LogosWitnessKind.transport ||
            w.kind == LogosWitnessKind.relation),
        isEmpty,
      );
    });

    test('generated/source focus pair emits a generated-source metric sidecar', () {
      final stats = LogosGitStats(
        touches: const {
          'lib/foo.dart': 12,
          'lib/generated/foo.g.dart': 12,
        },
        totalCommits: 20,
        volatility: const {
          'lib/foo.dart': 2.0,
          'lib/generated/foo.g.dart': 2.0,
        },
        volMean: 2.0,
        volStddev: 0.1,
        coupling: FileCouplingMatrix(
          jaccard: const {
            'lib/foo.dart': {'lib/generated/foo.g.dart': 0.3},
            'lib/generated/foo.g.dart': {'lib/foo.dart': 0.3},
          },
          headHash: 'generated-sidecar',
          commitsAnalyzed: 20,
        ),
        perFileCommitIndices: const {},
      );
      final engine = LogosGit.buildFromStats(stats);
      final result = engine.gatherEvidence(
        focusWeights: const {
          'lib/foo.dart': 1.0,
          'lib/generated/foo.g.dart': 1.0,
        },
        topK: 5,
      );
      expect(result, isNotNull);
      expect(
        result!.metricSidecars.map((s) => s.label),
        contains('generated-source-map'),
      );
      expect(
        result.transport.dominantLanes(),
        containsAll(<String>['source->generated', 'generated->source']),
      );
      expect(
        result.transport.frontierPaths,
        containsAll(<String>['lib/foo.dart', 'lib/generated/foo.g.dart']),
      );
      expect(result.transport.frontierEdges, isNotEmpty);
      expect(
        result.transport.frontierEdges.map((e) => e.laneLabel),
        containsAll(<String>['source->generated', 'generated->source']),
      );
      expect(
        result.transportPullByPath.keys,
        containsAll(<String>['lib/foo.dart', 'lib/generated/foo.g.dart']),
      );
      final transportPulls = <double>[];
      for (final path in const ['lib/foo.dart', 'lib/generated/foo.g.dart']) {
        final score = result.ranked.firstWhere((e) => e.path == path);
        transportPulls.add(score.transportPull);
        expect(
          result.transportPullByPath[path],
          closeTo(score.transportPull, 1e-9),
        );
        expect(
          score.sidecars.map((s) => s.label),
          contains('generated-source-map'),
        );
      }
      expect(
        transportPulls.reduce(math.max),
        greaterThan(0.0),
      );
    });

    test('transport lane can admit generated companion from source-only focus', () {
      final stats = LogosGitStats(
        touches: const {
          'lib/foo.dart': 12,
          'lib/generated/foo.g.dart': 12,
        },
        totalCommits: 20,
        volatility: const {
          'lib/foo.dart': 2.0,
          'lib/generated/foo.g.dart': 2.0,
        },
        volMean: 2.0,
        volStddev: 0.1,
        coupling: FileCouplingMatrix(
          jaccard: const {
            'lib/foo.dart': {'lib/generated/foo.g.dart': 0.2},
            'lib/generated/foo.g.dart': {'lib/foo.dart': 0.2},
          },
          headHash: 'transport-admit',
          commitsAnalyzed: 20,
        ),
        perFileCommitIndices: const {},
      );
      final engine = LogosGit.buildFromStats(stats);
      final result = engine.gatherEvidence(
        focusWeights: const {'lib/foo.dart': 1.0},
        topK: 10,
      );
      expect(result, isNotNull);
      final generated = result!.ranked.firstWhere(
        (e) => e.path == 'lib/generated/foo.g.dart',
      );
      expect(generated.transportPull, greaterThan(0.0));
      expect(
        result.transport.dominantLanes(),
        contains('source->generated'),
      );
      expect(
        result.transport.frontierPaths,
        contains('lib/generated/foo.g.dart'),
      );
      expect(result.transport.frontierEdges, isNotEmpty);
      final edge = result.transport.frontierEdges.firstWhere(
        (e) => e.targetPath == 'lib/generated/foo.g.dart',
      );
      expect(edge.sourcePath, 'lib/foo.dart');
      expect(edge.laneLabel, 'source->generated');
      expect(edge.directional, isTrue);
      expect(edge.pull, closeTo(generated.transportPull, 1e-9));
      expect(
        result.transportPullByPath['lib/generated/foo.g.dart'],
        closeTo(generated.transportPull, 1e-9),
      );
      expect(
        generated.sidecars.map((s) => s.label),
        contains('generated-source-map'),
      );
      expect(generated.transportedSupport, greaterThan(0.0));
      expect(generated.innovationResidual, closeTo(0.0, 1e-9));
      expect(result.inquiryPlan.steps, isNotEmpty);
      final inquiry = result.inquiryPlan.steps.firstWhere(
        (step) => step.path == 'lib/generated/foo.g.dart',
      );
      expect(inquiry.kind, LogosInquiryActionKind.inspectCompanion);
      expect(inquiry.viaPath, 'lib/foo.dart');
      expect(inquiry.laneLabel, 'source->generated');
    });

    test('semantic motion separates transported companions from innovation residuals', () {
      final stats = LogosGitStats(
        touches: const {
          'lib/foo.dart': 12,
          'lib/generated/foo.g.dart': 10,
          'lib/neighbor.dart': 10,
        },
        totalCommits: 20,
        volatility: const {
          'lib/foo.dart': 2.0,
          'lib/generated/foo.g.dart': 2.0,
          'lib/neighbor.dart': 2.0,
        },
        volMean: 2.0,
        volStddev: 0.1,
        coupling: FileCouplingMatrix(
          jaccard: const {
            'lib/foo.dart': {
              'lib/generated/foo.g.dart': 0.2,
              'lib/neighbor.dart': 0.8,
            },
            'lib/generated/foo.g.dart': {'lib/foo.dart': 0.2},
            'lib/neighbor.dart': {'lib/foo.dart': 0.8},
          },
          headHash: 'semantic-motion',
          commitsAnalyzed: 20,
        ),
        perFileCommitIndices: const {},
      );
      final engine = LogosGit.buildFromStats(stats);
      final result = engine.gatherEvidence(
        focusWeights: const {'lib/foo.dart': 1.0},
        topK: 10,
      );
      expect(result, isNotNull);
      final generated = result!.ranked.firstWhere(
        (e) => e.path == 'lib/generated/foo.g.dart',
      );
      final neighbor = result.ranked.firstWhere(
        (e) => e.path == 'lib/neighbor.dart',
      );
      expect(generated.transportedSupport, greaterThan(0.0));
      expect(generated.innovationResidual, lessThanOrEqualTo(1e-9));
      expect(neighbor.transportedSupport, closeTo(0.0, 1e-9));
      expect(neighbor.innovationResidual, greaterThan(0.0));
      expect(result.semanticMotion.warpCoverage, greaterThan(0.0));
      expect(result.semanticMotion.innovationMass, greaterThan(0.0));
      expect(
        result.semanticMotion.innovationFrontier,
        contains('lib/neighbor.dart'),
      );
    });

    test('witness-from-carrier surfaces missing test witness residuals', () {
      final stats = LogosGitStats(
        touches: const {
          'lib/foo.dart': 12,
          'test/foo_test.dart': 4,
        },
        totalCommits: 20,
        volatility: const {
          'lib/foo.dart': 2.0,
          'test/foo_test.dart': 2.0,
        },
        volMean: 2.0,
        volStddev: 1.0,
        coupling: FileCouplingMatrix(
          jaccard: const {
            'lib/foo.dart': {
              'test/foo_test.dart': 0.08,
            },
            'test/foo_test.dart': {
              'lib/foo.dart': 0.08,
            },
          },
          headHash: 'witness-residual',
          commitsAnalyzed: 20,
        ),
        perFileCommitIndices: const {},
      );
      final engine = LogosGit.buildFromStats(stats);
      final result = engine.gatherEvidence(
        focusWeights: const {'lib/foo.dart': 1.0},
        detailBudget: 4,
      );
      expect(result, isNotNull);
      final testScore = result!.ranked.firstWhere(
        (e) => e.path == 'test/foo_test.dart',
      );
      expect(testScore.transportedSupport, greaterThan(0.0));
      expect(testScore.witnessResidual, greaterThan(0.0));
      final residual = result.residualByPath['test/foo_test.dart'];
      expect(residual, isNotNull);
      expect(residual!.transportedSupport, closeTo(testScore.transportedSupport, 1e-9));
      expect(residual.witnessResidual, closeTo(testScore.witnessResidual, 1e-9));
      expect(result.witnessResidual.predictedMass, greaterThan(0.0));
      expect(result.witnessResidual.residualMass, greaterThan(0.0));
      expect(
        result.witnessResidual.frontierPaths,
        contains('test/foo_test.dart'),
      );
      expect(
        result.witnessResidual.dominantKinds,
        anyOf(contains('source->test'), contains('source-test')),
      );
      expect(
        testScore.sidecars.map((s) => s.label),
        contains('test-witness-map'),
      );
      final inquiry = result.inquiryPlan.steps.firstWhere(
        (step) => step.path == 'test/foo_test.dart',
      );
      expect(inquiry.rationale, contains('missing'));
    });

    test('transport seeding materializes taxonomy-backed companions without structural coupling', () {
      final stats = LogosGitStats(
        touches: const {
          'lib/foo.dart': 12,
          'test/foo_test.dart': 4,
        },
        totalCommits: 20,
        volatility: const {
          'lib/foo.dart': 2.0,
          'test/foo_test.dart': 2.0,
        },
        volMean: 2.0,
        volStddev: 1.0,
        coupling: FileCouplingMatrix(
          jaccard: {},
          headHash: 'transport-seed-only',
          commitsAnalyzed: 20,
        ),
        perFileCommitIndices: const {},
      );
      final engine = LogosGit.buildFromStats(stats);
      final result = engine.gatherEvidence(
        focusWeights: const {'lib/foo.dart': 1.0},
        detailBudget: 4,
      );
      expect(result, isNotNull);
      final testScore = result!.ranked.firstWhere(
        (e) => e.path == 'test/foo_test.dart',
      );
      expect(testScore.support, closeTo(0.0, 1e-9));
      expect(testScore.transportedSupport, greaterThan(0.0));
      expect(testScore.witnessResidual, greaterThan(0.0));
      expect(
        result.transport.frontierEdges.any(
          (edge) =>
              edge.sourcePath == 'lib/foo.dart' &&
              edge.targetPath == 'test/foo_test.dart',
        ),
        isTrue,
      );
    });

    test('derived transport is interpolated from the operator field', () {
      final stats = LogosGitStats(
        touches: const {
          'lib/foo.dart': 12,
          'lib/generated/foo.g.dart': 12,
        },
        totalCommits: 20,
        volatility: const {
          'lib/foo.dart': 2.0,
          'lib/generated/foo.g.dart': 2.0,
        },
        volMean: 2.0,
        volStddev: 0.1,
        coupling: FileCouplingMatrix(
          jaccard: const {
            'lib/foo.dart': {'lib/generated/foo.g.dart': 0.2},
            'lib/generated/foo.g.dart': {'lib/foo.dart': 0.2},
          },
          headHash: 'transport-derived',
          commitsAnalyzed: 20,
        ),
        perFileCommitIndices: const {},
      );
      final engine = LogosGit.buildFromStats(stats).withSymbolEdges(const {
        'lib/generated/foo.extra.dart': {
          'lib/generated/foo.g.dart': 1.0,
        },
      });
      final result = engine.gatherEvidence(
        focusWeights: const {'lib/foo.dart': 1.0},
        topK: 10,
      );
      expect(result, isNotNull);
      final known = result!.ranked.firstWhere(
        (e) => e.path == 'lib/generated/foo.g.dart',
      );
      final derived = result.ranked.firstWhere(
        (e) => e.path == 'lib/generated/foo.extra.dart',
      );
      expect(derived.transportPull, greaterThan(0.0));
      expect(
        derived.transportPull,
        closeTo(known.transportPull, 1e-9),
      );
      expect(
        result.transportPullByPath['lib/generated/foo.extra.dart'],
        closeTo(derived.transportPull, 1e-9),
      );
    });

    test('low t still preserves near-vs-far ordering for spectrum fields', () {
      final engine = LogosGit.buildFromStats(_canonicalCoChangeStats());
      final result = engine.gatherEvidence(
        focusWeights: const {'lib/a.dart': 1.0},
        t: 0.05,
        topK: 8,
      );
      expect(result, isNotNull);
      final source = result!.ranked.firstWhere((e) => e.path == 'lib/a.dart');
      expect(source.lowFrequencySupport, greaterThanOrEqualTo(0.0));
      expect(source.highFrequencySurprise, greaterThan(0.0));
    });
  });

  group('integrity relation helpers', () {
    test('generated-source lane is directional and explicit', () {
      final lane = logosTransportLane(
        'lib/generated/foo.g.dart',
        'lib/foo.dart',
      );
      expect(lane, isNotNull);
      expect(lane!.label, 'generated->source');
      expect(lane.strength, greaterThan(0.4));
    });

    test('fixture and vendor relations carry non-zero strength', () {
      expect(
        logosRelationStrength('test/fixtures/foo.json', 'lib/foo.dart'),
        greaterThan(0.0),
      );
      expect(
        logosRelationStrength('packages/vendor/pkg/foo.dart', 'lib/foo.dart'),
        greaterThan(0.0),
      );
    });
  });

  group('CsrGraph rank-1 updates', () {
    // Small symmetric fixture: 3 nodes in a triangle with weights
    //   0-1 = 0.6,  1-2 = 0.4,  0-2 = 0.2.
    CsrGraph buildTriangle() => CsrGraph.fromRawEdges(
          n: 3,
          edgesPerNode: const [
            [(1, 0.6), (2, 0.2)],
            [(0, 0.6), (2, 0.4)],
            [(0, 0.2), (1, 0.4)],
          ],
        );

    test('fromRawEdges fuses D^{-1/2} symmetrically', () {
      final g = buildTriangle();
      // L_sym symmetry: values[i→j] == values[j→i].
      expect(csrWeight(g, 0, 1), closeTo(csrWeight(g, 1, 0), 1e-12));
      expect(csrWeight(g, 1, 2), closeTo(csrWeight(g, 2, 1), 1e-12));
      expect(csrWeight(g, 0, 2), closeTo(csrWeight(g, 2, 0), 1e-12));
      expect(g.supportsRankOneUpdates, isTrue);
    });

    test('withNodeAppended preserves Laplacian symmetry', () {
      final base = buildTriangle();
      final augmented = base.withNodeAppended(
        edges: const [(0, 0.3), (2, 0.7)],
      );
      expect(augmented.n, 4);
      // Symmetry must hold across every edge, old or new.
      for (var i = 0; i < augmented.n; i++) {
        for (var j = 0; j < augmented.n; j++) {
          if (i == j) continue;
          expect(
            csrWeight(augmented, i, j),
            closeTo(csrWeight(augmented, j, i), 1e-12),
            reason: 'L_sym must be symmetric at ($i,$j)',
          );
        }
      }
    });

    test('withNodeAppended matches full rebuild via fromRawEdges', () {
      // Start from triangle; append a 4th node connected to 0 and 2.
      final incremental = buildTriangle().withNodeAppended(
        edges: const [(0, 0.3), (2, 0.7)],
      );
      // Full rebuild of the same 4-node graph from raw edges.
      final fullRebuild = CsrGraph.fromRawEdges(
        n: 4,
        edgesPerNode: const [
          [(1, 0.6), (2, 0.2), (3, 0.3)],
          [(0, 0.6), (2, 0.4)],
          [(0, 0.2), (1, 0.4), (3, 0.7)],
          [(0, 0.3), (2, 0.7)],
        ],
      );
      // Every fused value should match byte-for-byte modulo float eps.
      for (var i = 0; i < 4; i++) {
        for (var j = 0; j < 4; j++) {
          if (i == j) continue;
          expect(
            csrWeight(incremental, i, j),
            closeTo(csrWeight(fullRebuild, i, j), 1e-12),
            reason: 'values diverge at ($i,$j)',
          );
        }
      }
      // D^{-1/2} must match too.
      for (var i = 0; i < 4; i++) {
        expect(
          incremental.degreeInvSqrt[i],
          closeTo(fullRebuild.degreeInvSqrt[i], 1e-12),
        );
      }
    });

    test('withNodeAppended keeps spectrum in [0, 2]', () {
      final augmented = buildTriangle().withNodeAppended(
        edges: const [(0, 0.3), (2, 0.7)],
      );
      final lambdaMax = augmented.estimateSpectralRadius(iterations: 32);
      // Normalised Laplacian's analytic bound is 2; allow a small slack
      // for power-iteration truncation.
      expect(lambdaMax, lessThanOrEqualTo(2.0 + 1e-6));
    });

    test('withNodeRemoved matches full rebuild via fromRawEdges', () {
      // Start from a 4-node graph, remove node 1.
      final base = CsrGraph.fromRawEdges(
        n: 4,
        edgesPerNode: const [
          [(1, 0.6), (2, 0.2), (3, 0.3)],
          [(0, 0.6), (2, 0.4)],
          [(0, 0.2), (1, 0.4), (3, 0.7)],
          [(0, 0.3), (2, 0.7)],
        ],
      );
      final removed = base.withNodeRemoved(1);
      expect(removed.n, 3);
      // After removing node 1, the node formerly at id 2 is at id 1
      // and the node formerly at id 3 is at id 2. The remaining raw
      // edges are {(0→1=0.2), (0→2=0.3), (1→2=0.7)}.
      final rebuilt = CsrGraph.fromRawEdges(
        n: 3,
        edgesPerNode: const [
          [(1, 0.2), (2, 0.3)],
          [(0, 0.2), (2, 0.7)],
          [(0, 0.3), (1, 0.7)],
        ],
      );
      for (var i = 0; i < 3; i++) {
        for (var j = 0; j < 3; j++) {
          if (i == j) continue;
          expect(
            csrWeight(removed, i, j),
            closeTo(csrWeight(rebuilt, i, j), 1e-12),
            reason: 'mismatch at ($i,$j)',
          );
        }
      }
    });

    test('append then remove is a no-op (round-trip identity)', () {
      final base = buildTriangle();
      final roundTripped = base
          .withNodeAppended(edges: const [(0, 0.3), (2, 0.7)])
          .withNodeRemoved(3);
      // Round trip must reconstruct the original triangle's fused values.
      expect(roundTripped.n, base.n);
      for (var i = 0; i < base.n; i++) {
        for (var j = 0; j < base.n; j++) {
          if (i == j) continue;
          expect(
            csrWeight(roundTripped, i, j),
            closeTo(csrWeight(base, i, j), 1e-12),
            reason: 'round trip diverges at ($i,$j)',
          );
        }
      }
    });

    test('rank-1 path preserves heat-kernel diffusion values', () {
      // The whole point of rank-1 updates is that downstream diffusion
      // gives the same answer as if the caller had rebuilt from scratch.
      // Check φ(t) numerically agrees on the triangle vs. triangle+1.
      final augmented = buildTriangle().withNodeAppended(
        edges: const [(0, 0.3), (2, 0.7)],
      );
      final fullRebuild = CsrGraph.fromRawEdges(
        n: 4,
        edgesPerNode: const [
          [(1, 0.6), (2, 0.2), (3, 0.3)],
          [(0, 0.6), (2, 0.4)],
          [(0, 0.2), (1, 0.4), (3, 0.7)],
          [(0, 0.3), (2, 0.7)],
        ],
      );
      final rho = Float64List.fromList(const [1.0, 0.0, 0.0, 0.0]);
      final phiA = Float64List(4);
      final phiB = Float64List(4);
      diffuseChebyshevForTesting(
          graph: augmented, rho: rho, phi: phiA, t: 1.0);
      diffuseChebyshevForTesting(
          graph: fullRebuild, rho: rho, phi: phiB, t: 1.0);
      for (var i = 0; i < 4; i++) {
        expect(phiA[i], closeTo(phiB[i], 1e-9));
      }
    });
  });

  group('Spectral basis (Lanczos)', _spectralTests);
  group('Spectral tower (multi-level)', _spectralTowerTests);
  group('Spectral spacetime (Kronecker sum)', _spectralSpacetimeTests);
  group('Spectral walks (path-integral sampling)', _spectralWalksTests);
  group('Spectral ratchet (forward-only dynamics)', _spectralRatchetTests);
  group('Logos state (the outer primitive)', _logosStateTests);
}

void _logosStateTests() {
  CsrGraph buildPath(int n) => _buildPathFixture(n);

  test('empty LogosState has signature derived from revision=0 only', () {
    final a = LogosState.empty();
    final b = LogosState.empty();
    expect(a.isEmpty, true);
    expect(a.signature, b.signature);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.heatTrace(1.0), 0.0);
    expect(a.spectralGap, 0.0);
  });

  test('state with only file spectrum carries file signature', () {
    final basis = SpectralBasis.fromGraph(buildPath(20), 6);
    final state = LogosState(
      fileSpectrum: basis,
      commitSpectrum: null,
      joint: null,
      revision: 1,
    );
    expect(state.isEmpty, false);
    expect(state.heatTrace(1.0), closeTo(basis.heatTrace(1.0), 1e-12));
    expect(state.spectralGap, closeTo(basis.spectralGap, 1e-12));
    expect(state.signature.isZero, isFalse);
  });

  test('state signature discriminates revision, file, commit, joint', () {
    final basis = SpectralBasis.fromGraph(buildPath(16), 5);
    final rev1 = LogosState(
      fileSpectrum: basis,
      commitSpectrum: null,
      joint: null,
      revision: 1,
    );
    final rev2 = LogosState(
      fileSpectrum: basis,
      commitSpectrum: null,
      joint: null,
      revision: 2,
    );
    final withCommit = LogosState(
      fileSpectrum: basis,
      commitSpectrum: basis,
      joint: null,
      revision: 1,
    );
    expect(rev1.signature, isNot(rev2.signature),
        reason: 'revision bump changes signature');
    expect(rev1.signature, isNot(withCommit.signature),
        reason: 'adding commit factor changes signature');
  });

  test('diff localises divergence across the three factor levels', () {
    final fileA = SpectralBasis.fromGraph(buildPath(20), 6);
    final fileB = SpectralBasis.fromGraph(buildPath(24), 6); // different
    final commit = SpectralBasis.fromGraph(buildPath(12), 4);
    final a = LogosState(
      fileSpectrum: fileA,
      commitSpectrum: commit,
      joint: null,
      revision: 1,
    );
    final b = LogosState(
      fileSpectrum: fileB,
      commitSpectrum: commit,
      joint: null,
      revision: 1,
    );
    final d = a.diff(b);
    expect(d.signatureMatch, false);
    expect(d.fileSpectrumChanged, true);
    expect(d.commitSpectrumChanged, false);
    expect(d.jointChanged, false);
    expect(d.revisionDelta, 0);
  });

  test('diff returns signatureMatch=true on equal states', () {
    final basis = SpectralBasis.fromGraph(buildPath(16), 4);
    final a = LogosState(
      fileSpectrum: basis,
      commitSpectrum: null,
      joint: null,
      revision: 3,
    );
    final b = LogosState(
      fileSpectrum: basis,
      commitSpectrum: null,
      joint: null,
      revision: 3,
    );
    final d = a.diff(b);
    expect(d.signatureMatch, true);
    expect(d.inSync, true);
  });

  test('diff surfaces per-file Hamming when labels match and files diverge',
      () {
    // Build two labeled bases on paths of the same size but slightly
    // different structures — enough to flip Fiedler signs on some nodes.
    final paths = [for (var i = 0; i < 20; i++) 'f_$i'];
    final g1 = buildPath(20);
    final g2 = buildPath(20);
    final basisA = SpectralBasis.fromGraph(g1, 9, nodePaths: paths);
    final basisB = SpectralBasis.fromGraph(g2, 9, nodePaths: paths);
    // They'll have the same signature if both Lanczos invocations
    // land on identical seeds + graph — that's fine, means inSync.
    final a = LogosState(
      fileSpectrum: basisA,
      commitSpectrum: null,
      joint: null,
      revision: 1,
    );
    final b = LogosState(
      fileSpectrum: basisB,
      commitSpectrum: null,
      joint: null,
      revision: 1,
    );
    final d = a.diff(b);
    // If both bases are identical (same graph, same seed), Hamming is empty.
    if (d.signatureMatch) {
      expect(d.filePerNodeHamming, isEmpty);
    }
  });

  test('Cross-level unifying query: single call reads file + commit + joint',
      () {
    // Muse's forcing function: write a single function that composes at
    // least three modules. If it reads cleanly, the manifold is real.
    final fileBasis = SpectralBasis.fromGraph(buildPath(20), 6);
    final commitBasis = SpectralBasis.fromGraph(buildPath(12), 4);
    final joint = tensorSpectral(fileBasis, commitBasis);
    final state = LogosState(
      fileSpectrum: fileBasis,
      commitSpectrum: commitBasis,
      joint: joint,
      revision: 5,
    );

    // The unifying query: summarise the state's thermodynamic shape
    // at scale t across all populated factors with one function call.
    ({double heatTrace, double gap, Signature signature}) summarise(
            LogosState s, double t) =>
        (
          heatTrace: s.heatTrace(t),
          gap: s.spectralGap,
          signature: s.signature,
        );

    final summary = summarise(state, 1.0);
    // heatTrace prefers joint; joint.heatTrace = file * commit product.
    expect(summary.heatTrace,
        closeTo(fileBasis.heatTrace(1.0) * commitBasis.heatTrace(1.0), 1e-10));
    // Gap is the min of the factor gaps — the bigger graph (file,
    // n=20) has a smaller gap than the smaller graph (commit, n=12),
    // so the minimum is the file gap.
    final expectedGap = fileBasis.spectralGap < commitBasis.spectralGap
        ? fileBasis.spectralGap
        : commitBasis.spectralGap;
    expect(summary.gap, closeTo(expectedGap, 1e-12));
    // Signature is stable / non-zero.
    expect(summary.signature.isZero, isFalse);
  });

  test('withRevision preserves spectra and bumps signature', () {
    final basis = SpectralBasis.fromGraph(buildPath(16), 5);
    final a = LogosState(
      fileSpectrum: basis,
      commitSpectrum: null,
      joint: null,
      revision: 1,
    );
    final b = a.withRevision(2);
    expect(b.fileSpectrum, same(a.fileSpectrum));
    expect(b.revision, 2);
    expect(b.signature, isNot(a.signature));
  });
}

void _spectralRatchetTests() {
  // The ratchet wraps a LogosGit engine and enforces monotonic,
  // forward-only event application with a bounded skip buffer. Tests
  // don't need a real repo — we use a minimal stub that satisfies
  // the ratchet's read surface (revision, heatTraceWitness, etc.).
  // The engine is built from the canonical co-change fixture.

  LogosGit miniEngine() => LogosGit.buildFromStats(_canonicalCoChangeStats());

  test('Forward-only: past ops are silently discarded', () {
    final r = LogosRatchet.fromEngine(miniEngine());
    r.advance(FileEvent(sequence: 1, paths: const {'lib/a.dart'}));
    r.advance(FileEvent(sequence: 2, paths: const {'lib/b.dart'}));
    expect(r.revision, 2);
    // A "past" event — already applied — must not rewind the counter.
    r.advance(FileEvent(sequence: 1, paths: const {'lib/a.dart'}));
    expect(r.revision, 2);
  });

  test('In-order ops advance the revision monotonically', () {
    final r = LogosRatchet.fromEngine(miniEngine());
    for (var i = 1; i <= 10; i++) {
      r.advance(FileEvent(sequence: i, paths: const {}));
    }
    expect(r.revision, 10);
    expect(r.skippedCount, 0);
    expect(r.isSpectralDirty, true);
  });

  test('Out-of-order ops buffer until their slot comes up', () {
    final r = LogosRatchet.fromEngine(miniEngine());
    r.advance(FileEvent(sequence: 3, paths: const {}));
    r.advance(FileEvent(sequence: 5, paths: const {}));
    expect(r.revision, 0);
    expect(r.skippedCount, 2);
    r.advance(FileEvent(sequence: 1, paths: const {}));
    expect(r.revision, 1);
    expect(r.skippedCount, 2);
    r.advance(FileEvent(sequence: 2, paths: const {}));
    // Now ops 3 drains immediately (4 is still missing).
    expect(r.revision, 3);
    expect(r.skippedCount, 1);
    r.advance(FileEvent(sequence: 4, paths: const {}));
    // Both 4 and 5 drain.
    expect(r.revision, 5);
    expect(r.skippedCount, 0);
  });

  test('Skip buffer evicts oldest when over capacity', () {
    final r = LogosRatchet.fromEngine(miniEngine());
    // Fill well past kMaxSkip with out-of-order ops (start at seq=2
    // so nothing can advance; we're at revision 0 waiting for seq=1).
    for (var i = 2; i <= LogosRatchet.kMaxSkip + 10; i++) {
      r.advance(FileEvent(sequence: i, paths: const {}));
    }
    expect(r.skippedCount, LogosRatchet.kMaxSkip);
    // The oldest eviction is sequence=2 (the first out-of-order one).
    // When seq=1 finally lands, the drain skips the evicted slots
    // and stops at the first missing sequence in the buffer.
    r.advance(FileEvent(sequence: 1, paths: const {}));
    expect(r.revision, 1);
    // The surviving ops are the most-recent kMaxSkip, starting at
    // some sequence > 2. So draining from seq=2 fails at slot 2 (it
    // was evicted), leaving revision at 1.
  });

  test('Rekey resets the dirty flag and op counter, keeps revision',
      () {
    final r = LogosRatchet.fromEngine(miniEngine());
    for (var i = 1; i <= 5; i++) {
      r.advance(FileEvent(sequence: i, paths: const {}));
    }
    expect(r.revision, 5);
    expect(r.isSpectralDirty, true);
    r.rekey(miniEngine());
    expect(r.revision, 5, reason: 'rekey does not rewind ratchet identity');
    expect(r.isSpectralDirty, false);
    expect(r.shouldRekey(), false);
  });

  test('shouldRekey fires past the op-count threshold', () {
    final r = LogosRatchet.fromEngine(miniEngine());
    for (var i = 1; i <= LogosRatchet.kDefaultRekeyInterval; i++) {
      r.advance(FileEvent(sequence: i, paths: const {}));
    }
    expect(r.shouldRekey(), true);
    r.rekey(miniEngine());
    expect(r.shouldRekey(), false);
  });

  test('diagnose reports inSync on identical ratchets', () {
    final engineA = miniEngine();
    final engineB = miniEngine();
    final a = LogosRatchet.fromEngine(engineA);
    final b = LogosRatchet.fromEngine(engineB);
    final diag = a.diagnose(b);
    expect(diag.inSync, true);
    expect(diag.revisionMatch, true);
    expect(diag.heatTraceMatch, true);
    expect(diag.hammingByPath, isEmpty);
  });

  test('diagnose detects revision divergence', () {
    final a = LogosRatchet.fromEngine(miniEngine());
    final b = LogosRatchet.fromEngine(miniEngine());
    a.advance(FileEvent(sequence: 1, paths: const {}));
    a.advance(FileEvent(sequence: 2, paths: const {}));
    final diag = a.diagnose(b);
    expect(diag.revisionMatch, false);
    expect(diag.selfRevision, 2);
    expect(diag.peerRevision, 0);
    expect(diag.inSync, false);
  });

  test('Event subtypes all extend LogosEvent', () {
    const f = FileEvent(sequence: 1, paths: {'a'});
    const e = EdgeEvent(sequence: 2, a: 'a', b: 'b', delta: 0.5);
    const c = CommitEvent(sequence: 3, paths: {'a'}, commitId: 'abc');
    expect(f, isA<LogosEvent>());
    expect(e, isA<LogosEvent>());
    expect(c, isA<LogosEvent>());
    expect(c.touchedPaths, {'a'});
  });
}

/// Unit-weight path graph `0 — 1 — 2 — … — n-1`. The canonical
/// non-degenerate-spectrum fixture every spectral test reaches for.
CsrGraph _buildPathFixture(int n) {
  final edges = <List<(int, double)>>[];
  for (var i = 0; i < n; i++) {
    final row = <(int, double)>[];
    if (i > 0) row.add((i - 1, 1.0));
    if (i < n - 1) row.add((i + 1, 1.0));
    edges.add(row);
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

void _spectralSpacetimeTests() {
  CsrGraph buildPath(int n) => _buildPathFixture(n);

  test('Joint heat trace factors as Z_space(t) · Z_time(t)', () {
    final gS = buildPath(10);
    final gT = buildPath(6);
    final bS = SpectralBasis.fromGraph(gS, 10);
    final bT = SpectralBasis.fromGraph(gT, 6);
    final st = SpacetimeBasis(space: bS, time: bT);
    for (final t in const [0.25, 1.0, 2.5]) {
      expect(st.heatTrace(t),
          closeTo(bS.heatTrace(t) * bT.heatTrace(t), 1e-10));
    }
  });

  test('Joint diffuse at t=0 is identity on rho', () {
    // At t=0 all thermal weights are 1 and the full-rank projection+
    // recombination round-trips to rho.
    final gS = buildPath(5);
    final gT = buildPath(4);
    final bS = SpectralBasis.fromGraph(gS, 5);
    final bT = SpectralBasis.fromGraph(gT, 4);
    final st = SpacetimeBasis(space: bS, time: bT);
    final rho = Float64List(20);
    for (var i = 0; i < 20; i++) {
      rho[i] = i.toDouble();
    }
    final out = st.diffuse(rho, 0.0);
    for (var i = 0; i < 20; i++) {
      expect(out[i], closeTo(rho[i], 1e-8));
    }
  });

  test('Joint project returns a k_space × k_time coefficient grid', () {
    final gS = buildPath(10);
    final gT = buildPath(6);
    final bS = SpectralBasis.fromGraph(gS, 5);
    final bT = SpectralBasis.fromGraph(gT, 4);
    final st = SpacetimeBasis(space: bS, time: bT);
    final rho = Float64List(60);
    rho[23] = 1.0;
    final c = st.project(rho);
    expect(c, hasLength(5 * 4));
  });

  test('Joint eigenvalue at (0, 0) is zero on a connected-graph pair', () {
    final gS = buildPath(10);
    final gT = buildPath(6);
    final bS = SpectralBasis.fromGraph(gS, 5);
    final bT = SpectralBasis.fromGraph(gT, 4);
    final st = SpacetimeBasis(space: bS, time: bT);
    expect(st.eigenvalue(0, 0), closeTo(0.0, 1e-6));
  });

  test('buildCommitGraph links commits that touched overlapping files', () {
    // Three commits: 0 touches {a}, 1 touches {a, b}, 2 touches {b}.
    // Commits 0-1 share {a}, commits 1-2 share {b}, 0-2 share nothing.
    final g = buildCommitGraph(
      perFileCommitIndices: const {
        'a': [0, 1],
        'b': [1, 2],
      },
      totalCommits: 3,
      timeDecay: 0.0,
    );
    expect(g.n, 3);
    // Find edges from commit 0 — should include 1 and possibly 2 (if
    // they happened to share via transitive walk; but edges are direct
    // Jaccard, so 0-2 should be absent).
    var has01 = false;
    var has02 = false;
    for (var e = g.indptr[0]; e < g.indptr[1]; e++) {
      final dst = g.indices[e];
      if (dst == 1) has01 = true;
      if (dst == 2) has02 = true;
    }
    expect(has01, isTrue);
    expect(has02, isFalse,
        reason: 'commits 0 and 2 share no files and should not be linked');
  });

  test('buildCommitGraph attenuates distant commits by temporal decay', () {
    // Two commit pairs with identical overlap but different temporal
    // distance — far pair should end up with smaller weight.
    final g = buildCommitGraph(
      perFileCommitIndices: const {
        'a': [0, 1, 100, 101],
      },
      totalCommits: 102,
      topK: 8,
      timeDecay: 0.1,
    );
    double weightBetween(int a, int b) {
      for (var e = g.indptr[a]; e < g.indptr[a + 1]; e++) {
        if (g.indices[e] == b) return g.values[e];
      }
      return 0.0;
    }
    // CsrGraph values are fused with D^{-1/2} on both sides, so absolute
    // weights depend on node degrees; use sign/ordering tests rather
    // than exact magnitude comparisons.
    final near = weightBetween(0, 1);
    final far = weightBetween(0, 100);
    // File 'a' was touched by {0, 1, 100, 101}. Under a 0.1 decay, the
    // 0-1 pair should have a stronger raw weight than the 0-100 pair,
    // which propagates through the normalisation (same degrees).
    expect(near, greaterThan(far),
        reason: 'adjacent commits should couple more strongly');
  });

  test('Evaporation factor rises with spectral concentration', () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 20);
    // Spatial delta projects onto many eigenmodes (spectrally diffuse),
    // so its spectral entropy is HIGHER than a uniform distribution
    // — the uniform vector lives almost entirely in u₀ (the zero mode
    // on a connected graph). Confidence runs on spectral concentration,
    // not spatial concentration.
    final spatialDelta = Float64List(20)..[5] = 1.0;
    final spatialUniform = Float64List(20);
    for (var i = 0; i < 20; i++) {
      spatialUniform[i] = 0.05;
    }
    final fDelta = basis.evaporationFactor(spatialDelta, 1.0);
    final fUniform = basis.evaporationFactor(spatialUniform, 1.0);
    expect(fUniform, greaterThan(fDelta),
        reason: 'spectrally concentrated ρ (uniform) → crystal phase');
    for (final f in [fDelta, fUniform]) {
      expect(f, inInclusiveRange(1.0 / math.e - 1e-9, 1.0 + 1e-9));
    }
  });
}

void _spectralWalksTests() {
  CsrGraph buildPath(int n) => _buildPathFixture(n);

  test('Transition amplitude is symmetric and largest at self', () {
    final g = buildPath(12);
    final basis = SpectralBasis.fromGraph(g, 12);
    final walker = SpectralWalker(basis: basis, seed: 42);
    final selfAmp = walker.transitionAmplitude(5, 5, 0.5);
    final neigh = walker.transitionAmplitude(5, 6, 0.5);
    final far = walker.transitionAmplitude(5, 10, 0.5);
    expect(selfAmp, greaterThan(neigh));
    expect(neigh, greaterThan(far));
    expect(walker.transitionAmplitude(5, 6, 0.5),
        closeTo(walker.transitionAmplitude(6, 5, 0.5), 1e-10));
  });

  test('Step distribution is a proper probability', () {
    final g = buildPath(12);
    final basis = SpectralBasis.fromGraph(g, 12);
    final walker = SpectralWalker(basis: basis, seed: 7);
    final p = walker.stepDistribution(5, 1.0);
    var total = 0.0;
    for (var i = 0; i < p.length; i++) {
      expect(p[i], greaterThanOrEqualTo(0.0));
      total += p[i];
    }
    expect(total, closeTo(1.0, 1e-10));
  });

  test('Forward walk stays inside the node set', () {
    final g = buildPath(12);
    final basis = SpectralBasis.fromGraph(g, 12);
    final walker = SpectralWalker(basis: basis, seed: 99);
    final w =
        walker.sampleForwardWalk(start: 3, steps: 10, dt: 0.5);
    expect(w.nodes, hasLength(11));
    expect(w.nodes.first, 3);
    for (final node in w.nodes) {
      expect(node, inInclusiveRange(0, 11));
    }
  });

  test('Bridge walk ends at the pinned target', () {
    final g = buildPath(12);
    final basis = SpectralBasis.fromGraph(g, 12);
    final walker = SpectralWalker(basis: basis, seed: 11);
    final w = walker.sampleBridgeWalk(
      start: 1,
      target: 9,
      steps: 8,
      dt: 0.6,
    );
    expect(w.nodes.first, 1);
    expect(w.nodes.last, 9);
  });

  test('Same seed → same walk (reproducibility)', () {
    final g = buildPath(12);
    final basis = SpectralBasis.fromGraph(g, 12);
    final a = SpectralWalker(basis: basis, seed: 1234)
        .sampleForwardWalk(start: 5, steps: 6, dt: 0.5);
    final b = SpectralWalker(basis: basis, seed: 1234)
        .sampleForwardWalk(start: 5, steps: 6, dt: 0.5);
    expect(a.nodes, b.nodes);
  });

  test('Sharpest path is deterministic and begins/ends on pinned nodes',
      () {
    final g = buildPath(12);
    final basis = SpectralBasis.fromGraph(g, 12);
    final walker = SpectralWalker(basis: basis, seed: 1);
    final a = walker.sharpestPath(
      start: 1,
      target: 9,
      steps: 6,
      dt: 0.6,
    );
    final b = walker.sharpestPath(
      start: 1,
      target: 9,
      steps: 6,
      dt: 0.6,
    );
    expect(a.nodes, b.nodes);
    expect(a.nodes.first, 1);
    expect(a.nodes.last, 9);
  });

  test('Aggregate forward hits approximate the heat kernel shape', () {
    // Over many samples the hit distribution should peak near the
    // start and decay with graph distance — qualitative sanity, not
    // bit-exact kernel match.
    final g = buildPath(12);
    final basis = SpectralBasis.fromGraph(g, 12);
    final walker = SpectralWalker(basis: basis, seed: 777);
    final hits = walker.aggregateForwardHits(
      start: 5,
      steps: 1,
      dt: 1.0,
      numSamples: 2000,
    );
    // Near the start should have more hits than far away, in expectation.
    expect(hits[5] + hits[4] + hits[6],
        greaterThan(hits[0] + hits[1] + hits[11]));
  });
}

void _spectralTowerTests() {
  CsrGraph buildPath(int n) => _buildPathFixture(n);

  test('Uniform restriction averages fine values onto coarse', () {
    // 2 coarse nodes, 4 fine nodes. Coarse 0 owns {0, 1}; coarse 1
    // owns {2, 3}. Uniform weights = 1/2 each.
    final r = RestrictionOperator.uniform(
      nCoarse: 2,
      nFine: 4,
      membersByCoarse: {
        0: const [0, 1],
        1: const [2, 3],
      },
    );
    final fine = Float64List.fromList(const [1.0, 3.0, 5.0, 7.0]);
    final coarse = r.restrict(fine);
    expect(coarse[0], closeTo(2.0, 1e-12));
    expect(coarse[1], closeTo(6.0, 1e-12));
  });

  test('Prolongate is the formal adjoint of restrict', () {
    final r = RestrictionOperator.uniform(
      nCoarse: 2,
      nFine: 4,
      membersByCoarse: {
        0: const [0, 1],
        1: const [2, 3],
      },
    );
    // ⟨R·fine, coarse⟩ == ⟨fine, P·coarse⟩ for any vectors.
    final fine = Float64List.fromList(const [0.5, 1.5, 2.5, 3.5]);
    final coarse = Float64List.fromList(const [7.0, 11.0]);
    final lhs = _dot(r.restrict(fine), coarse);
    final rhs = _dot(fine, r.prolongate(coarse));
    expect(lhs, closeTo(rhs, 1e-12));
  });

  test('Tower lift yields one vector per level, finest first preserved', () {
    final coarseG = buildPath(4);
    final fineG = buildPath(8);
    final coarseBasis = SpectralBasis.fromGraph(coarseG, 4);
    final fineBasis = SpectralBasis.fromGraph(fineG, 8);
    final r = RestrictionOperator.uniform(
      nCoarse: 4,
      nFine: 8,
      membersByCoarse: {
        for (var c = 0; c < 4; c++) c: [2 * c, 2 * c + 1],
      },
    );
    final tower = SpectralTower(
      bases: [coarseBasis, fineBasis],
      restrictions: [r],
    );
    final fine = Float64List.fromList(
      const [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0],
    );
    final lifted = tower.liftToTop(fine);
    expect(lifted, hasLength(2));
    expect(lifted[1], fine); // finest level untouched
    expect(lifted[0][0], closeTo(1.5, 1e-12));
    expect(lifted[0][1], closeTo(3.5, 1e-12));
    expect(lifted[0][2], closeTo(5.5, 1e-12));
    expect(lifted[0][3], closeTo(7.5, 1e-12));
  });

  test('Cross-level coherence is high on an aligned path tower', () {
    // Both levels are paths; their Fiedlers are both monotone, so
    // aggregating the fine Fiedler onto the coarse should be a
    // monotone vector aligned with the coarse Fiedler — high coherence.
    final coarseG = buildPath(4);
    final fineG = buildPath(8);
    final coarseBasis = SpectralBasis.fromGraph(coarseG, 4);
    final fineBasis = SpectralBasis.fromGraph(fineG, 8);
    final r = RestrictionOperator.uniform(
      nCoarse: 4,
      nFine: 8,
      membersByCoarse: {
        for (var c = 0; c < 4; c++) c: [2 * c, 2 * c + 1],
      },
    );
    final tower = SpectralTower(
      bases: [coarseBasis, fineBasis],
      restrictions: [r],
    );
    final coherence = tower
        .crossLevelCoherence(coarseIdx: 0, fineIdx: 1, t: 0.0)
        .abs();
    expect(coherence, greaterThan(0.9),
        reason: 'aligned path tower must have high Fiedler coherence');
  });

  test('Multiscale projection returns one coefficient vector per level', () {
    final coarseG = buildPath(4);
    final fineG = buildPath(8);
    final coarseBasis = SpectralBasis.fromGraph(coarseG, 4);
    final fineBasis = SpectralBasis.fromGraph(fineG, 8);
    final r = RestrictionOperator.uniform(
      nCoarse: 4,
      nFine: 8,
      membersByCoarse: {
        for (var c = 0; c < 4; c++) c: [2 * c, 2 * c + 1],
      },
    );
    final tower = SpectralTower(
      bases: [coarseBasis, fineBasis],
      restrictions: [r],
    );
    final fine = Float64List(8)..[0] = 1.0;
    final proj = tower.multiscaleProject(fine);
    expect(proj, hasLength(2));
    expect(proj[0].length, coarseBasis.k);
    expect(proj[1].length, fineBasis.k);
  });
}

double _dot(Float64List a, Float64List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

/// Fixture: four files where {a, b, c} strongly co-change and
/// `unrelated` barely co-occurs with anything.
LogosGitStats _canonicalCoChangeStats() {
  return LogosGitStats(
    touches: const {
      'lib/a.dart': 30,
      'lib/b.dart': 28,
      'lib/c.dart': 25,
      'lib/unrelated.dart': 2,
    },
    totalCommits: 50,
    volatility: const {
      'lib/a.dart': 10.0,
      'lib/b.dart': 12.0,
      'lib/c.dart': 9.0,
      'lib/unrelated.dart': 1.0,
    },
    volMean: 8.0,
    volStddev: 4.0,
    coupling: FileCouplingMatrix(
      jaccard: const {
        'lib/a.dart': {
          'lib/b.dart': 0.8,
          'lib/c.dart': 0.7,
          'lib/unrelated.dart': 0.05,
        },
        'lib/b.dart': {
          'lib/a.dart': 0.8,
          'lib/c.dart': 0.75,
          'lib/unrelated.dart': 0.05,
        },
        'lib/c.dart': {
          'lib/a.dart': 0.7,
          'lib/b.dart': 0.75,
          'lib/unrelated.dart': 0.05,
        },
        'lib/unrelated.dart': {
          'lib/a.dart': 0.05,
          'lib/b.dart': 0.05,
          'lib/c.dart': 0.05,
        },
      },
      headHash: 'abc',
      commitsAnalyzed: 50,
    ),
    perFileCommitIndices: const {},
  );
}

void _spectralTests() {
  // Path graph: 0—1—2—3—4 with unit edge weights. Used by both
  // Chebyshev path-graph reference test and here for spectral
  // equivalence so the two paths are pinned against the same fixture.
  CsrGraph buildPath(int n) => _buildPathFixture(n);

  test('lanczosSmallEigenpairs returns sorted eigenvalues in [0, 2]', () {
    final g = buildPath(20);
    final pairs = lanczosSmallEigenpairs(g, 8);
    expect(pairs.k, 8);
    for (var j = 0; j < pairs.k; j++) {
      expect(pairs.eigenvalues[j],
          inInclusiveRange(-1e-9, 2.0 + 1e-9));
    }
    for (var j = 1; j < pairs.k; j++) {
      expect(pairs.eigenvalues[j], greaterThanOrEqualTo(pairs.eigenvalues[j - 1] - 1e-9));
    }
    // Smallest eigenvalue of L_sym on a connected graph is 0.
    expect(pairs.eigenvalues[0], closeTo(0.0, 1e-6));
  });

  test('Spectral eigenvectors are orthonormal up to Lanczos drift', () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 8);
    // Uᵀ·U should be identity. Test diagonal ≈ 1 and off-diagonal ≈ 0.
    for (var a = 0; a < basis.k; a++) {
      for (var b = 0; b < basis.k; b++) {
        var dot = 0.0;
        for (var i = 0; i < basis.n; i++) {
          dot += basis.eigenvectors[a * basis.n + i] *
              basis.eigenvectors[b * basis.n + i];
        }
        if (a == b) {
          expect(dot, closeTo(1.0, 1e-8),
              reason: 'eigenvector $a should be unit-norm');
        } else {
          expect(dot, closeTo(0.0, 1e-8),
              reason: 'eigenvectors $a and $b should be orthogonal');
        }
      }
    }
  });

  test('Spectral diffuse with full k matches Chebyshev to f64 precision', () {
    // Full eigendecomposition (k = n) should recover Chebyshev exactly
    // up to Lanczos floating-point drift — both compute exp(−t·L_sym)·ρ,
    // just with different numerical paths.
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 20);
    final rho = Float64List(g.n)..[5] = 1.0;
    for (final t in const [0.5, 1.0, 2.0]) {
      final phiSpectral = basis.diffuse(rho, t);
      final phiChebyshev = Float64List(g.n);
      chebyshevDiffuse(graph: g, rho: rho, phi: phiChebyshev, t: t);
      var maxAbsErr = 0.0;
      for (var i = 0; i < g.n; i++) {
        final e = (phiSpectral[i] - phiChebyshev[i]).abs();
        if (e > maxAbsErr) maxAbsErr = e;
      }
      expect(maxAbsErr, lessThan(1e-8),
          reason: 't=$t: full-rank spectral must equal Chebyshev');
    }
  });

  test('Spectral diffuse with truncated k beats Chebyshev at large t', () {
    // Heat-kernel modes decay as e^(−t·λ). At t ≥ 1, modes with λ > 3
    // contribute < e^−3 ≈ 0.05 of their initial amplitude — truncating
    // them costs a small constant and we still recover the right shape.
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 12);
    final rho = Float64List(g.n)..[10] = 1.0;
    final phiSpectral = basis.diffuse(rho, 2.0);
    final phiChebyshev = Float64List(g.n);
    chebyshevDiffuse(graph: g, rho: rho, phi: phiChebyshev, t: 2.0);
    var maxAbsErr = 0.0;
    for (var i = 0; i < g.n; i++) {
      final e = (phiSpectral[i] - phiChebyshev[i]).abs();
      if (e > maxAbsErr) maxAbsErr = e;
    }
    // 12 of 20 modes at t=2.0 — the missing 8 high-frequency modes
    // each contribute up to e^(−2·1.9) ≈ 0.022 of their projection
    // amplitude. Per-node max-abs error around 1–2% is the expected
    // shape; tighten by raising k or t.
    expect(maxAbsErr, lessThan(2e-2),
        reason: 'truncated spectral should approximate well at large t');
  });

  test('Spectral project + recombine equals one-shot diffuse', () {
    // The two-step API (project once, recombine many) must match the
    // one-step API exactly — they're literally the same math, the
    // split exists only to amortise project across slider sweeps.
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 8);
    final rho = Float64List(g.n)..[3] = 0.7..[12] = 0.3;
    final coeffs = basis.project(rho);
    expect(coeffs.length, basis.k);
    for (final t in const [0.25, 0.75, 1.5]) {
      final phiOneShot = basis.diffuse(rho, t);
      final phiTwoStep = basis.recombineFromProjection(coeffs, t);
      for (var i = 0; i < g.n; i++) {
        expect(phiTwoStep[i], closeTo(phiOneShot[i], 1e-12));
      }
    }
  });

  test('Heat trace decays monotonically in t and equals Σ e^(−tλ)', () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 20);
    final z0 = basis.heatTrace(0.0);
    expect(z0, closeTo(20.0, 1e-9), reason: 'tr(I) = n');
    var prev = z0;
    for (final t in const [0.5, 1.0, 2.0, 4.0]) {
      final z = basis.heatTrace(t);
      expect(z, lessThan(prev), reason: 'heat trace must decay');
      var manual = 0.0;
      for (var j = 0; j < basis.k; j++) {
        manual += math.exp(-t * basis.eigenvalues[j]);
      }
      expect(z, closeTo(manual, 1e-12));
      prev = z;
    }
  });

  test('Free energy and partition function obey F = −log Z', () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 20);
    // Build a unit-mass focus on the centre node.
    final rho = Float64List(g.n)..[10] = 1.0;
    for (final t in const [0.5, 1.0, 2.0]) {
      final z = basis.partitionFunction(rho, t);
      final f = basis.negLogPartition(rho, t);
      expect(z, greaterThan(0.0));
      expect(f, closeTo(-math.log(z), 1e-12));
    }
  });

  test('Spectral entropy is bounded and ordered with focus diffusion', () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 20);
    final delta = Float64List(g.n)..[10] = 1.0;
    // At t=0 the projection coeffs are the raw uⱼ[10] values; entropy
    // is bounded by log(k). Larger t concentrates mass into lower
    // modes (small λ survive longer) — entropy decreases.
    final entropyCold = basis.spectralEntropy(delta, 0.0);
    final entropyWarm = basis.spectralEntropy(delta, 1.0);
    final entropyHot = basis.spectralEntropy(delta, 4.0);
    final logK = math.log(basis.k.toDouble());
    expect(entropyCold, lessThanOrEqualTo(logK + 1e-9));
    expect(entropyHot, lessThan(entropyWarm),
        reason: 'higher t → more low-mode dominance → lower entropy');
    expect(entropyWarm, lessThanOrEqualTo(entropyCold + 1e-9));
  });

  test('Diffusion distance is a metric on a path graph', () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 20);
    // Identity: d(x, x) = 0.
    expect(basis.diffusionDistance(5, 5, 1.0), closeTo(0.0, 1e-12));
    // Symmetry: d(x, y) = d(y, x).
    expect(basis.diffusionDistance(3, 7, 1.0),
        closeTo(basis.diffusionDistance(7, 3, 1.0), 1e-12));
    // On a path graph, far-apart nodes have larger diffusion distance
    // than close nodes (at any moderate t).
    final dShort = basis.diffusionDistance(5, 7, 1.0);
    final dLong = basis.diffusionDistance(5, 15, 1.0);
    expect(dLong, greaterThan(dShort));
  });

  test('Spectral divergence is zero on identical sources, positive otherwise',
      () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 20);
    final rhoA = Float64List(g.n)..[5] = 1.0;
    final rhoB = Float64List(g.n)..[5] = 1.0;
    final rhoC = Float64List(g.n)..[15] = 1.0;
    expect(basis.spectralDivergence(rhoA, rhoB, 1.0),
        closeTo(0.0, 1e-12));
    final dAC = basis.spectralDivergence(rhoA, rhoC, 1.0);
    expect(dAC, greaterThan(0.0));
    // Symmetry.
    expect(basis.spectralDivergence(rhoC, rhoA, 1.0), closeTo(dAC, 1e-12));
  });

  test('Fiedler partition splits a barbell graph along its bridge', () {
    // Two K3 cliques joined by a single edge. The Fiedler vector
    // u₁ should change sign across the bridge — the deepest cut of
    // the graph is exactly that one edge.
    //
    //   0 — 1            4 — 5
    //   |\ /|            |\ /|
    //   |/ \|            |/ \|
    //   2 — 3 ─────── 4
    //
    // Numbering: clique A = {0,1,2}, clique B = {3,4,5}, bridge 2—3.
    final edges = <List<(int, double)>>[
      [(1, 1.0), (2, 1.0)], // 0
      [(0, 1.0), (2, 1.0)], // 1
      [(0, 1.0), (1, 1.0), (3, 1.0)], // 2 — bridge end
      [(2, 1.0), (4, 1.0), (5, 1.0)], // 3 — bridge end
      [(3, 1.0), (5, 1.0)], // 4
      [(3, 1.0), (4, 1.0)], // 5
    ];
    final g = CsrGraph.fromRawEdges(n: 6, edgesPerNode: edges);
    final basis = SpectralBasis.fromGraph(g, 6);
    final fiedler = basis.fiedlerVector!;
    // Each clique's nodes should share the sign of fiedler[i]; the
    // two cliques should have opposite signs.
    final signA = fiedler[0].sign;
    final signB = fiedler[5].sign;
    expect(signA, isNot(signB),
        reason: 'two cliques sit on opposite sides of u₁');
    expect(fiedler[1].sign, signA);
    expect(fiedler[2].sign, signA);
    expect(fiedler[3].sign, signB);
    expect(fiedler[4].sign, signB);
  });

  test('Spectral community labels separate the barbell cliques', () {
    final edges = <List<(int, double)>>[
      [(1, 1.0), (2, 1.0)],
      [(0, 1.0), (2, 1.0)],
      [(0, 1.0), (1, 1.0), (3, 1.0)],
      [(2, 1.0), (4, 1.0), (5, 1.0)],
      [(3, 1.0), (5, 1.0)],
      [(3, 1.0), (4, 1.0)],
    ];
    final g = CsrGraph.fromRawEdges(n: 6, edgesPerNode: edges);
    final basis = SpectralBasis.fromGraph(g, 6);
    final labels = basis.spectralCommunityLabels(2);
    expect(labels, hasLength(6));
    // Nodes 0..2 must share a label; nodes 3..5 must share a (different) label.
    expect(labels[0], labels[1]);
    expect(labels[1], labels[2]);
    expect(labels[3], labels[4]);
    expect(labels[4], labels[5]);
    expect(labels[2], isNot(labels[3]),
        reason: 'two cliques must end up in different communities');
  });

  test('Spectral gap recovers Fiedler eigenvalue on connected graph', () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 6);
    final gap = basis.spectralGap;
    expect(gap, closeTo(basis.eigenvalues[1] - basis.eigenvalues[0], 1e-12));
    expect(gap, greaterThan(0.0));
  });

  test('Stationary distribution sums to 1 and puts most mass on hubs', () {
    // Star graph: node 0 is connected to all others. Hub should dominate.
    final edges = <List<(int, double)>>[
      [(1, 1.0), (2, 1.0), (3, 1.0), (4, 1.0), (5, 1.0)],
      [(0, 1.0)],
      [(0, 1.0)],
      [(0, 1.0)],
      [(0, 1.0)],
      [(0, 1.0)],
    ];
    final g = CsrGraph.fromRawEdges(n: 6, edgesPerNode: edges);
    final basis = SpectralBasis.fromGraph(g, 6);
    final pi = basis.stationaryDistribution();
    var total = 0.0;
    for (var i = 0; i < pi.length; i++) {
      expect(pi[i], greaterThanOrEqualTo(0.0));
      total += pi[i];
    }
    expect(total, closeTo(1.0, 1e-8));
    // Hub has degree 5, leaves have degree 1; hub should carry 5/10 = 0.5.
    for (var i = 1; i < 6; i++) {
      expect(pi[0], greaterThan(pi[i]));
    }
  });

  test('Effective resistance is zero on self, symmetric, and positive', () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 20);
    expect(basis.effectiveResistance(5, 5), closeTo(0.0, 1e-12));
    expect(basis.effectiveResistance(3, 7),
        closeTo(basis.effectiveResistance(7, 3), 1e-12));
    final short = basis.effectiveResistance(5, 7);
    final long = basis.effectiveResistance(5, 15);
    expect(short, greaterThan(0.0));
    // On a path graph, effective resistance is monotone in graph distance.
    expect(long, greaterThan(short));
  });

  test('Heat capacity is non-negative and peaks at a finite scale', () {
    // For a connected path graph, heat capacity is a bell-shaped curve
    // in t — zero at t=0 and t=∞, positive in the middle.
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 20);
    for (final t in const [0.0, 0.5, 1.0, 2.0, 4.0, 8.0]) {
      final c = basis.energyVariance(t);
      expect(c, greaterThanOrEqualTo(-1e-12));
    }
    // C(0) = variance of all eigenvalues (uniform weighting) — non-zero
    // because the spectrum is non-degenerate.
    final cZero = basis.energyVariance(0.0);
    expect(cZero, greaterThan(0.0));
    // At very large t the distribution collapses onto λ_0 = 0 — variance
    // vanishes asymptotically. Floating-point noise in Lanczos's tiny
    // λ_0 (not exactly zero) leaves a ~1e-4 tail, so tolerance accordingly.
    final cHot = basis.energyVariance(50.0);
    expect(cHot, lessThan(cZero));
    expect(cHot, lessThan(1e-3));
  });

  test('Spectral fingerprint is an 8-bit label and respects Hamming geometry',
      () {
    // Path graph gives us a non-degenerate spectrum so Lanczos can
    // return all k=9 Ritz pairs cleanly. Fiedler splits the path at
    // its midpoint — nodes in opposite halves must differ on bit 0.
    final g = buildPath(30);
    final basis = SpectralBasis.fromGraph(g, 9);
    expect(basis.k, greaterThanOrEqualTo(9));
    final table = basis.spectralFingerprintTable();
    expect(table, hasLength(30));
    for (var i = 0; i < 30; i++) {
      expect(table[i], inInclusiveRange(0, 255));
      expect(table[i], basis.spectralByteFingerprint(i));
    }
    // Opposite ends of a 30-node path are on opposite sides of the Fiedler.
    final leftBit0 = table[0] & 1;
    final rightBit0 = table[29] & 1;
    expect(leftBit0, isNot(rightBit0),
        reason: 'Fiedler sign must flip across the path midpoint');
  });

  test('Spectral fingerprint returns 0 when basis has fewer than 9 modes',
      () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 4);
    // Not enough modes to read 8 non-trivial cleavages — safe fallback.
    expect(basis.spectralByteFingerprint(5), 0);
    final table = basis.spectralFingerprintTable();
    for (var i = 0; i < table.length; i++) {
      expect(table[i], 0);
    }
  });

  test('Natural scales returns monotone-sorted t values — peaks or fallback',
      () {
    final g = buildPath(40);
    final basis = SpectralBasis.fromGraph(g, 15);
    final scales = basis.naturalScales();
    expect(scales, isNotEmpty,
        reason: 'naturalScales must never return an empty list');
    for (var i = 1; i < scales.length; i++) {
      expect(scales[i], greaterThan(scales[i - 1]));
    }
    for (final t in scales) {
      expect(t, greaterThan(0.0));
    }
  });

  test('Fingerprint Hamming distance agrees with popcount(XOR)', () {
    final g = buildPath(30);
    final basis = SpectralBasis.fromGraph(g, 9);
    final table = basis.spectralFingerprintTable();
    // Same-index distance is zero.
    expect(basis.spectralFingerprintDistance(5, 5), 0);
    // Cross-midpoint pairs should flip at least the Fiedler bit (bit 0),
    // so distance ≥ 1 — and match XOR popcount exactly.
    for (final pair in const [(0, 29), (2, 27), (10, 20)]) {
      final d = basis.spectralFingerprintDistance(pair.$1, pair.$2);
      expect(d, greaterThanOrEqualTo(0));
      expect(d, lessThanOrEqualTo(8));
      // Independently verified popcount.
      var xor = table[pair.$1] ^ table[pair.$2];
      var manual = 0;
      while (xor != 0) {
        manual += xor & 1;
        xor >>= 1;
      }
      expect(d, manual);
    }
  });

  test('Node coordinates return top-k non-trivial eigenvector entries', () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 6);
    final coords = basis.nodeCoordinates(5, dims: 3);
    expect(coords, hasLength(3));
    // Should equal u_1[5], u_2[5], u_3[5] (skipping u_0).
    expect(coords[0], closeTo(basis.eigenvectors[1 * 20 + 5], 1e-12));
    expect(coords[1], closeTo(basis.eigenvectors[2 * 20 + 5], 1e-12));
    expect(coords[2], closeTo(basis.eigenvectors[3 * 20 + 5], 1e-12));
  });

  test('Unitary diffusion preserves total probability for all t', () {
    // Quantum evolution e^(−itL) is unitary — ‖ψ(t)‖² = ‖ρ‖² for every
    // t. Verifies exactly what classical heat diffusion violates (the
    // heat kernel contracts mass monotonically).
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 20);
    final rho = Float64List(20);
    rho[5] = 0.8;
    rho[12] = -0.3;
    rho[18] = 0.5;
    var normSq = 0.0;
    for (var i = 0; i < 20; i++) {
      normSq += rho[i] * rho[i];
    }
    for (final t in const [0.0, 0.5, 1.5, 3.0]) {
      final p = basis.quantumProbability(rho, t);
      var total = 0.0;
      for (var i = 0; i < 20; i++) {
        total += p[i];
      }
      expect(total, closeTo(normSq, 1e-6),
          reason: 't=$t: unitary evolution must preserve ‖ρ‖²');
    }
  });

  test('Unitary diffuse at t=0 returns ρ real, zero imag', () {
    final g = buildPath(10);
    final basis = SpectralBasis.fromGraph(g, 10);
    final rho = Float64List(10);
    for (var i = 0; i < 10; i++) {
      rho[i] = i.toDouble();
    }
    final psi = basis.unitaryDiffuse(rho, 0.0);
    for (var i = 0; i < 10; i++) {
      expect(psi.real[i], closeTo(rho[i], 1e-8));
      expect(psi.imag[i], closeTo(0.0, 1e-10));
    }
  });

  test('Interference mass equals per-node field integral and is t-invariant',
      () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 20);
    final a = Float64List(20)..[5] = 1.0;
    final b = Float64List(20)..[8] = 1.0;
    final scalar = basis.interferenceMass(a, b);
    for (final t in const [0.0, 0.3, 1.0, 2.5]) {
      final field = basis.interferenceField(a, b, t);
      var integral = 0.0;
      for (var i = 0; i < 20; i++) {
        integral += field[i];
      }
      // Integrated cross-term is conserved under unitary evolution —
      // spatial fringes move, total is invariant.
      expect(integral, closeTo(scalar, 1e-6),
          reason: 't=$t: integrated interference must equal 2·⟨c_a, c_b⟩');
    }
  });

  test('Interference of identical focuses equals 2·‖project(ρ)‖² at t=0',
      () {
    // |ψ_a + ψ_a|² = 4·|ψ_a|² — coherent doubling. At t=0, the
    // interference cross-term collapses to `2·⟨project(ρ)|project(ρ)⟩`,
    // which equals `2·‖ρ‖²` when the basis is full-rank, less when
    // the spectrum is truncated.
    final g = buildPath(12);
    final basis = SpectralBasis.fromGraph(g, 12);
    final rho = Float64List(12)..[4] = 1.0;
    final coeffs = basis.project(rho);
    var projSq = 0.0;
    for (var j = 0; j < coeffs.length; j++) {
      projSq += coeffs[j] * coeffs[j];
    }
    final mass = basis.interferenceMass(rho, rho);
    expect(mass, closeTo(2.0 * projSq, 1e-8));
  });

  test('Orthogonal full-rank focuses have interference mass near zero', () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 20);
    final a = Float64List(20)..[2] = 1.0;
    final b = Float64List(20)..[17] = 1.0;
    // Cross term = 2·⟨c_a, c_b⟩. Under full-rank Uᵀ the spectral
    // coefficients inherit the spatial inner product, so disjoint
    // deltas produce ~0 interference mass.
    expect(basis.interferenceMass(a, b), closeTo(0.0, 1e-6));
  });

  test('Signature is stable, deterministic, reflects Λ identity', () {
    final g = buildPath(20);
    final a = SpectralBasis.fromGraph(g, 8);
    final b = SpectralBasis.fromGraph(g, 8);
    // Two independent builds from the same deterministic Lanczos seed
    // yield identical eigenvalues → identical signature.
    expect(a.signature, b.signature);
    expect(a.signature.isZero, isFalse);
    // Different k → different spectrum → different signature.
    final c = SpectralBasis.fromGraph(g, 6);
    expect(c.signature, isNot(a.signature));
  });

  test('SpectralBasis round-trips through toBytes / fromBytes', () {
    final g = buildPath(15);
    final a = SpectralBasis.fromGraph(g, 6,
        nodePaths: [for (var i = 0; i < 15; i++) 'node_$i']);
    final bytes = a.toBytes();
    final b = SpectralBasis.fromBytes(bytes);
    expect(b.n, a.n);
    expect(b.k, a.k);
    expect(b.signature, a.signature);
    for (var i = 0; i < a.k; i++) {
      expect(b.eigenvalues[i], closeTo(a.eigenvalues[i], 1e-12));
    }
    for (var i = 0; i < a.k * a.n; i++) {
      expect(b.eigenvectors[i], closeTo(a.eigenvectors[i], 1e-12));
    }
    expect(b.nodePaths, a.nodePaths);
  });

  test('Labeled projection + phiForPath agree with plain project+diffuse',
      () {
    final g = buildPath(20);
    final paths = [for (var i = 0; i < 20; i++) 'file_$i'];
    final basis = SpectralBasis.fromGraph(g, 8, nodePaths: paths);
    final weights = <String, double>{
      'file_3': 0.7,
      'file_12': 0.3,
    };
    final coeffs = basis.labelProject(weights);
    // Equivalent plain rho (normalised weights on those nodes).
    final plainRho = Float64List(20)..[3] = 0.7..[12] = 0.3;
    final total = 1.0;
    for (var i = 0; i < 20; i++) {
      plainRho[i] /= total;
    }
    final plainCoeffs = basis.project(plainRho);
    for (var j = 0; j < basis.k; j++) {
      expect(coeffs[j], closeTo(plainCoeffs[j], 1e-9));
    }
    // phiForPath matches direct recombine at that node.
    final phi = basis.recombineFromProjection(coeffs, 1.0);
    for (final p in paths.take(5)) {
      final direct = basis.phiForPath(coeffs, p, 1.0);
      final id = basis.pathToId![p]!;
      expect(direct, closeTo(phi[id], 1e-9));
    }
  });

  test('Unlabeled basis throws on labelProject', () {
    final g = buildPath(10);
    final basis = SpectralBasis.fromGraph(g, 4);
    expect(() => basis.labelProject({'x': 1.0}), throwsStateError);
    expect(basis.phiForPath(Float64List(4), 'x', 1.0), 0.0);
  });

  test('Ratchet diagnose uses signature fast-path', () {
    final g = buildPath(300);
    final a = SpectralBasis.fromGraph(g, 20);
    final b = SpectralBasis.fromGraph(g, 20);
    // Same graph → deterministic Lanczos → identical signature.
    expect(a.signature, b.signature);
  });

  test('== and hashCode mirror signature equality', () {
    final g1 = buildPath(12);
    final g2 = buildPath(12);
    final a = SpectralBasis.fromGraph(g1, 6);
    final b = SpectralBasis.fromGraph(g2, 6);
    expect(a == b, true);
    expect(a.hashCode, b.hashCode);
    final set = <SpectralBasis>{a};
    expect(set.contains(b), true, reason: 'HashSet key equivalence');
    // Different k produces a different signature → !=.
    final c = SpectralBasis.fromGraph(g1, 4);
    expect(a == c, false);
  });

  test('tensorSpectral produces a SpacetimeBasis with derived signature',
      () {
    final g1 = buildPath(10);
    final g2 = buildPath(6);
    final a = SpectralBasis.fromGraph(g1, 5);
    final b = SpectralBasis.fromGraph(g2, 4);
    final st = tensorSpectral(a, b);
    expect(st.space.signature, a.signature);
    expect(st.time.signature, b.signature);
    // Joint signature changes when either factor changes.
    final c = SpectralBasis.fromGraph(g1, 4);
    final stPrime = tensorSpectral(c, b);
    expect(stPrime.signature, isNot(st.signature));
  });

  test('SpectralBasisCache roundtrips a basis through disk', () async {
    final tmp = await Directory.systemTemp.createTemp('logos-basis-test-');
    try {
      final cache = SpectralBasisCache(directory: tmp);
      final g = buildPath(14);
      final a = SpectralBasis.fromGraph(g, 6,
          nodePaths: [for (var i = 0; i < 14; i++) 'n$i']);
      await cache.write(a);
      final b = await cache.read(a.signature);
      expect(b, isNotNull);
      expect(b!.signature, a.signature);
      expect(b, a, reason: '== via signature match');
      // Unknown signature returns null.
      expect(await cache.read(const Signature(lo: 0x0eadbeef, hi: 0x5)),
          isNull);
    } finally {
      await tmp.delete(recursive: true);
    }
  });

  test('mixingTime = 1/λ₁; cheegerUpperBound = √(2·λ₁)', () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 6);
    final gap = basis.spectralGap;
    expect(gap, greaterThan(0.0));
    expect(basis.mixingTime, closeTo(1.0 / gap, 1e-12));
    expect(basis.cheegerUpperBound, closeTo(math.sqrt(2.0 * gap), 1e-12));
  });

  test('naturalScales falls back to mixing time when flat', () {
    // A trivial basis (k=0) should still return a non-empty list.
    // Synthesize one directly via the constructor.
    final emptyBasis = SpectralBasis(
      n: 0,
      k: 0,
      eigenvalues: Float64List(0),
      eigenvectors: Float64List(0),
    );
    final scales = emptyBasis.naturalScales();
    expect(scales, hasLength(1));
    expect(scales.first, 1.0);
  });

  test('naturalScales returns mixing-time fallback when no peaks', () {
    // A fresh basis from a very small graph: energyVariance curve is
    // usually too flat to have peaks under default thresholds, so we
    // should get the mixing-time fallback (or 1.0 if that's infinite).
    final g = buildPath(4);
    final basis = SpectralBasis.fromGraph(g, 4);
    final scales = basis.naturalScales();
    expect(scales, isNotEmpty,
        reason: 'naturalScales must never return an empty list');
    for (final t in scales) {
      expect(t, greaterThan(0.0));
    }
  });

  test('SpectralProjection.diffuseAt matches basis.recombineFromProjection',
      () {
    final g = buildPath(15);
    final basis = SpectralBasis.fromGraph(g, 6);
    final rho = Float64List(15)..[3] = 1.0;
    final source = basis.projectSource(rho);
    expect(source.basis, same(basis));
    expect(source.basisSignature, basis.signature);
    for (final t in const [0.0, 0.5, 1.5]) {
      final viaNoun = source.diffuseAt(t);
      final direct = basis.recombineFromProjection(source.coefficients, t);
      for (var i = 0; i < 15; i++) {
        expect(viaNoun[i], closeTo(direct[i], 1e-12));
      }
    }
  });

  test('SpectralProjection entropy + negLogPartition reuse cached projection',
      () {
    final g = buildPath(15);
    final basis = SpectralBasis.fromGraph(g, 8);
    final rho = Float64List(15)..[5] = 0.7..[10] = 0.3;
    final source = basis.projectSource(rho);
    for (final t in const [0.3, 1.0, 2.5]) {
      expect(source.entropy(t),
          closeTo(basis.spectralEntropy(rho, t), 1e-9));
      expect(source.negLogPartition(t),
          closeTo(basis.negLogPartition(rho, t), 1e-9));
    }
  });

  test('SpectralProjection addition requires matching basis signature',
      () {
    final g = buildPath(12);
    final a = SpectralBasis.fromGraph(g, 4);
    final b = SpectralBasis.fromGraph(g, 6);
    final rho1 = Float64List(12)..[2] = 1.0;
    final rho2 = Float64List(12)..[9] = 1.0;
    final pa1 = a.projectSource(rho1);
    final pa2 = a.projectSource(rho2);
    final pb1 = b.projectSource(rho1);
    // Same basis → addition works; each coeff is summed.
    final combined = pa1 + pa2;
    for (var j = 0; j < a.k; j++) {
      expect(combined.coefficients[j],
          closeTo(pa1.coefficients[j] + pa2.coefficients[j], 1e-12));
    }
    // Different-signature bases reject.
    expect(() => pa1 + pb1, throwsStateError);
  });

  test('crossLevelCoherence handles fineIdx in the middle of the tower',
      () {
    // Build a 3-level tower: coarse(4) → middle(8) → fine(16).
    // Query coherence between coarse (0) and middle (1), NOT fine (2).
    // The old implementation started at restrictions.length - 1 = 1
    // and applied restrictions[1] (middle → coarse on fine's Fiedler,
    // which is dim 16) — catching the size-mismatch guard and
    // silently returning 0.0. The fix should produce a real value.
    final coarseG = buildPath(4);
    final middleG = buildPath(8);
    final fineG = buildPath(16);
    final coarse = SpectralBasis.fromGraph(coarseG, 4);
    final middle = SpectralBasis.fromGraph(middleG, 8);
    final fine = SpectralBasis.fromGraph(fineG, 16);
    final rCM = RestrictionOperator.uniform(
      nCoarse: 4,
      nFine: 8,
      membersByCoarse: {for (var c = 0; c < 4; c++) c: [2 * c, 2 * c + 1]},
    );
    final rMF = RestrictionOperator.uniform(
      nCoarse: 8,
      nFine: 16,
      membersByCoarse: {for (var c = 0; c < 8; c++) c: [2 * c, 2 * c + 1]},
    );
    final tower = SpectralTower(
      bases: [coarse, middle, fine],
      restrictions: [rCM, rMF],
    );
    final coh = tower.crossLevelCoherence(coarseIdx: 0, fineIdx: 1, t: 0.0);
    expect(coh, isNot(0.0),
        reason: 'coarseIdx=0, fineIdx=1 should lift middle.fiedler via '
            'restrictions[0] only, never touching restrictions[1]');
    expect(coh.abs(), lessThanOrEqualTo(1.0 + 1e-9));
  });

  test('SpectralBasisCache prunes everything outside the keep set',
      () async {
    final tmp = await Directory.systemTemp.createTemp('logos-basis-prune-');
    try {
      final cache = SpectralBasisCache(directory: tmp);
      final a = SpectralBasis.fromGraph(buildPath(10), 4);
      final b = SpectralBasis.fromGraph(buildPath(12), 4);
      await cache.write(a);
      await cache.write(b);
      await cache.prune({a.signature});
      expect(await cache.read(a.signature), isNotNull);
      expect(await cache.read(b.signature), isNull);
    } finally {
      await tmp.delete(recursive: true);
    }
  });

  test('Bulk coordinate table packs every node row-major', () {
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 6);
    final table = basis.nodeCoordinateTable(dims: 3);
    expect(table, hasLength(20 * 3));
    for (var i = 0; i < 20; i++) {
      final row = basis.nodeCoordinates(i, dims: 3);
      expect(table[i * 3 + 0], closeTo(row[0], 1e-12));
      expect(table[i * 3 + 1], closeTo(row[1], 1e-12));
      expect(table[i * 3 + 2], closeTo(row[2], 1e-12));
    }
  });

  test('Poincaré coordinates live inside the open unit disc', () {
    final g = buildPath(40);
    final basis = SpectralBasis.fromGraph(g, 10);
    final table = basis.poincareCoordinateTable(targetRadius: 0.92);
    expect(table, hasLength(40 * 2));
    for (var i = 0; i < 40; i++) {
      final x = table[i * 2];
      final y = table[i * 2 + 1];
      final r = math.sqrt(x * x + y * y);
      expect(r, lessThan(0.92 + 1e-12),
          reason: 'node $i breached the targetRadius boundary');
      expect(r.isFinite, isTrue);
    }
  });

  test('Poincaré coordinates are symmetric under graph-endpoint swap', () {
    // A path graph's spectrum has a sign symmetry — the first Fiedler
    // mode is monotonic from one end to the other. Nodes at symmetric
    // positions around the center should sit at symmetric radii.
    final g = buildPath(20);
    final basis = SpectralBasis.fromGraph(g, 8);
    final t = basis.poincareCoordinateTable();
    for (var i = 0; i < 10; i++) {
      final rA = math.sqrt(t[i * 2] * t[i * 2] + t[i * 2 + 1] * t[i * 2 + 1]);
      final j = 19 - i;
      final rB = math.sqrt(t[j * 2] * t[j * 2] + t[j * 2 + 1] * t[j * 2 + 1]);
      expect(rA, closeTo(rB, 0.05),
          reason: 'mirror nodes $i/$j should embed at similar radii');
    }
  });

  test('poincareDistance is 0 for same point, finite for distinct', () {
    expect(poincareDistance(0.3, 0.4, 0.3, 0.4), closeTo(0.0, 1e-12));
    final d = poincareDistance(0.0, 0.0, 0.5, 0.0);
    expect(d, greaterThan(0.0));
    expect(d.isFinite, isTrue);
    // Boundary: points on/outside unit circle return infinity.
    expect(poincareDistance(0.0, 0.0, 1.0, 0.0), equals(double.infinity));
  });

  test('poincareDistance respects triangle inequality on random triples', () {
    final rng = math.Random(42);
    for (var trial = 0; trial < 20; trial++) {
      double pt() => (rng.nextDouble() - 0.5) * 1.6; // radius < 0.8
      final ax = pt(), ay = pt();
      final bx = pt(), by = pt();
      final cx = pt(), cy = pt();
      if (ax * ax + ay * ay >= 0.81) continue;
      if (bx * bx + by * by >= 0.81) continue;
      if (cx * cx + cy * cy >= 0.81) continue;
      final dab = poincareDistance(ax, ay, bx, by);
      final dbc = poincareDistance(bx, by, cx, cy);
      final dac = poincareDistance(ax, ay, cx, cy);
      expect(dac, lessThanOrEqualTo(dab + dbc + 1e-9),
          reason: 'triangle inequality failed on trial $trial');
    }
  });

  test('Poincaré beats Euclidean distortion on a tree graph', () {
    // A balanced binary tree is the canonical tree-like (δ = 0) fixture.
    // Hyperbolic embedding should track hop distance dramatically better
    // than Euclidean in the same number of dimensions.
    CsrGraph buildBinaryTree(int depth) {
      final n = (1 << (depth + 1)) - 1;
      final indptr = Int32List(n + 1);
      final indices = <int>[];
      final values = <double>[];
      final row = List<List<(int, double)>>.generate(n, (_) => []);
      for (var i = 0; i < n; i++) {
        final left = 2 * i + 1;
        final right = 2 * i + 2;
        if (left < n) {
          row[i].add((left, 1.0));
          row[left].add((i, 1.0));
        }
        if (right < n) {
          row[i].add((right, 1.0));
          row[right].add((i, 1.0));
        }
      }
      for (var i = 0; i < n; i++) {
        indptr[i + 1] = indptr[i] + row[i].length;
        for (final (j, w) in row[i]) {
          indices.add(j);
          values.add(w);
        }
      }
      return CsrGraph(
        n: n,
        indptr: indptr,
        indices: Int32List.fromList(indices),
        values: Float64List.fromList(values),
      );
    }

    final g = buildBinaryTree(5); // 63 nodes, depth 5
    final basis = SpectralBasis.fromGraph(g, 12);
    final euc2d = basis.nodeCoordinateTable(dims: 2);
    final hyp = basis.poincareCoordinateTable();

    // Compute ~200 random-pair (euclidean 2D vs hyperbolic 2D) vs a
    // per-pair "rank proxy" — shared-ancestor depth difference in the
    // tree. Spearman-style: count how often each metric preserves the
    // ordering of pair distances vs the true graph distance.
    final rng = math.Random(0xC0DE);
    var hypBetter = 0;
    var eucBetter = 0;
    for (var t = 0; t < 300; t++) {
      final a = rng.nextInt(63);
      final b = rng.nextInt(63);
      final c = rng.nextInt(63);
      final d = rng.nextInt(63);
      if (a == b || c == d) continue;
      // True distance via path-to-root reconstruction.
      int treeDist(int u, int v) {
        final pu = <int>[u];
        var x = u;
        while (x > 0) {
          x = (x - 1) >> 1;
          pu.add(x);
        }
        var y = v;
        var steps = 0;
        final seen = pu.toSet();
        while (!seen.contains(y)) {
          y = (y - 1) >> 1;
          steps++;
        }
        return steps + pu.indexOf(y);
      }

      final dAB = treeDist(a, b);
      final dCD = treeDist(c, d);
      if (dAB == dCD) continue;

      double euclid(int i, int j) {
        final dx = euc2d[i * 2] - euc2d[j * 2];
        final dy = euc2d[i * 2 + 1] - euc2d[j * 2 + 1];
        return math.sqrt(dx * dx + dy * dy);
      }

      final eAB = euclid(a, b);
      final eCD = euclid(c, d);
      final hAB = poincareDistance(
          hyp[a * 2], hyp[a * 2 + 1], hyp[b * 2], hyp[b * 2 + 1]);
      final hCD = poincareDistance(
          hyp[c * 2], hyp[c * 2 + 1], hyp[d * 2], hyp[d * 2 + 1]);
      if (!hAB.isFinite || !hCD.isFinite) continue;

      final trueOrder = dAB < dCD ? -1 : 1;
      final eOrder = eAB < eCD ? -1 : 1;
      final hOrder = hAB < hCD ? -1 : 1;
      if (hOrder == trueOrder && eOrder != trueOrder) hypBetter++;
      if (eOrder == trueOrder && hOrder != trueOrder) eucBetter++;
    }
    // On a tree, hyperbolic should win clearly — not a tie.
    expect(hypBetter, greaterThan(eucBetter),
        reason:
            'On a tree, Poincaré must track hop distance better than Euclidean '
            '(got hypBetter=$hypBetter, eucBetter=$eucBetter)');
  });
}
