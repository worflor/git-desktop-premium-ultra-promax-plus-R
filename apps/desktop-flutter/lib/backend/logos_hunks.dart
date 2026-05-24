// LOGOS HUNKS â€” hunk-level heat-kernel diffusion
//
// Sits parallel to LogosGit's file graph. Nodes are HUNKS inside one diff;
// edges are the geometric bonds between them:
//
//   H_sym  â€” shared non-trivial identifiers (Jaccard via inverted index)
//   H_file â€” parent-file coupling. Within-file = 1. Cross-file borrows
//            the already-computed file-Ï† from the LogosGit engine. This
//            is the factorisation trick â€” file-graph âŠ— hunk-graph â€”
//            so cross-file hunk coupling costs ~zero.
//   H_prox â€” within-file proximity kernel exp(-|Î”line|/Ïƒ_file) where
//            Ïƒ_file is the median line-gap inside that file (self-derived)
//   H_vol  â€” add/delete balance similarity; pure-add hunks cluster with
//            pure-add, pure-delete with pure-delete, balanced with balanced
//
// Weights compose as a convex blend; edges sparsified top-K per node;
// Laplacian normalised; heat-kernel via Chebyshev polynomial expansion
// (same math as logos_git.dart, just a smaller graph).
//
// Source mass Ï per hunk = log(1+bytes). Every hunk is a source â€” the
// diffusion measures centrality relative to the diff as a whole.
//
// Recombines at three temperatures (0.5, 1.0, 2.0) and blends via
// geometric mean â€” the three-temperature-blend trick from commit_tagger.
//
// Used by ai.dart's diff prompt packer: when the full diff overflows
// the budget, hunks are emitted in Ï†-desc order at full content. Logos
// picks which hunks matter most; peripheral mass-edit noise drops off.

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'engram_bootstrap.dart' show EngramAssets;
import 'engram_hunk_encoder.dart';
import 'graph/csr_builder.dart' show buildSymmetricCsrGraph;
import 'graph/top_k_symmetrise.dart' show topKSymmetriseEdges;
import 'logos_core.dart';
import 'logos_git.dart'
    show
        LogosEvidenceWitness,
        LogosGit,
        LogosResidualView,
        formatLogosEvidenceWitness;

// Data model

class DiffHunk {
  DiffHunk({
    required this.filePath,
    required this.hunkIndex,
    required this.header,
    required this.body,
    required this.oldStart,
    required this.newStart,
    required this.additions,
    required this.deletions,
  });

  /// Parent file (e.g. `lib/foo.dart`).
  final String filePath;

  /// 0-based index within the parent file's hunk list.
  final int hunkIndex;

  /// The `@@ -a,b +c,d @@` header line (trimmed).
  final String header;

  /// The hunk body including the header, +, -, and context lines, so
  /// emitting `body` in a prompt reproduces the original hunk exactly.
  final String body;

  /// Start line in the old file (from `@@ -oldStart,... @@`).
  final int oldStart;

  /// Start line in the new file (from `@@ ...,+newStart,... @@`).
  final int newStart;

  final int additions;
  final int deletions;

  int get bytes => body.length;

  int get churn => additions + deletions;
}

class HunkRanking {
  HunkRanking({
    required this.hunk,
    required this.phi,
    required this.rank,
    this.wellName,
    this.wellDistance,
    this.transportPull = 0.0,
    this.transportedSupport = 0.0,
    this.innovationResidual = 0.0,
    this.witnessResidual = 0.0,
    this.fileEvidenceWitnesses = const [],
    this.fileWitnesses = const [],
    this.spectralGap = 0.0,
  });
  final DiffHunk hunk;
  final double phi;
  final int rank; // 0 = top

  /// Nearest Alexandria well for this hunk (e.g. "computing", "well_43").
  /// Null when engram assets weren't loaded, the brain had zero wells, or
  /// the hunk didn't have enough in-vocab sub-tokens to fit an AR(2).
  /// Surfaced in the prompt bundle so the model sees feature-cluster
  /// membership alongside Ï†.
  final String? wellName;

  /// Raw RMS distance to the nearest well centroid in K-space. Lower =
  /// stronger domain match. Present whenever [wellName] is.
  final double? wellDistance;

  /// Canonical parent-file residual channels inherited from LogosGit.
  final double transportPull;
  final double transportedSupport;
  final double innovationResidual;
  final double witnessResidual;

  /// Structured parent-file witnesses inherited from LogosGit evidence.
  final List<LogosEvidenceWitness> fileEvidenceWitnesses;

  /// Parent-file witness labels inherited from LogosGit evidence. This
  /// carries file-level admission rationale down into hunk emission.
  final List<String> fileWitnesses;

  final double spectralGap;
}

// Parser â€” unified diff â†’ List<DiffHunk>

List<DiffHunk> parseDiffHunks(String diffText) {
  final result = <DiffHunk>[];
  final lines = diffText.split('\n');
  String? currentFile;
  int fileHunkIndex = 0;
  StringBuffer? hunkBuf;
  String? hunkHeader;
  int hunkOldStart = 0;
  int hunkNewStart = 0;
  int hunkAdds = 0;
  int hunkDels = 0;

  void flushHunk() {
    final file = currentFile;
    final header = hunkHeader;
    final buf = hunkBuf;
    if (file == null || buf == null || header == null) {
      hunkBuf = null;
      hunkHeader = null;
      return;
    }
    result.add(DiffHunk(
      filePath: file,
      hunkIndex: fileHunkIndex,
      header: header,
      body: buf.toString(),
      oldStart: hunkOldStart,
      newStart: hunkNewStart,
      additions: hunkAdds,
      deletions: hunkDels,
    ));
    fileHunkIndex++;
    hunkBuf = null;
    hunkHeader = null;
    hunkAdds = 0;
    hunkDels = 0;
  }

  final headerRe = RegExp(r'^@@\s*-(\d+)(?:,\d+)?\s*\+(\d+)(?:,\d+)?\s*@@');

  for (final line in lines) {
    if (line.startsWith('diff --git ')) {
      flushHunk();
      currentFile = _pathFromDiffHeader(line);
      fileHunkIndex = 0;
      continue;
    }
    if (currentFile == null) continue;
    if (line.startsWith('@@')) {
      flushHunk();
      final m = headerRe.firstMatch(line);
      hunkOldStart = m != null ? int.tryParse(m.group(1)!) ?? 0 : 0;
      hunkNewStart = m != null ? int.tryParse(m.group(2)!) ?? 0 : 0;
      hunkHeader = line.trim();
      hunkBuf = StringBuffer()..writeln(line);
      continue;
    }
    if (line.startsWith('+++ ') || line.startsWith('--- ')) continue;
    if (hunkBuf == null) continue;
    hunkBuf!.writeln(line);
    if (line.startsWith('+')) {
      hunkAdds++;
    } else if (line.startsWith('-')) {
      hunkDels++;
    }
  }
  flushHunk();
  return result;
}

/// Scoped variant of [parseDiffHunks] that only materialises hunks for
/// [filePath]. Skips over other files' sections without allocating their
/// bodies so a 22k-line multi-file diff can be walked in a fraction of the
/// time when only one file's hunks are needed (fallback path in
/// `DiffFileContextRequest` when the session has no pre-parsed cache).
///
/// `filePath` must be the post-rename (`b/`) path — same convention as
/// the headers git emits (`diff --git a/old b/new`). If the caller
/// supplies the pre-rename path it will silently not match and this
/// function returns an empty list.
List<DiffHunk> parseDiffHunksForFile(String diffText, String filePath) {
  final result = <DiffHunk>[];
  final lines = diffText.split('\n');
  var inTarget = false;
  var fileHunkIndex = 0;
  StringBuffer? hunkBuf;
  String? hunkHeader;
  var hunkOldStart = 0;
  var hunkNewStart = 0;
  var hunkAdds = 0;
  var hunkDels = 0;

  void flushHunk() {
    final header = hunkHeader;
    final buf = hunkBuf;
    if (!inTarget || buf == null || header == null) {
      hunkBuf = null;
      hunkHeader = null;
      hunkAdds = 0;
      hunkDels = 0;
      return;
    }
    result.add(DiffHunk(
      filePath: filePath,
      hunkIndex: fileHunkIndex,
      header: header,
      body: buf.toString(),
      oldStart: hunkOldStart,
      newStart: hunkNewStart,
      additions: hunkAdds,
      deletions: hunkDels,
    ));
    fileHunkIndex++;
    hunkBuf = null;
    hunkHeader = null;
    hunkAdds = 0;
    hunkDels = 0;
  }

  final headerRe = RegExp(r'^@@\s*-(\d+)(?:,\d+)?\s*\+(\d+)(?:,\d+)?\s*@@');

  for (final line in lines) {
    if (line.startsWith('diff --git ')) {
      flushHunk();
      final path = _pathFromDiffHeader(line);
      inTarget = path == filePath;
      fileHunkIndex = 0;
      continue;
    }
    if (!inTarget) continue;
    if (line.startsWith('@@')) {
      flushHunk();
      final m = headerRe.firstMatch(line);
      hunkOldStart = m != null ? int.tryParse(m.group(1)!) ?? 0 : 0;
      hunkNewStart = m != null ? int.tryParse(m.group(2)!) ?? 0 : 0;
      hunkHeader = line.trim();
      hunkBuf = StringBuffer()..writeln(line);
      continue;
    }
    if (line.startsWith('+++ ') || line.startsWith('--- ')) continue;
    if (hunkBuf == null) continue;
    hunkBuf!.writeln(line);
    if (line.startsWith('+')) {
      hunkAdds++;
    } else if (line.startsWith('-')) {
      hunkDels++;
    }
  }
  flushHunk();
  return result;
}

