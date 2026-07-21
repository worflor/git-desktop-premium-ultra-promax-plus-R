// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Differential agreement between the TWO independent unified-diff parsers.
//
// The app has two parsers that both must classify a hunk-body line as
// add/delete/context and, crucially, must NOT mistake a content line whose
// text begins `++`/`--` (rendering as `+++ …`/`--- …`, ordinary C `++i;` /
// SQL `-- comment`) for a `+++ b/path`/`--- a/path` file header:
//
//   - `parseUnifiedDiff` / `DiffStats.fromRawDiff` / `sliceDiffByFile`
//     (lib/features/diff/diff_models.dart) — the canonical UI parser, which
//     shares one `_HunkCursor` (the @@ body-budget counter) across all three.
//   - `parseDiffHunks` / `parseDiffHunksForFile`
//     (lib/backend/logos_hunks.dart) — the hunk-ranking parser, a SEPARATE
//     implementation.
//
// Both had the same prefix-vs-content bug and were fixed independently. A
// code review flagged the obvious hazard: the two can DRIFT — one regresses
// on `++`/`--` body lines while the other doesn't — and nothing would catch
// it. This file is that catch. It feeds the same diffs to both and asserts
// they agree on the ONE observable both expose: the add/delete line counts.
// If either parser starts dropping or mis-binding a `+++ `/`--- ` body line,
// its count diverges from the other's and this test fails at the exact diff
// that broke them.
//
// The counts are a faithful proxy: a body line dropped as a "header" is a
// line NOT counted as an add/delete, so a drift on exactly the ambiguous
// shapes this guards shows up as a count mismatch. Real git diffs (via
// ScratchRepo) and hand-built hostile diffs both feed the comparison, plus a
// fuzz sweep over generated multi-line edits.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_hunks.dart' show parseDiffHunks;
import 'package:git_desktop/features/diff/diff_models.dart';

import '../support/gen.dart';
import '../support/prop.dart';
import '../support/scratch_repo.dart';

/// (adds, dels) as counted by the canonical parser (parseUnifiedDiff).
(int, int) _viaParseUnified(String diff) {
  final lines = parseUnifiedDiff(diff);
  var adds = 0, dels = 0;
  for (final l in lines) {
    if (l.kind == LineKind.added) adds++;
    if (l.kind == LineKind.deleted) dels++;
  }
  return (adds, dels);
}

/// (adds, dels) as counted by DiffStats — the third consumer of _HunkCursor.
(int, int) _viaDiffStats(String diff) {
  final s = DiffStats.fromRawDiff(diff);
  return (s.adds, s.dels);
}

/// (adds, dels) as counted by the SEPARATE hunk-ranking parser.
(int, int) _viaLogosHunks(String diff) {
  final hunks = parseDiffHunks(diff);
  var adds = 0, dels = 0;
  for (final h in hunks) {
    adds += h.additions;
    dels += h.deletions;
  }
  return (adds, dels);
}

/// Asserts all three parsers agree on the add/delete counts for [diff].
void _expectAgreement(String diff, {String? because}) {
  final unified = _viaParseUnified(diff);
  final stats = _viaDiffStats(diff);
  final hunks = _viaLogosHunks(diff);
  final ctx = because == null ? '' : '\n$because';
  expect(stats, unified,
      reason: 'DiffStats.fromRawDiff disagrees with parseUnifiedDiff on '
          '(adds,dels): stats=$stats unified=$unified. Both share _HunkCursor '
          'in diff_models.dart — a divergence means one path stopped using '
          'the shared body-budget cursor.$ctx\n--- diff ---\n$diff');
  expect(hunks, unified,
      reason: 'logos_hunks.parseDiffHunks disagrees with '
          'parseUnifiedDiff on (adds,dels): hunks=$hunks unified=$unified. The '
          'two diff parsers have DRIFTED — most likely one regressed on a '
          '`++`/`--`-content line (rendered `+++ `/`--- `) being read as a '
          'file header instead of hunk body. Re-align them (see _HunkCursor '
          'in diff_models.dart and the hunkBuf==null guard in '
          'logos_hunks.dart).$ctx\n--- diff ---\n$diff');
}

