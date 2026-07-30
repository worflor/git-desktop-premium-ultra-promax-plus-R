// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_causal_order_test.dart — ordering that does not ask a clock.
//
// Every case here is a merge or a fold that USED to be decided by whose
// wall clock was ahead. They are unit-level on purpose: each is a pure
// function over a hand-built document, so the failing input is written
// down in the test rather than coaxed out of three real clones.
//
// The three in the second group were found by running Manifold's own
// reviewer over the change that introduced the first group — a fix that
// had traded one guarantee for another instead of composing them.
//
//  K1  attention: a later ROUND beats an earlier one, whatever the local
//      counters say.
//  K2  attention: within a round, the causal counter beats the clock —
//      the step-out that a peer's fast clock used to resurrect.
//  K3  attention: same round, same counter, and only then the clock.
//  K4  comments: a comment that HAS a seq is newer than one that never
//      did, so a reply never sorts above the legacy question it answers.
//  K5  the turn fold reads that same order, so a migrated thread reports
//      the right person's turn.
//  K6  verdicts: the standing fold ranks rounds before clocks, so an
//      approval of newer code cannot lose to an older changes-requested.
//  K7  two verdicts in one round rank by sequence.
//  K8  a line thread still serializes as a bare `anchor`, so older
//      clients read it unchanged.
//  K9-K14  unread by MEMBERSHIP: own words, never-shown, the comment
//      that defined the cursor, its concurrent twin, a late arrival
//      from an older round, and a document with no rounds at all.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/merge_policy.dart';
import 'package:git_desktop/backend/review_anchor.dart';
import 'package:git_desktop/backend/review_records.dart';
import 'package:git_desktop/features/review/review_adapter.dart';
import 'package:git_desktop/features/review/review_view_model.dart';

