// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_store_test.dart — contracts for the review-object store.
//
//  R1  first mutation creates the state doc at
//      refs/manifold/review/<id>/state; read round-trips it.
//  R2  cutRoundIfMoved pins the head as an immutable round ref,
//      records metadata (with a change-id), no-ops when unmoved, and
//      cuts the next round after the head advances.
//  R3  drafts live ONLY under refs/manifold-local/; publish moves them
//      into the shared state atomically (threads open, replies
//      append), deletes the draft ref, and REPLAYS idempotently.
//  R4  resolveThread flips state with provenance.
//  R5  anchors: exact-same content → anchored; content moved →
//      re-anchored at the nearest line; content gone → outdated.
//  R10 reopening a resolved thread is the exact inverse of resolving
//      it — state back to unresolved AND the resolution provenance
//      cleared, so no reader sees "unresolved, resolved by mira".
//  R9  listReviewedDeskIds names exactly the desks with a state doc,
//      even in a namespace thick with round pins — and the glob it hands
//      git really does select only state refs (the claim its cost
//      argument rests on).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/clock.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/manifold_refs.dart';
import 'package:git_desktop/backend/review_anchor.dart';
import 'package:git_desktop/backend/review_records.dart';
import 'package:git_desktop/backend/review_store.dart';

import '../support/scratch_repo.dart';

class _TickClock implements Clock {
  DateTime _t = DateTime.utc(2026, 7, 22, 12);
  @override
  DateTime now() {
    _t = _t.add(const Duration(seconds: 1));
    return _t;
  }
}

const _mira = ReviewIdentity('mira');
const _jun = ReviewIdentity('jun');

/// Await a store call and FAIL the test on error — every result is
/// checked, none dropped (the @useResult contract, honored).
Future<T> ok<T>(Future<GitResult<T>> f) async {
  final r = await f;
  expect(r.ok, isTrue, reason: r.error ?? '');
  return r.data as T;
}

