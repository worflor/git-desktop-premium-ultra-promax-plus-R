// ═════════════════════════════════════════════════════════════════════════
// semantic_manifest.dart — structured change summary for AI prompts
//
// Upstream of the packed diff in the commit-message / review prompt, the
// model benefits from a *pre-computed* story of what the commit actually
// does: which themes dominate, which tokens moved (vs were removed),
// which identifiers are truly new, and which hunks carry the most
// semantic weight.
//
// The raw unified diff asks the model to do cross-hunk reasoning on
// fragmented text — and it gets that wrong on large commits. The classic
// failure: an enum value `kirby` is deleted from one position and
// re-inserted two lines earlier. The model sees `-  kirby,` near the end
// of its context window and reports a removal, never reconciling it with
// the `+  kirby,` it saw a hundred lines prior.
//
// The semantic engine (engram K-vectors, logos diffusion, well
// assignment) already reasons across hunks. This file turns those
// outputs into a compact, bounded manifest that ships *above* the packed
// diff so the model gets the story first and the bytes second.
//
// Scale: manifest size grows with *themes* and *files*, not with diff
// size. A five-hunk diff and a five-thousand-hunk diff produce manifests
// of similar order. The raw diff remains in the prompt as evidence; the
// manifest is the narrative that prevents diff-archaeology hallucination.
//
// Inputs:
//   • Required: ranked hunks from `rankHunksByPhiAsync` — carry φ and
//     well assignment per hunk.
//   • Optional [SymbolFrequencyIndex]: corpus-wide IDF. When provided,
//     add/remove token ranking uses true rarity ("self-learning
//     stop-word filter") instead of a commit-local frequency proxy.
//   • Optional [FileCouplingMatrix]: historical co-change data. When
//     provided, surfaces file pairs touched in this commit that have
//     moved together in the past — the commit's structural story.
// Both optional inputs degrade gracefully: null = skip that signal, not
// error. The manifest still emits usefully on the φ + well axis alone.
// ═════════════════════════════════════════════════════════════════════════

import 'package:meta/meta.dart';

import 'file_coupling.dart' show FileCouplingMatrix, SymbolFrequencyIndex;
import 'logos_hunks.dart' show DiffHunk, HunkRanking;

// ── Identifier extraction ────────────────────────────────────────────────

/// Matches identifier-shaped runs. Same shape as the engram file-index
/// tokeniser so move/add/remove detection classifies tokens on the same
/// grid that the well assignment used.
final RegExp _kIdentifierRe = RegExp(r'[A-Za-z_][A-Za-z0-9_]{1,40}');

/// Hard-skip tokens: language keywords, core collection types, pervasive
/// standard-library names. These appear in every diff as noise and
/// should never become "additions" or "removals" the model narrates
/// unless explicitly asked to. Keep this list tight — domain words do
/// NOT belong here, only true boilerplate.
const Set<String> _kSkipTokens = {
  // Dart keywords
  'abstract', 'as', 'async', 'await', 'break', 'case', 'catch', 'class',
  'const', 'continue', 'covariant', 'default', 'deferred', 'do', 'dynamic',
  'else', 'enum', 'export', 'extends', 'extension', 'external', 'factory',
  'false', 'final', 'finally', 'for', 'function', 'get', 'hide', 'if',
  'implements', 'import', 'in', 'interface', 'is', 'late', 'library',
  'mixin', 'new', 'null', 'of', 'on', 'operator', 'part', 'required',
  'rethrow', 'return', 'sealed', 'set', 'show', 'static', 'super',
  'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef', 'var',
  'void', 'when', 'while', 'with', 'yield',
  // Core types that dominate every Dart diff
  'int', 'double', 'bool', 'num', 'String', 'List', 'Map', 'Set',
  'Iterable', 'Iterator', 'Future', 'Stream', 'Object', 'Function',
  'Never', 'Null', 'Uint8List', 'Float64List', 'Int32List', 'ByteData',
  'StringBuffer', 'Duration',
  // Common method/property noise
  'toString', 'hashCode', 'runtimeType', 'length', 'isEmpty', 'isNotEmpty',
  // Import prefixes
  'dart', 'flutter', 'package',
};

