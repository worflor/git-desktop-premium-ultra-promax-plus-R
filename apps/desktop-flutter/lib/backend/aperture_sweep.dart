// Aperture sweep — read a codebase's history from its current shape,
// at arbitrary focal lengths, via a dense sweep of observation windows.
//
// Conceptually this is the renormalization-group analog for codebases:
// the same system observed at different scales reveals different
// effective theories. Some observables are scale-invariant (universal
// species properties — the repo's identity). Some run predictably with
// scale (the developmental arc). The derivative with respect to scale
// localises transitions — compound events where multiple observables
// flip in the same aperture bin are the repo's structural "growth
// rings", mapped directly to ranges in commit history.
//
// The primitive doesn't name any particular window as "correct" — it
// hands the full sweep to callers so they can slide the aperture as
// a UX control or render the multi-scale picture directly.
//
// Cost: one spectral-basis build per window. O(W × Lanczos cost).
// Default W=12; on mid-sized repos this lands in ~30-90 seconds.
// Cache per (repo path, HEAD hash).
//
// See docs/architecture/spectral-cosmology.md for the theoretical
// grounding; see tests in test/backend/aperture_sweep_test.dart for
// the event-detection contract.

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'git_result.dart';
import 'logos_core.dart';
import 'logos_git.dart';
import 'logos_git_stats.dart';
import 'logos_spectrogeometry.dart';

/// One snapshot of the engine observed at a specific commit-window
/// depth. Every field is a pure read of the spectral + persistence
/// state the engine computes at that focal length. A [ApertureSweep]
/// is a sequence of these sorted by ascending window.
class ApertureSample {
  /// The commit-window used to observe the repo. Semantically: "how
  /// many commits back did we integrate over to build this snapshot."
  final int window;

  /// Node count at this window (number of paths that appear in the
  /// truncated history's coupling matrix).
  final int nodeCount;

  /// Total edge count (non-zero entries in the symmetric coupling
  /// CSR, divided by 2).
  final int edgeCount;

  /// Algebraic connectivity — λ₁ of the normalised Laplacian. Low
  /// values (→ 0) mean the graph is near a cleavage.
  final double fiedler;

  /// β₀ — number of connected components at the end of the coupling
  /// persistence filtration. Distinct subsystems visible at this
  /// window.
  final int componentCount;

  /// β₁ — number of independent cycles in the coupling graph.
  /// High cycle counts indicate dense mutual coupling.
  final int cycleCount;

  /// Spectral dimension from the heat-trace log-log slope. Effective
  /// dimension of the coupling graph — path ≈ 1, planar ≈ 2, dense
  /// ≥ 3. `NaN` when the basis was too short for the fit.
  final double spectralDim;

  /// Shannon entropy of the normalised Laplacian spectrum. High →
  /// spread across many modes; low → dominated by a few modes.
  final double spectralEntropy;

  /// Name of the nearest universality archetype ('crystalline',
  /// 'poisson', 'goe', 'tree', 'bulk', 'modular').
  final String nearestArchetype;

  /// Distance to [nearestArchetype] in `[0, 1]`. 0 = exact match.
  final double nearestDistance;

  /// How decisively one archetype wins over the next-nearest —
  /// `1 − nearest / runner_up`, clamped to `[0, 1]`.
  final double decisiveness;

  /// Path of the file with the highest spectral eigenvector-
  /// centrality at this window. Intuition: the "centre of gravity"
  /// of the repo as the math sees it at this focal length. As
  /// window widens this centre drifts toward historically-deep
  /// files that dominated the older coupling pattern.
  final String topHousekeepingPath;

  const ApertureSample({
    required this.window,
    required this.nodeCount,
    required this.edgeCount,
    required this.fiedler,
    required this.componentCount,
    required this.cycleCount,
    required this.spectralDim,
    required this.spectralEntropy,
    required this.nearestArchetype,
    required this.nearestDistance,
    required this.decisiveness,
    required this.topHousekeepingPath,
  });
}

/// Full multi-window observation of a repo. The list of samples is
/// sorted by ascending [ApertureSample.window].
class ApertureSweep {
  final List<ApertureSample> samples;

