// engram_complex.dart — complex AR(2) fit_all (port of engram_codec.fit_all)
//
// Companion to engram_fit.dart. That file is the real-1D specialisation
// used for branch-orbit work. This file is the P-wide complex
// generalisation the Alexandria codec uses for K-space embedding:
//
//   given [T, P] complex trajectory z (T timesteps × P pairs),
//   fit z[n] = K·z[n-1] − G·z[n-2] per-pair independently
//   return K[P], G[P], per-pair RMS, mean RMS.
//
// Complex values are stored SoA (separate real/imag Float64Lists) —
// this matches Engram's Rust layout, which is structured that way so
// LLVM auto-vectorises the inner loops. Dart doesn't have explicit
// SIMD, but SoA still wins by keeping tight scalar loops cache-hot and
// letting the VM's JIT emit clean numeric code.
//
// Fallback: inputs with T < SEED_COUNT+1 return the "linear K" fallback
// (K=2+0i, G=1+0i) exactly as Engram does, so well assignment never
// sees NaN.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The order of the autoregressive model we fit: AR(2). This is the
/// fundamental parameter of the whole Whisper/Alexandria codec — every
/// observation is predicted from the previous two via
/// `z[n] = K·z[n-1] − G·z[n-2]`. Not a tuning knob; if this changed,
/// we'd be fitting a different model entirely (AR(1) is a random walk,
/// AR(3)+ gives a non-unique K,G solution without extra constraints).
const int engramArOrder = 2;

/// Seed-sample count — matches the Python codec's `SEED_COUNT`. Derived
/// from the AR order: you need [engramArOrder] past samples before any
/// residual row can be written. This is WHAT it means, not a choice.
const int engramSeedCount = engramArOrder;

/// Minimum trajectory length that can actually be fitted. Derived
/// directly: [engramSeedCount] seeds plus at least one residual row so
/// the normal equations have a solution. Anything shorter returns the
/// linear (K=2, G=1) fallback — geometrically, "no orbit detectable."
const int engramComplexMinSamples = engramSeedCount + 1;

/// Tikhonov ridge scale on the normal equations — 1e-4 matches the
/// Python codec's `RIDGE_SCALE`. The ridge is applied proportional to
/// the trace (sAA + sBB), so it never distorts well-conditioned
/// systems; singular/degenerate systems get regularised into solvability.
/// 1e-4 is a standard numerical-analysis ridge scale (the sqrt of
/// ~f32-epsilon-squared-over-unity): large enough to dominate true
/// floating-point noise at f64, small enough not to bias the solved
/// K, G away from their physical values. Tied to IEEE 754's
/// single-precision boundary, not a tuning dial.
const double _engramRidgeScale = 1e-4;

/// IEEE 754 f32 machine epsilon — 2^-23. The fit's degenerate-
/// determinant guard uses this: determinants within `eps·trace²` of
/// zero are treated as singular. Constant of arithmetic, not logic.
const double _engramMachineEps = 1.1920928955078125e-7;

/// Linear fallback (K=2+0i, G=1+0i). Applied per-pair when the normal
/// equations are singular for that pair. Same constants as Engram's
/// `LINEAR_K` / `LINEAR_G`.
const double _linearKre = 2.0;
const double _linearKim = 0.0;
const double _linearGre = 1.0;
const double _linearGim = 0.0;

/// Result of fit_all: per-pair K, G, RMS plus mean RMS.
@immutable
class EngramFitAll {
  final Float64List kRe; // [P]
  final Float64List kIm; // [P]
  final Float64List gRe; // [P]
  final Float64List gIm; // [P]
  final Float32List pairRms; // [P]
  final double meanRms;
  final bool anyValid;

  const EngramFitAll({
    required this.kRe,
    required this.kIm,
    required this.gRe,
    required this.gIm,
    required this.pairRms,
    required this.meanRms,
    required this.anyValid,
  });

  int get pairs => kRe.length;

