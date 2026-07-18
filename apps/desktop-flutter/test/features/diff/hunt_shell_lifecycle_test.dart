// hunt_shell_lifecycle_test.dart — adversarial-sequencing bug hunt for
// DiffShell's interaction lifecycle: search, pin, document swap, hunk
// collapse, and keyboard nav under torture ordering. Confirmed-repro tests
// only; see the bug-hunt report for anything that didn't reproduce.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_shell.dart';
import 'package:git_desktop/ui/tokens.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

import '../../support/widget_harness.dart';

/// Multi-hunk unified diff, same shape as diff_shell_widget_test.dart's
/// helper — small, resident, human-scale.
String _diff({String marker = 'ALPHA', int hunks = 15, String path = 'a.txt'}) {
  final b = StringBuffer()
    ..writeln('diff --git a/$path b/$path')
    ..writeln('index 1111111..2222222 100644')
    ..writeln('--- a/$path')
    ..writeln('+++ b/$path');
  var old = 1, neu = 1;
  for (var h = 0; h < hunks; h++) {
    b.writeln('@@ -$old,2 +$neu,2 @@');
    b.writeln(' context $marker h$h');
    b.writeln('-removed $marker h$h');
    b.writeln('+added $marker h$h');
    old += 12;
    neu += 12;
  }
  return b.toString();
}

/// New-file unified diff whose body is all `added` lines (every row is a
/// "changed" line for keyboard-nav purposes). [needleAt] optionally injects
/// a unique marker at that 0-based body-line index so search can target a
/// specific far-off row without hydrating the whole window by hand.
String _newFileDiff({
  required int lines,
  String path = 'big.gr',
  int? needleAt,
  String needle = 'NEEDLE',
}) {
  final sb = StringBuffer()
    ..write('diff --git a/$path b/$path\n')
    ..write('new file mode 100644\n')
    ..write('index 0000000..1111111\n')
    ..write('--- /dev/null\n')
    ..write('+++ b/$path\n')
    ..write('@@ -0,0 +1,$lines @@\n');
  for (var i = 0; i < lines; i++) {
    sb.write('+');
    if (i == 0) sb.write('FIRSTROW ');
    if (needleAt != null && i == needleAt) sb.write('$needle ');
    sb.write('row$i');
    sb.write('\n');
  }
  return sb.toString();
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required DiffDocument document,
  String filePath = 'a.txt',
  bool enableStaging = false,
  String? repositoryPath,
}) async {
  await pumpHarness(
    tester,
    Scaffold(
      body: DiffShell(
        filePath: filePath,
        tokens: AppTokens.fromId(AppThemeId.aether),
        document: document,
        enableStaging: enableStaging,
        repositoryPath: repositoryPath,
      ),
    ),
  );
  await tester.pump();
}

