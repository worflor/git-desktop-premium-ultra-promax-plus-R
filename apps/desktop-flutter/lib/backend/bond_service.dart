// ═════════════════════════════════════════════════════════════════════════
// bond_service.dart — top-level process-wide Bond state
//
// Holds the user's unlocked [MasterSeed], derived [SwarmKeyPair]s per
// bond, the [BondBackend] instance, and the map of which repos are
// bonded. Exposes [ChangeNotifier] so the UI rebuilds on identity
// unlock and bond membership changes.
//
// Lifecycle:
//   • Process start: construct with a [BondTransport] (Loopback in
//     dev, Whisper in prod). No identity yet; isUnlocked == false.
//   • User enters phrase in BondPage → [unlock] derives master seed.
//   • [bindBond] registers a repo ↔ bond_id mapping (computed once
//     from bootstrap commit + swarm phrase, persisted in repo config).
//   • [backend] reads these mappings via resolveBondForRepo.
//   • [lock] wipes the master seed from memory; isUnlocked flips false.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'bond/bond_backend.dart';
import 'bond/bond_id.dart';
import 'bond/identity.dart';
import 'bond/invite.dart';
import 'bond/objects.dart';
import 'bond/safety_number.dart';
import 'bond/transport.dart';

/// One repo ↔ one bond mapping, persisted under
/// `.git/manifold/bond/bonds/<bond_hex>/config.json`.
class BondMembership {
  const BondMembership({
    required this.repoPath,
    required this.bondId,
    required this.bootstrapCommit,
    required this.displayName,
  });

  final String repoPath;
  final BondId bondId;
  final String bootstrapCommit;

  /// Local-only label shown in the UI. Never transmitted.
  final String displayName;
}

class BondService extends ChangeNotifier {
  BondService({required BondTransport transport}) : _transport = transport {
    _backend = BondBackend(
      transport: _transport,
      resolveIdentity: _resolveIdentity,
      resolveBondForRepo: _resolveBondForRepo,
    );
  }

  final BondTransport _transport;
  late final BondBackend _backend;

  MasterSeed? _master;
  final Map<String, SwarmKeyPair> _keys = {};
  final Map<String, BondMembership> _byRepo = {};

  /// The configured transport. Exposed so tests can inject loopback
  /// session pairs via [BondBackend.attachPeerSession].
  BondTransport get transport => _transport;

  /// The shared BondBackend instance. Subscribers to the
  /// CollaborationBackend seam read this value when the active
  /// backend is `'bond'`.
  BondBackend get backend => _backend;

  /// True after a successful [unlock]. Drives the UI's "locked" vs
  /// "unlocked" state.
  bool get isUnlocked => _master != null;

  /// Enumerated bond memberships the service knows about. Read-only.
  Iterable<BondMembership> get memberships => _byRepo.values;

  /// Derives the master seed from the user's phrase. Running
  /// Argon2id off the UI thread is the caller's responsibility (this
  /// method awaits synchronously); wrap in `compute` when calling
  /// from a button handler. Throws on empty phrase.
  Future<void> unlock(String phrase) async {
    if (phrase.trim().isEmpty) {
      throw ArgumentError('phrase is required');
    }
    _master?.wipe();
    _keys.clear();
    // Argon2id at production parameters is ~1s. Run off the UI
    // isolate so the unlock button + any concurrent animation don't
    // jank for the duration.
    final seed = await compute<String, MasterSeed>(_deriveMasterInIsolate, phrase);
    _master = seed;
    notifyListeners();
  }

  /// Wipes the in-memory master and all derived subkeys. The UI
  /// should call this on app lock / screen lock / user logout.
  /// Also tears down active peer sessions via the backend so we
  /// don't keep signing with keys that no longer match the unlocked
  /// identity.
  void lock() {
    _master?.wipe();
    _master = null;
    _keys.clear();
    notifyListeners();
    unawaited(_backend.onIdentityChanged());
  }

  /// Registers a repo ↔ bond mapping. If the mapping is new it is
  /// persisted under the repo's `.git/manifold/bond/bonds/<hex>/` so
  /// a later process start can re-resolve without re-prompting.
  ///
  /// [swarmPhrase] is the swarm-specific phrase — NOT the identity
  /// phrase. Different layer of the model; see the design note.
  Future<BondMembership> bindBond({
    required String repoPath,
    required String bootstrapCommit,
    required String swarmPhrase,
    required String displayName,
  }) async {
    final bondId = await deriveBondId(
      bootstrapCommitHash: bootstrapCommit,
      swarmPhrase: swarmPhrase,
    );
    final membership = BondMembership(
      repoPath: repoPath,
      bondId: bondId,
      bootstrapCommit: bootstrapCommit,
      displayName: displayName,
    );
    _byRepo[repoPath] = membership;
    await _persistMembership(membership);
    notifyListeners();
    return membership;
  }

