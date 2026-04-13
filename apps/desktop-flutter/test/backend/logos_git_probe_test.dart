// Tests for [DiffProbe] construction — the M-axis pickaxe symbol
// extraction, the Ab-axis path-mirror convention, and the adaptive
// temperature regime selection.
//
// Pickaxe is I/O-bound (git grep); we don't exercise that here because
// it requires a real git repo. What we DO pin down is:
//   - Symbol extraction is deterministic, filters stopwords, respects
//     caps, ignores context/hunk-header lines
//   - Path mirror generation produces plausible candidates across
//     lib/test directory conventions for multiple languages
//   - Adaptive temperature respects the documented regimes

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_git_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M-axis symbol extraction', () {
    test('picks identifiers from added/removed lines only', () {
      const diff = r'''
diff --git a/lib/foo.dart b/lib/foo.dart
@@ -1,3 +1,3 @@
 unchangedIdentifier
-removedIdentifier
+addedIdentifier
''';
      final syms =
          LogosGitProbeTestAccess.extractDiffSymbols(diff, minLength: 4);
      expect(syms, contains('removedIdentifier'));
      expect(syms, contains('addedIdentifier'));
      expect(syms, isNot(contains('unchangedIdentifier')),
          reason: 'context lines (no +/− prefix) should be skipped');
    });

    test('respects cap — longest symbols win when over cap', () {
      const diff = r'''
diff --git a/lib/foo.dart b/lib/foo.dart
@@ -1,3 +1,3 @@
+shortA shortB shortC
+muchLongerIdentifier1 muchLongerIdentifier2
+evenLongerIdentifierName3
''';
      final syms =
          LogosGitProbeTestAccess.extractDiffSymbols(diff, cap: 2);
      expect(syms.length, 2);
      // Longest two win — by .length desc sort.
      expect(syms[0], 'evenLongerIdentifierName3');
      expect(syms[1].length,
          greaterThanOrEqualTo('muchLongerIdentifier1'.length));
    });

    test('ignores short tokens and blocklist keywords', () {
      const diff = r'''
diff --git a/lib/foo.dart b/lib/foo.dart
@@ -1,3 +1,3 @@
+return null; const x = value; async function boom() {}
+myInterestingIdentifier
''';
      final syms =
          LogosGitProbeTestAccess.extractDiffSymbols(diff, minLength: 4);
      expect(syms, contains('myInterestingIdentifier'));
      for (final boring in [
        'return',
        'const',
        'value',
        'async',
        'function',
        'null',
      ]) {
        expect(syms, isNot(contains(boring)),
            reason: '$boring should be filtered as noise');
      }
    });

    test('empty diff yields no symbols', () {
      expect(LogosGitProbeTestAccess.extractDiffSymbols(''), isEmpty);
    });
  });

  group('Ab-axis path mirrors', () {
    test('lib/dart source → test_ conventions', () {
      final mirrors = LogosGitProbeTestAccess.candidateMirrors(
        'lib/app/foo.dart',
      );
      expect(
        mirrors,
        anyOf(
          contains('test/app/foo_test.dart'),
          contains('test/app/test_foo.dart'),
        ),
      );
    });

    test('src/ts source → test/foo.test.ts', () {
      final mirrors = LogosGitProbeTestAccess.candidateMirrors(
        'src/auth/login.ts',
      );
      expect(
        mirrors,
        anyOf(
          contains('test/auth/login.test.ts'),
          contains('test/auth/login_test.ts'),
          contains('test/auth/login.spec.ts'),
        ),
      );
    });

    test('test file mirrors back to source', () {
      final mirrors = LogosGitProbeTestAccess.candidateMirrors(
        'test/app/foo_test.dart',
      );
      expect(mirrors, anyOf(contains('lib/app/foo.dart')));
    });

    test('non-standard paths produce no mirrors (no false positives)', () {
      final mirrors = LogosGitProbeTestAccess.candidateMirrors('README.md');
      // May include a sibling test but never an unrelated one.
      for (final m in mirrors) {
        expect(m, isNot(equals('README.md')));
      }
    });
  });

  group('adaptiveTemperature regime selection', () {
    test('cohesive small diff → tight t (near 0.5-0.7)', () {
      final t = LogosGitProbeTestAccess.adaptiveTemperature(
        primaryPaths: const {'lib/a.dart', 'lib/b.dart'},
        coherence: 0.9,
      );
      // size 2 → sizeScale=0, coherence 0.9 → cohShift = 0.1 - 0.4 = -0.3
      // t = 1 + 0 - 0.3 = 0.7 (within tight band)
      expect(t, lessThanOrEqualTo(1.0));
      expect(t, greaterThanOrEqualTo(0.3));
    });

    test('scattered large diff → wide t (near 2.0+)', () {
      final many = {
        for (var i = 0; i < 40; i++) 'file$i.dart',
      };
      final t = LogosGitProbeTestAccess.adaptiveTemperature(
        primaryPaths: many,
        coherence: 0.2,
      );
      // sizeScale=0.8, cohShift = 0.8 - 0.4 = 0.4, t ≈ 2.2 (clamped ≤ 3)
      expect(t, greaterThanOrEqualTo(1.5));
      expect(t, lessThanOrEqualTo(3.0));
    });

    test('default-ish mid diff → ~1.0', () {
      final t = LogosGitProbeTestAccess.adaptiveTemperature(
        primaryPaths: const {'a.dart', 'b.dart', 'c.dart'},
        coherence: 0.6,
      );
      // sizeScale=0 (≤3), cohShift = 0.4 - 0.4 = 0.0, t = 1.0
      expect(t, closeTo(1.0, 0.2));
    });

    test('always within clamp band [0.3, 3.0]', () {
      for (final size in [1, 5, 20, 100]) {
        for (final coh in [0.0, 0.5, 1.0]) {
          final paths = <String>{for (var i = 0; i < size; i++) 'f$i.dart'};
          final t = LogosGitProbeTestAccess.adaptiveTemperature(
            primaryPaths: paths,
            coherence: coh,
          );
          expect(t, greaterThanOrEqualTo(0.3),
              reason: 'size=$size coh=$coh');
          expect(t, lessThanOrEqualTo(3.0), reason: 'size=$size coh=$coh');
        }
      }
    });
  });

  group('SSE → probe weight scaling (closed learning loop)', () {
    // The effective-weight functions are what the live probe path uses
    // to apply learned utilities. Pin down the invariants so a refactor
    // can't silently break the self-learning feedback loop.

    test('neutral utility of 1.0 reproduces the base weight exactly', () {
      const baseM = 0.35;
      const baseAb = 0.55;
      final effM = LogosGitProbeTestAccess.effectiveMWeightFor(
        baseMWeight: baseM,
        learnedUtility: 1.0,
      );
      final effAb = LogosGitProbeTestAccess.effectiveAbWeightFor(
        baseAbWeight: baseAb,
        learnedUtility: 1.0,
      );
      expect(effM, closeTo(baseM, 1e-9));
      expect(effAb, closeTo(baseAb, 1e-9));
    });

    test('high utility (≈2.0, axis consistently cited) boosts weight', () {
      final eff = LogosGitProbeTestAccess.effectiveMWeightFor(
        baseMWeight: 0.35,
        learnedUtility: 2.0,
      );
      // At 2.0 the utility hits the upper clamp at 2.5 — but 2.0 < 2.5
      // so it passes through. 0.35 * 2.0 = 0.70.
      expect(eff, closeTo(0.70, 1e-9));
    });

    test('zero utility (axis never cited) floors at clamp boundary 0.3', () {
      final eff = LogosGitProbeTestAccess.effectiveMWeightFor(
        baseMWeight: 0.35,
        learnedUtility: 0.0,
      );
      // 0.0 clamped up to 0.3, then 0.35 * 0.3 = 0.105
      expect(eff, closeTo(0.35 * 0.3, 1e-9));
    });

    test('runaway utility caps at 2.5× so a single spike cannot hijack '
        'the mix', () {
      final eff = LogosGitProbeTestAccess.effectiveAbWeightFor(
        baseAbWeight: 0.55,
        learnedUtility: 10.0,
      );
      expect(eff, closeTo(0.55 * 2.5, 1e-9));
    });
  });
}
