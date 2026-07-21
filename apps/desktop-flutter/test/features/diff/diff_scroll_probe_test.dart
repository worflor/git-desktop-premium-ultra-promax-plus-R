// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// diff_scroll_probe_test.dart — bisection probe for O(document) interaction
// cost on machine-scale diffs. When diff_smoothness_lab_test.dart's vscroll
// gate goes red, run this to localize WHERE in a drag the time goes. It found
// the 2026-07 regression: ~2.2s of pin-on-press simHash rhyme scanning inside
// pointer-event dispatch (dragOnly), invisible to every load-time profiler.
// Splits one drag into its parts:
//   dragOnly  — pointer down/move/up WITHOUT pumping (synchronous scroll
//               listeners + position update).
//   pumpAfter — the single frame after the drag (build/layout of slivers).
//   jumpPump  — ScrollPosition.jumpTo (no pointer events) + pump.
//   settled   — a second pump with nothing dirty.
// Whichever bucket carries the ~2s tells us where to read next.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_shell.dart';
import 'package:git_desktop/ui/tokens.dart';

import '../../support/widget_harness.dart';

String _megaDiff(int lines) {
  final sb = StringBuffer()
    ..write('diff --git a/graph_0.gr b/graph_0.gr\n')
    ..write('new file mode 100644\n')
    ..write('index 0000000..1111111\n')
    ..write('--- /dev/null\n')
    ..write('+++ b/graph_0.gr\n')
    ..write('@@ -0,0 +1,$lines @@\n');
  var rng = 0x5eed;
  int next() {
    rng = (rng * 1664525 + 1013904223) & 0x7fffffff;
    return rng;
  }

  for (var i = 0; i < lines; i++) {
    sb.write(i == 0
        ? '+MARKFIRSTROW a 1 2 3\n'
        : '+a ${next() % 90000000 + 1000000} '
            '${next() % 90000000 + 1000000} ${next() % 900 + 100}\n');
  }
  return sb.toString();
}

void main() {
  LeakTesting.settings = LeakTesting.settings.withIgnoredAll();

  setUpAll(() async {
    installSharedPreferencesMock();
    await loadTestFonts();
  });

  late Directory tmp;
  setUp(() async {
    await installHermeticStorageSeams();
    tmp = await Directory.systemTemp.createTemp('diff_scroll_probe_');
    addTearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });
  });

  testWidgets('bisect the per-drag cost on a 300k-line diff', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final spool = File('${tmp.path}${Platform.pathSeparator}mega.diff');
    final doc = (await tester.runAsync(() async {
      await spool.writeAsString(_megaDiff(300000));
      return DiffDocument.lazyFromSpool(spool.path, documentId: 'probe:mega');
    }))!;

    await pumpHarness(
      tester,
      Scaffold(
        body: DiffShell(
          filePath: 'graph_0.gr',
          tokens: AppTokens.fromId(AppThemeId.aether),
          document: doc,
          enableStaging: true,
        ),
      ),
    );
    final mark = find.textContaining('MARKFIRSTROW', findRichText: true);
    for (var i = 0; i < 200 && mark.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(mark, findsWidgets);

    // Let the mount fully settle before timing anything.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final scrollable = find.byType(Scrollable).first;
    final buckets = <String, List<double>>{};
    void record(String name, Stopwatch sw) {
      (buckets[name] ??= []).add(sw.elapsedMicroseconds / 1000.0);
    }

    for (var rep = 0; rep < 6; rep++) {
      // -- dragOnly: pointer events, no pump --
      var sw = Stopwatch()..start();
      final gesture = await tester.startGesture(
        tester.getCenter(scrollable),
      );
      await gesture.moveBy(const Offset(0, -500));
      await gesture.up();
      sw.stop();
      record('dragOnly', sw);

      // -- pumpAfter: the frame that renders the new offset --
      sw = Stopwatch()..start();
      await tester.pump();
      sw.stop();
      record('pumpAfter', sw);

      // -- ballistic settle: pump frames until nothing is scheduled --
      sw = Stopwatch()..start();
      var frames = 0;
      while (tester.binding.hasScheduledFrame && frames < 120) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
      }
      sw.stop();
      record('settle(${frames}f)', sw);

      // -- jumpPump: offset change without any pointer event --
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            ).first,
          )
          .position;
      sw = Stopwatch()..start();
      position.jumpTo(position.pixels + 500);
      await tester.pump();
      sw.stop();
      record('jumpPump', sw);

      // -- settled: a frame with nothing dirty --
      sw = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      sw.stop();
      record('settled', sw);
    }

    final sb = StringBuffer('\nscroll probe — per-rep ms\n');
    for (final e in buckets.entries) {
      sb
        ..write(e.key.padRight(14))
        ..writeln(e.value.map((v) => v.toStringAsFixed(1)).join('  '));
    }
    // ignore: avoid_print
    print(sb);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async => doc.dispose());
  }, timeout: const Timeout(Duration(minutes: 10)));
}
