// relevance.dart — per-file relevance scalars and active-set selection.
//
// The lens through which every downstream stage sees the repo. A file's
// relevance combines three engine-native signals:
//
//   temporal   = touchMass       — semantic-weighted, EWMA'd touches
//                                  (already computed by the logos git
//                                  ingest; decay and meaningfulness
//                                  weighting are properties of the
//                                  engine, not of this module)
//
//   authentic  = 1 - ritualness  — the fraction of the file's commits
//                                  that carry real intent (as opposed
//                                  to bot bumps, lockfile rewrites,
//                                  regeneration churn)
//
//   structural = Σ coupling      — sum of co-change Jaccard to
//                                  neighbouring files; carries brand-
//                                  new files that don't have history
//                                  yet via current-tree symbol overlap
//
// Relevance = structural × √(1 + temporal × authentic). The √ keeps
// the distribution well-scaled; the +1 ensures a file with no history
// but strong coupling still scores. A file with high ritualness
// (mechanical commits) has authentic ≈ 0, collapsing the temporal
// contribution — which is exactly how generated code gets silently
// demoted without needing a path-based exclusion list.
//
// The active set is everything above the knee of the sorted relevance
// curve. The knee is data-driven — no fixed percentage, no fixed count.

import 'dart:math' as math;

import '../file_coupling.dart';
import '../logos_git.dart';
import 'curves.dart';
import 'types.dart';

/// Per-file relevance result.
class Relevance {
  const Relevance({
    required this.score,
    required this.temporalMass,
    required this.authenticity,
    required this.structuralMass,
    required this.activePaths,
    required this.threshold,
    required this.allRanked,
  });

  /// Path → relevance scalar. Non-negative. Higher = more relevant.
  final Map<String, double> score;

  /// Path → temporal component (engine's `touchMass`).
  final Map<String, double> temporalMass;

  /// Path → authenticity (1 - engine's `ritualness`). In [0, 1].
  final Map<String, double> authenticity;

  /// Path → structural component (coupling-sum + 1 baseline).
  final Map<String, double> structuralMass;

  /// Files at or above the relevance knee, sorted by descending score.
  final List<String> activePaths;

  /// The scalar threshold used to cut the active set.
  final double threshold;

  /// Every harvested file path in descending relevance order.
  final List<String> allRanked;
}

/// Compute the relevance scalar for every file in [files], using the
/// temporal signal from [stats] (when available) and the structural
/// signal from [coupling]. Both inputs are optional.
Relevance computeRelevance({
  required List<HarvestedFile> files,
  LogosGitStats? stats,
  FileCouplingMatrix? coupling,
}) {
  if (files.isEmpty) {
    return const Relevance(
      score: {},
      temporalMass: {},
      authenticity: {},
      structuralMass: {},
      activePaths: [],
      threshold: 0.0,
      allRanked: [],
    );
  }

  // Temporal: pass the engine's touchMass through verbatim. Missing
  // entries (files never committed) score 0.
  final temporal = <String, double>{};
  if (stats != null) {
    for (final entry in stats.touchMass.entries) {
      temporal[entry.key] = entry.value;
    }
  }

  // Authenticity: 1 - ritualness. Missing entries default to 1.0
  // (we have no evidence they're ritualistic).
  final authentic = <String, double>{};
  if (stats != null) {
    for (final f in files) {
      final r = stats.ritualnessByPath[f.path] ?? 0.0;
      final a = 1.0 - r;
      authentic[f.path] = a < 0.0 ? 0.0 : (a > 1.0 ? 1.0 : a);
    }
  } else {
    for (final f in files) {
      authentic[f.path] = 1.0;
    }
  }

  // Structural: baseline of 1.0 so a file with no coupling row still
  // has non-zero structural support (rescuing fresh files). Sum of
  // Jaccard weights is the file's total coupling budget.
  final structural = <String, double>{};
  for (final f in files) {
    structural[f.path] = 1.0;
  }
  if (coupling != null) {
    for (final f in files) {
      if (!coupling.containsPath(f.path)) continue;
      var acc = 1.0;
      for (final entry in coupling.jaccardEntriesOf(f.path)) {
        acc += entry.value;
      }
      structural[f.path] = acc;
    }
  }

  // Combine: relevance = structural × √(1 + temporal × authentic) − 1.
  // The −1 pulls the baseline (structural=1, temporal=0) to zero so
  // files with nothing interesting sit at exactly the knee's tail.
  // Non-negativity is structural: `structural` has a baseline of 1.0
  // (set above), so s · √(1 + t·a) ≥ 1 · √1 = 1 and the subtraction
  // can't produce negative results. The clamp below is belt-and-
  // -braces for numerical edge cases, not a logic rescue.
  final score = <String, double>{};
  for (final f in files) {
    final t = temporal[f.path] ?? 0.0;
    final a = authentic[f.path] ?? 1.0;
    final s = structural[f.path] ?? 1.0;
    final combined = s * math.sqrt(1.0 + t * a) - 1.0;
    score[f.path] = combined < 0.0 ? 0.0 : combined;
  }

  // Rank by descending relevance.
  final ranked = files.map((f) => f.path).toList()
    ..sort((a, b) {
      final c = (score[b] ?? 0.0).compareTo(score[a] ?? 0.0);
      return c != 0 ? c : a.compareTo(b);
    });

  // Active-set knee: farthest point from the chord on the sorted curve.
  final sortedScores = ranked.map((p) => score[p] ?? 0.0).toList();
  final knee = kneeIndex(sortedScores);
  final threshold = knee < sortedScores.length ? sortedScores[knee] : 0.0;

  final active = <String>[];
  for (final p in ranked) {
    if ((score[p] ?? 0.0) >= threshold && threshold > 0.0) {
      active.add(p);
    } else if (threshold <= 0.0) {
      // All scores zero (no git history, no coupling) → keep everything.
      active.add(p);
    } else {
      break;
    }
  }

  return Relevance(
    score: Map<String, double>.unmodifiable(score),
    temporalMass: Map<String, double>.unmodifiable(temporal),
    authenticity: Map<String, double>.unmodifiable(authentic),
    structuralMass: Map<String, double>.unmodifiable(structural),
    activePaths: List<String>.unmodifiable(active),
    threshold: threshold,
    allRanked: List<String>.unmodifiable(ranked),
  );
}
