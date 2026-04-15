// logos_git.dart — Logos-inspired git context engine
//
// A relevance diffusion engine for code review context. The diff is a
// source field ρ. The codebase is a Riemannian manifold whose metric is
// learned from the repo's own history. Relevance is the heat-kernel
// solution φ = exp(-t·L)·ρ — temperature at equilibrium after diffusing
// the diff-source through the manifold.
//
// Architecturally this is a direct sibling of `logos.wat`:
//   - Fixed memory regions via typed-array buffers at named offsets
//   - Lazy LUTs (log1p, logit, sigmoid) computed on first access
//   - Born-amplitude mixing with confidence-gated evidence weights
//   - KT/Jeffreys priors for cold-start
//   - Chebyshev polynomial expansion of the heat kernel
//
// The Dart implementation mirrors a hand-written `.wat` module at a 1:1
// level — Float64List/Int32List buffers stand in for WASM linear memory,
// method bodies are shaped the same as the kernels would be. Porting
// to `logos_git.wat` later is mechanical.
//
// AXIS DECOMPOSITION (Phase 1 — zero new dependencies)
//
//   F0 (global frequency)     — per-file touch rate in history
//                               analogue: Logos order-0 bit distribution
//
//   CC (co-change Jaccard)    — from existing FileCouplingMatrix
//                               analogue: Logos O2 bigram (pairwise memory)
//
//   SP (spatial / path)       — directory proximity
//                               analogue: Logos Ab (above-neighbor)
//
//   V  (volatility / GARCH)   — EWMA of per-file churn magnitude
//                               analogue: Logos V (local energy / second moment)
//
// All axes output (p, n) — a predictor probability and an evidence count.
// Mix via Born rule: p = (Σwᵢ√pᵢ)² / ((Σwᵢ√pᵢ)² + (Σwᵢ√(1-pᵢ))²)
// Weights: wᵢ = |pᵢ - 0.5| · min(log1p(nᵢ), cap_i)
//
// The mixed edge probability p_mix is converted to a distance via
// d(i,j) = -ln(p_mix). Edge weights for the graph Laplacian use
// exp(-d) = p_mix, so the same number serves both roles.
//
// HEAT-KERNEL DIFFUSION
//
//   φ(t) = exp(-t · L_sym) · ρ
//
// where L_sym = I - D^(-1/2) W D^(-1/2) is the normalised graph Laplacian.
// Evaluated via Chebyshev polynomial expansion:
//
//   exp(-t·L) ≈ Σ_{k=0..K} c_k(t) · T_k(L)
//
// where T_k are Chebyshev polynomials (first kind) and c_k(t) are
// modified Bessel functions I_k(-t). For K=20, accuracy is ~1e-8 on the
// spectrum [0, 2]. Each T_k(L)·ρ step is a sparse matvec — O(|E|) work.
// Total: O(K·|E|). A 10k-file repo with 100k edges diffuses in ~2M ops.
//
// THE TEMPERATURE KNOB
//
// Single scalar t controls diffusion range:
//   t ≈ 0.25  — just the touched items
//   t ≈ 1.0   — 1-hop neighbourhood (commit review default)
//   t ≈ 2.0   — 2-hop, semantic neighbours (code Q&A)
//   t ≈ 4.0   — wide, historical (codebase navigation)
//   t → ∞     — graph centrality (whole-repo summary)
//
// Same engine, same data, different t.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'engram_file_ktable.dart';
import 'engram_fit.dart';
import 'engram_hunk_encoder.dart';
import 'file_coupling.dart';
import 'logos_core.dart';
import 'logos_git_calibration.dart' show LogosAxis;
import 'logos_git_integrity.dart';

/// Internals re-exported for tests. Not stable API — the `@visibleForTesting`
/// annotation makes accidental production use lint.
@visibleForTesting
// ignore: library_private_types_in_public_api
typedef LogosCsrGraphForTesting = CsrGraph;

@visibleForTesting
List<double> chebyshevBesselCoeffsForTesting(double t, int K) =>
    besselCoeffs(t, K);

@visibleForTesting
void diffuseChebyshevForTesting({
  required CsrGraph graph,
  required Float64List rho,
  required Float64List phi,
  required double t,
  int K = kDefaultChebyshevK,
}) =>
    chebyshevDiffuse(graph: graph, rho: rho, phi: phi, t: t, K: K);

@visibleForTesting
// ignore: library_private_types_in_public_api
CsrGraph buildCsrForTesting({
  required int n,
  required List<int> indptr,
  required List<int> indices,
  required List<double> values,
}) =>
    CsrGraph(
      n: n,
      indptr: Int32List.fromList(indptr),
      indices: Int32List.fromList(indices),
      values: Float64List.fromList(values),
    );

@visibleForTesting
extension LogosGitTestAccess on LogosGit {
  // ignore: library_private_types_in_public_api
  CsrGraph get graphForTesting => graph;
}

// LAZY LUTs — adapted from logos.wat

/// log1p(n) — returns ln(1+n). Cached for small integer n so the
/// repeated weight computation doesn't call `math.log` for every edge.
/// Sentinel 0.0 means "not yet computed"; ln(1+0) = 0 naturally, so the
/// sentinel is safe for n=0 too.
class _Log1pLut {
  static final Float64List _t = Float64List(4096);

  static double call(int n) {
    if (n <= 0) return 0;
    if (n < 4096) {
      final cached = _t[n];
      if (cached != 0) return cached;
      final v = math.log(1.0 + n);
      _t[n] = v;
      return v;
    }
    return math.log(1.0 + n);
  }
}

/// σ(x) — logistic sigmoid. Same role as Logos' SIGMOID_LUT. Kept
/// lightweight; Dart's math.exp is native so a table lookup would barely
/// beat it on modern CPUs. If we need to port to .wat we'll add a
/// linear-interpolated LUT there (the WASM VM has no native exp).
double _sigmoid(double x) {
  if (x <= -12) return 1.5259021896696422e-05;
  if (x >= 12) return 0.9999847409781033;
  return 1.0 / (1.0 + math.exp(-x));
}

// BORN-AMPLITUDE MIX — the core blend operation

/// Per-axis observation: probability `p` in [ε, 1-ε] and evidence count `n`.
/// Axes with `n == 0` declare themselves silent via `weight() == 0`.
class AxisObs {
  final double p;
  final int n;
  const AxisObs(this.p, this.n);
  static const silent = AxisObs(0.5, 0);
}

/// Born-amplitude mix with confidence-gated, evidence-capped weights.
///   weight(i) = |p_i - 0.5| · min(log1p(n_i), cap_i)
///   A  = Σ w_i · √p_i
///   Ā  = Σ w_i · √(1 - p_i)
///   p  = A² / (A² + Ā²)
/// The confidence gate |p-0.5| makes axes at p≈0.5 (pure uncertainty)
/// contribute zero — they can't drown out sharper axes. The `cap_i` per
/// axis prevents an over-evidenced axis from monopolising the mix.
/// Correlated axes (CC and AU firing together because same team edits
/// same files) don't double-count: amplitude interference absorbs the
/// shared component quadratically. Orthogonal lifts add as Pythagorean
/// limbs.
/// Returns a single probability in (ε, 1-ε). If all axes are silent,
/// returns 0.5 (maximum uncertainty — edge contributes weight exp(-d)=
/// exp(ln(2)) ≈ 0.5 to the graph, i.e. a "weak connection").
class BornMixer {
  /// Evidence caps per axis — order matches the observation list passed
  /// to [mix]. F0 has the smallest cap (low evidence per commit);
  /// CC/V/SP mid-range; axes to be added later (CG, AU, EM) can set
  /// higher caps to reflect richer evidence.
  final List<double> caps;

  const BornMixer(this.caps);

  double mix(List<AxisObs> obs) {
    if (obs.length != caps.length) {
      throw ArgumentError('axis count mismatch');
    }
    var aSum = 0.0, aBarSum = 0.0;
    var totalWeight = 0.0;

    for (var i = 0; i < obs.length; i++) {
      final o = obs[i];
      if (o.n == 0) continue; // silent axis
      final evidence = math.min(_Log1pLut.call(o.n), caps[i]);
      final confidence = (o.p - 0.5).abs();
      final w = confidence * evidence;
      if (w == 0) continue;
      totalWeight += w;
      // Clamp p into the numerical safe zone to keep sqrt stable.
      final p = o.p.clamp(1e-6, 1 - 1e-6);
      aSum += w * math.sqrt(p);
      aBarSum += w * math.sqrt(1.0 - p);
    }
    if (totalWeight == 0) return 0.5;
    final a2 = aSum * aSum;
    final b2 = aBarSum * aBarSum;
    final denom = a2 + b2;
    // Belt + braces: the only paths into NaN here are sqrt of a clamped
    // p (impossible) or aSum/aBarSum already non-finite (also impossible
    // given the upstream guards) — but cheaper to guard than to debug.
    if (!denom.isFinite || denom <= 0) return 0.5;
    final p = a2 / denom;
    if (!p.isFinite) return 0.5;
    return p.clamp(1e-6, 1 - 1e-6);
  }
}

// AXIS COMPUTERS — Phase 1 set
//
// Each axis is a function (file_a, file_b, repoStats) → AxisObs.
// Axes only need the symmetric pair; the engine feeds every edge it
// decides to materialise.
//
// The axis order here is THE canonical order. BornMixer.caps must be
// in the same order. Keep them in lockstep.

/// The canonical axis order. [BornMixer.caps] is indexed in this order;
/// any axis reshuffle needs both lists to move together. EN sits last
/// because it's optional (only present when the engine was built with
/// engram K-vectors); the engram-less mixer uses caps[0..3] only.
enum AxisId { f0, cc, sp, v, en }

/// F0 — global frequency axis.
/// Purely conditional on the *destination* file: "how often does this
/// file appear in commits at all?" Symmetric by design — we're asking
/// whether `b` is a noteworthy node in the repo regardless of `a`.
/// Cold-start via KT prior α=0.5.
class _F0Axis {
  /// touches[file] = commits that touched the file over the analysed
  /// history window.
  final Map<String, double> touchMass;

  /// Total commits in the window (denominator for the KT prior).
  final double totalCommitMass;

  const _F0Axis({required this.touchMass, required this.totalCommitMass});

  AxisObs observe(String b) {
    final t = touchMass[b] ?? 0.0;
    if (totalCommitMass <= 0) return AxisObs.silent;
    // KT prior: (t + 0.5) / (totalCommits + 1)
    final p = (t + 0.5) / (totalCommitMass + 1.0);
    final evidence = totalCommitMass.clamp(0.0, 1 << 20).round();
    return AxisObs(p, evidence);
  }
}

/// CC — co-change axis. Uses the existing [FileCouplingMatrix].
/// P(b co-occurs with a | history) = Jaccard(a, b) smoothed with a KT
/// prior against the number of commits touching either side.
class _CcAxis {
  final FileCouplingMatrix matrix;

  const _CcAxis(this.matrix);

  AxisObs observe(String a, String b) {
    if (a == b) return const AxisObs(1.0, 1);
    final j = matrix.score(a, b);
    // Convert Jaccard (already smoothed by the matrix builder) into a
    // KT-style probability. We bias toward 0.5 when Jaccard is 0 by
    // blending with the prior at n=commitsAnalyzed/10 evidence.
    final evidence = (matrix.commitsAnalyzed / 10).clamp(0, 1024).toInt();
    final p = (j * evidence + 0.5) / (evidence + 1.0);
    return AxisObs(p, evidence);
  }
}

// SP — path / spatial proximity.
//
// Measures directory overlap between two paths. Inlined into the build
// loop in `LogosGit.buildFromStats` (uses cached `pathSegments` to
// avoid two `.split('/')` allocations per scored edge — a per-build
// bytes saved is allocation pressure that won't trigger a young-gen GC).
//
// Semantics, for reference:
//   sa = a.split('/'); sb = b.split('/'); max = max(|sa|, |sb|)
//   shared = longest common prefix length, excluding final segment
//   p = (shared + 0.5) / (max + 1.0); evidence = max

