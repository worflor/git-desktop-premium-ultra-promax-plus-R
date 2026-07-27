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
class TranslationsPl extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsPl({
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
             locale: AppLocale.pl,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <pl>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final TranslationsPl _root = this; // ignore: unused_field

  @override
  TranslationsPl $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsPl(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$app$pl app = _Translations$app$pl._(_root);
  @override
  late final _Translations$backend$pl backend = _Translations$backend$pl._(
    _root,
  );
  @override
  late final _Translations$branches$pl branches = _Translations$branches$pl._(
    _root,
  );
  @override
  late final _Translations$changes$pl changes = _Translations$changes$pl._(
    _root,
  );
  @override
  late final _Translations$common$pl common = _Translations$common$pl._(_root);
  @override
  late final _Translations$diff$pl diff = _Translations$diff$pl._(_root);
  @override
  late final _Translations$filament$pl filament = _Translations$filament$pl._(
    _root,
  );
  @override
  late final _Translations$history$pl history = _Translations$history$pl._(
    _root,
  );
  @override
  late final _Translations$historySurgery$pl historySurgery =
      _Translations$historySurgery$pl._(_root);
  @override
  late final _Translations$onboarding$pl onboarding =
      _Translations$onboarding$pl._(_root);
  @override
  late final _Translations$orrery$pl orrery = _Translations$orrery$pl._(_root);
  @override
  late final _Translations$palette$pl palette = _Translations$palette$pl._(
    _root,
  );
  @override
  late final _Translations$releaseNotes$pl releaseNotes =
      _Translations$releaseNotes$pl._(_root);
  @override
  late final _Translations$repoSummary$pl repoSummary =
      _Translations$repoSummary$pl._(_root);
  @override
  late final _Translations$review$pl review = _Translations$review$pl._(_root);
  @override
  late final _Translations$settings$pl settings = _Translations$settings$pl._(
    _root,
  );
  @override
  late final _Translations$sync$pl sync = _Translations$sync$pl._(_root);
  @override
  late final _Translations$xray$pl xray = _Translations$xray$pl._(_root);
}

// Path: app
class _Translations$app$pl extends Translations$app$en {
  _Translations$app$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get panelSettings => 'Ustawienia';
  @override
  String get panelReleaseNotes => 'Uwagi do wydania';
  @override
  String get panelFilamentFindings => 'Znaleziska Filament';
  @override
  String get filamentFindingsUpper => 'ZNALEZISKA FILAMENT';
  @override
  late final _Translations$app$cheatsheet$pl cheatsheet =
      _Translations$app$cheatsheet$pl._(_root);
  @override
  String get commandPaletteTooltip => 'Paleta poleceń   /';
  @override
  String get newDeskFallback => 'nowy Desk';
  @override
  String get deskFallback => 'Desk';
  @override
  String get currentDeskFallback => 'bieżące';
  @override
  String get noRepositoryOpen => 'Brak otwartego repozytorium';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Nie udało się otworzyć jako Desk: ${error}';
  @override
  String couldNotDetectForge({required Object error}) =>
      'Nie udało się wykryć forge: ${error}';
  @override
  String get cannotFetchPrNoForge =>
      'Nie można pobrać PR: nie wykryto forge dla tego repozytorium.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      'Nadpisać ${ref} najnowszą wersją ze zdalnego?';
  @override
  String get overwrite => 'Nadpisz';
  @override
  String couldntFetchPr({required Object error}) =>
      'Nie udało się pobrać PR: ${error}';
  @override
  String get promoteDeskToPr => 'Wypromuj Desk do PR';
  @override
  String get applyToMain => 'Zastosuj do main';
  @override
  String updateDeskFrom({required Object target, required Object source}) =>
      'Zaktualizuj ${target} z ${source}';
  @override
  String bringChangesFromHere({required Object source}) =>
      'Przenieś zmiany z ${source} tutaj';
  @override
  String get editLocalPr => 'Edytuj lokalny PR';
  @override
  String get discardLocalPr => 'Odrzuć lokalny PR';
  @override
  String get closeDesk => 'Zamknij Desk';
  @override
  String couldntPromote({required Object error}) =>
      'Nie udało się wypromować: ${error}';
  @override
  String get commitOrShelveBeforeApplying =>
      'Zacommituj lub odłóż zmiany Desku przed zastosowaniem.';
  @override
  String get couldNotResolveMainWorktree =>
      'Nie udało się ustalić ścieżki głównego drzewa roboczego.';
  @override
  String couldntPromoteDesk({required Object error}) =>
      'Nie udało się wypromować Desku: ${error}';
  @override
  String get couldntDetermineBaseBranch =>
      'Nie udało się ustalić gałęzi bazowej dla tego Desku.';
  @override
  String prBaseHeadSame({required Object branch}) =>
      'Baza i wierzchołek PR to ta sama gałąź (${branch}) — nie ma czego zastosować.';
  @override
  String appliedBranchToBase({required Object branch, required Object base}) =>
      'Zastosowano ${branch} do ${base}';
  @override
  String updatedDeskToDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
    n,
    one: 'Zaktualizowano ${target} do ${source} (${n} commit).',
    few: 'Zaktualizowano ${target} do ${source} (${n} commity).',
    many: 'Zaktualizowano ${target} do ${source} (${n} commitów).',
    other: 'Zaktualizowano ${target} do ${source} (${n} commita).',
  );
  @override
  String get fastForwardFailedFallback =>
      'Fast-forward nie zadziałał czysto — zamiast tego pokazuję podgląd patcha.';
  @override
  String deskAheadOfDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
    n,
    one: '${target} wyprzedza ${source} o ${n} commit.',
    few: '${target} wyprzedza ${source} o ${n} commity.',
    many: '${target} wyprzedza ${source} o ${n} commitów.',
    other: '${target} wyprzedza ${source} o ${n} commita.',
  );
  @override
  String deskUpToDate({required Object target, required Object source}) =>
      '${target} jest już zsynchronizowane z ${source}.';
  @override
  String uncommittedPreviewNotice({required Object target}) =>
      'Niezacommitowane zmiany w ${target} — pokazuję jako patch.';
  @override
  String updateDeskFromLower({
    required Object target,
    required Object source,
  }) => 'zaktualizuj ${target} z ${source}';
  @override
  String noUpdatesToBringFrom({required Object source}) =>
      'Brak aktualizacji do przeniesienia z ${source}.';
  @override
  String get updatePrepFailed => 'Nie udało się przygotować aktualizacji';
  @override
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => 'przenieś zmiany z ${source} do ${target}';
  @override
  String noPatchableChanges({required Object source, required Object target}) =>
      'Brak zmian do przeniesienia patchem z ${source} do ${target}.';
  @override
  String get patchPrepFailed => 'Nie udało się przygotować patcha';
  @override
  String failureWithError({required Object label, required Object error}) =>
      '${label}: ${error}';
  @override
  String get titleHint => 'tytuł';
  @override
  String get bodyHint => 'treść';
  @override
  String get bodyOptionalHint => 'treść (opcjonalnie)';
  @override
  String get draftLower => 'szkic';
  @override
  String get cancelLower => 'anuluj';
  @override
  String get saveLower => 'zapisz';
  @override
  String couldntSave({required Object error}) =>
      'Nie udało się zapisać: ${error}';
  @override
  String get stashedNoOtherDesk =>
      'Zmiany schowane — brak innego Desku do ich zastosowania. Użyj git stash pop, aby je odzyskać.';
  @override
  String get suggestedSource => 'sugerowane źródło';
  @override
  String tooltipModifiedCount({required Object n}) => '${n} zmienionych';
  @override
  String tooltipAheadCount({required Object n}) => '${n} do przodu';
  @override
  String tooltipBehindCount({required Object n}) => '${n} w tyle';
  @override
  String get focusedEdits => 'skupione zmiany';
  @override
  String get editsSpreadAcrossSubsystems =>
      'zmiany rozproszone po podsystemach';
  @override
  String get editsTouchingManySubsystems =>
      'zmiany dotykające wielu podsystemów';
  @override
  String get focusedBranch => 'skupiona gałąź';
  @override
  String get branchSpansMultipleSubsystems =>
      'gałąź obejmuje wiele podsystemów';
  @override
  String get structurallyDivergentFromMainline =>
      'strukturalnie rozbieżna z główną linią';
  @override
  String get localPr => 'lokalny PR';
  @override
  String lastTouched({required Object time}) => 'ostatnio dotknięte ${time}';
  @override
  String driftGroupCount({required Object n, required Object dir}) =>
      '${n} w ${dir}';
  @override
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';
  @override
  String get uncommittedChanges => 'Niezacommitowane zmiany';
  @override
  String get closeDeskQuestion => 'Zamknąć Desk?';
  @override
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} niezacommitowany plik.',
        few: '${n} niezacommitowane pliki.',
        many: '${n} niezacommitowanych plików.',
        other: '${n} niezacommitowanego pliku.',
      );
  @override
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} commit do przodu względem main.',
        few: '${n} commity do przodu względem main.',
        many: '${n} commitów do przodu względem main.',
        other: '${n} commita do przodu względem main.',
      );
  @override
  String get willRemoveWorktreeDirectory =>
      'To usunie katalog drzewa roboczego.';
  @override
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} plik zmieniony',
        few: '${n} pliki zmienione',
        many: '${n} plików zmienionych',
        other: '${n} pliku zmienione',
      );
  @override
  String get shelveHere => 'Odłóż tutaj';
  @override
  String get discardAndClose => 'Odrzuć i zamknij';
  @override
  String get noRepository => 'brak repozytorium';
  @override
  String get issuePromotedToRemote => 'Zgłoszenie wypromowane do zdalnego.';
  @override
  String get pushedToRemote => 'Pushnięto do zdalnego.';
  @override
  String get pulledFromRemote => 'Pullnięto ze zdalnego.';
  @override
  String get remoteIssueNotFound => 'nie znaleziono zdalnego zgłoszenia';
  @override
  String importedIssueLocally({required Object id}) =>
      'Zaimportowano #${id} lokalnie.';
  @override
  String get issueAbandoned => 'Zgłoszenie porzucone.';
  @override
  String get abandonIssue => 'Porzuć zgłoszenie';
  @override
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      'Trwale usunąć lokalne zgłoszenie #${id}? Usunie to jego ref i nie da się cofnąć.';
  @override
  String get abandon => 'Porzuć';
  @override
  String publishedBranch({required Object branch}) => 'Opublikowano ${branch}.';
  @override
  String get publishingEllipsis => 'Publikowanie…';
  @override
  String get publish => 'Opublikuj';
  @override
  String get noRemoteConfigured =>
      'Dla tego repozytorium nie skonfigurowano zdalnego.';
  @override
  String get jumpToDesk => 'Przejdź do Desku';
  @override
  String get arrowOpen => '→ otwórz';
  @override
  String get openOnANewDesk => 'Otwórz na nowym Desku';
  @override
  String get plusDesk => '+ Desk';
  @override
  String get plusSpace => '+ ';
  @override
  String get newBranchNameHint => 'nazwa-nowej-gałęzi';
  @override
  String get escLower => 'esc';
  @override
  String get plusNewDesk => '+ nowy Desk';
  @override
  String get fromHeadEllipsis => 'od HEAD...';
  @override
  String get viewAllBranches => 'Pokaż wszystkie gałęzie';
  @override
  String get issuesLower => 'zgłoszenia';
  @override
  String get newIssueLower => 'nowe zgłoszenie';
  @override
  String get noneLinked => 'brak powiązanych';
  @override
  String get noOpenIssues => 'brak otwartych zgłoszeń';
  @override
  String get createAndPushLower => 'utwórz + push';
  @override
  String get createLower => 'utwórz';
  @override
  String get remoteLower => 'zdalny';
  @override
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';
  @override
  String get promoteToRemote => 'Wypromuj do zdalnego';
  @override
  String get pushToRemote => 'Pushnij do zdalnego';
  @override
  String get pullFromRemote => 'Pullnij ze zdalnego';
  @override
  String get importLabel => 'Importuj';
  @override
  String get failedToCreateRepository => 'Nie udało się utworzyć repozytorium.';
  @override
  String get openRepositoryLower => 'otwórz repozytorium';
  @override
  String get newRepositoryLower => 'nowe repozytorium';
  @override
  String get back => 'Wstecz';
  @override
  String get openRepositoryDialogTitle => 'Otwórz repozytorium';
  @override
  String get createRepositoryDialogTitle => 'Utwórz repozytorium';
  @override
  String get cloneTargetDialogTitle => 'Cel klonowania';
  @override
  String get cloneToDialogTitle => 'Klonuj do';
  @override
  String get exportToDialogTitle => 'Eksportuj do';
  @override
  String get createFromTemplateInDialogTitle => 'Utwórz z szablonu w';
  @override
  String get notAGitRepoInitConfirm =>
      'To nie jest repozytorium git. Zainicjować je tutaj?';
  @override
  String get repositoryUrlRequired => 'Wymagany jest URL repozytorium.';
  @override
  String get failedToCloneRepository => 'Nie udało się sklonować repozytorium.';
  @override
  String cloningEllipsis({required Object name}) => 'Klonowanie ${name}...';
  @override
  String get cloneCancelled => 'Klonowanie anulowane.';
  @override
  String get noProjectsYet => 'Brak projektów';
  @override
  String get dissolveGroup => 'Rozwiąż grupę';
  @override
  String get projectsHeader => 'Projekty';
  @override
  String get cloneLabel => 'Klonuj';
  @override
  String get createLabel => 'Utwórz';
  @override
  String get openLabel => 'Otwórz';
  @override
  String get repositoryUrlPlaceholder => 'URL repozytorium';
  @override
  String get projectNameOrFullPathPlaceholder =>
      'nazwa-projektu lub pełna ścieżka';
  @override
  String get pathToProjectPlaceholder => '/ścieżka/do/projektu';
  @override
  String get cloneToFolderPathPlaceholder => 'Ścieżka folderu docelowego';
  @override
  String get switchToCreateRepo => 'Przełącz na tworzenie repo';
  @override
  String get explorer => 'Eksplorator';
  @override
  String get terminal => 'Terminal';
  @override
  String get cloneUrl => 'URL klonowania';
  @override
  String get copyPath => 'Kopiuj ścieżkę';
  @override
  String get export => 'Eksportuj';
  @override
  String get readme => 'README';
  @override
  String get duplicate => 'Duplikuj';
  @override
  String get template => 'Szablon';
  @override
  String get forgetThisProject => 'Zapomnij ten projekt';
  @override
  String get aiKindCommitMessage => 'wiadomość commita';
  @override
  String get aiKindReview => 'przegląd';
  @override
  String get aiKindMuse => 'muse';
  @override
  String get aiKindPresent => 'prezentacja';
  @override
  String get aiKindDebug => 'debugowanie';
  @override
  String aiStatusRunning({required Object kind}) => '${kind} w toku';
  @override
  String aiStatusFailedUnread({required Object kind}) =>
      '${kind} — błąd (nieprzeczytane)';
  @override
  String aiStatusReadyUnread({required Object kind}) =>
      '${kind} gotowe (nieprzeczytane)';
  @override
  String get filesLower => 'pliki';
  @override
  String get commitsLower => 'commity';
  @override
  String get undoLabel => 'Cofnij';
  @override
  String get goLabel => 'dalej';
  @override
  String countdownSeconds({required Object n}) => '${n} s';
  @override
  String get collapseGlyph => '▲ zwiń';
  @override
  String moreLinesGlyph({required Object n}) => '▼ jeszcze ${n} linii';
}

// Path: backend
class _Translations$backend$pl extends Translations$backend$en {
  _Translations$backend$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$backend$ops$pl ops = _Translations$backend$ops$pl._(
    _root,
  );
  @override
  late final _Translations$backend$mergeOutcome$pl mergeOutcome =
      _Translations$backend$mergeOutcome$pl._(_root);
}

// Path: branches
class _Translations$branches$pl extends Translations$branches$en {
  _Translations$branches$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get runningAiReview => 'Wykonuję przegląd AI…';
  @override
  String prNumberLabel({required Object number}) => 'PR #${number}';
  @override
  String get findings => 'ZNALEZISKA';
  @override
  String get observations => 'OBSERWACJE';
  @override
  String get renameEllipsis => 'Zmień nazwę…';
  @override
  String get publish => 'Opublikuj';
  @override
  String publishFailed({required Object error}) =>
      'Nie udało się opublikować: ${error}';
  @override
  String couldntOpenDesk({required Object error}) =>
      'Nie udało się otworzyć Desku: ${error}';
  @override
  String syncFailed({required Object error}) =>
      'Synchronizacja nie powiodła się: ${error}';
  @override
  String get renameBranchTitle => 'Zmień nazwę gałęzi';
  @override
  String get newNameHint => 'nowa nazwa';
  @override
  String get rename => 'Zmień nazwę';
  @override
  String invalidBranchName({required Object name}) =>
      '„${name}” nie jest prawidłową nazwą gałęzi.';
  @override
  String renameFailed({required Object error}) =>
      'Nie udało się zmienić nazwy: ${error}';
  @override
  String deletingBranch({required Object name}) => 'Usuwam ${name}';
  @override
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '„${name}” jest otwarta na Desku „${desk}”.';
  @override
  String get openDesk => 'Otwórz Desk';
  @override
  String openInDeskShort({required Object desk}) => 'otwórz na Desku „${desk}”';
  @override
  String get couldNotPinBranch =>
      'nie udało się przypiąć wierzchołka gałęzi; pominięto usunięcie';
  @override
  String get couldNotPinTag =>
      'nie udało się przypiąć tagu; pominięto usunięcie';
  @override
  String deletingTag({required Object name}) => 'Usuwam tag ${name}';
  @override
  String get applyToActiveChanges => 'Zastosuj do aktywnych zmian…';
  @override
  String get couldNotLoadPrDiff => 'Nie udało się załadować diff PR.';
  @override
  String prSourceLabel({required Object number, required Object title}) =>
      'PR #${number}: ${title}';
  @override
  String mergeIntoDesk({required Object branch}) => 'Merge do ${branch}…';
  @override
  String get checkoutThisPr => 'Checkout tego PR';
  @override
  String get mergeIntoNewDesk => 'Merge do nowego Desku…';
  @override
  String get pushToForge => 'Pushnij do forge';
  @override
  String get linkToIssue => 'Powiąż ze zgłoszeniem…';
  @override
  String get gitPatch => '↓ patch git';
  @override
  String get copyBranchName => 'Kopiuj nazwę gałęzi';
  @override
  String copiedRef({required Object ref}) => 'Skopiowano „${ref}”';
  @override
  String get reviewPr => 'Przejrzyj PR';
  @override
  String get openInBrowser => 'Otwórz w przeglądarce';
  @override
  String get markAsRead => 'Oznacz jako przeczytane';
  @override
  String get markAsUnread => 'Oznacz jako nieprzeczytane';
  @override
  String get replaceLocalCommitsTitle => 'Zastąpić lokalne commity?';
  @override
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref} zawiera lokalne commity, których nie ma w zdalnym wierzchołku PR. Aktualizacja zastąpi je najnowszą wersją ze zdalnego.';
  @override
  String get update => 'Zaktualizuj';
  @override
  String couldntFetchPr({required Object error}) =>
      'Nie udało się pobrać PR: ${error}';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Nie udało się otworzyć jako Desk: ${error}';
  @override
  String couldntOpenInBrowser({required Object error}) =>
      'Nie udało się otworzyć w przeglądarce: ${error}';
  @override
  String get noIssuesYetLocal =>
      'Brak zgłoszeń. Otwórz jedno w upstream lub użyj „+ nowe lokalne zgłoszenie” w soczewce zgłoszeń.';
  @override
  String get remotePrsLinkLocalOnly =>
      'Zdalne PR mogą być powiązane tylko z lokalnymi zgłoszeniami. Utwórz jedno przez „+ nowe lokalne zgłoszenie”.';
  @override
  String linkPrToIssues({required Object number}) =>
      'Powiąż PR #${number} ze zgłoszeniami';
  @override
  String get noPrsYetLocal =>
      'Brak PR. Otwórz jeden w upstream lub wypromuj Desk do PR.';
  @override
  String get remoteIssuesLinkLocalOnly =>
      'Zdalne zgłoszenia mogą być powiązane tylko z lokalnymi PR. Najpierw wypromuj Desk do PR.';
  @override
  String linkIssueToPrs({required Object number}) =>
      'Powiąż zgłoszenie #${number} z PR';
  @override
  String couldntToggleLink({required Object error}) =>
      'Nie udało się przełączyć powiązania: ${error}';
  @override
  String get openPatchDialogTitle => 'Otwórz patch (.patch / .diff)';
  @override
  String get clipboardNoText => 'Schowek nie zawiera tekstu.';
  @override
  String get clipboardPatchLabel => 'clipboard.patch';
  @override
  String failedToOpenPatch({required Object error}) =>
      'Nie udało się otworzyć patcha: ${error}';
  @override
  String get patchEmptyOrUnparseable =>
      'Patch jest pusty lub nie da się go sparsować.';
  @override
  String get prPushedToForge => 'PR pushnięty do forge.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      'Nadpisać ${ref} najnowszą wersją ze zdalnego?';
  @override
  String get overwrite => 'Nadpisz';
  @override
  String get loadingBranchesTitle => 'Ładowanie gałęzi';
  @override
  String get loadingBranchesMessage => 'Odczytuję lokalne gałęzie i tagi.';
  @override
  String get branchesUnavailableTitle => 'Gałęzie niedostępne';
  @override
  String get filterPullRequestsHint => 'filtruj pull requesty…';
  @override
  String get filterIssuesHint => 'filtruj zgłoszenia…';
  @override
  String get branchNameHint => 'nazwa gałęzi';
  @override
  String get tagsNewestFirst => 'tagi, najnowsze pierwsze';
  @override
  String get tagsOldestFirst => 'tagi, najstarsze pierwsze';
  @override
  String get flipSortDirection => 'odwróć kierunek sortowania';
  @override
  String get readingPullRequests => 'Odczytuję pull requesty…';
  @override
  String get noOpenPullRequests => 'Brak otwartych pull requestów';
  @override
  String get noPullRequestsHint => 'Otwórz z gałęzi lub wypromuj Desk.';
  @override
  String get noPrsMatchFilters => 'Żaden PR nie pasuje do tych filtrów';
  @override
  String get toggleFiltersRowAbove => 'Wyłącz filtry w wierszu powyżej.';
  @override
  String get issuesNewestFirst => 'zgłoszenia, najnowsze pierwsze';
  @override
  String get issuesOldestFirst => 'zgłoszenia, najstarsze pierwsze';
  @override
  String get issuesHeading => 'ZGŁOSZENIA';
  @override
  String get readingIssuesLower => 'odczytuję zgłoszenia…';
  @override
  String get noOpenIssues => 'Brak otwartych zgłoszeń';
  @override
  String get noIssuesHint => '+ nowe do śledzenia pracy i błędów.';
  @override
  String get nothingMatches => 'Nic nie pasuje';
  @override
  String get toggleFiltersAbove => 'Wyłącz filtry powyżej.';
  @override
  String get bucketFresh => 'ŚWIEŻE';
  @override
  String get bucketThisWeek => 'W TYM TYGODNIU';
  @override
  String get bucketStalled => 'UTKNĘŁO';
  @override
  String get bucketOlder => 'STARSZE';
  @override
  String get couldNotResolveMainWorktree =>
      'Nie udało się ustalić ścieżki głównego drzewa roboczego.';
  @override
  String couldntSubmitReview({required Object error}) =>
      'Nie udało się wysłać przeglądu: ${error}';
  @override
  String get reviewAiNotAvailable => 'Przegląd AI nie jest jeszcze dostępny.';
  @override
  String get noReviewModelConfigured =>
      'Nie skonfigurowano modelu do przeglądu.';
  @override
  String get deskFallback => 'Desk';
  @override
  String deskUncommittedChanges({
    required num n,
    required Object branch,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
    n,
    one:
        '${branch} ma ${n} niezacommitowaną zmianę — najpierw zacommituj lub zrób stash.',
    few:
        '${branch} ma ${n} niezacommitowane zmiany — najpierw zacommituj lub zrób stash.',
    many:
        '${branch} ma ${n} niezacommitowanych zmian — najpierw zacommituj lub zrób stash.',
    other:
        '${branch} ma ${n} niezacommitowanej zmiany — najpierw zacommituj lub zrób stash.',
  );
  @override
  String get targetDeskNoBranch => 'Docelowy Desk nie ma gałęzi.';
  @override
  String mergePrIntoDesk({required Object number, required Object branch}) =>
      'Merge PR #${number} do ${branch}';
  @override
  String get conflictCheckUnavailableVersion =>
      'Sprawdzanie konfliktów niedostępne — wymagany git 2.38+';
  @override
  String get conflictCheckUnavailable => 'Sprawdzanie konfliktów niedostępne';
  @override
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'BĘDZIE KONFLIKT · ${n} plik',
        few: 'BĘDZIE KONFLIKT · ${n} pliki',
        many: 'BĘDZIE KONFLIKT · ${n} plików',
        other: 'BĘDZIE KONFLIKT · ${n} pliku',
      );
  @override
  String plusMore({required Object n}) => '+${n} więcej';
  @override
  String get rebase => 'Rebase';
  @override
  String get squash => 'Squash';
  @override
  String get mergeCommit => 'Commit merge\'a';
  @override
  String noDeskForBranch({required Object branch}) =>
      'Nie znaleziono Desku dla gałęzi ${branch}';
  @override
  String get mergeAnyway => 'Merge mimo to';
  @override
  String get readingIssues => 'Odczytuję zgłoszenia…';
  @override
  String get openUpstreamOrLocal =>
      'Otwórz jedno w upstream lub otwórz lokalne.';
  @override
  String get noIssuesMatchFilters =>
      'Żadne zgłoszenie nie pasuje do tych filtrów';
  @override
  String couldntCreateIssue({required Object error}) =>
      'Nie udało się utworzyć zgłoszenia: ${error}';
  @override
  String get promoteToRemote => 'Wypromuj do zdalnego';
  @override
  String get pushToRemote => 'Pushnij do zdalnego';
  @override
  String get pullFromRemote => 'Pullnij ze zdalnego';
  @override
  String get import => 'Importuj';
  @override
  String get linkToPr => 'Powiąż z PR…';
  @override
  String get abandon => 'Porzuć';
  @override
  String get issuePromotedToRemote => 'Zgłoszenie wypromowane do zdalnego.';
  @override
  String get issuePushedToRemote => 'Pushnięto do zdalnego.';
  @override
  String get issuePulledFromRemote => 'Pullnięto ze zdalnego.';
  @override
  String issueImportedLocally({required Object number}) =>
      'Zaimportowano #${number} lokalnie.';
  @override
  String get abandonIssueTitle => 'Porzuć zgłoszenie';
  @override
  String abandonIssueMessage({required Object id}) =>
      'Trwale usunąć lokalne zgłoszenie #${id}? Usunie to jego ref i nie da się cofnąć.';
  @override
  String couldntAbandon({required Object error}) =>
      'Nie udało się porzucić: ${error}';
  @override
  String couldntPostComment({required Object error}) =>
      'Nie udało się dodać komentarza: ${error}';
  @override
  String couldntCloseIssue({required Object error}) =>
      'Nie udało się zamknąć zgłoszenia: ${error}';
  @override
  String couldntAddLabel({required Object error}) =>
      'Nie udało się dodać etykiety: ${error}';
  @override
  String get lensBranches => 'GAŁĘZIE';
  @override
  String get lensPrs => 'PR';
  @override
  String get patchUp => '↑ patch';
  @override
  String get syncRibbon => '⇅ synchr';
  @override
  String get kbHeading => 'KLAWIATURA';
  @override
  String get kbNavigateRows => 'nawigacja po wierszach';
  @override
  String get kbExpandCollapse => 'rozwiń / zwiń wiersz w fokusie';
  @override
  String get kbCheckoutPr => 'checkout PR w fokusie lokalnie';
  @override
  String get kbApproveReview => 'zatwierdź · przegląd';
  @override
  String get kbRequestChanges => 'poproś o zmiany';
  @override
  String get kbFocusSearch => 'fokus na wyszukiwanie';
  @override
  String get kbSwitchLens => 'przełącz soczewkę (gałęzie · pr)';
  @override
  String get kbToggleOverlay => 'przełącz tę nakładkę';
  @override
  String get kbPressToDismiss => 'kliknij gdziekolwiek, aby zamknąć';
  @override
  String get overrideScarTooltip =>
      'zmergowane z nieudanymi sprawdzeniami lub bez zatwierdzającego przeglądu — najpierw rozpracuj to pod ostrzałem';
  @override
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} plik pokrywa się z twoją niezacommitowaną pracą',
        few: '${n} pliki pokrywają się z twoją niezacommitowaną pracą',
        many: '${n} plików pokrywa się z twoją niezacommitowaną pracą',
        other: '${n} pliku pokrywa się z twoją niezacommitowaną pracą',
      );
  @override
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '#${pr}  (${n} plik)',
        few: '#${pr}  (${n} pliki)',
        many: '#${pr}  (${n} plików)',
        other: '#${pr}  (${n} pliku)',
      );
  @override
  String get prStateDraft => 'SZKIC';
  @override
  String get localBadge => 'LOKALNE';
  @override
  String get myReviewPending => 'twój przegląd oczekuje';
  @override
  String get myReviewApproved => 'ty ✓';
  @override
  String get myReviewChangesRequested => 'ty ✗ poproszono o zmiany';
  @override
  String get myReviewCommented => 'skomentowałeś';
  @override
  String get myReviewDefault => 'ty';
  @override
  String tailCommentsAuthor({required Object count}) =>
      '${count} komentarzy · pokazano ostatni od autora';
  @override
  String get tailLastComment => 'ostatni komentarz';
  @override
  String tailLastReviewState({required Object state}) =>
      'ostatni przegląd · ${state}';
  @override
  String get tailLastReview => 'ostatni przegląd';
  @override
  String tailLastCheckState({required Object state}) =>
      'ostatnie sprawdzenie · ${state}';
  @override
  String get tailLastCommit => 'ostatni commit';
  @override
  String get tailLastActivity => 'ostatnia aktywność';
  @override
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'zamyka ${n} zgłoszenie — kliknij, aby przejść',
        few: 'zamyka ${n} zgłoszenia — kliknij, aby przejść',
        many: 'zamyka ${n} zgłoszeń — kliknij, aby przejść',
        other: 'zamyka ${n} zgłoszenia — kliknij, aby przejść',
      );
  @override
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'rozwiązywane przez ${n} PR — kliknij, aby przejść',
        few: 'rozwiązywane przez ${n} PR — kliknij, aby przejść',
        many: 'rozwiązywane przez ${n} PR — kliknij, aby przejść',
        other: 'rozwiązywane przez ${n} PR — kliknij, aby przejść',
      );
  @override
  String get checksLabel => 'sprawdzenia';
  @override
  String get reviewersLabel => 'recenzenci';
  @override
  String get conflictsLabel => 'konflikty';
  @override
  String exportFailed({required Object error}) =>
      'Eksport nie powiódł się: ${error}';
  @override
  String get readingFiles => 'odczytuję pliki…';
  @override
  String get noDetailAvailable => 'brak szczegółów';
  @override
  String get noFilesReported => 'nie zgłoszono plików';
  @override
  String get readingGitHistory => 'odczytuję historię git…';
  @override
  String get knowsThisCode => 'zna ten kod';
  @override
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} commit na tych plikach w ostatnim roku',
        few: '${n} commity na tych plikach w ostatnim roku',
        many: '${n} commitów na tych plikach w ostatnim roku',
        other: '${n} commita na tych plikach w ostatnim roku',
      );
  @override
  String get willFight => 'BĘDZIE WALKA';
  @override
  String orbitalPartnerCos({required Object cos}) =>
      'partner orbitalny — cos ${cos}';
  @override
  String get orbitLabel => 'orbita';
  @override
  String get touchesYourLocalWork => 'DOTYKA TWOJEJ LOKALNEJ PRACY';
  @override
  String get mergingWillConflict =>
      'merge prawdopodobnie skonfliktuje z twoimi niezacommitowanymi zmianami';
  @override
  String get closesHeading => 'ZAMYKA';
  @override
  String get filesHeading => 'PLIKI';
  @override
  String get orientAligned => 'wyrównany';
  @override
  String get orientAdjacent => 'przyległy';
  @override
  String get orientOrthogonal => 'ortogonalny';
  @override
  String shapeField({required Object v}) => 'pole ${v}';
  @override
  String shapeSource({required Object v}) => 'źródło ${v}';
  @override
  String shapeSrcDelta({required Object v}) => 'srcΔ ${v}';
  @override
  String shapeFldDelta({required Object v}) => 'fldΔ ${v}';
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
  String shapeStress({required Object v}) => 'naprężenie ${v}';
  @override
  String shapeWit({required Object v}) => 'wit ${v}';
  @override
  String resonanceReadout({required Object v}) => 'rezonans ${v}';
  @override
  String ghostFileTooltip({required Object path}) =>
      'zwykle porusza się z plikami tego PR\n(${path})';
  @override
  String get prStateDraftLower => 'szkic';
  @override
  String get keystoneTooltip =>
      'zwornik — plik-most na poziomie całego repozytorium';
  @override
  String get reviewNoteHint => 'zostaw notatkę (opcjonalnie)…';
  @override
  String get reviewComment => 'komentarz';
  @override
  String get reviewRequestChanges => 'poproś o zmiany';
  @override
  String get reviewApprove => '✓ zatwierdź';
  @override
  String get actionPatchDown => '↓ patch';
  @override
  String get actionPrReview => '✦ przegląd pr';
  @override
  String get actionOpenAsDesk => '⊞ otwórz jako Desk';
  @override
  String get actionCheckout => '[c] checkout';
  @override
  String get actionMerge => '[m] merge ▾';
  @override
  String get mergeMenuMergeCommit => 'commit merge\'a';
  @override
  String get mergeMenuSquash => 'squash i merge';
  @override
  String get mergeMenuRebase => 'rebase i merge';
  @override
  String get deleteBranchAfter => 'usuń gałąź po';
  @override
  String checkDurationSec({required Object n}) => '${n} s';
  @override
  String checkDurationMin({required Object m, required Object s}) =>
      '${m} m ${s} s';
  @override
  String assignedTo({required Object names}) => 'przypisano: ${names}';
  @override
  String issueConvLine({required Object n, required Object time}) =>
      '${n} rozm · ${time}';
  @override
  String get readingThread => 'odczytuję wątek…';
  @override
  String get addressedByHeading => 'ROZWIĄZYWANE PRZEZ';
  @override
  String get descriptionHeading => 'OPIS';
  @override
  String get threadHeading => 'WĄTEK';
  @override
  String get replyHint => 'odpowiedz…';
  @override
  String get assignMe => 'przypisz mnie';
  @override
  String get closeLower => 'zamknij';
  @override
  String get postReply => '↩ wyślij';
  @override
  String get remoteProviderUnavailable => 'Zdalny dostawca niedostępny';
  @override
  String get noRecognisedRemoteHost =>
      'Brak rozpoznanego zdalnego hosta dla tego repozytorium.';
  @override
  String get corpseGone => 'znikła';
  @override
  String get corpseAbsorbed => 'wchłonięta';
  @override
  String get corpseSquashed => 'zesquashowana';
  @override
  String absorbedDeliveredIn({required Object hash}) => 'dostarczono w ${hash}';
  @override
  String get absorbedNoChanges => 'merge nie dodaje zmian';
  @override
  String get corpseTagUpstreamGone => 'upstream znikł';
  @override
  String corpseTagAbsorbed({required Object receipt}) =>
      'wchłonięta, ${receipt}';
  @override
  String get corpseTagSquashed => 'zesquashowana i zmergowana';
  @override
  String semanticsCurrentBranch({required Object name}) =>
      '${name}, bieżąca gałąź';
  @override
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}, śledzi ${upstream}';
  @override
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}, ${tag}';
  @override
  String semanticsWorktreeOpen({required Object label}) =>
      '${label}, drzewo robocze otwarte';
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
  String get crossLinkPrDraft => 'PR · szkic';
  @override
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} zgłoszenie',
        few: '${n} zgłoszenia',
        many: '${n} zgłoszeń',
        other: '${n} zgłoszenia',
      );
  @override
  String get headBadge => 'HEAD';
  @override
  String trackingLine({required Object upstream}) => '→ śledzenie: ${upstream}';
  @override
  String get checkoutButton => 'Checkout';
  @override
  String get createBranch => 'Utwórz gałąź';
  @override
  String get newBranchName => 'Nazwa nowej gałęzi';
  @override
  String newBranchNameError({required Object error}) =>
      'Nazwa nowej gałęzi — ${error}';
  @override
  String get forceDelete => 'Wymusić?';
  @override
  String get annotated => 'adnotowany';
  @override
  String get applyCheckFailed => 'apply --check nie przeszedł';
  @override
  String get openPatchFrom => 'OTWÓRZ PATCH Z';
  @override
  String get patchFromFile => 'z pliku…';
  @override
  String get patchFromFileHint => '.patch / .diff';
  @override
  String get patchFromClipboard => 'ze schowka';
  @override
  String get patchFromClipboardHint => 'wklej tekst';
  @override
  String get patchPreviewHeading => 'PODGLĄD PATCHA';
  @override
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';
  @override
  String get stagedDone => 'dodano do indeksu.';
  @override
  String get appliedDone => 'zastosowano.';
  @override
  String get opening => 'otwieram…';
  @override
  String get mergeEditor => '⇋ edytor merge\'a';
  @override
  String get staging => 'indeksowanie…';
  @override
  String get applying => 'stosuję…';
  @override
  String get stage => 'do indeksu';
  @override
  String get apply => 'zastosuj';
  @override
  String get refineHint => 'doprecyzuj… (np. „usuń też zmiany w loggerze”)';
  @override
  String get reverseArmedTooltip =>
      'uzbrojone — następne zastosowanie COFNIE patch (-R)';
  @override
  String get reverseDisarmedTooltip =>
      'uzbrój reverse (-R) — cofnij zamiast zastosować';
  @override
  String get reverseArmedLabel => '⟲ reverse ✓';
  @override
  String get reverseLabel => '⟲ reverse';
  @override
  String get untouchedHeading => '⚠ NIETKNIĘTE';
  @override
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${count} z ${n} pliku nie ma w patchu',
        few: '${count} z ${n} plików nie ma w patchu',
        many: '${count} z ${n} plików nie ma w patchu',
        other: '${count} z ${n} pliku nie ma w patchu',
      );
  @override
  String get staysConflicted =>
      'te pliki pozostaną w konflikcie — zastosowanie nie doda ich do indeksu';
  @override
  String get orWith => 'LUB Z';
  @override
  String get noAiModelConfigured => 'nie skonfigurowano modelu AI';
  @override
  String applyWithPatchFrom({required Object label}) =>
      'zastosuj z patchem od ${label}';
  @override
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => 'zastosuj z patchem od ${label}  ·  ${model}';
  @override
  String get patching => 'patchuję…';
  @override
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  zastosuj z patchem od ${label}';
  @override
  String get orWithAnotherModel => 'lub z innym modelem';
  @override
  String get applyCheckPassed =>
      'git apply --check przeszedł — patch zastosuje się czysto';
  @override
  String get gitApplyCheckFailed => 'git apply --check nie przeszedł';
  @override
  String get appliesClean => 'stosuje się czysto';
  @override
  String get willNotApply => 'nie zastosuje się';
  @override
  String get newLocalIssue => 'nowe lokalne zgłoszenie';
  @override
  String get filterHint => 'filtruj…';
  @override
  String get nothingToLink => 'Na razie nie ma czego wiązać.';
  @override
  String get nothingMatchesDot => 'Nic nie pasuje.';
  @override
  String get relevantHeading => 'ISTOTNE';
  @override
  String get allHeading => 'WSZYSTKO';
  @override
  String get doneLower => 'gotowe';
  @override
  String get candidateRemote => 'R';
  @override
  String get candidateLocal => 'L';
  @override
  String get newLocalIssueTitle => 'Nowe lokalne zgłoszenie';
  @override
  String get titleHint => 'tytuł';
  @override
  String get bodyHint => 'treść (markdown)';
  @override
  String get cancelLower => 'anuluj';
  @override
  String get createLower => 'utwórz';
  @override
  String get deleteFailed => 'nie udało się usunąć';
  @override
  String reviewFailed({required Object error}) =>
      'Przegląd nie powiódł się: ${error}';
  @override
  String get resolutionFailed => 'nie udało się rozwiązać';
  @override
  String get patchBlocksNoCover =>
      'model zwrócił bloki patcha, które nie pokrywają problematycznych plików';
  @override
  String get applyFailed => 'nie udało się zastosować';
  @override
  String get emptyOrUnparseablePatch =>
      'model zwrócił pusty lub niemożliwy do sparsowania patch';
  @override
  String noModelConfiguredFor({required Object label}) =>
      'brak skonfigurowanego modelu dla „${label}”';
  @override
  String get checksHeading => 'KONTROLE';
  @override
  String get peopleHeading => 'OSOBY';
  @override
  String get conversationHeading => 'ROZMOWA';
}

