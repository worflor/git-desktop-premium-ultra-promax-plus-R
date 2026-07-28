// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_chrome.dart — the review surfaces' shared micro-vocabulary.
//
// Three laws, and every review element derives from them:
//
//  1. ONE TYPE SCALE. Every label is meta 9 / ident 10 / body 11.
//  2. ONE CHIP. Every badge-like element is the same 18px primitive.
//     The quiet variant keeps the same horizontal padding as the
//     painted ones, so the TEXT rail aligns whether or not a box is
//     drawn around it.
//  3. ONE LINE COMPOSER. Meta rows are never hand-built Rows of
//     center-aligned Texts — centering boxes does not align baselines
//     across font sizes and faces. [ReviewLine] renders a row as a
//     single paragraph: text segments share the paragraph baseline
//     natively, and chips join it as baseline-aligned inline spans.
//     Alignment is derived, not nudged.
//
// Path fitting is measured, not clipped: [middleEllipsize] preserves
// the filename and drops directory prefix instead of letting the tail
// (the line number, the part you trust) fall off the edge.

import 'package:flutter/material.dart';

import '../../ui/design_primitives.dart';
import '../../ui/material_surface.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';

/// The review type scale. Three sizes, no exceptions:
/// meta 9 (chips, timestamps, resolution notes), ident 10 (mono
/// identifiers, verbs, header facts), body 11 (comment prose).
abstract final class ReviewType {
  static const double meta = 9;
  static const double ident = 10;
  static const double body = 11;
}

/// Fixed metrics so rows of mixed elements align by construction.
abstract final class ReviewMetrics {
  /// Every chip is exactly this tall. 16, not 18: a baseline-locked
  /// box next to 10px ident text hangs asymmetrically (3px above the
  /// ascenders, 4.7px below the baseline at 18 — measured in the 8x
  /// probe, and exactly what reads as "the chip is sagging"). At 16
  /// the border sits symmetric around the text's line box AND the
  /// label baseline still lands on the text baseline — the one height
  /// where both constraints nearly coincide.
  static const double chipHeight = 16;

  /// The meta-row line box every chip centers within.
  static const double lineHeight = 18;

  /// Every verb pill is exactly this tall.
  static const double verbHeight = 22;

  /// Chip horizontal padding — shared by ALL variants (painted or not)
  /// so chip text always sits on the same rail.
  static const double chipPadX = AppSpacing.sm6;

  /// The right-aligned line-number gutter in excerpts — fixed so code
  /// starts at the same x on every card in a pane.
  static const double lineNumWidth = 32;
}

enum ReviewChipVariant {
  /// No box painted — for states that should read as a fact, not a
  /// badge ("unresolved", "done · jun", "waiting on mira"). Same
  /// geometry as the painted variants.
  quiet,

  /// Hairline border, no fill — secondary qualifiers ("outdated",
  /// "draft", the round number).
  outline,

  /// Tinted fill, no border — provenance tags ("engine").
  fill,

  /// Fill + border + bold — the one loud element ("your turn").
  accent,
}

class ReviewChip extends StatefulWidget {
  final String label;
  final Color color;
  final ReviewChipVariant variant;

  /// Leading 5px status dot (the quiet variant's attention mark).
  final bool dot;
  final bool mono;

  /// Overrides the variant's default text weight
  /// (quiet/accent → w700, outline/fill → w600).
  final FontWeight? weight;

  /// Makes the chip pressable. A chip is the right home for this when
  /// the action changes the very state the chip reports — the turn
  /// indicator and its hand-off verbs, say. It stays a [ReviewChip] so
  /// it still travels inside a [ChipSeg] and keeps the line's baseline;
  /// nothing about the resting appearance changes, so a pressable chip
  /// never resizes the row it sits in.
  final VoidCallback? onTap;

  const ReviewChip({
    super.key,
    required this.label,
    required this.color,
    this.variant = ReviewChipVariant.outline,
    this.dot = false,
    this.mono = false,
    this.weight,
    this.onTap,
  });

  @override
  State<ReviewChip> createState() => _ReviewChipState();

  FontWeight get _weight =>
      weight ??
      (variant == ReviewChipVariant.accent ||
              variant == ReviewChipVariant.quiet
          ? FontWeight.w700
          : FontWeight.w600);

  /// Estimated box width, for layout math that must reserve chip space
  /// before build (path fitting). Mirrors [build]'s layout exactly.
  double estimateWidth(TextScaler scaler) {
    final text = measureTextWidth(
      label,
      TextStyle(
        fontSize: ReviewType.meta,
        height: 1,
        fontWeight: _weight,
        letterSpacing: 0.2,
        fontFamily: mono ? AppFonts.mono : null,
        fontFamilyFallback: mono ? AppFonts.monoFallback : null,
      ),
      scaler,
    );
    final dotW = dot ? 5 + AppSpacing.xs : 0;
    return text + dotW + 2 * ReviewMetrics.chipPadX;
  }

}

