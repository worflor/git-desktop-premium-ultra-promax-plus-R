// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_anchor.dart — content-anchored comment positions.
//
// A review comment pins to WHAT a line is, not where it sits: the
// anchor captures the line's exact content hash, its fuzzy SimHash,
// and the SimHashes of its ±4 neighbours (the LHDiff recipe's context
// term), plus the round/commit it was made against for the honest
// fallback. Resolution ladder (dossier §6.3):
//
//   1. EXACT — a line with the identical content hash exists; same
//      position → anchored, moved → re-anchored (provenance shown).
//   2. (next slice) RHYME — SimHash + context Hamming search.
//   3. OUTDATED — pin to the round the anchor last resolved in. Never
//      silently wrong, never silently dropped.
//
// Hashes are persisted as fixed-width hex STRINGS: a 64-bit value can
// exceed JSON's 2^53 safe-integer range, and hex round-trips exactly
// everywhere. Both hash functions are deterministic by construction
// (FNV-1a over UTF-8; trigram SimHash) — no `hashCode` anywhere, so
// persisted anchors stay valid across platforms and app versions.

import 'dart:convert';

import '../features/diff/diff_models.dart' show ParsedLine;

/// How many neighbour lines on EACH side contribute context hashes.
const int kAnchorContextRadius = 4;

/// FNV-1a 64-bit over the UTF-8 bytes of [line]. Exact content
/// identity — stable, well-known, and independent of Dart's hashCode.
///
/// CONTRACT: this app runs on the Dart VM, where `int` is a fixed
/// 64-bit two's-complement value and multiplication WRAPS at 64 bits —
/// the accumulator can never "grow beyond 64 bits" (that is a dart2js
/// hazard this desktop app does not have; the diff engine's SplitMix64
/// relies on the same semantics). The canonical-hex law (anchor fuzz
/// A6) pins the resulting 16-char serialization on every run.
int lineContentHash(String line) {
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(line)) {
    h ^= b;
    h = (h * 0x100000001b3);
  }
  return h;
}

/// The line's fuzzy fingerprint — the diff engine's own trigram
/// SimHash, over the lowercased line, so anchor hashes live in the
/// same space as diff-line hashes.
int lineSimHash(String line) => ParsedLine.simHashOf(line.toLowerCase());

