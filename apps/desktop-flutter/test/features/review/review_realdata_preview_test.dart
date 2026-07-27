// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Not a pass/fail test — the REAL-PIPELINE render. A seeded scenario
// drives the actual ReviewStore on an actual two-clone team (edits,
// rounds, batches, verdicts, robot findings, resolutions, syncs), the
// converged state flows through the real adapter (anchor resolution
// against the author's real file), and the pane renders from THAT —
// no hand-authored fixture anywhere in the chain. What these PNGs
// show is what the feature actually produces. Run with:
//   flutter test test/features/review/review_realdata_preview_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/features/review/review_adapter.dart';
import 'package:git_desktop/features/review/review_file_header.dart';
import 'package:git_desktop/features/review/review_header_strip.dart';
import 'package:git_desktop/features/review/review_thread_card.dart';
import 'package:git_desktop/ui/tokens.dart';
import 'package:provider/provider.dart';

import '../../support/review_scenario.dart';
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


void main() {
  setUpAll(loadTestFonts);

  testWidgets('real-pipeline pane — reviewer and author views',
      (tester) async {
    tester.view.physicalSize = const Size(760, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The corpus run happens under runAsync (real subprocess IO).
    late ReviewScenarioResult result;
    await tester.runAsync(() async {
      result = await runReviewScenario(seed: 424242, opCount: 16);
    });

    for (final (viewer, theme) in [
      ('bob', AppThemeId.nightwalker),
      ('alice', AppThemeId.petrichor),
    ]) {
      final tokens = AppTokens.fromId(theme);
      final views = buildReviewViews(
        result.finalState,
        viewerDisplay: viewer,
        authorDisplay: 'alice',
        currentFiles: result.files,
      );
      final key = ValueKey('real-$viewer');

      await tester.pumpWidget(_app(
        tokens,
        Scaffold(
          backgroundColor: tokens.bg1,
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: tokens.bg1,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: 640,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ReviewHeaderStrip(header: views.header),
                          const SizedBox(height: 12),
                          for (final g in views.groups) ...[
                            ReviewFileHeader(filePath: g.filePath),
                            const SizedBox(height: 6),
                            for (final t in g.threads) ...[
                              ReviewThreadCard(
                                thread: t,
                                showPath: false,
                                onDone: t.isRobot ? null : () {},
                                onAck: t.isRobot ? null : () {},
                                onReply: () {},
                                onPleaseFix: t.isRobot ? () {} : null,
                              ),
                              const SizedBox(height: 10),
                            ],
                            const SizedBox(height: 6),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      // MaterialApp ANIMATES theme changes; capturing after one pump
      // mid-lerp blends the previous theme into this one (caught in
      // preview — half-dark petrichor cards). Settle first.
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
        final image = await boundary.toImage(pixelRatio: 2.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final file = File('.preview/review/pane_realdata_$viewer.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        // ignore: avoid_print
        print('wrote ${file.absolute.path} '
            '(${views.threads.length} threads from seed ${result.seed})');
      });
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
