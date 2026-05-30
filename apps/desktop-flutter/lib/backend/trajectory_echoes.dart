// TRAJECTORY ECHOES — past commits that resonate spectrally with the
// diff's predicted landing.
//
// The temporal counterpart to the engine's spatial divergent-
// neighborhood. Where divergent-neighborhood asks "which files are
// spectrally adjacent to the diff in the current graph?", echoes
// asks "which past commits had a graph spectrally adjacent to where
// this diff is heading?"
//
// Method:
//   1. Take the current state (basis at HEAD) and the predicted
//      tangent from [readDiffMotion].
//   2. For every past TrajectoryPoint, compute eigenvalue distance
//      between (current eigenvalues + tangent) and that point's
//      eigenvalues — truncated to the smaller k where bases disagree.
//   3. Sort ascending. The smallest distances are the strongest
//      echoes: past moments when the repo's spectrum was nearest to
//      where this diff is taking the repo.
//
// Two surfaces:
//   - lightEchoes(): top-3 for the brainstorm prompt — sha + timestamp
//     so the divergent model can seed past-rooted ideas without
//     bloating the cheap call.
//   - reshapedEchoes(): top-N for the synthesis prompt, re-ranked by
//     a brainstorm-cited-path overlap weight (past commits whose
//     strong modes load on the brainstorm-cited files get boosted —
//     the temporal twin of reshapedRelevance).
//
// All measurement. No magic constants — the rank is eigenvalue
// distance, the reshape weight is a true eigenvector amplitude
// inner-product on the cited file set.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart' show SpectralBasis, SpectralGroundSpace;
import 'spectral_trajectory.dart';

/// A past trajectory point spectrally resonant with where the diff
/// is heading. `distance` is the eigenvalue distance from
/// `(currentEigs + predictedTangent)` to this point's eigenvalues,
/// truncated to the smaller k.
class TrajectoryEcho {
  final int revision;
  final String? commitSha;
  final DateTime? timestamp;

  /// Eigenvalue distance — smaller = stronger resonance.
  final double distance;

  /// Reshape weight when this echo was reranked by brainstorm-cited
  /// paths. Zero in the unranked / light surface; non-zero when the
  /// past point's eigenvectors load on the cited files.
  final double reshapeWeight;

  const TrajectoryEcho({
    required this.revision,
    required this.commitSha,
    required this.timestamp,
    required this.distance,
    this.reshapeWeight = 0.0,
  });

  /// 7-char short sha for citation. Empty when [commitSha] is null
  /// or shorter than 7 chars (synthetic / test fixtures).
  String get shortSha {
    final s = commitSha;
    if (s == null) return '';
    return s.length >= 7 ? s.substring(0, 7) : s;
  }
}

/// Top-K echoes for the brainstorm prompt. Pure eigenvalue-distance
/// ranking — no reshape. Excludes the trajectory's tip (the head
/// point) since echoing-against-self is uninformative.
///
/// Returns an empty list when:
///   - trajectory is null / empty / shorter than 2 points
///   - currentEigs has zero useful k
///   - predictedTangent is empty (no diff motion to project against)
List<TrajectoryEcho> lightEchoes({
  required SpectralTrajectory? trajectory,
  required SpectralBasis currentBasis,
  required Float64List predictedTangent,
  int topK = 3,
}) {
  if (trajectory == null || trajectory.length < 2) return const [];
  if (predictedTangent.isEmpty) return const [];

  final projected = _projectedEigenvalues(
    currentBasis: currentBasis,
    tangent: predictedTangent,
  );
  if (projected.isEmpty) return const [];

  final scored = <TrajectoryEcho>[];
  // Exclude the tip — comparing landing-point to itself returns 0
  // distance and would always dominate the ranking.
  final lastIndex = trajectory.length - 1;
  for (var i = 0; i < lastIndex; i++) {
    final point = trajectory.points[i];
    final pBasis = point.state.fileSpectrum;
    // Skip null and degenerate (k==0) bases. A genesis/boundary commit
    // touching <2 files yields an empty-eigenvalue basis; its truncated
    // distance is a meaningless 0.0 that would otherwise sort to the top
    // as the "strongest" echo.
    if (pBasis == null || pBasis.eigenvalues.isEmpty) continue;
    final dist = _truncatedEigenvalueDistance(projected, pBasis.eigenvalues);
    if (!dist.isFinite) continue;
    scored.add(TrajectoryEcho(
      revision: point.revision,
      commitSha: point.commitSha,
      timestamp: point.timestamp,
      distance: dist,
    ));
  }
  if (scored.isEmpty) return const [];
  scored.sort((a, b) => a.distance.compareTo(b.distance));
  return scored.take(topK).toList(growable: false);
}

