/// Translation layer from raw logos engine values (coherence, motion
/// warp, flow stress, witness residual, etc.) to semantic bands that
/// an LLM can interpret without hallucinating.
///
/// Background: feeding raw values like `coherence=0.15` or
/// `motion.warp=0.42` to a review model invites fabrication. The
/// model has no stable prior for what these numbers mean, but it
/// does have robust priors for qualitative descriptors like
/// "scattered", "active", "sparse coverage". By translating at the
/// prompt-assembly boundary we give the model a controlled
/// vocabulary and eliminate the "model confabulates interpretation
/// of a number it can't ground" class of hallucinations.
///
/// Every translation returns a [SemanticBand] — a (label, gloss)
/// pair. The prompt builder emits the label as the primary citation
/// target and the gloss as a one-line explanation. Models are
/// instructed to cite labels, never raw numbers.

import 'logos_git_calibration.dart' show LogosAxis, LogosRegime;

/// A qualitative band with a short label and one-line gloss.
///
/// [label] is the citation token (e.g. "scattered", "turbulent") —
/// short, stable, and from a closed vocabulary so prompt
/// reinforcement stays consistent across review turns.
///
/// [gloss] is the human-readable explanation, safe to cite verbatim.
class SemanticBand {
  final String label;
  final String gloss;
  const SemanticBand(this.label, this.gloss);

  /// Render as `label · gloss` — the canonical prompt form.
  String render() => gloss.isEmpty ? label : '$label · $gloss';
}

/// Coherence: how concentrated the relevance signal is across files.
/// Low coherence = change touches many loosely-related areas. High =
/// change is tightly focused.
SemanticBand coherenceBand(double v) {
  if (v < 0.20) {
    return const SemanticBand('scattered',
        'signal dispersed across many loosely-related files');
  }
  if (v < 0.45) {
    return const SemanticBand('mixed',
        'change spans related regions but not one tight cluster');
  }
  if (v < 0.70) {
    return const SemanticBand('coherent',
        'change stays within one related cluster');
  }
  return const SemanticBand('tightly-coherent',
      'change concentrated on a single focal area');
}

/// Stability: how stable the spectral signature is. Low means the
/// relevance field fluctuates from turn to turn (noisy / unstable
/// graph state). High means the signature is settled.
SemanticBand stabilityBand(double v) {
  if (v < 0.30) return const SemanticBand('unstable', 'signal is noisy');
  if (v < 0.60) return const SemanticBand('settling', 'signal is stabilizing');
  return const SemanticBand('stable', 'signal is reliable');
}

/// Motion.warp coverage: how much of the code paths are being
/// actively reshaped. Higher means the change is redirecting flow.
SemanticBand motionWarpBand(double v) {
  if (v < 0.10) return const SemanticBand('still', 'no meaningful path movement');
  if (v < 0.30) return const SemanticBand('gentle', 'light edits, paths mostly preserved');
  if (v < 0.60) return const SemanticBand('active', 'code paths are flowing');
  return const SemanticBand('turbulent', 'paths are being significantly redirected');
}

/// Innovation mass: how much of the change introduces new material
/// vs. tracks existing. Higher = more new content.
SemanticBand innovationBand(double v) {
  if (v < 0.15) return const SemanticBand('incremental', 'small deltas on existing code');
  if (v < 0.40) return const SemanticBand('extending', 'adding to existing patterns');
  if (v < 0.70) return const SemanticBand('expanding', 'meaningful new material');
  return const SemanticBand('novel', 'substantial new surface');
}

/// Flow structural stress: proxy for how much the change stresses
/// existing invariants. Low stress = change fits cleanly; high
/// stress = change is cutting across established structure.
SemanticBand flowStressBand(double v) {
  if (v < 0.15) return const SemanticBand('aligned', 'fits the existing structure');
  if (v < 0.35) return const SemanticBand('mild-stress', 'mostly fits, some torque');
  if (v < 0.60) return const SemanticBand('stress', 'crosses several invariants');
  return const SemanticBand('high-stress', 'heavy cross-structural strain');
}

/// Flow confidence: how confident the engine is in its flow
/// decomposition for this change. Low means the read is uncertain.
SemanticBand flowConfidenceBand(double v) {
  if (v < 0.30) return const SemanticBand('low', 'uncertain reading');
  if (v < 0.60) return const SemanticBand('moderate', 'partial reading');
  return const SemanticBand('high', 'reliable reading');
}

/// Witness coverage: fraction of witness kinds (tests, imports,
/// symbol defs, etc.) that have something to say about this change.
/// Low means the change lacks guardrails.
SemanticBand witnessCoverageBand(double v) {
  if (v < 0.20) return const SemanticBand('absent', 'no witnesses could speak to this change');
  if (v < 0.50) return const SemanticBand('sparse', 'few witnesses engaged');
  if (v < 0.80) return const SemanticBand('partial', 'most witness kinds engaged');
  return const SemanticBand('strong', 'witnesses broadly cover this change');
}

/// Witness corroboration: agreement among the witnesses that DID
/// speak. High corroboration = witnesses agree on the signal.
SemanticBand witnessCorroborationBand(double v) {
  if (v < 0.30) return const SemanticBand('fragmented', 'witnesses disagree or each speaks in isolation');
  if (v < 0.60) return const SemanticBand('partial-agreement', 'some witness alignment');
  return const SemanticBand('corroborated', 'witnesses align on the signal');
}

