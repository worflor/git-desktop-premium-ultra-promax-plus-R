// correlatedness_hunk_sort.dart — file-level ordering derived from
// the logos hunk pipeline's Fiedler vector, optionally lifted into 2D
// by a per-file timestamp.
//
// Consumes the existing hunk pipeline (no new primitives):
//
//   parseDiffHunks(diffText) → List<DiffHunk>
//   rankHunksByPhiAsync     → HunkDiffusionResult
//                              ├── graph (H_sym + H_file + H_prox + H_vol)
//                              └── spectralBasis → Fiedler vector
//
// Each file's coordinate is the φ-weighted mean of its hunks' Fiedler
// coords. φ is the hunk's heat-kernel centrality from the pipeline,
// so load-bearing hunks dominate; trivial hunks still vote (weight 1)
// so they don't disappear. Files with no hunks in the result fall
// back to the global mean.
//
// When ageByFilePath is supplied, files are embedded into 2D as
// (Fiedler, age) and sorted along the principal axis of that cloud
// via closed-form 2×2 PCA. Zero age variance collapses the axis to
// pure Fiedler; otherwise the temporal dimension contributes in
// proportion to its covariance with Fiedler — no hand-tuned blend.

import 'dart:math' as math;

import 'logos_hunks.dart' show DiffHunk, HunkDiffusionResult;

/// Bundle the changes panel passes into the sort after the hunk
/// pipeline has run. `hunks` is the original input list fed to
/// `rankHunksByPhiAsync`; the graph was built over it in order, so
/// `hunks[i]`'s graph node index is `i`.
///
/// `ageByFilePath` is optional — wall-clock seconds per touched file,
/// typically the most recent commit timestamp from
/// `LogosGitStats.perFileCommitClock` (or `now` for untracked files).
/// When present, triggers the 2D (Fiedler × age) path; when absent,
/// pure Fiedler.
class CorrelatednessContext {
  const CorrelatednessContext({
    required this.hunks,
    required this.hunkResult,
    this.ageByFilePath = const {},
  });

  final List<DiffHunk> hunks;
  final HunkDiffusionResult hunkResult;
  final Map<String, double> ageByFilePath;
}

/// Sort [paths] by the Fiedler centroid of their hunks, optionally
/// lifted to 2D by per-file age and projected onto the principal
/// axis. Returns input order when no spectral basis is available
/// (graph too small, Lanczos refusal, empty hunk set).
List<String> seriateByHunkFiedler(
  List<String> paths,
  CorrelatednessContext context,
) {
  if (paths.length <= 1) return List<String>.of(paths);
  final basis = context.hunkResult.spectralBasis();
  if (basis == null) return List<String>.of(paths);
  final fiedler = basis.fiedlerVector;
  if (fiedler == null) return List<String>.of(paths);

  // φ lookup keyed by (filePath, hunkIndex). HunkRanking carries φ
  // but not the graph index, so we match through the original hunks
  // list whose position is the graph index.
  final phiByKey = <String, double>{};
  for (final ranking in context.hunkResult.rankings) {
    final key = '${ranking.hunk.filePath}\u0000${ranking.hunk.hunkIndex}';
    phiByKey[key] = ranking.phi;
  }

  // hunks[i] → node i → fiedler[i].
  final sumByFile = <String, double>{};
  final weightByFile = <String, double>{};
  final n = context.hunks.length;
  for (var i = 0; i < n; i++) {
    if (i >= fiedler.length) break;
    final DiffHunk h = context.hunks[i];
    final key = '${h.filePath}\u0000${h.hunkIndex}';
    final phi = phiByKey[key] ?? 0.0;
    final coord = fiedler[i];
    // Zero-φ hunks vote at weight 1 so trivial clusters don't drop
    // out; heavy-φ hunks dominate.
    final w = phi > 0 ? phi : 1.0;
    sumByFile.update(
      h.filePath,
      (acc) => acc + coord * w,
      ifAbsent: () => coord * w,
    );
    weightByFile.update(
      h.filePath,
      (acc) => acc + w,
      ifAbsent: () => w,
    );
  }

  if (sumByFile.isEmpty) return List<String>.of(paths);

  // Global mean is the fallback for paths with no hunks in the
  // result — they land in the middle.
  final centroid = <String, double>{};
  var globalSum = 0.0;
  var globalCount = 0;
  sumByFile.forEach((path, s) {
    final w = weightByFile[path] ?? 0.0;
    if (w <= 0) return;
    final c = s / w;
    centroid[path] = c;
    globalSum += c;
    globalCount++;
  });
  final globalMean = globalCount > 0 ? globalSum / globalCount : 0.0;

  final scores = _projectOntoPrincipalAxis(
    paths: paths,
    fiedlerCentroid: centroid,
    fiedlerFallback: globalMean,
    ageByFilePath: context.ageByFilePath,
  );

  final ordered = List<String>.of(paths);
  ordered.sort((a, b) {
    final sa = scores[a] ?? 0.0;
    final sb = scores[b] ?? 0.0;
    if (sa == sb) return a.compareTo(b);
    return sa.compareTo(sb);
  });

  // Lanczos Fiedler sign flips run-to-run; pin the heavier end at
  // the head to match the repo_summary spectral paths.
  final firstScore = scores[ordered.first] ?? 0.0;
  final lastScore = scores[ordered.last] ?? 0.0;
  if (firstScore.abs() < lastScore.abs()) {
    return ordered.reversed.toList();
  }
  return ordered;
}