/// Reshaped echoes — like [lightEchoes] but reranked so past commits
/// whose strong modes load on the brainstorm-cited paths float to
/// the top. The reshape uses a true eigenvector-amplitude weight on
/// the cited file set: for each past point, compute the squared-
/// amplitude sum of its non-trivial modes restricted to the cited
/// paths, normalised per cited file. Combine with the eigenvalue
/// distance via a Boltzmann-style multiplicative tilt:
///
///     score = distance · exp(−weight)
///
/// At `weight = 0` the score is `distance` (recovers [lightEchoes]
/// ordering). At higher weights — past commits whose eigenmodes load
/// strongly on the cited files — the score is pulled toward smaller
/// values. Multiplicative — no additive smoothing constant.
///
/// [citedPaths] are the paths the brainstorm referenced. When empty,
/// the result is equivalent to [lightEchoes] up to [topK].
List<TrajectoryEcho> reshapedEchoes({
  required SpectralTrajectory? trajectory,
  required SpectralBasis currentBasis,
  required Float64List predictedTangent,
  required Set<String> citedPaths,
  int topK = 6,
}) {
  if (trajectory == null || trajectory.length < 2) return const [];
  if (predictedTangent.isEmpty) return const [];

  final projected = _projectedEigenvalues(
    currentBasis: currentBasis,
    tangent: predictedTangent,
  );
  if (projected.isEmpty) return const [];

  final lastIndex = trajectory.length - 1;
  final scored = <_ScoredEcho>[];
  for (var i = 0; i < lastIndex; i++) {
    final point = trajectory.points[i];
    final pBasis = point.state.fileSpectrum;
    // Skip null and degenerate (k==0) bases — see lightEchoes for why an
    // empty-eigenvalue genesis snapshot must not rank as a 0.0-distance echo.
    if (pBasis == null || pBasis.eigenvalues.isEmpty) continue;
    final dist = _truncatedEigenvalueDistance(projected, pBasis.eigenvalues);
    if (!dist.isFinite) continue;
    final weight = citedPaths.isEmpty
        ? 0.0
        : _citedPathLoading(pBasis, citedPaths);
    final score = dist * math.exp(-weight);
    scored.add(_ScoredEcho(
      echo: TrajectoryEcho(
        revision: point.revision,
        commitSha: point.commitSha,
        timestamp: point.timestamp,
        distance: dist,
        reshapeWeight: weight,
      ),
      score: score,
    ));
  }
  if (scored.isEmpty) return const [];
  scored.sort((a, b) => a.score.compareTo(b.score));
  return scored.take(topK).map((s) => s.echo).toList(growable: false);
}

/// Format a compact `<temporal_echoes>` block for the brainstorm
/// prompt — one line per echo, sha + timestamp + distance. Empty
/// when [echoes] is empty.
String formatLightEchoesBlock(List<TrajectoryEcho> echoes) {
  if (echoes.isEmpty) return '';
  final buf = StringBuffer();
  for (final e in echoes) {
    final ts = e.timestamp == null
        ? ''
        : ' (${_formatTimeAgo(e.timestamp!)})';
    final sha = e.shortSha.isEmpty ? 'rev${e.revision}' : e.shortSha;
    buf.writeln('  $sha$ts  distance=${e.distance.toStringAsFixed(3)}');
  }
  return buf.toString().trimRight();
}