// Path: changes
class _Translations$changes$pl extends Translations$changes$en {
  _Translations$changes$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$usage$pl usage =
      _Translations$changes$usage$pl._(_root);
  @override
  late final _Translations$changes$tabs$pl tabs =
      _Translations$changes$tabs$pl._(_root);
  @override
  late final _Translations$changes$tabStrip$pl tabStrip =
      _Translations$changes$tabStrip$pl._(_root);
  @override
  late final _Translations$changes$select$pl select =
      _Translations$changes$select$pl._(_root);
  @override
  late final _Translations$changes$constellationToggle$pl constellationToggle =
      _Translations$changes$constellationToggle$pl._(_root);
  @override
  late final _Translations$changes$nudgeChip$pl nudgeChip =
      _Translations$changes$nudgeChip$pl._(_root);
  @override
  late final _Translations$changes$minimap$pl minimap =
      _Translations$changes$minimap$pl._(_root);
  @override
  late final _Translations$changes$tagInput$pl tagInput =
      _Translations$changes$tagInput$pl._(_root);
  @override
  late final _Translations$changes$composer$pl composer =
      _Translations$changes$composer$pl._(_root);
  @override
  late final _Translations$changes$commit$pl commit =
      _Translations$changes$commit$pl._(_root);
  @override
  late final _Translations$changes$rebase$pl rebase =
      _Translations$changes$rebase$pl._(_root);
  @override
  late final _Translations$changes$editor$pl editor =
      _Translations$changes$editor$pl._(_root);
  @override
  late final _Translations$changes$editorTitles$pl editorTitles =
      _Translations$changes$editorTitles$pl._(_root);
  @override
  late final _Translations$changes$askHint$pl askHint =
      _Translations$changes$askHint$pl._(_root);
  @override
  late final _Translations$changes$fileMenu$pl fileMenu =
      _Translations$changes$fileMenu$pl._(_root);
  @override
  late final _Translations$changes$multiFileMenu$pl multiFileMenu =
      _Translations$changes$multiFileMenu$pl._(_root);
  @override
  late final _Translations$changes$ignoreMenu$pl ignoreMenu =
      _Translations$changes$ignoreMenu$pl._(_root);
  @override
  late final _Translations$changes$discard$pl discard =
      _Translations$changes$discard$pl._(_root);
  @override
  late final _Translations$changes$snack$pl snack =
      _Translations$changes$snack$pl._(_root);
  @override
  late final _Translations$changes$trace$pl trace =
      _Translations$changes$trace$pl._(_root);
  @override
  late final _Translations$changes$cleanTree$pl cleanTree =
      _Translations$changes$cleanTree$pl._(_root);
  @override
  late final _Translations$changes$guardrail$pl guardrail =
      _Translations$changes$guardrail$pl._(_root);
  @override
  late final _Translations$changes$dropHint$pl dropHint =
      _Translations$changes$dropHint$pl._(_root);
  @override
  late final _Translations$changes$diffEmpty$pl diffEmpty =
      _Translations$changes$diffEmpty$pl._(_root);
  @override
  late final _Translations$changes$shelvePill$pl shelvePill =
      _Translations$changes$shelvePill$pl._(_root);
  @override
  late final _Translations$changes$stashAction$pl stashAction =
      _Translations$changes$stashAction$pl._(_root);
  @override
  late final _Translations$changes$stashContents$pl stashContents =
      _Translations$changes$stashContents$pl._(_root);
  @override
  late final _Translations$changes$stashFile$pl stashFile =
      _Translations$changes$stashFile$pl._(_root);
  @override
  late final _Translations$changes$fileRow$pl fileRow =
      _Translations$changes$fileRow$pl._(_root);
  @override
  late final _Translations$changes$resolveStrip$pl resolveStrip =
      _Translations$changes$resolveStrip$pl._(_root);
  @override
  late final _Translations$changes$badge$pl badge =
      _Translations$changes$badge$pl._(_root);
  @override
  late final _Translations$changes$review$pl review =
      _Translations$changes$review$pl._(_root);
  @override
  late final _Translations$changes$commitBtn$pl commitBtn =
      _Translations$changes$commitBtn$pl._(_root);
  @override
  late final _Translations$changes$shapeBtn$pl shapeBtn =
      _Translations$changes$shapeBtn$pl._(_root);
  @override
  late final _Translations$changes$dejaVu$pl dejaVu =
      _Translations$changes$dejaVu$pl._(_root);
  @override
  late final _Translations$changes$identity$pl identity =
      _Translations$changes$identity$pl._(_root);
  @override
  late final _Translations$changes$staleScope$pl staleScope =
      _Translations$changes$staleScope$pl._(_root);
  @override
  late final _Translations$changes$finding$pl finding =
      _Translations$changes$finding$pl._(_root);
  @override
  late final _Translations$changes$muse$pl muse =
      _Translations$changes$muse$pl._(_root);
  @override
  late final _Translations$changes$debug$pl debug =
      _Translations$changes$debug$pl._(_root);
  @override
  late final _Translations$changes$includeSummary$pl includeSummary =
      _Translations$changes$includeSummary$pl._(_root);
  @override
  late final _Translations$changes$status$pl status =
      _Translations$changes$status$pl._(_root);
  @override
  late final _Translations$changes$stash$pl stash =
      _Translations$changes$stash$pl._(_root);
  @override
  late final _Translations$changes$tooltips$pl tooltips =
      _Translations$changes$tooltips$pl._(_root);
  @override
  late final _Translations$changes$mergeEditor$pl mergeEditor =
      _Translations$changes$mergeEditor$pl._(_root);
  @override
  late final _Translations$changes$conflictResolution$pl conflictResolution =
      _Translations$changes$conflictResolution$pl._(_root);
  @override
  late final _Translations$changes$mergeFlow$pl mergeFlow =
      _Translations$changes$mergeFlow$pl._(_root);
  @override
  late final _Translations$changes$constellation$pl constellation =
      _Translations$changes$constellation$pl._(_root);
}

// Path: common
class _Translations$common$pl extends Translations$common$en {
  _Translations$common$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get listSeparator => ', ';
  @override
  String get cancel => 'Anuluj';
  @override
  String get close => 'Zamknij';
  @override
  String get save => 'Zapisz';
  @override
  String get delete => 'Usuń';
  @override
  String get retry => 'Ponów';
  @override
  String get copy => 'Kopiuj';
  @override
  String get copied => 'Skopiowano';
  @override
  String get done => 'Gotowe';
  @override
  String get loading => 'Ładowanie…';
  @override
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} plik',
        few: '${n} pliki',
        many: '${n} plików',
        other: '${n} pliku',
      );
  @override
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} commit',
        few: '${n} commity',
        many: '${n} commitów',
        other: '${n} commita',
      );
  @override
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} gałąź',
        few: '${n} gałęzie',
        many: '${n} gałęzi',
        other: '${n} gałęzi',
      );
  @override
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} lokalny commit',
        few: '${n} lokalne commity',
        many: '${n} lokalnych commitów',
        other: '${n} lokalnego commita',
      );
  @override
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} zdalny commit',
        few: '${n} zdalne commity',
        many: '${n} zdalnych commitów',
        other: '${n} zdalnego commita',
      );
  @override
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} plik z konfliktem',
        few: '${n} pliki z konfliktami',
        many: '${n} plików z konfliktami',
        other: '${n} pliku z konfliktami',
      );
  @override
  late final _Translations$common$time$pl time = _Translations$common$time$pl._(
    _root,
  );
  @override
  late final _Translations$common$size$pl size = _Translations$common$size$pl._(
    _root,
  );
}

// Path: diff
class _Translations$diff$pl extends Translations$diff$en {
  _Translations$diff$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$diff$status$pl status =
      _Translations$diff$status$pl._(_root);
  @override
  late final _Translations$diff$toolbar$pl toolbar =
      _Translations$diff$toolbar$pl._(_root);
  @override
  late final _Translations$diff$hunkDropdown$pl hunkDropdown =
      _Translations$diff$hunkDropdown$pl._(_root);
  @override
  String stagingFailed({required Object error}) =>
      'Częściowe dodanie do indeksu nie powiodło się: ${error}';
  @override
  late final _Translations$diff$trail$pl trail = _Translations$diff$trail$pl._(
    _root,
  );
  @override
  late final _Translations$diff$pinned$pl pinned =
      _Translations$diff$pinned$pl._(_root);
  @override
  late final _Translations$diff$hunkHint$pl hunkHint =
      _Translations$diff$hunkHint$pl._(_root);
  @override
  late final _Translations$diff$binary$pl binary =
      _Translations$diff$binary$pl._(_root);
  @override
  late final _Translations$diff$media$pl media = _Translations$diff$media$pl._(
    _root,
  );
}

// Path: filament
class _Translations$filament$pl extends Translations$filament$en {
  _Translations$filament$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get noRepositoryOpen => 'Brak otwartego repozytorium.';
  @override
  String scanningProgress({required Object scanned, required Object total}) =>
      'skanowanie ${scanned} / ${total} plików…';
  @override
  String findingsAcrossFiles({required Object count, required Object files}) =>
      '${count} znalezisk w ${files} plikach';
  @override
  String copiedFindings({required Object count}) =>
      'Skopiowano znaleziska: ${count}';
  @override
  String get copy => 'KOPIUJ';
  @override
  String get noFindings => 'Brak znalezisk w przepływie wykonania.';
  @override
  late final _Translations$filament$severity$pl severity =
      _Translations$filament$severity$pl._(_root);
  @override
  late final _Translations$filament$kind$pl kind =
      _Translations$filament$kind$pl._(_root);
  @override
  String lineLabel({required Object line}) => 'w${line}';
  @override
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class _Translations$history$pl extends Translations$history$en {
  _Translations$history$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$pl commitLede =
      _Translations$history$commitLede$pl._(_root);
  @override
  late final _Translations$history$seismograph$pl seismograph =
      _Translations$history$seismograph$pl._(_root);
  @override
  late final _Translations$history$worldline$pl worldline =
      _Translations$history$worldline$pl._(_root);
  @override
  late final _Translations$history$contextMenu$pl contextMenu =
      _Translations$history$contextMenu$pl._(_root);
  @override
  late final _Translations$history$cherryPick$pl cherryPick =
      _Translations$history$cherryPick$pl._(_root);
  @override
  late final _Translations$history$revert$pl revert =
      _Translations$history$revert$pl._(_root);
  @override
  late final _Translations$history$reflog$pl reflog =
      _Translations$history$reflog$pl._(_root);
  @override
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'Ten commit jest głębszy niż ${n} załadowany commit.',
        few: 'Ten commit jest głębszy niż ${n} załadowane commity.',
        many: 'Ten commit jest głębszy niż ${n} załadowanych commitów.',
        other: 'Ten commit jest głębszy niż ${n} załadowanego commita.',
      );
  @override
  String deleteTagFailed({required Object error}) =>
      'Nie udało się usunąć tagu: ${error}';
  @override
  String get loadingTitle => 'Ładowanie historii';
  @override
  String get loadingMessage => 'Odczytuję ostatnie commity.';
  @override
  String get unavailableTitle => 'Historia niedostępna';
  @override
  String get toggleWorldline => 'Przełącz linię świata';
  @override
  String get pageTitle => 'Historia';
  @override
  String get viewingLast => 'Widok ostatnich';
  @override
  String get commitsUnit => 'commitów';
  @override
  String get noCommitSelectedTitle => 'Nie wybrano commita';
  @override
  String get noCommitSelectedMessage =>
      'Wybierz commit, aby zbadać jego zmiany.';
  @override
  String get loadingCommitTitle => 'Ładowanie commita';
  @override
  String get loadingCommitMessage => 'Odczytuję szczegóły commita.';
  @override
  String get commitUnavailableTitle => 'Commit niedostępny';
  @override
  String get couldNotLoadCommit => 'Nie udało się załadować commita.';
  @override
  String get reflogDividerLabel => 'reflog';
  @override
  String get loadReflog => 'Załaduj reflog';
  @override
  String get createTag => 'Utwórz tag';
  @override
  String get newTagName => 'Nazwa nowego tagu';
  @override
  String newTagNameError({required Object error}) =>
      'Nazwa nowego tagu — ${error}';
  @override
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} plik · wszystkie zmiany',
        few: '${n} pliki · wszystkie zmiany',
        many: '${n} plików · wszystkie zmiany',
        other: '${n} pliku · wszystkie zmiany',
      );
  @override
  String get allChangesLabel => 'wszystkie zmiany';
  @override
  late final _Translations$history$rebase$pl rebase =
      _Translations$history$rebase$pl._(_root);
  @override
  late final _Translations$history$inFlight$pl inFlight =
      _Translations$history$inFlight$pl._(_root);
}

// Path: historySurgery
class _Translations$historySurgery$pl extends Translations$historySurgery$en {
  _Translations$historySurgery$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$historySurgery$chrome$pl chrome =
      _Translations$historySurgery$chrome$pl._(_root);
  @override
  late final _Translations$historySurgery$select$pl select =
      _Translations$historySurgery$select$pl._(_root);
  @override
  late final _Translations$historySurgery$understand$pl understand =
      _Translations$historySurgery$understand$pl._(_root);
  @override
  late final _Translations$historySurgery$confirm$pl confirm =
      _Translations$historySurgery$confirm$pl._(_root);
  @override
  late final _Translations$historySurgery$execute$pl execute =
      _Translations$historySurgery$execute$pl._(_root);
  @override
  late final _Translations$historySurgery$verify$pl verify =
      _Translations$historySurgery$verify$pl._(_root);
  @override
  late final _Translations$historySurgery$forcePush$pl forcePush =
      _Translations$historySurgery$forcePush$pl._(_root);
}

// Path: onboarding
class _Translations$onboarding$pl extends Translations$onboarding$en {
  _Translations$onboarding$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$nav$pl nav =
      _Translations$onboarding$nav$pl._(_root);
  @override
  late final _Translations$onboarding$naming$pl naming =
      _Translations$onboarding$naming$pl._(_root);
  @override
  late final _Translations$onboarding$theme$pl theme =
      _Translations$onboarding$theme$pl._(_root);
  @override
  late final _Translations$onboarding$repo$pl repo =
      _Translations$onboarding$repo$pl._(_root);
  @override
  late final _Translations$onboarding$preview$pl preview =
      _Translations$onboarding$preview$pl._(_root);
}

// Path: orrery
class _Translations$orrery$pl extends Translations$orrery$en {
  _Translations$orrery$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$orrery$header$pl header =
      _Translations$orrery$header$pl._(_root);
  @override
  late final _Translations$orrery$status$pl status =
      _Translations$orrery$status$pl._(_root);
  @override
  late final _Translations$orrery$legend$pl legend =
      _Translations$orrery$legend$pl._(_root);
  @override
  late final _Translations$orrery$node$pl node = _Translations$orrery$node$pl._(
    _root,
  );
  @override
  late final _Translations$orrery$milestone$pl milestone =
      _Translations$orrery$milestone$pl._(_root);
  @override
  late final _Translations$orrery$structure$pl structure =
      _Translations$orrery$structure$pl._(_root);
  @override
  late final _Translations$orrery$rail$pl rail = _Translations$orrery$rail$pl._(
    _root,
  );
  @override
  late final _Translations$orrery$selection$pl selection =
      _Translations$orrery$selection$pl._(_root);
  @override
  late final _Translations$orrery$findingKind$pl findingKind =
      _Translations$orrery$findingKind$pl._(_root);
  @override
  late final _Translations$orrery$findings$pl findings =
      _Translations$orrery$findings$pl._(_root);
  @override
  late final _Translations$orrery$anchor$pl anchor =
      _Translations$orrery$anchor$pl._(_root);
  @override
  late final _Translations$orrery$compare$pl compare =
      _Translations$orrery$compare$pl._(_root);
}

// Path: palette
class _Translations$palette$pl extends Translations$palette$en {
  _Translations$palette$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get active => 'aktywne';
  @override
  late final _Translations$palette$prefixes$pl prefixes =
      _Translations$palette$prefixes$pl._(_root);
  @override
  late final _Translations$palette$chips$pl chips =
      _Translations$palette$chips$pl._(_root);
  @override
  late final _Translations$palette$predictive$pl predictive =
      _Translations$palette$predictive$pl._(_root);
  @override
  late final _Translations$palette$topTouched$pl topTouched =
      _Translations$palette$topTouched$pl._(_root);
  @override
  late final _Translations$palette$coherence$pl coherence =
      _Translations$palette$coherence$pl._(_root);
  @override
  late final _Translations$palette$keystone$pl keystone =
      _Translations$palette$keystone$pl._(_root);
  @override
  late final _Translations$palette$repoSub$pl repoSub =
      _Translations$palette$repoSub$pl._(_root);
  @override
  late final _Translations$palette$desks$pl desks =
      _Translations$palette$desks$pl._(_root);
  @override
  late final _Translations$palette$actions$pl actions =
      _Translations$palette$actions$pl._(_root);
  @override
  late final _Translations$palette$tools$pl tools =
      _Translations$palette$tools$pl._(_root);
  @override
  late final _Translations$palette$gitCommands$pl gitCommands =
      _Translations$palette$gitCommands$pl._(_root);
  @override
  late final _Translations$palette$pr$pl pr = _Translations$palette$pr$pl._(
    _root,
  );
  @override
  late final _Translations$palette$ai$pl ai = _Translations$palette$ai$pl._(
    _root,
  );
  @override
  late final _Translations$palette$undo$pl undo =
      _Translations$palette$undo$pl._(_root);
  @override
  late final _Translations$palette$navigation$pl navigation =
      _Translations$palette$navigation$pl._(_root);
  @override
  late final _Translations$palette$settings$pl settings =
      _Translations$palette$settings$pl._(_root);
  @override
  late final _Translations$palette$info$pl info =
      _Translations$palette$info$pl._(_root);
  @override
  late final _Translations$palette$debug$pl debug =
      _Translations$palette$debug$pl._(_root);
  @override
  late final _Translations$palette$dev$pl dev = _Translations$palette$dev$pl._(
    _root,
  );
  @override
  late final _Translations$palette$historySurgery$pl historySurgery =
      _Translations$palette$historySurgery$pl._(_root);
  @override
  late final _Translations$palette$orrery$pl orrery =
      _Translations$palette$orrery$pl._(_root);
  @override
  late final _Translations$palette$command$pl command =
      _Translations$palette$command$pl._(_root);
  @override
  late final _Translations$palette$search$pl search =
      _Translations$palette$search$pl._(_root);
  @override
  late final _Translations$palette$wick$pl wick =
      _Translations$palette$wick$pl._(_root);
  @override
  late final _Translations$palette$gitCache$pl gitCache =
      _Translations$palette$gitCache$pl._(_root);
}

// Path: releaseNotes
class _Translations$releaseNotes$pl extends Translations$releaseNotes$en {
  _Translations$releaseNotes$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get versionFallback => 'dev';
  @override
  late final _Translations$releaseNotes$about$pl about =
      _Translations$releaseNotes$about$pl._(_root);
  @override
  late final _Translations$releaseNotes$legal$pl legal =
      _Translations$releaseNotes$legal$pl._(_root);
}

// Path: repoSummary
class _Translations$repoSummary$pl extends Translations$repoSummary$en {
  _Translations$repoSummary$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$repoSummary$backbone$pl backbone =
      _Translations$repoSummary$backbone$pl._(_root);
  @override
  late final _Translations$repoSummary$glance$pl glance =
      _Translations$repoSummary$glance$pl._(_root);
  @override
  late final _Translations$repoSummary$heading$pl heading =
      _Translations$repoSummary$heading$pl._(_root);
  @override
  String get historyStarvedCaveat =>
      'Ranking jest ograniczony: graf sprzężeń nie miał krawędzi (świeży klon lub zbyt mało commitów). Kolejność plików odzwierciedla rozmiar, a nie centralność strukturalną.';
  @override
  late final _Translations$repoSummary$pitch$pl pitch =
      _Translations$repoSummary$pitch$pl._(_root);
  @override
  late final _Translations$repoSummary$region$pl region =
      _Translations$repoSummary$region$pl._(_root);
  @override
  late final _Translations$repoSummary$shape$pl shape =
      _Translations$repoSummary$shape$pl._(_root);
}

