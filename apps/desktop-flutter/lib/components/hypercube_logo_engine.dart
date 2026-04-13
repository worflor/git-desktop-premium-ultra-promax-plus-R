import 'dart:math' as math;
import 'dart:ui';

const List<List<double>> hypercubeStates = <List<double>>[
  <double>[0.35, 0.35, 0.1, 0.35, 0.1, 0.1],
  <double>[0.5, 0.8, 0.2, 1.2, 0.5, 0.1],
  <double>[1.5, 0.3, 2.1, 0.1, 0.9, 0.6],
  <double>[2.1, 1.5, 0.8, 3.1, 0.4, 1.2],
  <double>[3.14, 2.1, 1.5, 0.8, 0.1, 3.14],
  <double>[0.8, 1.6, 3.2, 0.4, 4.0, 1.2],
  <double>[1.57, 0, 1.57, 0, 1.57, 0],
  <double>[0, 0.785, 0, 0, 0.785, 0],
  <double>[0.4, 0.2, 3.142, 3.142, 0.2, 0.4],
  <double>[0.1, 0.1, 2.356, 0.1, 2.356, 2.356],
  <double>[0, 0.4, 3.142, 0, 3.142, 0],
  <double>[0.785, 0, 0, 0, 0, 0.785],
  <double>[0, 0, 1.57, 0, 1.57, 0],
];

final List<List<double>> hypercubeVertices = List<List<double>>.unmodifiable(
  List<List<double>>.generate(
    16,
    (int i) => <double>[
      ((i & 1) << 1) - 1,
      (i & 2) - 1,
      ((i & 4) >> 1) - 1,
      ((i & 8) >> 2) - 1,
    ],
    growable: false,
  ),
);

final List<(int, int)> hypercubeEdges =
    List<(int, int)>.unmodifiable(_buildEdges());

final List<List<List<double>>> _stateVertices =
    List<List<List<double>>>.unmodifiable(
  hypercubeStates
      .map(
        (List<double> state) => List<List<double>>.unmodifiable(
          hypercubeVertices
              .map((List<double> vertex) => rotate4D(vertex, state))
              .toList(growable: false),
        ),
      )
      .toList(growable: false),
);

final List<Set<int>> _tooCloseIdsByState = List<Set<int>>.unmodifiable(
  _buildTooCloseIdsByState(),
);

const double warpSettledThreshold = 0.01;

class HypercubeProjectedPoint {
  const HypercubeProjectedPoint({
    required this.point,
    required this.z,
    required this.w,
  });

  final Offset point;
  final double z;
  final double w;
}

class HypercubeProjectedData {
  const HypercubeProjectedData({
    required this.main,
    required this.home,
    required this.ghost,
  });

  final List<HypercubeProjectedPoint> main;
  final List<HypercubeProjectedPoint> home;
  final List<HypercubeProjectedPoint> ghost;
}

class HypercubeLogoEngine {
  HypercubeLogoEngine({int? seed}) : _rngState = _normalizeSeed(seed);

  static const int _mask32 = 0xFFFFFFFF;
  static const double _spring = 800;
  static const double _dampingPerSecond = 21.400478750629333;

  // Accelerated damping for warp/tilt residue when reducing, so hover/drag
  // trails die quickly without a visible spring wobble. The pose itself
  // stays frozen wherever it was at the moment of toggle — no canonical
  // "rest index", no teleport to a preset pose.
  static const double _reducedDampingMultiplier = 2.0;

  // Reduce-motion singularity teleport. When the user releases a drag
  // under reduce-motion, the cube doesn't drift back via spring physics
  // (that would be sustained motion). Instead it shrinks to a point at
  // the drag-release location, then grows back at origin — two brief
  // impulses totalling ~290ms. Technically still motion, but the kind
  // that satisfies the spirit of "reduced": no continuous drift, no
  // spring oscillation.
  static const double _implodeRatePerSecond = 8.0; // 1 → 0 in ~125ms
  static const double _explodeRatePerSecond = 6.0; // 0 → 1 in ~166ms

  int _rngState;
  final List<int> _history = <int>[0, 1];

  double time = 0;
  double smoothBoost = 1;
  int currentIndex = 0;
  int targetIndex = 1;
  double transition = 0;
  double near = 0;
  bool dragging = false;
  double tiltX = 0;
  double tiltY = 0;
  double warpX = 0;
  double warpY = 0;
  double warpVx = 0;
  double warpVy = 0;

  bool _reduced = false;

