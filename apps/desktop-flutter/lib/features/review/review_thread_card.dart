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
import '../../ui/motion.dart';
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

  const ReviewThreadCard({
    super.key,
    required this.thread,
    this.strings = const ReviewStrings(),
    this.showPath = true,
    this.onDone,
    this.onAck,
    this.onReply,
    this.onPleaseFix,
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
              _excerpt(context, t, dim: dim),
              const SizedBox(height: AppSpacing.sm),
              for (final c in thread.comments) ...[
                _ReviewCommentBlock(
                  comment: c,
                  strings: strings,
                  // In a draft-only thread the card already says draft;
                  // the per-comment chip marks the unpublished one only
                  // when it sits among published comments.
                  showDraftChip: c.isDraft && !draftOnly,
                  dim: dim,
                ),
                if (c != thread.comments.last)
                  const SizedBox(height: AppSpacing.sm),
              ],
              if (unresolved && !draftOnly) ...[
                const SizedBox(height: AppSpacing.sm10),
                _verbRow(context, t),
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

    return LayoutBuilder(builder: (context, constraints) {
      // Measure everything that is NOT the path, then fit the path into
      // what remains. The line number and the chips are never the
      // casualty; directory prefix is.
      final lineLabel = ':${thread.line}';
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
          _VerbPill(
              label: strings.pleaseFix, emphasis: true, onTap: onPleaseFix!),
          const SizedBox(width: AppSpacing.sm6),
        ],
        if (!thread.isRobot && onDone != null) ...[
          _VerbPill(label: strings.done, emphasis: true, onTap: onDone!),
          const SizedBox(width: AppSpacing.sm6),
        ],
        if (!thread.isRobot && onAck != null) ...[
          _VerbPill(label: strings.ack, onTap: onAck!),
          const SizedBox(width: AppSpacing.sm6),
        ],
        if (onReply != null) _VerbPill(label: strings.reply, onTap: onReply!),
      ],
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

  /// Resolved-thread recede: all ink one contrast role down.
  final bool dim;
  const _ReviewCommentBlock({
    required this.comment,
    required this.strings,
    required this.showDraftChip,
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
          TextSeg(
            comment.when,
            color: t.textMuted,
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
    return MarkdownBody(
      data: comment.body,
      selectable: false,
      shrinkWrap: true,
      fitContent: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: dim ? t.textMuted : t.textNormal,
          fontSize: ReviewType.body,
          height: 1.45,
          fontFamily: geo.typography,
        ),
        em: TextStyle(
          color: t.textNormal,
          fontStyle: FontStyle.italic,
          fontFamily: geo.typography,
        ),
        strong: TextStyle(
          color: t.textStrong,
          fontWeight: FontWeight.w700,
          fontFamily: geo.typography,
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
        ),
        listBullet: TextStyle(
          color: t.textNormal,
          fontSize: ReviewType.body,
          fontFamily: geo.typography,
        ),
      ),
    );
  }
}

/// Small turn-verb pill. Hover brightens; emphasis marks the verb the
/// turn most likely wants (Done on a human ask, Please fix on a robot
/// finding). Fixed height so verb rows never wobble.
class _VerbPill extends StatefulWidget {
  final String label;
  final bool emphasis;
  final VoidCallback onTap;
  const _VerbPill({
    required this.label,
    required this.onTap,
    this.emphasis = false,
  });

  @override
  State<_VerbPill> createState() => _VerbPillState();
}

class _VerbPillState extends State<_VerbPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final geo = context.surfaceShader.geometry;
    final base = widget.emphasis ? t.textStrong : t.textMuted;
    final color = _hover ? t.accentBright : base;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motionRead(AppMotion.snap),
          curve: AppMotion.snapCurve,
          height: ReviewMetrics.verbHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover
                ? t.accentBright.withValues(alpha: 0.10)
                : t.bg0.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(geo.pillRadius),
            border: Border.all(
              color: _hover
                  ? t.accentBright.withValues(alpha: 0.45)
                  : t.chromeBorderSubtle,
              width: AppBorderWidth.hairline,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: color,
              fontSize: ReviewType.ident,
              height: 1,
              fontWeight:
                  widget.emphasis ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
