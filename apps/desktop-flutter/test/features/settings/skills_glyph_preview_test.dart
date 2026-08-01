// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Not a pass/fail test — renders the agent-skills toggle across its morph
// (sprig -> X) at true size and zoomed, so the mark can be judged. Writes to
// .preview/skills/. Run with:
//   flutter test test/features/settings/skills_glyph_preview_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/settings/agent_skills/skills_bloom.dart';
import 'package:git_desktop/ui/material_surface.dart';
import 'package:git_desktop/ui/tokens.dart';

import '../../support/widget_harness.dart';

const _steps = [0.0, 0.25, 0.5, 0.75, 1.0];

Future<void> _capture(WidgetTester tester, Key key, String path) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final image = await boundary.toImage(pixelRatio: 8);
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

  for (final theme in [AppThemeId.petrichor, AppThemeId.nightwalker]) {
    testWidgets('skills glyph morph — ${theme.name}', (tester) async {
      final tokens = AppTokens.fromId(theme);
      final key = ValueKey('glyph-${theme.name}');
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
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final s in _steps)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: SkillsToggleButton(reveal: s, onTap: () {}),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        theme: theme,
        size: const Size(420, 160),
      );
      await tester.pumpAndSettle();
      await _capture(tester, key, '.preview/skills/glyph-${theme.name}.png');
    });
  }
}
