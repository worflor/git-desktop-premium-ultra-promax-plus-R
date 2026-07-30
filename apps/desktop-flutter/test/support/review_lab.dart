// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_lab.dart — the whole review, end to end, for one person.
//
// Review is the one feature a single developer cannot exercise by using
// the app: it needs several humans on several machines disagreeing over
// the same lines, and the interesting bugs live precisely in what one
// machine can and cannot see of another. The pieces to fake that already
// existed separately — [ScratchTeam] gives a bare origin plus N real
// clones with real identities, [ReviewStore] does the ref work,
// review_scenario.dart drives a seeded two-party lifecycle — but nothing
// joined the whole chain:
//
//     refs on disk -> ReviewStore -> ReviewPaneController
//                  -> ReviewViewBundle -> the widgets a human reads
//
// The halves were each covered and the seam between them was not.
// review_pane_widget_test renders hand-authored view models
// (review_fixture.dart), and review_pane_controller_test checks data
// without ever rendering it. So the pane could be perfect on fixtures
// and wrong on everything the store actually produces — a real outdated
// anchor, a robot finding, a draft that exists only in one clone.
//
// This lab closes that seam and adds the parties. Every member is a real
// clone with its own identity, its own store, its own controller and its
// own pane. Nothing is mocked: drafts really are invisible to the other
// machines because they live in a ref that is never pushed, and a late
// joiner really does reconstruct the review from refs it fetched.
//
// FAKE ASYNC. Almost none of this needs widgets, and lab work awaited
// inside a testWidgets body HANGS rather than fails — see
// [requireRealAsync]. Write review tests as plain test(); reach for
// testWidgets only to render a pane, and put the git half inside
// tester.runAsync.
//
// DETERMINISM. Seeded RNG, a logical clock per member (each with its own
// skew, so "who wrote first" is decided by data and not by the host),
// and no wall-clock or network anywhere. A failure reproduces from its
// seed. The AI-authored content in review_corpus.dart is RECORDED, not
// generated at test time, for the same reason: agents write the words
// once, the suite replays them forever.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/clock.dart';
import 'package:git_desktop/backend/desk_pr_store.dart';
import 'package:git_desktop/backend/manifold_refs.dart';
import 'package:git_desktop/backend/review_anchor.dart';
import 'package:git_desktop/backend/review_records.dart';
import 'package:git_desktop/backend/review_store.dart';
import 'package:git_desktop/features/review/review_adapter.dart';
import 'package:git_desktop/features/review/review_pane.dart';
import 'package:git_desktop/features/review/review_pane_controller.dart';
import 'package:git_desktop/features/review/review_view_model.dart';
import 'package:git_desktop/ui/tokens.dart';

import 'scratch_repo.dart';
import 'scratch_team.dart';
import 'widget_harness.dart';

/// The desk PR a lab review hangs off is ALLOCATED, not assumed.
///
/// A review is addressed by desk id, and desk ids come from a counter in
/// the manifold namespace. Hardcoding one gave every lab the same number
/// while no desk PR existed at all — reviews the running app could not
/// navigate to, and a staged repo you could not open. [ReviewLab.deskId]
/// is whatever the real store handed out.

/// The branch under review, and what it forked from.
const String kLabHead = 'feat/lab';
const String kLabBase = 'main';

/// A clock that advances one second per read, starting from a fixed
/// instant plus a per-member skew.
///
/// Per-member skew is the point: with every machine on the same clock,
/// "whose comment is newer" would be decided by which store happened to
/// be called first, and a last-write-wins field would look correct while
/// being untested. Skew makes the ordering a property of the data.
class LabClock implements Clock {
  LabClock(this._t);
  DateTime _t;
  @override
  DateTime now() {
    _t = _t.add(const Duration(seconds: 1));
    return _t;
  }
}

