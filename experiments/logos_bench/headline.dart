// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: LicenseRef-WLCSL-1.0
// See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

// Pure-dart cold-build scaling harness for LogosGit.buildFromStats.
//
// Run (from repo root):
//   dart --packages=apps/desktop-flutter/.dart_tool/package_config.json \
//        experiments/logos_bench/headline.dart
//
// Synthesises realistic large-repo LogosGitStats at a range of sizes,
// warms up once (JIT), then times >=5 trials of buildFromStats per size,
// reporting median + p95 wall-clock, peak RSS, and the per-phase
// probeTimingsUs breakdown. Fits log-log scaling per phase.
//
// lib/** is untouched — this only consumes the public engine API.

import 'dart:io';
import 'dart:math' as math;

import '../../apps/desktop-flutter/lib/backend/logos_git.dart';
import '../../apps/desktop-flutter/lib/backend/file_coupling.dart';

/// Deterministic LCG so runs are reproducible (no result-changing
/// randomness in the engine itself — this only shapes the synthetic
/// input distribution, which is fixed by seed).
class _Rng {
  int _s;
  _Rng(this._s);
  int nextInt(int n) {
    // 64-bit LCG (Knuth MMIX constants), take high bits.
    _s = (_s * 6364136223846793005 + 1442695040888963407) & 0x7fffffffffffffff;
    return (_s >>> 17) % n;
  }

  double nextDouble() => nextInt(1 << 30) / (1 << 30);
}

/// Build a realistic repo: n files, c commits, each commit touches f
/// files where f is mostly small (1-4) with an occasional large commit
/// (refactor / mass rename). Co-change coupling (jaccard) is derived
/// from co-occurrence counts, capped per file to mimic the real
/// builder's top-k neighbour budget. Per-file commit-index series feed
/// the AR(2) curvature phase.
LogosGitStats synth(int n, {required int seed}) {
  final rng = _Rng(seed);
  final paths = List<String>.generate(n, (i) {
    // Spread across a directory tree so SP / dirIndex has real fan-out.
    final dir = i % 200; // ~200 directories
    final sub = (i ~/ 200) % 40;
    return 'lib/pkg$dir/mod$sub/file$i.dart';
  });

  // commit count scales with files (real repos: more files => more
  // history). ~3 commits per file, capped.
  final c = math.min(60000, n * 3);

  final touches = <String, int>{};
  final volatility = <String, double>{};
  final perFileCommitIndices = <String, List<int>>{};
  // Co-occurrence counts: pathId -> (pathId -> count). Symmetric.
  // Kept as nested int maps, capped to top-k per row at the end.
  final cooc = List<Map<int, int>>.generate(n, (_) => <int, int>{});
  final fileCommitCount = List<int>.filled(n, 0);

  for (var commit = 0; commit < c; commit++) {
    // Fan-out: 85% tiny (1-4), 13% medium (5-20), 2% large (40-200).
    final roll = rng.nextDouble();
    final int f;
    if (roll < 0.85) {
      f = 1 + rng.nextInt(4);
    } else if (roll < 0.98) {
      f = 5 + rng.nextInt(16);
    } else {
      f = 40 + rng.nextInt(160);
    }
    // Pick f distinct files. Bias toward a "hot" working-set window so
    // coupling clusters form (locality), with occasional global reach.
    final touched = <int>{};
    final window = 1 + rng.nextInt(n);
    final base = rng.nextInt(n);
    var guard = 0;
    while (touched.length < f && guard < f * 4) {
      guard++;
      final id = (base + rng.nextInt(window)) % n;
      touched.add(id);
    }
    final tl = touched.toList();
    for (final id in tl) {
      fileCommitCount[id]++;
      final p = paths[id];
      (perFileCommitIndices[p] ??= <int>[]).add(commit);
      for (final other in tl) {
        if (other == id) continue;
        cooc[id][other] = (cooc[id][other] ?? 0) + 1;
      }
    }
  }

  // Touches + volatility from commit counts.
  var volSum = 0.0;
  var volSumSq = 0.0;
  for (var i = 0; i < n; i++) {
    final ct = fileCommitCount[i];
    touches[paths[i]] = ct;
    // volatility ~ lines churned proxy: count * mean-hunk-size noise.
    final vol = ct * (2.0 + rng.nextDouble() * 8.0);
    volatility[paths[i]] = vol;
    volSum += vol;
    volSumSq += vol * vol;
  }
  final volMean = volSum / n;
  final volStddev =
      math.sqrt(math.max(0.0, volSumSq / n - volMean * volMean));

  // Build jaccard nested map, top-k capped per row (real builders cap
  // neighbour fan-out; d ~ 50 is typical). Jaccard estimated from
  // co-occurrence: |A∩B| / (|A|+|B|-|A∩B|).
  const topK = 50;
  final jaccard = <String, Map<String, double>>{};
  for (var i = 0; i < n; i++) {
    final row = cooc[i];
    if (row.isEmpty) continue;
    // Top-k by raw co-occurrence count.
    final entries = row.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final keep = entries.length > topK ? entries.sublist(0, topK) : entries;
    final m = <String, double>{};
    final ci = fileCommitCount[i];
    for (final e in keep) {
      final j = e.key;
      final inter = e.value;
      final cj = fileCommitCount[j];
      final union = ci + cj - inter;
      final jac = union > 0 ? inter / union : 0.0;
      if (jac > 0.001) m[paths[j]] = jac;
    }
    if (m.isNotEmpty) jaccard[paths[i]] = m;
  }

  final coupling = FileCouplingMatrix(
    jaccard: jaccard,
    headHash: 'bench$n',
    commitsAnalyzed: c,
  );

  return LogosGitStats(
    touches: touches,
    totalCommits: c,
    volatility: volatility,
    volMean: volMean,
    volStddev: volStddev,
    coupling: coupling,
    perFileCommitIndices: perFileCommitIndices,
  );
}

