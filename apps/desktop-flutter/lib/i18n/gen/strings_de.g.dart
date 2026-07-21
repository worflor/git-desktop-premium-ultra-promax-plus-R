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
class TranslationsDe extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsDe({
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
             locale: AppLocale.de,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <de>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final TranslationsDe _root = this; // ignore: unused_field

  @override
  TranslationsDe $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsDe(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$app$de app = _Translations$app$de._(_root);
  @override
  late final _Translations$backend$de backend = _Translations$backend$de._(
    _root,
  );
  @override
  late final _Translations$branches$de branches = _Translations$branches$de._(
    _root,
  );
  @override
  late final _Translations$changes$de changes = _Translations$changes$de._(
    _root,
  );
  @override
  late final _Translations$common$de common = _Translations$common$de._(_root);
  @override
  late final _Translations$diff$de diff = _Translations$diff$de._(_root);
  @override
  late final _Translations$filament$de filament = _Translations$filament$de._(
    _root,
  );
  @override
  late final _Translations$history$de history = _Translations$history$de._(
    _root,
  );
  @override
  late final _Translations$historySurgery$de historySurgery =
      _Translations$historySurgery$de._(_root);
  @override
  late final _Translations$onboarding$de onboarding =
      _Translations$onboarding$de._(_root);
  @override
  late final _Translations$orrery$de orrery = _Translations$orrery$de._(_root);
  @override
  late final _Translations$palette$de palette = _Translations$palette$de._(
    _root,
  );
  @override
  late final _Translations$releaseNotes$de releaseNotes =
      _Translations$releaseNotes$de._(_root);
  @override
  late final _Translations$repoSummary$de repoSummary =
      _Translations$repoSummary$de._(_root);
  @override
  late final _Translations$settings$de settings = _Translations$settings$de._(
    _root,
  );
  @override
  late final _Translations$sync$de sync = _Translations$sync$de._(_root);
  @override
  late final _Translations$xray$de xray = _Translations$xray$de._(_root);
}

// Path: app
class _Translations$app$de extends Translations$app$en {
  _Translations$app$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get panelSettings => 'Einstellungen';
  @override
  String get panelReleaseNotes => 'Release Notes';
  @override
  String get panelFilamentFindings => 'Filament-Funde';
  @override
  String get filamentFindingsUpper => 'FILAMENT-FUNDE';
  @override
  late final _Translations$app$cheatsheet$de cheatsheet =
      _Translations$app$cheatsheet$de._(_root);
  @override
  String get commandPaletteTooltip => 'Befehlspalette   /';
  @override
  String get newDeskFallback => 'neuer Desk';
  @override
  String get deskFallback => 'Desk';
  @override
  String get currentDeskFallback => 'aktuell';
  @override
  String get noRepositoryOpen => 'Kein Repository geöffnet';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Konnte nicht als Desk öffnen: ${error}';
  @override
  String couldNotDetectForge({required Object error}) =>
      'Forge konnte nicht erkannt werden: ${error}';
  @override
  String get cannotFetchPrNoForge =>
      'PR kann nicht abgerufen werden: Forge für dieses Repo nicht erkannt.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      '${ref} mit dem neuesten Stand vom Remote überschreiben?';
  @override
  String get overwrite => 'Überschreiben';
  @override
  String couldntFetchPr({required Object error}) =>
      'PR konnte nicht abgerufen werden: ${error}';
  @override
  String get promoteDeskToPr => 'Desk zu PR befördern';
  @override
  String get applyToMain => 'Auf main anwenden';
  @override
  String updateDeskFrom({required Object target, required Object source}) =>
      '${target} von ${source} aktualisieren';
  @override
  String bringChangesFromHere({required Object source}) =>
      'Änderungen von ${source} hierher holen';
  @override
  String get editLocalPr => 'Lokalen PR bearbeiten';
  @override
  String get discardLocalPr => 'Lokalen PR verwerfen';
  @override
  String get closeDesk => 'Desk schließen';
  @override
  String couldntPromote({required Object error}) =>
      'Beförderung fehlgeschlagen: ${error}';
  @override
  String get commitOrShelveBeforeApplying =>
      'Committe oder verstaue die Änderungen des Deskes vor dem Anwenden.';
  @override
  String get couldNotResolveMainWorktree =>
      'Der Pfad des Haupt-Worktrees konnte nicht aufgelöst werden.';
  @override
  String couldntPromoteDesk({required Object error}) =>
      'Desk konnte nicht befördert werden: ${error}';
  @override
  String get couldntDetermineBaseBranch =>
      'Der Basis-Branch für diesen Desk konnte nicht bestimmt werden.';
  @override
  String prBaseHeadSame({required Object branch}) =>
      'PR-Basis und -Head sind derselbe Branch (${branch}) — nichts anzuwenden.';
  @override
  String appliedBranchToBase({required Object branch, required Object base}) =>
      '${branch} auf ${base} angewendet';
  @override
  String updatedDeskToDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    n,
    one: '${target} auf ${source} aktualisiert (${n} Commit).',
    other: '${target} auf ${source} aktualisiert (${n} Commits).',
  );
  @override
  String get fastForwardFailedFallback =>
      'Fast-Forward konnte nicht sauber landen — zeige stattdessen eine Patch-Vorschau.';
  @override
  String deskAheadOfDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    n,
    one: '${target} ist ${source} um ${n} Commit voraus.',
    other: '${target} ist ${source} um ${n} Commits voraus.',
  );
  @override
  String deskUpToDate({required Object target, required Object source}) =>
      '${target} ist bereits auf dem Stand von ${source}.';
  @override
  String uncommittedPreviewNotice({required Object target}) =>
      'Uncommittete Änderungen in ${target} — zeige stattdessen eine Vorschau als Patch.';
  @override
  String updateDeskFromLower({
    required Object target,
    required Object source,
  }) => '${target} von ${source} aktualisieren';
  @override
  String noUpdatesToBringFrom({required Object source}) =>
      'Keine Updates von ${source} zu holen.';
  @override
  String get updatePrepFailed => 'Update-Vorbereitung fehlgeschlagen';
  @override
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => 'Änderungen von ${source} nach ${target} holen';
  @override
  String noPatchableChanges({required Object source, required Object target}) =>
      'Keine patchbaren Änderungen von ${source} nach ${target} zu holen.';
  @override
  String get patchPrepFailed => 'Patch-Vorbereitung fehlgeschlagen';
  @override
  String failureWithError({required Object label, required Object error}) =>
      '${label}: ${error}';
  @override
  String get titleHint => 'Titel';
  @override
  String get bodyHint => 'Text';
  @override
  String get bodyOptionalHint => 'Text (optional)';
  @override
  String get draftLower => 'entwurf';
  @override
  String get cancelLower => 'abbrechen';
  @override
  String get saveLower => 'speichern';
  @override
  String couldntSave({required Object error}) =>
      'Konnte nicht speichern: ${error}';
  @override
  String get stashedNoOtherDesk =>
      'Änderungen gestasht — kein anderer Desk zum Anwenden. Nutze git stash pop zum Wiederherstellen.';
  @override
  String get suggestedSource => 'vorgeschlagene Quelle';
  @override
  String tooltipModifiedCount({required Object n}) => '${n} geändert';
  @override
  String tooltipAheadCount({required Object n}) => '${n} voraus';
  @override
  String tooltipBehindCount({required Object n}) => '${n} zurück';
  @override
  String get focusedEdits => 'fokussierte Änderungen';
  @override
  String get editsSpreadAcrossSubsystems =>
      'Änderungen über Subsysteme verteilt';
  @override
  String get editsTouchingManySubsystems =>
      'Änderungen berühren viele Subsysteme';
  @override
  String get focusedBranch => 'fokussierter Branch';
  @override
  String get branchSpansMultipleSubsystems =>
      'Branch erstreckt sich über mehrere Subsysteme';
  @override
  String get structurallyDivergentFromMainline =>
      'strukturell abweichend vom Hauptzweig';
  @override
  String get localPr => 'lokaler PR';
  @override
  String lastTouched({required Object time}) => 'zuletzt berührt ${time}';
  @override
  String driftGroupCount({required Object n, required Object dir}) =>
      '${n} in ${dir}';
  @override
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';
  @override
  String get uncommittedChanges => 'Uncommittete Änderungen';
  @override
  String get closeDeskQuestion => 'Desk schließen?';
  @override
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} uncommittete Datei.',
        other: '${n} uncommittete Dateien.',
      );
  @override
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Commit vor main.',
        other: '${n} Commits vor main.',
      );
  @override
  String get willRemoveWorktreeDirectory =>
      'Das entfernt das Worktree-Verzeichnis.';
  @override
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Datei geändert',
        other: '${n} Dateien geändert',
      );
  @override
  String get shelveHere => 'Hier verstauen';
  @override
  String get discardAndClose => 'Verwerfen & schließen';
  @override
  String get noRepository => 'kein Repository';
  @override
  String get issuePromotedToRemote => 'Issue zum Remote befördert.';
  @override
  String get pushedToRemote => 'Zum Remote gepusht.';
  @override
  String get pulledFromRemote => 'Vom Remote gepullt.';
  @override
  String get remoteIssueNotFound => 'Remote-Issue nicht gefunden';
  @override
  String importedIssueLocally({required Object id}) =>
      '#${id} lokal importiert.';
  @override
  String get issueAbandoned => 'Issue aufgegeben.';
  @override
  String get abandonIssue => 'Issue aufgeben';
  @override
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      'Lokales Issue #${id} dauerhaft entfernen? Das löscht seine Ref und ist nicht rückgängig zu machen.';
  @override
  String get abandon => 'Aufgeben';
  @override
  String publishedBranch({required Object branch}) =>
      '${branch} veröffentlicht.';
  @override
  String get publishingEllipsis => 'Veröffentliche…';
  @override
  String get publish => 'Veröffentlichen';
  @override
  String get noRemoteConfigured =>
      'Kein Remote für dieses Repository konfiguriert.';
  @override
  String get jumpToDesk => 'Zum Desk springen';
  @override
  String get arrowOpen => '→ öffnen';
  @override
  String get openOnANewDesk => 'Auf einem neuen Desk öffnen';
  @override
  String get plusDesk => '+ Desk';
  @override
  String get plusSpace => '+ ';
  @override
  String get newBranchNameHint => 'neuer-branch-name';
  @override
  String get escLower => 'esc';
  @override
  String get plusNewDesk => '+ neuer Desk';
  @override
  String get fromHeadEllipsis => 'von HEAD...';
  @override
  String get viewAllBranches => 'Alle Branches ansehen';
  @override
  String get issuesLower => 'issues';
  @override
  String get newIssueLower => 'neues issue';
  @override
  String get noneLinked => 'nichts verknüpft';
  @override
  String get noOpenIssues => 'keine offenen Issues';
  @override
  String get createAndPushLower => 'erstellen + pushen';
  @override
  String get createLower => 'erstellen';
  @override
  String get remoteLower => 'remote';
  @override
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';
  @override
  String get promoteToRemote => 'Zum Remote befördern';
  @override
  String get pushToRemote => 'Zum Remote pushen';
  @override
  String get pullFromRemote => 'Vom Remote pullen';
  @override
  String get importLabel => 'Importieren';
  @override
  String get failedToCreateRepository =>
      'Repository konnte nicht erstellt werden.';
  @override
  String get openRepositoryLower => 'repository öffnen';
  @override
  String get newRepositoryLower => 'neues repository';
  @override
  String get back => 'Zurück';
  @override
  String get openRepositoryDialogTitle => 'Repository öffnen';
  @override
  String get createRepositoryDialogTitle => 'Repository erstellen';
  @override
  String get cloneTargetDialogTitle => 'Klon-Ziel';
  @override
  String get cloneToDialogTitle => 'Klonen nach';
  @override
  String get exportToDialogTitle => 'Exportieren nach';
  @override
  String get createFromTemplateInDialogTitle => 'Aus Vorlage erstellen in';
  @override
  String get notAGitRepoInitConfirm =>
      'Kein Git-Repository. Hier eins initialisieren?';
  @override
  String get repositoryUrlRequired => 'Repository-URL erforderlich.';
  @override
  String get failedToCloneRepository =>
      'Repository konnte nicht geklont werden.';
  @override
  String cloningEllipsis({required Object name}) => 'Klone ${name}...';
  @override
  String get cloneCancelled => 'Klon abgebrochen.';
  @override
  String get noProjectsYet => 'Noch keine Projekte';
  @override
  String get dissolveGroup => 'Gruppe auflösen';
  @override
  String get projectsHeader => 'Projekte';
  @override
  String get cloneLabel => 'Klonen';
  @override
  String get createLabel => 'Erstellen';
  @override
  String get openLabel => 'Öffnen';
  @override
  String get repositoryUrlPlaceholder => 'Repository-URL';
  @override
  String get projectNameOrFullPathPlaceholder =>
      'projekt-name oder voller Pfad';
  @override
  String get pathToProjectPlaceholder => '/pfad/zum/projekt';
  @override
  String get cloneToFolderPathPlaceholder => 'Klon-Zielordnerpfad';
  @override
  String get switchToCreateRepo => 'Zu Repo erstellen wechseln';
  @override
  String get explorer => 'Explorer';
  @override
  String get terminal => 'Terminal';
  @override
  String get cloneUrl => 'Klon-URL';
  @override
  String get copyPath => 'Pfad kopieren';
  @override
  String get export => 'Exportieren';
  @override
  String get readme => 'README';
  @override
  String get duplicate => 'Duplizieren';
  @override
  String get template => 'Vorlage';
  @override
  String get forgetThisProject => 'Dieses Projekt vergessen';
  @override
  String get aiKindCommitMessage => 'commit-nachricht';
  @override
  String get aiKindReview => 'review';
  @override
  String get aiKindMuse => 'muse';
  @override
  String get aiKindPresent => 'präsentieren';
  @override
  String get aiKindDebug => 'debug';
  @override
  String aiStatusRunning({required Object kind}) => '${kind} läuft';
  @override
  String aiStatusFailedUnread({required Object kind}) =>
      '${kind} fehlgeschlagen (ungelesen)';
  @override
  String aiStatusReadyUnread({required Object kind}) =>
      '${kind} bereit (ungelesen)';
  @override
  String get filesLower => 'dateien';
  @override
  String get commitsLower => 'commits';
  @override
  String get undoLabel => 'Rückgängig';
  @override
  String get goLabel => 'los';
  @override
  String countdownSeconds({required Object n}) => '${n}s';
  @override
  String get collapseGlyph => '▲ einklappen';
  @override
  String moreLinesGlyph({required Object n}) => '▼ ${n} weitere Zeilen';
}

// Path: backend
class _Translations$backend$de extends Translations$backend$en {
  _Translations$backend$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$backend$ops$de ops = _Translations$backend$ops$de._(
    _root,
  );
  @override
  late final _Translations$backend$mergeOutcome$de mergeOutcome =
      _Translations$backend$mergeOutcome$de._(_root);
}

// Path: branches
class _Translations$branches$de extends Translations$branches$en {
  _Translations$branches$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get runningAiReview => 'AI-Review läuft…';
  @override
  String prNumberLabel({required Object number}) => 'PR #${number}';
  @override
  String get findings => 'FUNDE';
  @override
  String get observations => 'BEOBACHTUNGEN';
  @override
  String get renameEllipsis => 'Umbenennen…';
  @override
  String get publish => 'Veröffentlichen';
  @override
  String publishFailed({required Object error}) =>
      'Veröffentlichen fehlgeschlagen: ${error}';
  @override
  String couldntOpenDesk({required Object error}) =>
      'Desk konnte nicht geöffnet werden: ${error}';
  @override
  String syncFailed({required Object error}) => 'Sync fehlgeschlagen: ${error}';
  @override
  String get renameBranchTitle => 'Branch umbenennen';
  @override
  String get newNameHint => 'neuer Name';
  @override
  String get rename => 'Umbenennen';
  @override
  String invalidBranchName({required Object name}) =>
      '\'${name}\' ist kein gültiger Branch-Name.';
  @override
  String renameFailed({required Object error}) =>
      'Umbenennen fehlgeschlagen: ${error}';
  @override
  String deletingBranch({required Object name}) => 'Lösche ${name}';
  @override
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '\'${name}\' ist im Desk \'${desk}\' geöffnet.';
  @override
  String get openDesk => 'Desk öffnen';
  @override
  String openInDeskShort({required Object desk}) =>
      'in Desk \'${desk}\' öffnen';
  @override
  String get couldNotPinBranch =>
      'Branch-Spitze konnte nicht fixiert werden; Löschen übersprungen';
  @override
  String get couldNotPinTag =>
      'Tag konnte nicht fixiert werden; Löschen übersprungen';
  @override
  String deletingTag({required Object name}) => 'Lösche Tag ${name}';
  @override
  String get applyToActiveChanges => 'Auf aktive Änderungen anwenden…';
  @override
  String get couldNotLoadPrDiff => 'PR-Diff konnte nicht geladen werden.';
  @override
  String prSourceLabel({required Object number, required Object title}) =>
      'PR #${number}: ${title}';
  @override
  String mergeIntoDesk({required Object branch}) => 'In ${branch} mergen…';
  @override
  String get checkoutThisPr => 'Diesen PR auschecken';
  @override
  String get mergeIntoNewDesk => 'In neuen Desk mergen…';
  @override
  String get pushToForge => 'Zur Forge pushen';
  @override
  String get linkToIssue => 'Mit Issue verknüpfen…';
  @override
  String get gitPatch => '↓ git-patch';
  @override
  String get copyBranchName => 'Branch-Namen kopieren';
  @override
  String copiedRef({required Object ref}) => '"${ref}" kopiert';
  @override
  String get reviewPr => 'PR reviewen';
  @override
  String get openInBrowser => 'Im Browser öffnen';
  @override
  String get markAsRead => 'Als gelesen markieren';
  @override
  String get markAsUnread => 'Als ungelesen markieren';
  @override
  String get replaceLocalCommitsTitle => 'Lokale Commits ersetzen?';
  @override
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref} hat lokale Commits, die nicht auf dem Remote-PR-Head sind. Beim Aktualisieren werden sie durch den neuesten Stand vom Remote ersetzt.';
  @override
  String get update => 'Aktualisieren';
  @override
  String couldntFetchPr({required Object error}) =>
      'PR konnte nicht abgerufen werden: ${error}';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Konnte nicht als Desk öffnen: ${error}';
  @override
  String couldntOpenInBrowser({required Object error}) =>
      'Konnte nicht im Browser öffnen: ${error}';
  @override
  String get noIssuesYetLocal =>
      'Noch keine Issues. Öffne eins upstream oder nutze "+ neues lokales Issue" in der Issues-Linse.';
  @override
  String get remotePrsLinkLocalOnly =>
      'Remote-PRs können nur mit lokalen Issues verknüpft werden. Erstelle eins mit "+ neues lokales Issue".';
  @override
  String linkPrToIssues({required Object number}) =>
      'PR #${number} mit Issue(s) verknüpfen';
  @override
  String get noPrsYetLocal =>
      'Noch keine PRs. Öffne einen upstream oder befördere einen Desk zum PR.';
  @override
  String get remoteIssuesLinkLocalOnly =>
      'Remote-Issues können nur mit lokalen PRs verknüpft werden. Befördere zuerst einen Desk zum PR.';
  @override
  String linkIssueToPrs({required Object number}) =>
      'Issue #${number} mit PR(s) verknüpfen';
  @override
  String couldntToggleLink({required Object error}) =>
      'Verknüpfung konnte nicht umgeschaltet werden: ${error}';
  @override
  String get openPatchDialogTitle => 'Patch öffnen (.patch / .diff)';
  @override
  String get clipboardNoText => 'Zwischenablage enthält keinen Text.';
  @override
  String get clipboardPatchLabel => 'clipboard.patch';
  @override
  String failedToOpenPatch({required Object error}) =>
      'Patch konnte nicht geöffnet werden: ${error}';
  @override
  String get patchEmptyOrUnparseable => 'Patch ist leer oder nicht parsbar.';
  @override
  String get prPushedToForge => 'PR zur Forge gepusht.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      '${ref} mit dem neuesten Stand vom Remote überschreiben?';
  @override
  String get overwrite => 'Überschreiben';
  @override
  String get loadingBranchesTitle => 'Lade Branches';
  @override
  String get loadingBranchesMessage => 'Lese lokale Branches und Tags.';
  @override
  String get branchesUnavailableTitle => 'Branches nicht verfügbar';
  @override
  String get filterPullRequestsHint => 'pull requests filtern…';
  @override
  String get filterIssuesHint => 'issues filtern…';
  @override
  String get branchNameHint => 'Branch-Name';
  @override
  String get tagsNewestFirst => 'Tags, neueste zuerst';
  @override
  String get tagsOldestFirst => 'Tags, älteste zuerst';
  @override
  String get flipSortDirection => 'Sortierrichtung umkehren';
  @override
  String get readingPullRequests => 'Lese Pull Requests…';
  @override
  String get noOpenPullRequests => 'Keine offenen Pull Requests';
  @override
  String get noPullRequestsHint =>
      'Öffne einen aus einem Branch oder befördere einen Desk.';
  @override
  String get noPrsMatchFilters => 'Keine PRs passen zu diesen Filtern';
  @override
  String get toggleFiltersRowAbove =>
      'Schalte die Filter in der Zeile darüber aus.';
  @override
  String get issuesNewestFirst => 'Issues, neueste zuerst';
  @override
  String get issuesOldestFirst => 'Issues, älteste zuerst';
  @override
  String get issuesHeading => 'ISSUES';
  @override
  String get readingIssuesLower => 'lese issues…';
  @override
  String get noOpenIssues => 'Keine offenen Issues';
  @override
  String get noIssuesHint => '+ neu, um Arbeit und Bugs zu verfolgen.';
  @override
  String get nothingMatches => 'Nichts passt';
  @override
  String get toggleFiltersAbove => 'Schalte die Filter oben aus.';
  @override
  String get bucketFresh => 'FRISCH';
  @override
  String get bucketThisWeek => 'DIESE WOCHE';
  @override
  String get bucketStalled => 'STOCKEND';
  @override
  String get bucketOlder => 'ÄLTER';
  @override
  String get couldNotResolveMainWorktree =>
      'Der Pfad des Haupt-Worktrees konnte nicht aufgelöst werden.';
  @override
  String couldntSubmitReview({required Object error}) =>
      'Review konnte nicht eingereicht werden: ${error}';
  @override
  String get reviewAiNotAvailable => 'Review-AI ist noch nicht verfügbar.';
  @override
  String get noReviewModelConfigured => 'Kein Review-Modell konfiguriert.';
  @override
  String get deskFallback => 'Desk';
  @override
  String deskUncommittedChanges({
    required num n,
    required Object branch,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    n,
    one:
        '${branch} hat ${n} uncommittete Änderung — committe oder stashe zuerst.',
    other:
        '${branch} hat ${n} uncommittete Änderungen — committe oder stashe zuerst.',
  );
  @override
  String get targetDeskNoBranch => 'Ziel-Desk hat keinen Branch.';
  @override
  String mergePrIntoDesk({required Object number, required Object branch}) =>
      'PR #${number} in ${branch} mergen';
  @override
  String get conflictCheckUnavailableVersion =>
      'Konfliktprüfung nicht verfügbar — git 2.38+ erforderlich';
  @override
  String get conflictCheckUnavailable => 'Konfliktprüfung nicht verfügbar';
  @override
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'KONFLIKT DROHT · ${n} Datei',
        other: 'KONFLIKT DROHT · ${n} Dateien',
      );
  @override
  String plusMore({required Object n}) => '+${n} mehr';
  @override
  String get rebase => 'Rebase';
  @override
  String get squash => 'Squash';
  @override
  String get mergeCommit => 'Merge-Commit';
  @override
  String noDeskForBranch({required Object branch}) =>
      'Kein Desk für Branch ${branch} gefunden';
  @override
  String get mergeAnyway => 'Trotzdem mergen';
  @override
  String get readingIssues => 'Lese Issues…';
  @override
  String get openUpstreamOrLocal => 'Öffne eins upstream oder ein lokales.';
  @override
  String get noIssuesMatchFilters => 'Keine Issues passen zu diesen Filtern';
  @override
  String couldntCreateIssue({required Object error}) =>
      'Issue konnte nicht erstellt werden: ${error}';
  @override
  String get promoteToRemote => 'Zum Remote befördern';
  @override
  String get pushToRemote => 'Zum Remote pushen';
  @override
  String get pullFromRemote => 'Vom Remote pullen';
  @override
  String get import => 'Importieren';
  @override
  String get linkToPr => 'Mit PR verknüpfen…';
  @override
  String get abandon => 'Aufgeben';
  @override
  String get issuePromotedToRemote => 'Issue zum Remote befördert.';
  @override
  String get issuePushedToRemote => 'Zum Remote gepusht.';
  @override
  String get issuePulledFromRemote => 'Vom Remote gepullt.';
  @override
  String issueImportedLocally({required Object number}) =>
      '#${number} lokal importiert.';
  @override
  String get abandonIssueTitle => 'Issue aufgeben';
  @override
  String abandonIssueMessage({required Object id}) =>
      'Lokales Issue #${id} dauerhaft entfernen? Das löscht seine Ref und ist nicht rückgängig zu machen.';
  @override
  String couldntAbandon({required Object error}) =>
      'Aufgeben fehlgeschlagen: ${error}';
  @override
  String couldntPostComment({required Object error}) =>
      'Kommentar konnte nicht gepostet werden: ${error}';
  @override
  String couldntCloseIssue({required Object error}) =>
      'Issue konnte nicht geschlossen werden: ${error}';
  @override
  String couldntAddLabel({required Object error}) =>
      'Label konnte nicht hinzugefügt werden: ${error}';
  @override
  String get lensBranches => 'BRANCHES';
  @override
  String get lensPrs => 'PRs';
  @override
  String get patchUp => '↑ patch';
  @override
  String get syncRibbon => '⇅ sync';
  @override
  String get kbHeading => 'TASTATUR';
  @override
  String get kbNavigateRows => 'Zeilen navigieren';
  @override
  String get kbExpandCollapse => 'fokussierte Zeile aus-/einklappen';
  @override
  String get kbCheckoutPr => 'fokussierten PR lokal auschecken';
  @override
  String get kbApproveReview => 'freigeben · review';
  @override
  String get kbRequestChanges => 'Änderungen anfordern';
  @override
  String get kbFocusSearch => 'Suche fokussieren';
  @override
  String get kbSwitchLens => 'Linse wechseln (branches · prs)';
  @override
  String get kbToggleOverlay => 'dieses Overlay umschalten';
  @override
  String get kbPressToDismiss => 'beliebige Stelle drücken zum Schließen';
  @override
  String get overrideScarTooltip =>
      'mit fehlgeschlagenen Checks oder ohne freigebendes Review gemergt — untersuche es zuerst unter Beschuss';
  @override
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Datei überschneidet deine uncommittete Arbeit',
        other: '${n} Dateien überschneiden deine uncommittete Arbeit',
      );
  @override
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '#${pr}  (${n} Datei)',
        other: '#${pr}  (${n} Dateien)',
      );
  @override
  String get prStateDraft => 'DRAFT';
  @override
  String get localBadge => 'LOKAL';
  @override
  String get myReviewPending => 'dein Review ausstehend';
  @override
  String get myReviewApproved => 'du ✓';
  @override
  String get myReviewChangesRequested => 'du ✗ Änderungen angefordert';
  @override
  String get myReviewCommented => 'du kommentiert';
  @override
  String get myReviewDefault => 'du';
  @override
  String tailCommentsAuthor({required Object count}) =>
      '${count} Kommentare · letzter vom Autor gezeigt';
  @override
  String get tailLastComment => 'letzter Kommentar';
  @override
  String tailLastReviewState({required Object state}) =>
      'letztes Review · ${state}';
  @override
  String get tailLastReview => 'letztes Review';
  @override
  String tailLastCheckState({required Object state}) =>
      'letzter Check · ${state}';
  @override
  String get tailLastCommit => 'letzter Commit';
  @override
  String get tailLastActivity => 'letzte Aktivität';
  @override
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'schließt ${n} Issue — klicken zum Springen',
        other: 'schließt ${n} Issues — klicken zum Springen',
      );
  @override
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'bearbeitet durch ${n} PR — klicken zum Springen',
        other: 'bearbeitet durch ${n} PRs — klicken zum Springen',
      );
  @override
  String get checksLabel => 'checks';
  @override
  String get reviewersLabel => 'reviewer';
  @override
  String get conflictsLabel => 'konflikte';
  @override
  String exportFailed({required Object error}) =>
      'Export fehlgeschlagen: ${error}';
  @override
  String get readingFiles => 'lese Dateien…';
  @override
  String get noDetailAvailable => 'kein Detail verfügbar';
  @override
  String get noFilesReported => 'keine Dateien gemeldet';
  @override
  String get readingGitHistory => 'lese Git-Historie…';
  @override
  String get knowsThisCode => 'kennt diesen Code';
  @override
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Commit auf diesen Dateien im letzten Jahr',
        other: '${n} Commits auf diesen Dateien im letzten Jahr',
      );
  @override
  String get willFight => 'WIRD KÄMPFEN';
  @override
  String orbitalPartnerCos({required Object cos}) =>
      'Orbitalpartner — cos ${cos}';
  @override
  String get orbitLabel => 'orbit';
  @override
  String get touchesYourLocalWork => 'BERÜHRT DEINE LOKALE ARBEIT';
  @override
  String get mergingWillConflict =>
      'Mergen wird wahrscheinlich mit deinen uncommitteten Änderungen kollidieren';
  @override
  String get closesHeading => 'SCHLIESST';
  @override
  String get filesHeading => 'DATEIEN';
  @override
  String get orientAligned => 'ausgerichtet';
  @override
  String get orientAdjacent => 'benachbart';
  @override
  String get orientOrthogonal => 'orthogonal';
  @override
  String shapeField({required Object v}) => 'feld ${v}';
  @override
  String shapeSource({required Object v}) => 'quelle ${v}';
  @override
  String shapeSrcDelta({required Object v}) => 'quelleΔ ${v}';
  @override
  String shapeFldDelta({required Object v}) => 'feldΔ ${v}';
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
  String resonanceReadout({required Object v}) => 'resonanz ${v}';
  @override
  String ghostFileTooltip({required Object path}) =>
      'bewegt sich meist mit den Dateien in diesem PR\n(${path})';
  @override
  String get prStateDraftLower => 'entwurf';
  @override
  String get keystoneTooltip => 'Schlussstein — repo-weite Brückendatei';
  @override
  String get reviewNoteHint => 'hinterlasse eine Notiz (optional)…';
  @override
  String get reviewComment => 'kommentar';
  @override
  String get reviewRequestChanges => 'änderungen anfordern';
  @override
  String get reviewApprove => '✓ freigeben';
  @override
  String get actionPatchDown => '↓ patch';
  @override
  String get actionPrReview => '✦ pr-review';
  @override
  String get actionOpenAsDesk => '⊞ als desk öffnen';
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
  String get deleteBranchAfter => 'Branch danach löschen';
  @override
  String checkDurationSec({required Object n}) => '${n}s';
  @override
  String checkDurationMin({required Object m, required Object s}) =>
      '${m}m ${s}s';
  @override
  String assignedTo({required Object names}) => 'zugewiesen: ${names}';
  @override
  String issueConvLine({required Object n, required Object time}) =>
      '${n} unterh. · ${time}';
  @override
  String get readingThread => 'lese Thread…';
  @override
  String get addressedByHeading => 'BEARBEITET DURCH';
  @override
  String get descriptionHeading => 'BESCHREIBUNG';
  @override
  String get threadHeading => 'THREAD';
  @override
  String get replyHint => 'antworten…';
  @override
  String get assignMe => 'mir zuweisen';
  @override
  String get closeLower => 'schließen';
  @override
  String get postReply => '↩ posten';
  @override
  String get remoteProviderUnavailable => 'Remote-Anbieter nicht verfügbar';
  @override
  String get noRecognisedRemoteHost =>
      'Kein erkannter Remote-Host für dieses Repo.';
  @override
  String get corpseGone => 'weg';
  @override
  String get corpseAbsorbed => 'absorbiert';
  @override
  String get corpseSquashed => 'gesquasht';
  @override
  String absorbedDeliveredIn({required Object hash}) => 'geliefert in ${hash}';
  @override
  String get absorbedNoChanges => 'Mergen fügt keine Änderungen hinzu';
  @override
  String get corpseTagUpstreamGone => 'Upstream weg';
  @override
  String corpseTagAbsorbed({required Object receipt}) =>
      'absorbiert, ${receipt}';
  @override
  String get corpseTagSquashed => 'gesquasht und gemergt';
  @override
  String semanticsCurrentBranch({required Object name}) =>
      '${name}, aktueller Branch';
  @override
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}, verfolgt ${upstream}';
  @override
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}, ${tag}';
  @override
  String semanticsWorktreeOpen({required Object label}) =>
      '${label}, Worktree offen';
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
  String get crossLinkDesk => 'Desk';
  @override
  String get crossLinkPr => 'PR';
  @override
  String get crossLinkPrDraft => 'PR · Entwurf';
  @override
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Issue',
        other: '${n} Issues',
      );
  @override
  String get headBadge => 'HEAD';
  @override
  String trackingLine({required Object upstream}) => '→ verfolgt: ${upstream}';
  @override
  String get checkoutButton => 'Checkout';
  @override
  String get createBranch => 'Branch erstellen';
  @override
  String get newBranchName => 'Neuer Branch-Name';
  @override
  String newBranchNameError({required Object error}) =>
      'Neuer Branch-Name — ${error}';
  @override
  String get forceDelete => 'Erzwingen?';
  @override
  String get annotated => 'annotiert';
  @override
  String get applyCheckFailed => 'apply --check fehlgeschlagen';
  @override
  String get openPatchFrom => 'PATCH ÖFFNEN VON';
  @override
  String get patchFromFile => 'aus Datei…';
  @override
  String get patchFromFileHint => '.patch / .diff';
  @override
  String get patchFromClipboard => 'aus Zwischenablage';
  @override
  String get patchFromClipboardHint => 'Text einfügen';
  @override
  String get patchPreviewHeading => 'PATCH-VORSCHAU';
  @override
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';
  @override
  String get stagedDone => 'gestaged.';
  @override
  String get appliedDone => 'angewendet.';
  @override
  String get opening => 'öffne…';
  @override
  String get mergeEditor => '⇋ merge-editor';
  @override
  String get staging => 'stage…';
  @override
  String get applying => 'wende an…';
  @override
  String get stage => 'stage';
  @override
  String get apply => 'anwenden';
  @override
  String get refineHint =>
      'verfeinern… (z. B. "auch die Logger-Änderungen weglassen")';
  @override
  String get reverseArmedTooltip =>
      'scharf — das nächste Anwenden REVERTIERT den Patch (-R)';
  @override
  String get reverseDisarmedTooltip =>
      'Reverse scharfstellen (-R) — rückgängig statt anwenden';
  @override
  String get reverseArmedLabel => '⟲ reverse ✓';
  @override
  String get reverseLabel => '⟲ reverse';
  @override
  String get untouchedHeading => '⚠ UNBERÜHRT';
  @override
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${count} von ${n} Datei nicht im Patch',
        other: '${count} von ${n} Dateien nicht im Patch',
      );
  @override
  String get staysConflicted =>
      'diese Dateien bleiben in Konflikt — das Anwenden staged sie nicht';
  @override
  String get orWith => 'ODER MIT';
  @override
  String get noAiModelConfigured => 'kein AI-Modell konfiguriert';
  @override
  String applyWithPatchFrom({required Object label}) =>
      'mit Patch von ${label} anwenden';
  @override
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => 'mit Patch von ${label} anwenden  ·  ${model}';
  @override
  String get patching => 'patche…';
  @override
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  mit Patch von ${label} anwenden';
  @override
  String get orWithAnotherModel => 'oder mit einem anderen Modell';
  @override
  String get applyCheckPassed =>
      'git apply --check bestanden — Patch wird sauber angewendet';
  @override
  String get gitApplyCheckFailed => 'git apply --check fehlgeschlagen';
  @override
  String get appliesClean => 'wird sauber angewendet';
  @override
  String get willNotApply => 'wird nicht angewendet';
  @override
  String get newLocalIssue => 'neues lokales Issue';
  @override
  String get filterHint => 'filtern…';
  @override
  String get nothingToLink => 'Noch nichts zu verknüpfen.';
  @override
  String get nothingMatchesDot => 'Nichts passt.';
  @override
  String get relevantHeading => 'RELEVANT';
  @override
  String get allHeading => 'ALLE';
  @override
  String get doneLower => 'fertig';
  @override
  String get candidateRemote => 'R';
  @override
  String get candidateLocal => 'L';
  @override
  String get newLocalIssueTitle => 'Neues lokales Issue';
  @override
  String get titleHint => 'Titel';
  @override
  String get bodyHint => 'Text (Markdown)';
  @override
  String get cancelLower => 'abbrechen';
  @override
  String get createLower => 'erstellen';
  @override
  String get deleteFailed => 'Löschen fehlgeschlagen';
  @override
  String reviewFailed({required Object error}) =>
      'Review fehlgeschlagen: ${error}';
  @override
  String get resolutionFailed => 'Auflösung fehlgeschlagen';
  @override
  String get patchBlocksNoCover =>
      'Modell lieferte Patch-Blöcke, die die fehlschlagenden Dateien nicht abdeckten';
  @override
  String get applyFailed => 'Anwenden fehlgeschlagen';
  @override
  String get emptyOrUnparseablePatch =>
      'Modell lieferte einen leeren oder nicht parsbaren Patch';
  @override
  String noModelConfiguredFor({required Object label}) =>
      'kein Modell konfiguriert für "${label}"';
}

