// Comet primitive for the Manifold drawer.
//
// The manifold is a real 3D neighborhood of evidence around the
// pinned line. Each comet carries an (x, y, z) position in normalized
// pane coordinates. A [CometCamera] rotates the neighborhood around
// its anchor before perspective projection, and callers can quaternion-
// slerp between a small set of prefixed perspectives so the user
// witnesses the same evidence from different vantage points — the
// diff from here, the diff as seen from a parallel worktree, the
// residual perspective where only dormant ghosts carry meaning.
//
// Hard-edged visual language, no glow:
//   * filled diamond for the orientation anchor (current hunk / tangent
//     source)
//   * filled circle for echoes, surrounded by a thin static ring
//   * a sonar-style expanding pulse ring per comet, phase-offset, that
//     fades as it travels outward — the "breathing" without blur
//   * absence (dormant witness) renders as a dashed ring only, no body
//   * everything theme-routed: alphas ramp with `shader.luminescence`,
//     strokes scale with `shader.edgeIntensity`, no hardcoded minima
//     that override a theme's intent to be plain (petrichor test)
//
// Depth is encoded twice for legibility: per-comet scale from the
// perspective projection, AND back-to-front paint order so closer
// comets occlude farther ones.

import 'dart:math' as math;

import 'package:flutter/material.dart';

enum CometShape {
  /// Generic echo / ripple. Filled disc + concentric ring.
  circle,

  /// Orientation anchor (current hunk, tangent source). Filled diamond
  /// so the eye lands on it first without needing a label.
  diamond,
}

/// A relationship line between two comets.
///
/// Peer links (hoverOnly = false) render at rest as hairline threads —
/// gossamer mesh between comets that share a meaningful relation, e.g.
/// rhymes living in the same file, or transport targets sharing a
/// witness lane. Focus tethers (hoverOnly = true) only appear when one
/// of their endpoints is hovered — a responsive "this is what this
/// connects to" affordance.
class CometLink {
  final int fromIndex;
  final int toIndex;
  final Color color;
  final double strength;
  final bool hoverOnly;

  const CometLink({
    required this.fromIndex,
    required this.toIndex,
    required this.color,
    this.strength = 0.5,
    this.hoverOnly = false,
  });
}

/// An evidence-bearing point in the manifold.
///
/// Position is normalized in-plane coordinates [0..1]. [z] is the
/// depth offset in the same normalized unit; positive z reads as
/// closer to the viewer after perspective projection.
class Comet {
  final Offset position;
  final double z;
  final double strength;
  final double coreMass;
  final Color laneColor;
  final double phase;
  final CometShape shape;
  final Object? tag;

  const Comet({
    required this.position,
    this.z = 0,
    required this.strength,
    required this.coreMass,
    required this.laneColor,
    required this.phase,
    this.shape = CometShape.circle,
    this.tag,
  });
}

/// Minimal quaternion used to rotate the manifold around its anchor.
///
/// Implemented inline to avoid pulling vector_math into this layer for
/// a single use-case. Supports composition, slerp, and vector rotation
/// — enough for prefixed perspectives that interpolate smoothly.
@immutable
class _Quat {
  final double x;
  final double y;
  final double z;
  final double w;

  const _Quat(this.x, this.y, this.z, this.w);

  /// Identity quaternion (no rotation).
  static const identity = _Quat(0, 0, 0, 1);

  /// Build from an axis-angle. [axis] must be unit length.
  factory _Quat.axisAngle(double ax, double ay, double az, double angle) {
    final half = angle * 0.5;
    final s = math.sin(half);
    return _Quat(ax * s, ay * s, az * s, math.cos(half));
  }

  /// Build from yaw (around +Y) composed with pitch (around +X). Yaw
  /// first gives us "swing left/right" then "look up/down" which is
  /// the intuitive camera convention.
  factory _Quat.yawPitch(double yaw, double pitch) {
    final qy = _Quat.axisAngle(0, 1, 0, yaw);
    final qp = _Quat.axisAngle(1, 0, 0, pitch);
    return qy * qp;
  }

