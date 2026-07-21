// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// GitLab CLI integration — glab.dart shells out to the `glab` binary and
// parses its JSON stdout (same shape as gh.dart, just a different CLI and a
// different wire vocabulary). Unlike gitea_api.dart (HTTP, testable end to
// end against a local fake server), there is no hermetic way to drive the
// *subprocess* boundary here without depending on a real `glab` install —
// Process.run resolves the binary via the ambient PATH/environment that
// runForgeCli inherits, which a Dart test cannot safely override per-call.
//
// So this suite targets the actual testable surface: the pure
// JSON(Map/List) -> DTO mapping functions that normalize GitLab's field
// names onto the shared forge-neutral types (PullRequestSummary,
// IssueSummary, RemoteComment, CheckSummary). Those functions used to be
// private (`_mrSummaryFromGlab` etc.); this suite's existence is the reason
// they were promoted to top-level public functions in glab.dart — the
// smallest public seam that takes real Map/String input, mirroring how
// remote_types.dart already exposes `parseAssigneeLogins` / `parseRemoteDate`
// / `PullRequestSummary.fromJson` for gh.dart's GitHub-shaped JSON.
//
// Left genuinely untested (subprocess-entangled, no pure seam):
//  - glabStatus / glabWhoami: spawn `glab --version` / `glab auth status`
//    directly and regex-parse the username out of stderr text. The regex
//    itself is trivial; the entanglement is the live Process.run call.
//  - createGlabMr / createGlabIssue: regex-extract the new MR/issue number
//    from `glab mr create`/`glab issue create`'s stdout URL, but only after
//    a real subprocess call.
//  - every `Future<GitResult<...>>` wrapper (listMergeRequests, getMergeRequest,
//    listGlabIssues, ...): each is just `_glab(...)` (a Process.run call)
//    followed by a try/catch around the mapper this suite tests directly.
//    Their exitCode!=0 -> GitResult.err(stderr) branch is one line with no
//    parsing logic to break, and their try/catch is exercised implicitly by
//    every "the mapper throws on X" case below (that's exactly what those
//    catches are for).
//
// Three genuine bugs turned up while writing this coverage and were fixed
// alongside it (see glab.dart):
//  1. `changes_count` on a GitLab merge request is documented by the GitLab
//     API as a STRING (e.g. "3", or the "1000+" sentinel for huge diffs),
//     not a number. The old code did `j['changes_count'] as num?`, which
//     THROWS on a non-null String instead of falling through the `??`
//     default (a cast only yields null when the source itself is null) —
//     so every real merge request row would fail to parse the moment
//     GitLab populated this field, which is effectively always. Fixed with
//     `glabChangesCount`, covered below.
//  2. `j['author']` (and the nested `approved_by[].user`) was cast with
//     `as Map<String, dynamic>?`, which throws on a non-null, wrong-shaped
//     value, unlike the `is Map<String, dynamic>` pattern remote_types.dart
//     already uses for the identical GitHub field. Hardened to match.
//  3. A follow-up review asked: `changes_count` was hardened, but is it the
//     *only* numeric field with this problem? No — reading every mapper in
//     glab.dart turned up 7 more numeric fields (`iid`, `user_notes_count`,
//     `additions`, `deletions` on mrSummaryFromGlab; `iid`,
//     `user_notes_count` on issueSummaryFromGlab; `duration` on
//     checkFromGlabJob) doing the same unsafe `(j['x'] as num? ?? 0)
//     .toInt()` / bare `as num?` cast — same bug class, just not yet fixed.
//     ROOT-fixed by promoting `glabChangesCount`'s tolerant body into a
//     shared `glabIntOrNull` helper and routing all 8 numeric sites through
//     it, so the whole class is unrepresentable instead of patched
//     field-by-field. The "numeric-field family" section near the bottom of
//     this file sweeps all 8 fields with the same adversarial value set
//     (string, the "N+" sentinel, bool, map, list, plus int/null controls),
//     table-driven by `_NumericFieldSpec`/`_FieldCase` — every case is now a
//     live passing contract test, not a skipped bug repro.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/glab.dart';
import 'package:git_desktop/backend/remote_types.dart';

import '../support/gen.dart';
import '../support/prop.dart';

/// `login -> state` view of a reviewer list, order-independent — the
/// mapper's own dedup/precedence rule (approved wins over pending) is what
/// matters, not the incidental Map-insertion order the implementation
/// happens to produce.
Map<String, String> _reviewerStates(List<PrReviewer> reviewers) =>
    {for (final r in reviewers) r.login: r.state};

// -----------------------------------------------------------------------
// Parametrized robustness sweep over the WHOLE numeric-cast family.
//
// glab.dart has 8 numeric fields spread across its 3 mappers (confirmed by
// reading the source, not guessed): mrSummaryFromGlab's `iid` -> number,
// `user_notes_count` -> conversationCount, `additions`, `deletions`, and
// `changes_count` -> changedFiles; issueSummaryFromGlab's `iid` -> number
// and `user_notes_count` -> commentCount; checkFromGlabJob's `duration`.
// All 8 now route through the shared `glabIntOrNull` helper (promoted from
// `glabChangesCount`'s originally-lone-hardened body), so every field
// degrades the same way instead of throwing an uncaught TypeError the
// instant it's present with a non-num, non-null runtime type (a cast only
// falls through `??` when the source is null, never when it's merely the
// wrong type).
//
// This harness is table-driven so future numeric fields get the same
// coverage almost for free: add one `_NumericFieldSpec` entry instead of
// hand-writing a new set of tests.
// -----------------------------------------------------------------------

