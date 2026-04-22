// api.dart — the single orchestrator that produces a RepoDoc.
//
// One function: `generateRepoSummary(repoRoot)`. The pipeline:
//
//   1. harvest tracked text files (binary sniff only; no path allow/deny)
//   2. collect logos git stats (touchMass, ritualness, coupling) —
//      LogosGitStats is the engine's ingest layer
//   3. compute per-file relevance from engine signals:
//         structural × √(1 + touchMass × (1 − ritualness))
//      and cut the active set at the knee of the sorted curve
//   4. encode every active file through the Alexandria brain via
//      EngramHunkEncoder → HunkKVector, yielding path → well-name
//   5. classify every active file via TransportRoles.of(path), yielding
//      path → role flags + concept seed key
//   6. partition the active coupling subgraph with SpectralBasis →
//      spectralCommunityLabels (k from eigengap) → stationaryDistribution
//   7. name each region via modal engram well, falling through to modal
//      transport concept seed, never to filename grep
//   8. assemble (thesis / glance / backbone / regions / getting-started)
//
// The output describes the present. Every classification is engine-
// native. There is no hardcoded extension list, language map, stopword
// set, or conventions allowlist. What isn't the engine's signal isn't
// in this file.

import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../engram_bootstrap.dart';
import '../engram_file_index.dart';
import '../engram_hunk_encoder.dart';
import '../file_coupling.dart';
import '../git.dart' show runGitProbe;
import '../logos_git.dart';
import '../logos_git_integrity.dart' show TransportRoles;
import '../logos_git_stats.dart';
import '../logos_spectrogeometry.dart' show SpectroGeometry, spectrogeometry;
import 'assembler.dart';
import 'curves.dart';
import 'naming.dart';
import 'prose.dart';
import 'purpose.dart';
import 'regions.dart';
import 'relevance.dart';
import 'shape.dart';
import 'text_harvest.dart';
import 'types.dart';

