// os_probe_corpus.dart — shared cross-OS differential probe.
//
// Runs a FIXED, hardcoded, adversarial corpus of inputs through every
// OS-sensitive PURE function this app ships, and returns one flat
// JSON-serializable map keyed `<funcName>::<inputLabel>`.
//
// This file is imported by BOTH sides of the differential test:
//   - directly, in-process, on Windows (test/fuzz/cross_os_differential_test.dart)
//   - via test/support/os_probe_main.dart, run under `flutter test` inside
//     an isolated Linux worktree through WSL2
//
// Determinism contract: no wall-clock reads, no `Random`, no filesystem
// or process I/O, no ambient global mutable state. Every entry must
// produce the exact same bytes on every run on the SAME os. Whether it
// must also match ACROSS oses is a per-key property documented below.
//
// Key convention:
//   - Ordinary keys (`funcName::label`) are asserted EQUAL across
//     Windows and Linux by the differential test — these are functions
//     that take no OS-dependent input (paths are always explicit
//     strings, never read from `Platform` or the filesystem) and so
//     MUST behave identically regardless of host OS. A mismatch here
//     is a genuine cross-OS bug: a hidden path separator, a locale-
//     sensitive sort/case-fold, a line-ending assumption, or float
//     non-determinism in a numeric routine.
//   - Keys prefixed `INTENTIONAL::` read ambient `Platform.isWindows`
//     (or equivalent) BY DESIGN and are expected to differ. The
//     differential test asserts each side against its own expected
//     per-OS value instead of asserting cross-OS equality.
//
// Keep this corpus small-ish but adversarial — every entry earns its
// place by probing a specific way OS-sensitivity could sneak in
// (backslash vs forward slash, trailing separators, mixed-script
// unicode, case-folding, Turkish-İ, CRLF vs LF, malformed percent
// escapes, surrogate pairs, emoji, combining marks).

import 'package:git_desktop/backend/desk_pr_store.dart';
import 'package:git_desktop/backend/engram_tokenizer.dart';
import 'package:git_desktop/backend/geometric_tokenizer.dart';
import 'package:git_desktop/backend/logos_git_calibration.dart';
import 'package:git_desktop/features/branches/branch_ops.dart';
import 'package:git_desktop/features/diff/diff_models.dart';

/// Run the full probe corpus and return one flat, JSON-serializable map.
Map<String, Object?> computeOsProbe() {
  final out = <String, Object?>{};
  _probeNormalizeWorktreePath(out);
  _probeParseUnifiedDiff(out);
  _probeDeskPrBranchCodec(out);
  _probeGeometricTokenizer(out);
  _probeSplitIdentifier(out);
  _probeStringSort(out);
  _probeLockKeyForIntentional(out);
  return out;
}

// ---------------------------------------------------------------------------
// normalizeWorktreePath — OS-invariant given an EXPLICIT caseFold.
// ---------------------------------------------------------------------------

