import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/repository_xray.dart'
    show
        buildRepositoryXraySnapshot,
        computeRepositoryXrayFingerprint,
        parseDatedCommitCanonicalFilesForTesting,
        parseLsTreeBytesForTesting;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Repository X-Ray', () {
    test('detects hidden refs, migration strata, and filtered pivot commits', () async {
      final snapshotResult = await buildRepositoryXraySnapshot(
        r'C:\repo',
        statusLoader: (_) async => GitResult.ok(
          const RepositoryStatus(
            branch: 'main',
            ahead: 0,
            behind: 0,
            files: [
              RepositoryStatusFile(path: 'README.md', staged: 'M', unstaged: ' '),
            ],
          ),
        ),
        probe: _fakeProbe,
      );

      expect(snapshotResult.ok, isTrue);
      final snapshot = snapshotResult.data!;

      expect(snapshot.signalIntegrity.hasHiddenRefs, isTrue);
      expect(snapshot.signalIntegrity.hiddenRefCount, 1);
      expect(snapshot.signalIntegrity.machineCommitCount, 1);
      expect(snapshot.signalIntegrity.machineHistoryDominant, isFalse);

      expect(snapshot.refSummary.hiddenNamespaces, contains('t3'));

      expect(snapshot.cards.map((card) => card.id), contains('hidden-refs'));
      expect(snapshot.cards.map((card) => card.id), contains('migration'));
      expect(snapshot.cards.map((card) => card.id), contains('single-owner-hotspot'));
      expect(snapshot.cards.map((card) => card.id), contains('no-tags'));
      expect(snapshot.cards.map((card) => card.id), contains('reflog-intense'));

      expect(
        snapshot.strata.map((stratum) => stratum.pathPrefix),
        containsAll(<String>['apps/desktop', 'apps/desktop-flutter']),
      );

      final filteredPivotSubjects =
          snapshot.pivots.map((pivot) => pivot.subject).toList();
      expect(filteredPivotSubjects, isNot(contains('t3 checkpoint: synthetic sweep')));

      final rawPivotSubjects =
          snapshot.rawPivots.map((pivot) => pivot.subject).toList();
      expect(rawPivotSubjects, contains('t3 checkpoint: synthetic sweep'));

      final filteredHotspotPaths =
          snapshot.hotspots.map((hotspot) => hotspot.path).toList();
      expect(filteredHotspotPaths, isNot(contains('generated/session.lock')));
      expect(filteredHotspotPaths, contains('apps/desktop-flutter/lib/features/changes/changes_page.dart'));

      final rawHotspotPaths =
          snapshot.rawHotspots.map((hotspot) => hotspot.path).toList();
      expect(rawHotspotPaths, contains('generated/session.lock'));

      // Enriched fields are derived from the single `--name-only` pass
      // (no per-path `git log` fan-out). Pin author/date/hash so the
      // in-memory enrichment can't silently regress.
      final changesPageHotspot = snapshot.hotspots.firstWhere(
        (h) => h.path ==
            'apps/desktop-flutter/lib/features/changes/changes_page.dart',
      );
      expect(changesPageHotspot.ownerCount, 1);
      expect(changesPageHotspot.lastTouchedAt, '2026-04-11');
      expect(changesPageHotspot.latestShortHash, 'aaaa1111');
      expect(changesPageHotspot.latestCommitHash, 'aaaa111122223333');

      final legacyShellHotspot = snapshot.hotspots.firstWhere(
        (h) => h.path == 'apps/desktop/src/legacy_shell.ts',
      );
      expect(legacyShellHotspot.ownerCount, 1);
      expect(legacyShellHotspot.lastTouchedAt, '2026-04-02');
      expect(legacyShellHotspot.latestShortHash, 'bbbb1111');

      // Directory strata enrichment: `apps/desktop-flutter` is touched
      // only by Alice (2026-04-11), and `apps/desktop` only by Bob
      // (2026-04-02) — the dir prefix must NOT match `apps/desktop-*`.
      final flutterStratum = snapshot.strata
          .firstWhere((s) => s.pathPrefix == 'apps/desktop-flutter');
      expect(flutterStratum.ownerCount, 1);
      expect(flutterStratum.lastTouchedAt, '2026-04-11');

      final desktopStratum = snapshot.strata
          .firstWhere((s) => s.pathPrefix == 'apps/desktop');
      expect(desktopStratum.ownerCount, 1);
      expect(desktopStratum.lastTouchedAt, '2026-04-02');

      // Raw hotspots include machine history — the session.lock file
      // should be attributed to Machine alone.
      final sessionLockHotspot = snapshot.rawHotspots.firstWhere(
        (h) => h.path == 'generated/session.lock',
      );
      expect(sessionLockHotspot.ownerCount, 1);
      expect(sessionLockHotspot.latestShortHash, 'ffff1111');

      expect(snapshot.flow.gradientMass, inInclusiveRange(0.0, 1.0));
      expect(snapshot.flow.curlMass, inInclusiveRange(0.0, 1.0));
      expect(snapshot.flow.harmonicMass, inInclusiveRange(0.0, 1.0));
      expect(snapshot.flow.structuralStress, inInclusiveRange(0.0, 1.0));
      expect(snapshot.flow.confidence, inInclusiveRange(0.0, 1.0));
      expect(snapshot.flow.confidence, greaterThan(0.5));
    });

    test('fingerprint uses repo path, branch, head, and dirty count', () async {
      final result = await computeRepositoryXrayFingerprint(
        r'C:\repo',
        (_) async => GitResult.ok(
          const RepositoryStatus(
            branch: 'feature/xray',
            ahead: 0,
            behind: 0,
            files: [
              RepositoryStatusFile(path: 'a.dart', staged: 'M', unstaged: ' '),
              RepositoryStatusFile(path: 'b.dart', staged: ' ', unstaged: 'M'),
            ],
          ),
        ),
        (workingDir, args) async {
          expect(workingDir, r'C:\repo');
          expect(args, ['rev-parse', 'HEAD']);
          return ProcessResult(0, 0, 'deadbeefcafebabe\n', '');
        },
      );

      expect(result.ok, isTrue);
      expect(
        result.data,
        r'C:/repo|feature/xray|deadbeefcafebabe|2|s1|u1',
      );
    });

    test('snapshot path avoids duplicate status and head probes', () async {
      var statusCalls = 0;
      final commandCounts = <String, int>{};

      final snapshotResult = await buildRepositoryXraySnapshot(
        r'C:\repo',
        statusLoader: (_) async {
          statusCalls += 1;
          return GitResult.ok(
            const RepositoryStatus(
              branch: 'main',
              ahead: 0,
              behind: 0,
              files: [],
            ),
          );
        },
        probe: (workingDir, args) async {
          final key = args.join(' ');
          commandCounts.update(key, (value) => value + 1, ifAbsent: () => 1);
          return _fakeProbe(workingDir, args);
        },
      );

      expect(snapshotResult.ok, isTrue);
      expect(statusCalls, 1);
      expect(commandCounts['rev-parse HEAD'], 1);
    });

    test('rename events collapse pre-rename history onto HEAD-side name', () {
      // `git log --all --name-status -M95` output for a repo where the
      // file walked old/one.dart → mid/two.dart → new/three.dart across
      // two rename commits. Walk is newest→oldest, so the destination
      // of the newest rename is HEAD-side — all three names must
      // canonicalise to `new/three.dart`.
      final stream = [
        // Newest commit touches the current name directly.
        '__C__cccc1111\tcccc\t2026-04-20\tAlice',
        'M\tnew/three.dart',
        '',
        // Second rename.
        '__C__bbbb1111\tbbbb\t2026-04-15\tAlice',
        'R98\tmid/two.dart\tnew/three.dart',
        '',
        // First rename.
        '__C__aaaa1111\taaaa\t2026-04-10\tBob',
        'R97\told/one.dart\tmid/two.dart',
        '',
        // Oldest commit touches the original name.
        '__C__zzzz1111\tzzzz\t2026-04-01\tBob',
        'M\told/one.dart',
      ].join('\n');

      final perCommit = parseDatedCommitCanonicalFilesForTesting(stream);
      expect(perCommit.length, 4);
      // Every commit should attribute to the HEAD-side path after
      // union-find canonicalisation — pre-rename names are gone.
      for (final files in perCommit) {
        expect(files, {'new/three.dart'});
      }
    });

    test('non-rename status lines preserve their paths unchanged', () {
      // With no rename events the union-find stays empty and every
      // path is its own canonical — guards against accidental
      // collapsing of unrelated files.
      final stream = [
        '__C__aaaa1111\taaaa\t2026-04-10\tAlice',
        'M\tlib/a.dart',
        'A\tlib/b.dart',
        'D\tlib/c.dart',
        '',
        '__C__bbbb1111\tbbbb\t2026-04-11\tBob',
        'M\tlib/a.dart',
        'T\tlib/d.dart',
      ].join('\n');

      final perCommit = parseDatedCommitCanonicalFilesForTesting(stream);
      expect(perCommit, [
        {'lib/a.dart', 'lib/b.dart', 'lib/c.dart'},
        {'lib/a.dart', 'lib/d.dart'},
      ]);
    });

    test('ls-tree parser handles the real git format (single-tab, padded size)', () {
      // Real `git ls-tree -r -l HEAD` output: one TAB between the
      // right-padded size column and the path. Submodule entries use
      // `-` for size (no fixed byte count) and must be skipped.
      const sample =
          '100644 blob 2971eee6b7a810f1b9c7ae48d83a97657df4130b      92\t.claude/scheduled_tasks.lock\n'
          '100644 blob dfe0770424b2a19faf507a501ebfc23be8f54e7b      66\t.gitattributes\n'
          '100644 blob 8a140d78e49e02fd1aa63707a66f5e836bdd12a6    2013\t.github/workflows/desktop-ci.yml\n'
          '160000 commit abcdef1234567890abcdef1234567890abcdef12       -\tvendor/sub\n';

      final parsed = parseLsTreeBytesForTesting(sample);

      expect(parsed['.claude/scheduled_tasks.lock'], 92);
      expect(parsed['.gitattributes'], 66);
      expect(parsed['.github/workflows/desktop-ci.yml'], 2013);
      // Submodule commit ('-' size) is skipped — not a blob, has no
      // byte count to feed the alive-mass filter.
      expect(parsed.containsKey('vendor/sub'), isFalse);
    });
  });
}