String _pathFromDiffHeader(String line) {
  final parts = line.split(' ');
  if (parts.length < 4) return 'unknown';
  final candidate = parts[3];
  final stripped =
      candidate.startsWith('b/') ? candidate.substring(2) : candidate;
  return _unCQuoteGitPath(stripped);
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

/// Reverse of git's `core.quotepath` encoding for paths containing
/// non-printable / special bytes. Unwraps the surrounding double
/// quotes and decodes `\n`, `\t`, `\r`, `\"`, `\\`, and octal
/// `\NNN` byte escapes. Non-quoted paths pass through unchanged.
String _unCQuoteGitPath(String s) {
  if (s.length < 2 || !s.startsWith('"') || !s.endsWith('"')) return s;
  final inner = s.substring(1, s.length - 1);
  final buf = StringBuffer();
  var i = 0;
  while (i < inner.length) {
    final c = inner.codeUnitAt(i);
    if (c == 0x5C && i + 1 < inner.length) {
      final n = inner.codeUnitAt(i + 1);
      if (n >= 0x30 && n <= 0x37 && i + 3 < inner.length) {
        final b = inner.codeUnitAt(i + 2);
        final d = inner.codeUnitAt(i + 3);
        if (b >= 0x30 && b <= 0x37 && d >= 0x30 && d <= 0x37) {
          buf.writeCharCode(((n - 0x30) << 6) | ((b - 0x30) << 3) | (d - 0x30));
          i += 4;
          continue;
        }
      }
      final mapped = _cQuoteEscapeByte[n];
      if (mapped != null) {
        buf.writeCharCode(mapped);
      } else {
        buf.writeCharCode(c);
        buf.writeCharCode(n);
      }
      i += 2;
      continue;
    }
    buf.writeCharCode(c);
    i++;
  }
  return buf.toString();
}

// Identifier tokenisation is now a single-pass char-code scan (see
// `_tokensOf` above). The legacy `_nonWord` / `_camelBoundary` regexes
// are gone — their Unicode lookbehind/lookahead profiled at 10+ seconds
// on large diffs.

/// Horizon multiplier for H_prox: pairs with `d â‰¥ Ïƒ Â· ratio` contribute
/// `exp(-ratio) â‰ˆ 1e-6` â€” below the noise floor after D^{-1/2} Laplacian
/// normalisation and Chebyshev basis truncation. Precomputed as `ln(1e6)`
/// since `math.log` isn't a const expression in Dart; tightening the
/// floor is a literal change.
const double _proxHorizonLnRatio = 13.815510557964274;

/// Maximum hunk-pair edges materialised per (file_a, file_b) cross-file
/// coupling pass. Above this, the loop samples a deterministic stride
/// of representative pairs that preserves the file pair's total mass
/// without paying for the |A|Â·|B| explosion. Picked to stay within an
/// order of magnitude of the per-node top-K fanout the symmetriser
/// keeps anyway, so larger values would do redundant work.
const int _kCrossFileFanoutCap = 32;

/// Weights for the hunk-file inherited-coupling formula in
/// [buildHunkFileEvidenceFromResiduals]. Each term represents a
/// distinct *channel* by which a file's evidence signal can transmit
/// to its hunks:
///
/// - [_hfBaseSupportWeight] — direct support×integrity; the default
///   coupling when no transport or residual signal is present.
/// - [_hfTransportSignalWeight] — pull through the co-change /
///   semantic-link transport graph; a file whose related files have
///   evidence should inherit some of it.
/// - [_hfResidualSignalWeight] — unexplained innovation / witness
///   residuals; a file flagged as architecturally surprising
///   propagates that surprise to its hunks.
///
/// The three weights sum to 1.45 — an intentional overcount,
/// clamped by the surrounding `math.max(baseSupport, ...)` and the
/// `[0, 1]` bound. The overcount means any single strong channel
/// can dominate, while two weaker channels can still combine to
/// beat a solo base. Compositional constants (hand-picked, not
/// derived); ablation-study range is ~±0.1 per weight.
const double _hfBaseSupportWeight = 0.60;
const double _hfTransportSignalWeight = 0.35;
const double _hfResidualSignalWeight = 0.50;

/// Single-pass char-scan tokenizer: walks the text exactly once,
/// extracting identifier runs and splitting them at camelCase
/// boundaries in the same loop. Avoids the `text.split(_nonWord)` +
/// per-word `raw.split(_camelBoundary)` regex chain, whose Unicode
/// lookbehind/lookahead was the dominant cost in `rankHunksByPhiAsync`
/// (measured at 5–25 seconds on real commits with many large hunks).
///
/// Semantics match the regex form for ASCII source code — the common
/// case. Non-ASCII runs (code units ≥ 0x80) are treated as identifier
/// continuation, which matches `\p{L}\p{N}` for typical unicode
/// letters and over-approximates only for exotic whitespace-category
/// letters (which don't appear in normal source text).
Set<String> _tokensOf(String text) {
  if (text.isEmpty) return const {};
  final tokens = <String>{};
  final n = text.length;
  var i = 0;
  while (i < n) {
    // Skip non-identifier chars.
    while (i < n && !_isIdentChar(text.codeUnitAt(i))) {
      i++;
    }
    if (i >= n) break;
    // Walk one identifier run, emitting at each camelCase boundary:
    // "prev is lower/digit AND current is upper" → split here.
    var pieceStart = i;
    var prev = text.codeUnitAt(i);
    i++;
    while (i < n) {
      final c = text.codeUnitAt(i);
      if (!_isIdentChar(c)) break;
      if (_isLowerOrDigit(prev) && _isUpper(c)) {
        if (i - pieceStart >= 3) {
          tokens.add(text.substring(pieceStart, i).toLowerCase());
        }
        pieceStart = i;
      }
      prev = c;
      i++;
    }
    if (i - pieceStart >= 3) {
      tokens.add(text.substring(pieceStart, i).toLowerCase());
    }
  }
  return tokens;
}

bool _isIdentChar(int c) =>
    (c >= 0x30 && c <= 0x39) || // 0-9
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x61 && c <= 0x7A) || // a-z
    c == 0x5F ||                // _
    c >= 0x80;                  // treat any non-ASCII as identifier

bool _isUpper(int c) => c >= 0x41 && c <= 0x5A;

bool _isLowerOrDigit(int c) =>
    (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39);

/// Returns the diff-local stop-set: tokens above the kneedle cutoff on
/// the descending per-hunk document-frequency curve. Empty on diffs
/// too small for the curve to have shape (< 5 hunks), or when the
/// distribution is flat or the top token doesn't stand out.
Set<String> _deriveStopTokens(List<Set<String>> perHunkTokens) {
  if (perHunkTokens.length < 5) return const {};
  final docFreq = <String, int>{};
  for (final ts in perHunkTokens) {
    for (final t in ts) {
      docFreq[t] = (docFreq[t] ?? 0) + 1;
    }
  }
  if (docFreq.length < 3) return const {};
  final sorted = docFreq.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final n = sorted.length;
  final maxV = sorted.first.value.toDouble();
  final minV = sorted.last.value.toDouble();
  final spread = maxV - minV;
  if (spread <= 0) return const {};
  // Kneedle â€” bend of the descending curve (0,1)â†’(1,0).
  var kneeIdx = 0;
  var bestDist = -1.0;
  for (var i = 0; i < n; i++) {
    final x = i / (n - 1);
    final y = (sorted[i].value - minV) / spread;
    final d = (y + x - 1).abs();
    if (d > bestDist) {
      bestDist = d;
      kneeIdx = i;
    }
  }
  // Knee at the head means no clear split between high-freq and tail.
  if (kneeIdx == 0) return const {};
  final stop = <String>{};
  for (var i = 0; i <= kneeIdx; i++) {
    stop.add(sorted[i].key);
  }
  return stop;
}

/// Only the +/- payload contributes to hunk identifier tokens â€” that's
/// the *change*, not the unchanged context.
Set<String> _hunkChangeTokens(DiffHunk hunk) {
  final buf = StringBuffer();
  for (final line in hunk.body.split('\n')) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      buf.write(line.substring(1));
      buf.write(' ');
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      buf.write(line.substring(1));
      buf.write(' ');
    }
  }
  return _tokensOf(buf.toString());
}

// Hunk-graph construction. Diffusion math lives in logos_core.dart â€”
// this file only owns the hunk-specific axis blend (H_sym / H_file /
// H_prox / H_vol) and the source-mass model.

