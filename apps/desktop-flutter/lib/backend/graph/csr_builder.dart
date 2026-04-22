// csr_builder.dart — one-shot symmetric CSR graph builder.
//
// Produces a ready-to-use `CsrGraph` (the format consumed by the
// spectral engine: ricci, diffusion, operator, trajectory) from an
// edge list. Symmetric: every edge (u, v, w) is stored in both rows
// u and v. Duplicate edges are summed — callers that want max / avg
// combination should preprocess their input.
//
// This is the generic primitive. Every consumer that used to hand-roll
// CSR layout against a specific domain (file paths, hunks, tokens) can
// route through here instead. Keeping the construction in one place
// keeps fusion + normalization consistent across engines.

import 'dart:math' as math;
import 'dart:typed_data';

import '../logos_core.dart' show CsrGraph;

/// One undirected edge. Order of [u] / [v] doesn't matter; the builder
/// stores both directions. [weight] must be positive and finite.
class CsrEdge {
  const CsrEdge(this.u, this.v, this.weight);
  final int u;
  final int v;
  final double weight;
}

/// Build a symmetric CSR graph on [n] nodes from [edges].
///
/// - Self-loops (`u == v`) are silently dropped; they don't add graph
///   structure and would bias the degree normalisation.
/// - Duplicate edges (same `{u, v}` pair submitted multiple times) are
///   summed. Pre-deduplicate upstream if that's not what you want.
/// - Zero- / negative- / non-finite-weight edges are dropped.
/// - Isolated nodes (no edges) remain as degree-zero rows; the ricci
///   code handles them correctly.
///
/// The returned [CsrGraph] has:
///   * `rawWeights` — parallel to `values`, holding `W[i,j]` verbatim.
///   * `values` — pre-fused normalised weights `D^{-1/2}·W·D^{-1/2}`
///     so the graph supports `RicciField.sinkhorn`, diffusion, and
///     the operator algebra without any further preprocessing.
///   * `degreeInvSqrt` — per-node `1/√deg` for rank-1 updates.
///
/// Cost: O(m log m) to sort the per-row column indices + O(m) to fuse.
/// Memory: ~16 bytes per directed edge (two per undirected) — tight.
CsrGraph buildSymmetricCsrGraph({
  required int n,
  required Iterable<CsrEdge> edges,
}) {
  if (n < 0) {
    throw ArgumentError('n must be non-negative, got $n');
  }

  // Pass 1: accumulate edges per row. Use nested growable lists so we
  // don't pre-allocate O(n^2). Small-index trees + a HashMap tiebreak
  // via `indexOf` would hurt on dense graphs; flat list-of-lists with
  // a final sort-and-dedup pass is simpler and fast enough at the
  // graph sizes we deal with (tokens ≤ ~20k, files ≤ ~5k).
  final rowTargets = List<List<int>>.generate(n, (_) => <int>[], growable: false);
  final rowWeights = List<List<double>>.generate(n, (_) => <double>[], growable: false);

  for (final e in edges) {
    final u = e.u;
    final v = e.v;
    final w = e.weight;
    if (u == v) continue;
    if (u < 0 || v < 0 || u >= n || v >= n) {
      throw RangeError('edge ($u, $v) out of range [0, $n)');
    }
    if (!w.isFinite || w <= 0.0) continue;
    rowTargets[u].add(v);
    rowWeights[u].add(w);
    rowTargets[v].add(u);
    rowWeights[v].add(w);
  }

  // Pass 2: per-row sort + dedup. Sort by target index so the row
  // slice is monotonic (binary search + deterministic iteration), and
  // combine any duplicate edges by summing weights.
  final indptr = Int32List(n + 1);
  final degreeRaw = Float64List(n);

  // Pre-count final row sizes so we can size indices / values exactly.
  var total = 0;
  for (var i = 0; i < n; i++) {
    final tgts = rowTargets[i];
    if (tgts.isEmpty) {
      indptr[i + 1] = total;
      continue;
    }
    // Sort in-place by target id using parallel-array permutation.
    _sortParallel(tgts, rowWeights[i]);
    // Dedup consecutive duplicates, summing weights.
    var write = 0;
    for (var read = 0; read < tgts.length; read++) {
      if (write > 0 && tgts[read] == tgts[write - 1]) {
        rowWeights[i][write - 1] += rowWeights[i][read];
      } else {
        tgts[write] = tgts[read];
        rowWeights[i][write] = rowWeights[i][read];
        write++;
      }
    }
    if (write < tgts.length) {
      tgts.length = write;
      rowWeights[i].length = write;
    }
    total += write;
    indptr[i + 1] = total;
  }

  // Pass 3: materialise flat indices / raw weights.
  final indices = Int32List(total);
  final rawWeights = Float64List(total);
  for (var i = 0; i < n; i++) {
    final start = indptr[i];
    final tgts = rowTargets[i];
    final wts = rowWeights[i];
    var acc = 0.0;
    for (var k = 0; k < tgts.length; k++) {
      indices[start + k] = tgts[k];
      rawWeights[start + k] = wts[k];
      acc += wts[k];
    }
    degreeRaw[i] = acc;
  }

  // Pass 4: fuse normalisation `D^{-1/2}·W·D^{-1/2}`.
  final degreeInvSqrt = Float64List(n);
  for (var i = 0; i < n; i++) {
    final d = degreeRaw[i];
    degreeInvSqrt[i] = d > 0 ? 1.0 / _sqrt(d) : 0.0;
  }
  final values = Float64List(total);
  for (var i = 0; i < n; i++) {
    final di = degreeInvSqrt[i];
    if (di == 0.0) continue;
    for (var p = indptr[i]; p < indptr[i + 1]; p++) {
      final j = indices[p];
      final dj = degreeInvSqrt[j];
      values[p] = di * rawWeights[p] * dj;
    }
  }

  return CsrGraph(
    n: n,
    indptr: indptr,
    indices: indices,
    values: values,
    degreeInvSqrt: degreeInvSqrt,
    rawWeights: rawWeights,
  );
}

/// Sort [keys] ascending, permuting [values] in lockstep. In-place.
/// Uses a key-carrying index sort since Dart doesn't give us a
/// two-array parallel sort out of the box.
void _sortParallel(List<int> keys, List<double> values) {
  final n = keys.length;
  if (n < 2) return;
  final order = List<int>.generate(n, (i) => i, growable: false);
  order.sort((a, b) => keys[a].compareTo(keys[b]));
  final keysCopy = List<int>.from(keys);
  final valuesCopy = List<double>.from(values);
  for (var i = 0; i < n; i++) {
    keys[i] = keysCopy[order[i]];
    values[i] = valuesCopy[order[i]];
  }
}

double _sqrt(double x) => x <= 0.0 ? 0.0 : math.sqrt(x);