  // 1.0 = fully visible; 0.0 = collapsed to a singularity. Multiplied
  // into the projection's scale, so the cube shrinks/grows uniformly
  // around its current position. Only non-1.0 during the reduced-motion
  // drag-release teleport.
  double _materialize = 1.0;
  _MaterializePhase _materializePhase = _MaterializePhase.idle;

  bool get isReduced => _reduced;

  /// True when the engine's *transient* state (warp, tilt, hover) has
  /// fully settled in reduced mode. The pose itself is already frozen —
  /// widgets just wait for residual motion to die out before stopping
  /// the ticker.
  ///
  /// Never true while:
  ///   * dragging — the user is actively moving the cube
  ///   * materializing — the implode/explode sequence needs frames
  ///   * materialize scale hasn't fully returned to 1
  bool get isAtReducedRest {
    if (!_reduced) return false;
    if (dragging) return false;
    if (_materializePhase != _MaterializePhase.idle) return false;
    if ((_materialize - 1.0).abs() > warpSettledThreshold) return false;
    return (warpX.abs() + warpY.abs() + warpVx.abs() + warpVy.abs() +
            tiltX.abs() + tiltY.abs() + near) <
        warpSettledThreshold;
  }

  Offset get tilt => Offset(tiltX, tiltY);
  Offset get warp => Offset(warpX, warpY);

  bool get isIdleVisualState {
    if (near > 0 || dragging) {
      return false;
    }
    return (warpX.abs() + warpY.abs() + warpVx.abs() + warpVy.abs()) <
        warpSettledThreshold;
  }

  void step(double dt, {double speed = 0.85}) {
    if (_reduced) {
      _stepReduced(dt);
      return;
    }
    final double targetBoost = 1 + near * 1.2 + (dragging ? 2.3 : 0);
    smoothBoost += (targetBoost - smoothBoost) * dt * 12;
    time += dt * speed * smoothBoost;

    final List<double> start = hypercubeStates[currentIndex];
    final List<double> end = hypercubeStates[targetIndex];
    double distSquared = 0;
    for (int i = 0; i < start.length; i++) {
      final double delta = start[i] - end[i];
      distSquared += delta * delta;
    }
    final double distMult = 0.9 + math.min(math.sqrt(distSquared) * 0.1, 0.1);
    transition += 0.095 * dt * smoothBoost * distMult;
    while (transition >= 1) {
      currentIndex = targetIndex;
      targetIndex = pickNextIndex();
      transition -= 1;
    }

    if (!dragging) {
      final double damping = math.exp(-_dampingPerSecond * dt);
      final double ax = -_spring * warpX;
      final double ay = -_spring * warpY;
      warpVx = (warpVx + ax * dt) * damping;
      warpVy = (warpVy + ay * dt) * damping;
      warpX += warpVx * dt;
      warpY += warpVy * dt;
      if (isIdleVisualState) {
        warpX = 0;
        warpY = 0;
        warpVx = 0;
        warpVy = 0;
      }
    }
  }

  /// Reduce-motion step.
  ///
  /// Freezes the pose exactly where the engine was at toggle time:
  ///   * `time` does not advance → projection-pipeline breathing locked.
  ///   * `transition` does not advance → the state lerp stops at its
  ///      current fraction, so a mid-transition toggle holds that
  ///      intermediate pose rather than snapping to either endpoint.
  ///   * `smoothBoost` re-settles to 1 so a re-enter into normal mode
  ///      doesn't inherit a stale hover boost.
  ///   * While dragging, warp is driven directly by [updatePointer] each
  ///     frame — we don't apply damping here or the user's pull would
  ///     get fought. After release, damping kicks in and the cube
  ///     glides back to its resting pose.
  void _stepReduced(double dt) {
    smoothBoost = 1;
    if (dragging) {
      // Active drag — user owns the warp. Abort any residual phase so
      // re-grab during an in-flight materialize aborts gracefully.
      _materialize = 1.0;
      _materializePhase = _MaterializePhase.idle;
      return;
    }

    // Phase 1: implode. Shrink at the current (warped) position.
    if (_materializePhase == _MaterializePhase.imploding) {
      _materialize -= _implodeRatePerSecond * dt;
      if (_materialize <= 0) {
        _materialize = 0;
        // Singularity reached — teleport home and flip to explode.
        warpX = 0;
        warpY = 0;
        warpVx = 0;
        warpVy = 0;
        tiltX = 0;
        tiltY = 0;
        near = 0;
        _materializePhase = _MaterializePhase.exploding;
      }
      return;
    }

    // Phase 2: explode. Grow back from singularity at origin.
    if (_materializePhase == _MaterializePhase.exploding) {
      _materialize += _explodeRatePerSecond * dt;
      if (_materialize >= 1.0) {
        _materialize = 1.0;
        _materializePhase = _MaterializePhase.idle;
      }
      return;
    }

    // Idle: just damp any leftover hover residue. No spring restore —
    // that would be the continuous drift we're specifically avoiding.
    final double damping =
        math.exp(-_dampingPerSecond * _reducedDampingMultiplier * dt);
    warpVx *= damping;
    warpVy *= damping;
    warpX += warpVx * dt;
    warpY += warpVy * dt;
    tiltX *= damping;
    tiltY *= damping;
    near *= damping;
    if (warpX.abs() < warpSettledThreshold) warpX = 0;
    if (warpY.abs() < warpSettledThreshold) warpY = 0;
    if (warpVx.abs() < warpSettledThreshold) warpVx = 0;
    if (warpVy.abs() < warpSettledThreshold) warpVy = 0;
    if (tiltX.abs() < warpSettledThreshold) tiltX = 0;
    if (tiltY.abs() < warpSettledThreshold) tiltY = 0;
    if (near.abs() < warpSettledThreshold) near = 0;
  }

