import 'dart:typed_data';

enum LineKind { added, deleted, hunk, meta, context }

/// SplitMix64 avalanche — Principia Mathematica Obscura, Circle XVII.
/// Mixes 64 input bits such that flipping any single input bit changes
/// approximately half the output bits. Used to derive stable integer
/// identities from structural inputs (hunk index, line numbers, text
/// hash). Constants are the canonical Stafford-tuned finalizer from
/// splitmix64(), preserving the avalanche property at every step.
int _splitmix64(int z) {
  z += 0x9e3779b97f4a7c15;
  z = (z ^ (z >>> 30)) * 0xbf58476d1ce4e5b9;
  z = (z ^ (z >>> 27)) * 0x94d049bb133111eb;
  return z ^ (z >>> 31);
}

class ParsedLine {
  final String text;
  final String lowerText;
  final LineKind kind;
  final int? lineNumOld;
  final int? lineNumNew;
  final int hunkIndex;
  final String? filePath;
  final bool isStaged;

  /// True when git emitted `\ No newline at end of file` immediately
  /// after this line in the unified diff. Applies to whichever side
  /// (old or new) this line participates in. Persisted here (rather
  /// than as a standalone `meta` ParsedLine) so the patch engine can
  /// reconstruct the marker after the correct line and the parser
  /// doesn't mistakenly consume a line-number counter for it.
  final bool noNewlineAtEof;

  /// Content-derived 64-bit identity — stable across stage toggles, derived
  /// from (hunkIndex, lineNumOld, lineNumNew, text.hashCode) via SplitMix64
  /// avalanche. The hot paths in the diff shell use this instead of the
  /// [stagingKey] string so that per-row `ValueKey`, `Set`/`Map` lookups,
  /// and ListView rebuilds during scroll do not allocate strings per
  /// frame. Integer hash + integer equality → single-cycle comparisons,
  /// no interpolation, no GC pressure. The collision probability at
  /// 64 bits is ~$2^{-64}$, so the fast path is effectively exact for
  /// any realistic diff size (birthday bound ≈ 4 billion entries before
  /// a 50% chance of collision — Principia Circle XLV).
  final int fastKey;

  /// SWAR presence bitmap — a 64-bit signature of which characters appear
  /// anywhere in [lowerText]. For each code-unit `c` the bit at
  /// position `c & 0x3F` is set, folding the 7-bit ASCII range into 64
  /// bits (letters / digits / common punctuation each land in distinct
  /// slots; uppercase folds onto lowercase naturally since lowerText is
  /// already case-folded).
  /// Used as the first-stage pre-filter for substring search. A query's
  /// charBits is computed once; every line runs one `AND` against it, and
  /// lines missing any query character are rejected without running the
  /// substring scan. Transposed from Whisper Logos' per-axis bit-tree
  /// counters (logos.wat circa `f0C / o2C / abC`) — precompute a dense
  /// bit-level summary once, then use bitwise ops at query time.
  /// Principia Circle II (SWAR — SIMD within a register).
  final int charBits;

  /// Bigram SWAR bitmap — a SECOND-STAGE filter that catches cases the
  /// single-character [charBits] can't. For queries like "function" where
  /// every character is common (f, u, n, c, t, i, o are all in nearly
  /// every line), charBits saturates and fails to reject. But the SPECIFIC
  /// 2-grams (fu, un, nc, ct, ti, io, on) are much rarer — lines that
  /// don't contain at least one of them cannot contain the full query.
  /// Each adjacent code-unit pair `(c₀, c₁)` hashes to a bit position
  /// via `((c₀ & 0x3F) * 37 + (c₁ & 0x3F)) & 0x3F` — multiplicative
  /// scramble that spreads bigrams roughly uniformly across 64 bits
  /// despite the compressed address space. Runtime cost: one AND + one
  /// compare per line during search, identical to the charBits check.
  /// Storage cost: 8 bytes per line. For long queries this filter
  /// contributes another ~order of magnitude of rejection on top of
  /// charBits — the cumulative `(charBits & qc) == qc && (bigramBits &
  /// qb) == qb` check typically drops to <1% pass-through for queries
  /// ≥ 4 characters.
  /// Principia Circle XXVIII (shift-or bitap family) — a sparser N-gram
  /// presence filter, though we stop short of full Bitap NFA since
  /// Dart's native `String.contains` is already SIMD-accelerated and
  /// pays for itself once we've reached the shrinking pass-through set.
  final int bigramBits;

