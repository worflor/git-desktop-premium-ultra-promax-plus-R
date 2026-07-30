// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_scope_test.dart — comments that are not about a line.
//
// A review used to be able to say only "line 12 of this file is wrong",
// because a thread carried a required line anchor. The first thing a
// reviewer actually wants to say is usually "this is two changes in one
// branch" — about none of the lines and all of them — and the only ways
// to say it were to pin it to an arbitrary line (a lie about what was
// meant) or to a verdict, which carries no words.
//
// So a thread's subject is now a sealed [ReviewScope]: a line, a file,
// or the change. These tests hold it to the promise that made a scope
// the right shape rather than a separate "summary" field — that a
// review-wide comment is a THREAD, and therefore inherits every rule
// threads already have.
//
//  S1  a review-scoped comment round-trips to every machine, stays out
//      of the file list, and renders above it.
//  S2  a file-scoped comment groups under its file and leads it.
//  S3  it is drafted, not published, until publish — the same privacy a
//      line comment has, per machine.
//  S4  a verdict and a review-scoped note publish as ONE turn, which is
//      the whole point: "approved, and here is why".
//  S5  it resolves like anything else.
//  S6  deleting a file keeps its thread live — a deletion is IN the
//      change — and a review scope never decays at all.
//  S7  scopes survive a client that does not understand them — the
//      format stayed additive, no schema bump, no migration.
//  S8  a review-scoped comment moves the turn, because it is a comment.

@Timeout(Duration(minutes: 12))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/manifold_refs.dart';
import 'package:git_desktop/backend/review_anchor.dart';
import 'package:git_desktop/backend/review_records.dart';
import 'package:git_desktop/backend/review_store.dart';
import 'package:git_desktop/features/review/review_file_header.dart';
import 'package:git_desktop/features/review/review_view_model.dart';

import '../../support/must.dart';
import '../../support/review_lab.dart';
import '../../support/scratch_team.dart';