double _median(List<double> xs) {
  final s = List<double>.from(xs)..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : 0.5 * (s[mid - 1] + s[mid]);
}

double _percentile(List<double> xs, double p) {
  final s = List<double>.from(xs)..sort();
  final idx = ((s.length - 1) * p).round();
  return s[idx];
}

void main() {
  final sizes = [200, 1000, 5000, 20000];
  const trials = 7;

  // Per-phase median microseconds per size, for log-log fit.
  final phaseSeries = <String, List<double>>{};
  final sizeAxis = <int>[];
  final totalMedian = <double>[];

  print('=== logos buildFromStats cold-build scaling ===');
  print('dart ${Platform.version}');
  print('trials=$trials (warmup discarded)');
  print('');

  for (final n in sizes) {
    final stats = synth(n, seed: 0xC0FFEE + n);
    // Report graph shape.
    var edgeCount = 0;
    for (final m in stats.coupling.paths) {
      edgeCount += stats.coupling.jaccardKeysOf(m).length;
    }
    // Warmup (JIT) — discard.
    LogosGit.buildFromStats(stats);

    final wall = <double>[];
    final phaseAccum = <String, List<double>>{};
    for (var t = 0; t < trials; t++) {
      final probe = <String, int>{};
      final sw = Stopwatch()..start();
      LogosGit.buildFromStats(stats, probeTimingsUs: probe);
      sw.stop();
      wall.add(sw.elapsedMicroseconds / 1000.0); // ms
      probe.forEach((k, v) {
        (phaseAccum[k] ??= <double>[]).add(v.toDouble());
      });
    }

    final med = _median(wall);
    final p95 = _percentile(wall, 0.95);
    final rss = ProcessInfo.currentRss / (1024 * 1024);

    sizeAxis.add(n);
    totalMedian.add(med);

    // Separate real phase TIMINGS (microseconds) from the engine's
    // work-COUNTERS, which share the same map but carry counts:
    //   _probePairsScored  = pairs scored (== coupling edges m examined)
    //   _probeMixerCalls   = BornMixer.mix calls
    //   _probeTransportCalls = directed transport-lane evals (2 per pair)
    final phaseMed = <String, double>{};
    final counters = <String, double>{};
    phaseAccum.forEach((k, v) {
      if (k.startsWith('_probe')) {
        counters[k] = _median(v);
      } else {
        phaseMed[k] = _median(v);
      }
    });

    print('--- n=$n  files=${stats.coupling.paths.length}  '
        'directedCouplingEdges=$edgeCount  commits=${stats.totalCommits} ---');
    print('  wall median=${med.toStringAsFixed(2)}ms  '
        'p95=${p95.toStringAsFixed(2)}ms  rss=${rss.toStringAsFixed(1)}MB');
    print('  counters: pairsScored=${counters['_probePairsScored']?.toInt()}  '
        'mixerCalls=${counters['_probeMixerCalls']?.toInt()}  '
        'transportCalls=${counters['_probeTransportCalls']?.toInt()}');
    // Phase medians, sorted by cost. Percentages over real timed phases.
    final ordered = phaseMed.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalUs = phaseMed.values.fold<double>(0, (a, b) => a + b);
    for (final e in ordered) {
      final pct = totalUs > 0 ? 100 * e.value / totalUs : 0;
      print('    ${e.key.padRight(22)} '
          '${(e.value / 1000).toStringAsFixed(3).padLeft(9)}ms  '
          '${pct.toStringAsFixed(1).padLeft(5)}%');
      (phaseSeries[e.key] ??= <double>[]).add(e.value);
    }
    print('    ${"[sum timed phases]".padRight(22)} '
        '${(totalUs / 1000).toStringAsFixed(3).padLeft(9)}ms');
    print('');
  }

  // Log-log scaling fit per phase: slope of log(t) vs log(n) between
  // smallest and largest size where the phase has data for all sizes.
  print('=== scaling fit (log-log slope = empirical exponent in n) ===');
  final fitLines = <String>[];
  phaseSeries.forEach((phase, times) {
    if (times.length < 2) return;
    // Use first and last size with data.
    final logN0 = math.log(sizeAxis[0].toDouble());
    final logN1 = math.log(sizeAxis[sizeAxis.length - 1].toDouble());
    final t0 = times.first;
    final t1 = times.last;
    if (t0 <= 0 || t1 <= 0) return;
    final slope = (math.log(t1) - math.log(t0)) / (logN1 - logN0);
    fitLines.add('  ${phase.padRight(22)} exponent~${slope.toStringAsFixed(2)}  '
        '(${(t0 / 1000).toStringAsFixed(2)}ms -> ${(t1 / 1000).toStringAsFixed(2)}ms)');
  });
  // total fit
  {
    final logN0 = math.log(sizeAxis[0].toDouble());
    final logN1 = math.log(sizeAxis.last.toDouble());
    final slope = (math.log(totalMedian.last) - math.log(totalMedian.first)) /
        (logN1 - logN0);
    fitLines.add('  ${"TOTAL".padRight(22)} exponent~${slope.toStringAsFixed(2)}  '
        '(${totalMedian.first.toStringAsFixed(2)}ms -> ${totalMedian.last.toStringAsFixed(2)}ms)');
  }
  fitLines.sort();
  fitLines.forEach(print);
}
