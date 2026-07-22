// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// diff_hscroll_integrity_test.dart — X-axis virtualization laws.
//
// Before X virtualization the shell clamped horizontal extent at 12,000px:
// every column past ~1,590 was silently UNREACHABLE — content truncation in
// a diff viewer, on any file with long lines (minified assets, data rows).
// Rows also shaped their entire text regardless of visibility. These laws
// pin the replacement: any column of any line is reachable, the rendered
// slice matches the true content at that column, and columns far outside
// the viewport are genuinely not rendered.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

import 'package:git_desktop/features/diff/diff_shell.dart';
import 'package:git_desktop/ui/tokens.dart';

import '../../support/widget_harness.dart';

/// One monster line built from 32-char blocks: `COLnnnnnn` + dots, so the
/// content AT any column is known and searchable.
String _monsterLine(int chars) {
  final sb = StringBuffer();
  var col = 0;
  while (sb.length < chars) {
    sb.write('COL${col.toString().padLeft(6, '0')}');
    sb.write('.' * 23);
    col += 32;
  }
  return sb.toString().substring(0, chars);
}

String _diffWithMonsterLine(int monsterChars) {
  final b = StringBuffer()
    ..writeln('diff --git a/wide.txt b/wide.txt')
    ..writeln('new file mode 100644')
    ..writeln('--- /dev/null')
    ..writeln('+++ b/wide.txt')
    ..writeln('@@ -0,0 +1,40 @@');
  for (var i = 0; i < 39; i++) {
    b.writeln('+row $i MARKROW$i');
  }
  b.writeln('+${_monsterLine(monsterChars)}');
  return b.toString();
}

void main() {
  LeakTesting.settings = LeakTesting.settings.withIgnoredAll();

  setUpAll(() async {
    installSharedPreferencesMock();
    await loadTestFonts();
  });

  setUp(() async {
    await installHermeticStorageSeams();
  });

  testWidgets('every column of a 20k-char line is reachable and correct', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const monsterChars = 20000;
    await pumpHarness(
      tester,
      Scaffold(
        body: DiffShell(
          filePath: 'wide.txt',
          tokens: AppTokens.fromId(AppThemeId.aether),
          diffContent: _diffWithMonsterLine(monsterChars),
        ),
      ),
    );
    final firstRow = find.textContaining('MARKROW0', findRichText: true);
    for (var i = 0; i < 100 && firstRow.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(firstRow, findsWidgets);

    // The horizontal scroller is the axis under test.
    final hPos = tester
        .widgetList<Scrollable>(find.byType(Scrollable))
        .map(
          (s) => tester
              .state<ScrollableState>(find.byWidget(s, skipOffstage: false))
              .position,
        )
        .firstWhere((p) => p.axis == Axis.horizontal);

    // LAW 1 (clamp removal): the extent covers the whole line, far past the
    // old 12,000px ceiling.
    final totalWidth = hPos.maxScrollExtent + hPos.viewportDimension;
    expect(
      totalWidth,
      greaterThan(20000),
      reason:
          'a 20k-char monospace line must span far beyond the old 12000px '
          'clamp — its tail used to be unreachable',
    );
    final charW = (totalWidth - 72.0) / monsterChars;

    // LAW 2 (content correctness deep in the line): scroll to ~column 10k
    // and the marker written at that column must render.
    hPos.jumpTo((72.0 + 10016 * charW).clamp(0.0, hPos.maxScrollExtent));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.textContaining('COL010016', findRichText: true),
      findsWidgets,
      reason: 'the slice under the viewport must contain the true content '
          'at that column',
    );

    // LAW 3 (virtualization): content thousands of columns behind the
    // viewport is NOT rendered.
    expect(
      find.textContaining('COL000032', findRichText: true),
      findsNothing,
      reason: 'columns far outside the slice window must not be shaped',
    );

    // LAW 4 (the very end is reachable): jump to max extent; the final
    // block's marker renders.
    hPos.jumpTo(hPos.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    const lastBlockCol = ((monsterChars - 32) ~/ 32) * 32;
    expect(
      find.textContaining(
        'COL${lastBlockCol.toString().padLeft(6, '0')}',
        findRichText: true,
      ),
      findsWidgets,
      reason: 'the tail of the line must be scrollable into view',
    );

    // LAW 5 (short lines untouched): the normal rows still render whole at
    // offset 0 after scrolling back.
    hPos.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('MARKROW3', findRichText: true), findsWidgets);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 5)));
}
