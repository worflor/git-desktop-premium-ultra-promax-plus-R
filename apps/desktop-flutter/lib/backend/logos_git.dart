// logos_git.dart - Logos-inspired git context engine
//
// A relevance diffusion engine for code review context. The diff is a
// source field rho. The codebase is a Riemannian manifold whose metric is
// learned from the repo's own history. Relevance is the heat-kernel
// solution phi = exp(-t * L) * rho - temperature at equilibrium after
// diffusing
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
// level - Float64List/Int32List buffers stand in for WASM linear memory,
// method bodies are shaped the same as the kernels would be. Porting
// to `logos_git.wat` later is mechanical.
//
// AXIS DECOMPOSITION (Phase 1 - zero new dependencies)
//
//   F0 (global frequency)     - per-file touch rate in history
//                               analogue: Logos order-0 bit distribution
//
//   CC (co-change Jaccard)    - from existing FileCouplingMatrix
//                               analogue: Logos O2 bigram (pairwise memory)
//
//   SP (spatial / path)       - directory proximity
//                               analogue: Logos Ab (above-neighbor)
//
//   V  (volatility / GARCH)   - EWMA of per-file churn magnitude
//                               analogue: Logos V (local energy / second moment)
//
// All axes output (p, n) - a predictor probability and an evidence count.
// Mix via Born rule:
//   A    = sum_i w_i * sqrt(p_i)
//   Abar = sum_i w_i * sqrt(1 - p_i)
//   p    = A^2 / (A^2 + Abar^2)
// Weights: w_i = abs(p_i - 0.5) * min(log1p(n_i), cap_i)
//
// The mixed edge probability p_mix is converted to a distance via
// d(i,j) = -ln(p_mix). Edge weights for the graph Laplacian use
// exp(-d) = p_mix, so the same number serves both roles.
//
// HEAT-KERNEL DIFFUSION
//
//   phi(t) = exp(-t * L_sym) * rho
//
// where L_sym = I - D^(-1/2) W D^(-1/2) is the normalised graph Laplacian.
// Evaluated via Chebyshev polynomial expansion:
//
//   exp(-tL) * rho ~= sum_{k=0..K} c_k(t) * T_k(L)
//
// where T_k are Chebyshev polynomials (first kind) and c_k(t) are
// modified Bessel functions I_k(-t). For K=20, accuracy is ~1e-8 on the
// spectrum [0, 2]. Each T_k(L) step is a sparse matvec - O(|E|) work.
// Total: O(K * |E|). A 10k-file repo with 100k edges diffuses in ~2M ops.
//
// THE TEMPERATURE KNOB
//
// Single scalar t controls diffusion range:
//   t ~ 0.25  - just the touched items
//   t ~ 1.0   - 1-hop neighbourhood (commit review default)
//   t ~ 2.0   - 2-hop, semantic neighbours (code Q&A)
//   t ~ 4.0   - wide, historical (codebase navigation)
//   t -> inf  - graph centrality (whole-repo summary)
//
// Same engine, same data, different t.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'engram_file_ktable.dart';
import 'engram_fit.dart';
import 'file_coupling.dart';
import 'logos_core.dart';
import 'logos_signature.dart';
import 'logos_spectrogeometry.dart' as sg_lib;
import 'spectral_kizuna.dart';
import 'spectral_ricci.dart';
import 'spectral_spacetime.dart';
import 'spectral_state.dart';
import 'spectral_walks.dart';
import 'logos_git_calibration.dart' show LogosAxis;
import 'logos_git_integrity.dart';
import 'spectral_constants.dart' as sc;
import 'lru_cache.dart';

/// Internals re-exported for tests. Not stable API - the
/// `@visibleForTesting`
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

// LAZY LUTs - adapted from logos.wat

/// log1p(n) - returns ln(1+n). Cached for small integer n so the
/// repeated weight computation doesn't call `math.log` for every edge.
/// Sentinel 0.0 means "not yet computed"; ln(1+0) = 0 naturally, so the
/// sentinel is safe for n=0 too.
///
/// Size is tuned to the dominant caller's evidence range. The CC axis
/// inside [BornMixer.mix] is called with `(matrix.commitsAnalyzed / 10)`
/// clamped to ~1024, so a 1024-entry table covers it completely while
/// keeping the table at 8 KB — solidly in L1 on every target core. The
/// F0 axis can exceed the cap for very large repos; those rare requests
/// fall through to `math.log` directly with no memoisation, which is
/// fine because the tail is one-off and the table would have been a
/// cold miss anyway.
class _Log1pLut {
  static const int _size = 1024;
  static final Float64List _t = Float64List(_size);

  static double call(int n) {
    if (n <= 0) return 0;
    if (n < _size) {
      final cached = _t[n];
      if (cached != 0) return cached;
      final v = math.log(1.0 + n);
      _t[n] = v;
      return v;
    }
    return math.log(1.0 + n);
  }
}

/// sigmoid(x) - logistic sigmoid. Same role as Logos' SIGMOID_LUT. Kept
/// lightweight; Dart's math.exp is native so a table lookup would barely
/// beat it on modern CPUs. If we need to port to .wat we'll add a
/// linear-interpolated LUT there (the WASM VM has no native exp).
double _sigmoid(double x) {
  if (x <= -12) return 1.5259021896696422e-05;
  if (x >= 12) return 0.9999847409781033;
  return 1.0 / (1.0 + math.exp(-x));
}

// BORN-AMPLITUDE MIX - the core blend operation

/// Per-axis observation: probability `p` in (0, 1) and evidence count `n`.
/// Axes with `n == 0` declare themselves silent via `weight() == 0`.
class AxisObs {
  final double p;
  final int n;
  const AxisObs(this.p, this.n);
  static const silent = AxisObs(0.5, 0);
}

/// Born-amplitude mix with confidence-gated, evidence-capped weights.
///   weight(i) = abs(p_i - 0.5) * min(log1p(n_i), cap_i)
///   A    = sum_i w_i * sqrt(p_i)
///   Abar = sum_i w_i * sqrt(1 - p_i)
///   p    = A^2 / (A^2 + Abar^2)
/// The confidence gate |p - 0.5| makes axes at p ~= 0.5 (pure uncertainty)
/// contribute zero - they can't drown out sharper axes. The `cap_i` per
/// axis prevents an over-evidenced axis from monopolising the mix.
/// Correlated axes (CC and AU firing together because same team edits
/// same files) don't double-count: amplitude interference absorbs the
/// shared component quadratically. Orthogonal lifts add as Pythagorean
/// limbs.
/// Returns a single probability in (0, 1). If all axes are silent,
/// returns 0.5 (maximum uncertainty - edge contributes weight exp(-d) =
/// exp(ln(2)) = 0.5 to the graph, i.e. a "weak connection").
class BornMixer {
  /// Evidence caps per axis - order matches the observation list passed
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
    // given the upstream guards) - but cheaper to guard than to debug.
    if (!denom.isFinite || denom <= 0) return 0.5;
    final p = a2 / denom;
    if (!p.isFinite) return 0.5;
    return p.clamp(1e-6, 1 - 1e-6);
  }
}

// AXIS COMPUTERS - Phase 1 set
//
// Each axis is a function (file_a, file_b, repoStats) -> AxisObs.
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

/// F0 - global frequency axis.
/// Purely conditional on the *destination* file: "how often does this
/// file appear in commits at all?" Symmetric by design - we're asking
/// whether `b` is a noteworthy node in the repo regardless of `a`.
/// Cold-start via KT prior -> 0.5.
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

/// CC - co-change axis. Uses the existing [FileCouplingMatrix].
/// P(b co-occurs with a | history) = Jaccard(a, b) smoothed with a KT
/// prior against the number of commits touching either side.
class _CcAxis {
  final FileCouplingMatrix matrix;

  const _CcAxis(this.matrix);

  AxisObs observe(String a, String b) {
    if (a == b) return const AxisObs(1.0, 1);
    final j = matrix.score(a, b);
    // Evidence scales with commits-per-file rather than a flat divisor.
    final filesTracked = matrix.trackedFileCount;
    final perFileEvidence = filesTracked > 0
        ? matrix.commitsAnalyzed / filesTracked
        : matrix.commitsAnalyzed / 10;
    final evidence = (perFileEvidence * 2).clamp(1, 1024).toInt();
    final p = (j * evidence + 0.5) / (evidence + 1.0);
    return AxisObs(p, evidence);
  }
}

// SP - path / spatial proximity.
//
// Measures directory overlap between two paths. Inlined into the build
// loop in `LogosGit.buildFromStats` (uses cached `pathSegments` to
// avoid two `.split('/')` allocations per scored edge - a per-build
// bytes saved is allocation pressure that won't trigger a young-gen GC).
//
// Semantics, for reference:
//   sa = a.split('/'); sb = b.split('/'); max = max(|sa|, |sb|)
//   shared = longest common prefix length, excluding final segment
//   p = (shared + 0.5) / (max + 1.0); evidence = max

/// V - volatility (GARCH-style second moment).
/// Each file has an EWMA of per-commit churn magnitude (additions +
/// deletions). Two files are "V-related" when their volatilities *match*
/// - the axis rewards probes diffusing toward other noisy files when
/// the diff itself is noisy, and toward stable files when the diff is
/// tame. Sign-aligned z-matching: z(|v_a - v_b|) inverted via sigmoid.
class _VAxis {
  final Map<String, double> volatility;
  final Map<String, int> touches;
  final double mean;
  final double stddev;

  const _VAxis({
    required this.volatility,
    required this.touches,
    required this.mean,
    required this.stddev,
  });

  AxisObs observe(String a, String b) {
    final va = volatility[a];
    final vb = volatility[b];
    if (va == null || vb == null) return AxisObs.silent;
    if (stddev <= 0) return AxisObs.silent;
    final z = (va - vb).abs() / stddev;
    final p = _sigmoid(2.0 - z);
    final na = touches[a] ?? 0;
    final nb = touches[b] ?? 0;
    final evidence = math.min(na, nb).clamp(2, 20);
    return AxisObs(p, evidence);
  }
}

/// EN - engram K-space cosine. Optional; only present when the engine
/// was built with `perFileKVectors` populated by the resolver.
/// Each file gets a complex K-vector with P real/imag pairs
/// (Alexandria's 150-pair eigenvalue signature for the file's identifier
/// content). Pairwise cosine over the flattened 2P vector measures
/// **content-semantic** affinity - orthogonal to CC's
/// historical co-change and SP's directory geometry, complementary to
/// the existing symbolEdges per-changeset symbol-overlap signal.
/// What this catches that the other axes miss:
///   - Files with similar purpose that have never co-changed (refactored
///     out, renamed, freshly-added).
///   - Cross-module semantic neighbours (test fixtures next to the
///     service they exercise; reducer + selector pairs in different dirs).
///   - Cold-start: a brand-new repo with empty history still has full
///     EN signal because K-vectors come from current content, not history.
/// Probability is the cosine clamped to [0, 1] then re-anchored against
/// the 0.5 mid-line (the silent default) - cosine >= 0.5 reads as a
/// positive predictor; below pulls the mixer toward "unrelated".
/// Built atop [EngramFileKTable] so observations read from contiguous
/// flat arrays - no per-pair object dereference. The build loop
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
    final aMagSq = _rowMagSq(table, ra);
    return _observeWithMagSq(ra, rb, aMagSq);
  }

  /// Precomputed `‖kRi[row]‖²` for [aNodeId]. Returns -1 if the node
  /// has no K-vector (caller must skip EN observations for that node).
  /// The build-loop pre-computes this ONCE per outer node `i` and
  /// reuses it across all candidate `j` via [observeIdsWithMag] —
  /// saves `P = pairs` FMAs per candidate that were previously
  /// re-accumulating the same `aMagSq` on every scored pair.
  double aMagSqFor(int aNodeId) {
    final ra = rowIds[aNodeId];
    if (ra < 0) return -1.0;
    return _rowMagSq(table, ra);
  }

  /// Variant of [observeIds] that skips the row-A mag-sq accumulation
  /// when the caller has cached `aMagSq` via [aMagSqFor]. Must pass a
  /// non-negative [aMagSq] (caller-gated).
  AxisObs observeIdsWithMag(int aNodeId, int bNodeId, double aMagSq) {
    final ra = rowIds[aNodeId];
    if (ra < 0) return AxisObs.silent;
    final rb = rowIds[bNodeId];
    if (rb < 0) return AxisObs.silent;
    return _observeWithMagSq(ra, rb, aMagSq);
  }

  AxisObs _observeWithMagSq(int ra, int rb, double aMagSq) {
    final cos = _cosineRowsWithAMagSq(table, ra, rb, aMagSq);
    if (cos <= 0) return AxisObs.silent;
    final p = 0.5 + 0.5 * cos;
    final hitsA = table.vocabHits[ra];
    final hitsB = table.vocabHits[rb];
    final n = hitsA < hitsB ? hitsA : hitsB;
    return AxisObs(p, n);
  }
}

/// Sum-of-squares of a single row's interleaved `kRi` slice. Used by
/// [_EnAxis.aMagSqFor] to cache the outer-node mag-sq across a whole
/// candidate scan (Grimoire XXI — tile row A into L1 for the inner
/// candidate loop instead of re-accumulating on every pair).
double _rowMagSq(EngramFileKTable t, int row) {
  final p = t.pairs;
  final base = row * p;
  final ri = t.kRi;
  double sum = 0.0;
  for (var i = 0; i < p; i++) {
    final a = ri[base + i];
    sum += a.x * a.x + a.y * a.y;
  }
  return sum;
}

/// Cosine between two rows of an [EngramFileKTable] when the caller
/// already has row A's magnitude-squared cached — the typical hot-path
/// shape in `buildFromStats`, where every row is compared against many
/// neighbours so the outer row's norm is paid once and reused.
/// The inner loop reads one Float64x2 per pair (row B only) and
/// accumulates `dot` and `bMagSq`.
double _cosineRowsWithAMagSq(
    EngramFileKTable t, int rowA, int rowB, double aMagSq) {
  if (aMagSq <= 0) return 0.0;
  final p = t.pairs;
  final aBase = rowA * p;
  final bBase = rowB * p;
  final ri = t.kRi;
  double dot = 0.0;
  double bMagSq = 0.0;
  for (var i = 0; i < p; i++) {
    final a = ri[aBase + i];
    final b = ri[bBase + i];
    dot += a.x * b.x + a.y * b.y;
    bMagSq += b.x * b.x + b.y * b.y;
  }
  if (bMagSq <= 0) return 0.0;
  final cos = dot / math.sqrt(aMagSq * bMagSq);
  if (!cos.isFinite) return 0.0;
  if (cos <= 0) return 0.0;
  if (cos >= 1) return 1.0;
  return cos;
}

// SPARSE GRAPH (CSR) + Chebyshev heat-kernel - moved to logos_core.dart
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
/// epsilon = 0.15 means source weights move by +/-15% per trial - well above
/// the noise floor of sane upstream probes (SSE-scaled weights shift
/// by <5%) but inside the band where a stable ranking should hold.
const double _defaultStabilityEpsilon = 0.15;

/// Deterministic seed for the stability primitive's RNG. Arbitrary
/// but constant - repeated calls produce identical perturbations,
/// making the primitive reproducible in tests and diagnostics.
const int _defaultStabilitySeed = 0xABDE;

/// Default top-K neighbours per node in the sparsified graph. Derived
/// as a small multiple of the max expected "cluster size" in a real
/// repo - a single module typically has 10-20 tightly-coupled files,
/// so 24 neighbours keeps every plausible cluster connected while
/// bounding the graph to O(24 * |V|) edges. Mentioned separately from
/// the Chebyshev K to avoid confusion - this K is graph sparsity, not
/// polynomial order.
const int _defaultEdgeDensity = 24;

/// Floor below which a spectral signal is indistinguishable from
/// numerical noise in the diffusion. Every scattered `> 0.02` gate
/// in the witness / frontier / summary builders references this
/// single constant so the engine has one noise floor, not twelve.
const double _kSignalFloor = 0.02;

/// Transport-edge floor — half the signal floor because transport
/// pull is a product of two masses (source × edge weight), so its
/// magnitude is inherently smaller for legitimate connections.
const double _kTransportFloor = _kSignalFloor * 0.5;

/// Integrity floor for transport edge weighting. Files with integrity
/// below this still contribute transport signal at this minimum level
/// so that newly-appeared files aren't invisible to transport lanes.
class GhostCoupling {
  final String sourceFile;
  final String targetFile;
  final double ghostJaccard;
  final double effectiveWeight;
  const GhostCoupling({
    required this.sourceFile,
    required this.targetFile,
    required this.ghostJaccard,
    required this.effectiveWeight,
  });
}

// Gas-phase evaporation (1/e) — the thermodynamic minimum for both
// transport integrity and shadow evidence discount.
final double _kTransportIntegrityFloor = sc.gasPhase;
final double _kShadowDiscount = sc.gasPhase;

// Corroboration bonus: when shadow evidence reinforces a real edge,
// the real score gets a small additive lift scaled by the shadow's
// discounted strength. Derived from the Born mixer's amplitude
// addition: sqrt(p_real) + sqrt(p_shadow) → squared back.
final double _kCorroborationLift = sc.gasPhase * sc.phiDecay3; // ≈ 0.087

Iterable<MapEntry<String, double>> _blendedJaccardEdges(
  FileCouplingMatrix real,
  FileCouplingMatrix shadow,
  String path,
) sync* {
  final seen = <String>{};
  for (final entry in real.jaccardEntriesOf(path)) {
    seen.add(entry.key);
    final shadowScore = shadow.jaccardScoreOf(path, entry.key);
    if (shadowScore > 0) {
      final lift = shadowScore * _kCorroborationLift;
      yield MapEntry(entry.key, (entry.value + lift).clamp(0.0, 1.0));
    } else {
      yield entry;
    }
  }
  for (final entry in shadow.jaccardEntriesOf(path)) {
    if (seen.contains(entry.key)) continue;
    yield MapEntry(entry.key, entry.value * _kShadowDiscount);
  }
}

/// Additive boost applied to a file's utility score for its
/// high-frequency-spectral "surprise" signal — the portion of a
/// file's diffused mass that lives in modes above the Fiedler scale.
/// Value chosen in the same order of magnitude as the transport-pull
/// boost below, deliberately kept smaller than 1 so that the base
/// `surplus * integrity` score dominates for high-support files. This
/// is a compositional tuning constant (hand-picked, not derived); if
/// tuning via an ablation study, expect a range of 0.10–0.25 to
/// behave similarly.
const double _utilityHfSurpriseWeight = 0.15;

/// Additive boost applied to a file's utility score for its
/// transport-pull signal — the strength of the directed-flow heat
/// arriving at the file from semantically linked neighbours. Same
/// compositional-constant class as [_utilityHfSurpriseWeight]; its
/// smaller magnitude reflects that transport pull is already
/// indirectly in `surplus` via the transport graph.
const double _utilityTransportPullWeight = 0.10;

// (besselCoeffs / adaptiveK / chebyshevDiffuse live in logos_core.dart.)

// THE ENGINE

/// Raw per-file statistics the engine needs to construct its axes.
const Object _sentinel = Object();

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
  /// commit indices (in oldest->newest order, range [0, totalCommits))
  /// where the file appeared. Drives the per-file AR(2) curvature
  /// metric in [LogosGit.buildFromStats] - each file gets its own
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
  final Map<String, List<LogosCommitHyperedge>> hyperedgesByPath;
  final String forge;
  /// Merge-commit SHAs that arrived through reviewed PRs/MRs,
  /// mapped to the set of reviewer logins who observed the change.
  final Map<String, Set<String>> reviewedCommits;
  /// Per-path union of all reviewer logins across all reviewed
  /// commits that touched the path. The reviewer constellation —
  /// which humans have observed which parts of the codebase.
  final Map<String, Set<String>> reviewersByPath;
  final Map<String, Map<String, int>> authorTouches;

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
    this.hyperedgesByPath = const {},
    this.forge = 'unknown',
    this.reviewedCommits = const {},
    this.reviewersByPath = const {},
    this.authorTouches = const {},
    this.shadowCoupling,
  });

  final FileCouplingMatrix? shadowCoupling;

  LogosGitStats copyWith({
    Map<String, int>? touches,
    int? totalCommits,
    Map<String, double>? volatility,
    double? volMean,
    double? volStddev,
    FileCouplingMatrix? coupling,
    Map<String, List<int>>? perFileCommitIndices,
    Map<String, int>? rawTouches,
    int? rawTotalCommits,
    Map<String, double>? touchMass,
    double? semanticCommitMass,
    Map<String, List<double>>? perFileCommitClock,
    Map<String, double>? ritualnessByPath,
    Map<String, double>? integrityByPath,
    Map<String, List<String>>? integrityReasonsByPath,
    Map<String, List<LogosCommitHyperedge>>? hyperedgesByPath,
    String? forge,
    Map<String, Set<String>>? reviewedCommits,
    Map<String, Set<String>>? reviewersByPath,
    Map<String, Map<String, int>>? authorTouches,
    Object? shadowCoupling = _sentinel,
  }) =>
      LogosGitStats(
        touches: touches ?? this.touches,
        totalCommits: totalCommits ?? this.totalCommits,
        volatility: volatility ?? this.volatility,
        volMean: volMean ?? this.volMean,
        volStddev: volStddev ?? this.volStddev,
        coupling: coupling ?? this.coupling,
        perFileCommitIndices: perFileCommitIndices ?? this.perFileCommitIndices,
        rawTouches: rawTouches ?? this.rawTouches,
        rawTotalCommits: rawTotalCommits ?? this.rawTotalCommits,
        touchMass: touchMass ?? this.touchMass,
        semanticCommitMass: semanticCommitMass ?? this.semanticCommitMass,
        perFileCommitClock: perFileCommitClock ?? this.perFileCommitClock,
        ritualnessByPath: ritualnessByPath ?? this.ritualnessByPath,
        integrityByPath: integrityByPath ?? this.integrityByPath,
        integrityReasonsByPath:
            integrityReasonsByPath ?? this.integrityReasonsByPath,
        hyperedgesByPath: hyperedgesByPath ?? this.hyperedgesByPath,
        forge: forge ?? this.forge,
        reviewedCommits: reviewedCommits ?? this.reviewedCommits,
        reviewersByPath: reviewersByPath ?? this.reviewersByPath,
        authorTouches: authorTouches ?? this.authorTouches,
        shadowCoupling: identical(shadowCoupling, _sentinel)
            ? this.shadowCoupling
            : shadowCoupling as FileCouplingMatrix?,
      );
}

/// Relevance score produced by diffusion. `phi` is the raw heat-kernel
/// value; higher = more relevant. `path` identifies the file.
class RelevanceScore {
  final String path;
  final double phi;
  const RelevanceScore(this.path, this.phi);
  @override
  String toString() => '$path  phi=${phi.toStringAsFixed(4)}';
}

