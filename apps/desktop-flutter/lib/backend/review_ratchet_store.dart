// review_ratchet_store.dart — per-repo persistence for the claim
// outcome ratchet (axis 5 of the review scorer).
//
// Each accept/dismiss the user makes on a finding is recorded, keyed by
// the claim's quantised shape. The learned posterior feeds back as a
// per-shape prior in composeReviewScore. State is kept per repository —
// shape outcomes are repo-specific (a "low-grounding warn about a
// generated file" means different things in different codebases) — as a
// small JSON file under the app data dir, mirroring AiSettingsStore.

import 'dart:async';
import 'dart:io';

import 'atomic_write.dart';
import 'review_ratchet.dart' show ClaimOutcomeRatchet;
import 'storage_paths.dart' show StoragePaths;

class ReviewRatchetStore {
  ReviewRatchetStore._();

  /// Serialises the load→observe→persist read-modify-write so concurrent
  /// observations can't each load the pre-observation state and clobber one
  /// another. Mirrors CommandTelemetryStore's single-writer chain.
  static Future<void> _writeLock = Future<void>.value();

  /// FNV-1a (32-bit) of the repo path — a stable, filesystem-safe key
  /// so two repos never collide and the filename survives restarts
  /// (unlike String.hashCode, which is not guaranteed stable).
  static String _key(String repoPath) {
    var hash = 0x811c9dc5;
    for (final c in repoPath.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Future<File> _fileFor(String repoPath) async {
    final dataDir = await StoragePaths.gdpuDataDir();
    final sep = Platform.pathSeparator;
    final dir = Directory('${dataDir.path}${sep}ai${sep}review_ratchet');
    return File('${dir.path}$sep${_key(repoPath)}.json');
  }

  /// Load the ratchet for [repoPath]. A fresh (empty) ratchet is
  /// returned when no file exists or the file is unreadable/corrupt —
  /// losing accumulated observations is preferable to blocking review.
  static Future<ClaimOutcomeRatchet> load(String repoPath) async {
    try {
      final file = await _fileFor(repoPath);
      if (!await file.exists()) return ClaimOutcomeRatchet();
      return ClaimOutcomeRatchet.fromJsonString(await file.readAsString());
    } catch (_) {
      return ClaimOutcomeRatchet();
    }
  }

  /// Persist [ratchet] for [repoPath]. Best-effort — failures are
  /// swallowed (the learning loop is a bonus, never load-bearing).
  static Future<void> persist(
    String repoPath,
    ClaimOutcomeRatchet ratchet,
  ) async {
    try {
      final file = await _fileFor(repoPath);
      // Atomic temp-then-rename so a crash mid-write can't leave a torn
      // ratchet file (see atomic_write.dart).
      await writeFileAtomicString(file, ratchet.toJsonString());
    } catch (_) {}
  }

  /// Atomically record one observation: load → [observe] → persist, with the
  /// whole read-modify-write serialised across calls so two outcomes actioned
  /// in rapid succession don't each load the pre-observation ratchet (the
  /// second persist would otherwise silently drop the first's observation).
  /// Best-effort — failures are swallowed (the learning loop is a bonus,
  /// never load-bearing).
  static Future<void> recordObservation(
    String repoPath,
    void Function(ClaimOutcomeRatchet ratchet) observe,
  ) {
    final completer = Completer<void>();
    _writeLock = _writeLock.then((_) async {
      try {
        final ratchet = await load(repoPath);
        observe(ratchet);
        await persist(repoPath, ratchet);
      } catch (_) {
        // best-effort; never block review on a learning-loop write
      } finally {
        completer.complete();
      }
    });
    return completer.future;
  }
}
