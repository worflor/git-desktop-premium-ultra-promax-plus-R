// ═════════════════════════════════════════════════════════════════════════
// engram_brain.dart — Alexandria brain (wells + pairing) loaded at runtime.
//
// Reads the compact ENDB ("Engram Dart Brain") binary produced by the
// preprocessing script from alexandria.engram. Holds the reference
// pairing (permutation over dim dims into complex pairs) and every
// well's sum_K + count so centroids can be computed on demand.
//
// ─── Storage geometry ──────────────────────────────────────────────────
//
// The brain's hot path is `nearestWell`, called once per file during
// index builds (typically 10k+ calls per repo switch). It needs:
//   • Contiguous sweep over all wells' centroid pairs
//   • Per-well precomputed `log(1 + count)` for mass-weighted distance
//   • Per-well precomputed `||c||` for the Cauchy-Schwarz gate
//
// Every one of those wants a flat typed array indexed by integer, not
// an object graph with one heap allocation per well. We store
// accordingly — this file owns the Hilbert-space-native layout.
//
// All per-well state lives in flat Float64List/Int32List/List<String>
// arrays indexed by `sortPos`, the well's position in descending
// logMass order. `_flatOrder[sortPos] → originalIdx` preserves the
// stable on-disk identity so `EngramWellMatch.index` survives cache
// reloads.
//
// Callers that want to walk wells externally (tests, diagnostics) use
// the `wellCount` + `wellName(i)` + `wellObservationCount(i)` +
// `wellCentroidReView(i)` / `wellCentroidImView(i)` accessors, which
// take an ORIGINAL index and read through the `_originalToSortPos`
// inverse permutation.
//
// The public surface is intentionally thin:
//
//   EngramBrain.loadBytes(bytes) → parsed brain
//   brain.nearestWell(K_vector) → (well name, raw distance, index)
//   brain.wellCount / brain.wellName(i) / brain.wellCentroidReView(i)
//
// The brain is stateless after load: no absorption, no dream buffer, no
// training. It's a semantic lookup table for the hunk encoder.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// File magic: "ENDB" — matches the preprocessing script's header.
const _kEndbMagic = [0x45, 0x4E, 0x44, 0x42];

/// Supported format version. Bumps if the binary layout changes.
const int _kEndbVersion = 1;

@immutable
class EngramWellMatch {
  /// Name of the nearest well.
  final String name;

  /// Index into the brain's wells list in ORIGINAL (on-disk) order.
  /// Stable across cache reloads; does not shift when the internal
  /// nearest-well search reorders by mass.
  final int index;

  /// Raw RMS distance (not mass-weighted) — matches Engram's Python
  /// `nearest_well` return which reports raw distance at the argmin of
  /// the weighted distance.
  final double rawDistance;

  /// Mass-weighted distance that was used for the argmin.
  final double weightedDistance;

  const EngramWellMatch({
    required this.name,
    required this.index,
    required this.rawDistance,
    required this.weightedDistance,
  });
}

/// Snapshot of Alexandria's learned structure: reference pairing + every
/// well's centroid + count. Immutable. Safe to share across isolates.
///
/// All per-well data is stored in flat typed arrays (no per-well object).
/// Construct via [EngramBrain.loadBytes]; access via the public
/// `wellCount` / `wellName(i)` / `wellCentroidReView(i)` accessors.
class EngramBrain {
  EngramBrain._({
    required this.dim,
    required this.pairs,
    required this.pairing,
    required this.wellCount,
    required Int32List flatOrder,
    required Int32List originalToSortPos,
    required Float64List flatCentroidRe,
    required Float64List flatCentroidIm,
    required Int32List wellCounts,
    required Float64List invLogMass,
    required Float64List wellNorm,
    required List<String> wellNamesSorted,
    required List<String> wellNamesOriginal,
  })  : _flatOrder = flatOrder,
        _originalToSortPos = originalToSortPos,
        _flatCentroidRe = flatCentroidRe,
        _flatCentroidIm = flatCentroidIm,
        _wellCountsSorted = wellCounts,
        _invLogMass = invLogMass,
        _wellNorm = wellNorm,
        _wellNamesSorted = wellNamesSorted,
        _wellNamesOriginal = wellNamesOriginal;

