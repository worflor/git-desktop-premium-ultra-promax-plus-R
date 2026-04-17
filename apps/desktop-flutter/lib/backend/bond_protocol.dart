// BOND PROTOCOL — peer-to-peer handshake decisions.
//
// Two machines each have a LogosGit engine. Each computes:
//   (a) a KizunaBond25D (a 25-coefficient fingerprint of joint
//       file × commit structure)
//   (b) a LogosState signature + monotonic revision
//
// They exchange (a) and (b) over some transport (websocket, WebRTC,
// gossip — not this file's problem). Then each side asks:
//
//   "given my bond, my state, the peer's bond, and the peer's state,
//    what should I do next?"
//
// That's the `decideBondSync` function. It is pure — no I/O, no
// transport, no mutation. It returns a [BondSyncDecision] that the
// caller turns into UI or transport actions.
//
// The protocol primitives are:
//   - KizunaBond25D — chemistry of the peer's repo, compact (216 bytes
//     on the wire via `toBytes` / `fromBytes`)
//   - classifyBondPair — 4-way relation: identical / compatible /
//     related / divergent
//   - LogosState signature + revision — identity of the peer's
//     spectral snapshot, for deciding who's ahead
//
// Out of scope for this file: transport framing, authentication,
// encryption, conflict resolution, UI.

import 'dart:typed_data';

import 'logos_core.dart';
import 'spectral_kizuna.dart';

/// Packet a peer sends when opening a bond handshake. Exactly three
/// small fields; the full binary form is 216 bytes (bond) + 8 bytes
/// (Signature) + 8 bytes (revision int64) = 232 bytes. Actual wire
/// framing is the transport's responsibility.
class BondHandshakePacket {
  const BondHandshakePacket({
    required this.bond,
    required this.stateSignature,
    required this.revision,
  });

  /// The peer's Kizuna bond.
  final KizunaBond25D bond;

  /// The peer's LogosState.signature — opaque 62-bit identity of
  /// their full spectral snapshot, carried as a web-safe [Signature]
  /// value (two 31-bit halves).
  final Signature stateSignature;

  /// The peer's LogosRatchet.revision — monotonic counter that
  /// says which state is "ahead" when two bonds are compatible.
  final int revision;

  /// Total byte length when serialised.
  static const int wireSize = 232;

  /// Serialise to wire bytes. Layout:
  ///   [0..216)    bond (KizunaBond25D.toBytes)
  ///   [216..224)  state signature (Signature.writeBytes — lo/hi uint32)
  ///   [224..232)  revision as (lo, hi) int32 pair (two's complement)
  Uint8List toBytes() {
    final bondBytes = bond.toBytes();
    assert(bondBytes.length == 216);
    final out = Uint8List(wireSize);
    out.setRange(0, 216, bondBytes);
    final bd = ByteData.view(out.buffer, out.offsetInBytes, wireSize);
    stateSignature.writeBytes(bd, 216);
    // Revision is a monotonic counter; int32 pair handles negative
    // values too (two's complement via setInt32 on both halves).
    bd.setInt32(224, revision & 0xffffffff, Endian.little);
    final revHi = revision >= 0 ? revision ~/ 0x100000000 : -1;
    bd.setInt32(228, revHi & 0xffffffff, Endian.little);
    return out;
  }

  /// Reconstruct from wire bytes produced by [toBytes]. Throws
  /// [FormatException] on length mismatch or bad bond payload.
  factory BondHandshakePacket.fromBytes(Uint8List bytes) {
    if (bytes.length != wireSize) {
      throw FormatException(
        'BondHandshakePacket.fromBytes: expected $wireSize bytes, '
        'got ${bytes.length}',
      );
    }
    final bondBytes = Uint8List.view(bytes.buffer, bytes.offsetInBytes, 216);
    final bond = KizunaBond25D.fromBytes(bondBytes);
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, wireSize);
    final stateSig = Signature.readBytes(bd, 216);
    final revLo = bd.getUint32(224, Endian.little);
    final revHiSigned = bd.getInt32(228, Endian.little);
    final rev = revHiSigned * 0x100000000 + revLo;
    return BondHandshakePacket(
      bond: bond,
      stateSignature: stateSig,
      revision: rev,
    );
  }
}

/// What a node should do after exchanging handshake packets. These
/// are the cardinal outcomes the protocol expresses; the caller
/// translates them into concrete transport actions.
enum BondSyncDecision {
  /// Both sides have the exact same spectral state. No sync needed.
  /// Identical bond + identical state signature.
  identicalSkip,

  /// Bonds compatible and peer revision is higher. Pull their changes.
  pullFromPeer,

  /// Bonds compatible and local revision is higher. Push our changes.
  pushToPeer,

  /// Bonds compatible, revisions tied (both updated independently).
  /// Caller should run a state-diff-based merge.
  mergeBidirectional,

  /// Bonds related but not compatible — partial overlap. Caller should
  /// surface the situation to the user rather than auto-sync.
  askUser,

  /// Bonds divergent — different repos or very divergent states.
  /// Decline to sync.
  divergentSkip,
}

/// Given local and peer handshake packets, decide the next action.
///
/// Pure function: no I/O, no transport, no mutation. Deterministic for
/// deterministic inputs — two peers running this independently arrive
/// at compatible decisions (one pulls while the other pushes, both see
/// identical when signatures match, etc.).
BondSyncDecision decideBondSync({
  required KizunaBond25D localBond,
  required Signature localStateSignature,
  required int localRevision,
  required KizunaBond25D peerBond,
  required Signature peerStateSignature,
  required int peerRevision,
}) {
  final classification = classifyBondPair(localBond, peerBond);

  // If the state signatures match exactly, the two spectra are
  // identical regardless of what the bond says — skip. Bond classifier
  // may say `identical` here but also `compatible` if there's minor
  // bond-level drift with the same underlying spectra; either way,
  // equal state signature ⇒ no sync needed.
  if (localStateSignature == peerStateSignature &&
      classification == KizunaBondCompatibility.identical) {
    return BondSyncDecision.identicalSkip;
  }

  switch (classification) {
    case KizunaBondCompatibility.identical:
      // Bond identical but state signatures differ (rare, happens
      // when bond has less entropy than full state). Fall through
      // to revision compare.
      return _revisionDecision(localRevision, peerRevision);

    case KizunaBondCompatibility.compatible:
      return _revisionDecision(localRevision, peerRevision);

    case KizunaBondCompatibility.related:
      return BondSyncDecision.askUser;

    case KizunaBondCompatibility.divergent:
      return BondSyncDecision.divergentSkip;
  }
}

BondSyncDecision _revisionDecision(int localRevision, int peerRevision) {
  if (peerRevision > localRevision) return BondSyncDecision.pullFromPeer;
  if (peerRevision < localRevision) return BondSyncDecision.pushToPeer;
  return BondSyncDecision.mergeBidirectional;
}

