// LOGOS SIGNATURE — identity fingerprinting primitives.
//
// Extracted from `logos_core.dart` because these three units
// ([Signature] value type, [fingerprintFloat64] hash, [popcount8]
// Hamming helper) form a self-contained layer: zero coupling to the
// graph or basis, used everywhere above for cache keys, CRDT-safe
// equality, and bit-level distance.
//
// The public entrypoint `logos_core.dart` re-exports this file so
// callers that `import 'logos_core.dart'` continue to see
// [Signature], [fingerprintFloat64], and [popcount8] at the same
// import path they always have.

import 'dart:typed_data';

/// 62-bit content fingerprint, represented as two 31-bit halves so
/// it is bit-for-bit identical on Dart VM and Dart Web. A single-int
/// representation would overflow JS `Number.MAX_SAFE_INTEGER = 2^53 − 1`
/// on the web and silently round; callers that rely on signatures for
/// CRDT merges, cache keys, or wire transfers would see state divergence
/// between web and desktop clients.
///
/// Equality is structural (both halves equal). `hashCode` combines the
/// halves into a Dart int safely (xor). Serialization is 8 bytes,
/// little-endian, `lo` first then `hi`.
///
/// Zero signature ([Signature.zero]) is the identity element — used as
/// the default for empty or uninitialised state.
class Signature implements Comparable<Signature> {
  const Signature({required this.lo, required this.hi})
      : assert(lo >= 0 && lo <= 0x7fffffff,
            'lo must fit in 31 unsigned bits'),
        assert(hi >= 0 && hi <= 0x7fffffff,
            'hi must fit in 31 unsigned bits');

  /// Identity element. Equality with `isZero` is an engine-wide
  /// "uninitialised / empty" marker.
  static const Signature zero = Signature(lo: 0, hi: 0);

  /// Low 31 bits. Always non-negative and < 2^31.
  final int lo;

  /// High 31 bits. Always non-negative and < 2^31.
  final int hi;

  /// True iff both halves are zero.
  bool get isZero => lo == 0 && hi == 0;

  /// 16-character lowercase hex, `hi` first then `lo`, zero-padded.
  /// Suitable for filename-safe cache keys.
  String toHex() {
    final hiStr = hi.toRadixString(16).padLeft(8, '0');
    final loStr = lo.toRadixString(16).padLeft(8, '0');
    return '$hiStr$loStr';
  }

  /// Write as 8 little-endian bytes at [offset].
  void writeBytes(ByteData out, int offset) {
    out.setUint32(offset, lo, Endian.little);
    out.setUint32(offset + 4, hi, Endian.little);
  }

  /// Read 8 little-endian bytes starting at [offset].
  factory Signature.readBytes(ByteData bd, int offset) {
    final lo = bd.getUint32(offset, Endian.little);
    final hi = bd.getUint32(offset + 4, Endian.little);
    // uint32 can be up to 2^32 − 1; mask to 31 bits since our hash
    // producer guarantees that range. (Old serialised values are
    // backward-compatible because they were always < 2^31.)
    return Signature(lo: lo & 0x7fffffff, hi: hi & 0x7fffffff);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Signature && lo == other.lo && hi == other.hi);

  @override
  int get hashCode => lo ^ (hi * 2654435769) & 0x7fffffff;

  @override
  int compareTo(Signature other) {
    final dh = hi.compareTo(other.hi);
    return dh != 0 ? dh : lo.compareTo(other.lo);
  }

  @override
  String toString() => 'Signature(0x${toHex()})';
}

/// 62-bit FNV-1a-style fingerprint over the bit patterns of a
/// Float64List. Two independent 31-bit streams with different seeds
/// and per-word salts, combined into a [Signature] pair. All arithmetic
/// stays within JS-int safe range; the two halves are returned as a
/// structured [Signature] rather than multiplied together, so the
/// output is bit-for-bit identical on every Dart target.
///
/// Birthday collision probability at 10^4 distinct states ≈ 1e-11
/// — safe for CRDT-style state comparison.
Signature fingerprintFloat64(Float64List values) {
  if (values.isEmpty) return Signature.zero;
  final bd =
      values.buffer.asByteData(values.offsetInBytes, values.lengthInBytes);
  var hLo = 0x811c9dc5 ^ values.length;
  var hHi = 0xdeadbeef ^ values.length;
  const mask = 0x7fffffff;
  for (var i = 0; i < values.length; i++) {
    final lo = bd.getInt32(i * 8, Endian.little);
    final hi = bd.getInt32(i * 8 + 4, Endian.little);
    hLo = (hLo ^ lo) & mask;
    hLo = ((hLo * 0x01000193) ^ (hLo >> 13)) & mask;
    hLo = (hLo ^ hi) & mask;
    hLo = ((hLo * 0x01000193) ^ (hLo >> 13)) & mask;
    hHi = (hHi ^ lo ^ 0x5a5a5a5a) & mask;
    hHi = ((hHi * 0x01000193) ^ (hHi >> 13)) & mask;
    hHi = (hHi ^ hi ^ 0xa5a5a5a5) & mask;
    hHi = ((hHi * 0x01000193) ^ (hHi >> 13)) & mask;
  }
  return Signature(lo: hLo, hi: hHi);
}

/// 8-bit popcount via the standard bit-tricks reduction. Three shifts,
/// three masks. Compiles to a few integer ops on AOT; no tables.
///
/// Used by [Signature]-based Hamming distance consumers
/// (`spectral_state.dart`, `spectral_ratchet.dart`) as a shared
/// implementation, and by the spectral fingerprint distance on
/// `SpectralBasis`.
@pragma('vm:prefer-inline')
int popcount8(int v) {
  v = (v & 0x55) + ((v >> 1) & 0x55);
  v = (v & 0x33) + ((v >> 2) & 0x33);
  return (v & 0x0f) + ((v >> 4) & 0x0f);
}