  /// Construct an all-linear-fallback result for a given pair count.
  /// Used when T < min samples so downstream nearest-well still has a
  /// valid K vector to compare against well centroids (though in practice
  /// callers should gate on `anyValid`).
  factory EngramFitAll.linear(int p) {
    final kRe = Float64List(p)..fillRange(0, p, _linearKre);
    final kIm = Float64List(p)..fillRange(0, p, _linearKim);
    final gRe = Float64List(p)..fillRange(0, p, _linearGre);
    final gIm = Float64List(p)..fillRange(0, p, _linearGim);
    return EngramFitAll(
      kRe: kRe,
      kIm: kIm,
      gRe: gRe,
      gIm: gIm,
      pairRms: Float32List(p),
      meanRms: 0.0,
      anyValid: false,
    );
  }
}

/// Reusable scratch buffers for [fitAllComplex]'s accumulator pass.
/// One instance holds the 9 per-pair accumulators the AR(2) fit
/// needs; by keeping them alive across calls we turn what used to be
/// 9 Float64List allocations per hunk into zero — all the GC pressure
/// from thousands of hunks per diff evaporates.
/// Only the *internal accumulators* are reused. The output K/G/rms
/// arrays are freshly allocated per call because the caller's
/// `HunkKVector` retains a reference and the solver would otherwise
/// overwrite it on the next fit. That still cuts allocations per call
/// from 9 f64 lists to 4 f64 + 1 f32 — more than halved — and the
/// kept lists exactly fit the shape a downstream K-vector consumer
/// wants to hold.
/// Not thread-safe on purpose: every caller owns its own instance
/// (the hunk encoder creates one at construction; isolates have
/// their own encoder anyway). Size is fixed at construction to
/// `pairs`; attempting to use a scratch sized for a different
/// pair count hits the assertion and we'd catch it in tests.
class EngramComplexScratch {
  EngramComplexScratch(int p)
      : sAa = Float64List(p),
        sBb = Float64List(p),
        sTt = Float64List(p),
        sAbRe = Float64List(p),
        sAbIm = Float64List(p),
        sTaRe = Float64List(p),
        sTaIm = Float64List(p),
        sTbRe = Float64List(p),
        sTbIm = Float64List(p);

  final Float64List sAa, sBb, sTt;
  final Float64List sAbRe, sAbIm, sTaRe, sTaIm, sTbRe, sTbIm;

  int get pairs => sAa.length;

  /// Zero every accumulator in one pass. Float64List.fillRange with
  /// 0.0 compiles to a tight `memset` on the underlying byte buffer —
  /// the VM recognises zero-fill and dispatches to the platform's
  /// hardware-accelerated clear rather than a scalar loop.
  void reset() {
    sAa.fillRange(0, pairs, 0);
    sBb.fillRange(0, pairs, 0);
    sTt.fillRange(0, pairs, 0);
    sAbRe.fillRange(0, pairs, 0);
    sAbIm.fillRange(0, pairs, 0);
    sTaRe.fillRange(0, pairs, 0);
    sTaIm.fillRange(0, pairs, 0);
    sTbRe.fillRange(0, pairs, 0);
    sTbIm.fillRange(0, pairs, 0);
  }
}

