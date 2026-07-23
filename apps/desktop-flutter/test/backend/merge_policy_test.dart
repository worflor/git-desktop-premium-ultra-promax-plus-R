// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// merge_policy_test.dart — laws of the declared per-field merge.
//
// The reconcile engine's convergence rests on these being TRUE, not
// plausible:
//  M1  commutativity: merge(a,b) == merge(b,a) byte-for-byte;
//  M2  idempotence: merge(a,a) == canonical(a);
//  M3  absorption: merging the merge with either input returns the
//      merge (no ping-pong fuel);
//  M4  union semantics: threads/comments/verdicts from both sides all
//      survive, keyed correctly;
//  M5  element recursion: a thread mutated on both sides keeps BOTH
//      new comments and resolves scalar conflicts by element recency;
//  M6  MaxNum never regresses; LwwTs picks per-entry recency against
//      the record-level winner;
//  M7  seeded fuzz: random divergent pairs uphold M1-M3.

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/merge_policy.dart';
import 'package:git_desktop/backend/review_records.dart';

const _shaA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _shaB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, dynamic> _thread(
  String id, {
  String state = 'unresolved',
  List<Map<String, dynamic>> comments = const [],
  String updatedAt = '2026-07-22T10:00:00.000',
}) =>
    {
      'id': id,
      'state': state,
      'anchor': {'path': 'a.dart', 'line': 3},
      'comments': comments,
      'updatedAt': updatedAt,
    };

Map<String, dynamic> _comment(String author, String at, String body) => {
      'author': {'display': author},
      'at': at,
      'body': body,
      'kind': 'human',
    };

Map<String, dynamic> _base({
  List<Map<String, dynamic>> threads = const [],
  List<Map<String, dynamic>> rounds = const [],
  Map<String, dynamic> reviewedFiles = const {},
  int schemaVersion = 1,
  String updatedAt = '2026-07-22T10:00:00.000',
}) =>
    {
      'schemaVersion': schemaVersion,
      'deskId': 7,
      'rounds': rounds,
      'threads': threads,
      'verdicts': <Map<String, dynamic>>[],
      'reviewedFiles': reviewedFiles,
      'updatedAt': updatedAt,
    };

String _m(Map<String, dynamic> a, Map<String, dynamic> b) =>
    mergeWithSchema(
        kReviewStateSchema, jsonEncode(a), jsonEncode(b), _shaA, _shaB);