/// Build the hunk graph.
/// [fileCoupling] is an optional map that gives, for each non-source file,
/// the file-Ï† score from LogosGit. When building cross-file hunk edges we
/// multiply by this to get hunk-level cross-file weight for free â€” the
/// factorisation trick.
CsrGraph _buildHunkGraph({
  required List<DiffHunk> hunks,
  required List<Set<String>> tokens,
  required Map<String, double> fileCouplingFromParent,
  required int topK,
  List<HunkKVector?>? engramKVectors,
}) {
  final n = hunks.length;
  if (n == 0) {
    return CsrGraph(
      n: 0,
      indptr: Int32List(1),
      indices: Int32List(0),
      values: Float64List(0),
    );
  }

  // Inverted token index â†’ candidate pair generator. We only score pairs
  // that share â‰¥1 token; this is O(Î£ bucket_sizeÂ²) which is small in
  // practice thanks to the stop-list and the min-length filter.
  final tokenBuckets = <String, List<int>>{};
  for (var i = 0; i < n; i++) {
    for (final tok in tokens[i]) {
      (tokenBuckets[tok] ??= <int>[]).add(i);
    }
  }

  // Precompute per-file statistics for H_prox (line-gap Ïƒ). Sort each
  // file's hunk-id list by newStart once here â€” downstream consumers
  // (fileSigma gap statistics, H_prox horizon break) both require
  // ordered line positions, and H_file / H_vol are order-independent
  // pair iterations so the sort has no side effect on them.
  final fileToHunks = <String, List<int>>{};
  for (var i = 0; i < n; i++) {
    (fileToHunks[hunks[i].filePath] ??= <int>[]).add(i);
  }
  for (final ids in fileToHunks.values) {
    if (ids.length > 1) {
      ids.sort((x, y) => hunks[x].newStart.compareTo(hunks[y].newStart));
    }
  }
  final fileSigma = <String, double>{};
  for (final entry in fileToHunks.entries) {
    final ids = entry.value;
    if (ids.length < 2) continue;
    final gaps = <int>[];
    for (var k = 1; k < ids.length; k++) {
      // ids is sorted by newStart, so b â‰¥ a and abs() is redundant.
      final g = hunks[ids[k]].newStart - hunks[ids[k - 1]].newStart;
      if (g > 0) gaps.add(g);
    }
    if (gaps.isEmpty) continue;
    gaps.sort();
    // Median gap as the natural within-file proximity scale.
    final median = gaps[gaps.length ~/ 2].toDouble();
    fileSigma[entry.key] = median > 0 ? median : 1.0;
  }

  // Axis weights â€” convex blend. Chosen by order-of-magnitude balance,
  // not tuned: identifier coupling is the strongest signal, parent-file
  // and proximity are structural priors, volume-balance is a soft
  // regulariser. A future iteration could self-derive these from the
  // per-diff variance of each axis, but uniform-ish blend is a fine start.
  const wSym = 0.55;
  const wFile = 0.25;
  const wProx = 0.15;
  const wVol = 0.05;

  // Accumulate candidate weights into a sparse symmetric map.
  final edges = <int, Map<int, double>>{};

  void addEdge(int a, int b, double w) {
    if (a == b || w <= 0 || !w.isFinite) return;
    final rowA = edges[a] ??= <int, double>{};
    rowA[b] = (rowA[b] ?? 0.0) + w;
    final rowB = edges[b] ??= <int, double>{};
    rowB[a] = (rowB[a] ?? 0.0) + w;
  }

  //
  // For each bucket of hunks sharing a token, add pair contributions
  // weighted by 1/bucket_size. Repeated across all shared tokens this
  // converges to the proper Jaccard numerator; the denominator is
  // |tokens[i] âˆª tokens[j]| â‰ˆ |tokens[i]| + |tokens[j]| - overlap.
  // We approximate by tallying numerator first, then normalising at
  // the end.
  // Flat single-map with a record key. The earlier nested
  // `Map<int, Map<int, int>>` allocated an inner map on every
  // first-seen `lo`, which fired thousands of small heap allocations
  // per diff inside the hottest token-bucket loop. Collapsing into
  // one map keyed by `(lo, hi)` is O(1) per upsert and zero
  // auxiliary allocations.
  // (Grimoire Circle XIV: the access pattern wants one flat table,
  // not a tree of tables.)
  final symNumerator = <(int, int), int>{};
  for (final bucket in tokenBuckets.values) {
    if (bucket.length < 2) continue;
    // No upper bucket cap: a token shared by many hunks lowers each
    // pair's Jaccard contribution naturally (denominator grows), and
    // D^{-1/2} normalisation absorbs the rest. Geometry handles it.
    for (var a = 0; a < bucket.length; a++) {
      final ia = bucket[a];
      for (var b = a + 1; b < bucket.length; b++) {
        final ib = bucket[b];
        final lo = ia < ib ? ia : ib;
        final hi = ia < ib ? ib : ia;
        final key = (lo, hi);
        symNumerator[key] = (symNumerator[key] ?? 0) + 1;
      }
    }
  }

  // Engram-augmented H_sym blend.
  //
  // When engram assets are loaded, each hunk has a K-vector âˆˆ â„‚^P that
  // encodes its semantic position in Alexandria's GloVe-seeded well
  // geometry. Cosine similarity between two hunk K-vectors âˆˆ [0,1]
  // captures "shared concept space" even when no identifier strings
  // overlap â€” a hunk using `dispatchEvent` and one using `emitSignal`
  // share zero Jaccard but ~0.7 K-cosine. That's the feature-cluster
  // signal Jaccard misses.
  //
  // **Blend is evidence-weighted, not magic-constant-weighted.** Each
  // signal contributes in proportion to `log1p(evidence)` â€” the same
  // nats-of-information metric the Born mixer uses elsewhere in the
  // engine. A hunk with many shared tokens leans Jaccard; a hunk with
  // many in-vocab GloVe hits leans engram. Neither axis gets an
  // arbitrary weight floor or ceiling â€” their evidence decides.
  //
  //   w_jac = log1p(|tokens_i| + |tokens_j|)   â€” larger bag â†’ better Jaccard
  //   w_eng = log1p(min(hits_i, hits_j))      â€” more hits â†’ tighter K-vector
  //   blended = (w_jacÂ·jaccard + w_engÂ·cos) / (w_jac + w_eng)
  //
  // Pairs with neither Jaccard overlap nor an engram connection drop
  // out entirely â€” preserving graph sparsity. Pairs with engram signal
  // but no Jaccard still enter the graph: we seed those via the
  // file-level H_file coupling below when both files have touched
  // hunks, and via an e-decay thresholded engram-only pass here when
  // they don't.
  //
  // The engram-only admission threshold is `1/e â‰ˆ 0.368` â€” the natural
  // exponential decay floor. Below 1/e the cosine has decayed past one
  // e-folding from perfect alignment; that's the classical "signal has
  // faded to noise" boundary, not a hand-picked decimal.
  final engramOnlyThreshold = math.exp(-1.0);

  // Pass 1: pairs with at least one shared token. Blend Jaccard with
  // an engram signal that itself fuses K-cosine (velocity channel)
  // and G-cosine (curvature channel). The engram signal per pair is
  // the geometric mean of the two cosines when both are positive —
  // a bonded pair must agree on BOTH where the concept points AND
  // how it bends. When either cosine has decayed past zero, the
  // geometric mean collapses to 0 and we fall through to Jaccard
  // alone for that pair. When G is near-degenerate (linear fallback)
  // for one side, we fall through to K alone rather than let a
  // broken curvature kill a legitimately-bonded pair.
  for (final entry in symNumerator.entries) {
    final i = entry.key.$1;
    final j = entry.key.$2;
    final overlap = entry.value;
    final iTokens = tokens[i].length;
    final jTokens = tokens[j].length;
    final denom = iTokens + jTokens - overlap;
    if (denom <= 0) continue;
    final jaccard = overlap / denom;
    double weight;
    if (engramKVectors != null) {
      final kvi = engramKVectors[i];
      final kvj = engramKVectors[j];
      final engramSignal = _engramSignal(kvi, kvj);
      if (engramSignal > 0 && kvi != null && kvj != null) {
        final jaccardEvidence =
            math.log(1.0 + (iTokens + jTokens).toDouble());
        final engramEvidence = math.log(1.0 +
            (kvi.vocabHits < kvj.vocabHits ? kvi.vocabHits : kvj.vocabHits)
                .toDouble());
        final totalEvidence = jaccardEvidence + engramEvidence;
        final blended = totalEvidence > 0
            ? (jaccardEvidence * jaccard + engramEvidence * engramSignal) /
                totalEvidence
            : jaccard;
        weight = wSym * blended;
      } else {
        weight = wSym * jaccard;
      }
    } else {
      weight = wSym * jaccard;
    }
    addEdge(i, j, weight);
  }

  // Pass 2: engram-only edges. Walk every pair that has K-vectors but
  // did NOT share any tokens, and admit those clearing the 1/e cosine
  // floor. This is O(NÂ²) on hunks that have K-vectors â€” we bound it
  // by the hunk count (already â‰¤ hundreds in practice) and skip
  // entirely when engram isn't loaded. The engram-only weight uses
  // pure engram evidence (no Jaccard term, by definition there's no
  // Jaccard overlap on these pairs), scaled by `w_eng / (w_eng + 1)`
  // â€” a self-normalising factor derivable from the evidence blend
  // with the Jaccard evidence held at its "zero overlap, single
  // witness" baseline of log(1+1) = ln(2).
  if (engramKVectors != null) {
    // Walks every pair (i, j) that has K-vectors and wasn't already
    // scored in pass 1. Cross-file pairs are INCLUDED here on purpose:
    // the H_file pass below uses file-level φ coupling, which is pair-
    // uniform within a file pair and does not capture hunk-level
    // K-vector similarity across files. A lone renamed helper in file A
    // that semantically clones a helper in file B has no Jaccard
    // overlap and weak file-level φ coupling, yet produces a strong
    // engram cosine — that's the cross-file semantic bridge this pass
    // exists to admit. The 1/e cosine gate keeps the edge count small.
    for (var i = 0; i < n; i++) {
      final kvi = engramKVectors[i];
      if (kvi == null) continue;
      for (var j = i + 1; j < n; j++) {
        final kvj = engramKVectors[j];
        if (kvj == null) continue;
        // Direct O(1) pair-presence check in the flat map — no inner
        // map to walk, no null-guard of a missing row.
        if (symNumerator.containsKey((i, j))) continue;
        // Engram-only path uses the same K+G geometric mean so the
        // token-free bridges only admit pairs that agree on both
        // velocity and curvature — a stricter gate than K alone,
        // and the 1/e floor filters noise the same way.
        final signal = _engramSignal(kvi, kvj);
        if (signal < engramOnlyThreshold) continue;
        final engEvidence = math.log(1.0 +
            (kvi.vocabHits < kvj.vocabHits ? kvi.vocabHits : kvj.vocabHits)
                .toDouble());
        // Self-normalised engram-only weight. With Jaccard evidence =
        // ln(2) (the zero-overlap baseline), the blend collapses to:
        //   weight = signal · engEvidence / (engEvidence + ln2)
        // which tends to `signal` as evidence grows and to `0` when
        // evidence is tiny — the "confidence-gated signal" shape the
        // Born mixer uses on its axes.
        final selfNorm = engEvidence / (engEvidence + math.ln2);
        addEdge(i, j, wSym * signal * selfNorm);
      }
    }
  }

  for (final group in fileToHunks.values) {
    for (var a = 0; a < group.length; a++) {
      for (var b = a + 1; b < group.length; b++) {
        addEdge(group[a], group[b], wFile * 1.0);
      }
    }
  }
  // Cross-file hunk coupling via LogosGit file-Ï†. We treat the file
  // with the higher Ï† contribution as the "host" and multiply the pair
  // weight by the lesser of their Ï† values (conservative).
  //
  // Fanout cap: the original |A|Â·|B| double loop allocated up to
  // ~|A|Â·|B| edge entries per file pair, then the top-K sparsifier
  // discarded the bulk. On a 20-file Ã— 10-hunk diff that was ~200k
  // wasted addEdge calls. We now cap the per-pair fanout at
  // [_kCrossFileFanoutCap]: once the product exceeds the cap, sample
  // a deterministic subset of representative pairs that preserves the
  // total mass (each kept edge carries the full weight share that the
  // dropped edges would have summed to). The 1/sqrt normaliser is
  // unchanged, so total injected mass per file pair still equals
  // ~coupling regardless of the fanout path taken.
  if (fileCouplingFromParent.isNotEmpty) {
    // Pre-resolve the hashmap lookups ONCE. The nested loop below was
    // doing 3·nF² Map<String, double> probes (phiA, phiB, fileToHunks
    // both sides) where nF is the diff's file count. Parallel
    // Float64List + List-of-List lookups collapse that to nF hash
    // lookups plus nF² typed-array reads.
    // (Grimoire Circle XIV: replace cache-hostile per-pair pointer
    // chasing with aligned column access.)
    final filePaths = fileToHunks.keys.toList(growable: false);
    final nF = filePaths.length;
    final phis = Float64List(nF);
    final hunkLists = List<List<int>>.generate(
        nF, (i) => fileToHunks[filePaths[i]]!,
        growable: false);
    for (var i = 0; i < nF; i++) {
      phis[i] = fileCouplingFromParent[filePaths[i]] ?? 0.0;
    }
    for (var a = 0; a < nF; a++) {
      final phiA = phis[a];
      if (phiA <= 0) continue;
      final listA = hunkLists[a];
      for (var b = a + 1; b < nF; b++) {
        final phiB = phis[b];
        if (phiB <= 0) continue;
        final coupling = phiA < phiB ? phiA : phiB;
        if (coupling <= 0) continue;
        final listB = hunkLists[b];
        final fanout = listA.length * listB.length;
        final norm = 1.0 / math.sqrt(fanout);
        if (fanout <= _kCrossFileFanoutCap) {
          for (final ia in listA) {
            for (final ib in listB) {
              addEdge(ia, ib, wFile * coupling * norm);
            }
          }
        } else {
          // Sample _kCrossFileFanoutCap pairs deterministically along
          // a stride that visits both lists' index spaces uniformly.
          // Each kept edge carries `(fanout / cap)`× the per-pair
          // weight so the summed mass over the file pair matches the
          // full-fanout case.
          final massScale = fanout / _kCrossFileFanoutCap;
          final w = wFile * coupling * norm * massScale;
          for (var k = 0; k < _kCrossFileFanoutCap; k++) {
            final ia = listA[(k * 31) % listA.length];
            final ib = listB[(k * 17) % listB.length];
            addEdge(ia, ib, w);
          }
        }
      }
    }
  }

  // Edges land inside the Ïƒ-scaled horizon; beyond it `exp(-d/Ïƒ)` is
  // below [_proxFloor] â€” numerically indistinguishable from zero after
  // D^{-1/2} normalisation â€” so we break the inner loop. Because `ids`
  // is sorted by newStart (monotone non-decreasing), the first `b` that
  // exceeds the horizon proves all later `b` do too. The horizon is
  // derived from the floor (not a magic constant): `exp(-d/Ïƒ) â‰¥ Îµ âŸº
  // d â‰¤ ÏƒÂ·ln(1/Îµ)`. On a file with 50 scattered hunks this collapses
  // exp() calls from 1225 to roughly `hunks Ã— horizon / median-gap`.
  for (final entry in fileToHunks.entries) {
    final ids = entry.value;
    if (ids.length < 2) continue;
    final sigma = fileSigma[entry.key] ?? 1.0;
    final horizon = sigma * _proxHorizonLnRatio;
    for (var a = 0; a < ids.length; a++) {
      final la = hunks[ids[a]].newStart;
      for (var b = a + 1; b < ids.length; b++) {
        final d = hunks[ids[b]].newStart - la; // sorted â‡’ â‰¥ 0
        if (d >= horizon) break;
        addEdge(ids[a], ids[b], wProx * math.exp(-d / sigma));
      }
    }
  }

  // balance_i = (adds - dels) / (adds + dels + 1) âˆˆ [-1, 1]
  // similarity_ij = 1 - |balance_i - balance_j| / 2 âˆˆ [0, 1]
  // Only contribute within-file (balance across unrelated files is
  // meaningless noise). This is a tiny signal; it breaks ties between
  // structurally-similar hunks by preferring same-character edits.
  for (final group in fileToHunks.values) {
    if (group.length < 2) continue;
    for (var a = 0; a < group.length; a++) {
      final ha = hunks[group[a]];
      final balA =
          (ha.additions - ha.deletions) / (ha.additions + ha.deletions + 1);
      for (var b = a + 1; b < group.length; b++) {
        final hb = hunks[group[b]];
        final balB =
            (hb.additions - hb.deletions) / (hb.additions + hb.deletions + 1);
        final sim = 1.0 - ((balA - balB).abs() / 2.0);
        addEdge(group[a], group[b], wVol * sim);
      }
    }
  }

  // Sparsify + build: top-K per row, symmetric union, then degree +
  // D^{-1/2} fusion. Both passes live in `graph/` so the file, hunk,
  // and chunk engines share the same sparsification policy and
  // normalisation — change it once, every engine picks it up.
  return buildSymmetricCsrGraph(
    n: n,
    edges: topKSymmetriseEdges(edges: edges, topK: topK),
  );
}