const List<(String, String)> _pathCorpus = [
  ('backslash-basic', r'C:\Users\mini server\Projects\repo'),
  ('backslash-upper', r'C:\Users\MINI SERVER\Projects\REPO'),
  ('forward-basic', '/home/user/repo'),
  ('forward-trailing-slash', '/home/user/repo/'),
  ('backslash-trailing-slash', r'C:\Users\mini server\Projects\repo\'),
  ('mixed-separators', r'mixed/path\separators\here/mixed'),
  ('many-trailing-slashes', 'trailing/slashes///'),
  ('unicode-mixed-script', 'ÜNICÖDE/Пример/日本語/path'),
  ('case-variant', 'CaseVariant/PATH/Mixed'),
  ('inner-spaces-preserved', '  leading and trailing spaces  '),
  ('root-slash', '/'),
  ('empty', ''),
  ('single-char', 'a'),
  ('unc-device-path', r'\\?\C:\weird\device\path'),
  ('dotdot-relative', 'relative/../path/../here'),
  // Turkish dotted/dotless I is the canonical locale-sensitive
  // case-folding trap (ICU default-locale toLowerCase would map
  // 'İ' -> 'i̇' with a combining dot under a Turkish locale, but plain
  // Unicode-table folding does not). Dart's String.toLowerCase() is
  // NOT locale-aware, so both OSes must agree regardless of host
  // locale settings.
  ('turkish-i', 'İstanbul/DOSYA/İ/dizin'),
  ('emoji-and-surrogate-pair', 'repo/🔥branch/𝕆bject/path'),
  ('combining-marks', 'café/Über/naïve'),
];

void _probeNormalizeWorktreePath(Map<String, Object?> out) {
  for (final (label, path) in _pathCorpus) {
    out['normalizeWorktreePath::caseFoldTrue::$label'] =
        normalizeWorktreePath(path, caseFold: true);
    out['normalizeWorktreePath::caseFoldFalse::$label'] =
        normalizeWorktreePath(path, caseFold: false);
  }
}

// ---------------------------------------------------------------------------
// parseUnifiedDiff — OS-invariant; run over both a CRLF and an LF corpus.
// ---------------------------------------------------------------------------

const String _unifiedDiffLf = '''
diff --git a/src/a.txt b/src/a.txt
index 1111111..2222222 100644
--- a/src/a.txt
+++ b/src/a.txt
@@ -1,3 +1,4 @@
 context line one
-old line Ünïcödé
+new line 日本語
+another added line 🔥
 trailing context
\\ No newline at end of file
diff --git a/src/b.txt b/src/renamed_b.txt
similarity index 90%
rename from src/b.txt
rename to src/renamed_b.txt
--- a/src/b.txt
+++ b/src/renamed_b.txt
@@ -1,2 +1,2 @@
-line B old
+line B new
 shared context
diff --git a/bin/blob.dat b/bin/blob.dat
new file mode 100644
Binary files /dev/null and b/bin/blob.dat differ
''';

List<Map<String, Object?>> _serializeParsed(String diffText) =>
    parseUnifiedDiff(diffText)
        .map((l) => {
              'text': l.text,
              'lowerText': l.lowerText,
              'kind': l.kind.name,
              'lineNumOld': l.lineNumOld,
              'lineNumNew': l.lineNumNew,
              'hunkIndex': l.hunkIndex,
              'filePath': l.filePath,
              'isStaged': l.isStaged,
              'noNewlineAtEof': l.noNewlineAtEof,
            })
        .toList();

void _probeParseUnifiedDiff(Map<String, Object?> out) {
  out['parseUnifiedDiff::lf'] = _serializeParsed(_unifiedDiffLf);
  out['parseUnifiedDiff::crlf'] =
      _serializeParsed(_unifiedDiffLf.replaceAll('\n', '\r\n'));
}

// ---------------------------------------------------------------------------
// DeskPrStore.encodeBranch / decodeBranch — OS-invariant (pure percent-codec).
// ---------------------------------------------------------------------------

const List<(String, String)> _branchCorpus = [
  ('plain', 'feature/add-thing'),
  ('tilde', 'feat/~x'),
  ('collision-risk', 'feat-x'),
  ('deep-segments', 'a/b/c/d'),
  ('spaces', 'branch with spaces'),
  ('percent-literal', 'branch%20percent'),
  ('already-percent-encoded', '%25already-encoded'),
  ('unicode-emoji', 'ünïcödé/日本語/emoji-🔥-branch'),
  ('dotdot', '..dotdot..'),
  ('trailing-dot', 'trailing.'),
  ('leading-slash', '/leading-slash'),
  ('trailing-slash', 'trailing-slash/'),
  ('colon', 'colon:branch'),
  ('glob-chars', 'question?mark*and[brackets]'),
  ('backslash', r'back\slash\branch'),
  ('empty', ''),
  ('whitespace-only', '   '),
  ('long-repeat', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
];

// Raw (possibly malformed) already-encoded strings, decoded directly —
// stresses decodeBranch's percent-escape handling independent of
// whatever encodeBranch would itself produce.
const List<(String, String)> _rawEncodedCorpus = [
  ('slash-escape-not-produced-by-encode', 'feat%2Fx'),
  ('bad-hex', 'feat%zz-bad-hex'),
  ('trailing-percent', 'trailing%'),
  ('partial-escape', 'partial%2'),
  ('double-percent', '%25%25double-percent'),
  ('no-escapes', 'plain-no-escapes'),
  ('empty', ''),
];

void _probeDeskPrBranchCodec(Map<String, Object?> out) {
  for (final (label, branch) in _branchCorpus) {
    final encoded = DeskPrStore.encodeBranch(branch);
    out['encodeBranch::$label'] = encoded;
    out['decodeBranchRoundtrip::$label'] = DeskPrStore.decodeBranch(encoded);
  }
  for (final (label, raw) in _rawEncodedCorpus) {
    out['decodeBranchDirect::$label'] = DeskPrStore.decodeBranch(raw);
  }
}

// ---------------------------------------------------------------------------
// GeometricTokenizer — OS-invariant; byte-level determinism across OS is
// exactly the property under test (Jacobi eigensolve + bigram counts +
// vocabulary build, no RNG per geometric_tokenizer_test.dart's own
// docstring — but Jacobi rotation angles route through math.sqrt/atan2,
// which on some platforms fall through to the native libm, so this is a
// real place cross-OS float drift could hide).
// ---------------------------------------------------------------------------

const List<String> _tokenizerTrainingCorpus = [
  'final result = computeValue(input, context);\n'
      'final result = computeValue(other, context);\n'
      'return result.normalize();',
  'class WidgetState extends State<Widget> {\n'
      '  final WidgetState state = WidgetState();\n'
      '  void update() => setState(() => state.value = value);\n'
      '}',
  'ℂ[(Z/2)⁸] ⊕ Cl(8) ≅ 𝕆 — signature (3,5) ✓ 日本語 🔥',
];

const List<(String, String)> _tokenizerProbes = [
  ('seen-source', 'final result = computeValue(input, context);'),
  ('unseen-ascii', 'totally unseen but ascii words 123 !@#'),
  ('empty', ''),
  ('mixed-unicode', '𝕆 𝕊 𝕋 · λ∇∂ ≤ ≥ ≠ é ñ 日本語 🜂'),
  ('mixed-whitespace', '\r\n\t mixed \r\n whitespace \n here'),
];

void _probeGeometricTokenizer(Map<String, Object?> out) {
  final tok = GeometricTokenizer.train(_tokenizerTrainingCorpus);
  out['GeometricTokenizer::describe'] = tok.describe();
  out['GeometricTokenizer::vocabSize'] = tok.vocabSize;
  for (final (label, probe) in _tokenizerProbes) {
    final ids = tok.encode(probe);
    out['GeometricTokenizer::encode::$label'] = ids;
    out['GeometricTokenizer::decodeRoundtrip::$label'] = tok.decode(ids);
  }
}

// ---------------------------------------------------------------------------
// splitIdentifier — OS-invariant (pure ASCII-range code-unit classification;
// catches accidental locale-sensitive case conversion).
// ---------------------------------------------------------------------------

const List<(String, String)> _identifierCorpus = [
  ('camel', 'getUserAuthProfile'),
  ('acronym-leading', 'HTTPResponseCode'),
  ('snake', 'build_diff_hunk'),
  ('kebab', 'kebab-case-name'),
  ('acronym-trailing-digit', 'PHPVersion8'),
  ('digit-leading-word', 'iOS15Device'),
  ('all-caps-run', 'XMLHttpRequest'),
  ('unicode-digits', 'snake_case_数字123'),
  ('dunder', '__dunder__'),
  ('allcaps', 'ALLCAPS'),
  ('mixed-punct', 'mixedCASE_with-Dashes.and.Dots'),
  ('alnum-interleave', 'a1b2c3'),
  ('unicode-ident', 'ünïcödé_ident'),
  ('empty', ''),
  ('digits-only', '123456'),
  ('spaced', '  spaced ident  '),
  ('turkish-i', 'İstanbulCity'),
];

void _probeSplitIdentifier(Map<String, Object?> out) {
  for (final (label, ident) in _identifierCorpus) {
    out['splitIdentifier::$label'] = splitIdentifier(ident);
  }
}

// ---------------------------------------------------------------------------
// Dart string sort — catches accidental locale-aware collation. Dart's
// default `Comparable`-based String `sort()` is a pure UTF-16 code-unit
// ordinal comparison (no ICU collation), so it must be identical on every
// OS/locale — an accidental switch to a locale-aware comparator anywhere
// upstream would show up here first.
// ---------------------------------------------------------------------------

const List<String> _sortCorpus = [
  'Banana', 'banana', 'Àpple', 'apple', 'apple2', 'APPLE', 'Ärger', 'arger',
  '日本語', 'にほんご', 'Zebra', 'able', 'Able', '_underscore', '1number',
  'émoji🔥string', 'émoji🔥string2', 'ß', 'straße', 'strasse', '',
  ' leading space', 'trailing space ', 'Ω', 'ω', 'İstanbul', 'istanbul',
];

void _probeStringSort(Map<String, Object?> out) {
  final sorted = List<String>.of(_sortCorpus)..sort();
  out['stringSort::hostileUnicodeList'] = sorted;
}

// ---------------------------------------------------------------------------
// LogosSseStore.lockKeyFor — INTENTIONALLY platform-branching (reads
// Platform.isWindows to decide whether to case-fold). Labeled so the
// differential test asserts each side against its OWN expected value
// instead of cross-OS equality.
// ---------------------------------------------------------------------------

// Public (not `_`-prefixed) so cross_os_differential_test.dart can
// independently replicate the non-Windows branch of lockKeyFor's logic
// per input and assert each OS's `INTENTIONAL::` output against its own
// expected value, rather than against the other OS's output.
const List<(String, String)> lockKeyForCorpus = [
  ('backslash-basic', r'C:\Users\mini server\Projects\repo'),
  ('forward-basic', '/home/user/Repo'),
  ('backslash-trailing', r'C:\Users\MINI SERVER\Projects\REPO\'),
  ('forward-trailing', '/home/user/repo/'),
  ('mixed-case-mixed-sep', r'MixedCase/Path\Here/'),
];

void _probeLockKeyForIntentional(Map<String, Object?> out) {
  for (final (label, path) in lockKeyForCorpus) {
    out['INTENTIONAL::lockKeyFor::$label'] = LogosSseStore.lockKeyFor(path);
  }
}