  /// Flip the engine into / out of reduce-motion mode.
  ///
  /// When entering, the pose freezes exactly where it is — no target
  /// pose, no teleport. When [randomizeOnEnter] is true the engine
  /// *first* picks a random pose (current + target indices and a random
  /// mid-transition fraction), then freezes. Use this on fresh launches
  /// where reduce-motion was already on — the alternative is every cold
  /// start showing the same initial pose, which reads as mechanical.
  ///
  /// When exiting, cycling resumes from wherever the pose was held.
  void setReduced(bool value, {bool randomizeOnEnter = false}) {
    if (_reduced == value) return;
    _reduced = value;
    // Abort any in-flight materialize. Whichever mode we're entering
    // owns the warp from here — normal spring physics if leaving
    // reduce, idle damping if entering.
    _materialize = 1.0;
    _materializePhase = _MaterializePhase.idle;
    if (value && randomizeOnEnter) {
      _randomizeFrozenPose();
    }
  }

  /// Pick a random pose to freeze at. Used only when entering reduce-
  /// motion at widget mount — mid-session toggles intentionally preserve
  /// whatever pose the user was looking at.
  void _randomizeFrozenPose() {
    final int count = hypercubeStates.length;
    final int fresh = (_xorshift64() * count).floor().clamp(0, count - 1);
    currentIndex = fresh;
    int other;
    do {
      other = (_xorshift64() * count).floor().clamp(0, count - 1);
    } while (other == fresh);
    targetIndex = other;
    // 0..1 mid-transition fraction — allows the frozen pose to be
    // anywhere along the lerp between the two states, not just at a
    // canonical endpoint.
    transition = _xorshift64();
    // Reset history so a later exit-from-reduced doesn't start cycling
    // based on stale indices from before mount.
    _history
      ..clear()
      ..addAll(<int>[currentIndex, targetIndex]);
    // Kill transient state so the cube reads as still from frame 0.
    warpX = 0;
    warpY = 0;
    warpVx = 0;
    warpVy = 0;
    tiltX = 0;
    tiltY = 0;
    near = 0;
  }

  int pickNextIndex() {
    final int sourceIndex = targetIndex;
    final Set<int> tooCloseIds = _tooCloseIdsByState[sourceIndex];

    final List<int> available = List<int>.generate(
      hypercubeStates.length,
      (int i) => i,
      growable: false,
    ).where((int i) {
      return i != sourceIndex &&
          !_history.contains(i) &&
          !tooCloseIds.contains(i);
    }).toList(growable: false);

    final int next;
    if (available.isEmpty) {
      next = (sourceIndex + 2) % hypercubeStates.length;
    } else {
      final double rand = _xorshift64();
      final int index = (rand * available.length).floor();
      next = index >= available.length
          ? (sourceIndex + 2) % hypercubeStates.length
          : available[index];
    }

    _history.add(next);
    if (_history.length > 4) {
      _history.removeAt(0);
    }
    return next;
  }

