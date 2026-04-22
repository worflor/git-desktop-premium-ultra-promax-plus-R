// engram_text_kspace.dart
//
// K-space operations for arbitrary text — the bridge from LLM brainstorm
// prose back into the Alexandria geometry the engine was built on.
//
// The hunk encoder tokenises via `splitIdentifier`, which treats any
// non-alphanumeric as a boundary. That already covers natural-language
// prose: words are delimited by whitespace and punctuation. So for an
// idea like "looks like a concurrency refactor in the scheduler", the
// encoder sees the token list ["looks", "like", "concurrency", "refactor",
// "scheduler"] (stopwords too short to pass the ≥2 length filter drop
// out, and the AR(2) fit runs over the trajectory of their GloVe vectors).
//
// Two knobs the muse pipeline cares about:
//
//   • `encodeProse` — text → KVector or null if vocab coverage is thin
//   • `nearestRowsInTable` — KNN against the file K-table, for surfacing
//      files in the same semantic neighbourhood as a brainstormed idea
//
// Pure Dart, no allocation in the KNN hot path beyond the result list.

import 'dart:math' as math;
import 'dart:typed_data';

import 'engram_file_ktable.dart';
import 'engram_hunk_encoder.dart';

/// Encode arbitrary text into a K-vector using the loaded hunk encoder.
/// Returns null when GloVe coverage is too thin to fit an AR(2) — most
/// commonly short/vague prose ("looks weird", "maybe a bug") or ideas
/// dominated by proper nouns not in the embedding vocab.
/// The encoder internally applies `splitIdentifier` to each "raw token"
/// it receives. Splitting prose on whitespace up front keeps the
/// sub-tokens cleaner than passing whole sentences as a single token
/// (which would leave `splitIdentifier` walking char-by-char through
/// punctuation anyway — same result, slightly more work).
HunkKVector? encodeProse(String text, EngramHunkEncoder encoder) {
  if (text.isEmpty) return null;
  // Word-level tokenisation — space/punct as boundary, plus a length
  // guard so one-character glyphs don't bloat the trajectory buffer.
  final words = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    final isAlnum = (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A);
    if (isAlnum) {
      buf.writeCharCode(c);
    } else if (buf.isNotEmpty) {
      words.add(buf.toString());
      buf.clear();
    }
  }
  if (buf.isNotEmpty) words.add(buf.toString());
  if (words.isEmpty) return null;
  return encoder.encode(words);
}

/// Complex inner-product-based similarity between two K-vectors in ℂ^P.
///   sim = Re(⟨a, b⟩) / (‖a‖ · ‖b‖)   ∈ [-1, 1]
/// This is the real part of the hermitian inner product, normalised —
/// it's the natural cosine in complex K-space. 1.0 = same direction,
/// 0 = orthogonal, negative = opposite phase.
double cosineK(
  Float64List aRe,
  Float64List aIm,
  Float64List bRe,
  Float64List bIm,
) {
  if (aRe.length != bRe.length) return 0.0;
  final n = aRe.length;
  var dotRe = 0.0;
  var aNorm = 0.0;
  var bNorm = 0.0;
  for (var i = 0; i < n; i++) {
    final ar = aRe[i], ai = aIm[i];
    final br = bRe[i], bi = bIm[i];
    // Re(⟨a, b⟩) = Σ (aRe·bRe + aIm·bIm).
    dotRe += ar * br + ai * bi;
    aNorm += ar * ar + ai * ai;
    bNorm += br * br + bi * bi;
  }
  final denom = math.sqrt(aNorm) * math.sqrt(bNorm);
  if (denom <= 0) return 0.0;
  return dotRe / denom;
}

/// One file's similarity to a query K-vector, plus the row id.
class FileSimilarity {
  final int row;
  final String path;
  final double similarity;
  const FileSimilarity(this.row, this.path, this.similarity);
}