/// Project (Fiedler, age) per file onto the principal axis of their
/// 2D cloud via closed-form 2×2 PCA. Empty or constant ages collapse
/// to pure Fiedler; otherwise the axis tilts toward whichever
/// direction carries more combined variance.
Map<String, double> _projectOntoPrincipalAxis({
  required List<String> paths,
  required Map<String, double> fiedlerCentroid,
  required double fiedlerFallback,
  required Map<String, double> ageByFilePath,
}) {
  final xs = <String, double>{};
  final ys = <String, double>{};
  var haveY = false;
  for (final path in paths) {
    xs[path] = fiedlerCentroid[path] ?? fiedlerFallback;
    final age = ageByFilePath[path];
    if (age != null && age.isFinite) {
      ys[path] = age;
      haveY = true;
    }
  }

  if (!haveY) return xs;

  // Z-score both axes. Fiedler coords are ~1/sqrt(n), Unix timestamps
  // ~1e9; without this, time always dominates on raw scale.
  final xVals = [for (final p in paths) xs[p]!];
  final yVals = [
    for (final p in paths) ys[p] ?? _mean(ys.values),
  ];
  final xMean = _mean(xVals);
  final yMean = _mean(yVals);
  final xStd = _stddev(xVals, xMean);
  final yStd = _stddev(yVals, yMean);

  if (yStd <= 0) return xs;
  if (xStd <= 0) {
    // All hunks at one Fiedler coord — sort by time alone, files
    // without an age land at the centre.
    return {
      for (final p in paths) p: ((ys[p] ?? yMean) - yMean) / yStd,
    };
  }

  final xz = <String, double>{
    for (final p in paths) p: ((xs[p]! - xMean) / xStd),
  };
  final yz = <String, double>{
    for (final p in paths) p: (((ys[p] ?? yMean) - yMean) / yStd),
  };

  // Covariance of the z-scored cloud = Pearson correlation ρ.
  var cov = 0.0;
  final n = paths.length.toDouble();
  if (n > 1) {
    for (final p in paths) {
      cov += xz[p]! * yz[p]!;
    }
    cov /= (n - 1);
  }

  // Principal eigenvector of [[1,ρ],[ρ,1]] is (1, sign(ρ))/√2.
  // Project onto it to collapse 2D → 1D.
  final sign = cov >= 0 ? 1.0 : -1.0;
  final inv = 1.0 / math.sqrt(2.0);
  final wx = inv;
  final wy = inv * sign;

  final scores = <String, double>{
    for (final p in paths) p: wx * xz[p]! + wy * yz[p]!,
  };
  return scores;
}

double _mean(Iterable<double> xs) {
  var s = 0.0;
  var n = 0;
  for (final x in xs) {
    s += x;
    n++;
  }
  return n == 0 ? 0.0 : s / n;
}

double _stddev(Iterable<double> xs, double mean) {
  var s = 0.0;
  var n = 0;
  for (final x in xs) {
    final d = x - mean;
    s += d * d;
    n++;
  }
  if (n < 2) return 0.0;
  return math.sqrt(s / (n - 1));
}