// Path: changes
class _Translations$changes$de extends Translations$changes$en {
  _Translations$changes$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$usage$de usage =
      _Translations$changes$usage$de._(_root);
  @override
  late final _Translations$changes$tabs$de tabs =
      _Translations$changes$tabs$de._(_root);
  @override
  late final _Translations$changes$tabStrip$de tabStrip =
      _Translations$changes$tabStrip$de._(_root);
  @override
  late final _Translations$changes$select$de select =
      _Translations$changes$select$de._(_root);
  @override
  late final _Translations$changes$constellationToggle$de constellationToggle =
      _Translations$changes$constellationToggle$de._(_root);
  @override
  late final _Translations$changes$nudgeChip$de nudgeChip =
      _Translations$changes$nudgeChip$de._(_root);
  @override
  late final _Translations$changes$minimap$de minimap =
      _Translations$changes$minimap$de._(_root);
  @override
  late final _Translations$changes$tagInput$de tagInput =
      _Translations$changes$tagInput$de._(_root);
  @override
  late final _Translations$changes$composer$de composer =
      _Translations$changes$composer$de._(_root);
  @override
  late final _Translations$changes$commit$de commit =
      _Translations$changes$commit$de._(_root);
  @override
  late final _Translations$changes$rebase$de rebase =
      _Translations$changes$rebase$de._(_root);
  @override
  late final _Translations$changes$editor$de editor =
      _Translations$changes$editor$de._(_root);
  @override
  late final _Translations$changes$editorTitles$de editorTitles =
      _Translations$changes$editorTitles$de._(_root);
  @override
  late final _Translations$changes$askHint$de askHint =
      _Translations$changes$askHint$de._(_root);
  @override
  late final _Translations$changes$fileMenu$de fileMenu =
      _Translations$changes$fileMenu$de._(_root);
  @override
  late final _Translations$changes$multiFileMenu$de multiFileMenu =
      _Translations$changes$multiFileMenu$de._(_root);
  @override
  late final _Translations$changes$ignoreMenu$de ignoreMenu =
      _Translations$changes$ignoreMenu$de._(_root);
  @override
  late final _Translations$changes$discard$de discard =
      _Translations$changes$discard$de._(_root);
  @override
  late final _Translations$changes$snack$de snack =
      _Translations$changes$snack$de._(_root);
  @override
  late final _Translations$changes$trace$de trace =
      _Translations$changes$trace$de._(_root);
  @override
  late final _Translations$changes$cleanTree$de cleanTree =
      _Translations$changes$cleanTree$de._(_root);
  @override
  late final _Translations$changes$guardrail$de guardrail =
      _Translations$changes$guardrail$de._(_root);
  @override
  late final _Translations$changes$dropHint$de dropHint =
      _Translations$changes$dropHint$de._(_root);
  @override
  late final _Translations$changes$diffEmpty$de diffEmpty =
      _Translations$changes$diffEmpty$de._(_root);
  @override
  late final _Translations$changes$shelvePill$de shelvePill =
      _Translations$changes$shelvePill$de._(_root);
  @override
  late final _Translations$changes$stashAction$de stashAction =
      _Translations$changes$stashAction$de._(_root);
  @override
  late final _Translations$changes$stashContents$de stashContents =
      _Translations$changes$stashContents$de._(_root);
  @override
  late final _Translations$changes$stashFile$de stashFile =
      _Translations$changes$stashFile$de._(_root);
  @override
  late final _Translations$changes$fileRow$de fileRow =
      _Translations$changes$fileRow$de._(_root);
  @override
  late final _Translations$changes$resolveStrip$de resolveStrip =
      _Translations$changes$resolveStrip$de._(_root);
  @override
  late final _Translations$changes$badge$de badge =
      _Translations$changes$badge$de._(_root);
  @override
  late final _Translations$changes$review$de review =
      _Translations$changes$review$de._(_root);
  @override
  late final _Translations$changes$commitBtn$de commitBtn =
      _Translations$changes$commitBtn$de._(_root);
  @override
  late final _Translations$changes$shapeBtn$de shapeBtn =
      _Translations$changes$shapeBtn$de._(_root);
  @override
  late final _Translations$changes$dejaVu$de dejaVu =
      _Translations$changes$dejaVu$de._(_root);
  @override
  late final _Translations$changes$identity$de identity =
      _Translations$changes$identity$de._(_root);
  @override
  late final _Translations$changes$staleScope$de staleScope =
      _Translations$changes$staleScope$de._(_root);
  @override
  late final _Translations$changes$finding$de finding =
      _Translations$changes$finding$de._(_root);
  @override
  late final _Translations$changes$muse$de muse =
      _Translations$changes$muse$de._(_root);
  @override
  late final _Translations$changes$debug$de debug =
      _Translations$changes$debug$de._(_root);
  @override
  late final _Translations$changes$includeSummary$de includeSummary =
      _Translations$changes$includeSummary$de._(_root);
  @override
  late final _Translations$changes$status$de status =
      _Translations$changes$status$de._(_root);
  @override
  late final _Translations$changes$stash$de stash =
      _Translations$changes$stash$de._(_root);
  @override
  late final _Translations$changes$tooltips$de tooltips =
      _Translations$changes$tooltips$de._(_root);
  @override
  late final _Translations$changes$mergeEditor$de mergeEditor =
      _Translations$changes$mergeEditor$de._(_root);
  @override
  late final _Translations$changes$conflictResolution$de conflictResolution =
      _Translations$changes$conflictResolution$de._(_root);
  @override
  late final _Translations$changes$mergeFlow$de mergeFlow =
      _Translations$changes$mergeFlow$de._(_root);
  @override
  late final _Translations$changes$constellation$de constellation =
      _Translations$changes$constellation$de._(_root);
}

// Path: common
class _Translations$common$de extends Translations$common$en {
  _Translations$common$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get listSeparator => ', ';
  @override
  String get cancel => 'Abbrechen';
  @override
  String get close => 'Schließen';
  @override
  String get save => 'Speichern';
  @override
  String get delete => 'Löschen';
  @override
  String get retry => 'Wiederholen';
  @override
  String get copy => 'Kopieren';
  @override
  String get copied => 'Kopiert';
  @override
  String get done => 'Fertig';
  @override
  String get loading => 'Lädt…';
  @override
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Datei',
        other: '${n} Dateien',
      );
  @override
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Commit',
        other: '${n} Commits',
      );
  @override
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Branch',
        other: '${n} Branches',
      );
  @override
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} lokaler Commit',
        other: '${n} lokale Commits',
      );
  @override
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Remote-Commit',
        other: '${n} Remote-Commits',
      );
  @override
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Datei mit Konflikt',
        other: '${n} Dateien mit Konflikt',
      );
  @override
  late final _Translations$common$time$de time = _Translations$common$time$de._(
    _root,
  );
  @override
  late final _Translations$common$size$de size = _Translations$common$size$de._(
    _root,
  );
}

// Path: diff
class _Translations$diff$de extends Translations$diff$en {
  _Translations$diff$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$diff$status$de status =
      _Translations$diff$status$de._(_root);
  @override
  late final _Translations$diff$toolbar$de toolbar =
      _Translations$diff$toolbar$de._(_root);
  @override
  late final _Translations$diff$hunkDropdown$de hunkDropdown =
      _Translations$diff$hunkDropdown$de._(_root);
  @override
  String stagingFailed({required Object error}) =>
      'Teilweises Stagen fehlgeschlagen: ${error}';
  @override
  late final _Translations$diff$trail$de trail = _Translations$diff$trail$de._(
    _root,
  );
  @override
  late final _Translations$diff$pinned$de pinned =
      _Translations$diff$pinned$de._(_root);
  @override
  late final _Translations$diff$hunkHint$de hunkHint =
      _Translations$diff$hunkHint$de._(_root);
  @override
  late final _Translations$diff$binary$de binary =
      _Translations$diff$binary$de._(_root);
  @override
  late final _Translations$diff$media$de media = _Translations$diff$media$de._(
    _root,
  );
}

// Path: filament
class _Translations$filament$de extends Translations$filament$en {
  _Translations$filament$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get noRepositoryOpen => 'Kein Repository geöffnet.';
  @override
  String scanningProgress({required Object scanned, required Object total}) =>
      'scanne ${scanned} / ${total} Dateien…';
  @override
  String findingsAcrossFiles({required Object count, required Object files}) =>
      '${count} Funde in ${files} Dateien';
  @override
  String copiedFindings({required Object count}) => '${count} Funde kopiert';
  @override
  String get copy => 'KOPIEREN';
  @override
  String get noFindings => 'Keine Funde im Ausführungsfluss.';
  @override
  late final _Translations$filament$severity$de severity =
      _Translations$filament$severity$de._(_root);
  @override
  late final _Translations$filament$kind$de kind =
      _Translations$filament$kind$de._(_root);
  @override
  String lineLabel({required Object line}) => 'Z${line}';
  @override
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class _Translations$history$de extends Translations$history$en {
  _Translations$history$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$de commitLede =
      _Translations$history$commitLede$de._(_root);
  @override
  late final _Translations$history$seismograph$de seismograph =
      _Translations$history$seismograph$de._(_root);
  @override
  late final _Translations$history$worldline$de worldline =
      _Translations$history$worldline$de._(_root);
  @override
  late final _Translations$history$contextMenu$de contextMenu =
      _Translations$history$contextMenu$de._(_root);
  @override
  late final _Translations$history$cherryPick$de cherryPick =
      _Translations$history$cherryPick$de._(_root);
  @override
  late final _Translations$history$revert$de revert =
      _Translations$history$revert$de._(_root);
  @override
  late final _Translations$history$reflog$de reflog =
      _Translations$history$reflog$de._(_root);
  @override
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'Dieser Commit liegt tiefer als der ${n} geladene Commit.',
        other: 'Dieser Commit liegt tiefer als die ${n} geladenen Commits.',
      );
  @override
  String deleteTagFailed({required Object error}) =>
      'Tag konnte nicht gelöscht werden: ${error}';
  @override
  String get loadingTitle => 'Lade Verlauf';
  @override
  String get loadingMessage => 'Lese jüngste Commits.';
  @override
  String get unavailableTitle => 'Verlauf nicht verfügbar';
  @override
  String get toggleWorldline => 'Weltlinie umschalten';
  @override
  String get pageTitle => 'Verlauf';
  @override
  String get viewingLast => 'Zeige letzte';
  @override
  String get commitsUnit => 'Commits';
  @override
  String get noCommitSelectedTitle => 'Kein Commit ausgewählt';
  @override
  String get noCommitSelectedMessage =>
      'Wähle einen Commit, um seine Änderungen zu untersuchen.';
  @override
  String get loadingCommitTitle => 'Lade Commit';
  @override
  String get loadingCommitMessage => 'Lese Commit-Details.';
  @override
  String get commitUnavailableTitle => 'Commit nicht verfügbar';
  @override
  String get couldNotLoadCommit => 'Commit konnte nicht geladen werden.';
  @override
  String get reflogDividerLabel => 'reflog';
  @override
  String get loadReflog => 'Reflog laden';
  @override
  String get createTag => 'Tag erstellen';
  @override
  String get newTagName => 'Neuer Tag-Name';
  @override
  String newTagNameError({required Object error}) =>
      'Neuer Tag-Name — ${error}';
  @override
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Datei · alle Änderungen',
        other: '${n} Dateien · alle Änderungen',
      );
  @override
  String get allChangesLabel => 'alle Änderungen';
  @override
  late final _Translations$history$rebase$de rebase =
      _Translations$history$rebase$de._(_root);
  @override
  late final _Translations$history$inFlight$de inFlight =
      _Translations$history$inFlight$de._(_root);
}

// Path: historySurgery
class _Translations$historySurgery$de extends Translations$historySurgery$en {
  _Translations$historySurgery$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$historySurgery$chrome$de chrome =
      _Translations$historySurgery$chrome$de._(_root);
  @override
  late final _Translations$historySurgery$select$de select =
      _Translations$historySurgery$select$de._(_root);
  @override
  late final _Translations$historySurgery$understand$de understand =
      _Translations$historySurgery$understand$de._(_root);
  @override
  late final _Translations$historySurgery$confirm$de confirm =
      _Translations$historySurgery$confirm$de._(_root);
  @override
  late final _Translations$historySurgery$execute$de execute =
      _Translations$historySurgery$execute$de._(_root);
  @override
  late final _Translations$historySurgery$verify$de verify =
      _Translations$historySurgery$verify$de._(_root);
  @override
  late final _Translations$historySurgery$forcePush$de forcePush =
      _Translations$historySurgery$forcePush$de._(_root);
}

// Path: onboarding
class _Translations$onboarding$de extends Translations$onboarding$en {
  _Translations$onboarding$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$nav$de nav =
      _Translations$onboarding$nav$de._(_root);
  @override
  late final _Translations$onboarding$naming$de naming =
      _Translations$onboarding$naming$de._(_root);
  @override
  late final _Translations$onboarding$theme$de theme =
      _Translations$onboarding$theme$de._(_root);
  @override
  late final _Translations$onboarding$repo$de repo =
      _Translations$onboarding$repo$de._(_root);
  @override
  late final _Translations$onboarding$preview$de preview =
      _Translations$onboarding$preview$de._(_root);
}

// Path: orrery
class _Translations$orrery$de extends Translations$orrery$en {
  _Translations$orrery$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$orrery$header$de header =
      _Translations$orrery$header$de._(_root);
  @override
  late final _Translations$orrery$status$de status =
      _Translations$orrery$status$de._(_root);
  @override
  late final _Translations$orrery$legend$de legend =
      _Translations$orrery$legend$de._(_root);
  @override
  late final _Translations$orrery$node$de node = _Translations$orrery$node$de._(
    _root,
  );
  @override
  late final _Translations$orrery$milestone$de milestone =
      _Translations$orrery$milestone$de._(_root);
  @override
  late final _Translations$orrery$structure$de structure =
      _Translations$orrery$structure$de._(_root);
  @override
  late final _Translations$orrery$rail$de rail = _Translations$orrery$rail$de._(
    _root,
  );
  @override
  late final _Translations$orrery$selection$de selection =
      _Translations$orrery$selection$de._(_root);
  @override
  late final _Translations$orrery$findingKind$de findingKind =
      _Translations$orrery$findingKind$de._(_root);
  @override
  late final _Translations$orrery$findings$de findings =
      _Translations$orrery$findings$de._(_root);
  @override
  late final _Translations$orrery$anchor$de anchor =
      _Translations$orrery$anchor$de._(_root);
  @override
  late final _Translations$orrery$compare$de compare =
      _Translations$orrery$compare$de._(_root);
}

// Path: palette
class _Translations$palette$de extends Translations$palette$en {
  _Translations$palette$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get active => 'aktiv';
  @override
  late final _Translations$palette$prefixes$de prefixes =
      _Translations$palette$prefixes$de._(_root);
  @override
  late final _Translations$palette$chips$de chips =
      _Translations$palette$chips$de._(_root);
  @override
  late final _Translations$palette$predictive$de predictive =
      _Translations$palette$predictive$de._(_root);
  @override
  late final _Translations$palette$topTouched$de topTouched =
      _Translations$palette$topTouched$de._(_root);
  @override
  late final _Translations$palette$coherence$de coherence =
      _Translations$palette$coherence$de._(_root);
  @override
  late final _Translations$palette$keystone$de keystone =
      _Translations$palette$keystone$de._(_root);
  @override
  late final _Translations$palette$repoSub$de repoSub =
      _Translations$palette$repoSub$de._(_root);
  @override
  late final _Translations$palette$desks$de desks =
      _Translations$palette$desks$de._(_root);
  @override
  late final _Translations$palette$actions$de actions =
      _Translations$palette$actions$de._(_root);
  @override
  late final _Translations$palette$tools$de tools =
      _Translations$palette$tools$de._(_root);
  @override
  late final _Translations$palette$gitCommands$de gitCommands =
      _Translations$palette$gitCommands$de._(_root);
  @override
  late final _Translations$palette$pr$de pr = _Translations$palette$pr$de._(
    _root,
  );
  @override
  late final _Translations$palette$ai$de ai = _Translations$palette$ai$de._(
    _root,
  );
  @override
  late final _Translations$palette$undo$de undo =
      _Translations$palette$undo$de._(_root);
  @override
  late final _Translations$palette$navigation$de navigation =
      _Translations$palette$navigation$de._(_root);
  @override
  late final _Translations$palette$settings$de settings =
      _Translations$palette$settings$de._(_root);
  @override
  late final _Translations$palette$info$de info =
      _Translations$palette$info$de._(_root);
  @override
  late final _Translations$palette$debug$de debug =
      _Translations$palette$debug$de._(_root);
  @override
  late final _Translations$palette$dev$de dev = _Translations$palette$dev$de._(
    _root,
  );
  @override
  late final _Translations$palette$historySurgery$de historySurgery =
      _Translations$palette$historySurgery$de._(_root);
  @override
  late final _Translations$palette$orrery$de orrery =
      _Translations$palette$orrery$de._(_root);
  @override
  late final _Translations$palette$command$de command =
      _Translations$palette$command$de._(_root);
  @override
  late final _Translations$palette$search$de search =
      _Translations$palette$search$de._(_root);
  @override
  late final _Translations$palette$wick$de wick =
      _Translations$palette$wick$de._(_root);
  @override
  late final _Translations$palette$gitCache$de gitCache =
      _Translations$palette$gitCache$de._(_root);
}

// Path: releaseNotes
class _Translations$releaseNotes$de extends Translations$releaseNotes$en {
  _Translations$releaseNotes$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get versionFallback => 'dev';
  @override
  late final _Translations$releaseNotes$about$de about =
      _Translations$releaseNotes$about$de._(_root);
  @override
  late final _Translations$releaseNotes$legal$de legal =
      _Translations$releaseNotes$legal$de._(_root);
}

// Path: repoSummary
class _Translations$repoSummary$de extends Translations$repoSummary$en {
  _Translations$repoSummary$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$repoSummary$backbone$de backbone =
      _Translations$repoSummary$backbone$de._(_root);
  @override
  late final _Translations$repoSummary$glance$de glance =
      _Translations$repoSummary$glance$de._(_root);
  @override
  late final _Translations$repoSummary$heading$de heading =
      _Translations$repoSummary$heading$de._(_root);
  @override
  String get historyStarvedCaveat =>
      'Sortierung eingeschränkt: der Kopplungsgraph hatte keine Kanten (frischer Klon oder zu wenige Commits). Die Dateireihenfolge spiegelt die Größe wider, nicht die strukturelle Zentralität.';
  @override
  late final _Translations$repoSummary$pitch$de pitch =
      _Translations$repoSummary$pitch$de._(_root);
  @override
  late final _Translations$repoSummary$region$de region =
      _Translations$repoSummary$region$de._(_root);
  @override
  late final _Translations$repoSummary$shape$de shape =
      _Translations$repoSummary$shape$de._(_root);
}