Future<ProcessResult> _fakeProbe(String workingDir, List<String> args) async {
  final command = args.join(' ');
  final responses = <String, String>{
    'rev-parse HEAD': 'abcdef1234567890abcdef1234567890abcdef12\n',
    'for-each-ref --format=%(refname)\t%(objecttype)\t%(creatordate:short)\t%(subject)':
        [
          'refs/heads/main\tcommit\t2026-04-11\tship flutter surface',
          'refs/remotes/origin/main\tcommit\t2026-04-11\tship flutter surface',
          'refs/t3/checkpoints/session-1\tcommit\t2026-04-11\tt3 checkpoint: synthetic sweep',
        ].join('\n'),
    'branch -a -vv': [
      '* main                abcdef1 ship flutter surface',
      '  remotes/origin/main abcdef1 ship flutter surface',
    ].join('\n'),
    'log --all --date=short --pretty=format:%H\t%h\t%ad\t%an\t%s': _rawCommitLog(),
    'log --all --grep=^t3 checkpoint --invert-grep --date=short --pretty=format:%H\t%h\t%ad\t%an\t%s':
        _filteredCommitLog(),
    'log --all --name-status -M95 --date=short --format=__C__%H\t%h\t%ad\t%an':
        _rawPathLog(),
    'log --all --grep=^t3 checkpoint --invert-grep --name-status -M95 --date=short --format=__C__%H\t%h\t%ad\t%an':
        _filteredPathLog(),
    'log --all --shortstat --date=short --pretty=format:__C__%H\t%h\t%ad\t%an\t%s':
        _rawShortstatLog(),
    'log --all --grep=^t3 checkpoint --invert-grep --shortstat --date=short --pretty=format:__C__%H\t%h\t%ad\t%an\t%s':
        _filteredShortstatLog(),
    'log --all --date=short --pretty=format:%ad': [
      '2026-04-01',
      '2026-04-01',
      '2026-04-01',
      '2026-04-04',
    ].join('\n'),
    'log --all --grep=^t3 checkpoint --invert-grep --date=short --pretty=format:%ad': [
      '2026-04-01',
      '2026-04-01',
      '2026-04-04',
    ].join('\n'),
    'shortlog -sn --all --no-merges': '4 Alice\n',
    'shortlog -sn --all --no-merges --grep=^t3 checkpoint --invert-grep': '3 Alice\n',
    'reflog -n 120 --date=short': _reflogLog(),
    'stash list': '',
    'notes list': '',
    'worktree list --porcelain': 'worktree C:/repo\nHEAD abcdef1234567890\nbranch refs/heads/main\n',
    'log --all --merges --oneline': '',
    'log --all --diff-filter=R --summary --format=': '',
    'remote -v': [
      'origin\thttps://example.com/repo.git (fetch)',
      'origin\thttps://example.com/repo.git (push)',
    ].join('\n'),
  };

  if (responses.containsKey(command)) {
    return ProcessResult(0, 0, responses[command]!, '');
  }
  return ProcessResult(0, 0, '', '');
}