/// Generate a [RepoDoc] for the repository at [repoRoot].
Future<RepoDoc> generateRepoSummary(String repoRoot) async {
  if (repoRoot.isEmpty) {
    throw ArgumentError.value(repoRoot, 'repoRoot', 'must be non-empty');
  }

  final generatedAt = DateTime.now();
  final resolvedRoot = await _resolveRepoRoot(repoRoot);
  final repoName = _deriveRepoName(resolvedRoot);
  final harvest = await harvestTextFiles(resolvedRoot);
  final files = harvest.files;

  if (files.isEmpty) {
    return RepoDoc(
      repoName: repoName,
      elevatorPitch: _emptyRepoPitch(harvest),
      shape: '',
      glance: const RepoStatsGlance(
        activeFileCount: 0,
        activeLines: 0,
        activeBytes: 0,
        roles: [],
        dormantSkipped: 0,
      ),
      backbone: const [],
      regions: const [],
      gettingStarted: '',
      generatedAt: generatedAt,
      totalHarvested: harvest.trackedCount,
    );
  }

  // Git stats + coupling. `generateRepoSummary` is invoked via
  // Flutter's `compute()` from the UI, which spawns a fresh isolate.
  // The `LogosGitResolver` caches are module-level variables —
  // isolate-local — so routing through the resolver from inside the
  // compute isolate would always cold-miss the main isolate's cache
  // AND pay the extra cost of building the full LogosGit engine
  // (CSR graphs, axes, spectral basis warm-up) that we don't need.
  // Going direct gives us exactly what we need and no more.
  LogosGitStats? stats;
  FileCouplingMatrix? coupling;
  try {
    final statsResult = await collectLogosGitStats(resolvedRoot);
    if (statsResult.ok && statsResult.data != null) {
      stats = statsResult.data;
      coupling = stats!.coupling;
    }
  } on Object {
    stats = null;
    coupling = null;
  }

  // Relevance + knee cut. Engine signals only.
  final relevance = computeRelevance(
    files: files,
    stats: stats,
    coupling: coupling,
  );
  final activePaths = relevance.activePaths.isEmpty
      ? relevance.allRanked
      : relevance.activePaths;
  final dormantSkipped = files.length - activePaths.length;
  final activeSet = activePaths.toSet();
  final activeFiles = <HarvestedFile>[];
  for (final f in files) {
    if (activeSet.contains(f.path)) activeFiles.add(f);
  }
  final orderByPath = <String, int>{
    for (var i = 0; i < activePaths.length; i++) activePaths[i]: i,
  };
  activeFiles.sort(
      (a, b) => (orderByPath[a.path] ?? 0).compareTo(orderByPath[b.path] ?? 0));

  // Engine-native file classification.
  final rolesByPath = <String, TransportRoles>{
    for (final f in activeFiles) f.path: TransportRoles.of(f.path),
  };

  // Alexandria brain encoding — per-file K-vector + nearest well.
  // When the engram assets aren't loadable (minimal test environment,
  // stripped build, compute-isolate without a Flutter binary
  // messenger) the encoder is null and wellByPath stays empty; naming
  // then falls through to filename-concept / central-anchor tiers.
  final encoder = await EngramRuntime.instance.mainEncoder();
  Map<String, HunkKVector> kvByPath = const {};
  if (encoder != null) {
    kvByPath = buildEngramFileIndex(
      repoPath: resolvedRoot,
      encoder: encoder,
      paths: activePaths,
    );
  }
  final wellByPath = encodeWellsByPath(
    encoder: encoder,
    kvByPath: kvByPath,
  );

  // Spectral regions.
  final regionResult = findRegions(
    activePaths: activePaths,
    coupling: coupling,
  );

  // Overall architecture archetype (tree / modular / bulk / etc).
  // `spectrogeometry` requires BOTH the graph and a spectral basis —
  // skipped on degenerate fallback paths where either is null.
  SpectroGeometry? geometry;
  if (regionResult.graph != null && regionResult.basis != null) {
    try {
      geometry = spectrogeometry(regionResult.graph!, regionResult.basis!);
    } on Object {
      geometry = null;
    }
  }
  final shape = shapeDescription(geometry);

  // Name each region — wells first, filename-concept second, then
  // structural-anchor fallback ("around `main.dart`"), finally
  // positional.
  final regionPathLists = [for (final r in regionResult.regions) r.paths];
  final regionNames = nameRegions(
    regionPaths: regionPathLists,
    wellByPath: wellByPath,
    rolesByPath: rolesByPath,
    fileCentrality: regionResult.fileCentrality,
  );

  // Backbone: top-of-centrality up to the curve's knee, keystone-
  // weighted so a file central-AND-stable beats one central-AND-
  // thrashing. Touches carry the activity signal.
  final backbone = _buildBackbone(
    fileCentrality: regionResult.fileCentrality,
    regions: regionResult.regions,
    regionNames: regionNames,
    activeFiles: activeFiles,
    touchesByPath: stats?.touches ?? const <String, int>{},
  );
  final backbonePaths = <String>{for (final b in backbone) b.path};

  // Materialise RegionDocs. Per-region themes come from the engram
  // brain's multi-well profile, averaged over the region's K-vectors.
  final regionDocs = <RegionDoc>[];
  for (var i = 0; i < regionResult.regions.length; i++) {
    final r = regionResult.regions[i];
    final neighborNames = <String>[];
    for (final nid in r.neighborIds) {
      if (nid < 0 || nid >= regionNames.length) continue;
      neighborNames.add(regionNames[nid]);
    }
    var backboneInRegion = 0;
    for (final path in r.paths) {
      if (backbonePaths.contains(path)) backboneInRegion++;
    }
    final rawThemes = regionThemes(
      regionPaths: r.paths,
      wellByPath: wellByPath,
    );
    // Drop the tautological theme that matches the region's own name.
    final themes = [
      for (final t in rawThemes) if (t != regionNames[i]) t,
    ];
    regionDocs.add(RegionDoc(
      id: i,
      name: regionNames[i],
      body: regionBody(
        name: regionNames[i],
        fileCount: r.paths.length,
        backboneFileCount: backboneInRegion,
        themes: themes,
        commonDirectory: commonDirectoryFor(r.paths),
      ),
      paths: r.paths,
      neighborNames: List<String>.unmodifiable(neighborNames),
      fileCount: r.paths.length,
      themes: themes,
    ));
  }

  // Glance — active-only, TransportRoles-driven.
  final glance = _glanceFrom(
    activeFiles: activeFiles,
    rolesByPath: rolesByPath,
    dormantSkipped: dormantSkipped,
  );

  // Elevator pitch + getting-started come from the top prose file.
  final proseFile = _findTopProseFile(files);
  final pitch = _pickElevatorPitch(
    proseFile: proseFile,
    repoName: repoName,
    regionNames: regionNames,
    activeFileCount: activeFiles.length,
  );
  final gettingStarted = proseFile == null
      ? ''
      : _extractCodeDenseSection(proseFile.text);

  // History-starved = no edges in the coupling subgraph. That means
  // the centrality ranking collapsed to file-size ordering and the
  // community partition is a single region. Surface that honestly.
  final historyStarved = regionResult.basis == null &&
      regionResult.graph == null &&
      regionResult.regions.length <= 1;

  return RepoDoc(
    repoName: repoName,
    elevatorPitch: pitch,
    shape: shape,
    glance: glance,
    backbone: List<BackboneEntry>.unmodifiable(backbone),
    regions: List<RegionDoc>.unmodifiable(regionDocs),
    gettingStarted: gettingStarted,
    generatedAt: generatedAt,
    totalHarvested: harvest.trackedCount,
    historyStarved: historyStarved,
  );
}

