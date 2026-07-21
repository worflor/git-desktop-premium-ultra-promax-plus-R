// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:math' as math;
import 'dart:typed_data';

import 'dtos.dart';

/// ═════════════════════════════════════════════════════════════════════════
/// COMMIT FINGERPRINT — 25D Walsh-Hadamard signature + 256-bit witness
/// ═════════════════════════════════════════════════════════════════════════
/// Two layered structural fingerprints per commit, both deterministic from
/// the commit's diff alone:
///   • [Float32List fingerprint] (length 25) — Walsh-Hadamard coefficients
///     against a fixed 25-mask family (lower / upper / cross / global) over
///     a 16-bit-indexed distribution built from the commit's files. Cosine
///     between fingerprints measures angular structural compatibility; two
///     commits whose diffs operate in similar parts of the file-id space
///     produce similar fingerprints. Doubles as the data input for the
///     5×5 sigil glyph rendered next to each commit hash.
///   • [Uint32List witness] (length 8 = 256 bits) — bipolar sign-projection
///     of the 25-fingerprint through a fixed scramble matrix. Hamming
///     distance between witnesses (XOR + popcount, O(8) words) is a cheap
///     cosine proxy. Use as a first-pass filter before falling back to
///     expensive Logos diffusion: pairwise scan over a 1000-commit history
///     is sub-millisecond.
/// The math is sparse — only the commit's actual files contribute, so the
/// per-commit cost scales with file count (~|files| × 25 ops for the WHT,
/// plus 256 × 25 = 6400 FMAs for the sign-projection). Both fingerprints
/// fit in 132 bytes of typed-array memory; a 1000-commit cache is ~130 KB.
/// SOURCE OF THE 25-MASK FAMILY: ports the Kizuna 25D bond geometry
/// (lower/upper/cross/global decomposition over 16-bit indices) from the
/// hyperdimensional-chemistry research codebase. The mask family is fixed
/// across the entire app; cross-commit comparisons are well-defined.
/// ═════════════════════════════════════════════════════════════════════════

/// Output dimensionality of [computeCommitSignature]'s fingerprint.
const int kFingerprintDim = 25;

/// Width of the bipolar witness in bits. 256 = 8 × Uint32 lanes —
/// keeps Hamming distance to a tiny inlined loop.
const int kWitnessBits = 256;

/// Stable seed for the witness scramble matrix. Fixed forever — changing
/// this invalidates every cached witness in the field. Drawn from the
/// same pinned-seed convention `LogosGit` uses for stability trials.
const int _kScrambleSeed = 0xABDE;

/// The 25 canonical Kizuna masks over 16-bit indices, in the fixed order the
/// fingerprint and the 5×5 sigil grid both read (row-major):
///   fp[0..7]   L0..L7 : single-bit masks 1<<i         — lower byte
///   fp[8..15]  U0..U7 : single-bit masks 1<<(i+8)     — upper byte
///   fp[16..23] X0..X7 : cross pairs (1<<i)|(1<<(i+8)) — diagonal coupling
///   fp[24]     FFFF   : global mask 0xFFFF            — total parity
///
/// alpha-math proof: these masks are NOT stored. They live in the character
/// group of (Z/2)^16 under XOR, where χ_S·χ_T = χ_{S⊕T}, so the 8 cross masks
/// are X_i = L_i ⊕ U_i and the global mask is the XOR of all 16 single bits —
/// only 16 of the 25 are independent. Every mask's Walsh sign is therefore an
/// XOR of single-bit signs, and a single-bit sign 1<<b is just bit b of the
/// bucket. So the whole 25-coefficient evaluation is bit reads + XOR: no mask
/// table, no (m & mask), no popcount LUT. The alpha-math instrument reads the
/// substrate commutative+associative and certifies the rewrite bit-identical
/// across all 2^16 buckets (manifold-proofs.ts, THEORY 1–2); the structural
/// path now lives in [computeCommitSignature].

/// Scramble matrix for the bipolar witness projection — 256 rows of 25
/// signed entries (±1, Achlioptas-style sketching). Lazy: built on the
/// first witness computation, then reused forever. ±1 entries are as
/// good as Gaussian for sign-projection (only the sign of the dot
/// product matters) and avoid every Gaussian-RNG cost.
Float32List? _scramble;
Float32List _scrambleMatrix() {
  final cached = _scramble;
  if (cached != null) return cached;
  final m = Float32List(kWitnessBits * kFingerprintDim);
  // xorshift32 — deterministic, portable across VM and web.
  var s = _kScrambleSeed;
  for (var i = 0; i < m.length; i++) {
    s ^= (s << 13) & 0xFFFFFFFF;
    s ^= s >> 17;
    s ^= (s << 5) & 0xFFFFFFFF;
    m[i] = (s & 1) == 0 ? -1.0 : 1.0;
  }
  _scramble = m;
  return m;
}

/// Bundled per-commit signature. Both members are typed arrays — cheap
/// to retain in a sidecar cache, trivial to send across an isolate port.
class CommitSignature {
  final Float32List fingerprint; // length kFingerprintDim
  final Uint32List witness; // length kWitnessBits ~/ 32
  const CommitSignature(this.fingerprint, this.witness);
}

