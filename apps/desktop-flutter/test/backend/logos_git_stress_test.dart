// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// logos_git_stress_test.dart — stress + edge-case probing of the CORE engine
// (buildFromStats → diffuse → gatherEvidence → spectral) on pathological and
// large synthetic inputs, with REAL execution. Small connected unit-test
// graphs (logos_git_hardening_test) don't exercise: empty/1/2-node boundaries,
// disconnected components, star/complete topologies, non-ASCII paths (the known
// 7-bit CharCoupling alphabet), or scale. Each case asserts the engine builds,
// queries return only finite φ (no NaN/Inf), the spectrum stays bounded, and —
// the real correctness invariant — heat never crosses a graph disconnect.
//
//   run: flutter test test/backend/logos_git_stress_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';

/// Build stats from a (symmetric) jaccard adjacency. touches/volatility are
/// derived uniformly so the graph topology is the variable under test.
LogosGitStats _stats(Map<String, Map<String, double>> jaccard,
    {int commits = 100}) {
  final paths = <String>{};
  jaccard.forEach((k, v) {
    paths.add(k);
    paths.addAll(v.keys);
  });
  return LogosGitStats(
    touches: {for (final p in paths) p: 5},
    totalCommits: commits,
    volatility: {for (final p in paths) p: 1.0},
    volMean: 1.0,
    volStddev: 0.5,
    coupling: FileCouplingMatrix(
      jaccard: jaccard,
      headHash: 'h',
      commitsAnalyzed: commits,
    ),
    perFileCommitIndices: const {},
  );
}

/// Symmetric sparse random graph: n nodes, ~avgDeg undirected edges each.
Map<String, Map<String, double>> _randomSparse(int n, int avgDeg, int seed) {
  final rng = Random(seed);
  final j = <String, Map<String, double>>{
    for (var i = 0; i < n; i++) 'file_$i.dart': <String, double>{},
  };
  for (var i = 0; i < n; i++) {
    for (var d = 0; d < avgDeg; d++) {
      final t = rng.nextInt(n);
      if (t == i) continue;
      final w = 0.05 + rng.nextDouble() * 0.95;
      j['file_$i.dart']!['file_$t.dart'] = w;
      j['file_$t.dart']!['file_$i.dart'] = w; // keep symmetric
    }
  }
  return j;
}

