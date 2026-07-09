// GIT DIFF PATHS — single source of truth for recovering file paths from
// git diff/patch headers.
//
// Git C-quotes any path containing non-ASCII, backslash, or quote bytes
// whenever `core.quotepath` is at its default (true) — one octal escape
// PER BYTE of the path's UTF-8 encoding. It also never quotes a path that
// merely contains a space, so unquoted headers can legitimately have
// embedded spaces that must not be mistaken for the a/-b/ separator.
//
// Both the backend hunk parser (logos_hunks.dart) and the canonical UI
// diff parser (features/diff/diff_models.dart — PatchEngine, DiffShell,
// reviewMergeFromPatch) need to recover the SAME path from the SAME
// header for their outputs to agree. This module is that one
// implementation; import it from both sides so quoted/C-quoted/
// space-containing path handling can never drift between them again.

import 'utf8_exact.dart' show utf8DecodeExact;

/// Reverse of git's `core.quotepath` encoding for paths containing
/// non-printable / special bytes. Unwraps the surrounding double
/// quotes and decodes `\n`, `\t`, `\r`, `\"`, `\\`, and octal
/// `\NNN` byte escapes. Non-quoted paths pass through unchanged.
///
/// Git C-quotes non-ASCII filenames as one octal escape PER BYTE of the
/// path's UTF-8 encoding — a single multi-byte code point (e.g. "é" =
/// UTF-8 bytes 0xC3 0xA9) becomes TWO consecutive `\NNN` escapes.
/// Decoding each escape to its own UTF-16 code unit independently (as if
/// each byte were already a code point) produces mojibake ("café-file"
/// round-trips as "cafeÃ©-file"). This accumulates the raw bytes of every
/// CONTIGUOUS escape run — octal or single-char — into [pendingBytes] and
/// flushes them through one [utf8DecodeExact] call when the run ends
/// (a plain char or the string's end), so a multi-byte code point is
/// recombined and decoded exactly once, correctly.
String unCQuoteGitPath(String s) {
  if (s.length < 2 || !s.startsWith('"') || !s.endsWith('"')) return s;
  final inner = s.substring(1, s.length - 1);
  final buf = StringBuffer();
  final pendingBytes = <int>[];
  var i = 0;

  void flushPending() {
    if (pendingBytes.isEmpty) return;
    buf.write(utf8DecodeExact(pendingBytes, allowMalformed: true));
    pendingBytes.clear();
  }

  while (i < inner.length) {
    final c = inner.codeUnitAt(i);
    if (c == 0x5C && i + 1 < inner.length) {
      final n = inner.codeUnitAt(i + 1);
      if (n >= 0x30 && n <= 0x37 && i + 3 < inner.length) {
        final b = inner.codeUnitAt(i + 2);
        final d = inner.codeUnitAt(i + 3);
        if (b >= 0x30 && b <= 0x37 && d >= 0x30 && d <= 0x37) {
          pendingBytes
              .add(((n - 0x30) << 6) | ((b - 0x30) << 3) | (d - 0x30));
          i += 4;
          continue;
        }
      }
      final mapped = _cQuoteEscapeByte[n];
      if (mapped != null) {
        // Single-char escapes decode to one ASCII byte — folding them
        // into the same pending-byte run keeps the "one decode per
        // contiguous escape run" invariant intact even for a run that
        // mixes octal and single-char escapes.
        pendingBytes.add(mapped);
        i += 2;
        continue;
      }
      flushPending();
      buf.writeCharCode(c);
      buf.writeCharCode(n);
      i += 2;
      continue;
    }
    flushPending();
    buf.writeCharCode(c);
    i++;
  }
  flushPending();
  return buf.toString();
}

/// Single-char escape sequences git emits alongside octal for paths
/// containing control/non-ASCII bytes. Maps the char AFTER the `\` to
/// the decoded byte.
const Map<int, int> _cQuoteEscapeByte = {
  0x6E: 0x0A, // \n
  0x74: 0x09, // \t
  0x72: 0x0D, // \r
  0x22: 0x22, // \"
  0x5C: 0x5C, // \\
};

/// Extracts a double-quoted token starting at [start] (where `s[start]`
/// must be `"`), honoring backslash-escaping so an escaped `\"` inside the
/// token doesn't end it early. Returns the token INCLUDING its surrounding
/// quotes plus the index just past the closing quote, or null if [start]
/// isn't a quote or the token is unterminated.
({String text, int end})? extractQuotedToken(String s, int start) {
  if (start >= s.length || s.codeUnitAt(start) != 0x22) return null;
  var i = start + 1;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c == 0x5C && i + 1 < s.length) {
      i += 2;
      continue;
    }
    if (c == 0x22) {
      return (text: s.substring(start, i + 1), end: i + 1);
    }
    i++;
  }
  return null;
}