/// Thin re-export so callers only need one import.
String repoDocToMarkdown(RepoDoc doc) => renderMarkdown(doc);

/// Resolve [input] to the true git toplevel. Falls back to [input]
/// when git isn't available or the path isn't inside a repository.
Future<String> _resolveRepoRoot(String input) async {
  try {
    final probe = await runGitProbe(
      input, const ['rev-parse', '--show-toplevel'],
    );
    if (probe.exitCode == 0) {
      final out = probe.stdout.toString().trim();
      if (out.isNotEmpty) {
        return out.replaceAll('\\', '/');
      }
    }
  } on Object {
    // fall through
  }
  return input;
}

String _deriveRepoName(String repoRoot) {
  try {
    final norm = p.normalize(repoRoot);
    final base = p.basename(norm);
    return base.isEmpty ? 'repository' : base;
  } on Object {
    return 'repository';
  }
}

String _emptyRepoPitch(HarvestResult harvest) {
  final parts = <String>[];
  if (harvest.binarySkipped > 0) {
    parts.add('${harvest.binarySkipped} binary');
  }
  if (harvest.decodeFailed > 0) {
    parts.add('${harvest.decodeFailed} unreadable');
  }
  final suffix = parts.isEmpty ? '' : ' (${parts.join(', ')})';
  return 'A repository with no readable text files$suffix.';
}

