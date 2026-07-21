// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: LicenseRef-WLCSL-1.0
// See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

// coupling_accumulator_bench.dart — A/B: does the int-scatter Gram accumulator
// beat the current String-keyed nested-map co-change build enough to justify
// rewriting the sacred file_coupling.dart kernel? Measures the ACCUMULATION
// (commits -> jaccard) in isolation (no git I/O), on realistic + mega-commit
// fixtures, AND golden-diffs the two outputs as an empirical bit-identity check.
//
//   run:  dart experiments/logos_bench/coupling_accumulator_bench.dart
//
// Pure Dart (no engine import) — both kernels are faithful ports of
// file_coupling.dart:1063-1148 (String) and the proposed brick (int-scatter).

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class Commit {
  final List<({String path, int lines})> files;
  final double step; // meaningfulness weight in [0,1] (precomputed; not the hot path)
  Commit(this.files, this.step);
}

// ───────── CURRENT: String-keyed nested maps (verbatim port) ─────────
Map<String, Map<String, double>> accStr(List<Commit> commits, double halfLife, int knee) {
  final invHalfLifeLn2 = halfLife > 0 ? math.ln2 / halfLife : 0.0;
  double commitWeight(double age) => halfLife <= 0 ? 1.0 : math.exp(-age * invHalfLifeLn2);
  double softKnee(int n) => n <= knee ? 1.0 : knee / n.toDouble();
  final fileCommits = <String, double>{};
  final pairCount = <String, Map<String, double>>{};
  var semanticAge = 0.0;
  for (var rank = 0; rank < commits.length; rank++) {
    final files = commits[rank].files;
    final w = commitWeight(semanticAge) * commits[rank].step * softKnee(files.length);
    semanticAge += commits[rank].step;
    if (w <= 0) continue;
    for (final f in files) {
      fileCommits[f.path] = (fileCommits[f.path] ?? 0) + w * f.lines;
    }
    final n = files.length;
    if (n < 2) continue;
    for (var i = 0; i < n; i++) {
      final a = files[i];
      for (var j = i + 1; j < n; j++) {
        final b = files[j];
        final cmp = a.path.compareTo(b.path);
        final lo = cmp < 0 ? a.path : b.path;
        final hi = cmp < 0 ? b.path : a.path;
        final mass = math.sqrt(a.lines.toDouble() * b.lines.toDouble());
        final row = pairCount.putIfAbsent(lo, () => {});
        row[hi] = (row[hi] ?? 0) + w * mass;
      }
    }
  }
  for (var lag = 1; lag <= 3; lag++) {
    final lagDiscount = 1.0 / (1 + lag);
    for (var rank = 0; rank < commits.length - lag; rank++) {
      final here = commits[rank].files;
      final there = commits[rank + lag].files;
      final w = math.sqrt(commitWeight(rank.toDouble()) * commitWeight((rank + lag).toDouble())) *
          lagDiscount * softKnee(here.length) * softKnee(there.length);
      if (w <= 1e-9) continue;
      for (final fH in here) {
        for (final fT in there) {
          if (fH.path == fT.path) continue;
          final cmp = fH.path.compareTo(fT.path);
          final lo = cmp < 0 ? fH.path : fT.path;
          final hi = cmp < 0 ? fT.path : fH.path;
          final mass = math.sqrt(fH.lines.toDouble() * fT.lines.toDouble());
          final row = pairCount.putIfAbsent(lo, () => {});
          row[hi] = (row[hi] ?? 0) + w * mass;
        }
      }
    }
  }
  final jaccard = <String, Map<String, double>>{};
  pairCount.forEach((a, row) {
    final na = fileCommits[a] ?? 0;
    final dest = jaccard.putIfAbsent(a, () => {});
    row.forEach((b, co) {
      final union = na + (fileCommits[b] ?? 0) - co;
      if (union > 0) dest[b] = co / union;
    });
  });
  for (final p in fileCommits.keys) {
    jaccard.putIfAbsent(p, () => {});
  }
  return jaccard;
}