  /// Wall-clock of the sweep's completion. Callers can use this to
  /// decide when to invalidate against HEAD movement.
  final DateTime computedAt;

  /// HEAD hash at the time of the sweep. `''` when unavailable.
  final String headHash;

  const ApertureSweep({
    required this.samples,
    required this.computedAt,
    required this.headHash,
  });

  /// Neutral empty sweep. Used as an initial value before the first
  /// probe completes. Not `const` because [DateTime] isn't constant-
  /// constructible; the empty object is cheap enough to allocate.
  static final ApertureSweep empty = ApertureSweep(
    samples: const [],
    computedAt: DateTime.fromMillisecondsSinceEpoch(0),
    headHash: '',
  );

  bool get isEmpty => samples.isEmpty;
  bool get isNotEmpty => samples.isNotEmpty;
  int get length => samples.length;

  /// Continuous-domain sample lookup. Returns an [ApertureSample] for
  /// any [window] by linearly interpolating between the two bracketing
  /// real samples. Essential for a scrubber UX where the slider moves
  /// through aperture values that weren't literally sampled — the math
  /// behaves smoothly between seeds, so linear interpolation in
  /// log-window space preserves the geometric structure of the sweep.
  ///
  /// Scalars (fiedler, spectralDim, nearestDistance, decisiveness,
  /// spectralEntropy) interpolate linearly; integer counts interpolate
  /// linearly and round; discrete fields (nearestArchetype,
  /// topHousekeepingPath) snap to the closer real sample so the UI
  /// doesn't invent hybrid archetype names.
  ///
  /// Returns `null` when [samples] is empty. When [window] falls
  /// outside the seeded range, returns the nearest endpoint sample
  /// (no extrapolation — extrapolating spectral observables past the
  /// last real measurement lies to the user).
  ApertureSample? sampleAt(int window) {
    if (samples.isEmpty) return null;
    if (window <= samples.first.window) return samples.first;
    if (window >= samples.last.window) return samples.last;
    // Binary search for the bracketing pair (lo, hi) with
    // samples[lo].window <= window < samples[hi].window.
    var lo = 0;
    var hi = samples.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (samples[mid].window <= window) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = samples[lo];
    final b = samples[hi];
    if (a.window == b.window) return a;
    // Interpolate in log-window space — matches the geometric seeding
    // schedule aperture uses everywhere else, so a query halfway
    // between window=100 and window=400 lands at window=200, not 250.
    final la = math.log(a.window.toDouble());
    final lb = math.log(b.window.toDouble());
    final lw = math.log(window.toDouble());
    final tRaw = (lw - la) / (lb - la);
    final t = tRaw.clamp(0.0, 1.0).toDouble();
    double lerp(double x, double y) => x + (y - x) * t;
    int lerpI(int x, int y) => (x + (y - x) * t).round();
    return ApertureSample(
      window: window,
      nodeCount: lerpI(a.nodeCount, b.nodeCount),
      edgeCount: lerpI(a.edgeCount, b.edgeCount),
      fiedler: lerp(a.fiedler, b.fiedler),
      componentCount: lerpI(a.componentCount, b.componentCount),
      cycleCount: lerpI(a.cycleCount, b.cycleCount),
      spectralDim: a.spectralDim.isFinite && b.spectralDim.isFinite
          ? lerp(a.spectralDim, b.spectralDim)
          : (t < 0.5 ? a.spectralDim : b.spectralDim),
      spectralEntropy: lerp(a.spectralEntropy, b.spectralEntropy),
      // Discrete fields snap to the closer endpoint — never blend.
      nearestArchetype: t < 0.5 ? a.nearestArchetype : b.nearestArchetype,
      nearestDistance: lerp(a.nearestDistance, b.nearestDistance),
      decisiveness: lerp(a.decisiveness, b.decisiveness),
      topHousekeepingPath:
          t < 0.5 ? a.topHousekeepingPath : b.topHousekeepingPath,
    );
  }
}

