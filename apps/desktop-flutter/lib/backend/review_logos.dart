// review_logos.dart — emergent review-score pipeline.
//
// The reviewing LLM emits CANDIDATE claims; the spectral engine
// scores them via five native-logos axes and a Born-mixer blend.
// Nothing in this file pattern-matches against claim text, filename
// regexes, or error kinds. Every score is a functional of the
// diffusion field.
//
// The five axes:
//
//   1. grounding        — cos(φ_claim, φ_diff). Does the claim's
//                         symbol-neighborhood overlap the diff's?
//   2. verifiability    — can we actually read the diff? NUL bytes,
//                         binary markers, mixed line endings collapse
//                         the score toward zero.
//   3. reach            — participation-ratio of φ_claim. Hub symbols
//                         have high reach; dead-code leaves have low.
//   4. coherence        — mean pairwise cosine across all φs of the
//                         claim's named symbols. Scattered claims
//                         score low; tightly-coupled claims score
//                         high.
//   5. learned prior    — outcome ratchet (see review_ratchet.dart).
//                         Feeds in as a per-shape Bayesian prior.
//
// The axes compose via the same evidence-weighted blend the codebase
// already uses for H_sym / K / G (Grimoire Circle XI — Born mixer
// as confidence-gated combiner). No hand-tuned weights; each axis
// contributes in proportion to the evidence supporting it.

import 'dart:math' as math;
import 'dart:typed_data';

import 'engram_hunk_encoder.dart' show EngramHunkEncoder, HunkKVector;
import 'engram_text_kspace.dart' show encodeProse, nearestRowsInTable;
import 'git.dart' show extractDiffTouchedPaths;
import 'logos_git.dart' show LogosGit;
import 'logos_hunks.dart' as hunks;
import 'pr_shape.dart' show PrShapeComputer;
import 'review_ratchet.dart' show ClaimOutcomeRatchet;

/// Bag of observables describing one reviewer claim. Every field is
/// a continuous projection onto an axis the reviewer and engine both
/// see — no categoricals, no strings-as-enums. Quantisation happens
/// only at ratchet-lookup time ([ClaimShapeKey]); the raw shape keeps
/// full precision for downstream analytics.
class ClaimShape {
  const ClaimShape({
    required this.grounding,
    required this.verifiability,
    required this.reach,
    required this.coherence,
    required this.symbolCount,
    required this.textLength,
  });

  /// Axis 1: cosine between the claim's diffused φ and the diff's
  /// diffused φ. `0` when the claim's symbols don't land in the
  /// engine's coupling graph at all (= the textbook hallucination).
  final double grounding;

  /// Axis 2: per-whole-diff verifiability. Tripped by binary markers
  /// (`Binary files … differ`), literal NUL bytes, mixed CRLF/LF.
  final double verifiability;

  /// Axis 3: normalised participation ratio of φ_claim —
  /// `(Σφ)² / (Σφ² · n)`. In [0, 1]: 0 = no reach, 1 = uniform reach
  /// across every file in the graph.
  final double reach;

  /// Axis 4: mean pairwise cosine of per-symbol φs within a single
  /// claim. `1.0` for single-symbol or perfectly-coherent claims;
  /// drops toward `0` as the claim's symbols scatter into unrelated
  /// neighborhoods.
  final double coherence;

  /// Number of distinct symbol/path references the claim named,
  /// after filtering to paths the engine actually knows about. Used
  /// as evidence weight in the Born blend.
  final int symbolCount;

  /// Length of the claim's raw text in bytes. Evidence weight for the
  /// ratchet prior — longer claims carry more information and deserve
  /// a higher-confidence learned prior term.
  final int textLength;

  /// Shape → probability serialisation for the ratchet (5 quantised
  /// axes + one log-bucket on text length).
  int shapeHash() {
    int h = 0;
    h = (h * 31) ^ (grounding * 15).round().clamp(0, 15);
    h = (h * 31) ^ (verifiability * 15).round().clamp(0, 15);
    h = (h * 31) ^ (reach * 15).round().clamp(0, 15);
    h = (h * 31) ^ (coherence * 15).round().clamp(0, 15);
    h = (h * 31) ^ symbolCount.clamp(0, 31);
    // Log-bucket text length so "200 bytes" and "210 bytes" share a
    // bucket but "200 bytes" and "20 000 bytes" don't.
    final logLen = textLength <= 0 ? 0 : math.log(textLength).ceil();
    h = (h * 31) ^ logLen.clamp(0, 31);
    return h;
  }
}

/// The composed score of a ClaimShape plus per-axis breakdown so the
/// UI can surface *why* a claim was admitted or dropped. Never round
/// or clip the composite downstream; read the per-axis fields when
/// you want to display detail.
class ReviewScore {
  const ReviewScore({
    required this.composite,
    required this.shape,
    required this.ratchetPrior,
    required this.evidenceTotal,
  });

