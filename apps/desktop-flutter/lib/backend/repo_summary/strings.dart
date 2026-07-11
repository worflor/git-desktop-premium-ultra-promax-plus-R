// strings.dart — the whole-sentence i18n boundary for the repo summary.
//
// Every user-facing sentence the summary assembles goes through this
// pure interface. The backend never touches Flutter or slang: it
// composes structure (which sections, in which order, with which
// markdown scaffolding) and delegates each *complete* clause or
// sentence to a [RepoSummaryStrings]. That keeps word order the
// translator's to own — the backend hands over whole reorderable units,
// never word-by-word fragments glued in Dart.
//
// [EnglishRepoSummaryStrings] is the byte-for-byte reproduction of the
// original hardcoded English; it is the default so every existing caller
// (and every test) keeps its exact output. The localized implementation
// lives UI-side (`lib/ui/repo_summary_text.dart`) atop slang, so this
// layer stays Flutter-free.

/// The single English pluralizer — the consolidation of the two
/// identical `_plural` helpers that used to live in assembler.dart and
/// prose.dart. `n == 1 ? "$n $singular" : "$n $plural"`.
String enPlural(int n, String singular, String plural) =>
    n == 1 ? '$n $singular' : '$n $plural';

/// Whole-sentence string provider for the repo-summary renderer.
///
/// Each member returns a complete, translatable unit. Optional clauses
/// (a core count, a common directory, a purpose) are separate members
/// joined by locale-owned separator members, rather than concatenated
/// with hardcoded punctuation — so a locale can place them wherever its
/// grammar wants.
abstract interface class RepoSummaryStrings {
  // ── Section headings (the `## ` scaffolding stays in the renderer) ──
  String get headingShape;
  String get headingAtAGlance;
  String get headingCore;
  String get headingRegions;
  String get headingGettingStarted;

  // ── "At a glance" bullets (leading "- " stays in the renderer) ──
  String glanceShowingNofM({required int active, required int total});
  String glanceFiles(int n);
  String glanceLines({required int n, required String bytes});
  String glanceRoles(String parts);
  String get historyStarvedCaveat;

  // ── Core / backbone bullets ──
  String backboneEntry({
    required String path,
    required String lines,
    required String region,
  });
  String backboneLineCount(int n);
  String backbonePurposeSuffix(String purpose);

  // ── Region section ──
  String get regionFilesLabel;
  String regionConnectsTo(String linked);

  // ── Region body (assembled in the pipeline, from clause members) ──
  String regionBodyFiles(int n);
  String regionBodyCore(int n);
  String get regionBodyCoreSeparator;
  String regionBodyCommonDir(String dir);
  String get regionBodyCommonDirSeparator;

  // ── Elevator pitch synthesis ──
  String synthPitchNoRegions(int n);
  String synthPitchWithRegions({required int n, required String regions});
  String emptyRepoPitch(String detail);
  String emptyRepoBinary(int n);
  String emptyRepoUnreadable(int n);

  // ── Overall-shape sentences (one per spectral archetype) ──
  String get shapeTree;
  String get shapeModular;
  String get shapeBulk;
  String get shapeCrystalline;
  String get shapeGoe;
  String get shapePoisson;
}

/// The original English copy, verbatim. Default for every backend entry
/// point so behavior — and every existing test — is unchanged.
class EnglishRepoSummaryStrings implements RepoSummaryStrings {
  const EnglishRepoSummaryStrings();

  @override
  String get headingShape => 'Shape';
  @override
  String get headingAtAGlance => 'At a glance';
  @override
  String get headingCore => 'Core';
  @override
  String get headingRegions => 'Regions';
  @override
  String get headingGettingStarted => 'Getting started';

  @override
  String glanceShowingNofM({required int active, required int total}) =>
      'Showing $active of $total files, ranked by structural centrality.';
  @override
  String glanceFiles(int n) => enPlural(n, 'file.', 'files.');
  @override
  String glanceLines({required int n, required String bytes}) =>
      n == 1 ? '$n line ($bytes).' : '$n lines ($bytes).';
  @override
  String glanceRoles(String parts) => 'Roles — $parts.';
  @override
  String get historyStarvedCaveat =>
      'Ranking is limited: the coupling graph had no edges '
      '(fresh clone or too few commits). File order reflects size, '
      'not structural centrality.';

  @override
  String backboneEntry({
    required String path,
    required String lines,
    required String region,
  }) =>
      '`$path` ($lines) — $region';
  @override
  String backboneLineCount(int n) => enPlural(n, 'line', 'lines');
  @override
  String backbonePurposeSuffix(String purpose) => ' · $purpose';

  @override
  String get regionFilesLabel => 'Files:';
  @override
  String regionConnectsTo(String linked) => 'Connects to: $linked.';

  @override
  String regionBodyFiles(int n) => n == 1 ? 'One file' : '$n files';
  @override
  String regionBodyCore(int n) => n == 1 ? '1 core' : '$n core';
  @override
  String get regionBodyCoreSeparator => ', ';
  @override
  String regionBodyCommonDir(String dir) => 'All under `$dir`.';
  @override
  String get regionBodyCommonDirSeparator => ' ';

  @override
  String synthPitchNoRegions(int n) =>
      'A repository of ${enPlural(n, 'active file', 'active files')}.';
  @override
  String synthPitchWithRegions({required int n, required String regions}) =>
      'A repository of ${enPlural(n, 'active file', 'active files')} — $regions.';
  @override
  String emptyRepoPitch(String detail) =>
      'A repository with no readable text files$detail.';
  @override
  String emptyRepoBinary(int n) => '$n binary';
  @override
  String emptyRepoUnreadable(int n) => '$n unreadable';

  @override
  String get shapeTree =>
      'Tree-shaped codebase: one dominant spine with dependent '
      'branches. Change usually propagates outward from the core.';
  @override
  String get shapeModular =>
      'Modular codebase: several cohesive regions with limited '
      'cross-coupling. Work in one region rarely disturbs another.';
  @override
  String get shapeBulk =>
      'Densely interconnected codebase: most files participate '
      'in one large neighbourhood of shared change.';
  @override
  String get shapeCrystalline =>
      'Lattice-shaped codebase: uniform, regular coupling across '
      'files with predictable local structure.';
  @override
  String get shapeGoe =>
      'Richly interconnected codebase: couplings spread across '
      'files without a dominant spine.';
  @override
  String get shapePoisson =>
      'Loosely coupled codebase: files evolve mostly on their '
      'own, with occasional shared change.';
}