String _rawCommitLog() => [
      'ffff111122223333\tffff1111\t2026-04-11\tMachine\tt3 checkpoint: synthetic sweep',
      'aaaa111122223333\taaaa1111\t2026-04-04\tAlice\tship flutter surface',
      'bbbb111122223333\tbbbb1111\t2026-04-02\tBob\tstabilize legacy desktop shell',
      'cccc111122223333\tcccc1111\t2026-04-01\tAlice\tseed desktop flutter migration',
    ].join('\n');

String _filteredCommitLog() => [
      'aaaa111122223333\taaaa1111\t2026-04-04\tAlice\tship flutter surface',
      'bbbb111122223333\tbbbb1111\t2026-04-02\tBob\tstabilize legacy desktop shell',
      'cccc111122223333\tcccc1111\t2026-04-01\tAlice\tseed desktop flutter migration',
    ].join('\n');

/// Build a per-commit log: each marker line packs hash/shortHash/date/
/// author tab-separated, followed by the file paths touched in that
/// commit. Matches the `--format=__C__%H\t%h\t%ad\t%an` string used
/// by the production xray path.
String _commitBlock(
  String hash,
  String shortHash,
  String date,
  String author,
  List<String> files,
) =>
    ['__C__$hash\t$shortHash\t$date\t$author', ...files].join('\n');

