// types.dart — data structures carried across the repo summary pipeline.
//
// Every primitive here operates on raw text (files, lines). Extensions
// are reported verbatim (no extension→language mapping); the reader
// infers domain from the extension directly. Conventions and
// getting-started text are extracted from the repo's own README —
// there is no curated filename list.

import 'dart:typed_data';

/// A text-bearing tracked file.
class HarvestedFile {
  HarvestedFile({
    required this.path,
    required this.text,
    required this.lineOffsets,
  });

  final String path;
  final String text;
  final Int32List lineOffsets;

  int get lineCount => lineOffsets.length - 1;

  int lineAt(int byteOffset) {
    var lo = 0, hi = lineOffsets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (lineOffsets[mid] <= byteOffset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

/// Pointer to a contiguous range within a file.
class FileSpan {
  const FileSpan({
    required this.path,
    required this.lineStart,
    required this.lineEnd,
  });
  final String path;
  final int lineStart;
  final int lineEnd;
}

/// One region of the codebase as identified by spectral community
/// detection on the co-change coupling graph.
class RegionDoc {
  const RegionDoc({
    required this.id,
    required this.name,
    required this.body,
    required this.paths,
    required this.neighborNames,
    required this.fileCount,
    required this.themes,
  });

  final int id;
  final String name;
  final String body;
  final List<String> paths;
  final List<String> neighborNames;
  final int fileCount;
  /// Top Alexandria wells this region's files resolve to, ordered by
  /// aggregated well-profile proximity. Empty when the brain isn't
  /// loaded or the region's files didn't encode.
  final List<String> themes;
}

/// One entry in the "Core" section — a file the spectral stationary
/// distribution (keystone-weighted) places near the top of the
/// coupling graph's structural center. The numerical centrality
/// drove the selection but is not surfaced to the reader.
class BackboneEntry {
  const BackboneEntry({
    required this.path,
    required this.lineCount,
    required this.regionName,
    required this.purpose,
  });

  final String path;
  final int lineCount;
  final String regionName;
  /// One-line description extracted from the file's leading doc
  /// comment or first declaration. Empty when nothing useful
  /// surfaced in the file's head.
  final String purpose;
}

/// "At a glance" — derived from the active file set only. The role
/// breakdown comes from the engine's [TransportRoles] classifier, not
/// from extension grep; "source" here means "the logos engine marks
/// this path as isSource" with all the semantic nuance that carries.
class RepoStatsGlance {
  const RepoStatsGlance({
    required this.activeFileCount,
    required this.activeLines,
    required this.activeBytes,
    required this.roles,
    required this.dormantSkipped,
  });

  final int activeFileCount;
  final int activeLines;
  final int activeBytes;
  /// Role → active-file count, descending by count. Roles are the
  /// enum of flags [TransportRoles] exposes (source, test, doc,
  /// generated, manifest, lockfile, migration, fixture). A file that
  /// matches multiple roles contributes to each bucket.
  final List<MapEntry<String, int>> roles;
  /// Files harvested but filtered out by the relevance knee.
  final int dormantSkipped;
}

/// The final assembled document. Call `renderMarkdown(doc)` from
/// assembler.dart to produce the markdown blob.
class RepoDoc {
  const RepoDoc({
    required this.repoName,
    required this.elevatorPitch,
    required this.shape,
    required this.glance,
    required this.backbone,
    required this.regions,
    required this.gettingStarted,
    required this.generatedAt,
    required this.totalHarvested,
    this.historyStarved = false,
  });

  final String repoName;
  /// Pulled verbatim from the repo's top prose file (largest
  /// root-depth markdown), or synthesised from region names when no
  /// such file exists.
  final String elevatorPitch;
  /// One-line natural-language description of the repo's overall
  /// architecture, derived from the spectrogeometry archetype. Empty
  /// when the basis couldn't be built (degenerate graph).
  final String shape;
  final RepoStatsGlance glance;
  /// Files whose coupling centrality puts them at the structural
  /// core. Count self-calibrated by the centrality distribution.
  final List<BackboneEntry> backbone;
  /// How many files the repo harvested in total (before any filter).
  /// Renders as "Showing N of M, ranked …" so the reader sees the
  /// ratio rather than an opaque "N omitted."
  final int totalHarvested;
  /// Regions in presentation order (largest first).
  final List<RegionDoc> regions;
  /// Extracted setup text from the repo's top prose file.
  final String gettingStarted;
  /// When true, the coupling graph had no edges — the pipeline ran
  /// in a degenerate mode (usually a fresh clone with one commit,
  /// a detached worktree, or a repo where every commit touched a
  /// single file). Rendered as a one-line caveat so a reader can
  /// judge the ranking quality.
  final bool historyStarved;
  final DateTime generatedAt;
}
