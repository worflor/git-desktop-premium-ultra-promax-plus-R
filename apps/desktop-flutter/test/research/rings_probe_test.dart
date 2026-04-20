// Growth-rings probe — dense aperture sweep, derivative-based
// event detection, temporal event reconstruction.
//
// The tree-ring analog: a codebase preserves its history as layers
// readable by varying the observation scale. We don't need to
// reconstruct the state at every commit to read those layers — a
// sparse aperture sweep integrates each observable over a cumulative
// window, and the DERIVATIVE of that observable with respect to
// aperture localises the scale at which a transition happened.
// That scale maps back to a commit range in real history.
//
// Each peak in d(observable)/d(aperture) is a "growth ring" event.
// Peaks co-occurring across multiple observables at the same aperture
// = a major compound event. Peaks on single observables = narrower
// shifts.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_git_stats.dart';

void main() {
  test('rings probe — event timeline via aperture derivative', () async {
    const repo =
        'C:/Users/mini server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R';

    // Geometric progression — same log-space step, denser sampling
    // than the earlier aperture test.
    final windows = <int>[
      60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160, 180,
      200, 220, 250, 280, 320, 360, 400, 500, 600, 800, 1000,
    ];

    final samples = <_Sample>[];
    for (final w in windows) {
      final s = await _sample(repo, w);
      if (s != null) samples.add(s);
    }

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('── samples ──');
    // ignore: avoid_print
    print('  w       n    λ₁       β₀    β₁     dS      entropy  arche  topFile');
    for (final s in samples) {
      // ignore: avoid_print
      print('  ${s.window.toString().padLeft(4)}  '
          '${s.n.toString().padLeft(4)}  '
          '${s.lambda1.toStringAsFixed(4)}  '
          '${s.beta0.toString().padLeft(4)}  '
          '${s.beta1.toString().padLeft(4)}  '
          '${s.dS.toStringAsFixed(3)}  '
          '${s.entropy.toStringAsFixed(3)}   '
          '${s.archetype.padRight(5)}  '
          '${s.topFile}');
    }

    // ── Derivatives: |Δobservable / Δlog(aperture)| ──
    // Log-space because aperture is multiplicatively meaningful
    // (going from 50→100 is "one step", same as 100→200).
    final derivPeaks = <_Peak>[];

    void scan(String label, List<double> values, {required bool fractional}) {
      for (var i = 1; i < samples.length; i++) {
        final dw =
            math.log(samples[i].window / samples[i - 1].window);
        final v0 = values[i - 1];
        final v1 = values[i];
        if (dw <= 0) continue;
        // Fractional Δ for quantities with meaningful zero; raw Δ
        // for others.
        final delta = fractional
            ? (v0.abs() < 1e-9 ? 0.0 : (v1 - v0) / v0.abs())
            : (v1 - v0);
        final magnitude = delta.abs() / dw;
        if (magnitude > 0) {
          derivPeaks.add(_Peak(
            observable: label,
            apertureMid:
                math.sqrt(samples[i - 1].window * samples[i].window),
            from: samples[i - 1].window,
            to: samples[i].window,
            delta: delta,
            magnitude: magnitude,
          ));
        }
      }
    }

    scan('n', samples.map((s) => s.n.toDouble()).toList(), fractional: true);
    scan('λ₁', samples.map((s) => s.lambda1).toList(), fractional: true);
    scan('β₀', samples.map((s) => s.beta0.toDouble()).toList(),
        fractional: true);
    scan('β₁', samples.map((s) => s.beta1.toDouble()).toList(),
        fractional: true);
    scan('dS', samples.map((s) => s.dS).toList(), fractional: true);
    scan('universality-dist',
        samples.map((s) => s.universalityDist).toList(),
        fractional: false);
    scan('spectral-entropy',
        samples.map((s) => s.entropy).toList(),
        fractional: true);

    // Filter for top-of-distribution per observable — the local
    // peaks rather than every bin with any delta.
    final perObs = <String, List<_Peak>>{};
    for (final p in derivPeaks) {
      perObs.putIfAbsent(p.observable, () => []).add(p);
    }
    final filtered = <_Peak>[];
    perObs.forEach((obs, list) {
      list.sort((a, b) => b.magnitude.compareTo(a.magnitude));
      // Keep top 3 peaks per observable.
      for (final p in list.take(3)) {
        filtered.add(p);
      }
    });
    // Sort combined timeline by aperture.
    filtered.sort((a, b) => a.apertureMid.compareTo(b.apertureMid));

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('── event timeline (top-3 derivative peaks per observable) ──');
    // ignore: avoid_print
    print('  aperture  observable          Δ          magnitude');
    for (final p in filtered) {
      // ignore: avoid_print
      print('  ${p.from.toString().padLeft(4)}→${p.to.toString().padRight(4)}  '
          '${p.observable.padRight(20)}'
          '${p.delta.toStringAsFixed(3).padLeft(10)}  '
          '${p.magnitude.toStringAsFixed(3)}');
    }

    // ── Compound events: apertures where multiple observables all
    // have a peak in the same bin. These are the repo's macro-events.
    final binCounts = <int, List<String>>{};
    for (final p in filtered) {
      binCounts.putIfAbsent(p.to, () => []).add(p.observable);
    }
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('── compound events (multiple observables co-flipping) ──');
    final sortedBins = binCounts.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final e in sortedBins) {
      if (e.value.length >= 2) {
        // ignore: avoid_print
        print('  aperture≈${e.key}  ${e.value.length} observables flipped: '
            '${e.value.join(", ")}');
      }
    }

    // ── Top-file trajectory — reads out the sequence of "centres
    // of gravity" this codebase has had.
    final topFileTrajectory = <String>[];
    String? last;
    for (final s in samples) {
      if (s.topFile != last) {
        topFileTrajectory.add('w${s.window}:${s.topFile}');
        last = s.topFile;
      }
    }
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('── centre-of-gravity trajectory across aperture ──');
    for (final t in topFileTrajectory) {
      // ignore: avoid_print
      print('  $t');
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}

class _Sample {
  final int window;
  final int n;
  final double lambda1;
  final int beta0;
  final int beta1;
  final double dS;
  final double entropy;
  final String archetype;
  final double universalityDist;
  final String topFile;
  _Sample({
    required this.window,
    required this.n,
    required this.lambda1,
    required this.beta0,
    required this.beta1,
    required this.dS,
    required this.entropy,
    required this.archetype,
    required this.universalityDist,
    required this.topFile,
  });
}

class _Peak {
  final String observable;
  final double apertureMid;
  final int from;
  final int to;
  final double delta;
  final double magnitude;
  _Peak({
    required this.observable,
    required this.apertureMid,
    required this.from,
    required this.to,
    required this.delta,
    required this.magnitude,
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
  final topFile = _shortPath(engine.nodePaths[bestIdx]);

  return _Sample(
    window: window,
    n: n,
    lambda1: lambda1,
    beta0: sg.persistence?.finalComponents ?? 0,
    beta1: sg.persistence?.finalCycles ?? 0,
    dS: sg.spectralDim?.dS ?? 0.0,
    entropy: entropy,
    archetype: sg.universality.nearest.name,
    universalityDist: sg.universality.nearest.distance,
    topFile: topFile,
  );
}

String _shortPath(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  if (parts.length <= 2) return path;
  return parts.sublist(parts.length - 2).join('/');
}