/// Fit P independent complex AR(2) oscillators to a [T, P] complex matrix
/// stored row-major as separate real/imaginary Float64Lists of length T*P.
/// `zRe[t*P + p]` and `zIm[t*P + p]` are the real/imag components of
/// observation t for pair p.
/// Direct port of Python's `fit_all` in engram_codec.py — including the
/// ridge regularisation, per-pair degenerate-determinant guard, linear
/// fallback for bad pairs, and algebraic RMS computation.
/// If [scratch] is provided it's reused across calls (the hot path).
/// If null we allocate a fresh one for this call — fine for
/// one-off test code but the hunk encoder always passes its own.
EngramFitAll fitAllComplex({
  required Float64List zRe,
  required Float64List zIm,
  required int t,
  required int p,
  EngramComplexScratch? scratch,
}) {
  // Buffer must hold AT LEAST t × p values; allowing `>` lets callers
  // reuse oversized scratch buffers (sized for a max trajectory length)
  // without reallocating per call. The fit only reads the prefix
  // [0 .. t*p), so the tail is free to carry stale data.
  assert(zRe.length >= t * p && zIm.length >= t * p,
      'z buffer must hold at least t * p values');
  assert(scratch == null || scratch.pairs == p,
      'scratch pair count must match p');

  if (t < engramComplexMinSamples || p == 0) {
    return EngramFitAll.linear(p);
  }

  final n = t - 2; // number of rows in the normal equations

  // Per-pair accumulators, either reused from the caller's scratch
  // (the hot path — zero-allocation) or freshly allocated. Names
  // match the Python / Rust version:
  //   sAA = Σ |a|²   where a = z[i+1]
  //   sBB = Σ |b|²   where b = z[i]
  //   sTT = Σ |tgt|² where tgt = z[i+2]
  //   sAB = Σ a · conj(b)
  //   sTA = Σ tgt · conj(a)
  //   sTB = Σ tgt · conj(b)
  final s = scratch ?? EngramComplexScratch(p);
  if (scratch != null) s.reset();
  final sAa = s.sAa;
  final sBb = s.sBb;
  final sTt = s.sTt;
  final sAbRe = s.sAbRe;
  final sAbIm = s.sAbIm;
  final sTaRe = s.sTaRe;
  final sTaIm = s.sTaIm;
  final sTbRe = s.sTbRe;
  final sTbIm = s.sTbIm;

  // Single pass through time, all pairs at once per timestep.
  for (var i = 0; i < n; i++) {
    final aBase = (i + 1) * p;
    final bBase = i * p;
    final tBase = (i + 2) * p;
    for (var j = 0; j < p; j++) {
      final aRe = zRe[aBase + j];
      final aIm = zIm[aBase + j];
      final bRe = zRe[bBase + j];
      final bIm = zIm[bBase + j];
      final tRe = zRe[tBase + j];
      final tIm = zIm[tBase + j];

      sAa[j] += aRe * aRe + aIm * aIm;
      sBb[j] += bRe * bRe + bIm * bIm;
      sTt[j] += tRe * tRe + tIm * tIm;

      // a · conj(b) = (a·b*).re + i·(a·b*).im
      //             = (aRe·bRe + aIm·bIm) + i·(aIm·bRe − aRe·bIm)
      sAbRe[j] += aRe * bRe + aIm * bIm;
      sAbIm[j] += aIm * bRe - aRe * bIm;

      sTaRe[j] += tRe * aRe + tIm * aIm;
      sTaIm[j] += tIm * aRe - tRe * aIm;

      sTbRe[j] += tRe * bRe + tIm * bIm;
      sTbIm[j] += tIm * bRe - tRe * bIm;
    }
  }

  // Solve per pair: 2×2 complex Cramer with Tikhonov ridge on the
  // diagonal. Algebraic RMS from the already-accumulated sums. The
  // output arrays are freshly allocated so downstream consumers of
  // the returned [EngramFitAll] can retain them independently of
  // whether scratch is reused on the next call.
  final kRe = Float64List(p);
  final kIm = Float64List(p);
  final gRe = Float64List(p);
  final gIm = Float64List(p);
  final pairRms = Float32List(p);
  double totalRms = 0.0;
  var validCount = 0;

  for (var j = 0; j < p; j++) {
    final trace = sAa[j] + sBb[j];
    final ridge = math.max(_engramMachineEps, _engramRidgeScale * trace * 0.5);
    final sAaR = sAa[j] + ridge;
    final sBbR = sBb[j] + ridge;

    // |sAB|² = sAbRe² + sAbIm²
    final sAbMagSq = sAbRe[j] * sAbRe[j] + sAbIm[j] * sAbIm[j];
    final det = sAaR * sBbR - sAbMagSq;

    if (!det.isFinite || det.abs() < _engramMachineEps * trace * trace) {
      kRe[j] = _linearKre;
      kIm[j] = _linearKim;
      gRe[j] = _linearGre;
      gIm[j] = _linearGim;
      pairRms[j] = 0.0;
      continue;
    }

    final invDet = 1.0 / det;

    // K = (sTA · sBB_r − conj(sAB) · sTB) · inv(det)  (complex)
    //   conj(sAB) = (sAbRe, -sAbIm)
    //   conj(sAB) · sTB = (sAbRe · sTbRe + sAbIm · sTbIm)
    //                   + i·(sAbRe · sTbIm − sAbIm · sTbRe)
    // Wait — conjugation negates imag so:
    //   conj(sAB) · sTB = (sAbRe + i·(-sAbIm)) · (sTbRe + i·sTbIm)
    //                   = sAbRe·sTbRe + sAbIm·sTbIm
    //                   + i·(sAbRe·sTbIm − sAbIm·sTbRe)
    final numKRe = sTaRe[j] * sBbR - (sAbRe[j] * sTbRe[j] + sAbIm[j] * sTbIm[j]);
    final numKIm = sTaIm[j] * sBbR - (sAbRe[j] * sTbIm[j] - sAbIm[j] * sTbRe[j]);
    kRe[j] = numKRe * invDet;
    kIm[j] = numKIm * invDet;

    // G = (sAB · sTA − sAA_r · sTB) · inv(det)
    //   sAB · sTA = (sAbRe·sTaRe − sAbIm·sTaIm) + i·(sAbRe·sTaIm + sAbIm·sTaRe)
    final numGRe = (sAbRe[j] * sTaRe[j] - sAbIm[j] * sTaIm[j]) - sAaR * sTbRe[j];
    final numGIm = (sAbRe[j] * sTaIm[j] + sAbIm[j] * sTaRe[j]) - sAaR * sTbIm[j];
    gRe[j] = numGRe * invDet;
    gIm[j] = numGIm * invDet;

    if (!kRe[j].isFinite ||
        !kIm[j].isFinite ||
        !gRe[j].isFinite ||
        !gIm[j].isFinite) {
      kRe[j] = _linearKre;
      kIm[j] = _linearKim;
      gRe[j] = _linearGre;
      gIm[j] = _linearGim;
      pairRms[j] = 0.0;
      continue;
    }

    // Algebraic RMS (per pair) — the full 6-term formula:
    //   err_sq = sTT + |K|²·sAA + |G|²·sBB
    //          − 2·Re(conj(K)·sTA) + 2·Re(conj(G)·sTB)
    //          − 2·Re(K·conj(G)·sAB)
    //
    // The LS projection identity `||r||²_min = y*y − x*M*y` would
    // reduce this to three terms — but only when K, G are pure LS
    // solutions. Our Cramer solve includes Tikhonov ridge on the
    // diagonal, so K, G are LS-of-the-ridged-system, not pure LS.
    // The full formula is the one that matches the *actual* residual
    // energy of (K·A − G·B − y) on the real data. The reduction
    // would be mathematically "equivalent" only modulo O(ridge)
    // and observably shifts meanRms by ~1e-3 on short trajectories —
    // a behaviour change, not a free speedup. We keep the full form.
    final kMagSq = kRe[j] * kRe[j] + kIm[j] * kIm[j];
    final gMagSq = gRe[j] * gRe[j] + gIm[j] * gIm[j];

    // Re(conj(K) · sTA) = kRe·sTaRe + kIm·sTaIm
    final reKconjTa = kRe[j] * sTaRe[j] + kIm[j] * sTaIm[j];
    final reGconjTb = gRe[j] * sTbRe[j] + gIm[j] * sTbIm[j];

    // K · conj(G) = (kRe + i·kIm) · (gRe − i·gIm)
    //             = (kRe·gRe + kIm·gIm) + i·(kIm·gRe − kRe·gIm)
    final kGcRe = kRe[j] * gRe[j] + kIm[j] * gIm[j];
    final kGcIm = kIm[j] * gRe[j] - kRe[j] * gIm[j];
    final reKGcAb = kGcRe * sAbRe[j] - kGcIm * sAbIm[j];

    var errSq = sTt[j] +
        kMagSq * sAa[j] +
        gMagSq * sBb[j] -
        2.0 * reKconjTa +
        2.0 * reGconjTb -
        2.0 * reKGcAb;
    if (errSq < 0 || !errSq.isFinite) errSq = 0;
    final rms = math.sqrt(errSq / n);
    pairRms[j] = rms.isFinite ? rms : 0.0;
    totalRms += pairRms[j];
    validCount++;
  }

  final meanRms = validCount == 0 ? 0.0 : totalRms / validCount;
  return EngramFitAll(
    kRe: kRe,
    kIm: kIm,
    gRe: gRe,
    gIm: gIm,
    pairRms: pairRms,
    meanRms: meanRms,
    anyValid: validCount > 0,
  );
}

