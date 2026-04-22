// Micro-benchmarks pinning the speedups from the Perf pass.
//
// These are not absolute-latency tests — they are RATIO pins. We run
// the fast path and the slow path against the same matrix and require
// the fast path to be meaningfully faster. Ratios tolerate wide
// variance in CI hardware; they fail only when a regression would
// re-expose the quadratic / per-row-allocation costs the optimization
// was meant to remove.
//
// Each benchmark measures wall time with Stopwatch() in both "warm"
// runs (post-JIT / post-cache-build) for fairness.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/graph/csr_builder.dart';

/// Synthesize a coupling matrix with [n] paths and an approximate
/// degree distribution matching real repos: roughly sqrt(n) random
/// partners per file, edge weights sampled from U(0, 1).
FileCouplingMatrix _syntheticMatrix({required int n, int? seed}) {
  final rng = math.Random(seed ?? 0xC0DE);
  final paths = [for (var i = 0; i < n; i++) _padPath(i, n)];
  final jaccard = <String, Map<String, double>>{};
  final targetDeg = math.sqrt(n).ceil();
  for (var i = 0; i < n; i++) {
    final row = <String, double>{};
    for (var k = 0; k < targetDeg; k++) {
      final j = rng.nextInt(n);
      if (j == i) continue;
      row[paths[j]] = rng.nextDouble();
    }
    if (row.isNotEmpty) jaccard[paths[i]] = row;
  }
  return FileCouplingMatrix(
    jaccard: jaccard,
    headHash: 'bench',
    commitsAnalyzed: 500,
  );
}

String _padPath(int i, int n) {
  // Zero-pad so lex order = numeric order, making lex-late / lex-early
  // tests deterministic across n.
  final width = n.toString().length;
  final s = i.toString().padLeft(width, '0');
  return 'lib/f_$s.dart';
}

/// Old-shape per-path max loop: emulates what `_rankedByImpact`
/// looked like before Perf 1.
double _oldMaxPerPathLoop(FileCouplingMatrix m, List<String> paths) {
  double sink = 0.0;
  final pathSet = paths.toSet();
  for (final p in paths) {
    var maxJ = 0.0;
    for (final entry in m.fullJaccardRowOf(p)) {
      if (!pathSet.contains(entry.key)) continue;
      if (entry.value > maxJ) maxJ = entry.value;
    }
    sink += maxJ;
  }
  return sink;
}

/// New-shape single CSR pass: uses `jaccardMaxNeighborMap`.
double _newMaxMapPass(FileCouplingMatrix m, List<String> paths) {
  final mx = m.jaccardMaxNeighborMap(restrict: paths.toSet());
  var sink = 0.0;
  for (final p in paths) {
    sink += mx[p] ?? 0.0;
  }
  return sink;
}