// Path: review
class _Translations$review$pl extends Translations$review$en {
  _Translations$review$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get unresolved => 'nierozwiązane';
  @override
  String get done => 'gotowe';
  @override
  String get ack => 'przyjęte';
  @override
  String get reply => 'odpowiedz';
  @override
  String get pleaseFix => 'do poprawy';
  @override
  String get draft => 'szkic';
  @override
  String get engine => 'silnik';
  @override
  String get moved => 'przeniesione';
  @override
  String get yourTurn => 'twoja kolej';
  @override
  String get drafts => 'szkice';
  @override
  String get publish => 'opublikuj';
  @override
  String get discard => 'odrzuć';
  @override
  String get saveDraft => 'zapisz szkic';
  @override
  String get cancel => 'anuluj';
  @override
  String get verdictApprove => 'zatwierdź';
  @override
  String get verdictRequestChanges => 'poproś o zmiany';
  @override
  String get verdictComment => 'komentarz';
  @override
  String get caughtUp => 'na bieżąco';
  @override
  String get sinceLastLook => 'od ostatniego spojrzenia';
  @override
  String get fullDiff => 'pełny diff';
  @override
  String get commentHint => 'napisz komentarz';
  @override
  String outdatedLastSeen({required Object round}) =>
      'nieaktualne · ostatnio widziane R${round}';
  @override
  String resolvedByFmt({required Object verb, required Object who}) =>
      '${verb} · ${who}';
  @override
  String waitingOnFmt({required Object who}) => 'czeka na ${who}';
  @override
  String roundChip({required Object round}) => 'R${round}';
  @override
  String filesSinceLastLook({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '1 plik od ostatniego spojrzenia',
        other: '${n} plików od ostatniego spojrzenia',
      );
  @override
  String unresolvedCountFmt({required Object n}) => '${n} nierozwiązanych';
  @override
  String draftCountFmt({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '1 szkic',
        other: '${n} szkiców',
      );
  @override
  String startReviewFailed({required Object error}) =>
      'Nie udało się rozpocząć recenzji: ${error}';
  @override
  String get anchorUnavailable =>
      'Tej linii nie można zakotwiczyć — plik jest zbyt duży lub niedostępny.';
  @override
  String reviewActionFailed({required Object error}) =>
      'Akcja recenzji nie powiodła się: ${error}';
  @override
  String get lensTooLarge =>
      'To porównanie jest zbyt duże, aby je tu pokazać — zostajemy przy pełnym diffie.';
  @override
  String get lensEmpty => 'Nic się nie zmieniło między tymi migawkami.';
  @override
  String get reopen => 'otwórz ponownie';
  @override
  String get notBlocking => 'nie czekajcie na mnie';
  @override
  String get markReviewed => 'przeczytane';
  @override
  String newComments({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '1 nowy komentarz',
        other: '${n} nowych komentarzy',
      );
  @override
  String get handTo => 'przekaż';
  @override
  String get heading => 'PRZEGLĄD';
  @override
  String get identityNeeded => 'Ustaw tożsamość git, aby recenzować';
  @override
  String get fileUnreadable =>
      'Tego pliku nie można tu odczytać — jest za duży lub nie istnieje w tej rundzie.';
  @override
  String get timeNow => 'teraz';
  @override
  String timeMinutesFmt({required Object n}) => '${n} min';
  @override
  String timeHoursFmt({required Object n}) => '${n} godz.';
  @override
  String timeDaysFmt({required Object n}) => '${n} dn.';
  @override
  String get standingApproved => 'zatwierdzono';
  @override
  String get standingChangesRequested => 'poproszono o zmiany';
}

// Path: settings
class _Translations$settings$pl extends Translations$settings$en {
  _Translations$settings$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$language$pl language =
      _Translations$settings$language$pl._(_root);
  @override
  late final _Translations$settings$sectionLabels$pl sectionLabels =
      _Translations$settings$sectionLabels$pl._(_root);
  @override
  late final _Translations$settings$errors$pl errors =
      _Translations$settings$errors$pl._(_root);
  @override
  late final _Translations$settings$promptStatus$pl promptStatus =
      _Translations$settings$promptStatus$pl._(_root);
  @override
  late final _Translations$settings$clearData$pl clearData =
      _Translations$settings$clearData$pl._(_root);
  @override
  List<String> get guardrailStageLabels => [
    'Luźno',
    'Zrównoważone',
    'Ściśle',
    'Paranoicznie',
  ];
  @override
  late final _Translations$settings$guardrailMacro$pl guardrailMacro =
      _Translations$settings$guardrailMacro$pl._(_root);
  @override
  late final _Translations$settings$guardrails$pl guardrails =
      _Translations$settings$guardrails$pl._(_root);
  @override
  late final _Translations$settings$appearance$pl appearance =
      _Translations$settings$appearance$pl._(_root);
  @override
  late final _Translations$settings$retention$pl retention =
      _Translations$settings$retention$pl._(_root);
  @override
  late final _Translations$settings$navigation$pl navigation =
      _Translations$settings$navigation$pl._(_root);
  @override
  late final _Translations$settings$behaviour$pl behaviour =
      _Translations$settings$behaviour$pl._(_root);
  @override
  late final _Translations$settings$retentionClear$pl retentionClear =
      _Translations$settings$retentionClear$pl._(_root);
  @override
  late final _Translations$settings$channels$pl channels =
      _Translations$settings$channels$pl._(_root);
  @override
  late final _Translations$settings$pollResult$pl pollResult =
      _Translations$settings$pollResult$pl._(_root);
  @override
  late final _Translations$settings$keybindingProfile$pl keybindingProfile =
      _Translations$settings$keybindingProfile$pl._(_root);
  @override
  late final _Translations$settings$apiKeys$pl apiKeys =
      _Translations$settings$apiKeys$pl._(_root);
  @override
  late final _Translations$settings$shortcuts$pl shortcuts =
      _Translations$settings$shortcuts$pl._(_root);
  @override
  late final _Translations$settings$toggles$pl toggles =
      _Translations$settings$toggles$pl._(_root);
  @override
  late final _Translations$settings$diffDiffability$pl diffDiffability =
      _Translations$settings$diffDiffability$pl._(_root);
  @override
  late final _Translations$settings$modelSlots$pl modelSlots =
      _Translations$settings$modelSlots$pl._(_root);
  @override
  late final _Translations$settings$modelPicker$pl modelPicker =
      _Translations$settings$modelPicker$pl._(_root);
  @override
  late final _Translations$settings$aiFeatures$pl aiFeatures =
      _Translations$settings$aiFeatures$pl._(_root);
  @override
  late final _Translations$settings$commitEditor$pl commitEditor =
      _Translations$settings$commitEditor$pl._(_root);
  @override
  late final _Translations$settings$review$pl review =
      _Translations$settings$review$pl._(_root);
  @override
  late final _Translations$settings$museHint$pl museHint =
      _Translations$settings$museHint$pl._(_root);
  @override
  late final _Translations$settings$museEditor$pl museEditor =
      _Translations$settings$museEditor$pl._(_root);
  @override
  late final _Translations$settings$museStage$pl museStage =
      _Translations$settings$museStage$pl._(_root);
  @override
  late final _Translations$settings$lensAxis$pl lensAxis =
      _Translations$settings$lensAxis$pl._(_root);
  @override
  late final _Translations$settings$logosLens$pl logosLens =
      _Translations$settings$logosLens$pl._(_root);
  @override
  late final _Translations$settings$sortGuide$pl sortGuide =
      _Translations$settings$sortGuide$pl._(_root);
  @override
  late final _Translations$settings$piggyback$pl piggyback =
      _Translations$settings$piggyback$pl._(_root);
  @override
  late final _Translations$settings$diffStage$pl diffStage =
      _Translations$settings$diffStage$pl._(_root);
  @override
  late final _Translations$settings$undoScope$pl undoScope =
      _Translations$settings$undoScope$pl._(_root);
  @override
  late final _Translations$settings$undoWindow$pl undoWindow =
      _Translations$settings$undoWindow$pl._(_root);
  @override
  late final _Translations$settings$guardrailPhrase$pl guardrailPhrase =
      _Translations$settings$guardrailPhrase$pl._(_root);
  @override
  late final _Translations$settings$reviewGuideHint$pl reviewGuideHint =
      _Translations$settings$reviewGuideHint$pl._(_root);
  @override
  late final _Translations$settings$commitFormat$pl commitFormat =
      _Translations$settings$commitFormat$pl._(_root);
  @override
  late final _Translations$settings$commitPreview$pl commitPreview =
      _Translations$settings$commitPreview$pl._(_root);
  @override
  late final _Translations$settings$externalTools$pl externalTools =
      _Translations$settings$externalTools$pl._(_root);
  @override
  late final _Translations$settings$apiUsage$pl apiUsage =
      _Translations$settings$apiUsage$pl._(_root);
  @override
  late final _Translations$settings$gitea$pl gitea =
      _Translations$settings$gitea$pl._(_root);
  @override
  late final _Translations$settings$wick$pl wick =
      _Translations$settings$wick$pl._(_root);
  @override
  late final _Translations$settings$integrations$pl integrations =
      _Translations$settings$integrations$pl._(_root);
  @override
  late final _Translations$settings$reduceMotion$pl reduceMotion =
      _Translations$settings$reduceMotion$pl._(_root);
  @override
  late final _Translations$settings$resetQuit$pl resetQuit =
      _Translations$settings$resetQuit$pl._(_root);
  @override
  late final _Translations$settings$diagnostics$pl diagnostics =
      _Translations$settings$diagnostics$pl._(_root);
  @override
  late final _Translations$settings$telemetry$pl telemetry =
      _Translations$settings$telemetry$pl._(_root);
  @override
  late final _Translations$settings$flowEngine$pl flowEngine =
      _Translations$settings$flowEngine$pl._(_root);
  @override
  late final _Translations$settings$museStrands$pl museStrands =
      _Translations$settings$museStrands$pl._(_root);
  @override
  late final _Translations$settings$cliPiggyback$pl cliPiggyback =
      _Translations$settings$cliPiggyback$pl._(_root);
  @override
  late final _Translations$settings$header$pl header =
      _Translations$settings$header$pl._(_root);
  @override
  late final _Translations$settings$diagnosticsPanel$pl diagnosticsPanel =
      _Translations$settings$diagnosticsPanel$pl._(_root);
  @override
  late final _Translations$settings$release$pl release =
      _Translations$settings$release$pl._(_root);
  @override
  late final _Translations$settings$providerStatus$pl providerStatus =
      _Translations$settings$providerStatus$pl._(_root);
  @override
  late final _Translations$settings$meridiem$pl meridiem =
      _Translations$settings$meridiem$pl._(_root);
  @override
  late final _Translations$settings$offenders$pl offenders =
      _Translations$settings$offenders$pl._(_root);
}

// Path: sync
class _Translations$sync$pl extends Translations$sync$en {
  _Translations$sync$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$actions$pl actions =
      _Translations$sync$actions$pl._(_root);
  @override
  late final _Translations$sync$panel$pl panel = _Translations$sync$panel$pl._(
    _root,
  );
  @override
  late final _Translations$sync$forcePush$pl forcePush =
      _Translations$sync$forcePush$pl._(_root);
}

// Path: xray
class _Translations$xray$pl extends Translations$xray$en {
  _Translations$xray$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$board$pl board = _Translations$xray$board$pl._(
    _root,
  );
  @override
  late final _Translations$xray$cadence$pl cadence =
      _Translations$xray$cadence$pl._(_root);
  @override
  late final _Translations$xray$cards$pl cards = _Translations$xray$cards$pl._(
    _root,
  );
  @override
  late final _Translations$xray$cardTitle$pl cardTitle =
      _Translations$xray$cardTitle$pl._(_root);
  @override
  late final _Translations$xray$grain$pl grain = _Translations$xray$grain$pl._(
    _root,
  );
  @override
  late final _Translations$xray$header$pl header =
      _Translations$xray$header$pl._(_root);
  @override
  late final _Translations$xray$hotspot$pl hotspot =
      _Translations$xray$hotspot$pl._(_root);
  @override
  late final _Translations$xray$inspector$pl inspector =
      _Translations$xray$inspector$pl._(_root);
  @override
  late final _Translations$xray$loadingCard$pl loadingCard =
      _Translations$xray$loadingCard$pl._(_root);
  @override
  late final _Translations$xray$metabolism$pl metabolism =
      _Translations$xray$metabolism$pl._(_root);
  @override
  late final _Translations$xray$multi$pl multi = _Translations$xray$multi$pl._(
    _root,
  );
  @override
  late final _Translations$xray$recency$pl recency =
      _Translations$xray$recency$pl._(_root);
  @override
  late final _Translations$xray$rings$pl rings = _Translations$xray$rings$pl._(
    _root,
  );
  @override
  late final _Translations$xray$stats$pl stats = _Translations$xray$stats$pl._(
    _root,
  );
  @override
  late final _Translations$xray$stratumLabel$pl stratumLabel =
      _Translations$xray$stratumLabel$pl._(_root);
  @override
  late final _Translations$xray$summary$pl summary =
      _Translations$xray$summary$pl._(_root);
  @override
  late final _Translations$xray$tabs$pl tabs = _Translations$xray$tabs$pl._(
    _root,
  );
  @override
  late final _Translations$xray$trajectory$pl trajectory =
      _Translations$xray$trajectory$pl._(_root);
  @override
  late final _Translations$xray$verdict$pl verdict =
      _Translations$xray$verdict$pl._(_root);
}

// Path: app.cheatsheet
class _Translations$app$cheatsheet$pl extends Translations$app$cheatsheet$en {
  _Translations$app$cheatsheet$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Klawiatura';
  @override
  String get sectionNavigate => 'nawigacja';
  @override
  String get sectionStaging => 'indeks';
  @override
  String get sectionBranchesPrs => 'gałęzie i PR';
  @override
  String get changes => 'Zmiany';
  @override
  String get history => 'Historia';
  @override
  String get branches => 'Gałęzie';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Przełącz (zawsze)';
  @override
  String get commandPalette => 'Paleta poleceń';
  @override
  String get elevatedPalette => 'Rozszerzona paleta';
  @override
  String get dismiss => 'Zamknij';
  @override
  String get refresh => 'Odśwież';
  @override
  String get nextPrevChange => 'Nast. / poprz. zmiana';
  @override
  String get toggleLine => 'Przełącz linię';
  @override
  String get toggleHunk => 'Przełącz hunk';
  @override
  String get toggleFile => 'Przełącz plik';
  @override
  String get pinContext => 'Przypnij kontekst';
  @override
  String get commit => 'Commit';
  @override
  String get acceptAiHint => 'Przyjmij podpowiedź AI';
  @override
  String get undo => 'Cofnij';
  @override
  String get navigate => 'Nawigacja';
  @override
  String get expand => 'Rozwiń';
  @override
  String get checkoutPr => 'Checkout PR';
  @override
  String get approve => 'Zatwierdź';
  @override
  String get requestChanges => 'Poproś o zmiany';
  @override
  String profileSwitchHint({required Object profile}) =>
      'profil ${profile} · zmień w Ustawieniach';
}

// Path: backend.ops
class _Translations$backend$ops$pl extends Translations$backend$ops$en {
  _Translations$backend$ops$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'Merge';
  @override
  String get pull => 'Pull';
  @override
  String get apply => 'Zastosowanie';
  @override
  String get switchOp => 'Przełączanie';
  @override
  String get sync => 'Synchr.';
}

// Path: backend.mergeOutcome
class _Translations$backend$mergeOutcome$pl
    extends Translations$backend$mergeOutcome$en {
  _Translations$backend$mergeOutcome$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String cancelled({required Object op}) => '${op} — anulowano.';
  @override
  String complete({required Object op}) => '${op} — zakończono.';
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'Pozostał ${n} konflikt — rozwiąż go na stronie „Zmiany”.',
        few: 'Pozostały ${n} konflikty — rozwiąż je na stronie „Zmiany”.',
        many: 'Pozostało ${n} konfliktów — rozwiąż je na stronie „Zmiany”.',
        other: 'Pozostało ${n} konfliktu — rozwiąż je na stronie „Zmiany”.',
      );
  @override
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'Rozwiązano ${n} konflikt.',
        few: 'Rozwiązano ${n} konflikty.',
        many: 'Rozwiązano ${n} konfliktów.',
        other: 'Rozwiązano ${n} konfliktu.',
      );
  @override
  String uncommittedEdits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} plik ma zmiany bez commita — najpierw je zacommituj.',
        few: '${n} pliki mają zmiany bez commita — najpierw je zacommituj.',
        many: '${n} plików ma zmiany bez commita — najpierw je zacommituj.',
        other: '${n} pliku ma zmiany bez commita — najpierw je zacommituj.',
      );
}

// Path: changes.usage
class _Translations$changes$usage$pl extends Translations$changes$usage$en {
  _Translations$changes$usage$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String caption({required Object input, required Object output}) =>
      '${input} wejście · ${output} wyjście';
  @override
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '${fresh} wejście · ${cached} z cache · ${out} wyjście';
  @override
  String get inWord => 'wejście';
  @override
  String get cachedWord => 'z cache';
  @override
  String get outWord => 'wyjście';
  @override
  String tipIn({required Object value}) => '${value}  wejście';
  @override
  String tipCacheRead({required Object value}) => '${value}  odczyt cache';
  @override
  String tipCacheWrite({required Object value}) => '${value}  zapis cache';
  @override
  String tipOut({required Object value}) => '${value}  wyjście';
  @override
  String tipReasoning({required Object value}) => '${value}  rozumowanie';
  @override
  String tipWallClock({required Object value}) =>
      '${value} s  czas rzeczywisty';
}

// Path: changes.tabs
class _Translations$changes$tabs$pl extends Translations$changes$tabs$en {
  _Translations$changes$tabs$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get defaultLabel => 'Zmiany';
  @override
  String get empty => 'Puste';
}

// Path: changes.tabStrip
class _Translations$changes$tabStrip$pl
    extends Translations$changes$tabStrip$en {
  _Translations$changes$tabStrip$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get newDiffTab => 'Nowa karta diff';
}

// Path: changes.select
class _Translations$changes$select$pl extends Translations$changes$select$en {
  _Translations$changes$select$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get selectAll => 'Zaznacz wszystko';
  @override
  String get deselectAll => 'Odznacz wszystko';
}

// Path: changes.constellationToggle
class _Translations$changes$constellationToggle$pl
    extends Translations$changes$constellationToggle$en {
  _Translations$changes$constellationToggle$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get backToList => 'powrót do listy';
  @override
  String get atlas => 'atlas, zobacz kandydatów na commit';
}

// Path: changes.nudgeChip
class _Translations$changes$nudgeChip$pl
    extends Translations$changes$nudgeChip$en {
  _Translations$changes$nudgeChip$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\nsprzęga się z ${anchor} · ${pct}%${receipts}';
}

// Path: changes.minimap
class _Translations$changes$minimap$pl extends Translations$changes$minimap$en {
  _Translations$changes$minimap$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get roleNew => 'nowy';
  @override
  String get roleBridge => 'most';
  @override
  String get roleHub => 'węzeł';
  @override
  String get roleLeaf => 'liść';
  @override
  String get roleConnected => 'połączony';
  @override
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';
  @override
  String changesWith({required Object name}) => 'zmienia się z ${name}';
  @override
  String get newFile => 'nowy plik';
  @override
  String nearOtherChanges({required Object count, required Object dir}) =>
      'blisko ${count} innych zmian w ${dir}';
  @override
  String usuallyChangesWithFile({required Object name}) =>
      '${name} zwykle zmienia się razem z tym plikiem';
}

// Path: changes.tagInput
class _Translations$changes$tagInput$pl
    extends Translations$changes$tagInput$en {
  _Translations$changes$tagInput$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get hint => 'tag...';
}

// Path: changes.composer
class _Translations$changes$composer$pl
    extends Translations$changes$composer$en {
  _Translations$changes$composer$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get hintPlaceholder => 'wiadomość commita...';
  @override
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class _Translations$changes$commit$pl extends Translations$changes$commit$en {
  _Translations$changes$commit$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get primaryCommitChanges => 'Zacommituj zmiany';
  @override
  String get primaryCommitChangesDetail =>
      'Odłączony HEAD: commit lokalnie bez synchronizacji.';
  @override
  String get primaryPublish => 'Commit i publikacja';
  @override
  String get primaryPublishDetail =>
      'Utwórz commit i opublikuj tę gałąź w jednym kroku.';
  @override
  String get primarySync => 'Commit i synchronizacja';
  @override
  String get primarySyncDetail =>
      'Utwórz commit, następnie uzgodnij i wyślij gałąź.';
  @override
  String get primaryPush => 'Commit i push';
  @override
  String get primaryPushDetail => 'Utwórz commit i od razu go pushnij.';
  @override
  String get amendLast => 'Popraw ostatni commit';
  @override
  String amendAnd({required Object action}) => 'Popraw i ${action}';
  @override
  String get chooseFile =>
      'Wybierz co najmniej jeden plik do następnego commita.';
  @override
  String get writeMessage => 'Najpierw napisz wiadomość commita.';
  @override
  String get committing => 'Commituję';
  @override
  String get committingSync => 'Commituję i synchronizuję';
  @override
  String get committed => 'Zacommitowano.';
  @override
  String get undoFailed => 'Nie udało się cofnąć.';
  @override
  String get working => 'Pracuję…';
  @override
  String get commitOnly => 'Tylko commit';
  @override
  String get noRuntimeModels =>
      'Brak wykrytych w czasie działania modeli do wiadomości commitów.';
  @override
  String restoreFailedRetry({required Object err}) =>
      '${err}\nNie udało się przywrócić indeksowania wykluczonych plików; sprawdź indeks przed ponowieniem.';
  @override
  String committedSummary({required Object summary, required Object hash}) =>
      'Zacommitowano ${summary} (${hash}).';
  @override
  String get restoreFailedSync =>
      'Nie udało się ponownie dodać do indeksu wyborów wykluczonych plików; pominięto synchronizację. Sprawdź indeks przed synchronizacją.';
  @override
  String get noModelLabel => 'Brak modelu';
  @override
  String get chooseBeforeGenerate =>
      'Wybierz co najmniej jeden plik przed generowaniem.';
  @override
  String get aiUnavailable =>
      'AI do wiadomości commitów nie jest jeszcze dostępne.';
  @override
  String get generateFailed => 'Nie udało się wygenerować.';
  @override
  String get stageFailed => 'Nie udało się dodać plików do indeksu.';
  @override
  String get commitFailed => 'Nie udało się utworzyć commita.';
  @override
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => 'Zacommitowano ${summary} (${hash}) i wykonano ${operation}.';
  @override
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
    n,
    one: 'Zacommitowano ${summary} (${hash}); rozwiązano ${n} konflikt.',
    few: 'Zacommitowano ${summary} (${hash}); rozwiązano ${n} konflikty.',
    many: 'Zacommitowano ${summary} (${hash}); rozwiązano ${n} konfliktów.',
    other: 'Zacommitowano ${summary} (${hash}); rozwiązano ${n} konfliktu.',
  );
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'Pozostał ${n} konflikt do rozwiązania.',
        few: 'Pozostały ${n} konflikty do rozwiązania.',
        many: 'Pozostało ${n} konfliktów do rozwiązania.',
        other: 'Pozostało ${n} konfliktu do rozwiązania.',
      );
  @override
  String syncBlocked({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
    n,
    one:
        'Commit się udał, ale synchronizację zablokował ${n} niezacommitowany plik.',
    few:
        'Commit się udał, ale synchronizację zablokowały ${n} niezacommitowane pliki.',
    many:
        'Commit się udał, ale synchronizację zablokowało ${n} niezacommitowanych plików.',
    other:
        'Commit się udał, ale synchronizację zablokowało ${n} niezacommitowanego pliku.',
  );
  @override
  String syncStalled({required Object message}) =>
      'Commit się udał, ale synchronizacja utknęła: ${message}';
  @override
  String syncFailed({required Object message}) =>
      'Commit się udał, ale synchronizacja nie powiodła się: ${message}';
}

// Path: changes.rebase
class _Translations$changes$rebase$pl extends Translations$changes$rebase$en {
  _Translations$changes$rebase$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get continueFailed => 'Nie udało się kontynuować rebase.';
}

// Path: changes.editor
class _Translations$changes$editor$pl extends Translations$changes$editor$en {
  _Translations$changes$editor$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get closeBarrier => 'Zamknij edytor';
}

// Path: changes.editorTitles
class _Translations$changes$editorTitles$pl
    extends Translations$changes$editorTitles$en {
  _Translations$changes$editorTitles$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  List<String> get any => [
    'drogi git logu',
    'wybacz mi, o Gicie, bom zgrzeszył…',
    'nazwij tę chwilę',
    'gadaj dalej',
    'mów!',
    'twoja matka była wiszącą referencją, a twój ojciec pachniał średnikami',
  ];
  @override
  List<String> get short => [
    'no?',
    'witaj:)',
    'swoją drogą:',
    'kilka słów',
    'wersja grzeczna',
    'zostaw notatkę',
    'mówiłeś coś..?',
    'no dawaj, wyrzuć to z siebie',
  ];
  @override
  List<String> get mid => [
    'dla porządku',
    'powiedz sobie z przyszłości',
    'ale najpierw?',
    'jak poszło',
    'własnymi słowami',
    'zrobiłeś CO?',
    'przyjęto do wiadomości',
    'słucham uważnie',
  ];
  @override
  List<String> get long => [
    'twoje marzenia, proszę',
    'powiedz coś miłego',
    '…a wtedy powiedziałem:',
    'potomność czeka',
    'im więcej piszesz, tym więcej bugów znika',
    'no proszę',
    'święte teksty',
  ];
}

// Path: changes.askHint
class _Translations$changes$askHint$pl extends Translations$changes$askHint$en {
  _Translations$changes$askHint$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String round({required Object n}) =>
      'runda ${n} — doprecyzuj lub dodaj kontekst.';
  @override
  String get symptom => 'opisz objaw.';
  @override
  String get broken => 'co się zepsuło?';
  @override
  String get bug => 'opisz buga.';
  @override
  String get error => 'wklej błąd.';
}

// Path: changes.fileMenu
class _Translations$changes$fileMenu$pl
    extends Translations$changes$fileMenu$en {
  _Translations$changes$fileMenu$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get ripple => 'Fala';
  @override
  String get includeCoChanges => 'Dołącz wspólne zmiany';
  @override
  String deleteFile({required Object name}) => 'Usuń ${name}…';
  @override
  String discardChangesTo({required Object name}) => 'Odrzuć zmiany w ${name}…';
  @override
  String get ignore => 'Ignoruj';
  @override
  String get diffTabFromSelection => 'Karta diff z zaznaczenia';
  @override
  String addSelectedToTab({required Object name}) =>
      'Dodaj zaznaczone do ${name}';
  @override
  String diffTabFromFile({required Object name}) => 'Karta diff z ${name}';
  @override
  String addFileToTab({required Object file, required Object tab}) =>
      'Dodaj ${file} do ${tab}';
  @override
  String get copyFilePath => 'Kopiuj ścieżkę pliku';
  @override
  String get showInExplorer => 'Pokaż w eksploratorze';
}

// Path: changes.multiFileMenu
class _Translations$changes$multiFileMenu$pl
    extends Translations$changes$multiFileMenu$en {
  _Translations$changes$multiFileMenu$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get cohesionTight => 'ściśle sprzężone';
  @override
  String get cohesionLoose => 'luźno powiązane';
  @override
  String get cohesionScattered => 'strukturalnie rozproszone';
  @override
  String get clusterOne => 'wszystko w jednym klastrze';
  @override
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      'obejmuje ${count} klastrów (${parts} plików)';
  @override
  String clusterSpans({required Object count}) => 'obejmuje ${count} klastrów';
  @override
  String roleLine({required Object count, required Object cohesion}) =>
      '${count} plików · ${cohesion}';
  @override
  String usuallyChangesWithGroup({required Object file}) =>
      '${file} zwykle zmienia się razem z tą grupą';
  @override
  String get splitToNewTab => 'Wydziel do nowej karty';
  @override
  String copyPaths({required Object count}) => 'Kopiuj ${count} ścieżek';
}

// Path: changes.ignoreMenu
class _Translations$changes$ignoreMenu$pl
    extends Translations$changes$ignoreMenu$en {
  _Translations$changes$ignoreMenu$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String extension({required Object ext}) => 'rozszerzenie .${ext}';
  @override
  String allSelected({required Object count}) =>
      'Wszystkie zaznaczone ${count}';
  @override
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'Sprzęga się z ${n} dołączonym plikiem',
        few: 'Sprzęga się z ${n} dołączonymi plikami',
        many: 'Sprzęga się z ${n} dołączonymi plikami',
        other: 'Sprzęga się z ${n} dołączonego pliku',
      );
  @override
  String get updateFailed => 'Nie udało się zaktualizować .gitignore.';
}

// Path: changes.discard
class _Translations$changes$discard$pl extends Translations$changes$discard$en {
  _Translations$changes$discard$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String deleteTitle({required Object name}) => 'Usunąć ${name}?';
  @override
  String discardTitle({required Object name}) => 'Odrzucić zmiany w ${name}?';
  @override
  String deleteBody({required Object path}) =>
      '${path} zostanie usunięty z dysku. Nie można tego cofnąć z poziomu aplikacji.';
  @override
  String discardBody({required Object path}) =>
      'Wszystkie zmiany w ${path} zostaną przywrócone do stanu z HEAD. Nie można tego cofnąć.';
  @override
  String get discard => 'Odrzuć';
  @override
  String deletingFile({required Object name}) => 'Usuwam ${name}';
  @override
  String discardingFile({required Object name}) => 'Odrzucam ${name}';
  @override
  String get discardFailed => 'Nie udało się odrzucić zmian.';
  @override
  String discardManyTitle({required Object count}) =>
      'Odrzucić zmiany w ${count} plikach?';
  @override
  String get discardManyBody =>
      'Śledzone pliki zostaną przywrócone do stanu z HEAD; nieśledzone zostaną usunięte z dysku. Nie można tego cofnąć.';
  @override
  String discardManyConfirm({required Object count}) => 'Odrzuć ${count}';
  @override
  String discardingManyFiles({required Object count}) =>
      'Odrzucam ${count} plików';
  @override
  String failedOpenExplorer({required Object error}) =>
      'Nie udało się otworzyć eksploratora plików: ${error}';
  @override
  String get someFailed => 'Niektóre odrzucenia nie powiodły się.';
}

// Path: changes.snack
class _Translations$changes$snack$pl extends Translations$changes$snack$en {
  _Translations$changes$snack$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get sameWorktree => 'To samo drzewo robocze — nie ma czego zrzucić.';
  @override
  String diffFailed({required Object error}) =>
      'Diff nie powiódł się: ${error}';
  @override
  String get deskEmpty => 'Desk nie ma nic przed tobą — pusty zrzut.';
  @override
  String sourceDesk({required Object label}) => 'Desk ${label}';
  @override
  String shelfReadFailed({required Object error}) =>
      'Nie udało się odczytać półki: ${error}';
  @override
  String get shelfEmpty => 'Pusta półka — nie ma czego zrzucić.';
  @override
  String sourceShelf({required Object label}) => 'półka ${label}';
  @override
  String noModelConfigured({required Object label}) =>
      'Nie skonfigurowano modelu dla „${label}”.';
  @override
  String fetchFailed({required Object error}) =>
      'Fetch nie powiódł się: ${error}';
}

// Path: changes.trace
class _Translations$changes$trace$pl extends Translations$changes$trace$en {
  _Translations$changes$trace$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Ślad weryfikacji';
  @override
  String get draftReview => 'Szkic przeglądu';
}

// Path: changes.cleanTree
class _Translations$changes$cleanTree$pl
    extends Translations$changes$cleanTree$en {
  _Translations$changes$cleanTree$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Drzewo robocze czyste';
  @override
  String get subtitle => 'Nie wykryto zmian w indeksie ani poza nim.';
  @override
  String get noUpstream => '  ·  brak upstream';
  @override
  String get ahead => ' do przodu';
  @override
  String get behind => ' w tyle';
  @override
  String get refreshing => 'Odświeżanie...';
  @override
  String get refresh => 'Odśwież';
  @override
  String get check => 'sprawdź';
  @override
  String get checkTooltip => 'Fetch i lokalne odświeżenie.';
  @override
  String get sync => '& synchr';
}

// Path: changes.guardrail
class _Translations$changes$guardrail$pl
    extends Translations$changes$guardrail$en {
  _Translations$changes$guardrail$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'Luźno';
  @override
  String get balanced => 'Zrównoważone';
  @override
  String get strict => 'Ściśle';
  @override
  String get paranoid => 'Paranoicznie';
}

// Path: changes.dropHint
class _Translations$changes$dropHint$pl
    extends Translations$changes$dropHint$en {
  _Translations$changes$dropHint$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get fromShelf => 'upuść, aby przenieść zmiany z tej półki tutaj';
  @override
  String get fromDesk => 'upuść, aby przenieść zmiany z tego Desku tutaj';
}

// Path: changes.diffEmpty
class _Translations$changes$diffEmpty$pl
    extends Translations$changes$diffEmpty$en {
  _Translations$changes$diffEmpty$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Nie wybrano pliku';
  @override
  String get message => 'Wybierz zmieniony plik, aby zobaczyć jego diff.';
}

// Path: changes.shelvePill
class _Translations$changes$shelvePill$pl
    extends Translations$changes$shelvePill$en {
  _Translations$changes$shelvePill$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String shelveN({required Object count}) => '↓ odłóż ${count}';
  @override
  String get shelve => '↓ odłóż';
  @override
  String shelvedCount({required Object count, required Object glyph}) =>
      '${count} odłożono ${glyph}';
}

// Path: changes.stashAction
class _Translations$changes$stashAction$pl
    extends Translations$changes$stashAction$en {
  _Translations$changes$stashAction$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get pickUp => 'podnieś';
  @override
  String get peek => 'zerknij';
  @override
  String get toss => 'wyrzuć';
}

