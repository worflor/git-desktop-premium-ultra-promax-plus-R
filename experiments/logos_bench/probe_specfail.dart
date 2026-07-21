// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: LicenseRef-WLCSL-1.0
// See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

// Probe the two spectral_observables_test failures against dense ground
// truth, to decide: solver bug, or test calibrated to the old undercount?
//
//   dart --packages=experiments/logos_bench/package_config.json \
//        experiments/logos_bench/probe_specfail.dart

import 'dart:math' as math;
import 'dart:typed_data';

import '../../apps/desktop-flutter/lib/backend/logos_core.dart';

Float64List denseLsym(CsrGraph g) {
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

List<double> denseEigs(CsrGraph g) {
  final e = denseSymmetricEigen(denseLsym(g), g.n);
  return (Float64List.fromList(e.values)..sort()).toList();
}

double rValue(List<double> evs) {
  var sum = 0.0;
  var n = 0;
  for (var j = 1; j < evs.length - 1; j++) {
    final sp = evs[j] - evs[j - 1];
    final sn = evs[j + 1] - evs[j];
    final lo = sp < sn ? sp : sn;
    final hi = sp < sn ? sn : sp;
    if (hi <= 1e-300) continue;
    sum += lo / hi;
    n++;
  }
  return n == 0 ? double.nan : sum / n;
}

CsrGraph grid(int side) {
  final n = side * side;
  final eps = List.generate(n, (_) => <(int, double)>[]);
  int id(int r, int c) => r * side + c;
  for (var r = 0; r < side; r++) {
    for (var c = 0; c < side; c++) {
      if (c + 1 < side) {
        eps[id(r, c)].add((id(r, c + 1), 1.0));
        eps[id(r, c + 1)].add((id(r, c), 1.0));
      }
      if (r + 1 < side) {
        eps[id(r, c)].add((id(r + 1, c), 1.0));
        eps[id(r + 1, c)].add((id(r, c), 1.0));
      }
    }
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: eps);
}

CsrGraph twoClusters(int nPer, double bridge) {
  final e = List<List<(int, double)>>.generate(2 * nPer, (_) => []);
  for (var i = 0; i < nPer - 1; i++) {
    e[i].add((i + 1, 1.0));
    e[i + 1].add((i, 1.0));
    e[nPer + i].add((nPer + i + 1, 1.0));
    e[nPer + i + 1].add((nPer + i, 1.0));
  }
  if (bridge > 0) {
    e[nPer - 1].add((nPer, bridge));
    e[nPer].add((nPer - 1, bridge));
  }
  return CsrGraph.fromRawEdges(n: 2 * nPer, edgesPerNode: e);
}

String fmt(List<double> xs) =>
    xs.map((x) => x.toStringAsFixed(4)).join(' ');

void main() {
  print('=== 8x8 grid r-value ===');
  final g = grid(8);
  final lan = SpectralBasis.fromGraph(g, 20);
  final lanEigs = List.generate(lan.k, (j) => lan.eigenvalues[j]);
  final dense20 = denseEigs(g).take(20).toList();
  print('  Lanczos r = ${rValue(lanEigs).toStringAsFixed(4)}  (k=${lan.k})');
  print('  dense   r = ${rValue(dense20).toStringAsFixed(4)}  (20 smallest)');
  print('  Lanczos eigs: ${fmt(lanEigs)}');
  print('  dense   eigs: ${fmt(dense20)}');

  print('\n=== Casimir twoClusters(6, w), k=12 ===');
  for (final w in [0.0, 0.05]) {
    final cg = twoClusters(6, w);
    final b = SpectralBasis.fromGraph(cg, 12);
    final le = List.generate(b.k, (j) => b.eigenvalues[j]);
    final de = denseEigs(cg);
    print('  bridge=$w  k=${b.k}');
    print('    Lanczos: ${fmt(le)}');
    print('    dense  : ${fmt(de)}');
  }
}