/// Emission tier - FULL (whole body), SIG (signature + breadcrumbs),
/// BREAD (filename + one-liner). Higher tier = more tokens, more info.
enum EmissionTier { full, signature, breadcrumb }

class EmissionPlan {
  final String path;
  final double phi;
  final EmissionTier tier;
  const EmissionPlan(this.path, this.phi, this.tier);
}

enum LogosWitnessKind {
  axis,
  relation,
  transport,
  hyperedge,
  reducibility,
  integrity,
  spectrum,
  ambient,
}

class LogosEvidenceWitness {
  final LogosWitnessKind kind;
  final String label;
  final double strength;
  final List<String> sourcePaths;
  final String? note;
  final String? sourcePath;
  final String? targetPath;
  final String? sourceRole;
  final String? targetRole;
  final bool directional;
  /// Named human observers on this witness (for hyperedge kind).
  final Set<String> observers;

  const LogosEvidenceWitness({
    required this.kind,
    required this.label,
    required this.strength,
    this.sourcePaths = const [],
    this.note,
    this.sourcePath,
    this.targetPath,
    this.sourceRole,
    this.targetRole,
    this.directional = false,
    this.observers = const {},
  });
}

class LogosMetricSidecar {
  final String label;
  final double strength;
  final List<String> paths;
  final List<String> channels;
  final String? note;

  const LogosMetricSidecar({
    required this.label,
    required this.strength,
    this.paths = const [],
    this.channels = const [],
    this.note,
  });
}

String _compactWitnessPath(String path) {
  final parts = path
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return path;
  if (parts.length == 1) return parts.first;
  return '${parts[parts.length - 2]}/${parts.last}';
}

String formatLogosEvidenceWitness(
  LogosEvidenceWitness witness, {
  bool includeNote = true,
  bool includeSource = false,
}) {
  final source = witness.sourcePath ??
      (witness.sourcePaths.isEmpty ? null : witness.sourcePaths.first);
  final directionTag = !includeSource &&
          witness.directional &&
          witness.sourceRole != null &&
          witness.targetRole != null
      ? '[${witness.sourceRole}->${witness.targetRole}]'
      : '';
  final sourceTag =
      includeSource && source != null ? '@${_compactWitnessPath(source)}' : '';
  final note =
      includeNote && witness.note != null && witness.note!.trim().isNotEmpty
          ? ':${witness.note!.trim()}'
          : '';
  return '${witness.label}$directionTag$sourceTag$note';
}

String formatLogosMetricSidecar(
  LogosMetricSidecar sidecar, {
  bool includeNote = true,
}) {
  final note =
      includeNote && sidecar.note != null && sidecar.note!.trim().isNotEmpty
          ? ':${sidecar.note!.trim()}'
          : '';
  return '${sidecar.label}$note';
}

class LogosCommitHyperedge {
  final List<String> paths;
  final double weight;
  final String? summary;
  final String? commitHash;
  /// Named human observers who reviewed this change.
  final Set<String> observers;

  const LogosCommitHyperedge({
    required this.paths,
    required this.weight,
    this.summary,
    this.commitHash,
    this.observers = const {},
  });

  int get observerCount => observers.length + 1;
}

class LogosEvidenceScore {
  final String path;
  final double support;
  final double ambient;
  final double transportPull;
  final double transportedSupport;
  final double innovationResidual;
  final double witnessResidual;
  final double lowFrequencySupport;
  final double highFrequencySurprise;
  final double rawSurplus;
  final double surplus;
  final double integrity;
  final double utility;
  final double higherOrderLift;
  final double reducibilityGap;
  final String? dominantAxis;
  final Map<String, double>? axisShares;
  final List<LogosEvidenceWitness> witnesses;
  final List<LogosMetricSidecar> sidecars;

  const LogosEvidenceScore({
    required this.path,
    required this.support,
    required this.ambient,
    required this.transportPull,
    required this.transportedSupport,
    required this.innovationResidual,
    required this.witnessResidual,
    required this.lowFrequencySupport,
    required this.highFrequencySurprise,
    required this.rawSurplus,
    required this.surplus,
    required this.integrity,
    required this.utility,
    required this.higherOrderLift,
    required this.reducibilityGap,
    this.dominantAxis,
    this.axisShares,
    this.witnesses = const [],
    this.sidecars = const [],
  });
}

class LogosTransportFlowEdge {
  final String sourcePath;
  final String targetPath;
  final double pull;
  final String? laneLabel;
  final double laneStrength;
  final String? note;
  final String? sourceRole;
  final String? targetRole;
  final bool directional;

  const LogosTransportFlowEdge({
    required this.sourcePath,
    required this.targetPath,
    required this.pull,
    this.laneLabel,
    this.laneStrength = 0.0,
    this.note,
    this.sourceRole,
    this.targetRole,
    this.directional = true,
  });
}

String formatLogosTransportFlowEdge(
  LogosTransportFlowEdge edge, {
  bool includePull = true,
}) {
  final src = _compactWitnessPath(edge.sourcePath);
  final dst = _compactWitnessPath(edge.targetPath);
  final lane = edge.laneLabel == null || edge.laneLabel!.trim().isEmpty
      ? ''
      : '[${edge.laneLabel}]';
  final pull = includePull ? ':${edge.pull.toStringAsFixed(3)}' : '';
  return '$src->$dst$lane$pull';
}

class LogosTransportSummary {
  final double pull;
  final Map<String, double> laneFractions;
  final List<String> frontierPaths;
  final List<LogosTransportFlowEdge> frontierEdges;

  const LogosTransportSummary({
    this.pull = 0.0,
    this.laneFractions = const {},
    this.frontierPaths = const [],
    this.frontierEdges = const [],
  });

  List<String> dominantLanes({int limit = 3}) {
    if (laneFractions.isEmpty || limit <= 0) return const [];
    final entries = laneFractions.entries.toList()
      ..sort((a, b) {
        final byMass = b.value.compareTo(a.value);
        if (byMass != 0) return byMass;
        return a.key.compareTo(b.key);
      });
    return entries.take(limit).map((e) => e.key).toList(growable: false);
  }

  List<String> frontierPathsFromEdges({int limit = 4}) {
    if (frontierEdges.isEmpty || limit <= 0) return const [];
    final paths = <String>[];
    final seen = <String>{};
    for (final edge in frontierEdges) {
      if (!seen.add(edge.targetPath)) continue;
      paths.add(edge.targetPath);
      if (paths.length >= limit) break;
    }
    return paths;
  }

  List<String> dominantEdgeLanes({int limit = 3}) {
    if (frontierEdges.isEmpty || limit <= 0) return const [];
    final laneMass = <String, double>{};
    for (final edge in frontierEdges) {
      final label = edge.laneLabel;
      if (label == null || label.trim().isEmpty) continue;
      laneMass[label] = (laneMass[label] ?? 0.0) + edge.pull;
    }
    if (laneMass.isEmpty) return const [];
    final entries = laneMass.entries.toList()
      ..sort((a, b) {
        final byMass = b.value.compareTo(a.value);
        if (byMass != 0) return byMass;
        return a.key.compareTo(b.key);
      });
    return entries.take(limit).map((e) => e.key).toList(growable: false);
  }
}

class LogosSemanticMotionSummary {
  final double warpCoverage;
  final double innovationMass;
  final double compensatedChangeRatio;
  final bool sceneCut;
  final List<String> innovationFrontier;

  const LogosSemanticMotionSummary({
    this.warpCoverage = 0.0,
    this.innovationMass = 0.0,
    this.compensatedChangeRatio = 0.0,
    this.sceneCut = false,
    this.innovationFrontier = const [],
  });
}

class LogosWitnessResidualSummary {
  final double predictedMass;
  final double residualMass;
  final double coverage;
  final List<String> frontierPaths;
  final List<String> dominantKinds;

  const LogosWitnessResidualSummary({
    this.predictedMass = 0.0,
    this.residualMass = 0.0,
    this.coverage = 0.0,
    this.frontierPaths = const [],
    this.dominantKinds = const [],
  });
}

class LogosResidualView {
  final String path;
  final double support;
  final double ambient;
  final double utility;
  final double integrity;
  final double transportPull;
  final double transportedSupport;
  final double innovationResidual;
  final double witnessResidual;
  final double lowFrequencySupport;
  final double highFrequencySurprise;
  final double higherOrderLift;
  final double reducibilityGap;
  final String? dominantAxis;
  final List<LogosEvidenceWitness> witnesses;
  final List<LogosMetricSidecar> sidecars;

  const LogosResidualView({
    required this.path,
    required this.support,
    required this.ambient,
    required this.utility,
    required this.integrity,
    required this.transportPull,
    required this.transportedSupport,
    required this.innovationResidual,
    required this.witnessResidual,
    required this.lowFrequencySupport,
    required this.highFrequencySurprise,
    required this.higherOrderLift,
    required this.reducibilityGap,
    required this.dominantAxis,
    this.witnesses = const [],
    this.sidecars = const [],
  });

  double get transportSignal =>
      math.max(transportPull, transportedSupport).clamp(0.0, 1.0).toDouble();

  double get residualMass =>
      (innovationResidual + witnessResidual).clamp(0.0, 1.0).toDouble();

  double get residualSignal =>
      math.max(innovationResidual, witnessResidual).clamp(0.0, 1.0).toDouble();

  double semanticSignal({double importance = 0.0}) => math
      .max(importance, math.max(transportSignal, residualSignal))
      .clamp(0.0, 1.0)
      .toDouble();
}

/// Per-iteration snapshot passed to [gatherEvidenceRecurrent]'s
/// optional `onIteration` callback. Carries just enough for the
/// vis layer to pulse a ring — no heavy data, no coupling.
class RecurrentIterationReport {
  const RecurrentIterationReport({
    required this.iteration,
    required this.noveltyMass,
    required this.promotedPaths,
    required this.hfWeight,
    required this.tpWeight,
  });

  final int iteration;
  final double noveltyMass;
  final int promotedPaths;
  final double hfWeight;
  final double tpWeight;
}

/// Output of [LogosGit.gatherEvidenceRecurrent]. Wraps a single
/// [LogosEvidenceQueryResult] (the final iteration's snapshot) with
/// metadata describing how the iterative exploration proceeded —
/// which paths were discovered at which depth, whether the loop
/// converged on a self-consistent distribution, and the residual
/// novelty mass at termination.
class LogosRecurrentEvidenceResult {
  const LogosRecurrentEvidenceResult({
    required this.evidence,
    required this.iterations,
    required this.converged,
    required this.discoveryDepth,
    required this.finalNoveltyMass,
    this.adaptedHfSurpriseWeight,
    this.adaptedTransportPullWeight,
  });

  final LogosEvidenceQueryResult? evidence;
  final int iterations;
  final bool converged;
  final Map<String, int> discoveryDepth;
  final double finalNoveltyMass;

  /// Self-tuned utility weights at termination. Null when the loop
  /// ran only one iteration (no adaptation occurred).
  final double? adaptedHfSurpriseWeight;
  final double? adaptedTransportPullWeight;
}

class _NoveltyCandidate {
  _NoveltyCandidate(this.path, this.novelty);
  final String path;
  final double novelty;
}

class LogosEvidenceQueryResult {
  final List<LogosEvidenceScore> ranked;
  final Map<String, LogosResidualView> residualByPath;
  final List<LogosMetricSidecar> metricSidecars;
  final LogosTransportSummary transport;
  final LogosSemanticMotionSummary semanticMotion;
  final LogosWitnessResidualSummary witnessResidual;
  final Map<String, double> transportPullByPath;
  final LogosInquiryPlan inquiryPlan;
  final double? sourceAlignment;
  final double? fieldAlignment;
  final double? sourceSurprise;
  final double? fieldSurprise;
  final double coherence;
  final double stability;
  final LogosFlowDiagnostics flowDiagnostics;
  final LogosWitnessSyndrome witnessSyndrome;
  final AxisAttribution? supportAttribution;

  const LogosEvidenceQueryResult({
    required this.ranked,
    required this.residualByPath,
    required this.metricSidecars,
    required this.transport,
    required this.semanticMotion,
    required this.witnessResidual,
    required this.transportPullByPath,
    required this.inquiryPlan,
    required this.sourceAlignment,
    required this.fieldAlignment,
    required this.sourceSurprise,
    required this.fieldSurprise,
    required this.coherence,
    required this.stability,
    required this.flowDiagnostics,
    required this.witnessSyndrome,
    required this.supportAttribution,
  });
}

enum LogosInquiryActionKind {
  inspectPath,
  inspectCompanion,
}

class LogosInquiryStep {
  final LogosInquiryActionKind kind;
  final String path;
  final double priority;
  final String rationale;
  final String? viaPath;
  final String? laneLabel;

  const LogosInquiryStep({
    required this.kind,
    required this.path,
    required this.priority,
    required this.rationale,
    this.viaPath,
    this.laneLabel,
  });
}

class LogosInquiryPlan {
  final List<LogosInquiryStep> steps;

  const LogosInquiryPlan({
    this.steps = const [],
  });
}

String formatLogosInquiryStep(LogosInquiryStep step) {
  final via =
      step.viaPath == null ? '' : ' via ${_compactWitnessPath(step.viaPath!)}';
  final lane = step.laneLabel == null ? '' : ' [${step.laneLabel}]';
  return '${step.path}$via$lane:${step.rationale}';
}

class LogosEvidenceRollup {
  final double transportPull;
  final double lowFrequencySupport;
  final double highFrequencySurprise;
  final double higherOrderLift;
  final double reducibilityGap;
  final Map<String, double> witnessKindFractions;

  const LogosEvidenceRollup({
    required this.transportPull,
    required this.lowFrequencySupport,
    required this.highFrequencySurprise,
    required this.higherOrderLift,
    required this.reducibilityGap,
    this.witnessKindFractions = const {},
  });

  List<String> topWitnessKinds({int limit = 3}) {
    if (limit <= 0 || witnessKindFractions.isEmpty) return const [];
    final ordered = witnessKindFractions.entries.toList()
      ..sort((a, b) {
        final byValue = b.value.compareTo(a.value);
        if (byValue != 0) return byValue;
        return a.key.compareTo(b.key);
      });
    return ordered.take(limit).map((e) => e.key).toList(growable: false);
  }
}

class LogosWitnessSyndrome {
  final double coverage;
  final double corroboration;
  final double disagreement;
  final Map<String, double> kindFractions;
  final List<String> dominantKinds;
  final List<String> missingKinds;

  const LogosWitnessSyndrome({
    required this.coverage,
    required this.corroboration,
    required this.disagreement,
    this.kindFractions = const {},
    this.dominantKinds = const [],
    this.missingKinds = const [],
  });
}

class LogosFlowDiagnostics {
  final double gradientMass;
  final double curlMass;
  final double harmonicMass;
  final double structuralStress;
  final double witnessEntropy;
  final double confidence;

  const LogosFlowDiagnostics({
    required this.gradientMass,
    required this.curlMass,
    required this.harmonicMass,
    required this.structuralStress,
    required this.witnessEntropy,
    required this.confidence,
  });
}

double _normalizedWitnessEntropy(Map<String, double> fractions) {
  if (fractions.length <= 1) return 0.0;
  final mass = fractions.values.fold<double>(0.0, (a, b) => a + b);
  if (mass <= 0) return 0.0;
  var entropy = 0.0;
  for (final value in fractions.values) {
    if (value <= 0) continue;
    final p = value / mass;
    entropy -= p * math.log(p);
  }
  final denom = math.log(fractions.length);
  if (denom <= 0 || entropy.isNaN || !entropy.isFinite) return 0.0;
  return (entropy / denom).clamp(0.0, 1.0).toDouble();
}

LogosFlowDiagnostics computeLogosFlowDiagnostics({
  required double coherence,
  required double stability,
  double? sourceAlignment,
  double? fieldAlignment,
  required double lowFrequencySupport,
  required double highFrequencySurprise,
  required double higherOrderLift,
  required double reducibilityGap,
  Map<String, double> witnessKindFractions = const {},
}) {
  final coh = coherence.clamp(0.0, 1.0).toDouble();
  final stab = stability.clamp(0.0, 1.0).toDouble();
  final sa = sourceAlignment?.clamp(0.0, 1.0).toDouble();
  final fa = fieldAlignment?.clamp(0.0, 1.0).toDouble();
  final lf = lowFrequencySupport.clamp(0.0, 1.0).toDouble();
  final hf = highFrequencySurprise.clamp(0.0, 1.0).toDouble();
  final ho = higherOrderLift.clamp(0.0, 1.0).toDouble();
  final rg = reducibilityGap.clamp(0.0, 1.0).toDouble();
  final witnessEntropy = _normalizedWitnessEntropy(witnessKindFractions);
  final alignmentGap = sa != null && fa != null
      ? (sa - fa).abs()
      : (fa ?? sa) != null
          ? (1.0 - (fa ?? sa)!).abs()
          : 0.0;
  final gradientMass =
      (alignmentGap * (0.55 + 0.45 * lf)).clamp(0.0, 1.0).toDouble();
  final curlMass = (((1.0 - stab) + (1.0 - coh) + hf + witnessEntropy) / 4.0)
      .clamp(0.0, 1.0)
      .toDouble();
  // LF support and reducibility gap are symmetric axes of spectral
  // smoothness — one boosts, one attenuates, same depth.
  const spectralDepth = 0.6;
  const hfDepth = 0.35;
  const hoLift = 0.1;
  final harmonicMass = ((((coh + stab) / 2.0) *
              (1.0 - spectralDepth * (1.0 - lf)) *
              (1.0 - spectralDepth * rg) *
              (1.0 - hfDepth * hf)) +
          (hoLift * ho))
      .clamp(0.0, 1.0)
      .toDouble();
  // Weighted mean of disorder indicators. ho is half-weight (indirect).
  const hoStressWeight = 0.5;
  final structuralStress =
      ((curlMass + (1.0 - harmonicMass) + hf + rg + hoStressWeight * ho) /
              (4.0 + hoStressWeight))
          .clamp(0.0, 1.0)
          .toDouble();
  final observed = (sa != null ? 1.0 : 0.0) + (fa != null ? 1.0 : 0.0);
  final confidence = ((0.35 * (observed / 2.0)) +
          (0.25 * coh) +
          (0.25 * stab) +
          (0.15 * (witnessKindFractions.isNotEmpty ? 1.0 : 0.0)))
      .clamp(0.0, 1.0)
      .toDouble();
  return LogosFlowDiagnostics(
    gradientMass: gradientMass,
    curlMass: curlMass,
    harmonicMass: harmonicMass,
    structuralStress: structuralStress,
    witnessEntropy: witnessEntropy,
    confidence: confidence,
  );
}

LogosEvidenceRollup rollupEvidenceTopology(
  Iterable<LogosEvidenceScore> ranked, {
  int maxEntries = 12,
  int maxWitnessesPerEntry = 3,
}) {
  if (maxEntries <= 0) {
    return const LogosEvidenceRollup(
      lowFrequencySupport: 0.0,
      highFrequencySurprise: 0.0,
      transportPull: 0.0,
      higherOrderLift: 0.0,
      reducibilityGap: 0.0,
    );
  }
  var weightSum = 0.0;
  var low = 0.0;
  var high = 0.0;
  var transport = 0.0;
  var higherOrder = 0.0;
  var reducibility = 0.0;
  final witnessMass = <String, double>{};
  for (final score in ranked.take(maxEntries)) {
    final weight = score.support > 0 ? score.support : score.utility;
    if (!weight.isFinite || weight <= 0) continue;
    weightSum += weight;
    low += weight * score.lowFrequencySupport;
    high += weight * score.highFrequencySurprise;
    transport += weight * score.transportPull;
    higherOrder += weight * score.higherOrderLift;
    reducibility += weight * score.reducibilityGap;
    for (final witness in score.witnesses.take(maxWitnessesPerEntry)) {
      final witnessWeight = weight * witness.strength.clamp(0.0, 1.0);
      if (!witnessWeight.isFinite || witnessWeight <= 0) continue;
      witnessMass[witness.kind.name] =
          (witnessMass[witness.kind.name] ?? 0.0) + witnessWeight;
    }
  }
  if (weightSum <= 0) {
    return const LogosEvidenceRollup(
      lowFrequencySupport: 0.0,
      highFrequencySurprise: 0.0,
      transportPull: 0.0,
      higherOrderLift: 0.0,
      reducibilityGap: 0.0,
    );
  }
  final normalizedWitnessMass = <String, double>{};
  final witnessSum = witnessMass.values.fold<double>(0.0, (a, b) => a + b);
  if (witnessSum > 0) {
    for (final entry in witnessMass.entries) {
      normalizedWitnessMass[entry.key] = entry.value / witnessSum;
    }
  }
  return LogosEvidenceRollup(
    transportPull: transport / weightSum,
    lowFrequencySupport: low / weightSum,
    highFrequencySurprise: high / weightSum,
    higherOrderLift: higherOrder / weightSum,
    reducibilityGap: reducibility / weightSum,
    witnessKindFractions: normalizedWitnessMass,
  );
}

LogosWitnessSyndrome computeLogosWitnessSyndrome(
  LogosEvidenceRollup rollup, {
  required double witnessEntropy,
}) {
  const expectedKinds = <String>[
    'relation',
    'transport',
    'integrity',
    'spectrum',
  ];
  final ordered = rollup.witnessKindFractions.entries.toList()
    ..sort((a, b) {
      final byValue = b.value.compareTo(a.value);
      if (byValue != 0) return byValue;
      return a.key.compareTo(b.key);
    });
  final presentKinds = <String>{
    for (final entry in ordered)
      if (entry.value >= 0.08) entry.key,
  };
  final coverage = expectedKinds.isEmpty
      ? 0.0
      : expectedKinds.where(presentKinds.contains).length /
          expectedKinds.length;
  final topMass = ordered.take(2).fold<double>(0.0, (sum, e) => sum + e.value);
  final missingKinds = [
    for (final kind in expectedKinds)
      if (!presentKinds.contains(kind)) kind,
  ];
  return LogosWitnessSyndrome(
    coverage: coverage.clamp(0.0, 1.0).toDouble(),
    corroboration: topMass.clamp(0.0, 1.0).toDouble(),
    disagreement: witnessEntropy.clamp(0.0, 1.0).toDouble(),
    kindFractions: rollup.witnessKindFractions,
    dominantKinds:
        ordered.take(3).map((entry) => entry.key).toList(growable: false),
    missingKinds: missingKinds,
  );
}

/// Born-mix caps per axis, in the canonical [AxisId] order (f0, cc, sp, v).
/// The caps are the maximum evidence (in nats) each axis can contribute
/// to the Born amplitude mix. They're information-theoretic - each is
/// the natural log of the axis's intrinsic branching factor:
///   F0 = ln(2) - one bit: "is this file touched at all in this window?"
///   CC = ln(4) - two bits: four effective co-change regimes
///                (together|sometimes|rarely|never)
///   SP = ln(3) - one trit: same file | same directory | elsewhere
///   V  = ln(3) - one trit: calmer | matched | noisier than the partner
/// Derivable not magic: each value is literally `ln(k)` where k is the
/// axis's distinguishable states. Expressed as such so the relationship
/// is visible in the code, not stranded in a comment.
final _defaultCaps = <double>[
  math.ln2, // F0: ln(2)
  2 * math.ln2, // CC: ln(4) = 2?ln(2)
  math.log(3), // SP: ln(3)
  math.log(3), // V:  ln(3)
];

