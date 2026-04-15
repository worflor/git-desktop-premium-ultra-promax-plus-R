import 'dart:convert' show LineSplitter;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'engram_fit.dart';
import 'git.dart';
import 'git_result.dart';

/// Separator token planted into `git log` custom formats so downstream
/// parsers can identify commit boundaries without regex. Chosen to be
/// unambiguous vs filename characters (ASCII only, no whitespace, no
/// git-ref-legal character). Shared across every call site that parses
/// `--format=${logCommitSeparator}%H` output.
const String logCommitSeparator = '__C__';

/// Co-change coupling: files appearing in the same commit over and over are
/// *semantically* related. This is the truth git already holds — we just have
/// to read it out and cluster the current change set by it.
///
/// Built once per repo (keyed by HEAD hash) and reused across every render.
/// The [symbol] axis is layered on top per change-set — same shape as
/// [jaccard] but computed from identifier overlap in the current working
/// tree rather than from git history. See [computeSymbolCoupling].
class FileCouplingMatrix {
  /// Jaccard coefficient keyed by (path → other path → score in 0..1).
  /// Symmetric: jaccard[A][B] == jaccard[B][A].
  final Map<String, Map<String, double>> jaccard;

  /// Symbol-overlap scores for the current change set. Upper-triangle,
  /// same convention as [jaccard]. Empty until enriched via [withSymbol].
  final Map<String, Map<String, double>> symbol;

  final String headHash;
  final int commitsAnalyzed;

  const FileCouplingMatrix({
    required this.jaccard,
    required this.headHash,
    required this.commitsAnalyzed,
    this.symbol = const {},
  });

  /// Coupling score for a pair — maximum of historical co-change and
  /// structural symbol overlap. The two axes are independent evidence;
  /// neither suppresses the other. New files have zero history, so symbol
  /// carries them. Old files use whichever axis is stronger.
  double score(String a, String b) {
    if (a == b) return 1.0;
    final hist = jaccard[a]?[b] ?? jaccard[b]?[a] ?? 0.0;
    final sym = symbol[a]?[b] ?? symbol[b]?[a] ?? 0.0;
    return math.max(hist, sym);
  }

  /// Return a copy with symbol overlap data merged in. Called once per
  /// change-set update; the rest of the pipeline consumes the merged matrix
  /// transparently through [score].
  FileCouplingMatrix withSymbol(Map<String, Map<String, double>> sym) =>
      FileCouplingMatrix(
        jaccard: jaccard,
        symbol: sym,
        headHash: headHash,
        commitsAnalyzed: commitsAnalyzed,
      );

  /// Coherence of a *set* of files: the mean of all pairwise scores.
  /// Returns 1.0 for ≤1 files (trivially coherent — nothing to compare).
  ///
  /// Confidence gating: a brand-new repo with a handful of commits will
  /// produce *false-confident* Jaccard scores — every pair appears
  /// together because every commit touched every file once. We gate
  /// coherence on the matrix's underlying commit count, returning the
  /// max-uncertainty prior (0.5) when there isn't enough data to trust
  /// the signal. Matches the BornMixer's confidence-gate philosophy
  /// applied at the coherence level.
  ///
  /// Threshold of 50 commits chosen so that typical refactor churn
  /// inside a feature branch (a few dozen commits) doesn't produce
  /// spurious "tight coupling" reports before the history is
  /// statistically meaningful.
  double coherenceFor(Iterable<String> paths) {
    final list = paths.toList();
    if (list.length < 2) return 1.0;
    if (commitsAnalyzed < 50) return 0.5;
    double sum = 0.0;
    int pairs = 0;
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        sum += score(list[i], list[j]);
        pairs++;
      }
    }
    return pairs == 0 ? 1.0 : sum / pairs;
  }

  static const empty = FileCouplingMatrix(
    jaccard: {},
    symbol: {},
    headHash: '',
    commitsAnalyzed: 0,
  );
}

/// Compute co-change matrix for a repo from the last [commitLimit] commits.
/// Single git-log pass — the format embeds HEAD hash in the first commit
/// separator, so we don't need a separate `rev-parse HEAD` round-trip.
///
/// Skips commits with > [largeCommitCutoff] files (merges/imports/vendor
/// bumps); they're noise for co-change signal and would dominate pair counts.
Future<GitResult<FileCouplingMatrix>> computeFileCoupling(
  String repo, {
  int commitLimit = 1000,
  int largeCommitCutoff = 60,
  // Exponential decay half-life measured in commits. A commit at rank
  // [halfLifeCommits] contributes half as much as the tip. Set to 0 or
  // a negative number to disable (pure count-based Jaccard, legacy
  // behaviour). Pass null to *derive* a per-repo half-life via
  // [deriveEngramHalfLife] — an AR(2) oscillator fit on the commit
  // similarity trajectory. Rationale: a 50-commit greenfield repo and
  // a 50k-commit monorepo deserve different memory depths. Null is the
  // production default; tests and regression-pinning pass a number.
  double? halfLifeCommits,
}) async {
  final logProbe = await runGitProbe(repo, [
    'log',
    '-n', '$commitLimit',
    '--no-merges',
    '--name-only',
    '--format=$logCommitSeparator%H',
  ]);
  if (logProbe.exitCode != 0) {
    return GitResult.err(logProbe.stderr.toString().trim());
  }

  // Parse in one pass — avoid building intermediate String list per line.
  // Commit separator lines look like "${logCommitSeparator}<sha>"; we
  // extract HEAD from the first one and commit hashes are otherwise ignored.
  final stdout = logProbe.stdout.toString();
  String headHash = '';
  final commits = <List<String>>[];
  List<String>? current;
  final sepLen = logCommitSeparator.length;

  for (final rawLine in const LineSplitter().convert(stdout)) {
    if (rawLine.startsWith(logCommitSeparator)) {
      if (current != null &&
          current.isNotEmpty &&
          current.length <= largeCommitCutoff) {
        commits.add(current);
      }
      current = <String>[];
      if (headHash.isEmpty) {
        headHash = rawLine.substring(sepLen).trim();
      }
      continue;
    }
    if (current == null) continue;
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;
    current.add(trimmed.replaceAll('\\', '/'));
  }
  if (current != null &&
      current.isNotEmpty &&
      current.length <= largeCommitCutoff) {
    commits.add(current);
  }

  // Resolve the effective half-life. Null caller → derive it from the
  // signal via [deriveEngramHalfLife]; a number → use it verbatim.
  final double effectiveHalfLife = halfLifeCommits == null
      ? _deriveAdaptiveHalfLife(commits)
      : halfLifeCommits;
  // Commits are in reverse-chrono order — index 0 is the most recent.
  // Per-commit weight w_i = 2^(-i / halfLife). At halfLife=200,
  // w_0 = 1.0, w_200 = 0.5, w_400 = 0.25, w_1000 ≈ 0.03. Weighted
  // Jaccard preserves [0, 1] range because the inclusion-exclusion
  // identity |A∩B| / |A∪B| = co / (Na + Nb - co) is linear in the
  // underlying counts: substituting weighted sums keeps it sound.
  double commitWeight(int rank) {
    if (effectiveHalfLife <= 0) return 1.0;
    return math.pow(0.5, rank / effectiveHalfLife).toDouble();
  }

  // One pass: per-file weighted commit "count" + per-pair weighted co-
  // count. Only upper-triangle (a < b lexicographic) — halves inserts.
  final fileCommits = <String, double>{};
  final pairCount = <String, Map<String, double>>{};
  for (var rank = 0; rank < commits.length; rank++) {
    final files = commits[rank];
    final w = commitWeight(rank);
    for (final f in files) {
      fileCommits[f] = (fileCommits[f] ?? 0) + w;
    }
    final n = files.length;
    if (n < 2) continue;
    for (var i = 0; i < n; i++) {
      final a = files[i];
      for (var j = i + 1; j < n; j++) {
        final b = files[j];
        final lo = a.compareTo(b) < 0 ? a : b;
        final hi = a.compareTo(b) < 0 ? b : a;
        final row = pairCount.putIfAbsent(lo, () => {});
        row[hi] = (row[hi] ?? 0) + w;
      }
    }
  }

  // Jaccard: |A ∩ B| / |A ∪ B| = co / (Na + Nb - co), with the counts
  // now being time-weighted sums instead of integers. Still in [0, 1].
  final jaccard = <String, Map<String, double>>{};
  pairCount.forEach((a, row) {
    final na = fileCommits[a] ?? 0;
    final dest = jaccard.putIfAbsent(a, () => {});
    row.forEach((b, co) {
      final union = na + (fileCommits[b] ?? 0) - co;
      if (union > 0) dest[b] = co / union;
    });
  });

  // Ensure every file that appeared in any commit has a (possibly empty) row
  // so `jaccard.containsKey(path)` reliably answers "is this tracked?".
  for (final path in fileCommits.keys) {
    jaccard.putIfAbsent(path, () => {});
  }

  return GitResult.ok(FileCouplingMatrix(
    jaccard: jaccard,
    headHash: headHash,
    commitsAnalyzed: commits.length,
  ));
}

