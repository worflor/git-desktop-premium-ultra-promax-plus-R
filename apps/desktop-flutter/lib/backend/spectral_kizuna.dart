// SPECTRAL KIZUNA — 25D Walsh-Hadamard chemistry on joint (file, commit)
// fingerprint pairs.
//
// Ported from the OG Logos hyper-chemistry stack at
// `worflor.github.io/rag_tests` — specifically
// `hyper_cache.py:KIZUNA_MASKS_25` and
// `legacy/reference/test_25d_math.py`. The 25 masks are a graded WHT
// basis on the 16-bit hypercube (GF(2)^16):
//
//   L0..L7  (0x0001..0x0080)  first-order marginals of the commit byte
//   U0..U7  (0x0100..0x8000)  first-order marginals of the file byte
//   X0..X7  (0x0101..0x8080)  mode-by-mode diagonal correlation
//   FFFF    (0xFFFF)          global parity over the joint distribution
//
// Identity (proven in tmp_kizuna_proof.py EXP 1):
//   X_i = (#pairs with bit i agreement) − (#pairs with bit i disagreement)
//
// In the LogosGit register this gives a direct readout of whether the
// file graph's Fiedler mode i rhymes with the commit graph's Fiedler
// mode i over the touched (commit, file) pairs of a repo. Applied to
// two engines' bond fingerprints, cosine similarity reads compatibility;
// family-profile cosine is the travel-ready 4D chemistry card.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';
import 'logos_signature.dart';

/// 16-bit address space — the joint fingerprint range for an 8-bit file
/// fingerprint crossed with an 8-bit commit fingerprint.
const int kKizunaAddressSpace = 65536;

/// The 25 Kizuna masks in canonical order:
///   indices  0..7   L0..L7   commit-byte bit i
///   indices  8..15  U0..U7   file-byte bit i
///   indices 16..23  X0..X7   matched bit i in both bytes
///   index   24      FFFF     global all-bits parity
///
/// Byte-order convention: address = (fileFp << 8) | commitFp. This
/// matches the rag_tests reference, where the "lower" family reads
/// the low byte (commit) and "upper" reads the high byte (file).
const List<int> kKizunaMasks25 = <int>[
  0x0001, 0x0002, 0x0004, 0x0008, 0x0010, 0x0020, 0x0040, 0x0080,
  0x0100, 0x0200, 0x0400, 0x0800, 0x1000, 0x2000, 0x4000, 0x8000,
  0x0101, 0x0202, 0x0404, 0x0808, 0x1010, 0x2020, 0x4040, 0x8080,
  0xFFFF,
];

/// `popcount(m) & 1` for m in [0, 65536). Built once on first access.
/// 64 KiB fixed footprint.
final Uint8List _parity16 = _buildParity16();

Uint8List _buildParity16() {
  final p = Uint8List(kKizunaAddressSpace);
  for (var m = 1; m < kKizunaAddressSpace; m++) {
    p[m] = p[m >> 1] ^ (m & 1);
  }
  return p;
}

/// Compute the 25D Walsh-Hadamard fingerprint of a length-65536
/// real-valued histogram. `block[m]` is the weight at joint fingerprint
/// address `m`. Returns the 25 WHT coefficients in canonical order.
/// Cost is O(25 · 65536) ≈ 1.6 M ops per call.
Float64List whtFingerprint25D(Float64List block) {
  assert(block.length == kKizunaAddressSpace,
      'block must have length $kKizunaAddressSpace');
  final out = Float64List(25);
  for (var k = 0; k < 25; k++) {
    final mask = kKizunaMasks25[k];
    var s = 0.0;
    for (var m = 0; m < kKizunaAddressSpace; m++) {
      s += (_parity16[m & mask] == 0 ? 1.0 : -1.0) * block[m];
    }
    out[k] = s;
  }
  return out;
}

/// Immutable 25D Kizuna bond fingerprint of a joint (file, commit)
/// touch distribution. Holds the 25 WHT coefficients partitioned into
/// the four canonical families plus a cheap signature hash.
///
/// Equality is by signature (derived from the coefficient bit patterns).
/// Two bonds with the same coefficients produce the same signature and
/// compare equal; callers can use this for cache keys and Map lookup.
class KizunaBond25D {
  KizunaBond25D({required this.coefficients, Signature? signature})
      : assert(coefficients.length == 25, 'must be 25 coefficients'),
        signature = signature ?? _fingerprintCoefficients(coefficients);

