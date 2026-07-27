///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsNl extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsNl({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
    TranslationMetadata<AppLocale, Translations>? meta,
  }) : assert(
         overrides == null,
         'Set "translation_overrides: true" in order to enable this feature.',
       ),
       $meta =
           meta ??
           TranslationMetadata(
             locale: AppLocale.nl,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <nl>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final TranslationsNl _root = this; // ignore: unused_field

  @override
  TranslationsNl $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsNl(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$app$nl app = _Translations$app$nl._(_root);
  @override
  late final _Translations$backend$nl backend = _Translations$backend$nl._(
    _root,
  );
  @override
  late final _Translations$branches$nl branches = _Translations$branches$nl._(
    _root,
  );
  @override
  late final _Translations$changes$nl changes = _Translations$changes$nl._(
    _root,
  );
  @override
  late final _Translations$common$nl common = _Translations$common$nl._(_root);
  @override
  late final _Translations$diff$nl diff = _Translations$diff$nl._(_root);
  @override
  late final _Translations$filament$nl filament = _Translations$filament$nl._(
    _root,
  );
  @override
  late final _Translations$history$nl history = _Translations$history$nl._(
    _root,
  );
  @override
  late final _Translations$historySurgery$nl historySurgery =
      _Translations$historySurgery$nl._(_root);
  @override
  late final _Translations$onboarding$nl onboarding =
      _Translations$onboarding$nl._(_root);
  @override
  late final _Translations$orrery$nl orrery = _Translations$orrery$nl._(_root);
  @override
  late final _Translations$palette$nl palette = _Translations$palette$nl._(
    _root,
  );
  @override
  late final _Translations$releaseNotes$nl releaseNotes =
      _Translations$releaseNotes$nl._(_root);
  @override
  late final _Translations$repoSummary$nl repoSummary =
      _Translations$repoSummary$nl._(_root);
  @override
  late final _Translations$review$nl review = _Translations$review$nl._(_root);
  @override
  late final _Translations$settings$nl settings = _Translations$settings$nl._(
    _root,
  );
  @override
  late final _Translations$sync$nl sync = _Translations$sync$nl._(_root);
  @override
  late final _Translations$xray$nl xray = _Translations$xray$nl._(_root);
}

// Path: app
class _Translations$app$nl extends Translations$app$en {
  _Translations$app$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get panelSettings => 'Instellingen';
  @override
  String get panelReleaseNotes => 'Release Notes';
  @override
  String get panelFilamentFindings => 'Filament-bevindingen';
  @override
  String get filamentFindingsUpper => 'FILAMENT-BEVINDINGEN';
  @override
  late final _Translations$app$cheatsheet$nl cheatsheet =
      _Translations$app$cheatsheet$nl._(_root);
  @override
  String get commandPaletteTooltip => 'Opdrachtenpalet   /';
  @override
  String get newDeskFallback => 'nieuwe desk';
  @override
  String get deskFallback => 'desk';
  @override
  String get currentDeskFallback => 'huidig';
  @override
  String get noRepositoryOpen => 'Geen repository geopend';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Kon niet als desk openen: ${error}';
  @override
  String couldNotDetectForge({required Object error}) =>
      'Kon forge niet detecteren: ${error}';
  @override
  String get cannotFetchPrNoForge =>
      'Kan PR niet ophalen: forge voor deze repo niet gedetecteerd.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      '${ref} overschrijven met de nieuwste versie van de remote?';
  @override
  String get overwrite => 'Overschrijven';
  @override
  String couldntFetchPr({required Object error}) =>
      'Kon PR niet ophalen: ${error}';
  @override
  String get promoteDeskToPr => 'Desk promoveren naar PR';
  @override
  String get applyToMain => 'Toepassen op main';
  @override
  String updateDeskFrom({required Object target, required Object source}) =>
      '${target} bijwerken vanaf ${source}';
  @override
  String bringChangesFromHere({required Object source}) =>
      'Wijzigingen van ${source} hierheen halen';
  @override
  String get editLocalPr => 'Lokale PR bewerken';
  @override
  String get discardLocalPr => 'Lokale PR verwerpen';
  @override
  String get closeDesk => 'Desk sluiten';
  @override
  String couldntPromote({required Object error}) =>
      'Promoveren mislukt: ${error}';
  @override
  String get commitOrShelveBeforeApplying =>
      'Commit of berg de wijzigingen van de desk op voordat je toepast.';
  @override
  String get couldNotResolveMainWorktree =>
      'Het pad van de hoofd-werkboom kon niet worden bepaald.';
  @override
  String couldntPromoteDesk({required Object error}) =>
      'Desk kon niet worden gepromoveerd: ${error}';
  @override
  String get couldntDetermineBaseBranch =>
      'De basis-branch voor deze desk kon niet worden bepaald.';
  @override
  String prBaseHeadSame({required Object branch}) =>
      'PR-basis en -head zijn dezelfde branch (${branch}) — niets toe te passen.';
  @override
  String appliedBranchToBase({required Object branch, required Object base}) =>
      '${branch} toegepast op ${base}';
  @override
  String updatedDeskToDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
    n,
    one: '${target} bijgewerkt naar ${source} (${n} commit).',
    other: '${target} bijgewerkt naar ${source} (${n} commits).',
  );
  @override
  String get fastForwardFailedFallback =>
      'Fast-forward kon niet schoon landen — toont in plaats daarvan een patch-voorbeeld.';
  @override
  String deskAheadOfDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
    n,
    one: '${target} loopt ${n} commit voor op ${source}.',
    other: '${target} loopt ${n} commits voor op ${source}.',
  );
  @override
  String deskUpToDate({required Object target, required Object source}) =>
      '${target} is al bij met ${source}.';
  @override
  String uncommittedPreviewNotice({required Object target}) =>
      'Niet-gecommitte wijzigingen in ${target} — toont in plaats daarvan een voorbeeld als patch.';
  @override
  String updateDeskFromLower({
    required Object target,
    required Object source,
  }) => '${target} bijwerken vanaf ${source}';
  @override
  String noUpdatesToBringFrom({required Object source}) =>
      'Geen updates op te halen van ${source}.';
  @override
  String get updatePrepFailed => 'Voorbereiden van update mislukt';
  @override
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => 'wijzigingen van ${source} naar ${target} halen';
  @override
  String noPatchableChanges({required Object source, required Object target}) =>
      'Geen patchbare wijzigingen op te halen van ${source} naar ${target}.';
  @override
  String get patchPrepFailed => 'Voorbereiden van patch mislukt';
  @override
  String failureWithError({required Object label, required Object error}) =>
      '${label}: ${error}';
  @override
  String get titleHint => 'titel';
  @override
  String get bodyHint => 'tekst';
  @override
  String get bodyOptionalHint => 'tekst (optioneel)';
  @override
  String get draftLower => 'concept';
  @override
  String get cancelLower => 'annuleren';
  @override
  String get saveLower => 'opslaan';
  @override
  String couldntSave({required Object error}) => 'Kon niet opslaan: ${error}';
  @override
  String get stashedNoOtherDesk =>
      'Wijzigingen gestasht — geen andere desk om ze op toe te passen. Gebruik git stash pop om te herstellen.';
  @override
  String get suggestedSource => 'voorgestelde bron';
  @override
  String tooltipModifiedCount({required Object n}) => '${n} gewijzigd';
  @override
  String tooltipAheadCount({required Object n}) => '${n} voor';
  @override
  String tooltipBehindCount({required Object n}) => '${n} achter';
  @override
  String get focusedEdits => 'gerichte wijzigingen';
  @override
  String get editsSpreadAcrossSubsystems =>
      'wijzigingen verspreid over subsystemen';
  @override
  String get editsTouchingManySubsystems =>
      'wijzigingen raken veel subsystemen';
  @override
  String get focusedBranch => 'gerichte branch';
  @override
  String get branchSpansMultipleSubsystems =>
      'branch beslaat meerdere subsystemen';
  @override
  String get structurallyDivergentFromMainline =>
      'structureel afwijkend van de hoofdlijn';
  @override
  String get localPr => 'lokale PR';
  @override
  String lastTouched({required Object time}) => 'laatst aangeraakt ${time}';
  @override
  String driftGroupCount({required Object n, required Object dir}) =>
      '${n} in ${dir}';
  @override
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';
  @override
  String get uncommittedChanges => 'Niet-gecommitte wijzigingen';
  @override
  String get closeDeskQuestion => 'Desk sluiten?';
  @override
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} niet-gecommit bestand.',
        other: '${n} niet-gecommitte bestanden.',
      );
  @override
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} commit voor op main.',
        other: '${n} commits voor op main.',
      );
  @override
  String get willRemoveWorktreeDirectory => 'Dit verwijdert de werkboom-map.';
  @override
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} bestand gewijzigd',
        other: '${n} bestanden gewijzigd',
      );
  @override
  String get shelveHere => 'Hier opbergen';
  @override
  String get discardAndClose => 'Verwerpen & sluiten';
  @override
  String get noRepository => 'geen repository';
  @override
  String get issuePromotedToRemote => 'Issue gepromoveerd naar remote.';
  @override
  String get pushedToRemote => 'Gepusht naar remote.';
  @override
  String get pulledFromRemote => 'Gepulld van remote.';
  @override
  String get remoteIssueNotFound => 'extern issue niet gevonden';
  @override
  String importedIssueLocally({required Object id}) =>
      '#${id} lokaal geïmporteerd.';
  @override
  String get issueAbandoned => 'Issue opgegeven.';
  @override
  String get abandonIssue => 'Issue opgeven';
  @override
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      'Lokaal issue #${id} permanent verwijderen? Dit wist de ref en kan niet ongedaan worden gemaakt.';
  @override
  String get abandon => 'Opgeven';
  @override
  String publishedBranch({required Object branch}) => '${branch} gepubliceerd.';
  @override
  String get publishingEllipsis => 'Publiceren…';
  @override
  String get publish => 'Publiceren';
  @override
  String get noRemoteConfigured =>
      'Geen remote geconfigureerd voor deze repository.';
  @override
  String get jumpToDesk => 'Naar desk springen';
  @override
  String get arrowOpen => '→ openen';
  @override
  String get openOnANewDesk => 'Openen op een nieuwe desk';
  @override
  String get plusDesk => '+ desk';
  @override
  String get plusSpace => '+ ';
  @override
  String get newBranchNameHint => 'nieuwe-branch-naam';
  @override
  String get escLower => 'esc';
  @override
  String get plusNewDesk => '+ nieuwe desk';
  @override
  String get fromHeadEllipsis => 'vanaf HEAD...';
  @override
  String get viewAllBranches => 'Alle branches bekijken';
  @override
  String get issuesLower => 'issues';
  @override
  String get newIssueLower => 'nieuw issue';
  @override
  String get noneLinked => 'niets gekoppeld';
  @override
  String get noOpenIssues => 'geen open issues';
  @override
  String get createAndPushLower => 'aanmaken + pushen';
  @override
  String get createLower => 'aanmaken';
  @override
  String get remoteLower => 'remote';
  @override
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';
  @override
  String get promoteToRemote => 'Promoveren naar remote';
  @override
  String get pushToRemote => 'Pushen naar remote';
  @override
  String get pullFromRemote => 'Pullen van remote';
  @override
  String get importLabel => 'Importeren';
  @override
  String get failedToCreateRepository => 'Repository aanmaken mislukt.';
  @override
  String get openRepositoryLower => 'repository openen';
  @override
  String get newRepositoryLower => 'nieuwe repository';
  @override
  String get back => 'Terug';
  @override
  String get openRepositoryDialogTitle => 'Repository openen';
  @override
  String get createRepositoryDialogTitle => 'Repository aanmaken';
  @override
  String get cloneTargetDialogTitle => 'Kloon-doel';
  @override
  String get cloneToDialogTitle => 'Klonen naar';
  @override
  String get exportToDialogTitle => 'Exporteren naar';
  @override
  String get createFromTemplateInDialogTitle => 'Aanmaken uit sjabloon in';
  @override
  String get notAGitRepoInitConfirm =>
      'Geen git-repository. Hier een initialiseren?';
  @override
  String get repositoryUrlRequired => 'Repository-URL vereist.';
  @override
  String get failedToCloneRepository => 'Repository klonen mislukt.';
  @override
  String cloningEllipsis({required Object name}) => '${name} klonen...';
  @override
  String get cloneCancelled => 'Kloon geannuleerd.';
  @override
  String get noProjectsYet => 'Nog geen projecten';
  @override
  String get dissolveGroup => 'Groep ontbinden';
  @override
  String get projectsHeader => 'Projecten';
  @override
  String get cloneLabel => 'Klonen';
  @override
  String get createLabel => 'Aanmaken';
  @override
  String get openLabel => 'Openen';
  @override
  String get repositoryUrlPlaceholder => 'Repository-URL';
  @override
  String get projectNameOrFullPathPlaceholder => 'projectnaam of volledig pad';
  @override
  String get pathToProjectPlaceholder => '/pad/naar/project';
  @override
  String get cloneToFolderPathPlaceholder => 'Pad van kloon-doelmap';
  @override
  String get switchToCreateRepo => 'Wisselen naar Repo aanmaken';
  @override
  String get explorer => 'Verkenner';
  @override
  String get terminal => 'Terminal';
  @override
  String get cloneUrl => 'Kloon-URL';
  @override
  String get copyPath => 'Pad kopiëren';
  @override
  String get export => 'Exporteren';
  @override
  String get readme => 'README';
  @override
  String get duplicate => 'Dupliceren';
  @override
  String get template => 'Sjabloon';
  @override
  String get forgetThisProject => 'Dit project vergeten';
  @override
  String get aiKindCommitMessage => 'commit-bericht';
  @override
  String get aiKindReview => 'review';
  @override
  String get aiKindMuse => 'muse';
  @override
  String get aiKindPresent => 'presenteren';
  @override
  String get aiKindDebug => 'debug';
  @override
  String aiStatusRunning({required Object kind}) => '${kind} bezig';
  @override
  String aiStatusFailedUnread({required Object kind}) =>
      '${kind} mislukt (ongelezen)';
  @override
  String aiStatusReadyUnread({required Object kind}) =>
      '${kind} klaar (ongelezen)';
  @override
  String get filesLower => 'bestanden';
  @override
  String get commitsLower => 'commits';
  @override
  String get undoLabel => 'Ongedaan maken';
  @override
  String get goLabel => 'start';
  @override
  String countdownSeconds({required Object n}) => '${n}s';
  @override
  String get collapseGlyph => '▲ inklappen';
  @override
  String moreLinesGlyph({required Object n}) => '▼ ${n} meer regels';
}

// Path: backend
class _Translations$backend$nl extends Translations$backend$en {
  _Translations$backend$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$backend$ops$nl ops = _Translations$backend$ops$nl._(
    _root,
  );
  @override
  late final _Translations$backend$mergeOutcome$nl mergeOutcome =
      _Translations$backend$mergeOutcome$nl._(_root);
}

// Path: branches
class _Translations$branches$nl extends Translations$branches$en {
  _Translations$branches$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get runningAiReview => 'AI-review bezig…';
  @override
  String prNumberLabel({required Object number}) => 'PR #${number}';
  @override
  String get findings => 'BEVINDINGEN';
  @override
  String get observations => 'OBSERVATIES';
  @override
  String get renameEllipsis => 'Hernoemen…';
  @override
  String get publish => 'Publiceren';
  @override
  String publishFailed({required Object error}) =>
      'Publiceren mislukt: ${error}';
  @override
  String couldntOpenDesk({required Object error}) =>
      'Desk kon niet worden geopend: ${error}';
  @override
  String syncFailed({required Object error}) => 'Sync mislukt: ${error}';
  @override
  String get renameBranchTitle => 'Branch hernoemen';
  @override
  String get newNameHint => 'nieuwe naam';
  @override
  String get rename => 'Hernoemen';
  @override
  String invalidBranchName({required Object name}) =>
      '\'${name}\' is geen geldige branch-naam.';
  @override
  String renameFailed({required Object error}) => 'Hernoemen mislukt: ${error}';
  @override
  String deletingBranch({required Object name}) => '${name} verwijderen';
  @override
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '\'${name}\' is geopend in desk \'${desk}\'.';
  @override
  String get openDesk => 'Desk openen';
  @override
  String openInDeskShort({required Object desk}) =>
      'openen in desk \'${desk}\'';
  @override
  String get couldNotPinBranch =>
      'branch-tip kon niet worden vastgezet; verwijderen overgeslagen';
  @override
  String get couldNotPinTag =>
      'tag kon niet worden vastgezet; verwijderen overgeslagen';
  @override
  String deletingTag({required Object name}) => 'Tag ${name} verwijderen';
  @override
  String get applyToActiveChanges => 'Toepassen op actieve wijzigingen…';
  @override
  String get couldNotLoadPrDiff => 'PR-diff kon niet worden geladen.';
  @override
  String prSourceLabel({required Object number, required Object title}) =>
      'PR #${number}: ${title}';
  @override
  String mergeIntoDesk({required Object branch}) => 'Mergen in ${branch}…';
  @override
  String get checkoutThisPr => 'Deze PR uitchecken';
  @override
  String get mergeIntoNewDesk => 'Mergen in nieuwe desk…';
  @override
  String get pushToForge => 'Pushen naar forge';
  @override
  String get linkToIssue => 'Koppelen aan issue…';
  @override
  String get gitPatch => '↓ git-patch';
  @override
  String get copyBranchName => 'Branch-naam kopiëren';
  @override
  String copiedRef({required Object ref}) => '"${ref}" gekopieerd';
  @override
  String get reviewPr => 'PR reviewen';
  @override
  String get openInBrowser => 'Openen in browser';
  @override
  String get markAsRead => 'Markeren als gelezen';
  @override
  String get markAsUnread => 'Markeren als ongelezen';
  @override
  String get replaceLocalCommitsTitle => 'Lokale commits vervangen?';
  @override
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref} heeft lokale commits die niet op de externe PR-head staan. Bij het bijwerken worden ze vervangen door de nieuwste versie van de remote.';
  @override
  String get update => 'Bijwerken';
  @override
  String couldntFetchPr({required Object error}) =>
      'Kon PR niet ophalen: ${error}';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Kon niet als desk openen: ${error}';
  @override
  String couldntOpenInBrowser({required Object error}) =>
      'Kon niet in browser openen: ${error}';
  @override
  String get noIssuesYetLocal =>
      'Nog geen issues. Open er een upstream, of gebruik "+ nieuw lokaal issue" in de issues-lens.';
  @override
  String get remotePrsLinkLocalOnly =>
      'Externe PRs kunnen alleen aan lokale issues worden gekoppeld. Maak er een met "+ nieuw lokaal issue".';
  @override
  String linkPrToIssues({required Object number}) =>
      'PR #${number} koppelen aan issue(s)';
  @override
  String get noPrsYetLocal =>
      'Nog geen PRs. Open er een upstream, of promoveer een desk naar PR.';
  @override
  String get remoteIssuesLinkLocalOnly =>
      'Externe issues kunnen alleen aan lokale PRs worden gekoppeld. Promoveer eerst een desk naar PR.';
  @override
  String linkIssueToPrs({required Object number}) =>
      'Issue #${number} koppelen aan PR(\'s)';
  @override
  String couldntToggleLink({required Object error}) =>
      'Koppeling kon niet worden omgeschakeld: ${error}';
  @override
  String get openPatchDialogTitle => 'Patch openen (.patch / .diff)';
  @override
  String get clipboardNoText => 'Klembord bevat geen tekst.';
  @override
  String get clipboardPatchLabel => 'clipboard.patch';
  @override
  String failedToOpenPatch({required Object error}) =>
      'Patch openen mislukt: ${error}';
  @override
  String get patchEmptyOrUnparseable => 'Patch is leeg of niet te parsen.';
  @override
  String get prPushedToForge => 'PR gepusht naar forge.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      '${ref} overschrijven met de nieuwste versie van de remote?';
  @override
  String get overwrite => 'Overschrijven';
  @override
  String get loadingBranchesTitle => 'Branches laden';
  @override
  String get loadingBranchesMessage => 'Lokale branches en tags lezen.';
  @override
  String get branchesUnavailableTitle => 'Branches niet beschikbaar';
  @override
  String get filterPullRequestsHint => 'pull requests filteren…';
  @override
  String get filterIssuesHint => 'issues filteren…';
  @override
  String get branchNameHint => 'branch-naam';
  @override
  String get tagsNewestFirst => 'tags, nieuwste eerst';
  @override
  String get tagsOldestFirst => 'tags, oudste eerst';
  @override
  String get flipSortDirection => 'sorteerrichting omkeren';
  @override
  String get readingPullRequests => 'Pull requests lezen…';
  @override
  String get noOpenPullRequests => 'Geen open pull requests';
  @override
  String get noPullRequestsHint =>
      'Open er een vanuit een branch, of promoveer een desk.';
  @override
  String get noPrsMatchFilters => 'Geen PRs passen bij deze filters';
  @override
  String get toggleFiltersRowAbove =>
      'Schakel de filters in de rij hierboven uit.';
  @override
  String get issuesNewestFirst => 'issues, nieuwste eerst';
  @override
  String get issuesOldestFirst => 'issues, oudste eerst';
  @override
  String get issuesHeading => 'ISSUES';
  @override
  String get readingIssuesLower => 'issues lezen…';
  @override
  String get noOpenIssues => 'Geen open issues';
  @override
  String get noIssuesHint => '+ nieuw om werk en bugs bij te houden.';
  @override
  String get nothingMatches => 'Niets past';
  @override
  String get toggleFiltersAbove => 'Schakel de filters hierboven uit.';
  @override
  String get bucketFresh => 'VERS';
  @override
  String get bucketThisWeek => 'DEZE WEEK';
  @override
  String get bucketStalled => 'VASTGELOPEN';
  @override
  String get bucketOlder => 'OUDER';
  @override
  String get couldNotResolveMainWorktree =>
      'Het pad van de hoofd-worktree kon niet worden bepaald.';
  @override
  String couldntSubmitReview({required Object error}) =>
      'Review kon niet worden ingediend: ${error}';
  @override
  String get reviewAiNotAvailable => 'Review-AI is nog niet beschikbaar.';
  @override
  String get noReviewModelConfigured => 'Geen review-model geconfigureerd.';
  @override
  String get deskFallback => 'desk';
  @override
  String deskUncommittedChanges({
    required num n,
    required Object branch,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
    n,
    one:
        '${branch} heeft ${n} niet-gecommitte wijziging — commit of stash eerst.',
    other:
        '${branch} heeft ${n} niet-gecommitte wijzigingen — commit of stash eerst.',
  );
  @override
  String get targetDeskNoBranch => 'Doel-desk heeft geen branch.';
  @override
  String mergePrIntoDesk({required Object number, required Object branch}) =>
      'PR #${number} mergen in ${branch}';
  @override
  String get conflictCheckUnavailableVersion =>
      'Conflictcontrole niet beschikbaar — git 2.38+ vereist';
  @override
  String get conflictCheckUnavailable => 'Conflictcontrole niet beschikbaar';
  @override
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'CONFLICT DREIGT · ${n} bestand',
        other: 'CONFLICT DREIGT · ${n} bestanden',
      );
  @override
  String plusMore({required Object n}) => '+${n} meer';
  @override
  String get rebase => 'Rebase';
  @override
  String get squash => 'Squash';
  @override
  String get mergeCommit => 'Merge-commit';
  @override
  String noDeskForBranch({required Object branch}) =>
      'Geen desk gevonden voor branch ${branch}';
  @override
  String get mergeAnyway => 'Toch mergen';
  @override
  String get readingIssues => 'Issues lezen…';
  @override
  String get openUpstreamOrLocal => 'Open er een upstream, of open een lokale.';
  @override
  String get noIssuesMatchFilters => 'Geen issues passen bij deze filters';
  @override
  String couldntCreateIssue({required Object error}) =>
      'Issue kon niet worden aangemaakt: ${error}';
  @override
  String get promoteToRemote => 'Promoveren naar remote';
  @override
  String get pushToRemote => 'Pushen naar remote';
  @override
  String get pullFromRemote => 'Pullen van remote';
  @override
  String get import => 'Importeren';
  @override
  String get linkToPr => 'Koppelen aan PR…';
  @override
  String get abandon => 'Opgeven';
  @override
  String get issuePromotedToRemote => 'Issue gepromoveerd naar remote.';
  @override
  String get issuePushedToRemote => 'Gepusht naar remote.';
  @override
  String get issuePulledFromRemote => 'Gepulld van remote.';
  @override
  String issueImportedLocally({required Object number}) =>
      '#${number} lokaal geïmporteerd.';
  @override
  String get abandonIssueTitle => 'Issue opgeven';
  @override
  String abandonIssueMessage({required Object id}) =>
      'Lokaal issue #${id} permanent verwijderen? Dit wist de ref en kan niet ongedaan worden gemaakt.';
  @override
  String couldntAbandon({required Object error}) => 'Opgeven mislukt: ${error}';
  @override
  String couldntPostComment({required Object error}) =>
      'Reactie kon niet worden geplaatst: ${error}';
  @override
  String couldntCloseIssue({required Object error}) =>
      'Issue kon niet worden gesloten: ${error}';
  @override
  String couldntAddLabel({required Object error}) =>
      'Label kon niet worden toegevoegd: ${error}';
  @override
  String get lensBranches => 'BRANCHES';
  @override
  String get lensPrs => 'PRs';
  @override
  String get patchUp => '↑ patch';
  @override
  String get syncRibbon => '⇅ sync';
  @override
  String get kbHeading => 'TOETSENBORD';
  @override
  String get kbNavigateRows => 'rijen navigeren';
  @override
  String get kbExpandCollapse => 'gefocuste rij uit-/inklappen';
  @override
  String get kbCheckoutPr => 'gefocuste PR lokaal uitchecken';
  @override
  String get kbApproveReview => 'goedkeuren · review';
  @override
  String get kbRequestChanges => 'wijzigingen vragen';
  @override
  String get kbFocusSearch => 'zoeken focussen';
  @override
  String get kbSwitchLens => 'lens wisselen (branches · prs)';
  @override
  String get kbToggleOverlay => 'deze overlay omschakelen';
  @override
  String get kbPressToDismiss => 'druk ergens om te sluiten';
  @override
  String get overrideScarTooltip =>
      'gemergd met mislukte checks of zonder goedkeurende review — onderzoek het eerst onder vuur';
  @override
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} bestand overlapt je niet-gecommitte werk',
        other: '${n} bestanden overlappen je niet-gecommitte werk',
      );
  @override
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '#${pr}  (${n} bestand)',
        other: '#${pr}  (${n} bestanden)',
      );
  @override
  String get prStateDraft => 'DRAFT';
  @override
  String get localBadge => 'LOKAAL';
  @override
  String get myReviewPending => 'jouw review in afwachting';
  @override
  String get myReviewApproved => 'jij ✓';
  @override
  String get myReviewChangesRequested => 'jij ✗ wijzigingen gevraagd';
  @override
  String get myReviewCommented => 'jij hebt gereageerd';
  @override
  String get myReviewDefault => 'jij';
  @override
  String tailCommentsAuthor({required Object count}) =>
      '${count} reacties · laatste van auteur getoond';
  @override
  String get tailLastComment => 'laatste reactie';
  @override
  String tailLastReviewState({required Object state}) =>
      'laatste review · ${state}';
  @override
  String get tailLastReview => 'laatste review';
  @override
  String tailLastCheckState({required Object state}) =>
      'laatste check · ${state}';
  @override
  String get tailLastCommit => 'laatste commit';
  @override
  String get tailLastActivity => 'laatste activiteit';
  @override
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'sluit ${n} issue — klik om te springen',
        other: 'sluit ${n} issues — klik om te springen',
      );
  @override
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'behandeld door ${n} PR — klik om te springen',
        other: 'behandeld door ${n} PRs — klik om te springen',
      );
  @override
  String get checksLabel => 'checks';
  @override
  String get reviewersLabel => 'reviewers';
  @override
  String get conflictsLabel => 'conflicten';
  @override
  String exportFailed({required Object error}) => 'Export mislukt: ${error}';
  @override
  String get readingFiles => 'bestanden lezen…';
  @override
  String get noDetailAvailable => 'geen detail beschikbaar';
  @override
  String get noFilesReported => 'geen bestanden gemeld';
  @override
  String get readingGitHistory => 'git-geschiedenis lezen…';
  @override
  String get knowsThisCode => 'kent deze code';
  @override
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} commit op deze bestanden in het afgelopen jaar',
        other: '${n} commits op deze bestanden in het afgelopen jaar',
      );
  @override
  String get willFight => 'ZAL VECHTEN';
  @override
  String orbitalPartnerCos({required Object cos}) =>
      'orbitale partner — cos ${cos}';
  @override
  String get orbitLabel => 'orbit';
  @override
  String get touchesYourLocalWork => 'RAAKT JE LOKALE WERK';
  @override
  String get mergingWillConflict =>
      'mergen zal waarschijnlijk botsen met je niet-gecommitte wijzigingen';
  @override
  String get closesHeading => 'SLUIT';
  @override
  String get filesHeading => 'BESTANDEN';
  @override
  String get orientAligned => 'uitgelijnd';
  @override
  String get orientAdjacent => 'aangrenzend';
  @override
  String get orientOrthogonal => 'orthogonaal';
  @override
  String shapeField({required Object v}) => 'veld ${v}';
  @override
  String shapeSource({required Object v}) => 'bron ${v}';
  @override
  String shapeSrcDelta({required Object v}) => 'bronΔ ${v}';
  @override
  String shapeFldDelta({required Object v}) => 'veldΔ ${v}';
  @override
  String shapeHf({required Object v}) => 'hf ${v}';
  @override
  String shapeHo({required Object v}) => 'ho ${v}';
  @override
  String shapeRg({required Object v}) => 'rg ${v}';
  @override
  String shapeFlowG({required Object v}) => 'g ${v}';
  @override
  String shapeFlowC({required Object v}) => 'c ${v}';
  @override
  String shapeFlowH({required Object v}) => 'h ${v}';
  @override
  String shapeStress({required Object v}) => 'stress ${v}';
  @override
  String shapeWit({required Object v}) => 'wit ${v}';
  @override
  String resonanceReadout({required Object v}) => 'resonantie ${v}';
  @override
  String ghostFileTooltip({required Object path}) =>
      'beweegt meestal mee met de bestanden in deze PR\n(${path})';
  @override
  String get prStateDraftLower => 'concept';
  @override
  String get keystoneTooltip => 'sluitsteen — repo-brede brugbestand';
  @override
  String get reviewNoteHint => 'laat een notitie achter (optioneel)…';
  @override
  String get reviewComment => 'reageren';
  @override
  String get reviewRequestChanges => 'wijzigingen vragen';
  @override
  String get reviewApprove => '✓ goedkeuren';
  @override
  String get actionPatchDown => '↓ patch';
  @override
  String get actionPrReview => '✦ pr-review';
  @override
  String get actionOpenAsDesk => '⊞ openen als desk';
  @override
  String get actionCheckout => '[c] checkout';
  @override
  String get actionMerge => '[m] merge ▾';
  @override
  String get mergeMenuMergeCommit => 'merge-commit';
  @override
  String get mergeMenuSquash => 'squash & merge';
  @override
  String get mergeMenuRebase => 'rebase & merge';
  @override
  String get deleteBranchAfter => 'branch daarna verwijderen';
  @override
  String checkDurationSec({required Object n}) => '${n}s';
  @override
  String checkDurationMin({required Object m, required Object s}) =>
      '${m}m ${s}s';
  @override
  String assignedTo({required Object names}) => 'toegewezen: ${names}';
  @override
  String issueConvLine({required Object n, required Object time}) =>
      '${n} gesprek · ${time}';
  @override
  String get readingThread => 'thread lezen…';
  @override
  String get addressedByHeading => 'BEHANDELD DOOR';
  @override
  String get descriptionHeading => 'BESCHRIJVING';
  @override
  String get threadHeading => 'THREAD';
  @override
  String get replyHint => 'antwoorden…';
  @override
  String get assignMe => 'aan mij toewijzen';
  @override
  String get closeLower => 'sluiten';
  @override
  String get postReply => '↩ plaatsen';
  @override
  String get remoteProviderUnavailable => 'Externe provider niet beschikbaar';
  @override
  String get noRecognisedRemoteHost =>
      'Geen herkende externe host voor deze repo.';
  @override
  String get corpseGone => 'weg';
  @override
  String get corpseAbsorbed => 'geabsorbeerd';
  @override
  String get corpseSquashed => 'gesquasht';
  @override
  String absorbedDeliveredIn({required Object hash}) => 'geleverd in ${hash}';
  @override
  String get absorbedNoChanges => 'mergen voegt geen wijzigingen toe';
  @override
  String get corpseTagUpstreamGone => 'upstream weg';
  @override
  String corpseTagAbsorbed({required Object receipt}) =>
      'geabsorbeerd, ${receipt}';
  @override
  String get corpseTagSquashed => 'gesquasht en gemergd';
  @override
  String semanticsCurrentBranch({required Object name}) =>
      '${name}, huidige branch';
  @override
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}, volgt ${upstream}';
  @override
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}, ${tag}';
  @override
  String semanticsWorktreeOpen({required Object label}) =>
      '${label}, worktree open';
  @override
  String semanticsIdle({required Object name, required Object phrase}) =>
      '${name}, ${phrase}';
  @override
  String semanticsCorpse({
    required Object name,
    required Object tag,
    required Object phrase,
  }) => '${name}, ${tag}, ${phrase}';
  @override
  String get crossLinkDesk => 'desk';
  @override
  String get crossLinkPr => 'PR';
  @override
  String get crossLinkPrDraft => 'PR · concept';
  @override
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} issue',
        other: '${n} issues',
      );
  @override
  String get headBadge => 'HEAD';
  @override
  String trackingLine({required Object upstream}) => '→ volgt: ${upstream}';
  @override
  String get checkoutButton => 'Checkout';
  @override
  String get createBranch => 'Branch maken';
  @override
  String get newBranchName => 'Nieuwe branch-naam';
  @override
  String newBranchNameError({required Object error}) =>
      'Nieuwe branch-naam — ${error}';
  @override
  String get forceDelete => 'Forceren?';
  @override
  String get annotated => 'geannoteerd';
  @override
  String get applyCheckFailed => 'apply --check mislukt';
  @override
  String get openPatchFrom => 'PATCH OPENEN VAN';
  @override
  String get patchFromFile => 'uit bestand…';
  @override
  String get patchFromFileHint => '.patch / .diff';
  @override
  String get patchFromClipboard => 'uit klembord';
  @override
  String get patchFromClipboardHint => 'tekst plakken';
  @override
  String get patchPreviewHeading => 'PATCH-VOORBEELD';
  @override
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';
  @override
  String get stagedDone => 'gestaged.';
  @override
  String get appliedDone => 'toegepast.';
  @override
  String get opening => 'openen…';
  @override
  String get mergeEditor => '⇋ merge-editor';
  @override
  String get staging => 'stagen…';
  @override
  String get applying => 'toepassen…';
  @override
  String get stage => 'stage';
  @override
  String get apply => 'toepassen';
  @override
  String get refineHint =>
      'verfijnen… (bijv. "laat ook de logger-wijzigingen weg")';
  @override
  String get reverseArmedTooltip =>
      'scherp — de volgende toepassing REVERT de patch (-R)';
  @override
  String get reverseDisarmedTooltip =>
      'reverse scherpstellen (-R) — terugdraaien in plaats van toepassen';
  @override
  String get reverseArmedLabel => '⟲ reverse ✓';
  @override
  String get reverseLabel => '⟲ reverse';
  @override
  String get untouchedHeading => '⚠ ONAANGERAAKT';
  @override
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${count} van ${n} bestand niet in de patch',
        other: '${count} van ${n} bestanden niet in de patch',
      );
  @override
  String get staysConflicted =>
      'deze bestanden blijven in conflict — toepassen staged ze niet';
  @override
  String get orWith => 'OF MET';
  @override
  String get noAiModelConfigured => 'geen AI-model geconfigureerd';
  @override
  String applyWithPatchFrom({required Object label}) =>
      'toepassen met patch van ${label}';
  @override
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => 'toepassen met patch van ${label}  ·  ${model}';
  @override
  String get patching => 'patchen…';
  @override
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  toepassen met patch van ${label}';
  @override
  String get orWithAnotherModel => 'of met een ander model';
  @override
  String get applyCheckPassed =>
      'git apply --check geslaagd — patch wordt schoon toegepast';
  @override
  String get gitApplyCheckFailed => 'git apply --check mislukt';
  @override
  String get appliesClean => 'wordt schoon toegepast';
  @override
  String get willNotApply => 'wordt niet toegepast';
  @override
  String get newLocalIssue => 'nieuw lokaal issue';
  @override
  String get filterHint => 'filteren…';
  @override
  String get nothingToLink => 'Nog niets om te koppelen.';
  @override
  String get nothingMatchesDot => 'Niets past.';
  @override
  String get relevantHeading => 'RELEVANT';
  @override
  String get allHeading => 'ALLE';
  @override
  String get doneLower => 'klaar';
  @override
  String get candidateRemote => 'R';
  @override
  String get candidateLocal => 'L';
  @override
  String get newLocalIssueTitle => 'Nieuw lokaal issue';
  @override
  String get titleHint => 'titel';
  @override
  String get bodyHint => 'tekst (markdown)';
  @override
  String get cancelLower => 'annuleren';
  @override
  String get createLower => 'aanmaken';
  @override
  String get deleteFailed => 'verwijderen mislukt';
  @override
  String reviewFailed({required Object error}) => 'Review mislukt: ${error}';
  @override
  String get resolutionFailed => 'oplossen mislukt';
  @override
  String get patchBlocksNoCover =>
      'model gaf patch-blokken terug die de falende bestanden niet dekten';
  @override
  String get applyFailed => 'toepassen mislukt';
  @override
  String get emptyOrUnparseablePatch =>
      'model gaf een lege of niet te parsen patch terug';
  @override
  String noModelConfiguredFor({required Object label}) =>
      'geen model geconfigureerd voor "${label}"';
  @override
  String get checksHeading => 'CONTROLES';
  @override
  String get peopleHeading => 'PERSONEN';
  @override
  String get conversationHeading => 'GESPREK';
}

