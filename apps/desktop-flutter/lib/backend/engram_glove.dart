// engram_glove.dart — compact GloVe vocabulary loader.
//
// Reads the int16-quantised GloVe binary produced by the preprocessing
// script. Supports token → [dim] float32 lookup. The binary is int16
// quantised with a single global scale, so dequant = (int16 * scale / 32767).
//
// File format ("GLV1"):
//   magic[4]   = "GLV1"
//   version    u32 = 1
//   n_tokens   u32
//   dim        u32
//   scale      f32 (global quantisation scale)
//   vocab section: [u8 len][utf8 bytes]  per token  (index order)
//   vectors section: int16[n_tokens][dim] row-major
//
// Load time is fast: we parse the vocab into a Dart `Map<String, int>`
// and keep the int16 vector block as a view into the original bytes.
// Lookup is O(1) hash + in-place dequant into a reusable Float64 buffer.

import 'dart:convert';
import 'dart:typed_data';

/// File magic matching the preprocessing script.
const _kGloveMagic = [0x47, 0x4C, 0x56, 0x31]; // "GLV1"

/// Supported binary layout version.
const int _kGloveVersion = 1;

class EngramGlove {
  EngramGlove._({
    required this.dim,
    required this.scale,
    required this.tokenIndex,
    required this.vectors,
  }) : _dequantStep = scale / 32767.0;

  /// Embedding dimension (300 for the trained Alexandria).
  final int dim;

  /// Dequantisation scale — matches the encoder's `6.0` global scale.
  /// Applied as `value = int16 * _dequantStep` where `_dequantStep`
  /// is the precomputed `scale / 32767.0`.
  final double scale;

  /// Precomputed per-unit dequantisation step so the hot path never
  /// pays for the 3–4 cycle scalar division that `scale / 32767.0`
  /// compiles to. Called once per load; every `lookup`/`fillRow`/
  /// `accumulateMean` just multiplies an int16 by this.
  final double _dequantStep;

  /// Token → row index. O(1) lookup.
  final Map<String, int> tokenIndex;

  /// Int16 vectors, row-major. Length == n_tokens * dim. We copy into
  /// a fresh Int16List at load (not a view) because the vocab section
  /// has variable length and the vectors block often lands on an odd
  /// byte offset, which `asInt16List` rejects on alignment grounds.
  /// The copy is ~5MB for the 18k-token vocab — milliseconds at
  /// startup, then pure int16 indexing at query time.
  final Int16List vectors;

  int get vocabSize => tokenIndex.length;

  /// Parse a GLV1 binary into a queryable [EngramGlove]. Throws on a
  /// bad header. Safe to call off the UI thread.
  /// All multi-byte fields are little-endian, matching what
  /// `tools/export_engram_assets.py` writes via Python `struct.pack('<...')`
  /// and numpy's default little-endian int16 dtype.
  factory EngramGlove.loadBytes(Uint8List bytes) {
    if (bytes.length < 20) {
      throw const FormatException('glove: binary too small');
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _kGloveMagic[i]) {
        throw const FormatException('glove: bad magic (expected GLV1)');
      }
    }
    final bd = ByteData.sublistView(bytes);
    var off = 4;
    final version = bd.getUint32(off, Endian.little); off += 4;
    if (version != _kGloveVersion) {
      throw FormatException('glove: unsupported version $version');
    }
    final nTokens = bd.getUint32(off, Endian.little); off += 4;
    final dim = bd.getUint32(off, Endian.little); off += 4;
    final scale = bd.getFloat32(off, Endian.little); off += 4;
    if (dim == 0 || nTokens == 0) {
      throw const FormatException('glove: empty vocabulary');
    }

    // Vocab: [u8 len][utf8 bytes] per token, in row-index order.
    final index = <String, int>{};
    for (var i = 0; i < nTokens; i++) {
      if (off >= bytes.length) {
        throw const FormatException('glove: truncated vocab');
      }
      final len = bytes[off];
      off += 1;
      if (off + len > bytes.length) {
        throw const FormatException('glove: truncated token');
      }
      final token = utf8.decode(bytes.sublist(off, off + len));
      off += len;
      index[token] = i;
    }

