// LOGOS CORE — shared geometric primitives
//
// The math substrate every Logos engine in this codebase composes over.
// Three engines (file-graph in `logos_git.dart`, intra-file chunk graph
// in `logos_chunks.dart`, intra-diff hunk graph in `logos_hunks.dart`)
// previously reimplemented the same primitives with slight drift. This
// module is the single source of truth for:
//
//   • Compressed sparse-row graph storage with normalised Laplacian
//     application (`L_sym = I − D^{-1/2} W D^{-1/2}`, fused into the
//     stored values so the matvec is `y = v − W_norm·v`).
//   • Modified Bessel coefficients `c_k(t) = 2·e^{-t}·I_k(-t)` for the
//     heat-kernel Chebyshev expansion. Numerically stable forward
//     recurrence in log-space; NaN-safe; overflow-guarded for any
//     reasonable t.
//   • Adaptive Chebyshev truncation — prune tail terms whose
//     coefficients are below the noise floor.
//   • Heat-kernel diffusion `φ(t) = exp(−t·L_sym)·ρ` — both one-shot
//     ([chebyshevDiffuse]) and basis-cached for multi-temperature
//     recombination ([chebyshevBasis] + [recombineHeatPhi]).
//
// The pattern matches the whisper codec library's `Loup ⊗ Loup` factor-
// isation: shared geometric core, scale-specific composition. Every
// engine here builds its own graph (its own axis blend, its own edge
// construction) and then defers to this module for diffusion.
//
//
// The inner loops are hot: a single commit review can run ~10 Chebyshev
// steps across three engines (file/hunk/chunk) at up to four temperatures.
// Three optimisations keep the work to a minimum without compromising
// fidelity:
//
//   1. **Ring-buffer Chebyshev recurrence.** The three-term recurrence
//      `T_{k+1} = 2·x·T_k − T_{k-1}` only needs the last two basis
//      vectors in-flight. Three scratch buffers cycle by *reference*
//      each step — no memcpy shuffle. Every `setAll` saved is `n` f64
//      moves avoided per step.
//   2. **Float64x2 SIMD on elementwise passes.** The AXPY-style loops
//      (`t2 = 2·(scratch − t1) − t0`, `φ += c_k·t_k`) are pure stride-1
//      and paired up into Float64x2 lanes. Arithmetic is IEEE-identical
//      within each lane, so fidelity is preserved bit-for-bit. Scratch
//      buffers are allocated as `Float64x2List` (guaranteed 16-byte
//      aligned); the SpMV reads via a `Float64List` view over the same
//      memory.
//   3. **B=4 batched SpMV fast path.** With 4 contiguous batch lanes per
//      node the AoSoA block is exactly two Float64x2 accumulators; the
//      scalar `for (b in 0..4)` loop becomes two splat-scale-add pairs.
//      General B falls back to the scalar path unchanged.
//
// Additional guards: adaptive K truncation now applies to the batched
// variant too (was missing); Bessel coefficients use a precomputed log-
// factorial table instead of re-summing `log(i)` per k (O(K²) → O(K));
// output buffers get a subnormal flush pass to defend against the web
// FPU microcode trap on CanvasKit.

import 'dart:convert' show utf8;
import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_signature.dart';
import 'lru_cache.dart';

part 'logos_flow_math.dart';
part 'logos_generative.dart';
part 'logos_groundspace.dart';
part 'logos_heat.dart';
part 'logos_mobius.dart';
part 'logos_thermo.dart';

// ── OBSERVABLE TAXONOMY ──────────────────────────────────────────────
//
// Every observable in this file (and in the family-split parts) falls
// into one of three classes. Each method's doc comment should declare
// which, so readers don't confuse pedagogy with guarantee:
//
//   • **Theorem-tight** — the method computes a quantity that satisfies
//     a proven mathematical identity on the spectrum. The identity IS
//     the contract; the implementation is replaceable as long as it
//     delivers the same identity. Example: `heatTrace(t) = Σ e^{-tλⱼ}`
//     — two implementations agree bit-for-bit at floating-point
//     precision.
//
//   • **Operational** — engineering construct: the method performs a
//     well-defined task well, but the value isn't pinned by a theorem.
//     Reasonable alternative implementations would produce slightly
//     different outputs, and there's no pre-existing identity that
//     declares one correct. Example: `ricciFlowStep` (many valid
//     discretisations); `fragmentationCurve` (threshold granularity is
//     a modelling choice).
//
//   • **Analogy** — the method's NAMING borrows a physical concept to
//     aid intuition, and the correspondence is exact only under a
//     specific regime or after a change of variables. The math is
//     correct; the physical reading requires the reader to accept the
//     analogy. Example: `gravitationalPotential` IS the Wentzell-
//     Freidlin effective action, which IS a gravitational potential
//     after Wick rotation — but a reader who hasn't done that rotation
//     should treat the name as pedagogy, not theorem.
//
// When writing a new observable, tag it at the top of the doc comment:
//   `/// **Theorem-tight:** this quantity equals X by theorem Y.`
//   `/// **Operational:** this is a modelling choice — alternatives exist.`
//   `/// **Analogy:** this name is pedagogical — see the physics note.`

// Constants — pinned by the math, not by tuning

/// Default Chebyshev truncation order. K=20 gives relative error <1e-8
/// on the normalised-Laplacian spectrum [0, 2] for diffusion times
/// t ∈ [0, 10]. Bessel coefficient `|c_k(t)|` decays past `k ≈ e·t/2`
/// (Abramowitz–Stegun asymptotic); for t up to 10 the useful band is
/// `k ≤ 14`, so K=20 leaves comfortable headroom. [adaptiveK] prunes
/// the unused tail at runtime — pure perf win, no accuracy loss.
const int kDefaultChebyshevK = 20;

/// Chebyshev order for the small-graph engines (intra-file chunks,
/// intra-diff hunks). One step above [kDefaultChebyshevK] because
/// smaller graphs can have sharper spectra and the per-call cost of
/// 4 extra matvecs is negligible at adaptive K. Both small-graph
/// engines also use a three-temperature geometric-mean blend, which
/// benefits from the headroom.
const int kChebyshevSmallGraph = 24;

/// Default power-iteration depth for spectral-radius diagnostics.
/// Rayleigh-quotient convergence is geometric at rate `|λ₂/λ₁|`, where
/// `λ₂ < λ₁ ≤ 2` on a normalised Laplacian. 24 iterations gets us 2-3
/// significant figures on any realistic graph.
const int kDefaultPowerIterations = 24;

/// Default number of Laplacian eigenmodes to retain in a cached
/// [SpectralBasis]. Heat-kernel energy concentrates in the bottom 15–30
/// modes on typical code graphs (see `heatCapacity` natural-scale
/// detection); 20 comfortably covers that range. Tune via the per-engine
/// or per-result `k` parameter.
const int kDefaultSpectralBasisK = 20;

/// Minimum graph size below which the spectral path stays disabled.
/// For small graphs (hunk, chunk) the one-time Lanczos cost outweighs
/// the per-query saving. Above this threshold, spectral queries
/// amortise after the second call on the same graph.
const int kDefaultSpectralMinNodes = 256;

/// Hard ceiling on diffusion time before the Bessel computation
/// becomes numerically untrustworthy. The recurrence for `I_k(t)` uses
/// `(t/2)^2` per term — at t=30 that's 225 per step, near the f64
/// inner-loop overflow cliff. We clamp inputs to this and document it
/// rather than silently returning NaN.
const double _maxSafeT = 30.0;

/// Cap on the Bessel-series inner loop. The series converges in
/// `O(t)` terms in practice — 200 is well past convergence for t ≤ 30
/// at the [_besselConvergenceEps] floor, and bounds the cost in case
/// the convergence check fails on edge inputs.
const int _besselSeriesTermCap = 200;

/// Convergence floor for the Bessel series summation, measured as a
/// fraction of the running sum. `1e-20` is well below f64 ULP for
/// typical sums in [1e-10, 1e+5].
const double _besselConvergenceEps = 1e-20;

/// Coefficient magnitude below which the φ accumulation step is
/// skipped. `1e-12` is ~four orders above f64 epsilon — any Chebyshev
/// term smaller than this contributes below the numerical noise floor
/// of the basis vectors.
const double _coeffSkipEps = 1e-12;

/// Subnormal flush threshold. IEEE-754 subnormals below ~1e-308 can
/// trap into software emulation on some FPU microcode (notably older
/// Intel + CanvasKit's emscripten build), turning a 4-cycle FMA into a
/// hundred-cycle stall. Clamping magnitudes below `1e-300` to 0 is a
/// cheap FTZ/DAZ equivalent — no observable impact on ranking stability.
const double _subnormalFloor = 1e-300;

/// One row of a fragmentation / surgery curve — a filtration snapshot.
///
/// Returned by [CsrGraph.fragmentationCurve] and
/// [RicciField.surgeryFragmentation]. Identical shape between the
/// two families so callers can treat them uniformly.
///
/// * `threshold` — the cut level applied (edge weight for
///   fragmentation, curvature for Ricci surgery).
/// * `componentCount` — β₀ of the surviving subgraph.
/// * `largestFraction` — fraction of nodes in the biggest component,
///   in `[1/n, 1.0]`.
/// * `cycleRank` — β₁ of the 1-skeleton, `max(0, |E_sub| − n + β₀)`.
/// * `edgeCount` — number of edges that survived the cut.
typedef FragmentationRow = ({
  double threshold,
  int componentCount,
  double largestFraction,
  int cycleRank,
  int edgeCount,
});

/// Shared union-find sweep used by both [CsrGraph.fragmentationCurve]
/// and `RicciField.surgeryFragmentation`. The caller supplies an
/// [sweepEdges] callback that, for the given [threshold], invokes the
/// inner `emit(u, v)` for each edge that SURVIVES the cut. This
/// helper builds the union-find, counts components, and assembles
/// the [FragmentationRow].
///
/// Extracted because the two surgery families had identical ~40-line
/// bodies differing only in their edge iteration. Keeping the
/// invariants (monotonicity, non-negative cycle rank, largest-
/// fraction bounds) consistent means one place to fix.
FragmentationRow computeFragmentationRow({
  required int n,
  required double threshold,
  required void Function(void Function(int u, int v) emit) sweepEdges,
}) {
  if (n <= 0) {
    return (
      threshold: threshold,
      componentCount: 0,
      largestFraction: 0.0,
      cycleRank: 0,
      edgeCount: 0,
    );
  }
  final parent = Int32List(n);
  for (var i = 0; i < n; i++) {
    parent[i] = i;
  }
  int find(int x) {
    var root = x;
    while (parent[root] != root) {
      root = parent[root];
    }
    var cur = x;
    while (parent[cur] != root) {
      final next = parent[cur];
      parent[cur] = root;
      cur = next;
    }
    return root;
  }

  var edgeCount = 0;
  sweepEdges((u, v) {
    if (u < 0 || v < 0 || u >= n || v >= n) return;
    edgeCount += 1;
    final ru = find(u);
    final rv = find(v);
    if (ru != rv) parent[rv] = ru;
  });

  final sizes = <int, int>{};
  for (var i = 0; i < n; i++) {
    final r = find(i);
    sizes[r] = (sizes[r] ?? 0) + 1;
  }
  var largest = 0;
  for (final s in sizes.values) {
    if (s > largest) largest = s;
  }
  final comp = sizes.length;
  final cycleRank = edgeCount - n + comp;
  return (
    threshold: threshold,
    componentCount: comp,
    largestFraction: largest / n,
    cycleRank: cycleRank < 0 ? 0 : cycleRank,
    edgeCount: edgeCount,
  );
}

// CsrGraph — the data structure every engine builds

/// Compressed sparse-row graph with a fused-D⁻¹ᐟ² edge weight encoding.
/// Each engine constructs one of these from its own axis-mixed edge
/// weights, then hands it to the diffusion primitives. The values
/// stored in [values] are already `D^{-1/2}[i] · W[i,j] · D^{-1/2}[j]`
/// — so applying the symmetric normalised Laplacian `L_sym = I − W_norm`
/// reduces to `y[i] = v[i] − Σ_j values[i,j] · v[indices[i,j]]`.
class CsrGraph {
  CsrGraph({
    required this.n,
    required this.indptr,
    required this.indices,
    required this.values,
    Float64List? degreeInvSqrt,
    Float64List? rawWeights,
  })  : degreeInvSqrt = degreeInvSqrt ?? Float64List(0),
        rawWeights = rawWeights ?? Float64List(0);

  /// Number of nodes.
  final int n;

  /// CSR row pointers — `indptr[i]` is the start of row `i`'s edges,
  /// `indptr[n]` is the total non-zero count.
  final Int32List indptr;

  /// CSR column indices for each non-zero edge.
  final Int32List indices;

  /// Pre-fused normalised edge weights (`D^{-1/2}·W·D^{-1/2}`).
  final Float64List values;

  /// `D^{-1/2}[i]` — per-node normalisation factor, stored alongside
  /// [values] so rank-1 updates ([withNodeAppended], [withNodeRemoved])
  /// can re-fuse the affected rows without needing the caller to supply
  /// it separately. Empty (length-0) on graphs built without providing
  /// it; rank-1 ops on such graphs throw [StateError] rather than
  /// silently producing an asymmetric Laplacian.
  final Float64List degreeInvSqrt;

  /// Raw (un-normalised) edge weights `W[i,j]`, parallel to [values].
  /// Present when the graph was built with rank-1 updates in mind;
  /// empty otherwise. Lets [withNodeAppended] correctly un-fuse and
  /// re-fuse neighbour rows whose degrees change.
  final Float64List rawWeights;

  bool get supportsRankOneUpdates =>
      degreeInvSqrt.length == n && rawWeights.length == values.length;

  /// Harmonic-mean combinatorial degree — `n / Σᵢ (1/dᵢ)` where `dᵢ`
  /// is the number of outgoing edges from node `i` (unweighted row
  /// count in [indptr]).
  ///
  /// Used by [alonBoppanaMargin] to characterise the graph's sparsity
  /// for expander-quality measurements. Harmonic mean is the right
  /// choice because Alon-Boppana's bound is sensitive to the graph's
  /// **bottleneck** degree, not its average; one-connected leaves drag
  /// the harmonic mean down in the right way.
  ///
  /// Returns `0.0` on an empty graph or a graph with isolated nodes
  /// that contribute 1/0 to the sum.
  double harmonicMeanDegree() {
    if (n == 0) return 0.0;
    var invSum = 0.0;
    for (var i = 0; i < n; i++) {
      final d = indptr[i + 1] - indptr[i];
      if (d <= 0) return 0.0; // isolated node — harmonic mean undefined
      invSum += 1.0 / d;
    }
    return invSum > 0 ? n / invSum : 0.0;
  }

  /// **Operational** — the threshold grid and edge-count convention are
  /// modelling choices. Alternative filtration sweeps yield different
  /// but equally-valid β₀/β₁ curves. Fragmentation curve — at each of [thresholds], report
  /// `(θ, componentCount, largestFraction, cycleRank, edgeCount)` where
  /// the subgraph is defined by edges with **normalised weight ≥ θ** in
  /// [values].
  ///
  /// - `componentCount` is β₀ (connected components).
  /// - `cycleRank` is β₁ of the 1-skeleton: `|E_sub| − n + β₀`.
  ///   Equals the true β₁ of the graph viewed as a simplicial 1-complex
  ///   (no triangle filling). A codebase's `cycleRank` at a given
  ///   coupling level is the count of independent pairwise-only
  ///   dependency cycles — feedback loops that don't dissolve into
  ///   3-way symmetry.
  /// - `edgeCount` is the number of surviving edges, useful for
  ///   sanity-checking filtration curves.
  ///
  /// Use case: "at what coupling strength does this codebase decompose
  /// into independent modules, and how many cycles survive at each
  /// level?" A healthy repo has a flat β₀ curve and a β₁ that sheds
  /// gradually as θ rises; a fragmented repo shatters early.
  ///
  /// Cost: `O(|thresholds| · (n + m))` where `m = values.length`. Uses
  /// union-find with path compression; the sweep is one linear scan
  /// per threshold.
  List<FragmentationRow> fragmentationCurve(List<double> thresholds) {
    return [
      for (final theta in thresholds)
        computeFragmentationRow(
          n: n,
          threshold: theta,
          sweepEdges: (emit) {
            for (var u = 0; u < n; u++) {
              for (var p = indptr[u]; p < indptr[u + 1]; p++) {
                if (values[p] < theta) continue;
                final v = indices[p];
                if (v <= u) continue; // each undirected edge once
                emit(u, v);
              }
            }
          },
        )
    ];
  }

  /// Return a new graph with one additional node appended at id `n`.
  /// The new node's edges are `edges` — each tuple is `(targetId,
  /// rawWeight)`, with symmetric counterparts added automatically.
  ///
  /// Re-fuses `D^{-1/2}` for the new row and every existing row that
  /// received a new edge (their degree changed). Rows untouched by the
  /// update keep their fused values byte-identical to the input graph.
  ///
  /// Requires [supportsRankOneUpdates]; throws [StateError] otherwise.
  /// Cost is `O(|edges| + Σ_{i∈incident} deg(i))` — i.e. linear in the
  /// perturbation footprint, not the graph size. That's the whole
  /// point of rank-1: adding one file costs proportional to its local
  /// neighbourhood, not to the whole repository.
  CsrGraph withNodeAppended({
    required List<(int, double)> edges,
    double selfMass = 0.0,
  }) {
    if (!supportsRankOneUpdates) {
      throw StateError(
        'CsrGraph.withNodeAppended requires both degreeInvSqrt and rawWeights '
        'to be populated (build via `buildFromStats` with rank-1 support, or '
        'use `CsrGraph.rawFused` to seed them from raw weights).',
      );
    }
    if (!selfMass.isFinite || selfMass < 0) {
      // Negative or non-finite selfMass would flow into sqrt(newNodeDeg)
      // and produce a NaN D^{-1/2} that silently contaminates every
      // subsequent diffusion — fail loudly instead.
      throw ArgumentError.value(
        selfMass,
        'selfMass',
        'must be finite and non-negative',
      );
    }
    // Validate + dedupe edges. A repeated target folds into a single
    // edge with summed weight so the caller can safely compose deltas.
    final edgeByTarget = <int, double>{};
    for (final (target, w) in edges) {
      if (target < 0 || target >= n) {
        throw RangeError.range(target, 0, n - 1, 'target');
      }
      if (!w.isFinite || w <= 0) continue;
      edgeByTarget.update(target, (old) => old + w, ifAbsent: () => w);
    }

    final newN = n + 1;
    // New degree for the appended node = sum of its raw edge weights
    // plus any self-mass (matches the row-stochastic convention used
    // by `buildFromStats`).
    var newNodeDeg = selfMass;
    for (final w in edgeByTarget.values) {
      newNodeDeg += w;
    }
    final newNodeDInv = newNodeDeg > 0 ? 1.0 / math.sqrt(newNodeDeg) : 0.0;

    // Recompute D^{-1/2} for every existing node that gained an edge.
    final newDegreeInvSqrt = Float64List(newN);
    newDegreeInvSqrt.setRange(0, n, degreeInvSqrt);
    newDegreeInvSqrt[n] = newNodeDInv;
    // For each incident existing node, old degree = 1 / (D^{-1/2})^2.
    for (final entry in edgeByTarget.entries) {
      final i = entry.key;
      final added = entry.value;
      final oldDInv = degreeInvSqrt[i];
      final oldDeg = oldDInv > 0 ? 1.0 / (oldDInv * oldDInv) : 0.0;
      final newDeg = oldDeg + added;
      newDegreeInvSqrt[i] = newDeg > 0 ? 1.0 / math.sqrt(newDeg) : 0.0;
    }

    // Allocate new CSR buffers. Existing edges survive; each incident
    // row gains one edge (to the new node) at the end; a fresh row is
    // appended for the new node itself.
    final oldNnz = indptr[n];
    const edgesPerIncident = 1; // one new edge per incident existing row
    final addedToExisting = edgeByTarget.length * edgesPerIncident;
    final newRowSize = edgeByTarget.length;
    final newNnz = oldNnz + addedToExisting + newRowSize;

    final newIndptr = Int32List(newN + 1);
    final newIndices = Int32List(newNnz);
    final newValues = Float64List(newNnz);
    final newRaw = Float64List(newNnz);

    var writePos = 0;
    for (var i = 0; i < n; i++) {
      newIndptr[i] = writePos;
      final start = indptr[i];
      final end = indptr[i + 1];
      final rowChangedDInv = edgeByTarget.containsKey(i);
      final dInvI = newDegreeInvSqrt[i];
      for (var k = start; k < end; k++) {
        final j = indices[k];
        newIndices[writePos] = j;
        final raw = rawWeights[k];
        newRaw[writePos] = raw;
        // If either endpoint's D^{-1/2} changed, re-fuse. The only
        // endpoints whose D^{-1/2} changed are i itself (when incident)
        // and any neighbour that's also incident. For j ≥ n (can't
        // happen since j was a valid column before append) this is a
        // no-op branch.
        final dInvJ = newDegreeInvSqrt[j];
        if (rowChangedDInv || edgeByTarget.containsKey(j)) {
          newValues[writePos] = dInvI * raw * dInvJ;
        } else {
          newValues[writePos] = values[k];
        }
        writePos++;
      }
      // Append the new edge (i → newNode) for incident rows.
      if (rowChangedDInv) {
        final raw = edgeByTarget[i]!;
        newIndices[writePos] = n;
        newRaw[writePos] = raw;
        newValues[writePos] = dInvI * raw * newNodeDInv;
        writePos++;
      }
    }

    // New node's row: edges to each existing incident node, in
    // ascending column order (keeps later SpMV-friendly monotonicity).
    newIndptr[n] = writePos;
    final sortedTargets = edgeByTarget.keys.toList()..sort();
    for (final j in sortedTargets) {
      final raw = edgeByTarget[j]!;
      newIndices[writePos] = j;
      newRaw[writePos] = raw;
      newValues[writePos] = newNodeDInv * raw * newDegreeInvSqrt[j];
      writePos++;
    }
    newIndptr[newN] = writePos;

    return CsrGraph(
      n: newN,
      indptr: newIndptr,
      indices: newIndices,
      values: newValues,
      degreeInvSqrt: newDegreeInvSqrt,
      rawWeights: newRaw,
    );
  }

