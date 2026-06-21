// Isolated scaling benchmark for the `coupling-calibration` kernel:
//   calibrateCouplingConstants (logos_git_integrity.dart:487)
//
// Run (from repo root):
//   dart --packages=experiments/logos_bench/package_config.json \
//        experiments/logos_bench/coupling_calibration_kernel.dart
//
// WHAT THIS MEASURES
// ------------------
// `coupling-calibration` is the fastest-growing phase of buildFromStats
// (share 19% -> 40%, ~1.47 exponent at the large end, ~1.16s at n=20000
// in the headline run). This harness isolates JUST that kernel and drives
// it at n in {200,1000,5000,20000} with the same power-law repo synthesis
// the headline harness uses, then compares two NUMERICALLY-IDENTICAL paths:
//
//   BASELINE  — the real public calibrateCouplingConstants. It rebuilds a
//               fresh `roles` map via TransportRoles.of(p) for ALL n paths
//               (logos_git_integrity.dart:492-495) even though buildFromStats
//               already built transportRoles[] at logos_git.dart:2518.
//
//   OPTIMIZED — a faithful, bit-for-bit reimplementation of the kernel that
//               THREADS the already-built TransportRoles list in instead of
//               recomputing it. Every primitive it needs is public on
//               TransportRoles (the bool role flags + seedKey); the two
//               private gates _sharesManifestRoot / _sharesTransportConcept
//               are reconstructed verbatim from the public seedKey field
//               (logos_git_integrity.dart:436-444). The shrinkage math and
//               priors are the engine's own public constants.
//
// We ASSERT all 7 CouplingConstants fields are bit-for-bit equal between
// the two paths at every size before reporting any timing — a cheaper
// answer is failure; only a faster identical answer counts.
//
// We also (a) confirm the O(m) jaccardEdges branch is the one buildFromStats
// always takes, and (b) show the latent O(n^2) all-pairs branch (lines
// 516-529, taken only if jaccardEdges is null) is a 400M-pair catastrophe
// at n=20000 — the root-cause fix is to make a null callback structurally
// unrepresentable (see the report).
//
// lib/** is untouched — this only consumes the public engine API + a
// verbatim copy of the kernel body for the optimized arm.

import 'dart:io';
import 'dart:math' as math;

import '../../apps/desktop-flutter/lib/backend/logos_git.dart';
import '../../apps/desktop-flutter/lib/backend/logos_git_integrity.dart';
import '../../apps/desktop-flutter/lib/backend/file_coupling.dart';
import '../../apps/desktop-flutter/lib/backend/spectral_constants.dart' as sc;

// ---------------------------------------------------------------------------
// Deterministic LCG (seed shapes ONLY the synthetic input; engine runs with
// no injected randomness). Identical to headline.dart.
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

/// Same large-repo synthesis as headline.dart: n files in ~200 dirs x 40
/// subdirs, c = min(60000, 3n) commits, power-law fan-out (85% 1-4,
/// 13% 5-20, 2% 40-200), hot-window locality, jaccard top-50 capped per row.
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
  final volStddev =
      math.sqrt(math.max(0.0, volSumSq / n - volMean * volMean));

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
// nodePaths reconstruction — identical to buildFromStats (logos_git.dart:
// 2355-2364): sorted union of every path-bearing key set. With our synth
// only touches / volatility / coupling.paths carry keys; the union equals
// the file set and the sort gives the canonical order the kernel sees.
// ---------------------------------------------------------------------------
List<String> nodePathsOf(LogosGitStats stats) {
  final pathSet = <String>{};
  pathSet.addAll(stats.touches.keys);
  pathSet.addAll(stats.volatility.keys);
  pathSet.addAll(stats.coupling.paths);
  return pathSet.toList()..sort();
}

// ---------------------------------------------------------------------------
// OPTIMIZED kernel — byte-for-byte semantics of calibrateCouplingConstants,
// but the caller threads in the pre-built TransportRoles list (index-aligned
// with `paths`) instead of rebuilding it. The two private gates and the
// classification + shrinkage are copied verbatim from the engine source
// (logos_git_integrity.dart) using only public fields, so the result is
// identical by construction.
// ---------------------------------------------------------------------------

const double _kPriorWeight = sc.kCcEvidenceSquare; // 16.0 == 4²
const double _kPriorManifestLockfile = 0.80;
const double _kPriorSourceGenerated = 0.72;
const double _kPriorSourceMigration = 0.48;
const double _kPriorSourceTest = 0.42;
const double _kPriorFixture = 0.36;
const double _kPriorCiConfig = 0.36;
const double _kPriorSourceDoc = 0.30;

