// ═════════════════════════════════════════════════════════════════════════
// engram_brain.dart — Alexandria brain (wells + pairing) loaded at runtime.
//
// Reads the compact ENDB ("Engram Dart Brain") binary produced by the
// preprocessing script from alexandria.engram. Holds the reference
// pairing (permutation over dim dims into complex pairs) and every
// well's sum_K + count so centroids can be computed on demand.
//
// The public surface is intentionally thin:
//
//   EngramBrain.loadBytes(bytes) → parsed brain
//   brain.nearestWell(K_vector) → (well name, raw distance, index)
//   brain.wellCentroid(index)   → (Float64List re, Float64List im)
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
class EngramBrainWell {
  /// Well name as written (e.g. "computing", "well_42").
  final String name;

  /// Observation count. Used for log1p mass weighting in nearest-well.
  final int count;

  /// Precomputed log(1 + count). The nearest-well search divides the raw
  /// RMS distance by this — bigger wells pull harder. Computed once at
  /// load so the query path is pure arithmetic.
  final double logMass;

  /// Centroid K-vector in ℂ^P, stored SoA for fast cosine/RMS.
  /// Already divided by count (so these are means, not sums). Length P.
  final Float64List centroidRe;
  final Float64List centroidIm;

  const EngramBrainWell({
    required this.name,
    required this.count,
    required this.logMass,
    required this.centroidRe,
    required this.centroidIm,
  });
}

@immutable
class EngramWellMatch {
  /// Name of the nearest well.
  final String name;

  /// Index into [EngramBrain.wells]. Useful when callers want to walk
  /// back to the well object without a second map lookup.
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
class EngramBrain {
  EngramBrain._raw({
    required this.dim,
    required this.pairs,
    required this.pairing,
    required this.wells,
    required Int32List flatOrder,
    required Float64List flatCentroidRe,
    required Float64List flatCentroidIm,
    required Float64List invLogMass,
    required Float64List wellNorm,
    required List<String> wellNames,
  })  : _flatOrder = flatOrder,
        _flatCentroidRe = flatCentroidRe,
        _flatCentroidIm = flatCentroidIm,
        _invLogMass = invLogMass,
        _wellNorm = wellNorm,
        _wellNames = wellNames;

  /// Build the full set of nearest-well lookup tables once and hand
  /// them to the private constructor. Does the descending-logMass
  /// sort only once; every derived table threads through the same
  /// `flatOrder` permutation so they stay aligned.
  factory EngramBrain._build({
    required int dim,
    required int pairs,
    required Int32List pairing,
    required List<EngramBrainWell> wells,
  }) {
    final order = _buildFlatOrder(wells);
    final flatRe = _flatten(wells, pairs, order, realPart: true);
    final flatIm = _flatten(wells, pairs, order, realPart: false);
    return EngramBrain._raw(
      dim: dim,
      pairs: pairs,
      pairing: pairing,
      wells: wells,
      flatOrder: order,
      flatCentroidRe: flatRe,
      flatCentroidIm: flatIm,
      invLogMass: _invLogMasses(wells, order),
      wellNorm: _wellNorms(flatRe, flatIm, wells.length, pairs),
      wellNames: List<String>.unmodifiable([
        for (var i = 0; i < order.length; i++) wells[order[i]].name,
      ]),
    );
  }

  /// All well centroids' real parts in a single contiguous Float64List,
  /// row-major as `[well0.re, well1.re, ..., wellN.re]` each of length
  /// [pairs]. **Stored in DESCENDING logMass order** — the heaviest
  /// wells (most observation count, most likely to contain an
  /// arbitrary query's nearest match) come first. Combined with the
  /// triangle-inequality break in [nearestWell], the hot loop
  /// establishes a tight `bestWeighted` threshold within the first
  /// few wells and then prunes the remaining (mostly-tiny) wells on
  /// the first 16-pair partial-distance check.
  ///
  /// A wrapped-well's centroid lives at offset `sortPos * pairs`.
  /// [_flatOrder] maps `sortPos → original index` so we can hand
  /// callers back the original-index (stable across reloads) while
  /// visiting wells in mass-descending order.
  final Float64List _flatCentroidRe;
  final Float64List _flatCentroidIm;

  /// Permutation: `_flatOrder[sortPos]` is the well's index in the
  /// original [wells] list. Used at the end of [nearestWell] to
  /// translate the winner's sorted position back to its stable
  /// original index so serialised `EngramWellMatch.index` values
  /// survive cache reloads.
  final Int32List _flatOrder;

  /// Precomputed `1.0 / log1p(count)` per well, aligned with
  /// [_flatCentroidRe] (sorted order). The hot loop multiplies
  /// instead of dividing — saves ~5 cycles per well per query.
  /// Wells with zero count get a sentinel zero that rejects them
  /// naturally via the min tracker.
  final Float64List _invLogMass;

