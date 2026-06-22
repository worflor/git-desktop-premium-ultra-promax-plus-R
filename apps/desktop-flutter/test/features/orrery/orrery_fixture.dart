// Synthetic OrreryModel for visual iteration — a plausible 26-step history:
// an undifferentiated core that matures into three radial arms (modularisation)
// with a mid-history reorg where a slice of files migrate between arms.

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:git_desktop/features/orrery/orrery_model.dart';

double _easeInOut(double x) => x * x * (3 - 2 * x);

OrreryModel syntheticOrrery({int steps = 26, int nodeCount = 220, int seed = 7}) {
  final rng = math.Random(seed);
  const clusterAngles = <double>[0.7, 2.85, 4.95];
  final cluster = List<int>.generate(nodeCount, (i) => i % 3);
  final birth = List<int>.generate(
      nodeCount, (i) => i < nodeCount * 0.62 ? 0 : rng.nextInt(steps ~/ 2));
  // depth 0 = structural hub (near the core), 1 = leaf (drifts to the rim).
  final depth = List<double>.generate(nodeCount, (_) => rng.nextDouble());
  // leaves fan out more than hubs, so the core stays tight and the rim feathers.
  final spread = List<double>.generate(
      nodeCount, (i) => (rng.nextDouble() - 0.5) * (0.4 + 0.95 * depth[i]));
  final phase = List<double>.generate(nodeCount, (_) => rng.nextDouble() * math.pi * 2);
  final wobble = List<double>.generate(nodeCount, (_) => 0.025 + rng.nextDouble() * 0.06);
  const reorgAt = 13;
  final switched = List<bool>.generate(nodeCount, (_) => rng.nextDouble() < 0.16);
  final newCluster =
      List<int>.generate(nodeCount, (i) => (cluster[i] + 1 + rng.nextInt(2)) % 3);

  final positions = List.generate(nodeCount, (_) => <Offset?>[]);
  for (int s = 0; s < steps; s++) {
    final p = s / (steps - 1);
    for (int i = 0; i < nodeCount; i++) {
      if (s < birth[i]) {
        positions[i].add(null);
        continue;
      }
      final double mig =
          switched[i] ? ((s - reorgAt + 1) / 3).clamp(0.0, 1.0) : 0.0;
      final double ang0 = clusterAngles[cluster[i]] + spread[i];
      final double ang1 = clusterAngles[newCluster[i]] + spread[i];
      double ang = ang0 + (ang1 - ang0) * _easeInOut(mig);
      final double radTarget = 0.06 + 0.82 * depth[i];
      double rad = 0.12 + (radTarget - 0.12) * _easeInOut(p);
      ang += wobble[i] * math.sin(phase[i] + s * 0.5);
      rad += wobble[i] * 0.5 * math.cos(phase[i] + s * 0.4);
      positions[i].add(Offset(rad * math.cos(ang), rad * math.sin(ang)));
    }
  }

  String fakeSha() =>
      List.generate(7, (_) => '0123456789abcdef'[rng.nextInt(16)]).join();
  final stepList = <OrreryStep>[];
  for (int s = 0; s < steps; s++) {
    final p = s / (steps - 1);
    stepList.add(OrreryStep(
      revision: s,
      sha: fakeSha(),
      date: DateTime(2025, 1, 1).add(Duration(days: s * 9)),
      gap: 0.4 - 0.26 * _easeInOut(p) + 0.015 * math.sin(s.toDouble()),
      rigidity: 0.28 + 0.42 * p,
      vonNeumann: 1.1 + 1.7 * p,
      archetype: p < 0.42 ? 'tree' : (p < 0.82 ? 'modular' : 'goe'),
      canonicality: 0.5 + 0.32 * math.sin(p * math.pi),
      regimeChange: s == reorgAt,
      archetypeShift: s == (steps * 0.42).round() || s == (steps * 0.82).round(),
    ));
  }
  // Plausible directory paths so the fixture exercises module aggregation and
  // hover labels: each co-change cluster maps to a top-level area, with sub-dirs
  // for depth, plus a few root/docs files.
  const area = <String>['lib/core', 'lib/features', 'lib/ui'];
  const sub = <String>['model', 'view', 'service', 'util'];
  String pathFor(int i) {
    if (i % 37 == 0) return 'README$i.md'; // a few root files
    if (i % 19 == 0) return 'docs/note$i.md'; // a small sparse area
    return '${area[cluster[i]]}/${sub[i % sub.length]}/file$i.dart';
  }

  return OrreryModel(
    steps: stepList,
    nodes: <OrreryNode>[
      for (int i = 0; i < nodeCount; i++)
        OrreryNode(
          id: i,
          path: pathFor(i),
          positions: positions[i],
          churn: 1.0 - depth[i], // central files (low depth) churn more
        ),
    ],
  );
}
