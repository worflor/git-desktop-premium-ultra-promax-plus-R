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
import 'dart:math';

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
        'at': at.toIso8601String(),
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
  final Random _rng;

  ReviewStore(this.refs, {this.clock = const SystemClock(), Random? rng})
      : _rng = rng ?? Random();

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
        'updatedAt': clock.now().toIso8601String(),
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

  /// Test seam: runs between the durable state write and the draft-ref
  /// cleanup, where the save-during-publish race lives.
  @visibleForTesting
  Future<void> Function()? beforePublishDiscard;

  // ─── Publish (the atomic batch) ──────────────────────────────────

  String _mintThreadId(ReviewIdentity author, DateTime at) {
    final slug = author.display
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final rand = _rng.nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    return 't-${at.millisecondsSinceEpoch.toRadixString(36)}-$slug-$rand';
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
                id: _mintThreadId(author, d.at),
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
              v.at.toIso8601String() == batchAt.toIso8601String());
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
        final moved = still.ok && still.data != null && still.data != draftsTip;
        if (!moved) {
          return GitResult.err(del.error ?? 'draft delete failed');
        }
        // Moved = a mid-publish save won the race; leaving it is the fix.
      }
    }
    return GitResult.ok(result.data!);
  }

  static bool _sameComment(ReviewComment a, ReviewComment b) =>
      a.author.display == b.author.display &&
      a.at.toIso8601String() == b.at.toIso8601String() &&
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
              id: _mintThreadId(opener.author, opener.at),
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