  /// Precomputed `||c_w||` (euclidean norm, not squared) for every
  /// well centroid. Enables a Cauchy-Schwarz lower bound on the
  /// distance from any query: `||c-k||² ≥ (||c|| − ||k||)²`. Wells
  /// whose norm differs from the query's norm by more than the
  /// current best distance threshold get eliminated with O(1) math —
  /// no pair loop, no cache touches beyond one f64 load.
  final Float64List _wellNorm;

  /// Unmodifiable list of well names aligned with [_flatCentroidRe]
  /// indexing (sorted order). Kept separately so the hot path doesn't
  /// read through the wells List<Object> (one dereference per well
  /// → cache stall).
  final List<String> _wellNames;

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

  /// All wells in declaration order (sorted alphabetically by the encoder).
  final List<EngramBrainWell> wells;

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

    // Wells
    final wells = <EngramBrainWell>[];
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

      // sum_K: complex128[pairs]  (re f64 + im f64 interleaved)
      final centroidRe = Float64List(pairs);
      final centroidIm = Float64List(pairs);
      final invCount = count > 0 ? 1.0 / count : 1.0;
      for (var p = 0; p < pairs; p++) {
        final re = bd.getFloat64(off, Endian.little); off += 8;
        final im = bd.getFloat64(off, Endian.little); off += 8;
        centroidRe[p] = re * invCount;
        centroidIm[p] = im * invCount;
      }

      wells.add(EngramBrainWell(
        name: name,
        count: count,
        logMass: math.log(1.0 + count),
        centroidRe: centroidRe,
        centroidIm: centroidIm,
      ));
    }

    return EngramBrain._build(
      dim: dim,
      pairs: pairs,
      pairing: pairing,
      wells: wells,
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
  ///   • Sweeps every well's centroid via the flattened
  ///     [_flatCentroidRe] / [_flatCentroidIm] arrays — one linear
  ///     scan, no per-well dereference, cache-friendly.
  ///   • Runs a squared-distance accumulator (no sqrt in the hot
  ///     loop) with the argmin tracked in squared weighted units,
  ///     then takes the single sqrt on the winner.
  ///   • Early-exits the inner pair loop as soon as the partial
  ///     accumulator already exceeds the best seen — the "triangle
  ///     inequality break" that collapses the average work to
  ///     roughly O(√pairs) once a plausible winner is found.
  ///
  /// `kRe` / `kIm` must have length == [pairs].
  EngramWellMatch? nearestWell(Float64List kRe, Float64List kIm) {
    final n = wells.length;
    if (n == 0) return null;
    final p = pairs;
    if (kRe.length != p || kIm.length != p) return null;

    // Track the argmin in squared-weighted-distance space so the hot
    // loop never calls sqrt. Final conversion happens once at the end.
    //   weighted_squared = (acc / pairs) / logMass²  (we multiply by invLogMass²)
    // Holds the best seen so the inner triangle-break can compare
    // against this threshold.
    final cRe = _flatCentroidRe;
    final cIm = _flatCentroidIm;
    final invLM = _invLogMass;
    final wNorm = _wellNorm;
    final invPairs = 1.0 / p;

    // One-time query norm. Cauchy-Schwarz lower-bounds the distance
    // to any well by `||c_w|| − ||k||`, so this is the only piece
    // that depends on the observation — compute once, reuse for
    // every well's gate test.
    double kNormSq = 0.0;
    for (var j = 0; j < p; j++) {
      kNormSq += kRe[j] * kRe[j] + kIm[j] * kIm[j];
    }
    final kNorm = math.sqrt(kNormSq);

    var bestIdx = -1;
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
      //
      // First iteration skips the gate (bestWeightedSq = ∞ passes
      // everything). By the time we reach well N, the mass-sorted
      // heavy wells have already established a tight threshold that
      // CS applies to kill the remaining light wells.
      if (bestWeightedSq.isFinite) {
        final normGap = wNorm[w] - kNorm;
        final lowerBoundWSq =
            normGap * normGap * invPairs * invLogMass * invLogMass;
        if (lowerBoundWSq >= bestWeightedSq) continue;
      }

      final base = w * p;
      // Corresponding threshold on the raw accumulator that would
      // already lose to the best seen. Once `acc * invPairs *
      // invLogMass² > bestWeightedSq`, this well cannot win — break.
      final accBreak = bestWeightedSq.isFinite
          ? bestWeightedSq / (invPairs * invLogMass * invLogMass)
          : double.infinity;
      double acc = 0.0;
      // Triangle-break pair loop. We check every 16 pairs to keep the
      // inner arithmetic at unit stride — more granular checks would
      // churn branch prediction; less granular would waste work after
      // the accumulator passes the threshold.
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
        bestIdx = w;
      }
    }

