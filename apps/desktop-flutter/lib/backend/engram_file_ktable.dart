// engram_file_ktable.dart — dense column-store of per-file K-vectors.
//
// The LogosGit engine wants to ask "what K-vector does this file have?"
// and "what well does this file live in?" thousands of times during a
// single build. The old storage was `Map<String, HunkKVector>` — one
// hashmap entry per file, each pointing at an object holding two
// Float64Lists, an `EngramWellMatch` struct, and scalar metadata.
//
// That shape *answered* the question but fought the geometry at every
// step: a hashmap lookup for the path, an object dereference for the
// HunkKVector, two more object dereferences for the Float64Lists, a
// fifth dereference for the well match. Five pointer hops to reach a
// f64 value that conceptually lives at `kRe[row * pairs + pair]`.
//
// This file gives the geometry its native shape. Columns live in
// contiguous typed arrays. Rows are addressed by integer id. The
// `pathToRow` map is the ONLY hashmap in the hot path, and it's
// touched once per query to translate a path into an index — after
// that, everything is pointer-bumping linear access.
//
// Public surface mirrors what callers used to ask of the map:
//
//   • `rowOf(path)` — O(1) path → row id (or null for unencoded files)
//   • `wellOf(path)` / `wellOfRow(row)` — semantic well name, null if none
//   • `viewKRe(row)` / `viewKIm(row)` — zero-copy Float64List slices
//     of the flat columns (no allocation)
//   • Direct flat-array access (`kRe`, `kIm`, `vocabHits`, …) for hot
//     paths that iterate over rows — the LogosGit EN axis does this
//
// Construction is one-shot from a `Map<String, HunkKVector>` — the
// output of the parallel encode phase. The map itself is discarded
// after the table is built. For a 1000-file repo this replaces ~1000
// hashmap entries + 1000 HunkKVector objects + 3000 Float64List
// wrappers with a handful of typed arrays.

import 'dart:typed_data';

import 'engram_hunk_encoder.dart';

/// Sentinel "no well" value stored in [EngramFileKTable.wellIdx] for
/// rows whose encoder returned `HunkKVector.well == null`.
const int kEngramNoWell = -1;

/// Dense column-store for per-file engram encodings.
/// Observably immutable after construction. Safe to share across
/// isolates — the typed-array columns copy as bulk bytes, the String
/// list + Map are small and cheap to serialise. Carries one internal
/// lazy cache (the well→rows reverse index) which doesn't affect
/// observable state.
class EngramFileKTable {
  EngramFileKTable._({
    required this.pairs,
    required this.n,
    required this.paths,
    required Map<String, int> pathToRow,
    required this.kRi,
    required this.meanRms,
    required this.vocabHits,
    required this.wellIdx,
    required this.wellRawDistance,
    required this.wellWeightedDistance,
    required this.wellNamesByOriginalIndex,
  }) : _pathToRow = pathToRow;

  /// Number of complex pairs per K-vector (matches `brain.pairs`).
  final int pairs;

  /// Number of encoded file rows.
  final int n;

  /// Row id → repo-relative path. Parallel to every column array.
  final List<String> paths;

  /// Path → row id. The only hashmap access on the hot path; translates
  /// an external-facing path into a column-store index so subsequent
  /// reads are pointer-bumping array loads.
  final Map<String, int> _pathToRow;

  /// Interleaved K-vector as `Float64x2List` (grimoire XIV / AoSoA):
  /// one vector lane per pair, with real in `.x` and imaginary in `.y`.
  /// Addressed as `kRi[row * pairs + pair]`.
  ///
  /// Replaced the earlier two-column `kRe` + `kIm` storage because the
  /// hot loop (`_cosineRows` inside `_EnAxis`) reads BOTH components
  /// per pair; two separate arrays forced four disjoint cache-line
  /// streams (re[a], im[a], re[b], im[b]). The interleaved layout
  /// fuses re/im into one fetch per pair so a single cache line
  /// carries up to four consecutive complex values at once.
  final Float64x2List kRi;

  /// Per-row mean RMS of the AR(2) fit. f32 because this is a signal-
  /// quality indicator, not a precision-critical value.
  final Float32List meanRms;

  /// Per-row count of sub-tokens that hit the GloVe vocabulary.
  final Int32List vocabHits;

  /// Per-row nearest-well ORIGINAL index (stable across cache reloads)
  /// or [kEngramNoWell] for rows whose fit produced no well match.
  final Int32List wellIdx;

  /// Per-row raw RMS distance to the nearest well centroid.
  final Float64List wellRawDistance;

  /// Per-row mass-weighted distance (the value used for argmin).
  final Float64List wellWeightedDistance;

  /// Full well-name lookup table indexed by ORIGINAL (brain-side) well
  /// index. Lives on the table so callers don't need a reference to
  /// the brain to look up names. Small (~225 strings for Alexandria);
  /// stored once, shared across all row lookups.
  final List<String> wellNamesByOriginalIndex;

  /// True when no files were encoded (engram assets missing or every
  /// file failed to fit). Downstream consumers branch on this to fall
  /// back to the legacy 4-axis graph without an EN contribution.
  bool get isEmpty => n == 0;