String _rawPathLog() => [
      _commitBlock('ffff111122223333', 'ffff1111', '2026-04-11', 'Machine', [
        ...List.filled(18, 'generated/session.lock'),
      ]),
      _commitBlock('aaaa111122223333', 'aaaa1111', '2026-04-11', 'Alice', [
        ...List.filled(24, 'apps/desktop-flutter/lib/features/changes/changes_page.dart'),
        ...List.filled(12, 'apps/desktop-flutter/lib/app/workspace_shell.dart'),
      ]),
      _commitBlock('bbbb111122223333', 'bbbb1111', '2026-04-02', 'Bob', [
        ...List.filled(22, 'apps/desktop/src/legacy_shell.ts'),
      ]),
    ].join('\n');

String _filteredPathLog() => [
      _commitBlock('aaaa111122223333', 'aaaa1111', '2026-04-11', 'Alice', [
        ...List.filled(24, 'apps/desktop-flutter/lib/features/changes/changes_page.dart'),
        ...List.filled(12, 'apps/desktop-flutter/lib/app/workspace_shell.dart'),
      ]),
      _commitBlock('bbbb111122223333', 'bbbb1111', '2026-04-02', 'Bob', [
        ...List.filled(22, 'apps/desktop/src/legacy_shell.ts'),
      ]),
    ].join('\n');

String _rawShortstatLog() => [
      '__C__ffff111122223333\tffff1111\t2026-04-11\tMachine\tt3 checkpoint: synthetic sweep',
      ' 30 files changed, 900 insertions(+), 20 deletions(-)',
      '__C__aaaa111122223333\taaaa1111\t2026-04-04\tAlice\tship flutter surface',
      ' 8 files changed, 240 insertions(+), 60 deletions(-)',
      '__C__bbbb111122223333\tbbbb1111\t2026-04-02\tBob\tstabilize legacy desktop shell',
      ' 11 files changed, 120 insertions(+), 40 deletions(-)',
      '__C__cccc111122223333\tcccc1111\t2026-04-01\tAlice\tseed desktop flutter migration',
      ' 9 files changed, 160 insertions(+), 15 deletions(-)',
    ].join('\n');

String _filteredShortstatLog() => [
      '__C__aaaa111122223333\taaaa1111\t2026-04-04\tAlice\tship flutter surface',
      ' 8 files changed, 240 insertions(+), 60 deletions(-)',
      '__C__bbbb111122223333\tbbbb1111\t2026-04-02\tBob\tstabilize legacy desktop shell',
      ' 11 files changed, 120 insertions(+), 40 deletions(-)',
      '__C__cccc111122223333\tcccc1111\t2026-04-01\tAlice\tseed desktop flutter migration',
      ' 9 files changed, 160 insertions(+), 15 deletions(-)',
    ].join('\n');

String _reflogLog() => [
      ...List.filled(18, 'abcdef12 HEAD@{2026-04-11 10:00:00 -0400}: commit: ship flutter surface'),
      ...List.filled(4, 'bbbb1111 HEAD@{2026-04-02 09:00:00 -0400}: commit: stabilize legacy desktop shell'),
    ].join('\n');
