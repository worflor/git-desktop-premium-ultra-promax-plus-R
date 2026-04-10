import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:provider/provider.dart';
import '../app/hyper_reactivity.dart';
import '../ui/tokens.dart';

const _states = <List<double>>[
  [0.35, 0.35, 0.1, 0.35, 0.1, 0.1],
  [0.5, 0.8, 0.2, 1.2, 0.5, 0.1],
  [1.5, 0.3, 2.1, 0.1, 0.9, 0.6],
  [2.1, 1.5, 0.8, 3.1, 0.4, 1.2],
  [3.14, 2.1, 1.5, 0.8, 0.1, 3.14],
  [0.8, 1.6, 3.2, 0.4, 4.0, 1.2],
  [1.57, 0, 1.57, 0, 1.57, 0],
  [0, 0.785, 0, 0, 0.785, 0],
  [0.4, 0.2, 3.142, 3.142, 0.2, 0.4],
  [0.1, 0.1, 2.356, 0.1, 2.356, 2.356],
  [0, 0.4, 3.142, 0, 3.142, 0],
  [0.785, 0, 0, 0, 0, 0.785],
  [0, 0, 1.57, 0, 1.57, 0],
];

const _planes = <(int, int)>[
  (0, 1),
  (0, 2),
  (0, 3),
  (1, 2),
  (1, 3),
  (2, 3),
];

class HypercubeLogo extends StatefulWidget {
  final double size;

  const HypercubeLogo({super.key, this.size = 24});

  @override
  State<HypercubeLogo> createState() => _HypercubeLogoState();
}

class _HypercubeLogoState extends State<HypercubeLogo>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastElapsed;
  double _time = 0;
  double _smoothBoost = 1;
  int _currentIndex = 0;
  int _targetIndex = 1;
  int _nextCursor = 2;
  double _transition = 0;
  double _near = 0;
  bool _dragging = false;
  Offset _tilt = Offset.zero;
  Offset _warp = Offset.zero;
  Offset _warpVelocity = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final previous = _lastElapsed;
    _lastElapsed = elapsed;
    if (previous == null) return;

    final dt = math.min(
        (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond,
        0.033);
    final targetBoost = 1 + _near * 1.2 + (_dragging ? 2.3 : 0);
    _smoothBoost += (targetBoost - _smoothBoost) * dt * 12;
    _time += dt * 0.85 * _smoothBoost;

    final start = _states[_currentIndex];
    final end = _states[_targetIndex];
    var distance = 0.0;
    for (var i = 0; i < start.length; i++) {
      final delta = start[i] - end[i];
      distance += delta * delta;
    }
    final distanceMult = 0.9 + math.min(math.sqrt(distance) * 0.1, 0.1);
    _transition += 0.095 * dt * _smoothBoost * distanceMult;
    if (_transition >= 1) {
      _currentIndex = _targetIndex;
      _targetIndex = _pickNextIndex();
      _transition = 0;
    }

    if (!_dragging) {
      const spring = 800.0;
      const damp = 0.7;
      final acceleration = Offset(-spring * _warp.dx, -spring * _warp.dy);
      _warpVelocity = Offset(
        (_warpVelocity.dx + acceleration.dx * dt) * damp,
        (_warpVelocity.dy + acceleration.dy * dt) * damp,
      );
      _warp = Offset(
        _warp.dx + _warpVelocity.dx * dt,
        _warp.dy + _warpVelocity.dy * dt,
      );
    }

    if (mounted) setState(() {});
  }

  int _pickNextIndex() {
    final next = _nextCursor % _states.length;
    _nextCursor += 3;
    if (next == _targetIndex || next == _currentIndex) {
      return (next + 5) % _states.length;
    }
    return next;
  }

  void _updatePointer(Offset localPosition) {
    final half = widget.size / 2;
    final delta = localPosition - Offset(half, half);
    final distance = delta.distance;
    var nextNear = 0.0;
    setState(() {
      _tilt = Offset(delta.dx / widget.size, delta.dy / widget.size);
      nextNear = math.max(0, 1 - distance / (widget.size * 3));
      _near = nextNear;
      if (_dragging) {
        _warp = delta;
        _warpVelocity = Offset.zero;
      }
    });
    if (_dragging) {
      context.read<HyperReactivity>().activate(nextNear + 1);
    }
  }

  void _releaseDrag() {
    setState(() => _dragging = false);
    context.read<HyperReactivity>().deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor:
          _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.click,
      onHover: (event) => _updatePointer(event.localPosition),
      onExit: (_) => setState(() {
        _near = 0;
        if (!_dragging) _tilt = Offset.zero;
      }),
      child: Listener(
        onPointerDown: (event) {
          setState(() => _dragging = true);
          _updatePointer(event.localPosition);
        },
        onPointerMove: (event) => _updatePointer(event.localPosition),
        onPointerUp: (_) => _releaseDrag(),
        onPointerCancel: (_) => _releaseDrag(),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _HypercubePainter(
              size: widget.size,
              time: _time,
              transition: _transition,
              currentIndex: _currentIndex,
              targetIndex: _targetIndex,
              near: _near,
              dragging: _dragging,
              tilt: _tilt,
              warp: _warp,
              colors: _HypercubeColors.fromTokens(tokens),
            ),
          ),
        ),
      ),
    );
  }
}