/// Fuse K-cosine (velocity channel) and G-cosine (curvature channel)
/// into a single per-pair engram similarity signal.
///
/// Geometric mean — a pair only scores high when it agrees on BOTH
/// channels. A shared concept-heading with opposite bending shapes
/// is legitimately dissimilar; we shouldn't bond it via the K-axis
/// alone. Arithmetic mean would paper over that disagreement; the
/// geometric mean respects it.
///
/// Falls back to K alone when the G channel is degenerate (either
/// side has zero-norm G — linear AR(2) fallback, a short trajectory
/// that couldn't fit curvature). This protects legitimate K matches
/// from being killed by a collapsed curvature channel.
double _engramSignal(HunkKVector? a, HunkKVector? b) {
  if (a == null || b == null) return 0.0;
  final k = EngramHunkEncoder.cosine(a, b);
  if (k <= 0) return 0.0;
  final g = EngramHunkEncoder.curvatureCosine(a, b);
  if (g <= 0) return k; // linear-fallback G → use K alone
  return math.sqrt(k * g);
}

// Chebyshev/Bessel math + heat-kernel diffusion live in logos_core.dart
// â€” see [chebyshevBasis], [recombineHeatPhi], and [kChebyshevSmallGraph]
// for the polynomial-order policy this engine shares with logos_chunks.

// Public API â€” rank hunks by semantic centrality Ï† in this diff.

