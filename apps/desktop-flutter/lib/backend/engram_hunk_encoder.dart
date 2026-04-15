// engram_hunk_encoder.dart — encode hunks into K-space vectors.
//
// Pipeline:
//   List<String> raw tokens    (identifiers from hunk change lines)
//   → splitIdentifier          (camelCase → sub-tokens)
//   → GloVe lookup per sub-token  (drops OOV)
//   → [T, 300] float matrix
//   → reference_pairing        (pair dims → complex)
//   → [T, 150] complex trajectory
//   → fitAllComplex            (AR(2) per pair)
//   → K[150] complex vector + optional nearest well
//
// Used by logos_hunks.dart as an input to the H_sym axis (blended with
// the existing Jaccard signal) and as a feature label in the prompt
// bundle that ai.dart ships to the LLM.
//
// The encoder is cheap when the brain+glove are loaded (~10μs per hunk
// for typical token counts). It's designed to be called inside the
// existing logos diffusion isolate, not on the UI thread.

import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'engram_brain.dart';
import 'engram_complex.dart';
import 'engram_glove.dart';
import 'engram_tokenizer.dart';

/// Cap on how many in-vocab sub-tokens we'll feed into a single AR(2)
/// fit. Beyond this the eigenvalue centroid is saturated — more samples
/// barely move the K-vector. Fits comfortably in L1 cache (128 tokens
/// × 300 dims × 8 bytes = 300KB sized buffer; cap is chosen so the
/// working set stays friendly even on older hardware with 256KB L2).
const int _kMaxTrajectoryTokens = 128;

/// One hunk's K-space signature. `kRe` and `kIm` are length `brain.pairs`
/// (150 for the trained Alexandria). [well] is the nearest well match
/// (null when the brain has zero wells or the fit degenerated).
@immutable
class HunkKVector {
  final Float64List kRe;
  final Float64List kIm;

  /// Mean per-pair RMS — a rough "signal quality" read. High RMS means
  /// the AR(2) couldn't explain the trajectory (short sequence, wild
  /// jumps); callers can fall back to Jaccard for those hunks.
  final double meanRms;

  /// How many sub-tokens hit the GloVe vocabulary (OOV tokens drop out
  /// of the trajectory). Used for gating — very short effective
  /// trajectories produce noisy K vectors.
  final int vocabHits;

  final EngramWellMatch? well;

  const HunkKVector({
    required this.kRe,
    required this.kIm,
    required this.meanRms,
    required this.vocabHits,
    required this.well,
  });
}

class EngramHunkEncoder {
  EngramHunkEncoder({required this.brain, required this.glove})
      : assert(brain.dim == glove.dim,
            'brain and glove must share embedding dim (got ${brain.dim} vs ${glove.dim})'),
        _scratch = EngramComplexScratch(brain.pairs),
        _trajectoryReBuf = Float64List(_kMaxTrajectoryTokens * brain.pairs),
        _trajectoryImBuf = Float64List(_kMaxTrajectoryTokens * brain.pairs);

  final EngramBrain brain;
  final EngramGlove glove;

  /// Reusable AR(2) accumulator scratch. One allocation for the life
  /// of the encoder; every [encode] call calls `_scratch.reset()` and
  /// then passes it into [fitAllComplex]. Eliminates the 9 × pairs ×
  /// 8 bytes of per-hunk GC churn.
  final EngramComplexScratch _scratch;

  /// Reusable complex trajectory scratch buffers. Sized for the max
  /// number of sub-tokens we'll admit into a single encode call. The
  /// old design also carried a [T, dim] real buffer (`_trajectoryBuf`)
  /// because the reference pairing was applied at encode time —
  /// scatter-gather from [T, dim] into [T, pairs] re/im pairs.
  /// With the pairing pre-baked into the GloVe storage at load, the
  /// encode path writes directly into [_trajectoryReBuf]/[_trajectoryImBuf]
  /// via [EngramGlove.fillPairedRow], which does unit-stride reads on
  /// the already-permuted int16 vectors. The intermediate [T, dim]
  /// buffer is gone entirely — we saved a full [T, dim] Float64List
  /// AND the scatter-gather pass that used to write it.
  final Float64List _trajectoryReBuf;
  final Float64List _trajectoryImBuf;

  int get dim => brain.dim;
  int get pairs => brain.pairs;

