// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:convert';
import 'dart:io';

// The TYPE only — deliberately not git.dart, whose transitive graph
// reaches package:flutter and would make this whole machine-scale
// path unrunnable from a headless tool.
import '../../backend/spooled_diff.dart';
import 'byte_store.dart';
import 'diff_models.dart';
import 'edit_units.dart';
import 'new_file_index.dart';
import 'predictive_diff_index.dart';

/// Above this raw-diff length (UTF-16 code units, i.e. `String.length`),
/// ingestion switches to the predictive lazy path: a sparse offset index +
/// on-demand row hydration instead of a ParsedLine per line.
///
/// Deliberately measured in CODE UNITS, not UTF-8 bytes. The thing this gate
/// bounds is per-line OBJECT pressure, which scales with line COUNT, and line
/// count tracks code units — not bytes. UTF-8 bytes would *over*-count wide
/// (CJK / supplementary) text (more bytes per char, but the SAME number of
/// ParsedLine objects), pushing modest diffs onto the lazy path for no reason.
/// Code units are the cheaper AND more faithful proxy. ~4M ≈ 200k road-graph
/// lines — well above any human-reviewed change, so ordinary diffs stay eager.
const int kLazyDiffLengthThreshold = 4 * 1024 * 1024;

class DiffHunkHeader {
  final int lineIndex;
  final String filePath;
  final int fileHunkIndex;
  final String label;
  final int additions;
  final int deletions;

  /// Scope text following the `@@` header — typically the enclosing
  /// class/function that git infers from the diff context. Empty when
  /// the hunk has no identifiable scope. Trimmed of surrounding
  /// whitespace and trailing `{`/`:` that look ragged in UI.
  final String scope;

  /// Raw `@@ -A,B +C,D @@` header (without the trailing scope). Kept
  /// verbatim so power-user tooltips can surface the exact line-range
  /// signature for copy into patches.
  final String rawHeader;

  /// New-side start line, parsed from the `+C` half of the `@@` header.
  /// -1 when the header was malformed / unparseable.
  final int startLine;

  int get churn => additions + deletions;

  const DiffHunkHeader({
    required this.lineIndex,
    required this.filePath,
    required this.fileHunkIndex,
    required this.label,
    required this.additions,
    required this.deletions,
    required this.scope,
    required this.rawHeader,
    required this.startLine,
  });
}

class DiffDocumentSection {
  final String path;
  final String displayName;
  final int index;
  final int startLine;

  const DiffDocumentSection({
    required this.path,
    required this.displayName,
    required this.index,
    required this.startLine,
  });
}

class DiffFileDocument {
  final String path;
  final String displayName;
  final String rawContent;
  final List<ParsedLine> lines;
  final Map<int, EditUnit> unitByFastKey;
  final Set<int> pairedAddFastKeys;
  final DiffStats stats;
  final int changedLines;
  final int payloadBytes;
  final int maxLineLength;
  final String cacheKey;
  final bool isBinary;
  final String? oldBlobHash;
  final String? newBlobHash;

  /// True for the per-file entries a lazy multi-file document exposes via
  /// [DiffDocument.filesByPath]. Those entries are metadata-only views (path +
  /// stats + section) that deliberately carry NO lines — the rows live once in
  /// the combined lazy document. They must never be materialized into a
  /// standalone document (that would replay the entire multi-file diff); a
  /// single-file view is instead rebuilt from that file's own raw slice.
  final bool isLazyMeta;

  /// True when this document is backed by the lazy predictive index in ANY form
  /// — a metadata-only per-file entry ([isLazyMeta]) OR the combined entry whose
  /// [lines] is a [LazyDiffLines]. Either way it must never be fed through
  /// [DiffDocument.fromFiles] (whose meta-line condense pass walks every row and
  /// would hydrate the whole diff) nor cached as a reusable eager file document;
  /// a single-file view is rebuilt from raw via the lazy path instead.
  bool get isLazy => isLazyMeta || lines is LazyDiffLines;

  const DiffFileDocument._({
    required this.path,
    required this.displayName,
    required this.rawContent,
    required this.lines,
    required this.unitByFastKey,
    required this.pairedAddFastKeys,
    required this.stats,
    required this.changedLines,
    required this.payloadBytes,
    required this.maxLineLength,
    required this.cacheKey,
    required this.isBinary,
    this.oldBlobHash,
    this.newBlobHash,
    this.isLazyMeta = false,
  });

