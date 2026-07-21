// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// The "powerpuff" diff — a predictive, lazily-hydrated index over a raw
// unified diff. PROTOTYPE (proven on real 326MB road-graph data; see
// test/features/diff/predictive_diff_bench_test.dart).
//
// The thesis, and the rebuttal to "information takes time": you never need
// more of a diff MATERIALIZED than the ~60 rows on screen. Building 16M
// ParsedLine objects up front (≈5s, ≈1.6GB) to show 60 of them is the waste.
//
// Two facts from the real data make random access cheap:
//   • A newline-only scan of the raw bytes is ~4× faster than object parsing
//     and holds far less (a sparse state anchor, not an object per line).
//   • Line lengths are near-stationary (μ≈22.4, σ≈0.9 on road data), so the
//     byte offset of line N is PREDICTABLE: with an exact state snapshot every
//     [kAnchorSpacing] lines, the offset of any line lands within ~38 lines of
//     a prediction — a local scan snaps to the exact boundary in microseconds.
//
// This is the whisper AR/harmonic predictor (ga-predictor.ts / the resonant
// `pred = C·p1 − p2`) applied to the offset sequence: the "signal" is
// cumulative byte-offset vs line index; the anchors are the fitted model; the
// replay in [hydrateRange] pays only the residual.
//
// Correctness: [hydrateRange] reproduces exactly what [parseUnifiedDiff] emits
// for the same lines — it replays the identical per-line classification from a
// nearby anchor. The bench test pins that equivalence on real + hostile diffs.
//
// NOT yet wired into the shell: DiffShell holds a full List<ParsedLine>, so
// integration (making `document.lines` a lazy ListBase backed by this index)
// is a separate step. This module proves the core is real and insanely fast.

import 'dart:collection';

import 'package:meta/meta.dart';

import '../../backend/git_diff_paths.dart'
    show pathFromDiffGitHeader, patchSidePath;
import 'byte_store.dart';
import 'diff_models.dart';

/// An exact parse-state snapshot is stored whenever EITHER this many display
/// lines OR [kAnchorByteSpacing] bytes have elapsed since the last one —
/// whichever comes first. The line bound keeps cold-seek replay short on normal
/// diffs (4096 gave a ~38-line correction window on real road data —
/// microseconds); the byte bound is the giant-line safety net: a diff of a few
/// enormous lines would, under a line-only rule, leave megabytes between anchors
/// and make a cold seek scan them all. With the dual bound, no cold seek ever
/// replays more than [kAnchorByteSpacing] bytes OR [kAnchorSpacing] lines.
const int kAnchorSpacing = 4096;

/// The byte half of the dual anchor bound (see [kAnchorSpacing]). 512 KiB keeps
/// a cold seek's replay bounded even when individual lines are enormous, while
/// staying tiny relative to any real diff (a few hundred anchors per GB).
const int kAnchorByteSpacing = 512 * 1024;

final RegExp _kHunkHeader = RegExp(
  r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@',
);

/// The full parse cursor state at a line boundary — everything needed to resume
/// classification exactly where [parseUnifiedDiff] would be. Mirrors the fields
/// of diff_models' `_HunkCursor` plus the surrounding parse counters.
class _State {
  int byte; // byte offset in `raw` where the line at this boundary begins
  int oldLine;
  int newLine;
  int hunkIndex;
  String? currentFile;
  String? pendingOldFile;
  bool inHunk;
  bool bounded;
  int oldRemaining;
  int newRemaining;
  int hunkOldStart;
  int hunkNewStart;

  // Scratch describing the line the last [_classify] call emitted (valid only
  // when it returned true). Lets build COUNT without allocating a ParsedLine
  // and hydrate MATERIALIZE from the same state machine — no second parser.
  LineKind emKind = LineKind.context;
  int? emOld;
  int? emNew;
  int emHunk = -1;
  String? emFile;

  _State()
    : byte = 0,
      oldLine = 0,
      newLine = 0,
      hunkIndex = -1,
      currentFile = null,
      pendingOldFile = null,
      inHunk = false,
      bounded = false,
      oldRemaining = 0,
      newRemaining = 0,
      hunkOldStart = 0,
      hunkNewStart = 0;

  _State._copy(
    this.byte,
    this.oldLine,
    this.newLine,
    this.hunkIndex,
    this.currentFile,
    this.pendingOldFile,
    this.inHunk,
    this.bounded,
    this.oldRemaining,
    this.newRemaining,
    this.hunkOldStart,
    this.hunkNewStart,
  );

  _State clone() => _State._copy(
    byte,
    oldLine,
    newLine,
    hunkIndex,
    currentFile,
    pendingOldFile,
    inHunk,
    bounded,
    oldRemaining,
    newRemaining,
    hunkOldStart,
    hunkNewStart,
  );
}

