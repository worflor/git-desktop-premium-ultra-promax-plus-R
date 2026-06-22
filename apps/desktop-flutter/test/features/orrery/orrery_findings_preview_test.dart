// Focused render of the findings rail at a readable scale, so the card design
// can be judged up close (the full-page previews shrink the rail too far).

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

void main() {
  testWidgets('finding cards, up close, across themes', (tester) async {
    tester.view.physicalSize = const Size(760, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final model = syntheticOrrery();

    for (final theme in [
      AppThemeId.kirby,
      AppThemeId.aether,
      AppThemeId.petrichor,
    ]) {
      final key = GlobalKey();
      await tester.pumpWidget(orreryTestApp(
        theme: theme,
        home: Scaffold(
          backgroundColor: AppTokens.fromId(theme).bg0,
          body: RepaintBoundary(
            key: key,
            child: OrreryView(
              model: model,
              repoLabel: 'manifold',
              initialLod: OrreryLod.files,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final boundary =
          tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('.preview/orrery_findings_${theme.name}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        // ignore: avoid_print
        print('wrote ${file.absolute.path}');
      });
    }
  });
}