  final double composite;
  final ClaimShape shape;
  final double ratchetPrior;
  final double evidenceTotal;

  /// True when the claim cleared the `admissionFloor`. Split from the
  /// numeric score so UI can chart the distribution of composites
  /// independent of the accept/reject decision.
  bool admitted({double admissionFloor = 0.55}) => composite >= admissionFloor;
}

// ---------------------------------------------------------------------------
// Axis 1: grounding via counter-diffusion.
// ---------------------------------------------------------------------------

/// Cosine between two heat-kernel φ vectors, where φ_claim is
/// diffused from the claim's named symbols and φ_diff is diffused
/// from the diff's touched paths. A grounded claim's symbols
/// inhabit the same manifold corner as the diff → cosine near 1. A
/// hallucination names symbols disconnected from the diff → cosine
/// near 0.
///
/// Reuses [PrShapeComputer.cosine] — the same math that powers PR
/// orbital partnership — applied to a new pair of vectors.
double groundingConsistency({
  required LogosGit engine,
  required Set<String> claimPaths,
  required Set<String> diffTouchedPaths,
  double t = 1.0,
}) {
  if (claimPaths.isEmpty || diffTouchedPaths.isEmpty) return 0.0;
  final phiClaim = _densePhiFor(engine, claimPaths, t: t);
  final phiDiff = _densePhiFor(engine, diffTouchedPaths, t: t);
  // When either source set resolves to zero in-graph paths, the
  // corresponding φ is all zeros and PrShapeComputer.cosine returns
  // 0 — which is the correct signal for "ungrounded."
  return PrShapeComputer.cosine(phiClaim, phiDiff);
}

// ---------------------------------------------------------------------------
// Axis 2: verifiability from diff structure.
// ---------------------------------------------------------------------------

/// Whole-diff verifiability — the fraction of paths git said were
/// touched for which we actually have **visible hunk content**.
///
/// This is a structural measurement, not a pattern match. When git
/// emits a `Binary files a/X b/X differ` section, the diff header
/// declares that X was touched but [hunks.parseDiffHunks] returns
/// no hunks for X — the hunk stream is empty precisely because git
/// refused to render the change as text. Coverage of such a diff
/// lands at 0 by construction, without the pipeline ever knowing
/// the string "Binary files" or recognising any specific marker.
///
/// Mixed diffs (some text files, some binary files) land on a
/// fractional score proportional to the readable fraction, so the
/// reviewer's confidence scales smoothly with how much it could
/// actually see.
///
/// Empty diffs return `1.0` (trivially — no paths were claimed
/// touched, so 0 of 0 covered is vacuously full coverage).
double wholeDiffVerifiability(String diffText) {
  if (diffText.isEmpty) return 1.0;
  final touchedPaths = extractDiffTouchedPaths(diffText);
  if (touchedPaths.isEmpty) return 1.0;
  final parsedHunks = hunks.parseDiffHunks(diffText);
  final pathsWithHunks = <String>{for (final h in parsedHunks) h.filePath};
  var covered = 0;
  for (final p in touchedPaths) {
    if (pathsWithHunks.contains(p)) covered++;
  }
  return covered / touchedPaths.length;
}

// ---------------------------------------------------------------------------
// Axis 3: downstream reach as normalised participation ratio.
// ---------------------------------------------------------------------------

/// Reach of the claim's diffusion across the graph. Computed as the
/// participation ratio of φ_claim, normalised by graph size:
///
///     reach = (Σφ)² / (Σφ² · n)
///
/// In [0, 1]: 0 = claim's mass concentrates on a single node (trivial
/// reach); 1 = mass spreads perfectly uniformly across all `n` nodes
/// of the graph (maximum reach). Severity scales with reach — a
/// claim about a central hub naturally ranks higher than a claim
/// about a leaf.
double downstreamReach({
  required LogosGit engine,
  required Set<String> claimPaths,
  double t = 1.0,
}) {
  if (claimPaths.isEmpty) return 0.0;
  final phi = _densePhiFor(engine, claimPaths, t: t);
  final n = phi.length;
  if (n == 0) return 0.0;
  double l1 = 0.0, l2 = 0.0;
  for (final v in phi) {
    l1 += v;
    l2 += v * v;
  }
  if (l2 <= 0) return 0.0;
  final pr = (l1 * l1) / l2;
  // PR ∈ [1, n]; subtract 1 so a delta (reach-1 concentrated mass)
  // maps to 0, and normalise by (n-1) so a uniform field maps to 1.
  if (n <= 1) return 0.0;
  return ((pr - 1.0) / (n - 1.0)).clamp(0.0, 1.0);
}

