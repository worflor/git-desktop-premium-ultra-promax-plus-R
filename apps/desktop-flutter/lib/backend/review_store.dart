// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_store.dart — read/write review objects through git plumbing.
//
// A desk PR's review is a facet of the desk PR, keyed by its deskId:
//  * `refs/manifold/review/<deskId>/state` — the mutable state doc
//    (one review.json blob per orphan commit, CAS-mutated exactly like
//    the desk PR store, reconciled across machines by the declared
//    schema in review_records.dart);
//  * `refs/manifold/review/<deskId>/round/<n>` — immutable pins on
//    REAL branch commits: the snapshot chain. Cutting a round is
//    create-only (zero-OID CAS), never a move;
//  * `refs/manifold-local/review/<deskId>/drafts` — the viewer's
//    unpublished comments. The local namespace is excluded from every
//    refspec by construction; [publish] is the only crossing point,
//    and it is state-first then draft-delete, so a crash between the
//    two REPLAYS safely (publishing is idempotent — comment identity
//    dedupes on the (author, at, body) union key).
//
// Time comes from the Clock seam; randomness (thread-id suffixes) is
// injectable. No settings reads, no UI types.

import 'dart:convert';

import 'package:meta/meta.dart';

import 'clock.dart';
import 'git.dart' as git;
import 'git_result.dart';
import 'manifold_refs.dart';
import 'review_anchor.dart';
import 'review_records.dart';

/// One unpublished draft entry. `threadId` empty → opens a new thread
/// at publish; non-empty → a reply to that thread.
class ReviewDraftEntry {
  final String threadId;
  final ReviewAnchor? anchor;
  final String body;
  final DateTime at;

