// naming.dart — engine-native region naming.
//
// Every label comes from a logos primitive, never from filename grep:
//
//   Tier 1  ENGRAM WELL
//   Each file in the active set is encoded through the Alexandria brain
//   (EngramHunkEncoder.encode → HunkKVector → EngramWellMatch). The
//   well name IS the semantic label Alexandria trained on. A region's
//   name is its modal well — greedy assignment across regions so the
//   most dominant well claims its region first.
//
//   Tier 2  FILENAME CONCEPT (ordered)
//   Replays the engine's own `_transportConceptTokens` tokenization
//   pipeline locally (non-word split + camelCase boundary + noise
//   filter) — but keeps first-occurrence order instead of the engine's
//   alphabetical sort, and skips plural-stemming. Produces readable
//   region names like `engram_bootstrap` rather than `bootstrap-engram`.
//
//   Tier 3  TRANSPORT SEED KEY
//   Falls back to the engine's own `concept:` seed when even the
//   filename-concept tokens came up empty (paths with no word
//   characters at all — rare, but handled).
//
//   Tier 4  NUMBERED FALLBACK
//   `region N` positional label when everything above declined.

import '../engram_hunk_encoder.dart';
import '../logos_git_integrity.dart' show TransportRoles, logosTransportSeedKey;

/// Produce a display name per region. [regionPaths] is one path-list
/// per region. The other two maps are engine-produced:
///   [wellByPath] — file → Alexandria well name (empty when the brain
///                   isn't loaded or the file failed to encode).
///   [rolesByPath] — file → TransportRoles.
List<String> nameRegions({
  required List<List<String>> regionPaths,
  required Map<String, String> wellByPath,
  required Map<String, TransportRoles> rolesByPath,
  Map<String, double>? fileCentrality,
}) {
  final used = <String>{};
  final names = List<String>.filled(regionPaths.length, '', growable: false);

  // Pass A: modal Alexandria well, greedy across regions.
  final wellRanks = <int, List<MapEntry<String, int>>>{};
  for (var ri = 0; ri < regionPaths.length; ri++) {
    wellRanks[ri] = _modalCounts(regionPaths[ri], wellByPath);
  }
  final remaining = <int>{for (var i = 0; i < regionPaths.length; i++) i};
  while (remaining.isNotEmpty) {
    int? bestRegion;
    String? bestWell;
    var bestCoverage = 0.0;
    for (final ri in remaining) {
      final entries = wellRanks[ri]!;
      for (final e in entries) {
        if (used.contains(e.key)) continue;
        final coverage = e.value / regionPaths[ri].length;
        if (coverage <= bestCoverage) continue;
        bestCoverage = coverage;
        bestRegion = ri;
        bestWell = e.key;
      }
    }
    if (bestRegion == null || bestWell == null) break;
    names[bestRegion] = bestWell;
    used.add(bestWell);
    remaining.remove(bestRegion);
  }

  // Pass B: filename-concept prefix, order-preserving.
  for (final ri in remaining.toList()) {
    final candidate = _filenameConceptName(regionPaths[ri]);
    if (candidate == null) continue;
    if (used.add(candidate)) {
      names[ri] = candidate;
      remaining.remove(ri);
    }
  }

  // Pass C: anchor to the region's highest-centrality file. When
  // tiers 1 and 2 both declined, this region doesn't have a shared
  // concept — but it DOES have a structural anchor (the file the
  // spectral stationary distribution puts at the middle of its
  // coupling neighborhood). Naming the region after that file is
  // honest: "these files cluster around `workspace_shell.dart`."
  for (final ri in remaining.toList()) {
    final anchor = _centralAnchor(regionPaths[ri], fileCentrality);
    if (anchor == null || anchor.isEmpty) continue;
    // Use the bare identifier as the name. The assembler's region
    // label will italicise multi-word names automatically, rendering
    // as "_around main_" — no nested backticks.
    final candidate = 'around $anchor';
    if (used.add(candidate)) {
      names[ri] = candidate;
      remaining.remove(ri);
    }
  }

  // Pass D: engine transport seed key. When centrality isn't available
  // (fresh repo, degenerate graph), fall back to the engine's own
  // concept seed. Dotfile basenames (`.gitignore`, `.gitattributes`)
  // produce noisy concept tokens when fed through the transport
  // tokenizer — their leading dot and short stems yield nothing
  // semantic — so we skip them and let a non-dotfile in the region
  // drive the name.
  for (final ri in remaining.toList()) {
    final conceptCounts = <String, int>{};
    for (final path in regionPaths[ri]) {
      if (_isDotfile(path)) continue;
      final roles = rolesByPath[path];
      final seed = roles?.seedKey ?? logosTransportSeedKey(path);
      if (seed == null) continue;
      if (!seed.startsWith('concept:')) continue;
      final body = seed.substring('concept:'.length);
      conceptCounts[body] = (conceptCounts[body] ?? 0) + 1;
    }
    if (conceptCounts.isEmpty) continue;
    final ranked = conceptCounts.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    for (final e in ranked) {
      if (used.add(e.key)) {
        names[ri] = e.key;
        remaining.remove(ri);
        break;
      }
    }
  }

  // Pass D: positional fallback.
  for (final ri in remaining) {
    var candidate = 'region ${ri + 1}';
    var n = ri + 2;
    while (used.contains(candidate)) {
      candidate = 'region $n';
      n++;
    }
    names[ri] = candidate;
    used.add(candidate);
  }

  return names;
}