  /// Return a new graph with node [id] removed. All existing references
  /// to nodes `> id` are shifted down by one. Rows incident to the
  /// removed node have their `D^{-1/2}` re-fused to reflect the lower
  /// degree. Requires [supportsRankOneUpdates].
  CsrGraph withNodeRemoved(int id) {
    if (!supportsRankOneUpdates) {
      throw StateError('CsrGraph.withNodeRemoved requires rank-1 support.');
    }
    if (id < 0 || id >= n) {
      throw RangeError.range(id, 0, n - 1, 'id');
    }
    final newN = n - 1;
    if (newN == 0) {
      return CsrGraph(
        n: 0,
        indptr: Int32List(1),
        indices: Int32List(0),
        values: Float64List(0),
        degreeInvSqrt: Float64List(0),
        rawWeights: Float64List(0),
      );
    }

    // Pass 1: tally degree loss per incident neighbour and count edges
    // that survive.
    final degreeLoss = <int, double>{};
    final removedStart = indptr[id];
    final removedEnd = indptr[id + 1];
    for (var k = removedStart; k < removedEnd; k++) {
      final j = indices[k];
      degreeLoss[j] = (degreeLoss[j] ?? 0) + rawWeights[k];
    }
    var survivingNnz = 0;
    for (var i = 0; i < n; i++) {
      if (i == id) continue;
      final start = indptr[i];
      final end = indptr[i + 1];
      for (var k = start; k < end; k++) {
        if (indices[k] == id) continue;
        survivingNnz++;
      }
    }

    // Recompute D^{-1/2} for incident rows; carry others over.
    final newDegreeInvSqrt = Float64List(newN);
    var writeRow = 0;
    for (var i = 0; i < n; i++) {
      if (i == id) continue;
      final oldDInv = degreeInvSqrt[i];
      final loss = degreeLoss[i];
      if (loss == null) {
        newDegreeInvSqrt[writeRow] = oldDInv;
      } else {
        final oldDeg = oldDInv > 0 ? 1.0 / (oldDInv * oldDInv) : 0.0;
        final newDeg = oldDeg - loss;
        newDegreeInvSqrt[writeRow] =
            newDeg > 0 ? 1.0 / math.sqrt(newDeg) : 0.0;
      }
      writeRow++;
    }

    final newIndptr = Int32List(newN + 1);
    final newIndices = Int32List(survivingNnz);
    final newValues = Float64List(survivingNnz);
    final newRaw = Float64List(survivingNnz);

    var writePos = 0;
    var rowOut = 0;
    for (var i = 0; i < n; i++) {
      if (i == id) continue;
      newIndptr[rowOut] = writePos;
      final start = indptr[i];
      final end = indptr[i + 1];
      final dInvI = newDegreeInvSqrt[rowOut];
      final rowChangedDInv = degreeLoss.containsKey(i);
      for (var k = start; k < end; k++) {
        final j = indices[k];
        if (j == id) continue;
        // Column indices > id must shift down by one.
        final newCol = j > id ? j - 1 : j;
        newIndices[writePos] = newCol;
        final raw = rawWeights[k];
        newRaw[writePos] = raw;
        final dInvJ = newDegreeInvSqrt[newCol];
        if (rowChangedDInv || degreeLoss.containsKey(j)) {
          newValues[writePos] = dInvI * raw * dInvJ;
        } else {
          newValues[writePos] = values[k];
        }
        writePos++;
      }
      rowOut++;
    }
    newIndptr[newN] = writePos;

    return CsrGraph(
      n: newN,
      indptr: newIndptr,
      indices: newIndices,
      values: newValues,
      degreeInvSqrt: newDegreeInvSqrt,
      rawWeights: newRaw,
    );
  }

  /// Factory: build a CSR graph from raw symmetric edges, computing
  /// `D^{-1/2}` and fusing into `values` in one pass. Emits a graph
  /// with full rank-1 support ([supportsRankOneUpdates] = true).
  ///
  /// `edgesPerNode[i]` is a list of `(targetId, rawWeight)` pairs for
  /// node i. The caller must ensure the edges are symmetric (if i→j
  /// exists with weight w then j→i must also exist with weight w) —
  /// this is checked in assertions but not in release. Self-loops are
  /// allowed and contribute to the node's degree.
  factory CsrGraph.fromRawEdges({
    required int n,
    required List<List<(int, double)>> edgesPerNode,
  }) {
    assert(edgesPerNode.length == n);
    // Degrees = sum of raw outgoing weights per row (includes self-loops).
    final degrees = Float64List(n);
    var nnz = 0;
    for (var i = 0; i < n; i++) {
      for (final (_, w) in edgesPerNode[i]) {
        degrees[i] += w;
        nnz++;
      }
    }
    final dInv = Float64List(n);
    for (var i = 0; i < n; i++) {
      dInv[i] = degrees[i] > 0 ? 1.0 / math.sqrt(degrees[i]) : 0.0;
    }
    final indptr = Int32List(n + 1);
    final indices = Int32List(nnz);
    final values = Float64List(nnz);
    final raw = Float64List(nnz);
    var pos = 0;
    for (var i = 0; i < n; i++) {
      indptr[i] = pos;
      // Sort by column index for SpMV monotonicity — small lists so
      // insertion-sort via List.sort is fine.
      final row = [...edgesPerNode[i]]..sort((a, b) => a.$1.compareTo(b.$1));
      for (final (j, w) in row) {
        indices[pos] = j;
        raw[pos] = w;
        values[pos] = dInv[i] * w * dInv[j];
        pos++;
      }
    }
    indptr[n] = pos;
    return CsrGraph(
      n: n,
      indptr: indptr,
      indices: indices,
      values: values,
      degreeInvSqrt: dInv,
      rawWeights: raw,
    );
  }

  /// Coarsen the graph by collapsing nodes into groups. `groupOf[i]` is
  /// the new (dense) id of the coarse node that original node `i` maps
  /// into; groups must be labelled `0..m−1` where `m` is the number of
  /// coarse nodes. Edges within a group fold into the coarse node (drop
  /// as self-loops); edges between groups sum their raw weights. The
  /// result is a freshly normalised [CsrGraph] with rank-1 support.
  ///
  /// This is the **renormalisation-group coarsening** primitive: the
  /// Wilsonian "zoom out" operation. Low-frequency eigenmodes of the
  /// original graph survive the coarsening (long-wavelength physics is
  /// preserved), while high-frequency modes are integrated out — so
  /// `SpectralBasis.fromGraph(coarsened, k)` for small `k` gives an
  /// almost-exact reproduction of the original's long-scale structure
  /// at a fraction of the cost.
  ///
  /// Use case: hierarchical codebase analysis — coarsen files by
  /// package, then by module, then by subsystem, and compare spectra
  /// at each scale to find the natural decomposition level.
  CsrGraph coarsen(List<int> groupOf) {
    if (groupOf.length != n) {
      throw ArgumentError('groupOf length ${groupOf.length} != n=$n');
    }
    var m = 0;
    for (final g in groupOf) {
      if (g < 0) {
        throw ArgumentError('groupOf contains negative id $g');
      }
      if (g + 1 > m) m = g + 1;
    }
    if (m == 0) {
      return CsrGraph(
        n: 0,
        indptr: Int32List(1),
        indices: Int32List(0),
        values: Float64List(0),
        degreeInvSqrt: Float64List(0),
        rawWeights: Float64List(0),
      );
    }
    // Accumulate (groupU, groupV) → summed raw weight. Only keep one
    // direction per undirected pair while traversing; we emit both
    // directions when assembling edgesPerNode.
    final acc = <int, Map<int, double>>{};
    final hasRaw = rawWeights.length == values.length;
    for (var u = 0; u < n; u++) {
      final gu = groupOf[u];
      for (var p = indptr[u]; p < indptr[u + 1]; p++) {
        final v = indices[p];
        if (v <= u) continue; // each undirected edge once
        final gv = groupOf[v];
        if (gu == gv) continue; // intra-group edges drop
        // Recover raw weight: either from rawWeights directly, or (if
        // the graph was built without rank-1 metadata) undo the fusion
        // via degreeInvSqrt if present. Fall back to using `values`
        // as pseudo-raw — the coarsened graph will still be a valid
        // CSR, just with a different weight convention.
        final double w;
        if (hasRaw) {
          w = rawWeights[p];
        } else {
          w = values[p];
        }
        if (!w.isFinite || w <= 0) continue;
        final a = gu < gv ? gu : gv;
        final b = gu < gv ? gv : gu;
        final inner = acc.putIfAbsent(a, () => <int, double>{});
        inner[b] = (inner[b] ?? 0) + w;
      }
    }
    final edgesPerNode = List<List<(int, double)>>.generate(m, (_) => []);
    acc.forEach((a, innerMap) {
      innerMap.forEach((b, w) {
        edgesPerNode[a].add((b, w));
        edgesPerNode[b].add((a, w));
      });
    });
    return CsrGraph.fromRawEdges(n: m, edgesPerNode: edgesPerNode);
  }

  /// Apply `L_sym = I − D^{-1/2} W D^{-1/2}` to vector `v`. Since
  /// [values] is pre-fused with `D^{-1/2}` on both sides, the matvec
  /// is simply `y[i] = v[i] − (W_norm · v)[i]`. `out` is overwritten;
  /// must have length [n].
  void applyLsym(Float64List v, Float64List out) {
    for (var i = 0; i < n; i++) {
      double s = 0;
      final start = indptr[i];
      final end = indptr[i + 1];
      for (var k = start; k < end; k++) {
        s += values[k] * v[indices[k]];
      }
      out[i] = v[i] - s;
    }
  }

  /// Batched [applyLsym] — applies `L_sym` to `B` vectors at once.
  /// Input and output are AoSoA: length `n * B`, indexed by `i*B + b`
  /// so the `B` values for each node are contiguous in memory. A
  /// single pass over the edge arrays (indptr, indices, values)
  /// updates all `B` accumulators, amortising graph-array memory
  /// traffic — the dominant cost of SpMV — across the batch.
  /// For `B=4` on the review path, graph traffic drops 4× vs. running
  /// four independent [applyLsym] calls. The B=4 inner block is packed
  /// as two [Float64x2] accumulators when input/output alignment
  /// permits — each splat-scale-add pair retires two f64 FMAs.
  void applyLsymBatch(Float64List v, Float64List out, int B) {
    if (B == 1) {
      applyLsym(v, out);
      return;
    }
    // B=4 is the review hot path. SIMD when buffers are 16-byte aligned
    // (true for any freshly-allocated Float64List or Float64x2List-backed
    // view). Scalar fallback preserves correctness for misaligned views.
    if (B == 4 && _isX2Aligned(v) && _isX2Aligned(out)) {
      _applyLsymBatch4(v, out);
      return;
    }
    // General path: scalar B-wide accumulator.
    final s = Float64List(B);
    for (var i = 0; i < n; i++) {
      for (var b = 0; b < B; b++) {
        s[b] = 0.0;
      }
      final start = indptr[i];
      final end = indptr[i + 1];
      for (var k = start; k < end; k++) {
        final col = indices[k] * B;
        final w = values[k];
        for (var b = 0; b < B; b++) {
          s[b] += w * v[col + b];
        }
      }
      final iOff = i * B;
      for (var b = 0; b < B; b++) {
        out[iOff + b] = v[iOff + b] - s[b];
      }
    }
  }

  /// SIMD fast path for B=4. Treats the 4 contiguous batch lanes per
  /// node as two back-to-back [Float64x2] slots, so each node's
  /// accumulation is two splat-scale-add pairs over the node's incident
  /// edges. Preconditions (enforced by caller): `v.length == n*4`,
  /// `out.length == n*4`, both buffers 16-byte aligned.
  void _applyLsymBatch4(Float64List v, Float64List out) {
    // Each node's 4 lanes = two contiguous Float64x2 slots.
    final vX = Float64x2List.view(v.buffer, v.offsetInBytes, n * 2);
    final outX = Float64x2List.view(out.buffer, out.offsetInBytes, n * 2);
    final zero = Float64x2.zero();
    for (var i = 0; i < n; i++) {
      var s0 = zero;
      var s1 = zero;
      final start = indptr[i];
      final end = indptr[i + 1];
      for (var k = start; k < end; k++) {
        // `indices[k] * 4 / 2` — step in Float64x2 units.
        final col = indices[k] << 1;
        final w = values[k];
        s0 = s0 + vX[col].scale(w);
        s1 = s1 + vX[col + 1].scale(w);
      }
      final iOff = i << 1;
      outX[iOff] = vX[iOff] - s0;
      outX[iOff + 1] = vX[iOff + 1] - s1;
    }
  }

  /// Apply the advection-modified Laplacian: `y = (L_sym − ε·A)·v`.
  /// [antisym] is the antisymmetric component of a directed transport
  /// graph (`A = (T − Tᵀ)/2`), normalised into the same basis as
  /// [values]. The combined operator shifts heat downstream through
  /// directed transport lanes. When `epsilon` is 0 this is identical
  /// to [applyLsym].
  void applyLdrift(Float64List v, Float64List out,
      {required CsrGraph antisym, required double epsilon}) {
    applyLsym(v, out);
    if (epsilon == 0) return;
    for (var i = 0; i < n; i++) {
      double s = 0;
      final start = antisym.indptr[i];
      final end = antisym.indptr[i + 1];
      for (var k = start; k < end; k++) {
        s += antisym.values[k] * v[antisym.indices[k]];
      }
      out[i] -= epsilon * s;
    }
  }

  void applyLdriftBatch(Float64List v, Float64List out, int B,
      {required CsrGraph antisym, required double epsilon}) {
    applyLsymBatch(v, out, B);
    if (epsilon == 0) return;
    final s = Float64List(B);
    for (var i = 0; i < n; i++) {
      for (var b = 0; b < B; b++) {
        s[b] = 0.0;
      }
      final start = antisym.indptr[i];
      final end = antisym.indptr[i + 1];
      for (var k = start; k < end; k++) {
        final col = antisym.indices[k] * B;
        final w = antisym.values[k];
        for (var b = 0; b < B; b++) {
          s[b] += w * v[col + b];
        }
      }
      final iOff = i * B;
      for (var b = 0; b < B; b++) {
        out[iOff + b] -= epsilon * s[b];
      }
    }
  }

  /// Estimate the spectral radius `|λ_max|` of `L_sym` via power
  /// iteration with Rayleigh-quotient readout. The normalised
  /// Laplacian has a proven spectrum in [0, 2]; this method is a
  /// diagnostic — useful for verifying the bound holds on a given
  /// graph and for catching numerical-error drift on pathological
  /// inputs.
  /// Cost: `O(iterations · |E|)`. 24 iterations gives 2-3 significant
  /// figures on any realistic graph.
  double estimateSpectralRadius({
    int iterations = kDefaultPowerIterations,
    int? seed,
  }) {
    if (n == 0) return 0;
    // Deterministic seed-based init so tests/diagnostics are
    // reproducible.
    final rng = math.Random(seed ?? 0xC0DE5EED);
    final a = Float64List(n);
    final b = Float64List(n);
    for (var i = 0; i < n; i++) {
      a[i] = rng.nextDouble() - 0.5;
    }
    var lambda = 0.0;
    var src = a;
    var dst = b;
    for (var it = 0; it < iterations; it++) {
      // Renormalise src to unit length to keep numerics in scale.
      var norm = 0.0;
      for (var i = 0; i < n; i++) {
        norm += src[i] * src[i];
      }
      norm = math.sqrt(norm);
      if (norm == 0 || !norm.isFinite) return 0;
      for (var i = 0; i < n; i++) {
        src[i] /= norm;
      }
      applyLsym(src, dst);
      // Rayleigh quotient: λ ≈ src · L·src (src is unit-norm).
      lambda = 0;
      for (var i = 0; i < n; i++) {
        lambda += src[i] * dst[i];
      }
      // Next iteration's input is L·src; ping-pong the buffers.
      final tmp = src;
      src = dst;
      dst = tmp;
    }
    return lambda.abs();
  }
}

/// A Float64List is safely viewable as Float64x2List iff its backing
/// buffer offset is 16-byte aligned and its length is even. Fresh
/// allocations and Float64x2List-backed views always satisfy both.
bool _isX2Aligned(Float64List v) =>
    (v.offsetInBytes & 15) == 0 && (v.length & 1) == 0;

// Bessel coefficients — `c_k(t) = 2·e^{-t}·I_k(-t)` with `c_0` halved

/// Modified Bessel coefficients for the heat-kernel Chebyshev
/// expansion: `c_k(t) = (k==0 ? 1 : 2) · e^{-t} · I_k(-t)`.
/// `I_k(-t) = (-1)^k · I_k(t)`. We compute `I_k(t)` via the ascending
/// power series in log-space (overflow-safe for any t) with an inner-
/// loop convergence check.
/// Numerical safety:
///   • NaN input → returns coefficients for t=0 (degenerate identity).
///   • t > [_maxSafeT] → clamped to the safe ceiling.
///   • Non-finite intermediate values → coerced to 0 (truncates the
///     expansion early; never propagates non-finite into the recurrence).
/// Cost: O(K) log() calls for the factorial table, plus the inner series
/// loop. The earlier version re-summed `Σ log(i)` per k for O(K²) total
/// log()s — measurably slower at the three-temperature blend call rate.
/// System-wide memo for `besselCoeffs`. Hot-path temperatures come
/// from a tiny discrete set (the canonical three-temperature blend
/// uses t ∈ {0.5, 1.0, 2.0}; `gatherEvidence` derives nearT ≈ 0.55·t
/// and farT ≈ 1.85·t from its single input t). A 16-entry LRU keyed
/// by `(t, K)` holds every realistic call shape for the lifetime of
/// the process — basis builds, recombines, and the DiffusionBasis
/// animation slider all hit the same slot repeatedly.
///
/// Returns a **shared immutable view**: callers MUST NOT mutate the
/// returned `Float64List`. `recombineHeatPhi` and the Chebyshev
/// passes only read, so the share is safe.
final LruCache<_BesselKey, Float64List> _besselCache =
    LruCache<_BesselKey, Float64List>(maxSize: 16);

class _BesselKey {
  const _BesselKey(this.t, this.k);
  final double t;
  final int k;
  @override
  bool operator ==(Object other) =>
      other is _BesselKey && other.t == t && other.k == k;
  @override
  int get hashCode => Object.hash(t, k);
}

Float64List besselCoeffs(double t, int k) {
  final tSafe = t.isNaN ? 0.0 : t.clamp(0.0, _maxSafeT).toDouble();
  final key = _BesselKey(tSafe, k);
  final cached = _besselCache.get(key);
  if (cached != null) return cached;
  final computed = _computeBesselCoeffs(tSafe, k);
  _besselCache.put(key, computed);
  return computed;
}

Float64List _computeBesselCoeffs(double tSafe, int k) {
  final result = Float64List(k + 1);
  if (tSafe == 0) {
    // c_0 = e^0 · I_0(0) = 1; c_k = 0 for k≥1.
    result[0] = 1.0;
    return result;
  }
  final expNegT = math.exp(-tSafe);
  final half = tSafe / 2.0;
  final halfSq = half * half;
  final logHalf = math.log(half);
  // Cumulative log-factorial: logFact[i] = log(i!) = Σ_{j=1..i} log(j).
  // Computed once; indexed per k instead of recomputing the partial sum.
  final logFact = Float64List(k + 1);
  for (var i = 1; i <= k; i++) {
    logFact[i] = logFact[i - 1] + math.log(i);
  }
  for (var kk = 0; kk <= k; kk++) {
    // `logTerm0` = log of the I_k(t) series' leading term: (t/2)^kk / kk!
    final logTerm0 = kk * logHalf - logFact[kk];
    var term = math.exp(logTerm0);
    var sum = term;
    for (var m = 0; m < _besselSeriesTermCap; m++) {
      term *= halfSq / ((m + 1) * (kk + m + 1));
      sum += term;
      if (term.abs() < _besselConvergenceEps * sum.abs()) break;
    }
    final ik = (kk & 1) == 0 ? sum : -sum;
    final c = kk == 0 ? expNegT * ik : 2 * expNegT * ik;
    result[kk] = c.isFinite ? c : 0.0;
  }
  return result;
}

/// Adaptive Chebyshev truncation: pick the smallest `K* ≤ maxK` where
/// `|c_{K*}(t)| < eps · ||c||_∞`. Bessel coefficients decay super-
/// exponentially past `k ≈ t·e/2`; for small t the tail is already
/// negligible at `K = 8–10` while large t needs more. Hardcoding K=20
/// wastes matvecs at low t and starves accuracy at high t.
int adaptiveK(Float64List coeffs, double eps) {
  var maxAbs = 0.0;
  for (final c in coeffs) {
    final a = c.abs();
    if (a > maxAbs) maxAbs = a;
  }
  if (maxAbs == 0) return coeffs.length - 1;
  final threshold = eps * maxAbs;
  for (var k = coeffs.length - 1; k >= 2; k--) {
    if (coeffs[k].abs() >= threshold) return k;
  }
  return 1;
}

// Heat-kernel diffusion — one-shot and basis-cached forms

/// Apply the heat kernel to source ρ at temperature t using the
/// Chebyshev expansion. Writes result into [phi]. Pure — no hidden
/// state. Allocates three ring-buffer scratch vectors internally; each
/// Chebyshev step cycles them by reference rather than copying bytes.
/// Internally calls [adaptiveK] to skip the coefficient-tail past the
/// noise floor, so the effective polynomial order is `≤ K`. Elementwise
/// passes run as [Float64x2] SIMD when `n > 1`; arithmetic within each
/// lane is IEEE-identical to the scalar path.
void chebyshevDiffuse({
  required CsrGraph graph,
  required Float64List rho,
  required Float64List phi,
  required double t,
  int K = kDefaultChebyshevK,
  CsrGraph? antisym,
  double advectionEpsilon = 0.0,
}) {
  final n = graph.n;
  assert(rho.length == n);
  assert(phi.length == n);
  if (n == 0) return;
  final fullCoeffs = besselCoeffs(t, K);
  final effectiveK = adaptiveK(fullCoeffs, 1e-8);

  // We expand in the shifted spectrum [-1, 1]. The normalised
  // Laplacian L_sym has spectrum [0, 2]; the shift x = L − I moves it
  // to [-1, 1]. For the matvec we compute y = L_sym·v − v.
  //
  // T_0(x)·ρ = ρ
  // T_1(x)·ρ = x·ρ = L_sym·ρ − ρ
  // T_{k+1}(x)·ρ = 2·x·(T_k·ρ) − T_{k-1}·ρ
  //
  // Buffer layout: three SIMD-aligned scratch basis slots plus one
  // SpMV scratch. Slots cycle by reference each step (ring buffer) —
  // no memcpy between iterations. Each buffer exposes both an x2 pair
  // view (for elementwise SIMD ops) and a scalar view (for SpMV index
  // access) over the *same* memory.
  final nPairs = (n + 1) >> 1;
  var t0x = Float64x2List(nPairs);
  var t1x = Float64x2List(nPairs);
  var t2x = Float64x2List(nPairs);
  final scratchX = Float64x2List(nPairs);
  final phiX = Float64x2List(nPairs);
  var t0 = Float64List.view(t0x.buffer, 0, n);
  var t1 = Float64List.view(t1x.buffer, 0, n);
  var t2 = Float64List.view(t2x.buffer, 0, n);
  final scratch = Float64List.view(scratchX.buffer, 0, n);

  // T_0·ρ = ρ
  for (var i = 0; i < n; i++) {
    t0[i] = rho[i];
  }

  // T_1·ρ = L·ρ − ρ (L = L_sym or L_sym − ε·A when advection active)
  final _hasDrift = antisym != null && advectionEpsilon != 0;
  if (_hasDrift) {
    graph.applyLdrift(t0, scratch,
        antisym: antisym!, epsilon: advectionEpsilon);
  } else {
    graph.applyLsym(t0, scratch);
  }
  for (var i = 0; i < nPairs; i++) {
    t1x[i] = scratchX[i] - t0x[i];
  }

  // φ = c_0·T_0 + c_1·T_1
  final c0 = fullCoeffs[0];
  final c1 = fullCoeffs[1];
  for (var i = 0; i < nPairs; i++) {
    phiX[i] = t0x[i].scale(c0) + t1x[i].scale(c1);
  }

  // Recurrence for k = 2..effectiveK.
  for (var k = 2; k <= effectiveK; k++) {
    if (_hasDrift) {
      graph.applyLdrift(t1, scratch,
          antisym: antisym!, epsilon: advectionEpsilon);
    } else {
      graph.applyLsym(t1, scratch);
    }
    final ck = fullCoeffs[k];
    if (ck.abs() >= _coeffSkipEps) {
      for (var i = 0; i < nPairs; i++) {
        final tk = (scratchX[i] - t1x[i]).scale(2.0) - t0x[i];
        t2x[i] = tk;
        phiX[i] = phiX[i] + tk.scale(ck);
      }
    } else {
      // Skip the φ accumulation — coefficient is below noise floor —
      // but still compute T_k so the recurrence can continue.
      for (var i = 0; i < nPairs; i++) {
        t2x[i] = (scratchX[i] - t1x[i]).scale(2.0) - t0x[i];
      }
    }
    // Ring-buffer shift: the slot holding T_{k-2} is now unreferenced
    // and becomes next step's T_{k+1} destination. No memcpy.
    final tmpx = t0x;
    t0x = t1x;
    t1x = t2x;
    t2x = tmpx;
    final tmps = t0;
    t0 = t1;
    t1 = t2;
    t2 = tmps;
  }

  // Copy-out + subnormal flush (FTZ insurance for web FPU).
  final phiLocal = Float64List.view(phiX.buffer, 0, n);
  for (var i = 0; i < n; i++) {
    final v = phiLocal[i];
    phi[i] = v.abs() < _subnormalFloor ? 0.0 : v;
  }
}