/// Back-compat alias for explicit-windows callers. Adaptive sampling
/// replaces the hardcoded default; this constant is kept so existing
/// code that passed `windows: kDefaultApertureWindows` still compiles
/// and produces a reasonable non-adaptive sweep.
const List<int> kDefaultApertureWindows = [
  60, 80, 100, 120, 140, 160, 200, 300, 500, 800, 1000
];

/// Run the aperture sweep on [repoPath]. By default the sweep is
/// **adaptive**: seed a handful of geometrically-spaced samples, then
/// refine by inserting new windows wherever adjacent observables are
/// changing fastest. The refinement is Mandelbrot-style progressive —
/// dense only where change is genuinely present, sparse in the flat
/// regions where additional samples tell us nothing new.
///
/// Samples run concurrently inside [Isolate.run] up to [parallelism]
/// at a time, so the calling isolate's UI thread stays responsive
/// AND multiple CPU cores do the Lanczos work in parallel. Only
/// primitive-typed sample values cross the isolate boundary.
///
/// Parameters:
///   [windows]          — explicit window list. When supplied, adaptive
///                        refinement is skipped and exactly these windows
///                        are sampled (in parallel). Leave `null` for
///                        adaptive mode.
///   [minWindow]        — smallest window in adaptive seed.
///   [maxWindow]        — largest window in adaptive seed.
///   [seedCount]        — number of geometric seed windows (default 4).
///   [maxSamples]       — hard cap on total samples (default 8). Adaptive
///                        refinement stops at this count or when gap
///                        scores fall below [refinementThreshold].
///   [refinementThreshold] — minimum observable-change-density required
///                        to insert a refinement sample. Low values give
///                        denser sweeps, higher values stop earlier.
///   [parallelism]      — maximum concurrent isolates. Typical machines
///                        have 4-16 logical cores; saturating them all
///                        with Lanczos tends to spike the system. The
///                        default of 6 fits the common 8-core desktop
///                        without pegging every core and cuts a 6-8
///                        sample sweep down to one or two batch rounds.
///                        The UI stays responsive regardless because
///                        isolates run off the Flutter thread; parallelism
///                        just affects total throughput.
///   [onProgress]       — fires after each completed sample with
///                        (done, totalEstimate). Total is seedCount
///                        initially and may grow during refinement.
///   [onSample]         — fires once per completed sample with the
///                        freshly-landed [ApertureSample]. Lets the
///                        UI stream partial rings data into view as
///                        the sweep runs, instead of waiting for the
///                        whole ritual to finish. Samples arrive in
///                        completion order, not window order — the
///                        consumer should sort if it wants monotone
///                        aperture ordering.
///
/// Returns [GitResult.err] only when no samples succeeded. Partial
/// sweeps (some windows failed) still return [GitResult.ok].
Future<GitResult<ApertureSweep>> collectApertureSweep(
  String repoPath, {
  List<int>? windows,
  int minWindow = 60,
  int maxWindow = 1000,
  int seedCount = 6,
  int maxSamples = 8,
  double refinementThreshold = 0.20,
  int parallelism = 6,
  void Function(int done, int total)? onProgress,
  void Function(ApertureSample sample)? onSample,
}) async {
  if (windows != null && windows.isNotEmpty) {
    return _collectExplicit(
        repoPath, windows, parallelism, onProgress, onSample);
  }
  return _collectAdaptive(
    repoPath,
    minWindow: minWindow,
    maxWindow: maxWindow,
    seedCount: seedCount.clamp(2, maxSamples).toInt(),
    maxSamples: math.max(maxSamples, seedCount),
    refinementThreshold: refinementThreshold,
    parallelism: math.max(1, parallelism),
    onProgress: onProgress,
    onSample: onSample,
  );
}

