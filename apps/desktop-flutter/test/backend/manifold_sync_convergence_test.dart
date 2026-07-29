// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// File-wide timeout: see the contention note in main() — heavy property
// cases pass solo in ~10-30s but share the global git-subprocess semaphore
// with the whole suite in integrated runs.
@Timeout(Duration(minutes: 3))
library;

// manifold_sync_convergence_test.dart — replication-protocol hardening
// for the Manifold refs sync engine (ManifoldRefs.syncWithRemote).
//
// desk_issue_store_test.dart / desk_pr_store_test.dart lock single
// scripted scenarios (one divergence, one race). This file tests the
// underlying anti-entropy protocol the way a distributed system's
// convergence properties are tested: randomized multi-replica op
// sequences driven to fixpoint, with invariants asserted over the
// converged state rather than over one hand-picked interleaving.
//
// All fixtures are temp bare-origin + clone(s), same pattern as the
// sibling test files. No commits to the real repo; nothing here builds
// the app. Every randomized case uses a fixed literal seed so a failure
// reproduces deterministically — the seed and the full op log are
// printed on any assertion failure so a failing case can be minimized
// by hand (or by a follow-up agent) without re-running the fuzzer.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_issue.dart';
import 'package:git_desktop/backend/desk_issue_store.dart';
import 'package:git_desktop/backend/desk_pr_store.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/manifold_refs.dart';
import '../support/must.dart';

// ─── Shared fixture plumbing (mirrors the sibling test files) ──────────

Future<Directory> _bareRemote(String label) async {
  final dir =
      await Directory.systemTemp.createTemp('manifold_conv_remote_${label}_');
  await Process.run('git', ['init', '-q', '--bare', dir.path]);
  return dir;
}

Future<Directory> _cloneOf(Directory remote, String label) async {
  final parent =
      await Directory.systemTemp.createTemp('manifold_conv_clone_${label}_');
  final dst = Directory('${parent.path}/repo');
  await Process.run('git', ['clone', '-q', remote.path, dst.path]);
  await Process.run('git', ['config', 'user.name', 'test'],
      workingDirectory: dst.path);
  await Process.run('git', ['config', 'user.email', 'test@local'],
      workingDirectory: dst.path);
  // A root commit so the clone isn't headless — matches the sibling
  // test files' pattern. Manifold refs push independently regardless.
  await Process.run('git', ['commit', '--allow-empty', '-m', 'root'],
      workingDirectory: dst.path);
  return dst;
}

Future<void> _safeCleanup(Directory dir) async {
  try {
    await dir.delete(recursive: true);
  } on FileSystemException {
    // Windows briefly holds handles after spawned git processes exit —
    // see the sibling test files' identical helper.
  }
}

ManifoldRefs _refsFor(Directory repo, String who) => ManifoldRefs(
      repoPath: repo.path,
      authorName: who,
      authorEmail: '$who@manifold.local',
    );

class _Clone {
  final Directory dir;
  final ManifoldRefs refs;
  final DeskIssueStore issues;
  final DeskPrStore prs;
  final String label;
  _Clone(this.dir, this.refs, this.issues, this.prs, this.label);
}

Future<_Clone> _makeClone(Directory remote, String label) async {
  final dir = await _cloneOf(remote, label);
  final refs = _refsFor(dir, label);
  return _Clone(dir, refs, DeskIssueStore(refs), DeskPrStore(refs), label);
}

Future<void> _cleanupAll(Directory remote, List<_Clone> clones) async {
  for (final c in clones) {
    await _safeCleanup(c.dir);
  }
  await _safeCleanup(remote);
}

/// True iff every clone's live `refs/manifold/*` namespace has the exact
/// same set of ref → sha entries. This is the "no ping-pong" convergence
/// check: the reconcile protocol's anti-ping-pong rule (content-identical
/// tips adopt the larger sha) is specifically designed to make sha
/// equality — not just content equality — reachable in a bounded number
/// of rounds.
Future<bool> _allRefsEqual(List<_Clone> clones) async {
  final maps = <Map<String, String>>[];
  for (final c in clones) {
    final r = await c.refs.listRefs(ManifoldRefs.manifoldPrefix);
    if (!r.ok) return false;
    maps.add(r.data!);
  }
  final first = maps.first;
  for (final m in maps.skip(1)) {
    if (m.length != first.length) return false;
    for (final e in first.entries) {
      if (m[e.key] != e.value) return false;
    }
  }
  return true;
}

/// Establish a shared baseline before the free-for-all randomized op
/// sequence begins: one clone creates a seed issue and pushes it, then
/// every clone (including that one) syncs once.
///
/// Without this, the fuzzer can pick two clones' very FIRST-EVER ops as
/// simultaneous creates with literally zero prior communication between
/// them or via the remote (the remote itself has nothing yet either).
/// That is a genuinely unsolvable race for a small-integer shared
/// counter — no local guard can invent knowledge neither side nor the
/// remote ever had, any more than two air-gapped machines can hand out
/// non-colliding serial numbers without a channel between them. It is
/// also not how this app is used: `create()` always configures the
/// fetch refspec, and the whole point of a clone is that it came from
/// somewhere reachable. Establishing one shared synced record models the
/// realistic starting condition (every clone has seen the remote at
/// least once) while still leaving the interesting regression surface —
/// mid-stream unsynced allocation races, counter regressions, divergent
/// concurrent edits — fully exercised by the random ops that follow.
Future<void> _establishBaseline(List<_Clone> clones, [_Registry? reg]) async {
  final seed = await clones.first.issues
      .create(title: 'baseline', body: '', authorIdentity: 'baseline');
  expect(seed.ok, isTrue, reason: seed.error);
  reg?.allIssueIds.add(seed.data!.issueId);
  for (final c in clones) {
    final r = await c.issues.syncWithRemote();
    expect(r.ok, isTrue, reason: 'baseline sync failed on ${c.label}: ${r.error}');
  }
}

/// Drive every clone to sync, round by round, until all live refs agree
/// bit-for-bit or [maxRounds] is exhausted. Returns the number of rounds
/// actually used (0 means already converged before any round ran).
Future<int> _syncToFixpoint(List<_Clone> clones,
    {int maxRounds = 3, List<String>? log}) async {
  if (await _allRefsEqual(clones)) return 0;
  for (var round = 1; round <= maxRounds; round++) {
    for (final c in clones) {
      final r = await c.issues.syncWithRemote();
      expect(r.ok, isTrue,
          reason: 'convergence sync failed on ${c.label}: ${r.error}'
              '${log != null ? '\n${log.join('\n')}' : ''}');
    }
    if (await _allRefsEqual(clones)) return round;
  }
  return maxRounds + 1; // did not converge within the bound
}

/// Audit-trail invariant (property 5): every live ref's history walks
/// without error, its tip parses as JSON (implied by the caller already
/// having read it via the store), and no commit has more than the two
/// documented parents (plain mutation commits have 0 or 1; reconcile
/// merges always take exactly `[local, staged]` — see
/// `ManifoldRefs.commitMergeTree`).
Future<void> _assertAuditTrailIntact(_Clone c, {List<String>? log}) async {
  final refsR = await c.refs.listRefs(ManifoldRefs.manifoldPrefix);
  expect(refsR.ok, isTrue);
  for (final ref in refsR.data!.keys) {
    final walk = await Process.run('git', ['rev-list', ref],
        workingDirectory: c.dir.path);
    expect(walk.exitCode, 0,
        reason: 'history walk failed for $ref on ${c.label}: '
            '${walk.stderr}${log != null ? '\n${log.join('\n')}' : ''}');
    final parents = await Process.run('git', ['log', '--format=%P', ref],
        workingDirectory: c.dir.path);
    expect(parents.exitCode, 0);
    for (final line in (parents.stdout as String).split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final n = t.split(' ').where((s) => s.isNotEmpty).length;
      expect(n, lessThanOrEqualTo(2),
          reason: 'commit on $ref has $n parents (documented max is 2 — '
              'local + staged)${log != null ? '\n${log.join('\n')}' : ''}');
    }
  }
}

// ─── Randomized op generator (property 1) ──────────────────────────────

const _authors = ['alice', 'bob', 'carol', 'dave'];
const _bodies = ['lgtm', 'needs work', 'question?', 'ship it', '+1', 'wat'];
const _verdicts = ['APPROVED', 'CHANGES_REQUESTED', 'COMMENTED'];

// Weighted op kinds — sync is deliberately frequent (~19%) so the
// generator regularly interleaves reconciliation with fresh mutations,
// the scenario the staging-namespace redesign exists to survive.
const _kinds = [
  'createIssue', 'createIssue',
  'commentIssue', 'commentIssue', 'commentIssue',
  'toggleStateIssue',
  'editMetaIssue',
  'toggleAddressedBy',
  'createPr', 'createPr',
  'commentPr', 'commentPr',
  'reviewPr',
  'setStatePr',
  'sync', 'sync', 'sync',
];

