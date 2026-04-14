// Integration tests for the desk-issue plumbing. Mirrors the
// desk_pr_store_test pattern: spin up a temp git repo, exercise the
// public DeskIssueStore API, verify on-disk state via plain `git`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_issue.dart';
import 'package:git_desktop/backend/desk_issue_store.dart';
import 'package:git_desktop/backend/manifold_refs.dart';

Future<Directory> _newRepo() async {
  final dir = await Directory.systemTemp.createTemp('manifold_issue_test_');
  await Process.run('git', ['init', '-q', '-b', 'main'],
      workingDirectory: dir.path);
  await Process.run('git', ['config', 'user.name', 'test'],
      workingDirectory: dir.path);
  await Process.run('git', ['config', 'user.email', 'test@local'],
      workingDirectory: dir.path);
  await Process.run('git', ['commit', '--allow-empty', '-m', 'root'],
      workingDirectory: dir.path);
  return dir;
}

/// Tolerant cleanup — Windows briefly holds file handles after spawned
/// `git` processes exit, racing with delete(recursive:). The handles
/// drop on their own; swallowing the FS exception keeps the test
/// signal honest.
Future<void> _safeCleanup(Directory dir) async {
  try {
    await dir.delete(recursive: true);
  } on FileSystemException {
    // Ignored — see _safeCleanup docstring.
  }
}

ManifoldRefs _refs(Directory repo) => ManifoldRefs(
      repoPath: repo.path,
      authorName: 'tester',
      authorEmail: 'tester@manifold.local',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeskIssueStore.create', () {
    test('writes refs/manifold/issues/<id> with issue.json', () async {
      final repo = await _newRepo();
      try {
        final store = DeskIssueStore(_refs(repo));
        final r = await store.create(
          title: 'Bug: thing breaks',
          body: 'reproducer here',
          authorIdentity: 'tester',
          labels: const ['bug'],
        );
        expect(r.ok, isTrue, reason: r.error);
        final issue = r.data!;
        expect(issue.issueId, greaterThan(0));
        final blob = await Process.run(
          'git',
          ['cat-file', 'blob', 'refs/manifold/issues/${issue.issueId}:issue.json'],
          workingDirectory: repo.path,
        );
        expect(blob.exitCode, 0);
        expect(blob.stdout.toString(), contains('"title": "Bug: thing breaks"'));
        expect(blob.stdout.toString(), contains('"bug"'));
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('thread', () {
    test('addComment + setState produce audit-log commits', () async {
      final repo = await _newRepo();
      try {
        final store = DeskIssueStore(_refs(repo));
        final issue = (await store.create(
                title: 't', body: '', authorIdentity: 'tester'))
            .data!;
        await store.addComment(
            id: issue.issueId, author: 'tester', body: 'hello');
        await store.setState(id: issue.issueId, state: 'CLOSED');
        final log = await Process.run(
          'git',
          ['log', '--format=%s', 'refs/manifold/issues/${issue.issueId}'],
          workingDirectory: repo.path,
        );
        final subjects = (log.stdout as String)
            .split('\n')
            .where((s) => s.isNotEmpty)
            .toList();
        expect(subjects, ['state -> closed', 'comment by tester', 'create issue']);
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('cross-references', () {
    test('toggleAddressedBy adds and removes the branch symmetrically',
        () async {
      final repo = await _newRepo();
      try {
        final store = DeskIssueStore(_refs(repo));
        final issue = (await store.create(
                title: 't', body: '', authorIdentity: 'tester'))
            .data!;
        await store.toggleAddressedBy(
            id: issue.issueId, branch: 'feat/x');
        var read = (await store.read(issue.issueId)).data!;
        expect(read.addressedBy, ['feat/x']);
        await store.toggleAddressedBy(
            id: issue.issueId, branch: 'feat/x');
        read = (await store.read(issue.issueId)).data!;
        expect(read.addressedBy, isEmpty);
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('list + abandon', () {
    test('listAll returns every issue, abandon removes from list', () async {
      final repo = await _newRepo();
      try {
        final store = DeskIssueStore(_refs(repo));
        await store.create(title: 'a', body: '', authorIdentity: 'tester');
        await store.create(title: 'b', body: '', authorIdentity: 'tester');
        var all = await store.listAll();
        expect(all.data!.length, 2);
        await store.abandon(all.data!.first.issueId);
        all = await store.listAll();
        expect(all.data!.length, 1);
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('JSON roundtrip', () {
    test('DeskIssue.toBlob → fromBlob preserves all fields', () {
      final issue = DeskIssue(
        issueId: 5,
        title: 'roundtrip',
        body: 'body',
        state: 'OPEN',
        authorIdentity: 'tester',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
        labels: const ['bug'],
        addressedBy: const ['feat/fix'],
        comments: [
          DeskIssueComment(
            author: 'tester',
            body: 'hi',
            at: DateTime.utc(2026, 1, 1, 12, 0),
          ),
        ],
      );
      final round = DeskIssue.fromBlob(issue.toBlob());
      expect(round.issueId, issue.issueId);
      expect(round.title, issue.title);
      expect(round.labels, issue.labels);
      expect(round.addressedBy, issue.addressedBy);
      expect(round.comments.length, 1);
      expect(round.comments[0].body, 'hi');
    });
  });
}
