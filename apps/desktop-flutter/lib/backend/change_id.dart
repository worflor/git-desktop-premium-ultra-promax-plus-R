// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// change_id.dart — stable change identity for commits
//
// Implements the `change-id` git commit header standardized between
// Jujutsu, GitButler, and Gerrit: a 16-byte identity rendered as a
// 32-character reverse-hex string (nibble 0 → 'z' … nibble 15 → 'k',
// alphabet "zyxwvutsrqponmlk") that stays constant while a commit is
// amended/rebased THROUGH tools that preserve it. Reverse-hex exists so
// a change id can never be mistaken for a commit sha.
//
// Empirical contract (git 2.52, verified 2026-07-22, matching jj's
// git-compatibility.md): git accepts the header via `hash-object -t
// commit` and fsck stays clean; object transfer (clone/push/fetch)
// preserves it by content addressing; `git commit --amend` PRESERVES
// unknown headers (both message-only and content amends — git copies
// extra headers forward, excluding gpgsig); but `rebase` (both
// backends) and `cherry-pick` drop them. Stability across history
// rewrites is therefore as good as the tool driving them — which is why
// this module exists: Manifold stamps its own commits and carries
// identity through its own rewrite flows. Foreign commits get the
// jj-compatible synthetic fallback ([syntheticChangeIdForCommit]) so
// every commit always has SOME stable-for-its-lifetime id.
//
// This file is pure byte/string algebra — no I/O, no git. The plumbing
// that reads/stamps real commits lives in git.dart so it rides the
// GitSpawn seam like every other git call.

import 'dart:math';
import 'dart:typed_data';

/// Number of identity bytes; renders as 2× this many reverse-hex chars.
const int kChangeIdBytes = 16;

/// Rendered length of a change id (32).
const int kChangeIdLength = kChangeIdBytes * 2;

/// The commit-header key, per the jj/GitButler/Gerrit agreement.
const String kChangeIdHeader = 'change-id';

/// Reverse-hex "digits": nibble value is the index — 0 → 'z', 15 → 'k'.
/// Byte-identical to jj's `REVERSE_HEX_CHARS`.
const String _kReverseHexChars = 'zyxwvutsrqponmlk';

/// A validated 32-character reverse-hex change id.
///
/// The representation IS the wire form (what goes after `change-id ` in
/// the commit header). Construction validates; everything downstream can
/// trust the shape.
extension type const ChangeId._(String value) implements Object {
  /// Parses [raw], throwing [FormatException] on anything that is not
  /// exactly [kChangeIdLength] reverse-hex characters.
  factory ChangeId.parse(String raw) {
    final id = ChangeId.tryParse(raw);
    if (id == null) {
      throw FormatException('not a $kChangeIdLength-char reverse-hex id', raw);
    }
    return id;
  }

  /// [ChangeId.parse] that returns null instead of throwing.
  ///
  /// Case-insensitive on input — jj's decoder accepts both `k-z` and
  /// `K-Z` — but the canonical [value] is always lowercase, which is
  /// what jj's writer emits and what its `--new-change-id` validator
  /// (`^[k-z]*$`) accepts.
  static ChangeId? tryParse(String raw) {
    if (raw.length != kChangeIdLength) return null;
    var needsLower = false;
    for (var i = 0; i < raw.length; i++) {
      var c = raw.codeUnitAt(i);
      // 'K' (0x4b) … 'Z' (0x5a) reads fine; canonicalize below.
      if (c >= 0x4b && c <= 0x5a) {
        needsLower = true;
        c += 0x20;
      }
      // 'k' (0x6b) … 'z' (0x7a) — the alphabet is a contiguous range.
      if (c < 0x6b || c > 0x7a) return null;
    }
    return ChangeId._(needsLower ? raw.toLowerCase() : raw);
  }