// Path: settings
class _Translations$settings$de extends Translations$settings$en {
  _Translations$settings$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$language$de language =
      _Translations$settings$language$de._(_root);
  @override
  late final _Translations$settings$sectionLabels$de sectionLabels =
      _Translations$settings$sectionLabels$de._(_root);
  @override
  late final _Translations$settings$errors$de errors =
      _Translations$settings$errors$de._(_root);
  @override
  late final _Translations$settings$promptStatus$de promptStatus =
      _Translations$settings$promptStatus$de._(_root);
  @override
  late final _Translations$settings$clearData$de clearData =
      _Translations$settings$clearData$de._(_root);
  @override
  List<String> get guardrailStageLabels => [
    'Locker',
    'Ausgewogen',
    'Streng',
    'Paranoid',
  ];
  @override
  late final _Translations$settings$guardrailMacro$de guardrailMacro =
      _Translations$settings$guardrailMacro$de._(_root);
  @override
  late final _Translations$settings$guardrails$de guardrails =
      _Translations$settings$guardrails$de._(_root);
  @override
  late final _Translations$settings$appearance$de appearance =
      _Translations$settings$appearance$de._(_root);
  @override
  late final _Translations$settings$retention$de retention =
      _Translations$settings$retention$de._(_root);
  @override
  late final _Translations$settings$navigation$de navigation =
      _Translations$settings$navigation$de._(_root);
  @override
  late final _Translations$settings$behaviour$de behaviour =
      _Translations$settings$behaviour$de._(_root);
  @override
  late final _Translations$settings$retentionClear$de retentionClear =
      _Translations$settings$retentionClear$de._(_root);
  @override
  late final _Translations$settings$channels$de channels =
      _Translations$settings$channels$de._(_root);
  @override
  late final _Translations$settings$pollResult$de pollResult =
      _Translations$settings$pollResult$de._(_root);
  @override
  late final _Translations$settings$keybindingProfile$de keybindingProfile =
      _Translations$settings$keybindingProfile$de._(_root);
  @override
  late final _Translations$settings$apiKeys$de apiKeys =
      _Translations$settings$apiKeys$de._(_root);
  @override
  late final _Translations$settings$shortcuts$de shortcuts =
      _Translations$settings$shortcuts$de._(_root);
  @override
  late final _Translations$settings$toggles$de toggles =
      _Translations$settings$toggles$de._(_root);
  @override
  late final _Translations$settings$diffDiffability$de diffDiffability =
      _Translations$settings$diffDiffability$de._(_root);
  @override
  late final _Translations$settings$modelSlots$de modelSlots =
      _Translations$settings$modelSlots$de._(_root);
  @override
  late final _Translations$settings$modelPicker$de modelPicker =
      _Translations$settings$modelPicker$de._(_root);
  @override
  late final _Translations$settings$aiFeatures$de aiFeatures =
      _Translations$settings$aiFeatures$de._(_root);
  @override
  late final _Translations$settings$commitEditor$de commitEditor =
      _Translations$settings$commitEditor$de._(_root);
  @override
  late final _Translations$settings$review$de review =
      _Translations$settings$review$de._(_root);
  @override
  late final _Translations$settings$museHint$de museHint =
      _Translations$settings$museHint$de._(_root);
  @override
  late final _Translations$settings$museEditor$de museEditor =
      _Translations$settings$museEditor$de._(_root);
  @override
  late final _Translations$settings$museStage$de museStage =
      _Translations$settings$museStage$de._(_root);
  @override
  late final _Translations$settings$lensAxis$de lensAxis =
      _Translations$settings$lensAxis$de._(_root);
  @override
  late final _Translations$settings$logosLens$de logosLens =
      _Translations$settings$logosLens$de._(_root);
  @override
  late final _Translations$settings$sortGuide$de sortGuide =
      _Translations$settings$sortGuide$de._(_root);
  @override
  late final _Translations$settings$piggyback$de piggyback =
      _Translations$settings$piggyback$de._(_root);
  @override
  late final _Translations$settings$diffStage$de diffStage =
      _Translations$settings$diffStage$de._(_root);
  @override
  late final _Translations$settings$undoScope$de undoScope =
      _Translations$settings$undoScope$de._(_root);
  @override
  late final _Translations$settings$undoWindow$de undoWindow =
      _Translations$settings$undoWindow$de._(_root);
  @override
  late final _Translations$settings$guardrailPhrase$de guardrailPhrase =
      _Translations$settings$guardrailPhrase$de._(_root);
  @override
  late final _Translations$settings$reviewGuideHint$de reviewGuideHint =
      _Translations$settings$reviewGuideHint$de._(_root);
  @override
  late final _Translations$settings$commitFormat$de commitFormat =
      _Translations$settings$commitFormat$de._(_root);
  @override
  late final _Translations$settings$commitPreview$de commitPreview =
      _Translations$settings$commitPreview$de._(_root);
  @override
  late final _Translations$settings$externalTools$de externalTools =
      _Translations$settings$externalTools$de._(_root);
  @override
  late final _Translations$settings$apiUsage$de apiUsage =
      _Translations$settings$apiUsage$de._(_root);
  @override
  late final _Translations$settings$gitea$de gitea =
      _Translations$settings$gitea$de._(_root);
  @override
  late final _Translations$settings$wick$de wick =
      _Translations$settings$wick$de._(_root);
  @override
  late final _Translations$settings$integrations$de integrations =
      _Translations$settings$integrations$de._(_root);
  @override
  late final _Translations$settings$reduceMotion$de reduceMotion =
      _Translations$settings$reduceMotion$de._(_root);
  @override
  late final _Translations$settings$resetQuit$de resetQuit =
      _Translations$settings$resetQuit$de._(_root);
  @override
  late final _Translations$settings$diagnostics$de diagnostics =
      _Translations$settings$diagnostics$de._(_root);
  @override
  late final _Translations$settings$telemetry$de telemetry =
      _Translations$settings$telemetry$de._(_root);
  @override
  late final _Translations$settings$flowEngine$de flowEngine =
      _Translations$settings$flowEngine$de._(_root);
  @override
  late final _Translations$settings$museStrands$de museStrands =
      _Translations$settings$museStrands$de._(_root);
  @override
  late final _Translations$settings$cliPiggyback$de cliPiggyback =
      _Translations$settings$cliPiggyback$de._(_root);
  @override
  late final _Translations$settings$header$de header =
      _Translations$settings$header$de._(_root);
  @override
  late final _Translations$settings$diagnosticsPanel$de diagnosticsPanel =
      _Translations$settings$diagnosticsPanel$de._(_root);
  @override
  late final _Translations$settings$release$de release =
      _Translations$settings$release$de._(_root);
  @override
  late final _Translations$settings$providerStatus$de providerStatus =
      _Translations$settings$providerStatus$de._(_root);
  @override
  late final _Translations$settings$meridiem$de meridiem =
      _Translations$settings$meridiem$de._(_root);
  @override
  late final _Translations$settings$offenders$de offenders =
      _Translations$settings$offenders$de._(_root);
}

// Path: sync
class _Translations$sync$de extends Translations$sync$en {
  _Translations$sync$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$actions$de actions =
      _Translations$sync$actions$de._(_root);
  @override
  late final _Translations$sync$panel$de panel = _Translations$sync$panel$de._(
    _root,
  );
  @override
  late final _Translations$sync$forcePush$de forcePush =
      _Translations$sync$forcePush$de._(_root);
}

// Path: xray
class _Translations$xray$de extends Translations$xray$en {
  _Translations$xray$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$board$de board = _Translations$xray$board$de._(
    _root,
  );
  @override
  late final _Translations$xray$cadence$de cadence =
      _Translations$xray$cadence$de._(_root);
  @override
  late final _Translations$xray$cards$de cards = _Translations$xray$cards$de._(
    _root,
  );
  @override
  late final _Translations$xray$cardTitle$de cardTitle =
      _Translations$xray$cardTitle$de._(_root);
  @override
  late final _Translations$xray$grain$de grain = _Translations$xray$grain$de._(
    _root,
  );
  @override
  late final _Translations$xray$header$de header =
      _Translations$xray$header$de._(_root);
  @override
  late final _Translations$xray$hotspot$de hotspot =
      _Translations$xray$hotspot$de._(_root);
  @override
  late final _Translations$xray$inspector$de inspector =
      _Translations$xray$inspector$de._(_root);
  @override
  late final _Translations$xray$loadingCard$de loadingCard =
      _Translations$xray$loadingCard$de._(_root);
  @override
  late final _Translations$xray$metabolism$de metabolism =
      _Translations$xray$metabolism$de._(_root);
  @override
  late final _Translations$xray$multi$de multi = _Translations$xray$multi$de._(
    _root,
  );
  @override
  late final _Translations$xray$recency$de recency =
      _Translations$xray$recency$de._(_root);
  @override
  late final _Translations$xray$rings$de rings = _Translations$xray$rings$de._(
    _root,
  );
  @override
  late final _Translations$xray$stats$de stats = _Translations$xray$stats$de._(
    _root,
  );
  @override
  late final _Translations$xray$stratumLabel$de stratumLabel =
      _Translations$xray$stratumLabel$de._(_root);
  @override
  late final _Translations$xray$summary$de summary =
      _Translations$xray$summary$de._(_root);
  @override
  late final _Translations$xray$tabs$de tabs = _Translations$xray$tabs$de._(
    _root,
  );
  @override
  late final _Translations$xray$trajectory$de trajectory =
      _Translations$xray$trajectory$de._(_root);
  @override
  late final _Translations$xray$verdict$de verdict =
      _Translations$xray$verdict$de._(_root);
}

// Path: app.cheatsheet
class _Translations$app$cheatsheet$de extends Translations$app$cheatsheet$en {
  _Translations$app$cheatsheet$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Tastatur';
  @override
  String get sectionNavigate => 'navigieren';
  @override
  String get sectionStaging => 'staging';
  @override
  String get sectionBranchesPrs => 'Branches & PRs';
  @override
  String get changes => 'Änderungen';
  @override
  String get history => 'Verlauf';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Wechseln (immer)';
  @override
  String get commandPalette => 'Befehlspalette';
  @override
  String get elevatedPalette => 'Erhöhte Palette';
  @override
  String get dismiss => 'Verwerfen';
  @override
  String get refresh => 'Aktualisieren';
  @override
  String get nextPrevChange => 'Nächste / vorige Änderung';
  @override
  String get toggleLine => 'Zeile umschalten';
  @override
  String get toggleHunk => 'Hunk umschalten';
  @override
  String get toggleFile => 'Datei umschalten';
  @override
  String get pinContext => 'Kontext anheften';
  @override
  String get commit => 'Commit';
  @override
  String get acceptAiHint => 'AI-Hinweis annehmen';
  @override
  String get undo => 'Rückgängig';
  @override
  String get navigate => 'Navigieren';
  @override
  String get expand => 'Ausklappen';
  @override
  String get checkoutPr => 'PR auschecken';
  @override
  String get approve => 'Freigeben';
  @override
  String get requestChanges => 'Änderungen anfordern';
  @override
  String profileSwitchHint({required Object profile}) =>
      'Profil ${profile} · in Einstellungen wechseln';
}

// Path: backend.ops
class _Translations$backend$ops$de extends Translations$backend$ops$en {
  _Translations$backend$ops$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'Merge';
  @override
  String get pull => 'Pull';
  @override
  String get apply => 'Anwenden';
  @override
  String get switchOp => 'Wechseln';
  @override
  String get sync => 'Sync';
}

// Path: backend.mergeOutcome
class _Translations$backend$mergeOutcome$de
    extends Translations$backend$mergeOutcome$en {
  _Translations$backend$mergeOutcome$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String cancelled({required Object op}) => '${op} abgebrochen.';
  @override
  String complete({required Object op}) => '${op} abgeschlossen.';
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'Noch ${n} Konflikt — löse ihn auf der Änderungen-Seite.',
        other: 'Noch ${n} Konflikte — löse sie auf der Änderungen-Seite.',
      );
  @override
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Konflikt gelöst.',
        other: '${n} Konflikte gelöst.',
      );
  @override
  String uncommittedEdits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Datei hat uncommittete Änderungen — committe sie zuerst.',
        other:
            '${n} Dateien haben uncommittete Änderungen — committe sie zuerst.',
      );
}

// Path: changes.usage
class _Translations$changes$usage$de extends Translations$changes$usage$en {
  _Translations$changes$usage$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String caption({required Object input, required Object output}) =>
      '${input} rein · ${output} raus';
  @override
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '${fresh} rein · ${cached} gecacht · ${out} raus';
  @override
  String get inWord => 'rein';
  @override
  String get cachedWord => 'gecacht';
  @override
  String get outWord => 'raus';
  @override
  String tipIn({required Object value}) => '${value}  rein';
  @override
  String tipCacheRead({required Object value}) => '${value}  Cache-Lesen';
  @override
  String tipCacheWrite({required Object value}) => '${value}  Cache-Schreiben';
  @override
  String tipOut({required Object value}) => '${value}  raus';
  @override
  String tipReasoning({required Object value}) => '${value}  Reasoning';
  @override
  String tipWallClock({required Object value}) => '${value}s  Echtzeit';
}

// Path: changes.tabs
class _Translations$changes$tabs$de extends Translations$changes$tabs$en {
  _Translations$changes$tabs$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get defaultLabel => 'Änderungen';
  @override
  String get empty => 'Leer';
}

// Path: changes.tabStrip
class _Translations$changes$tabStrip$de
    extends Translations$changes$tabStrip$en {
  _Translations$changes$tabStrip$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get newDiffTab => 'Neuer Diff-Tab';
}

// Path: changes.select
class _Translations$changes$select$de extends Translations$changes$select$en {
  _Translations$changes$select$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get selectAll => 'Alle auswählen';
  @override
  String get deselectAll => 'Alle abwählen';
}

// Path: changes.constellationToggle
class _Translations$changes$constellationToggle$de
    extends Translations$changes$constellationToggle$en {
  _Translations$changes$constellationToggle$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get backToList => 'zurück zur Liste';
  @override
  String get atlas => 'Atlas, Commit-Kandidaten ansehen';
}

// Path: changes.nudgeChip
class _Translations$changes$nudgeChip$de
    extends Translations$changes$nudgeChip$en {
  _Translations$changes$nudgeChip$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\nkoppelt mit ${anchor} · ${pct}%${receipts}';
}

// Path: changes.minimap
class _Translations$changes$minimap$de extends Translations$changes$minimap$en {
  _Translations$changes$minimap$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get roleNew => 'neu';
  @override
  String get roleBridge => 'brücke';
  @override
  String get roleHub => 'hub';
  @override
  String get roleLeaf => 'blatt';
  @override
  String get roleConnected => 'verbunden';
  @override
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';
  @override
  String changesWith({required Object name}) => 'ändert sich mit ${name}';
  @override
  String get newFile => 'neue Datei';
  @override
  String nearOtherChanges({required Object count, required Object dir}) =>
      'nahe ${count} anderen Änderungen in ${dir}';
  @override
  String usuallyChangesWithFile({required Object name}) =>
      '${name} ändert sich meist mit dieser Datei';
}

// Path: changes.tagInput
class _Translations$changes$tagInput$de
    extends Translations$changes$tagInput$en {
  _Translations$changes$tagInput$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get hint => 'tag...';
}

// Path: changes.composer
class _Translations$changes$composer$de
    extends Translations$changes$composer$en {
  _Translations$changes$composer$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get hintPlaceholder => 'commit-nachricht...';
  @override
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class _Translations$changes$commit$de extends Translations$changes$commit$en {
  _Translations$changes$commit$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get primaryCommitChanges => 'Änderungen committen';
  @override
  String get primaryCommitChangesDetail =>
      'Detached HEAD: lokal committen ohne Sync.';
  @override
  String get primaryPublish => 'Committen & veröffentlichen';
  @override
  String get primaryPublishDetail =>
      'Erstelle den Commit und veröffentliche diesen Branch in einem Schritt.';
  @override
  String get primarySync => 'Committen & syncen';
  @override
  String get primarySyncDetail =>
      'Erstelle den Commit, dann gleiche den Branch ab und schicke ihn los.';
  @override
  String get primaryPush => 'Committen & pushen';
  @override
  String get primaryPushDetail => 'Erstelle den Commit und pushe ihn sofort.';
  @override
  String get amendLast => 'Letzten Commit ergänzen';
  @override
  String amendAnd({required Object action}) => 'Ergänzen & ${action}';
  @override
  String get chooseFile =>
      'Wähle mindestens eine Datei für den nächsten Commit.';
  @override
  String get writeMessage => 'Schreib zuerst eine Commit-Nachricht.';
  @override
  String get committing => 'Committe';
  @override
  String get committingSync => 'Committe und synce';
  @override
  String get committed => 'Committet.';
  @override
  String get undoFailed => 'Rückgängig fehlgeschlagen.';
  @override
  String get working => 'Arbeite…';
  @override
  String get commitOnly => 'Nur committen';
  @override
  String get noRuntimeModels =>
      'Keine zur Laufzeit erkannten Modelle für Commit-Nachrichten verfügbar.';
  @override
  String restoreFailedRetry({required Object err}) =>
      '${err}\nDas Staging der ausgeschlossenen Dateien konnte nicht wiederhergestellt werden; prüfe den Index vor dem erneuten Versuch.';
  @override
  String committedSummary({required Object summary, required Object hash}) =>
      '${summary} committet (${hash}).';
  @override
  String get restoreFailedSync =>
      'Die Auswahl der ausgeschlossenen Dateien konnte nicht neu gestaged werden; Sync übersprungen. Prüfe den Index vor dem Syncen.';
  @override
  String get noModelLabel => 'Kein Modell';
  @override
  String get chooseBeforeGenerate =>
      'Wähle mindestens eine Datei vor dem Generieren.';
  @override
  String get aiUnavailable => 'Commit-Nachricht-AI ist noch nicht verfügbar.';
  @override
  String get generateFailed => 'Generieren fehlgeschlagen.';
  @override
  String get stageFailed => 'Dateien konnten nicht gestaged werden.';
  @override
  String get commitFailed => 'Commit fehlgeschlagen.';
  @override
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => '${summary} committet (${hash}) und ${operation} ausgeführt.';
  @override
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    n,
    one: '${summary} committet (${hash}); ${n} Konflikt gelöst.',
    other: '${summary} committet (${hash}); ${n} Konflikte gelöst.',
  );
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'Noch ${n} Konflikt zu lösen.',
        other: 'Noch ${n} Konflikte zu lösen.',
      );
  @override
  String syncBlocked({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    n,
    one:
        'Commit erfolgreich, aber Sync wurde durch ${n} uncommittete Datei blockiert.',
    other:
        'Commit erfolgreich, aber Sync wurde durch ${n} uncommittete Dateien blockiert.',
  );
  @override
  String syncStalled({required Object message}) =>
      'Commit erfolgreich, aber Sync stockte: ${message}';
  @override
  String syncFailed({required Object message}) =>
      'Commit erfolgreich, aber Sync fehlgeschlagen: ${message}';
}

// Path: changes.rebase
class _Translations$changes$rebase$de extends Translations$changes$rebase$en {
  _Translations$changes$rebase$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get continueFailed => 'Der Rebase konnte nicht fortgesetzt werden.';
}

// Path: changes.editor
class _Translations$changes$editor$de extends Translations$changes$editor$en {
  _Translations$changes$editor$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get closeBarrier => 'Editor schließen';
}

// Path: changes.editorTitles
class _Translations$changes$editorTitles$de
    extends Translations$changes$editorTitles$en {
  _Translations$changes$editorTitles$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  List<String> get any => [
    'liebes git-log',
    'ver-git mir denn ich habe gesündigt…',
    'gib diesem Moment einen Namen',
    'laber los',
    'sprich!',
    'deine Mutter war eine baumelnde Referenz und dein Vater roch nach Semikolons',
  ];
  @override
  List<String> get short => [
    'oh?',
    'hallöchen:)',
    'übrigens:',
    'ein paar Worte',
    'die höfliche Version',
    'hinterlass eine Notiz',
    'du wolltest sagen..?',
    'ach ja, raus damit',
  ];
  @override
  List<String> get mid => [
    'fürs Protokoll',
    'sag\'s dem Zukunfts-Ich',
    'aber zuerst?',
    'wie es lief',
    'in deinen eigenen Worten',
    'du hast WAS gemacht?',
    'zur Kenntnis genommen',
    'du hast meine Aufmerksamkeit',
  ];
  @override
  List<String> get long => [
    'deine Träume, bitte',
    'sag was Nettes',
    '... und dann sagte ich:',
    'die Nachwelt wartet',
    'mehr schreiben lässt deine Bugs verschwinden',
    'oh wow',
    'die heiligen Texte',
  ];
}

// Path: changes.askHint
class _Translations$changes$askHint$de extends Translations$changes$askHint$en {
  _Translations$changes$askHint$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String round({required Object n}) =>
      'Runde ${n} — verfeinern oder Kontext ergänzen.';
  @override
  String get symptom => 'beschreibe das Symptom.';
  @override
  String get broken => 'was ist kaputt?';
  @override
  String get bug => 'beschreibe den Bug.';
  @override
  String get error => 'füge den Fehler ein.';
}

// Path: changes.fileMenu
class _Translations$changes$fileMenu$de
    extends Translations$changes$fileMenu$en {
  _Translations$changes$fileMenu$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get ripple => 'Welle';
  @override
  String get includeCoChanges => 'Co-Changes einbeziehen';
  @override
  String deleteFile({required Object name}) => '${name} löschen…';
  @override
  String discardChangesTo({required Object name}) =>
      'Änderungen an ${name} verwerfen…';
  @override
  String get ignore => 'Ignorieren';
  @override
  String get diffTabFromSelection => 'Diff-Tab aus Auswahl';
  @override
  String addSelectedToTab({required Object name}) =>
      'Auswahl zu ${name} hinzufügen';
  @override
  String diffTabFromFile({required Object name}) => 'Diff-Tab aus ${name}';
  @override
  String addFileToTab({required Object file, required Object tab}) =>
      '${file} zu ${tab} hinzufügen';
  @override
  String get copyFilePath => 'Dateipfad kopieren';
  @override
  String get showInExplorer => 'Im Explorer zeigen';
}

// Path: changes.multiFileMenu
class _Translations$changes$multiFileMenu$de
    extends Translations$changes$multiFileMenu$en {
  _Translations$changes$multiFileMenu$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get cohesionTight => 'eng gekoppelt';
  @override
  String get cohesionLoose => 'lose verwandt';
  @override
  String get cohesionScattered => 'strukturell verstreut';
  @override
  String get clusterOne => 'alle in einem Cluster';
  @override
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      'erstreckt sich über ${count} Cluster (${parts} Dateien)';
  @override
  String clusterSpans({required Object count}) =>
      'erstreckt sich über ${count} Cluster';
  @override
  String roleLine({required Object count, required Object cohesion}) =>
      '${count} Dateien · ${cohesion}';
  @override
  String usuallyChangesWithGroup({required Object file}) =>
      '${file} ändert sich meist mit dieser Gruppe';
  @override
  String get splitToNewTab => 'In neuen Tab abspalten';
  @override
  String copyPaths({required Object count}) => '${count} Pfade kopieren';
}

// Path: changes.ignoreMenu
class _Translations$changes$ignoreMenu$de
    extends Translations$changes$ignoreMenu$en {
  _Translations$changes$ignoreMenu$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String extension({required Object ext}) => '.${ext}-Endung';
  @override
  String allSelected({required Object count}) => 'Alle ${count} ausgewählt';
  @override
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'Koppelt mit ${n} einbezogenen Datei',
        other: 'Koppelt mit ${n} einbezogenen Dateien',
      );
  @override
  String get updateFailed => '.gitignore konnte nicht aktualisiert werden.';
}

// Path: changes.discard
class _Translations$changes$discard$de extends Translations$changes$discard$en {
  _Translations$changes$discard$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String deleteTitle({required Object name}) => '${name} löschen?';
  @override
  String discardTitle({required Object name}) =>
      'Änderungen an ${name} verwerfen?';
  @override
  String deleteBody({required Object path}) =>
      '${path} wird von der Platte entfernt. Das kann innerhalb der App nicht rückgängig gemacht werden.';
  @override
  String discardBody({required Object path}) =>
      'Alle Änderungen an ${path} werden auf ihren Stand in HEAD zurückgesetzt. Das kann nicht rückgängig gemacht werden.';
  @override
  String get discard => 'Verwerfen';
  @override
  String deletingFile({required Object name}) => 'Lösche ${name}';
  @override
  String discardingFile({required Object name}) => 'Verwerfe ${name}';
  @override
  String get discardFailed => 'Änderungen konnten nicht verworfen werden.';
  @override
  String discardManyTitle({required Object count}) =>
      'Änderungen an ${count} Dateien verwerfen?';
  @override
  String get discardManyBody =>
      'Getrackte Dateien werden auf ihren Stand in HEAD zurückgesetzt; ungetrackte Dateien werden von der Platte entfernt. Das kann nicht rückgängig gemacht werden.';
  @override
  String discardManyConfirm({required Object count}) => '${count} verwerfen';
  @override
  String discardingManyFiles({required Object count}) =>
      'Verwerfe ${count} Dateien';
  @override
  String failedOpenExplorer({required Object error}) =>
      'Dateimanager konnte nicht geöffnet werden: ${error}';
  @override
  String get someFailed => 'Einige Verwerfungen sind fehlgeschlagen.';
}

// Path: changes.snack
class _Translations$changes$snack$de extends Translations$changes$snack$en {
  _Translations$changes$snack$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get sameWorktree => 'Gleicher Worktree — nichts zum Ablegen.';
  @override
  String diffFailed({required Object error}) => 'Diff fehlgeschlagen: ${error}';
  @override
  String get deskEmpty => 'Der Desk hat nichts vor dir — leere Ablage.';
  @override
  String sourceDesk({required Object label}) => 'Desk ${label}';
  @override
  String shelfReadFailed({required Object error}) =>
      'Ablage konnte nicht gelesen werden: ${error}';
  @override
  String get shelfEmpty => 'Leere Ablage — nichts zum Ablegen.';
  @override
  String sourceShelf({required Object label}) => 'Ablage ${label}';
  @override
  String noModelConfigured({required Object label}) =>
      'Kein Modell für "${label}" konfiguriert.';
  @override
  String fetchFailed({required Object error}) =>
      'Fetch fehlgeschlagen: ${error}';
}

// Path: changes.trace
class _Translations$changes$trace$de extends Translations$changes$trace$en {
  _Translations$changes$trace$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Verifikations-Trace';
  @override
  String get draftReview => 'Review-Entwurf';
}

// Path: changes.cleanTree
class _Translations$changes$cleanTree$de
    extends Translations$changes$cleanTree$en {
  _Translations$changes$cleanTree$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Arbeitsverzeichnis sauber';
  @override
  String get subtitle => 'Keine gestagten oder ungestagten Änderungen erkannt.';
  @override
  String get noUpstream => '  ·  kein Upstream';
  @override
  String get ahead => ' voraus';
  @override
  String get behind => ' zurück';
  @override
  String get refreshing => 'Aktualisiere...';
  @override
  String get refresh => 'Aktualisieren';
  @override
  String get check => 'prüfen';
  @override
  String get checkTooltip => 'Fetch und lokale Aktualisierung.';
  @override
  String get sync => '& sync';
}

// Path: changes.guardrail
class _Translations$changes$guardrail$de
    extends Translations$changes$guardrail$en {
  _Translations$changes$guardrail$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'Locker';
  @override
  String get balanced => 'Ausgewogen';
  @override
  String get strict => 'Streng';
  @override
  String get paranoid => 'Paranoid';
}

// Path: changes.dropHint
class _Translations$changes$dropHint$de
    extends Translations$changes$dropHint$en {
  _Translations$changes$dropHint$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get fromShelf =>
      'ablegen, um Änderungen aus dieser Ablage hierher zu holen';
  @override
  String get fromDesk =>
      'ablegen, um Änderungen von diesem Desk hierher zu holen';
}

// Path: changes.diffEmpty
class _Translations$changes$diffEmpty$de
    extends Translations$changes$diffEmpty$en {
  _Translations$changes$diffEmpty$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Keine Datei ausgewählt';
  @override
  String get message =>
      'Wähle eine geänderte Datei, um ihren Diff zu untersuchen.';
}

// Path: changes.shelvePill
class _Translations$changes$shelvePill$de
    extends Translations$changes$shelvePill$en {
  _Translations$changes$shelvePill$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String shelveN({required Object count}) => '↓ ${count} ablegen';
  @override
  String get shelve => '↓ ablegen';
  @override
  String shelvedCount({required Object count, required Object glyph}) =>
      '${count} abgelegt ${glyph}';
}

// Path: changes.stashAction
class _Translations$changes$stashAction$de
    extends Translations$changes$stashAction$en {
  _Translations$changes$stashAction$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get pickUp => 'aufnehmen';
  @override
  String get peek => 'spähen';
  @override
  String get toss => 'wegwerfen';
}

// Path: changes.stashContents
class _Translations$changes$stashContents$de
    extends Translations$changes$stashContents$en {
  _Translations$changes$stashContents$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get reading => 'lese Ablage…';
  @override
  String get empty => 'leere Ablage';
}

// Path: changes.stashFile
class _Translations$changes$stashFile$de
    extends Translations$changes$stashFile$en {
  _Translations$changes$stashFile$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get binary => 'bin';
}

// Path: changes.fileRow
class _Translations$changes$fileRow$de extends Translations$changes$fileRow$en {
  _Translations$changes$fileRow$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get stagedLinesOnly => 'committet nur gestagte Zeilen';
  @override
  String get doubleClickToggle => 'Doppelklick: ganze Gruppe umschalten';
  @override
  String get repoRoot => 'Repository-Wurzel';
}

// Path: changes.resolveStrip
class _Translations$changes$resolveStrip$de
    extends Translations$changes$resolveStrip$en {
  _Translations$changes$resolveStrip$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'lese ${n} Datei · entwerfe Auflösung…',
        other: 'lese ${n} Dateien · entwerfe Auflösung…',
      );
  @override
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Konflikt in ${files}',
        other: '${n} Konflikte in ${files}',
      );
  @override
  String get resolve => 'Lösen';
  @override
  String get orWith => 'ODER MIT';
  @override
  String resolveWith({required Object label}) => 'mit ${label} lösen';
  @override
  String resolveWithModel({required Object label, required Object model}) =>
      'mit ${label} lösen  ·  ${model}';
  @override
  String get resolving => 'löse…';
  @override
  String resolveWithGlyph({required Object label}) => '↵  mit ${label} lösen';
  @override
  String get orWithAnother => 'oder mit einem anderen Modell';
}

// Path: changes.badge
class _Translations$changes$badge$de extends Translations$changes$badge$en {
  _Translations$changes$badge$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get stagedEdit => 'Gestagte Änderung';
  @override
  String get edited => 'Geändert';
  @override
  String get stagedAdd => 'Gestagte Hinzufügung';
  @override
  String get added => 'Hinzugefügt';
  @override
  String get stagedDelete => 'Gestagte Löschung';
  @override
  String get deleted => 'Gelöscht';
  @override
  String get stagedRename => 'Gestagte Umbenennung';
  @override
  String get renamed => 'Umbenannt';
  @override
  String get stagedCopy => 'Gestagte Kopie';
  @override
  String get copied => 'Kopiert';
  @override
  String get conflict => 'Konflikt';
  @override
  String get stagedTypeChange => 'Gestagte Typänderung';
  @override
  String get typeChanged => 'Typ geändert';
  @override
  String get untracked => 'Ungetrackt';
}

// Path: changes.review
class _Translations$changes$review$de extends Translations$changes$review$en {
  _Translations$changes$review$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Code-Review';
  @override
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} einbezogene Datei',
        other: '${n} einbezogene Dateien',
      );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Hunk',
        other: '${n} Hunks',
      );
  @override
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';
  @override
  String get unavailable => 'Review nicht verfügbar';
  @override
  String get backToDiff => 'Zurück zum Diff';
  @override
  String get verified => 'Verifiziert';
  @override
  String get draftOnly => 'Nur Entwurf';
  @override
  String get runAgain => 'Erneut ausführen';
  @override
  String draftShownBelow({required Object error}) =>
      '${error} Der Review-Entwurf wird unten gezeigt.';
  @override
  String get hideTrace => 'Trace verbergen';
  @override
  String get showTrace => 'Trace zeigen';
  @override
  String get showVerificationTrace => 'Verifikations-Trace zeigen';
  @override
  String get whyLanded => 'Warum dieses Review hier landete';
  @override
  String get noFindings => 'Keine Funde';
  @override
  String get findings => 'Funde';
  @override
  String get noEvidenceIssues =>
      'Für diesen Commit-Umfang wurden keine belegbaren Probleme gefunden.';
  @override
  String get observations => 'Beobachtungen';
  @override
  String get chooseBeforeReview =>
      'Wähle mindestens eine Datei vor dem Reviewen.';
  @override
  String get aiUnavailable => 'Review-AI ist noch nicht verfügbar.';
  @override
  String get failed => 'Review fehlgeschlagen.';
  @override
  String get noRuntimeModels =>
      'Keine zur Laufzeit erkannten Modelle für Commit-Review verfügbar.';
}

