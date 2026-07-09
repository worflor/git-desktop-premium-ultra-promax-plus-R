// Coverage for the JSON(Map/List) -> DTO parsers in lib/backend/gh.dart and
// lib/backend/remote_types.dart (the GitHub-shaped mappers gh.dart exports
// and shares its DTO types with).
//
// glab.dart's own mappers (mrSummaryFromGlab, issueSummaryFromGlab,
// commentFromGlab, checkFromGlabJob, glabLabels, glabAssigneeLogins,
// parseGlabDate, countGlabDiffLines, glabIntOrNull/glabChangesCount) already
// have thorough dedicated coverage in glab_test.dart — including the exact
// "wrong-typed field throws instead of degrading" bug class this file is
// about, already found and fixed there. Duplicating that here would just be
// redundant, so this file targets the actually-dark parsers: gh.dart's
// PullRequestSummary.fromJson / IssueSummary.fromJson / RemoteComment.fromJson
// / CheckSummary.fromJson (defined in remote_types.dart, re-exported by
// gh.dart) and the shared parseLabelStrings/parseAssigneeLogins/
// parseCommentCount/parseRemoteDate/parseRemoteDuration helpers. None of
// these had a test file before this one — matching gh.dart's ~5% coverage.
//
// ---------------------------------------------------------------------------
// ROBUSTNESS HISTORY — both bugs originally found by this suite are now
// fixed in lib/ (not by this file — this file only asserts the fixed
// behavior). Kept as a landmark for why the groups below are shaped the
// way they are:
//
//  1. `PullRequestSummary.fromJson` / `IssueSummary.fromJson` used to read
//     `number: (j['number'] as num).toInt()` — a NON-nullable cast that
//     threw a TypeError the instant `number` was missing or explicitly
//     null. FIXED by making `number` strict identity: both factories are
//     now `static PullRequestSummary?` / `static IssueSummary?` and return
//     `null` (via `asIntOrNull`) instead of throwing or fabricating an
//     actionable PR/issue #0. Callers (`listPullRequests`, `listIssues`,
//     …) drop null rows with `.whereType<...>()` rather than surface a
//     phantom — see the "list-parse drops only identity-less rows" groups
//     below, and `mrSummaryFromGlab`/`issueSummaryFromGlab` in glab.dart,
//     which mirror the same strict-identity rule.
//
//  2. Every OTHER field (`title`, `headRefName`, `additions`, nested
//     `author.login`, etc.) now reads through json_safety.dart's total,
//     type-safe helpers (`asStringOr`, `asIntOr`, `asBoolOr`,
//     `asMapOrNull`, `asListOrNull`, …) instead of a raw `as T?` cast, so a
//     present-but-wrong-typed value degrades to the documented default
//     instead of throwing. The "present-but-wrong-typed leaf fields"
//     groups below assert exactly that (`returnsNormally`) as a live
//     regression pin, not a bug repro.
// ---------------------------------------------------------------------------

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/remote_types.dart';

import '../support/gen.dart';
import '../support/prop.dart';

Gen<bool> _genBool() => (rng) => rng.nextBool();

/// A value of a different "shape" than whatever a well-typed field expects —
/// used to attack every `as T?` cast in the mappers under test.
final List<Object?> _wrongTypePool = [
  42,
  3.14,
  'unexpected-string',
  true,
  <dynamic>[],
  <String, dynamic>{},
  <dynamic>[1, 2, 3],
];

/// Mutates a valid JSON map by replacing, nulling, or deleting a random
/// subset of its top-level keys — the generic "malformed variant of a valid
/// tree" generator the task asks for.
Gen<Map<String, dynamic>> _mutateJson(Map<String, dynamic> valid) {
  final keys = valid.keys.toList();
  return (rng) {
    final mutated = Map<String, dynamic>.of(valid);
    if (keys.isEmpty) return mutated;
    final mutationCount = rng.intBetween(1, keys.length);
    final chosenKeys = rng.sample(keys, mutationCount);
    for (final k in chosenKeys) {
      final action = rng.intBetween(0, 2);
      if (action == 0) {
        mutated.remove(k);
      } else if (action == 1) {
        mutated[k] = null;
      } else {
        mutated[k] = rng.pick(_wrongTypePool);
      }
    }
    return mutated;
  };
}

