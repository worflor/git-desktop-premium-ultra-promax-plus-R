// LOGOS HUNKS — hunk-level heat-kernel diffusion
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

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'engram_bootstrap.dart' show EngramAssets;
import 'engram_hunk_encoder.dart';
import 'logos_core.dart';
import 'logos_git.dart' show LogosGit;

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
  });
  final DiffHunk hunk;
  final double phi;
  final int rank; // 0 = top

  /// Nearest Alexandria well for this hunk (e.g. "computing", "well_43").
  /// Null when engram assets weren't loaded, the brain had zero wells, or
  /// the hunk didn't have enough in-vocab sub-tokens to fit an AR(2).
  /// Surfaced in the prompt bundle so the model sees feature-cluster
  /// membership alongside φ.
  final String? wellName;

  /// Raw RMS distance to the nearest well centroid in K-space. Lower =
  /// stronger domain match. Present whenever [wellName] is.
  final double? wellDistance;
}

// Parser — unified diff → List<DiffHunk>

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

// Identifier tokenisation — camelCase + snake_case + separators.
// Deliberately matches the commit-tagger basename tokenizer so identifiers
// coupling here are the same kind logos treats as meaningful elsewhere.

final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _camelBoundary =
    RegExp(r'(?<=[\p{Ll}\p{N}])(?=[\p{Lu}])', unicode: true);

/// Horizon multiplier for H_prox: pairs with `d ≥ σ · ratio` contribute
/// `exp(-ratio) ≈ 1e-6` — below the noise floor after D^{-1/2} Laplacian
/// normalisation and Chebyshev basis truncation. Precomputed as `ln(1e6)`
/// since `math.log` isn't a const expression in Dart; tightening the
/// floor is a literal change.
const double _proxHorizonLnRatio = 13.815510557964274;

/// Maximum hunk-pair edges materialised per (file_a, file_b) cross-file
/// coupling pass. Above this, the loop samples a deterministic stride
/// of representative pairs that preserves the file pair's total mass
/// without paying for the |A|·|B| explosion. Picked to stay within an
/// order of magnitude of the per-node top-K fanout the symmetriser
/// keeps anyway, so larger values would do redundant work.
const int _kCrossFileFanoutCap = 32;

Set<String> _tokensOf(String text) {
  if (text.isEmpty) return const {};
  final tokens = <String>{};
  for (final raw in text.split(_nonWord)) {
    if (raw.isEmpty) continue;
    for (final piece in raw.split(_camelBoundary)) {
      if (piece.length < 3) continue; // drop noise like 'i', 'id', 'fn'
      tokens.add(piece.toLowerCase());
    }
  }
  return tokens;
}

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
  // Kneedle — bend of the descending curve (0,1)→(1,0).
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

// Hunk-graph construction. Diffusion math lives in logos_core.dart —
// this file only owns the hunk-specific axis blend (H_sym / H_file /
// H_prox / H_vol) and the source-mass model.

