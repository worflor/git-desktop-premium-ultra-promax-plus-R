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
// Time is carried as a DateTime, and every label is composed from the
// injected [ReviewStrings] at render. It used to arrive pre-formatted,
// which read as "the widgets never format dates" but actually meant the
// formatting happened once, in English, upstream of every locale.
// Previews stay deterministic by passing a fixed clock to the formatter
// rather than by freezing the string.

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

  /// When the comment was written, in UTC.
  ///
  /// A DateTime rather than a rendered label. It used to arrive
  /// pre-formatted, which put "now" / "2h" — English, and only English
  /// — inside a data structure every locale renders from. Formatting is
  /// the widget's job for the same reason every other string is: that
  /// is where the injected [ReviewStrings] are.
  final DateTime at;

  /// Markdown body.
  final String body;
  final ReviewAuthorKind kind;

  /// True for the viewer's own unpublished comments — visible only to
  /// them until the batch publishes.
  final bool isDraft;

  /// When an unpublished draft was written. Carried so a single draft
  /// can be targeted for removal; meaningless (and unused) for
  /// published comments.
  final DateTime? draftAt;

  /// Landed after the viewer's last look, and not written by them.
  final bool isUnseen;

  const ReviewCommentView({
    required this.author,
    required this.at,
    required this.body,
    this.kind = ReviewAuthorKind.human,
    this.isDraft = false,
    this.draftAt,
    this.isUnseen = false,
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

  /// 'new' | 'old' — which diff column the anchor pins to. Drives the
  /// gutter-marker mapping (old-side threads mark deletion rows).
  final String side;

  /// Stable thread id for verb wiring; empty for unpublished opener
  /// drafts (their verbs live on the batch bar, not the card).
  final String threadId;

  const ReviewThreadView({
    required this.filePath,
    required this.line,
    required this.excerpt,
    this.anchorState = ReviewAnchorState.anchored,
    this.lastSeenRound = 0,
    this.state = ReviewThreadState.unresolved,
    this.resolvedBy = '',
    this.comments = const [],
    this.side = 'new',
    this.threadId = '',
  });

  /// True when any comment here is new to the viewer — what lets the
  /// pane say "these threads moved" without them opening each one.
  bool get hasUnseen => comments.any((c) => c.isUnseen);

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

  /// Comments that landed since that look and are not the viewer's own.
  final int newCommentCount;

  /// The standing verdict across all reviewers, and who holds it.
  ///
  /// Structured rather than the pre-composed "changes requested · mira"
  /// string this used to be: that string was assembled in English in
  /// the adapter and rendered verbatim in all fourteen locales.
  final ReviewStanding standing;

  /// Who the [standing] belongs to. [ReviewStandingBy.round] is 0 when
  /// the verdict is current, or the round it was given at once the code
  /// has moved past it — a verdict that has not seen the code being
  /// described says so rather than reading as present tense.
  final List<ReviewStandingBy> standingBy;

  const ReviewHeaderView({
    required this.round,
    required this.turn,
    this.waitingOn = '',
    this.unresolvedCount = 0,
    this.filesSinceLastLook = 0,
    this.newCommentCount = 0,
    this.standing = ReviewStanding.none,
    this.standingBy = const [],
  });
}

/// The decisive verdict a review currently stands at.
enum ReviewStanding { none, approved, changesRequested }

/// One reviewer's contribution to the standing verdict.
class ReviewStandingBy {
  final String display;

  /// The round the verdict was given at, or 0 when it is current.
  final int round;

  const ReviewStandingBy(this.display, {this.round = 0});

  @override
  bool operator ==(Object other) =>
      other is ReviewStandingBy &&
      other.display == display &&
      other.round == round;

  @override
  int get hashCode => Object.hash(display, round);
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
  final String publish;
  final String discard;
  final String saveDraft;
  final String cancel;
  final String verdictApprove;
  final String verdictRequestChanges;
  final String verdictComment;
  final String caughtUp;
  final String sinceLastLook;
  final String fullDiff;
  final String commentHint;
  final String reopen;
  final String notBlocking;

  /// Verb label for the hand-off controls; the names follow it.
  final String handTo;
  final String markReviewed;

  /// Compact relative time, for spans under a minute. The parameterised
  /// units are methods below, following this class's own convention.
  final String timeNow;

  /// Standing-verdict labels. Past tense on purpose: these describe
  /// where the review stands, not a button you can press, which is why
  /// they are not [verdictApprove] / [verdictRequestChanges].
  final String standingApproved;
  final String standingChangesRequested;

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
    this.publish = 'publish',
    this.discard = 'discard',
    this.saveDraft = 'save draft',
    this.cancel = 'cancel',
    this.verdictApprove = 'approve',
    this.verdictRequestChanges = 'request changes',
    this.verdictComment = 'comment',
    this.caughtUp = 'caught up',
    this.sinceLastLook = 'since your last look',
    this.fullDiff = 'full diff',
    this.commentHint = 'write a comment',
    this.reopen = 'reopen',
    this.notBlocking = 'not blocking on me',
    this.handTo = 'hand to',
    this.markReviewed = 'reviewed',
    this.timeNow = 'now',
    this.standingApproved = 'approved',
    this.standingChangesRequested = 'changes requested',
  });

  /// Compact relative time. Value-plus-unit, no prose, so the shape
  /// survives translation; the unit still has to BE translated, which
  /// it was not while these were literals inside the adapter.
  String timeMinutes(int n) => '${n}m';
  String timeHours(int n) => '${n}h';
  String timeDays(int n) => '${n}d';

  /// The standing verdict, named. Empty for [ReviewStanding.none] so a
  /// caller can test it the same way it tests every other optional
  /// segment.
  String standingLabel(ReviewStanding s) => switch (s) {
        ReviewStanding.none => '',
        ReviewStanding.approved => standingApproved,
        ReviewStanding.changesRequested => standingChangesRequested,
      };

  String outdatedLastSeen(int round) => 'outdated · last seen R$round';
  String resolvedBy(String verb, String who) => '$verb · $who';
  String waitingOn(String who) => 'waiting on $who';
  String roundChip(int round) => 'R$round';
  String filesSinceLastLook(int n) =>
      n == 1 ? '1 file since your last look' : '$n files since your last look';
  String unresolvedCount(int n) => '$n unresolved';
  String draftCount(int n) => n == 1 ? '1 draft' : '$n drafts';
  String newComments(int n) => n == 1 ? '1 new comment' : '$n new comments';
}

/// Compact relative-time label. The shape (value+unit, no prose) is
/// deliberately language-thin, but thin is not the same as absent: the
/// units used to be English literals baked into the view bundle by the
/// adapter, so all fourteen locales rendered "now" and "2h".
///
/// Lives here rather than in the adapter because this is the file that
/// has the strings, and because a widget asking for it must not have to
/// import the record layer to get it.
String relativeLabel(ReviewStrings s, DateTime now, DateTime at) {
  final d = now.difference(at);
  if (d.inSeconds < 45) return s.timeNow;
  if (d.inMinutes < 60) return s.timeMinutes(d.inMinutes);
  if (d.inHours < 24) return s.timeHours(d.inHours);
  return s.timeDays(d.inDays);
}
