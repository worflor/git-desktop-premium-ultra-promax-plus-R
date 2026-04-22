// Unit tests for the repo-summary building blocks.
//
// These test modules that take structured inputs and produce
// deterministic outputs — no git process, no filesystem, no engram
// assets. Full-pipeline behavior is covered by smoke_test.dart.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_git_integrity.dart' show TransportRoles;
import 'package:git_desktop/backend/repo_summary/assembler.dart';
import 'package:git_desktop/backend/repo_summary/curves.dart';
import 'package:git_desktop/backend/repo_summary/naming.dart';
import 'package:git_desktop/backend/repo_summary/prose.dart';
import 'package:git_desktop/backend/repo_summary/purpose.dart';
import 'package:git_desktop/backend/repo_summary/types.dart';

HarvestedFile _harvested(String path, String text) {
  final offsets = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) offsets.add(i + 1);
  }
  offsets.add(text.length);
  return HarvestedFile(
    path: path,
    text: text,
    lineOffsets: Int32List.fromList(offsets),
  );
}

void main() {
  group('curves', () {
    test('kneeIndex on a sharp elbow', () {
      final xs = <double>[100, 95, 90, 85, 20, 19, 18, 17, 16];
      final idx = kneeIndex(xs);
      expect(idx, inInclusiveRange(3, 5));
    });

    test('kneeIndex on a flat sequence keeps everything', () {
      final xs = <double>[5, 5, 5, 5, 5];
      expect(kneeIndex(xs), xs.length - 1);
    });

    test('maxGapIndex finds the largest forward difference', () {
      final xs = <double>[0.0, 0.01, 0.02, 0.5, 0.52, 0.54];
      final idx = maxGapIndex(xs, start: 0, end: xs.length);
      expect(idx, 2);
    });
  });

  group('naming', () {
    test('modal engram well wins tier 1', () {
      final regionPaths = <List<String>>[
        ['lib/a.dart', 'lib/b.dart', 'lib/c.dart'],
        ['lib/x.dart', 'lib/y.dart'],
      ];
      // Region 0 is dominated by the "spectral-math" well; region 1
      // by "ui-rendering". Naming should surface both names verbatim.
      final wellByPath = <String, String>{
        'lib/a.dart': 'spectral-math',
        'lib/b.dart': 'spectral-math',
        'lib/c.dart': 'ui-rendering',
        'lib/x.dart': 'ui-rendering',
        'lib/y.dart': 'ui-rendering',
      };
      final rolesByPath = <String, TransportRoles>{
        for (final p in ['lib/a.dart', 'lib/b.dart', 'lib/c.dart',
                         'lib/x.dart', 'lib/y.dart'])
          p: TransportRoles.of(p),
      };
      final names = nameRegions(
        regionPaths: regionPaths,
        wellByPath: wellByPath,
        rolesByPath: rolesByPath,
      );
      // Greedy assignment: region 1 has coverage 3/3 = 100% for
      // ui-rendering so it claims it first; region 0 has 2/3 for
      // spectral-math so it takes that.
      expect(names[0], 'spectral-math');
      expect(names[1], 'ui-rendering');
    });

    test('falls back to transport concept when no wells', () {
      final regionPaths = <List<String>>[
        ['lib/auth/model.dart', 'lib/auth/service.dart'],
      ];
      final names = nameRegions(
        regionPaths: regionPaths,
        wellByPath: const {},
        rolesByPath: <String, TransportRoles>{
          for (final p in regionPaths[0]) p: TransportRoles.of(p),
        },
      );
      // Both files share a concept: seed key derived from the basename
      // tokens; the label's body is that concept.
      expect(names[0], isNotEmpty);
      expect(names[0].startsWith('region'), isFalse);
    });

    test('filename-concept tier preserves source order', () {
      // All files share `logos_git_` prefix — this is the ordered
      // concept prior, NOT the engine's alphabetical seed.
      final regionPaths = <List<String>>[
        ['lib/logos_git_probe.dart',
         'lib/logos_git_stats.dart',
         'lib/logos_git_resolver.dart'],
      ];
      final names = nameRegions(
        regionPaths: regionPaths,
        wellByPath: const {},
        rolesByPath: <String, TransportRoles>{
          for (final p in regionPaths[0]) p: TransportRoles.of(p),
        },
      );
      expect(names[0], 'logos_git_');
    });

    test('positional fallback when engine and filename both decline', () {
      // Paths with no word characters at all — the filename tokenizer
      // produces empty lists for each, and the engine's seedKey is
      // null, so everything falls through to the positional tier.
      final regionPaths = <List<String>>[
        ['...'],
      ];
      final names = nameRegions(
        regionPaths: regionPaths,
        wellByPath: const {},
        rolesByPath: <String, TransportRoles>{
          '...': TransportRoles.of('...'),
        },
      );
      expect(names[0], 'region 1');
    });
  });

  group('purpose', () {
    test('extracts leading // comment above imports', () {
      final file = _harvested(
        'engram_bootstrap.dart',
        '// engram_bootstrap.dart — singleton provider.\n'
        '//\n'
        "import 'dart:async';\n"
        '\n'
        'class Foo {}\n',
      );
      final p = extractPurpose(file);
      expect(p, contains('singleton provider'));
    });

    test('extracts /// doc above first declaration', () {
      final file = _harvested(
        'undo_controller.dart',
        "import 'dart:async';\n"
        '\n'
        '/// Classifies pending actions.\n'
        'enum UndoActionKind { commit }\n',
      );
      final p = extractPurpose(file);
      expect(p, contains('Classifies pending actions'));
    });

    test('extracts real engram_bootstrap comment', () {
      // Real file head copied in. Verifies the extractor handles
      // multi-line // blocks with blank-body lines intermixed.
      final file = _harvested(
        'engram_bootstrap.dart',
        '// engram_bootstrap.dart — singleton provider + isolate-safe snapshot.\n'
        '//\n'
        '// The brain + glove assets are loaded once per app launch (via\n'
        '// rootBundle). The encoder is fairly expensive to construct because of\n'
        '// the ~12MB GloVe vector table, so we memoise behind a future and hand\n'
        '// out the same [EngramHunkEncoder] everywhere.\n'
        '//\n'
        '\n'
        "import 'dart:async';\n"
        '\n'
        'class EngramAssets {}\n',
      );
      final p = extractPurpose(file);
      expect(p, contains('singleton provider'),
          reason: 'leading // block must win over class decl name');
    });

    test('handles CRLF line endings', () {
      final file = _harvested(
        'foo.dart',
        '// foo.dart — the point.\r\n'
        '//\r\n'
        '// details follow.\r\n'
        '\r\n'
        'class Foo {}\r\n',
      );
      final p = extractPurpose(file);
      expect(p, contains('the point'));
    });

    test('falls back to declaration name when no doc comment', () {
      final file = _harvested(
        'foo.dart',
        "import 'x.dart';\n"
        'class MyWidget {}\n',
      );
      final p = extractPurpose(file);
      expect(p, 'MyWidget');
    });
  });

  group('prose', () {
    test('elevatorPitch synthesis with zero regions', () {
      final out = synthesiseElevatorPitch(
        repoName: 'r', topRegionNames: const [], activeFileCount: 4,
      );
      expect(out, contains('4 active files'));
    });

    test('regionBody renders file count and core count, no physics', () {
      final body = regionBody(
        name: 'x',
        fileCount: 5,
        backboneFileCount: 2,
        themes: const ['auth', 'session'],
      );
      expect(body, contains('5 files'));
      expect(body, contains('core'));
      expect(body, isNot(contains('%')));
      expect(body, isNot(contains('cohesion')));
      expect(body, isNot(contains('centrality')));
    });

    test('regionBody surfaces common directory when present', () {
      final body = regionBody(
        name: 'x',
        fileCount: 3,
        backboneFileCount: 0,
        themes: const [],
        commonDirectory: 'apps/desktop/src-tauri/',
      );
      expect(body, contains('apps/desktop/src-tauri/'));
    });
  });

  group('renderer', () {
    test('deterministic and emits the expected skeleton', () {
      final doc = RepoDoc(
        repoName: 'test-repo',
        elevatorPitch: 'Pitch.',
        shape: 'Modular codebase: several cohesive regions.',
        glance: const RepoStatsGlance(
          activeFileCount: 2,
          activeLines: 10,
          activeBytes: 200,
          roles: [MapEntry('source', 2)],
          dormantSkipped: 0,
        ),
        backbone: const [
          BackboneEntry(
            path: 'a.dart',
            lineCount: 120,
            regionName: 'core',
            purpose: 'Entry point.',
          ),
        ],
        regions: const [
          RegionDoc(
            id: 0,
            name: 'core',
            body: 'Two files.',
            paths: ['a.dart', 'b.dart'],
            neighborNames: [],
            fileCount: 2,
            themes: [],
          ),
        ],
        gettingStarted: '',
        generatedAt: DateTime.utc(2026, 4, 20, 12, 0, 0),
        totalHarvested: 2,
      );
      final a = renderMarkdown(doc);
      final b = renderMarkdown(doc);
      expect(a, b);
      expect(a, contains('# test-repo'));
      expect(a, contains('## Shape'));
      expect(a, contains('Modular codebase'));
      expect(a, contains('## At a glance'));
      expect(a, contains('## Core'));
      expect(a, contains('Entry point.'));
      expect(a, contains('## Regions'));
      expect(a, contains('### core'));
      expect(a, contains('Roles — source: 2'));
      expect(a, contains('generated 2026-04-20T12:00:00.000Z'));
      expect(a, contains('<!--'));
      expect(a, isNot(contains('centrality ')));
      expect(a, isNot(contains('Cohesion ')));
      expect(a, isNot(contains('knee')));
      expect(a, isNot(contains('omitted'))); // reframed phrasing
    });

    test('renderer skips Core section when backbone is empty', () {
      final doc = RepoDoc(
        repoName: 'thin',
        elevatorPitch: '',
        shape: '',
        glance: const RepoStatsGlance(
          activeFileCount: 1,
          activeLines: 5,
          activeBytes: 50,
          roles: [],
          dormantSkipped: 0,
        ),
        backbone: const [],
        regions: const [
          RegionDoc(
            id: 0,
            name: 'only',
            body: 'One file.',
            paths: ['a.dart'],
            neighborNames: [],
            fileCount: 1,
            themes: [],
          ),
        ],
        gettingStarted: '',
        generatedAt: DateTime.utc(2026, 1, 1),
        totalHarvested: 1,
      );
      final md = renderMarkdown(doc);
      expect(md, isNot(contains('## Core')));
      expect(md, contains('### only'));
    });

    test('renderer surfaces history-starved caveat', () {
      final doc = RepoDoc(
        repoName: 'fresh',
        elevatorPitch: '',
        shape: '',
        glance: const RepoStatsGlance(
          activeFileCount: 5,
          activeLines: 200,
          activeBytes: 2000,
          roles: [MapEntry('source', 5)],
          dormantSkipped: 0,
        ),
        backbone: const [],
        regions: const [],
        gettingStarted: '',
        generatedAt: DateTime.utc(2026, 1, 1),
        totalHarvested: 5,
        historyStarved: true,
      );
      final md = renderMarkdown(doc);
      expect(md, contains('Ranking is limited'));
      expect(md, contains('coupling graph had no edges'));
    });

    test('renderer shows "N of M" when harvest filtered files', () {
      final doc = RepoDoc(
        repoName: 'big',
        elevatorPitch: '',
        shape: '',
        glance: const RepoStatsGlance(
          activeFileCount: 10,
          activeLines: 1000,
          activeBytes: 10000,
          roles: [MapEntry('source', 10)],
          dormantSkipped: 30,
        ),
        backbone: const [],
        regions: const [],
        gettingStarted: '',
        generatedAt: DateTime.utc(2026, 1, 1),
        totalHarvested: 40,
      );
      final md = renderMarkdown(doc);
      expect(md, contains('Showing 10 of 40 files'));
      expect(md, contains('ranked by structural centrality'));
    });
  });
}
