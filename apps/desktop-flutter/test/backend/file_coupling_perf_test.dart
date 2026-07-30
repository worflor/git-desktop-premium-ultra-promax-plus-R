// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

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

/// Fastest of [reps] runs, in microseconds.
///
/// A single wall-clock sample cannot support a tight ratio: the scheduler
/// can steal time from either side, and this suite runs alongside real
/// git subprocesses and (in a full-tree run) a release build. Theft only
/// ever ADDS time, so the MINIMUM is the estimator that survives it —
/// taking the min of both sides cancels most of the contention instead
/// of comparing one unlucky sample against one lucky one.
int _bestOfMicros(int reps, void Function() body) {
  var best = -1;
  for (var i = 0; i < reps; i++) {
    final sw = Stopwatch()..start();
    body();
    sw.stop();
    final us = sw.elapsedMicroseconds;
    if (best < 0 || us < best) best = us;
  }
  return best < 1 ? 1 : best;
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

      var sinkOld = 0.0;
      var sinkNew = 0.0;
      final bestOld =
          _bestOfMicros(5, () => sinkOld = _oldMaxPerPathLoop(matrix, subset));
      final bestNew =
          _bestOfMicros(5, () => sinkNew = _newMaxMapPass(matrix, subset));

      expect(sinkOld, closeTo(sinkNew, 1e-6));
      final ratio = bestOld / bestNew;
      // ignore: avoid_print
      print('Perf 1: old=${bestOld}us, new=${bestNew}us, '
          'ratio=${ratio.toStringAsFixed(2)}x (best of 5 each)');
      // The threshold sits in the GAP BETWEEN TWO MEASURED POPULATIONS,
      // which is the only way a timing bound is worth anything:
      //
      //   healthy, idle machine     5.7x
      //   healthy, under a full-tree run + release build   5.9x - 9.7x
      //   direct-CSR path removed (new = old, simulated)   1.2x
      //
      // So 2x passes every healthy run measured, including contended
      // ones, and fails the regression this test exists to catch. The
      // old form asserted >=0.9 on a SINGLE sample: flaky (it went red
      // during a contended full-tree run on code it had just passed)
      // AND blind (the simulated collapse scores 1.17x, which >=0.9
      // happily accepts). A first pass at this fix used >=0.5, which
      // fixed the flake and kept the blindness — worth stating, because
      // loosening a bound to silence noise without checking where the
      // BROKEN population lands is how a guard turns into decoration.
      expect(ratio, greaterThanOrEqualTo(2.0),
          reason: 'the direct-CSR path collapsed toward per-path scanning '
              '(old=${bestOld}us new=${bestNew}us, ratio '
              '${ratio.toStringAsFixed(2)}x): healthy runs measure 5.7x+ '
              'even under load, a removed fast path measures ~1.2x');
    });
  });

  group('Perf 2: cached mirror CSR amortises fullJaccardRowOf', () {
    test('second-call cost << first-call cost', () {
      const n = 1500;
      final matrix = _syntheticMatrix(n: n, seed: 0xBEEF);
      final probePath = _padPath(n - 1, n); // lex-late → worst case

      // First call triggers the O(nnz) mirror build — inherently a
      // one-shot measurement, since it can only happen once per matrix.
      final stopFirst = Stopwatch()..start();
      final firstCount = matrix.fullJaccardRowOf(probePath).length;
      stopFirst.stop();

      // The cached walk CAN be repeated, so take its best of 5: that is
      // what keeps a stolen timeslice on one cached call from inverting
      // the comparison.
      var secondCount = 0;
      final bestCached = _bestOfMicros(
          5, () => secondCount = matrix.fullJaccardRowOf(probePath).length);

      expect(firstCount, equals(secondCount),
          reason: 'Row iteration must yield the same set.');

      final ratio = stopFirst.elapsedMicroseconds / bestCached;
      // ignore: avoid_print
      print('Perf 2: first=${stopFirst.elapsedMicroseconds}us, '
          'cached=${bestCached}us, ratio=${ratio.toStringAsFixed(2)}x');
      // Threshold from the two measured populations, same method as
      // Perf 1:
      //
      //   mirror cache live      ~830x (build ~3300us, cached ~4us)
      //   cache disabled         ~1x   (every call rebuilds O(nnz))
      //
      // `cached <= build` — what this asserted before — is satisfied by
      // the BROKEN state: if every call rebuilds, both numbers measure
      // the same work and best-of-5 on the cached side lands it under a
      // single build sample almost every time. The review caught that
      // the claim ("the mirror cache is off") could not fail, which is
      // the same defect Perf 1 had: an assertion that accepts the thing
      // it names. 20x sits three orders of magnitude clear of the
      // disabled case and forty-fold clear of the live one.
      expect(ratio, greaterThanOrEqualTo(20.0),
          reason: 'repeated fullJaccardRowOf is no longer amortised '
              '(build=${stopFirst.elapsedMicroseconds}us '
              'cached=${bestCached}us, ratio ${ratio.toStringAsFixed(2)}x): '
              'a live mirror measures hundreds of x, a rebuild-every-call '
              'measures ~1x');
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
