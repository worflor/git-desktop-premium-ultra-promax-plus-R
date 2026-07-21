// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Tests for the blast-radius evidence channel — given a diff's changed
// files, surface historically co-changed files that are absent from the
// diff, and never surface ones that are present.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/review_blast_radius.dart';

FileCouplingMatrix _coupling() => FileCouplingMatrix(
      jaccard: {
        'lib/auth.dart': {
          'test/auth_test.dart': 0.80,
          'lib/session.dart': 0.50,
          'lib/trivial.dart': 0.05,
        },
        'lib/payment.dart': {'lib/ledger.dart': 0.70},
      },
      headHash: 'test',
      commitsAnalyzed: 100,
    );

void main() {
  group('computeBlastRadius', () {
    test('surfaces strongly-coupled files absent from the diff', () {
      final files = computeBlastRadius(
        coupling: _coupling(),
        changedPaths: {'lib/auth.dart', 'lib/payment.dart'},
        integrityByPath: const {},
      );
      final paths = files.map((c) => c.path).toSet();
      expect(paths, contains('test/auth_test.dart'));
      expect(paths, contains('lib/ledger.dart'));
      // session is within the φ⁻¹ band of auth's strongest tie (0.8).
      expect(paths, contains('lib/session.dart'));
    });

    test('drops weak, unnameable ties below the φ-band', () {
      final files = computeBlastRadius(
        coupling: _coupling(),
        changedPaths: {'lib/auth.dart'},
        integrityByPath: const {},
      );
      // 0.05 is far below 0.8 * φ⁻¹ ≈ 0.49 and has no named relation.
      expect(files.map((c) => c.path), isNot(contains('lib/trivial.dart')));
    });

    test('never surfaces a file that is itself in the diff', () {
      final files = computeBlastRadius(
        coupling: _coupling(),
        changedPaths: {'lib/auth.dart', 'test/auth_test.dart'},
        integrityByPath: const {},
      );
      expect(files.map((c) => c.path), isNot(contains('test/auth_test.dart')));
    });

    test('ranks by jaccard × integrity (trust down-weights)', () {
      final files = computeBlastRadius(
        coupling: _coupling(),
        changedPaths: {'lib/auth.dart', 'lib/payment.dart'},
        // ledger is generated/low-trust → its 0.70 tie is discounted
        // below auth_test's 0.80.
        integrityByPath: const {'lib/ledger.dart': 0.2},
      );
      expect(files.first.path, 'test/auth_test.dart');
    });

    test('counts multiple anchors pulling the same file', () {
      final coupling = FileCouplingMatrix(
        jaccard: {
          'lib/a.dart': {'lib/shared.dart': 0.9},
          'lib/b.dart': {'lib/shared.dart': 0.9},
        },
        headHash: 'test',
        commitsAnalyzed: 50,
      );
      final files = computeBlastRadius(
        coupling: coupling,
        changedPaths: {'lib/a.dart', 'lib/b.dart'},
        integrityByPath: const {},
      );
      final shared = files.firstWhere((c) => c.path == 'lib/shared.dart');
      expect(shared.anchorCount, 2);
    });
  });

  group('formatBlastRadiusBlock', () {
    test('empty in, empty out', () {
      expect(formatBlastRadiusBlock(const []), '');
    });

    test('renders a status line and one row per file', () {
      final files = computeBlastRadius(
        coupling: _coupling(),
        changedPaths: {'lib/auth.dart'},
        integrityByPath: const {},
      );
      final block = formatBlastRadiusBlock(files);
      expect(block, contains('status: populated'));
      expect(block, contains('lib/auth.dart ↔ test/auth_test.dart'));
      expect(block, contains('J=0.80'));
    });
  });
}