/// Explicit-windows mode: run every requested window, in parallel
/// batches of [parallelism]. Progress is a clean `(done, total)` ramp
/// because the total is fixed up-front.
Future<GitResult<ApertureSweep>> _collectExplicit(
  String repoPath,
  List<int> windows,
  int parallelism,
  void Function(int done, int total)? onProgress,
  void Function(ApertureSample sample)? onSample,
) async {
  final samples = <ApertureSample>[];
  String headHash = '';
  var done = 0;
  for (var i = 0; i < windows.length; i += parallelism) {
    final batch = windows.sublist(
        i, math.min(i + parallelism, windows.length));
    final batchResults = await Future.wait([
      for (final w in batch)
        Isolate.run(() => _sampleInIsolate(repoPath, w)),
    ]);
    for (final r in batchResults) {
      done++;
      onProgress?.call(done, windows.length);
      if (r == null) continue;
      samples.add(r.sample);
      onSample?.call(r.sample);
      if (headHash.isEmpty) headHash = r.headHash;
    }
  }
  if (samples.isEmpty) {
    return const GitResult.err('no aperture samples produced');
  }
  samples.sort((a, b) => a.window.compareTo(b.window));
  return GitResult.ok(ApertureSweep(
    samples: samples,
    computedAt: DateTime.now(),
    headHash: headHash,
  ));
}

/// Adaptive mode: seed a few geometric windows in parallel, then
/// iteratively insert one sample at a time wherever the adjacent-pair
/// observable change density is highest. Converges when either the
/// sample budget is exhausted or the largest remaining gap score
/// falls below [refinementThreshold].
///
/// The total count passed to [onProgress] starts at [seedCount] and
/// ratchets up as refinements are scheduled, so UI progress bars
/// need to tolerate a growing denominator — design the bar as a
/// "done/cap" rather than "done/committed" to avoid apparent
/// regressions when a refinement extends the schedule.
Future<GitResult<ApertureSweep>> _collectAdaptive(
  String repoPath, {
  required int minWindow,
  required int maxWindow,
  required int seedCount,
  required int maxSamples,
  required double refinementThreshold,
  required int parallelism,
  void Function(int done, int total)? onProgress,
  void Function(ApertureSample sample)? onSample,
}) async {
  // Geometric seed: evenly spaced in log-window space so the seed
  // treats "short memory" and "deep memory" as equally important.
  final seeds = <int>{};
  for (var i = 0; i < seedCount; i++) {
    final t = seedCount == 1 ? 0.0 : i / (seedCount - 1);
    final w = (minWindow *
            math.pow(maxWindow / minWindow, t.clamp(0.0, 1.0)))
        .round();
    seeds.add(w);
  }
  final seedList = seeds.toList()..sort();

  // Phase 1: run seeds concurrently in batches.
  final samples = <ApertureSample>[];
  String headHash = '';
  var done = 0;
  for (var i = 0; i < seedList.length; i += parallelism) {
    final batch =
        seedList.sublist(i, math.min(i + parallelism, seedList.length));
    final batchResults = await Future.wait([
      for (final w in batch)
        Isolate.run(() => _sampleInIsolate(repoPath, w)),
    ]);
    for (final r in batchResults) {
      done++;
      onProgress?.call(done, maxSamples);
      if (r == null) continue;
      samples.add(r.sample);
      onSample?.call(r.sample);
      if (headHash.isEmpty) headHash = r.headHash;
    }
  }
  if (samples.isEmpty) {
    return const GitResult.err('no aperture samples produced');
  }
  samples.sort((a, b) => a.window.compareTo(b.window));

  // Phase 2: refine in parallel batches. Pure "one at a time" adaptive
  // is theoretically prettier — every decision sees the updated curve —
  // but throws away the parallelism that made seeds fast. The
  // compromise: pick the top-K non-overlapping gap midpoints per
  // iteration, run them concurrently, then re-evaluate. Two or three
  // batched rounds usually converge and reuse the CPU properly.
  final seenMidpoints = <int>{for (final s in samples) s.window};
  while (samples.length < maxSamples) {
    final remaining = maxSamples - samples.length;
    final batchSize = math.min(parallelism, remaining);
    final candidates = _topNonOverlappingMidpoints(
      samples,
      refinementThreshold,
      batchSize,
      seenMidpoints,
    );
    if (candidates.isEmpty) break;
    final batchResults = await Future.wait([
      for (final w in candidates)
        Isolate.run(() => _sampleInIsolate(repoPath, w)),
    ]);
    var addedAny = false;
    for (final r in batchResults) {
      done++;
      onProgress?.call(done, maxSamples);
      if (r == null) continue;
      samples.add(r.sample);
      onSample?.call(r.sample);
      seenMidpoints.add(r.sample.window);
      addedAny = true;
    }
    if (!addedAny) break;
    samples.sort((a, b) => a.window.compareTo(b.window));
  }

  return GitResult.ok(ApertureSweep(
    samples: samples,
    computedAt: DateTime.now(),
    headHash: headHash,
  ));
}

