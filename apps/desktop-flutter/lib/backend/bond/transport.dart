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
//
// Reconnect contract (important for adapter implementers):
//   A dropped peer does NOT flip its existing BondSession's isOpen
//   back to true. Instead, a fresh BondSession is emitted on
//   [BondTransport.listen] (or returned from a re-dial) with the
//   SAME `remotePubkey`. The prior session's `incoming` stream
//   closes and `isOpen` reads false thereafter. Backend callers
//   replace the peer entry by pubkey; PeerSession teardown + re-
//   attach is their responsibility, not the transport's.
//
// Chunking contract:
//   One `send(packet)` produces exactly one `incoming` event on the
//   remote. The transport may split the body across data-channel
//   frames internally, but boundaries are preserved end-to-end.
//
// Backpressure:
//   `send` resolves when the transport buffer has accepted the
//   packet AND the underlying channel's buffered-amount is below
//   the transport's chosen threshold — callers can treat successive
//   awaits as flow-controlled.
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

  /// Fine-grained handshake + liveness state — UIs subscribe to
  /// render "connecting… handshaking… verifying peer… open". Emits
  /// the current state immediately on subscription and on every
  /// transition. [isOpen] is a convenience derived from this stream.
  Stream<BondSessionState> get state;

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

/// Session lifecycle states. Coarse enough to render as UI chrome
/// (one icon / color per state), fine enough that adapter authors
/// don't have to invent private enums.
enum BondSessionState {
  /// Signaling / tracker announce / ICE gathering.
  dialing,

  /// Whisper handshake (ECDH + Kizuna + ratchet init) running.
  handshaking,

  /// Handshake succeeded; verifying the signed-envelope binding of
  /// the remote Ed25519 swarm pubkey to the ephemeral ECDH key.
  verifyingIdentity,

  /// Session ready for application packets.
  open,

  /// Lost transport; adapter will emit a fresh session on success.
  reconnecting,

  /// Session is done. Stream-terminal.
  closed,
}

/// Addressing sum — how to reach a peer. Each variant maps to a
/// different Whisper-adapter code path. The `Object` escape hatch
/// previously baked into `dial()` is replaced by this sealed type so
/// the adapter can switch on it exhaustively.
sealed class BondAddressing {
  const BondAddressing();
}

/// Tracker-rendezvous addressing — the standard path. The adapter
/// derives the tracker topic from the bond_id + swarm phrase, matches
/// on the topic, then exchanges SDP via the tracker channel.
class BondAddressViaTracker extends BondAddressing {
  const BondAddressViaTracker({
    required this.trackers,
    this.iceServers = const [],
    this.roleHint,
  });

  /// Tracker URLs — typically WSS. Concatenated with the network
  /// settings' configured trackers; this is an override slot.
  final List<String> trackers;

  /// STUN/TURN servers. Empty = adapter defaults (public STUN).
  final List<String> iceServers;

  /// Optional: 'offerer' / 'answerer' hint when the caller wants to
  /// force a role (e.g., in test harnesses). Null = auto-negotiate.
  final String? roleHint;
}

/// Direct-SDP addressing — out-of-band SDP handoff (e.g. user
/// pasted a peer's offer code from a QR). Skips tracker.
class BondAddressDirect extends BondAddressing {
  const BondAddressDirect({required this.sdpOffer});
  final String sdpOffer;
}

/// Network-wide transport configuration. Built from user settings
/// and passed to the adapter at construction, not at each dial.
class BondNetworkSettings {
  const BondNetworkSettings({
    this.trackers = const <String>[
      'wss://tracker.openwebtorrent.com',
      'wss://tracker.btorrent.xyz',
    ],
    this.iceServers = const <String>[
      'stun:stun.l.google.com:19302',
    ],
    this.allowPublicTrackers = true,
    this.dcMaxBufferedBytes = 64 * 1024,
  });

  final List<String> trackers;
  final List<String> iceServers;
  final bool allowPublicTrackers;

  /// Backpressure threshold. `send()` blocks when the underlying
  /// data channel's bufferedAmount exceeds this.
  final int dcMaxBufferedBytes;
}