/// Half-life clamp band. Half-life is measured in commits.
///
/// The floor [_halfLifeMin] is the point where the exponential kernel
/// concentrates ~99% of its mass inside the most recent ~7·halfLife
/// commits (7·ln(2) ≈ 4.85, so 2⁻⁷ ≈ 1%). Below 50 the tail becomes
/// sparse enough that a single unusual recent commit dominates the
/// Jaccard signal. Empirically the minimum sustainable window.
///
/// The ceiling [_halfLifeMax] is the reciprocal concern on big
/// monorepos — beyond this, files that co-changed a year ago still
/// carry near-equal weight to yesterday's edit, and the matrix
/// effectively degenerates toward count-based Jaccard.
const double _halfLifeMin = 50.0;
const double _halfLifeMax = 500.0;

/// Fraction of the analysed window the fallback half-life occupies.
/// Picking halfLife = n/[_fallbackHalfLifeDivisor] means the most
/// recent 25% of commits holds ≈ 87.5% of the weight (1 - 2⁻³).
/// That matches the "new edits should dominate but old ones still
/// count" intuition without needing a fit.
const int _fallbackHalfLifeDivisor = 4;

/// Fallback half-life when the Engram fit can't run (too few commits,
/// degenerate signal). Proportional to the analysable window so tiny
/// repos get a tighter half-life than big ones.
double _fallbackHalfLife(int commitCount) =>
    (commitCount / _fallbackHalfLifeDivisor)
        .clamp(_halfLifeMin, _halfLifeMax)
        .toDouble();

/// Derive an adaptive half-life (in commits) from the shape of the
/// history itself. Implements the Whisper Engram principle: block size
/// is a property of the data, not a parameter anyone chose.
///
/// Algorithm:
///   1. Build the consecutive-commit Jaccard series via the shared
///      helper [consecutiveJaccardSeries]. This is the "trajectory" of
///      how fast the working set turns over — highly correlated = slow
///      drift (monorepo), oscillating near 0 = fast topic changes.
///   2. Centre the sequence so the AR(2) fit isn't biased by the
///      baseline similarity.
///   3. Fit z[n] = K·z[n-1] − G·z[n-2]. Spectral radius |λ| is the
///      per-step decay factor; half-life = −ln(2)/ln|λ|.
///   4. Clamp to the production band; fall back to a size-proportional
///      heuristic when the fit degenerates (short / non-orbital /
///      divergent).
///
/// Public so the derivation can be exercised in isolation by tests.
double deriveEngramHalfLife(List<List<String>> commitFileLists) {
  final n = commitFileLists.length;
  // Fit needs at least `engramMinSamples` similarity values, and the
  // similarity series has length n-1. +1 margin for the centring pass.
  if (n < engramMinSamples + 2) return _fallbackHalfLife(n);

  final fileSets = commitFileLists.map((c) => c.toSet()).toList();
  final sims = consecutiveJaccardSeries(fileSets);

  // Centre the signal. AR(2) on a biased series fits the mean instead
  // of the dynamics.
  var mean = 0.0;
  for (final s in sims) {
    mean += s;
  }
  mean /= sims.length;
  final centred = List<double>.generate(sims.length, (i) => sims[i] - mean);

  final fit = engramFit(centred);
  final hl = fit.halfLifeSamples;
  if (hl == null) return _fallbackHalfLife(n);
  return hl.clamp(_halfLifeMin, _halfLifeMax);
}

double _deriveAdaptiveHalfLife(List<List<String>> commits) =>
    deriveEngramHalfLife(commits);

/// How files are ordered in the change list once they've been clustered.
enum FileSortGuide {
  /// Files arranged so tightly-coupled pairs sit adjacent. Clusters kept
  /// together; the rail's hover visualization reads as a continuous band.
  relatedProximity,

  /// Plain A→Z by path. Cluster colors still render; position ignores them.
  alphabetical,

  /// Ranked by the weight of *this* change — hunk count + line churn in
  /// the current diff. The noisiest files rise to the top; tiny edits
  /// drop to the bottom. Where the action is, not where it might echo.
  impact,
}

/// Result of agglomerative clustering on the current change set.
///
/// Files with a coupling score ≥ [threshold] to any current peer end up in
/// the same cluster (single-link). Files with no qualifying peer get
/// [clusterIdIsolated] (-1) — rendered as a muted stripe so they read as
/// "standalone, no coupling signal" rather than "part of cluster N".
class FileClusters {
  final Map<String, int> byPath;
  final int clusterCount;

  /// Paths in render order — same cluster ids are contiguous; clusters
  /// themselves are ordered by size (largest first), with isolated at the end.
  final List<String> orderedPaths;

  const FileClusters({
    required this.byPath,
    required this.clusterCount,
    required this.orderedPaths,
  });

  static const clusterIdIsolated = -1;

  static FileClusters empty(List<String> fallbackOrder) => FileClusters(
        byPath: {for (final p in fallbackOrder) p: clusterIdIsolated},
        clusterCount: 0,
        orderedPaths: fallbackOrder,
      );
}

