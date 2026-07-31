// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// admitted_patch_test.dart — the memory gate in front of a history diff.
//
// Both cases here were found by Manifold reviewing its own change, and both
// fail in the same direction: they DECLARE LESS than the patch really costs,
// which is the direction that exhausts memory. A gate that under-declares is
// worse than no gate, because it reports success.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/admitted_git.dart';
import 'package:git_desktop/backend/analysis_admission.dart';
import 'package:git_desktop/backend/git.dart';

import '../support/scratch_repo.dart';

void main() {
  late ScratchRepo repo;
  late String bigOid;
  late String smallOid;

  setUpAll(() async {
    repo = await ScratchRepo.create(name: 'admit_patch');
    await repo.writeFile('big.txt', 'x' * 50000);
    await repo.writeFile('small.txt', 'y');
    await repo.commitAll('two blobs');
    bigOid = (await repo.gitOk(['rev-parse', 'HEAD:big.txt'])).trim();
    smallOid = (await repo.gitOk(['rev-parse', 'HEAD:small.txt'])).trim();
  });

  tearDownAll(() async => repo.dispose());

  test('A1: sizes are exact for the objects asked about', () async {
    final sizes = await gitBlobSizesBatch(repo.dir.path, [bigOid, smallOid]);
    expect(sizes, isNotNull);
    expect(sizes![bigOid], 50000);
    expect(sizes[smallOid], 1);
  });

  test('A2: an object git cannot resolve makes the whole answer null',
      () async {
    // A partial map summed by the caller declares a fraction of the real
    // cost, and "I measured a small diff" is then indistinguishable from
    // "I could not measure this diff".
    const absent = '0123456789012345678901234567890123456789';
    final sizes = await gitBlobSizesBatch(repo.dir.path, [bigOid, absent]);
    expect(sizes, isNull,
        reason: 'a hole in the measurement must not degrade to a smaller '
            'total — it must stop being a measurement');
  });

  test('A3: an unmeasurable patch is DECLINED, not admitted for free',
      () async {
    // The bug this pins: the sizing probe swallowed every failure into an
    // empty map, the caller summed it to zero, and a zero-byte declaration
    // is always admitted. The gate opened widest at exactly the moment it
    // knew least.
    var ran = false;
    final result = await admitGitPatchText(
      repo.dir.path,
      const ['0123456789012345678901234567890123456789'],
      () async {
        ran = true;
        return 'work';
      },
    );
    expect(result.decision, AdmissionDecision.declined);
    expect(ran, isFalse, reason: 'declined work must never have run');
  });

  test('A4: a blob on several paths is declared once PER OCCURRENCE',
      () async {
    // git prints the blob's content once per path it appears on, so three
    // occurrences cost three times the resident text. The sizing probe
    // dedupes its subprocess input (correctly — asking twice is waste), and
    // summing that deduped map is what silently loses the multiplier.
    //
    // Measured from the accountant itself while the admitted work is in
    // flight, so this reads the reservation the real function actually made
    // rather than re-deriving what it should have been.
    final one = await _declaredBytes(repo.dir.path, [bigOid]);
    final three =
        await _declaredBytes(repo.dir.path, [bigOid, bigOid, bigOid]);

    expect(one, greaterThan(0), reason: 'guard: something was reserved');
    expect(three, one * 3,
        reason: 'the same blob on three paths is printed three times; '
            'declaring it once under-reserves for every repository with '
            'copied or identical files');
  });
}

/// Bytes [admitGitPatchText] actually reserved for [oids], observed from
/// inside the admitted work.
Future<int> _declaredBytes(String repo, List<String> oids) async {
  final before = AnalysisAdmission.instance.inFlightBytes;
  var during = 0;
  final result = await admitGitPatchText(repo, oids, () async {
    during = AnalysisAdmission.instance.inFlightBytes;
    return null;
  });
  expect(result.ran, isTrue, reason: 'expected admission to run');
  return during - before;
}
