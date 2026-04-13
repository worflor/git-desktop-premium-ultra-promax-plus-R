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
}
