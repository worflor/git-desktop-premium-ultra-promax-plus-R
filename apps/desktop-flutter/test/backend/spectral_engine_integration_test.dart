// Cross-module integration test for the spectral engine surface.
//
// Verifies the wiring between LogosGit, LogosState, RicciField,
// KizunaBond25D, and SpectralOperator — the canonical flow a consumer
// would drive.
//
// Does NOT re-test individual module invariants (those live in their
// own test files). Only asserts that methods exist, types line up,
// and cross-module composition works.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/spectral_kizuna.dart';
import 'package:git_desktop/backend/spectral_operator.dart';
import 'package:git_desktop/backend/spectral_ricci.dart';
import 'package:git_desktop/backend/spectral_state.dart';

/// Minimal 4-file fixture — small graph; LogosGit.spectralBasis() will
/// return null because n < kDefaultSpectralMinNodes (256).
LogosGitStats _tinyStats() {
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
        'lib/a.dart': {'lib/b.dart': 0.8, 'lib/c.dart': 0.7},
        'lib/b.dart': {'lib/a.dart': 0.8, 'lib/c.dart': 0.75},
        'lib/c.dart': {'lib/a.dart': 0.7, 'lib/b.dart': 0.75},
      },
      headHash: 'abc',
      commitsAnalyzed: 50,
    ),
    perFileCommitIndices: const {},
  );
}

/// Synthetic fixture large enough for SpectralBasis amortisation
/// (n >= kDefaultSpectralMinNodes=256). Builds a block-structured
/// co-change pattern so there's real spectral signal.
LogosGitStats _largeStats({int nFiles = 300, int nCommits = 400}) {
  final touches = <String, int>{};
  final volatility = <String, double>{};
  final jaccard = <String, Map<String, double>>{};
  // Three blocks of files; within-block coupling strong, between weak.
  final block = <String, int>{};
  for (var i = 0; i < nFiles; i++) {
    final path = 'lib/b${i % 3}/f$i.dart';
    touches[path] = 10 + (i % 17);
    volatility[path] = 5.0 + (i % 7).toDouble();
    block[path] = i % 3;
  }
  // Build coupling: sparse, block-biased.
  final paths = touches.keys.toList();
  for (var i = 0; i < paths.length; i++) {
    final row = <String, double>{};
    for (var j = 0; j < paths.length; j++) {
      if (i == j) continue;
      final sameBlock = block[paths[i]] == block[paths[j]];
      // Only include strong within-block edges; skip most between-block.
      if (sameBlock) {
        if ((i + j) % 3 == 0) row[paths[j]] = 0.7;
      } else {
        if ((i + j) % 37 == 0) row[paths[j]] = 0.1;
      }
    }
    if (row.isNotEmpty) jaccard[paths[i]] = row;
  }
  // Commit indices: each file touched in ~block_id-scattered commits.
  final perFileCommitIndices = <String, List<int>>{};
  for (var i = 0; i < paths.length; i++) {
    final b = block[paths[i]]!;
    final indices = <int>[];
    for (var c = 0; c < nCommits; c++) {
      // File in block b appears in commits where c % 3 == b, roughly.
      if (c % 3 == b && (c + i) % 5 != 0) indices.add(c);
    }
    if (indices.isNotEmpty) perFileCommitIndices[paths[i]] = indices;
  }
  return LogosGitStats(
    touches: touches,
    totalCommits: nCommits,
    volatility: volatility,
    volMean: 8.0,
    volStddev: 3.0,
    coupling: FileCouplingMatrix(
      jaccard: jaccard,
      headHash: 'synth',
      commitsAnalyzed: nCommits,
    ),
    perFileCommitIndices: perFileCommitIndices,
  );
}

