// ═════════════════════════════════════════════════════════════════════════
// bond/kizuna_transport.dart — Whisper-Kizuna implementation of BondTransport
//
// The membrane binding. Wires kizuna's witness primitive + the 16D
// lattice topology into the [BondTransport] seam that BondBackend
// consumes. This is the file that turns NullBondTransport's "throws on
// dial" into "actually ratchets bytes between peers."
//
// What's complete in this skeleton:
//   • Kizuna handshake-witness derivation (lib/backend/bond/kizuna.dart)
//   • Lattice peer-placement + neighbourhood routing
//     (lib/backend/bond/kizuna_lattice.dart)
//   • [KizunaBondSession] state-stream and lattice-aware metadata
//   • [KizunaBondTransport.joinSwarm] returns a real [BondSwarmHandle]
//     that exposes the lattice membership; tracker WS + WebRTC peer
//     match are stubbed but the surface is shaped to receive them
//
// Out of scope for this skeleton (TODO markers throughout):
//   • The full Loup arithmetic coder (per-message stateful compression
//     + key chain) — substantial port; v1 ships AES-GCM directly
//   • Double Ratchet — the [RatchetStateStore] interface accepts the
//     bytes; serialisation format defined when the ratchet lands
//   • WebRTC plumbing via flutter_webrtc — platform plugin to add
//   • Tracker WSS rendezvous — needs a websocket client + the
//     BitTorrent-tracker offer/answer relay protocol
//
// Each TODO is annotated with the exact Whisper file to mirror; the
// shape here matches so the integration is mechanical when wired.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:typed_data';

import 'kizuna.dart';
import 'kizuna_lattice.dart';
import 'transport.dart';
import 'wire.dart';

/// Production [BondTransport] for Bond — the real network membrane.
/// Construct one per process at app start (in `main.dart`); both
/// [BondBackend] and any direct [connect] callers share the instance.
class KizunaBondTransport implements BondTransport {
  KizunaBondTransport({
    required this.networkSettings,
    required this.phraseProvider,
    required this.ratchetStore,
  });

  /// Tracker URLs, ICE servers, dc-buffered-amount cap.
  final BondNetworkSettings networkSettings;

  /// Phrase lookup callback — invoked on each [dial] / [joinSwarm] so
  /// the phrase stays scoped to whatever holds the unlocked identity
  /// (typically [BondService]). Never cached on this transport.
  final BondPhraseProvider phraseProvider;

  /// Per-peer Double Ratchet state persistence. Used on reconnect so
  /// peers don't have to re-handshake.
  final RatchetStateStore ratchetStore;

  final StreamController<BondSession> _listenCtrl =
      StreamController<BondSession>.broadcast();
  final Map<String, _KizunaSwarmHandle> _swarms = {};

  @override
  Future<BondSession> dial({
    required Uint8List remotePubkey,
    required Uint8List bondId,
    required BondAddressing addressing,
  }) async {
    // TODO(whisper-adapter): this is the directed-dial path — caller
    // already knows who they want to reach. Two sub-paths:
    //   • addressing is BondAddressViaTracker  → tracker rendezvous
    //     (mirror live-tracker.ts:765 runLiveRendezvous), then
    //     run live-handshake.ts handshake, derive kizuna witness, sign
    //     identity claim with our Ed25519 swarm key.
    //   • addressing is BondAddressDirect      → unseal SDP offer
    //     (mirror live-sdp.ts:codeToSdp), answer locally, run
    //     handshake. No tracker round-trip.
    //
    // Until the WebRTC + tracker plumbing lands, surface the gap as a
    // typed StateError instead of throwing UnsupportedError so callers
    // see what's missing.
    final phrase = await phraseProvider(bondId);
    if (phrase.isEmpty) {
      throw StateError('KizunaBondTransport: no swarm phrase for bond');
    }
    final coord = await placePeer(bondId: bondId, peerPubkey: remotePubkey);
    throw StateError(
      'KizunaBondTransport.dial not yet wired — peer at coord '
      '${coord.toHex()} is reachable in principle but the WebRTC + '
      'tracker layer (live.ts/live-tracker.ts/live-handshake.ts) has '
      'not been ported to Dart. Use LoopbackSessionPair for tests.',
    );
  }

  @override
  Future<BondSwarmHandle> joinSwarm({
    required Uint8List bondId,
    required BondAddressing addressing,
  }) async {
    final hex = _hex(bondId);
    final existing = _swarms[hex];
    if (existing != null) return existing;
    final phrase = await phraseProvider(bondId);
    if (phrase.isEmpty) {
      throw StateError('KizunaBondTransport: no swarm phrase for bond');
    }
    final lattice = KizunaLatticeBuilder(bondId: bondId);
    final handle = _KizunaSwarmHandle(
      bondId: bondId,
      lattice: lattice,
      addressing: addressing,
      phrase: phrase,
      networkSettings: networkSettings,
    );
    _swarms[hex] = handle;
    // TODO(whisper-adapter): kick off the tracker announce loop here.
    //   1. derivePhraseRoot(phrase) — same as live-handshake.ts
    //   2. createTrackerPool(networkSettings.trackers, bondId,
    //      derivedInfoHashes(phrase, currentEpoch))
    //   3. for each whisper-intent received:
    //        a. lockPeer + role assignment (compareAttemptOrder)
    //        b. SDP exchange via sealed offer/answer codes
    //        c. handshake → kizuna witness derivation
    //        d. identity-claim verify (peer signs handshake transcript
    //           with their Ed25519 swarm key, we verify against their
    //           claimed pubkey before flipping verifyingIdentity → open)
    //        e. handle.lattice.place(peerPubkey)
    //        f. handle._discoveredCtrl.add(session)
    //   4. respect networkSettings.allowPublicTrackers — if false,
    //      gate the announce on a configured private tracker list.
    return handle;
  }