List<BackboneEntry> _buildBackbone({
  required Map<String, double> fileCentrality,
  required List<RegionCluster> regions,
  required List<String> regionNames,
  required List<HarvestedFile> activeFiles,
  required Map<String, int> touchesByPath,
}) {
  final fileByPath = <String, HarvestedFile>{
    for (final f in activeFiles) f.path: f,
  };
  final regionByPath = <String, String>{};
  for (var i = 0; i < regions.length; i++) {
    final name = i < regionNames.length ? regionNames[i] : 'region ${i + 1}';
    for (final path in regions[i].paths) {
      regionByPath[path] = name;
    }
  }
  // Keystone-weighted score: centrality / log1p(touches). A file that
  // the coupling graph puts at the center AND that the history shows
  // as load-bearing (low churn relative to neighbours) wins. Matches
  // repository_xray's `keystoneScore` formula — we're just routing
  // the same primitive through a different lens.
  final scoreByPath = <String, double>{};
  fileCentrality.forEach((path, centrality) {
    final touches = touchesByPath[path] ?? 0;
    // log(1 + 0) = 0 would blow up, so add 1 to touches before log —
    // zero-touch files (new, no history) get score = centrality / 1.
    final damper = _safeLog1p(touches.toDouble());
    scoreByPath[path] = centrality / (1.0 + damper);
  });

  final ranked = scoreByPath.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      if (c != 0) return c;
      final la = fileByPath[a.key]?.lineCount ?? 0;
      final lb = fileByPath[b.key]?.lineCount ?? 0;
      final lc = lb.compareTo(la);
      return lc != 0 ? lc : a.key.compareTo(b.key);
    });
  final scoresDesc = [for (final e in ranked) e.value];
  final knee = kneeIndex(scoresDesc);
  final out = <BackboneEntry>[];
  for (var i = 0; i < ranked.length && i <= knee; i++) {
    final entry = ranked[i];
    final path = entry.key;
    final file = fileByPath[path];
    if (file == null) continue;
    out.add(BackboneEntry(
      path: path,
      lineCount: file.lineCount,
      regionName: regionByPath[path] ?? 'unassigned',
      purpose: extractPurpose(file, maxChars: 180),
    ));
  }
  return out;
}

double _safeLog1p(double x) {
  if (x <= 0) return 0.0;
  return math.log(1.0 + x);
}

RepoStatsGlance _glanceFrom({
  required List<HarvestedFile> activeFiles,
  required Map<String, TransportRoles> rolesByPath,
  required int dormantSkipped,
}) {
  var totalLines = 0;
  var totalBytes = 0;
  final roleCounts = <String, int>{};
  for (final f in activeFiles) {
    totalLines += f.lineCount;
    totalBytes += f.text.length;
    final roles = rolesByPath[f.path];
    if (roles == null) continue;
    if (roles.isSource) _bumpRole(roleCounts, 'source');
    if (roles.isTest) _bumpRole(roleCounts, 'test');
    if (roles.isDoc) _bumpRole(roleCounts, 'doc');
    if (roles.isGenerated) _bumpRole(roleCounts, 'generated');
    if (roles.isManifest) _bumpRole(roleCounts, 'manifest');
    if (roles.isLockfile) _bumpRole(roleCounts, 'lockfile');
    if (roles.isMigration) _bumpRole(roleCounts, 'migration');
    if (roles.isFixture) _bumpRole(roleCounts, 'fixture');
  }
  final roleList = roleCounts.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });

  return RepoStatsGlance(
    activeFileCount: activeFiles.length,
    activeLines: totalLines,
    activeBytes: totalBytes,
    roles: List<MapEntry<String, int>>.unmodifiable(roleList),
    dormantSkipped: dormantSkipped,
  );
}

void _bumpRole(Map<String, int> counts, String label) {
  counts[label] = (counts[label] ?? 0) + 1;
}

String _pickElevatorPitch({
  required HarvestedFile? proseFile,
  required String repoName,
  required List<String> regionNames,
  required int activeFileCount,
}) {
  if (proseFile != null) {
    final snippet = _firstParagraph(proseFile.text);
    if (snippet.isNotEmpty) return snippet;
  }
  return synthesiseElevatorPitch(
    repoName: repoName,
    topRegionNames: regionNames,
    activeFileCount: activeFileCount,
  );
}