// Path: changes
class _Translations$changes$nl extends Translations$changes$en {
  _Translations$changes$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$usage$nl usage =
      _Translations$changes$usage$nl._(_root);
  @override
  late final _Translations$changes$tabs$nl tabs =
      _Translations$changes$tabs$nl._(_root);
  @override
  late final _Translations$changes$tabStrip$nl tabStrip =
      _Translations$changes$tabStrip$nl._(_root);
  @override
  late final _Translations$changes$select$nl select =
      _Translations$changes$select$nl._(_root);
  @override
  late final _Translations$changes$constellationToggle$nl constellationToggle =
      _Translations$changes$constellationToggle$nl._(_root);
  @override
  late final _Translations$changes$nudgeChip$nl nudgeChip =
      _Translations$changes$nudgeChip$nl._(_root);
  @override
  late final _Translations$changes$minimap$nl minimap =
      _Translations$changes$minimap$nl._(_root);
  @override
  late final _Translations$changes$tagInput$nl tagInput =
      _Translations$changes$tagInput$nl._(_root);
  @override
  late final _Translations$changes$composer$nl composer =
      _Translations$changes$composer$nl._(_root);
  @override
  late final _Translations$changes$commit$nl commit =
      _Translations$changes$commit$nl._(_root);
  @override
  late final _Translations$changes$rebase$nl rebase =
      _Translations$changes$rebase$nl._(_root);
  @override
  late final _Translations$changes$editor$nl editor =
      _Translations$changes$editor$nl._(_root);
  @override
  late final _Translations$changes$editorTitles$nl editorTitles =
      _Translations$changes$editorTitles$nl._(_root);
  @override
  late final _Translations$changes$askHint$nl askHint =
      _Translations$changes$askHint$nl._(_root);
  @override
  late final _Translations$changes$fileMenu$nl fileMenu =
      _Translations$changes$fileMenu$nl._(_root);
  @override
  late final _Translations$changes$multiFileMenu$nl multiFileMenu =
      _Translations$changes$multiFileMenu$nl._(_root);
  @override
  late final _Translations$changes$ignoreMenu$nl ignoreMenu =
      _Translations$changes$ignoreMenu$nl._(_root);
  @override
  late final _Translations$changes$discard$nl discard =
      _Translations$changes$discard$nl._(_root);
  @override
  late final _Translations$changes$snack$nl snack =
      _Translations$changes$snack$nl._(_root);
  @override
  late final _Translations$changes$trace$nl trace =
      _Translations$changes$trace$nl._(_root);
  @override
  late final _Translations$changes$cleanTree$nl cleanTree =
      _Translations$changes$cleanTree$nl._(_root);
  @override
  late final _Translations$changes$guardrail$nl guardrail =
      _Translations$changes$guardrail$nl._(_root);
  @override
  late final _Translations$changes$dropHint$nl dropHint =
      _Translations$changes$dropHint$nl._(_root);
  @override
  late final _Translations$changes$diffEmpty$nl diffEmpty =
      _Translations$changes$diffEmpty$nl._(_root);
  @override
  late final _Translations$changes$shelvePill$nl shelvePill =
      _Translations$changes$shelvePill$nl._(_root);
  @override
  late final _Translations$changes$stashAction$nl stashAction =
      _Translations$changes$stashAction$nl._(_root);
  @override
  late final _Translations$changes$stashContents$nl stashContents =
      _Translations$changes$stashContents$nl._(_root);
  @override
  late final _Translations$changes$stashFile$nl stashFile =
      _Translations$changes$stashFile$nl._(_root);
  @override
  late final _Translations$changes$fileRow$nl fileRow =
      _Translations$changes$fileRow$nl._(_root);
  @override
  late final _Translations$changes$resolveStrip$nl resolveStrip =
      _Translations$changes$resolveStrip$nl._(_root);
  @override
  late final _Translations$changes$badge$nl badge =
      _Translations$changes$badge$nl._(_root);
  @override
  late final _Translations$changes$review$nl review =
      _Translations$changes$review$nl._(_root);
  @override
  late final _Translations$changes$commitBtn$nl commitBtn =
      _Translations$changes$commitBtn$nl._(_root);
  @override
  late final _Translations$changes$shapeBtn$nl shapeBtn =
      _Translations$changes$shapeBtn$nl._(_root);
  @override
  late final _Translations$changes$dejaVu$nl dejaVu =
      _Translations$changes$dejaVu$nl._(_root);
  @override
  late final _Translations$changes$identity$nl identity =
      _Translations$changes$identity$nl._(_root);
  @override
  late final _Translations$changes$staleScope$nl staleScope =
      _Translations$changes$staleScope$nl._(_root);
  @override
  late final _Translations$changes$finding$nl finding =
      _Translations$changes$finding$nl._(_root);
  @override
  late final _Translations$changes$muse$nl muse =
      _Translations$changes$muse$nl._(_root);
  @override
  late final _Translations$changes$debug$nl debug =
      _Translations$changes$debug$nl._(_root);
  @override
  late final _Translations$changes$includeSummary$nl includeSummary =
      _Translations$changes$includeSummary$nl._(_root);
  @override
  late final _Translations$changes$status$nl status =
      _Translations$changes$status$nl._(_root);
  @override
  late final _Translations$changes$stash$nl stash =
      _Translations$changes$stash$nl._(_root);
  @override
  late final _Translations$changes$tooltips$nl tooltips =
      _Translations$changes$tooltips$nl._(_root);
  @override
  late final _Translations$changes$mergeEditor$nl mergeEditor =
      _Translations$changes$mergeEditor$nl._(_root);
  @override
  late final _Translations$changes$conflictResolution$nl conflictResolution =
      _Translations$changes$conflictResolution$nl._(_root);
  @override
  late final _Translations$changes$mergeFlow$nl mergeFlow =
      _Translations$changes$mergeFlow$nl._(_root);
  @override
  late final _Translations$changes$constellation$nl constellation =
      _Translations$changes$constellation$nl._(_root);
}

// Path: common
class _Translations$common$nl extends Translations$common$en {
  _Translations$common$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get listSeparator => ', ';
  @override
  String get cancel => 'Annuleren';
  @override
  String get close => 'Sluiten';
  @override
  String get save => 'Opslaan';
  @override
  String get delete => 'Verwijderen';
  @override
  String get retry => 'Opnieuw';
  @override
  String get copy => 'Kopiëren';
  @override
  String get copied => 'Gekopieerd';
  @override
  String get done => 'Klaar';
  @override
  String get loading => 'Laden…';
  @override
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} bestand',
        other: '${n} bestanden',
      );
  @override
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} commit',
        other: '${n} commits',
      );
  @override
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} branch',
        other: '${n} branches',
      );
  @override
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} lokale commit',
        other: '${n} lokale commits',
      );
  @override
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} externe commit',
        other: '${n} externe commits',
      );
  @override
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} bestand met conflict',
        other: '${n} bestanden met conflict',
      );
  @override
  late final _Translations$common$time$nl time = _Translations$common$time$nl._(
    _root,
  );
  @override
  late final _Translations$common$size$nl size = _Translations$common$size$nl._(
    _root,
  );
}

// Path: diff
class _Translations$diff$nl extends Translations$diff$en {
  _Translations$diff$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$diff$status$nl status =
      _Translations$diff$status$nl._(_root);
  @override
  late final _Translations$diff$toolbar$nl toolbar =
      _Translations$diff$toolbar$nl._(_root);
  @override
  late final _Translations$diff$hunkDropdown$nl hunkDropdown =
      _Translations$diff$hunkDropdown$nl._(_root);
  @override
  String stagingFailed({required Object error}) =>
      'Gedeeltelijk stagen mislukt: ${error}';
  @override
  late final _Translations$diff$trail$nl trail = _Translations$diff$trail$nl._(
    _root,
  );
  @override
  late final _Translations$diff$pinned$nl pinned =
      _Translations$diff$pinned$nl._(_root);
  @override
  late final _Translations$diff$hunkHint$nl hunkHint =
      _Translations$diff$hunkHint$nl._(_root);
  @override
  late final _Translations$diff$binary$nl binary =
      _Translations$diff$binary$nl._(_root);
  @override
  late final _Translations$diff$media$nl media = _Translations$diff$media$nl._(
    _root,
  );
}

// Path: filament
class _Translations$filament$nl extends Translations$filament$en {
  _Translations$filament$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get noRepositoryOpen => 'Geen repository geopend.';
  @override
  String scanningProgress({required Object scanned, required Object total}) =>
      'scannen ${scanned} / ${total} bestanden…';
  @override
  String findingsAcrossFiles({required Object count, required Object files}) =>
      '${count} bevindingen in ${files} bestanden';
  @override
  String copiedFindings({required Object count}) =>
      '${count} bevindingen gekopieerd';
  @override
  String get copy => 'KOPIËREN';
  @override
  String get noFindings => 'Geen bevindingen in de uitvoeringsstroom.';
  @override
  late final _Translations$filament$severity$nl severity =
      _Translations$filament$severity$nl._(_root);
  @override
  late final _Translations$filament$kind$nl kind =
      _Translations$filament$kind$nl._(_root);
  @override
  String lineLabel({required Object line}) => 'R${line}';
  @override
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class _Translations$history$nl extends Translations$history$en {
  _Translations$history$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$nl commitLede =
      _Translations$history$commitLede$nl._(_root);
  @override
  late final _Translations$history$seismograph$nl seismograph =
      _Translations$history$seismograph$nl._(_root);
  @override
  late final _Translations$history$worldline$nl worldline =
      _Translations$history$worldline$nl._(_root);
  @override
  late final _Translations$history$contextMenu$nl contextMenu =
      _Translations$history$contextMenu$nl._(_root);
  @override
  late final _Translations$history$cherryPick$nl cherryPick =
      _Translations$history$cherryPick$nl._(_root);
  @override
  late final _Translations$history$revert$nl revert =
      _Translations$history$revert$nl._(_root);
  @override
  late final _Translations$history$reflog$nl reflog =
      _Translations$history$reflog$nl._(_root);
  @override
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'Die commit ligt dieper dan de ${n} geladen commit.',
        other: 'Die commit ligt dieper dan de ${n} geladen commits.',
      );
  @override
  String deleteTagFailed({required Object error}) =>
      'Tag verwijderen mislukt: ${error}';
  @override
  String get loadingTitle => 'Geschiedenis laden';
  @override
  String get loadingMessage => 'Recente commits lezen.';
  @override
  String get unavailableTitle => 'Geschiedenis niet beschikbaar';
  @override
  String get toggleWorldline => 'Wereldlijn omschakelen';
  @override
  String get pageTitle => 'Geschiedenis';
  @override
  String get viewingLast => 'Toont laatste';
  @override
  String get commitsUnit => 'commits';
  @override
  String get noCommitSelectedTitle => 'Geen commit geselecteerd';
  @override
  String get noCommitSelectedMessage =>
      'Kies een commit om de wijzigingen te inspecteren.';
  @override
  String get loadingCommitTitle => 'Commit laden';
  @override
  String get loadingCommitMessage => 'Commit-details lezen.';
  @override
  String get commitUnavailableTitle => 'Commit niet beschikbaar';
  @override
  String get couldNotLoadCommit => 'Commit kon niet worden geladen.';
  @override
  String get reflogDividerLabel => 'reflog';
  @override
  String get loadReflog => 'Reflog laden';
  @override
  String get createTag => 'Tag maken';
  @override
  String get newTagName => 'Nieuwe tag-naam';
  @override
  String newTagNameError({required Object error}) =>
      'Nieuwe tag-naam — ${error}';
  @override
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} bestand · alle wijzigingen',
        other: '${n} bestanden · alle wijzigingen',
      );
  @override
  String get allChangesLabel => 'alle wijzigingen';
  @override
  late final _Translations$history$rebase$nl rebase =
      _Translations$history$rebase$nl._(_root);
  @override
  late final _Translations$history$inFlight$nl inFlight =
      _Translations$history$inFlight$nl._(_root);
}

// Path: historySurgery
class _Translations$historySurgery$nl extends Translations$historySurgery$en {
  _Translations$historySurgery$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$historySurgery$chrome$nl chrome =
      _Translations$historySurgery$chrome$nl._(_root);
  @override
  late final _Translations$historySurgery$select$nl select =
      _Translations$historySurgery$select$nl._(_root);
  @override
  late final _Translations$historySurgery$understand$nl understand =
      _Translations$historySurgery$understand$nl._(_root);
  @override
  late final _Translations$historySurgery$confirm$nl confirm =
      _Translations$historySurgery$confirm$nl._(_root);
  @override
  late final _Translations$historySurgery$execute$nl execute =
      _Translations$historySurgery$execute$nl._(_root);
  @override
  late final _Translations$historySurgery$verify$nl verify =
      _Translations$historySurgery$verify$nl._(_root);
  @override
  late final _Translations$historySurgery$forcePush$nl forcePush =
      _Translations$historySurgery$forcePush$nl._(_root);
}

// Path: onboarding
class _Translations$onboarding$nl extends Translations$onboarding$en {
  _Translations$onboarding$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$nav$nl nav =
      _Translations$onboarding$nav$nl._(_root);
  @override
  late final _Translations$onboarding$naming$nl naming =
      _Translations$onboarding$naming$nl._(_root);
  @override
  late final _Translations$onboarding$theme$nl theme =
      _Translations$onboarding$theme$nl._(_root);
  @override
  late final _Translations$onboarding$repo$nl repo =
      _Translations$onboarding$repo$nl._(_root);
  @override
  late final _Translations$onboarding$preview$nl preview =
      _Translations$onboarding$preview$nl._(_root);
}

// Path: orrery
class _Translations$orrery$nl extends Translations$orrery$en {
  _Translations$orrery$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$orrery$header$nl header =
      _Translations$orrery$header$nl._(_root);
  @override
  late final _Translations$orrery$status$nl status =
      _Translations$orrery$status$nl._(_root);
  @override
  late final _Translations$orrery$legend$nl legend =
      _Translations$orrery$legend$nl._(_root);
  @override
  late final _Translations$orrery$node$nl node = _Translations$orrery$node$nl._(
    _root,
  );
  @override
  late final _Translations$orrery$milestone$nl milestone =
      _Translations$orrery$milestone$nl._(_root);
  @override
  late final _Translations$orrery$structure$nl structure =
      _Translations$orrery$structure$nl._(_root);
  @override
  late final _Translations$orrery$rail$nl rail = _Translations$orrery$rail$nl._(
    _root,
  );
  @override
  late final _Translations$orrery$selection$nl selection =
      _Translations$orrery$selection$nl._(_root);
  @override
  late final _Translations$orrery$findingKind$nl findingKind =
      _Translations$orrery$findingKind$nl._(_root);
  @override
  late final _Translations$orrery$findings$nl findings =
      _Translations$orrery$findings$nl._(_root);
  @override
  late final _Translations$orrery$anchor$nl anchor =
      _Translations$orrery$anchor$nl._(_root);
  @override
  late final _Translations$orrery$compare$nl compare =
      _Translations$orrery$compare$nl._(_root);
}

// Path: palette
class _Translations$palette$nl extends Translations$palette$en {
  _Translations$palette$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get active => 'actief';
  @override
  late final _Translations$palette$prefixes$nl prefixes =
      _Translations$palette$prefixes$nl._(_root);
  @override
  late final _Translations$palette$chips$nl chips =
      _Translations$palette$chips$nl._(_root);
  @override
  late final _Translations$palette$predictive$nl predictive =
      _Translations$palette$predictive$nl._(_root);
  @override
  late final _Translations$palette$topTouched$nl topTouched =
      _Translations$palette$topTouched$nl._(_root);
  @override
  late final _Translations$palette$coherence$nl coherence =
      _Translations$palette$coherence$nl._(_root);
  @override
  late final _Translations$palette$keystone$nl keystone =
      _Translations$palette$keystone$nl._(_root);
  @override
  late final _Translations$palette$repoSub$nl repoSub =
      _Translations$palette$repoSub$nl._(_root);
  @override
  late final _Translations$palette$desks$nl desks =
      _Translations$palette$desks$nl._(_root);
  @override
  late final _Translations$palette$actions$nl actions =
      _Translations$palette$actions$nl._(_root);
  @override
  late final _Translations$palette$tools$nl tools =
      _Translations$palette$tools$nl._(_root);
  @override
  late final _Translations$palette$gitCommands$nl gitCommands =
      _Translations$palette$gitCommands$nl._(_root);
  @override
  late final _Translations$palette$pr$nl pr = _Translations$palette$pr$nl._(
    _root,
  );
  @override
  late final _Translations$palette$ai$nl ai = _Translations$palette$ai$nl._(
    _root,
  );
  @override
  late final _Translations$palette$undo$nl undo =
      _Translations$palette$undo$nl._(_root);
  @override
  late final _Translations$palette$navigation$nl navigation =
      _Translations$palette$navigation$nl._(_root);
  @override
  late final _Translations$palette$settings$nl settings =
      _Translations$palette$settings$nl._(_root);
  @override
  late final _Translations$palette$info$nl info =
      _Translations$palette$info$nl._(_root);
  @override
  late final _Translations$palette$debug$nl debug =
      _Translations$palette$debug$nl._(_root);
  @override
  late final _Translations$palette$dev$nl dev = _Translations$palette$dev$nl._(
    _root,
  );
  @override
  late final _Translations$palette$historySurgery$nl historySurgery =
      _Translations$palette$historySurgery$nl._(_root);
  @override
  late final _Translations$palette$orrery$nl orrery =
      _Translations$palette$orrery$nl._(_root);
  @override
  late final _Translations$palette$command$nl command =
      _Translations$palette$command$nl._(_root);
  @override
  late final _Translations$palette$search$nl search =
      _Translations$palette$search$nl._(_root);
  @override
  late final _Translations$palette$wick$nl wick =
      _Translations$palette$wick$nl._(_root);
  @override
  late final _Translations$palette$gitCache$nl gitCache =
      _Translations$palette$gitCache$nl._(_root);
}

// Path: releaseNotes
class _Translations$releaseNotes$nl extends Translations$releaseNotes$en {
  _Translations$releaseNotes$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get versionFallback => 'dev';
  @override
  late final _Translations$releaseNotes$about$nl about =
      _Translations$releaseNotes$about$nl._(_root);
  @override
  late final _Translations$releaseNotes$legal$nl legal =
      _Translations$releaseNotes$legal$nl._(_root);
}

// Path: repoSummary
class _Translations$repoSummary$nl extends Translations$repoSummary$en {
  _Translations$repoSummary$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$repoSummary$backbone$nl backbone =
      _Translations$repoSummary$backbone$nl._(_root);
  @override
  late final _Translations$repoSummary$glance$nl glance =
      _Translations$repoSummary$glance$nl._(_root);
  @override
  late final _Translations$repoSummary$heading$nl heading =
      _Translations$repoSummary$heading$nl._(_root);
  @override
  String get historyStarvedCaveat =>
      'Rangschikking beperkt: de koppelingsgraaf had geen randen (verse kloon of te weinig commits). De bestandsvolgorde weerspiegelt grootte, niet structurele centraliteit.';
  @override
  late final _Translations$repoSummary$pitch$nl pitch =
      _Translations$repoSummary$pitch$nl._(_root);
  @override
  late final _Translations$repoSummary$region$nl region =
      _Translations$repoSummary$region$nl._(_root);
  @override
  late final _Translations$repoSummary$shape$nl shape =
      _Translations$repoSummary$shape$nl._(_root);
}