  /// Reload memberships from disk for the given repo. Called when a
  /// repo opens, before any collaboration surface renders.
  Future<void> loadFromDisk(String repoPath) async {
    final configs = await _readRepoConfigs(repoPath);
    if (configs.isEmpty) return;
    // v1: one bond per repo. Multi-bond support is a later iteration;
    // the on-disk layout already supports it.
    final first = configs.first;
    _byRepo[repoPath] = first;
    notifyListeners();
  }

  /// Returns the bond membership for a given repo, or null if the
  /// repo has not been bonded.
  BondMembership? membershipFor(String repoPath) => _byRepo[repoPath];

  /// Builds an invite blob the user can share with a peer. The invite
  /// carries only public inputs (bond id + bootstrap commit + label) —
  /// the swarm phrase is intentionally NOT included, so a leaked
  /// invite is not on its own a credential. Peers still need the
  /// phrase out-of-band.
  String buildInvite(String repoPath) {
    final m = membershipFor(repoPath);
    if (m == null) {
      throw StateError('buildInvite called for non-bonded repo');
    }
    return BondInvite(
      bondId: m.bondId,
      bootstrapCommit: m.bootstrapCommit,
      displayName: m.displayName,
    ).encode();
  }

  /// Pre-fills a bind from an invite blob. Returns the parsed invite
  /// so the UI can show "joining {name}" state; the user still types
  /// the swarm phrase before committing.
  BondInvite parseInvite(String blob) => BondInvite.decode(blob);

  /// Accept an invite + swarm phrase → full bind. Convenience wrapper
  /// for the join flow so the UI doesn't have to chain parse + bind
  /// itself.
  Future<BondMembership> bindFromInvite({
    required String repoPath,
    required String inviteBlob,
    required String swarmPhrase,
    String? overrideDisplayName,
  }) async {
    final invite = BondInvite.decode(inviteBlob);
    return bindBond(
      repoPath: repoPath,
      bootstrapCommit: invite.bootstrapCommit,
      swarmPhrase: swarmPhrase,
      displayName: overrideDisplayName?.trim().isNotEmpty == true
          ? overrideDisplayName!.trim()
          : (invite.displayName.isNotEmpty ? invite.displayName : 'Bond'),
    );
  }

  /// Removes a repo's bond membership: tears down sessions, wipes
  /// per-bond state on disk, drops the membership from memory.
  ///
  /// Does NOT publish a revocation (use [publishRevocation] for that —
  /// call it BEFORE unbinding if you want remote peers to notice).
  Future<void> unbind(String repoPath) async {
    await backend.unbind(repoPath);
    _byRepo.remove(repoPath);
    notifyListeners();
  }

  /// Derives this device's pubkey for a given bond (cached) and
  /// returns the fingerprint string that should appear in the UI.
  /// Returns null if the user is locked.
  Future<String?> fingerprintFor(BondId bondId) async {
    try {
      final kp = await _resolveIdentity(bondId);
      return fingerprintHex(kp.publicKeyBytes);
    } catch (_) {
      return null;
    }
  }

  /// Computes the 50-digit pair-pubkey safety number for a peer
  /// (SHA-256 over sorted pair, fast). Returns null if locked.
  Future<String?> safetyNumberWith({
    required BondId bondId,
    required Uint8List peerPubkey,
  }) async {
    try {
      final me = await _resolveIdentity(bondId);
      return computeSafetyNumber(me.publicKeyBytes, peerPubkey);
    } catch (_) {
      return null;
    }
  }

  /// Canonical kizuna-witness safety number for a peer. Bit-identical
  /// on both ends; this is the number that matches what a live session
  /// derives during handshake. Slower than [safetyNumberWith] (one
  /// 16D Möbius residual over a 65 KiB block), so the UI surfaces it
  /// async behind the verify dialog.
  Future<String?> kizunaSafetyNumberWith({
    required BondId bondId,
    required Uint8List peerPubkey,
  }) async {
    try {
      final me = await _resolveIdentity(bondId);
      return await computeKizunaSafetyNumber(me.publicKeyBytes, peerPubkey);
    } catch (_) {
      return null;
    }
  }

  /// Publishes a continuity attestation (welcome-back announcement or
  /// deliberate rotation). Delegates to the backend; returns a
  /// GitResult the UI can render.
  Future<String?> publishContinuity({
    required String repoPath,
    required String reason,
  }) async {
    final r = await backend.publishContinuity(repoPath: repoPath, reason: reason);
    return r.ok ? null : r.error;
  }

  /// Publishes a self or peer revocation. Returns null on success,
  /// or an error message for the UI.
  Future<String?> publishRevocation({
    required String repoPath,
    required Uint8List revokedPubkey,
    required RevokeReason reason,
    String detail = '',
  }) async {
    final r = await backend.publishRevocation(
      repoPath: repoPath,
      revokedPubkey: revokedPubkey,
      reason: reason,
      reasonDetail: detail,
    );
    return r.ok ? null : r.error;
  }