  /// SimHash locality-sensitive 64-bit signature. For each character
  /// trigram in [lowerText], compute a 64-bit hash; bit `k` of the
  /// output is `1` iff a weighted sum over all trigram-hash bit `k`
  /// values is positive. Hamming distance between two SimHashes tracks
  /// with cosine distance between the underlying trigram sets — lines
  /// that share many trigrams end up with SimHashes differing in few
  /// bits, so a `popcount(a ^ b)` threshold becomes a cheap fuzzy
  /// similarity test.
  /// Used by the fuzzy move-detection pass to catch relocations that
  /// also edited one or two identifiers (e.g. `function foo(x)` moved
  /// and renamed to `function bar(x)`). Exact-match Rabin-Karp handles
  /// identical-block moves; SimHash handles the surrounding signature
  /// line that exact matching misses.
  /// Principia Circle XVII (SplitMix64 avalanche per trigram) combined
  /// with a bit-counting projection — sign-of-weighted-sum per output
  /// bit. Zero for lines shorter than 3 characters (no trigrams).
  final int simHash;

  ParsedLine({
    required this.text,
    required this.lowerText,
    required this.kind,
    this.lineNumOld,
    this.lineNumNew,
    this.hunkIndex = -1,
    this.filePath,
    this.isStaged = false,
    this.noNewlineAtEof = false,
  })  : fastKey = _computeFastKey(hunkIndex, lineNumOld, lineNumNew, text),
        charBits = _computeCharBits(lowerText),
        bigramBits = _computeBigramBits(lowerText),
        simHash = _computeSimHash(lowerText);

  static int _computeFastKey(
      int hunkIndex, int? lnOld, int? lnNew, String text) {
    // Pack structural position into high/mid/low bit slots first so each
    // field contributes independent entropy before the avalanche runs.
    // lnOld/lnNew default to -1 so the key is stable even for context-only
    // lines where only one side has a number.
    final pos = (hunkIndex << 48) ^
        (((lnOld ?? -1) & 0xFFFFFF) << 24) ^
        ((lnNew ?? -1) & 0xFFFFFF);
    // text.hashCode is cached by the Dart VM after first call, so the
    // O(n) work happens exactly once per ParsedLine lifetime.
    return _splitmix64(pos) ^ _splitmix64(text.hashCode);
  }

  /// OR the bit at position `(c & 0x3F)` for every code unit of [lowerText].
  /// Folds the 7-bit ASCII range into 64 bits in a way that preserves good
  /// discrimination for letters, digits, and common code punctuation.
  static int _computeCharBits(String lowerText) {
    int bits = 0;
    final n = lowerText.length;
    for (int i = 0; i < n; i++) {
      bits |= 1 << (lowerText.codeUnitAt(i) & 0x3F);
    }
    return bits;
  }

  /// OR the bit at position `((c₀ & 0x3F) * 37 + (c₁ & 0x3F)) & 0x3F` for
  /// every adjacent code-unit pair in [lowerText]. 37 is a small prime
  /// that mixes the two character slots without degenerate alignment, so
  /// different bigrams with the same character multiset (e.g. "ab" vs
  /// "ba") land in different bits. Runs in a single pass with a carried
  /// previous byte, no substring allocation.
  static int _computeBigramBits(String lowerText) {
    final n = lowerText.length;
    if (n < 2) return 0;
    int bits = 0;
    int prev = lowerText.codeUnitAt(0) & 0x3F;
    for (int i = 1; i < n; i++) {
      final cur = lowerText.codeUnitAt(i) & 0x3F;
      bits |= 1 << (((prev * 37) + cur) & 0x3F);
      prev = cur;
    }
    return bits;
  }

  /// Build the SWAR presence bitmap for a query term the same way
  /// [_computeCharBits] does for lines. Exported so the diff shell can
  /// compute it once per keystroke and reuse it across the filter pass.
  static int queryCharBits(String lowerTerm) => _computeCharBits(lowerTerm);

  /// Build the bigram SWAR bitmap for a query term — mirror of
  /// [_computeBigramBits]. Returns 0 for queries shorter than 2 characters,
  /// signalling the caller to skip the bigram stage (char-stage only).
  static int queryBigramBits(String lowerTerm) => _computeBigramBits(lowerTerm);

