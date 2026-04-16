import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'motion.dart';

// Each icon transitions between these states. The widget manages its own
// AnimationControllers internally — callers just set the desired state.

enum IconAnimState { idle, hovered, loading, success, error }


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
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 240),
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // React to a live toggle of Reduce Motion — if the user flips it ON
    // while an icon is mid-loop, immediately stop the loop.
    if (context.reduceMotion) {
      if (_loop.isAnimating) _loop.stop();
      if (_hover.isAnimating) _hover.stop();
    } else {
      // If the icon is currently in a state that wants a loop but it isn't
      // running (because we stopped it earlier), resume.
      if ((widget.state == IconAnimState.loading ||
              widget.state == IconAnimState.error) &&
          !_loop.isAnimating) {
        _loop.repeat();
      }
    }
  }

  void _applyState(IconAnimState s) {
    final reduce = mounted ? context.reduceMotionRead : false;
    switch (s) {
      case IconAnimState.idle:
        _loop.stop();
        reduce ? _hover.value = 0 : _hover.reverse();
      case IconAnimState.hovered:
        _loop.stop();
        reduce ? _hover.value = 1 : _hover.forward();
      case IconAnimState.loading:
        reduce ? _hover.value = 0 : _hover.reverse();
        if (!reduce) _loop.repeat();
      case IconAnimState.success:
        _loop.stop();
        reduce ? _hover.value = 0 : _hover.reverse();
        if (!reduce) _flash.forward(from: 0);
        else {
          _flash.value = 1;
        }
      case IconAnimState.error:
        reduce ? _hover.value = 0 : _hover.reverse();
        if (!reduce) {
          _loop.repeat();
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted && widget.state == IconAnimState.error) {
              _loop.stop();
            }
          });
        }
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

    if (state == IconAnimState.success && flash > 0) {
      _paintMorphToCheck(canvas, paint, cx, cy, u);
      canvas.restore();
      return;
    }

    if (state == IconAnimState.error) {
      _paintCrumple(canvas, paint, cx, cy, u);
      canvas.restore();
      return;
    }

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

    if (state == IconAnimState.success && flash > 0) {
      _paintVerdictMorph(canvas, paint, s, size);
      canvas.restore();
      return;
    }

    if (state == IconAnimState.error) {
      _paintCrack(canvas, paint, s);
      canvas.restore();
      return;
    }

    double lensX = 7 * s;
    double lensY = 7 * s;
    double lensR = 4.5 * s;

    // Handle endpoints (base: 10.5,10.5 → 13.5,13.5)
    double handleStartX = 10.5 * s;
    double handleStartY = 10.5 * s;
    double handleEndX = 13.5 * s;
    double handleEndY = 13.5 * s;

    if (state == IconAnimState.hovered) {
      final h = Curves.easeOutCubic.transform(hover);
      lensR += 0.5 * s * h;              // lens grows
      lensX -= 0.3 * s * h;              // drifts toward center
      lensY -= 0.3 * s * h;
      handleEndX -= 1.0 * s * h;         // handle shortens
      handleEndY -= 1.0 * s * h;
    }

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

    paint.strokeWidth = 1.5 * s;
    canvas.drawCircle(Offset(lensX, lensY), lensR, paint);

    paint.strokeWidth = 1.8 * s;
    canvas.drawLine(
      Offset(handleStartX, handleStartY),
      Offset(handleEndX, handleEndY),
      paint,
    );

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

      case 'Mostly ready':
        final check = Path()
          ..moveTo(-4 * s, 0)
          ..lineTo(-1 * s, 3.5 * s)
          ..lineTo(5 * s, -3.5 * s);
        paint.strokeWidth = 1.8 * s;
        final cm = check.computeMetrics().first;
        canvas.drawPath(cm.extractPath(0, cm.length * symbolT), paint);

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

    if (state == IconAnimState.success && flash > 0) {
      _paintSuccess(canvas, paint, s, cx);
      canvas.restore();
      return;
    }

    if (state == IconAnimState.error) {
      _paintError(canvas, paint, s, cx);
      canvas.restore();
      return;
    }

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

// 4.  SYNC  —  mode toggle (commit ↔ sync)
//
//     Same commit icon (circle + lines) but rotated 90°, so the pipeline
//     runs horizontally. Same animations, same personality, different axis.

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

// 5.  COMMIT CIRCLE  —  commit-only mode toggle
//
//     Circle with vertical lines through it — data flowing through a node.
//     Shared paint logic with sync (which just rotates 90°).
//
//     idle:    static circle + lines
//     hover:   lines extend outward, circle breathes slightly
//     loading: streaming dashes flow through, circle pulses

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

// 6.  HISTORY  —  a clockface that unwinds time
//
//     Anatomy: clock circle, hour hand (10), minute hand (2 — "10:10"),
//     center dot, and a small counter-clockwise arc indicator at the
//     9-o'clock edge with a fin arrowhead. The indicator isn't decorative —
//     it's the visible part of the rewind mechanism the hands belong to.
//
//     idle:    static. The indicator's alpha settles as hover reverses,
//              so the clock feels like it's "quietly ticking down".
//     hover:   hands rotate CCW up to 60° (unwinding time). The indicator
//              brightens — a mechanical handshake.
//     loading: hands spin CCW continuously; 3 fading ghost minute-hands
//              trail behind showing temporal momentum. Indicator drifts
//              with the mechanism at half speed.
//     success: hands snap toward 12:00; three radial pulse rings expand
//              from the center dot (a chime resonating outward).
//     error:   hands lurch forward (wrong direction) in a damped
//              oscillation; the indicator's alpha stutters.

class AnimatedHistoryIcon extends _AnimatedIconBase {
  const AnimatedHistoryIcon({
    super.key,
    required super.state,
    required super.color,
    super.size,
  });

  @override
  State<AnimatedHistoryIcon> createState() => _AnimatedHistoryIconState();
}

class _AnimatedHistoryIconState
    extends _AnimatedIconBaseState<AnimatedHistoryIcon> {
  @override
  CustomPainter createPainter({
    required Color color,
    required double loopValue,
    required double flashValue,
    required double hoverValue,
    required IconAnimState state,
  }) =>
      _HistoryPainter(
        color: color, loop: loopValue, flash: flashValue,
        hover: hoverValue, state: state,
      );
}

class _HistoryPainter extends CustomPainter {
  final Color color;
  final double loop, flash, hover;
  final IconAnimState state;

