// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Play-test for the agent-skills toggle: drives the real interaction sequence
// a person performs — open, spam the toggle, press Escape, scroll underneath —
// and asserts the affordance behaves. These are the UX failures that never show
// up in a static render.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/settings/agent_skills/skills_bloom.dart';
import 'package:git_desktop/features/settings/agent_skills/skills_fab.dart';
import 'package:git_desktop/ui/material_surface.dart';

import '../../support/widget_harness.dart';

/// A settings-like scroller with the toggle pinned in a header row, so the
/// anchor MOVES when the page scrolls.
Widget _page() => Scaffold(
      body: ListView(
        children: [
          const SizedBox(height: 240),
          Row(
            children: const [
              Expanded(child: Text('Model Slots')),
              SkillsFab(),
            ],
          ),
          const SizedBox(height: 1400),
        ],
      ),
    );

void main() {
  setUpAll(() async {
    await loadTestFonts();
    MaterialSurface.debugDisableBackdropFilter = true;
  });
  tearDownAll(() => MaterialSurface.debugDisableBackdropFilter = false);

  testWidgets('opens, and Escape closes it', (tester) async {
    await pumpHarness(tester, _page(), size: const Size(900, 700));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SkillsFab));
    await tester.pumpAndSettle();
    expect(find.text('Code review'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Code review'), findsNothing,
        reason: 'Escape must dismiss an overlay; users expect it.');
  });

  testWidgets('survives spam-clicking the toggle', (tester) async {
    await pumpHarness(tester, _page(), size: const Size(900, 700));
    await tester.pumpAndSettle();

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byType(SkillsFab), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    // Whatever state it lands in, it must be consistent and not throw.
    expect(tester.takeException(), isNull);
  });

  testWidgets('reaching past the panel dismisses it instead of freezing',
      (tester) async {
    await pumpHarness(tester, _page(), size: const Size(900, 700));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SkillsFab));
    await tester.pumpAndSettle();
    expect(find.text('Code review'), findsOneWidget);

    // Someone trying to scroll the page behind the panel. The scrim must not
    // silently eat it — that reads as a frozen window.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Code review'), findsNothing,
        reason: 'Reaching past the panel should dismiss it, leaving the page '
            'usable on the next gesture.');
  });

  testWidgets('panel text has a Material ancestor', (tester) async {
    // An OverlayEntry is inserted above the page's Scaffold, so it inherits no
    // Material. Text without one renders with Flutter's yellow debug
    // underlines — which shipped, because every preview harness pumped the
    // panel INSIDE a Scaffold and never saw it.
    await pumpHarness(tester, _page(), size: const Size(900, 700));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SkillsFab));
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.text('Code review'),
        matching: find.byType(Material),
      ),
      findsWidgets,
      reason: 'Overlay text with no Material ancestor gets yellow underlines.',
    );
  });

  testWidgets('the panel is anchored to the toggle, not the screen',
      (tester) async {
    await pumpHarness(tester, _page(), size: const Size(900, 700));
    await tester.pumpAndSettle();

    final anchor = tester.getTopRight(find.byType(SkillsFab));
    await tester.tap(find.byType(SkillsFab));
    await tester.pumpAndSettle();

    // The slab hangs off the toggle: right edges effectively flush, and it
    // grows downward from the anchor rather than floating loose on screen.
    final panel = tester.getRect(find.byType(SkillsBloomPanel));
    expect((panel.right - anchor.dx).abs() < 14, isTrue,
        reason: 'Panel right edge should line up with the toggle it grew from '
            '(was ${panel.right} vs anchor ${anchor.dx}).');
    expect(panel.top >= anchor.dy - 1, isTrue,
        reason: 'It blooms downward from an inline header anchor.');
  });
}
