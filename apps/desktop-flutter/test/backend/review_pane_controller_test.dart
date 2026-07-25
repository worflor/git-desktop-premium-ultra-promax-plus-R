// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_pane_controller_test.dart — the production glue's contracts.
//
//  C1  looking is free: load() on an un-reviewed desk mints NO review
//      refs (state doc, round pins — nothing).
//  C2  first intent (ensureRound) cuts round 1; a later load() after
//      the head moved cuts the next round automatically.
//  C3  opener flow end-to-end: capture on head content → draft →
//      publish → thread visible, drafts consumed, last-look pointer
//      lands on the published round.
//  C4  old-side anchors capture and resolve against the MERGE BASE
//      version, so deletion comments stay anchored.
//  C5  the byte gate: over-cap files refuse capture instead of
//      materializing giant strings.
//  C6  reply + resolve verbs round-trip; row summaries project the
//      state without blob loads.
//  C7  an anchor's recorded commit CONTAINS the content it hashed —
//      capture reads the round's pin, never the moving branch tip.
//  C8  lens specs: since-last-look and round-compare both resolve to
//      two-dot pin ranges, and a materialized lens carries the files
//      that differ between exactly those two snapshots.
//  C9  concurrent loads serialize: every verb reloads, so two quick
//      actions must not interleave over the controller's shared blob
//      caches, and the LAST snapshot must be the newest.