/// Caps when the engine was built with engram K-vectors. Adds an EN
/// cap of ln(4) = 2 bits - Alexandria's wells distinguish ~225 semantic
/// basins, but most files cluster around a handful of dominant ones in
/// any given repo. Two bits captures "same well | adjacent well | far
/// well | unrelated" without letting the EN axis dominate well-evidenced
/// CC signals.
final _defaultCapsWithEngram = <double>[
  ..._defaultCaps,
  2 * math.ln2, // EN: ln(4)
];

/// Key for the Chebyshev basis cache. Record equality covers the
/// composite `(fingerprint, K)` identity without manual hash folding.
typedef _BasisCacheKey = ({int rhoFingerprint, int K});

/// Size of the per-engine basis LRU. Each entry is `(K+1)·n` doubles —
/// ~320 KB at K=20 and n=2k — so four entries cap the working set at
/// ~1 MB, comfortably in last-level cache without punishing hot code.
const int _kChebyshevBasisCacheSize = 4;

// Spectral thresholds are shared with hunk and chunk engines via
// [kDefaultSpectralMinNodes] and [kDefaultSpectralBasisK] in
// `logos_core.dart`. Keeping them in one place means every level of
// the spectral tower answers the "should I build a basis here?"
// question with the same policy.

/// Content fingerprint of a ρ vector. Uses the Float64 bit patterns so
/// identical-valued-but-freshly-allocated vectors hash the same. FNV-1a
/// style mix over the int32 halves keeps cost linear in `n` with no
/// allocation; for typical n < 10k the hash is sub-millisecond.
int _fingerprintRho(Float64List rho) {
  if (rho.isEmpty) return rho.length;
  final bd = rho.buffer.asByteData(rho.offsetInBytes, rho.lengthInBytes);
  var h = 0x811c9dc5 ^ rho.length;
  for (var i = 0; i < rho.length; i++) {
    final lo = bd.getInt32(i * 8, Endian.little);
    final hi = bd.getInt32(i * 8 + 4, Endian.little);
    h = (h ^ lo) & 0x3fffffff;
    h = ((h * 0x01000193) ^ (h >> 13)) & 0x3fffffff;
    h = (h ^ hi) & 0x3fffffff;
    h = ((h * 0x01000193) ^ (h >> 13)) & 0x3fffffff;
  }
  return h;
}