// ---------------------------------------------------------------------------
// Axis 4: intra-claim coherence from pairwise symbol cosines.
// ---------------------------------------------------------------------------

/// Mean pairwise cosine across per-symbol φs within one claim. A
/// claim that names three symbols all in the same module scores
/// near 1 (they all diffuse into the same neighborhood); a claim
/// that names three symbols from unrelated corners scores near 0.
///
/// Single-symbol claims score `1.0` — they are trivially coherent
/// with themselves and the axis should not penalise them relative
/// to multi-symbol claims.
double intraClaimCoherence({
  required LogosGit engine,
  required List<String> claimPaths,
  double t = 1.0,
}) {
  if (claimPaths.length < 2) return 1.0;
  final phis = <Float64List>[];
  for (final p in claimPaths) {
    final phi = _densePhiFor(engine, {p}, t: t);
    if (_hasMass(phi)) phis.add(phi);
  }
  if (phis.length < 2) return 1.0;
  var cosSum = 0.0;
  var pairs = 0;
  for (var i = 0; i < phis.length; i++) {
    for (var j = i + 1; j < phis.length; j++) {
      cosSum += PrShapeComputer.cosine(phis[i], phis[j]);
      pairs++;
    }
  }
  return pairs == 0 ? 1.0 : cosSum / pairs;
}

// ---------------------------------------------------------------------------
// Composition: Born-mixer blend of all five axes.
// ---------------------------------------------------------------------------

/// Compose a [ClaimShape] + learned prior into a composite
/// [ReviewScore]. The blend mirrors the evidence-weighted pattern in
/// `logos_hunks.dart`'s H_sym combiner (Grimoire Circle XI): each
/// axis contributes in proportion to `log(1 + supporting_evidence)`,
/// so axes with more measurement behind them carry more weight.
///
/// No hand-tuned constants. The evidence figures are structural:
///
///   • grounding evidence ≈ log(1 + #symbols)
///   • verifiability evidence ≈ 1 (always one diff worth)
///   • reach evidence ≈ log(1 + reach × n)
///   • coherence evidence ≈ log(1 + #symbols — 1)   (needs ≥ 2 syms)
///   • prior evidence ≈ log(1 + #observations in ratchet bucket)
ReviewScore composeReviewScore({
  required ClaimShape shape,
  required ClaimOutcomeRatchet ratchet,
}) {
  final prior = ratchet.priorFor(shape);
  final priorObs = ratchet.observationCountFor(shape);

  // Each spectral axis gets a base weight of 1 plus an evidence
  // bonus. The base ensures a low-evidence claim (e.g. zero
  // extractable symbols) still contributes its axis values into
  // the blend — otherwise the denominator collapses to verifiability
  // alone and a hallucinated claim with `grounding = 0` scores high
  // just because the diff happens to be readable text.
  //
  // Coherence is exempt from the base weight: it's only meaningful
  // with ≥ 2 symbols, so for single-symbol claims we set its weight
  // to zero and let the other axes carry the score.
  final wGrounding = 1.0 + math.log(1.0 + shape.symbolCount.toDouble());
  const wVerifiab = 1.0;
  final wReach = 1.0 + math.log(1.0 + shape.reach * 100.0);
  final wCoherence = shape.symbolCount >= 2
      ? 1.0 + math.log(shape.symbolCount.toDouble())
      : 0.0;
  final wPrior = math.log(1.0 + priorObs.toDouble());

  // wGrounding ≥ 1, wVerifiab = 1, wReach ≥ 1 (all have the constant
  // base), so `total ≥ 3` always. No need for a zero-guard.
  final total = wGrounding + wVerifiab + wReach + wCoherence + wPrior;
  final composite = (wGrounding * shape.grounding +
          wVerifiab * shape.verifiability +
          wReach * shape.reach +
          wCoherence * shape.coherence +
          wPrior * prior) /
      total;
  return ReviewScore(
    composite: composite.clamp(0.0, 1.0),
    shape: shape,
    ratchetPrior: prior,
    evidenceTotal: total,
  );
}

// ---------------------------------------------------------------------------
// Builder: claim text + diff + engine → ClaimShape.
// ---------------------------------------------------------------------------