  _Quat operator *(_Quat o) => _Quat(
        w * o.x + x * o.w + y * o.z - z * o.y,
        w * o.y - x * o.z + y * o.w + z * o.x,
        w * o.z + x * o.y - y * o.x + z * o.w,
        w * o.w - x * o.x - y * o.y - z * o.z,
      );

  double _dot(_Quat o) => x * o.x + y * o.y + z * o.z + w * o.w;

  _Quat _normalized() {
    final m2 = x * x + y * y + z * z + w * w;
    if (m2 <= 1e-12) return identity;
    final m = math.sqrt(m2);
    return _Quat(x / m, y / m, z / m, w / m);
  }

  /// Spherical linear interpolation. Produces a great-circle rotation
  /// path between two orientations — no gimbal lock at the poles.
  static _Quat slerp(_Quat a, _Quat b, double t) {
    var cosTheta = a._dot(b);
    // Always take the short way around.
    var bb = b;
    if (cosTheta < 0) {
      bb = _Quat(-b.x, -b.y, -b.z, -b.w);
      cosTheta = -cosTheta;
    }
    if (cosTheta > 0.9995) {
      // Very close — straight lerp avoids numerical blow-up.
      return _Quat(
        a.x + (bb.x - a.x) * t,
        a.y + (bb.y - a.y) * t,
        a.z + (bb.z - a.z) * t,
        a.w + (bb.w - a.w) * t,
      )._normalized();
    }
    final theta = math.acos(cosTheta.clamp(-1.0, 1.0));
    final sinTheta = math.sin(theta);
    final wa = math.sin((1 - t) * theta) / sinTheta;
    final wb = math.sin(t * theta) / sinTheta;
    return _Quat(
      a.x * wa + bb.x * wb,
      a.y * wa + bb.y * wb,
      a.z * wa + bb.z * wb,
      a.w * wa + bb.w * wb,
    );
  }

  /// Rotate a 3D vector. Returns (x', y', z').
  (double, double, double) rotate(double vx, double vy, double vz) {
    // q * v * q^-1, simplified for unit quaternion.
    final ix = w * vx + y * vz - z * vy;
    final iy = w * vy + z * vx - x * vz;
    final iz = w * vz + x * vy - y * vx;
    final iw = -x * vx - y * vy - z * vz;
    final rx = ix * w + iw * -x + iy * -z - iz * -y;
    final ry = iy * w + iw * -y + iz * -x - ix * -z;
    final rz = iz * w + iw * -z + ix * -y - iy * -x;
    return (rx, ry, rz);
  }
}

/// Camera pose for the manifold. Callers construct perspectives at
/// rest and slerp between them — no free-look, no cursor-driven yaw.
@immutable
class CometCamera {
  final double yaw;
  final double pitch;

  /// Focal length of the perspective projection. Larger = flatter
  /// (orthographic limit). Smaller = more dramatic foreshortening.
  final double focal;

  const CometCamera({
    this.yaw = 0,
    this.pitch = 0,
    this.focal = 2.4,
  });

  static const flat = CometCamera();

  /// Quaternion slerp between two cameras. Focal blends linearly.
  static CometCamera slerp(CometCamera a, CometCamera b, double t) {
    final qa = _Quat.yawPitch(a.yaw, a.pitch);
    final qb = _Quat.yawPitch(b.yaw, b.pitch);
    final q = _Quat.slerp(qa, qb, t);
    // Recover yaw/pitch from the slerped quaternion for painter use.
    // Yaw = rotation around Y, pitch = around X. Extracted via the
    // canonical Tait-Bryan formula for y-x'-z'' order.
    final sinPitch = (-2 * (q.y * q.z - q.w * q.x)).clamp(-1.0, 1.0);
    final pitch = math.asin(sinPitch);
    final yaw = math.atan2(
      2 * (q.x * q.z + q.w * q.y),
      1 - 2 * (q.x * q.x + q.y * q.y),
    );
    final focal = a.focal + (b.focal - a.focal) * t;
    return CometCamera(yaw: yaw, pitch: pitch, focal: focal);
  }
}