  /// 25 WHT coefficients in canonical order (L0..L7, U0..U7, X0..X7, FFFF).
  final Float64List coefficients;

  /// Content fingerprint over the 25 double bit patterns. Matched
  /// exactly between two bonds ⇒ coefficients are structurally identical.
  /// See [Signature] for cross-platform semantics.
  final Signature signature;

  /// Build a bond from a 65536-bin joint-touch histogram. `histogram[m]`
  /// is the weight at address `m = (fileFp << 8) | commitFp`.
  factory KizunaBond25D.fromHistogram(Float64List histogram) =>
      KizunaBond25D(coefficients: whtFingerprint25D(histogram));

  /// Build a bond from parallel file and commit fingerprint arrays, one
  /// entry per touched (commit, file) pair. This is the primary entry
  /// point from SpacetimeBasis + a touch graph.
  factory KizunaBond25D.fromFingerprintPairs({
    required Uint8List fileFingerprints,
    required Uint8List commitFingerprints,
  }) {
    assert(fileFingerprints.length == commitFingerprints.length,
        'parallel arrays must have equal length');
    final hist = Float64List(kKizunaAddressSpace);
    final n = fileFingerprints.length;
    for (var i = 0; i < n; i++) {
      final addr = (fileFingerprints[i] << 8) | commitFingerprints[i];
      hist[addr] += 1.0;
    }
    return KizunaBond25D.fromHistogram(hist);
  }

  /// Build a bond from (fileFp, commitFp, weight) triples — variant of
  /// [fromFingerprintPairs] for weighted touches (e.g. hunk size).
  factory KizunaBond25D.fromWeightedPairs({
    required Uint8List fileFingerprints,
    required Uint8List commitFingerprints,
    required Float64List weights,
  }) {
    assert(
      fileFingerprints.length == commitFingerprints.length &&
          fileFingerprints.length == weights.length,
      'parallel arrays must have equal length',
    );
    final hist = Float64List(kKizunaAddressSpace);
    final n = fileFingerprints.length;
    for (var i = 0; i < n; i++) {
      final addr = (fileFingerprints[i] << 8) | commitFingerprints[i];
      hist[addr] += weights[i];
    }
    return KizunaBond25D.fromHistogram(hist);
  }

  /// Lower family — first-order marginals of the commit 8-bit
  /// fingerprint across touched pairs. 8 signed scalars.
  Float64List get lower => _copySlice(0, 8);

  /// Upper family — first-order marginals of the file 8-bit
  /// fingerprint across touched pairs. 8 signed scalars.
  Float64List get upper => _copySlice(8, 16);

  /// Cross family — mode-i-by-mode-i alignment between the file and
  /// commit Fiedler cleavages over touched pairs. Signed:
  ///   X_i > 0   file and commit mode i agree more often than disagree
  ///   X_i = 0   decoupled
  ///   X_i < 0   anti-correlated
  /// Exactly `#agree − #disagree` by construction.
  Float64List get cross => _copySlice(16, 24);

  /// Global FFFF parity of the joint distribution. The scalar
  /// bond-energy witness in the chemistry framework.
  double get global => coefficients[24];

  /// Compact 4-D normalized family mass profile (lower, upper, cross,
  /// global). Travel-ready chemistry card — use for cross-machine
  /// first-stage filtering.
  KizunaFamilyProfile get familyProfile {
    var sL = 0.0, sU = 0.0, sX = 0.0;
    for (var i = 0; i < 8; i++) {
      sL += coefficients[i].abs();
      sU += coefficients[i + 8].abs();
      sX += coefficients[i + 16].abs();
    }
    final values = Float64List(4);
    values[0] = sL / 8.0;
    values[1] = sU / 8.0;
    values[2] = sX / 8.0;
    values[3] = coefficients[24].abs();
    final total = values[0] + values[1] + values[2] + values[3];
    if (total > 1e-9) {
      final inv = 1.0 / total;
      for (var i = 0; i < 4; i++) {
        values[i] *= inv;
      }
    }
    return KizunaFamilyProfile(values: values);
  }

