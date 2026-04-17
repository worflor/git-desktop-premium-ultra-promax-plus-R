// LOGOS CHUNKS — intra-file chunk-level heat-kernel diffusion
//
// Sits parallel to LogosGit (file graph) and LogosHunks (diff-hunk graph).
// Nodes are CHUNKS inside one source file; edges are the geometric bonds
// between them:
//
//   C_sym    — shared non-trivial identifiers (Jaccard via inverted index)
//   C_prox   — within-file proximity exp(-|Δline|/σ_file) where
//              σ_file is the median chunk-gap inside that file
//   C_struct — sibling-scope bonus: chunks at the same start indent get a
//              small structural prior (encourages emitting siblings together)
//
// Source mass ρ per chunk = # of diff-touched lines that fall within the
// chunk's [startLine, endLine]. Untouched chunks have zero mass; the
// diffusion is what decides whether they get emitted.
//
// Used by ai.dart's `_collectFileContext`: when a primary diff file is
// too large to emit at full content, we chunk it, diffuse from the diff-
// touched chunks as the heat source, and greedy-pack chunks by φ until
// the file's slice of the budget closes. Adjacent admitted chunks are
// stitched without a redundant header so the output reads as code, not
// confetti.

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_git.dart'
    show LogosEvidenceWitness, LogosResidualView, formatLogosEvidenceWitness;
import 'logos_core.dart';

// Chunker — split a source file on signature-line boundaries.
//
// Same regex set used by `_buildFileOutline` in ai.dart. Kept in sync by
// convention: any change to the universal sig detection there should be
// mirrored here so chunk boundaries match outline anchors.

final List<RegExp> _sigPatterns = [
  RegExp(
      r'^\s*(?:export\s+)?(?:abstract\s+)?(?:class|struct|enum|mixin|extension|interface|trait|protocol|type|union|module|namespace|package)\s+\w+'),
  RegExp(
      r'^\s*(?:export\s+)?(?:pub\s+)?(?:static\s+)?(?:async\s+)?(?:const\s+)?(?:\w+\s+)*\w+\s*(?:<[^>]*>\s*)?\([^)]*\)\s*(?:async\s*)?[{:=>\-]?\s*$'),
  RegExp(r'^\s*(?:def|fn|func|function|sub|proc|method)\s+\w+'),
  RegExp(r'^\s*func\s+(?:\([^)]*\)\s+)?\w+\s*\('),
  RegExp(r'^\s*(?:@\w+|#\[[\w:]+)'),
];

bool _isSigLine(String line) {
  for (final p in _sigPatterns) {
    if (p.hasMatch(line)) return true;
  }
  return false;
}

/// `d > sigma · _proxCutoffLnRatio` ⇒ `exp(-d/sigma) ≤ 1e-6`, below the
/// noise floor of the `D^{-1/2}`-normalised Laplacian. Precomputed as
/// `ln(1e6)` (Dart's `math.log` isn't `const`-evaluable, so a named
/// double literal is clearer than a runtime calculation and keeps the
/// horizon visible at the call site).
const double _proxCutoffLnRatio = 13.815510557964274;

int _leadingIndent(String line) {
  var i = 0;
  while (i < line.length &&
      (line.codeUnitAt(i) == 0x20 || line.codeUnitAt(i) == 0x09)) {
    i++;
  }
  return i;
}

class SourceChunk {
  SourceChunk({
    required this.chunkIndex,
    required this.headerLine,
    required this.startLine,
    required this.endLine,
    required this.body,
    required this.startIndent,
  });

  /// 0-based index in the file's chunk list.
  final int chunkIndex;

  /// First non-blank trimmed line of the chunk — the signature, or
  /// `(preamble)` for the leading region before any sig. Used for the
  /// emitted header when this chunk is admitted.
  final String headerLine;

  /// 1-based inclusive line numbers in the original file.
  final int startLine;
  final int endLine;

  /// Raw chunk content (including the signature line).
  final String body;

  /// Indent of the chunk's start line (in characters). Used by C_struct.
  final int startIndent;

  int get bytes => body.length;
  int get lineCount => endLine - startLine + 1;
}