  _HistoryPainter({
    required this.color, required this.loop, required this.flash,
    required this.hover, required this.state,
  });

  // Flutter canvas: y-down, angle 0 = 3 o'clock, -π/2 = 12, π = 9.
  static const double _hourBase = 7 * math.pi / 6;    // 10 o'clock
  static const double _minBase = -math.pi / 6;        // 2 o'clock ("10:10")

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    final cx = 8 * s, cy = 8 * s;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();

    if (state == IconAnimState.success && flash > 0) {
      _paintChime(canvas, paint, cx, cy, s);
      canvas.restore();
      return;
    }

    double rotation = 0;
    if (state == IconAnimState.hovered) {
      rotation = -Curves.easeOutCubic.transform(hover) * math.pi / 3;
    } else if (state == IconAnimState.loading) {
      rotation = -loop * math.pi * 2;
    } else if (state == IconAnimState.error) {
      rotation =
          math.sin(loop * math.pi * 6) * (1.0 - loop) * math.pi / 4;
    }

    final hourAngle = _hourBase + rotation;
    final minAngle = _minBase + rotation;
    final clockR = 4.8 * s;

    // Clock face
    paint.strokeWidth = 1.5 * s;
    canvas.drawCircle(Offset(cx, cy), clockR, paint);

    // Loading: ghost minute-hand trail (momentum blur)
    if (state == IconAnimState.loading) {
      for (int i = 1; i <= 3; i++) {
        final tAng = minAngle + i * math.pi / 14;
        final trail = Paint()
          ..color = color.withValues(alpha: (1.0 - i / 4.0) * 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3 * s
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(cx, cy),
          Offset(cx + 3.6 * s * math.cos(tAng),
              cy + 3.6 * s * math.sin(tAng)),
          trail,
        );
      }
    }

    // Hour + minute hands
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + 2.4 * s * math.cos(hourAngle),
          cy + 2.4 * s * math.sin(hourAngle)),
      paint,
    );
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + 3.6 * s * math.cos(minAngle),
          cy + 3.6 * s * math.sin(minAngle)),
      paint,
    );

    // Center dot
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 0.75 * s, dotPaint);

    // CCW indicator arc at 9-o'clock edge
    double indAlpha;
    switch (state) {
      case IconAnimState.idle:
        indAlpha = 0.40 + 0.2 * hover;
      case IconAnimState.hovered:
        indAlpha = 0.45 + 0.5 * hover;
      case IconAnimState.loading:
        indAlpha = 0.55 + 0.3 * math.sin(loop * math.pi * 2);
      case IconAnimState.error:
        indAlpha = 0.40 + 0.35 * math.sin(loop * math.pi * 10).abs();
      case IconAnimState.success:
        indAlpha = 0.6;
    }

    final indR = 6.3 * s;
    final indRot = state == IconAnimState.loading ? rotation * 0.5 : 0.0;
    final indStart = 5 * math.pi / 4 + indRot;  // 10:30
    const indSweep = -math.pi / 2;               // CCW → 7:30

    final indPaint = Paint()
      ..color = color.withValues(alpha: indAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3 * s
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: indR),
      indStart, indSweep, false, indPaint,
    );

    // Arrowhead fins at CCW end of indicator
    final headAng = indStart + indSweep;
    final hx = cx + indR * math.cos(headAng);
    final hy = cy + indR * math.sin(headAng);
    final tgx = -math.sin(headAng);
    final tgy = math.cos(headAng);
    final rdx = math.cos(headAng);
    final rdy = math.sin(headAng);
    final fL = 1.3 * s;
    canvas.drawLine(
      Offset(hx, hy),
      Offset(hx + fL * (-tgx * 0.7 - rdx * 0.55),
          hy + fL * (-tgy * 0.7 - rdy * 0.55)),
      indPaint,
    );
    canvas.drawLine(
      Offset(hx, hy),
      Offset(hx + fL * (-tgx * 0.7 + rdx * 0.55),
          hy + fL * (-tgy * 0.7 + rdy * 0.55)),
      indPaint,
    );

    canvas.restore();
  }

  void _paintChime(Canvas canvas, Paint paint, double cx, double cy, double s) {
    final et = Curves.easeOutCubic.transform(flash);
    paint.strokeWidth = 1.5 * s;
    final clockR = 4.8 * s;

    canvas.drawCircle(Offset(cx, cy), clockR, paint);

    // Phase 1 (0→0.25): hands lerp toward 12:00
    final handT = (et / 0.25).clamp(0.0, 1.0);
    const tgt = -math.pi / 2;
    final hA = _hourBase + (tgt - _hourBase) * handT;
    final mA = _minBase + (tgt - _minBase) * handT;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + 2.4 * s * math.cos(hA), cy + 2.4 * s * math.sin(hA)),
      paint,
    );
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + 3.6 * s * math.cos(mA), cy + 3.6 * s * math.sin(mA)),
      paint,
    );

    final dot = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 0.75 * s, dot);

    // Phase 2: 3 pulse rings expand outward
    for (int i = 0; i < 3; i++) {
      final rT = ((et - i * 0.18) / 0.7).clamp(0.0, 1.0);
      if (rT <= 0) continue;
      final rR = clockR * (1.0 + rT * 0.8);
      final rA = (1.0 - rT) * 0.5;
      final ring = Paint()
        ..color = color.withValues(alpha: rA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1 * s;
      canvas.drawCircle(Offset(cx, cy), rR, ring);
    }
  }

  @override
  bool shouldRepaint(_HistoryPainter old) =>
      loop != old.loop || flash != old.flash || hover != old.hover ||
      state != old.state || color != old.color;
}

// 7.  BRANCHES  —  a living commit graph
//
//     Anatomy: base commit (bottom) → merge/split node (center) → two tip
//     commits (upper-left, upper-right). Nodes are circles; the edges
//     between them are the branch lines. Think of it as a small section
//     of a real git graph.
//
//     idle:    static. A node graph at rest.
//     hover:   tips drift slightly outward; two small commit dots emerge
//              from the split and glide toward the tips (reach ~70% of
//              the way). The graph is reaching forward, not jumping.
//     loading: a commit pulse travels base → split, then the pulse splits
//              and travels along BOTH branches to the tips simultaneously.
//              Loops continuously.
//     success: both tips strobe; a quadratic arc briefly rises between
//              them (a merge) and fades. The graph "completed".
//     error:   the right branch line breaks (gap grows, stays, heals).
//              The right tip jitters while the branch is severed.