/// One adversarial-or-control value to try against a single numeric field,
/// paired with the exact value the (now-uniformly-hardened) mapper must
/// produce for it. Every case here is a passing contract, not a bug repro.
class _FieldCase {
  final String label;
  final Object? value;
  final Object? expected;

  const _FieldCase(this.label, this.value, this.expected);
}

/// Case set shared by every int-valued "count" field that falls back to
/// `0` via `?? 0` — mrSummaryFromGlab's user_notes_count/additions/
/// deletions/changes_count, and issueSummaryFromGlab's user_notes_count.
/// (`iid` used to be in this family too, but it is the IDENTITY field: an
/// unreadable one now rejects the whole row instead of falling back to 0 —
/// see `_identityFieldCases` below, which is NOT shared with this table.)
/// All of these still route through `glabIntOrNull`, the same parser
/// `changes_count` was hardened with first, so they share one case table: a
/// digit string and the "N+" sentinel parse to their numeric value (the
/// real GitLab wire shape for `changes_count`; defensive hardening for the
/// rest, in case a future glab version or a differently configured GitLab
/// instance sends the same shape elsewhere); anything unparseable (bool,
/// Map, List) falls back to 0, same as a null value would.
List<_FieldCase> _countFieldCases() => [
      const _FieldCase('String digit "5"', '5', 5),
      const _FieldCase('String "1000+" sentinel', '1000+', 1000),
      const _FieldCase('bool true', true, 0),
      const _FieldCase('nested map {}', <String, dynamic>{}, 0),
      const _FieldCase('empty list []', <dynamic>[], 0),
      const _FieldCase('control: normal int', 5, 5),
      const _FieldCase('control: null', null, 0),
    ];

/// Case set for checkFromGlabJob's `duration`: same shared `glabIntOrNull`
/// parser, but no `?? 0` fallback — a null/unparseable duration stays
/// `null` (never `Duration.zero`), so the unparseable and null-control
/// cases differ from `_countFieldCases`.
List<_FieldCase> _durationFieldCases() => [
      const _FieldCase('String digit "5"', '5', 5),
      const _FieldCase('String "1000+" sentinel', '1000+', 1000),
      const _FieldCase('bool true', true, null),
      const _FieldCase('nested map {}', <String, dynamic>{}, null),
      const _FieldCase('empty list []', <dynamic>[], null),
      const _FieldCase('control: normal int', 5, 5),
      const _FieldCase('control: null', null, null),
    ];

/// Case set for the IDENTITY field itself (mrSummaryFromGlab's `iid` and
/// issueSummaryFromGlab's `iid`, both -> `number`). Unlike every other
/// numeric field (which falls back to 0 via `?? 0`), an unreadable identity
/// now REJECTS the whole row (the mapper returns null) rather than
/// fabricating an actionable #0 — mirroring gh.dart's
/// `PullRequestSummary.fromJson`/`IssueSummary.fromJson` strict-number rule.
/// So "expected" here is either the parsed int (row survives) or `null`
/// (row rejected), never a fallback 0.
List<_FieldCase> _identityFieldCases() => [
      const _FieldCase('String digit "5"', '5', 5),
      const _FieldCase('String "1000+" sentinel', '1000+', 1000),
      const _FieldCase('bool true', true, null),
      const _FieldCase('nested map {}', <String, dynamic>{}, null),
      const _FieldCase('empty list []', <dynamic>[], null),
      const _FieldCase('control: normal int', 5, 5),
      const _FieldCase('control: null', null, null),
    ];

/// One numeric field to sweep: which mapper, which JSON key, how to reach
/// its parsed value from the mapper's return type, and the case table to
/// run against it. `minimalValidJson` is the smallest payload that reaches
/// this field's parse without erroring on anything else first. For
/// mrSummaryFromGlab/issueSummaryFromGlab fields that means `{'iid': 1}` —
/// a valid identity so the row survives to exercise the field under test
/// (an identity-less row is now rejected outright); checkFromGlabJob has no
/// identity concept, so `{}` still suffices there.
class _NumericFieldSpec {
  final String groupLabel;
  final String fieldKey;
  final Map<String, dynamic> Function() minimalValidJson;
  final Object? Function(Map<String, dynamic> json) getResult;
  final List<_FieldCase> cases;

  _NumericFieldSpec({
    required this.groupLabel,
    required this.fieldKey,
    required this.minimalValidJson,
    required this.getResult,
    required this.cases,
  });
}