  /// Embedding dimension (e.g. 300 for GloVe).
  final int dim;

  /// Number of complex pairs (dim / 2 for the trained Alexandria).
  final int pairs;

  /// Permutation over the dim dims — `pairing[2k]` and `pairing[2k+1]`
  /// are the original dim indices that become pair k's re/imag components.
  /// Stored as Int32List because Dart's typed lists don't include Int16List
  /// with usable sign semantics everywhere — widening to int32 once at
  /// load is trivial.
  final Int32List pairing;

  /// Total number of wells the brain holds.
  final int wellCount;

  // ── Hot-path (nearest-well) flat arrays in DESCENDING logMass order ──

  /// Permutation: `_flatOrder[sortPos]` is the well's ORIGINAL index.
  /// Used at the end of [nearestWell] to translate the winner's sorted
  /// position back to its stable original index so serialised
  /// EngramWellMatch values survive across cache reloads.
  final Int32List _flatOrder;

  /// Inverse permutation: `_originalToSortPos[originalIdx]` is the
  /// well's position in the sorted flat arrays. Used by the public
  /// accessors (wellName, wellCentroidReView, etc.) when callers
  /// address wells by their on-disk (original) index.
  final Int32List _originalToSortPos;

  /// All well centroids' real parts in a single contiguous Float64List,
  /// row-major as `[sortPos0.re, sortPos1.re, ..., sortPosN.re]` each
  /// of length [pairs]. **Stored in DESCENDING logMass order** — the
  /// heaviest wells come first. Combined with the triangle-inequality
  /// break in [nearestWell], the hot loop establishes a tight
  /// `bestWeighted` threshold within the first few wells and then
  /// prunes the remaining wells on the first 16-pair partial-distance
  /// check.
  final Float64List _flatCentroidRe;
  final Float64List _flatCentroidIm;

  /// Per-well observation count, in sorted order.
  final Int32List _wellCountsSorted;

  /// Precomputed `1.0 / log1p(count)` per well, aligned with
  /// [_flatCentroidRe] (sorted order). The hot loop multiplies
  /// instead of dividing — saves ~5 cycles per well per query.
  /// Wells with zero count get a sentinel zero; [nearestWell] skips
  /// any well with `invLogMass == 0.0` before evaluating distances.
  final Float64List _invLogMass;

  /// Precomputed `||c_w||` (euclidean norm, not squared) for every
  /// well centroid. Enables a Cauchy-Schwarz lower bound on the
  /// distance from any query.
  final Float64List _wellNorm;

  /// Sorted-order well names, aligned with the flat centroid arrays.
  /// Nearest-well returns from here via its sortPos.
  final List<String> _wellNamesSorted;

  /// Original-order well names. Public accessors like [wellName] read
  /// from here so callers addressing wells by on-disk index get stable
  /// identities.
  final List<String> _wellNamesOriginal;

  // ── Public accessors for external callers (tests, diagnostics) ──

  /// Well name at its ORIGINAL (on-disk) index.
  String wellName(int originalIdx) => _wellNamesOriginal[originalIdx];

  /// Observation count at the well's ORIGINAL index.
  int wellObservationCount(int originalIdx) =>
      _wellCountsSorted[_originalToSortPos[originalIdx]];

  /// Zero-copy view into the sorted centroid array for the well at
  /// [originalIdx]. Read-only — mutating the returned view would
  /// corrupt every future nearest-well query. Length == [pairs].
  Float64List wellCentroidReView(int originalIdx) {
    final sortPos = _originalToSortPos[originalIdx];
    final base = sortPos * pairs;
    return Float64List.sublistView(_flatCentroidRe, base, base + pairs);
  }