/// Minimum identifier length to consider. Tokens of 1–2 chars are almost
/// always parameter names or index variables — noise for the manifest.
const int _kMinTokenLen = 3;

// ── Manifest shape ───────────────────────────────────────────────────────

/// Structured pre-computed summary of a commit, designed to be emitted
/// ABOVE the packed diff so the model has a trustworthy narrative frame
/// before it starts reading raw hunks.
class SemanticManifest {
  SemanticManifest({
    required this.filesTouched,
    required this.totalHunks,
    required this.themes,
    required this.moves,
    required this.crossFileMoves,
    required this.additionsByFile,
    required this.removalsByFile,
    required this.couplingPairs,
    required this.topHunks,
    required this.idfAvailable,
  });

  final int filesTouched;
  final int totalHunks;

  /// Top wells (semantic clusters from Alexandria) weighted by φ mass.
  /// Empty when engram wasn't loaded or no hunks produced a well match.
  final List<ThemeEntry> themes;

  /// Tokens that appear in BOTH removed and added lines within the same
  /// file. Interpreted as moves / reorderings / reformats — *not*
  /// removals. This is the signal that collapses the most common
  /// model-hallucination class (symbol moved across distant hunks read
  /// as "symbol removed").
  final List<MoveEntry> moves;

  /// Tokens removed in some files and added in *different* files — the
  /// signature of a symbol migration, cross-file rename, or refactor
  /// that relocates code across module boundaries. These are the cases
  /// the raw diff presents as independent remove+add events; the
  /// manifest reunifies them so the model narrates a migration rather
  /// than hallucinating removal + unrelated addition.
  final List<CrossFileMoveEntry> crossFileMoves;

  /// Per-file tokens appearing ONLY in added lines, minus keywords and
  /// minus any token that also appears in a removed line for that file.
  /// Bounded per-file to keep the manifest compact on mega-commits.
  /// Ranked by corpus IDF when [idfAvailable], otherwise by commit-wide
  /// frequency.
  final Map<String, List<String>> additionsByFile;

  /// Per-file tokens appearing ONLY in removed lines. Same filtering as
  /// [additionsByFile].
  final Map<String, List<String>> removalsByFile;

  /// File pairs touched in this commit whose historical Jaccard
  /// coupling exceeds the manifest threshold — "these two usually
  /// change together, so narrate them together." Empty when no
  /// coupling matrix was supplied, or when no pair crossed the floor.
  final List<CouplingEntry> couplingPairs;

  /// Top-K hunks by φ (logos diffusion salience). The "map" the model
  /// should navigate to first.
  final List<TopHunkEntry> topHunks;

  /// True when add/remove token ranking used corpus IDF; false when it
  /// fell back to commit-local frequency. Surfaced in the prompt so a
  /// downstream debugger can tell which path produced the output.
  final bool idfAvailable;

  bool get isEmpty => totalHunks == 0;

