// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

@Timeout(Duration(minutes: 4))
library;

// review_sync_test.dart — two-clone convergence for review objects.
//
// The ScratchTeam lab exercising the whole reason reviews are
// git-native:
//  Y1  a review published on one clone arrives on the other via the
//      ordinary manifold sync.
//  Y2  CONCURRENT mutations on both clones converge to byte-identical
//      state containing both sides' work, and a further sync is a
//      no-op (anti-ping-pong).
//  Y3  drafts NEVER leave the machine: not on the origin, not in a
//      peer's staging namespace.
//  Y4  round pins transfer and converge; the pinned commit is
//      reachable on the peer.
//  Y5  the turn fold reads the synced state the same on both clones.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/clock.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/manifold_refs.dart';
import 'package:git_desktop/backend/review_anchor.dart';
import 'package:git_desktop/backend/review_records.dart';
import 'package:git_desktop/backend/review_store.dart';

import '../support/scratch_repo.dart';
import '../support/scratch_team.dart';

class _TickClock implements Clock {
  DateTime _t;
  _TickClock(this._t);
  @override
  DateTime now() {
    _t = _t.add(const Duration(seconds: 1));
    return _t;
  }
}

Future<T> ok<T>(Future<GitResult<T>> f) async {
  final r = await f;
  expect(r.ok, isTrue, reason: r.error ?? '');
  return r.data as T;
}

const _alice = ReviewIdentity('alice');
const _bob = ReviewIdentity('bob');

ReviewStore _storeFor(ScratchRepo repo, String who, {int clockSkew = 0}) =>
    ReviewStore(
      ManifoldRefs(
        repoPath: repo.dir.path,
        authorName: who,
        authorEmail: '$who@manifold.local',
      ),
      clock: _TickClock(
          DateTime.utc(2026, 7, 22, 12).add(Duration(minutes: clockSkew))),
    );

ReviewAnchor _anchor() => captureAnchor(
      lines: const ['void main() {', '  run();', '}'],
      lineIndex: 1,
      round: 1,
      commit: 'c' * 40,
      path: 'lib/a.dart',
    );