class HunkDiffusionResult {
  HunkDiffusionResult({
    required this.rankings,
    required this.fellBackToChurn,
    this.graph,
    this.nodeOrder,
  });

  /// Hunks in descending Ï† order. First = most central.
  final List<HunkRanking> rankings;

  /// True when the graph was degenerate (empty, single-hunk, or zero mass)
  /// and we fell back to ranking by churn. Callers may log this but
  /// behaviour is otherwise identical from their perspective.
  final bool fellBackToChurn;

  /// The hunk graph this diffusion ran on. Available (non-null) in the
  /// normal diffusion path; null on the churn-fallback and empty-input
  /// paths. Use [spectralBasis] to get a lazy Lanczos eigendecomposition
  /// for the same observables (heat trace, Fiedler, fingerprint, etc.)
  /// that [SpectralBasis] exposes on the file-level graph.
  final CsrGraph? graph;

  /// Graph node indices in φ-descending order. Entry [r] is the graph
  /// node index for the hunk at rank r.
  final List<int>? nodeOrder;

  SpectralBasis? _cachedSpectralBasis;
  HunkInteractionDecomposition? _cachedInteraction;

  /// Lazy spectral basis over [graph]. Cached for the lifetime of this
  /// result — safe because hunk graphs are immutable once built.
  /// Returns null when [graph] is null or when the graph is too small
  /// to amortise the Lanczos build.
  SpectralBasis? spectralBasis({int k = kDefaultSpectralBasisK}) {
    final g = graph;
    if (g == null || g.n < kDefaultSpectralMinNodes) return null;
    if (_cachedSpectralBasis != null) return _cachedSpectralBasis;
    final clamped = math.min(k, g.n);
    _cachedSpectralBasis = SpectralBasis.fromGraph(g, clamped);
    return _cachedSpectralBasis;
  }

  /// Lazy interaction decomposition on the Boolean lattice 2^[H].
  /// Decomposes hunk coupling into irreducible multi-body interactions
  /// via Walsh-Hadamard on the subgraph heat trace. Cached.
  HunkInteractionDecomposition? interactionDecomposition({double t = 1.0}) {
    final g = graph;
    if (g == null || g.n < 2) return null;
    if (_cachedInteraction != null) return _cachedInteraction;
    final order = nodeOrder;
    if (order == null || order.isEmpty) return null;
    // Derive the lattice depth from the hunk graph's spectral gap.
    // Tight gap → strong multi-body coupling → deeper decomposition.
    // Wide gap → weak coupling → higher orders are noise, stop early.
    // Formula: H = clamp(ceil(4 / gap), 4, 16). The constant 4 in
    // the numerator sets the scale: at gap=1 (maximally connected)
    // H=4 (minimal depth — everything is already coupled, no hidden
    // multi-body structure). At gap=0.25 (moderate coupling) H=16
    // (full depth — there's real structure to find). The spectral gap
    // IS the noise floor; dividing by it gives the number of resolvable
    // modes, which is the right depth for the Walsh decomposition.
    final basis = spectralBasis();
    final gap = basis?.spectralGap ?? 1.0;
    final derivedMaxH = gap > 0.01
        ? (4.0 / gap).ceil().clamp(4, _kHunkLatticeMaxH)
        : _kHunkLatticeMaxH;
    final effectiveH = math.min(order.length, derivedMaxH);
    final nodes = effectiveH < order.length
        ? order.sublist(0, effectiveH)
        : order;
    _cachedInteraction = decomposeHunkInteractions(
      graph: g,
      nodeSubset: nodes,
      t: t,
    );
    return _cachedInteraction;
  }

  /// Fraction of Walsh energy at interaction order ≥ 2 — how much of the
  /// hunk coupling is genuinely multi-body (not explained by individual
  /// hunk importance). High values mean hunks must be reviewed together.
  double get entanglementRatio =>
      interactionDecomposition()?.entanglementRatio ?? 0.0;
}

class HunkFileEvidence {
  final Map<String, double> coupling;
  final Map<String, LogosResidualView> residualByPath;
  final Map<String, List<String>> witnessLabelsByPath;
  final Map<String, List<LogosEvidenceWitness>> evidenceWitnessesByPath;

  const HunkFileEvidence({
    required this.coupling,
    required this.residualByPath,
    required this.witnessLabelsByPath,
    required this.evidenceWitnessesByPath,
  });
}

HunkFileEvidence buildHunkFileEvidenceFromResiduals(
  Map<String, LogosResidualView> residualByPath, {
  Iterable<String>? touchedPaths,
}) {
  final touched = touchedPaths?.toSet();
  final coupling = <String, double>{};
  final filteredResiduals = <String, LogosResidualView>{};
  final witnessLabelsByPath = <String, List<String>>{};
  final evidenceWitnessesByPath = <String, List<LogosEvidenceWitness>>{};

  for (final entry in residualByPath.entries) {
    final path = entry.key;
    if (touched != null && !touched.contains(path)) continue;
    final signal = entry.value;
    filteredResiduals[path] = signal;
    final baseSupport =
        (signal.support * signal.integrity).clamp(0.0, 1.0).toDouble();
    final transportSignal = signal.transportSignal;
    final residualSignal = signal.residualSignal;
    final inherited = math.max(
      baseSupport,
      (_hfBaseSupportWeight * baseSupport +
              _hfTransportSignalWeight * transportSignal +
              _hfResidualSignalWeight * residualSignal)
          .clamp(0.0, 1.0)
          .toDouble(),
    );
    if (inherited > 0) coupling[path] = inherited;
    if (signal.witnesses.isNotEmpty) {
      evidenceWitnessesByPath[path] =
          signal.witnesses.take(3).toList(growable: false);
    }
    final labels = <String>[
      for (final witness in signal.witnesses.take(3))
        formatLogosEvidenceWitness(
          witness,
          includeNote: true,
          includeSource: true,
        ),
      if (signal.transportedSupport > 0.05)
        'transported=${signal.transportedSupport.toStringAsFixed(2)}',
      if (signal.witnessResidual > 0.05)
        'missing-witness=${signal.witnessResidual.toStringAsFixed(2)}',
      if (signal.innovationResidual > 0.05)
        'innovation=${signal.innovationResidual.toStringAsFixed(2)}',
    ];
    if (labels.isNotEmpty) {
      witnessLabelsByPath[path] = labels;
    }
  }

  return HunkFileEvidence(
    coupling: coupling,
    residualByPath: filteredResiduals,
    witnessLabelsByPath: witnessLabelsByPath,
    evidenceWitnessesByPath: evidenceWitnessesByPath,
  );
}

/// Rank [hunks] by heat-kernel centrality.
/// If a [logosEngine] is provided we use it to compute the cross-file
/// coupling prior for the H_file axis â€” the factorisation trick. If it's
/// null (cold repo, no engine yet), within-file coupling still works and
/// the rest of the axes carry the load; cross-file edges simply don't
/// get the file-Ï† boost.
HunkDiffusionResult rankHunksByPhi({
  required List<DiffHunk> hunks,
  LogosGit? logosEngine,
  EngramAssets? engramAssets,
  HunkFileEvidence? fileEvidence,
  Map<String, double> flowGaps = const {},
}) {
  final resolvedFileEvidence =
      fileEvidence ?? _resolveFileCoupling(hunks, logosEngine);
  return _rankHunksByPhiCore(
    hunks: hunks,
    fileCoupling: resolvedFileEvidence.coupling,
    fileResidualByPath: resolvedFileEvidence.residualByPath,
    fileWitnessesByPath: resolvedFileEvidence.witnessLabelsByPath,
    fileEvidenceWitnessesByPath: resolvedFileEvidence.evidenceWitnessesByPath,
    engramAssets: engramAssets,
    flowGaps: flowGaps,
  );
}

/// Async variant â€” runs the graph build + 3-temperature recombination
/// on a background isolate so a diff with hundreds of hunks doesn't
/// hitch the UI on every diff-panel switch. Engine touches still
/// happen on the calling thread (cheap diffuseWeighted), then the
/// pure-data core hops to an isolate.
/// [engramAssets], when provided, enables the engram-backed H_sym blend
/// and annotates rankings with their nearest Alexandria well. The assets
/// are raw byte blobs so they cross the isolate boundary cheaply; the
/// encoder is constructed inside the isolate once.
Future<HunkDiffusionResult> rankHunksByPhiAsync({
  required List<DiffHunk> hunks,
  LogosGit? logosEngine,
  EngramAssets? engramAssets,
  HunkFileEvidence? fileEvidence,
  Map<String, double> flowGaps = const {},
}) async {
  final resolvedFileEvidence =
      fileEvidence ?? _resolveFileCoupling(hunks, logosEngine);
  if (hunks.length <= 1) {
    return _rankHunksByPhiCore(
      hunks: hunks,
      fileCoupling: resolvedFileEvidence.coupling,
      fileResidualByPath: resolvedFileEvidence.residualByPath,
      fileWitnessesByPath: resolvedFileEvidence.witnessLabelsByPath,
      fileEvidenceWitnessesByPath: resolvedFileEvidence.evidenceWitnessesByPath,
      engramAssets: engramAssets,
      flowGaps: flowGaps,
    );
  }
  return Isolate.run<HunkDiffusionResult>(
    () => _rankHunksByPhiCore(
      hunks: hunks,
      fileCoupling: resolvedFileEvidence.coupling,
      fileResidualByPath: resolvedFileEvidence.residualByPath,
      fileWitnessesByPath: resolvedFileEvidence.witnessLabelsByPath,
      fileEvidenceWitnessesByPath: resolvedFileEvidence.evidenceWitnessesByPath,
      engramAssets: engramAssets,
      flowGaps: flowGaps,
    ),
    debugName: 'rankHunksByPhi',
  );
}

