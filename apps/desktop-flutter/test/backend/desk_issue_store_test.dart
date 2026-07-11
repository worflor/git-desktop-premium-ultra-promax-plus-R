// Integration tests for the desk-issue plumbing. Mirrors the
// desk_pr_store_test pattern: spin up a temp git repo, exercise the
// public DeskIssueStore API, verify on-disk state via plain `git`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_issue.dart';
import 'package:git_desktop/backend/desk_issue_store.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/manifold_refs.dart';
import '../support/must.dart';

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

/// A ManifoldRefs that lets a test land ONE interfering commit at the
/// exact instant just before the store's first CAS update-ref runs — so
/// that update-ref sees a stale oldSha and rejects, forcing the store's
/// read-transform-commit retry loop to fire deterministically (no
/// reliance on scheduler luck). After it fires once it behaves normally,
/// so the retry succeeds.
class _RaceRefs extends ManifoldRefs {
  _RaceRefs({
    required super.repoPath,
    required super.authorName,
    required super.authorEmail,
  });

  bool _fired = false;
  Future<void> Function()? onFirstUpdate;

  @override
  Future<GitResult<void>> updateRef({
    required LiveManifoldRef ref,
    required CommitOid newSha,
    Oid? oldSha,
  }) async {
    if (!_fired && onFirstUpdate != null) {
      _fired = true;
      await onFirstUpdate!();
    }
    return super.updateRef(ref: ref, newSha: newSha, oldSha: oldSha);
  }
}

/// Overwrite the shared id-counter ref to [value] via raw plumbing,
/// simulating a force-fetch that rewound the counter below live ids.
Future<void> _forceCounter(ManifoldRefs refs, int value) async {
  final blob = await refs.writeBlob('$value\n');
  final tree = await refs.mkTree({'counter.txt': blob.data!});
  final commit = await refs.commitTree(
    treeSha: tree.data!,
    message: 'regress counter to $value',
  );
  final upd = await refs.updateRef(
    ref: ManifoldNs.idCounter,
    newSha: commit.data!,
  );
  expect(upd.ok, isTrue,
      reason: 'counter-regression setup must actually land: ${upd.error}');
}

Future<Directory> _bareRemote() async {
  final dir = await Directory.systemTemp.createTemp('manifold_remote_');
  await Process.run('git', ['init', '-q', '--bare', dir.path]);
  return dir;
}

