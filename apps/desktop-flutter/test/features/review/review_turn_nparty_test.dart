// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_turn_nparty_test.dart — whose turn it is, with more than two
// people in the room.
//
// Whose turn it is has TWO layers, and building this suite is what made
// the difference clear:
//
//   The STORED attention set (`state.attention`) is per-person and
//   already drained correctly — publishing takes the publisher out, an
//   author's publish brings back only reviewers who are not settled,
//   resolving somebody's thread asks THEM to verify. Every real verb
//   maintains it, so in a live review this layer is the answer.
//
//   The DERIVED fold underneath was the two-party remnant: author versus
//   reviewers as a bloc, unable to say "cara still owes a look while bob
//   is done". It runs whenever the stored set is empty — which a
//   document written before attention existed is, and which any review
//   becomes the moment the people it named all press "not blocking on
//   me". That is now per-person too.
//
// So the tests come in two halves, because they are testing two
// different mechanisms and conflating them is how the first draft of
// this file ended up asserting things no document could know.
//
// A note on what is NOT knowable: a reviewer becomes one by SPEAKING or
// by being handed the review. There is no invitation list, so "cara has
// never opened this" is not a fact the document contains, and the fold
// cannot invent her. Being handed the review (N7) is how she gets named
// before she has said anything.
//
//  A1  the stored set drains: a reviewer who publishes steps out.
//  A2  an author's publish recalls only the unsettled reviewers.
//  A3  resolving somebody's thread asks that person to verify.
//  A4  every machine agrees on the set, because it is computed from the
//      document rather than from who is running the client.
//  N1  the fold, per person: whoever spoke at the current round is
//      settled, whoever spoke only at an older one is not.
//  N2  the author is owed while an unresolved thread's last word is
//      somebody else's, and stops being owed once they answer.
//  N3  the author's reply re-obligates the reviewer it answered — and
//      only them; reviewer-to-reviewer discussion obligates nobody.
//  N4  new code puts every known reviewer back on and takes the author
//      off.
//  N5  a blocking verdict keeps the author owed with nothing open.
//  N6  a review blocked on nobody says so, which the bloc fold could
//      never do.
//  N7  with ONE reviewer the answers are the ones that shipped, so this
//      is a generalization and not a change of behaviour.

@Timeout(Duration(minutes: 20))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/review/review_view_model.dart';

import '../../support/review_lab.dart';