class AnimatedBranchesIcon extends _AnimatedIconBase {
  const AnimatedBranchesIcon({
    super.key,
    required super.state,
    required super.color,
    super.size,
  });

  @override
  State<AnimatedBranchesIcon> createState() => _AnimatedBranchesIconState();
}

class _AnimatedBranchesIconState
    extends _AnimatedIconBaseState<AnimatedBranchesIcon> {
  // Loop runs only while actively interacting — hover, loading, error.
  // Idle is still, as it should be.
  @override
  void _applyState(IconAnimState s) {
    switch (s) {
      case IconAnimState.idle:
        _loop.stop();
        _hover.reverse();
      case IconAnimState.hovered:
        if (!_loop.isAnimating) _loop.repeat();
        _hover.forward();
      case IconAnimState.loading:
        if (!_loop.isAnimating) _loop.repeat();
        _hover.reverse();
      case IconAnimState.error:
        if (!_loop.isAnimating) _loop.repeat();
        _hover.reverse();
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted && widget.state == IconAnimState.error) {
            _loop.stop();
          }
        });
      case IconAnimState.success:
        _loop.stop();
        _hover.reverse();
        _flash.forward(from: 0);
    }
  }

  @override
  CustomPainter createPainter({
    required Color color,
    required double loopValue,
    required double flashValue,
    required double hoverValue,
    required IconAnimState state,
  }) =>
      _BranchesPainter(
        color: color, loop: loopValue, flash: flashValue,
        hover: hoverValue, state: state,
      );
}

class _BranchesPainter extends CustomPainter {
  final Color color;
  final double loop, flash, hover;
  final IconAnimState state;