class _ReviewChipState extends State<ReviewChip> {
  bool _hover = false;

  /// Hover styling applies only to a chip that can actually be pressed.
  bool get _lit => _hover && widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    if (widget.onTap == null) return body;
    // Hover feedback matching ReviewVerbPill's: a pressable thing that
    // does not answer the pointer reads as decoration. DECORATION ONLY —
    // height and padding are untouched, so hovering never resizes the
    // row and never moves the control the pointer is travelling toward.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: body,
      ),
    );
  }

  Widget _body(BuildContext context) {
    final geo = context.surfaceShader.geometry;
    final text = Text(
      widget.label,
      style: TextStyle(
        color: widget.color,
        fontSize: ReviewType.meta,
        height: 1,
        fontWeight: widget._weight,
        letterSpacing: 0.2,
        fontFamily: widget.mono ? AppFonts.mono : null,
        fontFamilyFallback: widget.mono ? AppFonts.monoFallback : null,
      ),
    );

    final child = widget.dot
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.xs),
              text,
            ],
          )
        : text;

    // Hover only lifts the alphas; the geometry below is identical in
    // both states, which is what keeps a hover from resizing the row.
    final decoration = switch (widget.variant) {
      ReviewChipVariant.quiet => _lit
          ? BoxDecoration(
              color: widget.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(geo.badgeRadius),
            )
          : null,
      ReviewChipVariant.outline => BoxDecoration(
          borderRadius: BorderRadius.circular(geo.badgeRadius),
          border: Border.all(
              color: widget.color.withValues(alpha: _lit ? 0.75 : 0.45),
              width: AppBorderWidth.hairline),
        ),
      ReviewChipVariant.fill => BoxDecoration(
          color: widget.color.withValues(alpha: _lit ? 0.22 : 0.14),
          borderRadius: BorderRadius.circular(geo.badgeRadius),
        ),
      ReviewChipVariant.accent => BoxDecoration(
          color: widget.color.withValues(alpha: _lit ? 0.22 : 0.14),
          borderRadius: BorderRadius.circular(geo.badgeRadius),
          border: Border.all(
              color: widget.color.withValues(alpha: _lit ? 0.7 : 0.4),
              width: AppBorderWidth.hairline),
        ),
    };

    // NOT `alignment:` on the container — a Container with alignment
    // expands to its max width constraint, and inside a paragraph
    // (WidgetSpan) that constraint is the whole line: the chip would
    // stretch across it (caught in preview). Align with widthFactor: 1
    // centers vertically while shrink-wrapping horizontally.
    // ANIMATED ONLY WHEN PRESSABLE. Every chip in the app is a
    // ReviewChip and most are pure status; giving all of them an
    // implicit decoration animation means a static chip interpolates on
    // any token change, which is motion nobody asked for plus a ticker
    // per chip in dense lists.
    if (widget.onTap == null) {
      return Container(
        height: ReviewMetrics.chipHeight,
        padding:
            const EdgeInsets.symmetric(horizontal: ReviewMetrics.chipPadX),
        decoration: decoration,
        child: Align(
          alignment: Alignment.center,
          widthFactor: 1,
          child: child,
        ),
      );
    }
    return AnimatedContainer(
      duration: context.motionRead(AppMotion.snap),
      curve: AppMotion.snapCurve,
      height: ReviewMetrics.chipHeight,
      padding:
          const EdgeInsets.symmetric(horizontal: ReviewMetrics.chipPadX),
      decoration: decoration,
      child: Align(
        alignment: Alignment.center,
        widthFactor: 1,
        child: child,
      ),
    );
  }
}

// ─── The line composer ────────────────────────────────────────────────

/// One piece of a [ReviewLine].
sealed class ReviewSeg {
  const ReviewSeg();
}

class TextSeg extends ReviewSeg {
  final String text;
  final double size;
  final Color color;
  final FontWeight weight;
  final bool mono;
  const TextSeg(
    this.text, {
    required this.color,
    this.size = ReviewType.ident,
    this.weight = FontWeight.w400,
    this.mono = false,
  });

  TextStyle get style => TextStyle(
        color: color,
        fontSize: size,
        height: 1,
        fontWeight: weight,
        fontFamily: mono ? AppFonts.mono : null,
        fontFamilyFallback: mono ? AppFonts.monoFallback : null,
      );
}

class ChipSeg extends ReviewSeg {
  final ReviewChip chip;
  const ChipSeg(this.chip);
}

class GapSeg extends ReviewSeg {
  final double width;
  const GapSeg(this.width);
}

/// Renders a meta row as ONE paragraph. Text segments of any size or
/// face share the paragraph's baseline natively; chips are inline
/// placeholders aligned to that same baseline (their inner label's
/// baseline is what lands on it, via the render tree's baseline
/// propagation). This is what makes "path · chip · time" rows align
/// exactly, on every theme, with zero per-site tuning.
class ReviewLine extends StatelessWidget {
  final List<ReviewSeg> segs;
  const ReviewLine(this.segs, {super.key});

