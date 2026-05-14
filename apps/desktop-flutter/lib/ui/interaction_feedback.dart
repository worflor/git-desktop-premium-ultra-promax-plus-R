import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'motion.dart';
import 'tokens.dart';

/// Wrap any tap target in this to get the active theme's `ThemeInteraction`
/// rendered on click. Themes declaring `ThemeInteraction.none` (only
/// petrichor, by design — its restraint mandate) get a transparent
/// pass-through — zero overhead. Every other theme paints its per-tap
/// effect: caustic ripples, etch stamps, warp rings, vibration specks,
/// chalk dust, ink splats, block-break shards, gloss streaks.
///
/// Each instance owns a single reusable [AnimationController]; retriggers
/// reset + re-forward instead of allocating. The feedback layer is above
/// the child in a `Stack`, clipped to the provided [borderRadius] so
/// effects respect rounded corners, and wrapped in `IgnorePointer` so it
/// never steals hit tests from [child].
class InteractionFeedback extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final ValueChanged<bool>? onHoverChanged;
  /// Fires `true` on `onTapDown`, `false` on `onTapUp`/`onTapCancel`.
  /// Lets a parent (e.g. `ChromeButton`) drive press-state visuals
  /// without nesting its own gesture detector inside this one — since
  /// nested opaque detectors would compete for the tap and one would
  /// silently lose to the other.
  final ValueChanged<bool>? onPressedChanged;
  /// Right-click handler. Receives the global tap position so callers
  /// can position popovers / context menus. Without this, list rows
  /// that need right-click support would have to nest their own
  /// gesture detector and compete with this one.
  final void Function(Offset globalPosition)? onSecondaryTapDown;
  final MouseCursor cursor;
  final HitTestBehavior behavior;

  const InteractionFeedback({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius,
    this.onHoverChanged,
    this.onPressedChanged,
    this.onSecondaryTapDown,
    this.cursor = SystemMouseCursors.click,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<InteractionFeedback> createState() => _InteractionFeedbackState();
}

class _InteractionFeedbackState extends State<InteractionFeedback>
    with SingleTickerProviderStateMixin {
  // Initial duration is overwritten in `_fire()` before the controller
  // ever runs (`_ac.duration = context.motionRead(_durationFor(mode))`).
  // We use the longest possible mode duration so a forgotten fire-without-
  // reset has a sane upper bound rather than the framework default 0.
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  Offset _origin = Offset.zero;

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  void _fire(ThemeInteraction mode, Offset local) {
    if (mode == ThemeInteraction.none || widget.onTap == null) return;
    // Reduce motion: skip the feedback flash entirely. Keep the click
    // responsive; drop the decoration.
    if (context.reduceMotionRead) return;
    _origin = local;
    // Scale the per-mode authored duration through the user's
    // motionRate preference so users who picked "faster motion"
    // also get faster feedback flashes (and slower for the inverse).
    // Without this scaling, every other timed animation in the app
    // honored the rate but click feedback didn't.
    _ac.duration = context.motionRead(_durationFor(mode));
    _ac
      ..stop()
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final shader = context.surfaceShader;
    // Reduce-motion pref short-circuits the feedback painter entirely —
    // we stay a pure pass-through so the user's accessibility preference
    // is honored and the painter never allocates.
    final mode = context.reduceMotion
        ? ThemeInteraction.none
        : shader.interaction;
    final t = context.tokens;

    final hasPressCallback = widget.onPressedChanged != null;
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : widget.cursor,
      onEnter: widget.onHoverChanged == null
          ? null
          : (_) => widget.onHoverChanged!(true),
      onExit: widget.onHoverChanged == null
          ? null
          : (_) {
              widget.onHoverChanged!(false);
              // Mouse leaving while pressed should unstick the press
              // visual. Without this, dragging the cursor off mid-press
              // leaves the parent stuck in `_pressed = true`.
              if (hasPressCallback) widget.onPressedChanged!(false);
            },
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: mode == ThemeInteraction.none && !hasPressCallback
            ? null
            : (details) {
                if (mode != ThemeInteraction.none) {
                  _fire(mode, details.localPosition);
                }
                if (hasPressCallback) widget.onPressedChanged!(true);
              },
        onTapUp: hasPressCallback
            ? (_) => widget.onPressedChanged!(false)
            : null,
        onTapCancel: hasPressCallback
            ? () => widget.onPressedChanged!(false)
            : null,
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTapDown == null
            ? null
            : (d) => widget.onSecondaryTapDown!(d.globalPosition),
        child: Stack(
          children: [
            widget.child,
            if (mode != ThemeInteraction.none)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius:
                        widget.borderRadius ?? BorderRadius.zero,
                    // Use SizedBox.expand so CustomPaint takes the full
                    // constraints from the Positioned.fill above rather
                    // than trying to adopt a size captured from the
                    // outer RenderBox at tap time (illegal — the two
                    // aren't in a direct ancestor/child relationship,
                    // so Flutter rejects debugAdoptSize every frame).
                    child: AnimatedBuilder(
                      animation: _ac,
                      builder: (context, _) => _ac.value == 0
                          ? const SizedBox.shrink()
                          : SizedBox.expand(
                              child: CustomPaint(
                                painter: _feedbackPainter(
                                  mode: mode,
                                  accent: t.accentBright,
                                  origin: _origin,
                                  progress: _ac.value,
                                  luminescence: shader.luminescence,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tiny stateful wrapper that tracks hover and rebuilds with the new
/// state. For places where a tap target needs hover-driven visual change
/// (e.g., text link brightening on hover) without each call site
/// hand-rolling a StatefulWidget for two booleans. The `builder` receives
/// the current hover state and returns the visible widget; the wrapper
/// handles cursor + per-theme tap effect via [InteractionFeedback].
class HoverableTap extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final MouseCursor cursor;
  final HitTestBehavior behavior;

  const HoverableTap({
    super.key,
    required this.builder,
    required this.onTap,
    this.borderRadius,
    this.cursor = SystemMouseCursors.click,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<HoverableTap> createState() => _HoverableTapState();
}

class _HoverableTapState extends State<HoverableTap> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return InteractionFeedback(
      onTap: widget.onTap,
      borderRadius: widget.borderRadius,
      cursor: widget.cursor,
      behavior: widget.behavior,
      onHoverChanged: (h) {
        if (h == _hovered) return;
        setState(() => _hovered = h);
      },
      child: widget.builder(context, _hovered),
    );
  }
}

// Click-feedback durations. Compressed so click acknowledgement reads as
// low-latency — the user shouldn't feel the button "finishing" after they
// moved on. Relative ordering preserved so each theme still has its own
// tempo (caustic ripples longer than etch snaps).
Duration _durationFor(ThemeInteraction mode) => switch (mode) {
      ThemeInteraction.caustic => const Duration(milliseconds: 260),
      ThemeInteraction.etch => const Duration(milliseconds: 120),
      ThemeInteraction.warp => const Duration(milliseconds: 220),
      ThemeInteraction.vibration => const Duration(milliseconds: 180),
      ThemeInteraction.chalk => const Duration(milliseconds: 200),
      ThemeInteraction.inkSplat => const Duration(milliseconds: 220),
      ThemeInteraction.blockBreak => const Duration(milliseconds: 460),
      ThemeInteraction.gloss => const Duration(milliseconds: 160),
      ThemeInteraction.none => Duration.zero,
    };

class FeedbackGeometry {
  final Offset origin;
  final double nx;
  final double ny;
  final double biasX;
  final double biasY;

  FeedbackGeometry(this.origin, Size size)
      : nx = (origin.dx / size.width).clamp(0.0, 1.0),
        ny = (origin.dy / size.height).clamp(0.0, 1.0),
        biasX = -(origin.dx / size.width - 0.5) * 0.4,
        biasY = -(origin.dy / size.height - 0.5) * 0.4;
}

CustomPainter _feedbackPainter({
  required ThemeInteraction mode,
  required Color accent,
  required Offset origin,
  required double progress,
  required double luminescence,
}) {
  switch (mode) {
    case ThemeInteraction.caustic:
      return _CausticPainter(
          origin: origin, color: accent, t: progress, lum: luminescence);
    case ThemeInteraction.etch:
      return _EtchPainter(origin: origin, color: accent, t: progress);
    case ThemeInteraction.warp:
      return _WarpPainter(origin: origin, color: accent, t: progress);
    case ThemeInteraction.vibration:
      return _VibrationPainter(
          origin: origin, color: accent, t: progress);
    case ThemeInteraction.chalk:
      return _ChalkPainter(origin: origin, color: accent, t: progress);
    case ThemeInteraction.inkSplat:
      return _InkSplatPainter(origin: origin, t: progress);
    case ThemeInteraction.blockBreak:
      return _BlockBreakPainter(origin: origin, accent: accent, t: progress);
    case ThemeInteraction.gloss:
      return _GlossPainter(
          origin: origin, accent: accent, t: progress, lum: luminescence);
    case ThemeInteraction.none:
      return _NoopPainter();
  }
}

class _CausticPainter extends CustomPainter {
  final Offset origin;
  final Color color;
  final double t;
  final double lum;
  _CausticPainter({
    required this.origin,
    required this.color,
    required this.t,
    required this.lum,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxR = size.longestSide * 0.75;
    final r = 8 + (maxR - 8) * Curves.easeOutCubic.transform(t);
    final fade = (1 - t);
    final baseAlpha = (0.55 * fade * lum).clamp(0.0, 0.95);

    // Outer ring — expanding halo
    canvas.drawCircle(
      origin,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: baseAlpha),
    );
    // Inner caustic glow
    canvas.drawCircle(
      origin,
      r * 0.6,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: baseAlpha * 0.14),
    );
  }

  @override
  bool shouldRepaint(_CausticPainter old) =>
      old.t != t || old.origin != origin || old.color != color;
}

class _EtchPainter extends CustomPainter {
  final Offset origin;
  final Color color;
  final double t;
  _EtchPainter({required this.origin, required this.color, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = t < 0.3
        ? t / 0.3
        : 1 - (t - 0.3) / 0.7;
    final a = (pulse * 0.65).clamp(0.0, 1.0);

    final g = FeedbackGeometry(origin, size);
    final topW = 1.0 - g.ny;
    final botW = g.ny;
    final leftW = 1.0 - g.nx;
    final rightW = g.nx;

    final dark = Paint()..strokeWidth = 1.2;
    final light = Paint()..strokeWidth = 1.0;

    dark.color = Colors.black.withValues(alpha: a * 0.55 * topW);
    canvas.drawLine(Offset.zero, Offset(size.width, 0), dark);
    dark.color = Colors.black.withValues(alpha: a * 0.55 * leftW);
    canvas.drawLine(Offset.zero, Offset(0, size.height), dark);
    light.color = color.withValues(alpha: a * 0.35 * botW);
    canvas.drawLine(
        Offset(0, size.height), Offset(size.width, size.height), light);
    light.color = color.withValues(alpha: a * 0.35 * rightW);
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width, size.height), light);
  }

  @override
  bool shouldRepaint(_EtchPainter old) =>
      old.t != t || old.color != color || old.origin != origin;
}

class _WarpPainter extends CustomPainter {
  final Offset origin;
  final Color color;
  final double t;
  _WarpPainter({
    required this.origin,
    required this.color,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxR = size.longestSide * 0.5;
    final r = 10 + (maxR - 10) * Curves.easeOutCubic.transform(t);
    final fade = (1 - t);
    // Two rings with chromatic offset — "lens bending". Warm-shifted ring
    // on the right, cool-shifted on the left using HSL rotation so it
    // reads as glass refraction rather than raw inversion.
    final hsl = HSLColor.fromColor(color);
    final warm = hsl.withHue((hsl.hue - 18) % 360).toColor();
    final cool = hsl.withHue((hsl.hue + 18) % 360).toColor();
    Paint ringPaint(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = c.withValues(alpha: (0.45 * fade).clamp(0.0, 1.0));
    canvas.drawCircle(origin.translate(2, 0), r, ringPaint(warm));
    canvas.drawCircle(origin.translate(-2, 0), r, ringPaint(cool));
  }

  @override
  bool shouldRepaint(_WarpPainter old) =>
      old.t != t || old.origin != origin || old.color != color;
}

class _VibrationPainter extends CustomPainter {
  final Offset origin;
  final Color color;
  final double t;
  _VibrationPainter({
    required this.origin,
    required this.color,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Damped oscillation — 4 pulses, decaying
    final fade = 1 - t;
    const specks = 6;
    final seed = (origin.dx + origin.dy).hashCode & 0x7fffffff;
    final rng = math.Random(seed);
    // Paint hoisted: color is constant across all 6 specks this frame,
    // so we only allocate one Paint per paint() call instead of per-speck.
    final g = FeedbackGeometry(origin, size);
    final paint = Paint()
      ..color = color.withValues(alpha: (fade * 0.6).clamp(0.0, 1.0));
    for (var i = 0; i < specks; i++) {
      final dx = (rng.nextDouble() - 0.5 + g.biasX) * size.width * 0.6;
      final dy = (rng.nextDouble() - 0.5 + g.biasY) * size.height * 0.6;
      final jitter = math.sin(t * math.pi * 8 + i) * 1.8;
      final r = 1.5 + rng.nextDouble() * 1.5;
      canvas.drawCircle(origin.translate(dx + jitter, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(_VibrationPainter old) =>
      old.t != t || old.origin != origin || old.color != color;
}

class _ChalkPainter extends CustomPainter {
  final Offset origin;
  final Color color;
  final double t;
  _ChalkPainter({
    required this.origin,
    required this.color,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fade = 1 - t;
    final seed = (origin.dx * 31 + origin.dy).hashCode & 0x7fffffff;
    final rng = math.Random(seed);
    const dustCount = 10;
    // Paint hoisted — uniform color across all 10 dust specks this
    // frame means one allocation instead of ten.
    final paint = Paint()
      ..color = Colors.white
          .withValues(alpha: (fade * 0.55).clamp(0.0, 1.0));
    for (var i = 0; i < dustCount; i++) {
      final ang = rng.nextDouble() * math.pi * 2;
      final dist = 4 + t * (8 + rng.nextDouble() * 20);
      final dx = math.cos(ang) * dist;
      final dy = math.sin(ang) * dist + t * 6; // slight gravity
      final r = 0.6 + rng.nextDouble() * 0.8;
      canvas.drawCircle(origin.translate(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(_ChalkPainter old) =>
      old.t != t || old.origin != origin || old.color != color;
}

class _InkSplatPainter extends CustomPainter {
  final Offset origin;
  final double t;
  _InkSplatPainter({required this.origin, required this.t});

  // Hoisted Paths reused per paint — building once is cheaper than
  // re-allocating on every animation tick.
  static final Path _starPath = Path();

  @override
  void paint(Canvas canvas, Size size) {
    final fade = (1 - t).clamp(0.0, 1.0);
    if (fade <= 0.01) return;

    // 8-pointed star whose long spikes alternate with short ones —
    // classic Marvel-Comics impact-burst silhouette. Radius pops
    // outward over the first half then holds.
    final pop = (t * 2).clamp(0.0, 1.0);
    final outerR = 6.0 + 14.0 * pop;
    final innerR = outerR * 0.42;
    _starPath.reset();
    const points = 8;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outerR : innerR;
      final ang = (i * math.pi / points) - math.pi / 2;
      final p = origin + Offset(math.cos(ang) * r, math.sin(ang) * r);
      if (i == 0) {
        _starPath.moveTo(p.dx, p.dy);
      } else {
        _starPath.lineTo(p.dx, p.dy);
      }
    }
    _starPath.close();
    // Yellow fill — the comic-book impact color
    canvas.drawPath(
      _starPath,
      Paint()
        ..color = const Color(0xFFFFD300).withValues(alpha: fade * 0.85)
        ..style = PaintingStyle.fill,
    );
    // Heavy ink line on the star — every comic burst gets inked
    canvas.drawPath(
      _starPath,
      Paint()
        ..color = const Color(0xFF14141A).withValues(alpha: fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.miter,
    );

    // Like the impact lines around a comic-book punch.
    final flickPaint = Paint()
      ..color = const Color(0xFF14141A).withValues(alpha: fade * 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final ang = (i * math.pi * 2 / 4) + math.pi / 4;
      final innerEnd = outerR + 2;
      final outerEnd = outerR + 6 + fade * 4;
      canvas.drawLine(
        origin + Offset(math.cos(ang) * innerEnd, math.sin(ang) * innerEnd),
        origin + Offset(math.cos(ang) * outerEnd, math.sin(ang) * outerEnd),
        flickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_InkSplatPainter old) =>
      old.t != t || old.origin != origin;
}

class _NoopPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

/// Bibble gloss feedback. A tilted specular streak sweeps L-to-R
/// across the whole surface (not from the tap point — plastic catches
/// light along a line). Magenta leading edge, gold trailing tail,
/// matching the surface shader's highlight/rim hues.
class _GlossPainter extends CustomPainter {
  final Offset origin;
  final Color accent;
  final double t;
  final double lum;
  _GlossPainter({
    required this.origin,
    required this.accent,
    required this.t,
    required this.lum,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final travel = Curves.easeOutCubic.transform(t);
    final startX = origin.dx;
    final cx = startX + (size.width * 1.25 - startX) * travel;

    // 22% of width — narrower reads as cyberpunk scan, wider as spotlight
    final halfWidth = size.width * 0.11;

    // capped below full opacity — gloss is a reflection, not a brushstroke
    final env = math.sin(t * math.pi);
    final peakAlpha = (0.55 * env * lum).clamp(0.0, 0.85);

    final gold = const Color(0xFFFFC727);

    // ~12° tilt so it doesn't read as a flat vertical bar
    const tilt = 0.2094;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(cx, size.height / 2);
    canvas.rotate(tilt);

    // taller than surface height for rotation bleed
    final bandH = size.height * 1.4;

    // leading edge, magenta → transparent
    canvas.drawRect(
      Rect.fromLTRB(0, -bandH / 2, halfWidth, bandH / 2),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            accent.withValues(alpha: peakAlpha),
            accent.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromLTRB(0, -bandH / 2, halfWidth, bandH / 2),
        ),
    );
    // trailing tail, gold → transparent
    canvas.drawRect(
      Rect.fromLTRB(-halfWidth, -bandH / 2, 0, bandH / 2),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            gold.withValues(alpha: peakAlpha * 0.85),
            gold.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromLTRB(-halfWidth, -bandH / 2, 0, bandH / 2),
        ),
    );
    // hot white line at the boundary — sells specular vs gradient wash
    canvas.drawRect(
      Rect.fromLTRB(-1, -bandH / 2, 1, bandH / 2),
      Paint()..color = Colors.white.withValues(alpha: peakAlpha * 0.9),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlossPainter old) =>
      old.t != t || old.accent != accent || old.lum != lum;
}

/// Block-break burst. Taps spawn a handful of small voxel shards at
/// the click point; each is a tiny rotated square with an outward-
/// upward initial velocity, a slow spin, and gravity pulling it back
/// down. Half the shards take the dirt-brown side, half take the
/// theme accent, so the burst reads as "a block shattered here"
/// rather than a generic ripple.
class _BlockBreakPainter extends CustomPainter {
  final Offset origin;
  final Color accent;
  final double t;

  _BlockBreakPainter({
    required this.origin,
    required this.accent,
    required this.t,
  });

  // Pre-computed deterministic shard fan. Fixed seed so every tap
  // lands with the same shape — cheaper than allocating random
  // numbers per frame and gives the effect a consistent silhouette.
  // Each tuple: (angleRadians, speed, size, spin, palette-index)
  static const List<(double, double, double, double, int)> _shards = [
    (-2.80, 48, 3.5, 3.2, 0),
    (-2.25, 56, 2.8, -2.6, 1),
    (-1.90, 64, 3.2, 2.0, 0),
    (-1.55, 72, 2.5, -3.4, 1),
    (-1.20, 60, 3.0, 2.8, 0),
    (-0.85, 52, 2.7, -2.2, 1),
    (-0.50, 66, 3.4, 3.0, 0),
    (-0.15, 58, 2.6, -1.8, 1),
  ];

  // Dirt-tone brown — one of two shard palettes so the burst has
  // visual variety without depending on per-theme color lookups.
  static const Color _dirt = Color(0xFF6B4A2C);

  @override
  void paint(Canvas canvas, Size size) {
    // Gravity + duration tuned so shards arc up briefly then fall.
    // `physicalT` is normalized [0, 1]; gravity is expressed as
    // px-per-unit² so it scales with the progress timeline.
    const gravityPx = 180.0;
    final alpha = (1.0 - t * t).clamp(0.0, 1.0);
    if (alpha <= 0.01) return;

    final paint = Paint()
      ..isAntiAlias = false
      ..style = PaintingStyle.fill;

    for (final shard in _shards) {
      final angle = shard.$1;
      final speed = shard.$2;
      final size = shard.$3 * (1.0 - t * 0.25);
      final spin = shard.$4;
      final palette = shard.$5;

      final vx = math.cos(angle) * speed;
      final vy = math.sin(angle) * speed;
      final dx = vx * t;
      final dy = vy * t + 0.5 * gravityPx * t * t;

      final rotation = spin * t;
      final color = (palette == 0 ? _dirt : accent)
          .withValues(alpha: alpha * 0.85);

      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(rotation);
      paint.color = color;
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: size, height: size),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BlockBreakPainter old) =>
      old.t != t || old.origin != origin || old.accent != accent;
}