  /// Render as a compact XML block ready to sit inside `<diff_context>`
  /// above the packed diff. A single wrapper tag keeps the model's XML
  /// parser happy; inside, plain-text bullets give the best recall on
  /// scanning. Only non-empty sections render, so a small commit with
  /// no moves / no wells gets a short manifest.
  String toPromptXml() {
    final buf = StringBuffer();
    buf.writeln('<semantic_manifest>');
    buf.writeln(
      'Pre-computed by the logos diffusion + engram semantic engines. '
      'Trust these findings over your own reading of the raw diff below for '
      'add / remove / move claims — the diff may split a single move across '
      'distant hunks.',
    );
    buf.writeln();
    buf.writeln('Files touched: $filesTouched | Hunks: $totalHunks');

    if (themes.isNotEmpty) {
      buf.writeln();
      buf.writeln(
        'Themes (Alexandria wells, ranked by φ mass — higher = more central):',
      );
      for (final t in themes) {
        final pct = (t.massFraction * 100).round();
        buf.writeln('  • ${t.wellName}  '
            '(${t.hunkCount} hunk${t.hunkCount == 1 ? '' : 's'}, $pct% mass)');
      }
    }

    if (moves.isNotEmpty) {
      buf.writeln();
      buf.writeln(
        'Moves within-file (token appears in both - and + lines of the '
        'same file — reorder/reformat, NOT a removal):',
      );
      for (final m in moves) {
        buf.writeln('  • ${m.token} — ${m.filePath}');
      }
    }

    if (crossFileMoves.isNotEmpty) {
      buf.writeln();
      buf.writeln(
        'Moves cross-file (token was removed from some files and added '
        'in others — code migration / symbol relocation / refactor. '
        'NOT a removal + unrelated addition):',
      );
      for (final m in crossFileMoves) {
        final from = m.fromFiles.join(', ');
        final to = m.toFiles.join(', ');
        buf.writeln('  • ${m.token}');
        buf.writeln('      from: $from');
        buf.writeln('      to:   $to');
      }
    }

    if (additionsByFile.isNotEmpty) {
      buf.writeln();
      final rankLabel = idfAvailable
          ? 'ranked by corpus IDF — rarer first'
          : 'ranked by commit-wide repetition — multi-file first';
      buf.writeln(
        'Additions (identifiers appearing ONLY in + lines, per file; '
        '$rankLabel):',
      );
      additionsByFile.forEach((file, tokens) {
        buf.writeln('  $file: ${tokens.join(', ')}');
      });
    }

    if (removalsByFile.isNotEmpty) {
      buf.writeln();
      buf.writeln(
        'Removals (identifiers appearing ONLY in - lines, per file):',
      );
      removalsByFile.forEach((file, tokens) {
        buf.writeln('  $file: ${tokens.join(', ')}');
      });
    }

    if (couplingPairs.isNotEmpty) {
      buf.writeln();
      buf.writeln(
        'Historical coupling (file pairs touched here that usually '
        'co-change; narrate them together):',
      );
      for (final c in couplingPairs) {
        final j = c.jaccard.toStringAsFixed(2);
        buf.writeln('  • ${c.fileA}  ↔  ${c.fileB}  (jaccard=$j)');
      }
    }

    if (topHunks.isNotEmpty) {
      buf.writeln();
      buf.writeln(
        'Top hunks by φ salience, grouped by Alexandria well (same-well '
        'hunks are semantically related via the logos attention graph — '
        'narrate them as parts of the same change, not independent edits):',
      );
      // Group by wellName preserving φ order. LinkedHashMap iteration
      // yields groups in order of first-appearance, which equals order
      // of highest-φ representative because topHunks is already
      // sorted DESC by φ.
      final grouped = <String, List<TopHunkEntry>>{};
      for (final h in topHunks) {
        final key = h.wellName ?? '(unclustered)';
        (grouped[key] ??= <TopHunkEntry>[]).add(h);
      }
      grouped.forEach((well, hunksInWell) {
        buf.writeln('  $well:');
        for (final h in hunksInWell) {
          final phi = h.phi.toStringAsFixed(2);
          buf.writeln('    #${h.rank}  φ=$phi  '
              '${h.filePath} @@ -${h.oldStart} +${h.newStart} @@');
        }
      });
    }

    buf.write('</semantic_manifest>');
    return buf.toString();
  }
}

class ThemeEntry {
  const ThemeEntry({
    required this.wellName,
    required this.hunkCount,
    required this.massFraction,
  });
  final String wellName;
  final int hunkCount;
  /// Fraction of total φ mass in the ranked set (0..1).
  final double massFraction;
}