// Real-git suite: every case spawns dozens of git processes, and a
// loaded machine (parallel suites) trips the 30s default. Same
// convention as review_sync_test.
@Timeout(Duration(minutes: 4))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/manifold_refs.dart';
import 'package:git_desktop/features/review/review_pane_controller.dart';
import 'package:git_desktop/features/review/review_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/scratch_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScratchRepo repo;
  late ReviewPaneController ctrl;

  ManifoldRefs refs() => ManifoldRefs(
        repoPath: repo.dir.path,
        authorName: 'mira',
        authorEmail: 'mira@manifold.local',
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = await ScratchRepo.create(name: 'review_pane');
    await repo.writeFile('lib/a.dart', 'alpha\nbeta\ngamma\ndelta\n');
    await repo.commitAll('base file');
    await repo.gitOk(['checkout', '-q', '-b', 'feat']);
    await repo.writeFile(
        'lib/a.dart', 'alpha\nbeta2\ngamma\ndelta\nepsilon\n');
    await repo.commitAll('feature change');
    ctrl = ReviewPaneController(
      repoPath: repo.dir.path,
      deskId: 42,
      headBranch: 'feat',
      baseRef: 'main',
      authorDisplay: 'jun',
      viewerDisplay: 'mira',
      refs: refs(),
    );
  });

  tearDown(() => repo.dispose());

  test('C1: looking mints nothing', () async {
    final r = await ctrl.load();
    expect(r.ok, isTrue, reason: r.error ?? '');
    expect(r.data!.hasReview, isFalse);
    expect(r.data!.latestRound, 0);
    final out = await repo.gitOk(['for-each-ref', 'refs/manifold/']);
    expect(out.contains('review'), isFalse,
        reason: 'load() must not create review refs: $out');
  });

  test('C2: first intent cuts round 1; head move cuts the next', () async {
    await ctrl.load();
    final r1 = await ctrl.ensureRound();
    expect(r1.ok, isTrue, reason: r1.error ?? '');
    expect(r1.data!.latestRound, 1);
    // ensureRound is idempotent while the head is still.
    final r1b = await ctrl.ensureRound();
    expect(r1b.data!.latestRound, 1);

    await repo.writeFile(
        'lib/a.dart', 'alpha\nbeta2\ngamma\ndelta\nepsilon\nzeta\n');
    await repo.commitAll('more work');
    final r2 = await ctrl.load();
    expect(r2.data!.latestRound, 2,
        reason: 'a look after the head moved cuts the next round');
  });

  test('C3: opener draft → publish → pointer lands', () async {
    await ctrl.load();
    expect((await ctrl.ensureRound()).ok, isTrue);
    final anchor =
        await ctrl.captureAt(path: 'lib/a.dart', side: 'new', line: 2);
    expect(anchor, isNotNull);
    expect(anchor!.excerpt, 'beta2');
    expect(await ctrl.saveOpenerDraft(anchor: anchor, body: 'why beta2?'),
        isNull);

    var d = (await ctrl.load()).data!;
    expect(d.draftCount, 1);
    expect(d.bundle.draftThreads, hasLength(1));
    expect(d.bundle.draftThreads.single.anchorState,
        ReviewAnchorState.anchored);
    expect(d.bundle.draftThreads.single.line, 2);

    expect(await ctrl.publish(verdict: 'CHANGES_REQUESTED'), isNull);
    d = (await ctrl.load()).data!;
    expect(d.draftCount, 0);
    expect(d.bundle.draftThreads, isEmpty);
    expect(d.bundle.threads, hasLength(1));
    expect(d.bundle.threads.single.threadId, isNotEmpty);
    expect(d.bundle.threads.single.state, ReviewThreadState.unresolved);
    expect(d.lastSeenRound, d.latestRound,
        reason: 'publishing IS the "I have looked" event');
    expect(d.bundle.header.verdictNote, contains('mira'));
    // Viewer just spoke: the ball is with the author now.
    expect(d.bundle.header.turn, ReviewTurn.theirs);
  });

  test('C4: old-side anchors live on the merge base', () async {
    await ctrl.load();
    expect((await ctrl.ensureRound()).ok, isTrue);
    // Line 2 of the BASE version ('beta') was replaced on feat — the
    // deletion row. Its content comes from the merge-base blob.
    final anchor =
        await ctrl.captureAt(path: 'lib/a.dart', side: 'old', line: 2);
    expect(anchor, isNotNull);
    expect(anchor!.excerpt, 'beta');
    expect(anchor.side, 'old');
    expect(
        await ctrl.saveOpenerDraft(anchor: anchor, body: 'why remove beta?'),
        isNull);
    expect(await ctrl.publish(), isNull);
    final d = (await ctrl.load()).data!;
    expect(d.bundle.threads.single.side, 'old');
    expect(d.bundle.threads.single.anchorState, ReviewAnchorState.anchored,
        reason: 'the old column only shifts when the BASE moves');
  });

  test('C5: over-cap files refuse capture', () async {
    final big =
        List.filled(300000, 'xxxxxxxxxxxxxxx').join('\n'); // ~4.8 MB
    await repo.writeFile('lib/big.txt', big);
    await repo.commitAll('big file');
    await ctrl.load();
    expect((await ctrl.ensureRound()).ok, isTrue);
    expect(
        await ctrl.captureAt(path: 'lib/big.txt', side: 'new', line: 1),
        isNull);
  });

  test('C6: reply + resolve round-trip; summaries project it', () async {
    await ctrl.load();
    expect((await ctrl.ensureRound()).ok, isTrue);
    final anchor =
        await ctrl.captureAt(path: 'lib/a.dart', side: 'new', line: 1);
    await ctrl.saveOpenerDraft(anchor: anchor!, body: 'nit: naming');
    await ctrl.publish();

    var d = (await ctrl.load()).data!;
    final tid = d.bundle.threads.single.threadId;
    expect(await ctrl.saveReplyDraft(threadId: tid, body: 'will fix'),
        isNull);
    d = (await ctrl.load()).data!;
    // Opener + the viewer's unpublished reply draft, inline.
    expect(d.bundle.threads.single.comments, hasLength(2));
    expect(d.bundle.threads.single.comments.last.isDraft, isTrue);

    expect(await ctrl.resolve(tid, how: 'done'), isNull);
    d = (await ctrl.load()).data!;
    expect(d.bundle.threads.single.state, ReviewThreadState.done);
    expect(d.bundle.threads.single.resolvedBy, 'mira');

    final sums = await loadReviewRowSummaries(
      refs: refs(),
      desks: [(deskId: 42, author: 'jun')],
      viewerDisplay: 'jun',
    );
    expect(sums[42], isNotNull);
    expect(sums[42]!.unresolvedCount, 0);

    // A desk with no review at all costs one listing and reports
    // nothing — never a fabricated summary.
    final none = await loadReviewRowSummaries(
      refs: refs(),
      desks: [(deskId: 99, author: 'jun')],
      viewerDisplay: 'jun',
    );
    expect(none, isEmpty);
  });

  test('C9: concurrent loads serialize and land newest-last', () async {
    await ctrl.load();
    expect((await ctrl.ensureRound()).ok, isTrue);
    final a = await ctrl.captureAt(path: 'lib/a.dart', side: 'new', line: 1);
    await ctrl.saveOpenerDraft(anchor: a!, body: 'first');
    await ctrl.publish();

    // Fire the traversals a rapid pair of verbs would: they share the
    // blob caches and `_headSpec`, so an interleave would surface as a
    // wrong or half-resolved bundle rather than an exception.
    final results = await Future.wait([
      ctrl.load(),
      ctrl.load(),
      ctrl.load(),
    ]);
    for (final r in results) {
      expect(r.ok, isTrue, reason: r.error ?? '');
      expect(r.data!.bundle.threads, hasLength(1));
      expect(r.data!.bundle.threads.single.anchorState,
          ReviewAnchorState.anchored,
          reason: 'anchors resolved against a consistent head snapshot');
    }
    // The controller's own snapshot is the newest, not whichever
    // traversal happened to finish last.
    expect(ctrl.data!.latestRound, results.last.data!.latestRound);
    expect(ctrl.data!.bundle.threads, hasLength(1));
  });

  test('C7: the anchor commit holds the content it hashed', () async {
    await ctrl.load();
    expect((await ctrl.ensureRound()).ok, isTrue);
    // The branch moves AFTER the round was cut and before the tap —
    // exactly the window where reading `<branch>:<path>` would hash
    // content the recorded commit does not contain.
    await repo.writeFile('lib/a.dart', 'ZERO\nbeta2\ngamma\n');
    await repo.commitAll('rewrite head');

    final anchor =
        await ctrl.captureAt(path: 'lib/a.dart', side: 'new', line: 1);
    expect(anchor, isNotNull);
    final atCommit = await repo.gitOk(
        ['show', '${anchor!.commit}:lib/a.dart']);
    final lines = splitBlobLines(atCommit);
    expect(lines[anchor.line - 1], anchor.excerpt,
        reason: 'excerpt must come from the commit the anchor names');
    expect(anchor.excerpt, 'alpha',
        reason: 'the round pin, not the branch tip that says ZERO');
  });

  test('C8: lens specs and materialization', () async {
    await ctrl.load();
    expect((await ctrl.ensureRound()).ok, isTrue);
    // Never looked → nothing behind the viewer → no lens.
    expect(ctrl.sinceLastLookSpec, isNull);

    // Publishing marks the look; then the head moves.
    final a1 = await ctrl.captureAt(path: 'lib/a.dart', side: 'new', line: 2);
    await ctrl.saveOpenerDraft(anchor: a1!, body: 'first pass');
    expect(await ctrl.publish(), isNull);
    var d = (await ctrl.load()).data!;
    final r1Commit = d.latestRoundCommit;

    await repo.writeFile('lib/b.dart', 'brand new\n');
    await repo.commitAll('add b');
    d = (await ctrl.load()).data!;
    expect(d.latestRound, 2);

    final spec = ctrl.sinceLastLookSpec;
    expect(spec, '$r1Commit..${d.latestRoundCommit}');
    expect(d.bundle.header.filesSinceLastLook, 1,
        reason: 'counted through the same spec the lens renders');

    final lens = (await ctrl.loadLens(spec!)).data;
    expect(lens, isNotNull);
    expect(lens!.files.map((f) => f.path), ['lib/b.dart']);
    expect(lens.diffFor('lib/b.dart'), contains('brand new'));
    expect(lens.diffFor('lib/a.dart'), isEmpty,
        reason: 'untouched since the last look');

    // Round compare resolves to the same two pins, and a degenerate
    // pair (or an unknown round) has no spec at all.
    expect(ctrl.compareSpec(1, 2), spec);
    expect(ctrl.compareSpec(2, 2), isNull);
    expect(ctrl.compareSpec(1, 9), isNull);

    // Catching up retires the lens: nothing is behind the viewer.
    await ctrl.markCaughtUp();
    await ctrl.load();
    expect(ctrl.sinceLastLookSpec, isNull);
  });
}
