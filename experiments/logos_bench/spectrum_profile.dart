// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: LicenseRef-WLCSL-1.0
// See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

// Spectrum-honesty profiler — measures the CURRENT eigensolver's behaviour
// so the block/kernel/truncation work has a real before/after baseline.
//
// Run (from repo root):
//   dart --packages=experiments/logos_bench/package_config.json \
//        experiments/logos_bench/spectrum_profile.dart
//
// Per real repo it builds the production coupling graph and probes its
// normalized-Laplacian spectrum:
//   * kernel dimension: current Lanczos vs DENSE ground truth (the β₀ bug)
//   * eigenvalue accuracy: max |λ_lanczos − λ_dense| over the kept modes
//   * truncation: are there meaningful low modes beyond k=20?
//   * heat capture: Z_k(τ)/Z_n(τ) — how much mass the k-truncation drops
//   * Lanczos solve time
// A synthetic disjoint-cliques case (known β₀) leads, to exhibit the bug
// even when real coupling graphs happen to be connected.
//
// Read-only. lib/** untouched.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../apps/desktop-flutter/lib/backend/logos_core.dart';
import '../../apps/desktop-flutter/lib/backend/logos_chaos.dart';
import '../../apps/desktop-flutter/lib/backend/file_coupling.dart';
import '../../apps/desktop-flutter/lib/backend/logos_git.dart';
import '../../apps/desktop-flutter/lib/backend/logos_git_stats.dart';

const _projects = r'C:\Users\mini server\Documents\Projects';

final _repos = <(String, String)>[
  ('git-desktop', '$_projects\\git-desktop-premium-ultra-promax-plus-R'),
  ('worflor.io', '$_projects\\worflor.github.io'),
  ('wdym-mod', '$_projects\\Fabric Modding\\what-do-you-mean-mod-1.21'),
  ('alpha-math', '$_projects\\alpha-math'),
  ('seance', '$_projects\\seance'),
];

const int _denseCap = 750; // dense eigendecomp only at or below this n
const int _k = 20;

Float64List _denseLsym(CsrGraph g) {
  final n = g.n;
  final m = Float64List(n * n);
  for (var i = 0; i < n; i++) {
    m[i * n + i] = 1.0;
  }
  for (var i = 0; i < n; i++) {
    for (var p = g.indptr[i]; p < g.indptr[i + 1]; p++) {
      m[i * n + g.indices[p]] -= g.values[p];
    }
  }
  return m;
}

int _undirectedEdges(CsrGraph g) {
  var e = 0;
  for (var i = 0; i < g.n; i++) {
    for (var p = g.indptr[i]; p < g.indptr[i + 1]; p++) {
      if (g.indices[p] > i) e++;
    }
  }
  return e;
}

/// (β₀ over non-self edges, count of degree-0 isolated nodes).
(int, int) _components(CsrGraph g) {
  final n = g.n;
  final parent = List<int>.generate(n, (i) => i);
  int find(int x) {
    var r = x;
    while (parent[r] != r) {
      r = parent[r];
    }
    while (parent[x] != r) {
      final nx = parent[x];
      parent[x] = r;
      x = nx;
    }
    return r;
  }

  var isolated = 0;
  for (var i = 0; i < n; i++) {
    var hasNbr = false;
    for (var p = g.indptr[i]; p < g.indptr[i + 1]; p++) {
      if (g.indices[p] != i) {
        hasNbr = true;
        final ri = find(i);
        final rj = find(g.indices[p]);
        if (ri != rj) parent[rj] = ri;
      }
    }
    if (!hasNbr) isolated++;
  }
  final roots = <int>{};
  for (var i = 0; i < n; i++) {
    roots.add(find(i));
  }
  return (roots.length, isolated);
}

double _med(List<int> us) {
  us.sort();
  return us[us.length ~/ 2] / 1000.0;
}

double _heat(Iterable<double> evs, double tau) {
  var s = 0.0;
  for (final l in evs) {
    s += math.exp(-tau * l);
  }
  return s;
}

/// Reference spectral dimension from the dense spectrum: fit the EXCITED
/// heat trace Z_ex(t)=Σ_{λ>0} e^{−tλ} ~ t^{−d/2} over the λ-bracketed
/// power-law window [1/λ_max, 1/λ_gap]. This is the ground truth the
/// truncated-basis estimate should approach.
double _denseDs(List<double> dense) {
  final ex = dense.where((l) => l > 1e-9).toList();
  if (ex.length < 4) return double.nan;
  final lamMin = ex.first, lamMax = ex.last;
  if (!(lamMax > lamMin)) return double.nan;
  final logLo = math.log(1.0 / lamMax), logHi = math.log(1.0 / lamMin);
  const samples = 24;
  var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, nn = 0;
  for (var s = 0; s < samples; s++) {
    final t = math.exp(logLo + (logHi - logLo) * s / (samples - 1));
    var z = 0.0;
    for (final l in ex) {
      z += math.exp(-t * l);
    }
    if (z <= 1e-300) continue;
    final x = math.log(t), y = math.log(z / ex.length);
    sx += x;
    sy += y;
    sxx += x * x;
    sxy += x * y;
    nn++;
  }
  if (nn < 3) return double.nan;
  final mx = sx / nn, my = sy / nn;
  final denom = sxx - nn * mx * mx;
  if (denom.abs() < 1e-18) return double.nan;
  return -2.0 * ((sxy - nn * mx * my) / denom);
}