HunkFileEvidence _resolveFileCoupling(List<DiffHunk> hunks, LogosGit? engine) {
  final coupling = <String, double>{};
  final residualByPath = <String, LogosResidualView>{};
  final witnessLabelsByPath = <String, List<String>>{};
  final evidenceWitnessesByPath = <String, List<LogosEvidenceWitness>>{};
  if (engine == null) {
    return HunkFileEvidence(
      coupling: coupling,
      residualByPath: residualByPath,
      witnessLabelsByPath: witnessLabelsByPath,
      evidenceWitnessesByPath: evidenceWitnessesByPath,
    );
  }
  final touchedFiles = <String>{for (final h in hunks) h.filePath};
  if (touchedFiles.isEmpty) {
    return HunkFileEvidence(
      coupling: coupling,
      residualByPath: residualByPath,
      witnessLabelsByPath: witnessLabelsByPath,
      evidenceWitnessesByPath: evidenceWitnessesByPath,
    );
  }
  try {
    final weights = <String, double>{for (final p in touchedFiles) p: 1.0};
    final evidence = engine.gatherEvidence(
      focusWeights: weights,
      excludePaths: const {},
      includeSpectrum: false,
      // Per-path witness + sidecar construction profiled at ~150ms per
      // "detailed" path and dominated rank at 5-6 seconds on diffs
      // touching 50-100 files (detailBudget=24 → up to 36 detailed
      // paths = 5+ seconds). Dropping to detailBudget=4 caps detailed
      // paths at ~6 and keeps the downstream `DiffLogosHunkSignal.
      // witnessLabels` surface populated for the top focus/ranked
      // paths — which is what the prompt actually cites.
      detailBudget: 4,
      includeSupportAttribution: false,
      includeSummaryDiagnostics: false,
    );
    if (evidence != null) {
      return buildHunkFileEvidenceFromResiduals(
        evidence.residualByPath,
        touchedPaths: touchedFiles,
      );
    } else {
      final scores = engine.diffuseWeighted(weights);
      for (final s in scores) {
        if (touchedFiles.contains(s.path) && s.phi > 0) {
          coupling[s.path] = s.phi;
        }
      }
    }
  } catch (_) {
    // Graceful: engine errors never block the diff packer.
  }
  return HunkFileEvidence(
    coupling: coupling,
    residualByPath: residualByPath,
    witnessLabelsByPath: witnessLabelsByPath,
    evidenceWitnessesByPath: evidenceWitnessesByPath,
  );
}

HunkDiffusionResult _rankHunksByPhiCore({
  required List<DiffHunk> hunks,
  required Map<String, double> fileCoupling,
  required Map<String, LogosResidualView> fileResidualByPath,
  required Map<String, List<String>> fileWitnessesByPath,
  required Map<String, List<LogosEvidenceWitness>> fileEvidenceWitnessesByPath,
  EngramAssets? engramAssets,
  Map<String, double> flowGaps = const {},
}) {
  final n = hunks.length;
  if (n == 0) {
    return HunkDiffusionResult(rankings: const [], fellBackToChurn: false);
  }
  if (n == 1) {
    return HunkDiffusionResult(
      rankings: [
        HunkRanking(
          hunk: hunks[0],
          phi: 1.0,
          rank: 0,
          transportPull:
              fileResidualByPath[hunks[0].filePath]?.transportPull ?? 0.0,
          transportedSupport:
              fileResidualByPath[hunks[0].filePath]?.transportedSupport ?? 0.0,
          innovationResidual:
              fileResidualByPath[hunks[0].filePath]?.innovationResidual ?? 0.0,
          witnessResidual:
              fileResidualByPath[hunks[0].filePath]?.witnessResidual ?? 0.0,
          fileEvidenceWitnesses:
              fileEvidenceWitnessesByPath[hunks[0].filePath] ?? const [],
          fileWitnesses: fileWitnessesByPath[hunks[0].filePath] ?? const [],
        ),
      ],
      fellBackToChurn: false,
    );
  }

  final rawTokens =
      List<Set<String>>.generate(n, (i) => _hunkChangeTokens(hunks[i]));
  final stopSet = _deriveStopTokens(rawTokens);
  final tokens = stopSet.isEmpty
      ? rawTokens
      : [for (final ts in rawTokens) ts.difference(stopSet)];

  // Optional engram H_sym augmentation. Build the encoder from the
  // already-transferred byte blobs (cheap inside this isolate) and
  // encode every hunk to a K-vector. Returns a list aligned with
  // `hunks` â€” entries stay null for hunks that couldn't be encoded
  // (too few in-vocab sub-tokens to fit AR(2)); H_sym falls back to
  // pure Jaccard for those.
  List<HunkKVector?>? engramKVectors;
  final engramEncoder = engramAssets?.buildEncoder();
  if (engramEncoder != null) {
    engramKVectors = [
      for (var i = 0; i < n; i++) engramEncoder.encode(tokens[i]),
    ];
  }

  // Top-K per node: sqrt(n) is the classical "enough-neighbours" heuristic
  // that keeps the graph sparse while preserving global connectivity.
  final topK = math.max(4, math.sqrt(n).ceil());

  final graph = _buildHunkGraph(
    hunks: hunks,
    tokens: tokens,
    fileCouplingFromParent: fileCoupling,
    topK: topK,
    engramKVectors: engramKVectors,
  );

  // Source mass Ï = log(1+bytes). Normalised to unit mass inside the
  // basis builder (we normalise here too for consistency).
  final rho = Float64List(n);
  var totalMass = 0.0;
  for (var i = 0; i < n; i++) {
    var m = math.log(1.0 + hunks[i].bytes);
    if (m > 0 && flowGaps.isNotEmpty) {
      final gap = flowGaps[hunks[i].filePath];
      if (gap != null && gap > 0) {
        m *= 1.0 + filamentSat(gap);
      }
    }
    rho[i] = m > 0 ? m : 0.0;
    totalMass += rho[i];
  }
  if (totalMass <= 0 || graph.n == 0) {
    // Degenerate â€” no mass or no nodes. Fall back to churn order.
    final fallback = [...hunks]..sort((a, b) => b.churn.compareTo(a.churn));
    return HunkDiffusionResult(
      rankings: [
        for (var i = 0; i < fallback.length; i++)
          HunkRanking(
            hunk: fallback[i],
            phi: 0.0,
            rank: i,
            transportPull:
                fileResidualByPath[fallback[i].filePath]?.transportPull ?? 0.0,
            transportedSupport:
                fileResidualByPath[fallback[i].filePath]?.transportedSupport ??
                    0.0,
            innovationResidual:
                fileResidualByPath[fallback[i].filePath]?.innovationResidual ??
                    0.0,
            witnessResidual:
                fileResidualByPath[fallback[i].filePath]?.witnessResidual ??
                    0.0,
            fileEvidenceWitnesses:
                fileEvidenceWitnessesByPath[fallback[i].filePath] ?? const [],
            fileWitnesses:
                fileWitnessesByPath[fallback[i].filePath] ?? const [],
          ),
      ],
      fellBackToChurn: true,
    );
  }
  for (var i = 0; i < n; i++) {
    rho[i] /= totalMass;
  }

  // Three-temperature geometric-mean blend — canonical multi-scale
  // ranker shared with `logos_chunks.dart`. See [tripleTemperatureBlend].
  //
  // On graphs with enough nodes to have meaningful heat-capacity
  // structure (n ≥ 32), derive the three temperatures from the graph's
  // own spectrum via `naturalScales`. On small graphs, fall through to
  // the default log-spaced triplet — their heat-capacity curves are
  // too noisy for peak detection to help.
  List<double>? derivedTemps;
  if (graph.n >= 32) {
    final basis =
        SpectralBasis.fromGraph(graph, math.min(16, graph.n));
    derivedTemps = tripleBlendTemperaturesFromPeaks(basis.naturalScales());
  }
  final blended = tripleTemperatureBlend(
    graph: graph,
    rho: rho,
    K: kChebyshevSmallGraph,
    temperatures: derivedTemps,
  );

  final indexed = List<int>.generate(n, (i) => i);
  indexed.sort((a, b) => blended[b].compareTo(blended[a]));

  final rankings = <HunkRanking>[];
  for (var r = 0; r < indexed.length; r++) {
    final id = indexed[r];
    final kv = engramKVectors?[id];
    rankings.add(HunkRanking(
      hunk: hunks[id],
      phi: blended[id],
      rank: r,
      wellName: kv?.well?.name,
      wellDistance: kv?.well?.rawDistance,
      transportPull:
          fileResidualByPath[hunks[id].filePath]?.transportPull ?? 0.0,
      transportedSupport:
          fileResidualByPath[hunks[id].filePath]?.transportedSupport ?? 0.0,
      innovationResidual:
          fileResidualByPath[hunks[id].filePath]?.innovationResidual ?? 0.0,
      witnessResidual:
          fileResidualByPath[hunks[id].filePath]?.witnessResidual ?? 0.0,
      fileEvidenceWitnesses:
          fileEvidenceWitnessesByPath[hunks[id].filePath] ?? const [],
      fileWitnesses: fileWitnessesByPath[hunks[id].filePath] ?? const [],
      spectralGap: flowGaps[hunks[id].filePath] ?? 0.0,
    ));
  }
  return HunkDiffusionResult(
    rankings: rankings,
    fellBackToChurn: false,
    graph: graph,
    nodeOrder: indexed,
  );
}