/// Fail with a sentence instead of hanging forever when lab work is
/// awaited inside a [testWidgets] body.
///
/// testWidgets runs in a fake-async zone: a Timer there only fires when
/// the tester pumps, and the git layer's spawn guards ARE timers. So a
/// lab verb awaited directly inside testWidgets does not fail — it parks
/// forever, pumping nothing, printing nothing, until the harness kills
/// the run. That is the worst diagnostic in the box, and it cost a
/// ten-minute silent run to identify once.
///
/// Two lines of runtimeType sniffing convert it into an error that names
/// the fix. Test-only, so a heuristic is the right instrument: the
/// failure mode of a false positive is a loud message, and the failure
/// mode of no check at all is a dead run.
void requireRealAsync(String verb) {
  final t = Timer(Duration.zero, () {});
  final faked = t.runtimeType.toString().contains('FakeTimer');
  t.cancel();
  if (faked) {
    throw StateError(
        'lab: $verb was awaited inside a fake-async zone (testWidgets), '
        'where the git layer\'s timers never fire and this would hang '
        'silently. Wrap lab work in tester.runAsync(() async { ... }), or '
        'write it as a plain test() — most of the review lab needs no '
        'widgets at all.');
  }
}

/// One human at one machine: their clone, their store, their controller.
class LabMember {
  LabMember({
    required this.name,
    required this.repo,
    required this.store,
    required this.controller,
  });

  final String name;
  final ScratchRepo repo;
  final ReviewStore store;
  final ReviewPaneController controller;

  ReviewIdentity get identity => controller.viewer;

  /// Everything this machine can currently prove about the review, read
  /// back through the REAL controller — the same call the pane makes.
  Future<ReviewPaneData> read() async {
    requireRealAsync('$name.read()');
    final r = await controller.load();
    if (!r.ok || r.data == null) {
      throw StateError('lab: $name could not load the review: ${r.error}');
    }
    return r.data!;
  }

  /// The view models the widgets would render for this member.
  Future<ReviewViewBundle> view() async => (await read()).bundle;

  /// Anchor [line] (1-based) on [side] of the subject file.
  ///
  /// Loads first, always. Capture reads the controller's CACHED round
  /// pin, so a capture without a preceding load returns null on a
  /// perfectly healthy repo — the real pane always has fresh data
  /// behind a gutter tap, and a helper that skipped it would be testing
  /// a state the app cannot be in.
  Future<ReviewAnchor> anchorAt(int line, {String side = 'new'}) async {
    await read();
    final a = await controller.captureAt(
        path: ReviewLab.path, side: side, line: line);
    if (a == null) {
      throw StateError(
          'lab: $name could not anchor $side line $line — no round pin, '
          'or the file is unreadable from this clone');
    }
    return a;
  }

  /// Draft a new thread on [line]. Private to this machine until
  /// [publish].
  Future<void> draftOpener(int line, String body,
      {String side = 'new'}) async {
    final err = await controller.saveOpenerDraft(
        scope: LineScope(await anchorAt(line, side: side)), body: body);
    if (err != null) throw StateError('lab: $name draft failed: $err');
  }

  /// Draft a comment about the subject file as a whole.
  ///
  /// No side to pass: the controller discovers which side the path is on,
  /// so a comment on a file the change DELETED lands on the base version
  /// that still contains it rather than being born outdated.
  Future<void> draftOnFile(String body) async {
    await read();
    final scope = await controller.captureFile(path: ReviewLab.path);
    if (scope == null) {
      throw StateError('lab: $name could not scope the file (no round, or '
          'the path is on neither side)');
    }
    final err = await controller.saveOpenerDraft(scope: scope, body: body);
    if (err != null) throw StateError('lab: $name file draft failed: $err');
  }

  /// Draft a comment about the change itself.
  Future<void> draftOnChange(String body) async {
    await read();
    final scope = controller.captureReview();
    if (scope == null) {
      throw StateError('lab: $name could not scope the change (no round?)');
    }
    final err = await controller.saveOpenerDraft(scope: scope, body: body);
    if (err != null) throw StateError('lab: $name change draft failed: $err');
  }

  /// Say something about the whole change, published.
  Future<void> sayOnChange(String body, {String? verdict}) async {
    await draftOnChange(body);
    await publish(verdict: verdict);
  }