/// A hunk header seen during [PredictiveDiffIndex.build], with its display-line
/// index and the counts parsed from the `@@` line. [adds]/[dels] are the ACTUAL
/// `+`/`-` body-row counts (NOT the header's old/new counts, which include
/// context) — filled in as the hunk body is scanned, so churn metadata matches
/// the eager parser exactly.
class PredictiveHunk {
  final int displayIndex; // index of the `@@` row among display lines
  final int oldStart;
  final int newStart;
  final int oldCount; // header count (context + deletions)
  final int newCount; // header count (context + additions)
  final String header; // the raw `@@ … @@` line
  final String? filePath;
  int adds = 0; // actual added rows in the body
  int dels = 0; // actual deleted rows in the body
  PredictiveHunk(
    this.displayIndex,
    this.oldStart,
    this.newStart,
    this.oldCount,
    this.newCount,
    this.header,
    this.filePath,
  );
}

/// A file boundary discovered from unified-diff metadata. Unlike hunks, this
/// exists for binary, mode-only, empty, and other hunkless file sections.
class PredictiveFile {
  final String path;
  final int displayIndex;
  bool isBinary;

  /// True when this file has no old side (`new file mode` / `--- /dev/null`)
  /// — i.e. no committed ancestor exists, so ancestry-dependent features
  /// (blame) must skip it. Recorded structurally during the scan because
  /// file-backed documents carry no raw slices to sniff.
  bool isNewFile;

  /// EXACT byte offset of this file's first header line in the store
  /// (captured at scan time, not predicted). Lets a consumer extract one
  /// file's raw slice from a file-backed store without materializing the
  /// whole diff — see `DiffDocument.rawSliceForPath`.
  final int byteOffset;

  PredictiveFile(
    this.path,
    this.displayIndex, {
    this.isBinary = false,
    this.isNewFile = false,
    this.byteOffset = 0,
  });
}

/// The surface a [LazyDiffLines] and the diff shell need from a lazy row index,
/// so different backings can serve it. [PredictiveDiffIndex] parses real unified
/// diff bytes; [NewFileIndex] presents a working-tree file as an all-added new
/// file diff with ZERO copy. Both hydrate rows on demand and answer search/nav
/// off the [store] without materializing everything.
abstract interface class DiffLineIndex {
  ByteStore get store;

  /// True when [store]'s bytes ARE unified-diff text, so a byte range of it
  /// is a valid raw diff slice. [PredictiveDiffIndex] indexes real diff
  /// bytes (true); [NewFileIndex] presents a raw working-tree FILE as a
  /// synthetic all-added diff — its store holds file contents, not diff
  /// text, so extracting bytes from it would hand back content masquerading
  /// as a patch.
  bool get storeHoldsUnifiedDiff;
  int get lineCount;
  int get adds;
  int get dels;
  int get maxLineLength;
  int get leadingMetaCount;
  bool get isBinary;
  List<PredictiveFile> get files;
  List<PredictiveHunk> get hunks;
  List<ParsedLine> hydrateRange(int start, int count);
  List<int> findMatchingLines(String lowerTerm);
  int nextChangedLine(int fromDisplay, int dir);
  LineKind kindAt(int i);
  int predictByteOffset(int i);
}

class PredictiveDiffIndex implements DiffLineIndex {
  /// The raw diff bytes, read through the [ByteStore] seam so the backing —
  /// in-RAM string or spooled temp file — never leaks into the parser.
  @override
  final ByteStore store;

  @override
  bool get storeHoldsUnifiedDiff => true;

  /// Exact parse-state snapshots at the dual-bound anchor points (see
  /// [kAnchorSpacing] / [kAnchorByteSpacing]). Non-uniformly spaced in line
  /// index, so [_anchorLineAt] records each one's display-line ordinal and
  /// seeks binary-search it via [_anchorIndexForLine].
  final List<_State> _anchors;

  /// `_anchorLineAt[a]` = the display-line ordinal at which anchor `a` sits.
  /// Parallel to [_anchors]; monotonically increasing.
  final List<int> _anchorLineAt;

  /// Total number of display lines (what [parseUnifiedDiff] would return).
  @override
  final int lineCount;

  @override
  final int leadingMetaCount;

  /// Hunk headers, in order — collected cheaply during the build scan.
  @override
  final List<PredictiveHunk> hunks;

  @override
  final List<PredictiveFile> files;

  /// Whether any line is a binary marker (git "Binary files … differ"). The
  /// binary path owns rendering; the shell only needs the flag.
  @override
  final bool isBinary;

  /// Longest line seen (chars) — for the horizontal-extent measurement.
  @override
  final int maxLineLength;

  /// Added / deleted display-line counts (for DiffStats), gathered in the scan.
  @override
  final int adds;
  @override
  final int dels;

  PredictiveDiffIndex._(
    this.store,
    this._anchors,
    this._anchorLineAt,
    this.lineCount,
    this.leadingMetaCount,
    this.hunks,
    this.files,
    this.isBinary,
    this.maxLineLength,
    this.adds,
    this.dels,
  );

  /// Number of anchor snapshots — for tests asserting the dual bound placed
  /// byte-driven anchors on a few-enormous-lines diff (where a line-only rule
  /// would leave just one).
  @visibleForTesting
  int get anchorCount => _anchors.length;

  /// Index of the last anchor at or before display line [line] — the entry
  /// point for a cold seek. O(log anchors); anchors are non-uniform under the
  /// dual bound, so this replaces the old `line ~/ kAnchorSpacing`.
  int _anchorIndexForLine(int line) {
    var lo = 0, hi = _anchorLineAt.length - 1, ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_anchorLineAt[mid] <= line) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  /// One linear scan: classify every line (no object allocation beyond one
  /// sparse anchor per [kAnchorSpacing] lines) and record a state snapshot.
  /// The fast, tiny-footprint replacement for the ~5s / ~1.6GB object build.
  factory PredictiveDiffIndex.build(String raw) =>
      PredictiveDiffIndex.buildFromStore(StringByteStore(raw));

