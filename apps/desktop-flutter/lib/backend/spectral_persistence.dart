// SPECTRAL PERSISTENCE — disk-backed cache for SpectralBasis blobs.
//
// Now that [SpectralBasis.toBytes] emits a deterministic blob keyed
// by [SpectralBasis.signature], a disk layer lets us:
//
//   - **Instant-on-restart**: persist basis blobs on close; load on
//     open, skip the Lanczos build entirely when the graph signature
//     matches.
//   - **Cross-session caching**: expensive spectrum computations
//     (first-paint on a new repo) happen ONCE per HEAD state. After
//     that, every session until HEAD moves hits disk in milliseconds.
//   - **Offline-first**: closing and reopening the app produces the
//     same evidence as an unbroken session.
//
// Signature is the key. The blob filename is
// `<signature_hex>.logos-basis` — rename-free, content-addressed,
// cheap to GC when HEAD moves and the old signature becomes stale.
//
// Discipline: persistence is strictly a READ-THROUGH cache on a pure
// function. Nothing computed here should be authoritative; if the
// blob is missing or corrupt, rebuild from graph. That keeps the
// persistence layer a performance knob, not a correctness risk.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'logos_core.dart';

/// A disk-backed cache for [SpectralBasis] blobs.
///
/// Stores blobs under a caller-supplied directory; each blob is
/// content-addressed by its [SpectralBasis.signature]. Multiple
/// engines (file / hunk / chunk / commit) can share the same directory
/// without collision — the signature is the uniqueness guarantee.
class SpectralBasisCache {
  SpectralBasisCache({required this.directory});

  /// Directory the cache owns. Created lazily on first write.
  final Directory directory;

  String _pathFor(int signature) =>
      p.join(directory.path, '${_hex(signature)}.logos-basis');

  /// Persist [basis] to disk. Overwrites any existing entry with the
  /// same signature (which by definition would carry identical bytes).
  /// Best-effort: any I/O error is swallowed — persistence is a
  /// performance cache, never a correctness requirement.
  Future<void> write(SpectralBasis basis) async {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final file = File(_pathFor(basis.signature));
      await file.writeAsBytes(basis.toBytes(), flush: false);
    } catch (_) {
      // Swallowed on purpose — see class-level doc.
    }
  }

  /// Attempt to read a basis blob by its [signature]. Returns null on
  /// cache miss, corrupt file, or read error. Callers should always
  /// have a rebuild path for the null case.
  Future<SpectralBasis?> read(int signature) async {
    try {
      final file = File(_pathFor(signature));
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return SpectralBasis.fromBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Synchronous read — for paths where we need the result before the
  /// next UI frame and are willing to accept whatever latency the
  /// filesystem gives us.
  SpectralBasis? readSync(int signature) {
    try {
      final file = File(_pathFor(signature));
      if (!file.existsSync()) return null;
      final bytes = file.readAsBytesSync();
      return SpectralBasis.fromBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Delete every cached blob whose signature isn't in [keep]. Use
  /// after HEAD moves to evict stale spectra. Best-effort; never
  /// throws.
  Future<void> prune(Set<int> keep) async {
    try {
      if (!await directory.exists()) return;
      final keepNames = <String>{for (final s in keep) '${_hex(s)}.logos-basis'};
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.endsWith('.logos-basis')) continue;
        if (keepNames.contains(name)) continue;
        try {
          await entity.delete();
        } catch (_) {
          // Fine — another process may have beaten us.
        }
      }
    } catch (_) {
      // Fine — cache integrity isn't authoritative.
    }
  }

  /// Remove every cached blob. Used on "clear caches" UI paths.
  Future<void> clear() async {
    try {
      if (!await directory.exists()) return;
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        if (!p.basename(entity.path).endsWith('.logos-basis')) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }
}

/// 16-char lowercase hex representation of a 64-bit-ish integer. The
/// signature hash is a positive int that fits in ≤62 bits; padding to
/// 16 hex chars is harmless and keeps filenames uniform for ls/find.
String _hex(int v) {
  final s = v.toRadixString(16);
  if (s.length >= 16) return s;
  return '0' * (16 - s.length) + s;
}
