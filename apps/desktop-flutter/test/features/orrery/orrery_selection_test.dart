// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// P1 #9 — the selection card answers "why is this file here?" in plain
// language (coupling-central vs peripheral, and which way it drifted), with no
// eigen-anything on the surface. These lock that phrasing to real geometry.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/orrery/orrery_model.dart';
import 'package:git_desktop/features/orrery/orrery_page.dart';
import 'package:git_desktop/ui/tokens.dart';

import 'orrery_test_harness.dart';

OrreryModel _model(List<(String, double, List<Offset?>)> files) {
  final steps = files.first.$3.length;
  return OrreryModel(
    steps: <OrreryStep>[
      for (int s = 0; s < steps; s++)
        OrreryStep(
          revision: s,
          sha: null,
          date: null,
          gap: 0,
          rigidity: 0,
          vonNeumann: 0,
          archetype: 'modular',
          canonicality: 0.5,
        ),
    ],
    nodes: <OrreryNode>[
      for (int i = 0; i < files.length; i++)
        OrreryNode(
          id: i,
          path: files[i].$1,
          churn: files[i].$2,
          positions: files[i].$3,
        ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, OrreryModel model, int pinned) async {
  tester.view.physicalSize = const Size(1100, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(orreryTestApp(
    theme: AppThemeId.aether,
    home: Scaffold(
      body: OrreryView(model: model, initialPinned: pinned),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a core file reads as structurally central', (tester) async {
    final model = _model([
      ('lib/core.dart', 0.9, const [Offset.zero, Offset.zero, Offset.zero]),
      (
        'lib/leaf.dart',
        0.1,
        const [Offset(0.85, 0), Offset(0.85, 0), Offset(0.85, 0)]
      ),
    ]);
    await _pump(tester, model, 0);
    // 'Coupling-central' is unique to the selection card; the filename itself
    // also shows up in the hub finding, so just require it present.
    expect(find.textContaining('Coupling-central'), findsOneWidget);
    expect(find.textContaining('core.dart'), findsWidgets);
  });

  testWidgets('a rim file reads as peripheral', (tester) async {
    final model = _model([
      ('lib/core.dart', 0.9, const [Offset.zero, Offset.zero, Offset.zero]),
      (
        'lib/leaf.dart',
        0.1,
        const [Offset(0.85, 0), Offset(0.85, 0), Offset(0.85, 0)]
      ),
    ]);
    await _pump(tester, model, 1);
    expect(find.textContaining('Peripheral'), findsOneWidget);
  });

  testWidgets('a file that moved core→rim is called out as decoupling',
      (tester) async {
    final model = _model([
      (
        'lib/drifter.dart',
        0.5,
        const [
          Offset(0.05, 0), // born central
          Offset(0.5, 0),
          Offset(0.88, 0), // ends peripheral
        ]
      ),
    ]);
    await _pump(tester, model, 0);
    expect(find.textContaining('decoupling'), findsOneWidget);
  });

  testWidgets('clearing the selection removes the card', (tester) async {
    final model = _model([
      ('lib/core.dart', 0.9, const [Offset.zero, Offset.zero]),
    ]);
    await _pump(tester, model, 0);
    expect(find.text('SELECTED'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('SELECTED'), findsNothing);
  });
}
