// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Per-module drill-in (focus+context): a module super-node expands to its files
// in place while the rest stay collapsed, with a breadcrumb back to the map.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/orrery/orrery_model.dart';
import 'package:git_desktop/features/orrery/orrery_page.dart';
import 'package:git_desktop/ui/tokens.dart';

import 'orrery_fixture.dart';
import 'orrery_test_harness.dart';

void main() {
  testWidgets('a drilled-in module shows a breadcrumb that collapses on tap',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final model = syntheticOrrery();
    // A real module label from the same partition the view will use.
    final label = OrreryModel.aggregateByModule(model)
        .nodes
        .firstWhere((n) => n.isModule)
        .path!;

    await tester.pumpWidget(orreryTestApp(
      theme: AppThemeId.aether,
      home: Scaffold(
        body: OrreryView(model: model, initialExpand: label),
      ),
    ));
    await tester.pumpAndSettle();

    // Breadcrumb present while drilled in.
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);

    // Tapping it collapses back to the full map.
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
  });
}