  /// SimHash computation. Implements the sign-of-weighted-sum projection:
  ///   1. For each character trigram `(c₀, c₁, c₂)` in lowerText, hash via
  ///      SplitMix64 to produce a 64-bit fingerprint.
  ///   2. For each of the 64 output bit positions, maintain a running
  ///      weight counter: +1 if the fingerprint's bit `k` is set, -1
  ///      otherwise.
  ///   3. Output bit `k` = 1 iff final weight `k` > 0.
  /// Runs two counters in parallel (`Int32List[64]`) with a single
  /// per-trigram bit-walk. Cost is O(n·64) per line; on a 50-char line
  /// that's 3k simple integer ops — negligible at parse time.
  static int _computeSimHash(String lowerText) {
    final n = lowerText.length;
    if (n < 3) return 0;
    // 64 lanes of +/- weight. Using an Int32List keeps the inner loop
    // branch-free: we accumulate (bit-set ? +1 : -1) without a conditional.
    final weights = Int32List(64);
    for (int i = 0; i <= n - 3; i++) {
      // Pack trigram into 24 bits, then avalanche to 64.
      final tri = (lowerText.codeUnitAt(i) & 0xFF) |
          ((lowerText.codeUnitAt(i + 1) & 0xFF) << 8) |
          ((lowerText.codeUnitAt(i + 2) & 0xFF) << 16);
      final h = _splitmix64(tri);
      for (int k = 0; k < 64; k++) {
        // Branch-free (+1, -1): 1 - 2*((h >> k) & 1) gives +1 for bit 0, -1 for bit 1.
        // Invert: bit 1 = +1, bit 0 = -1 for readability.
        weights[k] += ((h >>> k) & 1) != 0 ? 1 : -1;
      }
    }
    int out = 0;
    for (int k = 0; k < 64; k++) {
      if (weights[k] > 0) out |= 1 << k;
    }
    return out;
  }

  /// Hamming distance between two 64-bit values via the canonical
  /// parallel-bit-sum popcount (Principia Circle II — SWAR). No builtin
  /// in Dart for this; rolling our own keeps us in the integer pipeline.
  ///   step 1: subtract pairs  (2-bit counts)
  ///   step 2: sum adjacent 2-bit pairs into 4-bit counts
  ///   step 3: mask into 8-bit groups
  ///   step 4: multiply by 0x0101... to cascade all bytes into the MSB
  ///           via carries, then shift the sum down from the top byte.
  /// Five fused ops give the total in O(1). Used by the fuzzy move
  /// matcher to compare SimHashes cheaply (sub-microsecond per pair).
  static int hamming64(int a, int b) {
    int x = a ^ b;
    x = x - ((x >>> 1) & 0x5555555555555555);
    x = (x & 0x3333333333333333) + ((x >>> 2) & 0x3333333333333333);
    x = (x + (x >>> 4)) & 0x0F0F0F0F0F0F0F0F;
    return ((x * 0x0101010101010101) >>> 56) & 0x7F;
  }