// Path: changes.commitBtn
class _Translations$changes$commitBtn$de
    extends Translations$changes$commitBtn$en {
  _Translations$changes$commitBtn$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String switchTo({required Object label}) => 'Wechseln zu: ${label}\n';
}

// Path: changes.shapeBtn
class _Translations$changes$shapeBtn$de
    extends Translations$changes$shapeBtn$en {
  _Translations$changes$shapeBtn$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String askingWith({required Object cat}) => 'frage mit ${cat}…';
  @override
  String askWith({required Object cat}) => 'mit ${cat} fragen';
  @override
  String get noModel => 'kein AI-Modell konfiguriert';
  @override
  String nextTooltip({required Object cat}) =>
      'nächste: ${cat}  ·  Shift-Klick für vorige';
  @override
  String get onlyOne => 'nur eine AI-Kategorie konfiguriert';
}

// Path: changes.dejaVu
class _Translations$changes$dejaVu$de extends Translations$changes$dejaVu$en {
  _Translations$changes$dejaVu$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required num n,
    required Object pct,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    n,
    one:
        '${pct}% Déjà-vu — ${n} Geisterkante aus verworfenen Zeitlinien berührt diesen Diff',
    other:
        '${pct}% Déjà-vu — ${n} Geisterkanten aus verworfenen Zeitlinien berühren diesen Diff',
  );
  @override
  String get label => 'déjà-vu';
}

// Path: changes.identity
class _Translations$changes$identity$de
    extends Translations$changes$identity$en {
  _Translations$changes$identity$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'keine Commit-Identität konfiguriert';
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
  String get firstCommit => '\nerster Commit in diesem Repo';
  @override
  String get newToRepo => '\nneu in diesem Repo';
}

// Path: changes.staleScope
class _Translations$changes$staleScope$de
    extends Translations$changes$staleScope$en {
  _Translations$changes$staleScope$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get message => 'Auswahl hat sich seit diesem Lauf geändert';
  @override
  String get rerun => 'erneut ausführen';
}

// Path: changes.finding
class _Translations$changes$finding$de extends Translations$changes$finding$en {
  _Translations$changes$finding$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get openDiff => 'Diff öffnen';
  @override
  String get recorded => 'erfasst';
  @override
  String get dismiss => 'Verwerfen';
}

// Path: changes.muse
class _Translations$changes$muse$de extends Translations$changes$muse$en {
  _Translations$changes$muse$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Muse';
  @override
  String get youPulledThis => 'das hast du gezogen';
  @override
  String fromIdea({required Object text}) => 'aus Idee: "${text}"';
  @override
  String get foothold => 'Halt — ';
  @override
  String get brainstormSpew => 'Brainstorm-Erguss';
  @override
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';
  @override
  String copyN({required Object count}) => '${count} kopieren';
  @override
  String get clear => 'Leeren';
  @override
  String get chooseBeforeMuse =>
      'Wähle mindestens eine Datei, bevor du die Muse rufst.';
  @override
  String get aiUnavailable => 'Muse-AI ist noch nicht verfügbar.';
  @override
  String get failed => 'Muse fehlgeschlagen.';
  @override
  String get noRuntimeModels =>
      'Keine zur Laufzeit erkannten Modelle für die Muse verfügbar.';
  @override
  String get needsModel =>
      'Die Muse braucht mindestens ein konfiguriertes Modell.';
  @override
  String get dreaming => 'die Muse träumt...';
}

// Path: changes.debug
class _Translations$changes$debug$de extends Translations$changes$debug$en {
  _Translations$changes$debug$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Debug';
  @override
  String round({required Object n}) => '· Runde ${n}';
  @override
  String get clear => 'leeren';
  @override
  String get close => 'schließen';
  @override
  String get analyzing => 'analysiere Symptom…';
  @override
  String get describeSymptom => 'beschreibe ein Symptom, dann drücke Debug.';
  @override
  String get evidenceFor => 'dafür';
  @override
  String get evidenceAgainst => 'aber';
  @override
  String get narrowDown => 'was beim Eingrenzen helfen würde:';
  @override
  String get failed => 'Debug fehlgeschlagen.';
  @override
  String get refinementFailed => 'Debug-Verfeinerung fehlgeschlagen.';
}

// Path: changes.includeSummary
class _Translations$changes$includeSummary$de
    extends Translations$changes$includeSummary$en {
  _Translations$changes$includeSummary$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'Keine';
  @override
  String stagedSuffix({required Object count}) => ' · ${count} gestaged';
  @override
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'Alle ${n} Datei${staged}',
        other: 'Alle ${n} Dateien${staged}',
      );
  @override
  String partial({
    required Object count,
    required Object n,
    required Object staged,
  }) => '${count} von ${n}${staged}';
  @override
  String shortAll({required Object n, required Object staged}) =>
      'Alle ${n}${staged}';
}

// Path: changes.status
class _Translations$changes$status$de extends Translations$changes$status$en {
  _Translations$changes$status$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get unavailableTitle => 'Repository-Status nicht verfügbar';
  @override
  String get loadingTitle => 'Lade Repository-Status';
  @override
  String get loadingMessage => 'Lese das Arbeitsverzeichnis.';
}

// Path: changes.stash
class _Translations$changes$stash$de extends Translations$changes$stash$en {
  _Translations$changes$stash$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get appliedWithConflicts =>
      'Stash mit Konflikten angewendet — löse sie auf der Änderungen-Seite (der Stash-Eintrag wurde behalten).';
  @override
  String get couldNotPop => 'Stash konnte nicht gepoppt werden.';
  @override
  String get listChanged =>
      'Die Stash-Liste hat sich geändert; Drop übersprungen. Versuch es erneut.';
  @override
  String get droppingStash => 'Verwerfe Stash';
}

// Path: changes.tooltips
class _Translations$changes$tooltips$de
    extends Translations$changes$tooltips$en {
  _Translations$changes$tooltips$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get commitGenerating => 'generiere Commit-Nachricht...';
  @override
  String get commitPreparing => 'bereite Commit-Nachricht vor...';
  @override
  String get commitSelectFile =>
      'wähle mindestens eine Datei, um eine Commit-Nachricht zu generieren.';
  @override
  String get commitConfigure =>
      'Commit-Nachricht konfigurieren unter Einstellungen > Verhaltensdynamik > Commit-Nachrichten.';
  @override
  String get fastFallback => 'schnell';
  @override
  String commitGenerateWith({required Object label}) =>
      'Commit-Nachricht mit Modell ${label} generieren';
  @override
  String get museConsulting => 'befrage die Muse...';
  @override
  String get showMuse => 'Muse zeigen';
  @override
  String get museSelectFile => 'wähle mindestens eine Datei für die Muse.';
  @override
  String get showMuseError => 'Muse-Fehler zeigen';
  @override
  String get museAsk => 'frage die Muse nach einer Richtung';
  @override
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => 'frage die Muse nach einer Richtung\n${brainstorm} → ${synthesis}';
  @override
  String get qualityFallback => 'qualität';
  @override
  String get reviewing => 'reviewe...';
  @override
  String get showReview => 'Review zeigen';
  @override
  String get reviewPreparing => 'bereite Commit-Review vor...';
  @override
  String get reviewSelectFile => 'wähle mindestens eine Datei zum Reviewen.';
  @override
  String get reviewConfigure => 'Review-AI in den Einstellungen konfigurieren.';
  @override
  String get viewingReview => 'sehe Review';
  @override
  String reviewWith({required Object guardrail, required Object label}) =>
      '${guardrail}-Review mit Modell ${label}';
}

// Path: changes.mergeEditor
class _Translations$changes$mergeEditor$de
    extends Translations$changes$mergeEditor$en {
  _Translations$changes$mergeEditor$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get resolutionYours => 'deins';
  @override
  String get resolutionTheirs => 'ihres';
  @override
  String get resolutionCustom => 'eigen';
  @override
  String get keepBoth => 'beide behalten';
  @override
  late final _Translations$changes$mergeEditor$trust$de trust =
      _Translations$changes$mergeEditor$trust$de._(_root);
  @override
  String get allResolved => 'alle gelöst';
  @override
  String get resolveEasy => 'einfache Konflikte lösen';
  @override
  String get base => 'basis';
  @override
  String get cancel => 'abbrechen';
  @override
  String get save => 'speichern';
  @override
  String get complete => 'abschließen';
  @override
  String get nextFile => 'nächste Datei';
  @override
  String get edit => 'bearbeiten';
  @override
  String get auto => 'auto';
  @override
  String get undo => 'rückgängig';
  @override
  late final _Translations$changes$mergeEditor$keyHints$de keyHints =
      _Translations$changes$mergeEditor$keyHints$de._(_root);
  @override
  String get favoredTooltip => 'strukturell durch Kopplungsanalyse bevorzugt';
  @override
  String get newOnBothSides => '(neu auf beiden Seiten)';
  @override
  String writeFailed({required Object error}) =>
      'Gelöste Dateien konnten nicht geschrieben werden: ${error}';
  @override
  String neighborsCoChanged({required Object changed, required Object total}) =>
      '${changed}/${total} Nachbarn mit-geändert';
  @override
  String integrity({required Object pct}) => 'Integrität ${pct}%';
  @override
  String reviewer({required Object name}) => 'Reviewer: ${name}';
}

// Path: changes.conflictResolution
class _Translations$changes$conflictResolution$de
    extends Translations$changes$conflictResolution$en {
  _Translations$changes$conflictResolution$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String noModelConfigured({required Object category}) =>
      'Kein Modell für "${category}" konfiguriert. Setze eins unter Einstellungen → AI.';
  @override
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} sensible Datei übersprungen — löse sie von Hand.',
        other: '${n} sensible Dateien übersprungen — löse sie von Hand.',
      );
  @override
  String get couldNotReadFiles =>
      'Es konnten keine Konfliktdateien gelesen werden.';
  @override
  String blockedSecret({required Object secret}) =>
      'Blockiert — eine Konfliktdatei sieht aus, als enthielte sie ein ${secret}. Löse sie von Hand.';
  @override
  String resolutionFailed({required Object error}) =>
      'Auflösung fehlgeschlagen: ${error}';
  @override
  String mergeResolutionLabel({
    required Object resolved,
    required Object total,
    required Object category,
  }) => '◇ Merge-Auflösung · ${resolved}/${total} Dateien · ${category}';
  @override
  String conflictSummary({
    required Object op,
    required Object conflicts,
    required Object files,
  }) => '${op} · ${conflicts} in ${files}';
  @override
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Konflikt',
        other: '${n} Konflikte',
      );
  @override
  String get mergeEditorButton => '⇋ merge-editor';
  @override
  String get noAiModel => 'kein AI-Modell';
  @override
  String get later => 'später';
  @override
  String get discard => 'verwerfen';
  @override
  String get resolveWithAi => '◇ mit AI lösen';
  @override
  String get otherModel => 'anderes Modell';
  @override
  String withModel({required Object model}) => 'mit ${model}';
}

// Path: changes.mergeFlow
class _Translations$changes$mergeFlow$de
    extends Translations$changes$mergeFlow$en {
  _Translations$changes$mergeFlow$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$mergeFlow$op$de op =
      _Translations$changes$mergeFlow$op$de._(_root);
  @override
  String get pushFailed => 'Push fehlgeschlagen';
  @override
  String get rebasedAndPushed => 'Rebased und gepusht.';
  @override
  String switchedTo({required Object name}) => 'Zu ${name} gewechselt.';
  @override
  String get switchFailed => 'Wechsel fehlgeschlagen.';
  @override
  String switchedToCarried({required Object name}) =>
      'Zu ${name} gewechselt (Änderungen übernommen).';
  @override
  String get alreadyUpToDate => 'Bereits aktuell.';
  @override
  String merged({required Object upstream, required Object n}) =>
      '${upstream} gemergt (${n} Dateien).';
  @override
  String get rebaseNotConverge => 'Rebase konvergierte nicht — löse manuell.';
  @override
  String get rebased => 'Rebased.';
  @override
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'Rebased (${n} Datei gelöst).',
        other: 'Rebased (${n} Dateien gelöst).',
      );
  @override
  String get detachedHead =>
      'Sync nicht möglich: Detached-HEAD-Zustand. Checke zuerst einen Branch aus.';
  @override
  String get publishFailed => 'Veröffentlichen fehlgeschlagen.';
  @override
  String get noRemote =>
      'Kein Remote konfiguriert. Füge eins hinzu, um diesen Branch zu veröffentlichen.';
  @override
  String get failed => 'fehlgeschlagen';
}

// Path: changes.constellation
class _Translations$changes$constellation$de
    extends Translations$changes$constellation$en {
  _Translations$changes$constellation$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get axisStructure => 'STRUKTUR';
  @override
  String get axisCoChange => 'CO-CHANGE';
  @override
  String get axisSpectralProfile => 'SPEKTRALPROFIL';
  @override
  String get axisPathSiblings => 'PFAD-GESCHWISTER';
  @override
  String get axisDiffStructure => 'DIFF-STRUKTUR';
  @override
  String get axisSpectral => 'SPEKTRAL';
  @override
  String get titleUnsorted => 'UNSORTIERT';
  @override
  String get titleSingleton => 'EINZELGÄNGER';
  @override
  String get titleMixed => 'GEMISCHT';
  @override
  String get untie => 'lösen';
  @override
  String get bind => 'binden';
  @override
  String get emptyClusters => 'noch keine Cluster';
}

// Path: common.time
class _Translations$common$time$de extends Translations$common$time$en {
  _Translations$common$time$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get now => 'jetzt';
  @override
  String get justNow => 'gerade eben';
  @override
  String get today => 'HEUTE';
  @override
  String minutesAgo({required Object n}) => 'vor ${n} Min';
  @override
  String hoursAgo({required Object n}) => 'vor ${n} Std';
  @override
  String daysAgo({required Object n}) => 'vor ${n} T';
  @override
  String weeksAgo({required Object n}) => 'vor ${n} Wo';
  @override
  String monthsAgo({required Object n}) => 'vor ${n} Mon';
  @override
  String yearsAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'vor ${n} J',
        other: 'vor ${n} J',
      );
  @override
  String minutesShort({required Object n}) => '${n} Min';
  @override
  String hoursShort({required Object n}) => '${n} Std';
  @override
  String daysShort({required Object n}) => '${n} T';
  @override
  String weeksShort({required Object n}) => '${n} Wo';
  @override
  String monthsShort({required Object n}) => '${n} Mon';
  @override
  String yearsShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} J',
        other: '${n} J',
      );
  @override
  String commitMonthsShort({required Object n}) => '${n} M';
  @override
  String get idle => 'ruht';
  @override
  String idleDays({required Object n}) => 'ruht seit ${n} Tagen';
  @override
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'ruht seit ${n} Jahr',
        other: 'ruht seit ${n} Jahren',
      );
  @override
  List<String> get monthAbbrevs => [
    'Jan',
    'Feb',
    'Mär',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ];
}

// Path: common.size
class _Translations$common$size$de extends Translations$common$size$en {
  _Translations$common$size$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

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
class _Translations$diff$status$de extends Translations$diff$status$en {
  _Translations$diff$status$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Lade Diff';
  @override
  String get loadingMessage => 'Lese Dateiänderungen.';
  @override
  String get unavailableTitle => 'Diff nicht verfügbar';
  @override
  String get noChangesTitle => 'Keine Änderungen';
  @override
  String get noChangesMessage =>
      'Diese Datei hat keinen Diff-Inhalt zum Anzeigen.';
}

// Path: diff.toolbar
class _Translations$diff$toolbar$de extends Translations$diff$toolbar$en {
  _Translations$diff$toolbar$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get searchHint => 'diff durchsuchen...';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Zeile',
        other: '${n} Zeilen',
      );
  @override
  String get blameLoading => 'blame...';
  @override
  String get blame => 'blame';
  @override
  String get wearMapOn => 'abnutzung · an';
  @override
  String get wearMapOnHint => 'abnutzungskarte an — klicken zum ausblenden';
  @override
  String get wearMapOffHint => 'abnutzungskarte zeigen (aktivitäts-heatmap)';
  @override
  String get trailBadge => '· spur';
}

// Path: diff.hunkDropdown
class _Translations$diff$hunkDropdown$de
    extends Translations$diff$hunkDropdown$en {
  _Translations$diff$hunkDropdown$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip => 'Zum Änderungsblock springen. Git nennt diese Hunks.';
  @override
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Änderung',
        other: '${n} Änderungen',
      );
}

// Path: diff.trail
class _Translations$diff$trail$de extends Translations$diff$trail$en {
  _Translations$diff$trail$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'lade spur...';
  @override
  String get noHistory => 'keine historie gefunden';
  @override
  String get nowWorkingCopy => 'jetzt · arbeitskopie';
  @override
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class _Translations$diff$pinned$de extends Translations$diff$pinned$en {
  _Translations$diff$pinned$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get loadingContext => 'lade angehefteten kontext';
  @override
  String get pageManifold => 'Manifold';
  @override
  String get pageSignals => 'Signale';
  @override
  String get echoesTitle => 'Echos';
  @override
  String get technicalLedger => 'Technisches Register';
  @override
  String get noSecondaryCues => 'Keine sekundären Hinweise erkannt.';
  @override
  String get linkedPaths => 'Verknüpfte Pfade';
  @override
  String moreCount({required Object n}) => '+${n} mehr';
  @override
  String get localSeam => 'Lokale Naht';
  @override
  String get sharedOwnership => 'geteilte zuständigkeit';
  @override
  String get historyWarmingUp => 'Historie wärmt sich auf';
  @override
  String echoesTotal({required Object n}) => '${n} GESAMT';
  @override
  String get noEchoes => 'Keine Echos in diesem Diff.';
  @override
  String openRelatedFile({required Object name}) =>
      'Verwandte Datei ${name} öffnen';
  @override
  String inspectFile({required Object name}) => '${name} untersuchen';
  @override
  String get jumpEcho => 'zu echo springen';
  @override
  String get copyLine => 'zeile kopieren';
  @override
  String get signalTempo => 'T';
  @override
  String get signalNovelty => 'N';
  @override
  String get signalReach => 'R';
  @override
  late final _Translations$diff$pinned$tempo$de tempo =
      _Translations$diff$pinned$tempo$de._(_root);
  @override
  late final _Translations$diff$pinned$tone$de tone =
      _Translations$diff$pinned$tone$de._(_root);
  @override
  late final _Translations$diff$pinned$summary$de summary =
      _Translations$diff$pinned$summary$de._(_root);
  @override
  late final _Translations$diff$pinned$tightness$de tightness =
      _Translations$diff$pinned$tightness$de._(_root);
  @override
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept} (${tightness})';
  @override
  String get storyWhyThisMatters => 'Warum das wichtig ist';
  @override
  String get storyConfidence => 'Konfidenz';
  @override
  String get storySecondarySignal => 'Sekundäres Signal';
  @override
  String get storyNeighbourhood => 'Nachbarschaft';
  @override
  String neighbourhoodDetail({required Object name}) =>
      'Diese Zeile sitzt nah an ${name} im aktuellen Codebasis-Feld.';
  @override
  String get propagationLane => 'Ausbreitungsbahn';
  @override
  String propagationLaneNamed({required Object lane}) =>
      'Ausbreitungsbahn: ${lane}';
  @override
  late final _Translations$diff$pinned$witness$de witness =
      _Translations$diff$pinned$witness$de._(_root);
  @override
  late final _Translations$diff$pinned$integrity$de integrity =
      _Translations$diff$pinned$integrity$de._(_root);
  @override
  late final _Translations$diff$pinned$related$de related =
      _Translations$diff$pinned$related$de._(_root);
  @override
  late final _Translations$diff$pinned$axis$de axis =
      _Translations$diff$pinned$axis$de._(_root);
}

// Path: diff.hunkHint
class _Translations$diff$hunkHint$de extends Translations$diff$hunkHint$en {
  _Translations$diff$hunkHint$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String hiddenCount({required Object n}) => '${n} versteckt';
  @override
  String get landing => 'landung';
}

// Path: diff.binary
class _Translations$diff$binary$de extends Translations$diff$binary$en {
  _Translations$diff$binary$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String tooLargeToPreview({required Object size}) =>
      '${size} MB (zu groß für Vorschau)';
  @override
  String get unableToLoadBlob => 'Blob konnte nicht geladen werden';
  @override
  String get omittedKindMedia => 'medien';
  @override
  String get omittedKindBinary => 'binär';
  @override
  String omittedStub({required Object kind}) => '${kind} · versteckt';
}

// Path: diff.media
class _Translations$diff$media$de extends Translations$diff$media$en {
  _Translations$diff$media$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get unableToDecodeImage => 'Bild konnte nicht dekodiert werden';
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
  String get stateAdded => 'hinzugefügt';
  @override
  String get stateDeleted => 'gelöscht';
  @override
  String get stateModified => 'geändert';
  @override
  String get fallbackFormatName => 'Binär';
}

// Path: filament.severity
class _Translations$filament$severity$de
    extends Translations$filament$severity$en {
  _Translations$filament$severity$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get critical => 'kritisch';
  @override
  String get warn => 'warnung';
  @override
  String get info => 'info';
  @override
  String get joint => 'gelenk';
}

// Path: filament.kind
class _Translations$filament$kind$de extends Translations$filament$kind$en {
  _Translations$filament$kind$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get staleValue => 'veralteter wert';
  @override
  String get temporalShift => 'zeitliche verschiebung';
  @override
  String get contextInversion => 'kontext-inversion';
  @override
  String get contradictoryFlow => 'widersprüchlicher fluss';
}

// Path: history.commitLede
class _Translations$history$commitLede$de
    extends Translations$history$commitLede$en {
  _Translations$history$commitLede$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$semantics$de semantics =
      _Translations$history$commitLede$semantics$de._(_root);
}

// Path: history.seismograph
class _Translations$history$seismograph$de
    extends Translations$history$seismograph$en {
  _Translations$history$seismograph$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get rootTrackLabel => '(root)';
  @override
  String dirTrackLabel({required Object name}) => '(${name})';
  @override
  String moreLabel({required Object n}) => '+${n} mehr';
  @override
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Datei in ${path}/',
        other: '${n} Dateien in ${path}/',
      );
  @override
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} weitere Datei',
        other: '${n} weitere Dateien',
      );
  @override
  String get breadcrumbAll => 'alle';
  @override
  String breadcrumbCurrentFocus({required Object target}) =>
      'Aktueller Fokus: ${target}';
  @override
  String get breadcrumbViewAllChanges =>
      'Alle Änderungen in diesem Commit ansehen';
  @override
  String breadcrumbDrillUpTo({required Object target}) => 'Hoch zu ${target}';
  @override
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    n,
    one: '${n} Datei  +${adds}  -${dels}',
    other: '${n} Dateien  +${adds}  -${dels}',
  );
  @override
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Unterverz.',
        other: '${n} Unterverz.',
      );
  @override
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}, ${adds} hinzugefügt, ${dels} gelöscht';
  @override
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    n,
    one: '${n} Datei, ${adds} hinzugefügt, ${dels} gelöscht',
    other: '${n} Dateien, ${adds} hinzugefügt, ${dels} gelöscht',
  );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Hunk',
        other: '${n} Hunks',
      );
  @override
  String get largestChangeInView => 'größte Änderung in dieser Ansicht';
  @override
  String get conflictedTag => 'Konflikt';
  @override
  String get dirtyTag => 'unsauber';
  @override
  String get drillInTag => 'eintauchen';
  @override
  String get changeTypeRenamed => 'umbenannt';
  @override
  String get changeTypeCopied => 'kopiert';
  @override
  String get changeTypeTypechange => 'typänderung';
  @override
  String get changeTypeConflict => 'konflikt';
  @override
  String get coreFile => 'Kerndatei';
  @override
  String get staleFile => 'veraltet';
  @override
  String get filterPathHint => 'pfad filtern';
  @override
  String get escHint => 'esc';
}

// Path: history.worldline
class _Translations$history$worldline$de
    extends Translations$history$worldline$en {
  _Translations$history$worldline$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get closeWorldline => 'Weltlinie schließen';
  @override
  String get dragToOpenWorldline => 'Ziehen, um Weltlinie zu öffnen';
}

// Path: history.contextMenu
class _Translations$history$contextMenu$de
    extends Translations$history$contextMenu$en {
  _Translations$history$contextMenu$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get currentBranchFallback => 'aktueller Branch';
  @override
  String applyCommitOnto({required Object branch}) =>
      'Commit-Änderungen auf ${branch} anwenden';
  @override
  String revertCommitOn({required Object branch}) =>
      'Commit-Änderungen auf ${branch} rückgängig machen';
}

// Path: history.cherryPick
class _Translations$history$cherryPick$de
    extends Translations$history$cherryPick$en {
  _Translations$history$cherryPick$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Cherry-Pick pausiert. Schließe die restlichen Konflikte auf der Änderungen-Seite ab.';
  @override
  String failed({required Object error}) =>
      'Cherry-Pick fehlgeschlagen: ${error}';
  @override
  String pickedResolved({required Object short}) =>
      '${short} cherry-gepickt (Konflikte gelöst)';
  @override
  String picked({required Object short}) => '${short} cherry-gepickt';
}

// Path: history.revert
class _Translations$history$revert$de extends Translations$history$revert$en {
  _Translations$history$revert$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Revert pausiert. Schließe die restlichen Konflikte auf der Änderungen-Seite ab.';
  @override
  String failed({required Object error}) => 'Revert fehlgeschlagen: ${error}';
  @override
  String revertedResolved({required Object short}) =>
      '${short} rückgängig gemacht (Konflikte gelöst)';
  @override
  String reverted({required Object short}) => '${short} rückgängig gemacht';
}

// Path: history.reflog
class _Translations$history$reflog$de extends Translations$history$reflog$en {
  _Translations$history$reflog$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get createBranchFromHere => 'Branch von hier erstellen…';
  @override
  String get copyCommitHash => 'Commit-Hash kopieren';
  @override
  String get createBranchDialogTitle => 'Branch aus Reflog-Eintrag erstellen';
  @override
  String anchorLine({required Object short, required Object summary}) =>
      'Anker: ${short}  ·  ${summary}';
  @override
  String get branchNameHint => 'Branch-Name';
  @override
  String get createAction => 'Erstellen';
  @override
  String createBranchFailed({required Object error}) =>
      'Branch konnte nicht erstellt werden: ${error}';
  @override
  String branchCreatedAt({required Object name, required Object short}) =>
      'Branch "${name}" bei ${short} erstellt.';
}

// Path: history.rebase
class _Translations$history$rebase$de extends Translations$history$rebase$en {
  _Translations$history$rebase$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String firstCommitCannotBe({required Object action}) =>
      'Erster Commit kann nicht ${action} werden';
  @override
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Commit rebasen',
        other: '${n} Commits rebasen',
      );
  @override
  String get resetLabel => 'zurücksetzen';
  @override
  String get dragToReorderHint =>
      'ziehen zum Umordnen, Aktion pro Commit wählen';
  @override
  String get newMessageHint => 'neue Nachricht';
  @override
  String get runningEllipsis => '…';
  @override
  String get startRebase => 'Rebase starten';
}

// Path: history.inFlight
class _Translations$history$inFlight$de
    extends Translations$history$inFlight$en {
  _Translations$history$inFlight$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'UNTERWEGS';
  @override
  String get deskFallbackLabel => 'desk';
}

// Path: historySurgery.chrome
class _Translations$historySurgery$chrome$de
    extends Translations$historySurgery$chrome$en {
  _Translations$historySurgery$chrome$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Historien-Chirurgie';
  @override
  String get alphaBadge => 'alpha';
  @override
  String get dryRunBadge => 'TROCKENLAUF';
}