/// Witness disagreement: amount of cross-kind conflict in the
/// witness signal. High = the kinds disagree.
SemanticBand witnessDisagreementBand(double v) {
  if (v < 0.15) return const SemanticBand('aligned', 'no significant disagreement');
  if (v < 0.35) return const SemanticBand('mild-disagreement', 'minor cross-kind friction');
  if (v < 0.60) return const SemanticBand('notable-disagreement', 'kinds diverge on signal');
  return const SemanticBand('heavy-disagreement', 'strong cross-kind conflict');
}

/// Witness residual predicted/residual mass — how much the witness
/// channel believes it predicted the change vs. how much it did not.
SemanticBand witnessResidualBand({
  required double predicted,
  required double residual,
  required double coverage,
}) {
  if (coverage < 0.20) {
    return const SemanticBand('not-yet-witnessed',
        'witness channel has not engaged this change');
  }
  final ratio = residual <= 0
      ? 0.0
      : residual / (residual + predicted + 1e-9);
  if (ratio < 0.25) {
    return const SemanticBand('predicted',
        'witnesses had strong priors for this change');
  }
  if (ratio < 0.55) {
    return const SemanticBand('partly-predicted',
        'witnesses partially anticipated this change');
  }
  return const SemanticBand('surprising',
      'witnesses did not anticipate most of this change');
}

/// Source/field alignment — how the query itself (diff shape) sits
/// in the broader manifold. High alignment = change follows the
/// current field direction.
SemanticBand alignmentBand(double? v) {
  if (v == null) return const SemanticBand('unavailable', '');
  if (v < 0.30) return const SemanticBand('off-axis', 'change goes against the field');
  if (v < 0.60) return const SemanticBand('partial', 'change partially aligns with the field');
  return const SemanticBand('aligned', 'change follows the field');
}

/// Per-axis attribution strength → word label.
///
/// Used when emitting "why this neighbor was surfaced" trails.
/// Labels map to: negligible / trace / moderate / strong / dominant.
String attributionStrength(double fraction) {
  final f = fraction.clamp(0.0, 1.0);
  if (f < 0.10) return 'negligible';
  if (f < 0.25) return 'trace';
  if (f < 0.50) return 'moderate';
  if (f < 0.75) return 'strong';
  return 'dominant';
}

/// Human-readable label for each `LogosAxis`. Used in axis-trail
/// rendering (e.g. "symbol-overlap(strong) · test-mirror(moderate)").
String axisLabel(LogosAxis axis) {
  switch (axis) {
    case LogosAxis.primary:
      return 'touched-in-diff';
    case LogosAxis.m:
      return 'symbol-pickaxe';
    case LogosAxis.ab:
      return 'path-mirror';
    case LogosAxis.graph:
      return 'graph-diffusion';
    case LogosAxis.symbol:
      return 'symbol-overlap';
  }
}

/// Regime name with a one-line gloss appropriate for an LLM.
SemanticBand regimeBand(LogosRegime regime) {
  switch (regime) {
    case LogosRegime.focused:
      return const SemanticBand('focused',
          'change stays in a tight cluster — prioritize depth of review within it');
    case LogosRegime.scoped:
      return const SemanticBand('scoped',
          'feature-sized change across a few related files — check tests and call sites');
    case LogosRegime.sweep:
      return const SemanticBand('sweep',
          'large or low-coherence change — prioritize cross-module consistency');
    case LogosRegime.uncategorised:
      return const SemanticBand('uncategorised',
          'regime unclear — fall back to generic review priors');
  }
}

/// Overall "shape" read — a single descriptor combining coherence
/// + motion + stress. Gives the review a quick characterization
/// without pushing multiple bands onto the model at once.
SemanticBand overallShape({
  required double coherence,
  required double motionWarp,
  required double structuralStress,
}) {
  final c = coherenceBand(coherence).label;
  final m = motionWarpBand(motionWarp).label;
  final s = flowStressBand(structuralStress).label;
  // Encode a few intuitive combinations. Rest fall through to a
  // composite label so the model still gets a coherent phrase.
  if (c == 'tightly-coherent' && m == 'still') {
    return const SemanticBand('surgical',
        'small, tightly-focused change with no meaningful flow movement');
  }
  if (c == 'scattered' && s == 'high-stress') {
    return const SemanticBand('broad-restructuring',
        'change spans many areas and puts heavy stress on existing invariants');
  }
  if (c == 'coherent' && m == 'gentle') {
    return const SemanticBand('tidy',
        'coherent edits with gentle path movement');
  }
  if (m == 'turbulent') {
    return const SemanticBand('heavy-flow',
        'change significantly redirects code paths');
  }
  if (s == 'high-stress') {
    return const SemanticBand('structurally-stressful',
        'change crosses several invariants');
  }
  return SemanticBand('$c-$m', 'composite read: $c coherence, $m motion, $s stress');
}

/// A confidence badge for a whole section — derived from whether
/// the engine had enough data to make a reliable read.
SemanticBand sectionConfidence({
  required bool hasFlow,
  required bool hasWitness,
  required bool hasAttribution,
  required double flowConfidence,
}) {
  if (!hasFlow) {
    return const SemanticBand('low',
        'flow channel is quiet this turn; let the bands inform, not anchor');
  }
  if (flowConfidence < 0.30) {
    return const SemanticBand('low',
        'early read — the engine is still finding its footing on this change');
  }
  if (!hasWitness && !hasAttribution) {
    return const SemanticBand('moderate',
        'flow speaks clearly; witness and attribution are resting this turn');
  }
  if (flowConfidence < 0.60) {
    return const SemanticBand('moderate',
        'partial reading — some channels firmer than others');
  }
  return const SemanticBand('high',
      'channels agree on a stable, well-supported read');
}
