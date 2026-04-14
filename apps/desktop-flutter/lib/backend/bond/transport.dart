// ═════════════════════════════════════════════════════════════════════════
// bond/transport.dart — the peer-session abstraction
//
// Bond's cryptographic + object layers are transport-agnostic. This
// interface is what the session layer above uses, and what a Whisper
// adapter (or any future transport) implements below.
//
// v1 ships with a LoopbackTransport — two BondSessions that deliver
// each other's packets in-process — for tests and local integration.
// The real WebRTC+Whisper transport lands as a separate file
// implementing the same BondTransport contract.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:typed_data';

import 'wire.dart';

/// One end of a two-party Bond conversation. Send packets out,
/// receive packets in via [incoming]. Symmetric — offerer and
/// answerer see identical API shapes; the handshake-role distinction
/// lives below this interface in the Whisper-adapter layer.
abstract interface class BondSession {
  /// Stable identifier for this session — ideally the remote peer's
  /// swarm pubkey hex. Used for logging and for routing replies back
  /// to the originating session.
  String get sessionId;

  /// Pubkey of the remote peer. 32 bytes, Ed25519. Populated once
  /// the handshake completes and the remote's identity is confirmed.
  Uint8List get remotePubkey;

  /// True when the session is ready to send + receive. Set by the
  /// transport implementation after handshake completion; flips back
  /// to false on disconnect.
  bool get isOpen;

  /// Broadcast stream of packets the peer sent us. Subscribing
  /// multiple listeners is allowed; packets dispatch to all of them.
  /// The stream closes when [close] is called or the transport
  /// terminates.
  Stream<BondPacket> get incoming;

  /// Send a packet to the peer. Returns when the packet is queued
  /// locally (not when the peer has acked it). Throws if the session
  /// is closed.
  Future<void> send(BondPacket packet);

  /// Tear down the session. Idempotent; safe to call multiple times.
  Future<void> close();
}

/// A packet observed on the Bond wire, with its type tag pre-parsed
/// and its body bytes delivered opaque for the appropriate decoder.
class BondPacket {
  BondPacket({required this.type, required this.body});

  /// Parsed packet type. Packets with unknown tags are delivered
  /// anyway with [type] = null so downstream can log + skip rather
  /// than the transport dropping them silently.
  final BondPacketType? type;

  /// Remainder of the plaintext after the 1-byte type tag. Decoding
  /// is the caller's job — they know which CBOR schema applies.
  final Uint8List body;
}

/// Transport-level abstraction a Bond session manager asks to open
/// or accept sessions. One instance per running Manifold process;
/// sessions multiplex through it.
abstract interface class BondTransport {
  /// Open a session with a remote identified by swarm pubkey,
  /// reachable via transport-specific addressing. Returns a
  /// [BondSession] once the handshake completes. Throws on
  /// unreachable peer or handshake failure.
  Future<BondSession> dial({
    required Uint8List remotePubkey,
    required Uint8List bondId,
    required Object addressing,
  });

  /// Stream of inbound sessions. Fires when a remote peer dials us
  /// and the handshake completes. The consumer (session manager)
  /// is responsible for retaining or closing each session.
  Stream<BondSession> get listen;

  /// Shut down the transport. All active sessions are closed.
  Future<void> close();
}

/// In-process loopback transport. Two sessions back-to-back — send
/// on one, receive on the other. No crypto, no chunking; exists so
/// the session manager and BondBackend can be exercised under unit
/// tests before the Whisper adapter is available.
class LoopbackSessionPair {
  LoopbackSessionPair._(this.alice, this.bob);

  /// A paired set of sessions. Packets sent by [alice] arrive on
  /// [bob.incoming] and vice versa.
  final BondSession alice;
  final BondSession bob;

  factory LoopbackSessionPair.create({
    required Uint8List alicePubkey,
    required Uint8List bobPubkey,
  }) {
    final aliceToBob = StreamController<BondPacket>.broadcast();
    final bobToAlice = StreamController<BondPacket>.broadcast();
    final aliceSession = _LoopbackSession(
      sessionId: 'loopback:alice',
      remotePubkey: bobPubkey,
      outbound: aliceToBob,
      inboundStream: bobToAlice.stream,
      partner: () => (_, __, ___) {}, // set below
    );
    final bobSession = _LoopbackSession(
      sessionId: 'loopback:bob',
      remotePubkey: alicePubkey,
      outbound: bobToAlice,
      inboundStream: aliceToBob.stream,
      partner: () => (_, __, ___) {},
    );
    return LoopbackSessionPair._(aliceSession, bobSession);
  }
}

class _LoopbackSession implements BondSession {
  _LoopbackSession({
    required this.sessionId,
    required this.remotePubkey,
    required this.outbound,
    required Stream<BondPacket> inboundStream,
    // ignore: unused_element_parameter
    required Function Function() partner,
  }) : _inbound = inboundStream;

  @override
  final String sessionId;

  @override
  final Uint8List remotePubkey;

  final StreamController<BondPacket> outbound;
  final Stream<BondPacket> _inbound;

  bool _open = true;

  @override
  bool get isOpen => _open && !outbound.isClosed;

  @override
  Stream<BondPacket> get incoming => _inbound;

  @override
  Future<void> send(BondPacket packet) async {
    if (!isOpen) {
      throw StateError('LoopbackSession $sessionId is closed');
    }
    outbound.add(packet);
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    await outbound.close();
  }
}
