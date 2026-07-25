// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_turn_test.dart — whose move is it?
//
// The turn fold is the feature the whole design bets on ("the tool
// makes whose-turn free"), and it is a pure function of the state doc,
// so it deserves direct contracts rather than only being exercised
// through convergence tests.
//
//  T1  a round cut is the CODE moving, not a person: it hands the ball
//      to the reviewers no matter whose client observed it.
//  T2  the fold is deterministic — the same state reads the same on
//      every clone, whoever's client cut the round.
//  T3  DOCUMENTS a known limit: the fold is two-party (author ↔
//      reviewers), so with several reviewers it names the bloc, not the
//      individual still owing. Pinned so that changing it is a
//      deliberate act rather than an accident.
//  T4  a fresh review with no reviewer activity waits on the reviewers.
//  T5  every instant the format writes is UTC — the ordering LWW and
//      the dedup keys both rest on that.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/review_anchor.dart';
import 'package:git_desktop/backend/review_records.dart';

const _author = 'bob';
const _alice = ReviewIdentity('alice');
const _carol = ReviewIdentity('carol');
const _bob = ReviewIdentity('bob');

DateTime _t(int minute) => DateTime.utc(2026, 7, 24, 12, minute);

ReviewState _state({
  List<ReviewThreadRecord> threads = const [],
  List<ReviewVerdict> verdicts = const [],
  List<ReviewRoundInfo> rounds = const [],
}) =>
    ReviewState(
      schemaVersion: kReviewSchemaVersion,
      deskId: 1,
      rounds: rounds,
      threads: threads,
      verdicts: verdicts,
      reviewedFiles: const {},
      updatedAt: _t(59),
    );

ReviewThreadRecord _thread({
  required String id,
  required ReviewIdentity author,
  required DateTime at,
  String body = 'x',
}) =>
    ReviewThreadRecord(
      id: id,
      state: 'unresolved',
      anchor: const ReviewAnchor(
        round: 1,
        commit: 'c',
        path: 'a.dart',
        side: 'new',
        line: 1,
        lineHash: '0000000000000000',
        simHash: '0000000000000000',
        ctx: <String>[],
        excerpt: 'x',
      ),
      comments: [ReviewComment(author: author, at: at, body: body)],
      updatedAt: at,
    );

ReviewRoundInfo _round(int n, DateTime at, ReviewIdentity by) =>
    ReviewRoundInfo(n: n, commit: 'c$n', cutAt: at, by: by, changeId: '');

void main() {
  test('T1: a round hands the ball to reviewers, whoever observed it',
      () {
    // Alice comments; Bob (the author) pushes a fix. Whichever client
    // notices the head move stamps the round — here it is ALICE's
    // background sync, which used to make her the "last actor" and
    // point the ball at Bob, who had just delivered.
    final state = _state(
      threads: [_thread(id: 't1', author: _alice, at: _t(10))],
      rounds: [_round(2, _t(20), _alice)],
    );

    final forAlice = deriveTurn(state,
        authorDisplay: _author, viewerDisplay: 'alice');
    final forBob =
        deriveTurn(state, authorDisplay: _author, viewerDisplay: _author);

    expect(forAlice.yourTurn, isTrue,
        reason: 'new code is waiting for the reviewer to look');
    expect(forBob.yourTurn, isFalse, reason: 'bob already delivered');
    expect(forBob.waitingOn, 'alice');

    // The attribution genuinely does not matter: same answer when BOB's
    // client cut the very same round.
    final cutByBob = _state(
      threads: [_thread(id: 't1', author: _alice, at: _t(10))],
      rounds: [_round(2, _t(20), _bob)],
    );
    expect(
      deriveTurn(cutByBob, authorDisplay: _author, viewerDisplay: 'alice')
          .yourTurn,
      isTrue,
    );
  });

  test('T2: the fold is identical whoever observed the round', () {
    ReviewState withCutter(ReviewIdentity by) => _state(
          threads: [_thread(id: 't1', author: _alice, at: _t(10))],
          rounds: [_round(2, _t(20), by)],
          verdicts: [
            ReviewVerdict(
                by: _alice, verdict: 'APPROVED', at: _t(15), round: 1),
          ],
        );

    for (final viewer in const ['alice', 'carol', _author]) {
      final byAlice =
          deriveTurn(withCutter(_alice), authorDisplay: _author,
              viewerDisplay: viewer);
      final byBob = deriveTurn(withCutter(_bob), authorDisplay: _author,
          viewerDisplay: viewer);
      expect(byAlice.yourTurn, byBob.yourTurn,
          reason: 'turn must not depend on whose client cut the round');
      expect(byAlice.waitingOn, byBob.waitingOn, reason: 'nor must the name');
    }
  });

  test('T3: two-party fold names the reviewer bloc (known limit)', () {
    // Alice has approved this round; carol has not looked. The fold
    // still names both, because it models "the reviewers" as one party.
    // This is pinned as CURRENT behaviour, not endorsed as correct — see
    // the KNOWN LIMIT note in deriveTurn.
    final state = _state(
      threads: [
        _thread(id: 't1', author: _alice, at: _t(10)),
        _thread(id: 't2', author: _carol, at: _t(11)),
      ],
      rounds: [_round(2, _t(20), _bob)],
    );
    final forAuthor =
        deriveTurn(state, authorDisplay: _author, viewerDisplay: _author);
    expect(forAuthor.waitingOn, 'alice, carol');
    expect(forAuthor.yourTurn, isFalse);
  });

  test('T4: a review nobody has reviewed waits on reviewers', () {
    final fresh = _state(rounds: [_round(1, _t(5), _bob)]);
    expect(
      deriveTurn(fresh, authorDisplay: _author, viewerDisplay: 'alice')
          .yourTurn,
      isTrue,
    );
    expect(
      deriveTurn(fresh, authorDisplay: _author, viewerDisplay: _author)
          .yourTurn,
      isFalse,
    );
  });

  test('T5: serialized instants are UTC, not wall clocks', () {
    // A local-stamped DateTime must still land as UTC in the doc.
    final localNoon = DateTime(2026, 7, 24, 12);
    final comment =
        ReviewComment(author: _alice, at: localNoon, body: 'hi').toJson();
    expect(comment['at'], endsWith('Z'),
        reason: 'a zone-less stamp makes LWW compare wall clocks, so a '
            'peer one timezone east wins a race it actually lost');
    expect(DateTime.parse(comment['at'] as String).isAtSameMomentAs(localNoon),
        isTrue, reason: 'same instant, expressed absolutely');

    // Two clients in different zones describing the SAME instant must
    // produce the same string — the dedup key that makes publish
    // replay-safe is that raw string.
    final east = DateTime.utc(2026, 7, 24, 3).toLocal();
    final asWritten =
        ReviewComment(author: _alice, at: east, body: 'hi').toJson()['at'];
    expect(asWritten, '2026-07-24T03:00:00.000Z');

    // And the whole doc, not just comments.
    final state = _state(
      rounds: [_round(1, DateTime(2026, 7, 24, 9), _bob)],
      verdicts: [
        ReviewVerdict(
            by: _alice,
            verdict: 'APPROVED',
            at: DateTime(2026, 7, 24, 10),
            round: 1),
      ],
    );
    final json = state.toJson();
    final round = (json['rounds'] as List).single as Map<String, dynamic>;
    final verdict = (json['verdicts'] as List).single as Map<String, dynamic>;
    expect(round['cutAt'], endsWith('Z'));
    expect(verdict['at'], endsWith('Z'));
    expect(json['updatedAt'], endsWith('Z'));
  });
}
