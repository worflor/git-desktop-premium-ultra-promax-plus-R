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

import '../collaboration_backend.dart';
import '../dtos.dart';
import '../git_result.dart';
import 'bond_id.dart';
import 'identity.dart';
import 'objects.dart';
import 'packfile.dart';
import 'peer_session.dart';
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
    required Object addressing,
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
    peer.start();
    final subs = <StreamSubscription<dynamic>>[];
    subs.add(peer.refAdverts.listen((advert) {
      final existingAdvert = runtime.lastAdverts[hex];
      // Replay protection: never regress a signer's Lamport clock. A
      // properly-signed but older advert is dropped.
      if (existingAdvert != null &&
          advert.lamportClock <= existingAdvert.lamportClock) {
        return;
      }
      runtime.lastAdverts[hex] = advert;
      unawaited(_persistAdvert(runtime, peer.session.remotePubkey, advert));
    }));
    subs.add(peer.objectWants.listen((body) {
      unawaited(_respondToWant(runtime, peer, body));
    }));
    runtime.peerSubs[hex] = subs;
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
    return runtime;
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
