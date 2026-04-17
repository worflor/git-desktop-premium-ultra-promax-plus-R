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

import 'manifold_tuning.dart';

enum CometShape {
  /// Generic evidence node — topology ladder picks its polyhedron
  /// from the per-comet `support` count.
  circle,

  /// Orientation anchor (current hunk, tangent source). Forced to
  /// the densest polyhedron on the ladder regardless of support so
  /// the pinned line always reads as the centerpiece.
  diamond,
}

/// Platonic-solid topology ladder. Picked per-comet from the amount
/// of evidence the engine has for that node — more witnesses = more
/// facets. The shape family emerges from the data; nothing is role-
/// pinned except the anchor (forced to [icosa] via [CometShape.diamond]).
enum Polyhedron { tetra, octa, cube, icosa }

typedef _V3 = (double, double, double);

/// Vertex / face tables for each Platonic solid. Coordinates are
/// normalized so the polyhedron fits inside a unit sphere — callers
/// scale by the comet's core radius. Face windings are consistently
/// counter-clockwise when viewed from outside, which lets the painter
/// use a cross-product sign test for back-face culling.
class _Polyhedra {
  _Polyhedra._();

  static const double _phi = 1.6180339887498949;

  // Normalization scales so every solid's vertices sit on the unit
  // sphere. Baked in rather than computed so the tables stay `const`.
  static const double _sTetra = 0.5773502691896257;   // 1/√3
  static const double _sCube = 0.5773502691896257;    // 1/√3
  static const double _sIcosa = 0.5257311121191336;   // 1/√(1+φ²)

  static const List<_V3> _tetraVerts = [
    (_sTetra, _sTetra, _sTetra),
    (_sTetra, -_sTetra, -_sTetra),
    (-_sTetra, _sTetra, -_sTetra),
    (-_sTetra, -_sTetra, _sTetra),
  ];
  static const List<List<int>> _tetraFaces = [
    [0, 2, 1],
    [0, 1, 3],
    [0, 3, 2],
    [1, 2, 3],
  ];

  static const List<_V3> _octaVerts = [
    (1, 0, 0),
    (-1, 0, 0),
    (0, 1, 0),
    (0, -1, 0),
    (0, 0, 1),
    (0, 0, -1),
  ];
  static const List<List<int>> _octaFaces = [
    [0, 2, 4],
    [2, 1, 4],
    [1, 3, 4],
    [3, 0, 4],
    [2, 0, 5],
    [1, 2, 5],
    [3, 1, 5],
    [0, 3, 5],
  ];

  static const List<_V3> _cubeVerts = [
    (-_sCube, -_sCube, -_sCube),
    (_sCube, -_sCube, -_sCube),
    (_sCube, _sCube, -_sCube),
    (-_sCube, _sCube, -_sCube),
    (-_sCube, -_sCube, _sCube),
    (_sCube, -_sCube, _sCube),
    (_sCube, _sCube, _sCube),
    (-_sCube, _sCube, _sCube),
  ];
  static const List<List<int>> _cubeFaces = [
    [0, 3, 2, 1], // -z
    [4, 5, 6, 7], // +z
    [0, 1, 5, 4], // -y
    [2, 3, 7, 6], // +y
    [1, 2, 6, 5], // +x
    [0, 4, 7, 3], // -x
  ];

  static const List<_V3> _icosaVerts = [
    (0, _sIcosa, _sIcosa * _phi),
    (0, -_sIcosa, _sIcosa * _phi),
    (0, _sIcosa, -_sIcosa * _phi),
    (0, -_sIcosa, -_sIcosa * _phi),
    (_sIcosa, _sIcosa * _phi, 0),
    (-_sIcosa, _sIcosa * _phi, 0),
    (_sIcosa, -_sIcosa * _phi, 0),
    (-_sIcosa, -_sIcosa * _phi, 0),
    (_sIcosa * _phi, 0, _sIcosa),
    (_sIcosa * _phi, 0, -_sIcosa),
    (-_sIcosa * _phi, 0, _sIcosa),
    (-_sIcosa * _phi, 0, -_sIcosa),
  ];
  static const List<List<int>> _icosaFaces = [
    [0, 1, 8], [0, 10, 1], [0, 5, 10], [0, 4, 5], [0, 8, 4],
    [1, 6, 8], [1, 7, 6], [1, 10, 7], [8, 6, 9], [8, 9, 4],
    [4, 9, 2], [4, 2, 5], [5, 2, 11], [5, 11, 10], [10, 11, 7],
    [7, 11, 3], [7, 3, 6], [6, 3, 9], [9, 3, 2], [2, 3, 11],
  ];