  ParsedLine copyWith({
    bool? isStaged,
    bool? noNewlineAtEof,
    String? filePath,
  }) {
    return ParsedLine(
      text: text,
      lowerText: lowerText,
      kind: kind,
      lineNumOld: lineNumOld,
      lineNumNew: lineNumNew,
      hunkIndex: hunkIndex,
      filePath: filePath ?? this.filePath,
      isStaged: isStaged ?? this.isStaged,
      noNewlineAtEof: noNewlineAtEof ?? this.noNewlineAtEof,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ParsedLine &&
          fastKey == other.fastKey &&
          isStaged == other.isStaged &&
          // Text check guards the 2^-64 collision case. Pays its way only
          // on fastKey matches, which is already the common equality path.
          text == other.text);

  @override
  int get hashCode => fastKey ^ (isStaged ? 1 : 0);
}

/// Parse a raw unified-diff string (the kind `git diff` or `gh pr diff`
/// emits) into a flat list of [ParsedLine]s. Each line carries its kind
/// (added / deleted / context / hunk / meta), line numbers, hunk index,
/// and the file path it belongs to (extracted from the `diff --git`
/// header). Multi-file diffs preserve [ParsedLine.filePath] on every
/// line so callers can post-filter by file. Handles `\ No newline at
/// end of file` markers by attaching them to the previous line via
/// [ParsedLine.noNewlineAtEof] without consuming a counter slot.
/// This is the canonical parser for the app — used by the changes-panel
/// diff shell, the patch engine, and the PR detail surface so every
/// place that reads a diff sees the exact same model.
List<ParsedLine> parseUnifiedDiff(String diff) {
  final rawLines = diff.split('\n');
  final result = <ParsedLine>[];
  int oldLine = 0, newLine = 0, hunkIdx = -1;
  String? currentFile;
  String? pendingOldFile;

  final diffHeaderRe = RegExp(r'^diff --git a/(.+) b/(.+)$');
  for (final line in rawLines) {
    if (line.startsWith('diff --git')) {
      final m = diffHeaderRe.firstMatch(line);
      if (m != null) currentFile = m.group(2) ?? m.group(1);
      pendingOldFile = null;
      continue;
    }
    if (line.startsWith('diff ') || line.startsWith('index ')) {
      continue;
    }
    if (line.startsWith('@@')) {
      final m =
          RegExp(r'@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@').firstMatch(line);
      if (m != null) {
        oldLine = int.tryParse(m.group(1)!) ?? 0;
        newLine = int.tryParse(m.group(2)!) ?? 0;
      }
      hunkIdx++;
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.hunk,
          hunkIndex: hunkIdx,
          filePath: currentFile));
    } else if (line.startsWith('+') && !line.startsWith('+++')) {
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.added,
          lineNumNew: newLine++,
          hunkIndex: hunkIdx,
          filePath: currentFile));
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.deleted,
          lineNumOld: oldLine++,
          hunkIndex: hunkIdx,
          filePath: currentFile));
    } else if (line.startsWith('\\')) {
      // `\ No newline at end of file` — attach the flag to the prior
      // line. See ParsedLine.noNewlineAtEof for the full reasoning.
      if (result.isNotEmpty) {
        final prev = result.removeLast();
        result.add(prev.copyWith(noNewlineAtEof: true));
      }
    } else if (line.startsWith('--- ')) {
      pendingOldFile = _patchSidePath(line, preferredPrefix: 'a');
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.meta,
          filePath: currentFile ?? pendingOldFile));
    } else if (line.startsWith('+++ ')) {
      currentFile = _patchSidePath(line, preferredPrefix: 'b') ??
          pendingOldFile ??
          currentFile;
      pendingOldFile = null;
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.meta,
          filePath: currentFile));
    } else if (line.startsWith('new file mode ') ||
        line.startsWith('deleted file mode ') ||
        line.startsWith('old mode ') ||
        line.startsWith('new mode ') ||
        line.startsWith('similarity index ') ||
        line.startsWith('rename from ') ||
        line.startsWith('rename to ') ||
        line.startsWith('Binary files ') ||
        line.startsWith('GIT binary patch')) {
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.meta,
          filePath: currentFile));
    } else if (line.isNotEmpty) {
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.context,
          lineNumOld: oldLine++,
          lineNumNew: newLine++,
          hunkIndex: hunkIdx,
          filePath: currentFile));
    } else {
      result.add(ParsedLine(
          text: line,
          lowerText: '',
          kind: LineKind.context,
          hunkIndex: hunkIdx));
    }
  }

  return result;
}

