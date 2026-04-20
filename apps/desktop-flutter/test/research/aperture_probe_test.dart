// Aperture probe — the commit window is an observation lens, not a
// parameter to tune. Sweep it continuously and report which
// observables hold stable across the sweep (scale-invariant, true
// properties of the repo) vs which run predictably (scale-dependent,
// describing the developmental arc) vs which flap (lens artifacts).
//
// This is the renormalization-group analog for codebases: at every
// scale a different effective theory, with invariants that classify
// the species and running couplings that describe the history.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_git_stats.dart';

void main() {
  test('aperture sweep — scale-dependent vs scale-invariant', () async {
    const repo =
        'C:/Users/mini server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R';
    // Geometric series of windows — equal ratio steps so a log-log
    // plot would be evenly spaced. Uses 1.5× stepping.
    final windows = <int>[60, 80, 100, 120, 140, 160, 200, 300, 500, 1000];
    final samples = <_Sample>[];
    for (final w in windows) {
      final s = await _sample(repo, w);
      if (s != null) {
        samples.add(s);
        // ignore: avoid_print
        print('  w=${w.toString().padLeft(4)}  '
            'n=${s.n.toString().padLeft(3)}  '
            'λ₁=${s.lambda1.toStringAsFixed(4)}  '
            'β₀=${s.beta0.toString().padLeft(3)}  '
            'β₁=${s.beta1.toString().padLeft(4)}  '
            'dS=${s.dS.toStringAsFixed(3)}  '
            'nearest=${s.universalityNearest}(d=${s.universalityDist.toStringAsFixed(2)})  '
            'topCentral=${s.topCentralShort}');
      }
    }

    // ── Analysis ──
    // Scale-invariant candidates: quantities whose coefficient of
    // variation (sd/mean) across the window sweep is small.
    // Running: large CV but monotonic trend.
    // Artifact: large CV without monotonic trend.
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('── sweep statistics (coefficient of variation, '
        'Spearman trend) ──');
    _summarise('n', samples.map((s) => s.n.toDouble()).toList());
    _summarise('λ₁ (Fiedler)', samples.map((s) => s.lambda1).toList());
    _summarise('β₀ (components)', samples.map((s) => s.beta0.toDouble()).toList());
    _summarise('β₁ (cycles)', samples.map((s) => s.beta1.toDouble()).toList());
    _summarise('dS (spectral dim)', samples.map((s) => s.dS).toList());
    _summarise(
        'universality-dist', samples.map((s) => s.universalityDist).toList());
    _summarise('spectral entropy',
        samples.map((s) => s.spectralEntropy).toList());
    _summarise(
        'decisiveness', samples.map((s) => s.decisiveness).toList());
    _summarise('β₁ / n (cycle density)',
        samples.map((s) => s.beta1 / s.n).toList());
    _summarise('β₀ / n (component density)',
        samples.map((s) => s.beta0 / s.n).toList());

    // Nearest-archetype stability — does the "species label" flip
    // across lens settings, or does the repo have a stable species
    // even as observables shift?
    final nearestCounts = <String, int>{};
    for (final s in samples) {
      nearestCounts.update(s.universalityNearest, (v) => v + 1,
          ifAbsent: () => 1);
    }
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('nearest archetype across sweep: $nearestCounts');

    // Center-of-mass drift — the top housekeeping file across
    // windows. Small set = stable center. Large set = drifting
    // center.
    final centerSet = <String>{};
    for (final s in samples) {
      centerSet.add(s.topCentralShort);
    }
    // ignore: avoid_print
    print('distinct top-housekeeping files across sweep: '
        '${centerSet.length} (${centerSet.join(", ")})');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

class _Sample {
  final int window;
  final int n;
  final double lambda1;
  final int beta0;
  final int beta1;
  final double dS;
  final double spectralEntropy;
  final String universalityNearest;
  final double universalityDist;
  final double decisiveness;
  final String topCentralShort;
  const _Sample({
    required this.window,
    required this.n,
    required this.lambda1,
    required this.beta0,
    required this.beta1,
    required this.dS,
    required this.spectralEntropy,
    required this.universalityNearest,
    required this.universalityDist,
    required this.decisiveness,
    required this.topCentralShort,
  });
}

Future<_Sample?> _sample(String repoPath, int window) async {
  final statsResult =
      await collectLogosGitStats(repoPath, commitWindow: window);
  if (!statsResult.ok) return null;
  final stats = statsResult.data!;
  final engine = LogosGit.buildFromStats(stats);
  final basis = engine.spectralBasis();
  if (basis == null) return null;
  final sg = engine.spectrogeometry();
  if (sg == null) return null;

  final evs = basis.eigenvalues;
  final lambda1 = evs.length > 1 ? evs[1] : 0.0;
  final total = evs.fold<double>(0.0, (a, b) => a + b);
  var entropy = 0.0;
  if (total > 0) {
    for (final e in evs) {
      final p = e / total;
      if (p > 1e-12) entropy -= p * math.log(p);
    }
  }

  // Top housekeeping file (short path representation for set-membership)
  final n = basis.n;
  final k = basis.k;
  final centrality = Float64List(n);
  var start = 0;
  for (var i = 0; i < evs.length; i++) {
    if (evs[i] > 0.01) {
      start = i;
      break;
    }
  }
  for (var m = start; m < math.min(k, start + 6); m++) {
    for (var i = 0; i < n; i++) {
      final e = basis.eigenvectors[m * n + i];
      centrality[i] += e * e;
    }
  }
  var bestIdx = 0;
  var bestC = -1.0;
  for (var i = 0; i < n; i++) {
    final c = math.sqrt(centrality[i]);
    if (c > bestC) {
      bestC = c;
      bestIdx = i;
    }
  }
  final topFile = engine.nodePaths[bestIdx];
  final topShort = _shortPath(topFile);

  return _Sample(
    window: window,
    n: n,
    lambda1: lambda1,
    beta0: sg.persistence?.finalComponents ?? 0,
    beta1: sg.persistence?.finalCycles ?? 0,
    dS: sg.spectralDim?.dS ?? 0.0,
    spectralEntropy: entropy,
    universalityNearest: sg.universality.nearest.name,
    universalityDist: sg.universality.nearest.distance,
    decisiveness: sg.universality.decisiveness,
    topCentralShort: topShort,
  );
}

void _summarise(String label, List<double> values) {
  if (values.isEmpty) return;
  final mean = values.reduce((a, b) => a + b) / values.length;
  var varSum = 0.0;
  for (final v in values) {
    varSum += (v - mean) * (v - mean);
  }
  final sd = math.sqrt(varSum / values.length);
  final cv = mean.abs() > 1e-9 ? sd / mean.abs() : double.infinity;

  // Spearman-ish ordinal trend — fraction of (i<j) pairs where
  // values[i] < values[j] in input order.
  var up = 0;
  var total = 0;
  for (var i = 0; i < values.length; i++) {
    for (var j = i + 1; j < values.length; j++) {
      if (values[i] == values[j]) continue;
      total++;
      if (values[i] < values[j]) up++;
    }
  }
  final tau = total == 0 ? 0.5 : up / total;

  final classification = cv < 0.10
      ? 'INVARIANT'
      : (tau > 0.75 || tau < 0.25 ? 'RUNNING  ' : 'ARTIFACT ');
  // ignore: avoid_print
  print('  ${label.padRight(26)} mean=${mean.toStringAsFixed(3).padLeft(8)}  '
      'sd=${sd.toStringAsFixed(3).padLeft(7)}  '
      'CV=${cv.toStringAsFixed(3).padLeft(7)}  '
      'τ=${tau.toStringAsFixed(2)}  '
      '[$classification]');
}

String _shortPath(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  if (parts.length <= 2) return path;
  return parts.sublist(parts.length - 2).join('/');
}
