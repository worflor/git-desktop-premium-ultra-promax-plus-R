// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Coverage for the dark half of lib/backend/logos_hunks.dart:
// parseDiffHunks / parseDiffHunksForFile on multi-file diffs, renames,
// new/deleted files, binary stanzas, mode changes, CRLF content, and
// no-newline-at-eof — plus one real-git property check via ScratchRepo.
//
// test/backend/logos_hunks_test.dart already covers packHunksUnderBudget's
// file-witness annotation and the rankHunksByPhiAsync isolate hop; this
// file does not repeat that. test/backend/git_diff_paths_test.dart already
// exhaustively covers unCQuoteGitPath/pathFromDiffGitHeader in isolation;
// here we only check that parseDiffHunks wires that shared parser in
// correctly end-to-end (one quoted-path integration case).

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_hunks.dart';

import '../support/scratch_repo.dart';

/// Comparable signature for a [DiffHunk] — the type has no `==`, so
/// determinism/equality checks compare this tuple instead.
(String, int, String, String, int, int, int, int) _sig(DiffHunk h) => (
      h.filePath,
      h.hunkIndex,
      h.header,
      h.body,
      h.oldStart,
      h.newStart,
      h.additions,
      h.deletions,
    );

/// Parses a `@@ -old,oldCount +new,newCount @@` header. Missing counts
/// default to 1 per the unified-diff spec (matches git's own emission
/// rule: an omitted `,N` means exactly one line).
final _headerCountsRe =
    RegExp(r'^@@\s*-(\d+)(?:,(\d+))?\s*\+(\d+)(?:,(\d+))?\s*@@');

(int oldCount, int newCount) _headerCounts(String header) {
  final m = _headerCountsRe.firstMatch(header);
  if (m == null) {
    fail('header does not match the @@ pattern: $header');
  }
  final oldCount = m.group(2) == null ? 1 : int.parse(m.group(2)!);
  final newCount = m.group(4) == null ? 1 : int.parse(m.group(4)!);
  return (oldCount, newCount);
}