class MoveEntry {
  const MoveEntry({required this.token, required this.filePath});
  final String token;
  final String filePath;
}

class CrossFileMoveEntry {
  const CrossFileMoveEntry({
    required this.token,
    required this.fromFiles,
    required this.toFiles,
  });
  final String token;

  /// Files where the token was removed (− lines, nowhere added in that
  /// same file).
  final List<String> fromFiles;

  /// Files where the token was added (+ lines, nowhere removed in that
  /// same file).
  final List<String> toFiles;
}

class TopHunkEntry {
  const TopHunkEntry({
    required this.rank,
    required this.phi,
    required this.wellName,
    required this.filePath,
    required this.oldStart,
    required this.newStart,
  });
  final int rank;
  final double phi;
  final String? wellName;
  final String filePath;
  final int oldStart;
  final int newStart;
}

class CouplingEntry {
  const CouplingEntry({
    required this.fileA,
    required this.fileB,
    required this.jaccard,
  });
  final String fileA;
  final String fileB;
  /// Historical co-change Jaccard coefficient in [0, 1].
  final double jaccard;
}

// ── Bounds ───────────────────────────────────────────────────────────────

const int _kMaxThemes = 5;
const int _kMaxMoves = 30;
const int _kMaxCrossFileMoves = 30;
const int _kMaxFilesInTokenList = 20;
const int _kMaxTokensPerFile = 15;
const int _kMaxTopHunks = 10;
const int _kMaxCouplingPairs = 10;

/// Minimum historical Jaccard score to surface a file pair. Below this,
/// the signal is too weak to be worth narrating — the model is better
/// off not being told "these two files are related" when they barely
/// are. 0.25 matches the coupling_nudge threshold convention elsewhere.
const double _kCouplingFloor = 0.25;

// ── Builder ──────────────────────────────────────────────────────────────

