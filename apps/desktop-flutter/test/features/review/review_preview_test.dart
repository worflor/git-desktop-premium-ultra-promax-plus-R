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
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/features/review/review_adapter.dart'
    show groupThreadsByFile;
import 'package:git_desktop/features/review/review_chrome.dart'
    show ReviewVerbPill;
import 'package:git_desktop/features/review/review_file_header.dart';
import 'package:git_desktop/features/review/review_header_strip.dart';
import 'package:git_desktop/features/review/review_identity_notice.dart';
import 'package:git_desktop/features/review/review_pane.dart'
    show ReviewComposer, ReviewHandOff, ReviewPublishBar;
import 'package:git_desktop/features/review/review_thread_card.dart';
import 'package:git_desktop/features/review/review_view_model.dart';
import 'package:git_desktop/ui/material_surface.dart'
    show AppTokenSurfaceTones;
import 'package:git_desktop/ui/tokens.dart';
import 'package:provider/provider.dart';

import '../../support/review_fixture.dart';
import '../../support/widget_harness.dart';

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
              // The reviewed mark ships on these headers, so the story
              // renders both states — a lab header without it would be
              // iterating a surface the product does not have.
              ReviewFileHeader(
                filePath: g.filePath,
                reviewed: groups.indexOf(g) == 0,
                onToggleReviewed: (_) {},
              ),
              const SizedBox(height: 6),
              for (final th in g.threads) ...[
                ReviewThreadCard(
                  thread: th,
                  now: kFixtureNow,
                  showPath: false,
                  onDone: th.isRobot ? null : () {},
                  onAck: th.isRobot ? null : () {},
                  onReply: () {},
                  onPleaseFix: th.isRobot ? () {} : null,
                  // Resolved cards ship WITH a reopen handler, so the
                  // preview has to pass one — otherwise the state chip
                  // renders in a mode the product never shows and the
                  // look gets iterated against a surface nobody sees.
                  onReopen:
                      th.state == ReviewThreadState.unresolved ? null : () {},
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
                ReviewThreadCard(thread: th, now: kFixtureNow, onReply: () {}),
                const SizedBox(height: 10),
              ],
            ],
            // Production pieces: the opener composer (as it mounts under
            // the diff) and the atomic publish bar that ends the pane.
            const SizedBox(height: 6),
            ReviewComposer(
              strings: const ReviewStrings(),
              contextLabel: 'lib/engine/lattice.dart:214',
              autofocus: false,
              onSave: (_) async => true,
              onCancel: () {},
            ),
            const SizedBox(height: 16),
            ReviewPublishBar(
              strings: const ReviewStrings(),
              draftCount: 2,
              onPublish: (_) async {},
              onDiscard: () {},
            ),
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
  setUpAll(loadTestFonts);

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
                    now: kFixtureNow,
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

  // The review section when git has no identity to sign writes with.
  // Captured because it is the ONLY state in which the pane refuses to
  // exist, so nothing else in the lab shows it — and an uncaptured
  // surface is a surface nobody has looked at.
  testWidgets('review identity notice', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const key = ValueKey('identity');

    await tester.pumpWidget(_app(
      AppTokens.fromId(AppThemeId.petrichor),
      Builder(builder: (context) {
        final tokens = context.tokens;
        return Scaffold(
          backgroundColor: tokens.bg1,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: tokens.bg1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final id in [
                        AppThemeId.nightwalker,
                        AppThemeId.petrichor,
                        AppThemeId.nacre,
                        AppThemeId.crafty,
                      ])
                        Builder(builder: (context) {
                          final t = AppTokens.fromId(id);
                          return Theme(
                            data: Theme.of(context).copyWith(
                              extensions: <ThemeExtension<dynamic>>[
                                AppThemeExtension(t)
                              ],
                            ),
                            child: ColoredBox(
                              color: t.bg1,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 14),
                                child: ReviewIdentityNotice(
                                  strings: ReviewStrings(),
                                  command:
                                      'git config --global user.name "Your Name"',
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    ));
    await tester.pump();
    await _capture(tester, key, '.preview/review/identity_notice.png',
        pixelRatio: 3);
  });

  // The hand-off row across themes: verb, then bare names. Captured
  // because it is the one review control the pane preview never sees
  // (it lives in the PR page's verb row), and an uncaptured control is
  // a control nobody has looked at.
  testWidgets('review hand-off row', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const key = ValueKey('handoff');

    await tester.pumpWidget(_app(
      AppTokens.fromId(AppThemeId.petrichor),
      Builder(builder: (context) {
        final tokens = context.tokens;
        return Scaffold(
          backgroundColor: tokens.bg1,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: tokens.bg1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final id in [
                        AppThemeId.nightwalker,
                        AppThemeId.petrichor,
                        AppThemeId.nacre,
                        AppThemeId.crafty,
                      ])
                        Builder(builder: (context) {
                          final t = AppTokens.fromId(id);
                          return Theme(
                            data: Theme.of(context).copyWith(
                              extensions: <ThemeExtension<dynamic>>[
                                AppThemeExtension(t)
                              ],
                            ),
                            child: ColoredBox(
                              color: t.bg1,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Wrap(
                                        alignment: WrapAlignment.end,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          ReviewVerbPill(
                                              label: 'caught up',
                                              onTap: () {}),
                                          ReviewVerbPill(
                                              label: 'not blocking on me',
                                              onTap: () {}),
                                          ReviewHandOff(
                                            label: 'hand to',
                                            to: const ['mira', 'jun'],
                                            onHandTo: (_) {},
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    ));
    await tester.pump();
    await _capture(tester, key, '.preview/review/handoff_row.png',
        pixelRatio: 3);
  });

  // Nobody to hand to means no control at all, not a dead one.
  testWidgets('hand-off with nobody to hand to renders nothing',
      (tester) async {
    await tester.pumpWidget(_app(
      AppTokens.fromId(AppThemeId.petrichor),
      Scaffold(
        body: ReviewHandOff(label: 'hand to', to: const <String>[], onHandTo: (_) {}),
      ),
    ));
    expect(find.text('hand to'), findsNothing);
  });

  // The name is the control: tapping one names that person, not an index.
  testWidgets('hand-off taps name the person tapped', (tester) async {
    final handed = <String>[];
    await tester.pumpWidget(_app(
      AppTokens.fromId(AppThemeId.petrichor),
      Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: ReviewHandOff(
            label: 'hand to',
            to: const ['mira', 'jun'],
            onHandTo: handed.add,
          ),
        ),
      ),
    ));
    await tester.tap(find.text('jun'));
    await tester.tap(find.text('mira'));
    expect(handed, ['jun', 'mira']);
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
            ReviewThreadCard(
                thread: card,
                now: kFixtureNow,
                onDone: () {},
                onAck: () {},
                onReply: () {}),
          ],
        ),
      ),
    ),
  );
}