/// Single-link clustering over the current change set.
///
/// Scales cleanly from 1 file to 10,000+ by:
///   * enumerating only above-threshold pairs (no O(n²) score scan),
///   * using Union-Find for merges (near-linear in pair count),
///   * bucketing untracked files by path prefix before enumerating path
///     pairs, so path-affinity lookups stay O(n·avg_bucket_size) rather
///     than O(n²) when the change set is dominated by untracked files.
FileClusters clusterFiles(
  List<String> currentPaths,
  FileCouplingMatrix matrix, {
  double threshold = 0.25,
  FileSortGuide sortGuide = FileSortGuide.relatedProximity,
  // Per-path diff signal used by [FileSortGuide.impact]. The sort
  // computes effective impact from these AND the coupling matrix —
  // a file whose change is "explained" by a co-changing peer in the
  // same diff gets its impact attenuated proportionally, so
  // source+generated pairs and lockfile+manifest pairs don't double-
  // count. Missing entries score 0.
  Map<String, FileImpactSignal>? impactSignals,
  // Paths currently in a merge-conflict state. Regardless of sortGuide
  // these float to the very top of the list — unresolvable conflicts
  // block every commit, so the user must see them first.
  Set<String>? conflictedPaths,
  // Paths the user has checked for inclusion in the current commit.
  // Only consulted by [FileSortGuide.relatedProximity]: within a cluster
  // included files sort above excluded, and clusters with any included
  // files sort above fully-excluded clusters.
  Set<String>? includedPaths,
  // "Smart invert" toggle. Reverses the effective order per mode —
  // conflicts always stay pinned at the top regardless. Each mode
  // carries its own interpretation of "opposite":
  //   * related: tight clusters drop to the bottom, isolated/one-off
  //     files rise — "show me the odd ones out."
  //   * alphabetical: Z → A.
  //   * impact: smallest churn first — "quick wins on top."
  bool inverted = false,
}) {
  final n = currentPaths.length;
  if (n == 0) {
    return const FileClusters(byPath: {}, clusterCount: 0, orderedPaths: []);
  }

  // Index paths so we can refer to them by int everywhere.
  final pathIndex = <String, int>{
    for (var i = 0; i < n; i++) currentPaths[i]: i,
  };

  // Collect candidate pairs above threshold. Each pair stored at most once
  // via a lexicographic (lo, hi) key in a compact int-encoded set.
  final candidates = <_PairScore>[];
  final seen = <int>{};

  int encode(int a, int b) {
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    return lo * n + hi;
  }

  // -- 1. Historical pairs: sparse iteration over the jaccard matrix.
  //    For each current file, walk its neighbour row; only add pairs where
  //    the neighbour is also in the current change set.
  for (var i = 0; i < n; i++) {
    final a = currentPaths[i];
    final row = matrix.jaccard[a];
    if (row == null) continue;
    row.forEach((b, s) {
      if (s < threshold) return;
      final j = pathIndex[b];
      if (j == null || i == j) return;
      final key = encode(i, j);
      if (seen.add(key)) candidates.add(_PairScore(s, i, j));
    });
  }

  // -- 2. Path-affinity pairs for new/untracked files (and for pairs the
  //    historical matrix doesn't cover). Bucket by top-2 path segments to
  //    keep enumeration near-linear even for huge change sets.
  final buckets = <String, List<int>>{};
  for (var i = 0; i < n; i++) {
    final p = currentPaths[i];
    final segs = p.replaceAll('\\', '/').split('/');
    final key = segs.length >= 2
        ? '${segs[0]}/${segs[1]}'
        : (segs.isNotEmpty ? segs[0] : '');
    buckets.putIfAbsent(key, () => <int>[]).add(i);
  }
  buckets.forEach((_, idxs) {
    // O(m²) within bucket, but avg bucket is tiny for typical projects.
    for (var ii = 0; ii < idxs.length; ii++) {
      for (var jj = ii + 1; jj < idxs.length; jj++) {
        final i = idxs[ii];
        final j = idxs[jj];
        final a = currentPaths[i];
        final b = currentPaths[j];
        final aTracked = matrix.jaccard.containsKey(a);
        final bTracked = matrix.jaccard.containsKey(b);
        if (aTracked && bTracked) continue; // history-only for that case
        final s = pathAffinity(a, b);
        if (s < threshold) continue;
        final key = encode(i, j);
        if (seen.add(key)) candidates.add(_PairScore(s, i, j));
      }
    }
  });

  // -- 3. Union-Find: merge pairs in descending-score order.
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final uf = _UnionFind(n);
  for (final p in candidates) {
    uf.union(p.a, p.b);
  }

  // -- 4. Build clusters from UF roots. Singletons (their own root) become
  //    isolated — they had no pair above threshold by definition.
  final byRoot = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    byRoot.putIfAbsent(uf.find(i), () => <int>[]).add(i);
  }

  // Build unsorted clusters (int index lists). Actual seriation + member
  // ordering happens inside each branch below so the related branch can
  // be include-aware without affecting the other modes.
  final realClusters = <List<int>>[];
  final isolatedIdx = <int>[];
  byRoot.forEach((root, members) {
    if (members.length <= 1) {
      isolatedIdx.addAll(members);
    } else {
      realClusters.add(members);
    }
  });
  bool _clusterHasIncluded(List<int> members) {
    if (includedPaths == null || includedPaths.isEmpty) return true;
    return members.any((i) => includedPaths.contains(currentPaths[i]));
  }
  // Precompute every per-cluster sort key ONCE before the comparator
  // runs. The comparator then does only integer/reference compares —
  // no string allocation, no double parsing, no map lookups in the
  // hot loop. Sort calls the comparator O(n log n) times; doing
  // O(n) upfront work turns each step into constant-time integer
  // arithmetic.
  //
  // Fields, in comparator order:
  //   hasInc  — 0 if cluster has any included file, 1 otherwise
  //   coh100  — coherence × 100, rounded to int (kills float jitter)
  //   size    — member count (used DESC via negation)
  //   minPath — lex-min path, for the final stable tiebreak
  final clusterSortKeys = <List<int>, _ClusterSortKey>{
    for (final c in realClusters)
      c: _ClusterSortKey(
        hasInc: _clusterHasIncluded(c) ? 0 : 1,
        coh100: (_meanClusterCoherence(c, currentPaths, matrix) * 100)
            .round(),
        size: c.length,
        minPath: c
            .map((i) => currentPaths[i])
            .reduce((a, b) => a.compareTo(b) < 0 ? a : b),
      ),
  };
  realClusters.sort((x, y) {
    final kx = clusterSortKeys[x]!;
    final ky = clusterSortKeys[y]!;
    // Primary: included clusters first (design choice — "the work
    // the user is doing comes first" beats "how tightly coupled
    // this unrelated cluster is").
    if (kx.hasInc != ky.hasInc) return kx.hasInc - ky.hasInc;
    // Secondary: coherence DESC via integer compare on the rounded
    // ×100 form. No allocations, no floating-point flicker.
    if (kx.coh100 != ky.coh100) return ky.coh100 - kx.coh100;
    // Tertiary: bigger clusters first.
    if (kx.size != ky.size) return ky.size - kx.size;
    // Quaternary: lex-min path for stable alphabetical tiebreak,
    // independent of Union-Find traversal.
    return kx.minPath.compareTo(ky.minPath);
  });
  isolatedIdx.sort((x, y) => currentPaths[x].compareTo(currentPaths[y]));

  // byPath — cluster membership is independent of ordering; clusters
  // are still drawn via the rail stripe regardless of sort mode.
  final byPath = <String, int>{};
  for (var ci = 0; ci < realClusters.length; ci++) {
    for (final idx in realClusters[ci]) {
      byPath[currentPaths[idx]] = ci;
    }
  }
  for (final idx in isolatedIdx) {
    byPath[currentPaths[idx]] = FileClusters.clusterIdIsolated;
  }

  // orderedPaths — the actual row order. Strategy depends on sortGuide.
  final orderedPaths = <String>[];
  switch (sortGuide) {
    case FileSortGuide.relatedProximity:
      // Grouped: clusters in (included-first, coherence DESC, size DESC,
      // alpha ASC) order. Inside each cluster, split by inclusion and
      // nearest-neighbour-chain each subgroup — so the "files I'm
      // actually committing" sit above the surrounding context, each
      // sub-chain still locally tight.
      //
      // The junction between the two sub-chains (last included, first
      // excluded) is ALSO coupling-optimized: when the excluded chain
      // would be more tightly bound to the included tail by its end
      // than by its head, we reverse it so the strongest pair sits at
      // the seam. This keeps "here's the stuff I'm committing, and
      // here's the most-related context" reading as one continuous
      // gradient of coupling rather than a size-sorted list glued to
      // another size-sorted list.
      for (final cluster in realClusters) {
        final included = <int>[];
        final excluded = <int>[];
        for (final idx in cluster) {
          if (includedPaths == null ||
              includedPaths.contains(currentPaths[idx])) {
            included.add(idx);
          } else {
            excluded.add(idx);
          }
        }
        final incChain =
            _seriateCluster(included, currentPaths, matrix).toList();
        final excChain =
            _seriateCluster(excluded, currentPaths, matrix).toList();
        if (incChain.isNotEmpty && excChain.length >= 2) {
          final tail = incChain.last;
          final headScore = combinedCouplingScore(
              currentPaths[tail], currentPaths[excChain.first], matrix);
          final rearScore = combinedCouplingScore(
              currentPaths[tail], currentPaths[excChain.last], matrix);
          if (rearScore > headScore) {
            // In-place two-pointer reverse — no intermediate list.
            var lo = 0;
            var hi = excChain.length - 1;
            while (lo < hi) {
              final tmp = excChain[lo];
              excChain[lo] = excChain[hi];
              excChain[hi] = tmp;
              lo++;
              hi--;
            }
          }
        }
        for (final idx in incChain) {
          orderedPaths.add(currentPaths[idx]);
        }
        for (final idx in excChain) {
          orderedPaths.add(currentPaths[idx]);
        }
      }
      // Isolated-but-included files above isolated-but-excluded.
      final isolatedIncluded = <int>[];
      final isolatedExcluded = <int>[];
      for (final idx in isolatedIdx) {
        if (includedPaths == null ||
            includedPaths.contains(currentPaths[idx])) {
          isolatedIncluded.add(idx);
        } else {
          isolatedExcluded.add(idx);
        }
      }
      for (final idx in isolatedIncluded) {
        orderedPaths.add(currentPaths[idx]);
      }
      for (final idx in isolatedExcluded) {
        orderedPaths.add(currentPaths[idx]);
      }
    case FileSortGuide.alphabetical:
      // Natural, case-insensitive sort by BASENAME (the visible
      // filename column), falling back to the full path as tiebreak
      // for same-named files in different directories.
      //
      // Sorting by full path made `apps/foo/zzz.dart` land before
      // `lib/aaa.dart` because the comparison starts on the directory
      // segments — which reads as "broken alphabetical" in a list
      // that shows filenames prominently and directories as subtitle.
      orderedPaths.addAll(
        List<String>.from(currentPaths)
          ..sort((a, b) {
            final c = _naturalCompare(_basenameOf(a), _basenameOf(b));
            if (c != 0) return c;
            return _naturalCompare(a, b);
          }),
      );
    case FileSortGuide.impact:
      // Effective impact = raw line-churn × (1 − entanglement), where
      // entanglement is the maximum Jaccard between this file and any
      // other file in the CURRENT diff. Derived entirely from
      // physical signals — no hardcoded filename lists, no magic
      // suffix patterns, no language- or platform-specific rules.
      //
      // Intuition: if a file's change is fully "explained" by its
      // co-change with another file in the same diff (Jaccard → 1),
      // the pair contributes one unit of information, not two.
      // Source+generated companions and lockfile+manifest pairs
      // naturally attenuate each other without us having to know
      // what they are. A file with no peer in the diff keeps its
      // full impact — the attenuation only fires when there's
      // actually a co-change partner participating.
      //
      // Binaries contribute 0 (we don't have file-size data to
      // score them honestly; a magic baseline would lie). They
      // sink to the bottom on ties, ordered alphabetically.
      //
      // Tiebreaks in order: included-above-excluded (parity with
      // relatedProximity's "work first, context after"), then
      // natural compare by BASENAME (the visible filename column),
      // then full path as final stabilizer.
      // Precompute effectiveImpact for every path ONCE. Without this
      // the sort comparator re-derives entanglement (an O(|Jaccard
      // row|) lookup) on every comparison, turning an O(n log n)
      // sort into O(n² log n). Upfront cost: O(n²) over n paths —
      // same as the inherent cost of building the full entanglement
      // map, but paid once. Also eliminates the repeated basename
      // substring allocation that a naïve sort comparator would
      // otherwise do per comparison.
      final signals = impactSignals ?? const <String, FileImpactSignal>{};
      final pathSet = currentPaths.toSet();
      final effective = <String, double>{};
      final basenames = <String, String>{};
      for (final p in currentPaths) {
        final s = signals[p];
        final raw = (s == null || s.binary) ? 0.0 : (s.adds + s.dels).toDouble();
        var maxJ = 0.0;
        final row = matrix.jaccard[p];
        if (row != null && raw > 0) {
          row.forEach((peer, j) {
            if (peer == p) return;
            if (!pathSet.contains(peer)) return;
            if (j > maxJ) maxJ = j;
          });
        }
        effective[p] = raw * (1 - maxJ);
        basenames[p] = _basenameOf(p);
      }
      final ranked = List<String>.from(currentPaths);
      ranked.sort((a, b) {
        final sa = effective[a] ?? 0.0;
        final sb = effective[b] ?? 0.0;
        final c = sb.compareTo(sa);
        if (c != 0) return c;
        final aIn = includedPaths == null || includedPaths.contains(a);
        final bIn = includedPaths == null || includedPaths.contains(b);
        if (aIn != bIn) return aIn ? -1 : 1;
        final bc = _naturalCompare(basenames[a]!, basenames[b]!);
        if (bc != 0) return bc;
        return _naturalCompare(a, b);
      });
      orderedPaths.addAll(ranked);
  }

  // Smart invert: reverse the mode's ordered list. Applied BEFORE the
  // conflict float so conflicts still end up at position 0 regardless.
  // Each mode's notion of "opposite" is just "flip the list" — but
  // because each mode has its own ordering logic (cluster grouping,
  // alphabetical, weight), the reversal produces the semantically
  // appropriate inverse automatically:
  //   * related reversed → isolated-excluded first, tight-cluster-
  //     included last → "odd ones out on top."
  //   * alphabetical reversed → Z → A.
  //   * impact reversed → smallest churn first.
  if (inverted) {
    orderedPaths.setAll(0, orderedPaths.reversed.toList());
  }

  // Universal float-to-top: merge conflicts block every commit. Whatever
  // the sort mode, conflicted files belong at eye level. Preserves their
  // relative order as produced by the main sort below.
  if (conflictedPaths != null && conflictedPaths.isNotEmpty) {
    final conflicted = <String>[];
    final rest = <String>[];
    for (final p in orderedPaths) {
      if (conflictedPaths.contains(p)) {
        conflicted.add(p);
      } else {
        rest.add(p);
      }
    }
    orderedPaths
      ..clear()
      ..addAll(conflicted)
      ..addAll(rest);
  }

  return FileClusters(
    byPath: byPath,
    clusterCount: realClusters.length,
    orderedPaths: orderedPaths,
  );
}

