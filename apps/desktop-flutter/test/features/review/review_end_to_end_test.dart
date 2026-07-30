// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_end_to_end_test.dart — three humans, three machines, one review.
//
// The flow a single developer cannot walk by hand, walked deterministically:
// an author and TWO independent reviewers on real clones of a real bare
// origin, every write going through the real ReviewStore, every read coming
// back through the real ReviewPaneController, and the pane rendered from
// whatever that machine can actually prove.
//
// Two parties can express "the other side cannot see my drafts". Only three
// can express "my co-reviewer cannot see my drafts either", which is the
// property that makes a review safe to think in — and it is the one nothing
// covered before this file.
//
//  E1  a comment written on one machine, published and synced, is readable
//      as the SAME comment on every other machine.
//  E2  drafts are private per MACHINE, not per side: two reviewers drafting
//      on the same line see only their own, before and after syncing, and
//      the remote never hears about either.
//  E3  two reviewers publishing concurrently lose nothing — the union
//      lands, and every machine agrees on it exactly.
//  E4  the pane a human reads is a function of that machine's refs: the
//      published comment is on screen, the co-reviewer's unpublished draft
//      is not. This is the seam the fixture-only pane tests cannot reach.
//  E5  an anchor survives the author moving the line under it, and the
//      thread still points at the content it was written about.
//  E6  a verdict published by one reviewer is visible to everyone, and
//      every machine derives the same turn from it.
//  E7  the late joiner reconstructs the review from refs alone: same
//      comments, same threads, same turn, and it renders. The review lives
//      in git, not in the process that wrote it.
//  E8  two reviewers replying INTO THE SAME THREAD from two machines both
//      land — the per-thread comment union, which E1-E7 never touched
//      because every one of them opened its own thread.
//  E9  with the attention set emptied by a real step-out, the event fold
//      still names the author — the fallback half of the turn rule, which
//      nothing reached because every path through the real verbs leaves
//      attention populated.
//
// E8 and E9 exist because the first seven passed under mutation: breaking
// the comment union and breaking the author's own turn derivation both
// left the suite green. Falsification is not a formality.
//
// Most of these are plain test()s on purpose: the review's behaviour is
// store-and-controller behaviour, and testWidgets would only add a
// fake-async zone that the git layer cannot run in (see
// requireRealAsync). The two that DO render put the git half inside
// tester.runAsync.

@Timeout(Duration(minutes: 10))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/review_records.dart';
import 'package:git_desktop/features/review/review_pane_controller.dart';
import 'package:git_desktop/features/review/review_view_model.dart';

import '../../support/review_lab.dart';