/// Build a manifest from a ranked hunk list (φ + optional well).
///
/// Pure function: given the same rankings + state, returns the same
/// manifest. Never throws — a malformed hunk body just contributes no
/// tokens. Returns an empty-ish manifest when [rankings] is empty;
/// callers can check [SemanticManifest.isEmpty] before emitting.
///
/// [symbolIndex] — corpus IDF. When non-null and non-empty, identifier
/// ranking uses true rarity instead of commit-local repetition.
/// [couplingMatrix] — historical co-change data. When non-null, file
/// pairs above [_kCouplingFloor] are surfaced as narrative hints.
SemanticManifest buildSemanticManifest(
  List<HunkRanking> rankings, {
  SymbolFrequencyIndex? symbolIndex,
  FileCouplingMatrix? couplingMatrix,
}) {
  if (rankings.isEmpty) {
    return SemanticManifest(
      filesTouched: 0,
      totalHunks: 0,
      themes: const [],
      moves: const [],
      crossFileMoves: const [],
      additionsByFile: const {},
      removalsByFile: const {},
      couplingPairs: const [],
      topHunks: const [],
      idfAvailable: false,
    );
  }

  final idfReady = symbolIndex != null && symbolIndex.isNotEmpty;

  // Per-file token accumulators. LinkedHashMap insertion order keeps the
  // rendered output stable (= first file seen = first file listed).
  final addedByFile = <String, Set<String>>{};
  final removedByFile = <String, Set<String>>{};
  final hunksByFile = <String, int>{};

  // Commit-wide frequency is the fallback scoring axis when no IDF
  // index is available. When IDF *is* available, freq is still useful
  // as a deterministic tiebreaker for tokens with equal IDF (very
  // common in small corpora where most tokens land at the IDF ceiling).
  final commitWideFreq = <String, int>{};

  for (final r in rankings) {
    final (:added, :removed) = _tokensFromHunk(r.hunk);
    (addedByFile[r.hunk.filePath] ??= <String>{}).addAll(added);
    (removedByFile[r.hunk.filePath] ??= <String>{}).addAll(removed);
    hunksByFile[r.hunk.filePath] = (hunksByFile[r.hunk.filePath] ?? 0) + 1;
    for (final t in added) {
      commitWideFreq[t] = (commitWideFreq[t] ?? 0) + 1;
    }
    for (final t in removed) {
      commitWideFreq[t] = (commitWideFreq[t] ?? 0) + 1;
    }
  }

  // Scoring function: IDF when the corpus is indexed, commit-local
  // frequency otherwise. Higher score → kept over cap.
  double score(String token) {
    if (idfReady) return symbolIndex.idf(token);
    return (commitWideFreq[token] ?? 0).toDouble();
  }

  // Phase 2a: within-file moves. Per-file intersection of added and
  // removed token sets — these are reorderings/reformats within a
  // single file. They never appear in additions or removals; they live
  // in their own section so the model doesn't double-narrate them.
  final moves = <MoveEntry>[];
  final trulyAddedByFile = <String, Set<String>>{};
  final trulyRemovedByFile = <String, Set<String>>{};
  final allFiles = <String>{...addedByFile.keys, ...removedByFile.keys};

  for (final file in allFiles) {
    final added = addedByFile[file] ?? const <String>{};
    final removed = removedByFile[file] ?? const <String>{};
    final intersection = added.intersection(removed);
    for (final tok in intersection) {
      moves.add(MoveEntry(token: tok, filePath: file));
    }
    trulyAddedByFile[file] = added.difference(intersection);
    trulyRemovedByFile[file] = removed.difference(intersection);
  }

  // Phase 2b: cross-file moves. A token that is truly-added in some
  // files AND truly-removed in other files is a symbol migration: the
  // code physically relocated from the remove-side to the add-side.
  // This is the class of hallucination the raw diff creates — the
  // reviewer sees two independent events ("removal in X", "addition
  // in Y") and narrates them as unrelated deletion + new code. The
  // manifest reunifies them here. After detection, the token is
  // subtracted from the per-file sets so it never appears in the
  // additions or removals sections.
  final addedFilesByToken = <String, Set<String>>{};
  final removedFilesByToken = <String, Set<String>>{};
  trulyAddedByFile.forEach((file, tokens) {
    for (final t in tokens) {
      (addedFilesByToken[t] ??= <String>{}).add(file);
    }
  });
  trulyRemovedByFile.forEach((file, tokens) {
    for (final t in tokens) {
      (removedFilesByToken[t] ??= <String>{}).add(file);
    }
  });
  final migratedTokens = addedFilesByToken.keys
      .toSet()
      .intersection(removedFilesByToken.keys.toSet());

  final crossFileMoves = <CrossFileMoveEntry>[];
  for (final tok in migratedTokens) {
    final from = removedFilesByToken[tok]!.toList()..sort();
    final to = addedFilesByToken[tok]!.toList()..sort();
    crossFileMoves.add(CrossFileMoveEntry(
      token: tok,
      fromFiles: from,
      toFiles: to,
    ));
    for (final f in addedFilesByToken[tok]!) {
      trulyAddedByFile[f]?.remove(tok);
    }
    for (final f in removedFilesByToken[tok]!) {
      trulyRemovedByFile[f]?.remove(tok);
    }
  }

  // Phase 3: rank + cap per-file additions and removals AFTER
  // cross-file migration tokens have been removed from the pool.
  // Tokens with equal score tie-break alphabetically for stability.
  final additionsByFile = <String, List<String>>{};
  final removalsByFile = <String, List<String>>{};
  trulyAddedByFile.forEach((file, set) {
    final ranked = _rank(set, score, _kMaxTokensPerFile);
    if (ranked.isNotEmpty) additionsByFile[file] = ranked;
  });
  trulyRemovedByFile.forEach((file, set) {
    final ranked = _rank(set, score, _kMaxTokensPerFile);
    if (ranked.isNotEmpty) removalsByFile[file] = ranked;
  });

  // Sort moves and cap. Within-file moves rank by score (IDF/freq) —
  // rare tokens moving are more interesting. Cross-file moves rank by
  // total fan-out (|from| + |to|) because a token touching many files
  // is almost certainly a rename/refactor worth narrating; ties break
  // by score.
  moves.sort((a, b) => score(b.token).compareTo(score(a.token)));
  final cappedMoves =
      moves.length <= _kMaxMoves ? moves : moves.sublist(0, _kMaxMoves);

  crossFileMoves.sort((a, b) {
    final fa = a.fromFiles.length + a.toFiles.length;
    final fb = b.fromFiles.length + b.toFiles.length;
    if (fa != fb) return fb.compareTo(fa);
    return score(b.token).compareTo(score(a.token));
  });
  final cappedCrossFileMoves = crossFileMoves.length <= _kMaxCrossFileMoves
      ? crossFileMoves
      : crossFileMoves.sublist(0, _kMaxCrossFileMoves);

  final cappedAdditions =
      _capFiles(additionsByFile, hunksByFile, _kMaxFilesInTokenList);
  final cappedRemovals =
      _capFiles(removalsByFile, hunksByFile, _kMaxFilesInTokenList);

  // Historical coupling: pairs among the touched files whose jaccard
  // co-change history is above the floor. We read jaccard directly
  // (not `score()`) because we want the *historical* signal, not the
  // blended matrix score which includes in-flight symbol overlap.
  final couplingPairs = <CouplingEntry>[];
  if (couplingMatrix != null && allFiles.length >= 2) {
    final fileList = allFiles.toList();
    final seen = <String>{};
    for (var i = 0; i < fileList.length; i++) {
      final a = fileList[i];
      for (var j = i + 1; j < fileList.length; j++) {
        final b = fileList[j];
        final key = a.compareTo(b) <= 0 ? '$a\u0000$b' : '$b\u0000$a';
        if (!seen.add(key)) continue;
        // CSR-native jaccard lookup (no symbol blend). Equivalent to
        // the legacy `couplingMatrix.jaccard[a]?[b] ?? jaccard[b]?[a]
        // ?? 0.0` two-direction probe — one binary search with
        // canonicalised (lo, hi) instead of two hashmap lookups, no
        // lazy-map materialisation triggered.
        final jac = couplingMatrix.jaccardScoreOf(a, b);
        if (jac >= _kCouplingFloor) {
          couplingPairs.add(CouplingEntry(fileA: a, fileB: b, jaccard: jac));
        }
      }
    }
    couplingPairs.sort((x, y) => y.jaccard.compareTo(x.jaccard));
    if (couplingPairs.length > _kMaxCouplingPairs) {
      couplingPairs.removeRange(_kMaxCouplingPairs, couplingPairs.length);
    }
  }

  // Theme histogram: sum φ per well. A well contributes the φ of every
  // hunk that lands in it; the well with the largest φ-mass is the
  // commit's dominant theme. Mass fraction is relative to total φ in
  // the ranked set (NOT across all wells in the brain) — the denominator
  // is the commit, so "42% mass" means 42% of this commit's salience
  // lives in that theme.
  final themeMass = <String, double>{};
  final themeHunks = <String, int>{};
  double totalPhi = 0.0;
  for (final r in rankings) {
    totalPhi += r.phi;
    final name = r.wellName;
    if (name == null) continue;
    themeMass[name] = (themeMass[name] ?? 0.0) + r.phi;
    themeHunks[name] = (themeHunks[name] ?? 0) + 1;
  }
  final themeEntries = themeMass.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final themes = <ThemeEntry>[];
  for (final e in themeEntries.take(_kMaxThemes)) {
    themes.add(ThemeEntry(
      wellName: e.key,
      hunkCount: themeHunks[e.key] ?? 0,
      massFraction: totalPhi > 0 ? e.value / totalPhi : 0.0,
    ));
  }

  // Top hunks: already sorted DESC by φ in the ranking input, so just
  // take the prefix. We pass the ranking.rank through — it's 0-based
  // and matches the input ordering.
  final topHunks = <TopHunkEntry>[];
  for (final r in rankings.take(_kMaxTopHunks)) {
    topHunks.add(TopHunkEntry(
      rank: r.rank,
      phi: r.phi,
      wellName: r.wellName,
      filePath: r.hunk.filePath,
      oldStart: r.hunk.oldStart,
      newStart: r.hunk.newStart,
    ));
  }

  return SemanticManifest(
    filesTouched: allFiles.length,
    totalHunks: rankings.length,
    themes: themes,
    moves: cappedMoves,
    crossFileMoves: cappedCrossFileMoves,
    additionsByFile: cappedAdditions,
    removalsByFile: cappedRemovals,
    couplingPairs: couplingPairs,
    topHunks: topHunks,
    idfAvailable: idfReady,
  );
}