/// Return up to [count] refinement midpoints, ranked by gap score
/// descending, drawn from non-overlapping pairs so a single iteration
/// can't schedule two midpoints inside the same adjacent gap. Skips
/// any midpoint in [seen] so repeated rounds don't re-propose the
/// same window.
///
/// Non-overlap matters because if the top two gap scores come from
/// the SAME pair (they can't, since there's only one score per pair)
/// or from adjacent pairs both anchored on the same central sample,
/// inserting into them simultaneously would give one of the two
/// picks a stale neighbour — fine in principle, but the score was
/// computed assuming that neighbour.
///
/// The simpler discipline: rank pairs, walk highest-first, and skip
/// a pair if a previously selected pair in this batch already shares
/// a sample boundary with it.
List<int> _topNonOverlappingMidpoints(
  List<ApertureSample> samples,
  double threshold,
  int count,
  Set<int> seen,
) {
  if (samples.length < 2 || count <= 0) return const [];
  final ranked = <({int idx, double score, int mid})>[];
  for (var i = 1; i < samples.length; i++) {
    final a = samples[i - 1];
    final b = samples[i];
    if (b.window - a.window < 2) continue;
    final score = _gapScore(a, b);
    if (score < threshold) continue;
    final mid = math.sqrt(a.window.toDouble() * b.window.toDouble())
        .round()
        .clamp(a.window + 1, b.window - 1)
        .toInt();
    if (mid <= a.window || mid >= b.window) continue;
    if (seen.contains(mid)) continue;
    ranked.add((idx: i, score: score, mid: mid));
  }
  ranked.sort((a, b) => b.score.compareTo(a.score));
  final picked = <int>[];
  final usedSampleIndices = <int>{};
  for (final entry in ranked) {
    if (picked.length >= count) break;
    // A pair at index i uses sample indices (i-1, i). Skip if either
    // is already committed to another midpoint in this batch.
    if (usedSampleIndices.contains(entry.idx - 1) ||
        usedSampleIndices.contains(entry.idx)) {
      continue;
    }
    picked.add(entry.mid);
    usedSampleIndices.add(entry.idx - 1);
    usedSampleIndices.add(entry.idx);
  }
  return picked;
}

/// Change density between adjacent samples. Large when the observables
/// disagree a lot across a small log-aperture gap — those are the
/// places where structural transitions hide and where an additional
/// sample is most informative.
double _gapScore(ApertureSample a, ApertureSample b) {
  final logDelta = math.log(b.window / a.window);
  if (logDelta <= 0) return 0.0;

  double rel(double x, double y) {
    final base = math.max(x.abs(), 1e-9);
    return (y - x).abs() / base;
  }

  var change = 0.0;
  change += rel(a.nodeCount.toDouble(), b.nodeCount.toDouble());
  change += rel(a.fiedler, b.fiedler);
  change += rel(a.componentCount.toDouble(), b.componentCount.toDouble());
  change += rel(a.cycleCount.toDouble(), b.cycleCount.toDouble());
  if (a.spectralDim.isFinite && b.spectralDim.isFinite) {
    change += rel(a.spectralDim, b.spectralDim);
  }
  change += rel(a.spectralEntropy, b.spectralEntropy);
  change += rel(a.nearestDistance, b.nearestDistance);
  // Discrete bumps for structural transitions that scalar deltas miss:
  // an archetype flip or a centre-of-gravity path change signals a
  // real regime boundary worth refining around.
  if (a.nearestArchetype != b.nearestArchetype) change += 1.0;
  if (a.topHousekeepingPath != b.topHousekeepingPath) change += 0.5;

  return change / logDelta;
}

