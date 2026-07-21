// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Compare mode's analytical core: topMovers ranks what actually travelled
// between two moments (skipping the unborn and the noise), and the A/B bench
// flow — pick two frames, read the movers, drill a mover into scrub pinned.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/orrery/orrery_model.dart';
import 'package:git_desktop/features/orrery/orrery_page.dart';
import 'package:git_desktop/ui/tokens.dart';

import 'orrery_test_harness.dart';

OrreryModel _model(List<(String, List<Offset?>)> files) {
  final steps = files.first.$2.length;
  return OrreryModel(
    steps: <OrreryStep>[
      for (int s = 0; s < steps; s++)
        OrreryStep(
          revision: s,
          sha: 'sha$s',
          date: DateTime.utc(2026, 1, 1 + s),
          gap: 0.1 * s,
          rigidity: 0.5,
          vonNeumann: 1.0,
          archetype: 'modular',
          canonicality: 0.5,
        ),
    ],
    nodes: <OrreryNode>[
      for (int i = 0; i < files.length; i++)
        OrreryNode(
          id: i,
          path: files[i].$1,
          churn: 0.5,
          positions: files[i].$2,
        ),
    ],
  );
}

void main() {
  group('topMovers', () {
    test('ranks by displacement and signs the radial direction', () {
      final model = _model([
        // Big outward mover: core → rim.
        ('lib/out.dart', const [Offset(0.1, 0), Offset(0.8, 0)]),
        // Smaller inward mover: rim → mid.
        ('lib/in.dart', const [Offset(0, 0.7), Offset(0, 0.4)]),
        // Still — under the noise floor.
        ('lib/still.dart', const [Offset(0.5, 0.5), Offset(0.5, 0.5)]),
      ]);
      final movers = OrreryModel.topMovers(model, 0, 1);
      expect(movers.map((m) => m.path).toList(),
          ['lib/out.dart', 'lib/in.dart']);
      expect(movers[0].radialDelta, greaterThan(0));
      expect(movers[1].radialDelta, lessThan(0));
    });

    test('skips nodes absent at either end and honors the include filter', () {
      final model = _model([
        ('lib/born_late.dart', const [null, Offset(0.9, 0)]),
        ('README.md', const [Offset(0.1, 0), Offset(0.9, 0)]),
        ('lib/code.dart', const [Offset(0, 0.1), Offset(0, 0.9)]),
      ]);
      final movers = OrreryModel.topMovers(model, 0, 1,
          include: (p) => p.endsWith('.dart'));
      expect(movers.map((m) => m.path).toList(), ['lib/code.dart']);
    });

    test('is empty on a degenerate pair', () {
      final model = _model([
        ('lib/a.dart', const [Offset(0.1, 0), Offset(0.8, 0)]),
      ]);
      expect(OrreryModel.topMovers(model, 1, 1), isEmpty);
    });
  });

  group('compare bench', () {
    OrreryModel benchModel() => _model([
          ('lib/mover.dart', const [Offset(0.1, 0), Offset(0.1, 0), Offset(0.8, 0)]),
          ('lib/anchor.dart', const [Offset(0, 0.3), Offset(0, 0.3), Offset(0, 0.3)]),
        ]);

    Future<void> pump(WidgetTester tester, OrreryModel model) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(orreryTestApp(
        theme: AppThemeId.aether,
        home: Scaffold(
          body: OrreryView(model: model, initialMode: OrreryMode.compare),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('picking two frames opens the bench with movers', (t) async {
      await pump(t, benchModel());
      // Milestones for a 3-step quiet history: genesis, middle pad, head.
      await t.tap(find.byKey(const ValueKey('compare-card-0')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('compare-card-2')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('compare-bench')), findsOneWidget);
      expect(find.text('MOVERS'), findsOneWidget);
      expect(find.text('mover.dart'), findsOneWidget);
      expect(find.text('outward'), findsOneWidget);
      // The still file never ranks.
      expect(find.text('anchor.dart'), findsNothing);
    });

    testWidgets('a mover drills into scrub with the file pinned', (t) async {
      await pump(t, benchModel());
      await t.tap(find.byKey(const ValueKey('compare-card-0')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('compare-card-2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('mover-0')));
      await t.pumpAndSettle();
      // Scrub mode with the inspector on the moved file.
      expect(find.text('SELECTED'), findsOneWidget);
      expect(find.textContaining('mover.dart'), findsWidgets);
      expect(find.byKey(const ValueKey('compare-bench')), findsNothing);
    });

    testWidgets('deselecting a frame returns to the grid', (t) async {
      await pump(t, benchModel());
      await t.tap(find.byKey(const ValueKey('compare-card-0')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('compare-card-2')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('compare-bench')), findsOneWidget);
      // The bench close chip collapses back to the milestone grid.
      await t.tap(find.byIcon(Icons.close_rounded).last);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('compare-bench')), findsNothing);
      expect(find.byKey(const ValueKey('compare-card-0')), findsOneWidget);
    });
  });
}
