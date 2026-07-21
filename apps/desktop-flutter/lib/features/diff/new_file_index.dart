// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// NewFileIndex — the zero-copy path for an UNTRACKED file's diff.
//
// An untracked file's diff is a pure function of the file: a "new file" header
// followed by every line as an addition. So instead of reading the file into
// RAM (the marble OOM) or spooling git's `--no-index` output to a second copy on
// disk, we back the diff DIRECTLY with a [FileByteStore] over the working-tree
// file and synthesize the diff on the fly: the header rows live in RAM (five
// tiny strings), and every body row is that file line, classified as added,
// read from the page cache on demand. The file already on disk — held by the OS
// page cache — IS the data structure. Resident RAM = the sparse line-offset
// index + a bounded page cache + the viewport, independent of file size.
//
// Binary files collapse to the usual "Binary files … differ" marker (probed
// from the first page — never the whole file).

import 'dart:async';

import 'package:meta/meta.dart';

import 'byte_store.dart';
import 'diff_models.dart';
import 'predictive_diff_index.dart'
    show DiffLineIndex, PredictiveFile, PredictiveHunk;

/// A byte this-far into the file gets a line-offset anchor, OR every
/// [_lineAnchorSpacing] lines — whichever first (dual bound, giant-line safe).
const int _byteAnchorSpacing = 512 * 1024;
const int _lineAnchorSpacing = 4096;
const int _yieldEvery = 60000;
const int _binaryProbeBytes = 8192;

class NewFileIndex implements DiffLineIndex {
  /// The store IS the raw working-tree file — its bytes are file CONTENTS,
  /// not unified-diff text (the diff shape is synthesized at hydrate time).
  @override
  bool get storeHoldsUnifiedDiff => false;

  @override
  final ByteStore store;

  final String _displayPath;
  final int _len; // bytes in the file
  final bool _endsWithNewline;

  /// Header rows shown before the body (the `diff --git`/`new file`/`@@` block,
  /// or the binary marker). Small, fully resident.
  final List<ParsedLine> _header;

  /// Number of body (file) lines. Zero for empty or binary files.
  final int _fileLineCount;

  /// Dual-bound anchors into the FILE: `_anchorByte[a]` is the byte offset of
  /// the file line whose ordinal is `_anchorLine[a]`. Binary-searched on seek.
  final List<int> _anchorByte;
  final List<int> _anchorLine;

  @override
  final int maxLineLength;
  @override
  final bool isBinary;

  @override
  int get leadingMetaCount =>
      _header.takeWhile((line) => line.kind == LineKind.meta).length;

  @override
  List<PredictiveFile> get files => [
    // An untracked working file IS a new file: no committed ancestor exists,
    // so ancestry-dependent features (blame) must skip it.
    PredictiveFile(_displayPath, 0, isBinary: isBinary, isNewFile: true),
  ];

  NewFileIndex._(
    this.store,
    this._displayPath,
    this._len,
    this._endsWithNewline,
    this._header,
    this._fileLineCount,
    this._anchorByte,
    this._anchorLine,
    this.maxLineLength,
    this.isBinary,
  );

  /// Build over the working-tree file at [workingPath], presented at
  /// [displayPath] (the repo-relative, forward-slash path). Cooperative: yields
  /// while scanning so a giant file never freezes the UI.
  static Future<NewFileIndex> build(
    String workingPath,
    String displayPath,
  ) async {
    final store = FileByteStore.open(workingPath);
    try {
      return await _buildOver(store, displayPath);
    } catch (_) {
      // A failed scan must not strand the open handle — on Windows it would
      // also block the file's later deletion/rename by the user.
      store.dispose();
      rethrow;
    }
  }