  _BranchesPainter({
    required this.color, required this.loop, required this.flash,
    required this.hover, required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;

    final baseX = 8.0 * s, baseY = 13.2 * s;
    final splitX = 8.0 * s, splitY = 7.5 * s;
    final leftX = 3.2 * s, leftY = 2.8 * s;
    final rightX = 12.8 * s, rightY = 2.8 * s;
    final nodeR = 1.35 * s;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.5 * s;

    canvas.save();

    if (state == IconAnimState.success && flash > 0) {
      _paintMerge(canvas, paint, s,
          baseX, baseY, splitX, splitY, leftX, leftY, rightX, rightY, nodeR);
      canvas.restore();
      return;
    }
    if (state == IconAnimState.error) {
      _paintBreak(canvas, paint, s,
          baseX, baseY, splitX, splitY, leftX, leftY, rightX, rightY, nodeR);
      canvas.restore();
      return;
    }

    // Idle is still (loop stopped, no activity). Hover is a slow,
    // deliberate flow (~3s per commit). Loading is steadier (~1.8s).
    final double flowSpeed;
    final int nParticles;
    final double activity;
    switch (state) {
      case IconAnimState.loading:
        flowSpeed = 0.65; nParticles = 3; activity = 1.0;
      case IconAnimState.hovered:
        flowSpeed = 0.40; nParticles = 2;
        activity = 0.45 + 0.55 * hover;
      case IconAnimState.error:
        flowSpeed = 0.50; nParticles = 2; activity = 0.9;
      case IconAnimState.idle:
      case IconAnimState.success:
        flowSpeed = 0.0; nParticles = 0; activity = 0.0;
    }

    // ── Pipeline particles — compute phases once, reuse for pulses
    //    AND downstream particle rendering. The `particleTs` list is
    //    a tiny nParticles-sized (≤3) allocation; per-element pulse
    //    accumulation is fused into the same pass so we only traverse
    //    once here.
    final particleTs = List<double>.filled(nParticles, 0.0, growable: false);
    double basePulse = 0, splitPulse = 0, leftTipPulse = 0, rightTipPulse = 0;
    for (int i = 0; i < nParticles; i++) {
      final t = (loop * flowSpeed + i / nParticles) % 1.0;
      particleTs[i] = t;
      if (t < 0.10) {
        basePulse = math.max(basePulse, (1.0 - t / 0.10) * 0.75);
      }
      if (t > 0.32 && t < 0.52) {
        final prox = 1.0 - (t - 0.42).abs() / 0.10;
        splitPulse = math.max(splitPulse, prox.clamp(0.0, 1.0) * 0.85);
      }
      if (t > 0.90) {
        final decay = ((1.0 - t) / 0.10).clamp(0.0, 1.0);
        leftTipPulse = math.max(leftTipPulse, decay * 0.9);
        rightTipPulse = math.max(rightTipPulse, decay * 0.9);
      }
    }

    // ── Reusable Paints — one for shimmer, one for node halo, one
    //    for node fill-flash. Previously each helper call allocated a
    //    fresh Paint; shimmer ran 3×/frame and drawNode ran 4×/frame,
    //    for up to 14 Paint allocs per frame per icon.
    final shimmerPaint = Paint()..style = PaintingStyle.fill;
    final nodeHaloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9 * s;
    final nodeFillPaint = Paint()..style = PaintingStyle.fill;

    void shimmer(Offset a, Offset b, double phaseOffset) {
      if (activity < 0.05) return;
      final phase = (loop * flowSpeed * 0.7 + phaseOffset) % 1.0;
      final px = a.dx + (b.dx - a.dx) * phase;
      final py = a.dy + (b.dy - a.dy) * phase;
      final sA = activity * 0.4 * math.sin(phase * math.pi);
      if (sA < 0.04) return;
      shimmerPaint.color = color.withValues(alpha: sA);
      canvas.drawCircle(Offset(px, py), 0.45 * s, shimmerPaint);
    }

    paint.strokeWidth = 1.5 * s;
    canvas.drawLine(Offset(baseX, baseY), Offset(splitX, splitY), paint);
    canvas.drawLine(Offset(splitX, splitY), Offset(leftX, leftY), paint);
    canvas.drawLine(Offset(splitX, splitY), Offset(rightX, rightY), paint);

    shimmer(Offset(baseX, baseY), Offset(splitX, splitY), 0.0);
    shimmer(Offset(splitX, splitY), Offset(leftX, leftY), 0.33);
    shimmer(Offset(splitX, splitY), Offset(rightX, rightY), 0.66);

    void drawNode(double x, double y, double pulse) {
      final r = nodeR * (1.0 + pulse * 0.55);
      final center = Offset(x, y);
      if (pulse > 0.15) {
        nodeHaloPaint.color = color.withValues(alpha: pulse * 0.4);
        canvas.drawCircle(center, r + pulse * 1.3 * s, nodeHaloPaint);
      }
      canvas.drawCircle(center, r, paint);
      if (pulse > 0.05) {
        nodeFillPaint.color = color.withValues(alpha: pulse);
        canvas.drawCircle(center, r * 0.65, nodeFillPaint);
      }
    }

    drawNode(baseX, baseY, basePulse);
    drawNode(splitX, splitY, splitPulse);
    drawNode(leftX, leftY, leftTipPulse);
    drawNode(rightX, rightY, rightTipPulse);

    // Each particle leaves 2 ghost positions behind it for momentum blur.
    void drawParticle(double x, double y, double r, double a) {
      canvas.drawCircle(
        Offset(x, y), r,
        Paint()
          ..color = color.withValues(alpha: a)
          ..style = PaintingStyle.fill,
      );
    }

    for (final t in particleTs) {
      if (t <= 0.005 || t >= 0.995) continue;
      final birthFade = t < 0.08 ? t / 0.08 : 1.0;

      // 3 positions: current + 2 trail ghosts
      for (int tr = 2; tr >= 0; tr--) {
        final tt = (t - tr * 0.04).clamp(0.0, 1.0);
        if (tt <= 0.005) continue;
        final alphaMul = tr == 0 ? 1.0 : (tr == 1 ? 0.45 : 0.20);
        final radiusMul = tr == 0 ? 1.0 : (tr == 1 ? 0.82 : 0.62);

        if (tt < 0.42) {
          final u = tt / 0.42;
          final px = baseX + (splitX - baseX) * u;
          final py = baseY + (splitY - baseY) * u;
          final r = 1.25 * s * radiusMul;
          final a = activity * birthFade * alphaMul;
          drawParticle(px, py, r, a);
        } else {
          final u = (tt - 0.42) / 0.58;
          final lpx = splitX + (leftX - splitX) * u;
          final lpy = splitY + (leftY - splitY) * u;
          final rpx = splitX + (rightX - splitX) * u;
          final rpy = splitY + (rightY - splitY) * u;
          final r = 1.15 * s * radiusMul;
          final a = activity * alphaMul * (1.0 - u * 0.1);
          drawParticle(lpx, lpy, r, a);
          drawParticle(rpx, rpy, r, a);
        }
      }
    }

    void burst(double x, double y, double intensity) {
      if (intensity < 0.12) return;
      final spokeR = nodeR * 1.8 + intensity * 1.9 * s;
      final sp = Paint()
        ..color = color.withValues(alpha: intensity * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * s
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 4; i++) {
        final a = i * math.pi / 2 + math.pi / 4;
        final ix = x + nodeR * 1.4 * math.cos(a);
        final iy = y + nodeR * 1.4 * math.sin(a);
        final ox = x + spokeR * math.cos(a);
        final oy = y + spokeR * math.sin(a);
        canvas.drawLine(Offset(ix, iy), Offset(ox, oy), sp);
      }
    }

    burst(leftX, leftY, leftTipPulse);
    burst(rightX, rightY, rightTipPulse);

    canvas.restore();
  }

  void _paintMerge(Canvas canvas, Paint paint, double s,
      double baseX, double baseY, double splitX, double splitY,
      double leftX, double leftY, double rightX, double rightY, double nodeR) {
    final et = Curves.easeOutCubic.transform(flash);

    canvas.drawLine(Offset(baseX, baseY), Offset(splitX, splitY), paint);
    canvas.drawLine(Offset(splitX, splitY), Offset(leftX, leftY), paint);
    canvas.drawLine(Offset(splitX, splitY), Offset(rightX, rightY), paint);
    canvas.drawCircle(Offset(baseX, baseY), nodeR, paint);
    canvas.drawCircle(Offset(splitX, splitY), nodeR, paint);
    canvas.drawCircle(Offset(leftX, leftY), nodeR, paint);
    canvas.drawCircle(Offset(rightX, rightY), nodeR, paint);

    // Tip flash
    if (et < 0.55) {
      final fT = et / 0.55;
      final fA = math.sin(fT * math.pi) * 0.55;
      final flashP = Paint()
        ..color = color.withValues(alpha: fA)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(leftX, leftY), nodeR * 1.9, flashP);
      canvas.drawCircle(Offset(rightX, rightY), nodeR * 1.9, flashP);
    }

    // Merge arc between tips
    if (et > 0.12) {
      final mT = ((et - 0.12) / 0.88).clamp(0.0, 1.0);
      final aA = mT < 0.5 ? mT * 1.6 : (1.0 - (mT - 0.5) / 0.5) * 0.8;
      final arcP = Paint()
        ..color = color.withValues(alpha: aA.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3 * s
        ..strokeCap = StrokeCap.round;
      final midX = (leftX + rightX) / 2;
      final midY = leftY - 1.5 * s;
      final arc = Path()
        ..moveTo(leftX, leftY)
        ..quadraticBezierTo(midX, midY, rightX, rightY);
      canvas.drawPath(arc, arcP);
    }
  }

  void _paintBreak(Canvas canvas, Paint paint, double s,
      double baseX, double baseY, double splitX, double splitY,
      double leftX, double leftY, double rightX, double rightY, double nodeR) {
    final t = loop;

    canvas.drawLine(Offset(baseX, baseY), Offset(splitX, splitY), paint);
    canvas.drawLine(Offset(splitX, splitY), Offset(leftX, leftY), paint);
    canvas.drawCircle(Offset(baseX, baseY), nodeR, paint);
    canvas.drawCircle(Offset(splitX, splitY), nodeR, paint);
    canvas.drawCircle(Offset(leftX, leftY), nodeR, paint);

    // Right branch gap
    double gs, ge;
    if (t < 0.25) {
      final b = t / 0.25;
      gs = 0.3 * b; ge = 0.65 * b;
    } else if (t < 0.7) {
      gs = 0.3; ge = 0.65;
    } else {
      final h = (t - 0.7) / 0.3;
      gs = 0.3 * (1 - h); ge = 0.3 + 0.35 * (1 - h);
    }

    canvas.drawLine(
      Offset(splitX, splitY),
      Offset(splitX + (rightX - splitX) * gs, splitY + (rightY - splitY) * gs),
      paint,
    );
    canvas.drawLine(
      Offset(splitX + (rightX - splitX) * ge, splitY + (rightY - splitY) * ge),
      Offset(rightX, rightY),
      paint,
    );

    // Right tip jitters
    final jx = math.sin(t * math.pi * 14) * (1 - t) * 1.2 * s;
    final jy = math.cos(t * math.pi * 11) * (1 - t) * 0.7 * s;
    canvas.drawCircle(Offset(rightX + jx, rightY + jy), nodeR, paint);
  }

  @override
  bool shouldRepaint(_BranchesPainter old) =>
      loop != old.loop || flash != old.flash || hover != old.hover ||
      state != old.state || color != old.color;
}

// 8.  XRAY  —  a scanning eye
//
//     Anatomy: almond/oval eye outline (twin quadratic beziers), iris
//     circle, filled pupil dot, and horizontal scan lines inside the
//     eye (clipped to the oval). This isn't a magnifying glass — it's
//     a diagnostic surface that SEES THROUGH the thing you point it at.
//
//     idle:    static. Scan lines at low alpha; the eye "holds its gaze".
//     hover:   eye opens wider (oval height grows), iris dilates, scan
//              lines come forward in alpha — focusing.
//     loading: three scan lines sweep top→bottom at offset phases (active
//              scan). A sonar ring expands from the iris each cycle. The
//              eye itself breathes subtly.
//     success: eye blinks (closes, reopens), pupil emerges as a check
//              ring with a tiny checkmark drawn into it.
//     error:   whole icon shakes horizontally. Scan lines scramble
//              (random angles each frame). Pupil becomes a small X.

class AnimatedXrayIcon extends _AnimatedIconBase {
  const AnimatedXrayIcon({
    super.key,
    required super.state,
    required super.color,
    super.size,
  });