/// Builds a real unified diff for one file by committing [before] then
/// writing [after], via git itself — so the input is exactly what the app
/// parses in production, not a hand-forged approximation.
Future<String> _realDiff(ScratchRepo repo, String path, String before,
    String after) async {
  await repo.writeFile(path, before);
  await repo.stageAll();
  await repo.gitOk(['commit', '-m', 'base', '--allow-empty']);
  await repo.writeFile(path, after);
  final r = await repo.git(['diff', '--', path]);
  return r.stdout as String;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('two diff parsers agree on add/delete counts (drift guard)', () {
    // The discriminating cases — content lines whose text begins with the
    // exact prefixes that render as `+++ `/`--- ` / `++`/`--`. A parser that
    // reads any of these as a header (the bug both had) undercounts.
    const hostileDiffs = <String, String>{
      'added ++i (C increment)': '''
diff --git a/f.c b/f.c
index 1111111..2222222 100644
--- a/f.c
+++ b/f.c
@@ -1,1 +1,2 @@
 int main() {
+++i;
''',
      'deleted -- comment (SQL)': '''
diff --git a/q.sql b/q.sql
index 1111111..2222222 100644
--- a/q.sql
+++ b/q.sql
@@ -1,2 +1,1 @@
 SELECT 1;
--- old comment
''',
      'added ++ with space (looks like +++ header)': '''
diff --git a/x b/x
index 1111111..2222222 100644
--- a/x
+++ b/x
@@ -1,1 +1,2 @@
 ctx
+++ counter update note
''',
      'deleted -- with space (looks like --- header)': '''
diff --git a/y b/y
index 1111111..2222222 100644
--- a/y
+++ b/y
@@ -1,2 +1,1 @@
 ctx
--- comment line removed
''',
      'both ++ and -- content in one hunk': '''
diff --git a/z b/z
index 1111111..2222222 100644
--- a/z
+++ b/z
@@ -1,2 +1,2 @@
--- was a comment
+++i = 0;
''',
    };

    hostileDiffs.forEach((name, diff) {
      test('agree: $name', () => _expectAgreement(diff, because: name));
    });

    test('agree on a real git diff with ++/-- content lines', () async {
      final repo = await ScratchRepo.create(name: 'diff_agreement_real');
      addTearDown(repo.dispose);
      // `before` has a `-- ` line that gets deleted; `after` adds a `++` line.
      const before = 'line one\n-- sql style comment\nline three\n';
      const after = 'line one\n++i; // c increment\nline three\nextra\n';
      final diff = await _realDiff(repo, 'src/mix.txt', before, after);
      expect(diff, isNotEmpty);
      _expectAgreement(diff, because: 'real git diff');
    });

    test('agree across a multi-file real diff', () async {
      final repo = await ScratchRepo.create(name: 'diff_agreement_multi');
      addTearDown(repo.dispose);
      await repo.writeFile('a.c', 'int x;\n');
      await repo.writeFile('b.sql', 'select 1;\n');
      await repo.stageAll();
      await repo.gitOk(['commit', '-m', 'seed']);
      await repo.writeFile('a.c', 'int x;\n++x;\n');
      await repo.writeFile('b.sql', 'select 1;\n-- note\n');
      final r = await repo.git(['diff']);
      final diff = r.stdout as String;
      expect(diff, isNotEmpty);
      _expectAgreement(diff, because: 'multi-file real diff');
    });

    test('fuzz: generated real diffs never make the two parsers disagree',
        () async {
      final repo = await ScratchRepo.create(name: 'diff_agreement_fuzz');
      addTearDown(repo.dispose);
      var caseId = 0;
      // Draw two multi-line blobs; the generator's ASCII pool naturally
      // produces lines beginning with '+'/'-'/'+++'/'---' etc., and CRLF /
      // no-trailing-newline shapes, which is exactly the parser stress we
      // want the two implementations to survive identically.
      final gen = genMultilineText(maxLines: 8);
      await forAllAsync<(String, String)>(
        (rng) => (gen(rng), gen(rng)),
        count: 25,
        seed: 0xD1FF,
        describe: 'diff parser agreement',
        check: (pair) async {
          final (before, after) = pair;
          if (before == after) return;
          final id = caseId++;
          final diff =
              await _realDiff(repo, 'fuzz/f$id.txt', before, after);
          if (diff.isEmpty) return;
          _expectAgreement(diff, because: 'fuzz case $id');
        },
      );
    });
  });
}
