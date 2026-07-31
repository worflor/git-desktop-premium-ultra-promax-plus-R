// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_thread_card.dart — one anchored comment thread.
//
// The core review surface: an excerpt of the code the thread is pinned
// to, the conversation under it, and the turn verbs (Done / Ack /
// Reply). Robot threads carry a visibly different comment treatment —
// that separation is load-bearing (a machine nit must never read as a
// human ask). Draft-only threads are unpublished: they claim no thread
// state (nothing exists to resolve yet) and carry a draft chip instead.
//
// Every meta row on this card is a [ReviewLine] — one paragraph, one
// baseline — and every badge is a [ReviewChip]. The anchor path is
// fitted by measurement ([middleEllipsize]), so the filename and line
// number always survive; only directory prefix is expendable.

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../ui/design_primitives.dart';
import '../../ui/material_surface.dart';
import '../../ui/prose_markdown.dart';
import '../../ui/tokens.dart';
import 'review_chrome.dart';
import 'review_view_model.dart';

class ReviewThreadCard extends StatelessWidget {
  final ReviewThreadView thread;
  final ReviewStrings strings;

  /// False when the card renders under a file-group header — the
  /// group owns the path; the card anchors by line alone.
  final bool showPath;
  final VoidCallback? onDone;
  final VoidCallback? onAck;
  final VoidCallback? onReply;
  final VoidCallback? onPleaseFix;

  /// Undo a resolution. Rendered on the state chip itself rather than as
  /// a verb, so a resolved card keeps receding (see [_ReopenableChip]).
  final VoidCallback? onReopen;

  /// Remove THIS draft, leaving the rest of the batch intact. Offered
  /// only on draft-only cards: the batch bar's `discard` erases every
  /// unpublished comment on the PR, which is the wrong instrument for
  /// changing your mind about one line.
  final VoidCallback? onDiscardDraft;

  /// The clock relative timestamps are measured against.
  ///
  /// REQUIRED, and deliberately not defaulted to the wall clock. It was
  /// nullable for one revision and the preview lab promptly forgot to
  /// pass it, so every captured PNG relabelled a "3h" comment as "5d"
  /// and would have drifted again every day after. A caller that has to
  /// name its clock cannot silently inherit the wrong one.
  final DateTime now;

