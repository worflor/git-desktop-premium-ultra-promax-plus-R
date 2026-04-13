// ═════════════════════════════════════════════════════════════════════════
// LOGOS HUNKS — hunk-level heat-kernel diffusion
// ═════════════════════════════════════════════════════════════════════════
//
// Sits parallel to LogosGit's file graph. Nodes are HUNKS inside one diff;
// edges are the geometric bonds between them:
//
//   H_sym  — shared non-trivial identifiers (Jaccard via inverted index)
//   H_file — parent-file coupling. Within-file = 1. Cross-file borrows
//            the already-computed file-φ from the LogosGit engine. This
//            is the factorisation trick — file-graph ⊗ hunk-graph —
//            so cross-file hunk coupling costs ~zero.
//   H_prox — within-file proximity kernel exp(-|Δline|/σ_file) where
//            σ_file is the median line-gap inside that file (self-derived)
//   H_vol  — add/delete balance similarity; pure-add hunks cluster with
//            pure-add, pure-delete with pure-delete, balanced with balanced
//
// Weights compose as a convex blend; edges sparsified top-K per node;
// Laplacian normalised; heat-kernel via Chebyshev polynomial expansion
// (same math as logos_git.dart, just a smaller graph).
//
// Source mass ρ per hunk = log(1+bytes). Every hunk is a source — the
// diffusion measures centrality relative to the diff as a whole.
//
// Recombines at three temperatures (0.5, 1.0, 2.0) and blends via
// geometric mean — the three-temperature-blend trick from commit_tagger.
//
// Used by ai.dart's diff prompt packer: when the full diff overflows
// the budget, hunks are emitted in φ-desc order at full content. Logos
// picks which hunks matter most; peripheral mass-edit noise drops off.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_git.dart' show LogosGit;

// ─────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────

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
  HunkRanking({required this.hunk, required this.phi, required this.rank});
  final DiffHunk hunk;
  final double phi;
  final int rank; // 0 = top
}

// ─────────────────────────────────────────────────────────────────────────
// Parser — unified diff → List<DiffHunk>
// ─────────────────────────────────────────────────────────────────────────

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

String _pathFromDiffHeader(String line) {
  final parts = line.split(' ');
  if (parts.length < 4) return 'unknown';
  final candidate = parts[3];
  return candidate.startsWith('b/') ? candidate.substring(2) : candidate;
}

// ─────────────────────────────────────────────────────────────────────────
// Identifier tokenisation — camelCase + snake_case + separators.
// Deliberately matches the commit-tagger basename tokenizer so identifiers
// coupling here are the same kind logos treats as meaningful elsewhere.
// ─────────────────────────────────────────────────────────────────────────

final _nonWord = RegExp(r'[^A-Za-z0-9]+');
final _camelBoundary = RegExp(r'(?<=[a-z0-9])(?=[A-Z])');

Set<String> _tokensOf(String text) {
  if (text.isEmpty) return const {};
  final tokens = <String>{};
  for (final raw in text.split(_nonWord)) {
    if (raw.isEmpty) continue;
    for (final piece in raw.split(_camelBoundary)) {
      if (piece.length < 3) continue; // drop noise like 'i', 'id', 'fn'
      final lower = piece.toLowerCase();
      if (_isCommonWord(lower)) continue;
      tokens.add(lower);
    }
  }
  return tokens;
}

// Tiny stop-list — universal programming filler; not language-specific
// enough to cause trouble, just trims noise that would saturate the
// inverted index.
const _commonWords = <String>{
  'the', 'and', 'for', 'with', 'from', 'this', 'that', 'into', 'null',
  'true', 'false', 'return', 'function', 'const', 'let', 'var', 'final',
  'new', 'get', 'set', 'void', 'int', 'string', 'bool', 'double', 'list',
  'map', 'else', 'then', 'import', 'export', 'class', 'async', 'await',
};
bool _isCommonWord(String s) => _commonWords.contains(s);