/// True when [path]'s basename starts with `.` — a Unix dotfile.
/// Dotfiles' basename tokens (`gitignore`, `gitattributes`, `editorconfig`)
/// are structural metadata, not content-describing; they should never
/// drive a region's name.
bool _isDotfile(String path) {
  final slash = path.lastIndexOf('/');
  final base = slash < 0 ? path : path.substring(slash + 1);
  return base.isNotEmpty && base.startsWith('.');
}

/// Pick the region's structural anchor — the highest-centrality file
/// in the region's path list. Returns the file's basename (without
/// extension) or null if no centrality data is available or the
/// region is empty.
/// Names that every ecosystem reserves for "the entry point of this
/// directory" — Rust `mod.rs`, Python `__init__.py`, JS/TS `index.ts`,
/// Dart `lib.dart`, etc. When these turn out to be the central anchor
/// of a region, using their basename tells the reader nothing about
/// WHAT the region does — every directory has one. Fall back to the
/// parent directory name in that case, which DOES carry semantic
/// weight (`around src-tauri` vs. `around mod`).
const Set<String> _languageContainerBasenames = <String>{
  'mod', 'index', 'main', 'lib', '__init__', '_init', 'init',
  'package', 'module', 'entry',
};

String? _centralAnchor(List<String> paths, Map<String, double>? centrality) {
  if (paths.isEmpty || centrality == null) return null;
  String? best;
  var bestScore = -double.infinity;
  for (final path in paths) {
    final score = centrality[path] ?? 0.0;
    if (score > bestScore) {
      bestScore = score;
      best = path;
    }
  }
  if (best == null) return null;
  final slashIdx = best.lastIndexOf('/');
  final base = slashIdx < 0 ? best : best.substring(slashIdx + 1);
  final dotIdx = base.indexOf('.');
  final stem = dotIdx < 0 ? base : base.substring(0, dotIdx);
  // If the central file is a language-convention container name,
  // climb the directory chain until we find a segment that isn't
  // also a container — `main.dart` inside `lib/` in `desktop-flutter/`
  // becomes `desktop-flutter`, not `lib`.
  if (_languageContainerBasenames.contains(stem.toLowerCase())) {
    final segments = best.split('/');
    for (var i = segments.length - 2; i >= 0; i--) {
      final seg = segments[i];
      if (seg.isEmpty) continue;
      if (_languageContainerBasenames.contains(seg.toLowerCase())) continue;
      return seg;
    }
  }
  return stem;
}