/// Tracks everything the harness needs to verify after convergence:
/// every id ever allocated, and every comment/thread-entry tuple ever
/// successfully written, keyed by the record it landed on.
class _Registry {
  int issueSeq = 0;
  int prSeq = 0;
  final Set<int> allIssueIds = {};
  final Set<String> allPrBranches = {};
  final Set<int> allDeskIds = {};
  final Map<int, List<({String author, String body, String at})>>
      issueComments = {};
  final Map<String, List<({String author, String body, String at})>>
      prThread = {};
}

Future<void> _applyOp(
  int step,
  _Clone clone,
  Random rand,
  _Registry reg,
  List<String> log,
) async {
  final kind = _kinds[rand.nextInt(_kinds.length)];
  log.add('#$step ${clone.label}: $kind');

  Future<void> fallbackCreateIssue() async {
    final title = 'issue-${reg.issueSeq++}';
    final r = await clone.issues
        .create(title: title, body: 'b', authorIdentity: clone.label);
    expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
    reg.allIssueIds.add(r.data!.issueId);
  }

  Future<void> fallbackCreatePr() async {
    final branch = 'feat/pr-${reg.prSeq++}';
    final r = await clone.prs.create(
      branch: branch,
      title: 'pr $branch',
      body: 'b',
      baseRef: 'main',
      authorIdentity: clone.label,
    );
    expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
    reg.allPrBranches.add(branch);
    reg.allDeskIds.add(r.data!.deskId);
  }

  switch (kind) {
    case 'sync':
      final r = await clone.issues.syncWithRemote();
      expect(r.ok, isTrue,
          reason: 'sync failed: ${r.error}\n${log.join('\n')}');
      break;

    case 'createIssue':
      await fallbackCreateIssue();
      break;

    case 'commentIssue':
      {
        final list = (await clone.issues.listAll()).data ?? [];
        if (list.isEmpty) {
          await fallbackCreateIssue();
          break;
        }
        final issue = list[rand.nextInt(list.length)];
        final author = _authors[rand.nextInt(_authors.length)];
        final body = _bodies[rand.nextInt(_bodies.length)];
        final r = await clone.issues
            .addComment(id: issue.issueId, author: author, body: body);
        expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
        final c = r.data!.comments.last;
        reg.issueComments.putIfAbsent(issue.issueId, () => []).add(
            (author: c.author, body: c.body, at: c.at.toIso8601String()));
        break;
      }

    case 'toggleStateIssue':
      {
        final list = (await clone.issues.listAll()).data ?? [];
        if (list.isEmpty) {
          await fallbackCreateIssue();
          break;
        }
        final issue = list[rand.nextInt(list.length)];
        final state = rand.nextBool() ? 'OPEN' : 'CLOSED';
        final r =
            await clone.issues.setState(id: issue.issueId, state: state);
        expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
        break;
      }

    case 'editMetaIssue':
      {
        final list = (await clone.issues.listAll()).data ?? [];
        if (list.isEmpty) {
          await fallbackCreateIssue();
          break;
        }
        final issue = list[rand.nextInt(list.length)];
        final r = await clone.issues.editMeta(
          id: issue.issueId,
          title: 'edited-by-${clone.label}-$step',
          labels: [_authors[rand.nextInt(_authors.length)]],
        );
        expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
        break;
      }

    case 'toggleAddressedBy':
      {
        final list = (await clone.issues.listAll()).data ?? [];
        if (list.isEmpty) {
          await fallbackCreateIssue();
          break;
        }
        final issue = list[rand.nextInt(list.length)];
        final branch = reg.allPrBranches.isEmpty
            ? 'feat/phantom-$step'
            : reg.allPrBranches
                .elementAt(rand.nextInt(reg.allPrBranches.length));
        final r = await clone.issues
            .toggleAddressedBy(id: issue.issueId, branch: branch);
        expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
        break;
      }

    case 'createPr':
      await fallbackCreatePr();
      break;

    case 'commentPr':
      {
        final list = (await clone.prs.listAll()).data ?? [];
        if (list.isEmpty) {
          await fallbackCreatePr();
          break;
        }
        final pr = list[rand.nextInt(list.length)];
        final author = _authors[rand.nextInt(_authors.length)];
        final body = _bodies[rand.nextInt(_bodies.length)];
        final r = await clone.prs
            .addComment(branch: pr.headRef, author: author, body: body);
        expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
        final t = r.data!.thread.last;
        reg.prThread.putIfAbsent(pr.headRef, () => []).add(
            (author: t.author, body: t.body, at: t.at.toIso8601String()));
        break;
      }

    case 'reviewPr':
      {
        final list = (await clone.prs.listAll()).data ?? [];
        if (list.isEmpty) {
          await fallbackCreatePr();
          break;
        }
        final pr = list[rand.nextInt(list.length)];
        final author = _authors[rand.nextInt(_authors.length)];
        final verdict = _verdicts[rand.nextInt(_verdicts.length)];
        final body = _bodies[rand.nextInt(_bodies.length)];
        final r = await clone.prs.addReview(
            branch: pr.headRef, author: author, verdict: verdict, body: body);
        expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
        final t = r.data!.thread.last;
        reg.prThread.putIfAbsent(pr.headRef, () => []).add(
            (author: t.author, body: t.body, at: t.at.toIso8601String()));
        break;
      }

    case 'setStatePr':
      {
        final list = (await clone.prs.listAll()).data ?? [];
        if (list.isEmpty) {
          await fallbackCreatePr();
          break;
        }
        final pr = list[rand.nextInt(list.length)];
        final state = ['OPEN', 'CLOSED', 'MERGED'][rand.nextInt(3)];
        final r =
            await clone.prs.setState(branch: pr.headRef, state: state);
        expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
        break;
      }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // These property cases drive dozens of real git subprocesses through the
  // process-global subprocess semaphore. Solo they run in ~10-30s, but under
  // the FULL suite that semaphore is shared with every other git-heavy test
  // file, so wall time can triple — the heaviest seed blew flutter_test's
  // default 30s per-test budget in the integrated run while passing solo.
  // The generous ceiling reflects contention, not expected runtime.

  // ─── 1. Randomized anti-entropy convergence ──────────────────────────
  group('randomized anti-entropy convergence', () {
    // Case count/op count tuned to stay well under the suite's runtime
    // budget while still exercising both replica counts. Each case's
    // full op log is printed on failure, so if a bug surfaces here it
    // can still be minimized to a shorter seed/prefix by hand.
    final cases = <({int seed, int n, int ops})>[
      (seed: 10001, n: 2, ops: 16),
      (seed: 10002, n: 2, ops: 16),
      (seed: 10003, n: 2, ops: 16),
      (seed: 10004, n: 3, ops: 16),
      (seed: 10005, n: 3, ops: 18),
    ];

    for (final spec in cases) {
      test(
          'seed=${spec.seed} n=${spec.n} ops=${spec.ops}: converges, no '
          'data loss, no id collisions, audit trail intact', () async {
        final rand = Random(spec.seed);
        final reg = _Registry();
        final log = <String>[];
        final remote = await _bareRemote('${spec.seed}');
        final clones = <_Clone>[];
        try {
          for (var i = 0; i < spec.n; i++) {
            clones.add(await _makeClone(remote, 'c$i-${spec.seed}'));
          }
          await _establishBaseline(clones, reg);

          for (var step = 0; step < spec.ops; step++) {
            final clone = clones[rand.nextInt(clones.length)];
            await _applyOp(step, clone, rand, reg, log);
          }

          // (b) fixpoint within a small bound — no ping-pong.
          final rounds = await _syncToFixpoint(clones, maxRounds: 3, log: log);
          expect(rounds, lessThanOrEqualTo(3),
              reason: 'did not converge (sha-identical refs across all '
                  'clones) within 3 full sync rounds\n${log.join('\n')}');

          // (a) content-identical across every clone, for every record
          // ever created.
          for (final id in reg.allIssueIds) {
            Map<String, dynamic>? base;
            for (final c in clones) {
              final r = await c.issues.read(id);
              expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
              expect(r.data, isNotNull,
                  reason: 'issue $id missing on ${c.label}\n'
                      '${log.join('\n')}');
              final decoded =
                  jsonDecode(r.data!.toBlob()) as Map<String, dynamic>;
              if (base == null) {
                base = decoded;
              } else {
                expect(decoded, base,
                    reason: 'issue $id content diverged on ${c.label}\n'
                        '${log.join('\n')}');
              }
            }
          }
          for (final branch in reg.allPrBranches) {
            Map<String, dynamic>? base;
            for (final c in clones) {
              final r = await c.prs.read(branch);
              expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
              expect(r.data, isNotNull,
                  reason: 'pr $branch missing on ${c.label}\n'
                      '${log.join('\n')}');
              final decoded =
                  jsonDecode(r.data!.toBlob()) as Map<String, dynamic>;
              if (base == null) {
                base = decoded;
              } else {
                expect(decoded, base,
                    reason: 'pr $branch content diverged on ${c.label}\n'
                        '${log.join('\n')}');
              }
            }
          }

          // (c) no comment/thread-entry ever written is missing from the
          // converged state.
          final witness = clones.first;
          for (final entry in reg.issueComments.entries) {
            final read = (await witness.issues.read(entry.key)).data!;
            final actual = read.comments
                .map((c) => (
                      author: c.author,
                      body: c.body,
                      at: c.at.toIso8601String()
                    ))
                .toSet();
            for (final expected in entry.value) {
              expect(actual, contains(expected),
                  reason: 'comment $expected lost from issue ${entry.key}\n'
                      '${log.join('\n')}');
            }
          }
          for (final entry in reg.prThread.entries) {
            final read = (await witness.prs.read(entry.key)).data!;
            final actual = read.thread
                .map((t) => (
                      author: t.author,
                      body: t.body,
                      at: t.at.toIso8601String()
                    ))
                .toSet();
            for (final expected in entry.value) {
              expect(actual, contains(expected),
                  reason:
                      'thread entry $expected lost from pr ${entry.key}\n'
                      '${log.join('\n')}');
            }
          }

          // (d) ids never collide, and none vanished.
          final converged0 = clones.first;
          final issueIds = (await converged0.issues.listAll())
              .data!
              .map((i) => i.issueId)
              .toList();
          final deskIds =
              (await converged0.prs.listAll()).data!.map((p) => p.deskId).toList();
          expect(issueIds.length, issueIds.toSet().length,
              reason: 'duplicate issue ids in converged state\n'
                  '${log.join('\n')}');
          expect(deskIds.length, deskIds.toSet().length,
              reason: 'duplicate desk ids in converged state\n'
                  '${log.join('\n')}');
          expect(issueIds.toSet().intersection(deskIds.toSet()), isEmpty,
              reason: 'issue id collided with a desk id (shared counter '
                  'breach)\n${log.join('\n')}');
          expect(issueIds.toSet(), reg.allIssueIds,
              reason: 'converged issue-id set != every id ever allocated\n'
                  '${log.join('\n')}');
          expect(deskIds.toSet(), reg.allDeskIds,
              reason: 'converged desk-id set != every id ever allocated\n'
                  '${log.join('\n')}');

          // (5) audit-trail invariant on the converged witness.
          await _assertAuditTrailIntact(witness, log: log);
        } catch (e) {
          // Print the seed + full op log so a failing case can be
          // minimized (shortest failing prefix) without re-running the
          // fuzzer with different randomness.
          // ignore: avoid_print
          print('CASE FAILED seed=${spec.seed} n=${spec.n} ops=${spec.ops}\n'
              '${log.join('\n')}');
          rethrow;
        } finally {
          await _cleanupAll(remote, clones);
        }
      });
    }
  });

  // ─── 2. Adversarial interleaving (lease race) ────────────────────────
  group('adversarial interleaving', () {
    test(
        'a mutation landing on clone A between B\'s fetch and push forces '
        'the retryable lease-failure path, and a subsequent sync '
        'converges with both writes intact', () async {
      final remote = await _bareRemote('lease');
      final cloneA = await _cloneOf(remote, 'leaseA');
      final cloneB = await _cloneOf(remote, 'leaseB');
      try {
        final storeA = DeskIssueStore(_refsFor(cloneA, 'A'));
        final storeB = DeskIssueStore(_refsFor(cloneB, 'B'));
        final issue =
            (await storeA.create(title: 't', body: '', authorIdentity: 'A'))
                .data!;
        expect((await storeA.syncWithRemote()).ok, isTrue);
        expect((await storeB.syncWithRemote()).ok, isTrue);

        // B has a local-ahead change to push.
        await expectOk(storeB.addComment(id: issue.issueId, author: 'B', body: 'from B'));

        // Wire B's sync so clone A pushes in the window after B fetched
        // staging but before B pushes — invalidating B's lease.
        final raceRefs = _LeaseRaceRefs(
          repoPath: cloneB.path,
          authorName: 'B',
          authorEmail: 'b@manifold.local',
        );
        final raceStore = DeskIssueStore(raceRefs);
        raceRefs.afterFetch = () async {
          await expectOk(storeA.addComment(id: issue.issueId, author: 'A', body: 'from A'));
          final s = await storeA.syncWithRemote();
          expect(s.ok, isTrue, reason: s.error);
        };

        final r = await raceStore.syncWithRemote();
        expect(r.ok, isFalse, reason: 'lease must fail');
        expect(r.error, startsWith(ManifoldRefs.retryablePrefix));

        // Nothing was clobbered: a subsequent sync converges with BOTH
        // comments intact.
        expect((await storeB.syncWithRemote()).ok, isTrue);
        expect((await storeA.syncWithRemote()).ok, isTrue);
        expect((await storeB.syncWithRemote()).ok, isTrue);

        final bodies =
            (await storeA.read(issue.issueId)).data!.comments.map((c) => c.body);
        expect(bodies, containsAll(<String>['from A', 'from B']));
        final bodiesB =
            (await storeB.read(issue.issueId)).data!.comments.map((c) => c.body);
        expect(bodiesB, containsAll(<String>['from A', 'from B']));
      } finally {
        await _safeCleanup(cloneA);
        await _safeCleanup(cloneB);
        await _safeCleanup(remote);
      }
    });
  });

  // ─── 3. Counter properties under randomized interleaving ────────────
  group('counter properties (randomized)', () {
    const counterKinds = [
      'createIssue', 'createIssue', 'createIssue',
      'createPr', 'createPr', 'createPr',
      'sync', 'sync',
      'forceRegress',
    ];

    for (final seed in [20001, 20002, 20003, 20004, 20005]) {
      test('seed=$seed: allocated ids never repeat even when the counter '
          'ref regresses via a divergent sync', () async {
        final rand = Random(seed);
        final reg = _Registry();
        final log = <String>[];
        final remote = await _bareRemote('$seed');
        final clones = [
          await _makeClone(remote, 'ctrA-$seed'),
          await _makeClone(remote, 'ctrB-$seed'),
        ];
        try {
          await _establishBaseline(clones);
          for (var step = 0; step < 8; step++) {
            final clone = clones[rand.nextInt(clones.length)];
            final kind = counterKinds[rand.nextInt(counterKinds.length)];
            log.add('#$step ${clone.label}: $kind');
            switch (kind) {
              case 'sync':
                final r = await clone.issues.syncWithRemote();
                expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
                break;
              case 'createIssue':
                final r = await clone.issues.create(
                    title: 'i-${reg.issueSeq++}',
                    body: '',
                    authorIdentity: clone.label);
                expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
                reg.allIssueIds.add(r.data!.issueId);
                break;
              case 'createPr':
                final branch = 'feat/ctr-${reg.prSeq++}';
                final r = await clone.prs.create(
                    branch: branch,
                    title: branch,
                    body: '',
                    baseRef: 'main',
                    authorIdentity: clone.label);
                expect(r.ok, isTrue, reason: '${r.error}\n${log.join('\n')}');
                reg.allPrBranches.add(branch);
                break;
              case 'forceRegress':
                // Simulate a stale counter (hand-edited ref, or a losing
                // divergence resolution) reading below live ids — direct
                // plumbing write, same technique as the scripted
                // "counter regression guard" unit test.
                final regressed =
                    rand.nextInt(max(1, reg.issueSeq + reg.prSeq));
                final blob = await clone.refs.writeBlob('$regressed\n');
                final tree =
                    await clone.refs.mkTree({'counter.txt': blob.data!});
                final commit = await clone.refs.commitTree(
                    treeSha: tree.data!,
                    message: 'regress counter to $regressed');
                final upd = await clone.refs.updateRef(
                    ref: ManifoldNs.idCounter, newSha: commit.data!);
                expect(upd.ok, isTrue,
                    reason: 'counter-regress op must land: ${upd.error}');
                break;
            }
          }

          final rounds = await _syncToFixpoint(clones, maxRounds: 3, log: log);
          expect(rounds, lessThanOrEqualTo(3),
              reason: 'did not converge\n${log.join('\n')}');

          final witness = clones.first;
          final issueIds =
              (await witness.issues.listAll()).data!.map((i) => i.issueId);
          final deskIds =
              (await witness.prs.listAll()).data!.map((p) => p.deskId);
          final all = [...issueIds, ...deskIds];
          expect(all.length, all.toSet().length,
              reason: 'id collision after counter regression\n'
                  '${log.join('\n')}');
        } catch (e) {
          // ignore: avoid_print
          print('CASE FAILED seed=$seed\n${log.join('\n')}');
          rethrow;
        } finally {
          await _cleanupAll(remote, clones);
        }
      });
    }
  });

  // ─── 3b. In-process serialization + pinned-sha push ──────────────────
  //
  // Targets the review finding fixed alongside this test group:
  // allocSequentialId used to push whatever the LOCAL counter ref pointed
  // at when the push ran, not the commit the call itself created — so a
  // sibling call racing in the same process could push a DIFFERENT
  // reservation while returning an id that never actually reached the
  // remote counter's history. The fix is two layers: (1) same-process
  // calls are now serialized (a static per-repoPath chain), so they never
  // interleave their CAS/push at all; (2) the push is pinned to the exact
  // sha the CAS just created (`<sha>:<ref>`, not `<ref>:<ref>`), so even a
  // ref moved by something else between CAS and push can't desync "the id
  // returned" from "what got pushed".
  group('counter: in-process serialization + pinned-sha push', () {
    test(
        '8 concurrent allocSequentialId calls (interleaved with syncWithRemote) '
        'against one repo+remote all return distinct ids, and both the local '
        'and remote counters catch up to at least the max', () async {
      final remote = await _bareRemote('serialize');
      final clone = await _makeClone(remote, 'serialize');
      try {
        await _establishBaseline([clone]);

        final futures = <Future<GitResult<int>>>[];
        final syncFutures = <Future<void>>[];
        for (var i = 0; i < 8; i++) {
          futures.add(clone.refs.allocSequentialId(
            ref: ManifoldNs.idCounter,
            filename: 'counter.txt',
            commitLabel: 'id',
          ));
          if (i == 2 || i == 5) {
            // Syncs interleaved among the allocations — syncWithRemote is
            // NOT gated by the allocation queue, so this exercises the two
            // kinds of caller genuinely overlapping. Its own success isn't
            // asserted (a sync landing mid-contention with a live push can
            // legitimately hit a transient git-level lock and isn't the
            // property this test is checking); errors are swallowed so a
            // transient failure here can't be mistaken for an unhandled
            // exception elsewhere in the test.
            syncFutures.add(
                clone.issues.syncWithRemote().then((_) {}).catchError((_) {}));
          }
        }
        final results = await Future.wait(futures);
        await Future.wait(syncFutures);

        for (final r in results) {
          expect(r.ok, isTrue, reason: r.error);
        }
        final ids = results.map((r) => r.data!).toList();
        expect(ids.length, ids.toSet().length,
            reason: 'concurrent allocations returned duplicate ids: $ids');
        final maxId = ids.reduce((a, b) => a > b ? a : b);

        // Local counter caught up to at least the max returned id.
        final localBlob = await clone.refs
            .readRefBlob(ManifoldNs.idCounter, 'counter.txt');
        expect(localBlob.ok, isTrue);
        final localVal = int.parse(localBlob.data!.trim());
        expect(localVal, greaterThanOrEqualTo(maxId),
            reason: 'local counter ($localVal) behind max returned id ($maxId)');

        // Remote counter (via a fresh sync into staging) also caught up.
        final fetch = await clone.refs.fetchToStaging();
        expect(fetch.ok, isTrue, reason: fetch.error);
        final stagedTip = await clone.refs
            .resolveRef(const MetadataRemote('origin').stage(ManifoldNs.idCounter));
        expect(stagedTip.ok, isTrue);
        expect(stagedTip.data, isNotNull,
            reason: 'remote never received the counter at all');
        final stagedBlob =
            await clone.refs.readRefBlob(stagedTip.data!, 'counter.txt');
        expect(stagedBlob.ok, isTrue);
        final remoteVal = int.parse(stagedBlob.data!.trim());
        expect(remoteVal, greaterThanOrEqualTo(maxId),
            reason:
                'remote counter ($remoteVal) behind max returned id ($maxId) — '
                'a reservation was lost');
      } finally {
        await _safeCleanup(clone.dir);
        await _safeCleanup(remote);
      }
    });

    test(
        'two-clone interleave: A allocates, B allocates+syncs first, then A '
        'syncs — both ids distinct, remote counter covers both, and a third '
        'clone syncing sees a counter at least that high (reservation-coverage '
        'early-exit path)', () async {
      final remote = await _bareRemote('interleave');
      final cloneA = await _makeClone(remote, 'ilA');
      final cloneB = await _makeClone(remote, 'ilB');
      try {
        await _establishBaseline([cloneA, cloneB]);

        final aAlloc = await cloneA.refs.allocSequentialId(
          ref: ManifoldNs.idCounter,
          filename: 'counter.txt',
          commitLabel: 'id',
        );
        expect(aAlloc.ok, isTrue, reason: aAlloc.error);

        final bAlloc = await cloneB.refs.allocSequentialId(
          ref: ManifoldNs.idCounter,
          filename: 'counter.txt',
          commitLabel: 'id',
        );
        expect(bAlloc.ok, isTrue, reason: bAlloc.error);
        final bSync = await cloneB.issues.syncWithRemote();
        expect(bSync.ok, isTrue, reason: bSync.error);

        // A syncs last, after B's reservation is already on the remote —
        // this is the shape that exercises the reservation-coverage
        // early-exit (A's own earlier remote push attempt, if any, may
        // have found the remote already past its own value).
        final aSync = await cloneA.issues.syncWithRemote();
        expect(aSync.ok, isTrue, reason: aSync.error);

        expect(aAlloc.data, isNot(equals(bAlloc.data)),
            reason: 'A and B allocated the same id');

        final maxId =
            aAlloc.data! > bAlloc.data! ? aAlloc.data! : bAlloc.data!;

        for (final c in [cloneA, cloneB]) {
          final local = await c.refs
              .readRefBlob(ManifoldNs.idCounter, 'counter.txt');
          expect(local.ok, isTrue);
          expect(int.parse(local.data!.trim()), greaterThanOrEqualTo(maxId),
              reason: '${c.label} local counter behind max id $maxId');
        }

        // A third, previously-uninvolved clone syncing now must see a
        // counter at least as high as both allocations — proving the
        // remote genuinely covers both ids, not just A's or B's own view.
        final cloneC = await _makeClone(remote, 'ilC');
        try {
          final sync = await cloneC.issues.syncWithRemote();
          expect(sync.ok, isTrue, reason: sync.error);
          final cBlob = await cloneC.refs
              .readRefBlob(ManifoldNs.idCounter, 'counter.txt');
          expect(cBlob.ok, isTrue);
          expect(int.parse(cBlob.data!.trim()), greaterThanOrEqualTo(maxId),
              reason: 'third clone saw a remote counter behind max id $maxId');
        } finally {
          await _safeCleanup(cloneC.dir);
        }
      } finally {
        await _safeCleanup(cloneA.dir);
        await _safeCleanup(cloneB.dir);
        await _safeCleanup(remote);
      }
    });

    test(
        'pinned-sha unit: pushing with the source pinned to an OLDER sha sends '
        'exactly that sha even though the local ref has since moved to a newer '
        'commit, and the reservation-coverage early-exit settles without a '
        'retry storm when the remote is found to have moved past the reserved '
        'value', () async {
      final remote = await _bareRemote('pin');
      final clone = await _makeClone(remote, 'pin');
      try {
        await _establishBaseline([clone]);
        final refs = clone.refs;
        const ref = ManifoldNs.idCounter;
        const filename = 'counter.txt';

        final baseTip = (await refs.resolveRef(ref)).data!;
        final baseVal =
            int.parse((await refs.readRefBlob(baseTip, filename)).data!.trim());

        // ── Part 1: prove the <sha>:<ref> refspec semantics directly ──
        //
        // Commit N (the "older" counter commit this test pins the push to)
        // and commit N+1 chained onto it, with the LOCAL ref advanced to
        // N+1 — reproducing "the local ref has moved past the commit we
        // mean to push" from the review finding, without needing two real
        // racing calls.
        final blobN = await refs.writeBlob('${baseVal + 1}\n');
        final treeN = await refs.mkTree({filename: blobN.data!});
        final commitN = await refs.commitTree(
            treeSha: treeN.data!, parentSha: baseTip, message: 'N');

        final blobN1 = await refs.writeBlob('${baseVal + 2}\n');
        final treeN1 = await refs.mkTree({filename: blobN1.data!});
        final commitN1 = await refs.commitTree(
            treeSha: treeN1.data!, parentSha: commitN.data!, message: 'N+1');
        final advanced = await refs.updateRef(
            ref: ref, newSha: commitN1.data!, oldSha: baseTip);
        expect(advanced.ok, isTrue,
            reason: 'local-ref advance to N+1 must land: ${advanced.error}');

        // Lease-push the OLDER sha (commitN) explicitly, leasing against
        // the remote's actual current tip (baseTip — the real bare remote
        // is still there since establishBaseline's sync). This drives the
        // exact plumbing `ManifoldRefs._leasePush` uses when
        // [allocSequentialId] passes an explicit `sha`; reproduced with a
        // raw git invocation here because `_leasePush` is private to
        // manifold_refs.dart (Dart privacy is per-library — the same
        // constraint the merge-function property tests below already work
        // around).
        final leaseTip = (await refs.resolveRef(ref)).data!;
        expect(leaseTip, commitN1.data,
            reason: 'sanity: local ref should be at N+1 before the push');
        final pinnedPush = await Process.run(
          'git',
          [
            'push',
            'origin',
            '--force-with-lease=$ref:$baseTip',
            '${commitN.data!}:$ref',
          ],
          workingDirectory: clone.dir.path,
        );
        expect(pinnedPush.exitCode, 0,
            reason: 'pinned-sha push failed: ${pinnedPush.stderr}');

        final remoteTipAfterPin =
            await Process.run('git', ['rev-parse', ref], workingDirectory: remote.path);
        expect((remoteTipAfterPin.stdout as String).trim(), commitN.data,
            reason: 'remote must receive exactly the pinned sha (N), not '
                'the local ref\'s current tip (N+1)');

        // ── Part 2: FOREIGN higher reservation lands after our CAS ──
        //
        // A peer's (foreign-chain) reservation with a HIGHER value lands
        // on the remote in the window between this call's local CAS and
        // its push. Empirical wrinkle the first version of this test
        // caught: a push from the same clone also advances the local
        // staging ref (git maps pushed refs through `remote.origin.fetch`
        // onto remote-tracking refs), so the alloc's lease was FRESH and
        // its push succeeded — silently REGRESSING the remote counter
        // from farVal down to our lower value. The coverage guard must
        // instead classify the staged tip as foreign-higher, refuse to
        // push, and retry with a floor past farVal.
        final farVal = baseVal + 5;
        final blobFar = await refs.writeBlob('$farVal\n');
        final treeFar = await refs.mkTree({filename: blobFar.data!});
        final commitFar = await refs.commitTree(
            treeSha: treeFar.data!, parentSha: commitN.data!, message: 'far');

        final foreignRace = _AfterCasRefs(
          repoPath: clone.dir.path,
          authorName: clone.label,
          authorEmail: '${clone.label}@manifold.local',
          counterRef: ref,
        );
        foreignRace.afterCas = (ownSha) async {
          final push = await Process.run(
            'git',
            ['push', '--force', 'origin', '${commitFar.data!}:$ref'],
            workingDirectory: clone.dir.path,
          );
          expect(push.exitCode, 0,
              reason: 'injected foreign push failed: ${push.stderr}');
        };

        final alloc = await foreignRace.allocSequentialId(
          ref: ref,
          filename: filename,
          commitLabel: 'id',
        );
        expect(alloc.ok, isTrue, reason: alloc.error);
        expect(alloc.data, farVal + 1,
            reason: 'foreign-higher reservation must force a retry that '
                'allocates strictly past the peer\'s value — never at or '
                'below it');
        final remoteBlobAfterForeign = await Process.run(
            'git', ['cat-file', 'blob', '$ref:$filename'],
            workingDirectory: remote.path);
        expect(
            int.parse((remoteBlobAfterForeign.stdout as String).trim()),
            farVal + 1,
            reason: 'the retry\'s own reservation should land on the remote; '
                'the counter must never regress below farVal');

        // ── Part 3: reservation covered by our OWN chain → early exit ──
        //
        // A descendant of the very commit this call minted lands on the
        // remote before the call's own push (in production: a concurrent
        // same-process syncWithRemote pushing the local ref, or a peer
        // relaying it). The reservation is then already ON the remote's
        // history — the call must settle as a SUCCESS without pushing
        // (no retry storm, and no pushing a now-stale sha over the newer
        // one: reserving N under a remote already at N+1 is a success).
        final localValNow = int.parse(
            (await refs.readRefBlob(ref, filename)).data!.trim());
        final expectedId = localValNow + 1;

        String? injectedDescendant;
        final ownRace = _AfterCasRefs(
          repoPath: clone.dir.path,
          authorName: clone.label,
          authorEmail: '${clone.label}@manifold.local',
          counterRef: ref,
        );
        ownRace.afterCas = (ownSha) async {
          // Build a child of the alloc's own commit carrying value+1 and
          // land it on the remote — exactly what a sync relaying a
          // subsequent allocation would produce.
          final v = int.parse(
              (await ownRace.readRefBlob(ownSha, filename)).data!.trim());
          final blob = await ownRace.writeBlob('${v + 1}\n');
          final tree = await ownRace.mkTree({filename: blob.data!});
          final child = await ownRace.commitTree(
              treeSha: tree.data!, parentSha: ownSha, message: 'descendant');
          injectedDescendant = child.data!;
          final push = await Process.run(
            'git',
            ['push', '--force', 'origin', '${child.data!}:$ref'],
            workingDirectory: clone.dir.path,
          );
          expect(push.exitCode, 0,
              reason: 'injected descendant push failed: ${push.stderr}');
        };

        final alloc2 = await ownRace.allocSequentialId(
          ref: ref,
          filename: filename,
          commitLabel: 'id',
        );
        expect(alloc2.ok, isTrue,
            reason: 'covered-by-own-chain must settle as success, not a '
                'retry storm: ${alloc2.error}');
        expect(alloc2.data, expectedId,
            reason: 'the early-exit returns the id whose reservation the '
                'remote already carries');

        final remoteTipAfterOwn = await Process.run(
            'git', ['rev-parse', ref],
            workingDirectory: remote.path);
        expect((remoteTipAfterOwn.stdout as String).trim(), injectedDescendant,
            reason: 'the early-exit must NOT push — the remote should still '
                'be exactly the injected descendant, which already covers '
                'the returned id');
      } finally {
        await _safeCleanup(clone.dir);
        await _safeCleanup(remote);
      }
    });
  });

  // ─── 3c. Worktree identity (queue keyed by common git dir) ───────────
  //
  // Targets the review finding fixed alongside this test group:
  // DeskPrState/DeskIssueState build a ManifoldRefs from
  // RepositoryState.activePath, which is worktree-specific — this app
  // routinely addresses ONE repository through MULTIPLE worktree paths
  // (desks). The in-process allocation queue used to be keyed by
  // repoPath, so two open desks of the same repo (one per worktree) got
  // different keys, bypassed the queue entirely, and could interleave
  // CAS/push on the SAME refs in the shared common git dir — exactly the
  // race the queue was added to prevent. The fix keys the queue by the
  // resolved common git dir instead (`ManifoldRefs._commonGitDir`,
  // memoized in `ManifoldRefs.commonGitDirMemo`), which sibling worktrees
  // of one repo resolve to identically (confirmed empirically below, and
  // separately via a scratch `git worktree add` on this machine before
  // this fix was written: two worktrees of one repo returned the
  // byte-identical `--path-format=absolute --git-common-dir` string —
  // forward slashes, no trailing slash, same casing).
  group('worktree identity (queue keyed by common git dir)', () {
    test(
        '8 concurrent allocSequentialId calls split across TWO real '
        'worktrees of the same repo all return distinct ids, and the local '
        '+ remote counters catch up to at least the max', () async {
      final remote = await _bareRemote('worktree-race');
      final mainClone = await _cloneOf(remote, 'wtMain');
      final wtDir = Directory('${mainClone.parent.path}/wt2');
      try {
        final wt = await Process.run(
            'git', ['worktree', 'add', '-q', '-b', 'wt2-branch', wtDir.path],
            workingDirectory: mainClone.path);
        expect(wt.exitCode, 0, reason: wt.stderr.toString());

        // Sanity: confirm empirically the two worktree paths really do
        // resolve to the identical common git dir before relying on that
        // fact for the rest of this test. (Before this fix, the queue was
        // keyed on repoPath directly — these two distinct paths would
        // have produced two DIFFERENT queue keys and the 8 allocations
        // below would race uninterlocked.)
        final mainCommon = await Process.run('git',
            ['rev-parse', '--path-format=absolute', '--git-common-dir'],
            workingDirectory: mainClone.path);
        final wtCommon = await Process.run('git',
            ['rev-parse', '--path-format=absolute', '--git-common-dir'],
            workingDirectory: wtDir.path);
        expect((wtCommon.stdout as String).trim(),
            (mainCommon.stdout as String).trim(),
            reason: 'two worktrees of one repo must resolve to the same '
                'common git dir for the queue key to unify them');

        final mainRefs = _refsFor(mainClone, 'wtMain');
        final wtRefs = ManifoldRefs(
          repoPath: wtDir.path,
          authorName: 'wt2',
          authorEmail: 'wt2@manifold.local',
        );

        // 4 concurrent allocations through EACH path, interleaved, fired
        // simultaneously — 8 total, all against the one shared repo.
        final futures = <Future<GitResult<int>>>[];
        for (var i = 0; i < 4; i++) {
          futures.add(mainRefs.allocSequentialId(
            ref: ManifoldNs.idCounter,
            filename: 'counter.txt',
            commitLabel: 'id',
          ));
          futures.add(wtRefs.allocSequentialId(
            ref: ManifoldNs.idCounter,
            filename: 'counter.txt',
            commitLabel: 'id',
          ));
        }
        final results = await Future.wait(futures);
        for (final r in results) {
          expect(r.ok, isTrue, reason: r.error);
        }
        final ids = results.map((r) => r.data!).toList();
        expect(ids.length, ids.toSet().length,
            reason: 'concurrent allocations across two worktrees of the '
                'same repo returned duplicate ids: $ids');
        final maxId = ids.reduce((a, b) => a > b ? a : b);

        final localBlob = await mainRefs.readRefBlob(
            ManifoldNs.idCounter, 'counter.txt');
        expect(localBlob.ok, isTrue);
        expect(int.parse(localBlob.data!.trim()), greaterThanOrEqualTo(maxId),
            reason: 'local counter behind max returned id');

        final fetch = await mainRefs.fetchToStaging();
        expect(fetch.ok, isTrue, reason: fetch.error);
        final stagedTip = await mainRefs
            .resolveRef(const MetadataRemote('origin').stage(ManifoldNs.idCounter));
        expect(stagedTip.ok, isTrue);
        expect(stagedTip.data, isNotNull,
            reason: 'remote never received the counter at all');
        final stagedBlob =
            await mainRefs.readRefBlob(stagedTip.data!, 'counter.txt');
        expect(stagedBlob.ok, isTrue);
        expect(int.parse(stagedBlob.data!.trim()), greaterThanOrEqualTo(maxId),
            reason: 'remote counter behind max returned id — a reservation '
                'was lost across the worktree split');
      } finally {
        await _safeCleanup(wtDir);
        await _safeCleanup(mainClone);
        await _safeCleanup(remote);
      }
    });

    test(
        'memoization: two paths addressing the same repo resolve to one '
        'shared chain key, and a repeat allocation from an already-seen '
        'path reuses the memoized future rather than adding a new entry',
        () async {
      final remote = await _bareRemote('worktree-memo');
      final mainClone = await _cloneOf(remote, 'memoMain');
      final wtDir = Directory('${mainClone.parent.path}/wt2memo');
      try {
        final wt = await Process.run(
            'git', ['worktree', 'add', '-q', '-b', 'memo-branch', wtDir.path],
            workingDirectory: mainClone.path);
        expect(wt.exitCode, 0, reason: wt.stderr.toString());

        final mainRefs = _refsFor(mainClone, 'memoMain');
        final wtRefs = ManifoldRefs(
          repoPath: wtDir.path,
          authorName: 'memoWt',
          authorEmail: 'memoWt@manifold.local',
        );

        // Make sure these two paths start with no memo entry (a prior
        // test in this same isolate may have touched unrelated paths, but
        // never these fresh temp dirs).
        expect(ManifoldRefs.commonGitDirMemo.containsKey(mainClone.path),
            isFalse);
        expect(
            ManifoldRefs.commonGitDirMemo.containsKey(wtDir.path), isFalse);

        final a = await mainRefs.allocSequentialId(
            ref: ManifoldNs.idCounter, filename: 'counter.txt');
        expect(a.ok, isTrue, reason: a.error);
        final b = await wtRefs.allocSequentialId(
            ref: ManifoldNs.idCounter, filename: 'counter.txt');
        expect(b.ok, isTrue, reason: b.error);

        // One memo entry per distinct PATH...
        expect(ManifoldRefs.commonGitDirMemo.containsKey(mainClone.path),
            isTrue);
        expect(
            ManifoldRefs.commonGitDirMemo.containsKey(wtDir.path), isTrue);
        // ...but both resolve to the same shared chain KEY.
        final mainKey = await ManifoldRefs.commonGitDirMemo[mainClone.path]!;
        final wtKey = await ManifoldRefs.commonGitDirMemo[wtDir.path]!;
        expect(wtKey, mainKey,
            reason: 'two worktrees of one repo must resolve to one shared '
                'allocation-chain key');

        // A repeat allocation from an already-memoized path must not add
        // a new entry NOR recompute the resolution (same Future instance
        // — proving no additional `rev-parse --git-common-dir` process
        // was spawned).
        final beforeFuture = ManifoldRefs.commonGitDirMemo[mainClone.path];
        final keysBefore = Set.of(ManifoldRefs.commonGitDirMemo.keys);
        final c = await mainRefs.allocSequentialId(
            ref: ManifoldNs.idCounter, filename: 'counter.txt');
        expect(c.ok, isTrue, reason: c.error);
        expect(Set.of(ManifoldRefs.commonGitDirMemo.keys), keysBefore,
            reason: 'a repeat allocation from an already-seen path must not '
                'add a new memo entry');
        expect(
            identical(
                ManifoldRefs.commonGitDirMemo[mainClone.path], beforeFuture),
            isTrue,
            reason: 'the memoized resolution future must be reused, not '
                'recomputed, on a repeat allocation from the same path');
      } finally {
        await _safeCleanup(wtDir);
        await _safeCleanup(mainClone);
        await _safeCleanup(remote);
      }
    });

    test(
        'fallback: a path that is not a git repo at all still resolves a '
        'queue key (itself) and completes the allocation attempt without '
        'throwing, even though the attempt itself cannot succeed outside '
        'a repo', () async {
      final dir =
          await Directory.systemTemp.createTemp('manifold_notrepo_');
      try {
        final refs = ManifoldRefs(
          repoPath: dir.path,
          authorName: 'norepo',
          authorEmail: 'norepo@manifold.local',
        );
        // `git rev-parse --git-common-dir` fails outside a repo (verified
        // empirically: exit 128, "fatal: not a git repository") — the
        // resolver must swallow that and fall back to the raw path rather
        // than letting it propagate. The allocation itself still runs
        // (and fails cleanly, since there is genuinely no ref to read in
        // a non-repo directory) rather than hanging or throwing.
        final r = await refs.allocSequentialId(
          ref: ManifoldNs.idCounter,
          filename: 'counter.txt',
        );
        expect(r.ok, isFalse,
            reason: 'a non-repo path cannot actually allocate a ref, but '
                'the call must complete with a clean error, not throw');
        final resolved = await ManifoldRefs.commonGitDirMemo[dir.path];
        expect(resolved, dir.path,
            reason: 'resolver must fall back to the raw repoPath when '
                'git-common-dir resolution fails');
      } finally {
        await _safeCleanup(dir);
      }
    });
  });

  // ─── 3d. Metadata remote resolution (non-'origin' forge remotes) ──────
  //
  // Regression coverage for the finding that DeskIssueStore/DeskPrStore's
  // _allocId() used to call ManifoldRefs.allocSequentialId with no remote
  // (hardcoded default 'origin'), while syncWithRemote() let callers pick
  // — so a repo whose forge remote is named anything else (the common
  // fork shape: 'upstream') reserved ids against the wrong namespace (or
  // degraded to local-only) while sync ran against the real remote,
  // breaking the "ids never collide across clones" guarantee. Every other
  // group in this file builds bare remotes named 'origin' (via _cloneOf's
  // plain `git clone`), so it keeps passing whether or not the resolver
  // exists — these are the cases that only pass once creation and sync
  // agree on a resolved (not hardcoded) remote.
  group('metadata remote resolution (non-origin remotes)', () {
    test(
        'a repo whose ONLY remote is named upstream: create() reserves the '
        'id-counter against upstream (not a hardcoded origin), and a '
        'no-argument syncWithRemote() pushes the new issue ref there too',
        () async {
      final bare = await _bareRemote('resolve-upstream');
      final clone = await _cloneOf(bare, 'resolveA');
      try {
        final rename = await Process.run(
            'git', ['remote', 'rename', 'origin', 'upstream'],
            workingDirectory: clone.path);
        expect(rename.exitCode, 0, reason: rename.stderr.toString());
        // Sanity: this clone genuinely has no remote named 'origin' — a
        // literal-'origin' default would see no configured remote at all
        // and silently degrade the reservation to local-only.
        final remotes = await Process.run('git', ['remote'],
            workingDirectory: clone.path);
        expect((remotes.stdout as String).split('\n').map((s) => s.trim()),
            isNot(contains('origin')));

        final refs = _refsFor(clone, 'resolveA');
        final store = DeskIssueStore(refs);
        final created =
            await store.create(title: 'via upstream', body: '', authorIdentity: 'A');
        expect(created.ok, isTrue, reason: created.error);

        // The counter reservation must have landed on the bare repo — the
        // ONLY remote this clone has — proving allocSequentialId resolved
        // 'upstream' rather than defaulting to an absent 'origin'.
        final counterTip = await Process.run(
            'git', ['rev-parse', '${ManifoldRefs.manifoldPrefix}_id-counter'],
            workingDirectory: bare.path);
        expect(counterTip.exitCode, 0,
            reason: 'id-counter reservation never reached the upstream '
                'remote — allocSequentialId must have resolved a remote '
                'other than this repo\'s actual (only) one');
        final counterBlob = await Process.run('git',
            ['cat-file', 'blob', '${(counterTip.stdout as String).trim()}:counter.txt'],
            workingDirectory: bare.path);
        expect(counterBlob.exitCode, 0);
        expect(int.parse((counterBlob.stdout as String).trim()),
            created.data!.issueId);

        // create() never pushes the entity ref itself — only sync does.
        // A no-argument syncWithRemote() must resolve to the SAME
        // upstream remote create() used, not fall back to 'origin'.
        final sync = await store.syncWithRemote();
        expect(sync.ok, isTrue, reason: sync.error);

        final issueRef = DeskIssueStore.refFor(created.data!.issueId);
        final onRemote = await Process.run('git', ['rev-parse', issueRef],
            workingDirectory: bare.path);
        expect(onRemote.exitCode, 0,
            reason: 'syncWithRemote() with no explicit remote must sync '
                'against the same upstream remote create() reserved '
                'against, not a hardcoded origin');
      } finally {
        await _safeCleanup(clone);
        await _safeCleanup(bare);
      }
    });

    test(
        'a repo with NO remote at all still allocates locally (documented '
        'offline degradation, unaffected by remote resolution)', () async {
      final dir = await Directory.systemTemp.createTemp('manifold_noremote_');
      try {
        await Process.run('git', ['init', '-q', '-b', 'main'],
            workingDirectory: dir.path);
        await Process.run('git', ['config', 'user.name', 'test'],
            workingDirectory: dir.path);
        await Process.run('git', ['config', 'user.email', 'test@local'],
            workingDirectory: dir.path);
        await Process.run('git', ['commit', '--allow-empty', '-m', 'root'],
            workingDirectory: dir.path);

        final refs = ManifoldRefs(
          repoPath: dir.path,
          authorName: 'solo',
          authorEmail: 'solo@manifold.local',
        );
        final store = DeskIssueStore(refs);
        final created =
            await store.create(title: 'offline', body: '', authorIdentity: 'solo');
        expect(created.ok, isTrue, reason: created.error);
        expect(created.data!.issueId, 1);

        final tip = await refs.resolveRef(ManifoldNs.idCounter);
        expect(tip.ok, isTrue);
        expect(tip.data, isNotNull,
            reason: 'a remote-less repo must still commit the counter ref '
                'locally — allocation degrades, it does not fail');
      } finally {
        await _safeCleanup(dir);
      }
    });

    test(
        'an explicit remote: override wins over resolution, even when '
        'origin also exists and would otherwise be preferred', () async {
      final originBare = await _bareRemote('override-origin');
      final upstreamBare = await _bareRemote('override-upstream');
      final clone = await _cloneOf(originBare, 'overrideA');
      try {
        final addUpstream = await Process.run(
            'git', ['remote', 'add', 'upstream', upstreamBare.path],
            workingDirectory: clone.path);
        expect(addUpstream.exitCode, 0, reason: addUpstream.stderr.toString());

        final refs = _refsFor(clone, 'overrideA');
        // 'origin' is present and is what resolveMetadataRemote() would
        // pick by default — but an explicit remote: argument must win.
        final r = await refs.allocSequentialId(
          ref: ManifoldNs.idCounter,
          filename: 'counter.txt',
          remote: const MetadataRemote('upstream'),
        );
        expect(r.ok, isTrue, reason: r.error);

        final onUpstream = await Process.run(
            'git', ['rev-parse', '${ManifoldRefs.manifoldPrefix}_id-counter'],
            workingDirectory: upstreamBare.path);
        expect(onUpstream.exitCode, 0,
            reason: 'an explicit remote: override must reserve against '
                'THAT remote');
        final onOrigin = await Process.run(
            'git', ['rev-parse', '${ManifoldRefs.manifoldPrefix}_id-counter'],
            workingDirectory: originBare.path);
        expect(onOrigin.exitCode, isNot(0),
            reason: 'an explicit remote: override must NOT also reserve '
                'against the default-resolved origin');
      } finally {
        await _safeCleanup(clone);
        await _safeCleanup(originBare);
        await _safeCleanup(upstreamBare);
      }
    });
  });

  // ─── 4. Merge-function properties ────────────────────────────────────
  //
  // ManifoldRefs._mergeJsonRecords/_canonicalJson/_unionComments are
  // private to manifold_refs.dart (Dart privacy is per-library), so they
  // cannot be called directly from this test file. Every property below
  // is instead exercised through minimal two-clone divergence
  // constructions that hit the exact same merge code path via
  // syncWithRemote — the same technique manifold_refs.dart's own
  // `_forceCounter`-style tests already use to drive the plumbing
  // directly without a full store round-trip.
  group('merge-function properties (via minimal divergence)', () {
    test(
        'commutativity: the converged content does not depend on which '
        'side initiates the reconcile', () async {
      Future<String> runOrder(String order) async {
        final remote = await _bareRemote('commute-$order');
        final cloneA = await _cloneOf(remote, 'cmA-$order');
        final cloneB = await _cloneOf(remote, 'cmB-$order');
        try {
          final storeA = DeskIssueStore(_refsFor(cloneA, 'A'));
          final storeB = DeskIssueStore(_refsFor(cloneB, 'B'));
          final issue = (await storeA.create(
                  title: 'base', body: '', authorIdentity: 'A'))
              .data!;
          expect((await storeA.syncWithRemote()).ok, isTrue);
          expect((await storeB.syncWithRemote()).ok, isTrue);

          // A edits first (earlier updatedAt), B edits second (later).
          await expectOk(storeA.editMeta(id: issue.issueId, title: 'from A'));
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await expectOk(storeB.editMeta(id: issue.issueId, title: 'from B'));

          if (order == 'A-first') {
            expect((await storeA.syncWithRemote()).ok, isTrue);
            expect((await storeB.syncWithRemote()).ok, isTrue);
            expect((await storeA.syncWithRemote()).ok, isTrue);
          } else {
            expect((await storeB.syncWithRemote()).ok, isTrue);
            expect((await storeA.syncWithRemote()).ok, isTrue);
            expect((await storeB.syncWithRemote()).ok, isTrue);
          }
          final title = (await storeA.read(issue.issueId)).data!.title;
          final titleB = (await storeB.read(issue.issueId)).data!.title;
          expect(title, titleB, reason: 'both sides must agree post-sync');
          return title;
        } finally {
          await _safeCleanup(cloneA);
          await _safeCleanup(cloneB);
          await _safeCleanup(remote);
        }
      }

      final aFirst = await runOrder('A-first');
      final bFirst = await runOrder('B-first');
      // LWW picks the later `updatedAt` (B's edit), regardless of which
      // side happened to initiate the reconcile.
      expect(aFirst, 'from B');
      expect(bFirst, 'from B');
      expect(aFirst, bFirst,
          reason: 'merge(a,b) content must equal merge(b,a) content');
    });

    test('idempotence: re-syncing a converged pair moves nothing', () async {
      final remote = await _bareRemote('idem');
      final cloneA = await _cloneOf(remote, 'idA');
      final cloneB = await _cloneOf(remote, 'idB');
      try {
        final storeA = DeskIssueStore(_refsFor(cloneA, 'A'));
        final storeB = DeskIssueStore(_refsFor(cloneB, 'B'));
        final issue =
            (await storeA.create(title: 't', body: '', authorIdentity: 'A'))
                .data!;
        expect((await storeA.syncWithRemote()).ok, isTrue);
        expect((await storeB.syncWithRemote()).ok, isTrue);
        await expectOk(storeA.addComment(id: issue.issueId, author: 'A', body: 'x'));
        await expectOk(storeB.addComment(id: issue.issueId, author: 'B', body: 'y'));
        expect((await storeB.syncWithRemote()).ok, isTrue);
        expect((await storeA.syncWithRemote()).ok, isTrue);
        expect((await storeB.syncWithRemote()).ok, isTrue);

        final ref = DeskIssueStore.refFor(issue.issueId);
        Future<String> tip(Directory d) async {
          final r = await Process.run('git', ['rev-parse', ref],
              workingDirectory: d.path);
          return (r.stdout as String).trim();
        }

        final before = await tip(cloneA);
        expect((await storeA.syncWithRemote()).ok, isTrue);
        expect((await storeB.syncWithRemote()).ok, isTrue);
        expect((await storeA.syncWithRemote()).ok, isTrue);
        // merge(a, a) == a: no new commit was minted by re-syncing an
        // already-converged pair.
        expect(await tip(cloneA), before);
        expect(await tip(cloneB), before);
      } finally {
        await _safeCleanup(cloneA);
        await _safeCleanup(cloneB);
        await _safeCleanup(remote);
      }
    });

    test(
        'comment-union completeness: a shared comment tuple dedupes to one '
        'copy, distinct comments from both sides both survive', () async {
      final remote = await _bareRemote('union');
      final cloneA = await _cloneOf(remote, 'unA');
      final cloneB = await _cloneOf(remote, 'unB');
      try {
        final refsA = _refsFor(cloneA, 'A');
        final refsB = _refsFor(cloneB, 'B');
        final storeA = DeskIssueStore(refsA);
        final storeB = DeskIssueStore(refsB);
        final issue =
            (await storeA.create(title: 't', body: '', authorIdentity: 'A'))
                .data!;
        expect((await storeA.syncWithRemote()).ok, isTrue);
        expect((await storeB.syncWithRemote()).ok, isTrue);

        final baseRef = DeskIssueStore.refFor(issue.issueId);
        final baseTipR = await refsA.resolveRef(baseRef);
        final baseTip = baseTipR.data!;
        final base = (await storeA.read(issue.issueId)).data!;

        final sharedAt = DateTime.utc(2026, 1, 1, 12, 0, 0);
        final shared = DeskIssueComment(
            author: 'shared', body: 'identical tuple', at: sharedAt);
        final onlyA =
            DeskIssueComment(author: 'A', body: 'only-A', at: sharedAt);
        final onlyB =
            DeskIssueComment(author: 'B', body: 'only-B', at: sharedAt);

        Future<void> forceTip(
            ManifoldRefs refs, DeskIssue next, String message) async {
          final blob = await refs.writeBlob(next.toBlob());
          final tree = await refs.mkTree({'issue.json': blob.data!});
          final commit = await refs.commitTree(
              treeSha: tree.data!, parentSha: baseTip, message: message);
          final upd = await refs.updateRef(
              ref: baseRef, newSha: commit.data!, oldSha: baseTip);
          expect(upd.ok, isTrue,
              reason: 'divergence setup must land: ${upd.error}');
        }

        // Both sides branch from the SAME parent with a DIFFERENT
        // updatedAt so this is a genuine (non-content-identical)
        // divergence, each containing the shared tuple plus one unique
        // comment.
        await forceTip(
            refsA,
            base.copyWith(
              comments: [shared, onlyA],
              updatedAt: DateTime.utc(2026, 1, 1, 12, 1, 0),
            ),
            'A adds comments');
        await forceTip(
            refsB,
            base.copyWith(
              comments: [shared, onlyB],
              updatedAt: DateTime.utc(2026, 1, 1, 12, 2, 0),
            ),
            'B adds comments');

        expect((await storeB.syncWithRemote()).ok, isTrue);
        final syncA = await storeA.syncWithRemote();
        expect(syncA.ok, isTrue, reason: syncA.error);
        expect((await storeB.syncWithRemote()).ok, isTrue);

        final merged = (await storeA.read(issue.issueId)).data!;
        expect(merged.comments.length, 3,
            reason: 'expected exactly {shared, onlyA, onlyB}, got '
                '${merged.comments.map((c) => c.body).toList()}');
        final bodies = merged.comments.map((c) => c.body).toSet();
        expect(bodies, {'identical tuple', 'only-A', 'only-B'});
        // The shared (author, at, body) tuple appears exactly once.
        expect(
            merged.comments.where((c) => c.body == 'identical tuple').length,
            1);
      } finally {
        await _safeCleanup(cloneA);
        await _safeCleanup(cloneB);
        await _safeCleanup(remote);
      }
    });

    test(
        'LWW tie-break determinism: equal updatedAt resolves to the '
        'a content-determined winner, identical in both sync directions',
        () async {
      // Constructs a genuine divergence where BOTH sides carry the same
      // updatedAt, so the tie-break is the only thing deciding the
      // winner. Verified independently with the reconcile initiated from
      // each side, so the outcome cannot depend on who happens to call
      // syncWithRemote first.
      //
      // This used to assert the winner was the lexicographically larger
      // TIP SHA. That was pinning the mechanism, and the mechanism was
      // wrong: a sha describes the commit a blob was read from, not the
      // blob, so a merged record (a new commit, unrelated sha) settles
      // the same tie the other way when it meets a third peer. The
      // property worth pinning is the one the anti-ping-pong design
      // actually rests on — both directions agree — plus the winner
      // being decided by CONTENT, which is what makes it survive a
      // third peer at all. See merge_policy_test's M9.
      Future<({String aSha, String bSha, String winnerTitle})> setupAndSync(
          {required bool aInitiates}) async {
        final remote = await _bareRemote('tie-$aInitiates');
        final cloneA = await _cloneOf(remote, 'tieA-$aInitiates');
        final cloneB = await _cloneOf(remote, 'tieB-$aInitiates');
        try {
          final refsA = _refsFor(cloneA, 'A');
          final refsB = _refsFor(cloneB, 'B');
          final storeA = DeskIssueStore(refsA);
          final storeB = DeskIssueStore(refsB);
          final issue = (await storeA.create(
                  title: 't', body: '', authorIdentity: 'A'))
              .data!;
          expect((await storeA.syncWithRemote()).ok, isTrue);
          expect((await storeB.syncWithRemote()).ok, isTrue);

          final baseRef = DeskIssueStore.refFor(issue.issueId);
          final baseTip = (await refsA.resolveRef(baseRef)).data!;
          final base = (await storeA.read(issue.issueId)).data!;
          const tie = 'ISO-FIXED-TIE';
          final tieAt = DateTime.utc(2026, 1, 1);

          Future<String> forceTip(ManifoldRefs refs, String title) async {
            final next = base.copyWith(title: title, updatedAt: tieAt);
            final blob = await refs.writeBlob(next.toBlob());
            final tree = await refs.mkTree({'issue.json': blob.data!});
            final commit = await refs.commitTree(
                treeSha: tree.data!, parentSha: baseTip, message: tie);
            final upd = await refs.updateRef(
                ref: baseRef, newSha: commit.data!, oldSha: baseTip);
            expect(upd.ok, isTrue,
                reason: 'tie-break setup must land: ${upd.error}');
            return commit.data!;
          }

          final aSha = await forceTip(refsA, 'title-A');
          final bSha = await forceTip(refsB, 'title-B');

          if (aInitiates) {
            expect((await storeB.syncWithRemote()).ok, isTrue);
            expect((await storeA.syncWithRemote()).ok, isTrue);
            expect((await storeB.syncWithRemote()).ok, isTrue);
          } else {
            expect((await storeA.syncWithRemote()).ok, isTrue);
            expect((await storeB.syncWithRemote()).ok, isTrue);
            expect((await storeA.syncWithRemote()).ok, isTrue);
          }
          final winnerTitle = (await storeA.read(issue.issueId)).data!.title;
          final winnerTitleB = (await storeB.read(issue.issueId)).data!.title;
          expect(winnerTitle, winnerTitleB);
          return (aSha: aSha, bSha: bSha, winnerTitle: winnerTitle);
        } finally {
          await _safeCleanup(cloneA);
          await _safeCleanup(cloneB);
          await _safeCleanup(remote);
        }
      }

      // 'title-B' > 'title-A' as canonical JSON, and the tie-break is a
      // max over content, so B's title is the winner on both runs. The
      // shas differ between the two runs (different clones, different
      // commits) and no longer influence the outcome — which is the
      // whole point.
      final r1 = await setupAndSync(aInitiates: true);
      expect(r1.winnerTitle, 'title-B',
          reason: 'the greater canonical content must win (A initiating)');

      final r2 = await setupAndSync(aInitiates: false);
      expect(r2.winnerTitle, 'title-B',
          reason: 'the greater canonical content must win (B initiating)');

      expect(r1.winnerTitle, r2.winnerTitle,
          reason: 'both sync directions must land on the same record — '
              'the anti-ping-pong design rests on exactly this');
    });
  });
}

/// A ManifoldRefs that lands ONE interfering action right AFTER a sync
/// fetches remote refs into staging but BEFORE it pushes — simulating a
/// peer who pushes in the race window, so our per-ref force-with-lease
/// finds a stale lease and must refuse rather than clobber. Identical
/// pattern to the one in desk_pr_store_test.dart; redefined here because
/// Dart privacy is per-file and the seam is intentionally private.
class _LeaseRaceRefs extends ManifoldRefs {
  _LeaseRaceRefs({
    required super.repoPath,
    required super.authorName,
    required super.authorEmail,
  });

  bool _fired = false;
  Future<void> Function()? afterFetch;

  @override
  Future<GitResult<void>> fetchToStaging({MetadataRemote? remote}) async {
    final r = await super.fetchToStaging(remote: remote);
    if (!_fired && afterFetch != null) {
      _fired = true;
      await afterFetch!();
    }
    return r;
  }
}

/// A ManifoldRefs that fires ONE injected action right after the FIRST
/// successful CAS `updateRef` of [counterRef] — the exact window between
/// "this allocation's local CAS won" and "this allocation pushes its
/// reservation" where a racing peer's (or a concurrent sync's) push would
/// land in production. The callback receives the sha the CAS just
/// installed (the allocation's own freshly minted counter commit), so a
/// test can construct either a FOREIGN competing reservation or a
/// DESCENDANT of the allocation's own commit and land it on the remote
/// before the allocation's push runs. Subsequent updateRef calls (retry
/// attempts, other refs) pass through untouched.
class _AfterCasRefs extends ManifoldRefs {
  _AfterCasRefs({
    required super.repoPath,
    required super.authorName,
    required super.authorEmail,
    required this.counterRef,
  });

  final LiveManifoldRef counterRef;
  bool _fired = false;
  Future<void> Function(CommitOid casSha)? afterCas;

  @override
  Future<GitResult<void>> updateRef({
    required WritableManifoldRef ref,
    required CommitOid newSha,
    Oid? oldSha,
  }) async {
    final r = await super.updateRef(ref: ref, newSha: newSha, oldSha: oldSha);
    if (r.ok && !_fired && ref == counterRef && afterCas != null) {
      _fired = true;
      await afterCas!(newSha);
    }
    return r;
  }
}
