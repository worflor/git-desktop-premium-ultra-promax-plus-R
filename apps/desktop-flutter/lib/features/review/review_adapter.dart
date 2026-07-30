// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_adapter.dart — records → view models.
//
// The one bridge between the git-backed review objects and the
// surfaces. Widgets stay substrate-blind (they render view models);
// records stay presentation-blind (no strings, no formatting). This
// adapter owns:
//  * anchor RESOLUTION against current file content (the honesty
//    ladder becomes the view's anchorState);
//  * merging the viewer's private DRAFTS into the visible thread list
//    (drafts render, but only for their author);
//  * the turn fold and verdict fold into the header.
//
// It does NOT format for display. Formatting needs the injected
// ReviewStrings, which live with the widgets; a label composed here
// would be composed in exactly one language.

import '../../backend/review_anchor.dart';
import '../../backend/review_records.dart';
import '../../backend/review_store.dart' show ReviewDraftEntry;
import 'review_view_model.dart';

class ReviewViewBundle {
  final ReviewHeaderView header;

  /// Published threads in reading order (kept for consumers that want
  /// the flat list; the pane renders [groups]).
  final List<ReviewThreadView> threads;

  /// Published threads grouped per file, reading order within. File-
  /// scoped threads lead their group; review-scoped ones are NOT here.
  final List<ReviewFileGroupView> groups;

  /// Published threads about the change itself — no file, no line.
  ///
  /// Their own list rather than a group with a blank heading: a comment
  /// on the change is not a comment on a file called "", and the pane
  /// opens with them because that is the order a reviewer thinks in
  /// (what is this, then what is in it).
  final List<ReviewThreadView> reviewThreads;

  /// The viewer's unpublished opener drafts — a separate SECTION, not
  /// interleaved with public threads: a private half-thought is a
  /// different kind of object and must not sort in by path coincidence.
  final List<ReviewThreadView> draftThreads;

  const ReviewViewBundle({
    required this.header,
    required this.threads,
    required this.groups,
    required this.draftThreads,
    this.reviewThreads = const [],
  });
}

/// A draft row's own save time, for ordering rows that share a subject
/// and have no thread id to separate them.
DateTime _firstDraftAt(ReviewThreadView v) =>
    v.comments.isEmpty
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : (v.comments.first.draftAt ?? v.comments.first.at);

String _firstBody(ReviewThreadView v) =>
    v.comments.isEmpty ? '' : v.comments.first.body;

/// Group [threads] by file, preserving the incoming order (which is
/// already the reading order). Shared with the preview lab so fixture
/// stories and adapter output compose identically.
List<ReviewFileGroupView> groupThreadsByFile(List<ReviewThreadView> threads) {
  final order = <String>[];
  final byPath = <String, List<ReviewThreadView>>{};
  for (final t in threads) {
    byPath.putIfAbsent(t.filePath, () {
      order.add(t.filePath);
      return <ReviewThreadView>[];
    }).add(t);
  }
  return [
    for (final p in order)
      ReviewFileGroupView(filePath: p, threads: byPath[p]!),
  ];
}