/// Asserts the "line counts in the @@ header match the body" law: the
/// number of context+removed lines equals the header's old count, and
/// the number of context+added lines equals the header's new count.
/// Skips the `@@` header line itself (body's first line) and any
/// `\ No newline at end of file` marker (neither +, -, nor context).
void _expectHeaderMatchesBody(DiffHunk h) {
  final (oldCount, newCount) = _headerCounts(h.header);
  final lines = h.body.split('\n');
  var oldSeen = 0;
  var newSeen = 0;
  for (final line in lines.skip(1)) {
    if (line.isEmpty) continue;
    if (line.startsWith('\\')) continue; // "\ No newline at end of file"
    if (line.startsWith(' ')) {
      oldSeen++;
      newSeen++;
    } else if (line.startsWith('-')) {
      oldSeen++;
    } else if (line.startsWith('+')) {
      newSeen++;
    }
  }
  expect(oldSeen, oldCount,
      reason: 'old-side line count mismatch for header "${h.header}"');
  expect(newSeen, newCount,
      reason: 'new-side line count mismatch for header "${h.header}"');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseDiffHunks — multi-file, multi-hunk', () {
    const diffText = 'diff --git a/lib/foo.dart b/lib/foo.dart\n'
        'index 111..222 100644\n'
        '--- a/lib/foo.dart\n'
        '+++ b/lib/foo.dart\n'
        '@@ -1,2 +1,2 @@\n'
        '-old1\n'
        '+new1\n'
        ' ctx\n'
        '@@ -10,1 +10,2 @@\n'
        ' ctx2\n'
        '+added2\n'
        'diff --git a/lib/bar.dart b/lib/bar.dart\n'
        'index 333..444 100644\n'
        '--- a/lib/bar.dart\n'
        '+++ b/lib/bar.dart\n'
        '@@ -5,1 +5,1 @@\n'
        '-oldBar\n'
        '+newBar\n';

    test('resolves per-file hunk index resets and correct headers', () {
      final hunks = parseDiffHunks(diffText);
      expect(hunks, hasLength(3));

      expect(hunks[0].filePath, 'lib/foo.dart');
      expect(hunks[0].hunkIndex, 0);
      expect(hunks[0].oldStart, 1);
      expect(hunks[0].newStart, 1);
      expect(hunks[0].additions, 1);
      expect(hunks[0].deletions, 1);

      expect(hunks[1].filePath, 'lib/foo.dart');
      expect(hunks[1].hunkIndex, 1);
      expect(hunks[1].oldStart, 10);
      expect(hunks[1].newStart, 10);
      expect(hunks[1].additions, 1);
      expect(hunks[1].deletions, 0);

      expect(hunks[2].filePath, 'lib/bar.dart');
      expect(hunks[2].hunkIndex, 0); // resets per file
      expect(hunks[2].oldStart, 5);
      expect(hunks[2].newStart, 5);
      expect(hunks[2].additions, 1);
      expect(hunks[2].deletions, 1);

      for (final h in hunks) {
        _expectHeaderMatchesBody(h);
      }
    });

    test('parseDiffHunksForFile scopes to exactly one file, indices intact', () {
      final fooOnly = parseDiffHunksForFile(diffText, 'lib/foo.dart');
      expect(fooOnly, hasLength(2));
      expect(fooOnly.every((h) => h.filePath == 'lib/foo.dart'), isTrue);
      expect(fooOnly[0].hunkIndex, 0);
      expect(fooOnly[1].hunkIndex, 1);

      final barOnly = parseDiffHunksForFile(diffText, 'lib/bar.dart');
      expect(barOnly, hasLength(1));
      expect(barOnly.single.filePath, 'lib/bar.dart');

      expect(parseDiffHunksForFile(diffText, 'lib/nonexistent.dart'), isEmpty);
    });

    test('parsing is deterministic', () {
      final a = parseDiffHunks(diffText).map(_sig).toList();
      final b = parseDiffHunks(diffText).map(_sig).toList();
      expect(a, b);
    });
  });

  group('parseDiffHunks — renames', () {
    test('rename with content change resolves filePath to the NEW (b-side) name', () {
      const diffText = 'diff --git a/lib/old_name.dart b/lib/new_name.dart\n'
          'similarity index 90%\n'
          'rename from lib/old_name.dart\n'
          'rename to lib/new_name.dart\n'
          'index 555..666 100644\n'
          '--- a/lib/old_name.dart\n'
          '+++ b/lib/new_name.dart\n'
          '@@ -1,1 +1,1 @@\n'
          '-oldContent\n'
          '+newContent\n';

      final hunks = parseDiffHunks(diffText);
      expect(hunks, hasLength(1));
      expect(hunks.single.filePath, 'lib/new_name.dart');

      // parseDiffHunksForFile's contract: only the post-rename path matches.
      expect(parseDiffHunksForFile(diffText, 'lib/new_name.dart'), hasLength(1));
      expect(parseDiffHunksForFile(diffText, 'lib/old_name.dart'), isEmpty);
    });

    test('a pure rename (no content change) produces zero hunks', () {
      const diffText = 'diff --git a/lib/moved_a.dart b/lib/moved_b.dart\n'
          'similarity index 100%\n'
          'rename from lib/moved_a.dart\n'
          'rename to lib/moved_b.dart\n';
      expect(parseDiffHunks(diffText), isEmpty);
    });
  });

  group('parseDiffHunks — new / deleted files', () {
    test('a new file diff has additions only, oldStart 0', () {
      const diffText = 'diff --git a/lib/new_file.dart b/lib/new_file.dart\n'
          'new file mode 100644\n'
          'index 000..777\n'
          '--- /dev/null\n'
          '+++ b/lib/new_file.dart\n'
          '@@ -0,0 +1,2 @@\n'
          '+line1\n'
          '+line2\n';
      final hunks = parseDiffHunks(diffText);
      expect(hunks, hasLength(1));
      final h = hunks.single;
      expect(h.filePath, 'lib/new_file.dart');
      expect(h.oldStart, 0);
      expect(h.newStart, 1);
      expect(h.additions, 2);
      expect(h.deletions, 0);
      // /dev/null and the +++ header line are never treated as hunk content.
      expect(h.body, isNot(contains('/dev/null')));
    });

    test('a deleted file diff has deletions only, newStart 0', () {
      const diffText = 'diff --git a/lib/gone.dart b/lib/gone.dart\n'
          'deleted file mode 100644\n'
          'index 888..000\n'
          '--- a/lib/gone.dart\n'
          '+++ /dev/null\n'
          '@@ -1,2 +0,0 @@\n'
          '-line1\n'
          '-line2\n';
      final hunks = parseDiffHunks(diffText);
      expect(hunks, hasLength(1));
      final h = hunks.single;
      expect(h.filePath, 'lib/gone.dart');
      expect(h.oldStart, 1);
      expect(h.newStart, 0);
      expect(h.additions, 0);
      expect(h.deletions, 2);
    });
  });

  group('parseDiffHunks — no-hunk stanzas', () {
    test('a binary-file stanza produces no hunks and does not corrupt the next file', () {
      const diffText = 'diff --git a/assets/img.png b/assets/img.png\n'
          'index 999..aaa 100644\n'
          'Binary files a/assets/img.png and b/assets/img.png differ\n'
          'diff --git a/lib/after.dart b/lib/after.dart\n'
          'index bbb..ccc 100644\n'
          '--- a/lib/after.dart\n'
          '+++ b/lib/after.dart\n'
          '@@ -1,1 +1,1 @@\n'
          '-old\n'
          '+new\n';
      final hunks = parseDiffHunks(diffText);
      expect(hunks, hasLength(1));
      expect(hunks.single.filePath, 'lib/after.dart');
    });

    test('a mode-only change produces no hunks', () {
      const diffText = 'diff --git a/scripts/run.sh b/scripts/run.sh\n'
          'old mode 100644\n'
          'new mode 100755\n';
      expect(parseDiffHunks(diffText), isEmpty);
    });
  });

  group('parseDiffHunks — no newline at end of file', () {
    test('the "\\ No newline" marker is preserved in body but not counted as a change', () {
      const diffText = 'diff --git a/lib/noeol.dart b/lib/noeol.dart\n'
          'index bbb..ccc 100644\n'
          '--- a/lib/noeol.dart\n'
          '+++ b/lib/noeol.dart\n'
          '@@ -1,1 +1,1 @@\n'
          '-oldLine\n'
          r'\ No newline at end of file' '\n'
          '+newLine\n'
          r'\ No newline at end of file' '\n';
      final hunks = parseDiffHunks(diffText);
      expect(hunks, hasLength(1));
      final h = hunks.single;
      expect(h.additions, 1);
      expect(h.deletions, 1);
      expect('\\ No newline at end of file'.allMatches(h.body).length, 2);
    });
  });

  group('parseDiffHunks — CRLF content lines are preserved byte-for-byte', () {
    test('a \\r embedded in +/- content survives into the hunk body', () {
      const diffText = 'diff --git a/lib/crlf.dart b/lib/crlf.dart\n'
          'index abc..def 100644\n'
          '--- a/lib/crlf.dart\n'
          '+++ b/lib/crlf.dart\n'
          '@@ -1,1 +1,1 @@\n'
          '-old line\r\n'
          '+new line\r\n';
      final hunks = parseDiffHunks(diffText);
      expect(hunks, hasLength(1));
      final h = hunks.single;
      expect(h.filePath, 'lib/crlf.dart'); // no stray \r leaking into the path
      expect(h.additions, 1);
      expect(h.deletions, 1);
      expect(h.body, contains('-old line\r'));
      expect(h.body, contains('+new line\r'));
    });
  });

  group('parseDiffHunks — quoted/unicode path integration', () {
    test('a C-quoted unicode diff --git header resolves via the shared decoder', () {
      const diffText = r'diff --git "a/caf\303\251.txt" "b/caf\303\251.txt"' '\n'
          'index fff..000 100644\n'
          r'--- "a/caf\303\251.txt"' '\n'
          r'+++ "b/caf\303\251.txt"' '\n'
          '@@ -1,1 +1,1 @@\n'
          '-old\n'
          '+new\n';
      final hunks = parseDiffHunks(diffText);
      expect(hunks, hasLength(1));
      expect(hunks.single.filePath, 'café.txt');
    });
  });

  // ---------------------------------------------------------------------
  // BUG: a hunk body line whose CONTENT begins with "-- " (two dashes +
  // space) or "++ " (two pluses + space) is indistinguishable, once the
  // diff marker char is prepended, from a "--- a/…" / "+++ b/…" patch
  // header line. parseDiffHunks/parseDiffHunksForFile both unconditionally
  // `continue` on `line.startsWith('--- ')` / `line.startsWith('+++ ')`
  // BEFORE checking whether a hunk is even open, so a removed/added line
  // whose real file content starts that way (a SQL/Lua "--" comment, or
  // any "++ " prefixed text) is silently dropped from both the hunk body
  // AND the additions/deletions count. Left FAILING per instructions —
  // do not weaken these assertions to match the buggy behavior.
  // ---------------------------------------------------------------------
  group('parseDiffHunks — BUG: content lines shaped like patch headers are dropped', () {
    test('a removed line whose content starts with "-- " is dropped mid-hunk', () {
      const diffText = 'diff --git a/notes.sql b/notes.sql\n'
          'index ddd..eee 100644\n'
          '--- a/notes.sql\n'
          '+++ b/notes.sql\n'
          '@@ -1,3 +1,2 @@\n'
          ' keep this\n'
          '--- comment line\n' // removing file content "-- comment line"
          '-second removed\n'
          '+replacement\n';
      final hunks = parseDiffHunks(diffText);
      expect(hunks, hasLength(1));
      final h = hunks.single;
      expect(h.body, contains('--- comment line'),
          reason: 'the removed "-- comment line" must survive in the hunk body');
      expect(h.deletions, 2,
          reason: 'both removed lines must be counted, not just "second removed"');
    });

    test('an added line whose content starts with "++ " is dropped mid-hunk', () {
      const diffText = 'diff --git a/lib/plusplus.dart b/lib/plusplus.dart\n'
          'index 111..222 100644\n'
          '--- a/lib/plusplus.dart\n'
          '+++ b/lib/plusplus.dart\n'
          '@@ -1,1 +1,2 @@\n'
          '-old\n'
          '+++ counter update\n' // adding file content "++ counter update"
          '+second added\n';
      final hunks = parseDiffHunks(diffText);
      expect(hunks, hasLength(1));
      final h = hunks.single;
      expect(h.body, contains('+++ counter update'),
          reason: 'the added "++ counter update" must survive in the hunk body');
      expect(h.additions, 2,
          reason: 'both added lines must be counted, not just "second added"');
    });

    test('parseDiffHunksForFile exhibits the same drop (shared parsing logic)', () {
      const diffText = 'diff --git a/notes.sql b/notes.sql\n'
          'index ddd..eee 100644\n'
          '--- a/notes.sql\n'
          '+++ b/notes.sql\n'
          '@@ -1,3 +1,2 @@\n'
          ' keep this\n'
          '--- comment line\n'
          '-second removed\n'
          '+replacement\n';
      final hunks = parseDiffHunksForFile(diffText, 'notes.sql');
      expect(hunks, hasLength(1));
      expect(hunks.single.body, contains('--- comment line'));
      expect(hunks.single.deletions, 2);
    });
  });

  // ---------------------------------------------------------------------
  // Real-git property check: generate a genuine diff via ScratchRepo and
  // assert the header-vs-body-count law plus the "hunk files ⊆ changed
  // files" law against real `git diff` output (renames included).
  // ---------------------------------------------------------------------
  group('parseDiffHunks — real git ground truth', () {
    test('header counts match body counts on a real two-commit diff, including a rename',
        () async {
      final repo = await ScratchRepo.create(name: 'logos_hunks_more');
      try {
        await repo.writeFile('a.txt', 'line1\nline2\nline3\nline4\nline5\n');
        await repo.writeFile('b.txt', 'unchanged-one\nunchanged-two\n');
        await repo.commitAll('base');

        await repo.writeFile(
            'a.txt', 'line1\nCHANGED-line2\nline3\nline4\nline5\nAPPENDED-line6\n');
        await repo.gitOk(['mv', 'b.txt', 'renamed_b.txt']);
        await repo.commitAll('second');

        final diffResult = await repo.git(['diff', '-M', 'HEAD~1', 'HEAD']);
        expect(diffResult.exitCode, 0, reason: diffResult.stderr.toString());
        final diffText = diffResult.stdout.toString();

        final nameOnly = await repo.gitOk(['diff', '--name-only', '-M', 'HEAD~1', 'HEAD']);
        final changedFiles = nameOnly.split('\n').where((l) => l.isNotEmpty).toSet();

        final hunks = parseDiffHunks(diffText);
        expect(hunks, isNotEmpty);

        // Law: every file that produced a hunk was reported as changed.
        // (The converse need not hold — a pure rename changes no lines.)
        final hunkFiles = hunks.map((h) => h.filePath).toSet();
        for (final f in hunkFiles) {
          expect(changedFiles, contains(f),
              reason: '$f produced a hunk but git diff --name-only did not list it');
        }

        // Law: header counts match body counts, for every hunk.
        for (final h in hunks) {
          _expectHeaderMatchesBody(h);
        }

        // Law: parsing the same text twice is deterministic.
        final again = parseDiffHunks(diffText).map(_sig).toList();
        expect(hunks.map(_sig).toList(), again);
      } finally {
        await repo.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