/// Canonical fixed-width unsigned hex for a 64-bit value. Built from
/// 32-bit halves: on the VM `toUnsigned(64)` is an IDENTITY for
/// negative ints (2^64+v isn't representable), so the naive
/// `toRadixString` emits a MINUS-SIGNED string — round-trippable by our
/// own parser but a format violation any third-party implementation
/// would choke on (caught by the manifold review + empirical check).
String hex64(int v) {
  final hi = (v >>> 32).toRadixString(16).padLeft(8, '0');
  final lo = (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '$hi$lo';
}

/// Parse canonical 16-char unsigned hex back to the VM's signed 64-bit
/// space. Halves again: `int.tryParse` refuses hex above 2^63-1, so a
/// single-shot parse would reject exactly the values negative hashes
/// produce.
int? _fromHex64(String? s) {
  if (s == null || s.length != 16) return null;
  final hi = int.tryParse(s.substring(0, 8), radix: 16);
  final lo = int.tryParse(s.substring(8), radix: 16);
  if (hi == null || lo == null) return null;
  return (hi << 32) | lo;
}

/// Where a comment is pinned. Immutable once captured.
class ReviewAnchor {
  /// Round the anchor was made against, and that round's pinned commit.
  final int round;
  final String commit;
  final String path;

  /// 'new' | 'old' — which side of the round's diff the line is on.
  final String side;

  /// 1-based line number in [commit]'s version of [path].
  final int line;

  /// FNV-1a 64 of the exact line content, hex.
  final String lineHash;

  /// Trigram SimHash of the lowercased line, hex.
  final String simHash;

  /// SimHashes of the ±[kAnchorContextRadius] neighbours, in order,
  /// absent lines omitted. Reserved for the rhyme layer.
  final List<String> ctx;

  /// The line verbatim, for display and last-resort human orientation.
  final String excerpt;

  /// Unknown fields from foreign writers, preserved verbatim.
  final Map<String, dynamic> extra;

  const ReviewAnchor({
    required this.round,
    required this.commit,
    required this.path,
    required this.side,
    required this.line,
    required this.lineHash,
    required this.simHash,
    required this.ctx,
    required this.excerpt,
    this.extra = const {},
  });

  Map<String, dynamic> toJson() => {
        ...extra,
        'round': round,
        'commit': commit,
        'path': path,
        'side': side,
        'line': line,
        'lineHash': lineHash,
        'simHash': simHash,
        'ctx': ctx,
        'excerpt': excerpt,
      };

  factory ReviewAnchor.fromJson(Map<String, dynamic> j) => ReviewAnchor(
        round: (j['round'] as num? ?? 0).toInt(),
        commit: j['commit'] as String? ?? '',
        path: j['path'] as String? ?? '',
        side: j['side'] as String? ?? 'new',
        line: (j['line'] as num? ?? 0).toInt(),
        lineHash: j['lineHash'] as String? ?? '',
        simHash: j['simHash'] as String? ?? '',
        ctx: (j['ctx'] as List? ?? const []).whereType<String>().toList(),
        excerpt: j['excerpt'] as String? ?? '',
        extra: {
          for (final e in j.entries)
            if (!const {
              'round', 'commit', 'path', 'side', 'line', 'lineHash',
              'simHash', 'ctx', 'excerpt',
            }.contains(e.key))
              e.key: e.value,
        },
      );
}

/// Capture an anchor for [lineIndex] (0-based) of [lines] — the
/// content of [path] at [commit], which is round [round]'s snapshot.
ReviewAnchor captureAnchor({
  required List<String> lines,
  required int lineIndex,
  required int round,
  required String commit,
  required String path,
  String side = 'new',
}) {
  RangeError.checkValidIndex(lineIndex, lines, 'lineIndex');
  final text = lines[lineIndex];
  final ctx = <String>[];
  for (var d = -kAnchorContextRadius; d <= kAnchorContextRadius; d++) {
    if (d == 0) continue;
    final i = lineIndex + d;
    if (i < 0 || i >= lines.length) continue;
    ctx.add(hex64(lineSimHash(lines[i])));
  }
  return ReviewAnchor(
    round: round,
    commit: commit,
    path: path,
    side: side,
    line: lineIndex + 1,
    lineHash: hex64(lineContentHash(text)),
    simHash: hex64(lineSimHash(text)),
    ctx: ctx,
    excerpt: text,
  );
}

enum AnchorStatus {
  /// Identical content at the identical position.
  anchored,

  /// Identical content found at a different position — provenance is
  /// surfaced, never silent.
  reanchored,

  /// The content no longer exists in this version; the anchor pins to
  /// its recorded round instead.
  outdated,
}

class AnchorResolution {
  final AnchorStatus status;

  /// 1-based line in the NEW version, when [status] is not outdated.
  final int? line;

  const AnchorResolution(this.status, this.line);
}

/// Resolve [anchor] against a NEW version of its file ([lines]).
/// Exact-content pass only (the rhyme layer is the next slice): all
/// lines whose content hash equals the anchor's are candidates, the
/// one nearest the recorded position wins. No candidate → outdated.
AnchorResolution resolveAnchor(ReviewAnchor anchor, List<String> lines) {
  final want = _fromHex64(anchor.lineHash);
  if (want == null) return const AnchorResolution(AnchorStatus.outdated, null);
  int? best;
  for (var i = 0; i < lines.length; i++) {
    if (lineContentHash(lines[i]) != want) continue;
    final lineNo = i + 1;
    if (lineNo == anchor.line) {
      return AnchorResolution(AnchorStatus.anchored, lineNo);
    }
    if (best == null ||
        (lineNo - anchor.line).abs() < (best - anchor.line).abs()) {
      best = lineNo;
    }
  }
  if (best == null) {
    return const AnchorResolution(AnchorStatus.outdated, null);
  }
  return AnchorResolution(AnchorStatus.reanchored, best);
}

// ─── What a comment is ABOUT ──────────────────────────────────────────

/// The subject of a thread: a line, a file, or the change itself.
///
/// Every thread used to carry a required [ReviewAnchor], which made a
/// line the only thing a review could be about. That is not how people
/// review: the first thing a reviewer usually wants to say is "this is
/// two changes in one branch", which is about none of the lines and all
/// of them. Before this existed the only way to say it was to pin it to
/// an arbitrary line — a lie about what was meant — or to a verdict,
/// which carries no words at all.
///
/// SEALED, so every reader is forced to be exhaustive. The obvious
/// alternative — making the anchor nullable — was rejected: `null`
/// cannot distinguish "about the whole change" from "about this file",
/// and it would make the adapter's file grouping partial in a way the
/// compiler could not see. A scope tells you which of the three kinds
/// of subject you are holding, and there is no fourth.
sealed class ReviewScope {
  const ReviewScope();

  /// Round this scope was captured against, and that round's commit.
  /// Both scopes above a line still name a snapshot: "this file should
  /// not exist" is a claim about a particular version of the tree.
  int get round;
  String get commit;

  /// The file this is about, or `''` for the change as a whole. The
  /// adapter groups on this, so `''` is what keeps a review-wide thread
  /// out of the file list rather than at the top of it under a blank
  /// heading.
  String get path;

  Map<String, dynamic> toJson();

  /// Same SUBJECT, ignoring which round it was captured against.
  ///
  /// "Is this the composer I opened?" is a question about the subject,
  /// not about the pin: a round cut while someone was typing re-captures
  /// the scope, and an identity or round-sensitive comparison would then
  /// fail to close the composer whose save just landed. Kinds never
  /// match across each other, so a file comment and a line comment on
  /// the same path stay distinct composers.
  bool sameSubject(ReviewScope other) => switch ((this, other)) {
        (LineScope(anchor: final a), LineScope(anchor: final b)) =>
          a.path == b.path && a.side == b.side && a.line == b.line,
        (FileScope(path: final p1, side: final s1),
              FileScope(path: final p2, side: final s2)) =>
          p1 == p2 && s1 == s2,
        (WholeScope(), WholeScope()) => true,
        _ => false,
      };

  /// Read a scope out of a thread or draft record.
  ///
  /// Accepts BOTH shapes on purpose. `scope` wins when present; a record
  /// carrying only `anchor` is every document written before scopes
  /// existed, and is read as a [LineScope] — so no migration runs, no
  /// schema version moves, and no older client is locked out. (Bumping
  /// [kReviewSchemaVersion] would have been a hard fork: the store
  /// REFUSES a doc from a higher version outright.)
  ///
  /// A record with neither is malformed rather than absent; it reads as
  /// a zero [LineScope], exactly as a missing `anchor` did before, so a
  /// corrupt entry degrades instead of throwing inside a merge.
  ///
  /// WHAT AN OLDER CLIENT SEES, decided deliberately and pinned by test
  /// rather than left to be re-argued:
  ///
  ///   * a LINE thread is byte-identical to what it always was — the
  ///     bare `anchor`, fully readable (`K8`);
  ///   * a FILE thread carries a legacy anchor naming its file at line 0,
  ///     so an old client shows the right file rather than a blank one
  ///     (`K8b`);
  ///   * a WHOLE-change thread has no path to name and reads as a zero
  ///     anchor there. Inventing a path would file a comment about the
  ///     change under a file nobody wrote it about, which is worse than
  ///     showing nothing;
  ///   * whatever an old client cannot read, it PRESERVES — the scope
  ///     survives a round trip through it (`S7`).
  ///
  /// The alternative, a schema-version gate, was rejected: [ReviewStore]
  /// REFUSES a document from a higher version outright, so bumping would
  /// stop older clients reading the review at all rather than reading
  /// most of it. Partial legibility beats a hard fork.
  static ReviewScope fromJson(Map<String, dynamic> j) {
    final raw = j['scope'];
    if (raw is Map) {
      final s = raw.cast<String, dynamic>();
      final round = (s['round'] as num? ?? 0).toInt();
      final commit = s['commit'] as String? ?? '';
      switch (s['kind'] as String? ?? '') {
        case 'file':
          return FileScope(
            path: s['path'] as String? ?? '',
            side: s['side'] as String? ?? 'new',
            round: round,
            commit: commit,
          );
        case 'review':
          return WholeScope(round: round, commit: commit);
        // 'line', or a kind from a future writer: fall through to the
        // anchor, which a well-formed line scope also carries.
      }
    }
    return LineScope(ReviewAnchor.fromJson(
        (j['anchor'] as Map?)?.cast<String, dynamic>() ?? const {}));
  }

  /// The keys [fromJson] consumes, for the `extra` passthrough that
  /// preserves a foreign writer's fields.
  static const Set<String> jsonKeys = {'scope', 'anchor'};
}

/// A comment on one line of one side of one file — the original and
/// still the common case.
///
/// Serializes as a bare `anchor`, byte-identical to what every existing
/// document holds, so adding scopes changed no stored bytes for any
/// thread that already existed.
final class LineScope extends ReviewScope {
  const LineScope(this.anchor);
  final ReviewAnchor anchor;

  @override
  int get round => anchor.round;
  @override
  String get commit => anchor.commit;
  @override
  String get path => anchor.path;

  @override
  Map<String, dynamic> toJson() => {'anchor': anchor.toJson()};
}

/// A comment on a file as a whole — "this file should not exist", "the
/// whole thing wants to move under services/".
///
/// [side] carries which version is meant, so a comment on a DELETED
/// file resolves against the merge base rather than reading as outdated
/// the moment it is written (the same reason line anchors are sided).
final class FileScope extends ReviewScope {
  const FileScope({
    required this.path,
    required this.side,
    required this.round,
    required this.commit,
  });

  @override
  final String path;
  final String side;
  @override
  final int round;
  @override
  final String commit;

  /// Carries a legacy-shaped `anchor` ALONGSIDE the scope.
  ///
  /// Not redundancy and not a lie: line 0 is not a line, so a client old
  /// enough to read only `anchor` shows this thread against the right
  /// FILE instead of against a blank path — which is what an absent
  /// anchor degrades to. New clients never read it; [ReviewScope.fromJson]
  /// prefers `scope` and only falls back when there is no scope at all.
  ///
  /// A whole-change scope deliberately does NOT do this: there is no path
  /// it could name without inventing one, and inventing one is how a
  /// review-wide comment would end up filed under a file nobody wrote it
  /// about.
  @override
  Map<String, dynamic> toJson() => {
        'scope': {
          'kind': 'file',
          'path': path,
          'side': side,
          'round': round,
          'commit': commit,
        },
        'anchor': ReviewAnchor(
          round: round,
          commit: commit,
          path: path,
          side: side,
          line: 0,
          lineHash: '',
          simHash: '',
          ctx: const [],
          excerpt: '',
        ).toJson(),
      };
}

/// A comment on the change itself. The summary conversation — the one a
/// reviewer opens with and an author answers first.
///
/// Deliberately a THREAD and not a new kind of object: being a thread is
/// what makes it drafted before it is public, published in the same turn
/// as a verdict, resolvable when it has been dealt with, counted as
/// unread since your last look, and folded into whose turn it is. A
/// dedicated "summary" field would have had to re-earn every one of
/// those, and would have disagreed with the line threads about at least
/// one of them.
final class WholeScope extends ReviewScope {
  const WholeScope({required this.round, required this.commit});

  @override
  final int round;
  @override
  final String commit;

  /// Empty by construction: the change as a whole is not a file.
  @override
  String get path => '';

  @override
  Map<String, dynamic> toJson() => {
        'scope': {'kind': 'review', 'round': round, 'commit': commit},
      };
}