  /// Zero-copy view into the sorted centroid array (imaginary part).
  Float64List wellCentroidImView(int originalIdx) {
    final sortPos = _originalToSortPos[originalIdx];
    final base = sortPos * pairs;
    return Float64List.sublistView(_flatCentroidIm, base, base + pairs);
  }

  /// All well names in original order. Exposed as a fixed-length list
  /// view so downstream column-stores (like `EngramFileKTable`) can
  /// retain a reference without depending on the brain itself.
  List<String> get wellNamesByOriginalIndex =>
      List<String>.unmodifiable(_wellNamesOriginal);

  /// Deserialize a brain from its compact ENDB binary form. Throws
  /// [FormatException] on magic / version / bounds mismatches — callers
  /// at the singleton layer should catch and degrade silently.
  ///
  /// Binary layout is little-endian throughout, matching the byte order
  /// emitted by `tools/export_engram_assets.py` (which uses Python's
  /// `struct.pack('<...')` and numpy's default little-endian dtypes).
  /// On the unlikely big-endian Dart host this parser would still
  /// produce numerically-valid output because we use ByteData with an
  /// explicit Endian.little, not raw byte aliasing.
  factory EngramBrain.loadBytes(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    var off = 0;

    // Header
    if (bytes.length < 20) {
      throw const FormatException('engram: binary too small');
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _kEndbMagic[i]) {
        throw const FormatException('engram: bad magic (expected ENDB)');
      }
    }
    off = 4;
    final version = bd.getUint32(off, Endian.little); off += 4;
    if (version != _kEndbVersion) {
      throw FormatException('engram: unsupported version $version');
    }
    final dim = bd.getUint32(off, Endian.little); off += 4;
    final pairs = bd.getUint32(off, Endian.little); off += 4;
    final nWells = bd.getUint32(off, Endian.little); off += 4;
    if (dim.isOdd || dim ~/ 2 != pairs) {
      throw FormatException('engram: dim/pairs mismatch (dim=$dim, pairs=$pairs)');
    }

    // Pairing: int16[dim]
    final pairing = Int32List(dim);
    for (var i = 0; i < dim; i++) {
      pairing[i] = bd.getInt16(off, Endian.little);
      off += 2;
      if (pairing[i] < 0 || pairing[i] >= dim) {
        throw FormatException('engram: pairing index out of range at $i');
      }
    }

    // Parse wells directly into per-original-index arrays to avoid the
    // intermediate object list that used to live here. We still need
    // to sort by descending logMass for the hot path, so we track
    // per-well metadata in original order here and permute into
    // flat-sorted storage below.
    final namesOriginal = List<String>.filled(nWells, '', growable: false);
    final countsOriginal = Int32List(nWells);
    final logMassOriginal = Float64List(nWells);
    // Per-well centroids in original-order flat storage. We could
    // build the sorted version directly in a single pass if we
    // pre-computed the sort order, but we don't know logMass until
    // we've read every well's count — so two passes here.
    final centroidReOriginal = Float64List(nWells * pairs);
    final centroidImOriginal = Float64List(nWells * pairs);

    for (var w = 0; w < nWells; w++) {
      if (off + 2 > bytes.length) {
        throw const FormatException('engram: truncated at well header');
      }
      final nameLen = bd.getUint16(off, Endian.little); off += 2;
      if (off + nameLen + 4 + pairs * 16 > bytes.length) {
        throw FormatException('engram: well #$w truncated');
      }
      final name = utf8.decode(bytes.sublist(off, off + nameLen));
      off += nameLen;
      final count = bd.getUint32(off, Endian.little); off += 4;

      namesOriginal[w] = name;
      countsOriginal[w] = count;
      logMassOriginal[w] = math.log(1.0 + count);

      // sum_K: complex128[pairs]  (re f64 + im f64 interleaved).
      // Divide by count on read to store centroids, not sums.
      final invCount = count > 0 ? 1.0 / count : 1.0;
      final base = w * pairs;
      for (var p = 0; p < pairs; p++) {
        centroidReOriginal[base + p] =
            bd.getFloat64(off, Endian.little) * invCount;
        off += 8;
        centroidImOriginal[base + p] =
            bd.getFloat64(off, Endian.little) * invCount;
        off += 8;
      }
    }