  /// Say something about the subject file, published.
  Future<void> sayOnFile(String body) async {
    await draftOnFile(body);
    await publish();
  }

  /// Draft a reply into an existing thread.
  Future<void> draftReply(String threadId, String body) async {
    await read();
    final err =
        await controller.saveReplyDraft(threadId: threadId, body: body);
    if (err != null) throw StateError('lab: $name reply failed: $err');
  }

  /// Publish this machine's draft batch (and optionally a verdict) as
  /// one turn.
  Future<void> publish({String? verdict}) async {
    await read();
    final err = await controller.publish(verdict: verdict);
    if (err != null) throw StateError('lab: $name publish failed: $err');
  }

  /// Open a thread and publish it — the common two-step, as one call.
  Future<void> say(int line, String body, {String side = 'new'}) async {
    await draftOpener(line, body, side: side);
    await publish();
  }

  Future<void> resolve(String threadId, {String how = 'done'}) async {
    await read();
    final err = await controller.resolve(threadId, how: how);
    if (err != null) throw StateError('lab: $name resolve failed: $err');
  }

  Future<void> reopen(String threadId) async {
    await read();
    final err = await controller.reopen(threadId);
    if (err != null) throw StateError('lab: $name reopen failed: $err');
  }

  /// Push this machine's review refs, then take everyone else's.
  Future<void> sync() async {
    requireRealAsync('$name.sync()');
    final r = await store.syncWithRemote();
    if (!r.ok) throw StateError('lab: $name sync failed: ${r.error}');
  }
}

/// A synthetic review team: one bare origin, N real clones, one desk PR.
class ReviewLab {
  ReviewLab._(
      this._team, this.members, this.seed, this._sourceLines, this.deskId);

  final ScratchTeam _team;
  final Map<String, LabMember> members;
  final int seed;
  final List<String> _sourceLines;

  /// The desk PR this review hangs off, as allocated by [DeskPrStore].
  final int deskId;

  /// The file every lab review argues about.
  static const String path = 'lib/subject.dart';

  LabMember operator [](String name) {
    final m = members[name];
    if (m == null) {
      throw ArgumentError.value(
          name, 'name', 'no such lab member (have: ${members.keys.join(', ')})');
    }
    return m;
  }

  /// The shared bare origin every member pushes to.
  String get originPath => _team.originPath;

  /// The author is always the first member — they own the branch.
  LabMember get author => members.values.first;

  /// Everyone who is not the author.
  Iterable<LabMember> get reviewers => members.values.skip(1);

