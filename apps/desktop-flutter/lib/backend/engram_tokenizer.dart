// engram_tokenizer.dart — split identifiers into sub-tokens.
//
// Code identifiers (`getUserAuthProfile`, `build_diff_hunk`, `PHPVersion`)
// collapse into a bag of English sub-words that GloVe can look up.
// Splitters handle camelCase, PascalCase, snake_case, kebab-case, digit
// runs, and acronym runs (HTTPResponse → ["http", "response"]).
//
// Used by engram_hunk_encoder.dart on the symbol-token bags that the
// existing logos_hunks.dart H_sym axis already extracts — we reuse
// those tokens rather than re-tokenising the raw hunk body. This keeps
// the signals aligned (hunk A and hunk B compared via engram run on the
// same vocabulary they compared via Jaccard on).

/// Minimum sub-token length to keep. 2 chars preserves meaningful code
/// shorthand (`db`, `io`, `ui`) that's in the GloVe vocab.
const int _kMinSubTokenLen = 2;

/// Hard cap on sub-token length. 32 chars is plenty for any real
/// identifier; longer strings are likely minified/obfuscated noise.
const int _kMaxSubTokenLen = 32;

/// Split one identifier into lowercase sub-tokens. Walks the string
/// once, emitting a sub-token at every boundary:
///   - non-letter/digit character (`_`, `-`, `.`, `$`, `/`, space, etc.)
///   - lower→upper transition inside camelCase (`getUser` → `get`, `user`)
///   - acronym→word transition (`HTTPServer` → `http`, `server`)
///   - letter→digit / digit→letter transition
/// Digits-only runs are dropped (they're not in the GloVe vocabulary
/// anyway and carry little semantic signal for code domains).
List<String> splitIdentifier(String identifier) {
  if (identifier.isEmpty) return const [];
  final out = <String>[];
  final buf = StringBuffer();

  var prevKind = _CharKind.boundary;
  for (var i = 0; i < identifier.length; i++) {
    final c = identifier.codeUnitAt(i);
    final kind = _kindOf(c);

    var boundary = false;
    if (kind == _CharKind.boundary) {
      boundary = true;
    } else if (prevKind == _CharKind.boundary) {
      boundary = false;
    } else if (prevKind == _CharKind.digit && kind != _CharKind.digit) {
      boundary = true;
    } else if (kind == _CharKind.digit && prevKind != _CharKind.digit) {
      boundary = true;
    } else if (prevKind == _CharKind.lower && kind == _CharKind.upper) {
      // camelCase hump
      boundary = true;
    } else if (prevKind == _CharKind.upper && kind == _CharKind.lower) {
      // acronym → word: close the run one char before, restart with the
      // previous character — we handle this by flushing "buf minus last",
      // then starting a new buffer with the last uppercase + current.
      if (buf.length >= 2) {
        final s = buf.toString();
        final keep = s.substring(0, s.length - 1);
        final carry = s.substring(s.length - 1);
        _flush(out, keep);
        buf
          ..clear()
          ..write(carry);
      }
      boundary = false;
    }

    if (boundary) {
      _flush(out, buf.toString());
      buf.clear();
    }

    if (kind != _CharKind.boundary) {
      // Buffer the original code unit; lowercasing happens once in
      // `_flush` via `String.toLowerCase()` so we don't recompute it
      // per character. Faster on average and handles edge cases like
      // surrogate-encoded codepoints correctly.
      buf.writeCharCode(c);
    }

    prevKind = kind;
  }

  _flush(out, buf.toString());
  return out;
}

void _flush(List<String> out, String s) {
  if (s.isEmpty) return;
  if (s.length < _kMinSubTokenLen || s.length > _kMaxSubTokenLen) return;
  // Drop pure-digit runs.
  var allDigit = true;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) {
      allDigit = false;
      break;
    }
  }
  if (allDigit) return;
  out.add(s.toLowerCase());
}

enum _CharKind { lower, upper, digit, boundary }

_CharKind _kindOf(int c) {
  if (c >= 0x61 && c <= 0x7A) return _CharKind.lower; // a-z
  if (c >= 0x41 && c <= 0x5A) return _CharKind.upper; // A-Z
  if (c >= 0x30 && c <= 0x39) return _CharKind.digit; // 0-9
  return _CharKind.boundary;
}

/// Walk a bag of identifier-ish tokens (as extracted by logos_hunks.dart)
/// and produce a list of lowercase sub-tokens suitable for GloVe lookup.
/// Preserves order loosely — identifier A's sub-tokens appear before
/// identifier B's. Duplicates are kept (the downstream hunk encoder
/// may weight by frequency).
List<String> expandIdentifiers(Iterable<String> tokens) {
  final out = <String>[];
  for (final t in tokens) {
    out.addAll(splitIdentifier(t));
  }
  return out;
}