/// Only the +/- payload contributes to hunk identifier tokens — that's
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

// ─────────────────────────────────────────────────────────────────────────
// CSR graph + Chebyshev heat-kernel — mirrors logos_git.dart but private
// to this module. Kept inline so the hunk path is self-contained and the
// file graph (logos_git) can evolve independently.
// ─────────────────────────────────────────────────────────────────────────

class _CsrHunkGraph {
  _CsrHunkGraph({
    required this.n,
    required this.indptr,
    required this.indices,
    required this.values,
  });
  final int n;
  final Int32List indptr;
  final Int32List indices;
  /// Already fused with D^{-1/2} on both sides — applyLsym is v - W_norm·v.
  final Float64List values;

  void applyLsym(Float64List v, Float64List out) {
    for (var i = 0; i < n; i++) {
      double s = 0;
      final start = indptr[i];
      final end = indptr[i + 1];
      for (var k = start; k < end; k++) {
        s += values[k] * v[indices[k]];
      }
      out[i] = v[i] - s;
    }
  }
}

/// Build the hunk graph.
///
/// [fileCoupling] is an optional map that gives, for each non-source file,
/// the file-φ score from LogosGit. When building cross-file hunk edges we
/// multiply by this to get hunk-level cross-file weight for free — the
/// factorisation trick.
_CsrHunkGraph _buildHunkGraph({
  required List<DiffHunk> hunks,
  required List<Set<String>> tokens,
  required Map<String, double> fileCouplingFromParent,
  required int topK,
}) {
  final n = hunks.length;
  if (n == 0) {
    return _CsrHunkGraph(
      n: 0,
      indptr: Int32List(1),
      indices: Int32List(0),
      values: Float64List(0),
    );
  }

  // Inverted token index → candidate pair generator. We only score pairs
  // that share ≥1 token; this is O(Σ bucket_size²) which is small in
  // practice thanks to the stop-list and the min-length filter.
  final tokenBuckets = <String, List<int>>{};
  for (var i = 0; i < n; i++) {
    for (final tok in tokens[i]) {
      (tokenBuckets[tok] ??= <int>[]).add(i);
    }
  }

  // Precompute per-file statistics for H_prox (line-gap σ).
  final fileToHunks = <String, List<int>>{};
  for (var i = 0; i < n; i++) {
    (fileToHunks[hunks[i].filePath] ??= <int>[]).add(i);
  }
  final fileSigma = <String, double>{};
  for (final entry in fileToHunks.entries) {
    final ids = entry.value;
    if (ids.length < 2) continue;
    final gaps = <int>[];
    for (var k = 1; k < ids.length; k++) {
      final a = hunks[ids[k - 1]].newStart;
      final b = hunks[ids[k]].newStart;
      final g = (b - a).abs();
      if (g > 0) gaps.add(g);
    }
    if (gaps.isEmpty) continue;
    gaps.sort();
    // Median gap as the natural within-file proximity scale.
    final median = gaps[gaps.length ~/ 2].toDouble();
    fileSigma[entry.key] = median > 0 ? median : 1.0;
  }

  // Axis weights — convex blend. Chosen by order-of-magnitude balance,
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

  // ── H_sym: Jaccard via inverted index ──────────────────────────────
  //
  // For each bucket of hunks sharing a token, add pair contributions
  // weighted by 1/bucket_size. Repeated across all shared tokens this
  // converges to the proper Jaccard numerator; the denominator is
  // |tokens[i] ∪ tokens[j]| ≈ |tokens[i]| + |tokens[j]| - overlap.
  // We approximate by tallying numerator first, then normalising at
  // the end.
  final symNumerator = <int, Map<int, int>>{};
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
        (symNumerator[lo] ??= <int, int>{})[hi] =
            (symNumerator[lo]![hi] ?? 0) + 1;
      }
    }
  }
  symNumerator.forEach((i, row) {
    row.forEach((j, overlap) {
      final denom = tokens[i].length + tokens[j].length - overlap;
      if (denom <= 0) return;
      final jaccard = overlap / denom;
      addEdge(i, j, wSym * jaccard);
    });
  });

  // ── H_file: same-file = 1; cross-file = parent-file-φ ──────────────
  for (final group in fileToHunks.values) {
    for (var a = 0; a < group.length; a++) {
      for (var b = a + 1; b < group.length; b++) {
        addEdge(group[a], group[b], wFile * 1.0);
      }
    }
  }
  // Cross-file hunk coupling via LogosGit file-φ. We treat the file
  // with the higher φ contribution as the "host" and multiply the pair
  // weight by the lesser of their φ values (conservative).
  if (fileCouplingFromParent.isNotEmpty) {
    final filePaths = fileToHunks.keys.toList(growable: false);
    for (var a = 0; a < filePaths.length; a++) {
      final fa = filePaths[a];
      final phiA = fileCouplingFromParent[fa] ?? 0.0;
      if (phiA <= 0) continue;
      for (var b = a + 1; b < filePaths.length; b++) {
        final fb = filePaths[b];
        final phiB = fileCouplingFromParent[fb] ?? 0.0;
        if (phiB <= 0) continue;
        final coupling = math.min(phiA, phiB);
        if (coupling <= 0) continue;
        final listA = fileToHunks[fa]!;
        final listB = fileToHunks[fb]!;
        // Cap the pair explosion: cross-file file pairs with a large
        // hunk×hunk product would dominate edge count. Scale weight by
        // 1/sqrt(|A|·|B|) so the total mass injected per file pair stays
        // ~coupling, not coupling·|A|·|B|.
        final norm = 1.0 / math.sqrt(listA.length * listB.length);
        for (final ia in listA) {
          for (final ib in listB) {
            addEdge(ia, ib, wFile * coupling * norm);
          }
        }
      }
    }
  }

  // ── H_prox: within-file line distance ──────────────────────────────
  for (final entry in fileToHunks.entries) {
    final ids = entry.value;
    if (ids.length < 2) continue;
    final sigma = fileSigma[entry.key] ?? 1.0;
    for (var a = 0; a < ids.length; a++) {
      for (var b = a + 1; b < ids.length; b++) {
        final la = hunks[ids[a]].newStart;
        final lb = hunks[ids[b]].newStart;
        final d = (lb - la).abs().toDouble();
        final k = math.exp(-d / sigma);
        if (k <= 1e-6) continue;
        addEdge(ids[a], ids[b], wProx * k);
      }
    }
  }

  // ── H_vol: add/delete balance similarity ───────────────────────────
  // balance_i = (adds - dels) / (adds + dels + 1) ∈ [-1, 1]
  // similarity_ij = 1 - |balance_i - balance_j| / 2 ∈ [0, 1]
  // Only contribute within-file (balance across unrelated files is
  // meaningless noise). This is a tiny signal; it breaks ties between
  // structurally-similar hunks by preferring same-character edits.
  for (final group in fileToHunks.values) {
    if (group.length < 2) continue;
    for (var a = 0; a < group.length; a++) {
      final ha = hunks[group[a]];
      final balA = (ha.additions - ha.deletions) /
          (ha.additions + ha.deletions + 1);
      for (var b = a + 1; b < group.length; b++) {
        final hb = hunks[group[b]];
        final balB = (hb.additions - hb.deletions) /
            (hb.additions + hb.deletions + 1);
        final sim = 1.0 - ((balA - balB).abs() / 2.0);
        addEdge(group[a], group[b], wVol * sim);
      }
    }
  }

  // ── Top-K sparsification per node ──────────────────────────────────
  final trimmedRows = List<List<_Edge>>.generate(n, (_) => <_Edge>[]);
  edges.forEach((i, row) {
    final list = row.entries
        .map((e) => _Edge(e.key, e.value))
        .toList(growable: false);
    list.sort((x, y) => y.w.compareTo(x.w));
    final cap = math.min(topK, list.length);
    for (var k = 0; k < cap; k++) {
      trimmedRows[i].add(list[k]);
    }
  });

  // Symmetrise: an edge survives if EITHER endpoint kept it. This is the
  // same top-K-then-symmetrise policy LogosGit uses.
  final adj = List<Map<int, double>>.generate(n, (_) => <int, double>{});
  for (var i = 0; i < n; i++) {
    for (final e in trimmedRows[i]) {
      adj[i][e.j] = e.w;
      adj[e.j][i] = e.w; // symmetric weight
    }
  }

  // Degree then D^{-1/2} fusion.
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

  // Pack CSR. Pre-count for indptr.
  final indptr = Int32List(n + 1);
  for (var i = 0; i < n; i++) {
    indptr[i + 1] = indptr[i] + adj[i].length;
  }
  final nnz = indptr[n];
  final indices = Int32List(nnz);
  final values = Float64List(nnz);
  for (var i = 0; i < n; i++) {
    var cursor = indptr[i];
    // Sort neighbours by index for nicer locality; not required.
    final keys = adj[i].keys.toList()..sort();
    for (final j in keys) {
      indices[cursor] = j;
      values[cursor] = dInv[i] * adj[i][j]! * dInv[j];
      cursor++;
    }
  }

  return _CsrHunkGraph(
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

// ─────────────────────────────────────────────────────────────────────────
// Chebyshev-Bessel coefficients and heat-kernel recombine.
//
// Same recurrence as logos_git.dart's _buildDiffusionBasis; reproduced
// here to keep this module independent of that file's private symbols.
// ─────────────────────────────────────────────────────────────────────────

const int _kChebyshev = 24;

List<double> _besselCoeffs(double t, int K) {
  // c_k(t) = 2·e^{-t}·I_k(-t) for k≥1, c_0 = e^{-t}·I_0(-t).
  // I_k(-t) = (-1)^k · I_k(t).
  // Compute I_k(t) via the ascending power series:
  //   I_k(t) = Σ_{m=0..∞} (t/2)^{2m+k} / (m! · (m+k)!)
  // Converges fast for our t ∈ [0.5, 2.0].
  final coeffs = List<double>.filled(K + 1, 0.0);
  final eNegT = math.exp(-t);
  final half = t / 2.0;
  for (var k = 0; k <= K; k++) {
    // Compute I_k(t) by series; stop when terms fall below 1e-18.
    var term = 1.0;
    // (t/2)^k / k!
    for (var i = 1; i <= k; i++) {
      term *= half / i;
    }
    var sum = term;
    var m = 0;
    while (true) {
      m++;
      // term *= (t/2)^2 / (m · (m+k))
      term *= (half * half) / (m * (m + k));
      sum += term;
      if (term.abs() < 1e-18) break;
      if (m > 400) break;
    }
    final ikT = sum;
    final ikMinusT = (k.isEven ? 1.0 : -1.0) * ikT;
    final c = (k == 0 ? 1.0 : 2.0) * eNegT * ikMinusT;
    coeffs[k] = c;
  }
  return coeffs;
}

Float64List _recombinePhi({
  required _CsrHunkGraph graph,
  required Float64List basis, // (K+1) · n row-major
  required double t,
  required int K,
}) {
  final n = graph.n;
  final coeffs = _besselCoeffs(t, K);
  final phi = Float64List(n);
  for (var k = 0; k <= K; k++) {
    final c = coeffs[k];
    if (c.abs() < 1e-12) continue;
    final base = k * n;
    for (var i = 0; i < n; i++) {
      phi[i] += c * basis[base + i];
    }
  }
  return phi;
}

Float64List _buildBasis({
  required _CsrHunkGraph graph,
  required Float64List rho,
  required int K,
}) {
  final n = graph.n;
  final basis = Float64List((K + 1) * n);
  for (var i = 0; i < n; i++) {
    basis[i] = rho[i];
  }
  final scratch = Float64List(n);
  final t0 = Float64List.fromList(rho);
  final t1 = Float64List(n);
  graph.applyLsym(t0, scratch);
  for (var i = 0; i < n; i++) {
    t1[i] = scratch[i] - t0[i];
    basis[n + i] = t1[i];
  }
  final t2 = Float64List(n);
  for (var k = 2; k <= K; k++) {
    graph.applyLsym(t1, scratch);
    final base = k * n;
    for (var i = 0; i < n; i++) {
      t2[i] = 2 * (scratch[i] - t1[i]) - t0[i];
      basis[base + i] = t2[i];
    }
    t0.setAll(0, t1);
    t1.setAll(0, t2);
  }
  return basis;
}

// ─────────────────────────────────────────────────────────────────────────
// Public API — rank hunks by semantic centrality φ in this diff.
// ─────────────────────────────────────────────────────────────────────────

class HunkDiffusionResult {
  HunkDiffusionResult({
    required this.rankings,
    required this.fellBackToChurn,
  });

  /// Hunks in descending φ order. First = most central.
  final List<HunkRanking> rankings;

  /// True when the graph was degenerate (empty, single-hunk, or zero mass)
  /// and we fell back to ranking by churn. Callers may log this but
  /// behaviour is otherwise identical from their perspective.
  final bool fellBackToChurn;
}

/// Rank [hunks] by heat-kernel centrality.
///
/// If a [logosEngine] is provided we use it to compute the cross-file
/// coupling prior for the H_file axis — the factorisation trick. If it's
/// null (cold repo, no engine yet), within-file coupling still works and
/// the rest of the axes carry the load; cross-file edges simply don't
/// get the file-φ boost.
HunkDiffusionResult rankHunksByPhi({
  required List<DiffHunk> hunks,
  LogosGit? logosEngine,
}) {
  final n = hunks.length;
  if (n == 0) {
    return HunkDiffusionResult(rankings: const [], fellBackToChurn: false);
  }
  if (n == 1) {
    return HunkDiffusionResult(
      rankings: [HunkRanking(hunk: hunks[0], phi: 1.0, rank: 0)],
      fellBackToChurn: false,
    );
  }

  // Token sets per hunk (change lines only).
  final tokens = List<Set<String>>.generate(n, (i) => _hunkChangeTokens(hunks[i]));

  // Cross-file coupling prior: ask logos how "hot" each touched file is
  // when the source set is the whole touched-file set. Every touched file
  // gets a φ; we use it as the weight-multiplier on cross-file hunk pairs.
  final fileCoupling = <String, double>{};
  final touchedFiles = <String>{for (final h in hunks) h.filePath};
  if (logosEngine != null && touchedFiles.isNotEmpty) {
    try {
      final weights = <String, double>{for (final p in touchedFiles) p: 1.0};
      final scores = logosEngine.diffuseWeighted(weights);
      for (final s in scores) {
        if (touchedFiles.contains(s.path) && s.phi > 0) {
          fileCoupling[s.path] = s.phi;
        }
      }
    } catch (_) {
      // Graceful: engine errors never block the diff packer.
    }
  }

  // Top-K per node: sqrt(n) is the classical "enough-neighbours" heuristic
  // that keeps the graph sparse while preserving global connectivity.
  final topK = math.max(4, math.sqrt(n).ceil());

  final graph = _buildHunkGraph(
    hunks: hunks,
    tokens: tokens,
    fileCouplingFromParent: fileCoupling,
    topK: topK,
  );

  // Source mass ρ = log(1+bytes). Normalised to unit mass inside the
  // basis builder (we normalise here too for consistency).
  final rho = Float64List(n);
  var totalMass = 0.0;
  for (var i = 0; i < n; i++) {
    final m = math.log(1.0 + hunks[i].bytes);
    rho[i] = m > 0 ? m : 0.0;
    totalMass += rho[i];
  }
  if (totalMass <= 0 || graph.n == 0) {
    // Degenerate — no mass or no nodes. Fall back to churn order.
    final fallback = [...hunks]..sort((a, b) => b.churn.compareTo(a.churn));
    return HunkDiffusionResult(
      rankings: [
        for (var i = 0; i < fallback.length; i++)
          HunkRanking(hunk: fallback[i], phi: 0.0, rank: i),
      ],
      fellBackToChurn: true,
    );
  }
  for (var i = 0; i < n; i++) {
    rho[i] /= totalMass;
  }

  // Build the Chebyshev basis once, recombine at three temperatures.
  final basis = _buildBasis(graph: graph, rho: rho, K: _kChebyshev);

  final phi05 = _recombinePhi(graph: graph, basis: basis, t: 0.5, K: _kChebyshev);
  final phi10 = _recombinePhi(graph: graph, basis: basis, t: 1.0, K: _kChebyshev);
  final phi20 = _recombinePhi(graph: graph, basis: basis, t: 2.0, K: _kChebyshev);

  const eps = 1e-12;
  final blended = Float64List(n);
  for (var i = 0; i < n; i++) {
    final a = phi05[i] > 0 ? phi05[i] : 0.0;
    final b = phi10[i] > 0 ? phi10[i] : 0.0;
    final c = phi20[i] > 0 ? phi20[i] : 0.0;
    if (a + b + c <= 0) {
      blended[i] = 0.0;
      continue;
    }
    blended[i] = math.pow((a + eps) * (b + eps) * (c + eps), 1.0 / 3).toDouble();
  }

  final indexed = List<int>.generate(n, (i) => i);
  indexed.sort((a, b) => blended[b].compareTo(blended[a]));

  final rankings = <HunkRanking>[];
  for (var r = 0; r < indexed.length; r++) {
    final id = indexed[r];
    rankings.add(HunkRanking(hunk: hunks[id], phi: blended[id], rank: r));
  }
  return HunkDiffusionResult(
    rankings: rankings,
    fellBackToChurn: false,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// Prompt packing — emit full hunk bodies greedily under a byte budget.
// ─────────────────────────────────────────────────────────────────────────

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

/// Pack hunks into a prompt-safe body in φ-desc order. Emits full hunk
/// bodies; hunks that don't fit the remaining budget are skipped rather
/// than truncated (a partial hunk is worse than no hunk — it breaks
/// git-apply and confuses the model).
///
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

  // Group admitted hunks by parent file so the emitted body reads like a
  // normal diff: one header per file, its admitted hunks in order.
  final perFile = <String, List<DiffHunk>>{};

  // Header overhead per file: `diff --git a/<p> b/<p>\n--- a/<p>\n+++ b/<p>\n`
  int headerCost(String p) => 'diff --git a/$p b/$p\n--- a/$p\n+++ b/$p\n'.length;
  // Overhead for the wrapping tag and metadata line.
  const wrapOverhead = 200;
  var remaining = budgetChars - wrapOverhead;

  for (final r in rankings) {
    final h = r.hunk;
    final needsHeader = !perFile.containsKey(h.filePath);
    final cost = h.bytes + (needsHeader ? headerCost(h.filePath) : 0);
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
  // admitted set. φ ranking governs ADMISSION; emission order restores
  // the normal diff reading shape so the model doesn't have to re-sort.
  final fileOrder = perFile.keys.toList()..sort();
  final buf = StringBuffer();
  buf.writeln('<logos_packed_diff admitted=${admitted.length} skipped=${skipped.length}>');
  for (final fp in fileOrder) {
    final group = perFile[fp]!..sort((a, b) => a.hunkIndex.compareTo(b.hunkIndex));
    buf.writeln('diff --git a/$fp b/$fp');
    buf.writeln('--- a/$fp');
    buf.writeln('+++ b/$fp');
    for (final h in group) {
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
