// Tests for logos_diff_attention.dart — the adaptive LOD hunk
// compactor. One algorithm, every scale. Pins the invariants:
//
//   1. Tiny diff → every hunk renders at L4 full (no compression).
//   2. Output never exceeds budget, whatever the input size.
//   3. Every hunk is accounted for: admitted + clustered = total.
//      Nothing is silently discarded.
//   4. Body-rewrite hunks (symbols shared across +/−) rise naturally
//      under the refactor-jaccard boost — they get richer tiers than
//      size-equivalent additive hunks, without any hard floor.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_diff_attention.dart';
import 'package:git_desktop/backend/logos_hunks.dart';

DiffHunk _mkHunk({
  required String path,
  required int hunkIndex,
  required int oldStart,
  required int newStart,
  required List<String> addLines,
  required List<String> delLines,
  List<String> contextLines = const [],
}) {
  final body = StringBuffer();
  body.writeln('@@ -$oldStart,${delLines.length + contextLines.length}'
      ' +$newStart,${addLines.length + contextLines.length} @@');
  for (final c in contextLines) {
    body.writeln(' $c');
  }
  for (final d in delLines) {
    body.writeln('-$d');
  }
  for (final a in addLines) {
    body.writeln('+$a');
  }
  return DiffHunk(
    filePath: path,
    hunkIndex: hunkIndex,
    header: '@@ -$oldStart,${delLines.length + contextLines.length}'
        ' +$newStart,${addLines.length + contextLines.length} @@',
    body: body.toString(),
    oldStart: oldStart,
    newStart: newStart,
    additions: addLines.length,
    deletions: delLines.length,
  );
}

HunkRanking _rank(DiffHunk h, double phi, int rank) =>
    HunkRanking(hunk: h, phi: phi, rank: rank);

