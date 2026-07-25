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
//  * the turn fold and verdict fold into the header;
//  * display-time formatting (relative labels) — injected `now`, so
//    rendering is deterministic under test.

import '../../backend/review_anchor.dart';
import '../../backend/review_records.dart';
import '../../backend/review_store.dart' show ReviewDraftEntry;
import 'review_view_model.dart';

/// Compact relative-time label. Slang-localizable later; the shape
/// (value+unit, no prose) is deliberately language-thin.
String relativeLabel(DateTime now, DateTime at) {
  final d = now.difference(at);
  if (d.inSeconds < 45) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}

class ReviewViewBundle {
  final ReviewHeaderView header;

  /// Published threads in reading order (kept for consumers that want
  /// the flat list; the pane renders [groups]).
  final List<ReviewThreadView> threads;

  /// Published threads grouped per file, reading order within.
  final List<ReviewFileGroupView> groups;

  /// The viewer's unpublished opener drafts — a separate SECTION, not
  /// interleaved with public threads: a private half-thought is a
  /// different kind of object and must not sort in by path coincidence.
  final List<ReviewThreadView> draftThreads;

  const ReviewViewBundle({
    required this.header,
    required this.threads,
    required this.groups,
    required this.draftThreads,
  });
}

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
  required DateTime now,
  Map<String, List<String>> currentFiles = const {},
  Map<String, List<String>> oldFiles = const {},
  List<ReviewDraftEntry> drafts = const [],
  int filesSinceLastLook = 0,
  DateTime? lastLookAt,
}) {
  // The boundary between read and unread: the moment the round the
  // viewer last saw was cut. A comment newer than that is new TO THEM —
  // their own words never are, since writing is looking.
  bool unseen(ReviewComment c) =>
      lastLookAt != null &&
      c.author.display != viewerDisplay &&
      c.at.isAfter(lastLookAt);
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

  final threads = <ReviewThreadView>[];

  for (final t in state.threads) {
    for (final c in t.comments) {
      if (unseen(c)) newComments++;
    }
    final res = resolveSided(t.anchor);
    final replyDrafts = drafts.where((d) => d.threadId == t.id);
    threads.add(ReviewThreadView(
      threadId: t.id,
      side: t.anchor.side,
      filePath: t.anchor.path,
      line: res.line ?? t.anchor.line,
      excerpt: t.anchor.excerpt,
      anchorState: switch (res.status) {
        AnchorStatus.anchored => ReviewAnchorState.anchored,
        AnchorStatus.reanchored => ReviewAnchorState.reanchored,
        AnchorStatus.outdated => ReviewAnchorState.outdated,
      },
      lastSeenRound: t.anchor.round,
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
            when: relativeLabel(now, c.at),
            body: c.body,
            kind: c.kind == 'robot'
                ? ReviewAuthorKind.robot
                : ReviewAuthorKind.human,
            isUnseen: unseen(c),
          ),
        for (final d in replyDrafts)
          ReviewCommentView(
            author: viewerDisplay,
            when: relativeLabel(now, d.at),
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
    if (d.threadId.isNotEmpty || d.anchor == null) continue;
    final res = resolveSided(d.anchor!);
    draftThreads.add(ReviewThreadView(
      side: d.anchor!.side,
      filePath: d.anchor!.path,
      line: res.line ?? d.anchor!.line,
      excerpt: d.anchor!.excerpt,
      anchorState: switch (res.status) {
        AnchorStatus.anchored => ReviewAnchorState.anchored,
        AnchorStatus.reanchored => ReviewAnchorState.reanchored,
        AnchorStatus.outdated => ReviewAnchorState.outdated,
      },
      lastSeenRound: d.anchor!.round,
      comments: [
        ReviewCommentView(
          author: viewerDisplay,
          when: relativeLabel(now, d.at),
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
  final ordered = [...state.verdicts]..sort((a, b) => a.at.compareTo(b.at));
  for (final v in ordered) {
    if (v.verdict == 'APPROVED' || v.verdict == 'CHANGES_REQUESTED') {
      standing[v.by.display] = v;
    }
  }
  String verdictNote = '';
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
  String stamp(ReviewVerdict v) {
    final latest = state.latestRound?.n ?? 0;
    return v.round > 0 && latest > v.round
        ? '${v.by.display} · R${v.round}'
        : v.by.display;
  }

  if (blocking.isNotEmpty) {
    verdictNote =
        'changes requested · ${blocking.map(stamp).join(', ')}';
  } else if (approving.isNotEmpty) {
    verdictNote = 'approved · ${approving.map(stamp).join(', ')}';
  }

  // Reading order, not record order: the pane follows the code —
  // by file, then by the line the thread currently resolves to.
  // Deterministic (path, line, excerpt) so re-renders never shuffle.
  int readingOrder(ReviewThreadView a, ReviewThreadView b) {
    var c = a.filePath.compareTo(b.filePath);
    if (c != 0) return c;
    c = a.line.compareTo(b.line);
    if (c != 0) return c;
    return a.excerpt.compareTo(b.excerpt);
  }

  threads.sort(readingOrder);
  draftThreads.sort(readingOrder);

  final turn = deriveTurn(state,
      authorDisplay: authorDisplay, viewerDisplay: viewerDisplay);

  return ReviewViewBundle(
    header: ReviewHeaderView(
      round: state.latestRound?.n ?? 1,
      turn: turn.yourTurn ? ReviewTurn.yours : ReviewTurn.theirs,
      waitingOn: turn.waitingOn,
      unresolvedCount: state.unresolvedCount,
      filesSinceLastLook: filesSinceLastLook,
      newCommentCount: newComments,
      verdictNote: verdictNote,
    ),
    threads: threads,
    groups: groupThreadsByFile(threads),
    draftThreads: draftThreads,
  );
}
