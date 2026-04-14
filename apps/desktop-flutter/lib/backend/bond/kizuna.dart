// ═════════════════════════════════════════════════════════════════════════
// bond/kizuna.dart — the 16D Möbius witness primitive (Dart port)
//
// Port of `live-wasm-kizuna.ts` from the Whisper reference. Pure math:
// no SIMD, no lookup tricks needed — boundary-cancellation is algebraic.
// At BS=2, the anti-causal Möbius predictor over the 65535-cell Boolean
// lattice 2^{0..15} telescopes to zero on every voxel except the origin.
// The single residual at the origin mixes all 65535 boundary voxels via
// signed inclusion-exclusion.
//
//   P = Σ_{∅≠S⊆{0..15}} (−1)^(|S|+1) · block[bitMask(S)]
//
// Both ends of a session expand the same ECDH-derived secret to 65536
// bytes and call [handshake16D] — equal residuals confirm the shared
// secret end-to-end. Fed into the confirm-context hash so a MITM at any
// signaling step makes the safety number diverge.
//
// Same algorithm as Whisper's `handshake16D`; bit-identical output for
// the same input block.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

/// Side of the 16D hypercube. 2^16 voxels per block.
const int kKizunaBlockSize = 65536;

/// Output sizes from [handshake16D].
const int kKizunaRowWitnessCount = 256;
const int kKizunaCountsBitMSize = 1024;

/// Popcount-parity table for masks 0..65535 — populated lazily on first
/// use. PARITY16[mask] = popcount(mask) & 1. Same table for 16D and 8D
/// since masks <256 give the 8-bit popcount parity directly.
Uint8List? _parity16;

Uint8List _parityTable() {
  final cached = _parity16;
  if (cached != null) return cached;
  final t = Uint8List(kKizunaBlockSize);
  for (var mask = 1; mask < kKizunaBlockSize; mask++) {
    t[mask] = t[mask >> 1] ^ (mask & 1);
  }
  _parity16 = t;
  return t;
}

/// Anti-causal 16D Möbius predictor at the origin voxel.
/// Loops over all 65535 non-empty subsets; sign by popcount parity.
int predAnti16D(Uint8List block) {
  final p = _parityTable();
  var sum = 0;
  for (var mask = 1; mask < kKizunaBlockSize; mask++) {
    sum += p[mask] != 0 ? block[mask] : -block[mask];
  }
  return sum;
}

/// 8D anti-causal Möbius predictor over a 256-element slice.
/// Works on any int-typed list (Uint8List for raw blocks, Int32List for
/// row witnesses in the factored decomposition).
int predAnti8D(List<int> data, int offset) {
  final p = _parityTable();
  var sum = 0;
  for (var mask = 1; mask < 256; mask++) {
    sum += p[mask] != 0 ? data[offset + mask] : -data[offset + mask];
  }
  return sum;
}

/// Result of the 8D⊗8D factored decomposition.
class Factored16DResult {
  Factored16DResult({required this.residual, required this.rowWitnesses});

  /// Identical to [predAnti16D] over the same block — by the
  /// μ₁₆ = μ₈ ⊗ μ₈ multiplicative identity.
  final int residual;

  /// 256 × int32 row sub-witnesses. rowWitnesses[h] is the 8D Möbius
  /// residual of `block[h*256 .. h*256+255]` — sensitive to all 255
  /// non-origin bytes in row h. Lets a corrupted block be diagnosed
  /// down to a 256-byte segment without recomputing the full 16D.
  final Int32List rowWitnesses;
}

/// 8D⊗8D factorisation — same residual as [predAnti16D], plus 256
/// intermediate row witnesses for free.
Factored16DResult factored16D(Uint8List block) {
  if (block.length != kKizunaBlockSize) {
    throw ArgumentError('expected $kKizunaBlockSize bytes, got ${block.length}');
  }
  final g = Int32List(256);
  for (var h = 0; h < 256; h++) {
    g[h] = block[h * 256] - predAnti8D(block, h * 256);
  }
  final outerPred = predAnti8D(g, 0);
  final residual = (g[0] - outerPred) | 0;
  return Factored16DResult(residual: residual, rowWitnesses: g);
}

/// Output of the kizuna handshake primitive. Both peers derive
/// bit-identical instances from the same ECDH-derived block.
class Handshake16DResult {
  Handshake16DResult({
    required this.residual,
    required this.rowWitnesses8D,
    required this.countsBitM,
  });

  /// The single Möbius residual at the origin — mixes all 65535
  /// boundary voxels through full inclusion-exclusion. Sensitive to
  /// every byte in the input block.
  final int residual;

  /// 256 × int32 sub-witnesses from the 8D⊗8D factorisation. See
  /// [Factored16DResult.rowWitnesses].
  final Int32List rowWitnesses8D;

  /// 1024 × uint32 Möbius per-bit model counts, primed with the first
  /// 512 bytes of the shared block via a binary-tree walk (mirrors
  /// the Loop's `BitContextModelM` initialisation in live-loop.ts).
  /// counts[ctx*2] = c0, counts[ctx*2+1] = c1, ctx = 0..511
  /// (prevBit*256 + treeCtx). Exposed for downstream use; kizuna
  /// itself doesn't read it back.
  final Uint32List countsBitM;
}

/// The kizuna handshake. Both ends compute this over the same expanded
/// secret block; equal `residual` confirms a shared cryptographic root.
///
/// Bit-compatible with `handshake16D` in `live-wasm-kizuna.ts`.
Handshake16DResult handshake16D(Uint8List sharedBlock) {
  if (sharedBlock.length != kKizunaBlockSize) {
    throw ArgumentError(
      'expected $kKizunaBlockSize bytes, got ${sharedBlock.length}',
    );
  }
  final f = factored16D(sharedBlock);
  final counts = Uint32List(kKizunaCountsBitMSize);
  // Laplace prior: 1/1 in every bin so the model converges fast on the
  // first observed bit.
  for (var i = 0; i < 512; i++) {
    counts[i * 2] = 1;
    counts[i * 2 + 1] = 1;
  }
  // Walk 512 bytes through the bit-context tree, advancing `ctx` per
  // bit and conditioning on the previous byte's bit at the same lane.
  var prev = 0;
  for (var i = 0; i < 512; i++) {
    final byte = sharedBlock[i];
    var ctx = 1;
    for (var k = 7; k >= 0; k--) {
      final bit = (byte >> k) & 1;
      final prevBit = (prev >> k) & 1;
      final idx = (prevBit * 256 + ctx) * 2;
      counts[idx + bit] = counts[idx + bit] + 1;
      ctx = (ctx << 1) | bit;
    }
    prev = byte;
  }
  return Handshake16DResult(
    residual: f.residual,
    rowWitnesses8D: f.rowWitnesses,
    countsBitM: counts,
  );
}

/// Encodes the residual as 4 little-endian bytes — the form fed into
/// the confirm-context hash in `deriveKizunaWitness`.
Uint8List residualToWitnessBytes(int residual) {
  // Treat as uint32 wrap so negative residuals round-trip cleanly.
  final r = residual & 0xFFFFFFFF;
  final out = Uint8List(4);
  out[0] = r & 0xFF;
  out[1] = (r >> 8) & 0xFF;
  out[2] = (r >> 16) & 0xFF;
  out[3] = (r >> 24) & 0xFF;
  return out;
}
