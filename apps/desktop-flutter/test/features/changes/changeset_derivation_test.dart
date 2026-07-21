// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/changes/changeset_derivation.dart';

void main() {
  group('computeFileDimOpacity', () {
    test('dims the below-median files, leaves the rest at full opacity', () {
      // 4 files, no coupling (centrality falls back to 0.5 everywhere), uniform
      // integrity 0.9. Blend weight = 0.45·0.5 + 0.35·surprise + 0.20·0.9.
      //   a: vol 1.0 → surprise 0   → 0.405
      //   b: vol 0.0 → surprise 1   → 0.755
      //   c: vol 0.5 → surprise 0.5 → 0.580
      //   d: vol 0.0 → surprise 1   → 0.755
      // median = 0.755 → a & c fall below and dim; b & d stay full.
      final dim = computeFileDimOpacity(
        paths: const ['a', 'b', 'c', 'd'],
        volatility: const {'a': 1.0, 'b': 0.0, 'c': 0.5, 'd': 0.0},
        integrity: const {'a': 0.9, 'b': 0.9, 'c': 0.9, 'd': 0.9},
        coupling: null,
      );

      expect(dim.keys.toSet(), {'a', 'c'});
      expect(dim['a'], closeTo(0.791, 0.002));
      expect(dim['c'], closeTo(0.896, 0.002));
    });

    test('abstains below 3 files', () {
      final dim = computeFileDimOpacity(
        paths: const ['a', 'b'],
        volatility: const {'a': 1.0, 'b': 0.0},
        integrity: const {},
        coupling: null,
      );
      expect(dim, isEmpty);
    });

    test('abstains when the changeset is too uniform to separate', () {
      // Identical inputs → zero spread → no foreground/background to dim.
      final dim = computeFileDimOpacity(
        paths: const ['a', 'b', 'c', 'd'],
        volatility: const {'a': 0.5, 'b': 0.5, 'c': 0.5, 'd': 0.5},
        integrity: const {'a': 0.9, 'b': 0.9, 'c': 0.9, 'd': 0.9},
        coupling: null,
      );
      expect(dim, isEmpty);
    });

    test('abstains when stats are unavailable', () {
      final dim = computeFileDimOpacity(
        paths: const ['a', 'b', 'c'],
        volatility: null,
        integrity: null,
        coupling: null,
      );
      expect(dim, isEmpty);
    });
  });
}