/// Build the full pane's view models from a state doc.
///
/// [currentFiles] maps path → current line content; anchors resolve
/// against it (absent path → outdated, honestly: we cannot verify the
/// code still exists). [drafts] are the VIEWER's unpublished entries —
/// opener drafts become draft-only threads, reply drafts append as
/// draft comments. [filesSinceLastLook] is supplied by the caller (it
/// needs diff machinery this adapter deliberately doesn't own).
ReviewViewBundle buildReviewViews(
  ReviewState state, {
  required String viewerDisplay,
  required String authorDisplay,
  Map<String, List<String>> currentFiles = const {},
  Map<String, List<String>> oldFiles = const {},

  /// Paths still IN THE CHANGE — what a file-scoped thread is about.
  ///
  /// Membership, not existence: a file reverted to its base content is
  /// still in both trees and no longer in the diff, and a thread saying
  /// "this file should not be in this change" about it has been answered
  /// rather than being current.
  ///
  /// Not sided — membership belongs to the path, and the side only tells
  /// content resolution which tree to read.
  ///
  /// NULL MEANS UNKNOWN, not empty: a caller that could not determine the
  /// change set (a fixture, or a git call that failed) leaves file scopes
  /// as they are instead of marking every one of them outdated.
  Set<String>? changedPaths,
  List<ReviewDraftEntry> drafts = const [],
  int filesSinceLastLook = 0,

  /// Identities of the comments this viewer has already been shown.
  ///
  /// The ONLY unread input. A round pointer and a look timestamp used to
  /// sit beside this and were left behind when the ladder collapsed —
  /// still accepted, no longer read. A parameter that looks like it
  /// configures unread behaviour and silently does nothing is worse than
  /// no parameter, so they are gone: a caller with only a legacy cursor
  /// now fails to compile instead of quietly reporting every historical
  /// comment as new. (The controller seeds this set from that cursor on
  /// the first load after upgrading — see ReviewLastSeen.seedSeen.)
  ///
  /// Exact, and the reason there is no ladder here any more: a round's
  /// comments are a PARTIAL order (concurrent peers are incomparable),
  /// and a read frontier over a partial order is a set rather than a
  /// point. Every scalar cursor this replaced had to guess at ties in
  /// one direction or the other, and both directions were wrong in a
  /// case that actually happens.
  Set<String> seenComments = const {},
}) {
  // The boundary between read and unread: the moment the round the
  // viewer last saw was cut. A comment newer than that is new TO THEM —
  // their own words never are, since writing is looking.

  /// Is this comment new to the viewer?
  ///
  /// Two cases, and there is no third: your own words are never new to
  /// you, and everything else is new until you have been shown it.
  ///
  /// This replaced a six-rung ladder over rounds, sequences and wall
  /// clocks. The ladder existed because a scalar cursor cannot describe
  /// a read frontier over a PARTIAL order — concurrent peers publishing
  /// into one round are incomparable — so it had to guess at ties, and
  /// each guess was wrong in a case that happens. Set membership asks
  /// the question directly and needs no ordering, no clock, and no
  /// migration of the document format.
  bool unseen(ReviewComment c) =>
      c.author.display != viewerDisplay &&
      !seenComments.contains(reviewCommentIdentity(c));

  var newComments = 0;
  // Side-aware resolution: a 'new'-side anchor asks "where is this
  // content in the head version", an 'old'-side anchor (a comment on a
  // deletion row) asks the same of the MERGE-BASE version — the old
  // column only shifts when the base does, and resolving a deleted
  // line against head would mark every deletion comment outdated the
  // moment it was made.
  AnchorResolution resolveSided(ReviewAnchor a) {
    final lines = a.side == 'old' ? oldFiles[a.path] : currentFiles[a.path];
    if (lines == null) {
      return const AnchorResolution(AnchorStatus.outdated, null);
    }
    return resolveAnchor(a, lines);
  }

  /// The honesty ladder, one rung per kind of subject.
  ///
  /// A line can slip and be re-found. A FILE can only be there or gone —
  /// which is worth saying, because "this file should not exist" against
  /// a file that no longer exists is a thread that got what it asked
  /// for. The change itself cannot go stale at all, so a review-scoped
  /// thread is never marked moved or outdated; claiming otherwise would
  /// put a decayed chip on the one thread that cannot decay.
  ///
  /// Exhaustive over the sealed scope: a fourth kind of subject cannot
  /// be added without the compiler stopping here first.
  (ReviewAnchorState, int, String) resolveScope(ReviewScope scope) {
    switch (scope) {
      case LineScope(anchor: final a):
        final res = resolveSided(a);
        return (
          switch (res.status) {
            AnchorStatus.anchored => ReviewAnchorState.anchored,
            AnchorStatus.reanchored => ReviewAnchorState.reanchored,
            AnchorStatus.outdated => ReviewAnchorState.outdated,
          },
          res.line ?? a.line,
          a.excerpt,
        );
      case FileScope(path: final path):
        // MEMBERSHIP, not content and not existence: see the controller's
        // note for why a file scope must never pull a blob in, why "is it
        // still in the tree" was the wrong question, and why an unknown
        // change set must not decay anything.
        return (
          changedPaths == null || changedPaths.contains(path)
              ? ReviewAnchorState.anchored
              : ReviewAnchorState.outdated,
          0,
          '',
        );
      case WholeScope():
        return (ReviewAnchorState.anchored, 0, '');
    }
  }

  ReviewThreadScope kindOf(ReviewScope scope) => switch (scope) {
        LineScope() => ReviewThreadScope.line,
        FileScope() => ReviewThreadScope.file,
        WholeScope() => ReviewThreadScope.review,
      };

  final threads = <ReviewThreadView>[];

  for (final t in state.threads) {
    for (final c in t.comments) {
      if (unseen(c)) newComments++;
    }
    final (state_, line, excerpt) = resolveScope(t.scope);
    final replyDrafts = drafts.where((d) => d.threadId == t.id);
    threads.add(ReviewThreadView(
      threadId: t.id,
      scope: kindOf(t.scope),
      side: switch (t.scope) {
        LineScope(anchor: final a) => a.side,
        FileScope(side: final side) => side,
        WholeScope() => 'new',
      },
      filePath: t.scope.path,
      line: line,
      excerpt: excerpt,
      anchorState: state_,
      lastSeenRound: t.scope.round,
      state: switch (t.state) {
        'done' => ReviewThreadState.done,
        'acked' => ReviewThreadState.acked,
        _ => ReviewThreadState.unresolved,
      },
      resolvedBy: t.resolvedBy?.display ?? '',
      comments: [
        for (final c in t.comments)
          ReviewCommentView(
            author: c.author.display,
            at: c.at,
            body: c.body,
            kind: c.kind == 'robot'
                ? ReviewAuthorKind.robot
                : ReviewAuthorKind.human,
            isUnseen: unseen(c),
          ),
        for (final d in replyDrafts)
          ReviewCommentView(
            author: viewerDisplay,
            at: d.at,
            body: d.body,
            isDraft: true,
            draftAt: d.at,
          ),
      ],
    ));
  }

  // Opener drafts: unpublished threads only the viewer sees — their
  // own section, never interleaved with published discussion.
  final draftThreads = <ReviewThreadView>[];
  for (final d in drafts) {
    final scope = d.scope;
    if (d.threadId.isNotEmpty || scope == null) continue;
    final (state_, line, excerpt) = resolveScope(scope);
    draftThreads.add(ReviewThreadView(
      scope: kindOf(scope),
      side: switch (scope) {
        LineScope(anchor: final a) => a.side,
        FileScope(side: final side) => side,
        WholeScope() => 'new',
      },
      filePath: scope.path,
      line: line,
      excerpt: excerpt,
      anchorState: state_,
      lastSeenRound: scope.round,
      comments: [
        ReviewCommentView(
          author: viewerDisplay,
          at: d.at,
          body: d.body,
          isDraft: true,
          draftAt: d.at,
        ),
      ],
    ));
  }

  // Standing verdict note: per-reviewer-latest decisive verdict, the
  // same fold desk PRs use. CHANGES_REQUESTED outranks APPROVED.
  final standing = <String, ReviewVerdict>{};
  // ROUND first, then the clock. The last write per reviewer wins the
  // standing, so the order this sorts in decides what the header claims —
  // and `at` alone compares two machines' wall clocks. A reviewer who
  // asked for changes at round 1 from a fast machine and approved round 3
  // from a slow one would have had the header still reporting
  // "changes requested" about code they had already signed off.
  final ordered = [...state.verdicts]
    ..sort((a, b) {
      final byRound = a.round.compareTo(b.round);
      if (byRound != 0) return byRound;
      // Then the causal counter, and only then the clock — the same
      // ranking the attention set and thread comments use. Round alone
      // still left two verdicts from one reviewer in ONE round decided by
      // whose machine was ahead.
      final bySeq = a.seq.compareTo(b.seq);
      if (bySeq != 0) return bySeq;
      // TIED: one reviewer, two machines, neither having seen the other
      // when they wrote. There is no causal information linking them and
      // the clocks belong to different computers, so "later" has no
      // answer — and the previous fallback let skew decide whether a
      // reviewer had approved or objected.
      //
      // An unresolvable tie is not "later", it is "we do not know", and
      // the safe reading of not knowing is the BLOCKING one. Reporting
      // "changes requested" when they approved is friction; reporting
      // "approved" when they objected can let unwanted code through.
      // This also matches the rule already applied ACROSS reviewers,
      // where any blocking verdict outranks every approval.
      final aBlocks = a.verdict == 'CHANGES_REQUESTED';
      final bBlocks = b.verdict == 'CHANGES_REQUESTED';
      if (aBlocks != bBlocks) return aBlocks ? 1 : -1;
      final byAt = a.at.compareTo(b.at);
      if (byAt != 0) return byAt;
      // Total, so an exact tie cannot depend on sort stability. The
      // input order is already canonical (the union sorts it), but a
      // comparator that returns 0 for distinguishable values leaves the
      // outcome to the sort implementation rather than to the data.
      return a.verdict.compareTo(b.verdict);
    });
  for (final v in ordered) {
    if (v.verdict == 'APPROVED' || v.verdict == 'CHANGES_REQUESTED') {
      standing[v.by.display] = v;
    }
  }
  final blocking = standing.values
      .where((v) => v.verdict == 'CHANGES_REQUESTED')
      .toList();
  final approving =
      standing.values.where((v) => v.verdict == 'APPROVED').toList();
  // A verdict names the round it was given at once the code has moved
  // past it. "approved · alice" sitting next to a live turn chip reads
  // as a present-tense fact; if alice approved R1 and the branch is on
  // R3 she has not seen the code being described, and the header should
  // not let that pass unqualified. Round-tagging says it without a
  // second concept or an alarm colour.
  //
  // The stamp is a NUMBER here, not "· R1": composing the label is the
  // header's job now, because the header is where the strings are.
  ReviewStandingBy stamp(ReviewVerdict v) {
    final latest = state.latestRound?.n ?? 0;
    final stale = v.round > 0 && latest > v.round;
    return ReviewStandingBy(v.by.display, round: stale ? v.round : 0);
  }

  final ReviewStanding verdictStanding;
  final List<ReviewStandingBy> standingBy;
  if (blocking.isNotEmpty) {
    verdictStanding = ReviewStanding.changesRequested;
    standingBy = blocking.map(stamp).toList();
  } else if (approving.isNotEmpty) {
    verdictStanding = ReviewStanding.approved;
    standingBy = approving.map(stamp).toList();
  } else {
    verdictStanding = ReviewStanding.none;
    standingBy = const [];
  }

  // Reading order, not record order: the pane follows the code —
  // by file, then by the line the thread currently resolves to.
  // Deterministic (path, line, excerpt) so re-renders never shuffle.
  //
  // A file-scoped thread carries line 0, which sorts it to the head of
  // its own file's group for free — "about this file" before "about line
  // 12 of it" — with no special case in the comparator.
  int readingOrder(ReviewThreadView a, ReviewThreadView b) {
    var c = a.filePath.compareTo(b.filePath);
    if (c != 0) return c;
    c = a.line.compareTo(b.line);
    if (c != 0) return c;
    c = a.excerpt.compareTo(b.excerpt);
    if (c != 0) return c;
    // TOTAL, because the new scopes made ties reachable: two file-scoped
    // threads on one path, or two threads about the change itself, agree
    // on (path, line, excerpt) — all three of which are empty or zero for
    // them. A comparator that returns 0 for distinguishable rows leaves
    // their order to the sort implementation, so the pane could shuffle
    // two comments between rebuilds.
    final byId = a.threadId.compareTo(b.threadId);
    if (byId != 0) return byId;
    // Drafts have no thread id yet — they are unpublished — so two of
    // them on one subject were still tied after all of the above. Their
    // own save time and text are what distinguishes them, and both are
    // stable for the life of the draft.
    final at = _firstDraftAt(a).compareTo(_firstDraftAt(b));
    if (at != 0) return at;
    return _firstBody(a).compareTo(_firstBody(b));
  }

  threads.sort(readingOrder);
  draftThreads.sort(readingOrder);

  // Review-scoped threads leave the file list. They keep their place in
  // `threads` (the flat list is every published thread, which is what
  // its consumers count) and are pulled out of `groups`, so no caller
  // can accidentally render a file heading for the change itself.
  bool aboutTheChange(ReviewThreadView v) =>
      v.scope == ReviewThreadScope.review;
  final reviewThreads = threads.where(aboutTheChange).toList();
  final filed = threads.where((v) => !aboutTheChange(v)).toList();

  final turn = deriveTurn(state,
      authorDisplay: authorDisplay, viewerDisplay: viewerDisplay);

  return ReviewViewBundle(
    header: ReviewHeaderView(
      // 0, not 1: a state doc with no rounds is a real state (a
      // verdict-only publish, or a head branch that stopped resolving),
      // and reporting a round that was never cut made the header claim
      // a snapshot nothing was anchored against.
      round: state.latestRound?.n ?? 0,
      turn: turn.yourTurn ? ReviewTurn.yours : ReviewTurn.theirs,
      waitingOn: turn.waitingOn,
      unresolvedCount: state.unresolvedCount,
      filesSinceLastLook: filesSinceLastLook,
      newCommentCount: newComments,
      standing: verdictStanding,
      standingBy: standingBy,
    ),
    threads: threads,
    groups: groupThreadsByFile(filed),
    draftThreads: draftThreads,
    reviewThreads: reviewThreads,
  );
}
