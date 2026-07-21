// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Generators and reference oracles built on top of prop.dart.
//
// Two families live here:
//  - "friendly" generators (genInt, genAscii, ...) for well-behaved inputs;
//  - "hostile" generators (genUnicodeHostile, genLine, genMultilineText,
//    genRelPath) that deliberately manufacture the inputs that break naive
//    string/path/diff handling: NUL bytes, bare CR line endings, missing
//    trailing newlines, zero-width characters, mixed path separators.
//
// The graph generators + oracles are the important half of this file. The
// engine (docs/architecture/spectral-cosmology.md) computes things like
// connected-component counts (beta-0, the graph's zeroth Betti number - the
// count of pieces it falls into) via spectral/approximate methods for
// performance. Those methods must be checked against something dumb and
// obviously correct, never against themselves. `connectedComponents` is a
// plain union-find; `denseAdjacency`/`denseLaplacian` are O(n^2) dense
// matrices. Both are asymptotically worse than anything the engine does -
// that slowness is the point: correctness, not speed, is what a reference
// oracle is for.
//
// Every combining/zero-width/bidi/control code point used by
// [_hostileTokens] (including NUL) is built from a plain-ASCII integer
// literal via `String.fromCharCode`/`fromCharCodes`, never pasted into this
// file as a raw literal character. A raw literal control/invisible/joining
// character sitting directly in source is indistinguishable in a diff, easy
// to mangle on a re-encode, and (for NUL specifically) has previously
// broken tooling in this repo that scans source files as text - see the
// project's own "NUL byte in source" incident notes. Only ordinary,
// visibly-rendering non-ASCII text (the unicode path segments in
// [_pathSegmentPool]) is left as literal text, since that carries none of
// those risks.

import 'dart:math' as math;
import 'dart:typed_data';

import 'prop.dart';

// ---------------------------------------------------------------------------
// Combinators
// ---------------------------------------------------------------------------
//
// Plain functions over `Gen<T>`, matching this file's stated philosophy
// (see the [Gen] doc comment in prop.dart): generators compose with
// ordinary function combinators instead of a bespoke builder class. Every
// one of these is itself a `Gen<T> Function(Rng) -> T`, so it inherits
// shrinking for free — no separate shrink logic to keep in sync.

/// Transforms every value [g] produces through [f]. The shrink behavior is
/// entirely [g]'s: whatever tape shrinks [g]'s output also shrinks the
/// mapped output, since `f` is applied after the value is drawn.
Gen<R> genMap<T, R>(Gen<T> g, R Function(T) f) => (rng) => f(g(rng));

/// Draws a [T] from [g], then uses it to pick and run a second generator.
/// The composed draw records onto one flat tape like any nested generator
/// call, so it shrinks normally.
Gen<R> genFlatMap<T, R>(Gen<T> g, Gen<R> Function(T) f) =>
    (rng) => f(g(rng))(rng);

/// Picks uniformly among [options] and runs it. Shrinks toward
/// `options.first`, so — as with [Rng.pick] generally — list the most
/// boring generator first.
Gen<T> genOneOf<T>(List<Gen<T>> options) {
  if (options.isEmpty) {
    throw ArgumentError('genOneOf requires at least one option');
  }
  return (rng) => rng.pick(options)(rng);
}

/// Picks among [options] with probability proportional to each entry's
/// weight (all weights must be `> 0`) and runs the chosen generator.
Gen<T> genFrequency<T>(List<(int weight, Gen<T>)> options) {
  if (options.isEmpty) {
    throw ArgumentError('genFrequency requires at least one option');
  }
  var total = 0;
  for (final (weight, _) in options) {
    assert(weight > 0, 'genFrequency weights must be > 0');
    total += weight;
  }
  return (rng) {
    var roll = rng.intBetween(0, total - 1);
    for (final (weight, gen) in options) {
      if (roll < weight) return gen(rng);
      roll -= weight;
    }
    return options.last.$2(rng); // unreachable: roll < total by construction
  };
}