  static List<_V3> vertices(Polyhedron p) {
    switch (p) {
      case Polyhedron.tetra:
        return _tetraVerts;
      case Polyhedron.octa:
        return _octaVerts;
      case Polyhedron.cube:
        return _cubeVerts;
      case Polyhedron.icosa:
        return _icosaVerts;
    }
  }

  static List<List<int>> faces(Polyhedron p) {
    switch (p) {
      case Polyhedron.tetra:
        return _tetraFaces;
      case Polyhedron.octa:
        return _octaFaces;
      case Polyhedron.cube:
        return _cubeFaces;
      case Polyhedron.icosa:
        return _icosaFaces;
    }
  }
}

/// Pick the polyhedron family based on how much evidence the engine
/// has for a node. More support = more facets — shape complexity is
/// literally the engine's confidence in the node's relevance.
Polyhedron polyhedronFor(int support) {
  if (support <= 1) return Polyhedron.tetra;
  if (support <= 3) return Polyhedron.octa;
  if (support <= 6) return Polyhedron.cube;
  return Polyhedron.icosa;
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
  /// Just-intonation wavelength ratio versus the tonic (anchor).
  /// Comets picked from a consonant ratio (3/2, 4/3, …) reinforce
  /// the anchor when both fire; comets at a more dissonant ratio
  /// (9/8, 15/8) produce visible beat frequencies in the shader.
  /// Defaults to 1.0 (unison) so legacy construction sites still
  /// behave.
  final double pitch;
  /// Four-value timbre signature `(h1, h2, h3, phaseShift)`. The
  /// first three are amplitudes of the first three harmonics; the
  /// last doubles as per-source beat tempo and phase offset. Derived
  /// from the comet's simhash PCA coefficients in the caller so
  /// each source's wave *shape* encodes real evidence. Default
  /// `[1, 0, 0, 0]` is a pure cosine tonic.
  final List<double> harmonics;
  /// Evidence count for this node — witnesses + integrity reasons +
  /// transport siblings, whatever the builder chose to sum. Drives
  /// the polyhedron topology picker via [polyhedronFor]: more support
  /// = more facets = the engine has more to say about this node.
  final int support;
  final Object? tag;

  const Comet({
    required this.position,
    this.z = 0,
    required this.strength,
    required this.coreMass,
    required this.laneColor,
    required this.phase,
    this.shape = CometShape.circle,
    this.pitch = 1.0,
    this.harmonics = const [1.0, 0.0, 0.0, 0.0],
    this.support = 0,
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
  /// Monotonic breath-cycle count — ever-increasing real number where
  /// 1.0 = one full breath cycle of wall time. Sawtooth-free: every
  /// rotation consumer (polyhedron spin, link droplets) reads this
  /// and takes `% 1.0` itself if it wants a cycle position. Driving
  /// rotation off the raw value keeps quaternions coherent across
  /// the cycle boundary — no snap-back at the wrap.
  final double breathT;
  final double luminescence;
  final double edgeIntensity;
  final int? focusedIndex;
  /// Progress 0..1 of the focus-ring acquisition animation. Drives
  /// the ring's scale via [Curves.easeOutBack] (so it lands with a
  /// small overshoot past the rest radius, then settles at exactly
  /// the rest radius at t=1) and its alpha via [Curves.easeOutCubic]
  /// so brightness trails the scale by a half-beat. Default 1.0 =
  /// "already acquired" for legacy callers that don't animate the
  /// ring.
  final double focusRingT;
  final Offset? cursor;
  final CometCamera camera;
  final Offset anchor;
  final double staggerSpread;

  /// When luminescence drops below this, the traveling pulse on
  /// flow lines is suppressed. Respects the petrichor-plain intent
  /// that low-lum themes signal "no decoration".
  static const double silentPulseThreshold = 0.18;

  const CometField({
    required this.comets,
    this.links = const [],
    required this.introT,
    required this.breathT,
    this.luminescence = 1,
    this.edgeIntensity = 1,
    this.focusedIndex,
    this.focusRingT = 1.0,
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

      // Intro: emerge from the anchor along its target direction,
      // blending the default easeOutCubic with a snap-heavy
      // easeOutExpo based on the comet's own `strength`. Confident
      // nodes (anchor @ strength 1) snap into place; weak peripheral
      // echoes drift in soft. Confidence is tempo, not topology.
      final snappiness = c.strength.clamp(0.0, 1.0);
      final easeCubic = Curves.easeOutCubic.transform(tLocal);
      final easeExpo = Curves.easeOutExpo.transform(tLocal);
      final ease = easeCubic *
              (1.0 - snappiness * ManifoldTuning.introSnapBlend) +
          easeExpo * (snappiness * ManifoldTuning.introSnapBlend);
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
      // Support-driven presence lift — more evidence behind a node
      // makes it *physically larger*, not just more-faceted. Reads
      // as "this matters more" at a glance, without counting verts.
      final presence =
          1.0 + comets[i].support * ManifoldTuning.supportPresenceLift;
      reach.add(_staticRingRadius(comets[i].strength, locals[i]) *
          presence *
          scales[i]);
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

    // Anchor pixel for bezier sag. Links curve toward it so the web
    // reads as draping inward under gravity rather than as flat
    // polyline chords.
    final anchorPx = Offset(anchor.dx * size.width, anchor.dy * size.height);

    // Pass 0: flowing connection web. Each link renders as a honey-
    // gooey double-stroke (wider halo + narrower core) cubic bezier
    // with energy particles drifting along it. Peer links are always
    // visible at low alpha; focus tethers only appear while one of
    // their endpoints is hovered.
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
          alpha = (0.55 * link.strength * luminescence * progress)
              .clamp(0.0, 0.85);
        } else {
          final base = f == null
              ? 0.18
              : (isFocused ? 0.50 : 0.06);
          alpha = (base * link.strength * luminescence * progress)
              .clamp(0.0, 0.75);
        }
        if (alpha <= 0.01) continue;

        final a = lay.positions[link.fromIndex];
        final b = lay.positions[link.toIndex];

        // Cubic bezier draping toward the scene anchor — control
        // points pulled a third of the way from each endpoint
        // toward the anchor, giving a "hanging honey strand" sag.
        final m1 = Offset.lerp(a, anchorPx, 0.22)!;
        final c1 = Offset.lerp(a, m1, 0.55)!;
        final m2 = Offset.lerp(b, anchorPx, 0.22)!;
        final c2 = Offset.lerp(b, m2, 0.55)!;
        final path = Path()
          ..moveTo(a.dx, a.dy)
          ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.dx, b.dy);

        final scaleAvg =
            (lay.scales[link.fromIndex] + lay.scales[link.toIndex]) * 0.5;

        // Honey halo — wider, lower alpha. Gives thickness.
        final haloWidth =
            (2.4 * edgeIntensity * scaleAvg).clamp(0.5, 4.0);
        canvas.drawPath(
          path,
          Paint()
            ..color = link.color.withValues(alpha: alpha * 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = haloWidth
            ..strokeCap = StrokeCap.round,
        );

        // Honey core — narrower, brighter.
        final coreWidth =
            (1.1 * edgeIntensity * scaleAvg).clamp(0.4, 2.2);
        canvas.drawPath(
          path,
          Paint()
            ..color = link.color.withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = coreWidth
            ..strokeCap = StrokeCap.round,
        );

        // Energy droplets flowing along the strand. Three particles
        // staggered at 1/3 phase offsets; each fades in at the
        // start and out at the end of its travel via a sin
        // envelope so they don't pop at the endpoints.
        final metrics = path.computeMetrics().toList();
        if (metrics.isNotEmpty) {
          final metric = metrics.first;
          final len = metric.length;
          if (len > 1.0) {
            const droplets = 3;
            // Tempo scales with link strength — strong transport
            // pull surges droplets visibly faster than a weak edge.
            // Urgency is tempo, not label.
            final speed = ManifoldTuning.dropletBaseSpeed +
                link.strength * ManifoldTuning.dropletPullSpeedLift;
            for (var k = 0; k < droplets; k++) {
              final phaseOffset = k / droplets;
              final t = (breathT * speed + phaseOffset) % 1.0;
              final tangent =
                  metric.getTangentForOffset(t * len);
              if (tangent == null) continue;
              // sin(πt) peaks at t=0.5 — droplets brightest mid-strand.
              final envelope = math.sin(t * math.pi);
              final droplAlpha =
                  (alpha * 1.4 * envelope).clamp(0.0, 1.0);
              if (droplAlpha <= 0.02) continue;
              final droplRadius =
                  (1.3 + 0.6 * link.strength) * scaleAvg;
              canvas.drawCircle(
                tangent.position,
                droplRadius,
                Paint()
                  ..color = link.color.withValues(alpha: droplAlpha),
              );
            }
          }
        }
      }
    }

    // Pass 2+3 (unified): 3D polyhedron body per comet. Topology
    // comes from each comet's `support` count (tetra → icosa), pose
    // from the camera quaternion × a per-node base orientation × a
    // slow breath spin. PCA harmonics anisotropically stretch the
    // vertices so two same-family shapes still read as individual.
    // Ghosts draw wireframe-only — absence as skeletal outline.
    for (final i in lay.paintOrder) {
      final c = comets[i];
      final tLocal = lay.localTimes[i];
      if (tLocal <= 0) continue;

      final isGhost = c.coreMass <= 0.001;
      final bodyAlpha = ((0.88 * (isGhost ? 0.55 : c.coreMass)) * tLocal)
          .clamp(0.0, 1.0);
      if (bodyAlpha <= 0.01) continue;

      // Radius tracks the old ring reach so spacing density reads the
      // same — the polyhedron literally replaces the ring+core pair.
      final r = lay.reachRadii[i];
      if (r <= 0.5) continue;

      _paintPolyhedron(
        canvas,
        center: lay.positions[i],
        radius: r,
        comet: c,
        cameraYaw: camera.yaw,
        cameraPitch: camera.pitch,
        breathT: breathT,
        tLocal: tLocal,
        bodyAlpha: bodyAlpha,
        wireframe: isGhost,
      );
    }

    // Pass 4: focus ring — matches the underlying comet's style
    // (dashed for ghosts, solid for present). The ring pops in with
    // an overshoot (easeOutBack on radius) and brightens a half-beat
    // behind (easeOutCubic on alpha) — tells the body "yes, I heard
    // you" with a tiny weight transfer instead of a silent snap.
    final f = focusedIndex;
    if (f != null && f >= 0 && f < comets.length) {
      final tLocal = lay.localTimes[f];
      if (tLocal > 0) {
        final c = comets[f];
        final isGhost = c.coreMass <= 0.001;
        final ringT = focusRingT.clamp(0.0, 1.0);
        // easeOutBack starts at 0, passes ~1.1 near t≈0.8, lands
        // exactly at 1.0 — a bounded overshoot that uses the curve's
        // built-in "back" amount. No magic overshoot constant needed.
        final ringScale = Curves.easeOutBack.transform(ringT);
        final alphaT = Curves.easeOutCubic.transform(ringT);
        final baseR = lay.reachRadii[f] + 3.5;
        final r = baseR * ringScale;
        if (r > 0.5) {
          final w = _strokeWidth(1.3, lay.scales[f]);
          final paint = Paint()
            ..color = c.laneColor.withValues(
              alpha: (0.92 * luminescence * alphaT).clamp(0.0, 1.0),
            )
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
  }

  /// Render a per-comet polyhedron at [center] fitting inside radius
  /// [radius]. Faces are sorted back-to-front by rotated-z centroid
  /// and culled by face-normal dot viewer direction so silhouettes
  /// are genuinely 3D — rotating the camera reveals a different set
  /// of faces rather than just translating a flat sprite.
  void _paintPolyhedron(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Comet comet,
    required double cameraYaw,
    required double cameraPitch,
    required double breathT,
    required double tLocal,
    required double bodyAlpha,
    required bool wireframe,
  }) {
    // Anchor is forced to icosa regardless of evidence count — it's
    // the pinned line itself, the dense centerpiece of the scene.
    final topology = comet.shape == CometShape.diamond
        ? Polyhedron.icosa
        : polyhedronFor(comet.support);
    final verts = _Polyhedra.vertices(topology);
    final faces = _Polyhedra.faces(topology);

    // PCA / spectral harmonics drive anisotropic stretch. Clamps
    // enforce "vary, don't invert" — we want two icosas to look like
    // different icosas, not like a collapsed point.
    final h = comet.harmonics;
    final hx = h.length > 1 ? h[1] : 0.0;
    final hy = h.length > 2 ? h[2] : 0.0;
    final hz = h.length > 3 ? h[3] : 0.0;
    final sx = (1.0 + hx * ManifoldTuning.vertexStretchLateral)
        .clamp(ManifoldTuning.vertexStretchMinLateral,
            ManifoldTuning.vertexStretchMaxLateral);
    final sy = (1.0 + hy * ManifoldTuning.vertexStretchLateral)
        .clamp(ManifoldTuning.vertexStretchMinLateral,
            ManifoldTuning.vertexStretchMaxLateral);
    final sz = (1.0 + hz * ManifoldTuning.vertexStretchLongitudinal)
        .clamp(ManifoldTuning.vertexStretchMinLongitudinal,
            ManifoldTuning.vertexStretchMaxLongitudinal);
    // Chirality — sign of the dominant lateral harmonic flips spin
    // direction. Two same-family nodes with opposite principal-
    // component signs rotate opposite ways.
    final chirality = hx < 0 ? -1.0 : 1.0;

    // Per-node base orientation — stable per-frame, seeded by
    // `phase`. The irrational pitch/roll multipliers keep the three
    // rotation axes from syncing back to the same silhouette.
    final phaseAngle = comet.phase * 2 * math.pi;
    final baseYaw = phaseAngle;
    final basePitch = math.sin(phaseAngle * ManifoldTuning.posePitchPhaseMult) *
        ManifoldTuning.posePitchAmp;
    final baseRoll = math.cos(phaseAngle * ManifoldTuning.poseRollPhaseMult) *
        ManifoldTuning.poseRollAmp;

    // Data-derived spin rate: stronger nodes (anchor @ 1.0) breathe
    // slower / statelier; weaker nodes (peripheral echoes) rotate
    // more quickly. Harmonic energy adds per-node jitter so two
    // same-strength comets never lock in phase.
    final harmEnergy = math.sqrt(hx * hx + hy * hy + hz * hz);
    var spinTurnsPerCycle = (ManifoldTuning.spinBaseTurnsPerCycle +
            (1.0 - comet.strength) * ManifoldTuning.spinWeaknessLift +
            harmEnergy * ManifoldTuning.spinHarmonicJitter)
        .clamp(ManifoldTuning.spinMinTurnsPerCycle,
            ManifoldTuning.spinMaxTurnsPerCycle);
    // Ghost amplification — a ghost at the top of its strength band
    // (almost-present) fidgets up to `ghostSpinAmplification`× its
    // base rate; one at the bottom (deep background) is unchanged.
    // Absence that almost was a presence feels restless; forgotten
    // absence sits still.
    if (wireframe) {
      const ghostSpan = ManifoldTuning.scoreMaxGhost -
          ManifoldTuning.scoreMinGhost;
      final ghostStrength = ghostSpan > 0
          ? ((comet.strength - ManifoldTuning.scoreMinGhost) / ghostSpan)
              .clamp(0.0, 1.0)
              .toDouble()
          : 0.0;
      spinTurnsPerCycle *= 1.0 +
          ghostStrength * (ManifoldTuning.ghostSpinAmplification - 1.0);
    }
    // Monotonic breath-time means this angle grows without bound,
    // but quaternions wrap cleanly mod 2π — no visible seam at any
    // cycle boundary. This is the fix for the teleport bug.
    final breathAngle = breathT * 2 * math.pi * spinTurnsPerCycle * chirality;

    // Data-derived spin axis: each node rotates around a unit vector
    // unique to its (phase, harmonics) signature. Two cubes that used
    // to both spin around +Y now spin around genuinely different
    // lines — silhouettes move in visibly different ways.
    final axX = math.cos(phaseAngle) * ManifoldTuning.spinAxisPhaseWeight +
        hx * ManifoldTuning.spinAxisHarmonicLateralWeight;
    final axY = math.sin(phaseAngle) * ManifoldTuning.spinAxisPhaseWeight +
        hy * ManifoldTuning.spinAxisHarmonicLateralWeight;
    final axZ = hz * ManifoldTuning.spinAxisHarmonicLongitudinalWeight +
        ManifoldTuning.spinAxisLongitudinalBias;
    final axLen = math.sqrt(axX * axX + axY * axY + axZ * axZ);
    final double nax;
    final double nay;
    final double naz;
    if (axLen < 1e-6) {
      // Degenerate (all weights canceled) — fall back to +Z so the
      // node still rotates rather than freezing.
      nax = 0.0;
      nay = 0.0;
      naz = 1.0;
    } else {
      nax = axX / axLen;
      nay = axY / axLen;
      naz = axZ / axLen;
    }

    // Compose: camera × base orientation × breath spin. Order matters —
    // breath-spin is innermost (local to the node), then base
    // orientation, then camera so the whole scene still rotates
    // coherently as the user slerps perspective.
    final qCam = _Quat.yawPitch(cameraYaw, cameraPitch);
    final qBaseYP = _Quat.yawPitch(baseYaw, basePitch);
    final qRoll = _Quat.axisAngle(0, 0, 1, baseRoll);
    final qSpin = _Quat.axisAngle(nax, nay, naz, breathAngle);
    final qTotal = qCam * qBaseYP * qRoll * qSpin;

    // Scale to the target pixel radius. Poly vertices live in the
    // unit sphere; multiplying by radius fits them to the comet's
    // reach.
    final projected = List<Offset>.filled(verts.length, Offset.zero);
    final zDepths = List<double>.filled(verts.length, 0);
    for (var vi = 0; vi < verts.length; vi++) {
      final v = verts[vi];
      final (rx, ry, rz) =
          qTotal.rotate(v.$1 * sx * radius, v.$2 * sy * radius, v.$3 * sz * radius);
      projected[vi] = Offset(center.dx + rx, center.dy + ry);
      zDepths[vi] = rz;
    }

    // Per-face: centroid z for paint ordering, rotated normal for
    // backface test. Normal comes from two in-plane edges of each
    // face (v1 - v0) × (v2 - v0) — consistent CCW winding gives
    // outward-pointing normals, so after rotation a positive Z
    // component means the face is pointing toward the viewer.
    final faceDepth = List<double>.filled(faces.length, 0);
    final faceFront = List<bool>.filled(faces.length, false);
    for (var fi = 0; fi < faces.length; fi++) {
      final face = faces[fi];
      var z = 0.0;
      for (final vi in face) {
        z += zDepths[vi];
      }
      faceDepth[fi] = z / face.length;

      final v0 = verts[face[0]];
      final v1 = verts[face[1]];
      final v2 = verts[face[2]];
      final ex = v1.$1 - v0.$1;
      final ey = v1.$2 - v0.$2;
      final ez = v1.$3 - v0.$3;
      final fx = v2.$1 - v0.$1;
      final fy = v2.$2 - v0.$2;
      final fz = v2.$3 - v0.$3;
      final nx = ey * fz - ez * fy;
      final ny = ez * fx - ex * fz;
      final nz = ex * fy - ey * fx;
      final (_, _, nrz) = qTotal.rotate(nx, ny, nz);
      // Viewer direction is +Z after projection (camera looks down
      // the negative Z / into the scene). Positive rotated nz means
      // the face normal points back at the viewer — front-facing.
      faceFront[fi] = nrz >= 0;
    }

    final order = List<int>.generate(faces.length, (i) => i);
    order.sort((a, b) => faceDepth[a].compareTo(faceDepth[b]));

    final edgeAlpha =
        ((0.55 + 0.30 * comet.strength) * luminescence * tLocal)
            .clamp(0.0, 0.95);
    final edgePaint = Paint()
      ..color = comet.laneColor.withValues(alpha: edgeAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (0.9 * edgeIntensity).clamp(0.3, 2.0)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    for (final fi in order) {
      if (!faceFront[fi]) continue;
      final face = faces[fi];

      final path = Path()
        ..moveTo(projected[face[0]].dx, projected[face[0]].dy);
      for (var k = 1; k < face.length; k++) {
        path.lineTo(projected[face[k]].dx, projected[face[k]].dy);
      }
      path.close();

      if (!wireframe) {
        // Cheap Lambert-ish shading: face-centroid depth doubles as
        // a "how much does this face face the viewer" proxy. Brighter
        // at the front, dimmer at the rim — gives real volume without
        // needing a light source.
        final centroidShade =
            (0.72 + 0.28 * (faceDepth[fi] / (radius + 0.01)))
                .clamp(0.40, 1.0);
        canvas.drawPath(
          path,
          Paint()
            ..color = comet.laneColor.withValues(
              alpha: (bodyAlpha * centroidShade * 0.72).clamp(0.0, 1.0),
            ),
        );
      }
      if (edgeAlpha > 0.01 && edgePaint.strokeWidth > 0.01) {
        canvas.drawPath(path, edgePaint);
      }
    }
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
      old.focusRingT != focusRingT ||
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

      // Same strength-weighted ease as the chart intro — flows with
      // strong transport pull snap into place; weak flows drift.
      final snappiness = f.strength.clamp(0.0, 1.0);
      final easeCubic = Curves.easeOutCubic.transform(tLocal);
      final easeExpo = Curves.easeOutExpo.transform(tLocal);
      final ease = easeCubic *
              (1.0 - snappiness * ManifoldTuning.introSnapBlend) +
          easeExpo * (snappiness * ManifoldTuning.introSnapBlend);
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