/// Natural, case-insensitive path comparator.
///
/// Walks both strings in lockstep, comparing digit runs *numerically*
/// and non-digit runs *case-insensitively*. So `migration-10.sql` sorts
/// after `migration-2.sql`, and `README.md` doesn't leapfrog `src/` just
/// because uppercase codepoints are lower in ASCII.
///
/// Falls back to the raw `compareTo` as a final tiebreaker so the sort
/// is deterministic even for strings that differ only in case.
int _naturalCompare(String a, String b) {
  final aLen = a.length;
  final bLen = b.length;
  var i = 0;
  var j = 0;
  while (i < aLen && j < bLen) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    final aDigit = _isDigit(ca);
    final bDigit = _isDigit(cb);
    if (aDigit && bDigit) {
      // Consume both digit runs, compare numerically by length then value.
      var aEnd = i;
      while (aEnd < aLen && _isDigit(a.codeUnitAt(aEnd))) {
        aEnd++;
      }
      var bEnd = j;
      while (bEnd < bLen && _isDigit(b.codeUnitAt(bEnd))) {
        bEnd++;
      }
      // Strip leading zeros for magnitude compare; shorter = smaller.
      final aDigits = _stripLeadingZeros(a.substring(i, aEnd));
      final bDigits = _stripLeadingZeros(b.substring(j, bEnd));
      if (aDigits.length != bDigits.length) {
        return aDigits.length - bDigits.length;
      }
      final cmp = aDigits.compareTo(bDigits);
      if (cmp != 0) return cmp;
      i = aEnd;
      j = bEnd;
    } else if (aDigit != bDigit) {
      // One side is numeric, the other textual — numeric sorts earlier
      // so "v2" < "v_alpha". Subjective but consistent with most UIs.
      return aDigit ? -1 : 1;
    } else {
      // Both non-digit — compare case-insensitively, then case-sensitively
      // on equality so 'a' and 'A' stay stable relative to each other.
      final la = _toLower(ca);
      final lb = _toLower(cb);
      if (la != lb) return la - lb;
      if (ca != cb) return ca - cb;
      i++;
      j++;
    }
  }
  if (i < aLen) return 1;
  if (j < bLen) return -1;
  return 0;
}