// Prompt packing â€” emit full hunk bodies greedily under a byte budget.

class HunkPackResult {
  HunkPackResult({
    required this.body,
    required this.admitted,
    required this.skipped,
  });
  final String body;
  final List<DiffHunk> admitted;
  final List<DiffHunk> skipped;
}

/// Pack hunks into a prompt-safe body in Ï†-desc order. Emits full hunk
/// bodies; hunks that don't fit the remaining budget are skipped rather
/// than truncated (a partial hunk is worse than no hunk â€” it breaks
/// git-apply and confuses the model).
/// The output is wrapped with a `<logos_packed_diff>` tag carrying
/// honest metadata: how many hunks admitted vs skipped, and the skipped
/// hunk paths (so the AI knows the model saw a filtered view, not the
/// full diff).
HunkPackResult packHunksUnderBudget({
  required List<HunkRanking> rankings,
  required int budgetChars,
}) {
  if (budgetChars <= 0 || rankings.isEmpty) {
    return HunkPackResult(body: '', admitted: const [], skipped: const []);
  }

  final admitted = <DiffHunk>[];
  final skipped = <DiffHunk>[];
  // Cache ranking metadata per-hunk so we can annotate the emitted
  // diff with Ï† + well labels without re-walking `rankings`.
  final byHunk = <DiffHunk, HunkRanking>{
    for (final r in rankings) r.hunk: r,
  };
  // Any engram-derived labels? If not we skip the metadata annotation
  // overhead entirely (keeps behaviour identical to the pre-engram
  // builds when assets aren't loaded).
  final anyWells = rankings.any((r) => r.wellName != null);
  // Budget cost of an in-diff annotation line, in characters. Grows
  // with each emitted hunk â€” approximately `<!-- engram well=NAME
  // phi=0.NN -->\n` which is ~40-50 chars per hunk.
  int hunkAnnotationCost(HunkRanking r) {
    if (r.wellName == null) return 0;
    return '<!-- engram well=${r.wellName} phi=${r.phi.toStringAsFixed(3)} -->\n'
        .length;
  }

  // Group admitted hunks by parent file so the emitted body reads like a
  // normal diff: one header per file, its admitted hunks in order.
  final perFile = <String, List<DiffHunk>>{};

  // Header overhead per file: `diff --git a/<p> b/<p>\n--- a/<p>\n+++ b/<p>\n`
  int headerCost(String p) =>
      'diff --git a/$p b/$p\n--- a/$p\n+++ b/$p\n'.length;
  // Overhead for the wrapping tag and metadata line.
  const wrapOverhead = 200;
  var remaining = budgetChars - wrapOverhead;

  for (final r in rankings) {
    final h = r.hunk;
    final needsHeader = !perFile.containsKey(h.filePath);
    final cost = h.bytes +
        (needsHeader ? headerCost(h.filePath) : 0) +
        (anyWells ? hunkAnnotationCost(r) : 0);
    if (cost > remaining) {
      skipped.add(h);
      continue;
    }
    remaining -= cost;
    admitted.add(h);
    (perFile[h.filePath] ??= <DiffHunk>[]).add(h);
  }

  if (admitted.isEmpty) {
    return HunkPackResult(body: '', admitted: const [], skipped: skipped);
  }

  // Emit in file-then-hunk-index order (natural diff order) within the
  // admitted set. Ï† ranking governs ADMISSION; emission order restores
  // the normal diff reading shape so the model doesn't have to re-sort.
  final fileOrder = perFile.keys.toList()..sort();
  final buf = StringBuffer();
  buf.writeln(
      '<logos_packed_diff admitted="${admitted.length}" skipped="${skipped.length}">');
  for (final fp in fileOrder) {
    final group = perFile[fp]!
      ..sort((a, b) => a.hunkIndex.compareTo(b.hunkIndex));
    HunkRanking? fileRanking;
    for (final h in group) {
      final candidate = byHunk[h];
      if (candidate == null) continue;
      if (fileRanking == null || candidate.phi > fileRanking.phi) {
        fileRanking = candidate;
      }
    }
    buf.writeln('diff --git a/$fp b/$fp');
    buf.writeln('--- a/$fp');
    buf.writeln('+++ b/$fp');
    if (fileRanking != null && fileRanking.fileEvidenceWitnesses.isNotEmpty) {
      final evidenceLabels = [
        for (final witness in fileRanking.fileEvidenceWitnesses.take(3))
          formatLogosEvidenceWitness(
            witness,
            includeNote: true,
            includeSource: true,
          ),
      ];
      if (evidenceLabels.isNotEmpty) {
        buf.writeln(
          '<!-- file-evidence-witnesses ${evidenceLabels.join(" | ")} -->',
        );
      }
    }
    if (fileRanking != null && fileRanking.fileWitnesses.isNotEmpty) {
      buf.writeln(
          '<!-- file-witnesses ${fileRanking.fileWitnesses.join(" | ")} -->');
    }
    for (final h in group) {
      final ranking = byHunk[h];
      // Annotate with the nearest Alexandria well and Ï† â€” a feature-
      // cluster hint for the LLM. Wrapped in an HTML-style comment so
      // most diff renderers just show it inline; `git apply` ignores
      // lines between hunks, so the output stays applicable when
      // emitted for that purpose.
      if (ranking != null && ranking.wellName != null) {
        final gapStr = ranking.spectralGap > 0
            ? ' gap=${ranking.spectralGap.toStringAsFixed(2)}'
            : '';
        buf.writeln(
            '<!-- engram well=${ranking.wellName} phi=${ranking.phi.toStringAsFixed(3)}$gapStr -->');
      }
      buf.write(h.body);
    }
  }
  if (skipped.isNotEmpty) {
    buf.writeln('<overflow skipped=${skipped.length}>');
    // List skipped paths (deduped) so the AI knows what it *didn't* see.
    final skippedPaths = <String>{for (final h in skipped) h.filePath};
    for (final p in skippedPaths) {
      buf.writeln('  $p');
    }
    buf.writeln('</overflow>');
  }
  buf.writeln('</logos_packed_diff>');
  return HunkPackResult(
    body: buf.toString(),
    admitted: admitted,
    skipped: skipped,
  );
}

// ── Hunk interaction decomposition via 2^[H] Möbius ──────────────
//
// For a commit with H hunks, the Boolean lattice 2^[H] indexes every
// subset of hunks. The subgraph heat trace f(S) = tr(exp(-t·L_S))
// measures each subset's thermal cohesion. Its Walsh-Hadamard transform
// decomposes hunk interactions into irreducible multi-body terms:
//
//   Order 0: baseline thermal capacity
//   Order 1: per-hunk marginal contribution
//   Order 2: pairwise entanglement
//   Order 3+: genuine multi-body coupling (bridge hunks, triadic
//             interference, architectural bottlenecks)
//
// The heat trace is genuinely nonlinear in the vertex set — removing a
// bridge hunk disconnects the subgraph and collapses the trace, creating
// higher-order Walsh coefficients that pairwise weights alone cannot.
//
// Two computational paths:
//   H ≤ 12 (spectral): enumerate all 2^H subsets, Jacobi-eigensolve
//     each subgraph Laplacian, compute heat traces, then WHT. O(2^H·H³).
//   H > 12 (quadratic): closed-form Walsh coefficients from pairwise
//     edge weights. Orders 0-2 only; order 3+ structurally zero.
//   H > 16: caller truncates to top-16 by φ.

const _kHunkLatticeFullH = 12;
const _kHunkLatticeMaxH = 16;
const _kInteractionDominantLimit = 32;

class HunkInteractionDecomposition {
  const HunkInteractionDecomposition({
    required this.h,
    required this.walshSpectrum,
    required this.orderSpectrum,
    required this.entanglementRatio,
    required this.dominantModes,
    required this.perHunkCoefficient,
    required this.isSpectral,
  });

  /// Number of hunks in the decomposition.
  final int h;

  /// Walsh spectrum f̂(S) for all S ∈ 2^[H]. Length = 2^h.
  final Float64List walshSpectrum;

  /// Energy per Walsh order 0..h. Entry [k] = Σ_{|S|=k} f̂(S)².
  final Float64List orderSpectrum;

  /// Fraction of Walsh energy at order ≥ 2.
  final double entanglementRatio;

  /// Dominant modes sorted by |coefficient|. At most 32.
  final List<({int mask, int order, double coefficient})> dominantModes;

  /// Walsh coefficient of {i} for each hunk — marginal importance.
  final Float64List perHunkCoefficient;

  /// True when the full spectral (heat trace) decomposition was used.
  final bool isSpectral;
}