    // Vector block: int16[nTokens * dim] row-major.
    final vecBytes = nTokens * dim * 2;
    if (off + vecBytes > bytes.length) {
      throw const FormatException('glove: truncated vectors');
    }
    // Copy into a freshly-allocated Int16List. The vocab section has
    // variable length (1 byte for `len` + `len` utf-8 bytes per token)
    // so the vectors block almost always lands on a non-2-aligned byte
    // offset — `asInt16List` would throw. Copying via ByteData.getInt16
    // sidesteps the alignment constraint and costs ~5MB + a few ms at
    // startup on the 18k-token bundle.
    final nInt16 = nTokens * dim;
    final vectors = Int16List(nInt16);
    final vecView = ByteData.sublistView(bytes, off, off + vecBytes);
    for (var i = 0; i < nInt16; i++) {
      vectors[i] = vecView.getInt16(i * 2, Endian.little);
    }

    return EngramGlove._(
      dim: dim,
      scale: scale,
      tokenIndex: index,
      vectors: vectors,
    );
  }

  /// Look up a token. Returns null for OOV. `out` is filled with the
  /// dequantised dim-dimensional vector. The caller owns `out`.
  bool lookup(String token, Float64List out) {
    assert(out.length == dim, 'out buffer length must equal dim');
    final idx = tokenIndex[token];
    if (idx == null) return false;
    final base = idx * dim;
    final step = _dequantStep;
    for (var i = 0; i < dim; i++) {
      out[i] = vectors[base + i] * step;
    }
    return true;
  }

  /// Compute the mean of GloVe vectors for a list of tokens, in place
  /// into `out` (length dim). Returns the number of hits — callers
  /// divide `out` themselves to finish the mean. Returns 0 if none of
  /// the tokens were in vocabulary.
  /// This is the hot path used by the hunk encoder: it avoids building
  /// an intermediate list of per-token vectors and reuses `out` across
  /// many hunks.
  int accumulateMean(Iterable<String> tokens, Float64List out) {
    assert(out.length == dim, 'out buffer length must equal dim');
    for (var i = 0; i < dim; i++) {
      out[i] = 0.0;
    }
    var hits = 0;
    final step = _dequantStep;
    for (final tok in tokens) {
      final idx = tokenIndex[tok];
      if (idx == null) continue;
      final base = idx * dim;
      for (var i = 0; i < dim; i++) {
        out[i] += vectors[base + i] * step;
      }
      hits++;
    }
    if (hits > 0) {
      final invHits = 1.0 / hits;
      for (var i = 0; i < dim; i++) {
        out[i] *= invHits;
      }
    }
    return hits;
  }

  /// Fill `outRow` (length [dim]) with the dequantised vector at
  /// `rowIndex`. Used by the encoder when we want to stack per-token
  /// vectors into a [T, dim] trajectory matrix.
  void fillRow(int rowIndex, Float64List outRow, int outOffset) {
    final base = rowIndex * dim;
    final step = _dequantStep;
    for (var i = 0; i < dim; i++) {
      outRow[outOffset + i] = vectors[base + i] * step;
    }
  }

  /// Fill paired re/im buffers by fusing the GloVe lookup + dequant
  /// + reference pairing into a single pass. The old pipeline did
  /// this in three stages: an intermediate Float64List fill via
  /// `fillRow`, then `applyPairingToComplex` scattering the D-dim
  /// row into P complex pairs. This fuses them: read each of the
  /// P pairs directly from the permuted pairing positions, dequant
  /// on the fly, split into re/im on the fly.
  /// No intermediate `[T, dim]` Float64List is allocated or touched.
  /// For a 50-token hunk at dim=300 that's 15,000 fewer loads + 15,000
  /// fewer stores compared to the separate-stages version, and zero
  /// per-call allocation of the (previously reusable) trajectory
  /// buffer.
  /// The pairing argument is the brain's reference pairing. It's a
  /// constant across all encodes for a given brain — callers
  /// typically pass `brain.pairing` and receive interleaved re/im
  /// filled into their scratch buffers.
  void fillPairedRow(
    int rowIndex,
    Int32List pairing,
    Float64List zRe,
    Float64List zIm,
    int pairOffset,
    int pairs,
  ) {
    assert(pairs * 2 == dim, 'pairs*2 must equal dim');
    final base = rowIndex * dim;
    final step = _dequantStep;
    for (var k = 0; k < pairs; k++) {
      final pi = k << 1;
      zRe[pairOffset + k] = vectors[base + pairing[pi]] * step;
      zIm[pairOffset + k] = vectors[base + pairing[pi + 1]] * step;
    }
  }
}