final List<_NumericFieldSpec> _numericFieldSpecs = [
  _NumericFieldSpec(
    groupLabel:
        'mrSummaryFromGlab: user_notes_count -> conversationCount',
    fieldKey: 'user_notes_count',
    minimalValidJson: () => <String, dynamic>{'iid': 1},
    getResult: (j) => mrSummaryFromGlab(j)!.conversationCount,
    cases: _countFieldCases(),
  ),
  _NumericFieldSpec(
    groupLabel: 'mrSummaryFromGlab: additions',
    fieldKey: 'additions',
    minimalValidJson: () => <String, dynamic>{'iid': 1},
    getResult: (j) => mrSummaryFromGlab(j)!.additions,
    cases: _countFieldCases(),
  ),
  _NumericFieldSpec(
    groupLabel: 'mrSummaryFromGlab: deletions',
    fieldKey: 'deletions',
    minimalValidJson: () => <String, dynamic>{'iid': 1},
    getResult: (j) => mrSummaryFromGlab(j)!.deletions,
    cases: _countFieldCases(),
  ),
  _NumericFieldSpec(
    groupLabel: 'mrSummaryFromGlab: changes_count -> changedFiles '
        '(hardened via glabChangesCount / glabIntOrNull)',
    fieldKey: 'changes_count',
    minimalValidJson: () => <String, dynamic>{'iid': 1},
    getResult: (j) => mrSummaryFromGlab(j)!.changedFiles,
    cases: _countFieldCases(),
  ),
  _NumericFieldSpec(
    groupLabel: 'issueSummaryFromGlab: user_notes_count -> commentCount',
    fieldKey: 'user_notes_count',
    minimalValidJson: () => <String, dynamic>{'iid': 1},
    getResult: (j) => issueSummaryFromGlab(j)!.commentCount,
    cases: _countFieldCases(),
  ),
  _NumericFieldSpec(
    groupLabel: 'checkFromGlabJob: duration',
    fieldKey: 'duration',
    minimalValidJson: () => <String, dynamic>{},
    getResult: (j) => checkFromGlabJob(j).duration?.inSeconds,
    cases: _durationFieldCases(),
  ),
];