  /// [build] over any [ByteStore] backing (in-RAM string or spooled file).
  factory PredictiveDiffIndex.buildFromStore(ByteStore store) {
    final anchors = <_State>[];
    final anchorLineAt = <int>[];
    final hunks = <PredictiveHunk>[];
    final files = <PredictiveFile>[];
    PredictiveFile? currentFile;
    PredictiveHunk? curHunk;
    final st = _State();
    var count = 0;
    var leadingMetaCount = 0;
    var sawNonMeta = false;
    var adds = 0, dels = 0;
    var binary = false;
    var pendingNewFile = false;
    // Byte offset of a `--- ` header line whose `+++` successor has not been
    // processed yet. In a HEADER-LESS unified diff the section truly starts
    // at `--- `, but `st.currentFile` only changes on the `+++` line — so an
    // entry created there would record its start one line late and
    // rawSliceForPath would return a slice missing its `--- ` header. Valid
    // for exactly one following line (unified format puts `+++` directly
    // after `--- `); anything else clears it. [pendingSectionStartRow] is
    // the same line's DISPLAY row, so the section anchor and the byte
    // offset always name the same line.
    int? pendingSectionStart;
    var pendingSectionStartRow = 0;
    var maxLen = 0;
    final len = store.length;
    var pos = 0;
    var lastAnchorLine = 0, lastAnchorByte = 0;

    while (pos < len) {
      final nl = store.indexOfNewline(pos);
      final end = nl < 0 ? len : nl;
      final lineLen = end - pos;
      if (lineLen > maxLen) maxLen = lineLen;

      // Dual-bound anchoring: snapshot at the FIRST line boundary once either
      // [kAnchorSpacing] emitted lines OR [kAnchorByteSpacing] bytes have
      // elapsed since the last anchor (and always anchor[0]). `pos` is always a
      // line start, so the state is exact here; non-uniform spacing is resolved
      // by [_anchorIndexForLine].
      if (anchors.isEmpty ||
          count - lastAnchorLine >= kAnchorSpacing ||
          pos - lastAnchorByte >= kAnchorByteSpacing) {
        anchors.add((st.clone())..byte = pos);
        anchorLineAt.add(count);
        lastAnchorLine = count;
        lastAnchorByte = pos;
      }

      // Cheap prefix check to avoid substring for the vast body-line majority:
      // only header/hunk/binary lines need the actual string.
      final first = lineLen == 0 ? -1 : store.unitAt(pos);
      final previousFile = st.currentFile;
      if (_classifyFast(store, pos, end, first, st)) {
        if (!sawNonMeta && st.emKind == LineKind.meta) {
          leadingMetaCount++;
        } else {
          sawNonMeta = true;
        }
        if (st.emKind == LineKind.added) {
          adds++;
          curHunk?.adds++;
        } else if (st.emKind == LineKind.deleted) {
          dels++;
          curHunk?.dels++;
        } else if (st.emKind == LineKind.hunk) {
          curHunk = PredictiveHunk(
            count,
            st.hunkOldStart,
            st.hunkNewStart,
            st.oldRemaining,
            st.newRemaining,
            store.substring(pos, end),
            st.currentFile,
          );
          hunks.add(curHunk);
        } else if (st.emKind == LineKind.meta) {
          final line = store.substring(pos, end);
          if (line.startsWith('--- ')) {
            pendingSectionStart = pos; // see the field's doc: one-line window
            pendingSectionStartRow = count; // this line's row (pre-increment)
          }
          if (line.startsWith('Binary files ') ||
              line.startsWith('GIT binary patch')) {
            binary = true;
            currentFile?.isBinary = true;
          } else if (line.startsWith('new file mode ') ||
              line.startsWith('--- /dev/null')) {
            // No old side → no committed ancestor (blame must skip it).
            // Header-full git diffs mark the just-created entry; a
            // header-less synthetic patch sees `--- /dev/null` BEFORE its
            // `+++` line names the file, so the mark pends onto the next
            // entry created.
            if (currentFile != null && currentFile.path == st.currentFile) {
              currentFile.isNewFile = true;
            } else {
              pendingNewFile = true;
            }
          }
        }
        count++;
      }
      if (st.currentFile != null && st.currentFile != previousFile) {
        // displayIndex is a DISPLAY row, byteOffset a RAW offset — two
        // different spaces, each anchored to its own truth. Git-style: the
        // switching `diff --git` line does NOT emit, so `count` already
        // names the section's first VISIBLE row. Header-less: the switching
        // `+++` line DOES emit (as does its `--- ` predecessor), so `count`
        // here is two rows past the section's true visible start — the
        // `--- ` row, whose display index rode along with
        // [pendingSectionStart].
        currentFile = PredictiveFile(
          st.currentFile!,
          pendingSectionStart != null ? pendingSectionStartRow : count,
          isNewFile: pendingNewFile,
          byteOffset: pendingSectionStart ?? pos,
        );
        pendingNewFile = false;
        files.add(currentFile);
      }
      // The pending `--- ` offset survives exactly one line: its `+++`
      // successor consumed it above, and any other line invalidates it (a
      // git-style diff's `--- a/x` follows an entry already created at
      // `diff --git`, so it must never leak into the NEXT file's entry).
      // Allocation-free: it was set THIS line iff it equals `pos` — no
      // per-line substring, which the body-line fast path forbids.
      if (pendingSectionStart != null && pendingSectionStart != pos) {
        pendingSectionStart = null;
      }

      if (nl < 0) break;
      pos = nl + 1;
    }

    return PredictiveDiffIndex._(
      store,
      anchors,
      anchorLineAt,
      count,
      leadingMetaCount,
      hunks,
      files,
      binary,
      maxLen,
      adds,
      dels,
    );
  }