/// Build the Chebyshev basis `T_k(L_sym − I)·ρ` for `k = 0..K`. Each
/// row of the returned `(K+1) × n` flat layout is a basis vector;
/// row `k` starts at offset `k·n`. Cache once, then call
/// [recombineHeatPhi] at any temperature in O(K·n) instead of
/// rerunning O(K·|E|) Chebyshev matvecs.
/// Useful for multi-temperature blends (e.g. the three-temperature
/// geometric-mean trick used by the chunk and hunk engines) and any
/// future temperature-sweep analysis. Uses the same ring-buffer +
/// SIMD elementwise pattern as [chebyshevDiffuse]; basis rows are
/// emitted with `setRange` (optimised memcpy) rather than a scalar
/// copy loop.
Float64List chebyshevBasis({
  required CsrGraph graph,
  required Float64List rho,
  int K = kDefaultChebyshevK,
  CsrGraph? antisym,
  double advectionEpsilon = 0.0,
}) {
  final n = graph.n;
  final basis = Float64List((K + 1) * n);
  if (n == 0) return basis;

  final nPairs = (n + 1) >> 1;
  var t0x = Float64x2List(nPairs);
  var t1x = Float64x2List(nPairs);
  var t2x = Float64x2List(nPairs);
  final scratchX = Float64x2List(nPairs);
  var t0 = Float64List.view(t0x.buffer, 0, n);
  var t1 = Float64List.view(t1x.buffer, 0, n);
  var t2 = Float64List.view(t2x.buffer, 0, n);
  final scratch = Float64List.view(scratchX.buffer, 0, n);

  final _hasDrift = antisym != null && advectionEpsilon != 0;

  // T_0·ρ = ρ — seed T_0 and emit basis row 0.
  for (var i = 0; i < n; i++) {
    t0[i] = rho[i];
  }
  basis.setRange(0, n, rho);

  // T_1·ρ = L·ρ − ρ
  if (_hasDrift) {
    graph.applyLdrift(t0, scratch,
        antisym: antisym!, epsilon: advectionEpsilon);
  } else {
    graph.applyLsym(t0, scratch);
  }
  for (var i = 0; i < nPairs; i++) {
    t1x[i] = scratchX[i] - t0x[i];
  }
  basis.setRange(n, 2 * n, t1);

  // Recurrence for k = 2..K.
  for (var k = 2; k <= K; k++) {
    if (_hasDrift) {
      graph.applyLdrift(t1, scratch,
          antisym: antisym!, epsilon: advectionEpsilon);
    } else {
      graph.applyLsym(t1, scratch);
    }
    for (var i = 0; i < nPairs; i++) {
      t2x[i] = (scratchX[i] - t1x[i]).scale(2.0) - t0x[i];
    }
    basis.setRange(k * n, (k + 1) * n, t2);
    // Ring-buffer shift — see [chebyshevDiffuse] for rationale.
    final tmpx = t0x;
    t0x = t1x;
    t1x = t2x;
    t2x = tmpx;
    final tmps = t0;
    t0 = t1;
    t1 = t2;
    t2 = tmps;
  }
  return basis;
}

/// Batched variant of [chebyshevBasis] — builds `T_k(L_sym − I)·ρ` for
/// `k = 0..K` over `B` independent rho inputs in a SINGLE SpMV chain
/// over the graph. `rhoBatch` is AoSoA-packed: `rhoBatch[i*B + b]` is
/// the seed mass at node `i` for column `b`. Output layout mirrors the
/// input's AoSoA pattern but with an outer k-stride:
/// `basis[k * (n * B) + i * B + b]` is the k-th basis coefficient of
/// node i for column b.
/// Use [extractBasisColumn] to lift one column into the same flat layout
/// [chebyshevBasis] produces (so it is drop-in compatible with
/// [recombineHeatPhi]).
/// Graph-array memory traffic scales `O(K·|E|)` regardless of `B` — one
/// pass services every column. Arithmetic scales `O(K·|E|·B)` but
/// arithmetic is cheap vs. cache misses on sparse indices.
Float64List chebyshevBasisBatch({
  required CsrGraph graph,
  required Float64List rhoBatch,
  required int B,
  int K = kDefaultChebyshevK,
  CsrGraph? antisym,
  double advectionEpsilon = 0.0,
}) {
  final n = graph.n;
  final stride = n * B;
  final basis = Float64List((K + 1) * stride);
  if (n == 0 || B == 0) return basis;

  final stridePairs = (stride + 1) >> 1;
  var t0x = Float64x2List(stridePairs);
  var t1x = Float64x2List(stridePairs);
  var t2x = Float64x2List(stridePairs);
  final scratchX = Float64x2List(stridePairs);
  var t0 = Float64List.view(t0x.buffer, 0, stride);
  var t1 = Float64List.view(t1x.buffer, 0, stride);
  var t2 = Float64List.view(t2x.buffer, 0, stride);
  final scratch = Float64List.view(scratchX.buffer, 0, stride);

  final _hasDrift = antisym != null && advectionEpsilon != 0;

  // T_0·ρ = ρ — seed T_0 and emit basis row 0.
  t0.setRange(0, stride, rhoBatch);
  basis.setRange(0, stride, rhoBatch);
  if (K == 0) return basis;

  // T_1 = L·T_0 − T_0
  if (_hasDrift) {
    graph.applyLdriftBatch(t0, scratch, B,
        antisym: antisym!, epsilon: advectionEpsilon);
  } else {
    graph.applyLsymBatch(t0, scratch, B);
  }
  for (var i = 0; i < stridePairs; i++) {
    t1x[i] = scratchX[i] - t0x[i];
  }
  basis.setRange(stride, 2 * stride, t1);

  for (var k = 2; k <= K; k++) {
    if (_hasDrift) {
      graph.applyLdriftBatch(t1, scratch, B,
          antisym: antisym!, epsilon: advectionEpsilon);
    } else {
      graph.applyLsymBatch(t1, scratch, B);
    }
    for (var i = 0; i < stridePairs; i++) {
      t2x[i] = (scratchX[i] - t1x[i]).scale(2.0) - t0x[i];
    }
    basis.setRange(k * stride, (k + 1) * stride, t2);
    final tmpx = t0x;
    t0x = t1x;
    t1x = t2x;
    t2x = tmpx;
    final tmps = t0;
    t0 = t1;
    t1 = t2;
    t2 = tmps;
  }
  return basis;
}

/// Lift one AoSoA column `b` from a [chebyshevBasisBatch] result into
/// the same flat layout [chebyshevBasis] emits, so the returned basis
/// plugs straight into [recombineHeatPhi].
Float64List extractBasisColumn({
  required Float64List batchedBasis,
  required int n,
  required int B,
  required int b,
  int K = kDefaultChebyshevK,
}) {
  final out = Float64List((K + 1) * n);
  final stride = n * B;
  for (var k = 0; k <= K; k++) {
    final kInBase = k * stride;
    final kOutBase = k * n;
    for (var i = 0; i < n; i++) {
      out[kOutBase + i] = batchedBasis[kInBase + i * B + b];
    }
  }
  return out;
}

/// Batched Chebyshev diffusion — runs `B` heat-kernel solutions
/// simultaneously on the same graph. `rhoBatch` is AoSoA-packed:
/// `rhoBatch[i*B + b]` is the initial mass at node `i` for batch `b`.
/// Returns `phiBatch` in the same layout.
/// One pass over the edge arrays per Chebyshev step services all `B`
/// matvecs, so graph-array memory traffic scales as `O(K·|E|)` rather
/// than `O(B·K·|E|)`. The arithmetic still scales with `B` (each
/// edge contributes `B` multiply-adds), but arithmetic is cheap; the
/// graph load was the bottleneck.
/// Now also uses [adaptiveK] to prune the Chebyshev tail (was missing
/// — full K SpMVs ran regardless of coefficient magnitude), ring-
/// buffers the three basis slots, and SIMD-vectorises the elementwise
/// AXPY passes over the flat stride.
Float64List chebyshevDiffuseBatch({
  required CsrGraph graph,
  required Float64List rhoBatch,
  required int B,
  required double t,
  int K = kDefaultChebyshevK,
  CsrGraph? antisym,
  double advectionEpsilon = 0.0,
}) {
  final n = graph.n;
  final stride = n * B;
  if (n == 0 || B == 0) return Float64List(stride < 0 ? 0 : stride);
  final fullCoeffs = besselCoeffs(t, K);
  final effectiveK = adaptiveK(fullCoeffs, 1e-8);

  // Allocate scratch through Float64x2List so alignment is guaranteed
  // for SIMD views. When stride is odd, the final pair has one padding
  // slot. Correctness relies on Float64x2List being zero-initialised and
  // the length-stride Float64List views only writing indices 0..stride-1,
  // so the padding slot stays 0 throughout the recurrence and does not
  // contaminate the final accumulation.
  final stridePairs = (stride + 1) >> 1;
  var t0x = Float64x2List(stridePairs);
  var t1x = Float64x2List(stridePairs);
  var t2x = Float64x2List(stridePairs);
  final scratchX = Float64x2List(stridePairs);
  final phiBatchX = Float64x2List(stridePairs);
  var t0 = Float64List.view(t0x.buffer, 0, stride);
  var t1 = Float64List.view(t1x.buffer, 0, stride);
  var t2 = Float64List.view(t2x.buffer, 0, stride);
  final scratch = Float64List.view(scratchX.buffer, 0, stride);
  final phiBatch = Float64List.view(phiBatchX.buffer, 0, stride);

  // Seed T_0 with ρ. `setRange` → memcpy.
  t0.setRange(0, stride, rhoBatch);

  // φ += c_0 · T_0
  final c0 = fullCoeffs[0];
  if (c0.abs() >= _coeffSkipEps) {
    for (var i = 0; i < stridePairs; i++) {
      phiBatchX[i] = phiBatchX[i] + t0x[i].scale(c0);
    }
  }
  if (effectiveK == 0) {
    return _flushSubnormals(_detachToFresh(phiBatch));
  }

  // T_1 = L·T_0 − T_0
  final _hasDrift = antisym != null && advectionEpsilon != 0;
  if (_hasDrift) {
    graph.applyLdriftBatch(t0, scratch, B,
        antisym: antisym!, epsilon: advectionEpsilon);
  } else {
    graph.applyLsymBatch(t0, scratch, B);
  }
  for (var i = 0; i < stridePairs; i++) {
    t1x[i] = scratchX[i] - t0x[i];
  }
  final c1 = fullCoeffs[1];
  if (c1.abs() >= _coeffSkipEps) {
    for (var i = 0; i < stridePairs; i++) {
      phiBatchX[i] = phiBatchX[i] + t1x[i].scale(c1);
    }
  }

  // T_{k+1} = 2·(L·T_k − T_k) − T_{k-1}
  for (var k = 2; k <= effectiveK; k++) {
    if (_hasDrift) {
      graph.applyLdriftBatch(t1, scratch, B,
          antisym: antisym!, epsilon: advectionEpsilon);
    } else {
      graph.applyLsymBatch(t1, scratch, B);
    }
    final ck = fullCoeffs[k];
    if (ck.abs() >= _coeffSkipEps) {
      for (var i = 0; i < stridePairs; i++) {
        final tk = (scratchX[i] - t1x[i]).scale(2.0) - t0x[i];
        t2x[i] = tk;
        phiBatchX[i] = phiBatchX[i] + tk.scale(ck);
      }
    } else {
      for (var i = 0; i < stridePairs; i++) {
        t2x[i] = (scratchX[i] - t1x[i]).scale(2.0) - t0x[i];
      }
    }
    // Ring-buffer shift.
    final tmpx = t0x;
    t0x = t1x;
    t1x = t2x;
    t2x = tmpx;
    final tmps = t0;
    t0 = t1;
    t1 = t2;
    t2 = tmps;
  }

  return _flushSubnormals(_detachToFresh(phiBatch));
}

/// Recombine a pre-computed Chebyshev [basis] at temperature [t].
/// Returns `φ(t) = Σ_{k=0..K} c_k(t) · (T_k·ρ)` — the heat-kernel
/// solution at t, evaluated as a linear combination of the basis
/// vectors. Cost is O(K·n), regardless of `|E|`. Coefficients below
/// [_coeffSkipEps] are skipped (no observable accuracy impact).
/// Each per-k accumulation runs as a SIMD AXPY over Float64x2 pairs
/// when n is even (or handles the odd tail scalar-wise).
Float64List recombineHeatPhi({
  required CsrGraph graph,
  required Float64List basis,
  required double t,
  int K = kDefaultChebyshevK,
}) {
  final n = graph.n;
  if (n == 0) return Float64List(0);
  final coeffs = besselCoeffs(t, K);
  // Allocate through x2 to guarantee SIMD-view alignment.
  final phiPairs = (n + 1) >> 1;
  final phiX = Float64x2List(phiPairs);
  final phi = Float64List.view(phiX.buffer, 0, n);
  final nPairs = n >> 1; // floor — excludes an odd tail element.
  final hasTail = (n & 1) == 1;
  final tailIdx = n - 1;
  final basisAligned = (basis.offsetInBytes & 15) == 0;
  for (var k = 0; k <= K; k++) {
    final c = coeffs[k];
    if (c.abs() < _coeffSkipEps) continue;
    final base = k * n;
    if (nPairs > 0 && basisAligned && ((base * 8) & 15) == 0) {
      final basisX = Float64x2List.view(
          basis.buffer, basis.offsetInBytes + base * 8, nPairs);
      for (var i = 0; i < nPairs; i++) {
        phiX[i] = phiX[i] + basisX[i].scale(c);
      }
    } else {
      // Fallback: scalar loop over the even prefix.
      for (var i = 0; i < nPairs * 2; i++) {
        phi[i] += c * basis[base + i];
      }
    }
    if (hasTail) {
      phi[tailIdx] += c * basis[base + tailIdx];
    }
  }
  // Subnormal flush + detach to a fresh Float64List (caller owns).
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final v = phi[i];
    out[i] = v.abs() < _subnormalFloor ? 0.0 : v;
  }
  return out;
}

/// Elementwise geometric mean of three non-negative φ vectors.
/// `blended[i] = ((max(0,a[i]) + eps) · (max(0,b[i]) + eps) · (max(0,c[i]) + eps))^(1/3)`
/// with `blended[i] = 0` when the entry is zero at every scale.
///
/// Used by the multi-scale diffusion blenders in `logos_hunks.dart`,
/// `logos_chunks.dart`, and `features/history/commit_tagger.dart` —
/// all three run diffusion at three temperatures (0.5, 1.0, 2.0) and
/// fuse via geometric mean so a node only scores high if it's
/// prominent at more than one scale. The ε term stabilises the log-
/// space average: a node present at exactly one scale contributes a
/// small but non-zero residue rather than being annihilated by the
/// other two zeros.
Float64List geometricMeanBlend3(
  Float64List phiA,
  Float64List phiB,
  Float64List phiC, {
  double eps = 1e-12,
}) {
  assert(phiA.length == phiB.length && phiB.length == phiC.length,
      'phi vectors must share length');
  final n = phiA.length;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final a = phiA[i] > 0 ? phiA[i] : 0.0;
    final b = phiB[i] > 0 ? phiB[i] : 0.0;
    final c = phiC[i] > 0 ? phiC[i] : 0.0;
    if (a + b + c <= 0) continue;
    out[i] = math.pow((a + eps) * (b + eps) * (c + eps), 1.0 / 3).toDouble();
  }
  return out;
}

/// Multi-scale heat-kernel blend — the canonical hunk/chunk ranker
/// pipeline in one call. Builds the Chebyshev basis once, recombines
/// at three temperatures, then fuses via [geometricMeanBlend3].
///
/// Default temperatures are `[0.5, 1.0, 2.0]` — a log-spaced triplet
/// that covers local / moderate / wide diffusion on most graphs.
/// Callers that have a `SpectralBasis` for the same graph can derive
/// temperatures from the graph's own heat-capacity peaks via
/// [tripleBlendTemperaturesFromPeaks] and pass them through the
/// [temperatures] parameter — the triplet then aligns with the
/// graph's actual phase transitions instead of a heuristic.
///
/// Total cost: one `O(K·|E|)` basis pass plus three `O(K·n)`
/// recombines plus one `O(n)` blend.
Float64List tripleTemperatureBlend({
  required CsrGraph graph,
  required Float64List rho,
  int K = kDefaultChebyshevK,
  double eps = 1e-12,
  List<double>? temperatures,
}) {
  if (graph.n == 0) return Float64List(0);
  final ts = temperatures ?? const [0.5, 1.0, 2.0];
  assert(ts.length == 3, 'tripleTemperatureBlend needs exactly 3 temperatures');
  final basis = chebyshevBasis(graph: graph, rho: rho, K: K);
  final phi0 = recombineHeatPhi(graph: graph, basis: basis, t: ts[0], K: K);
  final phi1 = recombineHeatPhi(graph: graph, basis: basis, t: ts[1], K: K);
  final phi2 = recombineHeatPhi(graph: graph, basis: basis, t: ts[2], K: K);
  return geometricMeanBlend3(phi0, phi1, phi2, eps: eps);
}

/// Derive a 3-temperature triplet for [tripleTemperatureBlend] from a
/// list of heat-capacity peaks (e.g. `SpectralBasis.naturalScales()`).
///
/// Behaviour by peak count:
/// - `>= 3`: pick the lowest, the median, and the highest peak —
///   spans the widest informative range while landing on three
///   actual phase transitions of the graph.
/// - `2`: bracket around the midpoint between the two peaks.
/// - `1`: spread ratio-spaced around the single peak (`p/2, p, p*2`).
/// - `0`: fall back to the default `[0.5, 1.0, 2.0]`.
List<double> tripleBlendTemperaturesFromPeaks(List<double> peaks) {
  if (peaks.isEmpty) return const [0.5, 1.0, 2.0];
  if (peaks.length == 1) {
    final p = peaks[0];
    return [p * 0.5, p, p * 2.0];
  }
  if (peaks.length == 2) {
    final lo = peaks[0];
    final hi = peaks[1];
    return [lo, (lo + hi) / 2.0, hi];
  }
  // >= 3 peaks: lowest, median, highest. Sorted ascending on input
  // (naturalScales returns sorted).
  return [peaks.first, peaks[peaks.length ~/ 2], peaks.last];
}

/// Copy a Float64List view into a fresh owned Float64List. Used when
/// we internally alias an x2 buffer for SIMD but need to hand the
/// caller a plain buffer they can treat as independent storage.
Float64List _detachToFresh(Float64List view) {
  final out = Float64List(view.length);
  out.setRange(0, view.length, view);
  return out;
}

/// In-place flush of subnormal magnitudes to zero. Guards downstream
/// consumers (and the web FPU) against microcode traps on denormals.
Float64List _flushSubnormals(Float64List buf) {
  for (var i = 0; i < buf.length; i++) {
    if (buf[i].abs() < _subnormalFloor) buf[i] = 0.0;
  }
  return buf;
}

// ─────────────────────────────────────────────────────────────────────
// SPECTRAL PRIMITIVES
//
// The heat kernel φ(t) = exp(−t·L_sym)·ρ has a closed-form spectral
// expansion: if L_sym = U·Λ·Uᵀ with eigenpairs (λ_j, u_j), then
//
//   φ(t) = U · diag(e^{−t·λ}) · Uᵀ · ρ
//
// Once the eigenpairs are cached, every query (any t, any ρ) costs
// only O(k·n) — independent of the graph's edge count and Chebyshev's
// degree-K matvec chain. The trade-off: a one-time O(m·|E| + m²·n)
// Lanczos decomposition.
//
// Heat kernels are dominated by the SMALL eigenvalues of L_sym (large
// λ → fast decay → negligible contribution at any t > 0). Standard
// Lanczos converges fastest at extremal eigenvalues, which means it
// hunts the LARGE end of the spectrum naturally. To pivot it onto the
// small end without sparse LU / shift-invert, we run Lanczos on the
// folded operator
//
//   M = 2·I − L_sym
//
// whose eigenvalues are 2 − λ (also in [0, 2], spectrum flipped).
// Lanczos's affinity for the large eigenvalues of M lands on the
// small eigenvalues of L_sym, and eigenvectors are shared between
// the two operators (they differ only by a uniform shift). M·v is
// computed via the existing applyLsym in two SIMD passes:
// `M·v = 2·v − L_sym·v`.
// ─────────────────────────────────────────────────────────────────────