/// V — volatility (GARCH-style second moment).
/// Each file has an EWMA of per-commit churn magnitude (additions +
/// deletions). Two files are "V-related" when their volatilities *match*
/// — the axis rewards probes diffusing toward other noisy files when
/// the diff itself is noisy, and toward stable files when the diff is
/// tame. Sign-aligned z-matching: z(|v_a - v_b|) inverted via sigmoid.
class _VAxis {
  final Map<String, double> volatility;
  final double mean;
  final double stddev;

  const _VAxis({
    required this.volatility,
    required this.mean,
    required this.stddev,
  });

  AxisObs observe(String a, String b) {
    final va = volatility[a];
    final vb = volatility[b];
    if (va == null || vb == null) return AxisObs.silent;
    if (stddev <= 0) return AxisObs.silent;
    final z = (va - vb).abs() / stddev;
    // Small |z| → high p (volatilities match).
    final p = _sigmoid(2.0 - z);
    // Evidence grows with the number of observations feeding the EWMA.
    // We don't track per-file sample counts; use a small fixed evidence
    // count (axis remains informative but can't dominate).
    return AxisObs(p, 4);
  }
}

/// EN — engram K-space cosine. Optional; only present when the engine
/// was built with `perFileKVectors` populated by the resolver.
/// Each file gets a K-vector ∈ ℂ^P (Alexandria's 150-pair eigenvalue
/// signature for the file's identifier content). Pairwise cosine in
/// ℝ^(2P) measures **content-semantic** affinity — orthogonal to CC's
/// historical co-change and SP's directory geometry, complementary to
/// the existing symbolEdges per-changeset symbol-overlap signal.
/// What this catches that the other axes miss:
///   • Files with similar purpose that have never co-changed (refactored
///     out, renamed, freshly-added).
///   • Cross-module semantic neighbours (test fixtures next to the
///     service they exercise; reducer + selector pairs in different dirs).
///   • Cold-start: a brand-new repo with empty history still has full
///     EN signal because K-vectors come from current content, not history.
/// Probability is the cosine clamped to [0, 1] then re-anchored against
/// the 0.5 mid-line (the silent default) — cosine ≥ 0.5 reads as a
/// positive predictor; below pulls the mixer toward "unrelated".
/// Built atop [EngramFileKTable] so observations read from contiguous
/// flat arrays — no per-pair object dereference. The build loop
/// pre-resolves each nodePath to its table row id once, then
/// `observeIds(rowA, rowB)` is pointer-bumping linear access for the
/// pairwise cosine.
class _EnAxis {
  /// Pre-resolved row ids per node. `_rowIds[nodeId] == -1` for nodes
  /// without a K-vector (silent for those pairs). Resolved once at
  /// build start to avoid a hashmap lookup per edge candidate.
  final Int32List rowIds;
  final EngramFileKTable table;

  const _EnAxis({required this.rowIds, required this.table});

  AxisObs observeIds(int aNodeId, int bNodeId) {
    final ra = rowIds[aNodeId];
    if (ra < 0) return AxisObs.silent;
    final rb = rowIds[bNodeId];
    if (rb < 0) return AxisObs.silent;
    final cos = _cosineRows(table, ra, rb);
    if (cos <= 0) return AxisObs.silent;
    // Map cosine ∈ [0,1] to p ∈ [0.5, 1] — the axis is a "boost only"
    // signal. The 0.5 anchor makes the confidence gate `|p - 0.5|`
    // proportional to the cosine itself, which is what we want.
    final p = 0.5 + 0.5 * cos;
    // Evidence: the K-vector quality reflects how many GloVe-hittable
    // sub-tokens fed the AR(2). Use the smaller of the pair so a
    // sparsely-tokenised file can't claim more confidence than its
    // signal supports.
    final hitsA = table.vocabHits[ra];
    final hitsB = table.vocabHits[rb];
    final n = hitsA < hitsB ? hitsA : hitsB;
    return AxisObs(p, n);
  }
}

/// Cosine between two rows of an [EngramFileKTable], reading directly
/// from the flat columns. Treats ℂ^P as ℝ^(2P) — same metric as
/// [EngramHunkEncoder.cosine] but with no object dereference.
double _cosineRows(EngramFileKTable t, int rowA, int rowB) {
  final p = t.pairs;
  final aBase = rowA * p;
  final bBase = rowB * p;
  final re = t.kRe;
  final im = t.kIm;
  double dot = 0.0;
  double aMagSq = 0.0;
  double bMagSq = 0.0;
  for (var i = 0; i < p; i++) {
    final ar = re[aBase + i];
    final ai = im[aBase + i];
    final br = re[bBase + i];
    final bi = im[bBase + i];
    dot += ar * br + ai * bi;
    aMagSq += ar * ar + ai * ai;
    bMagSq += br * br + bi * bi;
  }
  if (aMagSq <= 0 || bMagSq <= 0) return 0.0;
  final cos = dot / math.sqrt(aMagSq * bMagSq);
  if (!cos.isFinite) return 0.0;
  if (cos <= 0) return 0.0;
  if (cos >= 1) return 1.0;
  return cos;
}

// SPARSE GRAPH (CSR) + Chebyshev heat-kernel — moved to logos_core.dart
//
// The graph data structure ([CsrGraph]) and all heat-kernel diffusion
// primitives ([besselCoeffs], [adaptiveK], [chebyshevDiffuse],
// [chebyshevBasis], [recombineHeatPhi]) live in `logos_core.dart`. The
// file/chunk/hunk engines all share that one implementation. What
// remains in this file is the file-graph-specific axis blend
// (BornMixer + F0/CC/SP/V) and the LogosGit engine itself.
//
// (CsrGraph + applyLsym + estimateSpectralRadius live in logos_core.dart.)

// (kDefaultChebyshevK + kDefaultPowerIterations + Bessel constants
// live in logos_core.dart and are re-exported via the import above.)

/// Default top-K window for the stability primitive and single-source
/// `relatedTo` queries. Scaled to a typical commit-review budget:
/// ~20 neighbours fits comfortably inside a 60k-char prompt at the
/// breadcrumb tier, and a meaningfully-long ranking to perturb.
const int _defaultTopK = 20;

/// Stability-primitive perturbation budget. Six trials is the minimum
/// for a meaningful Jaccard-overlap mean without burning too much CPU
/// on a diagnostic call (each trial is one full Chebyshev diffusion).
/// Three trials would give 33%-granular stability; six gives ~17%,
/// comfortable for the downstream firm/soft/knife-edge bucketing.
const int _defaultStabilityTrials = 6;

/// Multiplicative jitter magnitude for the stability primitive.
/// ε = 0.15 means source weights move ±15% per trial — well above
/// the noise floor of sane upstream probes (SSE-scaled weights shift
/// by <5%) but inside the band where a stable ranking should hold.
const double _defaultStabilityEpsilon = 0.15;

/// Deterministic seed for the stability primitive's RNG. Arbitrary
/// but constant — repeated calls produce identical perturbations,
/// making the primitive reproducible in tests and diagnostics.
const int _defaultStabilitySeed = 0xABDE;

/// Default top-K neighbours per node in the sparsified graph. Derived
/// as a small multiple of the max expected "cluster size" in a real
/// repo — a single module typically has 10-20 tightly-coupled files,
/// so 24 neighbours keeps every plausible cluster connected while
/// bounding the graph to O(24·|V|) edges. Mentioned separately from
/// the Chebyshev K to avoid confusion — this K is graph sparsity, not
/// polynomial order.
const int _defaultEdgeDensity = 24;

// (besselCoeffs / adaptiveK / chebyshevDiffuse live in logos_core.dart.)

// THE ENGINE

/// Raw per-file statistics the engine needs to construct its axes.
class LogosGitStats {
  final Map<String, int> touches;
  final int totalCommits;
  final Map<String, int> rawTouches;
  final int rawTotalCommits;
  final Map<String, double> touchMass;
  final double semanticCommitMass;
  final Map<String, double> volatility;
  final double volMean;
  final double volStddev;
  final FileCouplingMatrix coupling;

  /// Per-file commit-index series: for each file, the sorted list of
  /// commit indices (in oldest→newest order, range [0, totalCommits))
  /// where the file appeared. Drives the per-file AR(2) curvature
  /// metric in [LogosGit.buildFromStats] — each file gets its own
  /// `K, G` from the inter-touch-gap dynamics, and edge weights are
  /// multiplied by the geometric mean of the two endpoints' spectral
  /// radii so heat flows respect each file's own time-scale (Whisper
  /// Harmonic's curved-Christoffel pattern, applied per-file).
  /// Required: pass `const {}` to explicitly opt out (flat-metric
  /// graph, curvature factor 1.0 for every edge). Tests + light-
  /// weight engines that don't have per-commit data should be
  /// explicit about it rather than silently falling through a
  /// default.
  final Map<String, List<int>> perFileCommitIndices;
  final Map<String, List<double>> perFileCommitClock;
  final Map<String, double> ritualnessByPath;
  final Map<String, double> integrityByPath;
  final Map<String, List<String>> integrityReasonsByPath;

  const LogosGitStats({
    required this.touches,
    required this.totalCommits,
    required this.volatility,
    required this.volMean,
    required this.volStddev,
    required this.coupling,
    required this.perFileCommitIndices,
    this.rawTouches = const {},
    this.rawTotalCommits = 0,
    this.touchMass = const {},
    this.semanticCommitMass = 0.0,
    this.perFileCommitClock = const {},
    this.ritualnessByPath = const {},
    this.integrityByPath = const {},
    this.integrityReasonsByPath = const {},
  });
}

/// Relevance score produced by diffusion. `phi` is the raw heat-kernel
/// value; higher = more relevant. `path` identifies the file.
class RelevanceScore {
  final String path;
  final double phi;
  const RelevanceScore(this.path, this.phi);
  @override
  String toString() => '$path  φ=${phi.toStringAsFixed(4)}';
}

/// Emission tier — FULL (whole body), SIG (signature + breadcrumbs),
/// BREAD (filename + one-liner). Higher tier = more tokens, more info.
enum EmissionTier { full, signature, breadcrumb }

class EmissionPlan {
  final String path;
  final double phi;
  final EmissionTier tier;
  const EmissionPlan(this.path, this.phi, this.tier);
}

class LogosEvidenceScore {
  final String path;
  final double support;
  final double ambient;
  final double rawSurplus;
  final double surplus;
  final double integrity;
  final double utility;
  final String? dominantAxis;
  final Map<String, double>? axisShares;

  const LogosEvidenceScore({
    required this.path,
    required this.support,
    required this.ambient,
    required this.rawSurplus,
    required this.surplus,
    required this.integrity,
    required this.utility,
    this.dominantAxis,
    this.axisShares,
  });
}

class LogosEvidenceQueryResult {
  final List<LogosEvidenceScore> ranked;
  final double? sourceAlignment;
  final double? fieldAlignment;
  final double? sourceSurprise;
  final double? fieldSurprise;
  final double coherence;
  final double stability;
  final AxisAttribution? supportAttribution;

  const LogosEvidenceQueryResult({
    required this.ranked,
    required this.sourceAlignment,
    required this.fieldAlignment,
    required this.sourceSurprise,
    required this.fieldSurprise,
    required this.coherence,
    required this.stability,
    required this.supportAttribution,
  });
}

/// Born-mix caps per axis, in the canonical [AxisId] order (f0, cc, sp, v).
/// The caps are the maximum evidence (in nats) each axis can contribute
/// to the Born amplitude mix. They're information-theoretic — each is
/// the natural log of the axis's intrinsic branching factor:
///   F0 = ln(2) — one bit: "is this file touched at all in this window?"
///   CC = ln(4) — two bits: four effective co-change regimes
///                (together|sometimes|rarely|never)
///   SP = ln(3) — one trit: same file | same directory | elsewhere
///   V  = ln(3) — one trit: calmer | matched | noisier than the partner
/// Derivable not magic: each value is literally `ln(k)` where k is the
/// axis's distinguishable states. Expressed as such so the relationship
/// is visible in the code, not stranded in a comment.
final _defaultCaps = <double>[
  math.ln2,          // F0: ln(2)
  2 * math.ln2,      // CC: ln(4) = 2·ln(2)
  math.log(3),       // SP: ln(3)
  math.log(3),       // V:  ln(3)
];

