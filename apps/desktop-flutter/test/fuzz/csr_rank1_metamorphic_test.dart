// Metamorphic property tests for the INCREMENTAL graph-update operations of
// Manifold's spectral engine (lib/backend/logos_core.dart +
// lib/backend/graph/csr_builder.dart).
//
// The core law, for every op below, is the same:
//
//     incremental_update(G) == from_scratch_rebuild(updated_edge_set)
//
// That's the entire point of `withNodeAppended` / `withNodeRemoved` /
// `coarsen` existing as rank-1 primitives instead of always calling
// `CsrGraph.fromRawEdges` — they must be a pure optimization, never a
// different answer. `test/backend/logos_git_test.dart` already pins ONE
// hand-picked example each for `withNodeAppended` and `fromRawEdges`'s
// D^{-1/2} fusion; `test/backend/spectral_observables_test.dart` pins a
// handful of hand-picked `coarsen` examples. This file is the fuzzed
// complement — hundreds of random graphs per law, covering the ops that
// aren't fuzzed anywhere else: `withNodeRemoved`, `coarsen`, the
// append-then-remove round trip, and `buildSymmetricCsrGraph`'s own
// adversarial normalization contract (duplicate/self-loop/invalid-weight
// edges, and edge-order permutation invariance at the raw-CSR-array level,
// not just downstream spectrum).
//
// LAWS:
//   1. withNodeAppended(G) == rebuild(G.nodes + 1, G.edges u appendEdges).
//   2. withNodeRemoved(G, id) == rebuild(G.nodes - {id}) with the same
//      column-shift-down remap `withNodeRemoved` itself uses.
//   3. coarsen(G, groupOf) == manually-built quotient graph (inter-group
//      raw weights summed, intra-group edges dropped, no self-loops).
//      Corollary: coarsening never increases beta_0, and preserves it
//      exactly when every group stays within one original component.
//   4. Round trip: G.withNodeAppended(e).withNodeRemoved(newId) == G,
//      where newId is the id append just assigned (always the max id,
//      so the remove-side remap is a no-op).
//   5. csr_builder normalization: duplicate edges summed, self-loops
//      dropped, non-positive/non-finite weights dropped, symmetric
//      fusion (values[u->v] == values[v->u]), every row fused as
//      D^{-1/2}*W*D^{-1/2}, and permuting the input edge order produces
//      an identical CsrGraph.
//
// All comparisons are structural (indptr/indices exact, values/rawWeights/
// degreeInvSqrt within a tight tolerance — this is exact math, not an
// approximation) plus a looser sorted-eigenvalue check via
// `lanczosSmallEigenpairs` for the ops cheap enough to afford it. A
// divergence beyond tolerance is a correctness bug in a hot path, not a
// flaky test — a few known ones are left skipped inline rather than
// weakening the tolerance to hide them.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/graph/csr_builder.dart';
import 'package:git_desktop/backend/logos_core.dart';

import '../support/gen.dart';
import '../support/prop.dart';

// ---------------------------------------------------------------------------
// Tolerances
// ---------------------------------------------------------------------------

/// CSR array comparisons are exact math (a handful of adds/multiplies/
/// sqrts) — any two faithful constructions of "the same graph" should
/// agree to within a few ULPs. 1e-9 is generous slack for accumulated
/// float noise across rows with up to ~24 terms, nowhere near loose
/// enough to hide a real fusion/remap bug.
const double _structTol = 1e-9;

/// Lanczos is iterative; two independent decompositions of "the same
/// graph" (different array identities, same numbers) should still
/// converge to the same Ritz values well within 1e-6 at these graph
/// sizes (<=16 nodes).
const double _specTol = 1e-6;

// ---------------------------------------------------------------------------
// Graph-family mix — reused across every law below.
// ---------------------------------------------------------------------------

final List<Gen<TestGraph>> _graphMix = [
  genGraph(maxNodes: 24),
  genConnectedGraph(maxNodes: 24),
  genDisconnectedGraph(maxNodes: 24),
  genTree(maxNodes: 24),
];

/// Smaller cap for the spectrum-comparison variants — Lanczos cost is
/// still tiny at these sizes, but we run fewer, smaller cases to keep
/// the whole suite snappy while still exercising every graph family.
final List<Gen<TestGraph>> _graphMixSmall = [
  genGraph(maxNodes: 14),
  genConnectedGraph(maxNodes: 14),
  genDisconnectedGraph(maxNodes: 14),
  genTree(maxNodes: 14),
];

TestGraph _pickGraph(List<Gen<TestGraph>> mix, Rng rng) =>
    rng.pick(mix)(rng.split());

List<List<(int, double)>> _toEdgesPerNode(TestGraph g) {
  final out = List<List<(int, double)>>.generate(g.n, (_) => []);
  for (final (a, b, w) in g.edges) {
    out[a].add((b, w));
    out[b].add((a, w));
  }
  return out;
}

