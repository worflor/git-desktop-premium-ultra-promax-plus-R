// ═════════════════════════════════════════════════════════════════════════
// bond/object_xfer.dart — wire codec for objectWant / objectPack
//
// CBOR-framed bodies carry a 16-byte request id alongside the payload.
// The id lets the requester correlate a pack response to its specific
// want — without it, two concurrent fetches against the same broadcast
// `peer.packfiles` stream could attach packs to the wrong waiter (the
// per-peer fetch lock currently mitigates this but request ids are the
// proper fix).
//
// Wire shapes (all CBOR maps, short string keys):
//
//   objectWant (sender → peer):
//     { v: u8, id: bytes16, want: [bytes20|32, ...] }
//
//   objectPack (peer → sender):
//     { v: u8, id: bytes16, pack: bytes, err?: string }
//
//   Empty pack with err set = "I have nothing for you" or a server-
//   side build failure that's safe to surface to the requester.
//
// Version 1. Forward-compat: peers seeing v != 1 should drop with a
// dropCounter bump — older peers wouldn't sign or generate v=1
// envelopes anyway, so this is a hard cutover for v1 of the protocol.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:math';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';

const int kObjectXferVersion = 1;

/// Decoded `objectWant` body.
class ObjectWantBody {
  ObjectWantBody({
    required this.requestId,
    required this.want,
    this.have = const [],
  });

  /// 16 random bytes the requester picked. Echoed in the matching
  /// [ObjectPackBody]. Opaque to the responder.
  final Uint8List requestId;

  /// Hex commit hashes the responder should pack and send back.
  /// Empty list is legal (matches "no objects desired" — useful for
  /// keepalive or capability ping; responder echoes empty pack).
  final List<String> want;

  /// Optional hashes the requester already has. Responder uses these
  /// as `^hash` exclusions in `git pack-objects --revs` so the pack
  /// only carries the closure of (want \ have). Empty when the
  /// requester hasn't computed a have-bitmap yet.
  final List<String> have;

  Uint8List encode() {
    final map = <CborString, CborValue>{
      CborString('v'): CborSmallInt(kObjectXferVersion),
      CborString('id'): CborBytes(requestId),
      CborString('want'): CborList(
        want.map((s) => CborString(s)).toList(growable: false),
      ),
    };
    if (have.isNotEmpty) {
      map[CborString('have')] = CborList(
        have.map((s) => CborString(s)).toList(growable: false),
      );
    }
    return Uint8List.fromList(cbor.encode(CborMap(map)));
  }

  static ObjectWantBody? tryDecode(Uint8List body) {
    try {
      final decoded = cbor.decode(body);
      if (decoded is! CborMap) return null;
      final v = decoded[CborString('v')];
      final id = decoded[CborString('id')];
      final want = decoded[CborString('want')];
      if (v is! CborSmallInt || v.value != kObjectXferVersion) return null;
      if (id is! CborBytes || id.bytes.length != 16) return null;
      if (want is! CborList) return null;
      final hashes = <String>[];
      for (final item in want) {
        if (item is! CborString) return null;
        final s = item.toString();
        if (!_isPlausibleHash(s)) return null;
        hashes.add(s);
      }
      // Have list is optional and tolerant — entries that don't look
      // like hashes are skipped rather than failing the whole decode.
      final have = <String>[];
      final h = decoded[CborString('have')];
      if (h is CborList) {
        for (final item in h) {
          if (item is CborString && _isPlausibleHash(item.toString())) {
            have.add(item.toString());
          }
        }
      }
      return ObjectWantBody(
        requestId: Uint8List.fromList(id.bytes),
        want: hashes,
        have: have,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Decoded `objectPack` body.
class ObjectPackBody {
  ObjectPackBody({
    required this.requestId,
    required this.pack,
    this.error,
  });

  /// 16-byte echo of the corresponding [ObjectWantBody.requestId].
  final Uint8List requestId;

  /// Raw packfile bytes from `git pack-objects --stdout`. May be
  /// empty when [error] is set or when the responder genuinely had
  /// nothing to send.
  final Uint8List pack;

  /// Optional human-readable error from the responder side. UI may
  /// surface this; the dispatch layer treats any non-null error as
  /// "the response is informational, do not index."
  final String? error;

  Uint8List encode() {
    final map = <CborString, CborValue>{
      CborString('v'): CborSmallInt(kObjectXferVersion),
      CborString('id'): CborBytes(requestId),
      CborString('pack'): CborBytes(pack),
    };
    if (error != null) {
      map[CborString('err')] = CborString(error!);
    }
    return Uint8List.fromList(cbor.encode(CborMap(map)));
  }

  static ObjectPackBody? tryDecode(Uint8List body) {
    try {
      final decoded = cbor.decode(body);
      if (decoded is! CborMap) return null;
      final v = decoded[CborString('v')];
      final id = decoded[CborString('id')];
      final pack = decoded[CborString('pack')];
      if (v is! CborSmallInt || v.value != kObjectXferVersion) return null;
      if (id is! CborBytes || id.bytes.length != 16) return null;
      if (pack is! CborBytes) return null;
      final err = decoded[CborString('err')];
      return ObjectPackBody(
        requestId: Uint8List.fromList(id.bytes),
        pack: Uint8List.fromList(pack.bytes),
        error: err is CborString ? err.toString() : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Generates a 16-byte cryptographically-random request id. Uses
/// `dart:math`'s `Random.secure` — same primitive Bond uses elsewhere
/// for non-key randomness.
Uint8List newRequestId() {
  final rng = Random.secure();
  final out = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    out[i] = rng.nextInt(256);
  }
  return out;
}

bool _isPlausibleHash(String s) {
  if (s.length != 40 && s.length != 64) return false;
  for (final c in s.codeUnits) {
    final isHex =
        (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66);
    if (!isHex) return false;
  }
  return true;
}

/// Constant-time byte equality for request-id comparison. Not strictly
/// needed for correctness here (request ids aren't secret), but cheap
/// to keep consistent with the rest of the crypto-adjacent codebase.
bool requestIdEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