// Path: review
class _Translations$review$nl extends Translations$review$en {
  _Translations$review$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get unresolved => 'onopgelost';
  @override
  String get done => 'klaar';
  @override
  String get ack => 'genoteerd';
  @override
  String get reply => 'antwoorden';
  @override
  String get pleaseFix => 'graag fixen';
  @override
  String get draft => 'concept';
  @override
  String get engine => 'engine';
  @override
  String get moved => 'verplaatst';
  @override
  String get yourTurn => 'jouw beurt';
  @override
  String get drafts => 'concepten';
  @override
  String get publish => 'publiceren';
  @override
  String get discard => 'verwerpen';
  @override
  String get saveDraft => 'concept opslaan';
  @override
  String get cancel => 'annuleren';
  @override
  String get verdictApprove => 'goedkeuren';
  @override
  String get verdictRequestChanges => 'wijzigingen vragen';
  @override
  String get verdictComment => 'reageren';
  @override
  String get caughtUp => 'helemaal bij';
  @override
  String get sinceLastLook => 'sinds je laatste blik';
  @override
  String get fullDiff => 'volledige diff';
  @override
  String get commentHint => 'schrijf een reactie';
  @override
  String outdatedLastSeen({required Object round}) =>
      'verouderd · laatst gezien R${round}';
  @override
  String resolvedByFmt({required Object verb, required Object who}) =>
      '${verb} · ${who}';
  @override
  String waitingOnFmt({required Object who}) => 'wacht op ${who}';
  @override
  String roundChip({required Object round}) => 'R${round}';
  @override
  String filesSinceLastLook({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '1 bestand sinds je laatste blik',
        other: '${n} bestanden sinds je laatste blik',
      );
  @override
  String unresolvedCountFmt({required Object n}) => '${n} onopgelost';
  @override
  String draftCountFmt({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '1 concept',
        other: '${n} concepten',
      );
  @override
  String startReviewFailed({required Object error}) =>
      'Kon de review niet starten: ${error}';
  @override
  String get anchorUnavailable =>
      'Die regel kan niet worden verankerd — het bestand is te groot of niet beschikbaar.';
  @override
  String reviewActionFailed({required Object error}) =>
      'Reviewactie mislukt: ${error}';
  @override
  String get lensTooLarge =>
      'Die vergelijking is te groot om hier te tonen — we blijven op de volledige diff.';
  @override
  String get lensEmpty => 'Er is niets veranderd tussen deze snapshots.';
  @override
  String get reopen => 'heropenen';
  @override
  String get notBlocking => 'wacht niet op mij';
  @override
  String get markReviewed => 'gelezen';
  @override
  String newComments({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '1 nieuwe reactie',
        other: '${n} nieuwe reacties',
      );
  @override
  String get handTo => 'doorgeven aan';
  @override
  String get heading => 'REVIEW';
  @override
  String get identityNeeded => 'Stel een git-identiteit in om te reviewen';
  @override
  String get fileUnreadable =>
      'Dit bestand kan hier niet gelezen worden — te groot of niet aanwezig in deze ronde.';
}

// Path: settings
class _Translations$settings$nl extends Translations$settings$en {
  _Translations$settings$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$language$nl language =
      _Translations$settings$language$nl._(_root);
  @override
  late final _Translations$settings$sectionLabels$nl sectionLabels =
      _Translations$settings$sectionLabels$nl._(_root);
  @override
  late final _Translations$settings$errors$nl errors =
      _Translations$settings$errors$nl._(_root);
  @override
  late final _Translations$settings$promptStatus$nl promptStatus =
      _Translations$settings$promptStatus$nl._(_root);
  @override
  late final _Translations$settings$clearData$nl clearData =
      _Translations$settings$clearData$nl._(_root);
  @override
  List<String> get guardrailStageLabels => [
    'Los',
    'Gebalanceerd',
    'Streng',
    'Paranoïde',
  ];
  @override
  late final _Translations$settings$guardrailMacro$nl guardrailMacro =
      _Translations$settings$guardrailMacro$nl._(_root);
  @override
  late final _Translations$settings$guardrails$nl guardrails =
      _Translations$settings$guardrails$nl._(_root);
  @override
  late final _Translations$settings$appearance$nl appearance =
      _Translations$settings$appearance$nl._(_root);
  @override
  late final _Translations$settings$retention$nl retention =
      _Translations$settings$retention$nl._(_root);
  @override
  late final _Translations$settings$navigation$nl navigation =
      _Translations$settings$navigation$nl._(_root);
  @override
  late final _Translations$settings$behaviour$nl behaviour =
      _Translations$settings$behaviour$nl._(_root);
  @override
  late final _Translations$settings$retentionClear$nl retentionClear =
      _Translations$settings$retentionClear$nl._(_root);
  @override
  late final _Translations$settings$channels$nl channels =
      _Translations$settings$channels$nl._(_root);
  @override
  late final _Translations$settings$pollResult$nl pollResult =
      _Translations$settings$pollResult$nl._(_root);
  @override
  late final _Translations$settings$keybindingProfile$nl keybindingProfile =
      _Translations$settings$keybindingProfile$nl._(_root);
  @override
  late final _Translations$settings$apiKeys$nl apiKeys =
      _Translations$settings$apiKeys$nl._(_root);
  @override
  late final _Translations$settings$shortcuts$nl shortcuts =
      _Translations$settings$shortcuts$nl._(_root);
  @override
  late final _Translations$settings$toggles$nl toggles =
      _Translations$settings$toggles$nl._(_root);
  @override
  late final _Translations$settings$diffDiffability$nl diffDiffability =
      _Translations$settings$diffDiffability$nl._(_root);
  @override
  late final _Translations$settings$modelSlots$nl modelSlots =
      _Translations$settings$modelSlots$nl._(_root);
  @override
  late final _Translations$settings$modelPicker$nl modelPicker =
      _Translations$settings$modelPicker$nl._(_root);
  @override
  late final _Translations$settings$aiFeatures$nl aiFeatures =
      _Translations$settings$aiFeatures$nl._(_root);
  @override
  late final _Translations$settings$commitEditor$nl commitEditor =
      _Translations$settings$commitEditor$nl._(_root);
  @override
  late final _Translations$settings$review$nl review =
      _Translations$settings$review$nl._(_root);
  @override
  late final _Translations$settings$museHint$nl museHint =
      _Translations$settings$museHint$nl._(_root);
  @override
  late final _Translations$settings$museEditor$nl museEditor =
      _Translations$settings$museEditor$nl._(_root);
  @override
  late final _Translations$settings$museStage$nl museStage =
      _Translations$settings$museStage$nl._(_root);
  @override
  late final _Translations$settings$lensAxis$nl lensAxis =
      _Translations$settings$lensAxis$nl._(_root);
  @override
  late final _Translations$settings$logosLens$nl logosLens =
      _Translations$settings$logosLens$nl._(_root);
  @override
  late final _Translations$settings$sortGuide$nl sortGuide =
      _Translations$settings$sortGuide$nl._(_root);
  @override
  late final _Translations$settings$piggyback$nl piggyback =
      _Translations$settings$piggyback$nl._(_root);
  @override
  late final _Translations$settings$diffStage$nl diffStage =
      _Translations$settings$diffStage$nl._(_root);
  @override
  late final _Translations$settings$undoScope$nl undoScope =
      _Translations$settings$undoScope$nl._(_root);
  @override
  late final _Translations$settings$undoWindow$nl undoWindow =
      _Translations$settings$undoWindow$nl._(_root);
  @override
  late final _Translations$settings$guardrailPhrase$nl guardrailPhrase =
      _Translations$settings$guardrailPhrase$nl._(_root);
  @override
  late final _Translations$settings$reviewGuideHint$nl reviewGuideHint =
      _Translations$settings$reviewGuideHint$nl._(_root);
  @override
  late final _Translations$settings$commitFormat$nl commitFormat =
      _Translations$settings$commitFormat$nl._(_root);
  @override
  late final _Translations$settings$commitPreview$nl commitPreview =
      _Translations$settings$commitPreview$nl._(_root);
  @override
  late final _Translations$settings$externalTools$nl externalTools =
      _Translations$settings$externalTools$nl._(_root);
  @override
  late final _Translations$settings$apiUsage$nl apiUsage =
      _Translations$settings$apiUsage$nl._(_root);
  @override
  late final _Translations$settings$gitea$nl gitea =
      _Translations$settings$gitea$nl._(_root);
  @override
  late final _Translations$settings$wick$nl wick =
      _Translations$settings$wick$nl._(_root);
  @override
  late final _Translations$settings$integrations$nl integrations =
      _Translations$settings$integrations$nl._(_root);
  @override
  late final _Translations$settings$reduceMotion$nl reduceMotion =
      _Translations$settings$reduceMotion$nl._(_root);
  @override
  late final _Translations$settings$resetQuit$nl resetQuit =
      _Translations$settings$resetQuit$nl._(_root);
  @override
  late final _Translations$settings$diagnostics$nl diagnostics =
      _Translations$settings$diagnostics$nl._(_root);
  @override
  late final _Translations$settings$telemetry$nl telemetry =
      _Translations$settings$telemetry$nl._(_root);
  @override
  late final _Translations$settings$flowEngine$nl flowEngine =
      _Translations$settings$flowEngine$nl._(_root);
  @override
  late final _Translations$settings$museStrands$nl museStrands =
      _Translations$settings$museStrands$nl._(_root);
  @override
  late final _Translations$settings$cliPiggyback$nl cliPiggyback =
      _Translations$settings$cliPiggyback$nl._(_root);
  @override
  late final _Translations$settings$header$nl header =
      _Translations$settings$header$nl._(_root);
  @override
  late final _Translations$settings$diagnosticsPanel$nl diagnosticsPanel =
      _Translations$settings$diagnosticsPanel$nl._(_root);
  @override
  late final _Translations$settings$release$nl release =
      _Translations$settings$release$nl._(_root);
  @override
  late final _Translations$settings$providerStatus$nl providerStatus =
      _Translations$settings$providerStatus$nl._(_root);
  @override
  late final _Translations$settings$meridiem$nl meridiem =
      _Translations$settings$meridiem$nl._(_root);
  @override
  late final _Translations$settings$offenders$nl offenders =
      _Translations$settings$offenders$nl._(_root);
}

// Path: sync
class _Translations$sync$nl extends Translations$sync$en {
  _Translations$sync$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$actions$nl actions =
      _Translations$sync$actions$nl._(_root);
  @override
  late final _Translations$sync$panel$nl panel = _Translations$sync$panel$nl._(
    _root,
  );
  @override
  late final _Translations$sync$forcePush$nl forcePush =
      _Translations$sync$forcePush$nl._(_root);
}

// Path: xray
class _Translations$xray$nl extends Translations$xray$en {
  _Translations$xray$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$board$nl board = _Translations$xray$board$nl._(
    _root,
  );
  @override
  late final _Translations$xray$cadence$nl cadence =
      _Translations$xray$cadence$nl._(_root);
  @override
  late final _Translations$xray$cards$nl cards = _Translations$xray$cards$nl._(
    _root,
  );
  @override
  late final _Translations$xray$cardTitle$nl cardTitle =
      _Translations$xray$cardTitle$nl._(_root);
  @override
  late final _Translations$xray$grain$nl grain = _Translations$xray$grain$nl._(
    _root,
  );
  @override
  late final _Translations$xray$header$nl header =
      _Translations$xray$header$nl._(_root);
  @override
  late final _Translations$xray$hotspot$nl hotspot =
      _Translations$xray$hotspot$nl._(_root);
  @override
  late final _Translations$xray$inspector$nl inspector =
      _Translations$xray$inspector$nl._(_root);
  @override
  late final _Translations$xray$loadingCard$nl loadingCard =
      _Translations$xray$loadingCard$nl._(_root);
  @override
  late final _Translations$xray$metabolism$nl metabolism =
      _Translations$xray$metabolism$nl._(_root);
  @override
  late final _Translations$xray$multi$nl multi = _Translations$xray$multi$nl._(
    _root,
  );
  @override
  late final _Translations$xray$recency$nl recency =
      _Translations$xray$recency$nl._(_root);
  @override
  late final _Translations$xray$rings$nl rings = _Translations$xray$rings$nl._(
    _root,
  );
  @override
  late final _Translations$xray$stats$nl stats = _Translations$xray$stats$nl._(
    _root,
  );
  @override
  late final _Translations$xray$stratumLabel$nl stratumLabel =
      _Translations$xray$stratumLabel$nl._(_root);
  @override
  late final _Translations$xray$summary$nl summary =
      _Translations$xray$summary$nl._(_root);
  @override
  late final _Translations$xray$tabs$nl tabs = _Translations$xray$tabs$nl._(
    _root,
  );
  @override
  late final _Translations$xray$trajectory$nl trajectory =
      _Translations$xray$trajectory$nl._(_root);
  @override
  late final _Translations$xray$verdict$nl verdict =
      _Translations$xray$verdict$nl._(_root);
}

// Path: app.cheatsheet
class _Translations$app$cheatsheet$nl extends Translations$app$cheatsheet$en {
  _Translations$app$cheatsheet$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Toetsenbord';
  @override
  String get sectionNavigate => 'navigeren';
  @override
  String get sectionStaging => 'staging';
  @override
  String get sectionBranchesPrs => 'branches & PRs';
  @override
  String get changes => 'Wijzigingen';
  @override
  String get history => 'Geschiedenis';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Wisselen (altijd)';
  @override
  String get commandPalette => 'Opdrachtenpalet';
  @override
  String get elevatedPalette => 'Verhoogd palet';
  @override
  String get dismiss => 'Sluiten';
  @override
  String get refresh => 'Verversen';
  @override
  String get nextPrevChange => 'Volgende / vorige wijziging';
  @override
  String get toggleLine => 'Regel omschakelen';
  @override
  String get toggleHunk => 'Hunk omschakelen';
  @override
  String get toggleFile => 'Bestand omschakelen';
  @override
  String get pinContext => 'Context vastzetten';
  @override
  String get commit => 'Commit';
  @override
  String get acceptAiHint => 'AI-hint accepteren';
  @override
  String get undo => 'Ongedaan maken';
  @override
  String get navigate => 'Navigeren';
  @override
  String get expand => 'Uitklappen';
  @override
  String get checkoutPr => 'PR uitchecken';
  @override
  String get approve => 'Goedkeuren';
  @override
  String get requestChanges => 'Wijzigingen vragen';
  @override
  String profileSwitchHint({required Object profile}) =>
      'Profiel ${profile} · wisselen in Instellingen';
}

// Path: backend.ops
class _Translations$backend$ops$nl extends Translations$backend$ops$en {
  _Translations$backend$ops$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'Merge';
  @override
  String get pull => 'Pull';
  @override
  String get apply => 'Toepassen';
  @override
  String get switchOp => 'Wisselen';
  @override
  String get sync => 'Sync';
}

// Path: backend.mergeOutcome
class _Translations$backend$mergeOutcome$nl
    extends Translations$backend$mergeOutcome$en {
  _Translations$backend$mergeOutcome$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String cancelled({required Object op}) => '${op} geannuleerd.';
  @override
  String complete({required Object op}) => '${op} voltooid.';
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'Nog ${n} conflict — los het op de Wijzigingen-pagina op.',
        other: 'Nog ${n} conflicten — los ze op de Wijzigingen-pagina op.',
      );
  @override
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} conflict opgelost.',
        other: '${n} conflicten opgelost.',
      );
  @override
  String uncommittedEdits({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
    n,
    one: '${n} bestand heeft niet-gecommitte wijzigingen — commit ze eerst.',
    other:
        '${n} bestanden hebben niet-gecommitte wijzigingen — commit ze eerst.',
  );
}

// Path: changes.usage
class _Translations$changes$usage$nl extends Translations$changes$usage$en {
  _Translations$changes$usage$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String caption({required Object input, required Object output}) =>
      '${input} in · ${output} uit';
  @override
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '${fresh} in · ${cached} gecacht · ${out} uit';
  @override
  String get inWord => 'in';
  @override
  String get cachedWord => 'gecacht';
  @override
  String get outWord => 'uit';
  @override
  String tipIn({required Object value}) => '${value}  in';
  @override
  String tipCacheRead({required Object value}) => '${value}  cache lezen';
  @override
  String tipCacheWrite({required Object value}) => '${value}  cache schrijven';
  @override
  String tipOut({required Object value}) => '${value}  uit';
  @override
  String tipReasoning({required Object value}) => '${value}  redenering';
  @override
  String tipWallClock({required Object value}) => '${value}s  kloktijd';
}

// Path: changes.tabs
class _Translations$changes$tabs$nl extends Translations$changes$tabs$en {
  _Translations$changes$tabs$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get defaultLabel => 'Wijzigingen';
  @override
  String get empty => 'Leeg';
}

// Path: changes.tabStrip
class _Translations$changes$tabStrip$nl
    extends Translations$changes$tabStrip$en {
  _Translations$changes$tabStrip$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get newDiffTab => 'Nieuw diff-tabblad';
}

// Path: changes.select
class _Translations$changes$select$nl extends Translations$changes$select$en {
  _Translations$changes$select$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get selectAll => 'Alles selecteren';
  @override
  String get deselectAll => 'Alles deselecteren';
}

// Path: changes.constellationToggle
class _Translations$changes$constellationToggle$nl
    extends Translations$changes$constellationToggle$en {
  _Translations$changes$constellationToggle$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get backToList => 'terug naar lijst';
  @override
  String get atlas => 'atlas, bekijk commit-kandidaten';
}

// Path: changes.nudgeChip
class _Translations$changes$nudgeChip$nl
    extends Translations$changes$nudgeChip$en {
  _Translations$changes$nudgeChip$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\nkoppelt met ${anchor} · ${pct}%${receipts}';
}

// Path: changes.minimap
class _Translations$changes$minimap$nl extends Translations$changes$minimap$en {
  _Translations$changes$minimap$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get roleNew => 'nieuw';
  @override
  String get roleBridge => 'brug';
  @override
  String get roleHub => 'hub';
  @override
  String get roleLeaf => 'blad';
  @override
  String get roleConnected => 'verbonden';
  @override
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';
  @override
  String changesWith({required Object name}) => 'wijzigt met ${name}';
  @override
  String get newFile => 'nieuw bestand';
  @override
  String nearOtherChanges({required Object count, required Object dir}) =>
      'nabij ${count} andere wijzigingen in ${dir}';
  @override
  String usuallyChangesWithFile({required Object name}) =>
      '${name} wijzigt meestal met dit bestand';
}

// Path: changes.tagInput
class _Translations$changes$tagInput$nl
    extends Translations$changes$tagInput$en {
  _Translations$changes$tagInput$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get hint => 'tag...';
}

// Path: changes.composer
class _Translations$changes$composer$nl
    extends Translations$changes$composer$en {
  _Translations$changes$composer$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get hintPlaceholder => 'commit-bericht...';
  @override
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class _Translations$changes$commit$nl extends Translations$changes$commit$en {
  _Translations$changes$commit$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get primaryCommitChanges => 'Wijzigingen committen';
  @override
  String get primaryCommitChangesDetail =>
      'Detached HEAD: lokaal committen zonder sync.';
  @override
  String get primaryPublish => 'Committen & publiceren';
  @override
  String get primaryPublishDetail =>
      'Maak de commit en publiceer deze branch in één stap.';
  @override
  String get primarySync => 'Committen & syncen';
  @override
  String get primarySyncDetail =>
      'Maak de commit, verzoen dan de branch en verstuur hem.';
  @override
  String get primaryPush => 'Committen & pushen';
  @override
  String get primaryPushDetail => 'Maak de commit en push hem meteen.';
  @override
  String get amendLast => 'Laatste commit amenden';
  @override
  String amendAnd({required Object action}) => 'Amenden & ${action}';
  @override
  String get chooseFile => 'Kies minstens één bestand voor de volgende commit.';
  @override
  String get writeMessage => 'Schrijf eerst een commit-bericht.';
  @override
  String get committing => 'Committen';
  @override
  String get committingSync => 'Committen en syncen';
  @override
  String get committed => 'Gecommit.';
  @override
  String get undoFailed => 'Ongedaan maken mislukt.';
  @override
  String get working => 'Bezig…';
  @override
  String get commitOnly => 'Alleen committen';
  @override
  String get noRuntimeModels =>
      'Geen tijdens runtime ontdekte modellen beschikbaar voor commit-berichten.';
  @override
  String restoreFailedRetry({required Object err}) =>
      '${err}\nDe staging van de uitgesloten bestanden kon niet worden hersteld; controleer de index voordat je het opnieuw probeert.';
  @override
  String committedSummary({required Object summary, required Object hash}) =>
      '${summary} gecommit (${hash}).';
  @override
  String get restoreFailedSync =>
      'De selecties van de uitgesloten bestanden konden niet opnieuw worden gestaged; sync overgeslagen. Controleer de index voordat je synct.';
  @override
  String get noModelLabel => 'Geen model';
  @override
  String get chooseBeforeGenerate =>
      'Kies minstens één bestand voordat je genereert.';
  @override
  String get aiUnavailable => 'Commit-bericht-AI is nog niet beschikbaar.';
  @override
  String get generateFailed => 'Genereren mislukt.';
  @override
  String get stageFailed => 'Bestanden stagen mislukt.';
  @override
  String get commitFailed => 'Commit mislukt.';
  @override
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => '${summary} gecommit (${hash}) en ${operation} uitgevoerd.';
  @override
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
    n,
    one: '${summary} gecommit (${hash}); ${n} conflict opgelost.',
    other: '${summary} gecommit (${hash}); ${n} conflicten opgelost.',
  );
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'Nog ${n} conflict op te lossen.',
        other: 'Nog ${n} conflicten op te lossen.',
      );
  @override
  String syncBlocked({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
    n,
    one:
        'Commit geslaagd, maar sync werd geblokkeerd door ${n} niet-gecommit bestand.',
    other:
        'Commit geslaagd, maar sync werd geblokkeerd door ${n} niet-gecommitte bestanden.',
  );
  @override
  String syncStalled({required Object message}) =>
      'Commit geslaagd, maar sync stokte: ${message}';
  @override
  String syncFailed({required Object message}) =>
      'Commit geslaagd, maar sync mislukt: ${message}';
}

// Path: changes.rebase
class _Translations$changes$rebase$nl extends Translations$changes$rebase$en {
  _Translations$changes$rebase$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get continueFailed => 'De rebase kon niet worden voortgezet.';
}

// Path: changes.editor
class _Translations$changes$editor$nl extends Translations$changes$editor$en {
  _Translations$changes$editor$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get closeBarrier => 'Editor sluiten';
}

// Path: changes.editorTitles
class _Translations$changes$editorTitles$nl
    extends Translations$changes$editorTitles$en {
  _Translations$changes$editorTitles$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  List<String> get any => [
    'beste git-log',
    'vergit me, hemel, want ik heb gezondigd…',
    'geef dit moment een naam',
    'kwek maar door',
    'spreek!',
    'je moeder was een bungelende referentie en je vader rook naar puntkomma\'s',
  ];
  @override
  List<String> get short => [
    'oh?',
    'hallo daar:)',
    'trouwens:',
    'een paar woorden',
    'de nette versie',
    'laat een briefje achter',
    'je zei..?',
    'kom op, eruit ermee',
  ];
  @override
  List<String> get mid => [
    'voor de goede orde',
    'vertel het de toekomstige jij',
    'maar eerst?',
    'hoe het ging',
    'in je eigen woorden',
    'je deed WAT?',
    'genoteerd',
    'je hebt mijn aandacht',
  ];
  @override
  List<String> get long => [
    'je dromen, graag',
    'zeg eens iets aardigs',
    '... en toen zei ik:',
    'het nageslacht wacht',
    'meer schrijven laat je bugs verdwijnen',
    'oh wauw',
    'de heilige teksten',
  ];
}

// Path: changes.askHint
class _Translations$changes$askHint$nl extends Translations$changes$askHint$en {
  _Translations$changes$askHint$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String round({required Object n}) =>
      'ronde ${n} — verfijn of voeg context toe.';
  @override
  String get symptom => 'beschrijf het symptoom.';
  @override
  String get broken => 'wat is er stuk?';
  @override
  String get bug => 'beschrijf de bug.';
  @override
  String get error => 'plak de foutmelding.';
}

// Path: changes.fileMenu
class _Translations$changes$fileMenu$nl
    extends Translations$changes$fileMenu$en {
  _Translations$changes$fileMenu$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get ripple => 'Rimpel';
  @override
  String get includeCoChanges => 'Co-changes meenemen';
  @override
  String deleteFile({required Object name}) => '${name} verwijderen…';
  @override
  String discardChangesTo({required Object name}) =>
      'Wijzigingen aan ${name} verwerpen…';
  @override
  String get ignore => 'Negeren';
  @override
  String get diffTabFromSelection => 'Diff-tabblad uit selectie';
  @override
  String addSelectedToTab({required Object name}) =>
      'Selectie toevoegen aan ${name}';
  @override
  String diffTabFromFile({required Object name}) => 'Diff-tabblad uit ${name}';
  @override
  String addFileToTab({required Object file, required Object tab}) =>
      '${file} toevoegen aan ${tab}';
  @override
  String get copyFilePath => 'Bestandspad kopiëren';
  @override
  String get showInExplorer => 'Tonen in Verkenner';
}

// Path: changes.multiFileMenu
class _Translations$changes$multiFileMenu$nl
    extends Translations$changes$multiFileMenu$en {
  _Translations$changes$multiFileMenu$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get cohesionTight => 'strak gekoppeld';
  @override
  String get cohesionLoose => 'los verwant';
  @override
  String get cohesionScattered => 'structureel verspreid';
  @override
  String get clusterOne => 'alles in één cluster';
  @override
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      'beslaat ${count} clusters (${parts} bestanden)';
  @override
  String clusterSpans({required Object count}) => 'beslaat ${count} clusters';
  @override
  String roleLine({required Object count, required Object cohesion}) =>
      '${count} bestanden · ${cohesion}';
  @override
  String usuallyChangesWithGroup({required Object file}) =>
      '${file} wijzigt meestal met deze groep';
  @override
  String get splitToNewTab => 'Afsplitsen naar nieuw tabblad';
  @override
  String copyPaths({required Object count}) => '${count} paden kopiëren';
}

// Path: changes.ignoreMenu
class _Translations$changes$ignoreMenu$nl
    extends Translations$changes$ignoreMenu$en {
  _Translations$changes$ignoreMenu$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String extension({required Object ext}) => '.${ext}-extensie';
  @override
  String allSelected({required Object count}) => 'Alle ${count} geselecteerd';
  @override
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'Koppelt met ${n} meegenomen bestand',
        other: 'Koppelt met ${n} meegenomen bestanden',
      );
  @override
  String get updateFailed => '.gitignore kon niet worden bijgewerkt.';
}

// Path: changes.discard
class _Translations$changes$discard$nl extends Translations$changes$discard$en {
  _Translations$changes$discard$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String deleteTitle({required Object name}) => '${name} verwijderen?';
  @override
  String discardTitle({required Object name}) =>
      'Wijzigingen aan ${name} verwerpen?';
  @override
  String deleteBody({required Object path}) =>
      '${path} wordt van schijf verwijderd. Dit kan niet vanuit de app ongedaan worden gemaakt.';
  @override
  String discardBody({required Object path}) =>
      'Alle wijzigingen aan ${path} worden teruggezet naar hun staat in HEAD. Dit kan niet ongedaan worden gemaakt.';
  @override
  String get discard => 'Verwerpen';
  @override
  String deletingFile({required Object name}) => '${name} verwijderen';
  @override
  String discardingFile({required Object name}) => '${name} verwerpen';
  @override
  String get discardFailed => 'Wijzigingen verwerpen mislukt.';
  @override
  String discardManyTitle({required Object count}) =>
      'Wijzigingen aan ${count} bestanden verwerpen?';
  @override
  String get discardManyBody =>
      'Getrackte bestanden worden teruggezet naar hun staat in HEAD; ongetrackte bestanden worden van schijf verwijderd. Dit kan niet ongedaan worden gemaakt.';
  @override
  String discardManyConfirm({required Object count}) => '${count} verwerpen';
  @override
  String discardingManyFiles({required Object count}) =>
      '${count} bestanden verwerpen';
  @override
  String failedOpenExplorer({required Object error}) =>
      'Bestandsverkenner openen mislukt: ${error}';
  @override
  String get someFailed => 'Sommige verwerpingen zijn mislukt.';
}

// Path: changes.snack
class _Translations$changes$snack$nl extends Translations$changes$snack$en {
  _Translations$changes$snack$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get sameWorktree => 'Zelfde worktree — niets om te dumpen.';
  @override
  String diffFailed({required Object error}) => 'Diff mislukt: ${error}';
  @override
  String get deskEmpty => 'Desk heeft niets voor op je — lege dump.';
  @override
  String sourceDesk({required Object label}) => 'desk ${label}';
  @override
  String shelfReadFailed({required Object error}) =>
      'Berging lezen mislukt: ${error}';
  @override
  String get shelfEmpty => 'Lege berging — niets om te dumpen.';
  @override
  String sourceShelf({required Object label}) => 'berging ${label}';
  @override
  String noModelConfigured({required Object label}) =>
      'Geen model geconfigureerd voor "${label}".';
  @override
  String fetchFailed({required Object error}) => 'Fetch mislukt: ${error}';
}

// Path: changes.trace
class _Translations$changes$trace$nl extends Translations$changes$trace$en {
  _Translations$changes$trace$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Verificatie-trace';
  @override
  String get draftReview => 'Concept-review';
}

// Path: changes.cleanTree
class _Translations$changes$cleanTree$nl
    extends Translations$changes$cleanTree$en {
  _Translations$changes$cleanTree$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Werkboom schoon';
  @override
  String get subtitle =>
      'Geen gestagede of ongestagede wijzigingen gedetecteerd.';
  @override
  String get noUpstream => '  ·  geen upstream';
  @override
  String get ahead => ' voor';
  @override
  String get behind => ' achter';
  @override
  String get refreshing => 'Verversen...';
  @override
  String get refresh => 'Verversen';
  @override
  String get check => 'check';
  @override
  String get checkTooltip => 'Fetch en lokale verversing.';
  @override
  String get sync => '& sync';
}

// Path: changes.guardrail
class _Translations$changes$guardrail$nl
    extends Translations$changes$guardrail$en {
  _Translations$changes$guardrail$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'Los';
  @override
  String get balanced => 'Gebalanceerd';
  @override
  String get strict => 'Streng';
  @override
  String get paranoid => 'Paranoïde';
}

// Path: changes.dropHint
class _Translations$changes$dropHint$nl
    extends Translations$changes$dropHint$en {
  _Translations$changes$dropHint$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get fromShelf =>
      'sleep om wijzigingen uit deze berging hierheen te halen';
  @override
  String get fromDesk => 'sleep om wijzigingen van deze desk hierheen te halen';
}

// Path: changes.diffEmpty
class _Translations$changes$diffEmpty$nl
    extends Translations$changes$diffEmpty$en {
  _Translations$changes$diffEmpty$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Geen bestand geselecteerd';
  @override
  String get message => 'Kies een gewijzigd bestand om de diff te inspecteren.';
}

// Path: changes.shelvePill
class _Translations$changes$shelvePill$nl
    extends Translations$changes$shelvePill$en {
  _Translations$changes$shelvePill$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String shelveN({required Object count}) => '↓ ${count} opbergen';
  @override
  String get shelve => '↓ opbergen';
  @override
  String shelvedCount({required Object count, required Object glyph}) =>
      '${count} opgeborgen ${glyph}';
}

// Path: changes.stashAction
class _Translations$changes$stashAction$nl
    extends Translations$changes$stashAction$en {
  _Translations$changes$stashAction$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get pickUp => 'oppakken';
  @override
  String get peek => 'gluren';
  @override
  String get toss => 'weggooien';
}

// Path: changes.stashContents
class _Translations$changes$stashContents$nl
    extends Translations$changes$stashContents$en {
  _Translations$changes$stashContents$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get reading => 'berging lezen…';
  @override
  String get empty => 'lege berging';
}

// Path: changes.stashFile
class _Translations$changes$stashFile$nl
    extends Translations$changes$stashFile$en {
  _Translations$changes$stashFile$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get binary => 'bin';
}

// Path: changes.fileRow
class _Translations$changes$fileRow$nl extends Translations$changes$fileRow$en {
  _Translations$changes$fileRow$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get stagedLinesOnly => 'commit alleen gestagede regels';
  @override
  String get doubleClickToggle => 'dubbelklik: hele groep omschakelen';
  @override
  String get repoRoot => 'Repository-root';
}