  /// Angular compatibility with another bond in the 25-D coefficient
  /// space. `+1` identical (up to positive scale), `0` orthogonal,
  /// `−1` fully anti-correlated.
  double cosineSimilarity(KizunaBond25D other) =>
      _cosineSimilarity(coefficients, other.coefficients);

  /// Steric stability `1 / (1 + |W_FFFF| / meanAxisMass)`. High when
  /// the bond's mass is distributed across directions; low when it
  /// concentrates at the global boundary. From hyper_cache.py:2749.
  double get stericStability {
    var sumAbs = 0.0;
    for (var i = 0; i < 25; i++) {
      sumAbs += coefficients[i].abs();
    }
    final meanAxisMass = sumAbs / 25.0 + 1e-6;
    return 1.0 / (1.0 + coefficients[24].abs() / meanAxisMass);
  }

  /// Wire-transferable byte representation. Layout:
  ///   [0..4)    magic "KZN\0"  0x4b5a4e00
  ///   [4..8)    version        uint32 (1)
  ///   [8..16)   signature      two little-endian uint32 (lo, hi)
  ///   [16..216) coefficients   25 × 8 bytes little-endian Float64
  ///   total = 216 bytes
  Uint8List toBytes() {
    const total = 216;
    final out = Uint8List(total);
    final bd = ByteData.view(out.buffer);
    bd.setUint32(0, 0x4b5a4e00, Endian.little);
    bd.setUint32(4, 1, Endian.little);
    // Signature as two little-endian 31-bit halves (see [Signature]).
    signature.writeBytes(bd, 8);
    for (var i = 0; i < 25; i++) {
      bd.setFloat64(16 + i * 8, coefficients[i], Endian.little);
    }
    return out;
  }

  /// Reconstruct from [toBytes] bytes. Throws [FormatException] on bad
  /// magic or unknown version.
  factory KizunaBond25D.fromBytes(Uint8List bytes) {
    if (bytes.length < 216) {
      throw const FormatException('KizunaBond25D.fromBytes: buffer too small');
    }
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    final magic = bd.getUint32(0, Endian.little);
    final version = bd.getUint32(4, Endian.little);
    if (magic != 0x4b5a4e00 || version != 1) {
      throw const FormatException('KizunaBond25D.fromBytes: bad magic/version');
    }
    final signature = Signature.readBytes(bd, 8);
    final coefficients = Float64List(25);
    for (var i = 0; i < 25; i++) {
      coefficients[i] = bd.getFloat64(16 + i * 8, Endian.little);
    }
    return KizunaBond25D(coefficients: coefficients, signature: signature);
  }

  Float64List _copySlice(int start, int end) {
    final out = Float64List(end - start);
    for (var i = 0; i < end - start; i++) {
      out[i] = coefficients[start + i];
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KizunaBond25D && signature == other.signature);

  @override
  int get hashCode => signature.hashCode;

  @override
  String toString() =>
      'KizunaBond25D(sig=0x${signature.toHex()}, '
      'fam=${familyProfile.values})';
}

/// 4-D normalized mass profile (lower, upper, cross, global). Compact
/// enough to ship over the wire as a "chemistry card"; the four numbers
/// sum to 1.0 (or 0 when the bond is empty).
class KizunaFamilyProfile {
  KizunaFamilyProfile({required this.values})
      : assert(values.length == 4, 'must be 4 family values');

  final Float64List values;

  double get lower => values[0];
  double get upper => values[1];
  double get cross => values[2];
  double get global => values[3];

  double cosineSimilarity(KizunaFamilyProfile other) =>
      _cosineSimilarity(values, other.values);

  // intentionally no == / hashCode: the four Float64 entries are derived
  // from a KizunaBond25D signature; callers that need identity comparison
  // should compare the parent bond's signature directly. Structural Float64
  // equality is fragile across serialization boundaries (NaN, ±0).

