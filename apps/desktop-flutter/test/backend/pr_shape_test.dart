// Tests for the geometric / magnetic PR-shape pipeline.
//
// The PrShape struct + PrShapeComputer encapsulate the "PR as magnet
// in the field" framing — these tests exercise the math invariants
// (cosine bounds, alignment buckets, field-vector decay) and the
// compute path (handles empty graph, out-of-graph files, etc).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/gh.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/pr_shape.dart';

LogosGit _ringEngine() {
  // 4-node ring: a-b, b-c, c-d, d-a — bounded spectrum, two clear
  // halves so PR shapes can be meaningfully distinguished.
  const matrix = FileCouplingMatrix(
    jaccard: {
      'lib/a.dart': {'lib/b.dart': 0.7, 'lib/d.dart': 0.7},
      'lib/b.dart': {'lib/a.dart': 0.7, 'lib/c.dart': 0.7},
      'lib/c.dart': {'lib/b.dart': 0.7, 'lib/d.dart': 0.7},
      'lib/d.dart': {'lib/a.dart': 0.7, 'lib/c.dart': 0.7},
    },
    headHash: 'h',
    commitsAnalyzed: 100,
  );
  return LogosGit.buildFromStats(LogosGitStats(
    touches: const {
      'lib/a.dart': 5,
      'lib/b.dart': 5,
      'lib/c.dart': 5,
      'lib/d.dart': 5,
    },
    totalCommits: 100,
    volatility: const {
      'lib/a.dart': 1.0,
      'lib/b.dart': 1.0,
      'lib/c.dart': 1.0,
      'lib/d.dart': 1.0,
    },
    volMean: 1.0,
    volStddev: 0.5,
    coupling: matrix,
    perFileCommitIndices: const {
      // Touches monotonically increasing from 0..99 — recent enough
      // to register in the field's ~30-commit half-life window.
      'lib/a.dart': [0, 25, 50, 75, 95],
      'lib/b.dart': [10, 30, 55, 80, 96],
      'lib/c.dart': [5, 35, 60, 85, 97],
      'lib/d.dart': [15, 40, 65, 90, 98],
    },
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrShapeComputer.cosine', () {
    test('identical vectors → 1.0', () {
      final a = Float64List.fromList([0.5, 0.3, 0.2]);
      final b = Float64List.fromList([0.5, 0.3, 0.2]);
      expect(PrShapeComputer.cosine(a, b), closeTo(1.0, 1e-12));
    });

    test('orthogonal non-overlapping vectors → 0', () {
      final a = Float64List.fromList([1.0, 0.0, 0.0]);
      final b = Float64List.fromList([0.0, 1.0, 0.0]);
      expect(PrShapeComputer.cosine(a, b), closeTo(0.0, 1e-12));
    });

    test('zero-norm vector → 0 (no NaN propagation)', () {
      final a = Float64List.fromList([0.0, 0.0, 0.0]);
      final b = Float64List.fromList([1.0, 1.0, 1.0]);
      expect(PrShapeComputer.cosine(a, b), 0.0);
    });

    test('non-negative inputs always produce cosine in [0, 1]', () {
      final a = Float64List.fromList([0.1, 0.5, 0.9, 0.2]);
      final b = Float64List.fromList([0.4, 0.1, 0.7, 0.3]);
      final c = PrShapeComputer.cosine(a, b);
      expect(c, greaterThanOrEqualTo(0.0));
      expect(c, lessThanOrEqualTo(1.0));
    });
  });

  group('PrShapeComputer.bucketAlignment', () {
    test('1.0 → withField', () {
      expect(PrShapeComputer.bucketAlignment(1.0),
          FieldOrientation.withField);
    });
    test('0.5 boundary → withField (≥ threshold)', () {
      expect(PrShapeComputer.bucketAlignment(0.5),
          FieldOrientation.withField);
    });
    test('0.49 → adjacent', () {
      expect(PrShapeComputer.bucketAlignment(0.49),
          FieldOrientation.adjacent);
    });
    test('0.2 boundary → adjacent', () {
      expect(PrShapeComputer.bucketAlignment(0.2),
          FieldOrientation.adjacent);
    });
    test('0.0 → orthogonal', () {
      expect(PrShapeComputer.bucketAlignment(0.0),
          FieldOrientation.orthogonal);
    });
  });

  group('LogosGit.recentActivityWeights', () {
    test('returns non-empty weights for files with recent touches', () {
      final engine = _ringEngine();
      final weights = engine.recentActivityWeights(halfLifeCommits: 30);
      expect(weights, isNotEmpty);
      // All four files have touches at index 95+ — well within the
      // 30-commit half-life — so they should all carry weight.
      expect(weights.keys.toSet(),
          {'lib/a.dart', 'lib/b.dart', 'lib/c.dart', 'lib/d.dart'});
    });

    test('weights respect recency — newer touches dominate', () {
      // Engine where one file has only ancient touches, another only
      // recent — the recent one should carry strictly more weight.
      const matrix = FileCouplingMatrix(
        jaccard: {
          'lib/old.dart': {'lib/new.dart': 0.5},
          'lib/new.dart': {'lib/old.dart': 0.5},
        },
        headHash: 'h',
        commitsAnalyzed: 100,
      );
      final engine = LogosGit.buildFromStats(LogosGitStats(
        touches: const {'lib/old.dart': 3, 'lib/new.dart': 3},
        totalCommits: 200,
        volatility: const {'lib/old.dart': 1.0, 'lib/new.dart': 1.0},
        volMean: 1.0,
        volStddev: 0.1,
        coupling: matrix,
        perFileCommitIndices: const {
          // OLD: indices 0, 1, 2 — way past the 30-commit half-life.
          'lib/old.dart': [0, 1, 2],
          // NEW: indices 197, 198, 199 — most recent.
          'lib/new.dart': [197, 198, 199],
        },
      ));
      final weights = engine.recentActivityWeights(halfLifeCommits: 30);
      // Old file's age (≥ 197) is far past 6×30 = 180, so it should
      // be dropped entirely.
      expect(weights.containsKey('lib/old.dart'), isFalse);
      expect(weights['lib/new.dart']!, greaterThan(2.0));
    });
  });

  group('PrShapeComputer.compute', () {
    test('null when engine is empty', () {
      final emptyEngine = LogosGit.buildFromStats(const LogosGitStats(
        touches: {},
        totalCommits: 0,
        volatility: {},
        volMean: 0,
        volStddev: 0,
        coupling: FileCouplingMatrix.empty,
        perFileCommitIndices: {},
      ));
      final shape = PrShapeComputer.compute(
        engine: emptyEngine,
        prFiles: const [
          PrFile(path: 'lib/a.dart', additions: 5, deletions: 2),
        ],
      );
      expect(shape, isNull);
    });

    test('null when no PR files land in-graph', () {
      final engine = _ringEngine();
      final shape = PrShapeComputer.compute(
        engine: engine,
        prFiles: const [
          PrFile(path: 'unknown/path.dart', additions: 5, deletions: 2),
        ],
      );
      expect(shape, isNull);
    });

    test('produces a populated shape for in-graph PR files', () {
      final engine = _ringEngine();
      final shape = PrShapeComputer.compute(
        engine: engine,
        prFiles: const [
          PrFile(path: 'lib/a.dart', additions: 10, deletions: 3),
          PrFile(path: 'lib/b.dart', additions: 5, deletions: 1),
        ],
      );
      expect(shape, isNotNull);
      expect(shape!.phi.length, engine.nodePaths.length);
      expect(shape.coherence, greaterThan(0));
      expect(shape.coherence, lessThanOrEqualTo(1));
      expect(shape.stability, greaterThanOrEqualTo(0));
      expect(shape.stability, lessThanOrEqualTo(1));
      expect(shape.metabolismRisk, greaterThan(0));
      // Single-axis collapse → axisMassFractions has exactly one entry
      // summing to 1.
      expect(shape.axisMassFractions.values.fold<double>(0, (a, b) => a + b),
          closeTo(1.0, 1e-9));
    });

    test('field alignment is bound [0, 1] when field is provided', () {
      final engine = _ringEngine();
      final field = PrShapeComputer.computeField(engine: engine);
      expect(field, isNotNull);
      final shape = PrShapeComputer.compute(
        engine: engine,
        prFiles: const [
          PrFile(path: 'lib/a.dart', additions: 5, deletions: 1),
        ],
        field: field,
      );
      expect(shape, isNotNull);
      expect(shape!.fieldAlignment, isNotNull);
      expect(shape.fieldAlignment!, greaterThanOrEqualTo(0.0));
      expect(shape.fieldAlignment!, lessThanOrEqualTo(1.0));
      expect(shape.orientation, isNotNull);
    });

    test('two PRs touching the same neighborhood have high mutual cosine', () {
      final engine = _ringEngine();
      final shapeA = PrShapeComputer.compute(
        engine: engine,
        prFiles: const [
          PrFile(path: 'lib/a.dart', additions: 10, deletions: 0),
        ],
      )!;
      final shapeB = PrShapeComputer.compute(
        engine: engine,
        prFiles: const [
          PrFile(path: 'lib/b.dart', additions: 10, deletions: 0),
        ],
      )!;
      // a-b are directly coupled (Jaccard 0.7) — their φ neighborhoods
      // overlap heavily — cosine should be substantial.
      final cos = PrShapeComputer.cosine(shapeA.phi, shapeB.phi);
      expect(cos, greaterThan(0.5));
    });
  });

  group('PrShapeComputer.computeField', () {
    test('null on empty engine', () {
      final emptyEngine = LogosGit.buildFromStats(const LogosGitStats(
        touches: {},
        totalCommits: 0,
        volatility: {},
        volMean: 0,
        volStddev: 0,
        coupling: FileCouplingMatrix.empty,
        perFileCommitIndices: {},
      ));
      final field = PrShapeComputer.computeField(engine: emptyEngine);
      expect(field, isNull);
    });

    test('field vector matches engine node count', () {
      final engine = _ringEngine();
      final field = PrShapeComputer.computeField(engine: engine);
      expect(field, isNotNull);
      expect(field!.phi.length, engine.nodePaths.length);
    });
  });
}
