import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'animated_icons.dart';
import 'mosaic_seam.dart';
import 'tokens.dart';

/// One tappable half of a [SplitPillButton]. Each segment carries its own
/// resting + hover colour so a pill can teach two distinct intents at once —
/// accent for the affirmative action, a caution hue for a reset. The colour a
/// segment teaches shows in its text and in its hover wash.
class SplitPillSegment {
  final String label;

  /// Text colour at rest.
  final Color restColor;

  /// Text + hover-wash colour on hover (and while loading) — the accent this
  /// half teaches.
  final Color hoverColor;

  /// Heavier weight reads as the primary action.
  final bool bold;

  /// Swaps the label for a spinning sync glyph while this half's work runs.
  final bool loading;

  /// Optional hover tooltip. Keep the label terse for width and spell out the
  /// full intent here.
  final String? tooltip;

  final VoidCallback onTap;

  const SplitPillSegment({
    required this.label,
    required this.restColor,
    required this.hoverColor,
    required this.onTap,
    this.bold = false,
    this.loading = false,
    this.tooltip,
  });
}

/// A pill built from the app's shattered-mosaic language (see the right-click
/// menu's chip rail): one solid inset [AppTokens.surface2] surface split into
/// equal cells by a jagged, per-mount crack, each cell lighting up with its
/// own accent wash on hover. Reads as a single control whose halves stay
/// independently tappable. When [enabled] is false every half goes inert and
/// dims — a running action owns the whole pill until it finishes.
class SplitPillButton extends StatefulWidget {
  final List<SplitPillSegment> segments;
  final bool enabled;
  final double fontSize;

  const SplitPillButton({
    super.key,
    required this.segments,
    this.enabled = true,
    this.fontSize = 10.5,
  });

  @override
  State<SplitPillButton> createState() => _SplitPillButtonState();
}

class _SplitPillButtonState extends State<SplitPillButton> {
  static const double _hPad = 14;
  static const double _vPad = 7;

  late List<MosaicSeam> _seams;

  @override
  void initState() {
    super.initState();
    _seams = _buildSeams(widget.segments.length);
  }

  @override
  void didUpdateWidget(SplitPillButton old) {
    super.didUpdateWidget(old);
    // Seam count tracks the divisions between cells; only reshuffle when the
    // number of segments actually changes (label/loading swaps must not).
    if (old.segments.length != widget.segments.length) {
      _seams = _buildSeams(widget.segments.length);
    }
  }

  List<MosaicSeam> _buildSeams(int n) {
    final rng = math.Random();
    return List.generate(math.max(0, n - 1), (_) => generateMosaicSeam(rng));
  }

  /// Cells are sized to the widest label so the pill is symmetric and its
  /// width never jumps when a half swaps its label for the loading spinner.
  Size _measure(String text, TextStyle style, TextScaler scaler) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    return tp.size;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scaler = MediaQuery.textScalerOf(context);
    final n = widget.segments.length;

    var maxW = 0.0;
    var maxH = 0.0;
    for (final seg in widget.segments) {
      final s = _measure(
        seg.label,
        TextStyle(
          fontSize: widget.fontSize,
          fontWeight: seg.bold ? FontWeight.w700 : FontWeight.w600,
        ),
        scaler,
      );
      maxW = math.max(maxW, s.width);
      maxH = math.max(maxH, s.height);
    }

    final cellW = maxW + _hPad * 2;
    final railW = cellW * n;
    final railH = maxH + _vPad * 2;
    final jitter = cellW * kMosaicJitterFrac;

    // Theme-responsive corner: gently rounded on soft themes, square on
    // sharp/pixelated ones (Crafty/Kirby resolve pillRadius to 0), matching
    // every other button in the app rather than staying a fixed stadium.
    final radius = context.surfaceShader.geometry.pillRadius;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(radius),
      ),
      // Border rides on TOP of the clipped cells (foreground, not part of the
      // fill decoration) so a hovered half's wash meets the rounded edge with
      // no background hairline showing through between the wash and the stroke.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.16)),
      ),
      child: SizedBox(
        width: railW,
        height: railH,
        child: Stack(
          children: [
            for (var i = 0; i < n; i++) _cell(i, n, cellW, jitter, railW),
            if (_seams.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: ShatteredSeamPainter(
                      cellCount: n,
                      seams: _seams,
                      baseColor: t.chromeBorder,
                      baseAlpha: 0.34,
                      baseWidth: 0.7,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(int i, int n, double cellW, double jitter, double railW) {
    final isFirst = i == 0;
    final isLast = i == n - 1;
    final left = isFirst ? 0.0 : i * cellW - jitter;
    final right = isLast ? railW : (i + 1) * cellW + jitter;
    final leftNom = isFirst ? 0.0 : jitter;
    final rightNom = isFirst ? cellW : jitter + cellW;
    final boxW = right - left;
    return Positioned(
      left: left,
      width: boxW,
      top: 0,
      bottom: 0,
      child: ClipPath(
        clipper: MosaicCellClipper(
          leftNominal: leftNom,
          rightNominal: rightNom,
          jitter: jitter,
          leftSeam: i > 0 ? _seams[i - 1] : null,
          rightSeam: i < n - 1 ? _seams[i] : null,
        ),
        child: _SplitMosaicCell(
          segment: widget.segments[i],
          enabled: widget.enabled,
          fontSize: widget.fontSize,
          // Center content in the NOMINAL cell, not the ±jitter-extended box,
          // so first/last labels don't drift toward the seam.
          padLeft: leftNom,
          padRight: boxW - rightNom,
        ),
      ),
    );
  }
}

class _SplitMosaicCell extends StatefulWidget {
  final SplitPillSegment segment;
  final bool enabled;
  final double fontSize;
  final double padLeft;
  final double padRight;

  const _SplitMosaicCell({
    required this.segment,
    required this.enabled,
    required this.fontSize,
    required this.padLeft,
    required this.padRight,
  });

  @override
  State<_SplitMosaicCell> createState() => _SplitMosaicCellState();
}

class _SplitMosaicCellState extends State<_SplitMosaicCell> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final seg = widget.segment;
    final interactive = widget.enabled;
    final active = _hov && interactive;

    final Color textColor;
    if (!interactive && !seg.loading) {
      textColor = t.textFaint;
    } else if (active || seg.loading) {
      textColor = seg.hoverColor;
    } else {
      textColor = seg.restColor;
    }

    // Hover wash borrows the segment's own accent at low alpha — the crack
    // clips it, so a hovered half lights up right to the jagged seam.
    final bg =
        active ? seg.hoverColor.withValues(alpha: 0.08) : Colors.transparent;

    Widget content = ColoredBox(
      color: bg,
      child: Padding(
        padding: EdgeInsets.only(left: widget.padLeft, right: widget.padRight),
        child: Center(
          child: seg.loading
              ? AnimatedSyncIcon(
                  state: IconAnimState.loading,
                  color: textColor,
                  size: 12,
                )
              : Text(
                  seg.label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: widget.fontSize,
                    fontWeight: seg.bold ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
        ),
      ),
    );

    if (seg.tooltip != null) {
      content = Tooltip(message: seg.tooltip!, child: content);
    }

    return MouseRegion(
      cursor:
          interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: interactive ? seg.onTap : null,
        behavior: HitTestBehavior.opaque,
        child: content,
      ),
    );
  }
}