  @override
  State<AnimatedXrayIcon> createState() => _AnimatedXrayIconState();
}

class _AnimatedXrayIconState
    extends _AnimatedIconBaseState<AnimatedXrayIcon> {
  @override
  CustomPainter createPainter({
    required Color color,
    required double loopValue,
    required double flashValue,
    required double hoverValue,
    required IconAnimState state,
  }) =>
      _XrayPainter(
        color: color, loop: loopValue, flash: flashValue,
        hover: hoverValue, state: state,
      );
}

class _XrayPainter extends CustomPainter {
  final Color color;
  final double loop, flash, hover;
  final IconAnimState state;

  _XrayPainter({
    required this.color, required this.loop, required this.flash,
    required this.hover, required this.state,
  });

  Path _eye(double cx, double cy, double halfW, double halfH) => Path()
    ..moveTo(cx - halfW, cy)
    ..quadraticBezierTo(cx, cy - halfH, cx + halfW, cy)
    ..quadraticBezierTo(cx, cy + halfH, cx - halfW, cy)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    final cx = 8 * s, cy = 8 * s;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();

    if (state == IconAnimState.success && flash > 0) {
      _paintBlink(canvas, paint, cx, cy, s);
      canvas.restore();
      return;
    }
    if (state == IconAnimState.error) {
      _paintScramble(canvas, paint, cx, cy, s);
      canvas.restore();
      return;
    }

    // Each stage depends on the one before it. On hover, this plays out as
    // a story in 250ms. On loading, all stages run concurrently in loops.

    double halfW = 6.3 * s;
    double halfH = 3.4 * s;
    double irisR = 2.3 * s;
    double pupilGazeX = 0, pupilGazeY = 0;
    double refocusR = 0, refocusA = 0;
    double scanTopA = 0, scanMidA = 0, scanBotA = 0;
    double irisHighlightAngle = -math.pi * 0.7;
    double irisHighlightA = 0;

    if (state == IconAnimState.hovered) {
      final h = hover;  // raw for precise staging
      // Stage 1: eyelid retracts (0 → 0.35)
      final lidT = (h / 0.35).clamp(0.0, 1.0);
      halfH += 0.65 * s * Curves.easeOutCubic.transform(lidT);
      // Stage 2: pupil darts to examine (0.2 → 0.7)
      final gazeT = ((h - 0.2) / 0.5).clamp(0.0, 1.0);
      pupilGazeX = math.sin(gazeT * math.pi * 1.6) * 0.95 * s;
      pupilGazeY = math.cos(gazeT * math.pi * 2.2) * 0.3 * s * (1.0 - gazeT);
      // Stage 3: iris dilates in response to the gaze (0.35 → 0.8)
      final dilateT = ((h - 0.35) / 0.45).clamp(0.0, 1.0);
      irisR += 0.45 * s * Curves.easeOutCubic.transform(dilateT);
      // Stage 4: refocus ring emerges from iris (0.55 → 1.0)
      final refocusT = ((h - 0.55) / 0.45).clamp(0.0, 1.0);
      if (refocusT > 0) {
        refocusR = irisR + 0.3 * s + refocusT * 1.8 * s;
        refocusA = math.sin(refocusT * math.pi) * 0.55;
      }
      // Stage 5: scan lines illuminate in sequence (staggered)
      scanTopA = ((h - 0.28) / 0.35).clamp(0.0, 1.0) * 0.55;
      scanMidA = ((h - 0.42) / 0.35).clamp(0.0, 1.0) * 0.55;
      scanBotA = ((h - 0.56) / 0.35).clamp(0.0, 1.0) * 0.55;
      // Iris highlight brightens as the eye focuses
      irisHighlightA = dilateT * 0.45;
    } else if (state == IconAnimState.loading) {
      // Eye breathes (lid + iris oscillate at offset phases)
      halfH += math.sin(loop * math.pi * 2) * 0.35 * s;
      irisR += math.sin(loop * math.pi * 2 + math.pi * 0.6) * 0.2 * s;
      // Pupil reads horizontally (back-and-forth)
      pupilGazeX = math.sin(loop * math.pi * 2) * 1.2 * s;
      pupilGazeY = math.sin(loop * math.pi * 4) * 0.18 * s;
      // Iris highlight rotates (like light catching a wet eye)
      irisHighlightAngle = -math.pi * 0.7 + loop * math.pi * 2;
      irisHighlightA = 0.4;
      // Scan lines handled specially below (sweep animation)
    } else {
      // idle: very faint scan lines; fades as hover settles
      scanTopA = 0.18 * (1.0 - hover);
      scanMidA = 0.22 * (1.0 - hover);
      scanBotA = 0.18 * (1.0 - hover);
    }

