// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_gutter_overlay_test.dart — the review gutter layer's contracts.
//
//  G1  the layer mounts only when a host wires review data, and never
//      alongside staging (that surface owns the left strip).
//  G2  a gutter tap on an added/context row reports the NEW-side line;
//      a tap on a pure deletion row reports the OLD-side line; hunk
//      header rows report nothing.
//  G5  (not an assertion) captures the LIVE overlay to
//      .preview/review/gutter_marks.png. The gutter's look is iterated
//      here rather than against a stand-in widget: a separate lab
//      renderer used to hold that job and had already drifted from what
//      ships (it had no `resolved` kind), which is how a preview starts
//      lying about the product.
//  G4  newSideOnly (any review lens) withdraws deletion-row targets
//      entirely, rather than anchoring against a tree those old-side
//      coordinates don't belong to.
//  G3  the strip is welded to the row's LEFT EDGE, which scrolls
//      horizontally with the rows: taps follow it sideways, and once
//      it scrolls out of view it stops answering entirely (otherwise a
//      pinned strip would sit over code and steal presses).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:git_desktop/features/diff/diff_shell.dart';
import 'package:git_desktop/ui/tokens.dart';

import '../../support/widget_harness.dart';

// Two hunks, far apart so the delete and the add can never fuse into a
// replacement pair: hunk 1 deletes old line 2; hunk 2 adds new line 42.
const _diff = '''
diff --git a/f.txt b/f.txt
index 0000000..1111111 100644
--- a/f.txt
+++ b/f.txt
@@ -1,3 +1,2 @@
 ctx1
-gone
 ctx2
@@ -40,2 +39,3 @@
 ctx40
+added
 ctx41
''';


// One hunk carrying a row for every mark kind the overlay can paint.
const _markedDiff = '''
diff --git a/lib/engine/lattice.dart b/lib/engine/lattice.dart
index 1111111..2222222 100644
--- a/lib/engine/lattice.dart
+++ b/lib/engine/lattice.dart
@@ -210,7 +210,7 @@
   final lease = stagedTip.data ?? zeroFor(commitR.data);
-  final stale = await _probeRemote(remote);
+  final fresh = await _probeRemote(remote, timeout: kProbe);
   scheduleMicrotask(() => _drain(lease));
   return Resonance(lease, fresh);
 }
''';

const _everyMarkKind = [
  DiffLineMark(oldSide: false, line: 210, kind: DiffLineMarkKind.thread),
  DiffLineMark(oldSide: false, line: 211, kind: DiffLineMarkKind.draft),
  DiffLineMark(oldSide: false, line: 212, kind: DiffLineMarkKind.robot),
  DiffLineMark(oldSide: false, line: 213, kind: DiffLineMarkKind.resolved),
  DiffLineMark(oldSide: false, line: 214, kind: DiffLineMarkKind.outdated),
];

Future<void> _capture(WidgetTester tester, Key key, String path) async {
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote ${file.absolute.path}');
  });
}

Finder _layer() => find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_ReviewGutterLayer');

// One hunk whose context line is far wider than a narrow viewport, so
// the rows really do scroll horizontally.
final _wideDiff = '''
diff --git a/f.txt b/f.txt
index 0000000..1111111 100644
--- a/f.txt
+++ b/f.txt
@@ -1,2 +1,2 @@
 ${'w' * 400}
-gone
+here
''';