/// Caps when the engine was built with engram K-vectors. Adds an EN
/// cap of ln(4) = 2 bits — Alexandria's wells distinguish ~225 semantic
/// basins, but most files cluster around a handful of dominant ones in
/// any given repo. Two bits captures "same well | adjacent well | far
/// well | unrelated" without letting the EN axis dominate well-evidenced
/// CC signals.
final _defaultCapsWithEngram = <double>[
  ..._defaultCaps,
  2 * math.ln2,      // EN: ln(4)
];

/// The Logos-inspired git context engine.
/// Usage:
///   final engine = await LogosGit.buildFromStats(stats);
///   final scores = engine.diffuse({'lib/validators.dart', 'lib/auth.dart'});
///   final plan = engine.plan(scores, budget: 80000);
/// The engine is immutable after construction. To refresh after new
/// commits, rebuild.
class LogosGit {
  // ignore: library_private_types_in_public_api
  final CsrGraph graph;
  final List<String> nodePaths; // id → path
  final Map<String, int> pathToId;
  final BornMixer mixer;

  /// Per-file AR(2) fit on the file's inter-touch-gap series. Computed
  /// in [buildFromStats] when [LogosGitStats.perFileCommitIndices] is
  /// available and the file has enough touches for the fit. Empty for
  /// files with insufficient history (curvature factor = 1.0 for them).
  /// Drives the curved-metric edge weighting: each file's spectral
  /// radius `r_f = √G_f` measures how regular its touch pattern is
  /// (1.0 = perfectly periodic, 0 = chaotic). Edge weight `W'[a,b] =
  /// W[a,b] · √(r_a · r_b)` so heat flows faster through regularly-
  /// touched files and attenuates through chaotic ones.
  final Map<String, EngramFit> perFileMetrics;

  /// The raw stats this engine was built from. Retained as a back-
  /// reference so callers can derive secondary signals (recency-decayed
  /// activity field, per-file touch counts, etc.) without re-running
  /// [collectLogosGitStats]. Conceptually: stats are the *what*, the
  /// engine is the *how* — keeping both adjacent avoids duplicating the
  /// log-walk in features that need both.
  final LogosGitStats stats;
  final Map<String, double> integrityByPath;

  /// Symbol-overlap edges for the current change set. Injected per
  /// change-set via [withSymbolEdges]; absent from the base engine built
  /// from history alone. Stored fully-symmetric (both directions present)
  /// so neighbour lookups are a single map access.
  /// Used in two places:
  ///   • [_buildRho] — proxies heat from unknown (new/untracked) source
  ///     paths through their symbol-linked known graph nodes.
  ///   • [_deriveNewPathPhi] — computes a derived φ for new paths so they
  ///     appear in diffusion output even though they aren't graph nodes.
  final Map<String, Map<String, double>> symbolEdges;

  /// Per-file K-vector signatures from Alexandria, as a dense column
  /// store. Empty (`isEmpty == true`) when the engine was built
  /// without engram assets — the fallback path that keeps the engine
  /// working in cold-asset / test scenarios.
  /// When non-empty:
  ///   • Drives the EN axis in the Born mixer (semantic content
  ///     similarity between file pairs).
  ///   • Surfaced via [wellOf] for tagging and prompt annotations:
  ///     callers can ask "what semantic basin does file X live in?".
  /// Built once per HEAD inside the resolver; persisted to disk across
  /// app launches so repo reopens hit the cache.
  final EngramFileKTable perFileKVectors;

  LogosGit._({
    required this.graph,
    required this.nodePaths,
    required this.pathToId,
    required this.mixer,
    required this.perFileMetrics,
    required this.stats,
    required this.integrityByPath,
    this.symbolEdges = const {},
    EngramFileKTable? perFileKVectors,
  })  : perFileKVectors = perFileKVectors ?? _emptyTable;

  /// Singleton empty K-table used when no engram assets are loaded.
  /// Avoids per-engine empty allocations and ensures the field is
  /// non-nullable on all code paths.
  static final EngramFileKTable _emptyTable = EngramFileKTable.empty(0);

  /// Nearest Alexandria well for [path], or null if the engine wasn't
  /// built with engram K-vectors / the file failed to encode. The
  /// returned name is the well's label (e.g. "computing", "well_43").
  String? wellOf(String path) => perFileKVectors.wellOf(path);

  /// Return a copy of this engine aware of symbol-overlap edges for the
  /// current change set. Cheap — shares the immutable graph; only the
  /// edge map is new. The symmetrisation step here means every caller
  /// can do a single `symbolEdges[path]` lookup instead of checking
  /// both triangle directions.
  LogosGit withSymbolEdges(Map<String, Map<String, double>> sym) {
    if (sym.isEmpty) return this;
    // Expand upper-triangle storage → fully symmetric.
    final expanded = <String, Map<String, double>>{};
    for (final entry in sym.entries) {
      final a = entry.key;
      for (final inner in entry.value.entries) {
        final b = inner.key;
        final score = inner.value;
        (expanded[a] ??= {})[b] = score;
        (expanded[b] ??= {})[a] = score;
      }
    }
    return LogosGit._(
      graph: graph,
      nodePaths: nodePaths,
      pathToId: pathToId,
      mixer: mixer,
      perFileMetrics: perFileMetrics,
      stats: stats,
      integrityByPath: integrityByPath,
      symbolEdges: expanded,
      perFileKVectors: perFileKVectors,
    );
  }

