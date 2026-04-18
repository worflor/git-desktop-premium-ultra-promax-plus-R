// Tests for `_formatAxisBreakdown` — the per-file axis-explanation
// formatter that makes the Logos relevance neighborhood emission
// self-explaining (`via=cc(64%) sp=21% f0=15%` instead of just a φ).
//
// Locks the contract so a future refactor can't silently break the
// AI's ability to ground its findings in the axis attribution.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart' show formatAxisBreakdownForTesting;
import 'package:git_desktop/backend/logos_git.dart' show AxisAttribution;

AxisAttribution _attr({
  required Map<String, Map<String, double>> shares,
  required Map<String, String> dominant,
}) {
  return AxisAttribution(
    combined: const [],
    perAxisPhi: const {},
    nodePaths: const [],
    dominantAxis: dominant,
    shareByAxis: shares,
  );
}

void main() {
  group('_formatAxisBreakdown', () {
    test('dominant axis wears the parens marker; others use =', () {
      // Dominant=cc, others ranked by share desc.
      final attr = _attr(
        shares: {
          'lib/foo.dart': {'cc': 0.64, 'sp': 0.21, 'f0': 0.15},
        },
        dominant: {'lib/foo.dart': 'cc'},
      );
      expect(
        formatAxisBreakdownForTesting(attr, 'lib/foo.dart'),
        'cc(64%) sp=21% f0=15%',
      );
    });

    test('axes below the 10% signal floor are dropped', () {
      // 4% and 2% shares fall below floor; only cc + sp emitted.
      final attr = _attr(
        shares: {
          'lib/foo.dart': {'cc': 0.70, 'sp': 0.24, 'f0': 0.04, 'v': 0.02},
        },
        dominant: {'lib/foo.dart': 'cc'},
      );
      expect(
        formatAxisBreakdownForTesting(attr, 'lib/foo.dart'),
        'cc(70%) sp=24%',
      );
    });

    test('all axes below floor → empty string (no useful breakdown)', () {
      final attr = _attr(
        shares: {
          'lib/foo.dart': {'cc': 0.04, 'sp': 0.03, 'f0': 0.03},
        },
        dominant: {'lib/foo.dart': 'cc'},
      );
      expect(formatAxisBreakdownForTesting(attr, 'lib/foo.dart'), '');
    });

    test('alphabetical tiebreak on equal shares (deterministic)', () {
      final attr = _attr(
        shares: {
          'lib/foo.dart': {'sp': 0.50, 'cc': 0.50},
        },
        dominant: {'lib/foo.dart': 'cc'},
      );
      // Equal shares: alphabetical secondary → cc before sp.
      expect(
        formatAxisBreakdownForTesting(attr, 'lib/foo.dart'),
        'cc(50%) sp=50%',
      );
    });

  });
}