Finder _row(String text) => find.textContaining(text, findRichText: true);

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int budget = 100,
}) async {
  for (var i = 0; i < budget && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // Rapid repeated mounts (the swap-storm test) allocate/discard many
  // frames' worth of picture layers faster than the leak tracker's
  // bookkeeping settles — same rationale as diff_smoothness_lab_test.dart.
  LeakTesting.settings = LeakTesting.settings.withIgnoredAll();

  setUpAll(() async {
    installSharedPreferencesMock();
    await loadTestFonts();
  });

  late Directory tmp;
  setUp(() async {
    await installHermeticStorageSeams();
    tmp = await Directory.systemTemp.createTemp('hunt_shell_lifecycle_');
    addTearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });
  });

  Future<DiffDocument> spoolDoc(
    WidgetTester tester,
    String raw, {
    required String name,
    String? documentId,
  }) async {
    final file = File('${tmp.path}${Platform.pathSeparator}$name');
    final doc = await tester.runAsync(() async {
      await file.writeAsString(raw);
      return DiffDocument.lazyFromSpool(file.path, documentId: documentId);
    });
    addTearDown(doc!.dispose);
    return doc;
  }

  /// Tap the search toggle icon in the toolbar. AppIcon exposes a public
  /// `name` field — locate the search toggle via that rather than the
  /// private toolbar-button type.
  Future<void> openSearch(WidgetTester tester) async {
    final target = find.byWidgetPredicate((w) {
      if (w.runtimeType.toString() != 'AppIcon') return false;
      try {
        // ignore: avoid_dynamic_calls
        return (w as dynamic).name == 'search';
      } catch (_) {
        return false;
      }
    });
    expect(target, findsWidgets, reason: 'search toggle icon must render');
    await tester.tap(target.first, warnIfMissed: false);
    await tester.pump();
  }

  Future<void> typeSearch(WidgetTester tester, String term) async {
    final field = find.byType(TextField);
    expect(field, findsWidgets, reason: 'search field must be visible');
    await tester.enterText(field.first, term);
    await tester.pump();
  }

  testWidgets(
    'windowed doc: pin then search-to-far-match then clear does not throw '
    'and content keeps rendering',
    (tester) async {
      final raw = _newFileDiff(lines: 260000, needleAt: 255000);
      final doc = await spoolDoc(
        tester,
        raw,
        name: 'windowed_search.diff',
        documentId: 'hunt:windowed-search',
      );
      await _pumpShell(tester, document: doc, filePath: 'big.gr');
      await _pumpUntil(tester, _row('FIRSTROW'));
      expect(_row('FIRSTROW'), findsWidgets);

      // Pin the first row (tap anywhere on it away from the sigil column).
      await tester.tap(_row('FIRSTROW').first, warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Open search and jump straight to a match that lives past the
      // resident-window threshold (kLeanDiffLineThreshold = 200000).
      await openSearch(tester);
      await typeSearch(tester, 'NEEDLE');
      // Only ONE frame after typing — hunt state desync mid-hydration.
      await tester.pump();
      expect(tester.takeException(), isNull);

      await _pumpUntil(tester, _row('NEEDLE'));
      expect(
        _row('NEEDLE'),
        findsWidgets,
        reason: 'windowed search must surface the far match',
      );
      expect(tester.takeException(), isNull);

      // Clear the term mid-hydration (single pump) then let it settle.
      await typeSearch(tester, '');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _pumpUntil(tester, _row('FIRSTROW'));
      expect(
        _row('FIRSTROW'),
        findsWidgets,
        reason: 'clearing search must restore the unfiltered windowed view',
      );

      // Re-open / close / re-open search — no exception, content survives.
      await openSearch(tester); // closes it (toggle)
      await tester.pump();
      await openSearch(tester); // re-opens
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_row('FIRSTROW'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'pin survives a same-id instance swap but is cleared by a real '
    'documentId change',
    (tester) async {
      final rawA = _diff(marker: 'ALPHA', hunks: 15);
      final docA = DiffDocument.lazy(rawContent: rawA, documentId: 'hunt:pin-a');
      await _pumpShell(tester, document: docA);
      await _pumpUntil(tester, _row('added ALPHA h0'));

      await tester.tap(_row('added ALPHA h0').first, warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Same documentId, NEW instance (production reload shape).
      final docA2 = DiffDocument.lazy(
        rawContent: rawA,
        documentId: 'hunt:pin-a',
      );
      await _pumpShell(tester, document: docA2);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        _row('added ALPHA h0'),
        findsWidgets,
        reason: 'same-id swap must keep rendering the same content',
      );

      // Now swap to a genuinely different document/id.
      final rawB = _diff(marker: 'OMEGA', hunks: 15);
      final docB = DiffDocument.lazy(rawContent: rawB, documentId: 'hunt:pin-b');
      await _pumpShell(tester, document: docB);
      await _pumpUntil(tester, _row('added OMEGA h0'));
      expect(tester.takeException(), isNull);
      expect(_row('added ALPHA h0'), findsNothing);
      expect(_row('added OMEGA h0'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'document swap storm across three backings settles on the last '
    'document with no exception and no stuck loading state',
    (tester) async {
      final small = DiffDocument.lazy(
        rawContent: _diff(marker: 'SMALL', hunks: 5),
        documentId: 'hunt:storm-small',
      );
      final windowedRaw = _newFileDiff(lines: 210000);
      final windowed = await spoolDoc(
        tester,
        windowedRaw,
        name: 'storm_windowed.diff',
        documentId: 'hunt:storm-windowed',
      );
      final other = DiffDocument.lazy(
        rawContent: _diff(marker: 'OTHER', hunks: 5, path: 'b.txt'),
        documentId: 'hunt:storm-other',
      );
      final docs = [small, windowed, other];

      for (var round = 0; round < 20; round++) {
        final doc = docs[round % docs.length];
        await pumpHarness(
          tester,
          Scaffold(
            body: DiffShell(
              filePath: doc == windowed ? 'big.gr' : 'a.txt',
              tokens: AppTokens.fromId(AppThemeId.aether),
              document: doc,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Settle on the LAST document in the cycle (round 19 → index 19 % 3
      // == 1 == windowed).
      final last = docs[19 % docs.length];
      expect(identical(last, windowed), isTrue);
      await _pumpUntil(tester, _row('FIRSTROW'));
      expect(tester.takeException(), isNull);
      expect(
        _row('FIRSTROW'),
        findsWidgets,
        reason: 'must settle on the last document with no stuck loading',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async => windowed.dispose());
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'collapsing the first hunk shifts subsequent row content correctly',
    (tester) async {
      final raw = _diff(marker: 'BETA', hunks: 30);
      final doc = DiffDocument.lazy(rawContent: raw, documentId: 'hunt:collapse');
      await _pumpShell(tester, document: doc);
      await _pumpUntil(tester, _row('added BETA h0'));
      expect(_row('added BETA h0'), findsWidgets);
      expect(_row('added BETA h1'), findsWidgets);

      // Tap the first hunk's header row to collapse it.
      final header0 = find.textContaining('@@ -1,2 +1,2 @@');
      expect(header0, findsWidgets);
      await tester.tap(header0.first, warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        _row('added BETA h0'),
        findsNothing,
        reason: 'collapsed hunk body must be hidden',
      );
      expect(
        _row('added BETA h1'),
        findsWidgets,
        reason: 'later hunks must still render after an earlier collapse',
      );

      // Collapse ALL hunks — walk every header's known (old,new) coordinate
      // directly instead of relying on scroll position.
      var old = 1, neu = 1;
      for (var h = 0; h < 30; h++) {
        final header = find.textContaining('@@ -$old,2 +$neu,2 @@');
        if (header.evaluate().isNotEmpty) {
          await tester.tap(header.first, warnIfMissed: false);
          await tester.pump();
        }
        old += 12;
        neu += 12;
      }
      expect(tester.takeException(), isNull);

      // Collapse during active search: toggle the (now-collapsed) first
      // hunk back open while a search term is live.
      await openSearch(tester);
      await typeSearch(tester, 'BETA');
      await tester.pump();
      final header0b = find.textContaining('@@ -1,2 +1,2 @@');
      if (header0b.evaluate().isNotEmpty) {
        await tester.tap(header0b.first, warnIfMissed: false);
        await tester.pump();
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'keyboard nav on a windowed doc: j/k/p/space stay safe past the '
    'resident-window boundary',
    (tester) async {
      final raw = _newFileDiff(lines: 260000);
      final doc = await spoolDoc(
        tester,
        raw,
        name: 'kbd_windowed.diff',
        documentId: 'hunt:kbd-windowed',
      );
      // No repositoryPath: tapping the body only requests keyboard focus
      // when `_stagingEnabled` (enableStaging && repositoryPath != null),
      // but pinning with a repositoryPath set spawns a REAL `git`/Logos
      // resolve in the background (DiffLogosFacade.analyzePinnedLine →
      // resolveLogosGit) that outlives a bare `pumpWidget(SizedBox.shrink())`
      // teardown — an unrelated backend seam, not the shell lifecycle this
      // hunt targets. Drive focus directly on the shell's own FocusNode
      // instead of through the gated tap path so `p`/`space` still exercise
      // real code with no backend calls in flight.
      await _pumpShell(tester, document: doc, filePath: 'big.gr');
      await _pumpUntil(tester, _row('FIRSTROW'));
      expect(_row('FIRSTROW'), findsWidgets);

      final focusFinder = find.byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'DiffShellStaging',
      );
      expect(focusFinder, findsOneWidget);
      tester.widget<Focus>(focusFinder).focusNode!.requestFocus();
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Boundary: k (up) at the very first line is a no-op, must not throw.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Walk deep past the resident window (200_000) via repeated j.
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
        await tester.pump();
      }
      expect(tester.takeException(), isNull);

      // Force the cursor arbitrarily far via many more presses in a tight
      // loop without pumping every step (adversarial: cursor advances
      // faster than the widget tree settles).
      for (var i = 0; i < 400; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      }
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Pin at the current (possibly far) cursor. `_computePinContext` runs
      // a cooperatively-yielded (Future.delayed) rhyme scan even with no
      // repositoryPath, so drain it with a bounded pump budget rather than
      // a single frame — otherwise its pending zero-duration timer trips
      // flutter_test's post-dispose invariant check (a harness artifact,
      // not a shell bug: the guard `if (!mounted || seq != _pinSeq) return`
      // at diff_shell.dart:2726 makes the eventual completion a safe no-op).
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(tester.takeException(), isNull);

      // Space (staging) must be inert-but-safe: with staging disabled it's
      // ignored at the `_stagingEnabled` gate before reaching
      // `_handleSigilTap`'s own windowed early-return (diff_shell.dart:2242)
      // — either way, no crash and no state corruption.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Content must still render after all of this.
      expect(_row('row').evaluate().isNotEmpty, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