// ───────── PROPOSED: int-scatter over interned ids (the brick) ─────────
Map<String, Map<String, double>> accInt(List<Commit> commits, double halfLife, int knee) {
  // pre-intern: gather all paths, sort LEXICOGRAPHICALLY so id order == lex order
  // (reproduces String.compareTo canonicalisation via int compare).
  final pathSet = <String>{};
  for (final c in commits) {
    for (final f in c.files) pathSet.add(f.path);
  }
  final paths = pathSet.toList()..sort();
  final n = paths.length;
  final id = <String, int>{};
  for (var i = 0; i < n; i++) {
    id[paths[i]] = i;
  }
  // pre-resolve each commit's file ids + lines once (avoid map lookups in the 3 lag passes)
  final cIds = <Int32List>[];
  final cLines = <Int32List>[];
  for (final c in commits) {
    final m = c.files.length;
    final ids = Int32List(m);
    final ln = Int32List(m);
    for (var i = 0; i < m; i++) {
      ids[i] = id[c.files[i].path]!;
      ln[i] = c.files[i].lines;
    }
    cIds.add(ids);
    cLines.add(ln);
  }
  final invHalfLifeLn2 = halfLife > 0 ? math.ln2 / halfLife : 0.0;
  double commitWeight(double age) => halfLife <= 0 ? 1.0 : math.exp(-age * invHalfLifeLn2);
  double softKnee(int k) => k <= knee ? 1.0 : knee / k.toDouble();
  final fileCommits = Float64List(n);
  final seen = Uint8List(n);
  final pairCount = <int, double>{}; // packed key lo*n + hi
  var semanticAge = 0.0;
  for (var rank = 0; rank < commits.length; rank++) {
    final ids = cIds[rank];
    final ln = cLines[rank];
    final w = commitWeight(semanticAge) * commits[rank].step * softKnee(ids.length);
    semanticAge += commits[rank].step;
    if (w <= 0) continue;
    for (var i = 0; i < ids.length; i++) {
      fileCommits[ids[i]] += w * ln[i];
      seen[ids[i]] = 1;
    }
    final m = ids.length;
    if (m < 2) continue;
    for (var i = 0; i < m; i++) {
      final ai = ids[i];
      final al = ln[i].toDouble();
      for (var j = i + 1; j < m; j++) {
        final bj = ids[j];
        final lo = ai < bj ? ai : bj;
        final hi = ai < bj ? bj : ai;
        final key = lo * n + hi;
        final mass = math.sqrt(al * ln[j].toDouble());
        pairCount[key] = (pairCount[key] ?? 0) + w * mass;
      }
    }
  }
  for (var lag = 1; lag <= 3; lag++) {
    final lagDiscount = 1.0 / (1 + lag);
    for (var rank = 0; rank < commits.length - lag; rank++) {
      final hIds = cIds[rank];
      final hLn = cLines[rank];
      final tIds = cIds[rank + lag];
      final tLn = cLines[rank + lag];
      final w = math.sqrt(commitWeight(rank.toDouble()) * commitWeight((rank + lag).toDouble())) *
          lagDiscount * softKnee(hIds.length) * softKnee(tIds.length);
      if (w <= 1e-9) continue;
      for (var a = 0; a < hIds.length; a++) {
        final ah = hIds[a];
        final al = hLn[a].toDouble();
        for (var b = 0; b < tIds.length; b++) {
          final bt = tIds[b];
          if (ah == bt) continue;
          final lo = ah < bt ? ah : bt;
          final hi = ah < bt ? bt : ah;
          final key = lo * n + hi;
          final mass = math.sqrt(al * tLn[b].toDouble());
          pairCount[key] = (pairCount[key] ?? 0) + w * mass;
        }
      }
    }
  }
  final jaccard = <String, Map<String, double>>{};
  pairCount.forEach((key, co) {
    final lo = key ~/ n;
    final hi = key % n;
    // Match the String semantics exactly: a row exists for every distinct
    // `lo`-key in pairCount even when all its entries are degenerate
    // (union<=0). The String build does this via its outer putIfAbsent
    // before the union check; replicate it so the gate is honest.
    final dest = jaccard.putIfAbsent(paths[lo], () => {});
    final union = fileCommits[lo] + fileCommits[hi] - co;
    if (union > 0) dest[paths[hi]] = co / union;
  });
  for (var i = 0; i < n; i++) {
    if (seen[i] == 1) jaccard.putIfAbsent(paths[i], () => {});
  }
  return jaccard;
}

