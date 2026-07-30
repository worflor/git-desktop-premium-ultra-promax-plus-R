// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_header_strip.dart — the at-a-glance review state bar.
//
// One row that answers the three free questions without opening
// anything: which round this is, what's new since your last look, and
// whose turn it is. "Your turn" is the loudest element on the strip —
// the whole surface exists to make that fact impossible to miss — and
// everything else stays quiet. Both sides are [ReviewLine] paragraphs,
// so the round chip, the facts, the count, and the turn indicator all
// sit on one derived baseline.
//
// THE TURN CHIP IS ALSO THE CONTROL. It used to only DISPLAY who the
// change was blocked on, while the two verbs that change that
// ("not blocking on me", "hand to <name>") lived in a separate row of
// unrelated controls above the pane. Display in one room, control in
// another, for the single most important state the surface carries.
// Pressing the chip now expands the verbs inline underneath it.
//
// Expansion is on TAP, never on hover: a hover that resized this row
// would move the very control the pointer was travelling toward.

import 'package:flutter/material.dart';

import '../../ui/design_primitives.dart';
import '../../ui/material_surface.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import 'review_chrome.dart';
import 'review_view_model.dart';

class ReviewHeaderStrip extends StatefulWidget {
  final ReviewHeaderView header;
  final ReviewStrings strings;

  /// People this review can be handed to. Empty hides the hand-off.
  final List<String> handOffTo;
  final void Function(String display)? onHandTo;

  /// Take yourself out of the attention set. Null when you are not in
  /// it, which is also when the verb would be meaningless.
  final VoidCallback? onStepOut;

  /// Start a comment about the change itself. Null hides the verb.
  ///
  /// On the change's own row, by the same rule the attention verbs
  /// follow: a verb lives on the thing whose state it changes. The
  /// summary conversation is the change's state, so its verb is here and
  /// not in a row of unrelated controls elsewhere.
  final VoidCallback? onComment;

  const ReviewHeaderStrip({
    super.key,
    required this.header,
    this.strings = const ReviewStrings(),
    this.handOffTo = const [],
    this.onHandTo,
    this.onStepOut,
    this.onComment,
  });

  @override
  State<ReviewHeaderStrip> createState() => _ReviewHeaderStripState();
}

class _ReviewHeaderStripState extends State<ReviewHeaderStrip> {
  bool _open = false;

  /// Whether pressing the turn chip has anything to offer. A chip that
  /// expands to an empty strip is worse than a chip that does not
  /// expand, so it simply is not a button then.
  bool get _actionable =>
      widget.onStepOut != null ||
      (widget.handOffTo.isNotEmpty && widget.onHandTo != null);