  factory DiffFileDocument.fromRawContent({
    required String rawContent,
    String? pathHint,
    String? cacheKey,
  }) {
    var parsedLines = parseUnifiedDiff(rawContent);
    final resolvedPath = _resolveDocumentPath(parsedLines, pathHint);
    if (resolvedPath != null &&
        parsedLines.every((line) => (line.filePath ?? '').isEmpty)) {
      parsedLines = parsedLines
          .map((line) => line.copyWith(filePath: resolvedPath))
          .toList(growable: false);
    }

    // Lean gate: above [kLeanDiffLineThreshold] the per-line EditUnit index
    // and its O(deletes·inserts) fuzzy move-detection pass are skipped. On a
    // multi-million-line machine-generated diff that pass never returns and
    // the map alone would hold millions of entries; a human reviews neither.
    // Everything else (render, scroll, stage, per-line search) is unaffected.
    final lean = parsedLines.length > kLeanDiffLineThreshold;
    final units = lean
        ? const <EditUnit>[]
        : buildEditUnits(parsedLines, detectMoves: true);
    final unitMap = <int, EditUnit>{};
    final pairedAdds = <int>{};
    for (final unit in units) {
      for (final line in unit.oldLines) {
        unitMap[line.fastKey] = unit;
      }
      for (final line in unit.newLines) {
        unitMap[line.fastKey] = unit;
      }
      if (unit.kind == EditKind.replace &&
          unit.oldLines.isNotEmpty &&
          unit.newLines.isNotEmpty) {
        pairedAdds.add(unit.newLines.first.fastKey);
      }
    }

    var adds = 0, dels = 0, hunkCount = 0;
    for (final line in parsedLines) {
      if (line.kind == LineKind.added) {
        adds++;
      } else if (line.kind == LineKind.deleted) {
        dels++;
      } else if (line.kind == LineKind.hunk) {
        hunkCount++;
      }
    }
    final stats = DiffStats(adds: adds, dels: dels, hunks: hunkCount);

    final normalizedPath = resolvedPath ?? pathHint ?? '';

    final binary = parsedLines.any(
      (l) =>
          l.kind == LineKind.meta &&
          (l.text.startsWith('Binary files ') ||
              l.text.startsWith('GIT binary patch') ||
              l.text.contains('[binary content omitted]')),
    );

    // Bounded header scan for the first `index <old>..<new>` line. It always
    // precedes the first hunk, so stop at `@@` — this touches a handful of
    // header lines instead of splitting the entire (multi-MB) diff into a line
    // per region only to break after the third one.
    String? oldHash, newHash;
    final indexRe = RegExp(r'index ([0-9a-f]+)\.\.([0-9a-f]+)');
    var scan = 0;
    while (scan < rawContent.length) {
      if (rawContent.startsWith('@@', scan)) break;
      if (rawContent.startsWith('index ', scan)) {
        final m = indexRe.matchAsPrefix(rawContent, scan);
        if (m != null) {
          oldHash = m.group(1);
          newHash = m.group(2);
        }
        break;
      }
      final nl = rawContent.indexOf('\n', scan);
      if (nl < 0) break;
      scan = nl + 1;
    }

    return DiffFileDocument._(
      path: normalizedPath,
      displayName: _displayNameForPath(normalizedPath, fallback: pathHint),
      rawContent: rawContent,
      lines: List<ParsedLine>.unmodifiable(parsedLines),
      unitByFastKey: Map<int, EditUnit>.unmodifiable(unitMap),
      pairedAddFastKeys: Set<int>.unmodifiable(pairedAdds),
      stats: stats,
      changedLines: stats.adds + stats.dels,
      payloadBytes: _estimateUtf8Bytes(rawContent),
      maxLineLength: parsedLines.fold<int>(
        0,
        (maxChars, line) =>
            line.text.length > maxChars ? line.text.length : maxChars,
      ),
      cacheKey: cacheKey ?? '$normalizedPath|${rawContent.hashCode}',
      isBinary: binary,
      oldBlobHash: oldHash,
      newBlobHash: newHash,
    );
  }
}

class DiffDocument {
  final String documentId;
  final List<DiffFileDocument> files;
  final Map<String, DiffFileDocument> filesByPath;
  final Map<String, String> rawDiffByPath;
  final List<ParsedLine> lines;
  final List<DiffHunkHeader> hunks;
  final Map<int, EditUnit> unitByFastKey;
  final Set<int> pairedAddFastKeys;
  final List<DiffDocumentSection> sections;
  final DiffStats stats;
  final int changedLines;
  final int payloadBytes;
  final int maxLineLength;
  final bool trimLeadingMeta;

  /// Paths whose diff has no old side (`new file mode` / `--- /dev/null`) —
  /// no committed ancestor exists, so ancestry-dependent features (blame)
  /// must skip them. Computed structurally for EVERY backing: the eager path
  /// derives it from each file's raw slice, the lazy/spooled/working-file
  /// paths from the index scan — file-backed documents carry no raw slices
  /// for a consumer to sniff.
  final Set<String> newFilePaths;

  /// The disk-backed [ByteStore] this document owns, for file-backed diffs
  /// ([lazyFromSpool]). Null for in-RAM documents. [dispose] closes it.
  final ByteStore? store;

  /// A temp directory this document exclusively owns (the spool it was built
  /// from). [dispose] deletes it, so the whole disk-backed lifecycle collapses
  /// to a single `doc.dispose()` — no separate SpooledDiff to track. Null for
  /// in-RAM docs and for working-file-backed docs (which point at a real file).
  final String? _ownedTempDir;

  String? _rawContentCache;

  DiffDocument._({
    required this.documentId,
    required this.files,
    required this.filesByPath,
    required this.rawDiffByPath,
    required this.lines,
    required this.hunks,
    required this.unitByFastKey,
    required this.pairedAddFastKeys,
    required this.sections,
    required this.stats,
    required this.changedLines,
    required this.payloadBytes,
    required this.maxLineLength,
    required this.trimLeadingMeta,
    required this.newFilePaths,
    this.store,
    String? ownedTempDir,
  }) : _ownedTempDir = ownedTempDir;

