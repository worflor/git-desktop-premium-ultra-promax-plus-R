// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Law-based coverage for lib/backend/semantic_manifest.dart — the
// pre-computed commit-story builder that sits above the packed diff in
// AI prompts. Everything here is pure (buildSemanticManifest takes a
// List<HunkRanking> + optional FileCouplingMatrix and returns a plain
// data object), so no widget pumping / git / disk is needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_hunks.dart';
import 'package:git_desktop/backend/semantic_manifest.dart';

DiffHunk _hunk({
  required String filePath,
  required String body,
  int hunkIndex = 0,
  int oldStart = 1,
  int newStart = 1,
}) {
  final adds = body.split('\n').where((l) => l.startsWith('+') && !l.startsWith('+++')).length;
  final dels = body.split('\n').where((l) => l.startsWith('-') && !l.startsWith('---')).length;
  return DiffHunk(
    filePath: filePath,
    hunkIndex: hunkIndex,
    header: body.split('\n').first,
    body: body,
    oldStart: oldStart,
    newStart: newStart,
    additions: adds,
    deletions: dels,
  );
}

HunkRanking _ranking(
  DiffHunk hunk, {
  required double phi,
  required int rank,
  String? wellName,
}) =>
    HunkRanking(hunk: hunk, phi: phi, rank: rank, wellName: wellName);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildSemanticManifest — empty input', () {
    test('produces an empty-ish manifest', () {
      final m = buildSemanticManifest(const []);
      expect(m.isEmpty, isTrue);
      expect(m.filesTouched, 0);
      expect(m.totalHunks, 0);
      expect(m.themes, isEmpty);
      expect(m.moves, isEmpty);
      expect(m.crossFileMoves, isEmpty);
      expect(m.additionsByFile, isEmpty);
      expect(m.removalsByFile, isEmpty);
      expect(m.couplingPairs, isEmpty);
      expect(m.touchedCoherence, isNull);
      expect(m.topHunks, isEmpty);
      expect(m.idfAvailable, isFalse);
    });

    test('toPromptXml renders exactly the header + empty counts', () {
      final m = buildSemanticManifest(const []);
      const explanation =
          'Pre-computed by the logos diffusion + engram semantic engines. '
          'Trust these findings over your own reading of the raw diff below for '
          'add / remove / move claims — the diff may split a single move across '
          'distant hunks.';
      expect(
        m.toPromptXml(),
        '<semantic_manifest>\n'
        '$explanation\n'
        '\n'
        'Files touched: 0 | Hunks: 0\n'
        '</semantic_manifest>',
      );
    });
  });

  group('debugTokensFromHunk — tokenisation', () {
    test('extracts identifiers only from +/- lines, never context/metadata', () {
      final h = _hunk(
        filePath: 'lib/foo.dart',
        body: '@@ -1,2 +1,2 @@\n'
            '--- a/lib/foo.dart\n'
            '+++ b/lib/foo.dart\n'
            ' unchangedContextToken here\n'
            '-  removedOnlyToken();\n'
            '+  addedOnlyToken();\n',
      );
      final t = debugTokensFromHunk(h);
      expect(t.added, {'addedOnlyToken'});
      expect(t.removed, {'removedOnlyToken'});
      // Context line + the `---`/`+++` metadata lines contribute nothing.
      expect(t.added, isNot(contains('unchangedContextToken')));
      expect(t.removed, isNot(contains('unchangedContextToken')));
    });

    test('filters skip-listed keywords and sub-3-char tokens', () {
      final h = _hunk(
        filePath: 'lib/foo.dart',
        body: '@@ -1,1 +1,1 @@\n'
            '+  final int ab = myRealToken;\n',
      );
      final t = debugTokensFromHunk(h);
      // 'final' and 'int' are skip-listed; 'ab' is below the 3-char floor.
      expect(t.added, {'myRealToken'});
    });
  });

  group('buildSemanticManifest — single-file additions', () {
    test('a pure addition lands in additionsByFile, themes, and topHunks', () {
      final hunk = _hunk(
        filePath: 'lib/foo.dart',
        body: '@@ -1,1 +1,2 @@\n'
            ' unchanged context line\n'
            '+  final myNewToken = 1;\n',
      );
      final ranking = _ranking(hunk, phi: 0.8, rank: 0, wellName: 'alpha');
      final m = buildSemanticManifest([ranking]);

      expect(m.filesTouched, 1);
      expect(m.totalHunks, 1);
      expect(m.additionsByFile, {
        'lib/foo.dart': ['myNewToken'],
      });
      expect(m.removalsByFile, isEmpty);
      expect(m.moves, isEmpty);
      expect(m.crossFileMoves, isEmpty);

      expect(m.themes, hasLength(1));
      expect(m.themes.single.wellName, 'alpha');
      expect(m.themes.single.hunkCount, 1);
      expect(m.themes.single.massFraction, 1.0);

      expect(m.topHunks, hasLength(1));
      expect(m.topHunks.single.rank, 0);
      expect(m.topHunks.single.phi, 0.8);
      expect(m.topHunks.single.wellName, 'alpha');
      expect(m.topHunks.single.filePath, 'lib/foo.dart');
      expect(m.topHunks.single.oldStart, 1);
      expect(m.topHunks.single.newStart, 1);
    });

    test('toPromptXml only renders non-empty sections', () {
      final hunk = _hunk(
        filePath: 'lib/foo.dart',
        body: '@@ -1,1 +1,2 @@\n+  final onlyAdditionToken = 1;\n',
      );
      final m = buildSemanticManifest([_ranking(hunk, phi: 0.5, rank: 0)]);
      final xml = m.toPromptXml();
      expect(xml, contains('Additions ('));
      expect(xml, contains('onlyAdditionToken'));
      expect(xml, isNot(contains('Themes (')));
      expect(xml, isNot(contains('Moves within-file')));
      expect(xml, isNot(contains('Moves cross-file')));
      expect(xml, isNot(contains('Removals (')));
      expect(xml, isNot(contains('Historical coupling')));
      expect(xml, isNot(contains('Touched-set coherence')));
    });
  });

  group('buildSemanticManifest — within-file moves', () {
    test('a token added AND removed in the same file is a move, not add+remove', () {
      final hunk = _hunk(
        filePath: 'lib/bar.dart',
        body: '@@ -1,2 +1,2 @@\n'
            '-fooToken barToken\n'
            '+barToken fooToken\n',
      );
      final m = buildSemanticManifest([_ranking(hunk, phi: 0.4, rank: 0)]);

      expect(m.moves.map((e) => e.token).toSet(), {'fooToken', 'barToken'});
      for (final move in m.moves) {
        expect(move.filePath, 'lib/bar.dart');
      }
      // Fully absorbed by the move — must not double-appear as an add/remove.
      expect(m.additionsByFile.containsKey('lib/bar.dart'), isFalse);
      expect(m.removalsByFile.containsKey('lib/bar.dart'), isFalse);
      expect(m.crossFileMoves, isEmpty);
    });
  });

  group('buildSemanticManifest — cross-file moves', () {
    test('removed-in-A + added-in-B reunifies into a crossFileMoves entry', () {
      final hunkA = _hunk(
        filePath: 'lib/a.dart',
        body: '@@ -1,1 +1,0 @@\n-  movedSymbolToken();\n',
      );
      final hunkB = _hunk(
        filePath: 'lib/b.dart',
        body: '@@ -0,0 +1,1 @@\n+  movedSymbolToken();\n',
      );
      final m = buildSemanticManifest([
        _ranking(hunkA, phi: 0.5, rank: 0),
        _ranking(hunkB, phi: 0.5, rank: 1),
      ]);

      expect(m.crossFileMoves, hasLength(1));
      final move = m.crossFileMoves.single;
      expect(move.token, 'movedSymbolToken');
      expect(move.fromFiles, ['lib/a.dart']);
      expect(move.toFiles, ['lib/b.dart']);

      // The migrated token is subtracted from both sides' plain
      // add/remove sections — no double-narration.
      expect(m.additionsByFile.containsKey('lib/b.dart'), isFalse);
      expect(m.removalsByFile.containsKey('lib/a.dart'), isFalse);
      expect(m.moves, isEmpty);

      final xml = m.toPromptXml();
      expect(xml, contains('Moves cross-file'));
      expect(xml, contains('movedSymbolToken'));
      expect(xml, contains('from: lib/a.dart'));
      expect(xml, contains('to:   lib/b.dart'));
    });
  });

  group('buildSemanticManifest — historical coupling', () {
    FileCouplingMatrix matrix() => FileCouplingMatrix(
          jaccard: const {
            'a.dart': {'b.dart': 0.9, 'c.dart': 0.1},
            'b.dart': {'c.dart': 0.05},
          },
          headHash: 'head',
          commitsAnalyzed: 1000,
        );

    List<HunkRanking> rankings() => [
          _ranking(
            _hunk(filePath: 'a.dart', body: '@@ -1,1 +1,1 @@\n+  final aOnlyToken = 1;\n'),
            phi: 0.3,
            rank: 0,
          ),
          _ranking(
            _hunk(filePath: 'b.dart', body: '@@ -1,1 +1,1 @@\n+  final bOnlyToken = 1;\n'),
            phi: 0.3,
            rank: 1,
          ),
          _ranking(
            _hunk(filePath: 'c.dart', body: '@@ -1,1 +1,1 @@\n+  final cOnlyToken = 1;\n'),
            phi: 0.3,
            rank: 2,
          ),
        ];

    test('only pairs at/above the 0.25 floor surface, sorted by jaccard desc', () {
      final m = buildSemanticManifest(rankings(), couplingMatrix: matrix());
      expect(m.couplingPairs, hasLength(1));
      final pair = m.couplingPairs.single;
      expect(pair.fileA, 'a.dart');
      expect(pair.fileB, 'b.dart');
      expect(pair.jaccard, closeTo(0.9, 1e-9));
    });

    test('touchedCoherence is the confidence-weighted mean pairwise score', () {
      final m = buildSemanticManifest(rankings(), couplingMatrix: matrix());
      // raw mean of {0.9, 0.1, 0.05} = 0.35; commitsAnalyzed=1000 saturates
      // confidence to 1.0 (sat = max(50, 3*0.4) = 50), so the result is the
      // raw mean unshifted: 0.5 + (0.35 - 0.5) * 1.0 = 0.35.
      expect(m.touchedCoherence, closeTo(0.35, 1e-9));
    });

    test('touchedCoherence and couplingPairs are absent with no matrix', () {
      final m = buildSemanticManifest(rankings());
      expect(m.touchedCoherence, isNull);
      expect(m.couplingPairs, isEmpty);
    });
  });

  group('buildSemanticManifest — per-file token cap', () {
    test('additionsByFile caps at 15 tokens, alphabetical tiebreak on equal score', () {
      final tokens = List<String>.generate(20, (i) => 'zTok${i.toString().padLeft(2, '0')}');
      final body = StringBuffer('@@ -1,1 +1,20 @@\n');
      for (final t in tokens) {
        body.writeln('+  final $t = 1;');
      }
      final hunk = _hunk(filePath: 'lib/many.dart', body: body.toString());
      final m = buildSemanticManifest([_ranking(hunk, phi: 0.2, rank: 0)]);

      final kept = m.additionsByFile['lib/many.dart'];
      expect(kept, isNotNull);
      expect(kept, hasLength(15));
      // Every token appears exactly once (equal score) -> pure alphabetical.
      expect(kept, tokens.sublist(0, 15));
    });
  });

  group('buildSemanticManifest — determinism', () {
    test('same rankings always produce the same rendered manifest', () {
      final hunk = _hunk(
        filePath: 'lib/foo.dart',
        body: '@@ -1,1 +1,2 @@\n+  final stableToken = 1;\n',
      );
      final a = buildSemanticManifest([_ranking(hunk, phi: 0.7, rank: 0, wellName: 'w')]);
      final b = buildSemanticManifest([_ranking(hunk, phi: 0.7, rank: 0, wellName: 'w')]);
      expect(a.toPromptXml(), b.toPromptXml());
    });
  });
}
