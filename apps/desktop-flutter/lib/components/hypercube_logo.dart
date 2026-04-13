import 'dart:math' as math;
import 'dart:ui' show ViewFocusEvent, ViewFocusState;
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:provider/provider.dart';
import '../app/preferences_state.dart';
import '../app/hyper_reactivity.dart';
import '../ui/tokens.dart';
import 'hypercube_logo_engine.dart';

class HypercubeLogo extends StatefulWidget {
  final double size;
  final double speed;

  const HypercubeLogo({
    super.key,
    this.size = 24,
    this.speed = 0.85,
  });

  @override
  State<HypercubeLogo> createState() => _HypercubeLogoState();
}

class _HypercubeLogoState extends State<HypercubeLogo>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  late final HypercubeLogoEngine _engine;
  Duration? _lastElapsed;
  bool _isTickerModeVisible = true;
  bool _animateWhenUnfocused = true;
  bool _reduceMotion = false;
  bool _hasViewFocus = true;
  AppLifecycleState? _appLifecycleState;
  PreferencesState? _prefs;

  @override
  void initState() {
    super.initState();
    _engine = HypercubeLogoEngine();
    _appLifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isTickerModeVisible = TickerMode.of(context);

    // Use a manual listener so only logoAnimatesWhenUnfocused changes (not all
    // of PreferencesState) trigger _syncTicker — equivalent to context.select
    // but valid outside of build().
    final prefs = context.read<PreferencesState>();
    final bool isFirstPrefSync = _prefs == null;
    if (_prefs != prefs) {
      _prefs?.removeListener(_onPrefsChanged);
      _prefs = prefs;
      _prefs!.addListener(_onPrefsChanged);
      _animateWhenUnfocused = prefs.logoAnimatesWhenUnfocused;
      _reduceMotion = prefs.reduceMotion;
      // Fresh mount with reduce-motion already on: randomize the frozen
      // pose so cold launches don't all show the same still image.
      // Mid-session toggles (handled in _onPrefsChanged) never randomize
      // — they preserve whatever pose the user was looking at.
      if (_reduceMotion) {
        _engine.setReduced(true, randomizeOnEnter: isFirstPrefSync);
      }
    }

    _syncTicker();
  }

  void _onPrefsChanged() {
    final prefs = _prefs!;
    final newAnimate = prefs.logoAnimatesWhenUnfocused;
    final newReduce = prefs.reduceMotion;
    if (newAnimate != _animateWhenUnfocused || newReduce != _reduceMotion) {
      _animateWhenUnfocused = newAnimate;
      if (newReduce != _reduceMotion) {
        _reduceMotion = newReduce;
        // Mid-session toggle: freeze where we are (or thaw from there).
        // Never randomize — that would be a jarring pose jump and defeat
        // the whole "graceful stop" fantasy.
        _engine.setReduced(newReduce, randomizeOnEnter: false);
      }
      _syncTicker();
    }
  }

  void _syncTicker() {
    // Reduce motion: the engine needs a few hundred ms of ticking to
    // gracefully lerp to its rest pose. Keep the ticker running until
    // [isAtReducedRest] flips true; after that _tick() self-stops.
    if (_reduceMotion) {
      if (!_engine.isAtReducedRest && !_ticker.isActive) {
        _lastElapsed = null;
        _ticker.start();
      }
      return;
    }
    final AppLifecycleState lifecycleState =
        _appLifecycleState ?? AppLifecycleState.resumed;
    final bool isFocused =
        lifecycleState == AppLifecycleState.resumed && _hasViewFocus;
    final bool shouldRun =
        _isTickerModeVisible && (_animateWhenUnfocused || isFocused);
    if (shouldRun) {
      if (!_ticker.isActive) {
        _lastElapsed = null;
        _ticker.start();
      }
      return;
    }
    if (_ticker.isActive) {
      _ticker.stop();
      _lastElapsed = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    _syncTicker();
    if (state == AppLifecycleState.resumed || !mounted) {
      return;
    }
    _clearInteractionState();
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (!mounted || event.viewId != View.of(context).viewId) {
      return;
    }
    _hasViewFocus = event.state == ViewFocusState.focused;
    _syncTicker();
    if (_hasViewFocus) {
      return;
    }
    _clearInteractionState();
  }

  void _clearInteractionState() {
    final bool wasDragging = _engine.dragging;
    setState(() {
      if (wasDragging) {
        _engine.setDragging(false);
      }
      _engine.handlePointerExit();
    });
    if (wasDragging) {
      context.read<HyperReactivity>().deactivate();
    }
  }

  @override
  void dispose() {
    _prefs?.removeListener(_onPrefsChanged);
    WidgetsBinding.instance.removeObserver(this);
    context.read<HyperReactivity>().deactivate();
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    if (_lastElapsed == null) {
      _lastElapsed = elapsed;
      return;
    }

    final int deltaMicros =
        elapsed.inMicroseconds - _lastElapsed!.inMicroseconds;
    _lastElapsed = elapsed;
    final double dt = (deltaMicros / Duration.microsecondsPerSecond)
        .clamp(0, 0.033)
        .toDouble();
    _engine.step(dt, speed: widget.speed);

    if (mounted) {
      setState(() {});
    }

    // Reduce-motion self-stop: once the engine has eased into its rest
    // pose, kill the ticker so we stop painting frames. The widget will
    // hold at the canonical pose until reduce-motion is toggled off.
    if (_reduceMotion && _engine.isAtReducedRest && _ticker.isActive) {
      _ticker.stop();
      _lastElapsed = null;
    }
  }

  void _updatePointer(Offset localPosition, {Offset? globalPosition}) {
    final double half = widget.size / 2;
    final Offset delta = localPosition - Offset(half, half);
    _engine.updatePointer(delta: delta, size: widget.size);
    if (_engine.dragging) {
      context.read<HyperReactivity>().activate(
            _engine.near + 1,
            dragOffset: delta,
            normalizedOffset: _engine.tilt,
            globalPosition: globalPosition ?? Offset.zero,
          );
    }
  }

  void _releaseDrag() {
    setState(() => _engine.setDragging(false));
    context.read<HyperReactivity>().deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final HypercubeProjectedData projected = _engine.projectedData(widget.size);
    return MouseRegion(
      cursor: _engine.dragging
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.click,
      onExit: (_) {
        if (!_engine.dragging) {
          _engine.handlePointerExit();
        }
      },
      onHover: (PointerHoverEvent event) => _updatePointer(
        event.localPosition,
        globalPosition: event.position,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (DragStartDetails details) {
          _engine.setDragging(true);
          _updatePointer(
            details.localPosition,
            globalPosition: details.globalPosition,
          );
          // In reduced mode the ticker may have stopped after the cube
          // settled. Drag is intentional motion — wake the ticker so
          // warp updates render live. _tick self-stops again after the
          // drag releases and the post-drag damping decays to zero.
          if (_reduceMotion && !_ticker.isActive) {
            _lastElapsed = null;
            _ticker.start();
          }
        },
        onPanUpdate: (DragUpdateDetails details) {
          _updatePointer(
            details.localPosition,
            globalPosition: details.globalPosition,
          );
        },
        onPanEnd: (_) => _releaseDrag(),
        onPanCancel: _releaseDrag,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: HypercubeLogoPainter(
              projected: projected,
              near: _engine.near,
              dragging: _engine.dragging,
              colors: HypercubeLogoColors.fromTokens(tokens),
            ),
          ),
        ),
      ),
    );
  }
}