  /// Construct the engine from per-file statistics. Nodes are all files
  /// with at least one observation from any axis; edges are the
  /// `edgeDensity`·N pairs with the strongest mixed probability (top-K
  /// per node to keep the graph sparse).
  static LogosGit buildFromStats(
    LogosGitStats stats, {
    int edgeDensity = _defaultEdgeDensity,
    EngramFileKTable? perFileKVectors,
  }) {
    // Whether the EN axis is active for this build. Determined once
    // here so the build loop can branch cleanly without per-edge
    // null checks inside the hot path.
    final useEngram = perFileKVectors != null && !perFileKVectors.isEmpty;
    final caps = useEngram ? _defaultCapsWithEngram : _defaultCaps;
    final obsBufSize = caps.length;

    // Materialise the node set: union of files seen by any axis.
    // `coupling.paths` is the CSR's interned path list — using it
    // directly avoids triggering the lazy nested-map materialisation
    // just to read the key set.
    final pathSet = <String>{};
    pathSet.addAll(stats.touches.keys);
    pathSet.addAll(stats.rawTouches.keys);
    pathSet.addAll(stats.touchMass.keys);
    pathSet.addAll(stats.volatility.keys);
    pathSet.addAll(stats.coupling.paths);
    pathSet.addAll(stats.integrityByPath.keys);

    // Stable ordering — sort for determinism (helps debugging + caching).
    final nodePaths = pathSet.toList()..sort();
    final pathToId = <String, int>{};
    for (var i = 0; i < nodePaths.length; i++) {
      pathToId[nodePaths[i]] = i;
    }

    final n = nodePaths.length;
    if (n == 0) {
      // Empty graph — engine does nothing useful but doesn't throw.
      return LogosGit._(
        graph: CsrGraph(
          n: 0,
          indptr: Int32List(1),
          indices: Int32List(0),
          values: Float64List(0),
        ),
        nodePaths: nodePaths,
        perFileMetrics: const {},
        pathToId: pathToId,
        mixer: BornMixer(caps),
        stats: stats,
        integrityByPath: stats.integrityByPath,
        perFileKVectors: useEngram ? perFileKVectors : null,
      );
    }

    final mixer = BornMixer(caps);
    final f0 = _F0Axis(
      touchMass: stats.touchMass.isNotEmpty
          ? stats.touchMass
          : {
              for (final entry in stats.touches.entries)
                entry.key: entry.value.toDouble(),
            },
      totalCommitMass: stats.semanticCommitMass > 0
          ? stats.semanticCommitMass
          : stats.totalCommits.toDouble(),
    );
    final cc = _CcAxis(stats.coupling);
    // SP observe is inlined into the build loop below (uses cached
    // pathSegments to avoid the per-call `.split('/')` allocations).
    // `_SpAxis` is kept as a class for testing + potential out-of-loop
    // callers, but the build path no longer instantiates it.
    final v = _VAxis(
      volatility: stats.volatility,
      mean: stats.volMean,
      stddev: stats.volStddev,
    );

    // Pre-resolve every node's K-table row id once so the EN axis's
    // hot loop reads it from a flat Int32List instead of doing a
    // hashmap lookup per edge candidate. Rows that don't exist in the
    // table get -1 — silent for those pairs.
    final enRowIds = useEngram ? Int32List(n) : null;
    if (useEngram && enRowIds != null) {
      enRowIds.fillRange(0, n, -1);
      for (var i = 0; i < n; i++) {
        final row = perFileKVectors.rowOf(nodePaths[i]);
        if (row != null) enRowIds[i] = row;
      }
    }
    // EN axis — only constructed when we have K-vectors. When silent
    // we keep the variable null and the build loop simply skips the
    // 5th observation (mixer caps stay 4-element).
    final en = useEngram
        ? _EnAxis(rowIds: enRowIds!, table: perFileKVectors)
        : null;

    // ── Per-file curved metric (Whisper Harmonic, applied per-file).
    // For each file with sufficient touch history, fit AR(2) on the
    // inter-touch-gap series. The spectral radius `r_f = √G_f` of the
    // fit measures how regular the file's touch pattern is — high
    // when periodic, low when chaotic. Edge weight `W'[a,b] = W[a,b] ·
    // √(r_a · r_b)` so heat flows preferentially through files whose
    // own time-scale is well-defined. Files without enough history
    // fall through to the linear AR(2) fallback (spectral radius 0)
    // which would attenuate edges to zero — we coerce those to 1.0
    // so they're indistinguishable from the previous flat-metric
    // behaviour, not silently muted.
    final perFileMetrics = <String, EngramFit>{};
    final metricPaths = <String>{
      ...stats.perFileCommitIndices.keys,
      ...stats.perFileCommitClock.keys,
    };
    for (final path in metricPaths) {
      final series = stats.perFileCommitClock[path] ??
          stats.perFileCommitIndices[path]
              ?.map((i) => i.toDouble())
              .toList(growable: false);
      if (series == null || series.length < 3) continue; // need ≥2 gaps
      final gaps = <double>[];
      for (var k = 1; k < series.length; k++) {
        gaps.add(series[k] - series[k - 1]);
      }
      final fit = engramFit(gaps);
      // Skip non-orbital fits — their spectral radius is meaningless
      // for the curvature interpretation. Files left out of the map
      // get curvature 1.0 (no attenuation, no boost).
      if (fit.isLinearFallback) continue;
      perFileMetrics[path] = fit;
    }

    // (Per-file curvature factor — formerly an inline closure here —
    // is now materialised as a precomputed `Float64List curvatures`
    // inside the build loop below, keyed by node id. 1.0 when the
    // file has no AR(2) fit; otherwise the spectral radius clamped
    // to [0.5, 1.0] so the attenuation never drops an edge weight
    // by more than half.)

    // For each node, score all candidate neighbours and keep the top
    // `edgeDensity` by mixed probability. This is the critical step —
    // a fully-connected graph would be n² edges; we prune here.
    //
    //
    // Without these the inner loop is O(N²·d): the original code did a
    // `for (final p in nodePaths) if (p.startsWith('$parent/'))` scan
    // *per node*, plus per-edge `firstWhere` linear probes during
    // symmetrise. On a 10k-file repo that's 100M+ string compares.
    //
    //   dirIndex     — parent-dir → ids of all nodes whose parent is
    //                  that dir. Replaces the O(n) prefix scan with
    //                  an O(|siblings|) lookup.
    //   pathSegments — node id → already-split path. Eliminates the
    //                  `a.split('/')` + `b.split('/')` allocation pair
    //                  inside what is the build's hottest scoring call.
    //   curvatures   — node id → cached AR(2)-spectral-radius factor.
    //                  Avoids repeated Map lookup per edge.
    //   f0Obs        — node id → F0 observation (depends only on the
    //                  destination; can be precomputed).
    final f0Obs =
        List<AxisObs>.generate(n, (i) => f0.observe(nodePaths[i]));
    final dirIndex = <String, List<int>>{};
    final pathSegments = List<List<String>>.generate(
        n, (i) => nodePaths[i].split('/'));
    final curvatures = Float64List(n);
    // Well → node-ids index. Same shape as `dirIndex` but partitioned
    // by Alexandria's learned semantic wells instead of directory
    // structure. This is the creative move: wells already group files
    // that talk about the same concepts (via K-space geometry). By
    // surfacing same-well siblings as EDGE CANDIDATES — not just
    // scoring existing candidates with the EN axis — we capture
    // cross-directory, cross-history feature clusters that CC
    // (co-change) and SP (directory) structurally can't see.
    //
    // Indexed by the brain's ORIGINAL well index (an int from the
    // table's wellIdx column), so the inner-loop lookup is an
    // Int32List read instead of a string hash.
    //
    // Empty when `useEngram=false`; the downstream candidate loop
    // just skips the well-siblings contribution in that case.
    final List<List<int>>? wellIdToNodes;
    final Int32List? nodeWellIds;
    if (useEngram) {
      // First pass: read each node's wellIdx (or -1) directly from
      // the K-table column — pointer-bumping linear access.
      nodeWellIds = Int32List(n)..fillRange(0, n, -1);
      var maxWell = -1;
      for (var i = 0; i < n; i++) {
        final row = enRowIds![i];
        if (row < 0) continue;
        final wid = perFileKVectors!.wellIdx[row];
        if (wid < 0) continue;
        nodeWellIds[i] = wid;
        if (wid > maxWell) maxWell = wid;
      }
      // Second pass: bucket nodes by their well id. List indexed by
      // original well id ∈ [0, maxWell], so lookup is `wellIdToNodes![wid]`
      // — no hashmap. Empty bucket lists are null to skip allocation
      // for unused well ids.
      if (maxWell >= 0) {
        wellIdToNodes = List<List<int>>.filled(maxWell + 1, const []);
        for (var i = 0; i < n; i++) {
          final wid = nodeWellIds[i];
          if (wid < 0) continue;
          var bucket = wellIdToNodes[wid];
          if (bucket.isEmpty) {
            bucket = <int>[];
            wellIdToNodes[wid] = bucket;
          }
          bucket.add(i);
        }
      } else {
        wellIdToNodes = null;
      }
    } else {
      wellIdToNodes = null;
      nodeWellIds = null;
    }
    for (var i = 0; i < n; i++) {
      final p = nodePaths[i];
      final slash = p.lastIndexOf('/');
      if (slash > 0) {
        final parent = p.substring(0, slash);
        (dirIndex[parent] ??= <int>[]).add(i);
      }
      final fit = perFileMetrics[p];
      if (fit == null) {
        curvatures[i] = 1.0;
      } else {
        final r = fit.spectralRadius;
        curvatures[i] = (!r.isFinite || r <= 0) ? 1.0 : r.clamp(0.5, 1.0);
      }
    }

    // Pass 1: collect raw (neighbour, p_mix) pairs per row. Pass 2:
    // normalise by D^(-1/2) and write CSR.
    final degree = Float64List(n);
    final rawRows = List<List<_EdgeCandidate>>.generate(n, (_) => []);

    // Reused buffer fed to BornMixer.mix — saves one 4-element list
    // allocation per scored edge (~candidates × N allocations otherwise).
    // Sized to match the active mixer (4 axes by default, 5 with EN).
    final obsBuf = List<AxisObs>.filled(obsBufSize, AxisObs.silent,
        growable: false);

    for (var i = 0; i < n; i++) {
      final a = nodePaths[i];
      final integrityA = stats.integrityByPath[a] ?? 1.0;
      // Candidate set as ids — avoids the eventual pathToId hash lookup
      // we'd have done if we collected strings first. Set semantics
      // dedupe between the CC neighbours and the directory siblings.
      final candidates = <int>{};
      // CSR-native row iteration: walks the `a` row's contiguous
      // colIdx slice and yields neighbour paths without materialising
      // a Map. ~10× faster than the old `coupling.jaccard[a]?.keys`
      // access on warm builds because there's no lazy-map population
      // and no per-edge map-entry allocation.
      for (final neighbour in stats.coupling.jaccardKeysOf(a)) {
        final id = pathToId[neighbour];
        if (id != null && id != i) candidates.add(id);
      }
      final segA = pathSegments[i];
      if (segA.length > 1) {
        // Reconstruct the parent — segA already split, joining is faster
        // than re-substring on the original path.
        final parent = segA.sublist(0, segA.length - 1).join('/');
        final siblings = dirIndex[parent];
        if (siblings != null) {
          for (final id in siblings) {
            if (id != i) candidates.add(id);
          }
        }
      }

      // Well-siblings — semantic candidates. If this node has a
      // K-vector with a nearest well, consider every other node in
      // that well as a candidate too. Capped at [edgeDensity] per
      // node to match the downstream top-K sparsifier's budget —
      // beyond that the sparsifier would drop extras anyway, so we
      // don't pay the scoring cost.
      //
      // Together with the CC + SP sources, this widens the graph's
      // reach in exactly the dimension the existing axes don't: a
      // same-concept file sitting in a different directory, never
      // co-changed with `i` yet, now has a chance to be considered.
      // The Born mixer then decides whether the evidence across F0 /
      // CC / SP / V / EN actually justifies an edge.
      //
      // Lookup is now an Int32List + List<List<int>> indexing pair —
      // no hashmap, no string comparisons.
      if (wellIdToNodes != null) {
        final myWid = nodeWellIds![i];
        if (myWid >= 0 && myWid < wellIdToNodes.length) {
          final wellSiblings = wellIdToNodes[myWid];
          final cap = edgeDensity < wellSiblings.length
              ? edgeDensity
              : wellSiblings.length;
          for (var k = 0; k < cap; k++) {
            final id = wellSiblings[k];
            if (id != i) candidates.add(id);
          }
        }
      }

      if (candidates.isEmpty) continue;

      // Curved metric: edge weight attenuated by √(r_a · r_b). Both
      // factors already clamped to [0.5, 1.0] in `curvatures`, so the
      // scaling stays in that range — edges never boost past their
      // Born value, only proportionally attenuate.
      final curvA = curvatures[i];
      final scored = <_EdgeCandidate>[];
      for (final j in candidates) {
        final b = nodePaths[j];

        // Inline SP observe — uses cached pathSegments. Identical
        // semantics to _SpAxis.observe, but avoids two `.split('/')`
        // allocations per edge (~candidates × N per build).
        final segB = pathSegments[j];
        final maxLen = segA.length > segB.length ? segA.length : segB.length;
        AxisObs spObs;
        if (maxLen == 0) {
          spObs = AxisObs.silent;
        } else {
          final limit =
              (segA.length < segB.length ? segA.length : segB.length) - 1;
          var shared = 0;
          for (var k = 0; k < limit; k++) {
            if (segA[k] == segB[k]) {
              shared++;
            } else {
              break;
            }
          }
          spObs = AxisObs((shared + 0.5) / (maxLen + 1.0), maxLen);
        }

        obsBuf[0] = f0Obs[j];
        obsBuf[1] = cc.observe(a, b);
        obsBuf[2] = spObs;
        obsBuf[3] = v.observe(a, b);
        if (en != null) {
          obsBuf[4] = en.observeIds(i, j);
        }
        var p = mixer.mix(obsBuf);
        p *= math.sqrt(curvA * curvatures[j]);
        p *= math.sqrt(integrityA * (stats.integrityByPath[b] ?? 1.0)) *
            logosPairPenalty(a, b);
        if (p <= 0.5) continue; // only keep edges with positive lift
        scored.add(_EdgeCandidate(j, p));
      }

      // Top-K by p_mix — keep the graph sparse. Full sort at K=24 and
      // typical |scored| in the dozens-to-hundreds is fast enough.
      scored.sort((x, y) => y.pMix.compareTo(x.pMix));
      final k = math.min(edgeDensity, scored.length);
      final kept = scored.sublist(0, k);
      rawRows[i] = kept;
      for (final e in kept) {
        degree[i] += e.pMix;
      }
    }

    // ── Symmetrise: enforce W[i,j] = W[j,i] = max(W[i,j], W[j,i]).
    //
    // Original code did `rawRows[j].firstWhere(node==i)` per directed
    // edge — O(d) linear scan plus a second `indexWhere` on the upgrade
    // branch. With edgeDensity=24 and n=10k that's ~11M wasted compares.
    //
    // Build one int→position lookup per row up front; the symmetrise
    // pass is then O(E) point lookups + amortised O(1) row append.
    final rowIndex = List<Map<int, int>>.generate(n, (i) {
      final row = rawRows[i];
      final m = <int, int>{};
      for (var k = 0; k < row.length; k++) {
        m[row[k].node] = k;
      }
      return m;
    });
    for (var i = 0; i < n; i++) {
      final row = rawRows[i];
      for (var k = 0; k < row.length; k++) {
        final e = row[k];
        final j = e.node;
        final pos = rowIndex[j][i];
        if (pos == null) {
          rowIndex[j][i] = rawRows[j].length;
          rawRows[j].add(_EdgeCandidate(i, e.pMix));
          degree[j] += e.pMix;
        } else {
          final back = rawRows[j][pos];
          if (back.pMix < e.pMix) {
            degree[j] += e.pMix - back.pMix;
            rawRows[j][pos] = _EdgeCandidate(i, e.pMix);
          }
        }
      }
    }

    // ── Pass 2: build CSR with D^(-1/2) fused into values.
    //
    // Total edge count is known after symmetrise — allocate the typed
    // buffers once at the right size instead of two `List<int>` /
    // `List<double>` growable buffers + `Int32List.fromList` /
    // `Float64List.fromList` copies (which is the common pattern that
    // wastes 2× the edge memory transiently).
    var totalEdges = 0;
    for (var i = 0; i < n; i++) {
      totalEdges += rawRows[i].length;
    }
    final indptr = Int32List(n + 1);
    final indices = Int32List(totalEdges);
    final values = Float64List(totalEdges);
    final dInv = Float64List(n);
    for (var i = 0; i < n; i++) {
      dInv[i] = degree[i] <= 0 ? 0 : 1.0 / math.sqrt(degree[i]);
    }
    var write = 0;
    for (var i = 0; i < n; i++) {
      final row = rawRows[i]
        ..sort((x, y) => x.node.compareTo(y.node));
      final di = dInv[i];
      for (final e in row) {
        indices[write] = e.node;
        values[write] = di * e.pMix * dInv[e.node];
        write++;
      }
      indptr[i + 1] = write;
    }

    final graph = CsrGraph(
      n: n,
      indptr: indptr,
      indices: indices,
      values: values,
    );

    return LogosGit._(
      graph: graph,
      nodePaths: nodePaths,
      pathToId: pathToId,
      mixer: mixer,
      perFileMetrics: perFileMetrics,
      stats: stats,
      integrityByPath: stats.integrityByPath,
      perFileKVectors: useEngram ? perFileKVectors : null,
    );
  }

  /// Per-file curvature factor — `√(spectral radius)` of the file's
  /// AR(2) inter-touch-gap fit, clamped to [0.5, 1.0]. 1.0 when the
  /// file has no fit (insufficient history). Mirrors the local
  /// function used inside [buildFromStats] so external callers (PR
  /// shape, X-ray, etc.) can interpret the same per-file rhythm
  /// signal without re-deriving it.
  double curvature(String path) {
    final fit = perFileMetrics[path];
    if (fit == null) return 1.0;
    final r = fit.spectralRadius;
    if (!r.isFinite || r <= 0) return 1.0;
    return r.clamp(0.5, 1.0);
  }

