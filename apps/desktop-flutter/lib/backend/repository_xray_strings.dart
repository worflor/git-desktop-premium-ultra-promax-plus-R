// repository_xray_strings.dart — the whole-sentence i18n boundary for
// the Repo X-Ray insight cards.
//
// `repository_xray.dart` composes structure (which cards fire, in which
// order, with which evidence rows) but delegates every user-facing
// title, claim, and evidence label/detail to a pure [XrayCardStrings].
// The backend never touches Flutter or slang: it hands over whole
// reorderable sentences plus the raw values (paths, counts, dates) they
// interpolate — never word-by-word fragments glued in Dart. That keeps
// word order the translator's to own.
//
// [EnglishXrayCardStrings] is the byte-for-byte reproduction of the
// original hardcoded English; it is the default for every backend entry
// point so every existing caller (and every test) keeps its exact
// output. The localized implementation lives UI-side
// (`lib/ui/xray_card_text.dart`) atop slang, so this layer stays
// Flutter-free. Mirrors the `repo_summary/strings.dart` boundary.

/// Whole-sentence string provider for the Repo X-Ray card generator.
///
/// Each member returns a complete, translatable unit. Identity/value
/// fields on the card DTOs (`id`, `verdict`, `confidence`, `kind`) are
/// not display text and never pass through here; where a value word like
/// a hotspot `kind` ('file'/'directory') or a path is embedded in a
/// sentence, it is threaded in as a placeholder rather than concatenated.
abstract interface class XrayCardStrings {
  // ── Hidden-refs card ──
  String get hiddenRefsTitle;
  String hiddenRefsClaim(int count);
  String get hiddenRefsEvidenceLabel;
  String hiddenRefsEvidenceDetail(int count);
  String get namespacesLabel;

  // ── Machine-history card ──
  String get machineHistoryTitle;
  String get machineHistoryClaim;
  String get rawVsFilteredLabel;
  String rawVsFilteredDetail({required int raw, required int filtered});
  String get machineCommitsLabel;
  String machineCommitsDetail(int count);

  // ── Migration card ──
  String get migrationTitle;
  String migrationClaim({required String older, required String newer});
  String migrationStratumDetail({required int touches, required String lastActive});

  // ── Single-owner-hotspot card ──
  String get singleOwnerTitle;
  String singleOwnerClaim({required String path, required String kind});
  String get touchCountLabel;
  String singleOwnerTouchDetail({required int count, required bool raw});
  String get ownerCountLabel;
  String ownerCountDetail(int count);

  // ── No-tags card ──
  String get noTagsTitle;
  String get noTagsClaim;
  String get tagCountLabel;
  String get tagCountDetail;
  String get remoteEndpointsLabel;
  String remoteEndpointsDetail(int count);

  // ── Bursty-cadence card ──
  String get burstyTitle;
  String get burstyClaim;

  // ── Branch-model card ──
  String get branchModelSimpleTitle;
  String get branchModelBroadTitle;
  String get branchModelSimpleClaim;
  String get branchModelBroadClaim;
  String get localBranchesLabel;
  String localBranchesDetail(int count);
  String get remoteBranchesLabel;
  String remoteBranchesDetail(int count);

  // ── Reflog-intense card ──
  String get reflogTitle;
  String get reflogClaim;
  String get peakReflogDayLabel;

  // ── Keystone-files card ──
  String keystoneTitle(int count);
  String keystoneClaim(int count);
  String keystoneEvidenceDetail({required int touchCount, required String score});

  // ── Narrow-hotspot card ──
  String get narrowHotspotTitle;
  String get narrowHotspotClaim;
  String get topHotspotLabel;
  String topHotspotDetail({required String path, required String pct});
  String get visibleAuthorsLabel;
  String visibleAuthorsDetail(int count);
}

/// The original English copy, verbatim. Default for every card-generator
/// entry point so behavior — and every existing test — is unchanged.
class EnglishXrayCardStrings implements XrayCardStrings {
  const EnglishXrayCardStrings();

  // ── Hidden-refs card ──
  @override
  String get hiddenRefsTitle => 'Hidden Git namespaces';
  @override
  String hiddenRefsClaim(int count) =>
      '$count refs live outside normal branch/tag space.';
  @override
  String get hiddenRefsEvidenceLabel => 'Hidden refs';
  @override
  String hiddenRefsEvidenceDetail(int count) =>
      '$count refs outside heads/remotes/tags.';
  @override
  String get namespacesLabel => 'Namespaces';

