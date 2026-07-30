// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_corpus_render_test.dart — real review prose, and hostile prose,
// pushed through the whole chain by a peer.
//
// Every body here is published from ANOTHER machine's clone and read back
// through the real store and controller, because that is the actual trust
// boundary: a comment is remote-authored text that renders unprompted the
// moment a teammate opens the review. A fixture handed straight to a
// widget cannot test that; it skips both the transport that could mangle
// the bytes and the question of what the renderer does with them.
//
//  C1  every prose body survives the round trip byte-for-byte — the
//      store, the JSON, the refs, the merge keys.
//  C2  every prose body renders, and its text is actually on screen.
//  C3  no body of any kind makes the pane throw.
//  C4  a body containing a markdown image renders NO image widget and
//      issues no request. This is the leak L21 closes, checked at
//      runtime rather than in the source.
//  C5  a NUL in a body cannot forge a comment identity: two comments
//      that differ only around the separator stay two comments.

@Timeout(Duration(minutes: 12))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/review_corpus.dart';
import '../../support/review_lab.dart';

void main() {
  late ReviewLab lab;

  setUp(() async => lab = await ReviewLab.create(names: const [
        'alice',
        'bob',
      ]));
  tearDown(() async => lab.dispose());

  test('C1: every recorded prose body survives the round trip exactly',
      () async {
    // One body per line, all published by the reviewer, then read back
    // from the author's clone — through JSON, through the refs, through
    // the declared merge.
    var line = 1;
    for (final entry in kProseCorpus) {
      await lab['bob'].say(line++, entry.body);
    }
    await lab.syncAll();

    final got = {
      for (final t in (await lab.author.read()).state!.threads)
        for (final c in t.comments) c.body,
    };
    for (final entry in kProseCorpus) {
      expect(got, contains(entry.body),
          reason: 'the "${entry.label}" body did not survive the trip '
              'intact (${entry.why})');
    }
    expect(got.length, kProseCorpus.length,
        reason: 'bodies were merged or dropped: expected '
            '${kProseCorpus.length} distinct comments, got ${got.length}');
  });

  testWidgets('C2/C3: every recorded body renders, and its text is readable',
      (tester) async {
    await tester.runAsync(() async {
      var line = 1;
      for (final entry in [...kProseCorpus, ...kHostileCorpus]) {
        await lab['bob'].say(line++, entry.body);
      }
      await lab.syncAll();
    });

    // C3 is implicit and load-bearing: pumpLabPane rethrows anything the
    // build throws, so an unterminated fence or a stacked-mark run that
    // crashed the renderer would fail here rather than in production.
    await pumpLabPane(tester, lab.author, size: const Size(1000, 20000));
    final onScreen = visibleText(tester);

    // C2: check the bodies whose text markdown leaves intact. Prose that
    // markdown legitimately restructures (fences, lists, quotes) is
    // checked by a distinctive fragment instead of the whole body.
    const fragments = {
      'plain': 'is the second call load-bearing',
      'fenced-code': 'final steps = [for (var i = 0; i < n; i++)',
      'stack-trace': 'RangeError (index): Invalid value',
      'list-and-quote': 'later is where index bugs live',
      'cjk': '二つの責務',
      'emoji-and-rtl': 'renders in the same row',
      'very-long-line': 'off by one and nobody can explain why',
      'markdown-lookalike': 'is not a rule',
    };
    for (final entry in fragments.entries) {
      expect(onScreen, contains(entry.value),
          reason: 'the "${entry.key}" body is in the review but its text '
              'never reached the screen');
    }
  });

  testWidgets('C4: a peer\'s markdown image renders as text, never a request',
      (tester) async {
    final imageBodies =
        kHostileCorpus.where((e) => e.label.contains('image')).toList();
    expect(imageBodies, isNotEmpty, reason: 'the corpus lost its image cases');

    await tester.runAsync(() async {
      var line = 1;
      for (final entry in imageBodies) {
        await lab['bob'].say(line++, entry.body);
      }
      await lab.syncAll();
    });
    await pumpLabPane(tester, lab.author);

    // The whole finding, as one assertion: flutter_markdown's default
    // builder hands http/https to Image.network and everything else to
    // Image.file, so a bare MarkdownBody would put a real Image in this
    // tree and a GET on the wire. proseMarkdown puts inert text there.
    expect(find.byType(Image), findsNothing,
        reason: 'a review comment written on another machine produced an '
            'Image widget: opening the pane fetches a URL the comment '
            'author chose, which is a read receipt on every reviewer');
    expect(find.byType(RawImage), findsNothing);

    final onScreen = visibleText(tester);
    expect(onScreen, contains('[image not loaded]'),
        reason: 'the suppression is invisible — a reviewer should be able '
            'to see that something was stripped, not silently lose it');
    // And it says WHAT was suppressed, so the attempt is legible.
    expect(onScreen, contains('tracker.invalid'),
        reason: 'the suppressed URL is not shown, so a reviewer cannot '
            'tell a broken paste from a beacon');
  });

  test('C5: a NUL in a body cannot forge a comment identity', () async {
    // The comment dedup key is (display, at, body). If a body's
    // NULs were allowed to shift the field boundaries, two distinct
    // comments could collapse into one — a reviewer's words vanishing
    // because someone else's body happened to contain a separator.
    final hostile = kHostileCorpus.firstWhere((e) => e.label == 'nul-separator');
    await lab['bob'].say(1, hostile.body);
    await lab['bob'].say(2, '${hostile.body}\u0000tail');
    await lab.syncAll();

    final bodies = [
      for (final t in (await lab.author.read()).state!.threads)
        for (final c in t.comments) c.body,
    ];
    expect(bodies.length, 2,
        reason: 'two comments differing only around the NUL separator '
            'collapsed into ${bodies.length}: $bodies');
    expect(bodies, contains(hostile.body));
    expect(bodies, contains('${hostile.body}\u0000tail'));
  });
}