/// Wire-friendly bundle that crosses the isolate boundary. Contains
/// only primitives (via [ApertureSample]) plus the [headHash] string,
/// all trivially Sendable.
class _IsolateSampleResult {
  final ApertureSample sample;
  final String headHash;
  const _IsolateSampleResult({required this.sample, required this.headHash});
}

/// Top-level helper that runs inside the spawned isolate. Performs
/// the full per-window work — git probe, engine build, spectral
/// basis, spectrogeometry — and emits only the derived
/// [ApertureSample] back. Returns `null` when the spectral basis
/// or geometry couldn't be computed (tiny truncated history, etc.).
Future<_IsolateSampleResult?> _sampleInIsolate(
    String repoPath, int window) async {
  final statsResult = await collectLogosGitStats(repoPath,
      commitWindow: window, halfLifeCommits: window / 4.0);
  if (!statsResult.ok) return null;
  final stats = statsResult.data!;
  final engine = LogosGit.buildFromStats(stats);
  final basis = engine.spectralBasis();
  if (basis == null) return null;
  final sg = engine.spectrogeometry();
  if (sg == null) return null;
  return _IsolateSampleResult(
    sample: _sampleFrom(
      window: window,
      engine: engine,
      basis: basis,
      geom: sg,
    ),
    headHash: stats.coupling.headHash,
  );
}

/// A single transition detected between two adjacent aperture
/// samples. Each event carries:
///   * the aperture bin it sits in (from → to)
///   * the observables whose normalised magnitude jumped sharply
///   * a combined magnitude score (sum of per-observable magnitudes)
///
/// A COMPOUND event is one where multiple observables flipped in the
/// same bin — that concurrence distinguishes structural shifts from
/// single-observable churn.
class ApertureEvent {
  /// Aperture at the lower boundary of the bin.
  final int fromWindow;

  /// Aperture at the upper boundary of the bin.
  final int toWindow;

  /// Names of observables that had high |Δ/Δlog(window)| in this bin.
  /// Ordering is by individual magnitude descending.
  final List<String> flippedObservables;

  /// Combined magnitude — sum of per-observable normalised deltas
  /// across [flippedObservables]. Used to rank events globally.
  final double magnitude;

  const ApertureEvent({
    required this.fromWindow,
    required this.toWindow,
    required this.flippedObservables,
    required this.magnitude,
  });

  /// Geometric mean aperture of the bin. Convenient for timeline
  /// plotting where a single x-coordinate per event is wanted.
  double get apertureMid =>
      math.sqrt(fromWindow.toDouble() * toWindow.toDouble());
}

/// Signals that participate in compound-event detection. Each name
/// must match a field readable from [ApertureSample].
const List<String> kEventObservables = [
  'n',
  'fiedler',
  'beta0',
  'beta1',
  'spectralDim',
  'spectralEntropy',
  'nearestDistance',
];

/// Read an observable by its canonical name. Returns `null` when the
/// name isn't recognised so callers can ignore unknown axes gracefully.
double? _readObservable(ApertureSample s, String name) {
  switch (name) {
    case 'n':
      return s.nodeCount.toDouble();
    case 'fiedler':
      return s.fiedler;
    case 'beta0':
      return s.componentCount.toDouble();
    case 'beta1':
      return s.cycleCount.toDouble();
    case 'spectralDim':
      return s.spectralDim;
    case 'spectralEntropy':
      return s.spectralEntropy;
    case 'nearestDistance':
      return s.nearestDistance;
    case 'decisiveness':
      return s.decisiveness;
  }
  return null;
}

