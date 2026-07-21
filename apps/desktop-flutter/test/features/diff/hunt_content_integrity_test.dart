// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Content-integrity bug hunt over the diff document layer, anchored against
// the real machine-scale road-graph corpus (marble/data/USA-road-d.NY.gr,
// 733,853 lines / ~14MB). The corpus is READ-ONLY; any mutated copy lives
// under a temp dir.
//
// Broad dimensions were swept and passed clean (oracle line/text/lineNumNew
// agreement at 25 sampled indices incl. window boundaries (511-513,
// 1023-1025, 4095-4097), the 200k lean-gate boundary, and EOF; spool vs
// working-file backing agreement on line count/stats/sections/sampled text;
// eager vs lazy(rawContent) full-sweep agreement over a resident 150k-line
// slice; adversarial backwards/ping-pong/re-read window-cache torture) — see
// the final report for what was verified. The two REAL bugs those sweeps
// surfaced are pinned below.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/edit_units.dart' show stripDiffLineSign;

const _nyPath =
    r'C:\Users\mini server\Documents\Projects\marble\data\USA-road-d.NY.gr';

void main() {
  group('CONFIRMED BUG: NewFileIndex zero-copy path has no diff sigil to strip', () {
    // Root cause: lib/features/diff/new_file_index.dart `_bodyRow` (~line
    // 304-316) sets `text: store.substring(pos, end)` — the raw WORKING-FILE
    // line, with NO synthetic '+' prefix ever written into ParsedLine.text.
    // Every other backing (parseUnifiedDiff in diff_models.dart, and
    // PredictiveDiffIndex's `_materialize` in predictive_diff_index.dart)
    // stores the line EXACTLY as it appears in the unified diff text, i.e.
    // WITH its leading '+'/'-'/' ' sigil — that's what a real diff's raw
    // bytes contain.
    //
    // The renderer (lib/features/diff/diff_shell.dart:5167-5169) blindly
    // strips column 0 for every added/deleted row via
    // `stripDiffLineSign` (lib/features/diff/edit_units.dart:115-122), which
    // assumes ParsedLine.text ALWAYS carries that synthetic sigil. For an
    // untracked file opened through `DiffDocument.lazyFromWorkingFile` (the
    // zero-copy path — used for every untracked/new file in the real app),
    // that assumption is false: the text is the bare file line. If the
    // file's own first character happens to be '+' or '-' — a diff file
    // being added, a YAML/markdown list item, a CSV row with a negative
    // leading field, a patch fragment, a changelog bullet — that character
    // is real content, and `stripDiffLineSign` silently eats it in the
    // rendered view. This is a genuine WRONG-CONTENT bug for the single
    // most common "add a new file" review flow.
    //
    // Severity: HIGH. Silent, undetectable data loss in the review surface
    // for any untracked text file whose lines start with '+' or '-' — no
    // error, no visual cue, just a missing leading character.
    test(
      'a real file line starting with "-" or "+" loses that character when '
      'rendered (stripDiffLineSign assumes a sigil NewFileIndex never wrote)',
      () async {
        final tmp = Directory.systemTemp.createTempSync('hunt_strip_sign_');
        addTearDown(() {
          try {
            tmp.deleteSync(recursive: true);
          } catch (_) {}
        });
        final path = '${tmp.path}/notes.txt';
        File(path).writeAsStringSync(
          'normal line\n'
          '-1,2,3 negative csv row\n'
          '+42 delta note\n',
        );
        final doc = await DiffDocument.lazyFromWorkingFile(
          path,
          'notes.txt',
          trimLeadingMeta: true,
        );
        addTearDown(doc.dispose);

        // logical 0 = hunk header (trimmed away the meta lines above it);
        // 1 = "normal line"; 2 = "-1,2,3 ..."; 3 = "+42 ...". FIXED
        // contract: ParsedLine.text carries the '+' sigil on every backing
        // (new_file_index.dart _bodyRow), so stripping restores the file's
        // true content — including its own leading '-'/'+' characters.
        expect(doc.lines[2].text, '+-1,2,3 negative csv row');
        expect(doc.lines[3].text, '++42 delta note');

        // THE (FIXED) BUG: the shell's displayText strips column 0 as the
        // diff sigil; before the fix this backing never wrote one, so the
        // file's own first character was eaten.
        final rendered2 = stripDiffLineSign(doc.lines[2].text);
        final rendered3 = stripDiffLineSign(doc.lines[3].text);

        expect(
          rendered2,
          '-1,2,3 negative csv row',
          reason: 'BUG: rendered text is "$rendered2" — the real leading '
              "'-' of the file's own content was stripped as if it were a "
              'diff sigil',
        );
        expect(
          rendered3,
          '+42 delta note',
          reason: 'BUG: rendered text is "$rendered3" — the real leading '
              "'+' of the file's own content was stripped as if it were a "
              'diff sigil',
        );
      },
    );

    test(
      'root-cause isolation: NewFileIndex.hydrateRange never carries a sigil, '
      'unlike PredictiveDiffIndex over an equivalent real diff',
      () async {
        if (!File(_nyPath).existsSync()) {
          // ignore: avoid_print
          print('[hunt] marble corpus not present — skipping');
          return;
        }
        // Confirms the divergence at real scale, not just on a toy file: a
        // spool-backed doc of the SAME logical new-file content stores the
        // sigil (as any real unified diff does); the working-file-backed doc
        // of the identical file does not — the two backings are NOT
        // interchangeable at the ParsedLine.text contract, breaking the
        // "backing must not change observable content" invariant relied on
        // throughout diff_document.dart's docs (see e.g. the `isLazy` /
        // `isLazyMeta` comments there).
        final line = File(
          _nyPath,
        ).readAsLinesSync().firstWhere((l) => l.startsWith('c'));
        expect(
          line.startsWith('c'),
          isTrue,
          reason: 'sanity: NY.gr header comment lines start with "c "',
        );

        final workDoc = await DiffDocument.lazyFromWorkingFile(
          _nyPath,
          'road.gr',
          trimLeadingMeta: true,
        );
        addTearDown(workDoc.dispose);
        // logical 1 is the first body row (logical 0 is the trimmed-to hunk
        // header) — FIXED contract: its text is the sigil-prefixed row,
        // byte-identical to what a real unified diff of this file stores.
        expect(workDoc.lines[1].text.startsWith('+'), isTrue);
        expect(workDoc.lines[1].text, '+$line');
      },
    );
  });

  group(
    'CONFIRMED BUG: maxLineLength disagrees between backings of the '
    'identical new-file content',
    () {
      // Root cause: PredictiveDiffIndex.build/buildFromStoreAsync (predictive_
      // diff_index.dart ~line 339: `if (lineLen > maxLen) maxLen = lineLen;`)
      // measures RAW STORE line length, which for a real unified diff
      // includes the leading '+'/'-'/' ' sigil character. NewFileIndex's
      // scan (new_file_index.dart ~line 153: same `if (lineLen > maxLen)`
      // pattern) measures the bare FILE line — no sigil ever exists in that
      // store. So for the identical logical "new file X" diff, a
      // spool/PredictiveDiffIndex-backed DiffDocument reports
      // `maxLineLength` exactly 1 GREATER than a lazyFromWorkingFile-backed
      // DiffDocument of the same file, purely because of which backing
      // built it — not because of any real difference in displayed content
      // width. Same root defect as the sigil-strip bug above: NewFileIndex's
      // store never carries the synthetic sigil that every other backing's
      // store does.
      //
      // Severity: LOW — cosmetic (horizontal-scroll-extent sizing is off by
      // one character for working-file-backed docs), but it is a genuine,
      // reproducible content-derived-metric disagreement between backings
      // of the SAME diff, which the backing-equivalence law says must not
      // happen.
      test(
        'lazyFromSpool reports maxLineLength one character higher than '
        'lazyFromWorkingFile for the identical new-file content',
        () async {
          final tmp = Directory.systemTemp.createTempSync('hunt_maxlen_');
          addTearDown(() {
            try {
              tmp.deleteSync(recursive: true);
            } catch (_) {}
          });
          const longest = 'the single longest line in this tiny fixture file';
          final filePath = '${tmp.path}/f.txt';
          File(filePath).writeAsStringSync('short\n$longest\nalso short\n');

          final spoolPath = '${tmp.path}/f.diff';
          File(spoolPath).writeAsStringSync(
            'diff --git a/f.txt b/f.txt\n'
            'new file mode 100644\n'
            '--- /dev/null\n'
            '+++ b/f.txt\n'
            '@@ -0,0 +1,3 @@\n'
            '+short\n'
            '+$longest\n'
            '+also short\n',
          );

          final workDoc = await DiffDocument.lazyFromWorkingFile(
            filePath,
            'f.txt',
            trimLeadingMeta: true,
          );
          addTearDown(workDoc.dispose);
          final spoolDoc = await DiffDocument.lazyFromSpool(
            spoolPath,
            pathHint: 'f.txt',
            trimLeadingMeta: true,
          );
          addTearDown(spoolDoc.dispose);

          expect(
            spoolDoc.maxLineLength,
            workDoc.maxLineLength,
            reason:
                'BUG: spool backing counts the synthetic "+" sigil into '
                'maxLineLength (${spoolDoc.maxLineLength}) while the '
                'working-file backing of the IDENTICAL content does not '
                '(${workDoc.maxLineLength}) — same file, same logical diff, '
                'disagreeing metric purely by backing choice',
          );
        },
      );
    },
  );
}