  void updatePointer({
    required Offset delta,
    required double size,
  }) {
    // Reduce-motion: the logo is still a grabbable, movable object — the
    // drag is intentional, user-initiated motion, not ambient ornament.
    // Only the passive hover responses (tilt + near-proximity boost) are
    // suppressed so the cube doesn't wiggle or glow when the cursor
    // merely crosses it.
    if (_reduced) {
      if (dragging) {
        warpX = delta.dx;
        warpY = delta.dy;
        warpVx = 0;
        warpVy = 0;
      }
      return;
    }
    final double distance = delta.distance;
    tiltX = delta.dx / size;
    tiltY = delta.dy / size;
    near = math.max(0, 1 - distance / (size * 3));
    if (dragging) {
      warpX = delta.dx;
      warpY = delta.dy;
      warpVx = 0;
      warpVy = 0;
    }
  }

  void setDragging(bool value) {
    final wasDragging = dragging;
    dragging = value;
    if (value) {
      // Starting a new drag — abort any in-flight materialize so the
      // cube snaps back to full size at the user's cursor. Regrabbing
      // mid-materialize shouldn't leave them tugging on a shrunken ghost.
      _materialize = 1.0;
      _materializePhase = _MaterializePhase.idle;
      return;
    }
    if (wasDragging && _reduced) {
      // Released under reduce-motion. If the cube is displaced, kick
      // off the implode → teleport → explode sequence. Otherwise stay
      // idle — nothing to teleport.
      if (warpX.abs() + warpY.abs() > warpSettledThreshold) {
        _materializePhase = _MaterializePhase.imploding;
      }
    }
  }

  void handlePointerExit() {
    near = 0;
    if (!dragging) {
      tiltX = 0;
      tiltY = 0;
    }
  }

  HypercubeProjectedData projectedData(double size) {
    final List<double> start = hypercubeStates[currentIndex];
    final List<double> end = hypercubeStates[targetIndex];
    final double t = transition;
    final double interp = t * t * (3 - 2 * t);
    final double angleXY = start[0] + (end[0] - start[0]) * interp;
    final double angleXZ = start[1] + (end[1] - start[1]) * interp;
    final double angleXW = start[2] + (end[2] - start[2]) * interp;
    final double angleYZ = start[3] + (end[3] - start[3]) * interp;
    final double angleYW = start[4] + (end[4] - start[4]) * interp;
    final double angleZW = start[5] + (end[5] - start[5]) * interp;
    final bool includeHome = (near * 0.35 + (dragging ? 0.3 : 0)) > 0.01;
    final bool includeGhost = (near * 0.15) > 0.01;

    return HypercubeProjectedData(
      main: _solveProjection(
        size: size,
        baseXY: angleXY,
        baseXZ: angleXZ,
        baseXW: angleXW,
        baseYZ: angleYZ,
        baseYW: angleYW,
        baseZW: angleZW,
        tOffset: 0,
        fovOffset: 0,
        useWarp: true,
      ),
      home: includeHome
          ? _solveProjection(
              size: size,
              baseXY: angleXY,
              baseXZ: angleXZ,
              baseXW: angleXW,
              baseYZ: angleYZ,
              baseYW: angleYW,
              baseZW: angleZW,
              tOffset: -0.2,
              fovOffset: 0.04,
              useWarp: false,
            )
          : const <HypercubeProjectedPoint>[],
      ghost: includeGhost
          ? _solveProjection(
              size: size,
              baseXY: angleXY,
              baseXZ: angleXZ,
              baseXW: angleXW,
              baseYZ: angleYZ,
              baseYW: angleYW,
              baseZW: angleZW,
              tOffset: -0.4,
              fovOffset: 0.08,
              useWarp: false,
            )
          : const <HypercubeProjectedPoint>[],
    );
  }

