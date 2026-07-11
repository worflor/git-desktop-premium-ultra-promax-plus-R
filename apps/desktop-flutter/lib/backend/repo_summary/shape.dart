// shape.dart — translate engine observables into plain-English prose.
//
// The summary is for a reader who doesn't care about eigenvectors,
// stationary distributions, or Cheeger bounds. This module is the
// contract between the engine's output (archetype distances, well
// profiles, coupling matrices) and the reader's experience (short,
// factual sentences about the codebase). Nothing here adds math;
// every line is a physics-to-English hand-off.

import '../logos_spectrogeometry.dart';
import 'strings.dart';

/// One-line plain-English description of the repo's overall structure,
/// derived from the spectrogeometry archetype. The 6 archetype names
/// the engine produces (`tree`, `modular`, `bulk`, `goe`, `poisson`,
/// `crystalline`) are translated universally — these are physics
/// categories, not repo-specific heuristics.
///
/// Returns empty string when [geometry] is null (spectral basis failed).
String shapeDescription(
  SpectroGeometry? geometry, {
  RepoSummaryStrings strings = const EnglishRepoSummaryStrings(),
}) {
  if (geometry == null) return '';
  final nearest = geometry.universality.nearest;
  final archetype = nearest.name;
  switch (archetype) {
    case 'tree':
      return strings.shapeTree;
    case 'modular':
      return strings.shapeModular;
    case 'bulk':
      return strings.shapeBulk;
    case 'crystalline':
      return strings.shapeCrystalline;
    case 'goe':
      return strings.shapeGoe;
    case 'poisson':
      return strings.shapePoisson;
    default:
      return '';
  }
}

/// Return the distinct nearest-well names that files in this region
/// resolve to, ranked by how many files hit each well. Mirrors the
/// signal that `naming` uses (per-file modal well) but surfaces the
/// SECONDARY wells that discriminate the region beyond its own name.
///
/// Placeholder wells (Alexandria's `well_<N>` convention for clusters
/// it learned but didn't label) are dropped — they're the brain's
/// own "unknown" signal, not a theme.
///
/// Takes the per-file well map (already produced by the pipeline via
/// either the resolver's cached `EngramFileKTable` or a fallback
/// encode pass) so this module doesn't need to know about brains or
/// K-vectors.
List<String> regionThemes({
  required List<String> regionPaths,
  required Map<String, String> wellByPath,
  int top = 3,
}) {
  if (regionPaths.isEmpty) return const [];
  if (wellByPath.isEmpty) return const [];
  final counts = <String, int>{};
  for (final path in regionPaths) {
    final name = wellByPath[path];
    if (name == null || name.isEmpty) continue;
    if (_isPlaceholderWellName(name)) continue;
    counts[name] = (counts[name] ?? 0) + 1;
  }
  if (counts.isEmpty) return const [];
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [for (final e in entries.take(top)) e.key];
}

bool _isPlaceholderWellName(String name) {
  if (!name.startsWith('well_')) return false;
  for (var i = 5; i < name.length; i++) {
    final c = name.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return false;
  }
  return name.length > 5;
}