  @override
  void didUpdateWidget(ReviewHeaderStrip old) {
    super.didUpdateWidget(old);
    // A reload that removes every verb must not leave an empty drawer
    // hanging open — the state it was showing is gone.
    if (_open && !_actionable) _open = false;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final header = widget.header;
    final strings = widget.strings;
    // elevated: false — same reasoning as the thread card: the
    // down-offset elevation shadow bleeds through the translucent
    // panel fill as a lighter top band that fakes misalignment.
    return MaterialSurface(
      tone: AppMaterialTone.panel,
      borderColor: t.chromeBorder,
      borderAlpha: 0.14,
      elevated: false,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: ReviewLine([
                  // Round 0 means no round was ever cut (the head branch
                  // is unresolvable), and anchoring is refused in that
                  // state. The chip used to read "R1" regardless, which
                  // claimed a live round while every gutter tap was
                  // being silently declined — the header asserting the
                  // exact thing the surface below it would not do.
                  if (header.round > 0)
                    ChipSeg(ReviewChip(
                      label: strings.roundChip(header.round),
                      color: t.textStrong,
                      mono: true,
                    )),
                  if (header.filesSinceLastLook > 0) ...[
                    const GapSeg(AppSpacing.sm10),
                    TextSeg(
                      strings.filesSinceLastLook(header.filesSinceLastLook),
                      color: t.textNormal,
                    ),
                  ],
                  // The other half of "what's new since I looked": the
                  // code moved AND the conversation did. Accent, because
                  // unlike the file count this is someone waiting on a
                  // reply — and the matching accent on individual
                  // timestamps is what leads the eye from this number to
                  // the comments it counts.
                  if (header.newCommentCount > 0) ...[
                    const GapSeg(AppSpacing.sm10),
                    TextSeg(
                      strings.newComments(header.newCommentCount),
                      color: t.accentBright,
                    ),
                  ],
                  // A verdict already given is a FACT, not an alarm —
                  // muted, so it stops competing with the turn pill and
                  // unresolved markers for attention (accent was
                  // carrying five jobs at once).
                  if (header.standing != ReviewStanding.none) ...[
                    const GapSeg(AppSpacing.sm10),
                    TextSeg(_standingLabel(strings, header),
                        color: t.textMuted, weight: FontWeight.w600),
                  ],
                ]),
              ),
              if (widget.onComment != null) ...[
                const SizedBox(width: AppSpacing.sm10),
                ReviewQuietGlyph(
                  icon: Icons.mode_comment_outlined,
                  label: widget.strings.commentOnChange,
                  onTap: widget.onComment,
                ),
              ],
              const SizedBox(width: AppSpacing.sm),
              ReviewLine([
                if (header.unresolvedCount > 0) ...[
                  TextSeg(
                    strings.unresolvedCount(header.unresolvedCount),
                    color: t.textMuted,
                    weight: FontWeight.w600,
                  ),
                  const GapSeg(AppSpacing.sm10),
                ],
                ChipSeg(_turnChip(t)),
              ]),
            ],
          ),
          // The verbs for the state the chip above just reported.
          AnimatedSize(
            // AppMotion.snap is the toggle tier, which is what this is.
            // It was a hand-typed 110ms: wrapping a number you invented
            // in context.motion() scales it with the user's motion rate
            // but still opts this one control out of the shared scale,
            // which is the whole point of having one.
            duration: context.motionRead(AppMotion.snap),
            curve: AppMotion.snapCurve,
            alignment: Alignment.topCenter,
            child: _open && _actionable
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: AppSpacing.sm6,
                            runSpacing: AppSpacing.sm6,
                            children: [
                              if (widget.onStepOut != null)
                                ReviewVerbPill(
                                  label: strings.notBlocking,
                                  onTap: () {
                                    setState(() => _open = false);
                                    widget.onStepOut!();
                                  },
                                ),
                              if (widget.onHandTo != null)
                                ReviewHandOff(
                                  label: strings.handTo,
                                  to: widget.handOffTo,
                                  onHandTo: (who) {
                                    setState(() => _open = false);
                                    widget.onHandTo!(who);
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  ReviewChip _turnChip(AppTokens t) {
    final strings = widget.strings;
    final yours = widget.header.turn == ReviewTurn.yours;
    final press =
        _actionable ? () => setState(() => _open = !_open) : null;
    return yours
        ? ReviewChip(
            label: strings.yourTurn,
            color: t.accentBright,
            variant: ReviewChipVariant.accent,
            onTap: press,
          )
        : ReviewChip(
            // Nobody named means nobody is blocked — a finished review,
            // which the previous author-vs-reviewers fold could never
            // produce and so never needed to say. Rendering the empty
            // name left the chip reading "waiting on " with a trailing
            // space in exactly the moment the work is done.
            label: widget.header.waitingOn.isEmpty
                ? strings.nothingBlocking
                : strings.waitingOn(widget.header.waitingOn),
            color: t.textMuted,
            variant: ReviewChipVariant.quiet,
            weight: FontWeight.w400,
            onTap: press,
          );
  }
}

/// Compose the standing-verdict line: the verdict, then who holds it,
/// each name tagged with the round it was given at when the code has
/// moved past it.
///
/// Assembled here rather than in the adapter because this is where the
/// injected strings are. It used to be built in English inside the view
/// bundle, which meant every locale rendered "changes requested · mira"
/// verbatim no matter what language the rest of the strip was in.
String _standingLabel(ReviewStrings strings, ReviewHeaderView header) {
  final who = [
    for (final b in header.standingBy)
      b.round > 0 ? '${b.display} · ${strings.roundChip(b.round)}' : b.display,
  ].join(', ');
  final verdict = strings.standingLabel(header.standing);
  return who.isEmpty ? verdict : '$verdict · $who';
}