/// Format a full `<temporal_neighborhood>` block for the synthesis
/// prompt — adds reshape weight where present so the model can read
/// which echoes were boosted by brainstorm overlap vs. raw spectrum.
String formatReshapedEchoesBlock(List<TrajectoryEcho> echoes) {
  if (echoes.isEmpty) return '';
  final buf = StringBuffer();
  for (final e in echoes) {
    final ts = e.timestamp == null
        ? ''
        : ' (${_formatTimeAgo(e.timestamp!)})';
    final sha = e.shortSha.isEmpty ? 'rev${e.revision}' : e.shortSha;
    final w = e.reshapeWeight > 0
        ? ' weight=${e.reshapeWeight.toStringAsFixed(2)}'
        : '';
    buf.writeln('  $sha$ts  distance=${e.distance.toStringAsFixed(3)}$w');
  }
  return buf.toString().trimRight();
}

// ── internals ────────────────────────────────────────────────────

/// Return `currentBasis.eigenvalues + tangent`, clamped non-negative
/// and truncated to the shorter length.
Float64List _projectedEigenvalues({
  required SpectralBasis currentBasis,
  required Float64List tangent,
}) {
  final k = math.min(currentBasis.k, tangent.length);
  if (k == 0) return Float64List(0);
  final out = Float64List(k);
  for (var j = 0; j < k; j++) {
    final v = currentBasis.eigenvalues[j] + tangent[j];
    out[j] = v < 0 ? 0.0 : v;
  }
  return out;
}

/// Truncated Wasserstein-1 distance between two eigenvalue vectors,
/// matched by rank up to the shorter length. Mirrors the trajectory
/// engine's internal `_truncatedEigenvalueDistance` so per-step and
/// per-echo distances live on the same scale.
double _truncatedEigenvalueDistance(Float64List a, Float64List b) {
  final k = math.min(a.length, b.length);
  if (k == 0) return 0.0;
  var s = 0.0;
  for (var j = 0; j < k; j++) {
    final d = a[j] - b[j];
    s += d < 0 ? -d : d;
  }
  return s / k;
}

/// Sum of eigenvector amplitudes (L2) on the cited paths, accumulated
/// across the basis's non-trivial modes. A real measurement: how
/// strongly do this past basis's eigenmodes load on the files the
/// brainstorm referenced?
///
/// Returns 0 when the past basis has no nodePaths metadata (unlabeled
/// math-only basis), no overlap between [citedPaths] and the
/// basis's nodePaths, or k < 2 (no non-trivial modes).
double _citedPathLoading(SpectralBasis pastBasis, Set<String> citedPaths) {
  final paths = pastBasis.nodePaths;
  if (paths == null || paths.isEmpty) return 0.0;
  if (pastBasis.k < 2) return 0.0;
  final ids = <int>[];
  for (var i = 0; i < paths.length; i++) {
    if (citedPaths.contains(paths[i])) ids.add(i);
  }
  if (ids.isEmpty) return 0.0;
  // Skip the kernel of the Laplacian — its modes (one per connected
  // component) carry no structural information about which files
  // cluster with which. Past trajectory bases on disconnected file
  // graphs have firstExcitedIndex > 1, so the hardcoded "1" of an
  // earlier draft would mis-include zero modes on those snapshots.
  final start = pastBasis.firstExcitedIndex;
  final n = pastBasis.n;
  var sum = 0.0;
  for (var j = start; j < pastBasis.k; j++) {
    final base = j * n;
    for (final id in ids) {
      if (id >= n) continue;
      final v = pastBasis.eigenvectors[base + id];
      sum += v * v;
    }
  }
  // Normalise by the number of cited files so the weight is a per-
  // file mean amplitude rather than a sum that grows with cited-set
  // size.
  return sum / ids.length;
}

String _formatTimeAgo(DateTime t) {
  final now = DateTime.now().toUtc();
  final delta = now.difference(t.toUtc()).abs();
  if (delta.inDays >= 365) {
    final y = delta.inDays / 365.0;
    return '${y.toStringAsFixed(1)}y ago';
  }
  if (delta.inDays >= 30) {
    final m = delta.inDays / 30.0;
    return '${m.toStringAsFixed(1)}mo ago';
  }
  if (delta.inDays >= 1) return '${delta.inDays}d ago';
  if (delta.inHours >= 1) return '${delta.inHours}h ago';
  if (delta.inMinutes >= 1) return '${delta.inMinutes}m ago';
  return 'just now';
}

class _ScoredEcho {
  final TrajectoryEcho echo;
  final double score;
  _ScoredEcho({required this.echo, required this.score});
}