  /// Recency-decayed touch weights — for each file with at least one
  /// commit-index in [LogosGitStats.perFileCommitIndices], the sum
  /// `Σ exp(-(N-1-i)/τ)` over the file's touch indices, where N =
  /// `stats.totalCommits` and τ = [halfLifeCommits] / ln(2). Files with
  /// zero recent activity (all touches outside the meaningful decay
  /// horizon) drop out of the map.
  /// Diffuse this through the engine to get the **field vector** — a
  /// dense φ over the coupling graph that represents "what direction is
  /// the codebase moving lately." Pass each PR's footprint cosine
  /// against this field to get its alignment ("with the field" vs
  /// "against the field").
  /// Cheap: O(Σ |perFileCommitIndices[f]|), no diffusion. Diffusion is
  /// the caller's responsibility — pass the result to
  /// [diffuseWithAttribution] with a single axis label.
  Map<String, double> recentActivityWeights({int halfLifeCommits = 30}) {
    final useSemanticClock =
        stats.semanticCommitMass > 0 && stats.perFileCommitClock.isNotEmpty;
    if (!useSemanticClock && stats.totalCommits <= 0) return const {};
    // Memoise — same engine + same halfLife = identical output. The
    // rail, lede, and PR-shape signals all call this with the default
    // halfLife per render; recomputing every frame is wasted work.
    final cached = _activityCache[halfLifeCommits];
    if (cached != null) return cached;
    final tau = halfLifeCommits / math.ln2;
    final newest = useSemanticClock
        ? stats.semanticCommitMass
        : (stats.totalCommits - 1).toDouble();
    final cutoff = halfLifeCommits * 6;
    final out = <String, double>{};
    final seriesByPath = useSemanticClock
        ? stats.perFileCommitClock
        : {
            for (final entry in stats.perFileCommitIndices.entries)
              entry.key: entry.value.map((v) => v.toDouble()).toList(),
          };
    for (final entry in seriesByPath.entries) {
      var w = 0.0;
      final v = entry.value;
      for (var k = 0; k < v.length; k++) {
        final age = newest - v[k];
        if (age < 0) continue;
        // Skip entries beyond ~6 half-lives — contribution < 1.5%.
        if (age > cutoff) continue;
        w += math.exp(-age / tau);
      }
      if (w > 0) out[entry.key] = w;
    }
    _activityCache[halfLifeCommits] = out;
    return out;
  }

  /// Memo for [recentActivityWeights] keyed by halfLifeCommits. Cap is
  /// generous (~3 distinct half-lives in flight at most across the
  /// feature surface); each entry is one map of file → weight, ~80KB
  /// for a 10k-file repo.
  final Map<int, Map<String, double>> _activityCache = {};

  /// Build a reusable diffusion basis for the given source set. The
  /// Chebyshev expansion separates cleanly into:
  ///   • basis vectors `T_k(x)·ρ`  — t-independent, computed ONCE
  ///   • scalar coefficients `c_k(t)` — the only t-dependent part
  /// So for temperature-slider UIs we compute the K+1 basis vectors
  /// once (O(K·|E|)), then per-frame just recombine at a new t
  /// (O(K·|V|) — a dozen float multiplies per node, no matvec).
  /// Returns null on empty graph / empty source set — callers should
  /// degrade gracefully (no rail, no temperature interaction).
  DiffusionBasis? buildBasis(Set<String> sourceFiles, {int K = kDefaultChebyshevK}) {
    if (graph.n == 0) return null;
    final rho = _buildRho({for (final p in sourceFiles) p: 1.0});
    if (rho == null) return null;
    // `sources` tracks ORIGINAL source paths (both graph nodes and
    // symbol-proxied new files) so downstream exclusion works on the
    // caller's intent, not on the graph-level routing.
    return _buildDiffusionBasis(
      graph: graph,
      rho: rho,
      K: K,
      sources: {
        for (final p in sourceFiles)
          if (pathToId.containsKey(p) || symbolEdges.containsKey(p)) p,
      },
    );
  }

  /// Weighted variant of [buildBasis] — sources carry impact-weights
  /// (e.g. file churn for a commit-borrow query, where a high-line-
  /// change file should inject more heat than a one-line tweak).
  /// Returns null on empty graph / no in-graph sources.
  /// Like [buildBasis], the returned [DiffusionBasis] is t-independent
  /// — `recombine(t)` evaluates at any temperature in O(K·|V|) work.
  /// For a multi-temperature distillation (e.g. blending t=0.5/1.0/2.0
  /// to capture multi-scale neighborhood structure), build the basis
  /// ONCE per source set, then recombine three times. Compared to
  /// three separate `diffuseWeighted` calls, this saves 2·K matvecs —
  /// roughly 2/3 of the per-query work.
  DiffusionBasis? buildBasisWeighted(
    Map<String, double> weights, {
    int K = kDefaultChebyshevK,
  }) {
    if (graph.n == 0 || weights.isEmpty) return null;
    final rho = _buildRho(weights);
    if (rho == null) return null;
    // Track all contributing source paths (both in-graph and
    // symbol-proxied new files) so downstream exclusion respects the
    // caller's intent regardless of the routing mechanism.
    final sources = <String>{
      for (final entry in weights.entries)
        if (entry.value > 0 &&
            (pathToId.containsKey(entry.key) ||
                symbolEdges.containsKey(entry.key)))
          entry.key,
    };
    return _buildDiffusionBasis(
        graph: graph, rho: rho, K: K, sources: sources);
  }

  /// Diffuse from the source file set. Returns every node with positive
  /// relevance, sorted descending by φ.
  /// [t] is diffusion time. Defaults to 1.0 (commit-review scope).
  ///    0.25 — "only the touched files"
  ///    1.0  — "1-hop neighbourhood"                 ← commit review
  ///    2.0  — "2-hop + semantic"                    ← code Q&A
  ///    4.0  — "wide historical"                     ← codebase nav
  ///    ∞    — "graph equilibrium"                   ← repo summary
  /// [K] controls Chebyshev truncation. 20 is enough for t ∈ [0, 10].
  /// [topK]: when non-null, returns at most this many results, using a
  /// bounded min-heap during scan — O(n log topK) instead of O(n log n)
  /// for the full sort. The result list is still sorted descending.

  /// Prune [results] to the largest prefix whose induced-subgraph coherence
  /// on the Logos graph stays at or above [minCoherence].
  /// Walks from the tail inward: if the full set is already coherent, returns
  /// [results] unchanged. Otherwise removes the weakest-φ tail nodes one by
  /// one until the remaining set clears the threshold or only one node is
  /// left. Cost: O(k·d) per pruning step where d is average graph degree —
  /// fast for the small topK result sets this is called on.
  /// This turns coherence from a post-hoc metric into an active gate: the
  /// diffusion aperture closes when heat has spread into incoherent territory.
  List<RelevanceScore> _gateByCoherence(
    List<RelevanceScore> results,
    double minCoherence,
  ) {
    if (results.length < 2) return results;
    var k = results.length;
    while (k > 1) {
      final paths = results.take(k).map((r) => r.path);
      if (coherence(paths) >= minCoherence) break;
      k--;
    }
    return k == results.length ? results : results.sublist(0, k);
  }


  /// Build and normalise a source vector ρ from [weights] (path → weight).
  /// Returns null when total injected mass is zero (nothing in the graph
  /// and no resolvable symbol proxy).
  /// For paths present in the graph: inject weight directly.
  /// For paths absent but reachable via [symbolEdges]: distribute weight
  /// across their known neighbours proportionally to symbol overlap score.
  /// This makes new/untracked files valid diffusion sources — heat enters
  /// the graph through the files they're structurally coupled to.
  Float64List? _buildRho(Map<String, double> weights) {
    final rho = Float64List(graph.n);
    var total = 0.0;
    for (final entry in weights.entries) {
      final w = entry.value;
      if (w <= 0) continue;
      final id = pathToId[entry.key];
      if (id != null) {
        rho[id] += w;
        total += w;
      } else if (symbolEdges.isNotEmpty) {
        // Unknown node — proxy through symbol-linked known neighbours.
        final neighbours = symbolEdges[entry.key];
        if (neighbours == null || neighbours.isEmpty) continue;
        for (final ne in neighbours.entries) {
          final nid = pathToId[ne.key];
          if (nid == null) continue;
          final proxied = w * ne.value;
          rho[nid] += proxied;
          total += proxied;
        }
      }
    }
    if (total <= 0) return null;
    for (var i = 0; i < graph.n; i++) {
      rho[i] /= total;
    }
    return rho;
  }

  /// Derive φ scores for paths that are not graph nodes but are reachable
  /// via [symbolEdges]. Each new path's score is the symbol-overlap-weighted
  /// mean of its known neighbours' φ values — the same interpolation used
  /// in MDS for out-of-sample points.
  /// Returns an empty map when [symbolEdges] is empty or no new paths have
  /// any known neighbour with non-zero φ.
  Map<String, double> _deriveNewPathPhi(Float64List phi) {
    if (symbolEdges.isEmpty) return const {};
    final derived = <String, double>{};
    for (final entry in symbolEdges.entries) {
      final path = entry.key;
      if (pathToId.containsKey(path)) continue; // already a node
      var weightedSum = 0.0;
      var totalWeight = 0.0;
      for (final ne in entry.value.entries) {
        final nid = pathToId[ne.key];
        if (nid == null) continue;
        weightedSum += ne.value * phi[nid];
        totalWeight += ne.value;
      }
      if (totalWeight > 0) derived[path] = weightedSum / totalWeight;
    }
    return derived;
  }


  /// [phiThreshold]: when non-zero, drops sub-threshold φ values during
  /// scan (kills numerical-noise allocations on warm diffusions where
  /// thousands of nodes carry near-zero positive φ).
  List<RelevanceScore> diffuse(
    Set<String> sourceFiles, {
    double t = 1.0,
    int K = kDefaultChebyshevK,
    int? topK,
    double phiThreshold = 0.0,
    // When set, the result is pruned to the largest prefix whose induced
    // coherence on the Logos graph stays ≥ this value. Prevents diffusion
    // from surfacing files that are incoherent with the source cluster.
    // null = no gate (default). Good default for commit reranking: 0.25.
    double? coherenceGate,
  }) {
    if (graph.n == 0) return const [];
    final rho = _buildRho({for (final p in sourceFiles) p: 1.0});
    if (rho == null) return const [];

    final phi = Float64List(graph.n);
    chebyshevDiffuse(graph: graph, rho: rho, phi: phi, t: t, K: K);

    var results = _packTopPhi(
      phi: phi,
      excludePaths: sourceFiles,
      topK: topK,
      phiThreshold: phiThreshold,
    );

    final derived = _deriveNewPathPhi(phi);
    if (derived.isNotEmpty) {
      final extras = [
        for (final e in derived.entries)
          if (!sourceFiles.contains(e.key) && e.value > phiThreshold)
            RelevanceScore(e.key, e.value),
      ];
      if (extras.isNotEmpty) {
        results = ([...results, ...extras]
          ..sort((a, b) => b.phi.compareTo(a.phi)));
      }
    }

    if (coherenceGate != null) {
      results = _gateByCoherence(results, coherenceGate);
    }
    return results;
  }

  /// Diffuse from a WEIGHTED source map — the correct path for
  /// probe-based queries where different observables (primary, M-axis,
  /// Ab-axis) carry different starting amplitudes.
  /// Heat kernel is linear in ρ, so callers used to sum N unit-mass
  /// diffusions scaled by their weight. That's mathematically fine but
  /// wastes O(N) matvec passes per review. This method builds a single
  /// properly-weighted ρ and runs one Chebyshev expansion.
  /// `excludePaths` is filtered from the returned list — typically the
  /// diff's primary paths, which callers don't want surfaced back.
  /// Returns empty when the graph is empty, weights are empty, or every
  /// weighted entry misses the graph.
  List<RelevanceScore> diffuseWeighted(
    Map<String, double> weights, {
    double t = 1.0,
    int K = kDefaultChebyshevK,
    Set<String> excludePaths = const {},
    int? topK,
    double phiThreshold = 0.0,
    double? coherenceGate,
  }) {
    if (graph.n == 0 || weights.isEmpty) return const [];
    final rho = _buildRho(weights);
    if (rho == null) return const [];

    final phi = Float64List(graph.n);
    chebyshevDiffuse(graph: graph, rho: rho, phi: phi, t: t, K: K);

    var results = _packTopPhi(
      phi: phi,
      excludePaths: excludePaths,
      topK: topK,
      phiThreshold: phiThreshold,
    );

    final derived = _deriveNewPathPhi(phi);
    if (derived.isNotEmpty) {
      final extras = [
        for (final e in derived.entries)
          if (!excludePaths.contains(e.key) && e.value > phiThreshold)
            RelevanceScore(e.key, e.value),
      ];
      if (extras.isNotEmpty) {
        results = ([...results, ...extras]
          ..sort((a, b) => b.phi.compareTo(a.phi)));
      }
    }

    if (coherenceGate != null) {
      results = _gateByCoherence(results, coherenceGate);
    }
    return results;
  }