  List<HypercubeProjectedPoint> _solveProjection({
    required double size,
    required double baseXY,
    required double baseXZ,
    required double baseXW,
    required double baseYZ,
    required double baseYW,
    required double baseZW,
    required double tOffset,
    required double fovOffset,
    required bool useWarp,
  }) {
    // `_materialize` is 1.0 outside the reduce-motion teleport. During
    // the implode → explode sequence it ramps 1 → 0 → 1, collapsing all
    // vertices to the current canvas offset (warped, then origin after
    // the mid-sequence teleport) and growing them back.
    final double scale = size *
        1.55 *
        (1 + math.sin((time + tOffset) * 0.4) * 0.05 * near) *
        _materialize;
    final double warpRotation = useWarp ? (warpX + warpY) / size * 0.2 : 0;
    final double oscillation = math.sin((time + tOffset) * 0.1) * 0.05;
    final _RotationFrame rotation = _RotationFrame(
      xy: _RotationPair(
        c: math.cos(baseXY + tiltX * 0.5 + (useWarp ? warpX / size * 0.8 : 0)),
        s: math.sin(baseXY + tiltX * 0.5 + (useWarp ? warpX / size * 0.8 : 0)),
      ),
      xz: _RotationPair(
        c: math.cos(baseXZ + tiltY * 0.5 + (useWarp ? warpY / size * 0.8 : 0)),
        s: math.sin(baseXZ + tiltY * 0.5 + (useWarp ? warpY / size * 0.8 : 0)),
      ),
      xw: _RotationPair(
        c: math.cos(baseXW + oscillation + warpRotation),
        s: math.sin(baseXW + oscillation + warpRotation),
      ),
      yz: _RotationPair(
        c: math.cos(baseYZ + oscillation + warpRotation),
        s: math.sin(baseYZ + oscillation + warpRotation),
      ),
      yw: _RotationPair(
        c: math.cos(baseYW + oscillation + warpRotation),
        s: math.sin(baseYW + oscillation + warpRotation),
      ),
      zw: _RotationPair(
        c: math.cos(baseZW + oscillation + warpRotation),
        s: math.sin(baseZW + oscillation + warpRotation),
      ),
    );
    final List<HypercubeProjectedPoint> points =
        List<HypercubeProjectedPoint>.filled(
      hypercubeVertices.length,
      const HypercubeProjectedPoint(point: Offset.zero, z: 0, w: 0),
      growable: false,
    );
    for (int i = 0; i < hypercubeVertices.length; i++) {
      points[i] = _projectVertex(
        hypercubeVertices[i],
        rotation,
        size: size,
        scale: scale,
        fovOffset: fovOffset,
        useWarp: useWarp,
      );
    }
    return points;
  }

  HypercubeProjectedPoint _projectVertex(
    List<double> vertex,
    _RotationFrame rotation, {
    required double size,
    required double scale,
    required double fovOffset,
    required bool useWarp,
  }) {
    double x = vertex[0];
    double y = vertex[1];
    double z = vertex[2];
    double w = vertex[3];

    double tx = x * rotation.xy.c - y * rotation.xy.s;
    double ty = x * rotation.xy.s + y * rotation.xy.c;
    x = tx;
    y = ty;

    tx = x * rotation.xz.c - z * rotation.xz.s;
    double tz = x * rotation.xz.s + z * rotation.xz.c;
    x = tx;
    z = tz;

    tx = x * rotation.xw.c - w * rotation.xw.s;
    double tw = x * rotation.xw.s + w * rotation.xw.c;
    x = tx;
    w = tw;

    ty = y * rotation.yz.c - z * rotation.yz.s;
    tz = y * rotation.yz.s + z * rotation.yz.c;
    y = ty;
    z = tz;

    ty = y * rotation.yw.c - w * rotation.yw.s;
    tw = y * rotation.yw.s + w * rotation.yw.c;
    y = ty;
    w = tw;

    tz = z * rotation.zw.c - w * rotation.zw.s;
    tw = z * rotation.zw.s + w * rotation.zw.c;
    z = tz;
    w = tw;

    final double fov4D = 1 / math.max(0.01, 2.4 - near * 0.3 + fovOffset - w);
    final double fov3D = 1 / math.max(0.01, 3.6 - z);
    final double combinedFov = fov4D * fov3D;
    final double sx = x * combinedFov;
    final double sy = y * combinedFov;
    final double meldStrength = useWarp ? near * 0.45 : 0;
    double px = sx * scale + size / 2 + (useWarp ? warpX : 0);
    double py = sy * scale + size / 2 + (useWarp ? warpY : 0);
    if (useWarp && near > 0.5) {
      px += warpX * meldStrength;
      py += warpY * meldStrength;
    }
    return HypercubeProjectedPoint(point: Offset(px, py), z: z, w: w);
  }

  double _xorshift64() {
    _rngState ^= (_rngState << 13) & _mask32;
    _rngState &= _mask32;
    _rngState ^= (_rngState >> 17);
    _rngState &= _mask32;
    _rngState ^= (_rngState << 5) & _mask32;
    _rngState &= _mask32;
    return _rngState.toDouble() / _mask32;
  }

  static int _normalizeSeed(int? seed) {
    final int sourceSeed = seed ?? DateTime.now().millisecondsSinceEpoch;
    final int value = sourceSeed.abs() & _mask32;
    if (value == 0) {
      return 1;
    }
    return value;
  }
}

