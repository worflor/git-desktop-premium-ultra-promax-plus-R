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
    _master = deriveMasterSeed(phrase);
    notifyListeners();
  }

  /// Wipes the in-memory master and all derived subkeys. The UI
  /// should call this on app lock / screen lock / user logout.
  void lock() {
    _master?.wipe();
    _master = null;
    _keys.clear();
    notifyListeners();
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

  Future<void> _persistMembership(BondMembership m) async {
    final dir = Directory(
      p.join(m.repoPath, '.git', 'manifold', 'bond', 'bonds', m.bondId.hex),
    );
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'config.json'));
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'bond_id': m.bondId.hex,
        'bootstrap_commit': m.bootstrapCommit,
        'display_name': m.displayName,
      }),
      flush: true,
    );
  }

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
        if (hex == null || hex.length != 64 || bootstrap == null) continue;
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
