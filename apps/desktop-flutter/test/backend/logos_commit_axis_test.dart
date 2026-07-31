// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// logos_commit_axis_test.dart — the engine's commit coordinate, directly.
//
// The axis is what makes a commit addressable by the engine, and everything
// retrospective rides on it: locate the commit, split evidence into before
// and after, weight the after. These pin the coordinate's own invariants
// against a real `git log` walk rather than through a caller.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_commit_axis.dart';
import 'package:git_desktop/backend/logos_git_stats.dart';

import '../support/scratch_repo.dart';

void main() {
  late ScratchRepo repo;
  late LogosCommitAxis axis;
  late List<String> shas; // oldest -> newest, as committed

  setUpAll(() async {
    repo = await ScratchRepo.create(name: 'commit_axis');
    shas = [];
    // alpha is rewritten in every commit; beta only in the first two. The
    // asymmetry is what the future-churn arithmetic is read against.
    for (var i = 0; i < 5; i++) {
      await repo.writeFile('alpha.dart', 'const a = $i;\n');
      if (i < 2) await repo.writeFile('beta.dart', 'const b = $i;\n');
      shas.add(await repo.commitAllAs(
        name: i.isEven ? 'Even Author' : 'Odd Author',
        email: i.isEven ? 'even@example.com' : 'odd@example.com',
        message: 'step $i',
      ));
    }
    final stats = await collectLogosGitStats(repo.dir.path);
    expect(stats.ok, isTrue, reason: 'stats: ${stats.error}');
    axis = stats.data!.commitAxis;
  });

  tearDownAll(() async => repo.dispose());

  test('X1: index 0 is the OLDEST commit', () {
    // Everything downstream reads "after" as "greater index". Inverting this
    // would silently turn hindsight into foresight.
    final first = axis.indexOf(shas.first);
    final last = axis.indexOf(shas.last);
    expect(first, isNotNull);
    expect(last, isNotNull);
    expect(first! < last!, isTrue);
    for (var i = 1; i < shas.length; i++) {
      final prev = axis.indexOf(shas[i - 1]);
      final cur = axis.indexOf(shas[i]);
      if (prev != null && cur != null) expect(prev < cur, isTrue);
    }
  });

  test('X2: every parallel array is index-aligned with the hashes', () {
    expect(axis.stepAt, hasLength(axis.length));
    expect(axis.clockAt, hasLength(axis.length));
    expect(axis.authorAt, hasLength(axis.length));
    expect(axis.isNotEmpty, isTrue);
    expect(axis.tip, axis.hashes.last);
  });

  test('X3: the semantic clock is non-decreasing and cumulative', () {
    // clockAt[i] is the sum of stepAt[0..i]. perFileCommitClock samples the
    // same clock, so a drift here silently misaligns every per-file series
    // against the axis.
    var running = 0.0;
    for (var i = 0; i < axis.length; i++) {
      expect(axis.stepAt[i], greaterThanOrEqualTo(0.0));
      expect(axis.stepAt[i], lessThanOrEqualTo(1.0));
      running += axis.stepAt[i];
      expect(axis.clockAt[i], closeTo(running, 1e-9));
    }
    expect(axis.totalClock, closeTo(running, 1e-9));
  });

  test('X4: authors are interned, not repeated', () {
    expect(axis.authors.toSet(), hasLength(axis.authors.length),
        reason: 'the whole point of the index indirection');
    final seen = <String>{};
    for (var i = 0; i < axis.length; i++) {
      final a = axis.authorAtIndex(i);
      if (a != null) seen.add(a);
    }
    expect(seen, containsAll(<String>['even@example.com', 'odd@example.com']));
    expect(axis.authorAtIndex(-1), isNull);
    expect(axis.authorAtIndex(axis.length), isNull,
        reason: 'out of range is absent, not a crash and not a wrong author');
  });

  test('X5: an unknown hash is absent rather than clamped to a position', () {
    expect(axis.indexOf('not-a-hash'), isNull);
    expect(axis.contains('not-a-hash'), isFalse);
    expect(axis.indexOf(shas.first), isNotNull);
  });

  test('X6: clockBetween measures a closed span and never goes negative', () {
    expect(axis.clockBetween(0, axis.length - 1),
        closeTo(axis.totalClock, 1e-9));
    expect(axis.clockBetween(2, 1), 0.0,
        reason: 'a backwards span is empty, not a negative duration');
    expect(axis.clockBetween(0, 0), closeTo(axis.clockAt[0], 1e-9));
  });

  test('X7: the empty axis answers everything without inventing history', () {
    const empty = LogosCommitAxis.emptyAxis;
    expect(empty.isEmpty, isTrue);
    expect(empty.length, 0);
    expect(empty.tip, isNull);
    expect(empty.totalClock, 0.0);
    expect(empty.indexOf('anything'), isNull);
    expect(empty.clockBetween(0, 5), 0.0);
    expect(empty.authorAtIndex(0), isNull);
  });

  test('X8: future churn separates a rewritten file from a settled one',
      () async {
    final stats = await collectLogosGitStats(repo.dir.path);
    final series = stats.data!.perFileCommitIndices;
    final anchor = axis.indexOf(shas[1])!;

    final alpha = futureTouchCount(series['alpha.dart']!, anchor);
    final beta = futureTouchCount(series['beta.dart']!, anchor);

    expect(alpha, greaterThan(beta),
        reason: 'alpha.dart kept being rewritten after step 1 and beta.dart '
            'did not — that difference IS the retrospective signal');
    expect(beta, 0);
  });

  test('X9: the retrospective boost scales with what happened after', () {
    final series = {
      'rewritten': const [0, 1, 2, 3],
      'settled': const [0, 1],
    };
    final weights = retrospectiveFocusWeights(
      sourceWeights: const {'rewritten': 1.0, 'settled': 1.0},
      afterIndex: 1,
      perFileCommitIndices: series,
    );
    // Half of `rewritten`'s history came after the anchor, so 1 + 1/2.
    expect(weights['rewritten'], closeTo(1.5, 1e-9));
    expect(weights['settled'], closeTo(1.0, 1e-9),
        reason: 'a file nothing touched again keeps exactly its old weight');

    // Bounded: even a file touched only after the anchor at most doubles.
    final all = retrospectiveFocusWeights(
      sourceWeights: const {'x': 1.0},
      afterIndex: -1,
      perFileCommitIndices: const {
        'x': [0, 1, 2],
      },
    );
    expect(all['x'], closeTo(2.0, 1e-9));
  });

  test('X10: pending work is never boosted', () {
    // There is no "after" for a change that has not landed, and inventing one
    // would quietly reweight every ordinary review.
    const w = {'a': 1.0, 'b': 2.0};
    expect(
      retrospectiveFocusWeights(
        sourceWeights: w,
        afterIndex: null,
        perFileCommitIndices: const {
          'a': [0, 1],
        },
      ),
      same(w),
    );
  });
}
