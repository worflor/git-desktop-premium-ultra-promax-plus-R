// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// The Changes-page review pane and the branches PR-review dialog copy
// the same output. renderCommitReviewReport is the single source of
// truth they both serialize; these tests pin its layout — especially the
// Model attribution line that rides along in every dump — so the two copy
// buttons can't drift.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/commit_review_report.dart';
import 'package:git_desktop/backend/dtos.dart';

AiCommitReviewFindingData _finding(
  String title, {
  String severity = 'medium',
  String evidence = '',
  String whyItMatters = '',
  String origin = 'llm',
  String? filePath,
  String? hunkLabel,
}) =>
    AiCommitReviewFindingData(
      id: title,
      severity: severity,
      title: title,
      evidence: evidence,
      whyItMatters: whyItMatters,
      origin: origin,
      filePath: filePath,
      hunkLabel: hunkLabel,
    );

AiCommitReviewData _review({
  String providerId = 'anthropic',
  String modelId = 'claude-opus-4-8',
  String verdict = 'ship',
  int score = 82,
  String summary = 'Looks solid.',
  String reasoningReport = '',
  List<AiCommitReviewFindingData> findings = const [],
  List<AiCommitReviewObservationData> observations = const [],
}) =>
    AiCommitReviewData(
      providerId: providerId,
      modelId: modelId,
      scopeLabel: 'staged changes',
      promptCharacters: 0,
      diffCharacters: 0,
      verdict: verdict,
      score: score,
      summary: summary,
      reasoningReport: reasoningReport,
      findings: findings,
      observations: observations,
      twoStepEnabled: false,
      hasVerificationTrace: false,
    );

void main() {
  group('renderCommitReviewReport', () {
    test('names the provider and model right under the verdict header', () {
      final text = renderCommitReviewReport(_review());
      expect(text, startsWith('ship | 82\nModel: anthropic / claude-opus-4-8\n'));
    });

    test('full report carries header, model, summary, findings, observations',
        () {
      final text = renderCommitReviewReport(_review(
        reasoningReport: 'The diff narrows a race window.',
        findings: [
          _finding('Null deref on empty list',
              severity: 'high',
              evidence: 'line 12 dereferences head',
              whyItMatters: 'crashes on empty input',
              filePath: 'lib/x.dart',
              hunkLabel: '@@ -10,6 +10,7 @@'),
        ],
        observations: [
          const AiCommitReviewObservationData(
            id: 'o1',
            title: 'Consider a helper',
            detail: 'The mapping repeats three times.',
          ),
        ],
      ));
      expect(text, '''
ship | 82
Model: anthropic / claude-opus-4-8
Looks solid.

Review Report
The diff narrows a race window.

Findings
- Null deref on empty list
  lib/x.dart | @@ -10,6 +10,7 @@
  Evidence: line 12 dereferences head
  Why: crashes on empty input

Observations
- Consider a helper
  The mapping repeats three times.''');
    });

    test('Review Report section is omitted when the model gave no reasoning',
        () {
      final text = renderCommitReviewReport(_review());
      expect(text.contains('Review Report'), isFalse);
    });

    test('Findings and Observations headers only appear when populated', () {
      final text = renderCommitReviewReport(_review());
      expect(text.contains('Findings'), isFalse);
      expect(text.contains('Observations'), isFalse);
    });

    test('a finding with no location omits the indented meta line', () {
      final text = renderCommitReviewReport(_review(
        findings: [_finding('Bare finding')],
      ));
      expect(text, contains('- Bare finding'));
      // A bare finding emits only its title bullet — no indented
      // location/evidence/why lines follow it.
      expect(text.split('\n').any((l) => l.startsWith('  ')), isFalse);
    });

    test('Model line is dropped when the snapshot recorded no identity', () {
      final text =
          renderCommitReviewReport(_review(providerId: '', modelId: ''));
      expect(text.contains('Model:'), isFalse);
      expect(text, startsWith('ship | 82\n'));
    });

    test('output is trimmed — no trailing blank line', () {
      final text = renderCommitReviewReport(_review(
        observations: [
          const AiCommitReviewObservationData(id: 'o', title: 'T', detail: ''),
        ],
      ));
      expect(text, isNot(endsWith('\n')));
    });
  });
}
