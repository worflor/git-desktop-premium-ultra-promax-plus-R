// Tests for LogosRefactor — the principled refactor proposer.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_refactor.dart';

LogosGit _fixtureEngine({bool hierarchical = true}) {
  final touches = <String, int>{};
  final volatility = <String, double>{};
  final jaccard = <String, Map<String, double>>{};
  if (hierarchical) {
    // Four groups of 70, strong intra-coupling, weak inter.
    final byGroup = <List<String>>[];
    for (var g = 0; g < 4; g++) {
      final list = [
        for (var i = 0; i < 70; i++)
          'lib/g$g/f${i.toString().padLeft(3, '0')}.dart',
      ];
      byGroup.add(list);
      for (final p in list) {
        touches[p] = 10;
        volatility[p] = 1.0;
        jaccard[p] = <String, double>{};
      }
    }
    for (final group in byGroup) {
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          jaccard[group[i]]![group[j]] = 0.8;
          jaccard[group[j]]![group[i]] = 0.8;
        }
      }
    }
    for (var a = 0; a < 4; a++) {
      for (var b = a + 1; b < 4; b++) {
        jaccard[byGroup[a].first]![byGroup[b].first] = 0.05;
        jaccard[byGroup[b].first]![byGroup[a].first] = 0.05;
      }
    }
  } else {
    // Flat random — no structure.
    final rng = math.Random(3);
    final paths = [
      for (var i = 0; i < 280; i++)
        'lib/f${i.toString().padLeft(3, '0')}.dart',
    ];
    for (final p in paths) {
      touches[p] = 10;
      volatility[p] = 1.0;
      jaccard[p] = <String, double>{};
    }
    for (var i = 0; i < paths.length; i++) {
      for (var j = i + 1; j < paths.length; j++) {
        final w = 0.3 + 0.4 * rng.nextDouble();
        jaccard[paths[i]]![paths[j]] = w;
        jaccard[paths[j]]![paths[i]] = w;
      }
    }
  }
  return LogosGit.buildFromStats(LogosGitStats(
    touches: touches,
    totalCommits: 200,
    volatility: volatility,
    volMean: 1.0,
    volStddev: 0.3,
    coupling: FileCouplingMatrix(
      jaccard: jaccard,
      headHash: hierarchical ? 'hierarchical' : 'flat',
      commitsAnalyzed: 200,
    ),
    perFileCommitIndices: const {},
  ));
}

void main() {
  group('proposeRefactors — smoke', () {
    test('returns a non-null list on a hierarchical fixture', () {
      // List may be empty when the fixture is so clean that no
      // principled proposal fires — that's healthy behaviour, not a
      // failure. The contract is "returns a bounded list, never throws".
      final engine = _fixtureEngine(hierarchical: true);
      final list = proposeRefactors(engine);
      expect(list, isNotNull);
      expect(list!.length, lessThanOrEqualTo(10));
    });

    test('returns null for tiny repos', () {
      final engine = LogosGit.buildFromStats(LogosGitStats(
        touches: const {'a.dart': 1, 'b.dart': 1},
        totalCommits: 1,
        volatility: const {'a.dart': 1.0, 'b.dart': 1.0},
        volMean: 1.0,
        volStddev: 0.0,
        coupling: FileCouplingMatrix(
          jaccard: const {},
          headHash: 'tiny',
          commitsAnalyzed: 1,
        ),
        perFileCommitIndices: const {},
      ));
      expect(proposeRefactors(engine), isNull);
    });
  });

  group('RefactorProposal invariants', () {
    test('every proposal has finite ΔF and confidence in [0, 1]', () {
      final engine = _fixtureEngine(hierarchical: true);
      final list = proposeRefactors(engine)!;
      for (final p in list) {
        expect(p.deltaFreeEnergy.isFinite, isTrue);
        expect(p.confidence, greaterThanOrEqualTo(0.0));
        expect(p.confidence, lessThanOrEqualTo(1.0));
      }
    });

    test('benefitScore sorts the list descending', () {
      final engine = _fixtureEngine(hierarchical: true);
      final list = proposeRefactors(engine)!;
      for (var i = 1; i < list.length; i++) {
        expect(list[i].benefitScore,
            lessThanOrEqualTo(list[i - 1].benefitScore));
      }
    });

    test('every proposal carries a non-empty receipt', () {
      final engine = _fixtureEngine(hierarchical: true);
      final list = proposeRefactors(engine)!;
      for (final p in list) {
        expect(p.receipt, isNotEmpty);
      }
    });

    test('merge proposals name exactly two paths', () {
      final engine = _fixtureEngine(hierarchical: true);
      final list = proposeRefactors(engine)!;
      for (final p in list.where((p) => p.kind == RefactorKind.merge)) {
        expect(p.paths.length, 2);
      }
    });

    test('extract proposals name exactly one path', () {
      final engine = _fixtureEngine(hierarchical: true);
      final list = proposeRefactors(engine)!;
      for (final p in list.where((p) => p.kind == RefactorKind.extract)) {
        expect(p.paths.length, 1);
      }
    });

    test('decouple proposals name exactly two paths', () {
      final engine = _fixtureEngine(hierarchical: true);
      final list = proposeRefactors(engine)!;
      for (final p in list.where((p) => p.kind == RefactorKind.decouple)) {
        expect(p.paths.length, 2);
      }
    });
  });

  group('topN capping', () {
    test('list is bounded by topN', () {
      final engine = _fixtureEngine(hierarchical: true);
      final list = proposeRefactors(engine, topN: 3)!;
      expect(list.length, lessThanOrEqualTo(3));
    });
  });
}
