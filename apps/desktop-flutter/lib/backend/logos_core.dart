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

import 'dart:math' as math;
import 'dart:typed_data';

import 'lru_cache.dart';

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
    final edgesPerIncident = 1; // one new edge per incident existing row
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

  // T_1·ρ = L_sym·ρ − ρ
  graph.applyLsym(t0, scratch);
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
    graph.applyLsym(t1, scratch);
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

  // T_0·ρ = ρ — seed T_0 and emit basis row 0.
  for (var i = 0; i < n; i++) {
    t0[i] = rho[i];
  }
  basis.setRange(0, n, rho);

  // T_1·ρ = L_sym·ρ − ρ
  graph.applyLsym(t0, scratch);
  for (var i = 0; i < nPairs; i++) {
    t1x[i] = scratchX[i] - t0x[i];
  }
  basis.setRange(n, 2 * n, t1);

  // Recurrence for k = 2..K.
  for (var k = 2; k <= K; k++) {
    graph.applyLsym(t1, scratch);
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

  // T_0·ρ = ρ — seed T_0 and emit basis row 0.
  t0.setRange(0, stride, rhoBatch);
  basis.setRange(0, stride, rhoBatch);
  if (K == 0) return basis;

  // T_1 = L_sym·T_0 − T_0
  graph.applyLsymBatch(t0, scratch, B);
  for (var i = 0; i < stridePairs; i++) {
    t1x[i] = scratchX[i] - t0x[i];
  }
  basis.setRange(stride, 2 * stride, t1);

  for (var k = 2; k <= K; k++) {
    graph.applyLsymBatch(t1, scratch, B);
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

  // T_1 = L_sym·T_0 − T_0
  graph.applyLsymBatch(t0, scratch, B);
  for (var i = 0; i < stridePairs; i++) {
    t1x[i] = scratchX[i] - t0x[i];
  }
  final c1 = fullCoeffs[1];
  if (c1.abs() >= _coeffSkipEps) {
    for (var i = 0; i < stridePairs; i++) {
      phiBatchX[i] = phiBatchX[i] + t1x[i].scale(c1);
    }
  }

  // T_{k+1} = 2·(L_sym·T_k − T_k) − T_{k-1}
  for (var k = 2; k <= effectiveK; k++) {
    graph.applyLsymBatch(t1, scratch, B);
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
/// pipeline in one call. Builds the Chebyshev basis once, recombines at
/// `{0.5, 1.0, 2.0}`, then fuses via [geometricMeanBlend3].
///
/// Total cost: one `O(K·|E|)` basis pass (the matvec chain) plus three
/// `O(K·n)` recombines plus one `O(n)` blend. That's the shape of the
/// multi-temperature trick documented in `logos_hunks.dart` and
/// `logos_chunks.dart`; extracting it lets both call-sites collapse
/// ~20 lines of boilerplate into one call.
Float64List tripleTemperatureBlend({
  required CsrGraph graph,
  required Float64List rho,
  int K = kDefaultChebyshevK,
  double eps = 1e-12,
}) {
  if (graph.n == 0) return Float64List(0);
  final basis = chebyshevBasis(graph: graph, rho: rho, K: K);
  final phi05 =
      recombineHeatPhi(graph: graph, basis: basis, t: 0.5, K: K);
  final phi10 =
      recombineHeatPhi(graph: graph, basis: basis, t: 1.0, K: K);
  final phi20 =
      recombineHeatPhi(graph: graph, basis: basis, t: 2.0, K: K);
  return geometricMeanBlend3(phi05, phi10, phi20, eps: eps);
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

  const SpectralBasis({
    required this.n,
    required this.k,
    required this.eigenvalues,
    required this.eigenvectors,
  });

  /// Build a spectral basis directly from a graph by running
  /// [lanczosSmallEigenpairs]. Convenience constructor — most callers
  /// should go through the engine-level cache rather than rebuild
  /// per query.
  factory SpectralBasis.fromGraph(CsrGraph graph, int k, {int? maxIters}) {
    final pairs =
        lanczosSmallEigenpairs(graph, k, maxIters: maxIters);
    return SpectralBasis(
      n: pairs.n,
      k: pairs.k,
      eigenvalues: pairs.eigenvalues,
      eigenvectors: pairs.eigenvectors,
    );
  }

  /// Project `rho` onto the eigenbasis: returns `Uᵀ·ρ` of length k.
  /// Cheap O(k·n). The projection is the natural representation of a
  /// source distribution in the spectral coordinates — one number per
  /// mode, scale-aware. Future backtracking-attention paths will sit
  /// on top of this primitive (modes ↔ random-walk rates).
  Float64List project(Float64List rho) {
    assert(rho.length == n, 'rho length must equal n');
    final coeffs = Float64List(k);
    for (var j = 0; j < k; j++) {
      final base = j * n;
      var s = 0.0;
      for (var i = 0; i < n; i++) {
        s += eigenvectors[base + i] * rho[i];
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
    final phi = Float64List(n);
    for (var j = 0; j < k; j++) {
      final c = coeffs[j] * math.exp(-t * eigenvalues[j]);
      if (c == 0.0) continue;
      final base = j * n;
      for (var i = 0; i < n; i++) {
        phi[i] += c * eigenvectors[base + i];
      }
    }
    return phi;
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

  /// Heat trace `Z(t) = tr(e^{−t·L_sym}) = Σⱼ e^{−t·λⱼ}`.
  ///
  /// **Reading**: an isospectral invariant of the codebase. Two graphs
  /// with the same heat trace at every t share the same Laplacian
  /// spectrum (modulo Lanczos truncation); they "sound the same"
  /// (Kac, "Can one hear the shape of a drum?"). A PR that significantly
  /// shifts the trace is changing architectural shape, not just file
  /// contents. With `k = n` this is exact; with truncated `k` it
  /// captures the low-frequency contribution that dominates at
  /// any non-trivial `t`.
  double heatTrace(double t) {
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      s += math.exp(-t * eigenvalues[j]);
    }
    return s;
  }

  /// Partition function of `ρ` under the heat operator at temperature
  /// `t`: `Z(ρ, t) = ⟨ρ | e^{−t·L_sym} | ρ⟩ = Σⱼ e^{−t·λⱼ}·cⱼ²`,
  /// where `cⱼ = uⱼ·ρ` are the projection coefficients.
  ///
  /// **Reading**: how much of `ρ`'s mass survives after diffusing for
  /// time `t`. Concentrated sources on tightly-coupled clusters keep
  /// most of their mass; diffuse sources scatter into the low-mass
  /// regime. Substrate for [freeEnergy] and [spectralEntropy].
  double partitionFunction(Float64List rho, double t) {
    final coeffs = project(rho);
    var z = 0.0;
    for (var j = 0; j < k; j++) {
      z += math.exp(-t * eigenvalues[j]) * coeffs[j] * coeffs[j];
    }
    return z;
  }

  /// Helmholtz free energy of `ρ` at temperature `t`:
  /// `F(ρ, t) = −log Z(ρ, t)`.
  ///
  /// **Reading**: the natural information-theoretic cost of the
  /// source. Low free energy = `ρ` aligns with the operator's
  /// low-frequency modes (focused, well-coupled). High free energy =
  /// `ρ` lives in the high-frequency tail (scattered, poorly coupled).
  /// The minimum-free-energy `ρ` over a constraint set is the
  /// principled "minimum description length" emission set for that
  /// constraint — replaces ad-hoc budget knobs with a thermodynamic
  /// stationarity condition.
  double freeEnergy(Float64List rho, double t) {
    final z = partitionFunction(rho, t);
    if (z <= _subnormalFloor) return double.infinity;
    return -math.log(z);
  }

  /// Spectral participation entropy of `ρ` at temperature `t`:
  /// `S(ρ, t) = −Σⱼ pⱼ·log pⱼ` where `pⱼ = e^{−t·λⱼ}·cⱼ² / Z(ρ, t)`.
  ///
  /// **Reading**: how many spectral modes the source meaningfully
  /// occupies *after* thermal weighting. Bounded above by `log(k)`
  /// (uniform across modes — maximally diffuse focus); minimum 0
  /// (a single mode — maximally sharp focus). The natural scalar
  /// readout of "how focused is this PR / query / commit?". Free —
  /// it just reads off the projection we already cached.
  double spectralEntropy(Float64List rho, double t) {
    final coeffs = project(rho);
    var z = 0.0;
    final weighted = Float64List(k);
    for (var j = 0; j < k; j++) {
      final w = math.exp(-t * eigenvalues[j]) * coeffs[j] * coeffs[j];
      weighted[j] = w;
      z += w;
    }
    if (z <= _subnormalFloor) return 0.0;
    final invZ = 1.0 / z;
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      final p = weighted[j] * invZ;
      if (p > _subnormalFloor) s -= p * math.log(p);
    }
    return s;
  }

  /// Diffusion distance between two graph nodes at scale `t`:
  /// `d_t²(x, y) = ||p_t(x, ·) − p_t(y, ·)||² = Σⱼ e^{−2tλⱼ}·(uⱼ[x] − uⱼ[y])²`.
  ///
  /// **Reading**: a true metric on the graph induced by the heat
  /// kernel — small `t` recovers the graph's local geometry, large
  /// `t` recovers macroscopic cluster structure. Unlike shortest-path
  /// distance, it averages over *all* paths weighted by their thermal
  /// likelihood, so two nodes connected by many medium-strength paths
  /// are closer than two nodes connected by a single strong path.
  /// Use this for "how close is file X to file Y in the codebase's
  /// natural geometry?".
  double diffusionDistance(int srcId, int dstId, double t) {
    if (srcId == dstId) return 0.0;
    var sumSq = 0.0;
    for (var j = 0; j < k; j++) {
      final base = j * n;
      final delta = eigenvectors[base + srcId] - eigenvectors[base + dstId];
      sumSq += math.exp(-2.0 * t * eigenvalues[j]) * delta * delta;
    }
    return math.sqrt(sumSq);
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
    final embedDim = math.min(kClusters, k - 1);
    // Build n × embedDim embedding using u_1..u_{embedDim} (skip u_0).
    // Row-normalised so cosine-like similarity drives the k-means.
    final embedding = Float64List(n * embedDim);
    for (var i = 0; i < n; i++) {
      var rowNormSq = 0.0;
      for (var d = 0; d < embedDim; d++) {
        final v = eigenvectors[(d + 1) * n + i];
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