  /// Chunked, cooperative version of [build]: yields to the event loop every
  /// [_yieldEvery] lines so a multi-second scan of a giant diff never freezes
  /// the UI — the loading spinner keeps animating and the app stays responsive.
  /// Same classification (shared [_classify]/[_classifyFast]) → same result as
  /// [build]. Run this off the synchronous open path for machine-scale diffs.
  static Future<PredictiveDiffIndex> buildAsync(String raw) =>
      buildFromStoreAsync(StringByteStore(raw));

  /// [buildAsync] over any [ByteStore] backing.
  static Future<PredictiveDiffIndex> buildFromStoreAsync(
    ByteStore store,
  ) async {
    final anchors = <_State>[];
    final anchorLineAt = <int>[];
    final hunks = <PredictiveHunk>[];
    final files = <PredictiveFile>[];
    PredictiveFile? currentFile;
    PredictiveHunk? curHunk;
    final st = _State();
    var count = 0, adds = 0, dels = 0;
    var leadingMetaCount = 0;
    var sawNonMeta = false;
    var binary = false;
    var pendingNewFile = false;
    // Byte offset of a `--- ` header line whose `+++` successor has not been
    // processed yet. In a HEADER-LESS unified diff the section truly starts
    // at `--- `, but `st.currentFile` only changes on the `+++` line — so an
    // entry created there would record its start one line late and
    // rawSliceForPath would return a slice missing its `--- ` header. Valid
    // for exactly one following line (unified format puts `+++` directly
    // after `--- `); anything else clears it. [pendingSectionStartRow] is
    // the same line's DISPLAY row, so the section anchor and the byte
    // offset always name the same line.
    int? pendingSectionStart;
    var pendingSectionStartRow = 0;
    var maxLen = 0;
    final len = store.length;
    var pos = 0;
    var sinceYield = 0;
    var lastAnchorLine = 0, lastAnchorByte = 0;

    while (pos < len) {
      final nl = store.indexOfNewline(pos);
      final end = nl < 0 ? len : nl;
      final lineLen = end - pos;
      if (lineLen > maxLen) maxLen = lineLen;
      if (anchors.isEmpty ||
          count - lastAnchorLine >= kAnchorSpacing ||
          pos - lastAnchorByte >= kAnchorByteSpacing) {
        anchors.add((st.clone())..byte = pos);
        anchorLineAt.add(count);
        lastAnchorLine = count;
        lastAnchorByte = pos;
      }
      final first = lineLen == 0 ? -1 : store.unitAt(pos);
      final previousFile = st.currentFile;
      if (_classifyFast(store, pos, end, first, st)) {
        if (!sawNonMeta && st.emKind == LineKind.meta) {
          leadingMetaCount++;
        } else {
          sawNonMeta = true;
        }
        if (st.emKind == LineKind.added) {
          adds++;
          curHunk?.adds++;
        } else if (st.emKind == LineKind.deleted) {
          dels++;
          curHunk?.dels++;
        } else if (st.emKind == LineKind.hunk) {
          curHunk = PredictiveHunk(
            count,
            st.hunkOldStart,
            st.hunkNewStart,
            st.oldRemaining,
            st.newRemaining,
            store.substring(pos, end),
            st.currentFile,
          );
          hunks.add(curHunk);
        } else if (st.emKind == LineKind.meta) {
          final line = store.substring(pos, end);
          if (line.startsWith('--- ')) {
            pendingSectionStart = pos; // see the field's doc: one-line window
            pendingSectionStartRow = count; // this line's row (pre-increment)
          }
          if (line.startsWith('Binary files ') ||
              line.startsWith('GIT binary patch')) {
            binary = true;
            currentFile?.isBinary = true;
          } else if (line.startsWith('new file mode ') ||
              line.startsWith('--- /dev/null')) {
            // No old side → no committed ancestor (blame must skip it).
            // Header-full git diffs mark the just-created entry; a
            // header-less synthetic patch sees `--- /dev/null` BEFORE its
            // `+++` line names the file, so the mark pends onto the next
            // entry created.
            if (currentFile != null && currentFile.path == st.currentFile) {
              currentFile.isNewFile = true;
            } else {
              pendingNewFile = true;
            }
          }
        }
        count++;
      }
      if (st.currentFile != null && st.currentFile != previousFile) {
        // displayIndex is a DISPLAY row, byteOffset a RAW offset — two
        // different spaces, each anchored to its own truth. Git-style: the
        // switching `diff --git` line does NOT emit, so `count` already
        // names the section's first VISIBLE row. Header-less: the switching
        // `+++` line DOES emit (as does its `--- ` predecessor), so `count`
        // here is two rows past the section's true visible start — the
        // `--- ` row, whose display index rode along with
        // [pendingSectionStart].
        currentFile = PredictiveFile(
          st.currentFile!,
          pendingSectionStart != null ? pendingSectionStartRow : count,
          isNewFile: pendingNewFile,
          byteOffset: pendingSectionStart ?? pos,
        );
        pendingNewFile = false;
        files.add(currentFile);
      }
      // The pending `--- ` offset survives exactly one line: its `+++`
      // successor consumed it above, and any other line invalidates it (a
      // git-style diff's `--- a/x` follows an entry already created at
      // `diff --git`, so it must never leak into the NEXT file's entry).
      // Allocation-free: it was set THIS line iff it equals `pos` — no
      // per-line substring, which the body-line fast path forbids.
      if (pendingSectionStart != null && pendingSectionStart != pos) {
        pendingSectionStart = null;
      }
      if (nl < 0) break;
      pos = nl + 1;
      if (++sinceYield >= _yieldEvery) {
        sinceYield = 0;
        await Future<void>.delayed(Duration.zero);
      }
    }
    return PredictiveDiffIndex._(
      store,
      anchors,
      anchorLineAt,
      count,
      leadingMetaCount,
      hunks,
      files,
      binary,
      maxLen,
      adds,
      dels,
    );
  }

