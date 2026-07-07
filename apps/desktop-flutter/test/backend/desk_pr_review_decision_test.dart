// Tests for DeskPr's review-decision fold (GitHub-style per-reviewer-latest).
//
// The decision is private (_deriveReviewDecision) but surfaces through the
// PullRequestSummary adapter as `toSummary().reviewDecision`, which is the
// contract every row renderer reads — so we drive it through that.
//
// Invariant under test: only each reviewer's LATEST decisive verdict counts,
// COMMENTED never dismisses a standing decision, and any standing
// CHANGES_REQUESTED outranks any standing APPROVED.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_pr.dart';

DeskThreadEntry _entry(
  String author,
  String verdict, {
  required DateTime at,
}) =>
    DeskThreadEntry(author: author, body: '$verdict from $author', at: at, verdict: verdict);

DeskPr _prWithThread(List<DeskThreadEntry> thread) => DeskPr(
      deskId: 1,
      title: 't',
      body: 'b',
      headRef: 'feature',
      baseRef: 'main',
      state: 'OPEN',
      isDraft: false,
      authorIdentity: 'author',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      thread: thread,
    );

String _decision(List<DeskThreadEntry> thread) =>
    _prWithThread(thread).toSummary().reviewDecision;

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 9);
  final t1 = DateTime.utc(2026, 1, 1, 10);
  final t2 = DateTime.utc(2026, 1, 1, 11);
  final t3 = DateTime.utc(2026, 1, 1, 12);

  group('DeskPr._deriveReviewDecision (via toSummary)', () {
    test('same reviewer: CHANGES_REQUESTED then APPROVED → APPROVED', () {
      expect(
        _decision([
          _entry('alice', 'CHANGES_REQUESTED', at: t0),
          _entry('alice', 'APPROVED', at: t1),
        ]),
        'APPROVED',
      );
    });

    test('CR by A, APPROVED by B → CHANGES_REQUESTED (A still blocks)', () {
      expect(
        _decision([
          _entry('alice', 'CHANGES_REQUESTED', at: t0),
          _entry('bob', 'APPROVED', at: t1),
        ]),
        'CHANGES_REQUESTED',
      );
    });

    test('same reviewer: APPROVED then COMMENTED → still APPROVED', () {
      // COMMENTED does not dismiss a standing APPROVED.
      expect(
        _decision([
          _entry('alice', 'APPROVED', at: t0),
          _entry('alice', 'COMMENTED', at: t1),
        ]),
        'APPROVED',
      );
    });

    test('same reviewer: CR then COMMENTED → still CHANGES_REQUESTED', () {
      // COMMENTED does not dismiss a standing CHANGES_REQUESTED (GitHub rule).
      expect(
        _decision([
          _entry('alice', 'CHANGES_REQUESTED', at: t0),
          _entry('alice', 'COMMENTED', at: t1),
        ]),
        'CHANGES_REQUESTED',
      );
    });

    test('empty thread → \'\'', () {
      expect(_decision(const []), '');
    });

    test('comments-only thread → \'\' (no verdicts)', () {
      expect(
        _decision([
          DeskThreadEntry(author: 'alice', body: 'nit', at: t0),
          DeskThreadEntry(author: 'bob', body: 'lgtm-ish', at: t1),
        ]),
        '',
      );
    });

    test('COMMENTED-only reviews → \'\' (never approves nor blocks)', () {
      expect(
        _decision([
          _entry('alice', 'COMMENTED', at: t0),
          _entry('bob', 'COMMENTED', at: t1),
        ]),
        '',
      );
    });

    test('timestamp ties resolved by position (later entry wins)', () {
      // Both verdicts share t0; the later position (APPROVED) is the
      // reviewer's latest standing state.
      expect(
        _decision([
          _entry('alice', 'CHANGES_REQUESTED', at: t0),
          _entry('alice', 'APPROVED', at: t0),
        ]),
        'APPROVED',
      );
      // And the reverse order under a tie flips the outcome.
      expect(
        _decision([
          _entry('alice', 'APPROVED', at: t0),
          _entry('alice', 'CHANGES_REQUESTED', at: t0),
        ]),
        'CHANGES_REQUESTED',
      );
    });

    test('out-of-order timestamps: latest by time wins, not by position', () {
      // Positionally the APPROVED comes second, but its timestamp (t1) is
      // older than the CHANGES_REQUESTED at t2 — so CR is the latest.
      expect(
        _decision([
          _entry('alice', 'CHANGES_REQUESTED', at: t2),
          _entry('alice', 'APPROVED', at: t1),
        ]),
        'CHANGES_REQUESTED',
      );
    });

    test('two reviewers, each latest counts: A re-approves, B still blocks',
        () {
      expect(
        _decision([
          _entry('alice', 'CHANGES_REQUESTED', at: t0),
          _entry('bob', 'CHANGES_REQUESTED', at: t1),
          _entry('alice', 'APPROVED', at: t2),
          _entry('bob', 'COMMENTED', at: t3), // does not clear bob's CR
        ]),
        'CHANGES_REQUESTED',
      );
    });

    test('all reviewers converge to APPROVED → APPROVED', () {
      expect(
        _decision([
          _entry('alice', 'CHANGES_REQUESTED', at: t0),
          _entry('bob', 'CHANGES_REQUESTED', at: t1),
          _entry('alice', 'APPROVED', at: t2),
          _entry('bob', 'APPROVED', at: t3),
        ]),
        'APPROVED',
      );
    });
  });
}
