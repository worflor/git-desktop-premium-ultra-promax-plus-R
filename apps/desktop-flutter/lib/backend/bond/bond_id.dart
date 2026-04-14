// ═════════════════════════════════════════════════════════════════════════
// bond/bond_id.dart — deriving the swarm identifier
//
// A bond_id is the tracker topic + HKDF salt that lets peers sharing a
// repo and a phrase find each other. Derived, never assigned:
//
//   bond_id = SHA-256( bootstrap_commit_hash || swarm_phrase )
//
// Same repo + same phrase → same bond_id → peers converge on the same
// tracker channel. Phrase compromise → rotate the phrase → new bond_id
// → old channel becomes empty. No central registration; no name
// service; no way for an outside observer to guess the topic without
// both the repo's bootstrap commit and the shared phrase.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cg;

/// Canonical bond identifier. 32 bytes. Stable under the same
/// (bootstrap commit, swarm phrase) pair.
class BondId {
  BondId._(this.bytes);

  /// Reconstructs a [BondId] from previously-computed raw bytes.
  /// The only supported derivation path is [deriveBondId]; this
  /// factory exists for storage-enumeration (rebuilding ids from
  /// hex directory names) and round-tripping through persistence.
  /// Callers that accept untrusted input must validate length first.
  factory BondId.fromBytes(Uint8List bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('BondId requires exactly 32 bytes');
    }
    return BondId._(Uint8List.fromList(bytes));
  }

  /// The raw 32-byte identifier. Safe to treat as opaque; only
  /// byte-level comparisons are meaningful.
  final Uint8List bytes;

  /// Hex-encoded form for logging and storage-directory names.
  /// Lowercase, no prefix.
  String get hex =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Short form for UI surfaces — first 8 hex chars, same convention
  /// git uses for short commit hashes. Never use for identification.
  String get shortHex => hex.substring(0, 8);

  @override
  bool operator ==(Object other) {
    if (other is! BondId) return false;
    if (other.bytes.length != bytes.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    // FNV-1a over the first 8 bytes. Enough collision resistance for
    // the Map-key use-cases; full equality still uses byte compare.
    var h = 0x811c9dc5;
    for (var i = 0; i < 8 && i < bytes.length; i++) {
      h ^= bytes[i];
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  @override
  String toString() => 'BondId($shortHex)';
}

/// Derives a [BondId] from a repo's bootstrap commit hash (the
/// well-known anchor commit — typically the root commit, or an
/// explicitly-chosen historical commit that all participants have)
/// and the swarm phrase.
///
/// The swarm phrase is separate from the user's identity phrase. One
/// identity across many bonds; many bonds, each with its own phrase.
Future<BondId> deriveBondId({
  required String bootstrapCommitHash,
  required String swarmPhrase,
}) async {
  if (bootstrapCommitHash.isEmpty) {
    throw ArgumentError('bootstrapCommitHash is required');
  }
  if (swarmPhrase.isEmpty) {
    throw ArgumentError('swarmPhrase is required');
  }
  // Length-prefixed concatenation: each input is encoded as
  // (u32 big-endian byte-length)(utf8 bytes). Without the prefix a
  // pair like ("abc","def") and ("ab","cdef") would produce the same
  // hash input "abcdef" and therefore the same BondId — a trivial
  // collision. Prefixing makes the encoding prefix-free regardless
  // of field content.
  final hash = cg.Sha256();
  final bootstrapBytes =
      utf8.encode(bootstrapCommitHash.trim().toLowerCase());
  final phraseBytes = utf8.encode(swarmPhrase);
  final input = BytesBuilder(copy: false)
    ..add(_u32be(bootstrapBytes.length))
    ..add(bootstrapBytes)
    ..add(_u32be(phraseBytes.length))
    ..add(phraseBytes);
  final digest = await hash.hash(input.toBytes());
  return BondId._(Uint8List.fromList(digest.bytes));
}

Uint8List _u32be(int v) {
  final out = Uint8List(4);
  out[0] = (v >> 24) & 0xff;
  out[1] = (v >> 16) & 0xff;
  out[2] = (v >> 8) & 0xff;
  out[3] = v & 0xff;
  return out;
}