/// K-nearest-rows in [table] to the query vector (qRe, qIm). Returns
/// up to [topK] entries sorted by similarity descending, dropping
/// anything below [minSimilarity].
/// Cost: O(n · pairs) for the row scan + O(n · log topK) for the
/// streaming top-K; the brain's Cauchy-Schwarz / triangle tricks from
/// [EngramBrain.nearestWell] don't apply here because we want the
/// strongest *matches*, not the closest centroid, and the per-row
/// norms vary with the encoding quality of each file — pre-filtering
/// by norm gap would throw out valid partial matches.
List<FileSimilarity> nearestRowsInTable(
  EngramFileKTable table, {
  required Float64List qRe,
  required Float64List qIm,
  int topK = 8,
  double minSimilarity = 0.35,
}) {
  if (table.isEmpty || topK <= 0) return const [];
  final p = table.pairs;
  if (qRe.length != p || qIm.length != p) return const [];

  // Precondition: the squared-space gate below compares `dotRe² ≥
  // minSim² · rowNormSq · qNormSq`, which is monotone-equivalent to
  // `cos ≥ minSim` ONLY when `minSim ≥ 0`. A negative floor (e.g.
  // "admit anti-correlated rows too") would need a different gate,
  // and our cheap `dotRe ≤ 0` skip would silently discard valid
  // rows. All production call sites pass floors in [0.35, 0.55];
  // pinning the contract here stops a future caller from tripping
  // that footgun without discovering it.
  assert(minSimilarity >= 0,
      'nearestRowsInTable requires minSimilarity >= 0; '
      'negative floors would break the squared-space admission gate.');

  // Precompute ‖q‖² once. We keep it SQUARED (no outer sqrt) so the
  // per-row rejection test can gate on `dotRe² ≥ minSim² · rowNormSq ·
  // qNormSq` without a sqrt in the hot loop (Grimoire Circle XXIII /
  // XXV: stay in the representation where the cheap operation
  // dominates, pay for the transcendental only when admitting).
  var qNormSq = 0.0;
  for (var j = 0; j < p; j++) {
    qNormSq += qRe[j] * qRe[j] + qIm[j] * qIm[j];
  }
  if (qNormSq <= 0) return const [];
  // Assertion above ensures minSimilarity >= 0, so squaring is safe.
  final minSimSq = minSimilarity * minSimilarity;

  final n = table.n;
  final ri = table.kRi;

  // Streaming top-K: keep a bounded list sorted ascending by
  // similarity so the head is the current worst-kept. Cheap for small
  // topK — the muse pipeline caps this at a dozen or so.
  // Grimoire XIV: interleaved re/im per pair delivers both
  // components in one fetch, collapsing what used to be two disjoint
  // Float64List streams into a single Float64x2List stride.
  final kept = <FileSimilarity>[];
  for (var row = 0; row < n; row++) {
    final base = row * p;
    var dotRe = 0.0;
    var rowNormSq = 0.0;
    for (var j = 0; j < p; j++) {
      final a = ri[base + j];
      final ar = a.x;
      final ai = a.y;
      final br = qRe[j];
      final bi = qIm[j];
      dotRe += ar * br + ai * bi;
      rowNormSq += ar * ar + ai * ai;
    }
    if (rowNormSq <= 0 || dotRe <= 0) continue;
    // Squared-space gate: reject rows that can't clear the floor
    // without spending the sqrt. dotRe² ≥ minSim² · rowNormSq · qNormSq
    // ⟺ cos² ≥ minSim². Equivalent to the original comparison for
    // non-negative cosine (negative dotRe was already dropped above).
    final normProd = rowNormSq * qNormSq;
    if (dotRe * dotRe < minSimSq * normProd) continue;
    // Only now — after the row is known to clear the floor — do we
    // pay the one sqrt + division to recover the actual similarity.
    final sim = dotRe / math.sqrt(normProd);
    if (!sim.isFinite) continue;
    if (kept.length < topK) {
      kept.add(FileSimilarity(row, table.paths[row], sim));
      // Bubble down so head is the min.
      for (var i = kept.length - 1; i > 0; i--) {
        if (kept[i].similarity < kept[i - 1].similarity) {
          final tmp = kept[i];
          kept[i] = kept[i - 1];
          kept[i - 1] = tmp;
        } else {
          break;
        }
      }
    } else if (sim > kept.first.similarity) {
      kept[0] = FileSimilarity(row, table.paths[row], sim);
      // Re-sort just the head into position — small list, straight insertion.
      for (var i = 0; i < kept.length - 1; i++) {
        if (kept[i].similarity > kept[i + 1].similarity) {
          final tmp = kept[i];
          kept[i] = kept[i + 1];
          kept[i + 1] = tmp;
        } else {
          break;
        }
      }
    }
  }

  // Currently ascending; flip to descending for the caller.
  return kept.reversed.toList(growable: false);
}

/// K-nearest rows in [table] to the K-vector stored at [sourcePath]'s
/// own row. Thin wrapper over [nearestRowsInTable] that handles the
/// row → query-vector unpack (reading the interleaved `kRi` columns
/// into the two Float64List channels the KNN scan expects). Use this
/// whenever a feature asks "what files are semantically nearest to
/// THIS file?" — it keeps callers out of the AoSoA row-layout
/// internals.
///
/// Returns an empty list when [table] is empty, [sourcePath] isn't
/// encoded, or no row clears [minSimilarity]. The source path is
/// filtered out of the result by default so callers don't need to
/// re-check — the closest row is almost always [sourcePath] itself.
List<FileSimilarity> nearestKFilesForPath(
  EngramFileKTable table,
  String sourcePath, {
  int topK = 8,
  double minSimilarity = 0.35,
  bool excludeSource = true,
}) {
  if (table.isEmpty || topK <= 0) return const [];
  final row = table.rowOf(sourcePath);
  if (row == null) return const [];
  final p = table.pairs;
  if (p <= 0) return const [];

  // Unpack the interleaved AoSoA row into the two channels the KNN
  // scan expects. Cheap — a few dozen Float64x2 loads.
  final qRe = Float64List(p);
  final qIm = Float64List(p);
  final base = row * p;
  final ri = table.kRi;
  for (var j = 0; j < p; j++) {
    final v = ri[base + j];
    qRe[j] = v.x;
    qIm[j] = v.y;
  }

  // Over-pull by one so we can drop the self-match and still honour
  // the caller's topK budget. Cheap — `nearestRowsInTable` already
  // runs a streaming top-K, not a full sort.
  final scanTopK = excludeSource ? topK + 1 : topK;
  final raw = nearestRowsInTable(
    table,
    qRe: qRe,
    qIm: qIm,
    topK: scanTopK,
    minSimilarity: minSimilarity,
  );
  if (!excludeSource) return raw;
  final out = <FileSimilarity>[];
  for (final m in raw) {
    if (m.path == sourcePath) continue;
    out.add(m);
    if (out.length >= topK) break;
  }
  return out;
}
