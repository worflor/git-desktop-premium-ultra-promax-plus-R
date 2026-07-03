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
import 'package:git_desktop/features/changes/changes_page.dart';
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
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote ${file.absolute.path}');
  });
}

void main() {
  setUpAll(_loadFont);

  testWidgets('verdict badge stages preview', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final tokens = AppTokens.fromId(AppThemeId.nightwalker);
    const key = ValueKey('vb');

    // stage / verdict / score tuples.
    final rows = <(int, String, int)>[
      (0, 'Ready', 92),
      (1, 'Mostly ready', 70),
      (2, 'Needs attention', 58),
      (2, 'High risk', 34),
      (3, 'Block', 12),
    ];

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
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: ReviewVerdictBadgePreview(
                          tokens: tokens,
                          verdict: r.$2,
                          score: r.$3,
                          guardrailStage: r.$1,
                        ),
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
    await _capture(tester, key, '.preview/verdict_badge_real.png');
  });

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