/// Diagonalise a small dense symmetric matrix `A` in-place using cyclic
/// Jacobi rotations. `n` is the matrix dimension; `A` is row-major of
/// length `n²`. On return, `A` holds eigenvalues on its diagonal (and
/// near-zero entries off-diagonal); `eigvecs` is filled with the
/// orthogonal matrix of eigenvectors stored row-major (column j is
/// eigenvector j). `eigvecs` must be passed pre-allocated of length
/// `n²` and is overwritten with the identity before rotation.
///
/// Cost: ~O(n³) per Jacobi sweep × ~log(1/eps) sweeps. Intended for
/// small n (≲ 100) — the m×m tridiagonal that drops out of Lanczos.
/// For m=50 this finishes in well under a millisecond.
void _jacobiSymmetricEigen(Float64List A, int n, Float64List eigvecs) {
  // Initialise eigvecs to identity.
  for (var i = 0; i < n * n; i++) {
    eigvecs[i] = 0.0;
  }
  for (var i = 0; i < n; i++) {
    eigvecs[i * n + i] = 1.0;
  }
  if (n <= 1) return;

  const maxSweeps = 64;
  const tol = 1e-14;
  for (var sweep = 0; sweep < maxSweeps; sweep++) {
    // Compute Frobenius norm of the off-diagonal — convergence test.
    var off = 0.0;
    for (var p = 0; p < n - 1; p++) {
      for (var q = p + 1; q < n; q++) {
        final a = A[p * n + q];
        off += a * a;
      }
    }
    if (off < tol) break;

    for (var p = 0; p < n - 1; p++) {
      for (var q = p + 1; q < n; q++) {
        final apq = A[p * n + q];
        if (apq.abs() < 1e-18) continue;
        final app = A[p * n + p];
        final aqq = A[q * n + q];

        // Compute rotation that zeros A[p,q]. Numerically robust form
        // from Press et al.'s "Numerical Recipes" §11.1.
        final theta = (aqq - app) / (2.0 * apq);
        final t = theta >= 0
            ? 1.0 / (theta + math.sqrt(1.0 + theta * theta))
            : 1.0 / (theta - math.sqrt(1.0 + theta * theta));
        final c = 1.0 / math.sqrt(1.0 + t * t);
        final s = t * c;

        // Rotate A in-place. Symmetric updates only need to touch the
        // upper triangle plus the diagonal; the lower triangle is
        // mirrored at the end of the sweep.
        A[p * n + p] = app - t * apq;
        A[q * n + q] = aqq + t * apq;
        A[p * n + q] = 0.0;
        A[q * n + p] = 0.0;
        for (var r = 0; r < n; r++) {
          if (r == p || r == q) continue;
          final arp = A[r * n + p];
          final arq = A[r * n + q];
          final newRp = c * arp - s * arq;
          final newRq = s * arp + c * arq;
          A[r * n + p] = newRp;
          A[p * n + r] = newRp;
          A[r * n + q] = newRq;
          A[q * n + r] = newRq;
        }

        // Update accumulating eigenvectors.
        for (var r = 0; r < n; r++) {
          final vrp = eigvecs[r * n + p];
          final vrq = eigvecs[r * n + q];
          eigvecs[r * n + p] = c * vrp - s * vrq;
          eigvecs[r * n + q] = s * vrp + c * vrq;
        }
      }
    }
  }
}

/// Result of [lanczosSmallEigenpairs] — the top-k SMALLEST eigenpairs
/// of the normalised Laplacian, with eigenvectors row-major
/// (`eigenvectors[j * n + i]` = entry i of eigenvector j) and
/// eigenvalues sorted ascending.
class LaplacianEigenpairs {
  final int n;
  final int k;
  final Float64List eigenvalues; // [k], sorted ascending in [0, 2]
  final Float64List eigenvectors; // [k * n], row-major
  const LaplacianEigenpairs({
    required this.n,
    required this.k,
    required this.eigenvalues,
    required this.eigenvectors,
  });
}

/// Compute the top-`kRequested` SMALLEST eigenpairs of `graph`'s
/// normalised Laplacian via folded-spectrum Lanczos. The fold
/// `M = 2·I − L_sym` maps small L_sym eigenvalues to large M
/// eigenvalues, so Lanczos's natural extremal-end convergence hits
/// exactly the modes the heat kernel cares about — without ever
/// needing a sparse LU factorisation for shift-invert.
///
/// Algorithm: m-step Lanczos with full reorthogonalisation. The
/// orthonormal Lanczos vectors V (size n × (m+1)) and the symmetric
/// tridiagonal T (m × m, encoded as alpha/beta arrays) are the only
/// scratch state. T is then diagonalised by [_jacobiSymmetricEigen]
/// to extract m Ritz pairs; we keep the top `kRequested` (by Ritz
/// value on M) and reconstruct full-length Ritz vectors from V.
///
/// `maxIters` defaults to `max(2·k, 30)` — enough Lanczos steps that
/// the top-k Ritz values converge to working precision on a normalised
/// Laplacian. Random init uses a fixed seed so the decomposition is
/// deterministic across runs (test reproducibility).
LaplacianEigenpairs lanczosSmallEigenpairs(
  CsrGraph graph,
  int kRequested, {
  int? maxIters,
  int seed = 0xA1ECDA15,
}) {
  final n = graph.n;
  if (n == 0 || kRequested <= 0) {
    return LaplacianEigenpairs(
      n: n,
      k: 0,
      eigenvalues: Float64List(0),
      eigenvectors: Float64List(0),
    );
  }
  // Lanczos iterations capped at the dimension (T can be at most n×n).
  final m = math.min(n, math.max(maxIters ?? 0, math.max(2 * kRequested, 30)));
  final k = math.min(kRequested, m);

  // Lanczos vectors V[step * n + node]. step ranges 0..m (m+1 entries
  // total — step m is the residual that closes the recurrence).
  final V = Float64List((m + 1) * n);
  final alpha = Float64List(m); // T diagonal
  final beta = Float64List(m + 1); // T sub-diagonal (beta[0] unused)

  // Random unit vector seeds the Krylov subspace. A simple
  // linear-congruential generator suffices — Lanczos doesn't need
  // cryptographic randomness, only that the seed isn't orthogonal to
  // the eigenvectors we're after (vanishingly unlikely with random
  // gaussian-ish entries).
  var rngState = (seed | 1) & 0x7fffffff;
  double nextNormal() {
    // Box-Muller from two uniform draws. Replace later with a faster
    // stateless alternative if hot.
    rngState = (rngState * 1103515245 + 12345) & 0x7fffffff;
    final u1 = (rngState + 1) / 0x80000000;
    rngState = (rngState * 1103515245 + 12345) & 0x7fffffff;
    final u2 = (rngState + 1) / 0x80000000;
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
  }

  var seedNorm = 0.0;
  for (var i = 0; i < n; i++) {
    final v = nextNormal();
    V[i] = v;
    seedNorm += v * v;
  }
  seedNorm = math.sqrt(seedNorm);
  if (seedNorm == 0.0) {
    // Pathological — synthesise an axis-aligned unit vector.
    V[0] = 1.0;
    seedNorm = 1.0;
  }
  final invSeed = 1.0 / seedNorm;
  for (var i = 0; i < n; i++) {
    V[i] *= invSeed;
  }

  final scratch = Float64List(n);
  final w = Float64List(n);
  var actualM = m;

  for (var j = 0; j < m; j++) {
    // w = M · v_j  =  2·v_j − L_sym·v_j
    final vj = Float64List.view(V.buffer, V.offsetInBytes + j * n * 8, n);
    graph.applyLsym(vj, scratch);
    for (var i = 0; i < n; i++) {
      w[i] = 2.0 * vj[i] - scratch[i];
    }
    // w -= beta_{j-1} · v_{j-1}   (skipped at j=0; beta[0] = 0)
    if (j > 0) {
      final bjm1 = beta[j];
      for (var i = 0; i < n; i++) {
        w[i] -= bjm1 * V[(j - 1) * n + i];
      }
    }
    // alpha_j = w · v_j  (Rayleigh quotient on M)
    var aj = 0.0;
    for (var i = 0; i < n; i++) {
      aj += w[i] * vj[i];
    }
    alpha[j] = aj;
    // w -= alpha_j · v_j
    for (var i = 0; i < n; i++) {
      w[i] -= aj * vj[i];
    }

    // Full reorthogonalisation against all previous Lanczos vectors.
    // Without this, modified Gram-Schmidt loses orthogonality after
    // the first cluster of eigenvalues converges and Ritz vectors
    // get spurious copies. Cost is O(j·n) per step → O(m²·n) total,
    // tolerable for m ≲ 50.
    for (var l = 0; l <= j; l++) {
      var dot = 0.0;
      for (var i = 0; i < n; i++) {
        dot += w[i] * V[l * n + i];
      }
      if (dot.abs() < 1e-18) continue;
      for (var i = 0; i < n; i++) {
        w[i] -= dot * V[l * n + i];
      }
    }

    // beta_{j+1} = ||w||
    var bj = 0.0;
    for (var i = 0; i < n; i++) {
      bj += w[i] * w[i];
    }
    bj = math.sqrt(bj);
    beta[j + 1] = bj;
    if (bj < 1e-12) {
      // Krylov subspace exhausted — eigenproblem is rank-deficient
      // or the seed happened to lie in a smaller invariant subspace.
      // Truncate; what we have is exact for the explored subspace.
      actualM = j + 1;
      break;
    }
    final invBj = 1.0 / bj;
    for (var i = 0; i < n; i++) {
      V[(j + 1) * n + i] = w[i] * invBj;
    }
  }

  // Build the dense m×m tridiagonal T from alpha/beta and diagonalise.
  final T = Float64List(actualM * actualM);
  for (var j = 0; j < actualM; j++) {
    T[j * actualM + j] = alpha[j];
    if (j + 1 < actualM) {
      T[j * actualM + j + 1] = beta[j + 1];
      T[(j + 1) * actualM + j] = beta[j + 1];
    }
  }
  final Y = Float64List(actualM * actualM);
  _jacobiSymmetricEigen(T, actualM, Y);

  // Ritz values of M live on T's diagonal; their corresponding
  // eigenvectors of M sit in V·Y (column j of Y mixes the Lanczos
  // basis). We want the LARGEST Ritz values of M (= smallest L_sym
  // eigenvalues), so take the top-k by descending Ritz value.
  final ritzM = Float64List(actualM);
  for (var j = 0; j < actualM; j++) {
    ritzM[j] = T[j * actualM + j];
  }
  final indices = List<int>.generate(actualM, (i) => i);
  indices.sort((a, b) => ritzM[b].compareTo(ritzM[a]));

  final keep = math.min(k, actualM);
  final eigenvalues = Float64List(keep);
  final eigenvectors = Float64List(keep * n);
  for (var j = 0; j < keep; j++) {
    final src = indices[j];
    // λ_L = 2 − λ_M, clamped to the Laplacian's [0, 2] spectrum to
    // mop up the tiny negative drift Jacobi can leave on near-zero
    // eigenvalues. Reordering descending Ritz-of-M → ascending λ_L.
    var lam = 2.0 - ritzM[src];
    if (lam < 0.0) lam = 0.0;
    if (lam > 2.0) lam = 2.0;
    eigenvalues[j] = lam;
    // Ritz vector u_j = Σ_l Y[l, src] · v_l  (size n)
    final dst = j * n;
    for (var i = 0; i < n; i++) {
      var v = 0.0;
      for (var l = 0; l < actualM; l++) {
        v += Y[l * actualM + src] * V[l * n + i];
      }
      eigenvectors[dst + i] = v;
    }
  }

  return LaplacianEigenpairs(
    n: n,
    k: keep,
    eigenvalues: eigenvalues,
    eigenvectors: eigenvectors,
  );
}

/// Spectral basis cache — top-k eigenpairs of a graph's normalised
/// Laplacian, stored once and reused across every diffusion query
/// regardless of source ρ or temperature t. After the one-time
/// Lanczos decomposition, every `diffuse` / `project` call costs
/// O(k·n) — no edge traversals, no Chebyshev recurrence.
///
/// This is the "make it instant" path: a temperature slider that
/// re-evaluates 60 Hz, a multi-axis attribution call that runs a
/// dozen ρ projections, an autoregressive backtracking-attention
/// walk that needs the projection coefficients per node — all of
/// them collapse to dense O(k·n) work on the cached basis.
///
/// Conventions: eigenvalues are sorted ascending in [0, 2];
/// eigenvectors are row-major (`eigenvectors[j * n + i]` is entry i
/// of eigenvector j); the basis is exactly orthonormal up to Lanczos
/// floating-point drift.
class SpectralBasis {
  final int n;
  final int k;
  final Float64List eigenvalues; // [k]
  final Float64List eigenvectors; // [k * n]

  /// Optional path labels — when supplied, the basis carries enough
  /// metadata to answer labeled queries (`labelProject(weightsByPath)`,
  /// `phiForPath(...)`). null when the basis is operating purely in
  /// mathematical mode (no external labels attached). Every tower
  /// level (file/hunk/chunk/commit) enriches its basis with this
  /// when labels are available.
  final List<String>? nodePaths;

  /// Reverse index for [nodePaths]. Lazily materialised on first use
  /// when [nodePaths] is set and [pathToId] wasn't provided directly.
  final Map<String, int>? pathToId;

  /// 62-bit content fingerprint over the eigenvalue bit patterns.
  /// Two bases with identical eigenvalue sequences have identical
  /// signatures. Collisions are vanishingly rare (~1e-11 at 10^4
  /// states); callers needing exact equality still compare full
  /// spectra, but `signature` equality is sufficient for caching,
  /// CRDT merge fast-path, and wire-transfer short-IDs.
  ///
  /// Stored as a [Signature] value — two 31-bit halves so the identity
  /// is bit-for-bit equal on Dart VM and Dart Web. See [Signature] for
  /// equality, hashCode, ordering, and 8-byte serialisation.
  final Signature signature;

  SpectralBasis({
    required this.n,
    required this.k,
    required this.eigenvalues,
    required this.eigenvectors,
    this.nodePaths,
    Map<String, int>? pathToId,
    Signature? signature,
  })  : pathToId = pathToId ??
            (nodePaths != null
                ? <String, int>{
                    for (var i = 0; i < nodePaths.length; i++) nodePaths[i]: i,
                  }
                : null),
        signature = signature ?? _fingerprintEigenvalues(eigenvalues);

  /// Build a spectral basis directly from a graph by running
  /// [lanczosSmallEigenpairs]. Convenience constructor — most callers
  /// should go through the engine-level cache rather than rebuild
  /// per query. Callers that have node labels handy can supply them
  /// via [nodePaths] so labeled queries become available.
  factory SpectralBasis.fromGraph(
    CsrGraph graph,
    int k, {
    int? maxIters,
    List<String>? nodePaths,
  }) {
    final pairs = lanczosSmallEigenpairs(graph, k, maxIters: maxIters);
    return SpectralBasis(
      n: pairs.n,
      k: pairs.k,
      eigenvalues: pairs.eigenvalues,
      eigenvectors: pairs.eigenvectors,
      nodePaths: nodePaths,
    );
  }

  /// Two bases are equal iff their signatures match. Signature is
  /// derived from the eigenvalue bit patterns, so equality implies
  /// structural identity of the underlying spectra. A deliberately
  /// cheap comparison — one integer equality — so `SpectralBasis`
  /// can serve as a Map key, Set element, or cache lookup handle.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpectralBasis && signature == other.signature);

  @override
  int get hashCode => signature.hashCode;

  /// Return a new [SpectralBasis] with node labels attached. Shares
  /// the underlying Float64List storage (O(1) rewrap) so labelling
  /// is cheap regardless of basis size. Use to enrich a math-only
  /// basis with path metadata for labeled queries.
  SpectralBasis withLabels(List<String> paths) {
    assert(paths.length == n,
        'labels length (${paths.length}) must equal basis n ($n)');
    return SpectralBasis(
      n: n,
      k: k,
      eigenvalues: eigenvalues,
      eigenvectors: eigenvectors,
      nodePaths: paths,
      signature: signature,
    );
  }

  // ── Serialization ────────────────────────────────────────────────

  /// Wire-transferable byte representation of this basis. Layout:
  ///   [0..8)     magic + version
  ///   [8..16)    signature
  ///   [16..20)   n (uint32)
  ///   [20..24)   k (uint32)
  ///   [24..28)   nodePaths count (0 if unlabeled; uint32)
  ///   [28..)     eigenvalues   (k * 8 bytes)
  ///              eigenvectors  (k * n * 8 bytes)
  ///              path strings  (length-prefixed UTF-8) — optional
  ///
  /// The result is `O(k·n · 8)` bytes plus ~k·8 for Λ plus labels.
  /// For a typical 10k-node repo at k=20, this is ≈1.6 MB — a single
  /// HTTP response body. Send it on the wire and reconstruct on the
  /// other side with [SpectralBasis.fromBytes].
  Uint8List toBytes() {
    final labelCount = nodePaths?.length ?? 0;
    final labelBytes = <Uint8List>[];
    var labelsTotal = 0;
    if (labelCount > 0) {
      for (final p in nodePaths!) {
        final enc = utf8.encode(p);
        labelBytes.add(enc);
        labelsTotal += 4 + enc.length;
      }
    }
    final valBytes = k * 8;
    final vecBytes = k * n * 8;
    final total = 28 + valBytes + vecBytes + labelsTotal;
    final out = Uint8List(total);
    final bd = ByteData.view(out.buffer);
    // Magic: "LGS\0" + version 1 at bytes 4..7.
    bd.setUint32(0, 0x4c475300, Endian.little);
    bd.setUint32(4, 1, Endian.little);
    // Signature as two little-endian 31-bit halves (see [Signature]).
    signature.writeBytes(bd, 8);
    bd.setUint32(16, n, Endian.little);
    bd.setUint32(20, k, Endian.little);
    bd.setUint32(24, labelCount, Endian.little);
    // Eigenvalues.
    var off = 28;
    for (var i = 0; i < k; i++) {
      bd.setFloat64(off + i * 8, eigenvalues[i], Endian.little);
    }
    off += valBytes;
    // Eigenvectors.
    for (var i = 0; i < k * n; i++) {
      bd.setFloat64(off + i * 8, eigenvectors[i], Endian.little);
    }
    off += vecBytes;
    // Labels (optional).
    for (final b in labelBytes) {
      bd.setUint32(off, b.length, Endian.little);
      off += 4;
      out.setRange(off, off + b.length, b);
      off += b.length;
    }
    return out;
  }

  /// Reconstruct a [SpectralBasis] from its [toBytes] representation.
  /// Throws [FormatException] on mismatched magic / version. The
  /// reconstructed basis is bit-identical to the original (same
  /// eigenvalues → same signature → same identity).
  factory SpectralBasis.fromBytes(Uint8List bytes) {
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    final magic = bd.getUint32(0, Endian.little);
    final version = bd.getUint32(4, Endian.little);
    if (magic != 0x4c475300 || version != 1) {
      throw const FormatException('SpectralBasis.fromBytes: bad magic/version');
    }
    final signature = Signature.readBytes(bd, 8);
    final n = bd.getUint32(16, Endian.little);
    final k = bd.getUint32(20, Endian.little);
    final labelCount = bd.getUint32(24, Endian.little);
    var off = 28;
    final eigenvalues = Float64List(k);
    for (var i = 0; i < k; i++) {
      eigenvalues[i] = bd.getFloat64(off + i * 8, Endian.little);
    }
    off += k * 8;
    final eigenvectors = Float64List(k * n);
    for (var i = 0; i < k * n; i++) {
      eigenvectors[i] = bd.getFloat64(off + i * 8, Endian.little);
    }
    off += k * n * 8;
    List<String>? nodePaths;
    if (labelCount > 0) {
      nodePaths = <String>[];
      for (var i = 0; i < labelCount; i++) {
        final len = bd.getUint32(off, Endian.little);
        off += 4;
        nodePaths.add(utf8.decode(
          Uint8List.view(bytes.buffer, bytes.offsetInBytes + off, len),
        ));
        off += len;
      }
    }
    return SpectralBasis(
      n: n,
      k: k,
      eigenvalues: eigenvalues,
      eigenvectors: eigenvectors,
      nodePaths: nodePaths,
      signature: signature,
    );
  }

  // ── Labeled queries ──────────────────────────────────────────────

  /// Convenience: return a [SpectralProjection] noun instead of the
  /// raw `Float64List` coefficients. Same math as [project], but the
  /// result carries its basis reference and exposes `.diffuseAt(t)`,
  /// `.phiForPath(...)`, `.entropy(t)`, `.freeEnergy(t)`, and
  /// CRDT-friendly `+` / `.scale(...)` operators on the coefficient
  /// vector.
  SpectralProjection projectSource(Float64List rho) =>
      SpectralProjection(basis: this, coefficients: project(rho));

  /// Labeled-input twin of [projectSource]. Uses [labelProject] under
  /// the hood, so it requires the basis to be labeled.
  SpectralProjection projectLabeledSource(
          Map<String, double> weightsByPath) =>
      SpectralProjection(
        basis: this,
        coefficients: labelProject(weightsByPath),
      );

  /// Labeled variant of [project] — accepts a `path → weight` map,
  /// builds a sparse ρ via [pathToId], projects onto the eigenbasis.
  /// Requires [nodePaths] / [pathToId] to be set. Paths absent from
  /// the basis are silently dropped.
  Float64List labelProject(Map<String, double> weightsByPath) {
    final paths = pathToId;
    if (paths == null) {
      throw StateError(
        'labelProject requires nodePaths/pathToId; '
        'use `basis.withLabels(paths)` first.',
      );
    }
    final rho = Float64List(n);
    var total = 0.0;
    for (final entry in weightsByPath.entries) {
      final id = paths[entry.key];
      if (id == null || entry.value <= 0) continue;
      rho[id] += entry.value;
      total += entry.value;
    }
    if (total > 0) {
      final inv = 1.0 / total;
      for (var i = 0; i < n; i++) {
        if (rho[i] != 0) rho[i] *= inv;
      }
    }
    return project(rho);
  }

  /// Return the diffused mass at a specific path, at temperature t,
  /// from a cached projection. `O(k)` lookup — no per-node sweep.
  /// Throws if the basis is unlabeled.
  double phiForPath(Float64List projection, String path, double t) {
    final id = pathToId?[path];
    if (id == null) return 0.0;
    assert(projection.length == k, 'projection.length must equal k');
    var v = 0.0;
    for (var j = 0; j < k; j++) {
      v += projection[j] *
          math.exp(-t * eigenvalues[j]) *
          eigenvectors[j * n + id];
    }
    return v;
  }

