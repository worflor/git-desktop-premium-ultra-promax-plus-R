// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_scenario.dart — the seeded review-lifecycle corpus engine.
//
// Drives the REAL ReviewStore on a REAL two-clone ScratchTeam through a
// randomized but reproducible review: the author edits and commits,
// rounds get cut, the reviewer drafts and publishes batches (with
// verdicts), replies land from both sides, threads resolve, the robot
// files findings, and syncs interleave so genuine divergence happens
// constantly. A pure expectation model rides along, and every SETTLE
// checkpoint asserts the invariants that make the feature "just work":
//
//  I1  CONVERGENCE — both clones' state docs are byte-identical.
//  I2  NO LOSS / NO DUPES — thread count and every thread's comment
//      key-set equal the model exactly.
//  I3  VERDICTS — every published verdict survives, none duplicated.
//  I4  DRAFT PRIVACY — the origin never carries refs/manifold-local.
//  I5  TURN AGREEMENT — both clones derive the same turn for the same
//      viewer.
//  I6  ANCHOR SOUNDNESS — every thread anchor that resolves against
//      the author's current file points at a line whose content
//      matches the anchored content (the ladder never lies).
//  I7  RESOLUTION PROVENANCE — resolved threads carry who and when.
//
// Failures throw with the seed and the full op log — a one-line repro.

import 'dart:math';

import 'package:git_desktop/backend/clock.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/manifold_refs.dart';
import 'package:git_desktop/backend/review_anchor.dart';
import 'package:git_desktop/backend/review_records.dart';
import 'package:git_desktop/backend/review_store.dart';

import 'scratch_repo.dart';
import 'scratch_team.dart';

const int kScenarioDeskId = 7;

class _LogicalClock implements Clock {
  DateTime _t;
  _LogicalClock(this._t);
  @override
  DateTime now() {
    _t = _t.add(const Duration(seconds: 1));
    return _t;
  }
}

class _CommentKey {
  final String author;
  final String at;
  final String body;
  const _CommentKey(this.author, this.at, this.body);
  @override
  bool operator ==(Object o) =>
      o is _CommentKey && o.author == author && o.at == at && o.body == body;
  @override
  int get hashCode => Object.hash(author, at, body);
  @override
  String toString() => '($author @ $at: $body)';
}

/// Model of one expected thread: the opener key identifies it before
/// the store-minted id is learned.
class _ThreadModel {
  final _CommentKey opener;
  String? id; // learned after first observation in a synced state
  final Set<_CommentKey> comments;
  _ThreadModel(this.opener) : comments = {opener};
}

class ReviewScenarioResult {
  final int seed;
  final List<String> log;
  final ReviewState finalState;

  /// Author-side file content at the end (for anchor resolution in
  /// downstream consumers, e.g. the real-data preview).
  final Map<String, List<String>> files;

  const ReviewScenarioResult({
    required this.seed,
    required this.log,
    required this.finalState,
    required this.files,
  });
}