  @override
  String toString() => 'KizunaFamilyProfile('
      'L=${values[0].toStringAsFixed(3)}, '
      'U=${values[1].toStringAsFixed(3)}, '
      'X=${values[2].toStringAsFixed(3)}, '
      'G=${values[3].toStringAsFixed(3)})';
}

// ── Bond-pair compatibility ──────────────────────────────────────────────────

/// Classification of the relationship between two bonds.
///
/// Used as a decision surface for the Bonds sync/handshake protocol:
///
/// ```dart
/// switch (classifyBondPair(local, peer)) {
///   case KizunaBondCompatibility.identical: // no sync needed
///   case KizunaBondCompatibility.compatible: // fast delta sync
///   case KizunaBondCompatibility.related:    // full reconcile
///   case KizunaBondCompatibility.divergent:  // treat as unrelated
/// }
/// ```
enum KizunaBondCompatibility {
  /// Signature match — identical state.
  identical,

  /// Cosine > 0.85 and family-profile cosine > 0.9.
  compatible,

  /// Cosine in [0.3, 0.85].
  related,

  /// Cosine < 0.3 or anti-correlated.
  divergent,
}

/// Classify the relationship between two bonds for sync/handshake decisions.
///
/// Thresholds:
///   - `identical`  — signature equality (bit-for-bit same coefficients)
///   - `compatible` — 25D cosine > 0.85 **and** family-profile cosine > 0.9
///   - `related`    — 25D cosine in [0.3, 0.85]
///   - `divergent`  — 25D cosine < 0.3 (includes anti-correlated bonds)
KizunaBondCompatibility classifyBondPair(KizunaBond25D a, KizunaBond25D b) {
  if (a.signature == b.signature) return KizunaBondCompatibility.identical;
  final cos25 = a.cosineSimilarity(b);
  if (cos25 > 0.85) {
    final cosFamily = a.familyProfile.cosineSimilarity(b.familyProfile);
    if (cosFamily > 0.9) return KizunaBondCompatibility.compatible;
    // High 25D cosine but family mismatch — treat as related.
    return KizunaBondCompatibility.related;
  }
  if (cos25 >= 0.3) return KizunaBondCompatibility.related;
  return KizunaBondCompatibility.divergent;
}

/// Build the joint (file, commit) touch histogram that feeds a Kizuna
/// bond. `fileFpTable[fileId]` is the 8-bit file fingerprint;
/// `commitFpTable[commitId]` is the 8-bit commit fingerprint;
/// `touchesPerFile[fileId]` is the list of commit ids that touched that
/// file. Output is a length-65536 histogram suitable for
/// [KizunaBond25D.fromHistogram].
Float64List buildKizunaHistogram({
  required Uint8List fileFpTable,
  required Uint8List commitFpTable,
  required List<List<int>> touchesPerFile,
  double weightPerTouch = 1.0,
}) {
  final hist = Float64List(kKizunaAddressSpace);
  final nFiles = fileFpTable.length;
  final nCommits = commitFpTable.length;
  final touchLimit =
      math.min(nFiles, touchesPerFile.length);
  for (var fileId = 0; fileId < touchLimit; fileId++) {
    final f = fileFpTable[fileId];
    final touches = touchesPerFile[fileId];
    for (final commitId in touches) {
      if (commitId < 0 || commitId >= nCommits) continue;
      final c = commitFpTable[commitId];
      hist[(f << 8) | c] += weightPerTouch;
    }
  }
  return hist;
}

/// Convenience — compute a bond directly from file and commit spectral
/// bases plus a per-file touch list. Returns null when either basis is
/// too small to carry an 8-bit fingerprint (fewer than 9 modes).
KizunaBond25D? kizunaBondOfSpectra({
  required SpectralBasis fileSpectrum,
  required SpectralBasis commitSpectrum,
  required List<List<int>> touchesPerFile,
}) {
  if (fileSpectrum.k < 9 || commitSpectrum.k < 9) return null;
  final hist = buildKizunaHistogram(
    fileFpTable: fileSpectrum.spectralFingerprintTable(),
    commitFpTable: commitSpectrum.spectralFingerprintTable(),
    touchesPerFile: touchesPerFile,
  );
  return KizunaBond25D.fromHistogram(hist);
}

double _cosineSimilarity(Float64List a, Float64List b) {
  assert(a.length == b.length);
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na < 1e-18 || nb < 1e-18) return 0.0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

Signature _fingerprintCoefficients(Float64List values) =>
    fingerprintFloat64(values);