/// Apply a reference pairing permutation to a [T, dim] row-major float
/// matrix, producing a [T, pairs] complex trajectory. `pairing[2k]` and
/// `pairing[2k+1]` are the original dim indices that become the real/imag
/// components of complex pair k.
/// Returns (zRe, zIm), each length T * pairs.
({Float64List zRe, Float64List zIm}) applyPairingToComplex({
  required Float64List w,
  required Int32List pairing,
  required int t,
  required int dim,
}) {
  assert(pairing.length == dim, 'pairing length must equal dim');
  assert(dim.isEven, 'dim must be even');
  final pairs = dim ~/ 2;
  final zRe = Float64List(t * pairs);
  final zIm = Float64List(t * pairs);

  for (var ti = 0; ti < t; ti++) {
    final srcBase = ti * dim;
    final dstBase = ti * pairs;
    for (var k = 0; k < pairs; k++) {
      zRe[dstBase + k] = w[srcBase + pairing[2 * k]];
      zIm[dstBase + k] = w[srcBase + pairing[2 * k + 1]];
    }
  }
  return (zRe: zRe, zIm: zIm);
}

/// Cosine similarity between two K-vectors in ℂ^P, treated as ℝ^(2P)
/// by concatenating real and imaginary parts. Returns [0, 1] after
/// clamping (negative cosines mapped to 0 since our downstream use is
/// H_sym edge weights, which must be non-negative).
double cosineKVector({
  required Float64List aRe,
  required Float64List aIm,
  required Float64List bRe,
  required Float64List bIm,
}) {
  final p = aRe.length;
  if (p == 0 || bRe.length != p) return 0.0;
  double dot = 0.0;
  double aMagSq = 0.0;
  double bMagSq = 0.0;
  for (var i = 0; i < p; i++) {
    dot += aRe[i] * bRe[i] + aIm[i] * bIm[i];
    aMagSq += aRe[i] * aRe[i] + aIm[i] * aIm[i];
    bMagSq += bRe[i] * bRe[i] + bIm[i] * bIm[i];
  }
  if (aMagSq <= 0 || bMagSq <= 0) return 0.0;
  final cos = dot / math.sqrt(aMagSq * bMagSq);
  if (!cos.isFinite) return 0.0;
  if (cos <= 0) return 0.0;
  if (cos >= 1) return 1.0;
  return cos;
}

/// RMS distance between two K-vectors in ℂ^P.
///   sqrt(mean(|a[p] - b[p]|²))
/// Matches Python's nearest_well distance metric.
double rmsDistanceKVector({
  required Float64List aRe,
  required Float64List aIm,
  required Float64List bRe,
  required Float64List bIm,
}) {
  final p = aRe.length;
  if (p == 0 || bRe.length != p) return double.infinity;
  double acc = 0.0;
  for (var i = 0; i < p; i++) {
    final dre = aRe[i] - bRe[i];
    final dim_ = aIm[i] - bIm[i];
    acc += dre * dre + dim_ * dim_;
  }
  final d = math.sqrt(acc / p);
  return d.isFinite ? d : double.infinity;
}