// Path: changes.resolveStrip
class _Translations$changes$resolveStrip$nl
    extends Translations$changes$resolveStrip$en {
  _Translations$changes$resolveStrip$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} bestand lezen · oplossing opstellen…',
        other: '${n} bestanden lezen · oplossing opstellen…',
      );
  @override
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} conflict in ${files}',
        other: '${n} conflicten in ${files}',
      );
  @override
  String get resolve => 'Oplossen';
  @override
  String get orWith => 'OF MET';
  @override
  String resolveWith({required Object label}) => 'oplossen met ${label}';
  @override
  String resolveWithModel({required Object label, required Object model}) =>
      'oplossen met ${label}  ·  ${model}';
  @override
  String get resolving => 'oplossen…';
  @override
  String resolveWithGlyph({required Object label}) =>
      '↵  oplossen met ${label}';
  @override
  String get orWithAnother => 'of met een ander model';
}

// Path: changes.badge
class _Translations$changes$badge$nl extends Translations$changes$badge$en {
  _Translations$changes$badge$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get stagedEdit => 'Gestagede wijziging';
  @override
  String get edited => 'Bewerkt';
  @override
  String get stagedAdd => 'Gestagede toevoeging';
  @override
  String get added => 'Toegevoegd';
  @override
  String get stagedDelete => 'Gestagede verwijdering';
  @override
  String get deleted => 'Verwijderd';
  @override
  String get stagedRename => 'Gestagede hernoeming';
  @override
  String get renamed => 'Hernoemd';
  @override
  String get stagedCopy => 'Gestagede kopie';
  @override
  String get copied => 'Gekopieerd';
  @override
  String get conflict => 'Conflict';
  @override
  String get stagedTypeChange => 'Gestagede typewijziging';
  @override
  String get typeChanged => 'Type gewijzigd';
  @override
  String get untracked => 'Ongetrackt';
}

// Path: changes.review
class _Translations$changes$review$nl extends Translations$changes$review$en {
  _Translations$changes$review$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Code-review';
  @override
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} meegenomen bestand',
        other: '${n} meegenomen bestanden',
      );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} hunk',
        other: '${n} hunks',
      );
  @override
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';
  @override
  String get unavailable => 'Review niet beschikbaar';
  @override
  String get backToDiff => 'Terug naar diff';
  @override
  String get verified => 'Geverifieerd';
  @override
  String get draftOnly => 'Alleen concept';
  @override
  String get runAgain => 'Opnieuw uitvoeren';
  @override
  String draftShownBelow({required Object error}) =>
      '${error} De concept-review wordt hieronder getoond.';
  @override
  String get hideTrace => 'Trace verbergen';
  @override
  String get showTrace => 'Trace tonen';
  @override
  String get showVerificationTrace => 'Verificatie-trace tonen';
  @override
  String get whyLanded => 'Waarom deze review hier landde';
  @override
  String get noFindings => 'Geen bevindingen';
  @override
  String get findings => 'Bevindingen';
  @override
  String get noEvidenceIssues =>
      'Voor deze commit-scope zijn geen door bewijs onderbouwde problemen aan het licht gekomen.';
  @override
  String get observations => 'Observaties';
  @override
  String get chooseBeforeReview =>
      'Kies minstens één bestand voordat je reviewt.';
  @override
  String get aiUnavailable => 'Review-AI is nog niet beschikbaar.';
  @override
  String get failed => 'Review mislukt.';
  @override
  String get noRuntimeModels =>
      'Geen tijdens runtime ontdekte modellen beschikbaar voor commit-review.';
}

// Path: changes.commitBtn
class _Translations$changes$commitBtn$nl
    extends Translations$changes$commitBtn$en {
  _Translations$changes$commitBtn$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String switchTo({required Object label}) => 'Wisselen naar: ${label}\n';
}

// Path: changes.shapeBtn
class _Translations$changes$shapeBtn$nl
    extends Translations$changes$shapeBtn$en {
  _Translations$changes$shapeBtn$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String askingWith({required Object cat}) => 'vragen met ${cat}…';
  @override
  String askWith({required Object cat}) => 'vragen met ${cat}';
  @override
  String get noModel => 'geen AI-model geconfigureerd';
  @override
  String nextTooltip({required Object cat}) =>
      'volgende: ${cat}  ·  shift-klik voor vorige';
  @override
  String get onlyOne => 'slechts één AI-categorie geconfigureerd';
}

// Path: changes.dejaVu
class _Translations$changes$dejaVu$nl extends Translations$changes$dejaVu$en {
  _Translations$changes$dejaVu$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required num n,
    required Object pct,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
    n,
    one:
        '${pct}% déjà vu — ${n} spookrand uit verworpen tijdlijnen raakt deze diff',
    other:
        '${pct}% déjà vu — ${n} spookranden uit verworpen tijdlijnen raken deze diff',
  );
  @override
  String get label => 'déjà vu';
}

// Path: changes.identity
class _Translations$changes$identity$nl
    extends Translations$changes$identity$en {
  _Translations$changes$identity$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'geen commit-identiteit geconfigureerd';
  @override
  String asName({required Object name}) => 'als ${name}';
  @override
  String asNameEmail({required Object name, required Object email}) =>
      'als ${name} <${email}>';
  @override
  String asNameSpace({required Object name}) => 'als ${name} ';
  @override
  String emailAngle({required Object email}) => '<${email}>';
  @override
  String get firstCommit => '\neerste commit in deze repo';
  @override
  String get newToRepo => '\nnieuw in deze repo';
}

// Path: changes.staleScope
class _Translations$changes$staleScope$nl
    extends Translations$changes$staleScope$en {
  _Translations$changes$staleScope$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get message => 'selectie is gewijzigd sinds dit draaide';
  @override
  String get rerun => 'opnieuw uitvoeren';
}

// Path: changes.finding
class _Translations$changes$finding$nl extends Translations$changes$finding$en {
  _Translations$changes$finding$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get openDiff => 'Diff openen';
  @override
  String get recorded => 'vastgelegd';
  @override
  String get dismiss => 'Sluiten';
}

// Path: changes.muse
class _Translations$changes$muse$nl extends Translations$changes$muse$en {
  _Translations$changes$muse$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Muse';
  @override
  String get youPulledThis => 'dit heb je getrokken';
  @override
  String fromIdea({required Object text}) => 'uit idee: "${text}"';
  @override
  String get foothold => 'houvast — ';
  @override
  String get brainstormSpew => 'brainstorm-spui';
  @override
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';
  @override
  String copyN({required Object count}) => '${count} kopiëren';
  @override
  String get clear => 'Wissen';
  @override
  String get chooseBeforeMuse =>
      'Kies minstens één bestand voordat je de muse aanroept.';
  @override
  String get aiUnavailable => 'Muse-AI is nog niet beschikbaar.';
  @override
  String get failed => 'Muse mislukt.';
  @override
  String get noRuntimeModels =>
      'Geen tijdens runtime ontdekte modellen beschikbaar voor de muse.';
  @override
  String get needsModel =>
      'De muse heeft minstens één geconfigureerd model nodig.';
  @override
  String get dreaming => 'de muse droomt...';
}

// Path: changes.debug
class _Translations$changes$debug$nl extends Translations$changes$debug$en {
  _Translations$changes$debug$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Debug';
  @override
  String round({required Object n}) => '· ronde ${n}';
  @override
  String get clear => 'wissen';
  @override
  String get close => 'sluiten';
  @override
  String get analyzing => 'symptoom analyseren…';
  @override
  String get describeSymptom => 'beschrijf een symptoom, druk dan op debug.';
  @override
  String get evidenceFor => 'voor';
  @override
  String get evidenceAgainst => 'maar';
  @override
  String get narrowDown => 'wat zou helpen om het af te bakenen:';
  @override
  String get failed => 'Debug mislukt.';
  @override
  String get refinementFailed => 'Debug-verfijning mislukt.';
}

// Path: changes.includeSummary
class _Translations$changes$includeSummary$nl
    extends Translations$changes$includeSummary$en {
  _Translations$changes$includeSummary$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'Geen';
  @override
  String stagedSuffix({required Object count}) => ' · ${count} gestaged';
  @override
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'Alle ${n} bestand${staged}',
        other: 'Alle ${n} bestanden${staged}',
      );
  @override
  String partial({
    required Object count,
    required Object n,
    required Object staged,
  }) => '${count} van ${n}${staged}';
  @override
  String shortAll({required Object n, required Object staged}) =>
      'Alle ${n}${staged}';
}

// Path: changes.status
class _Translations$changes$status$nl extends Translations$changes$status$en {
  _Translations$changes$status$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get unavailableTitle => 'Repository-status niet beschikbaar';
  @override
  String get loadingTitle => 'Repository-status laden';
  @override
  String get loadingMessage => 'De werkboom lezen.';
}

// Path: changes.stash
class _Translations$changes$stash$nl extends Translations$changes$stash$en {
  _Translations$changes$stash$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get appliedWithConflicts =>
      'Stash toegepast met conflicten — los ze op de Wijzigingen-pagina op (het stash-item is bewaard).';
  @override
  String get couldNotPop => 'Stash kon niet worden gepopt.';
  @override
  String get listChanged =>
      'De stash-lijst is gewijzigd; drop overgeslagen. Probeer opnieuw.';
  @override
  String get droppingStash => 'Stash droppen';
}

// Path: changes.tooltips
class _Translations$changes$tooltips$nl
    extends Translations$changes$tooltips$en {
  _Translations$changes$tooltips$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get commitGenerating => 'commit-bericht genereren...';
  @override
  String get commitPreparing => 'commit-bericht voorbereiden...';
  @override
  String get commitSelectFile =>
      'kies minstens één bestand om een commit-bericht te genereren.';
  @override
  String get commitConfigure =>
      'commit-bericht configureren in Instellingen > Gedragsdynamiek > Commit-berichten.';
  @override
  String get fastFallback => 'snel';
  @override
  String commitGenerateWith({required Object label}) =>
      'commit-bericht genereren met model ${label}';
  @override
  String get museConsulting => 'de muse raadplegen...';
  @override
  String get showMuse => 'muse tonen';
  @override
  String get museSelectFile => 'kies minstens één bestand voor de muse.';
  @override
  String get showMuseError => 'muse-fout tonen';
  @override
  String get museAsk => 'vraag de muse om richting';
  @override
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => 'vraag de muse om richting\n${brainstorm} → ${synthesis}';
  @override
  String get qualityFallback => 'kwaliteit';
  @override
  String get reviewing => 'reviewen...';
  @override
  String get showReview => 'review tonen';
  @override
  String get reviewPreparing => 'commit-review voorbereiden...';
  @override
  String get reviewSelectFile => 'kies minstens één bestand om te reviewen.';
  @override
  String get reviewConfigure => 'review-AI configureren in instellingen.';
  @override
  String get viewingReview => 'review bekijken';
  @override
  String reviewWith({required Object guardrail, required Object label}) =>
      '${guardrail}-review met model ${label}';
}

// Path: changes.mergeEditor
class _Translations$changes$mergeEditor$nl
    extends Translations$changes$mergeEditor$en {
  _Translations$changes$mergeEditor$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get resolutionYours => 'van jou';
  @override
  String get resolutionTheirs => 'van hun';
  @override
  String get resolutionCustom => 'eigen';
  @override
  String get keepBoth => 'beide behouden';
  @override
  late final _Translations$changes$mergeEditor$trust$nl trust =
      _Translations$changes$mergeEditor$trust$nl._(_root);
  @override
  String get allResolved => 'alles opgelost';
  @override
  String get resolveEasy => 'makkelijke conflicten oplossen';
  @override
  String get base => 'basis';
  @override
  String get cancel => 'annuleren';
  @override
  String get save => 'opslaan';
  @override
  String get complete => 'afronden';
  @override
  String get nextFile => 'volgend bestand';
  @override
  String get edit => 'bewerken';
  @override
  String get auto => 'auto';
  @override
  String get undo => 'ongedaan maken';
  @override
  late final _Translations$changes$mergeEditor$keyHints$nl keyHints =
      _Translations$changes$mergeEditor$keyHints$nl._(_root);
  @override
  String get favoredTooltip => 'structureel bevoordeeld door koppelingsanalyse';
  @override
  String get newOnBothSides => '(nieuw aan beide kanten)';
  @override
  String writeFailed({required Object error}) =>
      'Opgeloste bestanden schrijven mislukt: ${error}';
  @override
  String neighborsCoChanged({required Object changed, required Object total}) =>
      '${changed}/${total} buren mee-gewijzigd';
  @override
  String integrity({required Object pct}) => 'integriteit ${pct}%';
  @override
  String reviewer({required Object name}) => 'reviewer: ${name}';
}

// Path: changes.conflictResolution
class _Translations$changes$conflictResolution$nl
    extends Translations$changes$conflictResolution$en {
  _Translations$changes$conflictResolution$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String noModelConfigured({required Object category}) =>
      'Geen model geconfigureerd voor "${category}". Stel er een in bij Instellingen → AI.';
  @override
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} gevoelig bestand overgeslagen — los het handmatig op.',
        other: '${n} gevoelige bestanden overgeslagen — los ze handmatig op.',
      );
  @override
  String get couldNotReadFiles =>
      'Er konden geen conflictbestanden worden gelezen.';
  @override
  String blockedSecret({required Object secret}) =>
      'Geblokkeerd — een conflictbestand lijkt een ${secret} te bevatten. Los het handmatig op.';
  @override
  String resolutionFailed({required Object error}) =>
      'Oplossen mislukt: ${error}';
  @override
  String mergeResolutionLabel({
    required Object resolved,
    required Object total,
    required Object category,
  }) => '◇ merge-oplossing · ${resolved}/${total} bestanden · ${category}';
  @override
  String conflictSummary({
    required Object op,
    required Object conflicts,
    required Object files,
  }) => '${op} · ${conflicts} in ${files}';
  @override
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} conflict',
        other: '${n} conflicten',
      );
  @override
  String get mergeEditorButton => '⇋ merge-editor';
  @override
  String get noAiModel => 'geen AI-model';
  @override
  String get later => 'later';
  @override
  String get discard => 'verwerpen';
  @override
  String get resolveWithAi => '◇ oplossen met AI';
  @override
  String get otherModel => 'ander model';
  @override
  String withModel({required Object model}) => 'met ${model}';
}

// Path: changes.mergeFlow
class _Translations$changes$mergeFlow$nl
    extends Translations$changes$mergeFlow$en {
  _Translations$changes$mergeFlow$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$mergeFlow$op$nl op =
      _Translations$changes$mergeFlow$op$nl._(_root);
  @override
  String get pushFailed => 'Push mislukt';
  @override
  String get rebasedAndPushed => 'Gerebased en gepusht.';
  @override
  String switchedTo({required Object name}) => 'Gewisseld naar ${name}.';
  @override
  String get switchFailed => 'Wisselen mislukt.';
  @override
  String switchedToCarried({required Object name}) =>
      'Gewisseld naar ${name} (wijzigingen meegenomen).';
  @override
  String get alreadyUpToDate => 'Al bij.';
  @override
  String merged({required Object upstream, required Object n}) =>
      '${upstream} gemergd (${n} bestanden).';
  @override
  String get rebaseNotConverge =>
      'Rebase convergeerde niet — los handmatig op.';
  @override
  String get rebased => 'Gerebased.';
  @override
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'Gerebased (${n} bestand opgelost).',
        other: 'Gerebased (${n} bestanden opgelost).',
      );
  @override
  String get detachedHead =>
      'Sync niet mogelijk: detached-HEAD-staat. Check eerst een branch uit.';
  @override
  String get publishFailed => 'Publiceren mislukt.';
  @override
  String get noRemote =>
      'Geen remote geconfigureerd. Voeg er een toe om deze branch te publiceren.';
  @override
  String get failed => 'mislukt';
}

// Path: changes.constellation
class _Translations$changes$constellation$nl
    extends Translations$changes$constellation$en {
  _Translations$changes$constellation$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get axisStructure => 'STRUCTUUR';
  @override
  String get axisCoChange => 'CO-CHANGE';
  @override
  String get axisSpectralProfile => 'SPECTRAAL PROFIEL';
  @override
  String get axisPathSiblings => 'PAD-BROERS';
  @override
  String get axisDiffStructure => 'DIFF-STRUCTUUR';
  @override
  String get axisSpectral => 'SPECTRAAL';
  @override
  String get titleUnsorted => 'ONGESORTEERD';
  @override
  String get titleSingleton => 'EENLING';
  @override
  String get titleMixed => 'GEMENGD';
  @override
  String get untie => 'losmaken';
  @override
  String get bind => 'binden';
  @override
  String get emptyClusters => 'nog geen clusters';
}

// Path: common.time
class _Translations$common$time$nl extends Translations$common$time$en {
  _Translations$common$time$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get now => 'nu';
  @override
  String get justNow => 'zojuist';
  @override
  String get today => 'VANDAAG';
  @override
  String minutesAgo({required Object n}) => '${n}m geleden';
  @override
  String hoursAgo({required Object n}) => '${n}u geleden';
  @override
  String daysAgo({required Object n}) => '${n}d geleden';
  @override
  String weeksAgo({required Object n}) => '${n}w geleden';
  @override
  String monthsAgo({required Object n}) => '${n}mnd geleden';
  @override
  String yearsAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n}j geleden',
        other: '${n}j geleden',
      );
  @override
  String minutesShort({required Object n}) => '${n}m';
  @override
  String hoursShort({required Object n}) => '${n}u';
  @override
  String daysShort({required Object n}) => '${n}d';
  @override
  String weeksShort({required Object n}) => '${n}w';
  @override
  String monthsShort({required Object n}) => '${n}mnd';
  @override
  String yearsShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n}j',
        other: '${n}j',
      );
  @override
  String commitMonthsShort({required Object n}) => '${n}m';
  @override
  String get idle => 'inactief';
  @override
  String idleDays({required Object n}) => 'inactief ${n} dagen';
  @override
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'inactief ${n} jaar',
        other: 'inactief ${n} jaar',
      );
  @override
  List<String> get monthAbbrevs => [
    'jan',
    'feb',
    'mrt',
    'apr',
    'mei',
    'jun',
    'jul',
    'aug',
    'sep',
    'okt',
    'nov',
    'dec',
  ];
}

// Path: common.size
class _Translations$common$size$nl extends Translations$common$size$en {
  _Translations$common$size$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String bytes({required Object n}) => '${n} B';
  @override
  String kb({required Object n}) => '${n} KB';
  @override
  String mb({required Object n}) => '${n} MB';
  @override
  String gb({required Object n}) => '${n} GB';
}

// Path: diff.status
class _Translations$diff$status$nl extends Translations$diff$status$en {
  _Translations$diff$status$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Diff laden';
  @override
  String get loadingMessage => 'Bestandswijzigingen lezen.';
  @override
  String get unavailableTitle => 'Diff niet beschikbaar';
  @override
  String get noChangesTitle => 'Geen wijzigingen';
  @override
  String get noChangesMessage =>
      'Dit bestand heeft geen diff-inhoud om te tonen.';
}

// Path: diff.toolbar
class _Translations$diff$toolbar$nl extends Translations$diff$toolbar$en {
  _Translations$diff$toolbar$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get searchHint => 'diff doorzoeken...';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} regel',
        other: '${n} regels',
      );
  @override
  String get blameLoading => 'blame...';
  @override
  String get blame => 'blame';
  @override
  String get wearMapOn => 'slijtage · aan';
  @override
  String get wearMapOnHint => 'slijtagekaart aan — klik om te verbergen';
  @override
  String get wearMapOffHint => 'slijtagekaart tonen (activiteits-heatmap)';
  @override
  String get trailBadge => '· spoor';
}

// Path: diff.hunkDropdown
class _Translations$diff$hunkDropdown$nl
    extends Translations$diff$hunkDropdown$en {
  _Translations$diff$hunkDropdown$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip => 'Naar wijzigingsblok springen. Git noemt deze hunks.';
  @override
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} wijziging',
        other: '${n} wijzigingen',
      );
}

// Path: diff.trail
class _Translations$diff$trail$nl extends Translations$diff$trail$en {
  _Translations$diff$trail$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'spoor laden...';
  @override
  String get noHistory => 'geen geschiedenis gevonden';
  @override
  String get nowWorkingCopy => 'nu · werkkopie';
  @override
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class _Translations$diff$pinned$nl extends Translations$diff$pinned$en {
  _Translations$diff$pinned$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get loadingContext => 'vastgezette context laden';
  @override
  String get pageManifold => 'Manifold';
  @override
  String get pageSignals => 'Signalen';
  @override
  String get echoesTitle => 'Echo\'s';
  @override
  String get technicalLedger => 'Technisch grootboek';
  @override
  String get noSecondaryCues => 'Geen secundaire aanwijzingen gedetecteerd.';
  @override
  String get linkedPaths => 'Gekoppelde paden';
  @override
  String moreCount({required Object n}) => '+${n} meer';
  @override
  String get localSeam => 'Lokale naad';
  @override
  String get sharedOwnership => 'gedeeld eigenaarschap';
  @override
  String get historyWarmingUp => 'Geschiedenis warmt op';
  @override
  String echoesTotal({required Object n}) => '${n} TOTAAL';
  @override
  String get noEchoes => 'Geen echo\'s in deze diff.';
  @override
  String openRelatedFile({required Object name}) =>
      'Gerelateerd bestand ${name} openen';
  @override
  String inspectFile({required Object name}) => '${name} inspecteren';
  @override
  String get jumpEcho => 'naar echo springen';
  @override
  String get copyLine => 'regel kopiëren';
  @override
  String get signalTempo => 'T';
  @override
  String get signalNovelty => 'N';
  @override
  String get signalReach => 'R';
  @override
  late final _Translations$diff$pinned$tempo$nl tempo =
      _Translations$diff$pinned$tempo$nl._(_root);
  @override
  late final _Translations$diff$pinned$tone$nl tone =
      _Translations$diff$pinned$tone$nl._(_root);
  @override
  late final _Translations$diff$pinned$summary$nl summary =
      _Translations$diff$pinned$summary$nl._(_root);
  @override
  late final _Translations$diff$pinned$tightness$nl tightness =
      _Translations$diff$pinned$tightness$nl._(_root);
  @override
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept} (${tightness})';
  @override
  String get storyWhyThisMatters => 'Waarom dit ertoe doet';
  @override
  String get storyConfidence => 'Vertrouwen';
  @override
  String get storySecondarySignal => 'Secundair signaal';
  @override
  String get storyNeighbourhood => 'Buurt';
  @override
  String neighbourhoodDetail({required Object name}) =>
      'Deze regel zit dicht bij ${name} in het huidige codebase-veld.';
  @override
  String get propagationLane => 'Voortplantingsbaan';
  @override
  String propagationLaneNamed({required Object lane}) =>
      'Voortplantingsbaan: ${lane}';
  @override
  late final _Translations$diff$pinned$witness$nl witness =
      _Translations$diff$pinned$witness$nl._(_root);
  @override
  late final _Translations$diff$pinned$integrity$nl integrity =
      _Translations$diff$pinned$integrity$nl._(_root);
  @override
  late final _Translations$diff$pinned$related$nl related =
      _Translations$diff$pinned$related$nl._(_root);
  @override
  late final _Translations$diff$pinned$axis$nl axis =
      _Translations$diff$pinned$axis$nl._(_root);
}

// Path: diff.hunkHint
class _Translations$diff$hunkHint$nl extends Translations$diff$hunkHint$en {
  _Translations$diff$hunkHint$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String hiddenCount({required Object n}) => '${n} verborgen';
  @override
  String get landing => 'landing';
}

// Path: diff.binary
class _Translations$diff$binary$nl extends Translations$diff$binary$en {
  _Translations$diff$binary$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String tooLargeToPreview({required Object size}) =>
      '${size} MB (te groot voor voorbeeld)';
  @override
  String get unableToLoadBlob => 'Blob kon niet worden geladen';
  @override
  String get omittedKindMedia => 'media';
  @override
  String get omittedKindBinary => 'binair';
  @override
  String omittedStub({required Object kind}) => '${kind} · verborgen';
}

// Path: diff.media
class _Translations$diff$media$nl extends Translations$diff$media$en {
  _Translations$diff$media$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get unableToDecodeImage => 'Afbeelding kon niet worden gedecodeerd';
  @override
  String sizeLabel({required Object format, required Object size}) =>
      '${format}  ${size}';
  @override
  String sizeDelta({
    required Object oldSize,
    required Object newSize,
    required Object sign,
    required Object delta,
  }) => '${oldSize} → ${newSize}  (${sign}${delta})';
  @override
  String get stateAdded => 'toegevoegd';
  @override
  String get stateDeleted => 'verwijderd';
  @override
  String get stateModified => 'gewijzigd';
  @override
  String get fallbackFormatName => 'Binair';
}

// Path: filament.severity
class _Translations$filament$severity$nl
    extends Translations$filament$severity$en {
  _Translations$filament$severity$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get critical => 'kritiek';
  @override
  String get warn => 'waarschuwing';
  @override
  String get info => 'info';
  @override
  String get joint => 'gewricht';
}

// Path: filament.kind
class _Translations$filament$kind$nl extends Translations$filament$kind$en {
  _Translations$filament$kind$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get staleValue => 'verouderde waarde';
  @override
  String get temporalShift => 'temporele verschuiving';
  @override
  String get contextInversion => 'context-inversie';
  @override
  String get contradictoryFlow => 'tegenstrijdige stroom';
}

// Path: history.commitLede
class _Translations$history$commitLede$nl
    extends Translations$history$commitLede$en {
  _Translations$history$commitLede$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$semantics$nl semantics =
      _Translations$history$commitLede$semantics$nl._(_root);
}

// Path: history.seismograph
class _Translations$history$seismograph$nl
    extends Translations$history$seismograph$en {
  _Translations$history$seismograph$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get rootTrackLabel => '(root)';
  @override
  String dirTrackLabel({required Object name}) => '(${name})';
  @override
  String moreLabel({required Object n}) => '+${n} meer';
  @override
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} bestand in ${path}/',
        other: '${n} bestanden in ${path}/',
      );
  @override
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} bestand meer',
        other: '${n} bestanden meer',
      );
  @override
  String get breadcrumbAll => 'alle';
  @override
  String breadcrumbCurrentFocus({required Object target}) =>
      'Huidige focus: ${target}';
  @override
  String get breadcrumbViewAllChanges =>
      'Alle wijzigingen in deze commit bekijken';
  @override
  String breadcrumbDrillUpTo({required Object target}) =>
      'Omhoog naar ${target}';
  @override
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
    n,
    one: '${n} bestand  +${adds}  -${dels}',
    other: '${n} bestanden  +${adds}  -${dels}',
  );
  @override
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} submap',
        other: '${n} submappen',
      );
  @override
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}, ${adds} toegevoegd, ${dels} verwijderd';
  @override
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
    n,
    one: '${n} bestand, ${adds} toegevoegd, ${dels} verwijderd',
    other: '${n} bestanden, ${adds} toegevoegd, ${dels} verwijderd',
  );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} hunk',
        other: '${n} hunks',
      );
  @override
  String get largestChangeInView => 'grootste wijziging in deze weergave';
  @override
  String get conflictedTag => 'conflict';
  @override
  String get dirtyTag => 'vuil';
  @override
  String get drillInTag => 'induiken';
  @override
  String get changeTypeRenamed => 'hernoemd';
  @override
  String get changeTypeCopied => 'gekopieerd';
  @override
  String get changeTypeTypechange => 'typewijziging';
  @override
  String get changeTypeConflict => 'conflict';
  @override
  String get coreFile => 'kernbestand';
  @override
  String get staleFile => 'verouderd';
  @override
  String get filterPathHint => 'pad filteren';
  @override
  String get escHint => 'esc';
}

// Path: history.worldline
class _Translations$history$worldline$nl
    extends Translations$history$worldline$en {
  _Translations$history$worldline$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get closeWorldline => 'Wereldlijn sluiten';
  @override
  String get dragToOpenWorldline => 'Sleep om wereldlijn te openen';
}

// Path: history.contextMenu
class _Translations$history$contextMenu$nl
    extends Translations$history$contextMenu$en {
  _Translations$history$contextMenu$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get currentBranchFallback => 'huidige branch';
  @override
  String applyCommitOnto({required Object branch}) =>
      'Wijzigingen van commit toepassen op ${branch}';
  @override
  String revertCommitOn({required Object branch}) =>
      'Wijzigingen van commit terugdraaien op ${branch}';
}

// Path: history.cherryPick
class _Translations$history$cherryPick$nl
    extends Translations$history$cherryPick$en {
  _Translations$history$cherryPick$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Cherry-pick gepauzeerd. Rond de resterende conflicten af op de Wijzigingen-pagina.';
  @override
  String failed({required Object error}) => 'Cherry-pick mislukt: ${error}';
  @override
  String pickedResolved({required Object short}) =>
      '${short} cherry-gepickt (conflicten opgelost)';
  @override
  String picked({required Object short}) => '${short} cherry-gepickt';
}

// Path: history.revert
class _Translations$history$revert$nl extends Translations$history$revert$en {
  _Translations$history$revert$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Revert gepauzeerd. Rond de resterende conflicten af op de Wijzigingen-pagina.';
  @override
  String failed({required Object error}) => 'Revert mislukt: ${error}';
  @override
  String revertedResolved({required Object short}) =>
      '${short} teruggedraaid (conflicten opgelost)';
  @override
  String reverted({required Object short}) => '${short} teruggedraaid';
}

// Path: history.reflog
class _Translations$history$reflog$nl extends Translations$history$reflog$en {
  _Translations$history$reflog$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get createBranchFromHere => 'Branch vanaf hier maken…';
  @override
  String get copyCommitHash => 'Commit-hash kopiëren';
  @override
  String get createBranchDialogTitle => 'Branch maken uit reflog-item';
  @override
  String anchorLine({required Object short, required Object summary}) =>
      'Anker: ${short}  ·  ${summary}';
  @override
  String get branchNameHint => 'branch-naam';
  @override
  String get createAction => 'Maken';
  @override
  String createBranchFailed({required Object error}) =>
      'Branch maken mislukt: ${error}';
  @override
  String branchCreatedAt({required Object name, required Object short}) =>
      'Branch "${name}" gemaakt bij ${short}.';
}