    paint.strokeWidth = 1.5 * s;
    canvas.drawPath(_eye(cx, cy, halfW, halfH), paint);

    canvas.save();
    canvas.clipPath(_eye(cx, cy, halfW - 0.8 * s, halfH - 0.5 * s));
    if (state == IconAnimState.loading) {
      // Three sweeping scan lines at offset phases
      for (int i = 0; i < 3; i++) {
        final phase = (loop * (1.0 + i * 0.15) + i * 0.33) % 1.0;
        final y = cy - halfH + phase * (halfH * 2);
        final dist = (y - cy).abs();
        final a = (dist < halfH * 0.85
            ? 0.65 - dist / halfH * 0.35
            : 0.0).clamp(0.0, 1.0);
        canvas.drawLine(
          Offset(cx - halfW + 1 * s, y),
          Offset(cx + halfW - 1 * s, y),
          Paint()
            ..color = color.withValues(alpha: a)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0 * s
            ..strokeCap = StrokeCap.round,
        );
      }
    } else {
      // Static three-line array; alpha computed per-line from stage timing
      final pairs = [
        (cy - halfH * 0.55, scanTopA),
        (cy, scanMidA),
        (cy + halfH * 0.55, scanBotA),
      ];
      final scanPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9 * s
        ..strokeCap = StrokeCap.round;
      final lineL = cx - halfW + 1.5 * s;
      final lineR = cx + halfW - 1.5 * s;
      for (final pair in pairs) {
        final y = pair.$1;
        final a = pair.$2;
        if (a <= 0.01) continue;
        scanPaint.color = color.withValues(alpha: a);
        canvas.drawLine(Offset(lineL, y), Offset(lineR, y), scanPaint);
      }
    }
    canvas.restore();

    if (refocusA > 0.01) {
      canvas.drawCircle(
        Offset(cx, cy), refocusR,
        Paint()
          ..color = color.withValues(alpha: refocusA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9 * s,
      );
    }

    paint.strokeWidth = 1.3 * s;
    canvas.drawCircle(Offset(cx, cy), irisR, paint);

    if (irisHighlightA > 0.01) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: irisR - 0.25 * s),
        irisHighlightAngle, 0.8, false,
        Paint()
          ..color = color.withValues(alpha: irisHighlightA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 * s
          ..strokeCap = StrokeCap.round,
      );
    }

    // Clamp gaze so pupil can't leave the iris
    final maxGaze = irisR - 0.9 * s;
    final gazeMag = math.sqrt(pupilGazeX * pupilGazeX + pupilGazeY * pupilGazeY);
    if (gazeMag > maxGaze) {
      pupilGazeX *= maxGaze / gazeMag;
      pupilGazeY *= maxGaze / gazeMag;
    }
    canvas.drawCircle(
      Offset(cx + pupilGazeX, cy + pupilGazeY), 0.7 * s,
      Paint()..color = color..style = PaintingStyle.fill,
    );

    if (state == IconAnimState.loading) {
      // Two sonar rings at offset phases for a continuous feel
      for (int i = 0; i < 2; i++) {
        final sT = (loop + i * 0.5) % 1.0;
        final sR = irisR + sT * (halfW - irisR);
        final sA = (1.0 - sT) * 0.32 * (sT < 0.1 ? sT / 0.1 : 1.0);
        canvas.drawCircle(
          Offset(cx, cy), sR,
          Paint()
            ..color = color.withValues(alpha: sA)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9 * s,
        );
      }
    }

    canvas.restore();
  }

  void _paintBlink(Canvas canvas, Paint paint, double cx, double cy, double s) {
    final et = Curves.easeOutCubic.transform(flash);
    paint.strokeWidth = 1.5 * s;
    final halfW = 6.3 * s;

    double halfH;
    if (et < 0.28) {
      halfH = 3.4 * s * (1.0 - (et / 0.28) * 0.92);
    } else if (et < 0.55) {
      halfH = 3.4 * s * (0.08 + ((et - 0.28) / 0.27) * 0.92);
    } else {
      halfH = 3.4 * s;
    }

    canvas.drawPath(_eye(cx, cy, halfW, halfH), paint);

    if (halfH > 1.5 * s) {
      paint.strokeWidth = 1.3 * s;
      canvas.drawCircle(Offset(cx, cy), 2.3 * s, paint);

      if (et > 0.58) {
        final cT = ((et - 0.58) / 0.42).clamp(0.0, 1.0);
        // Check ring
        canvas.drawCircle(
          Offset(cx, cy), 1.35 * s,
          Paint()
            ..color = color.withValues(alpha: cT * 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9 * s,
        );
        // Tiny check
        paint.strokeWidth = 1.1 * s;
        final check = Path()
          ..moveTo(cx - 0.8 * s, cy + 0.05 * s)
          ..lineTo(cx - 0.15 * s, cy + 0.7 * s)
          ..lineTo(cx + 1.05 * s, cy - 0.65 * s);
        final cm = check.computeMetrics().first;
        canvas.drawPath(cm.extractPath(0, cm.length * cT), paint);
      } else {
        canvas.drawCircle(
          Offset(cx, cy), 0.7 * s,
          Paint()..color = color..style = PaintingStyle.fill,
        );
      }
    }
  }

  void _paintScramble(Canvas canvas, Paint paint, double cx, double cy, double s) {
    final t = loop;
    final shake = math.sin(t * math.pi * 10) * (1 - t) * 1.5 * s;

    canvas.save();
    canvas.translate(shake, 0);

    paint.strokeWidth = 1.5 * s;
    final halfW = 6.3 * s, halfH = 3.4 * s;
    final ep = _eye(cx, cy, halfW, halfH);
    canvas.drawPath(ep, paint);

    paint.strokeWidth = 1.3 * s;
    canvas.drawCircle(Offset(cx, cy), 2.3 * s, paint);

    // X pupil
    final xL = 0.85 * s;
    final glitch = math.sin(t * math.pi * 8) * (1 - t) * 0.25 * s;
    paint.strokeWidth = 1.2 * s;
    canvas.drawLine(Offset(cx - xL + glitch, cy - xL),
        Offset(cx + xL + glitch, cy + xL), paint);
    canvas.drawLine(Offset(cx - xL + glitch, cy + xL),
        Offset(cx + xL + glitch, cy - xL), paint);

    // Scrambled scan lines
    canvas.save();
    canvas.clipPath(ep);
    final sp = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9 * s
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 3; i++) {
      final seed = i * 1.3 + t * 8;
      final y1 = cy + math.sin(seed) * halfH * 0.65;
      final y2 = cy + math.cos(seed * 1.3) * halfH * 0.65;
      canvas.drawLine(
        Offset(cx - halfW + 1 * s, y1),
        Offset(cx + halfW - 1 * s, y2), sp,
      );
    }
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(_XrayPainter old) =>
      loop != old.loop || flash != old.flash || hover != old.hover ||
      state != old.state || color != old.color;
}

