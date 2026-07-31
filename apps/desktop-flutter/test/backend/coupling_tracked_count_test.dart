// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// coupling_tracked_count_test.dart — history counts must not move with the
// working tree.
//
// Found by pointing Manifold's history review at the commit that introduced
// the coupling evidence rules. `trackedFileCount` returned the id-space size,
// and `withSpectral` appends the CURRENT change set's untracked files to that
// same space. The count of "files this repository has history for" therefore
// grew when you opened new files, and it is a denominator: repository-level
// coupling confidence shifted with what happened to be uncommitted.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';

import '../support/scratch_repo.dart';

void main() {
  late FileCouplingMatrix matrix;

  setUpAll(() async {
    final repo = await ScratchRepo.create(name: 'tracked_count');
    // Three files with real co-change history, built over several commits so
    // the jaccard rows are genuinely populated.
    for (var i = 0; i < 4; i++) {
      await repo.writeFile('a.dart', 'const a = $i;\n');
      await repo.writeFile('b.dart', 'const b = $i;\n');
      if (i.isEven) await repo.writeFile('c.dart', 'const c = $i;\n');
      await repo.commitAll('round $i');
    }
    final r = await computeFileCoupling(repo.dir.path);
    expect(r.ok, isTrue, reason: 'coupling: ${r.error}');
    matrix = r.data!;
    await repo.dispose();
  });

  test('C1: the count covers files with real co-change history', () {
    expect(matrix.trackedFileCount, greaterThan(0));
    for (final path in const ['a.dart', 'b.dart']) {
      expect(matrix.hasJaccardRow(path), isTrue,
          reason: 'guard: $path must have history for this test to mean '
              'anything');
    }
  });

  test('C2: layering untracked files in does NOT inflate the count', () {
    // The bug, directly: `withSpectral` puts these in the id space so their
    // spectral overlap can be queried. They carry no history and must not
    // enlarge a history count.
    final before = matrix.trackedFileCount;
    final layered = matrix.withSpectral({
      'brand_new_one.dart': {'brand_new_two.dart': 0.9},
      'brand_new_two.dart': {'brand_new_one.dart': 0.9},
      'brand_new_three.dart': {'a.dart': 0.5},
    });

    expect(layered.containsPath('brand_new_one.dart'), isTrue,
        reason: 'guard: withSpectral must still layer them into the id space, '
            'or this test is asserting nothing');
    expect(layered.hasJaccardRow('brand_new_one.dart'), isFalse,
        reason: 'guard: and they must still have no history');

    expect(layered.trackedFileCount, before,
        reason: 'three untracked files appeared in the id space; the number '
            'of files this repository has HISTORY for did not change');
  });

  test('C3: repository confidence does not drift with the change set', () {
    // The consequence that made the miscount matter. `couplingConfidence`
    // divides commits analysed by a saturation point sized from
    // trackedFileCount, so an inflated count lowered the confidence a
    // repository reported about history that had not changed at all.
    final plain = couplingConfidence(matrix);
    expect(plain, greaterThan(0.0), reason: 'guard: there is some evidence');

    final layered = matrix.withSpectral({
      for (var i = 0; i < 40; i++) 'scratch_$i.dart': {'a.dart': 0.4},
    });
    final withNoise = couplingConfidence(layered);

    expect(withNoise, closeTo(plain, 1e-12),
        reason: 'opening 40 new files changed how confident the repository '
            'was about history those files had no part in');
  });
}
