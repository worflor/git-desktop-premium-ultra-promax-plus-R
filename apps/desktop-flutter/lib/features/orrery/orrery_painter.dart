import 'dart:math' as math;
import 'dart:ui' as ui show Gradient;

import 'package:flutter/material.dart';

import '../../ui/tokens.dart';
import 'orrery_model.dart';

/// Resolved colours for the Orrery disk — pulled from [AppTokens] once and
/// passed into the painter, which never touches a BuildContext.
class OrreryColors {
  final Color bgInner;
  final Color bgOuter;
  final Color horizon;
  final Color guide;
  final Color nodeCore; // structurally central files
  final Color nodeEdge; // peripheral files
  final Color heat; // reorganising-now glow
  final Color trail;
  final Color ring; // hover highlight

  const OrreryColors({
    required this.bgInner,
    required this.bgOuter,
    required this.horizon,
    required this.guide,
    required this.nodeCore,
    required this.nodeEdge,
    required this.heat,
    required this.trail,
    required this.ring,
  });

  factory OrreryColors.fromTokens(AppTokens t) => OrreryColors(
        bgInner: t.bg1,
        bgOuter: t.bg0,
        horizon: t.chromeBorder,
        guide: t.chromeBorder,
        nodeCore: t.hyperCore,
        nodeEdge: t.textMuted,
        heat: t.stateModified,
        trail: t.textMuted,
        ring: t.accentBright,
      );

  bool sameAs(OrreryColors o) =>
      bgInner == o.bgInner &&
      bgOuter == o.bgOuter &&
      horizon == o.horizon &&
      guide == o.guide &&
      nodeCore == o.nodeCore &&
      nodeEdge == o.nodeEdge &&
      heat == o.heat &&
      trail == o.trail &&
      ring == o.ring;
}

/// Paints the repo's structural manifold at a continuous scrub position
/// [head]. Files are points in the Poincaré disk; each leaves a fading wake of
/// its recent path, glows warm while it's reorganising, and warms toward the
/// core as it becomes structurally central.
class OrreryPainter extends CustomPainter {
  final OrreryModel model;
  final double head; // scrub position in [0, stepCount - 1]
  final OrreryColors colors;
  final int trailSteps;
  final int? highlightId; // node under the cursor, ringed
  final int? pinnedId; // node selected from a finding / click — full journey

  static const double diskMargin = 0.9; // screen padding inside the square
  static const double _embedRadius = 0.92; // engine's targetRadius (poincaré)
  static const double _heatFloor = 0.015; // disk-speed below this doesn't glow
  static const double _heatScale = 17.0; // disk-speed above the floor → glow
  static const double _baseDot = 1.9;

  OrreryPainter({
    required this.model,
    required this.head,
    required this.colors,
    this.trailSteps = 4,
    this.highlightId,
    this.pinnedId,
    super.repaint,
  });