/// Detect compound events — aperture bins where `[minFlipped]+`
/// observables each exhibit a derivative spike relative to their own
/// per-observable distribution across the sweep.
///
/// Algorithm:
///   1. For each observable, compute |Δ/Δlog(window)| between every
///      pair of adjacent samples.
///   2. Mark the top-[topKPerObservable] bins as that observable's
///      "flip points".
///   3. Group flip points by bin. Bins with at least [minFlipped]
///      distinct observables become events.
///
/// Returns the event list sorted by ascending [ApertureEvent.toWindow].
/// `[minFlipped] = 2` by default — the one-observable-flipping case
/// is kept out because single-axis drift is often just the lens
/// running naturally with scale rather than a structural event.
List<ApertureEvent> detectCompoundEvents(
  ApertureSweep sweep, {
  int minFlipped = 2,
  int topKPerObservable = 3,
}) {
  if (sweep.samples.length < 2) return const [];

  // bin key = (fromWindow, toWindow) -> list of (observable, magnitude).
  // Using a Dart record as the map key gives us value equality +
  // hashCode for free and avoids any string-encoding round-trip, so
  // there's no delimiter to pick or parse back out. (The prior
  // implementation used a unicode arrow separator which is fragile
  // against editor/tooling re-encoding.)
  final perBin = <(int, int), List<(String, double)>>{};

  for (final obs in kEventObservables) {
    final values = <(int, int, double)>[]; // (from, to, magnitude)
    for (var i = 1; i < sweep.samples.length; i++) {
      final prev = sweep.samples[i - 1];
      final cur = sweep.samples[i];
      final v0 = _readObservable(prev, obs);
      final v1 = _readObservable(cur, obs);
      if (v0 == null || v1 == null) continue;
      if (!v0.isFinite || !v1.isFinite) continue;
      final dw = math.log(cur.window / prev.window);
      if (dw <= 0) continue;
      // Fractional delta when a non-zero baseline is available;
      // otherwise raw delta. Avoids division-by-near-zero blowups
      // on observables that can legitimately reach 0.
      final baseline = v0.abs();
      final delta =
          baseline < 1e-9 ? (v1 - v0).abs() : (v1 - v0).abs() / baseline;
      final magnitude = delta / dw;
      if (magnitude > 0) {
        values.add((prev.window, cur.window, magnitude));
      }
    }
    // Keep the top-K bins per observable.
    values.sort((a, b) => b.$3.compareTo(a.$3));
    for (final v in values.take(topKPerObservable)) {
      perBin.putIfAbsent((v.$1, v.$2), () => []).add((obs, v.$3));
    }
  }

  final events = <ApertureEvent>[];
  perBin.forEach((key, list) {
    if (list.length < minFlipped) return;
    list.sort((a, b) => b.$2.compareTo(a.$2));
    final total = list.fold<double>(0.0, (a, b) => a + b.$2);
    events.add(ApertureEvent(
      fromWindow: key.$1,
      toWindow: key.$2,
      flippedObservables: [for (final v in list) v.$1],
      magnitude: total,
    ));
  });
  events.sort((a, b) => a.toWindow.compareTo(b.toWindow));
  return events;
}

/// Centre-of-gravity trajectory — the sequence of top-housekeeping
/// paths as the aperture widens, deduplicated against consecutive
/// repeats. Reads like a narrative of the repo's recent work order:
/// closest focus = current attention, widest focus = historical
/// centre. Each entry carries the aperture at which that path
/// first became the centre of gravity, letting callers map strata
/// to approximate commit ranges.
List<CenterOfGravityStratum> centerOfGravityTrajectory(ApertureSweep sweep) {
  final out = <CenterOfGravityStratum>[];
  String? last;
  for (final s in sweep.samples) {
    if (s.topHousekeepingPath.isEmpty) continue;
    if (s.topHousekeepingPath != last) {
      out.add(CenterOfGravityStratum(
        window: s.window,
        path: s.topHousekeepingPath,
        nearestArchetype: s.nearestArchetype,
      ));
      last = s.topHousekeepingPath;
    }
  }
  return out;
}

/// One stratum in a centre-of-gravity trajectory. Records the
/// aperture at which the stratum's [path] first became the top
/// housekeeping file, plus the archetype classification observed
/// at that same aperture (small UX aid — the archetype name gives
/// context without needing to cross-reference the full sweep).
class CenterOfGravityStratum {
  final int window;
  final String path;
  final String nearestArchetype;
  const CenterOfGravityStratum({
    required this.window,
    required this.path,
    required this.nearestArchetype,
  });
}