  /// Stand up the lab: clones, a branch with real content, a desk PR's
  /// worth of divergence, and one review round pinned on it.
  ///
  /// [names] is author-first. Three is the interesting minimum: two
  /// reviewers who must not see each other's drafts is a property two
  /// parties cannot express.
  static Future<ReviewLab> create({
    List<String> names = const ['alice', 'bob', 'cara'],
    int seed = 0x1EAF,
    int lines = 40,
  }) async {
    final team = await ScratchTeam.create(memberNames: names);
    final source = [
      for (var i = 0; i < lines; i++) '  final step$i = compute($i);',
    ];

    // The author writes the base, pushes it, then diverges on a branch.
    final authorRepo = team[names.first];
    await authorRepo.writeFile(path, '${source.join('\n')}\n');
    await authorRepo.commitAll('subject: base');
    await authorRepo.gitOk(['push', '-q', 'origin', kLabBase]);
    await authorRepo.gitOk(['checkout', '-q', '-b', kLabHead]);
    final changed = [...source];
    // A real diff: edits near the top, an insertion in the middle, a
    // deletion late — enough shape that anchors have somewhere to slip.
    changed[3] = '  final step3 = compute(3) + 1; // reworked';
    changed[7] = '  final step7 = compute(7) * 2; // reworked';
    changed.insert(20, '  final inserted = compute(999);');
    changed.removeAt(30);
    await authorRepo.writeFile(path, '${changed.join('\n')}\n');
    await authorRepo.commitAll('subject: the change under review');
    await authorRepo.gitOk(['push', '-q', '-u', 'origin', kLabHead]);

    // Everyone else fetches the branch so their clone can resolve
    // anchors against the same content the author sees.
    for (final name in names.skip(1)) {
      await team[name].gitOk(['fetch', '-q', 'origin']);
      // Fast-forward their local base BEFORE branching.
      //
      // The clones are made when the origin holds only the bootstrap
      // commit, so a reviewer's local `main` predates the subject file
      // entirely. Anything resolved against the merge base then points
      // at a tree that never contained it — old-side anchors, and the
      // side probe for a file the change DELETED, which found the file
      // on neither side and refused a comment that should have worked.
      // A real reviewer's base tracks the remote; the lab has to as well
      // or it exercises a repository shape nobody has.
      // --ff-only on the checked-out branch: `branch -f` refuses to
      // move a branch a worktree is sitting on, and the clone is on it.
      await team[name].gitOk(['merge', '-q', '--ff-only', 'origin/$kLabBase']);
      await team[name].gitOk(['checkout', '-q', '-b', kLabHead,
        'origin/$kLabHead']);
    }

    // The desk PR the review hangs off, opened by the author through the
    // real store so its id comes from the real counter and the running
    // app can actually find the branch this review belongs to.
    final authorRefs = ManifoldRefs(
      repoPath: authorRepo.dir.path,
      authorName: names.first,
      authorEmail: ScratchTeam.emailFor(names.first),
    );
    final opened = await DeskPrStore(authorRefs).create(
      branch: kLabHead,
      title: 'the change under review',
      body: 'Opened by the review lab.',
      baseRef: kLabBase,
      authorIdentity: names.first,
    );
    if (!opened.ok || opened.data == null) {
      throw StateError('lab: could not open the desk PR: ${opened.error}');
    }
    final deskId = opened.data!.deskId;

    final members = <String, LabMember>{};
    var skew = 0;
    for (final name in names) {
      final repo = team[name];
      final clock = LabClock(DateTime.utc(2026, 8, 1, 9).add(
        Duration(seconds: skew),
      ));
      // The identity key is the clone's REAL git email, because that is
      // where the app gets it: a lab that invented its own key would
      // exercise a signing identity no running Manifold can produce.
      final email = ScratchTeam.emailFor(name);
      final refs = ManifoldRefs(
        repoPath: repo.dir.path,
        authorName: name,
        authorEmail: email,
      );
      members[name] = LabMember(
        name: name,
        repo: repo,
        store: ReviewStore(refs, clock: clock),
        controller: ReviewPaneController(
          repoPath: repo.dir.path,
          deskId: deskId,
          headBranch: kLabHead,
          baseRef: kLabBase,
          authorDisplay: names.first,
          viewer: ReviewIdentity(name, key: email),
          refs: refs,
          clock: clock,
        ),
      );
      skew += 17;
    }

    final lab = ReviewLab._(team, members, seed, changed, deskId);
    // One round, cut by the author, so every anchor has a pin to hang
    // off and reviewers have something to be "since last look" against.
    final cut = await lab.author.controller.ensureRound();
    if (!cut.ok) {
      throw StateError('lab: could not cut round 1: ${cut.error}');
    }
    // Push the desk PR and the round, then let everyone take them: a
    // reviewer whose clone has no desk PR is not a reviewer yet.
    await lab.author.sync();
    for (final r in lab.reviewers) {
      await r.sync();
    }
    return lab;
  }

  /// The content at 1-based [line] of the branch version — what a
  /// comment anchored there should still be pointing at. One-based to
  /// match the anchors and the gutter, so a test never has to convert.
  String lineAt(int line) => _sourceLines[line - 1];

  /// The subject file as it stands on [who]'s disk right now, read back
  /// rather than remembered: an anchor assertion has to be checked
  /// against the bytes git actually holds, not against the lab's own
  /// idea of what it wrote.
  Future<List<String>> subjectLines([LabMember? who]) async {
    final m = who ?? author;
    final raw = await File('${m.repo.dir.path}/$path').readAsString();
    final lines = raw.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return lines;
  }