  /// Pack a φ vector into a sorted-descending list of [RelevanceScore],
  /// optionally bounded by [topK] (using a bounded min-heap so the scan
  /// cost is O(n log topK) instead of O(n log n)) and pre-filtered by
  /// [phiThreshold] to drop near-zero-noise nodes before allocation.
  /// Used by both [diffuse] and [diffuseWeighted].
  List<RelevanceScore> _packTopPhi({
    required Float64List phi,
    required Set<String> excludePaths,
    required int? topK,
    required double phiThreshold,
  }) {
    if (topK != null && topK > 0) {
      // Bounded min-heap of size ≤ topK. We keep the SMALLEST element
      // at the heap root; when a new candidate beats it, replace and
      // sift down. At end, drain into a list and reverse for descending
      // order. Heap is a flat List backed by a 2i+1 / 2i+2 layout.
      final heap = <RelevanceScore>[];
      for (var i = 0; i < graph.n; i++) {
        final val = phi[i];
        if (val <= phiThreshold) continue;
        final p = nodePaths[i];
        if (excludePaths.contains(p)) continue;
        if (heap.length < topK) {
          heap.add(RelevanceScore(p, val));
          _heapSiftUp(heap, heap.length - 1);
        } else if (val > heap[0].phi) {
          heap[0] = RelevanceScore(p, val);
          _heapSiftDown(heap, 0);
        }
      }
      // Sort the heap descending — only `topK` elements, cheap.
      heap.sort((a, b) => b.phi.compareTo(a.phi));
      return heap;
    }
    // Unbounded path — full sort. Same as the original behaviour.
    final results = <RelevanceScore>[];
    for (var i = 0; i < graph.n; i++) {
      final val = phi[i];
      if (val <= phiThreshold) continue;
      final p = nodePaths[i];
      if (excludePaths.contains(p)) continue;
      results.add(RelevanceScore(p, val));
    }
    results.sort((a, b) => b.phi.compareTo(a.phi));
    return results;
  }

  /// Diffuses [sourceWeights] through the file graph and projects the
  /// resulting φ through [fileTokenCounts] (file → token → count) to
  /// produce an expected-token distribution:
  ///     expected(t) = Σ_f φ(f) · P(t | f)
  ///     P(t | f)    = fileTokenCounts[f][t] / Σ_{t'} fileTokenCounts[f][t']
  /// Callers typically compare this against an observed distribution
  /// with `log((observed + ε) / (expected + ε))` to score surprise.
  /// Returned values aren't normalised; divide by sum for probabilities.
  Map<String, double> projectTokenDistribution({
    required Map<String, double> sourceWeights,
    required Map<String, Map<String, double>> fileTokenCounts,
    double t = 1.0,
    int K = kDefaultChebyshevK,
  }) {
    if (graph.n == 0 || sourceWeights.isEmpty || fileTokenCounts.isEmpty) {
      return const {};
    }
    final rho = _buildRho(sourceWeights);
    if (rho == null) return const {};

    final phi = Float64List(graph.n);
    chebyshevDiffuse(graph: graph, rho: rho, phi: phi, t: t, K: K);

    final expected = <String, double>{};
    for (var i = 0; i < graph.n; i++) {
      final fi = phi[i];
      if (fi <= 0) continue;
      final path = nodePaths[i];
      final tokenCounts = fileTokenCounts[path];
      if (tokenCounts == null || tokenCounts.isEmpty) continue;
      var fileTotal = 0.0;
      for (final c in tokenCounts.values) {
        fileTotal += c;
      }
      if (fileTotal <= 0) continue;
      final inv = 1.0 / fileTotal;
      for (final entry in tokenCounts.entries) {
        final contribution = fi * entry.value * inv;
        expected.update(
          entry.key,
          (v) => v + contribution,
          ifAbsent: () => contribution,
        );
      }
    }
    return expected;
  }

  /// **Born overlap** — the Logos-native inner product between two
  /// probes' diffused fields. Measures how much they interfere on the
  /// manifold: near 1 = they cover overlapping territory; near 0 =
  /// disjoint neighbourhoods.
  ///   I(ρ_a, ρ_b; t) = Σ_v √(φ_a(v) · φ_b(v))
  /// The √ is the Born amplitude — same operation `BornMixer.mix` uses
  /// to compose axis distributions. Cosine / dot products would also
  /// give an "overlap" number, but Born overlap is the coherent-sum
  /// amplitude the rest of the codec operates in. Use this for:
  ///   - cross-PR merge-collision prediction ("these two PRs touch the
  ///     same semantic region")
  ///   - cross-branch ghost-conflict detection
  ///   - diff-pair similarity that respects multi-axis topology
  /// Null on empty weights either side. Both weight maps are normalised
  /// to unit mass before diffusion (same convention as [diffuseWeighted]).
  double? bornOverlap(
    Map<String, double> weightsA,
    Map<String, double> weightsB, {
    double t = 1.5,
    int K = kDefaultChebyshevK,
  }) {
    if (graph.n == 0) return null;
    final phiA = _phiFromWeights(weightsA, t, K);
    final phiB = _phiFromWeights(weightsB, t, K);
    if (phiA == null || phiB == null) return null;

    // Born overlap: Σ √(a·b) for non-negative a, b. Equivalent to
    // the Bhattacharyya coefficient when a, b are probability
    // distributions. With our unit-normalised φ vectors the value is
    // bounded by 1 (equality iff identical distributions).
    var sum = 0.0;
    for (var i = 0; i < graph.n; i++) {
      final a = phiA[i];
      final b = phiB[i];
      if (a <= 0 || b <= 0) continue;
      sum += math.sqrt(a * b);
    }
    return sum;
  }

  /// Helper: build φ from weight map at temperature t. Returns null on
  /// empty / all-unknown weights. Used by [bornOverlap] and available
  /// for any future multi-probe primitive.
  Float64List? _phiFromWeights(
    Map<String, double> weights,
    double t,
    int K,
  ) {
    if (weights.isEmpty) return null;
    final rho = _buildRho(weights);
    if (rho == null) return null;
    final phi = Float64List(graph.n);
    chebyshevDiffuse(graph: graph, rho: rho, phi: phi, t: t, K: K);
    return phi;
  }

  LogosEvidenceQueryResult? gatherEvidence({
    required Map<String, double> focusWeights,
    Map<String, String> axisLabelByPath = const {},
    double t = 1.0,
    int K = kDefaultChebyshevK,
    int ambientHalfLifeCommits = 30,
    double lambda = 0.5,
    Set<String> excludePaths = const {},
    int? topK,
    double phiThreshold = 0.0,
  }) {
    if (graph.n == 0 || focusWeights.isEmpty) return null;
    final focusRho = _buildRho(focusWeights);
    if (focusRho == null) return null;

    final ambientWeights =
        recentActivityWeights(halfLifeCommits: ambientHalfLifeCommits);
    final ambientRho = ambientWeights.isEmpty ? null : _buildRho(ambientWeights);
    final supportAttribution = diffuseWithAttribution(
      weightsByPath: focusWeights,
      axisLabelByPath: axisLabelByPath,
      t: t,
      K: K,
      excludePaths: excludePaths,
    );

    final batchWidth = ambientRho == null ? 1 : 2;
    final rhoBatch = Float64List(graph.n * batchWidth);
    for (var i = 0; i < graph.n; i++) {
      final base = i * batchWidth;
      rhoBatch[base] = focusRho[i];
      if (ambientRho != null) {
        rhoBatch[base + 1] = ambientRho[i];
      }
    }

    final phiBatch = chebyshevDiffuseBatch(
      graph: graph,
      rhoBatch: rhoBatch,
      B: batchWidth,
      t: t,
      K: K,
    );
    final focusPhi = Float64List(graph.n);
    final ambientPhi = Float64List(graph.n);
    for (var i = 0; i < graph.n; i++) {
      final base = i * batchWidth;
      focusPhi[i] = phiBatch[base];
      if (ambientRho != null) {
        ambientPhi[i] = phiBatch[base + 1];
      }
    }

    var focusMass = 0.0;
    var ambientMass = 0.0;
    for (var i = 0; i < graph.n; i++) {
      if (focusPhi[i] > 0) focusMass += focusPhi[i];
      if (ambientPhi[i] > 0) ambientMass += ambientPhi[i];
    }

    final focusDerived = _deriveNewPathPhi(focusPhi);
    final ambientDerived = ambientRho == null
        ? const <String, double>{}
        : _deriveNewPathPhi(ambientPhi);
    final focusPaths = <String>{
      for (final entry in focusWeights.entries)
        if (entry.value > 0) entry.key,
    };

    final ranked = <LogosEvidenceScore>[];
    for (var i = 0; i < graph.n; i++) {
      final path = nodePaths[i];
      if (excludePaths.contains(path)) continue;
      final support =
          focusMass > 0 && focusPhi[i] > 0 ? focusPhi[i] / focusMass : 0.0;
      final ambient = ambientMass > 0 && ambientPhi[i] > 0
          ? ambientPhi[i] / ambientMass
          : 0.0;
      if (support <= phiThreshold && ambient <= phiThreshold) continue;
      final rawSurplus = support - lambda * ambient;
      final surplus = rawSurplus > 0 ? rawSurplus : 0.0;
      final integrity = integrityByPath[path] ?? kNeutralIntegrity;
      final rescue = _witnessRescueScore(path, focusPaths, support, integrity);
      ranked.add(LogosEvidenceScore(
        path: path,
        support: support,
        ambient: ambient,
        rawSurplus: rawSurplus,
        surplus: surplus,
        integrity: integrity,
        utility: math.max(surplus * integrity, rescue),
        dominantAxis: supportAttribution?.dominantAxis[path],
        axisShares: supportAttribution?.shareByAxis[path],
      ));
    }

    for (final entry in focusDerived.entries) {
      final path = entry.key;
      if (excludePaths.contains(path)) continue;
      final support =
          focusMass > 0 && entry.value > 0 ? entry.value / focusMass : 0.0;
      final ambientRaw = ambientDerived[path] ?? 0.0;
      final ambient =
          ambientMass > 0 && ambientRaw > 0 ? ambientRaw / ambientMass : 0.0;
      if (support <= phiThreshold && ambient <= phiThreshold) continue;
      final rawSurplus = support - lambda * ambient;
      final surplus = rawSurplus > 0 ? rawSurplus : 0.0;
      final integrity = integrityByPath[path] ?? kNeutralIntegrity;
      final rescue = _witnessRescueScore(path, focusPaths, support, integrity);
      ranked.add(LogosEvidenceScore(
        path: path,
        support: support,
        ambient: ambient,
        rawSurplus: rawSurplus,
        surplus: surplus,
        integrity: integrity,
        utility: math.max(surplus * integrity, rescue),
      ));
    }

    ranked.sort((a, b) {
      final byUtility = b.utility.compareTo(a.utility);
      if (byUtility != 0) return byUtility;
      final bySupport = b.support.compareTo(a.support);
      if (bySupport != 0) return bySupport;
      return a.path.compareTo(b.path);
    });
    final limited = topK != null && topK > 0 && ranked.length > topK
        ? ranked.sublist(0, topK)
        : ranked;
    final coherenceScore =
        limited.isEmpty ? 1.0 : coherence(limited.take(12).map((r) => r.path));
    final stability = diffuseStability(focusWeights, t: t);
    final sourceAlignment = ambientWeights.isEmpty
        ? null
        : bornOverlap(focusWeights, ambientWeights, t: t, K: K);
    final fieldAlignment = ambientRho == null
        ? null
        : _bornOverlapFromPhi(
            focusPhi,
            ambientPhi,
            focusMass: focusMass,
            ambientMass: ambientMass,
          );

    return LogosEvidenceQueryResult(
      ranked: limited,
      sourceAlignment: sourceAlignment,
      fieldAlignment: fieldAlignment,
      sourceSurprise:
          sourceAlignment == null
              ? null
              : (1.0 - sourceAlignment).clamp(0.0, 1.0).toDouble(),
      fieldSurprise:
          fieldAlignment == null
              ? null
              : (1.0 - fieldAlignment).clamp(0.0, 1.0).toDouble(),
      coherence: coherenceScore,
      stability: stability,
      supportAttribution: supportAttribution,
    );
  }