/// Look up raw edge weight w(i,j) in a CSR graph. Returns 0 if no edge.
double _csrRawWeight(CsrGraph g, int i, int j) {
  final start = g.indptr[i];
  final end = g.indptr[i + 1];
  final w = g.rawWeights.isNotEmpty ? g.rawWeights : g.values;
  for (var k = start; k < end; k++) {
    if (g.indices[k] == j) return w[k];
  }
  return 0.0;
}

/// Eigenvalues of a small (n ≤ ~16) symmetric matrix via cyclic Jacobi.
/// Input: n×n row-major in [a]. DESTRUCTIVE — modifies [a] in place.
/// Returns eigenvalues in ascending order.
Float64List _jacobiEigenvalues(Float64List a, int n) {
  if (n == 0) return Float64List(0);
  if (n == 1) return Float64List.fromList([a[0]]);
  if (n == 2) {
    final p = a[0], q = a[1], r = a[3];
    final mid = (p + r) * 0.5;
    final half = (p - r) * 0.5;
    final disc = math.sqrt(half * half + q * q);
    return Float64List.fromList([mid - disc, mid + disc]);
  }

  const maxSweeps = 50;
  const eps = 1e-12;

  for (var sweep = 0; sweep < maxSweeps; sweep++) {
    var offMax = 0.0;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final v = a[i * n + j].abs();
        if (v > offMax) offMax = v;
      }
    }
    if (offMax < eps) break;

    for (var p = 0; p < n; p++) {
      for (var q = p + 1; q < n; q++) {
        final apq = a[p * n + q];
        if (apq.abs() < eps * 0.01) continue;

        final app = a[p * n + p];
        final aqq = a[q * n + q];
        final diff = aqq - app;

        double t;
        if (diff.abs() < eps) {
          t = apq >= 0 ? 1.0 : -1.0;
        } else {
          final theta = diff / (2.0 * apq);
          t = (theta >= 0 ? 1.0 : -1.0) /
              (theta.abs() + math.sqrt(1.0 + theta * theta));
        }
        final c = 1.0 / math.sqrt(1.0 + t * t);
        final s = t * c;

        a[p * n + p] = app - t * apq;
        a[q * n + q] = aqq + t * apq;
        a[p * n + q] = 0.0;
        a[q * n + p] = 0.0;

        for (var i = 0; i < n; i++) {
          if (i == p || i == q) continue;
          final ip = a[i * n + p];
          final iq = a[i * n + q];
          final nip = c * ip - s * iq;
          final niq = s * ip + c * iq;
          a[i * n + p] = nip;
          a[p * n + i] = nip;
          a[i * n + q] = niq;
          a[q * n + i] = niq;
        }
      }
    }
  }

  final eigenvalues = Float64List(n);
  for (var i = 0; i < n; i++) {
    eigenvalues[i] = a[i * n + i];
  }
  eigenvalues.sort();
  return eigenvalues;
}

double _heatTraceFromEigs(Float64List eigenvalues, double t) {
  var sum = 0.0;
  for (var i = 0; i < eigenvalues.length; i++) {
    final x = -t * eigenvalues[i];
    if (x > -40.0) sum += math.exp(x);
  }
  return sum;
}

/// Full spectral path: enumerate all 2^H subsets, build each subgraph's
/// combinatorial Laplacian, Jacobi-eigensolve, compute heat trace.
HunkInteractionDecomposition _decomposeHunkSpectral(
  CsrGraph graph,
  List<int> nodes,
  double t,
) {
  if (nodes.length > _kHunkLatticeFullH) {
    nodes = nodes.sublist(0, _kHunkLatticeFullH);
  }
  final h = nodes.length;
  final size = 1 << h;
  final f = Float64List(size);

  for (var s = 1; s < size; s++) {
    final subset = <int>[];
    for (var b = 0; b < h; b++) {
      if (s & (1 << b) != 0) subset.add(nodes[b]);
    }
    final m = subset.length;

    if (m == 1) {
      f[s] = 1.0;
      continue;
    }

    // Build m×m combinatorial Laplacian of the subgraph.
    final lap = Float64List(m * m);
    for (var a = 0; a < m; a++) {
      for (var b = a + 1; b < m; b++) {
        final w = _csrRawWeight(graph, subset[a], subset[b]);
        if (w <= 0) continue;
        lap[a * m + b] = -w;
        lap[b * m + a] = -w;
        lap[a * m + a] += w;
        lap[b * m + b] += w;
      }
    }

    final eigenvalues = _jacobiEigenvalues(lap, m);
    f[s] = _heatTraceFromEigs(eigenvalues, t);
  }

  // Transform to Walsh space.
  walshHadamard(f, h);
  final inv = 1.0 / size;
  for (var i = 0; i < size; i++) {
    f[i] *= inv;
  }

  return _buildInteractionResult(f, h, isSpectral: true);
}

/// Quadratic shortcut: closed-form Walsh coefficients from pairwise
/// edge weights. The set function f(S) = Σ_{i<j∈S} w_{ij} is degree-2
/// in the indicator variables, so its WHT has non-zero coefficients only
/// at orders 0, 1, and 2.
///
///   f̂(∅) = W_total / 4
///   f̂({k}) = -d_k / 4
///   f̂({k,l}) = w_{kl} / 4
///
/// (Normalized by 1/2^H; the factor 2^{H-2}/2^H = 1/4 is universal.)
HunkInteractionDecomposition _decomposeHunkQuadratic(
  CsrGraph graph,
  List<int> nodes,
) {
  if (nodes.length > _kHunkLatticeMaxH) {
    nodes = nodes.sublist(0, _kHunkLatticeMaxH);
  }
  final h = nodes.length;
  final size = 1 << h;
  final f = Float64List(size);

  var totalWeight = 0.0;
  final degree = Float64List(h);

  for (var i = 0; i < h; i++) {
    for (var j = i + 1; j < h; j++) {
      final w = _csrRawWeight(graph, nodes[i], nodes[j]);
      if (w <= 0) continue;
      totalWeight += w;
      degree[i] += w;
      degree[j] += w;
      f[(1 << i) | (1 << j)] = w * 0.25;
    }
  }

  f[0] = totalWeight * 0.25;
  for (var k = 0; k < h; k++) {
    f[1 << k] = -degree[k] * 0.25;
  }

  return _buildInteractionResult(f, h, isSpectral: false);
}

HunkInteractionDecomposition _buildInteractionResult(
  Float64List spectrum,
  int h, {
  required bool isSpectral,
}) {
  final orderSpec = walshOrderSpectrum(spectrum, h);

  final dominant = <({int mask, int order, double coefficient})>[];
  final size = 1 << h;
  for (var s = 1; s < size; s++) {
    final v = spectrum[s];
    if (v.abs() < 1e-15) continue;
    dominant.add((mask: s, order: walshOrder(s), coefficient: v));
  }
  dominant.sort((a, b) => b.coefficient.abs().compareTo(a.coefficient.abs()));
  if (dominant.length > _kInteractionDominantLimit) {
    dominant.removeRange(_kInteractionDominantLimit, dominant.length);
  }

  final perHunk = Float64List(h);
  for (var i = 0; i < h; i++) {
    perHunk[i] = spectrum[1 << i];
  }

  var totalEnergy = 0.0;
  var entangledEnergy = 0.0;
  for (var k = 0; k <= h; k++) {
    totalEnergy += orderSpec[k];
    if (k >= 2) entangledEnergy += orderSpec[k];
  }
  final entanglement = totalEnergy > 0 ? entangledEnergy / totalEnergy : 0.0;

  return HunkInteractionDecomposition(
    h: h,
    walshSpectrum: spectrum,
    orderSpectrum: orderSpec,
    entanglementRatio: entanglement,
    dominantModes: dominant,
    perHunkCoefficient: perHunk,
    isSpectral: isSpectral,
  );
}

/// Decompose the interaction structure of hunks in a graph on the
/// Boolean lattice 2^[H].
///
/// [nodeSubset] selects which graph nodes to decompose. If null, all
/// graph nodes are used. The selected count must be ≤ [_kHunkLatticeMaxH].
///
/// For H ≤ 12: full spectral path (subgraph heat traces via Jacobi).
/// For H > 12: quadratic shortcut (Walsh from edge weights, orders 0-2).
HunkInteractionDecomposition decomposeHunkInteractions({
  required CsrGraph graph,
  List<int>? nodeSubset,
  double t = 1.0,
}) {
  var nodes = nodeSubset ??
      List<int>.generate(math.min(graph.n, _kHunkLatticeMaxH), (i) => i,
          growable: false);
  if (nodes.length > _kHunkLatticeMaxH) {
    nodes = List<int>.from(nodes.sublist(0, _kHunkLatticeMaxH));
  }
  final h = nodes.length;
  if (h < 2) {
    return HunkInteractionDecomposition(
      h: h,
      walshSpectrum: Float64List(1 << math.max(h, 1)),
      orderSpectrum: Float64List(h + 1),
      entanglementRatio: 0.0,
      dominantModes: const [],
      perHunkCoefficient: Float64List(h),
      isSpectral: false,
    );
  }

  if (h <= _kHunkLatticeFullH) {
    return _decomposeHunkSpectral(graph, nodes, t);
  }
  return _decomposeHunkQuadratic(graph, nodes);
}
