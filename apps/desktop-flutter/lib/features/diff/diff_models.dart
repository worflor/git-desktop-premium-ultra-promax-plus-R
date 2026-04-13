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