  double _bornOverlapFromPhi(
    Float64List a,
    Float64List b, {
    required double focusMass,
    required double ambientMass,
  }) {
    if (focusMass <= 0 || ambientMass <= 0) return 0.0;
    var sum = 0.0;
    for (var i = 0; i < graph.n; i++) {
      final av = a[i];
      final bv = b[i];
      if (av <= 0 || bv <= 0) continue;
      sum += math.sqrt((av / focusMass) * (bv / ambientMass));
    }
    return sum;
  }

  double _witnessRescueScore(
    String candidate,
    Set<String> focusPaths,
    double support,
    double integrity,
  ) {
    var bestPrivilege = 0.0;
    for (final focus in focusPaths) {
      final privilege = logosWitnessPrivilege(focus, candidate);
      if (privilege > bestPrivilege) bestPrivilege = privilege;
    }
    if (bestPrivilege <= 0 || support <= 0) return 0.0;
    return support * bestPrivilege * math.max(integrity, 0.35);
  }

  /// **Stability of a diffusion query** — returns a [0, 1] score where
  /// 1.0 means "tiny perturbations to the source weights don't change
  /// the top-K ranking at all" and 0 means "one dropped source and the
  /// answer is entirely different." Novel Logos-spirited confidence
  /// signal: the same machinery that produces an answer produces its
  /// own self-consistency score, so downstream code can abstain rather
  /// than act on knife-edge rankings.
  /// Algorithm: run [nTrials] diffusions, each with source weights
  /// multiplicatively perturbed by ±[epsilon] (deterministic seed).
  /// Stability = mean pairwise Jaccard overlap of their top-[topK]
  /// sets against the unperturbed top-K.
  /// Returns 1.0 on degenerate inputs (empty graph, single source, K=0)
  /// — no perturbation can change a single-element ranking, so it's
  /// trivially stable.
  double diffuseStability(
    Map<String, double> weights, {
    double t = 1.0,
    int topK = _defaultTopK,
    int nTrials = _defaultStabilityTrials,
    double epsilon = _defaultStabilityEpsilon,
    int seed = _defaultStabilitySeed,
  }) {
    if (graph.n == 0 || weights.isEmpty || topK <= 0) return 1.0;
    final baseline = diffuseWeighted(weights, t: t);
    if (baseline.length <= 1) return 1.0;
    final baseSet = baseline
        .take(topK)
        .map((s) => s.path)
        .toSet();
    if (baseSet.isEmpty) return 1.0;

    final rng = math.Random(seed);
    var overlapAcc = 0.0;
    var trialsRun = 0;
    for (var trial = 0; trial < nTrials; trial++) {
      final perturbed = <String, double>{};
      for (final entry in weights.entries) {
        // Multiplicative jitter in [1-ε, 1+ε]. Preserves the sign of the
        // weight and never flips a non-zero source to zero (entropy-
        // preserving perturbation, Logos-style).
        final jitter = 1.0 + (rng.nextDouble() * 2 - 1) * epsilon;
        perturbed[entry.key] = entry.value * jitter;
      }
      final trialScores = diffuseWeighted(perturbed, t: t);
      if (trialScores.isEmpty) continue;
      final trialSet = trialScores
          .take(topK)
          .map((s) => s.path)
          .toSet();
      if (trialSet.isEmpty) continue;
      // Jaccard overlap between the perturbed top-K and the baseline
      // top-K: |A∩B| / |A∪B|.
      final inter = baseSet.intersection(trialSet).length;
      final union = baseSet.union(trialSet).length;
      if (union > 0) {
        overlapAcc += inter / union;
        trialsRun++;
      }
    }
    if (trialsRun == 0) return 0.0;
    return overlapAcc / trialsRun;
  }

  /// Estimated spectral radius of the engine's normalised Laplacian.
  /// Diagnostic — should always be ≤ 2 by construction. A larger value
  /// signals numerical drift or an asymmetric weight bug worth chasing.
  double estimateSpectralRadius({int iterations = kDefaultPowerIterations}) =>
      graph.estimateSpectralRadius(iterations: iterations);

  /// **Per-source attribution diffusion** — runs Chebyshev expansion
  /// once per axis bucket and returns φ vectors keyed by axis. Heat
  /// kernel is linear in ρ, so the combined φ equals the sum of per-
  /// axis φ. Use this to answer "*why* did file X surface as relevant?"
  /// — by reading the dominant axis bucket per result.
  /// `weightsByPath` carries the source amplitudes; `axisLabelByPath`
  /// assigns each path to a bucket label. Paths not in [pathToId] are
  /// silently dropped (out-of-graph). Paths with weight ≤ 0 are dropped.
  /// Returns null if no source contributes.
  AxisAttribution? diffuseWithAttribution({
    required Map<String, double> weightsByPath,
    required Map<String, String> axisLabelByPath,
    double t = 1.0,
    int K = kDefaultChebyshevK,
    Set<String> excludePaths = const {},
    // When set, the combined result is pruned so every included path
    // keeps the induced-subgraph coherence ≥ this value. Per-axis φ
    // vectors are not pruned (callers that want them can apply the
    // same gate themselves). Mirrors the behaviour in [diffuse].
    double? coherenceGate,
  }) {
    if (graph.n == 0 || weightsByPath.isEmpty) return null;

    // Symbol-axis routing: a source path absent from the graph but
    // present in [symbolEdges] is proxied through its known neighbours,
    // with the proxied mass attributed to the `symbol` axis regardless
    // of the caller's label. This keeps attribution math consistent with
    // _buildRho and surfaces new-file contributions in per-axis φ.
    final symbolAxisLabel = LogosAxis.symbol.name;

    // Bucket per axis, applying global mass normalisation up front so
    // per-axis φ vectors sum to combined φ. Two-pass structure: first
    // compute totalMass including any proxied mass, then populate rho.
    double resolveMass(String path, double weight) {
      if (pathToId.containsKey(path)) return weight;
      final neighbours = symbolEdges[path];
      if (neighbours == null || neighbours.isEmpty) return 0.0;
      var m = 0.0;
      for (final ne in neighbours.entries) {
        if (pathToId.containsKey(ne.key)) m += weight * ne.value;
      }
      return m;
    }

    var totalMass = 0.0;
    for (final entry in weightsByPath.entries) {
      final w = entry.value;
      if (w <= 0) continue;
      totalMass += resolveMass(entry.key, w);
    }
    if (totalMass <= 0) return null;

    final perAxisRaw = <String, Float64List>{};
    for (final entry in weightsByPath.entries) {
      final w = entry.value;
      if (w <= 0) continue;
      final path = entry.key;
      final id = pathToId[path];
      if (id != null) {
        final axis = axisLabelByPath[path] ?? '_default';
        final rho = perAxisRaw.putIfAbsent(axis, () => Float64List(graph.n));
        rho[id] += w / totalMass;
      } else {
        // Unknown path — proxy through symbol neighbours under the
        // symbol axis label (the real mechanism that surfaced the heat).
        final neighbours = symbolEdges[path];
        if (neighbours == null || neighbours.isEmpty) continue;
        final rho = perAxisRaw.putIfAbsent(
          symbolAxisLabel,
          () => Float64List(graph.n),
        );
        for (final ne in neighbours.entries) {
          final nid = pathToId[ne.key];
          if (nid == null) continue;
          rho[nid] += (w * ne.value) / totalMass;
        }
      }
    }

    // Batch all axes into one Chebyshev pass. AoSoA-pack the per-axis
    // rho vectors so the graph traversal services every axis
    // simultaneously — graph memory bandwidth (the SpMV bottleneck)
    // scales O(K·|E|) instead of O(B·K·|E|). Split back into per-axis
    // φ after.
    final axisOrder = perAxisRaw.keys.toList(growable: false);
    final B = axisOrder.length;
    final perAxisPhi = <String, Float64List>{};
    if (B == 1) {
      // Single axis — skip the packing overhead, run the scalar path.
      final phi = Float64List(graph.n);
      chebyshevDiffuse(
        graph: graph,
        rho: perAxisRaw[axisOrder[0]]!,
        phi: phi,
        t: t,
        K: K,
      );
      perAxisPhi[axisOrder[0]] = phi;
    } else {
      final rhoBatch = Float64List(graph.n * B);
      for (var b = 0; b < B; b++) {
        final axisRho = perAxisRaw[axisOrder[b]]!;
        for (var i = 0; i < graph.n; i++) {
          rhoBatch[i * B + b] = axisRho[i];
        }
      }
      final phiBatch = chebyshevDiffuseBatch(
        graph: graph,
        rhoBatch: rhoBatch,
        B: B,
        t: t,
        K: K,
      );
      for (var b = 0; b < B; b++) {
        final phi = Float64List(graph.n);
        for (var i = 0; i < graph.n; i++) {
          phi[i] = phiBatch[i * B + b];
        }
        perAxisPhi[axisOrder[b]] = phi;
      }
    }

    // Combined = elementwise sum (heat kernel linearity).
    final combinedPhi = Float64List(graph.n);
    for (final phi in perAxisPhi.values) {
      for (var i = 0; i < graph.n; i++) {
        combinedPhi[i] += phi[i];
      }
    }

    // Materialise sorted scores for combined; per-axis returned as raw
    // φ so callers can compose / threshold themselves.
    final combined = <RelevanceScore>[];
    final dominantAxis = <String, String>{};
    final shareByAxis = <String, Map<String, double>>{};
    for (var i = 0; i < graph.n; i++) {
      final path = nodePaths[i];
      if (excludePaths.contains(path)) continue;
      final v = combinedPhi[i];
      if (v <= 0) continue;
      combined.add(RelevanceScore(path, v));
      // Per-node attribution: which axis contributed most? And what
      // share of the node's φ came from each axis?
      var bestAxis = '';
      var bestVal = -1.0;
      final shares = <String, double>{};
      for (final entry in perAxisPhi.entries) {
        final ap = entry.value[i];
        if (ap <= 0) continue;
        final share = ap / v;
        shares[entry.key] = share;
        if (ap > bestVal) {
          bestVal = ap;
          bestAxis = entry.key;
        }
      }
      if (bestAxis.isNotEmpty) dominantAxis[path] = bestAxis;
      if (shares.isNotEmpty) shareByAxis[path] = shares;
    }

    // Derived φ for new / symbol-coupled paths not in the graph — same
    // interpolation as `_deriveNewPathPhi` but applied to combinedPhi.
    // Attribution for these paths is wholly the symbol axis: they exist
    // only because the symbol-overlap axis surfaced them, so their
    // dominantAxis and full share (1.0) go to `LogosAxis.symbol.name`.
    final derived = _deriveNewPathPhi(combinedPhi);
    if (derived.isNotEmpty) {
      for (final e in derived.entries) {
        if (excludePaths.contains(e.key)) continue;
        if (e.value <= 0) continue;
        combined.add(RelevanceScore(e.key, e.value));
        dominantAxis[e.key] = symbolAxisLabel;
        shareByAxis[e.key] = {symbolAxisLabel: 1.0};
      }
    }

    combined.sort((x, y) => y.phi.compareTo(x.phi));

    // Apply coherence gate to combined if requested. Only combined is
    // gated — per-axis φ is preserved for callers that need the raw
    // per-axis breakdown across the full graph.
    var gatedCombined = combined;
    if (coherenceGate != null) {
      gatedCombined = _gateByCoherence(combined, coherenceGate);
    }

    return AxisAttribution(
      combined: gatedCombined,
      perAxisPhi: perAxisPhi,
      nodePaths: nodePaths,
      dominantAxis: dominantAxis,
      shareByAxis: shareByAxis,
    );
  }