  const ReviewDraftEntry({
    required this.threadId,
    required this.anchor,
    required this.body,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'threadId': threadId,
        if (anchor != null) 'anchor': anchor!.toJson(),
        'body': body,
        'at': isoUtc(at),
      };

  factory ReviewDraftEntry.fromJson(Map<String, dynamic> j) =>
      ReviewDraftEntry(
        threadId: j['threadId'] as String? ?? '',
        anchor: j['anchor'] is Map
            ? ReviewAnchor.fromJson((j['anchor'] as Map).cast<String, dynamic>())
            : null,
        body: j['body'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class ReviewStore {
  static const String _stateFilename = 'review.json';
  static const String _draftsFilename = 'drafts.json';

  final ManifoldRefs refs;
  final Clock clock;

  ReviewStore(this.refs, {this.clock = const SystemClock()});

  static LiveManifoldRef stateRefFor(int deskId) =>
      LiveManifoldRef.reviewState(deskId);

  // ─── State doc ───────────────────────────────────────────────────

  /// Read the state doc; ok(null) when the review doesn't exist yet.
  @useResult
  Future<GitResult<ReviewState?>> read(int deskId) async {
    final blob =
        await refs.readRefBlob(stateRefFor(deskId), _stateFilename);
    if (!blob.ok) return GitResult.err(blob.error ?? 'readRefBlob failed');
    if (blob.data == null) return const GitResult.ok(null);
    try {
      return GitResult.ok(ReviewState.fromBlob(blob.data!));
    } catch (e) {
      return GitResult.err('corrupt review.json: $e');
    }
  }

  /// Read-transform-commit with CAS retry, creating the doc on first
  /// touch. Mirrors the desk store's `_mutate` (each attempt re-reads
  /// the tip and re-applies [transform] onto the winner) with one
  /// extension: a missing ref starts from [ReviewState.fresh] and
  /// lands via create-CAS, so two first-touchers can't clobber each
  /// other either.
  Future<GitResult<ReviewState>> _mutate(
    int deskId, {
    required ReviewState Function(ReviewState current) transform,
    required String Function(ReviewState next) message,
    int maxAttempts = 5,
  }) async {
    final ref = stateRefFor(deskId);
    String? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final tip = await refs.resolveRef(ref);
      if (!tip.ok) return GitResult.err(tip.error ?? 'resolveRef failed');
      ReviewState current;
      if (tip.data == null) {
        current = ReviewState.fresh(deskId, clock.now());
      } else {
        final blob = await refs.readRefBlob(tip.data!, _stateFilename);
        if (!blob.ok) {
          return GitResult.err(blob.error ?? 'readRefBlob failed');
        }
        if (blob.data == null) {
          return const GitResult.err(
              'review ref exists but has no state blob');
        }
        try {
          current = ReviewState.fromBlob(blob.data!);
        } catch (e) {
          return GitResult.err('corrupt review.json: $e');
        }
      }
      // Unknown FIELDS round-trip (the extras plumbing); an unknown
      // SCHEMA does not get mutated at all — a newer writer's semantics
      // are not ours to rewrite, extras or no extras.
      if (current.schemaVersion > kReviewSchemaVersion) {
        return GitResult.err(
            'review state is schemaVersion ${current.schemaVersion}; this '
            'client understands $kReviewSchemaVersion — refusing to '
            'mutate a newer document (reading is fine; update Manifold '
            'to write)');
      }
      final next = transform(current);
      final blobR = await refs.writeBlob(next.toBlob());
      if (!blobR.ok) return GitResult.err(blobR.error ?? 'writeBlob failed');
      final treeR = await refs.mkTree({_stateFilename: blobR.data!});
      if (!treeR.ok) return GitResult.err(treeR.error ?? 'mkTree failed');
      final commitR = await refs.commitTree(
        treeSha: treeR.data!,
        parentSha: tip.data,
        message: message(next),
      );
      if (!commitR.ok) {
        return GitResult.err(commitR.error ?? 'commitTree failed');
      }
      final updR = tip.data == null
          ? await refs.createRef(ref: ref, newSha: commitR.data!)
          : await refs.updateRef(
              ref: ref, newSha: commitR.data!, oldSha: tip.data);
      if (updR.ok) return GitResult.ok(next);
      lastError = updR.error;
      await Future<void>.delayed(Duration(milliseconds: 5 + attempt * 5));
    }
    return GitResult.err(
        lastError ?? 'updateRef failed after retries');
  }

  /// Desk ids that actually HAVE a review, from ONE ref listing.
  ///
  /// The gate every whole-repo sweep needs: reviews are far rarer than
  /// desks, so anything that would otherwise read state per desk (turn
  /// chips, post-sync round hygiene) asks this first and then touches
  /// only the desks it names. A repo with fifty desks and no reviews
  /// costs one spawn instead of fifty.
  ///
  /// The pattern selects state docs SERVER-SIDE (`.../*/state`) rather
  /// than listing the namespace and filtering here: round pins are the
  /// bulk of it — one ref per round, forever — so a plain prefix would
  /// make this scale with review AGE instead of review count.
  ///
  /// That is a COST choice only. Correctness rests on the exact-shape
  /// classifier below, which excludes pins whatever the listing returns,
  /// so the two forms are observationally identical and no output test
  /// can distinguish them. What the glob DOES rest on — that
  /// for-each-ref matches without FNM_PATHNAME, so `*` spans the id
  /// segment and a pin never matches `/state` — is pinned against the
  /// real binary by review_store_test R9.
  @useResult
  Future<GitResult<Set<int>>> listReviewedDeskIds() async {
    final listed =
        await refs.listRefs('${ManifoldNs.reviewPrefix}*/state');
    if (!listed.ok) return GitResult.err(listed.error ?? 'listRefs failed');
    final out = <int>{};
    for (final ref in listed.data!.keys) {
      // Exact-shape classifier, not a substring sniff: a foreign
      // `review/x/state/extra` must not be mistaken for a desk id.
      if (!ManifoldNs.isReviewStateRef(ref)) continue;
      final tail = ref.substring(ManifoldNs.reviewPrefix.length);
      final id = int.tryParse(tail.substring(0, tail.indexOf('/')));
      if (id != null) out.add(id);
    }
    return GitResult.ok(out);
  }

  // ─── Rounds ──────────────────────────────────────────────────────

  /// Cut a new round when [branch]'s head moved past the latest
  /// recorded round. Pin ref first (reachability before bookkeeping —
  /// a crash between the two leaves an orphan pin the next cut
  /// adopts), then record the metadata. Returns the new round's info,
  /// or ok(null) when the head hasn't moved.
  @useResult
  Future<GitResult<ReviewRoundInfo?>> cutRoundIfMoved({
    required int deskId,
    required String branch,
    required ReviewIdentity by,
    int maxAttempts = 5,
  }) async {
    final headR = await git.runGit(refs.repoPath,
        ['rev-parse', '--verify', '--quiet', '$branch^{commit}']);
    if (headR.exitCode != 0) {
      return GitResult.err('cannot resolve $branch');
    }
    final head = (headR.stdout as String).trim();
    if (head.isEmpty) return GitResult.err('cannot resolve $branch');

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final stateR = await read(deskId);
      if (!stateR.ok) return GitResult.err(stateR.error ?? 'read failed');
      final state = stateR.data;
      final latest = state?.latestRound;
      if (latest != null && latest.commit == head) {
        return const GitResult.ok(null);
      }

      // The round number must advance past EVERY existing pin, not
      // just the state doc's latest: an orphan pin (crashed cut, or a
      // peer's pin that synced before its metadata) would otherwise
      // collide on the same number every attempt and permanently block
      // cuts for this desk (caught by the manifold review — the old
      // `continue` re-derived the identical n from unchanged state).
      final pinsR = await refs
          .listRefs('${ManifoldNs.reviewPrefix}$deskId/round/');
      if (!pinsR.ok) return GitResult.err(pinsR.error ?? 'listRefs failed');
      var maxPinned = 0;
      int? headPinN;
      pinsR.data!.forEach((ref, sha) {
        final tailN =
            int.tryParse(ref.substring(ref.lastIndexOf('/') + 1)) ?? 0;
        if (tailN > maxPinned) maxPinned = tailN;
        if (sha == head) headPinN = tailN;
      });

      final recordedNs = {
        for (final r in state?.rounds ?? const <ReviewRoundInfo>[]) r.n
      };
      final int n;
      if (headPinN != null && !recordedNs.contains(headPinN)) {
        // An existing pin already holds this head (its cut crashed
        // between pin and metadata, or arrived by sync): ADOPT it —
        // record the bookkeeping under its number instead of minting a
        // duplicate pin of the same commit.
        n = headPinN!;
      } else {
        n = (latest?.n ?? 0) > maxPinned ? latest!.n + 1 : maxPinned + 1;
        final pin = LiveManifoldRef.reviewRound(deskId, n);
        final created =
            await refs.createRef(ref: pin, newSha: CommitOid(head));
        if (!created.ok) {
          // A peer claimed this number between our scan and our CAS —
          // the next attempt rescans and advances past it.
          continue;
        }
      }

      final changeId = await git.changeIdOfCommit(refs.repoPath, head);
      final info = ReviewRoundInfo(
        n: n,
        commit: head,
        cutAt: clock.now(),
        by: by,
        changeId: changeId?.toString() ?? '',
      );
      final rec = await _mutate(
        deskId,
        transform: (current) {
          // Re-check inside the transform: a racing cut that landed
          // this round first makes ours a no-op record.
          if (current.rounds.any((r) => r.n == n)) return current;
          return current.copyWith(
            rounds: [...current.rounds, info],
            updatedAt: clock.now(),
          );
        },
        message: (_) => 'cut round $n',
      );
      if (!rec.ok) return GitResult.err(rec.error ?? 'record failed');
      return GitResult.ok(info);
    }
    return const GitResult.err('round cut raced repeatedly; retry');
  }

  // ─── Drafts (local-only namespace) ───────────────────────────────

  ManifoldLocalRef _draftsRef(int deskId) =>
      ManifoldLocalRef.reviewDrafts(deskId);

  /// Read the draft entries AND the exact tip they came from — the tip
  /// is what makes both draft races fixable: saves CAS against it, and
  /// publish deletes only the revision it actually consumed.
  Future<GitResult<(List<ReviewDraftEntry>, CommitOid?)>> _draftsSnapshot(
      int deskId) async {
    final ref = _draftsRef(deskId);
    final tip = await refs.resolveRef(ref);
    if (!tip.ok) return GitResult.err(tip.error ?? 'resolveRef failed');
    if (tip.data == null) return const GitResult.ok((<ReviewDraftEntry>[], null));
    final blob = await refs.readRefBlob(tip.data!, _draftsFilename);
    if (!blob.ok) return GitResult.err(blob.error ?? 'readRefBlob failed');
    if (blob.data == null) return GitResult.ok((<ReviewDraftEntry>[], tip.data));
    try {
      final j = jsonDecode(blob.data!) as Map<String, dynamic>;
      return GitResult.ok((
        (j['entries'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReviewDraftEntry.fromJson)
            .toList(),
        tip.data,
      ));
    } catch (e) {
      return GitResult.err('corrupt drafts.json: $e');
    }
  }

  @useResult
  Future<GitResult<List<ReviewDraftEntry>>> listDrafts(int deskId) async {
    final snap = await _draftsSnapshot(deskId);
    if (!snap.ok) return GitResult.err(snap.error ?? 'read failed');
    return GitResult.ok(snap.data!.$1);
  }

  /// Append one draft entry. Drafts live on a local-only ref and are
  /// invisible to every sync by namespace construction. Read-append-CAS
  /// with retry: entries are read AT the tip the write CASes against,
  /// so two overlapping saves can never silently drop each other (the
  /// old separate listDrafts/resolveRef reads could — caught by the
  /// manifold review).
  @useResult
  Future<GitResult<void>> saveDraft(int deskId, ReviewDraftEntry entry,
      {int maxAttempts = 5}) async {
    final ref = _draftsRef(deskId);
    String? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final snap = await _draftsSnapshot(deskId);
      if (!snap.ok) return GitResult.err(snap.error ?? 'read failed');
      final (existing, tip) = snap.data!;
      final payload = const JsonEncoder.withIndent('  ').convert({
        'updatedAt': isoUtc(clock.now()),
        'entries': [...existing.map((e) => e.toJson()), entry.toJson()],
      });
      final blobR = await refs.writeBlob(payload);
      if (!blobR.ok) return GitResult.err(blobR.error ?? 'writeBlob failed');
      final treeR = await refs.mkTree({_draftsFilename: blobR.data!});
      if (!treeR.ok) return GitResult.err(treeR.error ?? 'mkTree failed');
      final commitR = await refs.commitTree(
        treeSha: treeR.data!,
        parentSha: tip,
        message: 'draft',
      );
      if (!commitR.ok) return GitResult.err(commitR.error ?? 'commit failed');
      final upd = tip == null
          ? await refs.createRef(ref: ref, newSha: commitR.data!)
          : await refs.updateRef(
              ref: ref, newSha: commitR.data!, oldSha: tip);
      if (upd.ok) return const GitResult.ok(null);
      lastError = upd.error;
      await Future<void>.delayed(Duration(milliseconds: 5 + attempt * 5));
    }
    return GitResult.err(lastError ?? 'saveDraft lost every CAS');
  }

  /// Unconditional discard — the USER's explicit "throw my drafts away".
  /// Publish never calls this; it CAS-deletes only the revision it
  /// consumed.
  @useResult
  Future<GitResult<void>> discardDrafts(int deskId) =>
      refs.deleteRef(_draftsRef(deskId));

  /// Drop ONE draft, leaving the rest of the batch alone.
  ///
  /// Without this the only eraser is [discardDrafts], which takes every
  /// unpublished comment on the desk with it — so changing your mind
  /// about one line meant destroying the other four. Same CAS shape as
  /// [saveDraft]: re-read the tip each attempt, so a save landing
  /// concurrently is never clobbered. Removing the last entry deletes
  /// the ref outright rather than leaving an empty husk behind.
  @useResult
  Future<GitResult<void>> discardDraft(
    int deskId,
    ReviewDraftEntry entry, {
    int maxAttempts = 5,
  }) async {
    final ref = _draftsRef(deskId);
    String? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final snap = await _draftsSnapshot(deskId);
      if (!snap.ok) return GitResult.err(snap.error ?? 'read failed');
      final (existing, tip) = snap.data!;
      if (tip == null) return const GitResult.ok(null);
      final keep = [
        for (final e in existing)
          if (!_sameDraft(e, entry)) e,
      ];
      // Already gone (a racing discard, or a replay): the caller's
      // intent is satisfied.
      if (keep.length == existing.length) return const GitResult.ok(null);
      if (keep.isEmpty) {
        final del = await refs.deleteRef(ref, expectedSha: tip);
        if (del.ok) return const GitResult.ok(null);
        lastError = del.error;
        await Future<void>.delayed(Duration(milliseconds: 5 + attempt * 5));
        continue;
      }
      final payload = const JsonEncoder.withIndent('  ').convert({
        'updatedAt': isoUtc(clock.now()),
        'entries': [...keep.map((e) => e.toJson())],
      });
      final blobR = await refs.writeBlob(payload);
      if (!blobR.ok) return GitResult.err(blobR.error ?? 'writeBlob failed');
      final treeR = await refs.mkTree({_draftsFilename: blobR.data!});
      if (!treeR.ok) return GitResult.err(treeR.error ?? 'mkTree failed');
      final commitR = await refs.commitTree(
        treeSha: treeR.data!,
        parentSha: tip,
        message: 'discard draft',
      );
      if (!commitR.ok) return GitResult.err(commitR.error ?? 'commit failed');
      final upd =
          await refs.updateRef(ref: ref, newSha: commitR.data!, oldSha: tip);
      if (upd.ok) return const GitResult.ok(null);
      lastError = upd.error;
      await Future<void>.delayed(Duration(milliseconds: 5 + attempt * 5));
    }
    return GitResult.err(lastError ?? 'discardDraft lost every CAS');
  }

  /// Draft identity for removal: the same (thread, when, text) triple
  /// publish already treats as one comment, so a draft cannot be
  /// mistaken for a different one that merely reads alike.
  static bool _sameDraft(ReviewDraftEntry a, ReviewDraftEntry b) =>
      a.threadId == b.threadId &&
      isoUtc(a.at) == isoUtc(b.at) &&
      a.body == b.body;

  /// Test seam: runs between the durable state write and the draft-ref
  /// cleanup, where the save-during-publish race lives.
  @visibleForTesting
  Future<void> Function()? beforePublishDiscard;

  // ─── Publish (the atomic batch) ──────────────────────────────────

  /// Thread id = time + author + a digest OF THE OPENER.
  ///
  /// The tiebreak is content, not chance. Two threads the same author
  /// opens in the same millisecond still separate (their bodies differ),
  /// two clients cannot collide (the digest carries the text), and the
  /// whole store stays reproducible — an unseeded Random here would make
  /// two runs of the same input diverge, which is precisely what the
  /// determinism tripwire exists to prevent.
  ///
  /// The degenerate case is the RIGHT answer, not a hazard: an identical
  /// (author, at, body) opener collapses onto one id, which is the same
  /// call [publish]'s replay dedupe already makes when it refuses to
  /// re-open a thread for a comment it has seen.
  ///
  /// 32 bits of digest, not the 16 the random suffix carried. A true
  /// collision — same author, same millisecond, DIFFERENT bodies — would
  /// not read as a clash: threads merge by id under the union policy, so
  /// two unrelated conversations would silently fuse into one. Nothing
  /// downstream can detect that, which is why the tiebreak is sized for
  /// it to never happen rather than to be caught when it does.
  String _mintThreadId(ReviewIdentity author, DateTime at, String body) {
    final slug = author.display
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final digest = hex64(lineContentHash(
      '${author.display}\u0000${isoUtc(at)}\u0000$body',
    )).substring(0, 8);
    return 't-${at.millisecondsSinceEpoch.toRadixString(36)}-$slug-$digest';
  }

  /// Publish the viewer's drafts as ONE batch: new threads open,
  /// replies append, an optional [verdict] lands as the same event,
  /// and the draft ref is deleted last. Comment identity is the
  /// (author, at, body) union key, so a replay after a crash between
  /// state-write and draft-delete cannot duplicate anything.
  @useResult
  Future<GitResult<ReviewState>> publish({
    required int deskId,
    required ReviewIdentity author,
    String? verdict,
    int? verdictRound,
  }) async {
    final snapR = await _draftsSnapshot(deskId);
    if (!snapR.ok) return GitResult.err(snapR.error ?? 'drafts failed');
    final (drafts, draftsTip) = snapR.data!;
    if (drafts.isEmpty && verdict == null) {
      return const GitResult.err('nothing to publish');
    }

    final result = await _mutate(
      deskId,
      transform: (current) {
        var threads = [...current.threads];
        for (final d in drafts) {
          final comment = ReviewComment(
              author: author, at: d.at, body: d.body);
          if (d.threadId.isNotEmpty) {
            final i = threads.indexWhere((t) => t.id == d.threadId);
            if (i < 0) continue;
            if (_hasComment(threads[i], comment)) continue;
            threads[i] = threads[i].copyWith(
              comments: [...threads[i].comments, comment],
              updatedAt: clock.now(),
            );
          } else {
            if (d.anchor == null) continue;
            // Idempotent replay guard: an identical opener (same
            // author/at/body) already published opens nothing new.
            final dup = threads.any((t) =>
                t.comments.isNotEmpty && _sameComment(t.comments.first, comment));
            if (dup) continue;
            threads = [
              ...threads,
              ReviewThreadRecord(
                id: _mintThreadId(author, d.at, d.body),
                state: 'unresolved',
                anchor: d.anchor!,
                comments: [comment],
                updatedAt: clock.now(),
              ),
            ];
          }
        }
        var verdicts = current.verdicts;
        if (verdict != null) {
          // The verdict's identity derives from the BATCH (latest draft
          // time), not the wall clock: a crash between state-write and
          // draft-delete replays this publish, and a clock-stamped
          // verdict would duplicate on every retry (caught by the
          // manifold review — the comment dedupe alone wasn't the whole
          // replay contract). Verdict-only publishes can't replay
          // (empty drafts refuse to publish), so the clock is safe there.
          final batchAt = drafts.isEmpty
              ? clock.now()
              : drafts
                  .map((d) => d.at)
                  .reduce((a, b) => a.isAfter(b) ? a : b);
          final already = verdicts.any((v) =>
              v.by.display == author.display &&
              v.verdict == verdict &&
              isoUtc(v.at) == isoUtc(batchAt));
          if (!already) {
            verdicts = [
              ...verdicts,
              ReviewVerdict(
                by: author,
                verdict: verdict,
                at: batchAt,
                round: verdictRound ?? (current.latestRound?.n ?? 0),
              ),
            ];
          }
        }
        return current.copyWith(
          threads: threads,
          verdicts: verdicts,
          updatedAt: clock.now(),
        );
      },
      message: (_) => 'publish review batch by ${author.display}',
    );
    if (!result.ok) return GitResult.err(result.error ?? 'publish failed');

    // State is durable; only now does the private half disappear — and
    // only the EXACT revision this publish consumed. A draft saved
    // while we were publishing moves the ref, the CAS-delete refuses,
    // and that draft survives for the next publish (already-published
    // entries in the surviving file are replay-safe by dedupe).
    if (beforePublishDiscard != null) await beforePublishDiscard!();
    if (draftsTip != null) {
      final del = await refs.deleteRef(_draftsRef(deskId),
          expectedSha: draftsTip);
      if (!del.ok) {
        final still = await refs.resolveRef(_draftsRef(deskId));
        // The state write is already durable, so the ONLY real failure
        // here is "the drafts we consumed are still sitting at the tip
        // we consumed". Anything else means the private half already
        // reached a correct place without us:
        //   • moved  — a mid-publish save; leaving it is the fix
        //   • gone   — a concurrent discard beat us to it
        // Reporting either as a failure would tell the user their
        // published review did not publish, which is the one lie a
        // review tool must never tell (the discard case used to do
        // exactly that: `moved` could only ever see a DIFFERENT sha,
        // never an absent ref).
        final stillOurs = still.ok && still.data == draftsTip;
        if (stillOurs) {
          return GitResult.err(del.error ?? 'draft delete failed');
        }
      }
    }
    return GitResult.ok(result.data!);
  }

  static bool _sameComment(ReviewComment a, ReviewComment b) =>
      a.author.display == b.author.display &&
      isoUtc(a.at) == isoUtc(b.at) &&
      a.body == b.body;

  static bool _hasComment(ReviewThreadRecord t, ReviewComment c) =>
      t.comments.any((e) => _sameComment(e, c));

  // ─── Thread verbs ────────────────────────────────────────────────

  /// Resolve a thread: [how] is 'done' or 'acked'.
  @useResult
  Future<GitResult<ReviewState>> resolveThread({
    required int deskId,
    required String threadId,
    required ReviewIdentity by,
    required String how,
  }) {
    if (how != 'done' && how != 'acked') {
      return Future.value(GitResult.err('unknown resolution: $how'));
    }
    return _mutate(
      deskId,
      transform: (current) {
        final i = current.threads.indexWhere((t) => t.id == threadId);
        if (i < 0) return current;
        final threads = [...current.threads];
        threads[i] = threads[i].copyWith(
          state: how,
          resolvedBy: by,
          resolvedAt: clock.now(),
          updatedAt: clock.now(),
        );
        return current.copyWith(threads: threads, updatedAt: clock.now());
      },
      message: (_) => '$how by ${by.display}',
    );
  }

  /// Reopen a resolved thread — the inverse of [resolveThread].
  ///
  /// Resolution was a one-way door until this existed, which made a
  /// premature `done` permanent and left a later round with no way to
  /// say the fix did not hold. Convergence needs nothing special: a
  /// thread's scalars are element-level LWW on `updatedAt`, so whichever
  /// of reopen/resolve happened last wins on every clone.
  @useResult
  Future<GitResult<ReviewState>> reopenThread({
    required int deskId,
    required String threadId,
    required ReviewIdentity by,
  }) =>
      _mutate(
        deskId,
        transform: (current) {
          final i = current.threads.indexWhere((t) => t.id == threadId);
          if (i < 0) return current;
          if (current.threads[i].unresolved) return current;
          final threads = [...current.threads];
          threads[i] = threads[i].copyWith(
            state: 'unresolved',
            clearResolution: true,
            updatedAt: clock.now(),
          );
          return current.copyWith(threads: threads, updatedAt: clock.now());
        },
        message: (_) => 'reopened by ${by.display}',
      );

  /// Append a comment directly (robot findings, immediate replies that
  /// bypass the draft flow).
  @useResult
  Future<GitResult<ReviewState>> addComment({
    required int deskId,
    required String threadId,
    required ReviewComment comment,
  }) =>
      _mutate(
        deskId,
        transform: (current) {
          final i = current.threads.indexWhere((t) => t.id == threadId);
          if (i < 0) return current;
          if (_hasComment(current.threads[i], comment)) return current;
          final threads = [...current.threads];
          threads[i] = threads[i].copyWith(
            comments: [...threads[i].comments, comment],
            updatedAt: clock.now(),
          );
          return current.copyWith(threads: threads, updatedAt: clock.now());
        },
        message: (_) => 'comment by ${comment.author.display}',
      );

  /// Open a thread directly (robot reviewers publish immediately —
  /// they have no draft privacy to protect).
  @useResult
  Future<GitResult<ReviewState>> openThread({
    required int deskId,
    required ReviewAnchor anchor,
    required ReviewComment opener,
  }) =>
      _mutate(
        deskId,
        transform: (current) => current.copyWith(
          threads: [
            ...current.threads,
            ReviewThreadRecord(
              id: _mintThreadId(opener.author, opener.at, opener.body),
              state: 'unresolved',
              anchor: anchor,
              comments: [opener],
              updatedAt: clock.now(),
            ),
          ],
          updatedAt: clock.now(),
        ),
        message: (_) => 'thread by ${opener.author.display}',
      );

  /// Mark [path] reviewed by [reviewer] as of [contentHash] at round
  /// [round]. Auto-clear is comparison, not an event: a bit whose
  /// contentHash no longer matches the file simply isn't "reviewed".
  @useResult
  Future<GitResult<ReviewState>> setFileReviewed({
    required int deskId,
    required String reviewer,
    required String path,
    required String contentHash,
    required int round,
  }) =>
      _mutate(
        deskId,
        transform: (current) {
          final files =
              Map<String, Map<String, ReviewedFileBit>>.from(
                  current.reviewedFiles);
          final mine = Map<String, ReviewedFileBit>.from(
              files[reviewer] ?? const {});
          mine[path] = ReviewedFileBit(
              contentHash: contentHash, round: round, at: clock.now());
          files[reviewer] = mine;
          return current.copyWith(
              reviewedFiles: files, updatedAt: clock.now());
        },
        message: (_) => 'reviewed $path',
      );

  /// Share reviews over the remote — delegates to the whole-namespace
  /// reconcile (reviews ride the same sync as desks/issues).
  @useResult
  Future<GitResult<void>> syncWithRemote({MetadataRemote? remote}) async {
    final resolvedRemote = remote ?? await refs.resolveMetadataRemote();
    await refs.ensureFetchRefspec(remote: resolvedRemote);
    return refs.syncWithRemote(remote: resolvedRemote);
  }
}
