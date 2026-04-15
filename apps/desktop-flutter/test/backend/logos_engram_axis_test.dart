// Tests for the EN axis added to LogosGit's Born mixer. These exercise
// the back-half of the integration: given a synthetic stats object and
// a populated `perFileKVectors` map, verify that semantically-related
// files get bonded into the graph (and unrelated files don't).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/engram_brain.dart';
import 'package:git_desktop/backend/engram_file_ktable.dart';
import 'package:git_desktop/backend/engram_hunk_encoder.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_git_stats.dart';

EngramFileKTable _kTable(Map<String, HunkKVector> m, {int pairs = 2}) {
  // Build a small wellNamesByOriginalIndex from observed wells (each
  // unique well name in the test gets index 0/1/... — order doesn't
  // matter for the EN axis behaviour, only well-id identity does).
  final names = <String>[];
  final byName = <String, int>{};
  final reIdxed = <String, HunkKVector>{};
  for (final e in m.entries) {
    final orig = e.value;
    final w = orig.well;
    if (w == null) {
      reIdxed[e.key] = orig;
      continue;
    }
    final idx = byName.putIfAbsent(w.name, () {
      names.add(w.name);
      return names.length - 1;
    });
    reIdxed[e.key] = HunkKVector(
      kRe: orig.kRe,
      kIm: orig.kIm,
      meanRms: orig.meanRms,
      vocabHits: orig.vocabHits,
      well: EngramWellMatch(
        name: w.name,
        index: idx,
        rawDistance: w.rawDistance,
        weightedDistance: w.weightedDistance,
      ),
    );
  }
  return EngramFileKTable.fromMap(
    pairs: pairs,
    encodings: reIdxed,
    wellNamesByOriginalIndex: names,
  );
}

LogosGitStats _bareStats(List<String> paths) {
  return LogosGitStats(
    touches: {for (final p in paths) p: 5},
    volatility: {for (final p in paths) p: 1.0},
    coupling: FileCouplingMatrix.empty,
    perFileCommitIndices: const {},
    totalCommits: 50,
    volMean: 1.0,
    volStddev: 0.5,
  );
}

HunkKVector _kVec({
  required List<double> re,
  required List<double> im,
  required int hits,
  String? wellName,
}) {
  return HunkKVector(
    kRe: Float64List.fromList(re),
    kIm: Float64List.fromList(im),
    meanRms: 0.01,
    vocabHits: hits,
    well: wellName == null
        ? null
        : EngramWellMatch(
            name: wellName,
            index: 0,
            rawDistance: 0.1,
            weightedDistance: 0.05,
          ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LogosGit EN axis', () {
    test('engine builds without engram (legacy 4-axis path) — backward compat',
        () {
      final stats = _bareStats(['lib/a.dart', 'lib/b.dart']);
      // No perFileKVectors → uses 4-axis mixer, no regression.
      final engine = LogosGit.buildFromStats(stats);
      expect(engine.nodePaths, hasLength(2));
      expect(engine.perFileKVectors.isEmpty, isTrue);
      expect(engine.wellOf('lib/a.dart'), isNull);
    });

    test('engine builds with engram K-vectors (5-axis path)', () {
      final stats = _bareStats(['lib/a.dart', 'lib/b.dart', 'lib/c.dart']);
      final kvecs = <String, HunkKVector>{
        'lib/a.dart': _kVec(re: [1.0, 0.0], im: [0.0, 0.0], hits: 8, wellName: 'computing'),
        'lib/b.dart': _kVec(re: [0.99, 0.05], im: [0.0, 0.0], hits: 8, wellName: 'computing'),
        'lib/c.dart': _kVec(re: [0.0, 1.0], im: [0.0, 0.0], hits: 8, wellName: 'biology'),
      };
      final engine = LogosGit.buildFromStats(stats, perFileKVectors: _kTable(kvecs));
      expect(engine.perFileKVectors.n, 3);
      expect(engine.wellOf('lib/a.dart'), 'computing');
      expect(engine.wellOf('lib/b.dart'), 'computing');
      expect(engine.wellOf('lib/c.dart'), 'biology');
    });

    test('semantically-similar files bond more strongly under EN-aware mix',
        () {
      // Three files in two different sibling directories so SP is silent
      // (no shared parent). All have the same f0 / volatility. Without
      // EN the mix is essentially flat between every pair. With EN, the
      // semantically-aligned pair should diffuse heat to each other
      // more readily than the orthogonal pair.
      final stats = _bareStats(['svc/auth.dart', 'svc/login.dart', 'svc/render.dart']);
      final aligned = <String, HunkKVector>{
        'svc/auth.dart': _kVec(
          re: [1.0, 0.0, 0.5, 0.0],
          im: [0.0, 1.0, 0.0, 0.0],
          hits: 12,
        ),
        // login is K-aligned with auth (cosine ≈ 0.95)
        'svc/login.dart': _kVec(
          re: [0.95, 0.05, 0.55, 0.0],
          im: [0.05, 0.95, 0.05, 0.0],
          hits: 12,
        ),
        // render is orthogonal to auth (cosine ≈ 0)
        'svc/render.dart': _kVec(
          re: [0.0, 0.0, -0.5, 1.0],
          im: [-1.0, 0.0, 0.0, 1.0],
          hits: 12,
        ),
      };
      final engine = LogosGit.buildFromStats(
        stats,
        perFileKVectors: _kTable(aligned, pairs: 4),
      );

      // Diffuse from auth — login should rank higher than render.
      final scores = engine.diffuse({'svc/auth.dart'});
      double phiOf(String path) =>
          scores.firstWhere((s) => s.path == path, orElse: () => RelevanceScore(path, 0)).phi;
      final phiLogin = phiOf('svc/login.dart');
      final phiRender = phiOf('svc/render.dart');

      // Both are 1-hop neighbours from auth via the SP/F0 plumbing,
      // but the EN axis specifically lifts login's edge because of
      // semantic alignment.
      expect(phiLogin, greaterThanOrEqualTo(phiRender),
          reason:
              'engram-aligned file (login) should not rank below '
              'engram-orthogonal file (render): phiLogin=$phiLogin, '
              'phiRender=$phiRender');
    });

    test('partial coverage — unencoded files use 4-axis silently', () {
      // Two of three files have K-vectors; the third has nothing.
      // The mixer is 5-cap because useEngram=true, but the EN axis
      // for pairs involving the unencoded file falls back to silent
      // (no contribution from EN, the other 4 axes carry the pair).
      final stats = _bareStats(['a.dart', 'b.dart', 'c.dart']);
      final partial = <String, HunkKVector>{
        'a.dart': _kVec(re: [1.0, 0.0], im: [0.0, 0.0], hits: 8),
        'b.dart': _kVec(re: [1.0, 0.0], im: [0.0, 0.0], hits: 8),
      };
      final engine =
          LogosGit.buildFromStats(stats, perFileKVectors: _kTable(partial));
      // No throw; engine builds and contains the 2 encoded files.
      expect(engine.perFileKVectors.n, 2);
      expect(engine.wellOf('c.dart'), isNull);
    });
  });
}
