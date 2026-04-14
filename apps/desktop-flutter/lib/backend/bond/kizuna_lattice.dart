// ═════════════════════════════════════════════════════════════════════════
// bond/kizuna_lattice.dart — peer coordinates in the 16D kizuna space
//
// Whisper's kizuna is a 2-party witness primitive: both ends compute the
// same residual, no notion of group topology. Bond extends it: every
// peer in a bond is assigned a deterministic 16-bit coordinate in the
// 65536-cell hypercube, derived from `HKDF(bondId, peerPubkey)`. The
// coordinate places the peer somewhere in the same Boolean lattice the
// kizuna residual already mixes over.
//
// Why coordinates matter:
//   • Hamming distance gives a natural neighbourhood metric — peers
//     within distance N gossip more aggressively.
//   • The 8D⊗8D factorisation cuts the lattice into 256 "rows" of 256
//     peers each — a row becomes a sub-bond for sharded operations.
//   • Add/remove a peer = flip one bit in their coordinate; the
//     surrounding row witnesses tell the swarm exactly which sub-row
//     needs re-keying.
//
// This module is *just* the topology — the placement function, distance
// metric, and neighbourhood enumeration. Cryptographic group keys and
// re-keying protocols live above (TODO: kizuna_group_ratchet.dart).
// ═════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cg;

/// A 16-bit coordinate in the kizuna hypercube. Encoded as a single
/// `int` in [0, 65535] so each bit is one dimension.
extension type const KizunaCoordinate(int value) {
  static const int dimensions = 16;
  static const int max = 65535; // 2^16 - 1

  /// Origin (all-zero coordinate). Reserved for the witness-author
  /// position — peers should never land here organically.
  static const KizunaCoordinate origin = KizunaCoordinate(0);

  /// Bit at [dim] (0..15). 1 = present in subset S.
  int bit(int dim) {
    assert(dim >= 0 && dim < dimensions);
    return (value >> dim) & 1;
  }

  /// Hamming distance to [other] — number of dimensions that differ.
  /// 0 = identical position, 16 = antipode.
  int hammingDistanceTo(KizunaCoordinate other) {
    var x = value ^ other.value;
    var n = 0;
    while (x != 0) {
      n += x & 1;
      x >>= 1;
    }
    return n;
  }

  /// 8D⊗8D row index — the high byte. Two peers share a row iff their
  /// high 8 bits match. Useful for sharding gossip into row-groups
  /// (256 peers per row, 256 rows per lattice).
  int get rowIndex => (value >> 8) & 0xFF;

  /// Column index inside the row — the low 8 bits.
  int get columnIndex => value & 0xFF;

  /// Hex form for logs and addressing — 4 lowercase hex chars.
  String toHex() => value.toRadixString(16).padLeft(4, '0');
}

/// Deterministic peer placement: HKDF(bondId, peerPubkey, "kizuna/coord/v1")
/// → 2 bytes → 16-bit coordinate. Same (bond, pubkey) on every device
/// derives the same coordinate, so the swarm converges on its layout
/// without coordination.
Future<KizunaCoordinate> placePeer({
  required Uint8List bondId,
  required Uint8List peerPubkey,
}) async {
  final hkdf = cg.Hkdf(hmac: cg.Hmac.sha256(), outputLength: 2);
  final ikm = cg.SecretKey(peerPubkey);
  final info = Uint8List.fromList([
    ..._kCoordInfoPrefix,
    ...bondId,
  ]);
  final derived = await hkdf.deriveKey(
    secretKey: ikm,
    nonce: const <int>[],
    info: info,
  );
  final bytes = await derived.extractBytes();
  // Big-endian: bytes[0] = high (row), bytes[1] = low (column).
  final v = (bytes[0] << 8) | bytes[1];
  return KizunaCoordinate(v);
}

const List<int> _kCoordInfoPrefix = [
  // ASCII "kizuna/coord/v1/"
  107, 105, 122, 117, 110, 97, 47, 99, 111, 111, 114, 100, 47, 118, 49, 47,
];