  /// True when this document is backed by a spool file on disk rather than an
  /// in-RAM string — its bytes are never all resident.
  bool get isFileBacked => store is FileByteStore;

  /// Release the disk-backed store's file handle AND delete its owned spool temp
  /// directory (both no-ops for in-RAM docs). Call when the document is replaced
  /// or evicted. Never deletes a working-tree file — [_ownedTempDir] is only set
  /// for spool-backed docs, whose backing IS a temp dir.
  void dispose() {
    store?.dispose();
    final dir = _ownedTempDir;
    if (dir != null) {
      try {
        Directory(dir).deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  factory DiffDocument.fromFiles({
    required List<DiffFileDocument> files,
    bool trimLeadingMeta = false,
    String? documentId,
  }) {
    final orderedFiles = List<DiffFileDocument>.unmodifiable(files);
    final filesByPath = <String, DiffFileDocument>{
      for (final file in orderedFiles)
        if (file.path.isNotEmpty) file.path: file,
    };
    final rawDiffByPath = <String, String>{
      for (final file in orderedFiles)
        if (file.path.isNotEmpty) file.path: file.rawContent,
    };
    // Header-bounded, never a whole-text contains: hunk content can forge
    // both marker shapes byte-identically (see the helper's doc).
    final newFilePaths = <String>{
      for (final file in orderedFiles)
        if (file.path.isNotEmpty &&
            unifiedDiffHeaderDeclaresNewFile(file.rawContent))
          file.path,
    };

    final condensedByFile = [
      for (final file in orderedFiles) _condenseFilePathMetaLines(file.lines),
    ];
    final fullLines = <ParsedLine>[for (final c in condensedByFile) ...c];
    final viewLines = trimLeadingMeta
        ? _trimLeadingMetaLines(fullLines)
        : fullLines;

    final unitByFastKey = <int, EditUnit>{};
    final pairedAdds = <int>{};
    var changedLines = 0;
    var payloadBytes = 0;
    var adds = 0;
    var dels = 0;
    var hunks = 0;

    for (final file in orderedFiles) {
      unitByFastKey.addAll(file.unitByFastKey);
      pairedAdds.addAll(file.pairedAddFastKeys);
      changedLines += file.changedLines;
      payloadBytes += file.payloadBytes;
      adds += file.stats.adds;
      dels += file.stats.dels;
      hunks += file.stats.hunks;
    }
    if (orderedFiles.length > 1) {
      payloadBytes += orderedFiles.length - 1;
    }

    final sections = <DiffDocumentSection>[];
    var lineOffset = 0;
    for (var i = 0; i < orderedFiles.length; i++) {
      final fileLines = trimLeadingMeta && i == 0
          ? _trimLeadingMetaLines(condensedByFile[i])
          : condensedByFile[i];
      sections.add(
        DiffDocumentSection(
          path: orderedFiles[i].path,
          displayName: orderedFiles[i].displayName,
          index: i,
          startLine: lineOffset,
        ),
      );
      lineOffset += fileLines.length;
    }

    return DiffDocument._(
      documentId:
          documentId ??
          Object.hashAll([
            trimLeadingMeta,
            for (final file in orderedFiles) file.cacheKey,
          ]).toString(),
      files: orderedFiles,
      filesByPath: Map<String, DiffFileDocument>.unmodifiable(filesByPath),
      rawDiffByPath: Map<String, String>.unmodifiable(rawDiffByPath),
      lines: List<ParsedLine>.unmodifiable(viewLines),
      hunks: List<DiffHunkHeader>.unmodifiable(extractDiffHunks(viewLines)),
      unitByFastKey: Map<int, EditUnit>.unmodifiable(unitByFastKey),
      pairedAddFastKeys: Set<int>.unmodifiable(pairedAdds),
      sections: List<DiffDocumentSection>.unmodifiable(sections),
      stats: DiffStats(adds: adds, dels: dels, hunks: hunks),
      changedLines: changedLines,
      payloadBytes: payloadBytes,
      newFilePaths: Set<String>.unmodifiable(newFilePaths),
      maxLineLength: viewLines.fold<int>(
        0,
        (maxChars, line) =>
            line.text.length > maxChars ? line.text.length : maxChars,
      ),
      trimLeadingMeta: trimLeadingMeta,
    );
  }

  factory DiffDocument.fromRawContent({
    required String rawContent,
    String? pathHint,
    bool trimLeadingMeta = false,
    String? documentId,
  }) {
    if (rawContent.length > kLazyDiffLengthThreshold) {
      return DiffDocument.lazy(
        rawContent: rawContent,
        pathHint: pathHint,
        documentId: documentId,
        trimLeadingMeta: trimLeadingMeta,
      );
    }
    final file = DiffFileDocument.fromRawContent(
      rawContent: rawContent,
      pathHint: pathHint,
      cacheKey: pathHint == null ? null : '$pathHint|${rawContent.hashCode}',
    );
    return DiffDocument.fromFiles(
      files: [file],
      trimLeadingMeta: trimLeadingMeta,
      documentId: documentId,
    );
  }

  /// The predictive lazy path for machine-scale diffs. Builds a sparse offset
  /// index (fast, tiny) and a [LazyDiffLines] that hydrates rows on demand —
  /// no ParsedLine-per-line materialization, no O(n) analysis passes. The diff
  /// renders and scrolls in full; per-line analysis (edit units, move
  /// detection) is skipped exactly as the eager lean gate skips it.
  factory DiffDocument.lazy({
    required String rawContent,
    String? pathHint,
    String? documentId,
    bool trimLeadingMeta = false,
  }) => _lazyFromIndex(
    rawContent,
    PredictiveDiffIndex.build(rawContent),
    pathHint,
    documentId,
    trimLeadingMeta: trimLeadingMeta,
  );

  /// [lazy] but the (multi-second, on a giant diff) index scan runs cooperative
  /// -ly, yielding to the event loop so the UI never freezes — the caller
  /// awaits this while showing a loading state, and the app stays responsive.
  static Future<DiffDocument> lazyAsync({
    required String rawContent,
    String? pathHint,
    String? documentId,
    bool trimLeadingMeta = false,
  }) async => _lazyFromIndex(
    rawContent,
    await PredictiveDiffIndex.buildAsync(rawContent),
    pathHint,
    documentId,
    trimLeadingMeta: trimLeadingMeta,
  );

  /// The disk-backed path: the diff lives ONLY in a spool file, read through a
  /// [FileByteStore]. Resident RAM is the sparse index + a bounded page cache +
  /// the viewport — independent of diff size. The returned document reports an
  /// EMPTY [rawContent]: every feature that matters (render, scroll, search,
  /// nav) routes through the index, so nothing ever materializes the whole diff.
  /// The document OWNS the store — call [dispose] to close the handle. Above the
  /// lean gate the per-line spectral/edit-unit analysis is skipped exactly as
  /// the in-RAM lazy path skips it.
  ///
  /// SPOOL OWNERSHIP CONTRACT. Pass [ownedTempDir] to transfer the spool dir
  /// to the document (deleted on [dispose], and on a FAILED build). Without
  /// it, a failure here releases only the store handle — the spool dir still
  /// belongs to the caller, and the caller MUST dispose it on the throw path
  /// (`try { lazyFromSpool } catch { spool.dispose(); rethrow; }`). A caller
  /// that keeps split ownership for disposal-order reasons and forgets that
  /// catch leaks a temp dir per failed build.
  ///
  /// This raw-path entry is the ENGINE (and the tests' direct door). Feature
  /// code building from a [SpooledDiff] must name its ownership mode instead —
  /// [adoptSpool] or [viewSpool] — enforced by the spool-ownership source law.
  static Future<DiffDocument> lazyFromSpool(
    String spoolPath, {
    String? pathHint,
    String? documentId,
    Encoding encoding = utf8,
    String? ownedTempDir,
    bool trimLeadingMeta = false,
  }) async {
    final store = FileByteStore.open(spoolPath, encoding: encoding);
    try {
      final index = await PredictiveDiffIndex.buildFromStoreAsync(store);
      return _lazyFromIndex(
        null,
        index,
        pathHint,
        documentId ?? 'spool:$spoolPath:${store.length}',
        store: store,
        ownedTempDir: ownedTempDir,
        trimLeadingMeta: trimLeadingMeta,
      );
    } catch (_) {
      // A failed index build must not strand the resources the document
      // would have owned: close the handle FIRST (Windows cannot delete a
      // dir containing an open file), then drop the owned spool dir.
      store.dispose();
      if (ownedTempDir != null) {
        try {
          Directory(ownedTempDir).deleteSync(recursive: true);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Build a file-backed document that ADOPTS [spool]: from this call onward
  /// the document is the spool's SOLE owner. [dispose] deletes the temp dir,
  /// and a FAILED build deletes it too — there is no throw path on which the
  /// caller still holds anything. The caller must not touch [spool] again
  /// (no reads, no dispose). This is the mode for one-reader spools whose
  /// lifetime IS the document's (single-file, combined, and commit diffs).
  static Future<DiffDocument> adoptSpool(
    SpooledDiff spool, {
    String? pathHint,
    String? documentId,
    Encoding encoding = utf8,
    bool trimLeadingMeta = false,
  }) => lazyFromSpool(
    spool.path,
    pathHint: pathHint,
    documentId: documentId,
    encoding: encoding,
    ownedTempDir: spool.dir,
    trimLeadingMeta: trimLeadingMeta,
  );

  /// Build a file-backed document that VIEWS [spool] without owning it. The
  /// spool belongs to the caller — who may serve other readers (patch export,
  /// per-file slices, rebuilt docs) — and MUST outlive this document; the
  /// caller likewise cleans the spool up on a failed build here. [dispose]
  /// releases only the read handle. This is the mode for cached spools with
  /// multiple consumers (the PR detail cache).
  static Future<DiffDocument> viewSpool(
    SpooledDiff spool, {
    String? pathHint,
    String? documentId,
    Encoding encoding = utf8,
    bool trimLeadingMeta = false,
  }) => lazyFromSpool(
    spool.path,
    pathHint: pathHint,
    documentId: documentId,
    encoding: encoding,
    trimLeadingMeta: trimLeadingMeta,
  );

  /// The ZERO-COPY path for an untracked file: back its diff directly with a
  /// [NewFileIndex] over the working-tree file — no git subprocess, no spool
  /// copy, no whole-file read. Resident RAM = the sparse index + page cache +
  /// viewport, independent of file size. [workingPath] is the absolute on-disk
  /// path; [displayPath] the repo-relative path shown in the header. The doc
  /// OWNS the store — call [dispose].
  static Future<DiffDocument> lazyFromWorkingFile(
    String workingPath,
    String displayPath, {
    String? documentId,
    bool trimLeadingMeta = false,
  }) async {
    final index = await NewFileIndex.build(workingPath, displayPath);
    // Default identity carries size + mtime + a sampled content fingerprint.
    // Consumers rebuild on documentId change, so a same-length in-place edit
    // must mint a new id or the shell keeps rendering the old store. mtime
    // alone is NOT enough: Dart's FileStat.modified has second granularity
    // on Windows (verified empirically), so a save landing in the same
    // second as the previous one is invisible to it — and save-then-refresh
    // is exactly the hot path. The fingerprint reads three 4KB pages
    // (head/middle/tail) regardless of file size, so identity stays O(1)
    // while catching every realistic same-length edit; length + mtime cover
    // the rest. Best-effort: an unreadable stat/sample degrades to the
    // signal-absent form rather than failing a document that already opened.
    var statSig = '';
    try {
      final stat = await File(workingPath).stat();
      final fingerprint = await _sampledFingerprint(workingPath);
      statSig = ':${stat.modified.microsecondsSinceEpoch}:$fingerprint';
    } catch (_) {}
    return _lazyFromIndex(
      null,
      index,
      displayPath,
      documentId ?? 'newfile:$displayPath:${index.store.length}$statSig',
      store: index.store,
      trimLeadingMeta: trimLeadingMeta,
    );
  }

  /// FNV-1a over three 4KB pages (head, middle, tail) of the file at [path]
  /// — an O(1)-per-file content signal for [lazyFromWorkingFile]'s identity,
  /// never a full read of a potentially multi-GB working file.
  static Future<int> _sampledFingerprint(String path) async {
    const page = 4096;
    var hash = 0x811C9DC5;
    void mix(List<int> bytes) {
      for (final b in bytes) {
        hash ^= b;
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
    }

    final raf = await File(path).open();
    try {
      final len = await raf.length();
      Future<void> sampleAt(int offset) async {
        if (offset < 0 || offset >= len) return;
        await raf.setPosition(offset);
        final want = (len - offset) < page ? (len - offset) : page;
        mix(await raf.read(want));
      }

      await sampleAt(0);
      if (len > page * 2) await sampleAt(len ~/ 2 - page ~/ 2);
      if (len > page) await sampleAt(len - page);
    } finally {
      await raf.close();
    }
    return hash;
  }

  /// [rawContent] is null for the disk-backed path ([lazyFromSpool]); the doc
  /// then carries no String and identifies itself by [store] length instead.
  static DiffDocument _lazyFromIndex(
    String? rawContent,
    DiffLineIndex index,
    String? pathHint,
    String? documentId, {
    ByteStore? store,
    String? ownedTempDir,
    bool trimLeadingMeta = false,
  }) {
    // For file-backed docs there is no String to hold — content lives on disk,
    // reachable only through the index. rawContent is empty; identity comes
    // from the store length so cache keys stay stable without materializing.
    final content = rawContent ?? '';
    final identity = rawContent?.hashCode ?? index.store.length;
    // Same guard as the eager _trimLeadingMetaLines: a meta-ONLY document
    // (empty or binary file — every row is meta, leadingMetaCount == the
    // whole line count) must keep its rows. 'new file mode …' / 'Binary
    // files … differ' ARE the change there; trimming would render a blank
    // pane for a real file-level change.
    final leadingTrim =
        trimLeadingMeta && index.leadingMetaCount < index.lineCount
        ? index.leadingMetaCount
        : 0;
    final lines = LazyDiffLines(index, leadingTrim: leadingTrim);
    final stats = DiffStats(
      adds: index.adds,
      dels: index.dels,
      hunks: index.hunks.length,
    );

    // File topology comes from diff headers, not hunks. Binary, mode-only and
    // empty-file sections legitimately have no `@@` row but must remain
    // selectable in a combined lazy document.
    //
    // Duplicate paths cannot occur from this app's own producers: the
    // selection diff runs ONE HEAD→worktree pass precisely so an MM file
    // yields one section (see getSelectionDiff). If an EXTERNAL malformed
    // patch repeats a path anyway, the stance is degrade-don't-crash, and the
    // degradation is UNIFORM: `fileOrder` collapses to one entry per path at
    // its FIRST occurrence, so every path-keyed structure built from it below
    // — the hunk-header list, `sections`/`orderedPaths`, and `filesByPath` —
    // resolves that same first occurrence, matching `rawSliceForPath`'s
    // first-wins `indexWhere`. (Before this dedup, `fileOrder` carried one
    // entry per physical SECTION: a repeated path then emitted its hunk
    // headers twice, listed a duplicate section, and let `filesByPath`
    // overwrite to the LAST occurrence while the slice stayed on the first —
    // the four-way disagreement this closes.) The rendered ROWS are untouched
    // by the dedup — they stream from the full [index] via [LazyDiffLines], so
    // every occurrence's content still renders in place; only the path→section
    // resolution collapses. A path's aggregate stats (below) sum all of its
    // sections' churn — a per-path total, not a section pointer, so it does
    // not reintroduce a which-occurrence ambiguity.
    final fileOrder = <String>[];
    final seenPaths = <String>{};
    // True if index.files ever repeats a path. DEFENSIVE: today's scan starts
    // a new file entry only on a path CHANGE (see predictive_diff_index's
    // `currentFile != previousFile`), so it already merges ADJACENT same-path
    // sections into one entry and never emits a repeat that leaves a single
    // unique path — meaning this flag cannot currently fire alongside
    // `fileOrder.length == 1`. It guards the single-file rawDiffByPath
    // shortcut anyway, so if that scan ever changes to emit separate entries
    // for adjacent duplicates, a `[a.txt, a.txt]` patch (which would then
    // dedup to ONE fileOrder entry) still cannot be mistaken for a genuine
    // single-file document and handed the whole combined content as its slice.
    var hadDuplicatePath = false;
    for (final file in index.files) {
      if (file.path.isEmpty) continue;
      if (seenPaths.add(file.path)) {
        fileOrder.add(file.path);
      } else {
        hadDuplicatePath = true;
      }
    }
    final byFile = <String, List<PredictiveHunk>>{};
    for (final h in index.hunks) {
      final p = h.filePath ?? pathHint ?? '';
      final list = byFile[p];
      if (list == null) {
        byFile[p] = [h];
        // A hunk whose path never appeared as a header section (seenPaths.add
        // returns true) extends the order; a hunk for an already-listed path
        // does not — no O(n) contains scan, and no duplicate entry.
        if (seenPaths.add(p)) fileOrder.add(p);
      } else {
        list.add(h);
      }
    }
    if (fileOrder.isEmpty) fileOrder.add(pathHint ?? '');
    final primaryPath = fileOrder.first;

    // Real +/- churn per hunk (NOT the @@ header counts, which include context).
    final hunks = <DiffHunkHeader>[];
    for (final p in fileOrder) {
      final fileHunks = byFile[p] ?? const <PredictiveHunk>[];
      for (var i = 0; i < fileHunks.length; i++) {
        final h = fileHunks[i];
        hunks.add(
          DiffHunkHeader(
            lineIndex: (h.displayIndex - leadingTrim).clamp(0, lines.length),
            filePath: p,
            fileHunkIndex: i,
            label: h.header,
            additions: h.adds,
            deletions: h.dels,
            scope: '',
            rawHeader: h.header,
            startLine: h.newStart,
          ),
        );
      }
    }

    // Per-file metadata (shared lazy rows; per-file stats). Kept out of the
    // `files` list — whose join backs `rawContent` — so content stays intact;
    // exposed via `filesByPath` + `sections` for the file list and navigation.
    final filesByPath = <String, DiffFileDocument>{};
    final sections = <DiffDocumentSection>[];
    for (var fi = 0; fi < fileOrder.length; fi++) {
      final p = fileOrder[fi];
      final fileHunks = byFile[p] ?? const <PredictiveHunk>[];
      var a = 0, d = 0;
      for (final h in fileHunks) {
        a += h.adds;
        d += h.dels;
      }
      final displayName = _displayNameForPath(p, fallback: pathHint);
      final sourceStart = fileHunks.isNotEmpty
          ? fileHunks.first.displayIndex
          : index.files
                .firstWhere(
                  (file) => file.path == p,
                  orElse: () => PredictiveFile(p, 0),
                )
                .displayIndex;
      sections.add(
        DiffDocumentSection(
          path: p,
          displayName: displayName,
          index: fi,
          startLine: (sourceStart - leadingTrim).clamp(0, lines.length),
        ),
      );
      if (p.isNotEmpty) {
        filesByPath[p] = DiffFileDocument._(
          path: p,
          displayName: displayName,
          rawContent: '', // metadata only; content lives in the combined doc
          // Deliberately NO lines. Sharing the combined lazy row list here is a
          // footgun: any consumer that iterates the entry (e.g. rebuilding a
          // single-file document via `fromFiles`, whose meta-line condense pass
          // walks every row) would replay — hydrate — the entire multi-file
          // diff, resurrecting the exact freeze this path exists to avoid. A
          // single-file view is rebuilt from the file's own raw slice instead.
          lines: const <ParsedLine>[],
          unitByFastKey: const {},
          pairedAddFastKeys: const {},
          stats: DiffStats(adds: a, dels: d, hunks: fileHunks.length),
          changedLines: a + d,
          payloadBytes: 0,
          maxLineLength: index.maxLineLength,
          cacheKey: 'lazy:$p|$identity',
          isBinary: index.files.any((file) => file.path == p && file.isBinary),
          isLazyMeta: true,
        );
      }
    }

    // The single combined file doc carries the full raw content (so
    // `DiffDocument.rawContent` reconstructs the original) and the total stats.
    //
    // payloadBytes means UTF-8 BYTES everywhere: the eager path estimates
    // them from the String, a spooled store's length IS them on disk — but
    // an in-RAM store's length is UTF-16 code units, which undercounts
    // non-ASCII-heavy diffs up to 3×. Any renderer/telemetry heuristic
    // branching on payloadBytes would drift between backings otherwise.
    final payloadBytes = rawContent != null
        ? _estimateUtf8Bytes(rawContent)
        : index.store.length;
    final combined = DiffFileDocument._(
      path: primaryPath,
      displayName: _displayNameForPath(primaryPath, fallback: pathHint),
      rawContent: content,
      lines: lines,
      unitByFastKey: const {},
      pairedAddFastKeys: const {},
      stats: stats,
      changedLines: index.adds + index.dels,
      payloadBytes: payloadBytes,
      maxLineLength: index.maxLineLength,
      cacheKey: 'lazy:$primaryPath|$identity',
      isBinary: index.isBinary,
    );

    return DiffDocument._(
      documentId: documentId ?? 'lazy:$primaryPath:$identity',
      files: [combined],
      filesByPath: filesByPath,
      // A path's entry must be exactly THAT FILE's slice — a contract every
      // consumer relies on (the blame gate sniffs it for new-file markers;
      // rawSliceForPath returns it first). Storing the combined multi-file
      // content under the primary path broke both: a later new-file section
      // wrongly disabled blame on the FIRST file, and the primary's "slice"
      // was the whole diff. Multi-file lazy docs therefore store nothing
      // here; per-file slices come from the index's exact byte offsets via
      // rawSliceForPath, uniform with the spooled backing.
      rawDiffByPath: {
        // Only a genuine single-file document may store its whole rawContent
        // as the primary path's slice. `!hadDuplicatePath` excludes the
        // malformed `[a.txt, a.txt]` shape, which also dedups to one
        // fileOrder entry but whose rawContent spans TWO sections — there the
        // slice must come from the index's first byte range via
        // rawSliceForPath, never the combined content.
        if (rawContent != null &&
            primaryPath.isNotEmpty &&
            fileOrder.length == 1 &&
            !hadDuplicatePath)
          primaryPath: rawContent,
      },
      lines: lines,
      hunks: List<DiffHunkHeader>.unmodifiable(hunks),
      unitByFastKey: const {},
      pairedAddFastKeys: const {},
      sections: sections,
      stats: stats,
      changedLines: index.adds + index.dels,
      payloadBytes: payloadBytes,
      maxLineLength: index.maxLineLength,
      trimLeadingMeta: trimLeadingMeta,
      newFilePaths: Set<String>.unmodifiable({
        for (final f in index.files)
          if (f.isNewFile && f.path.isNotEmpty) f.path,
      }),
      store: store,
      ownedTempDir: ownedTempDir,
    );
  }

  /// One file's raw unified-diff slice, without materializing the whole
  /// diff: eager documents answer from [rawDiffByPath]; lazy and spooled
  /// documents extract the exact byte range recorded by the index scan
  /// ([PredictiveFile.byteOffset]), so memory is bounded by that single
  /// file's size even when the document is a multi-GB spool. Returns null
  /// when [path] isn't in this document — or when the backing store holds
  /// no diff bytes at all (a working-file-backed doc's store is the raw
  /// FILE; slicing it would hand back contents masquerading as a patch).
  String? rawSliceForPath(String path) {
    final eager = rawDiffByPath[path];
    if (eager != null && eager.isNotEmpty) return eager;
    final l = lines;
    if (l is! LazyDiffLines) return null;
    final idx = l.index;
    if (!idx.storeHoldsUnifiedDiff) return null;
    final fileList = idx.files;
    final i = fileList.indexWhere((f) => f.path == path);
    if (i < 0) return null;
    final start = fileList[i].byteOffset;
    final end = i + 1 < fileList.length
        ? fileList[i + 1].byteOffset
        : idx.store.length;
    if (end <= start) return null;
    return idx.store.substring(start, end);
  }

  bool get isEmpty => lines.isEmpty && rawContent.isEmpty;

  /// Every file path in document order. Derived from [sections] — the one
  /// per-file topology that is real on EVERY backing: the lazy paths store a
  /// single combined entry in [files] (its `path` is just the primary), so
  /// mapping [files] here would collapse a multi-file lazy document to one
  /// bogus path.
  List<String> get orderedPaths => List<String>.unmodifiable([
    for (final section in sections)
      if (section.path.isNotEmpty) section.path,
  ]);

  String get rawContent =>
      _rawContentCache ??= files.map((file) => file.rawContent).join('\n');
}

List<DiffHunkHeader> extractDiffHunks(List<ParsedLine> lines) {
  final result = <DiffHunkHeader>[];
  final fileHunkCounts = <String, int>{};
  final headerIndices = <int>[];
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].kind == LineKind.hunk) {
      headerIndices.add(i);
    }
  }
  for (int h = 0; h < headerIndices.length; h++) {
    final start = headerIndices[h];
    final end = h + 1 < headerIndices.length
        ? headerIndices[h + 1]
        : lines.length;
    var additions = 0;
    var deletions = 0;
    for (var i = start + 1; i < end; i++) {
      final kind = lines[i].kind;
      if (kind == LineKind.added) {
        additions++;
      } else if (kind == LineKind.deleted) {
        deletions++;
      }
    }
    final text = lines[start].text;
    final filePath = lines[start].filePath ?? '';
    final fileHunkIndex = fileHunkCounts[filePath] ?? 0;
    fileHunkCounts[filePath] = fileHunkIndex + 1;
    final match = RegExp(r'^(@@ [^ ]+ [^ ]+ @@)(.*)$').firstMatch(text);
    final rawHeader = match?.group(1) ?? '';
    final rawScope = match?.group(2)?.trim() ?? '';
    // Strip trailing `{` / `:` / ` -` that git often emits after the
    // scope signature — noisy in UI, zero information loss.
    final scope = rawScope.replaceAll(RegExp(r'[\s{:\-]+$'), '');
    final label = match != null
        ? (match.group(1)! + (match.group(2)?.trimRight() ?? ''))
        : text;
    // New-side start line from `+C,D` (or `+C`) half of `@@ -A,B +C,D @@`.
    final startMatch = RegExp(r'\+(\d+)').firstMatch(rawHeader);
    final startLine = startMatch != null
        ? int.tryParse(startMatch.group(1)!) ?? -1
        : -1;
    result.add(
      DiffHunkHeader(
        lineIndex: start,
        filePath: filePath,
        fileHunkIndex: fileHunkIndex,
        label: label,
        additions: additions,
        deletions: deletions,
        scope: scope,
        rawHeader: rawHeader,
        startLine: startLine,
      ),
    );
  }
  return result;
}

List<ParsedLine> trimLeadingMetaLines(List<ParsedLine> lines) =>
    _trimLeadingMetaLines(lines);

List<ParsedLine> _trimLeadingMetaLines(List<ParsedLine> lines) {
  var firstContentIndex = 0;
  while (firstContentIndex < lines.length &&
      lines[firstContentIndex].kind == LineKind.meta) {
    firstContentIndex++;
  }
  // A meta-ONLY document must keep its rows: for an empty or binary file the
  // meta lines ('new file mode …', 'Binary files … differ') ARE the change —
  // trimming them would blank a real file-level change out of the review
  // surface. Trimming only ever removes the redundant header ABOVE content.
  if (firstContentIndex >= lines.length) return lines;
  return firstContentIndex == 0 ? lines : lines.sublist(firstContentIndex);
}

/// Collapse `--- a/path` + `+++ b/path` pairs into a single meta line
/// when the two paths match (the common case — a modification). The
/// old layout rendered both lines, wasting a row on duplicate info
/// the moment you could see either one. Renames keep both lines
/// because the paths actually differ. New files (`--- /dev/null`) and
/// deletions (`+++ /dev/null`) also keep the meaningful side.
List<ParsedLine> condenseDuplicateFilePathMetaLines(List<ParsedLine> lines) =>
    _condenseFilePathMetaLines(lines);

String? _metaPathFromText(String text, String prefix) {
  // Strips `--- a/` / `+++ b/` from the meta line text, leaving just
  // the path. Returns null for `/dev/null` markers and for anything
  // that doesn't look like a file path meta line.
  if (!text.startsWith(prefix)) return null;
  final tail = text.substring(prefix.length).trim();
  if (tail.isEmpty || tail == '/dev/null') return null;
  // git emits paths as `a/<path>` / `b/<path>` by default; strip the
  // one-char prefix + slash when present.
  if (tail.length >= 2 &&
      tail[1] == '/' &&
      (tail[0] == 'a' || tail[0] == 'b')) {
    return tail.substring(2);
  }
  return tail;
}

List<ParsedLine> _condenseFilePathMetaLines(List<ParsedLine> lines) {
  if (lines.length < 2) return lines;
  final out = <ParsedLine>[];
  var i = 0;
  while (i < lines.length) {
    final a = lines[i];
    final b = i + 1 < lines.length ? lines[i + 1] : null;
    if (a.kind == LineKind.meta && b != null && b.kind == LineKind.meta) {
      final oldPath = _metaPathFromText(a.text, '--- ');
      final newPath = _metaPathFromText(b.text, '+++ ');
      if (oldPath != null && newPath != null && oldPath == newPath) {
        // Same path on both sides — this was a modification. Emit
        // just the `+++` line (the "current" state); it stands in
        // for the whole pair. Keep identity stable via fastKey.
        out.add(b);
        i += 2;
        continue;
      }
    }
    out.add(a);
    i++;
  }
  return out;
}

int _estimateUtf8Bytes(String s) {
  var bytes = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x80) {
      bytes++;
    } else if (c < 0x800) {
      bytes += 2;
    } else if (c >= 0xD800 &&
        c <= 0xDBFF &&
        i + 1 < s.length &&
        s.codeUnitAt(i + 1) >= 0xDC00 &&
        s.codeUnitAt(i + 1) <= 0xDFFF) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

String _displayNameForPath(String path, {String? fallback}) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.isNotEmpty) {
    return parts.last;
  }
  if (fallback != null && fallback.isNotEmpty) {
    final fallbackNormalized = fallback.replaceAll('\\', '/');
    final fallbackParts = fallbackNormalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (fallbackParts.isNotEmpty) {
      return fallbackParts.last;
    }
    return fallback;
  }
  return path;
}

String? _resolveDocumentPath(List<ParsedLine> lines, String? pathHint) {
  for (final line in lines) {
    final path = line.filePath;
    if (path != null && path.isNotEmpty) {
      return path;
    }
  }
  return pathHint;
}
