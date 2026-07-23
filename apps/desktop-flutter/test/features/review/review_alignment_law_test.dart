// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_alignment_law_test.dart — alignment as an ASSERTED LAW.
//
// Eyeballing 8x screenshots caught the drift; this pins it forever:
// within every composed meta row, the rendered alphabetic baseline of
// every text element — the host paragraph AND each chip's label, on
// BOTH sides of two-sided rows — must coincide within a third of a
// pixel. Any construction that reintroduces baseline wobble fails
// with per-element numbers instead of a vibe.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/features/review/review_chrome.dart';
import 'package:git_desktop/features/review/review_header_strip.dart';
import 'package:git_desktop/features/review/review_view_model.dart';
import 'package:git_desktop/ui/tokens.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';
import 'package:provider/provider.dart';

const double kBaselineTolerance = 0.34;

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

/// Global y of the first alphabetic baseline of the paragraph whose
/// plain text CONTAINS [needle], scoped under [rowKey].
double _baselineY(WidgetTester tester, Key rowKey, String needle) {
  final finder = find.descendant(
    of: find.byKey(rowKey),
    matching: find.byWidgetPredicate((w) =>
        w is RichText && w.text.toPlainText().contains(needle)),
  );
  expect(finder, findsAtLeastNWidgets(1),
      reason: 'no paragraph containing "$needle" under $rowKey');
  final p = tester.renderObjectList<RenderParagraph>(finder).first;
  final dist = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  expect(dist, isNotNull);
  return p.localToGlobal(Offset(0, dist)).dy;
}

void _expectAligned(
    WidgetTester tester, Key rowKey, List<String> needles, String row) {
  final ys = {for (final n in needles) n: _baselineY(tester, rowKey, n)};
  final values = ys.values.toList();
  final spread = values.reduce((a, b) => a > b ? a : b) -
      values.reduce((a, b) => a < b ? a : b);
  expect(spread, lessThanOrEqualTo(kBaselineTolerance),
      reason: '$row baselines drift ${spread.toStringAsFixed(2)}px: '
          '${ys.map((k, v) => MapEntry(k, v.toStringAsFixed(2)))}');
}

void main() {
  LeakTesting.settings = LeakTesting.settings.withIgnoredAll();

  // Font metrics differ per theme family (sans, serif, pixel); the law
  // must hold on all of them, not just the one we eyeballed.
  for (final theme in [
    AppThemeId.petrichor,
    AppThemeId.nightwalker,
    AppThemeId.halo,
    AppThemeId.crafty,
  ]) {
  testWidgets('every meta-row element shares one baseline — ${theme.name}',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final tokens = AppTokens.fromId(theme);

    const headerKey = ValueKey('rowHeader');
    const anchorKey = ValueKey('rowAnchor');
    const authorKey = ValueKey('rowAuthor');

    await tester.pumpWidget(_app(
      tokens,
      Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KeyedSubtree(
              key: headerKey,
              child: ReviewHeaderStrip(
                header: ReviewHeaderView(
                  round: 4,
                  turn: ReviewTurn.yours,
                  unresolvedCount: 2,
                  filesSinceLastLook: 2,
                  verdictNote: 'changes requested · bob',
                ),
              ),
            ),
            KeyedSubtree(
              key: anchorKey,
              child: Row(
                children: [
                  Expanded(
                    child: ReviewLine([
                      TextSeg('src/main.dart',
                          color: tokens.textMuted, mono: true),
                      TextSeg(':13', color: tokens.textMuted, mono: true),
                      const GapSeg(6),
                      ChipSeg(ReviewChip(
                          label: 'moved', color: tokens.textMuted)),
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
            KeyedSubtree(
              key: authorKey,
              child: ReviewLine([
                TextSeg('@bob',
                    color: tokens.accentBright,
                    weight: FontWeight.w700,
                    mono: true),
                const GapSeg(8),
                TextSeg('3h',
                    color: tokens.textFaint, size: ReviewType.meta),
                const GapSeg(8),
                ChipSeg(ReviewChip(
                    label: 'engine',
                    color: tokens.stateFragile,
                    variant: ReviewChipVariant.fill)),
                const GapSeg(8),
                ChipSeg(
                    ReviewChip(label: 'draft', color: tokens.accentBright)),
              ]),
            ),
          ],
        ),
      ),
    ));
    await tester.pump();

    _expectAligned(
        tester,
        headerKey,
        ['R4', '2 files since your last look', '2 unresolved', 'your turn'],
        'header');
    _expectAligned(tester, anchorKey,
        ['src/main.dart', 'moved', 'unresolved'], 'anchor row');
    _expectAligned(
        tester, authorKey, ['@bob', 'engine', 'draft'], 'author row');

    // Box geometry: every chip is EXACTLY chipHeight tall, and chips
    // sharing a row share a top edge (settles the "one chip taller
    // than its neighbour" class mechanically).
    final chipRects = <Rect>[];
    for (final e in find.byType(ReviewChip).evaluate()) {
      final box = e.renderObject! as RenderBox;
      chipRects.add(box.localToGlobal(Offset.zero) & box.size);
    }
    expect(chipRects, isNotEmpty);
    for (final r in chipRects) {
      expect(r.height, ReviewMetrics.chipHeight,
          reason: 'chip height ${r.height}');
    }
    for (final rowKey in [headerKey, anchorKey, authorKey]) {
      final tops = <double>[];
      for (final e in find
          .descendant(of: find.byKey(rowKey), matching: find.byType(ReviewChip))
          .evaluate()) {
        final box = e.renderObject! as RenderBox;
        tops.add(box.localToGlobal(Offset.zero).dy);
      }
      if (tops.length < 2) continue;
      final spread =
          tops.reduce((a, b) => a > b ? a : b) - tops.reduce((a, b) => a < b ? a : b);
      expect(spread, lessThanOrEqualTo(kBaselineTolerance),
          reason: 'chip tops drift in $rowKey');
    }
  });
  }
}