/// Last path segment, handling both forward and back slashes. Walks
/// from the end and bails at the first separator — zero allocation
/// when the path has no separator, single `substring` otherwise.
/// Called in tight sort comparators, so the "no `replaceAll` scan on
/// every invocation" shape matters.
String _basenameOf(String path) {
  for (var i = path.length - 1; i >= 0; i--) {
    final c = path.codeUnitAt(i);
    if (c == 0x2F /* / */ || c == 0x5C /* \ */) {
      return path.substring(i + 1);
    }
  }
  return path;
}

/// Per-path raw diff signal consumed by [FileSortGuide.impact].
/// The sort uses this + the coupling matrix to derive effective
/// impact without any hardcoded filename rules — the attenuation
/// emerges from co-change physics, not a filetype whitelist.
///
/// Kept minimal on purpose: `adds` and `dels` are literal numstat
/// counts, `binary` tells the scorer "we can't count lines here."
/// No language-specific fields; no platform conventions baked in.
class FileImpactSignal {
  final int adds;
  final int dels;
  final bool binary;
  const FileImpactSignal({
    required this.adds,
    required this.dels,
    this.binary = false,
  });
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

int _toLower(int codeUnit) {
  if (codeUnit >= 0x41 && codeUnit <= 0x5A) return codeUnit + 0x20;
  return codeUnit;
}

String _stripLeadingZeros(String digits) {
  var i = 0;
  while (i < digits.length - 1 && digits.codeUnitAt(i) == 0x30) {
    i++;
  }
  return i == 0 ? digits : digits.substring(i);
}

/// Seriate a cluster's members so that adjacent files in the returned
/// order have the strongest pairwise coupling possible.
///
/// Greedy nearest-neighbour chain:
///   1. Seed with the highest-scoring pair in the cluster.
///   2. Extend from either end by the unplaced member with the strongest
///      coupling to that endpoint.
///
/// O(n²) per cluster — trivial for real change sets. Ties break on lex
/// order of the path so the output stays deterministic across runs and
/// files that truly have no coupling signal degrade gracefully to
/// alphabetical.
List<int> _seriateCluster(
  List<int> members,
  List<String> paths,
  FileCouplingMatrix matrix,
) {
  final n = members.length;
  if (n <= 2) return members;

  // One pair-score computation per pair — cache into a flat O(n²)
  // matrix. The hub-degree loop, seed-pair loop, and chain-extension
  // loop all read from this. Without caching, each phase redundantly
  // calls `combinedCouplingScore` on the same pairs. With n=20
  // typical, that's 400 cached scores vs. ~1200 redundant calls.
  //
  // Indexed by dense position within `members`, not the original
  // `paths` index — the cluster is local, the matrix is local, and
  // the symmetry `pair[i][j] == pair[j][i]` lets us walk only the
  // upper triangle.
  final pair = List<Float64List>.generate(n, (_) => Float64List(n));
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final s = combinedCouplingScore(paths[members[i]], paths[members[j]], matrix);
      pair[i][j] = s;
      pair[j][i] = s;
    }
  }

  // Precompute each member's hub degree (total coupling to the rest
  // of the cluster) in one linear pass over the cached matrix.
  final hubDegree = Float64List(n);
  for (var i = 0; i < n; i++) {
    var s = 0.0;
    for (var j = 0; j < n; j++) {
      if (i != j) s += pair[i][j];
    }
    hubDegree[i] = s;
  }

  // Precompute each member's parent directory so the sibling-tiebreak
  // in the chain-extension loop is a cheap string equality test, not
  // a replaceAll + lastIndexOf + substring on every comparison.
  final parentDir = List<String?>.generate(n, (i) {
    final p = paths[members[i]];
    for (var k = p.length - 1; k >= 0; k--) {
      final c = p.codeUnitAt(k);
      if (c == 0x2F /* / */ || c == 0x5C /* \ */) return p.substring(0, k);
    }
    return null;
  });

  // Pick the best starting pair: `pair_score + 0.1 × min(hub)`.
  // Weighting the WEAKER endpoint prevents a single hub from dragging
  // an otherwise-weak pair to the top; both sides must pull their
  // weight. Alphabetical tiebreak for stability.
  var bestPairScore = -1.0;
  var seedA = 0;
  var seedB = 1;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final composite =
          pair[i][j] + 0.1 * math.min(hubDegree[i], hubDegree[j]);
      if (composite > bestPairScore ||
          (composite == bestPairScore &&
              _lexBefore(
                paths[members[i]],
                paths[members[j]],
                paths[members[seedA]],
                paths[members[seedB]],
              ))) {
        bestPairScore = composite;
        seedA = i;
        seedB = j;
      }
    }
  }

  // Orient the seed so the higher-degree hub lands at index 0 (the
  // "backbone" file sits at the top of the cluster). Tiebreak
  // alphabetical.
  {
    final dA = hubDegree[seedA];
    final dB = hubDegree[seedB];
    if (dB > dA ||
        (dB == dA &&
            paths[members[seedB]].compareTo(paths[members[seedA]]) < 0)) {
      final t = seedA;
      seedA = seedB;
      seedB = t;
    }
  }

  final chain = <int>[seedA, seedB];
  // Track remaining by a visited bitset so removal is O(1) and we
  // never reshuffle a growing/shrinking list.
  final visited = List<bool>.filled(n, false);
  visited[seedA] = true;
  visited[seedB] = true;

  for (var step = 2; step < n; step++) {
    final frontIdx = chain.first;
    final backIdx = chain.last;
    var bestPos = -1;
    var bestPrepend = false;
    var bestScore = -1.0;
    var bestSiblingBoost = -1;
    String? bestTiebreak;
    for (var k = 0; k < n; k++) {
      if (visited[k]) continue;
      final frontScore = pair[k][frontIdx];
      final backScore = pair[k][backIdx];
      final prepend = frontScore > backScore;
      final localScore = prepend ? frontScore : backScore;
      final anchorDir = prepend ? parentDir[frontIdx] : parentDir[backIdx];
      final sibling =
          (parentDir[k] != null && parentDir[k] == anchorDir) ? 1 : 0;
      final kPath = paths[members[k]];
      final betterScore = localScore > bestScore;
      final equalScore = localScore == bestScore;
      final betterSibling = equalScore && sibling > bestSiblingBoost;
      final lexBreak = equalScore &&
          sibling == bestSiblingBoost &&
          (bestTiebreak == null || kPath.compareTo(bestTiebreak) < 0);
      if (betterScore || betterSibling || lexBreak) {
        bestScore = localScore;
        bestPos = k;
        bestPrepend = prepend;
        bestSiblingBoost = sibling;
        bestTiebreak = kPath;
      }
    }
    visited[bestPos] = true;
    if (bestPrepend) {
      chain.insert(0, bestPos);
    } else {
      chain.add(bestPos);
    }
  }

  // Map dense indices back to the caller's path indices.
  return [for (final i in chain) members[i]];
}