// Verbatim copies of TransportRoles._sharesManifestRoot /
// _sharesTransportConcept (logos_git_integrity.dart:436-444), expressed on
// the public `seedKey` field.
bool _sharesManifestRoot(TransportRoles a, TransportRoles b) =>
    a.seedKey != null &&
    a.seedKey == b.seedKey &&
    a.seedKey!.startsWith('manifest:');

bool _sharesTransportConcept(TransportRoles a, TransportRoles b) =>
    a.seedKey != null &&
    a.seedKey == b.seedKey &&
    a.seedKey!.startsWith('concept:');

// Verbatim copy of _classifyRolePair (logos_git_integrity.dart:550-580).
String? _classifyRolePair(TransportRoles a, TransportRoles b) {
  if ((a.isManifest && b.isLockfile) || (b.isManifest && a.isLockfile)) {
    if (_sharesManifestRoot(a, b)) return 'manifest_lockfile';
  }
  final sharesConcept = _sharesTransportConcept(a, b);
  if (sharesConcept &&
      ((a.isSource && b.isTest) || (b.isSource && a.isTest))) {
    return 'source_test';
  }
  if (sharesConcept &&
      ((a.isSource && b.isGenerated) || (b.isSource && a.isGenerated))) {
    return 'source_generated';
  }
  if (sharesConcept && ((a.isSource && b.isDoc) || (b.isSource && a.isDoc))) {
    return 'source_doc';
  }
  if (sharesConcept &&
      ((a.isSource && b.isMigration) || (b.isSource && a.isMigration))) {
    return 'source_migration';
  }
  if ((a.isFixture && b.isSource) || (b.isFixture && a.isSource)) {
    return 'fixture';
  }
  if ((a.isCiConfig && b.isSource) || (b.isCiConfig && a.isSource)) {
    return 'ci_config';
  }
  return null;
}