  static Future<NewFileIndex> _buildOver(
    FileByteStore store,
    String displayPath,
  ) async {
    final len = store.length;

    // Binary probe: NUL in the first page → treat as binary (marker only).
    var binary = false;
    final probeEnd = len < _binaryProbeBytes ? len : _binaryProbeBytes;
    for (var i = 0; i < probeEnd; i++) {
      if (store.unitAt(i) == 0) {
        binary = true;
        break;
      }
    }

    if (binary || len == 0) {
      final header = _binaryOrEmptyHeader(displayPath, binary);
      return NewFileIndex._(
        store,
        displayPath,
        len,
        len > 0,
        header,
        0,
        const [0],
        const [0],
        0,
        binary,
      );
    }

    // Scan the file for line boundaries, dual-bound anchors, max line length.
    final anchorByte = <int>[];
    final anchorLine = <int>[];
    var pos = 0, lineCount = 0, maxLen = 0;
    var lastAnchorLine = 0, lastAnchorByte = 0, sinceYield = 0;
    while (pos < len) {
      if (anchorByte.isEmpty ||
          lineCount - lastAnchorLine >= _lineAnchorSpacing ||
          pos - lastAnchorByte >= _byteAnchorSpacing) {
        anchorByte.add(pos);
        anchorLine.add(lineCount);
        lastAnchorLine = lineCount;
        lastAnchorByte = pos;
      }
      final nl = store.indexOfNewline(pos);
      final end = nl < 0 ? len : nl;
      // +1: rows hydrate with their '+' sigil (see _bodyRow), and this
      // length feeds scroll-extent sizing — measure the row as rendered so
      // all backings agree on maxLineLength for identical content.
      final lineLen = end - pos + 1;
      if (lineLen > maxLen) maxLen = lineLen;
      lineCount++;
      if (nl < 0) {
        pos = len;
        break;
      }
      pos = nl + 1;
      if (++sinceYield >= _yieldEvery) {
        sinceYield = 0;
        await Future<void>.delayed(Duration.zero);
      }
    }
    final endsWithNewline = store.unitAt(len - 1) == kNewlineByte;

    final header = _newFileHeader(displayPath, lineCount);
    return NewFileIndex._(
      store,
      displayPath,
      len,
      endsWithNewline,
      header,
      lineCount,
      anchorByte,
      anchorLine,
      maxLen,
      false,
    );
  }

  int get _headerCount => _header.length;

  static List<ParsedLine> _newFileHeader(String path, int lineCount) => [
    ParsedLine(
      text: 'diff --git a/$path b/$path',
      kind: LineKind.meta,
      hunkIndex: -1,
      filePath: path,
    ),
    ParsedLine(
      text: 'new file mode 100644',
      kind: LineKind.meta,
      hunkIndex: -1,
      filePath: path,
    ),
    ParsedLine(
      text: '--- /dev/null',
      kind: LineKind.meta,
      hunkIndex: -1,
      filePath: path,
    ),
    ParsedLine(
      text: '+++ b/$path',
      kind: LineKind.meta,
      hunkIndex: -1,
      filePath: path,
    ),
    ParsedLine(
      text: '@@ -0,0 +1,$lineCount @@',
      kind: LineKind.hunk,
      hunkIndex: 0,
      filePath: path,
    ),
  ];

  /// Header-only synthetic sections for binary and empty files. This is NOT
  /// a divergence from unified-diff shape — it is git's own canonical form,
  /// verified empirically: `git diff --no-index -- /dev/null <empty file>`
  /// emits exactly `diff --git` + `new file mode` + `index` with no
  /// `---`/`+++` pair and no hunk, and binary sections likewise carry only
  /// headers plus the `Binary files … differ` marker. Downstream features
  /// handle header-only sections structurally (meta-only trim guard,
  /// construction-time isNewFile, hunkless section anchors).
  static List<ParsedLine> _binaryOrEmptyHeader(String path, bool binary) => [
    ParsedLine(
      text: 'diff --git a/$path b/$path',
      kind: LineKind.meta,
      hunkIndex: -1,
      filePath: path,
    ),
    ParsedLine(
      text: 'new file mode 100644',
      kind: LineKind.meta,
      hunkIndex: -1,
      filePath: path,
    ),
    if (binary)
      ParsedLine(
        text: 'Binary files /dev/null and b/$path differ',
        kind: LineKind.meta,
        hunkIndex: -1,
        filePath: path,
      ),
  ];

  @override
  int get lineCount => _headerCount + _fileLineCount;

  @override
  int get adds => _fileLineCount;

  @override
  int get dels => 0;

  @override
  List<PredictiveHunk> get hunks {
    if (_fileLineCount == 0) return const [];
    // One hunk at the `@@` row (display index 4), adds = every file line.
    return [
      PredictiveHunk(
          4,
          0,
          1,
          0,
          _fileLineCount,
          '@@ -0,0 +1,$_fileLineCount @@',
          _displayPath,
        )
        ..adds = _fileLineCount
        ..dels = 0,
    ];
  }