/// Mean pairwise coupling among a cluster's members — used by
/// `clusterFiles` to order clusters by tightness instead of raw size.
/// Returns 0 for 0- or 1-member clusters (no pairs to average).
double _meanClusterCoherence(
  List<int> members,
  List<String> paths,
  FileCouplingMatrix matrix,
) {
  if (members.length < 2) return 0;
  var sum = 0.0;
  var pairs = 0;
  for (var i = 0; i < members.length; i++) {
    for (var j = i + 1; j < members.length; j++) {
      sum += combinedCouplingScore(paths[members[i]], paths[members[j]], matrix);
      pairs++;
    }
  }
  return pairs == 0 ? 0 : sum / pairs;
}

/// Compare two pairs of paths for a stable tiebreak when seed-pair scores
/// are equal: prefer the pair whose min-path is lex-smaller.
bool _lexBefore(String a, String b, String seedA, String seedB) {
  final candidate = a.compareTo(b) < 0 ? a : b;
  final seed = seedA.compareTo(seedB) < 0 ? seedA : seedB;
  return candidate.compareTo(seed) < 0;
}

class _PairScore {
  final double score;
  final int a;
  final int b;
  const _PairScore(this.score, this.a, this.b);
}

/// Precomputed sort key for a cluster — populated once outside the
/// comparator so the actual sort step is pure integer arithmetic.
class _ClusterSortKey {
  final int hasInc;
  final int coh100;
  final int size;
  final String minPath;
  const _ClusterSortKey({
    required this.hasInc,
    required this.coh100,
    required this.size,
    required this.minPath,
  });
}

class _UnionFind {
  final List<int> parent;
  final List<int> rank;
  _UnionFind(int n)
      : parent = List<int>.generate(n, (i) => i, growable: false),
        rank = List<int>.filled(n, 0);

  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]]; // path compression (halving)
      x = parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra == rb) return;
    if (rank[ra] < rank[rb]) {
      parent[ra] = rb;
    } else if (rank[ra] > rank[rb]) {
      parent[rb] = ra;
    } else {
      parent[rb] = ra;
      rank[ra]++;
    }
  }
}

/// Language-agnostic path-structure signal. Returns 0..1 based on how much
/// of the directory path and filename stem two paths share.
///
/// Used as a fallback coupling signal for files with no git history yet
/// (new/untracked files). No regex matching on language-specific patterns —
/// just string overlap, so it works for any filesystem layout.
double pathAffinity(String a, String b) {
  if (a == b) return 1.0;
  final aNorm = a.replaceAll('\\', '/');
  final bNorm = b.replaceAll('\\', '/');
  final aSegs = aNorm.split('/');
  final bSegs = bNorm.split('/');

  // Shared directory prefix (excludes the filename itself).
  var sharedDirs = 0;
  final maxPrefix = math.min(aSegs.length, bSegs.length) - 1;
  for (var i = 0; i < maxPrefix; i++) {
    if (aSegs[i] != bSegs[i]) break;
    sharedDirs++;
  }
  final maxDirs = math.max(aSegs.length, bSegs.length) - 1;
  final dirScore = maxDirs > 0 ? sharedDirs / maxDirs : 0.0;

  // Basename stem similarity — longest common prefix of the bare names,
  // stripped of the rightmost extension.
  final aStem = _stripExt(aSegs.last);
  final bStem = _stripExt(bSegs.last);
  var common = 0;
  final minLen = math.min(aStem.length, bStem.length);
  for (var i = 0; i < minLen; i++) {
    if (aStem[i] != bStem[i]) break;
    common++;
  }
  // Dice coefficient: 2·common / (|a| + |b|). Symmetric and penalises
  // neither party for having a longer name — unlike common/max, which
  // under-scores pairs like `file_coupling` vs `file_constellation`
  // because the shared prefix (`file_co`) is measured against the longer
  // stem's full length rather than the combined mass.
  final totalStem = aStem.length + bStem.length;
  final stemScore = totalStem > 0 ? (2.0 * common) / totalStem : 0.0;

  // Require BOTH some dir overlap AND some name overlap to couple by path.
  // This prevents unrelated files in a flat directory from being grouped
  // (same-dir alone is too weak a signal; same-name alone is too).
  return dirScore * stemScore;
}

String _stripExt(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot > 0 ? filename.substring(0, dot) : filename;
}

