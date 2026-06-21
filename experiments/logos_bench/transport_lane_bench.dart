// transport_lane_bench.dart — clean same-process A/B of the transport-lane
// fast path. The scoreLoop reads only `.strength`; the witness object
// (LogosTransportLane, 5 fields) was allocated per call, fwd+rev, per scored
// pair. This times the witness-object path (`logosTransportLaneOfRoles(a,b).strength`)
// vs the allocation-free `logosTransportLaneStrengthOfRoles(a,b)` on the SAME
// roles in one process, and asserts bit-identical strengths.
//
//   run:  dart --packages=experiments/logos_bench/package_config.json experiments/logos_bench/transport_lane_bench.dart

import 'dart:io';
import 'dart:typed_data';

import '../../apps/desktop-flutter/lib/backend/logos_git_integrity.dart';

List<String> _realisticPaths(int dirs) {
  final out = <String>[];
  for (var d = 0; d < dirs; d++) {
    final dir = 'lib/feature$d';
    out.add('$dir/widget$d.dart'); // source
    out.add('$dir/widget${d}_test.dart'); // test
    out.add('$dir/widget$d.g.dart'); // generated
    out.add('$dir/README.md'); // doc
    if (d % 5 == 0) out.add('$dir/fixtures/data$d.json'); // fixture
    if (d % 7 == 0) out.add('migrations/$d.sql'); // migration
  }
  out.add('pubspec.yaml'); // manifest
  out.add('pubspec.lock'); // lockfile
  out.add('.github/workflows/ci.yml'); // ci-config
  return out;
}

void main() {
  final paths = _realisticPaths(90); // ~400 paths spanning every role
  final roles = [for (final p in paths) TransportRoles.of(p)];
  final cc = CouplingConstants.prior;
  final n = roles.length;
  stdout.writeln('=== transport-lane A/B  (witness-object vs strength-only) ===');
  stdout.writeln('dart ${Platform.version.split(' ').first}   roles=$n   pairs/trial=${n * n} (fwd+rev)');

  // ── fidelity: strength-only == object.strength for every ordered pair ──
  var mismatches = 0, lanesFired = 0;
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      final obj = logosTransportLaneOfRoles(roles[i], roles[j], cc);
      final objStr = obj?.strength ?? 0.0;
      final fast = logosTransportLaneStrengthOfRoles(roles[i], roles[j], cc);
      if (objStr != 0.0) lanesFired++;
      if (_dbits(objStr) != _dbits(fast)) mismatches++;
    }
  }
  stdout.writeln('  fidelity: ${mismatches == 0 ? "BIT-IDENTICAL ✓" : "MISMATCH ✗ ($mismatches)"}'
      '   (lanes fired: $lanesFired / ${n * n})');

  // ── timing: warmup then median of trials ──
  double timeIt(double Function() body, int trials) {
    body();
    body(); // warmup (JIT)
    final us = <int>[];
    for (var t = 0; t < trials; t++) {
      final sw = Stopwatch()..start();
      final v = body();
      sw.stop();
      if (v.isNaN) stdout.write(''); // keep the optimizer honest
      us.add(sw.elapsedMicroseconds);
    }
    us.sort();
    return us[us.length ~/ 2] / 1000.0;
  }

  double objPass() {
    var acc = 0.0;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final lane = logosTransportLaneOfRoles(roles[i], roles[j], cc);
        if (lane != null && lane.strength > 0) acc += lane.strength;
      }
    }
    return acc;
  }

  double fastPass() {
    var acc = 0.0;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final s = logosTransportLaneStrengthOfRoles(roles[i], roles[j], cc);
        if (s > 0) acc += s;
      }
    }
    return acc;
  }

  // sanity: both passes sum to the same accumulator
  final accObj = objPass();
  final accFast = fastPass();
  stdout.writeln('  accumulator equal: ${_dbits(accObj) == _dbits(accFast) ? "✓" : "✗"}');

  const trials = 25;
  final mObj = timeIt(objPass, trials);
  final mFast = timeIt(fastPass, trials);
  stdout.writeln('  witness-object : ${mObj.toStringAsFixed(3)} ms / full ${n}² sweep (median of $trials)');
  stdout.writeln('  strength-only  : ${mFast.toStringAsFixed(3)} ms');
  stdout.writeln('  speedup        : ${(mObj / mFast).toStringAsFixed(2)}x   (${mObj > mFast ? "faster" : "SLOWER"})');
  stdout.writeln('  saved/sweep    : ${(mObj - mFast).toStringAsFixed(3)} ms  '
      '(${((mObj - mFast) / mObj * 100).toStringAsFixed(0)}% of the lane cost)');
}

String _dbits(double v) {
  final b = ByteData(8)..setFloat64(0, v);
  return b.getUint64(0).toRadixString(16);
}
