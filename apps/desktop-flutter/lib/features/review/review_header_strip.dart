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

import 'package:flutter/material.dart';

import '../../ui/design_primitives.dart';
import '../../ui/material_surface.dart';
import '../../ui/tokens.dart';
import 'review_chrome.dart';
import 'review_view_model.dart';

class ReviewHeaderStrip extends StatelessWidget {
  final ReviewHeaderView header;
  final ReviewStrings strings;

  const ReviewHeaderStrip({
    super.key,
    required this.header,
    this.strings = const ReviewStrings(),
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
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
      child: Row(
        children: [
          Expanded(
            child: ReviewLine([
              // Round 0 means no round was ever cut (the head branch is
              // unresolvable), and anchoring is refused in that state.
              // The chip used to read "R1" regardless, which claimed a
              // live round while every gutter tap was being silently
              // declined — the header asserting the exact thing the
              // surface below it would not do.
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
              // The other half of "what's new since I looked": the code
              // moved AND the conversation did. Accent, because unlike
              // the file count this is someone waiting on a reply — and
              // the matching accent on individual timestamps is what
              // leads the eye from this number to the comments it
              // counts.
              if (header.newCommentCount > 0) ...[
                const GapSeg(AppSpacing.sm10),
                TextSeg(
                  strings.newComments(header.newCommentCount),
                  color: t.accentBright,
                ),
              ],
              // A verdict already given is a FACT, not an alarm —
              // muted, so it stops competing with the turn pill and
              // unresolved markers for attention (accent was carrying
              // five jobs at once).
              if (header.standing != ReviewStanding.none) ...[
                const GapSeg(AppSpacing.sm10),
                TextSeg(_standingLabel(strings, header),
                    color: t.textMuted, weight: FontWeight.w600),
              ],
            ]),
          ),
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
            if (header.turn == ReviewTurn.yours)
              ChipSeg(ReviewChip(
                label: strings.yourTurn,
                color: t.accentBright,
                variant: ReviewChipVariant.accent,
              ))
            else
              ChipSeg(ReviewChip(
                label: strings.waitingOn(header.waitingOn),
                color: t.textMuted,
                variant: ReviewChipVariant.quiet,
                weight: FontWeight.w400,
              )),
          ]),
        ],
      ),
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
