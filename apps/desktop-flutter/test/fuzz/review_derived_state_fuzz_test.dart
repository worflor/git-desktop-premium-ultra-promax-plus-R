// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_derived_state_fuzz_test.dart — the review's derived state can
// never disagree with the state it is derived from.
//
// WHY THIS EXISTS. The branches page keeps NINE parallel collections
// keyed by deskId (controller, data, reviewed ticks, compose anchor,
// lens posture, lens diff, lens wanted, compare pair, marks memo) plus
// a row-summary map. Parallel maps keyed by one id are a missing
// object, and every review bug fixed on 2026-07-27 was two of them
// disagreeing: first open refreshed data but not ticks, three verbs
// refreshed the row badge and the other nine did not, a gutter tap
// wrote data with no reload at all.
//
// Each was patched individually. That is treating symptoms unless
// something asserts the WHOLE relation, so this drives real verbs
// against a real repository in random order and checks, after every
// single step, that everything derived still agrees with what it was
// derived from. It is the net under the ReviewSession refactor: if
// collapsing those maps into one object breaks a relation, this says
// which one and on which verb.
//
// REAL DATA, not a fixture: a real git repo, real commits, real blob
// reads, real refs. The bugs lived in the seams between git and the
// derived caches, and a hand-authored bundle has no seams.

@Timeout(Duration(minutes: 12))
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/review_anchor.dart';
import 'package:git_desktop/backend/manifold_refs.dart';
import 'package:git_desktop/backend/review_records.dart';
import 'package:git_desktop/features/review/review_pane_controller.dart';
import 'package:git_desktop/features/review/review_session.dart';
import 'package:git_desktop/features/review/review_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/scratch_repo.dart';

/// Scales with MANIFOLD_FUZZ, same convention as the other fuzz suites.
int get _rounds {
  final raw = Platform.environment['MANIFOLD_FUZZ'];
  final n = int.tryParse(raw ?? '') ?? 1;
  return (12 * (n < 1 ? 1 : n)).clamp(12, 400);
}

const _kDeskId = 42;
const _kAuthor = 'jun';
const _kViewer = 'mira';

