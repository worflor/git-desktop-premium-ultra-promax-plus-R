// ═════════════════════════════════════════════════════════════════════════
// bond/safety_number.dart — pair-verification numeric
//
// When Alice and Bob want to confirm they're really talking to each
// other, each device computes the same number over the unordered
// pair of their pubkeys. They read the digits to each other over a
// trusted side channel (phone, in person). Match = no MITM at
// handshake time.
//
// Two derivation paths:
//
//   • [computeSafetyNumber] (fast, no kizuna): SHA-256 over
//     sorted(pubA, pubB), sliced into 10 non-overlapping 3-byte
//     windows. Used for the always-available verify dialog and as a
//     fallback when no live kizuna witness is in scope.
//
//   • [computeKizunaSafetyNumber] (canonical): HKDF-expand the sorted
//     pair to 65536 bytes, run [handshake16D], encode the residual.
//     This is the witness Whisper's confirm-context hash uses; bit-
//     identical to what the live session derives during handshake.
//     Slower (one Möbius residual ≈ 65535 voxel reads) but it's the
//     primitive the project is named after — when both ends report
//     the same kizuna number, they share the same lattice position
//     in addition to the pair-pubkey commitment.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cg;
import 'package:pointycastle/digests/sha256.dart';

import 'kizuna.dart';

/// Formats the safety number as 10 groups of 5 digits, space-
/// separated — ~8 seconds to read aloud.
///
/// Example output:
///   "03421 88519 41207 62088 94513 00277 11840 96551 23874 09983"
String computeSafetyNumber(Uint8List pubA, Uint8List pubB) {
  if (pubA.length != 32 || pubB.length != 32) {
    throw ArgumentError('pubkeys must be 32 bytes each');
  }
  // Lexicographic sort so the output is symmetric between the two
  // peers — neither has to know which of them initiated.
  final ordered = _compare(pubA, pubB) <= 0
      ? [pubA, pubB]
      : [pubB, pubA];
  final digest = SHA256Digest();
  digest.update(ordered[0], 0, ordered[0].length);
  digest.update(ordered[1], 0, ordered[1].length);
  final hash = Uint8List(32);
  digest.doFinal(hash, 0);
  // 10 non-overlapping 3-byte windows covering bytes 0..29.
  final groups = <String>[];
  for (var i = 0; i < 10; i++) {
    final off = i * 3;
    final v = (hash[off] << 16) | (hash[off + 1] << 8) | hash[off + 2];
    groups.add((v % 100000).toString().padLeft(5, '0'));
  }
  return groups.join(' ');
}

int _compare(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    final d = a[i] - b[i];
    if (d != 0) return d;
  }
  return a.length - b.length;
}

/// Kizuna-witness safety number — the canonical pair-verify form.
///
/// Construction:
///   1. Lex-sort the pubkey pair (symmetric output).
///   2. HKDF-SHA256 with salt = sorted concatenation, info =
///      "kizuna/safety/v1", out = 65536 bytes.
///   3. Run [handshake16D] over the expanded block.
///   4. Format the 32-bit residual as 10 decimal digits in two groups
///      of 5 (matching the [computeSafetyNumber] groove so the UI can
///      render either kind in the same widget).
///
/// Both ends compute bit-identically. Mismatch = MITM at handshake or
/// at one party's pubkey — the same property the in-session kizuna
/// witness gives, applied here to the long-term identity pair.
Future<String> computeKizunaSafetyNumber(
  Uint8List pubA,
  Uint8List pubB,
) async {
  if (pubA.length != 32 || pubB.length != 32) {
    throw ArgumentError('pubkeys must be 32 bytes each');
  }
  final ordered = _compare(pubA, pubB) <= 0
      ? <Uint8List>[pubA, pubB]
      : <Uint8List>[pubB, pubA];
  final salt = Uint8List.fromList([...ordered[0], ...ordered[1]]);
  // HKDF-expand to a full kizuna block. The IKM is a constant zero
  // vector — entropy lives entirely in the salt (the pair). This is
  // the canonical "expand a pair to a 65536-byte witness block" step
  // mirroring `loopExpand` in live-handshake.ts.
  final hkdf = cg.Hkdf(hmac: cg.Hmac.sha256(), outputLength: kKizunaBlockSize);
  final ikm = cg.SecretKey(Uint8List(32));
  final derived = await hkdf.deriveKey(
    secretKey: ikm,
    nonce: salt,
    info: _kSafetyInfo,
  );
  final block = Uint8List.fromList(await derived.extractBytes());
  final witness = handshake16D(block).residual;
  // Two 5-digit groups from the residual: high 16 bits → group 1,
  // low 16 bits → group 2. Mod 100000 keeps each group in 5 digits.
  final wU = witness & 0xFFFFFFFF;
  final hi = ((wU >> 16) & 0xFFFF) % 100000;
  final lo = (wU & 0xFFFF) % 100000;
  return '${hi.toString().padLeft(5, "0")} ${lo.toString().padLeft(5, "0")}';
}

const List<int> _kSafetyInfo = [
  // ASCII "kizuna/safety/v1"
  107, 105, 122, 117, 110, 97, 47, 115, 97, 102, 101, 116, 121, 47, 118, 49,
];

/// Short fingerprint for UI chrome — first 8 bytes of SHA-256(pubkey),
/// hex-encoded, groups of 4. Not a security guarantee on its own; used
/// as a one-glance visual identifier alongside the full safety number.
String fingerprintHex(Uint8List pubkey) {
  final digest = SHA256Digest();
  digest.update(pubkey, 0, pubkey.length);
  final hash = Uint8List(32);
  digest.doFinal(hash, 0);
  final buf = StringBuffer();
  for (var i = 0; i < 8; i++) {
    if (i == 4) buf.write(' ');
    buf.write(hash[i].toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}