  /// The author edits the file again and commits, so anchors have to
  /// survive real movement rather than a synthetic re-write.
  Future<void> authorEdits({required int insertAt, int count = 1}) async {
    for (var i = 0; i < count; i++) {
      _sourceLines.insert(insertAt, '  // author inserted $i');
    }
    await author.repo.writeFile(path, '${_sourceLines.join('\n')}\n');
    await author.repo.commitAll('subject: more work');
    await author.repo.gitOk(['push', '-q', 'origin', kLabHead]);
    for (final r in reviewers) {
      await r.repo.gitOk(['fetch', '-q', 'origin']);
      await r.repo.gitOk(['reset', '-q', '--hard', 'origin/$kLabHead']);
    }
  }

  /// Empty the stored attention set, so the derived fold underneath is
  /// the thing being read.
  ///
  /// The stored set WINS whenever it has been maintained, and every real
  /// verb maintains it — which makes the fold reachable in exactly one
  /// way: everyone it names steps out. That is not a contrivance, it is
  /// the "not blocking on me" button pressed by each person it applies
  /// to, and the fold has to agree with reality afterwards or the button
  /// hands the review to nobody.
  Future<void> clearAttention() async {
    for (final m in members.values) {
      final data = await m.read();
      if (!(data.state?.attentionOn.contains(m.name) ?? false)) continue;
      final err = await m.controller.stepOutOfAttention();
      if (err != null) {
        throw StateError('lab: ${m.name} could not step out: $err');
      }
    }
    await syncAll();
  }

  /// Cut a new round on the author's clone (after [authorEdits] moved
  /// the head), which is what "new code landed" means to the review.
  Future<void> cutRound() async {
    await author.read();
    final r = await author.controller.ensureRound();
    if (!r.ok) throw StateError('lab: could not cut a round: ${r.error}');
  }

  /// The author removes [count] lines from the subject file and pushes,
  /// adding none — the diff shape that is indistinguishable from a file
  /// deletion if you are reading line counts instead of asking git.
  Future<void> authorDeletesLines({int count = 3}) async {
    _sourceLines.removeRange(0, count);
    await author.repo.writeFile(
        path, '${_sourceLines.join('\n')}\n');
    await author.repo.commitAll('subject: fewer lines');
    await author.repo.gitOk(['push', '-q', 'origin', kLabHead]);
    for (final r in reviewers) {
      await r.repo.gitOk(['fetch', '-q', 'origin']);
      await r.repo.gitOk(['reset', '-q', '--hard', 'origin/$kLabHead']);
    }
  }

  /// The author reverts the subject file to its BASE content and pushes.
  ///
  /// The file still exists on both sides afterwards and is no longer in
  /// the change — the case that separates "is this path in the tree" from
  /// "is this path in this diff", which a file scope's freshness depends
  /// on getting right.
  Future<void> revertSubject() async {
    // `checkout <base> -- <path>` rather than reading the blob and
    // writing it back: the scratch helper TRIMS command output, so a
    // round trip through it silently drops the trailing newline and the
    // file stays in the diff by one line — which is a perfectly good way
    // to write a test that proves nothing.
    await author.repo.gitOk(['checkout', kLabBase, '--', path]);
    await author.repo.commitAll('subject: reverted out of the change');
    await author.repo.gitOk(['push', '-q', 'origin', kLabHead]);
    for (final r in reviewers) {
      await r.repo.gitOk(['fetch', '-q', 'origin']);
      await r.repo.gitOk(['reset', '-q', '--hard', 'origin/$kLabHead']);
    }
  }

  /// The author removes the subject file entirely and pushes.
  ///
  /// What makes a FILE scope's outdated rung reachable: the claim "this
  /// file should not be here" has a subject right up until the file
  /// stops being here.
  Future<void> deleteSubject() async {
    await author.repo.deleteFile(path);
    await author.repo.commitAll('subject: dropped');
    await author.repo.gitOk(['push', '-q', 'origin', kLabHead]);
    for (final r in reviewers) {
      await r.repo.gitOk(['fetch', '-q', 'origin']);
      await r.repo.gitOk(['reset', '-q', '--hard', 'origin/$kLabHead']);
    }
  }

