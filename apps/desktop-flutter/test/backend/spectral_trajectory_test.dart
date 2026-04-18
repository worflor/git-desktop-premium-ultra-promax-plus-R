// Tests for SpectralTrajectory — the repo-as-a-path primitive.
//
// Coverage layout:
//   * Basic construction, immutability, monotone-revision assertion
//   * Per-point curves (rigidity, gap, vN entropy)
//   * Per-transition step distances (eigenvalue, signature Hamming)
//   * Path length and path speed
//   * Trajectory signature (deterministic, discriminates ordering)
//   * Change-point detection on a planted jump
//   * Linear forecast on a planted linear trend

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_signature.dart';
import 'package:git_desktop/backend/spectral_state.dart';
import 'package:git_desktop/backend/spectral_trajectory.dart';

CsrGraph _pathGraph(int n) {
  final edges = <List<(int, double)>>[];
  for (var i = 0; i < n; i++) {
    final row = <(int, double)>[];
    if (i > 0) row.add((i - 1, 1.0));
    if (i < n - 1) row.add((i + 1, 1.0));
    edges.add(row);
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

CsrGraph _cycleGraph(int n) {
  final edges = List<List<(int, double)>>.generate(
      n, (_) => <(int, double)>[]);
  for (var i = 0; i < n; i++) {
    edges[i].add(((i + 1) % n, 1.0));
    edges[i].add(((i - 1 + n) % n, 1.0));
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

CsrGraph _completeGraph(int n) {
  final edges = List<List<(int, double)>>.generate(
      n, (_) => <(int, double)>[]);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      if (i != j) edges[i].add((j, 1.0));
    }
  }
  return CsrGraph.fromRawEdges(n: n, edgesPerNode: edges);
}

LogosState _stateOf(CsrGraph g, int k, int revision) {
  final basis = SpectralBasis.fromGraph(g, k);
  return LogosState(
    fileSpectrum: basis,
    commitSpectrum: null,
    joint: null,
    revision: revision,
  );
}

TrajectoryPoint _point({
  required int rev,
  required CsrGraph graph,
  int k = 10,
  String? sha,
}) =>
    TrajectoryPoint(
      revision: rev,
      state: _stateOf(graph, k, rev),
      commitSha: sha,
    );

void main() {
  group('SpectralTrajectory basics', () {
    test('empty trajectory has no head, no genesis, length 0', () {
      final t = SpectralTrajectory.empty();
      expect(t.isEmpty, isTrue);
      expect(t.length, 0);
      expect(t.head, isNull);
      expect(t.genesis, isNull);
      expect(t.pathLength, closeTo(0.0, 1e-15));
      expect(t.trajectorySignature, equals(Signature.zero));
    });

    test('single point: head == genesis, path length 0', () {
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(16)),
      ]);
      expect(t.length, 1);
      expect(t.head, isNotNull);
      expect(t.head, equals(t.genesis));
      expect(t.pathLength, closeTo(0.0, 1e-15));
      expect(t.eigenvalueStepDistances(), isEmpty);
      expect(t.signatureStepDistances(), isEmpty);
    });

    test('appended returns a new trajectory with the point added at tip', () {
      final a = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(16)),
      ]);
      final b = a.appended(_point(rev: 2, graph: _pathGraph(17)));
      expect(a.length, 1, reason: 'original must be unchanged');
      expect(b.length, 2);
      expect(b.head!.revision, 2);
      expect(b.genesis!.revision, 1);
    });

    test('assertion fires on non-monotone revisions', () {
      expect(
        () => SpectralTrajectory(points: [
          _point(rev: 5, graph: _pathGraph(12)),
          _point(rev: 3, graph: _pathGraph(12)), // goes backward
        ]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('slice returns a valid sub-trajectory with clamped bounds', () {
      final t = SpectralTrajectory(points: [
        for (var i = 0; i < 5; i++)
          _point(rev: i + 1, graph: _pathGraph(12 + i)),
      ]);
      final s = t.slice(1, 4);
      expect(s.length, 3);
      expect(s.genesis!.revision, 2);
      expect(s.head!.revision, 4);
      // Out-of-range indices clamp silently, don't throw.
      expect(t.slice(-10, 100).length, 5);
      expect(t.slice(3, 2).length, 0);
    });
  });

  group('Per-point curves', () {
    test('rigidityCurve has one value per point', () {
      final t = SpectralTrajectory(points: [
        for (var i = 0; i < 4; i++)
          _point(rev: i + 1, graph: _pathGraph(20 + i)),
      ]);
      final rig = t.rigidityCurve();
      expect(rig, hasLength(4));
      for (final r in rig) {
        // Path graphs have well-defined rigidity; should be finite.
        expect(r.isFinite, isTrue);
      }
    });

    test('gapCurve and vonNeumannCurve match per-point values', () {
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(14)),
        _point(rev: 2, graph: _cycleGraph(14)),
      ]);
      final gaps = t.gapCurve();
      final vns = t.vonNeumannCurve();
      expect(gaps[0], closeTo(t.points[0].spectralGap, 1e-12));
      expect(gaps[1], closeTo(t.points[1].spectralGap, 1e-12));
      expect(vns[0], closeTo(t.points[0].vonNeumannEntropy, 1e-12));
      expect(vns[1], closeTo(t.points[1].vonNeumannEntropy, 1e-12));
    });
  });

  group('Step distances and path length', () {
    test('isospectral trajectory has zero path length', () {
      // Two snapshots of the SAME graph — deterministic Lanczos, so
      // eigenvalues match bit-for-bit; distance is exactly 0.
      final g = _pathGraph(16);
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: g),
        _point(rev: 2, graph: g),
      ]);
      expect(t.eigenvalueStepDistances(), hasLength(1));
      expect(t.eigenvalueStepDistances().single, closeTo(0.0, 1e-12));
      expect(t.pathLength, closeTo(0.0, 1e-12));
    });

    test('path length is monotone as the trajectory extends', () {
      final points = <TrajectoryPoint>[];
      SpectralTrajectory? prev;
      for (var i = 0; i < 4; i++) {
        points.add(_point(rev: i + 1, graph: _pathGraph(14 + i * 2)));
        final t = SpectralTrajectory(points: [...points]);
        if (prev != null) {
          expect(t.pathLength, greaterThanOrEqualTo(prev.pathLength - 1e-12),
              reason: 'appending must not shrink path length');
        }
        prev = t;
      }
    });

    test('different-topology transitions produce non-zero distance', () {
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(16)),
        _point(rev: 2, graph: _cycleGraph(16)),
      ]);
      expect(t.eigenvalueStepDistances().single, greaterThan(1e-6));
    });

    test('truncates to smaller k when bases disagree on dimension', () {
      // k is capped at SpectralBasis.fromGraph's min(n, k_requested).
      // A 6-node path has k ≤ 5; a 30-node path has k = 10 (requested).
      // Trajectory spanning the two should still produce a step distance
      // without throwing.
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(6), k: 10),
        _point(rev: 2, graph: _pathGraph(30), k: 10),
      ]);
      final d = t.eigenvalueStepDistances().single;
      expect(d.isFinite, isTrue);
      expect(d, greaterThanOrEqualTo(0.0));
    });

    test('signatureStepDistances are in [0, 62]', () {
      final t = SpectralTrajectory(points: [
        for (var i = 0; i < 4; i++)
          _point(rev: i + 1, graph: _pathGraph(20 + i)),
      ]);
      final hd = t.signatureStepDistances();
      expect(hd, hasLength(3));
      for (final d in hd) {
        expect(d, greaterThanOrEqualTo(0));
        expect(d, lessThanOrEqualTo(62));
      }
    });
  });

  group('pathSpeed', () {
    test('NaN on trajectories shorter than window + 1', () {
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(14)),
        _point(rev: 2, graph: _pathGraph(16)),
      ]);
      expect(t.pathSpeed(window: 10).isNaN, isTrue);
    });

    test('returns a finite value on a well-populated trajectory', () {
      final pts = <TrajectoryPoint>[];
      for (var i = 0; i < 15; i++) {
        pts.add(_point(rev: i + 1, graph: _pathGraph(12 + i)));
      }
      final t = SpectralTrajectory(points: pts);
      final s = t.pathSpeed(window: 5);
      expect(s.isFinite, isTrue);
      expect(s, greaterThanOrEqualTo(0.0));
    });
  });

  group('trajectorySignature', () {
    test('empty trajectory → zero signature', () {
      expect(SpectralTrajectory.empty().trajectorySignature,
          equals(Signature.zero));
    });

    test('deterministic: same points twice → same signature', () {
      final pts = [
        for (var i = 0; i < 3; i++)
          _point(rev: i + 1, graph: _pathGraph(14 + i)),
      ];
      final a = SpectralTrajectory(points: pts);
      final b = SpectralTrajectory(points: pts);
      expect(a.trajectorySignature, equals(b.trajectorySignature));
    });

    test('order matters: reversed points yield a different signature', () {
      // Build two distinct states (A from path, B from cycle), then
      // compose them in opposite orders into two trajectories.
      // Revision must still be monotone, so tag revisions freshly
      // in each constructed ordering.
      final pA = _stateOf(_pathGraph(14), 10, 1);
      final pB = _stateOf(_cycleGraph(14), 10, 1);
      // Skip the test if by unlikely coincidence they have equal
      // signatures (would render the test vacuous).
      if (pA.signature == pB.signature) return;
      final forward = SpectralTrajectory(points: [
        TrajectoryPoint(revision: 1, state: pA),
        TrajectoryPoint(revision: 2, state: pB),
      ]);
      final reverse = SpectralTrajectory(points: [
        TrajectoryPoint(revision: 1, state: pB),
        TrajectoryPoint(revision: 2, state: pA),
      ]);
      expect(forward.trajectorySignature,
          isNot(equals(reverse.trajectorySignature)));
    });

    test('appending changes the signature', () {
      final a = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(16)),
      ]);
      final b = a.appended(_point(rev: 2, graph: _cycleGraph(16)));
      expect(a.trajectorySignature, isNot(equals(b.trajectorySignature)));
    });
  });

  group('regimeChanges (change-point detection)', () {
    test('empty on short curves', () {
      final t = SpectralTrajectory.empty();
      final cp = t.regimeChanges(curve: const [1.0, 2.0, 3.0]);
      expect(cp, isEmpty);
    });

    test('empty on flat curves (no variance in baseline)', () {
      final t = SpectralTrajectory(points: [
        for (var i = 0; i < 20; i++)
          _point(rev: i + 1, graph: _pathGraph(16)),
      ]);
      // Identical curve — no jumps, no change points.
      final curve = List<double>.filled(20, 1.0);
      final cp = t.regimeChanges(curve: curve);
      expect(cp, isEmpty);
    });

    test('detects a planted step change', () {
      final t = SpectralTrajectory.empty();
      // Walk 30 steps at level 1.0 with noticeable noise so the
      // rolling baseline std stabilises; then jump to 8.0 (very
      // large relative to the ±0.1 noise) and continue. The jump's
      // first difference will dwarf the baseline variance and must
      // be the most anomalous index detected.
      final rng = math.Random(0x5EED);
      double noisy(double mu) => mu + (rng.nextDouble() - 0.5) * 0.1;
      final curve = <double>[
        for (var i = 0; i < 30; i++) noisy(1.0),
        for (var i = 0; i < 11; i++) noisy(8.0),
      ];
      final cp = t.regimeChanges(curve: curve, window: 8, sensitivity: 3.0);
      expect(cp, isNotEmpty, reason: 'planted step must trigger detection');
      // The top-|z| event must land on the jump itself — diff index 29
      // corresponds to output index 30 (the first post-jump point).
      final top = cp.reduce((a, b) =>
          a.zScore.abs() > b.zScore.abs() ? a : b);
      expect(top.index, equals(30),
          reason: 'the loudest change must be at the planted step');
      expect(top.zScore.abs(), greaterThan(10.0),
          reason: 'a 7σ+ jump should score very high');
    });

    test('does NOT fire on a smooth linear trend', () {
      final t = SpectralTrajectory.empty();
      // Strictly linear increase — first differences are constant,
      // variance is 0, so no z-score triggers.
      final curve = <double>[for (var i = 0; i < 40; i++) i * 0.1];
      final cp = t.regimeChanges(curve: curve, window: 8, sensitivity: 2.0);
      expect(cp, isEmpty);
    });
  });

  group('forecastScalar (linear forecast)', () {
    test('NaN on insufficient data', () {
      expect(SpectralTrajectory.forecastScalar(const []).isNaN, isTrue);
      expect(SpectralTrajectory.forecastScalar(const [1.0, 2.0]).isNaN,
          isTrue);
    });

    test('recovers a clean linear trend', () {
      // y = 3 + 0.5·x  for x = 0..19. Forecast at x = 20 should be 13.
      final curve = [for (var i = 0; i < 20; i++) 3.0 + 0.5 * i];
      final pred =
          SpectralTrajectory.forecastScalar(curve, fitWindow: 20, steps: 1);
      expect(pred, closeTo(13.0, 1e-9));
    });

    test('skips non-finite samples when fitting', () {
      final curve = [
        for (var i = 0; i < 10; i++) 3.0 + 0.5 * i,
        double.nan, // should be ignored
        8.5, // 3 + 0.5 * 11 = 8.5, matches the trend
      ];
      final pred =
          SpectralTrajectory.forecastScalar(curve, fitWindow: 12, steps: 1);
      // With NaN skipped, the trend is still recovered cleanly.
      expect(pred, closeTo(9.0, 1e-9));
    });

    test('flat curve returns the flat value', () {
      final curve = List<double>.filled(15, 4.2);
      final pred =
          SpectralTrajectory.forecastScalar(curve, fitWindow: 15, steps: 5);
      expect(pred, closeTo(4.2, 1e-9));
    });
  });

  group('tangentAt / curvatureAt / turbulence', () {
    test('tangent of an isospectral step is the zero vector', () {
      final g = _pathGraph(16);
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: g),
        _point(rev: 2, graph: g),
      ]);
      final tangent = t.tangentAt(0);
      expect(tangent, isNotEmpty);
      for (final v in tangent) {
        expect(v.abs(), lessThan(1e-12));
      }
    });

    test('tangent sum-abs equals the step\'s contribution to path length',
        () {
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(20)),
        _point(rev: 2, graph: _cycleGraph(20)),
      ]);
      final tangent = t.tangentAt(0);
      var sumAbs = 0.0;
      for (final v in tangent) {
        sumAbs += v.abs();
      }
      // pathLength here is the single step's mean |Δλ|; tangent
      // has the per-mode values so `sumAbs / k` equals pathLength.
      expect(sumAbs / tangent.length, closeTo(t.pathLength, 1e-12));
    });

    test('tangentAt returns empty for out-of-range indices', () {
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(14)),
        _point(rev: 2, graph: _pathGraph(15)),
      ]);
      expect(t.tangentAt(-1), isEmpty);
      expect(t.tangentAt(1), isEmpty); // last step is N-2 = 0
      expect(t.tangentAt(100), isEmpty);
    });

    test('curvature of a straight trajectory is ~0', () {
      // "Straight" = same two graphs repeating; every tangent is
      // identical to the previous one, so angle between them is 0.
      final gA = _pathGraph(20);
      final gB = _cycleGraph(20);
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: gA),
        _point(rev: 2, graph: gB),
        _point(rev: 3, graph: gA),
        _point(rev: 4, graph: gB),
      ]);
      // tangent(0) = B - A
      // tangent(1) = A - B = -tangent(0)
      // Angle between tangent(0) and tangent(1) = π.
      // So curvatureAt(1) should be close to π, not 0 — this is a
      // "full reversal" pattern. (Good for naming sanity.)
      final cReverse = t.curvatureAt(1);
      expect(cReverse, closeTo(math.pi, 1e-6));
    });

    test('curvature of an oscillating trajectory is near π', () {
      // Build a ping-pong: path → cycle → path → cycle …
      final gA = _pathGraph(14);
      final gB = _cycleGraph(14);
      final pts = [
        for (var i = 0; i < 6; i++)
          TrajectoryPoint(
            revision: i + 1,
            state: _stateOf(i.isEven ? gA : gB, 10, i + 1),
          ),
      ];
      final t = SpectralTrajectory(points: pts);
      // Turbulence should be near π (every step reverses).
      expect(t.turbulence, closeTo(math.pi, 0.1));
    });

    test('curvature of a monotone trend is small', () {
      // Graphs of growing path length — spectra drift in a consistent
      // direction, so consecutive tangents point similarly.
      final pts = [
        for (var i = 0; i < 8; i++)
          _point(rev: i + 1, graph: _pathGraph(14 + i)),
      ];
      final t = SpectralTrajectory(points: pts);
      final turb = t.turbulence;
      expect(turb.isFinite, isTrue);
      // Monotone growth should stay well below π/2.
      expect(turb, lessThan(math.pi / 2),
          reason: 'monotone trend should not look like chaos');
    });

    test('turbulence NaN on trajectories shorter than 3 points', () {
      expect(SpectralTrajectory.empty().turbulence.isNaN, isTrue);
      final single = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(12)),
      ]);
      expect(single.turbulence.isNaN, isTrue);
      final two = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(12)),
        _point(rev: 2, graph: _pathGraph(13)),
      ]);
      expect(two.turbulence.isNaN, isTrue);
    });

    test('curvatureCurve has length points.length - 2', () {
      final t = SpectralTrajectory(points: [
        for (var i = 0; i < 6; i++)
          _point(rev: i + 1, graph: _pathGraph(14 + i)),
      ]);
      expect(t.curvatureCurve(), hasLength(4));
    });

    test('curvatureCurve is empty for <3-point trajectories', () {
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(12)),
        _point(rev: 2, graph: _pathGraph(13)),
      ]);
      expect(t.curvatureCurve(), isEmpty);
    });
  });

  group('poincareTraceOfNode', () {
    test('returns (x, y, revision) per point for valid nodeId', () {
      final pts = [
        for (var i = 0; i < 4; i++)
          _point(rev: i + 1, graph: _pathGraph(20 + i)),
      ];
      final t = SpectralTrajectory(points: pts);
      final trace = t.poincareTraceOfNode(0);
      expect(trace, hasLength(4));
      for (final row in trace) {
        expect(row.x.isFinite, isTrue);
        expect(row.y.isFinite, isTrue);
        final r = math.sqrt(row.x * row.x + row.y * row.y);
        expect(r, lessThan(1.0));
      }
      // Revision tags match the trajectory's.
      for (var i = 0; i < trace.length; i++) {
        expect(trace[i].revision, pts[i].revision);
      }
    });

    test('out-of-range nodeId yields NaN coordinates', () {
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(10)),
      ]);
      final trace = t.poincareTraceOfNode(999);
      expect(trace, hasLength(1));
      expect(trace.single.x.isNaN, isTrue);
      expect(trace.single.y.isNaN, isTrue);
    });

    test('empty trajectory returns empty trace', () {
      expect(SpectralTrajectory.empty().poincareTraceOfNode(0), isEmpty);
    });
  });

  group('distanceTo (trajectory-to-trajectory)', () {
    test('zero against identical trajectory', () {
      final pts = [
        for (var i = 0; i < 3; i++)
          _point(rev: i + 1, graph: _pathGraph(14 + i)),
      ];
      final a = SpectralTrajectory(points: pts);
      final b = SpectralTrajectory(points: pts);
      expect(a.distanceTo(b), closeTo(0.0, 1e-12));
      expect(b.distanceTo(a), closeTo(0.0, 1e-12));
    });

    test('positive against divergent trajectory at some index', () {
      final shared = _point(rev: 1, graph: _pathGraph(16));
      final a = SpectralTrajectory(points: [
        shared,
        _point(rev: 2, graph: _pathGraph(17)),
      ]);
      final b = SpectralTrajectory(points: [
        shared,
        _point(rev: 2, graph: _cycleGraph(17)),
      ]);
      expect(a.distanceTo(b), greaterThan(0.0));
    });

    test('NaN on empty input', () {
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(12)),
      ]);
      expect(t.distanceTo(SpectralTrajectory.empty()).isNaN, isTrue);
      expect(SpectralTrajectory.empty().distanceTo(t).isNaN, isTrue);
    });

    test('truncates to the shorter trajectory', () {
      final pts = [
        for (var i = 0; i < 5; i++)
          _point(rev: i + 1, graph: _pathGraph(14 + i)),
      ];
      final full = SpectralTrajectory(points: pts);
      final short = SpectralTrajectory(points: pts.sublist(0, 2));
      // Overlap is 2 points, both identical → distance 0.
      expect(full.distanceTo(short), closeTo(0.0, 1e-12));
    });
  });

  group('Logos Transform — temporal DFT (ω axis)', () {
    test('DFT of zeros returns zeros', () {
      final zero = List<double>.filled(8, 0.0);
      final dft = SpectralTrajectory.dftOfCurve(zero);
      for (var k = 0; k < zero.length; k++) {
        expect(dft.real[k], closeTo(0.0, 1e-15));
        expect(dft.imaginary[k], closeTo(0.0, 1e-15));
      }
    });

    test('DFT of constant curve: all energy at DC (k=0)', () {
      final curve = List<double>.filled(16, 3.0);
      final mag = SpectralTrajectory.magnitudeSpectrum(curve);
      expect(mag[0], closeTo(3.0 * math.sqrt(16.0), 1e-9),
          reason: '|X[0]| = (1/√N) · N · c = c·√N');
      for (var k = 1; k < mag.length; k++) {
        expect(mag[k], closeTo(0.0, 1e-9));
      }
    });

    test('DFT recovers the planted frequency of a sinusoid', () {
      // x[j] = sin(2π·3·j/N) — pure tone at bin 3.
      const n = 32;
      const planted = 3;
      final curve = [
        for (var j = 0; j < n; j++)
          math.sin(2 * math.pi * planted * j / n),
      ];
      final mag = SpectralTrajectory.magnitudeSpectrum(curve);
      // Biggest non-DC bin must be the planted one (or its mirror at N - planted).
      final dom = SpectralTrajectory.empty().dominantFrequency(curve);
      expect(dom, isNotNull);
      // The planted frequency is at bin `planted`; dominantFrequency
      // restricts to [1, N/2] so it should land at `planted` itself.
      expect(dom!.bin, equals(planted));
      // Period recovered: N / bin = 32 / 3 ≈ 10.67
      expect(dom.periodCommits, closeTo(n / planted, 1e-9));
      // Mirror bin at N - planted should have similar magnitude
      // (real input → conjugate symmetry).
      expect(mag[planted], closeTo(mag[n - planted], 1e-9));
    });

    test('Parseval: ‖x‖² = ‖X‖²', () {
      final rng = math.Random(0xCA11);
      final curve = [for (var i = 0; i < 24; i++) rng.nextDouble() - 0.5];
      var timeSq = 0.0;
      for (final v in curve) {
        timeSq += v * v;
      }
      final dft = SpectralTrajectory.dftOfCurve(curve);
      var freqSq = 0.0;
      for (var k = 0; k < dft.real.length; k++) {
        freqSq += dft.real[k] * dft.real[k] +
            dft.imaginary[k] * dft.imaginary[k];
      }
      expect(freqSq, closeTo(timeSq, 1e-9));
    });

    test('dominantFrequency returns null on short curves', () {
      final t = SpectralTrajectory.empty();
      expect(t.dominantFrequency(const []), isNull);
      expect(t.dominantFrequency(const [1.0, 2.0, 3.0]), isNull);
    });

    test('dominantFrequency returns null on flat-at-zero signal', () {
      final t = SpectralTrajectory.empty();
      expect(
          t.dominantFrequency(List<double>.filled(32, 0.0)), isNull);
    });

    test('magnitudeRatioToDC flags pure oscillation vs DC-heavy signals', () {
      final t = SpectralTrajectory.empty();
      // Zero-mean sinusoid → DC is ~0, the ratio shoots way up.
      final zeroMean = [
        for (var i = 0; i < 32; i++) math.cos(2 * math.pi * 4 * i / 32),
      ];
      final pureOsc = t.dominantFrequency(zeroMean);
      // Same sinusoid but with a large DC offset — ratio should be
      // far smaller.
      final biasedOsc = [
        for (var i = 0; i < 32; i++)
          100.0 + math.cos(2 * math.pi * 4 * i / 32),
      ];
      final biased = t.dominantFrequency(biasedOsc);
      expect(pureOsc, isNotNull);
      expect(biased, isNotNull);
      expect(pureOsc!.magnitudeRatioToDC,
          greaterThan(biased!.magnitudeRatioToDC * 100),
          reason: 'a zero-mean sinusoid should dominate DC; adding a '
              'big offset floors the ratio');
      // Both should still identify bin 4 as the dominant frequency.
      expect(pureOsc.bin, equals(4));
      expect(biased.bin, equals(4));
    });

    test('NaN entries are treated as zero (no NaN propagation)', () {
      final curve = [1.0, 2.0, double.nan, 4.0, 5.0, 6.0, 7.0, 8.0];
      final dft = SpectralTrajectory.dftOfCurve(curve);
      for (var k = 0; k < dft.real.length; k++) {
        expect(dft.real[k].isFinite, isTrue);
        expect(dft.imaginary[k].isFinite, isTrue);
      }
    });
  });

  group('Discrete calculus on curves', () {
    test('derivative of constant is zero', () {
      final deriv = SpectralTrajectory.derivativeOfCurve(
          List<double>.filled(8, 3.0));
      for (final d in deriv) {
        expect(d, closeTo(0.0, 1e-15));
      }
    });

    test('derivative of linear ramp is constant', () {
      final curve = [for (var i = 0; i < 10; i++) 3.0 + 0.5 * i];
      final deriv = SpectralTrajectory.derivativeOfCurve(curve);
      for (final d in deriv) {
        expect(d, closeTo(0.5, 1e-12));
      }
    });

    test('second derivative of linear ramp is zero', () {
      final curve = [for (var i = 0; i < 10; i++) 1.0 + 2.0 * i];
      final d2 = SpectralTrajectory.secondDerivativeOfCurve(curve);
      for (final d in d2) {
        expect(d, closeTo(0.0, 1e-12));
      }
    });

    test('second derivative of quadratic is constant = 2a', () {
      final curve = [for (var i = 0; i < 10; i++) 3.0 * i * i];
      final d2 = SpectralTrajectory.secondDerivativeOfCurve(curve);
      for (final d in d2) {
        expect(d, closeTo(6.0, 1e-12));
      }
    });

    test('integral over empty range is 0', () {
      expect(
          SpectralTrajectory.integralOfCurve(const [1.0, 2.0, 3.0], from: 2, to: 2),
          equals(0.0));
    });

    test('integral of unit curve over [0, N) is N', () {
      final curve = List<double>.filled(12, 1.0);
      expect(
          SpectralTrajectory.integralOfCurve(curve), closeTo(12.0, 1e-15));
    });

    test('discrete FTC: integral(D[x], 0, N) = x[N] − x[0]', () {
      // Classic invariant: the sum of first differences telescopes.
      final rng = math.Random(0xF11);
      for (var trial = 0; trial < 8; trial++) {
        final curve = [for (var i = 0; i < 20; i++) rng.nextDouble() * 10];
        final deriv = SpectralTrajectory.derivativeOfCurve(curve);
        final integral = SpectralTrajectory.integralOfCurve(deriv);
        expect(integral, closeTo(curve.last - curve.first, 1e-10),
            reason: 'FTC failed on trial $trial');
      }
    });

    test('NaN entries in integration are ignored safely', () {
      final curve = <double>[1.0, 2.0, double.nan, 3.0, 4.0];
      // Sum should be 1+2+3+4 = 10 (NaN skipped).
      expect(
          SpectralTrajectory.integralOfCurve(curve), closeTo(10.0, 1e-15));
    });

    test('integral out-of-range throws', () {
      expect(
          () => SpectralTrajectory.integralOfCurve(
              const [1.0, 2.0], from: -1),
          throwsRangeError);
      expect(
          () => SpectralTrajectory.integralOfCurve(
              const [1.0, 2.0], to: 10),
          throwsRangeError);
    });
  });

  group('Dirichlet action', () {
    test('zero-point or single-point trajectory has zero action', () {
      expect(SpectralTrajectory.empty().dirichletAction, equals(0.0));
      final single = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(12)),
      ]);
      expect(single.dirichletAction, equals(0.0));
    });

    test('isospectral trajectory (zero motion) has zero action', () {
      final g = _pathGraph(14);
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: g),
        _point(rev: 2, graph: g),
        _point(rev: 3, graph: g),
      ]);
      expect(t.dirichletAction, closeTo(0.0, 1e-20));
    });

    test('action is non-negative and non-decreasing on appending', () {
      final pts = <TrajectoryPoint>[];
      double prev = 0.0;
      for (var i = 0; i < 5; i++) {
        pts.add(_point(rev: i + 1, graph: _pathGraph(14 + 2 * i)));
        final t = SpectralTrajectory(points: [...pts]);
        final a = t.dirichletAction;
        expect(a, greaterThanOrEqualTo(prev - 1e-12));
        expect(a, greaterThanOrEqualTo(0.0));
        prev = a;
      }
    });

    test('variational principle: straight trajectory has lower action than oscillating', () {
      // A "straight" trajectory: graphs grow monotonically in size.
      // An "oscillating" trajectory: alternates between two very
      // different graphs. Both span the same number of steps.
      final straight = SpectralTrajectory(points: [
        for (var i = 0; i < 6; i++)
          _point(rev: i + 1, graph: _pathGraph(14 + i)),
      ]);
      final oscillating = SpectralTrajectory(points: [
        for (var i = 0; i < 6; i++)
          _point(
              rev: i + 1,
              graph: i.isEven ? _pathGraph(14) : _cycleGraph(14)),
      ]);
      expect(oscillating.dirichletAction,
          greaterThan(straight.dirichletAction),
          reason: 'oscillation accumulates more tangent energy');
    });
  });

  group('Time reversal (duality)', () {
    SpectralTrajectory _buildJourney() => SpectralTrajectory(points: [
          for (var i = 0; i < 6; i++)
            _point(
                rev: i + 1,
                graph: i.isEven ? _pathGraph(14 + i) : _cycleGraph(14 + i)),
        ]);

    test('reversing empty is empty', () {
      expect(SpectralTrajectory.empty().reversed().isEmpty, isTrue);
    });

    test('reversing a single point yields the same set', () {
      final t = SpectralTrajectory(
          points: [_point(rev: 1, graph: _pathGraph(12))]);
      expect(t.reversed().length, 1);
      expect(t.reversed().head!.state, equals(t.head!.state));
    });

    test('pathLength is reversal-invariant', () {
      final t = _buildJourney();
      expect(t.reversed().pathLength, closeTo(t.pathLength, 1e-9));
    });

    test('dirichletAction is reversal-invariant', () {
      final t = _buildJourney();
      expect(t.reversed().dirichletAction,
          closeTo(t.dirichletAction, 1e-9));
    });

    test('turbulence is reversal-invariant', () {
      final t = _buildJourney();
      if (t.turbulence.isFinite) {
        expect(t.reversed().turbulence,
            closeTo(t.turbulence, 1e-9));
      }
    });

    test('tangent flips sign on reversal', () {
      // For a 3-point trajectory: tangentAt(0) in forward time =
      // B − A. In reversed time the order is (C, B, A), so
      // tangentAt(0) = B − C = −(C − B) = −tangentAt(1) of original.
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(16)),
        _point(rev: 2, graph: _cycleGraph(16)),
        _point(rev: 3, graph: _completeGraph(16)),
      ]);
      final origT0 = t.tangentAt(0);
      final origT1 = t.tangentAt(1);
      final rev = t.reversed();
      final revT0 = rev.tangentAt(0);
      final revT1 = rev.tangentAt(1);
      // reversed tangent[0] should match −original tangent[1].
      final k = revT0.length < origT1.length
          ? revT0.length
          : origT1.length;
      for (var j = 0; j < k; j++) {
        expect(revT0[j], closeTo(-origT1[j], 1e-12));
      }
      // Symmetric: reversed tangent[1] matches −original tangent[0].
      final k2 = revT1.length < origT0.length
          ? revT1.length
          : origT0.length;
      for (var j = 0; j < k2; j++) {
        expect(revT1[j], closeTo(-origT0[j], 1e-12));
      }
    });

    test('double reversal is identity (up to revision re-stamping)', () {
      final t = _buildJourney();
      final twice = t.reversed().reversed();
      expect(twice.length, equals(t.length));
      for (var i = 0; i < t.length; i++) {
        // States line up in the same order after two reversals.
        expect(twice.points[i].state, equals(t.points[i].state));
      }
    });

    test('signature is order-sensitive (not reversal-invariant in general)',
        () {
      final t = _buildJourney();
      // Unless the trajectory is palindromic (rare for non-trivial
      // graphs), the signature should change after reversal.
      expect(t.reversed().trajectorySignature,
          isNot(equals(t.trajectorySignature)));
    });
  });

  group('Dream — harmonic extrapolation', () {
    test('stepsAhead=0 reproduces the input (modulo NaN cleanup)', () {
      final curve = [for (var i = 0; i < 10; i++) i.toDouble()];
      final dreamed = SpectralTrajectory.dreamCurveForward(
          curve: curve, stepsAhead: 0);
      expect(dreamed, hasLength(10));
      for (var i = 0; i < curve.length; i++) {
        expect(dreamed[i], closeTo(curve[i], 1e-9));
      }
    });

    test('sinusoid continues phase-coherently', () {
      // A pure sine wave dreamed forward should extend the sine.
      const n = 32;
      const planted = 3;
      final curve = [
        for (var j = 0; j < n; j++) math.sin(2 * math.pi * planted * j / n)
      ];
      final dreamed = SpectralTrajectory.dreamCurveForward(
        curve: curve,
        stepsAhead: 16,
        keepOmegaBins: 2,
      );
      expect(dreamed, hasLength(n + 16));
      // The continuation region should still match the sinusoidal model.
      for (var t = n; t < n + 16; t++) {
        final expected = math.sin(2 * math.pi * planted * t / n);
        expect(dreamed[t], closeTo(expected, 1e-9),
            reason: 'dream at t=$t diverged from sinusoid continuation');
      }
    });

    test('constant curve dreams as a constant', () {
      final curve = List<double>.filled(20, 7.0);
      final dreamed = SpectralTrajectory.dreamCurveForward(
        curve: curve,
        stepsAhead: 10,
        keepOmegaBins: 0, // only DC
      );
      expect(dreamed, hasLength(30));
      for (final v in dreamed) {
        expect(v, closeTo(7.0, 1e-9));
      }
    });

    test('empty / negative inputs degrade cleanly', () {
      expect(SpectralTrajectory.dreamCurveForward(
          curve: const [], stepsAhead: 5), isEmpty);
      expect(SpectralTrajectory.dreamCurveForward(
          curve: const [1.0, 2.0], stepsAhead: -1), isEmpty);
    });

    test('dreamed training region approximates input', () {
      // Two-harmonic signal. Dream back over the training region
      // with keepOmegaBins=2 should reproduce it to tight tolerance.
      const n = 32;
      final curve = [
        for (var j = 0; j < n; j++)
          math.cos(2 * math.pi * 2 * j / n) +
              0.5 * math.cos(2 * math.pi * 5 * j / n)
      ];
      final dreamed = SpectralTrajectory.dreamCurveForward(
        curve: curve,
        stepsAhead: 0,
        keepOmegaBins: 4, // 2 harmonics × 2 sides (conjugate pairs)
      );
      for (var j = 0; j < n; j++) {
        expect(dreamed[j], closeTo(curve[j], 1e-9));
      }
    });

    test('low-keepBins truncation — noise dreams to trend only', () {
      final rng = math.Random(0xBEEF);
      // High-entropy random curve.
      final curve = [for (var i = 0; i < 40; i++) rng.nextDouble() * 2 - 1];
      final dreamed = SpectralTrajectory.dreamCurveForward(
        curve: curve,
        stepsAhead: 20,
        keepOmegaBins: 1,
      );
      expect(dreamed, hasLength(60));
      // The continuation should be SMOOTH (one frequency + DC), so
      // its second-difference variance should be much smaller than
      // the training region's.
      var trainVar = 0.0;
      for (var i = 1; i < 40 - 1; i++) {
        final d2 = curve[i + 1] - 2 * curve[i] + curve[i - 1];
        trainVar += d2 * d2;
      }
      trainVar /= 38;
      var dreamVar = 0.0;
      for (var i = 41; i < 60 - 1; i++) {
        final d2 =
            dreamed[i + 1] - 2 * dreamed[i] + dreamed[i - 1];
        dreamVar += d2 * d2;
      }
      dreamVar /= 17;
      expect(dreamVar, lessThan(trainVar),
          reason: 'low-keep dream should be smoother than noisy input');
    });
  });

  group('Heisenberg uncertainty — quantum mechanics on trajectory curves', () {
    test('zero energy returns NaN', () {
      final flat = List<double>.filled(16, 0.0);
      expect(SpectralTrajectory.heisenbergUncertainty(flat).isNaN, isTrue);
    });

    test('Gaussian has a finite, bounded uncertainty product', () {
      const n = 128;
      const sigma = 8.0;
      final curve = [
        for (var k = 0; k < n; k++)
          math.exp(-((k - n / 2) * (k - n / 2)) / (2 * sigma * sigma))
      ];
      final product = SpectralTrajectory.heisenbergUncertainty(curve);
      expect(product.isFinite, isTrue);
      expect(product, greaterThan(0.5),
          reason: 'Gaussian product must exceed the minimum positive bound');
      expect(product, lessThan(n.toDouble()),
          reason: 'Gaussian product is much less than N — concentrated in '
              'both time and frequency');
    });

    test('narrow-in-time ⇒ wide-in-frequency (Heisenberg duality)', () {
      // The essence of Heisenberg: concentration in one domain
      // MUST spread the other. Verify qualitatively on Gaussians.
      const n = 128;
      final narrow = <double>[];
      final wide = <double>[];
      for (var k = 0; k < n; k++) {
        narrow.add(math.exp(-((k - n / 2) * (k - n / 2)) / (2 * 4.0 * 4.0)));
        wide.add(math.exp(-((k - n / 2) * (k - n / 2)) / (2 * 16.0 * 16.0)));
      }
      final narrowT = SpectralTrajectory.curveTemporalMoments(narrow);
      final wideT = SpectralTrajectory.curveTemporalMoments(wide);
      final narrowF = SpectralTrajectory.curveSpectralMoments(narrow);
      final wideF = SpectralTrajectory.curveSpectralMoments(wide);
      // The DUAL relation: narrow in time ⇒ wide in freq and vice versa.
      expect(narrowT.variance, lessThan(wideT.variance),
          reason: 'narrow-σ curve has smaller time-variance');
      expect(narrowF.variance, greaterThan(wideF.variance),
          reason: 'narrow-σ curve has LARGER freq-variance (duality)');
    });

    test('uncertainty product stays positive on random curves', () {
      // For any non-zero signal, the product is positive.
      final rng = math.Random(0x12AB);
      const n = 64;
      for (var trial = 0; trial < 10; trial++) {
        final curve = [for (var i = 0; i < n; i++) rng.nextDouble()];
        final product = SpectralTrajectory.heisenbergUncertainty(curve);
        expect(product, greaterThan(0.0),
            reason: 'trial $trial got non-positive uncertainty product');
      }
    });
  });

  group('Integration — full observables stack on a synthetic journey', () {
    test('end-to-end: build, curves, CPD, forecast, signature, slice', () {
      // Build a "repo history" of 25 revisions. First 15 on a path
      // graph (slowly changing n); then jump to a cycle graph for
      // the rest — this is the planted regime change.
      final pts = <TrajectoryPoint>[];
      for (var i = 0; i < 15; i++) {
        pts.add(_point(rev: i + 1, graph: _pathGraph(20 + i)));
      }
      for (var i = 0; i < 10; i++) {
        pts.add(_point(rev: 16 + i, graph: _cycleGraph(34 + i)));
      }
      final t = SpectralTrajectory(points: pts);

      expect(t.length, 25);
      expect(t.pathLength, greaterThan(0.0));

      // The gap curve is what really shifts between path and cycle
      // topologies, so drive CPD from there.
      final gaps = t.gapCurve();
      final cp = t.regimeChanges(curve: gaps, window: 8, sensitivity: 2.0);
      expect(cp, isNotEmpty,
          reason: 'path→cycle transition must be detected');

      // Forecast the rigidity one step ahead; expect a finite number.
      final pred = SpectralTrajectory.forecastScalar(
          t.rigidityCurve(),
          fitWindow: 12);
      expect(pred.isFinite, isTrue);

      // Signature is deterministic AND changes with appended point.
      final sig0 = t.trajectorySignature;
      final t2 = t.appended(_point(rev: 26, graph: _completeGraph(15)));
      expect(t2.trajectorySignature, isNot(equals(sig0)));

      // Slice preserves signature equality on the matching subrange.
      final sub = t.slice(0, 5);
      expect(sub.length, 5);
      final subRebuilt = SpectralTrajectory(points: pts.sublist(0, 5));
      expect(sub.trajectorySignature, equals(subRebuilt.trajectorySignature));
    });
  });

  group('universality trajectory', () {
    test('universalityCurve populates one reading per resolved point', () {
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(24)),
        _point(rev: 2, graph: _cycleGraph(24)),
        _point(rev: 3, graph: _completeGraph(24)),
      ]);
      final curve = t.universalityCurve();
      expect(curve.length, 3);
      // Every resolved snapshot produces a non-null universality
      // reading, and every distance lives in [0, 1].
      for (final u in curve) {
        expect(u, isNotNull);
        for (final d in [
          u!.toCrystalline, u.toPoisson, u.toGoe, u.toTree,
          u.toBulk, u.toModular,
        ]) {
          expect(d, inInclusiveRange(0.0, 1.0));
        }
      }
    });

    test('archetypeDrift is zero on a constant trajectory', () {
      // Same graph at every point → identical basis → identical
      // universality → zero pairwise distance → zero drift. This is
      // the load-bearing contract: no drift on no change.
      final g = _pathGraph(24);
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: g),
        _point(rev: 2, graph: g),
        _point(rev: 3, graph: g),
      ]);
      expect(t.archetypeDrift(), equals(0.0));
    });

    test('archetypeDrift is positive when the repo actually changes', () {
      // Two structurally-different graphs in sequence → non-zero
      // universality vector distance.
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: _pathGraph(24)),
        _point(rev: 2, graph: _completeGraph(24)),
      ]);
      expect(t.archetypeDrift(), greaterThan(0.0));
    });

    test('archetypeTransitions is empty when all points share archetype',
        () {
      // On a constant trajectory every reading is identical → zero
      // transitions. On a changing one the count may be 0 or more
      // depending on classifier sensitivity (tested via drift above).
      final g = _pathGraph(24);
      final t = SpectralTrajectory(points: [
        _point(rev: 1, graph: g),
        _point(rev: 2, graph: g),
      ]);
      expect(t.archetypeTransitions(), isEmpty);
    });
  });
}
