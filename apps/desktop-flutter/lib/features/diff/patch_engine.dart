import 'diff_models.dart';

class PatchEngine {
  /// Reconstructs a raw unified patch string from a set of staged lines.
  /// It computes the exact @@ -a,b +c,d @@ headers dynamically so
  /// line staging is completely mathematically verified before git-apply.
  static String buildStagedPatch(String filePath, List<ParsedLine> allLines) {
    bool isNewFile = !allLines.any((l) => l.lineNumOld != null && l.kind != LineKind.meta);
    bool isDeletedFile = !allLines.any((l) => l.lineNumNew != null && l.kind != LineKind.meta);

    final builder = StringBuffer();
    builder.writeln('diff --git a/$filePath b/$filePath');

    if (isNewFile && !isDeletedFile) {
      builder.writeln('--- /dev/null');
      builder.writeln('+++ b/$filePath');
    } else if (isDeletedFile && !isNewFile) {
      builder.writeln('--- a/$filePath');
      builder.writeln('+++ /dev/null');
    } else {
      builder.writeln('--- a/$filePath');
      builder.writeln('+++ b/$filePath');
    }

    // Group lines into their hunks.
    final Map<int, List<ParsedLine>> hunks = {};
    for (final line in allLines) {
      if (line.hunkIndex < 0) continue; // Skip meta
      hunks.putIfAbsent(line.hunkIndex, () => []).add(line);
    }

    int cumulativeDelta = 0;

    // Process each hunk mathematically in isolation.
    final sortedHunkIndices = hunks.keys.toList()..sort();
    for (final idx in sortedHunkIndices) {
      final lines = hunks[idx]!;

      final activeLines = lines.where((l) {
        if (l.kind == LineKind.meta) return false;
        if (l.kind == LineKind.hunk) return false;
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
        final match = RegExp(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@').firstMatch(hunkLine.text);
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
      bool hasActionableStaged = activeLines.any((l) => l.isStaged && l.kind != LineKind.context);
      if (!hasActionableStaged) {
          cumulativeDelta += (originalOldCount - originalNewCount);
          continue;
      }

      int oldLineCount = 0;
      int newLineCount = 0;

      for (final line in activeLines) {
        if (line.kind == LineKind.context || (line.kind == LineKind.deleted && !line.isStaged)) {
          oldLineCount++;
          newLineCount++;
        } else if (line.kind == LineKind.deleted && line.isStaged) {
          oldLineCount++;
        } else if (line.kind == LineKind.added && line.isStaged) {
          newLineCount++;
        }
      }

      builder.writeln('@@ -$oldStartLine,$oldLineCount +$newStartLine,$newLineCount @@');

      cumulativeDelta += (newLineCount - originalNewCount);

      for (final line in activeLines) {
        if (line.kind == LineKind.context || (line.kind == LineKind.deleted && !line.isStaged)) {
          // Format as context
          final rawText = line.text.startsWith('-') || line.text.startsWith('+') ? ' ' + line.text.substring(1) : line.text;
          builder.writeln(rawText.startsWith(' ') ? rawText : ' ' + rawText);
        } else if (line.kind == LineKind.deleted && line.isStaged) {
          builder.writeln('-' + (line.text.startsWith('-') ? line.text.substring(1) : line.text));
        } else if (line.kind == LineKind.added && line.isStaged) {
          builder.writeln('+' + (line.text.startsWith('+') ? line.text.substring(1) : line.text));
        }
        // If git's unified diff flagged this line as having no trailing
        // newline in its source file, re-emit the `\ No newline at end
        // of file` marker right after it so `git apply` preserves the
        // missing newline instead of silently adding one (which can
        // corrupt formats where the final byte matters).
        if (line.noNewlineAtEof) {
          builder.writeln('\\ No newline at end of file');
        }
      }
    }

    return builder.toString();
  }
}