/// Resolved pixel positions for a [CometField]. Hit-testers keep this
/// so interaction matches exactly what the painter drew.
class CometLayout {
  final List<Offset> positions;
  final List<double> localTimes;
  final List<double> densities;
  final List<double> reachRadii;

  /// Per-comet perspective scale factor. 1.0 = on the reference plane,
  /// >1 closer to viewer, <1 farther away. Painter multiplies ring/
  /// core/pulse radii by this.
  final List<double> scales;

  /// Paint order — indices sorted back-to-front. Painter iterates this
  /// so closer comets occlude farther ones.
  final List<int> paintOrder;

  const CometLayout({
    required this.positions,
    required this.localTimes,
    required this.densities,
    required this.reachRadii,
    required this.scales,
    required this.paintOrder,
  });
}

class CometField extends CustomPainter {
  final List<Comet> comets;
  final List<CometLink> links;
  final double introT;
  final double breathT;
  final double luminescence;
  final double edgeIntensity;
  final int? focusedIndex;
  final Offset? cursor;
  final CometCamera camera;
  final Offset anchor;
  final double staggerSpread;

  /// When luminescence drops below this, the traveling pulse on flow
  /// lines and the sonar pulse on comets are suppressed. Respects the
  /// petrichor-plain intent that low-lum themes signal "no decoration".
  static const double silentPulseThreshold = 0.18;

  const CometField({
    required this.comets,
    this.links = const [],
    required this.introT,
    required this.breathT,
    this.luminescence = 1,
    this.edgeIntensity = 1,
    this.focusedIndex,
    this.cursor,
    this.camera = CometCamera.flat,
    this.anchor = const Offset(0.5, 0.5),
    this.staggerSpread = 0.35,
  });

  /// Tiny LRU keyed on the layout's full input tuple. One `CustomPaint`
  /// pass does the layout once in `paint()` and the hovering hit-tester
  /// does it again — with identical arguments — for the same frame. This
  /// cache eliminates the duplicate O(N²) density scan without forcing
  /// the caller to thread a `CometLayout` through the painter
  /// constructor. Two slots so the two panes (chart + tangent) don't
  /// thrash each other when both are in view.
  static final List<_LayoutCacheEntry> _layoutCache = <_LayoutCacheEntry>[];
  static const int _kLayoutCacheSize = 2;