/// Run one seeded scenario. Throws [StateError] with the op log on any
/// invariant violation. [opCount] is the number of generated ops (the
/// engine adds settles and a final settle on top).
Future<ReviewScenarioResult> runReviewScenario({
  required int seed,
  int opCount = 22,
}) async {
  final rng = Random(seed);
  final log = <String>[];
  final team = await ScratchTeam.create();
  try {
    final alice = team['alice']; // author
    final bob = team['bob']; // reviewer

    ReviewStore storeFor(ScratchRepo r, String who, int skewSec) =>
        ReviewStore(
          ManifoldRefs(
            repoPath: r.dir.path,
            authorName: who,
            authorEmail: '$who@manifold.local',
          ),
          clock: _LogicalClock(
              DateTime.utc(2026, 7, 22, 12).add(Duration(seconds: skewSec))),
        );

    final stores = {
      'alice': storeFor(alice, 'alice', 0),
      'bob': storeFor(bob, 'bob', 30),
    };
    const author = ReviewIdentity('alice');
    const reviewer = ReviewIdentity('bob');
    const robot = ReviewIdentity('varrho');

    // Event timestamps: engine-minted, unique, monotone per machine.
    var tick = 0;
    DateTime nextAt() =>
        DateTime.utc(2026, 7, 22, 9).add(Duration(seconds: 37 * ++tick));

    // The reviewed file, evolving in memory and committed on alice.
    const path = 'src/main.dart';
    var lines = <String>[
      'import "dart:async";',
      '',
      'Future<void> main() async {',
      '  final engine = Engine();',
      '  await engine.start();',
      '  engine.report();',
      '}',
      '',
      'class Engine {',
      '  Future<void> start() async {}',
      '  void report() {}',
      '}',
    ];
    Future<void> commitFile(String msg) async {
      await alice.writeFile(path, '${lines.join('\n')}\n');
      await alice.commitAll(msg);
    }

    await commitFile('seed file');
    var editSerial = 0;

    // Expectation model.
    final threads = <_ThreadModel>[];
    final verdictKeys = <_CommentKey>{};
    var pendingDraftOpeners = <_CommentKey>[]; // bob's unpublished
    var settledSinceMutation = false;

    Future<T> must<T>(String what, Future<GitResult<T>> f) async {
      final r = await f;
      if (!r.ok) {
        throw StateError(
            'seed $seed: $what failed: ${r.error}\nlog:\n${log.join('\n')}');
      }
      return r.data as T;
    }

    void check(bool cond, String why) {
      if (!cond) {
        throw StateError(
            'seed $seed INVARIANT: $why\nlog:\n${log.join('\n')}');
      }
    }

    Future<ReviewState?> readOn(String who) async =>
        must('read($who)', stores[who]!.read(kScenarioDeskId));

    // Learn store-minted thread ids by matching opener keys.
    void learnIds(ReviewState s) {
      for (final t in s.threads) {
        if (t.comments.isEmpty) continue;
        final c = t.comments.first;
        final key = _CommentKey(
            c.author.display, c.at.toIso8601String(), c.body);
        for (final m in threads) {
          if (m.opener == key) m.id ??= t.id;
        }
      }
    }

    Future<void> settle() async {
      log.add('settle');
      for (var i = 0; i < 2; i++) {
        await must('sync(alice)', stores['alice']!.syncWithRemote());
        await must('sync(bob)', stores['bob']!.syncWithRemote());
      }
      final a = await readOn('alice');
      final b = await readOn('bob');
      if (a == null && b == null && threads.isEmpty) return;
      check(a != null && b != null, 'state missing after settle');
      // I1 convergence.
      check(a!.toBlob() == b!.toBlob(), 'clones diverged after settle');
      learnIds(a);
      // I2 no loss / no dupes.
      check(a.threads.length == threads.length,
          'thread count ${a.threads.length} != model ${threads.length}');
      for (final m in threads) {
        check(m.id != null, 'model thread never appeared: ${m.opener}');
        final actual = a.threads.where((t) => t.id == m.id).toList();
        check(actual.length == 1, 'thread ${m.id} count ${actual.length}');
        final keys = actual.single.comments
            .map((c) => _CommentKey(
                c.author.display, c.at.toIso8601String(), c.body))
            .toSet();
        check(keys.length == actual.single.comments.length,
            'duplicate comments inside thread ${m.id}');
        check(keys.containsAll(m.comments) && m.comments.containsAll(keys),
            'thread ${m.id} comments != model '
            '(missing ${m.comments.difference(keys)}, '
            'extra ${keys.difference(m.comments)})');
      }
      // I3 verdicts.
      final actualVerdicts = a.verdicts
          .map((v) =>
              _CommentKey(v.by.display, v.at.toIso8601String(), v.verdict))
          .toSet();
      check(actualVerdicts.length == a.verdicts.length, 'duplicate verdicts');
      check(
          actualVerdicts.containsAll(verdictKeys) &&
              verdictKeys.containsAll(actualVerdicts),
          'verdicts != model');
      // I4 draft privacy.
      final onOrigin = await bob.gitOk(['ls-remote', 'origin']);
      check(!onOrigin.contains('manifold-local'),
          'local namespace leaked to origin');
      // I5 turn agreement.
      for (final viewer in ['alice', 'bob']) {
        final ta = deriveTurn(a,
            authorDisplay: 'alice', viewerDisplay: viewer);
        final tb = deriveTurn(b,
            authorDisplay: 'alice', viewerDisplay: viewer);
        check(ta.yourTurn == tb.yourTurn && ta.waitingOn == tb.waitingOn,
            'turn fold disagrees for $viewer');
      }
      // I6 anchor soundness against the author's current file.
      //
      // LINE scopes only, stated rather than assumed. A file or
      // whole-change thread pins no line and has nothing to resolve —
      // its freshness is membership in the change, which is a different
      // question checked elsewhere. This loop used to reach for every
      // thread's anchor unconditionally, which was correct exactly while
      // a line was the only thing a thread could be about.
      for (final t in a.threads) {
        final anchor = t.lineAnchor;
        if (anchor == null || anchor.path != path) continue;
        final res = resolveAnchor(anchor, lines);
        if (res.status != AnchorStatus.outdated) {
          final actual = lines[res.line! - 1];
          check(
              resolveAnchor(anchor, [actual]).status !=
                  AnchorStatus.outdated,
              'anchor resolved to non-matching content: "$actual" for '
              '"${anchor.excerpt}"');
        }
      }
      // I7 provenance.
      for (final t in a.threads) {
        if (t.state != 'unresolved') {
          check(t.resolvedBy != null && t.resolvedAt != null,
              'resolved thread ${t.id} lacks provenance');
        }
      }
      settledSinceMutation = true;
    }

    // Threads present on a machine (learned id AND synced there).
    Future<List<String>> knownThreadIds(String who) async {
      final s = await readOn(who);
      if (s == null) return const [];
      final modelIds = threads.map((m) => m.id).whereType<String>().toSet();
      return s.threads.map((t) => t.id).where(modelIds.contains).toList();
    }

    // ─── Ops ─────────────────────────────────────────────────────────
    Future<void> opAuthorEdit() async {
      final kind = rng.nextInt(3);
      final i = rng.nextInt(lines.length);
      editSerial++;
      switch (kind) {
        case 0:
          lines = [...lines]..insert(i, '  // note $editSerial');
          log.add('edit: insert@$i');
        case 1:
          lines = [...lines]..[i] = '${lines[i]} // touched $editSerial';
          log.add('edit: modify@$i');
        default:
          if (lines.length > 4) {
            lines = [...lines]..removeAt(i);
            log.add('edit: delete@$i');
          } else {
            lines = [...lines]..insert(i, '  // pad $editSerial');
            log.add('edit: insert@$i (short file)');
          }
      }
      await commitFile('edit $editSerial');
      settledSinceMutation = false;
    }

    Future<void> opCutRound() async {
      log.add('cutRound');
      await must(
          'cutRound',
          stores['alice']!.cutRoundIfMoved(
              deskId: kScenarioDeskId,
              branch: 'main',
              by: author,
              authorDisplay: author.display));
      settledSinceMutation = false;
    }

    /// A subject for a new thread — a line most of the time, and
    /// sometimes the file or the change itself.
    ///
    /// The scenario used to open line threads exclusively, which meant
    /// every invariant it proves (convergence, no-loss, turn agreement,
    /// resolution provenance) was proven for ONE of the three kinds of
    /// thread the format now carries. The seeded mix keeps the same
    /// determinism while letting a lifecycle actually contain the other
    /// two.
    ReviewScope randomScope(int li) {
      switch (rng.nextInt(6)) {
        case 0:
          return WholeScope(round: 1, commit: 'c' * 40);
        case 1:
          return FileScope(
              path: path, side: 'new', round: 1, commit: 'c' * 40);
        default:
          return LineScope(captureAnchor(
              lines: lines,
              lineIndex: li,
              round: 1,
              commit: 'c' * 40,
              path: path));
      }
    }

    Future<void> opDraft() async {
      final li = rng.nextInt(lines.length);
      final at = nextAt();
      final body = 'draft q${threads.length + pendingDraftOpeners.length}';
      log.add('draft@line$li');
      await must(
          'saveDraft',
          stores['bob']!.saveDraft(
              kScenarioDeskId,
              ReviewDraftEntry(
                threadId: '',
                scope: randomScope(li),
                body: body,
                at: at,
              )));
      pendingDraftOpeners
          .add(_CommentKey('bob', at.toIso8601String(), body));
      settledSinceMutation = false;
    }

    Future<void> opPublish() async {
      if (pendingDraftOpeners.isEmpty) return opDraft();
      final withVerdict = rng.nextInt(3) == 0;
      log.add('publish${withVerdict ? '+verdict' : ''}');
      final r = await must(
          'publish',
          stores['bob']!.publish(
            deskId: kScenarioDeskId,
            author: reviewer,
            verdict: withVerdict ? 'CHANGES_REQUESTED' : null,
          ));
      for (final k in pendingDraftOpeners) {
        threads.add(_ThreadModel(k));
      }
      pendingDraftOpeners = [];
      if (withVerdict) {
        // The store minted the verdict timestamp; learn it from state.
        final v = r.verdicts.last;
        verdictKeys.add(
            _CommentKey(v.by.display, v.at.toIso8601String(), v.verdict));
      }
      settledSinceMutation = false;
    }

    Future<void> opRobotFinding() async {
      final li = rng.nextInt(lines.length);
      final at = nextAt();
      final body = 'finding f${threads.length}';
      log.add('robot@line$li');
      await must(
          'openThread(robot)',
          stores['bob']!.openThread(
            deskId: kScenarioDeskId,
            scope: randomScope(li),
            opener: ReviewComment(
                author: robot, at: at, body: body, kind: 'robot'),
          ));
      threads.add(
          _ThreadModel(_CommentKey('varrho', at.toIso8601String(), body)));
      settledSinceMutation = false;
    }

    Future<void> opReply(String who) async {
      final known = await knownThreadIds(who);
      if (known.isEmpty) return;
      final id = known[rng.nextInt(known.length)];
      final at = nextAt();
      final body = 'reply r$tick by $who';
      log.add('reply($who)→$id');
      await must(
          'addComment($who)',
          stores[who]!.addComment(
            deskId: kScenarioDeskId,
            threadId: id,
            comment: ReviewComment(
                author: who == 'alice' ? author : reviewer,
                at: at,
                body: body),
          ));
      threads
          .firstWhere((m) => m.id == id)
          .comments
          .add(_CommentKey(who, at.toIso8601String(), body));
      settledSinceMutation = false;
    }

    Future<void> opResolve() async {
      // Scalar mutation: only from a fully settled state, so the model
      // never has to replicate concurrent-LWW semantics (comments are
      // the concurrency stress; resolution is serialized by design —
      // matching the real UX, where you resolve what you can see).
      if (!settledSinceMutation) await settle();
      final known = await knownThreadIds('alice');
      final a = await readOn('alice');
      if (a == null) return;
      final open = a.threads
          .where((t) => t.state == 'unresolved' && known.contains(t.id))
          .toList();
      if (open.isEmpty) return;
      final id = open[rng.nextInt(open.length)].id;
      final how = rng.nextBool() ? 'done' : 'acked';
      log.add('resolve($how)→$id');
      await must(
          'resolve',
          stores['alice']!.resolveThread(
              deskId: kScenarioDeskId,
              threadId: id,
              by: author,
              how: how));
      settledSinceMutation = false;
    }

    // ─── The run ─────────────────────────────────────────────────────
    // Open with one reviewer thread so early ops have something to hit.
    await opDraft();
    await opPublish();
    await settle();

    for (var i = 0; i < opCount; i++) {
      final roll = rng.nextInt(100);
      if (roll < 18) {
        await opAuthorEdit();
      } else if (roll < 28) {
        await opCutRound();
      } else if (roll < 42) {
        await opDraft();
      } else if (roll < 54) {
        await opPublish();
      } else if (roll < 62) {
        await opRobotFinding();
      } else if (roll < 76) {
        await opReply(rng.nextBool() ? 'alice' : 'bob');
      } else if (roll < 84) {
        await opResolve();
      } else {
        await settle();
      }
    }
    // Publish any dangling drafts so the model closes, then settle.
    if (pendingDraftOpeners.isNotEmpty) await opPublish();
    await settle();

    final finalState = (await readOn('alice'))!;
    return ReviewScenarioResult(
      seed: seed,
      log: log,
      finalState: finalState,
      files: {path: lines},
    );
  } finally {
    await team.dispose();
  }
}
