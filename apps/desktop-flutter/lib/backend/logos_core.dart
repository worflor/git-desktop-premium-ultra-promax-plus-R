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
List<double> besselCoeffs(double t, int k) {
  final result = Float64List(k + 1);
  final tSafe = t.isNaN ? 0.0 : t.clamp(0.0, _maxSafeT);
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
int adaptiveK(List<double> coeffs, double eps) {
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
