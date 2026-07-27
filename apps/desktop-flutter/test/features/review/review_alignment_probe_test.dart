// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Not a pass/fail test — the alignment MICROSCOPE. Renders individual
// review meta rows at 8x with hairline guides so vertical alignment
// claims are settled by pixels, not argument. Run with:
//   flutter test test/features/review/review_alignment_probe_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/features/review/review_chrome.dart';
import 'package:git_desktop/features/review/review_header_strip.dart';
import 'package:git_desktop/features/review/review_view_model.dart';
import 'package:git_desktop/ui/tokens.dart';
import 'package:provider/provider.dart';

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


/// Horizontal hairlines every 2px so element tops/bottoms/baselines can
/// be read off directly at 8x.
class _Ruler extends StatelessWidget {
  final Widget child;
  const _Ruler({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _RulerPainter()),
          ),
        ),
      ],
    );
  }
}

class _RulerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final faint = Paint()
      ..color = const Color(0x22FF00FF)
      ..strokeWidth = 0.125;
    final strong = Paint()
      ..color = const Color(0x55FF00FF)
      ..strokeWidth = 0.125;
    for (var y = 0.0; y <= size.height; y += 2) {
      canvas.drawLine(
          Offset(0, y), Offset(size.width, y), y % 10 == 0 ? strong : faint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  setUpAll(loadTestFonts);

  Future<void> capture(WidgetTester tester, Key key, String path) async {
    await tester.runAsync(() async {
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final image = await boundary.toImage(pixelRatio: 8);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.absolute.path}');
    });
  }

  testWidgets('alignment probe — meta rows at 8x with rulers',
      (tester) async {
    tester.view.physicalSize = const Size(700, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final tokens = AppTokens.fromId(AppThemeId.petrichor);
    const key = ValueKey('probe');

    await tester.pumpWidget(_app(
      tokens,
      Scaffold(
        backgroundColor: tokens.bg1,
        body: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: tokens.bg1,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  width: 600,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. The full header strip.
                      const _Ruler(
                        child: ReviewHeaderStrip(
                          header: ReviewHeaderView(
                            round: 4,
                            turn: ReviewTurn.yours,
                            unresolvedCount: 2,
                            standing: ReviewStanding.changesRequested,
                  standingBy: [ReviewStandingBy('bob')],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 2. An anchor-style line: mono path + chip + far
                      // side quiet chip, exactly as the card composes it.
                      _Ruler(
                        child: ColoredBox(
                          color: tokens.bg0.withValues(alpha: 0.3),
                          child: Row(
                            children: [
                              Expanded(
                                child: ReviewLine([
                                  TextSeg('src/main.dart',
                                      color: tokens.textMuted, mono: true),
                                  TextSeg(':13',
                                      color: tokens.textMuted, mono: true),
                                  const GapSeg(6),
                                  ChipSeg(ReviewChip(
                                      label: 'moved',
                                      color: tokens.textMuted)),
                                ]),
                              ),
                              const SizedBox(width: 8),
                              ReviewLine([
                                ChipSeg(ReviewChip(
                                  label: 'unresolved',
                                  color: tokens.accentBright,
                                  variant: ReviewChipVariant.quiet,
                                  dot: true,
                                )),
                              ]),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 3. Author row shape: bold mono author + meta time.
                      _Ruler(
                        child: ColoredBox(
                          color: tokens.bg0.withValues(alpha: 0.3),
                          child: ReviewLine([
                            TextSeg('@bob',
                                color: tokens.accentBright,
                                weight: FontWeight.w700,
                                mono: true),
                            const GapSeg(8),
                            TextSeg('3h',
                                color: tokens.textFaint,
                                size: ReviewType.meta),
                            const GapSeg(8),
                            ChipSeg(ReviewChip(
                                label: 'engine',
                                color: tokens.stateFragile,
                                variant: ReviewChipVariant.fill)),
                            const GapSeg(8),
                            ChipSeg(ReviewChip(
                                label: 'draft',
                                color: tokens.accentBright)),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await capture(tester, key, '.preview/review/probe_rows.png');
  });
}