  /// Lines processed between event-loop yields in [buildAsync] — sized so each
  /// chunk stays well under a 60fps frame (measured ~140ns/line, so 60k ≈ 8ms),
  /// keeping the spinner smooth during a multi-second scan.
  static const int _yieldEvery = 60000;

  /// Position-based classify for the BUILD hot path: only substrings a line
  /// when it might be a header (rare). Body `+`/`-`/space lines are classified
  /// from their first byte with zero allocation.
  static bool _classifyFast(
    ByteStore store,
    int pos,
    int end,
    int first,
    _State st,
  ) {
    // In an open, bounded hunk, a `+`/`-`/space line is unambiguously body —
    // no header can start there — so skip the substring + full state machine.
    if (st.inHunk &&
        st.bounded &&
        (first == 0x2B /* + */ ||
            first == 0x2D /* - */ ||
            first == 0x20 /* space */ )) {
      // Mirror _advanceCursor's budget bookkeeping + emit, positionally.
      if (first == 0x2B) {
        if (st.newRemaining > 0) st.newRemaining--;
        _emit(
          st,
          LineKind.added,
          null,
          st.newLine++,
          st.hunkIndex,
          st.currentFile,
        );
      } else if (first == 0x2D) {
        if (st.oldRemaining > 0) st.oldRemaining--;
        _emit(
          st,
          LineKind.deleted,
          st.oldLine++,
          null,
          st.hunkIndex,
          st.currentFile,
        );
      } else {
        if (st.oldRemaining > 0) st.oldRemaining--;
        if (st.newRemaining > 0) st.newRemaining--;
        _emit(
          st,
          LineKind.context,
          st.oldLine++,
          st.newLine++,
          st.hunkIndex,
          st.currentFile,
        );
      }
      if (st.oldRemaining <= 0 && st.newRemaining <= 0) _closeCursor(st);
      return true;
    }
    return _classify(store.substring(pos, end), st);
  }

  /// Predicted byte offset of display line [i] — the μ/anchor model used to
  /// position the scrollbar and seek BEFORE the exact replay. Piecewise-linear
  /// between anchors (an AR model refit per segment), exact at anchor lines.
  @override
  int predictByteOffset(int i) {
    if (i <= 0) return 0;
    if (i >= lineCount) return store.length;
    final a = _anchorIndexForLine(i);
    if (a >= _anchors.length - 1) {
      final mu = store.length / (lineCount == 0 ? 1 : lineCount);
      return (i * mu).round();
    }
    final lo = _anchors[a], hi = _anchors[a + 1];
    final loLine = _anchorLineAt[a], hiLine = _anchorLineAt[a + 1];
    final span = hiLine - loLine;
    final localMu = span <= 0 ? 0.0 : (hi.byte - lo.byte) / span;
    return (lo.byte + (i - loLine) * localMu).round();
  }

  /// Hydrate exactly the display lines in `[start, start+count)` into real
  /// [ParsedLine]s — byte-identical to `parseUnifiedDiff(raw).sublist(...)`.
  /// Replays from the nearest anchor (≤ [kAnchorSpacing] cheap steps), then
  /// materializes only the requested rows.
  @override
  List<ParsedLine> hydrateRange(int start, int count) {
    if (start < 0) start = 0;
    if (start >= lineCount || count <= 0) return const [];
    final end = (start + count).clamp(0, lineCount);

    final anchorIdx = _anchorIndexForLine(start);
    final st = _anchors[anchorIdx].clone();
    var emitted = _anchorLineAt[anchorIdx];

    final out = <ParsedLine>[];
    var pos = st.byte;
    final len = store.length;

    while (pos < len && emitted < end) {
      final nl = store.indexOfNewline(pos);
      final lineEnd = nl < 0 ? len : nl;
      final line = store.substring(pos, lineEnd);

      if (_classify(line, st)) {
        if (emitted >= start) out.add(_materialize(line, st));
        emitted++;
      } else if (line.startsWith('\\')) {
        // `\ No newline…` attaches to the previously emitted line, emits none.
        if (emitted - 1 >= start && out.isNotEmpty) {
          out[out.length - 1] = out.last.copyWith(noNewlineAtEof: true);
        }
      }

      if (nl < 0) break;
      pos = nl + 1;
    }
    _applyTrailingNoNewline(out, emitted, end, pos);
    return out;
  }