// Path: changes.stashContents
class _Translations$changes$stashContents$pl
    extends Translations$changes$stashContents$en {
  _Translations$changes$stashContents$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get reading => 'odczytuję półkę…';
  @override
  String get empty => 'pusta półka';
}

// Path: changes.stashFile
class _Translations$changes$stashFile$pl
    extends Translations$changes$stashFile$en {
  _Translations$changes$stashFile$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get binary => 'bin';
}

// Path: changes.fileRow
class _Translations$changes$fileRow$pl extends Translations$changes$fileRow$en {
  _Translations$changes$fileRow$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get stagedLinesOnly => 'commituje tylko linie z indeksu';
  @override
  String get doubleClickToggle => 'podwójne kliknięcie: przełącz całą grupę';
  @override
  String get repoRoot => 'Korzeń repozytorium';
}

// Path: changes.resolveStrip
class _Translations$changes$resolveStrip$pl
    extends Translations$changes$resolveStrip$en {
  _Translations$changes$resolveStrip$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'odczytuję ${n} plik · szkicuję rozwiązanie…',
        few: 'odczytuję ${n} pliki · szkicuję rozwiązanie…',
        many: 'odczytuję ${n} plików · szkicuję rozwiązanie…',
        other: 'odczytuję ${n} pliku · szkicuję rozwiązanie…',
      );
  @override
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} konflikt w ${files}',
        few: '${n} konflikty w ${files}',
        many: '${n} konfliktów w ${files}',
        other: '${n} konfliktu w ${files}',
      );
  @override
  String get resolve => 'Rozwiąż';
  @override
  String get orWith => 'LUB Z';
  @override
  String resolveWith({required Object label}) => 'rozwiąż z ${label}';
  @override
  String resolveWithModel({required Object label, required Object model}) =>
      'rozwiąż z ${label}  ·  ${model}';
  @override
  String get resolving => 'rozwiązuję…';
  @override
  String resolveWithGlyph({required Object label}) => '↵  rozwiąż z ${label}';
  @override
  String get orWithAnother => 'lub z innym modelem';
}

// Path: changes.badge
class _Translations$changes$badge$pl extends Translations$changes$badge$en {
  _Translations$changes$badge$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get stagedEdit => 'Edycja w indeksie';
  @override
  String get edited => 'Zmieniony';
  @override
  String get stagedAdd => 'Dodanie w indeksie';
  @override
  String get added => 'Dodany';
  @override
  String get stagedDelete => 'Usunięcie w indeksie';
  @override
  String get deleted => 'Usunięty';
  @override
  String get stagedRename => 'Zmiana nazwy w indeksie';
  @override
  String get renamed => 'Zmieniono nazwę';
  @override
  String get stagedCopy => 'Kopia w indeksie';
  @override
  String get copied => 'Skopiowany';
  @override
  String get conflict => 'Konflikt';
  @override
  String get stagedTypeChange => 'Zmiana typu w indeksie';
  @override
  String get typeChanged => 'Typ zmieniony';
  @override
  String get untracked => 'Nieśledzony';
}

// Path: changes.review
class _Translations$changes$review$pl extends Translations$changes$review$en {
  _Translations$changes$review$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Przegląd kodu';
  @override
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} dołączony plik',
        few: '${n} dołączone pliki',
        many: '${n} dołączonych plików',
        other: '${n} dołączonego pliku',
      );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} hunk',
        few: '${n} hunki',
        many: '${n} hunków',
        other: '${n} hunka',
      );
  @override
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';
  @override
  String get unavailable => 'Przegląd niedostępny';
  @override
  String get backToDiff => 'Powrót do diff';
  @override
  String get verified => 'Zweryfikowano';
  @override
  String get draftOnly => 'Tylko szkic';
  @override
  String get runAgain => 'Uruchom ponownie';
  @override
  String draftShownBelow({required Object error}) =>
      '${error} Szkic przeglądu pokazano poniżej.';
  @override
  String get hideTrace => 'Ukryj ślad';
  @override
  String get showTrace => 'Pokaż ślad';
  @override
  String get showVerificationTrace => 'Pokaż ślad weryfikacji';
  @override
  String get whyLanded => 'Dlaczego ten przegląd tu trafił';
  @override
  String get noFindings => 'Brak znalezisk';
  @override
  String get findings => 'Znaleziska';
  @override
  String get noEvidenceIssues =>
      'Dla tego zakresu commita nie wypłynęły problemy poparte dowodami.';
  @override
  String get observations => 'Obserwacje';
  @override
  String get chooseBeforeReview =>
      'Wybierz co najmniej jeden plik przed przeglądem.';
  @override
  String get aiUnavailable => 'Przegląd AI nie jest jeszcze dostępny.';
  @override
  String get failed => 'Przegląd nie powiódł się.';
  @override
  String get noRuntimeModels =>
      'Brak wykrytych w czasie działania modeli do przeglądu commitów.';
}

// Path: changes.commitBtn
class _Translations$changes$commitBtn$pl
    extends Translations$changes$commitBtn$en {
  _Translations$changes$commitBtn$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String switchTo({required Object label}) => 'Przełącz na: ${label}\n';
}

// Path: changes.shapeBtn
class _Translations$changes$shapeBtn$pl
    extends Translations$changes$shapeBtn$en {
  _Translations$changes$shapeBtn$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String askingWith({required Object cat}) => 'pytam przez ${cat}…';
  @override
  String askWith({required Object cat}) => 'zapytaj przez ${cat}';
  @override
  String get noModel => 'nie skonfigurowano modelu AI';
  @override
  String nextTooltip({required Object cat}) =>
      'dalej: ${cat}  ·  shift-klik dla poprzedniego';
  @override
  String get onlyOne => 'skonfigurowano tylko jedną kategorię AI';
}

// Path: changes.dejaVu
class _Translations$changes$dejaVu$pl extends Translations$changes$dejaVu$en {
  _Translations$changes$dejaVu$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required num n,
    required Object pct,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
    n,
    one:
        '${pct}% déjà vu — ${n} widmowa krawędź z odrzuconych linii czasu dotyka tego diff',
    few:
        '${pct}% déjà vu — ${n} widmowe krawędzie z odrzuconych linii czasu dotykają tego diff',
    many:
        '${pct}% déjà vu — ${n} widmowych krawędzi z odrzuconych linii czasu dotyka tego diff',
    other:
        '${pct}% déjà vu — ${n} widmowej krawędzi z odrzuconych linii czasu dotyka tego diff',
  );
  @override
  String get label => 'déjà vu';
}

// Path: changes.identity
class _Translations$changes$identity$pl
    extends Translations$changes$identity$en {
  _Translations$changes$identity$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'nie skonfigurowano tożsamości do commita';
  @override
  String asName({required Object name}) => 'jako ${name}';
  @override
  String asNameEmail({required Object name, required Object email}) =>
      'jako ${name} <${email}>';
  @override
  String asNameSpace({required Object name}) => 'jako ${name} ';
  @override
  String emailAngle({required Object email}) => '<${email}>';
  @override
  String get firstCommit => '\npierwszy commit w tym repozytorium';
  @override
  String get newToRepo => '\nnowy w tym repozytorium';
}

// Path: changes.staleScope
class _Translations$changes$staleScope$pl
    extends Translations$changes$staleScope$en {
  _Translations$changes$staleScope$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get message => 'wybór zmienił się od czasu uruchomienia';
  @override
  String get rerun => 'uruchom ponownie';
}

// Path: changes.finding
class _Translations$changes$finding$pl extends Translations$changes$finding$en {
  _Translations$changes$finding$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get openDiff => 'Otwórz diff';
  @override
  String get recorded => 'zapisano';
  @override
  String get dismiss => 'Odrzuć';
}

// Path: changes.muse
class _Translations$changes$muse$pl extends Translations$changes$muse$en {
  _Translations$changes$muse$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Muse';
  @override
  String get youPulledThis => 'wyciągnąłeś to';
  @override
  String fromIdea({required Object text}) => 'z pomysłu: „${text}”';
  @override
  String get foothold => 'punkt oparcia — ';
  @override
  String get brainstormSpew => 'wylew burzy mózgów';
  @override
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';
  @override
  String copyN({required Object count}) => 'Kopiuj ${count}';
  @override
  String get clear => 'Wyczyść';
  @override
  String get chooseBeforeMuse =>
      'Wybierz co najmniej jeden plik przed wezwaniem muzy.';
  @override
  String get aiUnavailable => 'AI dla Muse nie jest jeszcze dostępne.';
  @override
  String get failed => 'Muse nie powiodło się.';
  @override
  String get noRuntimeModels =>
      'Brak wykrytych w czasie działania modeli dla muzy.';
  @override
  String get needsModel =>
      'Muza potrzebuje co najmniej jednego skonfigurowanego modelu.';
  @override
  String get dreaming => 'muza śni...';
}

// Path: changes.debug
class _Translations$changes$debug$pl extends Translations$changes$debug$en {
  _Translations$changes$debug$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Debug';
  @override
  String round({required Object n}) => '· runda ${n}';
  @override
  String get clear => 'wyczyść';
  @override
  String get close => 'zamknij';
  @override
  String get analyzing => 'analizuję objaw…';
  @override
  String get describeSymptom => 'opisz objaw, potem naciśnij debug.';
  @override
  String get evidenceFor => 'za';
  @override
  String get evidenceAgainst => 'ale';
  @override
  String get narrowDown => 'co pomogłoby zawęzić:';
  @override
  String get failed => 'Debug nie powiódł się.';
  @override
  String get refinementFailed => 'Nie udało się doprecyzować debugowania.';
}

// Path: changes.includeSummary
class _Translations$changes$includeSummary$pl
    extends Translations$changes$includeSummary$en {
  _Translations$changes$includeSummary$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'Nic';
  @override
  String stagedSuffix({required Object count}) => ' · ${count} w indeksie';
  @override
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'Wszystkie ${n} plik${staged}',
        few: 'Wszystkie ${n} pliki${staged}',
        many: 'Wszystkie ${n} plików${staged}',
        other: 'Wszystkie ${n} pliku${staged}',
      );
  @override
  String partial({
    required Object count,
    required Object n,
    required Object staged,
  }) => '${count} z ${n}${staged}';
  @override
  String shortAll({required Object n, required Object staged}) =>
      'Wszystkie ${n}${staged}';
}

// Path: changes.status
class _Translations$changes$status$pl extends Translations$changes$status$en {
  _Translations$changes$status$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get unavailableTitle => 'Status repozytorium niedostępny';
  @override
  String get loadingTitle => 'Ładowanie statusu repozytorium';
  @override
  String get loadingMessage => 'Odczytuję drzewo robocze.';
}

// Path: changes.stash
class _Translations$changes$stash$pl extends Translations$changes$stash$en {
  _Translations$changes$stash$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get appliedWithConflicts =>
      'Stash zastosowany z konfliktami — rozwiąż je na stronie „Zmiany” (wpis stash zachowano).';
  @override
  String get couldNotPop => 'Nie udało się wyjąć stash.';
  @override
  String get listChanged =>
      'Lista stashy się zmieniła; pominięto usunięcie. Spróbuj ponownie.';
  @override
  String get droppingStash => 'Usuwam stash';
}

// Path: changes.tooltips
class _Translations$changes$tooltips$pl
    extends Translations$changes$tooltips$en {
  _Translations$changes$tooltips$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get commitGenerating => 'generuję wiadomość commita...';
  @override
  String get commitPreparing => 'przygotowuję wiadomość commita...';
  @override
  String get commitSelectFile =>
      'wybierz co najmniej jeden plik, aby wygenerować wiadomość commita.';
  @override
  String get commitConfigure =>
      'skonfiguruj wiadomości commitów w Ustawienia > Dynamika zachowań > Wiadomości commitów.';
  @override
  String get fastFallback => 'szybko';
  @override
  String commitGenerateWith({required Object label}) =>
      'wygeneruj wiadomość commita modelem ${label}';
  @override
  String get museConsulting => 'radzę się muzy...';
  @override
  String get showMuse => 'pokaż muzę';
  @override
  String get museSelectFile => 'wybierz co najmniej jeden plik dla muzy.';
  @override
  String get showMuseError => 'pokaż błąd muzy';
  @override
  String get museAsk => 'zapytaj muzę o kierunek';
  @override
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => 'zapytaj muzę o kierunek\n${brainstorm} → ${synthesis}';
  @override
  String get qualityFallback => 'jakość';
  @override
  String get reviewing => 'przeglądam...';
  @override
  String get showReview => 'pokaż przegląd';
  @override
  String get reviewPreparing => 'przygotowuję przegląd commita...';
  @override
  String get reviewSelectFile => 'wybierz co najmniej jeden plik do przeglądu.';
  @override
  String get reviewConfigure => 'skonfiguruj przegląd AI w ustawieniach.';
  @override
  String get viewingReview => 'wyświetlanie przeglądu';
  @override
  String reviewWith({required Object guardrail, required Object label}) =>
      '${guardrail} przegląd modelem ${label}';
}

// Path: changes.mergeEditor
class _Translations$changes$mergeEditor$pl
    extends Translations$changes$mergeEditor$en {
  _Translations$changes$mergeEditor$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get resolutionYours => 'twoje';
  @override
  String get resolutionTheirs => 'ich';
  @override
  String get resolutionCustom => 'własne';
  @override
  String get keepBoth => 'zachowaj oba';
  @override
  late final _Translations$changes$mergeEditor$trust$pl trust =
      _Translations$changes$mergeEditor$trust$pl._(_root);
  @override
  String get allResolved => 'wszystko rozwiązane';
  @override
  String get resolveEasy => 'rozwiąż proste konflikty';
  @override
  String get base => 'baza';
  @override
  String get cancel => 'anuluj';
  @override
  String get save => 'zapisz';
  @override
  String get complete => 'zakończ';
  @override
  String get nextFile => 'następny plik';
  @override
  String get edit => 'edytuj';
  @override
  String get auto => 'auto';
  @override
  String get undo => 'cofnij';
  @override
  late final _Translations$changes$mergeEditor$keyHints$pl keyHints =
      _Translations$changes$mergeEditor$keyHints$pl._(_root);
  @override
  String get favoredTooltip =>
      'strukturalnie preferowane przez analizę sprzężeń';
  @override
  String get newOnBothSides => '(nowe po obu stronach)';
  @override
  String writeFailed({required Object error}) =>
      'Nie udało się zapisać rozwiązanych plików: ${error}';
  @override
  String neighborsCoChanged({required Object changed, required Object total}) =>
      '${changed}/${total} sąsiadów zmieniło się wspólnie';
  @override
  String integrity({required Object pct}) => 'integralność ${pct}%';
  @override
  String reviewer({required Object name}) => 'recenzent: ${name}';
}

// Path: changes.conflictResolution
class _Translations$changes$conflictResolution$pl
    extends Translations$changes$conflictResolution$en {
  _Translations$changes$conflictResolution$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String noModelConfigured({required Object category}) =>
      'Nie skonfigurowano modelu dla „${category}”. Ustaw go w Ustawienia → AI.';
  @override
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} wrażliwy plik pominięto — rozwiąż ręcznie.',
        few: '${n} wrażliwe pliki pominięto — rozwiąż ręcznie.',
        many: '${n} wrażliwych plików pominięto — rozwiąż ręcznie.',
        other: '${n} wrażliwego pliku pominięto — rozwiąż ręcznie.',
      );
  @override
  String get couldNotReadFiles =>
      'Nie udało się odczytać żadnego pliku z konfliktem.';
  @override
  String blockedSecret({required Object secret}) =>
      'Zablokowano — plik z konfliktem wygląda, jakby zawierał ${secret}. Rozwiąż ręcznie.';
  @override
  String resolutionFailed({required Object error}) =>
      'Nie udało się rozwiązać: ${error}';
  @override
  String mergeResolutionLabel({
    required Object resolved,
    required Object total,
    required Object category,
  }) => '◇ rozwiązanie merge\'a · ${resolved}/${total} plików · ${category}';
  @override
  String conflictSummary({
    required Object op,
    required Object conflicts,
    required Object files,
  }) => '${op} · ${conflicts} w ${files}';
  @override
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} konflikt',
        few: '${n} konflikty',
        many: '${n} konfliktów',
        other: '${n} konfliktu',
      );
  @override
  String get mergeEditorButton => '⇋ edytor merge\'a';
  @override
  String get noAiModel => 'brak modelu AI';
  @override
  String get later => 'później';
  @override
  String get discard => 'odrzuć';
  @override
  String get resolveWithAi => '◇ rozwiąż z AI';
  @override
  String get otherModel => 'inny model';
  @override
  String withModel({required Object model}) => 'z ${model}';
}

// Path: changes.mergeFlow
class _Translations$changes$mergeFlow$pl
    extends Translations$changes$mergeFlow$en {
  _Translations$changes$mergeFlow$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$mergeFlow$op$pl op =
      _Translations$changes$mergeFlow$op$pl._(_root);
  @override
  String get pushFailed => 'Push nie powiódł się';
  @override
  String get rebasedAndPushed => 'Wykonano rebase i pushnięto.';
  @override
  String switchedTo({required Object name}) => 'Przełączono na ${name}.';
  @override
  String get switchFailed => 'Nie udało się przełączyć.';
  @override
  String switchedToCarried({required Object name}) =>
      'Przełączono na ${name} (zmiany przeniesione).';
  @override
  String get alreadyUpToDate => 'Już aktualne.';
  @override
  String merged({required Object upstream, required Object n}) =>
      'Zmergowano ${upstream} (${n} plików).';
  @override
  String get rebaseNotConverge => 'Rebase nie zbiegł się — rozwiąż ręcznie.';
  @override
  String get rebased => 'Wykonano rebase.';
  @override
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'Wykonano rebase (rozwiązano ${n} plik).',
        few: 'Wykonano rebase (rozwiązano ${n} pliki).',
        many: 'Wykonano rebase (rozwiązano ${n} plików).',
        other: 'Wykonano rebase (rozwiązano ${n} pliku).',
      );
  @override
  String get detachedHead =>
      'Nie można synchronizować: stan odłączonego HEAD. Najpierw przełącz się na gałąź.';
  @override
  String get publishFailed => 'Nie udało się opublikować.';
  @override
  String get noRemote =>
      'Nie skonfigurowano zdalnego. Dodaj jeden, aby opublikować tę gałąź.';
  @override
  String get failed => 'błąd';
}

// Path: changes.constellation
class _Translations$changes$constellation$pl
    extends Translations$changes$constellation$en {
  _Translations$changes$constellation$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get axisStructure => 'STRUKTURA';
  @override
  String get axisCoChange => 'WSPÓLNE ZMIANY';
  @override
  String get axisSpectralProfile => 'PROFIL SPEKTRALNY';
  @override
  String get axisPathSiblings => 'RODZEŃSTWO ŚCIEŻKI';
  @override
  String get axisDiffStructure => 'STRUKTURA DIFF';
  @override
  String get axisSpectral => 'SPEKTRALNY';
  @override
  String get titleUnsorted => 'NIEPOSORTOWANE';
  @override
  String get titleSingleton => 'POJEDYNCZY';
  @override
  String get titleMixed => 'MIESZANY';
  @override
  String get untie => 'rozwiąż';
  @override
  String get bind => 'zwiąż';
  @override
  String get emptyClusters => 'brak klastrów';
}

// Path: common.time
class _Translations$common$time$pl extends Translations$common$time$en {
  _Translations$common$time$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get now => 'teraz';
  @override
  String get justNow => 'przed chwilą';
  @override
  String get today => 'DZIŚ';
  @override
  String minutesAgo({required Object n}) => '${n} min temu';
  @override
  String hoursAgo({required Object n}) => '${n} godz temu';
  @override
  String daysAgo({required Object n}) => '${n} dni temu';
  @override
  String weeksAgo({required Object n}) => '${n} tyg temu';
  @override
  String monthsAgo({required Object n}) => '${n} mies temu';
  @override
  String yearsAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} lat temu',
        other: '${n} lat temu',
      );
  @override
  String minutesShort({required Object n}) => '${n} min';
  @override
  String hoursShort({required Object n}) => '${n} godz';
  @override
  String daysShort({required Object n}) => '${n} dni';
  @override
  String weeksShort({required Object n}) => '${n} tyg';
  @override
  String monthsShort({required Object n}) => '${n} mies';
  @override
  String yearsShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} lat',
        other: '${n} lat',
      );
  @override
  String commitMonthsShort({required Object n}) => '${n} mies';
  @override
  String get idle => 'bezczynny';
  @override
  String idleDays({required Object n}) => 'bezczynny ${n} dni';
  @override
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'bezczynny ${n} rok',
        few: 'bezczynny ${n} lata',
        many: 'bezczynny ${n} lat',
        other: 'bezczynny ${n} roku',
      );
  @override
  List<String> get monthAbbrevs => [
    'sty',
    'lut',
    'mar',
    'kwi',
    'maj',
    'cze',
    'lip',
    'sie',
    'wrz',
    'paź',
    'lis',
    'gru',
  ];
}

// Path: common.size
class _Translations$common$size$pl extends Translations$common$size$en {
  _Translations$common$size$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

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
class _Translations$diff$status$pl extends Translations$diff$status$en {
  _Translations$diff$status$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Ładowanie diff';
  @override
  String get loadingMessage => 'Odczytuję zmiany pliku.';
  @override
  String get unavailableTitle => 'Diff niedostępny';
  @override
  String get noChangesTitle => 'Brak zmian';
  @override
  String get noChangesMessage => 'Ten plik nie ma treści diff do wyświetlenia.';
}

// Path: diff.toolbar
class _Translations$diff$toolbar$pl extends Translations$diff$toolbar$en {
  _Translations$diff$toolbar$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get searchHint => 'szukaj w diff...';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} linia',
        few: '${n} linie',
        many: '${n} linii',
        other: '${n} linii',
      );
  @override
  String get blameLoading => 'blame...';
  @override
  String get blame => 'blame';
  @override
  String get wearMapOn => 'zużycie · wł';
  @override
  String get wearMapOnHint => 'mapa zużycia wł — kliknij, aby ukryć';
  @override
  String get wearMapOffHint => 'pokaż mapę zużycia (mapa cieplna aktywności)';
  @override
  String get trailBadge => '· ślad';
}

// Path: diff.hunkDropdown
class _Translations$diff$hunkDropdown$pl
    extends Translations$diff$hunkDropdown$en {
  _Translations$diff$hunkDropdown$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip => 'Przejdź do bloku zmian. Git nazywa je hunkami.';
  @override
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} zmiana',
        few: '${n} zmiany',
        many: '${n} zmian',
        other: '${n} zmiany',
      );
}

// Path: diff.trail
class _Translations$diff$trail$pl extends Translations$diff$trail$en {
  _Translations$diff$trail$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'ładowanie śladu...';
  @override
  String get noHistory => 'nie znaleziono historii';
  @override
  String get nowWorkingCopy => 'teraz · kopia robocza';
  @override
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class _Translations$diff$pinned$pl extends Translations$diff$pinned$en {
  _Translations$diff$pinned$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get loadingContext => 'ładowanie przypiętego kontekstu';
  @override
  String get pageManifold => 'Manifold';
  @override
  String get pageSignals => 'Sygnały';
  @override
  String get echoesTitle => 'Echa';
  @override
  String get technicalLedger => 'Rejestr techniczny';
  @override
  String get noSecondaryCues => 'Nie wykryto wtórnych wskazówek.';
  @override
  String get linkedPaths => 'Powiązane ścieżki';
  @override
  String moreCount({required Object n}) => '+${n} więcej';
  @override
  String get localSeam => 'Lokalny szew';
  @override
  String get sharedOwnership => 'współwłasność';
  @override
  String get historyWarmingUp => 'Historia się rozgrzewa';
  @override
  String echoesTotal({required Object n}) => '${n} ŁĄCZNIE';
  @override
  String get noEchoes => 'Brak ech w tym diff.';
  @override
  String openRelatedFile({required Object name}) =>
      'Otwórz powiązany plik ${name}';
  @override
  String inspectFile({required Object name}) => 'zbadaj ${name}';
  @override
  String get jumpEcho => 'do echa';
  @override
  String get copyLine => 'kopiuj linię';
  @override
  String get signalTempo => 'T';
  @override
  String get signalNovelty => 'N';
  @override
  String get signalReach => 'Z';
  @override
  late final _Translations$diff$pinned$tempo$pl tempo =
      _Translations$diff$pinned$tempo$pl._(_root);
  @override
  late final _Translations$diff$pinned$tone$pl tone =
      _Translations$diff$pinned$tone$pl._(_root);
  @override
  late final _Translations$diff$pinned$summary$pl summary =
      _Translations$diff$pinned$summary$pl._(_root);
  @override
  late final _Translations$diff$pinned$tightness$pl tightness =
      _Translations$diff$pinned$tightness$pl._(_root);
  @override
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept} (${tightness})';
  @override
  String get storyWhyThisMatters => 'Dlaczego to ważne';
  @override
  String get storyConfidence => 'Pewność';
  @override
  String get storySecondarySignal => 'Sygnał wtórny';
  @override
  String get storyNeighbourhood => 'Sąsiedztwo';
  @override
  String neighbourhoodDetail({required Object name}) =>
      'Ta linia znajduje się blisko ${name} w bieżącym polu bazy kodu.';
  @override
  String get propagationLane => 'Pas propagacji';
  @override
  String propagationLaneNamed({required Object lane}) =>
      'Pas propagacji: ${lane}';
  @override
  late final _Translations$diff$pinned$witness$pl witness =
      _Translations$diff$pinned$witness$pl._(_root);
  @override
  late final _Translations$diff$pinned$integrity$pl integrity =
      _Translations$diff$pinned$integrity$pl._(_root);
  @override
  late final _Translations$diff$pinned$related$pl related =
      _Translations$diff$pinned$related$pl._(_root);
  @override
  late final _Translations$diff$pinned$axis$pl axis =
      _Translations$diff$pinned$axis$pl._(_root);
}

// Path: diff.hunkHint
class _Translations$diff$hunkHint$pl extends Translations$diff$hunkHint$en {
  _Translations$diff$hunkHint$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String hiddenCount({required Object n}) => '${n} ukrytych';
  @override
  String get landing => 'lądowanie';
}

// Path: diff.binary
class _Translations$diff$binary$pl extends Translations$diff$binary$en {
  _Translations$diff$binary$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String tooLargeToPreview({required Object size}) =>
      '${size} MB (za duży, aby wyświetlić podgląd)';
  @override
  String get unableToLoadBlob => 'Nie udało się załadować blob';
  @override
  String get omittedKindMedia => 'media';
  @override
  String get omittedKindBinary => 'binarny';
  @override
  String omittedStub({required Object kind}) => '${kind} · ukryty';
}

// Path: diff.media
class _Translations$diff$media$pl extends Translations$diff$media$en {
  _Translations$diff$media$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get unableToDecodeImage => 'Nie udało się zdekodować obrazu';
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
  String get stateAdded => 'dodano';
  @override
  String get stateDeleted => 'usunięto';
  @override
  String get stateModified => 'zmieniono';
  @override
  String get fallbackFormatName => 'Binarny';
}

// Path: filament.severity
class _Translations$filament$severity$pl
    extends Translations$filament$severity$en {
  _Translations$filament$severity$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get critical => 'krytyczne';
  @override
  String get warn => 'ostrzeż.';
  @override
  String get info => 'info';
  @override
  String get joint => 'węzeł';
}

// Path: filament.kind
class _Translations$filament$kind$pl extends Translations$filament$kind$en {
  _Translations$filament$kind$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get staleValue => 'nieaktualna wartość';
  @override
  String get temporalShift => 'przesunięcie czasowe';
  @override
  String get contextInversion => 'inwersja kontekstu';
  @override
  String get contradictoryFlow => 'sprzeczny przepływ';
}

// Path: history.commitLede
class _Translations$history$commitLede$pl
    extends Translations$history$commitLede$en {
  _Translations$history$commitLede$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$semantics$pl semantics =
      _Translations$history$commitLede$semantics$pl._(_root);
}

// Path: history.seismograph
class _Translations$history$seismograph$pl
    extends Translations$history$seismograph$en {
  _Translations$history$seismograph$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get rootTrackLabel => '(korzeń)';
  @override
  String dirTrackLabel({required Object name}) => '(${name})';
  @override
  String moreLabel({required Object n}) => '+${n} więcej';
  @override
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} plik w ${path}/',
        few: '${n} pliki w ${path}/',
        many: '${n} plików w ${path}/',
        other: '${n} pliku w ${path}/',
      );
  @override
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'jeszcze ${n} plik',
        few: 'jeszcze ${n} pliki',
        many: 'jeszcze ${n} plików',
        other: 'jeszcze ${n} pliku',
      );
  @override
  String get breadcrumbAll => 'wszystkie';
  @override
  String breadcrumbCurrentFocus({required Object target}) =>
      'Bieżący fokus: ${target}';
  @override
  String get breadcrumbViewAllChanges =>
      'Pokaż wszystkie zmiany w tym commicie';
  @override
  String breadcrumbDrillUpTo({required Object target}) =>
      'Wejdź wyżej do ${target}';
  @override
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
    n,
    one: '${n} plik  +${adds}  -${dels}',
    few: '${n} pliki  +${adds}  -${dels}',
    many: '${n} plików  +${adds}  -${dels}',
    other: '${n} pliku  +${adds}  -${dels}',
  );
  @override
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} podkatalog',
        few: '${n} podkatalogi',
        many: '${n} podkatalogów',
        other: '${n} podkatalogu',
      );
  @override
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}, dodano ${adds}, usunięto ${dels}';
  @override
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
    n,
    one: '${n} plik, dodano ${adds}, usunięto ${dels}',
    few: '${n} pliki, dodano ${adds}, usunięto ${dels}',
    many: '${n} plików, dodano ${adds}, usunięto ${dels}',
    other: '${n} pliku, dodano ${adds}, usunięto ${dels}',
  );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} hunk',
        few: '${n} hunki',
        many: '${n} hunków',
        other: '${n} hunka',
      );
  @override
  String get largestChangeInView => 'największa zmiana w tym widoku';
  @override
  String get conflictedTag => 'konflikt';
  @override
  String get dirtyTag => 'brudny';
  @override
  String get drillInTag => 'wejdź głębiej';
  @override
  String get changeTypeRenamed => 'zmieniono nazwę';
  @override
  String get changeTypeCopied => 'skopiowano';
  @override
  String get changeTypeTypechange => 'zmiana typu';
  @override
  String get changeTypeConflict => 'konflikt';
  @override
  String get coreFile => 'plik rdzenia';
  @override
  String get staleFile => 'nieaktualny';
  @override
  String get filterPathHint => 'filtruj ścieżkę';
  @override
  String get escHint => 'esc';
}

// Path: history.worldline
class _Translations$history$worldline$pl
    extends Translations$history$worldline$en {
  _Translations$history$worldline$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get closeWorldline => 'Zamknij linię świata';
  @override
  String get dragToOpenWorldline => 'Przeciągnij, aby otworzyć linię świata';
}

// Path: history.contextMenu
class _Translations$history$contextMenu$pl
    extends Translations$history$contextMenu$en {
  _Translations$history$contextMenu$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get currentBranchFallback => 'bieżąca gałąź';
  @override
  String applyCommitOnto({required Object branch}) =>
      'Zastosuj zmiany commita na ${branch}';
  @override
  String revertCommitOn({required Object branch}) =>
      'Zrevertuj zmiany commita na ${branch}';
}

// Path: history.cherryPick
class _Translations$history$cherryPick$pl
    extends Translations$history$cherryPick$en {
  _Translations$history$cherryPick$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Cherry-pick wstrzymany. Dokończ pozostałe konflikty na stronie „Zmiany”.';
  @override
  String failed({required Object error}) =>
      'Cherry-pick nie powiódł się: ${error}';
  @override
  String pickedResolved({required Object short}) =>
      'Cherry-pick ${short} (konflikty rozwiązane)';
  @override
  String picked({required Object short}) => 'Cherry-pick ${short}';
}