/// Provider callback signature: given a bond_id, return the swarm
/// phrase. The Whisper adapter uses the phrase to derive the tracker
/// topic and handshake context. Kept as a callback (not a constant)
/// so the phrase stays lifetime-scoped to the unlocked session
/// instead of sitting in transport singletons.
typedef BondPhraseProvider = Future<String> Function(Uint8List bondId);

/// Persistence for per-peer Double Ratchet state. Whisper's ratchet
/// must survive reconnect to avoid re-handshakes (and to preserve
/// forward-secrecy against replay). The transport doesn't touch
/// BondStore directly; it calls this interface so tests can stub
/// with in-memory storage and storage layout can evolve
/// independently of the wire.
abstract interface class RatchetStateStore {
  Future<Uint8List?> load(Uint8List bondId, Uint8List peerPubkey);
  Future<void> save(
    Uint8List bondId,
    Uint8List peerPubkey,
    Uint8List stateBytes,
  );
  Future<void> erase(Uint8List bondId, Uint8List peerPubkey);
}

/// Handle on an active swarm membership. Fires a [discovered]
/// session each time a peer in the same bond matches us on the
/// tracker and the handshake + identity-verification completes.
abstract interface class BondSwarmHandle {
  Uint8List get bondId;

  /// New sessions in the order they appear.
  Stream<BondSession> get discovered;

  /// Leave the swarm — stop announcing, stop accepting new peers.
  /// Existing sessions survive until their own [BondSession.close].
  Future<void> leave();
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
    required BondAddressing addressing,
  });

  /// Announce presence on the bond's rendezvous channel and accept
  /// inbound peer matches. One call per bond (the backend dedups);
  /// the returned handle's [BondSwarmHandle.discovered] stream is
  /// how the backend learns about peers it didn't dial.
  Future<BondSwarmHandle> joinSwarm({
    required Uint8List bondId,
    required BondAddressing addressing,
  });

  /// Stream of inbound sessions NOT scoped to a specific bond — the
  /// direct-SDP / invite-code path lives here. Most sessions flow
  /// through [joinSwarm] instead.
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

/// Stand-in [BondTransport] used before the Whisper adapter is wired.
/// Every method fails fast or stays quiet; exists so the rest of the
/// stack (BondService, BondBackend) can be constructed at process
/// start without crashing. Swap for the Whisper adapter once it lands.
class NullBondTransport implements BondTransport {
  const NullBondTransport();

  @override
  Future<BondSession> dial({
    required Uint8List remotePubkey,
    required Uint8List bondId,
    required BondAddressing addressing,
  }) async {
    throw UnsupportedError(
      'NullBondTransport: no real transport wired. Integrate Whisper '
      'or inject a LoopbackSessionPair in tests.',
    );
  }

  @override
  Future<BondSwarmHandle> joinSwarm({
    required Uint8List bondId,
    required BondAddressing addressing,
  }) async {
    return _NullSwarmHandle(bondId: bondId);
  }

  @override
  Stream<BondSession> get listen {
    return const Stream<BondSession>.empty().asBroadcastStream();
  }

  @override
  Future<void> close() async {}
}

class _NullSwarmHandle implements BondSwarmHandle {
  _NullSwarmHandle({required this.bondId});
  @override
  final Uint8List bondId;
  @override
  Stream<BondSession> get discovered =>
      const Stream<BondSession>.empty().asBroadcastStream();
  @override
  Future<void> leave() async {}
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
  final StreamController<BondSessionState> _state =
      StreamController<BondSessionState>.broadcast();

  bool _open = true;

  @override
  bool get isOpen => _open && !outbound.isClosed;

  @override
  Stream<BondPacket> get incoming => _inbound;

  @override
  Stream<BondSessionState> get state {
    // Loopback "handshake" completes instantly. Emit the terminal
    // open state so subscribers see a value, and close() pushes
    // [closed] before terminating the stream.
    final ctrl = StreamController<BondSessionState>();
    scheduleMicrotask(() {
      ctrl.add(_open ? BondSessionState.open : BondSessionState.closed);
      _state.stream.listen(ctrl.add, onDone: ctrl.close);
    });
    return ctrl.stream;
  }

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
    if (!_state.isClosed) {
      _state.add(BondSessionState.closed);
      await _state.close();
    }
    await outbound.close();
  }
}
