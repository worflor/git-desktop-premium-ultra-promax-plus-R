// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Law-based coverage for repo_blob_walk.dart, previously untested.
//
// Two halves:
//   - buildLineOffsets: pure-function laws checked via forAll over
//     genMultilineText(), which deliberately produces LF/CR/CRLF-mixed text
//     with and without a trailing terminator.
//   - walkRepoBlobs / walkRepoBlobsForPaths / fileCap sampling: exercised
//     against real ScratchRepo working trees so the git ls-files + stat +
//     binary-sniff + decode pipeline runs for real.
//
// Each buildLineOffsets law gets its OWN forAll call rather than being
// bundled into one `check`, so a failure in one law does not starve the
// other laws of coverage across the 200-case sweep (forAll stops the whole
// sweep at the first failing case).

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/repo_blob_walk.dart';

import '../support/gen.dart';
import '../support/prop.dart';
import '../support/scratch_repo.dart';

/// Independent oracle for "how many terminator-delimited lines does this
/// text have": count LF, lone CR, and CRLF each as exactly one terminator,
/// then add one for the trailing (possibly empty) partial line — mirroring
/// the English-language spec buildLineOffsets is documented to satisfy,
/// not a copy of its implementation.
/// The line count `buildLineOffsets` should report, as `offsets.length - 1`.
///
/// A terminator ends a line; content after the last terminator is one more
/// (partial) line. A trailing terminator does NOT open a phantom empty line
/// — `"a\n"` is one line, not two — and the empty string is zero lines. This
/// is the correct terminator-delimited count, and it is exactly consistent
/// with the strict-monotonicity law: both hold together only because
/// `buildLineOffsets` appends its end sentinel just once.
int _oracleLineCount(String text) {
  if (text.isEmpty) return 0;
  var terminators = 0;
  var i = 0;
  final n = text.length;
  var lastWasTerminator = false;
  while (i < n) {
    final c = text.codeUnitAt(i);
    if (c == 0x0A) {
      terminators++;
      i++;
      lastWasTerminator = true;
    } else if (c == 0x0D) {
      terminators++;
      i++;
      if (i < n && text.codeUnitAt(i) == 0x0A) i++;
      lastWasTerminator = true;
    } else {
      i++;
      lastWasTerminator = false;
    }
  }
  // Content after the final terminator is one more line; a trailing
  // terminator is not.
  return terminators + (lastWasTerminator ? 0 : 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildLineOffsets — laws', () {
    test('starts at 0 and ends at text.length', () {
      forAll<String>(
        genMultilineText(),
        describe: 'buildLineOffsets bounds',
        check: (text) {
          final offsets = buildLineOffsets(text);
          expect(offsets.first, 0);
          expect(offsets.last, text.length);
        },
      );
    });

    test('slicing offsets[i]..offsets[i+1] and concatenating reproduces '
        'the text exactly', () {
      forAll<String>(
        genMultilineText(),
        describe: 'buildLineOffsets reconstruction',
        check: (text) {
          final offsets = buildLineOffsets(text);
          final buffer = StringBuffer();
          for (var k = 0; k < offsets.length - 1; k++) {
            buffer.write(text.substring(offsets[k], offsets[k + 1]));
          }
          expect(buffer.toString(), text);
        },
      );
    });

    test('offsets.length - 1 equals the terminator-delimited line count',
        () {
      forAll<String>(
        genMultilineText(),
        describe: 'buildLineOffsets line count',
        check: (text) {
          final offsets = buildLineOffsets(text);
          expect(offsets.length - 1, _oracleLineCount(text));
        },
      );
    });

    // Was a real bug: buildLineOffsets unconditionally appended
    // `text.length` after its scan loop, so a text that was empty or ended
    // exactly on a terminator got two equal trailing entries — violating
    // strict monotonicity and inflating every newline-terminated file's line
    // count by one. Fixed in repo_blob_walk.dart to append the end sentinel
    // only when it isn't already present. This property (and the line-count
    // oracle above) now pin that fix; the counterexample lives in the corpus.
    test('offsets is strictly increasing', () {
      forAll<String>(
        genMultilineText(),
        describe: 'buildLineOffsets strictly increasing',
        check: (text) {
          final offsets = buildLineOffsets(text);
          for (var i = 1; i < offsets.length; i++) {
            expect(offsets[i], greaterThan(offsets[i - 1]),
                reason: 'offsets[$i]=${offsets[i]} not > '
                    'offsets[${i - 1}]=${offsets[i - 1]} for text='
                    '${text.codeUnits}');
          }
        },
      );
    });

    test('lone CR is one terminator', () {
      expect(buildLineOffsets('a\rb'), [0, 2, 3]);
    });

    test('CRLF is one terminator, not two', () {
      expect(buildLineOffsets('a\r\nb'), [0, 3, 4]);
    });

    test('LF is one terminator', () {
      expect(buildLineOffsets('a\nb'), [0, 2, 3]);
    });

    test('no trailing newline still yields the final partial line', () {
      expect(buildLineOffsets('abc'), [0, 3]);
    });
  });

  group('walkRepoBlobs — real repo', () {
    test('exact filter counters and forward-slash relative paths', () async {
      final repo = await ScratchRepo.create(name: 'walk_counts');
      addTearDown(repo.dispose);
      const opts = RepoBlobWalkOptions(minBytes: 16, maxBytes: 64);

      await repo.writeFile('a.txt', 'a' * 20);
      await repo.writeFile('nested/b.txt', 'b' * 25);
      // Binary: a NUL byte within the first 8KB probe window, sized inside
      // the min/max band so it reaches the binary check (not sizeSkipped).
      await repo.writeFile('bin.dat', '${String.fromCharCode(0)}${'x' * 20}');
      await repo.writeFile('small.txt', 'tiny'); // below minBytes
      await repo.writeFile('large.txt', 'z' * 100); // above maxBytes
      await repo.stageAll();

      final result = await walkRepoBlobs(repo.dir.path, options: opts);

      expect(result.trackedCount, 5);
      expect(result.binarySkipped, 1);
      expect(result.sizeSkipped, 2);
      expect(result.decodeFailed, 0);
      expect(result.sampledOut, 0);
      expect(result.blobs.length, 2);
      expect(result.blobs.map((b) => b.relativePath).toSet(),
          {'a.txt', 'nested/b.txt'});
      expect(result.blobs.every((b) => !b.relativePath.contains('\\')), isTrue,
          reason: 'relativePath must always use forward slashes');
    });
  });

  group('walkRepoBlobsForPaths', () {
    test('a path that does not exist increments decodeFailed and never '
        'throws', () async {
      final repo = await ScratchRepo.create(name: 'walk_missing');
      addTearDown(repo.dispose);

      final result = await walkRepoBlobsForPaths(
        repo.dir.path,
        const ['does/not/exist.txt'],
      );

      expect(result.trackedCount, 1);
      expect(result.decodeFailed, 1);
      expect(result.blobs, isEmpty);
    });
  });

  group('fileCap sampling', () {
    test('10 tracked files with fileCap:3 samples down to <=3 blobs, with '
        'sampledOut making up the rest', () async {
      final repo = await ScratchRepo.create(name: 'walk_cap');
      addTearDown(repo.dispose);
      for (var i = 0; i < 10; i++) {
        await repo.writeFile('f$i.txt', 'content number $i padded long xxxx');
      }
      await repo.stageAll();

      final result = await walkRepoBlobs(
        repo.dir.path,
        options: const RepoBlobWalkOptions(fileCap: 3),
      );

      expect(result.trackedCount, 10);
      expect(result.blobs.length <= 3, isTrue);
      expect(result.sampledOut, result.trackedCount - result.blobs.length);
    });
  });
}
