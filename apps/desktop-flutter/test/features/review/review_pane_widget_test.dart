// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_pane_widget_test.dart — behaviour of the assembled pane.
//
// The preview harness proves these surfaces LOOK right; this proves
// they ACT right. Every verb is asserted at its call site, because the
// pane is the one place where a mis-wired callback would quietly
// resolve the wrong thread or publish the wrong verdict.
//
//  P1  published threads route done/ack/reply with their own id.
//  P2  reply opens a composer under ITS thread, saves as a DRAFT, and
//      closes on success; cancel closes without saving.
//  P3  draft-only threads offer NO verbs — their actions are the batch
//      bar's, per the look laws.
//  P4  the publish bar is inert until there is something to publish,
//      carries the selected verdict, and discards drafts separately.
//  P5  the composer refuses empty/whitespace bodies.
//  P6  a resolved thread offers reopen ON ITS STATE CHIP — no verb row,
//      because resolved cards recede — and an unresolved one does not.
//  P7  a save that lands late closes only the composer IT opened. The
//      user can cancel and start another one mid-flight, and that text
//      must survive the earlier save completing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/review/review_adapter.dart';
import 'package:git_desktop/features/review/review_pane.dart';
import 'package:git_desktop/features/review/review_view_model.dart';
import 'package:git_desktop/ui/tokens.dart';

import '../../support/widget_harness.dart';

ReviewThreadView _thread({
  required String id,
  String path = 'lib/a.dart',
  int line = 10,
  ReviewThreadState state = ReviewThreadState.unresolved,
  bool draftOnly = false,
}) =>
    ReviewThreadView(
      threadId: id,
      filePath: path,
      line: line,
      excerpt: 'final x = 1;',
      state: state,
      // A resolved thread always names its resolver — the chip reads
      // "done · jun", and a card without it would be testing a state
      // the store cannot produce.
      resolvedBy: state == ReviewThreadState.unresolved ? '' : 'jun',
      comments: [
        ReviewCommentView(
          author: 'mira',
          at: DateTime.utc(2026, 7, 22, 10),
          body: 'why this?',
          isDraft: draftOnly,
        ),
      ],
    );

ReviewViewBundle _bundle({
  List<ReviewThreadView> threads = const [],
  List<ReviewThreadView> drafts = const [],
}) =>
    ReviewViewBundle(
      header: const ReviewHeaderView(
        round: 2,
        turn: ReviewTurn.yours,
        waitingOn: 'you',
        unresolvedCount: 1,
      ),
      threads: threads,
      groups: groupThreadsByFile(threads),
      draftThreads: drafts,
    );

