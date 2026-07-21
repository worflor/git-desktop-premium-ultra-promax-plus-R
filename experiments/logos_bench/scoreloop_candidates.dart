// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: LicenseRef-WLCSL-1.0
// See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

// Isolated candidate-assembly micro-benchmark for the scoreLoop kernel.
//
// Run (from repo root):
//   dart --packages=experiments/logos_bench/package_config.json \
//        experiments/logos_bench/scoreloop_candidates.dart
//
// WHAT THIS ISOLATES
// ------------------
// The scoreLoop (logos_git.dart:2634-2881) is 56-70% of every cold build
// and shows superlinear per-edge cost. The headline harness confirms it:
//   n=5000 : scoreLoop 250.2ms / 187325 pairs = 1.336 us/pair
//   n=20000: scoreLoop 1689.4ms / 767582 pairs = 2.201 us/pair
//   -> per-edge cost grew 1.65x while edges grew 4.1x (superlinear).
//
// HYPOTHESIS (from brief): the superlinear term is NOT edge growth or the
// Born mixer math. It is the per-node candidate assembly:
//   final candidates = <int>{};            // fresh HashSet per node
//   final transportCandidates = <int>{};   // fresh HashSet per node
//   ... add() from CC neighbours + dir siblings + transport seeds ...
// A fresh Set<int> per node means n allocations + per-element hashing +
// rehash-on-grow, and the GC pressure of n short-lived hash tables. That
// cost scales with (n x avg-candidates) but with a hashing/alloc constant
// that worsens as the live heap grows -> superlinear wall time.
//
// This file reproduces the EXACT pre-loop precompute and the EXACT
// candidate-assembly block (lines 2640-2711) from the engine, using only
// PUBLIC engine symbols (TransportRoles, FileCouplingMatrix.jaccardKeysOf).
// For useEngram=false (no synthetic K-vectors) the well-siblings + EN
// sources are absent in the real engine too, so this is the COMPLETE
// candidate set the engine builds for this input -- not an approximation.
//
// It then provides an OPTIMIZED assembly (reused cleared membership buffer +
// reused output list, lazily reset over only the touched slots) that
// produces the SAME candidate ids in the SAME insertion order (so the
// downstream min-heap tie-handling is bit-for-bit identical), and proves
// equality node-by-node before timing.
//
// lib/** is untouched. This consumes only the public engine API.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../apps/desktop-flutter/lib/backend/logos_git.dart';
import '../../apps/desktop-flutter/lib/backend/file_coupling.dart';
import '../../apps/desktop-flutter/lib/backend/logos_git_integrity.dart'
    show TransportRoles;

// ---------------------------------------------------------------------------
// Synthetic stats (identical distribution to headline.dart).
// ---------------------------------------------------------------------------
class _Rng {
  int _s;
  _Rng(this._s);
  int nextInt(int n) {
    _s = (_s * 6364136223846793005 + 1442695040888963407) & 0x7fffffffffffffff;
    return (_s >>> 17) % n;
  }

  double nextDouble() => nextInt(1 << 30) / (1 << 30);
}

