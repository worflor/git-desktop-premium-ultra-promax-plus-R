// review_grounding.dart — grade the reviewer's own claims.
//
// The dormant 5-axis scorer in review_logos.dart reads a finding's
// named symbols back against the diff it claims to describe. This module
// applies it to the findings a review pass emitted, attaches the per-axis
// result to each finding (for the learning loop + UI), and renders a
// compact <claim_grounding> block that the *verify* pass studies as a
// second opinion.
//
// Design rule: grounding is advisory, never a gate. A real bug in a
// brand-new or leaf file legitimately scores low grounding/reach; the
// composite is shown, not enforced. The reviewer keeps the call — the
// manifold is a second witness, not the judge.

import 'dtos.dart' show AiCommitReviewFindingData, ClaimGroundingData;
import 'logos_git.dart' show LogosGit;
import 'review_logos.dart'
    show ReviewScore, composeReviewScore, computeClaimShape;
import 'review_ratchet.dart' show ClaimOutcomeRatchet;
import 'spectral_constants.dart' show phiDecay3;

/// A finding with its spectral grounding attached.
class GroundedFinding {
  const GroundedFinding(this.finding, this.score);

  /// The original finding, now carrying [AiCommitReviewFindingData.grounding].
  final AiCommitReviewFindingData finding;

  /// The full per-axis score (grounding, verifiability, reach, coherence)
  /// plus the composite and learned prior.
  final ReviewScore score;
}

/// Score every finding against the diff and attach the result. Returns
/// findings in input order, each with grounding populated.
List<GroundedFinding> groundFindings({
  required LogosGit engine,
  required String rawDiff,
  required List<AiCommitReviewFindingData> findings,
  required ClaimOutcomeRatchet ratchet,
}) {
  final out = <GroundedFinding>[];
  for (final f in findings) {
    final claimText = [f.title, f.evidence, f.whyItMatters]
        .where((s) => s.trim().isNotEmpty)
        .join('\n');
    final explicit =
        (f.filePath != null && f.filePath!.trim().isNotEmpty) ? {f.filePath!} : null;
    final shape = computeClaimShape(
      engine: engine,
      claimText: claimText,
      diffText: rawDiff,
      explicitClaimPaths: explicit,
    );
    final score = composeReviewScore(shape: shape, ratchet: ratchet);
    out.add(
      GroundedFinding(
        f.withGrounding(
          ClaimGroundingData(
            grounding: shape.grounding,
            verifiability: shape.verifiability,
            reach: shape.reach,
            coherence: shape.coherence,
            symbolCount: shape.symbolCount,
            textLength: shape.textLength,
            composite: score.composite,
            ratchetPrior: score.ratchetPrior,
          ),
        ),
        score,
      ),
    );
  }
  return out;
}

/// Render the `<claim_grounding>` body (no wrapper tag) for the verify
/// pass. '' when there is nothing to ground.
String formatClaimGroundingBlock(List<GroundedFinding> grounded) {
  if (grounded.isEmpty) return '';
  final buf = StringBuffer();
  buf.writeln(
    "The co-change manifold reads each prior-pass finding back against the "
    "diff it claims to describe. grounding: how strongly the finding's named "
    'symbols diffuse into the changed files (1 = co-located, 0 = '
    'disconnected). verifiability: the fraction of the diff that rendered as '
    'readable text. reach: how load-bearing the touched region is in the '
    'graph. A confident finding resting on low grounding is an invitation to '
    're-read the evidence — the structure is a second witness, not the judge.',
  );
  for (final g in grounded) {
    final s = g.score.shape;
    final weak = s.grounding < phiDecay3
        ? '  ← its named symbols barely reach the changed files'
        : '';
    final prior = g.score.ratchetPrior != 0.5
        ? ' prior=${g.score.ratchetPrior.toStringAsFixed(2)}'
        : '';
    buf.writeln(
      '${g.finding.id} grounding=${s.grounding.toStringAsFixed(2)} '
      'verifiability=${s.verifiability.toStringAsFixed(2)} '
      'reach=${s.reach.toStringAsFixed(2)} '
      'coherence=${s.coherence.toStringAsFixed(2)}$prior$weak',
    );
  }
  return buf.toString();
}
