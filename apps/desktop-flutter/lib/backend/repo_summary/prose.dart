// prose.dart — region bodies and elevator-pitch synthesis.
//
// Every slot carries names, counts, or themes. Nothing here surfaces
// percentages, ratios, or engine vocabulary — the physics is the lens,
// not the subject. Themes come from the engram brain's multi-well
// profile averaged over the region; the reader sees a short list of
// Alexandria's learned topics, not a distance vector.

/// One-line body for a region. Summarises size + core share, and
/// surfaces a common directory when every file in the region lives
/// under one — the reader can orient at a glance ("9 files under
/// `apps/desktop/src-tauri/`").
String regionBody({
  required String name,
  required int fileCount,
  required int backboneFileCount,
  required List<String> themes,
  String? commonDirectory,
}) {
  if (fileCount == 0) return '';
  final buf = StringBuffer();
  if (fileCount == 1) {
    buf.write('One file');
  } else {
    buf.write(_plural(fileCount, 'file', 'files'));
  }
  if (backboneFileCount > 0) {
    buf.write(', ${backboneFileCount == 1 ? '1 core' : '$backboneFileCount core'}');
  }
  buf.write('.');
  if (commonDirectory != null && commonDirectory.isNotEmpty) {
    buf.write(' All under `$commonDirectory`.');
  }
  return buf.toString();
}

/// Find the longest directory prefix shared by EVERY path in [paths],
/// provided that prefix has at least one segment and the region has
/// more than one file. Returns null otherwise.
///
/// A region that's exclusively rooted in one directory is often a
/// self-contained subproject (the Rust/Tauri sibling of a Flutter
/// repo, a separate SDK under `packages/`, a legacy tree). Surfacing
/// that location tells the reader whether to care about the region
/// in the context of the codebase's main surface.
String? commonDirectoryFor(List<String> paths) {
  if (paths.length < 2) return null;
  final splits = [for (final p in paths) p.split('/')];
  final minLen = splits
      .map((s) => s.length - 1) // exclude the terminal filename
      .reduce((a, b) => a < b ? a : b);
  if (minLen <= 0) return null;
  final shared = <String>[];
  for (var d = 0; d < minLen; d++) {
    final seg = splits.first[d];
    var allMatch = true;
    for (var i = 1; i < splits.length; i++) {
      if (splits[i][d] != seg) {
        allMatch = false;
        break;
      }
    }
    if (!allMatch) break;
    shared.add(seg);
  }
  if (shared.isEmpty) return null;
  return '${shared.join('/')}/';
}

/// Synthesised opening paragraph when no prose file is available.
/// Lists the top region names without physics vocabulary.
String synthesiseElevatorPitch({
  required String repoName,
  required List<String> topRegionNames,
  required int activeFileCount,
}) {
  if (topRegionNames.isEmpty) {
    return 'A repository of '
        '${_plural(activeFileCount, 'active file', 'active files')}.';
  }
  final joined = topRegionNames.map((n) => '**$n**').join(', ');
  return 'A repository of '
      '${_plural(activeFileCount, 'active file', 'active files')} — $joined.';
}

String _plural(int n, String singular, String plural) {
  return n == 1 ? '$n $singular' : '$n $plural';
}