/// Classify each observable as `invariant`, `running`, or `artifact`
/// across the sweep. The renormalization-group picture: invariants
/// are the repo's species properties, running observables describe
/// its developmental arc, artifacts are lens noise worth ignoring.
///
/// Classification heuristics:
///   * `invariant` iff coefficient-of-variation across samples is
///     below [invariantCV] (default 0.10).
///   * `running` iff a clear monotonic trend exists (ordinal pair-
///     concordance τ ∈ [0.25, 0.75] means no trend; outside =
///     running).
///   * `artifact` otherwise — high variance without monotonic trend.
///
/// Returns a map observable-name → classification string. Caller can
/// cosmetic-format as needed.
Map<String, String> classifyObservables(
  ApertureSweep sweep, {
  double invariantCV = 0.10,
}) {
  final out = <String, String>{};
  if (sweep.samples.length < 3) return out;
  for (final obs in kEventObservables) {
    final values = <double>[];
    for (final s in sweep.samples) {
      final v = _readObservable(s, obs);
      if (v == null || !v.isFinite) continue;
      values.add(v);
    }
    if (values.length < 3) continue;
    final mean = values.reduce((a, b) => a + b) / values.length;
    var varSum = 0.0;
    for (final v in values) {
      varSum += (v - mean) * (v - mean);
    }
    final sd = math.sqrt(varSum / values.length);
    final cv = mean.abs() > 1e-9 ? sd / mean.abs() : double.infinity;
    var up = 0;
    var total = 0;
    for (var i = 0; i < values.length; i++) {
      for (var j = i + 1; j < values.length; j++) {
        if (values[i] == values[j]) continue;
        total++;
        if (values[i] < values[j]) up++;
      }
    }
    final tau = total == 0 ? 0.5 : up / total;
    if (cv < invariantCV) {
      out[obs] = 'invariant';
    } else if (tau > 0.75 || tau < 0.25) {
      out[obs] = 'running';
    } else {
      out[obs] = 'artifact';
    }
  }
  return out;
}

ApertureSample _sampleFrom({
  required int window,
  required LogosGit engine,
  required SpectralBasis basis,
  required SpectroGeometry geom,
}) {
  final evs = basis.eigenvalues;
  final fiedler = evs.length > 1 ? evs[1] : 0.0;

  // Shannon entropy of the Laplacian spectrum, treating normalised
  // eigenvalues as a discrete distribution.
  final total = evs.fold<double>(0.0, (a, b) => a + b);
  var entropy = 0.0;
  if (total > 0) {
    for (final e in evs) {
      final p = e / total;
      if (p > 1e-12) entropy -= p * math.log(p);
    }
  }

  // Eigenvector centrality — squared magnitude across the first
  // several non-trivial modes. Skip any leading near-zero modes
  // (those index disconnected components on fragmented graphs and
  // would poison the centrality with component-indicator vectors).
  final n = basis.n;
  final k = basis.k;
  final centrality = Float64List(n);
  var start = 0;
  for (var i = 0; i < evs.length; i++) {
    if (evs[i] > 0.01) {
      start = i;
      break;
    }
  }
  final end = math.min(k, start + 6);
  for (var m = start; m < end; m++) {
    for (var i = 0; i < n; i++) {
      final e = basis.eigenvectors[m * n + i];
      centrality[i] += e * e;
    }
  }
  var bestIdx = 0;
  var bestC = -1.0;
  for (var i = 0; i < n; i++) {
    if (centrality[i] > bestC) {
      bestC = centrality[i];
      bestIdx = i;
    }
  }
  final topPath = engine.nodePaths.isNotEmpty ? engine.nodePaths[bestIdx] : '';

  return ApertureSample(
    window: window,
    nodeCount: n,
    edgeCount: engine.graph.indices.length ~/ 2,
    fiedler: fiedler,
    componentCount: geom.persistence?.finalComponents ?? 0,
    cycleCount: geom.persistence?.finalCycles ?? 0,
    spectralDim: geom.spectralDim?.dS ?? double.nan,
    spectralEntropy: entropy,
    nearestArchetype: geom.universality.nearest.name,
    nearestDistance: geom.universality.nearest.distance,
    decisiveness: geom.universality.decisiveness,
    topHousekeepingPath: topPath,
  );
}