/// Monotonic counter used to tag each [LogosGit] with a stable revision id.
/// Downstream caches can key on `manifoldRevision` to skip work whose
/// inputs haven't logically changed; `withSymbolEdges` preserves the
/// revision so symbol-edge overlays don't invalidate graph-derived work.
int _logosGitRevisionCounter = 0;

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
  final CsrGraph transportGraph;
  final List<String> nodePaths; // id -> path
  final Map<String, int> pathToId;
  final BornMixer mixer;

  /// Per-file AR(2) fit on the file's inter-touch-gap series. Computed
  /// in [buildFromStats] when [LogosGitStats.perFileCommitIndices] is
  /// available and the file has enough touches for the fit. Empty for
  /// files with insufficient history (curvature factor = 1.0 for them).
  /// Drives the curved-metric edge weighting: each file's spectral
  /// radius `r_f` measures how regular its touch pattern is
  /// (1.0 = perfectly periodic, 0 = chaotic). Edge weight `W'[a,b] =
  /// W[a,b] * sqrt(r_a * r_b)` so heat flows faster through regularly-
  /// touched files and attenuates through chaotic ones.
  final Map<String, EngramFit> perFileMetrics;

  /// The raw stats this engine was built from. Retained as a back-
  /// reference so callers can derive secondary signals (recency-decayed
  /// activity field, per-file touch counts, etc.) without re-running
  /// [collectLogosGitStats]. Conceptually: stats are the *what*, the
  /// engine is the *how* - keeping both adjacent avoids duplicating the
  /// log-walk in features that need both.
  final LogosGitStats stats;
  final Map<String, double> integrityByPath;
  final CouplingConstants couplingConstants;

  /// Symbol-overlap edges for the current change set. Injected per
  /// change-set via [withSymbolEdges]; absent from the base engine built
  /// from history alone. Stored fully-symmetric (both directions present)
  /// so neighbour lookups are a single map access.
  /// Used in two places:
  ///   - [_buildRho] proxies heat from unknown (new/untracked) source
  ///     paths through their symbol-linked known graph nodes.
  ///   - [_deriveNewPathPhi] computes a derived phi for new paths so they
  ///     appear in diffusion output even though they aren't graph nodes.
  final Map<String, Map<String, double>> symbolEdges;

  /// Per-file K-vector signatures from Alexandria, as a dense column
  /// store. Empty (`isEmpty == true`) when the engine was built
  /// without engram assets - the fallback path that keeps the engine
  /// working in cold-asset / test scenarios.
  /// When non-empty:
  ///   - Drives the EN axis in the Born mixer (semantic content
  ///     similarity between file pairs).
  ///   - Surfaced via [wellOf] for tagging and prompt annotations:
  ///     callers can ask "what semantic basin does file X live in?".
  /// Built once per HEAD inside the resolver; persisted to disk across
  /// app launches so repo reopens hit the cache.
  final EngramFileKTable perFileKVectors;

  /// Monotonic id of this engine instance. Two engines with the same
  /// revision share the same underlying graph topology and coupling — so
  /// any downstream cache keyed on `manifoldRevision` stays valid across
  /// overlays like [withSymbolEdges]. Bumps on every fresh
  /// [buildFromStats]; does NOT bump on symbol-edge derivation (by design
  /// — symbol edges live in a sidecar, never touch the core Laplacian).
  final int manifoldRevision;

  /// Per-engine basis cache. Shared with instances derived via
  /// [withSymbolEdges] so symbol-edge overlays don't cost a fresh build.
  /// Late-initialised (not a constructor parameter) so callers don't have
  /// to thread it through; the cache is a private implementation detail.
  final LruCache<_BasisCacheKey, Float64List> _basisCache;

  /// Per-engine spectral basis cache. Keyed by `k` — the requested
  /// number of low-frequency Laplacian eigenpairs. The graph itself is
  /// fixed for the lifetime of an engine instance (see [manifoldRevision]),
  /// so a single basis per k is enough. A fresh basis is computed lazily
  /// the first time [_getOrBuildSpectralBasis] is called for a given k.
  /// Shared with [withSymbolEdges] overlays — symbol edges live in a
  /// sidecar and never touch L_sym.
  final Map<int, SpectralBasis> _spectralCache;

  /// Lazy-computed per-k `SpectroGeometry` fingerprint. Holds the
  /// unified universality vector, RMT/persistence/dim/zeta reports,
  /// and the 62-bit content hash. Populated on first call to
  /// [spectrogeometry] for a given `k`. Keyed by the same `k` as
  /// [_spectralCache] so the basis and its geometric read are
  /// guaranteed coherent.
  final Map<int, sg_lib.SpectroGeometry> _spectrogeometryCache = {};

  LogosGit._({
    required this.graph,
    required this.transportGraph,
    required this.nodePaths,
    required this.pathToId,
    required this.mixer,
    required this.perFileMetrics,
    required this.stats,
    required this.integrityByPath,
    this.couplingConstants = CouplingConstants.prior,
    this.symbolEdges = const {},
    EngramFileKTable? perFileKVectors,
    int? manifoldRevision,
    LruCache<_BasisCacheKey, Float64List>? basisCache,
    Map<int, SpectralBasis>? spectralCache,
  })  : perFileKVectors = perFileKVectors ?? _emptyTable,
        manifoldRevision = manifoldRevision ?? ++_logosGitRevisionCounter,
        _basisCache = basisCache ??
            LruCache<_BasisCacheKey, Float64List>(
                maxSize: _kChebyshevBasisCacheSize),
        _spectralCache = spectralCache ?? <int, SpectralBasis>{};

  /// Singleton empty K-table used when no engram assets are loaded.
  /// Avoids per-engine empty allocations and ensures the field is
  /// non-nullable on all code paths.
  static final EngramFileKTable _emptyTable = EngramFileKTable.empty(0);

  /// Nearest Alexandria well for [path], or null if the engine wasn't
  /// built with engram K-vectors / the file failed to encode. The
  /// returned name is the well's label (e.g. "computing", "well_43").
  String? wellOf(String path) => perFileKVectors.wellOf(path);

  /// Return a copy of this engine aware of symbol-overlap edges for the
  /// current change set. Cheap - shares the immutable graph; only the
  /// edge map is new. The symmetrisation step here means every caller
  /// can do a single `symbolEdges[path]` lookup instead of checking
  /// both triangle directions.
  LogosGit withSymbolEdges(Map<String, Map<String, double>> sym) {
    if (sym.isEmpty) return this;
    // Expand upper-triangle storage -> fully symmetric.
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
      transportGraph: transportGraph,
      nodePaths: nodePaths,
      pathToId: pathToId,
      mixer: mixer,
      perFileMetrics: perFileMetrics,
      stats: stats,
      integrityByPath: integrityByPath,
      couplingConstants: couplingConstants,
      symbolEdges: expanded,
      perFileKVectors: perFileKVectors,
      manifoldRevision: manifoldRevision,
      basisCache: _basisCache,
      spectralCache: _spectralCache,
    );
  }

  /// Fetch (or build) the Chebyshev basis `T_k·ρ` for k=0..K on this
  /// engine's graph. Hits the per-engine LRU cache on content-identical
  /// ρ; misses fall through to [chebyshevBasis] and insert the result.
  ///
  /// Callers that want a heat-kernel solution at a single temperature
  /// and are confident ρ won't repeat should keep using
  /// [chebyshevDiffuse] directly — the basis path pays a small detach
  /// overhead that only pays back when the same ρ is queried at
  /// multiple temperatures or more than once in a session.
  Float64List _getOrBuildBasis(Float64List rho, int K) {
    final key = (rhoFingerprint: _fingerprintRho(rho), K: K);
    final cached = _basisCache.get(key);
    if (cached != null) return cached;
    final built = chebyshevBasis(graph: graph, rho: rho, K: K);
    _basisCache.put(key, built);
    return built;
  }

  /// Fetch (or build) the spectral basis — top-`k` smallest eigenpairs
  /// of `L_sym` on this engine's graph. Once built, every diffusion
  /// query through it costs O(k·n) regardless of source ρ, temperature
  /// t, or how many axes are batched. The Lanczos build is one-time
  /// per engine instance per k value (graph topology is fixed for an
  /// engine's lifetime — see [manifoldRevision]).
  ///
  /// Returns null when the graph is too small to amortise the
  /// decomposition: for n < [kDefaultSpectralMinNodes], the per-query
  /// Chebyshev path beats a one-time Lanczos pass and there's no
  /// reason to incur the build cost.
  SpectralBasis? _getOrBuildSpectralBasis(int k) {
    if (graph.n < kDefaultSpectralMinNodes) return null;
    final clampedK = math.min(k, graph.n);
    final cached = _spectralCache[clampedK];
    if (cached != null) return cached;
    // File-level bases carry nodePaths by default — callers that ask
    // for the basis on an engine already have the path labelling
    // available, and `labelProject` / `phiForPath` are the ergonomic
    // win that makes this worth the cheap re-wrap.
    final built = SpectralBasis.fromGraph(
      graph,
      clampedK,
      nodePaths: nodePaths,
    );
    _spectralCache[clampedK] = built;
    return built;
  }

  /// Public accessor for this engine's spectral basis. Use this to
  /// read codebase-level *observables* the math gives us for free —
  /// the Fiedler partition (deepest natural cleavage), spectral
  /// communities (k-way clustering by L_sym low modes), heat trace
  /// (isospectral graph fingerprint), free energy of a focus,
  /// spectral entropy of a focus, diffusion distance between any
  /// two files, and spectral divergence between two source
  /// distributions. See [SpectralBasis] for the full menu.
  ///
  /// `k` defaults to the engine's `kDefaultSpectralBasisK` (20) — enough
  /// modes for the heat kernel's low-frequency regime; bump it if
  /// you want sharper community resolution.
  ///
  /// Returns null when the graph is below [kDefaultSpectralMinNodes] —
  /// observables on tiny graphs are uninformative anyway, and the
  /// caller should fall back to direct edge inspection.
  SpectralBasis? spectralBasis({int k = kDefaultSpectralBasisK}) =>
      _getOrBuildSpectralBasis(k);

  /// Unified geometric fingerprint of this engine's graph at basis
  /// size `k`. Bundles RMT classification, persistence diagram,
  /// spectral dimension, zeta invariants, the 6-archetype
  /// `universality` vector, and a 62-bit content hash into one
  /// cached [SpectroGeometry] object.
  ///
  /// Cost: one `spectrogeometry()` evaluation the first time a
  /// given `k` is requested (O(k·n) for the RMT + dim sweep, O(m
  /// log m) for persistence, O(k) for zeta). Cached thereafter —
  /// subsequent calls are O(1) map lookup.
  ///
  /// Returns `null` when the engine's graph is below
  /// [kDefaultSpectralMinNodes] (the underlying basis is also null).
  sg_lib.SpectroGeometry? spectrogeometry(
      {int k = kDefaultSpectralBasisK}) {
    final clampedK = math.min(k, graph.n);
    final cached = _spectrogeometryCache[clampedK];
    if (cached != null) return cached;
    final basis = _getOrBuildSpectralBasis(clampedK);
    if (basis == null) return null;
    final sg = sg_lib.spectrogeometry(graph, basis);
    _spectrogeometryCache[clampedK] = sg;
    return sg;
  }

  /// Convenience: build a [SpectralWalker] over this engine's spectral
  /// basis. Use it to sample concrete random-walk paths ("why this
  /// file surfaced") — the path-integral realisation of the heat
  /// kernel. Returns null when the engine's graph is too small to
  /// support a useful spectral basis.
  SpectralWalker? spectralWalker({
    int k = kDefaultSpectralBasisK,
    int? seed,
  }) {
    final basis = spectralBasis(k: k);
    if (basis == null) return null;
    return SpectralWalker(basis: basis, seed: seed);
  }

  /// Cached commit graph (built lazily from [LogosGitStats.perFileCommitIndices]).
  CsrGraph? _commitGraph;

  /// Cached commit-level spectral basis.
  SpectralBasis? _commitSpectralBasis;

  /// Cached commit-level geometric fingerprint. Parallel to
  /// [_spectrogeometryCache] but over the commit graph — one report
  /// per k. Lazily populated on first [commitSpectrogeometry] call.
  final Map<int, sg_lib.SpectroGeometry> _commitSpectrogeometryCache = {};

  /// Cached spatiotemporal basis tying file space × commit time.
  SpacetimeBasis? _spacetimeBasis;

  /// The commit graph derived from this engine's stats: one node per
  /// commit, edges weighted by Jaccard file-overlap and attenuated by
  /// temporal distance. Lazy-built, cached per engine lifetime.
  ///
  /// Returns null when the stats don't carry commit indices or the
  /// repo has fewer than [kDefaultSpectralMinNodes] commits (spectral path
  /// isn't amortised below that threshold).
  CsrGraph? commitGraph({int topK = 16, double timeDecay = 0.1}) {
    if (_commitGraph != null) return _commitGraph;
    final indices = stats.perFileCommitIndices;
    final total = stats.totalCommits;
    if (indices.isEmpty || total < kDefaultSpectralMinNodes) return null;
    _commitGraph = buildCommitGraph(
      perFileCommitIndices: indices,
      totalCommits: total,
      topK: topK,
      timeDecay: timeDecay,
    );
    return _commitGraph;
  }

  /// Commit-level [SpectralBasis] — the temporal analog of
  /// [spectralBasis]. Same Lanczos machinery, smaller graph (one node
  /// per commit). Returns null when the commit graph is below the
  /// spectral-amortisation threshold.
  SpectralBasis? commitSpectralBasis({int k = kDefaultSpectralBasisK}) {
    if (_commitSpectralBasis != null) return _commitSpectralBasis;
    final g = commitGraph();
    if (g == null || g.n < kDefaultSpectralMinNodes) return null;
    final clamped = math.min(k, g.n);
    _commitSpectralBasis = SpectralBasis.fromGraph(g, clamped);
    return _commitSpectralBasis;
  }

  /// Commit-level geometric fingerprint — the temporal twin of
  /// [spectrogeometry]. Returns the full [sg_lib.SpectroGeometry]
  /// report (RMT, persistence, spectral dimension, ζ, universality
  /// vector, fingerprint) computed over the commit graph.
  ///
  /// A repo can exhibit very different universality across the two
  /// scales: a crystalline file graph (tidy code) paired with a GOE
  /// commit graph (chaotic co-change history) is not rare and is a
  /// meaningful signal. Caching is keyed by `k` just like the file
  /// variant — one synthesis per resolved basis size.
  ///
  /// Returns `null` when the commit graph isn't available (repo
  /// below the spectral-amortisation threshold or no commit indices
  /// in stats).
  sg_lib.SpectroGeometry? commitSpectrogeometry(
      {int k = kDefaultSpectralBasisK}) {
    final g = commitGraph();
    if (g == null) return null;
    final clampedK = math.min(k, g.n);
    final cached = _commitSpectrogeometryCache[clampedK];
    if (cached != null) return cached;
    final basis = commitSpectralBasis(k: clampedK);
    if (basis == null) return null;
    final sg = sg_lib.spectrogeometry(g, basis);
    _commitSpectrogeometryCache[clampedK] = sg;
    return sg;
  }

  /// Paired (file, commit) universality reading. Bundles both scales
  /// into one `({file, commit})` record so callers that want to
  /// compare or combine the two reports don't have to thread them
  /// separately.
  ///
  /// Either side may be null — returns `(null, null)` when no basis
  /// is available; `(file, null)` when the commit graph isn't large
  /// enough (common on young repos); never returns `(null, file)`
  /// because the file graph is the primary and always resolves first.
  ({
    sg_lib.SpectroGeometry? file,
    sg_lib.SpectroGeometry? commit,
  }) spacetimeSpectrogeometry({int k = kDefaultSpectralBasisK}) {
    return (
      file: spectrogeometry(k: k),
      commit: commitSpectrogeometry(k: k),
    );
  }

  /// Joint file × commit-time spectral basis via Kronecker sum. The
  /// file graph is the spatial factor; the commit graph is the
  /// temporal factor. Every joint observable factors through the two
  /// separate bases — we never materialise an `n_file · n_commit` ×
  /// `n_file · n_commit` joint Laplacian.
  ///
  /// **Reading**: the codebase-as-spacetime view. A focus distributed
  /// over (file, commit) pairs diffuses simultaneously through
  /// architectural coupling and historical co-evolution. Joint
  /// observables (heat trace, free energy, spectral divergence on
  /// joint rho) answer questions like "has this PR's shape appeared
  /// before in repo history?" that neither factor alone can reach.
  ///
  /// Returns null when either factor is unavailable.
  SpacetimeBasis? spacetimeBasis({
    int kSpace = kDefaultSpectralBasisK,
    int kTime = kDefaultSpectralBasisK,
  }) {
    if (_spacetimeBasis != null) return _spacetimeBasis;
    final sp = spectralBasis(k: kSpace);
    if (sp == null) return null;
    final tm = commitSpectralBasis(k: kTime);
    if (tm == null) return null;
    _spacetimeBasis = SpacetimeBasis(space: sp, time: tm);
    return _spacetimeBasis;
  }

  /// Produce a [LogosState] — an immutable value capturing this
  /// engine's full spectral identity at the current moment. One int
  /// comparison (`stateA.signature == stateB.signature`) tells you
  /// whether two engines are in the same state.
  ///
  /// The snapshot is lazy: spectra are materialised on demand via the
  /// existing accessors (`spectralBasis`, `commitSpectralBasis`,
  /// `spacetimeBasis`), each of which returns null when its graph is
  /// below the spectral amortisation threshold. The resulting state
  /// carries whatever was populated; observers can test `isEmpty` or
  /// inspect individual fields.
  ///
  /// Use [LogosState.diff] to localise divergence between two
  /// snapshots — fast-path by signature, then per-factor, then
  /// per-file Hamming on the 8-bit fingerprint.
  LogosState snapshot({int k = kDefaultSpectralBasisK}) => LogosState(
        fileSpectrum: spectralBasis(k: k),
        commitSpectrum: commitSpectralBasis(k: k),
        joint: spacetimeBasis(kSpace: k, kTime: k),
        revision: manifoldRevision,
      );

  /// Ollivier-Ricci curvature field of this engine's file graph.
  /// Computed lazily via Sinkhorn-Knopp entropic Wasserstein (see
  /// [RicciField.sinkhorn]). Each edge carries a signed scalar:
  /// negative = bottleneck / bridge, positive = community-like,
  /// ~0 = expander. [RicciField.depth] is the deepest bottleneck
  /// scalar; [RicciField.mostNegativeEdges] returns the top-k bridge
  /// candidates for review-salience ranking or refactor surfacing.
  ///
  /// Cost is O(|E| · Sinkhorn_per_edge). Typical repos land in the
  /// seconds range; callers should cache the result per engine
  /// instance via [manifoldRevision].
  RicciField ricciField({double epsilon = 0.05, int iterations = 100}) {
    return RicciField.sinkhorn(
      graph,
      epsilon: epsilon,
      iterations: iterations,
      graphSignatureHint:
          Signature(lo: manifoldRevision & 0x7fffffff, hi: 0),
    );
  }

  /// 25D Kizuna bond fingerprint of this engine's joint (file ×
  /// commit) fingerprint histogram. Requires both [spectralBasis] and
  /// [commitSpectralBasis] to be materialisable with at least 9 modes
  /// each (8 non-trivial + the zero mode); returns null otherwise.
  ///
  /// The bond is the graded Walsh-Hadamard basis on (Z/2)^16: 8 lower
  /// marginals of the commit byte, 8 upper marginals of the file
  /// byte, 8 cross-coupling coefficients (one per mode-by-mode
  /// diagonal), plus the global FFFF parity. See
  /// [KizunaBond25D] for operations and
  /// [KizunaBond25D.familyProfile] for the 4-D compact signature.
  KizunaBond25D? kizunaBond() {
    final fileSpec = spectralBasis();
    final commitSpec = commitSpectralBasis();
    if (fileSpec == null || commitSpec == null) return null;
    if (fileSpec.k < 9 || commitSpec.k < 9) return null;
    final touchesPerFile = List<List<int>>.generate(
      nodePaths.length,
      (fileId) => stats.perFileCommitIndices[nodePaths[fileId]] ?? const [],
    );
    return kizunaBondOfSpectra(
      fileSpectrum: fileSpec,
      commitSpectrum: commitSpec,
      touchesPerFile: touchesPerFile,
    );
  }

  /// Construct the engine from per-file statistics. Nodes are all files
  /// with at least one observation from any axis; edges are the
  /// up to `edgeDensity` neighbours per node with the strongest mixed
  /// probability (top-K
  /// per node to keep the graph sparse).
  static LogosGit buildFromStats(
    LogosGitStats stats, {
    int edgeDensity = _defaultEdgeDensity,
    EngramFileKTable? perFileKVectors,
    // Probe hook. When non-null, sub-phase wallclock is written here so
    // cold-start probes can drill into which piece of the build is
    // actually expensive. Null in production — zero overhead (a single
    // null-check per phase).
    Map<String, int>? probeTimingsUs,
  }) {
    Stopwatch? probeSw;
    // tick(label) closes out the *preceding* phase and records its
    // elapsed time under `label`. So tick('_start') just arms the
    // clock (records nothing), tick('nodes') attributes everything
    // between _start and nodes to the "nodes" phase, and so on. The
    // label names the slice that just finished, not the one about
    // to begin.
    void tick(String phase) {
      if (probeTimingsUs == null) return;
      probeSw ??= Stopwatch();
      if (probeSw!.isRunning) {
        probeSw!.stop();
        probeTimingsUs[phase] =
            (probeTimingsUs[phase] ?? 0) + probeSw!.elapsedMicroseconds;
      }
      probeSw!.reset();
      probeSw!.start();
    }
    tick('_start');
    // Whether the EN axis is active for this build. Determined once
    // here so the build loop can branch cleanly without per-edge
    // null checks inside the hot path.
    final useEngram = perFileKVectors != null && !perFileKVectors.isEmpty;
    final caps = useEngram ? _defaultCapsWithEngram : _defaultCaps;
    final obsBufSize = caps.length;

    // Materialise the node set: union of files seen by any axis.
    // `coupling.paths` is the CSR's interned path list - using it
    // directly avoids triggering the lazy nested-map materialisation
    // just to read the key set.
    final pathSet = <String>{};
    pathSet.addAll(stats.touches.keys);
    pathSet.addAll(stats.rawTouches.keys);
    pathSet.addAll(stats.touchMass.keys);
    pathSet.addAll(stats.volatility.keys);
    pathSet.addAll(stats.coupling.paths);
    pathSet.addAll(stats.integrityByPath.keys);

    // Stable ordering - sort for determinism (helps debugging + caching).
    final nodePaths = pathSet.toList()..sort();
    final pathToId = <String, int>{};
    for (var i = 0; i < nodePaths.length; i++) {
      pathToId[nodePaths[i]] = i;
    }

    final n = nodePaths.length;
    tick('nodes');
    if (n == 0) {
      // Empty graph - engine does nothing useful but doesn't throw.
      return LogosGit._(
        graph: CsrGraph(
          n: 0,
          indptr: Int32List(1),
          indices: Int32List(0),
          values: Float64List(0),
        ),
        transportGraph: CsrGraph(
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
      touches: stats.touches,
      mean: stats.volMean,
      stddev: stats.volStddev,
    );

    // Pre-resolve every node's K-table row id once so the EN axis's
    // hot loop reads it from a flat Int32List instead of doing a
    // hashmap lookup per edge candidate. Rows that don't exist in the
    // table get -1 - silent for those pairs.
    final enRowIds = useEngram ? Int32List(n) : null;
    if (useEngram && enRowIds != null) {
      enRowIds.fillRange(0, n, -1);
      for (var i = 0; i < n; i++) {
        final row = perFileKVectors.rowOf(nodePaths[i]);
        if (row != null) enRowIds[i] = row;
      }
    }
    // EN axis - only constructed when we have K-vectors. When silent
    // we keep the variable null and the build loop simply skips the
    // 5th observation (mixer caps stay 4-element).
    final en =
        useEngram ? _EnAxis(rowIds: enRowIds!, table: perFileKVectors) : null;
    tick('axes');

    // Per-file curved metric (Whisper Harmonic, applied per-file).
    // For each file with sufficient touch history, fit AR(2) on the
    // inter-touch-gap series. The spectral radius `r_f` of the fit
    // measures how regular the file's touch pattern is - high when
    // periodic, low when chaotic. Edge weight
    // `W'[a,b] = W[a,b] * sqrt(r_a * r_b)` so heat flows preferentially
    // through files whose
    // own time-scale is well-defined. Files without enough history
    // fall through to the linear AR(2) fallback (spectral radius 0)
    // which would attenuate edges to zero - we coerce those to 1.0
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
      if (series == null || series.length < 3) continue; // need ?2 gaps
      final gaps = <double>[];
      for (var k = 1; k < series.length; k++) {
        gaps.add(series[k] - series[k - 1]);
      }
      final fit = engramFit(gaps);
      // Skip non-orbital fits - their spectral radius is meaningless
      // for the curvature interpretation. Files left out of the map
      // get curvature 1.0 (no attenuation, no boost).
      if (fit.isLinearFallback) continue;
      perFileMetrics[path] = fit;
    }
    tick('curvature');

    // (Per-file curvature factor - formerly an inline closure here -
    // is now materialised as a precomputed `Float64List curvatures`
    // inside the build loop below, keyed by node id. 1.0 when the
    // file has no AR(2) fit; otherwise the spectral radius clamped
    // to [0.5, 1.0] so the attenuation never drops an edge weight
    // by more than half.)

    // For each node, score all candidate neighbours and keep the top
    // `edgeDensity` by mixed probability. This is the critical step -
    // a fully-connected graph would be O(n^2) edges; we prune here.
    //
    //
    // Without these the inner loop is effectively O(N * n * d): the
    // original code did a
    // `for (final p in nodePaths) if (p.startsWith('$parent/'))` scan
    // *per node*, plus per-edge `firstWhere` linear probes during
    // symmetrise. On a 10k-file repo that's 100M+ string compares.
    //
    //   dirIndex     -> parent-dir -> ids of all nodes whose parent is
    //                  that dir. Replaces the O(n) prefix scan with
    //                  an O(|siblings|) lookup.
    //   pathSegments -> node id -> already-split path. Eliminates the
    //                  `a.split('/')` + `b.split('/')` allocation pair
    //                  inside what is the build's hottest scoring call.
    //   curvatures   -> node id -> cached AR(2)-spectral-radius factor.
    //                  Avoids repeated Map lookup per edge.
    //   f0Obs        -> node id -> F0 observation (depends only on the
    //                  destination; can be precomputed).
    final f0Obs = List<AxisObs>.generate(n, (i) => f0.observe(nodePaths[i]));
    final dirIndex = <String, List<int>>{};
    final transportSeedIndex = <String, List<int>>{};
    final pathSegments =
        List<List<String>>.generate(n, (i) => nodePaths[i].split('/'));
    // Precomputed [TransportRoles] per node. `logosTransportLane(a, b)`
    // internally rebuilds both roles per call — at n²-scale that's 44k+
    // redundant string normalisations + seed-key + 8 pattern-match
    // sweeps per build. The file_coupling pass already pays this cost
    // once and reuses via `logosTransportLaneOfRoles`; we do the same
    // here. This was the single biggest cold-start win identified by
    // the phase-timing probe (scoreLoop was 98 % of build, transport
    // was the dominant sub-cost of each pair).
    final transportRoles =
        List<TransportRoles>.generate(n, (i) => TransportRoles.of(nodePaths[i]));
    final curvatures = Float64List(n);
    // Well -> node-ids index. Same shape as `dirIndex` but partitioned
    // by Alexandria's learned semantic wells instead of directory
    // structure. This is the creative move: wells already group files
    // that talk about the same concepts (via K-space geometry). By
    // surfacing same-well siblings as EDGE CANDIDATES - not just
    // scoring existing candidates with the EN axis - we capture
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
      // the K-table column - pointer-bumping linear access.
      nodeWellIds = Int32List(n)..fillRange(0, n, -1);
      var maxWell = -1;
      for (var i = 0; i < n; i++) {
        final row = enRowIds![i];
        if (row < 0) continue;
        final wid = perFileKVectors.wellIdx[row];
        if (wid < 0) continue;
        nodeWellIds[i] = wid;
        if (wid > maxWell) maxWell = wid;
      }
      // Second pass: bucket nodes by their well id. List indexed by
      // original well id in [0, maxWell], so lookup is
      // `wellIdToNodes![wid]` - no hashmap. Empty bucket lists are null
      // to skip allocation
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
      // Seed key already computed inside TransportRoles.of above — read
      // it back instead of redoing the pattern work.
      final transportKey = transportRoles[i].seedKey;
      if (transportKey != null) {
        (transportSeedIndex[transportKey] ??= <int>[]).add(i);
      }
      final fit = perFileMetrics[p];
      if (fit == null) {
        curvatures[i] = 1.0;
      } else {
        final r = fit.spectralRadius;
        curvatures[i] = (!r.isFinite || r <= 0) ? 1.0 : r.clamp(0.5, 1.0);
      }
    }
    tick('indexes');

    final shadow = stats.shadowCoupling;
    final couplingConstants = calibrateCouplingConstants(
      nodePaths,
      (a, b) => stats.coupling.jaccardScoreOf(a, b),
      jaccardEdges: shadow == null
          ? (p) => stats.coupling.jaccardEntriesOf(p)
          : (p) => _blendedJaccardEdges(stats.coupling, shadow, p),
    );
    tick('coupling-calibration');

    // Pass 1: collect raw (neighbour, p_mix) pairs per row. Pass 2:
    // normalise by D^(-1/2) and write CSR.
    final degree = Float64List(n);
    final rawRows = List<List<_EdgeCandidate>>.generate(n, (_) => []);
    final transportMass = Float64List(n);
    final transportRows =
        List<Map<int, double>>.generate(n, (_) => <int, double>{});

    // Reused buffer fed to BornMixer.mix - saves one 4-element list
    // allocation per scored edge (~candidates * N allocations otherwise).
    // Sized to match the active mixer (4 axes by default, 5 with EN).
    final obsBuf =
        List<AxisObs>.filled(obsBufSize, AxisObs.silent, growable: false);

    // Probe counters — only updated when a timings map is requested.
    // In production (`probeTimingsUs == null`) these stay 0 and the
    // per-pair increments below are gated by a single null-check.
    final probeActive = probeTimingsUs != null;
    var probePairsScored = 0;
    var probeMixerCalls = 0;
    var probeTransportCalls = 0;

    for (var i = 0; i < n; i++) {
      final a = nodePaths[i];
      final integrityA = stats.integrityByPath[a] ?? 1.0;
      // Candidate set as ids - avoids the eventual pathToId hash lookup
      // we'd have done if we collected strings first. Set semantics
      // dedupe between the CC neighbours and the directory siblings.
      final candidates = <int>{};
      final transportCandidates = <int>{};
      // CSR-native row iteration: walks the `a` row's contiguous
      // colIdx slice and yields neighbour paths without materialising
      // a Map. ~10x faster than the old `coupling.jaccard[a]?.keys`
      // access on warm builds because there's no lazy-map population
      // and no per-edge map-entry allocation.
      for (final neighbour in stats.coupling.jaccardKeysOf(a)) {
        final id = pathToId[neighbour];
        if (id != null && id != i) candidates.add(id);
      }
      final segA = pathSegments[i];
      if (segA.length > 1) {
        // Parent directory via single lastIndexOf on the original path
        // string. The previous shape was `segA.sublist(0, len-1).join('/')`
        // — allocates a new list plus runs the join writer — which the
        // comment above claimed was faster than re-substring. It isn't:
        // `String.lastIndexOf` is one scan, `substring` is one allocation,
        // and neither touches the split array. This runs per-node per
        // edge-scoring pass, so the allocation churn was measurable on
        // larger repos.
        final cut = a.lastIndexOf('/');
        final parent = cut > 0 ? a.substring(0, cut) : '';
        final siblings = dirIndex[parent];
        if (siblings != null) {
          for (final id in siblings) {
            if (id != i) candidates.add(id);
          }
        }
      }

      // Well-siblings - semantic candidates. If this node has a
      // K-vector with a nearest well, consider every other node in
      // that well as a candidate too. Capped at [edgeDensity] per
      // node to match the downstream top-K sparsifier's budget -
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
      // Lookup is now an Int32List + List<List<int>> indexing pair -
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

      final transportKey = transportRoles[i].seedKey;
      if (transportKey != null) {
        final seeded = transportSeedIndex[transportKey];
        if (seeded != null) {
          for (final id in seeded) {
            if (id != i) transportCandidates.add(id);
          }
        }
      }

      if (candidates.isEmpty && transportCandidates.isEmpty) continue;

      // Curved metric: edge weight attenuated by sqrt(r_a * r_b). Both
      // factors already clamped to [0.5, 1.0] in `curvatures`, so the
      // scaling stays in that range - edges never boost past their
      // Born value, only proportionally attenuate.
      final curvA = curvatures[i];
      // Precompute ‖kRi[row_i]‖² once per outer node and reuse it
      // across every candidate j scored inside this loop. Previously
      // each `en.observeIds(i, j)` call re-accumulated `aMagSq` over
      // all P pairs from scratch — for C_avg candidates that's
      // P·(C_avg−1) redundant FMAs per node, multiplied across all
      // n outer iterations. Grimoire XXI — tile row A into L1 and
      // let the inner loop stream only row B per pair.
      final aMagSqI = en == null ? -1.0 : en.aMagSqFor(i);
      // Bounded min-heap (size ≤ edgeDensity). Previously we
      // collected every candidate into a growable list and ran a
      // full sort + sublist, which is O(C · log C). The heap drops
      // every candidate whose pMix is below the current K-th-best in
      // O(log K) — for large candidate counts this is a win, and it
      // eliminates the intermediate `scored` list + its sublist
      // allocation (Grimoire XIX — avoid allocation pressure on the
      // hottest build-time loop).
      final kept = <_EdgeCandidate>[];
      for (final j in candidates) {
        if (probeActive) probePairsScored++;
        final b = nodePaths[j];

        // Inline SP observe - uses cached pathSegments. Identical
        // semantics to _SpAxis.observe, but avoids two `.split('/')`
        // allocations per edge (~candidates * N per build).
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
          obsBuf[4] = aMagSqI > 0
              ? en.observeIdsWithMag(i, j, aMagSqI)
              : AxisObs.silent;
        }
        if (probeActive) probeMixerCalls++;
        var p = mixer.mix(obsBuf);
        // Merge the two `sqrt` calls into one: the algebra is
        // `sqrt(curvA·curvB) · sqrt(integrityA·integrityB) =
        // sqrt(curvA·curvB·integrityA·integrityB)`. Saves one sqrt
        // per scored candidate — ~500k sqrt calls saved on a typical
        // 10k-file build (Grimoire XIX).
        final integrityB = stats.integrityByPath[b] ?? 1.0;
        p *= math.sqrt(
              curvA * curvatures[j] * integrityA * integrityB,
            ) *
            logosPairPenaltyOfRoles(transportRoles[i], transportRoles[j]);
        if (probeActive) probeTransportCalls += 2;
        final rolesA = transportRoles[i];
        final rolesB = transportRoles[j];
        final lane = logosTransportLaneOfRoles(rolesA, rolesB, couplingConstants);
        if (lane != null && lane.strength > 0) {
          final transportWeight = (lane.strength *
                  math.max(integrityA, _kTransportIntegrityFloor) *
                  math.sqrt(integrityB))
              .clamp(0.0, 1.0)
              .toDouble();
          if (transportWeight > 0.01) {
            final prev = transportRows[i][j] ?? 0.0;
            if (transportWeight > prev) {
              transportRows[i][j] = transportWeight;
              transportMass[i] += transportWeight - prev;
            }
          }
        }
        final reverseLane = logosTransportLaneOfRoles(rolesB, rolesA, couplingConstants);
        if (reverseLane != null && reverseLane.strength > 0) {
          final reverseWeight = (reverseLane.strength *
                  math.max(integrityB, _kTransportIntegrityFloor) *
                  math.sqrt(integrityA))
              .clamp(0.0, 1.0)
              .toDouble();
          if (reverseWeight > 0.01) {
            final prev = transportRows[j][i] ?? 0.0;
            if (reverseWeight > prev) {
              transportRows[j][i] = reverseWeight;
              transportMass[j] += reverseWeight - prev;
            }
          }
        }
        if (p <= 0.5) continue; // only keep edges with positive lift
        if (kept.length < edgeDensity) {
          kept.add(_EdgeCandidate(j, p));
          _edgeHeapSiftUp(kept, kept.length - 1);
        } else if (p > kept[0].pMix) {
          kept[0] = _EdgeCandidate(j, p);
          _edgeHeapSiftDown(kept, 0);
        }
      }
      for (final j in transportCandidates) {
        if (candidates.contains(j)) continue;
        final b = nodePaths[j];
        final integrityB = stats.integrityByPath[b] ?? 1.0;
        final rolesA = transportRoles[i];
        final rolesB = transportRoles[j];
        final lane = logosTransportLaneOfRoles(rolesA, rolesB, couplingConstants);
        if (lane != null && lane.strength > 0) {
          final transportWeight = (lane.strength *
                  math.max(integrityA, _kTransportIntegrityFloor) *
                  math.sqrt(integrityB))
              .clamp(0.0, 1.0)
              .toDouble();
          if (transportWeight > 0.01) {
            final prev = transportRows[i][j] ?? 0.0;
            if (transportWeight > prev) {
              transportRows[i][j] = transportWeight;
              transportMass[i] += transportWeight - prev;
            }
          }
        }
        final reverseLane = logosTransportLaneOfRoles(rolesB, rolesA, couplingConstants);
        if (reverseLane != null && reverseLane.strength > 0) {
          final reverseWeight = (reverseLane.strength *
                  math.max(integrityB, _kTransportIntegrityFloor) *
                  math.sqrt(integrityA))
              .clamp(0.0, 1.0)
              .toDouble();
          if (reverseWeight > 0.01) {
            final prev = transportRows[j][i] ?? 0.0;
            if (reverseWeight > prev) {
              transportRows[j][i] = reverseWeight;
              transportMass[j] += reverseWeight - prev;
            }
          }
        }
      }

      // Top-K admission policy — `kept` has been maintained as a
      // min-heap of size ≤ edgeDensity throughout the candidate scan.
      // Heap order is not topological order for the downstream CSR
      // pack (which sorts by column index anyway), so we leave it
      // unordered here and only pay for one degree-sum sweep.
      rawRows[i] = kept;
      for (final e in kept) {
        degree[i] += e.pMix;
      }
    }
    tick('scoreLoop');
    if (probeTimingsUs != null) {
      probeTimingsUs['_probePairsScored'] = probePairsScored;
      probeTimingsUs['_probeMixerCalls'] = probeMixerCalls;
      probeTimingsUs['_probeTransportCalls'] = probeTransportCalls;
    }

    // Symmetrise: enforce W[i,j] = W[j,i] = max(W[i,j], W[j,i]).
    //
    // Original code did `rawRows[j].firstWhere(node==i)` per directed
    // edge - O(d) linear scan plus a second `indexWhere` on the upgrade
    // branch. With edgeDensity=24 and n=10k that's ~11M wasted compares.
    //
    // Build one int->position lookup per row up front; the symmetrise
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
    tick('symmetrise');

    // Pass 2: build CSR with D^(-1/2) fused into values.
    //
    // Total edge count is known after symmetrise - allocate the typed
    // buffers once at the right size instead of two `List<int>` /
    // `List<double>` growable buffers + `Int32List.fromList` /
    // `Float64List.fromList` copies (which is the common pattern that
    // wastes 2x the edge memory transiently).
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
      final row = rawRows[i]..sort((x, y) => x.node.compareTo(y.node));
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
    tick('csr');
    var totalTransportEdges = 0;
    for (var i = 0; i < n; i++) {
      totalTransportEdges += transportRows[i].length;
    }
    final transportIndptr = Int32List(n + 1);
    final transportIndices = Int32List(totalTransportEdges);
    final transportValues = Float64List(totalTransportEdges);
    var transportWrite = 0;
    for (var i = 0; i < n; i++) {
      final rowEntries = transportRows[i].entries.toList()
        ..sort((x, y) => x.key.compareTo(y.key));
      // Preserve directional lane strength when a row's total outgoing
      // transport mass is already bounded (< 1). Only renormalize rows
      // that would otherwise exceed unit mass so the directed operator
      // stays sub-stochastic: transport can attenuate, but never explode.
      final inv = transportMass[i] > 1.0 ? 1.0 / transportMass[i] : 1.0;
      for (final entry in rowEntries) {
        transportIndices[transportWrite] = entry.key;
        transportValues[transportWrite] = entry.value * inv;
        transportWrite++;
      }
      transportIndptr[i + 1] = transportWrite;
    }
    final transportGraph = CsrGraph(
      n: n,
      indptr: transportIndptr,
      indices: transportIndices,
      values: transportValues,
    );
    tick('transportCsr');

    return LogosGit._(
      graph: graph,
      transportGraph: transportGraph,
      nodePaths: nodePaths,
      pathToId: pathToId,
      mixer: mixer,
      perFileMetrics: perFileMetrics,
      stats: stats,
      integrityByPath: stats.integrityByPath,
      couplingConstants: couplingConstants,
      perFileKVectors: useEngram ? perFileKVectors : null,
    );
  }

  /// Per-file curvature factor - the file's spectral radius clamped to
  /// [0.5, 1.0] from the file's
  /// AR(2) inter-touch-gap fit, clamped to [0.5, 1.0]. 1.0 when the
  /// file has no fit (insufficient history). Mirrors the local
  /// function used inside [buildFromStats] so external callers (PR
  /// shape, X-ray, etc.) can interpret the same per-file rhythm
  /// signal without re-deriving it.
  List<GhostCoupling> ghostCouplings({
    double minScore = 0.05,
    int limit = 50,
  }) {
    final shadow = stats.shadowCoupling;
    if (shadow == null) return const [];
    final results = <GhostCoupling>[];
    for (final path in shadow.paths) {
      for (final entry in shadow.jaccardEntriesOf(path)) {
        if (entry.value < minScore) continue;
        if (stats.coupling.jaccardScoreOf(path, entry.key) > 0) continue;
        results.add(GhostCoupling(
          sourceFile: path,
          targetFile: entry.key,
          ghostJaccard: entry.value,
          effectiveWeight: entry.value * _kShadowDiscount,
        ));
      }
    }
    results.sort((a, b) => b.ghostJaccard.compareTo(a.ghostJaccard));
    return results.length > limit ? results.sublist(0, limit) : results;
  }

  /// Déjà vu score: how much of the diff's coupling topology overlaps
  /// with previously-rejected shadow topologies. Returns a value in
  /// [0, 1] where 0 = no overlap with ghost history, 1 = perfect
  /// reproduction of a discarded coupling pattern.
  double dejaVuScore(Set<String> diffPaths) {
    final shadow = stats.shadowCoupling;
    if (shadow == null || diffPaths.length < 2) return 0.0;
    var ghostHits = 0;
    var possiblePairs = 0;
    final paths = diffPaths.toList();
    for (var i = 0; i < paths.length; i++) {
      for (var j = i + 1; j < paths.length; j++) {
        final ghostScore = shadow.jaccardScoreOf(paths[i], paths[j]);
        if (ghostScore <= 0) continue;
        possiblePairs++;
        final realScore = stats.coupling.jaccardScoreOf(paths[i], paths[j]);
        if (realScore <= 0) ghostHits++;
      }
    }
    if (possiblePairs == 0) return 0.0;
    return ghostHits / possiblePairs;
  }

  /// Ghost edges that touch the given diff paths — the subset of ghost
  /// couplings relevant to a specific change, ranked by strength.
  List<GhostCoupling> ghostsForDiff(Set<String> diffPaths, {int limit = 10}) {
    final shadow = stats.shadowCoupling;
    if (shadow == null) return const [];
    final results = <GhostCoupling>[];
    final paths = diffPaths.toList();
    for (var i = 0; i < paths.length; i++) {
      for (var j = i + 1; j < paths.length; j++) {
        final score = shadow.jaccardScoreOf(paths[i], paths[j]);
        if (score <= 0) continue;
        if (stats.coupling.jaccardScoreOf(paths[i], paths[j]) > 0) continue;
        results.add(GhostCoupling(
          sourceFile: paths[i],
          targetFile: paths[j],
          ghostJaccard: score,
          effectiveWeight: score * _kShadowDiscount,
        ));
      }
    }
    results.sort((a, b) => b.ghostJaccard.compareTo(a.ghostJaccard));
    return results.length > limit ? results.sublist(0, limit) : results;
  }

  double curvature(String path) {
    final fit = perFileMetrics[path];
    if (fit == null) return 1.0;
    final r = fit.spectralRadius;
    if (!r.isFinite || r <= 0) return 1.0;
    return r.clamp(0.5, 1.0);
  }

  /// Recency-decayed touch weights - for each file with at least one
  /// commit-index in [LogosGitStats.perFileCommitIndices], the sum
  /// `sum exp(-(N - 1 - i) / tau)` over the file's touch indices, where
  /// N = `stats.totalCommits` and `tau = halfLifeCommits / ln(2)`. Files with
  /// zero recent activity (all touches outside the meaningful decay
  /// horizon) drop out of the map.
  /// Diffuse this through the engine to get the **field vector** - a
  /// dense phi over the coupling graph that represents "what direction is
  /// the codebase moving lately." Pass each PR's footprint cosine
  /// against this field to get its alignment ("with the field" vs
  /// "against the field").
  /// Cheap: O(sum_f |perFileCommitIndices[f]|), no diffusion. Diffusion is
  /// the caller's responsibility - pass the result to
  /// [diffuseWithAttribution] with a single axis label.
  Map<String, double> recentActivityWeights({int halfLifeCommits = 30}) {
    final useSemanticClock =
        stats.semanticCommitMass > 0 && stats.perFileCommitClock.isNotEmpty;
    if (!useSemanticClock && stats.totalCommits <= 0) return const {};
    // Memoise - same engine + same halfLife = identical output. The
    // rail, lede, and PR-shape signals all call this with the default
    // halfLife per render; recomputing every frame is wasted work.
    final cached = _activityCache[halfLifeCommits];
    if (cached != null) return cached;
    final tau = halfLifeCommits / math.ln2;
    final invTau = 1.0 / tau; // hoisted divide (Grimoire XIX)
    final newest = useSemanticClock
        ? stats.semanticCommitMass
        : (stats.totalCommits - 1).toDouble();
    final cutoff = halfLifeCommits * 6;

    // Precompute an `exp(-age·invTau)` lookup for integer-stepped ages
    // in `[0, cutoff]`. The hot inner loop runs once per touch-index
    // per file — for a mid-size repo this is tens of thousands of
    // transcendental calls. The LUT replaces each `math.exp` with a
    // bounded-interpolation table read (Grimoire XXV — small enough
    // to live in L1, accurate enough for a mass-weight that's fed
    // into rank-order comparisons). `halfLifeCommits * 6 + 1 ≤ 541`
    // entries ≈ 4.3 KB — well inside L1.
    final lutSize = cutoff + 1;
    final expLut = Float64List(lutSize);
    for (var i = 0; i < lutSize; i++) {
      expLut[i] = math.exp(-i * invTau);
    }

    final out = <String, double>{};
    // Duplicate the hot inner loop for the two source-series types
    // rather than materialise a Map<String, List<double>> for the
    // integer case just to unify the read path. The previous shape
    // copied every per-file index list into a fresh boxed double
    // list on every call — N heap-allocated lists per refresh.
    // Duplicating ~10 lines of arithmetic is much cheaper than
    // paying that copy pass.
    if (useSemanticClock) {
      for (final entry in stats.perFileCommitClock.entries) {
        var w = 0.0;
        final v = entry.value;
        for (var k = 0; k < v.length; k++) {
          final age = newest - v[k];
          if (age < 0) continue;
          if (age >= cutoff) continue;
          // Linear-interpolate the LUT for fractional ages (semantic
          // clock carries real-valued timestamps). At tau ≫ 1 the
          // interpolation error is below 1e-4, well under the noise
          // floor of downstream rank-order consumption.
          final floorIdx = age.floor();
          final frac = age - floorIdx;
          final lo = expLut[floorIdx];
          final hi = floorIdx + 1 < lutSize ? expLut[floorIdx + 1] : 0.0;
          w += lo + (hi - lo) * frac;
        }
        if (w > 0) out[entry.key] = w;
      }
    } else {
      for (final entry in stats.perFileCommitIndices.entries) {
        var w = 0.0;
        final v = entry.value;
        for (var k = 0; k < v.length; k++) {
          // Commit indices are integers; fractional part is always 0
          // in this branch so the LUT read is a direct index — no
          // interpolation arithmetic needed.
          final age = newest - v[k].toDouble();
          if (age < 0) continue;
          if (age >= cutoff) continue;
          w += expLut[age.toInt()];
        }
        if (w > 0) out[entry.key] = w;
      }
    }
    _activityCache[halfLifeCommits] = out;
    return out;
  }

  /// Memo for [recentActivityWeights] keyed by halfLifeCommits. Cap is
  /// generous (~3 distinct half-lives in flight at most across the
  /// feature surface); each entry is one map of file -> weight, ~80KB
  /// for a 10k-file repo.
  final Map<int, Map<String, double>> _activityCache = {};

  /// Build a reusable diffusion basis for the given source set. The
  /// Chebyshev expansion separates cleanly into:
  ///   - basis vectors `T_k(L) * rho` - t-independent, computed once
  ///   - scalar coefficients `c_k(t)` - the only t-dependent part
  /// So for temperature-slider UIs we compute the K+1 basis vectors
  /// once (O(K * |E|)), then per-frame just recombine at a new t
  /// (O(K * |V|) - a dozen float multiplies per node, no matvec).
  /// Returns null on empty graph / empty source set - callers should
  /// degrade gracefully (no rail, no temperature interaction).
  DiffusionBasis? buildBasis(Set<String> sourceFiles,
      {int K = kDefaultChebyshevK}) {
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

  /// Weighted variant of [buildBasis] - sources carry impact-weights
  /// (e.g. file churn for a commit-borrow query, where a high-line-
  /// change file should inject more heat than a one-line tweak).
  /// Returns null on empty graph / no in-graph sources.
  /// Like [buildBasis], the returned [DiffusionBasis] is t-independent
  /// - `recombine(t)` evaluates at any temperature in O(K * |V|) work.
  /// For a multi-temperature distillation (e.g. blending t=0.5/1.0/2.0
  /// to capture multi-scale neighborhood structure), build the basis
  /// ONCE per source set, then recombine three times. Compared to
  /// three separate `diffuseWeighted` calls, this saves roughly `2 * K`
  /// matvecs -
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
    return _buildDiffusionBasis(graph: graph, rho: rho, K: K, sources: sources);
  }

  /// Diffuse from the source file set. Returns every node with positive
  /// relevance, sorted descending by phi.
  /// [t] is diffusion time. Defaults to 1.0 (commit-review scope).
  ///    0.25 - "only the touched files"
  ///    1.0  - "1-hop neighbourhood"                 - commit review
  ///    2.0  - "2-hop + semantic"                    - code Q&A
  ///    4.0  - "wide historical"                     - codebase nav
  ///    inf  - "graph equilibrium"                   - repo summary
  /// [K] controls Chebyshev truncation. 20 is enough for t in [0, 10].
  /// [topK]: when non-null, returns at most this many results, using a
  /// bounded min-heap during scan - O(n log topK) instead of O(n log n)
  /// for the full sort. The result list is still sorted descending.

  /// Prune [results] to the largest prefix whose induced-subgraph coherence
  /// on the Logos graph stays at or above [minCoherence].
  /// Walks from the tail inward: if the full set is already coherent, returns
  /// [results] unchanged. Otherwise removes the weakest tail nodes one by
  /// one until the remaining set clears the threshold or only one node is
  /// left. Cost: O(k * d) per pruning step where d is average graph degree -
  /// fast for the small topK result sets this is called on.
  /// This turns coherence from a post-hoc metric into an active gate: the
  /// diffusion aperture closes when heat has spread into incoherent territory.
  List<RelevanceScore> _gateByCoherence(
    List<RelevanceScore> results,
    double minCoherence,
  ) {
    if (results.length < 2) return results;
    // Pre-extract paths once into a fixed `Set<String>` that we pop
    // from as we prune. The previous loop built a new lazy
    // `.take(k).map(...)` iterable on every iteration, and
    // `coherence` internally materialised it to a list — O(k) extra
    // allocation per step for a loop that already has O(k) steps
    // worst case, i.e. O(k²) cumulative allocation (Grimoire XIX).
    // A mutable set lets us drop the weakest tail in O(1) per step
    // while `coherence` reads it via its existing `Iterable<String>`
    // parameter contract.
    final paths = <String>{for (final r in results) r.path};
    var k = results.length;
    while (k > 1) {
      if (coherence(paths) >= minCoherence) break;
      paths.remove(results[k - 1].path);
      k--;
    }
    return k == results.length ? results : results.sublist(0, k);
  }

  /// Build and normalise a source vector rho from [weights] (path -> weight).
  /// Returns null when total injected mass is zero (nothing in the graph
  /// and no resolvable symbol proxy).
  /// For paths present in the graph: inject weight directly.
  /// For paths absent but reachable via [symbolEdges]: distribute weight
  /// across their known neighbours proportionally to symbol overlap score.
  /// This makes new/untracked files valid diffusion sources - heat enters
  /// the graph through the files they're structurally coupled to.
  Float64List? _buildRho(Map<String, double> weights) {
    final rho = Float64List(graph.n);
    var total = 0.0;
    // Track which indices received mass. Typical sources are k ≪ n
    // (a handful of primary files, a few symbol proxies), so the
    // final normalisation touches only O(k) entries instead of
    // sweeping the full n-length buffer — on a 10k-file graph with
    // 5 source paths, that's a 2000× reduction of the normalisation
    // scan (Grimoire XIX — avoid touching memory we don't need to).
    final writtenIds = <int>[];
    for (final entry in weights.entries) {
      final w = entry.value;
      if (w <= 0) continue;
      final id = pathToId[entry.key];
      if (id != null) {
        if (rho[id] == 0.0) writtenIds.add(id);
        rho[id] += w;
        total += w;
      } else if (symbolEdges.isNotEmpty) {
        // Unknown node - proxy through symbol-linked known neighbours.
        final neighbours = symbolEdges[entry.key];
        if (neighbours == null || neighbours.isEmpty) continue;
        for (final ne in neighbours.entries) {
          final nid = pathToId[ne.key];
          if (nid == null) continue;
          final proxied = w * ne.value;
          if (rho[nid] == 0.0) writtenIds.add(nid);
          rho[nid] += proxied;
          total += proxied;
        }
      }
    }
    if (total <= 0) return null;
    final invTotal = 1.0 / total;
    for (final id in writtenIds) {
      rho[id] *= invTotal;
    }
    return rho;
  }

  /// Joint builder for the focus ρ and its per-axis partition — both derived
  /// from the same total-mass denominator, so the identity
  /// `Σ_a perAxisRho[a][i] == focusRho[i]` holds by construction. This is
  /// the key invariant that lets [gatherEvidence] fuse the attribution
  /// matvec chain into the focus-basis matvec chain via
  /// [chebyshevBasisBatch]: recombining any column of the batched basis at
  /// temperature t yields a phi vector whose sum over axes equals the
  /// focus phi, matching what a separate attribution call would have
  /// returned. Returns null when no mass resolves into the graph.
  ({
    Float64List focusRho,
    Map<String, Float64List> perAxisRhos,
  })? _buildFocusAndAxisRhos(
    Map<String, double> weights,
    Map<String, String> axisLabelByPath,
  ) {
    // Pass 1: accumulate total mass (direct + symbol-proxied). Must match
    // [_buildRho]'s denominator so focusRho here is bit-identical to
    // what _buildRho produces for the same input.
    var totalMass = 0.0;
    for (final entry in weights.entries) {
      final w = entry.value;
      if (w <= 0) continue;
      final path = entry.key;
      if (pathToId.containsKey(path)) {
        totalMass += w;
      } else if (symbolEdges.isNotEmpty) {
        final neighbours = symbolEdges[path];
        if (neighbours == null || neighbours.isEmpty) continue;
        for (final ne in neighbours.entries) {
          if (pathToId.containsKey(ne.key)) totalMass += w * ne.value;
        }
      }
    }
    if (totalMass <= 0) return null;
    final invTotal = 1.0 / totalMass;
    final focusRho = Float64List(graph.n);
    final perAxis = <String, Float64List>{};
    final needAxes = axisLabelByPath.isNotEmpty;
    final symbolAxisLabel = LogosAxis.symbol.name;

    // Pass 2: write normalised contributions to both focusRho and (when
    // requested) the per-axis bucket. Unknown paths with symbol proxies
    // always route to the `symbol` axis bucket — same convention used by
    // [diffuseWithAttribution] so downstream dominantAxis callers see a
    // consistent label.
    for (final entry in weights.entries) {
      final w = entry.value;
      if (w <= 0) continue;
      final path = entry.key;
      final id = pathToId[path];
      if (id != null) {
        final contribution = w * invTotal;
        focusRho[id] += contribution;
        if (needAxes) {
          final axis = axisLabelByPath[path] ?? '_default';
          final rho = perAxis.putIfAbsent(axis, () => Float64List(graph.n));
          rho[id] += contribution;
        }
      } else if (symbolEdges.isNotEmpty) {
        final neighbours = symbolEdges[path];
        if (neighbours == null || neighbours.isEmpty) continue;
        for (final ne in neighbours.entries) {
          final nid = pathToId[ne.key];
          if (nid == null) continue;
          final contribution = (w * ne.value) * invTotal;
          focusRho[nid] += contribution;
          if (needAxes) {
            final rho = perAxis.putIfAbsent(
              symbolAxisLabel,
              () => Float64List(graph.n),
            );
            rho[nid] += contribution;
          }
        }
      }
    }
    return (focusRho: focusRho, perAxisRhos: perAxis);
  }

  /// Derive `dominantAxis` + `shareByAxis` maps from a per-axis phi set.
  /// Mirrors the provenance extraction in [diffuseWithAttribution], but
  /// operates on an already-computed per-axis phi map (the fused path in
  /// [gatherEvidence] builds phi via batched basis recombine instead of
  /// running its own matvec chain).
  ({
    Map<String, String> dominantAxis,
    Map<String, Map<String, double>> shareByAxis,
  }) _deriveAxisProvenance(Map<String, Float64List> perAxisPhi) {
    final dominantAxis = <String, String>{};
    final shareByAxis = <String, Map<String, double>>{};
    if (perAxisPhi.isEmpty) {
      return (dominantAxis: dominantAxis, shareByAxis: shareByAxis);
    }
    for (var i = 0; i < graph.n; i++) {
      var combined = 0.0;
      for (final phi in perAxisPhi.values) {
        final v = phi[i];
        if (v > 0) combined += v;
      }
      if (combined <= 0) continue;
      final path = nodePaths[i];
      var bestAxis = '';
      var bestVal = -1.0;
      final shares = <String, double>{};
      for (final entry in perAxisPhi.entries) {
        final ap = entry.value[i];
        if (ap <= 0) continue;
        shares[entry.key] = ap / combined;
        if (ap > bestVal) {
          bestVal = ap;
          bestAxis = entry.key;
        }
      }
      if (bestAxis.isNotEmpty) dominantAxis[path] = bestAxis;
      if (shares.isNotEmpty) shareByAxis[path] = shares;
    }
    return (dominantAxis: dominantAxis, shareByAxis: shareByAxis);
  }

  /// Derive phi scores for paths that are not graph nodes but are reachable
  /// via [symbolEdges]. Each new path's score is the symbol-overlap-weighted
  /// mean of its known neighbours' phi values - the same interpolation used
  /// in MDS for out-of-sample points.
  /// Returns an empty map when [symbolEdges] is empty or no new paths have
  /// any known neighbour with non-zero phi.
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

  List<MapEntry<String, int>> filesForAuthor(String author, {int limit = 20}) {
    final map = stats.authorTouches[author];
    if (map == null || map.isEmpty) return const [];
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.length <= limit ? entries : entries.sublist(0, limit);
  }

  List<MapEntry<String, int>> authorsForFile(String path, {int limit = 10}) {
    final out = <MapEntry<String, int>>[];
    for (final entry in stats.authorTouches.entries) {
      final count = entry.value[path];
      if (count != null && count > 0) {
        out.add(MapEntry(entry.key, count));
      }
    }
    out.sort((a, b) => b.value.compareTo(a.value));
    return out.length <= limit ? out : out.sublist(0, limit);
  }

  double spectralSpread(Set<String> files) {
    final basis = spectralBasis();
    if (basis == null || basis.pathToId == null || files.isEmpty) return -1;
    final weights = <String, double>{for (final f in files) f: 1.0};
    final proj = basis.labelProject(weights);
    var sum = 0.0;
    for (var i = 0; i < proj.length; i++) {
      sum += proj[i] * proj[i];
    }
    return math.sqrt(sum);
  }

  /// L2 distance between two file-set projections in spectral space.
  /// Reserved for branch-to-mainline divergence measurement.
  double semanticDistance(Set<String> filesA, Set<String> filesB) {
    final basis = spectralBasis();
    if (basis == null || basis.pathToId == null) return -1;
    final weightsA = <String, double>{
      for (final f in filesA) f: 1.0,
    };
    final weightsB = <String, double>{
      for (final f in filesB) f: 1.0,
    };
    final projA = basis.labelProject(weightsA);
    final projB = basis.labelProject(weightsB);
    if (projA.length != projB.length) return -1;
    var sum = 0.0;
    for (var i = 0; i < projA.length; i++) {
      final d = projA[i] - projB[i];
      sum += d * d;
    }
    return math.sqrt(sum);
  }

  List<RelevanceScore> diffuse(
    Set<String> sourceFiles, {
    double t = 1.0,
    int K = kDefaultChebyshevK,
    int? topK,
    double phiThreshold = 0.0,
    // When set, the result is pruned to the largest prefix whose induced
    // coherence on the Logos graph stays above this value. Prevents diffusion
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
        results =
            ([...results, ...extras]..sort((a, b) => b.phi.compareTo(a.phi)));
      }
    }

    if (coherenceGate != null) {
      results = _gateByCoherence(results, coherenceGate);
    }
    return results;
  }

  /// Diffuse from a WEIGHTED source map - the correct path for
  /// probe-based queries where different observables (primary, M-axis,
  /// Ab-axis) carry different starting amplitudes.
  /// Heat kernel is linear in rho, so callers used to sum N unit-mass
  /// diffusions scaled by their weight. That's mathematically fine but
  /// wastes O(N) matvec passes per review. This method builds a single
  /// properly-weighted rho and runs one Chebyshev expansion.
  /// `excludePaths` is filtered from the returned list - typically the
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
        results =
            ([...results, ...extras]..sort((a, b) => b.phi.compareTo(a.phi)));
      }
    }

    if (coherenceGate != null) {
      results = _gateByCoherence(results, coherenceGate);
    }
    return results;
  }

  /// Pack a phi vector into a sorted-descending list of [RelevanceScore],
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
      // Bounded min-heap of size <= topK. We keep the SMALLEST element
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
      // Sort the heap descending - only `topK` elements, cheap.
      heap.sort((a, b) => b.phi.compareTo(a.phi));
      return heap;
    }
    // Unbounded path - full sort. Same as the original behaviour.
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
  /// resulting phi through [fileTokenCounts] (file -> token -> count) to
  /// produce an expected-token distribution:
  ///     expected(token) = sum_f phi(f) * P(token | f)
  ///     P(token | f)    = fileTokenCounts[f][token] /
  ///                       sum_{t'} fileTokenCounts[f][t']
  /// Callers typically compare this against an observed distribution
  /// with `log((observed + eps) / (expected + eps))` to score surprise.
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

  /// **Born overlap** - the Logos-native inner product between two
  /// probes' diffused fields. Measures how much they interfere on the
  /// manifold: near 1 = they cover overlapping territory; near 0 =
  /// disjoint neighbourhoods.
  ///   I(phi_a, phi_b; t) = sum_v sqrt(phi_a(v) * phi_b(v))
  /// The sqrt is the Born amplitude - same operation `BornMixer.mix` uses
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

    // Born overlap: sum sqrt(a * b) for non-negative a, b. Equivalent to
    // the Bhattacharyya coefficient when a, b are probability
    // distributions. With our unit-normalised phi vectors the value is
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

  /// Helper: build phi from a weight map at temperature t. Returns null on
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
    int detailBudget = 48,
    bool includeSpectrum = true,
    bool includeSupportAttribution = true,
    bool includeSummaryDiagnostics = true,
    double phiThreshold = 0.0,
    double utilityHfSurpriseWeight = _utilityHfSurpriseWeight,
    double utilityTransportPullWeight = _utilityTransportPullWeight,
  }) {
    if (graph.n == 0 || focusWeights.isEmpty) return null;
    final attribWanted =
        includeSupportAttribution && axisLabelByPath.isNotEmpty;
    final focusAxes = _buildFocusAndAxisRhos(
      focusWeights,
      attribWanted ? axisLabelByPath : const {},
    );
    if (focusAxes == null) return null;
    final focusRho = focusAxes.focusRho;
    final perAxisRhos = focusAxes.perAxisRhos;
    final transportPhi = _transportProject(focusRho);

    final ambientWeights =
        recentActivityWeights(halfLifeCommits: ambientHalfLifeCommits);
    final ambientRho =
        ambientWeights.isEmpty ? null : _buildRho(ambientWeights);
    final axisOrder = perAxisRhos.keys.toList(growable: false);
    final hasAxes = attribWanted && axisOrder.isNotEmpty;

    // Try the spectral path first. When the engine's graph has been
    // queried at least once before (or is large enough to warrant the
    // one-time Lanczos build), every diffusion below — focus at t /
    // near / far, ambient at t, every axis at t — collapses to a
    // single O(k·n) projection + recombine on the cached spectral
    // basis. No edge traversals, no Chebyshev recurrence.
    //
    // Returns null on small graphs where Chebyshev's per-query
    // O(K·|E|) wins; the rest of the function then runs the existing
    // Chebyshev path with the basis-fusion / attribution batching that
    // [_buildFocusAndAxisRhos] sets up.
    final spectral = _getOrBuildSpectralBasis(kDefaultSpectralBasisK);

    // Pick near/far temperatures from the graph's own heat-capacity
    // peaks via `flankingScales`. When the amortised spectral basis
    // exists we use it; otherwise we build a one-shot lightweight
    // basis just for scale derivation (cheap on small graphs where
    // the amortised path isn't warranted). Bounds [0.35, 4.0] are
    // retained to keep the output within the diffusion regime the
    // rest of `gatherEvidence` is tuned for.
    final scaleBasis = spectral ??
        SpectralBasis.fromGraph(
          graph,
          math.min(kDefaultSpectralBasisK, graph.n),
        );
    final flank = scaleBasis.flankingScales(t);
    final nearT = math.max(0.35, math.min(flank.nearT, t));
    final farT = math.min(4.0, math.max(flank.farT, t));

    final Float64List focusPhi;
    final Float64List nearPhi;
    final Float64List farPhi;
    final Float64List ambientPhi;
    Map<String, Float64List>? perAxisPhi;

    if (spectral != null) {
      // Spectral path — projection coefficients are the universal
      // spectral coordinate of the source. Project once, recombine at
      // any number of temperatures for free.
      final focusCoeffs = spectral.project(focusRho);
      focusPhi = spectral.recombineFromProjection(focusCoeffs, t);
      if (includeSpectrum) {
        nearPhi = spectral.recombineFromProjection(focusCoeffs, nearT);
        farPhi = spectral.recombineFromProjection(focusCoeffs, farT);
      } else {
        nearPhi = Float64List(graph.n);
        farPhi = Float64List(graph.n);
      }
      ambientPhi = ambientRho != null
          ? spectral.diffuse(ambientRho, t)
          : Float64List(graph.n);
      if (hasAxes) {
        perAxisPhi = <String, Float64List>{};
        for (final axisLabel in axisOrder) {
          perAxisPhi[axisLabel] =
              spectral.diffuse(perAxisRhos[axisLabel]!, t);
        }
      }
    } else {
      // Chebyshev fallback — basis cache + per-axis fusion via
      // [chebyshevBasisBatch]. Same identity (Σ_a perAxisRho[a] ==
      // focusRho) makes one batched matvec chain cover focus + every
      // axis when both miss the cache.
      final focusKey = (rhoFingerprint: _fingerprintRho(focusRho), K: K);
      var focusBasis = _basisCache.get(focusKey);
      if (focusBasis == null && hasAxes) {
        final b = 1 + axisOrder.length;
        final rhoBatch = Float64List(graph.n * b);
        for (var i = 0; i < graph.n; i++) {
          rhoBatch[i * b] = focusRho[i];
        }
        for (var a = 0; a < axisOrder.length; a++) {
          final axisRho = perAxisRhos[axisOrder[a]]!;
          for (var i = 0; i < graph.n; i++) {
            rhoBatch[i * b + 1 + a] = axisRho[i];
          }
        }
        final batched = chebyshevBasisBatch(
            graph: graph, rhoBatch: rhoBatch, B: b, K: K);
        focusBasis = extractBasisColumn(
          batchedBasis: batched,
          n: graph.n,
          B: b,
          b: 0,
          K: K,
        );
        _basisCache.put(focusKey, focusBasis);
        perAxisPhi = <String, Float64List>{};
        for (var a = 0; a < axisOrder.length; a++) {
          final axisBasis = extractBasisColumn(
            batchedBasis: batched,
            n: graph.n,
            B: b,
            b: 1 + a,
            K: K,
          );
          perAxisPhi[axisOrder[a]] =
              recombineHeatPhi(graph: graph, basis: axisBasis, t: t, K: K);
        }
      } else {
        focusBasis ??= _getOrBuildBasis(focusRho, K);
        if (hasAxes) {
          final b = axisOrder.length;
          perAxisPhi = <String, Float64List>{};
          if (b == 1) {
            final phi = Float64List(graph.n);
            chebyshevDiffuse(
              graph: graph,
              rho: perAxisRhos[axisOrder[0]]!,
              phi: phi,
              t: t,
              K: K,
            );
            perAxisPhi[axisOrder[0]] = phi;
          } else {
            final rhoBatch = Float64List(graph.n * b);
            for (var a = 0; a < b; a++) {
              final axisRho = perAxisRhos[axisOrder[a]]!;
              for (var i = 0; i < graph.n; i++) {
                rhoBatch[i * b + a] = axisRho[i];
              }
            }
            final phiBatch = chebyshevDiffuseBatch(
              graph: graph,
              rhoBatch: rhoBatch,
              B: b,
              t: t,
              K: K,
            );
            for (var a = 0; a < b; a++) {
              final phi = Float64List(graph.n);
              for (var i = 0; i < graph.n; i++) {
                phi[i] = phiBatch[i * b + a];
              }
              perAxisPhi[axisOrder[a]] = phi;
            }
          }
        }
      }
      focusPhi =
          recombineHeatPhi(graph: graph, basis: focusBasis, t: t, K: K);
      if (includeSpectrum) {
        nearPhi = recombineHeatPhi(
            graph: graph, basis: focusBasis, t: nearT, K: K);
        farPhi = recombineHeatPhi(
            graph: graph, basis: focusBasis, t: farT, K: K);
      } else {
        nearPhi = Float64List(graph.n);
        farPhi = Float64List(graph.n);
      }
      if (ambientRho != null) {
        final ambientBasis = _getOrBuildBasis(ambientRho, K);
        ambientPhi = recombineHeatPhi(
            graph: graph, basis: ambientBasis, t: t, K: K);
      } else {
        ambientPhi = Float64List(graph.n);
      }
    }

    final AxisAttribution? supportAttribution;
    if (perAxisPhi != null) {
      final provenance = _deriveAxisProvenance(perAxisPhi);
      supportAttribution = AxisAttribution(
        combined: const [],
        perAxisPhi: perAxisPhi,
        nodePaths: nodePaths,
        dominantAxis: provenance.dominantAxis,
        shareByAxis: provenance.shareByAxis,
      );
    } else {
      supportAttribution = null;
    }

    var focusMass = 0.0;
    var ambientMass = 0.0;
    var transportMass = 0.0;
    var nearMass = 0.0;
    var farMass = 0.0;
    for (var i = 0; i < graph.n; i++) {
      if (focusPhi[i] > 0) focusMass += focusPhi[i];
      if (ambientPhi[i] > 0) ambientMass += ambientPhi[i];
      if (transportPhi[i] > 0) transportMass += transportPhi[i];
      if (includeSpectrum) {
        if (nearPhi[i] > 0) nearMass += nearPhi[i];
        if (farPhi[i] > 0) farMass += farPhi[i];
      }
    }

    final focusDerived = _deriveNewPathPhi(focusPhi);
    final transportDerived = _deriveNewPathPhi(transportPhi);
    final ambientDerived = ambientRho == null
        ? const <String, double>{}
        : _deriveNewPathPhi(ambientPhi);
    final nearDerived =
        includeSpectrum ? _deriveNewPathPhi(nearPhi) : const <String, double>{};
    final farDerived =
        includeSpectrum ? _deriveNewPathPhi(farPhi) : const <String, double>{};
    final focusPaths = <String>{
      for (final entry in focusWeights.entries)
        if (entry.value > 0) entry.key,
    };
    // Precompute transport roles per focus path ONCE — the ranked loop
    // below calls `_hasWitnessCarrierLane*` `graph.n` times, and each
    // call previously rebuilt the roles for every focus path. Budget
    // for a 94-focus × 426-node diff: 40k fresh TransportRoles per
    // gatherEvidence call = seconds. Precomputing collapses this to
    // `|focusPaths|` role builds, amortised across the loop.
    final focusRoles = [
      for (final p in focusPaths) (path: p, roles: TransportRoles.of(p)),
    ];

    final ranked = <LogosEvidenceScore>[];
    for (var i = 0; i < graph.n; i++) {
      final path = nodePaths[i];
      if (excludePaths.contains(path)) continue;
      final support =
          focusMass > 0 && focusPhi[i] > 0 ? focusPhi[i] / focusMass : 0.0;
      final lowFrequencySupport = includeSpectrum
          ? (farMass > 0 && farPhi[i] > 0 ? farPhi[i] / farMass : 0.0)
          : support;
      final nearSupport = includeSpectrum
          ? (nearMass > 0 && nearPhi[i] > 0 ? nearPhi[i] / nearMass : 0.0)
          : support;
      final highFrequencySurprise = includeSpectrum
          ? math.max(0.0, nearSupport - lowFrequencySupport)
          : 0.0;
      final ambient = ambientMass > 0 && ambientPhi[i] > 0
          ? ambientPhi[i] / ambientMass
          : 0.0;
      final transportPull = transportPhi[i].clamp(0.0, 1.0).toDouble();
      final transportedSupport = transportMass > 0 && transportPhi[i] > 0
          ? transportPhi[i] / transportMass
          : 0.0;
      final innovationResidual = math.max(0.0, support - transportedSupport);
      // Build candidate roles once per loop body. Only pay the cost
      // if the witness-residual branch could possibly matter — when
      // transportedSupport > support the witness channel is active.
      final maybeWitness = transportedSupport > support;
      final witnessResidual = maybeWitness &&
              _hasWitnessCarrierLaneFast(
                path,
                TransportRoles.of(path),
                focusRoles,
              )
          ? math.max(0.0, transportedSupport - support)
          : 0.0;
      final transportSignal = math.max(transportPull, transportedSupport);
      if (support <= phiThreshold &&
          ambient <= phiThreshold &&
          transportSignal <= _kTransportFloor) {
        continue;
      }
      final rawSurplus = support - lambda * ambient;
      final surplus = rawSurplus > 0 ? rawSurplus : 0.0;
      final integrity = integrityByPath[path] ?? kNeutralIntegrity;
      final rescue = _companionRescueScore(
        support: support,
        integrity: integrity,
        transportPull: transportPull,
      );
      ranked.add(LogosEvidenceScore(
        path: path,
        support: support,
        ambient: ambient,
        transportPull: transportPull,
        transportedSupport: transportedSupport,
        innovationResidual: innovationResidual,
        witnessResidual: witnessResidual,
        lowFrequencySupport: lowFrequencySupport,
        highFrequencySurprise: highFrequencySurprise,
        rawSurplus: rawSurplus,
        surplus: surplus,
        integrity: integrity,
        utility: math.max(
          surplus * integrity +
              utilityHfSurpriseWeight * highFrequencySurprise +
              utilityTransportPullWeight * transportPull,
          rescue,
        ),
        higherOrderLift: 0.0,
        reducibilityGap: 0.0,
        dominantAxis: supportAttribution?.dominantAxis[path],
        axisShares: supportAttribution?.shareByAxis[path],
        sidecars: const [],
      ));
    }

    for (final entry in focusDerived.entries) {
      final path = entry.key;
      if (excludePaths.contains(path)) continue;
      final support =
          focusMass > 0 && entry.value > 0 ? entry.value / focusMass : 0.0;
      final lowFrequencySupport = includeSpectrum
          ? (farMass > 0 && (farDerived[path] ?? 0) > 0
              ? (farDerived[path] ?? 0) / farMass
              : 0.0)
          : support;
      final nearSupport = includeSpectrum
          ? (nearMass > 0 && (nearDerived[path] ?? 0) > 0
              ? (nearDerived[path] ?? 0) / nearMass
              : 0.0)
          : support;
      final highFrequencySurprise = includeSpectrum
          ? math.max(0.0, nearSupport - lowFrequencySupport)
          : 0.0;
      final ambientRaw = ambientDerived[path] ?? 0.0;
      final ambient =
          ambientMass > 0 && ambientRaw > 0 ? ambientRaw / ambientMass : 0.0;
      final transportPull =
          (transportDerived[path] ?? 0.0).clamp(0.0, 1.0).toDouble();
      final transportedSupport =
          transportMass > 0 && (transportDerived[path] ?? 0.0) > 0
              ? (transportDerived[path] ?? 0.0) / transportMass
              : 0.0;
      final innovationResidual = math.max(0.0, support - transportedSupport);
      final maybeWitness = transportedSupport > support;
      final witnessResidual = maybeWitness &&
              _hasWitnessCarrierLaneFast(
                path,
                TransportRoles.of(path),
                focusRoles,
              )
          ? math.max(0.0, transportedSupport - support)
          : 0.0;
      final transportSignal = math.max(transportPull, transportedSupport);
      if (support <= phiThreshold &&
          ambient <= phiThreshold &&
          transportSignal <= _kTransportFloor) {
        continue;
      }
      final rawSurplus = support - lambda * ambient;
      final surplus = rawSurplus > 0 ? rawSurplus : 0.0;
      final integrity = integrityByPath[path] ?? kNeutralIntegrity;
      final rescue = _companionRescueScore(
        support: support,
        integrity: integrity,
        transportPull: transportPull,
      );
      ranked.add(LogosEvidenceScore(
        path: path,
        support: support,
        ambient: ambient,
        transportPull: transportPull,
        transportedSupport: transportedSupport,
        innovationResidual: innovationResidual,
        witnessResidual: witnessResidual,
        lowFrequencySupport: lowFrequencySupport,
        highFrequencySurprise: highFrequencySurprise,
        rawSurplus: rawSurplus,
        surplus: surplus,
        integrity: integrity,
        utility: math.max(
          surplus * integrity +
              utilityHfSurpriseWeight * highFrequencySurprise +
              utilityTransportPullWeight * transportPull,
          rescue,
        ),
        higherOrderLift: 0.0,
        reducibilityGap: 0.0,
        sidecars: const [],
      ));
    }

    ranked.sort((a, b) {
      final byUtility = b.utility.compareTo(a.utility);
      if (byUtility != 0) return byUtility;
      final bySupport = b.support.compareTo(a.support);
      if (bySupport != 0) return bySupport;
      return a.path.compareTo(b.path);
    });
    final detailCap = math.max(topK ?? 0, detailBudget);
    if (detailCap > 0 && ranked.isNotEmpty) {
      final focusDetailPaths = focusWeights.entries.toList(growable: false)
        ..sort((a, b) {
          final byWeight = b.value.abs().compareTo(a.value.abs());
          if (byWeight != 0) return byWeight;
          return a.key.compareTo(b.key);
        });
      final focusKeep = math.min(
        focusDetailPaths.length,
        math.max(8, math.min(24, detailBudget ~/ 2)),
      );
      final detailedPaths = <String>{
        for (final entry in focusDetailPaths.take(focusKeep)) entry.key,
        for (final score in ranked.take(detailCap)) score.path,
      };
      for (var i = 0; i < ranked.length && detailedPaths.isNotEmpty; i++) {
        final score = ranked[i];
        if (!detailedPaths.remove(score.path)) continue;
        final higherOrder =
            _higherOrderSignal(score.path, focusPaths, support: score.support);
        final witnesses = _buildWitnesses(
          score.path,
          focusPaths,
          lowFrequencySupport: score.lowFrequencySupport,
          highFrequencySurprise: score.highFrequencySurprise,
          higherOrderLift: higherOrder.lift,
          reducibilityGap: higherOrder.gap,
          hyperedge: higherOrder.hyperedge,
          dominantAxis: score.dominantAxis,
          axisShares: score.axisShares,
        );
        final sidecars = _buildMetricSidecars(
          score.path,
          focusPaths,
          integrity: score.integrity,
          higherOrderLift: higherOrder.lift,
          reducibilityGap: higherOrder.gap,
          hyperedge: higherOrder.hyperedge,
        );
        ranked[i] = LogosEvidenceScore(
          path: score.path,
          support: score.support,
          ambient: score.ambient,
          transportPull: score.transportPull,
          transportedSupport: score.transportedSupport,
          innovationResidual: score.innovationResidual,
          witnessResidual: score.witnessResidual,
          lowFrequencySupport: score.lowFrequencySupport,
          highFrequencySurprise: score.highFrequencySurprise,
          rawSurplus: score.rawSurplus,
          surplus: score.surplus,
          integrity: score.integrity,
          utility: score.utility,
          higherOrderLift: higherOrder.lift,
          reducibilityGap: higherOrder.gap,
          dominantAxis: score.dominantAxis,
          axisShares: score.axisShares,
          witnesses: witnesses,
          sidecars: sidecars,
        );
      }
    }
    final limited = topK != null && topK > 0 && ranked.length > topK
        ? ranked.sublist(0, topK)
        : ranked;
    final coherenceScore = includeSummaryDiagnostics
        ? (limited.isEmpty
            ? 1.0
            : coherence(limited.take(12).map((r) => r.path)))
        : 1.0;
    final stability =
        includeSummaryDiagnostics ? diffuseStability(focusWeights, t: t) : 1.0;
    final sourceAlignment =
        includeSummaryDiagnostics && ambientWeights.isNotEmpty
            ? bornOverlap(focusWeights, ambientWeights, t: t, K: K)
            : null;
    final fieldAlignment = includeSummaryDiagnostics && ambientRho != null
        ? _bornOverlapFromPhi(
            focusPhi,
            ambientPhi,
            focusMass: focusMass,
            ambientMass: ambientMass,
          )
        : null;

    final flowRollup = includeSummaryDiagnostics
        ? rollupEvidenceTopology(limited, maxEntries: 12)
        : const LogosEvidenceRollup(
            transportPull: 0.0,
            lowFrequencySupport: 0.0,
            highFrequencySurprise: 0.0,
            higherOrderLift: 0.0,
            reducibilityGap: 0.0,
          );
    final flowDiagnostics = includeSummaryDiagnostics
        ? computeLogosFlowDiagnostics(
            coherence: coherenceScore,
            stability: stability,
            sourceAlignment: sourceAlignment,
            fieldAlignment: fieldAlignment,
            lowFrequencySupport: flowRollup.lowFrequencySupport,
            highFrequencySurprise: flowRollup.highFrequencySurprise,
            higherOrderLift: flowRollup.higherOrderLift,
            reducibilityGap: flowRollup.reducibilityGap,
            witnessKindFractions: flowRollup.witnessKindFractions,
          )
        : const LogosFlowDiagnostics(
            gradientMass: 0.0,
            curlMass: 0.0,
            harmonicMass: 0.0,
            structuralStress: 0.0,
            witnessEntropy: 0.0,
            confidence: 0.0,
          );
    final metricSidecars = includeSummaryDiagnostics
        ? _rollupMetricSidecars(limited)
        : const <LogosMetricSidecar>[];
    final transport = includeSummaryDiagnostics
        ? _rollupTransportSummary(
            limited,
            focusRho: focusRho,
          )
        : const LogosTransportSummary();
    final semanticMotion = includeSummaryDiagnostics
        ? _rollupSemanticMotionSummary(
            limited,
            excludePaths: focusPaths,
          )
        : const LogosSemanticMotionSummary();
    final witnessResidual = includeSummaryDiagnostics
        ? _rollupWitnessResidualSummary(limited)
        : const LogosWitnessResidualSummary();
    final inquiryPlan = includeSummaryDiagnostics
        ? _buildInquiryPlan(
            limited,
            transport: transport,
            focusPaths: focusPaths,
          )
        : const LogosInquiryPlan();
    final residualByPath = <String, LogosResidualView>{
      for (final score in limited)
        score.path: LogosResidualView(
          path: score.path,
          support: score.support,
          ambient: score.ambient,
          utility: score.utility,
          integrity: score.integrity,
          transportPull: score.transportPull,
          transportedSupport: score.transportedSupport,
          innovationResidual: score.innovationResidual,
          witnessResidual: score.witnessResidual,
          lowFrequencySupport: score.lowFrequencySupport,
          highFrequencySurprise: score.highFrequencySurprise,
          higherOrderLift: score.higherOrderLift,
          reducibilityGap: score.reducibilityGap,
          dominantAxis: score.dominantAxis,
          witnesses: score.witnesses,
          sidecars: score.sidecars,
        ),
    };
    final transportPullByPath = {
      for (final entry in residualByPath.entries)
        entry.key: entry.value.transportPull,
    };
    return LogosEvidenceQueryResult(
      ranked: limited,
      residualByPath: residualByPath,
      metricSidecars: metricSidecars,
      transport: transport,
      semanticMotion: semanticMotion,
      witnessResidual: witnessResidual,
      transportPullByPath: transportPullByPath,
      inquiryPlan: inquiryPlan,
      sourceAlignment: sourceAlignment,
      fieldAlignment: fieldAlignment,
      sourceSurprise: sourceAlignment == null
          ? null
          : (1.0 - sourceAlignment).clamp(0.0, 1.0).toDouble(),
      fieldSurprise: fieldAlignment == null
          ? null
          : (1.0 - fieldAlignment).clamp(0.0, 1.0).toDouble(),
      coherence: coherenceScore,
      stability: stability,
      flowDiagnostics: flowDiagnostics,
      witnessSyndrome: includeSummaryDiagnostics
          ? computeLogosWitnessSyndrome(
              flowRollup,
              witnessEntropy: flowDiagnostics.witnessEntropy,
            )
          : const LogosWitnessSyndrome(
              coverage: 0.0,
              corroboration: 0.0,
              disagreement: 0.0,
            ),
      supportAttribution: supportAttribution,
    );
  }

  /// Recurrent [gatherEvidence] with self-tuning utility weights.
  ///
  /// One rule, borrowed from Logos 0D: each weight tracks its signal's
  /// residual-weighted mean — the correlation between that signal and
  /// what's currently unexplained. Same principle as
  /// `w = |p−0.5| · min(log1p(n), cap)` in the Whisper codec tower:
  /// confidence × evidence, no per-axis special cases.
  ///
  /// Convergence requires both novelty mass relaxation (the exploration
  /// is done) AND weight stability (the attention has settled).
  LogosRecurrentEvidenceResult gatherEvidenceRecurrent({
    required Map<String, double> focusWeights,
    Map<String, String> axisLabelByPath = const {},
    double t = 1.0,
    int K = kDefaultChebyshevK,
    int ambientHalfLifeCommits = 30,
    double lambda = 0.5,
    Set<String> excludePaths = const {},
    int? topK,
    int detailBudget = 48,
    bool includeSpectrum = true,
    bool includeSupportAttribution = true,
    bool includeSummaryDiagnostics = true,
    double phiThreshold = 0.0,
    int maxIterations = 6,
    double convergenceRatio = 0.1353352832366127, // math.exp(-2)
    void Function(RecurrentIterationReport)? onIteration,
  }) {
    final focus = Map<String, double>.from(focusWeights);
    final depth = <String, int>{for (final k in focus.keys) k: 0};
    final newSourcesPerIter = math.max(1, focusWeights.length ~/ 3);

    var hfW = _utilityHfSurpriseWeight;
    var tpW = _utilityTransportPullWeight;
    // Symmetric bounds: self-tuning can shift emphasis to 3× or ⅓ of
    // the prior, but can't annihilate or dominate. Same rule both axes.
    const weightBoundFactor = 3.0;
    final wClampLo = math.min(hfW, tpW) / weightBoundFactor;
    final wClampHi = math.max(hfW, tpW) * weightBoundFactor;
    // Stability epsilon derived from the bound range: settled when the
    // step is <1% of the allowed travel distance.
    final stabilityEpsilon = (wClampHi - wClampLo) * 0.01;

    // Promoted-source decay from the heat kernel's own timescale:
    // exp(-t) per depth. Focused t (small) → slow decay (promoted
    // sources stay strong). Broad t (large) → fast decay.
    final depthDecay = math.exp(-t);

    LogosEvidenceQueryResult? last;
    var ranIterations = 0;
    var finalNovelty = 0.0;
    var noveltyBaseline = 0.0;
    var converged = false;

    for (var iter = 0; iter < maxIterations; iter++) {
      // Adaptive EMA rate: 2/(iter+2). Fast early (the system knows
      // nothing), decelerating as it settles. Standard EMA derivation.
      final adaptRate = 2.0 / (iter + 2);

      final evidence = gatherEvidence(
        focusWeights: focus,
        axisLabelByPath: axisLabelByPath,
        t: t,
        K: K,
        ambientHalfLifeCommits: ambientHalfLifeCommits,
        lambda: lambda,
        excludePaths: excludePaths,
        topK: topK,
        detailBudget: detailBudget,
        includeSpectrum: includeSpectrum,
        includeSupportAttribution: includeSupportAttribution,
        includeSummaryDiagnostics: includeSummaryDiagnostics,
        phiThreshold: phiThreshold,
        utilityHfSurpriseWeight: hfW,
        utilityTransportPullWeight: tpW,
      );
      if (evidence == null) {
        return LogosRecurrentEvidenceResult(
          evidence: last,
          iterations: ranIterations,
          converged: true,
          discoveryDepth: depth,
          finalNoveltyMass: finalNovelty,
          adaptedHfSurpriseWeight: iter > 0 ? hfW : null,
          adaptedTransportPullWeight: iter > 0 ? tpW : null,
        );
      }
      last = evidence;
      ranIterations = iter + 1;

      final candidates = <_NoveltyCandidate>[];
      var noveltySum = 0.0;
      var hfCorr = 0.0;
      var tpCorr = 0.0;
      for (final score in evidence.ranked) {
        if (focus.containsKey(score.path)) continue;
        final r = score.innovationResidual;
        if (r <= 0) continue;
        noveltySum += r;
        hfCorr += r * score.highFrequencySurprise;
        tpCorr += r * score.transportPull;
        if (r >= _kSignalFloor) {
          candidates.add(_NoveltyCandidate(score.path, r));
        }
      }
      finalNovelty = noveltySum;
      if (iter == 0) noveltyBaseline = noveltySum;

      // Self-tune: weight tracks signal–residual correlation.
      final prevHf = hfW;
      final prevTp = tpW;
      if (noveltySum > 0) {
        hfW += adaptRate * (hfCorr / noveltySum - hfW);
        tpW += adaptRate * (tpCorr / noveltySum - tpW);
        hfW = hfW.clamp(wClampLo, wClampHi);
        tpW = tpW.clamp(wClampLo, wClampHi);
      }

      onIteration?.call(RecurrentIterationReport(
        iteration: ranIterations,
        noveltyMass: noveltySum,
        promotedPaths: candidates.length,
        hfWeight: hfW,
        tpWeight: tpW,
      ));

      final settled = math.max(
            (hfW - prevHf).abs(),
            (tpW - prevTp).abs(),
          ) <
          stabilityEpsilon;
      final noveltyConverged = noveltyBaseline > 0 &&
          noveltySum < noveltyBaseline * convergenceRatio;
      if (noveltyConverged && settled) {
        converged = true;
        break;
      }
      if (candidates.isEmpty) {
        converged = true;
        break;
      }

      candidates.sort((a, b) => b.novelty.compareTo(a.novelty));
      final iterDepth = iter + 1;
      final decay = math.pow(depthDecay, iterDepth).toDouble();
      for (final cand in candidates.take(newSourcesPerIter)) {
        if (focus.containsKey(cand.path)) continue;
        focus[cand.path] = cand.novelty * decay;
        depth[cand.path] = iterDepth;
      }
    }

    return LogosRecurrentEvidenceResult(
      evidence: last,
      iterations: ranIterations,
      converged: converged,
      discoveryDepth: depth,
      finalNoveltyMass: finalNovelty,
      adaptedHfSurpriseWeight: ranIterations > 1 ? hfW : null,
      adaptedTransportPullWeight: ranIterations > 1 ? tpW : null,
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

  _HigherOrderSignal _higherOrderSignal(
    String candidate,
    Set<String> focusPaths, {
    required double support,
  }) {
    if (focusPaths.isEmpty) return const _HigherOrderSignal();
    final supportingFocusPaths = [
      for (final source in focusPaths)
        if (source != candidate) source,
    ];
    if (supportingFocusPaths.length < 2) return const _HigherOrderSignal();
    final hyperedges = stats.hyperedgesByPath[candidate];
    if (hyperedges == null || hyperedges.isEmpty) {
      return const _HigherOrderSignal();
    }
    var bestLift = 0.0;
    var bestGap = 0.0;
    LogosCommitHyperedge? bestHyperedge;
    for (final edge in hyperedges) {
      var overlap = 0;
      var neighbourSpan = 0;
      for (final path in edge.paths) {
        if (path == candidate) continue;
        neighbourSpan++;
        if (focusPaths.contains(path)) overlap++;
      }
      if (overlap < 2) continue;
      final overlapRatio = neighbourSpan <= 0
          ? 0.0
          : (overlap / neighbourSpan).clamp(0.0, 1.0).toDouble();
      final supportFactor =
          (0.35 + 0.65 * support.clamp(0.0, 1.0)).clamp(0.35, 1.0).toDouble();
      // observerCount > 1 means this commit was reviewed by independent
      // humans — the co-occurrence is more likely deliberate. Log-scaled
      // so 2 reviewers ≈ 1.10x, 4 ≈ 1.20x — gentle, never penalizes.
      final observerLift = 1.0 + 0.14 * math.log(edge.observerCount);
      final lift = edge.weight * overlapRatio * supportFactor * observerLift;
      var pairwise = 0.0;
      var pairwiseN = 0;
      for (final source in supportingFocusPaths) {
        final s = stats.coupling.score(source, candidate);
        if (s > 0) {
          pairwise += s;
          pairwiseN++;
        }
      }
      final pairwiseMean = pairwiseN > 0 ? pairwise / pairwiseN : 0.0;
      final gap = math.max(0.0, lift - pairwiseMean);
      if (lift > bestLift) {
        bestLift = lift;
        bestGap = gap;
        bestHyperedge = edge;
      }
    }
    if (bestHyperedge == null) return const _HigherOrderSignal();
    return _HigherOrderSignal(
      lift: bestLift,
      gap: bestGap,
      hyperedge: bestHyperedge,
    );
  }

  List<LogosEvidenceWitness> _buildWitnesses(
    String path,
    Set<String> focusPaths, {
    required double lowFrequencySupport,
    required double highFrequencySurprise,
    required double higherOrderLift,
    required double reducibilityGap,
    required LogosCommitHyperedge? hyperedge,
    required String? dominantAxis,
    required Map<String, double>? axisShares,
  }) {
    final witnesses = <LogosEvidenceWitness>[];
    if (dominantAxis != null) {
      final share = axisShares?[dominantAxis] ?? 0.0;
      witnesses.add(LogosEvidenceWitness(
        kind: LogosWitnessKind.axis,
        label: dominantAxis,
        strength: share > 0 ? share : 0.35,
      ));
    }

    if (highFrequencySurprise > _kSignalFloor) {
      witnesses.add(LogosEvidenceWitness(
        kind: LogosWitnessKind.spectrum,
        label: 'high-frequency-residual',
        strength: highFrequencySurprise,
      ));
    }
    if (lowFrequencySupport > _kSignalFloor) {
      witnesses.add(LogosEvidenceWitness(
        kind: LogosWitnessKind.spectrum,
        label: 'multiscale-support',
        strength: lowFrequencySupport,
      ));
    }

    final integrity = integrityByPath[path] ?? kNeutralIntegrity;
    if (integrity < kNeutralIntegrity) {
      witnesses.add(LogosEvidenceWitness(
        kind: LogosWitnessKind.integrity,
        label: 'integrity-gate',
        strength: 1.0 - integrity,
        note: (stats.integrityReasonsByPath[path] ?? const <String>[])
            .take(2)
            .join(', '),
      ));
    }

    final relationWitnesses = <LogosEvidenceWitness>[];
    final transportWitnesses = <LogosEvidenceWitness>[];
    for (final source in focusPaths) {
      if (source == path) continue;
      final relation = logosRelationDescriptor(source, path);
      if (relation != null && relation.strength > 0) {
        relationWitnesses.add(LogosEvidenceWitness(
          kind: LogosWitnessKind.relation,
          label: relation.label,
          strength: relation.strength,
          sourcePaths: [source],
          sourcePath: source,
          targetPath: path,
          sourceRole: relation.sourceRole,
          targetRole: relation.targetRole,
          directional: relation.directional,
          note: relation.note,
        ));
      }
      final lane = logosTransportLane(source, path, couplingConstants);
      if (lane != null) {
        transportWitnesses.add(LogosEvidenceWitness(
          kind: LogosWitnessKind.transport,
          label: lane.label,
          strength: lane.strength,
          sourcePaths: [source],
          sourcePath: source,
          targetPath: path,
          sourceRole: lane.sourceRole,
          targetRole: lane.targetRole,
          directional: lane.directional,
          note: lane.note,
        ));
      }
    }

    int byWitness(LogosEvidenceWitness a, LogosEvidenceWitness b) {
      final byStrength = b.strength.compareTo(a.strength);
      if (byStrength != 0) return byStrength;
      final byLabel = a.label.compareTo(b.label);
      if (byLabel != 0) return byLabel;
      return (a.sourcePath ?? '').compareTo(b.sourcePath ?? '');
    }

    relationWitnesses.sort(byWitness);
    transportWitnesses.sort(byWitness);
    final seenRelationKeys = <String>{};
    for (final witness in relationWitnesses) {
      final key = '${witness.label}\u0000${witness.sourcePath ?? ''}';
      if (!seenRelationKeys.add(key)) continue;
      witnesses.add(witness);
      if (seenRelationKeys.length >= 2) break;
    }
    final seenTransportKeys = <String>{};
    for (final witness in transportWitnesses) {
      final key = '${witness.label}\u0000${witness.sourcePath ?? ''}';
      if (!seenTransportKeys.add(key)) continue;
      witnesses.add(witness);
      if (seenTransportKeys.length >= 2) break;
    }

    final shadow = stats.shadowCoupling;
    if (shadow != null) {
      for (final source in focusPaths) {
        if (source == path) continue;
        final ghostScore = shadow.jaccardScoreOf(source, path);
        if (ghostScore <= _kSignalFloor) continue;
        final realScore = stats.coupling.jaccardScoreOf(source, path);
        witnesses.add(LogosEvidenceWitness(
          kind: LogosWitnessKind.ambient,
          label: realScore > 0 ? 'shadow-corroboration' : 'déjà-vu',
          strength: ghostScore * _kShadowDiscount,
          sourcePaths: [source],
          sourcePath: source,
          targetPath: path,
          note: realScore > 0
              ? 'shadow evidence reinforces real co-change'
              : 'this coupling existed in a discarded timeline',
        ));
        break;
      }
    }

    if (hyperedge != null && higherOrderLift > 0.0) {
      final overlapSources = [
        for (final p in hyperedge.paths)
          if (p != path && focusPaths.contains(p)) p,
      ];
      witnesses.add(LogosEvidenceWitness(
        kind: LogosWitnessKind.hyperedge,
        label: 'commit-hyperedge',
        strength: higherOrderLift,
        sourcePaths: overlapSources,
        note: hyperedge.summary,
        observers: hyperedge.observers,
      ));
    }

    if (reducibilityGap > _kSignalFloor) {
      witnesses.add(LogosEvidenceWitness(
        kind: LogosWitnessKind.reducibility,
        label: 'pairwise-loss',
        strength: reducibilityGap,
      ));
    }

    witnesses.sort((a, b) => b.strength.compareTo(a.strength));
    final selected = <LogosEvidenceWitness>[];
    final selectedKeys = <String>{};
    String witnessKey(LogosEvidenceWitness witness) =>
        '${witness.kind.name}\u0000${witness.label}\u0000${witness.sourcePath ?? ''}';
    for (final kind in const [
      LogosWitnessKind.hyperedge,
      LogosWitnessKind.reducibility,
      LogosWitnessKind.integrity,
    ]) {
      LogosEvidenceWitness? witness;
      for (final candidate in witnesses) {
        if (candidate.kind == kind) {
          witness = candidate;
          break;
        }
      }
      if (witness == null) continue;
      final key = witnessKey(witness);
      if (selectedKeys.add(key)) selected.add(witness);
    }
    for (final witness in witnesses) {
      final key = witnessKey(witness);
      if (!selectedKeys.add(key)) continue;
      selected.add(witness);
      if (selected.length >= 6) break;
    }
    return selected;
  }

  List<LogosMetricSidecar> _rollupMetricSidecars(
    Iterable<LogosEvidenceScore> scores, {
    int limit = 4,
  }) {
    final byLabel = <String, LogosMetricSidecar>{};
    for (final score in scores) {
      for (final sidecar in score.sidecars) {
        final prev = byLabel[sidecar.label];
        if (prev == null || sidecar.strength > prev.strength) {
          final mergedPaths = <String>{
            ...sidecar.paths,
            score.path,
            if (prev != null) ...prev.paths,
          };
          final mergedChannels = <String>{
            ...sidecar.channels,
            if (prev != null) ...prev.channels,
          };
          byLabel[sidecar.label] = LogosMetricSidecar(
            label: sidecar.label,
            strength: sidecar.strength,
            paths: mergedPaths.toList(growable: false),
            channels: mergedChannels.toList(growable: false),
            note: sidecar.note ?? prev?.note,
          );
        }
      }
    }
    final rolled = byLabel.values.toList(growable: false)
      ..sort((a, b) {
        final byStrength = b.strength.compareTo(a.strength);
        if (byStrength != 0) return byStrength;
        return a.label.compareTo(b.label);
      });
    if (rolled.length <= limit) return rolled;
    return rolled.take(limit).toList(growable: false);
  }

  List<LogosMetricSidecar> _buildMetricSidecars(
    String path,
    Set<String> focusPaths, {
    required double integrity,
    required double higherOrderLift,
    required double reducibilityGap,
    required LogosCommitHyperedge? hyperedge,
  }) {
    final sidecars = <LogosMetricSidecar>[];

    void addOrUpgrade(LogosMetricSidecar next) {
      final idx = sidecars.indexWhere((s) => s.label == next.label);
      if (idx < 0) {
        sidecars.add(next);
        return;
      }
      final prev = sidecars[idx];
      if (next.strength <= prev.strength) return;
      sidecars[idx] = next;
    }

    for (final source in focusPaths) {
      if (source == path) continue;
      final relation = logosRelationDescriptor(source, path);
      final lane = logosTransportLane(source, path, couplingConstants);
      final relationLabel = relation?.label;
      final laneLabel = lane?.label;
      if (relationLabel == 'source-generated' ||
          laneLabel == 'generated->source' ||
          laneLabel == 'source->generated') {
        addOrUpgrade(
          LogosMetricSidecar(
            label: 'generated-source-map',
            strength: math.max(
              relation?.strength ?? 0.0,
              lane?.strength ?? 0.0,
            ),
            paths: [source, path],
            channels: [
              if (relationLabel != null) relationLabel,
              if (laneLabel != null) laneLabel,
            ],
            note: 'directional companion lane',
          ),
        );
      }
      if (relationLabel == 'manifest-lockfile' ||
          laneLabel == 'manifest->lockfile' ||
          laneLabel == 'lockfile->manifest') {
        addOrUpgrade(
          LogosMetricSidecar(
            label: 'manifest-lockfile-map',
            strength: math.max(
              relation?.strength ?? 0.0,
              lane?.strength ?? 0.0,
            ),
            paths: [source, path],
            channels: [
              if (relationLabel != null) relationLabel,
              if (laneLabel != null) laneLabel,
            ],
            note: 'paired dependency witness',
          ),
        );
      }
      if (relationLabel == 'test-fixture' ||
          laneLabel == 'test->fixture' ||
          laneLabel == 'fixture->test') {
        addOrUpgrade(
          LogosMetricSidecar(
            label: 'test-fixture-map',
            strength: math.max(
              relation?.strength ?? 0.0,
              lane?.strength ?? 0.0,
            ),
            paths: [source, path],
            channels: [
              if (relationLabel != null) relationLabel,
              if (laneLabel != null) laneLabel,
            ],
            note: 'test witness lane',
          ),
        );
      }
      if (relationLabel == 'source-test' ||
          laneLabel == 'source->test' ||
          laneLabel == 'test->source') {
        addOrUpgrade(
          LogosMetricSidecar(
            label: 'test-witness-map',
            strength: math.max(
              relation?.strength ?? 0.0,
              lane?.strength ?? 0.0,
            ),
            paths: [source, path],
            channels: [
              if (relationLabel != null) relationLabel,
              if (laneLabel != null) laneLabel,
            ],
            note: 'test witness lane',
          ),
        );
      }
      if (relationLabel == 'source-doc' ||
          laneLabel == 'source->doc' ||
          laneLabel == 'doc->source') {
        addOrUpgrade(
          LogosMetricSidecar(
            label: 'doc-witness-map',
            strength: math.max(
              relation?.strength ?? 0.0,
              lane?.strength ?? 0.0,
            ),
            paths: [source, path],
            channels: [
              if (relationLabel != null) relationLabel,
              if (laneLabel != null) laneLabel,
            ],
            note: 'documentation witness lane',
          ),
        );
      }
      if (relationLabel == 'source-migration' ||
          laneLabel == 'source->migration' ||
          laneLabel == 'migration->source') {
        addOrUpgrade(
          LogosMetricSidecar(
            label: 'migration-witness-map',
            strength: math.max(
              relation?.strength ?? 0.0,
              lane?.strength ?? 0.0,
            ),
            paths: [source, path],
            channels: [
              if (relationLabel != null) relationLabel,
              if (laneLabel != null) laneLabel,
            ],
            note: 'migration witness lane',
          ),
        );
      }
    }

    if (hyperedge != null &&
        (higherOrderLift > _kSignalFloor || reducibilityGap > _kSignalFloor)) {
      final overlapSources = [
        for (final p in hyperedge.paths)
          if (p != path && focusPaths.contains(p)) p,
      ];
      if (overlapSources.isNotEmpty) {
        addOrUpgrade(
          LogosMetricSidecar(
            label: 'hyperedge-route',
            strength: math.max(higherOrderLift, reducibilityGap),
            paths: [path, ...overlapSources],
            channels: const ['hyperedge', 'reducibility'],
            note: hyperedge.summary ?? 'irreducible local motif',
          ),
        );
      }
    }

    if (integrity < kNeutralIntegrity) {
      final reasons = (stats.integrityReasonsByPath[path] ?? const <String>[])
          .take(2)
          .toList(growable: false);
      if (reasons.isNotEmpty) {
        addOrUpgrade(
          LogosMetricSidecar(
            label: 'integrity-boundary',
            strength: (1.0 - integrity).clamp(0.0, 1.0).toDouble(),
            paths: [path],
            channels: const ['integrity'],
            note: reasons.join(', '),
          ),
        );
      }
    }

    sidecars.sort((a, b) {
      final byStrength = b.strength.compareTo(a.strength);
      if (byStrength != 0) return byStrength;
      return a.label.compareTo(b.label);
    });
    if (sidecars.length <= 2) return sidecars;
    return sidecars.take(2).toList(growable: false);
  }

  LogosTransportSummary _rollupTransportSummary(
    Iterable<LogosEvidenceScore> scores, {
    required Float64List focusRho,
    int frontierLimit = 4,
  }) {
    var totalWeight = 0.0;
    var weightedPull = 0.0;
    final laneMass = <String, double>{};
    final frontier = scores
        .where((score) =>
            math.max(score.transportPull, score.transportedSupport) > _kSignalFloor)
        .toList(growable: false)
      ..sort((a, b) {
        final byPull = math
            .max(b.transportPull, b.transportedSupport)
            .compareTo(math.max(a.transportPull, a.transportedSupport));
        if (byPull != 0) return byPull;
        return a.path.compareTo(b.path);
      });
    for (final score in scores) {
      final transportSignal =
          math.max(score.transportPull, score.transportedSupport);
      final weight = math.max(score.support, transportSignal);
      if (weight <= 0) continue;
      totalWeight += weight;
      weightedPull += weight * transportSignal;
      for (final witness in score.witnesses) {
        if (witness.kind != LogosWitnessKind.transport) continue;
        laneMass[witness.label] =
            (laneMass[witness.label] ?? 0.0) + weight * witness.strength;
      }
    }
    final normalizedLaneMass = <String, double>{};
    final laneTotal = laneMass.values.fold<double>(0.0, (a, b) => a + b);
    if (laneTotal > 0) {
      for (final entry in laneMass.entries) {
        normalizedLaneMass[entry.key] = entry.value / laneTotal;
      }
    }
    final frontierEdges = _buildTransportFrontierEdges(
      focusRho,
      frontier,
      limit: frontierLimit,
    );
    final frontierPaths = <String>[];
    final seenFrontierPaths = <String>{};
    for (final edge in frontierEdges) {
      if (!seenFrontierPaths.add(edge.targetPath)) continue;
      frontierPaths.add(edge.targetPath);
      if (frontierPaths.length >= frontierLimit) break;
    }
    for (final score in frontier) {
      if (frontierPaths.length >= frontierLimit) break;
      if (!seenFrontierPaths.add(score.path)) continue;
      frontierPaths.add(score.path);
    }
    return LogosTransportSummary(
      pull: totalWeight > 0 ? weightedPull / totalWeight : 0.0,
      laneFractions: normalizedLaneMass,
      frontierPaths: frontierPaths,
      frontierEdges: frontierEdges,
    );
  }

  LogosSemanticMotionSummary _rollupSemanticMotionSummary(
    Iterable<LogosEvidenceScore> scores, {
    Set<String> excludePaths = const {},
    int frontierLimit = 4,
  }) {
    final filtered = [
      for (final score in scores)
        if (!excludePaths.contains(score.path)) score,
    ];
    var totalWeight = 0.0;
    var weightedTransported = 0.0;
    var weightedInnovation = 0.0;
    final frontier = filtered
        .where((score) => score.innovationResidual > _kSignalFloor)
        .toList(growable: false)
      ..sort((a, b) {
        final byInnovation =
            b.innovationResidual.compareTo(a.innovationResidual);
        if (byInnovation != 0) return byInnovation;
        return a.path.compareTo(b.path);
      });
    for (final score in filtered) {
      final weight = math.max(score.support, score.transportedSupport);
      if (weight <= 0) continue;
      totalWeight += weight;
      weightedTransported += weight * score.transportedSupport;
      weightedInnovation += weight * score.innovationResidual;
    }
    final warpCoverage =
        totalWeight > 0 ? weightedTransported / totalWeight : 0.0;
    final innovationMass =
        totalWeight > 0 ? weightedInnovation / totalWeight : 0.0;
    final ratioDen = warpCoverage + innovationMass;
    final compensatedChangeRatio =
        ratioDen > 0 ? innovationMass / ratioDen : 0.0;
    final sceneCut = innovationMass > 0.08 && compensatedChangeRatio > 0.55;
    return LogosSemanticMotionSummary(
      warpCoverage: warpCoverage,
      innovationMass: innovationMass,
      compensatedChangeRatio: compensatedChangeRatio,
      sceneCut: sceneCut,
      innovationFrontier: frontier
          .take(frontierLimit)
          .map((score) => score.path)
          .toList(growable: false),
    );
  }

  LogosWitnessResidualSummary _rollupWitnessResidualSummary(
    Iterable<LogosEvidenceScore> scores, {
    int frontierLimit = 4,
  }) {
    final filtered = [
      for (final score in scores)
        if (score.transportedSupport > _kSignalFloor || score.witnessResidual > _kSignalFloor)
          score,
    ];
    var totalWeight = 0.0;
    var predicted = 0.0;
    var residual = 0.0;
    final kindMass = <String, double>{};
    final frontier = filtered
        .where((score) => score.witnessResidual > _kSignalFloor)
        .toList(growable: false)
      ..sort((a, b) {
        final byResidual = b.witnessResidual.compareTo(a.witnessResidual);
        if (byResidual != 0) return byResidual;
        return a.path.compareTo(b.path);
      });
    for (final score in filtered) {
      final weight = math.max(score.transportedSupport, score.witnessResidual);
      if (weight <= 0) continue;
      totalWeight += weight;
      predicted += weight * score.transportedSupport;
      residual += weight * score.witnessResidual;
      final labels = <String>{
        for (final witness in score.witnesses)
          if (witness.kind == LogosWitnessKind.transport ||
              witness.kind == LogosWitnessKind.relation)
            witness.label,
      };
      for (final label in labels) {
        kindMass[label] = (kindMass[label] ?? 0.0) + weight;
      }
    }
    final predictedMass = totalWeight > 0 ? predicted / totalWeight : 0.0;
    final residualMass = totalWeight > 0 ? residual / totalWeight : 0.0;
    final coverage = predictedMass > 0
        ? (1.0 - (residualMass / predictedMass)).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final dominantKinds = kindMass.entries.toList()
      ..sort((a, b) {
        final byValue = b.value.compareTo(a.value);
        if (byValue != 0) return byValue;
        return a.key.compareTo(b.key);
      });
    return LogosWitnessResidualSummary(
      predictedMass: predictedMass,
      residualMass: residualMass,
      coverage: coverage,
      frontierPaths: frontier
          .take(frontierLimit)
          .map((score) => score.path)
          .toList(growable: false),
      dominantKinds:
          dominantKinds.take(4).map((e) => e.key).toList(growable: false),
    );
  }

  List<LogosTransportFlowEdge> _buildTransportFrontierEdges(
    Float64List focusRho,
    List<LogosEvidenceScore> frontier, {
    int limit = 4,
  }) {
    if (limit <= 0 || transportGraph.n == 0 || frontier.isEmpty) {
      return const [];
    }
    final allowedTargets = <int, double>{
      for (final score in frontier)
        if (math.max(score.transportPull, score.transportedSupport) > _kSignalFloor)
          if (pathToId[score.path] != null)
            pathToId[score.path]!: math.max(
              score.transportPull,
              score.transportedSupport,
            ),
    };
    if (allowedTargets.isEmpty) return const [];
    final byEdge = <String, LogosTransportFlowEdge>{};
    for (var sourceId = 0; sourceId < transportGraph.n; sourceId++) {
      final sourceMass = focusRho[sourceId];
      if (sourceMass <= 0) continue;
      final sourcePath = nodePaths[sourceId];
      final start = transportGraph.indptr[sourceId];
      final end = transportGraph.indptr[sourceId + 1];
      for (var k = start; k < end; k++) {
        final targetId = transportGraph.indices[k];
        final targetSignal = allowedTargets[targetId];
        if (targetSignal == null) continue;
        final pull = sourceMass * transportGraph.values[k];
        if (pull <= _kTransportFloor && targetSignal <= _kSignalFloor) continue;
        final targetPath = nodePaths[targetId];
        final lane = logosTransportLane(sourcePath, targetPath, couplingConstants);
        final candidate = LogosTransportFlowEdge(
          sourcePath: sourcePath,
          targetPath: targetPath,
          pull: pull,
          laneLabel: lane?.label,
          laneStrength: lane?.strength ?? transportGraph.values[k],
          note: lane?.note,
          sourceRole: lane?.sourceRole,
          targetRole: lane?.targetRole,
          directional: lane?.directional ?? true,
        );
        final key = '$sourcePath\u0000$targetPath';
        final prev = byEdge[key];
        if (prev == null || candidate.pull > prev.pull) {
          byEdge[key] = candidate;
        }
      }
    }
    final edges = byEdge.values.toList(growable: false)
      ..sort((a, b) {
        final byPull = b.pull.compareTo(a.pull);
        if (byPull != 0) return byPull;
        final bySource = a.sourcePath.compareTo(b.sourcePath);
        if (bySource != 0) return bySource;
        return a.targetPath.compareTo(b.targetPath);
      });
    if (edges.length <= limit) return edges;
    return edges.take(limit).toList(growable: false);
  }

  /// Fast variant: caller precomputes [TransportRoles] for every focus
  /// path once (outside the ranked-list loop) and for the candidate
  /// once per loop body. Replaces the O(|focusPaths|) fresh-role-build
  /// per call with O(1) field-access comparisons on pre-built roles.
  /// Dominates the cost profile of [gatherEvidence] on large diffs —
  /// worth the extra API surface.
  bool _hasWitnessCarrierLaneFast(
    String path,
    TransportRoles candRoles,
    List<({String path, TransportRoles roles})> focusRoles,
  ) {
    for (final entry in focusRoles) {
      if (entry.path == path) continue;
      if (logosTransportLaneOfRoles(entry.roles, candRoles, couplingConstants) != null) {
        return true;
      }
    }
    return false;
  }

  LogosInquiryPlan _buildInquiryPlan(
    List<LogosEvidenceScore> ranked, {
    required LogosTransportSummary transport,
    required Set<String> focusPaths,
    int limit = 4,
  }) {
    if (limit <= 0 || ranked.isEmpty) {
      return const LogosInquiryPlan();
    }
    final byPath = {
      for (final score in ranked) score.path: score,
    };
    final steps = <LogosInquiryStep>[];
    final seenPaths = <String>{};

    LogosInquiryActionKind classifyKind(String? laneLabel) {
      if (laneLabel == null) return LogosInquiryActionKind.inspectPath;
      if (laneLabel.contains('generated') ||
          laneLabel.contains('lockfile') ||
          laneLabel.contains('fixture')) {
        return LogosInquiryActionKind.inspectCompanion;
      }
      return LogosInquiryActionKind.inspectPath;
    }

    for (final edge in transport.frontierEdges) {
      if (steps.length >= limit) break;
      final target = byPath[edge.targetPath];
      if (target == null ||
          focusPaths.contains(edge.targetPath) ||
          !seenPaths.add(edge.targetPath)) {
        continue;
      }
      final rationale = target.witnessResidual > 0.05
          ? edge.laneLabel == null || edge.laneLabel!.trim().isEmpty
              ? 'missing witness residual'
              : 'missing ${edge.laneLabel!} witness'
          : edge.laneLabel == null || edge.laneLabel!.trim().isEmpty
              ? 'transport frontier'
              : 'transport frontier ${edge.laneLabel!}';
      steps.add(LogosInquiryStep(
        kind: classifyKind(edge.laneLabel),
        path: edge.targetPath,
        priority: math.max(
          target.utility,
          math.max(edge.pull, target.witnessResidual),
        ),
        rationale: rationale,
        viaPath: edge.sourcePath,
        laneLabel: edge.laneLabel,
      ));
    }

    for (final score in ranked) {
      if (steps.length >= limit) break;
      if (focusPaths.contains(score.path) || !seenPaths.add(score.path)) {
        continue;
      }
      LogosEvidenceWitness? transportWitness;
      for (final witness in score.witnesses) {
        if (witness.kind == LogosWitnessKind.transport) {
          transportWitness = witness;
          break;
        }
      }
      final leadWitness = score.witnessResidual > 0.05
          ? transportWitness == null
              ? 'missing witness residual'
              : 'missing ${transportWitness.label} witness'
          : score.innovationResidual > 0.05
              ? 'innovation residual'
              : score.witnesses.isEmpty
                  ? null
                  : formatLogosEvidenceWitness(
                      score.witnesses.first,
                      includeNote: false,
                      includeSource: false,
                    );
      steps.add(LogosInquiryStep(
        kind: LogosInquiryActionKind.inspectPath,
        path: score.path,
        priority: math.max(
          score.utility,
          math.max(score.innovationResidual, score.witnessResidual),
        ),
        rationale: leadWitness == null || leadWitness.isEmpty
            ? 'high-utility evidence'
            : score.witnessResidual > 0.05
                ? leadWitness
                : 'witness $leadWitness',
      ));
    }

    if (steps.length <= limit) {
      return LogosInquiryPlan(steps: steps);
    }
    return LogosInquiryPlan(
      steps: steps.take(limit).toList(growable: false),
    );
  }

  Float64List _transportProject(Float64List sourceMass) {
    if (transportGraph.n == 0) return Float64List(0);
    final projected = Float64List(transportGraph.n);
    for (var i = 0; i < transportGraph.n; i++) {
      final mass = sourceMass[i];
      if (mass <= 0) continue;
      final start = transportGraph.indptr[i];
      final end = transportGraph.indptr[i + 1];
      for (var k = start; k < end; k++) {
        projected[transportGraph.indices[k]] += mass * transportGraph.values[k];
      }
    }
    return projected;
  }

  @pragma('vm:prefer-inline')
  double _companionRescueScore({
    required double support,
    required double integrity,
    required double transportPull,
  }) {
    if (support <= 0 || transportPull <= 0) return 0.0;
    return support * transportPull * math.max(integrity, _kTransportIntegrityFloor);
  }

  /// **Stability of a diffusion query** - returns a [0, 1] score where
  /// 1.0 means "tiny perturbations to the source weights don't change
  /// the top-K ranking at all" and 0 means "one dropped source and the
  /// answer is entirely different." Novel Logos-spirited confidence
  /// signal: the same machinery that produces an answer produces its
  /// own self-consistency score, so downstream code can abstain rather
  /// than act on knife-edge rankings.
  /// Algorithm: run [nTrials] diffusions, each with source weights
  /// multiplicatively perturbed by +/-[epsilon] (deterministic seed).
  /// Stability = mean pairwise Jaccard overlap of their top-[topK]
  /// sets against the unperturbed top-K.
  /// Returns 1.0 on degenerate inputs (empty graph, single source, K=0)
  /// - no perturbation can change a single-element ranking, so it's
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
    final baseSet = baseline.take(topK).map((s) => s.path).toSet();
    if (baseSet.isEmpty) return 1.0;

    final rng = math.Random(seed);
    var overlapAcc = 0.0;
    var trialsRun = 0;
    for (var trial = 0; trial < nTrials; trial++) {
      final perturbed = <String, double>{};
      for (final entry in weights.entries) {
        // Multiplicative jitter in [1 - epsilon, 1 + epsilon]. Preserves
        // the sign of the
        // weight and never flips a non-zero source to zero (entropy-
        // preserving perturbation, Logos-style).
        final jitter = 1.0 + (rng.nextDouble() * 2 - 1) * epsilon;
        perturbed[entry.key] = entry.value * jitter;
      }
      final trialScores = diffuseWeighted(perturbed, t: t);
      if (trialScores.isEmpty) continue;
      final trialSet = trialScores.take(topK).map((s) => s.path).toSet();
      if (trialSet.isEmpty) continue;
      // Jaccard overlap between the perturbed top-K and the baseline
      // top-K: |A intersect B| / |A union B|.
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
  /// Diagnostic - should always be <= 2 by construction. A larger value
  /// signals numerical drift or an asymmetric weight bug worth chasing.
  double estimateSpectralRadius({int iterations = kDefaultPowerIterations}) =>
      graph.estimateSpectralRadius(iterations: iterations);

  /// **Per-source attribution diffusion** - runs Chebyshev expansion
  /// once per axis bucket and returns phi vectors keyed by axis. Heat
  /// kernel is linear in rho, so the combined phi equals the sum of
  /// per-axis phi. Use this to answer "*why* did file X surface as
  /// relevant?*" by reading the dominant axis bucket per result.
  /// `weightsByPath` carries the source amplitudes; `axisLabelByPath`
  /// assigns each path to a bucket label. Paths not in [pathToId] are
  /// silently dropped (out-of-graph). Paths with weight <= 0 are dropped.
  /// Returns null if no source contributes.
  AxisAttribution? diffuseWithAttribution({
    required Map<String, double> weightsByPath,
    required Map<String, String> axisLabelByPath,
    double t = 1.0,
    int K = kDefaultChebyshevK,
    Set<String> excludePaths = const {},
    // When set, the combined result is pruned so every included path
    // keeps the induced-subgraph coherence above this value. Per-axis phi
    // vectors are not pruned (callers that want them can apply the
    // same gate themselves). Mirrors the behaviour in [diffuse].
    double? coherenceGate,
  }) {
    if (graph.n == 0 || weightsByPath.isEmpty) return null;

    // Symbol-axis routing: a source path absent from the graph but
    // present in [symbolEdges] is proxied through its known neighbours,
    // with the proxied mass attributed to the `symbol` axis regardless
    // of the caller's label. This keeps attribution math consistent with
    // _buildRho and surfaces new-file contributions in per-axis phi.
    final symbolAxisLabel = LogosAxis.symbol.name;

    // Bucket per axis, applying global mass normalisation up front so
    // per-axis phi vectors sum to combined phi. Two-pass structure: first
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
        // Unknown path - proxy through symbol neighbours under the
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
    // simultaneously - graph memory bandwidth (the SpMV bottleneck)
    // scales O(K * |E|) instead of O(B * K * |E|). Split back into
    // per-axis phi after.
    final axisOrder = perAxisRaw.keys.toList(growable: false);
    final B = axisOrder.length;
    final perAxisPhi = <String, Float64List>{};
    if (B == 1) {
      // Single axis - skip the packing overhead, run the scalar path.
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
    // phi vectors so callers can compose / threshold themselves.
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
      // share of the node's phi came from each axis?
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

    // Derived phi for new / symbol-coupled paths not in the graph - same
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
    // gated - per-axis phi is preserved for callers that need the raw
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

  /// Multi-axis *coherence* of a path set - the mean pairwise relevance
  /// under the full Born-mixed metric. Replaces the single-axis
  /// `FileCouplingMatrix.coherenceFor(paths)` with a metric that
  /// considers frequency, coupling, proximity, and volatility together.
  /// Returns 1.0 for 0 or 1 known paths (nothing to compare).
  /// Returns in [0, 1] where higher = tighter semantic grouping.
  /// Used by the branches page to score PR "focus" - a high coherence
  /// means the PR touches files that historically belong together; low
  /// means a scattered sweep.
  double coherence(Iterable<String> paths) {
    // Dedup (coherence is a property of a set) and filter to known ids.
    // `knownIdx[nodeId]` gives the position in the subset - used both
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
    // Cost: O(k * avg_degree) - no pair loop, no per-pair row search.
    // The previous linear-scan-per-pair implementation was O(k^2 * degree).
    var sum = 0.0;
    knownIdx.forEach((ia, i) {
      final aEnd = graph.indptr[ia + 1];
      for (var e = graph.indptr[ia]; e < aEnd; e++) {
        final jIdx = knownIdx[graph.indices[e]];
        if (jIdx != null && jIdx > i) sum += graph.values[e];
      }
    });
    // The weight is the D^{-1/2}-normalised p_mix; ranking/averaging
    // is preserved by either form. Total pairs is combinatoric -
    // non-edges contribute 0 and pull the mean toward "scattered".
    final pairs = k * (k - 1) ~/ 2;
    return (sum / pairs).clamp(0.0, 1.0);
  }

  /// Rank all known paths by relevance to [seed]. Returns the top
  /// [limit] most-relevant paths (excluding the seed itself).
  /// Convenience wrapper over [diffuse] for single-file queries -
  /// "show me things related to this file."
  List<RelevanceScore> relatedTo(
    String seed, {
    double t = 1.0,
    int limit = 20,
  }) {
    // Seed may be a graph node OR a new/untracked file with symbol edges.
    // In either case, `diffuse` via `_buildRho` routes heat correctly.
    // Only bail when neither path exists - nothing to diffuse from.
    final hasSeed =
        pathToId.containsKey(seed) || (symbolEdges[seed]?.isNotEmpty ?? false);
    if (!hasSeed) return const [];
    final scores = diffuse({seed}, t: t);
    if (scores.length <= limit) return scores;
    return scores.sublist(0, limit);
  }

  /// Select an emission plan from relevance scores within [budget]
  /// tokens. Greedy density knapsack with a single-pass swap. Tiers:
  ///   FULL        - avg 1600 tokens, info 1.0
  ///   SIGNATURE   -        300              0.45
  ///   BREADCRUMB  -         60              0.12
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
    // (info / cost). The density metric is Lagrangian - we're solving a
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

    return selected.values.toList()..sort((a, b) => b.phi.compareTo(a.phi));
  }
}

/// Result of [LogosGit.diffuseWithAttribution]. Carries the combined
/// phi field (summed across axes - exactly what plain `diffuseWeighted`
/// would have returned), plus per-axis phi vectors and per-node provenance.
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

  /// path -> label of the axis that contributed the most at that node.
  final Map<String, String> dominantAxis;

  /// path -> axis-label -> fraction of phi contributed by that axis (sums
  /// to 1 per path, modulo silent axes which omit their entry).
  final Map<String, Map<String, double>> shareByAxis;

  const AxisAttribution({
    required this.combined,
    required this.perAxisPhi,
    required this.nodePaths,
    required this.dominantAxis,
    required this.shareByAxis,
  });

  /// Sum of phi contributed by [axisLabel] across all nodes. Useful for
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

  /// Map of axis label -> fractional total mass. Sums to 1.
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

// Min-heap helpers keyed on [pMix]. Used by the build-time top-K
// admission loop in [buildFromStats] to keep the K best edges across
// a candidate scan without a trailing full sort.

void _edgeHeapSiftUp(List<_EdgeCandidate> heap, int i) {
  while (i > 0) {
    final parent = (i - 1) >> 1;
    if (heap[i].pMix < heap[parent].pMix) {
      final tmp = heap[i];
      heap[i] = heap[parent];
      heap[parent] = tmp;
      i = parent;
    } else {
      break;
    }
  }
}

void _edgeHeapSiftDown(List<_EdgeCandidate> heap, int i) {
  final n = heap.length;
  while (true) {
    final l = 2 * i + 1;
    final r = 2 * i + 2;
    var smallest = i;
    if (l < n && heap[l].pMix < heap[smallest].pMix) smallest = l;
    if (r < n && heap[r].pMix < heap[smallest].pMix) smallest = r;
    if (smallest == i) break;
    final tmp = heap[i];
    heap[i] = heap[smallest];
    heap[smallest] = tmp;
    i = smallest;
  }
}

class _HigherOrderSignal {
  final double lift;
  final double gap;
  final LogosCommitHyperedge? hyperedge;

  const _HigherOrderSignal({
    this.lift = 0.0,
    this.gap = 0.0,
    this.hyperedge,
  });
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

// `_parentDir` removed - the build loop now precomputes parent
// directories via `dirIndex` directly off the cached `pathSegments`.

// Tiny binary min-heap on `List<RelevanceScore>` keyed by .phi.
//
// Used for bounded top-K extraction in `_packTopPhi`: scan O(n) nodes,
// per-node cost O(log topK) instead of growing an unbounded list and
// O(n log n) sorting at the end. For typical (n=10000, topK=24..200)
// this is a 2x-3x speed-up and cuts allocations from O(n) to O(topK).
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

// DiffusionBasis - cached Chebyshev basis for temperature-slider UIs.
//
// The heat kernel phi(t) = exp(-tL) * rho factors into
//
//   phi(t) = sum_{k=0..K} c_k(t) * (T_k(L) * rho)
//
// where the `T_k(L) * rho` vectors are independent of t. Precompute them
// once (O(K * |E|)) and every subsequent "move the slider" is a simple
// weighted sum: O(K * |V|), ~10 us for 5k nodes on a modern CPU.
//
// Exposed on the engine as `engine.buildBasis(sources)`. UI code holds
// the basis as long as the source set is stable and calls
// `basis.recombine(t)` per frame.

class DiffusionBasis {
  final int n;
  final int K;

  /// Basis vectors stored as a row-major f64 matrix of shape (K+1, n).
  /// basis[k * n + i] = (T_k(L) * rho)[i].
  final Float64List basis;

  /// The source paths the basis was built from - useful for UI labelling
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
    final phi = Float64List(n);
    recombineInto(t, phi);
    return phi;
  }

  /// In-place variant of [recombine]. Writes `φ(t)` into the caller-
  /// owned [out] buffer (which must have length [n]). Zeroes [out]
  /// before accumulation. Callers that evaluate the basis at multiple
  /// temperatures — the canonical three-T blend in `commit_tagger.dart`,
  /// any future temperature-slider UI — can allocate three scratch
  /// buffers once and reuse them across thousands of recombines,
  /// eliminating the per-call `Float64List(n)` allocation that
  /// [recombine] would emit.
  void recombineInto(double t, Float64List out) {
    assert(out.length == n, 'out buffer must have length n');
    final coeffs = besselCoeffs(t, K);
    final kEff = adaptiveK(coeffs, 1e-8);
    for (var i = 0; i < n; i++) {
      out[i] = 0.0;
    }
    for (var k = 0; k <= kEff; k++) {
      final c = coeffs[k];
      if (c == 0) continue;
      final base = k * n;
      for (var i = 0; i < n; i++) {
        out[i] += c * basis[base + i];
      }
    }
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
  // Delegate to logos_core.dart - single implementation shared by the
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