Future<Directory> _cloneOf(Directory remote, String label) async {
  final parent = await Directory.systemTemp.createTemp('manifold_clone_${label}_');
  final dst = Directory('${parent.path}/repo');
  await Process.run('git', ['clone', '-q', remote.path, dst.path]);
  await Process.run('git', ['config', 'user.name', 'test'],
      workingDirectory: dst.path);
  await Process.run('git', ['config', 'user.email', 'test@local'],
      workingDirectory: dst.path);
  return dst;
}

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
        await expectOk(store.addComment(
            id: issue.issueId, author: 'tester', body: 'hello'));
        await expectOk(store.setState(id: issue.issueId, state: 'CLOSED'));
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
        await expectOk(store.toggleAddressedBy(
            id: issue.issueId, branch: 'feat/x'));
        var read = (await store.read(issue.issueId)).data!;
        expect(read.addressedBy, ['feat/x']);
        await expectOk(store.toggleAddressedBy(
            id: issue.issueId, branch: 'feat/x'));
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
        await expectOk(store.create(title: 'a', body: '', authorIdentity: 'tester'));
        await expectOk(store.create(title: 'b', body: '', authorIdentity: 'tester'));
        var all = await store.listAll();
        expect(all.data!.length, 2);
        await expectOk(store.abandon(all.data!.first.issueId));
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

  group('CAS retry', () {
    test('a losing writer re-applies onto the winner — both comments survive',
        () async {
      final repo = await _newRepo();
      try {
        final store = DeskIssueStore(_refs(repo));
        final issue = (await store.create(
                title: 't', body: '', authorIdentity: 'tester'))
            .data!;

        // The racing store lands an interfering comment right before its
        // own first CAS commit, guaranteeing that commit rejects and the
        // retry loop must re-read and re-apply.
        final raceRefs = _RaceRefs(
          repoPath: repo.path,
          authorName: 'tester',
          authorEmail: 'tester@manifold.local',
        );
        final raceStore = DeskIssueStore(raceRefs);
        raceRefs.onFirstUpdate = () async {
          final interferer = DeskIssueStore(_refs(repo));
          final r = await interferer.addComment(
              id: issue.issueId, author: 'interferer', body: 'landed first');
          expect(r.ok, isTrue, reason: r.error);
        };

        final r = await raceStore.addComment(
            id: issue.issueId, author: 'racer', body: 'landed after retry');
        expect(r.ok, isTrue, reason: r.error);

        final read = (await store.read(issue.issueId)).data!;
        final bodies = read.comments.map((c) => c.body).toList();
        // Neither write was dropped: the interferer's comment and the
        // retried racer's comment are both present.
        expect(bodies, containsAll(<String>['landed first', 'landed after retry']));
        expect(read.comments.length, 2);
      } finally {
        await _safeCleanup(repo);
      }
    });

    test('two concurrently-fired comments both survive', () async {
      final repo = await _newRepo();
      try {
        final store = DeskIssueStore(_refs(repo));
        final issue = (await store.create(
                title: 't', body: '', authorIdentity: 'tester'))
            .data!;
        // Fire several comments at once. Whatever the interleaving, the
        // retry loop guarantees none are dropped.
        await Future.wait([
          for (var i = 0; i < 5; i++)
            store.addComment(
                id: issue.issueId, author: 'w$i', body: 'comment $i'),
        ]);
        final read = (await store.read(issue.issueId)).data!;
        expect(read.comments.length, 5);
        expect(
          read.comments.map((c) => c.body).toSet(),
          {for (var i = 0; i < 5; i++) 'comment $i'},
        );
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('counter regression guard', () {
    test('allocation never reissues a live id after the counter rewinds',
        () async {
      final repo = await _newRepo();
      try {
        final refs = _refs(repo);
        final store = DeskIssueStore(refs);
        final first = (await store.create(
                title: 'first', body: '', authorIdentity: 'tester'))
            .data!;
        expect(first.issueId, 1);

        // Simulate a force-fetch that rewound the shared counter below
        // the id we just handed out.
        await _forceCounter(refs, 0);

        // Without the guard this would recompute next = 0 + 1 = 1 and
        // collide with the live issue #1. The guard floors it at
        // (highest live id) + 1 = 2.
        final second = (await store.create(
                title: 'second', body: '', authorIdentity: 'tester'))
            .data!;
        expect(second.issueId, isNot(1));
        expect(second.issueId, 2);

        // The original issue is untouched — no overwrite.
        final all = (await store.listAll()).data!;
        expect(all.map((i) => i.issueId).toSet(), {1, 2});
        expect((await store.read(1)).data!.title, 'first');
      } finally {
        await _safeCleanup(repo);
      }
    });
  });

  group('error honesty', () {
    test('genuinely-missing refs read as ok(null); a broken repo reads as err',
        () async {
      final repo = await _newRepo();
      final nonRepo =
          await Directory.systemTemp.createTemp('manifold_nonrepo_');
      try {
        final good = _refs(repo);
        // Missing ref in a valid repo → ok(null), not an error.
        final rMissing = await good.resolveRef(LiveManifoldRef.issue(999));
        expect(rMissing.ok, isTrue);
        expect(rMissing.data, isNull);
        final bMissing =
            await good.readRefBlob(LiveManifoldRef.issue(999), 'issue.json');
        expect(bMissing.ok, isTrue);
        expect(bMissing.data, isNull);

        // A non-git directory is a real failure — git exits 128 with
        // "not a git repository". The old code swallowed this as ok(null)
        // and reported "no issues"; now it propagates as an error.
        final broken = ManifoldRefs(
          repoPath: nonRepo.path,
          authorName: 'tester',
          authorEmail: 'tester@manifold.local',
        );
        final rBroken = await broken.resolveRef(LiveManifoldRef.issue(1));
        expect(rBroken.ok, isFalse);
        final bBroken =
            await broken.readRefBlob(LiveManifoldRef.issue(1), 'issue.json');
        expect(bBroken.ok, isFalse);
      } finally {
        await _safeCleanup(repo);
        await _safeCleanup(nonRepo);
      }
    });
  });

  group('fetch refspec parity', () {
    test(
        'creating an issue configures the STAGING fetch refspec on origin '
        '(never the dangerous live-ref refspec)', () async {
      final remote = await _bareRemote();
      final clone = await _cloneOf(remote, 'refspec');
      try {
        final store = DeskIssueStore(_refs(clone));
        await expectOk(store.create(title: 'x', body: '', authorIdentity: 'tester'));
        final cfg = await Process.run(
          'git',
          ['config', '--get-all', 'remote.origin.fetch'],
          workingDirectory: clone.path,
        );
        final out = cfg.stdout.toString();
        // The safe staging refspec is installed…
        expect(out, contains('+refs/manifold/*:refs/manifold-remote/origin/*'));
        // …and the dangerous live-ref refspec is NOT.
        expect(out, isNot(contains('+refs/manifold/*:refs/manifold/*')));
      } finally {
        await _safeCleanup(clone);
        await _safeCleanup(remote);
      }
    });

    test(
        'ensureFetchRefspec MIGRATES away a previously-configured live-ref '
        'refspec, leaving unrelated fetch refspecs intact', () async {
      final remote = await _bareRemote();
      final clone = await _cloneOf(remote, 'migrate');
      try {
        // Simulate a repo configured by an older build with the dangerous
        // wildcard refspec, plus an unrelated user refspec that must survive.
        await Process.run(
          'git',
          ['config', '--add', 'remote.origin.fetch',
              '+refs/manifold/*:refs/manifold/*'],
          workingDirectory: clone.path,
        );
        await Process.run(
          'git',
          ['config', '--add', 'remote.origin.fetch',
              '+refs/notes/*:refs/notes/*'],
          workingDirectory: clone.path,
        );

        await _refs(clone).ensureFetchRefspec();

        final cfg = await Process.run(
          'git',
          ['config', '--get-all', 'remote.origin.fetch'],
          workingDirectory: clone.path,
        );
        final out = cfg.stdout.toString();
        // Legacy live-ref refspec removed.
        expect(out, isNot(contains('+refs/manifold/*:refs/manifold/*')));
        // Staging refspec installed.
        expect(out, contains('+refs/manifold/*:refs/manifold-remote/origin/*'));
        // Unrelated refspec untouched.
        expect(out, contains('+refs/notes/*:refs/notes/*'));
        // Default heads refspec untouched.
        expect(out, contains('+refs/heads/*:refs/remotes/origin/*'));
      } finally {
        await _safeCleanup(clone);
        await _safeCleanup(remote);
      }
    });
  });

  group('sync reconcile (data-loss fix)', () {
    // Reads the current tip sha of a manifold ref via raw git.
    Future<String> tipOf(Directory repo, String ref) async {
      final r = await Process.run('git', ['rev-parse', ref],
          workingDirectory: repo.path);
      return (r.stdout as String).trim();
    }

    test(
        'diverged unpushed comments both survive; sync converges with no '
        'further ref movement (the verified repro)', () async {
      final remote = await _bareRemote();
      final cloneA = await _cloneOf(remote, 'A');
      final cloneB = await _cloneOf(remote, 'B');
      try {
        await Process.run('git', ['commit', '--allow-empty', '-m', 'root'],
            workingDirectory: cloneA.path);
        final storeA = DeskIssueStore(_refs(cloneA));
        final storeB = DeskIssueStore(_refs(cloneB));

        // A creates + pushes; B pulls it down.
        final issue = (await storeA.create(
                title: 'shared', body: '', authorIdentity: 'A'))
            .data!;
        expect((await storeA.syncWithRemote()).ok, isTrue);
        expect((await storeB.syncWithRemote()).ok, isTrue);

        // A comments locally (UNPUSHED). B comments and syncs (remote moves).
        await expectOk(storeA.addComment(
            id: issue.issueId, author: 'A', body: 'from A'));
        await expectOk(storeB.addComment(
            id: issue.issueId, author: 'B', body: 'from B'));
        expect((await storeB.syncWithRemote()).ok, isTrue);

        // A syncs into the divergence — must UNION, not rewind.
        final syncA = await storeA.syncWithRemote();
        expect(syncA.ok, isTrue, reason: syncA.error);
        final aComments =
            (await storeA.read(issue.issueId)).data!.comments.map((c) => c.body).toSet();
        expect(aComments, {'from A', 'from B'});

        // B syncs again — fast-forwards onto A's merge (A's merge names B's
        // tip as a parent), so B gets both without a fresh merge.
        final syncB = await storeB.syncWithRemote();
        expect(syncB.ok, isTrue, reason: syncB.error);
        final bComments =
            (await storeB.read(issue.issueId)).data!.comments.map((c) => c.body).toSet();
        expect(bComments, {'from A', 'from B'});

        // Both tips are now the same content-identical commit.
        final ref = DeskIssueStore.refFor(issue.issueId);
        final aTip = await tipOf(cloneA, ref);
        final bTip = await tipOf(cloneB, ref);
        expect(aTip, bTip, reason: 'sides converged to one tip');

        // A third sync moves nothing — no ping-pong.
        final beforeThird = await tipOf(cloneA, ref);
        expect((await storeA.syncWithRemote()).ok, isTrue);
        expect((await storeB.syncWithRemote()).ok, isTrue);
        expect(await tipOf(cloneA, ref), beforeThird);
        expect(await tipOf(cloneB, ref), beforeThird);
      } finally {
        await _safeCleanup(cloneA);
        await _safeCleanup(cloneB);
        await _safeCleanup(remote);
      }
    });

    test(
        'a plain `git fetch` never rewinds a local-ahead manifold ref '
        '(staging namespace proof)', () async {
      final remote = await _bareRemote();
      final cloneA = await _cloneOf(remote, 'pfA');
      final cloneB = await _cloneOf(remote, 'pfB');
      try {
        await Process.run('git', ['commit', '--allow-empty', '-m', 'root'],
            workingDirectory: cloneA.path);
        final storeA = DeskIssueStore(_refs(cloneA));
        final storeB = DeskIssueStore(_refs(cloneB));
        final issue = (await storeA.create(
                title: 'x', body: '', authorIdentity: 'A'))
            .data!;
        expect((await storeA.syncWithRemote()).ok, isTrue);
        // B pulls it (this also persists the staging fetch refspec on B).
        expect((await storeB.syncWithRemote()).ok, isTrue);

        // B moves its local ref AHEAD of the remote, and does NOT push.
        await expectOk(storeB.addComment(
            id: issue.issueId, author: 'B', body: 'unpushed-local'));
        final ref = DeskIssueStore.refFor(issue.issueId);
        final before = await tipOf(cloneB, ref);

        // A plain `git fetch` (the configured refspec). Under the old
        // live-ref refspec this force-rewound B's ref to the remote tip,
        // eating the comment. With staging it can't touch the live ref.
        final fetch = await Process.run('git', ['fetch', 'origin'],
            workingDirectory: cloneB.path);
        expect(fetch.exitCode, 0, reason: fetch.stderr.toString());

        expect(await tipOf(cloneB, ref), before, reason: 'live ref untouched');
        expect(
            (await storeB.read(issue.issueId)).data!.comments.map((c) => c.body),
            contains('unpushed-local'));
      } finally {
        await _safeCleanup(cloneA);
        await _safeCleanup(cloneB);
        await _safeCleanup(remote);
      }
    });
  });

  group('counter reconcile by MAX', () {
    Future<int> counterOf(DeskIssueStore store) async {
      final b =
          await store.refs.readRefBlob(ManifoldNs.idCounter, 'counter.txt');
      return int.tryParse((b.data ?? '').trim()) ?? 0;
    }

    test('remote counter higher → local adopts it; lower → local keeps',
        () async {
      final remote = await _bareRemote();
      final cloneA = await _cloneOf(remote, 'ctrA');
      final cloneB = await _cloneOf(remote, 'ctrB');
      try {
        await Process.run('git', ['commit', '--allow-empty', '-m', 'root'],
            workingDirectory: cloneA.path);
        final refsA = _refs(cloneA);
        final refsB = _refs(cloneB);
        final storeA = DeskIssueStore(refsA);
        final storeB = DeskIssueStore(refsB);
        await expectOk(storeA.create(title: 'x', body: '', authorIdentity: 'A'));
        expect((await storeA.syncWithRemote()).ok, isTrue); // remote counter=1
        expect((await storeB.syncWithRemote()).ok, isTrue); // B counter=1

        // B force-advances its counter and pushes → remote counter = 5.
        await _forceCounter(refsB, 5);
        expect((await storeB.syncWithRemote()).ok, isTrue);

        // A (counter=1) syncs → adopts the higher remote counter.
        expect((await storeA.syncWithRemote()).ok, isTrue);
        expect(await counterOf(storeA), 5, reason: 'adopts higher remote');

        // A force-advances above remote → keeps its own, pushes it up.
        await _forceCounter(refsA, 9);
        expect((await storeA.syncWithRemote()).ok, isTrue);
        expect(await counterOf(storeA), 9, reason: 'keeps higher local');
        // And the higher value propagated to the remote (B adopts it).
        expect((await storeB.syncWithRemote()).ok, isTrue);
        expect(await counterOf(storeB), 9);
      } finally {
        await _safeCleanup(cloneA);
        await _safeCleanup(cloneB);
        await _safeCleanup(remote);
      }
    });
  });

  group('push/fetch round-trip', () {
    test('an issue created in clone A lists identically in clone B', () async {
      final remote = await _bareRemote();
      final cloneA = await _cloneOf(remote, 'A');
      try {
        // Clone A needs a root commit so it isn't headless before push
        // (the manifold refs push independently regardless).
        await Process.run('git', ['commit', '--allow-empty', '-m', 'root'],
            workingDirectory: cloneA.path);
        final storeA = DeskIssueStore(_refs(cloneA));
        final created = (await storeA.create(
          title: 'shared issue',
          body: 'crosses the wire',
          authorIdentity: 'tester',
          labels: const ['bug'],
        ))
            .data!;
        // Push manifold refs to origin.
        final syncA = await storeA.syncWithRemote();
        expect(syncA.ok, isTrue, reason: syncA.error);

        // Clone B pulls them down.
        final cloneB = await _cloneOf(remote, 'B');
        try {
          final storeB = DeskIssueStore(_refs(cloneB));
          final syncB = await storeB.syncWithRemote();
          expect(syncB.ok, isTrue, reason: syncB.error);

          final listA = (await storeA.listAll()).data!;
          final listB = (await storeB.listAll()).data!;
          expect(listB.length, listA.length);
          final b = listB.single;
          expect(b.issueId, created.issueId);
          expect(b.title, 'shared issue');
          expect(b.body, 'crosses the wire');
          expect(b.labels, ['bug']);
        } finally {
          await _safeCleanup(cloneB);
        }
      } finally {
        await _safeCleanup(cloneA);
        await _safeCleanup(remote);
      }
    });
  });
}
