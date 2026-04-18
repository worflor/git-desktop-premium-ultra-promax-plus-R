import 'dart:convert';

import 'diff_models.dart';
import 'edit_units.dart';

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

    final units = buildEditUnits(parsedLines, detectMoves: true);
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

    final stats = DiffStats(
      adds: parsedLines.where((line) => line.kind == LineKind.added).length,
      dels: parsedLines.where((line) => line.kind == LineKind.deleted).length,
      hunks: parsedLines.where((line) => line.kind == LineKind.hunk).length,
    );

    final normalizedPath = resolvedPath ?? pathHint ?? '';
    return DiffFileDocument._(
      path: normalizedPath,
      displayName: _displayNameForPath(normalizedPath, fallback: pathHint),
      rawContent: rawContent,
      lines: List<ParsedLine>.unmodifiable(parsedLines),
      unitByFastKey: Map<int, EditUnit>.unmodifiable(unitMap),
      pairedAddFastKeys: Set<int>.unmodifiable(pairedAdds),
      stats: stats,
      changedLines: stats.adds + stats.dels,
      payloadBytes: utf8.encode(rawContent).length,
      maxLineLength: parsedLines.fold<int>(
        0,
        (maxChars, line) =>
            line.text.length > maxChars ? line.text.length : maxChars,
      ),
      cacheKey: cacheKey ?? '${normalizedPath}|${rawContent.hashCode}',
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
  });

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

    final fullLines = <ParsedLine>[
      for (final file in orderedFiles) ...file.lines,
    ];
    final viewLines =
        trimLeadingMeta ? _trimLeadingMetaLines(fullLines) : fullLines;

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
      final file = orderedFiles[i];
      final fileLines = trimLeadingMeta && i == 0
          ? _trimLeadingMetaLines(file.lines)
          : file.lines;
      sections.add(
        DiffDocumentSection(
          path: file.path,
          displayName: file.displayName,
          index: i,
          startLine: lineOffset,
        ),
      );
      lineOffset += fileLines.length;
    }

    return DiffDocument._(
      documentId: documentId ??
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

  bool get isEmpty => lines.isEmpty && rawContent.isEmpty;

  List<String> get orderedPaths =>
      List<String>.unmodifiable(files.map((file) => file.path));

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
    final end =
        h + 1 < headerIndices.length ? headerIndices[h + 1] : lines.length;
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
    final startLine =
        startMatch != null ? int.tryParse(startMatch.group(1)!) ?? -1 : -1;
    result.add(
      DiffHunkHeader(
        lineIndex: start,
        filePath: filePath,
        fileHunkIndex: fileHunkIndex,
        label: label.length > 60 ? '${label.substring(0, 57)}...' : label,
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
  return firstContentIndex == 0 ? lines : lines.sublist(firstContentIndex);
}

String _displayNameForPath(String path, {String? fallback}) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.isNotEmpty) {
    return parts.last;
  }
  if (fallback != null && fallback.isNotEmpty) {
    final fallbackNormalized = fallback.replaceAll('\\', '/');
    final fallbackParts =
        fallbackNormalized.split('/').where((part) => part.isNotEmpty).toList();
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
