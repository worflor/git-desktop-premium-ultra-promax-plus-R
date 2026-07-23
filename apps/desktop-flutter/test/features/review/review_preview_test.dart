// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Not a pass/fail test — render harnesses that pump the review lab
// widgets (real fonts, real theme tokens) and write zoomed PNGs to
// .preview/review/ for eyeballing. This is the no-guessing loop for the
// critique surfaces: every look decision lands as a PNG before it lands
// in a page. Run with:
//   flutter test test/features/review/review_preview_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/features/review/review_adapter.dart'
    show groupThreadsByFile;
import 'package:git_desktop/features/review/review_file_header.dart';
import 'package:git_desktop/features/review/review_gutter.dart';
import 'package:git_desktop/features/review/review_header_strip.dart';
import 'package:git_desktop/features/review/review_thread_card.dart';
import 'package:git_desktop/features/review/review_view_model.dart';
import 'package:git_desktop/ui/material_surface.dart'
    show AppTokenSurfaceTones;
import 'package:git_desktop/ui/tokens.dart';
import 'package:provider/provider.dart';

import '../../support/review_fixture.dart';

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

Future<void> _loadFonts() async {
  Future<void> load(String family, String file) async {
    final bytes = File('assets/fonts/$file').readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  // Every family the themes' typography can resolve to, spaced and
  // unspaced variants alike, so serif themes render their real faces.
  await load('DMSans', 'DMSans-Variable.ttf');
  await load('DM Sans', 'DMSans-Variable.ttf');
  await load('JetBrainsMono', 'JetBrainsMono-Variable.ttf');
  await load('JetBrains Mono', 'JetBrainsMono-Variable.ttf');
  await load('Playfair Display', 'PlayfairDisplay-Variable.ttf');
  await load('Lora', 'Lora-Variable.ttf');
  await load('VT323', 'VT323-Regular.ttf');
}

Future<void> _capture(WidgetTester tester, Key key, String path,
    {double pixelRatio = 3}) async {
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote ${file.absolute.path}');
  });
}

/// The full review pane story: both header variants, then published
/// threads grouped per file, then the viewer's drafts as their own
/// quiet section — the same composition the adapter emits.
Widget _paneStory(AppTokens tokens) {
  final all = syntheticReviewThreads();
  final published = all.where((t) => !t.isDraftOnly).toList();
  final drafts = all.where((t) => t.isDraftOnly).toList();
  final groups = groupThreadsByFile(published);
  return ColoredBox(
    color: tokens.bg1,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReviewHeaderStrip(header: syntheticHeaderYourTurn()),
            const SizedBox(height: 8),
            ReviewHeaderStrip(header: syntheticHeaderTheirTurn()),
            const SizedBox(height: 16),
            for (final g in groups) ...[
              ReviewFileHeader(filePath: g.filePath),
              const SizedBox(height: 6),
              for (final th in g.threads) ...[
                ReviewThreadCard(
                  thread: th,
                  showPath: false,
                  onDone: th.isRobot ? null : () {},
                  onAck: th.isRobot ? null : () {},
                  onReply: () {},
                  onPleaseFix: th.isRobot ? () {} : null,
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
            ],
            if (drafts.isNotEmpty) ...[
              const SizedBox(height: 4),
              _sectionLabel(tokens, 'drafts'),
              const SizedBox(height: 6),
              for (final th in drafts) ...[
                ReviewThreadCard(thread: th, onReply: () {}),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    ),
  );
}

/// Quiet section divider for the drafts tray: meta label + hairline.
Widget _sectionLabel(AppTokens tokens, String label) => SizedBox(
      height: 18,
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 9,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 0.5,
              color: tokens.chromeBorderFaint,
            ),
          ),
        ],
      ),
    );

void main() {
  setUpAll(_loadFonts);

  // The whole pane story per representative theme — a dark glass theme,
  // the plain one, and a light one, plus the sharp-pixel outlier.
  for (final theme in [
    AppThemeId.nightwalker,
    AppThemeId.petrichor,
    AppThemeId.nacre,
    AppThemeId.crafty,
  ]) {
    testWidgets('review pane story — ${theme.name}', (tester) async {
      tester.view.physicalSize = const Size(720, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final tokens = AppTokens.fromId(theme);
      const key = ValueKey('pane');

      await tester.pumpWidget(_app(
        tokens,
        Scaffold(
          backgroundColor: tokens.bg1,
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(key: key, child: _paneStory(tokens)),
            ),
          ),
        ),
      ));
      await tester.pump();
      await _capture(tester, key, '.preview/review/pane_${theme.name}.png');
    });
  }

  // One unresolved card across ALL themes, 3-per-row grid — the sweep
  // that catches a theme where the treatment falls apart.
  testWidgets('review card all themes grid', (tester) async {
    tester.view.physicalSize = const Size(1560, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const key = ValueKey('grid');
    final card = syntheticReviewThreads().first;

    const themes = AppThemeId.values;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'DMSans'),
      home: Scaffold(
        backgroundColor: const Color(0xFF101014),
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row * 3 < themes.length; row++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final theme in themes.skip(row * 3).take(3))
                          _themedCell(theme, card),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await _capture(tester, key, '.preview/review/card_all_themes.png',
        pixelRatio: 2);
  });

  // Gutter states, zoomed, with labels.
  testWidgets('review gutter states', (tester) async {
    tester.view.physicalSize = const Size(900, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final tokens = AppTokens.fromId(AppThemeId.nightwalker);
    const key = ValueKey('gutter');

    await tester.pumpWidget(_app(
      tokens,
      Scaffold(
        backgroundColor: tokens.bg1,
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: tokens.bg1,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (state, count, label) in kGutterFixture)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: tokens.chromeBorder
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              child: ReviewGutterCell(
                                  state: state, count: count),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              label,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 8,
                              ),
                            ),
                          ],
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
    await _capture(tester, key, '.preview/review/gutter_states.png',
        pixelRatio: 6);
  });

  // Hover state on the Done verb — the interaction texture check.
  testWidgets('review verb hover', (tester) async {
    tester.view.physicalSize = const Size(760, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final tokens = AppTokens.fromId(AppThemeId.nightwalker);
    const key = ValueKey('hover');
    final thread = syntheticReviewThreads().first;

    await tester.pumpWidget(_app(
      tokens,
      Scaffold(
        backgroundColor: tokens.bg1,
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: tokens.bg1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: 620,
                  child: ReviewThreadCard(
                    thread: thread,
                    onDone: () {},
                    onAck: () {},
                    onReply: () {},
                  ),
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
    await gesture.moveTo(tester.getCenter(find.text('done')));
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, key, '.preview/review/verb_hover.png',
        pixelRatio: 4);
  });
}

Widget _themedCell(AppThemeId theme, ReviewThreadView card) {
  final tokens = AppTokens.fromId(theme);
  return Theme(
    data: ThemeData(
      fontFamily: 'DMSans',
      extensions: <ThemeExtension<dynamic>>[AppThemeExtension(tokens)],
    ),
    child: ChangeNotifierProvider(
      create: (_) => PreferencesState(),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(10),
        color: tokens.bg1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              theme.name,
              style: TextStyle(color: tokens.textMuted, fontSize: 9),
            ),
            const SizedBox(height: 4),
            ReviewThreadCard(thread: card, onDone: () {}, onAck: () {}, onReply: () {}),
          ],
        ),
      ),
    ),
  );
}
