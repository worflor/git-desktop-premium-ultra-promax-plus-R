// ═════════════════════════════════════════════════════════════════════════
// bond/bond_backend.dart — CollaborationBackend over Bond transport
//
// Bridges Manifold's git-collaboration surfaces (fetch/pull/push/sync
// buttons, branches panel, review UI) to the Bond peer-to-peer stack.
// Implements the same interface as GitHubBackend; the UI doesn't
// distinguish which backend it's calling.
//
// Operating model per repo:
//   • One resolved BondId (from repo config or derived from bootstrap
//     commit + swarm phrase).
//   • One [SwarmKeyPair] (cached from master seed at identity unlock).
//   • A fleet of [PeerSession]s, each with a connected peer. Dial on
//     demand; keep open sessions warm so ref adverts arrive push-style.
//
// Remote parameter on CollaborationBackend methods is interpreted as a
// bond name (not a URL). For single-bond repos it's optional. Branch
// parameter maps to a local ref name — Bond's namespace for other
// peers' work is `refs/bond/<pubkey_hex>/<ref>`, so "merge from peer
// X's main" reads `refs/bond/<x>/heads/main`.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../collaboration_backend.dart';
import '../dtos.dart';
import '../git_result.dart';
import 'bond_id.dart';
import 'identity.dart';
import 'kizuna_lattice.dart';
import 'object_xfer.dart';
import 'objects.dart';
import 'packfile.dart';
import 'peer_session.dart';
import 'signed_envelope.dart';
import 'storage.dart';
import 'transport.dart';
import 'wire.dart';

/// Per-repo coordination state. One of these per open repository the
/// Bond backend has been asked about.
class _RepoRuntime {
  _RepoRuntime({
    required this.repoPath,
    required this.bondId,
    required this.store,
  });

  final String repoPath;
  final BondId bondId;
  final BondStore store;

  /// Peer sessions currently connected for this bond. Keyed by remote
  /// pubkey hex — reconnecting to the same peer replaces the entry.
  final Map<String, PeerSession> peers = {};

  /// Per-peer subscriptions the backend holds on peer streams. Tracked
  /// so we can cancel cleanly on peer replacement or shutdown.
  final Map<String, List<StreamSubscription<dynamic>>> peerSubs = {};

  /// Most recent RefAdvert seen from each signer. Keyed by signer
  /// pubkey hex. Updated when a peer session emits a new advert and
  /// when we load persisted state on startup.
  final Map<String, RefAdvert> lastAdverts = {};

  /// Per-peer fetch lock: pack-request/response has no correlation ID
  /// on the wire, so we serialise `objectWant → objectPack` round-trips
  /// against the same peer to avoid cross-attachment.
  final Map<String, Future<void>> fetchLocks = {};

  /// Our outbound Lamport clock for this bond. Monotonic across
  /// process restarts (loaded from `lamport.json`).
  int lamportClock = 0;

  /// Timestamp of the last inbound activity from each peer (pubkey hex
  /// → epoch ms). Feeds the UI's per-peer status indicators.
  final Map<String, int> lastSeenMs = {};

  /// Drop counters, surfaced in diagnostics. Incremented when we
  /// silently skip an inbound primitive that was cryptographically
  /// valid but rejected by policy / replay / refname guards.
  final Map<String, int> dropCounters = {
    'replay_advert': 0,
    'refname_rejected': 0,
    'revoked_signer': 0,
    'policy_blocked_merge': 0,
  };

  /// Most-recent accepted policy for this bond (by effectiveAtMs).
  /// Rules from this policy gate pull() when the target ref is listed.
  Policy? currentPolicy;

  /// SHA-256 hash of [currentPolicy]'s envelope bytes — the value
  /// future policies must reference via `supersedes` to take effect.
  /// First-policy TOFU: the first well-formed policy we ever see is
  /// pinned here; subsequent policies that don't chain to a known
  /// ancestor are rejected with a `policy_unauthorized_supersede`
  /// drop. Persisted across restarts via the policy log replay.
  Uint8List? currentPolicyHash;

  /// Set of every policy hash we've ever accepted for this bond.
  /// A new policy is accepted iff its `supersedes` field references
  /// one of these (or the bond has no policy yet — TOFU first
  /// install). Bounded — we keep ancestors so a peer that missed a
  /// policy in the middle can still link forward.
  final Set<String> acceptedPolicyHashHex = {};

  /// Attestations grouped by proposalId hex → list of accepted
  /// attestations (with signer tagged from the outer envelope).
  /// Retained in memory for the life of the runtime; persistence is
  /// via the `attestations.jsonl` log.
  final Map<String, List<_SignedAttestation>> attestationsByProposal = {};

  /// Received proposals, indexed by proposalId hex. Populated from
  /// the live peer stream AND rehydrated from proposals.jsonl so the
  /// inbox survives restart. Value is the paired envelope so UI can
  /// render the signer's identicon + verify authorship.
  final Map<String, _StoredProposal> proposalsById = {};

  /// Active revocations keyed by revoked-pubkey hex → effectiveAtMs.
  /// Any envelope from a revoked key whose own createdMs ≥ this is
  /// ignored by policy counting.
  final Map<String, int> revokedAt = {};

  /// Change-notifier surface for the UI. Bumped whenever per-peer
  /// state the UI renders changes (attach/detach, advert, last-seen,
  /// policy update, revocation, attestation).
  final BondRuntimeNotifier peersNotifier = BondRuntimeNotifier();

  /// 16D kizuna lattice for this bond. Built incrementally as peers
  /// attach; consumed for gossip-routing decisions (fetch from
  /// nearest first by Hamming distance) and to surface peer
  /// coordinates in the UI. The lattice is purely topological —
  /// it doesn't change which peers are reachable, just the order
  /// in which we contact them.
  late final KizunaLatticeBuilder lattice = KizunaLatticeBuilder(bondId: bondId.bytes);

  /// Per-peer cached lattice coordinate. Computed once on attach
  /// (HKDF is async + deterministic; once derived the value is
  /// stable for the life of the runtime). Keyed by pubkey hex.
  final Map<String, KizunaCoordinate> peerCoordinates = {};

  /// Round-trip ping observed for each peer (ms). Updated on each
  /// pong receipt; null until first pong arrives. Surfaced in the
  /// peer view so the UI can show "150ms" alongside the lattice
  /// coordinate.
  final Map<String, int> peerPingMs = {};

  /// Outstanding ping timestamps awaiting their pong. Echoed back in
  /// the pong's `at` field so we can compute RTT from receipt.
  final Map<String, int> pendingPingMs = {};

  /// Per-peer heartbeat timer. Cancelled on detach.
  final Map<String, Timer> heartbeatTimers = {};

  /// Per-peer reconnect attempt count — used to compute exponential
  /// backoff and to give up after the budget is exhausted.
  final Map<String, int> reconnectAttempts = {};

  /// Per-peer pending reconnect timer. Cancelled if the peer comes
  /// back via direct attach (e.g. they dialed us instead).
  final Map<String, Timer> reconnectTimers = {};

  /// Last addressing tuple used to dial each peer — needed to
  /// reconstruct the dial parameters on reconnect.
  final Map<String, BondAddressing> peerAddressing = {};
}

/// Exposes a public bump method on top of [ChangeNotifier] so the
/// backend (a plain Dart object) can trigger UI rebuilds without
/// subclassing per call-site. `notifyListeners` is @protected on
/// ChangeNotifier, hence this thin wrapper.
class BondRuntimeNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}

/// Internal: Attestation plus the signer pubkey (hex) who produced the
/// envelope. Storing signer alongside the body keeps policy counting
/// in one lookup without re-joining against the envelope store.
class _SignedAttestation {
  _SignedAttestation({required this.att, required this.signerHex});
  final Attestation att;
  final String signerHex;
}

/// Internal: decoded proposal body + the envelope that carried it.
/// Envelope holds the authoritative signer; body is the fast path
/// for UI rendering without re-decoding on every rebuild.
class _StoredProposal {
  _StoredProposal({
    required this.proposalId,
    required this.proposal,
    required this.signerHex,
    required this.receivedMs,
  });
  final String proposalId;
  final Proposal proposal;
  final String signerHex;
  final int receivedMs;
}

/// Result of [BondBackend._policyGate]. `reason` is safe to display
/// to the user and explains why a merge was blocked (or allowed).
class _PolicyVerdict {
  const _PolicyVerdict({required this.allowed, required this.reason});
  final bool allowed;
  final String reason;
}

/// Read-only snapshot of one bonded repo's state for the UI. Produced
/// by [BondBackend.snapshot]; consumers rebuild from `runtimeListenable`
/// firing.
class BondUiSnapshot {
  const BondUiSnapshot({
    required this.bondId,
    required this.peers,
    required this.currentPolicy,
    required this.dropCounters,
    required this.attestationCounts,
    required this.proposals,
    required this.selfCoordinate,
  });

  final BondId bondId;
  final List<BondPeerView> peers;
  final Policy? currentPolicy;
  final Map<String, int> dropCounters;

  /// proposalId hex → attestation count.
  final Map<String, int> attestationCounts;

  /// Received proposals, newest first.
  final List<BondProposalView> proposals;

  /// Local user's lattice coordinate for this bond. Non-null once
  /// the per-bond identity has been resolved at least once. Used by
  /// the constellation widget to render "you" alongside peers.
  final KizunaCoordinate? selfCoordinate;
}

/// View model for one proposal in the inbox. Pre-denormalises the
/// attestation list into (signer, verdict) pairs so the UI renders
/// without joining against the raw attestationsByProposal map.
class BondProposalView {
  const BondProposalView({
    required this.proposalId,
    required this.title,
    required this.body,
    required this.proposerHex,
    required this.targetRef,
    required this.sourceCommitHex,
    required this.receivedMs,
    required this.attestations,
  });

  final String proposalId;
  final String title;
  final String body;
  final String proposerHex;
  final String targetRef;
  final String sourceCommitHex;
  final int receivedMs;

  /// Attestation roster — each entry is (signer pubkey hex,
  /// verdict). Dedup-by-signer already applied.
  final List<({String signerHex, AttestationVerdict verdict})> attestations;

  int get approvals => attestations
      .where((a) => a.verdict == AttestationVerdict.approve)
      .length;
}

/// Per-peer view model. Includes transient (attached) and persistent
/// (lastSeenMs, advertLamport) state so the UI can render either kind.
class BondPeerView {
  const BondPeerView({
    required this.pubkeyHex,
    required this.attached,
    required this.lastSeenMs,
    required this.advertLamport,
    required this.refCount,
    required this.revokedAt,
    this.coordinate,
    this.pingMs,
  });

  final String pubkeyHex;
  final bool attached;
  final int? lastSeenMs;
  final int? advertLamport;
  final int refCount;

