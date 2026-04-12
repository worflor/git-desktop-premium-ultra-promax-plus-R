import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── Animated icon state machine ──────────────────────────────────────────────
// Each icon transitions between these states. The widget manages its own
// AnimationControllers internally — callers just set the desired state.

enum IconAnimState { idle, hovered, loading, success, error }

// ── Base animated icon widget ────────────────────────────────────────────────

abstract class _AnimatedIconBase extends StatefulWidget {
  final IconAnimState state;
  final Color color;
  final double size;

  const _AnimatedIconBase({
    super.key,
    required this.state,
    required this.color,
    this.size = 14,
  });
}

abstract class _AnimatedIconBaseState<T extends _AnimatedIconBase>
    extends State<T> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  late final AnimationController _hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    reverseDuration: const Duration(milliseconds: 400),
  );

  @override
  void initState() {
    super.initState();
    _applyState(widget.state);
  }

  @override
  void didUpdateWidget(covariant T old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _applyState(widget.state);
  }

  void _applyState(IconAnimState s) {
    switch (s) {
      case IconAnimState.idle:
        _loop.stop();
        _hover.reverse();
      case IconAnimState.hovered:
        _loop.stop();
        _hover.forward();
      case IconAnimState.loading:
        _hover.reverse();
        _loop.repeat();
      case IconAnimState.success:
        _loop.stop();
        _hover.reverse();
        _flash.forward(from: 0);
      case IconAnimState.error:
        _hover.reverse();
        _loop.repeat();
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted && widget.state == IconAnimState.error) {
            _loop.stop();
          }
        });
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _flash.dispose();
    _hover.dispose();
    super.dispose();
  }

  CustomPainter createPainter({
    required Color color,
    required double loopValue,
    required double flashValue,
    required double hoverValue,
    required IconAnimState state,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_loop, _flash, _hover]),
      builder: (context, _) {
        return CustomPaint(
          size: Size.square(widget.size),
          painter: createPainter(
            color: widget.color,
            loopValue: _loop.value,
            flashValue: _flash.value,
            hoverValue: _hover.value,
            state: widget.state,
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 1.  SPARKLE  —  generate commit message
//
//     Two stars: a main 4-point star and a small accent star (top-right).
//     Each point and each star lives its own life.
//
//     idle:    small star twinkles gently (slow opacity breathe)
//     hover:   main star points extend outward like radiating energy,
//              small star brightens and drifts slightly away
//     loading: each point extends/retracts in staggered sequence (pulsing
//              starburst), small star orbits the main star
//     success: points fold inward and re-emerge as a checkmark stroke
//     error:   star crumples (points collapse asymmetrically) then reforms
// ═══════════════════════════════════════════════════════════════════════════════

class AnimatedSparkleIcon extends _AnimatedIconBase {
  const AnimatedSparkleIcon({
    super.key,
    required super.state,
    required super.color,
    super.size,
  });

  @override
  State<AnimatedSparkleIcon> createState() => _AnimatedSparkleIconState();
}

class _AnimatedSparkleIconState
    extends _AnimatedIconBaseState<AnimatedSparkleIcon> {
  @override
  CustomPainter createPainter({
    required Color color,
    required double loopValue,
    required double flashValue,
    required double hoverValue,
    required IconAnimState state,
  }) =>
      _SparklePainter(
        color: color, loop: loopValue, flash: flashValue,
        hover: hoverValue, state: state,
      );
}

class _SparklePainter extends CustomPainter {
  final Color color;
  final double loop, flash, hover;
  final IconAnimState state;

  _SparklePainter({
    required this.color, required this.loop, required this.flash,
    required this.hover, required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 16;
    final cx = size.width / 2;
    final cy = size.height / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();

    // ── Success: star points converge → checkmark ──
    if (state == IconAnimState.success && flash > 0) {
      _paintMorphToCheck(canvas, paint, cx, cy, u);
      canvas.restore();
      return;
    }

    // ── Error: asymmetric crumple then reform ──
    if (state == IconAnimState.error) {
      _paintCrumple(canvas, paint, cx, cy, u);
      canvas.restore();
      return;
    }

    // ── Main star: 4 points with individual reach ──
    // Each point has its own outer radius that can vary independently.
    final baseOuter = u * 4.2;
    final baseInner = u * 1.6;
    final points = <double>[]; // 4 outer radii

    for (int i = 0; i < 4; i++) {
      double r = baseOuter;

      // Hover: points extend outward, staggered
      if (state == IconAnimState.hovered) {
        final stagger = math.sin((hover * math.pi) + i * 0.4);
        r += u * 0.9 * hover * (0.7 + 0.3 * stagger);
      }

      // Loading: each point pulses in sequence (wave pattern)
      if (state == IconAnimState.loading) {
        final phase = (loop * 2 * math.pi) + (i * math.pi / 2);
        r += u * 1.4 * (0.5 + 0.5 * math.sin(phase));
      }

      points.add(r);
    }

    // Draw the main star with per-point radii
    final starPath = Path();
    for (int i = 0; i < 8; i++) {
      final isOuter = i.isEven;
      final r = isOuter ? points[i ~/ 2] : baseInner;
      final angle = (i * math.pi / 4) - math.pi / 2;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        starPath.moveTo(x, y);
      } else {
        starPath.lineTo(x, y);
      }
    }
    starPath.close();
    canvas.drawPath(starPath, paint);

    // ── Small accent star (top-right) ──
    double smallX = cx + u * 3.8;
    double smallY = cy - u * 3.5;
    double smallOuter = u * 1.8;
    double smallAlpha = 0.45;

    // Idle: gentle twinkle
    if (state == IconAnimState.idle) {
      // Use a slow time-based flicker — we don't have a running controller
      // in idle, so this stays static. The twinkle only shows when
      // transitioning out of hover (the _hover controller reverse).
      smallAlpha = 0.45;
    }

    // Hover: brighten and drift outward
    if (state == IconAnimState.hovered) {
      smallAlpha = 0.45 + 0.55 * hover;
      smallX += u * 0.5 * hover;
      smallY -= u * 0.4 * hover;
      smallOuter += u * 0.3 * hover;
    }

    // Loading: orbit around the main star
    if (state == IconAnimState.loading) {
      final orbitAngle = -math.pi / 4 + loop * math.pi * 2;
      final orbitR = u * 5.2;
      smallX = cx + orbitR * math.cos(orbitAngle);
      smallY = cy + orbitR * math.sin(orbitAngle);
      smallAlpha = 0.5 + 0.5 * math.sin(loop * math.pi * 4);
      smallOuter = u * 1.3 + u * 0.5 * math.sin(loop * math.pi * 6);
    }

    final smallPaint = Paint()
      ..color = color.withValues(alpha: smallAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    _drawStar4(canvas, smallPaint, smallX, smallY, smallOuter, u * 0.6, math.pi / 4);

    canvas.restore();
  }

  void _drawStar4(Canvas canvas, Paint paint, double cx, double cy,
      double outer, double inner, double startAngle) {
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final r = i.isEven ? outer : inner;
      final angle = startAngle + (i * math.pi / 4) - math.pi / 2;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _paintCrumple(Canvas canvas, Paint paint, double cx, double cy, double u) {
    // Points collapse inward asymmetrically, then spring back.
    // loop goes 0→1 over the error duration.
    final t = loop;
    final crumple = math.sin(t * math.pi * 4) * (1.0 - t); // damped oscillation

    final baseOuter = u * 4.2;
    final baseInner = u * 1.6;

    final path = Path();
    for (int i = 0; i < 8; i++) {
      final isOuter = i.isEven;
      double r = isOuter ? baseOuter : baseInner;
      if (isOuter) {
        // Each point crumples by a different amount
        final asymmetry = [1.0, 0.6, 0.8, 1.2][i ~/ 2];
        r -= u * 2.5 * crumple * asymmetry;
        r = r.clamp(u * 0.5, baseOuter * 1.5);
      }
      final angle = (i * math.pi / 4) - math.pi / 2;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);

    // Small star jitters
    final jitterX = math.sin(t * math.pi * 10) * u * 0.8 * (1 - t);
    final jitterY = math.cos(t * math.pi * 8) * u * 0.5 * (1 - t);
    final smallPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _drawStar4(canvas, smallPaint,
        cx + u * 3.8 + jitterX, cy - u * 3.5 + jitterY,
        u * 1.8, u * 0.6, math.pi / 4);
  }

  void _paintMorphToCheck(Canvas canvas, Paint paint,
      double cx, double cy, double u) {
    final et = Curves.easeOutCubic.transform(flash);

    // Phase 1 (0→0.4): star points shrink inward to a dot
    // Phase 2 (0.4→1): checkmark strokes draw out from the center

    if (et < 0.4) {
      // Collapsing star
      final collapse = et / 0.4; // 0→1
      final r = u * 4.2 * (1.0 - collapse * 0.85);
      final inner = u * 1.6 * (1.0 - collapse * 0.6);
      _drawStar4(canvas, paint, cx, cy, r, inner, 0);
    }

    if (et > 0.3) {
      // Checkmark emerges
      final checkT = ((et - 0.3) / 0.7).clamp(0.0, 1.0);
      final popScale = 1.0 + 0.12 * math.sin(checkT * math.pi);
      canvas.translate(cx, cy);
      canvas.scale(popScale);
      canvas.translate(-cx, -cy);

      final checkPath = Path()
        ..moveTo(u * 3.5, cy)
        ..lineTo(u * 6.5, cy + u * 3)
        ..lineTo(u * 12.5, cy - u * 3);

      final metric = checkPath.computeMetrics().first;
      canvas.drawPath(metric.extractPath(0, metric.length * checkT), paint);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) =>
      loop != old.loop || flash != old.flash || hover != old.hover ||
      state != old.state || color != old.color;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 2.  SEARCH / LENS  —  review commit
//
//     A magnifying glass: lens circle + handle.
//     The two parts move independently, like a real tool being used.
//
//     idle:    a tiny glint highlight drifts across the glass surface
//     hover:   handle retracts as lens floats forward (zooming-in gesture),
//              lens grows slightly, glint brightens
//     loading: lens sways side-to-side examining content, handle follows
//              with a lag; a highlight sweeps across the lens interior
//     success: lens circle morphs into shield outline, handle becomes
//              the check's descending stroke
//     error:   fracture lines crack across the lens, then heal
// ═══════════════════════════════════════════════════════════════════════════════

class AnimatedSearchIcon extends _AnimatedIconBase {
  /// Review verdict — controls what the lens morphs into on success.
  /// "Ready" → shield+check, "Mostly ready" → simple check,
  /// "Needs attention" → eye, "High risk" → warning, "Block" → X
  final String? verdict;

  const AnimatedSearchIcon({
    super.key,
    required super.state,
    required super.color,
    super.size,
    this.verdict,
  });

  @override
  State<AnimatedSearchIcon> createState() => _AnimatedSearchIconState();
}

class _AnimatedSearchIconState
    extends _AnimatedIconBaseState<AnimatedSearchIcon> {
  @override
  CustomPainter createPainter({
    required Color color,
    required double loopValue,
    required double flashValue,
    required double hoverValue,
    required IconAnimState state,
  }) =>
      _SearchPainter(
        color: color, loop: loopValue, flash: flashValue,
        hover: hoverValue, state: state,
        verdict: widget.verdict,
      );
}

class _SearchPainter extends CustomPainter {
  final Color color;
  final double loop, flash, hover;
  final IconAnimState state;
  final String? verdict;

  _SearchPainter({
    required this.color, required this.loop, required this.flash,
    required this.hover, required this.state, this.verdict,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();

    // ── Success: morph based on review verdict ──
    if (state == IconAnimState.success && flash > 0) {
      _paintVerdictMorph(canvas, paint, s, size);
      canvas.restore();
      return;
    }

    // ── Error: lens cracks then heals ──
    if (state == IconAnimState.error) {
      _paintCrack(canvas, paint, s);
      canvas.restore();
      return;
    }

    // ── Lens position (base: 7,7) ──
    double lensX = 7 * s;
    double lensY = 7 * s;
    double lensR = 4.5 * s;

    // Handle endpoints (base: 10.5,10.5 → 13.5,13.5)
    double handleStartX = 10.5 * s;
    double handleStartY = 10.5 * s;
    double handleEndX = 13.5 * s;
    double handleEndY = 13.5 * s;

    // ── Hover: lens zooms forward, handle retracts ──
    if (state == IconAnimState.hovered) {
      final h = Curves.easeOutCubic.transform(hover);
      lensR += 0.5 * s * h;              // lens grows
      lensX -= 0.3 * s * h;              // drifts toward center
      lensY -= 0.3 * s * h;
      handleEndX -= 1.0 * s * h;         // handle shortens
      handleEndY -= 1.0 * s * h;
    }

    // ── Loading: lens sways examining, handle follows with lag ──
    if (state == IconAnimState.loading) {
      final swayX = math.sin(loop * math.pi * 2) * 1.8 * s;
      final swayY = math.cos(loop * math.pi * 2 * 0.7) * 0.8 * s;
      lensX += swayX;
      lensY += swayY;
      // Handle follows with spring lag
      final lagX = math.sin((loop - 0.08) * math.pi * 2) * 1.8 * s;
      final lagY = math.cos((loop - 0.08) * math.pi * 2 * 0.7) * 0.8 * s;
      handleStartX += lagX * 0.7;
      handleStartY += lagY * 0.7;
      handleEndX += lagX * 0.3;
      handleEndY += lagY * 0.3;
    }

    // ── Draw lens circle ──
    paint.strokeWidth = 1.5 * s;
    canvas.drawCircle(Offset(lensX, lensY), lensR, paint);

    // ── Draw handle ──
    paint.strokeWidth = 1.8 * s;
    canvas.drawLine(
      Offset(handleStartX, handleStartY),
      Offset(handleEndX, handleEndY),
      paint,
    );

    // ── Glint: a small highlight arc on the lens surface ──
    double glintAngle = -math.pi * 0.75; // default position (top-left)
    double glintAlpha = 0.20;

    if (state == IconAnimState.hovered) {
      glintAlpha = 0.20 + 0.35 * hover;
    }
    if (state == IconAnimState.loading) {
      // Glint sweeps around the lens
      glintAngle = -math.pi * 0.75 + loop * math.pi * 2;
      glintAlpha = 0.25 + 0.25 * math.sin(loop * math.pi * 4);
    }

    final glintPaint = Paint()
      ..color = color.withValues(alpha: glintAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * s
      ..strokeCap = StrokeCap.round;
    final glintR = lensR * 0.65;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(lensX, lensY), radius: glintR),
      glintAngle,
      0.6, // arc sweep
      false,
      glintPaint,
    );

    // ── Loading: sweep highlight inside lens ──
    if (state == IconAnimState.loading) {
      canvas.save();
      canvas.clipPath(Path()..addOval(
        Rect.fromCircle(center: Offset(lensX, lensY), radius: lensR - s),
      ));
      final sweepT = (math.sin(loop * math.pi * 2) + 1) / 2;
      final sweepX = lensX - lensR + sweepT * lensR * 2;
      final sweepPaint = Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * s
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(sweepX, lensY - lensR),
        Offset(sweepX, lensY + lensR),
        sweepPaint,
      );
      canvas.restore();
    }

    canvas.restore();
  }

  void _paintCrack(Canvas canvas, Paint paint, double s) {
    final t = loop;
    final crackIntensity = math.sin(t * math.pi * 3) * (1.0 - t);

    // Draw lens normally
    final lensX = 7 * s;
    final lensY = 7 * s;
    final lensR = 4.5 * s;

    paint.strokeWidth = 1.5 * s;
    canvas.drawCircle(Offset(lensX, lensY), lensR, paint);

    // Handle
    paint.strokeWidth = 1.8 * s;
    canvas.drawLine(Offset(10.5 * s, 10.5 * s), Offset(13.5 * s, 13.5 * s), paint);

    // Fracture lines inside lens
    if (crackIntensity.abs() > 0.05) {
      final crackPaint = Paint()
        ..color = color.withValues(alpha: crackIntensity.abs() * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 * s
        ..strokeCap = StrokeCap.round;

      // Crack 1: diagonal from center
      canvas.drawLine(
        Offset(lensX - 0.5 * s, lensY - 0.5 * s),
        Offset(lensX - 3 * s * crackIntensity.abs(), lensY - 3.5 * s * crackIntensity.abs()),
        crackPaint,
      );
      // Crack 2: branch
      canvas.drawLine(
        Offset(lensX + 0.3 * s, lensY),
        Offset(lensX + 2.5 * s * crackIntensity.abs(), lensY + 2.8 * s * crackIntensity.abs()),
        crackPaint,
      );
      // Crack 3: short spur
      canvas.drawLine(
        Offset(lensX, lensY + 0.2 * s),
        Offset(lensX - 2 * s * crackIntensity.abs(), lensY + 1.5 * s * crackIntensity.abs()),
        crackPaint,
      );
    }
  }

  // ── Phase 1 (shared): lens collapses, handle retracts ──
  void _paintLensCollapse(Canvas canvas, Paint paint, double s, double morph) {
    final em = Curves.easeInOutCubic.transform(morph);
    final cx = s * 8;

    final lensX = 7 * s + (cx - 7 * s) * em;
    final lensY = 7 * s + (cx - 7 * s) * em;
    final lensR = 4.5 * s * (1.0 - em * 0.85);

    paint.strokeWidth = 1.5 * s;
    paint.color = color;
    canvas.drawCircle(Offset(lensX, lensY), lensR, paint);

    paint.color = color.withValues(alpha: 1.0 - em);
    paint.strokeWidth = 1.8 * s;
    canvas.drawLine(
      Offset(10.5 * s, 10.5 * s),
      Offset(13.5 * s - 2 * s * em, 13.5 * s - 2 * s * em),
      paint,
    );
    paint.color = color;
  }

  void _paintVerdictMorph(Canvas canvas, Paint paint, double s, Size size) {
    final et = Curves.easeOutCubic.transform(flash);
    paint.strokeWidth = 1.5 * s;

    // Phase 1: lens collapses (0→0.45)
    if (et < 0.45) {
      _paintLensCollapse(canvas, paint, s, et / 0.45);
      return;
    }

    // Phase 2: verdict symbol emerges (0.4→1.0)
    final cx = size.width / 2;
    final cy = size.height / 2;
    final symbolT = ((et - 0.4) / 0.6).clamp(0.0, 1.0);
    final pop = 1.0 + 0.1 * math.sin(symbolT * math.pi);

    canvas.translate(cx, cy);
    canvas.scale(pop);

    paint.color = color;
    paint.strokeWidth = 1.5 * s;

    switch (verdict) {
      // ── Ready: shield with check ──
      case 'Ready':
        final shield = Path()
          ..moveTo(0, -6 * s)
          ..lineTo(5 * s, -3.5 * s)
          ..lineTo(5 * s, 1 * s)
          ..quadraticBezierTo(0, 6.5 * s, 0, 6.5 * s)
          ..quadraticBezierTo(0, 6.5 * s, -5 * s, 1 * s)
          ..lineTo(-5 * s, -3.5 * s)
          ..close();
        final shieldMetric = shield.computeMetrics().first;
        canvas.drawPath(
          shieldMetric.extractPath(0, shieldMetric.length * symbolT),
          paint,
        );
        if (symbolT > 0.4) {
          final ct = ((symbolT - 0.4) / 0.6).clamp(0.0, 1.0);
          final check = Path()
            ..moveTo(-2.2 * s, 0.5 * s)
            ..lineTo(-0.5 * s, 2.5 * s)
            ..lineTo(2.5 * s, -1.5 * s);
          final cm = check.computeMetrics().first;
          canvas.drawPath(cm.extractPath(0, cm.length * ct), paint);
        }

      // ── Mostly ready: simple bold checkmark ──
      case 'Mostly ready':
        final check = Path()
          ..moveTo(-4 * s, 0)
          ..lineTo(-1 * s, 3.5 * s)
          ..lineTo(5 * s, -3.5 * s);
        paint.strokeWidth = 1.8 * s;
        final cm = check.computeMetrics().first;
        canvas.drawPath(cm.extractPath(0, cm.length * symbolT), paint);

      // ── Needs attention: open eye ──
      case 'Needs attention':
        // Eye outline (almond shape)
        final eyeTop = Path()
          ..moveTo(-6 * s, 0)
          ..quadraticBezierTo(0, -4.5 * s, 6 * s, 0);
        final eyeBot = Path()
          ..moveTo(-6 * s, 0)
          ..quadraticBezierTo(0, 4.5 * s, 6 * s, 0);
        final topM = eyeTop.computeMetrics().first;
        final botM = eyeBot.computeMetrics().first;
        canvas.drawPath(topM.extractPath(0, topM.length * symbolT), paint);
        canvas.drawPath(botM.extractPath(0, botM.length * symbolT), paint);
        // Pupil (appears after eye shape is drawn)
        if (symbolT > 0.5) {
          final pupilT = ((symbolT - 0.5) / 0.5).clamp(0.0, 1.0);
          canvas.drawCircle(Offset.zero, 1.8 * s * pupilT, paint);
        }

      // ── High risk: warning triangle with ! ──
      case 'High risk':
        final tri = Path()
          ..moveTo(0, -5.5 * s)
          ..lineTo(5.5 * s, 4.5 * s)
          ..lineTo(-5.5 * s, 4.5 * s)
          ..close();
        final triM = tri.computeMetrics().first;
        canvas.drawPath(triM.extractPath(0, triM.length * symbolT), paint);
        if (symbolT > 0.5) {
          final bangT = ((symbolT - 0.5) / 0.5).clamp(0.0, 1.0);
          // Exclamation line
          canvas.drawLine(
            Offset(0, -2.5 * s),
            Offset(0, (-2.5 + 3.5 * bangT) * s),
            paint,
          );
          // Dot
          if (bangT > 0.7) {
            canvas.drawCircle(
              Offset(0, 3 * s),
              0.5 * s,
              paint..style = PaintingStyle.fill,
            );
            paint.style = PaintingStyle.stroke;
          }
        }

      // ── Block: bold X ──
      case 'Block':
        // Sad robot face: head circle, antenna, dash eyes, frown arc.
        // Phase 1 (0→0.35): head draws
        // Phase 2 (0.35→0.6): antenna + eyes appear
        // Phase 3 (0.6→1.0): frown draws
        paint.strokeWidth = 1.5 * s;

        // Head circle
        final headR = 4.5 * s;
        final headRect = Rect.fromCircle(center: Offset.zero, radius: headR);
        final headT = (symbolT / 0.35).clamp(0.0, 1.0);
        canvas.drawArc(headRect, -math.pi / 2, math.pi * 2 * headT, false, paint);

        // Antenna (small line + dot on top)
        if (symbolT > 0.3) {
          final antT = ((symbolT - 0.3) / 0.2).clamp(0.0, 1.0);
          canvas.drawLine(
            Offset(0, -headR),
            Offset(0, -headR - 2.2 * s * antT),
            paint,
          );
          if (antT > 0.6) {
            canvas.drawCircle(
              Offset(0, -headR - 2.2 * s),
              0.6 * s,
              paint..style = PaintingStyle.fill,
            );
            paint.style = PaintingStyle.stroke;
          }
        }

        // Eyes (small horizontal dashes — half-shut, sad)
        if (symbolT > 0.4) {
          final eyeT = ((symbolT - 0.4) / 0.2).clamp(0.0, 1.0);
          final eyeW = 1.4 * s * eyeT;
          final eyeY = -1.0 * s;
          // Left eye
          canvas.drawLine(
            Offset(-2.0 * s - eyeW, eyeY),
            Offset(-2.0 * s + eyeW, eyeY),
            paint,
          );
          // Right eye
          canvas.drawLine(
            Offset(2.0 * s - eyeW, eyeY),
            Offset(2.0 * s + eyeW, eyeY),
            paint,
          );
        }

        // Frown (downward arc)
        if (symbolT > 0.6) {
          final frownT = ((symbolT - 0.6) / 0.4).clamp(0.0, 1.0);
          final frown = Path()
            ..moveTo(-2.2 * s, 2.2 * s)
            ..quadraticBezierTo(0, 0.8 * s, 2.2 * s, 2.2 * s);
          final fm = frown.computeMetrics().first;
          canvas.drawPath(fm.extractPath(0, fm.length * frownT), paint);
        }

      // ── Fallback (no verdict or unknown): simple check ──
      default:
        final check = Path()
          ..moveTo(-3.5 * s, 0)
          ..lineTo(-1 * s, 2.8 * s)
          ..lineTo(4 * s, -2.8 * s);
        final cm = check.computeMetrics().first;
        canvas.drawPath(cm.extractPath(0, cm.length * symbolT), paint);
    }
  }

  @override
  bool shouldRepaint(_SearchPainter old) =>
      loop != old.loop || flash != old.flash || hover != old.hover ||
      state != old.state || color != old.color || verdict != old.verdict;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3.  PUSH ARROW  —  commit & push
//
//     An upward arrow (shaft + chevron head) and a horizontal bar at top.
//     The parts are a cohesive system: the bar is the "destination" the
//     arrow is pushing toward.
//
//     idle:    static, but the arrowhead has a subtle upward lean
//     hover:   shaft extends, arrowhead sharpens (angles tighten),
//              top bar glows/thickens — the arrow is eager
//     loading: arrow dissolves into particles streaming upward through
//              the bar, then reforms below and streams again
//     success: arrow passes through bar, bar splits open to reveal a
//              checkmark that settles in with a bounce
//     error:   arrow slams into bar (bar shakes on impact), arrow
//              compresses and bounces back down
// ═══════════════════════════════════════════════════════════════════════════════

class AnimatedPushIcon extends _AnimatedIconBase {
  const AnimatedPushIcon({
    super.key,
    required super.state,
    required super.color,
    super.size,
  });

  @override
  State<AnimatedPushIcon> createState() => _AnimatedPushIconState();
}

class _AnimatedPushIconState extends _AnimatedIconBaseState<AnimatedPushIcon> {
  @override
  CustomPainter createPainter({
    required Color color,
    required double loopValue,
    required double flashValue,
    required double hoverValue,
    required IconAnimState state,
  }) =>
      _PushPainter(
        color: color, loop: loopValue, flash: flashValue,
        hover: hoverValue, state: state,
      );
}

class _PushPainter extends CustomPainter {
  final Color color;
  final double loop, flash, hover;
  final IconAnimState state;

  _PushPainter({
    required this.color, required this.loop, required this.flash,
    required this.hover, required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    final cx = 8 * s;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();

    // ── Success: arrow through bar → checkmark ──
    if (state == IconAnimState.success && flash > 0) {
      _paintSuccess(canvas, paint, s, cx);
      canvas.restore();
      return;
    }

    // ── Error: arrow slams into bar, compresses, bounces back ──
    if (state == IconAnimState.error) {
      _paintError(canvas, paint, s, cx);
      canvas.restore();
      return;
    }

    // ── Top bar ──
    double barWidth = 10 * s;
    double barStroke = 1.5 * s;

    // Hover: bar thickens slightly, eager to receive
    if (state == IconAnimState.hovered) {
      barStroke += 0.3 * s * hover;
      barWidth += 0.5 * s * hover;
    }

    paint.strokeWidth = barStroke;
    canvas.drawLine(
      Offset(cx - barWidth / 2, 3 * s),
      Offset(cx + barWidth / 2, 3 * s),
      paint,
    );

    // ── Arrow ──
    paint.strokeWidth = 1.5 * s;

    // Shaft endpoints
    double shaftBottom = 14 * s;
    double shaftTop = 5 * s;

    // Arrowhead spread
    double headSpreadX = 3 * s; // how far left/right the head goes
    double headY = 8 * s;

    if (state == IconAnimState.hovered) {
      final h = Curves.easeOutCubic.transform(hover);
      shaftTop -= 0.8 * s * h;           // shaft extends
      headSpreadX -= 0.5 * s * h;        // arrowhead sharpens
      headY -= 0.6 * s * h;              // head moves up with shaft
      shaftBottom -= 0.4 * s * h;        // tail lifts slightly
    }

    if (state == IconAnimState.loading) {
      // ── Streaming particles instead of solid arrow ──
      _paintStreamingParticles(canvas, paint, s, cx);
      canvas.restore();
      return;
    }

    // Draw shaft
    canvas.drawLine(Offset(cx, shaftBottom), Offset(cx, shaftTop), paint);

    // Draw arrowhead
    final arrowHead = Path()
      ..moveTo(cx - headSpreadX, headY)
      ..lineTo(cx, shaftTop)
      ..lineTo(cx + headSpreadX, headY);
    canvas.drawPath(arrowHead, paint);

    canvas.restore();
  }

  void _paintStreamingParticles(Canvas canvas, Paint paint, double s, double cx) {
    // Top bar stays
    paint.strokeWidth = 1.5 * s;
    canvas.drawLine(Offset(3 * s, 3 * s), Offset(13 * s, 3 * s), paint);

    // Stream of small strokes ascending at different speeds
    final rng = math.Random(42); // deterministic seed
    for (int i = 0; i < 7; i++) {
      final baseSpeed = 0.7 + rng.nextDouble() * 0.6;
      final xOffset = (rng.nextDouble() - 0.5) * 4 * s;
      final phase = ((loop * baseSpeed) + i * 0.14) % 1.0;

      // Y position: bottom (14) to top (1), wrapping
      final y = 14 * s - phase * 13 * s;
      final length = (1.5 + rng.nextDouble() * 1.5) * s;

      // Fade near top bar (destination)
      final distToBar = (y - 3 * s).abs();
      final alpha = distToBar < 2 * s
          ? (distToBar / (2 * s)).clamp(0.0, 1.0) * 0.8
          : 0.8;

      final particlePaint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * s
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(cx + xOffset, y),
        Offset(cx + xOffset, y - length),
        particlePaint,
      );
    }
  }

  void _paintError(Canvas canvas, Paint paint, double s, double cx) {
    final t = loop;
    final impact = math.sin(t * math.pi * 3) * (1.0 - t);

    // Bar shakes on impact
    final barShakeX = impact * 1.5 * s;
    paint.strokeWidth = 1.5 * s;
    canvas.drawLine(
      Offset(3 * s + barShakeX, 3 * s),
      Offset(13 * s + barShakeX, 3 * s),
      paint,
    );

    // Arrow compresses then bounces back
    final compress = impact.abs();
    final shaftTop = 5 * s + compress * 2.5 * s;  // top of shaft pushes down
    final shaftBottom = 14 * s - compress * 1.0 * s; // bottom lifts
    final headY = 8 * s + compress * 1.5 * s;

    canvas.drawLine(Offset(cx, shaftBottom), Offset(cx, shaftTop), paint);
    final head = Path()
      ..moveTo(cx - 3 * s, headY)
      ..lineTo(cx, shaftTop)
      ..lineTo(cx + 3 * s, headY);
    canvas.drawPath(head, paint);
  }

  void _paintSuccess(Canvas canvas, Paint paint, double s, double cx) {
    final et = Curves.easeOutCubic.transform(flash);

    if (et < 0.4) {
      // Arrow ascends through bar
      final rise = et / 0.4;
      final arrowY = -12 * s * rise; // arrow flies up past bar

      paint.strokeWidth = 1.5 * s;
      paint.color = color.withValues(alpha: 1.0 - rise);

      canvas.save();
      canvas.translate(0, arrowY);
      canvas.drawLine(Offset(cx, 14 * s), Offset(cx, 5 * s), paint);
      final head = Path()
        ..moveTo(5 * s, 8 * s)..lineTo(cx, 5 * s)..lineTo(11 * s, 8 * s);
      canvas.drawPath(head, paint);
      canvas.restore();

      // Bar splits open
      paint.color = color;
      final split = rise * 2 * s;
      canvas.drawLine(
        Offset(3 * s, 3 * s), Offset(cx - 1 * s - split, 3 * s), paint);
      canvas.drawLine(
        Offset(cx + 1 * s + split, 3 * s), Offset(13 * s, 3 * s), paint);
    } else {
      // Bar closes back
      paint.color = color;
      paint.strokeWidth = 1.5 * s;
      final closeT = ((et - 0.4) / 0.2).clamp(0.0, 1.0);
      final split = (1.0 - closeT) * 2 * s;
      canvas.drawLine(
        Offset(3 * s, 3 * s), Offset(cx - 1 * s - split, 3 * s), paint);
      canvas.drawLine(
        Offset(cx + 1 * s + split, 3 * s), Offset(13 * s, 3 * s), paint);

      // Checkmark settles with bounce
      if (et > 0.45) {
        final checkT = ((et - 0.45) / 0.55).clamp(0.0, 1.0);
        final bounce = Curves.elasticOut.transform(checkT);
        final checkY = 3 * s + 6 * s * bounce;

        canvas.save();
        canvas.translate(cx, checkY);
        final checkPath = Path()
          ..moveTo(-3 * s, 0)
          ..lineTo(-0.8 * s, 2.5 * s)
          ..lineTo(3.5 * s, -2.5 * s);
        final metric = checkPath.computeMetrics().first;
        canvas.drawPath(
          metric.extractPath(0, metric.length * checkT.clamp(0.0, 1.0)),
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_PushPainter old) =>
      loop != old.loop || flash != old.flash || hover != old.hover ||
      state != old.state || color != old.color;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 4.  SYNC  —  mode toggle (commit ↔ sync)
//
//     Same commit icon (circle + lines) but rotated 90°, so the pipeline
//     runs horizontally. Same animations, same personality, different axis.
// ═══════════════════════════════════════════════════════════════════════════════

class AnimatedSyncIcon extends _AnimatedIconBase {
  const AnimatedSyncIcon({
    super.key,
    required super.state,
    required super.color,
    super.size,
  });

  @override
  State<AnimatedSyncIcon> createState() => _AnimatedSyncIconState();
}

class _AnimatedSyncIconState extends _AnimatedIconBaseState<AnimatedSyncIcon> {
  @override
  CustomPainter createPainter({
    required Color color,
    required double loopValue,
    required double flashValue,
    required double hoverValue,
    required IconAnimState state,
  }) =>
      _SyncPainter(
        color: color, loop: loopValue, flash: flashValue,
        hover: hoverValue, state: state,
      );
}

class _SyncPainter extends CustomPainter {
  final Color color;
  final double loop, flash, hover;
  final IconAnimState state;

  _SyncPainter({
    required this.color, required this.loop, required this.flash,
    required this.hover, required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Rotate the whole canvas 90° and delegate to the commit painter logic.
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.translate(cx, cy);
    canvas.rotate(math.pi / 2);
    canvas.translate(-cx, -cy);

    _paintCommitShape(canvas, size, color, loop, flash, hover, state);
  }

  @override
  bool shouldRepaint(_SyncPainter old) =>
      loop != old.loop || flash != old.flash || hover != old.hover ||
      state != old.state || color != old.color;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 5.  COMMIT CIRCLE  —  commit-only mode toggle
//
//     Circle with vertical lines through it — data flowing through a node.
//     Shared paint logic with sync (which just rotates 90°).
//
//     idle:    static circle + lines
//     hover:   lines extend outward, circle breathes slightly
//     loading: streaming dashes flow through, circle pulses
// ═══════════════════════════════════════════════════════════════════════════════

/// Shared paint logic for commit (vertical) and sync (horizontal = rotated).
void _paintCommitShape(Canvas canvas, Size size, Color color,
    double loop, double flash, double hover, IconAnimState state) {
  final s = size.width / 16;
  final cx = 8 * s;
  final cy = 8 * s;

  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  canvas.save();

  // ── Circle ──
  double circleR = 2.5 * s;

  // Hover: smooth gentle grow — no sin pulse, just linear interpolation
  if (state == IconAnimState.hovered) {
    circleR += 0.3 * s * hover;
  }

  // Loading: rhythmic expansion
  if (state == IconAnimState.loading) {
    circleR += math.sin(loop * math.pi * 2) * 0.4 * s;
  }

  paint.strokeWidth = 1.5 * s;
  canvas.drawCircle(Offset(cx, cy), circleR, paint);

  // ── Pipeline lines ──
  final isStreaming = state == IconAnimState.loading;

  // Line extension on hover (lines reach outward smoothly)
  final extend = hover * 0.8 * s;

  if (!isStreaming) {
    // Static (or hover-extended) lines — always drawn, smooth at all hover values
    canvas.drawLine(Offset(cx, (1.5 * s) - extend), Offset(cx, 5.5 * s), paint);
    canvas.drawLine(Offset(cx, 10.5 * s), Offset(cx, (14.5 * s) + extend), paint);
  } else {
    // Streaming dashes flowing downward through the node
    for (int i = 0; i < 5; i++) {
      final phase = (loop * 2.5 + i * 0.2) % 1.0;
      final totalTravel = 13 * s;
      final y = 1.5 * s + phase * totalTravel;
      final segLen = 1.6 * s;

      // Skip inside the circle gap
      final distFromCenter = (y - cy).abs();
      if (distFromCenter < circleR + 0.8 * s) continue;

      final segAlpha = 0.4 + 0.6 * (1.0 - phase);
      final segPaint = Paint()
        ..color = color.withValues(alpha: segAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * s
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(cx, y),
        Offset(cx, (y + segLen).clamp(0, 14.5 * s)),
        segPaint,
      );
    }

    // Ghost lines behind the streaming dashes
    final ghostPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, 1.5 * s), Offset(cx, 5.5 * s), ghostPaint);
    canvas.drawLine(Offset(cx, 10.5 * s), Offset(cx, 14.5 * s), ghostPaint);
  }

  canvas.restore();
}

class AnimatedCommitIcon extends _AnimatedIconBase {
  const AnimatedCommitIcon({
    super.key,
    required super.state,
    required super.color,
    super.size,
  });

  @override
  State<AnimatedCommitIcon> createState() => _AnimatedCommitIconState();
}

class _AnimatedCommitIconState
    extends _AnimatedIconBaseState<AnimatedCommitIcon> {
  @override
  CustomPainter createPainter({
    required Color color,
    required double loopValue,
    required double flashValue,
    required double hoverValue,
    required IconAnimState state,
  }) =>
      _CommitPainter(
        color: color, loop: loopValue, flash: flashValue,
        hover: hoverValue, state: state,
      );
}

class _CommitPainter extends CustomPainter {
  final Color color;
  final double loop, flash, hover;
  final IconAnimState state;

  _CommitPainter({
    required this.color, required this.loop, required this.flash,
    required this.hover, required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintCommitShape(canvas, size, color, loop, flash, hover, state);
  }

  @override
  bool shouldRepaint(_CommitPainter old) =>
      loop != old.loop || flash != old.flash || hover != old.hover ||
      state != old.state || color != old.color;
}