// Path: history.revert
class _Translations$history$revert$pl extends Translations$history$revert$en {
  _Translations$history$revert$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Revert wstrzymany. Dokończ pozostałe konflikty na stronie „Zmiany”.';
  @override
  String failed({required Object error}) => 'Revert nie powiódł się: ${error}';
  @override
  String revertedResolved({required Object short}) =>
      'Zrevertowano ${short} (konflikty rozwiązane)';
  @override
  String reverted({required Object short}) => 'Zrevertowano ${short}';
}

// Path: history.reflog
class _Translations$history$reflog$pl extends Translations$history$reflog$en {
  _Translations$history$reflog$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get createBranchFromHere => 'Utwórz gałąź stąd…';
  @override
  String get copyCommitHash => 'Kopiuj hash commita';
  @override
  String get createBranchDialogTitle => 'Utwórz gałąź z wpisu reflog';
  @override
  String anchorLine({required Object short, required Object summary}) =>
      'Kotwica: ${short}  ·  ${summary}';
  @override
  String get branchNameHint => 'nazwa gałęzi';
  @override
  String get createAction => 'Utwórz';
  @override
  String createBranchFailed({required Object error}) =>
      'Nie udało się utworzyć gałęzi: ${error}';
  @override
  String branchCreatedAt({required Object name, required Object short}) =>
      'Gałąź „${name}” utworzona na ${short}.';
}

// Path: history.rebase
class _Translations$history$rebase$pl extends Translations$history$rebase$en {
  _Translations$history$rebase$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String firstCommitCannotBe({required Object action}) =>
      'Pierwszy commit nie może być ${action}';
  @override
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'Rebase ${n} commit',
        few: 'Rebase ${n} commity',
        many: 'Rebase ${n} commitów',
        other: 'Rebase ${n} commita',
      );
  @override
  String get resetLabel => 'reset';
  @override
  String get dragToReorderHint =>
      'przeciągaj, by zmienić kolejność, wybierz akcję dla każdego commita';
  @override
  String get newMessageHint => 'nowa wiadomość';
  @override
  String get runningEllipsis => '…';
  @override
  String get startRebase => 'Rozpocznij rebase';
}

// Path: history.inFlight
class _Translations$history$inFlight$pl
    extends Translations$history$inFlight$en {
  _Translations$history$inFlight$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'W TOKU';
  @override
  String get deskFallbackLabel => 'Desk';
}

// Path: historySurgery.chrome
class _Translations$historySurgery$chrome$pl
    extends Translations$historySurgery$chrome$en {
  _Translations$historySurgery$chrome$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chirurgia historii';
  @override
  String get alphaBadge => 'alpha';
  @override
  String get dryRunBadge => 'NA SUCHO';
}

// Path: historySurgery.select
class _Translations$historySurgery$select$pl
    extends Translations$historySurgery$select$en {
  _Translations$historySurgery$select$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get prompt => 'Wybierz pliki do usunięcia z historii';
  @override
  String selectedCount({required Object n}) => '${n} wybrano';
  @override
  String get searchHint => 'szukaj...';
  @override
  String get readingTree => 'odczyt drzewa...';
  @override
  String get continueDisabled => 'wybierz pliki, aby kontynuować';
  @override
  String get continueEnabled => 'kontynuuj →';
  @override
  String toPurgeCount({required Object n}) => '${n} do wyczyszczenia';
  @override
  String get analyzing => 'analizuję...';
  @override
  String get riskLow => 'niskie ryzyko';
  @override
  String get riskModerate => 'umiarkowane ryzyko';
  @override
  String get riskHigh => 'wysokie ryzyko';
  @override
  String get impactCommitsLabel => 'commity';
  @override
  String get impactBranchesLabel => 'gałęzie';
  @override
  String get impactWorktreesLabel => 'drzewa robocze';
  @override
  String get impactCouplingLabel => 'sprzężenie';
  @override
  String get impactCouplingIsland => 'wyspa';
  @override
  String impactCouplingNeighbors({required Object n}) => '${n} sąsiadów';
  @override
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class _Translations$historySurgery$understand$pl
    extends Translations$historySurgery$understand$en {
  _Translations$historySurgery$understand$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get heading => 'Jak to działa';
  @override
  String get backupTitle => 'Kopia zapasowa';
  @override
  String get backupBody =>
      'Każdy ref gałęzi i tagu jest kopiowany do zapasowej przestrzeni nazw przed jakąkolwiek zmianą. Jeśli coś pójdzie nie tak, jedno kliknięcie przywraca stan pierwotny.';
  @override
  String get rewriteTitle => 'Przepisywanie';
  @override
  String get rewriteBody =>
      'Każdy commit jest przechodzony od korzenia do wierzchołka. Dla każdego commita zawierającego docelowe pliki tworzony jest nowy commit z tymi plikami usuniętymi z drzewa. Łańcuchy rodziców są remapowane, aby zachować topologię. ';
  @override
  String rewriteSummary({required Object affected, required Object total}) =>
      'Przepisanych zostanie ${affected} z ${total} commitów.';
  @override
  String get updateRefsTitle => 'Aktualizacja refów';
  @override
  String get updateRefsBody =>
      'Wskaźniki gałęzi i tagów są przenoszone na nowe SHA commitów. Stare obiekty istnieją do czasu odśmiecania. ';
  @override
  String worktreesNeedRecheckout({required Object n}) =>
      'Twoje drzewa robocze (${n}) będą wymagać ponownego checkoutu.';
  @override
  String get noWorktreesAffected => 'Żadne drzewo robocze nie jest naruszone.';
  @override
  String get forcePushTitle => 'Wymuszony push';
  @override
  String get forcePushBody =>
      'Po zweryfikowaniu czyszczenia wybierasz, które gałęzie wymusić push. Używa --force-with-lease, więc bezpiecznie przerywa, jeśli ktoś w międzyczasie pushnął.';
  @override
  String get plumbingNote =>
      'W przeciwieństwie do filter-repo czy BFG, działa to w całości przez polecenia plumbing gita (cat-file, mktree, commit-tree, update-ref). Bez zewnętrznych zależności. Śledzenie zmian nazw idzie jednym łańcuchem na plik — jeśli plik został skopiowany, a obie kopie zmieniły nazwę niezależnie, zweryfikuj wynik czyszczenia po wykonaniu.';
  @override
  String get back => '← Wstecz';
  @override
  String get continueLabel => 'Rozumiem, kontynuuj →';
}

// Path: historySurgery.confirm
class _Translations$historySurgery$confirm$pl
    extends Translations$historySurgery$confirm$en {
  _Translations$historySurgery$confirm$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String commitsRewritten({required Object n}) =>
      'Przepisanych zostanie ${n} commitów';
  @override
  String get forcePushRequired =>
      'Dla zdalnych gałęzi wymagany będzie wymuszony push';
  @override
  String worktreesRecheckout({required Object n}) =>
      '${n} drzew roboczych będzie wymagać ponownego checkoutu';
  @override
  String stashesInvalid({required Object n}) =>
      '${n} schowków może stać się nieważnych';
  @override
  String get heading => 'Ta operacja przepisuje historię git';
  @override
  String get subheading =>
      'Nie można jej automatycznie cofnąć po wymuszonym pushu.';
  @override
  String typeHint({required Object word}) => 'wpisz ${word}';
  @override
  String get goBack => 'Wstecz';
  @override
  String get begin => 'Rozpocznij operację';
}

// Path: historySurgery.execute
class _Translations$historySurgery$execute$pl
    extends Translations$historySurgery$execute$en {
  _Translations$historySurgery$execute$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => 'Przygotowywanie...';
  @override
  String get backingUpRefs => 'Tworzę kopię refów...';
  @override
  String get rewritingCommits => 'Przepisuję commity...';
  @override
  String get updatingRefs => 'Aktualizuję refy...';
}

// Path: historySurgery.verify
class _Translations$historySurgery$verify$pl
    extends Translations$historySurgery$verify$en {
  _Translations$historySurgery$verify$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get complete => 'Operacja zakończona';
  @override
  String get failed => 'Operacja nie powiodła się';
  @override
  String get commitsRewrittenLabel => 'Przepisane commity';
  @override
  String get refsUpdatedLabel => 'Zaktualizowane refy';
  @override
  String get oldHeadLabel => 'Stary HEAD';
  @override
  String get newHeadLabel => 'Nowy HEAD';
  @override
  String get purgeVerifiedLabel => 'Czyszczenie zweryfikowane';
  @override
  String get purgeClean => 'czysto';
  @override
  String get purgeTracesRemain => 'POZOSTAŁY ŚLADY';
  @override
  String get displacedWorktrees => 'Przemieszczone drzewa robocze';
  @override
  String get undoSurgery => 'Cofnij operację';
  @override
  String get rolledBack => 'Wycofano do zapasowych refów.';
  @override
  String get done => 'Gotowe';
}

// Path: historySurgery.forcePush
class _Translations$historySurgery$forcePush$pl
    extends Translations$historySurgery$forcePush$en {
  _Translations$historySurgery$forcePush$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get pushing => 'push...';
  @override
  String get forcePushAll => 'Wymuś push wszystkich';
  @override
  String get confirmPush => 'potwierdź push';
  @override
  String get cancel => 'anuluj';
}

// Path: onboarding.nav
class _Translations$onboarding$nav$pl extends Translations$onboarding$nav$en {
  _Translations$onboarding$nav$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get back => 'Wstecz';
  @override
  String get continueLabel => 'Kontynuuj';
  @override
  String get letsGo => 'Zaczynajmy';
}

// Path: onboarding.naming
class _Translations$onboarding$naming$pl
    extends Translations$onboarding$naming$en {
  _Translations$onboarding$naming$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'czym to dla ciebie jest?';
  @override
  String get questionEmphasis => 'to';
  @override
  String get iAmPrefix => 'Jestem ';
  @override
  String get iAmSuffix => ' , twój osobisty klient Git.';
}

// Path: onboarding.theme
class _Translations$onboarding$theme$pl
    extends Translations$onboarding$theme$en {
  _Translations$onboarding$theme$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'przystrój ${name}.';
  @override
  String get themesHeader => 'MOTYWY';
  @override
  String get keybindingsHeader => 'SKRÓTY KLAWISZOWE';
  @override
  String get previewBadge => 'podgląd';
  @override
  String get useDefaults => 'użyj domyślnych';
}

// Path: onboarding.repo
class _Translations$onboarding$repo$pl extends Translations$onboarding$repo$en {
  _Translations$onboarding$repo$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'wskaż ${name} na coś.';
  @override
  String get later => 'zrobię to później';
  @override
  late final _Translations$onboarding$repo$doors$pl doors =
      _Translations$onboarding$repo$doors$pl._(_root);
  @override
  late final _Translations$onboarding$repo$cloneForm$pl cloneForm =
      _Translations$onboarding$repo$cloneForm$pl._(_root);
  @override
  late final _Translations$onboarding$repo$pickers$pl pickers =
      _Translations$onboarding$repo$pickers$pl._(_root);
  @override
  late final _Translations$onboarding$repo$errors$pl errors =
      _Translations$onboarding$repo$errors$pl._(_root);
}

// Path: onboarding.preview
class _Translations$onboarding$preview$pl
    extends Translations$onboarding$preview$en {
  _Translations$onboarding$preview$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$preview$panels$pl panels =
      _Translations$onboarding$preview$panels$pl._(_root);
  @override
  late final _Translations$onboarding$preview$sidebar$pl sidebar =
      _Translations$onboarding$preview$sidebar$pl._(_root);
  @override
  late final _Translations$onboarding$preview$changes$pl changes =
      _Translations$onboarding$preview$changes$pl._(_root);
  @override
  late final _Translations$onboarding$preview$history$pl history =
      _Translations$onboarding$preview$history$pl._(_root);
  @override
  late final _Translations$onboarding$preview$branches$pl branches =
      _Translations$onboarding$preview$branches$pl._(_root);
  @override
  late final _Translations$onboarding$preview$diff$pl diff =
      _Translations$onboarding$preview$diff$pl._(_root);
}

// Path: orrery.header
class _Translations$orrery$header$pl extends Translations$orrery$header$en {
  _Translations$orrery$header$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Orrery';
  @override
  String get modeScrub => 'Przewijanie';
  @override
  String get modeCompare => 'Porównanie';
  @override
  String get lodModules => 'Moduły';
  @override
  String get lodFiles => 'Pliki';
}

// Path: orrery.status
class _Translations$orrery$status$pl extends Translations$orrery$status$en {
  _Translations$orrery$status$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'Śledzę manifold przez historię…';
  @override
  String get loadError => 'Nie udało się odczytać historii tego repozytorium.';
  @override
  String get notEnoughHistory =>
      'Jeszcze za mało historii, aby wykreślić trajektorię.';
  @override
  String get notEnoughHistoryDetail =>
      'Orrery potrzebuje kilku commitów, aby coś wykreślić.';
}

// Path: orrery.legend
class _Translations$orrery$legend$pl extends Translations$orrery$legend$en {
  _Translations$orrery$legend$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get central => 'centralny';
  @override
  String get peripheral => 'peryferyjny';
}

// Path: orrery.node
class _Translations$orrery$node$pl extends Translations$orrery$node$en {
  _Translations$orrery$node$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get module => 'moduł';
  @override
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · ${n} plików';
  @override
  String fileFallback({required Object id}) => 'plik #${id}';
  @override
  String nodeFallback({required Object id}) => 'węzeł #${id}';
  @override
  String get rootModule => '(korzeń)';
}

// Path: orrery.milestone
class _Translations$orrery$milestone$pl
    extends Translations$orrery$milestone$en {
  _Translations$orrery$milestone$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get genesis => 'geneza';
  @override
  String get now => 'teraz';
  @override
  String get reorganized => 'zreorganizowany';
  @override
  String becameArchetype({required Object archetype}) =>
      'stał się ${archetype}';
  @override
  String get snapshot => 'migawka';
}

// Path: orrery.structure
class _Translations$orrery$structure$pl
    extends Translations$orrery$structure$en {
  _Translations$orrery$structure$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get forming => 'formuje się…';
  @override
  String get canonical => 'kanoniczny';
  @override
  String get connectivity => 'łączność';
  @override
  String get rigidity => 'sztywność';
  @override
  String get entropy => 'entropia';
}

// Path: orrery.rail
class _Translations$orrery$rail$pl extends Translations$orrery$rail$en {
  _Translations$orrery$rail$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get structureLabel => 'STRUKTURA';
  @override
  String get fieldLabel => 'POLE';
  @override
  String get findingsLabel => 'ZNALEZISKA';
  @override
  String get selectedLabel => 'WYBRANE';
  @override
  String get noFindings => 'W tej historii nie wykryto zdarzeń strukturalnych.';
}

// Path: orrery.selection
class _Translations$orrery$selection$pl
    extends Translations$orrery$selection$en {
  _Translations$orrery$selection$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get notPresent => 'Nieobecny w tym punkcie historii.';
  @override
  String get roleCentral =>
      'Centrum sprzężeń — zmiany tutaj rozchodzą się po całym systemie.';
  @override
  String get rolePeripheral =>
      'Peryferie — słabo sprzężony, zmienia się głównie sam.';
  @override
  String get roleMid => 'Środek struktury — umiarkowanie sprzężony.';
  @override
  String get driftOutward => ' Dryfuje na zewnątrz — rozprzęga się.';
  @override
  String get driftInward => ' Dryfuje do wewnątrz — integruje się.';
  @override
  String get driftHolding => ' Utrzymuje pozycję.';
}

// Path: orrery.findingKind
class _Translations$orrery$findingKind$pl
    extends Translations$orrery$findingKind$en {
  _Translations$orrery$findingKind$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get hub => 'WĘZEŁ';
  @override
  String get driftOut => 'DRYF NA ZEWNĄTRZ';
  @override
  String get driftIn => 'DRYF DO WEWNĄTRZ';
  @override
  String get tangle => 'SPLĄTYWANIE';
  @override
  String get clarify => 'KLAROWANIE';
  @override
  String get regime => 'REORG';
  @override
  String get thrash => 'MIOTANIE';
  @override
  String get reshuffle => 'PRZETASOWANIE';
  @override
  String get forecast => 'PROGNOZA';
}

// Path: orrery.findings
class _Translations$orrery$findings$pl extends Translations$orrery$findings$en {
  _Translations$orrery$findings$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get forecastSplit =>
      'Łączność spadała i jest blisko minimum — jeśli tak zostanie, baza kodu zmierza ku rozpadowi na dwie luźno sprzężone połowy. Zdecyduj teraz, czy taki był zamiar.';
  @override
  String get forecastConsolidate =>
      'Łączność wspinała się ku szczytowi — jeśli tak zostanie, baza kodu konsoliduje się w jedną ściśle sprzężoną masę. Uważaj, by nie stwardniała w monolit.';
  @override
  String thrash({required Object name}) =>
      '${name} wciąż jest reorganizowany tam i z powrotem — dużo strukturalnego zamieszania, mało realnego ruchu. Ustabilizuj jego sprzężenia albo przestań go ruszać.';
  @override
  String get reshuffle =>
      'Ten commit wyglądał rutynowo, ale po cichu przesunął, które pliki są centralne — ogólny kształt się utrzymał, a struktura pod nim się przetasowała. Sprawdź go dokładnie.';
  @override
  String hub({required Object name}) =>
      '${name} tkwi w strukturalnym rdzeniu — system reorganizuje się wokół niego. Traktuj zmiany tutaj jako o dużym promieniu rażenia.';
  @override
  String driftOut({required Object name}) =>
      '${name} oddryfował od rdzenia ku krawędzi — rozprzęga się z systemem. Albo jest wycofywany, albo po cichu gnije.';
  @override
  String driftIn({required Object name}) =>
      '${name} zmigrował ku rdzeniowi — staje się nośny. Upewnij się, że jest dobrze pokryty testami, zanim więcej od niego zależy.';
  @override
  String get regime =>
      'Baza kodu gwałtownie się tu zreorganizowała — jej łączność skoczyła. Sprawdź, co się odłączyło lub scaliło.';
  @override
  String get tangleTrend =>
      'W swojej historii baza kodu ciążyła ku bardziej splątanej strukturze — jej łączność staje się gęstsza i mniej modułowa.';
  @override
  String get clarifyTrend =>
      'W swojej historii baza kodu ciążyła ku czystszej strukturze — rozdziela się na wyraźniejsze moduły.';
}

// Path: orrery.anchor
class _Translations$orrery$anchor$pl extends Translations$orrery$anchor$en {
  _Translations$orrery$anchor$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get core => 'rdzeń';
  @override
  String get drift => 'dryf';
  @override
  String get trend => 'trend';
  @override
  String get thrash => 'miotanie';
}

// Path: orrery.compare
class _Translations$orrery$compare$pl extends Translations$orrery$compare$en {
  _Translations$orrery$compare$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'A → B';
  @override
  String get change => 'ZMIANA';
  @override
  String get movers => 'PRZESUNIĘCIA';
  @override
  String get noMovers => 'Między tymi klatkami żadne pliki się nie przesunęły.';
  @override
  String get badgeA => 'A';
  @override
  String get badgeB => 'B';
  @override
  String get deltaFiles => 'pliki';
  @override
  String get deltaConnectivity => 'łączność';
  @override
  String get deltaRigidity => 'sztywność';
  @override
  String get deltaEntropy => 'entropia';
  @override
  String get wayOutward => 'na zewnątrz';
  @override
  String get wayInward => 'do wewnątrz';
  @override
  String get wayShifted => 'przesunięty';
}

// Path: palette.prefixes
class _Translations$palette$prefixes$pl
    extends Translations$palette$prefixes$en {
  _Translations$palette$prefixes$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get askHint => 'ask: [pytanie]';
  @override
  String get nearHint => 'near: [plik]';
  @override
  String get whoHint => 'who: [plik]';
  @override
  String get logHint => 'log: [wiadomość]';
  @override
  String get runHint => 'run: [narzędzie]';
  @override
  String askLabel({required Object name, required Object body}) =>
      'Zapytaj ${name}: ${body}';
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
  }) => '${path} · ${count} recenzentów · ${touches} dotknięć';
  @override
  String whoTouchesLabel({required Object name, required Object touches}) =>
      '${name} — ${touches} dotknięć';
  @override
  String whoTouchesSubtitle({required Object path}) =>
      '${path} · brak zapisanych recenzentów';
}

// Path: palette.chips
class _Translations$palette$chips$pl extends Translations$palette$chips$en {
  _Translations$palette$chips$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get ai => 'AI';
  @override
  String get near => 'BLISKO';
  @override
  String get who => 'KTO';
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
  String get hot => 'GOR';
  @override
  String get key => 'KLAW';
  @override
  String get web => 'WEB';
  @override
  String get sys => 'SYS';
  @override
  String get clip => 'SCHOW';
  @override
  String get sync => 'SYNC';
  @override
  String get force => 'FORCE';
  @override
  String get pr => 'PR';
  @override
  String get draft => 'SZKIC';
  @override
  String get undo => 'COFNIJ';
  @override
  String get thm => 'MOTYW';
  @override
  String get ver => 'WER';
  @override
  String get desk => 'DESK';
  @override
  String get det => 'ODŁ';
  @override
  String get main => 'MAIN';
  @override
  String get head => 'HEAD';
  @override
  String get gone => 'BRAK';
  @override
  String get remote => 'ZDAL';
  @override
  String get local => 'LOK';
  @override
  String get an => 'AN';
  @override
  String get lw => 'LW';
}

// Path: palette.predictive
class _Translations$palette$predictive$pl
    extends Translations$palette$predictive$en {
  _Translations$palette$predictive$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String momentumSuffix({required Object percent}) => '${percent}% rozpędu';
}

// Path: palette.topTouched
class _Translations$palette$topTouched$pl
    extends Translations$palette$topTouched$en {
  _Translations$palette$topTouched$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object count, required Object path}) =>
      '${count} dotknięć · ${path}';
}

// Path: palette.coherence
class _Translations$palette$coherence$pl
    extends Translations$palette$coherence$en {
  _Translations$palette$coherence$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String label({required Object percent}) => 'Spójność indeksu: ${percent}%';
  @override
  String subtitle({required Object count}) => '${count} plików';
}

// Path: palette.keystone
class _Translations$palette$keystone$pl
    extends Translations$palette$keystone$en {
  _Translations$palette$keystone$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object path, required Object score}) =>
      '${path} · zwornik ${score}';
}

// Path: palette.repoSub
class _Translations$palette$repoSub$pl extends Translations$palette$repoSub$en {
  _Translations$palette$repoSub$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String changes({required Object name}) => 'Zmiany w ${name}';
  @override
  String history({required Object name}) => 'Historia w ${name}';
  @override
  String branches({required Object name}) => 'Gałęzie w ${name}';
  @override
  String terminal({required Object name}) => 'Terminal w ${name}';
  @override
  String generateCommit({required Object name}) => 'Wygeneruj commit · ${name}';
  @override
  String reviewChanges({required Object name}) => 'Przegląd zmian w ${name}';
  @override
  String muse({required Object name}) => 'Muse w ${name}';
}

// Path: palette.desks
class _Translations$palette$desks$pl extends Translations$palette$desks$en {
  _Translations$palette$desks$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get mainWorktree => 'główne drzewo robocze';
  @override
  String get detached => 'odłączony';
  @override
  String dirty({required Object count}) => '${count} brudnych';
}

// Path: palette.actions
class _Translations$palette$actions$pl extends Translations$palette$actions$en {
  _Translations$palette$actions$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get openInBrowser => 'Otwórz w przeglądarce';
  @override
  String get terminal => 'Terminal';
  @override
  String get revealInFiles => 'Pokaż w plikach';
  @override
  String get copyPath => 'Kopiuj ścieżkę';
  @override
  String get copyBranch => 'Kopiuj gałąź';
}

// Path: palette.tools
class _Translations$palette$tools$pl extends Translations$palette$tools$en {
  _Translations$palette$tools$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String launch({required Object label}) => 'Uruchom ${label}';
}

// Path: palette.gitCommands
class _Translations$palette$gitCommands$pl
    extends Translations$palette$gitCommands$en {
  _Translations$palette$gitCommands$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get fetch => 'Fetch';
  @override
  String get pull => 'Pull';
  @override
  String pullBehind({required Object count}) => '${count} w tyle';
  @override
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';
  @override
  String get push => 'Push';
  @override
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} commit',
        few: '${n} commity',
        many: '${n} commitów',
        other: '${n} commita',
      );
  @override
  String pushCommitsUpstream({
    required Object commits,
    required Object upstream,
  }) => '${commits} do ${upstream}';
  @override
  String get forcePush => 'Wymuś push';
  @override
  String forcePushNoUpstream({required Object branch}) =>
      'Nie można wymusić push: dla ${branch} nie ustawiono upstream.';
  @override
  String get commit => 'Commit';
  @override
  String get stageAll => 'Dodaj wszystko do indeksu';
  @override
  String get unstageAll => 'Usuń wszystko z indeksu';
  @override
  String get discardAll => 'Odrzuć wszystko';
  @override
  String get createBranch => 'Utwórz gałąź';
  @override
  String get deleteBranch => 'Usuń gałąź';
  @override
  String get renameBranch => 'Zmień nazwę gałęzi';
  @override
  String get stash => 'Stash';
  @override
  String get stashPop => 'Wyjmij stash';
  @override
  String get stashApply => 'Zastosuj stash';
  @override
  String get stashDrop => 'Porzuć stash';
  @override
  String get createTag => 'Utwórz tag';
  @override
  String get cherryPick => 'Cherry-pick';
  @override
  String get revert => 'Revert';
  @override
  String get stashConflictMessage =>
      'Stash zastosowany z konfliktami. Rozwiąż je na stronie „Zmiany”.';
}

// Path: palette.pr
class _Translations$palette$pr$pl extends Translations$palette$pr$en {
  _Translations$palette$pr$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get create => 'Utwórz PR';
  @override
  String get merge => 'Merge PR';
  @override
  String get markReady => 'Oznacz PR jako gotowy';
}

// Path: palette.ai
class _Translations$palette$ai$pl extends Translations$palette$ai$en {
  _Translations$palette$ai$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get generateCommit => 'Wygeneruj commit';
  @override
  String get reviewChanges => 'Przegląd zmian';
  @override
  String get runMuse => 'Uruchom Muse';
  @override
  String debugRepo({required Object name}) => 'Debuguj ${name}';
  @override
  String get describeSymptom => 'opisz objaw';
  @override
  String viewResult({required Object kind}) => 'Zobacz ${kind}';
  @override
  String get unseenResult => 'nieobejrzany wynik';
  @override
  String runningResult({required Object kind}) => 'AI: ${kind}…';
  @override
  String get running => 'wykonuje się';
  @override
  String get kindCommitMessage => 'Wiadomość commita';
  @override
  String get kindCodeReview => 'Przegląd kodu';
  @override
  String get kindMuseResult => 'Wynik Muse';
  @override
  String get kindPresentation => 'Prezentacja';
  @override
  String get kindDebugResult => 'Wynik debugowania';
}

// Path: palette.undo
class _Translations$palette$undo$pl extends Translations$palette$undo$en {
  _Translations$palette$undo$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String cancel({required Object label}) => 'Anuluj: ${label}';
}

// Path: palette.navigation
class _Translations$palette$navigation$pl
    extends Translations$palette$navigation$en {
  _Translations$palette$navigation$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get changes => 'Zmiany';
  @override
  String get history => 'Historia';
  @override
  String get branches => 'Gałęzie';
  @override
  String get xray => 'X-Ray';
  @override
  String get settings => 'Ustawienia';
  @override
  String get refresh => 'Odśwież';
}

// Path: palette.settings
class _Translations$palette$settings$pl
    extends Translations$palette$settings$en {
  _Translations$palette$settings$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get reduceMotion => 'Ogranicz animacje';
  @override
  String get animateLogoUnfocused => 'Animuj logo poza fokusem';
  @override
  String get instantBlameHover => 'Natychmiastowy blame przy najechaniu';
  @override
  String get autoSelectChanges => 'Automatyczny wybór zmian';
  @override
  String get fetchOnlineIssues => 'Pobieraj zgłoszenia online';
  @override
  String get rememberWip => 'Pamiętaj pracę w toku';
  @override
  String get hideAiFeatures => 'Ukryj funkcje AI';
  @override
  String get crashReporting => 'Raportowanie awarii';
  @override
  String get aiReadOnly => 'AI tylko do odczytu';
  @override
  String get stashCabinetExpanded => 'Szafka stash rozwinięta';
  @override
  String get fileSortInverted => 'Odwrócone sortowanie plików';
}