/// Probe a graph's spectrum and print the report. [haveTruth] forces the
/// dense path regardless of [_denseCap] (used by the synthetic case).
void _probeGraph(CsrGraph g, {bool forceDense = false}) {
  final n = g.n;
  if (n == 0) {
    stdout.writeln('  empty graph');
    return;
  }
  final solveUs = <int>[];
  late SpectralBasis basis;
  for (var t = 0; t < 5; t++) {
    final sw = Stopwatch()..start();
    basis = SpectralBasis.fromGraph(g, math.min(_k, n));
    sw.stop();
    solveUs.add(sw.elapsedMicroseconds);
  }
  var lanczosKernel = 0;
  for (var j = 0; j < basis.k; j++) {
    if (basis.eigenvalues[j] <= 1e-10) lanczosKernel++;
  }

  if (forceDense || n <= _denseCap) {
    final eig = denseSymmetricEigen(_denseLsym(g), n);
    final dense = Float64List.fromList(eig.values)..sort();
    var trueKernel = 0;
    for (final v in dense) {
      if (v <= 1e-9) trueKernel++;
    }
    final kk = math.min(basis.k, n);
    var maxErr = 0.0;
    for (var j = 0; j < kk; j++) {
      final e = (basis.eigenvalues[j] - dense[j]).abs();
      if (e > maxErr) maxErr = e;
    }
    final dlist = dense.toList();
    final capHalf = _heat(basis.eigenvalues.take(kk), 0.5) / _heat(dlist, 0.5);
    final cap2 = _heat(basis.eigenvalues.take(kk), 2.0) / _heat(dlist, 2.0);
    final lamLast = dense[kk - 1];
    final lamNext = n > kk ? dense[kk] : double.nan;
    final lamNext5 = n > kk + 4 ? dense[kk + 4] : double.nan;
    final gap = trueKernel - lanczosKernel;
    stdout.writeln(
        '  KERNEL  true(dense)=$trueKernel  Lanczos=$lanczosKernel  '
        '${gap != 0 ? ">>> UNDERCOUNT $gap" : "ok"}');
    stdout.writeln(
        '  ACCURACY  max|λ_lanczos−λ_dense| over k=$kk : ${maxErr.toStringAsExponential(2)}');
    stdout.writeln(
        '  TRUNC   λ[${kk - 1}]=${lamLast.toStringAsFixed(4)}  '
        'λ[$kk]=${lamNext.toStringAsFixed(4)}  '
        'λ[${kk + 4}]=${lamNext5.toStringAsFixed(4)}');
    stdout.writeln(
        '  CAPTURE Z_k/Z_n  τ=0.5: ${(capHalf * 100).toStringAsFixed(1)}%   '
        'τ=2.0: ${(cap2 * 100).toStringAsFixed(1)}%');
    final curDs = basis.spectralDimension();
    final fullDs = spectralDimension(basis, graph: g)?.dS ?? double.nan;
    final refDs = _denseDs(dlist);
    stdout.writeln(
        '  SPEC-DIM basis(trunc)=${curDs.toStringAsFixed(2)}  '
        'stochastic-full=${fullDs.toStringAsFixed(2)}  '
        'dense-ref=${refDs.toStringAsFixed(2)}');
  } else {
    stdout.writeln('  KERNEL  Lanczos=$lanczosKernel  (dense skipped, n>$_denseCap)');
  }
  stdout.writeln('  SOLVE   Lanczos k=$_k : ${_med(solveUs).toStringAsFixed(2)} ms (median of 5)');
}

CsrGraph _disjointCliques(int numCliques, int sizePer) {
  final n = numCliques * sizePer;
  final eps = List.generate(n, (_) => <(int, double)>[]);
  for (var c = 0; c < numCliques; c++) {
    final base = c * sizePer;
    for (var a = 0; a < sizePer; a++) {
      for (var b = 0; b < sizePer; b++) {
        if (a != b) eps[base + a].add((base + b, 1.0));
      }
    }
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: eps);
}

Future<void> _profileRepo(String label, String path) async {
  stdout.writeln('\n========== $label ==========');
  if (!Directory(path).existsSync()) {
    stdout.writeln('  SKIP — not found at $path');
    return;
  }
  final ccRes = await computeFileCoupling(path);
  final cc = ccRes.data;
  if (cc == null) {
    stdout.writeln('  coupling FAILED: ${ccRes.error}');
    return;
  }
  final statsRes = await collectLogosGitStats(path, coupling: cc);
  final stats = statsRes.data;
  if (stats == null) {
    stdout.writeln('  stats FAILED: ${statsRes.error}');
    return;
  }
  final engine = LogosGit.buildFromStats(stats);
  final g = engine.graphForTesting;
  final (beta0, isolated) = _components(g);
  stdout.writeln('  n=${g.n}  undirected edges=${_undirectedEdges(g)}  '
      'β₀(union-find)=$beta0  isolated(deg0)=$isolated');
  _probeGraph(g);
}

void main() async {
  stdout.writeln('\n################ SPECTRUM PROFILE (baseline) ################');
  stdout.writeln('dart ${Platform.version.split(' ').first}  cores=${Platform.numberOfProcessors}');

  stdout.writeln('\n========== synthetic: 3 disjoint 8-cliques (β₀=3, kernelDim=3) ==========');
  _probeGraph(_disjointCliques(3, 8), forceDense: true);
  stdout.writeln('\n========== synthetic: 5 disjoint 12-cliques (β₀=5, kernelDim=5) ==========');
  _probeGraph(_disjointCliques(5, 12), forceDense: true);

  for (final (label, path) in _repos) {
    await _profileRepo(label, path);
  }
  stdout.writeln('\n################ END ################\n');
}
