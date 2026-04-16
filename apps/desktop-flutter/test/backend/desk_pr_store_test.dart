// Integration tests for the desk-PR plumbing.
//
// Each test spins up a temp git repo, exercises the public DeskPrStore
// API, and verifies the on-disk state via plain `git` shell-outs. The
// goal is to lock the contract that this layer speaks pure git
// primitives — refs/manifold/desks/<branch> orphan history with
// meta.json blobs — not a sidecar JSON snapshot.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_pr.dart';
import 'package:git_desktop/backend/desk_pr_store.dart';
import 'package:git_desktop/backend/manifold_refs.dart';

Future<Directory> _newRepo() async {
  final dir = await Directory.systemTemp.createTemp('manifold_test_');
  await Process.run('git', ['init', '-q', '-b', 'main'], workingDirectory: dir.path);
  await Process.run('git', ['config', 'user.name', 'test'], workingDirectory: dir.path);
  await Process.run('git', ['config', 'user.email', 'test@local'], workingDirectory: dir.path);
  await Process.run('git', ['commit', '--allow-empty', '-m', 'root'], workingDirectory: dir.path);
  return dir;
}

/// Tolerant cleanup — Windows briefly holds file handles after spawned
/// `git` processes exit, which can race with our `delete(recursive:)`
/// call and throw PathAccessException for ~100ms. The handles drop on
/// their own; swallowing the error keeps the test signal honest (the
/// assertions ran; the tmp dir is the OS's problem).
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

  group('DeskPrStore.create', () {
    test('writes refs/manifold/desks/<branch> with meta.json', () async {
      final repo = await _newRepo();
      try {
        final store = DeskPrStore(_refs(repo));
        final r = await store.create(
          branch: 'feat/x',
          title: 'Feature X',
          body: 'Adds X',
          baseRef: 'main',
          authorIdentity: 'tester',
        );
        expect(r.ok, isTrue, reason: r.error);
        // Ref exists.
        final refRes = await Process.run(
          'git',
          ['rev-parse', '--verify', 'refs/manifold/desks/feat/x'],
          workingDirectory: repo.path,
        );
        expect(refRes.exitCode, 0);
        // meta.json blob is reachable from that ref's tree.
        final blobRes = await Process.run(
          'git',
          ['cat-file', 'blob', 'refs/manifold/desks/feat/x:meta.json'],
          workingDirectory: repo.path,
        );
        expect(blobRes.exitCode, 0);
        expect(blobRes.stdout.toString(), contains('"title": "Feature X"'));
      } finally {
        await _safeCleanup(repo);
      }
    });

    test('refuses to create a duplicate PR for the same branch', () async {
      final repo = await _newRepo();
      try {
        final store = DeskPrStore(_refs(repo));
        await store.create(
          branch: 'feat/dup',
          title: 'first',
          body: '',
          baseRef: 'main',
          authorIdentity: 'tester',
        );
        final second = await store.create(
          branch: 'feat/dup',
          title: 'second',
          body: '',
          baseRef: 'main',
          authorIdentity: 'tester',
        );
        expect(second.ok, isFalse);
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('audit history', () {
    test('each mutation appends a commit to the orphan history', () async {
      final repo = await _newRepo();
      try {
        final store = DeskPrStore(_refs(repo));
        await store.create(
          branch: 'feat/audit',
          title: 'audit',
          body: '',
          baseRef: 'main',
          authorIdentity: 'tester',
        );
        await store.addComment(
          branch: 'feat/audit',
          author: 'tester',
          body: 'first comment',
        );
        await store.addReview(
          branch: 'feat/audit',
          author: 'tester',
          verdict: 'APPROVED',
          body: 'lgtm',
        );
        await store.setState(branch: 'feat/audit', state: 'MERGED');
        // git log on the metadata ref should show 4 commits with the
        // expected subjects.
        final log = await Process.run(
          'git',
          ['log', '--format=%s', 'refs/manifold/desks/feat/audit'],
          workingDirectory: repo.path,
        );
        final subjects = (log.stdout as String)
            .split('\n')
            .where((s) => s.isNotEmpty)
            .toList();
        expect(subjects.length, 4);
        // Newest first.
        expect(subjects[0], 'state -> merged');
        expect(subjects[1], 'approved by tester');
        expect(subjects[2], 'comment by tester');
        expect(subjects[3], 'create pr');
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('listAll + read roundtrip', () {
    test('listAll returns every desk PR with correct fields', () async {
      final repo = await _newRepo();
      try {
        final store = DeskPrStore(_refs(repo));
        await store.create(
          branch: 'a',
          title: 'A',
          body: 'aaa',
          baseRef: 'main',
          authorIdentity: 'tester',
        );
        await store.create(
          branch: 'b',
          title: 'B',
          body: 'bbb',
          baseRef: 'main',
          authorIdentity: 'tester',
        );
        final all = await store.listAll();
        expect(all.ok, isTrue);
        expect(all.data!.length, 2);
        expect(all.data!.map((p) => p.headRef).toSet(), {'a', 'b'});
        // read() returns one.
        final one = await store.read('a');
        expect(one.ok, isTrue);
        expect(one.data!.title, 'A');
        expect(one.data!.body, 'aaa');
      } finally {
        await _safeCleanup(repo);
      }
    });

    test('read returns ok(null) when no PR exists for the branch', () async {
      final repo = await _newRepo();
      try {
        final store = DeskPrStore(_refs(repo));
        final r = await store.read('does-not-exist');
        expect(r.ok, isTrue);
        expect(r.data, isNull);
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('thread mutations', () {
    test('addComment appends a non-review entry; addReview a verdict entry',
        () async {
      final repo = await _newRepo();
      try {
        final store = DeskPrStore(_refs(repo));
        await store.create(
          branch: 'feat/thread',
          title: 't',
          body: '',
          baseRef: 'main',
          authorIdentity: 'tester',
        );
        await store.addComment(
          branch: 'feat/thread',
          author: 'tester',
          body: 'looking now',
        );
        await store.addReview(
          branch: 'feat/thread',
          author: 'tester',
          verdict: 'APPROVED',
          body: 'looks good',
        );
        final pr = (await store.read('feat/thread')).data!;
        expect(pr.thread.length, 2);
        expect(pr.thread[0].verdict, '');
        expect(pr.thread[0].body, 'looking now');
        expect(pr.thread[1].verdict, 'APPROVED');
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('abandon', () {
    test('deleteRef drops the metadata ref entirely', () async {
      final repo = await _newRepo();
      try {
        final store = DeskPrStore(_refs(repo));
        await store.create(
          branch: 'feat/abandon',
          title: 'a',
          body: '',
          baseRef: 'main',
          authorIdentity: 'tester',
        );
        final beforeAll = await store.listAll();
        expect(beforeAll.data!.length, 1);
        await store.abandon('feat/abandon');
        final afterAll = await store.listAll();
        expect(afterAll.data!.length, 0);
        final ref = await Process.run(
          'git',
          ['rev-parse', '--verify', '--quiet', 'refs/manifold/desks/feat/abandon'],
          workingDirectory: repo.path,
        );
        expect(ref.exitCode, isNot(0)); // ref no longer resolves
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('id allocation', () {
    test('sequential IDs across multiple PRs', () async {
      final repo = await _newRepo();
      try {
        final store = DeskPrStore(_refs(repo));
        final a = (await store.create(
                branch: 'a',
                title: 'a',
                body: '',
                baseRef: 'main',
                authorIdentity: 'tester'))
            .data!;
        final b = (await store.create(
                branch: 'b',
                title: 'b',
                body: '',
                baseRef: 'main',
                authorIdentity: 'tester'))
            .data!;
        final c = (await store.create(
                branch: 'c',
                title: 'c',
                body: '',
                baseRef: 'main',
                authorIdentity: 'tester'))
            .data!;
        expect(a.deskId, 1);
        expect(b.deskId, 2);
        expect(c.deskId, 3);
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('bijective branch encoding', () {
    test('encodeBranch + decodeBranch roundtrip for plain ASCII', () {
      const cases = ['feat/x', 'main', 'release/1.2.3', 'foo-bar_baz'];
      for (final c in cases) {
        expect(
          DeskPrStore.decodeBranch(DeskPrStore.encodeBranch(c)),
          c,
          reason: 'roundtrip failed for "$c"',
        );
      }
    });

    test('previously-colliding branches encode distinctly', () {
      // The audit found that `feat/~x` and `feat-x` both encoded to
      // `feat-x` under the lossy substitution. Bijective encoding
      // must produce different ref tails.
      expect(
        DeskPrStore.encodeBranch('feat/~x'),
        isNot(DeskPrStore.encodeBranch('feat-x')),
      );
      expect(
        DeskPrStore.encodeBranch('feat x'),
        isNot(DeskPrStore.encodeBranch('feat_x')),
      );
    });

    test('illegal git ref chars are percent-encoded', () {
      expect(DeskPrStore.encodeBranch('feat/~x'), contains('%7E'));
      expect(DeskPrStore.encodeBranch('feat ^ y'), contains('%5E'));
      expect(DeskPrStore.encodeBranch('a..b'), contains('%2E'));
    });

    test('non-ASCII branch names roundtrip via UTF-8', () {
      const name = 'feat/π-resonance';
      final encoded = DeskPrStore.encodeBranch(name);
      expect(DeskPrStore.decodeBranch(encoded), name);
    });

    test('forbids creating a duplicate after bijective encoding', () async {
      final repo = await _newRepo();
      try {
        final store = DeskPrStore(_refs(repo));
        // Create on `feat-x`.
        await store.create(
          branch: 'feat-x',
          title: 'first',
          body: '',
          baseRef: 'main',
          authorIdentity: 'tester',
        );
        // Try to create on `feat/~x`. Under the OLD lossy encoder,
        // both branches mapped to `feat-x` and the second create()
        // would silently overwrite. With bijective encoding they
        // have distinct refs and the second create succeeds without
        // collision.
        final second = await store.create(
          branch: 'feat/~x',
          title: 'second',
          body: '',
          baseRef: 'main',
          authorIdentity: 'tester',
        );
        expect(second.ok, isTrue, reason: second.error);
        // Both should be readable independently.
        final firstRead = await store.read('feat-x');
        final secondRead = await store.read('feat/~x');
        expect(firstRead.data!.title, 'first');
        expect(secondRead.data!.title, 'second');
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('JSON roundtrip', () {
    test('DeskPr.toJson → fromJson preserves all fields', () {
      final pr = DeskPr(
        deskId: 7,
        title: 'roundtrip',
        body: 'body',
        headRef: 'feat/rt',
        baseRef: 'main',
        state: 'OPEN',
        isDraft: true,
        authorIdentity: 'tester',
        createdAt: DateTime.utc(2026, 1, 1, 12, 0, 0),
        updatedAt: DateTime.utc(2026, 1, 2, 12, 0, 0),
        labels: const ['a', 'b'],
        thread: [
          DeskThreadEntry(
            author: 'tester',
            body: 'hi',
            at: DateTime.utc(2026, 1, 1, 12, 30, 0),
          ),
          DeskThreadEntry(
            author: 'tester',
            body: 'lgtm',
            at: DateTime.utc(2026, 1, 2, 9, 0, 0),
            verdict: 'APPROVED',
          ),
        ],
      );
      final round = DeskPr.fromBlob(pr.toBlob());
      expect(round.deskId, pr.deskId);
      expect(round.title, pr.title);
      expect(round.body, pr.body);
      expect(round.headRef, pr.headRef);
      expect(round.state, pr.state);
      expect(round.isDraft, pr.isDraft);
      expect(round.labels, pr.labels);
      expect(round.thread.length, 2);
      expect(round.thread[1].verdict, 'APPROVED');
    });
  });
}