/// OPTIMIZED calibration: identical to calibrateCouplingConstants except it
/// consumes a pre-built, index-aligned `roles` list rather than recomputing
/// TransportRoles.of for every path. (Optimization 1.) Only the jaccardEdges
/// branch exists here — the O(n^2) all-pairs branch is structurally absent,
/// which is the root-cause form of optimization 2.
CouplingConstants calibrateOptimized(
  List<String> paths,
  List<TransportRoles> rolesList, // threaded in — NOT rebuilt
  Iterable<MapEntry<String, double>> Function(String path) jaccardEdges,
) {
  // Map path -> roles for the neighbour lookups, built from the existing
  // list (no TransportRoles.of recomputation).
  final roles = <String, TransportRoles>{};
  for (var i = 0; i < paths.length; i++) {
    roles[paths[i]] = rolesList[i];
  }

  final sums = <String, double>{};
  final counts = <String, int>{};

  for (var i = 0; i < paths.length; i++) {
    final a = paths[i];
    final ra = rolesList[i];
    for (final entry in jaccardEdges(a)) {
      final b = entry.key;
      final rb = roles[b];
      if (rb == null) continue;
      final bucket = _classifyRolePair(ra, rb);
      if (bucket == null) continue;
      final score = entry.value;
      if (score <= 0) continue;
      sums[bucket] = (sums[bucket] ?? 0) + score;
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
  }

  double shrink(String key, double prior) {
    final m = counts[key] ?? 0;
    if (m == 0) return prior;
    final empirical = sums[key]! / m;
    return (prior * _kPriorWeight + empirical * m) / (_kPriorWeight + m);
  }

  return CouplingConstants(
    manifestLockfile: shrink('manifest_lockfile', _kPriorManifestLockfile),
    sourceGenerated: shrink('source_generated', _kPriorSourceGenerated),
    sourceMigration: shrink('source_migration', _kPriorSourceMigration),
    sourceTest: shrink('source_test', _kPriorSourceTest),
    fixture: shrink('fixture', _kPriorFixture),
    ciConfig: shrink('ci_config', _kPriorCiConfig),
    sourceDoc: shrink('source_doc', _kPriorSourceDoc),
  );
}

// ---------------------------------------------------------------------------
// Stats helpers.
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

bool _ccEqual(CouplingConstants a, CouplingConstants b) =>
    a.manifestLockfile == b.manifestLockfile &&
    a.sourceGenerated == b.sourceGenerated &&
    a.sourceMigration == b.sourceMigration &&
    a.sourceTest == b.sourceTest &&
    a.fixture == b.fixture &&
    a.ciConfig == b.ciConfig &&
    a.sourceDoc == b.sourceDoc;

String _ccStr(CouplingConstants c) =>
    'ml=${c.manifestLockfile.toStringAsFixed(6)} '
    'sg=${c.sourceGenerated.toStringAsFixed(6)} '
    'sm=${c.sourceMigration.toStringAsFixed(6)} '
    'st=${c.sourceTest.toStringAsFixed(6)} '
    'fx=${c.fixture.toStringAsFixed(6)} '
    'ci=${c.ciConfig.toStringAsFixed(6)} '
    'sd=${c.sourceDoc.toStringAsFixed(6)}';

void main() {
  final sizes = [200, 1000, 5000, 20000];
  const trials = 7;

  print('=== coupling-calibration kernel scaling (isolated) ===');
  print('dart ${Platform.version}');
  print('kernel: calibrateCouplingConstants (logos_git_integrity.dart:487)');
  print('trials=$trials per arm (1 warmup discarded). identity asserted '
      'bit-for-bit before timing.');
  print('');

  final baseAxis = <int>[];
  final baseMed = <double>[];
  final optMed = <double>[];
  final edgesAxis = <int>[];

  var allIdentical = true;

  for (final n in sizes) {
    final stats = synth(n, seed: 0xC0FFEE + n);
    final nodePaths = nodePathsOf(stats);
    final shadow = stats.shadowCoupling; // null in our synth (single matrix)

    // Pre-build the roles list exactly as buildFromStats does at line 2518.
    final rolesList = List<TransportRoles>.generate(
        nodePaths.length, (i) => TransportRoles.of(nodePaths[i]));

    // The edge callback buildFromStats passes when shadow == null
    // (logos_git.dart:2607).
    Iterable<MapEntry<String, double>> edges(String p) =>
        stats.coupling.jaccardEntriesOf(p);

    // The jaccardScore closure buildFromStats passes (logos_git.dart:2605).
    double jScore(String a, String b) => stats.coupling.jaccardScoreOf(a, b);

    // Count directed coupling edges m examined by the winning branch.
    var edgeCount = 0;
    for (final p in nodePaths) {
      for (final _ in edges(p)) {
        edgeCount++;
      }
    }

    // --- Identity check (sacred): baseline vs optimized, bit-for-bit. ---
    final baseCC = calibrateCouplingConstants(nodePaths, jScore,
        jaccardEdges: edges);
    final optCC = calibrateOptimized(nodePaths, rolesList, edges);
    final identical = _ccEqual(baseCC, optCC);
    allIdentical = allIdentical && identical;

    // Sanity: confirm shadow is null so the always-winning edges branch is
    // the one buildFromStats actually takes.
    final branch = shadow == null ? 'jaccardEdges (O(m))' : 'blended-edges';

    // --- Warmup (JIT) — discard. ---
    calibrateCouplingConstants(nodePaths, jScore, jaccardEdges: edges);
    calibrateOptimized(nodePaths, rolesList, edges);

    // --- Time BASELINE (real public kernel). ---
    final baseWall = <double>[];
    for (var t = 0; t < trials; t++) {
      final sw = Stopwatch()..start();
      final r = calibrateCouplingConstants(nodePaths, jScore,
          jaccardEdges: edges);
      sw.stop();
      if (r.fixture < -1) print('unreachable'); // keep optimizer honest
      baseWall.add(sw.elapsedMicroseconds / 1000.0);
    }

    // --- Time OPTIMIZED (threaded roles). ---
    final optWall = <double>[];
    for (var t = 0; t < trials; t++) {
      final sw = Stopwatch()..start();
      final r = calibrateOptimized(nodePaths, rolesList, edges);
      sw.stop();
      if (r.fixture < -1) print('unreachable');
      optWall.add(sw.elapsedMicroseconds / 1000.0);
    }

    // --- Isolate the redundant work itself: the roles-map rebuild loop
    // (logos_git_integrity.dart:492-495) that optimization 1 deletes. ---
    // warmup
    {
      final r = <String, TransportRoles>{};
      for (final p in nodePaths) {
        r[p] = TransportRoles.of(p);
      }
      if (r.length < 0) print('unreachable');
    }
    final rebuildWall = <double>[];
    for (var t = 0; t < trials; t++) {
      final sw = Stopwatch()..start();
      final r = <String, TransportRoles>{};
      for (final p in nodePaths) {
        r[p] = TransportRoles.of(p);
      }
      sw.stop();
      if (r.length < 0) print('unreachable');
      rebuildWall.add(sw.elapsedMicroseconds / 1000.0);
    }
    final rebuildMed = _median(rebuildWall);

    final bMed = _median(baseWall);
    final bP95 = _percentile(baseWall, 0.95);
    final oMed = _median(optWall);
    final oP95 = _percentile(optWall, 0.95);
    final rss = ProcessInfo.currentRss / (1024 * 1024);
    final speedup = oMed > 0 ? bMed / oMed : 0.0;
    final saved = bMed - oMed;

    baseAxis.add(n);
    baseMed.add(bMed);
    optMed.add(oMed);
    edgesAxis.add(edgeCount);

    print('--- n=$n  files=${nodePaths.length}  '
        'directedCouplingEdges(m)=$edgeCount  branch=$branch ---');
    print('  IDENTICAL=${identical ? "YES (bit-for-bit)" : "NO !!!"}  '
        'rolePairs/path~${(edgeCount / nodePaths.length).toStringAsFixed(1)}');
    if (!identical) {
      print('    base: ${_ccStr(baseCC)}');
      print('    opt : ${_ccStr(optCC)}');
    } else {
      print('    cc=${_ccStr(baseCC)}');
    }
    print('  BASELINE  median=${bMed.toStringAsFixed(3)}ms  '
        'p95=${bP95.toStringAsFixed(3)}ms');
    print('  OPTIMIZED median=${oMed.toStringAsFixed(3)}ms  '
        'p95=${oP95.toStringAsFixed(3)}ms');
    print('  SPEEDUP=${speedup.toStringAsFixed(2)}x  '
        'saved=${saved.toStringAsFixed(3)}ms  rss=${rss.toStringAsFixed(1)}MB');
    print('  redundant roles-rebuild loop alone = '
        '${rebuildMed.toStringAsFixed(3)}ms '
        '(this is the work optimization 1 deletes)');
    print('');
  }

  // --- Latent O(n^2) branch demonstration (optimization 2). ---
  // If jaccardEdges were ever null, the kernel falls into the all-pairs
  // branch (logos_git_integrity.dart:516-529): n(n-1)/2 jaccardScore calls.
  // We do NOT run it at n=20000 (it would be a ~400M-pair, multi-second
  // catastrophe); we run it only at the smallest size to MEASURE its slope,
  // then extrapolate, proving why the null branch must be unrepresentable.
  print('=== latent O(n^2) all-pairs branch (jaccardEdges==null path) ===');
  for (final n in [200, 1000]) {
    final stats = synth(n, seed: 0xC0FFEE + n);
    final nodePaths = nodePathsOf(stats);
    double jScore(String a, String b) => stats.coupling.jaccardScoreOf(a, b);
    // warmup
    calibrateCouplingConstants(nodePaths, jScore);
    final wall = <double>[];
    for (var t = 0; t < 3; t++) {
      final sw = Stopwatch()..start();
      final r = calibrateCouplingConstants(nodePaths, jScore); // null edges!
      sw.stop();
      if (r.fixture < -1) print('unreachable');
      wall.add(sw.elapsedMicroseconds / 1000.0);
    }
    final pairs = n * (n - 1) ~/ 2;
    print('  n=$n  all-pairs=$pairs  median=${_median(wall).toStringAsFixed(2)}ms '
        '(vs edges branch at same n above)');
  }
  // Extrapolate to n=20000.
  {
    const n = 20000;
    final pairs = n * (n - 1) ~/ 2;
    print('  n=$n  all-pairs=$pairs  -> NOT RUN (catastrophe). '
        'This is why a null callback must be made unrepresentable.');
  }
  print('');

  // --- Scaling fit (log-log slope between smallest and largest size). ---
  print('=== scaling fit (log-log slope = empirical exponent in n) ===');
  final logN0 = math.log(sizes.first.toDouble());
  final logN1 = math.log(sizes.last.toDouble());
  final baseSlope =
      (math.log(baseMed.last) - math.log(baseMed.first)) / (logN1 - logN0);
  final optSlope =
      (math.log(optMed.last) - math.log(optMed.first)) / (logN1 - logN0);
  final edgeSlope =
      (math.log(edgesAxis.last.toDouble()) - math.log(edgesAxis.first.toDouble())) /
          (logN1 - logN0);
  print('  BASELINE  exponent~${baseSlope.toStringAsFixed(2)}  '
      '(${baseMed.first.toStringAsFixed(3)}ms -> ${baseMed.last.toStringAsFixed(3)}ms)');
  print('  OPTIMIZED exponent~${optSlope.toStringAsFixed(2)}  '
      '(${optMed.first.toStringAsFixed(3)}ms -> ${optMed.last.toStringAsFixed(3)}ms)');
  print('  edges m   exponent~${edgeSlope.toStringAsFixed(2)}  '
      '(${edgesAxis.first} -> ${edgesAxis.last})  '
      '(kernel is O(m); m grows ~linearly in n => kernel should be ~O(n))');
  print('');
  print(allIdentical
      ? 'ALL SIZES BIT-FOR-BIT IDENTICAL — optimization is a pure speedup.'
      : 'IDENTITY FAILURE — optimization changes the answer (FAILURE).');
}
