// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_stage_test.dart — stand up a real multi-party review to open in
// the actual app.
//
// The suites next door prove the review is correct. They cannot tell you
// whether it FEELS right, and a person cannot answer that alone: judging
// the pane needs a review that already has two reviewers disagreeing, a
// thread someone resolved, an anchor the author moved out from under, and
// a draft that is yours and not theirs. Typing all that by hand as three
// imaginary people through one UI is the thing nobody does twice.
//
// So this stages it. It builds the same three real clones the tests use,
// plays a scripted review across them, and then does NOT clean up —
// leaving three repositories on disk that you open in Manifold like any
// other. alice's clone shows the author's seat; bob's and cara's show a
// reviewer's, each with their own private drafts.
//
// It is a test file rather than a tool/ script for one boring reason:
// ReviewStore reaches git.dart, git.dart reaches package:flutter, and
// `dart run` cannot compile that (see law L19). `flutter test` can.
//
// Not part of the suite — gated on an env var, so a normal run skips it
// instead of littering temp dirs:
//
//     MANIFOLD_STAGE=1 flutter test test/support/review_stage_test.dart
//
// Delete the printed sandbox directories when you are done with them.

@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'review_corpus.dart';
import 'review_lab.dart';

void main() {
  final staging = Platform.environment['MANIFOLD_STAGE'] == '1';

  test('stage a three-party review on disk and leave it there', () async {
    final lab = await ReviewLab.create(lines: 60);
    // NO dispose: leaving it is the entire point.

    final alice = lab.author;
    final bob = lab['bob'];
    final cara = lab['cara'];

    // ── A review with something in it ───────────────────────────────
    // Two reviewers who write differently, from the recorded personas.
    final bobLines = kPersonas.firstWhere((p) => p.name == 'bob').openers;
    final caraLines = kPersonas.firstWhere((p) => p.name == 'cara').openers;

    await bob.say(4, bobLines[0]);
    await bob.say(8, bobLines[1]);
    await lab.syncAll();
    await cara.say(21, caraLines[0]);
    await cara.say(31, caraLines[1]);
    await lab.syncAll();

    // A real conversation: the author answers, a reviewer answers back.
    final threads = (await alice.read()).state!.threads;
    await alice.draftReply(threads.first.id,
        'good catch — renamed to `stepBase` and `stepScaled` locally.');
    await alice.publish();
    await lab.syncAll();
    await bob.draftReply(threads.first.id, 'that reads much better, thanks.');
    await bob.publish();
    await lab.syncAll();

    // One thread closed, so the pane has a resolved card to render.
    await bob.resolve(threads.first.id, how: 'done');
    await lab.syncAll();

    // A markdown-heavy body, because that is what review prose is.
    await cara.say(
        12, kProseCorpus.firstWhere((e) => e.label == 'fenced-code').body);
    await lab.syncAll();

    // A verdict, so the header has a standing to show.
    await cara.draftOpener(40, 'one more pass and I am happy with this.');
    await cara.publish(verdict: 'CHANGES_REQUESTED');
    await lab.syncAll();

    // The author moves code under an existing comment: this is how you
    // see a re-anchored thread and its provenance without waiting for it
    // to happen by accident.
    await lab.authorEdits(insertAt: 2, count: 6);
    await lab.syncAll();

    // Private drafts, one per reviewer, never published. Each is visible
    // ONLY in that member's clone — open both and compare.
    await bob.draftOpener(15, 'draft (bob only): is this off by one?');
    await cara.draftOpener(15, 'draft (cara only): same line, my note.');

    final data = await alice.read();
    // ignore: avoid_print
    print('''

─── manifold review stage ────────────────────────────────────────────

Open any of these in Manifold. They are real clones of one bare origin,
so pushing and fetching between them works with no network:

  author    alice   ${alice.repo.dir.path}
  reviewer  bob     ${bob.repo.dir.path}
  reviewer  cara    ${cara.repo.dir.path}
  origin (bare)     ${lab.originPath}

The review is desk PR #${lab.deskId} on branch $kLabHead (base $kLabBase),
round ${data.latestRound}, ${data.state!.threads.length} threads,
${data.state!.unresolvedCount} unresolved, waiting on
"${data.bundle.header.waitingOn}".

What to look at:
  • alice's pane: both reviewers' threads, one resolved by bob, one
    re-anchored because she inserted six lines above it.
  • bob's pane: his own draft on line 15. cara's draft on the SAME line
    must not appear.
  • cara's pane: the mirror image — her draft, not bob's — plus the
    CHANGES_REQUESTED standing she published.
  • the fenced code block cara posted, for markdown rendering.

These are temp-dir sandboxes and nothing will clean them up for you.

──────────────────────────────────────────────────────────────────────
''');
    expect(data.state!.threads.length, greaterThanOrEqualTo(5),
        reason: 'the stage did not build a review worth looking at');
  }, skip: staging ? false : 'set MANIFOLD_STAGE=1 to stage a review on disk');
}
