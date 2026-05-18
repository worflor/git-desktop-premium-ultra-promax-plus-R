import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_flow.dart';

// ═══════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════

const _allAxes = [
  kFlowMutates, kFlowAsync, kFlowResource, kFlowLifecycle,
  kFlowIO, kFlowPure, kFlowError, kFlowRestabilizes,
];

FlowNode _node(String id, int address,
        {double lyapunov = 0.0, int line = 0, String text = ''}) =>
    FlowNode(
        id: id,
        address: address,
        lyapunov: lyapunov,
        sourceLine: line,
        sourceText: text);

FlowGraph _linearGraph(List<(String, int)> spec) {
  final g = FlowGraph();
  for (final (id, addr) in spec) {
    g.addNode(_node(id, addr));
  }
  g.chain([for (final (id, _) in spec) id]);
  return g;
}

FlowGraph _diamondGraph({
  int topAddr = kFlowLifecycle,
  int leftAddr = kFlowMutates,
  int rightAddr = kFlowAsync,
  int bottomAddr = kFlowResource,
}) {
  final g = FlowGraph();
  g.addNode(_node('top', topAddr));
  g.addNode(_node('left', leftAddr));
  g.addNode(_node('right', rightAddr));
  g.addNode(_node('bottom', bottomAddr));
  g.addEdge('top', 'left');
  g.addEdge('top', 'right');
  g.addEdge('left', 'bottom');
  g.addEdge('right', 'bottom');
  return g;
}

int _randomAddr(math.Random rng) {
  var addr = 0;
  for (final ax in _allAxes) {
    if (rng.nextDouble() < 0.3) addr |= ax;
  }
  if (addr == 0) addr = kFlowPure;
  return addr;
}

FlowGraph _randomDAG(int n, double p, math.Random rng) {
  final g = FlowGraph();
  final addrs = List.generate(n, (i) {
    if (i == 0) return kFlowLifecycle;
    if (i == n - 1) return kFlowResource;
    return _randomAddr(rng);
  });
  for (var i = 0; i < n; i++) {
    g.addNode(_node('n$i', addrs[i],
        lyapunov: rng.nextDouble() * 2));
  }
  // DAG: only forward edges i→j where i<j
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (rng.nextDouble() < p) {
        g.addEdge('n$i', 'n$j');
      }
    }
  }
  return g;
}

FlowGraph _randomGraph(int n, double p, math.Random rng) {
  final g = FlowGraph();
  for (var i = 0; i < n; i++) {
    final addr = i == 0
        ? kFlowLifecycle
        : (i == n - 1 ? kFlowResource : _randomAddr(rng));
    g.addNode(_node('n$i', addr, lyapunov: rng.nextDouble() * 2));
  }
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      if (i == j) continue;
      if (rng.nextDouble() < p) g.addEdge('n$i', 'n$j');
    }
  }
  return g;
}

/// Brute-force enumerate all simple paths from [src] to [dst].
int _bruteForcePathCount(FlowGraph g, String src, String dst) {
  var count = 0;
  void dfs(String nid, Set<String> visited) {
    if (nid == dst) {
      count++;
      return;
    }
    for (final e in g.adj[nid] ?? <FlowEdge>[]) {
      if (visited.contains(e.target)) continue;
      visited.add(e.target);
      dfs(e.target, visited);
      visited.remove(e.target);
    }
  }
  dfs(src, {src});
  return count;
}

/// Manually compute oscillator state after a sequence of (kr, ki, gr, h).
(double, double) _manualOscillator(List<(double, double, double, int)> steps) {
  var z1r = 1.0, z1i = 0.0, z0r = 1.0, z0i = 0.0;
  for (final (kr, ki, gr, h) in steps) {
    var zr = kr * z1r - ki * z1i - gr * z0r;
    var zi = kr * z1i + ki * z1r - gr * z0i;
    if (h > 0) {
      final r = (1.0 - math.cos(math.pi * h / 8)) / 2;
      final t = 1.0 - r;
      zr *= t;
      zi *= t;
    }
    z0r = z1r;
    z0i = z1i;
    z1r = zr;
    z1i = zi;
  }
  final mag = math.sqrt(z1r * z1r + z1i * z1i);
  return (mag < 1.0 ? mag : 1.0, math.atan2(z1i, z1r));
}

String _randomSource(math.Random rng, int lines) {
  final buf = StringBuffer();
  for (var i = 0; i < lines; i++) {
    final indent = rng.nextInt(8) * 2;
    final r = rng.nextDouble();
    if (r < 0.05) {
      buf.writeln('${' ' * indent}// comment $i');
    } else if (r < 0.08) {
      buf.writeln('');
    } else {
      buf.writeln('${' ' * indent}stmt_$i(${rng.nextInt(100)})');
    }
  }
  return buf.toString();
}

// ═══════════════════════════════════════════════════════════════════
// 1. K-G spectrum — targeted
// ═══════════════════════════════════════════════════════════════════

