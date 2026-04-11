import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/repository_xray.dart';

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
        r'C:/repo|feature/xray|deadbeefcafebabe|2',
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
    'log --all --name-only --format=': _rawPathLog(),
    'log --all --grep=^t3 checkpoint --invert-grep --name-only --format=': _filteredPathLog(),
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
    'log --grep=^t3 checkpoint --invert-grep --format=%an -- apps/desktop-flutter/lib/features/changes/changes_page.dart':
        List.filled(12, 'Alice').join('\n'),
    'log -n 1 --date=short --format=%H\t%h\t%ad -- apps/desktop-flutter/lib/features/changes/changes_page.dart':
        'abcdef1234567890\tabcdef12\t2026-04-11',
    'log --grep=^t3 checkpoint --invert-grep --format=%an -- apps/desktop': 'Alice\nBob',
    'log -n 1 --grep=^t3 checkpoint --invert-grep --date=short --format=%ad -- apps/desktop':
        '2026-04-02',
    'log --grep=^t3 checkpoint --invert-grep --format=%an -- apps/desktop-flutter': 'Alice',
    'log -n 1 --grep=^t3 checkpoint --invert-grep --date=short --format=%ad -- apps/desktop-flutter':
        '2026-04-11',
  };

  if (responses.containsKey(command)) {
    return ProcessResult(0, 0, responses[command]!, '');
  }

  if (command.startsWith('log --format=%an --')) {
    final path = args.last;
    if (path == 'generated/session.lock') {
      return ProcessResult(0, 0, List.filled(18, 'Machine').join('\n'), '');
    }
    if (path == 'apps/desktop/src/legacy_shell.ts') {
      return ProcessResult(0, 0, 'Alice\nBob', '');
    }
    if (path == 'apps/desktop-flutter') {
      return ProcessResult(0, 0, 'Alice', '');
    }
    return ProcessResult(0, 0, 'Alice', '');
  }

  if (command.startsWith('log --grep=^t3 checkpoint --invert-grep --format=%an --')) {
    final path = args.last;
    if (path == 'apps/desktop/src/legacy_shell.ts') {
      return ProcessResult(0, 0, 'Alice\nBob', '');
    }
    return ProcessResult(0, 0, 'Alice', '');
  }

  if (command.startsWith('log -n 1 --date=short --format=%H\t%h\t%ad --')) {
    final path = args.last;
    if (path == 'generated/session.lock') {
      return ProcessResult(0, 0, 'ffff111122223333\tffff1111\t2026-04-11', '');
    }
    if (path == 'apps/desktop/src/legacy_shell.ts') {
      return ProcessResult(0, 0, 'bbbb111122223333\tbbbb1111\t2026-04-02', '');
    }
    if (path == 'apps/desktop-flutter') {
      return ProcessResult(0, 0, 'cccc111122223333\tcccc1111\t2026-04-11', '');
    }
    return ProcessResult(0, 0, 'dddd111122223333\tdddd1111\t2026-04-11', '');
  }

  if (command.startsWith('log -n 1 --grep=^t3 checkpoint --invert-grep --date=short --format=%H\t%h\t%ad --')) {
    final path = args.last;
    if (path == 'apps/desktop/src/legacy_shell.ts') {
      return ProcessResult(0, 0, 'bbbb111122223333\tbbbb1111\t2026-04-02', '');
    }
    return ProcessResult(0, 0, 'dddd111122223333\tdddd1111\t2026-04-11', '');
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

String _rawPathLog() => [
      ...List.filled(18, 'generated/session.lock'),
      ...List.filled(22, 'apps/desktop/src/legacy_shell.ts'),
      ...List.filled(24, 'apps/desktop-flutter/lib/features/changes/changes_page.dart'),
      ...List.filled(12, 'apps/desktop-flutter/lib/app/workspace_shell.dart'),
    ].join('\n');

String _filteredPathLog() => [
      ...List.filled(22, 'apps/desktop/src/legacy_shell.ts'),
      ...List.filled(24, 'apps/desktop-flutter/lib/features/changes/changes_page.dart'),
      ...List.filled(12, 'apps/desktop-flutter/lib/app/workspace_shell.dart'),
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