// 9.  SETTINGS  —  a mechanical gear
//
//     Anatomy: 6-tooth gear, filled (evenOdd rule punches the center hole).
//     A stroked inner circle sharpens the hole's rim. Unlike the other
//     icons this one uses FILL for the body — a gear should feel solid.
//
//     idle:    still. A faint glint arc drifts on the inner rim (driven
//              by hover settling), as if light catches polished metal.
//     hover:   gear rotates one tooth-step (60° clockwise). No spinning
//              — just a single deliberate click, like engaging a mode.
//     loading: continuous CW rotation (half revolution per 1.2s). Steady
//              mechanical pace.
//     success: easeOutBack snap to a tooth-aligned rest position; a
//              checkmark draws itself inside the center hole.
//     error:   gear stutters back-and-forth (damped sin) — a jammed
//              mechanism. Occasional bright sparks pop at the top tooth.

class AnimatedSettingsIcon extends _AnimatedIconBase {
  const AnimatedSettingsIcon({
    super.key,
    required super.state,
    required super.color,
    super.size,
  });

  @override
  State<AnimatedSettingsIcon> createState() => _AnimatedSettingsIconState();
}

class _AnimatedSettingsIconState
    extends _AnimatedIconBaseState<AnimatedSettingsIcon> {
  @override
  CustomPainter createPainter({
    required Color color,
    required double loopValue,
    required double flashValue,
    required double hoverValue,
    required IconAnimState state,
  }) =>
      _SettingsPainter(
        color: color, loop: loopValue, flash: flashValue,
        hover: hoverValue, state: state,
      );
}

class _SettingsPainter extends CustomPainter {
  final Color color;
  final double loop, flash, hover;
  final IconAnimState state;

  _SettingsPainter({
    required this.color, required this.loop, required this.flash,
    required this.hover, required this.state,
  });

