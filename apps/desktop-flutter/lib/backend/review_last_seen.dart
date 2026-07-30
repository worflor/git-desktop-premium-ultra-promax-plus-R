// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_last_seen.dart — what this machine has already been shown.
//
// Client-local and never synced: which comments a person has read is
// theirs, not the review's, and pushing it would put reading habits on a
// shared remote. Lives HERE rather than beside the pane controller
// because it is persistence, and the app layer needs it too — a desk PR
// being abandoned has to forget its review's local state, and having
// `lib/app` reach into a feature's controller to do that inverted the
// layering for the sake of one class.

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'review_records.dart';

/// Client-local "last look" pointers: {repoPath#deskId: round}. A
/// display-law persistence (a fact about what the viewer has seen),
/// not a task posture — deliberately NOT synced in this slice; the
/// dossier's synced-attention bit replaces the storage, not the shape.
class ReviewLastSeen {
  static const _kKey = 'review.last_seen_round_v1';

  /// The legacy sequence pointer, read ONCE to seed the seen set and
  /// never written again. See [seedSeen].
  static const _kSeqKey = 'review.last_seen_seq_v1';

  /// Identities of the comments this viewer has been shown, per desk.
  ///
  /// A SET, because a read frontier over a partial order is a set. The
  /// scalar this replaced could not distinguish a concurrent peer's
  /// comment from the very comment that defined the cursor — they carry
  /// the same sequence number — and had to guess at ties in a direction
  /// that was wrong either way.
  ///
  /// Client-local and never synced, like the round pointer beside it.
  /// Not pruned: a review holds hundreds of comments and an identity is
  /// 16 bytes, so this is kilobytes per desk. The obvious pruning rule —
  /// "the head moved to round N+1, so everything at N is seen" — is
  /// UNSAFE: a peer publishing from a doc that predates the cut stamps
  /// round N and arrives afterwards, and collapsing would mark it read
  /// without ever showing it.
  static const _kSeenKey = 'review.seen_comments_v1';

  /// Writes queue. Every desk's pointer lives in ONE prefs key, so two
  /// desks advancing at once (publish here, caught-up there) would each
  /// write back a whole map read before the other's change — last write
  /// silently reverting the first. Same read-modify-write hazard the
  /// git index has, same answer: serialize.
  static Future<void> _writeGate = Future<void>.value();

  // JSON-encoded pair, not '<path>#<id>': a repo path may itself contain
  // '#', which would let two different repos collide on one pointer.
  static String _entryKey(String repoPath, int deskId) =>
      jsonEncode([repoPath, deskId]);

  static Future<Map<String, int>> _readAll([String key = _kKey]) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return {};
      return {
        for (final e in j.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toInt(),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<int?> read({
    required String repoPath,
    required int deskId,
  }) async =>
      (await _readAll())[_entryKey(repoPath, deskId)];

  /// The identities this viewer has already been shown for this desk.
  static Future<Set<String>> readSeen({
    required String repoPath,
    required int deskId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSeenKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return {};
      final xs = j[_entryKey(repoPath, deskId)];
      if (xs is! List) return {};
      return {for (final x in xs) if (x is String) x};
    } catch (_) {
      return {};
    }
  }

  /// Record that these identities have been shown. Union, never replace:
  /// two panes on one desk must not erase each other's reading.
  static Future<void> addSeen({
    required String repoPath,
    required int deskId,
    required Iterable<String> identities,
  }) {
    final prior = _writeGate;
    final mine = Completer<void>();
    _writeGate = mine.future;
    return prior.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> all;
      try {
        final j = jsonDecode(prefs.getString(_kSeenKey) ?? '{}');
        all = j is Map ? j.cast<String, dynamic>() : <String, dynamic>{};
      } catch (_) {
        all = <String, dynamic>{};
      }
      final key = _entryKey(repoPath, deskId);
      final existing = all[key];
      final merged = <String>{
        if (existing is List)
          for (final x in existing)
            if (x is String) x,
        ...identities,
      };
      all[key] = merged.toList()..sort();
      await prefs.setString(_kSeenKey, jsonEncode(all));
    }).whenComplete(mine.complete);
  }