  /// Anchor index whose file line is ≤ [fileLine] (binary search).
  int _anchorForFileLine(int fileLine) {
    var lo = 0, hi = _anchorLine.length - 1, ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_anchorLine[mid] <= fileLine) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  /// Byte offset where file line [fileLine] begins (replay from nearest anchor).
  int _byteOfFileLine(int fileLine) {
    final a = _anchorForFileLine(fileLine);
    var pos = _anchorByte[a];
    var line = _anchorLine[a];
    while (line < fileLine && pos < _len) {
      final nl = store.indexOfNewline(pos);
      if (nl < 0) return _len;
      pos = nl + 1;
      line++;
    }
    return pos;
  }

  ParsedLine _bodyRow(int fileLine, int pos, int end, bool isLast) {
    // The '+' sigil upholds the universal ParsedLine invariant: on
    // added/deleted rows, `text` is the raw unified-diff row (sigil +
    // content), exactly as every parser backing stores it. The renderer and
    // the patch engine both strip column 0 on that assumption — a bare
    // working-file line here silently ate the first character of any line
    // that itself starts with '+'/'-' (CSV negatives, markdown bullets),
    // on screen AND in staged patches. Hydration already allocates a fresh
    // substring per viewport row, so the prefix costs one concat, not the
    // zero-copy design.
    var row = ParsedLine(
      text: '+${store.substring(pos, end)}',
      kind: LineKind.added,
      lineNumNew: fileLine + 1,
      hunkIndex: 0,
      filePath: _displayPath,
    );
    if (isLast && !_endsWithNewline) {
      row = row.copyWith(noNewlineAtEof: true);
    }
    return row;
  }

  @override
  List<ParsedLine> hydrateRange(int start, int count) {
    if (start < 0) start = 0;
    final total = lineCount;
    if (start >= total || count <= 0) return const [];
    final end = (start + count) > total ? total : start + count;

    final out = <ParsedLine>[];
    var i = start;
    // Header rows (fully resident).
    for (; i < end && i < _headerCount; i++) {
      out.add(_header[i]);
    }
    if (i >= end) return out;

    // Body rows: seek once to the first requested file line, then scan forward.
    var fileLine = i - _headerCount;
    var pos = _byteOfFileLine(fileLine);
    while (i < end && pos <= _len) {
      final nl = store.indexOfNewline(pos);
      final lineEnd = nl < 0 ? _len : nl;
      out.add(_bodyRow(fileLine, pos, lineEnd, fileLine == _fileLineCount - 1));
      fileLine++;
      i++;
      if (nl < 0) break;
      pos = nl + 1;
    }
    return out;
  }

  @override
  LineKind kindAt(int i) {
    if (i < 0 || i >= lineCount) return LineKind.context;
    if (i < _headerCount) return _header[i].kind;
    return LineKind.added;
  }

  @override
  int nextChangedLine(int fromDisplay, int dir) {
    if (_fileLineCount == 0) return -1;
    final firstBody = _headerCount;
    final lastBody = lineCount - 1;
    if (dir >= 0) {
      final t = fromDisplay < firstBody ? firstBody : fromDisplay;
      return t <= lastBody ? t : -1;
    } else {
      final t = fromDisplay > lastBody ? lastBody : fromDisplay;
      return t >= firstBody ? t : -1;
    }
  }

  @override
  List<int> findMatchingLines(String lowerTerm) {
    if (lowerTerm.isEmpty) return const [];
    final out = <int>[];
    for (var i = 0; i < _headerCount; i++) {
      if (_header[i].text.toLowerCase().contains(lowerTerm)) out.add(i);
    }
    var pos = 0, fileLine = 0;
    while (pos < _len) {
      final nl = store.indexOfNewline(pos);
      final end = nl < 0 ? _len : nl;
      if (store.substring(pos, end).toLowerCase().contains(lowerTerm)) {
        out.add(_headerCount + fileLine);
      }
      fileLine++;
      if (nl < 0) break;
      pos = nl + 1;
    }
    return out;
  }

  @override
  int predictByteOffset(int i) {
    if (i <= _headerCount) return 0;
    if (i >= lineCount) return _len;
    final fileLine = i - _headerCount;
    final a = _anchorForFileLine(fileLine);
    if (a >= _anchorByte.length - 1) {
      final mu = _len / (_fileLineCount == 0 ? 1 : _fileLineCount);
      return (fileLine * mu).round();
    }
    final loLine = _anchorLine[a], hiLine = _anchorLine[a + 1];
    final span = hiLine - loLine;
    final mu = span <= 0 ? 0.0 : (_anchorByte[a + 1] - _anchorByte[a]) / span;
    return (_anchorByte[a] + (fileLine - loLine) * mu).round();
  }

  @visibleForTesting
  int get anchorCount => _anchorByte.length;
}