class HypercubeLogoColors {
  final Color chromatic1;
  final Color chromatic2;
  final Color core;

  const HypercubeLogoColors({
    required this.chromatic1,
    required this.chromatic2,
    required this.core,
  });

  factory HypercubeLogoColors.fromTokens(AppTokens tokens) {
    return HypercubeLogoColors(
      chromatic1: tokens.hyperChromatic1,
      chromatic2: tokens.hyperChromatic2,
      core: tokens.hyperCore,
    );
  }
}

class HypercubeLogoPainter extends CustomPainter {
  final HypercubeProjectedData projected;
  final double near;
  final bool dragging;
  final HypercubeLogoColors colors;

  const HypercubeLogoPainter({
    required this.projected,
    required this.near,
    required this.dragging,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    // Pass mapping mirrors TS exactly:
    // home/ghost -> chromatic2, connectors -> chromatic1, main -> core.
    _drawEdgePass(
      canvas,
      projected.home,
      colors.chromatic2,
      strokeWidth: 0.32,
      opacity: near * 0.35 + (dragging ? 0.3 : 0),
    );
    _drawConnectorPass(canvas, projected.main, projected.home);
    _drawMainPass(canvas, projected.main);
    _drawEdgePass(
      canvas,
      projected.ghost,
      colors.chromatic2,
      strokeWidth: 0.1,
      opacity: near * 0.15,
      dashLength: 1,
      gapLength: 5,
    );
  }

  void _drawEdgePass(
    Canvas canvas,
    List<HypercubeProjectedPoint> points,
    Color color, {
    required double strokeWidth,
    required double opacity,
    double? dashLength,
    double? gapLength,
  }) {
    if (opacity <= 0.01) {
      return;
    }
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color.withValues(alpha: opacity.clamp(0, 1).toDouble());
    for (final (int i, int j) in hypercubeEdges) {
      final Offset start = points[i].point;
      final Offset end = points[j].point;
      if (dashLength != null && gapLength != null) {
        _drawDashedLine(canvas, start, end, paint, dashLength, gapLength);
      } else {
        canvas.drawLine(start, end, paint);
      }
    }
  }

  void _drawConnectorPass(
    Canvas canvas,
    List<HypercubeProjectedPoint> main,
    List<HypercubeProjectedPoint> home,
  ) {
    if (!dragging) {
      return;
    }
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.12
      ..color = colors.chromatic1.withValues(alpha: 0.45);
    for (int i = 0; i < main.length; i++) {
      _drawDashedLine(canvas, main[i].point, home[i].point, paint, 0.4, 3);
    }
  }

  void _drawMainPass(Canvas canvas, List<HypercubeProjectedPoint> points) {
    final bool useEffects = near > 0.05 || dragging;
    final double glowBlurSigma = _blurSigma(0.6 + near * 0.5);
    final double saturationBoost = 1.8 + near * 1.5;
    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint leftPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint rightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (useEffects) {
      glowPaint.maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlurSigma);
    }

    for (final (int i, int j) in hypercubeEdges) {
      final HypercubeProjectedPoint p1 = points[i];
      final HypercubeProjectedPoint p2 = points[j];
      final double torsion = (p1.w - p2.w).abs() + (p1.z - p2.z).abs() * 0.5;
      final double stress =
          (torsion * (1.2 + near * 0.8)).clamp(0, 1.5).toDouble();
      final double depth = (p1.z + p2.z) * 0.5 + (p1.w + p2.w) * 0.5;
      final double opacity = (0.25 + near * 0.25 + depth * 0.08) < 0.05
          ? 0.05
          : (0.25 + near * 0.25 + depth * 0.08);
      final double strokeWidth =
          0.45 + opacity * 1.5 + (dragging ? 0.8 : 0) + stress * 0.4;
      final bool dashed = stress > 1.1;
      final double coreAlpha = (opacity + stress * 0.15).clamp(0, 1).toDouble();

      if (useEffects) {
        glowPaint
          ..strokeWidth = strokeWidth
          ..color = colors.core.withValues(
            alpha: (coreAlpha * 0.5 * (saturationBoost / 1.8))
                .clamp(0, 1)
                .toDouble(),
          );
        _drawEdgeLine(canvas, p1.point, p2.point, glowPaint, dashed);

        leftPaint
          ..strokeWidth = strokeWidth
          ..color = colors.chromatic1.withValues(alpha: coreAlpha);
        _drawEdgeLine(
          canvas,
          p1.point.translate(-0.4, 0),
          p2.point.translate(-0.4, 0),
          leftPaint,
          dashed,
        );

        rightPaint
          ..strokeWidth = strokeWidth
          ..color = colors.chromatic2.withValues(alpha: coreAlpha);
        _drawEdgeLine(
          canvas,
          p1.point.translate(0.4, 0),
          p2.point.translate(0.4, 0),
          rightPaint,
          dashed,
        );
      }

      corePaint
        ..strokeWidth = strokeWidth
        ..color = colors.core.withValues(alpha: coreAlpha);
      _drawEdgeLine(canvas, p1.point, p2.point, corePaint, dashed);
    }
  }