/// Count how many paths in [paths] fall under each value of [byPath],
/// returning entries sorted by descending count.
List<MapEntry<String, int>> _modalCounts(
  List<String> paths,
  Map<String, String> byPath,
) {
  final counts = <String, int>{};
  for (final p in paths) {
    final label = byPath[p];
    if (label == null || label.isEmpty) continue;
    counts[label] = (counts[label] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return entries;
}

/// Encode every path in [paths] through the Alexandria brain, returning
/// a path → well-name map. Paths that fail to encode are omitted.
Map<String, String> encodeWellsByPath({
  required EngramHunkEncoder? encoder,
  required Map<String, HunkKVector> kvByPath,
}) {
  final out = <String, String>{};
  if (encoder == null) return out;
  kvByPath.forEach((path, kv) {
    final match = kv.well;
    if (match == null) return;
    out[path] = match.name;
  });
  return out;
}

// ───────────────────────────────────────────────────────────────────────
// Filename-concept tokenization: mirrors the engine's
// `_transportConceptTokens` + `_normalizeTransportToken` logic in
// `logos_git_integrity.dart`, but preserves first-occurrence order
// and skips plural stemming. The engine alphabetises + stems because
// its purpose is CLUSTER MATCHING (two files that share the same
// token bag should produce the same seed regardless of token order).
// For DISPLAY we want "branches_page", not "branche-page".
// ───────────────────────────────────────────────────────────────────────

final RegExp _conceptNonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final RegExp _conceptCamelBoundary =
    RegExp(r'(?<=[\p{Ll}\p{N}])(?=[\p{Lu}])', unicode: true);
final RegExp _conceptExtension = RegExp(r'\.[^.]+$');
final RegExp _conceptAllDigits = RegExp(r'^\d+$');

/// Noise tokens — identical to the engine's set. These are tokens that
/// appear across so many files they carry no semantic discrimination.
final Set<String> _conceptNoise = <String>{
  'test', 'tests', 'spec', 'specs', 'doc', 'docs', 'readme',
  'generated', 'generate', 'gen', 'migration', 'migrations',
  'schema', 'sql', 'index', 'main', 'lib', 'src',
  'add', 'update', 'create', 'delete',
};

/// Tokenize a path the way the engine does (filename + doc parent dir),
/// but return an ORDERED list of tokens with first-occurrence uniqueness.
List<String> _orderedConceptTokens(String path) {
  final parts = path.split('/');
  final raw = <String>[];
  if (parts.isEmpty) return const [];
  raw.add(parts.last);
  // Docs + migrations also include their parent directory (engine
  // convention — `docs/auth.md` → concept "auth", not just "auth").
  final lower = path.toLowerCase();
  final isDoc = lower.endsWith('.md') ||
      lower.endsWith('.mdx') ||
      lower.endsWith('.rst') ||
      lower.contains('/docs/') ||
      lower.contains('/doc/');
  final isMigration = lower.contains('/migration/') ||
      lower.contains('/migrations/') ||
      lower.endsWith('.sql');
  if ((isDoc || isMigration) && parts.length > 1) {
    raw.add(parts[parts.length - 2]);
  }

  final seen = <String>{};
  final ordered = <String>[];
  for (final piece in raw) {
    final stem = piece.replaceAll(_conceptExtension, '');
    for (final word in stem.split(_conceptNonWord)) {
      if (word.isEmpty) continue;
      for (final sub in word.split(_conceptCamelBoundary)) {
        final token = _normalizeForDisplay(sub);
        if (token == null) continue;
        if (seen.add(token)) ordered.add(token);
      }
    }
  }
  return ordered;
}

/// Normalise for DISPLAY: lowercase + noise filter + digit reject.
/// No plural stemming — we want `branches`, not `branche`.
String? _normalizeForDisplay(String token) {
  final lower = token.toLowerCase();
  if (lower.length < 3) return null;
  if (_conceptNoise.contains(lower)) return null;
  if (_conceptAllDigits.hasMatch(lower)) return null;
  return lower;
}

/// Build a region name from the longest common prefix-sequence of its
/// files' filename-concept tokens. When no prefix is shared by at
/// least two files, fall back to the most-common first token across
/// the region. Returns null when every file's token list is empty.
String? _filenameConceptName(List<String> paths) {
  if (paths.isEmpty) return null;
  final perFile = <List<String>>[];
  for (final p in paths) {
    final toks = _orderedConceptTokens(p);
    if (toks.isNotEmpty) perFile.add(toks);
  }
  if (perFile.isEmpty) return null;

  // Longest common prefix across ALL files. A 2+ token prefix is rare
  // but highly descriptive when it exists (`logos_git_` for probe +
  // stats + resolver).
  final common = <String>[];
  final minLen = perFile
      .map((l) => l.length)
      .reduce((a, b) => a < b ? a : b);
  for (var i = 0; i < minLen; i++) {
    final candidate = perFile.first[i];
    final allMatch = perFile.every((l) => l[i] == candidate);
    if (!allMatch) break;
    common.add(candidate);
  }

  if (common.isNotEmpty) {
    // All files share this prefix; use it verbatim (engine-tokenized,
    // ordered). A trailing underscore flags it as a naming pattern.
    return '${common.join('_')}_';
  }

  // No shared prefix — take the most common first-token across the
  // region as a rough label. If no single token dominates, null out
  // and let the next tier handle it.
  final firstTokenCounts = <String, int>{};
  for (final tokens in perFile) {
    if (tokens.isEmpty) continue;
    final t = tokens.first;
    firstTokenCounts[t] = (firstTokenCounts[t] ?? 0) + 1;
  }
  if (firstTokenCounts.isEmpty) return null;
  // Require majority to avoid spurious labels.
  var bestToken = '';
  var bestCount = 0;
  firstTokenCounts.forEach((tok, count) {
    if (count > bestCount) {
      bestCount = count;
      bestToken = tok;
    }
  });
  if (bestCount * 2 <= perFile.length) return null;
  return '${bestToken}_';
}
