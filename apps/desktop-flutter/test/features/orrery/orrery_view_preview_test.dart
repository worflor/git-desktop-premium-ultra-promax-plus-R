// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Render harness for the whole Orrery page (header + disk + rail + scrubber)
// on synthetic data, across every theme. Writes PNGs to .preview/. Run with:
//   flutter test test/features/orrery/orrery_view_preview_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/orrery/orrery_model.dart';
import 'package:git_desktop/features/orrery/orrery_page.dart';
import 'package:git_desktop/ui/tokens.dart';

import 'orrery_fixture.dart';
import 'orrery_test_harness.dart';

Future<void> _capture(WidgetTester tester, GlobalKey key, String path) async {
  final boundary =
      tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose(); // ui.Image holds native memory — release it (leak_tracker)
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote ${file.absolute.path}');
  });
}

void main() {
  testWidgets('orrery page preview (all themes)', (tester) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final model = syntheticOrrery();

    Future<void> shoot(
      AppThemeId themeId,
      String label,
      double? head, {
      OrreryLod lod = OrreryLod.files,
      OrreryMode mode = OrreryMode.scrub,
    }) async {
      final tokens = AppTokens.fromId(themeId);
      final key = GlobalKey();
      await tester.pumpWidget(orreryTestApp(
        theme: themeId,
        home: Scaffold(
          backgroundColor: tokens.bg0,
          body: RepaintBoundary(
            key: key,
            child: OrreryView(
              model: model,
              repoLabel: 'manifold',
              initialHead: head,
              initialLod: lod,
              initialMode: mode,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle(); // let the theme lerp finish
      await _capture(
          tester, key, '.preview/orrery_page_${themeId.name}_$label.png');
    }

    for (final themeId in AppThemeId.values) {
      await shoot(themeId, 'head', null);
    }
    await shoot(AppThemeId.aether, 'reorg', 13);
    await shoot(AppThemeId.petrichor, 'reorg', 13);
    // Aggregated module view (the large-repo default).
    await shoot(AppThemeId.aether, 'modules', null, lod: OrreryLod.modules);
    await shoot(AppThemeId.petrichor, 'modules', null, lod: OrreryLod.modules);
    // Compare mode — static small-multiples at the regime boundaries.
    await shoot(AppThemeId.aether, 'compare', null, mode: OrreryMode.compare);
    await shoot(AppThemeId.petrichor, 'compare', null,
        mode: OrreryMode.compare);
  });
}