/// Compute a full [ClaimShape] from the raw claim text, the diff it
/// pertains to, and the engine. Handles entity extraction + all four
/// spectral axes. Axis 5 (learned prior) is applied at compose time
/// via [composeReviewScore].
ClaimShape computeClaimShape({
  required LogosGit engine,
  required String claimText,
  required String diffText,
  Set<String>? explicitClaimPaths,
  EngramHunkEncoder? encoder,
  double t = 1.0,
}) {
  // Entity extraction: merge regex-found paths with engram-nearest
  // semantic matches (when encoder + K-table are both available).
  final claimPaths = <String>{...?explicitClaimPaths};
  claimPaths.addAll(extractClaimPathsFromText(claimText, engine.pathToId));
  if (encoder != null) {
    final table = engine.perFileKVectors;
    if (!table.isEmpty) {
      claimPaths.addAll(
        extractClaimEntitiesViaEngram(
          claimText: claimText,
          encoder: encoder,
          engine: engine,
        ),
      );
    }
  }

  final diffTouchedPaths =
      extractDiffTouchedPaths(diffText).intersection(engine.pathToId.keys.toSet());

  final grounding = groundingConsistency(
    engine: engine,
    claimPaths: claimPaths,
    diffTouchedPaths: diffTouchedPaths,
    t: t,
  );
  final verifiability = wholeDiffVerifiability(diffText);
  final reach = downstreamReach(
    engine: engine,
    claimPaths: claimPaths,
    t: t,
  );
  final coherence = intraClaimCoherence(
    engine: engine,
    claimPaths: claimPaths.toList(),
    t: t,
  );

  return ClaimShape(
    grounding: grounding,
    verifiability: verifiability,
    reach: reach,
    coherence: coherence,
    symbolCount: claimPaths.length,
    textLength: claimText.length,
  );
}

// ---------------------------------------------------------------------------
// Entity extraction — the one parsing step before the axes kick in.
// ---------------------------------------------------------------------------

final RegExp _kPathLike = RegExp(
  r'[a-zA-Z_][\w\-./]*\.[a-zA-Z0-9]{1,6}',
);

/// Explicit file-path extraction from claim text. Catches anything
/// matching `{identifier}{.path}+.{ext}` then filters to paths the
/// engine actually knows about. Pure parsing, not pattern-matching:
/// "does this token look like a path?" is orthogonal to "is this
/// claim real?"
Set<String> extractClaimPathsFromText(
  String text,
  Map<String, int> pathToId,
) {
  final out = <String>{};
  for (final m in _kPathLike.allMatches(text)) {
    final candidate = m.group(0)!;
    if (pathToId.containsKey(candidate)) {
      out.add(candidate);
    }
  }
  return out;
}

/// Engram-based entity extraction. The claim text is encoded into
/// K-space and the nearest file rows in [engine.perFileKVectors] are
/// returned as the claim's semantic entities. A claim that names
/// real concepts (even without literal file paths) surfaces the
/// nearest files; a claim that's entirely garbage surfaces nothing
/// because the engram's GloVe coverage is too thin.
///
/// Uses the same [nearestRowsInTable] machinery that backs the
/// existing semantic-neighbor UI.
Set<String> extractClaimEntitiesViaEngram({
  required String claimText,
  required EngramHunkEncoder encoder,
  required LogosGit engine,
  int topK = 12,
  double minSimilarity = 0.45,
}) {
  final kv = encodeProse(claimText, encoder);
  if (kv == null) return const {};
  final HunkKVector kvNonNull = kv;
  if (kvNonNull.vocabHits < 3) return const {};
  final table = engine.perFileKVectors;
  if (table.isEmpty) return const {};
  final matches = nearestRowsInTable(
    table,
    qRe: kvNonNull.kRe,
    qIm: kvNonNull.kIm,
    topK: topK,
    minSimilarity: minSimilarity,
  );
  return {for (final m in matches) m.path};
}

// ---------------------------------------------------------------------------
// Internals.
// ---------------------------------------------------------------------------

/// Diffuse from a source path set into a dense φ vector indexed by
/// `engine.nodePaths`. Single-axis attribution — the Born mixer's
/// per-axis machinery returns a `Map<String, Float64List>` and we
/// grab the sole entry.
///
/// Returns a zero vector when the sources resolve to no in-graph
/// paths; the downstream cosine / participation-ratio math already
/// handles that case correctly.
Float64List _densePhiFor(
  LogosGit engine,
  Set<String> sources, {
  required double t,
}) {
  final n = engine.nodePaths.length;
  if (sources.isEmpty || n == 0) return Float64List(n);
  final weights = <String, double>{
    for (final p in sources)
      if (engine.pathToId.containsKey(p)) p: 1.0,
  };
  if (weights.isEmpty) return Float64List(n);
  final attr = engine.diffuseWithAttribution(
    weightsByPath: weights,
    axisLabelByPath: {for (final k in weights.keys) k: '_claim'},
    t: t,
  );
  final perAxis = attr?.perAxisPhi;
  if (perAxis == null || perAxis.isEmpty) return Float64List(n);
  return perAxis.values.first;
}

bool _hasMass(Float64List phi) {
  for (final v in phi) {
    if (v > 0) return true;
  }
  return false;
}
