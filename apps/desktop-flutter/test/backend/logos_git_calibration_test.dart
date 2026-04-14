// Tests for [LogosSseStore] — the per-repo SSE calibration layer that
// closes the Logos self-learning loop.
//
// Exercises:
//   - Regime classification from (fileCount, coherence)
//   - Per-cell emission / citation counting
//   - Utility math (KT prior at low n, cited/emitted at high n)
//   - Evaporation at saturation (halving at n=256)
//   - Round-trip persistence through a temp-dir fake repo
//   - `extractCitedPathsFromReviewOutput` parses common forms

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_git_calibration.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LogosRegime.classify', () {
    test('tiny cohesive diff → focused', () {
      expect(
        LogosRegime.classify(fileCount: 2, coherence: 0.8),
        LogosRegime.focused,
      );
    });

    test('medium moderately-cohesive diff → scoped', () {
      expect(
        LogosRegime.classify(fileCount: 8, coherence: 0.45),
        LogosRegime.scoped,
      );
    });

    test('huge scattered diff → sweep', () {
      expect(
        LogosRegime.classify(fileCount: 40, coherence: 0.1),
        LogosRegime.sweep,
      );
    });

    test('borderline path: 12 files, coherence 0.35 → scoped (inclusive)', () {
      expect(
        LogosRegime.classify(fileCount: 12, coherence: 0.35),
        LogosRegime.scoped,
      );
    });
  });

  group('LogosSseCell', () {
    test('utility stays at 0.5 prior under small evidence', () {
      final c = LogosSseCell(emitted: 1, cited: 1);
      expect(c.utility, 0.5);
      final c2 = LogosSseCell(emitted: 3, cited: 3);
      expect(c2.utility, 0.5);
    });

    test('utility equals cited/emitted once n ≥ 4', () {
      final c = LogosSseCell(emitted: 10, cited: 7);
      expect(c.utility, closeTo(0.7, 1e-9));
    });

    test('evaporation halves both counts at saturation', () {
      final c = LogosSseCell(emitted: 256, cited: 100);
      c.evaporateIfSaturated();
      expect(c.emitted, 128);
      expect(c.cited, 50);
    });

    test('no evaporation below threshold', () {
      final c = LogosSseCell(emitted: 255, cited: 100);
      c.evaporateIfSaturated();
      expect(c.emitted, 255);
      expect(c.cited, 100);
    });

    test('continuous-time decay halves counts per half-life elapsed', () {
      final halfLifeMs = LogosSseCell.halfLife.inMilliseconds;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final c = LogosSseCell(
        emitted: 100,
        cited: 50,
        lastUpdateMs: nowMs - halfLifeMs,
      );
      final u = c.utility; // triggers decay
      expect(u, closeTo(0.5, 1e-9),
          reason: 'ratio should survive uniform decay');
      expect(c.emitted, closeTo(50, 1.0),
          reason: 'emitted count should have halved');
      expect(c.cited, closeTo(25, 1.0),
          reason: 'cited count should have halved');
    });

    test('decay never violates cited ≤ emitted', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final c = LogosSseCell(
        emitted: 10,
        cited: 10,
        lastUpdateMs: nowMs - 1000000,
      );
      c.utility;
      expect(c.cited, lessThanOrEqualTo(c.emitted),
          reason: 'decay preserves the cited ≤ emitted invariant');
    });

    test('toJson round-trip preserves timestamp', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final c = LogosSseCell(
        emitted: 5,
        cited: 3,
        lastUpdateMs: nowMs,
      );
      final json = c.toJson();
      final restored = LogosSseCell.fromJson(json);
      expect(restored.lastUpdateMs, nowMs);
      expect(restored.emitted, closeTo(5, 0.01));
      expect(restored.cited, closeTo(3, 0.01));
    });

    test('legacy cells without timestamp migrate softly', () {
      final legacy = {'e': 40, 'c': 20};
      final cell = LogosSseCell.fromJson(legacy);
      final ageMs =
          DateTime.now().millisecondsSinceEpoch - cell.lastUpdateMs;
      final halfLifeMs = LogosSseCell.halfLife.inMilliseconds;
      expect(ageMs, greaterThan(halfLifeMs ~/ 4));
      expect(ageMs, lessThan(halfLifeMs));
    });
  });

  group('LogosSseStore round-trip persistence', () {
    late Directory repo;
    late LogosSseStore store;

    setUp(() async {
      repo = await Directory.systemTemp.createTemp('logos_sse_test_');
      await Directory(p.join(repo.path, '.git')).create(recursive: true);
      store = LogosSseStore(repo.path);
    });

    tearDown(() async {
      if (await repo.exists()) {
        await repo.delete(recursive: true);
      }
    });

    test('records emissions and reads them back', () async {
      await store.recordEmissions(LogosEmissionRecord(
        regime: LogosRegime.focused,
        axisByPath: const {
          'lib/a.dart': LogosAxis.primary,
          'lib/b.dart': LogosAxis.m,
          'test/a_test.dart': LogosAxis.ab,
        },
      ));
      final primary =
          await store.cellFor(LogosRegime.focused, LogosAxis.primary);
      expect(primary.emitted, 1);
      final m = await store.cellFor(LogosRegime.focused, LogosAxis.m);
      expect(m.emitted, 1);
      final ab = await store.cellFor(LogosRegime.focused, LogosAxis.ab);
      expect(ab.emitted, 1);
      // Cross-regime → empty
      final wrongRegime =
          await store.cellFor(LogosRegime.sweep, LogosAxis.primary);
      expect(wrongRegime.emitted, 0);
    });

    test('records citations against emitted paths', () async {
      final record = LogosEmissionRecord(
        regime: LogosRegime.scoped,
        axisByPath: const {
          'lib/foo.dart': LogosAxis.primary,
          'lib/bar.dart': LogosAxis.m,
          'test/foo_test.dart': LogosAxis.ab,
          'lib/graphlib.dart': LogosAxis.graph,
        },
      );
      await store.recordEmissions(record);
      await store.recordCitations(
        record: record,
        citedPaths: const {'lib/bar.dart', 'lib/graphlib.dart'},
      );
      final m = await store.cellFor(LogosRegime.scoped, LogosAxis.m);
      expect(m.cited, 1);
      expect(m.emitted, 1);
      final graph = await store.cellFor(LogosRegime.scoped, LogosAxis.graph);
      expect(graph.cited, 1);
      expect(graph.emitted, 1);
      // Not cited
      final ab = await store.cellFor(LogosRegime.scoped, LogosAxis.ab);
      expect(ab.cited, 0);
      expect(ab.emitted, 1);
    });

    test('persists across fresh store instances on same repo', () async {
      await store.recordEmissions(LogosEmissionRecord(
        regime: LogosRegime.focused,
        axisByPath: const {'lib/x.dart': LogosAxis.primary},
      ));
      final fresh = LogosSseStore(repo.path);
      final cell =
          await fresh.cellFor(LogosRegime.focused, LogosAxis.primary);
      expect(cell.emitted, 1);
    });

    test('utilitiesFor returns axis multipliers centred at 1.0', () async {
      // Build a history: axis M very useful (high cited/emitted), axis
      // Ab rarely useful. Utilities after n >= 4 should reflect that.
      for (var i = 0; i < 6; i++) {
        await store.recordEmissions(LogosEmissionRecord(
          regime: LogosRegime.focused,
          axisByPath: const {
            'lib/m-hit.dart': LogosAxis.m,
            'lib/ab-hit.dart': LogosAxis.ab,
          },
        ));
        // M cited every time; Ab never.
        await store.recordCitations(
          record: LogosEmissionRecord(
            regime: LogosRegime.focused,
            axisByPath: const {
              'lib/m-hit.dart': LogosAxis.m,
              'lib/ab-hit.dart': LogosAxis.ab,
            },
          ),
          citedPaths: const {'lib/m-hit.dart'},
        );
      }
      final util = await store.utilitiesFor(LogosRegime.focused);
      expect(util[LogosAxis.m]!, greaterThan(1.5),
          reason: 'M axis was always cited → utility should be ~2.0');
      expect(util[LogosAxis.ab]!, lessThan(0.5),
          reason: 'Ab axis never cited → utility should be ~0');
    });

    test('concurrent emissions from sibling stores do not lose counts',
        () async {
      // Race scenario: 20 separate LogosSseStore instances on the
      // same repo concurrently call recordEmissions. Without the
      // per-repo write lock each instance loads → mutates locally →
      // saves, with the latest writer overwriting earlier increments.
      // With the lock, the read-modify-write cycles serialise and the
      // total emitted count must equal the number of concurrent
      // operations, exactly.
      final futures = <Future<void>>[];
      for (var i = 0; i < 20; i++) {
        final sibling = LogosSseStore(repo.path);
        futures.add(sibling.recordEmissions(LogosEmissionRecord(
          regime: LogosRegime.scoped,
          axisByPath: const {'lib/contended.dart': LogosAxis.primary},
        )));
      }
      await Future.wait(futures);
      // Fresh reader (cache cold) sees the on-disk truth.
      final fresh = LogosSseStore(repo.path);
      final cell =
          await fresh.cellFor(LogosRegime.scoped, LogosAxis.primary);
      expect(
        cell.emitted,
        20,
        reason: '20 concurrent +1 increments must sum to exactly 20 '
            '(no race, no lost writes)',
      );
    });
  });

  group('extractCitedPathsFromReviewOutput', () {
    test('picks path="..." attribute form', () {
      const out = '''
<findings>
  <finding path="lib/validators.dart" line="12">issue</finding>
  <finding path="test/foo_test.dart">issue</finding>
</findings>
''';
      final cited = extractCitedPathsFromReviewOutput(out);
      expect(cited, contains('lib/validators.dart'));
      expect(cited, contains('test/foo_test.dart'));
    });

    test('picks bare relative paths mentioned in body', () {
      const out = '''
<observation>
The change in src/auth/login.ts suggests updating src/auth/session.ts too.
</observation>
''';
      final cited = extractCitedPathsFromReviewOutput(out);
      expect(cited, contains('src/auth/login.ts'));
      expect(cited, contains('src/auth/session.ts'));
    });

    test('does not match URLs', () {
      const out = 'See https://github.com/foo/bar/blob/main/README.md';
      final cited = extractCitedPathsFromReviewOutput(out);
      // The bare-path matcher does NOT grab anything starting with http/www.
      expect(cited.any((p) => p.startsWith('http')), isFalse);
    });

    test('empty output returns empty set', () {
      expect(extractCitedPathsFromReviewOutput(''), isEmpty);
    });
  });

  group('LogosSseCell utility velocity', () {
    test('no snapshot yet → velocity is 0', () {
      final cell = LogosSseCell(emitted: 100, cited: 50);
      expect(cell.utilityVelocityPerDay, 0.0);
    });

    test('low evidence (KT-prior land) → velocity is 0', () {
      // Below _minEvidenceForUtility (4): cell.utility returns the
      // KT prior 0.5 regardless of cited/emitted, so any "velocity"
      // would be measuring noise from the prior, not signal.
      final cell = LogosSseCell(
        emitted: 2,
        cited: 1,
        prevUtility: 0.3,
        prevUtilityMs:
            DateTime.now().millisecondsSinceEpoch - Duration.millisecondsPerDay,
      );
      expect(cell.utilityVelocityPerDay, 0.0);
    });

    test('positive trend: utility climbed over time → positive velocity',
        () {
      // emitted=100, cited=70 → utility=0.70; previous snapshot was
      // 0.50 from 10 days ago. Velocity = (0.70 - 0.50) / 10 = +0.02/day.
      final tenDaysAgoMs = DateTime.now().millisecondsSinceEpoch -
          10 * Duration.millisecondsPerDay;
      final cell = LogosSseCell(
        emitted: 100,
        cited: 70,
        prevUtility: 0.5,
        prevUtilityMs: tenDaysAgoMs,
      );
      expect(cell.utilityVelocityPerDay, closeTo(0.02, 1e-3));
    });

    test('negative trend: utility fell → negative velocity', () {
      final fiveDaysAgoMs = DateTime.now().millisecondsSinceEpoch -
          5 * Duration.millisecondsPerDay;
      final cell = LogosSseCell(
        emitted: 100,
        cited: 30,
        prevUtility: 0.5,
        prevUtilityMs: fiveDaysAgoMs,
      );
      // (0.30 - 0.50) / 5 = -0.04/day
      expect(cell.utilityVelocityPerDay, closeTo(-0.04, 1e-3));
    });

    test('zero or negative Δt → velocity 0 (clock-skew safety)', () {
      final cell = LogosSseCell(
        emitted: 100,
        cited: 70,
        prevUtility: 0.5,
        prevUtilityMs: DateTime.now().millisecondsSinceEpoch + 100000,
      );
      expect(cell.utilityVelocityPerDay, 0.0);
    });

    test('JSON round-trip preserves velocity snapshot', () {
      final cell = LogosSseCell(
        emitted: 100,
        cited: 60,
        prevUtility: 0.42,
        prevUtilityMs: 1700000000000,
      );
      final restored = LogosSseCell.fromJson(cell.toJson());
      expect(restored.prevUtility, closeTo(0.42, 1e-3));
      expect(restored.prevUtilityMs, 1700000000000);
    });

    test('JSON without snapshot keys round-trips to null (legacy migration)',
        () {
      // Legacy cells written before T6 won't have 'pu' / 'pt' keys.
      final restored = LogosSseCell.fromJson(const {
        'e': 100.0,
        'c': 50.0,
        't': 1700000000000,
      });
      expect(restored.prevUtility, isNull);
      expect(restored.prevUtilityMs, isNull);
      expect(restored.utilityVelocityPerDay, 0.0);
      expect(restored.utilityVariance, 0.0);
    });
  });

  group('LogosSseCell variance-modulated decay', () {
    test('zero samples → variance 0 → decay unchanged', () {
      // No samples taken → variance 0 → accelerationFactor = 1
      // → effective half-life = base half-life. Legacy behaviour.
      final cell = LogosSseCell(
        emitted: 100,
        cited: 50,
        lastUpdateMs: DateTime.now().millisecondsSinceEpoch -
            LogosSseCell.halfLife.inMilliseconds,
      );
      cell.utility; // triggers _decayInPlace
      // After exactly one half-life of decay at the standard rate,
      // counts should be at ~50% of their starting values.
      expect(cell.emitted, closeTo(50, 1));
      expect(cell.cited, closeTo(25, 1));
    });

    test('high variance accelerates decay (max ~2× faster)', () {
      // Construct a cell whose Welford state shows max variance
      // (samples at 0 and 1 alternating → variance ≈ 0.25).
      // After one half-life, variance-modulated decay should leave
      // counts at ~25% (not 50%) because effective half-life halved.
      final cell = LogosSseCell(
        emitted: 100,
        cited: 50,
        lastUpdateMs: DateTime.now().millisecondsSinceEpoch -
            LogosSseCell.halfLife.inMilliseconds,
        utilitySampleCount: 4,
        utilitySampleMean: 0.5,
        // For samples [0, 1, 0, 1] with mean 0.5: sumSq = 4·0.25 = 1.0
        // variance = 1.0 / (4-1) = 0.333... but capped at 0.25 by the
        // bound. Use a value just under to avoid overshoot.
        utilitySampleSumSq: 0.75, // variance = 0.25 (max)
      );
      cell.utility;
      // accelerationFactor = 1 + 0.25/0.25 = 2
      // effective half-life = halfLife / 2
      // After one full halfLife of wall-clock time, decayed by 2^2 = 4×
      // → counts at ~25%
      expect(cell.emitted, closeTo(25, 2));
      expect(cell.cited, closeTo(12.5, 2));
    });

    test('Welford updates on snapshot — variance grows with spread', () {
      final cell = LogosSseCell(emitted: 10, cited: 5);
      // Sample 1: utility = 0.5
      cell.snapshotUtilityForTesting();
      expect(cell.utilityVariance, 0.0);
      // Add evidence with shifted ratio — utility moves up.
      cell.cited += 5; // now 10/10 → utility = 1.0
      cell.snapshotUtilityForTesting();
      // 2 samples: 0.5 and 1.0; variance = ((0.5-0.75)² + (1.0-0.75)²) / 1 = 0.125
      expect(cell.utilityVariance, closeTo(0.125, 1e-3));
    });

    test('JSON round-trip preserves Welford state', () {
      final cell = LogosSseCell(
        emitted: 50,
        cited: 30,
        utilitySampleCount: 7,
        utilitySampleMean: 0.6,
        utilitySampleSumSq: 0.42,
      );
      final restored = LogosSseCell.fromJson(cell.toJson());
      expect(restored.utilitySampleCount, 7);
      expect(restored.utilitySampleMean, closeTo(0.6, 1e-3));
      expect(restored.utilitySampleSumSq, closeTo(0.42, 1e-3));
      expect(restored.utilityVariance, closeTo(0.42 / 6, 1e-3));
    });
  });
}