/// Assert no query produces a non-finite φ, the spectrum is bounded, and
/// gatherEvidence doesn't throw. Returns the engine for further checks.
void _assertHealthy(LogosGit engine) {
  final r = engine.estimateSpectralRadius();
  expect(r.isFinite, isTrue, reason: 'spectral radius must be finite');
  expect(r, lessThanOrEqualTo(2.0 + 1e-6),
      reason: 'normalised-Laplacian spectrum is bounded by 2');

  final nodes = engine.nodePaths;
  if (nodes.isEmpty) return;
  final seed = nodes.first;

  final scores = engine.diffuse({seed}, topK: 50);
  for (final s in scores) {
    expect(s.phi.isFinite, isTrue, reason: 'non-finite φ at ${s.path}');
  }

  // gatherEvidence is the heaviest query path — must not throw or NaN.
  final ev = engine.gatherEvidence(
    focusWeights: {seed: 1.0},
    includeSpectrum: true,
    includeSupportAttribution: true,
    includeSummaryDiagnostics: true,
    topK: 20,
  );
  if (ev != null) {
    expect(ev.coherence.isFinite, isTrue, reason: 'non-finite coherence');
    expect(ev.stability.isFinite, isTrue, reason: 'non-finite stability');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('boundary sizes', () {
    test('empty graph builds and queries without throwing', () {
      final engine = LogosGit.buildFromStats(_stats(const {}));
      expect(engine.nodePaths, isEmpty);
      // Querying a non-existent seed on an empty engine must be safe.
      final scores = engine.diffuse({'nope.dart'}, topK: 10);
      expect(scores, isEmpty);
      expect(engine.estimateSpectralRadius().isFinite, isTrue);
    });

    test('single isolated node', () {
      final engine = LogosGit.buildFromStats(_stats({'solo.dart': const {}}));
      _assertHealthy(engine);
    });

    test('two coupled nodes', () {
      final engine = LogosGit.buildFromStats(_stats({
        'a.dart': {'b.dart': 0.8},
        'b.dart': {'a.dart': 0.8},
      }));
      _assertHealthy(engine);
    });
  });

  group('degenerate topologies', () {
    test('star graph — one hub coupled to many leaves', () {
      const leaves = 200;
      final hub = <String, double>{};
      final j = <String, Map<String, double>>{'hub.dart': hub};
      for (var i = 0; i < leaves; i++) {
        hub['leaf_$i.dart'] = 0.5;
        j['leaf_$i.dart'] = {'hub.dart': 0.5};
      }
      _assertHealthy(LogosGit.buildFromStats(_stats(j)));
    });

    test('complete graph — everyone coupled to everyone', () {
      const n = 60;
      final j = <String, Map<String, double>>{};
      for (var i = 0; i < n; i++) {
        j['c_$i.dart'] = {
          for (var k = 0; k < n; k++)
            if (k != i) 'c_$k.dart': 0.5,
        };
      }
      _assertHealthy(LogosGit.buildFromStats(_stats(j)));
    });

    test('disconnected components — heat must NOT cross the disconnect', () {
      // Two cliques that never co-change. Diffusing from one must give exactly
      // zero φ to the other (the normalised-Laplacian heat kernel preserves
      // the component structure). This is where a single-pass Lanczos basis
      // that misses zero modes would leak — assert it does not.
      final j = <String, Map<String, double>>{
        'A0.dart': {'A1.dart': 0.7, 'A2.dart': 0.6},
        'A1.dart': {'A0.dart': 0.7, 'A2.dart': 0.5},
        'A2.dart': {'A0.dart': 0.6, 'A1.dart': 0.5},
        'B0.dart': {'B1.dart': 0.7, 'B2.dart': 0.6},
        'B1.dart': {'B0.dart': 0.7, 'B2.dart': 0.5},
        'B2.dart': {'B0.dart': 0.6, 'B1.dart': 0.5},
      };
      final engine = LogosGit.buildFromStats(_stats(j));
      _assertHealthy(engine);
      final scores = engine.diffuse({'A0.dart'}, topK: 10);
      for (final s in scores) {
        if (s.path.startsWith('B')) {
          expect(s.phi, closeTo(0.0, 1e-9),
              reason: 'heat leaked across a graph disconnect to ${s.path}');
        }
      }
    });
  });

  group('pathological data', () {
    test('non-ASCII / unicode / emoji / surrogate-pair paths', () {
      // The CharCoupling alphabet is 7-bit ASCII; non-ASCII path bytes must
      // fold gracefully (collision is acceptable; a crash or NaN is not).
      final j = <String, Map<String, double>>{
        'lib/café.dart': {'测试/文件.dart': 0.6, 'naïve/Ø.dart': 0.4},
        '测试/文件.dart': {'lib/café.dart': 0.6, '🚀/rocket🔥.dart': 0.5},
        'naïve/Ø.dart': {'lib/café.dart': 0.4},
        '🚀/rocket🔥.dart': {'测试/文件.dart': 0.5}, // emoji = surrogate pairs
        'ℝ/مرحبا/Ω.dart': {'lib/café.dart': 0.3}, // RTL + math + Greek
      };
      final engine = LogosGit.buildFromStats(_stats(j));
      _assertHealthy(engine);
      // Seed on a unicode path specifically.
      final scores = engine.diffuse({'测试/文件.dart'}, topK: 10);
      for (final s in scores) {
        expect(s.phi.isFinite, isTrue, reason: 'non-finite φ at ${s.path}');
      }
    });

    test('tiny and large edge weights coexist without overflow', () {
      final j = <String, Map<String, double>>{
        'a.dart': {'b.dart': 1e-12, 'c.dart': 1e6},
        'b.dart': {'a.dart': 1e-12, 'c.dart': 0.5},
        'c.dart': {'a.dart': 1e6, 'b.dart': 0.5},
      };
      _assertHealthy(LogosGit.buildFromStats(_stats(j)));
    });

    test('self-coupling on the diagonal is tolerated', () {
      final j = <String, Map<String, double>>{
        'a.dart': {'a.dart': 0.9, 'b.dart': 0.5},
        'b.dart': {'a.dart': 0.5, 'b.dart': 0.9},
      };
      _assertHealthy(LogosGit.buildFromStats(_stats(j)));
    });
  });

  group('scale (real telemetry)', () {
    void scaleCase(int n, int avgDeg) {
      final j = _randomSparse(n, avgDeg, 0xC0FFEE ^ n);
      final stats = j.isEmpty ? _stats(const {}) : _stats(j);
      final probe = <String, int>{};
      final swBuild = Stopwatch()..start();
      final engine = LogosGit.buildFromStats(stats, probeTimingsUs: probe);
      swBuild.stop();
      final nodes = engine.nodePaths;
      final seed = nodes[(n ~/ 3).clamp(0, nodes.length - 1)];
      final swDiff = Stopwatch()..start();
      final scores = engine.diffuse({seed}, topK: 50);
      swDiff.stop();
      for (final s in scores) {
        expect(s.phi.isFinite, isTrue);
      }
      final top = probe.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final phases =
          top.take(4).map((e) => '${e.key}=${(e.value / 1000).round()}ms').join('  ');
      // ignore: avoid_print
      print('  [SCALE n=$n deg=$avgDeg] build='
          '${(swBuild.elapsedMicroseconds / 1000).round()}ms  '
          'diffuse=${(swDiff.elapsedMicroseconds / 1000).toStringAsFixed(2)}ms  '
          '| $phases');
    }

    // Fixed degree across n so the growth law is a clean function of node count.
    test('n=1000 sparse', () => scaleCase(1000, 6),
        timeout: const Timeout(Duration(minutes: 2)));
    test('n=2000 sparse', () => scaleCase(2000, 6),
        timeout: const Timeout(Duration(minutes: 2)));
    test('n=4000 sparse', () => scaleCase(4000, 6),
        timeout: const Timeout(Duration(minutes: 4)));
    test('n=8000 sparse', () => scaleCase(8000, 6),
        timeout: const Timeout(Duration(minutes: 8)));
  });
}