  /// Deterministic layout shared by painter and hit-testers.
  static CometLayout layout({
    required List<Comet> comets,
    required Size size,
    required double introT,
    required Offset anchor,
    double staggerSpread = 0.35,
    Offset? cursor,
    CometCamera camera = CometCamera.flat,
    double densityRadiusPx = 52,
  }) {
    // Identity of `comets` is a valid key because callers rebuild the
    // list only when composition changes; animation ticks may advance
    // introT but reuse the same list. When identity mismatches we fall
    // through to recompute — no false hits.
    final key = Object.hash(
      identityHashCode(comets),
      size.width,
      size.height,
      introT,
      anchor,
      staggerSpread,
      cursor,
      camera.yaw,
      camera.pitch,
      camera.focal,
      densityRadiusPx,
    );
    for (var i = 0; i < _layoutCache.length; i++) {
      if (_layoutCache[i].key == key) {
        final hit = _layoutCache.removeAt(i);
        _layoutCache.add(hit); // LRU bump
        return hit.layout;
      }
    }

    final n = comets.length;
    final positions = <Offset>[];
    final locals = <double>[];
    final scales = <double>[];
    final projectedZ = <double>[];

    final rotation = _Quat.yawPitch(camera.yaw, camera.pitch);
    final focal = camera.focal <= 0.01 ? 2.4 : camera.focal;

    for (var i = 0; i < n; i++) {
      final c = comets[i];
      final stagger = staggerSpread == 0 ? 0.0 : (staggerSpread / n) * i;
      final window = (1.0 - stagger).clamp(0.25, 1.0);
      final tLocal = ((introT - stagger) / window).clamp(0.0, 1.0).toDouble();
      locals.add(tLocal);

      // Offset from anchor in normalized pane units.
      final dx = c.position.dx - anchor.dx;
      final dy = c.position.dy - anchor.dy;

      // Intro: emerge from the anchor along its target direction. Same
      // curve as before but now interpreted in 3D; z also eases in.
      final ease = Curves.easeOutCubic.transform(tLocal);
      final rx0 = dx * ease;
      final ry0 = dy * ease;
      final rz0 = c.z * ease;

      final (rx, ry, rz) = rotation.rotate(rx0, ry0, rz0);

      final denom = focal - rz;
      final scale = denom.abs() < 0.01 ? 1.0 : focal / denom;

      final screenX = (anchor.dx + rx * scale) * size.width;
      final screenY = (anchor.dy + ry * scale) * size.height;
      positions.add(Offset(screenX, screenY));
      scales.add(scale);
      projectedZ.add(rz);
    }

    // Hover-unfold stays — it's a direct manipulation interaction, not
    // an idle animation, so it's valid even on plain themes.
    if (cursor != null) {
      const clusterGateRadiusPx = 38.0;
      const unfoldRadiusPx = 48.0;
      const unfoldMaxPx = 12.0;
      var near = 0;
      for (var i = 0; i < n; i++) {
        if ((positions[i] - cursor).distance < clusterGateRadiusPx) near++;
      }
      if (near >= 2) {
        for (var i = 0; i < n; i++) {
          final delta = positions[i] - cursor;
          final d = delta.distance;
          if (d > 0.01 && d < unfoldRadiusPx) {
            final proximity = 1.0 - d / unfoldRadiusPx;
            final amount = proximity * proximity * unfoldMaxPx;
            final dir = delta / d;
            positions[i] = positions[i] + dir * amount;
          }
        }
      }
    }

    final densities = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (i == j) continue;
        final d = (positions[i] - positions[j]).distance;
        if (d < densityRadiusPx) {
          densities[i] += (1.0 - d / densityRadiusPx).clamp(0.0, 1.0);
        }
      }
    }

    final reach = <double>[];
    for (var i = 0; i < n; i++) {
      reach.add(_staticRingRadius(comets[i].strength, locals[i]) * scales[i]);
    }

    // Back-to-front paint order — smallest rotated z (farthest from
    // viewer) first, largest (closest) last.
    final indices = List<int>.generate(n, (i) => i);
    indices.sort((a, b) => projectedZ[a].compareTo(projectedZ[b]));

    final result = CometLayout(
      positions: positions,
      localTimes: locals,
      densities: densities,
      reachRadii: reach,
      scales: scales,
      paintOrder: indices,
    );
    _layoutCache.add(_LayoutCacheEntry(key: key, layout: result));
    while (_layoutCache.length > _kLayoutCacheSize) {
      _layoutCache.removeAt(0);
    }
    return result;
  }

  static double _staticRingRadius(double strength, double tLocal) =>
      (7.0 + 14.0 * strength) * tLocal;

  static double _coreRadius(double strength, double density, double tLocal) =>
      ((1.6 + 3.4 * strength) / math.sqrt(1 + 0.35 * density)) * tLocal;

  static double _maxPulseRadius(double strength, double tLocal) =>
      (18.0 + 28.0 * strength) * tLocal;

  double _strokeWidth(double base, double scale) {
    // edgeIntensity is not clamped from below — petrichor's 0 is
    // respected. Upper clamp keeps extreme themes from painting
    // hairy strokes on small scales.
    final w = (base * edgeIntensity * scale);
    return w.clamp(0.0, 3.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (comets.isEmpty || size.isEmpty) return;

    final lay = layout(
      comets: comets,
      size: size,
      introT: introT,
      anchor: anchor,
      staggerSpread: staggerSpread,
      cursor: cursor,
      camera: camera,
    );

    final pulseActive = luminescence >= silentPulseThreshold;

    // Pass 0: relationship links. Rendered first, so everything else
    // sits on top. Peer links (hoverOnly=false) stay as a gossamer
    // mesh at rest; focus tethers (hoverOnly=true) only appear when
    // one of their endpoints is hovered.
    if (links.isNotEmpty) {
      final f = focusedIndex;
      for (final link in links) {
        if (link.fromIndex < 0 ||
            link.fromIndex >= comets.length ||
            link.toIndex < 0 ||
            link.toIndex >= comets.length) {
          continue;
        }
        final fromT = lay.localTimes[link.fromIndex];
        final toT = lay.localTimes[link.toIndex];
        final progress = math.min(fromT, toT);
        if (progress <= 0) continue;

        final isFocused = f != null &&
            (f == link.fromIndex || f == link.toIndex);

        final double alpha;
        if (link.hoverOnly) {
          if (!isFocused) continue;
          alpha = (0.42 * link.strength * luminescence * progress)
              .clamp(0.0, 0.7);
        } else {
          final base = f == null
              ? 0.12
              : (isFocused ? 0.40 : 0.05);
          alpha = (base * link.strength * luminescence * progress)
              .clamp(0.0, 0.6);
        }
        if (alpha <= 0.01) continue;

        // Slight arc so links don't cross in a tangle. Pull the
        // midpoint toward the scene anchor in pixel space — creates
        // an organic bow toward the "gravitational" center.
        final a = lay.positions[link.fromIndex];
        final b = lay.positions[link.toIndex];
        final anchorPx = Offset(anchor.dx * size.width, anchor.dy * size.height);
        final mid = (a + b) * 0.5;
        final bowed = mid + (anchorPx - mid) * 0.08;

        final path = Path()
          ..moveTo(a.dx, a.dy)
          ..quadraticBezierTo(bowed.dx, bowed.dy, b.dx, b.dy);

        final w = (0.55 * edgeIntensity *
                (lay.scales[link.fromIndex] + lay.scales[link.toIndex]) *
                0.5)
            .clamp(0.0, 1.6);
        if (w <= 0.01) continue;

        canvas.drawPath(
          path,
          Paint()
            ..color = link.color.withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Pass 1: sonar pulse rings (gated by luminescence — petrichor/
    // other plain themes stay silent by design).
    if (pulseActive) {
      for (final i in lay.paintOrder) {
        final c = comets[i];
        final tLocal = lay.localTimes[i];
        if (tLocal <= 0) continue;
        if (c.coreMass <= 0.001) continue;

        final pulseT = (breathT + c.phase) % 1.0;
        final r = _maxPulseRadius(c.strength, tLocal) * pulseT * lay.scales[i];
        if (r <= 0.5) continue;

        final fade = (1.0 - pulseT);
        final alpha =
            (0.28 * fade * c.strength * luminescence).clamp(0.0, 0.6);
        if (alpha <= 0.01) continue;

        final w = _strokeWidth(0.8, lay.scales[i]);
        if (w <= 0.01) continue;

        final paint = Paint()
          ..color = c.laneColor.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w;
        canvas.drawCircle(lay.positions[i], r, paint);
      }
    }

    // Pass 2: static halo ring — solid for present comets, dashed for
    // ghosts. Density compositing happens through alpha stacking.
    for (final i in lay.paintOrder) {
      final c = comets[i];
      final tLocal = lay.localTimes[i];
      if (tLocal <= 0) continue;

      final r = lay.reachRadii[i];
      if (r <= 0.5) continue;

      final isGhost = c.coreMass <= 0.001;
      final alpha = ((0.40 + 0.30 * c.strength) * luminescence * tLocal)
          .clamp(0.0, 0.95);
      if (alpha <= 0.01) continue;

      final w = _strokeWidth(isGhost ? 1.0 : 1.1, lay.scales[i]);
      if (w <= 0.01) continue;

      final paint = Paint()
        ..color = c.laneColor.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w;

      if (isGhost) {
        _drawDashedCircle(canvas, lay.positions[i], r, paint);
      } else {
        canvas.drawCircle(lay.positions[i], r, paint);
      }
    }

    // Pass 3: solid core bodies — skipped for ghosts.
    for (final i in lay.paintOrder) {
      final c = comets[i];
      final tLocal = lay.localTimes[i];
      if (tLocal <= 0 || c.coreMass <= 0.001) continue;

      final coreR = _coreRadius(c.strength, lay.densities[i], tLocal) *
          lay.scales[i];
      final alpha = ((0.88 * c.coreMass) * tLocal).clamp(0.0, 1.0);
      final fill = Paint()..color = c.laneColor.withValues(alpha: alpha);

      switch (c.shape) {
        case CometShape.circle:
          canvas.drawCircle(lay.positions[i], coreR, fill);
        case CometShape.diamond:
          _drawDiamond(canvas, lay.positions[i], coreR * 1.25, fill);
      }
    }

    // Pass 4: focus ring — matches the underlying comet's style
    // (dashed for ghosts, solid for present).
    final f = focusedIndex;
    if (f != null && f >= 0 && f < comets.length) {
      final tLocal = lay.localTimes[f];
      if (tLocal > 0) {
        final c = comets[f];
        final isGhost = c.coreMass <= 0.001;
        final r = lay.reachRadii[f] + 3.5;
        final w = _strokeWidth(1.3, lay.scales[f]);
        final paint = Paint()
          ..color = c.laneColor
              .withValues(alpha: (0.92 * luminescence).clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = w.clamp(0.6, 2.6);
        if (isGhost) {
          _drawDashedCircle(canvas, lay.positions[f], r, paint);
        } else {
          canvas.drawCircle(lay.positions[f], r, paint);
        }
      }
    }
  }

  void _drawDiamond(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r, c.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawDashedCircle(Canvas canvas, Offset c, double r, Paint paint) {
    if (r <= 1) return;
    final circumference = 2 * math.pi * r;
    final dashCount = math.max(8, (circumference / 6).round());
    final step = 2 * math.pi / dashCount;
    for (var k = 0; k < dashCount; k++) {
      final a0 = k * step;
      final a1 = a0 + step * 0.55;
      final p0 = Offset(c.dx + math.cos(a0) * r, c.dy + math.sin(a0) * r);
      final p1 = Offset(c.dx + math.cos(a1) * r, c.dy + math.sin(a1) * r);
      canvas.drawLine(p0, p1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CometField old) =>
      old.introT != introT ||
      old.breathT != breathT ||
      old.luminescence != luminescence ||
      old.edgeIntensity != edgeIntensity ||
      old.focusedIndex != focusedIndex ||
      old.cursor != cursor ||
      old.camera.yaw != camera.yaw ||
      old.camera.pitch != camera.pitch ||
      old.camera.focal != camera.focal ||
      !identical(old.comets, comets) ||
      !identical(old.links, links);
}

class _LayoutCacheEntry {
  _LayoutCacheEntry({required this.key, required this.layout});
  final int key;
  final CometLayout layout;
}

/// A transport flow line from source to target. Both endpoints live
/// in 3D so the flow lines rotate with the manifold.
class TangentFlow {
  final Offset start;
  final double startZ;
  final Offset end;
  final double endZ;
  final double strength;
  final Color laneColor;
  final bool ghost;

  const TangentFlow({
    required this.start,
    this.startZ = 0,
    required this.end,
    this.endZ = 0,
    required this.strength,
    required this.laneColor,
    this.ghost = false,
  });
}

/// Paints flow lines as thin crisp strokes, with an optional traveling
/// pulse riding outward — suppressed on plain themes via the same
/// luminescence gate used for the sonar pulse.
class TangentFlowPainter extends CustomPainter {
  final List<TangentFlow> flows;
  final double introT;
  final double breathT;
  final double luminescence;
  final double edgeIntensity;
  final CometCamera camera;
  final Offset anchor;

  const TangentFlowPainter({
    required this.flows,
    required this.introT,
    required this.breathT,
    this.luminescence = 1,
    this.edgeIntensity = 1,
    this.camera = CometCamera.flat,
    this.anchor = const Offset(0.09, 0.5),
  });

  (Offset, double) _project(double nx, double ny, double nz, Size size) {
    final rotation = _Quat.yawPitch(camera.yaw, camera.pitch);
    final focal = camera.focal <= 0.01 ? 2.4 : camera.focal;
    final dx = nx - anchor.dx;
    final dy = ny - anchor.dy;
    final (rx, ry, rz) = rotation.rotate(dx, dy, nz);
    final denom = focal - rz;
    final scale = denom.abs() < 0.01 ? 1.0 : focal / denom;
    final sx = (anchor.dx + rx * scale) * size.width;
    final sy = (anchor.dy + ry * scale) * size.height;
    return (Offset(sx, sy), scale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (flows.isEmpty || size.isEmpty) return;
    final pulseActive = luminescence >= CometField.silentPulseThreshold;

    for (var i = 0; i < flows.length; i++) {
      final f = flows[i];
      final stagger = i * 0.06;
      final window = (1.0 - stagger).clamp(0.25, 1.0);
      final tLocal =
          ((introT - stagger) / window).clamp(0.0, 1.0).toDouble();
      if (tLocal <= 0) continue;

      final (s, _) = _project(f.start.dx, f.start.dy, f.startZ, size);
      final (eFull, endScale) =
          _project(f.end.dx, f.end.dy, f.endZ, size);

      final ease = Curves.easeOutCubic.transform(tLocal);
      final end = Offset.lerp(s, eFull, ease)!;

      final dx = eFull.dx - s.dx;
      final dy = eFull.dy - s.dy;
      final m1 = Offset(s.dx + dx * 0.45, s.dy + dy * 0.08);
      final m2 = Offset(s.dx + dx * 0.55, eFull.dy - dy * 0.08);

      final path = Path()
        ..moveTo(s.dx, s.dy)
        ..cubicTo(m1.dx, m1.dy, m2.dx, m2.dy, end.dx, end.dy);

      final alpha = ((0.34 + 0.36 * f.strength) * luminescence * tLocal)
          .clamp(0.0, 0.85);
      if (alpha <= 0.01) continue;

      final width =
          ((0.7 + 1.5 * f.strength) * edgeIntensity * endScale).clamp(0.0, 2.8);
      if (width <= 0.01) continue;

      if (f.ghost) {
        _drawDashedPath(
          canvas,
          path,
          f.laneColor.withValues(alpha: alpha * 0.82),
          width,
        );
      } else {
        final paint = Paint()
          ..color = f.laneColor.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(path, paint);

        if (pulseActive) {
          _drawTravelingPulse(
            canvas,
            path,
            breathT,
            i * 0.14,
            f.laneColor,
            alpha,
            width,
            luminescence,
            tLocal,
          );
        }
      }
    }
  }

  void _drawTravelingPulse(
    Canvas canvas,
    Path path,
    double breathT,
    double phase,
    Color color,
    double lineAlpha,
    double lineWidth,
    double luminescence,
    double tLocal,
  ) {
    final pulseT = (breathT + phase) % 1.0;
    for (final metric in path.computeMetrics()) {
      final pulseLen = (metric.length * 0.08).clamp(6.0, 18.0);
      final head = metric.length * pulseT;
      final start = (head - pulseLen).clamp(0.0, metric.length);
      if (head <= 0) continue;
      final seg = metric.extractPath(start, head);
      final fade = math.sin(pulseT * math.pi);
      final a =
          (lineAlpha * 1.8 * fade * luminescence * tLocal).clamp(0.0, 1.0);
      if (a <= 0.01) continue;
      final paint = Paint()
        ..color = color.withValues(alpha: a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth * 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(seg, paint);
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      const dash = 4.0;
      const gap = 4.0;
      var dist = 0.0;
      while (dist < metric.length) {
        final next = math.min(dist + dash, metric.length);
        final seg = metric.extractPath(dist, next);
        canvas.drawPath(seg, paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant TangentFlowPainter old) =>
      old.introT != introT ||
      old.breathT != breathT ||
      old.luminescence != luminescence ||
      old.edgeIntensity != edgeIntensity ||
      old.camera.yaw != camera.yaw ||
      old.camera.pitch != camera.pitch ||
      old.camera.focal != camera.focal ||
      !identical(old.flows, flows);
}