/// A list of [element] values, length drawn via `intBetween(0, maxLen)` so
/// the length itself shrinks toward `0` (an empty list), the usual
/// degenerate case worth checking first.
Gen<List<T>> genList<T>(Gen<T> element, {int maxLen = 12}) {
  return (rng) {
    final length = rng.intBetween(0, maxLen);
    return List<T>.generate(length, (_) => element(rng));
  };
}

/// [g], or `null` roughly 25% of the time. Backed by `intBetween(0, 3)`
/// (rolling `0` -> null), so shrinking drifts the roll toward `0` and a
/// minimized counterexample lands on `null` rather than a shrunk [g].
Gen<T?> genOptional<T>(Gen<T> g) {
  return (rng) => rng.intBetween(0, 3) == 0 ? null : g(rng);
}

/// Always produces [value], ignoring the [Rng] entirely (no draw, so it
/// contributes nothing to the tape).
Gen<T> genConst<T>(T value) => (_) => value;

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

/// Uniform integers in `[min, max]` (inclusive both ends).
///
/// Draws through [Rng.simpleIntBetween], so a minimized counterexample
/// reports `0` rather than whichever endpoint the tape happens to bottom out
/// at. The draw itself is uniform over the range either way — only the
/// shrink ordering differs.
Gen<int> genInt({int min = -1000, int max = 1000}) {
  return (rng) => rng.simpleIntBetween(min, max);
}

/// Uniform, finite doubles in `[min, max)` - never NaN or +/-infinity, since
/// both are constructed from `Rng.nextDouble()` (already finite in `[0,1)`)
/// linearly interpolated between two finite bounds.
Gen<double> genDouble({double min = -1e6, double max = 1e6}) {
  return (rng) => min + rng.nextDouble() * (max - min);
}

/// The adversarial counterpart to [genDouble]: every non-finite double
/// value, every magnitude extreme, and every mantissa-precision edge case
/// that [genDouble] deliberately never produces.
///
/// Exists to attack `lib/backend/json_safety.dart`, which exists
/// specifically to reject non-finite doubles read from untrusted JSON
/// (`asIntOrNull`/`asDoubleOrNull`) — and nothing else in this repo's
/// generator vocabulary ever hands it a NaN, an Infinity, or a double
/// outside the exact-int64-representable range to check that rejection
/// against.
///
/// The pool's first element is `0.0` so a minimized counterexample starts
/// from the most boring double, not `NaN` or a signed extreme.
Gen<double> genDoubleHostile() {
  final finite = genDouble(min: -1e6, max: 1e6);
  final pool = <double Function(Rng)>[
    (_) => 0.0,
    (_) => -0.0,
    (_) => double.nan,
    (_) => double.infinity,
    (_) => double.negativeInfinity,
    (_) => double.maxFinite,
    (_) => double.minPositive,
    (_) => -double.maxFinite,
    (_) => 1e308,
    (_) => 1e-308,
    (_) => 4503599627370496.0, // 2^52 — last exactly-representable "small" run
    (_) => 9007199254740992.0, // 2^53 — mantissa precision boundary
    (_) => 9007199254740993.0, // 2^53 + 1 — rounds to 2^53 in a double
    (_) => -1.0,
    (_) => 1.0,
    (_) => 0.5,
    (_) => 3.7,
    (rng) => finite(rng),
  ];
  return (rng) => rng.pick(pool)(rng);
}

/// Printable, non-control ASCII (space `0x20` through `~` `0x7E`), the
/// "friendly" string baseline. No newlines or control characters - that's
/// what [genUnicodeHostile] and [genLine] are for.
const int _asciiPrintableLo = 0x20;
const int _asciiPrintableHi = 0x7E;

Gen<String> genAscii({int maxLen = 32}) {
  return (rng) {
    final length = rng.intBetween(0, maxLen);
    final codeUnits = List<int>.generate(
      length,
      (_) => rng.intBetween(_asciiPrintableLo, _asciiPrintableHi),
    );
    return String.fromCharCodes(codeUnits);
  };
}