    // Derive sort order: descending by logMass, tiebreak by original
    // index so ordering is deterministic across builds.
    final order = Int32List(nWells);
    for (var i = 0; i < nWells; i++) {
      order[i] = i;
    }
    final orderList = order.toList()
      ..sort((a, b) {
        final cmp = logMassOriginal[b].compareTo(logMassOriginal[a]);
        if (cmp != 0) return cmp;
        return a.compareTo(b);
      });
    for (var i = 0; i < nWells; i++) {
      order[i] = orderList[i];
    }

    final originalToSortPos = Int32List(nWells);
    for (var sortPos = 0; sortPos < nWells; sortPos++) {
      originalToSortPos[order[sortPos]] = sortPos;
    }

    // Permute into sorted-order flat arrays.
    final flatCentroidRe = Float64List(nWells * pairs);
    final flatCentroidIm = Float64List(nWells * pairs);
    final wellCountsSorted = Int32List(nWells);
    final invLogMass = Float64List(nWells);
    final wellNorm = Float64List(nWells);
    final wellNamesSorted = List<String>.filled(nWells, '', growable: false);
    for (var sortPos = 0; sortPos < nWells; sortPos++) {
      final orig = order[sortPos];
      final srcBase = orig * pairs;
      final dstBase = sortPos * pairs;
      flatCentroidRe.setRange(dstBase, dstBase + pairs, centroidReOriginal,
          srcBase);
      flatCentroidIm.setRange(dstBase, dstBase + pairs, centroidImOriginal,
          srcBase);
      wellCountsSorted[sortPos] = countsOriginal[orig];
      final lm = logMassOriginal[orig];
      invLogMass[sortPos] = lm > 0 ? 1.0 / lm : 0.0;
      wellNamesSorted[sortPos] = namesOriginal[orig];

      // Norm: sqrt(Σ re² + im²). One pass, no intermediate.
      double accSq = 0.0;
      for (var p = 0; p < pairs; p++) {
        final re = flatCentroidRe[dstBase + p];
        final im = flatCentroidIm[dstBase + p];
        accSq += re * re + im * im;
      }
      wellNorm[sortPos] = math.sqrt(accSq);
    }