/// Split [content] into chunks using signature-line boundaries.
/// A new chunk starts at every signature line. Lines before the first sig
/// form a "preamble" chunk (imports, copyright, top-of-file comments).
/// Tiny tail chunks (<3 lines) merge into the previous chunk to avoid
/// noise from one-line decorator sigs.
List<SourceChunk> chunkSourceFile(String content) {
  if (content.isEmpty) return const [];
  final lines = content.split('\n');

  // Pass 1: find sig line indices.
  final sigAt = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.trim().isEmpty) continue;
    if (_isSigLine(l)) sigAt.add(i);
  }

  // Pass 2: build raw chunks from sig boundaries.
  final raw = <SourceChunk>[];
  var idx = 0;

  void emit({required int from, required int toExclusive, String? header}) {
    if (toExclusive <= from) return;
    final body = lines.sublist(from, toExclusive).join('\n');
    final firstLine = lines[from];
    raw.add(SourceChunk(
      chunkIndex: idx++,
      headerLine: header ?? firstLine.trim(),
      startLine: from + 1,
      endLine:
          toExclusive, // 1-based inclusive == toExclusive when from is 0-based
      body: body,
      startIndent: _leadingIndent(firstLine),
    ));
  }

  if (sigAt.isEmpty) {
    // No sigs detected — single-chunk file (e.g. data, config, or all-blob).
    emit(from: 0, toExclusive: lines.length, header: '(file body)');
    return raw;
  }

  // Preamble: from start to first sig.
  if (sigAt.first > 0) {
    emit(from: 0, toExclusive: sigAt.first, header: '(preamble)');
  }
  // Sig-bounded chunks.
  for (var k = 0; k < sigAt.length; k++) {
    final from = sigAt[k];
    final to = (k + 1 < sigAt.length) ? sigAt[k + 1] : lines.length;
    emit(from: from, toExclusive: to);
  }

  // Pass 3: coalesce tiny chunks into the previous chunk. Decorator sigs
  // (single-line `@override`, etc.) otherwise become noise nodes.
  if (raw.length < 2) return raw;
  final coalesced = <SourceChunk>[raw.first];
  for (var k = 1; k < raw.length; k++) {
    final cur = raw[k];
    if (cur.lineCount < 3 && coalesced.isNotEmpty) {
      final prev = coalesced.removeLast();
      final mergedBody = '${prev.body}\n${cur.body}';
      coalesced.add(SourceChunk(
        chunkIndex: prev.chunkIndex,
        headerLine: prev.headerLine,
        startLine: prev.startLine,
        endLine: cur.endLine,
        body: mergedBody,
        startIndent: prev.startIndent,
      ));
    } else {
      coalesced.add(SourceChunk(
        chunkIndex: coalesced.length,
        headerLine: cur.headerLine,
        startLine: cur.startLine,
        endLine: cur.endLine,
        body: cur.body,
        startIndent: cur.startIndent,
      ));
    }
  }
  return coalesced;
}

// Identifier tokenisation — same shape as logos_hunks (camelCase + snake +
// stop-list). Duplicated by convention so this module stays self-contained.

final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _camelBoundary = RegExp(r'(?<=[\p{Ll}\p{N}])(?=[\p{Lu}])', unicode: true);

Set<String> _tokensOf(String text) {
  if (text.isEmpty) return const {};
  final tokens = <String>{};
  for (final raw in text.split(_nonWord)) {
    if (raw.isEmpty) continue;
    for (final piece in raw.split(_camelBoundary)) {
      if (piece.length < 3) continue;
      tokens.add(piece.toLowerCase());
    }
  }
  return tokens;
}