// Path: historySurgery.select
class _Translations$historySurgery$select$de
    extends Translations$historySurgery$select$en {
  _Translations$historySurgery$select$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get prompt =>
      'Wähle Dateien, die aus der Historie entfernt werden sollen';
  @override
  String selectedCount({required Object n}) => '${n} ausgewählt';
  @override
  String get searchHint => 'suchen...';
  @override
  String get readingTree => 'lese baum...';
  @override
  String get continueDisabled => 'wähle Dateien zum Fortfahren';
  @override
  String get continueEnabled => 'weiter →';
  @override
  String toPurgeCount({required Object n}) => '${n} zu tilgen';
  @override
  String get analyzing => 'analysiere...';
  @override
  String get riskLow => 'geringes Risiko';
  @override
  String get riskModerate => 'mittleres Risiko';
  @override
  String get riskHigh => 'hohes Risiko';
  @override
  String get impactCommitsLabel => 'Commits';
  @override
  String get impactBranchesLabel => 'Branches';
  @override
  String get impactWorktreesLabel => 'Worktrees';
  @override
  String get impactCouplingLabel => 'Kopplung';
  @override
  String get impactCouplingIsland => 'Insel';
  @override
  String impactCouplingNeighbors({required Object n}) => '${n} Nachbarn';
  @override
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class _Translations$historySurgery$understand$de
    extends Translations$historySurgery$understand$en {
  _Translations$historySurgery$understand$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get heading => 'So funktioniert das';
  @override
  String get backupTitle => 'Backup';
  @override
  String get backupBody =>
      'Jede Branch- und Tag-Ref wird in einen Backup-Namespace kopiert, bevor sich etwas ändert. Falls etwas schiefgeht, stellt ein Klick den Ursprungszustand wieder her.';
  @override
  String get rewriteTitle => 'Neuschreiben';
  @override
  String get rewriteBody =>
      'Jeder Commit wird von der Wurzel bis zur Spitze durchlaufen. Für jeden Commit, der die Zieldateien enthält, wird ein neuer Commit erstellt, in dessen Baum diese Dateien entfernt sind. Elternketten werden neu zugeordnet, um die Topologie zu erhalten. ';
  @override
  String rewriteSummary({required Object affected, required Object total}) =>
      '${affected} von ${total} Commits werden neu geschrieben.';
  @override
  String get updateRefsTitle => 'Refs aktualisieren';
  @override
  String get updateRefsBody =>
      'Branch- und Tag-Zeiger werden auf die neuen Commit-SHAs verschoben. Die alten Objekte existieren weiter, bis die Garbage Collection greift. ';
  @override
  String worktreesNeedRecheckout({required Object n}) =>
      'Deine ${n} Worktree(s) müssen neu ausgecheckt werden.';
  @override
  String get noWorktreesAffected => 'Keine Worktrees betroffen.';
  @override
  String get forcePushTitle => 'Force-Push';
  @override
  String get forcePushBody =>
      'Nach der Prüfung der Tilgung wählst du, welche Branches force-gepusht werden. Nutzt --force-with-lease, sodass es sicher fehlschlägt, falls jemand anderes zwischenzeitlich gepusht hat.';
  @override
  String get plumbingNote =>
      'Anders als filter-repo oder BFG läuft das komplett über Git-Plumbing-Befehle (cat-file, mktree, commit-tree, update-ref). Keine externen Abhängigkeiten. Das Umbenennungs-Tracking folgt einer Kette pro Datei — falls eine Datei kopiert und beide Kopien unabhängig umbenannt wurden, prüfe das Tilgungsergebnis nach der Ausführung.';
  @override
  String get back => '← Zurück';
  @override
  String get continueLabel => 'Verstanden, weiter →';
}

// Path: historySurgery.confirm
class _Translations$historySurgery$confirm$de
    extends Translations$historySurgery$confirm$en {
  _Translations$historySurgery$confirm$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String commitsRewritten({required Object n}) =>
      '${n} Commits werden neu geschrieben';
  @override
  String get forcePushRequired =>
      'Für Remote-Branches ist ein Force-Push erforderlich';
  @override
  String worktreesRecheckout({required Object n}) =>
      '${n} Worktrees müssen neu ausgecheckt werden';
  @override
  String stashesInvalid({required Object n}) =>
      '${n} Stashes könnten ungültig werden';
  @override
  String get heading => 'Diese Operation schreibt die Git-Historie neu';
  @override
  String get subheading =>
      'Nach dem Force-Push lässt sie sich nicht automatisch rückgängig machen.';
  @override
  String typeHint({required Object word}) => 'tippe ${word}';
  @override
  String get goBack => 'Zurück';
  @override
  String get begin => 'Chirurgie beginnen';
}

// Path: historySurgery.execute
class _Translations$historySurgery$execute$de
    extends Translations$historySurgery$execute$en {
  _Translations$historySurgery$execute$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => 'Bereite vor...';
  @override
  String get backingUpRefs => 'Sichere Refs...';
  @override
  String get rewritingCommits => 'Schreibe Commits neu...';
  @override
  String get updatingRefs => 'Aktualisiere Refs...';
}

// Path: historySurgery.verify
class _Translations$historySurgery$verify$de
    extends Translations$historySurgery$verify$en {
  _Translations$historySurgery$verify$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get complete => 'Chirurgie abgeschlossen';
  @override
  String get failed => 'Chirurgie fehlgeschlagen';
  @override
  String get commitsRewrittenLabel => 'Commits neu geschrieben';
  @override
  String get refsUpdatedLabel => 'Refs aktualisiert';
  @override
  String get oldHeadLabel => 'Altes HEAD';
  @override
  String get newHeadLabel => 'Neues HEAD';
  @override
  String get purgeVerifiedLabel => 'Tilgung geprüft';
  @override
  String get purgeClean => 'sauber';
  @override
  String get purgeTracesRemain => 'SPUREN VERBLEIBEN';
  @override
  String get displacedWorktrees => 'Verdrängte Worktrees';
  @override
  String get undoSurgery => 'Chirurgie rückgängig machen';
  @override
  String get rolledBack => 'Auf Backup-Refs zurückgesetzt.';
  @override
  String get done => 'Fertig';
}

// Path: historySurgery.forcePush
class _Translations$historySurgery$forcePush$de
    extends Translations$historySurgery$forcePush$en {
  _Translations$historySurgery$forcePush$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get pushing => 'pushe...';
  @override
  String get forcePushAll => 'Alle force-pushen';
  @override
  String get confirmPush => 'Push bestätigen';
  @override
  String get cancel => 'abbrechen';
}

// Path: onboarding.nav
class _Translations$onboarding$nav$de extends Translations$onboarding$nav$en {
  _Translations$onboarding$nav$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get back => 'Zurück';
  @override
  String get continueLabel => 'Weiter';
  @override
  String get letsGo => 'Los geht\'s';
}

// Path: onboarding.naming
class _Translations$onboarding$naming$de
    extends Translations$onboarding$naming$en {
  _Translations$onboarding$naming$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'was ist das für dich?';
  @override
  String get questionEmphasis => 'das';
  @override
  String get iAmPrefix => 'Ich bin ';
  @override
  String get iAmSuffix => ' , dein persönlicher Git-Client.';
}

// Path: onboarding.theme
class _Translations$onboarding$theme$de
    extends Translations$onboarding$theme$en {
  _Translations$onboarding$theme$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'mach ${name} schick.';
  @override
  String get themesHeader => 'THEMES';
  @override
  String get keybindingsHeader => 'TASTENKÜRZEL';
  @override
  String get previewBadge => 'vorschau';
  @override
  String get useDefaults => 'standard nutzen';
}

// Path: onboarding.repo
class _Translations$onboarding$repo$de extends Translations$onboarding$repo$en {
  _Translations$onboarding$repo$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'richte ${name} auf etwas.';
  @override
  String get later => 'mach ich später';
  @override
  late final _Translations$onboarding$repo$doors$de doors =
      _Translations$onboarding$repo$doors$de._(_root);
  @override
  late final _Translations$onboarding$repo$cloneForm$de cloneForm =
      _Translations$onboarding$repo$cloneForm$de._(_root);
  @override
  late final _Translations$onboarding$repo$pickers$de pickers =
      _Translations$onboarding$repo$pickers$de._(_root);
  @override
  late final _Translations$onboarding$repo$errors$de errors =
      _Translations$onboarding$repo$errors$de._(_root);
}

// Path: onboarding.preview
class _Translations$onboarding$preview$de
    extends Translations$onboarding$preview$en {
  _Translations$onboarding$preview$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$preview$panels$de panels =
      _Translations$onboarding$preview$panels$de._(_root);
  @override
  late final _Translations$onboarding$preview$sidebar$de sidebar =
      _Translations$onboarding$preview$sidebar$de._(_root);
  @override
  late final _Translations$onboarding$preview$changes$de changes =
      _Translations$onboarding$preview$changes$de._(_root);
  @override
  late final _Translations$onboarding$preview$history$de history =
      _Translations$onboarding$preview$history$de._(_root);
  @override
  late final _Translations$onboarding$preview$branches$de branches =
      _Translations$onboarding$preview$branches$de._(_root);
  @override
  late final _Translations$onboarding$preview$diff$de diff =
      _Translations$onboarding$preview$diff$de._(_root);
}

// Path: orrery.header
class _Translations$orrery$header$de extends Translations$orrery$header$en {
  _Translations$orrery$header$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Orrery';
  @override
  String get modeScrub => 'Scrubben';
  @override
  String get modeCompare => 'Vergleichen';
  @override
  String get lodModules => 'Module';
  @override
  String get lodFiles => 'Dateien';
}

// Path: orrery.status
class _Translations$orrery$status$de extends Translations$orrery$status$en {
  _Translations$orrery$status$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'Verfolge die manifold durch die Historie…';
  @override
  String get loadError =>
      'Die Historie dieses Repos konnte nicht gelesen werden.';
  @override
  String get notEnoughHistory =>
      'Noch nicht genug Historie, um eine Trajektorie zu zeichnen.';
  @override
  String get notEnoughHistoryDetail =>
      'Die Orrery braucht ein paar Commits zum Kartieren.';
}

// Path: orrery.legend
class _Translations$orrery$legend$de extends Translations$orrery$legend$en {
  _Translations$orrery$legend$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get central => 'zentral';
  @override
  String get peripheral => 'peripher';
}

// Path: orrery.node
class _Translations$orrery$node$de extends Translations$orrery$node$en {
  _Translations$orrery$node$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get module => 'modul';
  @override
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · ${n} Dateien';
  @override
  String fileFallback({required Object id}) => 'Datei #${id}';
  @override
  String nodeFallback({required Object id}) => 'Knoten #${id}';
  @override
  String get rootModule => '(root)';
}

// Path: orrery.milestone
class _Translations$orrery$milestone$de
    extends Translations$orrery$milestone$en {
  _Translations$orrery$milestone$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get genesis => 'genesis';
  @override
  String get now => 'jetzt';
  @override
  String get reorganized => 'reorganisiert';
  @override
  String becameArchetype({required Object archetype}) =>
      'wurde zu ${archetype}';
  @override
  String get snapshot => 'schnappschuss';
}

// Path: orrery.structure
class _Translations$orrery$structure$de
    extends Translations$orrery$structure$en {
  _Translations$orrery$structure$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get forming => 'bildet sich…';
  @override
  String get canonical => 'kanonisch';
  @override
  String get connectivity => 'konnektivität';
  @override
  String get rigidity => 'starrheit';
  @override
  String get entropy => 'entropie';
}

// Path: orrery.rail
class _Translations$orrery$rail$de extends Translations$orrery$rail$en {
  _Translations$orrery$rail$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get structureLabel => 'STRUKTUR';
  @override
  String get fieldLabel => 'FELD';
  @override
  String get findingsLabel => 'FUNDE';
  @override
  String get selectedLabel => 'AUSGEWÄHLT';
  @override
  String get noFindings =>
      'Keine strukturellen Ereignisse in dieser Historie erkannt.';
}

// Path: orrery.selection
class _Translations$orrery$selection$de
    extends Translations$orrery$selection$en {
  _Translations$orrery$selection$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get notPresent => 'An diesem Punkt der Historie nicht vorhanden.';
  @override
  String get roleCentral =>
      'Kopplungs-zentral — Änderungen hier wirken sich auf das ganze System aus.';
  @override
  String get rolePeripheral =>
      'Peripher — lose gekoppelt, ändert sich meist eigenständig.';
  @override
  String get roleMid => 'Mittelstruktur — mäßig gekoppelt.';
  @override
  String get driftOutward => ' Driftet nach außen — entkoppelt sich.';
  @override
  String get driftInward => ' Driftet nach innen — integriert sich.';
  @override
  String get driftHolding => ' Hält seine Position.';
}

// Path: orrery.findingKind
class _Translations$orrery$findingKind$de
    extends Translations$orrery$findingKind$en {
  _Translations$orrery$findingKind$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get hub => 'HUB';
  @override
  String get driftOut => 'DRIFTET RAUS';
  @override
  String get driftIn => 'DRIFTET REIN';
  @override
  String get tangle => 'VERKNOTUNG';
  @override
  String get clarify => 'KLÄRUNG';
  @override
  String get regime => 'REORG';
  @override
  String get thrash => 'GESTAMPFE';
  @override
  String get reshuffle => 'UMSCHICHTUNG';
  @override
  String get forecast => 'PROGNOSE';
}

// Path: orrery.findings
class _Translations$orrery$findings$de extends Translations$orrery$findings$en {
  _Translations$orrery$findings$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get forecastSplit =>
      'Die Konnektivität ist gefallen und nahe ihrem Tiefpunkt — hält das an, steuert die Codebasis auf eine Aufspaltung in lose gekoppelte Hälften zu. Entscheide jetzt, ob das so gewollt ist.';
  @override
  String get forecastConsolidate =>
      'Die Konnektivität steigt auf ihren Höchststand zu — hält das an, verdichtet sich die Codebasis zu einer eng gekoppelten Masse. Achte darauf, dass sie nicht zum Monolithen erstarrt.';
  @override
  String thrash({required Object name}) =>
      '${name} wird ständig hin und her reorganisiert — viel struktureller Wirbel, kaum Nettobewegung. Kläre seine Kopplung oder lass es in Ruhe.';
  @override
  String get reshuffle =>
      'Dieser Commit sah routinemäßig aus, verschob aber still, welche Dateien zentral sind — die Gesamtform hielt, während sich die Struktur darunter umschichtete. Prüfe ihn sorgfältig.';
  @override
  String hub({required Object name}) =>
      '${name} sitzt im strukturellen Kern — das System reorganisiert sich um ihn herum. Behandle Änderungen hier als hoch-explosiv.';
  @override
  String driftOut({required Object name}) =>
      '${name} ist vom Kern zum Rand gedriftet — es entkoppelt sich vom System. Entweder wird es ausgemustert oder es verrottet still.';
  @override
  String driftIn({required Object name}) =>
      '${name} ist zum Kern gewandert — es wird tragend. Stelle sicher, dass es gut getestet ist, bevor mehr davon abhängt.';
  @override
  String get regime =>
      'Die Codebasis hat sich hier stark reorganisiert — ihre Konnektivität sprang. Prüfe, was sich abspaltete oder verschmolz.';
  @override
  String get tangleTrend =>
      'Über ihre Historie hinweg tendierte die Codebasis zu einer verknoteteren Struktur — ihre Konnektivität wird dichter und weniger modular.';
  @override
  String get clarifyTrend =>
      'Über ihre Historie hinweg tendierte die Codebasis zu einer saubereren Struktur — sie trennt sich in klarere Module.';
}

// Path: orrery.anchor
class _Translations$orrery$anchor$de extends Translations$orrery$anchor$en {
  _Translations$orrery$anchor$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get core => 'kern';
  @override
  String get drift => 'drift';
  @override
  String get trend => 'trend';
  @override
  String get thrash => 'gestampfe';
}

// Path: orrery.compare
class _Translations$orrery$compare$de extends Translations$orrery$compare$en {
  _Translations$orrery$compare$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'A → B';
  @override
  String get change => 'ÄNDERUNG';
  @override
  String get movers => 'BEWEGER';
  @override
  String get noMovers => 'Keine Dateien zwischen diesen Frames bewegt.';
  @override
  String get badgeA => 'A';
  @override
  String get badgeB => 'B';
  @override
  String get deltaFiles => 'dateien';
  @override
  String get deltaConnectivity => 'konnektivität';
  @override
  String get deltaRigidity => 'starrheit';
  @override
  String get deltaEntropy => 'entropie';
  @override
  String get wayOutward => 'nach außen';
  @override
  String get wayInward => 'nach innen';
  @override
  String get wayShifted => 'verschoben';
}

// Path: palette.prefixes
class _Translations$palette$prefixes$de
    extends Translations$palette$prefixes$en {
  _Translations$palette$prefixes$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get askHint => 'frag: [frage]';
  @override
  String get nearHint => 'nah: [datei]';
  @override
  String get whoHint => 'wer: [datei]';
  @override
  String get logHint => 'log: [nachricht]';
  @override
  String get runHint => 'starte: [tool]';
  @override
  String askLabel({required Object name, required Object body}) =>
      'Frag ${name}: ${body}';
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
  }) => '${path} · ${count} Reviewer · ${touches} Berührungen';
  @override
  String whoTouchesLabel({required Object name, required Object touches}) =>
      '${name} — ${touches} Berührungen';
  @override
  String whoTouchesSubtitle({required Object path}) =>
      '${path} · keine Reviewer erfasst';
}

// Path: palette.chips
class _Translations$palette$chips$de extends Translations$palette$chips$en {
  _Translations$palette$chips$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get ai => 'AI';
  @override
  String get near => 'NAH';
  @override
  String get who => 'WER';
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
  String get hot => 'HEISS';
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
  String get desk => 'TISCH';
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
  String get local => 'LOKAL';
  @override
  String get an => 'AN';
  @override
  String get lw => 'LW';
}

// Path: palette.predictive
class _Translations$palette$predictive$de
    extends Translations$palette$predictive$en {
  _Translations$palette$predictive$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String momentumSuffix({required Object percent}) => '${percent}% Momentum';
}

// Path: palette.topTouched
class _Translations$palette$topTouched$de
    extends Translations$palette$topTouched$en {
  _Translations$palette$topTouched$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object count, required Object path}) =>
      '${count} Berührungen · ${path}';
}

// Path: palette.coherence
class _Translations$palette$coherence$de
    extends Translations$palette$coherence$en {
  _Translations$palette$coherence$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String label({required Object percent}) => 'Staging-Kohärenz: ${percent}%';
  @override
  String subtitle({required Object count}) => '${count} Dateien';
}

// Path: palette.keystone
class _Translations$palette$keystone$de
    extends Translations$palette$keystone$en {
  _Translations$palette$keystone$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object path, required Object score}) =>
      '${path} · Schlussstein ${score}';
}

// Path: palette.repoSub
class _Translations$palette$repoSub$de extends Translations$palette$repoSub$en {
  _Translations$palette$repoSub$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String changes({required Object name}) => 'Änderungen in ${name}';
  @override
  String history({required Object name}) => 'Verlauf in ${name}';
  @override
  String branches({required Object name}) => 'Branches in ${name}';
  @override
  String terminal({required Object name}) => 'Terminal in ${name}';
  @override
  String generateCommit({required Object name}) =>
      'Commit generieren · ${name}';
  @override
  String reviewChanges({required Object name}) =>
      'Änderungen prüfen in ${name}';
  @override
  String muse({required Object name}) => 'Muse in ${name}';
}

// Path: palette.desks
class _Translations$palette$desks$de extends Translations$palette$desks$en {
  _Translations$palette$desks$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get mainWorktree => 'Haupt-Worktree';
  @override
  String get detached => 'detached';
  @override
  String dirty({required Object count}) => '${count} unsauber';
}

// Path: palette.actions
class _Translations$palette$actions$de extends Translations$palette$actions$en {
  _Translations$palette$actions$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get openInBrowser => 'Im Browser öffnen';
  @override
  String get terminal => 'Terminal';
  @override
  String get revealInFiles => 'Im Dateimanager zeigen';
  @override
  String get copyPath => 'Pfad kopieren';
  @override
  String get copyBranch => 'Branch kopieren';
}

// Path: palette.tools
class _Translations$palette$tools$de extends Translations$palette$tools$en {
  _Translations$palette$tools$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String launch({required Object label}) => '${label} starten';
}

// Path: palette.gitCommands
class _Translations$palette$gitCommands$de
    extends Translations$palette$gitCommands$en {
  _Translations$palette$gitCommands$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get fetch => 'Fetch';
  @override
  String get pull => 'Pull';
  @override
  String pullBehind({required Object count}) => '${count} zurück';
  @override
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';
  @override
  String get push => 'Push';
  @override
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Commit',
        other: '${n} Commits',
      );
  @override
  String pushCommitsUpstream({
    required Object commits,
    required Object upstream,
  }) => '${commits} nach ${upstream}';
  @override
  String get forcePush => 'Force-Push';
  @override
  String forcePushNoUpstream({required Object branch}) =>
      'Force-Push nicht möglich: kein Upstream für ${branch} gesetzt.';
  @override
  String get commit => 'Commit';
  @override
  String get stageAll => 'Alles stagen';
  @override
  String get unstageAll => 'Alles unstagen';
  @override
  String get discardAll => 'Alles verwerfen';
  @override
  String get createBranch => 'Branch erstellen';
  @override
  String get deleteBranch => 'Branch löschen';
  @override
  String get renameBranch => 'Branch umbenennen';
  @override
  String get stash => 'Stash';
  @override
  String get stashPop => 'Stash Pop';
  @override
  String get stashApply => 'Stash Apply';
  @override
  String get stashDrop => 'Stash Drop';
  @override
  String get createTag => 'Tag erstellen';
  @override
  String get cherryPick => 'Cherry-Pick';
  @override
  String get revert => 'Revert';
  @override
  String get stashConflictMessage =>
      'Stash mit Konflikten angewendet. Löse sie auf der Änderungen-Seite.';
}

// Path: palette.pr
class _Translations$palette$pr$de extends Translations$palette$pr$en {
  _Translations$palette$pr$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get create => 'PR erstellen';
  @override
  String get merge => 'PR mergen';
  @override
  String get markReady => 'PR als bereit markieren';
}

// Path: palette.ai
class _Translations$palette$ai$de extends Translations$palette$ai$en {
  _Translations$palette$ai$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get generateCommit => 'Commit generieren';
  @override
  String get reviewChanges => 'Änderungen prüfen';
  @override
  String get runMuse => 'Muse starten';
  @override
  String debugRepo({required Object name}) => '${name} debuggen';
  @override
  String get describeSymptom => 'beschreibe ein Symptom';
  @override
  String viewResult({required Object kind}) => '${kind} ansehen';
  @override
  String get unseenResult => 'ungesehenes Ergebnis';
  @override
  String runningResult({required Object kind}) => 'AI: ${kind}…';
  @override
  String get running => 'läuft';
  @override
  String get kindCommitMessage => 'Commit-Nachricht';
  @override
  String get kindCodeReview => 'Code-Review';
  @override
  String get kindMuseResult => 'Muse-Ergebnis';
  @override
  String get kindPresentation => 'Präsentation';
  @override
  String get kindDebugResult => 'Debug-Ergebnis';
}

// Path: palette.undo
class _Translations$palette$undo$de extends Translations$palette$undo$en {
  _Translations$palette$undo$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String cancel({required Object label}) => 'Abbrechen: ${label}';
}

// Path: palette.navigation
class _Translations$palette$navigation$de
    extends Translations$palette$navigation$en {
  _Translations$palette$navigation$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get changes => 'Änderungen';
  @override
  String get history => 'Verlauf';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get settings => 'Einstellungen';
  @override
  String get refresh => 'Aktualisieren';
}

// Path: palette.settings
class _Translations$palette$settings$de
    extends Translations$palette$settings$en {
  _Translations$palette$settings$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get reduceMotion => 'Bewegung reduzieren';
  @override
  String get animateLogoUnfocused => 'Logo unfokussiert animieren';
  @override
  String get instantBlameHover => 'Sofort-Blame beim Hovern';
  @override
  String get autoSelectChanges => 'Änderungen auto-auswählen';
  @override
  String get fetchOnlineIssues => 'Online-Issues abrufen';
  @override
  String get rememberWip => 'Work in Progress merken';
  @override
  String get hideAiFeatures => 'AI-Funktionen ausblenden';
  @override
  String get crashReporting => 'Absturzberichte';
  @override
  String get aiReadOnly => 'AI schreibgeschützt';
  @override
  String get stashCabinetExpanded => 'Stash-Schrank ausgeklappt';
  @override
  String get fileSortInverted => 'Dateisortierung umgekehrt';
}