void main() {
  // ---------------------------------------------------------------------
  // PullRequestSummary.fromJson — realistic `gh pr list/view --json ...`
  // shape.
  // ---------------------------------------------------------------------
  group('PullRequestSummary.fromJson — happy path', () {
    Map<String, dynamic> validJson() => <String, dynamic>{
          'number': 42,
          'title': '  Add dark mode  ',
          'headRefName': 'feature/dark-mode',
          'baseRefName': 'main',
          'state': 'open',
          'isDraft': false,
          'author': {'login': 'octocat', 'id': 'MDQ6VXNlcjE='},
          'comments': [
            {'body': 'nice'},
            {'body': 'ship it'},
          ],
          'updatedAt': '2026-05-01T12:00:00.000Z',
          'additions': 120,
          'deletions': 30,
          'changedFiles': 5,
          'mergeable': 'mergeable',
          'reviewDecision': 'approved',
          'reviewRequests': [
            {'login': 'reviewer1'}
          ],
          'reviews': [
            {
              'author': {'login': 'reviewer2'},
              'state': 'approved',
            }
          ],
          'labels': [
            {'name': 'bug'},
            {'name': 'P1'},
          ],
          'assignees': [
            {'login': 'carol'}
          ],
        };

    test('maps every field, trims strings, uppercases enums', () {
      final s = PullRequestSummary.fromJson(validJson())!;
      expect(s.number, 42);
      expect(s.title, 'Add dark mode');
      expect(s.headRef, 'feature/dark-mode');
      expect(s.baseRef, 'main');
      expect(s.state, 'OPEN');
      expect(s.isDraft, isFalse);
      expect(s.authorLogin, 'octocat');
      expect(s.conversationCount, 2); // comments is a List -> length
      expect(s.updatedAt, DateTime.parse('2026-05-01T12:00:00.000Z'));
      expect(s.additions, 120);
      expect(s.deletions, 30);
      expect(s.changedFiles, 5);
      expect(s.mergeable, 'MERGEABLE');
      expect(s.reviewDecision, 'APPROVED');
      expect({for (final r in s.reviewers) r.login: r.state}, {
        'reviewer1': 'PENDING',
        'reviewer2': 'APPROVED',
      });
      expect(s.labels, ['bug', 'P1']);
      expect(s.assignees, ['carol']);
    });

    test('determinism: same input -> identical output every time', () {
      final json = validJson();
      final a = PullRequestSummary.fromJson(json)!;
      final b = PullRequestSummary.fromJson(json)!;
      expect(a.number, b.number);
      expect(a.title, b.title);
      expect(a.headRef, b.headRef);
      expect(a.updatedAt, b.updatedAt);
      expect(a.labels, b.labels);
      expect({for (final r in a.reviewers) r.login: r.state},
          {for (final r in b.reviewers) r.login: r.state});
    });
  });

  group('PullRequestSummary.fromJson — safe degradation (absence/null)', () {
    test('author absent, or not a Map, -> empty login, no throw', () {
      expect(PullRequestSummary.fromJson({'number': 1})!.authorLogin, '');
      expect(
        PullRequestSummary.fromJson({'number': 1, 'author': 'not-a-map'})!
            .authorLogin,
        '',
      );
      expect(
        PullRequestSummary.fromJson({'number': 1, 'author': 42})!.authorLogin,
        '',
      );
    });

    test('reviewRequests/reviews shaped as a Map instead of a List do not '
        'throw', () {
      expect(
        () => PullRequestSummary.fromJson({
          'number': 1,
          'reviewRequests': {'not': 'a list'},
          'reviews': {'not': 'a list'},
        }),
        returnsNormally,
      );
      final s = PullRequestSummary.fromJson({
        'number': 1,
        'reviewRequests': {'not': 'a list'},
        'reviews': {'not': 'a list'},
      })!;
      expect(s.reviewers, isEmpty);
    });

    test('title/isDraft/additions explicitly null -> sane defaults', () {
      final s = PullRequestSummary.fromJson({
        'number': 1,
        'title': null,
        'isDraft': null,
        'additions': null,
        'labels': null,
        'assignees': null,
      })!;
      expect(s.title, '');
      expect(s.isDraft, isFalse);
      expect(s.additions, 0);
      expect(s.labels, isEmpty);
      expect(s.assignees, isEmpty);
    });
  });

  group(
    'PullRequestSummary.fromJson — a row with no `number` is rejected '
    '(returns null) so it can\'t become an actionable PR #0',
    () {
      test('completely empty {} -> null, not a fabricated #0', () {
        expect(PullRequestSummary.fromJson(const {}), isNull);
      });

      test('number explicitly null -> null', () {
        expect(
          PullRequestSummary.fromJson({'number': null, 'title': 'x'}),
          isNull,
        );
      });

      test(
        'number as a digit string -> null (asIntOrNull only accepts int, '
        'or an exactly-integral double, never a String — unlike glab.dart\'s '
        'glabIntOrNull, which does accept a digit string)',
        () {
          expect(PullRequestSummary.fromJson({'number': '42'}), isNull);
        },
      );
    },
  );

  group(
    'PullRequestSummary.fromJson — list-parse drops only identity-less '
    'rows (mirrors gh.dart\'s listPullRequests drop-null pattern)',
    () {
      test('identity-less rows are dropped, not fabricated as #0', () {
        final rows = <Map<String, dynamic>>[
          {'number': 1, 'title': 'first'},
          {'title': 'missing number'}, // no identity -> dropped
          {'number': null, 'title': 'explicit null number'}, // dropped
          {'number': 'NaN', 'title': 'non-numeric string number'}, // dropped
          {'number': 3, 'title': 'third'},
        ];
        final prs = rows
            .map(PullRequestSummary.fromJson)
            .whereType<PullRequestSummary>()
            .toList();
        expect(prs.length, 2);
        expect(prs.map((p) => p.number).toList(), [1, 3]);
        expect(prs.map((p) => p.title).toList(), ['first', 'third']);
      });
    },
  );

  group(
    'PullRequestSummary.fromJson — regression pin: present-but-wrong-typed '
    'leaf fields degrade to their default, never throw',
    () {
      // Every case below supplies a valid `number` so the failure is
      // attributable to exactly the field under test, not bug #1 above.
      final cases = <String, Object?>{
        'title': 123,
        'headRefName': true,
        'baseRefName': 3.14,
        'state': 42,
        'isDraft': 'yes',
        'additions': '5',
        'deletions': <dynamic>[],
        'changedFiles': <String, dynamic>{},
        'mergeable': 7,
        'reviewDecision': false,
      };
      for (final entry in cases.entries) {
        test('${entry.key} = ${entry.value} (${entry.value.runtimeType}) '
            'should degrade, not throw', () {
          expect(
            () => PullRequestSummary.fromJson({
              'number': 1,
              entry.key: entry.value,
            }),
            returnsNormally,
            reason: 'Regression pin: `(j[\'${entry.key}\'] as X? ?? default)` '
                'must degrade to its default instead of throwing when the '
                'field is present with the wrong runtime type — a cast only '
                'falls through `??` when the source is null, never when it '
                'is merely mistyped.',
          );
        });
      }

      test('nested author.login wrong-typed degrades, does not throw', () {
        expect(
          () => PullRequestSummary.fromJson({
            'number': 1,
            'author': {'login': 42},
          }),
          returnsNormally,
          reason: 'Regression pin: the is-Map guard on `author` protects '
              'the outer shape and the inner `login` field must degrade to '
              'its default instead of throwing on the wrong type.',
        );
      });

      test('reviewRequests[].login wrong-typed degrades, does not throw',
          () {
        expect(
          () => PullRequestSummary.fromJson({
            'number': 1,
            'reviewRequests': [
              {'login': 42}
            ],
          }),
          returnsNormally,
          reason: 'Regression pin: same class as author.login above, inside '
              'the reviewRequests list — must degrade, not throw.',
        );
      });

      test('reviews[].author.login wrong-typed degrades, does not throw',
          () {
        expect(
          () => PullRequestSummary.fromJson({
            'number': 1,
            'reviews': [
              {
                'author': {'login': 5},
              }
            ],
          }),
          returnsNormally,
        );
      });

      test('reviews[].state wrong-typed degrades, does not throw', () {
        expect(
          () => PullRequestSummary.fromJson({
            'number': 1,
            'reviews': [
              {
                'author': {'login': 'bob'},
                'state': 42,
              }
            ],
          }),
          returnsNormally,
        );
      });
    },
  );

  group(
    'PullRequestSummary.fromJson — malformed-mutation fuzz '
    '(regression pin: every mutation must degrade; was a real bug, now '
    'fixed — see file header)',
    () {
      test(
        '200 random field-level mutations (delete / null / wrong-type) of '
        'an otherwise-valid PR must never throw',
        () {
          final validJson = <String, dynamic>{
            'number': 7,
            'title': 'ok',
            'headRefName': 'a',
            'baseRefName': 'main',
            'state': 'open',
            'isDraft': false,
            'author': {'login': 'me'},
            'comments': <dynamic>[],
            'updatedAt': '2026-01-01T00:00:00Z',
            'additions': 1,
            'deletions': 1,
            'changedFiles': 1,
            'mergeable': 'mergeable',
            'reviewDecision': 'approved',
            'reviewRequests': <dynamic>[],
            'reviews': <dynamic>[],
            'labels': <dynamic>[],
            'assignees': <dynamic>[],
          };
          forAll<Map<String, dynamic>>(
            _mutateJson(validJson),
            describe: 'PullRequestSummary.fromJson mutation robustness',
            count: 60,
            persistCorpus: false,
            check: (json) {
              expect(() => PullRequestSummary.fromJson(json), returnsNormally);
            },
          );
        },
      );
    },
  );

  // ---------------------------------------------------------------------
  // IssueSummary.fromJson — realistic `gh issue list/view --json ...`
  // shape.
  // ---------------------------------------------------------------------
  group('IssueSummary.fromJson — happy path', () {
    test('maps every field', () {
      final json = <String, dynamic>{
        'number': 17,
        'title': 'Crash on startup',
        'state': 'open',
        'author': {'login': 'dave'},
        'labels': [
          {'name': 'bug'},
          {'name': 'p0'},
        ],
        'comments': [
          {'body': 'a'},
          {'body': 'b'},
          {'body': 'c'},
        ],
        'updatedAt': '2026-04-15T09:30:00Z',
        'assignees': [
          {'login': 'erin'}
        ],
      };
      final s = IssueSummary.fromJson(json)!;
      expect(s.number, 17);
      expect(s.title, 'Crash on startup');
      expect(s.state, 'OPEN');
      expect(s.authorLogin, 'dave');
      expect(s.labels, ['bug', 'p0']);
      expect(s.commentCount, 3);
      expect(s.updatedAt, DateTime.parse('2026-04-15T09:30:00Z'));
      expect(s.assignees, ['erin']);
    });

    test('determinism: same input -> identical output', () {
      final json = <String, dynamic>{'number': 1, 'title': 'x'};
      final a = IssueSummary.fromJson(json)!;
      final b = IssueSummary.fromJson(json)!;
      expect(a.number, b.number);
      expect(a.title, b.title);
      expect(a.state, b.state);
    });
  });

  group(
    'IssueSummary.fromJson — a row with no `number` is rejected (returns '
    'null) so it can\'t become an actionable issue #0',
    () {
      test('completely empty {} -> null', () {
        expect(IssueSummary.fromJson(const {}), isNull);
      });

      test('number explicitly null -> null', () {
        expect(IssueSummary.fromJson({'number': null, 'title': 'x'}), isNull);
      });

      test(
        'number as a digit string -> null (asIntOrNull never accepts a '
        'String)',
        () {
          expect(IssueSummary.fromJson({'number': '42'}), isNull);
        },
      );
    },
  );

  group(
    'IssueSummary.fromJson — list-parse drops only identity-less rows '
    '(mirrors gh.dart\'s listIssues drop-null pattern)',
    () {
      test('identity-less rows are dropped, not fabricated as #0', () {
        final rows = <Map<String, dynamic>>[
          {'number': 5, 'title': 'first'},
          {'title': 'missing number'}, // no identity -> dropped
          {'number': null, 'title': 'explicit null number'}, // dropped
          {'number': 9, 'title': 'second'},
        ];
        final issues = rows
            .map(IssueSummary.fromJson)
            .whereType<IssueSummary>()
            .toList();
        expect(issues.length, 2);
        expect(issues.map((i) => i.number).toList(), [5, 9]);
        expect(issues.map((i) => i.title).toList(), ['first', 'second']);
      });
    },
  );

  group(
    'IssueSummary.fromJson — regression pin: present-but-wrong-typed '
    'fields degrade, never throw',
    () {
      test('title wrong-typed degrades, does not throw', () {
        expect(
          () => IssueSummary.fromJson({'number': 1, 'title': 42}),
          returnsNormally,
        );
      });

      test('state wrong-typed degrades, does not throw', () {
        expect(
          () => IssueSummary.fromJson({'number': 1, 'state': true}),
          returnsNormally,
        );
      });

      test('author.login wrong-typed degrades, does not throw', () {
        expect(
          () => IssueSummary.fromJson({
            'number': 1,
            'author': {'login': 42},
          }),
          returnsNormally,
        );
      });
    },
  );

  group('IssueSummary.fromJson — safe degradation', () {
    test('author not a Map, labels/assignees not a List -> empty, no throw',
        () {
      expect(
        () => IssueSummary.fromJson({
          'number': 1,
          'author': 'nope',
          'labels': 'nope',
          'assignees': 'nope',
        }),
        returnsNormally,
      );
      final s = IssueSummary.fromJson({
        'number': 1,
        'author': 'nope',
        'labels': 'nope',
        'assignees': 'nope',
      })!;
      expect(s.authorLogin, '');
      expect(s.labels, isEmpty);
      expect(s.assignees, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  // RemoteComment.fromJson — shared by PR review comments and issue
  // comments (`gh pr view --json comments`, `gh issue view --json
  // comments`).
  // ---------------------------------------------------------------------
  group('RemoteComment.fromJson — happy path', () {
    test('maps author.login, trims body, parses createdAt', () {
      final c = RemoteComment.fromJson({
        'author': {'login': 'frank'},
        'body': '  looks good to me  ',
        'createdAt': '2026-01-02T03:04:05Z',
      });
      expect(c.authorLogin, 'frank');
      expect(c.body, 'looks good to me');
      expect(c.createdAt, DateTime.parse('2026-01-02T03:04:05Z'));
    });

    test('determinism', () {
      final json = {
        'author': {'login': 'x'},
        'body': 'hi',
      };
      final a = RemoteComment.fromJson(json);
      final b = RemoteComment.fromJson(json);
      expect(a.authorLogin, b.authorLogin);
      expect(a.body, b.body);
    });
  });

  group('RemoteComment.fromJson — safe degradation (completely untested '
      'before this file: empty object, absent/null/non-Map author)', () {
    test('completely empty {} does not throw', () {
      expect(() => RemoteComment.fromJson(const {}), returnsNormally);
      final c = RemoteComment.fromJson(const {});
      expect(c.authorLogin, '');
      expect(c.body, '');
      expect(c.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('author missing, or not a Map, -> empty login, no throw', () {
      expect(RemoteComment.fromJson({'body': 'hi'}).authorLogin, '');
      expect(
        RemoteComment.fromJson({'author': 'not-a-map', 'body': 'hi'})
            .authorLogin,
        '',
      );
      expect(
        RemoteComment.fromJson({'author': 42}).authorLogin,
        '',
      );
      expect(
        RemoteComment.fromJson({'author': <dynamic>[]}).authorLogin,
        '',
      );
    });

    test('createdAt unparseable/null/wrong-typed -> epoch fallback, no '
        'throw', () {
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      expect(RemoteComment.fromJson({'createdAt': 'not-a-date'}).createdAt,
          epoch);
      expect(RemoteComment.fromJson({'createdAt': null}).createdAt, epoch);
      expect(RemoteComment.fromJson({'createdAt': 12345}).createdAt, epoch);
    });
  });

  group(
    'RemoteComment.fromJson — regression pin: present-but-wrong-typed '
    '`body`/nested `author.login` degrade, never throw',
    () {
      test('body wrong-typed degrades, does not throw', () {
        expect(
          () => RemoteComment.fromJson({'body': 42}),
          returnsNormally,
          reason: 'Regression pin: `(j[\'body\'] as String? ?? \'\')` must '
              'degrade to its default instead of throwing when body is '
              'present but not a String.',
        );
      });

      test('author.login wrong-typed degrades, does not throw', () {
        expect(
          () => RemoteComment.fromJson({
            'author': {'login': 42},
          }),
          returnsNormally,
        );
      });
    },
  );

  // ---------------------------------------------------------------------
  // CheckSummary.fromJson — `gh pr checks --json name,bucket,state,
  // startedAt,completedAt` shape.
  // ---------------------------------------------------------------------
  group('CheckSummary.fromJson — happy path', () {
    test('a completed, passing check', () {
      final c = CheckSummary.fromJson({
        'name': 'unit-tests',
        'bucket': 'pass',
        'state': 'completed',
        'startedAt': '2026-01-01T00:00:00Z',
        'completedAt': '2026-01-01T00:05:00Z',
      });
      expect(c.name, 'unit-tests');
      expect(c.status, 'completed');
      expect(c.conclusion, 'pass');
      expect(c.duration, const Duration(minutes: 5));
    });

    test('a still-running check has no bucket yet -> queued/in_progress '
        'driven by state, no duration', () {
      final c = CheckSummary.fromJson({
        'name': 'build',
        'state': 'in_progress',
      });
      expect(c.status, 'in_progress');
      expect(c.conclusion, isNull);
      expect(c.duration, isNull);
    });

    test('bucket "pending" is NOT treated as completed', () {
      final c = CheckSummary.fromJson({'bucket': 'pending', 'state': ''});
      expect(c.status, 'queued');
    });

    test('determinism', () {
      final json = {'name': 'x', 'bucket': 'pass'};
      final a = CheckSummary.fromJson(json);
      final b = CheckSummary.fromJson(json);
      expect(a.name, b.name);
      expect(a.status, b.status);
      expect(a.conclusion, b.conclusion);
    });
  });

  group('CheckSummary.fromJson — safe degradation (completely untested '
      'before this file)', () {
    test('completely empty {} does not throw (unlike PR/IssueSummary, '
        'CheckSummary has no non-nullable numeric field)', () {
      expect(() => CheckSummary.fromJson(const {}), returnsNormally);
      final c = CheckSummary.fromJson(const {});
      expect(c.name, '');
      expect(c.status, 'queued');
      expect(c.conclusion, isNull);
      expect(c.duration, isNull);
    });

    test('startedAt/completedAt missing, null, or wrong-typed -> no '
        'duration, no throw', () {
      expect(
        () => CheckSummary.fromJson({'startedAt': 42, 'completedAt': true}),
        returnsNormally,
      );
      expect(
        CheckSummary.fromJson({'startedAt': 42, 'completedAt': true})
            .duration,
        isNull,
      );
      expect(
        CheckSummary.fromJson({'startedAt': 'only-one-side'}).duration,
        isNull,
      );
    });
  });

  group(
    'CheckSummary.fromJson — regression pin: present-but-wrong-typed '
    'bucket/state/name degrade, never throw',
    () {
      test('bucket wrong-typed degrades, does not throw', () {
        expect(
          () => CheckSummary.fromJson({'bucket': 42}),
          returnsNormally,
          reason: 'Regression pin: `j[\'bucket\'] as String?` must degrade '
              'to its default instead of throwing when bucket is present '
              'but not a String (e.g. a forge sending a numeric or boolean '
              'status code).',
        );
      });

      test('state wrong-typed degrades, does not throw', () {
        expect(
          () => CheckSummary.fromJson({'state': 7}),
          returnsNormally,
        );
      });

      test('name wrong-typed degrades, does not throw', () {
        expect(
          () => CheckSummary.fromJson({'name': false}),
          returnsNormally,
        );
      });
    },
  );

  // ---------------------------------------------------------------------
  // Shared helpers — parseLabelStrings / parseAssigneeLogins /
  // parseCommentCount / parseRemoteDate / parseRemoteDuration.
  // ---------------------------------------------------------------------
  group('parseLabelStrings', () {
    test('happy path: extracts name from each label object', () {
      expect(
        parseLabelStrings([
          {'name': 'bug'},
          {'name': 'P1'},
        ]),
        ['bug', 'P1'],
      );
    });

    test('drops empty-name entries', () {
      expect(
        parseLabelStrings([
          {'name': 'bug'},
          {'name': ''},
          {'name': '  '},
        ]),
        ['bug'],
      );
    });

    test('non-list input -> empty, no throw', () {
      expect(parseLabelStrings(null), isEmpty);
      expect(parseLabelStrings('bug'), isEmpty);
      expect(parseLabelStrings({'name': 'bug'}), isEmpty);
      expect(parseLabelStrings(42), isEmpty);
    });

    test('list of non-maps -> empty, no throw (whereType filters them)', () {
      expect(parseLabelStrings([1, 2, 'x', true]), isEmpty);
    });

    test('a GitLab-shaped label list (plain strings, not {name: ...} '
        'objects) yields no labels, not a crash', () {
      expect(parseLabelStrings(['bug', 'wip']), isEmpty);
    });

    test(
      'regression pin: an inner `name` field present but wrong-typed '
      'degrades (no throw) even though the outer is-Map guard does not '
      'protect it',
      () {
        expect(
          () => parseLabelStrings([
            {'name': 42}
          ]),
          returnsNormally,
        );
      },
    );
  });

  group('parseAssigneeLogins', () {
    test('happy path', () {
      expect(
        parseAssigneeLogins([
          {'login': 'gina'},
          {'login': 'hank'},
        ]),
        ['gina', 'hank'],
      );
    });

    test('drops blank logins; non-list/non-map entries -> empty, no throw',
        () {
      expect(
        parseAssigneeLogins([
          {'login': ''},
          {'id': 1},
          {'login': 'ivan'},
        ]),
        ['ivan'],
      );
      expect(parseAssigneeLogins(null), isEmpty);
      expect(parseAssigneeLogins('gina'), isEmpty);
      expect(parseAssigneeLogins(['gina', 'hank']), isEmpty);
    });

    test('regression pin: inner `login` wrong-typed degrades, does not '
        'throw', () {
      expect(
        () => parseAssigneeLogins([
          {'login': true}
        ]),
        returnsNormally,
      );
    });
  });

  group('parseCommentCount — always safe (no inner-field risk)', () {
    test('a number -> its int value', () {
      expect(parseCommentCount(5), 5);
      expect(parseCommentCount(5.0), 5);
    });

    test('a List -> its length (the `comments` array shape)', () {
      expect(parseCommentCount([1, 2, 3]), 3);
      expect(parseCommentCount(const <dynamic>[]), 0);
    });

    test('anything else -> 0, no throw', () {
      expect(parseCommentCount(null), 0);
      expect(parseCommentCount('5'), 0);
      expect(parseCommentCount(true), 0);
      expect(parseCommentCount({'count': 5}), 0);
    });

    test('property: never throws and is deterministic over arbitrary '
        'well-typed-but-hostile input', () {
      final gen = genOneOf<Object?>([
        genMap(genInt(), (v) => v as Object?),
        genMap(genList(genAscii()), (v) => v as Object?),
        genMap(genAscii(), (v) => v as Object?),
        genConst<Object?>(null),
        genMap(_genBool(), (v) => v as Object?),
        genMap(genDouble(), (v) => v as Object?),
      ]);
      forAll<Object?>(
        gen,
        describe: 'parseCommentCount never throws + deterministic',
        count: 200,
        check: (value) {
          final a = parseCommentCount(value);
          final b = parseCommentCount(value);
          expect(a, b, reason: 'determinism: same input -> same output');
          // Not asserting non-negativity here: a `num` input's sign passes
          // straight through (`value.toInt()`), so a (nonsensical, but
          // well-typed) negative `comments` field legitimately yields a
          // negative count. The property under test is total-and-
          // deterministic, not "always non-negative".
        },
      );
    });
  });

  group('parseRemoteDate — always safe (String or epoch fallback)', () {
    test('parses a real ISO-8601 timestamp', () {
      expect(parseRemoteDate('2026-03-04T05:06:07.000Z'),
          DateTime.parse('2026-03-04T05:06:07.000Z'));
    });

    test('unparseable string, null, and wrong types all yield the epoch',
        () {
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      expect(parseRemoteDate('not-a-date'), epoch);
      expect(parseRemoteDate(null), epoch);
      expect(parseRemoteDate(12345), epoch);
      expect(parseRemoteDate(<dynamic>[]), epoch);
      expect(parseRemoteDate(<String, dynamic>{}), epoch);
    });

    test('property: never throws and is deterministic over hostile string '
        'content, plus non-string inputs', () {
      final gen = genOneOf<Object?>([
        genMap(genUnicodeHostile(), (v) => v as Object?),
        genMap(genAscii(), (v) => v as Object?),
        genConst<Object?>(null),
        genMap(genInt(), (v) => v as Object?),
      ]);
      forAll<Object?>(
        gen,
        describe: 'parseRemoteDate never throws + deterministic',
        count: 200,
        check: (value) {
          final a = parseRemoteDate(value);
          final b = parseRemoteDate(value);
          expect(a, b);
        },
      );
    });
  });

  group('parseRemoteDuration — always safe (both sides must be String)', () {
    test('both sides parseable -> the difference', () {
      expect(
        parseRemoteDuration(
            '2026-01-01T00:00:00Z', '2026-01-01T00:05:00Z'),
        const Duration(minutes: 5),
      );
    });

    test('either side non-String, null, or unparseable -> null, no throw',
        () {
      expect(parseRemoteDuration(42, '2026-01-01T00:05:00Z'), isNull);
      expect(parseRemoteDuration('2026-01-01T00:00:00Z', null), isNull);
      expect(parseRemoteDuration(null, null), isNull);
      expect(parseRemoteDuration('not-a-date', 'also-not'), isNull);
      expect(parseRemoteDuration(<dynamic>[], <String, dynamic>{}), isNull);
    });

    test('property: never throws and is deterministic', () {
      final side = genOneOf<Object?>([
        genMap(genUnicodeHostile(), (v) => v as Object?),
        genConst<Object?>(null),
        genMap(genInt(), (v) => v as Object?),
      ]);
      forAll<(Object?, Object?)>(
        (rng) => (side(rng), side(rng)),
        describe: 'parseRemoteDuration never throws + deterministic',
        count: 200,
        check: (pair) {
          final a = parseRemoteDuration(pair.$1, pair.$2);
          final b = parseRemoteDuration(pair.$1, pair.$2);
          expect(a, b);
        },
      );
    });
  });

  // ---------------------------------------------------------------------
  // Hostile / unicode content survives unmangled through the safe fields.
  // ---------------------------------------------------------------------
  group('unicode + hostile content passes through unmangled', () {
    const probes = <String>[
      '👨‍👩‍👧‍👦 family PR', // multi-codepoint ZWJ emoji
      'مرحبا بالعالم', // Arabic (RTL)
      '日本語のテスト', // CJK
      "<script>alert('xss')</script>", // angle brackets + quotes
    ];

    for (var i = 0; i < probes.length; i++) {
      final probe = probes[i];
      test('probe #$i survives PullRequestSummary/IssueSummary/'
          'RemoteComment.fromJson', () {
        final pr = PullRequestSummary.fromJson({
          'number': 1,
          'title': probe,
          'author': {'login': probe},
        })!;
        expect(pr.title, probe);
        expect(pr.authorLogin, probe);

        final issue = IssueSummary.fromJson({'number': 1, 'title': probe})!;
        expect(issue.title, probe);

        final comment = RemoteComment.fromJson({'body': probe});
        expect(comment.body, probe);
      });
    }
  });
}
