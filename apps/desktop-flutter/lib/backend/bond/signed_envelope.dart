// ═════════════════════════════════════════════════════════════════════════
// bond/signed_envelope.dart — the universal wrapper for signed objects
//
// Every durable Bond primitive — ref advertisements, proposals,
// attestations, anchors, targets, policies, continuity attestations,
// revocations — ships inside this envelope:
//
//   SignedEnvelope {
//     version: u16,                     // kBondProtocolVersion
//     kind:    utf8 string,             // BondPacketType.name
//     body:    cbor-encoded bytes,      // type-specific payload
//     signer:  bytes[32],               // Ed25519 public key
//     signature: bytes[64]              // Ed25519 over canonical form
//   }
//
// Canonical bytes signed over = version-u16-BE || len(kind) || kind ||
//                               body_bytes.
//
// The envelope is then itself CBOR-encoded, so we never have to
// parse+reserialise the inner body to verify — the signature covers
// the body bytes exactly as received.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:cryptography/cryptography.dart' as cg;

import 'crypto.dart';
import 'wire.dart';

/// A signed, on-wire or at-rest Bond object. Opaque to the code that
/// routes it; carry it between peers, store it, re-verify as needed.
/// The `body` bytes decode into a type-specific struct based on
/// `kind`.
class SignedEnvelope {
  SignedEnvelope({
    required this.version,
    required this.kind,
    required this.body,
    required this.signerPublicKey,
    required this.signature,
  });

  /// Protocol version at sign time. Receivers drop envelopes with a
  /// higher major version they don't implement; minor bumps are
  /// forward-compatible by convention.
  final int version;

  /// Canonical kind tag. Values match [BondPacketType.name] so the
  /// routing code can `switch (env.kind)`.
  final String kind;

  /// Raw CBOR-encoded body. Parsers for each kind decode this
  /// directly without going back through `cborDecode` on the envelope.
  final Uint8List body;

  /// 32-byte Ed25519 public key of the signer.
  final Uint8List signerPublicKey;

  /// 64-byte Ed25519 signature over [canonicalSignedBytes] using
  /// [signerPublicKey].
  final Uint8List signature;

  /// The byte sequence the signature covers. Reconstructed from
  /// fields; must match exactly on both sides of a verification.
  Uint8List get canonicalSignedBytes {
    final kindBytes = utf8.encode(kind);
    final totalLen = 2 + 4 + kindBytes.length + body.length;
    final out = Uint8List(totalLen);
    // 2 bytes version (big-endian).
    out[0] = (version >> 8) & 0xff;
    out[1] = version & 0xff;
    // 4 bytes big-endian length of kind, then kind bytes.
    final kLen = kindBytes.length;
    out[2] = (kLen >> 24) & 0xff;
    out[3] = (kLen >> 16) & 0xff;
    out[4] = (kLen >> 8) & 0xff;
    out[5] = kLen & 0xff;
    out.setRange(6, 6 + kLen, kindBytes);
    out.setRange(6 + kLen, totalLen, body);
    return out;
  }
}

/// Builds a signed envelope around [bodyCbor], signing with the given
/// keypair. The caller is responsible for choosing `kind` — it must
/// match the expected tag for the body's decoded type, or verifiers
/// will reject the pairing.
Future<SignedEnvelope> signEnvelope({
  required cg.SimpleKeyPair keyPair,
  required Uint8List signerPublicKey,
  required BondPacketType kind,
  required Uint8List bodyCbor,
  int version = kBondProtocolVersion,
}) async {
  final env = SignedEnvelope(
    version: version,
    kind: kind.name,
    body: bodyCbor,
    signerPublicKey: signerPublicKey,
    signature: Uint8List(0), // temporary; overwritten below
  );
  final signature = await signMessage(keyPair, env.canonicalSignedBytes);
  return SignedEnvelope(
    version: version,
    kind: kind.name,
    body: bodyCbor,
    signerPublicKey: signerPublicKey,
    signature: signature,
  );
}