List<double> rotate4D(List<double> coords, List<double> angles) {
  final _RotationFrame rotation = _RotationFrame(
    xy: _RotationPair(c: math.cos(angles[0]), s: math.sin(angles[0])),
    xz: _RotationPair(c: math.cos(angles[1]), s: math.sin(angles[1])),
    xw: _RotationPair(c: math.cos(angles[2]), s: math.sin(angles[2])),
    yz: _RotationPair(c: math.cos(angles[3]), s: math.sin(angles[3])),
    yw: _RotationPair(c: math.cos(angles[4]), s: math.sin(angles[4])),
    zw: _RotationPair(c: math.cos(angles[5]), s: math.sin(angles[5])),
  );
  double x = coords[0];
  double y = coords[1];
  double z = coords[2];
  double w = coords[3];

  double tx = x * rotation.xy.c - y * rotation.xy.s;
  double ty = x * rotation.xy.s + y * rotation.xy.c;
  x = tx;
  y = ty;

  tx = x * rotation.xz.c - z * rotation.xz.s;
  double tz = x * rotation.xz.s + z * rotation.xz.c;
  x = tx;
  z = tz;

  tx = x * rotation.xw.c - w * rotation.xw.s;
  double tw = x * rotation.xw.s + w * rotation.xw.c;
  x = tx;
  w = tw;

  ty = y * rotation.yz.c - z * rotation.yz.s;
  tz = y * rotation.yz.s + z * rotation.yz.c;
  y = ty;
  z = tz;

  ty = y * rotation.yw.c - w * rotation.yw.s;
  tw = y * rotation.yw.s + w * rotation.yw.c;
  y = ty;
  w = tw;

  tz = z * rotation.zw.c - w * rotation.zw.s;
  tw = z * rotation.zw.s + w * rotation.zw.c;
  z = tz;
  w = tw;

  return <double>[x, y, z, w];
}

/// Phase machine for the reduce-motion drag-release teleport.
///   idle       — no teleport in flight; materialize held at 1.0.
///   imploding  — _materialize ramping 1 → 0 at the drag-release offset.
///   exploding  — _materialize ramping 0 → 1 at origin after teleport.
enum _MaterializePhase { idle, imploding, exploding }

class _RotationPair {
  const _RotationPair({required this.c, required this.s});

  final double c;
  final double s;
}

class _RotationFrame {
  const _RotationFrame({
    required this.xy,
    required this.xz,
    required this.xw,
    required this.yz,
    required this.yw,
    required this.zw,
  });

  final _RotationPair xy;
  final _RotationPair xz;
  final _RotationPair xw;
  final _RotationPair yz;
  final _RotationPair yw;
  final _RotationPair zw;
}

List<(int, int)> _buildEdges() {
  final List<(int, int)> edges = <(int, int)>[];
  for (int i = 0; i < 16; i++) {
    for (int j = i + 1; j < 16; j++) {
      final int diff = i ^ j;
      if (diff != 0 && (diff & (diff - 1)) == 0) {
        edges.add((i, j));
      }
    }
  }
  return edges;
}

List<Set<int>> _buildTooCloseIdsByState() {
  return List<Set<int>>.generate(_stateVertices.length, (int sourceIndex) {
    final List<List<double>> currentVerts = _stateVertices[sourceIndex];
    final List<({int id, double d})> sortedDistances =
        List<({int id, double d})>.generate(_stateVertices.length - 1, (int raw) {
      final int stateIndex = raw >= sourceIndex ? raw + 1 : raw;
      final List<List<double>> otherVerts = _stateVertices[stateIndex];
      double sum = 0;
      double c = 0;
      for (int j = 0; j < currentVerts.length; j++) {
        final List<double> v1 = currentVerts[j];
        final List<double> v2 = otherVerts[j];
        final double dx = v1[0] - v2[0];
        final double dy = v1[1] - v2[1];
        final double dz = v1[2] - v2[2];
        final double dw = v1[3] - v2[3];
        final double y = math.sqrt(dx * dx + dy * dy + dz * dz + dw * dw) - c;
        final double t = sum + y;
        c = (t - sum) - y;
        sum = t;
      }
      return (id: stateIndex, d: sum);
    }, growable: false)
          ..sort((({double d, int id}) a, ({double d, int id}) b) {
            return a.d.compareTo(b.d);
          });
    return sortedDistances.take(2).map((({double d, int id}) x) => x.id).toSet();
  }, growable: false);
}
