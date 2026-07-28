// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_header_strip_test.dart — the turn chip is also the control.
//
// The attention verbs used to live in a row of unrelated controls above
// the pane while the chip that REPORTS attention lived inside it. They
// are on the chip now, which turns a display into an interaction, and an
// interaction with no test is a claim nobody checked.
//
//  H1  a chip with no verbs to offer is not a button, and pressing it
//      opens nothing — an empty drawer is worse than no drawer.
//  H2  pressing the chip reveals exactly the verbs that apply.
//  H3  handing off names the person pressed, and closes the drawer.
//  H4  stepping out fires, and closes the drawer.
//  H5  a reload that removes every verb closes a drawer left open, so
//      the surface cannot outlive the state it was showing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/review/review_header_strip.dart';
import 'package:git_desktop/features/review/review_view_model.dart';
import 'package:git_desktop/ui/tokens.dart';

import '../../support/widget_harness.dart';

const _strings = ReviewStrings();

ReviewHeaderView _header({ReviewTurn turn = ReviewTurn.yours}) =>
    ReviewHeaderView(
      round: 3,
      turn: turn,
      waitingOn: turn == ReviewTurn.theirs ? 'mira' : '',
      unresolvedCount: 2,
    );

Future<void> _pump(
  WidgetTester tester, {
  List<String> handOffTo = const [],
  void Function(String)? onHandTo,
  VoidCallback? onStepOut,
  ReviewTurn turn = ReviewTurn.yours,
}) async {
  await pumpHarness(
    tester,
    Scaffold(
      backgroundColor: AppTokens.fromId(AppThemeId.petrichor).bg1,
      body: ReviewHeaderStrip(
        header: _header(turn: turn),
        strings: _strings,
        handOffTo: handOffTo,
        onHandTo: onHandTo,
        onStepOut: onStepOut,
      ),
    ),
  );
}

void main() {
  testWidgets('H1: a chip with nothing to offer does not open a drawer',
      (tester) async {
    await _pump(tester);
    expect(find.text(_strings.yourTurn), findsOneWidget);

    await tester.tap(find.text(_strings.yourTurn));
    await tester.pumpAndSettle();

    expect(find.text(_strings.notBlocking), findsNothing);
    expect(find.text(_strings.handTo), findsNothing);
  });

  testWidgets('H2: pressing the chip reveals exactly the verbs that apply',
      (tester) async {
    await _pump(
      tester,
      handOffTo: const ['mira', 'jun'],
      onHandTo: (_) {},
      onStepOut: () {},
    );

    // Closed at rest: the strip is a status line first.
    expect(find.text(_strings.notBlocking), findsNothing);

    await tester.tap(find.text(_strings.yourTurn));
    await tester.pumpAndSettle();

    expect(find.text(_strings.notBlocking), findsOneWidget);
    expect(find.text(_strings.handTo), findsOneWidget);
    expect(find.text('mira'), findsOneWidget);
    expect(find.text('jun'), findsOneWidget);
  });

  testWidgets('H2b: only the hand-off appears when you are not blocking',
      (tester) async {
    // Not in the attention set: "not blocking on me" would be a verb
    // for a state the viewer is not in.
    await _pump(
      tester,
      turn: ReviewTurn.theirs,
      handOffTo: const ['mira'],
      onHandTo: (_) {},
    );
    await tester.tap(find.text(_strings.waitingOn('mira')));
    await tester.pumpAndSettle();

    expect(find.text(_strings.notBlocking), findsNothing);
    expect(find.text('mira'), findsWidgets);
  });

  testWidgets('H3: handing off names the person pressed and closes',
      (tester) async {
    final handed = <String>[];
    await _pump(
      tester,
      handOffTo: const ['mira', 'jun'],
      onHandTo: handed.add,
      onStepOut: () {},
    );
    await tester.tap(find.text(_strings.yourTurn));
    await tester.pumpAndSettle();

    await tester.tap(find.text('jun'));
    await tester.pumpAndSettle();

    expect(handed, ['jun'], reason: 'the pill must name its own person');
    expect(find.text(_strings.handTo), findsNothing,
        reason: 'the drawer closes once its verb has been used');
  });

  testWidgets('H4: stepping out fires and closes', (tester) async {
    var stepped = 0;
    await _pump(
      tester,
      handOffTo: const ['mira'],
      onHandTo: (_) {},
      onStepOut: () => stepped++,
    );
    await tester.tap(find.text(_strings.yourTurn));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_strings.notBlocking));
    await tester.pumpAndSettle();

    expect(stepped, 1);
    expect(find.text(_strings.notBlocking), findsNothing);
  });

  testWidgets('H5: a reload that removes the verbs closes an open drawer',
      (tester) async {
    await _pump(
      tester,
      handOffTo: const ['mira'],
      onHandTo: (_) {},
      onStepOut: () {},
    );
    await tester.tap(find.text(_strings.yourTurn));
    await tester.pumpAndSettle();
    expect(find.text(_strings.notBlocking), findsOneWidget);

    // Every verb goes away — a peer published, say, and the viewer is no
    // longer the one being waited on. The drawer must not survive the
    // state that justified it.
    await _pump(tester, turn: ReviewTurn.theirs);
    await tester.pumpAndSettle();

    expect(find.text(_strings.notBlocking), findsNothing);
    expect(find.text(_strings.handTo), findsNothing);
  });
}
