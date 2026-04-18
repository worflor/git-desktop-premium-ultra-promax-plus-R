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

import 'logos_core.dart';
import 'logos_git.dart';
import 'logos_sensitivity.dart';

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

  // One sensitivity field, shared across all candidate generators.
  // Transpose builds once; gap + logDet fields each compute once and
  // cache. No re-scanning across proposal kinds.
  final field = SensitivityField(g, basis);

  final proposals = <RefactorProposal>[];
  proposals.addAll(
      _mergeCandidates(engine, basis, field, considerN: considerN));
  proposals.addAll(
      _decoupleCandidates(engine, basis, field, considerN: considerN));
  proposals.addAll(_extractCandidates(engine, basis, considerN: considerN));

  proposals.sort((a, b) => b.benefitScore.compareTo(a.benefitScore));
  return proposals.take(topN).toList();
}

// ── Merge candidates: files with strong gravity + coupling ─────────

List<RefactorProposal> _mergeCandidates(
    LogosGit engine, SpectralBasis basis, SensitivityField field,
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
    // Hellmann-Feynman log-det sensitivity: how much does this edge
    // actually move the spectrum? A strong raw weight on an edge the
    // spectrum doesn't notice is vacuous coupling (e.g. a leaf-to-leaf
    // symbol match). A strong weight where the spectrum ALSO cares is
    // the canonical merge candidate.
    final sens = logDetSensitivity(basis, p.u, p.v);
    // Predicted ΔF: raw Dirichlet contribution plus half of the
    // log-det cost — the sensitivity captures the "this edge matters"
    // correction. Both are negative (beneficial) on a good merge.
    final deltaF = -0.5 * p.w - 0.25 * sens;
    // Confidence compounds: (a) the edge is a standout in both rows
    // AND (b) its spectral sensitivity confirms it's not a vacuous
    // coupling.
    final uRowNext = _nextStrongestInRow(g, p.u, p.v);
    final vRowNext = _nextStrongestInRow(g, p.v, p.u);
    final standoutU = uRowNext <= 0 ? 1.0 : (p.w - uRowNext) / p.w;
    final standoutV = vRowNext <= 0 ? 1.0 : (p.w - vRowNext) / p.w;
    final standoutScore =
        (0.5 * standoutU + 0.5 * standoutV).clamp(0.0, 1.0).toDouble();
    // Sensitivity boost saturates quickly — we only care whether the
    // spectrum notices the edge, not its absolute magnitude.
    final sensBoost = (sens * 4.0).clamp(0.0, 1.0).toDouble();
    final confidence =
        (0.6 * standoutScore + 0.4 * sensBoost).clamp(0.0, 1.0).toDouble();
    out.add(RefactorProposal(
      kind: RefactorKind.merge,
      paths: [paths[p.u], paths[p.v]],
      deltaFreeEnergy: deltaF,
      confidence: confidence,
      receipt:
          'merge · gravity ${potential.toStringAsFixed(2)} · coupling '
          '${p.w.toStringAsFixed(2)} · logDet-sens '
          '${sens.toStringAsFixed(3)} · Ricci-flow + Hellmann-Feynman',
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
    LogosGit engine, SpectralBasis basis, SensitivityField field,
    {required int considerN}) {
  final out = <RefactorProposal>[];
  final g = engine.graph;
  final paths = engine.nodePaths;
  // An edge is a decouple candidate when:
  //   - its raw coupling is small (a weak bond),
  //   - but its spectral sensitivity is large (removing it would
  //     measurably shift the spectrum),
  //   - and it straddles two otherwise-well-separated regions of
  //     the Fiedler embedding (genuine cross-cluster anomaly).
  //
  // The first two are exactly the gap-sensitivity field — a
  // single-mode Fiedler scan delivered by the SensitivityField
  // primitive. The field caches the result, so this call shares
  // compute with any other consumer of the same field.
  final gapField = field.gap();
  if (gapField.isEmpty) return out;
  final cap = math.min(considerN, gapField.length);
  for (var i = 0; i < cap; i++) {
    final row = gapField[i];
    // Filter: only genuinely-weak edges. A strong bridge isn't a
    // decouple candidate, it's a load-bearing highway.
    final rawW = g.rawWeights.length == g.values.length
        ? _rawWeightFor(g, row.a, row.b)
        : row.weight;
    if (rawW > 0.5) continue;
    // The gap sensitivity already is `(u₁[a] − u₁[b])²` — a squared
    // spectral distance on the Fiedler mode. Small sensitivity means
    // the edge doesn't actually separate Fiedler regions, so it's
    // not really a bridge.
    if (row.value < 0.01) continue;
    // Predicted ΔF: proportional to (sensitivity × weight). Small
    // edges with large sensitivity cost the most on removal, but
    // their removal returns that cost PLUS the relief of a Fiedler
    // misalignment.
    final deltaF = -(0.2 * row.value + 0.2 * rawW * row.value);
    // Confidence: sensitivity dominates over neighbouring edges in
    // the sorted field. Top-of-field edges get higher confidence.
    final relStrength = i == 0
        ? 1.0
        : 1.0 - (gapField[i].value / gapField[0].value).clamp(0.0, 1.0);
    final confidence =
        (0.5 + 0.5 * relStrength).clamp(0.0, 1.0).toDouble();
    out.add(RefactorProposal(
      kind: RefactorKind.decouple,
      paths: [paths[row.a], paths[row.b]],
      deltaFreeEnergy: deltaF,
      confidence: confidence,
      receipt: 'decouple · weight ${rawW.toStringAsFixed(2)} · '
          'gap-sensitivity ${row.value.toStringAsFixed(3)} · '
          'Hellmann-Feynman bridge',
    ));
    if (out.length >= considerN ~/ 2) break;
  }
  return out;
}

/// Internal helper — look up the raw weight of edge (a, b) by scanning
/// row a's indptr range. O(deg(a)). Used by decouple candidates that
/// need the un-fused weight rather than the fused value from the
/// sensitivity row.
double _rawWeightFor(CsrGraph g, int a, int b) {
  for (var p = g.indptr[a]; p < g.indptr[a + 1]; p++) {
    if (g.indices[p] == b) {
      return g.rawWeights.length == g.values.length
          ? g.rawWeights[p]
          : g.values[p];
    }
  }
  return 0.0;
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