/// Code points behind the adversarial tokens below, named only as
/// plain-ASCII hex integers (see the file-level comment for why this file
/// never spells these out as literal characters).
const int _cpGrinningFace = 0x1F600;
const int _cpFire = 0x1F525;
const int _cpRocket = 0x1F680;
const int _cpWoman = 0x1F469;
const int _cpZwj = 0x200D; // zero-width joiner
const int _cpLaptop = 0x1F4BB;
const int _cpWhiteFlag = 0x1F3F3;
const int _cpVariationSelector16 = 0xFE0F;
const int _cpRainbow = 0x1F308;
const int _cpCombiningAcute = 0x0301;
const int _cpCombiningGrave = 0x0300;
const int _cpCombiningDiaeresis = 0x0308;
const int _cpCombiningDoubleBreve = 0x035C;
const int _cpRightToLeftMark = 0x200F;
const int _cpLeftToRightMark = 0x200E;
const int _cpArabicLetterMark = 0x061C;
const int _cpZeroWidthSpace = 0x200B;
const int _cpZeroWidthNonJoiner = 0x200C;
const int _cpByteOrderMark = 0xFEFF; // aka ZWNBSP
const int _cpNul = 0x0000;
const int _cpSoh = 0x0001;
const int _cpBel = 0x0007;
const int _cpEsc = 0x001B;

/// The adversarial string source. Every call draws a random number of
/// tokens from a fixed pool that mixes plain filler characters with every
/// category of string this app must not choke on:
///
///  - emoji, including a multi-codepoint ZWJ (zero-width-joiner) sequence,
///    because a "character" on screen is not one Dart string element;
///  - combining marks, which visually attach to the *previous* character
///    instead of standing alone;
///  - RTL/bidi control marks, which can make later text render
///    right-to-left with no visible glyph of their own;
///  - zero-width characters (including a BOM/ZWNBSP), which are real string
///    content that is invisible in any UI and easy to lose in naive
///    trimming/diffing logic;
///  - C0 control characters, including a literal NUL - NUL specifically
///    matters because it is `git diff -z`'s field separator and several
///    text pipelines (C strings, some platform APIs) treat it as a
///    terminator, so a NUL *inside* a string is a classic truncation bug;
///  - every line-terminator shape git/diff tooling has to handle: LF, CRLF,
///    a lone CR, and a run of lone CRs back to back.
final List<String> _hostileTokens = [
  // Plain filler so hostile tokens are interspersed with ordinary text.
  'a', 'Z', '0', ' ', '_', '-',
  // Emoji: grinning face, fire, rocket.
  String.fromCharCode(_cpGrinningFace),
  String.fromCharCode(_cpFire),
  String.fromCharCode(_cpRocket),
  // Multi-codepoint ZWJ sequences - a single rendered glyph made of several
  // code points: "woman technologist" (woman + ZWJ + laptop) and the pride
  // flag (white flag + variation selector-16 + ZWJ + rainbow).
  String.fromCharCodes([_cpWoman, _cpZwj, _cpLaptop]),
  String.fromCharCodes([
    _cpWhiteFlag,
    _cpVariationSelector16,
    _cpZwj,
    _cpRainbow,
  ]),
  // Combining marks (attach to the preceding character; standalone they
  // combine with whatever text sits before them).
  String.fromCharCode(_cpCombiningAcute),
  String.fromCharCode(_cpCombiningGrave),
  String.fromCharCode(_cpCombiningDiaeresis),
  String.fromCharCode(_cpCombiningDoubleBreve),
  // Bidi/RTL control marks (no visible glyph, can flip rendering direction).
  String.fromCharCode(_cpRightToLeftMark),
  String.fromCharCode(_cpLeftToRightMark),
  String.fromCharCode(_cpArabicLetterMark),
  // Zero-width characters, including the BOM/ZWNBSP.
  String.fromCharCode(_cpZeroWidthSpace),
  String.fromCharCode(_cpZeroWidthNonJoiner),
  String.fromCharCode(_cpZwj),
  String.fromCharCode(_cpByteOrderMark),
  // C0 control characters, including a literal NUL.
  String.fromCharCode(_cpNul),
  String.fromCharCode(_cpSoh),
  String.fromCharCode(_cpBel),
  String.fromCharCode(_cpEsc),
  // Line terminators, every shape: LF, CRLF, lone CR, a run of lone CRs.
  '\n', '\r\n', '\r', '\r\r',
];