// ── Helpers ──────────────────────────────────────────────────────────────

/// Walk a hunk body and extract identifier tokens on + and - lines.
/// Context lines (starting with a space) and diff metadata (`+++`,
/// `---`, `@@`) contribute nothing. Skip-listed tokens and very short
/// tokens are filtered at extraction time so downstream set algebra
/// operates on signal only.
({Set<String> added, Set<String> removed}) _tokensFromHunk(DiffHunk h) {
  final added = <String>{};
  final removed = <String>{};
  for (final line in h.body.split('\n')) {
    if (line.isEmpty) continue;
    // Exclude unified-diff metadata lines.
    if (line.startsWith('+++') ||
        line.startsWith('---') ||
        line.startsWith('@@')) {
      continue;
    }
    final Set<String>? target;
    if (line.startsWith('+')) {
      target = added;
    } else if (line.startsWith('-')) {
      target = removed;
    } else {
      target = null; // context line
    }
    if (target == null) continue;
    for (final m in _kIdentifierRe.allMatches(line)) {
      final tok = m.group(0)!;
      if (tok.length < _kMinTokenLen) continue;
      if (_kSkipTokens.contains(tok)) continue;
      target.add(tok);
    }
  }
  return (added: added, removed: removed);
}

/// Sort [tokens] by [score] (descending) then alphabetically, then take
/// up to [cap]. Score is IDF when the corpus index is live, or
/// commit-wide repetition as a fallback. Alphabetical tiebreak keeps
/// output deterministic across runs for the same input.
List<String> _rank(
  Set<String> tokens,
  double Function(String) score,
  int cap,
) {
  if (tokens.isEmpty) return const [];
  final list = tokens.toList()
    ..sort((a, b) {
      final sa = score(a);
      final sb = score(b);
      if (sa != sb) return sb.compareTo(sa);
      return a.compareTo(b);
    });
  if (list.length <= cap) return list;
  return list.sublist(0, cap);
}

/// Cap the number of files listed in a per-file token map. Files with
/// more hunks get priority (they're more central to the commit).
Map<String, List<String>> _capFiles(
  Map<String, List<String>> byFile,
  Map<String, int> hunksByFile,
  int cap,
) {
  if (byFile.length <= cap) return byFile;
  final sorted = byFile.keys.toList()
    ..sort((a, b) {
      final ha = hunksByFile[a] ?? 0;
      final hb = hunksByFile[b] ?? 0;
      if (ha != hb) return hb.compareTo(ha);
      return a.compareTo(b);
    });
  final out = <String, List<String>>{};
  for (final k in sorted.take(cap)) {
    out[k] = byFile[k]!;
  }
  return out;
}

/// Exposed for tests and debug tooling; not part of the build pipeline.
@visibleForTesting
({Set<String> added, Set<String> removed}) debugTokensFromHunk(DiffHunk h) =>
    _tokensFromHunk(h);