  /// The last requested row may be followed by a `\ No newline at end of file`
  /// marker the hydration loop never reached (it stops once `emitted == end`).
  /// Peek one line so that row's [ParsedLine.noNewlineAtEof] matches the eager
  /// parser exactly at any window boundary. A `\` in column 0 is unambiguously
  /// the marker (diff body lines always carry a `+`/`-`/space prefix).
  void _applyTrailingNoNewline(
    List<ParsedLine> out,
    int emitted,
    int end,
    int pos,
  ) {
    if (out.isEmpty || emitted != end || pos >= store.length) return;
    if (store.unitAt(pos) == 0x5C /* \ */ ) {
      out[out.length - 1] = out.last.copyWith(noNewlineAtEof: true);
    }
  }

  /// Cold first paint: the first [count] display rows, parsed straight from the
  /// top with NO prior index — O(count), sub-millisecond regardless of file
  /// size. Render this instantly on open, then build the full index in the
  /// background for random seeks.
  static List<ParsedLine> firstRows(String raw, int count) =>
      firstRowsFromStore(StringByteStore(raw), count);

  /// [firstRows] over any [ByteStore] backing.
  static List<ParsedLine> firstRowsFromStore(ByteStore store, int count) {
    final st = _State();
    final out = <ParsedLine>[];
    var pos = 0;
    final len = store.length;
    while (pos < len && out.length < count) {
      final nl = store.indexOfNewline(pos);
      final end = nl < 0 ? len : nl;
      final line = store.substring(pos, end);
      if (_classify(line, st)) {
        out.add(_materialize(line, st));
      } else if (line.startsWith('\\') && out.isNotEmpty) {
        out[out.length - 1] = out.last.copyWith(noNewlineAtEof: true);
      }
      if (nl < 0) break;
      pos = nl + 1;
    }
    // Boundary peek (see [_applyTrailingNoNewline]): the count-th row may be
    // followed by a `\ No newline` marker the loop stopped short of.
    if (out.isNotEmpty &&
        out.length == count &&
        pos < len &&
        store.unitAt(pos) == 0x5C) {
      out[out.length - 1] = out.last.copyWith(noNewlineAtEof: true);
    }
    return out;
  }

  /// Display-line indices whose text contains [lowerTerm] (already lowercased),
  /// case-insensitively. Uses the SAME `toLowerCase()` folding the eager path's
  /// [ParsedLine.lowerText] does, so search results are identical regardless of
  /// diff size (Unicode-correct — accented Latin, Greek, Cyrillic all match).
  /// One raw scan, no ParsedLine hydration — search works at ANY size (instant
  /// for a normal diff, sub-second on a 340MB one). Empty term → empty.
  @override
  List<int> findMatchingLines(String lowerTerm) {
    if (lowerTerm.isEmpty) return const [];
    final out = <int>[];
    final st = _State();
    var count = 0;
    final len = store.length;
    var pos = 0;
    while (pos < len) {
      final nl = store.indexOfNewline(pos);
      final end = nl < 0 ? len : nl;
      final first = end > pos ? store.unitAt(pos) : -1;
      if (_classifyFast(store, pos, end, first, st)) {
        if (store.substring(pos, end).toLowerCase().contains(lowerTerm)) {
          out.add(count);
        }
        count++;
      }
      if (nl < 0) break;
      pos = nl + 1;
    }
    return out;
  }

  /// The next display-line index at/after (dir>0) or at/before (dir<0)
  /// [fromDisplay] whose kind is added or deleted — for keyboard-cursor
  /// navigation without iterating (hydrating) the whole list. Returns -1 when
  /// none. Scans from the nearest anchor; the cursor moves one changed line at
  /// a time so the walk is short in practice.
  @override
  int nextChangedLine(int fromDisplay, int dir) {
    if (lineCount == 0) return -1;
    var target = fromDisplay.clamp(0, lineCount - 1);
    if (dir >= 0) {
      for (var i = target; i < lineCount; i++) {
        final k = kindAt(i);
        if (k == LineKind.added || k == LineKind.deleted) return i;
      }
    } else {
      for (var i = target; i >= 0; i--) {
        final k = kindAt(i);
        if (k == LineKind.added || k == LineKind.deleted) return i;
      }
    }
    return -1;
  }