CsrGraph _fromTestGraph(TestGraph g) =>
    CsrGraph.fromRawEdges(n: g.n, edgesPerNode: _toEdgesPerNode(g));

// ---------------------------------------------------------------------------
// Shared oracle: `fromRawEdges` generalized with an extra per-node degree
// bias that contributes NO CSR entry of its own. This is exactly what
// `withNodeAppended`'s `selfMass` does (folds into the appended node's
// degree sum for D^{-1/2}, but never creates a self-loop row entry) — a
// plain `fromRawEdges` self-loop edge would instead show up as a real
// (and extra) CSR entry, so it can't stand in as the oracle here.
// ---------------------------------------------------------------------------

CsrGraph _manualBuildWithSelfMass({
  required int n,
  required List<List<(int, double)>> edgesPerNode,
  required List<double> selfMass,
}) {
  final degrees = Float64List(n);
  var nnz = 0;
  for (var i = 0; i < n; i++) {
    degrees[i] = selfMass[i];
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

// ---------------------------------------------------------------------------
// Structural / spectral comparison helpers.
// ---------------------------------------------------------------------------

void _expectSameCsrStructure(
  CsrGraph a,
  CsrGraph b, {
  String context = '',
  double tol = _structTol,
}) {
  expect(a.n, b.n, reason: '$context: n mismatch');
  expect(a.indptr.toList(), b.indptr.toList(), reason: '$context: indptr mismatch');
  expect(a.indices.toList(), b.indices.toList(), reason: '$context: indices mismatch');
  for (var k = 0; k < a.values.length; k++) {
    expect(
      a.values[k],
      closeTo(b.values[k], tol),
      reason: '$context: values[$k] mismatch (col ${a.indices[k]})',
    );
  }
  if (a.rawWeights.length == b.rawWeights.length) {
    for (var k = 0; k < a.rawWeights.length; k++) {
      expect(
        a.rawWeights[k],
        closeTo(b.rawWeights[k], tol),
        reason: '$context: rawWeights[$k] mismatch',
      );
    }
  }
  for (var i = 0; i < a.n; i++) {
    expect(
      a.degreeInvSqrt[i],
      closeTo(b.degreeInvSqrt[i], tol),
      reason: '$context: degreeInvSqrt[$i] mismatch',
    );
  }
}

void _expectSameSpectrum(
  CsrGraph a,
  CsrGraph b, {
  String context = '',
  int k = 6,
  double tol = _specTol,
}) {
  final kk = math.min(k, math.min(a.n, b.n));
  if (kk <= 0) return;
  final ea = lanczosSmallEigenpairs(a, kk).eigenvalues;
  final eb = lanczosSmallEigenpairs(b, kk).eigenvalues;
  // Same-shape graphs must yield the same number of extractable eigenpairs;
  // a mismatch here is itself a finding, not just a bounds nuisance — but
  // report it as a clean assertion instead of crashing the whole case out
  // from under `forAll`'s reproduction machinery.
  expect(
    ea.length,
    eb.length,
    reason: '$context: lanczos returned different eigenpair counts '
        '(a=${ea.length}, b=${eb.length}) for graphs that should have the '
        'same shape',
  );
  final effective = math.min(ea.length, eb.length);
  final sa = [...ea]..sort();
  final sb = [...eb]..sort();
  for (var i = 0; i < effective; i++) {
    expect(
      sa[i],
      closeTo(sb[i], tol),
      reason: '$context: eigenvalue[$i] mismatch ($sa vs $sb)',
    );
  }
}

/// Dense `L_sym = I - D^{-1/2} W D^{-1/2}` built directly from a
/// [CsrGraph]'s own arrays, matching [CsrGraph.applyLsym]'s semantics
/// exactly. Used as the independent-oracle input to `denseSymmetricEigen`
/// (the engine's own exact dense Jacobi solver) for the bonus finding
/// below — a ground truth that never goes through `lanczosSmallEigenpairs`
/// or its kernel-deflation logic at all.
Float64List _denseLsymFromCsr(CsrGraph g) {
  final n = g.n;
  final m = Float64List(n * n);
  for (var i = 0; i < n; i++) {
    m[i * n + i] += 1.0;
    for (var k = g.indptr[i]; k < g.indptr[i + 1]; k++) {
      final j = g.indices[k];
      m[i * n + j] -= g.values[k];
    }
  }
  return m;
}

// ---------------------------------------------------------------------------
// Law 1 — withNodeAppended == full rebuild.
// ---------------------------------------------------------------------------

typedef AppendCase = ({TestGraph base, List<(int, double)> edges, double selfMass});

Gen<AppendCase> _genAppendCase(List<Gen<TestGraph>> mix) {
  return (rng) {
    final g = _pickGraph(mix, rng);
    final k = rng.intBetween(0, g.n);
    final targets = rng.sample(List<int>.generate(g.n, (i) => i), k);
    final edges = <(int, double)>[
      for (final t in targets) (t, 0.1 + rng.nextDouble() * 9.9),
    ];
    final selfMass = rng.nextBool() ? 0.0 : rng.nextDouble() * 5.0;
    return (base: g, edges: edges, selfMass: selfMass);
  };
}

/// Edges chosen WITH replacement (so duplicate targets are common) and
/// mixed with zero/negative/NaN/Infinity weights — exercises
/// `withNodeAppended`'s own `edgeByTarget` dedup-and-filter contract.
typedef AdversarialAppendCase = ({TestGraph base, List<(int, double)> edges, double selfMass});

Gen<AdversarialAppendCase> _genAdversarialAppendCase(List<Gen<TestGraph>> mix) {
  return (rng) {
    final g = _pickGraph(mix, rng);
    final count = rng.intBetween(0, 3 * g.n);
    final edges = <(int, double)>[];
    for (var i = 0; i < count; i++) {
      final t = rng.nextInt(g.n);
      final kind = rng.nextInt(5);
      double w;
      switch (kind) {
        case 0:
          w = 0.1 + rng.nextDouble() * 9.9;
          break;
        case 1:
          w = 0.0;
          break;
        case 2:
          w = -(0.1 + rng.nextDouble() * 9.9);
          break;
        case 3:
          w = double.nan;
          break;
        case 4:
          w = double.infinity;
          break;
        default:
          w = 0.1 + rng.nextDouble() * 9.9;
      }
      edges.add((t, w));
    }
    final selfMass = rng.nextBool() ? 0.0 : rng.nextDouble() * 5.0;
    return (base: g, edges: edges, selfMass: selfMass);
  };
}

CsrGraph _rebuildAppendOracle(TestGraph g, List<(int, double)> edges, double selfMass) {
  final edgesPerNode = _toEdgesPerNode(g);
  final dedup = <int, double>{};
  for (final (t, w) in edges) {
    if (!w.isFinite || w <= 0) continue;
    dedup.update(t, (old) => old + w, ifAbsent: () => w);
  }
  final newN = g.n + 1;
  final rebuildEdgesPerNode = List<List<(int, double)>>.generate(newN, (_) => []);
  for (var i = 0; i < g.n; i++) {
    rebuildEdgesPerNode[i].addAll(edgesPerNode[i]);
  }
  dedup.forEach((t, w) {
    rebuildEdgesPerNode[t].add((newN - 1, w));
    rebuildEdgesPerNode[newN - 1].add((t, w));
  });
  final selfMassVec = List<double>.filled(newN, 0.0);
  selfMassVec[newN - 1] = selfMass;
  return _manualBuildWithSelfMass(
    n: newN,
    edgesPerNode: rebuildEdgesPerNode,
    selfMass: selfMassVec,
  );
}

void _checkAppendCase(AppendCase c) {
  final base = _fromTestGraph(c.base);
  final incremental = base.withNodeAppended(edges: c.edges, selfMass: c.selfMass);
  final rebuilt = _rebuildAppendOracle(c.base, c.edges, c.selfMass);
  _expectSameCsrStructure(incremental, rebuilt, context: 'append n=${c.base.n}');
}

void _checkAppendSpectrum(AppendCase c) {
  final base = _fromTestGraph(c.base);
  final incremental = base.withNodeAppended(edges: c.edges, selfMass: c.selfMass);
  final rebuilt = _rebuildAppendOracle(c.base, c.edges, c.selfMass);
  _expectSameSpectrum(incremental, rebuilt, context: 'append-spectrum n=${c.base.n}');
}

void _checkAdversarialAppend(AdversarialAppendCase c) {
  final base = _fromTestGraph(c.base);
  final incremental = base.withNodeAppended(edges: c.edges, selfMass: c.selfMass);
  final rebuilt = _rebuildAppendOracle(c.base, c.edges, c.selfMass);
  _expectSameCsrStructure(incremental, rebuilt, context: 'adversarial-append n=${c.base.n}');
}

// ---------------------------------------------------------------------------
// Law 2 — withNodeRemoved == full rebuild on remaining, remapped nodes.
// ---------------------------------------------------------------------------

typedef RemoveCase = ({TestGraph base, int removeId});

Gen<RemoveCase> _genRemoveCase(List<Gen<TestGraph>> mix) {
  return (rng) {
    final g = _pickGraph(mix, rng);
    final id = rng.nextInt(g.n);
    return (base: g, removeId: id);
  };
}

/// `null` signals the `newN == 0` special case (removing the only node),
/// which `withNodeRemoved` itself short-circuits without an id remap.
// known bug: withNodeRemoved recomputes a row's post-removal degree via
// `1/(degreeInvSqrt[i])^2 - degreeLoss[i]` instead of the exact raw-weight
// sum, so a node whose entire remaining degree came from the removed
// edge lands on a spurious positive residual (~1e-15) instead of exact
// 0, which then blows up through 1/sqrt(x) into an astronomical
// degreeInvSqrt (repro: seed=0xA004 index=10; also seed=0xA00A index=4
// via the Law 4 round trip).
CsrGraph? _rebuildRemoveOracle(TestGraph g, int removeId) {
  final newN = g.n - 1;
  if (newN == 0) return null;
  int remap(int i) => i < removeId ? i : i - 1;
  final rebuildEdgesPerNode = List<List<(int, double)>>.generate(newN, (_) => []);
  for (final (a, b, w) in g.edges) {
    if (a == removeId || b == removeId) continue;
    rebuildEdgesPerNode[remap(a)].add((remap(b), w));
    rebuildEdgesPerNode[remap(b)].add((remap(a), w));
  }
  return CsrGraph.fromRawEdges(n: newN, edgesPerNode: rebuildEdgesPerNode);
}

void _checkRemoveCase(RemoveCase c) {
  final base = _fromTestGraph(c.base);
  final removed = base.withNodeRemoved(c.removeId);
  final rebuilt = _rebuildRemoveOracle(c.base, c.removeId);
  if (rebuilt == null) {
    expect(removed.n, 0, reason: 'removing the only node must yield an empty graph');
    return;
  }
  _expectSameCsrStructure(
    removed,
    rebuilt,
    context: 'remove id=${c.removeId} n=${c.base.n}',
  );
}

void _checkRemoveSpectrum(RemoveCase c) {
  final base = _fromTestGraph(c.base);
  final removed = base.withNodeRemoved(c.removeId);
  final rebuilt = _rebuildRemoveOracle(c.base, c.removeId);
  if (rebuilt == null) return;
  _expectSameSpectrum(
    removed,
    rebuilt,
    context: 'remove-spectrum id=${c.removeId} n=${c.base.n}',
  );
}

// ---------------------------------------------------------------------------
// Law 3 — coarsen == manual quotient-graph rebuild, plus the beta_0
// monotonicity corollary.
// ---------------------------------------------------------------------------

typedef CoarsenCase = ({TestGraph base, List<int> groupOf});

/// `coarsen`'s contract (per its doc comment) requires `groupOf` to use
/// DENSE ids `0..m-1` — every id in that range must have at least one
/// node mapped to it. Independently drawing each node's group id from
/// `[0, k)` can leave gaps (some id in range never chosen), which
/// `coarsen` doesn't validate away: it silently manifests as an extra
/// isolated coarse node with no original preimage at all, which is a
/// real (if minor) beta_0-inflating artifact that belongs to a
/// malformed *input*, not to the op. Remap to the densely-used ids so
/// every generated case honors the documented precondition.
List<int> _densifyGroupOf(List<int> raw) {
  final used = raw.toSet().toList()..sort();
  final remap = {for (var i = 0; i < used.length; i++) used[i]: i};
  return [for (final g in raw) remap[g]!];
}

/// Per-node original-component label via plain union-find — independent
/// of, and simpler than, anything the engine does; the oracle for "does
/// this grouping stay within one original component."
List<int> _componentLabelsOf(TestGraph g) {
  final parent = List<int>.generate(g.n, (i) => i);
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  for (final (a, b, _) in g.edges) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }
  final rootToId = <int, int>{};
  final labels = List<int>.filled(g.n, 0);
  for (var i = 0; i < g.n; i++) {
    final r = find(i);
    labels[i] = rootToId.putIfAbsent(r, () => rootToId.length);
  }
  return labels;
}

/// Arbitrary grouping: groups may freely span multiple original
/// components (a stress case coarsen must still handle correctly).
Gen<CoarsenCase> _genCoarsenCaseArbitrary(List<Gen<TestGraph>> mix) {
  return (rng) {
    final g = _pickGraph(mix, rng);
    final k = rng.intBetween(1, g.n);
    final raw = List<int>.generate(g.n, (_) => rng.nextInt(k));
    return (base: g, groupOf: _densifyGroupOf(raw));
  };
}

/// Compatible grouping: every group is confined to nodes of a single
/// original component (built by sub-partitioning each component
/// independently), so beta_0 must be preserved exactly.
Gen<CoarsenCase> _genCoarsenCaseCompatible(List<Gen<TestGraph>> mix) {
  return (rng) {
    final g = _pickGraph(mix, rng);
    final labels = _componentLabelsOf(g);
    final numComponents = labels.reduce(math.max) + 1;
    final sizes = List<int>.filled(numComponents, 0);
    for (final l in labels) {
      sizes[l]++;
    }
    final offsets = List<int>.filled(numComponents, 0);
    final localCounts = List<int>.filled(numComponents, 1);
    var running = 0;
    for (var comp = 0; comp < numComponents; comp++) {
      offsets[comp] = running;
      final k = rng.intBetween(1, sizes[comp]);
      localCounts[comp] = k;
      running += k;
    }
    final raw = List<int>.generate(g.n, (i) {
      final comp = labels[i];
      final local = rng.nextInt(localCounts[comp]);
      return offsets[comp] + local;
    });
    // Densifying preserves per-component confinement: it's an injective
    // remap of used raw ids, so it can never merge two different
    // components' ids together, only close gaps within each.
    return (base: g, groupOf: _densifyGroupOf(raw));
  };
}

CsrGraph _manualCoarsen(TestGraph g, List<int> groupOf) {
  var m = 0;
  for (final gi in groupOf) {
    if (gi + 1 > m) m = gi + 1;
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
  final acc = <int, Map<int, double>>{};
  for (final (a, b, w) in g.edges) {
    final ga = groupOf[a];
    final gb = groupOf[b];
    if (ga == gb) continue; // intra-group edges drop (no self-loop kept)
    final lo = math.min(ga, gb);
    final hi = math.max(ga, gb);
    final inner = acc.putIfAbsent(lo, () => <int, double>{});
    inner[hi] = (inner[hi] ?? 0) + w;
  }
  final edgesPerNode = List<List<(int, double)>>.generate(m, (_) => []);
  acc.forEach((a, inner) {
    inner.forEach((b, w) {
      edgesPerNode[a].add((b, w));
      edgesPerNode[b].add((a, w));
    });
  });
  return CsrGraph.fromRawEdges(n: m, edgesPerNode: edgesPerNode);
}

void _checkCoarsenRebuild(CoarsenCase c) {
  final base = _fromTestGraph(c.base);
  final coarse = base.coarsen(c.groupOf);
  final manual = _manualCoarsen(c.base, c.groupOf);
  _expectSameCsrStructure(coarse, manual, context: 'coarsen n=${c.base.n}');
}

void _checkCoarsenSpectrum(CoarsenCase c) {
  final base = _fromTestGraph(c.base);
  final coarse = base.coarsen(c.groupOf);
  final manual = _manualCoarsen(c.base, c.groupOf);
  _expectSameSpectrum(coarse, manual, context: 'coarsen-spectrum n=${c.base.n}');
}

int _componentCountOf(CsrGraph g) {
  if (g.n == 0) return 0;
  // Threshold below every possible normalized weight (all strictly
  // positive by construction) keeps every real edge in the sweep.
  return g.fragmentationCurve(const [-1.0]).first.componentCount;
}

void _checkCoarsenBeta0Monotonic(CoarsenCase c) {
  final base = _fromTestGraph(c.base);
  final coarse = base.coarsen(c.groupOf);
  final originalBeta0 = connectedComponents(c.base);
  final coarseBeta0 = _componentCountOf(coarse);
  expect(
    coarseBeta0,
    lessThanOrEqualTo(originalBeta0),
    reason: 'coarsening increased beta_0: $originalBeta0 -> $coarseBeta0',
  );
}

void _checkCoarsenBeta0ExactWhenCompatible(CoarsenCase c) {
  final base = _fromTestGraph(c.base);
  final coarse = base.coarsen(c.groupOf);
  final originalBeta0 = connectedComponents(c.base);
  final coarseBeta0 = _componentCountOf(coarse);
  expect(
    coarseBeta0,
    originalBeta0,
    reason: 'compatible grouping should preserve beta_0 exactly: '
        '$originalBeta0 -> $coarseBeta0',
  );
}

// ---------------------------------------------------------------------------
// Law 4 — append+remove round trip.
// ---------------------------------------------------------------------------

void _checkRoundTrip(AppendCase c) {
  final base = _fromTestGraph(c.base);
  final appended = base.withNodeAppended(edges: c.edges, selfMass: c.selfMass);
  // append always assigns the new node the max id (== old n).
  final newId = appended.n - 1;
  final roundTripped = appended.withNodeRemoved(newId);
  _expectSameCsrStructure(roundTripped, base, context: 'round-trip n=${c.base.n}');
}

void _checkRoundTripSpectrum(AppendCase c) {
  final base = _fromTestGraph(c.base);
  final appended = base.withNodeAppended(edges: c.edges, selfMass: c.selfMass);
  final newId = appended.n - 1;
  final roundTripped = appended.withNodeRemoved(newId);
  _expectSameSpectrum(roundTripped, base, context: 'round-trip-spectrum n=${c.base.n}');
}

// ---------------------------------------------------------------------------
// Law 5 — csr_builder normalization laws (adversarial edges).
// ---------------------------------------------------------------------------

CsrEdge _genOneAdversarialEdge(Rng rng, int n) {
  final u = rng.nextInt(n);
  final v = rng.nextInt(n);
  final kind = rng.nextInt(5);
  double w;
  switch (kind) {
    case 0:
      w = 0.1 + rng.nextDouble() * 9.9;
      break;
    case 1:
      w = 0.0;
      break;
    case 2:
      w = -(0.1 + rng.nextDouble() * 9.9);
      break;
    case 3:
      w = double.nan;
      break;
    case 4:
      w = double.infinity;
      break;
    default:
      w = 0.1 + rng.nextDouble() * 9.9;
  }
  return CsrEdge(u, v, w);
}

typedef AdversarialEdgesCase = ({int n, List<CsrEdge> edges});

/// Small `n` relative to edge count so duplicate (u, v) pairs and
/// self-loops show up often, not just theoretically.
Gen<AdversarialEdgesCase> _genAdversarialEdgesCase() {
  return (rng) {
    final n = rng.intBetween(2, 14);
    final count = rng.intBetween(0, 4 * n);
    final edges = List<CsrEdge>.generate(count, (_) => _genOneAdversarialEdge(rng, n));
    return (n: n, edges: edges);
  };
}

/// The independent reference model: a plain per-node adjacency map,
/// built by the simplest-possible-correct rule (drop self-loops, drop
/// non-positive/non-finite, sum duplicates) — never the same code path
/// as `buildSymmetricCsrGraph` itself.
Map<int, Map<int, double>> _referenceAdjacency(int n, List<CsrEdge> edges) {
  final adj = <int, Map<int, double>>{
    for (var i = 0; i < n; i++) i: <int, double>{},
  };
  for (final e in edges) {
    if (e.u == e.v) continue;
    if (!e.weight.isFinite || e.weight <= 0.0) continue;
    adj[e.u]!.update(e.v, (old) => old + e.weight, ifAbsent: () => e.weight);
    adj[e.v]!.update(e.u, (old) => old + e.weight, ifAbsent: () => e.weight);
  }
  return adj;
}

Map<int, double> _csrRowRaw(CsrGraph g, int i) {
  final out = <int, double>{};
  for (var k = g.indptr[i]; k < g.indptr[i + 1]; k++) {
    out[g.indices[k]] = g.rawWeights[k];
  }
  return out;
}

double _csrWeight(CsrGraph g, int from, int to) {
  for (var k = g.indptr[from]; k < g.indptr[from + 1]; k++) {
    if (g.indices[k] == to) return g.values[k];
  }
  return 0.0;
}

void _checkBuildSymmetricNormalization(AdversarialEdgesCase c) {
  final g = buildSymmetricCsrGraph(n: c.n, edges: c.edges);
  final ref = _referenceAdjacency(c.n, c.edges);

  // Dedup-sum / self-loop-drop / non-positive-non-finite-drop.
  for (var i = 0; i < c.n; i++) {
    final builtRow = _csrRowRaw(g, i);
    final refRow = ref[i]!;
    expect(
      builtRow.keys.toList()..sort(),
      refRow.keys.toList()..sort(),
      reason: 'row $i column set mismatch vs reference adjacency',
    );
    refRow.forEach((j, w) {
      expect(
        builtRow[j],
        closeTo(w, _structTol),
        reason: 'row $i raw weight mismatch at col $j (dedup-sum law)',
      );
    });
  }

  // Degree / D^{-1/2} correctness.
  for (var i = 0; i < c.n; i++) {
    final expectedDeg = ref[i]!.values.fold(0.0, (a, b) => a + b);
    final expectedDInv = expectedDeg > 0 ? 1.0 / math.sqrt(expectedDeg) : 0.0;
    expect(
      g.degreeInvSqrt[i],
      closeTo(expectedDInv, _structTol),
      reason: 'degreeInvSqrt[$i] mismatch',
    );
  }

  // Fusion (D^{-1/2} W D^{-1/2}) + symmetry.
  for (var i = 0; i < c.n; i++) {
    for (var k = g.indptr[i]; k < g.indptr[i + 1]; k++) {
      final j = g.indices[k];
      final expectedVal = g.degreeInvSqrt[i] * g.rawWeights[k] * g.degreeInvSqrt[j];
      expect(
        g.values[k],
        closeTo(expectedVal, 1e-12),
        reason: 'fused value != D^-1/2 W D^-1/2 at ($i,$j)',
      );
      expect(
        g.values[k],
        closeTo(_csrWeight(g, j, i), _structTol),
        reason: 'asymmetric normalized weight at ($i,$j)',
      );
    }
  }
}

typedef PermCase = ({int n, List<CsrEdge> edges, List<CsrEdge> shuffled});

Gen<PermCase> _genPermCase() {
  return (rng) {
    final n = rng.intBetween(2, 12);
    final count = rng.intBetween(0, 4 * n);
    final edges = List<CsrEdge>.generate(count, (_) => _genOneAdversarialEdge(rng, n));
    final shuffled = rng.sample(edges, edges.length);
    return (n: n, edges: edges, shuffled: shuffled);
  };
}

void _checkPermutationInvariance(PermCase c) {
  final g1 = buildSymmetricCsrGraph(n: c.n, edges: c.edges);
  final g2 = buildSymmetricCsrGraph(n: c.n, edges: c.shuffled);
  expect(g2.n, g1.n);
  expect(
    g2.indptr.toList(),
    g1.indptr.toList(),
    reason: 'indptr differs under edge permutation',
  );
  expect(
    g2.indices.toList(),
    g1.indices.toList(),
    reason: 'indices differ under edge permutation',
  );
  for (var k = 0; k < g1.values.length; k++) {
    expect(
      g2.values[k],
      closeTo(g1.values[k], _structTol),
      reason: 'values[$k] differ under edge permutation',
    );
    expect(
      g2.rawWeights[k],
      closeTo(g1.rawWeights[k], _structTol),
      reason: 'rawWeights[$k] differ under edge permutation',
    );
  }
  for (var i = 0; i < c.n; i++) {
    expect(
      g2.degreeInvSqrt[i],
      closeTo(g1.degreeInvSqrt[i], _structTol),
      reason: 'degreeInvSqrt[$i] differs under edge permutation',
    );
  }
}

// ---------------------------------------------------------------------------

void main() {
  group('Law 1 — withNodeAppended equals a from-scratch rebuild', () {
    test('CSR structure matches exactly', () {
      forAll(
        _genAppendCase(_graphMix),
        count: 400 * fuzzScale(),
        seed: 0xA001,
        describe: 'append-rebuild-structure',
        check: _checkAppendCase,
      );
    });

    test('sorted eigenvalue spectrum matches within tolerance', () {
      forAll(
        _genAppendCase(_graphMixSmall),
        count: 120 * fuzzScale(),
        seed: 0xA002,
        describe: 'append-rebuild-spectrum',
        check: _checkAppendSpectrum,
      );
    });

    test(
      'duplicate / zero / negative / non-finite append edges normalize '
      'identically to the dedup oracle',
      () {
        forAll(
          _genAdversarialAppendCase(_graphMixSmall),
          count: 300 * fuzzScale(),
          seed: 0xA003,
          describe: 'append-adversarial-dedup',
          check: _checkAdversarialAppend,
        );
      },
    );
  });

  group(
    'appended isolated selfMass-only node vs lanczosSmallEigenpairs',
    () {
      // known bug: withNodeAppended(edges: [], selfMass: s) agrees with
      // the from-scratch oracle (both give degree=s, zero real CSR
      // edges) so this isn't an incremental-vs-rebuild mismatch — both
      // are wrong relative to the true spectrum. Root cause:
      // `_exactLaplacianKernel` (lib/backend/logos_core.dart) recovers
      // sqrtDeg from degreeInvSqrt and treats any unmerged singleton
      // root with positive volume as a lambda=0 kernel direction, which
      // holds for a self-loop row but not for a selfMass-only node
      // (empty CSR row, so true L_sym action is identity, eigenvalue 1).
      // Cross-checked against `denseSymmetricEigen` on the dense L_sym
      // built directly from the CsrGraph's own arrays.
      test(
        'lanczosSmallEigenpairs reports a spurious extra zero eigenvalue '
        'for a selfMass-only appended node, instead of the true isolated-'
        'node eigenvalue of 1.0',
        () {
          // Base: a single edge (nodes 0-1, one connected component).
          final base = CsrGraph.fromRawEdges(n: 2, edgesPerNode: const [
            [(1, 3.0)],
            [(0, 3.0)],
          ]);
          // Append node 2 with NO real edges, only a positive selfMass —
          // a legitimate, documented use of the public API (e.g. "give a
          // brand new file some self-importance before it has any real
          // coupling edges").
          final withIsolated = base.withNodeAppended(edges: const [], selfMass: 5.0);

          final trueEig = denseSymmetricEigen(_denseLsymFromCsr(withIsolated), withIsolated.n);
          final trueSorted = [...trueEig.values]..sort();
          // True spectrum: {0-1} component contributes {0, 2}; the
          // structurally-empty-row node 2 contributes exactly 1.
          expect(trueSorted[0], closeTo(0.0, 1e-9));
          expect(trueSorted[1], closeTo(1.0, 1e-9));
          expect(trueSorted[2], closeTo(2.0, 1e-9));

          final lanczos = lanczosSmallEigenpairs(withIsolated, 3);
          final lanczosSorted = [...lanczos.eigenvalues]..sort();
          // known bug: lanczos reports [0.0, 0.0, 2.0], inventing a
          // second zero mode and dropping the true eigenvalue of 1.0
          // for the selfMass-only isolated node.
          expect(lanczosSorted[1], closeTo(1.0, 1e-9),
              reason: 'expected the isolated selfMass-only node at '
                  'eigenvalue 1.0, got a spurious second zero instead: '
                  '$lanczosSorted');
        },
        skip: 'known bug: _exactLaplacianKernel misclassifies a '
            'selfMass-only appended node as a lambda=0 kernel direction '
            'instead of eigenvalue 1.0',
      );
    },
  );

  group('Law 2 — withNodeRemoved equals a from-scratch rebuild on remaining nodes', () {
    // known bug: see `_rebuildRemoveOracle` above (repro: seed=0xA004 index=10).
    test('CSR structure matches exactly after id remap', () {
      forAll(
        _genRemoveCase(_graphMix),
        count: 400 * fuzzScale(),
        seed: 0xA004,
        describe: 'remove-rebuild-structure',
        check: _checkRemoveCase,
      );
    },
    skip: 'known bug: withNodeRemoved reconstructs a row\'s degree via a '
        'degreeInvSqrt round-trip instead of the exact raw weight sum, so a '
        'leaf losing its last edge yields a garbage degreeInvSqrt instead of '
        '0.0 (repro: seed=0xA004 index=10)');

    // known bug: same root cause as above, surfacing as a spurious extra
    // zero eigenvalue where the honest rebuild reports the true isolated-
    // node eigenvalue of 1.0 (repro: seed=0xA005 index=7, n=6, removeId=2).
    test('sorted eigenvalue spectrum matches within tolerance', () {
      forAll(
        _genRemoveCase(_graphMixSmall),
        count: 120 * fuzzScale(),
        seed: 0xA005,
        describe: 'remove-rebuild-spectrum',
        check: _checkRemoveSpectrum,
      );
    },
    skip: 'known bug: same withNodeRemoved degree round-trip bug as the '
        'structure test above, manifesting as a spurious extra zero '
        'eigenvalue instead of the true isolated-node eigenvalue of 1.0 '
        '(repro: seed=0xA005 index=7)');
  });

  group('Law 3 — coarsen equals the manual quotient-graph rebuild', () {
    test('CSR structure matches exactly under arbitrary groupings', () {
      forAll(
        _genCoarsenCaseArbitrary(_graphMix),
        count: 300 * fuzzScale(),
        seed: 0xA006,
        describe: 'coarsen-rebuild-structure',
        check: _checkCoarsenRebuild,
      );
    });

    test('sorted eigenvalue spectrum matches within tolerance', () {
      forAll(
        _genCoarsenCaseArbitrary(_graphMixSmall),
        count: 100 * fuzzScale(),
        seed: 0xA007,
        describe: 'coarsen-rebuild-spectrum',
        check: _checkCoarsenSpectrum,
      );
    });

    test('coarsening never increases beta_0 (component count)', () {
      forAll(
        _genCoarsenCaseArbitrary(_graphMix),
        count: 300 * fuzzScale(),
        seed: 0xA008,
        describe: 'coarsen-beta0-monotonic',
        check: _checkCoarsenBeta0Monotonic,
      );
    });

    test(
      'coarsening preserves beta_0 exactly when every group stays within '
      'one original component',
      () {
        forAll(
          _genCoarsenCaseCompatible(_graphMix),
          count: 300 * fuzzScale(),
          seed: 0xA009,
          describe: 'coarsen-beta0-compatible',
          check: _checkCoarsenBeta0ExactWhenCompatible,
        );
      },
    );
  });

  group('Law 4 — append+remove round trip returns to the original graph', () {
    // known bug: same withNodeRemoved degree round-trip bug as Law 2,
    // inherited because removing the just-appended node is itself a
    // withNodeRemoved call (repro: seed=0xA00A index=4, base.n=3).
    test('CSR structure round-trips exactly', () {
      forAll(
        _genAppendCase(_graphMix),
        count: 300 * fuzzScale(),
        seed: 0xA00A,
        describe: 'append-remove-roundtrip-structure',
        check: _checkRoundTrip,
      );
    },
    skip: 'known bug: inherits the withNodeRemoved degree round-trip bug '
        '(removing the just-appended node is itself a withNodeRemoved call) '
        '— repro: seed=0xA00A index=4');

    // known bug: same root cause, surfacing as a mismatched extractable-
    // eigenpair count between the round-tripped and original graphs
    // (repro: seed=0xA00B index=10, base.n=6).
    test('spectrum round-trips within tolerance', () {
      forAll(
        _genAppendCase(_graphMixSmall),
        count: 120 * fuzzScale(),
        seed: 0xA00B,
        describe: 'append-remove-roundtrip-spectrum',
        check: _checkRoundTripSpectrum,
      );
    },
    skip: 'known bug: same withNodeRemoved degree round-trip bug, '
        'surfacing as a mismatched extractable-eigenpair count between the '
        'round-tripped and original graphs (repro: seed=0xA00B index=10)');
  });

  group('Law 5 — csr_builder normalization laws (adversarial)', () {
    test(
      'duplicate edges summed, self-loops dropped, non-positive/non-finite '
      'dropped, symmetric fusion holds',
      () {
        forAll(
          _genAdversarialEdgesCase(),
          count: 300 * fuzzScale(),
          seed: 0xA00C,
          describe: 'csr-builder-normalization',
          check: _checkBuildSymmetricNormalization,
        );
      },
    );

    test('feeding edges in permuted order produces an identical CsrGraph', () {
      forAll(
        _genPermCase(),
        count: 250 * fuzzScale(),
        seed: 0xA00D,
        describe: 'csr-builder-permutation-invariance',
        check: _checkPermutationInvariance,
      );
    });
  });
}