void main() {
  group('compactHunksUnderBudget', () {
    test('tiny diff within generous budget → every hunk at L4 full', () {
      final h1 = _mkHunk(
        path: 'lib/foo.dart',
        hunkIndex: 0,
        oldStart: 10,
        newStart: 10,
        addLines: ['final x = 1;'],
        delLines: ['final x = 0;'],
      );
      final h2 = _mkHunk(
        path: 'lib/bar.dart',
        hunkIndex: 0,
        oldStart: 5,
        newStart: 5,
        addLines: ['return true;'],
        delLines: ['return false;'],
      );
      final result = compactHunksUnderBudget(
        rankings: [_rank(h1, 0.8, 0), _rank(h2, 0.6, 1)],
        budgetChars: 100000,
      );
      expect(result.admittedCount, 2);
      expect(result.clusteredCount, 0);
      for (final c in result.perHunk) {
        expect(c.lod, HunkLod.full);
      }
      expect(result.body, contains('final x = 1;'));
      expect(result.body, contains('return true;'));
    });

    test('output never exceeds budget across scales', () {
      final cases = [
        (hunkCount: 5, budget: 5000),
        (hunkCount: 50, budget: 4000),
        (hunkCount: 200, budget: 2500),
        (hunkCount: 1000, budget: 3000),
        (hunkCount: 5000, budget: 8000),
      ];
      for (final c in cases) {
        final hunks = <HunkRanking>[];
        for (var i = 0; i < c.hunkCount; i++) {
          final h = _mkHunk(
            path: 'lib/file_${i % 7}.dart',
            hunkIndex: i,
            oldStart: 100 + i * 10,
            newStart: 100 + i * 10,
            addLines: ['added_alpha_$i = nextValue($i);'],
            delLines: ['removed_beta_$i = priorValue($i);'],
            contextLines: ['context_gamma_$i'],
          );
          hunks.add(_rank(h, 1.0 - i / (c.hunkCount * 1.0), i));
        }
        final result = compactHunksUnderBudget(
          rankings: hunks,
          budgetChars: c.budget,
        );
        expect(result.renderedChars, lessThanOrEqualTo(c.budget),
            reason:
                'scale=${c.hunkCount} budget=${c.budget} got=${result.renderedChars}');
        expect(result.admittedCount + result.clusteredCount, c.hunkCount,
            reason: 'no hunk silently discarded at scale=${c.hunkCount}');
      }
    });

    test('body-rewrite hunk naturally outranks a plain-add peer of same size',
        () {
      // Two hunks with similar byte count and equal φ, but one is a
      // body-rewrite (paintWell appears on both + and −) and one is
      // a pure addition (no overlap).
      final rewrite = _mkHunk(
        path: 'lib/a.dart',
        hunkIndex: 0,
        oldStart: 1,
        newStart: 1,
        addLines: ['Color paintWell(String name) => sharedColour(name);'],
        delLines: [
          'Color paintWell(String name) {',
          '  return wellColourFromHash(name);',
          '}',
        ],
      );
      final plainAdd = _mkHunk(
        path: 'lib/b.dart',
        hunkIndex: 0,
        oldStart: 1,
        newStart: 1,
        addLines: [
          'int freshThing = calcFresh();',
          'List<int> freshList = buildList();',
          'void freshRun() => freshDo();',
        ],
        delLines: const [],
      );
      // Budget tight enough to force differentiated tiers.
      final result = compactHunksUnderBudget(
        rankings: [_rank(rewrite, 0.5, 0), _rank(plainAdd, 0.5, 1)],
        budgetChars: 450,
      );
      final rewriteRender =
          result.perHunk.where((c) => c.hunk == rewrite).toList();
      final plainRender =
          result.perHunk.where((c) => c.hunk == plainAdd).toList();
      // Rewrite tier index ≥ plain tier index — rewrite got at least
      // as rich a rendering as the peer despite equal φ.
      final rewriteTier = rewriteRender.isNotEmpty
          ? rewriteRender.single.lod.index
          : HunkLod.clustered.index;
      final plainTier = plainRender.isNotEmpty
          ? plainRender.single.lod.index
          : HunkLod.clustered.index;
      expect(rewriteTier, greaterThanOrEqualTo(plainTier),
          reason:
              'body-rewrite boost should elevate rewrite tier ≥ plain-add tier');
    });

    test('deterministic emission order: files alphabetical, hunks by index',
        () {
      final hB1 = _mkHunk(
        path: 'lib/b.dart',
        hunkIndex: 1,
        oldStart: 20,
        newStart: 20,
        addLines: ['alphaAdd_1'],
        delLines: ['alphaDel_1'],
      );
      final hB0 = _mkHunk(
        path: 'lib/b.dart',
        hunkIndex: 0,
        oldStart: 10,
        newStart: 10,
        addLines: ['alphaAdd_0'],
        delLines: ['alphaDel_0'],
      );
      final hA = _mkHunk(
        path: 'lib/a.dart',
        hunkIndex: 0,
        oldStart: 5,
        newStart: 5,
        addLines: ['aPureAdd'],
        delLines: ['aPureDel'],
      );
      final result = compactHunksUnderBudget(
        rankings: [
          _rank(hB1, 0.9, 0),
          _rank(hA, 0.5, 1),
          _rank(hB0, 0.3, 2),
        ],
        budgetChars: 100000,
      );
      final aIdx = result.body.indexOf('lib/a.dart');
      final bIdx = result.body.indexOf('lib/b.dart');
      expect(aIdx, greaterThan(-1));
      expect(bIdx, greaterThan(aIdx),
          reason: 'files emit alphabetically regardless of φ rank');
      final b0Idx = result.body.indexOf('alphaAdd_0');
      final b1Idx = result.body.indexOf('alphaAdd_1');
      expect(b0Idx, greaterThan(-1));
      expect(b1Idx, greaterThan(-1));
      expect(b0Idx, lessThan(b1Idx),
          reason: 'hunk index 0 emits before hunk index 1 within a file');
    });

    test('zero-size budget → empty body, no throws', () {
      final h = _mkHunk(
        path: 'lib/x.dart',
        hunkIndex: 0,
        oldStart: 1,
        newStart: 1,
        addLines: ['a'],
        delLines: ['b'],
      );
      final result = compactHunksUnderBudget(
        rankings: [_rank(h, 0.5, 0)],
        budgetChars: 0,
      );
      expect(result.body, '');
      expect(result.perHunk, isEmpty);
      expect(result.clustered, isEmpty);
    });

    test('cluster line carries emergent topology digest', () {
      final hunks = <HunkRanking>[];
      for (var i = 0; i < 30; i++) {
        final h = _mkHunk(
          path: 'lib/mega.dart',
          hunkIndex: i,
          oldStart: 1 + i * 2,
          newStart: 1 + i * 2,
          addLines: ['trivialAdd_$i'],
          delLines: ['trivialDel_$i'],
        );
        hunks.add(HunkRanking(
          hunk: h,
          phi: 0.01 + i / 10000.0,
          rank: i,
          transportPull: 0.25,
          innovationResidual: 0.40,
          wellName: 'computing',
        ));
      }
      final result = compactHunksUnderBudget(
        rankings: hunks,
        budgetChars: 400,
      );
      expect(result.renderedChars, lessThanOrEqualTo(400));
      // Cluster line exists and carries the algorithmic digest fields.
      expect(result.body, contains('<!-- cluster'));
      expect(result.body, contains('hunks='));
      expect(result.body, contains('phi_max='));
      expect(result.body, contains('phi_sum='));
      expect(result.body, contains('transport_max='));
      expect(result.body, contains('residual_max='));
      expect(result.body, contains('wells=computing'));
      expect(result.admittedCount + result.clusteredCount, 30);
    });
  });
}