  /// The [LineKind] of display line [i] without materializing its ParsedLine —
  /// replays from the nearest anchor and reads the classifier's verdict.
  @override
  LineKind kindAt(int i) {
    if (i < 0 || i >= lineCount) return LineKind.context;
    final anchorIdx = _anchorIndexForLine(i);
    final st = _anchors[anchorIdx].clone();
    var emitted = _anchorLineAt[anchorIdx];
    var pos = st.byte;
    final len = store.length;
    while (pos < len) {
      final nl = store.indexOfNewline(pos);
      final end = nl < 0 ? len : nl;
      final first = end > pos ? store.unitAt(pos) : -1;
      if (_classifyFast(store, pos, end, first, st)) {
        if (emitted == i) return st.emKind;
        emitted++;
      }
      if (nl < 0) break;
      pos = nl + 1;
    }
    return LineKind.context;
  }

  /// Materialize the [ParsedLine] the last [_classify] call emitted (its
  /// properties are on [st]). Byte-identical to what parseUnifiedDiff builds.
  static ParsedLine _materialize(String line, _State st) => ParsedLine(
    text: line,
    kind: st.emKind,
    lineNumOld: st.emOld,
    lineNumNew: st.emNew,
    hunkIndex: st.emHunk,
    filePath: st.emFile,
  );

  /// Run the per-line state machine, mutating [st]. Returns whether the line
  /// emits a display row; when true, [st].em* describe it. Allocation-free
  /// (no ParsedLine) so BUILD counts without materializing 15M objects — the
  /// single source of truth shared with HYDRATE (which then materializes).
  static bool _classify(String line, _State st) {
    final inHunk = _advanceCursor(line, st);

    if (!inHunk) {
      if (line.startsWith('diff --git')) {
        final path = pathFromDiffGitHeader(line);
        if (path != null) st.currentFile = path;
        st.pendingOldFile = null;
        return false;
      }
      if (line.startsWith('diff ') || line.startsWith('index ')) return false;
      if (line.startsWith('@@')) {
        st.oldLine = st.hunkOldStart;
        st.newLine = st.hunkNewStart;
        st.hunkIndex++;
        return _emit(
          st,
          LineKind.hunk,
          null,
          null,
          st.hunkIndex,
          st.currentFile,
        );
      }
    }
    if (line.startsWith('\\')) return false;
    if (inHunk) {
      if (line.startsWith('+')) {
        return _emit(
          st,
          LineKind.added,
          null,
          st.newLine++,
          st.hunkIndex,
          st.currentFile,
        );
      } else if (line.startsWith('-')) {
        return _emit(
          st,
          LineKind.deleted,
          st.oldLine++,
          null,
          st.hunkIndex,
          st.currentFile,
        );
      } else if (line.isEmpty) {
        return _emit(st, LineKind.context, null, null, -1, null);
      } else {
        return _emit(
          st,
          LineKind.context,
          st.oldLine++,
          st.newLine++,
          st.hunkIndex,
          st.currentFile,
        );
      }
    }
    if (line.startsWith('--- ')) {
      st.pendingOldFile = patchSidePath(line, preferredPrefix: 'a');
      return _emit(
        st,
        LineKind.meta,
        null,
        null,
        -1,
        st.currentFile ?? st.pendingOldFile,
      );
    } else if (line.startsWith('+++ ')) {
      st.currentFile =
          patchSidePath(line, preferredPrefix: 'b') ??
          st.pendingOldFile ??
          st.currentFile;
      st.pendingOldFile = null;
      return _emit(st, LineKind.meta, null, null, -1, st.currentFile);
    } else if (line.startsWith('new file mode ') ||
        line.startsWith('deleted file mode ') ||
        line.startsWith('old mode ') ||
        line.startsWith('new mode ') ||
        line.startsWith('similarity index ') ||
        line.startsWith('rename from ') ||
        line.startsWith('rename to ') ||
        line.startsWith('Binary files ') ||
        line.startsWith('GIT binary patch')) {
      return _emit(st, LineKind.meta, null, null, -1, st.currentFile);
    } else if (line.isNotEmpty) {
      return _emit(
        st,
        LineKind.context,
        st.oldLine++,
        st.newLine++,
        st.hunkIndex,
        st.currentFile,
      );
    } else {
      return _emit(st, LineKind.context, null, null, -1, null);
    }
  }

  static bool _emit(
    _State st,
    LineKind kind,
    int? old,
    int? neu,
    int hunk,
    String? file,
  ) {
    st.emKind = kind;
    st.emOld = old;
    st.emNew = neu;
    st.emHunk = hunk;
    st.emFile = file;
    return true;
  }
}

/// The ONE `List<ParsedLine>` the diff viewer uses, at every size. Rows are
/// materialized from a [PredictiveDiffIndex] with an ADAPTIVE cache:
///
///  • At or below [residentLimit] lines (a human-reviewable diff) it hydrates
///    the whole list on first touch and keeps it — indistinguishable from the
///    old eager list, so everything that iterates (edit units, search, nav)
///    just works, fast. This is the common path.
///  • Above it (a machine-scale diff) it keeps a small LRU of hydrated windows;
///    rendering and hunk-jump index single rows, and the bulk operations that
///    would otherwise iterate 15M rows use the index's own scanners
///    ([PredictiveDiffIndex.findMatchingLines] etc.) instead.
///
/// Staging writes go to an overlay so `list[i] = x` works without materializing
/// the rest. One representation, one code path — the size only changes the
/// cache policy, never the API.
class LazyDiffLines extends ListBase<ParsedLine> {
  final DiffLineIndex index;
  final int residentLimit;
  final int _windowSize;
  final int _maxWindows;
  final int leadingTrim;

