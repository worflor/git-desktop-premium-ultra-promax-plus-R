// ═════════════════════════════════════════════════════════════════════════
// bond/storage.dart — on-disk layout for Bond state, per repository
//
// Per-repo under `.git/manifold/bond/`:
//
//   identity/
//     master.enc            encrypted master-seed cache (opt-in; user
//                           unlocks with phrase at session start and
//                           the in-memory seed is wiped between uses)
//   bonds/<bond_hex>/
//     config.json           bond metadata (name, phrase hash for
//                           sanity checks, bootstrap commit)
//     contacts.jsonl        local address book (pubkey → label +
//                           notes); never transmitted
//     peers.jsonl           known peers with last-seen timestamps
//     refs/<signer_hex>.json  last-accepted signed ref advertisement
//                             per signer
//     refs/self.json        our own last-advertised refs + Lamport
//                           clock
//     logs/
//       proposals.jsonl     append-only proposal log (CBOR envelopes
//                           stored as base64 + metadata line)
//       attestations.jsonl  append-only attestation log
//       targets.jsonl       append-only target log
//       policies.jsonl      append-only policy log
//     ratchet/<pubkey_hex>.state  per-peer Double Ratchet state,
//                                 persisted so reconnect resumes
//                                 instead of re-handshakes
//     lamport.json          our monotonic clock + last-seen clocks
//                           per peer
//     have.bitmap           rough bitmap of locally-stored git object
//                           hashes, for OBJECT_HAVE negotiation
//
// Every file is either line-oriented JSONL (append-only logs), a
// single JSON document (config, refs), or opaque bytes (ratchet
// state, bitmap). No binary-packed formats; everything is
// human-inspectable for debugging.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'bond_id.dart';

/// Filesystem root and path helpers for one repository's Bond state.
/// One instance per repository; multiple bonds live under it.
class BondStore {
  BondStore._({required this.repoRoot});

  /// Absolute path to the host git repository.
  final String repoRoot;

  /// Public factory: resolves the store root under `.git/manifold/bond`,
  /// creates the directory if missing, returns a ready-to-use store.
  static Future<BondStore> open(String repoRoot) async {
    final store = BondStore._(repoRoot: repoRoot);
    await Directory(store._root).create(recursive: true);
    return store;
  }

  String get _root => p.join(repoRoot, '.git', 'manifold', 'bond');
  String get identityDir => p.join(_root, 'identity');
  String get bondsDir => p.join(_root, 'bonds');

  /// Filesystem root for one specific bond within this repo.
  String dirForBond(BondId bondId) => p.join(bondsDir, bondId.hex);

  String configPathFor(BondId bondId) =>
      p.join(dirForBond(bondId), 'config.json');

  String contactsPathFor(BondId bondId) =>
      p.join(dirForBond(bondId), 'contacts.jsonl');

  String peersPathFor(BondId bondId) =>
      p.join(dirForBond(bondId), 'peers.jsonl');

  String refsDirFor(BondId bondId) =>
      p.join(dirForBond(bondId), 'refs');

  String selfRefsPathFor(BondId bondId) =>
      p.join(refsDirFor(bondId), 'self.json');

  String refsPathForSigner(BondId bondId, String signerHex) =>
      p.join(refsDirFor(bondId), '$signerHex.json');

  String logsDirFor(BondId bondId) =>
      p.join(dirForBond(bondId), 'logs');

  String proposalsLogFor(BondId bondId) =>
      p.join(logsDirFor(bondId), 'proposals.jsonl');

  String attestationsLogFor(BondId bondId) =>
      p.join(logsDirFor(bondId), 'attestations.jsonl');

  String targetsLogFor(BondId bondId) =>
      p.join(logsDirFor(bondId), 'targets.jsonl');

  String policiesLogFor(BondId bondId) =>
      p.join(logsDirFor(bondId), 'policies.jsonl');

  String ratchetDirFor(BondId bondId) =>
      p.join(dirForBond(bondId), 'ratchet');

  String ratchetStatePathFor(BondId bondId, String pubkeyHex) =>
      p.join(ratchetDirFor(bondId), '$pubkeyHex.state');

  String lamportPathFor(BondId bondId) =>
      p.join(dirForBond(bondId), 'lamport.json');

  String haveBitmapPathFor(BondId bondId) =>
      p.join(dirForBond(bondId), 'have.bitmap');

  /// Ensures the directory tree for one bond exists. Idempotent.
  Future<void> ensureBondDirs(BondId bondId) async {
    await Directory(dirForBond(bondId)).create(recursive: true);
    await Directory(refsDirFor(bondId)).create(recursive: true);
    await Directory(logsDirFor(bondId)).create(recursive: true);
    await Directory(ratchetDirFor(bondId)).create(recursive: true);
  }

  /// Lists the bond ids this repo has state for. Each subdirectory
  /// under `bonds/` whose name is a 64-char hex string counts; other
  /// names are ignored (future dir types, OS detritus).
  Future<List<BondId>> listBonds() async {
    final dir = Directory(bondsDir);
    if (!await dir.exists()) return const [];
    final out = <BondId>[];
    await for (final entry in dir.list()) {
      if (entry is! Directory) continue;
      final name = p.basename(entry.path);
      if (name.length != 64 ||
          !RegExp(r'^[0-9a-f]+$').hasMatch(name)) {
        continue;
      }
      final bytes = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        bytes[i] = int.parse(name.substring(i * 2, i * 2 + 2), radix: 16);
      }
      out.add(BondId.fromBytes(bytes));
    }
    return out;
  }
}

/// Per-path write-chain lock. Dart is single-isolate but multiple
/// async futures can race on the same file — `writeAsString` is not
/// atomic with respect to other pending writes. Serialising per-path
/// ensures lines never interleave. One `Future` chain per absolute
/// path; garbage-collected implicitly once all pending writes resolve.
final Map<String, Future<void>> _jsonlWriteChains = {};

/// Utility: append a JSONL record atomically-ish. Each write opens
/// the file in append mode with a flushed close, serialised against
/// any other concurrent append to the same path via the per-path
/// write chain. Crash-mid-write safety still relies on [readJsonl]
/// skipping malformed lines.
Future<void> appendJsonl(String path, Map<String, dynamic> record) async {
  final prior = _jsonlWriteChains[path] ?? Future<void>.value();
  final completer = Completer<void>();
  _jsonlWriteChains[path] = completer.future;
  try {
    await prior;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  } finally {
    completer.complete();
    // Clean up the chain entry once we're the tail of it so the map
    // doesn't grow unboundedly across paths seen once and never
    // again. Chain tails are identified by pointer-equality against
    // our own future.
    if (identical(_jsonlWriteChains[path], completer.future)) {
      _jsonlWriteChains.remove(path);
    }
  }
}

/// Utility: read a JSONL file, skipping malformed lines. Returns an
/// empty list when the file doesn't exist.
Future<List<Map<String, dynamic>>> readJsonl(String path) async {
  final file = File(path);
  if (!await file.exists()) return const [];
  final lines = await file.readAsLines();
  final out = <Map<String, dynamic>>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) out.add(decoded);
    } catch (_) {
      // Skip malformed — survives mid-write crashes + format
      // evolution.
    }
  }
  return out;
}
