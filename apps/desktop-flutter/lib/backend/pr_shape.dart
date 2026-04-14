// ═════════════════════════════════════════════════════════════════════════
// pr_shape.dart — geometric / magnetic signature of a PR
//
// A PR isn't a queue entry; it's a magnet dropped into a field. Its
// FOOTPRINT is the heat-kernel diffusion of its touched files through
// the repo's coupling graph (φ_PR ∈ ℝⁿ, n = engine.nodePaths.length).
// Its ORIENTATION is the cosine of φ_PR against the rolling field
// vector (φ_field), which encodes "what direction the codebase has
// been moving lately" via recency-decayed touch weights.
//
// Signals derived per PR:
//   • combined φ vector + top-K bloom (the magnet's reach)
//   • coherence — focused vs scattered (magnet sharpness)
//   • per-axis mass fractions (which observable lit up)
//   • stability — robustness of the top-K under weight perturbation
//   • metabolism risk — Σ curvature(f)·touches[f] (touching the bones?)
//   • field alignment — cosine vs the rolling activity field
//
// Pairwise: cosine of two PR φ vectors gives "orbital partnership"
// (the legacy `_prCollisionMap` is a binary file-overlap; this is the
// continuous geometric upgrade).
//
// Pure data + pure functions. No I/O, no Flutter. Caching/lifetime is
// the caller's problem (BranchesPageState owns the per-PR map).
// ═════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:typed_data';

import 'gh.dart';
import 'logos_git.dart';

/// Single Logos label used for PR-shape diffusion. Per-axis attribution
/// isn't meaningful for an arbitrary PR (we don't have a probe-style
/// classifier here), so we collapse to one bucket and read the dense φ
/// vector out of `perAxisPhi.values.single`.
const String _prShapeAxis = '_pr';

/// Same-shape label for the field-vector diffusion. Distinct from the
/// PR axis just for readability when debugging mixed snapshots.
const String _fieldAxis = '_field';

/// Coarse buckets for `PrShape.fieldAlignment`. Heat-kernel φ is
/// non-negative so cosine ∈ [0, 1] — "against the field" isn't
/// representable here without signed flows. The thresholds partition
/// [0, 1] into thirds biased toward "needs attention" (the high-
/// alignment band is narrowest because alignment is the easy case).
enum FieldOrientation {
  /// cosine ≥ 0.5 — PR's mass largely overlaps the field. Swimming
  /// with the current; the easy review.
  withField,

  /// 0.2 ≤ cosine < 0.5 — partial overlap. The PR's neighborhood
  /// touches some of where activity is concentrated but extends
  /// beyond it. Common case for incremental feature work.
  adjacent,

  /// cosine < 0.2 — PR lives in a corner of the graph the field
  /// barely reaches. New territory, or stale work resurfacing.
  /// Worth a closer look — this is where surprises hide.
  orthogonal,
}

/// Geometric signature of a single PR — the data the orbital
/// list-ordering, rail tinting, and "WILL FIGHT" pairwise visualisation
/// all read from. Constructed via [PrShapeComputer.compute].
///
/// Immutable. Cheap to hold per-PR; dense vectors are compact (8 bytes
/// per node, ≤ a few KB for typical repos).
class PrShape {
  /// Dense φ vector indexed by [LogosGit.nodePaths]. Sums across the
  /// single `_pr` axis bucket. Used for cosine similarity (with field,
  /// with other PRs).
  final Float64List phi;

  /// Top-K most-relevant paths in the diffused neighborhood. Includes
  /// the PR's own files plus coupled neighbors that absorbed heat
  /// (the "bloom"). Sorted descending by φ.
  final List<RelevanceScore> topK;

  /// Multi-axis Born-mixed coherence over the PR's source files —
  /// 1.0 = tightly clustered (the PR knows what it's about), low =
  /// scattered. Falls back to 1.0 when ≤1 source paths are in-graph.
  final double coherence;

  /// Stability of the top-K under small weight perturbations.
  /// Measures whether the φ ranking is structurally robust or
  /// knife-edge. ∈ [0, 1].
  final double stability;

  /// Σ `LogosGit.curvature(path) × touches[path]` across PR files.
  /// Curvature is bounded [0.5, 1.0] so this is bounded above by the
  /// total touch sum. Higher = the PR is editing the codebase's bones
  /// (regularly-touched, load-bearing files).
  final double metabolismRisk;

  /// Cosine of `phi` against the field vector. ∈ [0, 1].
  /// 1.0 = full overlap with the recent-activity field; 0 = orthogonal.
  /// `null` when the field hasn't been computed yet.
  final double? fieldAlignment;

  /// Bucketed [fieldAlignment]. `null` when alignment is null.
  final FieldOrientation? orientation;

  /// Per-axis fraction map. With the single-axis collapse this is
  /// `{'_pr': 1.0}` — kept for forward compatibility with axis-aware
  /// classification later (e.g. splitting PR files into code vs test
  /// mirrors).
  final Map<String, double> axisMassFractions;

  /// When this shape was computed. Used for cache freshness checks
  /// against the field-vector snapshot.
  final DateTime computedAt;

  const PrShape({
    required this.phi,
    required this.topK,
    required this.coherence,
    required this.stability,
    required this.metabolismRisk,
    required this.fieldAlignment,
    required this.orientation,
    required this.axisMassFractions,
    required this.computedAt,
  });
}