void main() {
  late ScratchRepo repo;
  late ReviewStore store;

  setUp(() async {
    repo = await ScratchRepo.create(name: 'review_store');
    store = ReviewStore(
      ManifoldRefs(
        repoPath: repo.dir.path,
        authorName: 'tester',
        authorEmail: 'tester@manifold.local',
      ),
      clock: _TickClock(),
    );
  });

  tearDown(() => repo.dispose());

  ReviewAnchor anchorOn(List<String> lines, int idx) => captureAnchor(
        lines: lines,
        lineIndex: idx,
        round: 1,
        commit: 'c' * 40,
        path: 'lib/a.dart',
      );

  test('R1: first mutation creates the doc; read round-trips', () async {
    expect((await store.read(7)).data, isNull);
    final lines = ['void main() {', '  run();', '}'];
    final r = await store.openThread(
      deskId: 7,
      anchor: anchorOn(lines, 1),
      opener: ReviewComment(
          author: _mira, at: DateTime.utc(2026, 7, 22), body: 'why run?'),
    );
    expect(r.ok, isTrue, reason: r.error ?? '');
    final refs = await repo.allRefs();
    expect(refs, contains('refs/manifold/review/7/state'));
    final state = (await store.read(7)).data!;
    expect(state.deskId, 7);
    expect(state.threads.single.comments.single.body, 'why run?');
    expect(state.threads.single.anchor.excerpt, '  run();');
  });

  test('R2: round cutting pins, records, no-ops, advances', () async {
    final first = await store.cutRoundIfMoved(
        deskId: 7, branch: 'main', by: _jun);
    expect(first.ok, isTrue, reason: first.error ?? '');
    expect(first.data!.n, 1);
    expect(first.data!.changeId, isNotEmpty,
        reason: 'synthetic change-id must always resolve');
    final head1 = (await repo.head())!;
    expect(first.data!.commit, head1);
    expect(await repo.gitOk(['rev-parse', 'refs/manifold/review/7/round/1']),
        head1);

    final unmoved = await store.cutRoundIfMoved(
        deskId: 7, branch: 'main', by: _jun);
    expect(unmoved.ok, isTrue);
    expect(unmoved.data, isNull, reason: 'unmoved head must not cut');

    await repo.writeFile('f.txt', 'x\n');
    final head2 = await repo.commitAll('advance');
    final second = await store.cutRoundIfMoved(
        deskId: 7, branch: 'main', by: _jun);
    expect(second.data!.n, 2);
    expect(second.data!.commit, head2);
    final state = (await store.read(7)).data!;
    expect(state.rounds.length, 2);
    expect(state.latestRound!.n, 2);
  });

  test('R2b: a foreign orphan pin never blocks later cuts', () async {
    // Simulate a crashed/peer cut: round/1 pins the OLD head, no state
    // metadata exists. A new cut must advance PAST it, not retry the
    // same number until exhaustion (the bug: n derived from state only).
    final oldHead = (await repo.head())!;
    await repo.gitOk(
        ['update-ref', 'refs/manifold/review/7/round/1', oldHead]);
    await repo.writeFile('g.txt', 'y\n');
    final newHead = await repo.commitAll('advance past orphan');

    final cut = await store.cutRoundIfMoved(
        deskId: 7, branch: 'main', by: _jun);
    expect(cut.ok, isTrue, reason: cut.error ?? '');
    expect(cut.data!.n, 2,
        reason: 'must skip the foreign pin at round/1');
    expect(cut.data!.commit, newHead);
    expect(await repo.gitOk(['rev-parse', 'refs/manifold/review/7/round/2']),
        newHead);
  });

  test('R2c: an orphan pin of the CURRENT head is adopted, not duplicated',
      () async {
    // Crash between pin-create and metadata-record: the pin holds the
    // head but the state doc knows nothing. The next cut adopts it.
    final head = (await repo.head())!;
    await repo
        .gitOk(['update-ref', 'refs/manifold/review/7/round/1', head]);

    final cut = await store.cutRoundIfMoved(
        deskId: 7, branch: 'main', by: _jun);
    expect(cut.ok, isTrue, reason: cut.error ?? '');
    expect(cut.data!.n, 1, reason: 'adopt the orphan, do not mint round/2');
    expect(cut.data!.commit, head);
    final refs = await repo.allRefs();
    expect(refs, isNot(contains('refs/manifold/review/7/round/2')),
        reason: 'no duplicate pin of the same commit');
    final state = (await store.read(7)).data!;
    expect(state.rounds.single.n, 1,
        reason: 'metadata recorded under the adopted number');
  });

  test('R3: drafts are local-only; publish is atomic and idempotent',
      () async {
    final lines = ['a', 'b', 'c', 'd', 'e'];
    final at = DateTime.utc(2026, 7, 22, 9);
    await ok<void>(store.saveDraft(
        7,
        ReviewDraftEntry(
            threadId: '',
            anchor: anchorOn(lines, 2),
            body: 'first draft',
            at: at)));
    await ok<void>(store.saveDraft(
        7,
        ReviewDraftEntry(
            threadId: '',
            anchor: anchorOn(lines, 4),
            body: 'second draft',
            at: at.add(const Duration(minutes: 1)))));

    final refs = await repo.allRefs();
    expect(refs, contains('refs/manifold-local/review/7/drafts'));
    expect(refs.where((r) => r.startsWith('refs/manifold/')), isEmpty,
        reason: 'drafting must not touch the shared namespace');

    final pub = await store.publish(
        deskId: 7, author: _mira, verdict: 'CHANGES_REQUESTED');
    expect(pub.ok, isTrue, reason: pub.error ?? '');
    expect(pub.data!.threads.length, 2);
    expect(pub.data!.verdicts.single.verdict, 'CHANGES_REQUESTED');
    expect((await store.listDrafts(7)).data, isEmpty,
        reason: 'publish must clear the draft ref');
    expect(await repo.allRefs(),
        isNot(contains('refs/manifold-local/review/7/drafts')));

    // Replay WITH a verdict: identical drafts re-saved
    // (crash-between-write-and-delete simulation) publish to NOTHING
    // new — including the verdict, whose identity derives from the
    // batch timestamp, not the wall clock.
    // The crash leaves the WHOLE draft set on disk; replay resends it.
    await ok<void>(store.saveDraft(
        7,
        ReviewDraftEntry(
            threadId: '',
            anchor: anchorOn(lines, 2),
            body: 'first draft',
            at: at)));
    await ok<void>(store.saveDraft(
        7,
        ReviewDraftEntry(
            threadId: '',
            anchor: anchorOn(lines, 4),
            body: 'second draft',
            at: at.add(const Duration(minutes: 1)))));
    final replay = await store.publish(
        deskId: 7, author: _mira, verdict: 'CHANGES_REQUESTED');
    expect(replay.ok, isTrue, reason: replay.error ?? '');
    expect(replay.data!.threads.length, 2,
        reason: 'replayed opener must dedupe by (author, at, body)');
    expect(replay.data!.verdicts.length, 1,
        reason: 'replayed verdict must dedupe by batch identity');

    // A reply draft appends to the existing thread.
    final threadId = replay.data!.threads.first.id;
    await ok<void>(store.saveDraft(
        7,
        ReviewDraftEntry(
            threadId: threadId,
            anchor: null,
            body: 'a reply',
            at: at.add(const Duration(minutes: 5)))));
    final withReply = await store.publish(deskId: 7, author: _jun);
    expect(
        withReply.data!.threads
            .firstWhere((t) => t.id == threadId)
            .comments
            .length,
        2);
  });

  test('R4: resolveThread flips state with provenance', () async {
    final lines = ['x', 'y'];
    await ok(store.openThread(
      deskId: 7,
      anchor: anchorOn(lines, 0),
      opener: ReviewComment(
          author: _mira, at: DateTime.utc(2026, 7, 22), body: 'fix?'),
    ));
    final id = (await store.read(7)).data!.threads.single.id;
    final done = await store.resolveThread(
        deskId: 7, threadId: id, by: _jun, how: 'done');
    expect(done.ok, isTrue);
    final t = done.data!.threads.single;
    expect(t.state, 'done');
    expect(t.resolvedBy!.display, 'jun');
    expect(t.resolvedAt, isNotNull);

    final bad = await store.resolveThread(
        deskId: 7, threadId: id, by: _jun, how: 'whatever');
    expect(bad.ok, isFalse);
  });

  test('R6: overlapping saves both survive (CAS retry, no silent loss)',
      () async {
    final lines = ['a', 'b', 'c'];
    final at = DateTime.utc(2026, 7, 22, 9);
    await Future.wait([
      for (var i = 0; i < 4; i++)
        store.saveDraft(
            7,
            ReviewDraftEntry(
                threadId: '',
                anchor: anchorOn(lines, i % 3),
                body: 'racer $i',
                at: at.add(Duration(seconds: i)))),
    ]).then((rs) {
      for (final r in rs) {
        expect(r.ok, isTrue, reason: r.error ?? '');
      }
    });
    final drafts = (await store.listDrafts(7)).data!;
    expect(drafts.length, 4,
        reason: 'every concurrent save must survive: '
            '${drafts.map((d) => d.body).toList()}');
  });

  test('R7: a draft saved mid-publish survives (CAS-delete cleanup)',
      () async {
    final lines = ['x', 'y', 'z'];
    final at = DateTime.utc(2026, 7, 22, 9);
    await ok<void>(store.saveDraft(
        7,
        ReviewDraftEntry(
            threadId: '', anchor: anchorOn(lines, 0), body: 'batched', at: at)));
    // The race: a new draft lands between the durable state write and
    // the draft-ref cleanup.
    store.beforePublishDiscard = () async {
      await ok<void>(store.saveDraft(
          7,
          ReviewDraftEntry(
              threadId: '',
              anchor: anchorOn(lines, 2),
              body: 'mid-publish arrival',
              at: at.add(const Duration(minutes: 1)))));
    };
    final pub = await store.publish(deskId: 7, author: _mira);
    store.beforePublishDiscard = null;
    expect(pub.ok, isTrue, reason: pub.error ?? '');
    expect(pub.data!.threads.length, 1);
    final survivors = (await store.listDrafts(7)).data!;
    expect(survivors.map((d) => d.body), contains('mid-publish arrival'),
        reason: 'the unconsumed draft must NOT be deleted by publish');
  });

  test('R8: foreign fields round-trip through mutations; newer schema '
      'refuses to mutate', () async {
    final lines = ['m', 'n'];
    await ok(store.openThread(
      deskId: 7,
      anchor: anchorOn(lines, 0),
      opener: ReviewComment(
          author: _mira, at: DateTime.utc(2026, 7, 22), body: 'q'),
    ));
    // Inject foreign fields the way a third-party writer would.
    final refs = store.refs;
    final ref = ReviewStore.stateRefFor(7);
    final tip = (await refs.resolveRef(ref)).data!;
    final j = jsonDecode((await refs.readRefBlob(tip, 'review.json')).data!)
        as Map<String, dynamic>;
    j['xzForeignTop'] = {'from': 'other-client'};
    ((j['threads'] as List).first as Map<String, dynamic>)['xzForeignThread'] =
        'keep me';
    final blob = await refs.writeBlob(
        const JsonEncoder.withIndent('  ').convert(j));
    final tree = await refs.mkTree({'review.json': blob.data!});
    final commit = await refs.commitTree(
        treeSha: tree.data!, parentSha: tip, message: 'foreign write');
    await ok<void>(refs.updateRef(
        ref: ref, newSha: commit.data!, oldSha: tip));

    final id = (await store.read(7)).data!.threads.single.id;
    final done = await store.resolveThread(
        deskId: 7, threadId: id, by: _jun, how: 'done');
    expect(done.ok, isTrue, reason: done.error ?? '');
    final after = (await refs.readRefBlob(
            (await refs.resolveRef(ref)).data!, 'review.json'))
        .data!;
    expect(after, contains('xzForeignTop'),
        reason: 'top-level foreign field must survive our rewrite');
    expect(after, contains('xzForeignThread'),
        reason: 'thread-level foreign field must survive our rewrite');

    // Newer schema: reading fine, mutating refused.
    final tip2 = (await refs.resolveRef(ref)).data!;
    final j2 = jsonDecode((await refs.readRefBlob(tip2, 'review.json')).data!)
        as Map<String, dynamic>;
    j2['schemaVersion'] = 99;
    final blob2 = await refs.writeBlob(
        const JsonEncoder.withIndent('  ').convert(j2));
    final tree2 = await refs.mkTree({'review.json': blob2.data!});
    final commit2 = await refs.commitTree(
        treeSha: tree2.data!, parentSha: tip2, message: 'future write');
    await ok<void>(refs.updateRef(
        ref: ref, newSha: commit2.data!, oldSha: tip2));
    expect((await store.read(7)).ok, isTrue, reason: 'reading stays fine');
    final refused = await store.resolveThread(
        deskId: 7, threadId: id, by: _jun, how: 'acked');
    expect(refused.ok, isFalse);
    expect(refused.error, contains('schemaVersion'));
  });

  test('R5: anchor resolution ladder — anchored / re-anchored / outdated',
      () {
    final v1 = [
      'import "a";',
      '',
      'void main() {',
      '  final x = compute();',
      '  print(x);',
      '}',
    ];
    final anchor = captureAnchor(
        lines: v1, lineIndex: 3, round: 1, commit: 'c' * 40, path: 'a.dart');
    expect(anchor.line, 4);
    expect(anchor.excerpt, '  final x = compute();');
    expect(anchor.ctx.length, 5,
        reason: '±4 window clipped by file start: 3 above + 2 below');

    // Unchanged file: anchored, same line.
    var r = resolveAnchor(anchor, v1);
    expect(r.status, AnchorStatus.anchored);
    expect(r.line, 4);

    // Two lines inserted above: exact content found, moved.
    final v2 = ['// new', '// new2', ...v1];
    r = resolveAnchor(anchor, v2);
    expect(r.status, AnchorStatus.reanchored);
    expect(r.line, 6);

    // The line edited away: outdated.
    final v3 = [...v1]..[3] = '  final x = computeFast();';
    r = resolveAnchor(anchor, v3);
    expect(r.status, AnchorStatus.outdated);
    expect(r.line, isNull);

    // Duplicate content: nearest to the recorded position wins.
    final v4 = [
      '  final x = compute();',
      ...v1,
    ];
    r = resolveAnchor(anchor, v4);
    expect(r.status, AnchorStatus.reanchored);
    expect(r.line, 5, reason: 'line 5 is nearer to 4 than line 1');
  });

  test('R9: reviewed-desk listing selects state docs, not round pins',
      () async {
    // Two reviews, one thick with round pins.
    //
    // Read the two assertions below for what they each buy. The ids are
    // CORRECTNESS, and they hold for a prefix listing too — the
    // exact-shape classifier excludes pins either way, deliberately, so
    // no output test can tell the two forms apart. The listRefs
    // assertion is the one that pins the external contract the glob's
    // COST argument rests on: that git selects state refs server-side,
    // so round pins never cross the process boundary at all. That was
    // verified by hand against the real binary once; this is what keeps
    // it verified.
    await ok(store.openThread(
      deskId: 3,
      anchor: anchorOn(const ['alpha'], 0),
      opener: ReviewComment(author: _mira, at: DateTime.utc(2026), body: 'a'),
    ));
    await ok(store.openThread(
      deskId: 11,
      anchor: anchorOn(const ['beta'], 0),
      opener: ReviewComment(author: _jun, at: DateTime.utc(2026), body: 'b'),
    ));
    await repo.writeFile('f.txt', 'one');
    await repo.commitAll('r1');
    await ok(store.cutRoundIfMoved(deskId: 3, branch: 'HEAD', by: _mira));
    await repo.writeFile('f.txt', 'two');
    await repo.commitAll('r2');
    await ok(store.cutRoundIfMoved(deskId: 3, branch: 'HEAD', by: _mira));

    // The pins really are there, so the selection below is choosing
    // between shapes rather than finding an empty namespace either way.
    final everything = await repo.gitOk(
        ['for-each-ref', '--format=%(refname)', 'refs/manifold/review/']);
    expect(everything, contains('/round/'));

    // git's own selection: `*` spans the id segment (for-each-ref matches
    // without FNM_PATHNAME) and a round pin cannot match a pattern ending
    // in /state. If that ever stops being true, the cost argument in
    // listReviewedDeskIds is void and this fails.
    final plumbing = ManifoldRefs(
      repoPath: repo.dir.path,
      authorName: 'tester',
      authorEmail: 'tester@manifold.local',
    );
    final selected = await ok<Map<String, CommitOid>>(
        plumbing.listRefs('${ManifoldNs.reviewPrefix}*/state'));
    expect(selected.keys.toSet(), {
      '${ManifoldNs.reviewPrefix}3/state',
      '${ManifoldNs.reviewPrefix}11/state',
    });

    final ids = await ok(store.listReviewedDeskIds());
    expect(ids, {3, 11});
  });

  test('R10: reopen is the inverse of resolve', () async {
    final anchor = anchorOn(const ['alpha', 'beta'], 0);
    await ok(store.openThread(
      deskId: 5,
      anchor: anchor,
      opener: ReviewComment(
          author: _mira, at: DateTime.utc(2026), body: 'this leaks'),
    ));
    var state = (await ok(store.read(5)))!;
    final id = state.threads.single.id;

    await ok(store.resolveThread(
        deskId: 5, threadId: id, by: _jun, how: 'done'));
    state = (await ok(store.read(5)))!;
    expect(state.threads.single.state, 'done');
    expect(state.threads.single.resolvedBy?.display, 'jun');

    await ok(store.reopenThread(deskId: 5, threadId: id, by: _mira));
    state = (await ok(store.read(5)))!;
    final t = state.threads.single;
    expect(t.state, 'unresolved');
    expect(t.unresolved, isTrue);
    // Provenance goes with it: a thread claiming to be unresolved while
    // still naming a resolver is incoherent to any reader of the format.
    expect(t.resolvedBy, isNull);
    expect(t.resolvedAt, isNull);
    // The conversation itself is untouched — reopening is not undoing.
    expect(t.comments.single.body, 'this leaks');

    // Idempotent: reopening an already-open thread changes nothing.
    await ok(store.reopenThread(deskId: 5, threadId: id, by: _mira));
    state = (await ok(store.read(5)))!;
    expect(state.threads.single.state, 'unresolved');
  });

  test('R11: a concurrent discard does not fail a landed publish', () async {
    // The mirror of R7. R7 covers the drafts ref MOVING mid-publish (a
    // concurrent save); this covers it VANISHING (a concurrent discard).
    // The state write has already landed either way, so reporting
    // failure would tell the user their published review did not
    // publish — the one lie a review tool must not tell.
    final anchor = anchorOn(const ['alpha'], 0);
    await ok(store.saveDraft(
      9,
      ReviewDraftEntry(
        threadId: '',
        anchor: anchor,
        body: 'ship it',
        at: DateTime.utc(2026, 7, 24, 12),
      ),
    ));
    store.beforePublishDiscard = () => store.discardDrafts(9);

    final published = await store.publish(deskId: 9, author: _mira);
    expect(published.ok, isTrue,
        reason: 'state was written; a race on the private half is not a '
            'publish failure: ${published.error}');

    final state = (await ok(store.read(9)))!;
    expect(state.threads.single.comments.single.body, 'ship it');
  });

  test('R12: one draft can be dropped without taking the batch', () async {
    ReviewDraftEntry d(String body, int minute) => ReviewDraftEntry(
          threadId: '',
          anchor: anchorOn(const ['alpha', 'beta'], 0),
          body: body,
          at: DateTime.utc(2026, 7, 24, 12, minute),
        );
    await ok(store.saveDraft(4, d('keep one', 1)));
    await ok(store.saveDraft(4, d('drop me', 2)));
    await ok(store.saveDraft(4, d('keep two', 3)));

    await ok(store.discardDraft(4, d('drop me', 2)));
    var left = await ok(store.listDrafts(4));
    expect(left.map((e) => e.body), ['keep one', 'keep two'],
        reason: 'the other two survive — the whole point');

    // Removing something already gone is a no-op, not an error: a
    // replay or a racing discard has already satisfied the intent.
    await ok(store.discardDraft(4, d('drop me', 2)));
    left = await ok(store.listDrafts(4));
    expect(left, hasLength(2));

    // Emptying the batch removes the ref rather than leaving a husk,
    // so the drafts namespace matches "no drafts exist".
    await ok(store.discardDraft(4, d('keep one', 1)));
    await ok(store.discardDraft(4, d('keep two', 3)));
    expect(await ok(store.listDrafts(4)), isEmpty);
    final refs = await repo.gitOk(
        ['for-each-ref', '--format=%(refname)', 'refs/manifold-local/']);
    expect(refs.contains('review/4/drafts'), isFalse);
  });
}