// Path: history.rebase
class _Translations$history$rebase$nl extends Translations$history$rebase$en {
  _Translations$history$rebase$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String firstCommitCannotBe({required Object action}) =>
      'Eerste commit kan niet ${action}';
  @override
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} commit rebasen',
        other: '${n} commits rebasen',
      );
  @override
  String get resetLabel => 'resetten';
  @override
  String get dragToReorderHint =>
      'sleep om te herordenen, kies actie per commit';
  @override
  String get newMessageHint => 'nieuw bericht';
  @override
  String get runningEllipsis => '…';
  @override
  String get startRebase => 'Rebase starten';
}

// Path: history.inFlight
class _Translations$history$inFlight$nl
    extends Translations$history$inFlight$en {
  _Translations$history$inFlight$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'ONDERWEG';
  @override
  String get deskFallbackLabel => 'desk';
}

// Path: historySurgery.chrome
class _Translations$historySurgery$chrome$nl
    extends Translations$historySurgery$chrome$en {
  _Translations$historySurgery$chrome$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Geschiedenis-chirurgie';
  @override
  String get alphaBadge => 'alpha';
  @override
  String get dryRunBadge => 'DROOGRUN';
}

// Path: historySurgery.select
class _Translations$historySurgery$select$nl
    extends Translations$historySurgery$select$en {
  _Translations$historySurgery$select$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get prompt => 'Kies bestanden om uit de geschiedenis te verwijderen';
  @override
  String selectedCount({required Object n}) => '${n} geselecteerd';
  @override
  String get searchHint => 'zoeken...';
  @override
  String get readingTree => 'boom lezen...';
  @override
  String get continueDisabled => 'kies bestanden om door te gaan';
  @override
  String get continueEnabled => 'doorgaan →';
  @override
  String toPurgeCount({required Object n}) => '${n} te wissen';
  @override
  String get analyzing => 'analyseren...';
  @override
  String get riskLow => 'laag risico';
  @override
  String get riskModerate => 'matig risico';
  @override
  String get riskHigh => 'hoog risico';
  @override
  String get impactCommitsLabel => 'commits';
  @override
  String get impactBranchesLabel => 'branches';
  @override
  String get impactWorktreesLabel => 'worktrees';
  @override
  String get impactCouplingLabel => 'koppeling';
  @override
  String get impactCouplingIsland => 'eiland';
  @override
  String impactCouplingNeighbors({required Object n}) => '${n} buren';
  @override
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class _Translations$historySurgery$understand$nl
    extends Translations$historySurgery$understand$en {
  _Translations$historySurgery$understand$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get heading => 'Zo werkt dit';
  @override
  String get backupTitle => 'Back-up';
  @override
  String get backupBody =>
      'Elke branch- en tag-ref wordt naar een back-up-namespace gekopieerd voordat er iets verandert. Als er iets misgaat, herstelt één klik de oorspronkelijke staat.';
  @override
  String get rewriteTitle => 'Herschrijven';
  @override
  String get rewriteBody =>
      'Elke commit wordt van root tot tip doorlopen. Voor elke commit die de doelbestanden bevat, wordt een nieuwe commit gemaakt met die bestanden verwijderd uit de boom. Ouderketens worden opnieuw gekoppeld om de topologie te behouden. ';
  @override
  String rewriteSummary({required Object affected, required Object total}) =>
      '${affected} van ${total} commits worden herschreven.';
  @override
  String get updateRefsTitle => 'Refs bijwerken';
  @override
  String get updateRefsBody =>
      'Branch- en tag-pointers worden verplaatst naar de nieuwe commit-SHA\'s. De oude objecten blijven bestaan tot de garbage collection ze opruimt. ';
  @override
  String worktreesNeedRecheckout({required Object n}) =>
      'Je ${n} worktree(s) moeten opnieuw worden uitgecheckt.';
  @override
  String get noWorktreesAffected => 'Geen worktrees getroffen.';
  @override
  String get forcePushTitle => 'Force-push';
  @override
  String get forcePushBody =>
      'Na het verifiëren van het wissen kies je welke branches je force-pusht. Gebruikt --force-with-lease zodat het veilig faalt als iemand anders ondertussen heeft gepusht.';
  @override
  String get plumbingNote =>
      'Anders dan filter-repo of BFG loopt dit volledig via git-plumbing-commando\'s (cat-file, mktree, commit-tree, update-ref). Geen externe afhankelijkheden. De hernoem-tracking volgt één keten per bestand — als een bestand is gekopieerd en beide kopieën onafhankelijk zijn hernoemd, verifieer dan het wisresultaat na uitvoering.';
  @override
  String get back => '← Terug';
  @override
  String get continueLabel => 'Ik snap het, doorgaan →';
}

// Path: historySurgery.confirm
class _Translations$historySurgery$confirm$nl
    extends Translations$historySurgery$confirm$en {
  _Translations$historySurgery$confirm$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String commitsRewritten({required Object n}) =>
      '${n} commits worden herschreven';
  @override
  String get forcePushRequired =>
      'Voor externe branches is een force-push vereist';
  @override
  String worktreesRecheckout({required Object n}) =>
      '${n} worktrees moeten opnieuw worden uitgecheckt';
  @override
  String stashesInvalid({required Object n}) =>
      '${n} stashes kunnen ongeldig worden';
  @override
  String get heading => 'Deze operatie herschrijft de git-geschiedenis';
  @override
  String get subheading =>
      'Na het force-pushen kan het niet automatisch ongedaan worden gemaakt.';
  @override
  String typeHint({required Object word}) => 'typ ${word}';
  @override
  String get goBack => 'Terug';
  @override
  String get begin => 'Chirurgie beginnen';
}

// Path: historySurgery.execute
class _Translations$historySurgery$execute$nl
    extends Translations$historySurgery$execute$en {
  _Translations$historySurgery$execute$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => 'Voorbereiden...';
  @override
  String get backingUpRefs => 'Refs back-uppen...';
  @override
  String get rewritingCommits => 'Commits herschrijven...';
  @override
  String get updatingRefs => 'Refs bijwerken...';
}

// Path: historySurgery.verify
class _Translations$historySurgery$verify$nl
    extends Translations$historySurgery$verify$en {
  _Translations$historySurgery$verify$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get complete => 'Chirurgie voltooid';
  @override
  String get failed => 'Chirurgie mislukt';
  @override
  String get commitsRewrittenLabel => 'Commits herschreven';
  @override
  String get refsUpdatedLabel => 'Refs bijgewerkt';
  @override
  String get oldHeadLabel => 'Oude HEAD';
  @override
  String get newHeadLabel => 'Nieuwe HEAD';
  @override
  String get purgeVerifiedLabel => 'Wissen geverifieerd';
  @override
  String get purgeClean => 'schoon';
  @override
  String get purgeTracesRemain => 'SPOREN RESTEREN';
  @override
  String get displacedWorktrees => 'Verplaatste worktrees';
  @override
  String get undoSurgery => 'Chirurgie ongedaan maken';
  @override
  String get rolledBack => 'Teruggezet naar back-up-refs.';
  @override
  String get done => 'Klaar';
}

// Path: historySurgery.forcePush
class _Translations$historySurgery$forcePush$nl
    extends Translations$historySurgery$forcePush$en {
  _Translations$historySurgery$forcePush$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get pushing => 'pushen...';
  @override
  String get forcePushAll => 'Alles force-pushen';
  @override
  String get confirmPush => 'push bevestigen';
  @override
  String get cancel => 'annuleren';
}

// Path: onboarding.nav
class _Translations$onboarding$nav$nl extends Translations$onboarding$nav$en {
  _Translations$onboarding$nav$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get back => 'Terug';
  @override
  String get continueLabel => 'Doorgaan';
  @override
  String get letsGo => 'Aan de slag';
}

// Path: onboarding.naming
class _Translations$onboarding$naming$nl
    extends Translations$onboarding$naming$en {
  _Translations$onboarding$naming$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'wat is dit voor jou?';
  @override
  String get questionEmphasis => 'dit';
  @override
  String get iAmPrefix => 'Ik ben ';
  @override
  String get iAmSuffix => ' , jouw persoonlijke Git-client.';
}

// Path: onboarding.theme
class _Translations$onboarding$theme$nl
    extends Translations$onboarding$theme$en {
  _Translations$onboarding$theme$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'kleed ${name} aan.';
  @override
  String get themesHeader => 'THEMA\'S';
  @override
  String get keybindingsHeader => 'SNELTOETSEN';
  @override
  String get previewBadge => 'voorbeeld';
  @override
  String get useDefaults => 'standaard gebruiken';
}

// Path: onboarding.repo
class _Translations$onboarding$repo$nl extends Translations$onboarding$repo$en {
  _Translations$onboarding$repo$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'richt ${name} op iets.';
  @override
  String get later => 'dat doe ik later';
  @override
  late final _Translations$onboarding$repo$doors$nl doors =
      _Translations$onboarding$repo$doors$nl._(_root);
  @override
  late final _Translations$onboarding$repo$cloneForm$nl cloneForm =
      _Translations$onboarding$repo$cloneForm$nl._(_root);
  @override
  late final _Translations$onboarding$repo$pickers$nl pickers =
      _Translations$onboarding$repo$pickers$nl._(_root);
  @override
  late final _Translations$onboarding$repo$errors$nl errors =
      _Translations$onboarding$repo$errors$nl._(_root);
}

// Path: onboarding.preview
class _Translations$onboarding$preview$nl
    extends Translations$onboarding$preview$en {
  _Translations$onboarding$preview$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$preview$panels$nl panels =
      _Translations$onboarding$preview$panels$nl._(_root);
  @override
  late final _Translations$onboarding$preview$sidebar$nl sidebar =
      _Translations$onboarding$preview$sidebar$nl._(_root);
  @override
  late final _Translations$onboarding$preview$changes$nl changes =
      _Translations$onboarding$preview$changes$nl._(_root);
  @override
  late final _Translations$onboarding$preview$history$nl history =
      _Translations$onboarding$preview$history$nl._(_root);
  @override
  late final _Translations$onboarding$preview$branches$nl branches =
      _Translations$onboarding$preview$branches$nl._(_root);
  @override
  late final _Translations$onboarding$preview$diff$nl diff =
      _Translations$onboarding$preview$diff$nl._(_root);
}

// Path: orrery.header
class _Translations$orrery$header$nl extends Translations$orrery$header$en {
  _Translations$orrery$header$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Orrery';
  @override
  String get modeScrub => 'Scrubben';
  @override
  String get modeCompare => 'Vergelijken';
  @override
  String get lodModules => 'Modules';
  @override
  String get lodFiles => 'Bestanden';
}

// Path: orrery.status
class _Translations$orrery$status$nl extends Translations$orrery$status$en {
  _Translations$orrery$status$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'De manifold door de geschiedenis traceren…';
  @override
  String get loadError =>
      'De geschiedenis van deze repo kon niet worden gelezen.';
  @override
  String get notEnoughHistory =>
      'Nog niet genoeg geschiedenis om een traject te tekenen.';
  @override
  String get notEnoughHistoryDetail =>
      'De Orrery heeft een paar commits nodig om in kaart te brengen.';
}

// Path: orrery.legend
class _Translations$orrery$legend$nl extends Translations$orrery$legend$en {
  _Translations$orrery$legend$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get central => 'centraal';
  @override
  String get peripheral => 'perifeer';
}

// Path: orrery.node
class _Translations$orrery$node$nl extends Translations$orrery$node$en {
  _Translations$orrery$node$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get module => 'module';
  @override
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · ${n} bestanden';
  @override
  String fileFallback({required Object id}) => 'bestand #${id}';
  @override
  String nodeFallback({required Object id}) => 'knoop #${id}';
  @override
  String get rootModule => '(root)';
}

// Path: orrery.milestone
class _Translations$orrery$milestone$nl
    extends Translations$orrery$milestone$en {
  _Translations$orrery$milestone$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get genesis => 'genesis';
  @override
  String get now => 'nu';
  @override
  String get reorganized => 'gereorganiseerd';
  @override
  String becameArchetype({required Object archetype}) => 'werd ${archetype}';
  @override
  String get snapshot => 'snapshot';
}

// Path: orrery.structure
class _Translations$orrery$structure$nl
    extends Translations$orrery$structure$en {
  _Translations$orrery$structure$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get forming => 'vormt zich…';
  @override
  String get canonical => 'canoniek';
  @override
  String get connectivity => 'connectiviteit';
  @override
  String get rigidity => 'starheid';
  @override
  String get entropy => 'entropie';
}

// Path: orrery.rail
class _Translations$orrery$rail$nl extends Translations$orrery$rail$en {
  _Translations$orrery$rail$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get structureLabel => 'STRUCTUUR';
  @override
  String get fieldLabel => 'VELD';
  @override
  String get findingsLabel => 'BEVINDINGEN';
  @override
  String get selectedLabel => 'GESELECTEERD';
  @override
  String get noFindings =>
      'Geen structurele gebeurtenissen gedetecteerd in deze geschiedenis.';
}

// Path: orrery.selection
class _Translations$orrery$selection$nl
    extends Translations$orrery$selection$en {
  _Translations$orrery$selection$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get notPresent => 'Niet aanwezig op dit punt in de geschiedenis.';
  @override
  String get roleCentral =>
      'Koppelings-centraal — wijzigingen hier rimpelen door het hele systeem.';
  @override
  String get rolePeripheral =>
      'Perifeer — los gekoppeld, wijzigt meestal op zichzelf.';
  @override
  String get roleMid => 'Middenstructuur — matig gekoppeld.';
  @override
  String get driftOutward => ' Drijft naar buiten — ontkoppelt.';
  @override
  String get driftInward => ' Drijft naar binnen — integreert.';
  @override
  String get driftHolding => ' Houdt zijn positie.';
}

// Path: orrery.findingKind
class _Translations$orrery$findingKind$nl
    extends Translations$orrery$findingKind$en {
  _Translations$orrery$findingKind$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get hub => 'HUB';
  @override
  String get driftOut => 'DRIJFT NAAR BUITEN';
  @override
  String get driftIn => 'DRIJFT NAAR BINNEN';
  @override
  String get tangle => 'VERKNOPING';
  @override
  String get clarify => 'VERHELDERING';
  @override
  String get regime => 'REORG';
  @override
  String get thrash => 'GESTAMP';
  @override
  String get reshuffle => 'HERSCHIKKING';
  @override
  String get forecast => 'PROGNOSE';
}

// Path: orrery.findings
class _Translations$orrery$findings$nl extends Translations$orrery$findings$en {
  _Translations$orrery$findings$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get forecastSplit =>
      'De connectiviteit daalt al en zit dicht bij haar laagste punt — als dit aanhoudt, gaat de codebase richting een splitsing in los gekoppelde helften. Beslis nu of dat de bedoeling is.';
  @override
  String get forecastConsolidate =>
      'De connectiviteit klimt richting haar piek — als dit aanhoudt, consolideert de codebase tot één strak gekoppelde massa. Let op dat het niet verhardt tot een monoliet.';
  @override
  String thrash({required Object name}) =>
      '${name} wordt telkens heen en weer gereorganiseerd — veel structurele beroering, weinig netto beweging. Verhelder de koppeling of blijf er vanaf.';
  @override
  String get reshuffle =>
      'Deze commit oogde routineus maar verschoof stilletjes welke bestanden centraal staan — de algehele vorm hield stand terwijl de structuur eronder herschikte. Bekijk hem zorgvuldig.';
  @override
  String hub({required Object name}) =>
      '${name} zit in de structurele kern — het systeem reorganiseert zich eromheen. Behandel wijzigingen hier als hoge blast-radius.';
  @override
  String driftOut({required Object name}) =>
      '${name} is van de kern naar de rand gedreven — het ontkoppelt van het systeem. Of het wordt uitgefaseerd, of het rot stilletjes weg.';
  @override
  String driftIn({required Object name}) =>
      '${name} is naar de kern gemigreerd — het wordt dragend. Zorg dat het goed getest is voordat er meer van afhangt.';
  @override
  String get regime =>
      'De codebase reorganiseerde hier scherp — de connectiviteit sprong. Bekijk wat zich afsplitste of samensmolt.';
  @override
  String get tangleTrend =>
      'In de loop van haar geschiedenis neigde de codebase naar een meer verknoopte structuur — de connectiviteit wordt dichter en minder modulair.';
  @override
  String get clarifyTrend =>
      'In de loop van haar geschiedenis neigde de codebase naar een schonere structuur — ze scheidt zich af in helderdere modules.';
}

// Path: orrery.anchor
class _Translations$orrery$anchor$nl extends Translations$orrery$anchor$en {
  _Translations$orrery$anchor$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get core => 'kern';
  @override
  String get drift => 'drift';
  @override
  String get trend => 'trend';
  @override
  String get thrash => 'gestamp';
}

// Path: orrery.compare
class _Translations$orrery$compare$nl extends Translations$orrery$compare$en {
  _Translations$orrery$compare$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'A → B';
  @override
  String get change => 'WIJZIGING';
  @override
  String get movers => 'BEWEGERS';
  @override
  String get noMovers => 'Geen bestanden verplaatst tussen deze frames.';
  @override
  String get badgeA => 'A';
  @override
  String get badgeB => 'B';
  @override
  String get deltaFiles => 'bestanden';
  @override
  String get deltaConnectivity => 'connectiviteit';
  @override
  String get deltaRigidity => 'starheid';
  @override
  String get deltaEntropy => 'entropie';
  @override
  String get wayOutward => 'naar buiten';
  @override
  String get wayInward => 'naar binnen';
  @override
  String get wayShifted => 'verschoven';
}

// Path: palette.prefixes
class _Translations$palette$prefixes$nl
    extends Translations$palette$prefixes$en {
  _Translations$palette$prefixes$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get askHint => 'vraag: [vraag]';
  @override
  String get nearHint => 'nabij: [bestand]';
  @override
  String get whoHint => 'wie: [bestand]';
  @override
  String get logHint => 'log: [bericht]';
  @override
  String get runHint => 'start: [tool]';
  @override
  String askLabel({required Object name, required Object body}) =>
      'Vraag ${name}: ${body}';
  @override
  String nearSubtitle({required Object path, required Object phi}) =>
      '${path} · φ=${phi}';
  @override
  String whoReviewersLabel({required Object name, required Object reviewers}) =>
      '${name} — ${reviewers}';
  @override
  String whoReviewersSubtitle({
    required Object path,
    required Object count,
    required Object touches,
  }) => '${path} · ${count} reviewers · ${touches} aanrakingen';
  @override
  String whoTouchesLabel({required Object name, required Object touches}) =>
      '${name} — ${touches} aanrakingen';
  @override
  String whoTouchesSubtitle({required Object path}) =>
      '${path} · geen reviewers vastgelegd';
}

// Path: palette.chips
class _Translations$palette$chips$nl extends Translations$palette$chips$en {
  _Translations$palette$chips$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get ai => 'AI';
  @override
  String get near => 'NABIJ';
  @override
  String get who => 'WIE';
  @override
  String get term => 'TERM';
  @override
  String get gui => 'GUI';
  @override
  String get dev => 'DEV';
  @override
  String get debug => 'DEBUG';
  @override
  String get alpha => 'ALPHA';
  @override
  String get hot => 'HEET';
  @override
  String get key => 'KEY';
  @override
  String get web => 'WEB';
  @override
  String get sys => 'SYS';
  @override
  String get clip => 'CLIP';
  @override
  String get sync => 'SYNC';
  @override
  String get force => 'FORCE';
  @override
  String get pr => 'PR';
  @override
  String get draft => 'DRAFT';
  @override
  String get undo => 'UNDO';
  @override
  String get thm => 'THM';
  @override
  String get ver => 'VER';
  @override
  String get desk => 'BUREAU';
  @override
  String get det => 'DET';
  @override
  String get main => 'MAIN';
  @override
  String get head => 'HEAD';
  @override
  String get gone => 'WEG';
  @override
  String get remote => 'REMOTE';
  @override
  String get local => 'LOKAAL';
  @override
  String get an => 'AN';
  @override
  String get lw => 'LW';
}

// Path: palette.predictive
class _Translations$palette$predictive$nl
    extends Translations$palette$predictive$en {
  _Translations$palette$predictive$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String momentumSuffix({required Object percent}) => '${percent}% momentum';
}

// Path: palette.topTouched
class _Translations$palette$topTouched$nl
    extends Translations$palette$topTouched$en {
  _Translations$palette$topTouched$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object count, required Object path}) =>
      '${count} aanrakingen · ${path}';
}

// Path: palette.coherence
class _Translations$palette$coherence$nl
    extends Translations$palette$coherence$en {
  _Translations$palette$coherence$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String label({required Object percent}) => 'Staging-coherentie: ${percent}%';
  @override
  String subtitle({required Object count}) => '${count} bestanden';
}

// Path: palette.keystone
class _Translations$palette$keystone$nl
    extends Translations$palette$keystone$en {
  _Translations$palette$keystone$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object path, required Object score}) =>
      '${path} · sluitsteen ${score}';
}

// Path: palette.repoSub
class _Translations$palette$repoSub$nl extends Translations$palette$repoSub$en {
  _Translations$palette$repoSub$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String changes({required Object name}) => 'Wijzigingen in ${name}';
  @override
  String history({required Object name}) => 'Geschiedenis in ${name}';
  @override
  String branches({required Object name}) => 'Branches in ${name}';
  @override
  String terminal({required Object name}) => 'Terminal in ${name}';
  @override
  String generateCommit({required Object name}) => 'Commit genereren · ${name}';
  @override
  String reviewChanges({required Object name}) =>
      'Wijzigingen reviewen in ${name}';
  @override
  String muse({required Object name}) => 'Muse in ${name}';
}

// Path: palette.desks
class _Translations$palette$desks$nl extends Translations$palette$desks$en {
  _Translations$palette$desks$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get mainWorktree => 'hoofd-worktree';
  @override
  String get detached => 'detached';
  @override
  String dirty({required Object count}) => '${count} vuil';
}

// Path: palette.actions
class _Translations$palette$actions$nl extends Translations$palette$actions$en {
  _Translations$palette$actions$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get openInBrowser => 'Openen in browser';
  @override
  String get terminal => 'Terminal';
  @override
  String get revealInFiles => 'Tonen in bestandsbeheer';
  @override
  String get copyPath => 'Pad kopiëren';
  @override
  String get copyBranch => 'Branch kopiëren';
}

// Path: palette.tools
class _Translations$palette$tools$nl extends Translations$palette$tools$en {
  _Translations$palette$tools$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String launch({required Object label}) => '${label} starten';
}

// Path: palette.gitCommands
class _Translations$palette$gitCommands$nl
    extends Translations$palette$gitCommands$en {
  _Translations$palette$gitCommands$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get fetch => 'Fetch';
  @override
  String get pull => 'Pull';
  @override
  String pullBehind({required Object count}) => '${count} achter';
  @override
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';
  @override
  String get push => 'Push';
  @override
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} commit',
        other: '${n} commits',
      );
  @override
  String pushCommitsUpstream({
    required Object commits,
    required Object upstream,
  }) => '${commits} naar ${upstream}';
  @override
  String get forcePush => 'Force-push';
  @override
  String forcePushNoUpstream({required Object branch}) =>
      'Force-push niet mogelijk: geen upstream ingesteld voor ${branch}.';
  @override
  String get commit => 'Commit';
  @override
  String get stageAll => 'Alles stagen';
  @override
  String get unstageAll => 'Alles unstagen';
  @override
  String get discardAll => 'Alles verwerpen';
  @override
  String get createBranch => 'Branch maken';
  @override
  String get deleteBranch => 'Branch verwijderen';
  @override
  String get renameBranch => 'Branch hernoemen';
  @override
  String get stash => 'Stash';
  @override
  String get stashPop => 'Stash pop';
  @override
  String get stashApply => 'Stash apply';
  @override
  String get stashDrop => 'Stash drop';
  @override
  String get createTag => 'Tag maken';
  @override
  String get cherryPick => 'Cherry-pick';
  @override
  String get revert => 'Revert';
  @override
  String get stashConflictMessage =>
      'Stash toegepast met conflicten. Los ze op de Wijzigingen-pagina op.';
}

// Path: palette.pr
class _Translations$palette$pr$nl extends Translations$palette$pr$en {
  _Translations$palette$pr$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get create => 'PR maken';
  @override
  String get merge => 'PR mergen';
  @override
  String get markReady => 'PR als klaar markeren';
}

// Path: palette.ai
class _Translations$palette$ai$nl extends Translations$palette$ai$en {
  _Translations$palette$ai$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get generateCommit => 'Commit genereren';
  @override
  String get reviewChanges => 'Wijzigingen reviewen';
  @override
  String get runMuse => 'Muse starten';
  @override
  String debugRepo({required Object name}) => '${name} debuggen';
  @override
  String get describeSymptom => 'beschrijf een symptoom';
  @override
  String viewResult({required Object kind}) => '${kind} bekijken';
  @override
  String get unseenResult => 'ongezien resultaat';
  @override
  String runningResult({required Object kind}) => 'AI: ${kind}…';
  @override
  String get running => 'bezig';
  @override
  String get kindCommitMessage => 'Commit-bericht';
  @override
  String get kindCodeReview => 'Code-review';
  @override
  String get kindMuseResult => 'Muse-resultaat';
  @override
  String get kindPresentation => 'Presentatie';
  @override
  String get kindDebugResult => 'Debug-resultaat';
}

// Path: palette.undo
class _Translations$palette$undo$nl extends Translations$palette$undo$en {
  _Translations$palette$undo$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String cancel({required Object label}) => 'Annuleren: ${label}';
}

// Path: palette.navigation
class _Translations$palette$navigation$nl
    extends Translations$palette$navigation$en {
  _Translations$palette$navigation$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get changes => 'Wijzigingen';
  @override
  String get history => 'Geschiedenis';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get settings => 'Instellingen';
  @override
  String get refresh => 'Verversen';
}

// Path: palette.settings
class _Translations$palette$settings$nl
    extends Translations$palette$settings$en {
  _Translations$palette$settings$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get reduceMotion => 'Beweging verminderen';
  @override
  String get animateLogoUnfocused => 'Logo animeren zonder focus';
  @override
  String get instantBlameHover => 'Directe blame bij hover';
  @override
  String get autoSelectChanges => 'Wijzigingen auto-selecteren';
  @override
  String get fetchOnlineIssues => 'Online issues ophalen';
  @override
  String get rememberWip => 'Work in progress onthouden';
  @override
  String get hideAiFeatures => 'AI-functies verbergen';
  @override
  String get crashReporting => 'Crashrapportage';
  @override
  String get aiReadOnly => 'AI alleen-lezen';
  @override
  String get stashCabinetExpanded => 'Stash-kast uitgeklapt';
  @override
  String get fileSortInverted => 'Bestandssortering omgekeerd';
}

