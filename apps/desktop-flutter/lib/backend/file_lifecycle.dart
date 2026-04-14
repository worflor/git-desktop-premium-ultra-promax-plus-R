import 'dart:math' as math;

import 'logos_git.dart';

/// ═════════════════════════════════════════════════════════════════════════
/// FILE LIFECYCLE — two-axis classifier per file
/// ═════════════════════════════════════════════════════════════════════════
///
/// Ports the lifecycle vocabulary from the hyperdimensional research
/// codebase (memories were classified as `candidate/reinforced/canonical`
/// for promotion strength, and `fresh/cooling/aging/stale` for decay).
/// Same shape applies cleanly to repository files: a file's history of
/// touches gives it BOTH a promotion class (how structurally important
/// it is to the repo) AND a decay class (how recently it was touched).
///
/// Both axes derive from data the engine already has — touch count
/// quantiles for promotion, recency-weighted alive-mass quantiles for
/// decay. Zero new git work; the classifier is one O(N log N) pass over
/// the repo's file universe at engine load.
/// ═════════════════════════════════════════════════════════════════════════

/// How structurally important the file is — derived from how many
/// commits in the analysed window touch it.
enum FilePromotion {
  /// Touched in a small fraction of commits — the long tail.
  candidate,

  /// Touched often enough to be a recurring member of the repo's vocab.
  reinforced,

  /// Among the most-touched files in the repo. A change here ripples;
  /// reviewers and the seismograph should mark it accordingly.
  canonical,
}

/// How recently the file was touched, normalised against the repo's
/// own commit window so the buckets are repo-relative (a "stale" file
/// in a fast-moving repo might be 2 weeks old; in a slow one, a year).
enum FileDecay {
  /// Touched in the most-recent third of the window.
  fresh,

  /// Drifting out of the active set — touched but not recently.
  cooling,

  /// Long-tail touches; structurally remembered but not under work.
  aging,

  /// No touches inside the window's active half-life cone.
  stale,
}

/// Combined per-file class. Both axes are independently meaningful —
/// a `canonical` file can be `stale` (deep infrastructure that hasn't
/// needed change recently), or a `candidate` file can be `fresh`
/// (today's experimental scratch). The seismograph renders them as
/// independent visual signals.
class FileLifecycle {
  final FilePromotion promotion;
  final FileDecay decay;
  const FileLifecycle(this.promotion, this.decay);

  /// "Quiet" files — bottom-tier promotion AND aging/stale decay. The
  /// vast majority of files in any real repo land here; we use this
  /// to skip rendering rims for the common case.
  bool get isQuiet =>
      promotion == FilePromotion.candidate &&
      (decay == FileDecay.aging || decay == FileDecay.stale);
}

/// Build a per-file classifier from a [LogosGit] engine's stats.
///
/// Promotion thresholds: top-10% of files by touch count are
/// `canonical`; next 20% are `reinforced`; the rest are `candidate`.
/// Decay thresholds: alive-mass (exp-decay over commit-age) bucketed
/// at 0.7 / 0.4 / 0.15 — a fresh file's most-recent touch is within
/// ~halfLife/2 commits, aging is past 2-3 half-lives, stale beyond 4.
///
/// Cost: O(N log N) for the touch-count sort, O(N · |touches|) for
/// the alive-mass pass. Both run once per engine; the result is a
/// `Map<String, FileLifecycle>` retained for the engine's lifetime.
Map<String, FileLifecycle> classifyFileLifecycles(
  LogosGit engine, {
  int halfLifeCommits = 30,
}) {
  final stats = engine.stats;
  if (stats.totalCommits <= 0 || stats.touches.isEmpty) {
    return const {};
  }

  // ── Promotion thresholds: 10/20/70 quantiles over touch counts.
  // Sort once, take the cut points by index.
  final touchCounts = stats.touches.values.toList()..sort();
  final n = touchCounts.length;
  // High end of "canonical" — top 10%. The threshold IS the floor of
  // the canonical band; values >= it are canonical.
  final canonicalFloor =
      touchCounts[(n * 0.90).floor().clamp(0, n - 1)];
  // Floor of "reinforced" — top 30%, excluding canonical.
  final reinforcedFloor =
      touchCounts[(n * 0.70).floor().clamp(0, n - 1)];

  // ── Decay: alive mass per file via exp-decay (same kernel that
  // `recentActivityWeights` uses, inlined here so we don't allocate
  // a duplicate Map). Half-life converted to natural-log scale; ages
  // beyond ~6 half-lives contribute < 1.5% so we early-exit.
  final tau = halfLifeCommits / math.ln2;
  final newest = stats.totalCommits - 1;
  final cutoff = halfLifeCommits * 6;

  final out = <String, FileLifecycle>{};
  // Walk every known file. Promotion key = touch count from `touches`;
  // decay key = alive mass derived from `perFileCommitIndices`.
  for (final entry in stats.touches.entries) {
    final path = entry.key;
    final touches = entry.value;
    final FilePromotion promotion;
    if (touches >= canonicalFloor) {
      promotion = FilePromotion.canonical;
    } else if (touches >= reinforcedFloor) {
      promotion = FilePromotion.reinforced;
    } else {
      promotion = FilePromotion.candidate;
    }

    final indices = stats.perFileCommitIndices[path];
    var alive = 0.0;
    if (indices != null) {
      for (var k = 0; k < indices.length; k++) {
        final age = newest - indices[k];
        if (age < 0) continue;
        if (age > cutoff) continue;
        alive += math.exp(-age / tau);
      }
    }

    final FileDecay decay;
    if (alive >= 0.7) {
      decay = FileDecay.fresh;
    } else if (alive >= 0.4) {
      decay = FileDecay.cooling;
    } else if (alive >= 0.15) {
      decay = FileDecay.aging;
    } else {
      decay = FileDecay.stale;
    }

    out[path] = FileLifecycle(promotion, decay);
  }
  return out;
}
