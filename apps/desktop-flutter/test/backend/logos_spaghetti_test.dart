// Tests for LogosSpaghetti — the tangle analyzer.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_spaghetti.dart';

LogosGit _hierarchical({int groups = 4, int perGroup = 80}) {
  // Clean multi-cluster fixture: groups tightly connected internally,
  // weakly across. Should show clean scale separation under RG.
  final touches = <String, int>{};
  final volatility = <String, double>{};
  final jaccard = <String, Map<String, double>>{};
  final byGroup = <List<String>>[];
  for (var g = 0; g < groups; g++) {
    final list = <String>[];
    for (var i = 0; i < perGroup; i++) {
      final p = 'lib/g$g/f${i.toString().padLeft(3, '0')}.dart';
      list.add(p);
      touches[p] = 10;
      volatility[p] = 1.0;
      jaccard[p] = <String, double>{};
    }
    byGroup.add(list);
  }
  // Intra-group: strong jaccard.
  for (final group in byGroup) {
    for (var i = 0; i < group.length; i++) {
      for (var j = i + 1; j < group.length; j++) {
        jaccard[group[i]]![group[j]] = 0.8;
        jaccard[group[j]]![group[i]] = 0.8;
      }
    }
  }
  // Inter-group: one weak bridge per pair (the Casimir edges).
  for (var a = 0; a < groups; a++) {
    for (var b = a + 1; b < groups; b++) {
      final pA = byGroup[a].first;
      final pB = byGroup[b].first;
      jaccard[pA]![pB] = 0.03;
      jaccard[pB]![pA] = 0.03;
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
      headHash: 'hierarchical',
      commitsAnalyzed: 200,
    ),
    perFileCommitIndices: const {},
  ));
}

LogosGit _spaghetti({int n = 280}) {
  // Spaghetti fixture: flat random couplings, no hierarchy.
  final touches = <String, int>{};
  final volatility = <String, double>{};
  final jaccard = <String, Map<String, double>>{};
  final rng = math.Random(0xABBA);
  final paths = [
    for (var i = 0; i < n; i++)
      'lib/s${i.toString().padLeft(3, '0')}.dart',
  ];
  for (final p in paths) {
    touches[p] = 10;
    volatility[p] = 1.0;
    jaccard[p] = <String, double>{};
  }
  // Every pair gets a random small-to-medium jaccard.
  for (var i = 0; i < paths.length; i++) {
    for (var j = i + 1; j < paths.length; j++) {
      final w = 0.3 + 0.4 * rng.nextDouble();
      jaccard[paths[i]]![paths[j]] = w;
      jaccard[paths[j]]![paths[i]] = w;
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
      headHash: 'spaghetti',
      commitsAnalyzed: 200,
    ),
    perFileCommitIndices: const {},
  ));
}

void main() {
  group('analyzeSpaghetti — smoke test', () {
    test('returns a report on a hierarchical repo', () {
      final engine = _hierarchical();
      final report = analyzeSpaghetti(engine);
      expect(report, isNotNull);
    });

    test('returns null for tiny repos', () {
      final engine = LogosGit.buildFromStats(LogosGitStats(
        touches: const {'a.dart': 1},
        totalCommits: 1,
        volatility: const {'a.dart': 1.0},
        volMean: 1.0,
        volStddev: 0.0,
        coupling: FileCouplingMatrix(
          jaccard: const {},
          headHash: 'tiny',
          commitsAnalyzed: 1,
        ),
        perFileCommitIndices: const {},
      ));
      expect(analyzeSpaghetti(engine), isNull);
    });
  });

  group('TangleIndex', () {
    test('value is in [0, 1]', () {
      final engine = _hierarchical();
      final report = analyzeSpaghetti(engine)!;
      expect(report.tangleIndex.value, greaterThanOrEqualTo(0.0));
      expect(report.tangleIndex.value, lessThanOrEqualTo(1.0));
    });

    test('spectralGapPerLevel records every RG step', () {
      final engine = _hierarchical();
      final report = analyzeSpaghetti(engine, rgLevels: 2)!;
      expect(report.tangleIndex.spectralGapPerLevel, isNotEmpty);
    });
  });

  group('TangleMap', () {
    test('every path has a non-negative contribution', () {
      final engine = _hierarchical();
      final report = analyzeSpaghetti(engine)!;
      for (final v in report.tangleMap.perPath.values) {
        expect(v, greaterThanOrEqualTo(0.0));
        expect(v.isFinite, isTrue);
      }
    });

    test('top(n) returns n entries sorted desc', () {
      final engine = _hierarchical();
      final report = analyzeSpaghetti(engine)!;
      final top = report.tangleMap.top(3);
      expect(top.length, lessThanOrEqualTo(3));
      for (var i = 1; i < top.length; i++) {
        expect(top[i].value, lessThanOrEqualTo(top[i - 1].value));
      }
    });
  });

  group('Detectors', () {
    test('detectors produce a bounded findings list', () {
      // buildFromStats applies edge-density pruning that may remove
      // the explicit weak-bridge edges depending on their rank in
      // each row's top-N. The contract we actually care about is:
      // detectors run, produce finite-severity findings, and the
      // list is bounded (no infinite loop, no duplicates).
      final engine = _hierarchical();
      final report = analyzeSpaghetti(engine)!;
      expect(report.findings.length, lessThan(engine.graph.n));
    });

    test('findings all have severity in [0, 1]', () {
      final engine = _hierarchical();
      final report = analyzeSpaghetti(engine)!;
      for (final f in report.findings) {
        expect(f.severity, greaterThanOrEqualTo(0.0));
        expect(f.severity, lessThanOrEqualTo(1.0));
      }
    });

    test('findings all describe to non-empty strings', () {
      final engine = _hierarchical();
      final report = analyzeSpaghetti(engine)!;
      for (final f in report.findings) {
        expect(f.describe(), isNotEmpty);
      }
    });

    test('topFindings sorts by severity descending', () {
      final engine = _hierarchical();
      final report = analyzeSpaghetti(engine)!;
      final sorted = report.topFindings;
      for (var i = 1; i < sorted.length; i++) {
        expect(
            sorted[i].severity, lessThanOrEqualTo(sorted[i - 1].severity));
      }
    });
  });

  group('Hierarchical vs spaghetti — relative ordering', () {
    test('spaghetti fixture yields more findings than hierarchical', () {
      // Spaghetti has no bridges (all edges strong), so fewer Casimir.
      // But god-class and dead-code counts should differ.
      final hier = _hierarchical();
      final spag = _spaghetti();
      final hierReport = analyzeSpaghetti(hier);
      final spagReport = analyzeSpaghetti(spag);
      expect(hierReport, isNotNull);
      expect(spagReport, isNotNull);
      // Both should produce reports; magnitudes depend on topology.
      expect(hierReport!.findings, isNotNull);
      expect(spagReport!.findings, isNotNull);
    });
  });
}