  // ── Machine-history card ──
  @override
  String get machineHistoryTitle => 'Machine history dominates raw metrics';
  @override
  String get machineHistoryClaim =>
      'Checkpoint-style commits materially distort naive history metrics.';
  @override
  String get rawVsFilteredLabel => 'Raw vs filtered';
  @override
  String rawVsFilteredDetail({required int raw, required int filtered}) =>
      '$raw raw commits vs $filtered filtered commits.';
  @override
  String get machineCommitsLabel => 'Machine commits';
  @override
  String machineCommitsDetail(int count) =>
      '$count commits matched machine/session patterns.';

  // ── Migration card ──
  @override
  String get migrationTitle => 'Architecture migration visible';
  @override
  String migrationClaim({required String older, required String newer}) =>
      'History shifts from `$older` to `$newer`, suggesting a stack or surface transition.';
  @override
  String migrationStratumDetail(
          {required int touches, required String lastActive}) =>
      '$touches touches, last active $lastActive.';

  // ── Single-owner-hotspot card ──
  @override
  String get singleOwnerTitle => 'Single-owner hotspot';
  @override
  String singleOwnerClaim({required String path, required String kind}) =>
      '`$path` is a heavily touched $kind with one distinct visible author.';
  @override
  String get touchCountLabel => 'Touch count';
  @override
  String singleOwnerTouchDetail({required int count, required bool raw}) =>
      raw
          ? '$count touches in raw history.'
          : '$count touches in filtered history.';
  @override
  String get ownerCountLabel => 'Owner count';
  @override
  String ownerCountDetail(int count) => '$count distinct authors.';

  // ── No-tags card ──
  @override
  String get noTagsTitle => 'No formal release/tag trail';
  @override
  String get noTagsClaim =>
      'Git tags are not being used as a visible release or milestone layer.';
  @override
  String get tagCountLabel => 'Tag count';
  @override
  String get tagCountDetail => '0 tags found.';
  @override
  String get remoteEndpointsLabel => 'Remote endpoints';
  @override
  String remoteEndpointsDetail(int count) =>
      '$count remote endpoints configured.';

  // ── Bursty-cadence card ──
  @override
  String get burstyTitle => 'Bursty development cadence';
  @override
  String get burstyClaim =>
      'Work lands in concentrated bursts rather than a flat daily rhythm.';

  // ── Branch-model card ──
  @override
  String get branchModelSimpleTitle => 'Simple branch model';
  @override
  String get branchModelBroadTitle => 'Branch model has surface area';
  @override
  String get branchModelSimpleClaim => 'The visible branch model is narrow.';
  @override
  String get branchModelBroadClaim =>
      'The repository has enough branch surface to reward branch-aware navigation.';
  @override
  String get localBranchesLabel => 'Local branches';
  @override
  String localBranchesDetail(int count) => '$count local branches.';
  @override
  String get remoteBranchesLabel => 'Remote branches';
  @override
  String remoteBranchesDetail(int count) => '$count remote branches.';

  // ── Reflog-intense card ──
  @override
  String get reflogTitle => 'Intense local editing sessions';
  @override
  String get reflogClaim =>
      'Reflog volume suggests concentrated local iteration beyond published commits.';
  @override
  String get peakReflogDayLabel => 'Peak reflog day';

  // ── Keystone-files card ──
  @override
  String keystoneTitle(int count) =>
      count == 1 ? 'Keystone bridge-file' : '$count keystone bridge-files';
  @override
  String keystoneClaim(int count) => count == 1
      ? 'One file carries disproportionate co-change weight relative to its touch count.'
      : 'A small set of files carry disproportionate co-change weight relative to their touch counts.';
  @override
  String keystoneEvidenceDetail(
          {required int touchCount, required String score}) =>
      '$touchCount touch${touchCount == 1 ? '' : 'es'} · pull φ=$score';

  // ── Narrow-hotspot card ──
  @override
  String get narrowHotspotTitle => 'Hotspot concentration is narrow';
  @override
  String get narrowHotspotClaim =>
      'A small set of files and directories absorbs a disproportionate share of changes.';
  @override
  String get topHotspotLabel => 'Top hotspot';
  @override
  String topHotspotDetail({required String path, required String pct}) =>
      '$path accounts for $pct% of the visible hotspot set.';
  @override
  String get visibleAuthorsLabel => 'Visible authors';
  @override
  String visibleAuthorsDetail(int count) =>
      '$count authors in this history slice.';
}
