// ═════════════════════════════════════════════════════════════════════════
// bond/peer_session.dart — envelope-aware wrapper around a BondSession
//
// Transport ([BondSession]) delivers raw [BondPacket]s — type tag +
// body bytes. Most Bond packet types carry a [SignedEnvelope] as the
// body (refAdvert, proposal, attestation, anchor, target, policy,
// continuity, revoke). A handful don't: ctrl is JSON, objectHave /
// objectWant / objectPack are transport metadata and raw packfile
// bytes.
//
// [PeerSession] owns the common work: sign + frame outbound signed
// primitives, decode + verify inbound ones, and fan verified objects
// out to typed streams the [BondBackend] subscribes to. It also keeps
// the per-peer "last seen" timestamp fresh in [BondStore] so reconnect
// logic and UI staleness indicators have ground truth.
//
// Handshake-level work (ECDH, Double Ratchet, Whisper loop) lives in
// the underlying [BondSession] — this layer assumes `isOpen == true`
// means "plaintext frames move in both directions."
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cg;

import 'bond_id.dart';
import 'objects.dart';
import 'signed_envelope.dart';
import 'storage.dart';
import 'transport.dart';
import 'wire.dart';

/// One connected peer, one bond.
///
/// Lifecycle: construct around a live [BondSession], call [start] once
/// to begin consuming the incoming stream, call [close] to tear down.
/// After [close], typed streams are closed and further `send*` calls
/// throw.
class PeerSession {
  PeerSession({
    required this.session,
    required this.bondId,
    required this.store,
    required this.signingKeyPair,
    required this.signerPublicKey,
  });

  /// The underlying transport session. Owned by this PeerSession once
  /// constructed — [close] on PeerSession closes it.
  final BondSession session;

  /// Which bond this session operates within. Mismatched-bond packets
  /// from the peer are dropped at verification time.
  final BondId bondId;

  /// Persistence seam for last-seen, peers.jsonl, etc.
  final BondStore store;

  /// Our identity keypair in this bond. Used for signing outbound
  /// envelopes.
  final cg.SimpleKeyPair signingKeyPair;

  /// Our 32-byte Ed25519 public key. Stamped into outbound envelopes
  /// as the signer. Must match [signingKeyPair]'s public key.
  final Uint8List signerPublicKey;

  final StreamController<RefAdvert> _refAdverts =
      StreamController<RefAdvert>.broadcast();
  final StreamController<Proposal> _proposals =
      StreamController<Proposal>.broadcast();
  final StreamController<Attestation> _attestations =
      StreamController<Attestation>.broadcast();
  final StreamController<Anchor> _anchors =
      StreamController<Anchor>.broadcast();
  final StreamController<Target> _targets =
      StreamController<Target>.broadcast();
  final StreamController<Policy> _policies =
      StreamController<Policy>.broadcast();
  final StreamController<Uint8List> _packfiles =
      StreamController<Uint8List>.broadcast();
  final StreamController<Map<String, dynamic>> _ctrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<PeerSessionError> _errors =
      StreamController<PeerSessionError>.broadcast();

  StreamSubscription<BondPacket>? _sub;
  bool _started = false;
  bool _closed = false;

  /// Signed ref advertisements the peer sent us, already
  /// signature-verified. Bond-id match is enforced before emission.
  Stream<RefAdvert> get refAdverts => _refAdverts.stream;

  /// Verified Proposals from the peer.
  Stream<Proposal> get proposals => _proposals.stream;

  /// Verified Attestations from the peer.
  Stream<Attestation> get attestations => _attestations.stream;

  /// Verified Anchors (live delivery path; note-ref storage is the
  /// durable path handled elsewhere).
  Stream<Anchor> get anchors => _anchors.stream;

  /// Verified Targets.
  Stream<Target> get targets => _targets.stream;

  /// Verified Policies.
  Stream<Policy> get policies => _policies.stream;

  /// Raw packfile-bytes chunks in the order delivered by the transport.
  /// Re-assembly into a whole packfile is the caller's responsibility
  /// (the transport already re-assembled fragments of one packet; what
  /// this stream emits is one complete [BondPacketType.objectPack]
  /// payload per event).
  Stream<Uint8List> get packfiles => _packfiles.stream;

  /// JSON control-channel messages. The only non-CBOR packet type.
  Stream<Map<String, dynamic>> get ctrl => _ctrl.stream;

  /// Non-fatal decode / verify failures. Subscribers log + continue;
  /// transport stays open so a single bad packet doesn't drop the
  /// session.
  Stream<PeerSessionError> get errors => _errors.stream;