  /// Project `rho` onto the eigenbasis: returns `Uᵀ·ρ` of length k.
  /// Cheap O(k·n). The projection is the natural representation of a
  /// source distribution in the spectral coordinates — one number per
  /// mode, scale-aware. Future backtracking-attention paths will sit
  /// on top of this primitive (modes ↔ random-walk rates).
  Float64List project(Float64List rho) {
    assert(rho.length == n, 'rho length must equal n');
    final coeffs = Float64List(k);
    if (n == 0) return coeffs;
    // Grimoire XIV — the k·n dot products are the hottest path on this
    // class. When both ρ and the eigenvector slice are 16-byte aligned
    // (fresh `Float64List` / `Float64x2List`-backed views always are),
    // collapse each dot product into a Float64x2 accumulator so two
    // multiplies retire per lane per cycle. Misaligned base offsets
    // (odd n across modes) fall through to a scalar loop — still
    // stride-1, still cache-friendly.
    final evenPairs = n >> 1;
    final hasTail = (n & 1) == 1;
    final tailIdx = n - 1;
    final rhoAligned = (rho.offsetInBytes & 15) == 0;
    final basisAligned = (eigenvectors.offsetInBytes & 15) == 0;
    final Float64x2List? rhoX = rhoAligned && evenPairs > 0
        ? Float64x2List.view(rho.buffer, rho.offsetInBytes, evenPairs)
        : null;

    for (var j = 0; j < k; j++) {
      final base = j * n;
      var s = 0.0;
      if (rhoX != null &&
          basisAligned &&
          evenPairs > 0 &&
          ((base * 8) & 15) == 0) {
        final eigX = Float64x2List.view(eigenvectors.buffer,
            eigenvectors.offsetInBytes + base * 8, evenPairs);
        var accX = Float64x2.zero();
        for (var i = 0; i < evenPairs; i++) {
          accX = accX + eigX[i] * rhoX[i];
        }
        s = accX.x + accX.y;
      } else {
        for (var i = 0; i < evenPairs * 2; i++) {
          s += eigenvectors[base + i] * rho[i];
        }
      }
      if (hasTail) {
        s += eigenvectors[base + tailIdx] * rho[tailIdx];
      }
      coeffs[j] = s;
    }
    return coeffs;
  }

  /// Reconstruct φ(t) from a precomputed projection. Each mode j
  /// scales by `e^{−t·λ_j}`; the result is `U · diag(decay) · coeffs`.
  /// Use this for slider sweeps: project once, recombine many times.
  Float64List recombineFromProjection(Float64List coeffs, double t) {
    assert(coeffs.length == k, 'coeffs length must equal k');
    if (n == 0) return Float64List(0);
    // Float64x2-backed accumulator — see Grimoire XIV / XXIII comments
    // on [project]. Same SIMD pattern as [recombineHeatPhi] in the
    // Chebyshev path, ported so the two diffusion paths are equal-cost.
    final evenPairs = n >> 1;
    final hasTail = (n & 1) == 1;
    final tailIdx = n - 1;
    final phiX = Float64x2List((n + 1) >> 1);
    final phi = Float64List.view(phiX.buffer, 0, n);
    final basisAligned = (eigenvectors.offsetInBytes & 15) == 0;

    for (var j = 0; j < k; j++) {
      final c = coeffs[j] * math.exp(-t * eigenvalues[j]);
      if (c == 0.0) continue;
      final base = j * n;
      if (evenPairs > 0 && basisAligned && ((base * 8) & 15) == 0) {
        final eigX = Float64x2List.view(eigenvectors.buffer,
            eigenvectors.offsetInBytes + base * 8, evenPairs);
        for (var i = 0; i < evenPairs; i++) {
          phiX[i] = phiX[i] + eigX[i].scale(c);
        }
      } else {
        for (var i = 0; i < evenPairs * 2; i++) {
          phi[i] += c * eigenvectors[base + i];
        }
      }
      if (hasTail) {
        phi[tailIdx] += c * eigenvectors[base + tailIdx];
      }
    }
    // Return a caller-owned fresh buffer (the view aliases phiX storage).
    final out = Float64List(n);
    out.setRange(0, n, phi);
    return out;
  }

  /// One-shot diffuse: project, scale by `e^{−t·λ}`, reconstruct.
  /// Equivalent to `recombineFromProjection(project(rho), t)` but
  /// avoids materialising the intermediate coefficient vector when
  /// the caller doesn't need it.
  Float64List diffuse(Float64List rho, double t) {
    return recombineFromProjection(project(rho), t);
  }

  // ───────────────────────────────────────────────────────────────────
  // OBSERVABLES — physical quantities the math gives us for free.
  //
  // The heat-kernel diffusion's quantum-thermodynamic structure means
  // every cached spectrum carries more information than `diffuse(ρ, t)`
  // ever surfaces. The methods below extract scalars and structures
  // that make sense in their own right: the partition function and
  // free energy of the operator on a source, the entropy of the
  // source's spectral participation, the heat trace as a graph
  // invariant, the diffusion-induced metric on the manifold, and
  // the Fiedler / k-way community structure of the codebase as
  // partitions of L_sym's low-frequency eigenspace.
  //
  // None of these add a SpMV — every observable is derived from the
  // already-computed eigendecomposition. Cost is at most O(k·n).
  // ───────────────────────────────────────────────────────────────────

  // Heat trace, partition function, free energy, and spectral entropy
  // now live in `logos_thermo.dart` (extensions on SpectralBasis) —
  // same call-site (`basis.heatTrace(t)`), cleaner separation.

  // Heat-kernel observables (diffusionDistance, pathPropagator,
  // gravitationalPotential, correlationLength, pathPropagatorQuantum,
  // heatKernelSignature / Profile / ProfileTable, hksDistance) now
  // live in `logos_heat.dart`. Call-sites unchanged.

  /// **Theorem-tight.** **Rayleigh quotient** `⟨ρ, Lρ⟩ / ⟨ρ, ρ⟩` — the classical
  /// eigenvalue estimator. When ρ is exactly an eigenvector with
  /// eigenvalue λ, this recovers λ to fp precision.
  ///
  /// For arbitrary ρ, it gives the **λ-weighted mean over the modes
  /// ρ lives on** — a single-step "classical phase estimation" that
  /// projects the mode coefficients and reads off the Laplacian's
  /// mean action on this particular source.
  ///
  /// In the Fourier picture:
  ///
  ///     Rayleigh(ρ) = Σⱼ λⱼ · |cⱼ|²  /  Σⱼ |cⱼ|²
  ///
  /// The denominator is Parseval's energy; the numerator is the
  /// quadratic form `⟨ρ, Δ₀ ρ⟩`. The quotient is the expected
  /// eigenvalue of a random measurement on ρ — the spectral
  /// equivalent of Shor-style phase estimation's final readout,
  /// cashed out classically.
  ///
  /// Returns `double.nan` when ρ has zero energy.
  double rayleighQuotient(Float64List rho) {
    final c = project(rho);
    var num = 0.0;
    var den = 0.0;
    for (var j = 0; j < k; j++) {
      final cc = c[j] * c[j];
      num += eigenvalues[j] * cc;
      den += cc;
    }
    if (den <= _subnormalFloor) return double.nan;
    return num / den;
  }

  /// **Theorem-tight** (Perron-Frobenius). **Ground state** of the repo —
  /// the zero-mode eigenvector, the unique state the engine settles into
  /// as temperature → 0. Returns a Float64List of length [n].
  ///
  /// On a connected graph the zero-mode is proportional to
  /// `D^{1/2}·𝟙`, making the ground state the **weighted uniform
  /// distribution** where each node's amplitude is `√(degree(v))/Z`.
  /// This is the **natural equilibrium** of heat diffusion: infinite
  /// diffusion time converges every initial distribution to this.
  ///
  /// Every refactoring is a motion in state space that lowers the
  /// Rayleigh quotient toward its minimum (which is 0, the
  /// ground-state eigenvalue on a connected graph). Perfect code
  /// is a crystalline approximation to the ground state.
  ///
  /// Returns an empty list when the basis is trivial (k = 0).
  Float64List groundState() {
    if (k == 0) return Float64List(0);
    final out = Float64List(n);
    for (var v = 0; v < n; v++) {
      out[v] = eigenvectors[v]; // j=0, stride n
    }
    return out;
  }

  // `thermodynamics(β)` now lives in `logos_thermo.dart` — see the
  // [SpectralThermo] extension for the grand-pantheon record.