// Path: palette.info
class _Translations$palette$info$nl extends Translations$palette$info$en {
  _Translations$palette$info$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class _Translations$palette$debug$nl extends Translations$palette$debug$en {
  _Translations$palette$debug$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get engineStatus => 'Engine-status';
  @override
  String get engineStatusSubtitle => 'LogosGit spectrale-engine-diagnostiek';
  @override
  String get fileCoupling => 'Bestandskoppeling';
  @override
  String get fileCouplingSubtitle =>
      'Dichtstbijzijnde co-change-buren voor gestagede bestanden';
  @override
  String get themeSpecimen => 'Thema-specimen';
  @override
  String get themeSpecimenSubtitle =>
      'Alle kleuren, iconen, tekst-tiers en geometrie';
}

// Path: palette.dev
class _Translations$palette$dev$nl extends Translations$palette$dev$en {
  _Translations$palette$dev$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get testMergeEditor => 'Merge-editor testen';
  @override
  String get testHistorySurgery => 'Geschiedenis-chirurgie testen';
  @override
  String get back => 'terug';
  @override
  String get cancel => 'annuleren';
  @override
  String get buildingConflicts => 'testconflicten uit de geschiedenis bouwen…';
}

// Path: palette.historySurgery
class _Translations$palette$historySurgery$nl
    extends Translations$palette$historySurgery$en {
  _Translations$palette$historySurgery$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Geschiedenis-chirurgie';
  @override
  String get subtitle =>
      'Geschiedenis herschrijven om bestanden permanent te verwijderen';
}

// Path: palette.orrery
class _Translations$palette$orrery$nl extends Translations$palette$orrery$en {
  _Translations$palette$orrery$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Orrery';
  @override
  String get subtitle =>
      'Scrub de structurele geschiedenis van de repo door de manifold';
}

// Path: palette.command
class _Translations$palette$command$nl extends Translations$palette$command$en {
  _Translations$palette$command$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String complete({required Object label}) => '${label} voltooid';
  @override
  String failed({required Object label, required Object message}) =>
      '${label} mislukt: ${message}';
  @override
  String get copy => 'Kopiëren';
}

// Path: palette.search
class _Translations$palette$search$nl extends Translations$palette$search$en {
  _Translations$palette$search$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get hintDefault => 'alles doorzoeken...';
  @override
  String get hintElevated => 'verhoogd — alle acties';
  @override
  String get emptyTypeToSearch => 'typ om te zoeken';
  @override
  String get emptyNoResults => 'geen resultaten';
}

// Path: palette.wick
class _Translations$palette$wick$nl extends Translations$palette$wick$en {
  _Translations$palette$wick$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'wick';
  @override
  String get coupledFallback => 'gekoppeld';
}

// Path: palette.gitCache
class _Translations$palette$gitCache$nl
    extends Translations$palette$gitCache$en {
  _Translations$palette$gitCache$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'actueel';
  @override
  String get staged => 'gestaged';
  @override
  String get modified => 'gewijzigd';
}

// Path: releaseNotes.about
class _Translations$releaseNotes$about$nl
    extends Translations$releaseNotes$about$en {
  _Translations$releaseNotes$about$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$releaseNotes$about$whyFlutter$nl whyFlutter =
      _Translations$releaseNotes$about$whyFlutter$nl._(_root);
  @override
  late final _Translations$releaseNotes$about$spectralEngine$nl spectralEngine =
      _Translations$releaseNotes$about$spectralEngine$nl._(_root);
  @override
  late final _Translations$releaseNotes$about$whereGoing$nl whereGoing =
      _Translations$releaseNotes$about$whereGoing$nl._(_root);
}

// Path: releaseNotes.legal
class _Translations$releaseNotes$legal$nl
    extends Translations$releaseNotes$legal$en {
  _Translations$releaseNotes$legal$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get copyright => '© 2026 Woflo Labs';
  @override
  String get license =>
      'GPL-3.0-or-later · WLCSL community-source onderzoekskern · geen garantie';
}

// Path: repoSummary.backbone
class _Translations$repoSummary$backbone$nl
    extends Translations$repoSummary$backbone$en {
  _Translations$repoSummary$backbone$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}` (${lines}) — ${region}';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} regel',
        other: '${n} regels',
      );
  @override
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class _Translations$repoSummary$glance$nl
    extends Translations$repoSummary$glance$en {
  _Translations$repoSummary$glance$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} bestand.',
        other: '${n} bestanden.',
      );
  @override
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} regel (${bytes}).',
        other: '${n} regels (${bytes}).',
      );
  @override
  String roles({required Object parts}) => 'Rollen — ${parts}.';
  @override
  String showingNofM({required Object active, required Object total}) =>
      'Toont ${active} van ${total} bestanden, gerangschikt op structurele centraliteit.';
}

// Path: repoSummary.heading
class _Translations$repoSummary$heading$nl
    extends Translations$repoSummary$heading$en {
  _Translations$repoSummary$heading$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get atAGlance => 'In één oogopslag';
  @override
  String get core => 'Kern';
  @override
  String get gettingStarted => 'Aan de slag';
  @override
  String get regions => 'Regio\'s';
  @override
  String get shape => 'Vorm';
}

// Path: repoSummary.pitch
class _Translations$repoSummary$pitch$nl
    extends Translations$repoSummary$pitch$en {
  _Translations$repoSummary$pitch$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String empty({required Object detail}) =>
      'Een repository zonder leesbare tekstbestanden${detail}.';
  @override
  String emptyBinary({required Object n}) => '${n} binair';
  @override
  String emptyUnreadable({required Object n}) => '${n} onleesbaar';
  @override
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'Een repository met ${n} actief bestand.',
        other: 'Een repository met ${n} actieve bestanden.',
      );
  @override
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'Een repository met ${n} actief bestand — ${regions}.',
        other: 'Een repository met ${n} actieve bestanden — ${regions}.',
      );
}

// Path: repoSummary.region
class _Translations$repoSummary$region$nl
    extends Translations$repoSummary$region$en {
  _Translations$repoSummary$region$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String bodyCommonDir({required Object dir}) => 'Alles onder `${dir}`.';
  @override
  String get bodyCommonDirSeparator => ' ';
  @override
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '1 kern',
        other: '${n} kern',
      );
  @override
  String get bodyCoreSeparator => ', ';
  @override
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'Eén bestand',
        other: '${n} bestanden',
      );
  @override
  String connectsTo({required Object linked}) => 'Verbindt met: ${linked}.';
  @override
  String get filesLabel => 'Bestanden:';
}

// Path: repoSummary.shape
class _Translations$repoSummary$shape$nl
    extends Translations$repoSummary$shape$en {
  _Translations$repoSummary$shape$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get bulk =>
      'Dicht verknoopte codebase: de meeste bestanden horen bij één grote buurt van gedeelde wijzigingen.';
  @override
  String get crystalline =>
      'Roostervormige codebase: uniforme, regelmatige koppeling over bestanden heen met voorspelbare lokale structuur.';
  @override
  String get goe =>
      'Rijk verknoopte codebase: koppelingen verspreiden zich over bestanden zonder een dominante ruggengraat.';
  @override
  String get modular =>
      'Modulaire codebase: meerdere samenhangende regio\'s met beperkte kruiskoppeling. Werk in de ene regio verstoort zelden een andere.';
  @override
  String get poisson =>
      'Los gekoppelde codebase: bestanden evolueren grotendeels op zichzelf, met af en toe een gedeelde wijziging.';
  @override
  String get tree =>
      'Boomvormige codebase: één dominante ruggengraat met afhankelijke takken. Wijzigingen planten zich meestal vanuit de kern naar buiten voort.';
}

// Path: settings.language
class _Translations$settings$language$nl
    extends Translations$settings$language$en {
  _Translations$settings$language$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Taal';
  @override
  String get summary =>
      'UI-taal voor deze app. Git-uitvoer, logs en diagnostiek blijven Engels, zodat bugrapporten doorzoekbaar blijven.';
  @override
  String get label => 'WEERGAVETAAL';
  @override
  String get systemDefault => 'Systeemstandaard';
  @override
  String systemDefaultDetail({required Object resolved}) =>
      'Volgt je OS-taal (${resolved})';
  @override
  String get disclosureSource => 'Brontaal, geschreven door de ontwikkelaars.';
  @override
  String disclosureAi({required Object model}) =>
      'Machinaal vertaald door ${model}, nog niet door mensen gecontroleerd. Correcties welkom.';
  @override
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) =>
      'Machinaal vertaald door ${model}. ${percent}% door mensen gecontroleerd.';
  @override
  String get disclosureHuman =>
      'Menselijke vertaling, onderhouden door de community.';
  @override
  String reviewedBy({required Object names}) => 'Gecontroleerd door ${names}.';
}

// Path: settings.sectionLabels
class _Translations$settings$sectionLabels$nl
    extends Translations$settings$sectionLabels$en {
  _Translations$settings$sectionLabels$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get preferences => 'Voorkeuren';
  @override
  String get shortcuts => 'Sneltoetsen';
  @override
  String get behaviour => 'Gedrag';
  @override
  String get aiProviders => 'AI-providers';
  @override
  String get modelSlots => 'Modelslots';
  @override
  String get tools => 'Tools';
  @override
  String get diagnostics => 'Diagnostiek';
  @override
  String get offenders => 'Overtreders';
  @override
  String get release => 'Release';
}

// Path: settings.errors
class _Translations$settings$errors$nl extends Translations$settings$errors$en {
  _Translations$settings$errors$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get saveGuardrailProfile =>
      'Guardrail-profiel kon niet worden opgeslagen.';
  @override
  String get saveRetentionPolicy => 'Bewaarbeleid kon niet worden opgeslagen.';
  @override
  String get saveUpdateChannel => 'Update-kanaal kon niet worden opgeslagen.';
  @override
  String get saveModelSelection =>
      'AI-modelselectie kon niet worden opgeslagen.';
  @override
  String get saveModelAlias => 'Model-alias kon niet worden opgeslagen.';
  @override
  String get saveCommitMessageModelSlot =>
      'Modelslot voor commit-berichten kon niet worden opgeslagen.';
  @override
  String get saveReviewModelSlot =>
      'Review-modelslot kon niet worden opgeslagen.';
  @override
  String get saveCommitMessageCustomPrompt =>
      'Eigen commit-bericht-prompt kon niet worden opgeslagen.';
  @override
  String get saveReviewGuide => 'Review-gids kon niet worden opgeslagen.';
  @override
  String get saveMuseNotes => 'Muse-notities konden niet worden opgeslagen.';
  @override
  String get saveReviewDoubleCheck =>
      'Review-dubbelcheckmodus kon niet worden opgeslagen.';
  @override
  String get saveApiPiggybackCli =>
      'API-piggyback-CLI kon niet worden opgeslagen.';
  @override
  String get saveCliTimeout => 'CLI-time-out kon niet worden opgeslagen.';
  @override
  String get stopAllCli => 'De lopende CLI-sessies konden niet worden gestopt.';
  @override
  String clearLocalData({required Object error}) =>
      'Lokale gegevens konden niet worden gewist: ${error}';
}

// Path: settings.promptStatus
class _Translations$settings$promptStatus$nl
    extends Translations$settings$promptStatus$en {
  _Translations$settings$promptStatus$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get editing => 'Bewerken';
  @override
  String get saving => 'Opslaan';
  @override
  String get saveFailed => 'Opslaan mislukt';
}

// Path: settings.clearData
class _Translations$settings$clearData$nl
    extends Translations$settings$clearData$en {
  _Translations$settings$clearData$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => 'Lokale gegevens wissen';
  @override
  String get clear => 'Wissen';
  @override
  String get confirmDiagnostics =>
      'Lokale diagnostiek-samples en performance-timings wissen?';
  @override
  String get confirmAudit => 'Lokale AI-audit-metadata wissen?';
  @override
  String get confirmAll =>
      'Alle lokale diagnostiek-samples en AI-audit-metadata wissen?';
  @override
  String get confirmWipeAll =>
      'Alle lokale app-gegevens — inclusief de lijst met recente repo\'s — wissen en afsluiten? Je daadwerkelijke git-repo\'s op schijf worden niet aangeraakt.';
  @override
  String get confirmReset =>
      'Lokale app-gegevens resetten en afsluiten?\n\nInstellingen, thema, onboarding, AI-voorkeuren, telemetrie en engram-caches worden gewist. Je lijst met recente repo\'s blijft behouden.';
}

// Path: settings.guardrailMacro
class _Translations$settings$guardrailMacro$nl
    extends Translations$settings$guardrailMacro$en {
  _Translations$settings$guardrailMacro$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'los';
  @override
  String get balanced => 'gebalanceerd';
  @override
  String get strict => 'streng';
  @override
  String get paranoid => 'paranoïde';
}

// Path: settings.guardrails
class _Translations$settings$guardrails$nl
    extends Translations$settings$guardrails$en {
  _Translations$settings$guardrails$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Guardrails';
  @override
  String get summary =>
      'Hoe oplettend de automatisering is door de hele ervaring heen.';
}

// Path: settings.appearance
class _Translations$settings$appearance$nl
    extends Translations$settings$appearance$en {
  _Translations$settings$appearance$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Uiterlijk';
  @override
  String get summary => 'Globale sfeer en ambiance van de interface.';
}

// Path: settings.retention
class _Translations$settings$retention$nl
    extends Translations$settings$retention$en {
  _Translations$settings$retention$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Lokale gegevensbewaring';
  @override
  String get summaryDiagnostics => 'Bewaarbeleid voor diagnostiek.';
  @override
  String get summaryWithAudit => 'Bewaarbeleid voor diagnostiek en AI-audit.';
  @override
  String get unitDays => 'dagen';
  @override
  String get unitMb => 'MB';
  @override
  String get includesNote =>
      'Omvat diagnostiek, performance-timings en metadata.';
}

// Path: settings.navigation
class _Translations$settings$navigation$nl
    extends Translations$settings$navigation$en {
  _Translations$settings$navigation$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Navigatie en dynamiek';
  @override
  String get summaryShortcuts => 'Sneltoetsen en interfacegedrag.';
  @override
  String get summaryWithAi => 'Sneltoetsen, interfacegedrag en AI-routing.';
}

// Path: settings.behaviour
class _Translations$settings$behaviour$nl
    extends Translations$settings$behaviour$en {
  _Translations$settings$behaviour$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Gedragsdynamiek';
}

// Path: settings.retentionClear
class _Translations$settings$retentionClear$nl
    extends Translations$settings$retentionClear$en {
  _Translations$settings$retentionClear$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get diag => 'Diag';
  @override
  String get audit => 'Audit';
  @override
  String get all => 'Alle';
  @override
  String get clearsHint => '<-- wist';
}

// Path: settings.channels
class _Translations$settings$channels$nl
    extends Translations$settings$channels$en {
  _Translations$settings$channels$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get stable => 'STABLE';
  @override
  String get beta => 'BETA';
  @override
  String get dev => 'DEV';
}

// Path: settings.pollResult
class _Translations$settings$pollResult$nl
    extends Translations$settings$pollResult$en {
  _Translations$settings$pollResult$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get upToDate => 'bij';
  @override
  String updateAvailable({required Object version}) => '${version} beschikbaar';
  @override
  String get notConfigured => 'geen update-server';
  @override
  String notFound({required Object channel}) => 'geen ${channel}-releases';
  @override
  String get unreachable => 'onbereikbaar';
  @override
  String get badManifest => 'ongeldig manifest';
}

// Path: settings.keybindingProfile
class _Translations$settings$keybindingProfile$nl
    extends Translations$settings$keybindingProfile$en {
  _Translations$settings$keybindingProfile$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Sneltoetsprofiel';
  @override
  String get porcelain => 'Porcelain';
  @override
  String get numeric => 'Numeriek';
  @override
  String get porcelainDescription => 'Akkoord-sneltoetsen (G dan C, H, B…).';
  @override
  String get numericDescription =>
      'Numerieke enkeltoets-sneltoetsen (1, 2, 3…).';
}

// Path: settings.apiKeys
class _Translations$settings$apiKeys$nl
    extends Translations$settings$apiKeys$en {
  _Translations$settings$apiKeys$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get keyHintDefault => 'api-key';
  @override
  String get endpointHint => 'endpoint';
  @override
  String get test => 'Testen';
  @override
  String get hide => 'Verbergen';
  @override
  String get show => 'Tonen';
}

// Path: settings.shortcuts
class _Translations$settings$shortcuts$nl
    extends Translations$settings$shortcuts$en {
  _Translations$settings$shortcuts$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get navigate => 'navigeren';
  @override
  String get staging => 'staging';
  @override
  String get branchesPrs => 'branches & PRs';
  @override
  String get modifiers => 'modifiers';
  @override
  String get changes => 'Wijzigingen';
  @override
  String get history => 'Geschiedenis';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Wisselen (altijd)';
  @override
  String get search => 'Zoeken';
  @override
  String get dismiss => 'Sluiten';
  @override
  String get refresh => 'Verversen';
  @override
  String get shortcuts => 'Sneltoetsen';
  @override
  String get nextChange => 'Volgende wijziging';
  @override
  String get prevChange => 'Vorige wijziging';
  @override
  String get toggleLine => 'Regel omschakelen';
  @override
  String get toggleHunk => 'Hunk omschakelen';
  @override
  String get toggleFile => 'Bestand omschakelen';
  @override
  String get pinContext => 'Context vastzetten';
  @override
  String get commit => 'Commit';
  @override
  String get acceptHint => 'Hint accepteren';
  @override
  String get undo => 'Ongedaan maken';
  @override
  String get navigateRow => 'Navigeren';
  @override
  String get expand => 'Uitklappen';
  @override
  String get checkout => 'Checkout';
  @override
  String get approve => 'Goedkeuren';
  @override
  String get requestChanges => 'Wijzigingen vragen';
  @override
  String get selectRange => 'Bereik selecteren';
  @override
  String get extendedMenu => 'Uitgebreid menu';
}

// Path: settings.toggles
class _Translations$settings$toggles$nl
    extends Translations$settings$toggles$en {
  _Translations$settings$toggles$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get aiReadOnlyLabel => 'AI alleen-lezen-modus';
  @override
  String get aiReadOnlyDescription =>
      'Voorkomt dat AI automatisch wijzigingen schrijft of staged.';
  @override
  String get logoMotionLabel => 'Logo animeert wanneer weggetabt';
  @override
  String get logoMotionDescriptionEnabled =>
      'Het is ontworpen om efficiënt te zijn, kwets zijn gevoelens niet';
  @override
  String get logoMotionDescriptionDisabled => ':(';
  @override
  String get rememberWipLabel => 'Work in progress onthouden';
  @override
  String get rememberWipDescription =>
      'Bewaar je commit-concepten en bestandsselectie tussen sessies.';
  @override
  String get stashCabinetLabel => 'Stash-kast start uitgeklapt';
  @override
  String get stashCabinetDescription =>
      'Toon de archiefkast-lade standaard open wanneer een repo bergingen heeft.';
  @override
  String get instantBlameLabel => 'Directe blame bij hover';
  @override
  String get instantBlameDescription =>
      'Sla de vertraging van 180 ms over voordat blame-info op een diff-regel verschijnt.';
  @override
  String get autoSelectLabel => 'Nieuwe wijzigingen auto-selecteren';
  @override
  String get autoSelectDescription =>
      'Nieuw getrackte of gewijzigde bestanden worden automatisch aan de commit-selectie toegevoegd.';
  @override
  String get changeIdLabel => 'change-id-headers schrijven';
  @override
  String get changeIdDescription =>
      'Voegt aan nieuwe commits een change-id-identiteitsheader toe (de conventie van Jujutsu, GitButler en Gerrit). Elke commit wordt direct na het maken één keer herschreven.';
  @override
  String get fetchIssuesLabel => 'Online issues ophalen bij laden van branches';
  @override
  String get fetchIssuesDescription =>
      'Haal PR- en issue-details op de achtergrond op bij je git-provider wanneer de branches-pagina opent.';
  @override
  String get hateAiLabel => 'Ik haat AI';
  @override
  String get hateAiDescription =>
      'Verban alle LLM-gestuurde functies. Logos blijft draaien omdat het puur spectrale wiskunde is.';
}

// Path: settings.diffDiffability
class _Translations$settings$diffDiffability$nl
    extends Translations$settings$diffDiffability$en {
  _Translations$settings$diffDiffability$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'diff-diffbaarheid';
}

// Path: settings.modelSlots
class _Translations$settings$modelSlots$nl
    extends Translations$settings$modelSlots$en {
  _Translations$settings$modelSlots$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get loadingProviders => 'Providers laden...';
  @override
  String get refreshingProviders => 'Provider-diagnostiek verversen...';
  @override
  String get routeDescription =>
      'Hernoem configuraties en route ze naar elk gedetecteerd provider-model.';
  @override
  String get loadingCategories => 'Modelcategorieën laden...';
  @override
  String get noOptions =>
      'Nog geen modelopties beschikbaar. Detecteer eerst een compatibele lokale AI-CLI.';
  @override
  String get slotsAppearWhenAvailable =>
      'Modelslot-instellingen verschijnen hier zodra provider-modellen beschikbaar zijn.';
  @override
  String get effortDefault => 'standaard';
  @override
  String get noModelsForSlot => 'Geen modellen gedetecteerd voor dit slot.';
  @override
  String viaProvider({required Object provider}) => 'via ${provider}';
  @override
  String get customModelId => 'eigen model-id';
}

// Path: settings.modelPicker
class _Translations$settings$modelPicker$nl
    extends Translations$settings$modelPicker$en {
  _Translations$settings$modelPicker$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String noMatch({required Object query}) =>
      'geen modellen passen bij "${query}"';
  @override
  String get noModels => 'geen modellen beschikbaar';
  @override
  String get filterHint => 'modellen filteren...';
  @override
  String get warming => 'opwarmen…';
  @override
  String get detailsUnavailable => 'details niet beschikbaar';
  @override
  String get free => 'gratis';
}

// Path: settings.aiFeatures
class _Translations$settings$aiFeatures$nl
    extends Translations$settings$aiFeatures$en {
  _Translations$settings$aiFeatures$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get commitDescription =>
      'Stel commit-berichten op uit gestagede wijzigingen volgens je structuur-, stem- en dekkingsvoorkeuren.';
  @override
  String get reviewDescription =>
      'Review de huidige commit-scope voordat je commit.';
  @override
  String get museDescription =>
      'Driefasig orakel dat brainstormt en dan een voorwaartse richting voor de diff synthetiseert.';
}

// Path: settings.commitEditor
class _Translations$settings$commitEditor$nl
    extends Translations$settings$commitEditor$en {
  _Translations$settings$commitEditor$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get styleGuide => 'Stijlgids';
  @override
  String get styleGuideHint =>
      'Optioneel. Stem / toon / verboden. Het formaat hierboven regelt het geraamte.';
}

// Path: settings.review
class _Translations$settings$review$nl extends Translations$settings$review$en {
  _Translations$settings$review$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Extra notities om mee te reviewen';
  @override
  String get doubleCheckLabel => 'Review dubbel checken';
  @override
  String get doubleCheckDescription =>
      'Voer een tweede verificatieronde uit voordat het definitieve rapport wordt getoond.';
}

// Path: settings.museHint
class _Translations$settings$museHint$nl
    extends Translations$settings$museHint$en {
  _Translations$settings$museHint$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get loose =>
      'iets om zachtjes naartoe te sturen? de stemming is vandaag mild.';
  @override
  String get balanced =>
      'waar bij stil te staan, wat over te slaan. eerlijk, niet hard.';
  @override
  String get strict =>
      'de standaarden. de verboden. wat de muse niet laat passeren.';
  @override
  String get paranoid =>
      'stel de lens af. op welke frequenties moet de manifold neuriën?';
}

// Path: settings.museEditor
class _Translations$settings$museEditor$nl
    extends Translations$settings$museEditor$en {
  _Translations$settings$museEditor$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Extra notities voor de muse';
}

// Path: settings.museStage
class _Translations$settings$museStage$nl
    extends Translations$settings$museStage$en {
  _Translations$settings$museStage$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get brainstorm => 'BRAINSTORM';
  @override
  String get synthesize => 'SYNTHESE';
  @override
  String get slot => 'slot';
  @override
  String get ideaCountLoose => '~12 ideeën';
  @override
  String get ideaCountBalanced => '~16 ideeën';
  @override
  String get ideaCountStrict => '~20 ideeën';
  @override
  String get ideaCountParanoid => '~24 ideeën';
  @override
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  guardrail: ${macro}';
}

// Path: settings.lensAxis
class _Translations$settings$lensAxis$nl
    extends Translations$settings$lensAxis$en {
  _Translations$settings$lensAxis$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get folder => 'MAP';
  @override
  String get history => 'HISTORIE';
  @override
  String get far => 'VER';
  @override
  String get near => 'NABIJ';
}

// Path: settings.logosLens
class _Translations$settings$logosLens$nl
    extends Translations$settings$logosLens$en {
  _Translations$settings$logosLens$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get moduleMap => 'module-kaart';
  @override
  String get repoCenters => 'repo-centra';
  @override
  String get neighbors => 'buren';
  @override
  String get toTouch => 'wat als volgende aan te raken';
  @override
  String get relevanceEngine => 'relevantie-engine';
  @override
  String get description =>
      'leest hoe bestanden samen bewegen over structuur, geschiedenis en ritme, zodat Manifold weet wat ertoe doet, niet alleen wat er is gewijzigd.';
  @override
  String get withinReach => 'binnen bereik';
  @override
  String get gate => 'poort';
  @override
  String get nearest => 'dichtstbij';
  @override
  String get warming => 'opwarmen';
  @override
  String get emptyOpenRepo => 'open een repo om\nde lens live te zien';
  @override
  String get emptyNoFiles =>
      'geen bestanden binnen\nbereik — sleep\nrichting HISTORIE';
}

// Path: settings.sortGuide
class _Translations$settings$sortGuide$nl
    extends Translations$settings$sortGuide$en {
  _Translations$settings$sortGuide$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Sorteergids voor wijzigingen';
  @override
  String get related =>
      'Bestanden die samen wijzigen, clusteren samen. Het aandachtspunt eerst; de context volgt.';
  @override
  String get relatedInverted =>
      'Geïsoleerde wijzigingen eerst. Strak gekoppelde clusters zakken naar onderen.';
  @override
  String get alphabetical =>
      'Simpelweg A → Z op pad. Hoofdletterongevoelig, cijfers natuurlijk gesorteerd.';
  @override
  String get alphabeticalInverted =>
      'Simpelweg Z → A op pad. Hoofdletterongevoelig, cijfers natuurlijk gesorteerd.';
  @override
  String get impact =>
      'Zwaarste wijzigingen bovenaan. Churn wordt gewogen; binaire en nieuwe bestanden krijgen een boost.';
  @override
  String get impactInverted =>
      'Lichtste wijzigingen bovenaan. Snelle winsten boven; het zware werk wacht.';
  @override
  String get nearRelated => 'nabij verwant';
  @override
  String get alphabeticalShort => 'alfabetisch';
  @override
  String get byImpact => 'op impact';
  @override
  String get flipped => 'omgekeerd';
  @override
  String get peek => 'gluren';
}

// Path: settings.piggyback
class _Translations$settings$piggyback$nl
    extends Translations$settings$piggyback$en {
  _Translations$settings$piggyback$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get apiModelsUse => 'API-modellen gebruiken';
  @override
  String get codexNotDetected => 'codex niet gedetecteerd';
  @override
  String get dormant => 'SLAPEND';
}

// Path: settings.diffStage
class _Translations$settings$diffStage$nl
    extends Translations$settings$diffStage$en {
  _Translations$settings$diffStage$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get viewer => 'viewer';
  @override
  String get media => 'media';
  @override
  String get binary => 'binair';
  @override
  String get hidden => 'verborgen';
}

// Path: settings.undoScope
class _Translations$settings$undoScope$nl
    extends Translations$settings$undoScope$en {
  _Translations$settings$undoScope$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get destructiveActions => 'destructieve acties';
  @override
  String get discards => 'verwerpingen';
  @override
  String get commits => 'commits';
  @override
  String get commitPush => 'commit + push';
  @override
  String get all => 'alle';
}

// Path: settings.undoWindow
class _Translations$settings$undoWindow$nl
    extends Translations$settings$undoWindow$en {
  _Translations$settings$undoWindow$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Ongedaan-maken-venster';
  @override
  String get off => 'Uit';
  @override
  String descriptionInstant({required Object scope}) =>
      '${scope} worden direct definitief.';
  @override
  String descriptionDelayed({required Object seconds, required Object scope}) =>
      '${seconds}s voordat ${scope} definitief worden.';
  @override
  String get cycleScopeTooltip =>
      'Klik om de scope te doorlopen · sleep ook omhoog/omlaag op de slider';
  @override
  String get resetTooltip => 'Elke actie terugzetten naar het standaardvenster';
}

// Path: settings.guardrailPhrase
class _Translations$settings$guardrailPhrase$nl
    extends Translations$settings$guardrailPhrase$en {
  _Translations$settings$guardrailPhrase$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get probablyFine => 'Waarschijnlijk oké betekent oké';
  @override
  String get proper => 'Een grondige lezing: logica, integratie, patronen';
  @override
  String get lookAgain => 'Kijk nog eens. Er kan iets verscholen zitten';
  @override
  String get assumeWrong => 'Ga ervan uit dat er iets mis is. Vind het';
}

// Path: settings.reviewGuideHint
class _Translations$settings$reviewGuideHint$nl
    extends Translations$settings$reviewGuideHint$en {
  _Translations$settings$reviewGuideHint$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get focusHigh =>
      'bijv. Focus op high-level logica en grote bugs. Wees beknopt en mild.';
  @override
  String get surfaceBugs =>
      'bijv. Breng mogelijke bugs, architecturale inconsistenties en edge-case-fouten aan het licht.';
  @override
  String get scrutinize =>
      'bijv. Onderzoek elke regel op optimalisatie, beveiliging en patroonnaleving.';
  @override
  String get trustNothing =>
      'bijv. Vertrouw niets. Bevraag elk neveneffect. Behandel elke regel als een mogelijke fout.';
  @override
  String get optional =>
      'Optionele richtlijn voor waar de review op moet letten.';
}

// Path: settings.commitFormat
class _Translations$settings$commitFormat$nl
    extends Translations$settings$commitFormat$en {
  _Translations$settings$commitFormat$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Formaat';
  @override
  String get peek => 'gluren';
  @override
  String get structure => 'Structuur';
  @override
  String get voice => 'Stem';
  @override
  String get coverage => 'Dekking';
  @override
  String get structureTitleBody => 'titel + tekst';
  @override
  String get structureTitleOnly => 'alleen titel';
  @override
  String get structureFreeform => 'vrije vorm';
  @override
  String get voiceVerbLed => 'actiegericht';
  @override
  String get voiceDescriptive => 'beschrijvend';
  @override
  String get voiceNarrative => 'verhalend';
  @override
  String get coverageEssentials => 'essentie';
  @override
  String get coverageBalanced => 'gebalanceerd';
  @override
  String get coverageEverything => 'alles';
}

// Path: settings.commitPreview
class _Translations$settings$commitPreview$nl
    extends Translations$settings$commitPreview$en {
  _Translations$settings$commitPreview$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$nl title =
      _Translations$settings$commitPreview$title$nl._(_root);
  @override
  late final _Translations$settings$commitPreview$base$nl base =
      _Translations$settings$commitPreview$base$nl._(_root);
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$nl
  balancedSuffix = _Translations$settings$commitPreview$balancedSuffix$nl._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$nl
  everythingSuffix = _Translations$settings$commitPreview$everythingSuffix$nl._(
    _root,
  );
}

// Path: settings.externalTools
class _Translations$settings$externalTools$nl
    extends Translations$settings$externalTools$en {
  _Translations$settings$externalTools$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Externe tools';
  @override
  String get summary =>
      'Rechtsklik op een project in de zijbalk om het met een van deze te openen. Argumenten gebruiken {path} voor de projectmap.';
  @override
  String get detecting => 'Geïnstalleerde tools detecteren…';
  @override
  String get allPresetsAdded =>
      'Alle bekende presets zijn al toegevoegd. Gebruik „+ Eigen” om meer toe te voegen.';
  @override
  String get noToolsConfigured =>
      'Nog geen tools geconfigureerd. Voeg er hierboven een toe.';
  @override
  String get categoryAi => 'ai';
  @override
  String get categoryEditors => 'editors';
  @override
  String get categoryExplore => 'verkennen';
  @override
  String get categoryOps => 'ops';
  @override
  String get categoryGitOps => 'git-ops';
  @override
  String get nameHint => 'Naam';
  @override
  String get commandHint => 'opdracht';
  @override
  String get test => 'testen';
  @override
  String get removeTool => 'Tool verwijderen';
  @override
  String get modeTerminal => 'terminal';
  @override
  String get modeDetached => 'losgekoppeld';
}

// Path: settings.apiUsage
class _Translations$settings$apiUsage$nl
    extends Translations$settings$apiUsage$en {
  _Translations$settings$apiUsage$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String thisMonth({required Object used, required Object limit}) =>
      '${used}${limit} deze maand';
}

// Path: settings.gitea
class _Translations$settings$gitea$nl extends Translations$settings$gitea$en {
  _Translations$settings$gitea$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Gitea-tokens';
  @override
  String get hostHint => 'host';
  @override
  String get tokenHint => 'token';
  @override
  String get save => 'opslaan';
}

// Path: settings.wick
class _Translations$settings$wick$nl extends Translations$settings$wick$en {
  _Translations$settings$wick$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get selectExecutable => 'wick-executable kiezen';
  @override
  String get connected => 'wick · verbonden';
  @override
  String get pathToExecutable => 'wick · pad naar executable';
  @override
  String get off => 'uit';
  @override
  String get disableHint => 'wick-integratie uitschakelen';
  @override
  String get enableHint => 'wick-integratie inschakelen';
}

// Path: settings.integrations
class _Translations$settings$integrations$nl
    extends Translations$settings$integrations$en {
  _Translations$settings$integrations$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => '& Integraties';
  @override
  String get alpha => 'alpha';
  @override
  String get planned => 'gepland';
  @override
  String get lspComingSoon => 'lsp · binnenkort';
  @override
  String get alphaMathConnected => 'alpha-math · verbonden';
  @override
  String get alphaMathComingSoon => 'alpha-math · binnenkort';
}

// Path: settings.reduceMotion
class _Translations$settings$reduceMotion$nl
    extends Translations$settings$reduceMotion$en {
  _Translations$settings$reduceMotion$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Beweging verminderen';
  @override
  String get subtitleStill => 'Stil… als ijs?';
  @override
  String get subtitleFlow => 'Stroom als water.';
}

// Path: settings.resetQuit
class _Translations$settings$resetQuit$nl
    extends Translations$settings$resetQuit$en {
  _Translations$settings$resetQuit$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get resetAndQuit => 'RESETTEN & AFSLUITEN';
  @override
  String get keepRepos => 'REPO\'S BEHOUDEN';
  @override
  String get wipeAll => 'ALLES WISSEN';
}

// Path: settings.diagnostics
class _Translations$settings$diagnostics$nl
    extends Translations$settings$diagnostics$en {
  _Translations$settings$diagnostics$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get commandDiagnostics => 'Opdracht-diagnostiek';
  @override
  String get networkFlowTelemetry => 'Netwerkstroom-telemetrie';
  @override
  String get clearSamples => 'Samples wissen';
  @override
  String get clearMetrics => 'Metrieken wissen';
  @override
  String get clearTimings => 'Timings wissen';
  @override
  String get recalibrate => 'HERKALIBREREN';
  @override
  String get ok => 'ok';
  @override
  String get noCommandTimings =>
      'Nog geen opdracht-timings vastgelegd. Voer normale acties uit om de diagnostiek te vullen.';
  @override
  String get noBackendSamples =>
      'Nog geen backend-opdracht-samples vastgelegd. Voer git- en instellingenacties uit om deze log te vullen.';
  @override
  String get noDiffSessions =>
      'Nog geen diff-rendersessies vastgelegd. Open en scroll bestandsdiffs om dit paneel te vullen.';
  @override
  String get noUiSessions =>
      'Nog geen UI-timingsessies vastgelegd. Open panelen en navigeer routes om dit paneel te vullen.';
  @override
  String get recentOperations => 'Recente bewerkingen';
  @override
  String get recentBackendOperations => 'Recente backend-bewerkingen';
  @override
  String get recentDiffSessions => 'Recente diff-sessies';
  @override
  String get recentUiTimings => 'Recente UI-timings';
  @override
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} unieke opdracht',
        other: '${n} unieke opdrachten',
      );
  @override
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} scoped opdracht',
        other: '${n} scoped opdrachten',
      );
  @override
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} geïnstrumenteerde gebeurtenis',
        other: '${n} geïnstrumenteerde gebeurtenissen',
      );
  @override
  String summaryCommand({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryBackend({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryDiff({required Object sessions, required Object jank}) =>
      '${sessions} | jank ${jank}%';
  @override
  String summaryUi({required Object samples, required Object events}) =>
      '${samples} | ${events}';
  @override
  List<String> get headersCommand => [
    'opdracht',
    'p50',
    'betrouwbaarheid',
    'bereik',
  ];
  @override
  List<String> get headersBackend => ['scope', 'p50', 'p95', 'fouten'];
  @override
  List<String> get headersDiff => [
    'renderer',
    'eerste paint',
    'frame p95',
    'raster p95',
    'jank',
  ];
  @override
  List<String> get headersUi => ['gebeurtenis', 'p50', 'fouten', 'bereik'];
}

// Path: settings.telemetry
class _Translations$settings$telemetry$nl
    extends Translations$settings$telemetry$en {
  _Translations$settings$telemetry$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} sample',
        other: '${n} samples',
      );
  @override
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} opdracht',
        other: '${n} opdrachten',
      );
  @override
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} sessie',
        other: '${n} sessies',
      );
  @override
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} gebeurtenis',
        other: '${n} gebeurtenissen',
      );
  @override
  String stability({required Object pct}) => '${pct}% stabiliteit';
  @override
  String metaCommand({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String metaDiff({required Object sessions, required Object stability}) =>
      '${sessions} | ${stability}';
  @override
  String metaUi({required Object samples, required Object events}) =>
      '${samples} | ${events}';
}

// Path: settings.flowEngine
class _Translations$settings$flowEngine$nl
    extends Translations$settings$flowEngine$en {
  _Translations$settings$flowEngine$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get executionFlow => 'uitvoeringsstroom';
  @override
  String get description =>
      'simuleert oscillatoren op code. brengt fragiele uitvoeringspaden aan het licht voordat ze als bugs uitkristalliseren.';
  @override
  String get idle => 'inactief';
  @override
  String get emptyOpenRepo => 'open een repo om\nde stroomanalyse te zien';
  @override
  String get scanning => 'scannen';
  @override
  String get analysing => 'bestanden analyseren\nin de lens…';
  @override
  String get fragility => 'fragiliteit';
  @override
  String get findings => 'bevindingen';
  @override
  String get gap => 'gat';
  @override
  String get clean => 'schoon';
  @override
  String get severity => 'ernst';
  @override
  String get critical => 'kritiek';
  @override
  String get warn => 'waarschuwing';
  @override
  String get info => 'info';
}

// Path: settings.museStrands
class _Translations$settings$museStrands$nl
    extends Translations$settings$museStrands$en {
  _Translations$settings$museStrands$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get spark => 'vonk van inspiratie · de eerstvolgende stap';
  @override
  String get current =>
      'stroming in het water · uitbreidingen in de tegenwoordige tijd';
  @override
  String get horizon => 'kijk over de horizon · reikende richtingen';
  @override
  String get fever => 'ontwaak uit een koortsdroom · provocaties';
  @override
  String get echo => 'een echo over de kloof · analogieën elders';
  @override
  String get vertigo =>
      'duizeling aan de rand van de klif · aangrenzende risico\'s';
  @override
  String get ghost => 'de geest van wat was · historische context';
  @override
  String get mirror => 'een spiegel op stil water · inversies';
}

// Path: settings.cliPiggyback
class _Translations$settings$cliPiggyback$nl
    extends Translations$settings$cliPiggyback$en {
  _Translations$settings$cliPiggyback$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'CLI-piggybacking';
  @override
  String get clearCacheLabel => 'Cache wissen';
  @override
  String get clearCacheTooltip =>
      'Gecachte modellen wissen en opnieuw sonderen. Ruimt die op die een provider heeft laten vallen.';
  @override
  String get refreshLabel => 'Providers verversen';
  @override
  String get refreshTooltip => 'Elke provider nu opnieuw sonderen.';
  @override
  String get body =>
      'Leid interface-berichten direct door naar lokale provider-binaries.';
  @override
  String get cliTimeoutLabel => 'Time-out per run';
  @override
  String get cliTimeoutUnitMinutes => 'minuten';
  @override
  String get cliTimeoutUnitMinute => 'minuut';
  @override
  String get forceStopLabel => 'Alle sessies stoppen';
  @override
  String get forceStopTooltip => 'Elke lopende CLI-run hard afsluiten.';
  @override
  String get forceStopConfirmTitle => 'Lopende CLI-sessies stoppen?';
  @override
  String forceStopConfirmBody({required Object count}) =>
      'Dit sluit ${count} lopende CLI-runs hard af. Hun uitvoer gaat verloren.';
  @override
  String get forceStopConfirmAction => 'Alles stoppen';
  @override
  String get forceStopNoneRunning => 'Geen CLI-sessies actief';
  @override
  String get forceStopRecordError =>
      'Gestopt — CLI-sessies zijn hard afgesloten.';
}

// Path: settings.header
class _Translations$settings$header$nl extends Translations$settings$header$en {
  _Translations$settings$header$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Werkruimte-voorkeuren';
  @override
  String get subtitle =>
      'Configureer globale esthetiek, interfacedynamiek en centrale operationele beveiligingen voor de hele werkruimte.';
  @override
  String get releaseNotesTooltip => 'Release notes';
  @override
  String get replayOnboardingTooltip => 'Onboarding opnieuw afspelen';
}

// Path: settings.diagnosticsPanel
class _Translations$settings$diagnosticsPanel$nl
    extends Translations$settings$diagnosticsPanel$en {
  _Translations$settings$diagnosticsPanel$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Performance-diagnostiek';
  @override
  String get copyTrace => 'Trace kopiëren';
  @override
  String get offenderRanking => 'Overtreders-ranglijst';
  @override
  String get offenderRankingSubtitle =>
      'Latentie-aanjagers over de streams heen.';
  @override
  String get noOffenders =>
      'Nog geen overtreders-ranglijst. Leg diagnostiek-activiteit vast om deze lijst te vullen.';
}

// Path: settings.release
class _Translations$settings$release$nl
    extends Translations$settings$release$en {
  _Translations$settings$release$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Release-deployment';
  @override
  String get summary => 'Update-gerelateerde instellingen.';
  @override
  String get deploymentChannel => 'DEPLOYMENT-KANAAL';
  @override
  String get captureCrashDiagnostics => 'Crash-diagnostiek vastleggen';
  @override
  String get comingSoon => 'Binnenkort.';
  @override
  String get checking => 'CONTROLEREN…';
  @override
  String get pollForUpdates => 'OP UPDATES CONTROLEREN';
}

// Path: settings.providerStatus
class _Translations$settings$providerStatus$nl
    extends Translations$settings$providerStatus$en {
  _Translations$settings$providerStatus$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get detecting => 'Detecteren...';
  @override
  String get ready => 'Klaar';
  @override
  String get notDetected => 'Niet gedetecteerd';
  @override
  String configured({required Object count}) => '${count} geconfigureerd';
  @override
  String get notConfigured => 'Niet geconfigureerd';
  @override
  String get cliManaged => 'CLI-beheerd';
  @override
  String get connected => 'Verbonden';
  @override
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} model',
        other: '${n} modellen',
      );
  @override
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} provider',
        other: '${n} providers',
      );
}

// Path: settings.meridiem
class _Translations$settings$meridiem$nl
    extends Translations$settings$meridiem$en {
  _Translations$settings$meridiem$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get am => 'AM';
  @override
  String get pm => 'PM';
}

// Path: settings.offenders
class _Translations$settings$offenders$nl
    extends Translations$settings$offenders$en {
  _Translations$settings$offenders$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get commandStream => 'Opdracht';
  @override
  String get diffStream => 'Diff-render';
  @override
  String get uiStream => 'UI-timing';
  @override
  String rendererName({required Object mode}) => '${mode}-renderer';
  @override
  String latencyFailMetric({required Object p95, required Object fail}) =>
      '${p95}ms p95 | ${fail}% fout';
  @override
  String jankFrameMetric({required Object jank, required Object frame}) =>
      '${jank}% jank | ${frame}ms frame p95';
  @override
  String inStream({required Object stream}) => 'in ${stream}';
}

// Path: sync.actions
class _Translations$sync$actions$nl extends Translations$sync$actions$en {
  _Translations$sync$actions$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get syncLabel => 'Sync';
  @override
  String get syncOpenRepoDetail =>
      'Open een repository om push- en pull-bewerkingen te beheren.';
  @override
  String get detachedHeadLabel => 'Detached HEAD';
  @override
  String get detachedHeadDetail =>
      'Check een branch uit voordat je pusht of pullt.';
  @override
  String get publishBranchLabel => 'Branch publiceren';
  @override
  String publishBranchDetail({required Object branch}) =>
      'Push ${branch} en stel de upstream-tracking-branch in.';
  @override
  String get publishButtonLabel => 'Publiceren';
  @override
  String get syncBranchLabel => 'Branch synchroniseren';
  @override
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => 'Pull ${behindCount} met rebase, push dan ${aheadCount}.';
  @override
  String get syncBranchButtonLabel => 'Pullen (rebase), dan pushen';
  @override
  String get pushBranchLabel => 'Branch pushen';
  @override
  String pushBranchDetail({required Object count, required Object upstream}) =>
      'Push ${count} naar ${upstream}.';
  @override
  String get pushBranchButtonLabel => 'Commits pushen';
  @override
  String get pullUpdatesLabel => 'Updates pullen';
  @override
  String pullUpdatesDetail({required Object count, required Object upstream}) =>
      'Pull ${count} van ${upstream}.';
  @override
  String syncUpToDateDetail({required Object upstream}) =>
      'Fetch van ${upstream} en ververs de upstream-status.';
}

// Path: sync.panel
class _Translations$sync$panel$nl extends Translations$sync$panel$en {
  _Translations$sync$panel$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Externe status laden';
  @override
  String get loadingMessage => 'Branch-tracking-informatie controleren.';
  @override
  String get remoteStatusUnavailable => 'Externe status niet beschikbaar';
  @override
  String get noUpstream => 'geen upstream';
  @override
  String get aheadLabel => 'Voor';
  @override
  String get behindLabel => 'Achter';
  @override
  String get treeLabel => 'Boom';
  @override
  String get runningSync => 'Sync bezig…';
  @override
  String get fetching => 'Fetchen…';
  @override
  String get fetchOnly => 'Alleen fetchen';
  @override
  String get syncFailed => 'Sync mislukt';
  @override
  String get forcePushRecoveryLabel => 'Force-push (met lease)';
  @override
  String get conflictsToResolveTitle => 'Op te lossen conflicten';
  @override
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} moeten worden opgelost: ${list}';
  @override
  String get resolveConflicts => 'Conflicten oplossen';
  @override
  String get workingEllipsis => 'Bezig…';
  @override
  String lastActivity({required Object operation}) =>
      'Laatste activiteit: ${operation}';
  @override
  String get noOutput => 'Geen uitvoer.';
  @override
  String resolvedConflicts({required Object count}) => '${count} opgelost.';
  @override
  String get cancelledUnchanged => 'Geannuleerd, werkboom ongewijzigd.';
  @override
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) =>
      '${count} hebben niet-gecommitte wijzigingen, commit ze eerst om te rebase-syncen (${list}).';
  @override
  String noUpstreamForForcePush({required Object branch}) =>
      'Force-push niet mogelijk: voor "${branch}" is geen upstream geconfigureerd.';
}

// Path: sync.forcePush
class _Translations$sync$forcePush$nl extends Translations$sync$forcePush$en {
  _Translations$sync$forcePush$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get confirmTitle => 'Force-push (met lease)?';
  @override
  String target({required Object remote, required Object branch}) =>
      'Doel: ${remote}/${branch}';
  @override
  String get warning =>
      'Dit overschrijft de externe branch met je lokale geschiedenis. Met lease breekt het af als iemand na je laatste fetch naar de remote heeft gepusht, maar al gefetchte wijzigingen worden alsnog overschreven. Gebruik het alleen wanneer je een rebase of amend bedoelde die de branch liet divergeren.';
  @override
  String get confirmButton => 'Force-push';
}

// Path: xray.board
class _Translations$xray$board$nl extends Translations$xray$board$en {
  _Translations$xray$board$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get movesWithModule => 'beweegt mee met een andere module';
  @override
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} reviewer',
        other: '${n} reviewers',
      );
  @override
  String get territory => 'Territorium';
  @override
  String get unreviewed => 'niet gereviewd';
}

// Path: xray.cadence
class _Translations$xray$cadence$nl extends Translations$xray$cadence$en {
  _Translations$xray$cadence$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '${sum} commits · ${days} dagen\n${lines}';
  @override
  String burstTooltipSingle({required Object n, required Object label}) =>
      '${n} commits op ${label}';
  @override
  String gapTooltip({required Object n, required Object label}) =>
      'gat van ${n} dagen · ${label}';
  @override
  String reflogTooltip({required Object n, required Object label}) =>
      '${n} reflog-gebeurtenissen op ${label}';
}

// Path: xray.cards
class _Translations$xray$cards$nl extends Translations$xray$cards$en {
  _Translations$xray$cards$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$cards$branchModel$nl branchModel =
      _Translations$xray$cards$branchModel$nl._(_root);
  @override
  late final _Translations$xray$cards$bursty$nl bursty =
      _Translations$xray$cards$bursty$nl._(_root);
  @override
  late final _Translations$xray$cards$hiddenRefs$nl hiddenRefs =
      _Translations$xray$cards$hiddenRefs$nl._(_root);
  @override
  late final _Translations$xray$cards$keystone$nl keystone =
      _Translations$xray$cards$keystone$nl._(_root);
  @override
  late final _Translations$xray$cards$machineHistory$nl machineHistory =
      _Translations$xray$cards$machineHistory$nl._(_root);
  @override
  late final _Translations$xray$cards$migration$nl migration =
      _Translations$xray$cards$migration$nl._(_root);
  @override
  late final _Translations$xray$cards$narrowHotspot$nl narrowHotspot =
      _Translations$xray$cards$narrowHotspot$nl._(_root);
  @override
  late final _Translations$xray$cards$noTags$nl noTags =
      _Translations$xray$cards$noTags$nl._(_root);
  @override
  late final _Translations$xray$cards$reflog$nl reflog =
      _Translations$xray$cards$reflog$nl._(_root);
  @override
  late final _Translations$xray$cards$singleOwner$nl singleOwner =
      _Translations$xray$cards$singleOwner$nl._(_root);
}

// Path: xray.cardTitle
class _Translations$xray$cardTitle$nl extends Translations$xray$cardTitle$en {
  _Translations$xray$cardTitle$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get branches => 'branches';
  @override
  String get bursty => 'uitbarstend';
  @override
  String get hiddenRefs => 'verborgen refs';
  @override
  String get machineHeavy => 'machine-zwaar';
  @override
  String get migration => 'migratie';
  @override
  String get narrowHotspot => 'smalle hotspot';
  @override
  String get noTags => 'geen tags';
  @override
  String get reflog => 'reflog';
  @override
  String get singleOwner => 'één-eigenaar';
}

// Path: xray.grain
class _Translations$xray$grain$nl extends Translations$xray$grain$en {
  _Translations$xray$grain$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get coarsest => 'grofste — topniveau-modules';
  @override
  String get finest => 'fijnste korrel';
  @override
  String get mid => 'middenkorrel';
  @override
  String get oneCharacteristic => 'één karakteristieke schaal';
}

// Path: xray.header
class _Translations$xray$header$nl extends Translations$xray$header$en {
  _Translations$xray$header$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get dirtyBadge => 'vuil';
  @override
  String get machineChip => 'machine';
  @override
  String get refresh => 'Verversen';
  @override
  String get refreshing => 'Verversen...';
  @override
  String get title => 'Repo X-Ray';
}

// Path: xray.hotspot
class _Translations$xray$hotspot$nl extends Translations$xray$hotspot$en {
  _Translations$xray$hotspot$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get clusterPeers => 'cluster-buren';
  @override
  String get coChangers => 'co-changers';
  @override
  String get keystone => 'sluitsteen';
  @override
  String keystoneScore({required Object score}) => 'sluitsteen  φ=${score}';
}

// Path: xray.inspector
class _Translations$xray$inspector$nl extends Translations$xray$inspector$en {
  _Translations$xray$inspector$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get branchLabel => 'branch';
  @override
  String commitsHumanMachine({required Object n}) => 'mens · ${n} machine';
  @override
  String get commitsLabel => 'commits';
  @override
  String get confidenceLabel => 'vertrouwen';
  @override
  String get curlLabel => 'curl';
  @override
  String get engineSection => 'engine';
  @override
  String get gradientLabel => 'gradiënt';
  @override
  String get harmonicLabel => 'harmonisch';
  @override
  String get headLabel => 'head';
  @override
  String get hiddenRefsLabel => 'verborgen refs';
  @override
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} merge',
        other: '${n} merges',
      );
  @override
  String get noTags => 'geen tags';
  @override
  String get notesLabel => 'notes';
  @override
  String get openCommit => 'Commit openen';
  @override
  String get pathLabel => 'pad';
  @override
  String remoteCount({required Object n}) => '${n} remote';
  @override
  String get renamesLabel => 'hernoemingen';
  @override
  String scannedAt({required Object time}) => 'gescand ${time}';
  @override
  String selectedCount({required Object n}) => '${n} geselecteerd';
  @override
  String get shapeLinear => 'lineair';
  @override
  String get shapeMergeHeavy => 'merge-zwaar';
  @override
  String get shapeMostlyLinear => 'meestal lineair';
  @override
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} stash',
        other: '${n} stashes',
      );
  @override
  String get stressLabel => 'stress';
  @override
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} tag',
        other: '${n} tags',
      );
  @override
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} worktree',
        other: '${n} worktrees',
      );
}

// Path: xray.loadingCard
class _Translations$xray$loadingCard$nl
    extends Translations$xray$loadingCard$en {
  _Translations$xray$loadingCard$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get buildingMessage =>
      'Git-geschiedenis, refs, tempo en hotspots sonderen.';
  @override
  String get buildingTitle => 'Repo X-Ray bouwen';
  @override
  String get idleMessage =>
      'Open het paneel opnieuw om de huidige repository te sonderen.';
  @override
  String get idleTitle => 'Repo X-Ray';
  @override
  String get unavailableTitle => 'Repo X-Ray niet beschikbaar';
}

// Path: xray.metabolism
class _Translations$xray$metabolism$nl extends Translations$xray$metabolism$en {
  _Translations$xray$metabolism$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String halfLife({required Object n}) => '${n}d halfwaardetijd';
}

// Path: xray.multi
class _Translations$xray$multi$nl extends Translations$xray$multi$en {
  _Translations$xray$multi$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} cluster',
        other: '${n} clusters',
      );
  @override
  String clusterSingle({required Object id}) => 'cluster ${id}';
  @override
  String couplingSuffix({required Object parts}) => '${parts} koppeling';
  @override
  String externalCount({required Object n}) => '${n} extern';
  @override
  String mutualCount({required Object n}) => '${n} wederzijds';
}

// Path: xray.recency
class _Translations$xray$recency$nl extends Translations$xray$recency$en {
  _Translations$xray$recency$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String days({required Object n}) => '${n}d';
  @override
  String months({required Object n}) => '${n}mnd';
  @override
  String get today => 'vandaag';
  @override
  String weeks({required Object n}) => '${n}w';
  @override
  String years({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n}j',
        other: '${n}j',
      );
}

// Path: xray.rings
class _Translations$xray$rings$nl extends Translations$xray$rings$en {
  _Translations$xray$rings$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get hintOneBlended => 'één versmolten structuur';
  @override
  String get hintSelfSimilar => 'zelfgelijkvormig';
  @override
  String get oneBlendedBody =>
      'Eén versmolten structuur — nog geen scheidbare moduleschalen op te lossen.';
  @override
  String get overHistory => 'Over de geschiedenis';
  @override
  String get parts => 'delen';
  @override
  String get readingHint => 'structuur lezen…';
  @override
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} schaal',
        other: '${n} schalen',
      );
  @override
  String get scaleDissolved => 'een structurele schaal loste op';
  @override
  String get scaleEmerged => 'een structurele schaal ontstond';
  @override
  String get scaleSpectrum => 'schaalspectrum';
  @override
  String get selfSimilarBody =>
      'Zelfgelijkvormig — structuur herhaalt zich over schalen heen, zonder één karakteristiek niveau.';
  @override
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} verschuiving in de geschiedenis',
        other: '${n} verschuivingen in de geschiedenis',
      );
  @override
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} structurele verschuiving',
        other: '${n} structurele verschuivingen',
      );
  @override
  String get title => 'Groeiringen';
  @override
  String get unavailable => 'niet beschikbaar';
}

// Path: xray.stats
class _Translations$xray$stats$nl extends Translations$xray$stats$en {
  _Translations$xray$stats$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get alive => 'levend';
  @override
  String get files => 'bestanden';
  @override
  String get lastTouched => 'laatst aangeraakt';
  @override
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'eigenaar',
        other: 'eigenaren',
      );
  @override
  String get touches => 'aanrakingen';
}

// Path: xray.stratumLabel
class _Translations$xray$stratumLabel$nl
    extends Translations$xray$stratumLabel$en {
  _Translations$xray$stratumLabel$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'actueel';
  @override
  String get legacy => 'legacy';
  @override
  String get zone => 'repo-zone';
}

// Path: xray.summary
class _Translations$xray$summary$nl extends Translations$xray$summary$en {
  _Translations$xray$summary$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String analysisFailed({required Object error}) => 'Analyse mislukt: ${error}';
  @override
  String get analyze => 'Analyseren';
  @override
  String get copied => 'Samenvatting naar klembord gekopieerd.';
  @override
  String get directionHint => 'richting';
  @override
  String get download => 'Downloaden';
  @override
  String get emptyState =>
      'Start de Logos-analyse om de structuur en regio\'s van deze repository in kaart te brengen.\n(tw: nogal brak rn)';
  @override
  String get exit => 'Afsluiten';
  @override
  String get generating => 'De repo lezen en kenmerken clusteren…';
  @override
  String get noModel => 'Geen AI-model geconfigureerd.';
  @override
  String get noModelConfigured => 'geen AI-model geconfigureerd';
  @override
  String presentWith({required Object label}) => 'presenteren met ${label}';
  @override
  String presentingWith({required Object label}) => 'presenteren met ${label}…';
  @override
  String get reanalyze => 'Opnieuw analyseren';
  @override
  String get saveDialogTitle => 'Repository-samenvatting opslaan';
  @override
  String saveFailed({required Object error}) => 'Opslaan mislukt: ${error}';
  @override
  String get savePresentationDialogTitle => 'Presentatie opslaan';
  @override
  String savedTo({required Object path}) => 'Opgeslagen naar ${path}';
}

// Path: xray.tabs
class _Translations$xray$tabs$nl extends Translations$xray$tabs$en {
  _Translations$xray$tabs$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get map => 'Kaart';
  @override
  String get signals => 'Signalen';
  @override
  String get summary => 'Samenvatting';
  @override
  String get time => 'Tijd';
}

// Path: xray.trajectory
class _Translations$xray$trajectory$nl extends Translations$xray$trajectory$en {
  _Translations$xray$trajectory$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get connectivity => 'connectiviteit';
  @override
  String events({required Object n}) => '${n} gebeurtenissen';
  @override
  String get openInOrrery => 'Openen in Orrery';
  @override
  String get readingHint => 'geschiedenis lezen…';
  @override
  String snapshots({required Object n}) => '${n} snapshots';
  @override
  String get steady =>
      'Stabiel — geen structurele gebeurtenissen in dit venster.';
  @override
  String get title => 'Structureel traject';
}

// Path: xray.verdict
class _Translations$xray$verdict$nl extends Translations$xray$verdict$en {
  _Translations$xray$verdict$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String canonical({required Object pct}) => '${pct}% canoniek';
  @override
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · ${canonical}% canoniek · ${decisive}% beslissend';
}

// Path: changes.mergeEditor.trust
class _Translations$changes$mergeEditor$trust$nl
    extends Translations$changes$mergeEditor$trust$en {
  _Translations$changes$mergeEditor$trust$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get manual => 'handmatig';
  @override
  String get safe => 'veilig';
  @override
  String get guided => 'geleid';
  @override
  String get assisted => 'geassisteerd';
  @override
  String get full => 'volledig';
  @override
  String label({required Object label}) => 'vertrouwen: ${label}';
}

// Path: changes.mergeEditor.keyHints
class _Translations$changes$mergeEditor$keyHints$nl
    extends Translations$changes$mergeEditor$keyHints$en {
  _Translations$changes$mergeEditor$keyHints$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get accept => 'accepteren';
  @override
  String get other => 'andere';
  @override
  String get both => 'beide';
  @override
  String get navigate => 'navigeren';
  @override
  String get jumpNext => 'naar volgende springen';
}

// Path: changes.mergeFlow.op
class _Translations$changes$mergeFlow$op$nl
    extends Translations$changes$mergeFlow$op$en {
  _Translations$changes$mergeFlow$op$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'merge';
  @override
  String get cherryPick => 'cherry-pick';
  @override
  String get revert => 'revert';
  @override
  String get resolve => 'oplossen';
  @override
  String get switchOp => 'wisselen';
  @override
  String get pull => 'pull';
  @override
  String get rebase => 'rebase';
  @override
  String rebaseOnto({required Object branch, required Object base}) =>
      '${branch} rebasen op ${base}';
}

// Path: diff.pinned.tempo
class _Translations$diff$pinned$tempo$nl
    extends Translations$diff$pinned$tempo$en {
  _Translations$diff$pinned$tempo$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get hotOwnerLane =>
      'Recente beweging met één sterke eigenaar dichtbij.';
  @override
  String get activeSeam => 'Recente beweging van meerdere handen dichtbij.';
  @override
  String get stableOwnerLane => 'Langlevende baan met één dominante eigenaar.';
  @override
  String get sharedLongLivedSeam =>
      'Gedeelde naad die zich in de loop van de tijd heeft opgebouwd.';
  @override
  String get sharedLane => 'Gedeelde baan zonder één dominante eigenaar.';
  @override
  String get resolving =>
      'De geschiedenis rond deze regel is nog niet uitgekristalliseerd.';
}

// Path: diff.pinned.tone
class _Translations$diff$pinned$tone$nl
    extends Translations$diff$pinned$tone$en {
  _Translations$diff$pinned$tone$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get hot => 'Heet';
  @override
  String get novel => 'Nieuw';
  @override
  String get contested => 'Betwist';
  @override
  String get spreading => 'Verspreidend';
  @override
  String get stable => 'Stabiel';
}

// Path: diff.pinned.summary
class _Translations$diff$pinned$summary$nl
    extends Translations$diff$pinned$summary$en {
  _Translations$diff$pinned$summary$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String livesIn({required Object concept}) => 'Woont in ${concept}';
  @override
  String get sitsInLocalSeam => 'Zit in een lokale naad';
  @override
  String workedMostlyBy({required Object owner}) =>
      'meestal bewerkt door ${owner} dichtbij';
  @override
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'echoot op ${n} andere plek',
        other: 'echoot op ${n} andere plekken',
      );
  @override
  String inspectNext({required Object path, required Object detail}) =>
      'inspecteer ${path} als volgende${detail}';
  @override
  String inspectDetail({required Object reason}) => ' (${reason})';
}

// Path: diff.pinned.tightness
class _Translations$diff$pinned$tightness$nl
    extends Translations$diff$pinned$tightness$en {
  _Translations$diff$pinned$tightness$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get tight => 'strakke passing';
  @override
  String get close => 'nauwe passing';
  @override
  String get loose => 'losse passing';
}

// Path: diff.pinned.witness
class _Translations$diff$pinned$witness$nl
    extends Translations$diff$pinned$witness$en {
  _Translations$diff$pinned$witness$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String nearbySupport({required Object label}) => 'Steun dichtbij · ${label}';
  @override
  String localizedMove({required Object label}) =>
      'Gelokaliseerde beweging · ${label}';
  @override
  String surprisingMove({required Object label}) =>
      'Verrassende beweging · ${label}';
}

// Path: diff.pinned.integrity
class _Translations$diff$pinned$integrity$nl
    extends Translations$diff$pinned$integrity$en {
  _Translations$diff$pinned$integrity$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get stableStructure => 'Stabiele structuur';
  @override
  String get conflictingSignals => 'Tegenstrijdige signalen';
  @override
  String get novelShape => 'Nieuwe vorm';
}

// Path: diff.pinned.related
class _Translations$diff$pinned$related$nl
    extends Translations$diff$pinned$related$en {
  _Translations$diff$pinned$related$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get testMirror => 'Test-spiegel';
  @override
  String get semanticHistorySibling => 'Semantiek- + geschiedenis-broer';
  @override
  String get recentCoChange => 'Recente co-change';
  @override
  String get semanticSibling => 'Semantische broer';
  @override
  String get relatedStructure => 'Gerelateerde structuur';
  @override
  String get tightlyBound => 'strak gebonden';
  @override
  String get orbiting => 'in een baan eromheen';
  @override
  String get weaklyCoupled => 'zwak gekoppeld';
  @override
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class _Translations$diff$pinned$axis$nl
    extends Translations$diff$pinned$axis$en {
  _Translations$diff$pinned$axis$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get historyTrail => 'geschiedenisspoor';
  @override
  String get testMirrorLane => 'test-spiegel-baan';
  @override
  String get structuralLane => 'structurele baan';
  @override
  String get semanticNeighbourhood => 'semantische buurt';
}

// Path: history.commitLede.semantics
class _Translations$history$commitLede$semantics$nl
    extends Translations$history$commitLede$semantics$en {
  _Translations$history$commitLede$semantics$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get importanceHigh => 'hoog belang';
  @override
  String get importanceModerate => 'matig belang';
  @override
  String get mostlyAdditions => 'overwegend toevoegingen';
  @override
  String get mostlyDeletions => 'overwegend verwijderingen';
  @override
  String get tightlyCoupled => 'strak gekoppelde bestanden';
  @override
  String get overlapsWorkingTree => 'overlapt je werkboom';
}

// Path: onboarding.repo.doors
class _Translations$onboarding$repo$doors$nl
    extends Translations$onboarding$repo$doors$en {
  _Translations$onboarding$repo$doors$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$repo$doors$open$nl open =
      _Translations$onboarding$repo$doors$open$nl._(_root);
  @override
  late final _Translations$onboarding$repo$doors$clone$nl clone =
      _Translations$onboarding$repo$doors$clone$nl._(_root);
  @override
  late final _Translations$onboarding$repo$doors$create$nl create =
      _Translations$onboarding$repo$doors$create$nl._(_root);
}

// Path: onboarding.repo.cloneForm
class _Translations$onboarding$repo$cloneForm$nl
    extends Translations$onboarding$repo$cloneForm$en {
  _Translations$onboarding$repo$cloneForm$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Klonen van URL';
  @override
  String get urlLabel => 'Repository-URL';
  @override
  String get targetLabel => 'Doelmap';
  @override
  String get browse => 'Bladeren…';
  @override
  String get clone => 'Klonen';
  @override
  String get cloning => 'Klonen…';
}

// Path: onboarding.repo.pickers
class _Translations$onboarding$repo$pickers$nl
    extends Translations$onboarding$repo$pickers$en {
  _Translations$onboarding$repo$pickers$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get openRepository => 'Repository openen';
  @override
  String get createRepository => 'Repository aanmaken';
  @override
  String get cloneTarget => 'Kloon-doel';
}

// Path: onboarding.repo.errors
class _Translations$onboarding$repo$errors$nl
    extends Translations$onboarding$repo$errors$en {
  _Translations$onboarding$repo$errors$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get urlAndTargetRequired => 'URL en doelpad vereist.';
  @override
  String get createFailed => 'Repository aanmaken mislukt.';
  @override
  String get cloneFailed => 'Repository klonen mislukt.';
}

// Path: onboarding.preview.panels
class _Translations$onboarding$preview$panels$nl
    extends Translations$onboarding$preview$panels$en {
  _Translations$onboarding$preview$panels$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get xray => 'repo x-ray';
  @override
  String get settings => 'instellingen';
}

// Path: onboarding.preview.sidebar
class _Translations$onboarding$preview$sidebar$nl
    extends Translations$onboarding$preview$sidebar$en {
  _Translations$onboarding$preview$sidebar$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get projectsHeader => 'Projecten';
}

// Path: onboarding.preview.changes
class _Translations$onboarding$preview$changes$nl
    extends Translations$onboarding$preview$changes$en {
  _Translations$onboarding$preview$changes$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String filesStagedCount({required Object staged, required Object total}) =>
      '${staged} van ${total} bestanden';
  @override
  String stagedCount({required Object n}) => '${n} gestaged';
  @override
  String get commitMessageHint => 'Commit-bericht…';
  @override
  String get commitAndPush => 'Committen & pushen';
}

// Path: onboarding.preview.history
class _Translations$onboarding$preview$history$nl
    extends Translations$onboarding$preview$history$en {
  _Translations$onboarding$preview$history$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'Geschiedenis';
  @override
  String get viewingLast => 'laatste 20 commits bekijken';
  @override
  String get inFlight => 'ONDERWEG';
  @override
  String get you => 'jij';
  @override
  String get commit1 => 'vos leren snuffelen voor het doorslikken';
  @override
  String get commit2 => 'amber: geur de nacht over vasthouden';
  @override
  String get commit3 => 'kool afdanken ten gunste van amber + doorn';
  @override
  String get commit4 => 'doorn bewaakt de poort';
}

// Path: onboarding.preview.branches
class _Translations$onboarding$preview$branches$nl
    extends Translations$onboarding$preview$branches$en {
  _Translations$onboarding$preview$branches$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get lensBranches => 'BRANCHES';
  @override
  String get lensPRs => 'PRs';
  @override
  String get absorbed => 'geabsorbeerd';
  @override
  String get desk => 'desk';
  @override
  String get head => 'HEAD';
  @override
  String tracking({required Object ref}) => '→ volgt: ${ref}';
}

// Path: onboarding.preview.diff
class _Translations$onboarding$preview$diff$nl
    extends Translations$onboarding$preview$diff$en {
  _Translations$onboarding$preview$diff$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get readmeTagline => 'Jouw persoonlijke Git-client.';
}

// Path: releaseNotes.about.whyFlutter
class _Translations$releaseNotes$about$whyFlutter$nl
    extends Translations$releaseNotes$about$whyFlutter$en {
  _Translations$releaseNotes$about$whyFlutter$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'WAAROM FLUTTER?';
  @override
  String get body =>
      'De eerste versie hiervan was een Tauri-app (Rust + TypeScript). Ik voelde al dat het traag aanvoelde. Toen hoorde ik een streamer precies hetzelfde zeggen in een stream die ik normaal niet kijk, en dat was het duwtje om eindelijk over te stappen. Hij stelde geen Flutter voor; verre van dat. Dart vond ik zelf, ik klapte een prototype in elkaar, en de opstarttijd ging van zo\'n 15 seconden naar onder een seconde. Dag en nacht verschil. Vaarwel Tauri-tijdperk.\n\nFlutters rendering-pipeline ligt dichter bij een game-engine dan bij een DOM, en voor een desktop-app waarbij de UI het product is, is dat alles. Dart bleek daarbij een oprecht goede taal. De wiskunde achter de spectrale engine is eerst in Rust geprototyped, dus dat werk droeg prima over.\n\nFlutter is standaard cross-platform, wat geweldig is, maar het is van nature nogal Google-erig, dus er zijn een paar eigenaardigheden.';
}

// Path: releaseNotes.about.spectralEngine
class _Translations$releaseNotes$about$spectralEngine$nl
    extends Translations$releaseNotes$about$spectralEngine$en {
  _Translations$releaseNotes$about$spectralEngine$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'WAT IS DE SPECTRALE ENGINE?';
  @override
  String get body =>
      'Elke keer dat je commit, vormen de bestanden die je samen wijzigt patronen in de tijd. De spectrale engine leest je commit-graaf en ontleedt die co-change-patronen tot signalen: welke bestanden gekoppeld zijn, hoe strak, en welke structurele rol ze in de repo spelen. In essentie spectrale analyse op je ontwikkelgeschiedenis. In een git-client. Met opzet.\n\nDe wiskunde is nieuw, dus ik behandel het als game feel: afstemmen, testen, bijstellen en doorgaan tot de signalen goed aanvoelen.\n\nDie signalen voeden alles. De seismograaf in de geschiedenis, de geschilderde balken onder commit-onderwerpen, het reviewsysteem, Muse, de bestandsconstellatie. De hele app redeneert vanaf deze laag naar beneden, niet andersom.';
}

// Path: releaseNotes.about.whereGoing
class _Translations$releaseNotes$about$whereGoing$nl
    extends Translations$releaseNotes$about$whereGoing$en {
  _Translations$releaseNotes$about$whereGoing$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'WAAR GAAT DIT HEEN?';
  @override
  String get body =>
      'De eerste mijlpaal is volledige pariteit met GitHub Desktop, SourceTree en GitKraken. Een cross-platform git-client die snel aanvoelt en de fundamenten beter afhandelt dan wat dan ook. Dat is grotendeels er. De spectrale engine geeft ons nu al een voordeel bij bewerkingen die andere clients je handmatig laten doordenken.\n\nDaarna is het doel om elke andere git-client te overtreffen in snelheid, toegankelijkheid, intelligentie en algehele UX. Er zit meer in de pijplijn dan hier is aangekondigd.';
}

// Path: settings.commitPreview.title
class _Translations$settings$commitPreview$title$nl
    extends Translations$settings$commitPreview$title$en {
  _Translations$settings$commitPreview$title$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$verbLed$nl verbLed =
      _Translations$settings$commitPreview$title$verbLed$nl._(_root);
  @override
  late final _Translations$settings$commitPreview$title$descriptive$nl
  descriptive = _Translations$settings$commitPreview$title$descriptive$nl._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$title$narrative$nl narrative =
      _Translations$settings$commitPreview$title$narrative$nl._(_root);
}

// Path: settings.commitPreview.base
class _Translations$settings$commitPreview$base$nl
    extends Translations$settings$commitPreview$base$en {
  _Translations$settings$commitPreview$base$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$base$verbLed$nl verbLed =
      _Translations$settings$commitPreview$base$verbLed$nl._(_root);
  @override
  late final _Translations$settings$commitPreview$base$descriptive$nl
  descriptive = _Translations$settings$commitPreview$base$descriptive$nl._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$base$narrative$nl narrative =
      _Translations$settings$commitPreview$base$narrative$nl._(_root);
}

// Path: settings.commitPreview.balancedSuffix
class _Translations$settings$commitPreview$balancedSuffix$nl
    extends Translations$settings$commitPreview$balancedSuffix$en {
  _Translations$settings$commitPreview$balancedSuffix$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$verbLed$nl
  verbLed = _Translations$settings$commitPreview$balancedSuffix$verbLed$nl._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$descriptive$nl
  descriptive =
      _Translations$settings$commitPreview$balancedSuffix$descriptive$nl._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$narrative$nl
  narrative =
      _Translations$settings$commitPreview$balancedSuffix$narrative$nl._(_root);
}

// Path: settings.commitPreview.everythingSuffix
class _Translations$settings$commitPreview$everythingSuffix$nl
    extends Translations$settings$commitPreview$everythingSuffix$en {
  _Translations$settings$commitPreview$everythingSuffix$nl._(
    TranslationsNl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$verbLed$nl
  verbLed = _Translations$settings$commitPreview$everythingSuffix$verbLed$nl._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$descriptive$nl
  descriptive =
      _Translations$settings$commitPreview$everythingSuffix$descriptive$nl._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$narrative$nl
  narrative =
      _Translations$settings$commitPreview$everythingSuffix$narrative$nl._(
        _root,
      );
}

// Path: xray.cards.branchModel
class _Translations$xray$cards$branchModel$nl
    extends Translations$xray$cards$branchModel$en {
  _Translations$xray$cards$branchModel$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get broadClaim =>
      'De repository heeft genoeg branch-oppervlak om branchbewuste navigatie te belonen.';
  @override
  String get broadTitle => 'Branch-model heeft oppervlak';
  @override
  String localBranchesDetail({required Object count}) =>
      '${count} lokale branches.';
  @override
  String get localBranchesLabel => 'Lokale branches';
  @override
  String remoteBranchesDetail({required Object count}) =>
      '${count} externe branches.';
  @override
  String get remoteBranchesLabel => 'Externe branches';
  @override
  String get simpleClaim => 'Het zichtbare branch-model is smal.';
  @override
  String get simpleTitle => 'Eenvoudig branch-model';
}

// Path: xray.cards.bursty
class _Translations$xray$cards$bursty$nl
    extends Translations$xray$cards$bursty$en {
  _Translations$xray$cards$bursty$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Werk landt in geconcentreerde uitbarstingen in plaats van een vlak dagelijks ritme.';
  @override
  String get title => 'Uitbarstend ontwikkeltempo';
}

// Path: xray.cards.hiddenRefs
class _Translations$xray$cards$hiddenRefs$nl
    extends Translations$xray$cards$hiddenRefs$en {
  _Translations$xray$cards$hiddenRefs$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object count}) =>
      '${count} refs leven buiten de normale branch-/tag-ruimte.';
  @override
  String evidenceDetail({required Object count}) =>
      '${count} refs buiten heads/remotes/tags.';
  @override
  String get evidenceLabel => 'Verborgen refs';
  @override
  String get namespacesLabel => 'Namespaces';
  @override
  String get title => 'Verborgen Git-namespaces';
}

// Path: xray.cards.keystone
class _Translations$xray$cards$keystone$nl
    extends Translations$xray$cards$keystone$en {
  _Translations$xray$cards$keystone$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String claim({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
    n,
    one:
        'Eén bestand draagt onevenredig veel co-change-gewicht ten opzichte van zijn aanraaktelling.',
    other:
        'Een kleine set bestanden draagt onevenredig veel co-change-gewicht ten opzichte van hun aanraaktellingen.',
  );
  @override
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: '${n} aanraking · trek φ=${score}',
        other: '${n} aanrakingen · trek φ=${score}',
      );
  @override
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(
        n,
        one: 'Sluitsteen-brugbestand',
        other: '${n} sluitsteen-brugbestanden',
      );
}

// Path: xray.cards.machineHistory
class _Translations$xray$cards$machineHistory$nl
    extends Translations$xray$cards$machineHistory$en {
  _Translations$xray$cards$machineHistory$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Checkpoint-achtige commits vertekenen naïeve geschiedenismetrieken aanzienlijk.';
  @override
  String machineCommitsDetail({required Object count}) =>
      '${count} commits kwamen overeen met machine-/sessiepatronen.';
  @override
  String get machineCommitsLabel => 'Machine-commits';
  @override
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '${raw} ruwe commits vs ${filtered} gefilterde commits.';
  @override
  String get rawVsFilteredLabel => 'Ruw vs gefilterd';
  @override
  String get title => 'Machine-geschiedenis domineert de ruwe metrieken';
}

// Path: xray.cards.migration
class _Translations$xray$cards$migration$nl
    extends Translations$xray$cards$migration$en {
  _Translations$xray$cards$migration$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object older, required Object newer}) =>
      'De geschiedenis verschuift van `${older}` naar `${newer}`, wat op een stack- of oppervlakteovergang duidt.';
  @override
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches} aanrakingen, laatst actief ${lastActive}.';
  @override
  String get title => 'Architectuurmigratie zichtbaar';
}

// Path: xray.cards.narrowHotspot
class _Translations$xray$cards$narrowHotspot$nl
    extends Translations$xray$cards$narrowHotspot$en {
  _Translations$xray$cards$narrowHotspot$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Een kleine set bestanden en mappen absorbeert een onevenredig aandeel van de wijzigingen.';
  @override
  String get title => 'Hotspot-concentratie is smal';
  @override
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path} vormt ${pct}% van de zichtbare hotspot-set.';
  @override
  String get topHotspotLabel => 'Top-hotspot';
  @override
  String visibleAuthorsDetail({required Object count}) =>
      '${count} auteurs in dit geschiedenissegment.';
  @override
  String get visibleAuthorsLabel => 'Zichtbare auteurs';
}

// Path: xray.cards.noTags
class _Translations$xray$cards$noTags$nl
    extends Translations$xray$cards$noTags$en {
  _Translations$xray$cards$noTags$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Git-tags worden niet gebruikt als zichtbare release- of mijlpaallaag.';
  @override
  String remoteEndpointsDetail({required Object count}) =>
      '${count} externe endpoints geconfigureerd.';
  @override
  String get remoteEndpointsLabel => 'Externe endpoints';
  @override
  String get tagCountDetail => '0 tags gevonden.';
  @override
  String get tagCountLabel => 'Tag-aantal';
  @override
  String get title => 'Geen formeel release-/tag-spoor';
}

// Path: xray.cards.reflog
class _Translations$xray$cards$reflog$nl
    extends Translations$xray$cards$reflog$en {
  _Translations$xray$cards$reflog$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Het reflog-volume duidt op geconcentreerde lokale iteratie voorbij gepubliceerde commits.';
  @override
  String get peakReflogDayLabel => 'Piekdag reflog';
  @override
  String get title => 'Intense lokale bewerksessies';
}

// Path: xray.cards.singleOwner
class _Translations$xray$cards$singleOwner$nl
    extends Translations$xray$cards$singleOwner$en {
  _Translations$xray$cards$singleOwner$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object path, required Object kind}) =>
      '`${path}` is een zwaar aangeraakte ${kind} met één duidelijke zichtbare auteur.';
  @override
  String ownerCountDetail({required Object count}) =>
      '${count} unieke auteurs.';
  @override
  String get ownerCountLabel => 'Aantal eigenaren';
  @override
  String get title => 'Hotspot met één eigenaar';
  @override
  String get touchCountLabel => 'Aanraaktelling';
  @override
  String touchDetailFiltered({required Object count}) =>
      '${count} aanrakingen in gefilterde geschiedenis.';
  @override
  String touchDetailRaw({required Object count}) =>
      '${count} aanrakingen in ruwe geschiedenis.';
}

// Path: onboarding.repo.doors.open
class _Translations$onboarding$repo$doors$open$nl
    extends Translations$onboarding$repo$doors$open$en {
  _Translations$onboarding$repo$doors$open$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Openen';
  @override
  String get subtitle => 'bestaand';
  @override
  String get hint => 'een die je al hebt';
}

// Path: onboarding.repo.doors.clone
class _Translations$onboarding$repo$doors$clone$nl
    extends Translations$onboarding$repo$doors$clone$en {
  _Translations$onboarding$repo$doors$clone$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Klonen';
  @override
  String get subtitle => 'van URL';
  @override
  String get hint => 'plak een remote-URL';
}

// Path: onboarding.repo.doors.create
class _Translations$onboarding$repo$doors$create$nl
    extends Translations$onboarding$repo$doors$create$en {
  _Translations$onboarding$repo$doors$create$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Aanmaken';
  @override
  String get subtitle => 'nieuw';
  @override
  String get hint => 'begin iets nieuws';
}

// Path: settings.commitPreview.title.verbLed
class _Translations$settings$commitPreview$title$verbLed$nl
    extends Translations$settings$commitPreview$title$verbLed$en {
  _Translations$settings$commitPreview$title$verbLed$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Laat vos koekjes overslaan die vreemd ruiken';
  @override
  String get s2 =>
      'Leer vos geknoeide koekjes te weigeren vóór het doorslikken';
  @override
  String get s3 => 'Dwing vos elk koekje forensisch te keuren bij de poort';
  @override
  String get def => 'Leer vos slechte koekjes te weigeren';
}

// Path: settings.commitPreview.title.descriptive
class _Translations$settings$commitPreview$title$descriptive$nl
    extends Translations$settings$commitPreview$title$descriptive$en {
  _Translations$settings$commitPreview$title$descriptive$nl._(
    TranslationsNl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'vos kiest nu de koekjes';
  @override
  String get s2 => 'Koekje-inspectieroutine, de vos ingedrild';
  @override
  String get s3 =>
      'Koekje-keuringsforensiek, in de vos verankerd door herhaling';
  @override
  String get def => 'Koekje-snuffelprotocol, in de vos geïnstalleerd';
}

// Path: settings.commitPreview.title.narrative
class _Translations$settings$commitPreview$title$narrative$nl
    extends Translations$settings$commitPreview$title$narrative$en {
  _Translations$settings$commitPreview$title$narrative$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'de vos begon koekjes over te slaan die verkeerd roken';
  @override
  String get s2 =>
      'Ben met de vos gaan zitten en heb doorgenomen welke koekjes te weigeren';
  @override
  String get s3 =>
      'Een groot deel van een middag besteed om de vos ervan te overtuigen dat niet elk aangeboden koekje, te goeder trouw, een koekje is';
  @override
  String get def =>
      'De vos gevraagd koekjes te besnuffelen voordat hij ze opeet';
}

// Path: settings.commitPreview.base.verbLed
class _Translations$settings$commitPreview$base$verbLed$nl
    extends Translations$settings$commitPreview$base$verbLed$en {
  _Translations$settings$commitPreview$base$verbLed$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Vos werpt een blik. Alles wat vreemd is, blijft liggen.';
  @override
  String get s2 =>
      'Vos inspecteert elk token, wijst alles met een vreemde geur af en noteert de weigering op de veranda.';
  @override
  String get s3 =>
      'Vos cirkelt om elk token, proeft de lucht vanuit drie hoeken, weigert elk dat verkeerd aanvoelt en wacht een tel om zeker te weten dat de weigering blijft plakken.';
  @override
  String get def =>
      'Vos besnuffelt nu elk token en wijst de verdachte beleefd af.';
}

// Path: settings.commitPreview.base.descriptive
class _Translations$settings$commitPreview$base$descriptive$nl
    extends Translations$settings$commitPreview$base$descriptive$en {
  _Translations$settings$commitPreview$base$descriptive$nl._(
    TranslationsNl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Zachte doorloop bij de rare, meestal.';
  @override
  String get s2 =>
      'Een gedocumenteerde weigering bij elk token met vreemde geur, uitgevaardigd vanaf de veranda en genoteerd.';
  @override
  String get s3 =>
      'Een notarieel bekrachtigde weigering per token met vreemde geur, uitgevaardigd vanaf de veranda met één poot geheven, de andere stil.';
  @override
  String get def =>
      'Een beleefde weigering bij verdachte tokens, uitgevaardigd vanaf de veranda.';
}

// Path: settings.commitPreview.base.narrative
class _Translations$settings$commitPreview$base$narrative$nl
    extends Translations$settings$commitPreview$base$narrative$en {
  _Translations$settings$commitPreview$base$narrative$nl._(TranslationsNl root)
    : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      'De vos hield gewoon zo\'n beetje op met het opeten van de rare. Makkelijk.';
  @override
  String get s2 =>
      'Vroeger ging elk token zonder veel nadenken naar binnen; nu is er een pauze, een goede blik en een weigering voor die die niet lekker zitten.';
  @override
  String get s3 =>
      'Vroeger ging elk token naar binnen zonder nadenken. Nu: een pauze. De lucht, ingeademd. De lucht, vastgehouden. De vos let op de verandaplanken op het kleine trillen dat ze soms hebben als er iets mis is, en pas dan valt de beslissing.';
  @override
  String get def =>
      'Vroeger werd elk token zonder ceremonie doorgeslikt; nu is er eerst een snuf.';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class _Translations$settings$commitPreview$balancedSuffix$verbLed$nl
    extends Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  _Translations$settings$commitPreview$balancedSuffix$verbLed$nl._(
    TranslationsNl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Veranda is prima. Achtertuin boeit niet.';
  @override
  String get s2 =>
      ' Veranda geveegd na elke weigering; achtertuinmodder toegestaan binnen de aangekondigde uren.';
  @override
  String get s3 =>
      ' Veranda geveegd en opnieuw geveegd; achtertuinmodder gecatalogiseerd op pootafdruk en weer, en de vos talmt langer bij de drempel dan voorheen.';
  @override
  String get def =>
      ' Veranda blijft schoon; achtertuin behoudt zijn modderrechten.';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class _Translations$settings$commitPreview$balancedSuffix$descriptive$nl
    extends Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  _Translations$settings$commitPreview$balancedSuffix$descriptive$nl._(
    TranslationsNl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Veranda oké. Achtertuin doet achtertuindingen.';
  @override
  String get s2 =>
      ' Veranda als bewijs-schone zone; achtertuin als aangewezen modderzone, uren aangekondigd.';
  @override
  String get s3 =>
      ' Veranda als cleanroom van bewijskwaliteit; achtertuin als gecatalogiseerd modderarchief; drempel als plek waar de vos staat en te lang nadenkt.';
  @override
  String get def => ' Schone veranda; modderrechten behouden in de achtertuin.';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class _Translations$settings$commitPreview$balancedSuffix$narrative$nl
    extends Translations$settings$commitPreview$balancedSuffix$narrative$en {
  _Translations$settings$commitPreview$balancedSuffix$narrative$nl._(
    TranslationsNl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Veranda was prima. Achtertuin, wie zal het zeggen.';
  @override
  String get s2 =>
      ' De veranda werd daarna schoon gehouden; de vos trok zich terug in de achtertuin, waar het denken gebeurt.';
  @override
  String get s3 =>
      ' De veranda werd die avond twee keer geschrobd. De vos liep langzaam door de achtertuin, pauzeerde bij dezelfde hekpaal als altijd, en keek terug naar de veranda alsof de veranda hem iets schuldig was.';
  @override
  String get def =>
      ' De veranda blijft schoon, al wint de achtertuin nog steeds op waardigheid.';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class _Translations$settings$commitPreview$everythingSuffix$verbLed$nl
    extends Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  _Translations$settings$commitPreview$everythingSuffix$verbLed$nl._(
    TranslationsNl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Amber is er. Drift drijft. Doorn prikt als het moet. Meestal niets.';
  @override
  String get s2 =>
      ' Amber houdt elke geur vast ter beoordeling. Drift draagt de dagluchten naar de poortdoorn, die elke weigering markeert voor de avondtelling.';
  @override
  String get s3 =>
      ' Amber houdt elke geur vast en geeft hem een ander gewicht afhankelijk van het uur. Drift beweegt door de veranda onder hoeken die er niet toe zouden moeten doen maar dat wel doen. De poortdoorn prikt één keer voor weigeringen en twee keer voor die die de vos bijna miste, en de vos kent het verschil zelfs als niemand anders dat doet.';
  @override
  String get def =>
      ' Amber houdt de geur vast. Drift draagt hem verder. De poortdoorn vangt wat er niet door hoort.';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class _Translations$settings$commitPreview$everythingSuffix$descriptive$nl
    extends
        Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  _Translations$settings$commitPreview$everythingSuffix$descriptive$nl._(
    TranslationsNl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Amber op de paal. Drift in de lucht. Doorn bij de poort. Prima.';
  @override
  String get s2 =>
      ' Amber als aangewezen geurgetuige; drift als gelogde omgeving; doornmarkeringen als het weigeringsregister van de dag, verzoend bij schemering.';
  @override
  String get s3 =>
      ' Amber als geurgetuige wiens stilte zelf al een aflezing is; drift als een patroonrijke omgeving die verkeerd beweegt op de dagen dat er iets mis is; doorn als de tellenhouder van de poort, wiens markeringen de vos controleert voor het slapen en opnieuw voor zonsopgang.';
  @override
  String get def =>
      ' Amber als geurgetuige; drift als omgevingscontext; doorn als de stille weigeringsmarkering van de poort.';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class _Translations$settings$commitPreview$everythingSuffix$narrative$nl
    extends Translations$settings$commitPreview$everythingSuffix$narrative$en {
  _Translations$settings$commitPreview$everythingSuffix$narrative$nl._(
    TranslationsNl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsNl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Amber was in de buurt. Drift kwam en ging. Doorn deed zijn stille ding. Boeit niet, het was chill.';
  @override
  String get s2 =>
      ' Amber hield het geurregister van de dag bij, drift werd genoteerd op richting en uur, en de markeringen van de doorn werden geteld en medeondertekend door de veranda.';
  @override
  String get s3 =>
      ' Amber hield het geurregister bij, maar de vos zweert dat het op bepaalde ochtenden zwaarder weegt. Drift bewoog door de veranda zoals het dat altijd doet, wat wil zeggen: verkeerd op de dagen die ertoe doen. De poortdoorn markeerde elke weigering; de vos ging bij het eerste licht naar buiten om ze te tellen, zoals je treden telt die je al geteld hebt.';
  @override
  String get def =>
      ' Amber hield het geurregister vast, drift bewoog de lucht, en de poortdoorn ving wat gevangen moest worden.';
}
