// Fidelity proof for the repo-summary i18n boundary.
//
// The backend composes structure and delegates every user-facing
// sentence to a `RepoSummaryStrings`. This test drives the SLANG-backed
// implementation (the production path, `SlangRepoSummaryStrings`) and
// asserts that the rendered English is byte-identical to the original
// hardcoded prose — the expectations below are computed by hand from the
// pre-refactor logic in assembler.dart / prose.dart / shape.dart.
//
// Two complementary checks per input:
//   1. The slang render equals the verbatim-English default render
//      (`EnglishRepoSummaryStrings`), which reproduces the old code.
//   2. Hand-derived exact strings, so both paths can't silently drift
//      together.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/repo_summary/assembler.dart';
import 'package:git_desktop/backend/repo_summary/prose.dart';
import 'package:git_desktop/backend/repo_summary/strings.dart';
import 'package:git_desktop/backend/repo_summary/types.dart';
import 'package:git_desktop/ui/repo_summary_text.dart';

const _en = EnglishRepoSummaryStrings();
const _slang = SlangRepoSummaryStrings();

RepoDoc _doc({
  String repoName = 'demo',
  String elevatorPitch = '',
  String shape = '',
  RepoStatsGlance? glance,
  List<BackboneEntry> backbone = const [],
  List<RegionDoc> regions = const [],
  String gettingStarted = '',
  int totalHarvested = 2,
  bool historyStarved = false,
}) =>
    RepoDoc(
      repoName: repoName,
      elevatorPitch: elevatorPitch,
      shape: shape,
      glance: glance ??
          const RepoStatsGlance(
            activeFileCount: 2,
            activeLines: 10,
            activeBytes: 200,
            roles: [MapEntry('source', 2)],
            dormantSkipped: 0,
          ),
      backbone: backbone,
      regions: regions,
      gettingStarted: gettingStarted,
      generatedAt: DateTime.utc(2026, 4, 20, 12, 0, 0),
      totalHarvested: totalHarvested,
      historyStarved: historyStarved,
    );