  /// Publishes a Policy, installs it locally as the current rules.
  Future<String?> publishPolicy({
    required String repoPath,
    required List<PolicyRule> rules,
  }) async {
    final r = await backend.publishPolicy(repoPath: repoPath, rules: rules);
    return r.ok ? null : r.error;
  }

  /// Publishes a proposal. Returns the 32-byte proposalId on success
  /// (call sites pin it to a local draft/inbox entry). Wraps the
  /// backend's GitResult into a simpler success/error shape the UI
  /// can throw on.
  Future<({Uint8List? proposalId, String? error})> publishProposal({
    required String repoPath,
    required Uint8List recipientPubkey,
    required String sourceRef,
    required Uint8List sourceCommit,
    required String targetRef,
    required String title,
    required String body,
  }) async {
    final r = await backend.publishProposal(
      repoPath: repoPath,
      recipientPubkey: recipientPubkey,
      sourceRef: sourceRef,
      sourceCommit: sourceCommit,
      targetRef: targetRef,
      title: title,
      body: body,
    );
    return (proposalId: r.data, error: r.error);
  }

  /// Publishes an attestation on a proposal. The caller supplies the
  /// proposal hash + target commit; the UI component that renders a
  /// proposal knows both.
  Future<String?> publishAttestation({
    required String repoPath,
    required Uint8List proposalId,
    required AttestationVerdict verdict,
    required String body,
    required Uint8List targetCommit,
  }) async {
    final r = await backend.publishAttestation(
      repoPath: repoPath,
      proposalId: proposalId,
      verdict: verdict,
      body: body,
      targetCommit: targetCommit,
    );
    return r.ok ? null : r.error;
  }

  /// Removes all state and closes active peer sessions. The transport
  /// is NOT closed (owned by the embedder). Safe during app shutdown.
  Future<void> dispose_() async {
    await _backend.shutdown();
    lock();
    _byRepo.clear();
  }

  // ───────────────────── internals ─────────────────────

  Future<SwarmKeyPair> _resolveIdentity(BondId bondId) async {
    final cached = _keys[bondId.hex];
    if (cached != null) return cached;
    final master = _master;
    if (master == null) {
      throw StateError(
        'BondService: identity not unlocked; call unlock(phrase) first',
      );
    }
    final kp = await deriveSwarmKeyPair(master: master, bondId: bondId.bytes);
    _keys[bondId.hex] = kp;
    return kp;
  }

  Future<BondId?> _resolveBondForRepo(String repoPath) async {
    return _byRepo[repoPath]?.bondId;
  }

  /// Top-level isolate entry for Argon2id. Must be a top-level
  /// function, not a method, because `compute` only accepts static
  /// or top-level targets — instance methods carry closure state.
  static MasterSeed _deriveMasterInIsolate(String phrase) =>
      deriveMasterSeed(phrase);

  Future<void> _persistMembership(BondMembership m) async {
    final dir = Directory(
      p.join(m.repoPath, '.git', 'manifold', 'bond', 'bonds', m.bondId.hex),
    );
    await dir.create(recursive: true);
    final finalPath = p.join(dir.path, 'config.json');
    final tmp = File('$finalPath.tmp');
    await tmp.writeAsString(
      jsonEncode(<String, dynamic>{
        'bond_id': m.bondId.hex,
        'bootstrap_commit': m.bootstrapCommit,
        'display_name': m.displayName,
      }),
      flush: true,
    );
    // tmp + rename = atomic replace across crash on both Unix and
    // Windows. A torn write on the truncate-then-write path would have
    // left zero-byte configs that silently broke rebind.
    await tmp.rename(finalPath);
  }

  static final RegExp _hexOnly = RegExp(r'^[0-9a-f]+$');

  Future<List<BondMembership>> _readRepoConfigs(String repoPath) async {
    final bondsDir = Directory(
      p.join(repoPath, '.git', 'manifold', 'bond', 'bonds'),
    );
    if (!await bondsDir.exists()) return const [];
    final out = <BondMembership>[];
    await for (final entry in bondsDir.list()) {
      if (entry is! Directory) continue;
      final config = File(p.join(entry.path, 'config.json'));
      if (!await config.exists()) continue;
      try {
        final decoded = jsonDecode(await config.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        final hex = decoded['bond_id'] as String?;
        final bootstrap = decoded['bootstrap_commit'] as String?;
        final name = decoded['display_name'] as String? ?? '';
        if (hex == null ||
            hex.length != 64 ||
            !_hexOnly.hasMatch(hex) ||
            bootstrap == null) {
          continue;
        }
        final bytes = Uint8List(32);
        for (var i = 0; i < 32; i++) {
          bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
        }
        out.add(BondMembership(
          repoPath: repoPath,
          bondId: BondId.fromBytes(bytes),
          bootstrapCommit: bootstrap,
          displayName: name,
        ));
      } catch (_) {
        // Skip malformed config; fresh bind will overwrite.
      }
    }
    return out;
  }
}