/// Slice a multi-file unified diff into per-file sections, keyed by the
/// `b/`-side (post-change) path — the same convention [parseUnifiedDiff]
/// uses for [ParsedLine.filePath], so slice keys match parsed-line
/// `filePath` values exactly. Each value is the raw diff text belonging
/// to that file, starting with its `diff --git ...` header and ending
/// just before the next file's header (or the end of the input).
/// Mirrors [parseUnifiedDiff]'s header regex so the two stay in lockstep
/// — any parser-side change to how paths are extracted must be mirrored
/// here. Returns an empty map for empty input; files whose header can't
/// be parsed are skipped (same degrade behaviour as the parser).
/// Used by surfaces that want to hand a RAW diff string to [DiffShell]
/// for a single file out of a multi-file PR payload, without forcing
/// the Shell to re-scan the full patch for every rebuild. Pair with
/// [diffByFile] (parsed form) on the same detail object so callers can
/// pick whichever representation they need.
Map<String, String> sliceDiffByFile(String raw) {
  if (raw.isEmpty) return const {};
  if (!raw.contains('diff --git ')) {
    return _sliceBareUnifiedDiffByFile(raw);
  }

  final lines = raw.split('\n');
  final result = <String, String>{};
  final diffHeaderRe = RegExp(r'^diff --git a/(.+) b/(.+)$');
  var sectionStart = -1;
  String? currentPath;
  void flush(int endExclusive) {
    if (sectionStart < 0 || currentPath == null) return;
    result[currentPath!] = lines.sublist(sectionStart, endExclusive).join('\n');
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('diff --git')) {
      flush(i);
      sectionStart = i;
      final m = diffHeaderRe.firstMatch(line);
      currentPath = m == null ? null : (m.group(2) ?? m.group(1));
    }
  }
  flush(lines.length);
  return result;
}

Map<String, String> _sliceBareUnifiedDiffByFile(String raw) {
  final lines = raw.split('\n');
  final result = <String, String>{};
  var sectionStart = -1;
  String? currentPath;

  void flush(int endExclusive) {
    if (sectionStart < 0 || currentPath == null) return;
    result[currentPath!] = lines.sublist(sectionStart, endExclusive).join('\n');
  }

  for (var i = 0; i < lines.length - 1; i++) {
    final minus = lines[i];
    final plus = lines[i + 1];
    if (!minus.startsWith('--- ') || !plus.startsWith('+++ ')) {
      continue;
    }

    flush(i);
    sectionStart = i;
    currentPath = _patchSidePath(plus, preferredPrefix: 'b') ??
        _patchSidePath(minus, preferredPrefix: 'a');
    i++;
  }

  flush(lines.length);
  return result;
}

String? _patchSidePath(String headerLine, {required String preferredPrefix}) {
  final marker = headerLine.length >= 4 ? headerLine.substring(0, 4) : '';
  if (marker != '--- ' && marker != '+++ ') return null;
  var value = headerLine.substring(4).trim();
  if (value.isEmpty || value == '/dev/null') return null;
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    value = value.substring(1, value.length - 1);
  }
  final prefixed = '$preferredPrefix/';
  if (value.startsWith(prefixed)) {
    return value.substring(prefixed.length);
  }
  return value;
}

/// Returns the index of the paired add/delete line for an edit-in-place,
/// or null if there is no pair. A pair is a deletion immediately followed
/// by an addition (or vice-versa) within the same hunk — the standard
/// shape of a single-line modification in a unified diff.
int? findReplacementPair(List<ParsedLine> lines, int index) {
  if (index < 0 || index >= lines.length) return null;
  final here = lines[index];
  if (here.kind != LineKind.added && here.kind != LineKind.deleted) return null;

  if (here.kind == LineKind.deleted) {
    final next = index + 1 < lines.length ? lines[index + 1] : null;
    if (next != null &&
        next.kind == LineKind.added &&
        next.hunkIndex == here.hunkIndex) {
      return index + 1;
    }
  } else {
    final prev = index - 1 >= 0 ? lines[index - 1] : null;
    if (prev != null &&
        prev.kind == LineKind.deleted &&
        prev.hunkIndex == here.hunkIndex) {
      return index - 1;
    }
  }
  return null;
}

class DiffStats {
  final int adds;
  final int dels;
  final int hunks;

  const DiffStats({this.adds = 0, this.dels = 0, this.hunks = 0});

  static DiffStats fromRawDiff(String diff) {
    int a = 0;
    int d = 0;
    int h = 0;
    for (final line in diff.split('\n')) {
      if (line.startsWith('@@ ')) {
        h++;
      } else if (line.startsWith('+') && !line.startsWith('+++')) {
        a++;
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        d++;
      }
    }
    return DiffStats(adds: a, dels: d, hunks: h);
  }
}

/// Expose the SplitMix64 avalanche function to other diff-layer code that
/// needs to derive stable integer identities from structural inputs (e.g.
/// EditUnit.id composed from hunkIndex + line numbers + text hashes). The
/// internal name is kept underscored so the symbol is module-private and
/// this re-export documents the contract explicitly.
int splitmix64(int z) => _splitmix64(z);
