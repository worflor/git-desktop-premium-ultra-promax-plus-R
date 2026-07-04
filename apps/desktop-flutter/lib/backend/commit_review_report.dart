import 'dtos.dart';
import 'report_attribution.dart';

/// Render an [AiCommitReviewData] as plain text for the clipboard.
///
/// This is the single definition of the review export, shared by the
/// Changes-page inline pane and the branches PR-review dialog so their
/// two copy buttons can't drift — the same way [renderMuseReport] backs
/// both muse surfaces. Pure: no `Clipboard`, no `BuildContext`, so it is
/// unit-testable in isolation.
///
/// Layout:
///
///     {verdict} | {score}
///     Model: {provider} / {model}      (omitted if no identity recorded)
///     {summary}
///
///     Review Report                    (omitted if the model gave none)
///     {reasoningReport}
///
///     Findings                         (omitted if none)
///     - {title}
///       {filePath | hunkLabel}         (omitted if both absent)
///       Evidence: {evidence}           (omitted if blank)
///       Why: {whyItMatters}            (omitted if blank)
///
///     Observations                     (omitted if none)
///     - {title}
///       {detail}                       (omitted if blank)
String renderCommitReviewReport(AiCommitReviewData review) {
  final buffer = StringBuffer()..writeln('${review.verdict} | ${review.score}');
  // The generating provider/model rides along at the top of the dump, so
  // a pasted review always records which model produced it.
  final model = modelAttributionLine(review.providerId, review.modelId);
  if (model.isNotEmpty) {
    buffer.writeln(model);
  }
  buffer.writeln(review.summary);
  // Skip the Review Report section entirely when the model didn't return
  // reasoning — avoids dumping a stray header with no body.
  if (review.reasoningReport.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Review Report')
      ..writeln(review.reasoningReport);
  }
  if (review.findings.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Findings');
    for (final finding in review.findings) {
      buffer.writeln('- ${finding.title}');
      if (finding.filePath != null || finding.hunkLabel != null) {
        final meta = [
          if (finding.filePath != null) finding.filePath!,
          if (finding.hunkLabel != null) finding.hunkLabel!,
        ].join(' | ');
        buffer.writeln('  $meta');
      }
      if (finding.evidence.trim().isNotEmpty) {
        buffer.writeln('  Evidence: ${finding.evidence}');
      }
      if (finding.whyItMatters.trim().isNotEmpty) {
        buffer.writeln('  Why: ${finding.whyItMatters}');
      }
    }
  }
  if (review.observations.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Observations');
    for (final obs in review.observations) {
      buffer.writeln('- ${obs.title}');
      if (obs.detail.trim().isNotEmpty) {
        buffer.writeln('  ${obs.detail}');
      }
    }
  }
  return buffer.toString().trim();
}