void main() {
  late ScratchTeam team;
  late ReviewStore aliceStore;
  late ReviewStore bobStore;

  setUp(() async {
    team = await ScratchTeam.create();
    aliceStore = _storeFor(team['alice'], 'alice');
    bobStore = _storeFor(team['bob'], 'bob', clockSkew: 1);
  });

  tearDown(() => team.dispose());

  Future<void> settle() async {
    // Two full rounds propagate any divergence merge both ways.
    for (var i = 0; i < 2; i++) {
      final a = await aliceStore.syncWithRemote();
      expect(a.ok, isTrue, reason: a.error ?? '');
      final b = await bobStore.syncWithRemote();
      expect(b.ok, isTrue, reason: b.error ?? '');
    }
  }

  test('Y0 (static): the local namespace is outside every constructible '
      'fetch refspec', () {
    // Y3 proves this empirically over a real remote; this is the fast
    // static twin so a refspec/namespace edit fails in milliseconds
    // with an explanation. The exclusion is a STRING-PREFIX invariant
    // (review noted it is not compiler-enforced): the only
    // constructible refspec source pattern is `refs/manifold/*`, and
    // `refs/manifold-local/` must never be inside it.
    expect(ManifoldNs.localRoot.startsWith(ManifoldNs.prefix), isFalse,
        reason: 'localRoot under the synced prefix = drafts sync');
    const remote = MetadataRemote('origin');
    final refspecSource = remote.fetchRefspec.split(':').first;
    expect(refspecSource, '+${ManifoldNs.prefix}*',
        reason: 'a broader glob (e.g. refs/manifold*) would swallow '
            'the local namespace — this pin makes that edit loud');
    final localDraft = ManifoldLocalRef.reviewDrafts(1);
    expect(localDraft.startsWith(ManifoldNs.prefix), isFalse);
  });

  test('Y1: a published review arrives on the peer', () async {
    final open = await aliceStore.openThread(
      deskId: 7,
      anchor: _anchor(),
      opener: ReviewComment(
          author: _alice,
          at: DateTime.utc(2026, 7, 22, 9),
          body: 'why run() here?'),
    );
    expect(open.ok, isTrue, reason: open.error ?? '');
    await settle();

    final onBob = (await bobStore.read(7)).data;
    expect(onBob, isNotNull, reason: 'review must arrive via sync');
    expect(onBob!.threads.single.comments.single.body, 'why run() here?');
    expect(onBob.threads.single.anchor.excerpt, '  run();');
  });

  test('Y2: concurrent mutations converge, then go quiet', () async {
    await ok(aliceStore.openThread(
      deskId: 7,
      anchor: _anchor(),
      opener: ReviewComment(
          author: _alice,
          at: DateTime.utc(2026, 7, 22, 9),
          body: 'opening question'),
    ));
    await settle();
    final threadId = (await bobStore.read(7)).data!.threads.single.id;

    // Diverge: both comment on the same thread before either syncs.
    await ok(aliceStore.addComment(
      deskId: 7,
      threadId: threadId,
      comment: ReviewComment(
          author: _alice,
          at: DateTime.utc(2026, 7, 22, 9, 10),
          body: 'alice adds'),
    ));
    await ok(bobStore.addComment(
      deskId: 7,
      threadId: threadId,
      comment: ReviewComment(
          author: _bob,
          at: DateTime.utc(2026, 7, 22, 9, 11),
          body: 'bob adds'),
    ));
    await settle();

    final aState = (await aliceStore.read(7)).data!;
    final bState = (await bobStore.read(7)).data!;
    expect(aState.toBlob(), bState.toBlob(),
        reason: 'clones must converge to identical bytes');
    final bodies =
        aState.threads.single.comments.map((c) => c.body).toList();
    expect(bodies, containsAll(['opening question', 'alice adds', 'bob adds']),
        reason: 'no side of the divergence may be lost');

    // Anti-ping-pong: tips settle to equality and stay put.
    final aliceTip = await team['alice']
        .gitOk(['rev-parse', 'refs/manifold/review/7/state']);
    final bobTip =
        await team['bob'].gitOk(['rev-parse', 'refs/manifold/review/7/state']);
    expect(aliceTip, bobTip, reason: 'both clones on one sha, no re-merging');
    await settle();
    expect(
        await team['alice'].gitOk(['rev-parse', 'refs/manifold/review/7/state']),
        aliceTip,
        reason: 'a further sync must not mint new commits');
  });

  test('Y3: drafts never leave the machine', () async {
    await ok<void>(bobStore.saveDraft(
        7,
        ReviewDraftEntry(
            threadId: '',
            anchor: _anchor(),
            body: 'private half-thought',
            at: DateTime.utc(2026, 7, 22, 9))));
    final sync = await bobStore.syncWithRemote();
    expect(sync.ok, isTrue, reason: sync.error ?? '');

    final onOrigin = await team['bob'].gitOk(['ls-remote', 'origin']);
    expect(onOrigin, isNot(contains('manifold-local')),
        reason: 'the local namespace must never be pushed');
    expect(onOrigin, isNot(contains('drafts')));

    await ok<void>(aliceStore.syncWithRemote());
    final aliceRefs = await team['alice'].allRefs();
    expect(aliceRefs.where((r) => r.contains('manifold-local')), isEmpty,
        reason: 'a peer must never receive another machine\'s drafts');
  });

  test('Y4: round pins transfer, converge, and stay reachable', () async {
    final alice = team['alice'];
    await alice.writeFile('feature.dart', 'void f() {}\n');
    await alice.commitAll('feature work');
    await alice.gitOk(['push', '-q', 'origin', 'main']);
    final cut = await aliceStore.cutRoundIfMoved(
        deskId: 7, branch: 'main', by: _alice);
    expect(cut.ok, isTrue, reason: cut.error ?? '');
    final pinned = cut.data!.commit;
    await settle();

    final bobPin = await team['bob']
        .gitOk(['rev-parse', 'refs/manifold/review/7/round/1']);
    expect(bobPin, pinned, reason: 'the pin must transfer verbatim');
    // The pinned snapshot is present and readable on the peer.
    final type =
        await team['bob'].gitOk(['cat-file', '-t', pinned]);
    expect(type, 'commit');
    final state = (await bobStore.read(7)).data!;
    expect(state.latestRound!.commit, pinned);
    expect(state.latestRound!.changeId, isNotEmpty);
  });

  test('Y6: diverged NEWER-schema docs are left untouched by sync',
      () async {
    await ok(aliceStore.openThread(
      deskId: 7,
      anchor: _anchor(),
      opener: ReviewComment(
          author: _alice, at: DateTime.utc(2026, 7, 22, 9), body: 'base'),
    ));
    await settle();

    // Both clones now rewrite the doc as schemaVersion 99 with
    // DIFFERENT content — a future client's divergence.
    Future<void> futureWrite(ReviewStore store, String marker) async {
      final refs = store.refs;
      final ref = ReviewStore.stateRefFor(7);
      final tip = (await refs.resolveRef(ref)).data!;
      final j = jsonDecode(
              (await refs.readRefBlob(tip, 'review.json')).data!)
          as Map<String, dynamic>;
      j['schemaVersion'] = 99;
      j['futureField'] = marker;
      j['updatedAt'] = DateTime.utc(2026, 7, 23).toIso8601String();
      final blob = await refs.writeBlob(
          const JsonEncoder.withIndent('  ').convert(j));
      final tree = await refs.mkTree({'review.json': blob.data!});
      final commit = await refs.commitTree(
          treeSha: tree.data!, parentSha: tip, message: 'future $marker');
      await ok<void>(
          refs.updateRef(ref: ref, newSha: commit.data!, oldSha: tip));
    }

    await futureWrite(aliceStore, 'alice-future');
    await futureWrite(bobStore, 'bob-future');

    // Syncs must SUCCEED without merging what they don't understand.
    await ok<void>(aliceStore.syncWithRemote());
    await ok<void>(bobStore.syncWithRemote());
    await ok<void>(aliceStore.syncWithRemote());

    final aliceBlob = (await aliceStore.refs.readRefBlob(
            (await aliceStore.refs.resolveRef(ReviewStore.stateRefFor(7)))
                .data!,
            'review.json'))
        .data!;
    final bobBlob = (await bobStore.refs.readRefBlob(
            (await bobStore.refs.resolveRef(ReviewStore.stateRefFor(7)))
                .data!,
            'review.json'))
        .data!;
    expect(aliceBlob, contains('alice-future'),
        reason: "alice's future doc must survive her syncs untouched");
    expect(bobBlob, contains('bob-future'),
        reason: "bob's future doc must survive his syncs untouched");
    expect(aliceBlob, isNot(contains('bob-future')),
        reason: 'no v1-semantics hybrid merge of v99 documents');
  });

  test('Y5: the turn fold reads identically on both clones', () async {
    // bob authors the PR; alice reviews. Alice publishes a thread →
    // ball with bob everywhere.
    await ok(aliceStore.openThread(
      deskId: 7,
      anchor: _anchor(),
      opener: ReviewComment(
          author: _alice,
          at: DateTime.utc(2026, 7, 22, 9),
          body: 'needs a guard'),
    ));
    await settle();

    final onBob = (await bobStore.read(7)).data!;
    final bobTurn = deriveTurn(onBob,
        authorDisplay: 'bob', viewerDisplay: 'bob');
    expect(bobTurn.yourTurn, isTrue, reason: "reviewer acted → author's turn");
    final aliceView = deriveTurn((await aliceStore.read(7)).data!,
        authorDisplay: 'bob', viewerDisplay: 'alice');
    expect(aliceView.yourTurn, isFalse);
    expect(aliceView.waitingOn, 'bob');

    // bob replies → ball back with alice.
    final threadId = onBob.threads.single.id;
    await ok(bobStore.addComment(
      deskId: 7,
      threadId: threadId,
      comment: ReviewComment(
          author: _bob,
          at: DateTime.utc(2026, 7, 22, 10),
          body: 'guard added'),
    ));
    await settle();
    final after = deriveTurn((await aliceStore.read(7)).data!,
        authorDisplay: 'bob', viewerDisplay: 'alice');
    expect(after.yourTurn, isTrue, reason: "author replied → reviewer's turn");
  });
}
