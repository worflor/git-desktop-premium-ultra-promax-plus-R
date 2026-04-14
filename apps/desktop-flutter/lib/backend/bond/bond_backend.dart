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
  });

  final BondId bondId;
  final List<BondPeerView> peers;
  final Policy? currentPolicy;
  final Map<String, int> dropCounters;

  /// proposalId hex → attestation count.
  final Map<String, int> attestationCounts;

  /// Received proposals, newest first.
  final List<BondProposalView> proposals;
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
  });

  final String pubkeyHex;
  final bool attached;
  final int? lastSeenMs;
  final int? advertLamport;
  final int refCount;

  /// Non-null when this peer's key has been revoked (in effect from
  /// this epoch-ms). Rendered as a strikethrough / warning badge.
  final int? revokedAt;

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
    subs.add(peer.policies.listen((policy) {
      runtime.lastSeenMs[hex] = DateTime.now().millisecondsSinceEpoch;
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
      runtime.currentPolicy = policy;
      runtime.peersNotifier.bump();
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
    }));
    runtime.peerSubs[hex] = subs;
    runtime.peersNotifier.bump();
  }

  bool _isRevoked(
    _RepoRuntime runtime,
    Uint8List signerPubkey,
    int createdMs,
  ) {
    final effective = runtime.revokedAt[_hex(signerPubkey)];
    return effective != null && createdMs >= effective;
  }

  /// Authorizes an inbound revocation against current bond rules.
  /// Self-revocation is always honored. Peer revocation requires the
  /// revoker to appear in any current-policy rule's approverSet — the
  /// same authority that would approve a merge is empowered to eject
  /// a key. With no policy set, only self-revocation is honored (v1
  /// cautious default).
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
    final peers = runtime.peers.values.toList(growable: false);
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
      // supersedes: hash of the prior policy envelope would go here.
      // For v1 we don't track envelope hashes of incoming policies,
      // so null; peers that missed the prior policy cannot detect a
      // missed link. Hardening: persist policy envelope bytes and hash
      // when accepting, pass that hash here.
      supersedes: null,
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
    final current = runtime.currentPolicy;
    if (current == null || policy.effectiveAtMs > current.effectiveAtMs) {
      runtime.currentPolicy = policy;
    }
    runtime.peersNotifier.bump();
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
    // against currentPolicy / revokedAt.
    for (final env in await _readLogEnvelopes(runtime.store.policiesLogFor(runtime.bondId))) {
      final body = Policy.tryDecode(env.body);
      if (body == null) continue;
      if (!_policyWellFormed(body)) continue;
      final current = runtime.currentPolicy;
      if (current == null || body.effectiveAtMs > current.effectiveAtMs) {
        runtime.currentPolicy = body;
      }
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
  /// matching objectPack response. Serialised per peer via
  /// [_RepoRuntime.fetchLocks] — the wire has no correlation ID, so
  /// two concurrent waits against the same broadcast stream could
  /// attach a pack to the wrong request. Returns `false` when the
  /// peer responded with an empty pack or no pack within the timeout.
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
      final wantBody = utf8.encode(wanted.join('\n'));
      // Subscribe to the broadcast packfiles stream BEFORE sending the
      // want — subscribing after could miss a very fast peer.
      final packFuture = peer.packfiles.first
          .timeout(const Duration(seconds: 30));
      await peer.sendRaw(
        BondPacketType.objectWant,
        Uint8List.fromList(wantBody),
      );
      final pack = await packFuture;
      if (pack.isEmpty) return false;
      await indexPackfile(
        repoPath: runtime.repoPath,
        packBytes: pack,
      );
      return true;
    } finally {
      completer.complete();
      if (identical(runtime.fetchLocks[hex], completer.future)) {
        runtime.fetchLocks.remove(hex);
      }
    }
  }

  /// Responder half: peer asked for a pack containing [body] commit
  /// hashes (newline-separated hex). Build a pack locally and send it
  /// back over the same session.
  Future<void> _respondToWant(
    _RepoRuntime runtime,
    PeerSession peer,
    Uint8List body,
  ) async {
    try {
      final wanted = utf8
          .decode(body)
          .split('\n')
          .map((l) => l.trim())
          .where(_isPlausibleHash)
          .toList(growable: false);
      if (wanted.isEmpty) {
        await peer.sendRaw(BondPacketType.objectPack, Uint8List(0));
        return;
      }
      final pack = await buildPackfile(
        repoPath: runtime.repoPath,
        wanted: wanted,
      );
      await peer.sendRaw(BondPacketType.objectPack, pack.bytes);
    } catch (_) {
      // Swallow — responder is best-effort. A failing peer gets a
      // silent drop; requester sees timeout.
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