// ═════════════════════════════════════════════════════════════════════════
// SYMBOL-OVERLAP COUPLING — structural axis for new / untracked files
// ═════════════════════════════════════════════════════════════════════════
//
// Co-change history is a lagging signal: it can only score files that have
// appeared together in at least one prior commit. A brand-new file has zero
// Jaccard against everything, so the historical axis is blind to it.
//
// Symbol overlap is a leading signal: it scores files by shared identifier
// usage right now, before any commit exists. A file that uses FileClusters
// and FileCouplingMatrix is structurally coupled to file_coupling.dart
// regardless of whether that relationship has ever appeared in git log.
//
// ── Self-learning IDF, language-agnostic ────────────────────────────────
//
// Scoring is IDF-weighted Jaccard over identifier sets. The IDF weights
// come from a CORPUS-WIDE document-frequency index built once per repo
// ([SymbolFrequencyIndex] — scanned from every tracked file, cached by
// HEAD hash). This makes the filter self-learning and language-agnostic:
//   • `def` appears in every Python file → df is huge → idf ≈ 0 → ignored
//   • `func` appears in every Go file → same
//   • `FileCouplingMatrix` appears in 2 files repo-wide → idf is high
//   • the repo *teaches* the filter what's noise vs signal
//
// No hardcoded language keywords. No per-language stop-word lists. The
// math is the filter. The only fallback (when the corpus index hasn't
// been built yet) is change-set-local IDF plus a tiny universal
// C-family keyword set — enough to keep cold-start sane without biasing.
//
//   idf(id) = ln(1 + N / (1 + df(id)))   [corpus available]
//   idf(id) = 1 / df_local(id)           [change-set fallback]
//
//   overlap(a, b) = Σ idf(id) for id in a∩b
//                   ────────────────────────
//                   Σ idf(id) for id in a∪b

/// Max file size we'll read for symbol extraction. Avoids tokenising
/// multi-megabyte generated files or binary blobs with a source extension.
const int _symMaxBytes = 256 * 1024; // 256 KB

/// Hard cap on files scanned when building the corpus frequency index.
/// Beyond this, a uniform random sample is taken — at 2000 files the
/// df estimates are already well-converged for any reasonable codebase.
const int _symCorpusSampleCap = 2000;

/// Minimal, language-neutral cold-start filter. Only universal
/// C-family keywords that the IDF corpus would downweight anyway if it
/// were warm. Deliberately short — the corpus index is the real filter.
/// Single-/two-character tokens are already excluded by the identifier
/// regex (`{2,}` suffix), so nothing here is shorter than 3 chars.
const Set<String> _symColdStartFilter = {
  'for', 'while', 'return', 'class', 'struct', 'enum', 'union',
  'true', 'false', 'null', 'nil', 'None', 'undefined',
  'new', 'this', 'self', 'super', 'super_',
  'public', 'private', 'protected', 'static', 'const', 'final',
  'let', 'var', 'val', 'mut',
  'import', 'export', 'from', 'package', 'using', 'module',
  'void', 'int', 'bool', 'string', 'float',
  'def', 'fun', 'func', 'fn', 'sub', 'lambda',
  'try', 'catch', 'throw', 'throws', 'except', 'finally',
  'async', 'await', 'yield',
};

/// Extract meaningful identifier tokens from [content].
/// Language-agnostic: matches any C-family identifier (3+ chars,
/// alphanumeric + underscore). Works for Dart, Python, Go, Rust, JS,
/// TS, Java, C, C++, Kotlin, Swift, Ruby, etc.
Set<String> _extractSymbols(String content) {
  final out = <String>{};
  final pattern = RegExp(r'\b([A-Za-z_][A-Za-z0-9_]{2,})\b');
  for (final m in pattern.allMatches(content)) {
    final id = m.group(1)!;
    if (!_symColdStartFilter.contains(id)) out.add(id);
  }
  return out;
}

/// Read [path] (relative to [repoRoot]) and extract its symbol set.
/// Returns empty on I/O error, missing file, or oversize file.
Set<String> _symbolsForFile(String repoRoot, String path) {
  try {
    final file = File(p.join(repoRoot, p.joinAll(path.split('/'))));
    if (!file.existsSync()) return const {};
    if (file.lengthSync() > _symMaxBytes) return const {};
    return _extractSymbols(file.readAsStringSync());
  } catch (_) {
    return const {};
  }
}

/// Corpus-wide identifier document-frequency index.
///
/// Built once per repo (keyed by HEAD hash) by scanning every tracked
/// file's identifier set. Replaces hardcoded language-specific stop-word
/// lists: any identifier that appears in most of the repo's files ends up
/// with near-zero IDF weight automatically, whether that's `def` in a
/// Python project or `public` in a Java project. The repo teaches the
/// filter what's noise.
///
/// Computed asynchronously in the background (see
/// `computeSymbolFrequencyIndex`); change-set coupling falls back to
/// local IDF when the index isn't ready yet.
class SymbolFrequencyIndex {
  /// identifier → number of documents containing it (1 ≤ df ≤ totalDocuments).
  final Map<String, int> documentFrequency;

  /// Total distinct documents scanned (denominator for IDF).
  final int totalDocuments;

  /// HEAD hash at the time of indexing. Callers invalidate when HEAD moves.
  final String headHash;

  const SymbolFrequencyIndex({
    required this.documentFrequency,
    required this.totalDocuments,
    required this.headHash,
  });

  /// Inverse-document-frequency weight for [term].
  ///
  /// Uses the smoothed form `ln(1 + N / (1 + df))`. Bounded below by 0
  /// (terms appearing in every document) and above by `ln(1 + N)` (terms
  /// never seen in the corpus — could be new symbols in the change set).
  /// A term in 50% of the corpus gets roughly `ln(1 + 2) ≈ 1.1`; a term
  /// in 1% gets `ln(1 + 100) ≈ 4.6`. Rare terms dominate, common terms
  /// vanish — the self-learning stop-word filter.
  double idf(String term) {
    if (totalDocuments <= 0) return 1.0;
    final df = documentFrequency[term] ?? 0;
    return math.log(1 + totalDocuments / (1 + df));
  }

  bool get isEmpty => totalDocuments == 0;
  bool get isNotEmpty => totalDocuments > 0;

  static const empty = SymbolFrequencyIndex(
    documentFrequency: {},
    totalDocuments: 0,
    headHash: '',
  );
}

/// Build a [SymbolFrequencyIndex] for the repo at [repoRoot].
///
/// Uses `git ls-files` to enumerate tracked files. When the corpus
/// exceeds [maxFiles], a uniform random sample is taken — df estimates
/// converge fast, so 2000 files is plenty for any codebase.
///
/// [sampleSeed] gives deterministic sampling for tests; leave null in
/// production (wall-clock seeded).
Future<GitResult<SymbolFrequencyIndex>> computeSymbolFrequencyIndex(
  String repoRoot, {
  int maxFiles = _symCorpusSampleCap,
  int? sampleSeed,
}) async {
  final lsProbe = await runGitProbe(repoRoot, ['ls-files']);
  if (lsProbe.exitCode != 0) {
    return GitResult.err(lsProbe.stderr.toString().trim());
  }

  final headProbe = await runGitProbe(repoRoot, ['rev-parse', 'HEAD']);
  final headHash =
      headProbe.exitCode == 0 ? headProbe.stdout.toString().trim() : '';

  final allPaths = const LineSplitter()
      .convert(lsProbe.stdout.toString())
      .where((l) => l.isNotEmpty)
      .toList();

  // Uniform random sample when the repo is large. Deterministic when
  // [sampleSeed] is set. We pick files, not bytes — a tiny file counts
  // the same as a big one for df estimation, which is what we want.
  List<String> scan;
  if (allPaths.length > maxFiles) {
    final rng = math.Random(sampleSeed ?? DateTime.now().millisecondsSinceEpoch);
    final shuffled = [...allPaths]..shuffle(rng);
    scan = shuffled.take(maxFiles).toList();
  } else {
    scan = allPaths;
  }

  final df = <String, int>{};
  var totalDocs = 0;
  for (final path in scan) {
    final syms = _symbolsForFile(repoRoot, path);
    if (syms.isEmpty) continue;
    totalDocs++;
    for (final sym in syms) {
      df[sym] = (df[sym] ?? 0) + 1;
    }
  }

  return GitResult.ok(
    SymbolFrequencyIndex(
      documentFrequency: df,
      totalDocuments: totalDocs,
      headHash: headHash,
    ),
  );
}