void main() {
  // ---------------------------------------------------------------------
  // Merge requests — realistic `glab mr list/view -F json` shapes.
  // ---------------------------------------------------------------------
  group('mrSummaryFromGlab — faithful GitLab field mapping', () {
    test('a realistic opened MR maps every field with GitLab\'s own names',
        () {
      final json = <String, dynamic>{
        'iid': 42,
        'title': '  Add dark mode  ',
        'source_branch': 'feature/dark-mode',
        'target_branch': 'main',
        'state': 'opened',
        'draft': false,
        'author': {'id': 7, 'username': 'octocat', 'name': 'Oc Cat'},
        'user_notes_count': 5,
        'updated_at': '2026-05-01T12:00:00.000Z',
        'changes_count': '7', // real GitLab shape: a STRING, not a number
        'merge_status': 'can_be_merged',
        'approved': true,
        'reviewers': [
          {'username': 'bob'}
        ],
        'approved_by': [
          {
            'user': {'username': 'alice'}
          }
        ],
        'labels': ['bug', 'priority::1'],
        'assignees': [
          {'username': 'carol'}
        ],
      };

      final s = mrSummaryFromGlab(json)!;

      // iid -> number, NOT GitLab's project-global `id`.
      expect(s.number, 42);
      expect(s.title, 'Add dark mode');
      // source_branch/target_branch -> headRef/baseRef, not GH's
      // headRefName/baseRefName.
      expect(s.headRef, 'feature/dark-mode');
      expect(s.baseRef, 'main');
      expect(s.state, 'OPEN');
      expect(s.isDraft, isFalse);
      // author.username -> authorLogin, not GH's author.login.
      expect(s.authorLogin, 'octocat');
      expect(s.conversationCount, 5);
      expect(s.updatedAt, DateTime.parse('2026-05-01T12:00:00.000Z'));
      // The bug-fix assertion: a STRING changes_count must parse as an int,
      // not throw and not silently become 0.
      expect(s.changedFiles, 7);
      expect(s.mergeable, 'MERGEABLE');
      expect(s.reviewDecision, 'APPROVED');
      expect(_reviewerStates(s.reviewers), {
        'bob': 'PENDING',
        'alice': 'APPROVED',
      });
      expect(s.labels, ['bug', 'priority::1']);
      expect(s.assignees, ['carol']);
    });

    test('state: opened/closed/merged map to OPEN/CLOSED/MERGED', () {
      // Non-identity field under test -> a valid `iid` is added so the row
      // survives (an identity-less row is now rejected outright).
      expect(mrSummaryFromGlab({'iid': 1, 'state': 'opened'})!.state, 'OPEN');
      expect(
          mrSummaryFromGlab({'iid': 1, 'state': 'closed'})!.state, 'CLOSED');
      expect(
          mrSummaryFromGlab({'iid': 1, 'state': 'merged'})!.state, 'MERGED');
      // Unrecognized/future GitLab state -> safe default, not a crash.
      expect(mrSummaryFromGlab({'iid': 1, 'state': 'locked'})!.state, 'OPEN');
    });

    test('merge_status: can_be_merged/cannot_be_merged map to '
        'MERGEABLE/CONFLICTING; has_conflicts is the fallback', () {
      expect(
          mrSummaryFromGlab({'iid': 1, 'merge_status': 'can_be_merged'})!
              .mergeable,
          'MERGEABLE');
      expect(
          mrSummaryFromGlab({'iid': 1, 'merge_status': 'cannot_be_merged'})!
              .mergeable,
          'CONFLICTING');
      // merge_status absent (or an unrecognized value, e.g. 'unchecked')
      // falls back to the has_conflicts boolean.
      expect(mrSummaryFromGlab({'iid': 1, 'has_conflicts': true})!.mergeable,
          'CONFLICTING');
      expect(mrSummaryFromGlab({'iid': 1})!.mergeable, 'UNKNOWN');
      expect(
          mrSummaryFromGlab({
            'iid': 1,
            'merge_status': 'unchecked',
            'has_conflicts': false
          })!
              .mergeable,
          'UNKNOWN');
    });

    test('reviewer/approval precedence: approved_by wins over a pending '
        'reviewer entry for the same user', () {
      final s = mrSummaryFromGlab({
        'iid': 1,
        'reviewers': [
          {'username': 'alice'},
          {'username': 'bob'},
        ],
        'approved_by': [
          {'username': 'alice'}, // flat shape (no nested `user`)
        ],
      })!;
      expect(_reviewerStates(s.reviewers), {
        'alice': 'APPROVED', // promoted, not left PENDING
        'bob': 'PENDING',
      });
    });

    test('does not accidentally read GitHub-shaped fields', () {
      // A payload shaped like GH's PR JSON (number/login/headRefName) rather
      // than GitLab's (iid/username/source_branch) must NOT leak through —
      // proves the mapper is keyed on GitLab's real field names, not
      // coincidentally compatible with gh.dart's. `iid` is set so the row
      // isn't dropped for lacking identity; GH's `number` must be ignored
      // in favor of it.
      final s = mrSummaryFromGlab({
        'iid': 1,
        'number': 99,
        'headRefName': 'gh-feature',
        'baseRefName': 'gh-main',
        'author': {'login': 'gh-user'},
        'state': 'OPEN', // GH's already-uppercase shape
      })!;
      expect(s.number, 1); // 'iid' wins; GH's 'number' (99) is ignored
      expect(s.headRef, ''); // 'source_branch' is absent
      expect(s.baseRef, '');
      expect(s.authorLogin, ''); // author has 'login', not 'username'
      // 'OPEN' lowercased is 'open', which matches none of
      // opened/closed/merged -> falls through to the default.
      expect(s.state, 'OPEN');
    });
  });

  group('mrSummaryFromGlab — malformed-shape robustness', () {
    test('an identity-less MR json is rejected (returns null), not '
        'fabricated as MR #0', () {
      expect(mrSummaryFromGlab(const {}), isNull);
    });

    test('a valid iid + every OTHER field explicitly null -> sane defaults, '
        'no throw', () {
      // `iid` is set (RULE 2: this test's intent is every OTHER field's
      // null-safety, not the identity field itself, which has its own
      // dedicated rejection coverage above).
      final s = mrSummaryFromGlab({
        'iid': 1,
        'title': null,
        'source_branch': null,
        'target_branch': null,
        'state': null,
        'draft': null,
        'author': null,
        'user_notes_count': null,
        'updated_at': null,
        'changes_count': null,
        'changed_files': null,
        'merge_status': null,
        'has_conflicts': null,
        'approved': null,
        'reviewers': null,
        'approved_by': null,
        'labels': null,
        'assignees': null,
      })!;
      expect(s.number, 1);
      expect(s.title, '');
      expect(s.headRef, '');
      expect(s.baseRef, '');
      expect(s.state, 'OPEN');
      expect(s.isDraft, isFalse);
      expect(s.authorLogin, '');
      expect(s.conversationCount, 0);
      expect(s.additions, 0);
      expect(s.deletions, 0);
      expect(s.changedFiles, 0);
      expect(s.mergeable, 'UNKNOWN');
      expect(s.reviewDecision, '');
      expect(s.reviewers, isEmpty);
      expect(s.labels, isEmpty);
      expect(s.assignees, isEmpty);
      expect(s.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('a non-map author does not throw (hardened is-Map check)', () {
      expect(
          () => mrSummaryFromGlab({'iid': 1, 'author': 'not-a-map'}),
          returnsNormally);
      expect(
          mrSummaryFromGlab({'iid': 1, 'author': 'not-a-map'})!.authorLogin,
          '');
      expect(mrSummaryFromGlab({'iid': 1, 'author': 123})!.authorLogin, '');
      expect(
          mrSummaryFromGlab({'iid': 1, 'author': <dynamic>[]})!.authorLogin,
          '');
    });

    test('reviewers/approved_by shaped as a Map instead of a List does not '
        'throw (hardened is-List check)', () {
      expect(
          () => mrSummaryFromGlab({
                'iid': 1,
                'reviewers': {'not': 'a list'},
                'approved_by': {'not': 'a list'},
              }),
          returnsNormally);
      final s = mrSummaryFromGlab({
        'iid': 1,
        'reviewers': {'not': 'a list'},
        'approved_by': {'not': 'a list'},
      })!;
      expect(s.reviewers, isEmpty);
    });

    test('approved_by entries with a non-map nested `user` do not throw', () {
      expect(
          () => mrSummaryFromGlab({
                'iid': 1,
                'approved_by': [
                  {'user': 'not-a-map'}
                ],
              }),
          returnsNormally);
      final s = mrSummaryFromGlab({
        'iid': 1,
        'approved_by': [
          {'user': 'not-a-map'}
        ],
      })!;
      // No username resolvable from either the flat or nested shape ->
      // dropped, not a phantom empty-login reviewer.
      expect(s.reviewers, isEmpty);
    });
  });

  group('glabChangesCount — GitLab\'s string-typed changes_count (regression)', () {
    test('accepts a plain number defensively', () {
      expect(glabChangesCount(5), 5);
      expect(glabChangesCount(5.0), 5);
    });

    test('accepts the real GitLab shape: a digit string', () {
      expect(glabChangesCount('12'), 12);
      expect(glabChangesCount('0'), 0);
    });

    test('accepts the "N+" sentinel for very large diffs', () {
      expect(glabChangesCount('1000+'), 1000);
    });

    test('non-numeric garbage and null both yield null (caller falls back)',
        () {
      expect(glabChangesCount('N/A'), isNull);
      expect(glabChangesCount(null), isNull);
      expect(glabChangesCount(true), isNull);
    });

    test('mrSummaryFromGlab: string changes_count no longer throws and '
        'produces the right count (was: crashes the whole MR list parse)',
        () {
      expect(() => mrSummaryFromGlab({'iid': 1, 'changes_count': '3'}),
          returnsNormally);
      expect(
          mrSummaryFromGlab({'iid': 1, 'changes_count': '3'})!.changedFiles,
          3);
      expect(
          mrSummaryFromGlab({'iid': 1, 'changes_count': '1000+'})!
              .changedFiles,
          1000);
    });

    test('falls back to changed_files, then to 0', () {
      expect(mrSummaryFromGlab({'iid': 1, 'changed_files': 4})!.changedFiles,
          4);
      expect(
          mrSummaryFromGlab({
            'iid': 1,
            'changes_count': 'garbage',
            'changed_files': 9
          })!
              .changedFiles,
          9);
      expect(mrSummaryFromGlab({'iid': 1})!.changedFiles, 0);
    });
  });

  // ---------------------------------------------------------------------
  // Issues — realistic `glab issue list/view -F json` shapes.
  // ---------------------------------------------------------------------
  group('issueSummaryFromGlab — faithful GitLab field mapping', () {
    test('a realistic issue maps every field', () {
      final json = <String, dynamic>{
        'iid': 17,
        'title': 'Crash on startup',
        'state': 'opened',
        'author': {'username': 'dave'},
        'labels': ['bug', 'p0'],
        'assignees': [
          {'username': 'erin'}
        ],
        'user_notes_count': 3,
        'updated_at': '2026-04-15T09:30:00Z',
      };
      final s = issueSummaryFromGlab(json)!;
      expect(s.number, 17);
      expect(s.title, 'Crash on startup');
      expect(s.state, 'OPEN');
      expect(s.authorLogin, 'dave');
      expect(s.labels, ['bug', 'p0']);
      expect(s.assignees, ['erin']);
      expect(s.commentCount, 3);
      expect(s.updatedAt, DateTime.parse('2026-04-15T09:30:00Z'));
    });

    test('issues have no merged state — anything but opened is CLOSED', () {
      // Non-identity field under test -> a valid `iid` is added so the row
      // survives.
      expect(
          issueSummaryFromGlab({'iid': 1, 'state': 'opened'})!.state,
          'OPEN');
      expect(
          issueSummaryFromGlab({'iid': 1, 'state': 'closed'})!.state,
          'CLOSED');
      // No third bucket exists for issues (unlike MRs' merged).
      expect(
          issueSummaryFromGlab({'iid': 1, 'state': 'anything-else'})!.state,
          'CLOSED');
      // Missing state defaults to 'opened' -> OPEN, matching the MR default.
      expect(issueSummaryFromGlab({'iid': 1})!.state, 'OPEN');
    });
  });

  // ---------------------------------------------------------------------
  // Comments — shared by MR notes and issue notes.
  // ---------------------------------------------------------------------
  group('commentFromGlab', () {
    test('maps author.username, trims body, parses created_at', () {
      final c = commentFromGlab({
        'author': {'username': 'frank'},
        'body': '  looks good to me  ',
        'created_at': '2026-01-02T03:04:05Z',
      });
      expect(c.authorLogin, 'frank');
      expect(c.body, 'looks good to me');
      expect(c.createdAt, DateTime.parse('2026-01-02T03:04:05Z'));
    });

    test('missing author -> empty login, no throw', () {
      final c = commentFromGlab({'body': 'hi'});
      expect(c.authorLogin, '');
    });

    test('malformed author (not a map) does not throw', () {
      // Regression for the `as Map<String,dynamic>?` -> `is Map` hardening:
      // a non-map author used to be a TypeError, now degrades to ''.
      expect(() => commentFromGlab({'author': 'not-a-map', 'body': 'x'}),
          returnsNormally);
      expect(commentFromGlab({'author': 'not-a-map'}).authorLogin, '');
      expect(commentFromGlab({'author': 42}).authorLogin, '');
      expect(commentFromGlab({'author': <dynamic>[]}).authorLogin, '');
    });
  });

  // ---------------------------------------------------------------------
  // CI jobs/pipelines — `glab ci list -F json` shapes.
  // ---------------------------------------------------------------------
  group('checkFromGlabJob — CI status/conclusion mapping', () {
    test('success/failed/canceled/skipped are completed with a conclusion',
        () {
      expect(checkFromGlabJob({'status': 'success'}).status, 'completed');
      expect(checkFromGlabJob({'status': 'success'}).conclusion, 'success');
      expect(checkFromGlabJob({'status': 'failed'}).status, 'completed');
      expect(checkFromGlabJob({'status': 'failed'}).conclusion, 'failure');
      expect(checkFromGlabJob({'status': 'canceled'}).conclusion, 'cancelled');
      expect(checkFromGlabJob({'status': 'skipped'}).conclusion, 'skipped');
    });

    test('running is in_progress with no conclusion yet', () {
      final c = checkFromGlabJob({'status': 'running'});
      expect(c.status, 'in_progress');
      expect(c.conclusion, isNull);
    });

    test('pending/created/waiting_for_resource are queued', () {
      for (final s in ['pending', 'created', 'waiting_for_resource']) {
        final c = checkFromGlabJob({'status': s});
        expect(c.status, 'queued', reason: 'status=$s');
        expect(c.conclusion, isNull, reason: 'status=$s');
      }
    });

    test('an unrecognized status defaults to queued, not a crash', () {
      final c = checkFromGlabJob({'status': 'some-future-gitlab-status'});
      expect(c.status, 'queued');
      expect(c.conclusion, isNull);
    });

    test('name falls back to ref when the job has no name', () {
      expect(checkFromGlabJob({'name': 'unit-tests', 'ref': 'main'}).name,
          'unit-tests');
      expect(checkFromGlabJob({'ref': 'main'}).name, 'main');
      expect(checkFromGlabJob({}).name, '');
    });

    test('duration in whole seconds; absent duration is null', () {
      expect(checkFromGlabJob({'duration': 45.7}).duration,
          const Duration(seconds: 45));
      expect(checkFromGlabJob({'status': 'success'}).duration, isNull);
    });
  });

  // ---------------------------------------------------------------------
  // Shared list-shaped helpers.
  // ---------------------------------------------------------------------
  group('glabLabels — GitLab returns labels as plain strings, not objects',
      () {
    test('passes through a real GitLab label list', () {
      expect(glabLabels(['bug', 'needs-triage']), ['bug', 'needs-triage']);
    });

    test('drops empty strings', () {
      expect(glabLabels(['bug', '', 'wip']), ['bug', 'wip']);
    });

    test('a GitHub-shaped label list (objects with `name`) yields no labels, '
        'not a crash', () {
      // Silently ignoring the wrong shape (rather than corrupting real
      // GitLab data) is the intended degrade — this pins that behavior.
      expect(glabLabels([
        {'name': 'bug'}
      ]), isEmpty);
    });

    test('non-list input -> empty, no throw', () {
      expect(glabLabels(null), isEmpty);
      expect(glabLabels('bug'), isEmpty);
      expect(glabLabels({'name': 'bug'}), isEmpty);
    });
  });

  group('glabAssigneeLogins', () {
    test('extracts username from each assignee object', () {
      expect(
          glabAssigneeLogins([
            {'username': 'gina'},
            {'username': 'hank'},
          ]),
          ['gina', 'hank']);
    });

    test('drops entries with a missing/blank username', () {
      expect(
          glabAssigneeLogins([
            {'username': ''},
            {'id': 1},
            {'username': 'ivan'},
          ]),
          ['ivan']);
    });

    test('non-list input, and list of non-maps, -> empty, no throw', () {
      expect(glabAssigneeLogins(null), isEmpty);
      expect(glabAssigneeLogins('gina'), isEmpty);
      expect(glabAssigneeLogins(['gina', 'hank']), isEmpty);
    });
  });

  group('parseGlabDate', () {
    test('parses a real GitLab ISO-8601 timestamp', () {
      expect(parseGlabDate('2026-03-04T05:06:07.000Z'),
          DateTime.parse('2026-03-04T05:06:07.000Z'));
    });

    test('unparseable string, null, and wrong types all yield the epoch', () {
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      expect(parseGlabDate('not-a-date'), epoch);
      expect(parseGlabDate(null), epoch);
      expect(parseGlabDate(12345), epoch); // a number, not an ISO string
    });
  });

  group('countGlabDiffLines — per-file added/removed line counts', () {
    const diff = '--- a/lib/foo.dart\n'
        '+++ b/lib/foo.dart\n'
        '@@ -1,3 +1,4 @@\n'
        ' unchanged line\n'
        '-old line one\n'
        '-old line two\n'
        '+new line one\n'
        '+new line two\n'
        '+new line three\n';

    test('counts content lines, excludes the --- / +++ file headers', () {
      expect(countGlabDiffLines(diff, '+'), 3);
      expect(countGlabDiffLines(diff, '-'), 2);
    });

    test('a line starting with only two of the prefix char still counts', () {
      // '++foo' does not start with '+++', so it is content, not a header.
      expect(countGlabDiffLines('++foo\n+bar\n', '+'), 2);
    });

    test('empty diff and no-match diff both yield 0', () {
      expect(countGlabDiffLines('', '+'), 0);
      expect(countGlabDiffLines('no plus or minus lines here\n', '+'), 0);
    });
  });

  // ---------------------------------------------------------------------
  // Unicode / hostile content — must survive the mapping unmangled.
  // ---------------------------------------------------------------------
  group('unicode + hostile content pass through unmangled', () {
    const probes = <String>[
      '👨‍👩‍👧‍👦 family MR', // multi-codepoint ZWJ emoji
      'مرحبا بالعالم', // Arabic (RTL)
      '日本語のテスト', // CJK
      "<script>alert('xss')</script>", // angle brackets + quotes
    ];

    for (var i = 0; i < probes.length; i++) {
      final probe = probes[i];
      test('probe #$i survives mrSummaryFromGlab / issueSummaryFromGlab / '
          'commentFromGlab', () {
        final mr = mrSummaryFromGlab({
          'iid': 1,
          'title': probe,
          'author': {'username': probe},
          'labels': [probe],
        })!;
        expect(mr.title, probe);
        expect(mr.authorLogin, probe);
        expect(mr.labels, [probe]);

        final issue = issueSummaryFromGlab({'iid': 1, 'title': probe})!;
        expect(issue.title, probe);

        final comment = commentFromGlab({'body': probe});
        expect(comment.body, probe);
      });
    }
  });

  // ---------------------------------------------------------------------
  // Property-based sweep over well-typed-but-adversarial-content MR JSON:
  // never throws, and changedFiles/number/title stay internally consistent
  // regardless of which real-world shape changes_count arrives in.
  // ---------------------------------------------------------------------
  group('mrSummaryFromGlab — fuzz: well-typed hostile content never throws',
      () {
    test('200+ random MRs with unicode-hostile strings and mixed '
        'changes_count shapes all map cleanly', () {
      final title = genUnicodeHostile(maxLen: 16);
      final username = genUnicodeHostile(maxLen: 12);
      Map<String, dynamic> genMr(Rng rng) {
        final changesCountShape = rng.pick(const ['int', 'digitString', 'plus', 'garbage']);
        final n = rng.intBetween(0, 999);
        final Object changesCount = switch (changesCountShape) {
          'int' => n,
          'digitString' => '$n',
          'plus' => '$n+',
          _ => 'unknown',
        };
        return {
          'iid': rng.intBetween(0, 1000000),
          'title': title(rng),
          'source_branch': username(rng),
          'target_branch': username(rng),
          'state': rng.pick(const ['opened', 'closed', 'merged', 'weird']),
          'draft': rng.nextBool(),
          'author': {'username': username(rng)},
          'user_notes_count': rng.intBetween(0, 10000),
          'updated_at': rng.pick(const [
            '2026-01-01T00:00:00Z',
            'not-a-date',
            '',
          ]),
          'changes_count': changesCount,
          'merge_status': rng.pick(const [
            'can_be_merged',
            'cannot_be_merged',
            'unchecked',
            ''
          ]),
          'approved': rng.nextBool(),
          'reviewers': <Map<String, dynamic>>[
            {'username': username(rng)}
          ],
          'approved_by': <Map<String, dynamic>>[],
          'labels': <String>[title(rng)],
          'assignees': <Map<String, dynamic>>[
            {'username': username(rng)}
          ],
        };
      }

      forAll<Map<String, dynamic>>(
        genMr,
        describe: 'mrSummaryFromGlab well-typed fuzz',
        count: 200 * fuzzScale(),
        check: (json) {
          // `iid` is always a real int (0..1000000) in genMr, so the row is
          // never rejected here — the identity-rejection path has its own
          // dedicated coverage elsewhere in this file.
          final s = mrSummaryFromGlab(json)!;
          expect(s.title, (json['title'] as String).trim());
          expect(s.number, json['iid']);
          expect(s.changedFiles, isA<int>());
          expect(s.changedFiles, greaterThanOrEqualTo(0));
          // changes_count always resolved to the numeric value it encodes,
          // whatever shape it arrived in (int / digit-string / "N+"),
          // except the deliberate 'unknown' garbage case which falls to 0.
          final shape = json['changes_count'];
          if (shape is int) {
            expect(s.changedFiles, shape);
          } else if (shape is String && shape != 'unknown') {
            final expected = int.parse(shape.replaceAll('+', ''));
            expect(s.changedFiles, expected);
          } else {
            expect(s.changedFiles, 0);
          }
        },
      );
    });
  });

  // ---------------------------------------------------------------------
  // Numeric-field family — parametrized robustness sweep covering every
  // NON-identity `as num?` field (6 of the original 8 — `iid` moved to its
  // own identity-specific groups below, since it now rejects the row
  // instead of falling back to 0). All 6 share `glabIntOrNull`, so each
  // case below is a passing contract.
  // ---------------------------------------------------------------------
  for (final spec in _numericFieldSpecs) {
    group(spec.groupLabel, () {
      for (final c in spec.cases) {
        final json = {...spec.minimalValidJson(), spec.fieldKey: c.value};
        test('${c.label} -> ${c.expected}, does not throw', () {
          expect(() => spec.getResult(json), returnsNormally);
          expect(spec.getResult(json), c.expected);
        });
      }
    });
  }

  // ---------------------------------------------------------------------
  // Identity field (`iid`) — separated from the shared numeric-field sweep
  // above because its contract genuinely differs: every other numeric
  // field falls back to 0 when unreadable, but `iid` keys detail loads,
  // checkout, and actions, so an unreadable one now rejects the whole row
  // (mapper returns null) instead of fabricating an actionable MR/issue #0.
  // ---------------------------------------------------------------------
  group('mrSummaryFromGlab: iid -> number (identity — rejects the row, '
      'does not fall back to 0)', () {
    for (final c in _identityFieldCases()) {
      test('${c.label} -> ${c.expected ?? "null (row rejected)"}, '
          'does not throw', () {
        final json = {'iid': c.value};
        expect(() => mrSummaryFromGlab(json), returnsNormally);
        final s = mrSummaryFromGlab(json);
        if (c.expected == null) {
          expect(s, isNull);
        } else {
          expect(s!.number, c.expected);
        }
      });
    }
  });

  group('issueSummaryFromGlab: iid -> number (identity — rejects the row, '
      'does not fall back to 0)', () {
    for (final c in _identityFieldCases()) {
      test('${c.label} -> ${c.expected ?? "null (row rejected)"}, '
          'does not throw', () {
        final json = {'iid': c.value};
        expect(() => issueSummaryFromGlab(json), returnsNormally);
        final s = issueSummaryFromGlab(json);
        if (c.expected == null) {
          expect(s, isNull);
        } else {
          expect(s!.number, c.expected);
        }
      });
    }
  });

  group('numeric-field family — end-to-end', () {
    test(
      'a wrong-typed numeric field never crashes the mapper it belongs to',
      () {
        // iid is the identity field: an unreadable one now REJECTS the row
        // (returns null) rather than fabricating number 0 — see the
        // dedicated "iid -> number (identity...)" groups above. Every
        // OTHER numeric field is unchanged: it still degrades to 0 (a
        // valid `iid` is added here so those rows survive to exercise the
        // field under test, per this file's RULE 2).
        expect(mrSummaryFromGlab({'iid': 'not-a-number'}), isNull);
        expect(
            mrSummaryFromGlab({'iid': 1, 'user_notes_count': 'not-a-number'})!
                .conversationCount,
            0);
        expect(
            mrSummaryFromGlab({'iid': 1, 'additions': 'not-a-number'})!
                .additions,
            0);
        expect(
            mrSummaryFromGlab({'iid': 1, 'deletions': 'not-a-number'})!
                .deletions,
            0);
        expect(issueSummaryFromGlab({'iid': 'not-a-number'}), isNull);
        expect(
            issueSummaryFromGlab(
                    {'iid': 1, 'user_notes_count': 'not-a-number'})!
                .commentCount,
            0);
        expect(checkFromGlabJob({'duration': 'not-a-number'}).duration,
            isNull);
      },
    );
  });

  group(
    'mrSummaryFromGlab / issueSummaryFromGlab — list-parse drops only '
    'identity-less rows (mirrors glab.dart\'s listMergeRequests/'
    'listGlabIssues drop-null pattern)',
    () {
      test('identity-less MR rows are dropped, not fabricated as MR #0', () {
        final rows = <Map<String, dynamic>>[
          {'iid': 1, 'title': 'first'},
          {'title': 'missing iid'}, // no identity -> dropped
          {'iid': null, 'title': 'explicit null iid'}, // dropped
          {'iid': 'not-a-number', 'title': 'unreadable iid'}, // dropped
          {'iid': 3, 'title': 'third'},
        ];
        final mrs = rows
            .map(mrSummaryFromGlab)
            .whereType<PullRequestSummary>()
            .toList();
        expect(mrs.length, 2);
        expect(mrs.map((m) => m.number).toList(), [1, 3]);
        expect(mrs.map((m) => m.title).toList(), ['first', 'third']);
      });

      test('identity-less issue rows are dropped, not fabricated as issue '
          '#0', () {
        final rows = <Map<String, dynamic>>[
          {'iid': 5, 'title': 'first'},
          {'title': 'missing iid'}, // no identity -> dropped
          {'iid': null, 'title': 'explicit null iid'}, // dropped
          {'iid': 9, 'title': 'second'},
        ];
        final issues = rows
            .map(issueSummaryFromGlab)
            .whereType<IssueSummary>()
            .toList();
        expect(issues.length, 2);
        expect(issues.map((i) => i.number).toList(), [5, 9]);
        expect(issues.map((i) => i.title).toList(), ['first', 'second']);
      });
    },
  );
}