/// Build the hunk graph.
/// [fileCoupling] is an optional map that gives, for each non-source file,
/// the file-φ score from LogosGit. When building cross-file hunk edges we
/// multiply by this to get hunk-level cross-file weight for free — the
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

  // Inverted token index → candidate pair generator. We only score pairs
  // that share ≥1 token; this is O(Σ bucket_size²) which is small in
  // practice thanks to the stop-list and the min-length filter.
  final tokenBuckets = <String, List<int>>{};
  for (var i = 0; i < n; i++) {
    for (final tok in tokens[i]) {
      (tokenBuckets[tok] ??= <int>[]).add(i);
    }
  }

  // Precompute per-file statistics for H_prox (line-gap σ). Sort each
  // file's hunk-id list by newStart once here — downstream consumers
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
      // ids is sorted by newStart, so b ≥ a and abs() is redundant.
      final g = hunks[ids[k]].newStart - hunks[ids[k - 1]].newStart;
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

  // Engram-augmented H_sym blend.
  //
  // When engram assets are loaded, each hunk has a K-vector ∈ ℂ^P that
  // encodes its semantic position in Alexandria's GloVe-seeded well
  // geometry. Cosine similarity between two hunk K-vectors ∈ [0,1]
  // captures "shared concept space" even when no identifier strings
  // overlap — a hunk using `dispatchEvent` and one using `emitSignal`
  // share zero Jaccard but ~0.7 K-cosine. That's the feature-cluster
  // signal Jaccard misses.
  //
  // **Blend is evidence-weighted, not magic-constant-weighted.** Each
  // signal contributes in proportion to `log1p(evidence)` — the same
  // nats-of-information metric the Born mixer uses elsewhere in the
  // engine. A hunk with many shared tokens leans Jaccard; a hunk with
  // many in-vocab GloVe hits leans engram. Neither axis gets an
  // arbitrary weight floor or ceiling — their evidence decides.
  //
  //   w_jac = log1p(|tokens_i| + |tokens_j|)   — larger bag → better Jaccard
  //   w_eng = log1p(min(hits_i, hits_j))      — more hits → tighter K-vector
  //   blended = (w_jac·jaccard + w_eng·cos) / (w_jac + w_eng)
  //
  // Pairs with neither Jaccard overlap nor an engram connection drop
  // out entirely — preserving graph sparsity. Pairs with engram signal
  // but no Jaccard still enter the graph: we seed those via the
  // file-level H_file coupling below when both files have touched
  // hunks, and via an e-decay thresholded engram-only pass here when
  // they don't.
  //
  // The engram-only admission threshold is `1/e ≈ 0.368` — the natural
  // exponential decay floor. Below 1/e the cosine has decayed past one
  // e-folding from perfect alignment; that's the classical "signal has
  // faded to noise" boundary, not a hand-picked decimal.
  final engramOnlyThreshold = math.exp(-1.0);

  // Pass 1: pairs with at least one shared token. Blend Jaccard with
  // engram cosine using evidence-weighted convex combination.
  symNumerator.forEach((i, row) {
    row.forEach((j, overlap) {
      final denom = tokens[i].length + tokens[j].length - overlap;
      if (denom <= 0) return;
      final jaccard = overlap / denom;
      double weight;
      if (engramKVectors != null) {
        final kvi = engramKVectors[i];
        final kvj = engramKVectors[j];
        final cos = EngramHunkEncoder.cosine(kvi, kvj);
        if (cos > 0 && kvi != null && kvj != null) {
          // log1p of pool size = Jaccard's own evidence in nats.
          final jaccardEvidence =
              math.log(1.0 + (tokens[i].length + tokens[j].length).toDouble());
          // log1p of min vocab hits = engram's evidence in nats.
          final engramEvidence = math.log(1.0 +
              (kvi.vocabHits < kvj.vocabHits
                  ? kvi.vocabHits
                  : kvj.vocabHits)
                  .toDouble());
          final totalEvidence = jaccardEvidence + engramEvidence;
          final blended = totalEvidence > 0
              ? (jaccardEvidence * jaccard + engramEvidence * cos) /
                  totalEvidence
              : jaccard;
          weight = wSym * blended;
        } else {
          // One or both hunks couldn't be encoded — fall back to pure
          // Jaccard so H_sym degrades gracefully per hunk.
          weight = wSym * jaccard;
        }
      } else {
        weight = wSym * jaccard;
      }
      addEdge(i, j, weight);
    });
  });

  // Pass 2: engram-only edges. Walk every pair that has K-vectors but
  // did NOT share any tokens, and admit those clearing the 1/e cosine
  // floor. This is O(N²) on hunks that have K-vectors — we bound it
  // by the hunk count (already ≤ hundreds in practice) and skip
  // entirely when engram isn't loaded. The engram-only weight uses
  // pure engram evidence (no Jaccard term, by definition there's no
  // Jaccard overlap on these pairs), scaled by `w_eng / (w_eng + 1)`
  // — a self-normalising factor derivable from the evidence blend
  // with the Jaccard evidence held at its "zero overlap, single
  // witness" baseline of log(1+1) = ln(2).
  if (engramKVectors != null) {
    for (var i = 0; i < n; i++) {
      final kvi = engramKVectors[i];
      if (kvi == null) continue;
      final alreadyBonded = symNumerator[i];
      for (var j = i + 1; j < n; j++) {
        final kvj = engramKVectors[j];
        if (kvj == null) continue;
        // Skip pairs already scored in pass 1.
        if (alreadyBonded != null && alreadyBonded.containsKey(j)) continue;
        final cos = EngramHunkEncoder.cosine(kvi, kvj);
        if (cos < engramOnlyThreshold) continue;
        final engEvidence = math.log(1.0 +
            (kvi.vocabHits < kvj.vocabHits ? kvi.vocabHits : kvj.vocabHits)
                .toDouble());
        // Self-normalised engram-only weight. With Jaccard evidence =
        // ln(2) (the zero-overlap baseline), the blend collapses to:
        //   weight = cos · engEvidence / (engEvidence + ln2)
        // which tends to `cos` as evidence grows and to `0` when
        // evidence is tiny — exactly the "confidence-gated signal"
        // shape the Born mixer uses on its axes.
        final selfNorm = engEvidence / (engEvidence + math.ln2);
        addEdge(i, j, wSym * cos * selfNorm);
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
  // Cross-file hunk coupling via LogosGit file-φ. We treat the file
  // with the higher φ contribution as the "host" and multiply the pair
  // weight by the lesser of their φ values (conservative).
  //
  // Fanout cap: the original |A|·|B| double loop allocated up to
  // ~|A|·|B| edge entries per file pair, then the top-K sparsifier
  // discarded the bulk. On a 20-file × 10-hunk diff that was ~200k
  // wasted addEdge calls. We now cap the per-pair fanout at
  // [_kCrossFileFanoutCap]: once the product exceeds the cap, sample
  // a deterministic subset of representative pairs that preserves the
  // total mass (each kept edge carries the full weight share that the
  // dropped edges would have summed to). The 1/sqrt normaliser is
  // unchanged, so total injected mass per file pair still equals
  // ~coupling regardless of the fanout path taken.
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

  // Edges land inside the σ-scaled horizon; beyond it `exp(-d/σ)` is
  // below [_proxFloor] — numerically indistinguishable from zero after
  // D^{-1/2} normalisation — so we break the inner loop. Because `ids`
  // is sorted by newStart (monotone non-decreasing), the first `b` that
  // exceeds the horizon proves all later `b` do too. The horizon is
  // derived from the floor (not a magic constant): `exp(-d/σ) ≥ ε ⟺
  // d ≤ σ·ln(1/ε)`. On a file with 50 scattered hunks this collapses
  // exp() calls from 1225 to roughly `hunks × horizon / median-gap`.
  for (final entry in fileToHunks.entries) {
    final ids = entry.value;
    if (ids.length < 2) continue;
    final sigma = fileSigma[entry.key] ?? 1.0;
    final horizon = sigma * _proxHorizonLnRatio;
    for (var a = 0; a < ids.length; a++) {
      final la = hunks[ids[a]].newStart;
      for (var b = a + 1; b < ids.length; b++) {
        final d = hunks[ids[b]].newStart - la; // sorted ⇒ ≥ 0
        if (d >= horizon) break;
        addEdge(ids[a], ids[b], wProx * math.exp(-d / sigma));
      }
    }
  }

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
// for the polynomial-order policy this engine shares with logos_chunks.

// Public API — rank hunks by semantic centrality φ in this diff.

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
/// If a [logosEngine] is provided we use it to compute the cross-file
/// coupling prior for the H_file axis — the factorisation trick. If it's
/// null (cold repo, no engine yet), within-file coupling still works and
/// the rest of the axes carry the load; cross-file edges simply don't
/// get the file-φ boost.
HunkDiffusionResult rankHunksByPhi({
  required List<DiffHunk> hunks,
  LogosGit? logosEngine,
  EngramAssets? engramAssets,
}) {
  // Resolve the engine-side coupling prior on the calling thread (it
  // touches the engine, which we don't want to ship across an isolate).
  // Then dispatch the heavy graph build + Chebyshev to the pure-data
  // core path.
  final fileCoupling = _resolveFileCoupling(hunks, logosEngine);
  return _rankHunksByPhiCore(
    hunks: hunks,
    fileCoupling: fileCoupling,
    engramAssets: engramAssets,
  );
}

/// Async variant — runs the graph build + 3-temperature recombination
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
}) async {
  final fileCoupling = _resolveFileCoupling(hunks, logosEngine);
  // Trivial cases — skip the isolate hop's serialisation cost.
  if (hunks.length <= 1) {
    return _rankHunksByPhiCore(
      hunks: hunks,
      fileCoupling: fileCoupling,
      engramAssets: engramAssets,
    );
  }
  return Isolate.run<HunkDiffusionResult>(
    () => _rankHunksByPhiCore(
      hunks: hunks,
      fileCoupling: fileCoupling,
      engramAssets: engramAssets,
    ),
    debugName: 'rankHunksByPhi',
  );
}

Map<String, double> _resolveFileCoupling(
    List<DiffHunk> hunks, LogosGit? engine) {
  final coupling = <String, double>{};
  if (engine == null) return coupling;
  final touchedFiles = <String>{for (final h in hunks) h.filePath};
  if (touchedFiles.isEmpty) return coupling;
  try {
    final weights = <String, double>{for (final p in touchedFiles) p: 1.0};
    final evidence = engine.gatherEvidence(
      focusWeights: weights,
      excludePaths: const {},
    );
    if (evidence != null) {
      for (final s in evidence.ranked) {
        if (touchedFiles.contains(s.path)) {
          final inherited = s.support * s.integrity;
          if (inherited > 0) coupling[s.path] = inherited;
        }
      }
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
  return coupling;
}

HunkDiffusionResult _rankHunksByPhiCore({
  required List<DiffHunk> hunks,
  required Map<String, double> fileCoupling,
  EngramAssets? engramAssets,
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
  // Tokenize, then filter tokens the kneedle identifies as diff-local
  // noise (tokens that appear in most hunks).
  final rawTokens =
      List<Set<String>>.generate(n, (i) => _hunkChangeTokens(hunks[i]));
  final stopSet = _deriveStopTokens(rawTokens);
  final tokens = stopSet.isEmpty
      ? rawTokens
      : [for (final ts in rawTokens) ts.difference(stopSet)];

  // Optional engram H_sym augmentation. Build the encoder from the
  // already-transferred byte blobs (cheap inside this isolate) and
  // encode every hunk to a K-vector. Returns a list aligned with
  // `hunks` — entries stay null for hunks that couldn't be encoded
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
  // Build the Chebyshev basis once via the shared core, then recombine
  // at three temperatures for the geometric-mean blend.
  final basis = chebyshevBasis(graph: graph, rho: rho, K: kChebyshevSmallGraph);

  final phi05 = recombineHeatPhi(graph: graph, basis: basis, t: 0.5, K: kChebyshevSmallGraph);
  final phi10 = recombineHeatPhi(graph: graph, basis: basis, t: 1.0, K: kChebyshevSmallGraph);
  final phi20 = recombineHeatPhi(graph: graph, basis: basis, t: 2.0, K: kChebyshevSmallGraph);

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
    final kv = engramKVectors?[id];
    rankings.add(HunkRanking(
      hunk: hunks[id],
      phi: blended[id],
      rank: r,
      wellName: kv?.well?.name,
      wellDistance: kv?.well?.rawDistance,
    ));
  }
  return HunkDiffusionResult(
    rankings: rankings,
    fellBackToChurn: false,
  );
}

// Prompt packing — emit full hunk bodies greedily under a byte budget.

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
  // diff with φ + well labels without re-walking `rankings`.
  final byHunk = <DiffHunk, HunkRanking>{
    for (final r in rankings) r.hunk: r,
  };
  // Any engram-derived labels? If not we skip the metadata annotation
  // overhead entirely (keeps behaviour identical to the pre-engram
  // builds when assets aren't loaded).
  final anyWells = rankings.any((r) => r.wellName != null);
  // Budget cost of an in-diff annotation line, in characters. Grows
  // with each emitted hunk — approximately `<!-- engram well=NAME
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
  int headerCost(String p) => 'diff --git a/$p b/$p\n--- a/$p\n+++ b/$p\n'.length;
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
  // admitted set. φ ranking governs ADMISSION; emission order restores
  // the normal diff reading shape so the model doesn't have to re-sort.
  final fileOrder = perFile.keys.toList()..sort();
  final buf = StringBuffer();
  buf.writeln(
      '<logos_packed_diff admitted=${admitted.length} skipped=${skipped.length}>');
  for (final fp in fileOrder) {
    final group = perFile[fp]!..sort((a, b) => a.hunkIndex.compareTo(b.hunkIndex));
    buf.writeln('diff --git a/$fp b/$fp');
    buf.writeln('--- a/$fp');
    buf.writeln('+++ b/$fp');
    for (final h in group) {
      final ranking = byHunk[h];
      // Annotate with the nearest Alexandria well and φ — a feature-
      // cluster hint for the LLM. Wrapped in an HTML-style comment so
      // most diff renderers just show it inline; `git apply` ignores
      // lines between hunks, so the output stays applicable when
      // emitted for that purpose.
      if (ranking != null && ranking.wellName != null) {
        buf.writeln(
            '<!-- engram well=${ranking.wellName} phi=${ranking.phi.toStringAsFixed(3)} -->');
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