LogosGitStats synth(int n, {required int seed}) {
  final rng = _Rng(seed);
  final paths = List<String>.generate(n, (i) {
    final dir = i % 200;
    final sub = (i ~/ 200) % 40;
    return 'lib/pkg$dir/mod$sub/file$i.dart';
  });

  final c = math.min(60000, n * 3);

  final touches = <String, int>{};
  final volatility = <String, double>{};
  final perFileCommitIndices = <String, List<int>>{};
  final cooc = List<Map<int, int>>.generate(n, (_) => <int, int>{});
  final fileCommitCount = List<int>.filled(n, 0);

  for (var commit = 0; commit < c; commit++) {
    final roll = rng.nextDouble();
    final int f;
    if (roll < 0.85) {
      f = 1 + rng.nextInt(4);
    } else if (roll < 0.98) {
      f = 5 + rng.nextInt(16);
    } else {
      f = 40 + rng.nextInt(160);
    }
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

  var volSum = 0.0;
  var volSumSq = 0.0;
  for (var i = 0; i < n; i++) {
    final ct = fileCommitCount[i];
    touches[paths[i]] = ct;
    final vol = ct * (2.0 + rng.nextDouble() * 8.0);
    volatility[paths[i]] = vol;
    volSum += vol;
    volSumSq += vol * vol;
  }
  final volMean = volSum / n;
  final volStddev = math.sqrt(math.max(0.0, volSumSq / n - volMean * volMean));

  const topK = 50;
  final jaccard = <String, Map<String, double>>{};
  for (var i = 0; i < n; i++) {
    final row = cooc[i];
    if (row.isEmpty) continue;
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

// ---------------------------------------------------------------------------
// Faithful reproduction of the engine's pre-loop precompute.
//
// These mirror logos_git.dart exactly for the useEngram=false path:
//   nodePaths = sorted union of stat key sets   (line 2355-2364)
//   pathToId                                     (line 2365-2368)
//   pathSegments = path.split('/')               (line 2508-2509)
//   transportRoles = TransportRoles.of(path)     (line 2518-2519)
//   dirIndex: parent-dir -> [node ids]           (line 2575-2581)
//   transportSeedIndex: seedKey -> [node ids]    (line 2584-2587)
// ---------------------------------------------------------------------------
class _Precompute {
  final List<String> nodePaths;
  final Map<String, int> pathToId;
  final List<List<String>> pathSegments;
  final List<TransportRoles> transportRoles;
  final Map<String, List<int>> dirIndex;
  final Map<String, List<int>> transportSeedIndex;
  final FileCouplingMatrix coupling;
  int get n => nodePaths.length;

  _Precompute._(this.nodePaths, this.pathToId, this.pathSegments,
      this.transportRoles, this.dirIndex, this.transportSeedIndex,
      this.coupling);

  factory _Precompute.from(LogosGitStats stats) {
    final pathSet = <String>{};
    pathSet.addAll(stats.touches.keys);
    pathSet.addAll(stats.rawTouches.keys);
    pathSet.addAll(stats.touchMass.keys);
    pathSet.addAll(stats.volatility.keys);
    pathSet.addAll(stats.coupling.paths);
    pathSet.addAll(stats.integrityByPath.keys);
    final nodePaths = pathSet.toList()..sort();
    final pathToId = <String, int>{};
    for (var i = 0; i < nodePaths.length; i++) {
      pathToId[nodePaths[i]] = i;
    }
    final n = nodePaths.length;
    final pathSegments =
        List<List<String>>.generate(n, (i) => nodePaths[i].split('/'));
    final transportRoles =
        List<TransportRoles>.generate(n, (i) => TransportRoles.of(nodePaths[i]));
    final dirIndex = <String, List<int>>{};
    final transportSeedIndex = <String, List<int>>{};
    for (var i = 0; i < n; i++) {
      final p = nodePaths[i];
      final slash = p.lastIndexOf('/');
      if (slash > 0) {
        final parent = p.substring(0, slash);
        (dirIndex[parent] ??= <int>[]).add(i);
      }
      final transportKey = transportRoles[i].seedKey;
      if (transportKey != null) {
        (transportSeedIndex[transportKey] ??= <int>[]).add(i);
      }
    }
    return _Precompute._(nodePaths, pathToId, pathSegments, transportRoles,
        dirIndex, transportSeedIndex, stats.coupling);
  }
}

// ---------------------------------------------------------------------------
// BASELINE candidate assembly -- EXACT copy of logos_git.dart 2640-2711
// (useEngram=false: well-siblings block omitted exactly as the engine omits
// it when wellIdToNodes == null). Returns the two candidate id lists in
// engine insertion order.
// ---------------------------------------------------------------------------
class _Assembled {
  final List<int> candidates;
  final List<int> transportCandidates;
  _Assembled(this.candidates, this.transportCandidates);
}

_Assembled assembleBaseline(_Precompute pc, int i) {
  final a = pc.nodePaths[i];
  final candidates = <int>{};
  final transportCandidates = <int>{};
  for (final neighbour in pc.coupling.jaccardKeysOf(a)) {
    final id = pc.pathToId[neighbour];
    if (id != null && id != i) candidates.add(id);
  }
  final segA = pc.pathSegments[i];
  if (segA.length > 1) {
    final cut = a.lastIndexOf('/');
    final parent = cut > 0 ? a.substring(0, cut) : '';
    final siblings = pc.dirIndex[parent];
    if (siblings != null) {
      for (final id in siblings) {
        if (id != i) candidates.add(id);
      }
    }
  }
  final transportKey = pc.transportRoles[i].seedKey;
  if (transportKey != null) {
    final seeded = pc.transportSeedIndex[transportKey];
    if (seeded != null) {
      for (final id in seeded) {
        if (id != i) transportCandidates.add(id);
      }
    }
  }
  return _Assembled(candidates.toList(), transportCandidates.toList());
}

// ---------------------------------------------------------------------------
// OPTIMIZED candidate assembly.
//
// Root cause being removed: the per-node `<int>{}` HashSet allocation +
// element hashing + rehash-on-grow, paid n times. Replaced by:
//   - one reused Int32List `seen` membership-epoch buffer (size n). A
//     monotonically increasing epoch tag marks "seen this node" so the
//     buffer is reset in O(1) per node (just bump the epoch), never cleared
//     -- no O(n) wipe, no realloc.
//   - reused output List<int> buffers (`.length = 0` keeps backing store).
//
// Insertion-order semantics are preserved exactly: an id is appended the
// first time it is seen, in the same source order (CC neighbours, then dir
// siblings) as the baseline, so the produced list equals the baseline's
// `Set.toList()` element-for-element. transportCandidates likewise.
//
// Two membership epochs are tracked in one buffer using two tag spaces so
// `candidates` and `transportCandidates` never collide.
// ---------------------------------------------------------------------------
class _OptAssembler {
  final _Precompute pc;
  final Int32List seenCand; // epoch tag per node for `candidates`
  final Int32List seenTrans; // epoch tag per node for `transportCandidates`
  int _epochCand = 0;
  int _epochTrans = 0;
  final List<int> candidates = <int>[];
  final List<int> transportCandidates = <int>[];

  _OptAssembler(this.pc)
      : seenCand = Int32List(pc.n),
        seenTrans = Int32List(pc.n);

  void assemble(int i) {
    candidates.length = 0;
    transportCandidates.length = 0;
    final epoch = ++_epochCand;
    final a = pc.nodePaths[i];
    for (final neighbour in pc.coupling.jaccardKeysOf(a)) {
      final id = pc.pathToId[neighbour];
      if (id != null && id != i && seenCand[id] != epoch) {
        seenCand[id] = epoch;
        candidates.add(id);
      }
    }
    final segA = pc.pathSegments[i];
    if (segA.length > 1) {
      final cut = a.lastIndexOf('/');
      final parent = cut > 0 ? a.substring(0, cut) : '';
      final siblings = pc.dirIndex[parent];
      if (siblings != null) {
        for (final id in siblings) {
          if (id != i && seenCand[id] != epoch) {
            seenCand[id] = epoch;
            candidates.add(id);
          }
        }
      }
    }
    final tEpoch = ++_epochTrans;
    final transportKey = pc.transportRoles[i].seedKey;
    if (transportKey != null) {
      final seeded = pc.transportSeedIndex[transportKey];
      if (seeded != null) {
        for (final id in seeded) {
          if (id != i && seenTrans[id] != tEpoch) {
            seenTrans[id] = tEpoch;
            transportCandidates.add(id);
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Equality proof: baseline vs optimized produce identical id lists (order
// included) for every node.
// ---------------------------------------------------------------------------
bool _listEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var k = 0; k < a.length; k++) {
    if (a[k] != b[k]) return false;
  }
  return true;
}

bool validate(_Precompute pc) {
  final opt = _OptAssembler(pc);
  var totalCand = 0;
  var totalTrans = 0;
  for (var i = 0; i < pc.n; i++) {
    final base = assembleBaseline(pc, i);
    opt.assemble(i);
    if (!_listEq(base.candidates, opt.candidates)) {
      stderr.writeln('MISMATCH candidates at node $i');
      stderr.writeln('  base=${base.candidates.take(20).toList()}...');
      stderr.writeln('  opt =${opt.candidates.take(20).toList()}...');
      return false;
    }
    if (!_listEq(base.transportCandidates, opt.transportCandidates)) {
      stderr.writeln('MISMATCH transportCandidates at node $i');
      return false;
    }
    totalCand += base.candidates.length;
    totalTrans += base.transportCandidates.length;
  }
  stdout.writeln('  validate: OK  totalCand=$totalCand  '
      'totalTrans=$totalTrans  (bit-for-bit identical id lists)');
  return true;
}

// ---------------------------------------------------------------------------
// Timing.
// ---------------------------------------------------------------------------
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

/// Sink to defeat dead-code elimination of the assembly work.
int _sink = 0;

double timeBaseline(_Precompute pc, int trials) {
  // warmup
  for (var i = 0; i < pc.n; i++) {
    final r = assembleBaseline(pc, i);
    _sink ^= r.candidates.length ^ r.transportCandidates.length;
  }
  final ms = <double>[];
  for (var t = 0; t < trials; t++) {
    final sw = Stopwatch()..start();
    var acc = 0;
    for (var i = 0; i < pc.n; i++) {
      final r = assembleBaseline(pc, i);
      acc ^= r.candidates.length ^ r.transportCandidates.length;
      // touch ids so the lists can't be elided
      if (r.candidates.isNotEmpty) acc ^= r.candidates[0];
      if (r.transportCandidates.isNotEmpty) acc ^= r.transportCandidates[0];
    }
    sw.stop();
    _sink ^= acc;
    ms.add(sw.elapsedMicroseconds / 1000.0);
  }
  return _median(ms);
}

double timeOptimized(_Precompute pc, int trials, {List<double>? p95Out}) {
  final opt = _OptAssembler(pc);
  for (var i = 0; i < pc.n; i++) {
    opt.assemble(i);
    _sink ^= opt.candidates.length ^ opt.transportCandidates.length;
  }
  final ms = <double>[];
  for (var t = 0; t < trials; t++) {
    final sw = Stopwatch()..start();
    var acc = 0;
    for (var i = 0; i < pc.n; i++) {
      opt.assemble(i);
      acc ^= opt.candidates.length ^ opt.transportCandidates.length;
      if (opt.candidates.isNotEmpty) acc ^= opt.candidates[0];
      if (opt.transportCandidates.isNotEmpty) acc ^= opt.transportCandidates[0];
    }
    sw.stop();
    _sink ^= acc;
    ms.add(sw.elapsedMicroseconds / 1000.0);
  }
  if (p95Out != null) p95Out.add(_percentile(ms, 0.95));
  return _median(ms);
}

void main() {
  final sizes = [200, 1000, 5000, 20000];
  const trials = 15;

  stdout.writeln('=== scoreLoop candidate-assembly isolation ===');
  stdout.writeln('dart ${Platform.version}');
  stdout.writeln('trials=$trials (warmup discarded)');
  stdout.writeln('isolates lines 2640-2711 (Set<int> candidate assembly + '
      'dedup) with all inputs precomputed identically to the engine.');
  stdout.writeln('');

  final ns = <int>[];
  final baseMed = <double>[];
  final optMed = <double>[];
  final basePerNode = <double>[];
  final optPerNode = <double>[];

  for (final n in sizes) {
    final stats = synth(n, seed: 0xC0FFEE + n);
    final pc = _Precompute.from(stats);

    var totalCand = 0;
    var totalAdds = 0; // total deduped candidate ids produced (work units)
    {
      final opt = _OptAssembler(pc);
      for (var i = 0; i < pc.n; i++) {
        totalCand += pc.coupling.jaccardKeysOf(pc.nodePaths[i]).length;
        opt.assemble(i);
        totalAdds += opt.candidates.length + opt.transportCandidates.length;
      }
    }

    stdout.writeln('--- n=$n  files=${pc.n}  ccDirectedEdges=$totalCand  '
        'dedupedCandidateAdds=$totalAdds ---');
    if (!validate(pc)) {
      stderr.writeln('VALIDATION FAILED at n=$n -- aborting (optimization is '
          'not numerically identical).');
      exit(1);
    }

    final bMed = timeBaseline(pc, trials);
    final p95 = <double>[];
    final oMed = timeOptimized(pc, trials, p95Out: p95);
    final rss = ProcessInfo.currentRss / (1024 * 1024);

    // Per-CANDIDATE-ADD cost in microseconds (whole-pass median / adds).
    // This is the true per-edge work unit the brief's "1.37" refers to.
    final bPer = (bMed * 1000.0) / totalAdds;
    final oPer = (oMed * 1000.0) / totalAdds;

    ns.add(n);
    baseMed.add(bMed);
    optMed.add(oMed);
    basePerNode.add(bPer);
    optPerNode.add(oPer);

    stdout.writeln('  baseline  Set<int>/node : median=${bMed.toStringAsFixed(3)}ms'
        '  perAdd=${bPer.toStringAsFixed(4)}us');
    stdout.writeln('  optimized reused-buffer  : median=${oMed.toStringAsFixed(3)}ms'
        '  p95=${p95.first.toStringAsFixed(3)}ms'
        '  perAdd=${oPer.toStringAsFixed(4)}us');
    stdout.writeln('  speedup=${(bMed / oMed).toStringAsFixed(2)}x'
        '  rss=${rss.toStringAsFixed(1)}MB');
    stdout.writeln('');
  }

  // Scaling fits (log-log slope) of per-NODE cost. Flat per-node => the
  // assembly is the superlinear term iff baseline slope > 0 and the
  // optimized slope ~ 0.
  double slope(List<double> y) {
    final l0 = math.log(ns.first.toDouble());
    final l1 = math.log(ns.last.toDouble());
    return (math.log(y.last) - math.log(y.first)) / (l1 - l0);
  }

  stdout.writeln('=== per-CANDIDATE-ADD cost scaling (log-log slope in n) ===');
  stdout.writeln('  (this is the per-edge work unit; brief quotes baseline ~1.37 '
      '5k->20k)');
  stdout.writeln('  baseline  perAdd slope = ${slope(basePerNode).toStringAsFixed(3)}'
      '  (${basePerNode.first.toStringAsFixed(4)}us -> '
      '${basePerNode.last.toStringAsFixed(4)}us)');
  stdout.writeln('  optimized perAdd slope = ${slope(optPerNode).toStringAsFixed(3)}'
      '  (${optPerNode.first.toStringAsFixed(4)}us -> '
      '${optPerNode.last.toStringAsFixed(4)}us)');
  // Explicit 5k->20k per-add ratio (the brief's headline figure).
  final i5 = ns.indexOf(5000);
  final i20 = ns.indexOf(20000);
  if (i5 >= 0 && i20 >= 0) {
    stdout.writeln('  baseline  perAdd 5k->20k ratio = '
        '${(basePerNode[i20] / basePerNode[i5]).toStringAsFixed(3)}');
    stdout.writeln('  optimized perAdd 5k->20k ratio = '
        '${(optPerNode[i20] / optPerNode[i5]).toStringAsFixed(3)}');
  }
  stdout.writeln('');
  stdout.writeln('=== whole-pass cost scaling (log-log slope in n) ===');
  stdout.writeln('  baseline  slope = ${slope(baseMed).toStringAsFixed(3)}'
      '  (${baseMed.first.toStringAsFixed(3)}ms -> ${baseMed.last.toStringAsFixed(3)}ms)');
  stdout.writeln('  optimized slope = ${slope(optMed).toStringAsFixed(3)}'
      '  (${optMed.first.toStringAsFixed(3)}ms -> ${optMed.last.toStringAsFixed(3)}ms)');
  stdout.writeln('');
  stdout.writeln('sink=$_sink');
}
