// diff_shell_widget_test.dart — DiffShell integration witnesses.
//
// The document layer's backing-equivalence law proves eager / in-RAM lazy /
// spooled documents expose identical surfaces; these tests witness the layer
// ABOVE it that the law cannot reach: the shell actually rendering each
// backing, swapping content on documentId change, adopting a same-id new
// document instance while the parent disposes the old one's store (the
// reads-from-closed-handle class), and scrolling a windowed spooled doc.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_shell.dart';
import 'package:git_desktop/ui/tokens.dart';

import '../../support/widget_harness.dart';

// Default hunk count clears DiffShell's animated-melt-text threshold
// (kAnimatedDiffMaxChangedLines = 24; 2 changed lines per hunk here) so
// added/removed rows render as plain Text — findable via find.textContaining
// — instead of painted directly onto a CustomPaint canvas outside the widget
// tree. Tests that need a SMALL diff for a specific reason must pass enough
// hunks explicitly to stay over that line, or assert only on chrome text
// (hunk headers, line numbers) that always renders as a widget.
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

Future<void> _pumpShell(
  WidgetTester tester, {
  DiffDocument? document,
  String filePath = 'a.txt',
}) async {
  await pumpHarness(
    tester,
    Scaffold(
      body: DiffShell(
        filePath: filePath,
        tokens: AppTokens.fromId(AppThemeId.aether),
        document: document,
      ),
    ),
  );
  await tester.pump();
}

Finder _row(String text) => find.textContaining(text, findRichText: true);

/// The shell hydrates display rows asynchronously (post-frame + cooperative
/// index work), so a single pump races it. Drive frames until [finder]
/// matches or the budget runs out — the following expect gives the real
/// failure message.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    installSharedPreferencesMock();
    await loadTestFonts();
  });

  late Directory tmp;
  setUp(() async {
    await installHermeticStorageSeams();
    tmp = await Directory.systemTemp.createTemp('diff_shell_widget_');
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

  testWidgets('renders the same rows across all three backings', (
    tester,
  ) async {
    final raw = _diff();
    final backings = <String, Future<DiffDocument> Function()>{
      'eager': () async =>
          DiffDocument.fromRawContent(rawContent: raw, documentId: 'eager:x'),
      'in-RAM lazy': () async =>
          DiffDocument.lazy(rawContent: raw, documentId: 'lazy:x'),
      'spooled': () =>
          spoolDoc(tester, raw, name: 'backing.diff', documentId: 'spool:x'),
    };
    for (final entry in backings.entries) {
      final doc = await entry.value();
      await _pumpShell(tester, document: doc);
      await _pumpUntil(tester, _row('added ALPHA h0'));
      // Adds and context only: paired REMOVE rows are a progressive
      // enhancement (edit-unit pairing folds them into the add row on eager
      // backings), so they are deliberately not part of this invariant.
      for (final expected in [
        'added ALPHA h0',
        'context ALPHA h0',
        'added ALPHA h1',
      ]) {
        expect(
          _row(expected),
          findsWidgets,
          reason: '${entry.key}: "$expected" must render',
        );
      }
    }
  });

  testWidgets('documentId change swaps the rendered content', (tester) async {
    final docA = DiffDocument.lazy(
      rawContent: _diff(marker: 'ALPHA'),
      documentId: 'doc:a',
    );
    await _pumpShell(tester, document: docA);
    await _pumpUntil(tester, _row('added ALPHA h0'));
    expect(_row('added ALPHA h0'), findsWidgets);

    final docB = DiffDocument.lazy(
      rawContent: _diff(marker: 'OMEGA'),
      documentId: 'doc:b',
    );
    await _pumpShell(tester, document: docB);
    await _pumpUntil(tester, _row('added OMEGA h0'));
    expect(_row('added OMEGA h0'), findsWidgets);
    expect(
      _row('added ALPHA h0'),
      findsNothing,
      reason: 'stale document content must not survive an id change',
    );
  });

  testWidgets(
    'same-id new instance is adopted and survives the old store\'s disposal',
    (tester) async {
      // Production shape: a parent rebuilds a spool doc for the same logical
      // diff (same documentId), installs the NEW instance, then disposes the
      // OLD one. A shell that keeps rendering the old instance would read
      // from a closed file handle on the next hydration.
      final raw = _diff(marker: 'GAMMA', hunks: 15);
      final doc1 = await spoolDoc(
        tester,
        raw,
        name: 'gen1.diff',
        documentId: 'pr-spool:same',
      );
      await _pumpShell(tester, document: doc1);
      await _pumpUntil(tester, _row('added GAMMA h0'));
      expect(_row('added GAMMA h0'), findsWidgets);

      final doc2 = await spoolDoc(
        tester,
        raw,
        name: 'gen2.diff',
        documentId: 'pr-spool:same',
      );
      await _pumpShell(tester, document: doc2);
      doc1.dispose(); // the parent frees the replaced instance

      // Force fresh hydration work after the old store is closed: scroll,
      // then settle. Rendering must come from doc2's live store.
      await _pumpUntil(tester, _row('added GAMMA h0'));
      await tester.drag(
        _row('added GAMMA h0').first,
        const Offset(0, -200),
        warnIfMissed: false,
      );
      // DiffShell runs ongoing frame telemetry (session stopwatch, blame
      // hover timers) that never fully quiesces — pumpAndSettle times out
      // on it. A bounded pump budget is the right tool, same as jank_budget
      // and the rest of this file's helpers.
      await _pumpUntil(tester, _row('added GAMMA h2'));
      expect(_row('added GAMMA h2'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a windowed spooled document scrolls to off-screen rows', (
    tester,
  ) async {
    // Big enough that later hunks start off-screen; every row must arrive
    // through the store-backed window, not a resident string.
    final raw = _diff(marker: 'DELTA', hunks: 400);
    final doc = await spoolDoc(
      tester,
      raw,
      name: 'big.diff',
      documentId: 'spool:big',
    );
    await _pumpShell(tester, document: doc);
    await _pumpUntil(tester, _row('added DELTA h0'));
    expect(_row('added DELTA h0'), findsWidgets);
    expect(_row('added DELTA h399'), findsNothing);

    // Drag the Scrollable directly, not a row widget — a row-level gesture
    // detector (staging toggle, text selection) can swallow a drag that
    // starts on a Text/RichText child before it ever reaches the scroll view.
    final scrollable = find.byType(Scrollable).first;
    for (
      var i = 0;
      i < 200 && _row('added DELTA h399').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(scrollable, const Offset(0, -600), warnIfMissed: false);
      await tester.pump();
    }
    expect(
      _row('added DELTA h399'),
      findsWidgets,
      reason: 'the last hunk must hydrate on demand while scrolling',
    );
    expect(tester.takeException(), isNull);
    // Unmount the shell before the test ends so its own timers (scroll-idle,
    // hot-hunk-clear) are cancelled by State.dispose() rather than left
    // pending against flutter_test's end-of-test invariant check.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
