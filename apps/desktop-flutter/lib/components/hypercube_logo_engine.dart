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

const double warpSettledThreshold = 0.01;
const Duration idleFrameInterval = Duration(milliseconds: 100);

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

  static final BigInt _mask64 = BigInt.parse('FFFFFFFFFFFFFFFF', radix: 16);
  static final BigInt _mask32 = BigInt.parse('FFFFFFFF', radix: 16);

  BigInt _rngState;
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
    if (transition >= 1) {
      currentIndex = targetIndex;
      targetIndex = pickNextIndex();
      transition = 0;
    }

    if (!dragging) {
      const double spring = 800;
      const double damp = 0.7;
      final double ax = -spring * warpX;
      final double ay = -spring * warpY;
      warpVx = (warpVx + ax * dt) * damp;
      warpVy = (warpVy + ay * dt) * damp;
      warpX += warpVx * dt;
      warpY += warpVy * dt;
    }
  }

  int pickNextIndex() {
    final int sourceIndex = targetIndex;
    final List<List<double>> currentVerts = _stateVertices[sourceIndex];
    final List<({int id, double d})> distData = <({int id, double d})>[];
    for (int i = 0; i < _stateVertices.length; i++) {
      if (i == sourceIndex) {
        distData.add((id: i, d: 0.0));
        continue;
      }
      final List<List<double>> otherVerts = _stateVertices[i];
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
      distData.add((id: i, d: sum));
    }

    final List<({int id, double d})> sortedDistances = distData
        .where((({double d, int id}) x) => x.id != sourceIndex)
        .toList(growable: false)
      ..sort((({double d, int id}) a, ({double d, int id}) b) {
        return a.d.compareTo(b.d);
      });
    final Set<int> tooCloseIds = sortedDistances
        .take(2)
        .map((({double d, int id}) x) => x.id)
        .toSet();

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
    dragging = value;
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
    final List<double> angles = List<double>.generate(
      start.length,
      (int i) => start[i] + (end[i] - start[i]) * interp,
      growable: false,
    );

    List<HypercubeProjectedPoint> solve(
      double tOffset,
      double fovOffset,
      bool useWarp,
    ) {
      final double scale =
          size * 1.55 * (1 + math.sin((time + tOffset) * 0.4) * 0.05 * near);
      final List<double> solvedAngles = List<double>.generate(
        angles.length,
        (int i) {
          double angle = angles[i];
          if (i == 0) {
            angle += tiltX * 0.5 + (useWarp ? warpX / size * 0.8 : 0);
          } else if (i == 1) {
            angle += tiltY * 0.5 + (useWarp ? warpY / size * 0.8 : 0);
          } else {
            angle += math.sin((time + tOffset) * 0.1) * 0.05 +
                (useWarp ? (warpX + warpY) / size * 0.2 : 0);
          }
          return angle;
        },
        growable: false,
      );

      return hypercubeVertices.map((List<double> vertex) {
        final List<double> rotated = rotate4D(vertex, solvedAngles);
        final double x = rotated[0];
        final double y = rotated[1];
        final double z = rotated[2];
        final double w = rotated[3];
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
      }).toList(growable: false);
    }

    return HypercubeProjectedData(
      main: solve(0, 0, true),
      home: solve(-0.2, 0.04, false),
      ghost: solve(-0.4, 0.08, false),
    );
  }

  double _xorshift64() {
    _rngState ^= (_rngState << 13) & _mask64;
    _rngState ^= (_rngState >> 7);
    _rngState ^= (_rngState << 17) & _mask64;
    return (_rngState & _mask32).toDouble() / 0xFFFFFFFF;
  }

  static BigInt _normalizeSeed(int? seed) {
    final int sourceSeed = seed ?? DateTime.now().millisecondsSinceEpoch;
    final BigInt value = BigInt.from(sourceSeed).abs();
    if (value == BigInt.zero) {
      return BigInt.one;
    }
    return value & _mask64;
  }
}

List<double> rotate4D(List<double> coords, List<double> angles) {
  double x = coords[0];
  double y = coords[1];
  double z = coords[2];
  double w = coords[3];

  final List<_RotationPair> rotations = angles
      .map((double angle) => _RotationPair(c: math.cos(angle), s: math.sin(angle)))
      .toList(growable: false);
  final _RotationPair rXY = rotations[0];
  final _RotationPair rXZ = rotations[1];
  final _RotationPair rXW = rotations[2];
  final _RotationPair rYZ = rotations[3];
  final _RotationPair rYW = rotations[4];
  final _RotationPair rZW = rotations[5];

  double tx = x * rXY.c - y * rXY.s;
  double ty = x * rXY.s + y * rXY.c;
  x = tx;
  y = ty;

  tx = x * rXZ.c - z * rXZ.s;
  double tz = x * rXZ.s + z * rXZ.c;
  x = tx;
  z = tz;

  tx = x * rXW.c - w * rXW.s;
  double tw = x * rXW.s + w * rXW.c;
  x = tx;
  w = tw;

  ty = y * rYZ.c - z * rYZ.s;
  tz = y * rYZ.s + z * rYZ.c;
  y = ty;
  z = tz;

  ty = y * rYW.c - w * rYW.s;
  tw = y * rYW.s + w * rYW.c;
  y = ty;
  w = tw;

  tz = z * rZW.c - w * rZW.s;
  tw = z * rZW.s + w * rZW.c;
  z = tz;
  w = tw;

  return <double>[x, y, z, w];
}

class _RotationPair {
  const _RotationPair({required this.c, required this.s});

  final double c;
  final double s;
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
