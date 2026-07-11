// repo_summary_text.dart — the localized rendering layer for the repo
// summary.
//
// The `lib/backend/repo_summary/` pipeline is deliberately Flutter-free:
// it composes structure and delegates every user-facing sentence to a
// pure [RepoSummaryStrings]. This module supplies the slang-backed
// implementation so the summary reads in the viewer's locale, without
// dragging flutter/slang into the backend. It mirrors the pattern of
// `merge_outcome_text.dart`: whole sentences resolved via the global [t]
// at render time.

import '../backend/repo_summary/api.dart' show repoDocToMarkdown;
import '../backend/repo_summary/strings.dart';
import '../backend/repo_summary/types.dart';
import '../i18n/gen/strings.g.dart';

/// [RepoSummaryStrings] backed by the `repoSummary` slang namespace. Each
/// member returns a complete, translatable unit — the backend supplies
/// only counts and pre-joined structural fragments (paths, region
/// labels), never word order.
class SlangRepoSummaryStrings implements RepoSummaryStrings {
  const SlangRepoSummaryStrings();

  @override
  String get headingShape => t.repoSummary.heading.shape;
  @override
  String get headingAtAGlance => t.repoSummary.heading.atAGlance;
  @override
  String get headingCore => t.repoSummary.heading.core;
  @override
  String get headingRegions => t.repoSummary.heading.regions;
  @override
  String get headingGettingStarted => t.repoSummary.heading.gettingStarted;

  @override
  String glanceShowingNofM({required int active, required int total}) =>
      t.repoSummary.glance.showingNofM(active: active, total: total);
  @override
  String glanceFiles(int n) => t.repoSummary.glance.files(n: n);
  @override
  String glanceLines({required int n, required String bytes}) =>
      t.repoSummary.glance.lines(n: n, bytes: bytes);
  @override
  String glanceRoles(String parts) => t.repoSummary.glance.roles(parts: parts);
  @override
  String get historyStarvedCaveat => t.repoSummary.historyStarvedCaveat;

  @override
  String backboneEntry({
    required String path,
    required String lines,
    required String region,
  }) =>
      t.repoSummary.backbone.entry(path: path, lines: lines, region: region);
  @override
  String backboneLineCount(int n) => t.repoSummary.backbone.lineCount(n: n);
  @override
  String backbonePurposeSuffix(String purpose) =>
      t.repoSummary.backbone.purposeSuffix(purpose: purpose);

  @override
  String get regionFilesLabel => t.repoSummary.region.filesLabel;
  @override
  String regionConnectsTo(String linked) =>
      t.repoSummary.region.connectsTo(linked: linked);

  @override
  String regionBodyFiles(int n) => t.repoSummary.region.bodyFiles(n: n);
  @override
  String regionBodyCore(int n) => t.repoSummary.region.bodyCore(n: n);
  @override
  String get regionBodyCoreSeparator => t.repoSummary.region.bodyCoreSeparator;
  @override
  String regionBodyCommonDir(String dir) =>
      t.repoSummary.region.bodyCommonDir(dir: dir);
  @override
  String get regionBodyCommonDirSeparator =>
      t.repoSummary.region.bodyCommonDirSeparator;

  @override
  String synthPitchNoRegions(int n) => t.repoSummary.pitch.noRegions(n: n);
  @override
  String synthPitchWithRegions({required int n, required String regions}) =>
      t.repoSummary.pitch.withRegions(n: n, regions: regions);
  @override
  String emptyRepoPitch(String detail) => t.repoSummary.pitch.empty(detail: detail);
  @override
  String emptyRepoBinary(int n) => t.repoSummary.pitch.emptyBinary(n: n);
  @override
  String emptyRepoUnreadable(int n) => t.repoSummary.pitch.emptyUnreadable(n: n);

  @override
  String get shapeTree => t.repoSummary.shape.tree;
  @override
  String get shapeModular => t.repoSummary.shape.modular;
  @override
  String get shapeBulk => t.repoSummary.shape.bulk;
  @override
  String get shapeCrystalline => t.repoSummary.shape.crystalline;
  @override
  String get shapeGoe => t.repoSummary.shape.goe;
  @override
  String get shapePoisson => t.repoSummary.shape.poisson;
}

/// Render [doc] to markdown in the viewer's locale. The doc's own baked
/// prose (region bodies, elevator pitch, shape) is localized upstream in
/// the generating isolate; this localizes the assembled chrome.
String localizedRepoDocToMarkdown(RepoDoc doc) =>
    repoDocToMarkdown(doc, strings: const SlangRepoSummaryStrings());