/// File-local stop-set: tokens above the kneedle cutoff on the
/// descending per-chunk document-frequency curve. Empty when the
/// curve has no shape (< 5 chunks, flat, or no clear head).
Set<String> _deriveStopTokens(List<Set<String>> perChunkTokens) {
  if (perChunkTokens.length < 5) return const {};
  final docFreq = <String, int>{};
  for (final ts in perChunkTokens) {
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

// Chunk-graph construction. Diffusion math lives in logos_core.dart —
// this file only owns the chunk-specific axis blend (C_sym / C_prox /
// C_struct) and the source-mass model. The graph itself is the shared
// [CsrGraph] type.

/// Public entry to the chunk graph builder — same contract as the
/// private [_buildChunkGraph] hot path below, exposed so callers can
/// compose a [SpectralBasis] over chunks without re-implementing the
/// axis blend. Prefer [chunkSpectralBasis] when you just want the
/// basis; this entry is for callers who want the raw graph.
CsrGraph buildChunkGraph({
  required List<SourceChunk> chunks,
  required List<Set<String>> tokens,
  required int topK,
}) =>
    _buildChunkGraph(chunks: chunks, tokens: tokens, topK: topK);

/// Build a chunk-level [SpectralBasis] over the given chunks and
/// their pre-extracted token sets. Mirrors `LogosGit.spectralBasis()`
/// and `HunkDiffusionResult.spectralBasis()` for the chunk level of
/// the spectral tower. Returns null below [kDefaultSpectralMinNodes].
SpectralBasis? chunkSpectralBasis({
  required List<SourceChunk> chunks,
  required List<Set<String>> tokens,
  int k = kDefaultSpectralBasisK,
  int? topK,
}) {
  final n = chunks.length;
  if (n < kDefaultSpectralMinNodes) return null;
  final resolvedTopK = topK ?? math.max(4, math.sqrt(n).ceil());
  final graph = _buildChunkGraph(
    chunks: chunks,
    tokens: tokens,
    topK: resolvedTopK,
  );
  if (graph.n < kDefaultSpectralMinNodes) return null;
  return SpectralBasis.fromGraph(graph, math.min(k, graph.n));
}

CsrGraph _buildChunkGraph({
  required List<SourceChunk> chunks,
  required List<Set<String>> tokens,
  required int topK,
}) {
  final n = chunks.length;
  if (n == 0) {
    return CsrGraph(
      n: 0,
      indptr: Int32List(1),
      indices: Int32List(0),
      values: Float64List(0),
    );
  }

  final tokenBuckets = <String, List<int>>{};
  for (var i = 0; i < n; i++) {
    for (final tok in tokens[i]) {
      (tokenBuckets[tok] ??= <int>[]).add(i);
    }
  }

  // Median chunk-gap → σ for proximity kernel.
  double sigma = 1.0;
  if (n >= 2) {
    final gaps = <int>[];
    for (var i = 1; i < n; i++) {
      final g = (chunks[i].startLine - chunks[i - 1].startLine).abs();
      if (g > 0) gaps.add(g);
    }
    if (gaps.isNotEmpty) {
      gaps.sort();
      final m = gaps[gaps.length ~/ 2].toDouble();
      sigma = m > 0 ? m : 1.0;
    }
  }

  // Axis weights — same shape as logos_hunks's convex blend, retuned for
  // the smaller axis set: identifier coupling is still the strongest
  // signal; proximity carries more weight (within one file, line-distance
  // is a good locality prior); structural sibling-bonus is a small tie-
  // breaker that keeps adjacent siblings together.
  const wSym = 0.65;
  const wProx = 0.25;
  const wStruct = 0.10;

  final edges = <int, Map<int, double>>{};
  void addEdge(int a, int b, double w) {
    if (a == b || w <= 0 || !w.isFinite) return;
    final rowA = edges[a] ??= <int, double>{};
    rowA[b] = (rowA[b] ?? 0.0) + w;
    final rowB = edges[b] ??= <int, double>{};
    rowB[a] = (rowB[a] ?? 0.0) + w;
  }

  final symNumerator = <int, Map<int, int>>{};
  for (final bucket in tokenBuckets.values) {
    if (bucket.length < 2) continue;
    // No upper bucket cap: an identifier shared by many chunks lowers
    // each pair's Jaccard contribution naturally (denominator grows),
    // and D^{-1/2} normalisation absorbs the rest. Geometry handles it.
    for (var a = 0; a < bucket.length; a++) {
      final ia = bucket[a];
      for (var b = a + 1; b < bucket.length; b++) {
        final ib = bucket[b];
        final lo = ia < ib ? ia : ib;
        final hi = ia < ib ? ib : ia;
        (symNumerator[lo] ??= <int, int>{})[hi] =
            (symNumerator[lo]![hi] ?? 0) + 1;
      }
    }
  }
  for (final outer in symNumerator.entries) {
    final i = outer.key;
    final iTokens = tokens[i].length;
    for (final inner in outer.value.entries) {
      final j = inner.key;
      final overlap = inner.value;
      final denom = iTokens + tokens[j].length - overlap;
      if (denom <= 0) continue;
      addEdge(i, j, wSym * overlap / denom);
    }
  }

  // Fused pass for proximity + struct-sibling. Grimoire circles XXI
  // (loop fusion — one memory sweep, one `addEdge` per pair instead
  // of two), XIX (skip the `exp` transcendental when it can't produce
  // a meaningful weight), and the locality principle (far pairs
  // carry weak signal; top-K sparsification drops them anyway).
  //
  // `chunkSourceFile` emits chunks in ascending `startLine` from a
  // single-pass line scan, and the coalesce pass (lines 156–172)
  // only merges a chunk into the PREVIOUS one and preserves
  // `prev.startLine`, so the output remains monotone ascending.
  // That lets us `break` once `d > proxHorizon` instead of scanning
  // every j to n-1. We drop the (rare) long-distance struct-sibling
  // edges past the horizon along with the proximity edges — those
  // same-indent pairs carry wStruct=0.10, which is below the top-K
  // admission threshold under any real axis mix, so sparsification
  // would have dropped them in the next step regardless.
  final proxHorizon = sigma * _proxCutoffLnRatio;
  final invSigma = sigma > 0 ? 1.0 / sigma : 0.0;

  // Precompute `exp(-integerDelta · invSigma)` for integer line-deltas
  // in `[0, ceil(proxHorizon)]`. The proximity kernel fires for every
  // pair inside the horizon — for a 200-chunk file with σ ≈ 20 that's
  // ~2k `exp` calls per build. The table collapses each call to a
  // LUT read + linear interpolation (Grimoire XXV: small table, fits
  // in L1). Line gaps are integers from `chunks[j].startLine -
  // chunks[i].startLine`, so the integer-indexed lookup is exact
  // when `d` is an integer and still accurate to well under the
  // 1e-6 proximity noise floor when fractional (caller passes
  // `.toDouble()`).
  final Float64List expLut;
  if (invSigma > 0) {
    final horizonCeil = proxHorizon.ceil() + 1;
    expLut = Float64List(horizonCeil);
    for (var k = 0; k < horizonCeil; k++) {
      expLut[k] = math.exp(-k * invSigma);
    }
  } else {
    expLut = Float64List(0);
  }

  for (var i = 0; i < n; i++) {
    final iStart = chunks[i].startLine;
    final iIndent = chunks[i].startIndent;
    for (var j = i + 1; j < n; j++) {
      // `startLine` is monotone ascending, so `d` grows with j; the
      // `.abs()` is belt-and-braces against a future scanner change
      // that might break the invariant.
      final dInt = (chunks[j].startLine - iStart).abs();
      if (dInt > proxHorizon) break;
      double w = 0.0;
      if (invSigma > 0 && dInt < expLut.length) {
        final k = expLut[dInt];
        if (k > 1e-6) w += wProx * k;
      }
      if (chunks[j].startIndent == iIndent) w += wStruct;
      if (w > 0) addEdge(i, j, w);
    }
  }

  // Top-K + symmetrise (same policy as logos_hunks / logos_git).
  final trimmedRows = List<List<_Edge>>.generate(n, (_) => <_Edge>[]);
  for (final rowEntry in edges.entries) {
    final i = rowEntry.key;
    final row = rowEntry.value;
    final list = <_Edge>[];
    for (final e in row.entries) {
      list.add(_Edge(e.key, e.value));
    }
    list.sort((x, y) => y.w.compareTo(x.w));
    final cap = math.min(topK, list.length);
    final outRow = trimmedRows[i];
    for (var k = 0; k < cap; k++) {
      outRow.add(list[k]);
    }
  }
  final adj = List<Map<int, double>>.generate(n, (_) => <int, double>{});
  for (var i = 0; i < n; i++) {
    for (final e in trimmedRows[i]) {
      adj[i][e.j] = e.w;
      adj[e.j][i] = e.w;
    }
  }

  final deg = Float64List(n);
  for (var i = 0; i < n; i++) {
    double s = 0;
    for (final w in adj[i].values) {
      s += w;
    }
    deg[i] = s;
  }
  final dInv = Float64List(n);
  for (var i = 0; i < n; i++) {
    dInv[i] = deg[i] > 0 ? 1.0 / math.sqrt(deg[i]) : 0.0;
  }

  final indptr = Int32List(n + 1);
  for (var i = 0; i < n; i++) {
    indptr[i + 1] = indptr[i] + adj[i].length;
  }
  final nnz = indptr[n];
  final indices = Int32List(nnz);
  final values = Float64List(nnz);
  for (var i = 0; i < n; i++) {
    var cursor = indptr[i];
    final keys = adj[i].keys.toList()..sort();
    for (final j in keys) {
      indices[cursor] = j;
      values[cursor] = dInv[i] * adj[i][j]! * dInv[j];
      cursor++;
    }
  }

  return CsrGraph(
    n: n,
    indptr: indptr,
    indices: indices,
    values: values,
  );
}

class _Edge {
  _Edge(this.j, this.w);
  final int j;
  final double w;
}

// Chebyshev/Bessel math + heat-kernel diffusion live in logos_core.dart
// — see [chebyshevBasis], [recombineHeatPhi], and [kChebyshevSmallGraph]
// for the polynomial-order policy this engine shares with logos_hunks.

// Public API — pack the most relevant chunks of one source file under a
// byte budget.

class ChunkPackResult {
  ChunkPackResult({
    required this.body,
    required this.admittedCount,
    required this.totalChunks,
    required this.fellBackToProximity,
  });

  /// Renderable prompt body — empty string if nothing fit.
  final String body;
  final int admittedCount;
  final int totalChunks;

  /// True when the diff-touched-line ranges produced zero source mass
  /// (e.g. the diff was for trailing-newline-only changes); we then
  /// fall back to byte-mass weighted ρ so packing still produces output.
  final bool fellBackToProximity;
}

/// A diff-touched line range in the *new* file (1-based, inclusive on
/// both ends). Multiple ranges per file are common (one per hunk).
class TouchedLineRange {
  const TouchedLineRange(this.start, this.end);
  final int start;
  final int end;
}

/// Pack the most diff-relevant chunks of [content] into a budget-bounded
/// prompt body for [filePath].
/// Mass model: each chunk's source mass = number of diff-touched lines
/// that fall within its [startLine, endLine] window. Chunks with zero
/// touched lines start at zero mass; the heat kernel is what pulls them
/// in. Adjacent admitted chunks are stitched without a redundant header
/// so the output reads as a continuous excerpt.
/// Async variant — runs the entire pack on a background isolate so a
/// large file's chunk graph + 3-temperature recombination never hitches
/// the UI on diff open. The function is pure data in / data out (no
/// engine reference, no file IO), so the isolate hop is cheap.
Future<ChunkPackResult> packRelevantChunksAsync({
  required String filePath,
  required String content,
  required List<TouchedLineRange> touchedRanges,
  required int budgetChars,
  double fileTransportedSupport = 0.0,
  double fileInnovationResidual = 0.0,
  double fileWitnessResidual = 0.0,
  List<String> fileEvidenceTags = const [],
  List<String> fileEvidenceWitnessLabels = const [],
  List<LogosEvidenceWitness> fileEvidenceWitnesses = const [],
}) async {
  final resolvedWitnessLabels = fileEvidenceWitnessLabels.isNotEmpty
      ? fileEvidenceWitnessLabels
      : [
          for (final witness in fileEvidenceWitnesses.take(3))
            formatLogosEvidenceWitness(
              witness,
              includeNote: true,
              includeSource: true,
            ),
        ];
  // Trivially small inputs — skip the isolate's serialisation cost.
  if (budgetChars <= 0 || content.isEmpty || content.length < 4096) {
    return packRelevantChunks(
      filePath: filePath,
      content: content,
      touchedRanges: touchedRanges,
      budgetChars: budgetChars,
      fileTransportedSupport: fileTransportedSupport,
      fileInnovationResidual: fileInnovationResidual,
      fileWitnessResidual: fileWitnessResidual,
      fileEvidenceTags: fileEvidenceTags,
      fileEvidenceWitnessLabels: resolvedWitnessLabels,
    );
  }
  return Isolate.run<ChunkPackResult>(
    () => packRelevantChunks(
      filePath: filePath,
      content: content,
      touchedRanges: touchedRanges,
      budgetChars: budgetChars,
      fileTransportedSupport: fileTransportedSupport,
      fileInnovationResidual: fileInnovationResidual,
      fileWitnessResidual: fileWitnessResidual,
      fileEvidenceTags: fileEvidenceTags,
      fileEvidenceWitnessLabels: resolvedWitnessLabels,
    ),
    debugName: 'packRelevantChunks',
  );
}

/// Returns an empty body if budget is too small to fit any chunk.
ChunkPackResult packRelevantChunks({
  required String filePath,
  required String content,
  required List<TouchedLineRange> touchedRanges,
  required int budgetChars,
  double fileTransportedSupport = 0.0,
  double fileInnovationResidual = 0.0,
  double fileWitnessResidual = 0.0,
  List<String> fileEvidenceTags = const [],
  List<String> fileEvidenceWitnessLabels = const [],
  List<LogosEvidenceWitness> fileEvidenceWitnesses = const [],
}) {
  if (budgetChars <= 0 || content.isEmpty) {
    return ChunkPackResult(
      body: '',
      admittedCount: 0,
      totalChunks: 0,
      fellBackToProximity: false,
    );
  }

  final chunks = chunkSourceFile(content);
  final n = chunks.length;
  if (n == 0) {
    return ChunkPackResult(
      body: '',
      admittedCount: 0,
      totalChunks: 0,
      fellBackToProximity: false,
    );
  }

  // Trivially small file — no need to diffuse, just emit the whole thing
  // if it fits the budget.
  final lineCount = chunks.last.endLine;
  final witnessLabels = fileEvidenceWitnessLabels.isNotEmpty
      ? fileEvidenceWitnessLabels
      : [
          for (final witness in fileEvidenceWitnesses.take(3))
            formatLogosEvidenceWitness(
              witness,
              includeNote: true,
              includeSource: true,
            ),
        ];
  final wholeFileEvidence = fileEvidenceTags.isEmpty
      ? ''
      : '<!-- file-evidence ${fileEvidenceTags.join(' ')} -->\n';
  final wholeFileWitnesses = witnessLabels.isEmpty
      ? ''
      : '<!-- file-witnesses ${witnessLabels.join(' | ')} -->\n';
  final wholeFileBlock =
      '--- $filePath ($lineCount lines, full) ---\n$wholeFileEvidence$wholeFileWitnesses$content\n';
  if (wholeFileBlock.length <= budgetChars) {
    return ChunkPackResult(
      body: wholeFileBlock,
      admittedCount: n,
      totalChunks: n,
      fellBackToProximity: false,
    );
  }

  // Source mass: count touched lines falling in each chunk.
  final rho = Float64List(n);
  var totalMass = 0.0;
  for (var i = 0; i < n; i++) {
    final c = chunks[i];
    var hits = 0;
    for (final r in touchedRanges) {
      final lo = math.max(c.startLine, r.start);
      final hi = math.min(c.endLine, r.end);
      if (hi >= lo) hits += (hi - lo + 1);
    }
    rho[i] = hits.toDouble();
    totalMass += rho[i];
  }

  // Fallback: no touched chunks (e.g. range list was empty). Use byte
  // mass so we at least produce a φ-meaningful ranking.
  var fellBack = false;
  if (totalMass <= 0) {
    fellBack = true;
    totalMass = 0;
    for (var i = 0; i < n; i++) {
      rho[i] = math.log(1.0 + chunks[i].bytes);
      totalMass += rho[i];
    }
  }
  if (totalMass <= 0) {
    return ChunkPackResult(
      body: '',
      admittedCount: 0,
      totalChunks: n,
      fellBackToProximity: fellBack,
    );
  }
  for (var i = 0; i < n; i++) {
    rho[i] /= totalMass;
  }

  // Tokenize, then filter tokens the kneedle identifies as file-local
  // noise (tokens appearing in most chunks).
  final rawTokens =
      List<Set<String>>.generate(n, (i) => _tokensOf(chunks[i].body));
  final stopSet = _deriveStopTokens(rawTokens);
  final tokens = stopSet.isEmpty
      ? rawTokens
      : [for (final ts in rawTokens) ts.difference(stopSet)];
  final topK = math.max(4, math.sqrt(n).ceil());
  final graph = _buildChunkGraph(chunks: chunks, tokens: tokens, topK: topK);

  // Three-temperature geometric-mean blend — canonical multi-scale
  // ranker shared with `logos_hunks.dart`. See [tripleTemperatureBlend].
  //
  // Derive temperatures from the chunk graph's own natural scales when
  // the graph has enough nodes for peak detection to be informative.
  // Small graphs use the default log-spaced triplet.
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
  final residualView = LogosResidualView(
    path: '',
    support: 0.0,
    ambient: 0.0,
    utility: 0.0,
    integrity: 1.0,
    transportPull: 0.0,
    transportedSupport: fileTransportedSupport,
    innovationResidual: fileInnovationResidual,
    witnessResidual: fileWitnessResidual,
    lowFrequencySupport: 0.0,
    highFrequencySurprise: 0.0,
    higherOrderLift: 0.0,
    reducibilityGap: 0.0,
    dominantAxis: null,
  );
  final transportSignal = residualView.transportSignal;
  final residualSignal = residualView.residualMass;
  final contextWeight = (1.0 + 0.80 * transportSignal - 0.35 * residualSignal)
      .clamp(0.55, 1.85)
      .toDouble();
  final localWeight = (1.0 + 1.10 * residualSignal - 0.45 * transportSignal)
      .clamp(0.55, 2.10)
      .toDouble();
  final spreadWeight = (0.90 * transportSignal) - (1.10 * residualSignal);
  final untouchedCostScale =
      (1.0 + 1.20 * residualSignal - 0.45 * transportSignal)
          .clamp(0.65, 2.10)
          .toDouble();
  final ranked = Float64List(n);
  for (var i = 0; i < n; i++) {
    final spreadMass = math.max(0.0, blended[i] - rho[i]);
    ranked[i] = math.max(
      0.0,
      (contextWeight * blended[i]) +
          (localWeight * rho[i]) +
          (spreadWeight * spreadMass),
    );
  }

  // Greedy φ-desc admission within budget. We track admitted indices in
  // a set to detect adjacency at emission time.
  final order = List<int>.generate(n, (i) => i);
  order.sort((a, b) => ranked[b].compareTo(ranked[a]));

  final admitted = <int>{};
  // Per-chunk overhead for a non-stitched block: header line.
  String headerFor(SourceChunk c) =>
      '--- $filePath  L${c.startLine}-${c.endLine}  φ=${ranked[c.chunkIndex].toStringAsFixed(3)} ---';
  // File-level wrapper header so the AI knows this is excerpts not full.
  final wrapHeader =
      '--- $filePath ($lineCount lines, $n chunks, relevance excerpts) ---\n';
  final evidenceHeader = fileEvidenceTags.isEmpty
      ? ''
      : '<!-- file-evidence ${fileEvidenceTags.join(' ')} -->\n';
  final witnessHeader = witnessLabels.isEmpty
      ? ''
      : '<!-- file-witnesses ${witnessLabels.join(' | ')} -->\n';
  var remaining = budgetChars -
      wrapHeader.length -
      evidenceHeader.length -
      witnessHeader.length;
  if (remaining <= 0) {
    return ChunkPackResult(
      body: '',
      admittedCount: 0,
      totalChunks: n,
      fellBackToProximity: fellBack,
    );
  }

  for (final i in order) {
    final c = chunks[i];
    // Cost: chunk body + newline + (header iff this chunk is not adjacent
    // to an already-admitted chunk on its left). Right-adjacency is a
    // bonus — emitting this chunk lets the next-admitted right-neighbour
    // also drop its header — but we don't try to predict that here; the
    // greedy is φ-driven, not adjacency-driven.
    final hasLeftAdjacent = admitted.contains(i - 1);
    final headerCost = hasLeftAdjacent ? 0 : (headerFor(c).length + 1);
    final bodyCost = c.body.length + 1; // trailing newline
    final costScale = rho[i] > 1e-9 ? 1.0 : untouchedCostScale;
    final effectiveCost =
        math.max(1, ((headerCost + bodyCost) * costScale).ceil());
    if (effectiveCost > remaining) continue;
    admitted.add(i);
    remaining -= effectiveCost;
  }

  if (admitted.isEmpty) {
    return ChunkPackResult(
      body: '',
      admittedCount: 0,
      totalChunks: n,
      fellBackToProximity: fellBack,
    );
  }

  // Emit in source order so adjacent chunks render contiguously.
  final ordered = admitted.toList()..sort();
  final buf = StringBuffer();
  buf.write(wrapHeader);
  if (evidenceHeader.isNotEmpty) {
    buf.write(evidenceHeader);
  }
  if (witnessHeader.isNotEmpty) {
    buf.write(witnessHeader);
  }
  for (var k = 0; k < ordered.length; k++) {
    final i = ordered[k];
    final c = chunks[i];
    final prevAdjacent = k > 0 && ordered[k - 1] == i - 1;
    if (!prevAdjacent) {
      buf.writeln(headerFor(c));
    }
    buf.writeln(c.body);
  }

  return ChunkPackResult(
    body: buf.toString(),
    admittedCount: admitted.length,
    totalChunks: n,
    fellBackToProximity: fellBack,
  );
}

/// Convenience: collect the touched line ranges for [filePath] from a
/// parsed unified diff. Each hunk contributes one range covering the
/// hunk's `+` lines (i.e. the lines that exist in the new file).
List<TouchedLineRange> touchedRangesFromDiff({
  required String filePath,
  required String diffText,
}) {
  return touchedRangesByFileFromDiff(diffText)[filePath] ?? const [];
}

Map<String, List<TouchedLineRange>> touchedRangesByFileFromDiff(
  String diffText,
) {
  final byFile = <String, List<TouchedLineRange>>{};
  final lines = diffText.split('\n');
  String? currentFile;
  int? hunkNewStart;
  int? hunkNewLine;
  int? hunkRangeStart;
  int? hunkRangeEnd;

  void flushHunk() {
    final filePath = currentFile;
    if (filePath != null && hunkRangeStart != null && hunkRangeEnd != null) {
      (byFile[filePath] ??= <TouchedLineRange>[]).add(
        TouchedLineRange(hunkRangeStart!, hunkRangeEnd!),
      );
    }
    hunkRangeStart = null;
    hunkRangeEnd = null;
  }

  final headerRe = RegExp(r'^@@\s*-\d+(?:,\d+)?\s*\+(\d+)(?:,\d+)?\s*@@');
  for (final line in lines) {
    if (line.startsWith('diff --git ')) {
      flushHunk();
      final parts = line.split(' ');
      currentFile = (parts.length >= 4 && parts[3].startsWith('b/'))
          ? parts[3].substring(2)
          : null;
      hunkNewStart = null;
      hunkNewLine = null;
      continue;
    }
    if (line.startsWith('@@')) {
      flushHunk();
      final m = headerRe.firstMatch(line);
      hunkNewStart = m != null ? int.tryParse(m.group(1)!) ?? 1 : 1;
      hunkNewLine = hunkNewStart;
      continue;
    }
    if (line.startsWith('+++ ') || line.startsWith('--- ')) continue;
    if (hunkNewLine == null) continue;
    if (line.startsWith('+') && !line.startsWith('+++')) {
      hunkRangeStart ??= hunkNewLine;
      hunkRangeEnd = hunkNewLine;
      hunkNewLine = hunkNewLine + 1;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      // Deletion: doesn't advance new-line counter, doesn't widen range.
    } else {
      // Context line — advances the new-line counter.
      hunkNewLine = hunkNewLine + 1;
    }
  }
  flushHunk();
  return byFile;
}