Gen<String> genUnicodeHostile({int maxLen = 24}) {
  return (rng) {
    final tokenCount = rng.intBetween(0, maxLen);
    final buffer = StringBuffer();
    for (var i = 0; i < tokenCount; i++) {
      buffer.write(rng.pick(_hostileTokens));
    }
    return buffer.toString();
  };
}

/// One line of plain text plus a randomly chosen terminator: none, `'\n'`,
/// `'\r\n'`, or a lone `'\r'`. The "none" case matters on its own - a line
/// with no terminator is exactly what the last line of a file with no
/// trailing newline looks like.
Gen<String> genLine() {
  final body = genAscii(maxLen: 40);
  const terminators = ['', '\n', '\r\n', '\r'];
  return (rng) => '${body(rng)}${rng.pick(terminators)}';
}

/// Several lines of text joined into one blob.
///
/// Two properties are deliberately engineered to show up often (not just
/// theoretically possible) across repeated draws:
///  - the terminator after the *last* line is weighted so "no trailing
///    newline at all" happens roughly as often as "has one" - the
///    no-final-newline case is a classic hunk/diff off-by-one trap;
///  - every non-last line picks its own terminator independently, so a
///    single blob very often mixes `'\n'` and `'\r\n'` (and lone `'\r'`)
///    internally, the way real files edited across Windows/Unix tooling do.
Gen<String> genMultilineText({int maxLines = 12}) {
  final body = genAscii(maxLen: 24);
  const interiorTerminators = ['\n', '\r\n', '\r'];
  // '' appears twice so "no trailing newline" and "has a trailing newline"
  // are roughly equally likely, instead of a 1-in-4 minority case.
  const finalTerminators = ['', '', '\n', '\r\n'];
  return (rng) {
    final lineCount = rng.intBetween(1, maxLines);
    final buffer = StringBuffer();
    for (var i = 0; i < lineCount; i++) {
      buffer.write(body(rng));
      final isLast = i == lineCount - 1;
      buffer.write(rng.pick(isLast ? finalTerminators : interiorTerminators));
    }
    return buffer.toString();
  };
}

/// A relative path built from tricky segments: normal names, names with
/// spaces, unicode names, `.` and `..`, dotfile-looking names, deep
/// nesting, and - deliberately - a mix of `/` and `\` separators *within
/// the same path*, mirroring paths that arrive from Windows tooling,
/// copy-pasted diffs, or cross-platform git output. Never absolute
/// (no leading separator, no drive letter), never empty.
///
/// The unicode segments are built from plain-ASCII code-point integers
/// (same rationale as [_hostileTokens]) rather than pasted as literal
/// non-ASCII text: "cafe" with a trailing U+00E9 (e-acute), the Chinese
/// word for "file" (U+6587 U+4EF6), its Japanese katakana equivalent
/// (U+30D5 U+30A1 U+30A4 U+30EB), and its Russian equivalent (U+0444
/// U+0430 U+0439 U+043B).
final List<String> _pathSegmentPool = [
  'src', 'lib', 'test', 'a', 'b', 'file.dart', 'my file',
  'has space.txt',
  '${String.fromCharCodes([0x63, 0x61, 0x66, 0x65])}${String.fromCharCode(0xE9)}',
  String.fromCharCodes([0x6587, 0x4EF6]),
  String.fromCharCodes([0x30D5, 0x30A1, 0x30A4, 0x30EB]),
  String.fromCharCodes([0x0444, 0x0430, 0x0439, 0x043B]),
  '.', '..', '.git', '.gitignore', 'node_modules',
  'a.b.c', 'weird-name_123', 'trailing.',
];

