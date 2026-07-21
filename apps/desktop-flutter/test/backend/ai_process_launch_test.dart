// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Pins _runObservedProcess's launch-vs-timeout contract — the centerpiece of
// the "make failures loud" fix. A failed spawn must come back as a non-null
// result carrying the real OS error (exitCode -1), while ONLY a genuine
// timeout returns null. Conflating the two is exactly what made a 200 KB argv
// (the Windows 32767-char CreateProcess overflow) surface to the user as a
// phantom "Provider command timed out". Without this test that regression is
// a one-character edit away from silently returning.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart';

void main() {
  group('runObservedProcess launch vs timeout', () {
    test('a failed spawn returns a non-null result with the OS error, not null',
        () async {
      final result = await runObservedProcessForTesting(
        'definitely_not_a_real_binary_zzqq',
        const ['--version'],
      );
      // The regression guard: a spawn failure must NOT collapse to null — every
      // caller reads null as "timed out". It comes back as a non-zero result
      // whose stderr is the real launch error.
      expect(result, isNotNull);
      expect(result!.exitCode, -1);
      expect(result.stderr.trim(), isNotEmpty);
      expect(result.stderr.toLowerCase(), isNot(contains('timed out')));
    });

    test('a genuine timeout returns null (distinct from a spawn failure)',
        () async {
      // A process that comfortably outlives the timeout. _runObservedProcess
      // kills it and returns null — the one and only meaning of null now.
      final command = Platform.isWindows ? 'cmd' : 'sh';
      final args = Platform.isWindows
          ? const ['/c', 'ping', '-n', '30', '127.0.0.1']
          : const ['-c', 'sleep 30'];
      final result = await runObservedProcessForTesting(
        command,
        args,
        timeout: const Duration(milliseconds: 500),
      );
      expect(result, isNull);
    });
  });
}