  Path _gearPath(
      double cx, double cy, double tipR, double rootR, int n, double rot) {
    final period = 2 * math.pi / n;
    final tipHalf = period * 0.14;
    final rootHalf = period * 0.22;
    final path = Path();
    bool first = true;

    for (int i = 0; i < n; i++) {
      final c = rot + i * period;
      final angles = [c - rootHalf, c - tipHalf, c + tipHalf, c + rootHalf];
      final radii = [rootR, tipR, tipR, rootR];
      for (int j = 0; j < 4; j++) {
        final x = cx + radii[j] * math.cos(angles[j]);
        final y = cy + radii[j] * math.sin(angles[j]);
        if (first) { path.moveTo(x, y); first = false; }
        else { path.lineTo(x, y); }
      }
      final arcStart = c + rootHalf;
      final arcSweep = (rot + (i + 1) * period - rootHalf) - arcStart;
      if (arcSweep.abs() > 0.001) {
        path.arcTo(
          Rect.fromCircle(center: Offset(cx, cy), radius: rootR),
          arcStart, arcSweep, false,
        );
      }
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    final cx = 8 * s, cy = 8 * s;

    canvas.save();

    if (state == IconAnimState.success && flash > 0) {
      _paintSnap(canvas, cx, cy, s);
      canvas.restore();
      return;
    }

    // ── Two gears interacting. Outer rotates CW; inner (visible through
    //    the hole) rotates CCW at a different rate. On hover the inner
    //    fades INTO EXISTENCE — a hidden mechanism being revealed. On
    //    loading both spin continuously and spark at the mesh point. A
    //    stationary pin at 12 o'clock ticks each time an outer tooth
    //    passes beneath it, like a ratchet. ──
    double outerRot = 0, innerRot = 0, innerReveal = 0;
    if (state == IconAnimState.hovered) {
      final h = Curves.easeOutCubic.transform(hover);
      outerRot = h * math.pi / 3;           // one tooth step CW
      innerRot = -h * math.pi / 2;          // CCW, further
      innerReveal = h;                       // fade in
    } else if (state == IconAnimState.loading) {
      outerRot = loop * math.pi;             // half rev / cycle CW
      innerRot = -loop * math.pi * 1.6;      // CCW, faster
      innerReveal = 1.0;
    } else if (state == IconAnimState.error) {
      // Jam: different frequencies make the two gears feel "fighting"
      outerRot = math.sin(loop * math.pi * 8) * (1 - loop) * math.pi / 10;
      innerRot = math.sin(loop * math.pi * 13) * (1 - loop) * math.pi / 6;
      innerReveal = 1.0;
    } else {
      innerReveal = hover;  // settles back to 0 as hover reverses
    }

    final tipR = 5.7 * s, rootR = 4.2 * s;
    final outerHole = 2.3 * s;  // slightly larger to fit inner gear
    final innerTipR = 1.85 * s, innerRootR = 1.3 * s;

    final gear = _gearPath(cx, cy, tipR, rootR, 6, outerRot)
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: outerHole))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      gear,
      Paint()..color = color..style = PaintingStyle.fill,
    );

    // 4-tooth small gear. Always drawn inside the hole clip so it never
    // escapes. Alpha comes from `innerReveal`.
    if (innerReveal > 0.02) {
      canvas.save();
      canvas.clipPath(Path()
        ..addOval(Rect.fromCircle(
            center: Offset(cx, cy), radius: outerHole - 0.15 * s)));
      final innerGear = _gearPath(cx, cy, innerTipR, innerRootR, 4, innerRot)
        ..fillType = PathFillType.nonZero;
      canvas.drawPath(
        innerGear,
        Paint()
          ..color = color.withValues(alpha: innerReveal * 0.9)
          ..style = PaintingStyle.fill,
      );
      canvas.restore();
    }

    canvas.drawCircle(
      Offset(cx, cy), outerHole,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 * s,
    );

    // ── Mesh sparks: where outer teeth "meet" inner teeth. Fires only
    //    when a tooth of each aligns at the 3-o'clock mesh point. ──
    if (state == IconAnimState.loading) {
      // Outer tooth nearest 3 o'clock: 3oc = angle 0, outer teeth at i*π/3 + outerRot
      // nearness = cos of angular diff to 0
      final outerNear =
          math.cos(outerRot) + math.cos(outerRot - math.pi / 3).abs() * 0.3;
      final innerNear = math.cos(innerRot);
      final align = (outerNear.clamp(0.0, 1.0) * innerNear.clamp(0.0, 1.0))
          .clamp(0.0, 1.0);
      if (align > 0.55) {
        final meshX = cx + outerHole * 1.02;
        final meshY = cy;
        final intensity = (align - 0.55) / 0.45;
        canvas.drawCircle(
          Offset(meshX, meshY), 0.55 * s,
          Paint()
            ..color = color.withValues(alpha: intensity * 0.7)
            ..style = PaintingStyle.fill,
        );
        // Tiny radiating spark lines
        final sp = Paint()
          ..color = color.withValues(alpha: intensity * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5 * s
          ..strokeCap = StrokeCap.round;
        for (int i = 0; i < 3; i++) {
          final a = (i - 1) * 0.45;
          canvas.drawLine(
            Offset(meshX, meshY),
            Offset(meshX + 0.9 * s * math.cos(a),
                meshY + 0.9 * s * math.sin(a)),
            sp,
          );
        }
      }
    }

    // The pin is a small inward-pointing mark just above the outer tip.
    // Its alpha spikes when an outer tooth aligns with 12 o'clock.
    {
      // Angular distance of nearest tooth to -π/2 (12 o'clock)
      double minDelta = math.pi;
      for (int i = 0; i < 6; i++) {
        final toothAng = outerRot + i * math.pi / 3;
        // Normalize delta from -π/2
        double d = (toothAng - (-math.pi / 2)) % (math.pi * 2);
        if (d > math.pi) d -= math.pi * 2;
        if (d < -math.pi) d += math.pi * 2;
        if (d.abs() < minDelta) minDelta = d.abs();
      }
      // Tick when tooth is within ±10° of 12
      final tick = (1.0 - (minDelta / (math.pi / 18)).clamp(0.0, 1.0));
      final pinBaseA = 0.4 + 0.5 * tick;
      final pinX = cx;
      final pinTopY = cy - tipR - 0.9 * s;
      final pinBotY = cy - tipR - 0.15 * s;
      canvas.drawLine(
        Offset(pinX, pinTopY), Offset(pinX, pinBotY),
        Paint()
          ..color = color.withValues(alpha: pinBaseA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1 * s
          ..strokeCap = StrokeCap.round,
      );
      // Brief flare on tick
      if (tick > 0.3) {
        canvas.drawCircle(
          Offset(pinX, pinBotY - 0.2 * s), 0.6 * s * tick,
          Paint()
            ..color = color.withValues(alpha: tick * 0.6)
            ..style = PaintingStyle.fill,
        );
      }
    }

    if (state == IconAnimState.error) {
      final si = math.sin(loop * math.pi * 8).abs() * (1 - loop);
      if (si > 0.15) {
        final sa = -math.pi / 2 + outerRot;
        final sx = cx + tipR * math.cos(sa);
        final sy = cy + tipR * math.sin(sa);
        canvas.drawCircle(
          Offset(sx, sy), 0.8 * s,
          Paint()
            ..color = color.withValues(alpha: si * 0.85)
            ..style = PaintingStyle.fill,
        );
        final lp = Paint()
          ..color = color.withValues(alpha: si * 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6 * s
          ..strokeCap = StrokeCap.round;
        for (int i = 0; i < 3; i++) {
          final a = sa + (i - 1) * 0.55;
          canvas.drawLine(
            Offset(sx, sy),
            Offset(sx + 1.3 * s * math.cos(a), sy + 1.3 * s * math.sin(a)),
            lp,
          );
        }
      }
    }

    canvas.restore();
  }

  void _paintSnap(Canvas canvas, double cx, double cy, double s) {
    final et = flash;
    // easeOutBack briefly overshoots past 1 then settles to 1
    final outerSnap = -math.pi / 2 * Curves.easeOutBack.transform(et);
    // Inner gear spins down with damping, aligning then yielding to the check
    final innerSnap = math.pi / 4 *
        (1.0 - Curves.easeOutCubic.transform(et.clamp(0.0, 1.0)));

    final tipR = 5.7 * s, rootR = 4.2 * s, outerHole = 2.3 * s;
    final innerTipR = 1.85 * s, innerRootR = 1.3 * s;

    final gear = _gearPath(cx, cy, tipR, rootR, 6, outerSnap)
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: outerHole))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      gear,
      Paint()..color = color..style = PaintingStyle.fill,
    );

    // Inner gear fades out as the checkmark takes over
    final innerAlpha = (1.0 - (et / 0.55).clamp(0.0, 1.0)) * 0.9;
    if (innerAlpha > 0.02) {
      canvas.save();
      canvas.clipPath(Path()
        ..addOval(Rect.fromCircle(
            center: Offset(cx, cy), radius: outerHole - 0.15 * s)));
      final innerGear =
          _gearPath(cx, cy, innerTipR, innerRootR, 4, innerSnap)
            ..fillType = PathFillType.nonZero;
      canvas.drawPath(
        innerGear,
        Paint()
          ..color = color.withValues(alpha: innerAlpha)
          ..style = PaintingStyle.fill,
      );
      canvas.restore();
    }

    canvas.drawCircle(
      Offset(cx, cy), outerHole,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 * s,
    );

    // Checkmark inside center hole
    if (et > 0.45) {
      final cT = ((et - 0.45) / 0.55).clamp(0.0, 1.0);
      final check = Path()
        ..moveTo(cx - 1.05 * s, cy)
        ..lineTo(cx - 0.3 * s, cy + 0.85 * s)
        ..lineTo(cx + 1.15 * s, cy - 0.8 * s);
      final cm = check.computeMetrics().first;
      canvas.drawPath(
        cm.extractPath(0, cm.length * cT),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 * s
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SettingsPainter old) =>
      loop != old.loop || flash != old.flash || hover != old.hover ||
      state != old.state || color != old.color;
}
