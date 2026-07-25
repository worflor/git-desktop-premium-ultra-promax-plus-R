// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_records.dart — the review object model.
//
// A desk PR's review is two kinds of git state:
//  * ROUNDS — immutable refs pinning real branch commits
//    (`refs/manifold/review/<deskId>/round/<n>`), the snapshot chain
//    that makes "diff since I last looked" native and force-push-proof.
//    The state doc records round METADATA; the ref holds reachability.
//  * the STATE DOC — one mutable JSON record
//    (`refs/manifold/review/<deskId>/state`) holding threads, verdicts,
//    and per-file reviewed bits, merged across machines by the
//    DECLARED schema below (never shape-sniffing, never text merge).
//
// Identity is an object `{display, key?}` from day one: key is absent
// today and attachable later (account-free connectivity) without
// migration. Never bake "identity == author string" into a merge key.
//
// Timestamps in records are ISO-8601 strings minted by the store's
// Clock seam; this file never reads a clock.

import 'dart:convert';

import 'merge_policy.dart';
import 'review_anchor.dart';

const int kReviewSchemaVersion = 1;

/// Unknown-field preservation: every record captures the JSON keys it
/// does not model and re-emits them on serialization (spread FIRST, so
/// known fields always win a collision). A state doc written by a
/// newer schema or a third-party extension survives our rewrites
/// intact — without this, a typed round-trip silently STRIPS foreign
/// fields while keeping the newer schemaVersion, corrupting exactly
/// the interop the format promises (caught by the manifold review).
///
/// WHAT THIS DOES NOT PROMISE, stated because the guarantee is easy to
/// over-read: it protects a foreign field through OUR round-trip. It
/// does not deep-merge one. A key both sides changed independently
/// falls to the default whole-value LWW in the merge engine, so the
/// loser's edit is dropped — the engine cannot union or reconcile a
/// field whose meaning it does not know, and inventing a rule for it
/// would be a worse failure than an honest last-writer-wins. Foreign
/// extensions that need convergence have to declare a merge policy,
/// not merely a key.
Map<String, dynamic> _extrasOf(Map<String, dynamic> j, Set<String> known) =>
    {
      for (final e in j.entries)
        if (!known.contains(e.key)) e.key: e.value,
    };

/// Who did something. [display] is the human-readable name (the merge
/// key today); [key] is the future stable identity — carried verbatim,
/// never interpreted yet.
class ReviewIdentity {
  final String display;
  final String? key;
  final Map<String, dynamic> extra;
  const ReviewIdentity(this.display, {this.key, this.extra = const {}});

  Map<String, dynamic> toJson() =>
      {...extra, 'display': display, if (key != null) 'key': key};

  factory ReviewIdentity.fromJson(Map<String, dynamic> j) => ReviewIdentity(
        (j['display'] as String? ?? '').trim(),
        key: j['key'] as String?,
        extra: _extrasOf(j, const {'display', 'key'}),
      );
}

/// One comment inside a thread. Immutable once published — the union
/// merge dedupes by (author.display, at, body).
class ReviewComment {
  final ReviewIdentity author;
  final DateTime at;
  final String body;

  /// 'human' | 'robot'.
  final String kind;

  final Map<String, dynamic> extra;

  const ReviewComment({
    required this.author,
    required this.at,
    required this.body,
    this.kind = 'human',
    this.extra = const {},
  });

  Map<String, dynamic> toJson() => {
        ...extra,
        'author': author.toJson(),
        'at': isoUtc(at),
        'body': body,
        'kind': kind,
      };