Future<void> _pumpShell(
  WidgetTester tester, {
  List<DiffLineMark> marks = const [],
  void Function(bool oldSide, int line)? onTap,
  bool staging = false,
  String? diff,
  bool newSideOnly = false,
}) async {
  await pumpHarness(
    tester,
    Scaffold(
      body: DiffShell(
        filePath: 'f.txt',
        tokens: AppTokens.fromId(AppThemeId.aether),
        diffContent: diff ?? _diff,
        enableStaging: staging,
        lineMarks: marks,
        onGutterLineTap: onTap,
        gutterNewSideOnly: newSideOnly,
      ),
    ),
  );
  final row = find.textContaining(
      diff == null ? 'ctx1' : 'wwww',
      findRichText: true);
  for (var i = 0; i < 100 && row.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(row, findsWidgets);
  await tester.pump(const Duration(milliseconds: 50));
}

/// Tap the gutter strip at display row [idx] — pure fixed-extent
/// arithmetic from the layer's own origin, the same math the overlay
/// uses, exercised from the outside in. (Added/deleted rows don't
/// render as RichText, so text-based location can't address them.)
/// [dx] targets a column inside the strip.
Future<void> _tapGutterAtDisplayRow(
  WidgetTester tester,
  int idx, {
  double dx = 8,
}) async {
  final origin = tester.getTopLeft(_layer());
  await tester.tapAt(origin + Offset(dx, idx * 18.0 + 9.0));
  await tester.pump();
}

/// Scroll the diff's HORIZONTAL viewport (the one wrapping the rows).
Future<void> _hScrollTo(WidgetTester tester, double offset) async {
  final h = tester
      .widgetList<Scrollable>(find.byType(Scrollable))
      .firstWhere((s) => s.axisDirection == AxisDirection.right);
  final pos = h.controller!;
  pos.jumpTo(offset);
  await tester.pump();
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

  testWidgets('G1: layer gated on review wiring and staging', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpShell(tester);
    expect(_layer(), findsNothing,
        reason: 'no marks, no callback → no overlay work at all');

    await _pumpShell(tester, onTap: (_, __) {});
    expect(_layer(), findsOneWidget);

    await _pumpShell(tester, onTap: (_, __) {}, staging: true);
    expect(_layer(), findsNothing,
        reason: 'staging owns the strip; the overlay must yield');
  });

  testWidgets('G2: taps resolve side + line through display rows',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final taps = <(bool, int)>[];
    await _pumpShell(
      tester,
      marks: const [
        DiffLineMark(
            oldSide: false, line: 40, kind: DiffLineMarkKind.thread),
        DiffLineMark(
            oldSide: true, line: 2, kind: DiffLineMarkKind.draft),
      ],
      onTap: (oldSide, line) => taps.add((oldSide, line)),
    );

    // Display rows: 0 hunk1 header, 1 ctx1, 2 gone(-), 3 ctx2,
    //                4 hunk2 header, 5 ctx40, 6 added(+), 7 ctx41.
    // Added row → new side, its lineNumNew ('added' is new line 40).
    await _tapGutterAtDisplayRow(tester, 6);
    expect(taps, [(false, 40)]);

    // Pure deletion row → old side, its lineNumOld.
    taps.clear();
    await _tapGutterAtDisplayRow(tester, 2);
    expect(taps, [(true, 2)]);

    // Context row → new side.
    taps.clear();
    await _tapGutterAtDisplayRow(tester, 1);
    expect(taps, [(false, 1)]);

    // Hunk header row → no target, no callback.
    taps.clear();
    await _tapGutterAtDisplayRow(tester, 4);
    expect(taps, isEmpty);
  });

  testWidgets('G4: newSideOnly withdraws deletion-row targets',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final taps = <(bool, int)>[];
    await _pumpShell(
      tester,
      onTap: (oldSide, line) => taps.add((oldSide, line)),
      newSideOnly: true,
    );

    // A lens renders a left column that is NOT the tree old-side anchors
    // live in, so a deletion row must offer nothing at all — no capture
    // against coordinates that don't belong to it.
    await _tapGutterAtDisplayRow(tester, 2);
    expect(taps, isEmpty);

    // New-side rows are unaffected.
    await _tapGutterAtDisplayRow(tester, 6);
    expect(taps, [(false, 40)]);
  });

  testWidgets('G3: the strip rides the horizontal scroll', (tester) async {
    // Narrow viewport + a long line so the rows genuinely scroll sideways.
    tester.view.physicalSize = const Size(320, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final taps = <(bool, int)>[];
    await _pumpShell(
      tester,
      onTap: (oldSide, line) => taps.add((oldSide, line)),
      diff: _wideDiff,
    );

    // At rest the strip answers over the row's left edge.
    await _tapGutterAtDisplayRow(tester, 1);
    expect(taps, [(false, 1)]);

    // Scrolled 8px right, the row's left edge — and the strip with it —
    // has moved 8px left: the tap zone moved, it didn't stay pinned.
    taps.clear();
    await _hScrollTo(tester, 8);
    await _tapGutterAtDisplayRow(tester, 1, dx: 12);
    expect(taps, isEmpty, reason: 'x=12 is now code surface, not strip');
    await _tapGutterAtDisplayRow(tester, 1, dx: 4);
    expect(taps, [(false, 1)]);

    // Scrolled past its whole width, the strip is gone from the viewport
    // and answers nowhere — code keeps every pixel of its own row.
    taps.clear();
    await _hScrollTo(tester, 200);
    for (final dx in [1.0, 4.0, 8.0, 15.0]) {
      await _tapGutterAtDisplayRow(tester, 1, dx: dx);
    }
    expect(taps, isEmpty);
  });

  testWidgets('G5: capture the live gutter overlay', (tester) async {
    tester.view.physicalSize = const Size(760, 260);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const key = ValueKey('gutter-marks');
    await pumpHarness(
      tester,
      Scaffold(
        body: RepaintBoundary(
          key: key,
          child: SizedBox(
            height: 220,
            child: DiffShell(
              filePath: 'lib/engine/lattice.dart',
              tokens: AppTokens.fromId(AppThemeId.nightwalker),
              diffContent: _markedDiff,
              showFileHeader: false,
              enableStaging: false,
              lineMarks: _everyMarkKind,
              onGutterLineTap: (_, __) {},
            ),
          ),
        ),
      ),
    );
    final row = find.textContaining('scheduleMicrotask', findRichText: true);
    for (var i = 0; i < 100 && row.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 120));
    await _capture(tester, key, '.preview/review/gutter_marks.png');
  });
}
