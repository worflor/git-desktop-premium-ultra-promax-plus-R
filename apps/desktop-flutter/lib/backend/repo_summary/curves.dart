// curves.dart — self-calibrating threshold detectors.
//
// Two primitives every repo-summary phase reuses:
//
//   • kneeIndex  — the "elbow" of a sorted sequence, by maximum
//     perpendicular distance from the chord between endpoints.
//     Emergent. No fixed percentage, no fixed count — the cutoff is
//     wherever the distribution itself bends from head to tail.
//
//   • maxGapIndex — the index with the largest forward difference in
//     an ordered sequence. Used for the eigengap heuristic: natural
//     cluster count = 1 + argmax_i(λ_{i+1} - λ_i) over the excited
//     spectrum.
//
// Every threshold in the pipeline routes through one of these. There
// are no hand-tuned cuts.

import 'dart:math' as math;

/// Return the index of the knee in a sorted-descending sequence.
/// The knee is the point farthest from the chord connecting the first
/// and last values. For a flat or degenerate sequence returns the last
/// index (keep everything).
int kneeIndex(List<double> sortedDesc) {
  final n = sortedDesc.length;
  if (n < 3) return n - 1;
  final first = sortedDesc.first;
  final last = sortedDesc.last;
  final dy = last - first;
  final dx = (n - 1).toDouble();
  final chordNorm = math.sqrt(dx * dx + dy * dy);
  if (chordNorm <= 0) return n - 1;
  // A flat sequence has no knee; keep everything.
  if (first - last < 1e-12) return n - 1;

  // Perpendicular distance from point (i, y) to the chord A=(0, first),
  // B=(n-1, last): |cross((B-A), (P-A))| / |B-A|. With (B-A) = (dx, dy)
  // and (P-A) = (i, y-first), the 2D cross is dx*(y-first) - dy*i.
  var bestIdx = 0;
  var bestDist = -double.infinity;
  for (var i = 1; i < n - 1; i++) {
    final px = i.toDouble();
    final py = sortedDesc[i];
    final cross = (dx * (py - first) - dy * px).abs();
    final dist = cross / chordNorm;
    if (dist > bestDist) {
      bestDist = dist;
      bestIdx = i;
    }
  }
  return bestIdx;
}

/// Return the index `i` in `[start, end)` at which the forward
/// difference `values[i+1] - values[i]` is largest. Pass the range
/// carefully: callers using the eigengap heuristic should pass
/// `[firstExcitedIndex, k-1)` so they skip the kernel and don't
/// index past the end.
///
/// Returns `start` when the range is too short to measure a gap.
int maxGapIndex(List<double> values, {required int start, required int end}) {
  if (end - start < 2) return start;
  var bestIdx = start;
  var bestGap = -double.infinity;
  for (var i = start; i < end - 1; i++) {
    final gap = values[i + 1] - values[i];
    if (gap > bestGap) {
      bestGap = gap;
      bestIdx = i;
    }
  }
  return bestIdx;
}