Gen<String> genRelPath() {
  return (rng) {
    final depth = rng.intBetween(1, 6);
    final buffer = StringBuffer();
    for (var i = 0; i < depth; i++) {
      if (i > 0) buffer.write(rng.pick(const ['/', '\\']));
      buffer.write(rng.pick(_pathSegmentPool));
    }
    var path = buffer.toString();
    // Belt-and-suspenders guard for the "never empty, never absolute"
    // contract; the segment pool above can't actually produce either, but
    // future edits to the pool shouldn't be able to violate the contract
    // silently.
    if (path.isEmpty) path = 'fallback';
    while (path.startsWith('/') || path.startsWith('\\')) {
      path = path.substring(1);
    }
    return path;
  };
}

// ---------------------------------------------------------------------------
// Bytes / file headers
// ---------------------------------------------------------------------------

/// Uniform random bytes, length via `intBetween(0, maxLen)` so it shrinks
/// toward the empty buffer.
Gen<Uint8List> genBytes({int maxLen = 64}) {
  return (rng) {
    final length = rng.intBetween(0, maxLen);
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rng.intBetween(0, 255)),
    );
  };
}

/// `(formatName, magicBytes)` pairs mirroring `lib/backend/magic_bytes.dart`'s
/// `_signatures`/RIFF-subtype table, so [genFileHeaderBytes] and the
/// truncation/prefix laws in `hostile_input_laws_test.dart` share one
/// fixture instead of two copies that can silently drift apart. The RIFF
/// container (WebP) and the offset-4 `ftyp` (MP4) box are represented as
/// their minimal full recognized headers (arbitrary-but-fixed filler for
/// the bytes `probeContentClass` doesn't examine), not as flat offset-0
/// signatures — `probeContentClass` reads those two at different offsets
/// than everything else in the table.
const List<(String name, List<int> bytes)> fileHeaderMagicSignatures = [
  ('PNG', [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
  ('JPEG', [0xFF, 0xD8, 0xFF]),
  ('GIF', [0x47, 0x49, 0x46, 0x38]),
  ('PDF', [0x25, 0x50, 0x44, 0x46]), // %PDF
  ('ZIP', [0x50, 0x4B, 0x03, 0x04]),
  ('GZIP', [0x1F, 0x8B]),
  ('OTF', [0x4F, 0x54, 0x54, 0x4F]), // OTTO
  (
    'WEBP_RIFF',
    [
      0x52, 0x49, 0x46, 0x46, // "RIFF"
      0x00, 0x00, 0x00, 0x00, // container size — probeContentClass ignores it
      0x57, 0x45, 0x42, 0x50, // "WEBP"
    ],
  ),
  (
    'MP4_FTYP',
    [
      0x00, 0x00, 0x00, 0x00, // box size — probeContentClass ignores it
      0x66, 0x74, 0x79, 0x70, // "ftyp" at offset 4
    ],
  ),
];

/// Half the time, an arbitrary [genBytes] blob. Half the time, a real
/// magic-byte signature from [fileHeaderMagicSignatures] followed by a
/// random tail — and, about a quarter of THAT half, the signature itself
/// truncated mid-way instead of complete.
///
/// Attacks `lib/backend/magic_bytes.dart`'s `probeContentClass`, which has
/// zero tests today: totality over arbitrary bytes, determinism, prefix
/// stability (a longer header sharing a matched header's bytes classifies
/// identically), and truncation-below-signature-length falling back to
/// `unknown`.
Gen<Uint8List> genFileHeaderBytes() {
  final randomBlob = genBytes(maxLen: 64);
  return (rng) {
    if (!rng.nextBool()) return randomBlob(rng);
    final magic = rng.pick(fileHeaderMagicSignatures).$2;
    final truncate = rng.intBetween(0, 3) == 0; // ~25% truncated mid-signature
    final prefixLen = truncate
        ? (magic.length <= 1 ? 0 : rng.intBetween(0, magic.length - 1))
        : magic.length;
    final tailLen = rng.intBetween(0, 32);
    final bytes = <int>[
      ...magic.take(prefixLen),
      ...List<int>.generate(tailLen, (_) => rng.intBetween(0, 255)),
    ];
    return Uint8List.fromList(bytes);
  };
}

// ---------------------------------------------------------------------------
// Hostile identifiers — ref names, Windows paths, case collisions
// ---------------------------------------------------------------------------

/// One C0 control byte (BEL), reused from [_hostileTokens]'s constant
/// rather than pasted as a raw literal — see the file-level comment for
/// why control characters never appear as literal source text here.
const int _cpBadRefControl = _cpBel;

/// Strings that violate `git check-ref-format` in the specific shapes that
/// matter for `DeskPrStore.encodeBranch`/`decodeBranch` injectivity
/// (lib/backend/desk_pr_store.dart): a leading `-`, a `@{` reflog-style
/// sequence, `..`, a trailing `.lock`, a trailing `.`, a leading/trailing/
/// doubled `/`, an embedded control byte, a space, every character in
/// `~ ^ : ? * [ \`, the single character `@`, the empty string, and one
/// ordinary valid ref for contrast. `'a'` is first so a minimized
/// counterexample starts from the most boring, entirely legal ref.
final List<String> _badRefPool = [
  'a',
  '-branch',
  'refs@{1}',
  'a..b',
  'branch.lock',
  'branch.',
  '/branch',
  'branch/',
  'a//b',
  'ref${String.fromCharCode(_cpBadRefControl)}name',
  'has space',
  'a~b',
  'a^b',
  'a:b',
  'a?b',
  'a*b',
  'a[b',
  'a\\b',
  '@',
  '',
  'valid/ref-name',
];

Gen<String> genBadRef() {
  return (rng) => rng.pick(_badRefPool);
}

/// A path segment made of `'a' * 60` repeated deeply enough (30 segments,
/// `/`-joined) to bust Windows' historical 260-character `MAX_PATH` by a
/// wide margin — built at load time rather than pasted as a giant literal.
final String _maxPathBustingPath =
    List<String>.generate(30, (_) => 'a' * 60).join('/');

/// Windows-hostile path names: every reserved DOS device name (`CON`,
/// `PRN`, `AUX`, `NUL`, `COM1`, `LPT1`) bare and with an extension (both
/// are reserved on Windows — the device name wins regardless of what
/// follows the dot), a name ending in a trailing dot, a name ending in a
/// trailing space (both silently stripped by the Win32 API, a classic
/// source of a create/open mismatch), and [_maxPathBustingPath]. First
/// element is `'a.txt'`, an entirely ordinary filename, so a minimized
/// counterexample starts from the boring case.
final List<String> _windowsHostilePathPool = [
  'a.txt',
  'CON',
  'CON.txt',
  'PRN',
  'PRN.txt',
  'AUX',
  'AUX.txt',
  'NUL',
  'NUL.txt',
  'COM1',
  'COM1.txt',
  'LPT1',
  'LPT1.txt',
  'trailing.',
  'trailing ',
  _maxPathBustingPath,
];

Gen<String> genWindowsHostilePath() {
  return (rng) => rng.pick(_windowsHostilePathPool);
}

/// Pairs of strings that collide under a case-insensitive (or, for the
/// German entry, case-FOLDING) filesystem/ref comparison despite being
/// `==`-distinct Dart strings: an ordinary ASCII case difference, an
/// all-caps vs. all-lowercase pair, Turkish `İ` (LATIN CAPITAL LETTER I
/// WITH DOT ABOVE, U+0130) against ASCII `i` (collides under a
/// Turkish-locale-agnostic case fold but NOT under simple `toLowerCase()`
/// — the classic "Turkish I problem"), and German `ß` (U+00DF) against its
/// standard uppercase expansion `SS`. The Turkish/German entries are
/// written as literal, ordinary-rendering non-ASCII text (matching
/// `_pathSegmentPool`'s convention — only combining/zero-width/control
/// characters are barred from appearing as source literals in this file).
/// First pair is a non-colliding control, so a minimized counterexample
/// that doesn't need a collision lands there.
final List<(String, String)> _caseCollisionPairPool = [
  ('alpha', 'beta'),
  ('File.txt', 'file.txt'),
  ('README', 'readme'),
  ('İ', 'i'),
  ('ß', 'SS'),
];

Gen<(String, String)> genCaseCollisionPair() {
  return (rng) => rng.pick(_caseCollisionPairPool);
}

// ---------------------------------------------------------------------------
// Graphs
// ---------------------------------------------------------------------------

/// An undirected, positively-weighted test graph.
///
/// Node ids are `0 <= id < n`. [edges] is the undirected edge list - `(a,
/// b, w)` and `(b, a, w)` name the same edge, so generators only ever emit
/// one direction. Weights are strictly positive. No self-loops (`a == b`)
/// unless a future generator variant explicitly documents adding them.
class TestGraph {
  final int n;
  final List<(int a, int b, double w)> edges;
  const TestGraph(this.n, this.edges);
}

double _positiveWeight(Rng rng) => 0.1 + rng.nextDouble() * 9.9;

/// An arbitrary graph: `n` in `[1, maxNodes]`, density drawn independently
/// per call so both near-empty and near-complete graphs show up over many
/// samples. May be disconnected (most graphs at low density are); may have
/// zero edges.
Gen<TestGraph> genGraph({int maxNodes = 40}) {
  return (rng) {
    final n = rng.intBetween(1, maxNodes);
    final maxPossible = n * (n - 1) ~/ 2;
    final density = rng.nextDouble();
    final targetEdges = (maxPossible * density).round();
    final seen = <int>{};
    final edges = <(int, int, double)>[];
    var attempts = 0;
    final attemptCap = targetEdges * 20 + 50;
    while (edges.length < targetEdges && attempts < attemptCap) {
      attempts++;
      final a = rng.nextInt(n);
      final b = rng.nextInt(n);
      if (a == b) continue;
      final lo = math.min(a, b);
      final hi = math.max(a, b);
      final key = lo * n + hi;
      if (!seen.add(key)) continue;
      edges.add((lo, hi, _positiveWeight(rng)));
    }
    return TestGraph(n, edges);
  };
}

/// A graph guaranteed to be a single connected component: a random
/// spanning tree (each node `i >= 1` attaches to a uniformly random earlier
/// node) plus extra random edges layered on top for cycles/density.
Gen<TestGraph> genConnectedGraph({int maxNodes = 40}) {
  return (rng) {
    final n = rng.intBetween(1, maxNodes);
    final seen = <int>{};
    final edges = <(int, int, double)>[];
    void addEdge(int a, int b) {
      if (a == b) return;
      final lo = math.min(a, b);
      final hi = math.max(a, b);
      final key = lo * n + hi;
      if (!seen.add(key)) return;
      edges.add((lo, hi, _positiveWeight(rng)));
    }

    for (var i = 1; i < n; i++) {
      addEdge(i, rng.nextInt(i));
    }
    final extra = n <= 1 ? 0 : rng.intBetween(0, n);
    for (var i = 0; i < extra; i++) {
      addEdge(rng.nextInt(n), rng.nextInt(n));
    }
    return TestGraph(n, edges);
  };
}

/// A random tree: exactly `n - 1` edges, connected, acyclic. Same spanning
/// -tree construction as [genConnectedGraph] but with no extra edges added.
Gen<TestGraph> genTree({int maxNodes = 40}) {
  return (rng) {
    final n = rng.intBetween(1, maxNodes);
    final edges = <(int, int, double)>[];
    for (var i = 1; i < n; i++) {
      edges.add((rng.nextInt(i), i, _positiveWeight(rng)));
    }
    return TestGraph(n, edges);
  };
}

/// A graph guaranteed to have at least [minComponents] connected
/// components: builds that many independent connected "blobs" (each its
/// own random spanning tree) and never adds an edge between blobs.
Gen<TestGraph> genDisconnectedGraph({
  int maxNodes = 40,
  int minComponents = 2,
}) {
  return (rng) {
    final effectiveMax = math.max(maxNodes, minComponents);
    final k = rng.intBetween(minComponents, minComponents + 3);
    final totalNodes = rng.intBetween(k, math.max(k, effectiveMax));
    final sizes = List<int>.filled(k, 1);
    final extraNodes = totalNodes - k;
    for (var i = 0; i < extraNodes; i++) {
      sizes[rng.nextInt(k)]++;
    }
    final edges = <(int, int, double)>[];
    var offset = 0;
    for (var c = 0; c < k; c++) {
      final size = sizes[c];
      for (var i = 1; i < size; i++) {
        final parent = rng.nextInt(i) + offset;
        final child = i + offset;
        edges.add((parent, child, _positiveWeight(rng)));
      }
      offset += size;
    }
    return TestGraph(offset, edges);
  };
}

// ---------------------------------------------------------------------------
// Oracles - independent reference implementations. These are intentionally
// the simplest-possible-correct algorithm, never the fast one: their only
// job is to be obviously right, so the engine's fast/approximate/spectral
// paths have something honest to be checked against.
// ---------------------------------------------------------------------------

/// The number of connected components of [g] (its zeroth Betti number,
/// beta-0: how many disjoint pieces the graph falls into - an isolated
/// node is its own component). Computed with plain union-find over the
/// edge list; this is the beta-0 oracle every spectral/approximate
/// component-counting path in the engine should agree with.
int connectedComponents(TestGraph g) {
  final parent = List<int>.generate(g.n, (i) => i);
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]]; // path halving
      x = parent[x];
    }
    return x;
  }

  for (final (a, b, _) in g.edges) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }
  final roots = <int>{};
  for (var i = 0; i < g.n; i++) {
    roots.add(find(i));
  }
  return roots.length;
}