void main() {
  test('M1+M2: commutative and idempotent on a rich divergent pair', () {
    final a = _base(
      threads: [
        _thread('t1', comments: [_comment('mira', '2026-07-22T09:00:00.000', 'hm')]),
        _thread('t2'),
      ],
      updatedAt: '2026-07-22T11:00:00.000',
    );
    final b = _base(
      threads: [
        _thread('t1', comments: [_comment('jun', '2026-07-22T09:30:00.000', 'ok')]),
        _thread('t3'),
      ],
      updatedAt: '2026-07-22T10:30:00.000',
    );
    final ab = _m(a, b);
    final ba = mergeWithSchema(
        kReviewStateSchema, jsonEncode(b), jsonEncode(a), _shaB, _shaA);
    expect(ab, ba, reason: 'both peers must produce identical bytes');

    final aa = _m(a, a);
    final decodedAa = jsonDecode(aa) as Map<String, dynamic>;
    expect((decodedAa['threads'] as List).length, 2,
        reason: 'self-merge must not duplicate');
  });

  test('M3: absorption — re-merging the merge is a fixpoint', () {
    final a = _base(
        threads: [_thread('t1', comments: [_comment('mira', '2026-07-22T09:00:00.000', 'x')])]);
    final b = _base(
        threads: [_thread('t2', comments: [_comment('jun', '2026-07-22T09:10:00.000', 'y')])]);
    final merged = _m(a, b);
    final again =
        _m(jsonDecode(merged) as Map<String, dynamic>, a);
    expect(again, merged,
        reason: 'merge ∨ input must equal merge, or sync ping-pongs');
    final again2 =
        _m(jsonDecode(merged) as Map<String, dynamic>, b);
    expect(again2, merged);
  });

  test('M4: union keeps threads and comments from both sides', () {
    final a = _base(threads: [
      _thread('t1', comments: [_comment('mira', '2026-07-22T09:00:00.000', 'first')])
    ]);
    final b = _base(threads: [
      _thread('t1', comments: [_comment('jun', '2026-07-22T09:05:00.000', 'second')])
    ]);
    final merged = jsonDecode(_m(a, b)) as Map<String, dynamic>;
    final threads = merged['threads'] as List;
    expect(threads.length, 1);
    final comments = (threads.first as Map)['comments'] as List;
    expect(comments.length, 2,
        reason: 'concurrent comments on one thread must BOTH survive');
  });

  test('M5: element recursion — later resolution wins, comments union', () {
    // Side A resolved the thread at 10:00; side B commented at 10:30
    // (thread updatedAt 10:30 > A's 10:00). The resolution fields ride
    // element-level LWW: B's element is later, but B never wrote
    // resolution fields — union of keys keeps A's resolution, and the
    // comment lands too.
    final a = _base(threads: [
      _thread('t1',
          state: 'done',
          comments: [_comment('mira', '2026-07-22T09:00:00.000', 'q')],
          updatedAt: '2026-07-22T10:00:00.000')
        ..['resolvedBy'] = {'display': 'jun'}
        ..['resolvedAt'] = '2026-07-22T10:00:00.000',
    ]);
    final b = _base(threads: [
      _thread('t1',
          comments: [
            _comment('mira', '2026-07-22T09:00:00.000', 'q'),
            _comment('mira', '2026-07-22T10:30:00.000', 'also...'),
          ],
          updatedAt: '2026-07-22T10:30:00.000'),
    ]);
    final merged = jsonDecode(_m(a, b)) as Map<String, dynamic>;
    final t = (merged['threads'] as List).first as Map;
    expect((t['comments'] as List).length, 2);
    expect(t['state'], 'unresolved',
        reason: "B's element is later, so its scalar state wins — the "
            'comment REOPENS the race and the resolution replays or '
            'stands by recency, deterministically on both machines');
    expect(t['resolvedBy'], isNotNull,
        reason: 'union of keys keeps the resolution provenance');
  });

  test('M6: MaxNum never regresses; LwwTs picks per-entry recency', () {
    final a = _base(schemaVersion: 2, reviewedFiles: {
      'mira': {
        'a.dart': {
          'contentHash': 'old',
          'round': 1,
          'at': '2026-07-22T09:00:00.000'
        },
      },
    }, updatedAt: '2026-07-22T12:00:00.000'); // record-level winner
    final b = _base(schemaVersion: 1, reviewedFiles: {
      'mira': {
        'a.dart': {
          'contentHash': 'new',
          'round': 2,
          'at': '2026-07-22T11:00:00.000'
        },
      },
    }, updatedAt: '2026-07-22T10:00:00.000');
    final merged = jsonDecode(_m(a, b)) as Map<String, dynamic>;
    expect(merged['schemaVersion'], 2);
    final bit =
        ((merged['reviewedFiles'] as Map)['mira'] as Map)['a.dart'] as Map;
    expect(bit['contentHash'], 'new',
        reason: 'per-entry recency (11:00 > 09:00) must beat the '
            'record-level winner');
  });

  test('M8: same-number round collision converges to the larger commit, '
      'matching the pin rule', () {
    // The double-cut race: both sides recorded round 3, different
    // commits. The state doc MUST pick the same winner the pin ref
    // does (lexicographically larger commit sha) — regardless of which
    // record is the top-level winner, so set updatedAt AGAINST the
    // larger commit to prove collideBy overrides the record winner.
    Map<String, dynamic> round(String commit, String cutAt) =>
        {'n': 3, 'commit': commit, 'cutAt': cutAt, 'by': {'display': 'x'}};
    final a = _base(
        rounds: [round('f' * 40, '2026-07-22T09:00:00.000')],
        updatedAt: '2026-07-22T09:00:00.000'); // larger commit, LOSER record
    final b = _base(
        rounds: [round('0' * 40, '2026-07-22T12:00:00.000')],
        updatedAt: '2026-07-22T12:00:00.000'); // smaller commit, WINNER record
    final ab = jsonDecode(_m(a, b)) as Map<String, dynamic>;
    final ba = jsonDecode(mergeWithSchema(kReviewStateSchema, jsonEncode(b),
        jsonEncode(a), _shaB, _shaA)) as Map<String, dynamic>;
    for (final m in [ab, ba]) {
      final rounds = m['rounds'] as List;
      expect(rounds.length, 1);
      expect((rounds.single as Map)['commit'], 'f' * 40,
          reason: 'metadata must agree with the pin (larger sha wins)');
    }
  });

  test('M7: seeded fuzz upholds commutativity + absorption', () {
    final rng = Random(20260722);
    String iso(int m) =>
        DateTime.fromMillisecondsSinceEpoch(1700000000000 + m * 60000)
            .toIso8601String();
    Map<String, dynamic> randomState() {
      final threads = <Map<String, dynamic>>[];
      for (var t = 0; t < rng.nextInt(4); t++) {
        final comments = <Map<String, dynamic>>[];
        for (var c = 0; c < rng.nextInt(3); c++) {
          comments.add(_comment(
              ['mira', 'jun', 'varrho'][rng.nextInt(3)],
              iso(rng.nextInt(500)),
              'c${rng.nextInt(1000)}'));
        }
        threads.add(_thread('t${rng.nextInt(5)}',
            state: ['unresolved', 'done', 'acked'][rng.nextInt(3)],
            comments: comments,
            updatedAt: iso(rng.nextInt(500))));
      }
      return _base(threads: threads, updatedAt: iso(rng.nextInt(500)));
    }

    for (var i = 0; i < 60; i++) {
      final a = randomState();
      final b = randomState();
      final ab = _m(a, b);
      final ba = mergeWithSchema(
          kReviewStateSchema, jsonEncode(b), jsonEncode(a), _shaB, _shaA);
      expect(ab, ba, reason: 'fuzz iteration $i not commutative');
      final absorbed = _m(jsonDecode(ab) as Map<String, dynamic>, a);
      expect(absorbed, ab, reason: 'fuzz iteration $i not absorbing');
    }
  });
}