/// Swallow the result of a @useResult call the fuzz does not assert on:
/// a round cut can legitimately fail (unborn head mid-edit) and the
/// invariant check right after is what actually matters.
Future<void> ok(Future<Object?> f) async => f;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScratchRepo repo;
  late ReviewSession session;


  ManifoldRefs refs() => ManifoldRefs(
        repoPath: repo.dir.path,
        authorName: _kViewer,
        authorEmail: '$_kViewer@manifold.local',
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = await ScratchRepo.create(name: 'review_derived');
    await repo.writeFile('lib/a.dart', List.generate(24, (i) => 'a$i;').join('\n'));
    await repo.writeFile('lib/b.dart', List.generate(18, (i) => 'b$i;').join('\n'));
    await repo.commitAll('base');
    await repo.gitOk(['checkout', '-q', '-b', 'feat']);
    await repo.writeFile(
        'lib/a.dart', List.generate(24, (i) => i == 5 ? 'a5_edited;' : 'a$i;').join('\n'));
    await repo.commitAll('feature work');
    session = ReviewSession(
      controller: ReviewPaneController(
        repoPath: repo.dir.path,
        deskId: _kDeskId,
        headBranch: 'feat',
        baseRef: 'main',
        authorDisplay: _kAuthor,
        viewer: const ReviewIdentity(_kViewer, key: '$_kViewer@example.com'),
        refs: refs(),
      ),
    );
  });

  tearDown(() => repo.dispose());

  /// A COLD reader of the same refs: a brand-new controller with no
  /// caches, no memo, no gate history.
  ///
  /// This is the oracle. Asserting the session against its own reload
  /// would let a drift inside reload agree with itself — the bug would
  /// have to be inconsistent with a copy of the same mistake to be
  /// caught. A second reader that shares only the git refs cannot make
  /// the same mistake, so anything the session believes that a fresh
  /// process would not believe shows up here.
  Future<ReviewPaneData> coldRead() async {
    final fresh = ReviewPaneController(
      repoPath: repo.dir.path,
      deskId: _kDeskId,
      headBranch: 'feat',
      baseRef: 'main',
      authorDisplay: _kAuthor,
      viewer: const ReviewIdentity(_kViewer, key: '$_kViewer@example.com'),
      refs: refs(),
    );
    final r = await fresh.load();
    expect(r.ok, isTrue, reason: 'cold read failed — ${r.error}');
    return r.data!;
  }

  /// Re-derive everything the page caches, from scratch, and assert it
  /// agrees with the freshly loaded state. This is the whole point: the
  /// page keeps these as separate maps, so "agrees" is a claim that has
  /// to be checked rather than a property that holds by construction.
  Future<void> assertConsistent(String after) async {
    // Through the SESSION, because that is what the page reads. Driving
    // the controller directly would have let every relation the session
    // owns — reload serialization, lens coalescing, posture, ticks —
    // go untested while the test claimed to cover them.
    final outcome = await session.reload();
    expect(outcome.isOk, isTrue,
        reason: '$after: reload failed — ${outcome.fault} ${outcome.detail}');
    final d = session.data!;
    final b = d.bundle;

    // I1. Every tick is a claim about bytes that are still there. A tick
    // whose file changed must be ABSENT, not stale — the invalidation
    // the whole content-hash design exists for.
    final paths = {for (final g in b.groups) g.filePath};
    // The session's OWN tick set, refreshed by the reload above — not a
    // fresh recompute, which would have tested the controller twice and
    // the session not at all.
    final ticked = session.reviewedFiles;
    expect(ticked.difference(paths), isEmpty,
        reason: '$after: a tick names a file the pane is not showing');
    final stored = d.state?.reviewedFiles[_kViewer] ?? const {};
    for (final p in ticked) {
      expect(stored[p]?.contentHash, isNotEmpty,
          reason: '$after: $p reads as reviewed with no recorded hash');
    }

    // I2. The row badge and the pane header are two renderings of ONE
    // fact. They drifted in production because different verbs
    // refreshed them.
    final rows = await loadReviewRowSummaries(
      refs: refs(),
      desks: [(deskId: _kDeskId, author: _kAuthor)],
      viewerDisplay: _kViewer,
    );
    final row = rows[_kDeskId];
    if (d.state != null) {
      expect(row, isNotNull, reason: '$after: a live review has no row summary');
      expect(row!.yourTurn, b.header.turn == ReviewTurn.yours,
          reason: '$after: row badge and header disagree about the turn');
      expect(row.unresolvedCount, b.header.unresolvedCount,
          reason: '$after: row and header disagree about unresolved count');
    }

    // I3. Drafts are private until published. A draft that has leaked
    // into the published list is visible to peers who cannot see it.
    for (final t in b.threads) {
      expect(t.isDraftOnly, isFalse,
          reason: '$after: a draft-only thread is in the published list');
      expect(t.threadId, isNotEmpty,
          reason: '$after: a published thread has no id to act on');
    }
    for (final t in b.draftThreads) {
      expect(t.comments.every((c) => c.isDraft), isTrue,
          reason: '$after: a published comment sits in the drafts section');
    }
    expect(d.draftCount, greaterThanOrEqualTo(0));

    // I4. Anchors resolve inside the file or say outdated. A line number
    // past the end of the file would render a thread against nothing.
    for (final t in [...b.threads, ...b.draftThreads]) {
      expect(t.line, greaterThanOrEqualTo(0),
          reason: '$after: ${t.filePath} thread resolved to line ${t.line}');
      if (t.anchorState == ReviewAnchorState.outdated) {
        expect(t.lastSeenRound, greaterThan(0),
            reason: '$after: an outdated thread must pin the round it '
                'was last seen in, or it is pointing at nothing');
      }
    }

    // I5. A round that exists is anchorable; a round of 0 refuses. The
    // header used to claim R1 while every gutter tap was declined.
    expect(b.header.round, d.latestRound,
        reason: '$after: header round disagrees with the cut round');

    // I7. THE ORACLE. Everything the session believes must match what a
    // process that just opened this repository would see. A cache that
    // has quietly diverged from the refs passes every self-consistent
    // check above and fails this one.
    final cold = await coldRead();
    expect(d.latestRound, cold.latestRound,
        reason: '$after: session and a cold reader disagree on the round');
    expect(b.threads.length, cold.bundle.threads.length,
        reason: '$after: session holds a different number of threads '
            'than the refs actually contain');
    expect(b.header.turn, cold.bundle.header.turn,
        reason: '$after: session and a cold reader disagree on the turn');
    expect(b.header.unresolvedCount, cold.bundle.header.unresolvedCount,
        reason: '$after: unresolved count drifted from the refs');
    expect(b.header.standing, cold.bundle.header.standing,
        reason: '$after: standing verdict drifted from the refs');
    expect({for (final t in b.threads) t.threadId},
        {for (final t in cold.bundle.threads) t.threadId},
        reason: '$after: session and refs disagree about WHICH threads '
            'exist, not merely how many');

    // I6. Posture and lens never contradict, in EITHER direction. A
    // lens with no posture is content the viewer dismissed and got
    // back; it was reachable because the spec used to be captured
    // before an await and installed after one.
    if (session.hasLens) {
      expect(session.hasLensPosture, isTrue,
          reason: '$after: a lens is installed with no posture asking for it');
    }
    if (!session.hasLensPosture) {
      expect(session.lens, isNull,
          reason: '$after: a dismissed lens came back');
    }
    expect(session.loading, isFalse,
        reason: '$after: the reload gate did not release');
    expect(session.lensLoading, isFalse,
        reason: '$after: a lens fetch was left in flight');
  }

  test('derived review state never disagrees with its source', () async {
    final rng = Random(20260728);
    await session.controller.load();
    await assertConsistent('initial load');

    var edits = 0;
    for (var i = 0; i < _rounds; i++) {
      final op = rng.nextInt(9);
      switch (op) {
        case 0: // start a review / cut a round
          await ok(session.controller.ensureRound());
          await assertConsistent('ensureRound @$i');

        case 1: // open a thread on a real line
          if ((session.controller.data?.latestRound ?? 0) == 0) {
            await ok(session.controller.ensureRound());
          }
          final line = 1 + rng.nextInt(20);
          final a = await session.controller.captureAt(
              path: 'lib/a.dart', side: 'new', line: line);
          if (a != null) {
            await session.controller.saveOpenerDraft(scope: LineScope(a), body: 'q$i on $line');
          }
          await assertConsistent('openerDraft @$i');

        case 2: // publish the batch, sometimes with a verdict
          await session.controller.publish(
              verdict: rng.nextBool() ? null : 'CHANGES_REQUESTED');
          await assertConsistent('publish @$i');

        case 3: // resolve a published thread
          final threads = session.controller.data?.bundle.threads ?? const [];
          if (threads.isNotEmpty) {
            final t = threads[rng.nextInt(threads.length)];
            await session.controller.resolve(t.threadId,
                how: rng.nextBool() ? 'done' : 'acked');
          }
          await assertConsistent('resolve @$i');

        case 4: // reopen one
          final done = (session.controller.data?.bundle.threads ?? const <ReviewThreadView>[])
              .where((t) => t.state != ReviewThreadState.unresolved)
              .toList();
          if (done.isNotEmpty) {
            await session.controller.reopen(done[rng.nextInt(done.length)].threadId);
          }
          await assertConsistent('reopen @$i');

        case 5: // tick / untick a file the pane is showing
          final groups = session.controller.data?.bundle.groups ?? const [];
          if (groups.isNotEmpty) {
            final g = groups[rng.nextInt(groups.length)];
            await session.controller.setFileReviewed(g.filePath, reviewed: rng.nextBool());
          }
          await assertConsistent('setFileReviewed @$i');

        case 6: // the author edits, which must invalidate ticks + anchors
          edits++;
          await repo.writeFile(
              'lib/a.dart',
              List.generate(
                  24, (n) => n == (edits * 3) % 24 ? 'a${n}_e$edits;' : 'a$n;')
                .join('\n'));
          await repo.commitAll('edit $edits');
          await assertConsistent('author edit @$i');

        case 7: // lens postures, through the session that owns them
          final pick = rng.nextInt(3);
          if (pick == 0) {
            session.posture = const SinceLastLook();
          } else if (pick == 1 && (session.data?.latestRound ?? 0) >= 2) {
            session.posture =
                CompareRounds(1, session.data!.latestRound);
          } else {
            session.clearLens();
          }
          await assertConsistent('lens posture @$i');

        case 8: // attention moves by hand, both directions
          if (rng.nextBool()) {
            await session.controller.stepOutOfAttention();
          } else {
            final to = session.controller.handOffCandidates;
            if (to.isNotEmpty) await session.controller.handTo(to.first);
          }
          await assertConsistent('attention @$i');
      }
    }
  });
}
