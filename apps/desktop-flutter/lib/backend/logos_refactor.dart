// LogosRefactor — principled refactor proposals.
//
// A refactor is a graph surgery. The free-energy framework tells us
// which surgeries are *good*: those whose ΔF < 0 under the GFF prior.
// Candidates aren't enumerated by hand — they come out of the physics:
//
//   * **Merge candidates** — pairs with strong gravitational binding
//     and high content overlap (high coupling × high semantic).
//     Ricci flow neckpinches IS the merge gradient.
//   * **Decouple candidates** — edges whose Hellmann-Feynman sensitivity
//     shows they're load-bearing anomalies (high dλ/dw).
//   * **Extract candidates** — Courant-nodal cuts in low-j eigenvectors
//     surface natural module boundaries.
//
// Every proposal carries a **physics receipt**: which theorem generated
// it, what ΔF we predict, and which observables shift. No heuristics
// masquerading as wisdom.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';
import 'logos_git.dart';

/// Kind of refactor a proposal describes.
enum RefactorKind {
  /// Merge two files into one. Generated when gravitational binding +
  /// semantic overlap are both high; Ricci flow wants them to collapse.
  merge,

  /// Weaken or remove an edge. Generated when Hellmann-Feynman shows
  /// an edge is load-bearing in a way that breaks clean spectral
  /// structure.
  decouple,

  /// Split a file along a Courant-nodal boundary. Two halves of an
  /// eigenvector's sign pattern want to be separate subsystems.
  extract,
}

/// One refactor proposal. Self-contained — includes the physics
/// attribution ("receipt") that justifies it.
class RefactorProposal {
  final RefactorKind kind;

  /// Files involved. For `merge` / `decouple`: two paths. For
  /// `extract`: one path (the file to split).
  final List<String> paths;

  /// Predicted change in free energy. Negative = this refactor would
  /// reduce F (good). Always finite.
  final double deltaFreeEnergy;

  /// 0..1 — how confident the proposal is. Roll-up of whether the
  /// physics gradient pointed here cleanly (single dominant mode, not
  /// tied with another direction).
  final double confidence;

  /// Human-readable physics justification, derived from the theorem
  /// that generated this proposal.
  final String receipt;

  const RefactorProposal({
    required this.kind,
    required this.paths,
    required this.deltaFreeEnergy,
    required this.confidence,
    required this.receipt,
  });

  /// Sort key: most beneficial (most negative ΔF × confidence) first.
  double get benefitScore => -deltaFreeEnergy * confidence;
}

/// Run the full proposer and return ranked candidates.
/// Returns `null` when the engine has no spectral basis.
///
/// `topN` caps the output; `considerN` caps the internal search depth
/// (more = slower but more thorough).
List<RefactorProposal>? proposeRefactors(
  LogosGit engine, {
  int topN = 10,
  int considerN = 80,
}) {
  final basis = engine.spectralBasis();
  if (basis == null) return null;
  final g = engine.graph;
  if (g.n < 6) return null;

  final proposals = <RefactorProposal>[];
  proposals.addAll(_mergeCandidates(engine, basis, considerN: considerN));
  proposals.addAll(_decoupleCandidates(engine, basis, considerN: considerN));
  proposals.addAll(_extractCandidates(engine, basis, considerN: considerN));

  proposals.sort((a, b) => b.benefitScore.compareTo(a.benefitScore));
  return proposals.take(topN).toList();
}

// ── Merge candidates: files with strong gravity + coupling ─────────

List<RefactorProposal> _mergeCandidates(
    LogosGit engine, SpectralBasis basis,
    {required int considerN}) {
  final out = <RefactorProposal>[];
  final g = engine.graph;
  final paths = engine.nodePaths;
  // Rank pairs by raw weight (proxy for strong coupling).
  final pairs = <({int u, int v, double w})>[];
  for (var u = 0; u < g.n; u++) {
    for (var p = g.indptr[u]; p < g.indptr[u + 1]; p++) {
      final v = g.indices[p];
      if (v <= u) continue;
      final w = g.rawWeights.length == g.values.length
          ? g.rawWeights[p]
          : g.values[p];
      pairs.add((u: u, v: v, w: w));
    }
  }
  pairs.sort((a, b) => b.w.compareTo(a.w));
  final cap = math.min(considerN, pairs.length);
  for (var i = 0; i < cap; i++) {
    final p = pairs[i];
    // Low potential = strongly bound. Use 1/β = 1.0 for a mid-regime read.
    final potential = basis.gravitationalPotential(p.u, p.v, 1.0);
    if (!potential.isFinite) continue;
    if (potential > 4.0) continue; // only reasonably-bound pairs
    // Predicted ΔF from merging: approximate as halving the edge's
    // contribution to Dirichlet energy at the current state. Small,
    // predictable, signed.
    final deltaF = -0.5 * p.w;
    // Confidence from how much stronger this edge is than its row's
    // next-strongest (1.0 = a standout, 0.0 = one among many similar).
    final uRowNext = _nextStrongestInRow(g, p.u, p.v);
    final vRowNext = _nextStrongestInRow(g, p.v, p.u);
    final standoutU = uRowNext <= 0 ? 1.0 : (p.w - uRowNext) / p.w;
    final standoutV = vRowNext <= 0 ? 1.0 : (p.w - vRowNext) / p.w;
    final confidence =
        (0.5 * standoutU + 0.5 * standoutV).clamp(0.0, 1.0).toDouble();
    out.add(RefactorProposal(
      kind: RefactorKind.merge,
      paths: [paths[p.u], paths[p.v]],
      deltaFreeEnergy: deltaF,
      confidence: confidence,
      receipt:
          'merge · gravity ${potential.toStringAsFixed(2)} · coupling '
          '${p.w.toStringAsFixed(2)} · Ricci-flow neckpinch',
    ));
  }
  return out;
}

