// ═════════════════════════════════════════════════════════════════════════
// bond/safety_number.dart — Signal-style pair verification
//
// When Alice and Bob want to confirm they're really talking to each
// other, each device computes the same 60-digit number over the
// unordered pair of their pubkeys. They read the digits to each
// other over a trusted side channel (phone, in person). Match = no
// MITM at handshake time.
//
// Construction mirrors Signal's: SHA-256 over sorted(pubkeyA,
// pubkeyB), take first 30 bytes, decimal-encode in 5-digit chunks.
// Sorting makes the number symmetric (Alice and Bob compute the
// same string regardless of who initiated).
// ═════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

/// Formats a 60-digit safety number as twelve groups of 5 digits,
/// space-separated — readable in ~10 seconds over a phone call.
///
/// Example output:
///   "03421 88519 41207 62088 94513 00277 11840 96551 23874 09983 55162 70014"
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
  // Take 30 bytes → 12 groups of 5 decimal digits.
  final groups = <String>[];
  for (var i = 0; i < 12; i++) {
    final off = i * 2 + (i > 0 ? 1 : 0); // pick 30 bytes out of 32
    var v = 0;
    for (var j = 0; j < 3 && off + j < 30; j++) {
      v = (v << 8) | hash[off + j];
    }
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