// Path: palette.info
class _Translations$palette$info$de extends Translations$palette$info$en {
  _Translations$palette$info$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class _Translations$palette$debug$de extends Translations$palette$debug$en {
  _Translations$palette$debug$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get engineStatus => 'Engine-Status';
  @override
  String get engineStatusSubtitle => 'LogosGit Spektral-Engine-Diagnostik';
  @override
  String get fileCoupling => 'Datei-Kopplung';
  @override
  String get fileCouplingSubtitle =>
      'Nächste Co-Change-Nachbarn für gestagte Dateien';
  @override
  String get themeSpecimen => 'Theme-Muster';
  @override
  String get themeSpecimenSubtitle =>
      'Alle Farben, Icons, Text-Tiers und Geometrie';
}

// Path: palette.dev
class _Translations$palette$dev$de extends Translations$palette$dev$en {
  _Translations$palette$dev$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get testMergeEditor => 'Merge-Editor testen';
  @override
  String get testHistorySurgery => 'Historien-Chirurgie testen';
  @override
  String get back => 'zurück';
  @override
  String get cancel => 'abbrechen';
  @override
  String get buildingConflicts => 'baue Testkonflikte aus der Historie…';
}

// Path: palette.historySurgery
class _Translations$palette$historySurgery$de
    extends Translations$palette$historySurgery$en {
  _Translations$palette$historySurgery$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Historien-Chirurgie';
  @override
  String get subtitle =>
      'Historie neu schreiben, um Dateien dauerhaft zu entfernen';
}

// Path: palette.orrery
class _Translations$palette$orrery$de extends Translations$palette$orrery$en {
  _Translations$palette$orrery$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Orrery';
  @override
  String get subtitle =>
      'Scrubbe die strukturelle Historie des Repos durch die manifold';
}

// Path: palette.command
class _Translations$palette$command$de extends Translations$palette$command$en {
  _Translations$palette$command$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String complete({required Object label}) => '${label} abgeschlossen';
  @override
  String failed({required Object label, required Object message}) =>
      '${label} fehlgeschlagen: ${message}';
  @override
  String get copy => 'Kopieren';
}

// Path: palette.search
class _Translations$palette$search$de extends Translations$palette$search$en {
  _Translations$palette$search$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get hintDefault => 'alles durchsuchen...';
  @override
  String get hintElevated => 'erhöht — alle Aktionen';
  @override
  String get emptyTypeToSearch => 'tippen zum Suchen';
  @override
  String get emptyNoResults => 'keine Ergebnisse';
}

// Path: palette.wick
class _Translations$palette$wick$de extends Translations$palette$wick$en {
  _Translations$palette$wick$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'wick';
  @override
  String get coupledFallback => 'gekoppelt';
}

// Path: palette.gitCache
class _Translations$palette$gitCache$de
    extends Translations$palette$gitCache$en {
  _Translations$palette$gitCache$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'aktuell';
  @override
  String get staged => 'gestaged';
  @override
  String get modified => 'geändert';
}

// Path: releaseNotes.about
class _Translations$releaseNotes$about$de
    extends Translations$releaseNotes$about$en {
  _Translations$releaseNotes$about$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$releaseNotes$about$whyFlutter$de whyFlutter =
      _Translations$releaseNotes$about$whyFlutter$de._(_root);
  @override
  late final _Translations$releaseNotes$about$spectralEngine$de spectralEngine =
      _Translations$releaseNotes$about$spectralEngine$de._(_root);
  @override
  late final _Translations$releaseNotes$about$whereGoing$de whereGoing =
      _Translations$releaseNotes$about$whereGoing$de._(_root);
}

// Path: releaseNotes.legal
class _Translations$releaseNotes$legal$de
    extends Translations$releaseNotes$legal$en {
  _Translations$releaseNotes$legal$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get copyright => '© 2026 Woflo Labs';
  @override
  String get license =>
      'GPL-3.0-or-later · WLCSL Community-Source-Forschungskern · keine Gewährleistung';
}

// Path: repoSummary.backbone
class _Translations$repoSummary$backbone$de
    extends Translations$repoSummary$backbone$en {
  _Translations$repoSummary$backbone$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}` (${lines}) — ${region}';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Zeile',
        other: '${n} Zeilen',
      );
  @override
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class _Translations$repoSummary$glance$de
    extends Translations$repoSummary$glance$en {
  _Translations$repoSummary$glance$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Datei.',
        other: '${n} Dateien.',
      );
  @override
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Zeile (${bytes}).',
        other: '${n} Zeilen (${bytes}).',
      );
  @override
  String roles({required Object parts}) => 'Rollen — ${parts}.';
  @override
  String showingNofM({required Object active, required Object total}) =>
      'Zeige ${active} von ${total} Dateien, nach struktureller Zentralität sortiert.';
}

// Path: repoSummary.heading
class _Translations$repoSummary$heading$de
    extends Translations$repoSummary$heading$en {
  _Translations$repoSummary$heading$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get atAGlance => 'Auf einen Blick';
  @override
  String get core => 'Kern';
  @override
  String get gettingStarted => 'Erste Schritte';
  @override
  String get regions => 'Regionen';
  @override
  String get shape => 'Form';
}

// Path: repoSummary.pitch
class _Translations$repoSummary$pitch$de
    extends Translations$repoSummary$pitch$en {
  _Translations$repoSummary$pitch$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String empty({required Object detail}) =>
      'Ein Repository ohne lesbare Textdateien${detail}.';
  @override
  String emptyBinary({required Object n}) => '${n} binär';
  @override
  String emptyUnreadable({required Object n}) => '${n} unlesbar';
  @override
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'Ein Repository mit ${n} aktiven Datei.',
        other: 'Ein Repository mit ${n} aktiven Dateien.',
      );
  @override
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'Ein Repository mit ${n} aktiven Datei — ${regions}.',
        other: 'Ein Repository mit ${n} aktiven Dateien — ${regions}.',
      );
}

// Path: repoSummary.region
class _Translations$repoSummary$region$de
    extends Translations$repoSummary$region$en {
  _Translations$repoSummary$region$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String bodyCommonDir({required Object dir}) => 'Alles unter `${dir}`.';
  @override
  String get bodyCommonDirSeparator => ' ';
  @override
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '1 Kern',
        other: '${n} Kern',
      );
  @override
  String get bodyCoreSeparator => ', ';
  @override
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'Eine Datei',
        other: '${n} Dateien',
      );
  @override
  String connectsTo({required Object linked}) =>
      'Verbindet sich mit: ${linked}.';
  @override
  String get filesLabel => 'Dateien:';
}

// Path: repoSummary.shape
class _Translations$repoSummary$shape$de
    extends Translations$repoSummary$shape$en {
  _Translations$repoSummary$shape$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get bulk =>
      'Dicht vernetzte Codebasis: die meisten Dateien gehören zu einer großen Nachbarschaft gemeinsamer Änderungen.';
  @override
  String get crystalline =>
      'Gitterförmige Codebasis: gleichmäßige, regelmäßige Kopplung über Dateien hinweg mit vorhersehbarer lokaler Struktur.';
  @override
  String get goe =>
      'Reich vernetzte Codebasis: Kopplungen verteilen sich über Dateien ohne dominantes Rückgrat.';
  @override
  String get modular =>
      'Modulare Codebasis: mehrere zusammenhängende Regionen mit begrenzter Querkopplung. Arbeit in einer Region stört selten eine andere.';
  @override
  String get poisson =>
      'Locker gekoppelte Codebasis: Dateien entwickeln sich meist eigenständig, mit gelegentlicher gemeinsamer Änderung.';
  @override
  String get tree =>
      'Baumförmige Codebasis: ein dominantes Rückgrat mit abhängigen Zweigen. Änderungen breiten sich meist vom Kern nach außen aus.';
}

// Path: settings.language
class _Translations$settings$language$de
    extends Translations$settings$language$en {
  _Translations$settings$language$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Sprache';
  @override
  String get summary =>
      'UI-Sprache für diese App. Git-Ausgaben, Logs und Diagnostik bleiben englisch, damit Fehlerberichte durchsuchbar bleiben.';
  @override
  String get label => 'ANZEIGESPRACHE';
  @override
  String get systemDefault => 'Systemstandard';
  @override
  String systemDefaultDetail({required Object resolved}) =>
      'Folgt deiner OS-Sprache (${resolved})';
  @override
  String get disclosureSource =>
      'Ausgangssprache, von den Entwicklern geschrieben.';
  @override
  String disclosureAi({required Object model}) =>
      'Maschinell übersetzt von ${model}, noch nicht von Menschen geprüft. Korrekturen willkommen.';
  @override
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) => 'Maschinell übersetzt von ${model}. ${percent}% von Menschen geprüft.';
  @override
  String get disclosureHuman =>
      'Menschliche Übersetzung, gepflegt von der Community.';
  @override
  String reviewedBy({required Object names}) => 'Geprüft von ${names}.';
}

// Path: settings.sectionLabels
class _Translations$settings$sectionLabels$de
    extends Translations$settings$sectionLabels$en {
  _Translations$settings$sectionLabels$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get preferences => 'Einstellungen';
  @override
  String get shortcuts => 'Tastenkürzel';
  @override
  String get behaviour => 'Verhalten';
  @override
  String get aiProviders => 'AI-Anbieter';
  @override
  String get modelSlots => 'Modell-Slots';
  @override
  String get tools => 'Tools';
  @override
  String get diagnostics => 'Diagnostik';
  @override
  String get offenders => 'Übeltäter';
  @override
  String get release => 'Release';
}

// Path: settings.errors
class _Translations$settings$errors$de extends Translations$settings$errors$en {
  _Translations$settings$errors$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get saveGuardrailProfile =>
      'Guardrail-Profil konnte nicht gespeichert werden.';
  @override
  String get saveRetentionPolicy =>
      'Aufbewahrungsrichtlinie konnte nicht gespeichert werden.';
  @override
  String get saveUpdateChannel =>
      'Update-Kanal konnte nicht gespeichert werden.';
  @override
  String get saveModelSelection =>
      'AI-Modellauswahl konnte nicht gespeichert werden.';
  @override
  String get saveModelAlias => 'Modell-Alias konnte nicht gespeichert werden.';
  @override
  String get saveCommitMessageModelSlot =>
      'Commit-Nachricht-Modell-Slot konnte nicht gespeichert werden.';
  @override
  String get saveReviewModelSlot =>
      'Review-Modell-Slot konnte nicht gespeichert werden.';
  @override
  String get saveCommitMessageCustomPrompt =>
      'Eigener Commit-Nachricht-Prompt konnte nicht gespeichert werden.';
  @override
  String get saveReviewGuide =>
      'Review-Leitfaden konnte nicht gespeichert werden.';
  @override
  String get saveMuseNotes => 'Muse-Notizen konnten nicht gespeichert werden.';
  @override
  String get saveReviewDoubleCheck =>
      'Review-Doppelprüfungsmodus konnte nicht gespeichert werden.';
  @override
  String get saveApiPiggybackCli =>
      'API-Piggyback-CLI konnte nicht gespeichert werden.';
  @override
  String get saveCliTimeout => 'CLI-Timeout konnte nicht gespeichert werden.';
  @override
  String get stopAllCli =>
      'Die laufenden CLI-Sitzungen konnten nicht gestoppt werden.';
  @override
  String clearLocalData({required Object error}) =>
      'Lokale Daten konnten nicht gelöscht werden: ${error}';
}

// Path: settings.promptStatus
class _Translations$settings$promptStatus$de
    extends Translations$settings$promptStatus$en {
  _Translations$settings$promptStatus$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get editing => 'Bearbeite';
  @override
  String get saving => 'Speichere';
  @override
  String get saveFailed => 'Speichern fehlgeschlagen';
}

// Path: settings.clearData
class _Translations$settings$clearData$de
    extends Translations$settings$clearData$en {
  _Translations$settings$clearData$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => 'Lokale Daten löschen';
  @override
  String get clear => 'Löschen';
  @override
  String get confirmDiagnostics =>
      'Lokale Diagnostik-Samples und Performance-Timings löschen?';
  @override
  String get confirmAudit => 'Lokale AI-Audit-Metadaten löschen?';
  @override
  String get confirmAll =>
      'Alle lokalen Diagnostik-Samples und AI-Audit-Metadaten löschen?';
  @override
  String get confirmWipeAll =>
      'Alle lokalen App-Daten — inklusive der Liste der zuletzt genutzten Repos — löschen und beenden? Deine tatsächlichen Git-Repos auf der Platte bleiben unangetastet.';
  @override
  String get confirmReset =>
      'Lokale App-Daten zurücksetzen und beenden?\n\nEinstellungen, Theme, Onboarding, AI-Präferenzen, Telemetrie und Engram-Caches werden gelöscht. Deine Liste der zuletzt genutzten Repos bleibt erhalten.';
}

// Path: settings.guardrailMacro
class _Translations$settings$guardrailMacro$de
    extends Translations$settings$guardrailMacro$en {
  _Translations$settings$guardrailMacro$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'locker';
  @override
  String get balanced => 'ausgewogen';
  @override
  String get strict => 'streng';
  @override
  String get paranoid => 'paranoid';
}

// Path: settings.guardrails
class _Translations$settings$guardrails$de
    extends Translations$settings$guardrails$en {
  _Translations$settings$guardrails$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Guardrails';
  @override
  String get summary =>
      'Wie aufmerksam die Automatisierung im gesamten Erlebnis ist.';
}

// Path: settings.appearance
class _Translations$settings$appearance$de
    extends Translations$settings$appearance$en {
  _Translations$settings$appearance$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Erscheinungsbild';
  @override
  String get summary => 'Globale Stimmung und Atmosphäre der Oberfläche.';
}

// Path: settings.retention
class _Translations$settings$retention$de
    extends Translations$settings$retention$en {
  _Translations$settings$retention$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Lokale Datenaufbewahrung';
  @override
  String get summaryDiagnostics => 'Aufbewahrungsrichtlinie für Diagnostik.';
  @override
  String get summaryWithAudit =>
      'Aufbewahrungsrichtlinie für Diagnostik und AI-Audit.';
  @override
  String get unitDays => 'Tage';
  @override
  String get unitMb => 'MB';
  @override
  String get includesNote =>
      'Umfasst Diagnostik, Performance-Timings und Metadaten.';
}

// Path: settings.navigation
class _Translations$settings$navigation$de
    extends Translations$settings$navigation$en {
  _Translations$settings$navigation$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Navigation und Dynamik';
  @override
  String get summaryShortcuts => 'Tastenkürzel und Verhalten der Oberfläche.';
  @override
  String get summaryWithAi =>
      'Tastenkürzel, Verhalten der Oberfläche und AI-Routing.';
}

// Path: settings.behaviour
class _Translations$settings$behaviour$de
    extends Translations$settings$behaviour$en {
  _Translations$settings$behaviour$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Verhaltensdynamik';
}

// Path: settings.retentionClear
class _Translations$settings$retentionClear$de
    extends Translations$settings$retentionClear$en {
  _Translations$settings$retentionClear$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get diag => 'Diag';
  @override
  String get audit => 'Audit';
  @override
  String get all => 'Alle';
  @override
  String get clearsHint => '<-- löscht';
}

// Path: settings.channels
class _Translations$settings$channels$de
    extends Translations$settings$channels$en {
  _Translations$settings$channels$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get stable => 'STABLE';
  @override
  String get beta => 'BETA';
  @override
  String get dev => 'DEV';
}

// Path: settings.pollResult
class _Translations$settings$pollResult$de
    extends Translations$settings$pollResult$en {
  _Translations$settings$pollResult$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get upToDate => 'aktuell';
  @override
  String updateAvailable({required Object version}) => '${version} verfügbar';
  @override
  String get notConfigured => 'kein Update-Server';
  @override
  String notFound({required Object channel}) => 'keine ${channel}-Releases';
  @override
  String get unreachable => 'nicht erreichbar';
  @override
  String get badManifest => 'ungültiges Manifest';
}

// Path: settings.keybindingProfile
class _Translations$settings$keybindingProfile$de
    extends Translations$settings$keybindingProfile$en {
  _Translations$settings$keybindingProfile$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Tastenkürzel-Profil';
  @override
  String get porcelain => 'Porcelain';
  @override
  String get numeric => 'Numerisch';
  @override
  String get porcelainDescription => 'Akkord-Shortcuts (G, dann C, H, B…).';
  @override
  String get numericDescription =>
      'Numerische Einzeltasten-Shortcuts (1, 2, 3…).';
}

// Path: settings.apiKeys
class _Translations$settings$apiKeys$de
    extends Translations$settings$apiKeys$en {
  _Translations$settings$apiKeys$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

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
  String get show => 'Zeigen';
}

// Path: settings.shortcuts
class _Translations$settings$shortcuts$de
    extends Translations$settings$shortcuts$en {
  _Translations$settings$shortcuts$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get navigate => 'navigieren';
  @override
  String get staging => 'staging';
  @override
  String get branchesPrs => 'branches & PRs';
  @override
  String get modifiers => 'modifikatoren';
  @override
  String get changes => 'Änderungen';
  @override
  String get history => 'Verlauf';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Wechseln (immer)';
  @override
  String get search => 'Suchen';
  @override
  String get dismiss => 'Verwerfen';
  @override
  String get refresh => 'Aktualisieren';
  @override
  String get shortcuts => 'Tastenkürzel';
  @override
  String get nextChange => 'Nächste Änderung';
  @override
  String get prevChange => 'Vorige Änderung';
  @override
  String get toggleLine => 'Zeile umschalten';
  @override
  String get toggleHunk => 'Hunk umschalten';
  @override
  String get toggleFile => 'Datei umschalten';
  @override
  String get pinContext => 'Kontext anheften';
  @override
  String get commit => 'Commit';
  @override
  String get acceptHint => 'Hinweis annehmen';
  @override
  String get undo => 'Rückgängig';
  @override
  String get navigateRow => 'Navigieren';
  @override
  String get expand => 'Ausklappen';
  @override
  String get checkout => 'Checkout';
  @override
  String get approve => 'Freigeben';
  @override
  String get requestChanges => 'Änderungen anfordern';
  @override
  String get selectRange => 'Bereich auswählen';
  @override
  String get extendedMenu => 'Erweitertes Menü';
}

// Path: settings.toggles
class _Translations$settings$toggles$de
    extends Translations$settings$toggles$en {
  _Translations$settings$toggles$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get aiReadOnlyLabel => 'AI-Nur-Lese-Modus';
  @override
  String get aiReadOnlyDescription =>
      'Verhindert, dass AI automatisch Änderungen schreibt oder staged.';
  @override
  String get logoMotionLabel => 'Logo animiert, wenn weggetabbt';
  @override
  String get logoMotionDescriptionEnabled =>
      'Es ist auf Effizienz ausgelegt, verletze nicht seine Gefühle';
  @override
  String get logoMotionDescriptionDisabled => ':(';
  @override
  String get rememberWipLabel => 'Work in Progress merken';
  @override
  String get rememberWipDescription =>
      'Behalte deine Commit-Entwürfe und Dateiauswahl zwischen Sitzungen.';
  @override
  String get stashCabinetLabel => 'Stash-Schrank startet ausgeklappt';
  @override
  String get stashCabinetDescription =>
      'Zeige die Aktenschrank-Schublade standardmäßig offen, wenn ein Repo Ablagen hat.';
  @override
  String get instantBlameLabel => 'Sofort-Blame beim Hovern';
  @override
  String get instantBlameDescription =>
      'Überspringe die 180-ms-Verzögerung, bevor Blame-Infos auf einer Diff-Zeile erscheinen.';
  @override
  String get autoSelectLabel => 'Neue Änderungen auto-auswählen';
  @override
  String get autoSelectDescription =>
      'Neu getrackte oder geänderte Dateien werden automatisch zur Commit-Auswahl hinzugefügt.';
  @override
  String get fetchIssuesLabel => 'Online-Issues beim Branch-Laden abrufen';
  @override
  String get fetchIssuesDescription =>
      'Hole PR- und Issue-Details im Hintergrund von deinem Git-Anbieter, wenn die Branches-Seite öffnet.';
  @override
  String get hateAiLabel => 'Ich hasse AI';
  @override
  String get hateAiDescription =>
      'Verbanne alle LLM-gestützten Funktionen. Logos läuft weiter, weil es nur Spektralmathematik ist.';
}

// Path: settings.diffDiffability
class _Translations$settings$diffDiffability$de
    extends Translations$settings$diffDiffability$en {
  _Translations$settings$diffDiffability$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'diff-diffbarkeit';
}

// Path: settings.modelSlots
class _Translations$settings$modelSlots$de
    extends Translations$settings$modelSlots$en {
  _Translations$settings$modelSlots$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get loadingProviders => 'Lade Anbieter...';
  @override
  String get refreshingProviders => 'Aktualisiere Anbieter-Diagnostik...';
  @override
  String get routeDescription =>
      'Benenne Konfigurationen um und route sie zu jedem erkannten Anbieter-Modell.';
  @override
  String get loadingCategories => 'Lade Modell-Kategorien...';
  @override
  String get noOptions =>
      'Noch keine Modell-Optionen verfügbar. Erkenne zuerst eine kompatible lokale AI-CLI.';
  @override
  String get slotsAppearWhenAvailable =>
      'Modell-Slot-Einstellungen erscheinen hier, sobald Anbieter-Modelle verfügbar sind.';
  @override
  String get effortDefault => 'standard';
  @override
  String get noModelsForSlot => 'Keine Modelle für diesen Slot erkannt.';
  @override
  String viaProvider({required Object provider}) => 'über ${provider}';
  @override
  String get customModelId => 'eigene modell-id';
}

// Path: settings.modelPicker
class _Translations$settings$modelPicker$de
    extends Translations$settings$modelPicker$en {
  _Translations$settings$modelPicker$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String noMatch({required Object query}) =>
      'keine Modelle passen zu "${query}"';
  @override
  String get noModels => 'keine Modelle verfügbar';
  @override
  String get filterHint => 'modelle filtern...';
  @override
  String get warming => 'wärmt auf…';
  @override
  String get detailsUnavailable => 'details nicht verfügbar';
  @override
  String get free => 'gratis';
}

// Path: settings.aiFeatures
class _Translations$settings$aiFeatures$de
    extends Translations$settings$aiFeatures$en {
  _Translations$settings$aiFeatures$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get commitDescription =>
      'Entwirf Commit-Nachrichten aus gestagten Änderungen nach deinen Struktur-, Stimm- und Abdeckungspräferenzen.';
  @override
  String get reviewDescription =>
      'Prüfe den aktuellen Commit-Umfang, bevor du committest.';
  @override
  String get museDescription =>
      'Dreiphasiges Orakel, das brainstormt und dann eine Vorwärtsrichtung für den Diff synthetisiert.';
}

// Path: settings.commitEditor
class _Translations$settings$commitEditor$de
    extends Translations$settings$commitEditor$en {
  _Translations$settings$commitEditor$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get styleGuide => 'Stil-Leitfaden';
  @override
  String get styleGuideHint =>
      'Optional. Stimme / Ton / Verbote. Das Format oben regelt das Grundgerüst.';
}

// Path: settings.review
class _Translations$settings$review$de extends Translations$settings$review$en {
  _Translations$settings$review$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Zusätzliche Notizen zum Mitprüfen';
  @override
  String get doubleCheckLabel => 'Review doppelt prüfen';
  @override
  String get doubleCheckDescription =>
      'Führe einen zweiten Verifikationsdurchlauf aus, bevor der finale Bericht gezeigt wird.';
}

// Path: settings.museHint
class _Translations$settings$museHint$de
    extends Translations$settings$museHint$en {
  _Translations$settings$museHint$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get loose =>
      'irgendwas, wohin man sanft lenken sollte? die Stimmung ist heute gnädig.';
  @override
  String get balanced =>
      'worauf verweilen, was auslassen. ehrlich, nicht hart.';
  @override
  String get strict =>
      'die Standards. die Verbote. was die Muse nicht durchgehen lässt.';
  @override
  String get paranoid =>
      'justiere die Linse. auf welchen Frequenzen soll die manifold summen?';
}

// Path: settings.museEditor
class _Translations$settings$museEditor$de
    extends Translations$settings$museEditor$en {
  _Translations$settings$museEditor$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Zusätzliche Notizen für die Muse';
}

// Path: settings.museStage
class _Translations$settings$museStage$de
    extends Translations$settings$museStage$en {
  _Translations$settings$museStage$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get brainstorm => 'BRAINSTORM';
  @override
  String get synthesize => 'SYNTHESE';
  @override
  String get slot => 'slot';
  @override
  String get ideaCountLoose => '~12 Ideen';
  @override
  String get ideaCountBalanced => '~16 Ideen';
  @override
  String get ideaCountStrict => '~20 Ideen';
  @override
  String get ideaCountParanoid => '~24 Ideen';
  @override
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  guardrail: ${macro}';
}

// Path: settings.lensAxis
class _Translations$settings$lensAxis$de
    extends Translations$settings$lensAxis$en {
  _Translations$settings$lensAxis$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get folder => 'ORDNER';
  @override
  String get history => 'HISTORIE';
  @override
  String get far => 'FERN';
  @override
  String get near => 'NAH';
}

// Path: settings.logosLens
class _Translations$settings$logosLens$de
    extends Translations$settings$logosLens$en {
  _Translations$settings$logosLens$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get moduleMap => 'modul-karte';
  @override
  String get repoCenters => 'repo-zentren';
  @override
  String get neighbors => 'nachbarn';
  @override
  String get toTouch => 'was als nächstes anfassen';
  @override
  String get relevanceEngine => 'relevanz-engine';
  @override
  String get description =>
      'liest, wie sich Dateien über Struktur, Historie und Rhythmus zusammen bewegen, damit Manifold weiß, was zählt, nicht nur was sich geändert hat.';
  @override
  String get withinReach => 'in reichweite';
  @override
  String get gate => 'tor';
  @override
  String get nearest => 'nächste';
  @override
  String get warming => 'wärmt auf';
  @override
  String get emptyOpenRepo => 'öffne ein repo, um\ndie linse live zu sehen';
  @override
  String get emptyNoFiles =>
      'keine dateien in\nreichweite — ziehe\nrichtung HISTORIE';
}

// Path: settings.sortGuide
class _Translations$settings$sortGuide$de
    extends Translations$settings$sortGuide$en {
  _Translations$settings$sortGuide$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Änderungs-Sortierleitfaden';
  @override
  String get related =>
      'Dateien, die sich zusammen ändern, gruppieren sich zusammen. Das Anliegen zuerst; der Kontext folgt.';
  @override
  String get relatedInverted =>
      'Isolierte Änderungen zuerst. Eng gekoppelte Cluster sinken nach unten.';
  @override
  String get alphabetical =>
      'Schlicht A → Z nach Pfad. Groß-/Kleinschreibung egal, Zahlen natürlich sortiert.';
  @override
  String get alphabeticalInverted =>
      'Schlicht Z → A nach Pfad. Groß-/Kleinschreibung egal, Zahlen natürlich sortiert.';
  @override
  String get impact =>
      'Schwerste Änderungen zuerst. Churn wird gewichtet; Binärdateien und neue Dateien werden hochgestuft.';
  @override
  String get impactInverted =>
      'Leichteste Änderungen zuerst. Schnelle Erfolge oben; die schweren Brocken warten.';
  @override
  String get nearRelated => 'nah verwandt';
  @override
  String get alphabeticalShort => 'alphabetisch';
  @override
  String get byImpact => 'nach Impact';
  @override
  String get flipped => 'umgekehrt';
  @override
  String get peek => 'spähen';
}

// Path: settings.piggyback
class _Translations$settings$piggyback$de
    extends Translations$settings$piggyback$en {
  _Translations$settings$piggyback$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get apiModelsUse => 'API-Modelle nutzen';
  @override
  String get codexNotDetected => 'codex nicht erkannt';
  @override
  String get dormant => 'RUHEND';
}

// Path: settings.diffStage
class _Translations$settings$diffStage$de
    extends Translations$settings$diffStage$en {
  _Translations$settings$diffStage$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get viewer => 'viewer';
  @override
  String get media => 'medien';
  @override
  String get binary => 'binär';
  @override
  String get hidden => 'versteckt';
}

// Path: settings.undoScope
class _Translations$settings$undoScope$de
    extends Translations$settings$undoScope$en {
  _Translations$settings$undoScope$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get destructiveActions => 'destruktive Aktionen';
  @override
  String get discards => 'Verwerfungen';
  @override
  String get commits => 'Commits';
  @override
  String get commitPush => 'Commit + Push';
  @override
  String get all => 'alle';
}

// Path: settings.undoWindow
class _Translations$settings$undoWindow$de
    extends Translations$settings$undoWindow$en {
  _Translations$settings$undoWindow$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Rückgängig-Fenster';
  @override
  String get off => 'Aus';
  @override
  String descriptionInstant({required Object scope}) =>
      '${scope} werden sofort finalisiert.';
  @override
  String descriptionDelayed({required Object seconds, required Object scope}) =>
      '${seconds}s bevor ${scope} finalisiert werden.';
  @override
  String get cycleScopeTooltip =>
      'Klicken, um den Umfang durchzuschalten · auch am Slider hoch/runter ziehen';
  @override
  String get resetTooltip => 'Jede Aktion auf das Standardfenster zurücksetzen';
}

// Path: settings.guardrailPhrase
class _Translations$settings$guardrailPhrase$de
    extends Translations$settings$guardrailPhrase$en {
  _Translations$settings$guardrailPhrase$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get probablyFine => 'Wahrscheinlich okay heißt okay';
  @override
  String get proper => 'Ein gründlicher Blick: Logik, Integration, Muster';
  @override
  String get lookAgain => 'Schau nochmal. Etwas könnte sich verstecken';
  @override
  String get assumeWrong => 'Nimm an, etwas stimmt nicht. Finde es';
}

// Path: settings.reviewGuideHint
class _Translations$settings$reviewGuideHint$de
    extends Translations$settings$reviewGuideHint$en {
  _Translations$settings$reviewGuideHint$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get focusHigh =>
      'z. B. Fokus auf High-Level-Logik und große Bugs. Kurz und nachsichtig.';
  @override
  String get surfaceBugs =>
      'z. B. Bringe mögliche Bugs, architektonische Inkonsistenzen und Randfall-Fehler ans Licht.';
  @override
  String get scrutinize =>
      'z. B. Prüfe jede Zeile auf Optimierung, Sicherheit und Muster-Konformität.';
  @override
  String get trustNothing =>
      'z. B. Trau nichts. Hinterfrage jeden Seiteneffekt. Behandle jede Zeile als potenziellen Fehler.';
  @override
  String get optional => 'Optionale Vorgabe, worauf das Review achten soll.';
}

// Path: settings.commitFormat
class _Translations$settings$commitFormat$de
    extends Translations$settings$commitFormat$en {
  _Translations$settings$commitFormat$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Format';
  @override
  String get peek => 'spähen';
  @override
  String get structure => 'Struktur';
  @override
  String get voice => 'Stimme';
  @override
  String get coverage => 'Abdeckung';
  @override
  String get structureTitleBody => 'Titel + Text';
  @override
  String get structureTitleOnly => 'nur Titel';
  @override
  String get structureFreeform => 'freiform';
  @override
  String get voiceVerbLed => 'handlungsorientiert';
  @override
  String get voiceDescriptive => 'beschreibend';
  @override
  String get voiceNarrative => 'erzählend';
  @override
  String get coverageEssentials => 'das Nötigste';
  @override
  String get coverageBalanced => 'ausgewogen';
  @override
  String get coverageEverything => 'alles';
}

// Path: settings.commitPreview
class _Translations$settings$commitPreview$de
    extends Translations$settings$commitPreview$en {
  _Translations$settings$commitPreview$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$de title =
      _Translations$settings$commitPreview$title$de._(_root);
  @override
  late final _Translations$settings$commitPreview$base$de base =
      _Translations$settings$commitPreview$base$de._(_root);
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$de
  balancedSuffix = _Translations$settings$commitPreview$balancedSuffix$de._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$de
  everythingSuffix = _Translations$settings$commitPreview$everythingSuffix$de._(
    _root,
  );
}

// Path: settings.externalTools
class _Translations$settings$externalTools$de
    extends Translations$settings$externalTools$en {
  _Translations$settings$externalTools$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Externe Tools';
  @override
  String get summary =>
      'Rechtsklick auf ein Projekt in der Seitenleiste, um es mit einem davon zu öffnen. Argumente nutzen {path} für den Projektordner.';
  @override
  String get detecting => 'Erkenne installierte Tools…';
  @override
  String get allPresetsAdded =>
      'Alle bekannten Presets sind bereits hinzugefügt. Nutze „+ Eigenes“, um mehr hinzuzufügen.';
  @override
  String get noToolsConfigured =>
      'Noch keine Tools konfiguriert. Füge oben eins hinzu.';
  @override
  String get categoryAi => 'ai';
  @override
  String get categoryEditors => 'editoren';
  @override
  String get categoryExplore => 'erkunden';
  @override
  String get categoryOps => 'ops';
  @override
  String get categoryGitOps => 'git-ops';
  @override
  String get nameHint => 'Name';
  @override
  String get commandHint => 'befehl';
  @override
  String get test => 'testen';
  @override
  String get removeTool => 'Tool entfernen';
  @override
  String get modeTerminal => 'terminal';
  @override
  String get modeDetached => 'abgekoppelt';
}

// Path: settings.apiUsage
class _Translations$settings$apiUsage$de
    extends Translations$settings$apiUsage$en {
  _Translations$settings$apiUsage$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String thisMonth({required Object used, required Object limit}) =>
      '${used}${limit} diesen Monat';
}

// Path: settings.gitea
class _Translations$settings$gitea$de extends Translations$settings$gitea$en {
  _Translations$settings$gitea$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Gitea-Tokens';
  @override
  String get hostHint => 'host';
  @override
  String get tokenHint => 'token';
  @override
  String get save => 'speichern';
}

// Path: settings.wick
class _Translations$settings$wick$de extends Translations$settings$wick$en {
  _Translations$settings$wick$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get selectExecutable => 'wick-Executable auswählen';
  @override
  String get connected => 'wick · verbunden';
  @override
  String get pathToExecutable => 'wick · Pfad zur Executable';
  @override
  String get off => 'aus';
  @override
  String get disableHint => 'wick-Integration ausschalten';
  @override
  String get enableHint => 'wick-Integration einschalten';
}

// Path: settings.integrations
class _Translations$settings$integrations$de
    extends Translations$settings$integrations$en {
  _Translations$settings$integrations$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => '& Integrationen';
  @override
  String get alpha => 'alpha';
  @override
  String get planned => 'geplant';
  @override
  String get lspComingSoon => 'lsp · bald verfügbar';
  @override
  String get alphaMathConnected => 'alpha-math · verbunden';
  @override
  String get alphaMathComingSoon => 'alpha-math · bald verfügbar';
}

// Path: settings.reduceMotion
class _Translations$settings$reduceMotion$de
    extends Translations$settings$reduceMotion$en {
  _Translations$settings$reduceMotion$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Bewegung reduzieren';
  @override
  String get subtitleStill => 'Still… wie Eis?';
  @override
  String get subtitleFlow => 'Fließe wie Wasser.';
}

// Path: settings.resetQuit
class _Translations$settings$resetQuit$de
    extends Translations$settings$resetQuit$en {
  _Translations$settings$resetQuit$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get resetAndQuit => 'ZURÜCKSETZEN & BEENDEN';
  @override
  String get keepRepos => 'REPOS BEHALTEN';
  @override
  String get wipeAll => 'ALLES LÖSCHEN';
}

// Path: settings.diagnostics
class _Translations$settings$diagnostics$de
    extends Translations$settings$diagnostics$en {
  _Translations$settings$diagnostics$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get commandDiagnostics => 'Befehls-Diagnostik';
  @override
  String get networkFlowTelemetry => 'Netzwerkfluss-Telemetrie';
  @override
  String get clearSamples => 'Samples löschen';
  @override
  String get clearMetrics => 'Metriken löschen';
  @override
  String get clearTimings => 'Timings löschen';
  @override
  String get recalibrate => 'NEU KALIBRIEREN';
  @override
  String get ok => 'ok';
  @override
  String get noCommandTimings =>
      'Noch keine Befehls-Timings erfasst. Führe normale Aktionen aus, um die Diagnostik zu füllen.';
  @override
  String get noBackendSamples =>
      'Noch keine Backend-Befehls-Samples erfasst. Führe Git- und Einstellungsaktionen aus, um dieses Log zu füllen.';
  @override
  String get noDiffSessions =>
      'Noch keine Diff-Render-Sessions erfasst. Öffne und scrolle Datei-Diffs, um dieses Panel zu füllen.';
  @override
  String get noUiSessions =>
      'Noch keine UI-Timing-Sessions erfasst. Öffne Panels und navigiere Routen, um dieses Panel zu füllen.';
  @override
  String get recentOperations => 'Letzte Operationen';
  @override
  String get recentBackendOperations => 'Letzte Backend-Operationen';
  @override
  String get recentDiffSessions => 'Letzte Diff-Sessions';
  @override
  String get recentUiTimings => 'Letzte UI-Timings';
  @override
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} eindeutiger Befehl',
        other: '${n} eindeutige Befehle',
      );
  @override
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} gescopeter Befehl',
        other: '${n} gescopete Befehle',
      );
  @override
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} instrumentiertes Ereignis',
        other: '${n} instrumentierte Ereignisse',
      );
  @override
  String summaryCommand({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryBackend({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryDiff({required Object sessions, required Object jank}) =>
      '${sessions} | Ruckeln ${jank}%';
  @override
  String summaryUi({required Object samples, required Object events}) =>
      '${samples} | ${events}';
  @override
  List<String> get headersCommand => [
    'befehl',
    'p50',
    'zuverlässigkeit',
    'spanne',
  ];
  @override
  List<String> get headersBackend => ['scope', 'p50', 'p95', 'fehler'];
  @override
  List<String> get headersDiff => [
    'renderer',
    'erster paint',
    'frame p95',
    'raster p95',
    'ruckeln',
  ];
  @override
  List<String> get headersUi => ['ereignis', 'p50', 'fehler', 'spanne'];
}

// Path: settings.telemetry
class _Translations$settings$telemetry$de
    extends Translations$settings$telemetry$en {
  _Translations$settings$telemetry$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Sample',
        other: '${n} Samples',
      );
  @override
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Befehl',
        other: '${n} Befehle',
      );
  @override
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Session',
        other: '${n} Sessions',
      );
  @override
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Ereignis',
        other: '${n} Ereignisse',
      );
  @override
  String stability({required Object pct}) => '${pct}% Stabilität';
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
class _Translations$settings$flowEngine$de
    extends Translations$settings$flowEngine$en {
  _Translations$settings$flowEngine$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get executionFlow => 'ausführungsfluss';
  @override
  String get description =>
      'simuliert Oszillatoren auf Code. bringt fragile Ausführungspfade ans Licht, bevor sie als Bugs erstarren.';
  @override
  String get idle => 'ruht';
  @override
  String get emptyOpenRepo => 'öffne ein repo, um\ndie flussanalyse zu sehen';
  @override
  String get scanning => 'scanne';
  @override
  String get analysing => 'analysiere dateien\nin der linse…';
  @override
  String get fragility => 'fragilität';
  @override
  String get findings => 'funde';
  @override
  String get gap => 'lücke';
  @override
  String get clean => 'sauber';
  @override
  String get severity => 'schwere';
  @override
  String get critical => 'kritisch';
  @override
  String get warn => 'warnung';
  @override
  String get info => 'info';
}

// Path: settings.museStrands
class _Translations$settings$museStrands$de
    extends Translations$settings$museStrands$en {
  _Translations$settings$museStrands$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get spark => 'Funke der Inspiration · der unmittelbar nächste Schritt';
  @override
  String get current => 'Strömung im Wasser · Erweiterungen im Präsens';
  @override
  String get horizon => 'Blick über den Horizont · greifende Richtungen';
  @override
  String get fever => 'Erwachen aus einem Fiebertraum · Provokationen';
  @override
  String get echo => 'ein Echo über die Schlucht · Analoga anderswo';
  @override
  String get vertigo => 'Schwindel am Klippenrand · benachbarte Risiken';
  @override
  String get ghost => 'der Geist des Gewesenen · historischer Kontext';
  @override
  String get mirror => 'ein Spiegel auf stillem Wasser · Inversionen';
}

// Path: settings.cliPiggyback
class _Translations$settings$cliPiggyback$de
    extends Translations$settings$cliPiggyback$en {
  _Translations$settings$cliPiggyback$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'CLI-Piggybacking';
  @override
  String get clearCacheLabel => 'Cache löschen';
  @override
  String get clearCacheTooltip =>
      'Gecachte Modelle löschen und neu sondieren. Räumt die auf, die ein Anbieter fallengelassen hat.';
  @override
  String get refreshLabel => 'Anbieter aktualisieren';
  @override
  String get refreshTooltip => 'Jeden Anbieter jetzt neu sondieren.';
  @override
  String get body =>
      'Leite Interface-Nachrichten direkt an lokale Anbieter-Binaries weiter.';
  @override
  String get cliTimeoutLabel => 'Timeout pro Lauf';
  @override
  String get cliTimeoutUnitMinutes => 'Minuten';
  @override
  String get cliTimeoutUnitMinute => 'Minute';
  @override
  String get forceStopLabel => 'Alle Sitzungen stoppen';
  @override
  String get forceStopTooltip => 'Jeden laufenden CLI-Lauf hart beenden.';
  @override
  String get forceStopConfirmTitle => 'Laufende CLI-Sitzungen stoppen?';
  @override
  String forceStopConfirmBody({required Object count}) =>
      'Damit werden ${count} laufende CLI-Läufe hart beendet. Ihre Ausgabe geht verloren.';
  @override
  String get forceStopConfirmAction => 'Alle stoppen';
  @override
  String get forceStopNoneRunning => 'Keine CLI-Sitzungen aktiv';
  @override
  String get forceStopRecordError =>
      'Gestoppt — CLI-Sitzungen wurden hart beendet.';
}

// Path: settings.header
class _Translations$settings$header$de extends Translations$settings$header$en {
  _Translations$settings$header$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Workspace-Einstellungen';
  @override
  String get subtitle =>
      'Konfiguriere globale Ästhetik, Interface-Dynamik und zentrale Betriebssicherungen für den gesamten Workspace.';
  @override
  String get releaseNotesTooltip => 'Release Notes';
  @override
  String get replayOnboardingTooltip => 'Onboarding erneut abspielen';
}

// Path: settings.diagnosticsPanel
class _Translations$settings$diagnosticsPanel$de
    extends Translations$settings$diagnosticsPanel$en {
  _Translations$settings$diagnosticsPanel$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Performance-Diagnostik';
  @override
  String get copyTrace => 'Trace kopieren';
  @override
  String get offenderRanking => 'Übeltäter-Rangliste';
  @override
  String get offenderRankingSubtitle =>
      'Latenztreiber über die Streams hinweg.';
  @override
  String get noOffenders =>
      'Noch keine Übeltäter-Rangliste. Erfasse Diagnostik-Aktivität, um diese Liste zu füllen.';
}

// Path: settings.release
class _Translations$settings$release$de
    extends Translations$settings$release$en {
  _Translations$settings$release$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Release-Deployment';
  @override
  String get summary => 'Update-bezogene Einstellungen.';
  @override
  String get deploymentChannel => 'DEPLOYMENT-KANAL';
  @override
  String get captureCrashDiagnostics => 'Absturz-Diagnostik erfassen';
  @override
  String get comingSoon => 'Bald verfügbar.';
  @override
  String get checking => 'PRÜFE…';
  @override
  String get pollForUpdates => 'AUF UPDATES PRÜFEN';
}

// Path: settings.providerStatus
class _Translations$settings$providerStatus$de
    extends Translations$settings$providerStatus$en {
  _Translations$settings$providerStatus$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get detecting => 'Erkenne...';
  @override
  String get ready => 'Bereit';
  @override
  String get notDetected => 'Nicht erkannt';
  @override
  String configured({required Object count}) => '${count} konfiguriert';
  @override
  String get notConfigured => 'Nicht konfiguriert';
  @override
  String get cliManaged => 'CLI-verwaltet';
  @override
  String get connected => 'Verbunden';
  @override
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Modell',
        other: '${n} Modelle',
      );
  @override
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Anbieter',
        other: '${n} Anbieter',
      );
}

// Path: settings.meridiem
class _Translations$settings$meridiem$de
    extends Translations$settings$meridiem$en {
  _Translations$settings$meridiem$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get am => 'AM';
  @override
  String get pm => 'PM';
}

// Path: settings.offenders
class _Translations$settings$offenders$de
    extends Translations$settings$offenders$en {
  _Translations$settings$offenders$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get commandStream => 'Befehl';
  @override
  String get diffStream => 'Diff-Render';
  @override
  String get uiStream => 'UI-Timing';
  @override
  String rendererName({required Object mode}) => '${mode}-Renderer';
  @override
  String latencyFailMetric({required Object p95, required Object fail}) =>
      '${p95}ms p95 | ${fail}% Fehler';
  @override
  String jankFrameMetric({required Object jank, required Object frame}) =>
      '${jank}% Ruckeln | ${frame}ms Frame p95';
  @override
  String inStream({required Object stream}) => 'in ${stream}';
}

// Path: sync.actions
class _Translations$sync$actions$de extends Translations$sync$actions$en {
  _Translations$sync$actions$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get syncLabel => 'Sync';
  @override
  String get syncOpenRepoDetail =>
      'Öffne ein Repository, um Push- und Pull-Vorgänge zu verwalten.';
  @override
  String get detachedHeadLabel => 'Detached HEAD';
  @override
  String get detachedHeadDetail =>
      'Checke einen Branch aus, bevor du pushst oder pullst.';
  @override
  String get publishBranchLabel => 'Branch veröffentlichen';
  @override
  String publishBranchDetail({required Object branch}) =>
      'Pushe ${branch} und setze seinen Upstream-Tracking-Branch.';
  @override
  String get publishButtonLabel => 'Veröffentlichen';
  @override
  String get syncBranchLabel => 'Branch synchronisieren';
  @override
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => 'Pulle ${behindCount} mit Rebase, dann pushe ${aheadCount}.';
  @override
  String get syncBranchButtonLabel => 'Pullen (Rebase), dann pushen';
  @override
  String get pushBranchLabel => 'Branch pushen';
  @override
  String pushBranchDetail({required Object count, required Object upstream}) =>
      'Pushe ${count} nach ${upstream}.';
  @override
  String get pushBranchButtonLabel => 'Commits pushen';
  @override
  String get pullUpdatesLabel => 'Updates pullen';
  @override
  String pullUpdatesDetail({required Object count, required Object upstream}) =>
      'Pulle ${count} von ${upstream}.';
  @override
  String syncUpToDateDetail({required Object upstream}) =>
      'Fetche von ${upstream} und aktualisiere den Upstream-Status.';
}

// Path: sync.panel
class _Translations$sync$panel$de extends Translations$sync$panel$en {
  _Translations$sync$panel$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Lade Remote-Status';
  @override
  String get loadingMessage => 'Prüfe Branch-Tracking-Informationen.';
  @override
  String get remoteStatusUnavailable => 'Remote-Status nicht verfügbar';
  @override
  String get noUpstream => 'kein Upstream';
  @override
  String get aheadLabel => 'Voraus';
  @override
  String get behindLabel => 'Zurück';
  @override
  String get treeLabel => 'Baum';
  @override
  String get runningSync => 'Sync läuft…';
  @override
  String get fetching => 'Fetcht…';
  @override
  String get fetchOnly => 'Nur fetchen';
  @override
  String get syncFailed => 'Sync fehlgeschlagen';
  @override
  String get forcePushRecoveryLabel => 'Force-Push (mit Lease)';
  @override
  String get conflictsToResolveTitle => 'Zu lösende Konflikte';
  @override
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} müssen gelöst werden: ${list}';
  @override
  String get resolveConflicts => 'Konflikte lösen';
  @override
  String get workingEllipsis => 'Arbeite…';
  @override
  String lastActivity({required Object operation}) =>
      'Letzte Aktivität: ${operation}';
  @override
  String get noOutput => 'Keine Ausgabe.';
  @override
  String resolvedConflicts({required Object count}) => '${count} gelöst.';
  @override
  String get cancelledUnchanged =>
      'Abgebrochen, Arbeitsverzeichnis unverändert.';
  @override
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) =>
      '${count} haben uncommittete Änderungen, committe sie zuerst für den Rebase-Sync (${list}).';
  @override
  String noUpstreamForForcePush({required Object branch}) =>
      'Force-Push nicht möglich: für "${branch}" ist kein Upstream konfiguriert.';
}

// Path: sync.forcePush
class _Translations$sync$forcePush$de extends Translations$sync$forcePush$en {
  _Translations$sync$forcePush$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get confirmTitle => 'Force-Push (mit Lease)?';
  @override
  String target({required Object remote, required Object branch}) =>
      'Ziel: ${remote}/${branch}';
  @override
  String get warning =>
      'Das überschreibt den Remote-Branch mit deiner lokalen Historie. Mit Lease bricht es ab, falls jemand nach deinem letzten Fetch zum Remote gepusht hat, aber bereits gefetchte Änderungen werden trotzdem überschrieben. Nutze es nur, wenn du einen Rebase oder Amend beabsichtigt hast, der den Branch divergieren ließ.';
  @override
  String get confirmButton => 'Force-Push';
}

// Path: xray.board
class _Translations$xray$board$de extends Translations$xray$board$en {
  _Translations$xray$board$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get movesWithModule => 'bewegt sich mit einem anderen Modul';
  @override
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Reviewer',
        other: '${n} Reviewer',
      );
  @override
  String get territory => 'Territorium';
  @override
  String get unreviewed => 'ungeprüft';
}

// Path: xray.cadence
class _Translations$xray$cadence$de extends Translations$xray$cadence$en {
  _Translations$xray$cadence$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '${sum} Commits · ${days} Tage\n${lines}';
  @override
  String burstTooltipSingle({required Object n, required Object label}) =>
      '${n} Commits am ${label}';
  @override
  String gapTooltip({required Object n, required Object label}) =>
      '${n}-Tage-Lücke · ${label}';
  @override
  String reflogTooltip({required Object n, required Object label}) =>
      '${n} Reflog-Ereignisse am ${label}';
}

// Path: xray.cards
class _Translations$xray$cards$de extends Translations$xray$cards$en {
  _Translations$xray$cards$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$cards$branchModel$de branchModel =
      _Translations$xray$cards$branchModel$de._(_root);
  @override
  late final _Translations$xray$cards$bursty$de bursty =
      _Translations$xray$cards$bursty$de._(_root);
  @override
  late final _Translations$xray$cards$hiddenRefs$de hiddenRefs =
      _Translations$xray$cards$hiddenRefs$de._(_root);
  @override
  late final _Translations$xray$cards$keystone$de keystone =
      _Translations$xray$cards$keystone$de._(_root);
  @override
  late final _Translations$xray$cards$machineHistory$de machineHistory =
      _Translations$xray$cards$machineHistory$de._(_root);
  @override
  late final _Translations$xray$cards$migration$de migration =
      _Translations$xray$cards$migration$de._(_root);
  @override
  late final _Translations$xray$cards$narrowHotspot$de narrowHotspot =
      _Translations$xray$cards$narrowHotspot$de._(_root);
  @override
  late final _Translations$xray$cards$noTags$de noTags =
      _Translations$xray$cards$noTags$de._(_root);
  @override
  late final _Translations$xray$cards$reflog$de reflog =
      _Translations$xray$cards$reflog$de._(_root);
  @override
  late final _Translations$xray$cards$singleOwner$de singleOwner =
      _Translations$xray$cards$singleOwner$de._(_root);
}

// Path: xray.cardTitle
class _Translations$xray$cardTitle$de extends Translations$xray$cardTitle$en {
  _Translations$xray$cardTitle$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get branches => 'branches';
  @override
  String get bursty => 'schubartig';
  @override
  String get hiddenRefs => 'versteckte refs';
  @override
  String get machineHeavy => 'maschinen-lastig';
  @override
  String get migration => 'migration';
  @override
  String get narrowHotspot => 'schmaler hotspot';
  @override
  String get noTags => 'keine tags';
  @override
  String get reflog => 'reflog';
  @override
  String get singleOwner => 'ein-eigentümer';
}

// Path: xray.grain
class _Translations$xray$grain$de extends Translations$xray$grain$en {
  _Translations$xray$grain$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get coarsest => 'gröbste — oberste Module';
  @override
  String get finest => 'feinste Körnung';
  @override
  String get mid => 'mittlere Körnung';
  @override
  String get oneCharacteristic => 'eine charakteristische Skala';
}

// Path: xray.header
class _Translations$xray$header$de extends Translations$xray$header$en {
  _Translations$xray$header$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get dirtyBadge => 'unsauber';
  @override
  String get machineChip => 'maschine';
  @override
  String get refresh => 'Aktualisieren';
  @override
  String get refreshing => 'Aktualisiere...';
  @override
  String get title => 'Repo X-Ray';
}

// Path: xray.hotspot
class _Translations$xray$hotspot$de extends Translations$xray$hotspot$en {
  _Translations$xray$hotspot$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get clusterPeers => 'cluster-nachbarn';
  @override
  String get coChangers => 'co-changer';
  @override
  String get keystone => 'schlussstein';
  @override
  String keystoneScore({required Object score}) => 'schlussstein  φ=${score}';
}

// Path: xray.inspector
class _Translations$xray$inspector$de extends Translations$xray$inspector$en {
  _Translations$xray$inspector$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get branchLabel => 'branch';
  @override
  String commitsHumanMachine({required Object n}) => 'mensch · ${n} maschine';
  @override
  String get commitsLabel => 'commits';
  @override
  String get confidenceLabel => 'konfidenz';
  @override
  String get curlLabel => 'curl';
  @override
  String get engineSection => 'engine';
  @override
  String get gradientLabel => 'gradient';
  @override
  String get harmonicLabel => 'harmonisch';
  @override
  String get headLabel => 'head';
  @override
  String get hiddenRefsLabel => 'versteckte refs';
  @override
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} merge',
        other: '${n} merges',
      );
  @override
  String get noTags => 'keine tags';
  @override
  String get notesLabel => 'notes';
  @override
  String get openCommit => 'Commit öffnen';
  @override
  String get pathLabel => 'pfad';
  @override
  String remoteCount({required Object n}) => '${n} remote';
  @override
  String get renamesLabel => 'umbenennungen';
  @override
  String scannedAt({required Object time}) => 'gescannt ${time}';
  @override
  String selectedCount({required Object n}) => '${n} ausgewählt';
  @override
  String get shapeLinear => 'linear';
  @override
  String get shapeMergeHeavy => 'merge-lastig';
  @override
  String get shapeMostlyLinear => 'meist linear';
  @override
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} stash',
        other: '${n} stashes',
      );
  @override
  String get stressLabel => 'stress';
  @override
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} tag',
        other: '${n} tags',
      );
  @override
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} worktree',
        other: '${n} worktrees',
      );
}

// Path: xray.loadingCard
class _Translations$xray$loadingCard$de
    extends Translations$xray$loadingCard$en {
  _Translations$xray$loadingCard$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get buildingMessage =>
      'Sondiere Git-Historie, Refs, Kadenz und Hotspots.';
  @override
  String get buildingTitle => 'Baue Repo X-Ray';
  @override
  String get idleMessage =>
      'Öffne das Panel erneut, um das aktuelle Repository zu sondieren.';
  @override
  String get idleTitle => 'Repo X-Ray';
  @override
  String get unavailableTitle => 'Repo X-Ray nicht verfügbar';
}

// Path: xray.metabolism
class _Translations$xray$metabolism$de extends Translations$xray$metabolism$en {
  _Translations$xray$metabolism$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String halfLife({required Object n}) => '${n}T Halbwertszeit';
}

// Path: xray.multi
class _Translations$xray$multi$de extends Translations$xray$multi$en {
  _Translations$xray$multi$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Cluster',
        other: '${n} Cluster',
      );
  @override
  String clusterSingle({required Object id}) => 'Cluster ${id}';
  @override
  String couplingSuffix({required Object parts}) => '${parts} Kopplung';
  @override
  String externalCount({required Object n}) => '${n} extern';
  @override
  String mutualCount({required Object n}) => '${n} gegenseitig';
}

// Path: xray.recency
class _Translations$xray$recency$de extends Translations$xray$recency$en {
  _Translations$xray$recency$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String days({required Object n}) => '${n}T';
  @override
  String months({required Object n}) => '${n}Mon';
  @override
  String get today => 'heute';
  @override
  String weeks({required Object n}) => '${n}Wo';
  @override
  String years({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n}J',
        other: '${n}J',
      );
}

// Path: xray.rings
class _Translations$xray$rings$de extends Translations$xray$rings$en {
  _Translations$xray$rings$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get hintOneBlended => 'eine verschmolzene Struktur';
  @override
  String get hintSelfSimilar => 'selbstähnlich';
  @override
  String get oneBlendedBody =>
      'Eine verschmolzene Struktur — noch keine trennbaren Modul-Skalen auflösbar.';
  @override
  String get overHistory => 'Über die Historie';
  @override
  String get parts => 'Teile';
  @override
  String get readingHint => 'lese Struktur…';
  @override
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Skala',
        other: '${n} Skalen',
      );
  @override
  String get scaleDissolved => 'eine strukturelle Skala löste sich auf';
  @override
  String get scaleEmerged => 'eine strukturelle Skala entstand';
  @override
  String get scaleSpectrum => 'Skalenspektrum';
  @override
  String get selfSimilarBody =>
      'Selbstähnlich — Struktur wiederholt sich über Skalen hinweg, ohne eine einzelne charakteristische Ebene.';
  @override
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Verschiebung in der Historie',
        other: '${n} Verschiebungen in der Historie',
      );
  @override
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} strukturelle Verschiebung',
        other: '${n} strukturelle Verschiebungen',
      );
  @override
  String get title => 'Wachstumsringe';
  @override
  String get unavailable => 'nicht verfügbar';
}

// Path: xray.stats
class _Translations$xray$stats$de extends Translations$xray$stats$en {
  _Translations$xray$stats$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get alive => 'lebendig';
  @override
  String get files => 'dateien';
  @override
  String get lastTouched => 'zuletzt berührt';
  @override
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'eigentümer',
        other: 'eigentümer',
      );
  @override
  String get touches => 'berührungen';
}

// Path: xray.stratumLabel
class _Translations$xray$stratumLabel$de
    extends Translations$xray$stratumLabel$en {
  _Translations$xray$stratumLabel$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'aktuell';
  @override
  String get legacy => 'altlast';
  @override
  String get zone => 'repo-zone';
}

// Path: xray.summary
class _Translations$xray$summary$de extends Translations$xray$summary$en {
  _Translations$xray$summary$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String analysisFailed({required Object error}) =>
      'Analyse fehlgeschlagen: ${error}';
  @override
  String get analyze => 'Analysieren';
  @override
  String get copied => 'Zusammenfassung in die Zwischenablage kopiert.';
  @override
  String get directionHint => 'richtung';
  @override
  String get download => 'Herunterladen';
  @override
  String get emptyState =>
      'Starte die Logos-Analyse, um Struktur und Regionen dieses Repositorys zu kartieren.\n(tw: grad ziemlich schlonzig)';
  @override
  String get exit => 'Beenden';
  @override
  String get generating => 'Lese das Repo und clustere Merkmale…';
  @override
  String get noModel => 'Kein AI-Modell konfiguriert.';
  @override
  String get noModelConfigured => 'kein AI-Modell konfiguriert';
  @override
  String presentWith({required Object label}) => 'präsentieren mit ${label}';
  @override
  String presentingWith({required Object label}) => 'präsentiere mit ${label}…';
  @override
  String get reanalyze => 'Neu analysieren';
  @override
  String get saveDialogTitle => 'Repository-Zusammenfassung speichern';
  @override
  String saveFailed({required Object error}) =>
      'Speichern fehlgeschlagen: ${error}';
  @override
  String get savePresentationDialogTitle => 'Präsentation speichern';
  @override
  String savedTo({required Object path}) => 'Gespeichert unter ${path}';
}

// Path: xray.tabs
class _Translations$xray$tabs$de extends Translations$xray$tabs$en {
  _Translations$xray$tabs$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get map => 'Karte';
  @override
  String get signals => 'Signale';
  @override
  String get summary => 'Zusammenfassung';
  @override
  String get time => 'Zeit';
}

// Path: xray.trajectory
class _Translations$xray$trajectory$de extends Translations$xray$trajectory$en {
  _Translations$xray$trajectory$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get connectivity => 'konnektivität';
  @override
  String events({required Object n}) => '${n} Ereignisse';
  @override
  String get openInOrrery => 'In Orrery öffnen';
  @override
  String get readingHint => 'lese Historie…';
  @override
  String snapshots({required Object n}) => '${n} Schnappschüsse';
  @override
  String get steady =>
      'Stetig — keine strukturellen Ereignisse in diesem Fenster.';
  @override
  String get title => 'Strukturelle Trajektorie';
}

// Path: xray.verdict
class _Translations$xray$verdict$de extends Translations$xray$verdict$en {
  _Translations$xray$verdict$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String canonical({required Object pct}) => '${pct}% kanonisch';
  @override
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · ${canonical}% kanonisch · ${decisive}% entscheidend';
}

// Path: changes.mergeEditor.trust
class _Translations$changes$mergeEditor$trust$de
    extends Translations$changes$mergeEditor$trust$en {
  _Translations$changes$mergeEditor$trust$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get manual => 'manuell';
  @override
  String get safe => 'sicher';
  @override
  String get guided => 'geführt';
  @override
  String get assisted => 'assistiert';
  @override
  String get full => 'voll';
  @override
  String label({required Object label}) => 'Vertrauen: ${label}';
}

// Path: changes.mergeEditor.keyHints
class _Translations$changes$mergeEditor$keyHints$de
    extends Translations$changes$mergeEditor$keyHints$en {
  _Translations$changes$mergeEditor$keyHints$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get accept => 'annehmen';
  @override
  String get other => 'andere';
  @override
  String get both => 'beide';
  @override
  String get navigate => 'navigieren';
  @override
  String get jumpNext => 'zur nächsten springen';
}

// Path: changes.mergeFlow.op
class _Translations$changes$mergeFlow$op$de
    extends Translations$changes$mergeFlow$op$en {
  _Translations$changes$mergeFlow$op$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'merge';
  @override
  String get cherryPick => 'cherry-pick';
  @override
  String get revert => 'revert';
  @override
  String get resolve => 'lösen';
  @override
  String get switchOp => 'wechseln';
  @override
  String get pull => 'pull';
  @override
  String get rebase => 'rebase';
  @override
  String rebaseOnto({required Object branch, required Object base}) =>
      '${branch} auf ${base} rebasen';
}

// Path: diff.pinned.tempo
class _Translations$diff$pinned$tempo$de
    extends Translations$diff$pinned$tempo$en {
  _Translations$diff$pinned$tempo$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get hotOwnerLane =>
      'Kürzliche Bewegung mit einem starken Eigentümer in der Nähe.';
  @override
  String get activeSeam =>
      'Kürzliche Bewegung von mehreren Händen in der Nähe.';
  @override
  String get stableOwnerLane =>
      'Langlebige Bahn mit einem dominanten Eigentümer.';
  @override
  String get sharedLongLivedSeam =>
      'Geteilte Naht, die sich über die Zeit angesammelt hat.';
  @override
  String get sharedLane =>
      'Geteilte Bahn ohne einen einzelnen dominanten Eigentümer.';
  @override
  String get resolving => 'Die Historie klärt sich um diese Zeile noch.';
}

// Path: diff.pinned.tone
class _Translations$diff$pinned$tone$de
    extends Translations$diff$pinned$tone$en {
  _Translations$diff$pinned$tone$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get hot => 'Heiß';
  @override
  String get novel => 'Neu';
  @override
  String get contested => 'Umkämpft';
  @override
  String get spreading => 'Ausbreitend';
  @override
  String get stable => 'Stabil';
}

// Path: diff.pinned.summary
class _Translations$diff$pinned$summary$de
    extends Translations$diff$pinned$summary$en {
  _Translations$diff$pinned$summary$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String livesIn({required Object concept}) => 'Lebt in ${concept}';
  @override
  String get sitsInLocalSeam => 'Sitzt in einer lokalen Naht';
  @override
  String workedMostlyBy({required Object owner}) =>
      'meist von ${owner} in der Nähe bearbeitet';
  @override
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'hallt an ${n} weiterer Stelle wider',
        other: 'hallt an ${n} weiteren Stellen wider',
      );
  @override
  String inspectNext({required Object path, required Object detail}) =>
      'als Nächstes ${path} untersuchen${detail}';
  @override
  String inspectDetail({required Object reason}) => ' (${reason})';
}

// Path: diff.pinned.tightness
class _Translations$diff$pinned$tightness$de
    extends Translations$diff$pinned$tightness$en {
  _Translations$diff$pinned$tightness$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get tight => 'enge Passung';
  @override
  String get close => 'nahe Passung';
  @override
  String get loose => 'lose Passung';
}

// Path: diff.pinned.witness
class _Translations$diff$pinned$witness$de
    extends Translations$diff$pinned$witness$en {
  _Translations$diff$pinned$witness$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String nearbySupport({required Object label}) =>
      'Unterstützung in der Nähe · ${label}';
  @override
  String localizedMove({required Object label}) =>
      'Lokalisierte Bewegung · ${label}';
  @override
  String surprisingMove({required Object label}) =>
      'Überraschende Bewegung · ${label}';
}

// Path: diff.pinned.integrity
class _Translations$diff$pinned$integrity$de
    extends Translations$diff$pinned$integrity$en {
  _Translations$diff$pinned$integrity$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get stableStructure => 'Stabile Struktur';
  @override
  String get conflictingSignals => 'Widersprüchliche Signale';
  @override
  String get novelShape => 'Neue Form';
}

// Path: diff.pinned.related
class _Translations$diff$pinned$related$de
    extends Translations$diff$pinned$related$en {
  _Translations$diff$pinned$related$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get testMirror => 'Test-Spiegel';
  @override
  String get semanticHistorySibling => 'Semantik- + Historie-Geschwister';
  @override
  String get recentCoChange => 'Kürzliche Co-Change';
  @override
  String get semanticSibling => 'Semantisches Geschwister';
  @override
  String get relatedStructure => 'Verwandte Struktur';
  @override
  String get tightlyBound => 'eng gebunden';
  @override
  String get orbiting => 'umkreisend';
  @override
  String get weaklyCoupled => 'schwach gekoppelt';
  @override
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class _Translations$diff$pinned$axis$de
    extends Translations$diff$pinned$axis$en {
  _Translations$diff$pinned$axis$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get historyTrail => 'historien-spur';
  @override
  String get testMirrorLane => 'test-spiegel-bahn';
  @override
  String get structuralLane => 'strukturelle bahn';
  @override
  String get semanticNeighbourhood => 'semantische nachbarschaft';
}

// Path: history.commitLede.semantics
class _Translations$history$commitLede$semantics$de
    extends Translations$history$commitLede$semantics$en {
  _Translations$history$commitLede$semantics$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get importanceHigh => 'hohe Wichtigkeit';
  @override
  String get importanceModerate => 'mittlere Wichtigkeit';
  @override
  String get mostlyAdditions => 'überwiegend Hinzufügungen';
  @override
  String get mostlyDeletions => 'überwiegend Löschungen';
  @override
  String get tightlyCoupled => 'eng gekoppelte Dateien';
  @override
  String get overlapsWorkingTree => 'überschneidet dein Arbeitsverzeichnis';
}

// Path: onboarding.repo.doors
class _Translations$onboarding$repo$doors$de
    extends Translations$onboarding$repo$doors$en {
  _Translations$onboarding$repo$doors$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$repo$doors$open$de open =
      _Translations$onboarding$repo$doors$open$de._(_root);
  @override
  late final _Translations$onboarding$repo$doors$clone$de clone =
      _Translations$onboarding$repo$doors$clone$de._(_root);
  @override
  late final _Translations$onboarding$repo$doors$create$de create =
      _Translations$onboarding$repo$doors$create$de._(_root);
}

// Path: onboarding.repo.cloneForm
class _Translations$onboarding$repo$cloneForm$de
    extends Translations$onboarding$repo$cloneForm$en {
  _Translations$onboarding$repo$cloneForm$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Von URL klonen';
  @override
  String get urlLabel => 'Repository-URL';
  @override
  String get targetLabel => 'Zielordner';
  @override
  String get browse => 'Durchsuchen…';
  @override
  String get clone => 'Klonen';
  @override
  String get cloning => 'Klont…';
}

// Path: onboarding.repo.pickers
class _Translations$onboarding$repo$pickers$de
    extends Translations$onboarding$repo$pickers$en {
  _Translations$onboarding$repo$pickers$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get openRepository => 'Repository öffnen';
  @override
  String get createRepository => 'Repository erstellen';
  @override
  String get cloneTarget => 'Klon-Ziel';
}

// Path: onboarding.repo.errors
class _Translations$onboarding$repo$errors$de
    extends Translations$onboarding$repo$errors$en {
  _Translations$onboarding$repo$errors$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get urlAndTargetRequired => 'URL und Zielpfad erforderlich.';
  @override
  String get createFailed => 'Repository konnte nicht erstellt werden.';
  @override
  String get cloneFailed => 'Repository konnte nicht geklont werden.';
}

// Path: onboarding.preview.panels
class _Translations$onboarding$preview$panels$de
    extends Translations$onboarding$preview$panels$en {
  _Translations$onboarding$preview$panels$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get xray => 'repo x-ray';
  @override
  String get settings => 'einstellungen';
}

// Path: onboarding.preview.sidebar
class _Translations$onboarding$preview$sidebar$de
    extends Translations$onboarding$preview$sidebar$en {
  _Translations$onboarding$preview$sidebar$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get projectsHeader => 'Projekte';
}

// Path: onboarding.preview.changes
class _Translations$onboarding$preview$changes$de
    extends Translations$onboarding$preview$changes$en {
  _Translations$onboarding$preview$changes$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String filesStagedCount({required Object staged, required Object total}) =>
      '${staged} von ${total} Dateien';
  @override
  String stagedCount({required Object n}) => '${n} gestaged';
  @override
  String get commitMessageHint => 'Commit-Nachricht…';
  @override
  String get commitAndPush => 'Committen & pushen';
}

// Path: onboarding.preview.history
class _Translations$onboarding$preview$history$de
    extends Translations$onboarding$preview$history$en {
  _Translations$onboarding$preview$history$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'Verlauf';
  @override
  String get viewingLast => 'zeige letzte 20 Commits';
  @override
  String get inFlight => 'UNTERWEGS';
  @override
  String get you => 'du';
  @override
  String get commit1 => 'fuchs beibringen, vor dem schlucken zu schnuppern';
  @override
  String get commit2 => 'amber: duft über nacht halten';
  @override
  String get commit3 => 'kohl abschaffen zugunsten von amber + dorn';
  @override
  String get commit4 => 'dorn bewacht das tor';
}

// Path: onboarding.preview.branches
class _Translations$onboarding$preview$branches$de
    extends Translations$onboarding$preview$branches$en {
  _Translations$onboarding$preview$branches$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get lensBranches => 'BRANCHES';
  @override
  String get lensPRs => 'PRs';
  @override
  String get absorbed => 'absorbiert';
  @override
  String get desk => 'desk';
  @override
  String get head => 'HEAD';
  @override
  String tracking({required Object ref}) => '→ verfolgt: ${ref}';
}

// Path: onboarding.preview.diff
class _Translations$onboarding$preview$diff$de
    extends Translations$onboarding$preview$diff$en {
  _Translations$onboarding$preview$diff$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get readmeTagline => 'Dein persönlicher Git-Client.';
}

// Path: releaseNotes.about.whyFlutter
class _Translations$releaseNotes$about$whyFlutter$de
    extends Translations$releaseNotes$about$whyFlutter$en {
  _Translations$releaseNotes$about$whyFlutter$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'WARUM FLUTTER?';
  @override
  String get body =>
      'Die erste Version davon war eine Tauri-App (Rust + TypeScript). Ich wusste schon, dass sie sich träge anfühlte. Dann hörte ich einen Streamer in einem Stream, den ich sonst nicht schaue, dasselbe sagen, und das war der Anstoß, endlich zu wechseln. Er hat kein Flutter vorgeschlagen; ganz im Gegenteil. Dart habe ich selbst gefunden, einen Prototyp zusammengeschustert, und die Startzeit ging von etwa 15 Sekunden auf unter eine Sekunde. Tag und Nacht. Leb wohl, Tauri-Ära.\n\nFlutters Rendering-Pipeline liegt näher an einer Game-Engine als an einem DOM, und für eine Desktop-App, bei der die UI das Produkt ist, ist das alles. Dart entpuppte sich obendrein als richtig gute Sprache. Die Mathematik hinter der Spektral-Engine wurde zuerst in Rust prototypisiert, also ließ sich diese Arbeit problemlos übertragen.\n\nFlutter ist von Haus aus plattformübergreifend, was großartig ist, aber es ist von Natur aus googlig, also gibt es ein paar Macken.';
}

// Path: releaseNotes.about.spectralEngine
class _Translations$releaseNotes$about$spectralEngine$de
    extends Translations$releaseNotes$about$spectralEngine$en {
  _Translations$releaseNotes$about$spectralEngine$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'WAS IST DIE SPEKTRAL-ENGINE?';
  @override
  String get body =>
      'Jedes Mal, wenn du committest, bilden die Dateien, die du zusammen änderst, über die Zeit Muster. Die Spektral-Engine liest deinen Commit-Graphen und zerlegt diese Co-Change-Muster in Signale: welche Dateien gekoppelt sind, wie eng, und welche strukturelle Rolle sie im Repo spielen. Im Grunde Spektralanalyse deiner Entwicklungshistorie. In einem Git-Client. Mit Absicht.\n\nDie Mathematik ist neu, also behandle ich sie wie Game-Feel: einstellen, testen, nachjustieren und weitermachen, bis sich die Signale richtig anfühlen.\n\nDiese Signale fließen in alles ein. Der Seismograph im Verlauf, die gemalten Balken unter den Commit-Betreffs, das Review-System, Muse, die Datei-Konstellation. Die ganze App denkt von dieser Schicht nach unten, nicht andersherum.';
}

// Path: releaseNotes.about.whereGoing
class _Translations$releaseNotes$about$whereGoing$de
    extends Translations$releaseNotes$about$whereGoing$en {
  _Translations$releaseNotes$about$whereGoing$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'WOHIN GEHT DAS?';
  @override
  String get body =>
      'Der erste Meilenstein ist volle Ebenbürtigkeit mit GitHub Desktop, SourceTree und GitKraken. Ein plattformübergreifender Git-Client, der sich schnell anfühlt und die Grundlagen besser beherrscht als alles andere. Das ist größtenteils da. Die Spektral-Engine verschafft uns schon jetzt einen Vorteil bei Operationen, die dich andere Clients manuell durchdenken lassen.\n\nDarüber hinaus ist das Ziel, jeden anderen Git-Client in Geschwindigkeit, Zugänglichkeit, Intelligenz und der Gesamt-UX zu übertreffen. In der Pipeline steckt mehr, als hier angekündigt ist.';
}

// Path: settings.commitPreview.title
class _Translations$settings$commitPreview$title$de
    extends Translations$settings$commitPreview$title$en {
  _Translations$settings$commitPreview$title$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$verbLed$de verbLed =
      _Translations$settings$commitPreview$title$verbLed$de._(_root);
  @override
  late final _Translations$settings$commitPreview$title$descriptive$de
  descriptive = _Translations$settings$commitPreview$title$descriptive$de._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$title$narrative$de narrative =
      _Translations$settings$commitPreview$title$narrative$de._(_root);
}

// Path: settings.commitPreview.base
class _Translations$settings$commitPreview$base$de
    extends Translations$settings$commitPreview$base$en {
  _Translations$settings$commitPreview$base$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$base$verbLed$de verbLed =
      _Translations$settings$commitPreview$base$verbLed$de._(_root);
  @override
  late final _Translations$settings$commitPreview$base$descriptive$de
  descriptive = _Translations$settings$commitPreview$base$descriptive$de._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$base$narrative$de narrative =
      _Translations$settings$commitPreview$base$narrative$de._(_root);
}

// Path: settings.commitPreview.balancedSuffix
class _Translations$settings$commitPreview$balancedSuffix$de
    extends Translations$settings$commitPreview$balancedSuffix$en {
  _Translations$settings$commitPreview$balancedSuffix$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$verbLed$de
  verbLed = _Translations$settings$commitPreview$balancedSuffix$verbLed$de._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$descriptive$de
  descriptive =
      _Translations$settings$commitPreview$balancedSuffix$descriptive$de._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$narrative$de
  narrative =
      _Translations$settings$commitPreview$balancedSuffix$narrative$de._(_root);
}

// Path: settings.commitPreview.everythingSuffix
class _Translations$settings$commitPreview$everythingSuffix$de
    extends Translations$settings$commitPreview$everythingSuffix$en {
  _Translations$settings$commitPreview$everythingSuffix$de._(
    TranslationsDe root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$verbLed$de
  verbLed = _Translations$settings$commitPreview$everythingSuffix$verbLed$de._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$descriptive$de
  descriptive =
      _Translations$settings$commitPreview$everythingSuffix$descriptive$de._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$narrative$de
  narrative =
      _Translations$settings$commitPreview$everythingSuffix$narrative$de._(
        _root,
      );
}

// Path: xray.cards.branchModel
class _Translations$xray$cards$branchModel$de
    extends Translations$xray$cards$branchModel$en {
  _Translations$xray$cards$branchModel$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get broadClaim =>
      'Das Repository hat genug Branch-Fläche, um branchbewusste Navigation zu belohnen.';
  @override
  String get broadTitle => 'Branch-Modell hat Fläche';
  @override
  String localBranchesDetail({required Object count}) =>
      '${count} lokale Branches.';
  @override
  String get localBranchesLabel => 'Lokale Branches';
  @override
  String remoteBranchesDetail({required Object count}) =>
      '${count} Remote-Branches.';
  @override
  String get remoteBranchesLabel => 'Remote-Branches';
  @override
  String get simpleClaim => 'Das sichtbare Branch-Modell ist schmal.';
  @override
  String get simpleTitle => 'Einfaches Branch-Modell';
}

// Path: xray.cards.bursty
class _Translations$xray$cards$bursty$de
    extends Translations$xray$cards$bursty$en {
  _Translations$xray$cards$bursty$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Arbeit landet in konzentrierten Schüben statt in einem gleichmäßigen Tagesrhythmus.';
  @override
  String get title => 'Schubartige Entwicklungs-Kadenz';
}

// Path: xray.cards.hiddenRefs
class _Translations$xray$cards$hiddenRefs$de
    extends Translations$xray$cards$hiddenRefs$en {
  _Translations$xray$cards$hiddenRefs$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object count}) =>
      '${count} Refs leben außerhalb des normalen Branch-/Tag-Raums.';
  @override
  String evidenceDetail({required Object count}) =>
      '${count} Refs außerhalb von heads/remotes/tags.';
  @override
  String get evidenceLabel => 'Versteckte Refs';
  @override
  String get namespacesLabel => 'Namespaces';
  @override
  String get title => 'Versteckte Git-Namespaces';
}

// Path: xray.cards.keystone
class _Translations$xray$cards$keystone$de
    extends Translations$xray$cards$keystone$en {
  _Translations$xray$cards$keystone$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String claim({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    n,
    one:
        'Eine Datei trägt überproportionales Co-Change-Gewicht relativ zu ihrer Berührungszahl.',
    other:
        'Ein kleiner Satz Dateien trägt überproportionales Co-Change-Gewicht relativ zu ihren Berührungszahlen.',
  );
  @override
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: '${n} Berührung · Zug φ=${score}',
        other: '${n} Berührungen · Zug φ=${score}',
      );
  @override
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
        n,
        one: 'Schlussstein-Brückendatei',
        other: '${n} Schlussstein-Brückendateien',
      );
}

// Path: xray.cards.machineHistory
class _Translations$xray$cards$machineHistory$de
    extends Translations$xray$cards$machineHistory$en {
  _Translations$xray$cards$machineHistory$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Checkpoint-artige Commits verzerren naive Historien-Metriken erheblich.';
  @override
  String machineCommitsDetail({required Object count}) =>
      '${count} Commits entsprachen Maschinen-/Session-Mustern.';
  @override
  String get machineCommitsLabel => 'Maschinen-Commits';
  @override
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '${raw} rohe Commits vs ${filtered} gefilterte Commits.';
  @override
  String get rawVsFilteredLabel => 'Roh vs gefiltert';
  @override
  String get title => 'Maschinen-Historie dominiert die Rohmetriken';
}

// Path: xray.cards.migration
class _Translations$xray$cards$migration$de
    extends Translations$xray$cards$migration$en {
  _Translations$xray$cards$migration$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object older, required Object newer}) =>
      'Die Historie verschiebt sich von `${older}` zu `${newer}`, was auf einen Stack- oder Oberflächenwechsel hindeutet.';
  @override
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches} Berührungen, zuletzt aktiv ${lastActive}.';
  @override
  String get title => 'Architektur-Migration sichtbar';
}

// Path: xray.cards.narrowHotspot
class _Translations$xray$cards$narrowHotspot$de
    extends Translations$xray$cards$narrowHotspot$en {
  _Translations$xray$cards$narrowHotspot$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Ein kleiner Satz Dateien und Verzeichnisse absorbiert einen überproportionalen Anteil der Änderungen.';
  @override
  String get title => 'Hotspot-Konzentration ist schmal';
  @override
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path} macht ${pct}% des sichtbaren Hotspot-Satzes aus.';
  @override
  String get topHotspotLabel => 'Top-Hotspot';
  @override
  String visibleAuthorsDetail({required Object count}) =>
      '${count} Autoren in diesem Historien-Ausschnitt.';
  @override
  String get visibleAuthorsLabel => 'Sichtbare Autoren';
}

// Path: xray.cards.noTags
class _Translations$xray$cards$noTags$de
    extends Translations$xray$cards$noTags$en {
  _Translations$xray$cards$noTags$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Git-Tags werden nicht als sichtbare Release- oder Meilenstein-Ebene genutzt.';
  @override
  String remoteEndpointsDetail({required Object count}) =>
      '${count} Remote-Endpunkte konfiguriert.';
  @override
  String get remoteEndpointsLabel => 'Remote-Endpunkte';
  @override
  String get tagCountDetail => '0 Tags gefunden.';
  @override
  String get tagCountLabel => 'Tag-Anzahl';
  @override
  String get title => 'Keine formale Release-/Tag-Spur';
}

// Path: xray.cards.reflog
class _Translations$xray$cards$reflog$de
    extends Translations$xray$cards$reflog$en {
  _Translations$xray$cards$reflog$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Das Reflog-Volumen deutet auf konzentrierte lokale Iteration jenseits veröffentlichter Commits hin.';
  @override
  String get peakReflogDayLabel => 'Reflog-Spitzentag';
  @override
  String get title => 'Intensive lokale Editier-Sessions';
}

// Path: xray.cards.singleOwner
class _Translations$xray$cards$singleOwner$de
    extends Translations$xray$cards$singleOwner$en {
  _Translations$xray$cards$singleOwner$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object path, required Object kind}) =>
      '`${path}` ist ein stark berührter ${kind} mit einem einzigen erkennbaren sichtbaren Autor.';
  @override
  String ownerCountDetail({required Object count}) =>
      '${count} eindeutige Autoren.';
  @override
  String get ownerCountLabel => 'Anzahl Eigentümer';
  @override
  String get title => 'Ein-Eigentümer-Hotspot';
  @override
  String get touchCountLabel => 'Berührungszahl';
  @override
  String touchDetailFiltered({required Object count}) =>
      '${count} Berührungen in gefilterter Historie.';
  @override
  String touchDetailRaw({required Object count}) =>
      '${count} Berührungen in roher Historie.';
}

// Path: onboarding.repo.doors.open
class _Translations$onboarding$repo$doors$open$de
    extends Translations$onboarding$repo$doors$open$en {
  _Translations$onboarding$repo$doors$open$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Öffnen';
  @override
  String get subtitle => 'vorhanden';
  @override
  String get hint => 'eins, das du schon hast';
}

// Path: onboarding.repo.doors.clone
class _Translations$onboarding$repo$doors$clone$de
    extends Translations$onboarding$repo$doors$clone$en {
  _Translations$onboarding$repo$doors$clone$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Klonen';
  @override
  String get subtitle => 'von URL';
  @override
  String get hint => 'eine Remote-URL einfügen';
}

// Path: onboarding.repo.doors.create
class _Translations$onboarding$repo$doors$create$de
    extends Translations$onboarding$repo$doors$create$en {
  _Translations$onboarding$repo$doors$create$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Erstellen';
  @override
  String get subtitle => 'neu';
  @override
  String get hint => 'was Frisches anfangen';
}

// Path: settings.commitPreview.title.verbLed
class _Translations$settings$commitPreview$title$verbLed$de
    extends Translations$settings$commitPreview$title$verbLed$en {
  _Translations$settings$commitPreview$title$verbLed$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Lass Fuchs Kekse auslassen, die komisch riechen';
  @override
  String get s2 =>
      'Bring Fuchs bei, manipulierte Kekse vor dem Schlucken abzulehnen';
  @override
  String get s3 => 'Zwing Fuchs, jeden Keks am Tor forensisch zu prüfen';
  @override
  String get def => 'Bring Fuchs bei, schlechte Kekse abzulehnen';
}

// Path: settings.commitPreview.title.descriptive
class _Translations$settings$commitPreview$title$descriptive$de
    extends Translations$settings$commitPreview$title$descriptive$en {
  _Translations$settings$commitPreview$title$descriptive$de._(
    TranslationsDe root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Fuchs sucht jetzt die Kekse aus';
  @override
  String get s2 => 'Keks-Inspektionsroutine, dem Fuchs eingedrillt';
  @override
  String get s3 =>
      'Keks-Prüfforensik, dem Fuchs durch Wiederholung eingepflanzt';
  @override
  String get def => 'Keks-Schnupper-Protokoll, im Fuchs installiert';
}

// Path: settings.commitPreview.title.narrative
class _Translations$settings$commitPreview$title$narrative$de
    extends Translations$settings$commitPreview$title$narrative$en {
  _Translations$settings$commitPreview$title$narrative$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'der Fuchs fing an, komisch riechende Kekse auszulassen';
  @override
  String get s2 =>
      'Mit dem Fuchs zusammengesetzt und durchgegangen, welche Kekse abzulehnen sind';
  @override
  String get s3 =>
      'Den halben Nachmittag damit verbracht, den Fuchs zu überzeugen, dass nicht jeder angebotene Keks in gutem Glauben ein Keks ist';
  @override
  String get def =>
      'Den Fuchs gebeten, Kekse zu beschnuppern, bevor er sie frisst';
}

// Path: settings.commitPreview.base.verbLed
class _Translations$settings$commitPreview$base$verbLed$de
    extends Translations$settings$commitPreview$base$verbLed$en {
  _Translations$settings$commitPreview$base$verbLed$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Fuchs schaut kurz. Was komisch ist, bleibt liegen.';
  @override
  String get s2 =>
      'Fuchs inspiziert jeden Token, lehnt alles Anrüchige ab und vermerkt die Ablehnung auf der Veranda.';
  @override
  String get s3 =>
      'Fuchs umkreist jeden Token, prüft die Luft aus drei Winkeln, lehnt jeden ab, der falsch riecht, und wartet einen Moment, damit die Ablehnung sitzt.';
  @override
  String get def =>
      'Fuchs beschnuppert jetzt jeden Token und lehnt die verdächtigen höflich ab.';
}

// Path: settings.commitPreview.base.descriptive
class _Translations$settings$commitPreview$base$descriptive$de
    extends Translations$settings$commitPreview$base$descriptive$en {
  _Translations$settings$commitPreview$base$descriptive$de._(
    TranslationsDe root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Sanfter Durchlauf bei den komischen, meistens.';
  @override
  String get s2 =>
      'Eine dokumentierte Ablehnung bei jedem anrüchigen Token, von der Veranda erteilt und vermerkt.';
  @override
  String get s3 =>
      'Eine beglaubigte Ablehnung pro anrüchigem Token, von der Veranda erteilt, eine Pfote gehoben, die andere still.';
  @override
  String get def =>
      'Eine höfliche Ablehnung bei verdächtigen Token, von der Veranda erteilt.';
}

// Path: settings.commitPreview.base.narrative
class _Translations$settings$commitPreview$base$narrative$de
    extends Translations$settings$commitPreview$base$narrative$en {
  _Translations$settings$commitPreview$base$narrative$de._(TranslationsDe root)
    : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      'Der Fuchs hörte einfach auf, die komischen zu fressen. Ganz easy.';
  @override
  String get s2 =>
      'Früher ging jeder Token ohne viel Nachdenken runter; jetzt gibt es eine Pause, einen richtigen Blick und eine Ablehnung für die, die nicht passen.';
  @override
  String get s3 =>
      'Früher ging jeder Token gedankenlos runter. Jetzt: eine Pause. Die Luft, eingesogen. Die Luft, gehalten. Der Fuchs beobachtet die Verandabretter auf das kleine Zucken, das sie manchmal haben, wenn etwas nicht stimmt, und erst dann fällt die Entscheidung.';
  @override
  String get def =>
      'Früher wurde jeder Token ohne Zeremonie geschluckt; jetzt gibt es erst ein Schnuppern.';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class _Translations$settings$commitPreview$balancedSuffix$verbLed$de
    extends Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  _Translations$settings$commitPreview$balancedSuffix$verbLed$de._(
    TranslationsDe root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Veranda ist okay. Hinterhof ist egal.';
  @override
  String get s2 =>
      ' Veranda nach jeder Ablehnung gefegt; Hinterhof-Matsch innerhalb der ausgehängten Zeiten erlaubt.';
  @override
  String get s3 =>
      ' Veranda gefegt und nachgefegt; Hinterhof-Matsch nach Pfotenabdruck und Wetter katalogisiert, und der Fuchs verweilt länger als früher an der Schwelle.';
  @override
  String get def =>
      ' Veranda bleibt sauber; der Hinterhof behält seine Matsch-Rechte.';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class _Translations$settings$commitPreview$balancedSuffix$descriptive$de
    extends Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  _Translations$settings$commitPreview$balancedSuffix$descriptive$de._(
    TranslationsDe root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Veranda okay. Hinterhof macht Hinterhof-Sachen.';
  @override
  String get s2 =>
      ' Veranda als beweissaubere Zone; Hinterhof als ausgewiesene Matsch-Zone, Zeiten ausgehängt.';
  @override
  String get s3 =>
      ' Veranda als Reinraum in Beweisqualität; Hinterhof als katalogisiertes Matsch-Archiv; Schwelle als Ort, an dem der Fuchs steht und zu lange nachdenkt.';
  @override
  String get def => ' Saubere Veranda; Matsch-Rechte im Hinterhof gewahrt.';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class _Translations$settings$commitPreview$balancedSuffix$narrative$de
    extends Translations$settings$commitPreview$balancedSuffix$narrative$en {
  _Translations$settings$commitPreview$balancedSuffix$narrative$de._(
    TranslationsDe root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Veranda war okay. Hinterhof, wer weiß.';
  @override
  String get s2 =>
      ' Die Veranda wurde danach sauber gehalten; der Fuchs zog sich in den Hinterhof zurück, wo das Nachdenken passiert.';
  @override
  String get s3 =>
      ' Die Veranda wurde an dem Abend zweimal geschrubbt. Der Fuchs ging langsam durch den Hinterhof, hielt am immer gleichen Zaunpfahl inne und blickte zur Veranda zurück, als schulde sie ihm etwas.';
  @override
  String get def =>
      ' Die Veranda bleibt sauber, auch wenn der Hinterhof in Sachen Würde noch gewinnt.';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class _Translations$settings$commitPreview$everythingSuffix$verbLed$de
    extends Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  _Translations$settings$commitPreview$everythingSuffix$verbLed$de._(
    TranslationsDe root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Amber ist da. Drift driftet. Dorn sticht, wenn\'s sein muss. Meistens nichts.';
  @override
  String get s2 =>
      ' Amber hält jeden Duft zur Prüfung. Drift trägt die Tagesluft zum Tor-Dorn, der jede Ablehnung für die Abendabrechnung markiert.';
  @override
  String get s3 =>
      ' Amber hält jeden Duft und gibt ihm je nach Stunde ein anderes Gewicht. Drift zieht in Winkeln durch die Veranda, die keine Rolle spielen sollten, es aber tun. Der Tor-Dorn sticht einmal für Ablehnungen und zweimal für die, die der Fuchs fast übersehen hätte, und der Fuchs kennt den Unterschied, auch wenn es sonst niemand tut.';
  @override
  String get def =>
      ' Amber hält den Duft. Drift trägt ihn weiter. Der Tor-Dorn fängt, was nicht durch soll.';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class _Translations$settings$commitPreview$everythingSuffix$descriptive$de
    extends
        Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  _Translations$settings$commitPreview$everythingSuffix$descriptive$de._(
    TranslationsDe root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Amber am Pfosten. Drift in der Luft. Dorn am Tor. Passt.';
  @override
  String get s2 =>
      ' Amber als ausgewiesener Duft-Zeuge; Drift als protokollierte Umgebung; Dorn-Marken als das Ablehnungsregister des Tages, bei Einbruch der Nacht abgeglichen.';
  @override
  String get s3 =>
      ' Amber als Duft-Zeuge, dessen Schweigen selbst schon eine Lesung ist; Drift als gemustertes Ambiente, das an den Tagen falsch zieht, an denen etwas falsch ist; Dorn als Zählmeister des Tores, dessen Marken der Fuchs vor dem Schlafen und wieder vor Morgengrauen prüft.';
  @override
  String get def =>
      ' Amber als Duft-Zeuge; Drift als Umgebungskontext; Dorn als die stille Ablehnungs-Marke des Tores.';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class _Translations$settings$commitPreview$everythingSuffix$narrative$de
    extends Translations$settings$commitPreview$everythingSuffix$narrative$en {
  _Translations$settings$commitPreview$everythingSuffix$narrative$de._(
    TranslationsDe root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Amber war da. Drift kam und ging. Dorn machte sein stilles Ding. Egal, war entspannt.';
  @override
  String get s2 =>
      ' Amber führte das Duft-Register des Tages, Drift wurde nach Richtung und Stunde vermerkt, und die Dorn-Marken wurden gezählt und von der Veranda gegengezeichnet.';
  @override
  String get s3 =>
      ' Amber führte das Duft-Register, aber der Fuchs schwört, es wiegt an bestimmten Morgen schwerer. Drift zog durch die Veranda, wie es das immer tut, was heißt: falsch an den Tagen, die zählen. Der Tor-Dorn markierte jede Ablehnung; der Fuchs ging bei erstem Licht hinaus, sie zu zählen, so wie man Stufen zählt, die man schon gezählt hat.';
  @override
  String get def =>
      ' Amber hielt das Duft-Register, Drift bewegte die Luft, und der Tor-Dorn fing, was gefangen werden musste.';
}
