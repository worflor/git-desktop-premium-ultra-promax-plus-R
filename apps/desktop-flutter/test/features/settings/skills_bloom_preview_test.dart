// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Not a pass/fail test — a render harness that pumps the agent-skills bloom
// (real widgets, real fonts) and writes PNGs to .preview/skills/ for eyeballing.
// MaterialSurface's live blur/glass only renders on the GPU, so the harness
// disables the backdrop (MaterialSurface.debugDisableBackdropFilter) and shows
// the solid fill + border + shadow the layout otherwise sits on. Run with:
//   flutter test test/features/settings/skills_bloom_preview_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/settings/agent_skills/skill_catalog.dart';
import 'package:git_desktop/features/settings/agent_skills/skills_bloom.dart';
import 'package:git_desktop/ui/material_surface.dart';
import 'package:git_desktop/ui/tokens.dart';

import '../../support/widget_harness.dart';

typedef Shot = ({String label, AppThemeId theme, double reveal});

const List<Shot> _shots = [
  (label: 'petrichor-open', theme: AppThemeId.petrichor, reveal: 1.0),
  (label: 'petrichor-mid', theme: AppThemeId.petrichor, reveal: 0.55),
  (label: 'aether-open', theme: AppThemeId.aether, reveal: 1.0),
  (label: 'nightwalker-open', theme: AppThemeId.nightwalker, reveal: 1.0),
  (label: 'kirby-open', theme: AppThemeId.kirby, reveal: 1.0),
];

Future<void> _capture(WidgetTester tester, Key key, String path) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote ${file.path}');
  });
}

void main() {
  setUpAll(() async {
    await loadTestFonts();
    MaterialSurface.debugDisableBackdropFilter = true;
  });
  tearDownAll(() => MaterialSurface.debugDisableBackdropFilter = false);

  for (final shot in _shots) {
    testWidgets('skills bloom — ${shot.label}', (tester) async {
      final tokens = AppTokens.fromId(shot.theme);
      final key = ValueKey('skills-${shot.label}');
      await pumpHarness(
        tester,
        Scaffold(
          backgroundColor: tokens.bg1,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: tokens.bg1,
                child: Padding(
                  padding: const EdgeInsets.all(44),
                  child: SkillsBloomOverlay(
                    reveal: shot.reveal,
                    skills: kAgentSkills,
                    onCopy: (_) {},
                    onSave: (_) {},
                    onToggle: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
        theme: shot.theme,
        size: const Size(520, 640),
      );
      await tester.pumpAndSettle();
      await _capture(tester, key, '.preview/skills/${shot.label}.png');
    });
  }
}