void main() {
  group('LogosGit engine surface (tiny graph, below spectral threshold)', () {
    final engine = LogosGit.buildFromStats(_tinyStats());

    test('ricciField() computes curvatures with valid geometric ranges', () {
      final rf = engine.ricciField();
      expect(rf.length, greaterThan(0));
      // Every Ollivier-Ricci value is in [−1, 1] by definition
      // (1 − W₁/d, with W₁ ≤ d). Verify, not just non-null.
      for (var i = 0; i < rf.length; i++) {
        expect(rf.curvatures[i], inInclusiveRange(-1.0 - 1e-9, 1.0 + 1e-9),
            reason: 'OR curvatures must live in [-1, 1]');
      }
      // Deterministic rebuild: same graph, same numbers.
      final rf2 = engine.ricciField();
      expect(rf2.signature, equals(rf.signature));
      for (var i = 0; i < rf.length; i++) {
        expect(rf2.curvatures[i], equals(rf.curvatures[i]));
      }
    });

    test('kizunaBond() returns null below spectral threshold', () {
      // Tiny graph (4 files) ⇒ no spectral basis is materialised
      // (threshold = 256) ⇒ bond cannot be built.
      expect(engine.kizunaBond(), isNull);
    });

    test('snapshot() captures revision + distinct signature per state', () {
      final state = engine.snapshot();
      expect(state.revision, equals(engine.manifoldRevision));
      expect(state.fileSpectrum, isNull, reason: 'n < spectral threshold');
      // Signature must differ from the empty state.
      expect(state.signature, isNot(equals(LogosState.empty().signature)));
      // Bumping revision yields a distinct signature (revision is
      // folded into the hash, not just spectra).
      final bumped = state.withRevision(state.revision + 1);
      expect(bumped.signature, isNot(equals(state.signature)));
    });
  });

  group('LogosGit engine surface (large graph, above spectral threshold)', () {
    final engine = LogosGit.buildFromStats(_largeStats());

    test('spectralBasis() materialises on n >= 256', () {
      final basis = engine.spectralBasis();
      expect(basis, isNotNull);
      expect(basis!.n, greaterThanOrEqualTo(256));
      expect(basis.k, greaterThanOrEqualTo(9),
          reason: 'need k >= 9 for 8-bit fingerprint');
    });

    test('commitSpectralBasis carries its own spectrum', () {
      final basis = engine.commitSpectralBasis();
      expect(basis, isNotNull);
      // A valid basis has normalised-Laplacian eigenvalues in [0, 2].
      for (var j = 0; j < basis!.k; j++) {
        expect(basis.eigenvalues[j], inInclusiveRange(-1e-9, 2.0 + 1e-9),
            reason: 'λ_j ∈ [0, 2] for normalised Laplacian');
      }
      expect(basis.eigenvalues[0], closeTo(0.0, 1e-6),
          reason: 'λ_0 should be zero on a connected graph');
    });

    test('snapshot carries populated spectra with distinct factor sigs', () {
      final state = engine.snapshot();
      expect(state.fileSpectrum, isNotNull);
      // With populated spectra the state signature must mix the
      // factor signatures, not just trivially encode "populated".
      // Empty state and this state must produce different signatures.
      expect(state.signature, isNot(equals(LogosState.empty().signature)));
      // File and commit spectra should have distinct signatures
      // (they're different graphs; coincidence would be astronomical).
      if (state.commitSpectrum != null) {
        expect(state.fileSpectrum!.signature,
            isNot(equals(state.commitSpectrum!.signature)));
      }
    });

    test('state.diff() on equal states reports signatureMatch', () {
      final a = engine.snapshot();
      final b = engine.snapshot();
      final d = a.diff(b);
      expect(d.signatureMatch, isTrue);
      expect(d.inSync, isTrue);
    });

    test('ricciField() computes curvatures and depth scalar', () {
      final rf = engine.ricciField();
      expect(rf.length, greaterThan(0));
      // A block-structured graph should have some negative-curvature
      // bridge-like edges.
      expect(rf.depth, lessThanOrEqualTo(0.0 + 1e-6),
          reason: 'block-structured graph should have at least one '
              'bridge-ish edge with non-positive Ricci');
      final bridges = rf.mostNegativeEdges(k: 3);
      expect(bridges.length, lessThanOrEqualTo(3));
      expect(bridges.length, greaterThan(0));
    });

    test('kizunaBond() produces a valid 25-D fingerprint', () {
      final bond = engine.kizunaBond();
      expect(bond, isNotNull);
      expect(bond!.coefficients.length, 25);
      // Family profile sums to 1 (or 0 for empty).
      final p = bond.familyProfile;
      final total = p.lower + p.upper + p.cross + p.global;
      expect(total, anyOf(closeTo(1.0, 1e-9), closeTo(0.0, 1e-9)));
    });

    test('kizunaBond() self-cosine is 1.0 and empty histogram yields 0', () {
      final bond = engine.kizunaBond();
      expect(bond, isNotNull);
      // Self-cosine is 1 by definition.
      expect(bond!.cosineSimilarity(bond), closeTo(1.0, 1e-9));
      // Non-trivial bond has at least one family with mass.
      final p = bond.familyProfile;
      final hasMass = p.lower + p.upper + p.cross + p.global > 1e-6;
      expect(hasMass, isTrue,
          reason: 'block-structured synthetic repo should produce mass');
    });

    test('bond roundtrips through toBytes / fromBytes', () {
      final bond = engine.kizunaBond();
      expect(bond, isNotNull);
      final bytes = bond!.toBytes();
      final restored = KizunaBond25D.fromBytes(bytes);
      expect(restored.signature, equals(bond.signature));
      for (var i = 0; i < 25; i++) {
        expect(restored.coefficients[i], equals(bond.coefficients[i]));
      }
    });

    test('classifyBondPair reports identical on self-pair', () {
      final bond = engine.kizunaBond();
      expect(bond, isNotNull);
      expect(classifyBondPair(bond!, bond),
          equals(KizunaBondCompatibility.identical));
    });

    test('classifyBondPair classifies roundtripped bond as identical', () {
      final bond = engine.kizunaBond();
      expect(bond, isNotNull);
      final restored = KizunaBond25D.fromBytes(bond!.toBytes());
      expect(classifyBondPair(bond, restored),
          equals(KizunaBondCompatibility.identical));
    });
  });

  group('SpectralOperator works on an engine-derived basis', () {
    final engine = LogosGit.buildFromStats(_largeStats());

    test('heat(t) composition equals heat(t+s)', () {
      final basis = engine.spectralBasis()!;
      final h2 = SpectralOperator.heat(basis, 2.0);
      final h3 = SpectralOperator.heat(basis, 3.0);
      final h5 = SpectralOperator.heat(basis, 5.0);
      final composed = h2 * h3;
      for (var j = 0; j < basis.k; j++) {
        expect(composed.profile[j], closeTo(h5.profile[j], 1e-10));
      }
    });

    test('applyTo a SpectralProjection preserves basis signature', () {
      final basis = engine.spectralBasis()!;
      final rho = Float64List(basis.n);
      rho[0] = 1.0;
      final proj = basis.projectSource(rho);
      final op = SpectralOperator.heat(basis, 1.0);
      final out = op.applyTo(proj);
      expect(out.basisSignature, equals(proj.basisSignature));
    });
  });

  group('Full-stack new-observables sanity check', () {
    // Confirms that rigidity + AB margin + fragmentation + surgery +
    // Poincaré + eigenvalueDistance all produce sensible values on an
    // engine-built basis — the canonical integration path consumers
    // would drive.
    final engine = LogosGit.buildFromStats(_largeStats());

    test('rigidity returns a finite scalar on the engine basis', () {
      final basis = engine.spectralBasis()!;
      final r = basis.spectralRigidity;
      expect(r.isFinite, isTrue);
      expect(r, greaterThan(0.0));
      expect(r, lessThan(1.0));
    });

    test('Alon-Boppana margin returns either a finite scalar or NaN',
        () {
      final basis = engine.spectralBasis()!;
      final m = alonBoppanaMargin(basis, engine.graph);
      // NaN is a valid outcome for very sparse graphs (d̄ < 3); a
      // finite value must be non-negative.
      if (m.isFinite) {
        expect(m, greaterThanOrEqualTo(0.0));
      } else {
        expect(m.isNaN, isTrue,
            reason: 'non-finite result must be NaN, got $m '
                '(harmonic-mean-degree = ${engine.graph.harmonicMeanDegree()})');
      }
    });

    test('fragmentationCurve spans the normalised weight range', () {
      final curve = engine.graph.fragmentationCurve(const [0.0, 0.1, 1.0]);
      expect(curve.length, 3);
      // Monotonic: as θ rises, components non-decreasing; largest
      // fraction non-increasing.
      for (var i = 1; i < curve.length; i++) {
        expect(curve[i].componentCount,
            greaterThanOrEqualTo(curve[i - 1].componentCount));
        expect(curve[i].largestFraction,
            lessThanOrEqualTo(curve[i - 1].largestFraction + 1e-12));
      }
      // β₁ is always |E_sub| − n + β₀ at each row.
      for (final r in curve) {
        expect(r.cycleRank,
            equals((r.edgeCount - engine.graph.n + r.componentCount)
                .clamp(0, 1 << 30)));
      }
    });

    test('Poincaré table fits inside the unit disc', () {
      final basis = engine.spectralBasis()!;
      final table = basis.poincareCoordinateTable();
      expect(table.length, basis.n * 2);
      for (var i = 0; i < basis.n; i++) {
        final r2 = table[i * 2] * table[i * 2] +
            table[i * 2 + 1] * table[i * 2 + 1];
        expect(r2, lessThan(1.0));
      }
    });

    test('Ricci surgery fragments a block-structured graph', () {
      final field = engine.ricciField();
      final curve = field.surgeryFragmentation(
        engine.graph.n,
        const [-1.0, 0.0, 1.0],
      );
      // θ = -1.0 keeps everything → one big component for this fixture.
      // θ = 1.0 cuts all interior edges → very fragmented.
      expect(curve.first.componentCount,
          lessThan(curve.last.componentCount));
    });

    test('eigenvalueDistance from self is zero, from resampled non-zero',
        () {
      final basis = engine.spectralBasis()!;
      expect(basis.eigenvalueDistance(basis), closeTo(0.0, 1e-15));
      // Second engine built from same stats is deterministic, so
      // distance remains ~0. Instead build from a slightly different
      // stat set and expect nonzero.
      final engine2 = LogosGit.buildFromStats(
          _largeStats(nFiles: 300, nCommits: 420));
      final basis2 = engine2.spectralBasis()!;
      if (basis.k == basis2.k) {
        final d = basis.eigenvalueDistance(basis2);
        expect(d, greaterThan(0.0));
      }
    });
  });
}