/// Result of verifying an envelope. Either [ok] with the verified
/// envelope, or an error with a specific reason code so call sites
/// can log + degrade gracefully (don't drop a whole session on one
/// bad packet).
class EnvelopeVerification {
  EnvelopeVerification._(this.envelope, this.error);

  /// Populated on success; null on failure.
  final SignedEnvelope? envelope;

  /// Populated on failure with a short machine-readable reason.
  /// One of: `"version_mismatch"`, `"unknown_kind"`,
  /// `"bad_signature"`, `"malformed"`.
  final String? error;

  bool get ok => envelope != null;

  factory EnvelopeVerification.ok(SignedEnvelope env) =>
      EnvelopeVerification._(env, null);
  factory EnvelopeVerification.err(String reason) =>
      EnvelopeVerification._(null, reason);
}

/// Verifies an envelope's signature against its declared signer, and
/// checks version + kind sanity. Does NOT verify anything about the
/// body's internal structure — callers that care about body shape
/// decode + validate separately after a successful envelope check.
Future<EnvelopeVerification> verifyEnvelope(SignedEnvelope env) async {
  if (env.version != kBondProtocolVersion) {
    return EnvelopeVerification.err('version_mismatch');
  }
  if (BondPacketType.fromTag(_tagForKind(env.kind)) == null) {
    return EnvelopeVerification.err('unknown_kind');
  }
  if (env.signature.length != 64) {
    return EnvelopeVerification.err('malformed');
  }
  if (env.signerPublicKey.length != 32) {
    return EnvelopeVerification.err('malformed');
  }
  final valid = await verifySignature(
    message: env.canonicalSignedBytes,
    signature: env.signature,
    publicKeyBytes: env.signerPublicKey,
  );
  if (!valid) return EnvelopeVerification.err('bad_signature');
  return EnvelopeVerification.ok(env);
}

/// Serialises an envelope to CBOR bytes for wire or at-rest storage.
/// Deterministic: the same envelope always serialises to the same
/// bytes, which is important because hash-based object IDs (e.g. for
/// proposals) are computed over these bytes.
Uint8List encodeEnvelope(SignedEnvelope env) {
  final map = CborMap({
    CborString('v'): CborSmallInt(env.version),
    CborString('k'): CborString(env.kind),
    CborString('b'): CborBytes(env.body),
    CborString('p'): CborBytes(env.signerPublicKey),
    CborString('s'): CborBytes(env.signature),
  });
  return Uint8List.fromList(cbor.encode(map));
}

/// Parses bytes previously produced by [encodeEnvelope]. Returns an
/// [EnvelopeVerification] in the parse-failed arm on any shape error;
/// successful parse does NOT verify the signature — call
/// [verifyEnvelope] next.
EnvelopeVerification decodeEnvelope(Uint8List bytes) {
  try {
    final decoded = cbor.decode(bytes);
    if (decoded is! CborMap) {
      return EnvelopeVerification.err('malformed');
    }
    final v = decoded[CborString('v')];
    final k = decoded[CborString('k')];
    final b = decoded[CborString('b')];
    final p = decoded[CborString('p')];
    final s = decoded[CborString('s')];
    if (v is! CborSmallInt || k is! CborString || b is! CborBytes ||
        p is! CborBytes || s is! CborBytes) {
      return EnvelopeVerification.err('malformed');
    }
    return EnvelopeVerification.ok(SignedEnvelope(
      version: v.value,
      kind: k.toString(),
      body: Uint8List.fromList(b.bytes),
      signerPublicKey: Uint8List.fromList(p.bytes),
      signature: Uint8List.fromList(s.bytes),
    ));
  } catch (_) {
    return EnvelopeVerification.err('malformed');
  }
}

/// Look up a [BondPacketType] by its string name (for cross-checking
/// decoded envelopes against the known packet vocabulary).
int _tagForKind(String kind) {
  for (final t in BondPacketType.values) {
    if (t.name == kind) return t.tag;
  }
  return -1;
}