// ───────── fixtures ─────────
List<Commit> synth(int nCommits, int poolSize, int seed, {required int megaEvery, required int megaSize}) {
  final rng = math.Random(seed);
  final commits = <Commit>[];
  for (var c = 0; c < nCommits; c++) {
    int k;
    if (megaEvery > 0 && c % megaEvery == 0) {
      k = megaSize + rng.nextInt(megaSize ~/ 2 + 1); // mega-commit
    } else {
      final r = rng.nextDouble();
      k = r < 0.85 ? 1 + rng.nextInt(4) : (r < 0.98 ? 5 + rng.nextInt(16) : 40 + rng.nextInt(160));
    }
    // locality: draw from a sliding hot window so co-change clusters form
    final base = rng.nextInt(poolSize);
    final files = <({String path, int lines})>[];
    final used = <int>{};
    for (var i = 0; i < k; i++) {
      var fid = (base + rng.nextInt(math.min(poolSize, 400))) % poolSize;
      if (!used.add(fid)) continue;
      files.add((path: 'src/dir${fid % 200}/file_$fid.dart', lines: 1 + rng.nextInt(300)));
    }
    if (files.isEmpty) continue;
    final step = rng.nextDouble() < 0.1 ? 0.0 : (0.3 + 0.7 * rng.nextDouble());
    commits.add(Commit(files, step));
  }
  return commits;
}

String _dbits(double v) {
  final b = ByteData(8)..setFloat64(0, v);
  return b.getUint64(0).toRadixString(16);
}

bool bitIdentical(Map<String, Map<String, double>> a, Map<String, Map<String, double>> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    final rb = b[e.key];
    if (rb == null || rb.length != e.value.length) return false;
    for (final ee in e.value.entries) {
      final v = rb[ee.key];
      if (v == null || _dbits(v) != _dbits(ee.value)) return false;
    }
  }
  return true;
}

double _median(List<int> xs) {
  xs.sort();
  return xs[xs.length ~/ 2] / 1000.0; // µs -> ms
}

void main() {
  stdout.writeln('=== coupling accumulator A/B  (String nested-map vs int-scatter) ===');
  stdout.writeln('dart ${Platform.version.split(' ').first}');
  stdout.writeln('');
  final scenarios = [
    ('realistic 1000 commits, pool 5000, no mega', 1000, 5000, 0, 0),
    ('mega-commits: 600 commits, pool 5000, a 500-file commit every 40', 600, 5000, 40, 500),
    ('heavy mega: 400 commits, pool 8000, a 1500-file commit every 50', 400, 8000, 50, 1500),
  ];
  const trials = 9;
  const halfLife = 10.0;
  const knee = 60;
  for (final (label, nc, pool, me, ms) in scenarios) {
    final commits = synth(nc, pool, 0xC0FFEE + nc, megaEvery: me, megaSize: ms);
    final totalMentions = commits.fold<int>(0, (s, c) => s + c.files.length);
    final maxK = commits.fold<int>(0, (s, c) => math.max(s, c.files.length));
    // fidelity check first
    final jStr = accStr(commits, halfLife, knee);
    final jInt = accInt(commits, halfLife, knee);
    final ok = bitIdentical(jStr, jInt) && bitIdentical(jInt, jStr);
    // warmup
    accStr(commits, halfLife, knee);
    accInt(commits, halfLife, knee);
    final tStr = <int>[];
    final tInt = <int>[];
    for (var t = 0; t < trials; t++) {
      final sw1 = Stopwatch()..start();
      accStr(commits, halfLife, knee);
      sw1.stop();
      tStr.add(sw1.elapsedMicroseconds);
      final sw2 = Stopwatch()..start();
      accInt(commits, halfLife, knee);
      sw2.stop();
      tInt.add(sw2.elapsedMicroseconds);
    }
    final mStr = _median(tStr);
    final mInt = _median(tInt);
    stdout.writeln('--- $label ---');
    stdout.writeln('  commits=$nc  file-mentions=$totalMentions  maxCommitFiles=$maxK  nnz(jaccard rows)=${jStr.length}');
    stdout.writeln('  bit-identical(String vs int): ${ok ? "YES ✓" : "NO ✗ — FIDELITY BROKEN"}');
    stdout.writeln('  String nested-map : ${mStr.toStringAsFixed(2)} ms (median of $trials)');
    stdout.writeln('  int-scatter brick : ${mInt.toStringAsFixed(2)} ms');
    stdout.writeln('  speedup           : ${(mStr / mInt).toStringAsFixed(2)}x  (${mStr > mInt ? "faster" : "SLOWER"})');
    stdout.writeln('  rss               : ${(ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(0)} MB');
    stdout.writeln('');
  }
  stdout.writeln('verdict: install the brick only if it is bit-identical AND meaningfully faster on');
  stdout.writeln('the mega-commit scenarios (where the String/boxing/nested-map storm actually bites).');
}