// Path: palette.info
class _Translations$palette$info$pl extends Translations$palette$info$en {
  _Translations$palette$info$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class _Translations$palette$debug$pl extends Translations$palette$debug$en {
  _Translations$palette$debug$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get engineStatus => 'Status silnika';
  @override
  String get engineStatusSubtitle =>
      'Diagnostyka silnika spektralnego LogosGit';
  @override
  String get fileCoupling => 'Sprzężenie plików';
  @override
  String get fileCouplingSubtitle =>
      'Najbliżsi sąsiedzi po wspólnych zmianach dla plików w indeksie';
  @override
  String get themeSpecimen => 'Próbka motywu';
  @override
  String get themeSpecimenSubtitle =>
      'Wszystkie kolory, ikony, poziomy tekstu i geometria';
}

// Path: palette.dev
class _Translations$palette$dev$pl extends Translations$palette$dev$en {
  _Translations$palette$dev$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get testMergeEditor => 'Test edytora merge\'a';
  @override
  String get testHistorySurgery => 'Test chirurgii historii';
  @override
  String get back => 'wstecz';
  @override
  String get cancel => 'anuluj';
  @override
  String get buildingConflicts => 'buduję testowe konflikty z historii…';
}

// Path: palette.historySurgery
class _Translations$palette$historySurgery$pl
    extends Translations$palette$historySurgery$en {
  _Translations$palette$historySurgery$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Chirurgia historii';
  @override
  String get subtitle => 'Przepisz historię, aby trwale usunąć pliki';
}

// Path: palette.orrery
class _Translations$palette$orrery$pl extends Translations$palette$orrery$en {
  _Translations$palette$orrery$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Orrery';
  @override
  String get subtitle =>
      'Przewiń strukturalną historię repozytorium przez manifold';
}

// Path: palette.command
class _Translations$palette$command$pl extends Translations$palette$command$en {
  _Translations$palette$command$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String complete({required Object label}) => '${label} — zakończono';
  @override
  String failed({required Object label, required Object message}) =>
      '${label} — błąd: ${message}';
  @override
  String get copy => 'Kopiuj';
}

// Path: palette.search
class _Translations$palette$search$pl extends Translations$palette$search$en {
  _Translations$palette$search$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get hintDefault => 'szukaj wszędzie...';
  @override
  String get hintElevated => 'rozszerzone — wszystkie akcje';
  @override
  String get emptyTypeToSearch => 'pisz, aby szukać';
  @override
  String get emptyNoResults => 'brak wyników';
}

// Path: palette.wick
class _Translations$palette$wick$pl extends Translations$palette$wick$en {
  _Translations$palette$wick$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'wick';
  @override
  String get coupledFallback => 'sprzężony';
}

// Path: palette.gitCache
class _Translations$palette$gitCache$pl
    extends Translations$palette$gitCache$en {
  _Translations$palette$gitCache$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'bieżący';
  @override
  String get staged => 'w indeksie';
  @override
  String get modified => 'zmieniony';
}

// Path: releaseNotes.about
class _Translations$releaseNotes$about$pl
    extends Translations$releaseNotes$about$en {
  _Translations$releaseNotes$about$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$releaseNotes$about$whyFlutter$pl whyFlutter =
      _Translations$releaseNotes$about$whyFlutter$pl._(_root);
  @override
  late final _Translations$releaseNotes$about$spectralEngine$pl spectralEngine =
      _Translations$releaseNotes$about$spectralEngine$pl._(_root);
  @override
  late final _Translations$releaseNotes$about$whereGoing$pl whereGoing =
      _Translations$releaseNotes$about$whereGoing$pl._(_root);
}

// Path: releaseNotes.legal
class _Translations$releaseNotes$legal$pl
    extends Translations$releaseNotes$legal$en {
  _Translations$releaseNotes$legal$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get copyright => '© 2026 Woflo Labs';
  @override
  String get license =>
      'GPL-3.0-or-later · rdzeń badawczy community-source WLCSL · bez gwarancji';
}

// Path: repoSummary.backbone
class _Translations$repoSummary$backbone$pl
    extends Translations$repoSummary$backbone$en {
  _Translations$repoSummary$backbone$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}` (${lines}) — ${region}';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} linia',
        few: '${n} linie',
        many: '${n} linii',
        other: '${n} linii',
      );
  @override
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class _Translations$repoSummary$glance$pl
    extends Translations$repoSummary$glance$en {
  _Translations$repoSummary$glance$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} plik.',
        few: '${n} pliki.',
        many: '${n} plików.',
        other: '${n} pliku.',
      );
  @override
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} linia (${bytes}).',
        few: '${n} linie (${bytes}).',
        many: '${n} linii (${bytes}).',
        other: '${n} linii (${bytes}).',
      );
  @override
  String roles({required Object parts}) => 'Role — ${parts}.';
  @override
  String showingNofM({required Object active, required Object total}) =>
      'Pokazano ${active} z ${total} plików, wg centralności strukturalnej.';
}

// Path: repoSummary.heading
class _Translations$repoSummary$heading$pl
    extends Translations$repoSummary$heading$en {
  _Translations$repoSummary$heading$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get atAGlance => 'W skrócie';
  @override
  String get core => 'Rdzeń';
  @override
  String get gettingStarted => 'Od czego zacząć';
  @override
  String get regions => 'Regiony';
  @override
  String get shape => 'Kształt';
}

// Path: repoSummary.pitch
class _Translations$repoSummary$pitch$pl
    extends Translations$repoSummary$pitch$en {
  _Translations$repoSummary$pitch$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String empty({required Object detail}) =>
      'Repozytorium bez czytelnych plików tekstowych${detail}.';
  @override
  String emptyBinary({required Object n}) => '${n} binarnych';
  @override
  String emptyUnreadable({required Object n}) => '${n} nieczytelnych';
  @override
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'Repozytorium z ${n} aktywnym plikiem.',
        few: 'Repozytorium z ${n} aktywnymi plikami.',
        many: 'Repozytorium z ${n} aktywnymi plikami.',
        other: 'Repozytorium z ${n} aktywnego pliku.',
      );
  @override
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'Repozytorium z ${n} aktywnym plikiem — ${regions}.',
        few: 'Repozytorium z ${n} aktywnymi plikami — ${regions}.',
        many: 'Repozytorium z ${n} aktywnymi plikami — ${regions}.',
        other: 'Repozytorium z ${n} aktywnego pliku — ${regions}.',
      );
}

// Path: repoSummary.region
class _Translations$repoSummary$region$pl
    extends Translations$repoSummary$region$en {
  _Translations$repoSummary$region$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String bodyCommonDir({required Object dir}) => 'Wszystko w `${dir}`.';
  @override
  String get bodyCommonDirSeparator => ' ';
  @override
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '1 w rdzeniu',
        few: '${n} w rdzeniu',
        many: '${n} w rdzeniu',
        other: '${n} w rdzeniu',
      );
  @override
  String get bodyCoreSeparator => ', ';
  @override
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'Jeden plik',
        few: '${n} pliki',
        many: '${n} plików',
        other: '${n} pliku',
      );
  @override
  String connectsTo({required Object linked}) => 'Łączy się z: ${linked}.';
  @override
  String get filesLabel => 'Pliki:';
}

// Path: repoSummary.shape
class _Translations$repoSummary$shape$pl
    extends Translations$repoSummary$shape$en {
  _Translations$repoSummary$shape$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get bulk =>
      'Gęsto połączona baza kodu: większość plików należy do jednego dużego sąsiedztwa wspólnych zmian.';
  @override
  String get crystalline =>
      'Baza kodu w kształcie sieci krystalicznej: jednorodne, regularne sprzężenia między plikami z przewidywalną strukturą lokalną.';
  @override
  String get goe =>
      'Bogato połączona baza kodu: sprzężenia rozproszone po plikach bez dominującego kręgosłupa.';
  @override
  String get modular =>
      'Modułowa baza kodu: kilka spójnych regionów z ograniczonym sprzężeniem między nimi. Praca w jednym regionie rzadko narusza inny.';
  @override
  String get poisson =>
      'Luźno sprzężona baza kodu: pliki rozwijają się głównie osobno, z okazjonalnymi wspólnymi zmianami.';
  @override
  String get tree =>
      'Baza kodu w kształcie drzewa: jeden dominujący kręgosłup z zależnymi gałęziami. Zmiany zwykle rozchodzą się od rdzenia na zewnątrz.';
}

// Path: settings.language
class _Translations$settings$language$pl
    extends Translations$settings$language$en {
  _Translations$settings$language$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Język';
  @override
  String get summary =>
      'Język interfejsu tej aplikacji. Wyjście git, logi i diagnostyka pozostają po angielsku, aby zgłoszenia błędów były przeszukiwalne.';
  @override
  String get label => 'JĘZYK INTERFEJSU';
  @override
  String get systemDefault => 'Systemowy domyślny';
  @override
  String systemDefaultDetail({required Object resolved}) =>
      'Zgodny z językiem systemu (${resolved})';
  @override
  String get disclosureSource => 'Język źródłowy, napisany przez twórców.';
  @override
  String disclosureAi({required Object model}) =>
      'Tłumaczenie maszynowe od ${model}, jeszcze nie sprawdzone przez człowieka. Poprawki mile widziane.';
  @override
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) =>
      'Tłumaczenie maszynowe od ${model}. ${percent}% sprawdzone przez człowieka.';
  @override
  String get disclosureHuman =>
      'Tłumaczenie ludzkie, utrzymywane przez społeczność.';
  @override
  String reviewedBy({required Object names}) => 'Sprawdzone przez: ${names}.';
}

// Path: settings.sectionLabels
class _Translations$settings$sectionLabels$pl
    extends Translations$settings$sectionLabels$en {
  _Translations$settings$sectionLabels$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get preferences => 'Preferencje';
  @override
  String get shortcuts => 'Skróty';
  @override
  String get behaviour => 'Zachowanie';
  @override
  String get aiProviders => 'Dostawcy AI';
  @override
  String get modelSlots => 'Sloty modeli';
  @override
  String get tools => 'Narzędzia';
  @override
  String get diagnostics => 'Diagnostyka';
  @override
  String get offenders => 'Winowajcy';
  @override
  String get release => 'Wydanie';
}

// Path: settings.errors
class _Translations$settings$errors$pl extends Translations$settings$errors$en {
  _Translations$settings$errors$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get saveGuardrailProfile => 'Nie udało się zapisać profilu barierek.';
  @override
  String get saveRetentionPolicy =>
      'Nie udało się zapisać polityki przechowywania.';
  @override
  String get saveUpdateChannel => 'Nie udało się zapisać kanału aktualizacji.';
  @override
  String get saveModelSelection => 'Nie udało się zapisać wyboru modelu AI.';
  @override
  String get saveModelAlias => 'Nie udało się zapisać aliasu modelu.';
  @override
  String get saveCommitMessageModelSlot =>
      'Nie udało się zapisać slotu modelu wiadomości commitów.';
  @override
  String get saveReviewModelSlot =>
      'Nie udało się zapisać slotu modelu przeglądu.';
  @override
  String get saveCommitMessageCustomPrompt =>
      'Nie udało się zapisać własnego promptu wiadomości commitów.';
  @override
  String get saveReviewGuide => 'Nie udało się zapisać przewodnika przeglądu.';
  @override
  String get saveMuseNotes => 'Nie udało się zapisać notatek muzy.';
  @override
  String get saveReviewDoubleCheck =>
      'Nie udało się zapisać trybu podwójnej weryfikacji przeglądu.';
  @override
  String get saveApiPiggybackCli =>
      'Nie udało się zapisać CLI dla piggybacku API.';
  @override
  String get saveCliTimeout => 'Nie udało się zapisać limitu czasu CLI.';
  @override
  String get stopAllCli => 'Nie udało się zatrzymać działających sesji CLI.';
  @override
  String clearLocalData({required Object error}) =>
      'Nie udało się wyczyścić lokalnych danych: ${error}';
}

// Path: settings.promptStatus
class _Translations$settings$promptStatus$pl
    extends Translations$settings$promptStatus$en {
  _Translations$settings$promptStatus$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get editing => 'Edytowanie';
  @override
  String get saving => 'Zapisywanie';
  @override
  String get saveFailed => 'Zapis nie powiódł się';
}

// Path: settings.clearData
class _Translations$settings$clearData$pl
    extends Translations$settings$clearData$en {
  _Translations$settings$clearData$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => 'Wyczyść lokalne dane';
  @override
  String get clear => 'Wyczyść';
  @override
  String get confirmDiagnostics =>
      'Wyczyścić lokalne próbki diagnostyki i pomiary wydajności?';
  @override
  String get confirmAudit => 'Wyczyścić lokalne rekordy metadanych audytu AI?';
  @override
  String get confirmAll =>
      'Wyczyścić wszystkie lokalne próbki diagnostyki i rekordy metadanych audytu AI?';
  @override
  String get confirmWipeAll =>
      'Wymazać wszystkie lokalne dane aplikacji — w tym listę ostatnich repozytoriów — i wyjść? Twoje rzeczywiste repozytoria git na dysku nie zostaną naruszone.';
  @override
  String get confirmReset =>
      'Zresetować lokalne dane aplikacji i wyjść?\n\nUstawienia, motyw, onboarding, preferencje AI, telemetria i cache engramów zostaną wyczyszczone. Lista ostatnich repozytoriów przetrwa.';
}

// Path: settings.guardrailMacro
class _Translations$settings$guardrailMacro$pl
    extends Translations$settings$guardrailMacro$en {
  _Translations$settings$guardrailMacro$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'luźno';
  @override
  String get balanced => 'zrównoważone';
  @override
  String get strict => 'ściśle';
  @override
  String get paranoid => 'paranoicznie';
}

// Path: settings.guardrails
class _Translations$settings$guardrails$pl
    extends Translations$settings$guardrails$en {
  _Translations$settings$guardrails$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Barierki';
  @override
  String get summary => 'Jak uważna jest automatyka w całym doświadczeniu.';
}

// Path: settings.appearance
class _Translations$settings$appearance$pl
    extends Translations$settings$appearance$en {
  _Translations$settings$appearance$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Wygląd';
  @override
  String get summary => 'Globalny nastrój i atmosfera interfejsu.';
}

// Path: settings.retention
class _Translations$settings$retention$pl
    extends Translations$settings$retention$en {
  _Translations$settings$retention$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Przechowywanie danych lokalnych';
  @override
  String get summaryDiagnostics => 'Polityka przechowywania diagnostyki.';
  @override
  String get summaryWithAudit =>
      'Polityka przechowywania diagnostyki i audytu AI.';
  @override
  String get unitDays => 'dni';
  @override
  String get unitMb => 'MB';
  @override
  String get includesNote =>
      'Obejmuje diagnostykę, pomiary wydajności i metadane.';
}

// Path: settings.navigation
class _Translations$settings$navigation$pl
    extends Translations$settings$navigation$en {
  _Translations$settings$navigation$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Nawigacja i dynamika';
  @override
  String get summaryShortcuts => 'Skróty i zachowanie interfejsu.';
  @override
  String get summaryWithAi => 'Skróty, zachowanie interfejsu i routing AI.';
}

// Path: settings.behaviour
class _Translations$settings$behaviour$pl
    extends Translations$settings$behaviour$en {
  _Translations$settings$behaviour$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Dynamika zachowań';
}

// Path: settings.retentionClear
class _Translations$settings$retentionClear$pl
    extends Translations$settings$retentionClear$en {
  _Translations$settings$retentionClear$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get diag => 'Diag';
  @override
  String get audit => 'Audyt';
  @override
  String get all => 'Wszystko';
  @override
  String get clearsHint => '<-- czyści';
}

// Path: settings.channels
class _Translations$settings$channels$pl
    extends Translations$settings$channels$en {
  _Translations$settings$channels$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get stable => 'STABLE';
  @override
  String get beta => 'BETA';
  @override
  String get dev => 'DEV';
}

// Path: settings.pollResult
class _Translations$settings$pollResult$pl
    extends Translations$settings$pollResult$en {
  _Translations$settings$pollResult$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get upToDate => 'aktualne';
  @override
  String updateAvailable({required Object version}) => 'dostępna ${version}';
  @override
  String get notConfigured => 'brak serwera aktualizacji';
  @override
  String notFound({required Object channel}) => 'brak wydań ${channel}';
  @override
  String get unreachable => 'nieosiągalne';
  @override
  String get badManifest => 'zły manifest';
}

// Path: settings.keybindingProfile
class _Translations$settings$keybindingProfile$pl
    extends Translations$settings$keybindingProfile$en {
  _Translations$settings$keybindingProfile$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Profil skrótów klawiszowych';
  @override
  String get porcelain => 'Porcelain';
  @override
  String get numeric => 'Numeryczny';
  @override
  String get porcelainDescription => 'Skróty akordowe (G, potem C, H, B…).';
  @override
  String get numericDescription =>
      'Skróty numeryczne jednym klawiszem (1, 2, 3…).';
}

// Path: settings.apiKeys
class _Translations$settings$apiKeys$pl
    extends Translations$settings$apiKeys$en {
  _Translations$settings$apiKeys$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get keyHintDefault => 'klucz api';
  @override
  String get endpointHint => 'endpoint';
  @override
  String get test => 'Test';
  @override
  String get hide => 'Ukryj';
  @override
  String get show => 'Pokaż';
}

// Path: settings.shortcuts
class _Translations$settings$shortcuts$pl
    extends Translations$settings$shortcuts$en {
  _Translations$settings$shortcuts$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get navigate => 'nawigacja';
  @override
  String get staging => 'indeks';
  @override
  String get branchesPrs => 'gałęzie i PR';
  @override
  String get modifiers => 'modyfikatory';
  @override
  String get changes => 'Zmiany';
  @override
  String get history => 'Historia';
  @override
  String get branches => 'Gałęzie';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Przełącz (zawsze)';
  @override
  String get search => 'Szukaj';
  @override
  String get dismiss => 'Zamknij';
  @override
  String get refresh => 'Odśwież';
  @override
  String get shortcuts => 'Skróty';
  @override
  String get nextChange => 'Nast. zmiana';
  @override
  String get prevChange => 'Poprz. zmiana';
  @override
  String get toggleLine => 'Przełącz linię';
  @override
  String get toggleHunk => 'Przełącz hunk';
  @override
  String get toggleFile => 'Przełącz plik';
  @override
  String get pinContext => 'Przypnij kontekst';
  @override
  String get commit => 'Commit';
  @override
  String get acceptHint => 'Przyjmij podpowiedź';
  @override
  String get undo => 'Cofnij';
  @override
  String get navigateRow => 'Nawigacja';
  @override
  String get expand => 'Rozwiń';
  @override
  String get checkout => 'Checkout';
  @override
  String get approve => 'Zatwierdź';
  @override
  String get requestChanges => 'Poproś o zmiany';
  @override
  String get selectRange => 'Zaznacz zakres';
  @override
  String get extendedMenu => 'Menu rozszerzone';
}

// Path: settings.toggles
class _Translations$settings$toggles$pl
    extends Translations$settings$toggles$en {
  _Translations$settings$toggles$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get aiReadOnlyLabel => 'Tryb AI tylko do odczytu';
  @override
  String get aiReadOnlyDescription =>
      'Uniemożliwia AI automatyczne pisanie lub dodawanie zmian do indeksu.';
  @override
  String get logoMotionLabel => 'Logo animuje się poza aktywną kartą';
  @override
  String get logoMotionDescriptionEnabled =>
      'Jest zaprojektowane, by być wydajne, nie rań jego uczuć';
  @override
  String get logoMotionDescriptionDisabled => ':(';
  @override
  String get rememberWipLabel => 'Pamiętaj pracę w toku';
  @override
  String get rememberWipDescription =>
      'Zachowuj szkice commitów i wybór plików między sesjami.';
  @override
  String get stashCabinetLabel => 'Szafka stash otwarta na starcie';
  @override
  String get stashCabinetDescription =>
      'Domyślnie pokazuj szufladę kartoteki otwartą, gdy repozytorium ma półki.';
  @override
  String get instantBlameLabel => 'Natychmiastowy blame przy najechaniu';
  @override
  String get instantBlameDescription =>
      'Pomiń opóźnienie 180 ms przed pokazaniem informacji blame na linii diff.';
  @override
  String get autoSelectLabel => 'Automatyczny wybór nowych zmian';
  @override
  String get autoSelectDescription =>
      'Nowo śledzone lub zmienione pliki są automatycznie dodawane do wyboru do commita.';
  @override
  String get changeIdLabel => 'Zapisuj nagłówki change-id';
  @override
  String get changeIdDescription =>
      'Dodaje nowym commitom nagłówek tożsamości change-id (konwencja Jujutsu, GitButler i Gerrit). Każdy commit jest przepisywany raz, tuż po utworzeniu.';
  @override
  String get fetchIssuesLabel =>
      'Pobieraj zgłoszenia online przy ładowaniu gałęzi';
  @override
  String get fetchIssuesDescription =>
      'Podciągaj szczegóły PR i zgłoszeń od twojego dostawcy git w tle, gdy otwiera się strona gałęzi.';
  @override
  String get hateAiLabel => 'Nienawidzę AI';
  @override
  String get hateAiDescription =>
      'Wygnaj wszystkie funkcje oparte na LLM. Logos działa dalej, bo to tylko matematyka spektralna.';
}

// Path: settings.diffDiffability
class _Translations$settings$diffDiffability$pl
    extends Translations$settings$diffDiffability$en {
  _Translations$settings$diffDiffability$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'diff-owalność diff';
}

// Path: settings.modelSlots
class _Translations$settings$modelSlots$pl
    extends Translations$settings$modelSlots$en {
  _Translations$settings$modelSlots$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get loadingProviders => 'Ładowanie dostawców...';
  @override
  String get refreshingProviders => 'Odświeżam diagnostykę dostawców...';
  @override
  String get routeDescription =>
      'Zmień nazwę i skieruj konfiguracje na dowolny wykryty model dostawcy.';
  @override
  String get loadingCategories => 'Ładowanie kategorii modeli...';
  @override
  String get noOptions =>
      'Nie ma jeszcze dostępnych opcji modeli. Najpierw wykryj kompatybilne lokalne CLI AI.';
  @override
  String get slotsAppearWhenAvailable =>
      'Ustawienia slotów modeli pojawią się tutaj, gdy modele dostawców będą dostępne.';
  @override
  String get effortDefault => 'domyślny';
  @override
  String get noModelsForSlot => 'Nie wykryto modeli dla tego slotu.';
  @override
  String viaProvider({required Object provider}) => 'przez ${provider}';
  @override
  String get customModelId => 'własny id modelu';
}

// Path: settings.modelPicker
class _Translations$settings$modelPicker$pl
    extends Translations$settings$modelPicker$en {
  _Translations$settings$modelPicker$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String noMatch({required Object query}) => 'brak modeli dla „${query}”';
  @override
  String get noModels => 'brak dostępnych modeli';
  @override
  String get filterHint => 'filtruj modele...';
  @override
  String get warming => 'rozgrzewanie…';
  @override
  String get detailsUnavailable => 'szczegóły niedostępne';
  @override
  String get free => 'za darmo';
}

// Path: settings.aiFeatures
class _Translations$settings$aiFeatures$pl
    extends Translations$settings$aiFeatures$en {
  _Translations$settings$aiFeatures$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get commitDescription =>
      'Szkicuje wiadomości commitów z zaindeksowanych zmian, zgodnie z twoją strukturą, głosem i preferencjami zakresu.';
  @override
  String get reviewDescription =>
      'Przejrzyj bieżący zakres commita, zanim go utworzysz.';
  @override
  String get museDescription =>
      'Trójfazowa wyrocznia: najpierw burza mózgów, potem synteza kierunku naprzód dla diff.';
}

// Path: settings.commitEditor
class _Translations$settings$commitEditor$pl
    extends Translations$settings$commitEditor$en {
  _Translations$settings$commitEditor$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get styleGuide => 'Przewodnik stylu';
  @override
  String get styleGuideHint =>
      'Opcjonalne. Głos / ton / zakazy. Format powyżej odpowiada za szkielet.';
}

// Path: settings.review
class _Translations$settings$review$pl extends Translations$settings$review$en {
  _Translations$settings$review$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Dodatkowe notatki do przeglądu';
  @override
  String get doubleCheckLabel => 'Podwójna weryfikacja przeglądu';
  @override
  String get doubleCheckDescription =>
      'Uruchom drugi przebieg weryfikacji przed pokazaniem końcowego raportu.';
}

// Path: settings.museHint
class _Translations$settings$museHint$pl
    extends Translations$settings$museHint$en {
  _Translations$settings$museHint$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get loose =>
      'coś, ku czemu delikatnie skierować? nastrój dziś łaskawy.';
  @override
  String get balanced =>
      'na czym się zatrzymać, co pominąć. szczerze, ale nie ostro.';
  @override
  String get strict => 'standardy. zakazy. czego muza nie odpuści.';
  @override
  String get paranoid =>
      'nastrój soczewkę. na jakich częstotliwościach ma buczeć manifold?';
}

// Path: settings.museEditor
class _Translations$settings$museEditor$pl
    extends Translations$settings$museEditor$en {
  _Translations$settings$museEditor$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Dodatkowe notatki dla muzy';
}

// Path: settings.museStage
class _Translations$settings$museStage$pl
    extends Translations$settings$museStage$en {
  _Translations$settings$museStage$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get brainstorm => 'BURZA MÓZGÓW';
  @override
  String get synthesize => 'SYNTEZA';
  @override
  String get slot => 'slot';
  @override
  String get ideaCountLoose => '~12 pomysłów';
  @override
  String get ideaCountBalanced => '~16 pomysłów';
  @override
  String get ideaCountStrict => '~20 pomysłów';
  @override
  String get ideaCountParanoid => '~24 pomysły';
  @override
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  barierka: ${macro}';
}

// Path: settings.lensAxis
class _Translations$settings$lensAxis$pl
    extends Translations$settings$lensAxis$en {
  _Translations$settings$lensAxis$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get folder => 'FOLDER';
  @override
  String get history => 'HISTORIA';
  @override
  String get far => 'DALEKO';
  @override
  String get near => 'BLISKO';
}

// Path: settings.logosLens
class _Translations$settings$logosLens$pl
    extends Translations$settings$logosLens$en {
  _Translations$settings$logosLens$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get moduleMap => 'mapa modułów';
  @override
  String get repoCenters => 'centra repozytorium';
  @override
  String get neighbors => 'sąsiedzi';
  @override
  String get toTouch => 'co ruszyć dalej';
  @override
  String get relevanceEngine => 'silnik trafności';
  @override
  String get description =>
      'czyta, jak pliki poruszają się razem przez strukturę, historię i rytm, aby Manifold wiedział, co ważne, a nie tylko co się zmieniło.';
  @override
  String get withinReach => 'w zasięgu';
  @override
  String get gate => 'próg';
  @override
  String get nearest => 'najbliższy';
  @override
  String get warming => 'rozgrzewanie';
  @override
  String get emptyOpenRepo =>
      'otwórz repozytorium,\naby zobaczyć soczewkę na żywo';
  @override
  String get emptyNoFiles =>
      'brak plików w\nzasięgu — przeciągnij\nku HISTORII';
}

// Path: settings.sortGuide
class _Translations$settings$sortGuide$pl
    extends Translations$settings$sortGuide$en {
  _Translations$settings$sortGuide$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Przewodnik sortowania zmian';
  @override
  String get related =>
      'Pliki zmieniające się razem grupują się razem. Najpierw sedno, potem kontekst.';
  @override
  String get relatedInverted =>
      'Najpierw izolowane zmiany. Ściśle sprzężone klastry osiadają na dole.';
  @override
  String get alphabetical =>
      'Zwykłe A → Z wg ścieżki. Bez rozróżniania wielkości liter, liczby w naturalnym porządku.';
  @override
  String get alphabeticalInverted =>
      'Zwykłe Z → A wg ścieżki. Bez rozróżniania wielkości liter, liczby w naturalnym porządku.';
  @override
  String get impact =>
      'Najpierw wypływają najcięższe zmiany. Rotacja jest ważona; binaria i nowe pliki dostają wzmocnienie.';
  @override
  String get impactInverted =>
      'Najpierw wypływają najlżejsze zmiany. Szybkie zwycięstwa na górze; ciężkie czekają.';
  @override
  String get nearRelated => 'wg sprzężeń';
  @override
  String get alphabeticalShort => 'alfabetycznie';
  @override
  String get byImpact => 'wg wpływu';
  @override
  String get flipped => 'odwrócone';
  @override
  String get peek => 'zerknij';
}

// Path: settings.piggyback
class _Translations$settings$piggyback$pl
    extends Translations$settings$piggyback$en {
  _Translations$settings$piggyback$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get apiModelsUse => 'Modele API używają';
  @override
  String get codexNotDetected => 'nie wykryto codex';
  @override
  String get dormant => 'UŚPIONE';
}

// Path: settings.diffStage
class _Translations$settings$diffStage$pl
    extends Translations$settings$diffStage$en {
  _Translations$settings$diffStage$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get viewer => 'podgląd';
  @override
  String get media => 'media';
  @override
  String get binary => 'binarny';
  @override
  String get hidden => 'ukryty';
}

// Path: settings.undoScope
class _Translations$settings$undoScope$pl
    extends Translations$settings$undoScope$en {
  _Translations$settings$undoScope$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get destructiveActions => 'działania niszczące';
  @override
  String get discards => 'odrzucenia';
  @override
  String get commits => 'commity';
  @override
  String get commitPush => 'commit + push';
  @override
  String get all => 'wszystko';
}

// Path: settings.undoWindow
class _Translations$settings$undoWindow$pl
    extends Translations$settings$undoWindow$en {
  _Translations$settings$undoWindow$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Okno cofania';
  @override
  String get off => 'Wył';
  @override
  String descriptionInstant({required Object scope}) =>
      '${scope} finalizują się natychmiast.';
  @override
  String descriptionDelayed({required Object seconds, required Object scope}) =>
      '${seconds} s do finalizacji: ${scope}.';
  @override
  String get cycleScopeTooltip =>
      'Kliknij, aby przełączyć zakres · albo przeciągnij w górę/dół na suwaku';
  @override
  String get resetTooltip => 'Zresetuj każde działanie do domyślnego okna';
}

// Path: settings.guardrailPhrase
class _Translations$settings$guardrailPhrase$pl
    extends Translations$settings$guardrailPhrase$en {
  _Translations$settings$guardrailPhrase$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get probablyFine => '„Pewnie w porządku” znaczy w porządku';
  @override
  String get proper => 'Porządne czytanie, logika, integracja, wzorce';
  @override
  String get lookAgain => 'Spójrz jeszcze raz. Coś może się kryć';
  @override
  String get assumeWrong => 'Załóż, że coś jest nie tak. Znajdź to';
}

// Path: settings.reviewGuideHint
class _Translations$settings$reviewGuideHint$pl
    extends Translations$settings$reviewGuideHint$en {
  _Translations$settings$reviewGuideHint$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get focusHigh =>
      'np. Skup się na logice wysokiego poziomu i poważnych błędach. Zwięźle i wyrozumiale.';
  @override
  String get surfaceBugs =>
      'np. Wydobądź potencjalne błędy, niespójności architektoniczne i awarie przypadków brzegowych.';
  @override
  String get scrutinize =>
      'np. Analizuj każdą linię pod kątem optymalizacji, bezpieczeństwa i zgodności ze wzorcami.';
  @override
  String get trustNothing =>
      'np. Nie ufaj niczemu. Kwestionuj każdy efekt uboczny. Traktuj każdą linię jak potencjalną awarię.';
  @override
  String get optional => 'Opcjonalna wskazówka, o co przegląd ma dbać.';
}

// Path: settings.commitFormat
class _Translations$settings$commitFormat$pl
    extends Translations$settings$commitFormat$en {
  _Translations$settings$commitFormat$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Format';
  @override
  String get peek => 'zerknij';
  @override
  String get structure => 'Struktura';
  @override
  String get voice => 'Głos';
  @override
  String get coverage => 'Zakres';
  @override
  String get structureTitleBody => 'tytuł + treść';
  @override
  String get structureTitleOnly => 'tylko tytuł';
  @override
  String get structureFreeform => 'dowolna forma';
  @override
  String get voiceVerbLed => 'zorientowany na działanie';
  @override
  String get voiceDescriptive => 'opisowy';
  @override
  String get voiceNarrative => 'narracyjny';
  @override
  String get coverageEssentials => 'sedno';
  @override
  String get coverageBalanced => 'zrównoważony';
  @override
  String get coverageEverything => 'wszystko';
}

// Path: settings.commitPreview
class _Translations$settings$commitPreview$pl
    extends Translations$settings$commitPreview$en {
  _Translations$settings$commitPreview$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$pl title =
      _Translations$settings$commitPreview$title$pl._(_root);
  @override
  late final _Translations$settings$commitPreview$base$pl base =
      _Translations$settings$commitPreview$base$pl._(_root);
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$pl
  balancedSuffix = _Translations$settings$commitPreview$balancedSuffix$pl._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$pl
  everythingSuffix = _Translations$settings$commitPreview$everythingSuffix$pl._(
    _root,
  );
}

// Path: settings.externalTools
class _Translations$settings$externalTools$pl
    extends Translations$settings$externalTools$en {
  _Translations$settings$externalTools$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Narzędzia zewnętrzne';
  @override
  String get summary =>
      'Kliknij projekt prawym przyciskiem w panelu bocznym, aby otworzyć go jednym z nich. Argumenty używają {path} dla folderu projektu.';
  @override
  String get detecting => 'Wykrywam zainstalowane narzędzia…';
  @override
  String get allPresetsAdded =>
      'Wszystkie znane presety są już dodane. Użyj „+ Własne”, aby dodać więcej.';
  @override
  String get noToolsConfigured =>
      'Nie skonfigurowano jeszcze narzędzi. Dodaj jedno powyżej.';
  @override
  String get categoryAi => 'ai';
  @override
  String get categoryEditors => 'edytory';
  @override
  String get categoryExplore => 'eksploracja';
  @override
  String get categoryOps => 'operacje';
  @override
  String get categoryGitOps => 'operacje git';
  @override
  String get nameHint => 'Nazwa';
  @override
  String get commandHint => 'polecenie';
  @override
  String get test => 'test';
  @override
  String get removeTool => 'Usuń narzędzie';
  @override
  String get modeTerminal => 'terminal';
  @override
  String get modeDetached => 'odłączony';
}

// Path: settings.apiUsage
class _Translations$settings$apiUsage$pl
    extends Translations$settings$apiUsage$en {
  _Translations$settings$apiUsage$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String thisMonth({required Object used, required Object limit}) =>
      '${used}${limit} w tym miesiącu';
}

// Path: settings.gitea
class _Translations$settings$gitea$pl extends Translations$settings$gitea$en {
  _Translations$settings$gitea$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Tokeny Gitea';
  @override
  String get hostHint => 'host';
  @override
  String get tokenHint => 'token';
  @override
  String get save => 'zapisz';
}

// Path: settings.wick
class _Translations$settings$wick$pl extends Translations$settings$wick$en {
  _Translations$settings$wick$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get selectExecutable => 'Wybierz plik wykonywalny wick';
  @override
  String get connected => 'wick · połączony';
  @override
  String get pathToExecutable => 'wick · ścieżka do pliku wykonywalnego';
  @override
  String get off => 'wył.';
  @override
  String get disableHint => 'Wyłącz integrację wick';
  @override
  String get enableHint => 'Włącz integrację wick';
}

// Path: settings.integrations
class _Translations$settings$integrations$pl
    extends Translations$settings$integrations$en {
  _Translations$settings$integrations$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'i integracje';
  @override
  String get alpha => 'alpha';
  @override
  String get planned => 'w planach';
  @override
  String get lspComingSoon => 'lsp · wkrótce';
  @override
  String get alphaMathConnected => 'alpha-math · połączony';
  @override
  String get alphaMathComingSoon => 'alpha-math · wkrótce';
}

// Path: settings.reduceMotion
class _Translations$settings$reduceMotion$pl
    extends Translations$settings$reduceMotion$en {
  _Translations$settings$reduceMotion$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Ogranicz animacje';
  @override
  String get subtitleStill => 'Nieruchomo… jak lód?';
  @override
  String get subtitleFlow => 'Płynie jak woda.';
}

// Path: settings.resetQuit
class _Translations$settings$resetQuit$pl
    extends Translations$settings$resetQuit$en {
  _Translations$settings$resetQuit$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get resetAndQuit => 'RESET I WYJŚCIE';
  @override
  String get keepRepos => 'ZACHOWAJ REPOZYTORIA';
  @override
  String get wipeAll => 'WYMAŻ WSZYSTKO';
}

// Path: settings.diagnostics
class _Translations$settings$diagnostics$pl
    extends Translations$settings$diagnostics$en {
  _Translations$settings$diagnostics$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get commandDiagnostics => 'Diagnostyka poleceń';
  @override
  String get networkFlowTelemetry => 'Telemetria przepływu sieciowego';
  @override
  String get clearSamples => 'Wyczyść próbki';
  @override
  String get clearMetrics => 'Wyczyść metryki';
  @override
  String get clearTimings => 'Wyczyść pomiary';
  @override
  String get recalibrate => 'REKALIBRUJ';
  @override
  String get ok => 'ok';
  @override
  String get noCommandTimings =>
      'Brak zarejestrowanych pomiarów poleceń. Wykonuj zwykłe działania, aby wypełnić diagnostykę.';
  @override
  String get noBackendSamples =>
      'Brak zarejestrowanych próbek poleceń backendu. Wykonuj działania git i ustawień, aby wypełnić ten log.';
  @override
  String get noDiffSessions =>
      'Brak zarejestrowanych sesji renderowania diff. Otwieraj i przewijaj diff plików, aby wypełnić ten panel.';
  @override
  String get noUiSessions =>
      'Brak zarejestrowanych sesji pomiarów UI. Otwieraj panele i nawiguj po trasach, aby wypełnić ten panel.';
  @override
  String get recentOperations => 'Ostatnie operacje';
  @override
  String get recentBackendOperations => 'Ostatnie operacje backendu';
  @override
  String get recentDiffSessions => 'Ostatnie sesje diff';
  @override
  String get recentUiTimings => 'Ostatnie pomiary UI';
  @override
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} unikalne polecenie',
        few: '${n} unikalne polecenia',
        many: '${n} unikalnych poleceń',
        other: '${n} unikalnego polecenia',
      );
  @override
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} polecenie z zakresem',
        few: '${n} polecenia z zakresem',
        many: '${n} poleceń z zakresem',
        other: '${n} polecenia z zakresem',
      );
  @override
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} zdarzenie z instrumentacją',
        few: '${n} zdarzenia z instrumentacją',
        many: '${n} zdarzeń z instrumentacją',
        other: '${n} zdarzenia z instrumentacją',
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
    'polecenie',
    'p50',
    'niezawodność',
    'zakres',
  ];
  @override
  List<String> get headersBackend => ['zakres', 'p50', 'p95', 'awarie'];
  @override
  List<String> get headersDiff => [
    'renderer',
    'pierwsze malowanie',
    'klatka p95',
    'raster p95',
    'jank',
  ];
  @override
  List<String> get headersUi => ['zdarzenie', 'p50', 'awarie', 'zakres'];
}

// Path: settings.telemetry
class _Translations$settings$telemetry$pl
    extends Translations$settings$telemetry$en {
  _Translations$settings$telemetry$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} próbka',
        few: '${n} próbki',
        many: '${n} próbek',
        other: '${n} próbki',
      );
  @override
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} polecenie',
        few: '${n} polecenia',
        many: '${n} poleceń',
        other: '${n} polecenia',
      );
  @override
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} sesja',
        few: '${n} sesje',
        many: '${n} sesji',
        other: '${n} sesji',
      );
  @override
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} zdarzenie',
        few: '${n} zdarzenia',
        many: '${n} zdarzeń',
        other: '${n} zdarzenia',
      );
  @override
  String stability({required Object pct}) => '${pct}% stabilności';
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
class _Translations$settings$flowEngine$pl
    extends Translations$settings$flowEngine$en {
  _Translations$settings$flowEngine$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get executionFlow => 'przepływ wykonania';
  @override
  String get description =>
      'symuluje oscylatory na kodzie, wydobywając kruche ścieżki wykonania, zanim skrystalizują się w błędy.';
  @override
  String get idle => 'bezczynny';
  @override
  String get emptyOpenRepo =>
      'otwórz repozytorium,\naby zobaczyć analizę przepływu';
  @override
  String get scanning => 'skanowanie';
  @override
  String get analysing => 'analizuję pliki\nw soczewce…';
  @override
  String get fragility => 'kruchość';
  @override
  String get findings => 'znaleziska';
  @override
  String get gap => 'luka';
  @override
  String get clean => 'czysto';
  @override
  String get severity => 'waga';
  @override
  String get critical => 'krytyczne';
  @override
  String get warn => 'ostrzeż.';
  @override
  String get info => 'info';
}

// Path: settings.museStrands
class _Translations$settings$museStrands$pl
    extends Translations$settings$museStrands$en {
  _Translations$settings$museStrands$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get spark => 'iskra natchnienia · natychmiastowy następny krok';
  @override
  String get current => 'prąd w wodzie · rozwinięcia w czasie teraźniejszym';
  @override
  String get horizon => 'spojrzenie za horyzont · sięgające kierunki';
  @override
  String get fever => 'przebudzenie z gorączkowego snu · prowokacje';
  @override
  String get echo => 'echo przez kanion · analogie gdzie indziej';
  @override
  String get vertigo => 'zawroty głowy na skraju urwiska · sąsiednie ryzyka';
  @override
  String get ghost => 'duch tego, co było · kontekst historyczny';
  @override
  String get mirror => 'lustro na spokojnej wodzie · inwersje';
}

// Path: settings.cliPiggyback
class _Translations$settings$cliPiggyback$pl
    extends Translations$settings$cliPiggyback$en {
  _Translations$settings$cliPiggyback$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Piggybacking CLI';
  @override
  String get clearCacheLabel => 'Wyczyść cache';
  @override
  String get clearCacheTooltip =>
      'Wymaż zbuforowane modele i ponów sondowanie. Usuwa te, które dostawca porzucił.';
  @override
  String get refreshLabel => 'Odśwież dostawców';
  @override
  String get refreshTooltip => 'Ponów sondowanie każdego dostawcy teraz.';
  @override
  String get body =>
      'Bezpośrednio przekazuj wiadomości interfejsu do lokalnych binariów dostawców.';
  @override
  String get cliTimeoutLabel => 'Limit czasu na uruchomienie';
  @override
  String get cliTimeoutUnitMinutes => 'minuty';
  @override
  String get cliTimeoutUnitMinute => 'minuta';
  @override
  String get forceStopLabel => 'Zatrzymaj wszystkie sesje';
  @override
  String get forceStopTooltip =>
      'Wymuś zakończenie każdego trwającego uruchomienia CLI.';
  @override
  String get forceStopConfirmTitle => 'Zatrzymać działające sesje CLI?';
  @override
  String forceStopConfirmBody({required Object count}) =>
      'To wymusi zakończenie trwających uruchomień CLI (${count}). Ich wynik zostanie utracony.';
  @override
  String get forceStopConfirmAction => 'Zatrzymaj wszystkie';
  @override
  String get forceStopNoneRunning => 'Brak działających sesji CLI';
  @override
  String get forceStopRecordError =>
      'Zatrzymano — sesje CLI zostały przymusowo zakończone.';
}

// Path: settings.header
class _Translations$settings$header$pl extends Translations$settings$header$en {
  _Translations$settings$header$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Preferencje przestrzeni roboczej';
  @override
  String get subtitle =>
      'Skonfiguruj globalną estetykę, dynamikę interfejsu i kluczowe zabezpieczenia operacyjne dla całej przestrzeni roboczej.';
  @override
  String get releaseNotesTooltip => 'Uwagi do wydania';
  @override
  String get replayOnboardingTooltip => 'Powtórz onboarding';
}

// Path: settings.diagnosticsPanel
class _Translations$settings$diagnosticsPanel$pl
    extends Translations$settings$diagnosticsPanel$en {
  _Translations$settings$diagnosticsPanel$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Diagnostyka wydajności';
  @override
  String get copyTrace => 'Kopiuj ślad';
  @override
  String get offenderRanking => 'Ranking winowajców';
  @override
  String get offenderRankingSubtitle =>
      'Czynniki opóźnień we wszystkich strumieniach.';
  @override
  String get noOffenders =>
      'Brak rankingu winowajców. Zbierz aktywność diagnostyczną, aby wypełnić tę listę.';
}

// Path: settings.release
class _Translations$settings$release$pl
    extends Translations$settings$release$en {
  _Translations$settings$release$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Wdrożenie wydania';
  @override
  String get summary => 'Ustawienia związane z aktualizacjami.';
  @override
  String get deploymentChannel => 'KANAŁ WDROŻENIA';
  @override
  String get captureCrashDiagnostics => 'Zbieraj diagnostykę awarii';
  @override
  String get comingSoon => 'Wkrótce.';
  @override
  String get checking => 'SPRAWDZANIE…';
  @override
  String get pollForUpdates => 'SPRAWDŹ AKTUALIZACJE';
}

// Path: settings.providerStatus
class _Translations$settings$providerStatus$pl
    extends Translations$settings$providerStatus$en {
  _Translations$settings$providerStatus$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get detecting => 'Wykrywanie...';
  @override
  String get ready => 'Gotowy';
  @override
  String get notDetected => 'Nie wykryto';
  @override
  String configured({required Object count}) => '${count} skonfigurowano';
  @override
  String get notConfigured => 'Nie skonfigurowano';
  @override
  String get cliManaged => 'Zarządzany przez CLI';
  @override
  String get connected => 'Połączony';
  @override
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} model',
        few: '${n} modele',
        many: '${n} modeli',
        other: '${n} modelu',
      );
  @override
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} dostawca',
        few: '${n} dostawcy',
        many: '${n} dostawców',
        other: '${n} dostawcy',
      );
}

// Path: settings.meridiem
class _Translations$settings$meridiem$pl
    extends Translations$settings$meridiem$en {
  _Translations$settings$meridiem$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get am => 'AM';
  @override
  String get pm => 'PM';
}

// Path: settings.offenders
class _Translations$settings$offenders$pl
    extends Translations$settings$offenders$en {
  _Translations$settings$offenders$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get commandStream => 'Polecenie';
  @override
  String get diffStream => 'Renderowanie diff';
  @override
  String get uiStream => 'Pomiar UI';
  @override
  String rendererName({required Object mode}) => 'renderer ${mode}';
  @override
  String latencyFailMetric({required Object p95, required Object fail}) =>
      '${p95} ms p95 | ${fail}% awarii';
  @override
  String jankFrameMetric({required Object jank, required Object frame}) =>
      '${jank}% jank | ${frame} ms klatka p95';
  @override
  String inStream({required Object stream}) => 'w ${stream}';
}

// Path: sync.actions
class _Translations$sync$actions$pl extends Translations$sync$actions$en {
  _Translations$sync$actions$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get syncLabel => 'Synchronizuj';
  @override
  String get syncOpenRepoDetail =>
      'Otwórz repozytorium, aby zarządzać operacjami push i pull.';
  @override
  String get detachedHeadLabel => 'Odłączony HEAD';
  @override
  String get detachedHeadDetail =>
      'Przełącz się na gałąź przed pushem lub pullem.';
  @override
  String get publishBranchLabel => 'Opublikuj gałąź';
  @override
  String publishBranchDetail({required Object branch}) =>
      'Pushnij ${branch} i ustaw jej gałąź śledzenia upstream.';
  @override
  String get publishButtonLabel => 'Opublikuj';
  @override
  String get syncBranchLabel => 'Synchronizuj gałąź';
  @override
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => 'Pullnij ${behindCount} z rebase, następnie pushnij ${aheadCount}.';
  @override
  String get syncBranchButtonLabel => 'Pullnij (rebase), potem pushnij';
  @override
  String get pushBranchLabel => 'Pushnij gałąź';
  @override
  String pushBranchDetail({required Object count, required Object upstream}) =>
      'Pushnij ${count} do ${upstream}.';
  @override
  String get pushBranchButtonLabel => 'Pushnij commity';
  @override
  String get pullUpdatesLabel => 'Pullnij aktualizacje';
  @override
  String pullUpdatesDetail({required Object count, required Object upstream}) =>
      'Pullnij ${count} z ${upstream}.';
  @override
  String syncUpToDateDetail({required Object upstream}) =>
      'Wykonaj fetch z ${upstream} i odśwież status upstream.';
}

// Path: sync.panel
class _Translations$sync$panel$pl extends Translations$sync$panel$en {
  _Translations$sync$panel$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Ładowanie statusu zdalnego';
  @override
  String get loadingMessage => 'Sprawdzanie danych śledzenia gałęzi.';
  @override
  String get remoteStatusUnavailable => 'Status zdalnego niedostępny';
  @override
  String get noUpstream => 'brak upstream';
  @override
  String get aheadLabel => 'Do przodu';
  @override
  String get behindLabel => 'W tyle';
  @override
  String get treeLabel => 'Drzewo';
  @override
  String get runningSync => 'Synchronizacja…';
  @override
  String get fetching => 'Fetchowanie…';
  @override
  String get fetchOnly => 'Tylko fetch';
  @override
  String get syncFailed => 'Synchronizacja nie powiodła się';
  @override
  String get forcePushRecoveryLabel => 'Wymuś push (with lease)';
  @override
  String get conflictsToResolveTitle => 'Konflikty do rozwiązania';
  @override
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} wymaga rozwiązania: ${list}';
  @override
  String get resolveConflicts => 'Rozwiąż konflikty';
  @override
  String get workingEllipsis => 'Pracuję…';
  @override
  String lastActivity({required Object operation}) =>
      'Ostatnia aktywność: ${operation}';
  @override
  String get noOutput => 'Brak wyjścia.';
  @override
  String resolvedConflicts({required Object count}) => 'Rozwiązano: ${count}.';
  @override
  String get cancelledUnchanged => 'Anulowano, drzewo robocze bez zmian.';
  @override
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) =>
      '${count} ma niezacommitowane zmiany, zacommituj je najpierw, aby zsynchronizować z rebase (${list}).';
  @override
  String noUpstreamForForcePush({required Object branch}) =>
      'Nie można wymusić push: dla „${branch}” nie skonfigurowano upstream.';
}

// Path: sync.forcePush
class _Translations$sync$forcePush$pl extends Translations$sync$forcePush$en {
  _Translations$sync$forcePush$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get confirmTitle => 'Wymusić push (with lease)?';
  @override
  String target({required Object remote, required Object branch}) =>
      'Cel: ${remote}/${branch}';
  @override
  String get warning =>
      'To nadpisze zdalną gałąź twoją lokalną historią. Tryb with lease przerwie operację, jeśli ktoś pushnął do zdalnego po twoim ostatnim fetch, ale już pobrane zmiany i tak zostaną nadpisane. Używaj tylko wtedy, gdy celowo zrobiłeś rebase lub amend, który rozszedł się z gałęzią.';
  @override
  String get confirmButton => 'Wymuś push';
}

// Path: xray.board
class _Translations$xray$board$pl extends Translations$xray$board$en {
  _Translations$xray$board$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get movesWithModule => 'porusza się z innym modułem';
  @override
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} recenzent',
        few: '${n} recenzentów',
        many: '${n} recenzentów',
        other: '${n} recenzenta',
      );
  @override
  String get territory => 'Terytorium';
  @override
  String get unreviewed => 'bez przeglądu';
}

// Path: xray.cadence
class _Translations$xray$cadence$pl extends Translations$xray$cadence$en {
  _Translations$xray$cadence$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '${sum} commitów · ${days} dni\n${lines}';
  @override
  String burstTooltipSingle({required Object n, required Object label}) =>
      '${n} commitów w ${label}';
  @override
  String gapTooltip({required Object n, required Object label}) =>
      'przerwa ${n} dni · ${label}';
  @override
  String reflogTooltip({required Object n, required Object label}) =>
      '${n} zdarzeń reflog w ${label}';
}

// Path: xray.cards
class _Translations$xray$cards$pl extends Translations$xray$cards$en {
  _Translations$xray$cards$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$cards$branchModel$pl branchModel =
      _Translations$xray$cards$branchModel$pl._(_root);
  @override
  late final _Translations$xray$cards$bursty$pl bursty =
      _Translations$xray$cards$bursty$pl._(_root);
  @override
  late final _Translations$xray$cards$hiddenRefs$pl hiddenRefs =
      _Translations$xray$cards$hiddenRefs$pl._(_root);
  @override
  late final _Translations$xray$cards$keystone$pl keystone =
      _Translations$xray$cards$keystone$pl._(_root);
  @override
  late final _Translations$xray$cards$machineHistory$pl machineHistory =
      _Translations$xray$cards$machineHistory$pl._(_root);
  @override
  late final _Translations$xray$cards$migration$pl migration =
      _Translations$xray$cards$migration$pl._(_root);
  @override
  late final _Translations$xray$cards$narrowHotspot$pl narrowHotspot =
      _Translations$xray$cards$narrowHotspot$pl._(_root);
  @override
  late final _Translations$xray$cards$noTags$pl noTags =
      _Translations$xray$cards$noTags$pl._(_root);
  @override
  late final _Translations$xray$cards$reflog$pl reflog =
      _Translations$xray$cards$reflog$pl._(_root);
  @override
  late final _Translations$xray$cards$singleOwner$pl singleOwner =
      _Translations$xray$cards$singleOwner$pl._(_root);
}

// Path: xray.cardTitle
class _Translations$xray$cardTitle$pl extends Translations$xray$cardTitle$en {
  _Translations$xray$cardTitle$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get branches => 'gałęzie';
  @override
  String get bursty => 'zrywowy';
  @override
  String get hiddenRefs => 'ukryte refy';
  @override
  String get machineHeavy => 'maszynowo-ciężki';
  @override
  String get migration => 'migracja';
  @override
  String get narrowHotspot => 'wąski punkt zapalny';
  @override
  String get noTags => 'brak tagów';
  @override
  String get reflog => 'reflog';
  @override
  String get singleOwner => 'jeden właściciel';
}

// Path: xray.grain
class _Translations$xray$grain$pl extends Translations$xray$grain$en {
  _Translations$xray$grain$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get coarsest => 'najgrubsza — moduły najwyższego poziomu';
  @override
  String get finest => 'najdrobniejsze ziarno';
  @override
  String get mid => 'średnie ziarno';
  @override
  String get oneCharacteristic => 'jedna charakterystyczna skala';
}

// Path: xray.header
class _Translations$xray$header$pl extends Translations$xray$header$en {
  _Translations$xray$header$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get dirtyBadge => 'brudny';
  @override
  String get machineChip => 'maszynowy';
  @override
  String get refresh => 'Odśwież';
  @override
  String get refreshing => 'Odświeżanie...';
  @override
  String get title => 'X-Ray repozytorium';
}

// Path: xray.hotspot
class _Translations$xray$hotspot$pl extends Translations$xray$hotspot$en {
  _Translations$xray$hotspot$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get clusterPeers => 'sąsiedzi w klastrze';
  @override
  String get coChangers => 'współzmieniający';
  @override
  String get keystone => 'zwornik';
  @override
  String keystoneScore({required Object score}) => 'zwornik  φ=${score}';
}

// Path: xray.inspector
class _Translations$xray$inspector$pl extends Translations$xray$inspector$en {
  _Translations$xray$inspector$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get branchLabel => 'gałąź';
  @override
  String commitsHumanMachine({required Object n}) => 'człowiek · ${n} maszyna';
  @override
  String get commitsLabel => 'commity';
  @override
  String get confidenceLabel => 'pewność';
  @override
  String get curlLabel => 'curl';
  @override
  String get engineSection => 'silnik';
  @override
  String get gradientLabel => 'gradient';
  @override
  String get harmonicLabel => 'harmoniczna';
  @override
  String get headLabel => 'head';
  @override
  String get hiddenRefsLabel => 'ukryte refy';
  @override
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} merge',
        few: '${n} merge\'e',
        many: '${n} merge\'ów',
        other: '${n} merge\'a',
      );
  @override
  String get noTags => 'brak tagów';
  @override
  String get notesLabel => 'notatki';
  @override
  String get openCommit => 'Otwórz commit';
  @override
  String get pathLabel => 'ścieżka';
  @override
  String remoteCount({required Object n}) => '${n} zdalnych';
  @override
  String get renamesLabel => 'zmiany nazw';
  @override
  String scannedAt({required Object time}) => 'przeskanowano ${time}';
  @override
  String selectedCount({required Object n}) => '${n} wybrano';
  @override
  String get shapeLinear => 'liniowy';
  @override
  String get shapeMergeHeavy => 'dużo merge\'ów';
  @override
  String get shapeMostlyLinear => 'w większości liniowy';
  @override
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} stash',
        few: '${n} stashe',
        many: '${n} stashy',
        other: '${n} stasha',
      );
  @override
  String get stressLabel => 'naprężenie';
  @override
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} tag',
        few: '${n} tagi',
        many: '${n} tagów',
        other: '${n} tagu',
      );
  @override
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} drzewo robocze',
        few: '${n} drzewa robocze',
        many: '${n} drzew roboczych',
        other: '${n} drzewa roboczego',
      );
}

// Path: xray.loadingCard
class _Translations$xray$loadingCard$pl
    extends Translations$xray$loadingCard$en {
  _Translations$xray$loadingCard$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get buildingMessage =>
      'Sonduję historię Git, refy, rytm i punkty zapalne.';
  @override
  String get buildingTitle => 'Buduję X-Ray repozytorium';
  @override
  String get idleMessage =>
      'Otwórz panel ponownie, aby przesondować bieżące repozytorium.';
  @override
  String get idleTitle => 'X-Ray repozytorium';
  @override
  String get unavailableTitle => 'X-Ray repozytorium niedostępny';
}

// Path: xray.metabolism
class _Translations$xray$metabolism$pl extends Translations$xray$metabolism$en {
  _Translations$xray$metabolism$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String halfLife({required Object n}) => 'okres półtrwania ${n} dni';
}

// Path: xray.multi
class _Translations$xray$multi$pl extends Translations$xray$multi$en {
  _Translations$xray$multi$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} klaster',
        few: '${n} klastry',
        many: '${n} klastrów',
        other: '${n} klastra',
      );
  @override
  String clusterSingle({required Object id}) => 'klaster ${id}';
  @override
  String couplingSuffix({required Object parts}) => 'sprzężenie ${parts}';
  @override
  String externalCount({required Object n}) => '${n} zewnętrznych';
  @override
  String mutualCount({required Object n}) => '${n} wzajemnych';
}

// Path: xray.recency
class _Translations$xray$recency$pl extends Translations$xray$recency$en {
  _Translations$xray$recency$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String days({required Object n}) => '${n} dni';
  @override
  String months({required Object n}) => '${n} mies';
  @override
  String get today => 'dziś';
  @override
  String weeks({required Object n}) => '${n} tyg';
  @override
  String years({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} lat',
        other: '${n} lat',
      );
}

// Path: xray.rings
class _Translations$xray$rings$pl extends Translations$xray$rings$en {
  _Translations$xray$rings$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get hintOneBlended => 'jedna zmieszana struktura';
  @override
  String get hintSelfSimilar => 'samopodobna';
  @override
  String get oneBlendedBody =>
      'Jedna zmieszana struktura — odrębne skale modułów jeszcze się nie wyłaniają.';
  @override
  String get overHistory => 'Przez historię';
  @override
  String get parts => 'części';
  @override
  String get readingHint => 'odczytuję strukturę…';
  @override
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} skala',
        few: '${n} skale',
        many: '${n} skal',
        other: '${n} skali',
      );
  @override
  String get scaleDissolved => 'skala strukturalna rozpłynęła się';
  @override
  String get scaleEmerged => 'wyłoniła się skala strukturalna';
  @override
  String get scaleSpectrum => 'spektrum skal';
  @override
  String get selfSimilarBody =>
      'Samopodobna — struktura powtarza się na wszystkich skalach, bez jednego charakterystycznego poziomu.';
  @override
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} przesunięcie w historii',
        few: '${n} przesunięcia w historii',
        many: '${n} przesunięć w historii',
        other: '${n} przesunięcia w historii',
      );
  @override
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} przesunięcie strukturalne',
        few: '${n} przesunięcia strukturalne',
        many: '${n} przesunięć strukturalnych',
        other: '${n} przesunięcia strukturalnego',
      );
  @override
  String get title => 'Słoje przyrostu';
  @override
  String get unavailable => 'niedostępne';
}

// Path: xray.stats
class _Translations$xray$stats$pl extends Translations$xray$stats$en {
  _Translations$xray$stats$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get alive => 'żywy';
  @override
  String get files => 'pliki';
  @override
  String get lastTouched => 'ostatnio dotknięty';
  @override
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'właściciel',
        few: 'właściciele',
        many: 'właścicieli',
        other: 'właściciela',
      );
  @override
  String get touches => 'dotknięcia';
}

// Path: xray.stratumLabel
class _Translations$xray$stratumLabel$pl
    extends Translations$xray$stratumLabel$en {
  _Translations$xray$stratumLabel$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'bieżący';
  @override
  String get legacy => 'legacy';
  @override
  String get zone => 'strefa repo';
}

// Path: xray.summary
class _Translations$xray$summary$pl extends Translations$xray$summary$en {
  _Translations$xray$summary$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String analysisFailed({required Object error}) =>
      'Analiza nie powiodła się: ${error}';
  @override
  String get analyze => 'Analizuj';
  @override
  String get copied => 'Podsumowanie skopiowane do schowka.';
  @override
  String get directionHint => 'kierunek';
  @override
  String get download => 'Pobierz';
  @override
  String get emptyState =>
      'Uruchom analizę Logos, aby zmapować strukturę i regiony tego repozytorium.\n(tw: na razie kaszana)';
  @override
  String get exit => 'Wyjdź';
  @override
  String get generating => 'Odczytuję repozytorium i klastruję cechy…';
  @override
  String get noModel => 'Nie skonfigurowano modelu AI.';
  @override
  String get noModelConfigured => 'nie skonfigurowano modelu AI';
  @override
  String presentWith({required Object label}) => 'zaprezentuj z ${label}';
  @override
  String presentingWith({required Object label}) => 'prezentuję z ${label}…';
  @override
  String get reanalyze => 'Przeanalizuj ponownie';
  @override
  String get saveDialogTitle => 'Zapisz podsumowanie repozytorium';
  @override
  String saveFailed({required Object error}) =>
      'Nie udało się zapisać: ${error}';
  @override
  String get savePresentationDialogTitle => 'Zapisz prezentację';
  @override
  String savedTo({required Object path}) => 'Zapisano w ${path}';
}

// Path: xray.tabs
class _Translations$xray$tabs$pl extends Translations$xray$tabs$en {
  _Translations$xray$tabs$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get map => 'Mapa';
  @override
  String get signals => 'Sygnały';
  @override
  String get summary => 'Podsumowanie';
  @override
  String get time => 'Czas';
}

// Path: xray.trajectory
class _Translations$xray$trajectory$pl extends Translations$xray$trajectory$en {
  _Translations$xray$trajectory$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get connectivity => 'łączność';
  @override
  String events({required Object n}) => '${n} zdarzeń';
  @override
  String get openInOrrery => 'Otwórz w Orrery';
  @override
  String get readingHint => 'odczytuję historię…';
  @override
  String snapshots({required Object n}) => '${n} migawek';
  @override
  String get steady => 'Stabilnie — brak zdarzeń strukturalnych w tym oknie.';
  @override
  String get title => 'Trajektoria strukturalna';
}

// Path: xray.verdict
class _Translations$xray$verdict$pl extends Translations$xray$verdict$en {
  _Translations$xray$verdict$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String canonical({required Object pct}) => '${pct}% kanoniczny';
  @override
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · ${canonical}% kanoniczny · ${decisive}% zdecydowany';
}

// Path: changes.mergeEditor.trust
class _Translations$changes$mergeEditor$trust$pl
    extends Translations$changes$mergeEditor$trust$en {
  _Translations$changes$mergeEditor$trust$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get manual => 'ręcznie';
  @override
  String get safe => 'bezpiecznie';
  @override
  String get guided => 'z podpowiedziami';
  @override
  String get assisted => 'wspomagane';
  @override
  String get full => 'pełne';
  @override
  String label({required Object label}) => 'zaufanie: ${label}';
}

// Path: changes.mergeEditor.keyHints
class _Translations$changes$mergeEditor$keyHints$pl
    extends Translations$changes$mergeEditor$keyHints$en {
  _Translations$changes$mergeEditor$keyHints$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get accept => 'przyjmij';
  @override
  String get other => 'inne';
  @override
  String get both => 'oba';
  @override
  String get navigate => 'nawigacja';
  @override
  String get jumpNext => 'do następnego';
}

// Path: changes.mergeFlow.op
class _Translations$changes$mergeFlow$op$pl
    extends Translations$changes$mergeFlow$op$en {
  _Translations$changes$mergeFlow$op$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'merge';
  @override
  String get cherryPick => 'cherry-pick';
  @override
  String get revert => 'revert';
  @override
  String get resolve => 'rozwiązywanie';
  @override
  String get switchOp => 'przełączanie';
  @override
  String get pull => 'pull';
  @override
  String get rebase => 'rebase';
  @override
  String rebaseOnto({required Object branch, required Object base}) =>
      'rebase ${branch} na ${base}';
}

// Path: diff.pinned.tempo
class _Translations$diff$pinned$tempo$pl
    extends Translations$diff$pinned$tempo$en {
  _Translations$diff$pinned$tempo$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get hotOwnerLane =>
      'Niedawny ruch z jednym silnym właścicielem w pobliżu.';
  @override
  String get activeSeam => 'Niedawny ruch od wielu rąk w pobliżu.';
  @override
  String get stableOwnerLane =>
      'Długowieczny pas z jednym dominującym właścicielem.';
  @override
  String get sharedLongLivedSeam => 'Wspólny szew, który narastał z czasem.';
  @override
  String get sharedLane => 'Wspólny pas bez jednego dominującego właściciela.';
  @override
  String get resolving => 'Historia wokół tej linii wciąż się klaruje.';
}

// Path: diff.pinned.tone
class _Translations$diff$pinned$tone$pl
    extends Translations$diff$pinned$tone$en {
  _Translations$diff$pinned$tone$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get hot => 'Gorąco';
  @override
  String get novel => 'Nowo';
  @override
  String get contested => 'Sporne';
  @override
  String get spreading => 'Rozchodzi się';
  @override
  String get stable => 'Stabilnie';
}

// Path: diff.pinned.summary
class _Translations$diff$pinned$summary$pl
    extends Translations$diff$pinned$summary$en {
  _Translations$diff$pinned$summary$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String livesIn({required Object concept}) => 'Żyje w ${concept}';
  @override
  String get sitsInLocalSeam => 'Znajduje się w lokalnym szwie';
  @override
  String workedMostlyBy({required Object owner}) =>
      'głównie edytowany przez ${owner} w pobliżu';
  @override
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'echo w ${n} innym miejscu',
        few: 'echa w ${n} innych miejscach',
        many: 'echa w ${n} innych miejscach',
        other: 'echa w ${n} innych miejscach',
      );
  @override
  String inspectNext({required Object path, required Object detail}) =>
      'następnie zbadaj ${path}${detail}';
  @override
  String inspectDetail({required Object reason}) => ' (${reason})';
}

// Path: diff.pinned.tightness
class _Translations$diff$pinned$tightness$pl
    extends Translations$diff$pinned$tightness$en {
  _Translations$diff$pinned$tightness$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get tight => 'ciasne dopasowanie';
  @override
  String get close => 'bliskie dopasowanie';
  @override
  String get loose => 'luźne dopasowanie';
}

// Path: diff.pinned.witness
class _Translations$diff$pinned$witness$pl
    extends Translations$diff$pinned$witness$en {
  _Translations$diff$pinned$witness$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String nearbySupport({required Object label}) =>
      'Wsparcie w pobliżu · ${label}';
  @override
  String localizedMove({required Object label}) => 'Ruch lokalny · ${label}';
  @override
  String surprisingMove({required Object label}) =>
      'Zaskakujący ruch · ${label}';
}

// Path: diff.pinned.integrity
class _Translations$diff$pinned$integrity$pl
    extends Translations$diff$pinned$integrity$en {
  _Translations$diff$pinned$integrity$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get stableStructure => 'Stabilna struktura';
  @override
  String get conflictingSignals => 'Sprzeczne sygnały';
  @override
  String get novelShape => 'Nowy kształt';
}

// Path: diff.pinned.related
class _Translations$diff$pinned$related$pl
    extends Translations$diff$pinned$related$en {
  _Translations$diff$pinned$related$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get testMirror => 'Lustro testów';
  @override
  String get semanticHistorySibling => 'Rodzeństwo semantyczne i historyczne';
  @override
  String get recentCoChange => 'Niedawna wspólna zmiana';
  @override
  String get semanticSibling => 'Rodzeństwo semantyczne';
  @override
  String get relatedStructure => 'Powiązana struktura';
  @override
  String get tightlyBound => 'ściśle związany';
  @override
  String get orbiting => 'na orbicie';
  @override
  String get weaklyCoupled => 'słabo sprzężony';
  @override
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class _Translations$diff$pinned$axis$pl
    extends Translations$diff$pinned$axis$en {
  _Translations$diff$pinned$axis$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get historyTrail => 'ślad historii';
  @override
  String get testMirrorLane => 'pas lustra testów';
  @override
  String get structuralLane => 'pas strukturalny';
  @override
  String get semanticNeighbourhood => 'sąsiedztwo semantyczne';
}

// Path: history.commitLede.semantics
class _Translations$history$commitLede$semantics$pl
    extends Translations$history$commitLede$semantics$en {
  _Translations$history$commitLede$semantics$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get importanceHigh => 'wysoka ważność';
  @override
  String get importanceModerate => 'umiarkowana ważność';
  @override
  String get mostlyAdditions => 'głównie dodania';
  @override
  String get mostlyDeletions => 'głównie usunięcia';
  @override
  String get tightlyCoupled => 'ściśle sprzężone pliki';
  @override
  String get overlapsWorkingTree => 'pokrywa się z twoim drzewem roboczym';
}

// Path: onboarding.repo.doors
class _Translations$onboarding$repo$doors$pl
    extends Translations$onboarding$repo$doors$en {
  _Translations$onboarding$repo$doors$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$repo$doors$open$pl open =
      _Translations$onboarding$repo$doors$open$pl._(_root);
  @override
  late final _Translations$onboarding$repo$doors$clone$pl clone =
      _Translations$onboarding$repo$doors$clone$pl._(_root);
  @override
  late final _Translations$onboarding$repo$doors$create$pl create =
      _Translations$onboarding$repo$doors$create$pl._(_root);
}

// Path: onboarding.repo.cloneForm
class _Translations$onboarding$repo$cloneForm$pl
    extends Translations$onboarding$repo$cloneForm$en {
  _Translations$onboarding$repo$cloneForm$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Klonuj z URL';
  @override
  String get urlLabel => 'URL repozytorium';
  @override
  String get targetLabel => 'Folder docelowy';
  @override
  String get browse => 'Przeglądaj…';
  @override
  String get clone => 'Klonuj';
  @override
  String get cloning => 'Klonowanie…';
}

// Path: onboarding.repo.pickers
class _Translations$onboarding$repo$pickers$pl
    extends Translations$onboarding$repo$pickers$en {
  _Translations$onboarding$repo$pickers$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get openRepository => 'Otwórz repozytorium';
  @override
  String get createRepository => 'Utwórz repozytorium';
  @override
  String get cloneTarget => 'Cel klonowania';
}

// Path: onboarding.repo.errors
class _Translations$onboarding$repo$errors$pl
    extends Translations$onboarding$repo$errors$en {
  _Translations$onboarding$repo$errors$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get urlAndTargetRequired => 'Wymagany URL i ścieżka docelowa.';
  @override
  String get createFailed => 'Nie udało się utworzyć repozytorium.';
  @override
  String get cloneFailed => 'Nie udało się sklonować repozytorium.';
}

// Path: onboarding.preview.panels
class _Translations$onboarding$preview$panels$pl
    extends Translations$onboarding$preview$panels$en {
  _Translations$onboarding$preview$panels$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get xray => 'X-Ray repozytorium';
  @override
  String get settings => 'ustawienia';
}

// Path: onboarding.preview.sidebar
class _Translations$onboarding$preview$sidebar$pl
    extends Translations$onboarding$preview$sidebar$en {
  _Translations$onboarding$preview$sidebar$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get projectsHeader => 'Projekty';
}

// Path: onboarding.preview.changes
class _Translations$onboarding$preview$changes$pl
    extends Translations$onboarding$preview$changes$en {
  _Translations$onboarding$preview$changes$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String filesStagedCount({required Object staged, required Object total}) =>
      '${staged} z ${total} plików';
  @override
  String stagedCount({required Object n}) => '${n} w indeksie';
  @override
  String get commitMessageHint => 'Wiadomość commita…';
  @override
  String get commitAndPush => 'Commit i push';
}

// Path: onboarding.preview.history
class _Translations$onboarding$preview$history$pl
    extends Translations$onboarding$preview$history$en {
  _Translations$onboarding$preview$history$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'Historia';
  @override
  String get viewingLast => 'ostatnie 20 commitów';
  @override
  String get inFlight => 'W TOKU';
  @override
  String get you => 'ty';
  @override
  String get commit1 => 'naucz lisa wąchać, zanim połknie';
  @override
  String get commit2 => 'bursztyn: utrzymaj zapach przez noc';
  @override
  String get commit3 => 'wycofaj kapustę na rzecz bursztynu i ciernia';
  @override
  String get commit4 => 'cierń strzeże bramy';
}

// Path: onboarding.preview.branches
class _Translations$onboarding$preview$branches$pl
    extends Translations$onboarding$preview$branches$en {
  _Translations$onboarding$preview$branches$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get lensBranches => 'GAŁĘZIE';
  @override
  String get lensPRs => 'PR';
  @override
  String get absorbed => 'wchłonięta';
  @override
  String get desk => 'Desk';
  @override
  String get head => 'HEAD';
  @override
  String tracking({required Object ref}) => '→ śledzenie: ${ref}';
}

// Path: onboarding.preview.diff
class _Translations$onboarding$preview$diff$pl
    extends Translations$onboarding$preview$diff$en {
  _Translations$onboarding$preview$diff$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get readmeTagline => 'Twój osobisty klient Git.';
}

// Path: releaseNotes.about.whyFlutter
class _Translations$releaseNotes$about$whyFlutter$pl
    extends Translations$releaseNotes$about$whyFlutter$en {
  _Translations$releaseNotes$about$whyFlutter$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'DLACZEGO FLUTTER?';
  @override
  String get body =>
      'Pierwsza wersja tego była aplikacją na Tauri (Rust + TypeScript). Sam już czułem, że działa wolno. Potem złapałem streamera mówiącego dokładnie to samo na streamie, którego zwykle nie oglądam — i to był impuls, żeby wreszcie zmienić stos. Fluttera wcale nie polecał, wręcz przeciwnie. Dart znalazłem sam, sklecił prototyp i uruchamianie skróciło się z jakichś 15 sekund do poniżej jednej. Niebo a ziemia. Żegnaj, ero Tauri.\n\nPotok renderowania Fluttera jest bliższy silnikowi gry niż DOM-owi, a dla aplikacji desktopowej, gdzie interfejs jest produktem, to zmienia wszystko. Dart okazał się na dodatek naprawdę dobrym językiem. Matematykę stojącą za silnikiem spektralnym najpierw prototypowano w Rust, więc tamta praca przeniosła się bez problemu.\n\nFlutter jest domyślnie wieloplatformowy, co jest świetne, ale z natury jest „googlowy”, więc ma kilka dziwactw.';
}

// Path: releaseNotes.about.spectralEngine
class _Translations$releaseNotes$about$spectralEngine$pl
    extends Translations$releaseNotes$about$spectralEngine$en {
  _Translations$releaseNotes$about$spectralEngine$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'CZYM JEST SILNIK SPEKTRALNY?';
  @override
  String get body =>
      'Za każdym razem, gdy commitujesz, pliki, które zmieniasz razem, z czasem układają się we wzorce. Silnik spektralny czyta twój graf commitów i rozkłada te wzorce wspólnych zmian na sygnały: które pliki są sprzężone, jak ściśle i jaką rolę strukturalną pełnią w repozytorium. Zasadniczo analiza spektralna twojej historii rozwoju. W kliencie git. Celowo.\n\nTa matematyka jest nowa, więc traktuję ją jak „game feel”: stroję, testuję, koryguję i tak dalej, aż sygnały zaczną wydawać się poprawne.\n\nTe sygnały zasilają wszystko. Sejsmograf w historii, malowane paski pod tematami commitów, system przeglądu, Muse, konstelację plików. Cała aplikacja rozumuje od tej warstwy w dół, a nie na odwrót.';
}

// Path: releaseNotes.about.whereGoing
class _Translations$releaseNotes$about$whereGoing$pl
    extends Translations$releaseNotes$about$whereGoing$en {
  _Translations$releaseNotes$about$whereGoing$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'DOKĄD TO ZMIERZA?';
  @override
  String get body =>
      'Pierwszy kamień milowy to pełna równość z GitHub Desktop, SourceTree i GitKraken. Wieloplatformowy klient git, który działa szybko i radzi sobie z podstawami lepiej niż cokolwiek innego. To w większości już jest. Silnik spektralny już daje nam przewagę w operacjach, które inne klienty każą przemyśleć ręcznie.\n\nDalej celem jest przewyższyć każdy inny klient git pod względem szybkości, dostępności, inteligencji i ogólnego UX. W przygotowaniu jest więcej niż to, co ogłoszono tutaj.';
}

// Path: settings.commitPreview.title
class _Translations$settings$commitPreview$title$pl
    extends Translations$settings$commitPreview$title$en {
  _Translations$settings$commitPreview$title$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$verbLed$pl verbLed =
      _Translations$settings$commitPreview$title$verbLed$pl._(_root);
  @override
  late final _Translations$settings$commitPreview$title$descriptive$pl
  descriptive = _Translations$settings$commitPreview$title$descriptive$pl._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$title$narrative$pl narrative =
      _Translations$settings$commitPreview$title$narrative$pl._(_root);
}

// Path: settings.commitPreview.base
class _Translations$settings$commitPreview$base$pl
    extends Translations$settings$commitPreview$base$en {
  _Translations$settings$commitPreview$base$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$base$verbLed$pl verbLed =
      _Translations$settings$commitPreview$base$verbLed$pl._(_root);
  @override
  late final _Translations$settings$commitPreview$base$descriptive$pl
  descriptive = _Translations$settings$commitPreview$base$descriptive$pl._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$base$narrative$pl narrative =
      _Translations$settings$commitPreview$base$narrative$pl._(_root);
}

// Path: settings.commitPreview.balancedSuffix
class _Translations$settings$commitPreview$balancedSuffix$pl
    extends Translations$settings$commitPreview$balancedSuffix$en {
  _Translations$settings$commitPreview$balancedSuffix$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$verbLed$pl
  verbLed = _Translations$settings$commitPreview$balancedSuffix$verbLed$pl._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$descriptive$pl
  descriptive =
      _Translations$settings$commitPreview$balancedSuffix$descriptive$pl._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$narrative$pl
  narrative =
      _Translations$settings$commitPreview$balancedSuffix$narrative$pl._(_root);
}

// Path: settings.commitPreview.everythingSuffix
class _Translations$settings$commitPreview$everythingSuffix$pl
    extends Translations$settings$commitPreview$everythingSuffix$en {
  _Translations$settings$commitPreview$everythingSuffix$pl._(
    TranslationsPl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$verbLed$pl
  verbLed = _Translations$settings$commitPreview$everythingSuffix$verbLed$pl._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$descriptive$pl
  descriptive =
      _Translations$settings$commitPreview$everythingSuffix$descriptive$pl._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$narrative$pl
  narrative =
      _Translations$settings$commitPreview$everythingSuffix$narrative$pl._(
        _root,
      );
}

// Path: xray.cards.branchModel
class _Translations$xray$cards$branchModel$pl
    extends Translations$xray$cards$branchModel$en {
  _Translations$xray$cards$branchModel$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get broadClaim =>
      'Repozytorium ma wystarczającą powierzchnię gałęzi, by nawigacja świadoma gałęzi się opłacała.';
  @override
  String get broadTitle => 'Model gałęzi ma powierzchnię';
  @override
  String localBranchesDetail({required Object count}) =>
      '${count} lokalnych gałęzi.';
  @override
  String get localBranchesLabel => 'Lokalne gałęzie';
  @override
  String remoteBranchesDetail({required Object count}) =>
      '${count} zdalnych gałęzi.';
  @override
  String get remoteBranchesLabel => 'Zdalne gałęzie';
  @override
  String get simpleClaim => 'Widoczny model gałęzi jest wąski.';
  @override
  String get simpleTitle => 'Prosty model gałęzi';
}

// Path: xray.cards.bursty
class _Translations$xray$cards$bursty$pl
    extends Translations$xray$cards$bursty$en {
  _Translations$xray$cards$bursty$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Praca ląduje w skoncentrowanych zrywach, a nie równym dziennym rytmem.';
  @override
  String get title => 'Zrywowy rytm rozwoju';
}

// Path: xray.cards.hiddenRefs
class _Translations$xray$cards$hiddenRefs$pl
    extends Translations$xray$cards$hiddenRefs$en {
  _Translations$xray$cards$hiddenRefs$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object count}) =>
      '${count} refów żyje poza normalną przestrzenią gałęzi/tagów.';
  @override
  String evidenceDetail({required Object count}) =>
      '${count} refów poza heads/remotes/tags.';
  @override
  String get evidenceLabel => 'Ukryte refy';
  @override
  String get namespacesLabel => 'Przestrzenie nazw';
  @override
  String get title => 'Ukryte przestrzenie nazw Git';
}

// Path: xray.cards.keystone
class _Translations$xray$cards$keystone$pl
    extends Translations$xray$cards$keystone$en {
  _Translations$xray$cards$keystone$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String claim({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
    n,
    one:
        'Jeden plik niesie nieproporcjonalną wagę wspólnych zmian względem liczby dotknięć.',
    few:
        'Niewielki zbiór plików niesie nieproporcjonalną wagę wspólnych zmian względem liczby dotknięć.',
    many:
        'Niewielki zbiór plików niesie nieproporcjonalną wagę wspólnych zmian względem liczby dotknięć.',
    other:
        'Niewielki zbiór plików niesie nieproporcjonalną wagę wspólnych zmian względem liczby dotknięć.',
  );
  @override
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: '${n} dotknięcie · przyciąganie φ=${score}',
        few: '${n} dotknięcia · przyciąganie φ=${score}',
        many: '${n} dotknięć · przyciąganie φ=${score}',
        other: '${n} dotknięcia · przyciąganie φ=${score}',
      );
  @override
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pl'))(
        n,
        one: 'Zwornikowy plik-most',
        few: '${n} zwornikowe pliki-mosty',
        many: '${n} zwornikowych plików-mostów',
        other: '${n} zwornikowego pliku-mostu',
      );
}

// Path: xray.cards.machineHistory
class _Translations$xray$cards$machineHistory$pl
    extends Translations$xray$cards$machineHistory$en {
  _Translations$xray$cards$machineHistory$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Commity w stylu punktów kontrolnych istotnie zniekształcają naiwne metryki historii.';
  @override
  String machineCommitsDetail({required Object count}) =>
      '${count} commitów pasowało do wzorców maszynowych/sesyjnych.';
  @override
  String get machineCommitsLabel => 'Commity maszynowe';
  @override
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '${raw} surowych commitów wobec ${filtered} przefiltrowanych.';
  @override
  String get rawVsFilteredLabel => 'Surowe wobec przefiltrowanych';
  @override
  String get title => 'Historia maszynowa dominuje w surowych metrykach';
}

// Path: xray.cards.migration
class _Translations$xray$cards$migration$pl
    extends Translations$xray$cards$migration$en {
  _Translations$xray$cards$migration$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object older, required Object newer}) =>
      'Historia przesuwa się z `${older}` na `${newer}`, co sugeruje przejście stosu lub powierzchni.';
  @override
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches} dotknięć, ostatnia aktywność ${lastActive}.';
  @override
  String get title => 'Widoczna migracja architektury';
}

// Path: xray.cards.narrowHotspot
class _Translations$xray$cards$narrowHotspot$pl
    extends Translations$xray$cards$narrowHotspot$en {
  _Translations$xray$cards$narrowHotspot$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Niewielki zbiór plików i katalogów pochłania nieproporcjonalną część zmian.';
  @override
  String get title => 'Koncentracja punktów zapalnych jest wąska';
  @override
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path} stanowi ${pct}% widocznego zbioru punktów zapalnych.';
  @override
  String get topHotspotLabel => 'Główny punkt zapalny';
  @override
  String visibleAuthorsDetail({required Object count}) =>
      '${count} autorów w tym wycinku historii.';
  @override
  String get visibleAuthorsLabel => 'Widoczni autorzy';
}

// Path: xray.cards.noTags
class _Translations$xray$cards$noTags$pl
    extends Translations$xray$cards$noTags$en {
  _Translations$xray$cards$noTags$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Tagi git nie są używane jako widoczna warstwa wydań lub kamieni milowych.';
  @override
  String remoteEndpointsDetail({required Object count}) =>
      '${count} skonfigurowanych zdalnych punktów końcowych.';
  @override
  String get remoteEndpointsLabel => 'Zdalne punkty końcowe';
  @override
  String get tagCountDetail => 'Znaleziono 0 tagów.';
  @override
  String get tagCountLabel => 'Liczba tagów';
  @override
  String get title => 'Brak formalnego śladu wydań/tagów';
}

// Path: xray.cards.reflog
class _Translations$xray$cards$reflog$pl
    extends Translations$xray$cards$reflog$en {
  _Translations$xray$cards$reflog$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Objętość reflog wskazuje na skoncentrowaną lokalną iterację poza opublikowanymi commitami.';
  @override
  String get peakReflogDayLabel => 'Szczytowy dzień reflog';
  @override
  String get title => 'Intensywne sesje lokalnej edycji';
}

// Path: xray.cards.singleOwner
class _Translations$xray$cards$singleOwner$pl
    extends Translations$xray$cards$singleOwner$en {
  _Translations$xray$cards$singleOwner$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object path, required Object kind}) =>
      '`${path}` to intensywnie dotykany ${kind} z jednym wyraźnym widocznym autorem.';
  @override
  String ownerCountDetail({required Object count}) =>
      '${count} wyraźnych autorów.';
  @override
  String get ownerCountLabel => 'Liczba właścicieli';
  @override
  String get title => 'Punkt zapalny jednego właściciela';
  @override
  String get touchCountLabel => 'Liczba dotknięć';
  @override
  String touchDetailFiltered({required Object count}) =>
      '${count} dotknięć w przefiltrowanej historii.';
  @override
  String touchDetailRaw({required Object count}) =>
      '${count} dotknięć w surowej historii.';
}

// Path: onboarding.repo.doors.open
class _Translations$onboarding$repo$doors$open$pl
    extends Translations$onboarding$repo$doors$open$en {
  _Translations$onboarding$repo$doors$open$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Otwórz';
  @override
  String get subtitle => 'istniejący';
  @override
  String get hint => 'taki, który już masz';
}

// Path: onboarding.repo.doors.clone
class _Translations$onboarding$repo$doors$clone$pl
    extends Translations$onboarding$repo$doors$clone$en {
  _Translations$onboarding$repo$doors$clone$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Klonuj';
  @override
  String get subtitle => 'z URL';
  @override
  String get hint => 'wklej zdalny URL';
}

// Path: onboarding.repo.doors.create
class _Translations$onboarding$repo$doors$create$pl
    extends Translations$onboarding$repo$doors$create$en {
  _Translations$onboarding$repo$doors$create$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Utwórz';
  @override
  String get subtitle => 'nowy';
  @override
  String get hint => 'zacznij coś od zera';
}

// Path: settings.commitPreview.title.verbLed
class _Translations$settings$commitPreview$title$verbLed$pl
    extends Translations$settings$commitPreview$title$verbLed$en {
  _Translations$settings$commitPreview$title$verbLed$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Niech lis pomija ciastka, które pachną nie tak';
  @override
  String get s2 =>
      'Naucz lisa odrzucać zmanipulowane ciastka, zanim je połknie';
  @override
  String get s3 =>
      'Zmuś lisa, by kryminalistycznie sprawdzał każde ciastko u bramy';
  @override
  String get def => 'Naucz lisa odrzucać złe ciastka';
}

// Path: settings.commitPreview.title.descriptive
class _Translations$settings$commitPreview$title$descriptive$pl
    extends Translations$settings$commitPreview$title$descriptive$en {
  _Translations$settings$commitPreview$title$descriptive$pl._(
    TranslationsPl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'teraz to lis wybiera ciastka';
  @override
  String get s2 => 'Procedura inspekcji ciastek, wbita w lisa';
  @override
  String get s3 =>
      'Kryminalistyka weryfikacji ciastek, wszczepiona w lisa powtórzeniem';
  @override
  String get def => 'Protokół obwąchiwania ciastek, zainstalowany w lisie';
}

// Path: settings.commitPreview.title.narrative
class _Translations$settings$commitPreview$title$narrative$pl
    extends Translations$settings$commitPreview$title$narrative$en {
  _Translations$settings$commitPreview$title$narrative$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'lis zaczął pomijać ciastka, które pachniały nie tak';
  @override
  String get s2 => 'Usiadłem z lisem i przeszliśmy, które ciastka odrzucać';
  @override
  String get s3 =>
      'Spędziłem większość popołudnia, przekonując lisa, że nie każde oferowane ciastko jest, w dobrej wierze, ciastkiem';
  @override
  String get def => 'Poprosiłem lisa, by obwąchiwał ciastka, zanim je zje';
}

// Path: settings.commitPreview.base.verbLed
class _Translations$settings$commitPreview$base$verbLed$pl
    extends Translations$settings$commitPreview$base$verbLed$en {
  _Translations$settings$commitPreview$base$verbLed$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Lis zerka. Cokolwiek nie tak — zostawia.';
  @override
  String get s2 =>
      'Lis ogląda każdy token, odrzuca wszystko o niewłaściwym zapachu i odnotowuje odmowę na ganku.';
  @override
  String get s3 =>
      'Lis okrąża każdy token, próbuje powietrza pod trzema kątami, odrzuca każdy, który czyta się źle, i czeka chwilę, by upewnić się, że odmowa się utrzyma.';
  @override
  String get def =>
      'Lis obwąchuje teraz każdy token i grzecznie odrzuca podejrzane.';
}

// Path: settings.commitPreview.base.descriptive
class _Translations$settings$commitPreview$base$descriptive$pl
    extends Translations$settings$commitPreview$base$descriptive$en {
  _Translations$settings$commitPreview$base$descriptive$pl._(
    TranslationsPl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Łagodne przepuszczenie dziwnych, przeważnie.';
  @override
  String get s2 =>
      'Udokumentowana odmowa dla każdego tokenu o niewłaściwym zapachu, wydana z ganku i odnotowana.';
  @override
  String get s3 =>
      'Notarialnie poświadczona odmowa dla każdego pachnącego nie tak tokenu, wydana z ganku z jedną uniesioną łapą, druga nieruchoma.';
  @override
  String get def => 'Grzeczna odmowa dla podejrzanych tokenów, wydana z ganku.';
}

// Path: settings.commitPreview.base.narrative
class _Translations$settings$commitPreview$base$narrative$pl
    extends Translations$settings$commitPreview$base$narrative$en {
  _Translations$settings$commitPreview$base$narrative$pl._(TranslationsPl root)
    : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Lis po prostu jakoś przestał jeść te dziwne. Łatwo.';
  @override
  String get s2 =>
      'Kiedyś każdy token schodził bez namysłu; teraz jest pauza, porządne spojrzenie i odmowa dla tych, które siedzą nie tak.';
  @override
  String get s3 =>
      'Kiedyś każdy token schodził bez namysłu. Teraz: pauza. Powietrze wciągnięte. Powietrze zatrzymane. Lis wypatruje na deskach ganku tego małego drgnięcia, które czasem mają, gdy coś jest nie tak, i dopiero wtedy zapada decyzja.';
  @override
  String get def =>
      'Kiedyś każdy token był połykany bez ceremonii; teraz najpierw jest wąch.';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class _Translations$settings$commitPreview$balancedSuffix$verbLed$pl
    extends Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  _Translations$settings$commitPreview$balancedSuffix$verbLed$pl._(
    TranslationsPl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Ganek w porządku. Podwórko jakoś tam.';
  @override
  String get s2 =>
      ' Ganek zamieciony po każdej odmowie; błoto na podwórku dozwolone w wyznaczonych godzinach.';
  @override
  String get s3 =>
      ' Ganek zamieciony i zamieciony ponownie; błoto na podwórku skatalogowane wg odcisków łap i pogody, a lis marudzi na progu dłużej niż dawniej.';
  @override
  String get def =>
      ' Ganek pozostaje czysty; podwórko zachowuje swoje prawa do błota.';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class _Translations$settings$commitPreview$balancedSuffix$descriptive$pl
    extends Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  _Translations$settings$commitPreview$balancedSuffix$descriptive$pl._(
    TranslationsPl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Ganek okej. Podwórko robi podwórkowe rzeczy.';
  @override
  String get s2 =>
      ' Ganek jako strefa czysta od dowodów; podwórko jako wyznaczona strefa błota, godziny podane.';
  @override
  String get s3 =>
      ' Ganek jako pomieszczenie czyste na poziomie dowodowym; podwórko jako skatalogowane archiwum błota; próg jako miejsce, gdzie lis stoi i myśli zbyt długo.';
  @override
  String get def => ' Czysty ganek; prawa do błota zachowane na podwórku.';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class _Translations$settings$commitPreview$balancedSuffix$narrative$pl
    extends Translations$settings$commitPreview$balancedSuffix$narrative$en {
  _Translations$settings$commitPreview$balancedSuffix$narrative$pl._(
    TranslationsPl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Ganek był w porządku. Podwórko, kto wie.';
  @override
  String get s2 =>
      ' Ganek potem trzymano w czystości; lis wycofał się na podwórko, gdzie odbywa się myślenie.';
  @override
  String get s3 =>
      ' Ganek wyszorowano tego wieczoru dwa razy. Lis wolno obszedł podwórko, przystanął przy tym samym słupku płotu co zawsze i obejrzał się na ganek, jakby ganek był mu coś winien.';
  @override
  String get def =>
      ' Ganek pozostaje czysty, choć podwórko wciąż wygrywa godnością.';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class _Translations$settings$commitPreview$everythingSuffix$verbLed$pl
    extends Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  _Translations$settings$commitPreview$everythingSuffix$verbLed$pl._(
    TranslationsPl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Bursztyn jest. Dryf dryfuje. Cierń kłuje, gdy musi. Przeważnie nic.';
  @override
  String get s2 =>
      ' Bursztyn przechowuje każdy zapach do przeglądu. Dryf niesie dzienne powietrze ku cierniowi u bramy, który znaczy każdą odmowę do wieczornego podliczenia.';
  @override
  String get s3 =>
      ' Bursztyn przechowuje każdy zapach i nadaje mu inną wagę zależnie od godziny. Dryf przemieszcza się przez ganek pod kątami, które nie powinny mieć znaczenia, ale mają. Cierń u bramy kłuje raz za odmowy i dwa razy za te, które lis omal nie przegapił, a lis zna różnicę, nawet gdy nikt inny jej nie zna.';
  @override
  String get def =>
      ' Bursztyn przechowuje zapach. Dryf niesie go dalej. Cierń u bramy łapie to, co nie powinno przejść.';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class _Translations$settings$commitPreview$everythingSuffix$descriptive$pl
    extends
        Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  _Translations$settings$commitPreview$everythingSuffix$descriptive$pl._(
    TranslationsPl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Bursztyn na słupku. Dryf w powietrzu. Cierń u bramy. W porządku.';
  @override
  String get s2 =>
      ' Bursztyn jako wyznaczony świadek zapachu; dryf jako zalogowane tło; ślady ciernia jako dzienny rejestr odmów, uzgodniony o zmierzchu.';
  @override
  String get s3 =>
      ' Bursztyn jako świadek zapachu, którego milczenie samo jest odczytem; dryf jako wzorzyste tło, poruszające się nie tak w te dni, gdy coś jest nie tak; cierń jako rachmistrz bramy, którego ślady lis sprawdza przed snem i znów przed świtem.';
  @override
  String get def =>
      ' Bursztyn jako świadek zapachu; dryf jako tło kontekstu; cierń jako cicha oznaka odmowy u bramy.';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class _Translations$settings$commitPreview$everythingSuffix$narrative$pl
    extends Translations$settings$commitPreview$everythingSuffix$narrative$en {
  _Translations$settings$commitPreview$everythingSuffix$narrative$pl._(
    TranslationsPl root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPl _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Bursztyn był w pobliżu. Dryf przychodził i odchodził. Cierń robił swoje ciche. Nieważne, było spokojnie.';
  @override
  String get s2 =>
      ' Bursztyn prowadził rejestr zapachów za dzień, dryf odnotowywano wg kierunku i godziny, a ślady ciernia podliczono i kontrasygnowano z ganku.';
  @override
  String get s3 =>
      ' Bursztyn prowadził rejestr zapachów, ale lis przysięga, że w niektóre poranki waży on więcej. Dryf poruszał się przez ganek jak zawsze, to znaczy nie tak w te dni, które się liczą. Cierń u bramy znaczył każdą odmowę; lis wychodził o pierwszym świetle je liczyć, tak jak liczy się schody, które już się policzyło.';
  @override
  String get def =>
      ' Bursztyn trzymał rejestr zapachów, dryf poruszał powietrze, a cierń u bramy łapał to, co trzeba było złapać.';
}
