// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Not a pass/fail test — render harnesses that pump real widgets (real fonts)
// and write zoomed PNGs to .preview/ for eyeballing. Run with:
//   flutter test test/ui/split_pill_preview_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/features/changes/verdict_badge.dart';
import 'package:git_desktop/ui/split_pill_button.dart';
import 'package:git_desktop/ui/tokens.dart';
import 'package:provider/provider.dart';

Widget _app(AppTokens tokens, Widget home) => ChangeNotifierProvider(
      create: (_) => PreferencesState(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'DMSans',
          extensions: <ThemeExtension<dynamic>>[AppThemeExtension(tokens)],
        ),
        home: home,
      ),
    );

Future<void> _loadFont() async {
  final bytes = File('assets/fonts/DMSans-Variable.ttf').readAsBytesSync();
  final loader = FontLoader('DMSans')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

Future<void> _capture(WidgetTester tester, Key key, String path) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final image = await boundary.toImage(pixelRatio: 5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote ${file.absolute.path}');
  });
}

void main() {
  setUpAll(_loadFont);

  // Every guardrail shape at a spread of fill levels, so each shape's geometry
  // AND its score fill can actually be inspected — not just one lucky value.
  for (final theme in [AppThemeId.halo, AppThemeId.nightwalker]) {
    testWidgets('verdict badge grid — ${theme.name}', (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final tokens = AppTokens.fromId(theme);
      const key = ValueKey('vb');

      const stages = <(int, String)>[
        (0, 'Ready'),
        (1, 'Mostly ready'),
        (2, 'Needs attention'),
        (3, 'Block'),
      ];
      const scores = <int>[15, 45, 78, 100];

      await tester.pumpWidget(_app(
        tokens,
        Scaffold(
          backgroundColor: tokens.surface0,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: tokens.surface0,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in stages)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final sc in scores)
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: ReviewVerdictBadgePreview(
                                  tokens: tokens,
                                  verdict: s.$2,
                                  score: sc,
                                  guardrailStage: s.$1,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await _capture(tester, key, '.preview/verdict_badge_${theme.name}.png');
    });
  }

  // Big single-shape renders so each shape's geometry is unambiguous.
  for (final (stage, name, score) in const [
    (1, 'square', 100),
    (2, 'shield72', 72),
    (2, 'shield95', 95),
    (3, 'octagon', 100),
    (3, 'octagon87', 87),
  ]) {
    testWidgets('verdict badge zoom — $name', (tester) async {
      tester.view.physicalSize = const Size(600, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final tokens = AppTokens.fromId(AppThemeId.halo);
      final key = ValueKey('z$name');
      await tester.pumpWidget(_app(
        tokens,
        Scaffold(
          backgroundColor: tokens.surface0,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: tokens.surface0,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: ReviewVerdictBadgePreview(
                    tokens: tokens,
                    verdict: 'Mostly ready',
                    score: score,
                    guardrailStage: stage,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
        final image = await boundary.toImage(pixelRatio: 7);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose(); // ui.Image holds native memory — release (leak_tracker)
        final file = File('.preview/vb_zoom_$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        // ignore: avoid_print
        print('wrote ${file.absolute.path}');
      });
    });
  }

  testWidgets('split pill hover preview', (tester) async {
    tester.view.physicalSize = const Size(1200, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final tokens = AppTokens.fromId(AppThemeId.nightwalker);
    const key = ValueKey('sp');

    await tester.pumpWidget(_app(
      tokens,
      Scaffold(
        backgroundColor: tokens.surface0,
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: tokens.surface0,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SplitPillButton(
                  segments: [
                    SplitPillSegment(
                      label: 'Clear cache',
                      restColor: tokens.textMuted,
                      hoverColor: tokens.stateModified,
                      onTap: () {},
                    ),
                    SplitPillSegment(
                      label: 'Refresh providers',
                      restColor: tokens.textNormal,
                      hoverColor: tokens.accentBright,
                      bold: true,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Refresh providers')));
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, key, '.preview/split_pill_hover.png');
  });
}
