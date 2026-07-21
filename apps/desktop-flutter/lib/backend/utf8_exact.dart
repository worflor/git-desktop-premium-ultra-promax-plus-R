// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// utf8_exact.dart — BOM-preserving UTF-8 decoding.
//
// Dart's `Utf8Decoder` (and therefore `utf8.decode`) silently strips a
// leading U+FEFF byte-order mark from its output. That is the right call
// for reading whole documents, but wrong for wire codecs and ref-name
// round-trips where every code point is payload: a peer id, path, or
// branch name that genuinely starts with U+FEFF must survive a
// decode/encode round-trip byte-exact.

import 'dart:convert';

/// Decode [bytes] as UTF-8 without dropping a leading byte-order mark.
///
/// Every leading U+FEFF (bytes `EF BB BF`) is re-attached verbatim; the
/// remainder decodes through the standard [utf8] codec (which strips at
/// most one leading BOM, so consuming the whole run here is exact).
/// With [allowMalformed] set, invalid sequences become U+FFFD instead of
/// throwing [FormatException].
String utf8DecodeExact(List<int> bytes, {bool allowMalformed = false}) {
  var start = 0;
  var boms = 0;
  while (bytes.length - start >= 3 &&
      bytes[start] == 0xEF &&
      bytes[start + 1] == 0xBB &&
      bytes[start + 2] == 0xBF) {
    boms++;
    start += 3;
  }
  final rest = utf8.decode(
    start == 0 ? bytes : bytes.sublist(start),
    allowMalformed: allowMalformed,
  );
  return boms == 0 ? rest : '\uFEFF' * boms + rest;
}