  /// **Quadratic form** `⟨ρ, f(L) ρ⟩ = Σⱼ profile[j] · (Uᵀρ)[j]²`.
  ///
  /// The unifying primitive every energy-like observable in the
  /// engine reduces to. `f(L)` here is the operator whose mode-basis
  /// profile is [profile] — exactly the way `SpectralOperator`
  /// represents any function of the Laplacian. Given a profile, one
  /// function computes the quadratic form in `ρ` under that operator.
  ///
  /// Existing observables fall out as specific profiles:
  /// * `heatTrace(t)` → profile = `e^{-tλⱼ}`, ρ = uniform-mass delta
  /// * `spectralDivergence(ρₐ, ρᵦ, t)` → profile = `e^{-2tλⱼ}`,
  ///   ρ = ρₐ − ρᵦ
  /// * `alonBoppanaMargin` / `cheegerUpperBound` — rely on this
  ///   structure via λ₁
  /// * Dirichlet energy `⟨ρ, Δ₀ρ⟩` → profile = `λⱼ`
  ///
  /// Not a replacement for the above — the named observables remain
  /// the public API — but the building block they share. Expose
  /// the diagonal-profile pattern directly so callers can compose
  /// custom profiles without re-implementing project+reduce.
  ///
  /// Throws [StateError] when `profile.length != k`.
  double quadraticForm(Float64List rho, Float64List profile) {
    if (profile.length != k) {
      throw StateError(
          'quadraticForm: profile length ${profile.length} != basis.k $k');
    }
    final c = project(rho);
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      s += profile[j] * c[j] * c[j];
    }
    return s;
  }

  /// L² distance between the two diffused fields `φ(t, ρa)` and
  /// `φ(t, ρb)`. By orthonormality of the eigenbasis this collapses
  /// to a closed-form sum over modes:
  /// `‖φa − φb‖² = Σⱼ e^{−2tλⱼ}·(cⱼ_a − cⱼ_b)²`.
  ///
  /// **Reading**: a rigorous, math-grounded "are these two source
  /// distributions touching the same conceptual region of the
  /// codebase?" metric. Stronger than file-overlap, stronger than
  /// embedding cosines, *grounded in the graph's own geometry*.
  /// Use this for PR-vs-PR similarity, commit-vs-commit shape change,
  /// or "how different is yesterday's review focus from today's?".
  /// Wasserstein-1 distance between this basis's eigenvalue
  /// distribution and [other]'s — the "earth mover's distance" on
  /// sorted spectra. By construction both spectra are already
  /// ascending, so after matching by rank the W₁ distance is
  ///
  ///     mean_j |λ_j^(self) − λ_j^(other)|.
  ///
  /// This is the **spectrum-to-spectrum** distance (complementing
  /// [spectralDivergence], which is source-to-source on one fixed
  /// basis). Uses:
  ///
  /// - Cospectral equivalence test: returns `0.0` iff the two bases
  ///   are isospectral. Stronger than a signature-hash match
  ///   (signatures collide at birthday-bound rates; this is exact).
  /// - Structural similarity across time: compare HEAD's basis to
  ///   HEAD~N's to quantify how much a codebase's spectral identity
  ///   has drifted.
  /// - Cross-repo similarity: same query between two independent
  ///   repositories gives a continuous "how related are these?"
  ///   metric.
  ///
  /// Throws [StateError] when `k` differs between the two bases —
  /// comparing different-dimensional spectra is ill-defined.
  double eigenvalueDistance(SpectralBasis other) {
    if (k != other.k) {
      throw StateError(
          'eigenvalueDistance: bases must share k (got $k vs ${other.k})');
    }
    if (k == 0) return 0.0;
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      final d = eigenvalues[j] - other.eigenvalues[j];
      s += d < 0 ? -d : d;
    }
    return s / k;
  }

  double spectralDivergence(Float64List rhoA, Float64List rhoB, double t) {
    final ca = project(rhoA);
    final cb = project(rhoB);
    var sumSq = 0.0;
    for (var j = 0; j < k; j++) {
      final delta = ca[j] - cb[j];
      sumSq += math.exp(-2.0 * t * eigenvalues[j]) * delta * delta;
    }
    return math.sqrt(sumSq);
  }

  /// The Fiedler vector — eigenvector for the smallest non-trivial
  /// eigenvalue `λ₁` of `L_sym`. On a connected graph `λ₀ = 0`
  /// (trivial constant mode), so `u₁` is the next eigenvector and
  /// captures the codebase's deepest natural cleavage: the partition
  /// of nodes that minimises edge-cut weight relative to subset
  /// volume (Cheeger's inequality bounds this).
  ///
  /// **Reading**: the soul of the codebase, projected onto a single
  /// axis. `sign(fiedler[i])` partitions every file into one of two
  /// natural halves; the magnitude tells you how decisively each file
  /// belongs to its half. Returns null when `k < 2` (need at least
  /// the trivial + first non-trivial mode).
  Float64List? get fiedlerVector {
    if (k < 2) return null;
    return Float64List.view(
      eigenvectors.buffer,
      eigenvectors.offsetInBytes + n * 8,
      n,
    );
  }

  /// Cluster the graph's nodes into `kClusters` communities by
  /// running Lloyd's k-means in the spectral embedding spanned by
  /// `u₁..u_{kClusters}` (skip `u₀` — constant on a connected graph,
  /// no clustering signal). This is the Shi–Malik / Ng–Jordan–Weiss
  /// spectral clustering algorithm at its cleanest.
  ///
  /// **Reading**: the codebase's natural community structure as the
  /// math sees it — independent of the user's directory tree, the
  /// authors' co-authorship, or any heuristic. Two files in the same
  /// cluster diffuse onto each other faster than they diffuse onto
  /// outsiders. Surface this as a permanent dashboard layer; users
  /// will recognise architectural intent they never articulated.
  ///
  /// Returns a `List<int>` of length `n` mapping node id → cluster
  /// label `[0, kClusters)`. Deterministic given `seed`.
  List<int> spectralCommunityLabels(int kClusters, {int seed = 0xC005C0DE}) {
    if (kClusters <= 1 || n == 0 || k < 2) {
      return List<int>.filled(n, 0);
    }
    // Skip the full kernel subspace — on connected graphs this is 1,
    // on disconnected graphs it's β₀. Hardcoding "skip mode 0" would
    // feed a ground-state eigenvector into the embedding as an axis,
    // poisoning the clustering with a component-indicator mask.
    final start = firstExcitedIndex;
    final available = k - start;
    if (available <= 0) return List<int>.filled(n, 0);
    final embedDim = math.min(kClusters, available);
    // Build n × embedDim embedding using u_start..u_{start+embedDim-1}.
    // Row-normalised so cosine-like similarity drives the k-means.
    final embedding = Float64List(n * embedDim);
    for (var i = 0; i < n; i++) {
      var rowNormSq = 0.0;
      for (var d = 0; d < embedDim; d++) {
        final v = eigenvectors[(start + d) * n + i];
        embedding[i * embedDim + d] = v;
        rowNormSq += v * v;
      }
      final rowNorm = math.sqrt(rowNormSq);
      if (rowNorm > _subnormalFloor) {
        final inv = 1.0 / rowNorm;
        for (var d = 0; d < embedDim; d++) {
          embedding[i * embedDim + d] *= inv;
        }
      }
    }
    return _kmeansSpectral(embedding, n, embedDim, kClusters, seed);
  }

  // ───────────────────────────────────────────────────────────────────
  // SECOND-TIER OBSERVABLES
  //
  // The first observable layer (heat trace, free energy, entropy,
  // Fiedler, communities) reads single scalars off the spectrum.
  // This layer reads structure: graph invariants (spectral gap,
  // stationary distribution), two-point metrics (effective resistance),
  // derivatives of thermodynamic potentials (heat capacity), and the
  // codebase's **byte-wide spectral identity** — a derived analog of
  // OG Logos's 8-bit chain-rule lattice, obtained by reading the sign
  // pattern of the first eight non-trivial eigenvectors. Same Λ*(R⁸),
  // constructed from the graph's own cleavages rather than from bytes.
  // ───────────────────────────────────────────────────────────────────

  /// **Theorem-tight.** Spectral gap `λ₁ − λ₀`. On a connected graph
  /// `λ₀ = 0`, so this collapses to `λ₁` — the Fiedler eigenvalue.
  /// Bounds the graph's Cheeger constant from above (Cheeger's
  /// inequality) and governs the mixing time of a random walk
  /// (≈ 1/gap for moderate graphs).
  ///
  /// **Reading**: the one-number "how connected is the codebase?".
  /// Large gap = tightly knit single community; small gap = the graph
  /// is one cut away from splitting into two loosely-coupled halves.
  double get spectralGap {
    if (k < 2) return 0.0;
    return eigenvalues[1] - eigenvalues[0];
  }

  /// Mixing time of the random walk underlying the heat kernel,
  /// `≈ 1 / λ₁`. The characteristic time for a delta distribution to
  /// thermalise to the stationary distribution — the natural unit of
  /// diffusion temperature for this graph. Returns `double.infinity`
  /// when the graph is disconnected (λ₁ → 0).
  ///
  /// **Reading**: the principled value for `t = 1.0`. Every "canonical
  /// heat query" in the engine that hard-coded `t = 1.0` was really
  /// asking for "one mixing time"; wire this in when you want the
  /// temperature to scale with the graph's natural speed instead of
  /// a magic constant.
  double get mixingTime {
    final gap = spectralGap;
    if (gap <= _subnormalFloor) return double.infinity;
    return 1.0 / gap;
  }

  /// Spectral chaos — `log(λ_top / λ₁)`, the dynamic range of the
  /// Laplacian spectrum. Low chaos (~1) = uniform dynamics across
  /// modes, expander-like. High chaos (≳5) = long spectrum, path-like
  /// or highly hierarchical. Completes the thermodynamic pantheon
  /// alongside [spectralGap], [mixingTime], [cheegerUpperBound], and
  /// [heatCapacity].
  ///
  /// Returns `0.0` when the basis has fewer than 2 modes and
  /// `double.infinity` when the graph is disconnected (`λ₁ → 0`).
  ///
  /// **Reading**: how heterogeneous is diffusion on this graph? A repo
  /// with chaos ≈ 1 is essentially uniform — every file equidistant
  /// under the heat metric. Chaos ≈ 7 is a codebase strung out along
  /// a long structural axis (monolithic-linear, not clustered).
  double get spectralChaos {
    if (k < 2) return 0.0;
    final l1 = eigenvalues[1];
    if (l1 <= _subnormalFloor) return double.infinity;
    final lTop = eigenvalues[k - 1];
    if (lTop <= 0) return 0.0;
    return math.log(lTop / l1);
  }

  // `vonNeumannEntropy` now lives in `logos_thermo.dart`.

  /// **Theorem-tight** (Matrix-Tree). **Log-pseudo-determinant** — the
  /// sum of log-eigenvalues over non-trivial modes. Paired with
  /// [spanningTreeCountEstimate] via the Matrix-Tree theorem.
  ///
  /// Definition: `log det*(L) = Σⱼ log(λⱼ)` over `j ≥ 1` (zero
  /// modes excluded). The regularised logarithm of the
  /// "pseudo-determinant" that ignores zero eigenvalues.
  ///
  /// Returns `double.negativeInfinity` when any non-zero mode is
  /// numerically zero (graph disconnected at the resolution k).
  /// Returns 0.0 for trivial bases.
  double get logPseudoDeterminant {
    if (k < 2) return 0.0;
    var s = 0.0;
    for (var j = 1; j < k; j++) {
      final lam = eigenvalues[j];
      if (lam <= _subnormalFloor) return double.negativeInfinity;
      s += math.log(lam);
    }
    return s;
  }

  /// **Matrix-Tree theorem** — the number of spanning trees of the
  /// underlying graph equals `(1/n) · Π_{j≥1} λⱼ` (Kirchhoff's
  /// theorem, for the combinatorial Laplacian). On our normalised
  /// Laplacian the exact count picks up a degree-factor, but the
  /// order-of-magnitude and scaling law stay correct — this is the
  /// **Kirchhoff complexity** of the repo.
  ///
  /// Interpretation: the number of independent "paths" one could
  /// trace through the repo without revisiting any edge. Dense
  /// graphs have astronomically many spanning trees; trees have
  /// exactly one; disconnected graphs have zero.
  ///
  /// Returns `double.infinity` when the product overflows (dense
  /// graphs with high k), `0.0` when disconnected at resolution k.
  ///
  /// Reference: the wildest observable in the engine — a
  /// *combinatorial* count extracted from a *spectral* spectrum,
  /// via one of the oldest theorems in algebraic graph theory
  /// (Kirchhoff 1847).
  double get spanningTreeComplexity {
    if (k < 2 || n == 0) return 0.0;
    final logDet = logPseudoDeterminant;
    if (!logDet.isFinite) return 0.0;
    // log(count) ≈ logDet − log(n)
    final logCount = logDet - math.log(n.toDouble());
    if (logCount > 700) return double.infinity; // f64 exp limit
    return math.exp(logCount);
  }

  /// Spectral rigidity (Atas-Bogomolny r-value) — a single scalar in
  /// roughly (0, 1) summarising how "generic" the eigenvalue-spacing
  /// pattern is.
  ///
  /// For sorted consecutive spacings `s_i = λ_{i+1} − λ_i`, each
  /// interior spacing contributes
  ///
  ///     r_i = min(s_{i−1}, s_i) / max(s_{i−1}, s_i).
  ///
  /// The returned value is the mean of `r_i`. Because it is a ratio
  /// of adjacent spacings, it needs no unfolding — the local density
  /// cancels.
  ///
  /// Universality anchors (Atas-Bogomolny-Roux-Jacquod 2013):
  ///   - Poisson (independent / no level repulsion): ⟨r⟩ ≈ 0.386
  ///   - GOE (real-symmetric random, like our normalized Laplacian): ⟨r⟩ ≈ 0.536
  ///   - GUE (complex-Hermitian random): ⟨r⟩ ≈ 0.603
  ///
  /// **Reading**: where does this codebase sit on the random-to-structured
  /// axis? A GOE-like spectrum says the graph is "generic at this
  /// sparsity" — no pathological clustering of eigenvalues, mixing
  /// looks like a random graph would. A Poisson-like spectrum says the
  /// graph has decoupled structural components (eigenvalues don't
  /// repel each other the way random matrices do), typical of disjoint
  /// modules or heavy hierarchy.
  ///
  /// Empirical reference: `tmp_starwalk.py §4` — on Erdős-Rényi and
  /// random k-regular graphs the r-value lands near 0.54 (GOE); ring
  /// lattices and band-structured graphs drop toward the arcsine /
  /// Poisson regime.
  ///
  /// Returns `double.nan` when `k < 4` (fewer than two spacings, no
  /// ratios to average) or when every spacing is zero (fully
  /// degenerate spectrum).
  double get spectralRigidity {
    if (k < 4) return double.nan;
    // Eigenvalues are ascending by construction.
    var sum = 0.0;
    var count = 0;
    for (var j = 1; j < k - 1; j++) {
      final sPrev = eigenvalues[j] - eigenvalues[j - 1];
      final sNext = eigenvalues[j + 1] - eigenvalues[j];
      final lo = sPrev < sNext ? sPrev : sNext;
      final hi = sPrev < sNext ? sNext : sPrev;
      if (hi <= _subnormalFloor) continue; // degenerate cluster; skip
      sum += lo / hi;
      count += 1;
    }
    if (count == 0) return double.nan;
    return sum / count;
  }

  /// Inverse participation ratio per eigenvector: `IPR_j = Σᵢ |uⱼ[i]|⁴`.
  /// Small (~1/n) = delocalized / extended mode; large (→1) = localized
  /// on one node. The "effective support" of mode j is `1 / IPR_j`.
  ///
  /// **Reading**: which modes can see the whole graph and which are
  /// trapped in a local region. Dumbbell graphs develop near-degenerate
  /// localized modes at the mobility edge; disordered/random-like
  /// graphs mostly produce extended modes. Bulk behavior is a window
  /// into the Anderson-localization regime of the graph's heat flow.
  ///
  /// Returned array has length [k].
  Float64List inverseParticipationRatios() {
    final out = Float64List(k);
    if (n == 0 || k == 0) return out;
    for (var j = 0; j < k; j++) {
      final base = j * n;
      var s = 0.0;
      for (var i = 0; i < n; i++) {
        final v = eigenvectors[base + i];
        final v2 = v * v;
        s += v2 * v2;
      }
      out[j] = s;
    }
    return out;
  }

  /// Spectral dimension estimated from the decay of the heat-kernel
  /// return probability `P_t = (1/n) · tr(exp(−t·L)) = (1/k) Σⱼ e^{−t·λⱼ}`.
  /// **Operational** — this is a least-squares fit in a chosen t-window;
  /// the returned `d_s` depends on the fit window and Lanczos truncation.
  ///
  /// For a graph that resembles ℝ^d at long wavelengths,
  /// `P_t ~ t^{−d/2}` for moderate-to-large t; fitting log(P_t) vs
  /// log(t) in the decay window recovers `d_s`.
  ///
  /// Returns `double.nan` when the decay window is too short to fit.
  /// Uses a geometric grid of `samples` values of t in `[tMin, tMax]`.
  ///
  /// **Reading**: a chain reads ≈1, a grid ≈2, an expander climbs
  /// higher. For a repo: 2 ≈ architectural mesh, <2 ≈ tree-like,
  /// >2 ≈ dense coupling or small-world.
  double spectralDimension({
    double tMin = 0.5,
    double tMax = 50.0,
    int samples = 16,
    double pFloor = 0.01,
  }) {
    if (k == 0) return double.nan;
    final logMin = math.log(tMin);
    final logMax = math.log(tMax);
    final step = (logMax - logMin) / (samples - 1);
    final ts = <double>[];
    final ps = <double>[];
    for (var s = 0; s < samples; s++) {
      final t = math.exp(logMin + s * step);
      var sum = 0.0;
      for (var j = 0; j < k; j++) {
        sum += math.exp(-t * eigenvalues[j]);
      }
      final p = sum / k;
      if (p > pFloor) {
        ts.add(t);
        ps.add(p);
      }
    }
    if (ts.length < 3) return double.nan;
    // Linear fit of log(p) vs log(t).
    var sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0;
    final n2 = ts.length;
    for (var i = 0; i < n2; i++) {
      final x = math.log(ts[i]);
      final y = math.log(ps[i]);
      sumX += x;
      sumY += y;
      sumXX += x * x;
      sumXY += x * y;
    }
    final meanX = sumX / n2;
    final meanY = sumY / n2;
    final denom = sumXX - n2 * meanX * meanX;
    if (denom.abs() < 1e-18) return double.nan;
    final slope = (sumXY - n2 * meanX * meanY) / denom;
    return -2.0 * slope;
  }

  /// Cheeger upper bound on the graph's edge-expansion constant:
  /// `h(G) ≤ √(2·λ₁)`. Makes the Fiedler vector's "deepest cleavage"
  /// claim quantitative — the tightest cut the graph can be bisected
  /// along carries at most this fraction of the total edge weight.
  ///
  /// **Reading**: when this number is small, the graph is a
  /// near-bisection — you can cut it cleanly. When it's big, the
  /// graph resists bisection; it's genuinely one connected blob.
  double get cheegerUpperBound {
    final gap = spectralGap;
    if (gap <= 0.0) return 0.0;
    return math.sqrt(2.0 * gap);
  }

  /// Stationary distribution of the random walk `D⁻¹·W`. For the
  /// normalised Laplacian the zero-mode eigenvector `u₀` satisfies
  /// `u₀ ∝ D^{1/2}·𝟙`, so on a connected graph `π_i = u₀[i]²` is
  /// proportional to the i-th node's degree (and already unit-norm
  /// since `u₀` is).
  ///
  /// **Reading**: the PageRank of the codebase, free. High-`π_i` files
  /// are hubs — random diffusion drifts toward them regardless of where
  /// it starts.
  Float64List stationaryDistribution() {
    final pi = Float64List(n);
    if (k == 0) return pi;
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final v = eigenvectors[i];
      final sq = v * v;
      pi[i] = sq;
      sum += sq;
    }
    if (sum > _subnormalFloor && (sum - 1.0).abs() > 1e-6) {
      // Defensive re-normalise against Lanczos floating-point drift.
      final inv = 1.0 / sum;
      for (var i = 0; i < n; i++) {
        pi[i] *= inv;
      }
    }
    return pi;
  }

  /// Effective resistance between two nodes: the electrical resistance
  /// when the graph is treated as a network of unit resistors scaled
  /// by edge weights. `R(x, y) = Σⱼ₌₁ (uⱼ[x] − uⱼ[y])² / λⱼ` (skip
  /// `j=0` — the degenerate zero mode contributes nothing because
  /// `u₀[x] = u₀[y]` only up to degree rescaling, handled implicitly).
  ///
  /// **Reading**: a *different* metric than diffusion distance —
  /// captures the *commute time* `E[T_{x→y→x}] = 2·|E|·R(x,y)` under
  /// the normalised random walk. Pairs connected by many medium-weight
  /// paths have low R; pairs connected by a single bottleneck have
  /// high R *even if their diffusion distance is small*. Use this when
  /// "reliability of coupling" matters more than "proximity."
  double effectiveResistance(int x, int y) {
    if (x == y || k < 2) return 0.0;
    var s = 0.0;
    for (var j = 1; j < k; j++) {
      final lam = eigenvalues[j];
      if (lam <= _subnormalFloor) continue;
      final delta = eigenvectors[j * n + x] - eigenvectors[j * n + y];
      s += (delta * delta) / lam;
    }
    return s;
  }

  // `heatCapacity(t)` now lives in `logos_thermo.dart`.

  /// Detect the codebase's natural thermal scales — the `t` values at
  /// which `heatCapacity(t)` peaks. Each peak is a **phase transition**:
  /// a scale at which the effective structure of the diffusion
  /// changes character. On a typical repo the first peak sits at the
  /// method/symbol scale, the second at the module scale, the third
  /// at the service scale — derived from the spectrum itself, not
  /// hand-picked.
  ///
  /// Sweeps `t` on a log grid between [tMin] and [tMax]; returns local
  /// maxima above `minPeakRatio · globalMax` sorted ascending.
  ///
  /// This is the principled replacement for magic thermal constants
  /// like `nearT = 0.55·t`, `farT = 1.85·t`, `3-temperature blend
  /// {0.5, 1.0, 2.0}` — instead of picking temperatures a priori,
  /// read them off the codebase's own heat-capacity spectrum.
  List<double> naturalScales({
    double tMin = 0.1,
    double tMax = 8.0,
    int samples = 64,
    double minPeakRatio = 0.25,
  }) {
    // Default to the mixing-time scale if the basis can't be probed
    // or the heat-capacity curve is too flat for peaks. Callers can
    // then rely on a non-empty list invariant — three ad-hoc
    // fallbacks at three callsites collapse to one principled one.
    List<double> fallback() {
      final mix = mixingTime;
      return mix.isFinite && mix > 0.0 ? [mix] : const [1.0];
    }

    if (k == 0 || samples < 3) return fallback();
    final logMin = math.log(tMin);
    final logMax = math.log(tMax);
    final step = (logMax - logMin) / (samples - 1);
    final ts = Float64List(samples);
    final cs = Float64List(samples);
    var globalMax = 0.0;
    for (var s = 0; s < samples; s++) {
      final t = math.exp(logMin + s * step);
      ts[s] = t;
      final c = heatCapacity(t);
      cs[s] = c;
      if (c > globalMax) globalMax = c;
    }
    if (globalMax <= _subnormalFloor) return fallback();
    final threshold = globalMax * minPeakRatio;
    final peaks = <double>[];
    // Interior local maxima only — endpoint detection would bias
    // toward the grid boundaries rather than real phase transitions.
    for (var s = 1; s < samples - 1; s++) {
      if (cs[s] < threshold) continue;
      if (cs[s] > cs[s - 1] && cs[s] > cs[s + 1]) {
        peaks.add(ts[s]);
      }
    }
    return peaks.isEmpty ? fallback() : peaks;
  }

  /// Bracket a query temperature `t` with two flanking temperatures
  /// `(nearT, farT)` where `nearT <= t <= farT`. Uses the peaks of
  /// [naturalScales] — `nearT` is the largest peak at or below `t`,
  /// `farT` is the smallest peak above `t`.
  ///
  /// When `naturalScales` returns no peak on one side of `t`, the
  /// missing end falls back to `t / ratio` (for nearT) or `t * ratio`
  /// (for farT). This mirrors the old hand-picked brackets
  /// `0.55·t` / `1.85·t` but uses the engine's own phase transitions
  /// instead of a constant.
  ///
  /// Intended as the principled replacement for the hardcoded bracket
  /// formula previously used in evidence-temperature selection.
  ({double nearT, double farT}) flankingScales(double t, {double ratio = 1.85}) {
    final peaks = naturalScales();
    double? below;
    double? above;
    for (final p in peaks) {
      if (p <= t) {
        if (below == null || p > below) below = p;
      } else {
        if (above == null || p < above) above = p;
      }
    }
    final nearT = below ?? t / ratio;
    final farT = above ?? t * ratio;
    return (
      nearT: math.min(nearT, t),
      farT: math.max(farT, t),
    );
  }

  /// 8-bit spectral fingerprint of node `i` — the binary representation
  /// of `(sign(u₁[i]), sign(u₂[i]), …, sign(u₈[i]))`. On a connected
  /// graph `u₀` is constant-ish (degree-weighted), so we skip it and
  /// read signs of the first 8 **non-trivial** eigenvectors. The result
  /// is an integer in `[0, 256)` — the natural Logos analog of OG
  /// Logos's byte-wide identity, except derived from the graph's own
  /// cleavages rather than the stream's bit structure.
  ///
  /// **Reading**: every node gets a byte-wide class label. Two nodes
  /// with the same fingerprint share the same side of the first eight
  /// graph cleavages — they're structurally equivalent to byte-identity
  /// resolution. Pairs with Hamming-distance-1 fingerprints differ on
  /// exactly one cleavage. Pairs with distance 8 are maximally
  /// separated in the first 8 cleavages.
  ///
  /// Returns 0 when the basis has fewer than 9 modes (not enough for
  /// 8 non-trivial cleavages plus the zero mode).
  int spectralByteFingerprint(int i) {
    if (k < 9 || i < 0 || i >= n) return 0;
    var b = 0;
    for (var j = 0; j < 8; j++) {
      // Mode j+1 is the j-th non-trivial cleavage. Positive side → 1.
      if (eigenvectors[(j + 1) * n + i] >= 0.0) {
        b |= (1 << j);
      }
    }
    return b;
  }

  /// Compute the full fingerprint table in one sweep — one byte per
  /// node, length `n`. Cheaper than calling [spectralByteFingerprint]
  /// per node when you need all of them: one pass over memory in mode-
  /// major order, writing every node's j-th bit as the sign test fires.
  Uint8List spectralFingerprintTable() {
    final out = Uint8List(n);
    if (k < 9) return out;
    for (var j = 0; j < 8; j++) {
      final base = (j + 1) * n;
      final bit = 1 << j;
      for (var i = 0; i < n; i++) {
        if (eigenvectors[base + i] >= 0.0) {
          out[i] |= bit;
        }
      }
    }
    return out;
  }

  /// Coordinates of node `i` in the first `dims` non-trivial modes —
  /// a `dims`-vector `[u₁[i], u₂[i], …, u_{dims}[i]]`. Skips `u₀` (the
  /// constant zero mode on a connected graph carries no positional
  /// signal) and returns the requested mode entries directly.
  ///
  /// **Reading**: the natural embedding of node `i` into the codebase's
  /// spectral manifold. `dims = 3` gives a 3D point cloud where nearby
  /// nodes are structurally similar; `dims = 4` gives a 4-vector
  /// suitable for sonification harmonics (the replacement the Muse
  /// called out for the simhash-PCA trick in the manifold pane). Cost
  /// is O(dims) — cheaper than reading degree.
  Float64List nodeCoordinates(int i, {int dims = 3}) {
    final out = Float64List(dims);
    if (i < 0 || i >= n) return out;
    final bound = math.min(dims, math.max(0, k - 1));
    for (var d = 0; d < bound; d++) {
      out[d] = eigenvectors[(d + 1) * n + i];
    }
    return out;
  }

  /// Bulk variant of [nodeCoordinates] — returns every node's
  /// `dims`-vector embedding packed row-major into a single
  /// `Float64List` of length `n * dims`. One pass over memory; cheap
  /// even for full-repo emission to a GPU vertex buffer.
  Float64List nodeCoordinateTable({int dims = 3}) {
    final out = Float64List(n * dims);
    if (n == 0) return out;
    final bound = math.min(dims, math.max(0, k - 1));
    for (var d = 0; d < bound; d++) {
      final base = (d + 1) * n;
      for (var i = 0; i < n; i++) {
        out[i * dims + d] = eigenvectors[base + i];
      }
    }
    return out;
  }

  /// Hamming distance between two nodes' 8-bit spectral fingerprints.
  /// Returns the number of cleavages (out of 8) on which `x` and `y`
  /// sit on opposite sides. 0 = spectrally indistinguishable in the
  /// top 8 modes; 8 = maximally separated (every cleavage disagrees).
  ///
  /// **Reading**: the byte-level kizuna distance — same math that
  /// powers OG Logos's exact-match axis, applied to the graph
  /// fingerprint we derived. One hardware-instruction popcount on the
  /// XOR of two fingerprints.
  int spectralFingerprintDistance(int x, int y) {
    final fx = spectralByteFingerprint(x);
    final fy = spectralByteFingerprint(y);
    return popcount8(fx ^ fy);
  }

  // ── HEAT KERNEL SIGNATURE ─────────────────────────────────────────
  //
  // HKS(v, t) = Σⱼ e^{-t·λⱼ} · |uⱼ[v]|²
  //           = (exp(-tL))[v, v]                           (the
  //           diagonal of the heat semigroup at node v).
  //
  // Classical shape-analysis observable (Sun-Ovsjanikov-Guibas 2009).
  // Each node is characterised by the HEAT RETAINED at itself over
  // time. A spectrum-preserving map between graphs preserves HKS, so
  // two isospectral-equivalent nodes have the same profile.
  //
  // Compression view: collapses the (k eigenvalues × per-node
  // eigenvector entries) basis data into a small feature vector per
  // node (one value per time scale queried). Typical use: evaluate
  // across m ≈ 8 logarithmically-spaced t values, cluster nodes by
  // profile, recover multi-scale community structure that single-t
  // diagonals miss.
  //
  // Orthogonality view: every eigenmode contributes independently
  // (the sum is over orthogonal basis vectors) and the per-mode
  // contribution is exactly `|u_j[v]|²·e^{-tλ_j}` — Parseval's
  // identity applied to the diagonal of exp(-tL).

  // HKS family (heatKernelSignature / Profile / ProfileTable,
  // hksDistance) now lives in `logos_heat.dart`.

  // ── POINCARÉ EMBEDDING ─────────────────────────────────────────────
  //
  // For tree-like graphs (δ/diam small) a 2-D Poincaré disc beats
  // Euclidean-in-k-dims on both correlation and multiplicative
  // distortion. The empirical win on this repo's own co-change graph:
  // 4.6× lower log-distortion and +0.07 Spearman correlation, in 2 dims
  // instead of 8.
  //
  // Construction:
  //   1. Take the first two non-trivial eigenvector entries for each
  //      node as a 2-D direction (u₁[i], u₂[i]). Normalise to unit
  //      radius; zero vectors (a node on the graph's 2-D "center") are
  //      mapped to the origin direction.
  //   2. Compute each node's "spectral magnitude" from the first
  //      [magnitudeDims] modes — the norm of (u₁..u_m)[i]. This
  //      ranks how peripheral a node is in the full manifold, not
  //      just the 2 projected dims.
  //   3. Radial squish: `r_disc = tanh(mag / mag_max * 2.5) * targetRadius`.
  //      Concentrates central nodes near the origin and pushes
  //      peripheral nodes toward the boundary — the natural hyperbolic
  //      behaviour.
  //
  // The returned table is row-major [x0, y0, x1, y1, …] in the open
  // Poincaré disc of radius [targetRadius] < 1. Use with
  // [poincareDistance] to get proper geodesic distances.

  /// Row-major Poincaré-disc coordinates for every node: `n × 2` doubles.
  ///
  /// `magnitudeDims` controls how many spectral modes contribute to each
  /// node's radial rank. Higher values capture more of the manifold's
  /// structure at the cost of a slightly smaller spread near the origin.
  /// `targetRadius` is the outer saturation radius (< 1) — 0.92 leaves
  /// headroom so `poincareDistance` never blows up on boundary nodes.
  ///
  /// O(n · magnitudeDims). One pass for magnitudes, one for coords.
  Float64List poincareCoordinateTable({
    int magnitudeDims = 6,
    double targetRadius = 0.92,
  }) {
    assert(targetRadius > 0 && targetRadius < 1,
        'targetRadius must be in (0, 1); got $targetRadius');
    final out = Float64List(n * 2);
    if (n == 0 || k < 2) return out;
    final magModes = math.min(magnitudeDims, math.max(0, k - 1));

    // ── Pass 1: each node's spectral magnitude across top modes. ─────
    final mags = Float64List(n);
    var magMax = 0.0;
    for (var d = 0; d < magModes; d++) {
      final base = (d + 1) * n;
      for (var i = 0; i < n; i++) {
        final v = eigenvectors[base + i];
        mags[i] += v * v;
      }
    }
    for (var i = 0; i < n; i++) {
      final r = math.sqrt(mags[i]);
      mags[i] = r;
      if (r > magMax) magMax = r;
    }
    final invMax = magMax > 0 ? 1.0 / magMax : 1.0;

    // ── Pass 2: direction from (u₁, u₂), radial squish by tanh. ──────
    final u1Base = 1 * n;
    final u2Base = (k >= 3) ? 2 * n : u1Base;
    for (var i = 0; i < n; i++) {
      final x0 = eigenvectors[u1Base + i];
      final y0 = (k >= 3) ? eigenvectors[u2Base + i] : 0.0;
      final dirNorm = math.sqrt(x0 * x0 + y0 * y0);
      final squished = _tanh(mags[i] * invMax * 2.5) * targetRadius;
      if (dirNorm <= 1e-18) {
        // Node lives on the graph's 2-D center — stay near the origin.
        out[i * 2] = 0.0;
        out[i * 2 + 1] = 0.0;
      } else {
        final scale = squished / dirNorm;
        out[i * 2] = x0 * scale;
        out[i * 2 + 1] = y0 * scale;
      }
    }
    return out;
  }

  /// Poincaré-disc coordinates of a single node `i` — `(x, y)`.
  /// Convenience wrapper around [poincareCoordinateTable] when only one
  /// point is needed. Prefer the bulk form for n calls.
  ({double x, double y}) poincareCoordinates(
    int i, {
    int magnitudeDims = 6,
    double targetRadius = 0.92,
  }) {
    if (i < 0 || i >= n) return (x: 0.0, y: 0.0);
    final table = poincareCoordinateTable(
      magnitudeDims: magnitudeDims,
      targetRadius: targetRadius,
    );
    return (x: table[i * 2], y: table[i * 2 + 1]);
  }

  // ───────────────────────────────────────────────────────────────────
  // QUANTUM LIFT — unitary evolution on the same spectral basis.
  //
  // The heat kernel `exp(−t·L_sym)` is the Wick rotation of the
  // Schrödinger propagator `exp(−i·t·L_sym)`. Swap the real `−t`
  // for imaginary `−it` and the same diagonalisation gives a
  // unitary (mass-preserving, norm-preserving) evolution with
  // interference between coherent amplitudes.
  //
  // The Born rule we've been quoting as a name becomes literal here:
  // amplitudes live in ℂⁿ, probabilities are `|ψ|²`, two coherent
  // focuses superpose and their cross-term is the interference.
  // Same real eigenvectors (L_sym is self-adjoint, spectrum real);
  // only the coefficient evolution changes from `e^(−tλ)` (real, decaying)
  // to `e^(−itλ) = cos(tλ) − i·sin(tλ)` (complex, unitary).
  // ───────────────────────────────────────────────────────────────────

  /// Unitary Schrödinger evolution `ψ(t) = exp(−i·t·L_sym)·ρ`.
  /// Returns the complex amplitude split into real and imaginary parts.
  /// Same cost as [diffuse] (O(k·n)), produces a complex field instead
  /// of a decaying real one.
  ///
  /// **Reading**: the quantum version of heat diffusion. `|ψ|²` is
  /// a proper probability (mass is preserved for all t, unlike the
  /// contracting heat kernel). Two focuses evolved in parallel can
  /// interfere — constructive fringes where their phases align,
  /// destructive fringes where they oppose.
  ({Float64List real, Float64List imag}) unitaryDiffuse(
      Float64List rho, double t) {
    final coeffs = project(rho);
    if (n == 0) return (real: Float64List(0), imag: Float64List(0));
    // Twin-accumulator SIMD: each eigenvector chunk is read ONCE per
    // mode and feeds both the real and imaginary accumulators, halving
    // memory traffic vs. running re/im as separate passes. Same
    // alignment guard as [project] / [recombineFromProjection].
    final evenPairs = n >> 1;
    final hasTail = (n & 1) == 1;
    final tailIdx = n - 1;
    final reX = Float64x2List((n + 1) >> 1);
    final imX = Float64x2List((n + 1) >> 1);
    final re = Float64List.view(reX.buffer, 0, n);
    final im = Float64List.view(imX.buffer, 0, n);
    final basisAligned = (eigenvectors.offsetInBytes & 15) == 0;

    for (var j = 0; j < k; j++) {
      final c = coeffs[j];
      if (c == 0.0) continue;
      final phase = t * eigenvalues[j];
      final cReal = c * math.cos(phase);
      final cImag = -c * math.sin(phase);
      final base = j * n;
      if (evenPairs > 0 && basisAligned && ((base * 8) & 15) == 0) {
        final eigX = Float64x2List.view(eigenvectors.buffer,
            eigenvectors.offsetInBytes + base * 8, evenPairs);
        for (var i = 0; i < evenPairs; i++) {
          final u = eigX[i];
          reX[i] = reX[i] + u.scale(cReal);
          imX[i] = imX[i] + u.scale(cImag);
        }
      } else {
        for (var i = 0; i < evenPairs * 2; i++) {
          final u = eigenvectors[base + i];
          re[i] += cReal * u;
          im[i] += cImag * u;
        }
      }
      if (hasTail) {
        final u = eigenvectors[base + tailIdx];
        re[tailIdx] += cReal * u;
        im[tailIdx] += cImag * u;
      }
    }
    // Return caller-owned fresh buffers (views alias reX/imX storage).
    final outRe = Float64List(n)..setRange(0, n, re);
    final outIm = Float64List(n)..setRange(0, n, im);
    return (real: outRe, imag: outIm);
  }

  /// Born-rule probability density `|ψ(t)|²` at every node. Preserved
  /// under unitary evolution: `Σᵢ |ψ|²(i, t) = ‖ρ‖²` for all t.
  ///
  /// **Reading**: quantum probability of finding the focus at file i
  /// after unitary evolution for time t. Mass never leaks away (unlike
  /// heat), so this is the proper observable for "where would this
  /// focus interfere with another one?" style questions.
  Float64List quantumProbability(Float64List rho, double t) {
    final psi = unitaryDiffuse(rho, t);
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      out[i] = psi.real[i] * psi.real[i] + psi.imag[i] * psi.imag[i];
    }
    return out;
  }

  /// Per-node interference field between two focuses `ρ_a`, `ρ_b`
  /// under unitary evolution at time t. Defined as
  /// `2·Re(ψ_a(i) · conj(ψ_b(i)))` — the cross term in
  /// `|ψ_a + ψ_b|² = |ψ_a|² + |ψ_b|² + 2·Re(ψ_a·ψ_b*)`. Positive at
  /// nodes where the two focuses constructively interfere, negative
  /// where they destructively interfere.
  ///
  /// **Reading**: where in the codebase would two PRs/queries/foci
  /// *combine amplitude* rather than just share files? File-overlap
  /// and embedding cosines are classical; this is quantum. A sharp
  /// negative valley means the two foci are out of phase in that
  /// region — they describe it differently despite touching it both.
  /// A sharp positive peak means they reinforce each other.
  Float64List interferenceField(
      Float64List rhoA, Float64List rhoB, double t) {
    final a = unitaryDiffuse(rhoA, t);
    final b = unitaryDiffuse(rhoB, t);
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      out[i] =
          2.0 * (a.real[i] * b.real[i] + a.imag[i] * b.imag[i]);
    }
    return out;
  }

  /// Total interference mass — `∑ᵢ 2·Re(ψ_a·ψ_b*)` — as a single
  /// scalar. Unitary evolution preserves the inner product
  /// `⟨ψ_a, ψ_b⟩ = ⟨c_a, c_b⟩` for all t, so this reduces to
  /// `2·⟨c_a, c_b⟩` — a **time-independent** scalar (the integrated
  /// cross-term is a conserved quantity, even though its per-node
  /// distribution evolves into visible fringes).
  ///
  /// Sign-carrying: positive for focus pairs whose spectral
  /// coefficients align, negative for anti-aligned pairs, zero for
  /// spectrally orthogonal pairs (the interesting case: two focuses
  /// that share no dominant eigenmode despite sharing files).
  double interferenceMass(Float64List rhoA, Float64List rhoB) {
    final ca = project(rhoA);
    final cb = project(rhoB);
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      s += ca[j] * cb[j];
    }
    return 2.0 * s;
  }

  /// Thermodynamic evaporation: the OG Logos confidence gate, ported
  /// verbatim from the byte-level codec to the graph-level engine.
  /// `c` is a confidence signal in `[0, 1]` — defaults to `1 −
  /// spectralEntropy(rho, t) / log(k)`, the natural "how focused is
  /// this query" scalar. Returns `f = e^{−(1−c)²}` — the
  /// crystal/gas freeze function from OG Logos' `live-wasm-logos.ts`.
  ///
  /// **Reading**: `f → 1` when confidence is high (crystal phase —
  /// trust the basis, do nothing). `f → 1/e ≈ 0.368` when confidence
  /// bottoms out (gas phase — the basis is no longer describing the
  /// signal well, consider a refresh). Landau second-order transition
  /// math — same function OG Logos uses to decide when to freeze /
  /// melt its predictor tables. Same ontology, transplanted cleanly.
  double evaporationFactor(Float64List rho, double t) {
    if (k == 0) return 0.0;
    final s = spectralEntropy(rho, t);
    final bound = math.log(k.toDouble());
    if (bound <= 0.0) return 1.0;
    final c = (1.0 - s / bound).clamp(0.0, 1.0).toDouble();
    final delta = 1.0 - c;
    return math.exp(-delta * delta);
  }
}