  /// Start consuming the underlying session's packet stream. Must be
  /// called exactly once; subsequent calls no-op.
  void start() {
    if (_started || _closed) return;
    _started = true;
    _sub = session.incoming.listen(
      _onPacket,
      onError: (Object err, StackTrace st) {
        _errors.add(PeerSessionError(
          reason: 'transport_error',
          detail: err.toString(),
        ));
      },
      onDone: () {
        // Transport closed from below — mirror that into our streams.
        close();
      },
    );
    unawaited(_recordSeen());
  }

  Future<void> _onPacket(BondPacket packet) async {
    final type = packet.type;
    if (type == null) {
      // Forward-compatible skip: unknown tags are legal.
      return;
    }
    try {
      switch (type) {
        case BondPacketType.ctrl:
          final decoded = jsonDecode(utf8.decode(packet.body));
          if (decoded is Map<String, dynamic>) {
            _ctrl.add(decoded);
          }
          return;
        case BondPacketType.objectPack:
          _packfiles.add(packet.body);
          return;
        case BondPacketType.objectHave:
        case BondPacketType.objectWant:
          // Transfer-negotiation primitives — not envelope-wrapped.
          // The BondBackend handles these via dedicated streams on
          // the backend layer; for now just surface as ctrl-like
          // records for logging.
          _ctrl.add(<String, dynamic>{
            't': type.name,
            'len': packet.body.length,
          });
          return;
        case BondPacketType.refAdvert:
        case BondPacketType.proposal:
        case BondPacketType.attestation:
        case BondPacketType.anchor:
        case BondPacketType.target:
        case BondPacketType.policy:
        case BondPacketType.continuity:
        case BondPacketType.revoke:
          break;
      }

      final parse = decodeEnvelope(packet.body);
      if (!parse.ok) {
        _errors.add(PeerSessionError(
          reason: 'envelope_parse',
          detail: parse.error ?? 'unknown',
        ));
        return;
      }
      final env = parse.envelope!;
      if (env.kind != type.name) {
        _errors.add(const PeerSessionError(
          reason: 'kind_tag_mismatch',
          detail: 'envelope kind != packet tag',
        ));
        return;
      }
      final verdict = await verifyEnvelope(env);
      if (!verdict.ok) {
        _errors.add(PeerSessionError(
          reason: 'verify_failed',
          detail: verdict.error ?? 'unknown',
        ));
        return;
      }
      _dispatch(type, env);
    } catch (e) {
      _errors.add(PeerSessionError(
        reason: 'dispatch_exception',
        detail: e.toString(),
      ));
    }
  }

  void _dispatch(BondPacketType type, SignedEnvelope env) {
    switch (type) {
      case BondPacketType.refAdvert:
        final obj = RefAdvert.tryDecode(env.body);
        if (obj == null) {
          _errors.add(const PeerSessionError(
            reason: 'body_decode',
            detail: 'refAdvert',
          ));
          return;
        }
        if (!_bondIdMatches(obj.bondId)) return;
        _refAdverts.add(obj);
      case BondPacketType.proposal:
        final obj = Proposal.tryDecode(env.body);
        if (obj == null) {
          _errors.add(const PeerSessionError(
            reason: 'body_decode',
            detail: 'proposal',
          ));
          return;
        }
        if (!_bondIdMatches(obj.bondId)) return;
        _proposals.add(obj);
      case BondPacketType.attestation:
        final obj = Attestation.tryDecode(env.body);
        if (obj == null) {
          _errors.add(const PeerSessionError(
            reason: 'body_decode',
            detail: 'attestation',
          ));
          return;
        }
        if (!_bondIdMatches(obj.bondId)) return;
        _attestations.add(obj);
      case BondPacketType.anchor:
        final obj = Anchor.tryDecode(env.body);
        if (obj == null) {
          _errors.add(const PeerSessionError(
            reason: 'body_decode',
            detail: 'anchor',
          ));
          return;
        }
        if (!_bondIdMatches(obj.bondId)) return;
        _anchors.add(obj);
      case BondPacketType.target:
        final obj = Target.tryDecode(env.body);
        if (obj == null) {
          _errors.add(const PeerSessionError(
            reason: 'body_decode',
            detail: 'target',
          ));
          return;
        }
        if (!_bondIdMatches(obj.bondId)) return;
        _targets.add(obj);
      case BondPacketType.policy:
        final obj = Policy.tryDecode(env.body);
        if (obj == null) {
          _errors.add(const PeerSessionError(
            reason: 'body_decode',
            detail: 'policy',
          ));
          return;
        }
        if (!_bondIdMatches(obj.bondId)) return;
        _policies.add(obj);
      case BondPacketType.continuity:
      case BondPacketType.revoke:
        // Identity-management primitives — route to errors for now;
        // full handling is wired at the identity-service layer which
        // owns continuity lineage. Logging them preserves observability
        // until that lands.
        _ctrl.add(<String, dynamic>{
          't': type.name,
          'signer':
              env.signerPublicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        });
      case BondPacketType.ctrl:
      case BondPacketType.objectHave:
      case BondPacketType.objectWant:
      case BondPacketType.objectPack:
        // Already handled above.
        break;
    }
  }