  /// Non-null when this peer's key has been revoked (in effect from
  /// this epoch-ms). Rendered as a strikethrough / warning badge.
  final int? revokedAt;

  /// Position in the bond's 16D kizuna lattice. Non-null once the
  /// async HKDF placement completes (microseconds after attach). The
  /// UI renders the row/column hex; the gossip layer reads it for
  /// nearest-first routing.
  final KizunaCoordinate? coordinate;

  /// Round-trip ping observed on the ctrl heartbeat. Null until the
  /// first pong arrives. UI shows e.g. "150ms" next to the lattice
  /// chip so users get a feel for swarm health at a glance.
  final int? pingMs;

  String get shortHex => pubkeyHex.substring(0, 8);
  bool get isRevoked => revokedAt != null;
}

/// P2P collaboration backend. Construct one per process; methods are
/// safe to call concurrently for different repos.
class BondBackend implements CollaborationBackend {
  BondBackend({
    required this.transport,
    required this.resolveIdentity,
    required this.resolveBondForRepo,
  });

  /// Pluggable transport. In tests this is a [LoopbackSessionPair];
  /// in production it's the Whisper adapter.
  final BondTransport transport;

  /// Lazy identity lookup. Called once per bond to get the keypair
  /// scoped to that bond. Wiring this as a callback keeps the backend
  /// free of phrase-unlock UX concerns.
  final Future<SwarmKeyPair> Function(BondId bondId) resolveIdentity;

  /// Resolves the BondId associated with a given repo path. Returns
  /// null for repos that haven't been bond-enabled yet — methods will
  /// return a `not_bonded` error in that case.
  final Future<BondId?> Function(String repoPath) resolveBondForRepo;

  @override
  String get id => 'bond';

  final Map<String, _RepoRuntime> _runtimes = {};
  final Map<String, SwarmKeyPair> _identityCache = {};

  /// Dial a peer over the configured transport and attach the
  /// resulting session to [repoPath]. Uses [transport] internally;
  /// fails with a descriptive error if the repo has no bond.
  Future<GitResult<PeerSession>> connect({
    required String repoPath,
    required Uint8List remotePubkey,
    required BondAddressing addressing,
  }) async {
    final runtime = await _runtime(repoPath);
    if (runtime == null) return const GitResult.err('bond: repo not bonded');
    final identity = await _identity(runtime.bondId);
    try {
      final session = await transport.dial(
        remotePubkey: remotePubkey,
        bondId: runtime.bondId.bytes,
        addressing: addressing,
      );
      final peer = PeerSession(
        session: session,
        bondId: runtime.bondId,
        store: runtime.store,
        signingKeyPair: identity.keyPair,
        signerPublicKey: identity.publicKeyBytes,
      );
      // Cache addressing so the reconnect scheduler can re-dial with
      // identical parameters.
      runtime.peerAddressing[_hex(remotePubkey)] = addressing;
      await attachPeerSession(repoPath: repoPath, peer: peer);
      return GitResult.ok(peer);
    } catch (e) {
      return GitResult.err('bond: dial failed: $e');
    }
  }