/// The repo's "top prose file" is the markdown file that best serves
/// as an entry-point description. Ranking:
///   1. depth — shallower wins (root beats nested)
///   2. README basename — the cross-ecosystem filesystem convention
///   3. size — larger wins (tiebreak across multiple root markdowns)
///
/// README is a universal protocol-level convention, not a curated
/// per-repo choice; nothing downstream depends on the filename except
/// this one pitch-source selection.
HarvestedFile? _findTopProseFile(List<HarvestedFile> files) {
  HarvestedFile? best;
  var bestDepth = 1 << 30;
  var bestIsReadme = false;
  var bestSize = -1;
  for (final f in files) {
    final base = p.basename(f.path).toLowerCase();
    final dotIdx = base.lastIndexOf('.');
    if (dotIdx < 0) continue;
    final ext = base.substring(dotIdx + 1);
    final isMarkdown = ext == 'md' || ext == 'markdown' || ext == 'mdx';
    if (!isMarkdown) continue;
    final depth = '/'.allMatches(f.path).length;
    final isReadme = base.startsWith('readme');
    final size = f.text.length;
    final betterDepth = depth < bestDepth;
    final sameDepth = depth == bestDepth;
    final betterReadme = sameDepth && isReadme && !bestIsReadme;
    final sameReadme = sameDepth && isReadme == bestIsReadme;
    final betterSize = sameDepth && sameReadme && size > bestSize;
    if (betterDepth || betterReadme || betterSize) {
      best = f;
      bestDepth = depth;
      bestIsReadme = isReadme;
      bestSize = size;
    }
  }
  return best;
}

String _firstParagraph(String text) {
  final lines = text.split('\n');
  final filtered = <String>[];
  var skippedHeadings = false;
  for (final ln in lines) {
    final trimmed = ln.trim();
    if (!skippedHeadings && trimmed.startsWith('#')) continue;
    if (!skippedHeadings && trimmed.isEmpty) continue;
    skippedHeadings = true;
    filtered.add(ln);
  }
  if (filtered.isEmpty) return '';
  final paragraph = <String>[];
  for (final ln in filtered) {
    if (ln.trim().isEmpty) {
      if (paragraph.isNotEmpty) break;
      continue;
    }
    paragraph.add(ln.trim());
  }
  return paragraph.join(' ');
}

/// Extract the heading subtree with the highest fenced-code-block
/// density. Markdown fences are structural tokens, not keywords — a
/// section saturated with them is, by structural definition, the
/// section that shows you commands to run. Returns empty when no
/// section has enough fenced lines to qualify.
String _extractCodeDenseSection(String text) {
  final lines = text.split('\n');
  final headingStarts = <int>[];
  final headingLevels = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final level = _headingLevel(lines[i].trim());
    if (level > 0) {
      headingStarts.add(i);
      headingLevels.add(level);
    }
  }
  if (headingStarts.isEmpty) return '';

  final subtreeEnds = List<int>.filled(headingStarts.length, lines.length);
  for (var i = 0; i < headingStarts.length; i++) {
    for (var j = i + 1; j < headingStarts.length; j++) {
      if (headingLevels[j] <= headingLevels[i]) {
        subtreeEnds[i] = headingStarts[j];
        break;
      }
    }
  }

  var bestIdx = -1;
  var bestScore = 0.0;
  for (var i = 0; i < headingStarts.length; i++) {
    final start = headingStarts[i] + 1;
    final end = subtreeEnds[i];
    if (end - start < 1) continue;
    var fenceLines = 0;
    var inFence = false;
    for (var k = start; k < end; k++) {
      final trimmed = lines[k].trimLeft();
      if (trimmed.startsWith('```')) {
        inFence = !inFence;
        fenceLines++;
        continue;
      }
      if (inFence) fenceLines++;
    }
    if (fenceLines < 2) continue;
    final score = fenceLines / (end - start).toDouble();
    if (score > bestScore) {
      bestScore = score;
      bestIdx = i;
    }
  }
  if (bestIdx < 0) return '';
  final buf = StringBuffer();
  final start = headingStarts[bestIdx] + 1;
  final end = subtreeEnds[bestIdx];
  for (var k = start; k < end; k++) {
    buf.writeln(lines[k]);
  }
  return buf.toString().trim();
}

int _headingLevel(String line) {
  var n = 0;
  while (n < line.length && line[n] == '#') {
    n++;
  }
  if (n == 0 || n > 6) return 0;
  if (n == line.length) return 0;
  if (line[n] != ' ' && line[n] != '\t') return 0;
  return n;
}