  /// Encodes exactly [kChangeIdBytes] raw bytes.
  factory ChangeId.fromBytes(List<int> bytes) {
    if (bytes.length != kChangeIdBytes) {
      throw ArgumentError.value(
          bytes.length, 'bytes', 'must be exactly $kChangeIdBytes bytes');
    }
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(_kReverseHexChars[(b >> 4) & 0xf]);
      sb.write(_kReverseHexChars[b & 0xf]);
    }
    return ChangeId._(sb.toString());
  }

  /// The 16 identity bytes back out of the reverse-hex form.
  Uint8List toBytes() {
    final out = Uint8List(kChangeIdBytes);
    for (var i = 0; i < kChangeIdBytes; i++) {
      final hi = _nibble(value.codeUnitAt(i * 2));
      final lo = _nibble(value.codeUnitAt(i * 2 + 1));
      out[i] = (hi << 4) | lo;
    }
    return out;
  }

  static int _nibble(int codeUnit) {
    // Alphabet runs 'z' (0) down to 'k' (15): nibble = 'z' - c.
    return 0x7a - codeUnit;
  }
}

/// Mints a fresh random change id. [rng] is a seam for deterministic
/// tests; production uses a cryptographic source.
ChangeId generateChangeId({Random? rng}) {
  final r = rng ?? Random.secure();
  final bytes = Uint8List(kChangeIdBytes);
  for (var i = 0; i < kChangeIdBytes; i++) {
    bytes[i] = r.nextInt(256);
  }
  return ChangeId.fromBytes(bytes);
}

/// jj-compatible synthetic change id for a commit that carries no
/// `change-id` header: the LAST 16 bytes of the commit id, in reversed
/// byte order, each byte bit-reversed. (Last-not-first so a hash prefix
/// stays unambiguous between the two id spaces; bit-reversed so nobody
/// comes to depend on a visible relationship — jj's own rationale,
/// mirrored here byte-for-byte for interop.)
///
/// [commitSha] is the full lowercase hex object name (40 chars for
/// SHA-1, 64 for SHA-256).
ChangeId syntheticChangeIdForCommit(String commitSha) {
  if (commitSha.length < kChangeIdBytes * 2 || commitSha.length.isOdd) {
    throw ArgumentError.value(commitSha, 'commitSha', 'not a hex object name');
  }
  final byteLen = commitSha.length ~/ 2;
  final tail = Uint8List(kChangeIdBytes);
  for (var i = 0; i < kChangeIdBytes; i++) {
    final byteIndex = byteLen - kChangeIdBytes + i;
    final hex = commitSha.substring(byteIndex * 2, byteIndex * 2 + 2);
    final v = int.tryParse(hex, radix: 16);
    if (v == null) {
      throw ArgumentError.value(
          commitSha, 'commitSha', 'not a hex object name');
    }
    tail[i] = v;
  }
  final out = Uint8List(kChangeIdBytes);
  for (var i = 0; i < kChangeIdBytes; i++) {
    out[i] = _reverseBits(tail[kChangeIdBytes - 1 - i]);
  }
  return ChangeId.fromBytes(out);
}

int _reverseBits(int byte) {
  var b = byte & 0xff;
  b = ((b & 0xf0) >> 4) | ((b & 0x0f) << 4);
  b = ((b & 0xcc) >> 2) | ((b & 0x33) << 2);
  b = ((b & 0xaa) >> 1) | ((b & 0x55) << 1);
  return b;
}

const int _lf = 0x0a;
const int _space = 0x20;

/// Everything [parseCommitHeaders] knows about a raw commit object's
/// header block: where it ends, whether a signature is present, and the
/// change id if one is declared.
class CommitHeaderScan {
  /// Byte offset of the blank line separating headers from the message
  /// (i.e. the offset AT which a `change-id` line would be inserted).
  final int headerEndOffset;

  /// True when a `gpgsig` / `gpgsig-sha256` header exists. A stamp must
  /// never rewrite a signed commit — that would invalidate the signature.
  final bool hasSignature;

  /// The declared change id, or null. When multiple `change-id` headers
  /// exist the FIRST wins — matching gix's `extra_headers().find`, which
  /// is what jj reads through. Malformed values (wrong length or
  /// alphabet) read as null — same posture as jj's length-filtered
  /// extraction.
  final ChangeId? changeId;

