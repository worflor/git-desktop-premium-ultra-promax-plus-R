// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Contract tests for module aggregation (the LOD / "don't blob at scale"
// layer). These lock the partition invariants: every file lands in exactly one
// module, dense subtrees drill deeper than sparse ones, and a module's position
// is the churn-weighted centroid of its present members.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/orrery/orrery_model.dart';

/// Build a file-level model from (path, churn, position) triples. Every file
/// sits at a fixed position across [steps] steps unless [positions] overrides.
OrreryModel _model(
  List<(String path, double churn, Offset at)> files, {
  int steps = 3,
}) {
  final stepList = <OrreryStep>[
    for (int s = 0; s < steps; s++)
      OrreryStep(
        revision: s,
        sha: null,
        date: null,
        gap: 0,
        rigidity: 0,
        vonNeumann: 0,
        archetype: 'tree',
        canonicality: 0,
      ),
  ];
  final nodes = <OrreryNode>[
    for (int i = 0; i < files.length; i++)
      OrreryNode(
        id: i,
        path: files[i].$1,
        churn: files[i].$2,
        positions: List<Offset?>.filled(steps, files[i].$3),
      ),
  ];
  return OrreryModel(steps: stepList, nodes: nodes);
}

void main() {
  group('aggregateByModule', () {
    test('is a partition — every file lands in exactly one module', () {
      final files = <(String, double, Offset)>[
        for (int i = 0; i < 60; i++)
          ('app/lib/backend/spectral/f$i.dart', 0.5, const Offset(0.1, 0.0)),
        for (int i = 0; i < 40; i++)
          ('app/lib/backend/ai/f$i.dart', 0.3, const Offset(0.0, 0.1)),
        for (int i = 0; i < 30; i++)
          ('app/lib/ui/f$i.dart', 0.2, const Offset(-0.1, 0.0)),
        for (int i = 0; i < 8; i++)
          ('docs/d$i.md', 0.05, const Offset(0.0, -0.4)),
        for (int i = 0; i < 3; i++) ('r$i.txt', 0.01, const Offset(0.3, 0.3)),
      ];
      final m = OrreryModel.aggregateByModule(_model(files));

      var members = 0;
      for (final n in m.nodes) {
        members += n.memberCount;
      }
      expect(members, files.length, reason: 'all files assigned exactly once');
      expect(m.nodes.length, lessThan(files.length), reason: 'aggregates');
      expect(m.nodes.length, inInclusiveRange(3, 24));

      final labels = m.nodes.map((n) => n.path).toList();
      expect(labels.toSet().length, labels.length, reason: 'labels unique');
      expect(labels.every((l) => l != null && l.isNotEmpty), isTrue);
    });

    test('drills dense subtrees deeper, leaves sparse ones shallow', () {
      final files = <(String, double, Offset)>[
        for (int i = 0; i < 60; i++)
          ('app/lib/backend/spectral/f$i.dart', 0.5, const Offset(0.1, 0.0)),
        for (int i = 0; i < 40; i++)
          ('app/lib/backend/ai/f$i.dart', 0.3, const Offset(0.0, 0.1)),
        for (int i = 0; i < 30; i++)
          ('app/lib/ui/f$i.dart', 0.2, const Offset(-0.1, 0.0)),
        for (int i = 0; i < 8; i++)
          ('docs/d$i.md', 0.05, const Offset(0.0, -0.4)),
      ];
      final labels = OrreryModel.aggregateByModule(_model(files))
          .nodes
          .map((n) => n.path!);

      // The dense backend subtree resolved into its parts...
      expect(labels.any((l) => l.startsWith('app/lib/backend/')), isTrue);
      // ...while the sparse docs subtree stayed whole.
      expect(labels.contains('docs'), isTrue);
      // No module swallows the repo: the biggest split-able group came apart.
      final biggest = OrreryModel.aggregateByModule(_model(files))
          .nodes
          .map((n) => n.memberCount)
          .reduce((a, b) => a > b ? a : b);
      expect(biggest, lessThan(100));
    });

    test('module position is the churn-weighted centroid of members', () {
      // Two files in one directory; the busy one should dominate the centroid.
      final m = OrreryModel.aggregateByModule(_model([
        ('m/a.dart', 1.0, const Offset(0.4, 0.0)),
        ('m/b.dart', 0.0, const Offset(-0.2, 0.0)),
      ]));
      expect(m.nodes.length, 1);
      // w_a = 1.0 + floor(0.05), w_b = 0.0 + 0.05 → cx = (1.05·0.4 − 0.05·0.2)/1.1
      final p = m.nodes.single.positions.first!;
      expect(p.dx, closeTo((1.05 * 0.4 + 0.05 * -0.2) / 1.1, 1e-9));
      expect(p.dy, closeTo(0.0, 1e-9));
    });

    test('a module is absent at steps where none of its members exist', () {
      final stepList = <OrreryStep>[
        for (int s = 0; s < 3; s++)
          OrreryStep(
            revision: s,
            sha: null,
            date: null,
            gap: 0,
            rigidity: 0,
            vonNeumann: 0,
            archetype: 'tree',
            canonicality: 0,
          ),
      ];
      // a: present at 0,1 then gone; b: born at 1.
      final files = OrreryModel(
        steps: stepList,
        nodes: const [
          OrreryNode(
            id: 0,
            path: 'm/a.dart',
            churn: 0.5,
            positions: [Offset(0.3, 0.0), Offset(0.3, 0.0), null],
          ),
          OrreryNode(
            id: 1,
            path: 'm/b.dart',
            churn: 0.5,
            positions: [null, Offset(-0.3, 0.0), Offset(-0.3, 0.0)],
          ),
        ],
      );
      final mod = OrreryModel.aggregateByModule(files).nodes.single;
      expect(mod.positions[0]!.dx, closeTo(0.3, 1e-9)); // only a
      expect(mod.positions[1]!.dx, closeTo(0.0, 1e-9)); // a & b, equal churn
      expect(mod.positions[2]!.dx, closeTo(-0.3, 1e-9)); // only b
    });

    test('expand shows one module as files while the rest stay collapsed', () {
      final files = _model([
        ('a/f0.dart', 0.5, const Offset(0.1, 0)),
        ('a/f1.dart', 0.5, const Offset(0.2, 0)),
        ('a/f2.dart', 0.5, const Offset(0.3, 0)),
        ('b/g0.dart', 0.5, const Offset(-0.1, 0)),
        ('b/g1.dart', 0.5, const Offset(-0.2, 0)),
      ]);
      final collapsed = OrreryModel.aggregateByModule(files);
      expect(collapsed.nodes.every((n) => n.isModule), isTrue);

      final aLabel = collapsed.nodes.firstWhere((n) => n.memberCount == 3).path;
      final expanded = OrreryModel.aggregateByModule(files, expand: aLabel);

      final fileNodes = expanded.nodes.where((n) => !n.isModule).toList();
      final moduleNodes = expanded.nodes.where((n) => n.isModule).toList();
      expect(fileNodes.length, 3, reason: "a's files, individually");
      expect(moduleNodes.length, 1, reason: 'b stays a super-node');
      expect(moduleNodes.single.memberCount, 2);

      // The painter/hit-test invariant: id == index in nodes.
      for (int i = 0; i < expanded.nodes.length; i++) {
        expect(expanded.nodes[i].id, i);
      }
    });

    test('is deterministic — same input, identical partition', () {
      final files = <(String, double, Offset)>[
        for (int i = 0; i < 50; i++)
          ('a/b/c/f$i.dart', 0.4, const Offset(0.1, 0.1)),
        for (int i = 0; i < 50; i++)
          ('a/b/d/f$i.dart', 0.4, const Offset(0.2, 0.2)),
        for (int i = 0; i < 20; i++)
          ('x/f$i.dart', 0.1, const Offset(0.0, 0.3)),
      ];
      final a = OrreryModel.aggregateByModule(_model(files));
      final b = OrreryModel.aggregateByModule(_model(files));
      expect(a.nodes.map((n) => '${n.path}:${n.memberCount}').toList(),
          b.nodes.map((n) => '${n.path}:${n.memberCount}').toList());
    });
  });
}