void main() {
  late ReviewLab lab;

  setUp(() async => lab = await ReviewLab.create());
  tearDown(() async => lab.dispose());

  List<String> bodiesOf(ReviewState s) =>
      [for (final t in s.threads) ...t.comments.map((c) => c.body)]..sort();

  /// What every machine believes was said, keyed by whose machine it is.
  Future<Map<String, List<String>>> everyoneSees() async {
    final out = <String, List<String>>{};
    for (final m in lab.members.values) {
      out[m.name] = bodiesOf((await m.read()).state!);
    }
    return out;
  }

  test('E1: a published comment reads identically on every machine', () async {
    const said = 'this branch is doing two things at once';
    await lab['bob'].say(5, said);
    await lab.syncAll();

    final seen = await everyoneSees();
    expect(seen['bob'], contains(said),
        reason: 'the machine that published it cannot read it back');
    for (final entry in seen.entries) {
      expect(entry.value, seen['bob'],
          reason: '${entry.key} disagrees about what was said');
    }
  });

  test('E2: drafts are private per machine, not per side', () async {
    // A published comment first, so the remote is carrying a real review
    // for the control below to find — and so the drafts have to stay
    // private while the very same machines are pushing public comments.
    await lab['bob'].say(3, 'bob: published, on purpose');
    await lab.syncAll();

    // Now both reviewers draft on the SAME line, neither publishes.
    for (final who in [lab['bob'], lab['cara']]) {
      await who.draftOpener(7, '${who.name} drafted');
    }
    await lab.syncAll();

    for (final who in lab.members.values) {
      final drafts = [for (final d in (await who.read()).drafts) d.body];
      final mine =
          who.name == lab.author.name ? <String>[] : ['${who.name} drafted'];
      expect(drafts, mine,
          reason: '${who.name} sees the wrong draft set. A draft is private '
              'to the MACHINE that wrote it, so a co-reviewer drafting on '
              'the same line must be invisible — not merely absent from the '
              "author's view");
    }

    // And nothing draft-shaped ever reached the shared remote.
    final remote = await lab.author.repo.gitOk(['ls-remote', 'origin']);
    // Positive control first: a listing that came back empty (wrong
    // remote, silent failure) would make the two negatives below pass
    // for no reason at all, forever.
    expect(remote, contains('refs/manifold/review/${lab.deskId}/state'),
        reason: 'the remote is not carrying the review at all, so the '
            'privacy assertions below prove nothing: $remote');
    expect(remote.contains('manifold-local'), isFalse,
        reason: 'a draft ref reached the remote: $remote');
    expect(remote.contains('drafted'), isFalse);
  });

  test('E3: concurrent publishes from two reviewers lose nothing', () async {
    // Neither reviewer syncs before publishing, so both write on top of
    // the same state doc — the divergence a real team creates hourly.
    await lab['bob'].say(3, 'bob: extract this helper');
    await lab['cara'].say(21, 'cara: the inserted line needs a test');
    await lab.syncAll();

    final seen = await everyoneSees();
    for (final entry in seen.entries) {
      expect(entry.value, contains('bob: extract this helper'),
          reason: '${entry.key} lost bob');
      expect(entry.value, contains('cara: the inserted line needs a test'),
          reason: '${entry.key} lost cara');
    }
    // Convergence, not just presence: the same list everywhere.
    for (final entry in seen.entries) {
      expect(entry.value, seen[lab.author.name],
          reason: '${entry.key} diverged from the author');
    }
    // No duplication either — a merge that unioned by value would double
    // a comment that arrived from two directions.
    final all = seen[lab.author.name]!;
    expect(all.toSet().length, all.length, reason: 'duplicated comments: $all');
  });

  testWidgets('E4: the pane shows this machine exactly what its refs carry',
      (tester) async {
    await tester.runAsync(() async {
      await lab['bob'].say(5, 'published by bob');
      await lab['cara'].draftOpener(9, 'cara private thought');
      await lab.syncAll();
    });

    // The author's pane: bob's words are on screen, cara's are not.
    await pumpLabPane(tester, lab.author);
    final authorSees = visibleText(tester);
    expect(authorSees, contains('published by bob'),
        reason: 'a published comment must reach the reader');
    expect(authorSees, isNot(contains('cara private thought')),
        reason: 'an unpublished draft from another machine rendered — this '
            'is the assertion fixture-only pane tests could not make');

    // cara's own pane does show her draft: private, not lost.
    await pumpLabPane(tester, lab['cara']);
    final caraSees = visibleText(tester);
    expect(caraSees, contains('cara private thought'),
        reason: 'the machine that wrote a draft must see it');
    expect(caraSees, contains('published by bob'));
  });

  test('E5: an anchor survives the author moving its line', () async {
    const target = 7;
    final wasAbout = lab.lineAt(target);
    await lab['bob'].say(target, 'bob: about this exact line');
    await lab.syncAll();

    // The author inserts five lines ABOVE the commented one and pushes,
    // so the content is untouched and only its address moved.
    await lab.authorEdits(insertAt: 0, count: 5);
    await lab.syncAll();

    final data = await lab.author.read();
    final thread = data.bundle.threads.firstWhere(
      (t) => t.comments.any((c) => c.body.contains('about this exact line')),
      orElse: () => throw StateError('the thread vanished from the bundle'),
    );
    expect(thread.anchorState, isNot(ReviewAnchorState.outdated),
        reason: 'a pure insertion above a line marked it outdated — the '
            'content it was written about is still there verbatim');
    final lines = await lab.subjectLines();
    expect(lines[thread.line - 1], wasAbout,
        reason: 'the thread points at line ${thread.line}, which holds '
            '"${lines[thread.line - 1]}" rather than the "$wasAbout" the '
            'comment was written about');
  });

  test('E6: a verdict from one reviewer is seen by everyone', () async {
    await lab['bob'].draftOpener(3, 'bob: needs work');
    await lab['bob'].publish(verdict: 'CHANGES_REQUESTED');
    await lab.syncAll();

    // cara publishes the same decision in the WRONG CASE. The standing
    // fold compares against 'APPROVED'/'CHANGES_REQUESTED' exactly, so a
    // verdict normalized only on the read side was silently inert for as
    // long as the writer's own process believed it had landed.
    await lab['cara'].draftOpener(9, 'cara: agreed, needs work');
    await lab['cara'].publish(verdict: 'changes_requested');
    await lab.syncAll();

    final turns = <String, ReviewTurn>{};
    for (final m in lab.members.values) {
      final data = await m.read();
      final verdicts = [for (final v in data.state!.verdicts) v.verdict];
      expect(verdicts.where((v) => v == 'CHANGES_REQUESTED').length, 2,
          reason: '${m.name} does not see both reviewers asking for '
              'changes — a lower-cased verdict must normalize on the way '
              'IN, not on the next reload: $verdicts');
      turns[m.name] = data.bundle.header.turn;
    }
    // The author is being asked for changes; the reviewers are not.
    expect(turns[lab.author.name], ReviewTurn.yours,
        reason: "changes were requested and it is not the author's turn");
    for (final r in lab.reviewers) {
      expect(turns[r.name], ReviewTurn.theirs,
          reason: '${r.name} is told it is their turn after asking the '
              'author for changes');
    }
  });

  testWidgets('E7: a late joiner rebuilds the review from refs alone',
      (tester) async {
    late final LabMember dana;
    late final ReviewPaneData theirs;
    late final ReviewPaneData authors;
    await tester.runAsync(() async {
      await lab['bob'].say(5, 'bob: first');
      await lab['cara'].say(12, 'cara: second');
      await lab.syncAll();
      final first = (await lab['bob'].read()).state!.threads.first;
      await lab['bob'].resolve(first.id);
      await lab.syncAll();

      dana = await lab.lateJoiner();
      theirs = await dana.read();
      authors = await lab.author.read();
    });

    expect(bodiesOf(theirs.state!), bodiesOf(authors.state!),
        reason: 'the late joiner sees a different conversation');
    expect(theirs.state!.threads.length, authors.state!.threads.length);
    expect(theirs.state!.unresolvedCount, authors.state!.unresolvedCount,
        reason: 'a resolution did not survive the trip through git');
    // The strongest form of "it lives in git": the two clones hold the
    // same document, byte for byte, not merely the same summary of it.
    expect(theirs.state!.toBlob(), authors.state!.toBlob(),
        reason: 'the late joiner reconstructed a DIFFERENT state doc');

    // The turn itself is viewer-relative by design (deriveTurn takes the
    // viewer), so it is not comparable across two different humans. What
    // IS checkable is that a cold reader is told the truth about who the
    // ball is with: bob spoke last, so the author owes the next move and
    // dana owes nothing.
    expect(theirs.bundle.header.turn, ReviewTurn.theirs,
        reason: 'a reader who has never spoken is told it is their turn');
    expect(theirs.bundle.header.waitingOn, lab.author.name,
        reason: 'the cold reader cannot say who the change is waiting on');
    // A machine that has never written a word can still read the review.
    await pumpLabPane(tester, dana);
    final sees = visibleText(tester);
    expect(sees, contains('bob: first'));
    expect(sees, contains('cara: second'));
  });

  test('E8: two machines replying into one thread both land', () async {
    // One shared thread, published and distributed first.
    await lab['bob'].say(5, 'bob: why is this here?');
    await lab.syncAll();
    final threadId = (await lab['cara'].read()).state!.threads.single.id;

    // Both reviewers reply to it without seeing each other's reply:
    // the divergence is INSIDE one record, which is the only thing that
    // exercises the thread schema's comment union rather than the
    // state doc's thread union.
    await lab['cara'].draftReply(threadId, 'cara: it came from the old API');
    await lab['cara'].publish();
    await lab.author.draftReply(threadId, 'alice: I will drop it');
    await lab.author.publish();
    await lab.syncAll();

    for (final m in lab.members.values) {
      final state = (await m.read()).state!;
      expect(state.threads.length, 1,
          reason: '${m.name} split one thread into ${state.threads.length}');
      final bodies = [for (final c in state.threads.single.comments) c.body];
      expect(bodies, contains('bob: why is this here?'));
      expect(bodies, contains('cara: it came from the old API'),
          reason: "${m.name} lost cara's reply to a thread alice also "
              'replied to — the two replies merged as whole values '
              'instead of unioning');
      expect(bodies, contains('alice: I will drop it'),
          reason: "${m.name} lost alice's reply");
      expect(bodies.toSet().length, bodies.length,
          reason: 'duplicated replies on ${m.name}: $bodies');
    }
  });

  test('E9: with attention cleared, the event fold still names the author',
      () async {
    await lab['bob'].say(3, 'bob: this needs a second look');
    await lab.syncAll();
    // Publishing put the author in the attention set, and while that set
    // is non-empty it IS the answer. Emptying it through the real verb
    // is the only way a running app reaches the event fold underneath —
    // and that fold has to agree, or "not blocking on me" would silently
    // hand the ball to nobody.
    await lab.author.controller.stepOutOfAttention();
    await lab.syncAll();

    final data = await lab.author.read();
    expect(data.state!.attentionOn, isEmpty,
        reason: 'the step-out did not empty the attention set, so this '
            'test is not reaching the fold it exists to cover');
    expect(data.bundle.header.turn, ReviewTurn.yours,
        reason: 'a reviewer spoke last and no code landed after, so the '
            'ball is with the author — the fold must say so even with '
            'the attention set emptied');
    for (final r in lab.reviewers) {
      final theirs = await r.read();
      expect(theirs.bundle.header.turn, ReviewTurn.theirs,
          reason: '${r.name} is told to act after asking the author to');
      expect(theirs.bundle.header.waitingOn, lab.author.name,
          reason: '${r.name} is not told who the change waits on');
    }
  });
}
