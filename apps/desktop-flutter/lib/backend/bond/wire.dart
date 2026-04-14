// ═════════════════════════════════════════════════════════════════════════
// bond/wire.dart — packet type tags + framing constants
//
// Every Bond message is one byte of type tag followed by a CBOR-
// encoded payload, all carried inside the Whisper transport's loop-
// decoded plaintext. Whisper owns encryption, chunking, and framing;
// Bond owns the semantic content.
//
// The tag byte is never presumed small — it's a protocol-version
// invariant, not a length hint. New packet types appear as new tag
// values; old tags stay reserved forever.
// ═════════════════════════════════════════════════════════════════════════

/// Wire packet type tags. Transmitted as a single byte immediately
/// after the Whisper-loop plaintext header.
///
/// Values are stable across protocol versions. Adding a new packet
/// type = adding a new enum entry with a fresh byte value. Renaming
/// or renumbering an existing entry is a wire-break and must ship
/// with a version bump and migration.
enum BondPacketType {
  /// JSON control channel — ping, peer-list, capability negotiation.
  /// The one non-CBOR packet type; human-debuggable on the wire.
  ctrl(0x00),

  /// Signed [RefAdvert]. The primary gossip packet — each peer
  /// advertises which commits their refs point at, periodically and
  /// on change.
  refAdvert(0x01),

  /// Compact bitmap or sparse list of git object hashes the sender
  /// locally has. Used to negotiate which objects the recipient needs
  /// before streaming a packfile.
  objectHave(0x02),

  /// List of git object hashes the recipient needs from the sender.
  /// Response to `objectHave` or standalone during initial pull.
  objectWant(0x03),

  /// Git packfile bytes, chunked by the Whisper transport. Stream
  /// content is standard `git pack-objects --stdout` output, piped
  /// into `git index-pack --stdin` on the receiver.
  objectPack(0x04),

  /// Signed Proposal — a recipient-directed ask to adopt a ref.
  proposal(0x05),

  /// Signed Attestation — a verdict on a Proposal (approve, changes,
  /// comment, withdraw).
  attestation(0x06),

  /// Signed Anchor — a comment tied to a specific git object
  /// (commit / tree / blob / line range). Redundant with the
  /// `refs/notes/bond/anchors/*` sync path but faster for live
  /// delivery of new anchors within an active session.
  anchor(0x07),

  /// Signed Target — an unfulfilled intent that proposals can
  /// consume. Bond's issue-equivalent primitive.
  target(0x08),

  /// Signed Policy — consensus rules (which refs need how many
  /// attestations from which signers) that the gossip boundary
  /// enforces when adopting incoming ref advertisements.
  policy(0x09),

  /// Signed continuity attestation — identity rotation. Asserts
  /// `new_pubkey = old_pubkey` when both signatures are present; lets
  /// peers preserve label + reputation lineage across a key change.
  continuity(0x0A),

  /// Signed revocation — master-key or device-key revocation.
  /// Received peers stop accepting signed content from the revoked
  /// key from `effective_at` forward.
  revoke(0x0B);

  const BondPacketType(this.tag);

  /// Byte value on the wire.
  final int tag;

  /// Parse a wire tag byte. Returns `null` for unknown tags — callers
  /// should treat unknown as "forward-compatible, skip silently"
  /// rather than as an error, so old clients can receive newer
  /// traffic without connection drops.
  static BondPacketType? fromTag(int tag) {
    for (final t in BondPacketType.values) {
      if (t.tag == tag) return t;
    }
    return null;
  }
}

/// Current protocol version. Incremented when wire layout changes
/// incompatibly. Identity-phrase derivation and bond_id derivation
/// include `v1`-style scoped info strings independently, so this
/// version bump is strictly about packet framing and CBOR schemas.
const int kBondProtocolVersion = 1;

/// Hard ceiling on a single CBOR payload in bytes. Above this, the
/// sender must split into multiple packets (e.g. a huge packfile
/// chunked via `objectPack` repeats) rather than stuffing into one.
/// The Whisper transport already chunks at 15 KB per data-channel
/// frame; this higher ceiling is the CBOR-object ceiling before
/// application-level chunking kicks in.
const int kMaxBondPayloadBytes = 4 * 1024 * 1024;