/// Extracts a `diff --git` header's `b/`-side path.
///
/// `line.split(' ')[3]` (the old approach) shatters on filenames that
/// contain their own internal spaces — git only C-quotes paths with
/// non-ASCII/backslash/quote bytes, so a plain `has space in it.txt`
/// filename reaches this function completely unquoted, indistinguishable
/// from a run of space-separated header tokens.
///
/// Git quotes EACH side of the header INDEPENDENTLY — a rename where only
/// the new name needs quoting emits `diff --git a/old.txt "b/caf\303\251.txt"`
/// — and never quotes a name merely for containing spaces. Priority order:
///  1. Quoted b-side (`… "b/y"`): parse via [extractQuotedToken] (respects
///     C-quote escaping); the a-side before it is either its own quoted
///     token or a raw run that cannot contain `"` (git would have quoted
///     it), so the separator before the b-token is unambiguous.
///  2. Quoted a-side + raw b-side: extract the a-token; everything after
///     the following space is the raw b-side.
///  3. Both raw, non-rename: the identical path repeats (`a/P b/P`) — walk
///     every space and accept the split where prefix `a/P` and suffix
///     `b/P` agree on `P`. Handles any embedded spaces exactly, even a
///     literal ` b/` inside the name.
///  4. Both raw, rename (`a/old name.txt b/new name.txt` — nothing
///     repeats): split at the LAST ` b/` occurrence, reproducing the
///     greedy `^diff --git a/(.+) b/(.+)$` regex this parser replaced, so
///     rename paths with spaces keep working. (A new name itself
///     containing ` b/` is genuinely ambiguous — same answer the regex
///     gave.)
///  5. Last resort: the original `split(' ')[3]` (non-standard prefixes),
///     else null for a malformed header — callers decide their own
///     fallback (e.g. `'unknown'`).
String? pathFromDiffGitHeader(String line) {
  const prefix = 'diff --git ';
  if (line.startsWith(prefix)) {
    final remainder = line.substring(prefix.length);

    String stripB(String decoded) =>
        decoded.startsWith('b/') ? decoded.substring(2) : decoded;

    if (remainder.startsWith('"')) {
      final aTok = extractQuotedToken(remainder, 0);
      if (aTok != null &&
          aTok.end + 1 < remainder.length &&
          remainder[aTok.end] == ' ') {
        final rest = remainder.substring(aTok.end + 1);
        if (rest.startsWith('"')) {
          // Case 1a: "a/…" "b/…"
          final bTok = extractQuotedToken(rest, 0);
          if (bTok != null) return stripB(unCQuoteGitPath(bTok.text));
        }
        // Case 2: "a/…" b/… — raw b-side, no escapes to decode.
        return stripB(rest);
      }
    } else if (remainder.endsWith('"')) {
      // Case 1b: a/… "b/…" — raw a-side cannot contain `"`, so the first
      // ` "` is the separator. Require the b-token to close the line.
      final sep = remainder.indexOf(' "');
      if (sep != -1) {
        final bTok = extractQuotedToken(remainder, sep + 1);
        if (bTok != null && bTok.end == remainder.length) {
          return stripB(unCQuoteGitPath(bTok.text));
        }
      }
    }

    if (remainder.startsWith('a/')) {
      // Case 3: both raw, non-rename — repeated-path scan.
      for (var sp = remainder.indexOf(' ');
          sp != -1;
          sp = remainder.indexOf(' ', sp + 1)) {
        final aSide = remainder.substring(0, sp);
        final bSide = remainder.substring(sp + 1);
        if (bSide.startsWith('b/') &&
            aSide.substring(2) == bSide.substring(2)) {
          return bSide.substring(2);
        }
      }
      // Case 4: both raw, rename — last ` b/` split (old-regex parity).
      final lastB = remainder.lastIndexOf(' b/');
      if (lastB > 0) {
        return remainder.substring(lastB + 3);
      }
    }
  }

  // Case 5: malformed / non-standard prefixes — original behavior.
  final parts = line.split(' ');
  if (parts.length < 4) return null;
  final candidate = parts[3];
  final stripped =
      candidate.startsWith('b/') ? candidate.substring(2) : candidate;
  return unCQuoteGitPath(stripped);
}

/// Extracts the path from a `--- ` / `+++ ` patch header line (as used in
/// bare unified diffs without a `diff --git` header, or as the fallback
/// source for a rename's old/new name). [preferredPrefix] is `'a'` for
/// `--- ` lines and `'b'` for `+++ ` lines — the conventional git prefix
/// stripped when present. Returns null for `/dev/null` (added/removed
/// file) or a malformed header.
String? patchSidePath(String headerLine, {required String preferredPrefix}) {
  final marker = headerLine.length >= 4 ? headerLine.substring(0, 4) : '';
  if (marker != '--- ' && marker != '+++ ') return null;
  var value = headerLine.substring(4).trim();
  if (value.isEmpty || value == '/dev/null') return null;
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    // Quoted values may carry git's C-quote octal/escape encoding —
    // un-quote it before stripping the a/ or b/ prefix. Unquoted values
    // are NOT run through this decode: git only C-quotes inside quotes,
    // so a literal backslash in an unquoted path must survive untouched.
    value = unCQuoteGitPath(value);
  }
  final prefixed = '$preferredPrefix/';
  if (value.startsWith(prefixed)) {
    return value.substring(prefixed.length);
  }
  return value;
}
