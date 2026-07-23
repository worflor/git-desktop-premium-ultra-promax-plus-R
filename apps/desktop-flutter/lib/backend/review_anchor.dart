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
String _hex64(int v) {
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
    ctx.add(_hex64(lineSimHash(lines[i])));
  }
  return ReviewAnchor(
    round: round,
    commit: commit,
    path: path,
    side: side,
    line: lineIndex + 1,
    lineHash: _hex64(lineContentHash(text)),
    simHash: _hex64(lineSimHash(text)),
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