    return EngramBrain._(
      dim: dim,
      pairs: pairs,
      pairing: pairing,
      wellCount: nWells,
      flatOrder: order,
      originalToSortPos: originalToSortPos,
      flatCentroidRe: flatCentroidRe,
      flatCentroidIm: flatCentroidIm,
      wellCounts: wellCountsSorted,
      invLogMass: invLogMass,
      wellNorm: wellNorm,
      wellNamesSorted: List<String>.unmodifiable(wellNamesSorted),
      wellNamesOriginal: List<String>.unmodifiable(namesOriginal),
    );
  }

  /// Find the well closest to an observation K-vector.
  ///
  /// Matches Python `nearest_well` exactly:
  /// - compute raw RMS distance to every well centroid
  /// - mass-weight by dividing by log(1+count)
  /// - return the well at argmin(weighted), but report *raw* distance.
  ///
  /// Performance shape (called once per hunk, also once per file in
  /// the engram file index so tens of thousands of times per repo
  /// build):
  ///
  ///   • One-time query norm compute for the Cauchy-Schwarz gate
  ///   • Sweep every well's centroid via flat arrays
  ///   • Three-layer pruning: sort-by-mass + CS gate (O(1) per well)
  ///     + triangle-inequality break inside the pair loop
  ///   • Squared-distance accumulator (no sqrt in the hot loop);
  ///     one sqrt at the end on the winner
  ///
  /// `kRe` / `kIm` must have length == [pairs].
  EngramWellMatch? nearestWell(Float64List kRe, Float64List kIm) {
    final n = wellCount;
    if (n == 0) return null;
    final p = pairs;
    if (kRe.length != p || kIm.length != p) return null;

    final cRe = _flatCentroidRe;
    final cIm = _flatCentroidIm;
    final invLM = _invLogMass;
    final wNorm = _wellNorm;
    final invPairs = 1.0 / p;

    // One-time query norm for the CS gate.
    double kNormSq = 0.0;
    for (var j = 0; j < p; j++) {
      kNormSq += kRe[j] * kRe[j] + kIm[j] * kIm[j];
    }
    final kNorm = math.sqrt(kNormSq);

    var bestSortPos = -1;
    var bestWeightedSq = double.infinity;
    double bestRawSq = double.infinity;

    for (var w = 0; w < n; w++) {
      final invLogMass = invLM[w];

      // Zero-count wells have invLogMass = 0, which collapses weightedSq
      // to 0 regardless of distance — an instant false win. Skip them;
      // they carry no observations and can't be a meaningful match.
      if (invLogMass == 0.0) continue;

      // ── Cauchy-Schwarz gate ─────────────────────────────────────
      //
      // `||c - k||² ≥ (||c|| − ||k||)²` by CS, so the weighted-square
      // distance is at least `(||c|| − ||k||)² / pairs / logMass²`.
      // If that lower bound already exceeds the best weighted-square
      // we've seen, this well can't win — skip the pair loop
      // entirely. O(1) per well, gated by two floats plus a compare.
      if (bestWeightedSq.isFinite) {
        final normGap = wNorm[w] - kNorm;
        final lowerBoundWSq =
            normGap * normGap * invPairs * invLogMass * invLogMass;
        if (lowerBoundWSq >= bestWeightedSq) continue;
      }

      final base = w * p;
      // Triangle-inequality break threshold on the raw accumulator.
      final accBreak = bestWeightedSq.isFinite
          ? bestWeightedSq / (invPairs * invLogMass * invLogMass)
          : double.infinity;
      double acc = 0.0;
      for (var j = 0; j < p; j++) {
        final dre = cRe[base + j] - kRe[j];
        final dim_ = cIm[base + j] - kIm[j];
        acc += dre * dre + dim_ * dim_;
        if ((j & 15) == 15 && acc >= accBreak) {
          acc = double.infinity;
          break;
        }
      }
      if (!acc.isFinite) continue;
      final weightedSq = acc * invPairs * invLogMass * invLogMass;
      if (weightedSq < bestWeightedSq) {
        bestWeightedSq = weightedSq;
        bestRawSq = acc * invPairs;
        bestSortPos = w;
      }
    }

    if (bestSortPos < 0) return null;
    final originalIdx = _flatOrder[bestSortPos];
    return EngramWellMatch(
      name: _wellNamesSorted[bestSortPos],
      index: originalIdx,
      rawDistance: math.sqrt(bestRawSq),
      weightedDistance: math.sqrt(bestWeightedSq),
    );
  }

  /// Profile: raw distance to every well, keyed by name. Cheap but
  /// O(wells × pairs) — callers should reuse results for a batch of
  /// hunks rather than re-profiling per comparison.
  Map<String, double> wellProfile(Float64List kRe, Float64List kIm) {
    if (kRe.length != pairs || kIm.length != pairs) return const {};
    final result = <String, double>{};
    final n = wellCount;
    for (var w = 0; w < n; w++) {
      final base = w * pairs;
      double acc = 0.0;
      for (var p = 0; p < pairs; p++) {
        final dre = _flatCentroidRe[base + p] - kRe[p];
        final dim_ = _flatCentroidIm[base + p] - kIm[p];
        acc += dre * dre + dim_ * dim_;
      }
      final d = math.sqrt(acc / pairs);
      if (d.isFinite) result[_wellNamesSorted[w]] = d;
    }
    return result;
  }
}
