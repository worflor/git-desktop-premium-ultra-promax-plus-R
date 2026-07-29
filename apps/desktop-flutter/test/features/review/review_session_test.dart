// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_session_test.dart — one reload moves everything, or nothing.
//
// The page's nine per-desk maps produced a family of bugs with one
// shape: data advanced and something derived from it did not. These
// pin the property that makes that unwritable — after [reload], the
// ticks and the lens describe the data that came back in the SAME call,
// never the one before it.
//
//  S1  a reload refreshes data and ticks together.
//  S2  an author's edit clears the tick in the same step that brings
//      the new content in — the invalidation, proven end to end.
//  S3  a lens posture survives a reload and re-derives against the new
//      state; dropping the posture takes the lens down with it. The
//      posture is ONE sealed field, so "since last look AND compare
//      R2..R4 at once" is not a state a caller can construct.
//  S4  concurrent reloads complete without error and release the gate.
//      (The ORDERING claim — last-asked snapshot survives — has no
//      witness here: three identical reloads cannot distinguish a
//      serialized gate from a free-for-all. Pinning it needs a
//      controller seam that can hold one traversal open while another
//      finishes; until then this test claims only what it can falsify.)
//  S5  a lens fetch reports itself busy while it is in flight — the
//      signal the page draws a spinner from, and the one a refactor
//      silently dropped by deriving it from the wrong flag.
//  S7  a replacement session inherits WHERE THE VIEWER WAS — the open
//      composer and the lens posture — because renaming yourself in
//      settings replaces the session for a reason the viewer never
//      asked about and cannot see. Derived state does not cross: it
//      belongs to the retired controller.
//  S8  and none of it crosses a BRANCH change, where an anchor names a
//      line in a diff that is no longer on screen and a round pair
//      names rounds the new branch may not have.
//  S9  a lens dismissed while its fetch is in flight stays dismissed.
//      The body re-reads the posture after its await and loops instead
//      of installing; deleting that one line left every S-test green
//      (the mutation audit's finding), so the race it guards had no
//      witness until this one.
//  S6  a lens result is DATA, never an effect. The session calls
//      nothing back, so a fetch that lands after the page has dropped
//      the session writes only where nothing reads. Desk ids are
//      per-repo sequentials — #7 exists in every repository — and a
//      callback here could not be made safe by an epoch check at the
//      call site, because it would fire before the caller resumed.