  @override
  Stream<BondSession> get listen => _listenCtrl.stream;

  @override
  Future<void> close() async {
    for (final swarm in _swarms.values) {
      await swarm.leave();
    }
    _swarms.clear();
    await _listenCtrl.close();
  }
}

/// Per-bond swarm handle. Holds the lattice builder + the tracker
/// announce state (when the tracker is wired). The lattice is what
/// makes this more than a list-of-peers: gossip routing, sub-row
/// sharding, and group-rekey targeting all read from it.
class _KizunaSwarmHandle implements BondSwarmHandle {
  _KizunaSwarmHandle({
    required this.bondId,
    required this.lattice,
    required this.addressing,
    required this.phrase,
    required this.networkSettings,
  });

  @override
  final Uint8List bondId;

  /// Live-mutating lattice. The handle owner ([KizunaBondTransport])
  /// places peers as they're discovered; consumers snapshot for
  /// gossip-routing decisions.
  final KizunaLatticeBuilder lattice;

  final BondAddressing addressing;
  final String phrase;
  final BondNetworkSettings networkSettings;

  final StreamController<BondSession> _discoveredCtrl =
      StreamController<BondSession>.broadcast();
  bool _left = false;

  @override
  Stream<BondSession> get discovered => _discoveredCtrl.stream;

  /// Snapshot the lattice for gossip-routing decisions. Cheap; safe
  /// to call from UI rebuild paths.
  KizunaLatticeSnapshot snapshotLattice() => lattice.snapshot();

  @override
  Future<void> leave() async {
    if (_left) return;
    _left = true;
    // TODO(whisper-adapter): tracker pool cleanup (mirror
    // live-tracker.ts: send "stopped" announces on every active
    // info-hash, close WSS connections, cancel announce timers).
    await _discoveredCtrl.close();
  }
}

/// In-process [BondSession] backed by kizuna witness derivation + a
/// (yet to be wired) Double Ratchet on a WebRTC data channel.
///
/// Used as a typed return shape for the [KizunaBondTransport.dial]
/// path once the underlying WebRTC + handshake pieces land. Until
/// then, kept here so the contract is documented in code, and so the
/// loopback transport's [BondSession] interface stays parallel.
class KizunaBondSession implements BondSession {
  KizunaBondSession({
    required this.sessionId,
    required this.remotePubkey,
    required this.coordinate,
    required this.witnessResidual,
  }) : _stateCtrl = StreamController<BondSessionState>.broadcast(),
       _incomingCtrl = StreamController<BondPacket>.broadcast() {
    _stateCtrl.add(BondSessionState.open);
  }

  @override
  final String sessionId;

  @override
  final Uint8List remotePubkey;

  /// Where the remote peer sits in the lattice. Stable per (bond,
  /// peerPubkey); UI can render the row/column for gossip diagnosis.
  final KizunaCoordinate coordinate;

  /// The kizuna handshake residual computed at session-open time.
  /// Stored so reconnect can short-circuit redundant witness derivation
  /// and so the safety-number widget can render the live witness next
  /// to the long-term identity-pair witness.
  final int witnessResidual;

  final StreamController<BondSessionState> _stateCtrl;
  final StreamController<BondPacket> _incomingCtrl;
  bool _open = true;

  @override
  bool get isOpen => _open;

  @override
  Stream<BondSessionState> get state => _stateCtrl.stream;

  @override
  Stream<BondPacket> get incoming => _incomingCtrl.stream;

  @override
  Future<void> send(BondPacket packet) async {
    if (!_open) throw StateError('KizunaBondSession is closed');
    // TODO(whisper-adapter): real send pipeline:
    //   bytes = [packet.type.tag] ++ packet.body
    //   loopState.encode(bytes)        // live-loop.ts:loopEncode
    //   ratchet.encrypt(loopOut)       // live-ratchet.ts
    //   chunker.iterateChunksPrefixed  // live-chunking.ts
    //   for chunk in chunks: dc.send(chunk)
    //   await dc.bufferedAmountLow when bufferedAmount > 64KB
    throw StateError('KizunaBondSession.send not yet wired');
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    if (!_stateCtrl.isClosed) {
      _stateCtrl.add(BondSessionState.closed);
      await _stateCtrl.close();
    }
    await _incomingCtrl.close();
  }

  /// Kizuna witness as the 4 little-endian bytes used in
  /// `deriveConfirmContextHash`. Exposed for downstream consumers
  /// (safety-number widget, telemetry).
  Uint8List get witnessBytes => residualToWitnessBytes(witnessResidual);

  /// Shorthand for "this session is currently in the open state."
  /// Reads from the cached bool so callers don't need to subscribe to
  /// [state] for a one-shot check.
  bool get isLive => _open;
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