/// Compute pairwise symbol-overlap coupling for [paths].
///
/// Returns an upper-triangle map (same convention as [FileCouplingMatrix.jaccard])
/// of IDF-weighted Jaccard scores. Only pairs with a non-zero score are
/// stored.
///
/// When [corpus] is provided and non-empty, uses corpus-wide IDF (the
/// self-learning, language-agnostic filter). Otherwise falls back to
/// change-set-local IDF — the local `1 / df_local` form is a good
/// proxy when n is small but can overweight rare language keywords in
/// tiny change sets; prefer passing a warm corpus when available.
Map<String, Map<String, double>> computeSymbolCoupling(
  List<String> paths,
  String repoRoot, {
  SymbolFrequencyIndex? corpus,
}) {
  if (paths.length < 2) return const {};

  // Read identifier sets for every file in the change set.
  final symSets = <String, Set<String>>{};
  for (final path in paths) {
    final syms = _symbolsForFile(repoRoot, path);
    if (syms.isNotEmpty) symSets[path] = syms;
  }
  if (symSets.length < 2) return const {};

  // Resolve an IDF function once — corpus if warm, local fallback if not.
  final bool useCorpus = corpus != null && corpus.isNotEmpty;
  double Function(String) idfOf;
  if (useCorpus) {
    idfOf = corpus.idf;
  } else {
    final localDf = <String, int>{};
    for (final syms in symSets.values) {
      for (final id in syms) {
        localDf[id] = (localDf[id] ?? 0) + 1;
      }
    }
    idfOf = (id) => 1.0 / (localDf[id] ?? 1);
  }

  // IDF-weighted Jaccard for each pair (upper triangle only).
  final result = <String, Map<String, double>>{};
  final fileList = symSets.keys.toList();
  for (var i = 0; i < fileList.length; i++) {
    for (var j = i + 1; j < fileList.length; j++) {
      final a = fileList[i];
      final b = fileList[j];
      final symsA = symSets[a]!;
      final symsB = symSets[b]!;

      var numerator = 0.0;
      var denominator = 0.0;

      // Walk the union; intersection contributes to both.
      for (final id in symsA) {
        final w = idfOf(id);
        denominator += w;
        if (symsB.contains(id)) numerator += w;
      }
      for (final id in symsB) {
        if (!symsA.contains(id)) denominator += idfOf(id);
      }

      if (numerator == 0 || denominator == 0) continue;
      final score = numerator / denominator;

      // Upper-triangle: lex order for consistency with jaccard storage.
      final lo = a.compareTo(b) < 0 ? a : b;
      final hi = a.compareTo(b) < 0 ? b : a;
      (result[lo] ??= {})[hi] = score;
    }
  }
  return result;
}

// ─────────────────────────────────────────────────────────────────────────

/// Coupling score used by clustering and seriation.
///
/// Reads the blended score from the matrix (historical Jaccard + symbol
/// overlap, whichever is stronger). Falls back to path-structure affinity
/// only when the matrix has no signal at all for the pair — typically two
/// files that are both new AND share no identifiers.
///
/// If BOTH files are present in the co-change history (jaccard map), a
/// score of 0.0 is meaningful: they've been tracked and they don't
/// co-change. pathAffinity must NOT fire in that case — it would
/// manufacture coupling that contradicts the historical record and corrupt
/// clustering for pairs that deliberately don't co-change.
double combinedCouplingScore(String a, String b, FileCouplingMatrix m) {
  final s = m.score(a, b);
  if (s > 0) return s;
  // Both files are tracked with no co-change history → trust the history.
  if (m.jaccard.containsKey(a) && m.jaccard.containsKey(b)) return 0.0;
  return pathAffinity(a, b);
}

/// How many cluster colors we cycle through before stepping the alpha down.
/// Exposed for the color helper to stay in sync.
const int kFileClusterPaletteSize = 4;

/// Estimate how much information was used for a coupling decision.
/// Useful when rendering the header signal (low data → less confident).
double couplingConfidence(FileCouplingMatrix matrix) {
  if (matrix.commitsAnalyzed <= 0) return 0;
  return math.min(1.0, matrix.commitsAnalyzed / 200.0);
}

/// A single "you might have forgotten this" signal: an unselected changed
/// file whose coupling to the current selection is strong enough that
/// committing without it is likely a bug or a split the user didn't mean
/// to make.
class CouplingNudge {
  /// The unselected file the user is being nudged about.
  final String path;

  /// Mean `combinedCouplingScore` against the selection. 0..1.
  final double score;

  /// The selected peer with the tightest coupling — used to render the
  /// "because this file goes with X" affordance.
  final String anchor;

  const CouplingNudge({
    required this.path,
    required this.score,
    required this.anchor,
  });
}

/// Rank unselected files by how tightly they couple to the current
/// selection. A nudge fires when the mean coupling to the selection
/// reaches [threshold] — the same default used by [clusterFiles], so a
/// nudge aligns with what the clustering engine would have grouped.
///
/// Returns at most [limit] nudges, sorted by descending score. Empty when:
///   * [selected] is empty (nothing to couple *to*),
///   * [matrix] has fewer commits than the confidence gate in
///     [FileCouplingMatrix.coherenceFor] (we'd be surfacing noise), or
///   * no unselected file clears the threshold.
///
/// Cost: O(|selected| · |unselected|) combined-coupling lookups. Selection
/// sizes are small in practice (≤ tens); the whole call is microseconds.
List<CouplingNudge> suggestMissingPeers({
  required Iterable<String> selected,
  required Iterable<String> allChanged,
  required FileCouplingMatrix matrix,
  double threshold = 0.25,
  int limit = 5,
}) {
  final selectedList = selected.toList(growable: false);
  if (selectedList.isEmpty) return const [];
  // Gate on the same commit-count confidence bar [coherenceFor] uses —
  // under 50 commits the Jaccard rows are too noisy to nudge from.
  if (matrix.commitsAnalyzed < 50) return const [];

  final selectedSet = selectedList.toSet();
  final nudges = <CouplingNudge>[];
  for (final p in allChanged) {
    if (selectedSet.contains(p)) continue;
    double sum = 0.0;
    double best = 0.0;
    String bestAnchor = selectedList.first;
    for (final s in selectedList) {
      final c = combinedCouplingScore(p, s, matrix);
      sum += c;
      if (c > best) {
        best = c;
        bestAnchor = s;
      }
    }
    final mean = sum / selectedList.length;
    if (mean < threshold) continue;
    nudges.add(CouplingNudge(path: p, score: mean, anchor: bestAnchor));
  }
  nudges.sort((a, b) => b.score.compareTo(a.score));
  if (nudges.length > limit) {
    return nudges.sublist(0, limit);
  }
  return nudges;
}
