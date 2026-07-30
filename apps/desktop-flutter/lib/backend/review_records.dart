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

  /// The round this comment was published at. 0 when unknown (a
  /// document written before comments carried one).
  ///
  /// The turn fold needs to answer "has this person spoken at the
  /// current round", and [at] cannot answer it: comments come from
  /// different machines with different wall clocks, so a reviewer whose
  /// clock runs fast appears to have spoken after a round that was cut
  /// before they said anything. A round number comes from the shared ref
  /// rather than from anyone's clock, so comparing rounds is comparing
  /// the same thing on every machine.
  ///
  /// An opener's round is also on its scope, but a REPLY has no scope of
  /// its own — which is exactly the case the fold cares most about.
  final int round;

  /// Position within its thread. A Lamport counter, 1 for the opener.
  ///
  /// "Who spoke last in this thread" is a CAUSAL question, and `at`
  /// cannot answer it either: the opener and the reply come from
  /// different machines, so a reply written minutes later carries an
  /// earlier stamp whenever the replier's clock is behind. Two things
  /// broke on that — the turn fold decided the author had not answered a
  /// comment they had just answered, and the pane rendered the reply
  /// ABOVE the comment it was replying to.
  ///
  /// A publisher reads the thread and writes `max(seq) + 1`, so a comment
  /// written in knowledge of the ones before it sorts after them. Absent
  /// (0) in documents written before this existed, where ordering falls
  /// back to `at` exactly as it did then.
  final int seq;

  final Map<String, dynamic> extra;

  const ReviewComment({
    required this.author,
    required this.at,
    required this.body,
    this.kind = 'human',
    this.round = 0,
    this.seq = 0,
    this.extra = const {},
  });

  /// The same comment with its position in the document filled in.
  ///
  /// Only the STORE may call this: round and seq are facts about the doc
  /// being written, not about the words, and a caller inventing them
  /// produces a comment the turn fold misreads. Identity is untouched —
  /// the dedup keys are (author, at, body), so a replayed publish still
  /// recognizes itself.
  ReviewComment stamped({required int round, required int seq}) =>
      ReviewComment(
        author: author,
        at: at,
        body: body,
        kind: kind,
        round: round,
        seq: seq,
        extra: extra,
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'author': author.toJson(),
        'at': isoUtc(at),
        'body': body,
        'kind': kind,
        if (round > 0) 'round': round,
        if (seq > 0) 'seq': seq,
      };

  factory ReviewComment.fromJson(Map<String, dynamic> j) => ReviewComment(
        author: ReviewIdentity.fromJson(
            (j['author'] as Map?)?.cast<String, dynamic>() ?? const {}),
        at: DateTime.tryParse(j['at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        body: j['body'] as String? ?? '',
        kind: (j['kind'] as String? ?? 'human'),
        round: (j['round'] as num? ?? 0).toInt(),
        seq: (j['seq'] as num? ?? 0).toInt(),
        extra: _extrasOf(
            j, const {'author', 'at', 'body', 'kind', 'round', 'seq'}),
      );
}

/// One thread. Mutable: state moves, comments append. Carries its own
/// `updatedAt` so element-level merges resolve by recency.
class ReviewThreadRecord {
  final String id;

  /// 'unresolved' | 'done' | 'acked'.
  final String state;
  final ReviewIdentity? resolvedBy;
  final DateTime? resolvedAt;

  /// What this thread is about: a line, a file, or the change itself.
  /// See [ReviewScope] for why this is sealed rather than a nullable
  /// anchor.
  final ReviewScope scope;
  final List<ReviewComment> comments;
  final DateTime updatedAt;
  final Map<String, dynamic> extra;

  const ReviewThreadRecord({
    required this.id,
    required this.state,
    required this.scope,
    required this.comments,
    required this.updatedAt,
    this.resolvedBy,
    this.resolvedAt,
    this.extra = const {},
  });

  bool get unresolved => state == 'unresolved';

  /// The line anchor, when this thread is about a line. Null for file-
  /// and review-scoped threads — callers that need to resolve content
  /// must handle the absence rather than assume a line.
  ReviewAnchor? get lineAnchor =>
      scope is LineScope ? (scope as LineScope).anchor : null;

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
        scope: scope,
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
        ...scope.toJson(),
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
        scope: ReviewScope.fromJson(j),
        comments: (j['comments'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReviewComment.fromJson)
            .toList(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        // 'scope' AND 'anchor' both drop out of extra: a document that
        // round-trips through an older client keeps its scope, because
        // that client cannot parse the key but does preserve it here.
        extra: _extrasOf(j, const {
          'id', 'state', 'resolvedBy', 'resolvedAt', 'scope', 'anchor',
          'comments', 'updatedAt',
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
  ///
  /// Upper-cased by the constructor, so the case of a verdict cannot
  /// depend on which path wrote it. It used to be normalized on the READ
  /// side only ([fromJson]), which meant a caller passing
  /// 'changes_requested' wrote a doc that folded to no standing at all
  /// until the next reload happened to upcase it — a decision that was
  /// silently inert for exactly as long as the writer's own process
  /// believed it had landed. Normalizing here makes the mixed-case
  /// verdict unrepresentable instead of merely unlikely.
  final String verdict;
  final DateTime at;
  final int round;

  /// Per-reviewer write counter, ranked below [round] and above [at].
  ///
  /// The third record on this axis, and it is here for consistency as
  /// much as for the failure: a reviewer who changes their mind twice in
  /// one round from two machines would otherwise have the standing
  /// decided by which machine's clock was ahead — the same skew that
  /// attention and comments already refuse. Nobody reading this format
  /// should have to remember which record types are safe from it.
  final int seq;

  final Map<String, dynamic> extra;

  ReviewVerdict({
    required this.by,
    required String verdict,
    required this.at,
    required this.round,
    this.seq = 0,
    this.extra = const {},
  }) : verdict = verdict.toUpperCase();

  Map<String, dynamic> toJson() => {
        ...extra,
        'by': by.toJson(),
        'verdict': verdict,
        'at': isoUtc(at),
        'round': round,
        if (seq > 0) 'seq': seq,
      };

  factory ReviewVerdict.fromJson(Map<String, dynamic> j) => ReviewVerdict(
        by: ReviewIdentity.fromJson(
            (j['by'] as Map?)?.cast<String, dynamic>() ?? const {}),
        // Case is the constructor's job now — one normalizer, not two.
        verdict: j['verdict'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        round: (j['round'] as num? ?? 0).toInt(),
        seq: (j['seq'] as num? ?? 0).toInt(),
        extra: _extrasOf(j, const {'by', 'verdict', 'at', 'round', 'seq'}),
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

  /// Who the change is blocked on, keyed by display name. Entries with
  /// `inSet: false` are explicit removals and are kept, not pruned.
  final Map<String, ReviewAttention> attention;
  final DateTime updatedAt;
  final Map<String, dynamic> extra;

  const ReviewState({
    required this.schemaVersion,
    required this.deskId,
    required this.rounds,
    required this.threads,
    required this.verdicts,
    required this.reviewedFiles,
    this.attention = const {},
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
        attention: const {},
        updatedAt: now,
      );

  ReviewRoundInfo? get latestRound =>
      rounds.isEmpty ? null : rounds.reduce((a, b) => a.n >= b.n ? a : b);

  int get unresolvedCount => threads.where((t) => t.unresolved).length;

  /// The people currently blocking, in a stable order. Sorted because
  /// this is rendered: map order is an implementation detail and the
  /// same set must read identically on every clone.
  List<String> get attentionOn => [
        for (final e in attention.entries)
          if (e.value.inSet) e.key,
      ]..sort();

  bool blockedOn(String display) => attention[display]?.inSet ?? false;

  ReviewState copyWith({
    List<ReviewRoundInfo>? rounds,
    List<ReviewThreadRecord>? threads,
    List<ReviewVerdict>? verdicts,
    Map<String, Map<String, ReviewedFileBit>>? reviewedFiles,
    Map<String, ReviewAttention>? attention,
    DateTime? updatedAt,
  }) =>
      ReviewState(
        schemaVersion: schemaVersion,
        deskId: deskId,
        rounds: rounds ?? this.rounds,
        threads: threads ?? this.threads,
        verdicts: verdicts ?? this.verdicts,
        reviewedFiles: reviewedFiles ?? this.reviewedFiles,
        attention: attention ?? this.attention,
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
        'attention':
            attention.map((who, a) => MapEntry(who, a.toJson())),
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
        attention: ((j['attention'] as Map?) ?? const {})
            .cast<String, dynamic>()
            .map((who, a) => MapEntry(
                who,
                ReviewAttention.fromJson(
                    who, (a as Map).cast<String, dynamic>()))),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        extra: _extrasOf(j, const {
          'schemaVersion', 'deskId', 'rounds', 'threads', 'verdicts',
          'reviewedFiles', 'attention', 'updatedAt',
        }),
      );

  String toBlob() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory ReviewState.fromBlob(String blob) =>
      ReviewState.fromJson(jsonDecode(blob) as Map<String, dynamic>);
}

/// One per-file reviewed mark: which content the reviewer saw, when.
/// One person's standing in the attention set — who the change is
/// blocked on right now.
///
/// [inSet] false is a REMOVAL, carried explicitly rather than by
/// dropping the key: a tombstone can win a merge, an absence cannot.
/// That is what makes "I took myself out" survive a sync with a peer
/// who still had me in.
class ReviewAttention {
  final String display;
  final bool inSet;

  /// When this standing was last set — the tie-break for merges within
  /// one round.
  final DateTime at;

  /// The round it was set at. Informative — which snapshot of the
  /// change this standing was decided against.
  final int round;

  /// Per-person write counter — the merge key that ranks BELOW [round].
  ///
  /// Round first, then this. A counter is local mutation history and
  /// carries no cross-round meaning, so ranking on it alone let a clone
  /// that had toggled a lot at round 1 defeat a decision made at round 3.
  /// Within one round it is exactly right, which is the case it exists
  /// for.
  ///
  /// A Lamport counter, because the question "what is the latest decision
  /// about this person" is CAUSAL and not temporal. Two clones stamp `at`
  /// from their own wall clocks, so ranking on it ranks the clocks: the
  /// lab reproduced a step-out being silently resurrected by a peer whose
  /// clock was twelve seconds ahead and who had not written since. Adding
  /// the round as the major key fixed it across rounds and not within
  /// one, which is where it actually happens.
  ///
  /// A writer reads the entry it is replacing and stores `seq + 1`, so a
  /// decision made in FULL KNOWLEDGE of the previous one always wins,
  /// whatever the clocks say. Genuinely concurrent writes tie, and the
  /// timestamp then breaks the tie exactly as before — no worse than
  /// today in the only case where "who was later" is unanswerable.
  final int seq;

  /// Who set it. Self-removal and being handed the ball read
  /// differently to a human, and the fold keeps the distinction.
  final String by;

  final Map<String, dynamic> extra;

  const ReviewAttention({
    required this.display,
    required this.inSet,
    required this.at,
    required this.by,
    this.round = 0,
    this.seq = 0,
    this.extra = const {},
  });

  Map<String, dynamic> toJson() => {
        ...extra,
        'display': display,
        'in': inSet,
        'at': isoUtc(at),
        'by': by,
        if (round > 0) 'round': round,
        if (seq > 0) 'seq': seq,
      };

  factory ReviewAttention.fromJson(String display, Map<String, dynamic> j) =>
      ReviewAttention(
        display: display,
        inSet: j['in'] as bool? ?? false,
        at: DateTime.tryParse(j['at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        by: j['by'] as String? ?? '',
        round: (j['round'] as num? ?? 0).toInt(),
        seq: (j['seq'] as num? ?? 0).toInt(),
        extra: _extrasOf(
            j, const {'display', 'in', 'at', 'by', 'round', 'seq'}),
      );
}

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

/// A comment's stable identity, as 16 hex chars.
///
/// The SAME material the union merge keys on (see `_commentKey`), so two
/// comments sharing an identity are by construction the same comment —
/// which is what makes it safe to record "the viewer has been shown
/// this one" against it. A collision would be a false "seen", and the
/// merge already depends on this material not colliding, so nothing new
/// is being trusted.
///
/// Hashed rather than kept raw because callers hold SETS of these and a
/// body can be a pasted stack trace.
String reviewCommentIdentity(ReviewComment c) => hex64(lineContentHash(
    '${c.author.display}\u0000${isoUtc(c.at)}\u0000${c.body}'));

int _byAtAuthorBody(Map<String, dynamic> a, Map<String, dynamic> b) {
  // seq first, but ONLY when both sides carry one.
  //
  // Same principle as the merge policy's ranked majors: an absent field
  // makes a pair unrankable by it, not lowest-ranked by it. "Present
  // beats absent" looks right until you notice the two cases it cannot
  // tell apart — a NEW reply into an OLD thread, and an OLD reply into a
  // NEW one — are the same shape in the record. Ranking present-first
  // gets the first right and sorts the second before the comments it
  // answers, which the turn fold then reads as the wrong last word.
  //
  // No rule decides both, because the record does not distinguish them.
  // So: rank when both writers used the scheme, and otherwise fall to
  // the timestamp, which is the only thing both of them produced.
  // Ordering across clients that do not share a sequencing scheme is
  // best-effort by time, and saying so is more useful than a rule that
  // is confidently wrong half the time.
  final an = a['seq'];
  final bn = b['seq'];
  final aseq = an is num ? an.toInt() : 0;
  final bseq = bn is num ? bn.toInt() : 0;
  if (aseq > 0 && bseq > 0 && aseq != bseq) return aseq.compareTo(bseq);
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
  // Union with explicit removals, exactly as the dossier specifies: a
  // person's standing is per-key LWW on `at`, and `in: false` is a
  // tombstone that can WIN. Dropping the key on removal would make
  // "alice took herself out" lose to any peer who still had her in,
  // because absence carries no timestamp to compare.
  'attention': PerKeyMap(LwwTs('at', majors: ['round', 'seq'])),
});

// ─── Who is in this conversation ──────────────────────────────────────

/// Everyone who has acted as a reviewer here — never the author.
///
/// Derived from the record, so every clone names the same set without
/// coordinating: there is no reviewer ROSTER to fall out of sync, and
/// nobody can be a reviewer without a verdict or a comment proving it.
Set<String> reviewersOf(ReviewState s, String authorDisplay) {
  final out = <String>{};
  for (final v in s.verdicts) {
    if (v.by.display != authorDisplay) out.add(v.by.display);
  }
  for (final t in s.threads) {
    for (final c in t.comments) {
      if (c.author.display != authorDisplay && c.kind == 'human') {
        out.add(c.author.display);
      }
    }
  }
  return out;
}

/// Reviewers plus the author: everyone the review could be handed to.
///
/// Author first, then reviewers alphabetically. The order is fixed
/// rather than by-appearance because this feeds a row of controls, and
/// controls that reshuffle between reads are controls you misclick.
List<String> participantsOf(ReviewState s, String authorDisplay) {
  final reviewers = reviewersOf(s, authorDisplay).toList()..sort();
  return [if (authorDisplay.isNotEmpty) authorDisplay, ...reviewers];
}

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
/// N-PARTY, per person. Speaking at the current round settles your own
/// obligation and nobody else's; the author owes an answer while any
/// unresolved thread's last word is somebody else's; and the author's
/// reply re-obligates the reviewer it answered. So a reviewer who has
/// approved stops being told it is their turn, the author's "waiting on"
/// names only who is actually blocking, and a review that is blocked on
/// no one can say so — none of which the previous author-vs-reviewers
/// bloc could express.
ReviewTurnState deriveTurn(
  ReviewState state, {
  required String authorDisplay,
  required String viewerDisplay,
}) {
  // The STORED attention set wins whenever it has been maintained.
  //
  // The fold below can only ever produce one answer for everybody, and
  // it can never represent a person putting themselves in or taking
  // themselves out — a decision no history of past events contains. The
  // set holds a per-person answer and survives a hand-back, so once it
  // exists it is the truth and the fold is merely how it got seeded.
  //
  // Absence is not emptiness: a doc written before attention existed,
  // or one where everyone has been explicitly cleared, falls through to
  // the fold rather than claiming the review waits on nobody.
  final blocked = state.attentionOn;
  if (blocked.isNotEmpty) {
    final mine = blocked.contains(viewerDisplay);
    return ReviewTurnState(
      yourTurn: mine,
      // Nothing to name when the ball is yours; otherwise name everyone
      // holding it, whether the viewer is the author or a fellow
      // reviewer — "waiting on carol" is the useful sentence in both
      // seats.
      waitingOn: mine ? '' : blocked.join(', '),
    );
  }
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
    // review waits on a reviewer, and the only one we can name is
    // whoever is reading.
    final isAuthor = viewerDisplay == authorDisplay;
    return ReviewTurnState(
      yourTurn: !isAuthor,
      waitingOn: isAuthor ? '' : viewerDisplay,
    );
  }


  // ── The per-person fold ─────────────────────────────────────────
  //
  // This used to be TWO-PARTY: author ↔ reviewers as a bloc, which
  // could not express "cara still owes a look while bob is done". With
  // one reviewer that is invisible; with two it is the first thing you
  // notice, because a reviewer who has already approved keeps being told
  // it is their turn and the author's "waiting on" names people who are
  // not blocking anything.
  //
  // The two questions the bloc version left open, now answered:
  //
  //   Does one reviewer's approval move the ball while another has not
  //   looked?  YES — per person. Speaking at the current round settles
  //   your obligation and nobody else's.
  //
  //   Does the author's reply re-obligate the reviewer who commented?
  //   YES, and ONLY the author's. A reviewer whose point was answered
  //   owes an answer back; reviewer-to-reviewer discussion obligates
  //   nobody, or a busy thread would keep everyone permanently on the
  //   hook and never settle.
  //
  // Both rules are per-person and monotone, so the set drains: reviewer
  // speaks -> author owes -> author answers -> that reviewer owes ->
  // they resolve -> nobody owes. An empty set is a real answer ("this is
  // not blocked on anyone") that the bloc fold could not produce, since
  // it always named somebody.
  // ROUNDS, not timestamps, for every cross-person comparison.
  //
  // `at` is stamped by whichever machine wrote the record, from its own
  // wall clock. Comparing two people's stamps therefore compares two
  // computers' clocks, and the review lab reproduced what that costs the
  // first time a test asked "has cara spoken since round 2 was cut": her
  // round-1 comment carried a LATER stamp than the round-2 cut, because
  // her clock was ahead, so she looked settled on code she had never
  // seen. A round number comes from the shared ref, so every machine
  // compares the same integers.
  //
  // Ordering WITHIN one thread still uses `at` — those comments are a
  // conversation, and its order is what the participants saw.
  final latest = state.latestRound?.n ?? 0;

  /// The highest round this person has spoken at, or -1 if never.
  int spokeAt(String who) {
    var high = -1;
    for (final t in state.threads) {
      for (final c in t.comments) {
        if (c.author.display == who && c.round > high) high = c.round;
      }
    }
    for (final v in state.verdicts) {
      if (v.by.display == who && v.round > high) high = v.round;
    }
    return high;
  }

  /// The last word in a thread, causally.
  ///
  /// seq before `at`, for the reason on [ReviewComment.seq]: the opener
  /// and the reply come from different machines, so a reply written later
  /// can carry an earlier stamp. Ranking on `at` alone had this fold
  /// deciding the author had not answered a comment they had just
  /// answered — which then left the author owed and the reviewer free,
  /// the exact opposite of the truth.
  /// Is [a] causally after [b], within one thread?
  ///
  /// Same rule as the union's comparator, and it has to BE the same rule:
  /// a fold that ordered comments differently from the way they are
  /// stored and rendered would decide the turn from a sequence the humans
  /// never saw. See `_byAtAuthorBody` for why ranking requires BOTH sides
  /// to carry a sequence.
  bool after(ReviewComment a, ReviewComment b) {
    if (a.seq > 0 && b.seq > 0 && a.seq != b.seq) return a.seq > b.seq;
    return a.at.isAfter(b.at);
  }

  ReviewComment latestOf(List<ReviewComment> cs) =>
      cs.reduce((a, b) => after(b, a) ? b : a);

  final owed = <String>{};

  // Has ANYBODY spoken at the current round? This replaces comparing the
  // newest round's cutAt against the newest human stamp — same question,
  // no clocks. If nobody has spoken since the code landed, the code
  // moved last.
  final someoneSpokeThisRound = latest > 0 &&
      [authorDisplay, ...reviewers].any((who) => spokeAt(who) >= latest);
  // With no round ever cut there is no code event to be newest, so the
  // obligations below are decided entirely by the conversation. (The
  // clock comparison this replaced could not fire in that state either,
  // but it was a wall-clock read left inside a fold whose whole point is
  // that it does not make them.)
  final codeIsNewest = latest > 0 && !someoneSpokeThisRound;

  // The author's obligation: open feedback nobody has answered.
  //
  // Suppressed when the code is the newest thing to happen — the author
  // has just delivered, and new code awaits review whoever pushed it.
  // Without this a push would leave the author owing a text reply to a
  // comment they may have just fixed, and the "waiting on" would point
  // backwards.
  if (!codeIsNewest) {
    for (final t in state.threads) {
      if (!t.unresolved || t.comments.isEmpty) continue;
      if (latestOf(t.comments).author.display != authorDisplay) {
        owed.add(authorDisplay);
        break;
      }
    }
    // A blocking verdict from a round the author has not answered is an
    // obligation even with every thread resolved: "changes requested"
    // with nothing open still means changes are requested.
    final authorSpokeAt = spokeAt(authorDisplay);
    for (final v in state.verdicts) {
      if (v.verdict != 'CHANGES_REQUESTED') continue;
      if (v.by.display == authorDisplay) continue;
      if (v.round >= authorSpokeAt) {
        owed.add(authorDisplay);
        break;
      }
    }
  }

  // Each reviewer's obligation, one at a time.
  for (final r in reviewers) {
    final theirRound = spokeAt(r);
    // Never spoke, or has not spoken at the current round: there is code
    // they have not looked at.
    if (latest > 0 && theirRound < latest) {
      owed.add(r);
      continue;
    }
    // Spoke at this round, but the AUTHOR answered them afterwards.
    // Within a thread `at` is the right order — one conversation, and
    // its participants saw it in this sequence.
    for (final t in state.threads) {
      if (!t.unresolved || t.comments.isEmpty) continue;
      final mine = t.comments.where((c) => c.author.display == r).toList();
      if (mine.isEmpty) continue;
      final last = latestOf(t.comments);
      if (last.author.display == authorDisplay &&
          after(last, latestOf(mine))) {
        owed.add(r);
        break;
      }
    }
  }

  final mine = owed.contains(viewerDisplay);
  final naming = owed.toList()..sort();
  return ReviewTurnState(
    yourTurn: mine,
    // Same convention as the stored-set branch above: nothing to name
    // when the ball is yours.
    waitingOn: mine ? '' : naming.join(', '),
  );
}
