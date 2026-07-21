// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Pins openRepository's stale-folder contract: a path that no longer exists
// yields the clean, user-facing message — never the raw `ProcessException:
// The directory name is invalid` text that `git rev-parse` would otherwise
// throw and leak verbatim to the UI. Guards both the up-front existence check
// and the TOCTOU recheck in the catch.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';

void main() {
  test('openRepository on a missing folder returns the clean message', () async {
    final missing =
        '${Directory.systemTemp.path}${Platform.pathSeparator}zzqq_manifold_no_such_dir';
    expect(
      await Directory(missing).exists(),
      isFalse,
      reason: 'precondition: the test path must not exist',
    );

    final result = await openRepository(missing);

    expect(result.ok, isFalse);
    expect(result.error, "This project's folder no longer exists.");
    // The whole point of the guard — the raw exception text never escapes.
    expect(result.error, isNot(contains('ProcessException')));
  });
}