  /// Full residency, built once, for reviewable diffs.
  List<ParsedLine>? _all;

  /// Windowed cache for machine-scale diffs.
  final List<_HydratedWindow> _windows = [];
  final Map<int, ParsedLine> _overrides = {};

  LazyDiffLines(
    this.index, {
    this.residentLimit = kLeanDiffLineThreshold,
    int windowSize = 512,
    int maxWindows = 8,
    this.leadingTrim = 0,
  }) : _windowSize = windowSize,
       _maxWindows = maxWindows;

  /// Whether the whole list is (or will be, on first touch) kept resident —
  /// i.e. behaves like the eager list. False only for machine-scale diffs.
  bool get isFullyResident => length <= residentLimit;

  @override
  int get length => (index.lineCount - leadingTrim).clamp(0, index.lineCount);

  int sourceIndex(int logicalIndex) => logicalIndex + leadingTrim;
  int logicalIndex(int sourceIndex) => sourceIndex - leadingTrim;

  int nextChangedLine(int from, int direction) {
    final source = index.nextChangedLine(sourceIndex(from), direction);
    final logical = logicalIndex(source);
    return source < 0 || logical < 0 || logical >= length ? -1 : logical;
  }

  List<int> findMatchingLines(String lowerTerm) => [
    for (final source in index.findMatchingLines(lowerTerm))
      if (logicalIndex(source) >= 0 && logicalIndex(source) < length)
        logicalIndex(source),
  ];

  @override
  set length(int newLength) =>
      throw UnsupportedError('LazyDiffLines is fixed-length');

  @override
  ParsedLine operator [](int i) {
    final ov = _overrides[i];
    if (ov != null) return ov;
    if (isFullyResident) {
      final all = _all ??= index.hydrateRange(leadingTrim, length);
      return (i >= 0 && i < all.length) ? all[i] : _blank;
    }
    for (var w = _windows.length - 1; w >= 0; w--) {
      final win = _windows[w];
      final off = i - win.start;
      if (off >= 0 && off < win.lines.length) return win.lines[off];
    }
    final start = (i ~/ _windowSize) * _windowSize;
    final lines = index.hydrateRange(sourceIndex(start), _windowSize);
    _windows.add(_HydratedWindow(start, lines));
    if (_windows.length > _maxWindows) _windows.removeAt(0);
    final off = i - start;
    return (off >= 0 && off < lines.length) ? lines[off] : _blank;
  }

  @override
  void operator []=(int i, ParsedLine value) => _overrides[i] = value;

  /// ParsedLine objects currently held resident. For tests asserting that a
  /// machine-scale diff never fully materializes: a fully-resident (reviewable)
  /// diff returns its whole length; a windowed diff returns only the cached
  /// windows plus staging overrides — a tiny bounded fraction of [length].
  @visibleForTesting
  int get residentRowCount {
    final all = _all;
    if (all != null) return all.length;
    var n = _overrides.length;
    for (final w in _windows) {
      n += w.lines.length;
    }
    return n;
  }

  static final ParsedLine _blank = ParsedLine(
    text: '',
    kind: LineKind.context,
    hunkIndex: -1,
  );
}

class _HydratedWindow {
  final int start;
  final List<ParsedLine> lines;
  _HydratedWindow(this.start, this.lines);
}

// ── _HunkCursor replica (faithful to diff_models._HunkCursor) ────────────────
bool _advanceCursor(String line, _State st) {
  if (line.startsWith('diff --git') ||
      line.startsWith('diff ') ||
      line.startsWith('index ')) {
    _closeCursor(st);
    return false;
  }
  if (line.startsWith('@@')) {
    final m = _kHunkHeader.firstMatch(line);
    if (m != null) {
      st.hunkOldStart = int.tryParse(m.group(1)!) ?? 0;
      st.hunkNewStart = int.tryParse(m.group(3)!) ?? 0;
      st.oldRemaining = m.group(2) == null ? 1 : int.tryParse(m.group(2)!) ?? 1;
      st.newRemaining = m.group(4) == null ? 1 : int.tryParse(m.group(4)!) ?? 1;
      st.bounded = true;
      st.inHunk = st.oldRemaining > 0 || st.newRemaining > 0;
    } else {
      st.bounded = false;
      st.inHunk = true;
    }
    return false;
  }
  if (line.startsWith('\\')) return false;
  if (!st.inHunk) return false;

  if (line.startsWith('+')) {
    if (st.newRemaining > 0) st.newRemaining--;
  } else if (line.startsWith('-')) {
    if (st.oldRemaining > 0) st.oldRemaining--;
  } else if (line.isEmpty) {
    // consumes no budget
  } else {
    if (st.oldRemaining > 0) st.oldRemaining--;
    if (st.newRemaining > 0) st.newRemaining--;
  }
  if (st.bounded && st.oldRemaining <= 0 && st.newRemaining <= 0) {
    _closeCursor(st);
  }
  return true;
}

void _closeCursor(_State st) {
  st.inHunk = false;
  st.bounded = false;
  st.oldRemaining = 0;
  st.newRemaining = 0;
}