  void _drawEdgeLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    bool dashed,
  ) {
    if (!dashed) {
      canvas.drawLine(start, end, paint);
      return;
    }
    _drawDashedLine(canvas, start, end, paint, 0.2, 1.8);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    double dashLength,
    double gapLength,
  ) {
    if (dashLength <= 0 || gapLength <= 0) {
      canvas.drawLine(start, end, paint);
      return;
    }
    final double dx = end.dx - start.dx;
    final double dy = end.dy - start.dy;
    final double length = math.sqrt(dx * dx + dy * dy);
    if (length <= 0) {
      return;
    }
    final double invLength = 1 / length;
    final double stepX = dx * invLength;
    final double stepY = dy * invLength;
    double distance = 0;
    while (distance < length) {
      final double next = math.min(distance + dashLength, length);
      canvas.drawLine(
        Offset(start.dx + stepX * distance, start.dy + stepY * distance),
        Offset(start.dx + stepX * next, start.dy + stepY * next),
        paint,
      );
      distance += dashLength + gapLength;
    }
  }

  double _blurSigma(double stdDeviation) {
    return stdDeviation * 0.57735 + 0.5;
  }

  @override
  bool shouldRepaint(HypercubeLogoPainter oldDelegate) {
    return oldDelegate.projected != projected ||
        oldDelegate.near != near ||
        oldDelegate.dragging != dragging ||
        oldDelegate.colors.chromatic1 != colors.chromatic1 ||
        oldDelegate.colors.chromatic2 != colors.chromatic2 ||
        oldDelegate.colors.core != colors.core;
  }
}