void main() {
  late ReviewLab lab;

  setUp(() async => lab = await ReviewLab.create());
  tearDown(() async => lab.dispose());

  List<String> bodiesOf(ReviewState s) =>
      [for (final t in s.threads) ...t.comments.map((c) => c.body)]..sort();

  test('S1: a comment on the change reaches everyone and is not a file',
      () async {
    const said = 'this is two changes in one branch, and I can only '
        'review one of them well';
    await lab['bob'].sayOnChange(said);
    await lab.syncAll();

    for (final m in lab.members.values) {
      final data = await m.read();
      expect(bodiesOf(data.state!), contains(said),
          reason: '${m.name} cannot see the comment');

      final thread = data.state!.threads.single;
      expect(thread.scope, isA<WholeScope>(),
          reason: '${m.name} read the scope back as ${thread.scope}');
      expect(thread.scope.path, '',
          reason: 'the change is not a file, so it has no path');
      expect(thread.scope.round, greaterThan(0),
          reason: 'a review-wide claim is still about a snapshot — a reader '
              'three rounds later has to know which one');

      // The view side: present, and NOT in the file list.
      expect(data.bundle.reviewThreads, hasLength(1));
      expect(data.bundle.groups, isEmpty,
          reason: 'a review-wide thread created a file group, which would '
              'render a heading for a file called ""');
      expect(data.bundle.threads, hasLength(1),
          reason: 'the flat list is every published thread');
    }
  });

  testWidgets('S1b: it renders above the files, with no line reference',
      (tester) async {
    await tester.runAsync(() async {
      await lab['bob'].sayOnChange('about the change as a whole');
      await lab['bob'].say(5, 'about line five');
      await lab.syncAll();
    });
    await pumpLabPane(tester, lab.author);
    final seen = visibleText(tester);
    expect(seen, contains('about the change as a whole'));
    expect(seen, contains('about line five'));
    // The line thread names its position; the change-wide one must not
    // borrow a line number it does not have.
    expect(seen, contains(':5'));
    expect(seen, isNot(contains(':0')),
        reason: 'a scope with no line rendered a line reference anyway');
    // And it comes first — the reader meets "what is this change" before
    // "what is in it".
    final all = seen;
    expect(all.indexOf('about the change as a whole'),
        lessThan(all.indexOf('about line five')),
        reason: 'the change conversation must sit above the files');
  });

  test('S2: a comment on a file leads that file group', () async {
    await lab['bob'].sayOnFile('this file should not be in this change');
    await lab['bob'].say(5, 'and this line is wrong too');
    await lab.syncAll();

    final data = await lab.author.read();
    expect(data.bundle.reviewThreads, isEmpty,
        reason: 'a file comment is about a file, not about the change');
    final group = data.bundle.groups.single;
    expect(group.filePath, ReviewLab.path);
    expect(group.threads, hasLength(2));
    expect(group.threads.first.scope, ReviewThreadScope.file,
        reason: '"about this file" must sort above "about line 5 of it"');
    expect(group.threads.first.line, 0,
        reason: 'a file scope has no line, and 0 is what sorts it first');
    expect(group.threads.last.scope, ReviewThreadScope.line);
  });

  test('S3: an unpublished change-wide draft is private to its machine',
      () async {
    await lab['bob'].draftOnChange('bob thinks out loud');
    await lab['cara'].draftOnChange('cara thinks out loud');
    await lab.syncAll();

    for (final who in lab.members.values) {
      final data = await who.read();
      final mine =
          who.name == lab.author.name ? <String>[] : ['${who.name} thinks out loud'];
      expect([for (final d in data.drafts) d.body], mine,
          reason: '${who.name} sees the wrong drafts: a review-wide draft '
              'is exactly as private as a line draft, because it is the '
              'same kind of object');
      expect(data.state?.threads ?? const [], isEmpty,
          reason: 'a draft published itself');
      // The draft renders for its author, in the drafts section.
      expect(data.bundle.draftThreads.length, who.name == lab.author.name ? 0 : 1);
    }
  });

  test('S4: a verdict and a note about the change publish as one turn',
      () async {
    // The reason a summary comment is a thread and not a field: this is
    // one publish, one batch, one merge, one turn.
    await lab['bob'].sayOnChange(
        'approving, but the naming in here is going to bite us later',
        verdict: 'APPROVED');
    await lab.syncAll();

    for (final m in lab.members.values) {
      final data = await m.read();
      expect([for (final v in data.state!.verdicts) v.verdict],
          contains('APPROVED'),
          reason: '${m.name} lost the verdict');
      expect(bodiesOf(data.state!).join('\n'), contains('bite us later'),
          reason: '${m.name} lost the words that came with the verdict');
      expect(data.bundle.header.standing, ReviewStanding.approved);
      expect(data.bundle.reviewThreads, hasLength(1));
    }
  });

  test('S5: a comment on the change resolves like any other thread',
      () async {
    await lab['bob'].sayOnChange('should this be two branches?');
    await lab.syncAll();
    final id = (await lab.author.read()).state!.threads.single.id;
    await lab.author.resolve(id, how: 'acked');
    await lab.syncAll();

    for (final m in lab.members.values) {
      final data = await m.read();
      expect(data.state!.unresolvedCount, 0,
          reason: '${m.name} still counts it as open');
      expect(data.bundle.reviewThreads.single.state, ReviewThreadState.acked);
      expect(data.bundle.reviewThreads.single.resolvedBy, lab.author.name);
    }
  });

  test('S6: DELETING the file keeps its thread live; a review scope never '
      'decays', () async {
    await lab['bob'].sayOnFile('this file should not be in this change');
    await lab['bob'].sayOnChange('and the change is too big');
    await lab.syncAll();

    var data = await lab.author.read();
    expect(data.bundle.groups.single.threads.single.anchorState,
        ReviewAnchorState.anchored);
    expect(data.bundle.reviewThreads.single.anchorState,
        ReviewAnchorState.anchored);

    // The author deletes it. A deleted file is MORE part of the change,
    // not less — it is in the diff as a deletion — so the thread that
    // asked for exactly this stays live and readable. Marking it
    // outdated here (which an existence probe does, and which this test
    // used to assert) would hide the conversation at the precise moment
    // it was answered.
    await lab.deleteSubject();
    await lab.syncAll();

    data = await lab.author.read();
    final fileThread = data.bundle.threads
        .firstWhere((t) => t.scope == ReviewThreadScope.file);
    expect(fileThread.anchorState, ReviewAnchorState.anchored,
        reason: 'the deletion IS the change, so the thread about it is '
            'still about something in this change');
    expect(data.bundle.reviewThreads.single.anchorState,
        ReviewAnchorState.anchored,
        reason: 'a comment about the change was marked stale, but the '
            'change is what it is about — it cannot decay');
  });

  test('S6b: a comment on a DELETED file lands on the side that has it',
      () async {
    // The case that was born broken: the UI passed side 'new'
    // unconditionally, so a comment on a file the change removed was
    // instantly outdated — about the file most likely to deserve a
    // whole-file comment ("this should not be in this change" is usually
    // said about something being added, but "why was this deleted" is
    // said about something gone).
    //
    // The caller cannot know the side: the changed-file records carry
    // additions and deletions and no status. So it no longer picks one.
    await lab.deleteSubject();
    await lab.syncAll();

    await lab['bob'].sayOnFile('why was this removed?');
    await lab.syncAll();

    final data = await lab.author.read();
    final thread = data.state!.threads.single;
    expect(thread.scope, isA<FileScope>());
    expect((thread.scope as FileScope).side, 'old',
        reason: 'the file exists only at the merge base now, so a comment '
            'about it has to be about that version');
    expect(data.bundle.threads.single.anchorState,
        isNot(ReviewAnchorState.outdated),
        reason: 'the comment was born outdated: it was captured against '
            'the head, where the file no longer is');
  });

  test('S6c: a file reverted out of the change stops reading as current',
      () async {
    // Existence is not membership. A file the author reverted to its base
    // content is still in HEAD and still in the base — and no longer in
    // the diff at all. "This file should not be in this change" about it
    // has been answered, and a thread that keeps reading as current is
    // pointing at code the change does not touch.
    await lab['bob'].sayOnFile('this file does not belong in this branch');
    await lab.syncAll();
    expect(
        (await lab.author.read()).bundle.threads.single.anchorState,
        ReviewAnchorState.anchored,
        reason: 'the file is in the change, so the thread is live');

    await lab.revertSubject();
    await lab.syncAll();

    expect(
        (await lab.author.read()).bundle.threads.single.anchorState,
        ReviewAnchorState.outdated,
        reason: 'the file left the diff but the thread still claimed to '
            'be about something in this change — an existence probe says '
            'yes to a file that is merely still in the tree');
  });

  test('S6d: a file that only DELETES lines stays in the change', () async {
    // The count-based classification this replaced could not tell a file
    // that removes lines from a file that was removed — additions 0,
    // deletions positive, in both cases — and marked a live new-side
    // thread outdated. Binary files are worse still: numstat reports no
    // counts for them at all, and they are the case this scope exists to
    // serve.
    await lab.authorDeletesLines(count: 4);
    await lab.syncAll();
    await lab['bob'].sayOnFile('why did all of this go?');
    await lab.syncAll();

    final view = (await lab.author.read()).bundle.threads.single;
    expect(view.anchorState, ReviewAnchorState.anchored,
        reason: 'the file is still in the change — it only lost lines — '
            'but membership was inferred from line counts, which read a '
            'deletion-only edit as a deleted file');
  });

  test("S9: publishing records only what the viewer had LOADED", () async {
    // Publishing merges. A peer's comment that lands between the
    // viewer's last load and their publish has never been on screen, so
    // it must not be swept into "read" by the act of publishing.
    //
    // The publish here goes through the controller DIRECTLY rather than
    // the lab helper, because the helper reloads first — and a viewer
    // who reloaded genuinely has been shown the comment. The hazard is
    // specifically publishing from a stale snapshot, which is what the
    // app does whenever a peer syncs during composition.
    await lab['bob'].say(5, 'bob: a question');
    await lab.syncAll();
    await lab.author.draftOnChange('alice: my own note');

    // cara speaks and it reaches the author's clone on disk — but the
    // author's controller still holds the snapshot from before it.
    await lab['cara'].say(21, 'cara: something the author never loaded');
    await lab.syncAll();

    expect(await lab.author.controller.publish(), isNull);
    await lab.syncAll();

    final unread = [
      for (final t in (await lab.author.read()).bundle.threads)
        for (final cm in t.comments)
          if (cm.isUnseen) cm.body,
    ];
    expect(unread, contains('cara: something the author never loaded'),
        reason: 'publishing consumed a comment the author was never '
            'shown — the record of what was read must come from the '
            'state they had, not the one the write returned');
    expect(unread, isNot(contains('bob: a question')),
        reason: 'bob was on screen when they published, so it was read');
  });

  test('S10: tearing a review down leaves no refs behind', () async {
    // Abandoning a desk PR used to orphan its entire review: the state
    // doc, one pin per round holding that commit's objects alive
    // forever, and the viewer's unpublished drafts — private
    // half-thoughts outliving the review they belonged to.
    await lab['bob'].sayOnChange('bob: something to say');
    await lab['bob'].draftOnChange('bob: and something private');
    await lab.syncAll();

    final before = await lab['bob'].repo.gitOk(
        ['for-each-ref', '--format=%(refname)', 'refs/manifold/review/',
         'refs/manifold-local/review/']);
    expect(before, contains('/state'), reason: 'no review to tear down');
    expect(before, contains('/round/'));
    expect(before, contains('drafts'));

    final store = ReviewStore(ManifoldRefs(
      repoPath: lab['bob'].repo.dir.path,
      authorName: 'bob',
      authorEmail: ScratchTeam.emailFor('bob'),
    ));
    await expectOk(store.deleteReview(lab.deskId));

    final after = await lab['bob'].repo.gitOk(
        ['for-each-ref', '--format=%(refname)', 'refs/manifold/review/',
         'refs/manifold-local/review/']);
    expect(after.trim(), isEmpty,
        reason: 'the review left refs behind after teardown: $after');
  });

  testWidgets('S11: the file a new comment landed in is marked',
      (tester) async {
    // The header's "N new" is a number with no direction. The only other
    // unread signal is an accent on one comment's timestamp, which you
    // have to already be reading the card to see — so finding what moved
    // in a review with several files meant opening all of them.
    await tester.runAsync(() async {
      await lab['bob'].say(5, 'bob: opened before the author looked');
      await lab.syncAll();
    });

    await pumpLabPane(tester, lab.author);
    final headers = tester.widgetList<ReviewFileHeader>(
        find.byType(ReviewFileHeader));
    expect(headers, isNotEmpty, reason: 'no file row rendered at all');
    expect(headers.any((h) => h.hasUnseen), isTrue,
        reason: 'the file holding an unread comment was not marked, so '
            'the reviewer has nothing to steer by');

    // And once it has been read, the row goes quiet again.
    await tester.runAsync(() async {
      expect(await lab.author.controller.markCaughtUp(), isNull);
      await lab.author.read();
    });
    await pumpLabPane(tester, lab.author);
    expect(
        tester
            .widgetList<ReviewFileHeader>(find.byType(ReviewFileHeader))
            .any((h) => h.hasUnseen),
        isFalse,
        reason: 'the row still claims news after the viewer caught up');
  });

  test('S7: a scope survives a client that cannot read it', () async {
    // The format stayed ADDITIVE on purpose: no schema bump, because the
    // store REFUSES a doc from a higher version outright and a bump would
    // have locked every older client out of the review entirely.
    //
    // So an older client reads a review-scoped thread, does not
    // understand `scope`, keeps it in its `extra` passthrough, and writes
    // it back. Simulated here by round-tripping through JSON with the key
    // treated as unknown — which is exactly what that client's code path
    // does.
    await lab['bob'].sayOnChange('the change is too big');
    await lab['bob'].sayOnFile('and this file is the reason');
    await lab.syncAll();

    final original = (await lab.author.read()).state!;
    final wire = jsonDecode(original.toBlob()) as Map<String, dynamic>;

    // What an old reader keeps: everything it does not consume. Its own
    // key set is today's minus 'scope'.
    const oldKnown = {
      'id', 'state', 'resolvedBy', 'resolvedAt', 'anchor', 'comments',
      'updatedAt',
    };
    final threads = (wire['threads'] as List).cast<Map<String, dynamic>>();
    for (final t in threads) {
      final passthrough = {
        for (final e in t.entries)
          if (!oldKnown.contains(e.key)) e.key: e.value,
      };
      expect(passthrough.containsKey('scope'), isTrue,
          reason: 'an older client would drop the scope on the floor: it '
              'must land in the extras it preserves verbatim');
      // And it writes a zero anchor beside it, which must not win.
      t['anchor'] = <String, dynamic>{};
    }

    final reread = ReviewState.fromJson(wire);
    final kinds = [for (final t in reread.threads) t.scope.runtimeType.toString()]
      ..sort();
    expect(kinds, ['FileScope', 'WholeScope'],
        reason: 'the scope did not survive the trip: a zero anchor won '
            'over the scope the older client faithfully carried');
  });

  test('S8: a comment about the change moves the turn', () async {
    // It is a comment, so it obligates the author. Nothing special was
    // added to the turn fold to make this true — that is the argument
    // for scopes rather than a summary field.
    await lab['bob'].sayOnChange('why are we doing this at all?');
    await lab.syncAll();

    expect((await lab.author.read()).bundle.header.turn, ReviewTurn.yours,
        reason: 'the author was asked a question about the change and is '
            'not told it is their turn');
    expect((await lab['bob'].read()).bundle.header.waitingOn,
        contains(lab.author.name),
        reason: 'bob is not told he is waiting on the author');
  });
}