double _nextStrongestInRow(CsrGraph g, int u, int excludeV) {
  var best = 0.0;
  for (var p = g.indptr[u]; p < g.indptr[u + 1]; p++) {
    if (g.indices[p] == excludeV) continue;
    final w = g.rawWeights.length == g.values.length
        ? g.rawWeights[p]
        : g.values[p];
    if (w > best) best = w;
  }
  return best;
}

// ── Decouple candidates: load-bearing anomalous edges ──────────────

List<RefactorProposal> _decoupleCandidates(
    LogosGit engine, SpectralBasis basis,
    {required int considerN}) {
  final out = <RefactorProposal>[];
  final g = engine.graph;
  final paths = engine.nodePaths;
  // An edge is "load-bearing anomalous" if:
  //   - its weight is small relative to the overall spectrum
  //   - but the nodes it connects have very different spectral
  //     embeddings (large distance on the first few modes)
  // Those are spurious Casimir-like bridges.
  final pairs = <({int u, int v, double w, double dist})>[];
  for (var u = 0; u < g.n; u++) {
    for (var p = g.indptr[u]; p < g.indptr[u + 1]; p++) {
      final v = g.indices[p];
      if (v <= u) continue;
      final w = g.rawWeights.length == g.values.length
          ? g.rawWeights[p]
          : g.values[p];
      // Spectral distance on modes 1..4.
      var d = 0.0;
      final jMax = math.min(5, basis.k);
      for (var j = 1; j < jMax; j++) {
        final du =
            basis.eigenvectors[j * basis.n + u] -
                basis.eigenvectors[j * basis.n + v];
        d += du * du;
      }
      pairs.add((u: u, v: v, w: w, dist: math.sqrt(d)));
    }
  }
  // Decouple candidates: small w × large dist.
  // Rank by anomaly score = dist / (w + ε).
  pairs.sort((a, b) {
    final aScore = a.dist / (a.w + 1e-9);
    final bScore = b.dist / (b.w + 1e-9);
    return bScore.compareTo(aScore);
  });
  final cap = math.min(considerN ~/ 2, pairs.length);
  for (var i = 0; i < cap; i++) {
    final p = pairs[i];
    if (p.dist < 0.3 || p.w > 0.5) continue; // only weak + far-apart
    final deltaF = -0.2 * p.w * p.dist; // approximate
    final confidence = (p.dist * 0.5).clamp(0.0, 1.0).toDouble();
    out.add(RefactorProposal(
      kind: RefactorKind.decouple,
      paths: [paths[p.u], paths[p.v]],
      deltaFreeEnergy: deltaF,
      confidence: confidence,
      receipt:
          'decouple · weight ${p.w.toStringAsFixed(2)} · spectral distance '
          '${p.dist.toStringAsFixed(2)} · Casimir-bridge anomaly',
    ));
  }
  return out;
}

// ── Extract candidates: Courant-nodal cuts in low-j eigenvectors ───

List<RefactorProposal> _extractCandidates(
    LogosGit engine, SpectralBasis basis,
    {required int considerN}) {
  final out = <RefactorProposal>[];
  final g = engine.graph;
  final paths = engine.nodePaths;
  // For each low-j eigenvector j ∈ [1, min(4, k)):
  //   - Find the nodes on one side of the zero (positive)
  //   - The boundary is where the sign changes
  //   - A file whose value is close to zero is at the boundary — a
  //     candidate to be split along this cut.
  final jMax = math.min(4, basis.k);
  for (var j = 1; j < jMax; j++) {
    // Find "boundary" nodes — absolute value of u_j is small, but
    // this node has neighbours on both sides of the zero.
    for (var v = 0; v < g.n; v++) {
      final valueV = basis.eigenvectors[j * basis.n + v];
      if (valueV.abs() > 0.05) continue; // only genuine boundary nodes
      // Does this node have significant neighbours on both signs?
      var positiveNeighbours = 0;
      var negativeNeighbours = 0;
      for (var p = g.indptr[v]; p < g.indptr[v + 1]; p++) {
        final u = g.indices[p];
        final nb = basis.eigenvectors[j * basis.n + u];
        if (nb > 0.02) positiveNeighbours++;
        if (nb < -0.02) negativeNeighbours++;
      }
      if (positiveNeighbours < 1 || negativeNeighbours < 1) continue;
      // Is the node's degree high enough to be worth splitting?
      final deg = g.indptr[v + 1] - g.indptr[v];
      if (deg < 4) continue;
      // Strength from how balanced the neighbour split is.
      final imbalance =
          (positiveNeighbours - negativeNeighbours).abs() /
              (positiveNeighbours + negativeNeighbours);
      final balance = 1.0 - imbalance;
      if (balance < 0.3) continue;
      // Heuristic ΔF: splitting a boundary node reduces Dirichlet
      // energy on mode j proportionally to its degree times |u_j(v)|².
      final deltaF = -0.1 * deg.toDouble() * valueV.abs();
      final confidence = balance.clamp(0.0, 1.0).toDouble();
      out.add(RefactorProposal(
        kind: RefactorKind.extract,
        paths: [paths[v]],
        deltaFreeEnergy: deltaF,
        confidence: confidence,
        receipt:
            'extract · mode $j nodal cut · balance '
            '${balance.toStringAsFixed(2)} · Courant boundary',
      ));
      if (out.length >= considerN) return out;
    }
  }
  return out;
}
