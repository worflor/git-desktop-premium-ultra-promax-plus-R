// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Validates the UASE numerical core on a dynamic graph with a known answer:
// two stable communities, one growing, and a node that migrates between them.
// The properties that matter for Orrery: a node whose neighbourhood is
// unchanged keeps EXACTLY the same coordinate across frames (the teleport fix),
// communities are separated, and a node that genuinely moves, moves.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/uase.dart';

List<UaseEdge> _clique(List<int> nodes) {
  final e = <UaseEdge>[];
  for (var i = 0; i < nodes.length; i++) {
    for (var j = i + 1; j < nodes.length; j++) {
      e.add((a: nodes[i], b: nodes[j], w: 1.0));
    }
  }
  return e;
}

double _within(Float64List frame, int i, int j, int d) {
  var s = 0.0;
  for (var k = 0; k < d; k++) {
    final diff = frame[i * d + k] - frame[j * d + k];
    s += diff * diff;
  }
  return math.sqrt(s);
}

double _across(Float64List f1, int i1, Float64List f2, int i2, int d) {
  var s = 0.0;
  for (var k = 0; k < d; k++) {
    final diff = f1[i1 * d + k] - f2[i2 * d + k];
    s += diff * diff;
  }
  return math.sqrt(s);
}

void main() {
  test('UASE is stable for unchanged nodes and tracks genuine movement', () {
    const n = 11;
    final a = [0, 1, 2, 3, 4];
    final b = [5, 6, 7, 8, 9];

    final f0 = [..._clique(a), ..._clique(b)]; // two communities
    final f1 = [
      ..._clique(a),
      ..._clique([5, 6, 7, 8, 9, 10])
    ]; // B grows
    final f2 = [
      ..._clique([0, 1, 2, 3]),
      ..._clique([4, 5, 6, 7, 8, 9, 10]), // node 4 defects A → B
    ];

    final res = unfoldedSpectralEmbedding(<List<UaseEdge>>[f0, f1, f2], n, 4);
    final d = res.dims;
    final e0 = res.frames[0];
    final e1 = res.frames[1];
    final e2 = res.frames[2];

    // (1) THE fix: node 0's neighbourhood is identical in frames 0 and 1
    // (A is untouched while B grows), so its coordinate is *exactly* the same —
    // no per-frame sign flip, no teleport.
    expect(_across(e0, 0, e1, 0, d), lessThan(1e-9));

    // (2) The two communities are clearly separated at frame 0.
    final intra = _within(e0, 0, 1, d);
    final inter = _within(e0, 0, 5, d);
    expect(inter, greaterThan(0.05));
    expect(inter, greaterThan(intra));

    // (3) The defecting node moves more than a node that stayed, and lands
    // nearer its new community than its old one.
    expect(_across(e0, 4, e2, 4, d), greaterThan(_across(e0, 0, e2, 0, d)));
    expect(_within(e2, 4, 5, d), lessThan(_within(e2, 4, 0, d)));
  });
}
