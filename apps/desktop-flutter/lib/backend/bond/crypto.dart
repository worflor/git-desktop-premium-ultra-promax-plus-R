// ═════════════════════════════════════════════════════════════════════════
// bond/crypto.dart — thin wrappers over `cryptography` for Bond usage
//
// The `cryptography` package gives us Ed25519, HKDF-HMAC-SHA256, AEADs
// with a single unified API. These helpers narrow that surface to the
// exact shapes Bond uses — sign-and-return-bytes, verify-returning-
// bool, HKDF-bytes-out — so call sites don't carry the framework's
// class juggling into every signed-object type.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cg;

final cg.Ed25519 _ed25519 = cg.Ed25519();

/// Signs [message] with [keyPair]. Returns the 64-byte Ed25519
/// signature as a plain `Uint8List`.
Future<Uint8List> signMessage(
  cg.SimpleKeyPair keyPair,
  List<int> message,
) async {
  final sig = await _ed25519.sign(message, keyPair: keyPair);
  return Uint8List.fromList(sig.bytes);
}

/// Verifies [signature] over [message] against the given 32-byte
/// Ed25519 public key. Returns `true` on a valid signature, `false`
/// on anything else — malformed keys, tampered messages, library
/// errors are all collapsed to `false`, so call sites don't have to
/// distinguish "forgery" from "couldn't parse."
Future<bool> verifySignature({
  required List<int> message,
  required Uint8List signature,
  required Uint8List publicKeyBytes,
}) async {
  try {
    final sig = cg.Signature(
      signature,
      publicKey: cg.SimplePublicKey(publicKeyBytes, type: cg.KeyPairType.ed25519),
    );
    return await _ed25519.verify(message, signature: sig);
  } catch (_) {
    return false;
  }
}

/// HKDF-HMAC-SHA256 that returns raw bytes. Convenience wrapper
/// because the library's return type is a `SecretKey` which we then
/// have to `extractBytes` from every single time.
Future<Uint8List> hkdfBytes({
  required Uint8List inputKeyMaterial,
  required Uint8List info,
  Uint8List? salt,
  int outputLength = 32,
}) async {
  final hkdf = cg.Hkdf(hmac: cg.Hmac.sha256(), outputLength: outputLength);
  final derived = await hkdf.deriveKey(
    secretKey: cg.SecretKey(inputKeyMaterial),
    nonce: salt ?? const <int>[],
    info: info,
  );
  final bytes = await derived.extractBytes();
  return Uint8List.fromList(bytes);
}

/// Constant-time bytewise equality. Use for comparing signatures,
/// MACs, and session roots — not just because crypto, but because the
/// `==` on `Uint8List` is a reference check and gives wrong answers.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