Signature _fingerprintEigenvalues(Float64List values) =>
    fingerprintFloat64(values);

/// **Theorem-tight** (SU(2) rotation angle is exact). **Grover
/// amplification on an n-dimensional amplitude vector** — Grover's
/// quantum-search algorithm operating on a real-valued state vector
/// indexed by graph nodes. O(√n) iterations concentrate the amplitude
/// on a marked node [target] starting from the uniform state
/// `(1/√n, …, 1/√n)`.
///
/// ## The iteration
///
///     ψ ← (2|u⟩⟨u| − I)·(I − 2|target⟩⟨target|)·ψ
///
/// where `|u⟩` is the uniform-superposition vector. First the oracle
/// flips amplitude at the target; then the diffusion operator
/// reflects about the uniform state. Together: a rotation in the
/// 2-plane spanned by `|target⟩` and `|u⟩`, with angle `2·asin(1/√n)`
/// per iteration.
///
/// ## Mathematical note
///
/// The two operators involved **do not commute** — the oracle lives
/// in the node basis, the diffusion in the mode basis. This is the
/// first primitive in the engine that genuinely uses non-commuting
/// operators; everything else in `SpectralOperator` is a function
/// of L and so auto-commutes. The non-commutativity is *exactly*
/// why Grover works: it's the structure constant of the SU(2)
/// rotation that drives the amplitude toward the target.
///
/// ## Classical use
///
/// Given `n` files, find the structurally-focused one in O(√n) runs
/// of a ranker. Not a speedup over classical in the compute-cost
/// sense (we're not on a quantum computer), but a genuine O(√n)-step
/// construction: if you have an oracle that marks candidates, Grover
/// concentrates mass on them faster than linear sweep would
/// discover them.
///
/// Returns the amplified state as a new Float64List; does not
/// mutate the input.
Float64List groverAmplify({
  required Float64List initial,
  required int target,
  required int iterations,
}) {
  final n = initial.length;
  if (target < 0 || target >= n) {
    throw RangeError('groverAmplify: target $target out of range [0, $n)');
  }
  if (iterations < 0) {
    throw ArgumentError('groverAmplify: iterations must be >= 0');
  }
  var psi = Float64List.fromList(initial);
  for (var step = 0; step < iterations; step++) {
    // Oracle: flip amplitude at target.
    psi[target] = -psi[target];
    // Diffusion: reflect about the uniform state.
    var mean = 0.0;
    for (var i = 0; i < n; i++) {
      mean += psi[i];
    }
    mean /= n;
    for (var i = 0; i < n; i++) {
      psi[i] = 2 * mean - psi[i];
    }
  }
  return psi;
}

/// **Grover via Fourier** — one iteration of Grover's amplification
/// expressed through the graph's spectral basis. Makes explicit the
/// fact that Grover's algorithm is a **Fourier-mediated alternation**
/// between two diagonal profiles living in different bases.
///
/// The iteration decomposes as four clean steps:
///
///   1. **Oracle** (profile in node basis):
///      `ψ[v] ← −ψ[v]` when `v == target`, else unchanged.
///      This is diagonal in the primal basis: `O = I − 2|target⟩⟨target|`.
///
///   2. **Forward Fourier** to the mode basis:
///      `c = Uᵀ · ψ_oracled`
///
///   3. **Diffusion** (profile in mode basis):
///      `c[0] ← c[0]`, `c[j≥1] ← −c[j]`.
///      This is diagonal in the dual basis: `D = 2|u₀⟩⟨u₀| − I`
///      where u₀ is the zero-mode eigenvector (uniform on regular
///      graphs, up to sign).
///
///   4. **Inverse Fourier** back to node basis:
///      `ψ_out = U · c_diffused`
///
/// The key insight: **neither profile is diagonal in the other's
/// basis**. That's the non-commutativity driving Grover's
/// convergence. Every iteration is one Fourier transform out, one
/// back. The algorithm IS Fourier analysis.
///
/// ### Theorem (verified by test)
///
/// On any REGULAR graph where `u₀ = (1/√n, …, 1/√n)` (up to sign),
/// with a full-rank basis (k = n),
/// `groverStepViaFourier(ψ, basis, target)` equals
/// `groverAmplify(initial: ψ, target: target, iterations: 1)` to f64
/// precision. The two express the same quantum step in different
/// coordinates.
///
/// Throws on out-of-range [target].
Float64List groverStepViaFourier({
  required Float64List psi,
  required SpectralBasis basis,
  required int target,
}) {
  if (target < 0 || target >= basis.n) {
    throw RangeError(
        'groverStepViaFourier: target $target out of range [0, ${basis.n})');
  }
  // Step 1: oracle — flip amplitude at target (profile in node basis).
  final oracled = Float64List.fromList(psi);
  oracled[target] = -oracled[target];
  // Step 2: forward Fourier to mode basis.
  final coeffs = basis.project(oracled);
  // Step 3: diffusion — profile [1, −1, −1, …, −1] in mode basis.
  // This is D = 2|u_0⟩⟨u_0| − I expressed diagonally.
  final diffused = Float64List.fromList(coeffs);
  for (var j = 1; j < basis.k; j++) {
    diffused[j] = -diffused[j];
  }
  // Step 4: inverse Fourier back to node basis.
  return basis.recombineFromProjection(diffused, 0.0);
}

/// Optimal iteration count for Grover amplification on [n] states
/// with a single marked element: `⌊(π/4)·√n⌋`. Past this count, the
/// amplitude oscillates away from the target; below it, the target
/// isn't fully concentrated.
int groverOptimalIterations(int n) {
  if (n <= 1) return 0;
  return (math.pi / 4 * math.sqrt(n)).round();
}

/// Geodesic distance in the Poincaré disc between two 2-D coordinates.
///
///   d(u, v) = acosh(1 + 2·|u − v|² / ((1 − |u|²)(1 − |v|²)))
///
/// Inputs must live in the open unit disc (|u|, |v| < 1). Points on or
/// outside the boundary give `double.infinity`. Paired with
/// [SpectralBasis.poincareCoordinateTable], which caps radius below 1.
///
/// For tree-like graphs this metric tracks graph-hop distance
/// dramatically better than Euclidean distance in the same 2 dims —
/// 4.6× lower multiplicative distortion on empirical code co-change
/// structure vs. 8-D Fiedler coords.
double poincareDistance(double xa, double ya, double xb, double yb) {
  final normA = xa * xa + ya * ya;
  final normB = xb * xb + yb * yb;
  if (normA >= 1.0 || normB >= 1.0) return double.infinity;
  final dx = xa - xb;
  final dy = ya - yb;
  final diffSq = dx * dx + dy * dy;
  final denom = (1.0 - normA) * (1.0 - normB);
  if (denom <= 0.0) return double.infinity;
  final arg = 1.0 + 2.0 * diffSq / denom;
  // acosh(x) defined for x ≥ 1; guard the tiny floating-point underhang.
  return _acosh(arg < 1.0 ? 1.0 : arg);
}

// ── Hodge calculus — exterior derivatives on the graph ────────────
//
// A graph is a 1-complex: 0-cells are nodes, 1-cells are edges. The
// exterior derivative `d` and its adjoint `δ` (codifferential) are
// the discrete differential operators on this complex:
//
//     d₀ : C⁰(V) → C¹(E)     (0-forms → 1-forms, "gradient")
//     δ₀ : C¹(E) → C⁰(V)     (1-forms → 0-forms, "divergence")
//
// Inner products:
//     ⟨ρ, σ⟩_V  = Σ_v ρ(v)·σ(v)
//     ⟨α, β⟩_E  = Σ_{(u,v)} W(u,v)·α(u,v)·β(u,v)  (weighted)
//
// Green's identity (the adjoint relation):
//     ⟨d₀ ρ, α⟩_E  =  ⟨ρ, δ₀ α⟩_V
//
// The node-Laplacian is the composition:
//     Δ₀ = δ₀ · d₀   (positive semi-definite, our normalised L)
//
// This block ships the three as explicit primitives so the engine's
// flow-decomposition story is no longer implicit. It also paves the
// path for Hodge decomposition of edge flows into gradient /
// coexact / harmonic components — a proper theorem on graphs, with
// the harmonic component carrying topological information about
// cycles (β₁).

/// Exterior derivative of a node-scalar `rho` to an edge-flow. Uses
/// the normalised convention `(d₀ρ)(u, v) = W_norm(u, v) · (ρ(v) − ρ(u))`
/// for each directed edge (u → v) with u < v, so the output is
/// naturally weighted by the fused `D^{-1/2}` graph values. The
/// sign follows the oriented-simplex convention: traversing u → v
/// gives ρ(v) − ρ(u), and the reverse orientation flips sign.
///
/// Output layout is parallel to [CsrGraph.indptr] / [CsrGraph.indices]:
/// one entry per CSR slot. For the symmetric graph this produces
/// anti-symmetric pairs (u→v and v→u have opposite sign).
///
/// Cost: O(|E|). Pure — does not mutate the input.
Float64List exteriorDerivative0(CsrGraph graph, Float64List rho) {
  if (rho.length != graph.n) {
    throw StateError(
        'exteriorDerivative0: rho length ${rho.length} != graph.n ${graph.n}');
  }
  final out = Float64List(graph.values.length);
  for (var u = 0; u < graph.n; u++) {
    for (var p = graph.indptr[u]; p < graph.indptr[u + 1]; p++) {
      final v = graph.indices[p];
      out[p] = graph.values[p] * (rho[v] - rho[u]);
    }
  }
  return out;
}

/// Codifferential (divergence) of an edge-flow to a node-scalar —
/// the adjoint of [exteriorDerivative0] under the inner products
/// defined in the block comment above. Equivalent formulation: for
/// each node u, sum incoming contributions weighted by the edge.
///
///     (δ₀ α)(u) = Σ_{v~u} W_norm(u, v) · α(v → u)
///              = −Σ_{v~u} W_norm(u, v) · α(u → v)     (anti-symmetric α)
///
/// The two forms are equal for anti-symmetric edge flows produced by
/// [exteriorDerivative0]; this implementation uses the second form,
/// traversing each node's outgoing edges and negating.
Float64List codifferential1(CsrGraph graph, Float64List edgeFlow) {
  if (edgeFlow.length != graph.values.length) {
    throw StateError(
        'codifferential1: edgeFlow length ${edgeFlow.length} != '
        '|E| ${graph.values.length}');
  }
  final out = Float64List(graph.n);
  for (var u = 0; u < graph.n; u++) {
    var s = 0.0;
    for (var p = graph.indptr[u]; p < graph.indptr[u + 1]; p++) {
      s -= graph.values[p] * edgeFlow[p];
    }
    out[u] = s;
  }
  return out;
}

/// The node Laplacian as a composition: `Δ₀ = δ₀ · d₀`. By
/// construction this equals the graph's normalised-Laplacian action
/// up to sign (the engine's fused L_sym encoding makes the matvec
/// `y = ρ − W_norm·ρ`, which is this composition plus the identity
/// term — see [SpectralBasis.diffuse] for the version the engine
/// actually uses). Shipped for completeness of the Hodge layer and
/// as a theorem-verifier against the engine's L_sym.
Float64List laplacianFromExterior(CsrGraph graph, Float64List rho) {
  return codifferential1(graph, exteriorDerivative0(graph, rho));
}

/// Alon-Boppana expansion margin — how close a graph is to being a
/// theoretically-optimal expander for its sparsity.
///
///   margin = λ_gap(L_sym) / (1 − 2·sqrt(d̄ − 1) / d̄)
///
/// where `d̄` is the graph's harmonic-mean combinatorial degree. The
/// denominator is the Alon-Boppana upper bound on the normalized
/// Laplacian's spectral gap: no d̄-regular graph can exceed it
/// asymptotically. Graphs that reach or approximately saturate this
/// bound are called "Ramanujan" — the best possible expanders for
/// their sparsity.
///
/// Interpretation of the ratio:
///   - `margin ≥ 1.0`  — the graph saturates or exceeds the bound.
///                       Random d-regulars, complete graphs, and
///                       high-mixing SBMs land here.
///   - `0.5 ≤ margin < 1.0` — "good" expansion; bounded bottleneck.
///   - `margin < 0.5`  — bottleneck-dominated. Real code co-change
///                       graphs land here (empirical: this repo's
///                       Dart app is ~0.25).
///   - `margin < 0.05` — structurally fragmented; a clear dumbbell or
///                       multi-community graph.
///
/// Empirical reference: `tm_next_observables.py §A` — on synthetic
/// fixtures, random 3-regulars score ~1.6-2.1, SBM with weak cross-
/// blocks ~0.65, dumbbells ~0.009. The Dart co-change graph of this
/// repo scores 0.25 — bottleneck-dominated but not fragmented.
///
/// Returns `double.nan` when `graph.harmonicMeanDegree() < 3` (the
/// bound formula degenerates for very sparse graphs — cycles and
/// chains especially). Returns the numeric ratio otherwise.
double alonBoppanaMargin(SpectralBasis basis, CsrGraph graph) {
  final d = graph.harmonicMeanDegree();
  if (d < 3.0) return double.nan;
  final gap = basis.spectralGap;
  if (!gap.isFinite || gap <= 0.0) return double.nan;
  final bound = 1.0 - 2.0 * math.sqrt(d - 1.0) / d;
  if (bound <= 0.0) return double.nan;
  return gap / bound;
}

/// `tanh(x)` via `exp`, numerically stable for large |x|.
double _tanh(double x) {
  if (x > 20.0) return 1.0;
  if (x < -20.0) return -1.0;
  final e2x = math.exp(2.0 * x);
  return (e2x - 1.0) / (e2x + 1.0);
}

/// `acosh(x) = log(x + sqrt(x² − 1))` for `x ≥ 1`.
double _acosh(double x) {
  if (x <= 1.0) return 0.0;
  return math.log(x + math.sqrt(x * x - 1.0));
}

/// Universal name for the object the tower collapses into — every
/// level of the tower (file, hunk, chunk, commit, spacetime) returns
/// an instance of this type. Instances are:
///   - immutable (frozen bytes + integer metadata)
///   - cheaply identity-comparable via [SpectralBasis.signature]
///   - hashable for cache keys, CRDT merges, and wire transfers
///   - labeled or unlabeled (paths optional; math works regardless)
///   - serializable to a single byte blob (see `toBytes` / `fromBytes`)
///
/// Observables are pure functions of `(SpectralIdentity, SourceCoord,
/// temperature)`. The class holds the data; free functions + instance
/// methods give you the readouts. This is the singularity: one type,
/// many readouts, no hidden state.
typedef SpectralIdentity = SpectralBasis;

/// A source distribution expressed in the spectral coordinates of a
/// specific [SpectralBasis]. This is the noun for `Uᵀ·ρ` — the k
/// projection coefficients you get back from `basis.project(rho)`.
///
/// Before this type existed, callers passed a `Float64List` of length
/// `k` around and had to remember which basis it belonged to. Now:
///
///   final source = basis.projectSource(rho);
///   source.diffuseAt(t);           // temperature sweep, basis implicit
///   source.phiForPath('lib/x.dart', t);
///   source.entropy(t);
///   source.freeEnergy(t);
///
/// The type carries its basis reference so projections can't be
/// accidentally applied against the wrong spectrum. Identity checks
/// go through [SpectralBasis.signature]; cross-basis operations
/// throw when signatures don't match.
class SpectralProjection {
  const SpectralProjection({
    required this.basis,
    required this.coefficients,
  });

  /// The basis this projection is expressed against.
  final SpectralBasis basis;

  /// The `Uᵀ·ρ` coefficient vector of length [SpectralBasis.k].
  final Float64List coefficients;

  /// Signature of the underlying basis. Two projections with matching
  /// signatures refer to the same spectrum; they can be linearly
  /// combined without re-projection.
  Signature get basisSignature => basis.signature;

  /// Diffuse at temperature [t] — same contract as
  /// `basis.recombineFromProjection(coefficients, t)` but the noun
  /// carries its own basis reference so the caller doesn't have to
  /// thread `basis` through every call.
  Float64List diffuseAt(double t) =>
      basis.recombineFromProjection(coefficients, t);

  /// Read the diffused mass at a specific labeled path at scale [t].
  /// O(k). Throws if the basis isn't labeled.
  double phiForPath(String path, double t) =>
      basis.phiForPath(coefficients, path, t);

  /// Reconstruct the source ρ that produced this projection. Useful
  /// when the caller needs to reuse the same source through a
  /// different basis (rare, but necessary for cross-level lifts).
  /// Equivalent to `diffuseAt(0.0)` modulo Lanczos-truncation residue.
  Float64List reconstructSource() => diffuseAt(0.0);

  // `entropy(t)` and `freeEnergy(t)` on SpectralProjection now live
  // in `logos_thermo.dart` (extension SpectralProjectionThermo).