/// The dense, symmetric `n x n` adjacency matrix of [g]. Parallel edges
/// between the same pair of nodes have their weights summed.
List<List<double>> denseAdjacency(TestGraph g) {
  final adjacency = List.generate(g.n, (_) => List<double>.filled(g.n, 0.0));
  for (final (a, b, w) in g.edges) {
    adjacency[a][b] += w;
    adjacency[b][a] += w;
  }
  return adjacency;
}

/// The dense combinatorial Laplacian `L = D - A` of [g], where `D` is the
/// diagonal weighted-degree matrix and `A` is [denseAdjacency]. Reference
/// for any engine computation phrased in terms of the graph Laplacian
/// (spectral gap, diffusion, etc.) - every row sums to exactly zero by
/// construction, a cheap sanity check on any Laplacian this or the engine
/// produces.
List<List<double>> denseLaplacian(TestGraph g) {
  final adjacency = denseAdjacency(g);
  final laplacian = List.generate(g.n, (_) => List<double>.filled(g.n, 0.0));
  for (var i = 0; i < g.n; i++) {
    var degree = 0.0;
    for (var j = 0; j < g.n; j++) {
      degree += adjacency[i][j];
      if (j != i) laplacian[i][j] = -adjacency[i][j];
    }
    laplacian[i][i] = degree;
  }
  return laplacian;
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

/// Draws one value from [gen] using a fresh `Rng(seed)` - a one-off escape
/// hatch for tests that want a single concrete sample rather than a full
/// `forAll` sweep.
T runGen<T>(Gen<T> gen, int seed) => gen(Rng(seed));
