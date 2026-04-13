enum LineKind { added, deleted, hunk, meta, context }

class ParsedLine {
  final String text;
  final String lowerText;
  final LineKind kind;
  final int? lineNumOld;
  final int? lineNumNew;
  final int hunkIndex;
  final String? filePath;
  final bool isStaged;
  /// True when git emitted `\ No newline at end of file` immediately
  /// after this line in the unified diff. Applies to whichever side
  /// (old or new) this line participates in. Persisted here (rather
  /// than as a standalone `meta` ParsedLine) so the patch engine can
  /// reconstruct the marker after the correct line and the parser
  /// doesn't mistakenly consume a line-number counter for it.
  final bool noNewlineAtEof;

  const ParsedLine({
    required this.text,
    required this.lowerText,
    required this.kind,
    this.lineNumOld,
    this.lineNumNew,
    this.hunkIndex = -1,
    this.filePath,
    this.isStaged = false,
    this.noNewlineAtEof = false,
  });

  ParsedLine copyWith({
    bool? isStaged,
    bool? noNewlineAtEof,
  }) {
    return ParsedLine(
      text: text,
      lowerText: lowerText,
      kind: kind,
      lineNumOld: lineNumOld,
      lineNumNew: lineNumNew,
      hunkIndex: hunkIndex,
      filePath: filePath,
      isStaged: isStaged ?? this.isStaged,
      noNewlineAtEof: noNewlineAtEof ?? this.noNewlineAtEof,
    );
  }

  /// Robust key for re-hydrating staging state after a diff refresh.
  String get stagingKey => '$hunkIndex:$lineNumOld:$lineNumNew:$text';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ParsedLine &&
          stagingKey == other.stagingKey &&
          isStaged == other.isStaged);

  @override
  int get hashCode => stagingKey.hashCode ^ isStaged.hashCode;
}

/// Parse a raw unified-diff string (the kind `git diff` or `gh pr diff`
/// emits) into a flat list of [ParsedLine]s. Each line carries its kind
/// (added / deleted / context / hunk / meta), line numbers, hunk index,
/// and the file path it belongs to (extracted from the `diff --git`
/// header). Multi-file diffs preserve [ParsedLine.filePath] on every
/// line so callers can post-filter by file. Handles `\ No newline at
/// end of file` markers by attaching them to the previous line via
/// [ParsedLine.noNewlineAtEof] without consuming a counter slot.
///
/// This is the canonical parser for the app — used by the changes-panel
/// diff shell, the patch engine, and the PR detail surface so every
/// place that reads a diff sees the exact same model.
List<ParsedLine> parseUnifiedDiff(String diff) {
  final rawLines = diff.split('\n');
  final result = <ParsedLine>[];
  int oldLine = 0, newLine = 0, hunkIdx = -1;
  String? currentFile;

  final diffHeaderRe = RegExp(r'^diff --git a/(.+) b/(.+)$');
  for (final line in rawLines) {
    if (line.startsWith('diff --git')) {
      final m = diffHeaderRe.firstMatch(line);
      if (m != null) currentFile = m.group(2) ?? m.group(1);
      continue;
    }
    if (line.startsWith('diff ') || line.startsWith('index ')) {
      continue;
    }
    if (line.startsWith('@@')) {
      final m =
          RegExp(r'@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@').firstMatch(line);
      if (m != null) {
        oldLine = int.tryParse(m.group(1)!) ?? 0;
        newLine = int.tryParse(m.group(2)!) ?? 0;
      }
      hunkIdx++;
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.hunk,
          hunkIndex: hunkIdx,
          filePath: currentFile));
    } else if (line.startsWith('+') && !line.startsWith('+++')) {
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.added,
          lineNumNew: newLine++,
          hunkIndex: hunkIdx,
          filePath: currentFile));
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.deleted,
          lineNumOld: oldLine++,
          hunkIndex: hunkIdx,
          filePath: currentFile));
    } else if (line.startsWith('\\')) {
      // `\ No newline at end of file` — attach the flag to the prior
      // line. See ParsedLine.noNewlineAtEof for the full reasoning.
      if (result.isNotEmpty) {
        final prev = result.removeLast();
        result.add(prev.copyWith(noNewlineAtEof: true));
      }
    } else if (line.startsWith('new file mode ') ||
        line.startsWith('deleted file mode ') ||
        line.startsWith('old mode ') ||
        line.startsWith('new mode ') ||
        line.startsWith('similarity index ') ||
        line.startsWith('rename from ') ||
        line.startsWith('rename to ') ||
        line.startsWith('Binary files ') ||
        line.startsWith('GIT binary patch') ||
        line.startsWith('--- ') ||
        line.startsWith('+++ ')) {
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.meta,
          filePath: currentFile));
    } else if (line.isNotEmpty) {
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.context,
          lineNumOld: oldLine++,
          lineNumNew: newLine++,
          hunkIndex: hunkIdx,
          filePath: currentFile));
    } else {
      result.add(ParsedLine(
          text: line,
          lowerText: '',
          kind: LineKind.context,
          hunkIndex: hunkIdx));
    }
  }

  return result;
}

/// Returns the index of the paired add/delete line for an edit-in-place,
/// or null if there is no pair. A pair is a deletion immediately followed
/// by an addition (or vice-versa) within the same hunk — the standard
/// shape of a single-line modification in a unified diff.
int? findReplacementPair(List<ParsedLine> lines, int index) {
  if (index < 0 || index >= lines.length) return null;
  final here = lines[index];
  if (here.kind != LineKind.added && here.kind != LineKind.deleted) return null;

  if (here.kind == LineKind.deleted) {
    final next = index + 1 < lines.length ? lines[index + 1] : null;
    if (next != null &&
        next.kind == LineKind.added &&
        next.hunkIndex == here.hunkIndex) {
      return index + 1;
    }
  } else {
    final prev = index - 1 >= 0 ? lines[index - 1] : null;
    if (prev != null &&
        prev.kind == LineKind.deleted &&
        prev.hunkIndex == here.hunkIndex) {
      return index - 1;
    }
  }
  return null;
}

class DiffStats {
  final int adds;
  final int dels;
  final int hunks;

  const DiffStats({this.adds = 0, this.dels = 0, this.hunks = 0});

  static DiffStats fromLines(List<ParsedLine> lines) {
    int a = 0;
    int d = 0;
    int h = lines.where((l) => l.kind == LineKind.hunk).length;
    for (final l in lines) {
      if (l.kind == LineKind.added) a++;
      if (l.kind == LineKind.deleted) d++;
    }
    return DiffStats(adds: a, dels: d, hunks: h);
  }

  static DiffStats fromRawDiff(String diff) {
    int a = 0;
    int d = 0;
    int h = 0;
    for (final line in diff.split('\n')) {
      if (line.startsWith('@@ ')) {
        h++;
      } else if (line.startsWith('+') && !line.startsWith('+++')) {
        a++;
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        d++;
      }
    }
    return DiffStats(adds: a, dels: d, hunks: h);
  }
}