  /// Multi-axis *coherence* of a path set — the mean pairwise relevance
  /// under the full Born-mixed metric. Replaces the single-axis
  /// `FileCouplingMatrix.coherenceFor(paths)` with a metric that
  /// considers frequency, coupling, proximity, and volatility together.
  /// Returns 1.0 for ≤1 known paths (nothing to compare).
  /// Returns in [0, 1] where higher = tighter semantic grouping.
  /// Used by the branches page to score PR "focus" — a high coherence
  /// means the PR touches files that historically belong together; low
  /// means a scattered sweep.
  double coherence(Iterable<String> paths) {
    // Dedup (coherence is a property of a set) and filter to known ids.
    // `knownIdx[nodeId]` gives the position in the subset — used both
    // as a membership test (via `null` check) and as an ordering key
    // so each induced-subgraph edge is counted exactly once.
    final knownIdx = <int, int>{};
    for (final p in paths) {
      final id = pathToId[p];
      if (id == null || knownIdx.containsKey(id)) continue;
      knownIdx[id] = knownIdx.length;
    }
    final k = knownIdx.length;
    if (k < 2) return 1.0;
    // Single pass: for each subset node, scan its CSR row and
    // accumulate weights for edges landing on *other* subset nodes
    // with a higher subset-index. The index-order guard visits every
    // induced edge exactly once on symmetric graphs, matching the old
    // nested i<j enumeration without rescanning rows per partner.
    //
    // Cost: O(k · avg_degree) — no pair loop, no per-pair row search.
    // The previous linear-scan-per-pair implementation was O(k²·degree).
    var sum = 0.0;
    knownIdx.forEach((ia, i) {
      final aEnd = graph.indptr[ia + 1];
      for (var e = graph.indptr[ia]; e < aEnd; e++) {
        final jIdx = knownIdx[graph.indices[e]];
        if (jIdx != null && jIdx > i) sum += graph.values[e];
      }
    });
    // The weight is the D^{-1/2}-normalised p_mix; ranking/averaging
    // is preserved by either form. Total pairs is combinatoric —
    // non-edges contribute 0 and pull the mean toward "scattered".
    final pairs = k * (k - 1) ~/ 2;
    return (sum / pairs).clamp(0.0, 1.0);
  }

  /// Rank all known paths by relevance to [seed]. Returns the top
  /// [limit] most-relevant paths (excluding the seed itself).
  /// Convenience wrapper over [diffuse] for single-file queries —
  /// "show me things related to this file."
  List<RelevanceScore> relatedTo(
    String seed, {
    double t = 1.0,
    int limit = 20,
  }) {
    // Seed may be a graph node OR a new/untracked file with symbol edges.
    // In either case, `diffuse` via `_buildRho` routes heat correctly.
    // Only bail when neither path exists — nothing to diffuse from.
    final hasSeed = pathToId.containsKey(seed) ||
        (symbolEdges[seed]?.isNotEmpty ?? false);
    if (!hasSeed) return const [];
    final scores = diffuse({seed}, t: t);
    if (scores.length <= limit) return scores;
    return scores.sublist(0, limit);
  }

  /// Select an emission plan from relevance scores within [budget]
  /// tokens. Greedy density knapsack with a single-pass swap. Tiers:
  ///   FULL        — avg 1600 tokens, info 1.0
  ///   SIGNATURE   —        300              0.45
  ///   BREADCRUMB  —         60              0.12
  /// These numbers are deliberately conservative defaults; Phase 2 will
  /// learn them from audit-log citations.
  List<EmissionPlan> plan(
    List<RelevanceScore> scored, {
    int budget = 60000,
  }) {
    const tierCost = <EmissionTier, int>{
      EmissionTier.full: 1600,
      EmissionTier.signature: 300,
      EmissionTier.breadcrumb: 60,
    };
    const tierInfo = <EmissionTier, double>{
      EmissionTier.full: 1.0,
      EmissionTier.signature: 0.45,
      EmissionTier.breadcrumb: 0.12,
    };

    // Expand each score into three candidate tiers and rank by density
    // (info / cost). The density metric is Lagrangian — we're solving a
    // knapsack so density greedy is ~(1-1/e)-optimal.
    final candidates = <_TierCandidate>[];
    for (final s in scored) {
      for (final t in EmissionTier.values) {
        final cost = tierCost[t]!;
        final info = s.phi * tierInfo[t]!;
        candidates.add(_TierCandidate(s.path, s.phi, t, cost, info));
      }
    }
    candidates.sort((a, b) => b.density.compareTo(a.density));

    final selected = <String, EmissionPlan>{};
    var remaining = budget;
    for (final c in candidates) {
      if (selected.containsKey(c.path)) continue; // one tier per path
      if (c.cost > remaining) continue;
      selected[c.path] = EmissionPlan(c.path, c.phi, c.tier);
      remaining -= c.cost;
    }

    return selected.values.toList()
      ..sort((a, b) => b.phi.compareTo(a.phi));
  }
}

/// Result of [LogosGit.diffuseWithAttribution]. Carries the combined
/// φ field (summed across axes — exactly what plain `diffuseWeighted`
/// would have returned), plus per-axis φ vectors and per-node provenance.
/// Use [combined] for ranking emissions and [dominantAxis] / [shareByAxis]
/// for explaining why a result surfaced. Intended consumers: the
/// `<logos_shape>` block in AI prompts, the X-Ray UI's "why this file"
/// disclosure, and SSE feedback that wants per-axis precision.
class AxisAttribution {
  final List<RelevanceScore> combined;
  final Map<String, Float64List> perAxisPhi;
  /// id-to-path lookup matching the engine's internal node ordering
  /// (so consumers can index per-axis vectors without re-deriving it).
  final List<String> nodePaths;
  /// path → label of the axis that contributed the most φ at that node.
  final Map<String, String> dominantAxis;
  /// path → axis-label → fraction of φ contributed by that axis (sums
  /// to 1 per path, modulo silent axes which omit their entry).
  final Map<String, Map<String, double>> shareByAxis;

  const AxisAttribution({
    required this.combined,
    required this.perAxisPhi,
    required this.nodePaths,
    required this.dominantAxis,
    required this.shareByAxis,
  });

  /// Sum of φ contributed by [axisLabel] across all nodes. Useful for
  /// "this axis carried 38% of the total mass."
  double totalMassFor(String axisLabel) {
    final phi = perAxisPhi[axisLabel];
    if (phi == null) return 0;
    var s = 0.0;
    for (var i = 0; i < phi.length; i++) {
      s += phi[i];
    }
    return s;
  }

  /// Map of axis label → fractional total mass. Sums to 1.
  Map<String, double> axisMassFractions() {
    final raw = <String, double>{};
    var total = 0.0;
    for (final entry in perAxisPhi.entries) {
      final m = totalMassFor(entry.key);
      raw[entry.key] = m;
      total += m;
    }
    if (total <= 0) return raw;
    return raw.map((k, v) => MapEntry(k, v / total));
  }
}

class _EdgeCandidate {
  final int node;
  final double pMix;
  const _EdgeCandidate(this.node, this.pMix);
}

class _TierCandidate {
  final String path;
  final double phi;
  final EmissionTier tier;
  final int cost;
  final double info;
  const _TierCandidate(this.path, this.phi, this.tier, this.cost, this.info);
  double get density => info / cost;
}

// `_parentDir` removed — the build loop now precomputes parent
// directories via `dirIndex` directly off the cached `pathSegments`.

// ── Tiny binary min-heap on `List<RelevanceScore>` keyed by .phi.
//
// Used for bounded top-K extraction in `_packTopPhi`: scan O(n) nodes,
// per-node cost O(log topK) instead of growing an unbounded list and
// O(n log n) sorting at the end. For typical (n=10000, topK=24..200)
// this is a 2–3× speed-up and cuts allocations from O(n) to O(topK).
//
// Layout is the standard array-as-tree: parent(i) = (i-1)>>1,
// left(i) = 2i+1, right(i) = 2i+2. Min at index 0.
void _heapSiftUp(List<RelevanceScore> heap, int i) {
  while (i > 0) {
    final parent = (i - 1) >> 1;
    if (heap[i].phi < heap[parent].phi) {
      final tmp = heap[i];
      heap[i] = heap[parent];
      heap[parent] = tmp;
      i = parent;
    } else {
      break;
    }
  }
}

void _heapSiftDown(List<RelevanceScore> heap, int i) {
  final n = heap.length;
  while (true) {
    final l = 2 * i + 1;
    final r = 2 * i + 2;
    var smallest = i;
    if (l < n && heap[l].phi < heap[smallest].phi) smallest = l;
    if (r < n && heap[r].phi < heap[smallest].phi) smallest = r;
    if (smallest == i) break;
    final tmp = heap[i];
    heap[i] = heap[smallest];
    heap[smallest] = tmp;
    i = smallest;
  }
}

// DiffusionBasis — cached Chebyshev basis for temperature-slider UIs.
//
// The heat kernel φ(t) = exp(-t·L)·ρ factors into
//
//   φ(t) = Σ_{k=0..K} c_k(t) · (T_k(x) · ρ)
//
// where the `T_k(x)·ρ` vectors are INDEPENDENT of t. Precompute them
// once (O(K·|E|)) and every subsequent "move the slider" is a simple
// weighted sum: O(K·|V|), ~10µs for 5k nodes on a modern CPU.
//
// Exposed on the engine as `engine.buildBasis(sources)`. UI code holds
// the basis as long as the source set is stable and calls
// `basis.recombine(t)` per frame.

class DiffusionBasis {
  final int n;
  final int K;
  /// Basis vectors stored as a row-major f64 matrix of shape (K+1, n).
  /// basis[k * n + i] = (T_k(x) · ρ)[i].
  final Float64List basis;
  /// The source paths the basis was built from — useful for UI labelling
  /// and diagnostics.
  final Set<String> sources;

  DiffusionBasis._({
    required this.n,
    required this.K,
    required this.basis,
    required this.sources,
  });

  /// Recombine the cached basis at temperature [t]. Output is a fresh
  /// Float64List of length n. Fast enough to call every animation frame.
  /// Adaptive truncation: at low t the Bessel tail is already below
  /// 1e-8; we skip those terms. At high t we use the full K.
  Float64List recombine(double t) {
    final coeffs = besselCoeffs(t, K);
    final kEff = adaptiveK(coeffs, 1e-8);
    final phi = Float64List(n);
    for (var k = 0; k <= kEff; k++) {
      final c = coeffs[k];
      if (c == 0) continue;
      final base = k * n;
      for (var i = 0; i < n; i++) {
        phi[i] += c * basis[base + i];
      }
    }
    return phi;
  }

  /// Recombine AND rank into sorted scores, excluding [sources]. Useful
  /// for UI code that wants the same shape `diffuse()` returns.
  List<RelevanceScore> recombineAndRank(
    double t, {
    required List<String> idToPath,
  }) {
    final phi = recombine(t);
    final results = <RelevanceScore>[];
    for (var i = 0; i < phi.length; i++) {
      final path = idToPath[i];
      if (sources.contains(path)) continue;
      final v = phi[i];
      if (v <= 0) continue;
      results.add(RelevanceScore(path, v));
    }
    results.sort((a, b) => b.phi.compareTo(a.phi));
    return results;
  }
}

DiffusionBasis _buildDiffusionBasis({
  required CsrGraph graph,
  required Float64List rho,
  required int K,
  required Set<String> sources,
}) {
  // Delegate to logos_core.dart — single implementation shared by the
  // file-, chunk-, and hunk-graph engines.  Previously this duplicated
  // the Chebyshev recurrence inline; the wrapper only adds the `sources`
  // set that DiffusionBasis.recombineAndRank uses for UI labelling.
  return DiffusionBasis._(
    n: graph.n,
    K: K,
    basis: chebyshevBasis(graph: graph, rho: rho, K: K),
    sources: sources,
  );
}
