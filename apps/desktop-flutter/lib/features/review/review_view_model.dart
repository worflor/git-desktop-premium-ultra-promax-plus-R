// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_view_model.dart — presentation model for the review surfaces.
//
// Pure display shapes, no git and no stores: the review widgets render
// THESE, and whatever produces them (today the preview fixture, later
// the git-backed review records) adapts into them. Keeping the surface
// blind to the substrate is what lets the look iterate in the preview
// lab before a single ref exists.
//
// Time is carried as a display-ready string (`when`), not a DateTime:
// the widgets never format dates, so previews are deterministic and the
// eventual adapter owns locale-aware formatting.

/// Whose move the review is waiting on, from the viewer's seat.
enum ReviewTurn { yours, theirs }

/// How a thread's anchor currently binds to the code.
///
/// The honesty ladder: [anchored] = the line is exactly where the
/// comment was written; [reanchored] = the line moved and was re-found
/// by content identity (provenance always shown); [outdated] = the code
/// this thread pointed at no longer exists in the current round — the
/// thread pins to its last-seen round instead of guessing.
enum ReviewAnchorState { anchored, reanchored, outdated }

/// A thread's lifecycle state. Unresolved blocks; the two resolved
/// flavors keep WHO closed it and with what intent (Critique's Done =
/// "I changed the code", Ack = "noted, not changing").
enum ReviewThreadState { unresolved, done, acked }

/// Who authored a comment. Robot comments render visually distinct from
/// human ones — a load-bearing separation, never cosmetic.
enum ReviewAuthorKind { human, robot }

class ReviewCommentView {
  final String author;

  /// Display-ready time label ("2h", "yesterday"). Formatting is the
  /// adapter's job, never the widget's.
  final String when;

  /// Markdown body.
  final String body;
  final ReviewAuthorKind kind;

  /// True for the viewer's own unpublished comments — visible only to
  /// them until the batch publishes.
  final bool isDraft;

  const ReviewCommentView({
    required this.author,
    required this.when,
    required this.body,
    this.kind = ReviewAuthorKind.human,
    this.isDraft = false,
  });
}

class ReviewThreadView {
  final String filePath;

  /// Display line number in the round the thread currently binds to.
  final int line;

  /// The anchored source line, verbatim.
  final String excerpt;
  final ReviewAnchorState anchorState;

  /// Round the anchor last resolved in — shown when [anchorState] is
  /// [ReviewAnchorState.outdated] ("last seen R2").
  final int lastSeenRound;
  final ReviewThreadState state;

  /// Who resolved the thread (when [state] is not unresolved).
  final String resolvedBy;
  final List<ReviewCommentView> comments;

  const ReviewThreadView({
    required this.filePath,
    required this.line,
    required this.excerpt,
    this.anchorState = ReviewAnchorState.anchored,
    this.lastSeenRound = 0,
    this.state = ReviewThreadState.unresolved,
    this.resolvedBy = '',
    this.comments = const [],
  });

  bool get isRobot =>
      comments.isNotEmpty && comments.first.kind == ReviewAuthorKind.robot;

  bool get isDraftOnly =>
      comments.isNotEmpty && comments.every((c) => c.isDraft);
}

/// Threads of one file, rendered under a single file header — the
/// path prints once, cards anchor by line. Grouping is what breaks the
/// repeated-chiclet monotony and spares the eye re-diffing identical
/// path strings.
class ReviewFileGroupView {
  final String filePath;
  final List<ReviewThreadView> threads;
  const ReviewFileGroupView({required this.filePath, required this.threads});
}

class ReviewHeaderView {
  /// Current round number (1-based).
  final int round;
  final ReviewTurn turn;

  /// Display name the review waits on when [turn] is theirs.
  final String waitingOn;
  final int unresolvedCount;

  /// Files with new changes since the viewer's last look (0 = caught up).
  final int filesSinceLastLook;

  /// Optional standing-verdict note ("changes requested · mira").
  final String verdictNote;

  const ReviewHeaderView({
    required this.round,
    required this.turn,
    this.waitingOn = '',
    this.unresolvedCount = 0,
    this.filesSinceLastLook = 0,
    this.verdictNote = '',
  });
}

/// One diff-gutter cell's affordance.
enum ReviewGutterState {
  /// Nothing on this line.
  none,

  /// Hover invite — the quiet "+" that a comment could start here.
  invite,

  /// A published thread lives here.
  thread,

  /// The viewer's own unpublished draft.
  draft,

  /// A robot thread (engine finding).
  robot,

  /// A thread whose anchor no longer resolves on this round.
  outdated,
}

/// Display strings for the review surfaces, injected so the widgets are
/// string-blind. English defaults for the preview lab; when the
/// surfaces mount in the app this is populated from the slang tree
/// (context.t.review.*) — the same injected-strings pattern the backend
/// uses to stay Flutter-free, applied here to keep the lab hermetic.
class ReviewStrings {
  final String unresolved;
  final String done;
  final String ack;
  final String reply;
  final String pleaseFix;
  final String draft;
  final String engine;
  final String moved;
  final String yourTurn;
  final String drafts;

  const ReviewStrings({
    this.unresolved = 'unresolved',
    this.done = 'done',
    this.ack = 'ack',
    this.reply = 'reply',
    this.pleaseFix = 'please fix',
    this.draft = 'draft',
    this.engine = 'engine',
    this.moved = 'moved',
    this.yourTurn = 'your turn',
    this.drafts = 'drafts',
  });

  String outdatedLastSeen(int round) => 'outdated · last seen R$round';
  String resolvedBy(String verb, String who) => '$verb · $who';
  String waitingOn(String who) => 'waiting on $who';
  String roundChip(int round) => 'R$round';
  String filesSinceLastLook(int n) =>
      n == 1 ? '1 file since your last look' : '$n files since your last look';
  String unresolvedCount(int n) => '$n unresolved';
}