  /// Drop a desk's reading entirely — for a review that is gone.
  static Future<void> forget({
    required String repoPath,
    required int deskId,
  }) {
    final prior = _writeGate;
    final mine = Completer<void>();
    _writeGate = mine.future;
    return prior.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      try {
        final j = jsonDecode(prefs.getString(_kSeenKey) ?? '{}');
        if (j is! Map) return;
        final all = j.cast<String, dynamic>()
          ..remove(_entryKey(repoPath, deskId));
        await prefs.setString(_kSeenKey, jsonEncode(all));
      } catch (_) {}
    }).whenComplete(mine.complete);
  }

  /// Build the initial seen set from the legacy scalar cursor.
  ///
  /// One-time, on the first load after upgrading. Fidelity is exactly
  /// what the old ladder claimed — everything at an earlier round, plus
  /// everything at the last-seen round up to the sequence recorded — and
  /// exact from then on. An install with no legacy pointer starts empty,
  /// which reads as "all of this is new", the right answer for a review
  /// this viewer has genuinely never opened.
  ///
  /// Persisted immediately so the seeding happens once rather than on
  /// every load.
  static Future<Set<String>> seedSeen({
    required String repoPath,
    required int deskId,
    required ReviewState state,
    required int lastSeenRound,
    required int lastSeenSeq,
  }) async {
    final seen = <String>{
      for (final t in state.threads)
        for (final c in t.comments)
          if (c.round < lastSeenRound ||
              (c.round == lastSeenRound && c.seq <= lastSeenSeq))
            reviewCommentIdentity(c),
    };
    if (seen.isNotEmpty) {
      await addSeen(repoPath: repoPath, deskId: deskId, identities: seen);
    }
    return seen;
  }

  /// The legacy sequence pointer. Read only by [seedSeen].
  ///
  /// Stored as `[round, seq]` and returned ONLY when that round still
  /// matches the round pointer. The two live in separate prefs keys and
  /// therefore in separate writes: a crash between them leaves a new
  /// round beside a stale sequence, and a stale sequence that happens to
  /// be higher than anything in the new round marks its comments read.
  /// Carrying the round inside the value makes that torn state
  /// self-correcting rather than silently wrong — a mismatch reads as
  /// "nothing seen yet in this round", which can only over-report.
  static Future<int> readSeq({
    required String repoPath,
    required int deskId,
    required int round,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSeqKey);
    if (raw == null || raw.isEmpty) return 0;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return 0;
      final pair = j[_entryKey(repoPath, deskId)];
      if (pair is! List || pair.length != 2) return 0;
      final at = pair[0];
      final seq = pair[1];
      if (at is! num || seq is! num || at.toInt() != round) return 0;
      return seq.toInt();
    } catch (_) {
      return 0;
    }
  }

  static Future<void> write({
    required String repoPath,
    required int deskId,
    required int round,
    int seq = 0,
  }) {
    final prior = _writeGate;
    final mine = Completer<void>();
    _writeGate = mine.future;
    return prior.then((_) async {
      final key = _entryKey(repoPath, deskId);
      final prefs = await SharedPreferences.getInstance();
      final rounds = await _readAll();
      rounds[key] = round;
      Map<String, dynamic> seqs;
      try {
        final j = jsonDecode(prefs.getString(_kSeqKey) ?? '{}');
        seqs = j is Map ? j.cast<String, dynamic>() : <String, dynamic>{};
      } catch (_) {
        seqs = <String, dynamic>{};
      }
      // The sequence carries the round it belongs to, so the two keys
      // cannot be read as a matched pair when only one of them landed.
      seqs[key] = [round, seq];
      // Sequence FIRST. If only one write survives a crash it must be
      // this one: a sequence tagged with a round the pointer has not
      // reached yet is ignored on read, whereas a new round pointer
      // beside an untagged old sequence would hide that round's
      // comments.
      await prefs.setString(_kSeqKey, jsonEncode(seqs));
      await prefs.setString(_kKey, jsonEncode(rounds));
    }).whenComplete(mine.complete);
  }
}