void main() {
  // A battery of docs exercising each render branch. The single most
  // important assertion: the slang path is byte-identical to the
  // verbatim-English path (which is the old code, unchanged).
  group('slang render == verbatim-English render', () {
    final docs = <String, RepoDoc>{
      'plain plural file count': _doc(),
      'singular file count': _doc(
        glance: const RepoStatsGlance(
          activeFileCount: 1,
          activeLines: 1,
          activeBytes: 50,
          roles: [],
          dormantSkipped: 0,
        ),
        totalHarvested: 1,
      ),
      'showing N of M': _doc(
        glance: const RepoStatsGlance(
          activeFileCount: 10,
          activeLines: 1000,
          activeBytes: 10000,
          roles: [MapEntry('source', 10)],
          dormantSkipped: 30,
        ),
        totalHarvested: 40,
      ),
      'multi-role': _doc(
        glance: const RepoStatsGlance(
          activeFileCount: 3,
          activeLines: 300,
          activeBytes: 3000,
          roles: [MapEntry('source', 2), MapEntry('test', 1)],
          dormantSkipped: 0,
        ),
        totalHarvested: 3,
      ),
      'history starved': _doc(historyStarved: true),
      'shape present': _doc(
        shape: 'Modular codebase: several cohesive regions with limited '
            'cross-coupling. Work in one region rarely disturbs another.',
      ),
      'backbone with and without purpose': _doc(
        backbone: const [
          BackboneEntry(
            path: 'a.dart',
            lineCount: 120,
            regionName: 'core',
            purpose: 'Entry point.',
          ),
          BackboneEntry(
            path: 'x.dart',
            lineCount: 1,
            regionName: 'ui shell',
            purpose: '',
          ),
        ],
      ),
      'region with body, files, neighbors': _doc(
        regions: const [
          RegionDoc(
            id: 0,
            name: 'core',
            body: 'Two files.',
            paths: ['a.dart', 'b.dart'],
            neighborNames: ['ui', 'io'],
            fileCount: 2,
            themes: [],
          ),
        ],
      ),
      'getting started section': _doc(gettingStarted: '```sh\nmake run\n```'),
      'elevator pitch passthrough': _doc(elevatorPitch: 'Hand-written pitch.'),
    };
    docs.forEach((label, doc) {
      test(label, () {
        expect(
          renderMarkdown(doc, strings: _slang),
          renderMarkdown(doc, strings: _en),
          reason: 'slang templates must reproduce the English render',
        );
      });
    });
  });

  group('hand-derived exact English on the slang path', () {
    test('glance: showing N of M', () {
      final md = renderMarkdown(
        _doc(
          glance: const RepoStatsGlance(
            activeFileCount: 10,
            activeLines: 1000,
            activeBytes: 10000,
            roles: [],
            dormantSkipped: 30,
          ),
          totalHarvested: 40,
        ),
        strings: _slang,
      );
      expect(
        md,
        contains(
            '- Showing 10 of 40 files, ranked by structural centrality.'),
      );
    });

    test('glance: singular vs plural file count', () {
      expect(
        renderMarkdown(
          _doc(
            glance: const RepoStatsGlance(
              activeFileCount: 1,
              activeLines: 1,
              activeBytes: 50,
              roles: [],
              dormantSkipped: 0,
            ),
            totalHarvested: 1,
          ),
          strings: _slang,
        ),
        allOf(contains('- 1 file.'), contains('- 1 line (50 B).')),
      );
      expect(
        renderMarkdown(_doc(), strings: _slang),
        allOf(contains('- 2 files.'), contains('- 10 lines (200 B).')),
      );
    });

    test('glance: roles', () {
      final md = renderMarkdown(
        _doc(
          glance: const RepoStatsGlance(
            activeFileCount: 3,
            activeLines: 300,
            activeBytes: 3000,
            roles: [MapEntry('source', 2), MapEntry('test', 1)],
            dormantSkipped: 0,
          ),
          totalHarvested: 3,
        ),
        strings: _slang,
      );
      expect(md, contains('- Roles — source: 2, test: 1.'));
    });

    test('history-starved caveat', () {
      final md = renderMarkdown(_doc(historyStarved: true), strings: _slang);
      expect(
        md,
        contains('- Ranking is limited: the coupling graph had no edges '
            '(fresh clone or too few commits). File order reflects size, '
            'not structural centrality.'),
      );
    });

    test('backbone entries with and without purpose', () {
      final md = renderMarkdown(
        _doc(
          backbone: const [
            BackboneEntry(
              path: 'a.dart',
              lineCount: 120,
              regionName: 'core',
              purpose: 'Entry point.',
            ),
            BackboneEntry(
              path: 'x.dart',
              lineCount: 1,
              regionName: 'ui shell',
              purpose: '',
            ),
          ],
        ),
        strings: _slang,
      );
      // `core` is identifier-shaped -> backticks; `ui shell` has a space
      // -> italics (unchanged _regionLabel behavior).
      expect(md, contains('- `a.dart` (120 lines) — `core` · Entry point.'));
      expect(md, contains('- `x.dart` (1 line) — _ui shell_'));
    });

    test('headings', () {
      final md = renderMarkdown(
        _doc(
          shape: 'Modular codebase: several cohesive regions with limited '
              'cross-coupling. Work in one region rarely disturbs another.',
          backbone: const [
            BackboneEntry(
                path: 'a.dart', lineCount: 5, regionName: 'core', purpose: ''),
          ],
          regions: const [
            RegionDoc(
              id: 0,
              name: 'core',
              body: 'Two files.',
              paths: ['a.dart'],
              neighborNames: [],
              fileCount: 1,
              themes: [],
            ),
          ],
          gettingStarted: '```sh\nmake\n```',
        ),
        strings: _slang,
      );
      expect(md, contains('## Shape'));
      expect(md, contains('## At a glance'));
      expect(md, contains('## Core'));
      expect(md, contains('## Regions'));
      expect(md, contains('## Getting started'));
    });

    test('region files label and connects-to', () {
      final md = renderMarkdown(
        _doc(
          regions: const [
            RegionDoc(
              id: 0,
              name: 'core',
              body: 'Two files.',
              paths: ['a.dart', 'b.dart'],
              neighborNames: ['core', 'ui'],
              fileCount: 2,
              themes: [],
            ),
          ],
        ),
        strings: _slang,
      );
      expect(md, contains('Files:\n- `a.dart`\n- `b.dart`'));
      expect(md, contains('Connects to: `core`, `ui`.'));
    });
  });

  group('regionBody (pipeline-baked) via slang', () {
    String bodyEn(int files, int core, {String? dir}) => regionBody(
          name: 'x',
          fileCount: files,
          backboneFileCount: core,
          themes: const [],
          commonDirectory: dir,
        );
    String bodySlang(int files, int core, {String? dir}) => regionBody(
          name: 'x',
          fileCount: files,
          backboneFileCount: core,
          themes: const [],
          commonDirectory: dir,
          strings: _slang,
        );

    test('empty when zero files', () {
      expect(bodySlang(0, 0), '');
      expect(bodySlang(0, 0), bodyEn(0, 0));
    });

    test('singular file, no core', () {
      expect(bodySlang(1, 0), 'One file.');
      expect(bodySlang(1, 0), bodyEn(1, 0));
    });

    test('plural files, no core', () {
      expect(bodySlang(5, 0), '5 files.');
      expect(bodySlang(5, 0), bodyEn(5, 0));
    });

    test('plural files with singular core', () {
      expect(bodySlang(5, 1), '5 files, 1 core.');
      expect(bodySlang(5, 1), bodyEn(5, 1));
    });

    test('plural files with plural core', () {
      expect(bodySlang(5, 2), '5 files, 2 core.');
      expect(bodySlang(5, 2), bodyEn(5, 2));
    });

    test('with common directory', () {
      expect(
        bodySlang(5, 2, dir: 'apps/desktop/'),
        '5 files, 2 core. All under `apps/desktop/`.',
      );
      expect(bodySlang(5, 2, dir: 'apps/desktop/'), bodyEn(5, 2, dir: 'apps/desktop/'));
    });

    test('single file with common directory, no core', () {
      expect(bodySlang(1, 0, dir: 'lib/'), 'One file. All under `lib/`.');
      expect(bodySlang(1, 0, dir: 'lib/'), bodyEn(1, 0, dir: 'lib/'));
    });
  });

  group('synthesiseElevatorPitch via slang', () {
    String en(List<String> regions, int n) => synthesiseElevatorPitch(
          repoName: 'r',
          topRegionNames: regions,
          activeFileCount: n,
        );
    String slang(List<String> regions, int n) => synthesiseElevatorPitch(
          repoName: 'r',
          topRegionNames: regions,
          activeFileCount: n,
          strings: _slang,
        );

    test('no regions, singular', () {
      expect(slang(const [], 1), 'A repository of 1 active file.');
      expect(slang(const [], 1), en(const [], 1));
    });
    test('no regions, plural', () {
      expect(slang(const [], 4), 'A repository of 4 active files.');
      expect(slang(const [], 4), en(const [], 4));
    });
    test('with regions, plural', () {
      expect(
        slang(const ['core', 'ui'], 2),
        'A repository of 2 active files — **core**, **ui**.',
      );
      expect(slang(const ['core', 'ui'], 2), en(const ['core', 'ui'], 2));
    });
    test('with regions, singular', () {
      expect(
        slang(const ['core'], 1),
        'A repository of 1 active file — **core**.',
      );
      expect(slang(const ['core'], 1), en(const ['core'], 1));
    });
  });

  group('empty-repo pitch clauses via slang', () {
    test('binary + unreadable clauses', () {
      expect(_slang.emptyRepoBinary(3), '3 binary');
      expect(_slang.emptyRepoUnreadable(1), '1 unreadable');
      expect(_slang.emptyRepoBinary(3), _en.emptyRepoBinary(3));
      expect(_slang.emptyRepoUnreadable(1), _en.emptyRepoUnreadable(1));
    });
    test('base with and without detail', () {
      expect(
        _slang.emptyRepoPitch(' (3 binary, 1 unreadable)'),
        'A repository with no readable text files (3 binary, 1 unreadable).',
      );
      expect(_slang.emptyRepoPitch(''),
          'A repository with no readable text files.');
      expect(_slang.emptyRepoPitch(''), _en.emptyRepoPitch(''));
    });
  });

  group('shape sentences via slang', () {
    test('all six archetypes match the verbatim English', () {
      expect(_slang.shapeTree, _en.shapeTree);
      expect(_slang.shapeModular, _en.shapeModular);
      expect(_slang.shapeBulk, _en.shapeBulk);
      expect(_slang.shapeCrystalline, _en.shapeCrystalline);
      expect(_slang.shapeGoe, _en.shapeGoe);
      expect(_slang.shapePoisson, _en.shapePoisson);
    });
    test('exact modular sentence', () {
      expect(
        _slang.shapeModular,
        'Modular codebase: several cohesive regions with limited '
        'cross-coupling. Work in one region rarely disturbs another.',
      );
    });
  });
}
