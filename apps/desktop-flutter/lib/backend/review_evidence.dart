// Review-evidence introspection: the structured view of what the code-review
// gather assembles, plus hot-path telemetry. Built by the SAME gather the
// real review runs (`_collectCommitMessageContext`); the review ignores it,
// the `review-evidence` dry-run serialises it. No alternate gather path.

import 'ai_context_engine.dart' show AiProducerTrace;

/// Per-phase timings + a structured-channel summary for one review gather.
/// Cheap enough to fill on every gather (a handful of stopwatches + counts);
/// the real review path simply never reads it.
class GatherDiagnostics {
  // ── Phase timings (microseconds) ─────────────────────────────────
  int gitDerivationMicros = 0;
  int logosDiffusionMicros = 0;
  int diffBundleMicros = 0;
  int producerAssemblyMicros = 0;
  int telemetryAwaitMicros = 0;
  int totalMicros = 0;

  // ── Producer-level trace (which channel cost what, who was empty) ─
  final List<AiProducerTrace> producers = [];

  // ── Diffusion / spectral summary ─────────────────────────────────
  bool diffusionCold = true; // engine never warmed for this review
  bool evidenceNull = true; // diffusion ran but gatherEvidence returned null
  int recurrentIterations = 0;
  bool recurrentConverged = false;
  ({double ctx, double meta, double nbhd, double flow})? partition;
  bool get spectralBasisPresent => partition != null;

  // ── Evidence channel cardinalities ───────────────────────────────
  int rankedCount = 0;
  int residualCount = 0;
  int transportPullCount = 0;
  int metricSidecarCount = 0;
  int inquiryStepCount = 0;
  bool attributionPresent = false;
  double? coherence;
  double? stability;
  double? sourceAlignment;
  double? fieldAlignment;
  double? sourceSurprise;
  double? fieldSurprise;

  /// Human-readable "awkward gaps" — channels that ran but produced
  /// nothing, or signals that were unavailable. This is the list to act on.
  final List<String> gaps = [];

  Map<String, dynamic> toJson() => {
        'timingMicros': {
          'gitDerivation': gitDerivationMicros,
          'logosDiffusion': logosDiffusionMicros,
          'diffBundle': diffBundleMicros,
          'producerAssembly': producerAssemblyMicros,
          'telemetryAwait': telemetryAwaitMicros,
          'total': totalMicros,
        },
        'diffusion': {
          'cold': diffusionCold,
          'evidenceNull': evidenceNull,
          'recurrentIterations': recurrentIterations,
          'recurrentConverged': recurrentConverged,
          'spectralBasisPresent': spectralBasisPresent,
          'partition': partition == null
              ? null
              : {
                  'ctx': partition!.ctx,
                  'meta': partition!.meta,
                  'nbhd': partition!.nbhd,
                  'flow': partition!.flow,
                },
        },
        'channels': {
          'ranked': rankedCount,
          'residuals': residualCount,
          'transportPull': transportPullCount,
          'metricSidecars': metricSidecarCount,
          'inquirySteps': inquiryStepCount,
          'attributionPresent': attributionPresent,
          'coherence': coherence,
          'stability': stability,
          'sourceAlignment': sourceAlignment,
          'fieldAlignment': fieldAlignment,
          'sourceSurprise': sourceSurprise,
          'fieldSurprise': fieldSurprise,
        },
        'producers': [for (final p in producers) p.toJson()],
        'gaps': gaps,
      };
}

/// The full result of a review-evidence dry-run: the structured evidence
/// summary + the EXACT assembled prompt the model would have received. Same
/// `_collectCommitMessageContext` + `_buildCommitReviewPrompt` path as a
/// real review, stopped immediately before the provider call.
class ReviewEvidenceData {
  ReviewEvidenceData({
    required this.branchName,
    required this.scopeLabel,
    required this.statusSummary,
    required this.statSummary,
    required this.diffChars,
    required this.promptChars,
    required this.prompt,
    required this.diagnostics,
  });

  final String branchName;
  final String scopeLabel;
  final String statusSummary;
  final String statSummary;
  final int diffChars;
  final int promptChars;

  /// The complete assembled prompt — diff bundle + every producer section,
  /// XML-tagged, exactly as the LLM would see it.
  final String prompt;

  final GatherDiagnostics diagnostics;

  Map<String, dynamic> toJson() => {
        'branchName': branchName,
        'scopeLabel': scopeLabel,
        'statusSummary': statusSummary,
        'statSummary': statSummary,
        'diffChars': diffChars,
        'promptChars': promptChars,
        'diagnostics': diagnostics.toJson(),
        'prompt': prompt,
      };
}