    if (bestIdx < 0) return null;
    // Translate the sorted-position winner back to its stable index
    // in the original `wells` list so serialised EngramWellMatch
    // values survive across cache reloads (a re-sort with the same
    // data gives the same ordering, but being explicit here keeps
    // the contract simple for callers).
    final originalIdx = _flatOrder[bestIdx];
    return EngramWellMatch(
      name: _wellNames[bestIdx],
      index: originalIdx,
      rawDistance: math.sqrt(bestRawSq),
      weightedDistance: math.sqrt(bestWeightedSq),
    );
  }

  // ── flattening helpers, called once at construction ────────────

  /// Derive a `sortPos → originalIndex` permutation that orders wells
  /// by DESCENDING `logMass` (equivalently, descending count). Visiting
  /// the heaviest wells first in [nearestWell] tightens `bestWeighted`
  /// fast, maximising the triangle-inequality break's pruning on the
  /// remaining wells.
  static Int32List _buildFlatOrder(List<EngramBrainWell> wells) {
    final n = wells.length;
    final order = Int32List(n);
    for (var i = 0; i < n; i++) {
      order[i] = i;
    }
    // Stable-ish sort: descending by logMass, tiebreak by original
    // index so ordering is deterministic across builds.
    final orderList = order.toList()
      ..sort((a, b) {
        final cmp = wells[b].logMass.compareTo(wells[a].logMass);
        if (cmp != 0) return cmp;
        return a.compareTo(b);
      });
    for (var i = 0; i < n; i++) {
      order[i] = orderList[i];
    }
    return order;
  }

  /// Pack every well's centroid Real OR Imaginary component into one
  /// contiguous row-major Float64List of length `wells.length * pairs`,
  /// visited in the `order` permutation (descending-logMass from
  /// [_buildFlatOrder]). Uses [Float64List.setRange] which the Dart
  /// VM lowers to a typed block copy — no per-element scalar loop.
  static Float64List _flatten(
      List<EngramBrainWell> wells, int pairs, Int32List order,
      {required bool realPart}) {
    final out = Float64List(wells.length * pairs);
    for (var sortPos = 0; sortPos < wells.length; sortPos++) {
      final w = order[sortPos];
      final src = realPart ? wells[w].centroidRe : wells[w].centroidIm;
      out.setRange(sortPos * pairs, (sortPos + 1) * pairs, src);
    }
    return out;
  }

  /// Precompute `1.0 / log1p(count)` per well, in sorted order so the
  /// value at index `sortPos` aligns with the centroid at the same
  /// slot. Zero-count wells get a sentinel zero; [nearestWell] skips
  /// any well with `invLogMass == 0.0` before evaluating distances.
  static Float64List _invLogMasses(
      List<EngramBrainWell> wells, Int32List order) {
    final out = Float64List(wells.length);
    for (var sortPos = 0; sortPos < wells.length; sortPos++) {
      final lm = wells[order[sortPos]].logMass;
      out[sortPos] = lm > 0 ? 1.0 / lm : 0.0;
    }
    return out;
  }

  /// Compute `||c_w||` (non-squared euclidean norm) per well, over
  /// the already-flattened real + imaginary arrays. One pass over the
  /// centroid data — cheap since we touched those bytes anyway to
  /// build the flat centroids. The Cauchy-Schwarz gate in
  /// [nearestWell] uses these to reject wells in O(1) when their
  /// norm is so far from the query's that the lower-bound distance
  /// can't beat the current argmin.
  static Float64List _wellNorms(
      Float64List flatRe, Float64List flatIm, int nWells, int pairs) {
    final out = Float64List(nWells);
    for (var w = 0; w < nWells; w++) {
      final base = w * pairs;
      double accSq = 0.0;
      for (var j = 0; j < pairs; j++) {
        final re = flatRe[base + j];
        final im = flatIm[base + j];
        accSq += re * re + im * im;
      }
      out[w] = math.sqrt(accSq);
    }
    return out;
  }

  /// Profile: raw distance to every well, keyed by name. Cheap but
  /// O(wells × pairs) — callers should reuse results for a batch of
  /// hunks rather than re-profiling per comparison.
  Map<String, double> wellProfile(Float64List kRe, Float64List kIm) {
    if (kRe.length != pairs || kIm.length != pairs) return const {};
    final result = <String, double>{};
    for (final well in wells) {
      double acc = 0.0;
      final cRe = well.centroidRe;
      final cIm = well.centroidIm;
      for (var p = 0; p < pairs; p++) {
        final dre = cRe[p] - kRe[p];
        final dim_ = cIm[p] - kIm[p];
        acc += dre * dre + dim_ * dim_;
      }
      final d = math.sqrt(acc / pairs);
      if (d.isFinite) result[well.name] = d;
    }
    return result;
  }
}
