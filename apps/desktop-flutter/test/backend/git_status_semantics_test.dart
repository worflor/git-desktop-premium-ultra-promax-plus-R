import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/git.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RepositoryStatusFile semantics', () {
    test('normalizes untracked state across backend representations', () {
      const legacy = RepositoryStatusFile(
        path: 'draft.txt',
        staged: '?',
        unstaged: '?',
      );
      const normalized = RepositoryStatusFile(
        path: 'draft.txt',
        staged: 'untracked',
        unstaged: 'untracked',
      );

      for (final file in [legacy, normalized]) {
        expect(file.isUntracked, isTrue);
        expect(file.hasStagedChange, isFalse);
        expect(file.hasUnstagedChange, isTrue);
        expect(file.stagedCode, isEmpty);
        expect(file.unstagedCode, '?');
      }
    });

    test('normalizes clean and modified labels into commit semantics', () {
      const file = RepositoryStatusFile(
        path: 'tracked.txt',
        staged: 'clean',
        unstaged: 'modified',
      );

      expect(file.isUntracked, isFalse);
      expect(file.hasStagedChange, isFalse);
      expect(file.hasUnstagedChange, isTrue);
      expect(file.stagedCode, isEmpty);
      expect(file.unstagedCode, 'M');
    });
  });

  group('Git status integration', () {
    late Directory repo;

    Future<ProcessResult> git(List<String> args) {
      return Process.run(
        'git',
        args,
        workingDirectory: repo.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    }

    File repoFile(String relativePath) =>
        File('${repo.path}${Platform.pathSeparator}$relativePath');

    Future<void> seedRepo() async {
      repo = await Directory.systemTemp.createTemp('gdpu_git_status_');
      await git(['init', '-q', '-b', 'main']);
      await git(['config', 'user.name', 'test']);
      await git(['config', 'user.email', 'test@local']);
      await repoFile('tracked.txt').writeAsString('root\n');
      await git(['add', 'tracked.txt']);
      await git(['commit', '-m', 'root']);
    }

    setUp(() async {
      await seedRepo();
    });

    tearDown(() async {
      if (await repo.exists()) {
        await repo.delete(recursive: true);
      }
    });

    test('status loader keeps untracked files out of staged state', () async {
      await repoFile('draft.txt').writeAsString('draft\n');

      final status = await getRepositoryStatus(repo.path);
      expect(status.ok, isTrue, reason: status.error);

      final draft =
          status.data!.files.firstWhere((file) => file.path == 'draft.txt');
      expect(draft.staged, isEmpty);
      expect(draft.unstaged, '?');
      expect(draft.isUntracked, isTrue);
      expect(draft.hasStagedChange, isFalse);
      expect(draft.hasUnstagedChange, isTrue);
    });

    test('hasHeadCommit reports false on a fresh repo with no commits',
        () async {
      // Pin the gating signal for "Amend last commit" / reflog
      // recovery affordances. A fresh init has no HEAD ref, so
      // surfacing those menu items would just wire the user to a
      // "nothing to amend" error.
      final pristine = await Directory.systemTemp.createTemp('gdpu_init_');
      try {
        await Process.run('git', ['init', '-q', '-b', 'main'],
            workingDirectory: pristine.path);
        final status = await getRepositoryStatus(pristine.path);
        expect(status.ok, isTrue, reason: status.error);
        expect(status.data!.hasHeadCommit, isFalse);
      } finally {
        if (await pristine.exists()) {
          await pristine.delete(recursive: true);
        }
      }
    });

    test('hasHeadCommit reports true once a commit lands', () async {
      // The seedRepo helper already produced a commit, so the
      // baseline status from a clean checkout reports HEAD-present.
      final status = await getRepositoryStatus(repo.path);
      expect(status.ok, isTrue, reason: status.error);
      expect(status.data!.hasHeadCommit, isTrue);
    });

    test('unstagePaths ignores untracked paths while restoring staged ones',
        () async {
      await repoFile('tracked.txt').writeAsString('root\nnext\n');
      await repoFile('draft.txt').writeAsString('draft\n');

      final stage = await stagePaths(repo.path, ['tracked.txt']);
      expect(stage.ok, isTrue, reason: stage.error);

      final unstage =
          await unstagePaths(repo.path, ['tracked.txt', 'draft.txt']);
      expect(unstage.ok, isTrue, reason: unstage.error);

      final status = await getRepositoryStatus(repo.path);
      expect(status.ok, isTrue, reason: status.error);

      final tracked =
          status.data!.files.firstWhere((file) => file.path == 'tracked.txt');
      final draft =
          status.data!.files.firstWhere((file) => file.path == 'draft.txt');

      expect(tracked.hasStagedChange, isFalse);
      expect(tracked.hasUnstagedChange, isTrue);
      expect(draft.isUntracked, isTrue);
      expect(draft.hasStagedChange, isFalse);
      expect(draft.hasUnstagedChange, isTrue);
    });
  });
}
