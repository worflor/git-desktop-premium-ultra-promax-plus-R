// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'diff_models.dart';

class PatchEngine {
  /// Reconstructs a raw unified patch string from a set of staged lines.
  /// It computes the exact @@ -a,b +c,d @@ headers dynamically so
  /// line staging is completely mathematically verified before git-apply.
  ///
  /// BODY FIRST, HEADERS FROM THE BODY. The file-level headers
  /// (`--- /+++`, `new file mode`) describe what the CONSTRUCTED patch does
  /// — which, under partial staging, is not what the original diff did.
  /// Deriving them from the original diff's meta lines produced two
  /// git-verified data-loss bugs: a whole-file-delete diff with some lines
  /// left unstaged still emitted `+++ /dev/null`, and git silently deleted
  /// the kept lines from the index; a new-file diff never re-emitted
  /// `new file mode`, and git rejected every attempt to stage an untracked
  /// file. So the hunk body is built first, and the headers state only what
  /// it measures: the new side is /dev/null iff the staged patch leaves
  /// zero lines; a new file declares its mode.
  static String buildStagedPatch(String filePath, List<ParsedLine> allLines) {
    // Old/new-side EXISTENCE before this patch comes from the original
    // diff's own meta lines (parseUnifiedDiff preserves them), never from
    // line-number absence: an already-tracked, previously-empty file
    // gaining its first lines has zero old-side line numbers too, but its
    // meta says `--- a/path`, and real `git apply` rejects `--- /dev/null`
    // for a path that already exists.
    final bool isNewFile = allLines.any((l) =>
        l.kind == LineKind.meta &&
        (l.text.startsWith('new file mode') ||
            l.text.trimRight() == '--- /dev/null'));
    final bool isDeletedFile = allLines.any((l) =>
        l.kind == LineKind.meta &&
        (l.text.startsWith('deleted file mode') ||
            l.text.trimRight() == '+++ /dev/null'));
    String newFileMode = '';
    for (final l in allLines) {
      if (l.kind == LineKind.meta && l.text.startsWith('new file mode')) {
        newFileMode = l.text.replaceFirst('new file mode', '').trim();
        break;
      }
    }

    // Group lines into their hunks.
    final Map<int, List<ParsedLine>> hunks = {};
    for (final line in allLines) {
      if (line.hunkIndex < 0) continue; // Skip meta
      hunks.putIfAbsent(line.hunkIndex, () => []).add(line);
    }

    final body = StringBuffer();
    int cumulativeDelta = 0;
    // If no hunk body is written, the patch reduces to its header lines —
    // which `git apply` rejects as "patch with only garbage at line 4".
    // Caller short-circuits on empty input, leaving the file fully
    // unstaged (which is the correct outcome when the user has deselected
    // every actionable line).
    bool wroteAnyHunk = false;
    // Measured across every emitted hunk: what the staged patch leaves on
    // the new side. This — not the original diff's fate — decides whether
    // the header may claim `+++ /dev/null`.
    int newSideTotal = 0;

    // Process each hunk mathematically in isolation.
    final sortedHunkIndices = hunks.keys.toList()..sort();
    for (final idx in sortedHunkIndices) {
      final lines = hunks[idx]!;

      final activeLines = lines.where((l) {
        if (l.kind == LineKind.meta) return false;
        if (l.kind == LineKind.hunk) return false;
        // Patch material must be NUMBERED hunk body. The parser keeps
        // unnumbered context rows for display fidelity (blank lines in
        // `git show` preambles and similar); a patch that counts or
        // prints one desynchronizes the @@ header from the file and
        // git rejects the whole hunk.
        if (l.kind == LineKind.context &&
            l.lineNumOld == null &&
            l.lineNumNew == null) {
          return false;
        }
        if (l.isStaged == false && l.kind == LineKind.context) return true;
        if (l.isStaged == false && l.kind == LineKind.deleted) return true;
        if (l.isStaged == true) return true;
        return false;
      }).toList();

      if (activeLines.isEmpty) continue;

      // Extract the absolute starting locations directly from the original hunk boundary:
      // "@@ -oldStartLine,oldCount +newStartLine,newCount @@"
      int oldStartLine = 1;
      int newStartLine = 1;
      int originalOldCount = 1;
      int originalNewCount = 1;

      try {
        final hunkLine = lines.firstWhere((l) => l.kind == LineKind.hunk);
        final match = RegExp(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')
            .firstMatch(hunkLine.text);
        if (match != null) {
          oldStartLine = int.tryParse(match.group(1) ?? '1') ?? 1;
          originalOldCount = int.tryParse(match.group(2) ?? '1') ?? 1;
          newStartLine = int.tryParse(match.group(3) ?? '1') ?? 1;
          originalNewCount = int.tryParse(match.group(4) ?? '1') ?? 1;
        }
      } catch (_) {
        // Fallback
      }

      newStartLine += cumulativeDelta;

      // Skip hunks where we staged nothing of value.
      // IMPORTANT: We must still update cumulativeDelta for the skipped hunk
      // to "undo" its original net line change.
      bool hasActionableStaged =
          activeLines.any((l) => l.isStaged && l.kind != LineKind.context);
      if (!hasActionableStaged) {
        cumulativeDelta += (originalOldCount - originalNewCount);
        continue;
      }

      int oldLineCount = 0;
      int newLineCount = 0;

      for (final line in activeLines) {
        if (line.kind == LineKind.context ||
            (line.kind == LineKind.deleted && !line.isStaged)) {
          oldLineCount++;
          newLineCount++;
        } else if (line.kind == LineKind.deleted && line.isStaged) {
          oldLineCount++;
        } else if (line.kind == LineKind.added && line.isStaged) {
          newLineCount++;
        }
      }

      // A side's start is 0 only when that side is empty (git's own
      // convention). A whole-file-delete hunk reads `+0,0`; keeping lines
      // under partial staging re-materializes the new side, which then
      // starts at 1.
      if (newLineCount > 0 && newStartLine == 0) newStartLine = 1;
      if (oldLineCount > 0 && oldStartLine == 0) oldStartLine = 1;

      body.writeln(
          '@@ -$oldStartLine,$oldLineCount +$newStartLine,$newLineCount @@');
      wroteAnyHunk = true;
      newSideTotal += newLineCount;

      cumulativeDelta += (newLineCount - originalNewCount);

      for (final line in activeLines) {
        if (line.kind == LineKind.context ||
            (line.kind == LineKind.deleted && !line.isStaged)) {
          // Format as context
          final rawText =
              line.text.startsWith('-') || line.text.startsWith('+')
                  ? ' ${line.text.substring(1)}'
                  : line.text;
          body.writeln(rawText.startsWith(' ') ? rawText : ' $rawText');
        } else if (line.kind == LineKind.deleted && line.isStaged) {
          body.writeln(
              '-${line.text.startsWith('-') ? line.text.substring(1) : line.text}');
        } else if (line.kind == LineKind.added && line.isStaged) {
          body.writeln(
              '+${line.text.startsWith('+') ? line.text.substring(1) : line.text}');
        }
        // If git's unified diff flagged this line as having no trailing
        // newline in its source file, re-emit the `\ No newline at end
        // of file` marker right after it so `git apply` preserves the
        // missing newline instead of silently adding one (which can
        // corrupt formats where the final byte matters).
        if (line.noNewlineAtEof) {
          body.writeln('\\ No newline at end of file');
        }
      }
    }

    if (!wroteAnyHunk) return '';

    final header = StringBuffer();
    header.writeln('diff --git a/$filePath b/$filePath');
    if (isNewFile && !isDeletedFile) {
      // Without this line git rejects the patch with "does not exist in
      // index" — an untracked file cannot be staged by content alone.
      header.writeln('new file mode ${newFileMode.isEmpty ? '100644' : newFileMode}');
      header.writeln('--- /dev/null');
      header.writeln('+++ b/$filePath');
    } else if (isDeletedFile && !isNewFile && newSideTotal == 0) {
      header.writeln('--- a/$filePath');
      header.writeln('+++ /dev/null');
    } else {
      header.writeln('--- a/$filePath');
      header.writeln('+++ b/$filePath');
    }

    return '$header$body';
  }
}