  /// O(1) path → row id, or null if the file isn't encoded.
  int? rowOf(String path) => _pathToRow[path];

  /// O(1) well name at [row], or null if this row had no nearest well.
  String? wellOfRow(int row) {
    final wi = wellIdx[row];
    if (wi < 0) return null;
    return wellNamesByOriginalIndex[wi];
  }

  /// O(1) well name at [path], or null if the file isn't encoded or
  /// had no nearest well.
  String? wellOf(String path) {
    final r = _pathToRow[path];
    if (r == null) return null;
    return wellOfRow(r);
  }

  /// Raw distance to the row's nearest well, or null if the row has
  /// no well match. Used by callers that want to surface the distance
  /// metric alongside the well name.
  double? wellRawDistanceOfRow(int row) {
    if (wellIdx[row] < 0) return null;
    return wellRawDistance[row];
  }

  /// Reverse index cache: well's original index → list of row ids.
  /// Built on first access — muse typically hits many wells in a
  /// single brainstorm pass so the O(n) build amortises cleanly.
  Map<int, List<int>>? _rowsByWellIdxCache;

  /// Rows whose nearest well is [wellOriginalIndex], in row-id order.
  /// Returns `const []` for wells with no encoded files.
  List<int> rowsInWell(int wellOriginalIndex) {
    var cache = _rowsByWellIdxCache;
    if (cache == null) {
      cache = <int, List<int>>{};
      for (var row = 0; row < n; row++) {
        final wi = wellIdx[row];
        if (wi < 0) continue;
        (cache[wi] ??= <int>[]).add(row);
      }
      _rowsByWellIdxCache = cache;
    }
    return cache[wellOriginalIndex] ?? const [];
  }

  /// All rows in the table, for callers that want to iterate paths with
  /// their K-vectors (e.g. a muse KNN scan). The underlying list is
  /// already unmodifiable; exposed here for clarity at call sites.
  Iterable<String> get allPaths => paths;

  /// Empty table for the "no engram" path.
  factory EngramFileKTable.empty(int pairs) {
    return EngramFileKTable._(
      pairs: pairs,
      n: 0,
      paths: const [],
      pathToRow: const {},
      kRi: Float64x2List(0),
      meanRms: Float32List(0),
      vocabHits: Int32List(0),
      wellIdx: Int32List(0),
      wellRawDistance: Float64List(0),
      wellWeightedDistance: Float64List(0),
      wellNamesByOriginalIndex: const [],
    );
  }

  /// Build a table from a map of path → encoded K-vector. Typical
  /// caller is the resolver after merging cache hits and fresh
  /// parallel encodes. [wellNamesByOriginalIndex] is the brain's
  /// name table (copied into the result so the brain is no longer
  /// required for `wellOf` lookups).
  factory EngramFileKTable.fromMap({
    required int pairs,
    required Map<String, HunkKVector> encodings,
    required List<String> wellNamesByOriginalIndex,
  }) {
    final n = encodings.length;
    if (n == 0) return EngramFileKTable.empty(pairs);

    final paths = List<String>.filled(n, '', growable: false);
    final pathToRow = <String, int>{};
    final kRi = Float64x2List(n * pairs);
    final meanRms = Float32List(n);
    final vocabHits = Int32List(n);
    final wellIdx = Int32List(n)..fillRange(0, n, kEngramNoWell);
    final wellRawDistance = Float64List(n);
    final wellWeightedDistance = Float64List(n);

    var row = 0;
    for (final entry in encodings.entries) {
      final path = entry.key;
      final kv = entry.value;
      paths[row] = path;
      pathToRow[path] = row;

      // Interleave kv.kRe/kv.kIm into the Float64x2List: one vector
      // per pair, `.x = re`, `.y = im`. Per-element copy because the
      // source layout is two separate Float64Lists — no memcpy short-
      // cut exists for that→interleaved transition. The pair count
      // is small (~150) so this is a fraction of the time the old
      // setRange pair was spending on two larger copies, and this
      // happens once per encoded row at build time, not on the hot
      // query path.
      final base = row * pairs;
      final srcRe = kv.kRe;
      final srcIm = kv.kIm;
      for (var j = 0; j < pairs; j++) {
        kRi[base + j] = Float64x2(srcRe[j], srcIm[j]);
      }
      meanRms[row] = kv.meanRms;
      vocabHits[row] = kv.vocabHits;
      final w = kv.well;
      if (w != null) {
        wellIdx[row] = w.index;
        wellRawDistance[row] = w.rawDistance;
        wellWeightedDistance[row] = w.weightedDistance;
      }
      row++;
    }

    return EngramFileKTable._(
      pairs: pairs,
      n: n,
      paths: List<String>.unmodifiable(paths),
      pathToRow: pathToRow,
      kRi: kRi,
      meanRms: meanRms,
      vocabHits: vocabHits,
      wellIdx: wellIdx,
      wellRawDistance: wellRawDistance,
      wellWeightedDistance: wellWeightedDistance,
      wellNamesByOriginalIndex:
          List<String>.unmodifiable(wellNamesByOriginalIndex),
    );
  }
}
