// Contract tests for the net-new (CodeScene-can't-do-this) findings: thrashing
// (motion without progress) and silent reshuffle (a quiet commit that moved
// which files are central). Both are derived purely from the UASE-stable
// embedding, so these lock the signal to real geometry — and, just as
// important, lock that they STAY SILENT when there's nothing to report.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/orrery/orrery_findings.dart';
import 'package:git_desktop/features/orrery/orrery_model.dart';

OrreryStep _step(int i, {double gap = 0.5, bool regime = false}) => OrreryStep(
      revision: i,
      sha: 'sha$i',
      date: null,
      gap: gap,
      rigidity: 0,
      vonNeumann: 0,
      archetype: 'modular',
      canonicality: 0.5,
      regimeChange: regime,
    );

bool _has(List<OrreryFinding> fs, OrreryFindingKind k) =>
    fs.any((f) => f.kind == k);

void main() {
  group('thrash', () {
    test('fires on a file that oscillates back and forth', () {
      // x alternates 0.2↔0.6 then lands back near 0.2: long path, ~zero net.
      const xs = [0.2, 0.6, 0.2, 0.6, 0.2, 0.6, 0.25];
      final model = OrreryModel(
        steps: [for (int i = 0; i < xs.length; i++) _step(i)],
        nodes: [
          OrreryNode(
            id: 0,
            path: 'lib/thrasher.dart',
            positions: [for (final x in xs) Offset(x, 0)],
          ),
        ],
      );
      expect(_has(computeFindings(model), OrreryFindingKind.thrash), isTrue);
    });

    test('stays silent on a file that drifts steadily', () {
      const xs = [0.1, 0.22, 0.35, 0.5, 0.65, 0.8, 0.9];
      final model = OrreryModel(
        steps: [for (int i = 0; i < xs.length; i++) _step(i)],
        nodes: [
          OrreryNode(
            id: 0,
            path: 'lib/steady.dart',
            positions: [for (final x in xs) Offset(x, 0)],
          ),
        ],
      );
      expect(_has(computeFindings(model), OrreryFindingKind.thrash), isFalse);
    });
  });

  group('reshuffle', () {
    // 10 files wiggling slightly each step, with one big synchronized internal
    // jump at step 5 (a permanent shift) while the global gap holds steady, so
    // the motion spike sits at exactly one step.
    OrreryModel build({bool kick = true, bool regimeAtKick = false}) {
      const n = 10, steps = 10;
      final nodes = <OrreryNode>[];
      for (int i = 0; i < n; i++) {
        final a = 0.3 * i;
        final pos = <Offset?>[];
        for (int s = 0; s < steps; s++) {
          final r = 0.3 + 0.03 * i + 0.005 * s + (kick && s >= 5 ? 0.25 : 0.0);
          pos.add(Offset(r * math.cos(a), r * math.sin(a)));
        }
        nodes.add(OrreryNode(id: i, path: 'lib/f$i.dart', positions: pos));
      }
      return OrreryModel(
        steps: [
          for (int s = 0; s < steps; s++)
            _step(s, gap: 0.5 + 0.001 * s, regime: regimeAtKick && s == 5),
        ],
        nodes: nodes,
      );
    }

    test('fires on a big internal motion spike with steady connectivity', () {
      expect(
          _has(computeFindings(build()), OrreryFindingKind.reshuffle), isTrue);
    });

    test('stays silent on a flat history (no spike)', () {
      expect(
          _has(
              computeFindings(build(kick: false)), OrreryFindingKind.reshuffle),
          isFalse);
    });

    test('defers to a regime change — that is the loud kind, not silent', () {
      final fs = computeFindings(build(regimeAtKick: true));
      expect(_has(fs, OrreryFindingKind.reshuffle), isFalse);
      expect(_has(fs, OrreryFindingKind.regime), isTrue);
    });
  });

  group('forecast', () {
    // Gap flat-high through the first half, then a given trajectory in the
    // recent half. A few static nodes so the position-based findings stay quiet.
    OrreryModel fromGaps(List<double> gaps) => OrreryModel(
          steps: [
            for (int i = 0; i < gaps.length; i++) _step(i, gap: gaps[i]),
          ],
          nodes: const [
            OrreryNode(
              id: 0,
              path: 'lib/a.dart',
              positions: [Offset(0.1, 0), Offset(0.1, 0)],
            ),
          ],
        );

    List<double> ramp(double from, double to) {
      const n = 14;
      const lo = 7;
      return [
        for (int i = 0; i < n; i++)
          i < lo ? from : from + (to - from) * (i - lo) / (n - 1 - lo),
      ];
    }

    test('warns of a split when connectivity slides toward its low', () {
      final fs = computeFindings(fromGaps(ramp(0.9, 0.1)));
      expect(_has(fs, OrreryFindingKind.forecast), isTrue);
      expect(
          fs.firstWhere((f) => f.kind == OrreryFindingKind.forecast).headline,
          contains('splitting'));
    });

    test('warns of a monolith when connectivity climbs toward its peak', () {
      final fs = computeFindings(fromGaps(ramp(0.1, 0.9)));
      expect(_has(fs, OrreryFindingKind.forecast), isTrue);
      expect(
          fs.firstWhere((f) => f.kind == OrreryFindingKind.forecast).headline,
          contains('monolith'));
    });

    test('stays silent on a steady connectivity', () {
      final fs = computeFindings(fromGaps(List<double>.filled(14, 0.5)));
      expect(_has(fs, OrreryFindingKind.forecast), isFalse);
    });
  });
}