  bool _bondIdMatches(Uint8List other) {
    if (other.length != bondId.bytes.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (other[i] != bondId.bytes[i]) return false;
    }
    return true;
  }

  /// Sign + send a body under the given kind. The kind must match a
  /// packet type whose on-wire form is a [SignedEnvelope] body — if
  /// you pass [BondPacketType.ctrl] or any non-envelope type this
  /// throws synchronously.
  Future<void> sendSigned(BondPacketType kind, Uint8List bodyCbor) async {
    _ensureOpen();
    if (!_isEnvelopeKind(kind)) {
      throw ArgumentError(
        'sendSigned requires an envelope-wrapped packet type; got ${kind.name}',
      );
    }
    final env = await signEnvelope(
      keyPair: signingKeyPair,
      signerPublicKey: signerPublicKey,
      kind: kind,
      bodyCbor: bodyCbor,
    );
    final bytes = encodeEnvelope(env);
    if (bytes.length > kMaxBondPayloadBytes) {
      throw StateError(
        'encoded envelope exceeds kMaxBondPayloadBytes (${bytes.length})',
      );
    }
    await session.send(BondPacket(type: kind, body: bytes));
  }

  /// Send a raw (non-envelope) packet — ctrl JSON, objectHave /
  /// objectWant bitmaps, or an objectPack chunk.
  Future<void> sendRaw(BondPacketType kind, Uint8List body) async {
    _ensureOpen();
    if (_isEnvelopeKind(kind)) {
      throw ArgumentError(
        'sendRaw rejects envelope-wrapped packet types; use sendSigned',
      );
    }
    await session.send(BondPacket(type: kind, body: body));
  }

  /// Convenience: emit a JSON object on the ctrl channel.
  Future<void> sendCtrl(Map<String, dynamic> message) async {
    await sendRaw(
      BondPacketType.ctrl,
      Uint8List.fromList(utf8.encode(jsonEncode(message))),
    );
  }

  bool _isEnvelopeKind(BondPacketType kind) {
    switch (kind) {
      case BondPacketType.refAdvert:
      case BondPacketType.proposal:
      case BondPacketType.attestation:
      case BondPacketType.anchor:
      case BondPacketType.target:
      case BondPacketType.policy:
      case BondPacketType.continuity:
      case BondPacketType.revoke:
        return true;
      case BondPacketType.ctrl:
      case BondPacketType.objectHave:
      case BondPacketType.objectWant:
      case BondPacketType.objectPack:
        return false;
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('PeerSession ${session.sessionId} is closed');
    }
    if (!session.isOpen) {
      throw StateError(
        'PeerSession ${session.sessionId} underlying transport is not open',
      );
    }
  }

  Future<void> _recordSeen() async {
    try {
      await store.ensureBondDirs(bondId);
      final hex = session.remotePubkey
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await appendJsonl(store.peersPathFor(bondId), <String, dynamic>{
        'pubkey': hex,
        'seen_ms': DateTime.now().millisecondsSinceEpoch,
        'session': session.sessionId,
      });
    } catch (e) {
      _errors.add(PeerSessionError(
        reason: 'store_write',
        detail: e.toString(),
      ));
    }
  }

  /// Tear down the session and close all typed streams. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    _sub = null;
    await session.close();
    await _refAdverts.close();
    await _proposals.close();
    await _attestations.close();
    await _anchors.close();
    await _targets.close();
    await _policies.close();
    await _packfiles.close();
    await _ctrl.close();
    await _errors.close();
  }
}

/// Non-fatal error surfaced on [PeerSession.errors]. Subscribers
/// typically log and continue; the session stays open so a single bad
/// packet doesn't drop the peer.
class PeerSessionError {
  const PeerSessionError({required this.reason, required this.detail});

  /// Short machine-readable reason code. One of:
  /// `"envelope_parse"`, `"kind_tag_mismatch"`, `"verify_failed"`,
  /// `"body_decode"`, `"dispatch_exception"`, `"transport_error"`,
  /// `"store_write"`.
  final String reason;

  /// Longer human-facing detail. Safe to log; may contain the peer's
  /// pubkey hex or a decoded error string.
  final String detail;

  @override
  String toString() => 'PeerSessionError($reason: $detail)';
}