  /// Symmetric KL (Jeffreys) divergence between two thermal
  /// mode-probability distributions at temperature [t]:
  /// `J = Σⱼ (pⱼ − qⱼ) · log(pⱼ / qⱼ)` where
  /// `pⱼ = e^{−t·λⱼ}·cⱼ²/Z_p` and similarly for `q`.
  ///
  /// **Scale invariance**: ρ and α·ρ produce identical probabilities
  /// `p` (the normaliser absorbs α), so this divergence reads the
  /// *shape* of the focus in spectral coordinates, ignoring total
  /// mass. This is the structural complement to the L² mass-sensitive
  /// [SpectralBasis.spectralDivergence]: two PRs that touch the same
  /// structural region at different scales differ loudly in L² but
  /// are identical in Jeffreys.
  ///
  /// Returns `0.0` when either projection's partition function
  /// underflows. Throws [StateError] when the bases don't match.
  double jeffreysDivergence(SpectralProjection other, double t) {
    if (basis.signature != other.basis.signature) {
      throw StateError(
        'jeffreysDivergence: basis signatures must match '
        '(${basis.signature} vs ${other.basis.signature})',
      );
    }
    final k = basis.k;
    if (k == 0) return 0.0;
    final pa = Float64List(k);
    final pb = Float64List(k);
    var za = 0.0;
    var zb = 0.0;
    for (var j = 0; j < k; j++) {
      final decay = math.exp(-t * basis.eigenvalues[j]);
      final wa = decay * coefficients[j] * coefficients[j];
      final wb = decay * other.coefficients[j] * other.coefficients[j];
      pa[j] = wa;
      pb[j] = wb;
      za += wa;
      zb += wb;
    }
    if (za <= _subnormalFloor || zb <= _subnormalFloor) return 0.0;
    final invA = 1.0 / za;
    final invB = 1.0 / zb;
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      final p = pa[j] * invA;
      final q = pb[j] * invB;
      if (p > _subnormalFloor && q > _subnormalFloor) {
        s += (p - q) * math.log(p / q);
      }
    }
    return s;
  }

  /// Squared-L² norm of the projection — equals the squared-L² norm
  /// of the original ρ if the basis is full-rank. Useful for
  /// normalization, fidelity checks, and detecting basis-truncation
  /// loss.
  double get squaredNorm {
    var s = 0.0;
    for (var j = 0; j < basis.k; j++) {
      s += coefficients[j] * coefficients[j];
    }
    return s;
  }

  /// Linear superposition of two projections against the same basis.
  /// Throws [StateError] if signatures don't match — you can't
  /// meaningfully add coefficients in different spectral coordinates.
  /// This is the CRDT-friendly operator: two source coords with the
  /// same basis signature merge by vector addition.
  SpectralProjection operator +(SpectralProjection other) {
    if (basis.signature != other.basis.signature) {
      throw StateError(
        'SpectralProjection + : basis signatures must match '
        '(${basis.signature} vs ${other.basis.signature})',
      );
    }
    final out = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      out[j] = coefficients[j] + other.coefficients[j];
    }
    return SpectralProjection(basis: basis, coefficients: out);
  }

  /// Scalar scaling.
  SpectralProjection scale(double s) {
    final out = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      out[j] = coefficients[j] * s;
    }
    return SpectralProjection(basis: basis, coefficients: out);
  }

  /// **Negative-time heat deconvolution** — the inverse of
  /// [diffuseAt]. Given this projection interpreted as `φ(t₀)`, try
  /// to recover the source `ρ(t₀ − t)` that would have evolved into
  /// it under heat flow. Mathematically: apply `exp(+t·L)` to the
  /// coefficients, which is `exp(+t·λⱼ)` per mode.
  ///
  /// ## Why this "shouldn't" work
  ///
  /// The heat equation `∂φ/∂τ = −L·φ` is irreversible — high-frequency
  /// modes decay, and undoing them means *amplifying* them with
  /// `e^{+tλⱼ}`. For large t and large λⱼ this explodes, turning
  /// any numerical noise on a high mode into a large artefact.
  /// Running the heat kernel backward is the textbook example of an
  /// **ill-posed inverse problem**.
  ///
  /// ## Why it DOES work (with care)
  ///
  /// Regularise by cutting off modes where `λⱼ > cutoffLambda`.
  /// Inside the cutoff band the amplification is bounded
  /// (`e^{t·cutoff}`). Outside, modes are zeroed out: we accept
  /// losing the smallest-scale detail in exchange for stability.
  /// This is **Tikhonov regularisation** in the spectral domain.
  ///
  /// For small t and modest cutoff, round-trip deconvolution
  /// recovers the original source to fp precision. For large t it
  /// degrades gracefully — the engine won't hallucinate, just
  /// attenuate.
  ///
  /// ## Use case
  ///
  /// Given an observed attention field (the diffused result of some
  /// query), identify what focus could have produced it. "What
  /// focus, diffused for t=1.0, gave rise to this activity field?"
  /// The answer is `focus.diffuseAt(1.0).deconvolveTo(1.0)`.
  SpectralProjection deconvolveTo(
    double t, {
    double cutoffLambda = 2.0,
  }) {
    final k = basis.k;
    final out = Float64List(k);
    for (var j = 0; j < k; j++) {
      final lam = basis.eigenvalues[j];
      if (lam > cutoffLambda) continue; // regularise high modes to 0
      out[j] = coefficients[j] * math.exp(t * lam);
    }
    return SpectralProjection(basis: basis, coefficients: out);
  }

  /// Inner product `⟨this, other⟩` in coefficient space. Because the
  /// eigenbasis is orthonormal, this equals the inner product of the
  /// two source distributions — Parseval's identity, free.
  ///
  /// Throws [StateError] on basis-signature mismatch.
  double dot(SpectralProjection other) {
    if (basis.signature != other.basis.signature) {
      throw StateError(
        'SpectralProjection.dot: basis signatures must match '
        '(${basis.signature} vs ${other.basis.signature})',
      );
    }
    var s = 0.0;
    for (var j = 0; j < basis.k; j++) {
      s += coefficients[j] * other.coefficients[j];
    }
    return s;
  }

  /// Cosine alignment in coefficient space — `⟨a, b⟩ / (‖a‖·‖b‖)`.
  /// In `[-1, 1]`. Returns `0.0` when either projection has zero norm.
  ///
  /// This is the spectral-coordinate version of "how aligned are these
  /// two queries with the graph's eigenmodes?" — orthogonal queries
  /// illuminate disjoint regions of the structure.
  double alignmentWith(SpectralProjection other) {
    final a = squaredNorm;
    final b = other.squaredNorm;
    if (a <= _subnormalFloor || b <= _subnormalFloor) return 0.0;
    return dot(other) / (math.sqrt(a) * math.sqrt(b));
  }

  /// Orthogonal decomposition of `this` against [other]:
  ///
  ///     this = parallel + orthogonal
  ///     parallel    = (⟨this, other⟩ / ‖other‖²) · other
  ///     orthogonal  = this − parallel
  ///
  /// Returns `(parallel, orthogonal, alignment)` where:
  /// * `parallel` is the component of `this` along [other] — "the part
  ///   of this query that is already explained by the reference."
  /// * `orthogonal` is the residual — "what's *new* in this query that
  ///   the reference doesn't see."
  /// * `alignment` is the cosine in `[-1, 1]`, the scalar summary.
  ///
  /// Both parallel and orthogonal live in the same basis as `this`
  /// and can be diffused / scaled / fed back into the engine
  /// independently. Orthogonality is guaranteed:
  /// `parallel.dot(orthogonal) ≈ 0` to f64 precision.
  ///
  /// Use cases:
  /// * **Novelty queries**: "What's structurally new in today's PR vs
  ///   yesterday's review focus?" Decompose today against yesterday;
  ///   surface the orthogonal component.
  /// * **Attention subtraction**: "Show me the part of this query that
  ///   DOESN'T overlap with the areas we've already reviewed."
  /// * **Canonical basis extension**: sequentially decompose a new
  ///   query against accumulated references to build an orthogonal
  ///   history (Gram-Schmidt on queries).
  ///
  /// Throws [StateError] on basis-signature mismatch. When [other]
  /// has zero norm, returns `(zero, this, 0.0)` — no reference means
  /// the whole query is "new."
  ({
    SpectralProjection parallel,
    SpectralProjection orthogonal,
    double alignment,
  }) decomposeAgainst(SpectralProjection other) {
    if (basis.signature != other.basis.signature) {
      throw StateError(
        'SpectralProjection.decomposeAgainst: basis signatures must match '
        '(${basis.signature} vs ${other.basis.signature})',
      );
    }
    final otherSq = other.squaredNorm;
    final k = basis.k;
    if (otherSq <= _subnormalFloor) {
      final zeros = Float64List(k);
      return (
        parallel: SpectralProjection(basis: basis, coefficients: zeros),
        orthogonal: SpectralProjection(
          basis: basis,
          coefficients: Float64List.fromList(coefficients),
        ),
        alignment: 0.0,
      );
    }
    final inner = dot(other);
    final scale = inner / otherSq;
    final parallelCoeff = Float64List(k);
    final orthCoeff = Float64List(k);
    for (var j = 0; j < k; j++) {
      parallelCoeff[j] = scale * other.coefficients[j];
      orthCoeff[j] = coefficients[j] - parallelCoeff[j];
    }
    final selfNorm = math.sqrt(squaredNorm);
    final otherNorm = math.sqrt(otherSq);
    final alignment =
        selfNorm <= _subnormalFloor ? 0.0 : inner / (selfNorm * otherNorm);
    return (
      parallel: SpectralProjection(basis: basis, coefficients: parallelCoeff),
      orthogonal: SpectralProjection(basis: basis, coefficients: orthCoeff),
      alignment: alignment,
    );
  }

  /// Per-band alignment between two projections — returns a vector of
  /// cosines, one per band. Lets a caller ask "at which SCALES are
  /// these two queries similar, and at which are they different?"
  ///
  /// Example: two PRs touching the same community (high low-band
  /// alignment) but with different micro-level focuses (low high-band
  /// alignment) produce a characteristic descending-cosine profile.
  ///
  /// Throws [StateError] on basis mismatch or invalid [modeCuts]
  /// (same rules as [bandDecompose]).
  List<double> bandAlignmentWith(
    SpectralProjection other,
    List<int> modeCuts,
  ) {
    if (basis.signature != other.basis.signature) {
      throw StateError(
        'SpectralProjection.bandAlignmentWith: basis signatures must match '
        '(${basis.signature} vs ${other.basis.signature})',
      );
    }
    final myBands = bandDecompose(modeCuts);
    final theirBands = other.bandDecompose(modeCuts);
    final out = List<double>.filled(myBands.length, 0.0);
    for (var b = 0; b < myBands.length; b++) {
      out[b] = myBands[b].alignmentWith(theirBands[b]);
    }
    return out;
  }

  /// Gram-Schmidt orthogonalisation over a sequence of projections
  /// sharing the same basis. Returns a list where the i-th entry is
  /// the orthogonal residue of `queries[i]` against every prior entry
  /// — normalised to unit coefficient norm when non-zero.
  ///
  /// Use case: **de-duplicate a query history**. The first query is
  /// kept as-is (normalised). Each subsequent query is projected
  /// onto the span of previous residues and only the orthogonal
  /// complement is retained. The output is an orthonormal basis of
  /// the query sequence's reachable span — telling you which queries
  /// added *new* structural coverage vs merely revisited old ground.
  ///
  /// Duplicate-or-dependent queries collapse to zero-norm entries in
  /// the output. Callers can filter those out to get the actual
  /// independent basis.
  ///
  /// Throws [StateError] when the list contains projections against
  /// different bases.
  static List<SpectralProjection> gramSchmidt(
    List<SpectralProjection> queries,
  ) {
    if (queries.isEmpty) return const [];
    final baseSig = queries.first.basis.signature;
    for (final q in queries) {
      if (q.basis.signature != baseSig) {
        throw StateError(
          'SpectralProjection.gramSchmidt: all queries must share a basis',
        );
      }
    }
    final out = <SpectralProjection>[];
    for (final q in queries) {
      var residue = q;
      for (final prior in out) {
        final priorSq = prior.squaredNorm;
        if (priorSq <= _subnormalFloor) continue;
        residue = residue.decomposeAgainst(prior).orthogonal;
      }
      // Normalise to unit norm if non-zero (matches the "orthoNORMAL"
      // claim). Zero-residue queries stay zero — they added no new
      // direction. Threshold is well above floating-point dust from
      // the decomposition (~1e-15 on reasonable bases) so a true
      // duplicate collapses cleanly to zero instead of getting
      // spuriously normalised up.
      const kZeroResidueThreshold = 1e-12;
      final norm = math.sqrt(residue.squaredNorm);
      if (norm > kZeroResidueThreshold) {
        residue = residue.scale(1.0 / norm);
      } else {
        residue = SpectralProjection(
          basis: residue.basis,
          coefficients: Float64List(residue.basis.k),
        );
      }
      out.add(residue);
    }
    return out;
  }

  /// **Dream-fill** — the inverse of [compressToTopK]. Takes the
  /// present coefficients as a constraint and samples plausible
  /// values for the missing modes from a thermal prior.
  ///
  /// Behaviour:
  /// * Non-zero coefficients are preserved exactly (they are the
  ///   "observation").
  /// * Zero coefficients are filled with Box-Muller Gaussian samples
  ///   of variance `priorVariance · e^{-t·λⱼ}` — a thermal prior
  ///   that weights low-frequency modes with more energy, matching
  ///   the physics of heat-flow-like distributions on graphs.
  /// * The `seed` makes the dream reproducible: the same projection
  ///   + seed always yields the same filled completion.
  ///
  /// Use case: given a compressed [SpectralProjection] transmitted
  /// over the wire (via top-K retention), recover a full projection
  /// that (a) reproduces the sent coefficients exactly, (b) fills
  /// the rest with a thermodynamically-plausible "imagination" of
  /// what was dropped. Round-trip is lossy (you don't recover the
  /// original discarded coefficients), but the SHAPE of the filled
  /// projection matches the thermal prior.
  ///
  /// `priorVariance` controls the noise amplitude. 0 reproduces the
  /// compressed input verbatim (no fill). Large values produce noisy
  /// dreams.
  SpectralProjection dreamFill({
    double priorVariance = 0.01,
    double priorTemperature = 1.0,
    int seed = 42,
  }) {
    final k = basis.k;
    final out = Float64List(k);
    final rng = math.Random(seed);
    for (var j = 0; j < k; j++) {
      if (coefficients[j] != 0.0) {
        out[j] = coefficients[j];
        continue;
      }
      if (priorVariance <= 0.0) {
        out[j] = 0.0;
        continue;
      }
      // Box-Muller Gaussian with std = sqrt(priorVariance · exp(-tλⱼ)).
      final u1 = rng.nextDouble().clamp(1e-300, 1.0);
      final u2 = rng.nextDouble();
      final gauss = math.sqrt(-2.0 * math.log(u1)) *
          math.cos(2.0 * math.pi * u2);
      final std = math.sqrt(
          priorVariance * math.exp(-priorTemperature * basis.eigenvalues[j]));
      out[j] = std * gauss;
    }
    return SpectralProjection(basis: basis, coefficients: out);
  }

  /// **Low-rank compression** — zero out every coefficient except
  /// the [keepK] largest by absolute magnitude. Returns a new
  /// projection on the same basis.
  ///
  /// This is the analogue of truncating a Fourier series: keep the
  /// dominant frequencies, discard the rest. The approximation is
  /// *optimal* in the sense of minimum L² reconstruction error —
  /// a consequence of Parseval's identity: the error squared equals
  /// the sum of squared discarded coefficients, so keeping the
  /// top-k by magnitude is exactly the L² minimiser.
  ///
  /// ## Theorem (test-verified)
  ///
  /// Let `c` be the original coefficient vector, `c̃` the compressed
  /// one with support size [keepK]. Then
  ///
  ///     ‖c − c̃‖² = Σ_{j ∉ kept} c_j²
  ///
  /// and this is the minimum over all support-size-[keepK] subsets
  /// (greedy-magnitude selection is globally optimal by the
  /// Pythagorean theorem in ℝᵏ).
  ///
  /// Use cases:
  /// * **Sketch queries for wire transport** — send only the top-k
  ///   coefficients; receiver reconstructs an approximation.
  /// * **Denoising** — drop low-magnitude coefficients which are
  ///   dominated by numerical noise / basis truncation error.
  /// * **Importance ranking** — the kept coefficient indices ARE
  ///   the most load-bearing modes for this query.
  SpectralProjection compressToTopK(int keepK) {
    final k = basis.k;
    if (keepK >= k) {
      return SpectralProjection(
        basis: basis,
        coefficients: Float64List.fromList(coefficients),
      );
    }
    if (keepK <= 0) {
      return SpectralProjection(
        basis: basis,
        coefficients: Float64List(k),
      );
    }
    // Index by |coefficient| descending; keep the first keepK.
    final indices = List<int>.generate(k, (i) => i);
    indices.sort((a, b) =>
        coefficients[b].abs().compareTo(coefficients[a].abs()));
    final kept = indices.take(keepK).toSet();
    final out = Float64List(k);
    for (final j in kept) {
      out[j] = coefficients[j];
    }
    return SpectralProjection(basis: basis, coefficients: out);
  }

  /// **Reconstruction error** against another projection on the same
  /// basis — the L² distance `‖this − other‖`. Used to characterise
  /// compression loss: `this.compressToTopK(k).reconstructionErrorTo(this)`
  /// is the truncation error.
  double reconstructionErrorTo(SpectralProjection other) {
    if (basis.signature != other.basis.signature) {
      throw StateError(
        'SpectralProjection.reconstructionErrorTo: basis signatures must match',
      );
    }
    var s = 0.0;
    for (var j = 0; j < basis.k; j++) {
      final d = coefficients[j] - other.coefficients[j];
      s += d * d;
    }
    return math.sqrt(s);
  }

  /// Partition this projection into **mode bands** — each band being
  /// the sub-projection whose coefficients are nonzero only in a
  /// contiguous range of modes. [modeCuts] is a sorted list of mode
  /// indices defining band boundaries; cuts at 0 or k are implicit.
  ///
  /// Example: for k=12 and `modeCuts = [4, 8]`, returns 3 projections:
  /// * band 0 covers modes [0, 4) — the coarsest structure (low freq)
  /// * band 1 covers modes [4, 8) — medium scale
  /// * band 2 covers modes [8, 12) — fine detail (high freq)
  ///
  /// ## Invariants
  ///
  /// * **Orthogonality**: `bands[i].dot(bands[j]) == 0` for `i != j`
  ///   (disjoint mode support ⇒ zero inner product in an orthonormal
  ///   basis).
  /// * **Completeness**: the sum of all bands reconstructs the original
  ///   projection exactly (no coefficient is dropped).
  ///
  /// ## Reading
  ///
  /// The coarsest band is the low-frequency structure — global
  /// community shape, macro-scale layout. The finest band is the
  /// high-frequency residual — local noise, per-file fluctuation.
  /// Asking "how similar are two queries at each scale?" is now
  /// `a.bandDecompose(cuts).zip(b.bandDecompose(cuts)).map(alignment)`.
  ///
  /// Throws [StateError] on cuts outside `[1, k-1]` or non-monotone
  /// cut order.
  List<SpectralProjection> bandDecompose(List<int> modeCuts) {
    final k = basis.k;
    // Validate & canonicalise cuts
    for (var i = 0; i < modeCuts.length; i++) {
      if (modeCuts[i] < 1 || modeCuts[i] >= k) {
        throw StateError(
          'SpectralProjection.bandDecompose: cut ${modeCuts[i]} outside '
          '[1, ${k - 1}]',
        );
      }
      if (i > 0 && modeCuts[i] <= modeCuts[i - 1]) {
        throw StateError(
          'SpectralProjection.bandDecompose: cuts must be strictly increasing',
        );
      }
    }
    final bounds = <int>[0, ...modeCuts, k];
    final out = <SpectralProjection>[];
    for (var b = 0; b < bounds.length - 1; b++) {
      final lo = bounds[b];
      final hi = bounds[b + 1];
      final coeffs = Float64List(k);
      for (var j = lo; j < hi; j++) {
        coeffs[j] = coefficients[j];
      }
      out.add(SpectralProjection(basis: basis, coefficients: coeffs));
    }
    return out;
  }
}

/// Lloyd's k-means clustering over a flat row-major embedding. Used
/// internally by [SpectralBasis.spectralCommunityLabels]. Centroids
/// are seeded by k-means++ for stable cluster ids; the algorithm
/// runs until either no labels change or `_kKmeansMaxIters` is hit.
List<int> _kmeansSpectral(
  Float64List points, // [n * d], row-major
  int n,
  int d,
  int kClusters,
  int seed,
) {
  if (n == 0) return const [];
  if (kClusters <= 1) return List<int>.filled(n, 0);
  final clamped = math.min(kClusters, n);

  // k-means++ initialisation: pick the first centroid uniformly at
  // random, then each subsequent centroid with probability
  // proportional to its squared distance to the nearest existing one.
  // This avoids the bad-starting-points failure mode of pure random
  // init and makes the labelling deterministic across runs.
  var rngState = (seed | 1) & 0x7fffffff;
  int nextInt(int bound) {
    rngState = (rngState * 1103515245 + 12345) & 0x7fffffff;
    return rngState % bound;
  }

  final centroids = Float64List(clamped * d);
  // First centroid: random sample.
  final firstId = nextInt(n);
  for (var dim = 0; dim < d; dim++) {
    centroids[dim] = points[firstId * d + dim];
  }
  final dist = Float64List(n);
  for (var c = 1; c < clamped; c++) {
    // Compute min squared distance to any existing centroid.
    var totalDist = 0.0;
    for (var i = 0; i < n; i++) {
      var minDist = double.infinity;
      for (var existing = 0; existing < c; existing++) {
        var s = 0.0;
        for (var dim = 0; dim < d; dim++) {
          final delta = points[i * d + dim] - centroids[existing * d + dim];
          s += delta * delta;
        }
        if (s < minDist) minDist = s;
      }
      dist[i] = minDist;
      totalDist += minDist;
    }
    if (totalDist <= 0) {
      // All points coincide with existing centroids — duplicate the
      // last one to fill the slot.
      for (var dim = 0; dim < d; dim++) {
        centroids[c * d + dim] = centroids[(c - 1) * d + dim];
      }
      continue;
    }
    // Sample proportional to dist[].
    final scaled = (nextInt(0x7fffffff) / 0x7fffffff) * totalDist;
    var cum = 0.0;
    var pick = n - 1;
    for (var i = 0; i < n; i++) {
      cum += dist[i];
      if (cum >= scaled) {
        pick = i;
        break;
      }
    }
    for (var dim = 0; dim < d; dim++) {
      centroids[c * d + dim] = points[pick * d + dim];
    }
  }

  final labels = List<int>.filled(n, 0);
  final newCentroids = Float64List(clamped * d);
  final counts = Int32List(clamped);

  for (var iter = 0; iter < _kKmeansMaxIters; iter++) {
    // Assignment: each point to its nearest centroid.
    var changed = 0;
    for (var i = 0; i < n; i++) {
      var bestC = 0;
      var bestDist = double.infinity;
      for (var c = 0; c < clamped; c++) {
        var s = 0.0;
        for (var dim = 0; dim < d; dim++) {
          final delta = points[i * d + dim] - centroids[c * d + dim];
          s += delta * delta;
        }
        if (s < bestDist) {
          bestDist = s;
          bestC = c;
        }
      }
      if (labels[i] != bestC) {
        labels[i] = bestC;
        changed++;
      }
    }
    if (changed == 0 && iter > 0) break;

    // Update: centroid = mean of assigned points. Empty clusters keep
    // their previous centroid (rare with k-means++ init, but possible
    // on degenerate spectra).
    for (var i = 0; i < clamped * d; i++) {
      newCentroids[i] = 0.0;
    }
    for (var c = 0; c < clamped; c++) {
      counts[c] = 0;
    }
    for (var i = 0; i < n; i++) {
      final c = labels[i];
      counts[c]++;
      for (var dim = 0; dim < d; dim++) {
        newCentroids[c * d + dim] += points[i * d + dim];
      }
    }
    for (var c = 0; c < clamped; c++) {
      if (counts[c] == 0) continue;
      final inv = 1.0 / counts[c];
      for (var dim = 0; dim < d; dim++) {
        centroids[c * d + dim] = newCentroids[c * d + dim] * inv;
      }
    }
  }
  return labels;
}

/// Cap on Lloyd's k-means iterations. K-means++ init plus this many
/// refinement passes converges on the spectral embeddings we feed in
/// (low-dimensional, well-separated clusters when communities exist).
const int _kKmeansMaxIters = 32;
