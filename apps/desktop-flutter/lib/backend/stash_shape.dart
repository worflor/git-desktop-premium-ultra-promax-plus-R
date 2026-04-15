// ═════════════════════════════════════════════════════════════════════════
// stash_shape.dart — geometric signature of a stash relative to the
// current working tree.
//
// A stash isn't a list of saved files. It's a frozen field object — a
// snapshot of intent that either resonates with what you're doing now,
// fights it, or lives in a completely orthogonal corner of the graph.
//
// Three signals, all derivable from the coupling matrix:
//
//   coherence  — how tight is the stash's own file set? A high-coherence
//                stash is a focused feature; low = scattered WIP bag.
//
//   resonance  — mean combinedCouplingScore between stash files and
//                current changed files (excluding direct overlaps).
//                High = the stash is about the same concern you're
//                working on. Low = orthogonal, can apply independently.
//
//   directOverlap — files touched in both the stash and the working tree.
//                These are the conflict candidates. Non-empty means any
//                application will fight your in-progress work.
//
// orientation — bucketed summary:
//   conflicting  directOverlap non-empty
//   bonded       resonance ≥ 0.4, no overlap
//   adjacent     0.15 ≤ resonance < 0.4, no overlap
//   orthogonal   resonance < 0.15, no overlap
// ═════════════════════════════════════════════════════════════════════════

import 'file_coupling.dart';

/// Bucketed relationship between a stash and the current working tree.
enum StashOrientation {
  /// One or more files appear in both the stash and the working tree.
  /// Any application risks a conflict.
  conflicting,

  /// High coupling between stash files and current changed files, no
  /// direct overlap. The stash is about the same concern — a natural
  /// companion to what you're building.
  bonded,

  /// Moderate coupling, no direct overlap. Adjacent concern that extends
  /// into the same neighbourhood without touching the same files.
  adjacent,

  /// Low coupling, no direct overlap. The stash lives in a different
  /// corner of the graph — independent, safe to apply at any time.
  orthogonal,
}

/// Geometric signature of a stash entry relative to the current working tree.
class StashShape {
  /// Mean pairwise coupling of the stash's own files. ∈ [0, 1].
  /// 1.0 = tight focused feature. Near 0 = scattered bag of unrelated edits.
  final double coherence;

  /// Mean coupling between stash files and current changed files,
  /// excluding direct overlaps. ∈ [0, 1].
  final double resonance;

  /// Files present in both the stash and the current working tree.
  /// Non-empty = conflict risk on apply.
  final Set<String> directOverlap;

  /// Bucketed orientation derived from [resonance] and [directOverlap].
  final StashOrientation orientation;

  const StashShape({
    required this.coherence,
    required this.resonance,
    required this.directOverlap,
    required this.orientation,
  });

  static const empty = StashShape(
    coherence: 0.5,
    resonance: 0.0,
    directOverlap: {},
    orientation: StashOrientation.orthogonal,
  );
}

/// Compute the geometric signature of a stash entry relative to the
/// current working tree changes.
///
/// [stashPaths] — file paths touched by the stash.
/// [currentPaths] — file paths in the current working tree (status.files).
/// [matrix] — the repo's coupling matrix.
///
/// Returns [StashShape.empty] when [stashPaths] is empty.
StashShape computeStashShape({
  required List<String> stashPaths,
  required List<String> currentPaths,
  required FileCouplingMatrix matrix,
}) {
  if (stashPaths.isEmpty) return StashShape.empty;

  final stashSet = stashPaths.toSet();
  final currentSet = currentPaths.toSet();

  // Direct overlap — files touched in both.
  final directOverlap = stashSet.intersection(currentSet);

  // Coherence — internal tightness of the stash's file set.
  final coherence = matrix.coherenceFor(stashPaths);

  // Resonance — coupling between stash-only and current-only files.
  // Exclude direct overlaps: those belong in the conflict bucket.
  final stashOnly = stashSet.difference(directOverlap);
  final currentOnly = currentSet.difference(directOverlap);
  double resonance = 0.0;
  if (stashOnly.isNotEmpty && currentOnly.isNotEmpty) {
    var sum = 0.0;
    var pairs = 0;
    for (final s in stashOnly) {
      for (final c in currentOnly) {
        sum += combinedCouplingScore(s, c, matrix);
        pairs++;
      }
    }
    resonance = pairs > 0 ? (sum / pairs).clamp(0.0, 1.0) : 0.0;
  }

  // Orientation.
  final StashOrientation orientation;
  if (directOverlap.isNotEmpty) {
    orientation = StashOrientation.conflicting;
  } else if (resonance >= 0.4) {
    orientation = StashOrientation.bonded;
  } else if (resonance >= 0.15) {
    orientation = StashOrientation.adjacent;
  } else {
    orientation = StashOrientation.orthogonal;
  }

  return StashShape(
    coherence: coherence,
    resonance: resonance,
    directOverlap: directOverlap,
    orientation: orientation,
  );
}