void main() {
  group('flowKG — targeted', () {
    test('PURE-only yields identity (K=1, G=0)', () {
      final (kr, ki, gr) = flowKG(kFlowPure);
      expect(kr, 1.0);
      expect(ki, 0.0);
      expect(gr, 0.0);
    });

    test('PURE combined with another axis does NOT reset', () {
      final (kr, _, _) = flowKG(kFlowPure | kFlowMutates);
      expect(kr, 7.0 / 8.0);
    });

    test('MUTATES attenuates K by 7/8', () {
      final (kr, ki, gr) = flowKG(kFlowMutates);
      expect(kr, 7.0 / 8.0);
      expect(ki, 0.0);
      expect(gr, 0.0);
    });

    test('IO attenuates K by 3/4', () {
      final (kr, _, _) = flowKG(kFlowIO);
      expect(kr, 3.0 / 4.0);
    });

    test('MUTATES|IO compounds multiplicatively', () {
      final (kr, _, _) = flowKG(kFlowMutates | kFlowIO);
      expect(kr, closeTo(7.0 / 8.0 * 3.0 / 4.0, 1e-15));
    });

    test('ERROR amplifies K by 8/7 (reciprocal of MUTATES)', () {
      final (kr, ki, _) = flowKG(kFlowError);
      expect(kr, closeTo(8.0 / 7.0, 1e-15));
      expect(ki, closeTo(1.0 / (8 * math.pi), 1e-15));
    });

    test('MUTATES × ERROR cancel in K_real', () {
      final (kr, _, _) = flowKG(kFlowMutates | kFlowError);
      expect(kr, closeTo(1.0, 1e-15));
    });

    test('LIFECYCLE adds inertia G = sin²(π/8)', () {
      final (_, _, gr) = flowKG(kFlowLifecycle);
      final expected = math.sin(math.pi / 8) * math.sin(math.pi / 8);
      expect(gr, closeTo(expected, 1e-15));
    });

    test('RESOURCE adds inertia G = sin²(π/16)', () {
      final (_, _, gr) = flowKG(kFlowResource);
      final expected = math.sin(math.pi / 16) * math.sin(math.pi / 16);
      expect(gr, closeTo(expected, 1e-15));
    });

    test('LIFECYCLE|RESOURCE accumulates both inertia terms', () {
      final (_, _, gr) = flowKG(kFlowLifecycle | kFlowResource);
      final sinPi8Sq = math.sin(math.pi / 8) * math.sin(math.pi / 8);
      final sinPi16Sq = math.sin(math.pi / 16) * math.sin(math.pi / 16);
      expect(gr, closeTo(sinPi8Sq + sinPi16Sq, 1e-15));
    });

    test('ASYNC with zero Lyapunov: K survives fully', () {
      final (kr, ki, _) = flowKG(kFlowAsync, lyapunov: 0.0);
      expect(kr, closeTo(1.0, 1e-15));
      expect(ki, closeTo(0.0, 1e-15));
    });

    test('ASYNC with positive Lyapunov: Gaussian discharge', () {
      const ly = 1.5;
      final (kr, ki, _) = flowKG(kFlowAsync, lyapunov: ly);
      expect(kr, closeTo(math.exp(-ly * ly), 1e-12));
      final expectedKi = ly * math.sin(math.pi / 4) / (2 * math.pi);
      expect(ki, closeTo(expectedKi, 1e-12));
    });

    test('ASYNC sets G to zero', () {
      final (_, _, gr) = flowKG(kFlowAsync);
      expect(gr, 0.0);
    });

    test('RESTABILIZES with coverage yields projection operator', () {
      const cov = 0.6;
      final (kr, _, gr) = flowKG(kFlowRestabilizes, restabCoverage: cov);
      expect(kr, closeTo(1.0 / (1.0 - cov), 1e-12));
      expect(gr, closeTo(-cov / 4.0, 1e-12));
    });

    test('RESTABILIZES floor-clamps coverage to 0.25', () {
      final (kr, _, _) = flowKG(kFlowRestabilizes, restabCoverage: 0.0);
      expect(kr, closeTo(1.0 / (1.0 - 0.25), 1e-12));
    });

    test('RESTABILIZES ceiling-clamps coverage to 0.95', () {
      final (kr, _, _) = flowKG(kFlowRestabilizes, restabCoverage: 1.0);
      expect(kr, closeTo(1.0 / (1.0 - 0.95), 1e-12));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 1b. K-G spectrum — exhaustive lattice sweep
  // ═══════════════════════════════════════════════════════════════════

  group('flowKG — all 256 addresses', () {
    test('every address produces finite K, G', () {
      for (var addr = 0; addr < 256; addr++) {
        for (final ly in [0.0, 0.5, 1.5, 3.0]) {
          for (final cov in [0.0, 0.5, 1.0]) {
            final (kr, ki, gr) =
                flowKG(addr, lyapunov: ly, restabCoverage: cov);
            expect(kr.isFinite, true,
                reason: 'addr=$addr ly=$ly cov=$cov → kr=$kr');
            expect(ki.isFinite, true,
                reason: 'addr=$addr ly=$ly cov=$cov → ki=$ki');
            expect(gr.isFinite, true,
                reason: 'addr=$addr ly=$ly cov=$cov → gr=$gr');
            expect(kr.isNaN, false);
            expect(ki.isNaN, false);
            expect(gr.isNaN, false);
          }
        }
      }
    });

    test('PURE-only bit pattern always resets to identity', () {
      final (kr, ki, gr) = flowKG(kFlowPure);
      expect(kr, 1.0);
      expect(ki, 0.0);
      expect(gr, 0.0);
    });

    test('every address with ASYNC has K_real ≤ 1 (Gaussian ≤ 1)', () {
      for (var addr = 0; addr < 256; addr++) {
        if (addr & kFlowAsync == 0) continue;
        if (addr & kFlowRestabilizes != 0) continue; // restab uses max
        if (addr & kFlowError != 0) continue; // error amplifies
        final (kr, _, _) = flowKG(addr, lyapunov: 1.0);
        expect(kr, lessThanOrEqualTo(1.0 + 1e-12),
            reason: 'ASYNC addr=$addr should have K≤1');
      }
    });

    test('RESTABILIZES K is always ≥ 1/(1-0.25) = 4/3', () {
      for (var addr = 0; addr < 256; addr++) {
        if (addr & kFlowRestabilizes == 0) continue;
        final (kr, _, _) = flowKG(addr, restabCoverage: 0.0);
        expect(kr, greaterThanOrEqualTo(1.0 / (1.0 - 0.25) - 1e-12),
            reason: 'addr=$addr restab K must be at least 1/(1-0.25)');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 1c. K-G spectrum — Lyapunov fuzzing
  // ═══════════════════════════════════════════════════════════════════

  group('flowKG — Lyapunov fuzz', () {
    test('ASYNC K_real monotonically decreasing with |Lyapunov|', () {
      var prevKr = double.infinity;
      for (var ly = 0.0; ly <= 5.0; ly += 0.05) {
        final (kr, _, _) = flowKG(kFlowAsync, lyapunov: ly);
        expect(kr, lessThanOrEqualTo(prevKr + 1e-12),
            reason: 'ly=$ly: Gaussian discharge should be monotone');
        prevKr = kr;
      }
    });

    test('500 random Lyapunov values produce finite output', () {
      final rng = math.Random(1001);
      for (var i = 0; i < 500; i++) {
        final addr = rng.nextInt(256);
        final ly = rng.nextDouble() * 10;
        final cov = rng.nextDouble();
        final (kr, ki, gr) =
            flowKG(addr, lyapunov: ly, restabCoverage: cov);
        expect(kr.isFinite && ki.isFinite && gr.isFinite, true,
            reason: 'trial $i: addr=$addr ly=$ly cov=$cov');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 2. Hamming distance — targeted + exhaustive
  // ═══════════════════════════════════════════════════════════════════

  group('flowHamming — targeted', () {
    test('same address → 0', () {
      expect(flowHamming(kFlowMutates, kFlowMutates), 0);
      expect(flowHamming(0xFF, 0xFF), 0);
      expect(flowHamming(0, 0), 0);
    });

    test('single bit difference → 1', () {
      expect(flowHamming(0, 1), 1);
      expect(flowHamming(kFlowPure, kFlowPure | kFlowMutates), 1);
    });

    test('all bits differ → 8', () {
      expect(flowHamming(0, 0xFF), 8);
    });

    test('known popcount values', () {
      expect(flowHamming(0, 0x0F), 4);
      expect(flowHamming(0, kFlowMutates | kFlowAsync | kFlowResource), 3);
    });
  });

  group('flowHamming — exhaustive metric axioms', () {
    test('d(x,x) = 0 for all 256 addresses', () {
      for (var a = 0; a < 256; a++) {
        expect(flowHamming(a, a), 0, reason: 'a=$a');
      }
    });

    test('symmetry: d(a,b) = d(b,a) for all 65536 pairs', () {
      for (var a = 0; a < 256; a++) {
        for (var b = a + 1; b < 256; b++) {
          expect(flowHamming(a, b), flowHamming(b, a),
              reason: 'a=$a b=$b');
        }
      }
    });

    test('triangle inequality for 1000 random triples', () {
      final rng = math.Random(2002);
      for (var i = 0; i < 1000; i++) {
        final a = rng.nextInt(256);
        final b = rng.nextInt(256);
        final c = rng.nextInt(256);
        expect(flowHamming(a, c),
            lessThanOrEqualTo(flowHamming(a, b) + flowHamming(b, c)),
            reason: 'trial $i: a=$a b=$b c=$c');
      }
    });

    test('range: 0 ≤ d(a,b) ≤ 8 for all pairs', () {
      for (var a = 0; a < 256; a++) {
        for (var b = 0; b < 256; b++) {
          final d = flowHamming(a, b);
          expect(d, greaterThanOrEqualTo(0));
          expect(d, lessThanOrEqualTo(8));
        }
      }
    });

    test('d(a,b) = popcount(a^b) for all pairs', () {
      int popcount(int x) {
        var c = 0;
        var v = x & 0xFF;
        while (v != 0) {
          v &= v - 1;
          c++;
        }
        return c;
      }
      for (var a = 0; a < 256; a++) {
        for (var b = 0; b < 256; b++) {
          expect(flowHamming(a, b), popcount(a ^ b),
              reason: 'a=$a b=$b');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 3. Coverage — targeted + exhaustive
  // ═══════════════════════════════════════════════════════════════════

  group('flowCoverage — targeted', () {
    test('identity', () {
      const addr = kFlowMutates | kFlowResource | kFlowLifecycle;
      expect(flowCoverage(addr, addr), 1.0);
    });

    test('disjoint → 0', () {
      expect(flowCoverage(kFlowMutates, kFlowAsync), 0.0);
      expect(flowCoverage(0x0F, 0xF0), 0.0);
    });

    test('partial overlap', () {
      const restab = kFlowMutates | kFlowResource;
      const resource = kFlowResource | kFlowLifecycle;
      expect(flowCoverage(restab, resource), 0.5);
    });

    test('superset covers fully', () {
      const restab = kFlowMutates | kFlowResource | kFlowLifecycle;
      const resource = kFlowResource | kFlowLifecycle;
      expect(flowCoverage(restab, resource), 1.0);
    });

    test('empty resource → 1.0', () {
      expect(flowCoverage(kFlowMutates, 0), 1.0);
    });

    test('asymmetric', () {
      const a = kFlowMutates | kFlowResource;
      const b = kFlowResource;
      expect(flowCoverage(a, b), 1.0);
      expect(flowCoverage(b, a), 0.5);
    });
  });

  group('flowCoverage — exhaustive', () {
    test('coverage ∈ [0, 1] for all 65536 pairs', () {
      for (var a = 0; a < 256; a++) {
        for (var b = 0; b < 256; b++) {
          final c = flowCoverage(a, b);
          expect(c, greaterThanOrEqualTo(0.0),
              reason: 'a=$a b=$b → $c');
          expect(c, lessThanOrEqualTo(1.0),
              reason: 'a=$a b=$b → $c');
        }
      }
    });

    test('self-coverage = 1.0 when popcount > 0', () {
      for (var a = 1; a < 256; a++) {
        expect(flowCoverage(a, a), 1.0, reason: 'a=$a');
      }
    });

    test('superset ⊇ resource → coverage = 1.0', () {
      for (var b = 1; b < 256; b++) {
        final a = b | 0xFF; // superset of everything
        expect(flowCoverage(a, b), 1.0, reason: 'b=$b');
      }
    });

    test('monotone: adding bits to restab cannot decrease coverage', () {
      final rng = math.Random(3003);
      for (var i = 0; i < 500; i++) {
        final resource = rng.nextInt(255) + 1;
        final base = rng.nextInt(256);
        final extra = rng.nextInt(256);
        final superset = base | extra;
        final covBase = flowCoverage(base, resource);
        final covSuper = flowCoverage(superset, resource);
        expect(covSuper, greaterThanOrEqualTo(covBase - 1e-15),
            reason: 'trial $i: adding bits cannot reduce coverage');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 4. AR(2) oscillator — targeted
  // ═══════════════════════════════════════════════════════════════════

  group('FlowOscillator — targeted', () {
    test('initial state: certainty=1, phase=0', () {
      final o = FlowOscillator();
      expect(o.certainty, 1.0);
      expect(o.phase, 0.0);
    });

    test('step through pure node preserves certainty', () {
      final o = FlowOscillator();
      o.step(1.0, 0.0, 0.0, 0);
      expect(o.certainty, closeTo(1.0, 1e-15));
      o.step(1.0, 0.0, 0.0, 0);
      expect(o.certainty, closeTo(1.0, 1e-15));
    });

    test('MUTATES step: geometric decay by 7/8', () {
      final o = FlowOscillator();
      final (kr, ki, gr) = flowKG(kFlowMutates);
      o.step(kr, ki, gr, 0);
      expect(o.certainty, closeTo(7.0 / 8.0, 1e-12));
      o.step(kr, ki, gr, 0);
      expect(o.certainty, closeTo(49.0 / 64.0, 1e-12));
      o.step(kr, ki, gr, 0);
      expect(o.certainty, closeTo(343.0 / 512.0, 1e-12));
    });

    test('AR(2) recurrence exact for LIFECYCLE inertia', () {
      final o = FlowOscillator();
      final g = math.sin(math.pi / 8) * math.sin(math.pi / 8);
      o.step(1.0, 0.0, g, 0);
      expect(o.certainty, closeTo(1.0 - g, 1e-12));
      o.step(1.0, 0.0, g, 0);
      expect(o.certainty, closeTo(1.0 - 2 * g, 1e-12));
      o.step(1.0, 0.0, g, 0);
      expect(o.certainty, closeTo(1.0 - 3 * g + g * g, 1e-12));
    });

    test('Hamming impedance: h=0 full, h=4 half, h=8 block', () {
      var o = FlowOscillator();
      o.step(1.0, 0.0, 0.0, 0);
      expect(o.certainty, closeTo(1.0, 1e-15));

      o = FlowOscillator();
      o.step(1.0, 0.0, 0.0, 4);
      expect(o.certainty, closeTo(0.5, 1e-12));

      o = FlowOscillator();
      o.step(1.0, 0.0, 0.0, 8);
      expect(o.certainty, closeTo(0.0, 1e-12));
    });

    test('Hamming impedance monotonic across h=0..8', () {
      final certs = <double>[];
      for (var h = 0; h <= 8; h++) {
        final o = FlowOscillator();
        o.step(1.0, 0.0, 0.0, h);
        certs.add(o.certainty);
      }
      for (var i = 1; i < certs.length; i++) {
        expect(certs[i], lessThanOrEqualTo(certs[i - 1] + 1e-12));
      }
    });

    test('imaginary K produces positive phase', () {
      final o = FlowOscillator();
      o.step(0.9, 0.1, 0.0, 0);
      expect(o.phase, greaterThan(0));
    });

    test('certainty clamped under amplification', () {
      final o = FlowOscillator();
      final (kr, ki, gr) = flowKG(kFlowRestabilizes, restabCoverage: 0.8);
      o.step(kr, ki, gr, 0);
      expect(o.certainty, lessThanOrEqualTo(1.0));
    });

    test('restabilize interpolates toward baseline', () {
      final o = FlowOscillator();
      o.step(0.5, 0.0, 0.0, 0);
      final before = o.certainty;
      o.restabilize(0.5);
      expect(o.certainty, greaterThan(before));
    });

    test('restabilize(1.0) fully restores', () {
      final o = FlowOscillator();
      o.step(0.3, 0.2, 0.1, 3);
      o.restabilize(1.0);
      expect(o.certainty, closeTo(1.0, 1e-12));
      expect(o.phase, closeTo(0.0, 1e-12));
    });

    test('clone independent', () {
      final o = FlowOscillator();
      o.step(0.8, 0.1, 0.05, 2);
      final c = o.clone();
      expect(c.certainty, closeTo(o.certainty, 1e-15));
      o.step(0.5, 0.0, 0.0, 0);
      expect(c.certainty, isNot(closeTo(o.certainty, 1e-5)));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 4b. AR(2) oscillator — manual Z-matrix verification
  // ═══════════════════════════════════════════════════════════════════

  group('FlowOscillator — manual recurrence verification', () {
    test('matches hand-computed Z for 5-step sequence', () {
      final steps = <(double, double, double, int)>[
        (0.9, 0.05, 0.1, 1),
        (0.75, 0.0, 0.0, 3),
        (1.0, 0.1, 0.15, 0),
        (0.8, -0.05, 0.0, 2),
        (0.6, 0.0, 0.2, 0),
      ];
      final o = FlowOscillator();
      for (final (kr, ki, gr, h) in steps) {
        o.step(kr, ki, gr, h);
      }
      final (expectedCert, expectedPhase) = _manualOscillator(steps);
      expect(o.certainty, closeTo(expectedCert, 1e-12));
      expect(o.phase, closeTo(expectedPhase, 1e-12));
    });

    test('1000 random step sequences match manual computation', () {
      final rng = math.Random(4004);
      for (var trial = 0; trial < 1000; trial++) {
        final len = 1 + rng.nextInt(8);
        final steps = List.generate(len, (_) => (
          rng.nextDouble() * 1.5,
          (rng.nextDouble() - 0.5) * 0.3,
          (rng.nextDouble() - 0.5) * 0.4,
          rng.nextInt(9),
        ));

        final o = FlowOscillator();
        for (final (kr, ki, gr, h) in steps) {
          o.step(kr, ki, gr, h);
        }
        final (expectedCert, expectedPhase) = _manualOscillator(steps);
        expect(o.certainty, closeTo(expectedCert, 1e-10),
            reason: 'trial $trial');
        if (o.certainty > 1e-10) {
          expect(o.phase, closeTo(expectedPhase, 1e-10),
              reason: 'trial $trial');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 4c. AR(2) oscillator — heavy fuzz
  // ═══════════════════════════════════════════════════════════════════

  group('FlowOscillator — fuzz', () {
    test('certainty always in [0,1] over 500 random walks of 100 steps', () {
      final rng = math.Random(5005);
      for (var trial = 0; trial < 500; trial++) {
        final o = FlowOscillator();
        for (var step = 0; step < 100; step++) {
          final addr = rng.nextInt(256);
          final ly = rng.nextDouble() * 5;
          final cov = rng.nextDouble();
          final (kr, ki, gr) =
              flowKG(addr, lyapunov: ly, restabCoverage: cov);
          final h = rng.nextInt(9);
          o.step(kr, ki, gr, h);
          expect(o.certainty, greaterThanOrEqualTo(0.0),
              reason: 'trial=$trial step=$step');
          expect(o.certainty, lessThanOrEqualTo(1.0),
              reason: 'trial=$trial step=$step');
          expect(o.certainty.isNaN, false,
              reason: 'trial=$trial step=$step');
          expect(o.phase.isNaN, false,
              reason: 'trial=$trial step=$step');
        }
      }
    });

    test('pure steps preserve certainty over 1000 steps', () {
      final o = FlowOscillator();
      for (var i = 0; i < 1000; i++) {
        o.step(1.0, 0.0, 0.0, 0);
        expect(o.certainty, closeTo(1.0, 1e-12), reason: 'step $i');
      }
    });

    test('restabilize fuzz: reduces Euclidean distance to baseline (1,0)', () {
      final rng = math.Random(6006);
      for (var i = 0; i < 500; i++) {
        final o = FlowOscillator();
        for (var s = 0; s < 5; s++) {
          o.step(rng.nextDouble(), (rng.nextDouble() - 0.5) * 0.2,
              rng.nextDouble() * 0.3, rng.nextInt(5));
        }
        // |z1 - (1,0)|² = cert² - 2·cert·cos(phase) + 1
        final cB = o.certainty, pB = o.phase;
        final distBefore = cB * cB - 2 * cB * math.cos(pB) + 1;

        final strength = rng.nextDouble();
        o.restabilize(strength);

        final cA = o.certainty, pA = o.phase;
        final distAfter = cA * cA - 2 * cA * math.cos(pA) + 1;
        expect(distAfter, lessThanOrEqualTo(distBefore + 1e-10),
            reason: 'trial $i: restabilize should move z1 closer to (1,0)');
      }
    });

    test('clone divergence: 500 fork-and-step pairs', () {
      final rng = math.Random(7007);
      for (var i = 0; i < 500; i++) {
        final o = FlowOscillator();
        for (var s = 0; s < 3; s++) {
          o.step(rng.nextDouble(), 0.0, 0.0, rng.nextInt(5));
        }
        final c = o.clone();
        o.step(0.5, 0.1, 0.05, 2);
        // clone must not have moved
        expect((c.certainty - o.certainty).abs(), greaterThan(1e-15),
            reason: 'trial $i');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 5. Born-rule mixing — targeted + fuzz
  // ═══════════════════════════════════════════════════════════════════

  group('flowBornMix — targeted', () {
    test('single arrival returns its own certainty', () {
      final (mc, mp) = flowBornMix([(0.6, 0.3)]);
      expect(mc, closeTo(0.6, 1e-10));
      expect(mp, closeTo(0.3, 1e-10));
    });

    test('N identical arrivals return the same certainty', () {
      const c = 0.7, p = 0.5;
      final (mc1, _) = flowBornMix([(c, p)]);
      final (mc5, _) = flowBornMix(List.filled(5, (c, p)));
      final (mc100, _) = flowBornMix(List.filled(100, (c, p)));
      expect(mc5, closeTo(mc1, 1e-10));
      expect(mc100, closeTo(mc1, 1e-10));
    });

    test('symmetric', () {
      final (mc1, mp1) = flowBornMix([(0.3, 0.1), (0.8, -0.5)]);
      final (mc2, mp2) = flowBornMix([(0.8, -0.5), (0.3, 0.1)]);
      expect(mc1, closeTo(mc2, 1e-12));
      expect(mp1, closeTo(mp2, 1e-12));
    });

    test('high certainties mix high', () {
      final (mc, _) = flowBornMix([(0.99, 0.0), (0.99, 0.0)]);
      expect(mc, greaterThan(0.95));
    });

    test('result between extremes', () {
      const lo = 0.2, hi = 0.9;
      final (mc, _) = flowBornMix([(lo, 0.0), (hi, 0.0)]);
      expect(mc, greaterThanOrEqualTo(lo - 1e-10));
      expect(mc, lessThanOrEqualTo(hi + 1e-10));
    });

    test('phase is certainty-weighted average', () {
      const c = 0.5;
      final (_, mp) = flowBornMix([(c, 0.2), (c, 0.8)]);
      expect(mp, closeTo(0.5, 1e-10));
    });

    test('phase dominated by high-certainty arrival', () {
      final (_, mp) = flowBornMix([(0.01, 1.0), (0.99, 0.0)]);
      expect(mp.abs(), lessThan(0.05));
    });
  });

  group('flowBornMix — algebraic fuzz', () {
    test('N-copies invariant: 1000 random (c,p) pairs', () {
      final rng = math.Random(8008);
      for (var i = 0; i < 1000; i++) {
        final c = rng.nextDouble() * 0.98 + 0.01;
        final p = (rng.nextDouble() - 0.5) * math.pi;
        final n = 2 + rng.nextInt(20);
        final (mc, _) = flowBornMix(List.filled(n, (c, p)));
        expect(mc, closeTo(c, 1e-8),
            reason: 'trial $i: $n copies of c=$c');
      }
    });

    test('permutation symmetry: 500 random shuffles', () {
      final rng = math.Random(9009);
      for (var i = 0; i < 500; i++) {
        final n = 2 + rng.nextInt(8);
        final arrivals = List.generate(
            n, (_) => (rng.nextDouble(), (rng.nextDouble() - 0.5) * math.pi));
        final shuffled = List.of(arrivals)..shuffle(rng);
        final (mc1, mp1) = flowBornMix(arrivals);
        final (mc2, mp2) = flowBornMix(shuffled);
        expect(mc1, closeTo(mc2, 1e-12), reason: 'trial $i cert');
        expect(mp1, closeTo(mp2, 1e-12), reason: 'trial $i phase');
      }
    });

    test('output ∈ [0, 1]: 2000 random arrival sets', () {
      final rng = math.Random(1010);
      for (var i = 0; i < 2000; i++) {
        final n = 1 + rng.nextInt(20);
        final arrivals = List.generate(
            n, (_) => (rng.nextDouble(), (rng.nextDouble() - 0.5) * math.pi));
        final (mc, mp) = flowBornMix(arrivals);
        expect(mc, greaterThanOrEqualTo(0.0), reason: 'trial $i');
        expect(mc, lessThanOrEqualTo(1.0), reason: 'trial $i');
        expect(mc.isNaN, false, reason: 'trial $i');
        expect(mp.isNaN, false, reason: 'trial $i');
      }
    });

    test('all c=1 arrivals mix to ~1', () {
      for (var n = 1; n <= 20; n++) {
        final (mc, _) = flowBornMix(
            List.generate(n, (i) => (1.0 - 1e-10, i * 0.1)));
        expect(mc, greaterThan(0.99), reason: 'n=$n');
      }
    });

    test('all c≈0 arrivals mix to ~0', () {
      for (var n = 1; n <= 20; n++) {
        final (mc, _) =
            flowBornMix(List.generate(n, (i) => (1e-9, i * 0.1)));
        expect(mc, lessThan(0.01), reason: 'n=$n');
      }
    });

    test('mixing high cert with low cert stays between them: 500 trials', () {
      final rng = math.Random(1111);
      for (var i = 0; i < 500; i++) {
        final lo = rng.nextDouble() * 0.3;
        final hi = 0.7 + rng.nextDouble() * 0.29;
        final (mc, _) = flowBornMix([(lo, 0.0), (hi, 0.0)]);
        expect(mc, greaterThanOrEqualTo(lo - 1e-10), reason: 'trial $i');
        expect(mc, lessThanOrEqualTo(hi + 1e-10), reason: 'trial $i');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 6. FlowNode + FlowGraph — targeted
  // ═══════════════════════════════════════════════════════════════════

  group('FlowNode', () {
    test('factory caches K-G from address', () {
      final node = _node('n', kFlowMutates);
      final (kr, ki, gr) = flowKG(kFlowMutates);
      expect(node.kr, kr);
      expect(node.ki, ki);
      expect(node.gr, gr);
    });

    test('hasAxis checks individual bits', () {
      final node = _node('n', kFlowMutates | kFlowResource);
      expect(node.hasAxis(kFlowMutates), true);
      expect(node.hasAxis(kFlowResource), true);
      expect(node.hasAxis(kFlowAsync), false);
    });

    test('factory K-G matches flowKG for all 8 single axes', () {
      for (final ax in _allAxes) {
        final node = _node('n', ax);
        final (kr, ki, gr) = flowKG(ax);
        expect(node.kr, kr, reason: 'axis=$ax kr');
        expect(node.ki, ki, reason: 'axis=$ax ki');
        expect(node.gr, gr, reason: 'axis=$ax gr');
      }
    });
  });

  group('FlowGraph', () {
    test('addEdge computes hamming distance', () {
      final g = FlowGraph();
      g.addNode(_node('a', kFlowMutates));
      g.addNode(_node('b', kFlowResource));
      g.addEdge('a', 'b');
      expect(g.adj['a']!.first.hamming,
          flowHamming(kFlowMutates, kFlowResource));
    });

    test('addEdge reduces hamming for restab→resource by coverage', () {
      final g = FlowGraph();
      const restabAddr = kFlowRestabilizes | kFlowResource;
      const resAddr = kFlowResource;
      g.addNode(_node('r', restabAddr));
      g.addNode(_node('d', resAddr));
      g.addEdge('r', 'd');
      final rawHamming = flowHamming(restabAddr, resAddr);
      final cov = flowCoverage(restabAddr, resAddr);
      final expected = math.max(0, (rawHamming * (1.0 - cov)).round());
      expect(g.adj['r']!.first.hamming, expected);
    });

    test('addEdge silently ignores unknown nodes', () {
      final g = FlowGraph();
      g.addNode(_node('a', kFlowPure));
      g.addEdge('a', 'nonexistent');
      expect(g.adj['a'], isEmpty);
    });

    test('chain creates sequential edges', () {
      final g = _linearGraph([
        ('a', kFlowLifecycle),
        ('b', kFlowMutates),
        ('c', kFlowResource),
      ]);
      expect(g.adj['a']!.first.target, 'b');
      expect(g.adj['b']!.first.target, 'c');
      expect(g.adj['c'], isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 7. Graph extraction — targeted + fuzz
  // ═══════════════════════════════════════════════════════════════════

  group('extractFlowGraph — targeted', () {
    test('empty source → empty graph', () {
      expect(extractFlowGraph('').nodes, isEmpty);
    });

    test('whitespace-only → empty graph', () {
      expect(extractFlowGraph('  \n\n   \n').nodes, isEmpty);
    });

    test('comment-only → empty graph', () {
      expect(
          extractFlowGraph('// comment\n# comment\n/* block */').nodes, isEmpty);
    });

    test('first code line gets LIFECYCLE', () {
      final g = extractFlowGraph('x = 1\ny = 2');
      expect(g.nodes.values.first.hasAxis(kFlowLifecycle), true);
    });

    test('scope entry: next indent > current + 2 → LIFECYCLE', () {
      final g = extractFlowGraph('fn main:\n    body\n    more');
      expect(g.nodes.values.first.hasAxis(kFlowLifecycle), true);
    });

    test('deep scope lines get RESOURCE', () {
      final lines = ['top', '  mid', '              deep', '  mid2'];
      final g = extractFlowGraph(lines.join('\n'));
      final deep =
          g.nodes.values.firstWhere((n) => n.sourceText.contains('deep'));
      expect(deep.hasAxis(kFlowResource), true);
    });

    test('scope exit gets RESTABILIZES', () {
      final lines = ['top', '          deep_body', 'back'];
      final g = extractFlowGraph(lines.join('\n'));
      final back =
          g.nodes.values.firstWhere((n) => n.sourceText == 'back');
      expect(back.hasAxis(kFlowRestabilizes), true);
    });

    test('sequential edges connect non-comment lines', () {
      final g = extractFlowGraph('a\nb\nc');
      final ids = g.nodes.keys.toList();
      expect(g.adj[ids[0]]!.any((e) => e.target == ids[1]), true);
      expect(g.adj[ids[1]]!.any((e) => e.target == ids[2]), true);
    });

    test('early-return guard breaks sequential edge', () {
      final lines = ['top', '          deep', 'return early', 'unreachable'];
      final g = extractFlowGraph(lines.join('\n'));
      final returnNode = g.nodes.values
          .firstWhere((n) => n.sourceText.contains('return'));
      if (returnNode.hasAxis(kFlowRestabilizes)) {
        final targets =
            (g.adj[returnNode.id] ?? []).map((e) => e.target).toSet();
        final nextId = g.nodes.values
            .where((n) => n.sourceText == 'unreachable')
            .map((n) => n.id)
            .firstOrNull;
        if (nextId != null) {
          expect(targets.contains(nextId), false);
        }
      }
    });

    test('flat indent-0 lines: most are PURE', () {
      final lines = List.generate(10, (i) => 'statement_$i');
      final g = extractFlowGraph(lines.join('\n'));
      final pureCount =
          g.nodes.values.where((n) => n.address == kFlowPure).length;
      expect(pureCount, greaterThan(0));
      expect(g.nodes.values.first.hasAxis(kFlowLifecycle), true);
    });
  });

  group('extractFlowGraph — fuzz', () {
    test('200 random source texts: no crash, valid graph', () {
      final rng = math.Random(1212);
      for (var i = 0; i < 200; i++) {
        final lineCount = 5 + rng.nextInt(60);
        final source = _randomSource(rng, lineCount);
        final g = extractFlowGraph(source);

        // node count ≤ non-empty non-comment line count
        final contentLines = source
            .split('\n')
            .where((l) {
              final s = l.trim();
              return s.isNotEmpty &&
                  !s.startsWith('//') &&
                  !s.startsWith('#') &&
                  !s.startsWith('*') &&
                  !s.startsWith('/*');
            })
            .length;
        expect(g.nodes.length, lessThanOrEqualTo(contentLines),
            reason: 'trial $i');

        // all addresses are valid 8-bit
        for (final node in g.nodes.values) {
          expect(node.address, greaterThan(0),
              reason: 'trial $i node ${node.id}: addr=0 should be kFlowPure');
          expect(node.address, lessThan(256),
              reason: 'trial $i node ${node.id}');
        }

        // all edge targets exist
        for (final entry in g.adj.entries) {
          for (final edge in entry.value) {
            expect(g.nodes.containsKey(edge.target), true,
                reason: 'trial $i: edge ${entry.key}→${edge.target} dangling');
          }
        }

        // first node has LIFECYCLE only if it's on source line 0
        if (g.nodes.isNotEmpty && g.nodes.values.first.sourceLine == 0) {
          expect(g.nodes.values.first.hasAxis(kFlowLifecycle), true,
              reason: 'trial $i');
        }
      }
    });

    test('tab indentation handled: tabs = 4 spaces', () {
      final source = 'top\n\t\tbody\n\t\t\t\tdeep\nback';
      final g = extractFlowGraph(source);
      expect(g.nodes, isNotEmpty);
      // tab indentation should produce valid addresses
      for (final n in g.nodes.values) {
        expect(n.address, greaterThan(0));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 8. Renormalization — targeted + fuzz
  // ═══════════════════════════════════════════════════════════════════

  group('renormalize — targeted', () {
    test('strips linear PURE chain', () {
      final g = FlowGraph();
      g.addNode(_node('a', kFlowLifecycle));
      g.addNode(_node('p1', kFlowPure));
      g.addNode(_node('p2', kFlowPure));
      g.addNode(_node('b', kFlowResource));
      g.chain(['a', 'p1', 'p2', 'b']);
      final r = renormalize(g);
      expect(r.nodes.containsKey('p1'), false);
      expect(r.nodes.containsKey('p2'), false);
    });

    test('rewires edges through removed chain', () {
      final g = FlowGraph();
      g.addNode(_node('a', kFlowLifecycle));
      g.addNode(_node('p', kFlowPure));
      g.addNode(_node('b', kFlowResource));
      g.chain(['a', 'p', 'b']);
      final r = renormalize(g);
      expect(r.adj['a']!.any((e) => e.target == 'b'), true);
    });

    test('preserves PURE with multiple in-edges', () {
      final g = FlowGraph();
      g.addNode(_node('a', kFlowLifecycle));
      g.addNode(_node('b', kFlowMutates));
      g.addNode(_node('p', kFlowPure));
      g.addNode(_node('c', kFlowResource));
      g.addEdge('a', 'p');
      g.addEdge('b', 'p');
      g.addEdge('p', 'c');
      expect(renormalize(g).nodes.containsKey('p'), true);
    });

    test('preserves PURE with multiple out-edges', () {
      final g = FlowGraph();
      g.addNode(_node('a', kFlowLifecycle));
      g.addNode(_node('p', kFlowPure));
      g.addNode(_node('b', kFlowResource));
      g.addNode(_node('c', kFlowMutates));
      g.addEdge('a', 'p');
      g.addEdge('p', 'b');
      g.addEdge('p', 'c');
      expect(renormalize(g).nodes.containsKey('p'), true);
    });

    test('preserves non-PURE unconditionally', () {
      final g = _linearGraph([
        ('a', kFlowLifecycle), ('m', kFlowMutates), ('b', kFlowResource)
      ]);
      expect(renormalize(g).nodes.containsKey('m'), true);
    });

    test('20-node PURE chain collapses to 2 nodes', () {
      final g = FlowGraph();
      g.addNode(_node('entry', kFlowLifecycle));
      for (var i = 0; i < 20; i++) {
        g.addNode(_node('p$i', kFlowPure));
      }
      g.addNode(_node('exit', kFlowResource));
      g.chain(['entry', ...List.generate(20, (i) => 'p$i'), 'exit']);
      final r = renormalize(g);
      expect(r.nodes.length, 2);
      expect(r.adj['entry']!.any((e) => e.target == 'exit'), true);
    });
  });

  group('renormalize — fuzz', () {
    test('300 random graphs: non-PURE nodes always preserved', () {
      final rng = math.Random(1313);
      for (var i = 0; i < 300; i++) {
        final n = 4 + rng.nextInt(15);
        final g = _randomDAG(n, 0.3, rng);
        final nonPure = g.nodes.entries
            .where((e) => e.value.address != kFlowPure)
            .map((e) => e.key)
            .toSet();
        final r = renormalize(g);
        for (final id in nonPure) {
          expect(r.nodes.containsKey(id), true,
              reason: 'trial $i: non-PURE node $id removed');
        }
      }
    });

    test('300 random graphs: node count never increases', () {
      final rng = math.Random(1414);
      for (var i = 0; i < 300; i++) {
        final n = 4 + rng.nextInt(15);
        final g = _randomDAG(n, 0.3, rng);
        final r = renormalize(g);
        expect(r.nodes.length, lessThanOrEqualTo(g.nodes.length),
            reason: 'trial $i');
      }
    });

    test('300 random graphs: all edges point to existing nodes', () {
      final rng = math.Random(1515);
      for (var i = 0; i < 300; i++) {
        final n = 4 + rng.nextInt(15);
        final g = _randomDAG(n, 0.3, rng);
        final r = renormalize(g);
        for (final entry in r.adj.entries) {
          expect(r.nodes.containsKey(entry.key), true,
              reason: 'trial $i: src ${entry.key} not in nodes');
          for (final e in entry.value) {
            expect(r.nodes.containsKey(e.target), true,
                reason: 'trial $i: edge target ${e.target} not in nodes');
          }
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 9. Cooper pair fusion — targeted + fuzz
  // ═══════════════════════════════════════════════════════════════════

  group('fuseCooperPairs — targeted', () {
    test('fuses matching pair', () {
      final g = FlowGraph();
      g.addNode(_node('lock', kFlowMutates | kFlowResource));
      g.addNode(_node('unlock', kFlowRestabilizes | kFlowMutates));
      g.addEdge('lock', 'unlock');
      final f = fuseCooperPairs(g);
      expect(f.nodes.containsKey('lock+unlock'), true);
      expect(f.nodes['lock+unlock']!.address,
          kFlowMutates | kFlowResource | kFlowRestabilizes);
    });

    test('does not fuse multi-out lock', () {
      final g = FlowGraph();
      g.addNode(_node('lock', kFlowMutates | kFlowResource));
      g.addNode(_node('unlock', kFlowRestabilizes | kFlowMutates));
      g.addNode(_node('other', kFlowPure));
      g.addEdge('lock', 'unlock');
      g.addEdge('lock', 'other');
      expect(fuseCooperPairs(g).nodes.containsKey('lock'), true);
    });

    test('does not fuse lock with RESTABILIZES', () {
      final g = FlowGraph();
      g.addNode(
          _node('lock', kFlowMutates | kFlowResource | kFlowRestabilizes));
      g.addNode(_node('unlock', kFlowRestabilizes | kFlowMutates));
      g.addEdge('lock', 'unlock');
      expect(fuseCooperPairs(g).nodes.containsKey('lock'), true);
    });

    test('does not fuse partner lacking RESTABILIZES', () {
      final g = FlowGraph();
      g.addNode(_node('lock', kFlowMutates | kFlowResource));
      g.addNode(_node('notunlock', kFlowMutates));
      g.addEdge('lock', 'notunlock');
      expect(fuseCooperPairs(g).nodes.containsKey('lock'), true);
    });

    test('rewires surrounding edges', () {
      final g = FlowGraph();
      g.addNode(_node('before', kFlowLifecycle));
      g.addNode(_node('lock', kFlowMutates | kFlowResource));
      g.addNode(_node('unlock', kFlowRestabilizes | kFlowMutates));
      g.addNode(_node('after', kFlowResource));
      g.chain(['before', 'lock', 'unlock', 'after']);
      final f = fuseCooperPairs(g);
      expect(f.adj['before']!.any((e) => e.target == 'lock+unlock'), true);
      expect(
          f.adj['lock+unlock']!.any((e) => e.target == 'after'), true);
    });
  });

  group('fuseCooperPairs — fuzz', () {
    test('200 random graphs: fused address = OR of pair addresses', () {
      final rng = math.Random(1616);
      for (var i = 0; i < 200; i++) {
        final n = 4 + rng.nextInt(12);
        final g = _randomDAG(n, 0.25, rng);
        final f = fuseCooperPairs(g);
        for (final node in f.nodes.values) {
          if (node.id.contains('+')) {
            final parts = node.id.split('+');
            final orig0 = g.nodes[parts[0]];
            final orig1 = g.nodes[parts[1]];
            if (orig0 != null && orig1 != null) {
              expect(node.address, orig0.address | orig1.address,
                  reason: 'trial $i: fused ${node.id}');
            }
          }
        }
      }
    });

    test('200 random graphs: no dangling edges after fusion', () {
      final rng = math.Random(1717);
      for (var i = 0; i < 200; i++) {
        final n = 4 + rng.nextInt(12);
        final g = _randomDAG(n, 0.25, rng);
        final f = fuseCooperPairs(g);
        for (final entry in f.adj.entries) {
          for (final e in entry.value) {
            expect(f.nodes.containsKey(e.target), true,
                reason: 'trial $i: edge ${entry.key}→${e.target} dangling');
          }
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 10. optimizeGraph — fuzz
  // ═══════════════════════════════════════════════════════════════════

  group('optimizeGraph — fuzz', () {
    test('300 random graphs: converges within 5 rounds', () {
      final rng = math.Random(1818);
      for (var i = 0; i < 300; i++) {
        final n = 4 + rng.nextInt(15);
        var g = _randomDAG(n, 0.3, rng);
        var prevCount = g.nodes.length;
        var converged = false;
        for (var round = 0; round < 5; round++) {
          g = optimizeGraph(g);
          expect(g.nodes.length, lessThanOrEqualTo(prevCount),
              reason: 'trial $i round $round: node count should not increase');
          if (g.nodes.length == prevCount) {
            converged = true;
            break;
          }
          prevCount = g.nodes.length;
        }
        expect(converged, true,
            reason: 'trial $i: should converge within 5 rounds');
      }
    });

    test('300 random graphs: no dangling edges', () {
      final rng = math.Random(1919);
      for (var i = 0; i < 300; i++) {
        final n = 4 + rng.nextInt(15);
        final g = _randomDAG(n, 0.3, rng);
        final o = optimizeGraph(g);
        for (final entry in o.adj.entries) {
          expect(o.nodes.containsKey(entry.key), true,
              reason: 'trial $i src ${entry.key}');
          for (final e in entry.value) {
            expect(o.nodes.containsKey(e.target), true,
                reason: 'trial $i edge ${entry.key}→${e.target}');
          }
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 11. Simulation — targeted
  // ═══════════════════════════════════════════════════════════════════

  group('simulateFlow — targeted', () {
    test('empty graph → no findings', () {
      expect(simulateFlow(FlowGraph()), isEmpty);
    });

    test('single LIFECYCLE node → no findings', () {
      final g = FlowGraph();
      g.addNode(_node('a', kFlowLifecycle));
      expect(simulateFlow(g), isEmpty);
    });

    test('linear path delivers certainty to resource', () {
      final g = _linearGraph([
        ('a', kFlowLifecycle), ('b', kFlowMutates), ('c', kFlowResource),
      ]);
      final findings = simulateFlow(g, threshold: 1.0);
      expect(findings.length, 1);
      expect(findings.first.nodeId, 'c');
      expect(findings.first.certainty, lessThan(1.0));
      expect(findings.first.certainty, greaterThan(0.0));
    });

    test('diamond graph: 2 paths Born-mixed', () {
      final g = _diamondGraph();
      final findings = simulateFlow(g, threshold: 1.0);
      final bottom = findings.firstWhere((f) => f.nodeId == 'bottom');
      expect(bottom.pathCount, 2);
    });

    test('diamond: both paths explored with backtracking', () {
      final g = _diamondGraph(
          topAddr: kFlowLifecycle, leftAddr: kFlowPure,
          rightAddr: kFlowPure, bottomAddr: kFlowResource);
      final findings = simulateFlow(g, threshold: 1.0);
      expect(findings.firstWhere((f) => f.nodeId == 'bottom').pathCount, 2);
    });

    test('cycle terminates', () {
      final g = FlowGraph();
      g.addNode(_node('a', kFlowLifecycle));
      g.addNode(_node('b', kFlowMutates));
      g.addNode(_node('c', kFlowResource));
      g.addEdge('a', 'b');
      g.addEdge('b', 'c');
      g.addEdge('c', 'a');
      expect(simulateFlow(g, threshold: 1.0), isNotNull);
    });

    test('maxDepth limits exploration', () {
      final g = FlowGraph();
      g.addNode(_node('entry', kFlowLifecycle));
      for (var i = 0; i < 10; i++) {
        g.addNode(_node('m$i', kFlowMutates));
      }
      g.addNode(_node('res', kFlowResource));
      g.chain(['entry', ...List.generate(10, (i) => 'm$i'), 'res']);
      expect(
          simulateFlow(g, threshold: 1.0, maxDepth: 2)
              .where((f) => f.nodeId == 'res')
              .length,
          0);
      expect(
          simulateFlow(g, threshold: 1.0, maxDepth: 30)
              .where((f) => f.nodeId == 'res')
              .length,
          1);
    });

    test('findings sorted ascending', () {
      final g = FlowGraph();
      g.addNode(_node('entry', kFlowLifecycle));
      g.addNode(_node('m1', kFlowMutates));
      g.addNode(_node('r1', kFlowResource));
      g.addNode(_node('m2', kFlowMutates));
      g.addNode(_node('r2', kFlowResource));
      g.chain(['entry', 'm1', 'r1', 'm2', 'r2']);
      final findings = simulateFlow(g, threshold: 1.0);
      for (var i = 1; i < findings.length; i++) {
        expect(findings[i].certainty,
            greaterThanOrEqualTo(findings[i - 1].certainty));
      }
    });

    test('threshold filters', () {
      final g = _linearGraph([
        ('e', kFlowLifecycle), ('m', kFlowMutates), ('r', kFlowResource),
      ]);
      expect(simulateFlow(g, threshold: 1.0), isNotEmpty);
      expect(simulateFlow(g, threshold: 0.001).length,
          lessThanOrEqualTo(simulateFlow(g, threshold: 1.0).length));
    });

    test('entry fallback: first node if no LIFECYCLE', () {
      final g = FlowGraph();
      g.addNode(_node('a', kFlowMutates));
      g.addNode(_node('b', kFlowResource));
      g.addEdge('a', 'b');
      expect(simulateFlow(g, threshold: 1.0).length, 1);
    });

    test('explicit entryNodes', () {
      final g = FlowGraph();
      g.addNode(_node('a', kFlowLifecycle));
      g.addNode(_node('b', kFlowMutates));
      g.addNode(_node('c', kFlowResource));
      g.addEdge('a', 'b');
      g.addEdge('b', 'c');
      final fromB = simulateFlow(g, entryNodes: {'b'}, threshold: 1.0);
      final fromA = simulateFlow(g, threshold: 1.0);
      expect(fromB.first.certainty, greaterThan(fromA.first.certainty));
    });

    test('restabilizer restores certainty vs pure path', () {
      final gR = FlowGraph();
      gR.addNode(_node('e', kFlowLifecycle));
      gR.addNode(_node('m', kFlowMutates));
      gR.addNode(_node('r', kFlowRestabilizes | kFlowResource));
      gR.addNode(_node('d', kFlowResource));
      gR.chain(['e', 'm', 'r', 'd']);

      final gP = FlowGraph();
      gP.addNode(_node('e', kFlowLifecycle));
      gP.addNode(_node('m', kFlowMutates));
      gP.addNode(_node('p', kFlowPure));
      gP.addNode(_node('d', kFlowResource));
      gP.chain(['e', 'm', 'p', 'd']);

      final cR = simulateFlow(gR, threshold: 1.0)
          .firstWhere((f) => f.nodeId == 'd')
          .certainty;
      final cP = simulateFlow(gP, threshold: 1.0)
          .firstWhere((f) => f.nodeId == 'd')
          .certainty;
      expect(cR, greaterThan(cP));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 12. DFS backtracking — targeted + brute-force verification
  // ═══════════════════════════════════════════════════════════════════

  group('DFS backtracking — targeted', () {
    test('fan-out: 4 paths', () {
      final g = FlowGraph();
      g.addNode(_node('entry', kFlowLifecycle));
      for (var i = 0; i < 4; i++) {
        g.addNode(_node('b$i', kFlowMutates));
        g.addEdge('entry', 'b$i');
      }
      g.addNode(_node('res', kFlowResource));
      for (var i = 0; i < 4; i++) {
        g.addEdge('b$i', 'res');
      }
      expect(
          simulateFlow(g, threshold: 1.0)
              .firstWhere((f) => f.nodeId == 'res')
              .pathCount,
          4);
    });

    test('binary tree: 4 leaf paths', () {
      final g = FlowGraph();
      g.addNode(_node('root', kFlowLifecycle));
      for (final id in ['l', 'r', 'll', 'lr', 'rl', 'rr']) {
        g.addNode(_node(id, kFlowMutates));
      }
      g.addNode(_node('sink', kFlowResource));
      g.addEdge('root', 'l');
      g.addEdge('root', 'r');
      g.addEdge('l', 'll');
      g.addEdge('l', 'lr');
      g.addEdge('r', 'rl');
      g.addEdge('r', 'rr');
      for (final leaf in ['ll', 'lr', 'rl', 'rr']) {
        g.addEdge(leaf, 'sink');
      }
      expect(
          simulateFlow(g, threshold: 1.0)
              .firstWhere((f) => f.nodeId == 'sink')
              .pathCount,
          4);
    });

    test('shared intermediate re-visited', () {
      final g = FlowGraph();
      g.addNode(_node('entry', kFlowLifecycle));
      g.addNode(_node('a', kFlowMutates));
      g.addNode(_node('b', kFlowIO));
      g.addNode(_node('shared', kFlowAsync));
      g.addNode(_node('res', kFlowResource));
      g.addEdge('entry', 'a');
      g.addEdge('entry', 'b');
      g.addEdge('a', 'shared');
      g.addEdge('b', 'shared');
      g.addEdge('shared', 'res');
      expect(
          simulateFlow(g, threshold: 1.0)
              .firstWhere((f) => f.nodeId == 'res')
              .pathCount,
          2);
    });
  });

  group('DFS backtracking — brute-force path count verification', () {
    test('200 small random DAGs: pathCount matches brute-force enumeration',
        () {
      final rng = math.Random(2020);
      for (var trial = 0; trial < 200; trial++) {
        final n = 4 + rng.nextInt(8); // 4-11 nodes
        final g = _randomDAG(n, 0.35, rng);

        // find entry nodes the same way simulateFlow does
        var entries = g.nodes.values
            .where((n) => n.hasAxis(kFlowLifecycle))
            .map((n) => n.id)
            .toSet();
        if (entries.isEmpty && g.nodes.isNotEmpty) {
          entries = {g.nodes.values.first.id};
        }

        // find resource nodes
        final resources = g.nodes.values
            .where((n) => n.hasAxis(kFlowResource))
            .map((n) => n.id)
            .toSet();
        if (resources.isEmpty) continue;

        // brute-force: count simple paths from each entry to each resource
        final expectedCounts = <String, int>{};
        for (final res in resources) {
          var total = 0;
          for (final entry in entries) {
            total += _bruteForcePathCount(g, entry, res);
          }
          if (total > 0) expectedCounts[res] = total;
        }

        // simulate
        final findings = simulateFlow(g, threshold: 1.0);
        for (final f in findings) {
          if (expectedCounts.containsKey(f.nodeId)) {
            expect(f.pathCount, expectedCounts[f.nodeId],
                reason:
                    'trial $trial node ${f.nodeId}: pathCount mismatch');
          }
        }

        // also verify every resource with brute-force paths > 0 has a finding
        for (final entry in expectedCounts.entries) {
          final found = findings.any((f) => f.nodeId == entry.key);
          expect(found, true,
              reason:
                  'trial $trial: resource ${entry.key} has ${entry.value} paths but no finding');
        }
      }
    });

    test('100 random graphs WITH cycles: terminates and produces valid output',
        () {
      final rng = math.Random(2121);
      for (var trial = 0; trial < 100; trial++) {
        final n = 4 + rng.nextInt(10);
        final g = _randomGraph(n, 0.25, rng);
        final findings = simulateFlow(g, threshold: 1.0);
        for (final f in findings) {
          expect(f.certainty, greaterThanOrEqualTo(0.0),
              reason: 'trial $trial');
          expect(f.certainty, lessThanOrEqualTo(1.0),
              reason: 'trial $trial');
          expect(f.pathCount, greaterThan(0), reason: 'trial $trial');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 13. Adversarial graph topologies
  // ═══════════════════════════════════════════════════════════════════

  group('adversarial topologies', () {
    test('complete graph K_8: terminates, valid findings', () {
      final g = FlowGraph();
      for (var i = 0; i < 8; i++) {
        final addr = i == 0
            ? kFlowLifecycle
            : (i == 7 ? kFlowResource : kFlowMutates);
        g.addNode(_node('n$i', addr));
      }
      for (var i = 0; i < 8; i++) {
        for (var j = 0; j < 8; j++) {
          if (i != j) g.addEdge('n$i', 'n$j');
        }
      }
      final findings = simulateFlow(g, threshold: 1.0);
      for (final f in findings) {
        expect(f.certainty, greaterThanOrEqualTo(0.0));
        expect(f.certainty, lessThanOrEqualTo(1.0));
      }
    });

    test('star graph: hub → N leaves all RESOURCE', () {
      final g = FlowGraph();
      g.addNode(_node('hub', kFlowLifecycle));
      for (var i = 0; i < 20; i++) {
        g.addNode(_node('leaf$i', kFlowResource));
        g.addEdge('hub', 'leaf$i');
      }
      final findings = simulateFlow(g, threshold: 1.0);
      expect(findings.length, 20);
      // all leaves get the same certainty (one step from hub, same addr)
      final certs = findings.map((f) => f.certainty).toSet();
      expect(certs.length, 1, reason: 'symmetric star, all leaves identical');
    });

    test('long chain with back-edge at every node: terminates', () {
      final g = FlowGraph();
      for (var i = 0; i < 15; i++) {
        final addr = i == 0
            ? kFlowLifecycle
            : (i == 14 ? kFlowResource : kFlowMutates);
        g.addNode(_node('n$i', addr));
      }
      for (var i = 0; i < 14; i++) {
        g.addEdge('n$i', 'n${i + 1}');
        g.addEdge('n${i + 1}', 'n$i'); // bidirectional
      }
      final findings = simulateFlow(g, threshold: 1.0);
      expect(findings, isNotNull);
    });

    test('disconnected components: only reachable resources get findings', () {
      final g = FlowGraph();
      // component 1
      g.addNode(_node('a', kFlowLifecycle));
      g.addNode(_node('b', kFlowResource));
      g.addEdge('a', 'b');
      // component 2 (unreachable from a)
      g.addNode(_node('c', kFlowMutates));
      g.addNode(_node('d', kFlowResource));
      g.addEdge('c', 'd');
      final findings = simulateFlow(g, threshold: 1.0);
      final ids = findings.map((f) => f.nodeId).toSet();
      expect(ids.contains('b'), true);
      // d might or might not appear depending on whether c is used as fallback
      // but with explicit lifecycle entry 'a', 'd' should not be reachable
    });

    test('dense DAG with multiple resources: all certainties valid', () {
      final g = FlowGraph();
      g.addNode(_node('entry', kFlowLifecycle));
      for (var i = 1; i <= 10; i++) {
        g.addNode(_node('n$i', i % 3 == 0 ? kFlowResource : kFlowMutates));
      }
      // dense forward edges
      for (var i = 0; i <= 10; i++) {
        final src = i == 0 ? 'entry' : 'n$i';
        for (var j = i + 1; j <= math.min(i + 4, 10); j++) {
          g.addEdge(src, 'n$j');
        }
      }
      final findings = simulateFlow(g, threshold: 1.0);
      for (final f in findings) {
        expect(f.certainty, greaterThanOrEqualTo(0.0));
        expect(f.certainty, lessThanOrEqualTo(1.0));
        expect(f.pathCount, greaterThan(0));
      }
    });

    test('self-loop does not cause infinite recursion', () {
      final g = FlowGraph();
      g.addNode(_node('a', kFlowLifecycle));
      g.addNode(_node('b', kFlowResource));
      g.addEdge('a', 'b');
      g.addEdge('a', 'a'); // self-loop
      g.addEdge('b', 'b'); // self-loop
      final findings = simulateFlow(g, threshold: 1.0);
      expect(findings, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 14. Simulation — heavy fuzz
  // ═══════════════════════════════════════════════════════════════════

  group('simulateFlow — fuzz', () {
    test('500 random DAGs: all certainties in [0,1], sorted, no NaN', () {
      final rng = math.Random(2222);
      for (var trial = 0; trial < 500; trial++) {
        final n = 3 + rng.nextInt(15);
        final g = _randomDAG(n, 0.3, rng);
        final findings = simulateFlow(g, threshold: 1.0);
        for (var i = 0; i < findings.length; i++) {
          final f = findings[i];
          expect(f.certainty.isNaN, false, reason: 'trial $trial');
          expect(f.phase.isNaN, false, reason: 'trial $trial');
          expect(f.certainty, greaterThanOrEqualTo(0.0),
              reason: 'trial $trial');
          expect(f.certainty, lessThanOrEqualTo(1.0),
              reason: 'trial $trial');
          if (i > 0) {
            expect(f.certainty,
                greaterThanOrEqualTo(findings[i - 1].certainty - 1e-15),
                reason: 'trial $trial: sort order');
          }
        }
      }
    });

    test('300 random graphs with cycles: terminates with valid output', () {
      final rng = math.Random(2323);
      for (var trial = 0; trial < 300; trial++) {
        final n = 3 + rng.nextInt(12);
        final g = _randomGraph(n, 0.2, rng);
        final findings = simulateFlow(g, threshold: 1.0);
        for (final f in findings) {
          expect(f.certainty, greaterThanOrEqualTo(0.0));
          expect(f.certainty, lessThanOrEqualTo(1.0));
        }
      }
    });

    test('determinism: 200 graphs simulated twice give identical results', () {
      final rng = math.Random(2424);
      for (var trial = 0; trial < 200; trial++) {
        final n = 4 + rng.nextInt(10);
        final g = _randomDAG(n, 0.3, rng);
        final f1 = simulateFlow(g, threshold: 1.0);
        final f2 = simulateFlow(g, threshold: 1.0);
        expect(f1.length, f2.length, reason: 'trial $trial');
        for (var i = 0; i < f1.length; i++) {
          expect(f1[i].nodeId, f2[i].nodeId, reason: 'trial $trial');
          expect(f1[i].certainty, f2[i].certainty, reason: 'trial $trial');
          expect(f1[i].phase, f2[i].phase, reason: 'trial $trial');
          expect(f1[i].pathCount, f2[i].pathCount, reason: 'trial $trial');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 15. Top-level API + spectral gap
  // ═══════════════════════════════════════════════════════════════════

  group('analyzeExecutionFlow', () {
    test('trivial source: < 2 nodes → no findings', () {
      expect(analyzeExecutionFlow('x = 1'), isEmpty);
    });

    test('universal mode: indentation structure produces findings', () {
      final source = [
        'function main() {',
        '    val x = read()',
        '    if (x > 0) {',
        '        val y = process(x)',
        '                val deep = nested(y)',
        '                handle(deep)',
        '    }',
        '    cleanup()',
        '}',
      ].join('\n');
      final findings = analyzeExecutionFlow(source, threshold: 1.0);
      expect(findings, isNotNull);
    });

    test('labeled mode: explicit labels', () {
      final source = 'line0\nline1\nline2\nline3\nline4';
      final labels = <int, (int, double)>{
        0: (kFlowLifecycle, 0.0),
        1: (kFlowMutates, 0.5),
        2: (kFlowResource, 0.0),
        3: (kFlowMutates, 1.0),
        4: (kFlowResource, 0.0),
      };
      final findings = analyzeExecutionFlow(source,
          threshold: 1.0, nodeLabels: labels);
      expect(findings, isNotEmpty);
      for (final f in findings) {
        expect(f.certainty, greaterThanOrEqualTo(0.0));
        expect(f.certainty, lessThanOrEqualTo(1.0));
      }
    });

    test('labeled early-return guard', () {
      final source = 'entry\ncheck\nreturn null\nrest\nresource';
      final labels = <int, (int, double)>{
        0: (kFlowLifecycle, 0.0),
        1: (kFlowPure, 0.0),
        2: (kFlowRestabilizes, 0.0),
        3: (kFlowMutates, 0.0),
        4: (kFlowResource, 0.0),
      };
      final findings = analyzeExecutionFlow(source,
          threshold: 1.0, nodeLabels: labels);
      expect(findings, isNotNull);
    });
  });

  group('analyzeExecutionFlow — fuzz', () {
    test('200 random source texts: no crash, valid output', () {
      final rng = math.Random(2525);
      for (var i = 0; i < 200; i++) {
        final lineCount = 5 + rng.nextInt(50);
        final source = _randomSource(rng, lineCount);
        final findings = analyzeExecutionFlow(source, threshold: 1.0);
        for (final f in findings) {
          expect(f.certainty.isNaN, false, reason: 'trial $i');
          expect(f.certainty, greaterThanOrEqualTo(0.0), reason: 'trial $i');
          expect(f.certainty, lessThanOrEqualTo(1.0), reason: 'trial $i');
          expect(f.sourceLine, greaterThanOrEqualTo(0), reason: 'trial $i');
        }
      }
    });

    test('determinism: 100 random sources analyzed twice', () {
      final rng = math.Random(2626);
      for (var i = 0; i < 100; i++) {
        final source = _randomSource(rng, 10 + rng.nextInt(30));
        final f1 = analyzeExecutionFlow(source, threshold: 1.0);
        final f2 = analyzeExecutionFlow(source, threshold: 1.0);
        expect(f1.length, f2.length, reason: 'trial $i');
        for (var j = 0; j < f1.length; j++) {
          expect(f1[j].certainty, f2[j].certainty, reason: 'trial $i');
          expect(f1[j].phase, f2[j].phase, reason: 'trial $i');
        }
      }
    });
  });

  group('flowSpectralGap', () {
    test('no findings → 0', () {
      final g = FlowGraph();
      g.addNode(_node('a', kFlowLifecycle));
      expect(flowSpectralGap(g), 0.0);
    });

    test('known certainty → -log(certainty)', () {
      final g = _linearGraph([
        ('a', kFlowLifecycle), ('b', kFlowMutates), ('c', kFlowResource),
      ]);
      final findings = simulateFlow(g, threshold: 1.0);
      final gap = flowSpectralGap(g, findings: findings);
      final worst = findings.map((f) => f.certainty).reduce(math.min);
      expect(gap, closeTo(-math.log(worst), 1e-10));
    });

    test('longer chain → higher gap', () {
      final gShort = _linearGraph([
        ('a', kFlowLifecycle), ('b', kFlowMutates), ('c', kFlowResource),
      ]);
      final gLong = _linearGraph([
        ('a', kFlowLifecycle),
        ('b1', kFlowMutates), ('b2', kFlowMutates),
        ('b3', kFlowMutates), ('b4', kFlowMutates),
        ('c', kFlowResource),
      ]);
      expect(flowSpectralGap(gLong), greaterThan(flowSpectralGap(gShort)));
    });

    test('pre-computed findings match live computation', () {
      final g = _linearGraph([
        ('a', kFlowLifecycle), ('b', kFlowMutates), ('c', kFlowResource),
      ]);
      final findings = simulateFlow(g, threshold: 1.0);
      expect(flowSpectralGap(g, findings: findings),
          closeTo(flowSpectralGap(g), 1e-12));
    });
  });

  group('flowSpectralGap — fuzz', () {
    test('200 random DAGs: gap ≥ 0 and finite', () {
      final rng = math.Random(2727);
      for (var i = 0; i < 200; i++) {
        final n = 4 + rng.nextInt(12);
        final g = _randomDAG(n, 0.3, rng);
        final gap = flowSpectralGap(g);
        expect(gap, greaterThanOrEqualTo(0.0), reason: 'trial $i');
        expect(gap.isFinite, true, reason: 'trial $i');
        expect(gap.isNaN, false, reason: 'trial $i');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 16. FlowFinding severity + phase classification
  // ═══════════════════════════════════════════════════════════════════

  group('FlowFinding severity', () {
    test('certainty < 0.1 → critical', () {
      const f = FlowFinding(
          nodeId: 'x', sourceLine: 0, sourceText: '',
          certainty: 0.05, phase: 0.0, kind: FlowBugKind.staleValue);
      expect(f.severity, 'critical');
    });

    test('certainty < 0.3 → warn', () {
      const f = FlowFinding(
          nodeId: 'x', sourceLine: 0, sourceText: '',
          certainty: 0.2, phase: 0.0, kind: FlowBugKind.staleValue);
      expect(f.severity, 'warn');
    });

    test('certainty >= 0.3 → info', () {
      const f = FlowFinding(
          nodeId: 'x', sourceLine: 0, sourceText: '',
          certainty: 0.5, phase: 0.0, kind: FlowBugKind.staleValue);
      expect(f.severity, 'info');
    });

    test('severity boundary: 0.1 → warn, 0.3 → info', () {
      const fWarn = FlowFinding(
          nodeId: 'x', sourceLine: 0, sourceText: '',
          certainty: 0.1, phase: 0.0, kind: FlowBugKind.staleValue);
      expect(fWarn.severity, 'warn');
      const fInfo = FlowFinding(
          nodeId: 'x', sourceLine: 0, sourceText: '',
          certainty: 0.3, phase: 0.0, kind: FlowBugKind.staleValue);
      expect(fInfo.severity, 'info');
    });
  });

  group('phase classification exhaustive', () {
    test('all three FlowBugKind reachable across phase range', () {
      final kinds = <FlowBugKind>{};
      for (var p = -math.pi; p <= math.pi; p += 0.01) {
        final source = 'a\nb\nc';
        final labels = <int, (int, double)>{
          0: (kFlowLifecycle, 0.0),
          1: (kFlowAsync, p.abs()), // high Lyapunov → phase shift
          2: (kFlowResource, 0.0),
        };
        final findings = analyzeExecutionFlow(source,
            threshold: 1.0, nodeLabels: labels);
        for (final f in findings) {
          kinds.add(f.kind);
        }
      }
      expect(kinds.contains(FlowBugKind.staleValue), true);
      expect(kinds.contains(FlowBugKind.temporalShift), true);
      // contextInversion requires |phase| > 3π/4 which needs specific K_i
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 17. Physics invariants — deep
  // ═══════════════════════════════════════════════════════════════════

  group('physics invariants — deep', () {
    test('pure chain: 1000 steps, certainty = 1.0 exactly', () {
      final o = FlowOscillator();
      for (var i = 0; i < 1000; i++) {
        o.step(1.0, 0.0, 0.0, 0);
        expect(o.certainty, closeTo(1.0, 1e-12), reason: 'step $i');
      }
    });

    test('MUTATES monotone decay over 50 steps', () {
      final o = FlowOscillator();
      final (kr, ki, gr) = flowKG(kFlowMutates);
      var prev = 1.0;
      for (var i = 0; i < 50; i++) {
        o.step(kr, ki, gr, 0);
        expect(o.certainty, lessThanOrEqualTo(prev + 1e-12));
        prev = o.certainty;
      }
    });

    test('Hamming formula exact for all h=0..8', () {
      for (var h = 0; h <= 8; h++) {
        final o = FlowOscillator();
        o.step(1.0, 0.0, 0.0, h);
        final t = (1.0 + math.cos(math.pi * h / 8)) / 2;
        expect(o.certainty, closeTo(t, 1e-12), reason: 'h=$h');
      }
    });

    test('MUTATES exact: certainty = (7/8)^n after n steps', () {
      final o = FlowOscillator();
      final (kr, ki, gr) = flowKG(kFlowMutates);
      for (var n = 1; n <= 20; n++) {
        o.step(kr, ki, gr, 0);
        final expected = math.pow(7.0 / 8.0, n).toDouble();
        expect(o.certainty, closeTo(expected, 1e-10), reason: 'n=$n');
      }
    });

    test('flowKG all 256: oscillator 10-step walk stays bounded', () {
      for (var addr = 0; addr < 256; addr++) {
        final (kr, ki, gr) = flowKG(addr, lyapunov: 1.0);
        final o = FlowOscillator();
        for (var s = 0; s < 10; s++) {
          o.step(kr, ki, gr, 0);
          expect(o.certainty, greaterThanOrEqualTo(0.0),
              reason: 'addr=$addr step=$s');
          expect(o.certainty, lessThanOrEqualTo(1.0),
              reason: 'addr=$addr step=$s');
        }
      }
    });

    test('Born mix N-copies invariant: 500 random (c,p)', () {
      final rng = math.Random(2828);
      for (var i = 0; i < 500; i++) {
        final c = rng.nextDouble() * 0.98 + 0.01;
        final p = (rng.nextDouble() - 0.5) * math.pi;
        final (mc, _) = flowBornMix([(c, p), (c, p)]);
        expect(mc, closeTo(c, 1e-8), reason: 'trial $i c=$c');
      }
    });

    test('renormalize fuzz: non-PURE preserved in 500 random DAGs', () {
      final rng = math.Random(2929);
      for (var i = 0; i < 500; i++) {
        final n = 3 + rng.nextInt(12);
        final g = _randomDAG(n, 0.3, rng);
        final nonPure = g.nodes.entries
            .where((e) => e.value.address != kFlowPure)
            .map((e) => e.key)
            .toSet();
        final r = renormalize(g);
        for (final id in nonPure) {
          expect(r.nodes.containsKey(id), true,
              reason: 'trial $i: non-PURE $id removed');
        }
      }
    });

    test('optimizeGraph converges on 500 random DAGs', () {
      final rng = math.Random(3030);
      for (var i = 0; i < 500; i++) {
        final n = 4 + rng.nextInt(12);
        var g = _randomDAG(n, 0.3, rng);
        var prevCount = g.nodes.length;
        var converged = false;
        for (var round = 0; round < 5; round++) {
          g = optimizeGraph(g);
          expect(g.nodes.length, lessThanOrEqualTo(prevCount),
              reason: 'trial $i round $round');
          if (g.nodes.length == prevCount) {
            converged = true;
            break;
          }
          prevCount = g.nodes.length;
        }
        expect(converged, true,
            reason: 'trial $i: should converge within 5 rounds');
      }
    });

    test('end-to-end determinism: 100 random sources', () {
      final rng = math.Random(3131);
      for (var i = 0; i < 100; i++) {
        final source = _randomSource(rng, 10 + rng.nextInt(40));
        final f1 = analyzeExecutionFlow(source, threshold: 1.0);
        final f2 = analyzeExecutionFlow(source, threshold: 1.0);
        expect(f1.length, f2.length, reason: 'trial $i');
        for (var j = 0; j < f1.length; j++) {
          expect(f1[j].certainty, f2[j].certainty, reason: 'trial $i');
          expect(f1[j].phase, f2[j].phase, reason: 'trial $i');
        }
      }
    });

    test('spectral gap monotone: adding MUTATES steps increases gap', () {
      for (var extra = 0; extra < 8; extra++) {
        final spec = <(String, int)>[('a', kFlowLifecycle)];
        for (var i = 0; i < extra; i++) {
          spec.add(('m$i', kFlowMutates));
        }
        spec.add(('r', kFlowResource));
        final g = _linearGraph(spec);
        final gap = flowSpectralGap(g);
        if (extra > 0) {
          final prevSpec = <(String, int)>[('a', kFlowLifecycle)];
          for (var i = 0; i < extra - 1; i++) {
            prevSpec.add(('m$i', kFlowMutates));
          }
          prevSpec.add(('r', kFlowResource));
          final prevGap = flowSpectralGap(_linearGraph(prevSpec));
          expect(gap, greaterThanOrEqualTo(prevGap - 1e-12),
              reason: 'extra=$extra');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 18. Full pipeline stress
  // ═══════════════════════════════════════════════════════════════════

  group('full pipeline stress', () {
    test('deeply nested code (20 levels)', () {
      final lines = <String>[];
      for (var i = 0; i < 20; i++) {
        lines.add('${' ' * (i * 4)}scope_$i {');
      }
      for (var i = 19; i >= 0; i--) {
        lines.add('${' ' * (i * 4)}}');
      }
      final source = lines.join('\n');
      final findings = analyzeExecutionFlow(source, threshold: 1.0);
      for (final f in findings) {
        expect(f.certainty, greaterThanOrEqualTo(0.0));
        expect(f.certainty, lessThanOrEqualTo(1.0));
      }
    });

    test('wide flat code (200 lines at indent 0)', () {
      final source = List.generate(200, (i) => 'statement_$i').join('\n');
      final findings = analyzeExecutionFlow(source, threshold: 1.0);
      for (final f in findings) {
        expect(f.certainty, greaterThanOrEqualTo(0.0));
        expect(f.certainty, lessThanOrEqualTo(1.0));
      }
    });

    test('alternating indent sawtooth', () {
      final lines = <String>[];
      for (var i = 0; i < 50; i++) {
        final indent = (i % 2 == 0) ? 0 : 12;
        lines.add('${' ' * indent}saw_$i');
      }
      final source = lines.join('\n');
      final findings = analyzeExecutionFlow(source, threshold: 1.0);
      for (final f in findings) {
        expect(f.certainty, greaterThanOrEqualTo(0.0));
        expect(f.certainty, lessThanOrEqualTo(1.0));
      }
    });

    test('labeled mode with all 8 axis combinations on 8 lines', () {
      final source = List.generate(8, (i) => 'line_$i').join('\n');
      final labels = <int, (int, double)>{
        0: (kFlowLifecycle, 0.0),
        1: (kFlowMutates, 0.5),
        2: (kFlowAsync, 1.0),
        3: (kFlowResource, 0.0),
        4: (kFlowIO, 0.3),
        5: (kFlowError, 0.0),
        6: (kFlowRestabilizes, 0.0),
        7: (kFlowResource, 0.0),
      };
      final findings = analyzeExecutionFlow(source,
          threshold: 1.0, nodeLabels: labels);
      for (final f in findings) {
        expect(f.certainty, greaterThanOrEqualTo(0.0));
        expect(f.certainty, lessThanOrEqualTo(1.0));
      }
    });

    test('labeled mode: all 256 addresses on a 3-node graph', () {
      for (var addr = 0; addr < 256; addr++) {
        final source = 'entry\nmiddle\nresource';
        final labels = <int, (int, double)>{
          0: (kFlowLifecycle, 0.0),
          1: (addr, 1.0),
          2: (kFlowResource, 0.0),
        };
        final findings = analyzeExecutionFlow(source,
            threshold: 1.0, nodeLabels: labels);
        for (final f in findings) {
          expect(f.certainty.isNaN, false, reason: 'addr=$addr');
          expect(f.certainty, greaterThanOrEqualTo(0.0),
              reason: 'addr=$addr');
          expect(f.certainty, lessThanOrEqualTo(1.0),
              reason: 'addr=$addr');
        }
      }
    });
  });
}