  /// Disk radius for a square of [side] — shared with hit-testing so the hover
  /// geometry matches the paint geometry exactly.
  static double radiusFor(double side) => side * 0.5 * diskMargin;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final double r = radiusFor(math.min(size.width, size.height));
    final Offset center = Offset(size.width / 2, size.height / 2);
    _paintField(canvas, center, r);
    if (model.isEmpty) return;
    _paintNodes(canvas, center, r);
    _paintPinned(canvas, center, r);
  }

  /// The selected file's whole journey through the manifold — genesis → now —
  /// drawn on top, with a genesis dot and a prominent ring at its current
  /// position. This is the "show me where this file is, and where it's been"
  /// drill-down that connects a finding to the disk.
  void _paintPinned(Canvas canvas, Offset center, double r) {
    final int? id = pinnedId;
    if (id == null || id < 0 || id >= model.nodes.length) return;
    final OrreryNode node = model.nodes[id];
    final int headStep = head.floor();

    final List<Offset> pts = <Offset>[];
    for (int s = 0; s <= headStep && s < node.positions.length; s++) {
      final Offset? p = node.positions[s];
      if (p != null) pts.add(_toScreen(p, center, r));
    }
    final Offset? headPos = OrreryModel.sampleNode(node, head);
    if (headPos != null) pts.add(_toScreen(headPos, center, r));
    if (pts.isEmpty) return;

    if (pts.length >= 2) {
      for (int k = 0; k < pts.length - 1; k++) {
        final double recency = (k + 1) / (pts.length - 1);
        canvas.drawLine(
          pts[k],
          pts[k + 1],
          Paint()
            ..color = colors.ring.withValues(alpha: 0.22 + recency * 0.55)
            ..strokeWidth = 1.0 + recency * 1.1
            ..strokeCap = StrokeCap.round,
        );
      }
      // Where it began.
      canvas.drawCircle(
        pts.first,
        2.6,
        Paint()..color = colors.ring.withValues(alpha: 0.55),
      );
    }

    // Prominent ring at the current position (or last known if retired).
    final Offset marker = pts.last;
    canvas.drawCircle(
      marker,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = colors.ring.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      marker,
      8.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = colors.ring,
    );
  }

  Offset _toScreen(Offset unit, Offset center, double r) =>
      Offset(center.dx + unit.dx * r, center.dy + unit.dy * r);

  void _paintField(Canvas canvas, Offset center, double r) {
    // Radial vignette: a touch of light at the core falling to the void.
    canvas.drawCircle(
      center,
      r * 1.18,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          r * 1.18,
          <Color>[colors.bgInner, colors.bgOuter],
          <double>[0.0, 1.0],
        ),
    );
    // Hyperbolic depth rings — barely there.
    for (final double f in const <double>[0.34, 0.67]) {
      canvas.drawCircle(
        center,
        r * f,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = colors.guide.withValues(alpha: 0.05),
      );
    }
    // The horizon — the disk's edge — with a soft outer bloom.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = colors.horizon.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = colors.horizon.withValues(alpha: 0.5),
    );
  }

  void _paintNodes(Canvas canvas, Offset center, double r) {
    final int headStep = head.floor();
    final int lo = math.max(0, headStep - trailSteps);
    for (final OrreryNode node in model.nodes) {
      final Offset? pos = OrreryModel.sampleNode(node, head);
      if (pos == null) continue;
      final double dist = pos.distance;
      if (dist > 1.0) continue; // outside the disk — skip
      final double centrality = (1.0 - dist / _embedRadius).clamp(0.0, 1.0);
      final double speed = OrreryModel.sampleSpeed(node, head);
      final double heat =
          ((speed - _heatFloor) * _heatScale).clamp(0.0, 1.0);

      final Color base =
          Color.lerp(colors.nodeEdge, colors.nodeCore, centrality)!;
      final Color tone = Color.lerp(base, colors.heat, heat * 0.7)!;

      _paintTrail(canvas, node, center, r, lo, headStep, base);

      final Offset screen = _toScreen(pos, center, r);
      // Size carries churn — how much the file changes — as its own channel,
      // orthogonal to position (structural role) and colour (centrality/heat).
      // Log-normalised upstream, so this is linear here, over a floor that keeps
      // never-touched files legible as points.
      final double radius =
          _baseDot * (0.55 + 0.3 * centrality + 1.15 * node.churn) + heat * 1.4;
      // Glow — the file's presence bleeding into the field. Kept tight so
      // dense clusters of active files read as points, not a single smear.
      canvas.drawCircle(
        screen,
        radius * 2.5,
        Paint()
          ..color = tone.withValues(alpha: 0.07 + heat * 0.14)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 1.7),
      );
      // Core.
      canvas.drawCircle(
        screen,
        radius,
        Paint()..color = tone.withValues(alpha: 0.92),
      );
      // Hover highlight — a clean ring around the file under the cursor.
      if (node.id == highlightId) {
        canvas.drawCircle(
          screen,
          radius + 5.0,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = colors.ring.withValues(alpha: 0.95),
        );
      }
    }
  }

  void _paintTrail(
    Canvas canvas,
    OrreryNode node,
    Offset center,
    double r,
    int lo,
    int headStep,
    Color base,
  ) {
    final List<Offset> pts = <Offset>[];
    for (int s = lo; s <= headStep; s++) {
      final Offset? p = node.positions[s];
      if (p != null) pts.add(_toScreen(p, center, r));
    }
    final Offset? headPos = OrreryModel.sampleNode(node, head);
    if (headPos != null) pts.add(_toScreen(headPos, center, r));
    if (pts.length < 2) return;
    final int segs = pts.length - 1;
    for (int k = 0; k < segs; k++) {
      final double recency = (k + 1) / segs; // 0 old .. 1 at the head
      canvas.drawLine(
        pts[k],
        pts[k + 1],
        Paint()
          ..color = base.withValues(alpha: recency * recency * 0.30)
          ..strokeWidth = 0.6 + recency * 0.9
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(OrreryPainter old) =>
      old.head != head ||
      old.model != model ||
      old.trailSteps != trailSteps ||
      old.highlightId != highlightId ||
      old.pinnedId != pinnedId ||
      !old.colors.sameAs(colors);
}