/// The rolling activity field — `recentActivityWeights` diffused
/// through the engine. Snapshot stable until invalidated; PR shapes
/// re-bind to the latest snapshot when they recompute their
/// alignment.
class ActivityField {
  final Float64List phi;
  final int halfLifeCommits;
  final DateTime computedAt;

  const ActivityField({
    required this.phi,
    required this.halfLifeCommits,
    required this.computedAt,
  });
}

class PrShapeComputer {
  /// Compute a PR's geometric signature. `engine` is the resolved
  /// LogosGit for the repo; `prFiles` are the changed files (path +
  /// additions + deletions). `field` is optional — when present, the
  /// shape carries [PrShape.fieldAlignment] and [PrShape.orientation].
  ///
  /// Returns null when the engine is empty or none of the PR files
  /// land in-graph (a brand-new file the engine hasn't analyzed yet).
  static PrShape? compute({
    required LogosGit engine,
    required List<PrFile> prFiles,
    ActivityField? field,
    double t = 1.0,
  }) {
    if (engine.nodePaths.isEmpty || prFiles.isEmpty) return null;

    // Touch weight = additions + deletions. Aggregate per path in case
    // the PR file list ever contains duplicates.
    final touches = <String, double>{};
    for (final f in prFiles) {
      final w = (f.additions + f.deletions).toDouble();
      if (w <= 0) continue;
      touches[f.path] = (touches[f.path] ?? 0) + w;
    }
    if (touches.isEmpty) return null;

    // Single-axis attribution — we want the dense φ vector for cosine
    // math. Per-axis split isn't meaningful without a classifier.
    final axisLabels = <String, String>{
      for (final p in touches.keys) p: _prShapeAxis,
    };
    final attr = engine.diffuseWithAttribution(
      weightsByPath: touches,
      axisLabelByPath: axisLabels,
      t: t,
    );
    if (attr == null) return null;

    // Dense φ — single-axis case, perAxisPhi has exactly one entry.
    final phi = attr.perAxisPhi.values.first;

    // Coherence: read the raw co-change Jaccard matrix, NOT the
    // engine's sparsified graph. `engine.coherence` measures weights
    // that survived top-K-per-node sparsification — for a PR whose two
    // files both have stronger neighbours elsewhere, their cross-edge
    // gets pruned out and coherence bottoms at exactly 0 even when the
    // files genuinely co-change. The matrix is pre-sparsification, and
    // its `coherenceFor` already handles the confidence-gate for young
    // repos (< 50 commits → 0.5 uncertainty prior). For mature repos
    // with truly unrelated files, it still returns 0 honestly.
    final coh = engine.stats.coupling.coherenceFor(touches.keys);

    // Stability — robustness of top-K under weight perturbation.
    final stab = engine.diffuseStability(touches, t: t);

    // Metabolism risk — Σ curvature(path) × touches[path] over PR files
    // that are actually in the graph (curvature(p) returns 1.0 for
    // out-of-graph paths, which would inflate risk artificially).
    var metab = 0.0;
    for (final entry in touches.entries) {
      if (!engine.pathToId.containsKey(entry.key)) continue;
      metab += engine.curvature(entry.key) * entry.value;
    }

    // Field alignment — cosine of dense φ vectors. Bound to [0, 1]
    // because both vectors are non-negative.
    double? align;
    FieldOrientation? orient;
    if (field != null && field.phi.length == phi.length) {
      align = cosine(phi, field.phi);
      orient = bucketAlignment(align);
    }

    return PrShape(
      phi: phi,
      topK: attr.combined.take(20).toList(),
      coherence: coh,
      stability: stab,
      metabolismRisk: metab,
      fieldAlignment: align,
      orientation: orient,
      axisMassFractions: attr.axisMassFractions(),
      computedAt: DateTime.now(),
    );
  }

  /// Compute the rolling activity field. Diffuses recency-decayed
  /// touch weights through the engine and returns the dense φ vector.
  /// Snapshot once per session (or per refresh) so PR alignments are
  /// stable across rebuilds.
  static ActivityField? computeField({
    required LogosGit engine,
    int halfLifeCommits = 30,
    double t = 1.0,
  }) {
    if (engine.nodePaths.isEmpty) return null;
    final weights = engine.recentActivityWeights(halfLifeCommits: halfLifeCommits);
    if (weights.isEmpty) return null;
    final axisLabels = <String, String>{
      for (final p in weights.keys) p: _fieldAxis,
    };
    final attr = engine.diffuseWithAttribution(
      weightsByPath: weights,
      axisLabelByPath: axisLabels,
      t: t,
    );
    if (attr == null) return null;
    return ActivityField(
      phi: attr.perAxisPhi.values.first,
      halfLifeCommits: halfLifeCommits,
      computedAt: DateTime.now(),
    );
  }

  /// Cosine similarity of two equal-length non-negative vectors.
  /// Returns 0 when either vector has zero norm.
  static double cosine(Float64List a, Float64List b) {
    assert(a.length == b.length);
    var dot = 0.0;
    var na = 0.0;
    var nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na <= 0 || nb <= 0) return 0;
    final c = dot / (math.sqrt(na) * math.sqrt(nb));
    if (c.isNaN || !c.isFinite) return 0;
    return c.clamp(0.0, 1.0);
  }

  /// Bucket a cosine value into a [FieldOrientation]. Thresholds match
  /// the enum docstring.
  static FieldOrientation bucketAlignment(double cos) {
    if (cos >= 0.5) return FieldOrientation.withField;
    if (cos >= 0.2) return FieldOrientation.adjacent;
    return FieldOrientation.orthogonal;
  }
}
