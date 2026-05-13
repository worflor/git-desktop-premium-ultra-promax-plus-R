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

/// Per-file computed profile — the derived data from the Logos pipeline,
/// stripped of physics internals.
class FileProfile {
  const FileProfile({
    required this.path,
    required this.relevance,
    required this.centrality,
    required this.activity,
    required this.authenticity,
    required this.lineCount,
    required this.role,
    required this.regionId,
    this.well,
  });

  final String path;
  final double relevance;
  final double centrality;
  final double activity;
  final double authenticity;
  final int lineCount;
  final String role;
  final int regionId;
  final String? well;

  Map<String, dynamic> toJson() => {
        'path': path,
        'relevance': _r(relevance),
        'centrality': _r(centrality),
        'activity': _r(activity),
        'authenticity': _r(authenticity),
        'lineCount': lineCount,
        'role': role,
        'regionId': regionId,
        if (well != null) 'well': well,
      };
}

/// A co-change coupling edge between two files.
class CouplingEdge {
  const CouplingEdge({
    required this.source,
    required this.target,
    required this.weight,
  });

  final String source;
  final String target;
  final double weight;

  Map<String, dynamic> toJson() => {
        'source': source,
        'target': target,
        'weight': _r(weight),
      };
}

/// Coupling weight between two regions.
class RegionLink {
  const RegionLink({
    required this.sourceRegionId,
    required this.targetRegionId,
    required this.weight,
  });

  final int sourceRegionId;
  final int targetRegionId;
  final double weight;

  Map<String, dynamic> toJson() => {
        'sourceRegionId': sourceRegionId,
        'targetRegionId': targetRegionId,
        'weight': _r(weight),
      };
}

double _r(double v) => double.parse(v.toStringAsFixed(4));

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
    this.cohesion = 0.0,
    this.internalWeight = 0.0,
    this.externalWeight = 0.0,
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
  final double cohesion;
  final double internalWeight;
  final double externalWeight;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'body': body,
        'fileCount': fileCount,
        'themes': themes,
        'neighborNames': neighborNames,
        'cohesion': _r(cohesion),
        'internalWeight': _r(internalWeight),
        'externalWeight': _r(externalWeight),
        'paths': paths,
      };
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
    this.centrality = 0.0,
    this.keystoneScore = 0.0,
  });

  final String path;
  final int lineCount;
  final String regionName;
  /// One-line description extracted from the file's leading doc
  /// comment or first declaration. Empty when nothing useful
  /// surfaced in the file's head.
  final String purpose;
  final double centrality;
  final double keystoneScore;

  Map<String, dynamic> toJson() => {
        'path': path,
        'lineCount': lineCount,
        'regionName': regionName,
        'purpose': purpose,
        'centrality': _r(centrality),
        'keystoneScore': _r(keystoneScore),
      };
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
  final List<MapEntry<String, int>> roles;
  final int dormantSkipped;

  Map<String, dynamic> toJson() => {
        'activeFileCount': activeFileCount,
        'activeLines': activeLines,
        'activeBytes': activeBytes,
        'roles': {for (final e in roles) e.key: e.value},
        'dormantSkipped': dormantSkipped,
      };
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
    this.files = const [],
    this.couplingEdges = const [],
    this.regionLinks = const [],
    this.archetypeDistances = const {},
    this.canonicality = 0.0,
  });

  final String repoName;
  final String elevatorPitch;
  final String shape;
  final RepoStatsGlance glance;
  final List<BackboneEntry> backbone;
  final int totalHarvested;
  final List<RegionDoc> regions;
  final String gettingStarted;
  final bool historyStarved;
  final DateTime generatedAt;
  final List<FileProfile> files;
  final List<CouplingEdge> couplingEdges;
  final List<RegionLink> regionLinks;
  final Map<String, double> archetypeDistances;
  final double canonicality;

  Map<String, dynamic> toJson() => {
        'repoName': repoName,
        'elevatorPitch': elevatorPitch,
        'gettingStarted': gettingStarted,
        'shape': shape,
        'stats': glance.toJson(),
        'backbone': [for (final b in backbone) b.toJson()],
        'regions': [for (final r in regions) r.toJson()],
        'files': [for (final f in files) f.toJson()],
        'couplingEdges': [for (final e in couplingEdges) e.toJson()],
        'regionLinks': [for (final l in regionLinks) l.toJson()],
        if (archetypeDistances.isNotEmpty)
          'archetypeDistances': {
            for (final e in archetypeDistances.entries) e.key: _r(e.value),
          },
        'canonicality': _r(canonicality),
        'totalHarvested': totalHarvested,
        'historyStarved': historyStarved,
      };
}