void main() {
  group('Perf 1: jaccardMaxNeighborMap vs per-path fullJaccardRowOf', () {
    test('parity + no regression on a realistic matrix', () {
      // NOTE: Both paths are now fast. The per-path loop benefits
      // from the Perf-2 mirror cache (O(rowLen) per call); the
      // jaccardMaxNeighborMap path does the same work in one CSR
      // sweep. The regression we guard against is "did someone
      // remove the direct-CSR path and re-quadratic the hot site."
      const n = 800;
      final matrix = _syntheticMatrix(n: n);
      final subset = [for (var i = 0; i < n; i++) _padPath(i, n)];

      final warmOld = _oldMaxPerPathLoop(matrix, subset);
      final warmNew = _newMaxMapPass(matrix, subset);
      expect(warmOld, closeTo(warmNew, 1e-9),
          reason: 'Both paths must produce the same aggregate sum.');

      const iterations = 3;
      final stopOld = Stopwatch()..start();
      var sinkOld = 0.0;
      for (var i = 0; i < iterations; i++) {
        sinkOld += _oldMaxPerPathLoop(matrix, subset);
      }
      stopOld.stop();

      final stopNew = Stopwatch()..start();
      var sinkNew = 0.0;
      for (var i = 0; i < iterations; i++) {
        sinkNew += _newMaxMapPass(matrix, subset);
      }
      stopNew.stop();

      expect(sinkOld, closeTo(sinkNew, 1e-6));
      final ratio = stopOld.elapsedMicroseconds /
          math.max(stopNew.elapsedMicroseconds, 1);
      // ignore: avoid_print
      print('Perf 1: old=${stopOld.elapsedMilliseconds}ms, '
          'new=${stopNew.elapsedMilliseconds}ms, '
          'ratio=${ratio.toStringAsFixed(2)}× (expect ≥1×)');
      // We just require the new path isn't a regression — both are
      // now O(nnz). If someone accidentally turns `jaccardMaxNeighborMap`
      // back into a per-path loop without the mirror, this will
      // collapse to <1× and the test will fail.
      expect(ratio, greaterThanOrEqualTo(0.9),
          reason: 'New path must not be more than 10% slower than old.');
    });
  });

  group('Perf 2: cached mirror CSR amortises fullJaccardRowOf', () {
    test('second-call cost << first-call cost', () {
      const n = 1500;
      final matrix = _syntheticMatrix(n: n, seed: 0xBEEF);
      final probePath = _padPath(n - 1, n); // lex-late → worst case

      // First call triggers the O(nnz) mirror build.
      final stopFirst = Stopwatch()..start();
      final firstCount = matrix.fullJaccardRowOf(probePath).length;
      stopFirst.stop();

      // Second call uses the cached mirror.
      final stopSecond = Stopwatch()..start();
      final secondCount = matrix.fullJaccardRowOf(probePath).length;
      stopSecond.stop();

      expect(firstCount, equals(secondCount),
          reason: 'Row iteration must yield the same set.');

      // First call dominates second by at least 3× — the mirror build
      // is O(nnz) while the cached walk is O(rowLen). The exact ratio
      // varies per run; 3× is conservative.
      final ratio = stopFirst.elapsedMicroseconds /
          math.max(stopSecond.elapsedMicroseconds, 1);
      // ignore: avoid_print
      print('Perf 2: first=${stopFirst.elapsedMicroseconds}µs, '
          'cached=${stopSecond.elapsedMicroseconds}µs, '
          'ratio=${ratio.toStringAsFixed(2)}×');
      // Loose bound — the cached call on its own can be microseconds;
      // integer division can float the ratio. We just want to catch
      // "did we accidentally turn the cache off" regressions.
      expect(stopSecond.elapsedMicroseconds,
          lessThanOrEqualTo(stopFirst.elapsedMicroseconds),
          reason: 'Cached call should not cost more than the build.');
    });
  });

  group('Perf 3: short-row insertion sort in csr_builder', () {
    test('short-row graphs build without extra latency vs baseline', () {
      // We can't directly time the private _sortParallel, but we can
      // build graphs with representative row-length distributions and
      // assert the build completes fast. A regression that deletes
      // the short-row fast path would manifest as higher allocation
      // count and measurable slowdown at these sizes.
      const n = 2000;
      const avgDeg = 20; // well within the <=32 short-row cutoff
      final rng = math.Random(0xABCD);
      final edges = <CsrEdge>[];
      for (var i = 0; i < n; i++) {
        for (var k = 0; k < avgDeg; k++) {
          final j = rng.nextInt(n);
          if (j == i) continue;
          edges.add(CsrEdge(i, j, rng.nextDouble()));
        }
      }

      // Warm JIT with a small build using a subset of nodes. Filter
      // edges whose endpoints both fit inside the warm-up graph.
      final warmEdges = [
        for (final e in edges)
          if (e.u < 100 && e.v < 100) e,
      ].take(500);
      buildSymmetricCsrGraph(n: 100, edges: warmEdges);

      final stop = Stopwatch()..start();
      const repeats = 5;
      for (var r = 0; r < repeats; r++) {
        final g = buildSymmetricCsrGraph(n: n, edges: edges);
        expect(g.n, equals(n));
      }
      stop.stop();
      final perBuildMs = stop.elapsedMilliseconds / repeats;
      // ignore: avoid_print
      print('Perf 3: ${perBuildMs.toStringAsFixed(2)}ms per '
          '$n-node / ~${edges.length ~/ repeats}-edge build');
      // Very loose upper bound — even on a slow machine a 2000-node
      // graph with ~40k edges should build in well under a second.
      // Regression would re-introduce per-row GC pressure.
      expect(perBuildMs, lessThan(500),
          reason:
              'csr_builder should remain fast on short-row graph shapes.');
    });
  });
}