  @override
  Widget build(BuildContext context) {
    // A paragraph containing ONLY placeholders gets its line metrics
    // from the ambient text style, not the placeholder — measured 4px
    // of baseline sag on chip-only lines (see the alignment law test).
    // Chips are exactly line-height, so a chips-only line needs no
    // paragraph at all: top-aligned chips sit flush, and their labels
    // land on the same 11.1px baseline a mixed paragraph produces.
    if (segs.every((s) => s is! TextSeg)) {
      // Chips centered in the line box — the same (line-chip)/2 offset
      // a mixed paragraph produces once Align centers it, so chip-only
      // and mixed lines land labels on one baseline by shared formula.
      return SizedBox(
        height: ReviewMetrics.lineHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final s in segs)
              switch (s) {
                ChipSeg() => s.chip,
                GapSeg() => SizedBox(width: s.width),
                TextSeg() => const SizedBox.shrink(), // unreachable
              },
          ],
        ),
      );
    }
    return SizedBox(
      height: ReviewMetrics.lineHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              for (final s in segs)
                switch (s) {
                  TextSeg() => TextSpan(text: s.text, style: s.style),
                  ChipSeg() => WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: s.chip,
                    ),
                  GapSeg() => WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: SizedBox(width: s.width),
                    ),
                },
            ],
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }
}

// ─── Measured fitting ─────────────────────────────────────────────────

/// Exact painted width of [text] in [style] at [scaler].
double measureTextWidth(String text, TextStyle style, TextScaler scaler) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

/// Shorten [path] to fit [maxWidth], dropping directory prefix from the
/// FRONT and keeping the filename whole: `lib/backend/git.dart` →
/// `…end/git.dart`. The tail is the trustworthy part of a path; the
/// prefix is the expendable part. Falls back to the bare filename when
/// even that barely fits (the paragraph clips as a last resort).
String middleEllipsize(
    String path, TextStyle style, double maxWidth, TextScaler scaler) {
  if (maxWidth <= 0) return path;
  if (measureTextWidth(path, style, scaler) <= maxWidth) return path;
  const ell = '…';
  // Binary search the longest kept SUFFIX such that '…suffix' fits.
  var lo = 0, hi = path.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2; // candidate suffix start index
    final fits =
        measureTextWidth(ell + path.substring(mid), style, scaler) <=
            maxWidth;
    if (fits) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  return ell + path.substring(lo.clamp(0, path.length));
}

/// The one review action pill: quiet chrome, snap-motion hover, an
/// emphasis weight for the row's primary verb. Every clickable verb on
/// a review surface is THIS widget — cards, publish bar, composers —
/// so hover behaviour and hit-height can never drift apart.
class ReviewVerbPill extends StatefulWidget {
  final String label;
  final bool emphasis;
  final VoidCallback onTap;
  const ReviewVerbPill({
    super.key,
    required this.label,
    required this.onTap,
    this.emphasis = false,
  });

  @override
  State<ReviewVerbPill> createState() => _ReviewVerbPillState();
}

class _ReviewVerbPillState extends State<ReviewVerbPill> {
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
          // widthFactor: 1 rather than the container's own `alignment`.
          // A Container WITH alignment expands to fill whatever it is
          // given, so this pill hugged its label inside a Row (which
          // hands out unbounded width) and stretched to full width
          // inside a Wrap — the same control, two sizes, depending on
          // who held it. Sizing to the label is the invariant.
          child: Align(
            widthFactor: 1,
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
      ),
    );
  }
}

/// The other direction of the manually adjustable attention set: put
/// the change into someone's hands without having anything to publish.
///
/// One quiet verb, then bare names. The names are controls and the verb
/// is not, which is also why no locale has to inflect a person's name
/// into a sentence — a hand-off to "mira" reads the same in every
/// language the app speaks.
///
/// Renders nothing at all when there is nobody to hand to: an empty
/// conversation has no hand-off, and a stub control that greys out
/// would just be a promise the record cannot keep.
class ReviewHandOff extends StatelessWidget {
  final String label;
  final List<String> to;
  final void Function(String display) onHandTo;

  const ReviewHandOff({
    super.key,
    required this.label,
    required this.to,
    required this.onHandTo,
  });

  @override
  Widget build(BuildContext context) {
    if (to.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        SizedBox(
          height: ReviewMetrics.verbHeight,
          // widthFactor: 1 — a bare Center fills the width it is
          // offered, which inside a Wrap means the verb claims the
          // whole run and the names it introduces fall to the next
          // line, reading as two unrelated groups.
          child: Align(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                color: t.textFaint,
                fontSize: ReviewType.meta,
                height: 1,
              ),
            ),
          ),
        ),
        for (final who in to)
          ReviewVerbPill(label: who, onTap: () => onHandTo(who)),
      ],
    );
  }
}
