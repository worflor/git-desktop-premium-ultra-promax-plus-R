import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/tokens.dart';
import 'commit_tagger.dart';

/// Renders a single auto-derived commit tag as a compact pill sitting
/// inline with the existing git-tag pills on a commit row.
/// Color derivation is deterministic from the label string — same
/// label always paints the same hue across the app. Saturation and
/// lightness are pulled from the theme tokens so each theme auto-
/// paints its own palette; no per-label color map anywhere.
/// Kind only modulates emphasis (saturation + alpha weight), not the
/// hue itself. A `type` tag reads a touch brighter than an axis tag
/// to reinforce the "this is the author's own word" / "this is a
/// repo-relative observation" distinction.
class CommitTagPill extends StatelessWidget {
  final CommitTag tag;
  final AppTokens tokens;

  const CommitTagPill({
    super.key,
    required this.tag,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final hue = _labelHue(tag.label);
    final emphasis = _kindEmphasis(tag.kind);
    // Compose the pill color by rotating the theme's accent into the
    // hash-derived hue, keeping the theme's own saturation/lightness.
    // This guarantees: (a) the pill never clashes with the theme,
    // (b) the same label is visually stable across the app.
    final hsl = HSLColor.fromColor(tokens.accentBright);
    final pillColor = hsl
        .withHue(hue)
        .withSaturation((hsl.saturation * emphasis.saturation).clamp(0.0, 1.0))
        .toColor();

    final isBorrowed = tag.kind == CommitTagKind.borrowed;
    // Borrowed pills scale their visual weight by sqrt(confidence) so
    // weak signals stay visible as faint context and strong ones
    // reach full weight. Non-borrowed pills always use confidence=1.
    final cMul = isBorrowed
        ? math.sqrt(tag.confidence.clamp(0.0, 1.0))
        : 1.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: pillColor.withValues(alpha: emphasis.bgAlpha * cMul),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: pillColor.withValues(alpha: emphasis.borderAlpha * cMul),
          width: isBorrowed ? 0.6 : 0.8,
        ),
      ),
      child: Text(
        // Italic + lower-saturation marks borrowed labels as
        // neighborhood-inferred rather than subject-derived.
        tag.label.toLowerCase(),
        style: TextStyle(
          color: pillColor.withValues(alpha: emphasis.textAlpha * cMul),
          fontSize: 9,
          fontWeight: emphasis.weight,
          fontStyle: isBorrowed ? FontStyle.italic : FontStyle.normal,
          fontFamily: 'JetBrainsMono',
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Deterministic hash → hue mapping. Uses the full 0..360 range so
/// different labels spread across the color wheel. The transform is
/// stable — same label across sessions, themes, and repos produces
/// the same hue (its theme-rotated tone will shift with the theme,
/// but its slot on the wheel is fixed).
double _labelHue(String label) {
  // FNV-1a 32-bit — fast, good enough spread for short strings.
  var hash = 0x811c9dc5;
  for (final codeUnit in label.toLowerCase().codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return (hash % 360).toDouble();
}

/// Per-kind visual emphasis. Lower saturation / alpha for axis tags
/// so the author's own type words get visual priority; axis tags
/// read as "context" not "claim". All numbers are ratios that
/// multiply into the theme's own chroma — no absolute colors.
_PillEmphasis _kindEmphasis(CommitTagKind kind) {
  switch (kind) {
    // Identity tier — highest visual weight. The author told you (or
    // the directory tree told you) what this is.
    case CommitTagKind.type:
      return const _PillEmphasis(
        saturation: 1.0,
        bgAlpha: 0.14,
        borderAlpha: 0.50,
        textAlpha: 1.0,
        weight: FontWeight.w700,
      );
    case CommitTagKind.scope:
    case CommitTagKind.chain:
      return const _PillEmphasis(
        saturation: 0.9,
        bgAlpha: 0.10,
        borderAlpha: 0.40,
        textAlpha: 0.95,
        weight: FontWeight.w600,
      );
    case CommitTagKind.cluster:
      return const _PillEmphasis(
        saturation: 0.85,
        bgAlpha: 0.10,
        borderAlpha: 0.38,
        textAlpha: 0.92,
        weight: FontWeight.w600,
      );
    // Direction tier — universal phenomena. Slightly muted to defer
    // to identity but still informative.
    case CommitTagKind.cleanup:
    case CommitTagKind.growth:
    case CommitTagKind.hub:
      return const _PillEmphasis(
        saturation: 0.8,
        bgAlpha: 0.08,
        borderAlpha: 0.34,
        textAlpha: 0.90,
        weight: FontWeight.w600,
      );
    case CommitTagKind.echo:
      return const _PillEmphasis(
        saturation: 0.6,
        bgAlpha: 0.06,
        borderAlpha: 0.26,
        textAlpha: 0.82,
        weight: FontWeight.w500,
      );
    // Truth-teller — drift sits at warning-level visual weight (still
    // not loud — same hash-derived hue, slightly more opacity than
    // axis tags so it reads as a NOTICE not a complaint).
    case CommitTagKind.drift:
      return const _PillEmphasis(
        saturation: 0.7,
        bgAlpha: 0.10,
        borderAlpha: 0.40,
        textAlpha: 0.92,
        weight: FontWeight.w600,
      );
    // Distribution-extreme tier — quieter than identity, contextual.
    case CommitTagKind.axisHuge:
    case CommitTagKind.axisFocused:
      return const _PillEmphasis(
        saturation: 0.7,
        bgAlpha: 0.07,
        borderAlpha: 0.28,
        textAlpha: 0.85,
        weight: FontWeight.w500,
      );
    case CommitTagKind.axisTiny:
    case CommitTagKind.axisSprawl:
      return const _PillEmphasis(
        saturation: 0.5,
        bgAlpha: 0.05,
        borderAlpha: 0.22,
        textAlpha: 0.75,
        weight: FontWeight.w500,
      );
    case CommitTagKind.merge:
    case CommitTagKind.rename:
      // Both are topology-level observations; share emphasis so they
      // read at the same weight when a commit does both.
      return const _PillEmphasis(
        saturation: 0.6,
        bgAlpha: 0.08,
        borderAlpha: 0.32,
        textAlpha: 0.85,
        weight: FontWeight.w600,
      );
    // Branch-trajectory tier — Engram-fit observation. Reads like a
    // direction tag (same saturation) but at the structural/merge
    // weight band so it sits naturally next to `merge` in the pill row.
    case CommitTagKind.converging:
    case CommitTagKind.diverging:
    case CommitTagKind.unusualCadence:
      return const _PillEmphasis(
        saturation: 0.7,
        bgAlpha: 0.08,
        borderAlpha: 0.32,
        textAlpha: 0.88,
        weight: FontWeight.w600,
      );
    // Borrowed — lowest saturation + alpha of any kind so the pill
    // reads as inference rather than claim.
    case CommitTagKind.borrowed:
      return const _PillEmphasis(
        saturation: 0.55,
        bgAlpha: 0.05,
        borderAlpha: 0.22,
        textAlpha: 0.78,
        weight: FontWeight.w500,
      );
  }
}

class _PillEmphasis {
  final double saturation;
  final double bgAlpha;
  final double borderAlpha;
  final double textAlpha;
  final FontWeight weight;
  const _PillEmphasis({
    required this.saturation,
    required this.bgAlpha,
    required this.borderAlpha,
    required this.textAlpha,
    required this.weight,
  });
}
