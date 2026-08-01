// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Smoke test for the agent-skills toggle: it blooms the skill list into an
// overlay and an outside tap dismisses it. Copy/save go through platform
// channels (clipboard, native save dialog) and are not exercised here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/settings/agent_skills/skills_fab.dart';
import 'package:git_desktop/ui/material_surface.dart';

import '../../support/widget_harness.dart';

void main() {
  setUpAll(() async {
    await loadTestFonts();
    MaterialSurface.debugDisableBackdropFilter = true;
  });
  tearDownAll(() => MaterialSurface.debugDisableBackdropFilter = false);

  testWidgets('toggle blooms the skill list and dismisses on outside tap',
      (tester) async {
    await pumpHarness(
      tester,
      const Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.all(24),
            child: SkillsFab(),
          ),
        ),
      ),
      size: const Size(900, 900),
    );
    await tester.pumpAndSettle();

    // Closed: the skill rows are not in the tree.
    expect(find.text('Code review'), findsNothing);
    expect(find.text('Repo intel'), findsNothing);

    await tester.tap(find.byType(SkillsFab));
    await tester.pumpAndSettle();

    expect(find.text('Code review'), findsOneWidget);
    expect(find.text('Bug shaker'), findsOneWidget);
    expect(find.text('Repo intel'), findsOneWidget);

    // Outside tap (bottom-left, away from the panel) dismisses it.
    await tester.tapAt(const Offset(30, 860));
    await tester.pumpAndSettle();
    expect(find.text('Code review'), findsNothing);
  });
}