  /// Everyone pushes, then everyone pulls, twice — the second pass is
  /// what lets a machine see what the first pass published.
  Future<void> syncAll() async {
    for (final m in members.values) {
      await m.sync();
    }
    for (final m in members.values) {
      await m.sync();
    }
  }

  /// A machine that clones AFTER the review happened and has to rebuild
  /// it from refs alone. The cold reader: no local state, no drafts, no
  /// memory of the conversation — only what the remote carries.
  ///
  /// This is the check that the review really does live in git rather
  /// than in the process that wrote it.
  Future<LabMember> lateJoiner({String name = 'dana'}) async {
    final repo = await ScratchRepo.cloneLocal(
      sourceUrl: _team.originPath,
      name: 'team_$name',
      userName: name,
      userEmail: ScratchTeam.emailFor(name),
    );
    await repo.gitOk(['checkout', '-q', '-b', kLabHead, 'origin/$kLabHead']);
    final refs = ManifoldRefs(
      repoPath: repo.dir.path,
      authorName: name,
      authorEmail: ScratchTeam.emailFor(name),
    );
    final clock = LabClock(DateTime.utc(2026, 8, 1, 12));
    final member = LabMember(
      name: name,
      repo: repo,
      store: ReviewStore(refs, clock: clock),
      controller: ReviewPaneController(
        repoPath: repo.dir.path,
        deskId: deskId,
        headBranch: kLabHead,
        baseRef: kLabBase,
        authorDisplay: author.name,
        viewer: ReviewIdentity(name, key: ScratchTeam.emailFor(name)),
        refs: refs,
        clock: clock,
      ),
    );
    members[name] = member;
    await member.sync();
    return member;
  }

  /// Deterministic dice for scenario choices.
  Random rng() => Random(seed);

  Future<void> dispose() async {
    for (final m in members.values) {
      if (!_team.members.containsValue(m.repo)) {
        await m.repo.dispose();
      }
    }
    await _team.dispose();
  }
}

/// Render [member]'s pane from their REAL refs and settle it.
///
/// The assertion this enables is the one the suite was missing: not
/// "the widgets can render a bundle we wrote by hand", but "what this
/// human sees is what their machine can prove".
Future<void> pumpLabPane(
  WidgetTester tester,
  LabMember member, {
  Size size = const Size(900, 1600),
}) async {
  // Through runAsync, because the read is real git I/O and the enclosing
  // testWidgets body is fake-async. See [requireRealAsync].
  final data = await tester.runAsync(member.read);
  if (data == null) {
    throw StateError('lab: runAsync gave up reading ${member.name}\'s review');
  }
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await pumpHarness(
    tester,
    Scaffold(
      backgroundColor: AppTokens.fromId(AppThemeId.petrichor).bg1,
      body: SingleChildScrollView(
        child: ReviewPane(
          bundle: data.bundle,
          strings: const ReviewStrings(),
          // The member's own logical clock, so "3h ago" is a function of
          // the review's data and not of when the suite happened to run.
          now: DateTime.utc(2026, 8, 1, 18),
          draftCount: data.draftCount,
          onSaveReply: (_, __) async => true,
          onResolve: (_, __) async {},
          onPublish: (_) async {},
          onDiscardDrafts: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every glyph in the rendered tree, as one haystack — what the human
/// can actually read.
///
/// [RichText] rather than [Text]: comment bodies render through
/// MarkdownBody, so a `Text.data` sweep would miss the review's entire
/// content and quietly make every "is it on screen" assertion vacuous
/// — including the negative ones, which would then pass for the wrong
/// reason forever.
String visibleText(WidgetTester tester) => [
      for (final r in tester.widgetList<RichText>(find.byType(RichText)))
        r.text.toPlainText(
            includeSemanticsLabels: false, includePlaceholders: false),
    ].join('\n');
