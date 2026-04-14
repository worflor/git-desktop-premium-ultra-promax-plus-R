// ═════════════════════════════════════════════════════════════════════════
// bond/identity.dart — phrase → master → per-swarm keypair
//
// Bond's identity model: you remember a phrase; the phrase derives your
// master seed via Argon2id; the master seed derives per-swarm keypairs
// via HKDF. Lose the phrase → lose the identity. Remember the phrase →
// same identity on any device, forever. No central registrar, no
// recovery server.
//
// The master seed never touches the wire. Per-swarm subkeys are what
// peers see. Different swarms = different pubkeys from the same phrase,
// so cross-swarm correlation by pubkey is impossible.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cg;
import 'package:pointycastle/key_derivators/argon2.dart';
import 'package:pointycastle/key_derivators/api.dart';

/// Hardening parameters for the phrase → master-seed KDF.
///
/// Argon2id, memory-hard. The goal is to make offline brute-force of
/// weak phrases costly enough that a pubkey observation + phrase guess
/// can't recover the private key cheaply. At `m=256MiB, t=4, p=1` on
/// modern hardware this costs ~1s per guess; ~$0.001 per million
/// guesses on cloud GPUs. Weak phrases (< 40 bits) still fall; the
/// UI's entropy meter exists to refuse those at input time.
class BondKdfParams {
  const BondKdfParams({
    this.memoryKiB = 256 * 1024, // 256 MiB
    this.iterations = 4,
    this.parallelism = 1,
  });

  final int memoryKiB;
  final int iterations;
  final int parallelism;
}

/// Fixed-purpose salt for the phrase-level hardening. This is NOT a
/// per-user salt — per-user salts would require storage, which defeats
/// the "phrase is the only input" property. Instead, the salt is a
/// protocol constant that scopes the KDF output to Bond; a phrase used
/// for Bond derives a different master seed than the same phrase used
/// for any other protocol that adopts Argon2 with a different salt.
final Uint8List _kBondIdentitySalt =
    Uint8List.fromList(utf8.encode('bond/identity/v1'));

/// A Bond master seed. 32 bytes of cryptographic material that
/// never leaves the user's device and is never used directly on the
/// wire. Only source: [deriveMasterSeed].
///
/// Holding one of these in memory means holding the ability to act as
/// the user in every swarm they participate in. Zero it as soon as
/// subkey derivation is complete.
class MasterSeed {
  MasterSeed._(this._bytes);
  final Uint8List _bytes;

  /// Read-only view of the raw bytes. Callers should not retain
  /// references longer than a single derivation step.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// Best-effort zero of the backing buffer. Dart's VM doesn't give
  /// hard guarantees against copies, but this narrows the window.
  void wipe() {
    for (var i = 0; i < _bytes.length; i++) {
      _bytes[i] = 0;
    }
  }
}

/// Runs Argon2id over the phrase to produce a 32-byte master seed.
///
/// Blocking on the main isolate — at typical parameters this is ~1s,
/// so callers should run on a background isolate (via `compute`) when
/// invoked from UI code. Left synchronous here so the core primitive
/// is isolate-neutral.
MasterSeed deriveMasterSeed(
  String phrase, {
  BondKdfParams params = const BondKdfParams(),
}) {
  if (phrase.isEmpty) {
    throw ArgumentError('Bond phrase cannot be empty');
  }
  final normalisedPhrase =
      Uint8List.fromList(utf8.encode(phrase.trim()));
  final derivator = Argon2BytesGenerator()
    ..init(Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      _kBondIdentitySalt,
      version: Argon2Parameters.ARGON2_VERSION_13,
      iterations: params.iterations,
      memoryPowerOf2: _log2(params.memoryKiB),
      lanes: params.parallelism,
      desiredKeyLength: 32,
    ));
  final out = Uint8List(32);
  derivator.deriveKey(normalisedPhrase, 0, out, 0);
  // Zero the transient buffer immediately.
  for (var i = 0; i < normalisedPhrase.length; i++) {
    normalisedPhrase[i] = 0;
  }
  return MasterSeed._(out);
}

/// A keypair scoped to one Bond swarm. The pubkey is what peers see;
/// the private half signs outgoing Bond messages (ref adverts,
/// proposals, attestations, anchors, policies).
class SwarmKeyPair {
  SwarmKeyPair({
    required this.publicKeyBytes,
    required this.keyPair,
    required this.bondId,
  });

  /// 32-byte Ed25519 public key — the on-wire identity for this swarm.
  final Uint8List publicKeyBytes;

  /// `cryptography` package keypair, used for signing. Wraps the
  /// private key; does not expose raw private material directly.
  final cg.SimpleKeyPair keyPair;

  /// The bond/swarm this keypair is scoped to. Paired-together; the
  /// same master seed + a different bondId yields a different pubkey.
  final Uint8List bondId;
}

/// Info strings are protocol constants. Isolating subkey derivations
/// into named scopes keeps future additions (device subkeys,
/// recovery-material keys, policy-signing subkeys) from colliding with
/// identity output.
const String _kIdentityInSwarmInfoPrefix = 'bond/identity-in-swarm/v1/';

/// Derives the per-swarm Ed25519 keypair for the given [bondId] from
/// a [MasterSeed].
///
/// Determinism: same master + same bondId → same keypair. This is the
/// property that makes "rejoin on a new device" work — the new device
/// enters the phrase, derives the master, derives the same pubkey, and
/// peers recognise them from their local contact books.
Future<SwarmKeyPair> deriveSwarmKeyPair({
  required MasterSeed master,
  required Uint8List bondId,
}) async {
  // HKDF(master, info="bond/identity-in-swarm/v1/" || bondId) → 32 B
  final hkdf = cg.Hkdf(hmac: cg.Hmac.sha256(), outputLength: 32);
  final info = Uint8List.fromList([
    ...utf8.encode(_kIdentityInSwarmInfoPrefix),
    ...bondId,
  ]);
  final ikm = cg.SecretKey(master.bytes);
  final derived = await hkdf.deriveKey(
    secretKey: ikm,
    // No additional per-call salt — master is already phrase-scoped,
    // and we want determinism across devices.
    nonce: const <int>[],
    info: info,
  );
  final seedBytes = Uint8List.fromList(await derived.extractBytes());
  // Ed25519 from a 32-byte seed — the seed IS the private scalar input;
  // the public half is derived by the algorithm.
  final algo = cg.Ed25519();
  final keyPair = await algo.newKeyPairFromSeed(seedBytes);
  final publicKey = await keyPair.extractPublicKey();
  // Wipe the transient seed buffer; the keypair retains its own copy
  // inside the algorithm implementation.
  for (var i = 0; i < seedBytes.length; i++) {
    seedBytes[i] = 0;
  }
  return SwarmKeyPair(
    publicKeyBytes: Uint8List.fromList(publicKey.bytes),
    keyPair: keyPair,
    bondId: bondId,
  );
}

/// ceil(log₂(x)) for positive ints — used to pass memory size as a
/// power-of-two exponent to Argon2.
int _log2(int x) {
  var n = 0;
  var v = x;
  while (v > 1) {
    v >>= 1;
    n++;
  }
  return n;
}