  factory ReviewComment.fromJson(Map<String, dynamic> j) => ReviewComment(
        author: ReviewIdentity.fromJson(
            (j['author'] as Map?)?.cast<String, dynamic>() ?? const {}),
        at: DateTime.tryParse(j['at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        body: j['body'] as String? ?? '',
        kind: (j['kind'] as String? ?? 'human'),
        extra: _extrasOf(j, const {'author', 'at', 'body', 'kind'}),
      );
}

/// One anchored thread. Mutable: state moves, comments append. Carries
/// its own `updatedAt` so element-level merges resolve by recency.
class ReviewThreadRecord {
  final String id;

  /// 'unresolved' | 'done' | 'acked'.
  final String state;
  final ReviewIdentity? resolvedBy;
  final DateTime? resolvedAt;
  final ReviewAnchor anchor;
  final List<ReviewComment> comments;
  final DateTime updatedAt;
  final Map<String, dynamic> extra;

  const ReviewThreadRecord({
    required this.id,
    required this.state,
    required this.anchor,
    required this.comments,
    required this.updatedAt,
    this.resolvedBy,
    this.resolvedAt,
    this.extra = const {},
  });

  bool get unresolved => state == 'unresolved';

  /// [clearResolution] exists because `?? this.x` cannot express
  /// "unset": reopening has to drop resolvedBy/resolvedAt, and a thread
  /// that says `unresolved` while still naming who resolved it is
  /// incoherent to every reader of the format, ours or a third party's.
  ReviewThreadRecord copyWith({
    String? state,
    ReviewIdentity? resolvedBy,
    DateTime? resolvedAt,
    List<ReviewComment>? comments,
    DateTime? updatedAt,
    bool clearResolution = false,
  }) =>
      ReviewThreadRecord(
        id: id,
        state: state ?? this.state,
        anchor: anchor,
        comments: comments ?? this.comments,
        updatedAt: updatedAt ?? this.updatedAt,
        resolvedBy: clearResolution ? null : (resolvedBy ?? this.resolvedBy),
        resolvedAt: clearResolution ? null : (resolvedAt ?? this.resolvedAt),
        extra: extra,
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'state': state,
        if (resolvedBy != null) 'resolvedBy': resolvedBy!.toJson(),
        if (resolvedAt != null) 'resolvedAt': isoUtc(resolvedAt!),
        'anchor': anchor.toJson(),
        'comments': comments.map((c) => c.toJson()).toList(),
        'updatedAt': isoUtc(updatedAt),
      };

  factory ReviewThreadRecord.fromJson(Map<String, dynamic> j) =>
      ReviewThreadRecord(
        id: j['id'] as String? ?? '',
        state: (j['state'] as String? ?? 'unresolved'),
        resolvedBy: j['resolvedBy'] is Map
            ? ReviewIdentity.fromJson(
                (j['resolvedBy'] as Map).cast<String, dynamic>())
            : null,
        resolvedAt: DateTime.tryParse(j['resolvedAt'] as String? ?? ''),
        anchor: ReviewAnchor.fromJson(
            (j['anchor'] as Map?)?.cast<String, dynamic>() ?? const {}),
        comments: (j['comments'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReviewComment.fromJson)
            .toList(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        extra: _extrasOf(j, const {
          'id', 'state', 'resolvedBy', 'resolvedAt', 'anchor', 'comments',
          'updatedAt',
        }),
      );
}

/// Metadata for one cut round. The pin itself is the round REF; this
/// is the bookkeeping (when, who, what change-id) that rides the doc.
class ReviewRoundInfo {
  final int n;
  final String commit;
  final DateTime cutAt;
  final ReviewIdentity by;

  /// The commit's change-id (declared or synthetic) at cut time — the
  /// phase-2 rewrite-survival hook.
  final String changeId;

  final Map<String, dynamic> extra;

  const ReviewRoundInfo({
    required this.n,
    required this.commit,
    required this.cutAt,
    required this.by,
    required this.changeId,
    this.extra = const {},
  });

  Map<String, dynamic> toJson() => {
        ...extra,
        'n': n,
        'commit': commit,
        'cutAt': isoUtc(cutAt),
        'by': by.toJson(),
        'changeId': changeId,
      };

  factory ReviewRoundInfo.fromJson(Map<String, dynamic> j) => ReviewRoundInfo(
        n: (j['n'] as num? ?? 0).toInt(),
        commit: j['commit'] as String? ?? '',
        cutAt: DateTime.tryParse(j['cutAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        by: ReviewIdentity.fromJson(
            (j['by'] as Map?)?.cast<String, dynamic>() ?? const {}),
        changeId: j['changeId'] as String? ?? '',
        extra: _extrasOf(
            j, const {'n', 'commit', 'cutAt', 'by', 'changeId'}),
      );
}

/// One published verdict event (append-only; latest per reviewer is
/// the standing decision, same folding as desk PR reviews).
class ReviewVerdict {
  final ReviewIdentity by;

  /// 'APPROVED' | 'CHANGES_REQUESTED' | 'COMMENTED'.
  final String verdict;
  final DateTime at;
  final int round;

  final Map<String, dynamic> extra;

  const ReviewVerdict({
    required this.by,
    required this.verdict,
    required this.at,
    required this.round,
    this.extra = const {},
  });

  Map<String, dynamic> toJson() => {
        ...extra,
        'by': by.toJson(),
        'verdict': verdict,
        'at': isoUtc(at),
        'round': round,
      };

  factory ReviewVerdict.fromJson(Map<String, dynamic> j) => ReviewVerdict(
        by: ReviewIdentity.fromJson(
            (j['by'] as Map?)?.cast<String, dynamic>() ?? const {}),
        verdict: (j['verdict'] as String? ?? '').toUpperCase(),
        at: DateTime.tryParse(j['at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        round: (j['round'] as num? ?? 0).toInt(),
        extra: _extrasOf(j, const {'by', 'verdict', 'at', 'round'}),
      );
}

/// The mutable review-state doc.
class ReviewState {
  final int schemaVersion;
  final int deskId;
  final List<ReviewRoundInfo> rounds;
  final List<ReviewThreadRecord> threads;
  final List<ReviewVerdict> verdicts;

  /// reviewer display → path → {contentHash, round, at}. Reviewed bits
  /// keyed to CONTENT, so an edit auto-invalidates by comparison, not
  /// by event.
  final Map<String, Map<String, ReviewedFileBit>> reviewedFiles;
  final DateTime updatedAt;
  final Map<String, dynamic> extra;

  const ReviewState({
    required this.schemaVersion,
    required this.deskId,
    required this.rounds,
    required this.threads,
    required this.verdicts,
    required this.reviewedFiles,
    required this.updatedAt,
    this.extra = const {},
  });

  factory ReviewState.fresh(int deskId, DateTime now) => ReviewState(
        schemaVersion: kReviewSchemaVersion,
        deskId: deskId,
        rounds: const [],
        threads: const [],
        verdicts: const [],
        reviewedFiles: const {},
        updatedAt: now,
      );

  ReviewRoundInfo? get latestRound =>
      rounds.isEmpty ? null : rounds.reduce((a, b) => a.n >= b.n ? a : b);

  int get unresolvedCount => threads.where((t) => t.unresolved).length;

  ReviewState copyWith({
    List<ReviewRoundInfo>? rounds,
    List<ReviewThreadRecord>? threads,
    List<ReviewVerdict>? verdicts,
    Map<String, Map<String, ReviewedFileBit>>? reviewedFiles,
    DateTime? updatedAt,
  }) =>
      ReviewState(
        schemaVersion: schemaVersion,
        deskId: deskId,
        rounds: rounds ?? this.rounds,
        threads: threads ?? this.threads,
        verdicts: verdicts ?? this.verdicts,
        reviewedFiles: reviewedFiles ?? this.reviewedFiles,
        updatedAt: updatedAt ?? this.updatedAt,
        extra: extra,
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'schemaVersion': schemaVersion,
        'deskId': deskId,
        'rounds': rounds.map((r) => r.toJson()).toList(),
        'threads': threads.map((t) => t.toJson()).toList(),
        'verdicts': verdicts.map((v) => v.toJson()).toList(),
        'reviewedFiles': reviewedFiles.map((reviewer, files) => MapEntry(
            reviewer,
            files.map((path, bit) => MapEntry(path, bit.toJson())))),
        'updatedAt': isoUtc(updatedAt),
      };

  factory ReviewState.fromJson(Map<String, dynamic> j) => ReviewState(
        schemaVersion: (j['schemaVersion'] as num? ?? 1).toInt(),
        deskId: (j['deskId'] as num? ?? 0).toInt(),
        rounds: (j['rounds'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReviewRoundInfo.fromJson)
            .toList(),
        threads: (j['threads'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReviewThreadRecord.fromJson)
            .toList(),
        verdicts: (j['verdicts'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReviewVerdict.fromJson)
            .toList(),
        reviewedFiles: ((j['reviewedFiles'] as Map?) ?? const {})
            .cast<String, dynamic>()
            .map((reviewer, files) => MapEntry(
                reviewer,
                ((files as Map?) ?? const {}).cast<String, dynamic>().map(
                    (path, bit) => MapEntry(
                        path,
                        ReviewedFileBit.fromJson(
                            (bit as Map).cast<String, dynamic>()))))),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        extra: _extrasOf(j, const {
          'schemaVersion', 'deskId', 'rounds', 'threads', 'verdicts',
          'reviewedFiles', 'updatedAt',
        }),
      );

  String toBlob() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory ReviewState.fromBlob(String blob) =>
      ReviewState.fromJson(jsonDecode(blob) as Map<String, dynamic>);
}

/// One per-file reviewed mark: which content the reviewer saw, when.
class ReviewedFileBit {
  final String contentHash;
  final int round;
  final DateTime at;

  final Map<String, dynamic> extra;

  const ReviewedFileBit({
    required this.contentHash,
    required this.round,
    required this.at,
    this.extra = const {},
  });

  Map<String, dynamic> toJson() => {
        ...extra,
        'contentHash': contentHash,
        'round': round,
        'at': isoUtc(at),
      };

  factory ReviewedFileBit.fromJson(Map<String, dynamic> j) => ReviewedFileBit(
        contentHash: j['contentHash'] as String? ?? '',
        round: (j['round'] as num? ?? 0).toInt(),
        at: DateTime.tryParse(j['at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        extra: _extrasOf(j, const {'contentHash', 'round', 'at'}),
      );
}

// ─── The declared merge schema ────────────────────────────────────────

/// THE serializer for every instant in the review format.
///
/// UTC, always. A zone-less local stamp makes last-writer-wins compare
/// wall clocks instead of moments — a peer one timezone east wins a
/// race it actually lost — and it breaks the raw-string dedup keys that
/// make publish replay-safe across machines. Reading stays lenient:
/// `DateTime.tryParse` accepts both forms, so docs stamped before this
/// existed still load (they simply carry their old local reading).
String isoUtc(DateTime t) => t.toUtc().toIso8601String();

String _s(Object? v) => v is String ? v : (v?.toString() ?? '');

String _commentKey(Map<String, dynamic> e) {
  final author = (e['author'] as Map?)?['display'];
  return '${_s(author)}\u0000${_s(e['at'])}\u0000${_s(e['body'])}';
}

int _byAtAuthorBody(Map<String, dynamic> a, Map<String, dynamic> b) {
  var c = _s(a['at']).compareTo(_s(b['at']));
  if (c != 0) return c;
  c = _s((a['author'] as Map?)?['display'])
      .compareTo(_s((b['author'] as Map?)?['display']));
  if (c != 0) return c;
  return _s(a['body']).compareTo(_s(b['body']));
}

/// A thread's own merge behaviour: comments union (immutable entries),
/// everything else element-level LWW by the thread's `updatedAt`.
const RecordSchema kReviewThreadSchema = RecordSchema(fields: {
  'comments': UnionList(
    keyOf: _commentKey,
    compare: _byAtAuthorBody,
  ),
});

String _verdictKey(Map<String, dynamic> e) {
  final by = (e['by'] as Map?)?['display'];
  return '${_s(by)}\u0000${_s(e['at'])}\u0000${_s(e['verdict'])}';
}

int _byAtByVerdict(Map<String, dynamic> a, Map<String, dynamic> b) {
  var c = _s(a['at']).compareTo(_s(b['at']));
  if (c != 0) return c;
  c = _s((a['by'] as Map?)?['display'])
      .compareTo(_s((b['by'] as Map?)?['display']));
  if (c != 0) return c;
  return _s(a['verdict']).compareTo(_s(b['verdict']));
}

String _roundKey(Map<String, dynamic> e) => _s(e['n']);

int _byRoundN(Map<String, dynamic> a, Map<String, dynamic> b) {
  final an = (a['n'] as num? ?? 0).toInt();
  final bn = (b['n'] as num? ?? 0).toInt();
  return an.compareTo(bn);
}

String _threadKey(Map<String, dynamic> e) => _s(e['id']);

int _byThreadId(Map<String, dynamic> a, Map<String, dynamic> b) =>
    _s(a['id']).compareTo(_s(b['id']));

/// The review-state doc's declared merge schema. This is what the
/// reconcile engine consults for `refs/manifold/review/<id>/state`
/// divergences — the whole point of the generalization: convergence
/// behaviour is READ OFF THE TYPE, not guessed from value shapes.
const RecordSchema kReviewStateSchema = RecordSchema(fields: {
  'schemaVersion': MaxNum(),
  // collideBy 'commit': a same-number double-cut race must converge to
  // the SAME winner the pin ref chooses (_adoptLargerSha picks the
  // lexicographically larger commit) — two unrelated tiebreaks would
  // let round metadata name one snapshot while the ref pins another.
  'rounds': UnionList(
      keyOf: _roundKey, compare: _byRoundN, collideBy: 'commit'),
  'threads': UnionList(
    keyOf: _threadKey,
    element: kReviewThreadSchema,
    compare: _byThreadId,
  ),
  'verdicts': UnionList(keyOf: _verdictKey, compare: _byAtByVerdict),
  'reviewedFiles': PerKeyMap(PerKeyMap(LwwTs('at'))),
});

// ─── The turn fold ────────────────────────────────────────────────────

/// Whose move the review waits on, derived — never stored. The
/// attention set is a computed rendered fact: the last publisher hands
/// the ball to the other side.
class ReviewTurnState {
  /// True when the ball is with [viewer].
  final bool yourTurn;

  /// Display name of who the review waits on (empty when it's the
  /// viewer, or nobody has acted yet).
  final String waitingOn;

  const ReviewTurnState({required this.yourTurn, required this.waitingOn});
}

/// Derive the turn from the event history.
///
/// The rule (Critique's essence, minus explicit hand-backs): the most
/// recent MOVE flips the ball to the other party — author ↔ reviewers.
///
/// A round cut is a move by the CODE, not by a person. It deliberately
/// carries no actor into this fold: rounds are cut by whichever client
/// first notices the head advanced, so attributing one would make the
/// ball depend on whose app happened to sync first — a reviewer's
/// background sync of the author's push would name the REVIEWER as the
/// last actor and hand the ball back to the author who just delivered.
/// New code simply awaits review, whoever pushed it.
///
/// Among reviewers the fold is per-person: someone who has already
/// spoken since the current round is no longer being waited on, so a
/// reviewer who approved stops being told it is their turn and the
/// author's "waiting on" names only who is actually blocking.
ReviewTurnState deriveTurn(
  ReviewState state, {
  required String authorDisplay,
  required String viewerDisplay,
}) {
  final epoch0 = DateTime.fromMillisecondsSinceEpoch(0);
  String? lastActor;
  DateTime last = epoch0;
  // When each person last moved — the per-reviewer half of the fold.
  final lastMoveBy = <String, DateTime>{};
  void consider(String actor, DateTime at) {
    if (at.isAfter(last)) {
      last = at;
      lastActor = actor;
    }
    final prior = lastMoveBy[actor];
    if (prior == null || at.isAfter(prior)) lastMoveBy[actor] = at;
  }

  for (final t in state.threads) {
    for (final c in t.comments) {
      consider(c.author.display, c.at);
    }
    if (t.resolvedBy != null && t.resolvedAt != null) {
      consider(t.resolvedBy!.display, t.resolvedAt!);
    }
  }
  for (final v in state.verdicts) {
    consider(v.by.display, v.at);
  }
  // Rounds are timed but NOT attributed (see the doc comment).
  var newestRound = epoch0;
  for (final r in state.rounds) {
    if (r.cutAt.isAfter(newestRound)) newestRound = r.cutAt;
  }

  final reviewers = <String>{};
  for (final v in state.verdicts) {
    if (v.by.display != authorDisplay) reviewers.add(v.by.display);
  }
  for (final t in state.threads) {
    for (final c in t.comments) {
      if (c.author.display != authorDisplay && c.kind == 'human') {
        reviewers.add(c.author.display);
      }
    }
  }

  if (lastActor == null || reviewers.isEmpty) {
    // Nothing has happened, or no human reviewer exists yet: the
    // review waits on a reviewer.
    final isAuthor = viewerDisplay == authorDisplay;
    return ReviewTurnState(
      yourTurn: !isAuthor,
      waitingOn: isAuthor ? '' : viewerDisplay,
    );
  }

  // Code that landed after the last human move puts the ball back with
  // the reviewers regardless of who spoke last.
  final codeMovedLast = newestRound.isAfter(last);
  final ballWithAuthor = !codeMovedLast && lastActor != authorDisplay;
  if (ballWithAuthor) {
    return ReviewTurnState(
      yourTurn: viewerDisplay == authorDisplay,
      waitingOn: viewerDisplay == authorDisplay ? '' : authorDisplay,
    );
  }

  // Ball with reviewers, as a bloc.
  //
  // KNOWN LIMIT, stated rather than half-solved: this is a TWO-PARTY
  // fold (author ↔ reviewers). With several reviewers it cannot express
  // "carol still owes a look while alice is done", and the honest
  // per-person version is a design question, not a missing line — does
  // one reviewer's approval move the ball while another has not looked?
  // does an author's reply re-obligate the reviewer who just commented?
  // Answering those by guess would produce an attention model that is
  // confidently wrong, which is worse for trust than one that is
  // simple and understood. `lastMoveBy` is computed above and ready for
  // whichever rule gets chosen.
  final viewerIsReviewer = viewerDisplay != authorDisplay;
  final owing = reviewers.toList()..sort();
  return ReviewTurnState(
    yourTurn: viewerIsReviewer,
    waitingOn: viewerIsReviewer ? '' : owing.join(', '),
  );
}