  /// True when ANY `change-id` header key exists, valid or not. Distinct
  /// from [changeId] so a stamp can refuse to add a SECOND key next to a
  /// malformed one — duplicate keys are exactly the ambiguity the header
  /// convention exists to prevent.
  final bool hasChangeIdKey;

  const CommitHeaderScan({
    required this.headerEndOffset,
    required this.hasSignature,
    required this.changeId,
    required this.hasChangeIdKey,
  });
}

/// Scans the header block of a raw commit object (the exact bytes
/// `git cat-file commit` emits). Returns null when the buffer has no
/// header/message separator — not a commit object.
///
/// Header grammar: `key SP value LF`, where a value may continue across
/// lines that start with SP (gpgsig does this). The block ends at the
/// first empty line. This scanner never decodes the message: commit
/// messages are not guaranteed UTF-8 and every byte past the separator
/// is opaque payload.
CommitHeaderScan? parseCommitHeaders(List<int> raw) {
  var hasSignature = false;
  var hasChangeIdKey = false;
  ChangeId? changeId;
  var sawChangeId = false;
  var lineStart = 0;
  while (lineStart < raw.length) {
    // Empty line → header block ends here.
    if (raw[lineStart] == _lf) {
      return CommitHeaderScan(
        headerEndOffset: lineStart,
        hasSignature: hasSignature,
        changeId: changeId,
        hasChangeIdKey: hasChangeIdKey,
      );
    }
    var lineEnd = lineStart;
    while (lineEnd < raw.length && raw[lineEnd] != _lf) {
      lineEnd++;
    }
    if (lineEnd >= raw.length) break; // truncated: no separator found
    // Continuation lines (leading SP) extend the previous header; they
    // carry no key of their own.
    if (raw[lineStart] != _space) {
      var keyEnd = lineStart;
      while (keyEnd < lineEnd && raw[keyEnd] != _space) {
        keyEnd++;
      }
      final key = String.fromCharCodes(raw.sublist(lineStart, keyEnd));
      if (key == 'gpgsig' || key == 'gpgsig-sha256') {
        hasSignature = true;
      } else if (key == kChangeIdHeader) {
        hasChangeIdKey = true;
        // First key wins, even when its value is malformed — matching
        // gix `extra_headers().find(...)`, the reader jj sits on.
        if (!sawChangeId) {
          sawChangeId = true;
          changeId = keyEnd < lineEnd
              ? ChangeId.tryParse(
                  String.fromCharCodes(raw.sublist(keyEnd + 1, lineEnd)))
              : null;
        }
      }
    }
    lineStart = lineEnd + 1;
  }
  return null;
}

/// Returns a copy of [raw] with `change-id <id>` inserted as the LAST
/// header line, byte-exact everywhere else. Throws [StateError] when the
/// buffer is not a commit object, already carries a change id, or is
/// signed (rewriting signed commits is forbidden — the caller must skip,
/// not force).
///
/// Law (by construction, pinned by tests): deleting the inserted line
/// from the output yields [raw] exactly.
Uint8List stampChangeId(List<int> raw, ChangeId id) {
  final scan = parseCommitHeaders(raw);
  if (scan == null) {
    throw StateError('not a commit object: no header/message separator');
  }
  if (scan.hasChangeIdKey) {
    // Covers valid AND malformed existing keys: adding a second
    // `change-id` line next to a malformed one would make first-wins
    // readers (gix/jj) resolve to garbage while we resolve to ours.
    throw StateError('commit already carries a change-id header');
  }
  if (scan.hasSignature) {
    throw StateError('refusing to rewrite a signed commit');
  }
  final headerLine = '$kChangeIdHeader ${id.value}\n'.codeUnits;
  final out = Uint8List(raw.length + headerLine.length);
  out.setRange(0, scan.headerEndOffset, raw);
  out.setRange(
      scan.headerEndOffset, scan.headerEndOffset + headerLine.length,
      headerLine);
  out.setRange(scan.headerEndOffset + headerLine.length, out.length, raw,
      scan.headerEndOffset);
  return out;
}
