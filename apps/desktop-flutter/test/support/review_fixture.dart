// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_fixture.dart — hand-authored synthetic review for the preview lab.
//
// The orrery_fixture pattern applied to review: a deterministic set of
// view models covering every thread state the surfaces must carry —
// unresolved human back-and-forth, resolved (done / ack), an outdated
// anchor, a robot finding, and an unpublished draft — so preview tests
// render the whole state space with no repo, no store, and no clock.
// Two humans (mira: reviewer, jun: author/viewer) plus the varrho
// engine as the robot voice.

import 'package:git_desktop/features/review/review_view_model.dart';

/// The viewer of the fixture review (the author whose turn it is).
const String kFixtureViewer = 'jun';

/// The clock the fixture's relative timestamps are measured against.
///
/// Pinned so a captured preview says the same thing tomorrow. The view
/// models carry real DateTimes now (the labels used to be baked-in
/// English strings), so determinism comes from fixing the clock rather
/// than from freezing the rendered text.
final DateTime kFixtureNow = DateTime.utc(2026, 7, 22, 13);

DateTime _ago({int days = 0, int hours = 0, int seconds = 0}) =>
    kFixtureNow.subtract(
        Duration(days: days, hours: hours, seconds: seconds));

/// All six thread states, in the order a review pane would list them.
List<ReviewThreadView> syntheticReviewThreads() => [
      // 1. Unresolved human thread, mid ping-pong.
      ReviewThreadView(
        filePath: 'lib/backend/git.dart',
        line: 214,
        excerpt:
            '  final lease = stagedTip.data ?? Oid.zeroFor(commitR.data!);',
        state: ReviewThreadState.unresolved,
        comments: [
          ReviewCommentView(
            author: 'mira',
            at: _ago(hours: 3),
            body:
                'This lease falls back to a zero oid sized off `commitR`, '
                'but if the staging fetch failed silently above we lease '
                'against absence on a ref that *does* exist remotely. '
                "Shouldn't the fetch failure abort the push instead?",
          ),
          // Unseen by the viewer: its timestamp carries the accent, and
          // the header's "2 new comments" counts it. The preview must
          // show the pair together — they lead the eye to each other.
          ReviewCommentView(
            author: 'jun',
            at: _ago(hours: 1),
            isUnseen: true,
            body:
                'The lease failing is the safety net there. Worst case the '
                'push is rejected and we retry. But I can make the fetch '
                'failure explicit. Will do.',
          ),
        ],
      ),
      // 2. Resolved by Done — the code changed.
      ReviewThreadView(
        filePath: 'lib/backend/desk_pr_store.dart',
        line: 87,
        excerpt: '  static String encodeBranch(String branch) {',
        state: ReviewThreadState.done,
        resolvedBy: 'jun',
        comments: [
          ReviewCommentView(
            author: 'mira',
            at: _ago(days: 1),
            body:
                'Missing the empty-string guard: `encodeBranch("")` would '
                'mint an empty ref tail.',
          ),
        ],
      ),
      // 3. Resolved by Ack — noted, not changing.
      ReviewThreadView(
        filePath: 'lib/backend/manifold_refs.dart',
        line: 641,
        excerpt: '      await Future<void>.delayed(',
        state: ReviewThreadState.acked,
        resolvedBy: 'jun',
        comments: [
          ReviewCommentView(
            author: 'mira',
            at: _ago(days: 1),
            body:
                'Linear backoff here where the sync path uses jitter. '
                'Fine for now, just noting the asymmetry.',
          ),
        ],
      ),
      // 4. Outdated anchor — the code this pointed at is gone.
      ReviewThreadView(
        filePath: 'lib/backend/manifold_refs.dart',
        line: 512,
        excerpt: '    final hasRemote = await _probeRemote(remote);',
        anchorState: ReviewAnchorState.outdated,
        lastSeenRound: 2,
        state: ReviewThreadState.unresolved,
        comments: [
          ReviewCommentView(
            author: 'mira',
            at: _ago(days: 2),
            body:
                '`_probeRemote` swallows the timeout distinctly from '
                'unreachable. Collapse the two?',
          ),
        ],
      ),
      // 5. Robot finding under the Tricorder contract: changed-lines
      // only, fix attached, promotable via Please fix.
      ReviewThreadView(
        filePath: 'lib/backend/review_store.dart',
        line: 142,
        excerpt: "  final now = DateTime.now();",
        state: ReviewThreadState.unresolved,
        comments: [
          ReviewCommentView(
            author: 'varrho',
            at: _ago(hours: 4),
            kind: ReviewAuthorKind.robot,
            body:
                'Direct `DateTime.now()` in a store. Every other store '
                'takes the `Clock` seam so TTL tests can inject time. '
                'Fix: accept `Clock clock = const SystemClock()`.',
          ),
        ],
      ),
      // 6. The viewer's own unpublished draft.
      ReviewThreadView(
        filePath: 'lib/features/review/review_thread_card.dart',
        line: 58,
        excerpt: '        ? t.textFaint.withValues(alpha: 0.5)',
        state: ReviewThreadState.unresolved,
        comments: [
          ReviewCommentView(
            author: kFixtureViewer,
            at: _ago(seconds: 5),
            isDraft: true,
            body:
                'Note to self: the outdated rule reads too close to the '
                'resolved rule on petrichor. Check both before publish.',
          ),
        ],
      ),
    ];

/// Header variant: the viewer's turn, mid-review, new changes waiting.
ReviewHeaderView syntheticHeaderYourTurn() => const ReviewHeaderView(
      round: 3,
      turn: ReviewTurn.yours,
      unresolvedCount: 3,
      filesSinceLastLook: 2,
      // Both halves of "what's new since I looked" — the code moved AND
      // the conversation did. They share a line and compete for the
      // same eye, so the story has to show them together.
      newCommentCount: 2,
      standing: ReviewStanding.changesRequested,
      standingBy: [ReviewStandingBy('mira')],
    );

/// Header variant: published, waiting on the reviewer, caught up.
ReviewHeaderView syntheticHeaderTheirTurn() => const ReviewHeaderView(
      round: 1,
      turn: ReviewTurn.theirs,
      waitingOn: 'mira',
    );