class _HypercubeColors {
  final Color chromatic1;
  final Color chromatic2;
  final Color core;

  const _HypercubeColors({
    required this.chromatic1,
    required this.chromatic2,
    required this.core,
  });

  factory _HypercubeColors.fromTokens(AppTokens tokens) {
    return _HypercubeColors(
      chromatic1: tokens.hyperChromatic1,
      chromatic2: tokens.hyperChromatic2,
      core: tokens.hyperCore,
    );
  }
}

class _ProjectedPoint {
  final Offset point;
  final double z;
  final double w;

  const _ProjectedPoint(this.point, this.z, this.w);
}

class _HypercubePainter extends CustomPainter {
  final double size;
  final double time;
  final double transition;
  final int currentIndex;
  final int targetIndex;
  final double near;
  final bool dragging;
  final Offset tilt;
  final Offset warp;
  final _HypercubeColors colors;

  static final _vertices = List.generate(
    16,
    (i) => <double>[
      ((i & 1) << 1) - 1,
      (i & 2) - 1,
      ((i & 4) >> 1) - 1,
      ((i & 8) >> 2) - 1,
    ],
  );
  static final _edges = _buildEdges();

  const _HypercubePainter({
    required this.size,
    required this.time,
    required this.transition,
    required this.currentIndex,
    required this.targetIndex,
    required this.near,
    required this.dragging,
    required this.tilt,
    required this.warp,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final projected = _projectedData();
    final main = projected.main;
    final home = projected.home;
    final ghost = projected.ghost;

    _drawLogoHalo(canvas);
    _drawGhostEdges(canvas, home, colors.chromatic2,
        0.04 + near * 0.35 + (dragging ? 0.3 : 0));
    if (dragging) {
      _drawConnectors(canvas, main, home);
    }
    _drawMainEdges(canvas, main);
    _drawGhostEdges(canvas, ghost, colors.chromatic2, 0.02 + near * 0.15);
  }

  ({
    List<_ProjectedPoint> main,
    List<_ProjectedPoint> home,
    List<_ProjectedPoint> ghost
  }) _projectedData() {
    final start = _states[currentIndex];
    final end = _states[targetIndex];
    final eased = transition * transition * (3 - 2 * transition);
    final angles = List.generate(
      6,
      (i) => start[i] + (end[i] - start[i]) * eased,
    );

    List<_ProjectedPoint> solve(
        double tOffset, double fovOffset, bool useWarp) {
      final scale =
          size * 1.55 * (1 + math.sin((time + tOffset) * 0.4) * 0.05 * near);
      final solvedAngles = List<double>.from(angles);
      solvedAngles[0] += tilt.dx * 0.5 + (useWarp ? warp.dx / size * 0.8 : 0);
      solvedAngles[1] += tilt.dy * 0.5 + (useWarp ? warp.dy / size * 0.8 : 0);
      for (var i = 2; i < solvedAngles.length; i++) {
        solvedAngles[i] += math.sin((time + tOffset) * 0.1) * 0.05 +
            (useWarp ? (warp.dx + warp.dy) / size * 0.2 : 0);
      }

      return _vertices.map((vertex) {
        final rotated = _rotate4D(vertex, solvedAngles);
        final w = rotated[3];
        final z = rotated[2];
        final fov4 = 1 / math.max(0.01, 2.4 - near * 0.3 + fovOffset - w);
        final x3 = rotated[0] * fov4;
        final y3 = rotated[1] * fov4;
        final z3 = z * fov4;
        final fov3 = 1 / math.max(0.01, 3.6 - z3);
        final meldStrength = useWarp ? near * 0.45 : 0.0;
        var x = x3 * fov3 * scale + size / 2 + (useWarp ? warp.dx : 0);
        var y = y3 * fov3 * scale + size / 2 + (useWarp ? warp.dy : 0);
        if (useWarp && near > 0.5) {
          x += warp.dx * meldStrength;
          y += warp.dy * meldStrength;
        }
        return _ProjectedPoint(Offset(x, y), z, w);
      }).toList();
    }

    return (
      main: solve(0, 0, true),
      home: solve(-0.2, 0.04, false),
      ghost: solve(-0.4, 0.08, false),
    );
  }

  void _drawGhostEdges(
    Canvas canvas,
    List<_ProjectedPoint> points,
    Color color,
    double opacity,
  ) {
    if (opacity <= 0.01) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.32
      ..color = color.withValues(alpha: opacity.clamp(0, 1));
    for (final edge in _edges) {
      canvas.drawLine(points[edge.$1].point, points[edge.$2].point, paint);
    }
  }

  void _drawConnectors(
    Canvas canvas,
    List<_ProjectedPoint> main,
    List<_ProjectedPoint> home,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.12
      ..color = colors.chromatic1.withValues(alpha: 0.45);
    for (var i = 0; i < main.length; i++) {
      canvas.drawLine(main[i].point, home[i].point, paint);
    }
  }

  void _drawLogoHalo(Canvas canvas) {
    final interaction = near + (dragging ? 0.75 : 0);
    final haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 + interaction
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.4 + interaction * 4)
      ..color = colors.chromatic1.withValues(alpha: 0.10 + interaction * 0.13);
    canvas.drawCircle(Offset(size / 2, size / 2),
        size * (0.34 + interaction * 0.06), haloPaint);

    final secondHalo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.2 + interaction * 2)
      ..color = colors.chromatic2.withValues(alpha: 0.06 + interaction * 0.10);
    canvas.drawCircle(Offset(size / 2, size / 2), size * 0.44, secondHalo);
  }

  void _drawMainEdges(Canvas canvas, List<_ProjectedPoint> points) {
    final effect = dragging ? 1.0 : math.max(0.12, near);
    final useEffects = effect > 0.05;
    for (final edge in _edges) {
      final p1 = points[edge.$1];
      final p2 = points[edge.$2];
      final torsion = (p1.w - p2.w).abs() + (p1.z - p2.z).abs() * 0.5;
      final stress = math.min(1.5, torsion * (1.2 + near * 0.8));
      final depth = (p1.z + p2.z) * 0.5 + (p1.w + p2.w) * 0.5;
      final opacity = math.max(0.05, 0.25 + near * 0.25 + depth * 0.08);
      final strokeWidth =
          0.45 + opacity * 1.5 + (dragging ? 0.8 : 0) + stress * 0.4;
      final dashed = stress > 1.1;

      if (useEffects) {
        final glow = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeWidth * (2.2 + effect)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.8 + effect * 1.2)
          ..color =
              colors.core.withValues(alpha: opacity * (0.16 + effect * 0.18));
        _drawMaybeDashedLine(canvas, p1.point, p2.point, glow, dashed);

        final left = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeWidth
          ..color = colors.chromatic1
              .withValues(alpha: opacity * (0.18 + effect * 0.45));
        _drawMaybeDashedLine(
          canvas,
          p1.point.translate(-0.4 - near * 0.4, 0),
          p2.point.translate(-0.4 - near * 0.4, 0),
          left,
          dashed,
        );

        final right = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeWidth
          ..color = colors.chromatic2
              .withValues(alpha: opacity * (0.18 + effect * 0.45));
        _drawMaybeDashedLine(
          canvas,
          p1.point.translate(0.4 + near * 0.4, 0),
          p2.point.translate(0.4 + near * 0.4, 0),
          right,
          dashed,
        );
      }

      final core = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth
        ..color = colors.core
            .withValues(alpha: (opacity + stress * 0.15).clamp(0, 1));
      _drawMaybeDashedLine(canvas, p1.point, p2.point, core, dashed);
    }
  }

  void _drawMaybeDashedLine(
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
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 0.2, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 2.0;
      }
    }
  }

  @override
  bool shouldRepaint(_HypercubePainter oldDelegate) => true;
}

List<(int, int)> _buildEdges() {
  final edges = <(int, int)>[];
  for (var i = 0; i < 16; i++) {
    for (var j = i + 1; j < 16; j++) {
      final diff = i ^ j;
      if (diff != 0 && (diff & (diff - 1)) == 0) {
        edges.add((i, j));
      }
    }
  }
  return edges;
}

List<double> _rotate4D(List<double> coords, List<double> angles) {
  var result = List<double>.from(coords);
  for (var i = 0; i < _planes.length; i++) {
    final (p, q) = _planes[i];
    final c = math.cos(angles[i]);
    final s = math.sin(angles[i]);
    final rp = result[p] * c - result[q] * s;
    final rq = result[p] * s + result[q] * c;
    result[p] = rp;
    result[q] = rq;
  }
  return result;
}