@Timeout(Duration(minutes: 6))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/manifold_refs.dart';
import 'package:git_desktop/backend/review_records.dart';
import 'package:git_desktop/features/review/review_pane_controller.dart';
import 'package:git_desktop/features/review/review_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/scratch_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScratchRepo repo;
  late ReviewSession session;
  ManifoldRefs refs() => ManifoldRefs(
        repoPath: repo.dir.path,
        authorName: 'mira',
        authorEmail: 'mira@manifold.local',
      );

  String body(int marker) =>
      List.generate(20, (i) => i == 7 ? 'line7_v$marker;' : 'line$i;')
          .join('\n');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = await ScratchRepo.create(name: 'review_session');
    await repo.writeFile('lib/a.dart', body(0));
    await repo.commitAll('base');
    await repo.gitOk(['checkout', '-q', '-b', 'feat']);
    await repo.writeFile('lib/a.dart', body(1));
    await repo.commitAll('feature work');
    session = ReviewSession(
      controller: ReviewPaneController(
        repoPath: repo.dir.path,
        deskId: 7,
        headBranch: 'feat',
        baseRef: 'main',
        authorDisplay: 'jun',
        viewer: const ReviewIdentity('mira', key: 'mira@example.com'),
        refs: refs(),
      ),
    );
  });

  tearDown(() => repo.dispose());

  /// Start a review with one published thread on the changed line, so
  /// the pane has a file group for the tick to attach to.
  Future<void> seedThread() async {
    expect((await session.controller.ensureRound()).ok, isTrue);
    final anchor = await session.controller
        .captureAt(path: 'lib/a.dart', side: 'new', line: 8);
    expect(anchor, isNotNull, reason: 'line 8 must be anchorable');
    expect(
        await session.controller
            .saveOpenerDraft(anchor: anchor!, body: 'why v1?'),
        isNull);
    expect(await session.controller.publish(), isNull);
  }

  ReviewSession sessionOn(String branch, String viewer) => ReviewSession(
        controller: ReviewPaneController(
          repoPath: repo.dir.path,
          deskId: 7,
          headBranch: branch,
          baseRef: 'main',
          authorDisplay: 'jun',
          viewer: ReviewIdentity(viewer, key: '$viewer@example.com'),
          refs: refs(),
        ),
      );

  test('S7: a same-branch replacement inherits where the viewer was',
      () async {
    session.posture = const CompareRounds(1, 2);
    session.composeAt = ('lib/a.dart', false, 8);
    session.reviewedFiles = const {'lib/a.dart'};

    // The swap an identity change makes: same branch, new signer.
    final next = sessionOn('feat', 'mira-renamed');
    next.adoptPostureFrom(session);

    expect(next.compare, (1, 2),
        reason: 'the lens the viewer chose is still the lens they want');
    expect(next.composeAt, ('lib/a.dart', false, 8),
        reason: 'an open composer must not close under them');
    expect(next.reviewedFiles, isEmpty,
        reason: 'ticks are the OLD controller reading disk — the reload '
            'recomputes them, and copying would show one viewer ticks '
            'under the name of another');
    expect(next.data, isNull);
    expect(next.lens, isNull,
        reason: 'the materialized lens is derived; the posture is not');
  });

  test('S8: nothing crosses a branch change', () async {
    session.posture = const CompareRounds(1, 2);
    session.composeAt = ('lib/a.dart', false, 8);

    final next = sessionOn('other-feature', 'mira');
    next.adoptPostureFrom(session);

    expect(next.posture, isNull);
    expect(next.composeAt, isNull,
        reason: 'the anchor names a line in a diff that is gone');
  });

  test('S9: clearing the lens mid-fetch wins over the fetch', () async {
    await seedThread();
    await session.reload();

    // A real compare needs two DISTINCT pins — compareSpec refuses a
    // degenerate pair outright, which is exactly how the first cut of
    // this test ended up vacuous: CompareRounds(1, 1) never fetches at
    // all, so the race it staged had nothing to race.
    await repo.writeFile('lib/a.dart', body(2));
    await repo.commitAll('round two moves the branch');
    expect((await session.controller.ensureRound()).ok, isTrue,
        reason: 'a second round must pin the moved head');
    expect((await session.reload()).isOk, isTrue);

    // CONTROL: prove the spec actually produces a lens, or the race
    // assertion below is vacuously satisfiable by a failing fetch.
    session.posture = const CompareRounds(1, 2);
    final control = await session.refreshLens();
    expect(control.isOk, isTrue, reason: control.detail ?? '');
    expect(session.lens, isNotNull,
        reason: 'the control fetch must install a lens, else this test '
            'cannot distinguish "dismissed" from "failed"');
    session.clearLens();
    expect(session.lens, isNull);

    // The race: ask again, then dismiss while the git round-trip is in
    // flight. The dismissal is the LAST decision, so it must be the one
    // standing when the dust settles — without the post-await re-read,
    // the fetched lens lands over a posture the viewer already threw
    // away.
    session.posture = const CompareRounds(1, 2);
    final fetch = session.refreshLens();
    session.clearLens();
    final r = await fetch;

    expect(r.isOk, isTrue);
    expect(session.lens, isNull,
        reason: 'the fetch resolved AFTER the viewer dismissed the lens; '
            'installing it anyway shows content they explicitly closed');
    expect(session.posture, isNull);
  });

  test('S1: one reload brings data and ticks together', () async {
    await seedThread();
    expect((await session.reload()).isOk, isTrue);
    expect(session.data, isNotNull);
    expect(session.reviewedFiles, isEmpty);

    final tick =
        await session.controller.setFileReviewed('lib/a.dart', reviewed: true);
    expect(tick.error, isNull);
    expect(tick.unreadable, isFalse);

    // The page used to need a SECOND, separate refresh here, and the
    // verbs that remembered it were not the verbs that changed it.
    expect((await session.reload()).isOk, isTrue);
    expect(session.reviewedFiles, contains('lib/a.dart'));
    expect(session.data!.state?.reviewedFiles['mira']?['lib/a.dart'],
        isNotNull,
        reason: 'the tick the session reports must be the one on disk');
  });

  test('S2: the author edits and the tick clears in the same step',
      () async {
    await seedThread();
    await session.reload();
    expect(await session.controller
            .setFileReviewed('lib/a.dart', reviewed: true),
        (unreadable: false, error: null));
    await session.reload();
    expect(session.reviewedFiles, contains('lib/a.dart'));

    // The author changes the file the viewer just signed off.
    await repo.writeFile('lib/a.dart', body(2));
    await repo.commitAll('author edits after review');

    expect((await session.reload()).isOk, isTrue);
    expect(session.reviewedFiles, isNot(contains('lib/a.dart')),
        reason: 'a tick is a claim about bytes; the bytes moved');
    // And the record still holds the OLD hash — nobody cleared it, it
    // simply stopped matching, which is what makes this work on every
    // clone rather than only on the machine that noticed.
    expect(session.data!.state?.reviewedFiles['mira']?['lib/a.dart'],
        isNotNull);
  });

  test('S3: a lens posture survives reload and comes down with itself',
      () async {
    await seedThread();
    await session.reload();

    // Force a real delta so the lens definitely materializes. The
    // assertion below used to sit behind `if (session.hasLens)`, which
    // meant the test could pass having checked nothing at all — the
    // shape of a test that goes quietly green after the behaviour it
    // guards has been deleted.
    expect(session.data!.lastSeenRound, isNotNull,
        reason: 'publishing set the last-look pointer');
    await repo.writeFile('lib/a.dart', body(3));
    await repo.commitAll('a second round of work');

    session.posture = const SinceLastLook();
    expect((await session.reload()).isOk, isTrue);
    expect(session.data!.latestRound, greaterThanOrEqualTo(2),
        reason: 'the new commit must have cut a round to lens across');
    expect(session.hasLens, isTrue,
        reason: 'a real delta with a since-last-look posture IS a lens');
    expect(session.hasLensPosture, isTrue,
        reason: 'a lens with no posture is one nobody asked for');
    expect(session.lens!.files, isNotEmpty,
        reason: 'the lens must carry the files that actually differ');

    session.clearLens();
    expect(session.hasLens, isFalse);
    expect(session.hasLensPosture, isFalse);
    expect((await session.reload()).isOk, isTrue);
    expect(session.hasLens, isFalse,
        reason: 'a reload must not resurrect a lens the viewer dismissed');
  });

  test('S4: reloads serialize; the newest snapshot is the one that stands',
      () async {
    await seedThread();
    // Three at once, the way three quick verbs would.
    final results = await Future.wait([
      session.reload(),
      session.reload(),
      session.reload(),
    ]);
    expect(results.every((r) => r.isOk), isTrue);
    expect(session.loading, isFalse,
        reason: 'the gate must release even when calls overlap');

    // The surviving snapshot agrees with a fresh read, which is the
    // whole point of serializing: no older traversal landed last.
    final fresh = await session.controller.load();
    expect(session.data!.latestRound, fresh.data!.latestRound);
    expect(session.data!.bundle.threads.length,
        fresh.data!.bundle.threads.length);
  });

  test('S5: a lens fetch reports busy while it is in flight', () async {
    await seedThread();
    await session.reload();
    expect(session.lensLoading, isFalse, reason: 'nothing in flight yet');

    // Do NOT await: the whole point is what the page can observe DURING
    // the fetch. lensLoading is deliberately separate from `loading`,
    // because the two real lens entry points apply a lens without a
    // full reload and a busy signal derived from `loading` would go
    // dark during exactly the fetch the user is waiting on.
    await repo.writeFile('lib/a.dart', body(4));
    await repo.commitAll('another round');
    await session.reload();
    session.posture = const SinceLastLook();
    final pending = session.refreshLens();
    expect(session.lensLoading, isTrue,
        reason: 'the page draws its spinner from this');

    await pending;
    expect(session.lensLoading, isFalse,
        reason: 'and it must come down when the fetch lands');
  });

  test('S6: a dropped session cannot touch the one that replaced it',
      () async {
    await seedThread();
    await session.reload();
    await repo.writeFile('lib/a.dart', body(5));
    await repo.commitAll('work the lens will span');
    await session.reload();

    // A lens fetch goes in flight on the session the page currently
    // holds...
    final dropped = session;
    dropped.posture = const SinceLastLook();
    final inFlight = dropped.refreshLens();

    // ...and then the page switches repository: it drops that session
    // and builds a fresh one for the same desk id, which is exactly
    // what _evictAllPrDetails does. Desk ids are per-repo sequentials,
    // so the replacement legitimately carries the same number.
    final replacement = ReviewSession(
      controller: ReviewPaneController(
        repoPath: repo.dir.path,
        deskId: 7,
        headBranch: 'feat',
        baseRef: 'main',
        authorDisplay: 'jun',
        viewer: const ReviewIdentity('mira', key: 'mira@example.com'),
        refs: refs(),
      ),
    );
    await replacement.reload();

    // The late result lands AFTER the replacement is live.
    await inFlight;

    // It went where it could do no harm: into the object nothing reads
    // any more. The session calls nothing back, so there is no path by
    // which it could have reached the replacement.
    expect(replacement.lens, isNull,
        reason: 'a dropped session must not install a lens on its '
            'successor — this is the cross-repo bug class');
    expect(replacement.posture, isNull,
        reason: 'nor give it a posture nobody asked for');
    expect(replacement.lensLoading, isFalse);
    expect(identical(dropped, replacement), isFalse);
  });
}