void main() {
  DateTime t(int s) => DateTime.utc(2026, 8, 1, 9, 0, s);

  Map<String, dynamic> att(String who,
          {required bool inSet,
          required int round,
          required int seq,
          required int atSec,
          String by = 'someone'}) =>
      ReviewAttention(
        display: who,
        inSet: inSet,
        at: t(atSec),
        by: by,
        round: round,
        seq: seq,
      ).toJson();

  /// Merge two attention maps through the DECLARED schema.
  ///
  /// [mergeWithSchema] asserts commutativity and canonicality on every
  /// call in test builds, so a merge that depended on argument order
  /// would fail inside here rather than silently.
  bool mergedInSet(Map<String, dynamic> a, Map<String, dynamic> b) {
    String doc(Map<String, dynamic> e) => jsonEncode({
          'schemaVersion': kReviewSchemaVersion,
          'deskId': 1,
          'updatedAt': isoUtc(t(99)),
          'attention': {'alice': e},
        });
    final merged = jsonDecode(
        mergeWithSchema(kReviewStateSchema, doc(a), doc(b)))
        as Map<String, dynamic>;
    final entry = (merged['attention'] as Map)['alice'] as Map;
    return entry['in'] as bool;
  }

  test('K1: a later round wins however long the local history is', () {
    // The stale clone toggled a lot at round 1 and has the bigger seq AND
    // the later clock. It still must not resurrect obsolete attention.
    final stale = att('alice', inSet: true, round: 1, seq: 99, atSec: 50);
    final fresh = att('alice', inSet: false, round: 3, seq: 1, atSec: 10);
    expect(mergedInSet(stale, fresh), isFalse,
        reason: 'a round-1 entry with a longer local counter defeated a '
            'round-3 decision — seq is local mutation history and carries '
            'no cross-round meaning');
  });

  test('K2: within a round the causal counter beats the clock', () {
    // The bug this whole axis started from: alice reads the state (which a
    // peer wrote at seq 5), steps out at seq 6 — on a SLOWER clock. Her
    // decision was made in knowledge of theirs, so it wins.
    final peerSaysBlocked =
        att('alice', inSet: true, round: 2, seq: 5, atSec: 90, by: 'bob');
    final aliceStepsOut =
        att('alice', inSet: false, round: 2, seq: 6, atSec: 20, by: 'alice');
    expect(mergedInSet(peerSaysBlocked, aliceStepsOut), isFalse,
        reason: 'the step-out was silently resurrected by a peer whose '
            'clock ran ahead — the button did nothing');
  });

  test('K3: same round and counter, and only then the clock', () {
    // Genuinely concurrent: neither read the other. The clock is all
    // there is, and it must still be deterministic.
    final a = att('alice', inSet: true, round: 2, seq: 4, atSec: 10);
    final b = att('alice', inSet: false, round: 2, seq: 4, atSec: 20);
    expect(mergedInSet(a, b), isFalse,
        reason: 'a true tie must fall to the timestamp, deterministically');
  });

  // ── comments ──────────────────────────────────────────────────────
  ReviewComment c(String who, int atSec, String body,
          {int seq = 0, int round = 0}) =>
      ReviewComment(
        author: ReviewIdentity(who, key: '$who@x'),
        at: t(atSec),
        body: body,
        seq: seq,
        round: round,
      );

  ReviewState stateWith(List<ReviewComment> comments,
          {List<ReviewVerdict> verdicts = const [],
          int round = 1,
          int roundAtSec = 1}) =>
      ReviewState(
        schemaVersion: kReviewSchemaVersion,
        deskId: 1,
        rounds: [
          ReviewRoundInfo(
              n: round,
              commit: 'c' * 40,
              cutAt: t(roundAtSec),
              changeId: 'chg1',
              by: const ReviewIdentity('alice', key: 'alice@x')),
        ],
        threads: [
          ReviewThreadRecord(
            id: 'th1',
            state: 'unresolved',
            scope: LineScope(ReviewAnchor(
              round: round,
              commit: 'c' * 40,
              path: 'lib/a.dart',
              side: 'new',
              line: 3,
              lineHash: 'ff',
              simHash: 'ff',
              ctx: const [],
              excerpt: 'x',
            )),
            comments: comments,
            updatedAt: t(99),
          ),
        ],
        verdicts: verdicts,
        reviewedFiles: const {},
        updatedAt: t(99),
      );

  test('K15: an older peer can still clear attention', () {
    // Mixed versions. A client too old to stamp a round or a sequence
    // writes a LATER decision; a new-format entry from round 2 sits
    // opposite it. Ranking an absent field as zero made the new entry
    // win automatically, which meant an old peer could never clear,
    // reclaim, or hand off attention again once anyone had upgraded.
    final legacy = <String, dynamic>{
      'display': 'alice',
      'in': false,
      'at': isoUtc(t(90)),
      'by': 'alice',
    };
    final modern = att('alice', inSet: true, round: 2, seq: 3, atSec: 20);
    expect(mergedInSet(legacy, modern), isFalse,
        reason: 'the old peer wrote later and was outranked by a field it '
            'cannot produce — its step-out silently did nothing');

    // And between two entries that BOTH carry rounds, the round still
    // decides, so restoring old-peer participation cost nothing.
    expect(
        mergedInSet(att('alice', inSet: true, round: 1, seq: 9, atSec: 90),
            att('alice', inSet: false, round: 2, seq: 1, atSec: 10)),
        isFalse,
        reason: 'round ranking between two new-format entries regressed');
  });

  test('K4: a backfilled legacy thread orders causally, not by clock', () {
    // The migration path, as the store now produces it. Publishing into
    // a thread whose comments predate sequences NUMBERS them first, so
    // the thread stops being one of the ambiguous mixed-scheme ones and
    // orders causally forever after — even though the reply here was
    // stamped EARLIER than the question by a slower machine.
    final question = c('bob', 90, 'why is this here?', seq: 1);
    final reply = c('alice', 20, 'because of the old API', seq: 2, round: 1);
    final merged = jsonDecode(mergeWithSchema(
      kReviewStateSchema,
      stateWith([question]).toBlob(),
      stateWith([question, reply]).toBlob(),
    )) as Map<String, dynamic>;
    final bodies = [
      for (final e in ((merged['threads'] as List).first
          as Map<String, dynamic>)['comments'] as List)
        (e as Map)['body'] as String,
    ];
    expect(bodies, ['why is this here?', 'because of the old API'],
        reason: 'a fully sequenced thread must order by sequence, whatever '
            'the two machines say');
  });

  test('K4b: a MIXED-scheme thread orders by time, and says so', () {
    // The honest residual. When one comment carries a sequence and the
    // other never did, the record cannot say which case it is — a new
    // reply to an old thread, or an OLD client replying to a new thread.
    // Ranking "present beats absent" gets the first right and puts the
    // second above the comments it answers, every time. So neither is
    // ranked: the timestamp is the only signal both writers produced.
    //
    // This state is no longer reachable through the store (publish
    // backfills), so it describes a document an older client wrote.
    final stamped = c('alice', 20, 'stamped', seq: 1, round: 1);
    final legacy = c('bob', 90, 'from an older client');
    final merged = jsonDecode(mergeWithSchema(
      kReviewStateSchema,
      stateWith([stamped]).toBlob(),
      stateWith([stamped, legacy]).toBlob(),
    )) as Map<String, dynamic>;
    final bodies = [
      for (final e in ((merged['threads'] as List).first
          as Map<String, dynamic>)['comments'] as List)
        (e as Map)['body'] as String,
    ];
    expect(bodies, ['stamped', 'from an older client'],
        reason: 'an unsequenced comment written later must not be dragged '
            'above the sequenced ones — that is the failure that made '
            '"present beats absent" the wrong rule');
  });

  test('K5: the turn fold reads that same order', () {
    // If the fold ordered comments differently from the way they are
    // stored and rendered, it would decide the turn from a sequence the
    // humans never saw.
    final turn = deriveTurn(
      stateWith([
        c('bob', 90, 'why is this here?', seq: 1),
        c('alice', 20, 'because of the old API', seq: 2, round: 1),
      ]),
      authorDisplay: 'alice',
      viewerDisplay: 'alice',
    );
    expect(turn.yourTurn, isFalse,
        reason: 'the author answered, but the fold read the question as '
            'the last word and left the ball with them');
  });

  test('K8: a line thread still serializes as a bare `anchor`', () {
    // The compatibility promise the additive design rests on: a client
    // that predates scopes reads `anchor` and must find a real one.
    // LineScope.toJson() emits exactly that key, so the stored bytes for
    // a line thread did not change at all — which is why no schema bump
    // was needed, and a bump would have locked older clients out
    // entirely (the store REFUSES a higher version).
    //
    // Written down because a reviewer inferred the opposite twice from
    // `...scope.toJson()` at the call site without resolving the sealed
    // subtype. It is a two-line fact; it should not need re-deriving.
    final json = stateWith([c('bob', 5, 'x', seq: 1, round: 1)]).toJson();
    final thread = (json['threads'] as List).first as Map<String, dynamic>;
    expect(thread.containsKey('anchor'), isTrue,
        reason: 'a line-scoped thread stopped emitting `anchor`, so every '
            'older client would read a fabricated zero location');
    final anchor = thread['anchor'] as Map<String, dynamic>;
    expect(anchor['path'], 'lib/a.dart');
    expect(anchor['line'], 3);
    expect(anchor['side'], 'new');
    expect(thread.containsKey('scope'), isFalse,
        reason: 'a line thread should carry no scope key: the anchor IS '
            'the line scope, and emitting both would double the bytes of '
            'the common case for no reader');
  });

  test('K8b: a FILE thread names its file to an older client too', () {
    // A file scope has no line to put in a legacy anchor, but it does
    // have a path — and naming it costs nothing while turning "blank
    // thread against no file" into "thread against the right file" on a
    // client too old to read scopes.
    final scoped = FileScope(
        path: 'lib/a.dart', side: 'new', round: 2, commit: 'd' * 40);
    final j = scoped.toJson();
    expect(j.containsKey('scope'), isTrue);
    final anchor = j['anchor'] as Map<String, dynamic>;
    expect(anchor['path'], 'lib/a.dart');
    expect(anchor['line'], 0,
        reason: 'line 0 is not a line — the anchor names the file and '
            'claims nothing about a position it does not have');
    // And a current reader still takes the scope, not the shim.
    expect(ReviewScope.fromJson(j), isA<FileScope>());
  });

  // ── unread, by membership ──────────────────────────────────────
  //
  // The six-rung ladder these replaced tried to describe a read frontier
  // with a scalar. A round's comments are a PARTIAL order — concurrent
  // peers are incomparable — so the scalar had to guess at ties, and both
  // guesses were wrong in a case that happens. Membership asks directly.
  int unreadWith(Set<String> seen, List<ReviewComment> comments) =>
      buildReviewViews(
        stateWith(comments),
        viewerDisplay: 'alice',
        authorDisplay: 'alice',
        seenComments: seen,
      ).header.newCommentCount;

  test('K9: unread — your own words are never new', () {
    final mine = c('alice', 5, 'mine', seq: 1, round: 1);
    expect(unreadWith(const {}, [mine]), 0,
        reason: 'writing is looking');
  });

  test('K10: unread — anything not yet shown is new, whatever its clock',
      () {
    // A comment stamped BEFORE everything the viewer has read, by a
    // machine running behind. Nothing about a clock enters this decision
    // any more.
    final theirs = c('bob', 1, 'stamped early, arrived late', seq: 9,
        round: 1);
    expect(unreadWith(const {}, [theirs]), 1);
  });

  test('K11: unread — the comment that DEFINED the cursor is seen', () {
    // The scalar could not express this. Both cursor writers stored the
    // maximum sequence the viewer had seen, and the ladder treated
    // "equal to the cursor" as unread — so the newest comment at the
    // moment "caught up" was pressed was flagged unread permanently.
    final theirs = c('bob', 5, 'the one I was looking at', seq: 3,
        round: 1);
    expect(unreadWith({reviewCommentIdentity(theirs)}, [theirs]), 0,
        reason: 'the comment that set the cursor kept re-announcing '
            'itself, because a point cannot hold both "the twin I never '
            'saw" and "the one I just read" at the same number');
  });

  test('K12: unread — a concurrent twin at the same number is NOT seen',
      () {
    // ...and the same set says the opposite about the peer's comment
    // that ties with it, which is the pair no scalar can separate.
    final read = c('bob', 5, 'the one I was looking at', seq: 3, round: 1);
    final twin = c('cara', 6, 'published concurrently', seq: 3, round: 1);
    expect(unreadWith({reviewCommentIdentity(read)}, [read, twin]), 1,
        reason: 'the tied twin was never shown and must count');
  });

  test('K13: unread — a late arrival from an older round still counts',
      () {
    // A peer publishing from a doc that predates the cut stamps the OLD
    // round and arrives after the viewer has moved on. The ladder read
    // "earlier round" as "already seen" and buried it — an under-report,
    // which is the failure nobody ever notices.
    final old = c('bob', 5, 'stamped round 1, arrived after round 2',
        seq: 2, round: 1);
    final current = c('cara', 6, 'round 2', seq: 1, round: 2);
    expect(
        unreadWith({reviewCommentIdentity(current)}, [old, current]), 1,
        reason: 'a late round-1 arrival was silently marked read because '
            'the cursor had already advanced past round 1');
  });

  test('K14: unread — a document with no rounds at all still works', () {
    // No round, no sequence, no timestamp cursor. The whole legacy
    // fallback the ladder needed for this case is simply gone.
    final legacy = c('bob', 5, 'from before any of this existed');
    expect(unreadWith(const {}, [legacy]), 1);
    expect(unreadWith({reviewCommentIdentity(legacy)}, [legacy]), 0);
  });

  test('K7: two verdicts in ONE round rank by sequence, not by clock', () {
    // One reviewer changes their mind in the same round from two
    // machines: the causal counter says which came second, and the
    // clocks disagree with it.
    final bundle = buildReviewViews(
      stateWith(
        [c('bob', 5, 'a note', seq: 1, round: 1)],
        verdicts: [
          ReviewVerdict(
              by: const ReviewIdentity('bob', key: 'bob@x'),
              verdict: 'CHANGES_REQUESTED',
              at: t(90),
              round: 1,
              seq: 1),
          ReviewVerdict(
              by: const ReviewIdentity('bob', key: 'bob@x'),
              verdict: 'APPROVED',
              at: t(20),
              round: 1,
              seq: 2),
        ],
      ),
      viewerDisplay: 'alice',
      authorDisplay: 'alice',
    );
    expect(bundle.header.standing, ReviewStanding.approved,
        reason: 'the reviewer approved AFTER asking for changes, in the '
            'same round — the header showed the older verdict because the '
            'fold fell back to a wall clock the machines disagreed on');
  });

  test('K7b: an unresolvable verdict tie reads as BLOCKING', () {
    // One reviewer, two machines, neither having synced the other when
    // they wrote: same round, same sequence, and clocks that disagree.
    // Nothing orders them, so "later" has no answer — and letting skew
    // pick meant a reviewer's objection could be reported as approval.
    //
    // Not knowing must not resolve to "approved". Same reading the fold
    // already takes ACROSS reviewers, where any block outranks every
    // approval.
    ReviewStanding standingWith(int approvedAtSec, int blockedAtSec) =>
        buildReviewViews(
          stateWith(
            [c('bob', 5, 'a note', seq: 1, round: 1)],
            verdicts: [
              ReviewVerdict(
                  by: const ReviewIdentity('bob', key: 'bob@x'),
                  verdict: 'APPROVED',
                  at: t(approvedAtSec),
                  round: 1,
                  seq: 4),
              ReviewVerdict(
                  by: const ReviewIdentity('bob', key: 'bob@x'),
                  verdict: 'CHANGES_REQUESTED',
                  at: t(blockedAtSec),
                  round: 1,
                  seq: 4),
            ],
          ),
          viewerDisplay: 'alice',
          authorDisplay: 'alice',
        ).header.standing;

    // Whichever way the two clocks happen to fall, the answer is the
    // same — which is the point: the clock stops deciding.
    expect(standingWith(90, 10), ReviewStanding.changesRequested,
        reason: 'a tied objection lost to an approval with a later clock');
    expect(standingWith(10, 90), ReviewStanding.changesRequested);
  });

  test('K6: a later-round approval outranks an older changes-requested',
      () {
    // One reviewer, two machines, skewed clocks: changes requested at
    // round 1 stamped late, approved at round 3 stamped early.
    final bundle = buildReviewViews(
      stateWith(
        [c('bob', 5, 'a note', seq: 1, round: 1)],
        round: 3,
        verdicts: [
          ReviewVerdict(
              by: const ReviewIdentity('bob', key: 'bob@x'),
              verdict: 'CHANGES_REQUESTED',
              at: t(90),
              round: 1),
          ReviewVerdict(
              by: const ReviewIdentity('bob', key: 'bob@x'),
              verdict: 'APPROVED',
              at: t(20),
              round: 3),
        ],
      ),
      viewerDisplay: 'alice',
      authorDisplay: 'alice',
    );
    expect(bundle.header.standing, ReviewStanding.approved,
        reason: 'the header claimed changes were still requested about '
            'code the same reviewer had already approved — the standing '
            'fold sorted verdicts by wall clock alone');
  });
}