void main() {
  setUpAll(() async {
    installSharedPreferencesMock();
    await loadTestFonts();
  });

  Future<void> pumpPane(
    WidgetTester tester,
    ReviewViewBundle bundle, {
    int draftCount = 0,
    List<(String, String)>? resolves,
    List<(String, String)>? replies,
    List<String?>? publishes,
    VoidCallback? onDiscard,
    bool replyOk = true,
    List<String>? reopens,
    Completer<void>? holdReply,
  }) async {
    await pumpHarness(
      tester,
      Scaffold(
        backgroundColor: AppTokens.fromId(AppThemeId.petrichor).bg1,
        body: SingleChildScrollView(
          child: ReviewPane(
            bundle: bundle,
            strings: const ReviewStrings(),
            now: DateTime.utc(2026, 7, 22, 13),
            draftCount: draftCount,
            onSaveReply: (threadId, body) async {
              replies?.add((threadId, body));
              if (holdReply != null) await holdReply.future;
              return replyOk;
            },
            onResolve: (threadId, how) async {
              resolves?.add((threadId, how));
            },
            onReopen: reopens == null
                ? null
                : (threadId) async => reopens.add(threadId),
            onPublish: (verdict) async => publishes?.add(verdict),
            onDiscardDrafts: onDiscard ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('P1: verbs carry their own thread id', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final resolves = <(String, String)>[];
    await pumpPane(
      tester,
      _bundle(threads: [
        _thread(id: 't-one', line: 10),
        _thread(id: 't-two', line: 20),
      ]),
      resolves: resolves,
    );

    // Second thread's `done` must resolve t-two, not the first card's.
    await tester.tap(find.text('done').last);
    await tester.pump();
    expect(resolves, [('t-two', 'done')]);

    await tester.tap(find.text('ack').first);
    await tester.pump();
    expect(resolves.last, ('t-one', 'acked'));
  });

  testWidgets('P2: reply composes a draft under its own thread',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final replies = <(String, String)>[];
    await pumpPane(
      tester,
      _bundle(threads: [
        _thread(id: 't-one', line: 10),
        _thread(id: 't-two', line: 20),
      ]),
      replies: replies,
    );

    expect(find.byType(ReviewComposer), findsNothing);
    await tester.tap(find.text('reply').last);
    await tester.pumpAndSettle();

    // Exactly one composer, anchored to the thread that opened it.
    expect(find.byType(ReviewComposer), findsOneWidget);
    expect(find.text('lib/a.dart:20'), findsOneWidget);
    // It saves DRAFTS — the verb says so, and nothing here publishes.
    expect(find.text('save draft'), findsOneWidget);
    expect(find.text('publish'), findsOneWidget); // the bar's, not ours

    await tester.enterText(find.byType(TextField), '  will fix  ');
    await tester.tap(find.text('save draft'));
    await tester.pumpAndSettle();

    expect(replies, [('t-two', 'will fix')],
        reason: 'body trimmed, routed to the opening thread');
    expect(find.byType(ReviewComposer), findsNothing,
        reason: 'a saved reply closes its composer');

    // Cancel closes without saving.
    await tester.tap(find.text('reply').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'never sent');
    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewComposer), findsNothing);
    expect(replies, hasLength(1));
  });

  testWidgets('P3: draft-only threads carry no verbs', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpPane(
      tester,
      _bundle(drafts: [_thread(id: '', draftOnly: true)]),
      draftCount: 1,
    );

    expect(find.text('drafts'), findsOneWidget);
    expect(find.text('done'), findsNothing);
    expect(find.text('ack'), findsNothing);
    expect(find.text('reply'), findsNothing);
    // Its actions live on the batch bar instead.
    expect(find.text('discard'), findsOneWidget);
    expect(find.text('1 draft'), findsOneWidget);
  });

  testWidgets('P4: the bar gates, carries the verdict, discards apart',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final publishes = <String?>[];
    var discarded = 0;
    await pumpPane(
      tester,
      _bundle(threads: [_thread(id: 't-one')]),
      publishes: publishes,
      onDiscard: () => discarded++,
    );

    // Nothing drafted and no verdict chosen: publish is inert. The tap
    // is EXPECTED to miss — the gate wraps the pill in an IgnorePointer,
    // so warnIfMissed is off here to keep a real miss elsewhere loud.
    expect(find.text('discard'), findsNothing);
    await tester.tap(find.text('publish'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(publishes, isEmpty);

    // A verdict alone is publishable — approving without comments is a
    // legitimate turn.
    await tester.tap(find.text('approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('publish'));
    await tester.pumpAndSettle();
    expect(publishes, ['APPROVED']);

    // The choice resets after publishing, so the next turn starts
    // neutral — and inert again (this tap must also miss).
    await tester.tap(find.text('publish'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(publishes, ['APPROVED'], reason: 'inert again once reset');

    // With drafts present, discard is separate from publish.
    await pumpPane(
      tester,
      _bundle(threads: [_thread(id: 't-one')]),
      draftCount: 2,
      publishes: publishes,
      onDiscard: () => discarded++,
    );
    expect(find.text('2 drafts'), findsOneWidget);
    await tester.tap(find.text('discard'));
    await tester.pumpAndSettle();
    expect(discarded, 1);
    expect(publishes, hasLength(1), reason: 'discard never publishes');

    // Comment-only (no verdict) publishes as null once drafts exist.
    await tester.tap(find.text('publish'));
    await tester.pumpAndSettle();
    expect(publishes, ['APPROVED', null]);
  });

  testWidgets('P5: empty bodies never become drafts', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final replies = <(String, String)>[];
    await pumpPane(
      tester,
      _bundle(threads: [_thread(id: 't-one')]),
      replies: replies,
    );

    await tester.tap(find.text('reply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('save draft'));
    await tester.pumpAndSettle();
    expect(replies, isEmpty, reason: 'an empty body is not a draft');

    await tester.enterText(find.byType(TextField), '   \n  ');
    await tester.tap(find.text('save draft'));
    await tester.pumpAndSettle();
    expect(replies, isEmpty, reason: 'whitespace is not a comment');
    expect(find.byType(ReviewComposer), findsOneWidget,
        reason: 'the composer stays open for a real body');
  });

  testWidgets('P6: resolved threads reopen from their state chip',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final reopens = <String>[];
    await pumpPane(
      tester,
      _bundle(threads: [
        _thread(id: 't-open', line: 10),
        _thread(id: 't-done', line: 20, state: ReviewThreadState.done),
      ]),
      reopens: reopens,
    );

    // The resolved card still claims no verbs — that law holds.
    expect(find.text('done · jun'), findsOneWidget);
    expect(find.text('reply'), findsOneWidget,
        reason: 'only the unresolved thread carries verbs');
    expect(find.text('done'), findsOneWidget,
        reason: "the unresolved thread's own done verb, not a second card");

    // Its state chip is the way back.
    await tester.tap(find.text('done · jun'));
    await tester.pump();
    expect(reopens, ['t-done']);

    // The unresolved thread's chip is inert — there is nothing to undo.
    reopens.clear();
    await tester.tap(find.text('unresolved'), warnIfMissed: false);
    await tester.pump();
    expect(reopens, isEmpty);
  });

  testWidgets('P7: a late save closes only its own composer',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final hold = Completer<void>();
    final replies = <(String, String)>[];
    await pumpPane(
      tester,
      _bundle(threads: [
        _thread(id: 't-one', line: 10),
        _thread(id: 't-two', line: 20),
      ]),
      replies: replies,
      holdReply: hold,
    );

    // Start a reply on the FIRST thread and set its save in flight.
    await tester.tap(find.text('reply').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'on thread one');
    await tester.tap(find.text('save draft'));
    await tester.pump();
    expect(replies, [('t-one', 'on thread one')]);

    // Back out and start a different reply while that save is still
    // running — Cancel is deliberately never busy-gated.
    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('reply').last);
    await tester.pumpAndSettle();
    expect(find.text('lib/a.dart:20'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'still writing this');

    // The first save lands. It must not touch the composer now open.
    hold.complete();
    await tester.pumpAndSettle();

    expect(find.text('lib/a.dart:20'), findsOneWidget,
        reason: "the second composer must survive the first save's return");
    expect(find.text('still writing this'), findsOneWidget,
        reason: 'and keep the text the user is mid-sentence on');
  });
}