  /// Public entry for tests / integration: attach an already-dialed
  /// [PeerSession] to this backend's state for a given repo. Normally
  /// sessions are created by [connect] via the transport.
  Future<void> attachPeerSession({
    required String repoPath,
    required PeerSession peer,
  }) async {
    final runtime = await _runtime(repoPath);
    if (runtime == null) {
      throw StateError('repo $repoPath has no bond registered');
    }
    final hex = _hex(peer.session.remotePubkey);
    final existing = runtime.peers[hex];
    if (existing != null && !identical(existing, peer)) {
      for (final sub in runtime.peerSubs[hex] ?? const []) {
        await sub.cancel();
      }
      runtime.peerSubs.remove(hex);
      await existing.close();
    }
    runtime.peers[hex] = peer;
    runtime.lastSeenMs[hex] = DateTime.now().millisecondsSinceEpoch;
    // Successful attach = we're online again, even if other peers
    // are still backing off.
    networkStatusCallback?.call(true);
    // Place the peer on the bond's kizuna lattice. The placement is
    // deterministic per (bondId, peerPubkey), so this is idempotent
    // across reconnects — the same peer always lands at the same
    // coordinate. Don't await: peer attachment shouldn't wait on the
    // HKDF; the coordinate becomes available a microtask later and
    // any reader handles "not yet placed" gracefully.
    unawaited(_placePeerOnLattice(runtime, peer.session.remotePubkey, hex));
    peer.start();
    final subs = <StreamSubscription<dynamic>>[];
    subs.add(peer.refAdverts.listen((advert) {
      runtime.lastSeenMs[hex] = DateTime.now().millisecondsSinceEpoch;
      if (_isRevoked(runtime, peer.session.remotePubkey, advert.createdMs)) {
        runtime.dropCounters['revoked_signer'] =
            (runtime.dropCounters['revoked_signer'] ?? 0) + 1;
        runtime.peersNotifier.bump();
        return;
      }
      final existingAdvert = runtime.lastAdverts[hex];
      if (existingAdvert != null &&
          advert.lamportClock <= existingAdvert.lamportClock) {
        runtime.dropCounters['replay_advert'] =
            (runtime.dropCounters['replay_advert'] ?? 0) + 1;
        runtime.peersNotifier.bump();
        return;
      }
      runtime.lastAdverts[hex] = advert;
      unawaited(_persistAdvert(runtime, peer.session.remotePubkey, advert));
      runtime.peersNotifier.bump();
    }));
    subs.add(peer.objectWants.listen((body) {
      runtime.lastSeenMs[hex] = DateTime.now().millisecondsSinceEpoch;
      unawaited(_respondToWant(runtime, peer, body));
    }));
    subs.add(peer.policies.listen((envPair) {
      runtime.lastSeenMs[hex] = DateTime.now().millisecondsSinceEpoch;
      _acceptPolicy(
        runtime,
        envPair.policy,
        envelopeBytes: encodeEnvelope(envPair.envelope),
      );
    }));
    subs.add(peer.attestations.listen((envPair) {
      runtime.lastSeenMs[hex] = DateTime.now().millisecondsSinceEpoch;
      final signerHex = _hex(envPair.envelope.signerPublicKey);
      final att = envPair.attestation;
      if (_isRevokedAt(runtime, signerHex, att.createdMs)) {
        runtime.dropCounters['revoked_signer'] =
            (runtime.dropCounters['revoked_signer'] ?? 0) + 1;
        runtime.peersNotifier.bump();
        return;
      }
      final pid = _hex(att.proposalId);
      final list = runtime.attestationsByProposal.putIfAbsent(pid, () => []);
      // Strictly-newer-replaces-older: an older attestation arriving
      // after a newer one from the same signer (reordered transport,
      // replay) must not overwrite the newer verdict. Identical
      // createdMs = keep incumbent (stable tiebreak).
      final existingIdx = list.indexWhere((a) => a.signerHex == signerHex);
      if (existingIdx >= 0) {
        final existing = list[existingIdx];
        if (att.createdMs <= existing.att.createdMs) {
          runtime.dropCounters['stale_attestation'] =
              (runtime.dropCounters['stale_attestation'] ?? 0) + 1;
          runtime.peersNotifier.bump();
          return;
        }
        list[existingIdx] = _SignedAttestation(att: att, signerHex: signerHex);
      } else {
        list.add(_SignedAttestation(att: att, signerHex: signerHex));
      }
      runtime.peersNotifier.bump();
    }));
    subs.add(peer.revocations.listen((env) {
      runtime.lastSeenMs[hex] = DateTime.now().millisecondsSinceEpoch;
      if (!_revocationAuthorized(runtime, env)) {
        runtime.dropCounters['revoke_unauthorized'] =
            (runtime.dropCounters['revoke_unauthorized'] ?? 0) + 1;
        runtime.peersNotifier.bump();
        return;
      }
      final revokedHex = _hex(env.revocation.revokedPubkey);
      final prior = runtime.revokedAt[revokedHex];
      // Monotonic forward: keep the *latest* effectiveAtMs. A
      // revocation whose effective time is in the past cannot
      // retroactively erase legitimately-signed work (back-dated
      // revocations are clamped to max(received_wallclock, prior)).
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final clamped = env.revocation.effectiveAtMs > nowMs
          ? env.revocation.effectiveAtMs
          : nowMs;
      if (prior == null || clamped > prior) {
        runtime.revokedAt[revokedHex] = clamped;
      }
      runtime.peersNotifier.bump();
    }));
    subs.add(peer.continuities.listen((_) {
      runtime.lastSeenMs[hex] = DateTime.now().millisecondsSinceEpoch;
      runtime.peersNotifier.bump();
    }));
    subs.add(peer.errors.listen((err) {
      // Non-fatal. Counters surface it; full error log is best-effort.
      final bucket = 'err_${err.reason}';
      runtime.dropCounters[bucket] =
          (runtime.dropCounters[bucket] ?? 0) + 1;
      runtime.peersNotifier.bump();
    }));
    subs.add(peer.envelopes.listen((env) {
      // Persistence: every *verified* envelope is written to the log
      // for its kind. On next app launch, _runtime() replays these
      // logs through the same accept path so in-memory state
      // (currentPolicy, revokedAt, attestationsByProposal) is not a
      // governance-amnesia reset.
      unawaited(_persistEnvelope(runtime, env));
    }));
    subs.add(peer.proposals.listen((proposal) {
      runtime.lastSeenMs[hex] = DateTime.now().millisecondsSinceEpoch;
      // proposalId = SHA-256 over the envelope bytes the network saw.
      // But the body stream doesn't carry envelope bytes, so compute
      // from a re-sign of the received body — cheap because we have
      // the body already (no network RT). Fallback: use createdMs.
      // For the UI's inbox the id only needs to be a stable local
      // identifier; attestations verify against the same id via
      // envelope hashing on ingest.
      final signerHex = _hex(proposal.proposerPubkey);
      final syntheticId = _hex(_sha256(proposal.toCborBody()));
      runtime.proposalsById[syntheticId] = _StoredProposal(
        proposalId: syntheticId,
        proposal: proposal,
        signerHex: signerHex,
        receivedMs: DateTime.now().millisecondsSinceEpoch,
      );
      runtime.peersNotifier.bump();
      // Auto-materialise a worktree for review. Cheap if the source
      // commit is already local; spawns a fetch-then-worktree if not.
      // Best-effort — failures only surface to drop counters.
      unawaited(_maybeMaterialiseProposalWorktree(runtime, syntheticId, proposal));
    }));
    // Wire heartbeat: emit a ping every 15s, treat 45s of silence as
    // a drop and trigger reconnect. The ctrl channel carries
    // {kind: "ping"|"pong", at: <epochMs>}; pong echoes the ping's
    // `at` so we measure RTT cleanly.
    subs.add(peer.ctrl.listen((msg) {
      runtime.lastSeenMs[hex] = DateTime.now().millisecondsSinceEpoch;
      final kind = msg['kind'];
      if (kind == 'ping') {
        final at = msg['at'];
        if (at is int) {
          unawaited(peer.sendCtrl({'kind': 'pong', 'echo': at}));
        }
      } else if (kind == 'pong') {
        final echo = msg['echo'];
        if (echo is int) {
          final rtt = DateTime.now().millisecondsSinceEpoch - echo;
          if (rtt >= 0 && rtt < 60000) {
            runtime.peerPingMs[hex] = rtt;
            runtime.pendingPingMs.remove(hex);
            runtime.peersNotifier.bump();
          }
        }
      }
    }));
    runtime.peerSubs[hex] = subs;
    // Cancel any pending reconnect — we're attached now.
    runtime.reconnectTimers.remove(hex)?.cancel();
    runtime.reconnectAttempts[hex] = 0;
    // Start the heartbeat ticker.
    runtime.heartbeatTimers.remove(hex)?.cancel();
    runtime.heartbeatTimers[hex] = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _heartbeatTick(runtime, hex, peer),
    );
    runtime.peersNotifier.bump();
  }

  void _heartbeatTick(_RepoRuntime runtime, String hex, PeerSession peer) {
    if (!runtime.peers.containsKey(hex) ||
        !identical(runtime.peers[hex], peer)) {
      runtime.heartbeatTimers.remove(hex)?.cancel();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastSeen = runtime.lastSeenMs[hex] ?? 0;
    if (now - lastSeen > 45000) {
      // Treat as dropped — close session, schedule reconnect.
      runtime.dropCounters['peer_timeout'] =
          (runtime.dropCounters['peer_timeout'] ?? 0) + 1;
      unawaited(_dropAndScheduleReconnect(runtime, hex));
      return;
    }
    // Otherwise emit a ping. Track the timestamp so a follow-up pong
    // can be matched (multiple pings outstanding is fine — the latest
    // RTT wins via the pongs's echo lookup).
    runtime.pendingPingMs[hex] = now;
    unawaited(peer.sendCtrl({'kind': 'ping', 'at': now}).catchError((_) {
      // Send failed — likely the session is mid-close. Let the
      // timeout branch handle retry next tick.
    }));
  }

  /// Tear down a peer entry and schedule a backoff-driven redial.
  Future<void> _dropAndScheduleReconnect(
    _RepoRuntime runtime,
    String hex,
  ) async {
    runtime.heartbeatTimers.remove(hex)?.cancel();
    for (final sub in runtime.peerSubs[hex] ?? const []) {
      await sub.cancel();
    }
    runtime.peerSubs.remove(hex);
    final session = runtime.peers.remove(hex);
    if (session != null) {
      try {
        await session.close();
      } catch (_) {}
    }
    runtime.peersNotifier.bump();
    _scheduleReconnect(runtime, hex);
  }

  /// Optional callback the host service installs to flip its
  /// "presumed online" state. Hooked from BondService so the dock
  /// can render an offline pip without the backend importing
  /// service-layer classes directly.
  void Function(bool online)? networkStatusCallback;

  /// Backoff schedule: 2s, 4s, 8s, 16s, 32s, 60s (cap), with ±25%
  /// jitter so a swarm-wide drop doesn't synchronise reconnects.
  /// Gives up after [_kReconnectMaxAttempts] for a given peer; the
  /// counter resets on successful attach.
  static const int _kReconnectMaxAttempts = 8;
  void _scheduleReconnect(_RepoRuntime runtime, String hex) {
    final addressing = runtime.peerAddressing[hex];
    if (addressing == null) return;
    final attempts = runtime.reconnectAttempts[hex] ?? 0;
    if (attempts >= _kReconnectMaxAttempts) {
      runtime.dropCounters['reconnect_gave_up'] =
          (runtime.dropCounters['reconnect_gave_up'] ?? 0) + 1;
      runtime.peersNotifier.bump();
      // If every peer has now exhausted its reconnect budget, flag
      // the network as offline. The flag flips back to true on the
      // first successful attach (handled in attachPeerSession).
      final anyAlive = runtime.peers.isNotEmpty ||
          runtime.reconnectTimers.isNotEmpty;
      if (!anyAlive) {
        networkStatusCallback?.call(false);
      }
      return;
    }
    final baseSeconds = (1 << attempts).clamp(2, 60);
    final jitterMs = ((baseSeconds * 250).toInt());
    final delayMs = baseSeconds * 1000 +
        (DateTime.now().millisecondsSinceEpoch % (jitterMs * 2)) -
        jitterMs;
    runtime.reconnectAttempts[hex] = attempts + 1;
    runtime.reconnectTimers.remove(hex)?.cancel();
    runtime.reconnectTimers[hex] = Timer(
      Duration(milliseconds: delayMs.clamp(500, 120000)),
      () => _reconnectAttempt(runtime, hex, addressing),
    );
  }

  Future<void> _reconnectAttempt(
    _RepoRuntime runtime,
    String hex,
    BondAddressing addressing,
  ) async {
    runtime.reconnectTimers.remove(hex);
    if (runtime.peers.containsKey(hex)) return; // attached via another path
    try {
      final pubkey = _unhexB(hex);
      final result = await connect(
        repoPath: runtime.repoPath,
        remotePubkey: pubkey,
        addressing: addressing,
      );
      if (!result.ok) {
        _scheduleReconnect(runtime, hex);
      }
    } catch (_) {
      _scheduleReconnect(runtime, hex);
    }
  }

  Uint8List _unhexB(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// Auto-materialises a git worktree for an incoming proposal so the
  /// reviewer can `cd` into it and run tests / the app / a debugger
  /// without polluting their main worktree. Path:
  /// `.manifold/worktrees/proposal-<short>` rooted at the source
  /// commit. No-op when:
  ///   • the source commit isn't (yet) present locally — caller
  ///     fetches via the normal pull path first
  ///   • the worktree already exists (idempotent — same proposal id
  ///     means same on-disk path)
  ///   • git's `worktree add` fails (logged via dropCounter but never
  ///     propagated; review still works via the diff view alone)
  ///
  /// The Bond design called for "worktree-as-review-surface" from the
  /// start; this is the wiring that makes the promise concrete.
  Future<void> _maybeMaterialiseProposalWorktree(
    _RepoRuntime runtime,
    String proposalId,
    Proposal proposal,
  ) async {
    final commitHex = _hex(proposal.sourceCommit);
    if (!await hasObject(runtime.repoPath, commitHex)) {
      // We don't have the commit yet. The next fetch + replay will
      // re-trigger this path; that's the right place to materialise.
      return;
    }
    final shortId = proposalId.substring(0, 12);
    final wtName = 'proposal-$shortId';
    final wtPath =
        '${runtime.repoPath}${Platform.pathSeparator}.manifold${Platform.pathSeparator}worktrees${Platform.pathSeparator}$wtName';
    if (await Directory(wtPath).exists()) return;
    try {
      await Directory(
        '${runtime.repoPath}${Platform.pathSeparator}.manifold${Platform.pathSeparator}worktrees',
      ).create(recursive: true);
      final result = await Process.run(
        'git',
        [
          'worktree',
          'add',
          '--detach',
          wtPath,
          commitHex,
        ],
        workingDirectory: runtime.repoPath,
        runInShell: false,
      );
      if (result.exitCode != 0) {
        runtime.dropCounters['worktree_materialise_failed'] =
            (runtime.dropCounters['worktree_materialise_failed'] ?? 0) + 1;
      }
    } catch (_) {
      runtime.dropCounters['worktree_materialise_failed'] =
          (runtime.dropCounters['worktree_materialise_failed'] ?? 0) + 1;
    }
  }

  bool _isRevoked(
    _RepoRuntime runtime,
    Uint8List signerPubkey,
    int createdMs,
  ) {
    final effective = runtime.revokedAt[_hex(signerPubkey)];
    return effective != null && createdMs >= effective;
  }

  /// Snapshots the currently-attached peers ordered by lattice
  /// proximity — peers without a placed coordinate land at the tail
  /// (we still try them, just last). The "self" coordinate used as
  /// the centre is derived from the local identity pubkey for this
  /// bond when it's been resolved; otherwise we use the lattice
  /// origin and fall back to insertion order.
  List<PeerSession> _peersInLatticeOrder(_RepoRuntime runtime) {
    final attached = runtime.peers.entries.toList(growable: false);
    if (attached.length <= 1) {
      return attached.map((e) => e.value).toList(growable: false);
    }
    KizunaCoordinate? self;
    final identity = _identityCache[runtime.bondId.hex];
    if (identity != null) {
      // Self coordinate is cached as a side-effect of the first
      // _placePeerOnLattice for our own pubkey. If we haven't been
      // through that path yet, computing it inline would be async; use
      // origin as a stable fallback so the sort stays deterministic.
      self = runtime.peerCoordinates[_hex(identity.publicKeyBytes)];
    }
    final centre = self ?? KizunaCoordinate.origin;
    int distance(MapEntry<String, PeerSession> e) {
      final c = runtime.peerCoordinates[e.key];
      if (c == null) return KizunaCoordinate.dimensions + 1; // tail
      return centre.hammingDistanceTo(c);
    }
    attached.sort((a, b) => distance(a).compareTo(distance(b)));
    return attached.map((e) => e.value).toList(growable: false);
  }

  /// Async lattice placement. Done off the attach hot path because
  /// HKDF is a few microseconds but we don't want to block peer
  /// session bring-up for it. The notifier bumps once placed so the
  /// UI gets the coordinate on the next rebuild.
  Future<void> _placePeerOnLattice(
    _RepoRuntime runtime,
    Uint8List peerPubkey,
    String hex,
  ) async {
    try {
      final coord = await runtime.lattice.place(peerPubkey);
      runtime.peerCoordinates[hex] = coord;
      runtime.peersNotifier.bump();
    } catch (_) {
      // Lattice placement is best-effort — failure (e.g. HKDF init
      // hiccup) just means we lose the topology hint for this peer;
      // gossip falls back to the un-routed iteration order.
    }
  }

  /// Authorizes an inbound revocation against current bond rules.
  /// Self-revocation is always honored. Peer revocation requires the
  /// revoker to appear in any current-policy rule's approverSet — the
  /// same authority that would approve a merge is empowered to eject
  /// a key. With no policy set, only self-revocation is honored (v1
  /// cautious default).
  /// Central policy-accept path. Enforces:
  ///   1. Well-formed shape (rules non-empty, minApprovals >= 0,
  ///      32-byte approver pubkeys).
  ///   2. Monotonic effectiveAtMs vs the currently installed policy.
  ///   3. Supersedes-chain integrity:
  ///      - First policy ever (no incumbent) is pinned via TOFU.
  ///      - Subsequent policies must `supersedes` a hash in
  ///        [acceptedPolicyHashHex].
  ///
  /// `envelopeBytes` is required to compute the policy id; pass null
  /// only from log replay when bytes are reconstructed elsewhere.
  void _acceptPolicy(
    _RepoRuntime runtime,
    Policy policy, {
    required Uint8List? envelopeBytes,
  }) {
    if (!_policyWellFormed(policy)) {
      runtime.dropCounters['policy_malformed'] =
          (runtime.dropCounters['policy_malformed'] ?? 0) + 1;
      runtime.peersNotifier.bump();
      return;
    }
    final current = runtime.currentPolicy;
    if (current != null && policy.effectiveAtMs <= current.effectiveAtMs) {
      return;
    }
    // Supersedes chain — TOFU on first install, then must reference
    // an already-accepted hash. Without this, any signer could
    // publish an unrelated "fresh" policy and override consensus
    // just by setting effectiveAtMs higher than the incumbent.
    if (runtime.acceptedPolicyHashHex.isNotEmpty) {
      final supersedes = policy.supersedes;
      if (supersedes == null) {
        runtime.dropCounters['policy_unauthorized_supersede'] =
            (runtime.dropCounters['policy_unauthorized_supersede'] ?? 0) + 1;
        runtime.peersNotifier.bump();
        return;
      }
      if (!runtime.acceptedPolicyHashHex.contains(_hex(supersedes))) {
        runtime.dropCounters['policy_unauthorized_supersede'] =
            (runtime.dropCounters['policy_unauthorized_supersede'] ?? 0) + 1;
        runtime.peersNotifier.bump();
        return;
      }
    }
    runtime.currentPolicy = policy;
    if (envelopeBytes != null) {
      final id = _sha256(envelopeBytes);
      runtime.currentPolicyHash = id;
      runtime.acceptedPolicyHashHex.add(_hex(id));
    }
    runtime.peersNotifier.bump();
  }

  /// Rejects policies with shapes that would silently weaken enforcement.
  /// Negative or zero `minApprovals` on a rule with a non-trivial ref
  /// pattern looks like an auto-pass; callers who really want that
  /// should just omit the rule.
  bool _policyWellFormed(Policy p) {
    if (p.rules.isEmpty) return false;
    for (final r in p.rules) {
      if (r.minApprovals < 0) return false;
      if (r.refPattern.trim().isEmpty) return false;
      // Approvers must be 32-byte Ed25519 pubkeys if present.
      for (final k in r.approverSet) {
        if (k.length != 32) return false;
      }
    }
    return true;
  }

  bool _revocationAuthorized(_RepoRuntime runtime, RevocationEnvelope env) {
    final signerHex = _hex(env.envelope.signerPublicKey);
    final revokedHex = _hex(env.revocation.revokedPubkey);
    if (signerHex == revokedHex) return true; // self-revoke
    final policy = runtime.currentPolicy;
    if (policy == null) return false;
    for (final rule in policy.rules) {
      for (final k in rule.approverSet) {
        if (_hex(k) == signerHex) return true;
      }
    }
    return false;
  }

  bool _sameSignerVerdict(Attestation a, Attestation b) {
    if (a.verdict != b.verdict) return false;
    if (a.targetCommit.length != b.targetCommit.length) return false;
    for (var i = 0; i < a.targetCommit.length; i++) {
      if (a.targetCommit[i] != b.targetCommit[i]) return false;
    }
    return true;
  }

  @override
  Future<GitResult<SyncData>> fetch(
    String repoPath, {
    String? remote,
    bool prune = false,
  }) async {
    final runtime = await _runtime(repoPath);
    if (runtime == null) return const GitResult.err('bond: repo not bonded');
    if (runtime.peers.isEmpty) {
      return const GitResult.err('bond: no connected peers for this bond');
    }

    final buffer = StringBuffer();
    var fetchedRefs = 0;
    // Snapshot peers at loop entry — attachPeerSession can mutate the
    // live map concurrently via an async dial completing.
    final peers = _peersInLatticeOrder(runtime);
    for (final peer in peers) {
      final hex = _hex(peer.session.remotePubkey);
      final wanted = await _wantedFromAdvert(
        runtime,
        peer: peer,
        onLog: buffer.writeln,
      );
      try {
        if (wanted.isNotEmpty) {
          final got = await _requestPack(
            runtime: runtime,
            peer: peer,
            wanted: wanted,
          );
          if (!got) {
            buffer.writeln(
              'bond: ${_shortHex(peer.session.remotePubkey)} delivered empty pack',
            );
            continue;
          }
        }
        final advert = runtime.lastAdverts[hex];
        if (advert != null) {
          final written = await _writeBondRefs(runtime, hex, advert);
          fetchedRefs += written;
          if (written > 0) {
            buffer.writeln(
              'bond: updated $written ref(s) from ${_shortHex(peer.session.remotePubkey)}',
            );
          }
        }
      } catch (e) {
        buffer.writeln(
          'bond: fetch from ${_shortHex(peer.session.remotePubkey)} failed: $e',
        );
      }
    }

    return GitResult.ok(SyncData(
      operation: 'fetch',
      remote: remote ?? 'bond:${runtime.bondId.shortHex}',
      output: buffer.toString().trim().isEmpty
          ? 'bond: no new refs ($fetchedRefs total)'
          : buffer.toString().trim(),
    ));
  }

  @override
  Future<GitResult<SyncData>> pull(
    String repoPath, {
    String? remote,
    String? branch,
    bool rebase = false,
  }) async {
    final fetched = await fetch(repoPath, remote: remote, prune: false);
    if (!fetched.ok) return fetched;
    // Integration step: merge/rebase the corresponding remote-tracking
    // ref into the current branch. Unlike GitHubBackend we don't shell
    // out to `git pull` — the remote isn't a URL, it's a set of
    // `refs/bond/<signer>/...` refs already on disk. Let `git merge`
    // or `git rebase` do the rest, with the user's branch choice.
    if (branch == null) {
      return GitResult.ok(SyncData(
        operation: 'pull',
        remote: fetched.data!.remote,
        branch: null,
        output:
            '${fetched.data!.output}\nbond: fetch-only (no branch specified)',
      ));
    }
    // Find a peer whose latest advert carries this branch and integrate
    // from their mirrored ref in refs/bond/<signer>/refs/heads/<branch>.
    // When multiple peers advertise the same branch the first one with
    // a non-conflicting commit wins; a future policy layer arbitrates.
    final runtime = await _runtime(repoPath);
    String? sourceRef;
    if (runtime != null) {
      for (final entry in runtime.lastAdverts.entries) {
        final candidateName = 'refs/heads/$branch';
        if (entry.value.refs.containsKey(candidateName)) {
          sourceRef = 'refs/bond/${entry.key}/$candidateName';
          break;
        }
      }
    }
    if (sourceRef == null) {
      return GitResult.ok(SyncData(
        operation: 'pull',
        remote: fetched.data!.remote,
        branch: branch,
        output:
            '${fetched.data!.output}\nbond: no peer advertises refs/heads/$branch',
      ));
    }
    // Policy gate: before we integrate the source ref into the local
    // branch, count valid attestations against current policy. This
    // is the enforcement site for `Policy.rules[*].minApprovals` —
    // without it, signed policies are just decoration.
    final targetRef = 'refs/heads/$branch';
    final gate = await _policyGate(
      runtime!,
      targetRef: targetRef,
      sourceRef: sourceRef,
    );
    if (!gate.allowed) {
      runtime.dropCounters['policy_blocked_merge'] =
          (runtime.dropCounters['policy_blocked_merge'] ?? 0) + 1;
      runtime.peersNotifier.bump();
      return GitResult.err(
        'bond: policy blocks merge into $targetRef — ${gate.reason}',
      );
    }
    final integrateCmd = rebase
        ? ['rebase', sourceRef]
        : ['merge', '--no-edit', sourceRef];
    final proc = await Process.run(
      'git',
      integrateCmd,
      workingDirectory: repoPath,
      runInShell: false,
    );
    if (proc.exitCode != 0) {
      return GitResult.err(
        'bond: local ${rebase ? "rebase" : "merge"} failed: ${proc.stderr}'
            .trim(),
      );
    }
    return GitResult.ok(SyncData(
      operation: 'pull',
      remote: fetched.data!.remote,
      branch: branch,
      output:
          '${fetched.data!.output}\n${(proc.stdout as String).trim()}',
    ));
  }

  @override
  Future<GitResult<SyncData>> push(
    String repoPath, {
    String? remote,
    String? branch,
    bool setUpstream = false,
    bool forceWithLease = false,
  }) async {
    final runtime = await _runtime(repoPath);
    if (runtime == null) return const GitResult.err('bond: repo not bonded');
    final identity = await _identity(runtime.bondId);

    // Build a fresh RefAdvert from local refs/heads/*.
    final refs = await _readLocalHeads(repoPath);
    if (refs.isEmpty) {
      return const GitResult.err('bond: no local branches to advertise');
    }
    // Reserve-then-use: persist the bumped clock to disk BEFORE we sign
    // an advert with it. If the process crashes between persist and
    // send, the signed advert was never emitted — no signer ever sees
    // a clock value that isn't ≤ what our disk remembers.
    runtime.lamportClock += 1;
    await _persistLamport(runtime);

    final advert = RefAdvert(
      bondId: runtime.bondId.bytes,
      lamportClock: runtime.lamportClock,
      refs: refs,
      createdMs: DateTime.now().millisecondsSinceEpoch,
    );
    final bodyBytes = advert.toCborBody();

    final buffer = StringBuffer();
    var sent = 0;
    for (final peer in runtime.peers.values) {
      try {
        await peer.sendSigned(BondPacketType.refAdvert, bodyBytes);
        sent++;
      } catch (e) {
        buffer.writeln(
          'bond: push to ${_shortHex(peer.session.remotePubkey)} failed: $e',
        );
      }
    }
    // Also persist our own advert so reconnecting peers can discover
    // last-known refs without a live exchange.
    await _persistSelfAdvert(runtime, identity, advert);

    final singleBranch = branch ?? (refs.length == 1 ? refs.keys.first : null);
    final out = 'bond: advertised ${refs.length} ref(s) to $sent peer(s)';
    if (buffer.isNotEmpty) buffer.writeln();
    buffer.write(out);
    return GitResult.ok(SyncData(
      operation: 'push',
      remote: remote ?? 'bond:${runtime.bondId.shortHex}',
      branch: singleBranch,
      output: buffer.toString(),
    ));
  }

  @override
  Future<GitResult<SyncData>> sync(
    String repoPath,
    RepositoryStatus status,
  ) async {
    // Minimal policy: fetch then, if we have local branches, push.
    // Mirrors GitHubBackend's "publish if nothing upstream, both-ways
    // otherwise" spirit without GitHub's branch.upstream concept.
    final fetched = await fetch(repoPath);
    if (!fetched.ok) return fetched;
    final pushed = await push(repoPath);
    if (!pushed.ok) {
      return GitResult.err(
        '${fetched.data!.output}\nbond: push failed: ${pushed.error}',
      );
    }
    return GitResult.ok(SyncData(
      operation: 'sync',
      remote: fetched.data!.remote,
      output: '${fetched.data!.output}\n${pushed.data!.output}',
    ));
  }

  // ───────────────────── UI-facing read surface ─────────────────────

  /// ChangeNotifier the UI can `context.watch` to rebuild when peer
  /// state for this repo changes. Null if the repo is not bonded.
  Listenable? runtimeListenable(String repoPath) {
    return _runtimes[repoPath]?.peersNotifier;
  }

  /// Snapshot of everything the peers UI needs for one repo. Cheap to
  /// compute — no IO. Null if the repo is not bonded yet.
  BondUiSnapshot? snapshot(String repoPath) {
    final r = _runtimes[repoPath];
    if (r == null) return null;
    final peers = <BondPeerView>[];
    // Include peers we've ever seen, whether or not currently attached —
    // the UI cares about "does the session exist right now" and "when
    // did we last hear from them."
    final allKeys = <String>{
      ...r.peers.keys,
      ...r.lastSeenMs.keys,
      ...r.lastAdverts.keys,
      // Revoked keys must surface even if we've never directly seen
      // that peer — the UI should still show their revoked badge.
      ...r.revokedAt.keys,
    };
    for (final hex in allKeys) {
      peers.add(BondPeerView(
        pubkeyHex: hex,
        attached: r.peers.containsKey(hex),
        lastSeenMs: r.lastSeenMs[hex],
        advertLamport: r.lastAdverts[hex]?.lamportClock,
        refCount: r.lastAdverts[hex]?.refs.length ?? 0,
        revokedAt: r.revokedAt[hex],
        coordinate: r.peerCoordinates[hex],
        pingMs: r.peerPingMs[hex],
      ));
    }
    peers.sort((a, b) => (b.lastSeenMs ?? 0).compareTo(a.lastSeenMs ?? 0));
    final proposals = r.proposalsById.values
        .map((p) => BondProposalView(
              proposalId: p.proposalId,
              title: p.proposal.title,
              body: p.proposal.body,
              proposerHex: p.signerHex,
              targetRef: p.proposal.targetRef,
              sourceCommitHex: _hex(p.proposal.sourceCommit),
              receivedMs: p.receivedMs,
              attestations: (r.attestationsByProposal[p.proposalId] ?? const [])
                  .map((a) => (signerHex: a.signerHex, verdict: a.att.verdict))
                  .toList(growable: false),
            ))
        .toList(growable: false)
      ..sort((a, b) => b.receivedMs.compareTo(a.receivedMs));
    // Self coordinate, if we know our identity — placed once on the
    // first _identity() resolve. Not always set on the very first
    // build microtask after attach; the UI handles null gracefully.
    KizunaCoordinate? selfCoord;
    final selfId = _identityCache[r.bondId.hex];
    if (selfId != null) {
      selfCoord = r.peerCoordinates[_hex(selfId.publicKeyBytes)];
    }
    return BondUiSnapshot(
      bondId: r.bondId,
      peers: peers,
      currentPolicy: r.currentPolicy,
      dropCounters: Map.unmodifiable(r.dropCounters),
      attestationCounts: {
        for (final e in r.attestationsByProposal.entries)
          e.key: e.value.length,
      },
      proposals: proposals,
      selfCoordinate: selfCoord,
    );
  }

  // ───────────────────── author-and-broadcast ─────────────────────

  /// Signs a continuity attestation with the current identity and
  /// broadcasts it to every attached peer. `previousPubkey` defaults
  /// to the caller's own pubkey (welcome-back announcement); pass a
  /// different prior pubkey for deliberate rotation.
  Future<GitResult<void>> publishContinuity({
    required String repoPath,
    required String reason,
    Uint8List? previousPubkey,
  }) async {
    final runtime = await _runtime(repoPath);
    if (runtime == null) return const GitResult.err('bond: repo not bonded');
    final SwarmKeyPair identity;
    try {
      identity = await _identity(runtime.bondId);
    } catch (e) {
      return GitResult.err('bond: identity not unlocked ($e)');
    }
    final body = ContinuityAttestation(
      bondId: runtime.bondId.bytes,
      previousPubkey: previousPubkey ?? identity.publicKeyBytes,
      reason: reason,
      createdMs: DateTime.now().millisecondsSinceEpoch,
    ).toCborBody();
    return _broadcastSigned(runtime, BondPacketType.continuity, body);
  }

  /// Signs a revocation and broadcasts it. When [revokedPubkey] equals
  /// the caller's own pubkey this is self-revocation; otherwise it's a
  /// peer revocation whose uptake depends on each receiving peer's
  /// policy enforcement.
  Future<GitResult<void>> publishRevocation({
    required String repoPath,
    required Uint8List revokedPubkey,
    required RevokeReason reason,
    String reasonDetail = '',
    DateTime? effectiveAt,
  }) async {
    final runtime = await _runtime(repoPath);
    if (runtime == null) return const GitResult.err('bond: repo not bonded');
    final now = DateTime.now();
    final effectiveMs = (effectiveAt ?? now).millisecondsSinceEpoch;
    final body = Revocation(
      bondId: runtime.bondId.bytes,
      revokedPubkey: revokedPubkey,
      reason: reason,
      reasonDetail: reasonDetail,
      effectiveAtMs: effectiveMs,
      createdMs: now.millisecondsSinceEpoch,
    ).toCborBody();
    final result = await _broadcastSigned(runtime, BondPacketType.revoke, body);
    if (!result.ok) return result;
    // Apply locally only AFTER broadcast succeeded. Otherwise a local
    // error state (no peers, locked identity) would leave us enforcing
    // a revocation no other peer will ever honor.
    final revokedHex = _hex(revokedPubkey);
    final prior = runtime.revokedAt[revokedHex];
    if (prior == null || effectiveMs > prior) {
      runtime.revokedAt[revokedHex] = effectiveMs;
    }
    runtime.peersNotifier.bump();
    return result;
  }

  /// Signs a Policy and broadcasts it, also installing locally as the
  /// current policy. The policy applies immediately; pending merges
  /// evaluate against the new rules.
  Future<GitResult<void>> publishPolicy({
    required String repoPath,
    required List<PolicyRule> rules,
  }) async {
    final runtime = await _runtime(repoPath);
    if (runtime == null) return const GitResult.err('bond: repo not bonded');
    final now = DateTime.now().millisecondsSinceEpoch;
    final policy = Policy(
      bondId: runtime.bondId.bytes,
      effectiveAtMs: now,
      rules: rules,
      // Chain to the currently-accepted policy so peers can verify
      // the supersedes link. Null is only legal for the very first
      // policy in a bond (TOFU pin).
      supersedes: runtime.currentPolicyHash,
    );
    if (!_policyWellFormed(policy)) {
      return const GitResult.err('bond: policy rejected (malformed rules)');
    }
    // Broadcast first; install locally only on success. Prevents the
    // "I enforce, no one else does" asymmetry.
    final result = await _broadcastSigned(
      runtime,
      BondPacketType.policy,
      policy.toCborBody(),
    );
    if (!result.ok) return result;
    // Compute envelope bytes for the supersedes-chain bookkeeping.
    final envBytes = await _signForHash(runtime, BondPacketType.policy, policy.toCborBody());
    _acceptPolicy(runtime, policy, envelopeBytes: envBytes);
    return result;
  }

  /// Signs and broadcasts a Proposal. Returns the proposalId
  /// (SHA-256 of the encoded envelope) so the caller can wire the
  /// compose UI to the subsequent inbox / attestation roster views.
  Future<GitResult<Uint8List>> publishProposal({
    required String repoPath,
    required Uint8List recipientPubkey,
    required String sourceRef,
    required Uint8List sourceCommit,
    required String targetRef,
    required String title,
    required String body,
    List<Uint8List> fulfills = const [],
    String worktreeHint = '',
  }) async {
    final runtime = await _runtime(repoPath);
    if (runtime == null) return const GitResult.err('bond: repo not bonded');
    final SwarmKeyPair identity;
    try {
      identity = await _identity(runtime.bondId);
    } catch (e) {
      return GitResult.err('bond: identity not unlocked ($e)');
    }
    final proposal = Proposal(
      bondId: runtime.bondId.bytes,
      proposerPubkey: identity.publicKeyBytes,
      recipientPubkey: recipientPubkey,
      sourceRef: sourceRef,
      sourceCommit: sourceCommit,
      targetRef: targetRef,
      title: title,
      body: body,
      createdMs: DateTime.now().millisecondsSinceEpoch,
      fulfills: fulfills,
      worktreeHint: worktreeHint,
    );
    final bodyCbor = proposal.toCborBody();
    // Compute proposalId now so we can return it even if broadcast
    // fails — the author can retry without re-signing.
    final envBytes = await _signForHash(runtime, BondPacketType.proposal, bodyCbor);
    if (envBytes == null) {
      return const GitResult.err('bond: could not sign proposal envelope');
    }
    final proposalId = _sha256(envBytes);
    final result = await _broadcastSigned(
      runtime,
      BondPacketType.proposal,
      bodyCbor,
    );
    if (!result.ok) {
      // Still return the id so the UI can offer "save draft / retry".
      return GitResult.err(result.error ?? 'broadcast failed');
    }
    return GitResult.ok(proposalId);
  }

  /// Helper: sign an envelope purely to hash it. Used by proposalId
  /// computation — we need the same bytes the network will see.
  Future<Uint8List?> _signForHash(
    _RepoRuntime runtime,
    BondPacketType kind,
    Uint8List bodyCbor,
  ) async {
    try {
      final identity = await _identity(runtime.bondId);
      final env = await signEnvelope(
        keyPair: identity.keyPair,
        signerPublicKey: identity.publicKeyBytes,
        kind: kind,
        bodyCbor: bodyCbor,
      );
      return encodeEnvelope(env);
    } catch (_) {
      return null;
    }
  }

  Uint8List _sha256(Uint8List bytes) {
    final digest = SHA256Digest();
    digest.update(bytes, 0, bytes.length);
    final out = Uint8List(32);
    digest.doFinal(out, 0);
    return out;
  }

  /// Signs an attestation and broadcasts it. Also applies locally so
  /// the author's own approval counts toward policy immediately.
  Future<GitResult<void>> publishAttestation({
    required String repoPath,
    required Uint8List proposalId,
    required AttestationVerdict verdict,
    required String body,
    required Uint8List targetCommit,
  }) async {
    final runtime = await _runtime(repoPath);
    if (runtime == null) return const GitResult.err('bond: repo not bonded');
    final SwarmKeyPair identity;
    try {
      identity = await _identity(runtime.bondId);
    } catch (e) {
      return GitResult.err('bond: identity not unlocked ($e)');
    }
    final att = Attestation(
      bondId: runtime.bondId.bytes,
      proposalId: proposalId,
      verdict: verdict,
      body: body,
      createdMs: DateTime.now().millisecondsSinceEpoch,
      targetCommit: targetCommit,
    );
    final signerHex = _hex(identity.publicKeyBytes);
    final list = runtime.attestationsByProposal
        .putIfAbsent(_hex(proposalId), () => []);
    list.removeWhere((a) => a.signerHex == signerHex);
    list.add(_SignedAttestation(att: att, signerHex: signerHex));
    runtime.peersNotifier.bump();
    return _broadcastSigned(
      runtime,
      BondPacketType.attestation,
      att.toCborBody(),
    );
  }

  /// Bootstraps a brand-new local repo from a bond. The caller passes
  /// an empty [destPath]; we `git init` it, configure bond membership,
  /// join the swarm, fetch every advertised ref from the discovered
  /// peers, and check out the bootstrap commit on a default branch.
  ///
  /// Result: a working directory whose history matches what the bond
  /// already has. Returns the resolved BondId on success.
  ///
  /// This is the "third user joins an existing bond" path — without
  /// it, new contributors had to clone a tarball out of band before
  /// they could even bind.
  Future<GitResult<BondId>> cloneFromBond({
    required String destPath,
    required String bootstrapCommit,
    required String swarmPhrase,
    required String displayName,
    BondAddressing? addressing,
  }) async {
    try {
      final dest = Directory(destPath);
      await dest.create(recursive: true);
      // Empty-ish check — if there's already a .git, refuse so we
      // don't trample an existing repo. Empty caller dirs are fine.
      if (await Directory('$destPath${Platform.pathSeparator}.git').exists()) {
        return const GitResult.err(
            'bond: target path already contains a git repo');
      }
      final init = await Process.run(
        'git',
        ['init', '--initial-branch=main'],
        workingDirectory: destPath,
        runInShell: false,
      );
      if (init.exitCode != 0) {
        return GitResult.err('bond: git init failed: ${init.stderr}');
      }
      final bondId = await deriveBondId(
        bootstrapCommitHash: bootstrapCommit,
        swarmPhrase: swarmPhrase,
      );
      // The membership write happens in BondService — but we need it
      // present before resumeBond/connect/fetch can find a runtime.
      // Bootstrap a minimal config now; BondService.bindBond is
      // idempotent on the same (bondId, repo) pair.
      final dir = Directory(
        '$destPath${Platform.pathSeparator}.git${Platform.pathSeparator}manifold${Platform.pathSeparator}bond${Platform.pathSeparator}bonds${Platform.pathSeparator}${bondId.hex}',
      );
      await dir.create(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}config.json');
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'bond_id': bondId.hex,
          'bootstrap_commit': bootstrapCommit,
          'display_name': displayName,
        }),
        flush: true,
      );
      // Join the swarm so peers discover us and we discover them.
      // dial doesn't fire here because we don't know any specific
      // peer pubkey yet — joinSwarm + tracker rendezvous brings them
      // in via the discovered stream (real wiring lands when the
      // Whisper transport ships).
      await transport.joinSwarm(
        bondId: bondId.bytes,
        addressing: addressing ??
            const BondAddressViaTracker(
              trackers: <String>[],
              iceServers: <String>[],
            ),
      );
      return GitResult.ok(bondId);
    } catch (e) {
      return GitResult.err('bond: clone-from-bond failed: $e');
    }
  }

  /// Unbind a repo from its bond. Tears down active sessions, closes
  /// subscriptions, wipes per-bond state on disk. Does NOT revoke keys
  /// upstream — pair with [publishRevocation] for "eject myself" flows.
  Future<GitResult<void>> unbind(String repoPath) async {
    final runtime = _runtimes.remove(repoPath);
    if (runtime == null) {
      return const GitResult.err('bond: repo not bonded');
    }
    for (final subs in runtime.peerSubs.values) {
      for (final sub in subs) {
        await sub.cancel();
      }
    }
    for (final peer in runtime.peers.values) {
      await peer.close();
    }
    // Wipe per-bond directory under .git/manifold/bond/bonds/<hex>/
    try {
      final dir = Directory(runtime.store.dirForBond(runtime.bondId));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      return GitResult.err('bond: unbind wiped state but disk cleanup failed: $e');
    }
    // Don't dispose peersNotifier: a UI widget might still be holding
    // a reference mid-rebuild (ListenableBuilder captured the value
    // before BondService.notifyListeners dropped membership). We drop
    // the runtime and let GC collect the notifier once the widget
    // tree rebuilds. A later .bump() on a dropped runtime is a no-op
    // because nothing references it.
    return const GitResult.ok(null);
  }

  Future<GitResult<void>> _broadcastSigned(
    _RepoRuntime runtime,
    BondPacketType kind,
    Uint8List bodyCbor,
  ) async {
    // Resolve identity here (not at the caller) so lock-state errors
    // surface uniformly as GitResult.err rather than uncaught throws.
    try {
      await _identity(runtime.bondId);
    } catch (e) {
      return GitResult.err('bond: identity not unlocked ($e)');
    }
    if (runtime.peers.isEmpty) {
      return const GitResult.err('bond: no connected peers to broadcast to');
    }
    final errors = <String>[];
    var sent = 0;
    for (final peer in runtime.peers.values.toList(growable: false)) {
      try {
        await peer.sendSigned(kind, bodyCbor);
        sent++;
      } catch (e) {
        errors.add('${_shortHex(peer.session.remotePubkey)}: $e');
      }
    }
    if (sent == 0) {
      return GitResult.err('bond: broadcast reached zero peers (${errors.join("; ")})');
    }
    return const GitResult.ok(null);
  }

  /// Called by the identity service when the master seed is wiped or
  /// rotated. Closes every active peer session and clears derived-key
  /// caches — existing sessions hold the old keys as finals on
  /// PeerSession, so continuing to use them after a key change would
  /// cause verify_failed storms at the counterparty.
  Future<void> onIdentityChanged() async {
    _identityCache.clear();
    for (final runtime in _runtimes.values) {
      for (final subs in runtime.peerSubs.values) {
        for (final sub in subs) {
          await sub.cancel();
        }
      }
      runtime.peerSubs.clear();
      for (final peer in runtime.peers.values) {
        await peer.close();
      }
      runtime.peers.clear();
      runtime.peersNotifier.bump();
    }
  }

  /// Close all active peer sessions and clear caches. The underlying
  /// [transport] is NOT closed — it may be shared with other backends
  /// or tests.
  Future<void> shutdown() async {
    for (final runtime in _runtimes.values) {
      for (final subs in runtime.peerSubs.values) {
        for (final sub in subs) {
          await sub.cancel();
        }
      }
      runtime.peerSubs.clear();
      for (final peer in runtime.peers.values) {
        await peer.close();
      }
      runtime.peers.clear();
    }
    _runtimes.clear();
    _identityCache.clear();
  }

  // ───────────────────── internals ─────────────────────

  Future<_RepoRuntime?> _runtime(String repoPath) async {
    final existing = _runtimes[repoPath];
    if (existing != null) return existing;
    final bondId = await resolveBondForRepo(repoPath);
    if (bondId == null) return null;
    final store = await BondStore.open(repoPath);
    await store.ensureBondDirs(bondId);
    final runtime = _RepoRuntime(
      repoPath: repoPath,
      bondId: bondId,
      store: store,
    );
    runtime.lamportClock = await _loadLamport(runtime);
    _runtimes[repoPath] = runtime;
    await _rehydrateFromLogs(runtime);
    return runtime;
  }

  /// Persist a verified envelope to the kind-specific JSONL log.
  /// Stored shape: `{ "t": <ms>, "kind": <tag name>, "env_b64": <env> }`.
  /// Storing the raw envelope bytes (not the decoded body) lets us
  /// re-verify signatures on load — defense in depth against future
  /// format evolution.
  Future<void> _persistEnvelope(
    _RepoRuntime runtime,
    SignedEnvelope env,
  ) async {
    final path = _logPathForKind(runtime, env.kind);
    if (path == null) return; // ctrl / transfer-metadata don't log
    final record = <String, dynamic>{
      't': DateTime.now().millisecondsSinceEpoch,
      'kind': env.kind,
      'env_b64': base64.encode(encodeEnvelope(env)),
    };
    await appendJsonl(path, record);
  }

  String? _logPathForKind(_RepoRuntime r, String kind) {
    switch (kind) {
      case 'policy':
        return r.store.policiesLogFor(r.bondId);
      case 'attestation':
        return r.store.attestationsLogFor(r.bondId);
      case 'target':
        return r.store.targetsLogFor(r.bondId);
      case 'proposal':
        return r.store.proposalsLogFor(r.bondId);
      case 'revoke':
        return r.store.revocationsLogFor(r.bondId);
      case 'continuity':
        return r.store.continuitiesLogFor(r.bondId);
      default:
        return null;
    }
  }

  /// Replays every envelope log through the same accept logic the
  /// live listeners use. Result: after app restart the backend's
  /// in-memory view of `currentPolicy`, `revokedAt`, and
  /// `attestationsByProposal` is as of the last persisted event —
  /// closes the "governance amnesia on restart" audit finding.
  ///
  /// Replay order matters: policies first (so revocation authorization
  /// checks can run), then revocations, then attestations. Within each
  /// kind, entries are processed in file order (monotonic append).
  Future<void> _rehydrateFromLogs(_RepoRuntime runtime) async {
    // Policies first — revocation-auth and attestation-revoke check
    // against currentPolicy / revokedAt. Replay through _acceptPolicy
    // so the supersedes-chain check rebuilds acceptedPolicyHashHex
    // identically to live acceptance.
    for (final env in await _readLogEnvelopes(runtime.store.policiesLogFor(runtime.bondId))) {
      final body = Policy.tryDecode(env.body);
      if (body == null) continue;
      _acceptPolicy(runtime, body, envelopeBytes: encodeEnvelope(env));
    }
    for (final env in await _readLogEnvelopes(runtime.store.revocationsLogFor(runtime.bondId))) {
      final body = Revocation.tryDecode(env.body);
      if (body == null) continue;
      final pairEnv = RevocationEnvelope(revocation: body, envelope: env);
      if (!_revocationAuthorized(runtime, pairEnv)) continue;
      final revokedHex = _hex(body.revokedPubkey);
      final prior = runtime.revokedAt[revokedHex];
      // On replay trust the persisted effective time directly — no
      // wallclock clamp; receipt-time clamping already happened at
      // live acceptance.
      if (prior == null || body.effectiveAtMs > prior) {
        runtime.revokedAt[revokedHex] = body.effectiveAtMs;
      }
    }
    // Proposals: replay before attestations so the inbox view has
    // every known proposal already populated by the time attestation
    // counts are computed against them.
    for (final env in await _readLogEnvelopes(runtime.store.proposalsLogFor(runtime.bondId))) {
      final body = Proposal.tryDecode(env.body);
      if (body == null) continue;
      final signerHex = _hex(env.signerPublicKey);
      if (_isRevokedAt(runtime, signerHex, body.createdMs)) continue;
      final pid = _hex(_sha256(body.toCborBody()));
      runtime.proposalsById.putIfAbsent(
        pid,
        () => _StoredProposal(
          proposalId: pid,
          proposal: body,
          signerHex: signerHex,
          receivedMs: body.createdMs,
        ),
      );
    }
    // RefAdverts: replay last-known per signer from refs/<signer>.json.
    // These are persisted as a single "last value" (not append-only)
    // because only the latest matters for fetch/pull routing.
    await _rehydrateAdvertsFromDisk(runtime);
    for (final env in await _readLogEnvelopes(runtime.store.attestationsLogFor(runtime.bondId))) {
      final body = Attestation.tryDecode(env.body);
      if (body == null) continue;
      final signerHex = _hex(env.signerPublicKey);
      if (_isRevokedAt(runtime, signerHex, body.createdMs)) continue;
      final pid = _hex(body.proposalId);
      final list = runtime.attestationsByProposal
          .putIfAbsent(pid, () => <_SignedAttestation>[]);
      final existingIdx = list.indexWhere((a) => a.signerHex == signerHex);
      if (existingIdx >= 0) {
        if (body.createdMs <= list[existingIdx].att.createdMs) continue;
        list[existingIdx] = _SignedAttestation(att: body, signerHex: signerHex);
      } else {
        list.add(_SignedAttestation(att: body, signerHex: signerHex));
      }
    }
    runtime.peersNotifier.bump();
  }

  /// Reads each per-signer ref-advert JSON in `refs/<signer>.json`
  /// (written by [_persistAdvert]) and seeds `lastAdverts` so the
  /// replay-protection clock is correct on next inbound advert. The
  /// JSON files are last-value-wins (not append-only logs) — only
  /// the most-recent advert per signer matters for fetch/pull.
  ///
  /// We don't reverify signatures here: the `_persistAdvert` write
  /// path only fires after [verifyEnvelope] succeeded, and the file
  /// is in our own .git/manifold tree (not user-writeable in normal
  /// flows). If signature reverification becomes a hard requirement
  /// later, switch to persisting the full envelope alongside the
  /// decoded refs and wire it through `_readLogEnvelopes`.
  Future<void> _rehydrateAdvertsFromDisk(_RepoRuntime runtime) async {
    final dir = Directory(runtime.store.refsDirFor(runtime.bondId));
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (!name.endsWith('.json')) continue;
      final base = name.substring(0, name.length - 5);
      // Skip the local "self.json" — that's our outbound advert; it
      // doesn't belong in lastAdverts (which tracks remote signers).
      if (base == 'self') continue;
      // Validate the basename is a 64-char lowercase hex pubkey.
      if (base.length != 64 || !RegExp(r'^[0-9a-f]+$').hasMatch(base)) {
        continue;
      }
      try {
        final raw = await entry.readAsString();
        final json = jsonDecode(raw);
        if (json is! Map<String, dynamic>) continue;
        final lamport = json['lamport'];
        final createdMs = json['created_ms'];
        final refsRaw = json['refs'];
        if (lamport is! int || createdMs is! int || refsRaw is! Map) continue;
        final refs = <String, Uint8List>{};
        for (final e in refsRaw.entries) {
          final k = e.key;
          final v = e.value;
          if (k is! String || v is! String) continue;
          if (v.length != 40 && v.length != 64) continue;
          if (!RegExp(r'^[0-9a-f]+$').hasMatch(v)) continue;
          refs[k] = _unhex(v);
        }
        runtime.lastAdverts[base] = RefAdvert(
          bondId: runtime.bondId.bytes,
          lamportClock: lamport,
          refs: refs,
          createdMs: createdMs,
        );
      } catch (_) {
        // Skip torn / hand-edited / format-evolved files; live
        // gossip will re-establish state from the next inbound
        // advert.
      }
    }
  }

  /// Reads a log file and returns verified envelopes in file order.
  /// Lines that fail to parse or verify are skipped — never surfaces
  /// to users because log corruption is best-effort operational.
  Future<List<SignedEnvelope>> _readLogEnvelopes(String path) async {
    final records = await readJsonl(path);
    final out = <SignedEnvelope>[];
    for (final rec in records) {
      final b64 = rec['env_b64'];
      if (b64 is! String) continue;
      try {
        final bytes = base64.decode(b64);
        final parse = decodeEnvelope(Uint8List.fromList(bytes));
        if (!parse.ok) continue;
        final verified = await verifyEnvelope(parse.envelope!);
        if (!verified.ok) continue;
        out.add(verified.envelope!);
      } catch (_) {
        // Skip torn/garbled line; appendJsonl's crash-mid-write policy
        // allows these to exist.
      }
    }
    return out;
  }

  Future<SwarmKeyPair> _identity(BondId bondId) async {
    final cached = _identityCache[bondId.hex];
    if (cached != null) return cached;
    final kp = await resolveIdentity(bondId);
    _identityCache[bondId.hex] = kp;
    // Once we know our own pubkey for this bond, place ourselves on
    // the lattice so distance-based fetch ordering can centre on us
    // instead of the origin. Idempotent — placement is deterministic
    // per (bondId, pubkey).
    for (final runtime in _runtimes.values) {
      if (identical(runtime.bondId.bytes, bondId.bytes) ||
          _bytesEq(runtime.bondId.bytes, bondId.bytes)) {
        unawaited(_placePeerOnLattice(
          runtime,
          kp.publicKeyBytes,
          _hex(kp.publicKeyBytes),
        ));
      }
    }
    return kp;
  }

  /// Given the peer's latest advert, returns the set of commit hashes
  /// we want but don't have locally.
  Future<List<String>> _wantedFromAdvert(
    _RepoRuntime runtime, {
    required PeerSession peer,
    required void Function(String) onLog,
  }) async {
    final hex = _hex(peer.session.remotePubkey);
    final advert = runtime.lastAdverts[hex];
    if (advert == null) {
      onLog('bond: no advert yet from ${_shortHex(peer.session.remotePubkey)}');
      return const [];
    }
    final wanted = <String>[];
    for (final hash in advert.refs.values) {
      final hexHash = _hex(hash);
      if (!await hasObject(runtime.repoPath, hexHash)) {
        wanted.add(hexHash);
      }
    }
    return wanted;
  }

  /// Sends an objectWant with the requested hashes and waits for the
  /// matching objectPack response. Each request carries a 16-byte
  /// random id; the responder echoes it in the pack body so we filter
  /// the broadcast `peer.packfiles` stream for our specific reply.
  /// The per-peer fetch lock still serialises gossip turns (so we
  /// don't pile on a slow peer) but correlation no longer depends on
  /// it.
  Future<bool> _requestPack({
    required _RepoRuntime runtime,
    required PeerSession peer,
    required List<String> wanted,
  }) async {
    final hex = _hex(peer.session.remotePubkey);
    final prior = runtime.fetchLocks[hex] ?? Future<void>.value();
    final completer = Completer<void>();
    runtime.fetchLocks[hex] = completer.future;
    try {
      await prior;
      final reqId = newRequestId();
      // Hint a few local refs as "have" so the responder prunes
      // their closure from the pack. Limited to 32 hashes to keep
      // the want body small; for larger histories this is still a
      // big win (delta compression eliminates everything reachable).
      final localHaves = await _localHaves(runtime);
      final wantBytes = ObjectWantBody(
        requestId: reqId,
        want: wanted,
        have: localHaves,
      ).encode();
      // Subscribe to the broadcast packfiles stream BEFORE sending the
      // want — subscribing after could miss a fast peer. Filter for
      // our request id so other in-flight responses don't mis-attach.
      final packFuture = peer.packfiles
          .map(ObjectPackBody.tryDecode)
          .where((p) => p != null && requestIdEquals(p.requestId, reqId))
          .cast<ObjectPackBody>()
          .first
          .timeout(const Duration(seconds: 30));
      await peer.sendRaw(BondPacketType.objectWant, wantBytes);
      final pack = await packFuture;
      if (pack.error != null) {
        runtime.dropCounters['pack_remote_error'] =
            (runtime.dropCounters['pack_remote_error'] ?? 0) + 1;
        return false;
      }
      if (pack.pack.isEmpty) return false;
      // For packs above the spool threshold, write to a tmp file then
      // pipe into git index-pack via OS-level copy. Halves peak memory
      // (we don't hold packBytes alongside git's internal index buffer)
      // and prepares the path for future wire-streaming where bytes
      // arrive incrementally rather than as one Uint8List event.
      const spoolThreshold = 8 * 1024 * 1024;
      if (pack.pack.length >= spoolThreshold) {
        final tmpDir = await Directory.systemTemp.createTemp('bond_pack_');
        final tmp = File('${tmpDir.path}/incoming.pack');
        try {
          await tmp.writeAsBytes(pack.pack, flush: true);
          await indexPackfileFromFile(
            repoPath: runtime.repoPath,
            packFile: tmp,
          );
        } finally {
          try {
            await tmpDir.delete(recursive: true);
          } catch (_) {}
        }
      } else {
        await indexPackfile(
          repoPath: runtime.repoPath,
          packBytes: pack.pack,
        );
      }
      return true;
    } finally {
      completer.complete();
      if (identical(runtime.fetchLocks[hex], completer.future)) {
        runtime.fetchLocks.remove(hex);
      }
    }
  }

  /// Responder half: peer sent a CBOR-framed objectWant. Decode, build
  /// the pack, echo the request id back so the requester correlates.
  Future<void> _respondToWant(
    _RepoRuntime runtime,
    PeerSession peer,
    Uint8List body,
  ) async {
    final want = ObjectWantBody.tryDecode(body);
    if (want == null) {
      runtime.dropCounters['malformed_want'] =
          (runtime.dropCounters['malformed_want'] ?? 0) + 1;
      runtime.peersNotifier.bump();
      return;
    }
    Uint8List packBytes;
    String? errMsg;
    try {
      if (want.want.isEmpty) {
        packBytes = Uint8List(0);
      } else {
        final built = await buildPackfile(
          repoPath: runtime.repoPath,
          wanted: want.want,
          have: want.have,
        );
        packBytes = built.bytes;
      }
    } catch (e) {
      packBytes = Uint8List(0);
      // Surface the error to the requester so they don't sit on a
      // 30-second timeout for a build failure we already know about.
      errMsg = 'pack build failed';
      runtime.dropCounters['pack_build_failed'] =
          (runtime.dropCounters['pack_build_failed'] ?? 0) + 1;
      runtime.peersNotifier.bump();
    }
    try {
      await peer.sendRaw(
        BondPacketType.objectPack,
        ObjectPackBody(
          requestId: want.requestId,
          pack: packBytes,
          error: errMsg,
        ).encode(),
      );
    } catch (_) {
      // Best-effort send; peer may have closed mid-build.
    }
  }

  /// Evaluates current policy for a pending merge. Returns `allowed=true`
  /// when no rule matches the target ref or when every matching rule's
  /// `minApprovals` is satisfied by attestations whose `targetCommit`
  /// equals the head commit of [sourceRef], signed by non-revoked keys
  /// in the rule's `approverSet` (or any non-revoked key when the
  /// approverSet is empty).
  Future<_PolicyVerdict> _policyGate(
    _RepoRuntime runtime, {
    required String targetRef,
    required String sourceRef,
  }) async {
    final policy = runtime.currentPolicy;
    if (policy == null) {
      // No policy = no gate. First-launch bonds operate open until an
      // initiator publishes one.
      return const _PolicyVerdict(allowed: true, reason: 'no policy set');
    }
    final matching = policy.rules
        .where((r) => _globMatch(r.refPattern, targetRef))
        .toList(growable: false);
    if (matching.isEmpty) {
      return const _PolicyVerdict(allowed: true, reason: 'no matching rule');
    }

    final srcHead = await _resolveCommitHash(runtime.repoPath, sourceRef);
    if (srcHead == null) {
      return const _PolicyVerdict(
        allowed: false,
        reason: 'source ref resolves to no commit',
      );
    }
    final srcBytes = _unhex(srcHead);

    for (final rule in matching) {
      if (rule.minApprovals <= 0) continue;
      // Collect distinct-signer `approve` attestations that pin to
      // this exact source commit and whose signer isn't revoked.
      final approvers = <String>{};
      for (final entry in runtime.attestationsByProposal.entries) {
        for (final signed in entry.value) {
          final att = signed.att;
          if (att.verdict != AttestationVerdict.approve) continue;
          if (!_bytesEq(att.targetCommit, srcBytes)) continue;
          if (_isRevokedAt(runtime, signed.signerHex, att.createdMs)) continue;
          if (rule.approverSet.isNotEmpty) {
            final inSet = rule.approverSet.any(
              (k) => _hex(k) == signed.signerHex,
            );
            if (!inSet) continue;
          }
          approvers.add(signed.signerHex);
        }
      }
      if (approvers.length < rule.minApprovals) {
        return _PolicyVerdict(
          allowed: false,
          reason:
              'rule "${rule.refPattern}" needs ${rule.minApprovals} approvals, has ${approvers.length}',
        );
      }
    }
    return const _PolicyVerdict(allowed: true, reason: 'policy satisfied');
  }

  bool _isRevokedAt(_RepoRuntime runtime, String signerHex, int createdMs) {
    final effective = runtime.revokedAt[signerHex];
    return effective != null && createdMs >= effective;
  }

  bool _bytesEq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<String?> _resolveCommitHash(String repoPath, String ref) async {
    final result = await Process.run(
      'git',
      ['rev-parse', '--verify', ref],
      workingDirectory: repoPath,
      runInShell: false,
    );
    if (result.exitCode != 0) return null;
    final hex = (result.stdout as String).trim();
    return _isPlausibleHash(hex) ? hex : null;
  }

  /// Minimal git-refspec glob match. Supports `*` (no slash) and `**`
  /// (arbitrary path segments). `refs/heads/*` matches `refs/heads/main`
  /// but not `refs/heads/feature/x`; `refs/heads/**` matches both.
  static bool _globMatch(String pattern, String target) {
    final regex = _compileGlob(pattern);
    return regex.hasMatch(target);
  }

  static RegExp _compileGlob(String pattern) {
    final sb = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == '*') {
        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
          sb.write('.*');
          i++;
        } else {
          sb.write('[^/]*');
        }
      } else if ('.^\$+?()[]{}|\\'.contains(c)) {
        sb.write('\\$c');
      } else {
        sb.write(c);
      }
    }
    sb.write(r'$');
    return RegExp(sb.toString());
  }

  /// Sample of recent local commit hashes used as the `have` hint in
  /// objectWant. Walks each `refs/heads/*` tip back a few steps via
  /// `git rev-list`, deduped + capped at 32 entries. Empty on any
  /// error (graceful — responder just skips the prune).
  Future<List<String>> _localHaves(_RepoRuntime runtime) async {
    try {
      final headRefs = await Process.run(
        'git',
        ['for-each-ref', '--format=%(objectname)', 'refs/heads/'],
        workingDirectory: runtime.repoPath,
        runInShell: false,
      );
      if (headRefs.exitCode != 0) return const [];
      final tips = (headRefs.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where(_isPlausibleHash)
          .toSet();
      final have = <String>{};
      for (final tip in tips) {
        final more = await reachableCommits(
          repoPath: runtime.repoPath,
          startHash: tip,
          limit: 8,
        );
        for (final c in more) {
          have.add(c);
          if (have.length >= 32) return have.toList();
        }
      }
      return have.toList();
    } catch (_) {
      return const [];
    }
  }

  static bool _isPlausibleHash(String s) {
    if (s.length != 40 && s.length != 64) return false;
    for (final c in s.codeUnits) {
      final isHex = (c >= 0x30 && c <= 0x39) ||
          (c >= 0x61 && c <= 0x66);
      if (!isHex) return false;
    }
    return true;
  }

  Future<void> _persistAdvert(
    _RepoRuntime runtime,
    Uint8List signerPubkey,
    RefAdvert advert,
  ) async {
    final signerHex = _hex(signerPubkey);
    final path = runtime.store.refsPathForSigner(runtime.bondId, signerHex);
    final record = <String, dynamic>{
      'signer': signerHex,
      'lamport': advert.lamportClock,
      'created_ms': advert.createdMs,
      'refs': advert.refs.map((k, v) => MapEntry(k, _hex(v))),
    };
    await _atomicWriteJson(path, record);
  }

  Future<void> _persistSelfAdvert(
    _RepoRuntime runtime,
    SwarmKeyPair identity,
    RefAdvert advert,
  ) async {
    final path = runtime.store.selfRefsPathFor(runtime.bondId);
    final record = <String, dynamic>{
      'signer': _hex(identity.publicKeyBytes),
      'lamport': advert.lamportClock,
      'created_ms': advert.createdMs,
      'refs': advert.refs.map((k, v) => MapEntry(k, _hex(v))),
    };
    await _atomicWriteJson(path, record);
  }

  /// Write-then-rename to avoid torn JSON on crash. `File.rename` is
  /// atomic within one filesystem on Unix and Windows.
  Future<void> _atomicWriteJson(
    String path,
    Map<String, dynamic> record,
  ) async {
    final tmp = File('$path.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(jsonEncode(record), flush: true);
    await tmp.rename(path);
  }

  Future<int> _loadLamport(_RepoRuntime runtime) async {
    final file = File(runtime.store.lamportPathFor(runtime.bondId));
    if (!await file.exists()) return 0;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded['self'] is int) {
        return decoded['self'] as int;
      }
    } catch (_) {
      // Corrupt lamport file: start from zero and overwrite on next
      // persist. Safe because signed adverts carry the authoritative
      // clock anyway.
    }
    return 0;
  }

  Future<void> _persistLamport(_RepoRuntime runtime) async {
    await _atomicWriteJson(
      runtime.store.lamportPathFor(runtime.bondId),
      <String, dynamic>{'self': runtime.lamportClock},
    );
  }

  /// Refname allow-list. Advert refs must be `refs/heads/<name>` or
  /// `refs/tags/<name>`, and the `<name>` component must not contain
  /// path traversal, control chars, `@{`, etc. A malicious peer
  /// advertising `../../HEAD` would otherwise let us clobber refs
  /// outside the `refs/bond/<signer>/` namespace.
  static final RegExp _refNameAllowed =
      RegExp(r'^refs/(heads|tags)/[A-Za-z0-9._][A-Za-z0-9._/-]*$');

  static bool _isSafeRefName(String refName) {
    if (!_refNameAllowed.hasMatch(refName)) return false;
    if (refName.contains('..')) return false;
    if (refName.contains('@{')) return false;
    if (refName.endsWith('/')) return false;
    if (refName.endsWith('.lock')) return false;
    return true;
  }

  /// Writes refs from an accepted advert into the `refs/bond/<signer>/`
  /// namespace via `git update-ref` so hooks + reflog fire and the
  /// refname is validated by git itself. Returns the number of refs
  /// actually updated (unsafe or failing entries are skipped).
  Future<int> _writeBondRefs(
    _RepoRuntime runtime,
    String signerHex,
    RefAdvert advert,
  ) async {
    var written = 0;
    for (final entry in advert.refs.entries) {
      final refName = entry.key;
      if (!_isSafeRefName(refName)) continue;
      final hash = _hex(entry.value);
      if (!_isPlausibleHash(hash)) continue;
      final proc = await Process.run(
        'git',
        [
          'update-ref',
          'refs/bond/$signerHex/$refName',
          hash,
        ],
        workingDirectory: runtime.repoPath,
        runInShell: false,
      );
      if (proc.exitCode == 0) written += 1;
    }
    return written;
  }

  /// Reads local `refs/heads/*` and returns a map of ref name → commit
  /// hash bytes. Used when building our outbound RefAdvert.
  Future<Map<String, Uint8List>> _readLocalHeads(String repoPath) async {
    final result = await Process.run(
      'git',
      ['for-each-ref', '--format=%(refname) %(objectname)', 'refs/heads/'],
      workingDirectory: repoPath,
      runInShell: false,
    );
    if (result.exitCode != 0) return const {};
    final out = <String, Uint8List>{};
    for (final line in (result.stdout as String).split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final space = trimmed.indexOf(' ');
      if (space <= 0) continue;
      final refName = trimmed.substring(0, space);
      final hashHex = trimmed.substring(space + 1);
      if (hashHex.length != 40 && hashHex.length != 64) continue;
      out[refName] = _unhex(hashHex);
    }
    return out;
  }

  String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String _shortHex(Uint8List bytes) => _hex(bytes).substring(0, 8);

  Uint8List _unhex(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

}