/// Compute the structural signature for a commit from its file list.
/// Build phase:
///  1. Distribute each touched file into one of 65 536 buckets via
///     `path.hashCode & 0xFFFF`, accumulating add+del churn per bucket.
///  2. Sparse-evaluate the 25 Walsh-Hadamard coefficients against the
///     non-zero buckets only. Per-mask cost is O(|buckets|), per-commit
///     total is O(|files| × 25).
///  3. Sign-project the 25-fingerprint through the fixed scramble matrix
///     to derive the 256-bit witness. 6 400 FMAs per commit.
/// Determinism: file order, additions, deletions, and `String.hashCode`
/// are the only inputs. Same diff → same fingerprint forever.
CommitSignature computeCommitSignature(CommitDetailData detail) {
  // Sparse 16-bit bucket distribution. Hash-collisions across files in a
  // single commit just sum into the same bucket — matches the Kizuna
  // semantics of "atom = byte distribution," with files as our bytes.
  final buckets = <int, double>{};
  for (final f in detail.files) {
    final bucket = f.path.hashCode & 0xFFFF;
    final w = (f.additions + f.deletions).toDouble();
    if (w == 0) continue;
    buckets[bucket] = (buckets[bucket] ?? 0) + w;
  }

  final fp = Float32List(kFingerprintDim);
  if (buckets.isNotEmpty) {
    // Hot loop: contribute ±weight to each of the 25 Kizuna-mask Walsh
    // coefficients per non-zero bucket. The sign is the mask's Walsh
    // character χ_mask(m) = (-1)^popcount(m & mask) — but because the masks
    // form an XOR character subgroup (see the doc on the mask family above),
    // every sign reduces to bit reads + XOR of the bucket's bits. No mask
    // table, no popcount LUT. Each fp[k] accumulates exactly one ±w per
    // bucket, in the same bucket order as the old LUT path, so the float32
    // result is bit-identical.
    for (final e in buckets.entries) {
      final m = e.key;
      final w = e.value;
      var globalParity = 0;
      for (var i = 0; i < 8; i++) {
        final lo = (m >> i) & 1; // χ_{L_i}(m) — lower single bit
        final up = (m >> (i + 8)) & 1; // χ_{U_i}(m) — upper single bit
        globalParity ^= lo ^ up;
        fp[i] += lo == 1 ? -w : w; // L_i
        fp[8 + i] += up == 1 ? -w : w; // U_i
        fp[16 + i] += (lo ^ up) == 1 ? -w : w; // X_i = L_i ⊕ U_i
      }
      fp[24] += globalParity == 1 ? -w : w; // 0xFFFF = ⊕ all 16 single bits
    }
  }

  return CommitSignature(fp, projectWitness(fp));
}

/// Project a 25-fingerprint into a 256-bit bipolar witness using the
/// fixed scramble matrix. Exposed separately so callers (e.g. a query
/// "find me commits like THIS hunk-set") can build a witness from any
/// 25-vector without a CommitDetailData in hand.
Uint32List projectWitness(Float32List fp) {
  assert(fp.length == kFingerprintDim);
  final s = _scrambleMatrix();
  const words = kWitnessBits ~/ 32;
  final out = Uint32List(words);
  for (var k = 0; k < kWitnessBits; k++) {
    var dot = 0.0;
    final base = k * kFingerprintDim;
    for (var i = 0; i < kFingerprintDim; i++) {
      dot += s[base + i] * fp[i];
    }
    if (dot > 0) {
      out[k >> 5] |= 1 << (k & 31);
    }
  }
  return out;
}

/// Cosine similarity between two 25-fingerprints. Returns 0 when either
/// has zero magnitude (a pure-rename / 0-churn commit produces a
/// zero-vector fingerprint). Range [-1, 1].
double fingerprintCosine(Float32List a, Float32List b) {
  assert(a.length == b.length);
  var dot = 0.0;
  var na = 0.0;
  var nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  final denom = na * nb;
  if (denom <= 0) return 0.0;
  return dot / math.sqrt(denom);
}

/// Hamming distance between two 256-bit witnesses. O(8) words —
/// 8 × (XOR + popcount32). Returns the number of differing bits;
/// 0 = identical, kWitnessBits = maximally-divergent.
int witnessHamming(Uint32List a, Uint32List b) {
  assert(a.length == b.length);
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d += _popcount32(a[i] ^ b[i]);
  }
  return d;
}

/// Cosine-equivalent score derived from a witness Hamming distance.
/// Expected Hamming between two random sign-projections of vectors at
/// angle θ is `kWitnessBits · θ / π` — invert: `cos(π · h / kWitnessBits)`.
/// Returns a value in [-1, 1] directly comparable to [fingerprintCosine].
double witnessCosineFromHamming(int hamming) {
  final h = hamming.clamp(0, kWitnessBits);
  return math.cos(math.pi * h / kWitnessBits);
}

/// Portable popcount over a 32-bit integer. Hamming-weight via the
/// classic SWAR cascade, sized for 32-bit safety on every Dart target
/// (VM int is 64-bit, web smis are 53-bit). The shift+mask cascade
/// avoids the `* 0x01010101` final reduction that would overflow 53
/// bits in the worst case on web.
int _popcount32(int v) {
  v = v - ((v >> 1) & 0x55555555);
  v = (v & 0x33333333) + ((v >> 2) & 0x33333333);
  v = (v + (v >> 4)) & 0x0F0F0F0F;
  v = (v + (v >> 8)) & 0x00FF00FF;
  v = (v + (v >> 16)) & 0x0000FFFF;
  return v;
}