void main() {
  late ReviewLab lab;

  tearDown(() async => lab.dispose());

  /// Who the DOCUMENT says the change is blocked on. Read from the state
  /// doc rather than from a header, because `waitingOn` is deliberately
  /// blank when the ball is the viewer's own and cannot be reassembled
  /// into a set from one seat.
  Future<Set<String>> storedSet(LabMember who) async =>
      (await who.read()).state!.attentionOn.toSet();

  /// The owed set as the FOLD sees it, gathered across seats: a person is
  /// owed when their own machine says it is their turn. Every seat is
  /// asked, which is also the agreement check — one document, one answer
  /// per person, whoever is reading.
  Future<Set<String>> foldOwed() async {
    final owed = <String>{};
    for (final m in lab.members.values) {
      final h = (await m.read()).bundle.header;
      if (h.turn == ReviewTurn.yours) owed.add(m.name);
    }
    // Cross-check against what the others are TOLD they are waiting on:
    // a seat that is not owed must name exactly the owed set.
    for (final m in lab.members.values) {
      final h = (await m.read()).bundle.header;
      if (h.turn == ReviewTurn.yours) continue;
      final named =
          h.waitingOn.isEmpty ? <String>{} : h.waitingOn.split(', ').toSet();
      expect(named, owed,
          reason: '${m.name} is told the review waits on '
              '"${h.waitingOn}" while the seats themselves say $owed');
    }
    return owed;
  }

  // ── A: the stored set, which is what a live review reads ───────────

  test('A1: publishing takes the publisher out of the attention set',
      () async {
    lab = await ReviewLab.create();
    await lab['bob'].say(5, 'bob: one question');
    await lab.syncAll();

    final blocked = await storedSet(lab.author);
    expect(blocked, contains('alice'),
        reason: 'the author was asked a question and is not in the set');
    expect(blocked, isNot(contains('bob')),
        reason: 'bob just published, so he is not blocking anything');
  });

  test('A2: an author\'s publish recalls only the unsettled reviewers',
      () async {
    lab = await ReviewLab.create();
    // bob asks a question. cara approves outright with nothing open.
    await lab['bob'].say(5, 'bob: explain this');
    await lab['cara'].sayOnChange('cara: fine by me', verdict: 'APPROVED');
    await lab.syncAll();
    // The author answers bob's thread.
    final bobs = (await lab.author.read())
        .state!
        .threads
        .firstWhere((t) => t.comments.first.body.startsWith('bob:'));
    await lab.author.draftReply(bobs.id, 'alice: because of the old API');
    await lab.author.publish();
    await lab.syncAll();

    final blocked = await storedSet(lab.author);
    expect(blocked, contains('bob'),
        reason: 'bob was answered and still has an open thread, so the '
            'ball is his');
    expect(blocked, isNot(contains('alice')),
        reason: 'the author just answered');
  });

  test('A3: resolving somebody else\'s thread asks them to verify',
      () async {
    lab = await ReviewLab.create();
    await lab['bob'].say(5, 'bob: this is wrong');
    await lab.syncAll();
    final id = (await lab.author.read()).state!.threads.single.id;
    await lab.author.resolve(id, how: 'done');
    await lab.syncAll();

    expect(await storedSet(lab.author), contains('bob'),
        reason: 'the author claimed to have fixed bob\'s point, which is a '
            'claim bob is the one who can check');
  });

  test('A4: every machine computes the same attention set', () async {
    lab = await ReviewLab.create();
    await lab['bob'].say(5, 'bob: a question');
    await lab['cara'].say(21, 'cara: another');
    await lab.syncAll();

    Set<String>? agreed;
    for (final m in lab.members.values) {
      final theirs = await storedSet(m);
      agreed ??= theirs;
      expect(theirs, agreed,
          reason: '${m.name} disagrees about who is blocked: the set is '
              'computed from the document, not from who is running the '
              'client, precisely so this cannot happen');
    }
    // And each seat's own turn agrees with its membership.
    for (final m in lab.members.values) {
      final data = await m.read();
      expect(data.bundle.header.turn,
          agreed!.contains(m.name) ? ReviewTurn.yours : ReviewTurn.theirs,
          reason: '${m.name}\'s turn chip disagrees with the set it is '
              'derived from');
    }
  });

  // ── N: the fold underneath, reached by everyone stepping out ───────

  test('N1: the fold settles whoever spoke at the current round', () async {
    lab = await ReviewLab.create();
    // Round 1: both reviewers speak, so both are KNOWN reviewers.
    await lab['bob'].say(5, 'bob: round one');
    await lab['cara'].say(21, 'cara: round one');
    await lab.syncAll();
    // Round 2: new code, and only bob comes back to look.
    await lab.authorEdits(insertAt: 0, count: 3);
    await lab.cutRound();
    await lab.syncAll();
    await lab['bob'].sayOnChange('bob: had another look, still fine');
    await lab.syncAll();
    await lab.clearAttention();

    final owed = await foldOwed();
    expect(owed, contains('cara'),
        reason: 'cara has not spoken since the code moved, so there is a '
            'round she has not looked at — the bloc fold could not say '
            'this about one reviewer and not the other');
    expect(owed, isNot(contains('bob')),
        reason: 'bob looked at the current round and is still being told '
            'it is his turn');
  });

  test('N2: the author owes while the last word is somebody else\'s',
      () async {
    lab = await ReviewLab.create();
    await lab['bob'].say(5, 'bob: please explain this');
    await lab.syncAll();
    await lab.clearAttention();
    expect(await foldOwed(), contains('alice'));

    final id = (await lab.author.read()).state!.threads.single.id;
    await lab.author.draftReply(id, 'alice: because of the old API');
    await lab.author.publish();
    await lab.syncAll();
    await lab.clearAttention();

    expect(await foldOwed(), isNot(contains('alice')),
        reason: 'the author answered and is still being waited on');
  });

  test('N3: only the author\'s reply re-obligates a reviewer', () async {
    lab = await ReviewLab.create();
    await lab['bob'].say(5, 'bob: explain this');
    await lab.syncAll();
    // A fellow reviewer joins the thread. Not the author, so bob must
    // NOT be put back on the hook — a busy thread would never settle.
    final id = (await lab['cara'].read()).state!.threads.single.id;
    await lab['cara'].draftReply(id, 'cara: I think it is the old API');
    await lab['cara'].publish();
    await lab.syncAll();
    await lab.clearAttention();

    var owed = await foldOwed();
    expect(owed, isNot(contains('bob')),
        reason: 'a fellow reviewer spoke and bob was re-obligated');
    expect(owed, contains('alice'),
        reason: 'the thread is still open and the last word is not the '
            'author\'s');

    // Now the AUTHOR answers. That does re-obligate bob.
    await lab.author.draftReply(id, 'alice: it is the old API, yes');
    await lab.author.publish();
    await lab.syncAll();
    await lab.clearAttention();

    owed = await foldOwed();
    expect(owed, contains('bob'),
        reason: 'the author answered bob and bob owes an answer back');
    expect(owed, isNot(contains('alice')));
  });

  test('N4: new code recalls the reviewers and releases the author',
      () async {
    lab = await ReviewLab.create();
    await lab['bob'].say(5, 'bob: needs a rename');
    await lab['cara'].say(21, 'cara: needs a test');
    await lab.syncAll();
    await lab.clearAttention();
    expect(await foldOwed(), contains('alice'));

    // A round cut is a move by the CODE and carries no actor, so this
    // must not depend on whose client noticed the push first.
    await lab.authorEdits(insertAt: 0, count: 3);
    await lab.cutRound();
    await lab.syncAll();
    await lab.clearAttention();

    final owed = await foldOwed();
    expect(owed, containsAll(<String>['bob', 'cara']),
        reason: 'new code landed and the reviewers are not asked to look');
    expect(owed, isNot(contains('alice')),
        reason: 'the author just delivered, so the "waiting on" would be '
            'pointing backwards');
  });

  test('N5: a blocking verdict keeps the author owed with nothing open',
      () async {
    lab = await ReviewLab.create();
    await lab['bob'].draftOpener(5, 'bob: this needs work');
    await lab['bob'].publish(verdict: 'CHANGES_REQUESTED');
    await lab.syncAll();
    final id = (await lab['bob'].read()).state!.threads.single.id;
    await lab['bob'].resolve(id);
    await lab.syncAll();
    await lab.clearAttention();

    expect((await lab.author.read()).state!.unresolvedCount, 0);
    expect(await foldOwed(), contains('alice'),
        reason: 'changes were requested and nothing was pushed since, so '
            'the author owes a move even with every thread closed');
  });

  test('N6: a review blocked on nobody says so', () async {
    lab = await ReviewLab.create();
    // Both reviewers speak at the current round and nothing stays open.
    await lab['bob'].sayOnChange('bob: looks right', verdict: 'APPROVED');
    await lab['cara'].sayOnChange('cara: agreed', verdict: 'APPROVED');
    await lab.syncAll();
    for (final t in (await lab['bob'].read()).state!.threads) {
      await lab['bob'].resolve(t.id, how: 'acked');
    }
    await lab.syncAll();
    await lab.clearAttention();

    expect(await foldOwed(), isEmpty,
        reason: 'everyone spoke at this round and nothing is open, so the '
            'review is blocked on nobody. The bloc fold always named '
            'somebody, which is what made a finished review keep nagging '
            'one of the parties');
  });

  test('N7: with one reviewer, the answers are the ones that shipped',
      () async {
    lab = await ReviewLab.create(names: const ['alice', 'bob']);
    await lab['bob'].say(5, 'bob: a question');
    await lab.syncAll();
    await lab.clearAttention();
    expect((await lab.author.read()).bundle.header.turn, ReviewTurn.yours);
    expect((await lab['bob'].read()).bundle.header.turn, ReviewTurn.theirs);
    expect((await lab['bob'].read()).bundle.header.waitingOn, 'alice');

    final id = (await lab.author.read()).state!.threads.single.id;
    await lab.author.draftReply(id, 'alice: because of X');
    await lab.author.publish();
    await lab.syncAll();
    await lab.clearAttention();

    expect((await lab['bob'].read()).bundle.header.turn, ReviewTurn.yours,
        reason: 'the author answered, so it is the reviewer\'s move');
    expect((await lab.author.read()).bundle.header.turn, ReviewTurn.theirs);
    expect((await lab.author.read()).bundle.header.waitingOn, 'bob');
  });
}