/// Enumerates every coordinate within Hamming distance [radius] of
/// [center], ordered by increasing distance (so callers reading prefixes
/// of the iterable get nearest-first behaviour). For radius 16 returns
/// all 65536 cells; for radius 0 returns just the center.
Iterable<KizunaCoordinate> neighbourhood(
  KizunaCoordinate center, {
  required int radius,
}) sync* {
  assert(radius >= 0 && radius <= KizunaCoordinate.dimensions);
  // Iterate by increasing popcount of the difference-mask, so we emit
  // distance-0, then distance-1, etc.
  yield center;
  if (radius == 0) return;
  for (var d = 1; d <= radius; d++) {
    yield* _maskWithPopcount(d).map(
      (delta) => KizunaCoordinate(center.value ^ delta),
    );
  }
}

/// Emits every 16-bit value with exactly [k] bits set. Used by
/// [neighbourhood] to enumerate concentric Hamming rings.
Iterable<int> _maskWithPopcount(int k) sync* {
  if (k < 0 || k > 16) return;
  if (k == 0) {
    yield 0;
    return;
  }
  // Standard "next combination" walk: start at the lowest-k-bit-set
  // value, advance via the bit-twiddling identity until overflow.
  var v = (1 << k) - 1;
  while (v < (1 << 16)) {
    yield v;
    // Gosper's hack — next number with same popcount.
    final c = v & -v;
    final r = v + c;
    v = (((r ^ v) >> 2) ~/ c) | r;
  }
}

/// A snapshot of the lattice for one bond — every known peer placed at
/// their coordinate. Built incrementally as peers join; queried for
/// gossip-routing decisions ("who should I forward this advert to?").
class KizunaLatticeSnapshot {
  KizunaLatticeSnapshot._({required this.bondId, required this.byCoordinate});

  /// Bond this lattice scopes to.
  final Uint8List bondId;

  /// coordinate.value → peer pubkey. Multiple peers landing on the same
  /// coordinate is statistically rare (1/65536 per pair) but possible;
  /// the lattice keeps the first arrival to preserve determinism, and
  /// the second peer falls back to direct addressing.
  final Map<int, Uint8List> byCoordinate;

  /// Number of peers currently placed.
  int get size => byCoordinate.length;

  /// Peers within [radius] Hamming distance of [from], ordered by
  /// distance. The center peer (distance 0) is included if placed.
  Iterable<Uint8List> peersNear(
    KizunaCoordinate from, {
    required int radius,
  }) sync* {
    for (final coord in neighbourhood(from, radius: radius)) {
      final peer = byCoordinate[coord.value];
      if (peer != null) yield peer;
    }
  }

  /// Peers in the same 8D row — high byte equal. Useful for sharded
  /// gossip: refadverts within a row reach 255 sibling peers in O(1)
  /// directed sends.
  Iterable<Uint8List> peersInRow(int rowIndex) sync* {
    final base = (rowIndex & 0xFF) << 8;
    for (var col = 0; col < 256; col++) {
      final peer = byCoordinate[base | col];
      if (peer != null) yield peer;
    }
  }
}

/// Builder mirror of [KizunaLatticeSnapshot] — mutate as peers join,
/// snapshot for gossip decisions. Not thread-safe; the backend holds
/// one per bond and mutates from a single isolate.
class KizunaLatticeBuilder {
  KizunaLatticeBuilder({required this.bondId}) : _byCoordinate = {};

  final Uint8List bondId;
  final Map<int, Uint8List> _byCoordinate;

  /// Place [peerPubkey] at its derived coordinate. Returns the
  /// assigned coordinate; on collision returns the existing
  /// occupant's coordinate (the new peer falls back to direct
  /// addressing — log this case at the call site).
  Future<KizunaCoordinate> place(Uint8List peerPubkey) async {
    final coord = await placePeer(bondId: bondId, peerPubkey: peerPubkey);
    _byCoordinate.putIfAbsent(coord.value, () => peerPubkey);
    return coord;
  }

  /// Remove a peer (e.g., on revocation or explicit leave). No-op if
  /// the peer wasn't placed.
  Future<void> remove(Uint8List peerPubkey) async {
    final coord = await placePeer(bondId: bondId, peerPubkey: peerPubkey);
    _byCoordinate.remove(coord.value);
  }

  /// Cheap immutable view for gossip decisions.
  KizunaLatticeSnapshot snapshot() => KizunaLatticeSnapshot._(
        bondId: bondId,
        byCoordinate: Map.unmodifiable(_byCoordinate),
      );
}