  /// Encode one hunk given its bag of raw identifier tokens (as extracted
  /// by logos_hunks.dart's existing tokenizer). Returns null if the hunk
  /// has too few GloVe-hittable sub-tokens to fit an AR(2) model.
  HunkKVector? encode(Iterable<String> rawTokens) {
    // 1) Split identifiers and drop OOV in one pass.
    //    We dedupe duplicates up to a cap: a diff with the same variable
    //    name 20 times shouldn't stack 20 identical observations (the
    //    AR(2) fit on a constant sequence is degenerate and hits the
    //    linear fallback).
    //
    //    Cap is [engramComplexMinSamples] — i.e. the exact minimum
    //    number of observations an AR(2) fit needs. A single repeated
    //    token contributes enough "row" samples to let the mixer solve
    //    its normal equations once, but not so many that it flattens
    //    the trajectory into a constant (which would force the ridge-
    //    regularised Cramer solver into its linear fallback). Derived,
    //    not picked.
    final seen = <String, int>{};
    final keptIndices = <int>[]; // GloVe row indices
    final tokens = expandIdentifiers(rawTokens);
    for (final sub in tokens) {
      final idx = glove.tokenIndex[sub];
      if (idx == null) continue;
      final count = seen[sub] ?? 0;
      if (count >= engramComplexMinSamples) continue;
      seen[sub] = count + 1;
      keptIndices.add(idx);
    }
    final t = keptIndices.length;
    if (t < engramComplexMinSamples) return null;
    // Cap the effective trajectory length at the scratch buffer size.
    // The hot path never re-allocates; any tokens past the cap simply
    // don't contribute more observations to the AR(2) fit.
    final tEff = t > _kMaxTrajectoryTokens ? _kMaxTrajectoryTokens : t;

    // 2+3) Fill the complex trajectory re/im scratch directly from
    //    GloVe via `fillPairedRow`, which fuses the int16 dequant,
    //    the reference-pairing gather, and the re/im split into a
    //    single pass. The old pipeline was three stages: fillRow
    //    into a [T, dim] scratch, then applyPairingToComplex into
    //    [T, pairs] re/im. That intermediate buffer is gone, and
    //    the [T, dim] pass with it — for a 50-token hunk that's
    //    15,000 fewer loads and stores on this path per encode.
    final p = pairs;
    final pairing = brain.pairing;
    for (var i = 0; i < tEff; i++) {
      glove.fillPairedRow(
        keptIndices[i],
        pairing,
        _trajectoryReBuf,
        _trajectoryImBuf,
        i * p,
        p,
      );
    }

    // 4) Fit AR(2) per pair — reusing the accumulator scratch so the
    //    only per-call allocations are the 4 output arrays (K/G re/im)
    //    and the pair RMS, which the returned HunkKVector owns.
    _scratch.reset();
    final fit = fitAllComplex(
      zRe: _trajectoryReBuf,
      zIm: _trajectoryImBuf,
      t: tEff,
      p: pairs,
      scratch: _scratch,
    );
    if (!fit.anyValid) return null;

    // 5) Nearest well lookup (cheap — O(n_wells × pairs)).
    final match = brain.nearestWell(fit.kRe, fit.kIm);

    return HunkKVector(
      kRe: fit.kRe,
      kIm: fit.kIm,
      meanRms: fit.meanRms,
      vocabHits: t,
      well: match,
    );
  }

  /// Batch-encode a list of token bags into K-vectors. Preserves input
  /// order. Entries that fail the minimum-samples gate are emitted as
  /// nulls so callers can align indices with the original hunk list.
  List<HunkKVector?> encodeAll(List<Iterable<String>> perHunkTokens) {
    final out = List<HunkKVector?>.filled(perHunkTokens.length, null);
    for (var i = 0; i < perHunkTokens.length; i++) {
      out[i] = encode(perHunkTokens[i]);
    }
    return out;
  }

  /// Cosine similarity between two hunk K-vectors in ℝ^(2P). Returns 0
  /// if either side is null or has a zero-norm K vector.
  static double cosine(HunkKVector? a, HunkKVector? b) {
    if (a == null || b == null) return 0.0;
    return cosineKVector(
      aRe: a.kRe,
      aIm: a.kIm,
      bRe: b.kRe,
      bIm: b.kIm,
    );
  }
}