  const ReviewThreadCard({
    super.key,
    required this.thread,
    this.strings = const ReviewStrings(),
    required this.now,
    this.showPath = true,
    this.onDone,
    this.onAck,
    this.onReply,
    this.onPleaseFix,
    this.onReopen,
    this.onDiscardDraft,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final unresolved = thread.state == ReviewThreadState.unresolved;
    final draftOnly = thread.isDraftOnly;
    // Resolved threads genuinely recede: the whole card's ink steps
    // down one contrast role so unresolved work pops by comparison,
    // not merely by a dot.
    final dim = !unresolved && !draftOnly;

    final Color rule = draftOnly
        ? t.accentBright.withValues(alpha: 0.35)
        : unresolved
            ? t.accentBright.withValues(alpha: 0.65)
            : t.chromeBorderSubtle;

    // elevated: false — the elevation shadow is offset 12px DOWN and
    // the panel fill is translucent, so on every theme the shadow
    // bleeds through the body while missing the top 12px: a lighter
    // band whose edge slices through the anchor row and reads as
    // misalignment (pixel-scanned in preview). Dense stacked cards
    // don't want per-card depth anyway; the border and the left rule
    // carry the structure.
    return MaterialSurface(
      tone: AppMaterialTone.panel,
      borderColor: t.chromeBorder,
      borderAlpha: 0.14,
      elevated: false,
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: rule, width: 2)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _anchorRow(context, t, dim: dim),
              const SizedBox(height: AppSpacing.sm6),
              // No excerpt above a line: a file-scoped thread has no line
              // to quote and the change itself has no text at all. An
              // empty excerpt box would read as a failure to load the
              // code rather than as a comment that was never about code.
              if (thread.scope == ReviewThreadScope.line) ...[
                _excerpt(context, t, dim: dim),
                const SizedBox(height: AppSpacing.sm),
              ],
              for (final c in thread.comments) ...[
                _ReviewCommentBlock(
                  comment: c,
                  strings: strings,
                  // In a draft-only thread the card already says draft;
                  // the per-comment chip marks the unpublished one only
                  // when it sits among published comments.
                  showDraftChip: c.isDraft && !draftOnly,
                  now: now,
                  dim: dim,
                ),
                if (c != thread.comments.last)
                  const SizedBox(height: AppSpacing.sm),
              ],
              if (unresolved && !draftOnly) ...[
                const SizedBox(height: AppSpacing.sm10),
                _verbRow(context, t),
              ],
              // The one verb an unpublished note gets: remove itself.
              if (draftOnly && onDiscardDraft != null) ...[
                const SizedBox(height: AppSpacing.sm10),
                Row(children: [
                  ReviewVerbPill(
                      label: strings.discard, onTap: onDiscardDraft!),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  ReviewChip _stateChip(AppTokens t) {
    if (thread.isDraftOnly) {
      return ReviewChip(label: strings.draft, color: t.accentBright);
    }
    return switch (thread.state) {
      ReviewThreadState.unresolved => ReviewChip(
          label: strings.unresolved,
          color: t.accentBright,
          variant: ReviewChipVariant.quiet,
          dot: true,
        ),
      ReviewThreadState.done => ReviewChip(
          label: strings.resolvedBy(strings.done, thread.resolvedBy),
          color: t.textMuted,
          variant: ReviewChipVariant.quiet,
          weight: FontWeight.w400,
        ),
      ReviewThreadState.acked => ReviewChip(
          label: strings.resolvedBy(strings.ack, thread.resolvedBy),
          color: t.textMuted,
          variant: ReviewChipVariant.quiet,
          weight: FontWeight.w400,
        ),
    };
  }

  Widget _anchorRow(BuildContext context, AppTokens t,
      {required bool dim}) {
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final pathStyle = TextStyle(
      color: dim ? t.textFaint : t.textMuted,
      fontSize: ReviewType.ident,
      height: 1,
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallback,
    );
    final stateChip = _stateChip(t);

    final qualifiers = <ReviewChip>[
      if (thread.anchorState == ReviewAnchorState.reanchored)
        ReviewChip(label: strings.moved, color: t.textMuted),
      // Muted, not amber: the strikethrough carries the death; amber
      // collided with the engine chip's hue on light themes.
      if (thread.anchorState == ReviewAnchorState.outdated)
        ReviewChip(
          label: strings.outdatedLastSeen(thread.lastSeenRound),
          color: t.textMuted,
        ),
    ];

    // Only a published, resolved thread can be reopened; a draft-only
    // card has no thread to reopen and an unresolved one nothing to undo.
    final canReopen = onReopen != null &&
        !thread.isDraftOnly &&
        thread.state != ReviewThreadState.unresolved;

    return LayoutBuilder(builder: (context, constraints) {
      // Measure everything that is NOT the path, then fit the path into
      // what remains. The line number and the chips are never the
      // casualty; directory prefix is.
      // The subject, in as few glyphs as it takes:
      //   line   lib/a.dart:12
      //   file   lib/a.dart
      //   review (nothing — the card IS the change, and the header
      //          directly above already says which review this is)
      //
      // Deliberately no word like "general" or "summary" in the empty
      // case. A label would be there to explain the absence of a label,
      // and the position already carries the meaning.
      final lineLabel =
          thread.scope == ReviewThreadScope.line ? ':${thread.line}' : '';
      var reserved = measureTextWidth(lineLabel, pathStyle, scaler) +
          AppSpacing.sm +
          stateChip.estimateWidth(scaler);
      for (final q in qualifiers) {
        reserved += AppSpacing.sm6 + q.estimateWidth(scaler);
      }
      final fittedPath = showPath
          ? middleEllipsize(
              thread.filePath,
              pathStyle,
              constraints.maxWidth - reserved,
              scaler,
            )
          : '';

      return Row(
        children: [
          Expanded(
            child: ReviewLine([
              if (showPath)
                TextSeg(fittedPath,
                    color: dim ? t.textFaint : t.textMuted, mono: true),
              TextSeg(lineLabel,
                  color: dim ? t.textFaint : t.textMuted, mono: true),
              for (final q in qualifiers) ...[
                const GapSeg(AppSpacing.sm6),
                ChipSeg(q),
              ],
            ]),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Measured from the SAME chip either way — the affordance
          // wraps it without touching its geometry.
          if (canReopen)
            _ReopenableChip(
              chip: stateChip,
              tooltip: strings.reopen,
              onTap: onReopen!,
            )
          else
            ReviewLine([ChipSeg(stateChip)]),
        ],
      );
    });
  }

  Widget _excerpt(BuildContext context, AppTokens t,
      {required bool dim}) {
    final geo = context.surfaceShader.geometry;
    final dead = thread.anchorState == ReviewAnchorState.outdated;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: t.bg0.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(geo.pillRadius),
      ),
      child: Row(
        children: [
          SizedBox(
            width: ReviewMetrics.lineNumWidth,
            child: Text(
              '${thread.line}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: t.textFaint,
                fontSize: ReviewType.ident,
                fontFamily: AppFonts.mono,
                fontFamilyFallback: AppFonts.monoFallback,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm10),
          Expanded(
            child: Text(
              thread.excerpt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: (dead || dim) ? t.textFaint : t.textNormal,
                fontSize: ReviewType.ident,
                fontFamily: AppFonts.mono,
                fontFamilyFallback: AppFonts.monoFallback,
                decoration: dead ? TextDecoration.lineThrough : null,
                decorationColor: t.textFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _verbRow(BuildContext context, AppTokens t) {
    return Row(
      children: [
        if (thread.isRobot && onPleaseFix != null) ...[
          ReviewVerbPill(
              label: strings.pleaseFix, emphasis: true, onTap: onPleaseFix!),
          const SizedBox(width: AppSpacing.sm6),
        ],
        if (!thread.isRobot && onDone != null) ...[
          ReviewVerbPill(label: strings.done, emphasis: true, onTap: onDone!),
          const SizedBox(width: AppSpacing.sm6),
        ],
        if (!thread.isRobot && onAck != null) ...[
          ReviewVerbPill(label: strings.ack, onTap: onAck!),
          const SizedBox(width: AppSpacing.sm6),
        ],
        if (onReply != null) ReviewVerbPill(label: strings.reply, onTap: onReply!),
      ],
    );
  }
}

/// The resolved state chip, offered as its own undo.
///
/// Colour is the affordance and the tooltip is the meaning; the LABEL is
/// deliberately fixed. Re-labelling on hover would change the chip's
/// measured width, and the anchor row fits the file path against exactly
/// that measurement — the path would reflow under the pointer.
class _ReopenableChip extends StatefulWidget {
  final ReviewChip chip;
  final String tooltip;
  final VoidCallback onTap;

  const _ReopenableChip({
    required this.chip,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_ReopenableChip> createState() => _ReopenableChipState();
}

class _ReopenableChipState extends State<_ReopenableChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = widget.chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: ReviewLine([
            // Outline at REST, not just on hover: a control the user
            // cannot see is a control they do not have, and hover-only
            // discovery means finding this by accident. The outline
            // variant deliberately shares `quiet`'s padding (the chips
            // keep one text rail), so the box appears without the row
            // re-measuring — the same reason the label never swaps.
            ChipSeg(ReviewChip(
              label: c.label,
              color: _hover ? t.accentBright : c.color,
              variant: ReviewChipVariant.outline,
              weight: c.weight,
              dot: c.dot,
            )),
          ]),
        ),
      ),
    );
  }
}

/// One comment inside a thread. Human comments are plain; robot
/// comments sit on a tinted panel with an `engine` tag; a draft among
/// published comments carries its own chip and hollow border.
class _ReviewCommentBlock extends StatelessWidget {
  final ReviewCommentView comment;
  final ReviewStrings strings;
  final bool showDraftChip;

  /// See [ReviewThreadCard.now].
  final DateTime now;

  /// Resolved-thread recede: all ink one contrast role down.
  final bool dim;
  const _ReviewCommentBlock({
    required this.comment,
    required this.strings,
    required this.showDraftChip,
    required this.now,
    required this.dim,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final geo = context.surfaceShader.geometry;
    final robot = comment.kind == ReviewAuthorKind.robot;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ReviewLine([
          TextSeg(
            robot ? comment.author : '@${comment.author}',
            color: dim ? t.textMuted : (robot ? t.textMuted : t.accentBright),
            weight: FontWeight.w700,
            mono: true,
          ),
          if (robot) ...[
            const GapSeg(AppSpacing.sm6),
            ChipSeg(ReviewChip(
              label: strings.engine,
              color: t.stateFragile,
              variant: ReviewChipVariant.fill,
            )),
          ],
          if (showDraftChip) ...[
            const GapSeg(AppSpacing.sm6),
            ChipSeg(ReviewChip(label: strings.draft, color: t.accentBright)),
          ],
          const GapSeg(AppSpacing.sm),
          // textMuted, not faint: 9px faint timestamps sat at the
          // legibility edge on light themes.
          //
          // Accent when the comment is new to this viewer. Unseen work
          // is a fact about the conversation, so it rides the timestamp
          // the comment already shows rather than a badge invented for
          // it — the eye finds a coloured "3h" without another chip
          // competing for the row, and nothing re-measures.
          TextSeg(
            relativeLabel(strings, now, comment.at),
            color: comment.isUnseen ? t.accentBright : t.textMuted,
            size: ReviewType.meta,
          ),
        ]),
        const SizedBox(height: AppSpacing.xs),
        _markdown(context, t),
      ],
    );

    if (robot) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: t.stateFragile.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(geo.pillRadius),
          border: Border(
            left: BorderSide(
                color: t.stateFragile.withValues(alpha: 0.4), width: 2),
          ),
        ),
        child: body,
      );
    }
    if (comment.isDraft) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(geo.pillRadius),
          border: Border.all(
              color: t.accentBright.withValues(alpha: 0.3),
              width: AppBorderWidth.thin),
        ),
        child: body,
      );
    }
    return body;
  }

  Widget _markdown(BuildContext context, AppTokens t) {
    final geo = context.surfaceShader.geometry;
    // proseMarkdown, never MarkdownBody: a comment body is written by
    // another machine, and the default image builder would fetch
    // whatever URL it names. See lib/ui/prose_markdown.dart.
    return proseMarkdown(
      data: comment.body,
      tokens: t,
      imageNotLoadedLabel: strings.imageNotLoaded,
      selectable: false,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: dim ? t.textMuted : t.textNormal,
          fontSize: ReviewType.body,
          height: 1.45,
          fontFamily: geo.typography,
          fontFamilyFallback: AppFonts.sansFallback,
        ),
        em: TextStyle(
          color: t.textNormal,
          fontStyle: FontStyle.italic,
          fontFamily: geo.typography,
          fontFamilyFallback: AppFonts.sansFallback,
        ),
        strong: TextStyle(
          color: t.textStrong,
          fontWeight: FontWeight.w700,
          fontFamily: geo.typography,
          fontFamilyFallback: AppFonts.sansFallback,
        ),
        // Neutral, not accent: inline code is syntax, not state.
        // Accent stays scarce so chips and the turn pill keep their
        // signal (color was carrying five jobs at once).
        code: TextStyle(
          color: dim ? t.textMuted : t.textStrong,
          fontFamily: AppFonts.mono,
          fontFamilyFallback: AppFonts.monoFallback,
          fontSize: ReviewType.ident,
          backgroundColor: t.bg0,
        ),
        codeblockDecoration: BoxDecoration(
          color: t.bg0,
          borderRadius: BorderRadius.circular(geo.pillRadius),
          border: Border.all(color: t.chromeBorder.withValues(alpha: 0.3)),
        ),
        codeblockPadding: const EdgeInsets.all(AppSpacing.sm),
        blockquote: TextStyle(
          color: t.textMuted,
          fontSize: ReviewType.body,
          fontStyle: FontStyle.italic,
          fontFamily: geo.typography,
          fontFamilyFallback: AppFonts.sansFallback,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
                color: t.chromeBorder.withValues(alpha: 0.5), width: 3),
          ),
        ),
        blockquotePadding:
            const EdgeInsets.only(left: AppSpacing.sm10, top: 2, bottom: 2),
        a: TextStyle(
          color: t.accentBright,
          decoration: TextDecoration.underline,
          fontFamily: geo.typography,
          fontFamilyFallback: AppFonts.sansFallback,
        ),
        listBullet: TextStyle(
          color: t.textNormal,
          fontSize: ReviewType.body,
          fontFamily: geo.typography,
          fontFamilyFallback: AppFonts.sansFallback,
        ),
      ),
    );
  }
}

/// Small turn-verb pill. Hover brightens; emphasis marks the verb the
/// turn most likely wants (Done on a human ask, Please fix on a robot
/// finding). Fixed height so verb rows never wobble.
