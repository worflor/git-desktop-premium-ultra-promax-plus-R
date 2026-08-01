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
class TranslationsIt extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsIt({
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
             locale: AppLocale.it,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <it>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final TranslationsIt _root = this; // ignore: unused_field

  @override
  TranslationsIt $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsIt(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$agentSkills$it agentSkills =
      _Translations$agentSkills$it._(_root);
  @override
  late final _Translations$app$it app = _Translations$app$it._(_root);
  @override
  late final _Translations$backend$it backend = _Translations$backend$it._(
    _root,
  );
  @override
  late final _Translations$branches$it branches = _Translations$branches$it._(
    _root,
  );
  @override
  late final _Translations$changes$it changes = _Translations$changes$it._(
    _root,
  );
  @override
  late final _Translations$common$it common = _Translations$common$it._(_root);
  @override
  late final _Translations$diff$it diff = _Translations$diff$it._(_root);
  @override
  late final _Translations$filament$it filament = _Translations$filament$it._(
    _root,
  );
  @override
  late final _Translations$history$it history = _Translations$history$it._(
    _root,
  );
  @override
  late final _Translations$historySurgery$it historySurgery =
      _Translations$historySurgery$it._(_root);
  @override
  late final _Translations$onboarding$it onboarding =
      _Translations$onboarding$it._(_root);
  @override
  late final _Translations$orrery$it orrery = _Translations$orrery$it._(_root);
  @override
  late final _Translations$palette$it palette = _Translations$palette$it._(
    _root,
  );
  @override
  late final _Translations$releaseNotes$it releaseNotes =
      _Translations$releaseNotes$it._(_root);
  @override
  late final _Translations$repoSummary$it repoSummary =
      _Translations$repoSummary$it._(_root);
  @override
  late final _Translations$review$it review = _Translations$review$it._(_root);
  @override
  late final _Translations$settings$it settings = _Translations$settings$it._(
    _root,
  );
  @override
  late final _Translations$sync$it sync = _Translations$sync$it._(_root);
  @override
  late final _Translations$xray$it xray = _Translations$xray$it._(_root);
}

// Path: agentSkills
class _Translations$agentSkills$it extends Translations$agentSkills$en {
  _Translations$agentSkills$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get heading => 'Competenze dell\'agente';
  @override
  String get blurb =>
      'Anche i tuoi agenti possono usare le funzioni di Manifold.';
  @override
  String get installSoon => 'Installa nel client (a breve)';
  @override
  String copied({required Object title}) =>
      'Competenza ${title} copiata negli appunti';
  @override
  String savedTo({required Object path}) => 'Salvato in ${path}';
  @override
  String saveFailed({required Object error}) => 'Impossibile salvare: ${error}';
  @override
  String saveDialog({required Object title}) => 'Salva la competenza ${title}';
  @override
  late final _Translations$agentSkills$question$it question =
      _Translations$agentSkills$question$it._(_root);
}

// Path: app
class _Translations$app$it extends Translations$app$en {
  _Translations$app$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get panelSettings => 'Impostazioni';
  @override
  String get panelReleaseNotes => 'Note di rilascio';
  @override
  String get panelFilamentFindings => 'Riscontri Filament';
  @override
  String get filamentFindingsUpper => 'RISCONTRI FILAMENT';
  @override
  late final _Translations$app$cheatsheet$it cheatsheet =
      _Translations$app$cheatsheet$it._(_root);
  @override
  String get commandPaletteTooltip => 'Palette comandi   /';
  @override
  String get newDeskFallback => 'nuovo Desk';
  @override
  String get deskFallback => 'Desk';
  @override
  String get currentDeskFallback => 'corrente';
  @override
  String get noRepositoryOpen => 'Nessun repository aperto';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Impossibile aprire come Desk: ${error}';
  @override
  String couldNotDetectForge({required Object error}) =>
      'Impossibile rilevare la forge: ${error}';
  @override
  String get cannotFetchPrNoForge =>
      'Impossibile recuperare la PR: forge non rilevata per questo repo.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      'Sovrascrivere ${ref} con l\'ultima versione dal remoto?';
  @override
  String get overwrite => 'Sovrascrivi';
  @override
  String couldntFetchPr({required Object error}) =>
      'Impossibile recuperare la PR: ${error}';
  @override
  String get promoteDeskToPr => 'Promuovi Desk a PR';
  @override
  String get applyToMain => 'Applica a main';
  @override
  String updateDeskFrom({required Object target, required Object source}) =>
      'Aggiorna ${target} da ${source}';
  @override
  String bringChangesFromHere({required Object source}) =>
      'Porta qui le modifiche da ${source}';
  @override
  String get editLocalPr => 'Modifica PR locale';
  @override
  String get discardLocalPr => 'Scarta PR locale';
  @override
  String get closeDesk => 'Chiudi Desk';
  @override
  String couldntPromote({required Object error}) =>
      'Promozione non riuscita: ${error}';
  @override
  String get commitOrShelveBeforeApplying =>
      'Committa o metti da parte le modifiche del Desk prima di applicare.';
  @override
  String get couldNotResolveMainWorktree =>
      'Impossibile risolvere il percorso del worktree principale.';
  @override
  String couldntPromoteDesk({required Object error}) =>
      'Impossibile promuovere il Desk: ${error}';
  @override
  String get couldntDetermineBaseBranch =>
      'Impossibile determinare il branch di base per questo Desk.';
  @override
  String prBaseHeadSame({required Object branch}) =>
      'Base e head della PR sono lo stesso branch (${branch}) — niente da applicare.';
  @override
  String appliedBranchToBase({required Object branch, required Object base}) =>
      'Applicato ${branch} a ${base}';
  @override
  String updatedDeskToDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
    n,
    one: 'Aggiornato ${target} a ${source} (${n} commit).',
    other: 'Aggiornato ${target} a ${source} (${n} commit).',
  );
  @override
  String get fastForwardFailedFallback =>
      'Il fast-forward non è atterrato in modo pulito — mostro invece un\'anteprima patch.';
  @override
  String deskAheadOfDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
    n,
    one: '${target} è avanti a ${source} di ${n} commit.',
    other: '${target} è avanti a ${source} di ${n} commit.',
  );
  @override
  String deskUpToDate({required Object target, required Object source}) =>
      '${target} è già aggiornato allo stato di ${source}.';
  @override
  String uncommittedPreviewNotice({required Object target}) =>
      'Modifiche non committate in ${target} — anteprima come patch.';
  @override
  String updateDeskFromLower({
    required Object target,
    required Object source,
  }) => 'aggiorna ${target} da ${source}';
  @override
  String noUpdatesToBringFrom({required Object source}) =>
      'Nessun aggiornamento da portare da ${source}.';
  @override
  String get updatePrepFailed => 'Preparazione aggiornamento non riuscita';
  @override
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => 'porta le modifiche da ${source} in ${target}';
  @override
  String noPatchableChanges({required Object source, required Object target}) =>
      'Nessuna modifica applicabile come patch da portare da ${source} in ${target}.';
  @override
  String get patchPrepFailed => 'Preparazione patch non riuscita';
  @override
  String failureWithError({required Object label, required Object error}) =>
      '${label}: ${error}';
  @override
  String get titleHint => 'titolo';
  @override
  String get bodyHint => 'corpo';
  @override
  String get bodyOptionalHint => 'corpo (opzionale)';
  @override
  String get draftLower => 'bozza';
  @override
  String get cancelLower => 'annulla';
  @override
  String get saveLower => 'salva';
  @override
  String couldntSave({required Object error}) =>
      'Impossibile salvare: ${error}';
  @override
  String get stashedNoOtherDesk =>
      'Modifiche in stash — nessun altro Desk su cui applicarle. Usa git stash pop per recuperarle.';
  @override
  String get suggestedSource => 'sorgente suggerita';
  @override
  String tooltipModifiedCount({required Object n}) => '${n} modificati';
  @override
  String tooltipAheadCount({required Object n}) => '${n} avanti';
  @override
  String tooltipBehindCount({required Object n}) => '${n} indietro';
  @override
  String get focusedEdits => 'modifiche mirate';
  @override
  String get editsSpreadAcrossSubsystems =>
      'modifiche sparse tra i sottosistemi';
  @override
  String get editsTouchingManySubsystems =>
      'modifiche che toccano molti sottosistemi';
  @override
  String get focusedBranch => 'branch mirato';
  @override
  String get branchSpansMultipleSubsystems =>
      'il branch attraversa più sottosistemi';
  @override
  String get structurallyDivergentFromMainline =>
      'strutturalmente divergente dal ramo principale';
  @override
  String get localPr => 'PR locale';
  @override
  String lastTouched({required Object time}) => 'ultimo tocco ${time}';
  @override
  String driftGroupCount({required Object n, required Object dir}) =>
      '${n} in ${dir}';
  @override
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';
  @override
  String get uncommittedChanges => 'Modifiche non committate';
  @override
  String get closeDeskQuestion => 'Chiudere il Desk?';
  @override
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} file non committato.',
        other: '${n} file non committati.',
      );
  @override
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} commit avanti a main.',
        other: '${n} commit avanti a main.',
      );
  @override
  String get willRemoveWorktreeDirectory =>
      'Questo rimuoverà la directory del worktree.';
  @override
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} file modificato',
        other: '${n} file modificati',
      );
  @override
  String get shelveHere => 'Metti da parte qui';
  @override
  String get discardAndClose => 'Scarta e chiudi';
  @override
  String get noRepository => 'nessun repository';
  @override
  String get issuePromotedToRemote => 'Issue promossa al remoto.';
  @override
  String get pushedToRemote => 'Push sul remoto eseguito.';
  @override
  String get pulledFromRemote => 'Pull dal remoto eseguito.';
  @override
  String get remoteIssueNotFound => 'issue remota non trovata';
  @override
  String importedIssueLocally({required Object id}) =>
      'Importata #${id} localmente.';
  @override
  String get issueAbandoned => 'Issue abbandonata.';
  @override
  String get abandonIssue => 'Abbandona issue';
  @override
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      'Rimuovere definitivamente l\'issue locale #${id}? Questo elimina la sua ref e non è annullabile.';
  @override
  String get abandon => 'Abbandona';
  @override
  String publishedBranch({required Object branch}) => 'Pubblicato ${branch}.';
  @override
  String get publishingEllipsis => 'Pubblicazione…';
  @override
  String get publish => 'Pubblica';
  @override
  String get noRemoteConfigured =>
      'Nessun remoto configurato per questo repository.';
  @override
  String get jumpToDesk => 'Vai al Desk';
  @override
  String get arrowOpen => '→ apri';
  @override
  String get openOnANewDesk => 'Apri su un nuovo Desk';
  @override
  String get plusDesk => '+ Desk';
  @override
  String get plusSpace => '+ ';
  @override
  String get newBranchNameHint => 'nome-nuovo-branch';
  @override
  String get escLower => 'esc';
  @override
  String get plusNewDesk => '+ nuovo Desk';
  @override
  String get fromHeadEllipsis => 'da HEAD...';
  @override
  String get viewAllBranches => 'Vedi tutti i branch';
  @override
  String get issuesLower => 'issue';
  @override
  String get newIssueLower => 'nuova issue';
  @override
  String get noneLinked => 'nessun collegamento';
  @override
  String get noOpenIssues => 'nessuna issue aperta';
  @override
  String get createAndPushLower => 'crea + push';
  @override
  String get createLower => 'crea';
  @override
  String get remoteLower => 'remoto';
  @override
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';
  @override
  String get promoteToRemote => 'Promuovi al remoto';
  @override
  String get pushToRemote => 'Push sul remoto';
  @override
  String get pullFromRemote => 'Pull dal remoto';
  @override
  String get importLabel => 'Importa';
  @override
  String get failedToCreateRepository =>
      'Creazione del repository non riuscita.';
  @override
  String get openRepositoryLower => 'apri repository';
  @override
  String get newRepositoryLower => 'nuovo repository';
  @override
  String get back => 'Indietro';
  @override
  String get openRepositoryDialogTitle => 'Apri repository';
  @override
  String get createRepositoryDialogTitle => 'Crea repository';
  @override
  String get cloneTargetDialogTitle => 'Destinazione clone';
  @override
  String get cloneToDialogTitle => 'Clona in';
  @override
  String get exportToDialogTitle => 'Esporta in';
  @override
  String get createFromTemplateInDialogTitle => 'Crea da template in';
  @override
  String get notAGitRepoInitConfirm =>
      'Non è un repository git. Inizializzarne uno qui?';
  @override
  String get repositoryUrlRequired => 'URL del repository richiesto.';
  @override
  String get failedToCloneRepository =>
      'Clonazione del repository non riuscita.';
  @override
  String cloningEllipsis({required Object name}) => 'Clonazione di ${name}...';
  @override
  String get cloneCancelled => 'Clonazione annullata.';
  @override
  String get noProjectsYet => 'Ancora nessun progetto';
  @override
  String get dissolveGroup => 'Dissolvi gruppo';
  @override
  String get projectsHeader => 'Progetti';
  @override
  String get cloneLabel => 'Clona';
  @override
  String get createLabel => 'Crea';
  @override
  String get openLabel => 'Apri';
  @override
  String get repositoryUrlPlaceholder => 'URL del repository';
  @override
  String get projectNameOrFullPathPlaceholder =>
      'nome-progetto o percorso completo';
  @override
  String get pathToProjectPlaceholder => '/percorso/al/progetto';
  @override
  String get cloneToFolderPathPlaceholder =>
      'Percorso cartella di destinazione';
  @override
  String get switchToCreateRepo => 'Passa a Crea repo';
  @override
  String get explorer => 'Explorer';
  @override
  String get terminal => 'Terminale';
  @override
  String get cloneUrl => 'URL clone';
  @override
  String get copyPath => 'Copia percorso';
  @override
  String get export => 'Esporta';
  @override
  String get readme => 'README';
  @override
  String get duplicate => 'Duplica';
  @override
  String get template => 'Template';
  @override
  String get forgetThisProject => 'Dimentica questo progetto';
  @override
  String get aiKindCommitMessage => 'messaggio di commit';
  @override
  String get aiKindReview => 'review';
  @override
  String get aiKindMuse => 'muse';
  @override
  String get aiKindPresent => 'presenta';
  @override
  String get aiKindDebug => 'debug';
  @override
  String aiStatusRunning({required Object kind}) => '${kind} in corso';
  @override
  String aiStatusFailedUnread({required Object kind}) =>
      '${kind} fallito (non letto)';
  @override
  String aiStatusReadyUnread({required Object kind}) =>
      '${kind} pronto (non letto)';
  @override
  String get filesLower => 'file';
  @override
  String get commitsLower => 'commit';
  @override
  String get undoLabel => 'Annulla';
  @override
  String get goLabel => 'vai';
  @override
  String countdownSeconds({required Object n}) => '${n}s';
  @override
  String get collapseGlyph => '▲ comprimi';
  @override
  String moreLinesGlyph({required Object n}) => '▼ ${n} altre righe';
}

// Path: backend
class _Translations$backend$it extends Translations$backend$en {
  _Translations$backend$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$backend$ops$it ops = _Translations$backend$ops$it._(
    _root,
  );
  @override
  late final _Translations$backend$mergeOutcome$it mergeOutcome =
      _Translations$backend$mergeOutcome$it._(_root);
}

// Path: branches
class _Translations$branches$it extends Translations$branches$en {
  _Translations$branches$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get runningAiReview => 'Review AI in corso…';
  @override
  String prNumberLabel({required Object number}) => 'PR #${number}';
  @override
  String get findings => 'RISCONTRI';
  @override
  String get observations => 'OSSERVAZIONI';
  @override
  String get renameEllipsis => 'Rinomina…';
  @override
  String get publish => 'Pubblica';
  @override
  String publishFailed({required Object error}) =>
      'Pubblicazione non riuscita: ${error}';
  @override
  String couldntOpenDesk({required Object error}) =>
      'Impossibile aprire il Desk: ${error}';
  @override
  String syncFailed({required Object error}) => 'Sync non riuscito: ${error}';
  @override
  String get renameBranchTitle => 'Rinomina branch';
  @override
  String get newNameHint => 'nuovo nome';
  @override
  String get rename => 'Rinomina';
  @override
  String invalidBranchName({required Object name}) =>
      '\'${name}\' non è un nome di branch valido.';
  @override
  String renameFailed({required Object error}) =>
      'Rinomina non riuscita: ${error}';
  @override
  String deletingBranch({required Object name}) => 'Eliminazione di ${name}';
  @override
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '\'${name}\' è aperto nel Desk \'${desk}\'.';
  @override
  String get openDesk => 'Apri Desk';
  @override
  String openInDeskShort({required Object desk}) => 'apri nel Desk \'${desk}\'';
  @override
  String get couldNotPinBranch =>
      'impossibile fissare la punta del branch; eliminazione saltata';
  @override
  String get couldNotPinTag =>
      'impossibile fissare il tag; eliminazione saltata';
  @override
  String deletingTag({required Object name}) => 'Eliminazione del tag ${name}';
  @override
  String get applyToActiveChanges => 'Applica alle modifiche attive…';
  @override
  String get couldNotLoadPrDiff => 'Impossibile caricare il diff della PR.';
  @override
  String prSourceLabel({required Object number, required Object title}) =>
      'PR #${number}: ${title}';
  @override
  String mergeIntoDesk({required Object branch}) => 'Merge in ${branch}…';
  @override
  String get checkoutThisPr => 'Checkout di questa PR';
  @override
  String get mergeIntoNewDesk => 'Merge in un nuovo Desk…';
  @override
  String get pushToForge => 'Push alla forge';
  @override
  String get linkToIssue => 'Collega a issue…';
  @override
  String get gitPatch => '↓ git patch';
  @override
  String get copyBranchName => 'Copia nome branch';
  @override
  String copiedRef({required Object ref}) => 'Copiato "${ref}"';
  @override
  String get reviewPr => 'Rivedi PR';
  @override
  String get openInBrowser => 'Apri nel browser';
  @override
  String get markAsRead => 'Segna come letto';
  @override
  String get markAsUnread => 'Segna come non letto';
  @override
  String get replaceLocalCommitsTitle => 'Sostituire i commit locali?';
  @override
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref} ha commit locali che non sono sull\'head remoto della PR. Aggiornandolo verranno sostituiti con l\'ultima versione dal remoto.';
  @override
  String get update => 'Aggiorna';
  @override
  String couldntFetchPr({required Object error}) =>
      'Impossibile recuperare la PR: ${error}';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Impossibile aprire come Desk: ${error}';
  @override
  String couldntOpenInBrowser({required Object error}) =>
      'Impossibile aprire nel browser: ${error}';
  @override
  String get noIssuesYetLocal =>
      'Ancora nessuna issue. Aprine una upstream, oppure usa "+ nuova issue locale" nella lente issue.';
  @override
  String get remotePrsLinkLocalOnly =>
      'Le PR remote possono collegarsi solo a issue locali. Creane una con "+ nuova issue locale".';
  @override
  String linkPrToIssues({required Object number}) =>
      'Collega la PR #${number} a issue';
  @override
  String get noPrsYetLocal =>
      'Ancora nessuna PR. Aprine una upstream, o promuovi un Desk a PR.';
  @override
  String get remoteIssuesLinkLocalOnly =>
      'Le issue remote possono collegarsi solo a PR locali. Prima promuovi un Desk a PR.';
  @override
  String linkIssueToPrs({required Object number}) =>
      'Collega la issue #${number} a PR';
  @override
  String couldntToggleLink({required Object error}) =>
      'Impossibile commutare il collegamento: ${error}';
  @override
  String get openPatchDialogTitle => 'Apri patch (.patch / .diff)';
  @override
  String get clipboardNoText => 'Gli appunti non contengono testo.';
  @override
  String get clipboardPatchLabel => 'clipboard.patch';
  @override
  String failedToOpenPatch({required Object error}) =>
      'Impossibile aprire la patch: ${error}';
  @override
  String get patchEmptyOrUnparseable => 'La patch è vuota o non analizzabile.';
  @override
  String get prPushedToForge => 'PR inviata alla forge.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      'Sovrascrivere ${ref} con l\'ultima versione dal remoto?';
  @override
  String get overwrite => 'Sovrascrivi';
  @override
  String get loadingBranchesTitle => 'Caricamento branch';
  @override
  String get loadingBranchesMessage => 'Lettura di branch e tag locali.';
  @override
  String get branchesUnavailableTitle => 'Branch non disponibili';
  @override
  String get filterPullRequestsHint => 'filtra pull request…';
  @override
  String get filterIssuesHint => 'filtra issue…';
  @override
  String get branchNameHint => 'nome branch';
  @override
  String get tagsNewestFirst => 'tag, dal più recente';
  @override
  String get tagsOldestFirst => 'tag, dal più vecchio';
  @override
  String get flipSortDirection => 'inverti direzione ordinamento';
  @override
  String get readingPullRequests => 'Lettura delle pull request…';
  @override
  String get noOpenPullRequests => 'Nessuna pull request aperta';
  @override
  String get noPullRequestsHint =>
      'Aprine una da un branch, o promuovi un Desk.';
  @override
  String get noPrsMatchFilters => 'Nessuna PR corrisponde a questi filtri';
  @override
  String get toggleFiltersRowAbove => 'Disattiva i filtri nella riga sopra.';
  @override
  String get issuesNewestFirst => 'issue, dalla più recente';
  @override
  String get issuesOldestFirst => 'issue, dalla più vecchia';
  @override
  String get issuesHeading => 'ISSUE';
  @override
  String get readingIssuesLower => 'lettura issue…';
  @override
  String get noOpenIssues => 'Nessuna issue aperta';
  @override
  String get noIssuesHint => '+ nuova per tracciare lavoro e bug.';
  @override
  String get nothingMatches => 'Nessuna corrispondenza';
  @override
  String get toggleFiltersAbove => 'Disattiva i filtri qui sopra.';
  @override
  String get bucketFresh => 'FRESCHE';
  @override
  String get bucketThisWeek => 'QUESTA SETTIMANA';
  @override
  String get bucketStalled => 'IN STALLO';
  @override
  String get bucketOlder => 'PIÙ VECCHIE';
  @override
  String get couldNotResolveMainWorktree =>
      'Impossibile risolvere il percorso del worktree principale.';
  @override
  String couldntSubmitReview({required Object error}) =>
      'Impossibile inviare la review: ${error}';
  @override
  String get reviewAiNotAvailable => 'La review AI non è ancora disponibile.';
  @override
  String get noReviewModelConfigured => 'Nessun modello di review configurato.';
  @override
  String get deskFallback => 'Desk';
  @override
  String deskUncommittedChanges({
    required num n,
    required Object branch,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
    n,
    one:
        '${branch} ha ${n} modifica non committata — committa o fai stash prima.',
    other:
        '${branch} ha ${n} modifiche non committate — committa o fai stash prima.',
  );
  @override
  String get targetDeskNoBranch => 'Il Desk di destinazione non ha un branch.';
  @override
  String mergePrIntoDesk({required Object number, required Object branch}) =>
      'Merge della PR #${number} in ${branch}';
  @override
  String get conflictCheckUnavailableVersion =>
      'Controllo conflitti non disponibile — richiesto git 2.38+';
  @override
  String get conflictCheckUnavailable => 'Controllo conflitti non disponibile';
  @override
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'IN CONFLITTO · ${n} file',
        other: 'IN CONFLITTO · ${n} file',
      );
  @override
  String plusMore({required Object n}) => '+${n} altri';
  @override
  String get rebase => 'Rebase';
  @override
  String get squash => 'Squash';
  @override
  String get mergeCommit => 'Merge commit';
  @override
  String noDeskForBranch({required Object branch}) =>
      'Nessun Desk trovato per il branch ${branch}';
  @override
  String get mergeAnyway => 'Merge comunque';
  @override
  String get readingIssues => 'Lettura issue…';
  @override
  String get openUpstreamOrLocal => 'Aprine una upstream, o aprine una locale.';
  @override
  String get noIssuesMatchFilters =>
      'Nessuna issue corrisponde a questi filtri';
  @override
  String couldntCreateIssue({required Object error}) =>
      'Impossibile creare la issue: ${error}';
  @override
  String get promoteToRemote => 'Promuovi al remoto';
  @override
  String get pushToRemote => 'Push sul remoto';
  @override
  String get pullFromRemote => 'Pull dal remoto';
  @override
  String get import => 'Importa';
  @override
  String get linkToPr => 'Collega a PR…';
  @override
  String get abandon => 'Abbandona';
  @override
  String get issuePromotedToRemote => 'Issue promossa al remoto.';
  @override
  String get issuePushedToRemote => 'Push sul remoto eseguito.';
  @override
  String get issuePulledFromRemote => 'Pull dal remoto eseguito.';
  @override
  String issueImportedLocally({required Object number}) =>
      'Importata #${number} localmente.';
  @override
  String get abandonIssueTitle => 'Abbandona issue';
  @override
  String abandonIssueMessage({required Object id}) =>
      'Rimuovere definitivamente l\'issue locale #${id}? Questo elimina la sua ref e non è annullabile.';
  @override
  String couldntAbandon({required Object error}) =>
      'Impossibile abbandonare: ${error}';
  @override
  String couldntPostComment({required Object error}) =>
      'Impossibile pubblicare il commento: ${error}';
  @override
  String couldntCloseIssue({required Object error}) =>
      'Impossibile chiudere la issue: ${error}';
  @override
  String couldntAddLabel({required Object error}) =>
      'Impossibile aggiungere l\'etichetta: ${error}';
  @override
  String get lensBranches => 'BRANCH';
  @override
  String get lensPrs => 'PR';
  @override
  String get patchUp => '↑ patch';
  @override
  String get syncRibbon => '⇅ sync';
  @override
  String get kbHeading => 'TASTIERA';
  @override
  String get kbNavigateRows => 'naviga tra le righe';
  @override
  String get kbExpandCollapse => 'espandi / comprimi la riga a fuoco';
  @override
  String get kbCheckoutPr => 'checkout locale della PR a fuoco';
  @override
  String get kbApproveReview => 'approva · review';
  @override
  String get kbRequestChanges => 'richiedi modifiche';
  @override
  String get kbFocusSearch => 'vai alla ricerca';
  @override
  String get kbSwitchLens => 'cambia lente (branch · pr)';
  @override
  String get kbToggleOverlay => 'attiva/disattiva questo overlay';
  @override
  String get kbPressToDismiss => 'premi ovunque per chiudere';
  @override
  String get overrideScarTooltip =>
      'mergiato con check falliti o senza una review di approvazione — indaga prima, sotto tiro';
  @override
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} file si sovrappone al tuo lavoro non committato',
        other: '${n} file si sovrappongono al tuo lavoro non committato',
      );
  @override
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '#${pr}  (${n} file)',
        other: '#${pr}  (${n} file)',
      );
  @override
  String get prStateDraft => 'DRAFT';
  @override
  String get localBadge => 'LOCALE';
  @override
  String get myReviewPending => 'la tua review in attesa';
  @override
  String get myReviewApproved => 'tu ✓';
  @override
  String get myReviewChangesRequested => 'tu ✗ modifiche richieste';
  @override
  String get myReviewCommented => 'hai commentato';
  @override
  String get myReviewDefault => 'tu';
  @override
  String tailCommentsAuthor({required Object count}) =>
      '${count} commenti · mostrato l\'ultimo dell\'autore';
  @override
  String get tailLastComment => 'ultimo commento';
  @override
  String tailLastReviewState({required Object state}) =>
      'ultima review · ${state}';
  @override
  String get tailLastReview => 'ultima review';
  @override
  String tailLastCheckState({required Object state}) =>
      'ultimo check · ${state}';
  @override
  String get tailLastCommit => 'ultimo commit';
  @override
  String get tailLastActivity => 'ultima attività';
  @override
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'chiude ${n} issue — clicca per saltare',
        other: 'chiude ${n} issue — clicca per saltare',
      );
  @override
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'affrontata da ${n} PR — clicca per saltare',
        other: 'affrontata da ${n} PR — clicca per saltare',
      );
  @override
  String get checksLabel => 'check';
  @override
  String get reviewersLabel => 'reviewer';
  @override
  String get conflictsLabel => 'conflitti';
  @override
  String exportFailed({required Object error}) =>
      'Esportazione non riuscita: ${error}';
  @override
  String get readingFiles => 'lettura file…';
  @override
  String get noDetailAvailable => 'nessun dettaglio disponibile';
  @override
  String get noFilesReported => 'nessun file segnalato';
  @override
  String get readingGitHistory => 'lettura cronologia git…';
  @override
  String get knowsThisCode => 'conosce questo codice';
  @override
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} commit su questi file nell\'ultimo anno',
        other: '${n} commit su questi file nell\'ultimo anno',
      );
  @override
  String get willFight => 'SI SCONTRERÀ';
  @override
  String orbitalPartnerCos({required Object cos}) =>
      'partner orbitale — cos ${cos}';
  @override
  String get orbitLabel => 'orbita';
  @override
  String get touchesYourLocalWork => 'TOCCA IL TUO LAVORO LOCALE';
  @override
  String get mergingWillConflict =>
      'il merge andrà probabilmente in conflitto con le tue modifiche non committate';
  @override
  String get closesHeading => 'CHIUDE';
  @override
  String get filesHeading => 'FILE';
  @override
  String get orientAligned => 'allineato';
  @override
  String get orientAdjacent => 'adiacente';
  @override
  String get orientOrthogonal => 'ortogonale';
  @override
  String shapeField({required Object v}) => 'campo ${v}';
  @override
  String shapeSource({required Object v}) => 'sorgente ${v}';
  @override
  String shapeSrcDelta({required Object v}) => 'sorgΔ ${v}';
  @override
  String shapeFldDelta({required Object v}) => 'campoΔ ${v}';
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
  String resonanceReadout({required Object v}) => 'risonanza ${v}';
  @override
  String ghostFileTooltip({required Object path}) =>
      'di solito si muove con i file di questa PR\n(${path})';
  @override
  String get prStateDraftLower => 'bozza';
  @override
  String get keystoneTooltip =>
      'pietra angolare — file ponte a livello di repo';
  @override
  String get reviewNoteHint => 'lascia una nota (opzionale)…';
  @override
  String get reviewComment => 'commenta';
  @override
  String get reviewRequestChanges => 'richiedi modifiche';
  @override
  String get reviewApprove => '✓ approva';
  @override
  String get actionPatchDown => '↓ patch';
  @override
  String get actionPrReview => '✦ review pr';
  @override
  String get actionOpenAsDesk => '⊞ apri come Desk';
  @override
  String get actionCheckout => '[c] checkout';
  @override
  String get actionMerge => '[m] merge ▾';
  @override
  String get mergeMenuMergeCommit => 'merge commit';
  @override
  String get mergeMenuSquash => 'squash & merge';
  @override
  String get mergeMenuRebase => 'rebase & merge';
  @override
  String get deleteBranchAfter => 'elimina il branch dopo';
  @override
  String checkDurationSec({required Object n}) => '${n}s';
  @override
  String checkDurationMin({required Object m, required Object s}) =>
      '${m}m ${s}s';
  @override
  String assignedTo({required Object names}) => 'assegnata: ${names}';
  @override
  String issueConvLine({required Object n, required Object time}) =>
      '${n} conv · ${time}';
  @override
  String get readingThread => 'lettura thread…';
  @override
  String get addressedByHeading => 'AFFRONTATA DA';
  @override
  String get descriptionHeading => 'DESCRIZIONE';
  @override
  String get threadHeading => 'THREAD';
  @override
  String get replyHint => 'rispondi…';
  @override
  String get assignMe => 'assegna a me';
  @override
  String get closeLower => 'chiudi';
  @override
  String get postReply => '↩ pubblica';
  @override
  String get remoteProviderUnavailable => 'Provider remoto non disponibile';
  @override
  String get noRecognisedRemoteHost =>
      'Nessun host remoto riconosciuto per questo repo.';
  @override
  String get corpseGone => 'sparito';
  @override
  String get corpseAbsorbed => 'assorbito';
  @override
  String get corpseSquashed => 'squashato';
  @override
  String absorbedDeliveredIn({required Object hash}) => 'consegnato in ${hash}';
  @override
  String get absorbedNoChanges => 'il merge non aggiunge modifiche';
  @override
  String get corpseTagUpstreamGone => 'upstream sparito';
  @override
  String corpseTagAbsorbed({required Object receipt}) =>
      'assorbito, ${receipt}';
  @override
  String get corpseTagSquashed => 'squashato e mergiato';
  @override
  String semanticsCurrentBranch({required Object name}) =>
      '${name}, branch corrente';
  @override
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}, traccia ${upstream}';
  @override
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}, ${tag}';
  @override
  String semanticsWorktreeOpen({required Object label}) =>
      '${label}, worktree aperto';
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
  String get crossLinkPrDraft => 'PR · bozza';
  @override
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} issue',
        other: '${n} issue',
      );
  @override
  String get headBadge => 'HEAD';
  @override
  String trackingLine({required Object upstream}) => '→ tracking: ${upstream}';
  @override
  String get checkoutButton => 'Checkout';
  @override
  String get createBranch => 'Crea branch';
  @override
  String get newBranchName => 'Nome del nuovo branch';
  @override
  String newBranchNameError({required Object error}) =>
      'Nome del nuovo branch — ${error}';
  @override
  String get forceDelete => 'Forzare?';
  @override
  String get annotated => 'annotato';
  @override
  String get applyCheckFailed => 'apply --check non riuscito';
  @override
  String get openPatchFrom => 'APRI PATCH DA';
  @override
  String get patchFromFile => 'da file…';
  @override
  String get patchFromFileHint => '.patch / .diff';
  @override
  String get patchFromClipboard => 'dagli appunti';
  @override
  String get patchFromClipboardHint => 'incolla il testo';
  @override
  String get patchPreviewHeading => 'ANTEPRIMA PATCH';
  @override
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';
  @override
  String get stagedDone => 'in stage.';
  @override
  String get appliedDone => 'applicato.';
  @override
  String get opening => 'apertura…';
  @override
  String get mergeEditor => '⇋ editor di merge';
  @override
  String get staging => 'staging…';
  @override
  String get applying => 'applicazione…';
  @override
  String get stage => 'stage';
  @override
  String get apply => 'applica';
  @override
  String get refineHint => 'affina… (es. "togli anche le modifiche al logger")';
  @override
  String get reverseArmedTooltip =>
      'armato — la prossima applicazione REVERTIRÀ la patch (-R)';
  @override
  String get reverseDisarmedTooltip =>
      'arma il reverse (-R) — annulla invece di applicare';
  @override
  String get reverseArmedLabel => '⟲ reverse ✓';
  @override
  String get reverseLabel => '⟲ reverse';
  @override
  String get untouchedHeading => '⚠ INTATTI';
  @override
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${count} di ${n} file non nella patch',
        other: '${count} di ${n} file non nella patch',
      );
  @override
  String get staysConflicted =>
      'questi file resteranno in conflitto — applicare non li metterà in stage';
  @override
  String get orWith => 'OPPURE CON';
  @override
  String get noAiModelConfigured => 'nessun modello AI configurato';
  @override
  String applyWithPatchFrom({required Object label}) =>
      'applica con patch da ${label}';
  @override
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => 'applica con patch da ${label}  ·  ${model}';
  @override
  String get patching => 'patching…';
  @override
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  applica con patch da ${label}';
  @override
  String get orWithAnotherModel => 'o con un altro modello';
  @override
  String get applyCheckPassed =>
      'git apply --check superato — la patch verrà applicata in modo pulito';
  @override
  String get gitApplyCheckFailed => 'git apply --check non riuscito';
  @override
  String get appliesClean => 'si applica in modo pulito';
  @override
  String get willNotApply => 'non verrà applicato';
  @override
  String get newLocalIssue => 'nuova issue locale';
  @override
  String get filterHint => 'filtra…';
  @override
  String get nothingToLink => 'Ancora nulla da collegare.';
  @override
  String get nothingMatchesDot => 'Nessuna corrispondenza.';
  @override
  String get relevantHeading => 'RILEVANTI';
  @override
  String get allHeading => 'TUTTE';
  @override
  String get doneLower => 'fatto';
  @override
  String get candidateRemote => 'R';
  @override
  String get candidateLocal => 'L';
  @override
  String get newLocalIssueTitle => 'Nuova issue locale';
  @override
  String get titleHint => 'titolo';
  @override
  String get bodyHint => 'corpo (markdown)';
  @override
  String get cancelLower => 'annulla';
  @override
  String get createLower => 'crea';
  @override
  String get deleteFailed => 'eliminazione non riuscita';
  @override
  String reviewFailed({required Object error}) =>
      'Review non riuscita: ${error}';
  @override
  String get resolutionFailed => 'risoluzione non riuscita';
  @override
  String get patchBlocksNoCover =>
      'il modello ha restituito blocchi di patch che non coprivano i file falliti';
  @override
  String get applyFailed => 'applicazione non riuscita';
  @override
  String get emptyOrUnparseablePatch =>
      'il modello ha restituito una patch vuota o non analizzabile';
  @override
  String noModelConfiguredFor({required Object label}) =>
      'nessun modello configurato per "${label}"';
  @override
  String get checksHeading => 'CONTROLLI';
  @override
  String get peopleHeading => 'PERSONE';
  @override
  String get conversationHeading => 'CONVERSAZIONE';
}

// Path: changes
class _Translations$changes$it extends Translations$changes$en {
  _Translations$changes$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$usage$it usage =
      _Translations$changes$usage$it._(_root);
  @override
  late final _Translations$changes$tabs$it tabs =
      _Translations$changes$tabs$it._(_root);
  @override
  late final _Translations$changes$tabStrip$it tabStrip =
      _Translations$changes$tabStrip$it._(_root);
  @override
  late final _Translations$changes$select$it select =
      _Translations$changes$select$it._(_root);
  @override
  late final _Translations$changes$constellationToggle$it constellationToggle =
      _Translations$changes$constellationToggle$it._(_root);
  @override
  late final _Translations$changes$nudgeChip$it nudgeChip =
      _Translations$changes$nudgeChip$it._(_root);
  @override
  late final _Translations$changes$minimap$it minimap =
      _Translations$changes$minimap$it._(_root);
  @override
  late final _Translations$changes$tagInput$it tagInput =
      _Translations$changes$tagInput$it._(_root);
  @override
  late final _Translations$changes$composer$it composer =
      _Translations$changes$composer$it._(_root);
  @override
  late final _Translations$changes$commit$it commit =
      _Translations$changes$commit$it._(_root);
  @override
  late final _Translations$changes$rebase$it rebase =
      _Translations$changes$rebase$it._(_root);
  @override
  late final _Translations$changes$editor$it editor =
      _Translations$changes$editor$it._(_root);
  @override
  late final _Translations$changes$editorTitles$it editorTitles =
      _Translations$changes$editorTitles$it._(_root);
  @override
  late final _Translations$changes$askHint$it askHint =
      _Translations$changes$askHint$it._(_root);
  @override
  late final _Translations$changes$fileMenu$it fileMenu =
      _Translations$changes$fileMenu$it._(_root);
  @override
  late final _Translations$changes$multiFileMenu$it multiFileMenu =
      _Translations$changes$multiFileMenu$it._(_root);
  @override
  late final _Translations$changes$ignoreMenu$it ignoreMenu =
      _Translations$changes$ignoreMenu$it._(_root);
  @override
  late final _Translations$changes$discard$it discard =
      _Translations$changes$discard$it._(_root);
  @override
  late final _Translations$changes$snack$it snack =
      _Translations$changes$snack$it._(_root);
  @override
  late final _Translations$changes$trace$it trace =
      _Translations$changes$trace$it._(_root);
  @override
  late final _Translations$changes$cleanTree$it cleanTree =
      _Translations$changes$cleanTree$it._(_root);
  @override
  late final _Translations$changes$guardrail$it guardrail =
      _Translations$changes$guardrail$it._(_root);
  @override
  late final _Translations$changes$dropHint$it dropHint =
      _Translations$changes$dropHint$it._(_root);
  @override
  late final _Translations$changes$diffEmpty$it diffEmpty =
      _Translations$changes$diffEmpty$it._(_root);
  @override
  late final _Translations$changes$shelvePill$it shelvePill =
      _Translations$changes$shelvePill$it._(_root);
  @override
  late final _Translations$changes$stashAction$it stashAction =
      _Translations$changes$stashAction$it._(_root);
  @override
  late final _Translations$changes$stashContents$it stashContents =
      _Translations$changes$stashContents$it._(_root);
  @override
  late final _Translations$changes$stashFile$it stashFile =
      _Translations$changes$stashFile$it._(_root);
  @override
  late final _Translations$changes$fileRow$it fileRow =
      _Translations$changes$fileRow$it._(_root);
  @override
  late final _Translations$changes$resolveStrip$it resolveStrip =
      _Translations$changes$resolveStrip$it._(_root);
  @override
  late final _Translations$changes$badge$it badge =
      _Translations$changes$badge$it._(_root);
  @override
  late final _Translations$changes$review$it review =
      _Translations$changes$review$it._(_root);
  @override
  late final _Translations$changes$commitBtn$it commitBtn =
      _Translations$changes$commitBtn$it._(_root);
  @override
  late final _Translations$changes$shapeBtn$it shapeBtn =
      _Translations$changes$shapeBtn$it._(_root);
  @override
  late final _Translations$changes$dejaVu$it dejaVu =
      _Translations$changes$dejaVu$it._(_root);
  @override
  late final _Translations$changes$identity$it identity =
      _Translations$changes$identity$it._(_root);
  @override
  late final _Translations$changes$staleScope$it staleScope =
      _Translations$changes$staleScope$it._(_root);
  @override
  late final _Translations$changes$finding$it finding =
      _Translations$changes$finding$it._(_root);
  @override
  late final _Translations$changes$muse$it muse =
      _Translations$changes$muse$it._(_root);
  @override
  late final _Translations$changes$debug$it debug =
      _Translations$changes$debug$it._(_root);
  @override
  late final _Translations$changes$includeSummary$it includeSummary =
      _Translations$changes$includeSummary$it._(_root);
  @override
  late final _Translations$changes$status$it status =
      _Translations$changes$status$it._(_root);
  @override
  late final _Translations$changes$stash$it stash =
      _Translations$changes$stash$it._(_root);
  @override
  late final _Translations$changes$tooltips$it tooltips =
      _Translations$changes$tooltips$it._(_root);
  @override
  late final _Translations$changes$mergeEditor$it mergeEditor =
      _Translations$changes$mergeEditor$it._(_root);
  @override
  late final _Translations$changes$conflictResolution$it conflictResolution =
      _Translations$changes$conflictResolution$it._(_root);
  @override
  late final _Translations$changes$mergeFlow$it mergeFlow =
      _Translations$changes$mergeFlow$it._(_root);
  @override
  late final _Translations$changes$constellation$it constellation =
      _Translations$changes$constellation$it._(_root);
}

// Path: common
class _Translations$common$it extends Translations$common$en {
  _Translations$common$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get listSeparator => ', ';
  @override
  String get cancel => 'Annulla';
  @override
  String get close => 'Chiudi';
  @override
  String get save => 'Salva';
  @override
  String get delete => 'Elimina';
  @override
  String get retry => 'Riprova';
  @override
  String get copy => 'Copia';
  @override
  String get copied => 'Copiato';
  @override
  String get done => 'Fatto';
  @override
  String get loading => 'Caricamento…';
  @override
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} file',
        other: '${n} file',
      );
  @override
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} commit',
        other: '${n} commit',
      );
  @override
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} branch',
        other: '${n} branch',
      );
  @override
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} commit locale',
        other: '${n} commit locali',
      );
  @override
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} commit remoto',
        other: '${n} commit remoti',
      );
  @override
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} file in conflitto',
        other: '${n} file in conflitto',
      );
  @override
  late final _Translations$common$time$it time = _Translations$common$time$it._(
    _root,
  );
  @override
  late final _Translations$common$size$it size = _Translations$common$size$it._(
    _root,
  );
}

// Path: diff
class _Translations$diff$it extends Translations$diff$en {
  _Translations$diff$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$diff$status$it status =
      _Translations$diff$status$it._(_root);
  @override
  late final _Translations$diff$toolbar$it toolbar =
      _Translations$diff$toolbar$it._(_root);
  @override
  late final _Translations$diff$hunkDropdown$it hunkDropdown =
      _Translations$diff$hunkDropdown$it._(_root);
  @override
  String stagingFailed({required Object error}) =>
      'Stage parziale non riuscito: ${error}';
  @override
  late final _Translations$diff$trail$it trail = _Translations$diff$trail$it._(
    _root,
  );
  @override
  late final _Translations$diff$pinned$it pinned =
      _Translations$diff$pinned$it._(_root);
  @override
  late final _Translations$diff$hunkHint$it hunkHint =
      _Translations$diff$hunkHint$it._(_root);
  @override
  late final _Translations$diff$binary$it binary =
      _Translations$diff$binary$it._(_root);
  @override
  late final _Translations$diff$media$it media = _Translations$diff$media$it._(
    _root,
  );
}

// Path: filament
class _Translations$filament$it extends Translations$filament$en {
  _Translations$filament$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get noRepositoryOpen => 'Nessun repository aperto.';
  @override
  String scanningProgress({required Object scanned, required Object total}) =>
      'scansione ${scanned} / ${total} file…';
  @override
  String findingsAcrossFiles({required Object count, required Object files}) =>
      '${count} riscontri in ${files} file';
  @override
  String copiedFindings({required Object count}) =>
      '${count} riscontri copiati';
  @override
  String get copy => 'COPIA';
  @override
  String get noFindings => 'Nessun riscontro nel flusso di esecuzione.';
  @override
  late final _Translations$filament$severity$it severity =
      _Translations$filament$severity$it._(_root);
  @override
  late final _Translations$filament$kind$it kind =
      _Translations$filament$kind$it._(_root);
  @override
  String lineLabel({required Object line}) => 'R${line}';
  @override
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class _Translations$history$it extends Translations$history$en {
  _Translations$history$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$it commitLede =
      _Translations$history$commitLede$it._(_root);
  @override
  late final _Translations$history$seismograph$it seismograph =
      _Translations$history$seismograph$it._(_root);
  @override
  late final _Translations$history$worldline$it worldline =
      _Translations$history$worldline$it._(_root);
  @override
  late final _Translations$history$contextMenu$it contextMenu =
      _Translations$history$contextMenu$it._(_root);
  @override
  late final _Translations$history$cherryPick$it cherryPick =
      _Translations$history$cherryPick$it._(_root);
  @override
  late final _Translations$history$revert$it revert =
      _Translations$history$revert$it._(_root);
  @override
  late final _Translations$history$reflog$it reflog =
      _Translations$history$reflog$it._(_root);
  @override
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'Quel commit è più profondo del ${n} commit caricato.',
        other: 'Quel commit è più profondo dei ${n} commit caricati.',
      );
  @override
  String deleteTagFailed({required Object error}) =>
      'Eliminazione del tag non riuscita: ${error}';
  @override
  String get loadingTitle => 'Caricamento cronologia';
  @override
  String get loadingMessage => 'Lettura dei commit recenti.';
  @override
  String get unavailableTitle => 'Cronologia non disponibile';
  @override
  String get toggleWorldline => 'Attiva/disattiva worldline';
  @override
  String get pageTitle => 'Cronologia';
  @override
  String get viewingLast => 'Ultimi';
  @override
  String get commitsUnit => 'commit';
  @override
  String get noCommitSelectedTitle => 'Nessun commit selezionato';
  @override
  String get noCommitSelectedMessage =>
      'Seleziona un commit per ispezionarne le modifiche.';
  @override
  String get loadingCommitTitle => 'Caricamento commit';
  @override
  String get loadingCommitMessage => 'Lettura dei dettagli del commit.';
  @override
  String get commitUnavailableTitle => 'Commit non disponibile';
  @override
  String get couldNotLoadCommit => 'Impossibile caricare il commit.';
  @override
  String get reflogDividerLabel => 'reflog';
  @override
  String get loadReflog => 'Carica reflog';
  @override
  String get createTag => 'Crea tag';
  @override
  String get newTagName => 'Nome del nuovo tag';
  @override
  String newTagNameError({required Object error}) =>
      'Nome del nuovo tag — ${error}';
  @override
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} file · tutte le modifiche',
        other: '${n} file · tutte le modifiche',
      );
  @override
  String get allChangesLabel => 'tutte le modifiche';
  @override
  late final _Translations$history$rebase$it rebase =
      _Translations$history$rebase$it._(_root);
  @override
  late final _Translations$history$inFlight$it inFlight =
      _Translations$history$inFlight$it._(_root);
}

// Path: historySurgery
class _Translations$historySurgery$it extends Translations$historySurgery$en {
  _Translations$historySurgery$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$historySurgery$chrome$it chrome =
      _Translations$historySurgery$chrome$it._(_root);
  @override
  late final _Translations$historySurgery$select$it select =
      _Translations$historySurgery$select$it._(_root);
  @override
  late final _Translations$historySurgery$understand$it understand =
      _Translations$historySurgery$understand$it._(_root);
  @override
  late final _Translations$historySurgery$confirm$it confirm =
      _Translations$historySurgery$confirm$it._(_root);
  @override
  late final _Translations$historySurgery$execute$it execute =
      _Translations$historySurgery$execute$it._(_root);
  @override
  late final _Translations$historySurgery$verify$it verify =
      _Translations$historySurgery$verify$it._(_root);
  @override
  late final _Translations$historySurgery$forcePush$it forcePush =
      _Translations$historySurgery$forcePush$it._(_root);
}

// Path: onboarding
class _Translations$onboarding$it extends Translations$onboarding$en {
  _Translations$onboarding$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$nav$it nav =
      _Translations$onboarding$nav$it._(_root);
  @override
  late final _Translations$onboarding$naming$it naming =
      _Translations$onboarding$naming$it._(_root);
  @override
  late final _Translations$onboarding$theme$it theme =
      _Translations$onboarding$theme$it._(_root);
  @override
  late final _Translations$onboarding$repo$it repo =
      _Translations$onboarding$repo$it._(_root);
  @override
  late final _Translations$onboarding$preview$it preview =
      _Translations$onboarding$preview$it._(_root);
}

// Path: orrery
class _Translations$orrery$it extends Translations$orrery$en {
  _Translations$orrery$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$orrery$header$it header =
      _Translations$orrery$header$it._(_root);
  @override
  late final _Translations$orrery$status$it status =
      _Translations$orrery$status$it._(_root);
  @override
  late final _Translations$orrery$legend$it legend =
      _Translations$orrery$legend$it._(_root);
  @override
  late final _Translations$orrery$node$it node = _Translations$orrery$node$it._(
    _root,
  );
  @override
  late final _Translations$orrery$milestone$it milestone =
      _Translations$orrery$milestone$it._(_root);
  @override
  late final _Translations$orrery$structure$it structure =
      _Translations$orrery$structure$it._(_root);
  @override
  late final _Translations$orrery$rail$it rail = _Translations$orrery$rail$it._(
    _root,
  );
  @override
  late final _Translations$orrery$selection$it selection =
      _Translations$orrery$selection$it._(_root);
  @override
  late final _Translations$orrery$findingKind$it findingKind =
      _Translations$orrery$findingKind$it._(_root);
  @override
  late final _Translations$orrery$findings$it findings =
      _Translations$orrery$findings$it._(_root);
  @override
  late final _Translations$orrery$anchor$it anchor =
      _Translations$orrery$anchor$it._(_root);
  @override
  late final _Translations$orrery$compare$it compare =
      _Translations$orrery$compare$it._(_root);
}

// Path: palette
class _Translations$palette$it extends Translations$palette$en {
  _Translations$palette$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get active => 'attivo';
  @override
  late final _Translations$palette$prefixes$it prefixes =
      _Translations$palette$prefixes$it._(_root);
  @override
  late final _Translations$palette$chips$it chips =
      _Translations$palette$chips$it._(_root);
  @override
  late final _Translations$palette$predictive$it predictive =
      _Translations$palette$predictive$it._(_root);
  @override
  late final _Translations$palette$topTouched$it topTouched =
      _Translations$palette$topTouched$it._(_root);
  @override
  late final _Translations$palette$coherence$it coherence =
      _Translations$palette$coherence$it._(_root);
  @override
  late final _Translations$palette$keystone$it keystone =
      _Translations$palette$keystone$it._(_root);
  @override
  late final _Translations$palette$repoSub$it repoSub =
      _Translations$palette$repoSub$it._(_root);
  @override
  late final _Translations$palette$desks$it desks =
      _Translations$palette$desks$it._(_root);
  @override
  late final _Translations$palette$actions$it actions =
      _Translations$palette$actions$it._(_root);
  @override
  late final _Translations$palette$tools$it tools =
      _Translations$palette$tools$it._(_root);
  @override
  late final _Translations$palette$gitCommands$it gitCommands =
      _Translations$palette$gitCommands$it._(_root);
  @override
  late final _Translations$palette$pr$it pr = _Translations$palette$pr$it._(
    _root,
  );
  @override
  late final _Translations$palette$ai$it ai = _Translations$palette$ai$it._(
    _root,
  );
  @override
  late final _Translations$palette$undo$it undo =
      _Translations$palette$undo$it._(_root);
  @override
  late final _Translations$palette$navigation$it navigation =
      _Translations$palette$navigation$it._(_root);
  @override
  late final _Translations$palette$settings$it settings =
      _Translations$palette$settings$it._(_root);
  @override
  late final _Translations$palette$info$it info =
      _Translations$palette$info$it._(_root);
  @override
  late final _Translations$palette$debug$it debug =
      _Translations$palette$debug$it._(_root);
  @override
  late final _Translations$palette$dev$it dev = _Translations$palette$dev$it._(
    _root,
  );
  @override
  late final _Translations$palette$historySurgery$it historySurgery =
      _Translations$palette$historySurgery$it._(_root);
  @override
  late final _Translations$palette$orrery$it orrery =
      _Translations$palette$orrery$it._(_root);
  @override
  late final _Translations$palette$command$it command =
      _Translations$palette$command$it._(_root);
  @override
  late final _Translations$palette$search$it search =
      _Translations$palette$search$it._(_root);
  @override
  late final _Translations$palette$wick$it wick =
      _Translations$palette$wick$it._(_root);
  @override
  late final _Translations$palette$gitCache$it gitCache =
      _Translations$palette$gitCache$it._(_root);
}

// Path: releaseNotes
class _Translations$releaseNotes$it extends Translations$releaseNotes$en {
  _Translations$releaseNotes$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get versionFallback => 'dev';
  @override
  late final _Translations$releaseNotes$about$it about =
      _Translations$releaseNotes$about$it._(_root);
  @override
  late final _Translations$releaseNotes$legal$it legal =
      _Translations$releaseNotes$legal$it._(_root);
}

// Path: repoSummary
class _Translations$repoSummary$it extends Translations$repoSummary$en {
  _Translations$repoSummary$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$repoSummary$backbone$it backbone =
      _Translations$repoSummary$backbone$it._(_root);
  @override
  late final _Translations$repoSummary$glance$it glance =
      _Translations$repoSummary$glance$it._(_root);
  @override
  late final _Translations$repoSummary$heading$it heading =
      _Translations$repoSummary$heading$it._(_root);
  @override
  String get historyStarvedCaveat =>
      'Ordinamento limitato: il grafo di coupling non aveva archi (clone recente o troppo pochi commit). L\'ordine dei file riflette la dimensione, non la centralità strutturale.';
  @override
  late final _Translations$repoSummary$pitch$it pitch =
      _Translations$repoSummary$pitch$it._(_root);
  @override
  late final _Translations$repoSummary$region$it region =
      _Translations$repoSummary$region$it._(_root);
  @override
  late final _Translations$repoSummary$shape$it shape =
      _Translations$repoSummary$shape$it._(_root);
}

// Path: review
class _Translations$review$it extends Translations$review$en {
  _Translations$review$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get unresolved => 'non risolto';
  @override
  String get done => 'fatto';
  @override
  String get ack => 'annotato';
  @override
  String get reply => 'rispondi';
  @override
  String get pleaseFix => 'da correggere';
  @override
  String get draft => 'bozza';
  @override
  String get engine => 'motore';
  @override
  String get moved => 'spostato';
  @override
  String get yourTurn => 'tocca a te';
  @override
  String get drafts => 'bozze';
  @override
  String get publish => 'pubblica';
  @override
  String get discard => 'scarta';
  @override
  String get saveDraft => 'salva bozza';
  @override
  String get cancel => 'annulla';
  @override
  String get verdictApprove => 'approva';
  @override
  String get verdictRequestChanges => 'richiedi modifiche';
  @override
  String get verdictComment => 'commenta';
  @override
  String get caughtUp => 'in pari';
  @override
  String get sinceLastLook => 'dall\'ultima occhiata';
  @override
  String get fullDiff => 'diff completo';
  @override
  String get commentHint => 'scrivi un commento';
  @override
  String outdatedLastSeen({required Object round}) =>
      'obsoleto · visto l\'ultima volta R${round}';
  @override
  String resolvedByFmt({required Object verb, required Object who}) =>
      '${verb} · ${who}';
  @override
  String waitingOnFmt({required Object who}) => 'in attesa di ${who}';
  @override
  String roundChip({required Object round}) => 'R${round}';
  @override
  String filesSinceLastLook({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '1 file dall\'ultima occhiata',
        other: '${n} file dall\'ultima occhiata',
      );
  @override
  String unresolvedCountFmt({required Object n}) => '${n} non risolti';
  @override
  String draftCountFmt({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '1 bozza',
        other: '${n} bozze',
      );
  @override
  String startReviewFailed({required Object error}) =>
      'Impossibile avviare la revisione: ${error}';
  @override
  String get anchorUnavailable =>
      'Quella riga non può essere ancorata — il file è troppo grande o non disponibile.';
  @override
  String reviewActionFailed({required Object error}) =>
      'Azione di revisione non riuscita: ${error}';
  @override
  String get lensTooLarge =>
      'Quel confronto è troppo grande per essere mostrato qui — si resta sul diff completo.';
  @override
  String get lensEmpty => 'Non è cambiato nulla tra questi snapshot.';
  @override
  String get reopen => 'riapri';
  @override
  String get notBlocking => 'non aspettatemi';
  @override
  String get markReviewed => 'letto';
  @override
  String newComments({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '1 nuovo commento',
        other: '${n} nuovi commenti',
      );
  @override
  String get handTo => 'passa a';
  @override
  String get heading => 'REVISIONE';
  @override
  String get identityNeeded => 'Imposta un\'identità git per revisionare';
  @override
  String get fileUnreadable =>
      'Questo file non può essere letto qui — troppo grande o assente in questo round.';
  @override
  String get timeNow => 'ora';
  @override
  String timeMinutesFmt({required Object n}) => '${n} min';
  @override
  String timeHoursFmt({required Object n}) => '${n} h';
  @override
  String timeDaysFmt({required Object n}) => '${n} g';
  @override
  String get standingApproved => 'approvato';
  @override
  String get standingChangesRequested => 'modifiche richieste';
  @override
  String get commentOnChange => 'Commenta questa modifica';
  @override
  String get commentOnFile => 'Commenta questo file';
  @override
  String get imageNotLoaded => 'immagine non caricata';
  @override
  String get nothingBlocking => 'nulla in sospeso';
}

// Path: settings
class _Translations$settings$it extends Translations$settings$en {
  _Translations$settings$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$language$it language =
      _Translations$settings$language$it._(_root);
  @override
  late final _Translations$settings$sectionLabels$it sectionLabels =
      _Translations$settings$sectionLabels$it._(_root);
  @override
  late final _Translations$settings$errors$it errors =
      _Translations$settings$errors$it._(_root);
  @override
  late final _Translations$settings$promptStatus$it promptStatus =
      _Translations$settings$promptStatus$it._(_root);
  @override
  late final _Translations$settings$clearData$it clearData =
      _Translations$settings$clearData$it._(_root);
  @override
  List<String> get guardrailStageLabels => [
    'Lasco',
    'Bilanciato',
    'Rigoroso',
    'Paranoico',
  ];
  @override
  late final _Translations$settings$guardrailMacro$it guardrailMacro =
      _Translations$settings$guardrailMacro$it._(_root);
  @override
  late final _Translations$settings$guardrails$it guardrails =
      _Translations$settings$guardrails$it._(_root);
  @override
  late final _Translations$settings$appearance$it appearance =
      _Translations$settings$appearance$it._(_root);
  @override
  late final _Translations$settings$retention$it retention =
      _Translations$settings$retention$it._(_root);
  @override
  late final _Translations$settings$navigation$it navigation =
      _Translations$settings$navigation$it._(_root);
  @override
  late final _Translations$settings$behaviour$it behaviour =
      _Translations$settings$behaviour$it._(_root);
  @override
  late final _Translations$settings$retentionClear$it retentionClear =
      _Translations$settings$retentionClear$it._(_root);
  @override
  late final _Translations$settings$channels$it channels =
      _Translations$settings$channels$it._(_root);
  @override
  late final _Translations$settings$pollResult$it pollResult =
      _Translations$settings$pollResult$it._(_root);
  @override
  late final _Translations$settings$keybindingProfile$it keybindingProfile =
      _Translations$settings$keybindingProfile$it._(_root);
  @override
  late final _Translations$settings$apiKeys$it apiKeys =
      _Translations$settings$apiKeys$it._(_root);
  @override
  late final _Translations$settings$shortcuts$it shortcuts =
      _Translations$settings$shortcuts$it._(_root);
  @override
  late final _Translations$settings$toggles$it toggles =
      _Translations$settings$toggles$it._(_root);
  @override
  late final _Translations$settings$diffDiffability$it diffDiffability =
      _Translations$settings$diffDiffability$it._(_root);
  @override
  late final _Translations$settings$modelSlots$it modelSlots =
      _Translations$settings$modelSlots$it._(_root);
  @override
  late final _Translations$settings$modelPicker$it modelPicker =
      _Translations$settings$modelPicker$it._(_root);
  @override
  late final _Translations$settings$aiFeatures$it aiFeatures =
      _Translations$settings$aiFeatures$it._(_root);
  @override
  late final _Translations$settings$commitEditor$it commitEditor =
      _Translations$settings$commitEditor$it._(_root);
  @override
  late final _Translations$settings$review$it review =
      _Translations$settings$review$it._(_root);
  @override
  late final _Translations$settings$museHint$it museHint =
      _Translations$settings$museHint$it._(_root);
  @override
  late final _Translations$settings$museEditor$it museEditor =
      _Translations$settings$museEditor$it._(_root);
  @override
  late final _Translations$settings$museStage$it museStage =
      _Translations$settings$museStage$it._(_root);
  @override
  late final _Translations$settings$lensAxis$it lensAxis =
      _Translations$settings$lensAxis$it._(_root);
  @override
  late final _Translations$settings$logosLens$it logosLens =
      _Translations$settings$logosLens$it._(_root);
  @override
  late final _Translations$settings$sortGuide$it sortGuide =
      _Translations$settings$sortGuide$it._(_root);
  @override
  late final _Translations$settings$piggyback$it piggyback =
      _Translations$settings$piggyback$it._(_root);
  @override
  late final _Translations$settings$diffStage$it diffStage =
      _Translations$settings$diffStage$it._(_root);
  @override
  late final _Translations$settings$undoScope$it undoScope =
      _Translations$settings$undoScope$it._(_root);
  @override
  late final _Translations$settings$undoWindow$it undoWindow =
      _Translations$settings$undoWindow$it._(_root);
  @override
  late final _Translations$settings$guardrailPhrase$it guardrailPhrase =
      _Translations$settings$guardrailPhrase$it._(_root);
  @override
  late final _Translations$settings$reviewGuideHint$it reviewGuideHint =
      _Translations$settings$reviewGuideHint$it._(_root);
  @override
  late final _Translations$settings$commitFormat$it commitFormat =
      _Translations$settings$commitFormat$it._(_root);
  @override
  late final _Translations$settings$commitPreview$it commitPreview =
      _Translations$settings$commitPreview$it._(_root);
  @override
  late final _Translations$settings$externalTools$it externalTools =
      _Translations$settings$externalTools$it._(_root);
  @override
  late final _Translations$settings$apiUsage$it apiUsage =
      _Translations$settings$apiUsage$it._(_root);
  @override
  late final _Translations$settings$gitea$it gitea =
      _Translations$settings$gitea$it._(_root);
  @override
  late final _Translations$settings$wick$it wick =
      _Translations$settings$wick$it._(_root);
  @override
  late final _Translations$settings$integrations$it integrations =
      _Translations$settings$integrations$it._(_root);
  @override
  late final _Translations$settings$reduceMotion$it reduceMotion =
      _Translations$settings$reduceMotion$it._(_root);
  @override
  late final _Translations$settings$resetQuit$it resetQuit =
      _Translations$settings$resetQuit$it._(_root);
  @override
  late final _Translations$settings$diagnostics$it diagnostics =
      _Translations$settings$diagnostics$it._(_root);
  @override
  late final _Translations$settings$telemetry$it telemetry =
      _Translations$settings$telemetry$it._(_root);
  @override
  late final _Translations$settings$flowEngine$it flowEngine =
      _Translations$settings$flowEngine$it._(_root);
  @override
  late final _Translations$settings$museStrands$it museStrands =
      _Translations$settings$museStrands$it._(_root);
  @override
  late final _Translations$settings$cliPiggyback$it cliPiggyback =
      _Translations$settings$cliPiggyback$it._(_root);
  @override
  late final _Translations$settings$header$it header =
      _Translations$settings$header$it._(_root);
  @override
  late final _Translations$settings$diagnosticsPanel$it diagnosticsPanel =
      _Translations$settings$diagnosticsPanel$it._(_root);
  @override
  late final _Translations$settings$release$it release =
      _Translations$settings$release$it._(_root);
  @override
  late final _Translations$settings$providerStatus$it providerStatus =
      _Translations$settings$providerStatus$it._(_root);
  @override
  late final _Translations$settings$meridiem$it meridiem =
      _Translations$settings$meridiem$it._(_root);
  @override
  late final _Translations$settings$offenders$it offenders =
      _Translations$settings$offenders$it._(_root);
}

// Path: sync
class _Translations$sync$it extends Translations$sync$en {
  _Translations$sync$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$actions$it actions =
      _Translations$sync$actions$it._(_root);
  @override
  late final _Translations$sync$panel$it panel = _Translations$sync$panel$it._(
    _root,
  );
  @override
  late final _Translations$sync$forcePush$it forcePush =
      _Translations$sync$forcePush$it._(_root);
}

// Path: xray
class _Translations$xray$it extends Translations$xray$en {
  _Translations$xray$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$board$it board = _Translations$xray$board$it._(
    _root,
  );
  @override
  late final _Translations$xray$cadence$it cadence =
      _Translations$xray$cadence$it._(_root);
  @override
  late final _Translations$xray$cards$it cards = _Translations$xray$cards$it._(
    _root,
  );
  @override
  late final _Translations$xray$cardTitle$it cardTitle =
      _Translations$xray$cardTitle$it._(_root);
  @override
  late final _Translations$xray$grain$it grain = _Translations$xray$grain$it._(
    _root,
  );
  @override
  late final _Translations$xray$header$it header =
      _Translations$xray$header$it._(_root);
  @override
  late final _Translations$xray$hotspot$it hotspot =
      _Translations$xray$hotspot$it._(_root);
  @override
  late final _Translations$xray$inspector$it inspector =
      _Translations$xray$inspector$it._(_root);
  @override
  late final _Translations$xray$loadingCard$it loadingCard =
      _Translations$xray$loadingCard$it._(_root);
  @override
  late final _Translations$xray$metabolism$it metabolism =
      _Translations$xray$metabolism$it._(_root);
  @override
  late final _Translations$xray$multi$it multi = _Translations$xray$multi$it._(
    _root,
  );
  @override
  late final _Translations$xray$recency$it recency =
      _Translations$xray$recency$it._(_root);
  @override
  late final _Translations$xray$rings$it rings = _Translations$xray$rings$it._(
    _root,
  );
  @override
  late final _Translations$xray$stats$it stats = _Translations$xray$stats$it._(
    _root,
  );
  @override
  late final _Translations$xray$stratumLabel$it stratumLabel =
      _Translations$xray$stratumLabel$it._(_root);
  @override
  late final _Translations$xray$summary$it summary =
      _Translations$xray$summary$it._(_root);
  @override
  late final _Translations$xray$tabs$it tabs = _Translations$xray$tabs$it._(
    _root,
  );
  @override
  late final _Translations$xray$trajectory$it trajectory =
      _Translations$xray$trajectory$it._(_root);
  @override
  late final _Translations$xray$verdict$it verdict =
      _Translations$xray$verdict$it._(_root);
}

// Path: agentSkills.question
class _Translations$agentSkills$question$it
    extends Translations$agentSkills$question$en {
  _Translations$agentSkills$question$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get overview => 'Come si combinano le competenze';
  @override
  String get codeReview => 'Questa modifica è corretta?';
  @override
  String get muse => 'Cosa potrebbe diventare questa modifica?';
  @override
  String get bugShaker => 'Cosa non va nel codice consolidato?';
  @override
  String get repoIntel => 'A cosa è collegato questo file?';
}

// Path: app.cheatsheet
class _Translations$app$cheatsheet$it extends Translations$app$cheatsheet$en {
  _Translations$app$cheatsheet$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Tastiera';
  @override
  String get sectionNavigate => 'naviga';
  @override
  String get sectionStaging => 'staging';
  @override
  String get sectionBranchesPrs => 'branch e PR';
  @override
  String get changes => 'Modifiche';
  @override
  String get history => 'Cronologia';
  @override
  String get branches => 'Branch';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Cambia (sempre)';
  @override
  String get commandPalette => 'Palette comandi';
  @override
  String get elevatedPalette => 'Palette elevata';
  @override
  String get dismiss => 'Chiudi';
  @override
  String get refresh => 'Aggiorna';
  @override
  String get nextPrevChange => 'Modifica succ. / prec.';
  @override
  String get toggleLine => 'Attiva/disattiva riga';
  @override
  String get toggleHunk => 'Attiva/disattiva hunk';
  @override
  String get toggleFile => 'Attiva/disattiva file';
  @override
  String get pinContext => 'Fissa contesto';
  @override
  String get commit => 'Commit';
  @override
  String get acceptAiHint => 'Accetta suggerimento AI';
  @override
  String get undo => 'Annulla';
  @override
  String get navigate => 'Naviga';
  @override
  String get expand => 'Espandi';
  @override
  String get checkoutPr => 'Checkout PR';
  @override
  String get approve => 'Approva';
  @override
  String get requestChanges => 'Richiedi modifiche';
  @override
  String profileSwitchHint({required Object profile}) =>
      'Profilo ${profile} · cambia nelle Impostazioni';
}

// Path: backend.ops
class _Translations$backend$ops$it extends Translations$backend$ops$en {
  _Translations$backend$ops$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'Merge';
  @override
  String get pull => 'Pull';
  @override
  String get apply => 'Applica';
  @override
  String get switchOp => 'Cambia';
  @override
  String get sync => 'Sync';
}

// Path: backend.mergeOutcome
class _Translations$backend$mergeOutcome$it
    extends Translations$backend$mergeOutcome$en {
  _Translations$backend$mergeOutcome$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String cancelled({required Object op}) => '${op} annullato.';
  @override
  String complete({required Object op}) => '${op} completato.';
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} conflitto rimasto — risolvilo nella pagina Modifiche.',
        other: '${n} conflitti rimasti — risolvili nella pagina Modifiche.',
      );
  @override
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'Risolto ${n} conflitto.',
        other: 'Risolti ${n} conflitti.',
      );
  @override
  String uncommittedEdits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} file ha modifiche non committate — committale prima.',
        other: '${n} file hanno modifiche non committate — committale prima.',
      );
}

// Path: changes.usage
class _Translations$changes$usage$it extends Translations$changes$usage$en {
  _Translations$changes$usage$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String caption({required Object input, required Object output}) =>
      '${input} in · ${output} out';
  @override
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '${fresh} in · ${cached} in cache · ${out} out';
  @override
  String get inWord => 'in';
  @override
  String get cachedWord => 'cache';
  @override
  String get outWord => 'out';
  @override
  String tipIn({required Object value}) => '${value}  in';
  @override
  String tipCacheRead({required Object value}) => '${value}  lettura cache';
  @override
  String tipCacheWrite({required Object value}) => '${value}  scrittura cache';
  @override
  String tipOut({required Object value}) => '${value}  out';
  @override
  String tipReasoning({required Object value}) => '${value}  ragionamento';
  @override
  String tipWallClock({required Object value}) => '${value}s  tempo reale';
}

// Path: changes.tabs
class _Translations$changes$tabs$it extends Translations$changes$tabs$en {
  _Translations$changes$tabs$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get defaultLabel => 'Modifiche';
  @override
  String get empty => 'Vuoto';
}

// Path: changes.tabStrip
class _Translations$changes$tabStrip$it
    extends Translations$changes$tabStrip$en {
  _Translations$changes$tabStrip$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get newDiffTab => 'Nuova scheda diff';
}

// Path: changes.select
class _Translations$changes$select$it extends Translations$changes$select$en {
  _Translations$changes$select$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get selectAll => 'Seleziona tutto';
  @override
  String get deselectAll => 'Deseleziona tutto';
}

// Path: changes.constellationToggle
class _Translations$changes$constellationToggle$it
    extends Translations$changes$constellationToggle$en {
  _Translations$changes$constellationToggle$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get backToList => 'torna alla lista';
  @override
  String get atlas => 'atlante, vedi i candidati al commit';
}

// Path: changes.nudgeChip
class _Translations$changes$nudgeChip$it
    extends Translations$changes$nudgeChip$en {
  _Translations$changes$nudgeChip$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\nsi accoppia con ${anchor} · ${pct}%${receipts}';
}

// Path: changes.minimap
class _Translations$changes$minimap$it extends Translations$changes$minimap$en {
  _Translations$changes$minimap$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get roleNew => 'nuovo';
  @override
  String get roleBridge => 'ponte';
  @override
  String get roleHub => 'hub';
  @override
  String get roleLeaf => 'foglia';
  @override
  String get roleConnected => 'connesso';
  @override
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';
  @override
  String changesWith({required Object name}) => 'cambia con ${name}';
  @override
  String get newFile => 'nuovo file';
  @override
  String nearOtherChanges({required Object count, required Object dir}) =>
      'vicino ad altre ${count} modifiche in ${dir}';
  @override
  String usuallyChangesWithFile({required Object name}) =>
      '${name} di solito cambia con questo file';
}

// Path: changes.tagInput
class _Translations$changes$tagInput$it
    extends Translations$changes$tagInput$en {
  _Translations$changes$tagInput$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get hint => 'tag...';
}

// Path: changes.composer
class _Translations$changes$composer$it
    extends Translations$changes$composer$en {
  _Translations$changes$composer$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get hintPlaceholder => 'messaggio di commit...';
  @override
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class _Translations$changes$commit$it extends Translations$changes$commit$en {
  _Translations$changes$commit$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get primaryCommitChanges => 'Committa le modifiche';
  @override
  String get primaryCommitChangesDetail =>
      'HEAD scollegato: committa in locale senza sync.';
  @override
  String get primaryPublish => 'Committa e pubblica';
  @override
  String get primaryPublishDetail =>
      'Crea il commit e pubblica questo branch in un solo passo.';
  @override
  String get primarySync => 'Committa e sync';
  @override
  String get primarySyncDetail =>
      'Crea il commit, poi riconcilia e spedisci il branch.';
  @override
  String get primaryPush => 'Committa e push';
  @override
  String get primaryPushDetail => 'Crea il commit e fanne subito il push.';
  @override
  String get amendLast => 'Amend dell\'ultimo commit';
  @override
  String amendAnd({required Object action}) => 'Amend e ${action}';
  @override
  String get chooseFile => 'Scegli almeno un file per il prossimo commit.';
  @override
  String get writeMessage => 'Scrivi prima un messaggio di commit.';
  @override
  String get committing => 'Commit in corso';
  @override
  String get committingSync => 'Commit e sync in corso';
  @override
  String get committed => 'Committato.';
  @override
  String get undoFailed => 'Annullamento non riuscito.';
  @override
  String get working => 'In lavorazione…';
  @override
  String get commitOnly => 'Solo commit';
  @override
  String get noRuntimeModels =>
      'Nessun modello rilevato a runtime è disponibile per i messaggi di commit.';
  @override
  String restoreFailedRetry({required Object err}) =>
      '${err}\nImpossibile ripristinare lo staging dei file esclusi; controlla l\'indice prima di riprovare.';
  @override
  String committedSummary({required Object summary, required Object hash}) =>
      'Committato ${summary} (${hash}).';
  @override
  String get restoreFailedSync =>
      'Impossibile rimettere in stage le selezioni dei file esclusi; sync saltato. Controlla l\'indice prima del sync.';
  @override
  String get noModelLabel => 'Nessun modello';
  @override
  String get chooseBeforeGenerate => 'Scegli almeno un file prima di generare.';
  @override
  String get aiUnavailable =>
      'L\'AI per i messaggi di commit non è ancora disponibile.';
  @override
  String get generateFailed => 'Generazione non riuscita.';
  @override
  String get stageFailed => 'Impossibile mettere in stage i file.';
  @override
  String get commitFailed => 'Commit non riuscito.';
  @override
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => 'Committato ${summary} (${hash}) ed eseguito ${operation}.';
  @override
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
    n,
    one: 'Committato ${summary} (${hash}); risolto ${n} conflitto.',
    other: 'Committato ${summary} (${hash}); risolti ${n} conflitti.',
  );
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} conflitto ancora da risolvere.',
        other: '${n} conflitti ancora da risolvere.',
      );
  @override
  String syncBlocked({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
    n,
    one:
        'Commit riuscito, ma il sync è stato bloccato da ${n} file non committato.',
    other:
        'Commit riuscito, ma il sync è stato bloccato da ${n} file non committati.',
  );
  @override
  String syncStalled({required Object message}) =>
      'Commit riuscito, ma il sync si è arenato: ${message}';
  @override
  String syncFailed({required Object message}) =>
      'Commit riuscito, ma il sync è fallito: ${message}';
}

// Path: changes.rebase
class _Translations$changes$rebase$it extends Translations$changes$rebase$en {
  _Translations$changes$rebase$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get continueFailed => 'Impossibile continuare il rebase.';
}

// Path: changes.editor
class _Translations$changes$editor$it extends Translations$changes$editor$en {
  _Translations$changes$editor$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get closeBarrier => 'Chiudi l\'editor';
}

// Path: changes.editorTitles
class _Translations$changes$editorTitles$it
    extends Translations$changes$editorTitles$en {
  _Translations$changes$editorTitles$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  List<String> get any => [
    'caro git log',
    'per-git-onami perché ho peccato…',
    'dai un nome a questo momento',
    'vai di chiacchiere',
    'parla!',
    'tua madre era una reference penzolante e tuo padre puzzava di punto e virgola',
  ];
  @override
  List<String> get short => [
    'oh?',
    'ehilà:)',
    'comunque:',
    'due parole',
    'la versione educata',
    'lascia un biglietto',
    'stavi dicendo..?',
    'eh già, sputa il rospo',
  ];
  @override
  List<String> get mid => [
    'per la cronaca',
    'dillo al te del futuro',
    'ma prima?',
    'com\'è andata',
    'con parole tue',
    'hai fatto COSA?',
    'preso nota',
    'hai la mia attenzione',
  ];
  @override
  List<String> get long => [
    'i tuoi sogni, prego',
    'di\' qualcosa di carino',
    '... e poi ho detto:',
    'i posteri attendono',
    'scrivere di più fa sparire i tuoi bug',
    'oh wow',
    'i sacri testi',
  ];
}

// Path: changes.askHint
class _Translations$changes$askHint$it extends Translations$changes$askHint$en {
  _Translations$changes$askHint$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String round({required Object n}) =>
      'round ${n} — affina o aggiungi contesto.';
  @override
  String get symptom => 'descrivi il sintomo.';
  @override
  String get broken => 'cosa non funziona?';
  @override
  String get bug => 'descrivi il bug.';
  @override
  String get error => 'incolla l\'errore.';
}

// Path: changes.fileMenu
class _Translations$changes$fileMenu$it
    extends Translations$changes$fileMenu$en {
  _Translations$changes$fileMenu$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get ripple => 'Onda';
  @override
  String get includeCoChanges => 'Includi le co-change';
  @override
  String deleteFile({required Object name}) => 'Elimina ${name}…';
  @override
  String discardChangesTo({required Object name}) =>
      'Scarta le modifiche a ${name}…';
  @override
  String get ignore => 'Ignora';
  @override
  String get diffTabFromSelection => 'Scheda diff dalla selezione';
  @override
  String addSelectedToTab({required Object name}) =>
      'Aggiungi la selezione a ${name}';
  @override
  String diffTabFromFile({required Object name}) => 'Scheda diff da ${name}';
  @override
  String addFileToTab({required Object file, required Object tab}) =>
      'Aggiungi ${file} a ${tab}';
  @override
  String get copyFilePath => 'Copia percorso del file';
  @override
  String get showInExplorer => 'Mostra in Explorer';
}

// Path: changes.multiFileMenu
class _Translations$changes$multiFileMenu$it
    extends Translations$changes$multiFileMenu$en {
  _Translations$changes$multiFileMenu$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get cohesionTight => 'strettamente accoppiati';
  @override
  String get cohesionLoose => 'vagamente correlati';
  @override
  String get cohesionScattered => 'strutturalmente sparsi';
  @override
  String get clusterOne => 'tutti in un cluster';
  @override
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      'si estende su ${count} cluster (${parts} file)';
  @override
  String clusterSpans({required Object count}) =>
      'si estende su ${count} cluster';
  @override
  String roleLine({required Object count, required Object cohesion}) =>
      '${count} file · ${cohesion}';
  @override
  String usuallyChangesWithGroup({required Object file}) =>
      '${file} di solito cambia con questo gruppo';
  @override
  String get splitToNewTab => 'Dividi in una nuova scheda';
  @override
  String copyPaths({required Object count}) => 'Copia ${count} percorsi';
}

// Path: changes.ignoreMenu
class _Translations$changes$ignoreMenu$it
    extends Translations$changes$ignoreMenu$en {
  _Translations$changes$ignoreMenu$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String extension({required Object ext}) => 'estensione .${ext}';
  @override
  String allSelected({required Object count}) => 'Tutti i ${count} selezionati';
  @override
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'Si accoppia con ${n} file incluso',
        other: 'Si accoppia con ${n} file inclusi',
      );
  @override
  String get updateFailed => 'Impossibile aggiornare .gitignore.';
}

// Path: changes.discard
class _Translations$changes$discard$it extends Translations$changes$discard$en {
  _Translations$changes$discard$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String deleteTitle({required Object name}) => 'Eliminare ${name}?';
  @override
  String discardTitle({required Object name}) =>
      'Scartare le modifiche a ${name}?';
  @override
  String deleteBody({required Object path}) =>
      '${path} verrà rimosso dal disco. Non è annullabile dall\'interno dell\'app.';
  @override
  String discardBody({required Object path}) =>
      'Tutte le modifiche a ${path} verranno riportate allo stato in HEAD. Non è annullabile.';
  @override
  String get discard => 'Scarta';
  @override
  String deletingFile({required Object name}) => 'Eliminazione di ${name}';
  @override
  String discardingFile({required Object name}) => 'Scarto di ${name}';
  @override
  String get discardFailed => 'Impossibile scartare le modifiche.';
  @override
  String discardManyTitle({required Object count}) =>
      'Scartare le modifiche a ${count} file?';
  @override
  String get discardManyBody =>
      'I file tracciati verranno riportati allo stato in HEAD; i file non tracciati verranno rimossi dal disco. Non è annullabile.';
  @override
  String discardManyConfirm({required Object count}) => 'Scarta ${count}';
  @override
  String discardingManyFiles({required Object count}) =>
      'Scarto di ${count} file';
  @override
  String failedOpenExplorer({required Object error}) =>
      'Impossibile aprire l\'esplora file: ${error}';
  @override
  String get someFailed => 'Alcuni scarti sono falliti.';
}

// Path: changes.snack
class _Translations$changes$snack$it extends Translations$changes$snack$en {
  _Translations$changes$snack$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get sameWorktree => 'Stesso worktree — niente da scaricare.';
  @override
  String diffFailed({required Object error}) => 'Diff non riuscito: ${error}';
  @override
  String get deskEmpty =>
      'Il Desk non ha nulla in più rispetto a te — scarico vuoto.';
  @override
  String sourceDesk({required Object label}) => 'Desk ${label}';
  @override
  String shelfReadFailed({required Object error}) =>
      'Lettura della mensola non riuscita: ${error}';
  @override
  String get shelfEmpty => 'Mensola vuota — niente da scaricare.';
  @override
  String sourceShelf({required Object label}) => 'mensola ${label}';
  @override
  String noModelConfigured({required Object label}) =>
      'Nessun modello configurato per "${label}".';
  @override
  String fetchFailed({required Object error}) => 'Fetch non riuscito: ${error}';
}

// Path: changes.trace
class _Translations$changes$trace$it extends Translations$changes$trace$en {
  _Translations$changes$trace$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Traccia di verifica';
  @override
  String get draftReview => 'Bozza di review';
}

// Path: changes.cleanTree
class _Translations$changes$cleanTree$it
    extends Translations$changes$cleanTree$en {
  _Translations$changes$cleanTree$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Albero di lavoro pulito';
  @override
  String get subtitle => 'Nessuna modifica in stage o fuori stage rilevata.';
  @override
  String get noUpstream => '  ·  nessun upstream';
  @override
  String get ahead => ' avanti';
  @override
  String get behind => ' indietro';
  @override
  String get refreshing => 'Aggiornamento...';
  @override
  String get refresh => 'Aggiorna';
  @override
  String get check => 'controlla';
  @override
  String get checkTooltip => 'Fetch e aggiornamento locale.';
  @override
  String get sync => '& sync';
}

// Path: changes.guardrail
class _Translations$changes$guardrail$it
    extends Translations$changes$guardrail$en {
  _Translations$changes$guardrail$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'Lasco';
  @override
  String get balanced => 'Bilanciato';
  @override
  String get strict => 'Rigoroso';
  @override
  String get paranoid => 'Paranoico';
}

// Path: changes.dropHint
class _Translations$changes$dropHint$it
    extends Translations$changes$dropHint$en {
  _Translations$changes$dropHint$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get fromShelf =>
      'rilascia per portare qui le modifiche da questa mensola';
  @override
  String get fromDesk => 'rilascia per portare qui le modifiche da questo Desk';
}

// Path: changes.diffEmpty
class _Translations$changes$diffEmpty$it
    extends Translations$changes$diffEmpty$en {
  _Translations$changes$diffEmpty$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Nessun file selezionato';
  @override
  String get message =>
      'Seleziona un file modificato per ispezionarne il diff.';
}

// Path: changes.shelvePill
class _Translations$changes$shelvePill$it
    extends Translations$changes$shelvePill$en {
  _Translations$changes$shelvePill$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String shelveN({required Object count}) => '↓ metti in mensola ${count}';
  @override
  String get shelve => '↓ metti in mensola';
  @override
  String shelvedCount({required Object count, required Object glyph}) =>
      '${count} in mensola ${glyph}';
}

// Path: changes.stashAction
class _Translations$changes$stashAction$it
    extends Translations$changes$stashAction$en {
  _Translations$changes$stashAction$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get pickUp => 'riprendi';
  @override
  String get peek => 'sbircia';
  @override
  String get toss => 'butta';
}

// Path: changes.stashContents
class _Translations$changes$stashContents$it
    extends Translations$changes$stashContents$en {
  _Translations$changes$stashContents$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get reading => 'lettura mensola…';
  @override
  String get empty => 'mensola vuota';
}

// Path: changes.stashFile
class _Translations$changes$stashFile$it
    extends Translations$changes$stashFile$en {
  _Translations$changes$stashFile$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get binary => 'bin';
}

// Path: changes.fileRow
class _Translations$changes$fileRow$it extends Translations$changes$fileRow$en {
  _Translations$changes$fileRow$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get stagedLinesOnly => 'committa solo le righe in stage';
  @override
  String get doubleClickToggle => 'doppio clic: commuta l\'intero gruppo';
  @override
  String get repoRoot => 'Radice del repository';
}

// Path: changes.resolveStrip
class _Translations$changes$resolveStrip$it
    extends Translations$changes$resolveStrip$en {
  _Translations$changes$resolveStrip$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'lettura di ${n} file · bozza di risoluzione…',
        other: 'lettura di ${n} file · bozza di risoluzione…',
      );
  @override
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} conflitto su ${files}',
        other: '${n} conflitti su ${files}',
      );
  @override
  String get resolve => 'Risolvi';
  @override
  String get orWith => 'OPPURE CON';
  @override
  String resolveWith({required Object label}) => 'risolvi con ${label}';
  @override
  String resolveWithModel({required Object label, required Object model}) =>
      'risolvi con ${label}  ·  ${model}';
  @override
  String get resolving => 'risoluzione…';
  @override
  String resolveWithGlyph({required Object label}) => '↵  risolvi con ${label}';
  @override
  String get orWithAnother => 'o con un altro modello';
}

// Path: changes.badge
class _Translations$changes$badge$it extends Translations$changes$badge$en {
  _Translations$changes$badge$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get stagedEdit => 'Modifica in stage';
  @override
  String get edited => 'Modificato';
  @override
  String get stagedAdd => 'Aggiunta in stage';
  @override
  String get added => 'Aggiunto';
  @override
  String get stagedDelete => 'Eliminazione in stage';
  @override
  String get deleted => 'Eliminato';
  @override
  String get stagedRename => 'Rinomina in stage';
  @override
  String get renamed => 'Rinominato';
  @override
  String get stagedCopy => 'Copia in stage';
  @override
  String get copied => 'Copiato';
  @override
  String get conflict => 'Conflitto';
  @override
  String get stagedTypeChange => 'Cambio tipo in stage';
  @override
  String get typeChanged => 'Tipo cambiato';
  @override
  String get untracked => 'Non tracciato';
}

// Path: changes.review
class _Translations$changes$review$it extends Translations$changes$review$en {
  _Translations$changes$review$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Code review';
  @override
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} file incluso',
        other: '${n} file inclusi',
      );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} hunk',
        other: '${n} hunk',
      );
  @override
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';
  @override
  String get unavailable => 'Review non disponibile';
  @override
  String get backToDiff => 'Torna al diff';
  @override
  String get verified => 'Verificato';
  @override
  String get draftOnly => 'Solo bozza';
  @override
  String get runAgain => 'Esegui di nuovo';
  @override
  String draftShownBelow({required Object error}) =>
      '${error} La bozza di review è mostrata sotto.';
  @override
  String get hideTrace => 'Nascondi la traccia';
  @override
  String get showTrace => 'Mostra la traccia';
  @override
  String get showVerificationTrace => 'Mostra la traccia di verifica';
  @override
  String get whyLanded => 'Perché questa review è atterrata qui';
  @override
  String get noFindings => 'Nessun riscontro';
  @override
  String get findings => 'Riscontri';
  @override
  String get noEvidenceIssues =>
      'Nessun problema supportato da evidenze è emerso per questo ambito di commit.';
  @override
  String get observations => 'Osservazioni';
  @override
  String get chooseBeforeReview =>
      'Scegli almeno un file prima di fare la review.';
  @override
  String get aiUnavailable => 'La review AI non è ancora disponibile.';
  @override
  String get failed => 'Review non riuscita.';
  @override
  String get noRuntimeModels =>
      'Nessun modello rilevato a runtime è disponibile per la review dei commit.';
}

// Path: changes.commitBtn
class _Translations$changes$commitBtn$it
    extends Translations$changes$commitBtn$en {
  _Translations$changes$commitBtn$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String switchTo({required Object label}) => 'Passa a: ${label}\n';
}

// Path: changes.shapeBtn
class _Translations$changes$shapeBtn$it
    extends Translations$changes$shapeBtn$en {
  _Translations$changes$shapeBtn$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String askingWith({required Object cat}) => 'domanda con ${cat}…';
  @override
  String askWith({required Object cat}) => 'chiedi con ${cat}';
  @override
  String get noModel => 'nessun modello AI configurato';
  @override
  String nextTooltip({required Object cat}) =>
      'prossima: ${cat}  ·  shift-clic per la precedente';
  @override
  String get onlyOne => 'una sola categoria AI configurata';
}

// Path: changes.dejaVu
class _Translations$changes$dejaVu$it extends Translations$changes$dejaVu$en {
  _Translations$changes$dejaVu$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required num n,
    required Object pct,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
    n,
    one:
        '${pct}% déjà vu — ${n} arco fantasma da timeline scartate tocca questo diff',
    other:
        '${pct}% déjà vu — ${n} archi fantasma da timeline scartate toccano questo diff',
  );
  @override
  String get label => 'déjà vu';
}

// Path: changes.identity
class _Translations$changes$identity$it
    extends Translations$changes$identity$en {
  _Translations$changes$identity$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'nessuna identità di commit configurata';
  @override
  String asName({required Object name}) => 'come ${name}';
  @override
  String asNameEmail({required Object name, required Object email}) =>
      'come ${name} <${email}>';
  @override
  String asNameSpace({required Object name}) => 'come ${name} ';
  @override
  String emailAngle({required Object email}) => '<${email}>';
  @override
  String get firstCommit => '\nprimo commit in questo repo';
  @override
  String get newToRepo => '\nnuovo in questo repo';
}

// Path: changes.staleScope
class _Translations$changes$staleScope$it
    extends Translations$changes$staleScope$en {
  _Translations$changes$staleScope$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get message => 'la selezione è cambiata dall\'esecuzione';
  @override
  String get rerun => 'riesegui';
}

// Path: changes.finding
class _Translations$changes$finding$it extends Translations$changes$finding$en {
  _Translations$changes$finding$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get openDiff => 'Apri il diff';
  @override
  String get recorded => 'registrato';
  @override
  String get dismiss => 'Chiudi';
}

// Path: changes.muse
class _Translations$changes$muse$it extends Translations$changes$muse$en {
  _Translations$changes$muse$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Muse';
  @override
  String get youPulledThis => 'questo l\'hai tirato tu';
  @override
  String fromIdea({required Object text}) => 'dall\'idea: "${text}"';
  @override
  String get foothold => 'appiglio — ';
  @override
  String get brainstormSpew => 'sfogo di brainstorm';
  @override
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';
  @override
  String copyN({required Object count}) => 'Copia ${count}';
  @override
  String get clear => 'Svuota';
  @override
  String get chooseBeforeMuse =>
      'Scegli almeno un file prima di invocare la muse.';
  @override
  String get aiUnavailable => 'La muse AI non è ancora disponibile.';
  @override
  String get failed => 'Muse non riuscita.';
  @override
  String get noRuntimeModels =>
      'Nessun modello rilevato a runtime è disponibile per la muse.';
  @override
  String get needsModel =>
      'La muse ha bisogno di almeno un modello configurato.';
  @override
  String get dreaming => 'la muse sta sognando...';
}

// Path: changes.debug
class _Translations$changes$debug$it extends Translations$changes$debug$en {
  _Translations$changes$debug$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Debug';
  @override
  String round({required Object n}) => '· round ${n}';
  @override
  String get clear => 'svuota';
  @override
  String get close => 'chiudi';
  @override
  String get analyzing => 'analisi del sintomo…';
  @override
  String get describeSymptom => 'descrivi un sintomo, poi premi debug.';
  @override
  String get evidenceFor => 'a favore';
  @override
  String get evidenceAgainst => 'ma';
  @override
  String get narrowDown => 'cosa aiuterebbe a restringere il campo:';
  @override
  String get failed => 'Debug non riuscito.';
  @override
  String get refinementFailed => 'Affinamento del debug non riuscito.';
}

// Path: changes.includeSummary
class _Translations$changes$includeSummary$it
    extends Translations$changes$includeSummary$en {
  _Translations$changes$includeSummary$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'Nessuno';
  @override
  String stagedSuffix({required Object count}) => ' · ${count} in stage';
  @override
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'Tutti gli ${n} file${staged}',
        other: 'Tutti gli ${n} file${staged}',
      );
  @override
  String partial({
    required Object count,
    required Object n,
    required Object staged,
  }) => '${count} di ${n}${staged}';
  @override
  String shortAll({required Object n, required Object staged}) =>
      'Tutti ${n}${staged}';
}

// Path: changes.status
class _Translations$changes$status$it extends Translations$changes$status$en {
  _Translations$changes$status$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get unavailableTitle => 'Stato del repository non disponibile';
  @override
  String get loadingTitle => 'Caricamento stato del repository';
  @override
  String get loadingMessage => 'Lettura dell\'albero di lavoro.';
}

// Path: changes.stash
class _Translations$changes$stash$it extends Translations$changes$stash$en {
  _Translations$changes$stash$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get appliedWithConflicts =>
      'Stash applicato con conflitti — risolvili nella pagina Modifiche (la voce di stash è stata mantenuta).';
  @override
  String get couldNotPop => 'Impossibile fare il pop dello stash.';
  @override
  String get listChanged =>
      'La lista degli stash è cambiata; drop saltato. Riprova.';
  @override
  String get droppingStash => 'Drop dello stash';
}

// Path: changes.tooltips
class _Translations$changes$tooltips$it
    extends Translations$changes$tooltips$en {
  _Translations$changes$tooltips$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get commitGenerating => 'generazione del messaggio di commit...';
  @override
  String get commitPreparing => 'preparazione del messaggio di commit...';
  @override
  String get commitSelectFile =>
      'seleziona almeno un file per generare un messaggio di commit.';
  @override
  String get commitConfigure =>
      'configura il messaggio di commit in Impostazioni > Dinamiche comportamentali > Messaggi di commit.';
  @override
  String get fastFallback => 'veloce';
  @override
  String commitGenerateWith({required Object label}) =>
      'genera il messaggio di commit con il modello ${label}';
  @override
  String get museConsulting => 'consulto la muse...';
  @override
  String get showMuse => 'mostra la muse';
  @override
  String get museSelectFile => 'seleziona almeno un file per la muse.';
  @override
  String get showMuseError => 'mostra l\'errore della muse';
  @override
  String get museAsk => 'chiedi una direzione alla muse';
  @override
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => 'chiedi una direzione alla muse\n${brainstorm} → ${synthesis}';
  @override
  String get qualityFallback => 'qualità';
  @override
  String get reviewing => 'review in corso...';
  @override
  String get showReview => 'mostra la review';
  @override
  String get reviewPreparing => 'preparazione della review del commit...';
  @override
  String get reviewSelectFile => 'seleziona almeno un file da rivedere.';
  @override
  String get reviewConfigure => 'configura la review AI nelle impostazioni.';
  @override
  String get viewingReview => 'visualizzazione della review';
  @override
  String reviewWith({required Object guardrail, required Object label}) =>
      'review ${guardrail} con il modello ${label}';
}

// Path: changes.mergeEditor
class _Translations$changes$mergeEditor$it
    extends Translations$changes$mergeEditor$en {
  _Translations$changes$mergeEditor$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get resolutionYours => 'tuo';
  @override
  String get resolutionTheirs => 'loro';
  @override
  String get resolutionCustom => 'personale';
  @override
  String get keepBoth => 'tieni entrambi';
  @override
  late final _Translations$changes$mergeEditor$trust$it trust =
      _Translations$changes$mergeEditor$trust$it._(_root);
  @override
  String get allResolved => 'tutti risolti';
  @override
  String get resolveEasy => 'risolvi i conflitti facili';
  @override
  String get base => 'base';
  @override
  String get cancel => 'annulla';
  @override
  String get save => 'salva';
  @override
  String get complete => 'completa';
  @override
  String get nextFile => 'file successivo';
  @override
  String get edit => 'modifica';
  @override
  String get auto => 'auto';
  @override
  String get undo => 'annulla';
  @override
  late final _Translations$changes$mergeEditor$keyHints$it keyHints =
      _Translations$changes$mergeEditor$keyHints$it._(_root);
  @override
  String get favoredTooltip =>
      'strutturalmente favorito dall\'analisi di coupling';
  @override
  String get newOnBothSides => '(nuovo su entrambi i lati)';
  @override
  String writeFailed({required Object error}) =>
      'Impossibile scrivere i file risolti: ${error}';
  @override
  String neighborsCoChanged({required Object changed, required Object total}) =>
      '${changed}/${total} vicini co-modificati';
  @override
  String integrity({required Object pct}) => 'integrità ${pct}%';
  @override
  String reviewer({required Object name}) => 'reviewer: ${name}';
}

// Path: changes.conflictResolution
class _Translations$changes$conflictResolution$it
    extends Translations$changes$conflictResolution$en {
  _Translations$changes$conflictResolution$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String noModelConfigured({required Object category}) =>
      'Nessun modello configurato per "${category}". Impostane uno in Impostazioni → AI.';
  @override
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} file sensibile saltato — risolvi a mano.',
        other: '${n} file sensibili saltati — risolvi a mano.',
      );
  @override
  String get couldNotReadFiles =>
      'Impossibile leggere alcun file in conflitto.';
  @override
  String blockedSecret({required Object secret}) =>
      'Bloccato — un file in conflitto sembra contenere un ${secret}. Risolvi a mano.';
  @override
  String resolutionFailed({required Object error}) =>
      'Risoluzione non riuscita: ${error}';
  @override
  String mergeResolutionLabel({
    required Object resolved,
    required Object total,
    required Object category,
  }) => '◇ risoluzione merge · ${resolved}/${total} file · ${category}';
  @override
  String conflictSummary({
    required Object op,
    required Object conflicts,
    required Object files,
  }) => '${op} · ${conflicts} su ${files}';
  @override
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} conflitto',
        other: '${n} conflitti',
      );
  @override
  String get mergeEditorButton => '⇋ editor di merge';
  @override
  String get noAiModel => 'nessun modello AI';
  @override
  String get later => 'dopo';
  @override
  String get discard => 'scarta';
  @override
  String get resolveWithAi => '◇ risolvi con l\'AI';
  @override
  String get otherModel => 'altro modello';
  @override
  String withModel({required Object model}) => 'con ${model}';
}

// Path: changes.mergeFlow
class _Translations$changes$mergeFlow$it
    extends Translations$changes$mergeFlow$en {
  _Translations$changes$mergeFlow$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$mergeFlow$op$it op =
      _Translations$changes$mergeFlow$op$it._(_root);
  @override
  String get pushFailed => 'Push non riuscito';
  @override
  String get rebasedAndPushed => 'Rebase e push eseguiti.';
  @override
  String switchedTo({required Object name}) => 'Passato a ${name}.';
  @override
  String get switchFailed => 'Cambio non riuscito.';
  @override
  String switchedToCarried({required Object name}) =>
      'Passato a ${name} (modifiche riportate).';
  @override
  String get alreadyUpToDate => 'Già aggiornato.';
  @override
  String merged({required Object upstream, required Object n}) =>
      'Mergiato ${upstream} (${n} file).';
  @override
  String get rebaseNotConverge =>
      'Il rebase non è convergiuto — risolvi manualmente.';
  @override
  String get rebased => 'Rebase eseguito.';
  @override
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'Rebase eseguito (risolto ${n} file).',
        other: 'Rebase eseguito (risolti ${n} file).',
      );
  @override
  String get detachedHead =>
      'Sync impossibile: stato HEAD scollegato. Fai prima il checkout di un branch.';
  @override
  String get publishFailed => 'Pubblicazione non riuscita.';
  @override
  String get noRemote =>
      'Nessun remoto configurato. Aggiungine uno per pubblicare questo branch.';
  @override
  String get failed => 'fallito';
}

// Path: changes.constellation
class _Translations$changes$constellation$it
    extends Translations$changes$constellation$en {
  _Translations$changes$constellation$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get axisStructure => 'STRUTTURA';
  @override
  String get axisCoChange => 'CO-CHANGE';
  @override
  String get axisSpectralProfile => 'PROFILO SPETTRALE';
  @override
  String get axisPathSiblings => 'FRATELLI DI PERCORSO';
  @override
  String get axisDiffStructure => 'STRUTTURA DIFF';
  @override
  String get axisSpectral => 'SPETTRALE';
  @override
  String get titleUnsorted => 'NON ORDINATO';
  @override
  String get titleSingleton => 'SINGOLO';
  @override
  String get titleMixed => 'MISTO';
  @override
  String get untie => 'sciogli';
  @override
  String get bind => 'lega';
  @override
  String get emptyClusters => 'ancora nessun cluster';
}

// Path: common.time
class _Translations$common$time$it extends Translations$common$time$en {
  _Translations$common$time$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get now => 'ora';
  @override
  String get justNow => 'adesso';
  @override
  String get today => 'OGGI';
  @override
  String minutesAgo({required Object n}) => '${n} min fa';
  @override
  String hoursAgo({required Object n}) => '${n} h fa';
  @override
  String daysAgo({required Object n}) => '${n} g fa';
  @override
  String weeksAgo({required Object n}) => '${n} sett fa';
  @override
  String monthsAgo({required Object n}) => '${n} mes fa';
  @override
  String yearsAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} a fa',
        other: '${n} a fa',
      );
  @override
  String minutesShort({required Object n}) => '${n} min';
  @override
  String hoursShort({required Object n}) => '${n} h';
  @override
  String daysShort({required Object n}) => '${n} g';
  @override
  String weeksShort({required Object n}) => '${n} sett';
  @override
  String monthsShort({required Object n}) => '${n} mes';
  @override
  String yearsShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} a',
        other: '${n} a',
      );
  @override
  String commitMonthsShort({required Object n}) => '${n} m';
  @override
  String get idle => 'inattivo';
  @override
  String idleDays({required Object n}) => 'inattivo da ${n} giorni';
  @override
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'inattivo da ${n} anno',
        other: 'inattivo da ${n} anni',
      );
  @override
  List<String> get monthAbbrevs => [
    'Gen',
    'Feb',
    'Mar',
    'Apr',
    'Mag',
    'Giu',
    'Lug',
    'Ago',
    'Set',
    'Ott',
    'Nov',
    'Dic',
  ];
}

// Path: common.size
class _Translations$common$size$it extends Translations$common$size$en {
  _Translations$common$size$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

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
class _Translations$diff$status$it extends Translations$diff$status$en {
  _Translations$diff$status$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Caricamento diff';
  @override
  String get loadingMessage => 'Lettura delle modifiche al file.';
  @override
  String get unavailableTitle => 'Diff non disponibile';
  @override
  String get noChangesTitle => 'Nessuna modifica';
  @override
  String get noChangesMessage =>
      'Questo file non ha contenuto diff da mostrare.';
}

// Path: diff.toolbar
class _Translations$diff$toolbar$it extends Translations$diff$toolbar$en {
  _Translations$diff$toolbar$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get searchHint => 'cerca nel diff...';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} riga',
        other: '${n} righe',
      );
  @override
  String get blameLoading => 'blame...';
  @override
  String get blame => 'blame';
  @override
  String get wearMapOn => 'usura · on';
  @override
  String get wearMapOnHint => 'mappa d\'usura attiva — clicca per nascondere';
  @override
  String get wearMapOffHint => 'mostra mappa d\'usura (heatmap attività)';
  @override
  String get trailBadge => '· scia';
}

// Path: diff.hunkDropdown
class _Translations$diff$hunkDropdown$it
    extends Translations$diff$hunkDropdown$en {
  _Translations$diff$hunkDropdown$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip => 'Salta al blocco di modifiche. Git li chiama hunk.';
  @override
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} modifica',
        other: '${n} modifiche',
      );
}

// Path: diff.trail
class _Translations$diff$trail$it extends Translations$diff$trail$en {
  _Translations$diff$trail$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'caricamento scia...';
  @override
  String get noHistory => 'nessuna cronologia trovata';
  @override
  String get nowWorkingCopy => 'ora · copia di lavoro';
  @override
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class _Translations$diff$pinned$it extends Translations$diff$pinned$en {
  _Translations$diff$pinned$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get loadingContext => 'caricamento contesto fissato';
  @override
  String get pageManifold => 'Manifold';
  @override
  String get pageSignals => 'Segnali';
  @override
  String get echoesTitle => 'Echi';
  @override
  String get technicalLedger => 'Registro tecnico';
  @override
  String get noSecondaryCues => 'Nessun indizio secondario rilevato.';
  @override
  String get linkedPaths => 'Percorsi collegati';
  @override
  String moreCount({required Object n}) => '+${n} altri';
  @override
  String get localSeam => 'Giunzione locale';
  @override
  String get sharedOwnership => 'proprietà condivisa';
  @override
  String get historyWarmingUp => 'La cronologia si sta scaldando';
  @override
  String echoesTotal({required Object n}) => '${n} TOTALE';
  @override
  String get noEchoes => 'Nessun eco in questo diff.';
  @override
  String openRelatedFile({required Object name}) =>
      'Apri il file correlato ${name}';
  @override
  String inspectFile({required Object name}) => 'ispeziona ${name}';
  @override
  String get jumpEcho => 'vai all\'eco';
  @override
  String get copyLine => 'copia riga';
  @override
  String get signalTempo => 'T';
  @override
  String get signalNovelty => 'N';
  @override
  String get signalReach => 'R';
  @override
  late final _Translations$diff$pinned$tempo$it tempo =
      _Translations$diff$pinned$tempo$it._(_root);
  @override
  late final _Translations$diff$pinned$tone$it tone =
      _Translations$diff$pinned$tone$it._(_root);
  @override
  late final _Translations$diff$pinned$summary$it summary =
      _Translations$diff$pinned$summary$it._(_root);
  @override
  late final _Translations$diff$pinned$tightness$it tightness =
      _Translations$diff$pinned$tightness$it._(_root);
  @override
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept} (${tightness})';
  @override
  String get storyWhyThisMatters => 'Perché è importante';
  @override
  String get storyConfidence => 'Confidenza';
  @override
  String get storySecondarySignal => 'Segnale secondario';
  @override
  String get storyNeighbourhood => 'Vicinato';
  @override
  String neighbourhoodDetail({required Object name}) =>
      'Questa riga si trova vicino a ${name} nel campo attuale della codebase.';
  @override
  String get propagationLane => 'Corsia di propagazione';
  @override
  String propagationLaneNamed({required Object lane}) =>
      'Corsia di propagazione: ${lane}';
  @override
  late final _Translations$diff$pinned$witness$it witness =
      _Translations$diff$pinned$witness$it._(_root);
  @override
  late final _Translations$diff$pinned$integrity$it integrity =
      _Translations$diff$pinned$integrity$it._(_root);
  @override
  late final _Translations$diff$pinned$related$it related =
      _Translations$diff$pinned$related$it._(_root);
  @override
  late final _Translations$diff$pinned$axis$it axis =
      _Translations$diff$pinned$axis$it._(_root);
}

// Path: diff.hunkHint
class _Translations$diff$hunkHint$it extends Translations$diff$hunkHint$en {
  _Translations$diff$hunkHint$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String hiddenCount({required Object n}) => '${n} nascosti';
  @override
  String get landing => 'atterraggio';
}

// Path: diff.binary
class _Translations$diff$binary$it extends Translations$diff$binary$en {
  _Translations$diff$binary$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String tooLargeToPreview({required Object size}) =>
      '${size} MB (troppo grande per l\'anteprima)';
  @override
  String get unableToLoadBlob => 'Impossibile caricare il blob';
  @override
  String get omittedKindMedia => 'media';
  @override
  String get omittedKindBinary => 'binario';
  @override
  String omittedStub({required Object kind}) => '${kind} · nascosto';
}

// Path: diff.media
class _Translations$diff$media$it extends Translations$diff$media$en {
  _Translations$diff$media$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get unableToDecodeImage => 'Impossibile decodificare l\'immagine';
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
  String get stateAdded => 'aggiunto';
  @override
  String get stateDeleted => 'eliminato';
  @override
  String get stateModified => 'modificato';
  @override
  String get fallbackFormatName => 'Binario';
}

// Path: filament.severity
class _Translations$filament$severity$it
    extends Translations$filament$severity$en {
  _Translations$filament$severity$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get critical => 'critico';
  @override
  String get warn => 'avviso';
  @override
  String get info => 'info';
  @override
  String get joint => 'giunzione';
}

// Path: filament.kind
class _Translations$filament$kind$it extends Translations$filament$kind$en {
  _Translations$filament$kind$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get staleValue => 'valore obsoleto';
  @override
  String get temporalShift => 'slittamento temporale';
  @override
  String get contextInversion => 'inversione di contesto';
  @override
  String get contradictoryFlow => 'flusso contraddittorio';
}

// Path: history.commitLede
class _Translations$history$commitLede$it
    extends Translations$history$commitLede$en {
  _Translations$history$commitLede$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$semantics$it semantics =
      _Translations$history$commitLede$semantics$it._(_root);
}

// Path: history.seismograph
class _Translations$history$seismograph$it
    extends Translations$history$seismograph$en {
  _Translations$history$seismograph$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get rootTrackLabel => '(root)';
  @override
  String dirTrackLabel({required Object name}) => '(${name})';
  @override
  String moreLabel({required Object n}) => '+${n} altri';
  @override
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} file in ${path}/',
        other: '${n} file in ${path}/',
      );
  @override
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} altro file',
        other: '${n} altri file',
      );
  @override
  String get breadcrumbAll => 'tutti';
  @override
  String breadcrumbCurrentFocus({required Object target}) =>
      'Focus attuale: ${target}';
  @override
  String get breadcrumbViewAllChanges =>
      'Vedi tutte le modifiche di questo commit';
  @override
  String breadcrumbDrillUpTo({required Object target}) => 'Risali a ${target}';
  @override
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
    n,
    one: '${n} file  +${adds}  -${dels}',
    other: '${n} file  +${adds}  -${dels}',
  );
  @override
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} sottocart.',
        other: '${n} sottocart.',
      );
  @override
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}, ${adds} aggiunte, ${dels} eliminazioni';
  @override
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
    n,
    one: '${n} file, ${adds} aggiunte, ${dels} eliminazioni',
    other: '${n} file, ${adds} aggiunte, ${dels} eliminazioni',
  );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} hunk',
        other: '${n} hunk',
      );
  @override
  String get largestChangeInView => 'modifica più grande in questa vista';
  @override
  String get conflictedTag => 'in conflitto';
  @override
  String get dirtyTag => 'sporco';
  @override
  String get drillInTag => 'entra';
  @override
  String get changeTypeRenamed => 'rinominato';
  @override
  String get changeTypeCopied => 'copiato';
  @override
  String get changeTypeTypechange => 'cambio tipo';
  @override
  String get changeTypeConflict => 'conflitto';
  @override
  String get coreFile => 'file nucleo';
  @override
  String get staleFile => 'obsoleto';
  @override
  String get filterPathHint => 'filtra percorso';
  @override
  String get escHint => 'esc';
}

// Path: history.worldline
class _Translations$history$worldline$it
    extends Translations$history$worldline$en {
  _Translations$history$worldline$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get closeWorldline => 'Chiudi worldline';
  @override
  String get dragToOpenWorldline => 'Trascina per aprire la worldline';
}

// Path: history.contextMenu
class _Translations$history$contextMenu$it
    extends Translations$history$contextMenu$en {
  _Translations$history$contextMenu$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get currentBranchFallback => 'branch corrente';
  @override
  String applyCommitOnto({required Object branch}) =>
      'Applica le modifiche del commit su ${branch}';
  @override
  String revertCommitOn({required Object branch}) =>
      'Annulla le modifiche del commit su ${branch}';
}

// Path: history.cherryPick
class _Translations$history$cherryPick$it
    extends Translations$history$cherryPick$en {
  _Translations$history$cherryPick$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Cherry-pick in pausa. Concludi i conflitti rimanenti nella pagina Modifiche.';
  @override
  String failed({required Object error}) =>
      'Cherry-pick non riuscito: ${error}';
  @override
  String pickedResolved({required Object short}) =>
      'Cherry-pick di ${short} (conflitti risolti)';
  @override
  String picked({required Object short}) => 'Cherry-pick di ${short}';
}

// Path: history.revert
class _Translations$history$revert$it extends Translations$history$revert$en {
  _Translations$history$revert$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Revert in pausa. Concludi i conflitti rimanenti nella pagina Modifiche.';
  @override
  String failed({required Object error}) => 'Revert non riuscito: ${error}';
  @override
  String revertedResolved({required Object short}) =>
      'Revert di ${short} (conflitti risolti)';
  @override
  String reverted({required Object short}) => 'Revert di ${short}';
}

// Path: history.reflog
class _Translations$history$reflog$it extends Translations$history$reflog$en {
  _Translations$history$reflog$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get createBranchFromHere => 'Crea branch da qui…';
  @override
  String get copyCommitHash => 'Copia hash del commit';
  @override
  String get createBranchDialogTitle => 'Crea branch da voce reflog';
  @override
  String anchorLine({required Object short, required Object summary}) =>
      'Àncora: ${short}  ·  ${summary}';
  @override
  String get branchNameHint => 'nome branch';
  @override
  String get createAction => 'Crea';
  @override
  String createBranchFailed({required Object error}) =>
      'Creazione del branch non riuscita: ${error}';
  @override
  String branchCreatedAt({required Object name, required Object short}) =>
      'Branch "${name}" creato a ${short}.';
}

// Path: history.rebase
class _Translations$history$rebase$it extends Translations$history$rebase$en {
  _Translations$history$rebase$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String firstCommitCannotBe({required Object action}) =>
      'Il primo commit non può essere ${action}';
  @override
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'Rebase di ${n} commit',
        other: 'Rebase di ${n} commit',
      );
  @override
  String get resetLabel => 'reset';
  @override
  String get dragToReorderHint =>
      'trascina per riordinare, scegli l\'azione per commit';
  @override
  String get newMessageHint => 'nuovo messaggio';
  @override
  String get runningEllipsis => '…';
  @override
  String get startRebase => 'Avvia rebase';
}

// Path: history.inFlight
class _Translations$history$inFlight$it
    extends Translations$history$inFlight$en {
  _Translations$history$inFlight$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'IN VOLO';
  @override
  String get deskFallbackLabel => 'Desk';
}

// Path: historySurgery.chrome
class _Translations$historySurgery$chrome$it
    extends Translations$historySurgery$chrome$en {
  _Translations$historySurgery$chrome$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chirurgia della cronologia';
  @override
  String get alphaBadge => 'alpha';
  @override
  String get dryRunBadge => 'PROVA A VUOTO';
}

// Path: historySurgery.select
class _Translations$historySurgery$select$it
    extends Translations$historySurgery$select$en {
  _Translations$historySurgery$select$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get prompt => 'Seleziona i file da rimuovere dalla cronologia';
  @override
  String selectedCount({required Object n}) => '${n} selezionati';
  @override
  String get searchHint => 'cerca...';
  @override
  String get readingTree => 'lettura albero...';
  @override
  String get continueDisabled => 'seleziona file per continuare';
  @override
  String get continueEnabled => 'continua →';
  @override
  String toPurgeCount({required Object n}) => '${n} da eliminare';
  @override
  String get analyzing => 'analisi...';
  @override
  String get riskLow => 'rischio basso';
  @override
  String get riskModerate => 'rischio moderato';
  @override
  String get riskHigh => 'rischio alto';
  @override
  String get impactCommitsLabel => 'commit';
  @override
  String get impactBranchesLabel => 'branch';
  @override
  String get impactWorktreesLabel => 'worktree';
  @override
  String get impactCouplingLabel => 'coupling';
  @override
  String get impactCouplingIsland => 'isola';
  @override
  String impactCouplingNeighbors({required Object n}) => '${n} vicini';
  @override
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class _Translations$historySurgery$understand$it
    extends Translations$historySurgery$understand$en {
  _Translations$historySurgery$understand$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get heading => 'Come funziona';
  @override
  String get backupTitle => 'Backup';
  @override
  String get backupBody =>
      'Ogni ref di branch e tag viene copiata in un namespace di backup prima di qualsiasi modifica. Se qualcosa va storto, un clic ripristina lo stato originale.';
  @override
  String get rewriteTitle => 'Riscrittura';
  @override
  String get rewriteBody =>
      'Ogni commit viene percorso dalla radice alla punta. Per ogni commit che contiene i file bersaglio, viene creato un nuovo commit con quei file rimossi dall\'albero. Le catene di parent vengono rimappate per preservare la topologia. ';
  @override
  String rewriteSummary({required Object affected, required Object total}) =>
      '${affected} di ${total} commit verranno riscritti.';
  @override
  String get updateRefsTitle => 'Aggiorna ref';
  @override
  String get updateRefsBody =>
      'I puntatori di branch e tag vengono spostati sui nuovi SHA dei commit. I vecchi oggetti esistono ancora fino alla garbage collection. ';
  @override
  String worktreesNeedRecheckout({required Object n}) =>
      'I tuoi ${n} worktree richiederanno un nuovo checkout.';
  @override
  String get noWorktreesAffected => 'Nessun worktree interessato.';
  @override
  String get forcePushTitle => 'Force push';
  @override
  String get forcePushBody =>
      'Dopo aver verificato l\'eliminazione, scegli quali branch fare in force push. Usa --force-with-lease così fallisce in sicurezza se qualcun altro ha fatto push nel frattempo.';
  @override
  String get plumbingNote =>
      'A differenza di filter-repo o BFG, questo gira interamente tramite comandi plumbing di git (cat-file, mktree, commit-tree, update-ref). Nessuna dipendenza esterna. Il tracking dei rename segue una catena per file — se un file è stato copiato ed entrambe le copie rinominate in modo indipendente, verifica il risultato dell\'eliminazione dopo l\'esecuzione.';
  @override
  String get back => '← Indietro';
  @override
  String get continueLabel => 'Ho capito, continua →';
}

// Path: historySurgery.confirm
class _Translations$historySurgery$confirm$it
    extends Translations$historySurgery$confirm$en {
  _Translations$historySurgery$confirm$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String commitsRewritten({required Object n}) =>
      '${n} commit verranno riscritti';
  @override
  String get forcePushRequired =>
      'Sarà necessario il force push per i branch remoti';
  @override
  String worktreesRecheckout({required Object n}) =>
      '${n} worktree richiederanno un nuovo checkout';
  @override
  String stashesInvalid({required Object n}) =>
      '${n} stash potrebbero diventare non validi';
  @override
  String get heading => 'Questa operazione riscrive la cronologia git';
  @override
  String get subheading =>
      'Non può essere annullata automaticamente dopo il force push.';
  @override
  String typeHint({required Object word}) => 'digita ${word}';
  @override
  String get goBack => 'Torna indietro';
  @override
  String get begin => 'Inizia la chirurgia';
}

// Path: historySurgery.execute
class _Translations$historySurgery$execute$it
    extends Translations$historySurgery$execute$en {
  _Translations$historySurgery$execute$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => 'Preparazione...';
  @override
  String get backingUpRefs => 'Backup delle ref...';
  @override
  String get rewritingCommits => 'Riscrittura dei commit...';
  @override
  String get updatingRefs => 'Aggiornamento delle ref...';
}

// Path: historySurgery.verify
class _Translations$historySurgery$verify$it
    extends Translations$historySurgery$verify$en {
  _Translations$historySurgery$verify$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get complete => 'Chirurgia completata';
  @override
  String get failed => 'Chirurgia non riuscita';
  @override
  String get commitsRewrittenLabel => 'Commit riscritti';
  @override
  String get refsUpdatedLabel => 'Ref aggiornate';
  @override
  String get oldHeadLabel => 'Vecchio HEAD';
  @override
  String get newHeadLabel => 'Nuovo HEAD';
  @override
  String get purgeVerifiedLabel => 'Eliminazione verificata';
  @override
  String get purgeClean => 'pulito';
  @override
  String get purgeTracesRemain => 'RESTANO TRACCE';
  @override
  String get displacedWorktrees => 'Worktree spostati';
  @override
  String get undoSurgery => 'Annulla la chirurgia';
  @override
  String get rolledBack => 'Ripristinato alle ref di backup.';
  @override
  String get done => 'Fatto';
}

// Path: historySurgery.forcePush
class _Translations$historySurgery$forcePush$it
    extends Translations$historySurgery$forcePush$en {
  _Translations$historySurgery$forcePush$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get pushing => 'push in corso...';
  @override
  String get forcePushAll => 'Force push di tutti';
  @override
  String get confirmPush => 'conferma push';
  @override
  String get cancel => 'annulla';
}

// Path: onboarding.nav
class _Translations$onboarding$nav$it extends Translations$onboarding$nav$en {
  _Translations$onboarding$nav$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get back => 'Indietro';
  @override
  String get continueLabel => 'Continua';
  @override
  String get letsGo => 'Andiamo';
}

// Path: onboarding.naming
class _Translations$onboarding$naming$it
    extends Translations$onboarding$naming$en {
  _Translations$onboarding$naming$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'cos\'è questo per te?';
  @override
  String get questionEmphasis => 'questo';
  @override
  String get iAmPrefix => 'Sono ';
  @override
  String get iAmSuffix => ' , il tuo Git Client personale.';
}

// Path: onboarding.theme
class _Translations$onboarding$theme$it
    extends Translations$onboarding$theme$en {
  _Translations$onboarding$theme$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'vesti ${name} a festa.';
  @override
  String get themesHeader => 'TEMI';
  @override
  String get keybindingsHeader => 'SCORCIATOIE';
  @override
  String get previewBadge => 'anteprima';
  @override
  String get useDefaults => 'usa i predefiniti';
}

// Path: onboarding.repo
class _Translations$onboarding$repo$it extends Translations$onboarding$repo$en {
  _Translations$onboarding$repo$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'punta ${name} verso qualcosa.';
  @override
  String get later => 'lo farò dopo';
  @override
  late final _Translations$onboarding$repo$doors$it doors =
      _Translations$onboarding$repo$doors$it._(_root);
  @override
  late final _Translations$onboarding$repo$cloneForm$it cloneForm =
      _Translations$onboarding$repo$cloneForm$it._(_root);
  @override
  late final _Translations$onboarding$repo$pickers$it pickers =
      _Translations$onboarding$repo$pickers$it._(_root);
  @override
  late final _Translations$onboarding$repo$errors$it errors =
      _Translations$onboarding$repo$errors$it._(_root);
}

// Path: onboarding.preview
class _Translations$onboarding$preview$it
    extends Translations$onboarding$preview$en {
  _Translations$onboarding$preview$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$preview$panels$it panels =
      _Translations$onboarding$preview$panels$it._(_root);
  @override
  late final _Translations$onboarding$preview$sidebar$it sidebar =
      _Translations$onboarding$preview$sidebar$it._(_root);
  @override
  late final _Translations$onboarding$preview$changes$it changes =
      _Translations$onboarding$preview$changes$it._(_root);
  @override
  late final _Translations$onboarding$preview$history$it history =
      _Translations$onboarding$preview$history$it._(_root);
  @override
  late final _Translations$onboarding$preview$branches$it branches =
      _Translations$onboarding$preview$branches$it._(_root);
  @override
  late final _Translations$onboarding$preview$diff$it diff =
      _Translations$onboarding$preview$diff$it._(_root);
}

// Path: orrery.header
class _Translations$orrery$header$it extends Translations$orrery$header$en {
  _Translations$orrery$header$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Orrery';
  @override
  String get modeScrub => 'Scorri';
  @override
  String get modeCompare => 'Confronta';
  @override
  String get lodModules => 'Moduli';
  @override
  String get lodFiles => 'File';
}

// Path: orrery.status
class _Translations$orrery$status$it extends Translations$orrery$status$en {
  _Translations$orrery$status$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'Traccio il manifold attraverso la cronologia…';
  @override
  String get loadError => 'Impossibile leggere la cronologia di questo repo.';
  @override
  String get notEnoughHistory =>
      'Cronologia ancora insufficiente per tracciare una traiettoria.';
  @override
  String get notEnoughHistoryDetail =>
      'L\'Orrery ha bisogno di qualche commit per disegnare la mappa.';
}

// Path: orrery.legend
class _Translations$orrery$legend$it extends Translations$orrery$legend$en {
  _Translations$orrery$legend$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get central => 'centrale';
  @override
  String get peripheral => 'periferico';
}

// Path: orrery.node
class _Translations$orrery$node$it extends Translations$orrery$node$en {
  _Translations$orrery$node$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get module => 'modulo';
  @override
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · ${n} file';
  @override
  String fileFallback({required Object id}) => 'file #${id}';
  @override
  String nodeFallback({required Object id}) => 'nodo #${id}';
  @override
  String get rootModule => '(root)';
}

// Path: orrery.milestone
class _Translations$orrery$milestone$it
    extends Translations$orrery$milestone$en {
  _Translations$orrery$milestone$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get genesis => 'genesi';
  @override
  String get now => 'ora';
  @override
  String get reorganized => 'riorganizzato';
  @override
  String becameArchetype({required Object archetype}) =>
      'diventato ${archetype}';
  @override
  String get snapshot => 'snapshot';
}

// Path: orrery.structure
class _Translations$orrery$structure$it
    extends Translations$orrery$structure$en {
  _Translations$orrery$structure$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get forming => 'in formazione…';
  @override
  String get canonical => 'canonico';
  @override
  String get connectivity => 'connettività';
  @override
  String get rigidity => 'rigidità';
  @override
  String get entropy => 'entropia';
}

// Path: orrery.rail
class _Translations$orrery$rail$it extends Translations$orrery$rail$en {
  _Translations$orrery$rail$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get structureLabel => 'STRUTTURA';
  @override
  String get fieldLabel => 'CAMPO';
  @override
  String get findingsLabel => 'RISCONTRI';
  @override
  String get selectedLabel => 'SELEZIONATO';
  @override
  String get noFindings =>
      'Nessun evento strutturale rilevato in questa cronologia.';
}

// Path: orrery.selection
class _Translations$orrery$selection$it
    extends Translations$orrery$selection$en {
  _Translations$orrery$selection$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get notPresent => 'Non presente a questo punto della cronologia.';
  @override
  String get roleCentral =>
      'Centrale nel coupling — le modifiche qui si propagano in tutto il sistema.';
  @override
  String get rolePeripheral =>
      'Periferico — debolmente accoppiato, per lo più cambia da solo.';
  @override
  String get roleMid => 'Struttura intermedia — moderatamente accoppiato.';
  @override
  String get driftOutward => ' Deriva verso l\'esterno — si disaccoppia.';
  @override
  String get driftInward => ' Deriva verso l\'interno — si integra.';
  @override
  String get driftHolding => ' Mantiene la sua posizione.';
}

// Path: orrery.findingKind
class _Translations$orrery$findingKind$it
    extends Translations$orrery$findingKind$en {
  _Translations$orrery$findingKind$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get hub => 'HUB';
  @override
  String get driftOut => 'IN DERIVA VERSO L\'ESTERNO';
  @override
  String get driftIn => 'IN DERIVA VERSO L\'INTERNO';
  @override
  String get tangle => 'AGGROVIGLIAMENTO';
  @override
  String get clarify => 'CHIARIFICAZIONE';
  @override
  String get regime => 'RIORG';
  @override
  String get thrash => 'SBATTIMENTO';
  @override
  String get reshuffle => 'RIMESCOLAMENTO';
  @override
  String get forecast => 'PREVISIONE';
}

// Path: orrery.findings
class _Translations$orrery$findings$it extends Translations$orrery$findings$en {
  _Translations$orrery$findings$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get forecastSplit =>
      'La connettività è in calo ed è vicina al suo minimo — se prosegue così, la codebase sta andando verso una divisione in due metà debolmente accoppiate. Decidi ora se è ciò che vuoi.';
  @override
  String get forecastConsolidate =>
      'La connettività sta salendo verso il suo picco — se prosegue così, la codebase si sta consolidando in un\'unica massa strettamente accoppiata. Attento a che non si indurisca in un monolite.';
  @override
  String thrash({required Object name}) =>
      '${name} continua a essere riorganizzato avanti e indietro — molto rimescolio strutturale, poco movimento netto. Definisci il suo coupling o smetti di toccarlo.';
  @override
  String get reshuffle =>
      'Questo commit sembrava di routine ma ha spostato in sordina quali file sono centrali — la forma complessiva ha tenuto mentre la struttura si rimescolava sotto. Rivedilo con attenzione.';
  @override
  String hub({required Object name}) =>
      '${name} sta al nucleo strutturale — il sistema si riorganizza attorno a lui. Tratta le modifiche qui come ad alto raggio d\'impatto.';
  @override
  String driftOut({required Object name}) =>
      '${name} è derivato dal nucleo verso il bordo — si sta disaccoppiando dal sistema. O lo stai dismettendo, o sta marcendo in silenzio.';
  @override
  String driftIn({required Object name}) =>
      '${name} è migrato verso il nucleo — sta diventando portante. Assicurati che sia ben testato prima che altro dipenda da lui.';
  @override
  String get regime =>
      'La codebase si è riorganizzata bruscamente qui — la sua connettività è balzata. Rivedi cosa si è staccato o fuso.';
  @override
  String get tangleTrend =>
      'Nel corso della sua cronologia la codebase ha teso verso una struttura più aggrovigliata — la sua connettività diventa più densa e meno modulare.';
  @override
  String get clarifyTrend =>
      'Nel corso della sua cronologia la codebase ha teso verso una struttura più pulita — si sta separando in moduli più chiari.';
}

// Path: orrery.anchor
class _Translations$orrery$anchor$it extends Translations$orrery$anchor$en {
  _Translations$orrery$anchor$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get core => 'nucleo';
  @override
  String get drift => 'deriva';
  @override
  String get trend => 'tendenza';
  @override
  String get thrash => 'sbattimento';
}

// Path: orrery.compare
class _Translations$orrery$compare$it extends Translations$orrery$compare$en {
  _Translations$orrery$compare$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'A → B';
  @override
  String get change => 'VARIAZIONE';
  @override
  String get movers => 'IN MOVIMENTO';
  @override
  String get noMovers => 'Nessun file si è mosso tra questi frame.';
  @override
  String get badgeA => 'A';
  @override
  String get badgeB => 'B';
  @override
  String get deltaFiles => 'file';
  @override
  String get deltaConnectivity => 'connettività';
  @override
  String get deltaRigidity => 'rigidità';
  @override
  String get deltaEntropy => 'entropia';
  @override
  String get wayOutward => 'verso l\'esterno';
  @override
  String get wayInward => 'verso l\'interno';
  @override
  String get wayShifted => 'spostato';
}

// Path: palette.prefixes
class _Translations$palette$prefixes$it
    extends Translations$palette$prefixes$en {
  _Translations$palette$prefixes$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get askHint => 'chiedi: [domanda]';
  @override
  String get nearHint => 'vicino: [file]';
  @override
  String get whoHint => 'chi: [file]';
  @override
  String get logHint => 'log: [messaggio]';
  @override
  String get runHint => 'avvia: [tool]';
  @override
  String askLabel({required Object name, required Object body}) =>
      'Chiedi a ${name}: ${body}';
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
  }) => '${path} · ${count} reviewer · ${touches} tocchi';
  @override
  String whoTouchesLabel({required Object name, required Object touches}) =>
      '${name} — ${touches} tocchi';
  @override
  String whoTouchesSubtitle({required Object path}) =>
      '${path} · nessun reviewer registrato';
}

// Path: palette.chips
class _Translations$palette$chips$it extends Translations$palette$chips$en {
  _Translations$palette$chips$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get ai => 'AI';
  @override
  String get near => 'VICINO';
  @override
  String get who => 'CHI';
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
  String get hot => 'CALDO';
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
  String get draft => 'BOZZA';
  @override
  String get undo => 'ANNULLA';
  @override
  String get thm => 'THM';
  @override
  String get ver => 'VER';
  @override
  String get desk => 'BANCO';
  @override
  String get det => 'DET';
  @override
  String get main => 'MAIN';
  @override
  String get head => 'HEAD';
  @override
  String get gone => 'SPARITO';
  @override
  String get remote => 'REMOTO';
  @override
  String get local => 'LOCALE';
  @override
  String get an => 'AN';
  @override
  String get lw => 'LW';
}

// Path: palette.predictive
class _Translations$palette$predictive$it
    extends Translations$palette$predictive$en {
  _Translations$palette$predictive$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String momentumSuffix({required Object percent}) => '${percent}% slancio';
}

// Path: palette.topTouched
class _Translations$palette$topTouched$it
    extends Translations$palette$topTouched$en {
  _Translations$palette$topTouched$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object count, required Object path}) =>
      '${count} tocchi · ${path}';
}

// Path: palette.coherence
class _Translations$palette$coherence$it
    extends Translations$palette$coherence$en {
  _Translations$palette$coherence$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String label({required Object percent}) => 'Coerenza in stage: ${percent}%';
  @override
  String subtitle({required Object count}) => '${count} file';
}

// Path: palette.keystone
class _Translations$palette$keystone$it
    extends Translations$palette$keystone$en {
  _Translations$palette$keystone$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object path, required Object score}) =>
      '${path} · pietra angolare ${score}';
}

// Path: palette.repoSub
class _Translations$palette$repoSub$it extends Translations$palette$repoSub$en {
  _Translations$palette$repoSub$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String changes({required Object name}) => 'Modifiche in ${name}';
  @override
  String history({required Object name}) => 'Cronologia in ${name}';
  @override
  String branches({required Object name}) => 'Branch in ${name}';
  @override
  String terminal({required Object name}) => 'Terminale in ${name}';
  @override
  String generateCommit({required Object name}) => 'Genera commit · ${name}';
  @override
  String reviewChanges({required Object name}) =>
      'Rivedi le modifiche in ${name}';
  @override
  String muse({required Object name}) => 'Muse in ${name}';
}

// Path: palette.desks
class _Translations$palette$desks$it extends Translations$palette$desks$en {
  _Translations$palette$desks$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get mainWorktree => 'worktree principale';
  @override
  String get detached => 'scollegato';
  @override
  String dirty({required Object count}) => '${count} sporchi';
}

// Path: palette.actions
class _Translations$palette$actions$it extends Translations$palette$actions$en {
  _Translations$palette$actions$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get openInBrowser => 'Apri nel browser';
  @override
  String get terminal => 'Terminale';
  @override
  String get revealInFiles => 'Mostra nei file';
  @override
  String get copyPath => 'Copia percorso';
  @override
  String get copyBranch => 'Copia branch';
}

// Path: palette.tools
class _Translations$palette$tools$it extends Translations$palette$tools$en {
  _Translations$palette$tools$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String launch({required Object label}) => 'Avvia ${label}';
}

// Path: palette.gitCommands
class _Translations$palette$gitCommands$it
    extends Translations$palette$gitCommands$en {
  _Translations$palette$gitCommands$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get fetch => 'Fetch';
  @override
  String get pull => 'Pull';
  @override
  String pullBehind({required Object count}) => '${count} indietro';
  @override
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';
  @override
  String get push => 'Push';
  @override
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} commit',
        other: '${n} commit',
      );
  @override
  String pushCommitsUpstream({
    required Object commits,
    required Object upstream,
  }) => '${commits} verso ${upstream}';
  @override
  String get forcePush => 'Force push';
  @override
  String forcePushNoUpstream({required Object branch}) =>
      'Force push impossibile: nessun upstream impostato per ${branch}.';
  @override
  String get commit => 'Commit';
  @override
  String get stageAll => 'Stage di tutto';
  @override
  String get unstageAll => 'Unstage di tutto';
  @override
  String get discardAll => 'Scarta tutto';
  @override
  String get createBranch => 'Crea branch';
  @override
  String get deleteBranch => 'Elimina branch';
  @override
  String get renameBranch => 'Rinomina branch';
  @override
  String get stash => 'Stash';
  @override
  String get stashPop => 'Stash pop';
  @override
  String get stashApply => 'Stash apply';
  @override
  String get stashDrop => 'Stash drop';
  @override
  String get createTag => 'Crea tag';
  @override
  String get cherryPick => 'Cherry-pick';
  @override
  String get revert => 'Revert';
  @override
  String get stashConflictMessage =>
      'Stash applicato con conflitti. Risolvili nella pagina Modifiche.';
}

// Path: palette.pr
class _Translations$palette$pr$it extends Translations$palette$pr$en {
  _Translations$palette$pr$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get create => 'Crea PR';
  @override
  String get merge => 'Merge PR';
  @override
  String get markReady => 'Segna PR come pronta';
}

// Path: palette.ai
class _Translations$palette$ai$it extends Translations$palette$ai$en {
  _Translations$palette$ai$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get generateCommit => 'Genera commit';
  @override
  String get reviewChanges => 'Rivedi le modifiche';
  @override
  String get runMuse => 'Avvia Muse';
  @override
  String debugRepo({required Object name}) => 'Debug di ${name}';
  @override
  String get describeSymptom => 'descrivi un sintomo';
  @override
  String viewResult({required Object kind}) => 'Vedi ${kind}';
  @override
  String get unseenResult => 'risultato non visto';
  @override
  String runningResult({required Object kind}) => 'AI: ${kind}…';
  @override
  String get running => 'in corso';
  @override
  String get kindCommitMessage => 'Messaggio di commit';
  @override
  String get kindCodeReview => 'Code review';
  @override
  String get kindMuseResult => 'Risultato Muse';
  @override
  String get kindPresentation => 'Presentazione';
  @override
  String get kindDebugResult => 'Risultato debug';
}

// Path: palette.undo
class _Translations$palette$undo$it extends Translations$palette$undo$en {
  _Translations$palette$undo$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String cancel({required Object label}) => 'Annulla: ${label}';
}

// Path: palette.navigation
class _Translations$palette$navigation$it
    extends Translations$palette$navigation$en {
  _Translations$palette$navigation$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get changes => 'Modifiche';
  @override
  String get history => 'Cronologia';
  @override
  String get branches => 'Branch';
  @override
  String get xray => 'X-Ray';
  @override
  String get settings => 'Impostazioni';
  @override
  String get refresh => 'Aggiorna';
}

// Path: palette.settings
class _Translations$palette$settings$it
    extends Translations$palette$settings$en {
  _Translations$palette$settings$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get reduceMotion => 'Riduci il movimento';
  @override
  String get animateLogoUnfocused => 'Anima il logo non a fuoco';
  @override
  String get instantBlameHover => 'Blame istantaneo al passaggio';
  @override
  String get autoSelectChanges => 'Auto-seleziona le modifiche';
  @override
  String get fetchOnlineIssues => 'Recupera le issue online';
  @override
  String get rememberWip => 'Ricorda il lavoro in corso';
  @override
  String get hideAiFeatures => 'Nascondi le funzioni AI';
  @override
  String get crashReporting => 'Segnalazione crash';
  @override
  String get aiReadOnly => 'AI in sola lettura';
  @override
  String get stashCabinetExpanded => 'Armadietto stash espanso';
  @override
  String get fileSortInverted => 'Ordinamento file invertito';
}

// Path: palette.info
class _Translations$palette$info$it extends Translations$palette$info$en {
  _Translations$palette$info$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class _Translations$palette$debug$it extends Translations$palette$debug$en {
  _Translations$palette$debug$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get engineStatus => 'Stato del motore';
  @override
  String get engineStatusSubtitle =>
      'Diagnostica del motore spettrale LogosGit';
  @override
  String get fileCoupling => 'Coupling dei file';
  @override
  String get fileCouplingSubtitle =>
      'Vicini di co-change più prossimi per i file in stage';
  @override
  String get themeSpecimen => 'Campione del tema';
  @override
  String get themeSpecimenSubtitle =>
      'Tutti i colori, le icone, i livelli di testo e la geometria';
}

// Path: palette.dev
class _Translations$palette$dev$it extends Translations$palette$dev$en {
  _Translations$palette$dev$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get testMergeEditor => 'Testa l\'editor di merge';
  @override
  String get testHistorySurgery => 'Testa la chirurgia della cronologia';
  @override
  String get back => 'indietro';
  @override
  String get cancel => 'annulla';
  @override
  String get buildingConflicts =>
      'costruzione dei conflitti di test dalla cronologia…';
}

// Path: palette.historySurgery
class _Translations$palette$historySurgery$it
    extends Translations$palette$historySurgery$en {
  _Translations$palette$historySurgery$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Chirurgia della cronologia';
  @override
  String get subtitle =>
      'Riscrivi la cronologia per rimuovere i file in modo definitivo';
}

// Path: palette.orrery
class _Translations$palette$orrery$it extends Translations$palette$orrery$en {
  _Translations$palette$orrery$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Orrery';
  @override
  String get subtitle =>
      'Scorri la cronologia strutturale del repo attraverso il manifold';
}

// Path: palette.command
class _Translations$palette$command$it extends Translations$palette$command$en {
  _Translations$palette$command$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String complete({required Object label}) => '${label} completato';
  @override
  String failed({required Object label, required Object message}) =>
      '${label} non riuscito: ${message}';
  @override
  String get copy => 'Copia';
}

// Path: palette.search
class _Translations$palette$search$it extends Translations$palette$search$en {
  _Translations$palette$search$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get hintDefault => 'cerca in tutto...';
  @override
  String get hintElevated => 'elevata — tutte le azioni';
  @override
  String get emptyTypeToSearch => 'digita per cercare';
  @override
  String get emptyNoResults => 'nessun risultato';
}

// Path: palette.wick
class _Translations$palette$wick$it extends Translations$palette$wick$en {
  _Translations$palette$wick$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Wick';
  @override
  String get coupledFallback => 'accoppiato';
}

// Path: palette.gitCache
class _Translations$palette$gitCache$it
    extends Translations$palette$gitCache$en {
  _Translations$palette$gitCache$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'corrente';
  @override
  String get staged => 'in stage';
  @override
  String get modified => 'modificato';
}

// Path: releaseNotes.about
class _Translations$releaseNotes$about$it
    extends Translations$releaseNotes$about$en {
  _Translations$releaseNotes$about$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$releaseNotes$about$whyFlutter$it whyFlutter =
      _Translations$releaseNotes$about$whyFlutter$it._(_root);
  @override
  late final _Translations$releaseNotes$about$spectralEngine$it spectralEngine =
      _Translations$releaseNotes$about$spectralEngine$it._(_root);
  @override
  late final _Translations$releaseNotes$about$whereGoing$it whereGoing =
      _Translations$releaseNotes$about$whereGoing$it._(_root);
}

// Path: releaseNotes.legal
class _Translations$releaseNotes$legal$it
    extends Translations$releaseNotes$legal$en {
  _Translations$releaseNotes$legal$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get copyright => '© 2026 Woflo Labs';
  @override
  String get license =>
      'GPL-3.0-or-later · nucleo di ricerca community-source WLCSL · nessuna garanzia';
}

// Path: repoSummary.backbone
class _Translations$repoSummary$backbone$it
    extends Translations$repoSummary$backbone$en {
  _Translations$repoSummary$backbone$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}` (${lines}) — ${region}';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} riga',
        other: '${n} righe',
      );
  @override
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class _Translations$repoSummary$glance$it
    extends Translations$repoSummary$glance$en {
  _Translations$repoSummary$glance$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} file.',
        other: '${n} file.',
      );
  @override
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} riga (${bytes}).',
        other: '${n} righe (${bytes}).',
      );
  @override
  String roles({required Object parts}) => 'Ruoli — ${parts}.';
  @override
  String showingNofM({required Object active, required Object total}) =>
      'Mostro ${active} di ${total} file, ordinati per centralità strutturale.';
}

// Path: repoSummary.heading
class _Translations$repoSummary$heading$it
    extends Translations$repoSummary$heading$en {
  _Translations$repoSummary$heading$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get atAGlance => 'In sintesi';
  @override
  String get core => 'Nucleo';
  @override
  String get gettingStarted => 'Per iniziare';
  @override
  String get regions => 'Regioni';
  @override
  String get shape => 'Forma';
}

// Path: repoSummary.pitch
class _Translations$repoSummary$pitch$it
    extends Translations$repoSummary$pitch$en {
  _Translations$repoSummary$pitch$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String empty({required Object detail}) =>
      'Un repository senza file di testo leggibili${detail}.';
  @override
  String emptyBinary({required Object n}) => '${n} binario';
  @override
  String emptyUnreadable({required Object n}) => '${n} illeggibile';
  @override
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'Un repository con ${n} file attivo.',
        other: 'Un repository con ${n} file attivi.',
      );
  @override
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'Un repository con ${n} file attivo — ${regions}.',
        other: 'Un repository con ${n} file attivi — ${regions}.',
      );
}

// Path: repoSummary.region
class _Translations$repoSummary$region$it
    extends Translations$repoSummary$region$en {
  _Translations$repoSummary$region$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String bodyCommonDir({required Object dir}) => 'Tutto sotto `${dir}`.';
  @override
  String get bodyCommonDirSeparator => ' ';
  @override
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '1 nucleo',
        other: '${n} nucleo',
      );
  @override
  String get bodyCoreSeparator => ', ';
  @override
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'Un file',
        other: '${n} file',
      );
  @override
  String connectsTo({required Object linked}) => 'Si collega a: ${linked}.';
  @override
  String get filesLabel => 'File:';
}

// Path: repoSummary.shape
class _Translations$repoSummary$shape$it
    extends Translations$repoSummary$shape$en {
  _Translations$repoSummary$shape$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get bulk =>
      'Codebase densamente interconnessa: la maggior parte dei file partecipa a un unico grande vicinato di modifiche condivise.';
  @override
  String get crystalline =>
      'Codebase a reticolo: coupling uniforme e regolare tra i file con struttura locale prevedibile.';
  @override
  String get goe =>
      'Codebase riccamente interconnessa: i coupling si diffondono tra i file senza una spina dorsale dominante.';
  @override
  String get modular =>
      'Codebase modulare: diverse regioni coese con coupling incrociato limitato. Il lavoro in una regione raramente disturba un\'altra.';
  @override
  String get poisson =>
      'Codebase debolmente accoppiata: i file evolvono per lo più da soli, con occasionali modifiche condivise.';
  @override
  String get tree =>
      'Codebase ad albero: una spina dorsale dominante con branch dipendenti. Le modifiche di solito si propagano dal nucleo verso l\'esterno.';
}

// Path: settings.language
class _Translations$settings$language$it
    extends Translations$settings$language$en {
  _Translations$settings$language$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Lingua';
  @override
  String get summary =>
      'Lingua dell\'interfaccia per questa app. Output di git, log e diagnostica restano in inglese così le segnalazioni di bug rimangono ricercabili.';
  @override
  String get label => 'LINGUA INTERFACCIA';
  @override
  String get systemDefault => 'Predefinita di sistema';
  @override
  String systemDefaultDetail({required Object resolved}) =>
      'Segue la lingua del tuo OS (${resolved})';
  @override
  String get disclosureSource => 'Lingua sorgente, scritta dagli sviluppatori.';
  @override
  String disclosureAi({required Object model}) =>
      'Tradotta automaticamente da ${model}, non ancora revisionata da umani. Correzioni benvenute.';
  @override
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) =>
      'Tradotta automaticamente da ${model}. Revisionata da umani al ${percent}%.';
  @override
  String get disclosureHuman => 'Traduzione umana, mantenuta dalla community.';
  @override
  String reviewedBy({required Object names}) => 'Revisionata da ${names}.';
}

// Path: settings.sectionLabels
class _Translations$settings$sectionLabels$it
    extends Translations$settings$sectionLabels$en {
  _Translations$settings$sectionLabels$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get preferences => 'Preferenze';
  @override
  String get shortcuts => 'Scorciatoie';
  @override
  String get behaviour => 'Comportamento';
  @override
  String get aiProviders => 'Provider AI';
  @override
  String get modelSlots => 'Slot modelli';
  @override
  String get tools => 'Strumenti';
  @override
  String get diagnostics => 'Diagnostica';
  @override
  String get offenders => 'Colpevoli';
  @override
  String get release => 'Release';
}

// Path: settings.errors
class _Translations$settings$errors$it extends Translations$settings$errors$en {
  _Translations$settings$errors$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get saveGuardrailProfile =>
      'Impossibile salvare il profilo dei guardrail.';
  @override
  String get saveRetentionPolicy =>
      'Impossibile salvare la politica di conservazione.';
  @override
  String get saveUpdateChannel =>
      'Impossibile salvare il canale di aggiornamento.';
  @override
  String get saveModelSelection =>
      'Impossibile salvare la selezione del modello AI.';
  @override
  String get saveModelAlias => 'Impossibile salvare l\'alias del modello.';
  @override
  String get saveCommitMessageModelSlot =>
      'Impossibile salvare lo slot del modello per i messaggi di commit.';
  @override
  String get saveReviewModelSlot =>
      'Impossibile salvare lo slot del modello per la review.';
  @override
  String get saveCommitMessageCustomPrompt =>
      'Impossibile salvare il prompt personalizzato per i messaggi di commit.';
  @override
  String get saveReviewGuide => 'Impossibile salvare la guida alla review.';
  @override
  String get saveMuseNotes => 'Impossibile salvare le note della muse.';
  @override
  String get saveReviewDoubleCheck =>
      'Impossibile salvare la modalità di doppio controllo della review.';
  @override
  String get saveApiPiggybackCli =>
      'Impossibile salvare la CLI di piggyback API.';
  @override
  String get saveCliTimeout => 'Impossibile salvare il timeout della CLI.';
  @override
  String get stopAllCli => 'Impossibile arrestare le sessioni CLI in corso.';
  @override
  String clearLocalData({required Object error}) =>
      'Impossibile cancellare i dati locali: ${error}';
}

// Path: settings.promptStatus
class _Translations$settings$promptStatus$it
    extends Translations$settings$promptStatus$en {
  _Translations$settings$promptStatus$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get editing => 'Modifica';
  @override
  String get saving => 'Salvataggio';
  @override
  String get saveFailed => 'Salvataggio non riuscito';
}

// Path: settings.clearData
class _Translations$settings$clearData$it
    extends Translations$settings$clearData$en {
  _Translations$settings$clearData$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => 'Cancella i dati locali';
  @override
  String get clear => 'Cancella';
  @override
  String get confirmDiagnostics =>
      'Cancellare i campioni di diagnostica locale e i tempi di performance?';
  @override
  String get confirmAudit =>
      'Cancellare i record locali di metadati di audit AI?';
  @override
  String get confirmAll =>
      'Cancellare tutti i campioni di diagnostica locale e i record di metadati di audit AI?';
  @override
  String get confirmWipeAll =>
      'Cancellare tutti i dati locali dell\'app — inclusa la lista dei repo recenti — e uscire? I tuoi repo git effettivi su disco non vengono toccati.';
  @override
  String get confirmReset =>
      'Reimpostare i dati locali dell\'app e uscire?\n\nVengono cancellati impostazioni, tema, onboarding, preferenze AI, telemetria e cache degli engram. La lista dei tuoi repo recenti sopravvive.';
}

// Path: settings.guardrailMacro
class _Translations$settings$guardrailMacro$it
    extends Translations$settings$guardrailMacro$en {
  _Translations$settings$guardrailMacro$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'lasco';
  @override
  String get balanced => 'bilanciato';
  @override
  String get strict => 'rigoroso';
  @override
  String get paranoid => 'paranoico';
}

// Path: settings.guardrails
class _Translations$settings$guardrails$it
    extends Translations$settings$guardrails$en {
  _Translations$settings$guardrails$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Guardrail';
  @override
  String get summary =>
      'Quanto è attenta l\'automazione in tutta l\'esperienza.';
}

// Path: settings.appearance
class _Translations$settings$appearance$it
    extends Translations$settings$appearance$en {
  _Translations$settings$appearance$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Aspetto';
  @override
  String get summary => 'Umore e atmosfera globali dell\'interfaccia.';
}

// Path: settings.retention
class _Translations$settings$retention$it
    extends Translations$settings$retention$en {
  _Translations$settings$retention$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Conservazione dei dati locali';
  @override
  String get summaryDiagnostics =>
      'Politica di conservazione della diagnostica.';
  @override
  String get summaryWithAudit =>
      'Politica di conservazione della diagnostica e dell\'audit AI.';
  @override
  String get unitDays => 'giorni';
  @override
  String get unitMb => 'MB';
  @override
  String get includesNote =>
      'Include diagnostica, tempi di performance e metadati.';
}

// Path: settings.navigation
class _Translations$settings$navigation$it
    extends Translations$settings$navigation$en {
  _Translations$settings$navigation$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Navigazione e dinamiche';
  @override
  String get summaryShortcuts =>
      'Scorciatoie e comportamento dell\'interfaccia.';
  @override
  String get summaryWithAi =>
      'Scorciatoie, comportamento dell\'interfaccia e routing AI.';
}

// Path: settings.behaviour
class _Translations$settings$behaviour$it
    extends Translations$settings$behaviour$en {
  _Translations$settings$behaviour$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Dinamiche comportamentali';
}

// Path: settings.retentionClear
class _Translations$settings$retentionClear$it
    extends Translations$settings$retentionClear$en {
  _Translations$settings$retentionClear$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get diag => 'Diag';
  @override
  String get audit => 'Audit';
  @override
  String get all => 'Tutto';
  @override
  String get clearsHint => '<-- cancella';
}

// Path: settings.channels
class _Translations$settings$channels$it
    extends Translations$settings$channels$en {
  _Translations$settings$channels$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get stable => 'STABLE';
  @override
  String get beta => 'BETA';
  @override
  String get dev => 'DEV';
}

// Path: settings.pollResult
class _Translations$settings$pollResult$it
    extends Translations$settings$pollResult$en {
  _Translations$settings$pollResult$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get upToDate => 'aggiornato';
  @override
  String updateAvailable({required Object version}) => '${version} disponibile';
  @override
  String get notConfigured => 'nessun server di aggiornamento';
  @override
  String notFound({required Object channel}) => 'nessuna release ${channel}';
  @override
  String get unreachable => 'irraggiungibile';
  @override
  String get badManifest => 'manifest non valido';
}

// Path: settings.keybindingProfile
class _Translations$settings$keybindingProfile$it
    extends Translations$settings$keybindingProfile$en {
  _Translations$settings$keybindingProfile$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Profilo scorciatoie';
  @override
  String get porcelain => 'Porcelain';
  @override
  String get numeric => 'Numerico';
  @override
  String get porcelainDescription => 'Scorciatoie in accordo (G poi C, H, B…).';
  @override
  String get numericDescription =>
      'Scorciatoie numeriche a tasto singolo (1, 2, 3…).';
}

// Path: settings.apiKeys
class _Translations$settings$apiKeys$it
    extends Translations$settings$apiKeys$en {
  _Translations$settings$apiKeys$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get keyHintDefault => 'chiave api';
  @override
  String get endpointHint => 'endpoint';
  @override
  String get test => 'Prova';
  @override
  String get hide => 'Nascondi';
  @override
  String get show => 'Mostra';
}

// Path: settings.shortcuts
class _Translations$settings$shortcuts$it
    extends Translations$settings$shortcuts$en {
  _Translations$settings$shortcuts$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get navigate => 'naviga';
  @override
  String get staging => 'staging';
  @override
  String get branchesPrs => 'branch e PR';
  @override
  String get modifiers => 'modificatori';
  @override
  String get changes => 'Modifiche';
  @override
  String get history => 'Cronologia';
  @override
  String get branches => 'Branch';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Cambia (sempre)';
  @override
  String get search => 'Cerca';
  @override
  String get dismiss => 'Chiudi';
  @override
  String get refresh => 'Aggiorna';
  @override
  String get shortcuts => 'Scorciatoie';
  @override
  String get nextChange => 'Modifica successiva';
  @override
  String get prevChange => 'Modifica precedente';
  @override
  String get toggleLine => 'Attiva/disattiva riga';
  @override
  String get toggleHunk => 'Attiva/disattiva hunk';
  @override
  String get toggleFile => 'Attiva/disattiva file';
  @override
  String get pinContext => 'Fissa contesto';
  @override
  String get commit => 'Commit';
  @override
  String get acceptHint => 'Accetta suggerimento';
  @override
  String get undo => 'Annulla';
  @override
  String get navigateRow => 'Naviga';
  @override
  String get expand => 'Espandi';
  @override
  String get checkout => 'Checkout';
  @override
  String get approve => 'Approva';
  @override
  String get requestChanges => 'Richiedi modifiche';
  @override
  String get selectRange => 'Seleziona intervallo';
  @override
  String get extendedMenu => 'Menu esteso';
}

// Path: settings.toggles
class _Translations$settings$toggles$it
    extends Translations$settings$toggles$en {
  _Translations$settings$toggles$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get aiReadOnlyLabel => 'Modalità AI in sola lettura';
  @override
  String get aiReadOnlyDescription =>
      'Impedisce all\'AI di scrivere o mettere in stage modifiche automaticamente.';
  @override
  String get logoMotionLabel =>
      'Il logo si anima quando sei su un\'altra scheda';
  @override
  String get logoMotionDescriptionEnabled =>
      'È progettato per essere efficiente, non ferire i suoi sentimenti';
  @override
  String get logoMotionDescriptionDisabled => ':(';
  @override
  String get rememberWipLabel => 'Ricorda il lavoro in corso';
  @override
  String get rememberWipDescription =>
      'Mantieni le bozze di commit e la selezione dei file tra le sessioni.';
  @override
  String get stashCabinetLabel => 'L\'armadietto stash parte espanso';
  @override
  String get stashCabinetDescription =>
      'Mostra il cassetto dello schedario aperto per impostazione predefinita quando un repo ha delle mensole.';
  @override
  String get instantBlameLabel => 'Blame istantaneo al passaggio';
  @override
  String get instantBlameDescription =>
      'Salta il ritardo di 180ms prima che le info di blame compaiano su una riga del diff.';
  @override
  String get autoSelectLabel => 'Seleziona automaticamente le nuove modifiche';
  @override
  String get autoSelectDescription =>
      'I file appena tracciati o modificati vengono aggiunti automaticamente alla selezione del commit.';
  @override
  String get changeIdLabel => 'Scrivi header change-id';
  @override
  String get changeIdDescription =>
      'Aggiunge ai nuovi commit un header di identità change-id (la convenzione di Jujutsu, GitButler e Gerrit). Ogni commit viene riscritto una volta subito dopo la creazione.';
  @override
  String get fetchIssuesLabel =>
      'Recupera le issue online al caricamento dei branch';
  @override
  String get fetchIssuesDescription =>
      'Preleva in background i dettagli di PR e issue dal tuo provider git quando si apre la pagina dei branch.';
  @override
  String get hateAiLabel => 'Odio l\'AI';
  @override
  String get hateAiDescription =>
      'Bandisci tutte le funzioni basate su LLM. Logos continua a girare perché è solo matematica spettrale.';
}

// Path: settings.diffDiffability
class _Translations$settings$diffDiffability$it
    extends Translations$settings$diffDiffability$en {
  _Translations$settings$diffDiffability$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'diff-abilità del diff';
}

// Path: settings.modelSlots
class _Translations$settings$modelSlots$it
    extends Translations$settings$modelSlots$en {
  _Translations$settings$modelSlots$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get loadingProviders => 'Caricamento dei provider...';
  @override
  String get refreshingProviders =>
      'Aggiornamento della diagnostica dei provider...';
  @override
  String get routeDescription =>
      'Rinomina e instrada le configurazioni verso qualsiasi modello di provider rilevato.';
  @override
  String get loadingCategories => 'Caricamento delle categorie di modelli...';
  @override
  String get noOptions =>
      'Nessuna opzione di modello disponibile per ora. Rileva prima una CLI AI locale compatibile.';
  @override
  String get slotsAppearWhenAvailable =>
      'Le impostazioni degli slot dei modelli appariranno qui una volta disponibili i modelli dei provider.';
  @override
  String get effortDefault => 'predefinito';
  @override
  String get noModelsForSlot => 'Nessun modello rilevato per questo slot.';
  @override
  String viaProvider({required Object provider}) => 'tramite ${provider}';
  @override
  String get customModelId => 'id modello personalizzato';
}

// Path: settings.modelPicker
class _Translations$settings$modelPicker$it
    extends Translations$settings$modelPicker$en {
  _Translations$settings$modelPicker$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String noMatch({required Object query}) =>
      'nessun modello corrisponde a "${query}"';
  @override
  String get noModels => 'nessun modello disponibile';
  @override
  String get filterHint => 'filtra i modelli...';
  @override
  String get warming => 'riscaldamento…';
  @override
  String get detailsUnavailable => 'dettagli non disponibili';
  @override
  String get free => 'gratis';
}

// Path: settings.aiFeatures
class _Translations$settings$aiFeatures$it
    extends Translations$settings$aiFeatures$en {
  _Translations$settings$aiFeatures$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get commitDescription =>
      'Redige messaggi di commit dalle modifiche in stage usando le tue preferenze di struttura, voce e copertura.';
  @override
  String get reviewDescription =>
      'Rivedi l\'ambito del commit corrente prima di committare.';
  @override
  String get museDescription =>
      'Oracolo a tre fasi che fa brainstorming e poi sintetizza una direzione in avanti per il diff.';
}

// Path: settings.commitEditor
class _Translations$settings$commitEditor$it
    extends Translations$settings$commitEditor$en {
  _Translations$settings$commitEditor$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get styleGuide => 'Guida di stile';
  @override
  String get styleGuideHint =>
      'Opzionale. Voce / tono / divieti. Il formato sopra gestisce lo scheletro.';
}

// Path: settings.review
class _Translations$settings$review$it extends Translations$settings$review$en {
  _Translations$settings$review$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Note aggiuntive con cui rivedere';
  @override
  String get doubleCheckLabel => 'Doppio controllo della review';
  @override
  String get doubleCheckDescription =>
      'Esegue una seconda passata di verifica prima di mostrare il report finale.';
}

// Path: settings.museHint
class _Translations$settings$museHint$it
    extends Translations$settings$museHint$en {
  _Translations$settings$museHint$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get loose =>
      'qualcosa verso cui indirizzare con delicatezza? oggi l\'umore è gentile.';
  @override
  String get balanced => 'su cosa soffermarsi, cosa saltare. onesta, non dura.';
  @override
  String get strict =>
      'gli standard. i divieti. ciò che la muse non lascia passare.';
  @override
  String get paranoid =>
      'regola la lente. su quali frequenze dovrebbe vibrare il manifold?';
}

// Path: settings.museEditor
class _Translations$settings$museEditor$it
    extends Translations$settings$museEditor$en {
  _Translations$settings$museEditor$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Note aggiuntive per la muse';
}

// Path: settings.museStage
class _Translations$settings$museStage$it
    extends Translations$settings$museStage$en {
  _Translations$settings$museStage$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get brainstorm => 'BRAINSTORM';
  @override
  String get synthesize => 'SINTETIZZA';
  @override
  String get slot => 'slot';
  @override
  String get ideaCountLoose => '~12 idee';
  @override
  String get ideaCountBalanced => '~16 idee';
  @override
  String get ideaCountStrict => '~20 idee';
  @override
  String get ideaCountParanoid => '~24 idee';
  @override
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  guardrail: ${macro}';
}

// Path: settings.lensAxis
class _Translations$settings$lensAxis$it
    extends Translations$settings$lensAxis$en {
  _Translations$settings$lensAxis$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get folder => 'CARTELLA';
  @override
  String get history => 'CRONOLOGIA';
  @override
  String get far => 'LONTANO';
  @override
  String get near => 'VICINO';
}

// Path: settings.logosLens
class _Translations$settings$logosLens$it
    extends Translations$settings$logosLens$en {
  _Translations$settings$logosLens$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get moduleMap => 'mappa dei moduli';
  @override
  String get repoCenters => 'centri del repo';
  @override
  String get neighbors => 'vicini';
  @override
  String get toTouch => 'cosa toccare dopo';
  @override
  String get relevanceEngine => 'motore di rilevanza';
  @override
  String get description =>
      'legge come i file si muovono insieme attraverso struttura, cronologia e ritmo, così Manifold sa cosa conta, non solo cosa è cambiato.';
  @override
  String get withinReach => 'a portata';
  @override
  String get gate => 'soglia';
  @override
  String get nearest => 'più vicini';
  @override
  String get warming => 'riscaldamento';
  @override
  String get emptyOpenRepo => 'apri un repo per\nvedere la lente in azione';
  @override
  String get emptyNoFiles =>
      'nessun file a\nportata — trascina\nverso CRONOLOGIA';
}

// Path: settings.sortGuide
class _Translations$settings$sortGuide$it
    extends Translations$settings$sortGuide$en {
  _Translations$settings$sortGuide$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Guida all\'ordinamento delle modifiche';
  @override
  String get related =>
      'I file che cambiano insieme si raggruppano. Prima la questione; poi il contesto.';
  @override
  String get relatedInverted =>
      'Prima le modifiche isolate. I cluster strettamente accoppiati scendono in fondo.';
  @override
  String get alphabetical =>
      'Semplice A → Z per percorso. Senza distinzione di maiuscole, numeri ordinati in modo naturale.';
  @override
  String get alphabeticalInverted =>
      'Semplice Z → A per percorso. Senza distinzione di maiuscole, numeri ordinati in modo naturale.';
  @override
  String get impact =>
      'Prima emergono le modifiche più pesanti. Il churn è pesato; binari e nuovi file vengono promossi.';
  @override
  String get impactInverted =>
      'Prima emergono le modifiche più leggere. Vittorie rapide in cima; i lavori pesanti aspettano.';
  @override
  String get nearRelated => 'quasi correlate';
  @override
  String get alphabeticalShort => 'alfabetico';
  @override
  String get byImpact => 'per impatto';
  @override
  String get flipped => 'invertito';
  @override
  String get peek => 'sbircia';
}

// Path: settings.piggyback
class _Translations$settings$piggyback$it
    extends Translations$settings$piggyback$en {
  _Translations$settings$piggyback$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get apiModelsUse => 'I modelli API usano';
  @override
  String get codexNotDetected => 'codex non rilevato';
  @override
  String get dormant => 'DORMIENTE';
}

// Path: settings.diffStage
class _Translations$settings$diffStage$it
    extends Translations$settings$diffStage$en {
  _Translations$settings$diffStage$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get viewer => 'visualizzatore';
  @override
  String get media => 'media';
  @override
  String get binary => 'binario';
  @override
  String get hidden => 'nascosto';
}

// Path: settings.undoScope
class _Translations$settings$undoScope$it
    extends Translations$settings$undoScope$en {
  _Translations$settings$undoScope$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get destructiveActions => 'azioni distruttive';
  @override
  String get discards => 'scarti';
  @override
  String get commits => 'commit';
  @override
  String get commitPush => 'commit + push';
  @override
  String get all => 'tutto';
}

// Path: settings.undoWindow
class _Translations$settings$undoWindow$it
    extends Translations$settings$undoWindow$en {
  _Translations$settings$undoWindow$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Finestra di annullamento';
  @override
  String get off => 'Off';
  @override
  String descriptionInstant({required Object scope}) =>
      '${scope} si finalizzano all\'istante.';
  @override
  String descriptionDelayed({required Object seconds, required Object scope}) =>
      '${seconds}s prima che ${scope} si finalizzino.';
  @override
  String get cycleScopeTooltip =>
      'Clicca per scorrere l\'ambito · trascina anche su/giù sullo slider';
  @override
  String get resetTooltip =>
      'Reimposta ogni azione perché usi la finestra predefinita';
}

// Path: settings.guardrailPhrase
class _Translations$settings$guardrailPhrase$it
    extends Translations$settings$guardrailPhrase$en {
  _Translations$settings$guardrailPhrase$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get probablyFine => 'Probabilmente a posto vuol dire a posto';
  @override
  String get proper =>
      'Una lettura come si deve, logica, integrazione, pattern';
  @override
  String get lookAgain => 'Guarda di nuovo. Qualcosa potrebbe nascondersi';
  @override
  String get assumeWrong =>
      'Dai per scontato che qualcosa sia sbagliato. Trovalo';
}

// Path: settings.reviewGuideHint
class _Translations$settings$reviewGuideHint$it
    extends Translations$settings$reviewGuideHint$en {
  _Translations$settings$reviewGuideHint$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get focusHigh =>
      'es. Concentrati sulla logica di alto livello e sui bug principali. Sii breve e indulgente.';
  @override
  String get surfaceBugs =>
      'es. Fai emergere potenziali bug, incongruenze architetturali e fallimenti nei casi limite.';
  @override
  String get scrutinize =>
      'es. Esamina ogni riga per ottimizzazione, sicurezza e conformità ai pattern.';
  @override
  String get trustNothing =>
      'es. Non fidarti di niente. Metti in discussione ogni effetto collaterale. Tratta ogni riga come un potenziale fallimento.';
  @override
  String get optional =>
      'Indicazioni facoltative su cosa dovrebbe interessare alla review.';
}

// Path: settings.commitFormat
class _Translations$settings$commitFormat$it
    extends Translations$settings$commitFormat$en {
  _Translations$settings$commitFormat$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Formato';
  @override
  String get peek => 'sbircia';
  @override
  String get structure => 'Struttura';
  @override
  String get voice => 'Voce';
  @override
  String get coverage => 'Copertura';
  @override
  String get structureTitleBody => 'titolo + corpo';
  @override
  String get structureTitleOnly => 'solo titolo';
  @override
  String get structureFreeform => 'libero';
  @override
  String get voiceVerbLed => 'orientato all\'azione';
  @override
  String get voiceDescriptive => 'descrittivo';
  @override
  String get voiceNarrative => 'narrativo';
  @override
  String get coverageEssentials => 'l\'essenziale';
  @override
  String get coverageBalanced => 'bilanciato';
  @override
  String get coverageEverything => 'tutto';
}

// Path: settings.commitPreview
class _Translations$settings$commitPreview$it
    extends Translations$settings$commitPreview$en {
  _Translations$settings$commitPreview$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$it title =
      _Translations$settings$commitPreview$title$it._(_root);
  @override
  late final _Translations$settings$commitPreview$base$it base =
      _Translations$settings$commitPreview$base$it._(_root);
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$it
  balancedSuffix = _Translations$settings$commitPreview$balancedSuffix$it._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$it
  everythingSuffix = _Translations$settings$commitPreview$everythingSuffix$it._(
    _root,
  );
}

// Path: settings.externalTools
class _Translations$settings$externalTools$it
    extends Translations$settings$externalTools$en {
  _Translations$settings$externalTools$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Strumenti esterni';
  @override
  String get summary =>
      'Clic destro su un progetto nella barra laterale per aprirlo con uno di questi. Gli argomenti usano {path} per la cartella del progetto.';
  @override
  String get detecting => 'Rilevamento degli strumenti installati…';
  @override
  String get allPresetsAdded =>
      'Tutti i preset noti sono già stati aggiunti. Usa “+ Personalizzato” per aggiungerne altri.';
  @override
  String get noToolsConfigured =>
      'Ancora nessuno strumento configurato. Aggiungine uno sopra.';
  @override
  String get categoryAi => 'ai';
  @override
  String get categoryEditors => 'editor';
  @override
  String get categoryExplore => 'esplora';
  @override
  String get categoryOps => 'ops';
  @override
  String get categoryGitOps => 'git ops';
  @override
  String get nameHint => 'Nome';
  @override
  String get commandHint => 'comando';
  @override
  String get test => 'prova';
  @override
  String get removeTool => 'Rimuovi strumento';
  @override
  String get modeTerminal => 'terminale';
  @override
  String get modeDetached => 'distaccato';
}

// Path: settings.apiUsage
class _Translations$settings$apiUsage$it
    extends Translations$settings$apiUsage$en {
  _Translations$settings$apiUsage$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String thisMonth({required Object used, required Object limit}) =>
      '${used}${limit} questo mese';
}

// Path: settings.gitea
class _Translations$settings$gitea$it extends Translations$settings$gitea$en {
  _Translations$settings$gitea$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Token Gitea';
  @override
  String get hostHint => 'host';
  @override
  String get tokenHint => 'token';
  @override
  String get save => 'salva';
}

// Path: settings.wick
class _Translations$settings$wick$it extends Translations$settings$wick$en {
  _Translations$settings$wick$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get selectExecutable => 'Seleziona l\'eseguibile wick';
  @override
  String get connected => 'wick · connesso';
  @override
  String get pathToExecutable => 'wick · percorso all\'eseguibile';
  @override
  String get off => 'off';
  @override
  String get disableHint => 'Disattiva l\'integrazione wick';
  @override
  String get enableHint => 'Attiva l\'integrazione wick';
}

// Path: settings.integrations
class _Translations$settings$integrations$it
    extends Translations$settings$integrations$en {
  _Translations$settings$integrations$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => '& Integrazioni';
  @override
  String get alpha => 'alpha';
  @override
  String get planned => 'pianificato';
  @override
  String get lspComingSoon => 'lsp · in arrivo';
  @override
  String get alphaMathConnected => 'alpha-math · connesso';
  @override
  String get alphaMathComingSoon => 'alpha-math · in arrivo';
}

// Path: settings.reduceMotion
class _Translations$settings$reduceMotion$it
    extends Translations$settings$reduceMotion$en {
  _Translations$settings$reduceMotion$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Riduci il movimento';
  @override
  String get subtitleStill => 'Fermo… come il ghiaccio?';
  @override
  String get subtitleFlow => 'Scorri come l\'acqua.';
}

// Path: settings.resetQuit
class _Translations$settings$resetQuit$it
    extends Translations$settings$resetQuit$en {
  _Translations$settings$resetQuit$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get resetAndQuit => 'RESET ED ESCI';
  @override
  String get keepRepos => 'TIENI I REPO';
  @override
  String get wipeAll => 'CANCELLA TUTTO';
}

// Path: settings.diagnostics
class _Translations$settings$diagnostics$it
    extends Translations$settings$diagnostics$en {
  _Translations$settings$diagnostics$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get commandDiagnostics => 'Diagnostica dei comandi';
  @override
  String get networkFlowTelemetry => 'Telemetria del flusso di rete';
  @override
  String get clearSamples => 'Cancella campioni';
  @override
  String get clearMetrics => 'Cancella metriche';
  @override
  String get clearTimings => 'Cancella tempi';
  @override
  String get recalibrate => 'RICALIBRA';
  @override
  String get ok => 'ok';
  @override
  String get noCommandTimings =>
      'Ancora nessun tempo di comando catturato. Esegui azioni normali per popolare la diagnostica.';
  @override
  String get noBackendSamples =>
      'Ancora nessun campione di comando backend catturato. Esegui azioni git e impostazioni per popolare questo log.';
  @override
  String get noDiffSessions =>
      'Ancora nessuna sessione di rendering diff catturata. Apri e scorri i diff dei file per popolare questo pannello.';
  @override
  String get noUiSessions =>
      'Ancora nessuna sessione di tempi UI catturata. Apri i pannelli e naviga tra le rotte per popolare questo pannello.';
  @override
  String get recentOperations => 'Operazioni recenti';
  @override
  String get recentBackendOperations => 'Operazioni backend recenti';
  @override
  String get recentDiffSessions => 'Sessioni diff recenti';
  @override
  String get recentUiTimings => 'Tempi UI recenti';
  @override
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} comando unico',
        other: '${n} comandi unici',
      );
  @override
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} comando con ambito',
        other: '${n} comandi con ambito',
      );
  @override
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} evento strumentato',
        other: '${n} eventi strumentati',
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
    'comando',
    'p50',
    'affidabilità',
    'intervallo',
  ];
  @override
  List<String> get headersBackend => ['ambito', 'p50', 'p95', 'fallimenti'];
  @override
  List<String> get headersDiff => [
    'renderer',
    'primo paint',
    'frame p95',
    'raster p95',
    'jank',
  ];
  @override
  List<String> get headersUi => ['evento', 'p50', 'fallimenti', 'intervallo'];
}

// Path: settings.telemetry
class _Translations$settings$telemetry$it
    extends Translations$settings$telemetry$en {
  _Translations$settings$telemetry$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} campione',
        other: '${n} campioni',
      );
  @override
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} comando',
        other: '${n} comandi',
      );
  @override
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} sessione',
        other: '${n} sessioni',
      );
  @override
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} evento',
        other: '${n} eventi',
      );
  @override
  String stability({required Object pct}) => '${pct}% stabilità';
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
class _Translations$settings$flowEngine$it
    extends Translations$settings$flowEngine$en {
  _Translations$settings$flowEngine$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get executionFlow => 'flusso di esecuzione';
  @override
  String get description =>
      'simula oscillatori sul codice. fa emergere percorsi di esecuzione fragili prima che si cristallizzino in bug.';
  @override
  String get idle => 'inattivo';
  @override
  String get emptyOpenRepo => 'apri un repo per\nvedere l\'analisi del flusso';
  @override
  String get scanning => 'scansione';
  @override
  String get analysing => 'analisi dei file\nnella lente…';
  @override
  String get fragility => 'fragilità';
  @override
  String get findings => 'riscontri';
  @override
  String get gap => 'vuoto';
  @override
  String get clean => 'pulito';
  @override
  String get severity => 'gravità';
  @override
  String get critical => 'critico';
  @override
  String get warn => 'avviso';
  @override
  String get info => 'info';
}

// Path: settings.museStrands
class _Translations$settings$museStrands$it
    extends Translations$settings$museStrands$en {
  _Translations$settings$museStrands$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get spark =>
      'scintilla d\'ispirazione · il passo immediatamente successivo';
  @override
  String get current => 'corrente nell\'acqua · estensioni al presente';
  @override
  String get horizon =>
      'guarda oltre l\'orizzonte · direzioni verso cui tendere';
  @override
  String get fever => 'risveglio da un sogno febbrile · provocazioni';
  @override
  String get echo => 'un\'eco attraverso il canyon · analoghi altrove';
  @override
  String get vertigo =>
      'vertigine sull\'orlo del precipizio · rischi adiacenti';
  @override
  String get ghost => 'il fantasma di ciò che è stato · contesto storico';
  @override
  String get mirror => 'uno specchio sull\'acqua ferma · inversioni';
}

// Path: settings.cliPiggyback
class _Translations$settings$cliPiggyback$it
    extends Translations$settings$cliPiggyback$en {
  _Translations$settings$cliPiggyback$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Piggybacking CLI';
  @override
  String get clearCacheLabel => 'Cancella cache';
  @override
  String get clearCacheTooltip =>
      'Cancella i modelli in cache e riesegui il probe. Rimuove quelli che un provider ha abbandonato.';
  @override
  String get refreshLabel => 'Aggiorna provider';
  @override
  String get refreshTooltip => 'Riesegui subito il probe di ogni provider.';
  @override
  String get body =>
      'Invia direttamente i messaggi dell\'interfaccia ai binari dei provider locali.';
  @override
  String get cliTimeoutLabel => 'Timeout per esecuzione';
  @override
  String get cliTimeoutUnitMinutes => 'minuti';
  @override
  String get cliTimeoutUnitMinute => 'minuto';
  @override
  String get forceStopLabel => 'Arresta tutte le sessioni';
  @override
  String get forceStopTooltip =>
      'Forza la chiusura di ogni esecuzione CLI in corso.';
  @override
  String get forceStopConfirmTitle => 'Arrestare le sessioni CLI in corso?';
  @override
  String forceStopConfirmBody({required Object count}) =>
      'Questo forza la chiusura di ${count} esecuzioni CLI in corso. Il loro output andrà perso.';
  @override
  String get forceStopConfirmAction => 'Arresta tutte';
  @override
  String get forceStopNoneRunning => 'Nessuna sessione CLI in corso';
  @override
  String get forceStopRecordError =>
      'Arrestato — le sessioni CLI sono state chiuse forzatamente.';
}

// Path: settings.header
class _Translations$settings$header$it extends Translations$settings$header$en {
  _Translations$settings$header$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Preferenze del workspace';
  @override
  String get subtitle =>
      'Configura l\'estetica globale, le dinamiche dell\'interfaccia e le protezioni operative principali per l\'intero workspace.';
  @override
  String get releaseNotesTooltip => 'Note di rilascio';
  @override
  String get replayOnboardingTooltip => 'Ripeti l\'onboarding';
}

// Path: settings.diagnosticsPanel
class _Translations$settings$diagnosticsPanel$it
    extends Translations$settings$diagnosticsPanel$en {
  _Translations$settings$diagnosticsPanel$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Diagnostica delle performance';
  @override
  String get copyTrace => 'Copia traccia';
  @override
  String get offenderRanking => 'Classifica dei colpevoli';
  @override
  String get offenderRankingSubtitle => 'Cause di latenza tra gli stream.';
  @override
  String get noOffenders =>
      'Ancora nessuna classifica dei colpevoli. Cattura attività di diagnostica per popolare questa lista.';
}

// Path: settings.release
class _Translations$settings$release$it
    extends Translations$settings$release$en {
  _Translations$settings$release$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Distribuzione delle release';
  @override
  String get summary => 'Impostazioni relative agli aggiornamenti.';
  @override
  String get deploymentChannel => 'CANALE DI DISTRIBUZIONE';
  @override
  String get captureCrashDiagnostics => 'Cattura diagnostica dei crash';
  @override
  String get comingSoon => 'In arrivo.';
  @override
  String get checking => 'VERIFICA…';
  @override
  String get pollForUpdates => 'CERCA AGGIORNAMENTI';
}

// Path: settings.providerStatus
class _Translations$settings$providerStatus$it
    extends Translations$settings$providerStatus$en {
  _Translations$settings$providerStatus$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get detecting => 'Rilevamento...';
  @override
  String get ready => 'Pronto';
  @override
  String get notDetected => 'Non rilevato';
  @override
  String configured({required Object count}) => '${count} configurati';
  @override
  String get notConfigured => 'Non configurato';
  @override
  String get cliManaged => 'Gestito da CLI';
  @override
  String get connected => 'Connesso';
  @override
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} modello',
        other: '${n} modelli',
      );
  @override
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} provider',
        other: '${n} provider',
      );
}

// Path: settings.meridiem
class _Translations$settings$meridiem$it
    extends Translations$settings$meridiem$en {
  _Translations$settings$meridiem$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get am => 'AM';
  @override
  String get pm => 'PM';
}

// Path: settings.offenders
class _Translations$settings$offenders$it
    extends Translations$settings$offenders$en {
  _Translations$settings$offenders$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get commandStream => 'Comando';
  @override
  String get diffStream => 'Rendering diff';
  @override
  String get uiStream => 'Tempi UI';
  @override
  String rendererName({required Object mode}) => 'renderer ${mode}';
  @override
  String latencyFailMetric({required Object p95, required Object fail}) =>
      '${p95}ms p95 | ${fail}% fallimenti';
  @override
  String jankFrameMetric({required Object jank, required Object frame}) =>
      '${jank}% jank | ${frame}ms frame p95';
  @override
  String inStream({required Object stream}) => 'in ${stream}';
}

// Path: sync.actions
class _Translations$sync$actions$it extends Translations$sync$actions$en {
  _Translations$sync$actions$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get syncLabel => 'Sync';
  @override
  String get syncOpenRepoDetail =>
      'Apri un repository per gestire le operazioni di push e pull.';
  @override
  String get detachedHeadLabel => 'HEAD scollegato';
  @override
  String get detachedHeadDetail =>
      'Fai il checkout di un branch prima di push o pull.';
  @override
  String get publishBranchLabel => 'Pubblica branch';
  @override
  String publishBranchDetail({required Object branch}) =>
      'Fai il push di ${branch} e imposta il suo branch di tracking upstream.';
  @override
  String get publishButtonLabel => 'Pubblica';
  @override
  String get syncBranchLabel => 'Sincronizza branch';
  @override
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => 'Fai pull di ${behindCount} con rebase, poi push di ${aheadCount}.';
  @override
  String get syncBranchButtonLabel => 'Pull (rebase) poi push';
  @override
  String get pushBranchLabel => 'Push branch';
  @override
  String pushBranchDetail({required Object count, required Object upstream}) =>
      'Fai il push di ${count} verso ${upstream}.';
  @override
  String get pushBranchButtonLabel => 'Push dei commit';
  @override
  String get pullUpdatesLabel => 'Pull aggiornamenti';
  @override
  String pullUpdatesDetail({required Object count, required Object upstream}) =>
      'Fai il pull di ${count} da ${upstream}.';
  @override
  String syncUpToDateDetail({required Object upstream}) =>
      'Fetch da ${upstream} e aggiorna lo stato upstream.';
}

// Path: sync.panel
class _Translations$sync$panel$it extends Translations$sync$panel$en {
  _Translations$sync$panel$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Caricamento stato remoto';
  @override
  String get loadingMessage =>
      'Verifica delle informazioni di tracking del branch.';
  @override
  String get remoteStatusUnavailable => 'Stato remoto non disponibile';
  @override
  String get noUpstream => 'nessun upstream';
  @override
  String get aheadLabel => 'Avanti';
  @override
  String get behindLabel => 'Indietro';
  @override
  String get treeLabel => 'Albero';
  @override
  String get runningSync => 'Sync in corso…';
  @override
  String get fetching => 'Fetch in corso…';
  @override
  String get fetchOnly => 'Solo fetch';
  @override
  String get syncFailed => 'Sync non riuscito';
  @override
  String get forcePushRecoveryLabel => 'Force push (con lease)';
  @override
  String get conflictsToResolveTitle => 'Conflitti da risolvere';
  @override
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} da risolvere: ${list}';
  @override
  String get resolveConflicts => 'Risolvi conflitti';
  @override
  String get workingEllipsis => 'In lavorazione…';
  @override
  String lastActivity({required Object operation}) =>
      'Ultima attività: ${operation}';
  @override
  String get noOutput => 'Nessun output.';
  @override
  String resolvedConflicts({required Object count}) => 'Risolti ${count}.';
  @override
  String get cancelledUnchanged => 'Annullato, albero di lavoro invariato.';
  @override
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) =>
      '${count} hanno modifiche non committate, committale prima per il rebase-sync (${list}).';
  @override
  String noUpstreamForForcePush({required Object branch}) =>
      'Force push impossibile: nessun upstream configurato per "${branch}".';
}

// Path: sync.forcePush
class _Translations$sync$forcePush$it extends Translations$sync$forcePush$en {
  _Translations$sync$forcePush$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get confirmTitle => 'Force push (con lease)?';
  @override
  String target({required Object remote, required Object branch}) =>
      'Destinazione: ${remote}/${branch}';
  @override
  String get warning =>
      'Questo riscrive il branch remoto con la tua cronologia locale. Con lease si interrompe se qualcuno ha fatto push sul remoto dopo il tuo ultimo fetch, ma le modifiche già fetchate verranno comunque sovrascritte. Usalo solo quando hai voluto un rebase o un amend che ha fatto divergere il branch.';
  @override
  String get confirmButton => 'Force push';
}

// Path: xray.board
class _Translations$xray$board$it extends Translations$xray$board$en {
  _Translations$xray$board$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get movesWithModule => 'si muove con un altro modulo';
  @override
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} reviewer',
        other: '${n} reviewer',
      );
  @override
  String get territory => 'Territorio';
  @override
  String get unreviewed => 'non revisionato';
}

// Path: xray.cadence
class _Translations$xray$cadence$it extends Translations$xray$cadence$en {
  _Translations$xray$cadence$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '${sum} commit · ${days} giorni\n${lines}';
  @override
  String burstTooltipSingle({required Object n, required Object label}) =>
      '${n} commit il ${label}';
  @override
  String gapTooltip({required Object n, required Object label}) =>
      'pausa di ${n} giorni · ${label}';
  @override
  String reflogTooltip({required Object n, required Object label}) =>
      '${n} eventi reflog il ${label}';
}

// Path: xray.cards
class _Translations$xray$cards$it extends Translations$xray$cards$en {
  _Translations$xray$cards$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$cards$branchModel$it branchModel =
      _Translations$xray$cards$branchModel$it._(_root);
  @override
  late final _Translations$xray$cards$bursty$it bursty =
      _Translations$xray$cards$bursty$it._(_root);
  @override
  late final _Translations$xray$cards$hiddenRefs$it hiddenRefs =
      _Translations$xray$cards$hiddenRefs$it._(_root);
  @override
  late final _Translations$xray$cards$keystone$it keystone =
      _Translations$xray$cards$keystone$it._(_root);
  @override
  late final _Translations$xray$cards$machineHistory$it machineHistory =
      _Translations$xray$cards$machineHistory$it._(_root);
  @override
  late final _Translations$xray$cards$migration$it migration =
      _Translations$xray$cards$migration$it._(_root);
  @override
  late final _Translations$xray$cards$narrowHotspot$it narrowHotspot =
      _Translations$xray$cards$narrowHotspot$it._(_root);
  @override
  late final _Translations$xray$cards$noTags$it noTags =
      _Translations$xray$cards$noTags$it._(_root);
  @override
  late final _Translations$xray$cards$reflog$it reflog =
      _Translations$xray$cards$reflog$it._(_root);
  @override
  late final _Translations$xray$cards$singleOwner$it singleOwner =
      _Translations$xray$cards$singleOwner$it._(_root);
}

// Path: xray.cardTitle
class _Translations$xray$cardTitle$it extends Translations$xray$cardTitle$en {
  _Translations$xray$cardTitle$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get branches => 'branch';
  @override
  String get bursty => 'a raffiche';
  @override
  String get hiddenRefs => 'ref nascoste';
  @override
  String get machineHeavy => 'carico di macchina';
  @override
  String get migration => 'migrazione';
  @override
  String get narrowHotspot => 'hotspot ristretto';
  @override
  String get noTags => 'nessun tag';
  @override
  String get reflog => 'reflog';
  @override
  String get singleOwner => 'proprietario unico';
}

// Path: xray.grain
class _Translations$xray$grain$it extends Translations$xray$grain$en {
  _Translations$xray$grain$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get coarsest => 'più grossolana — moduli di primo livello';
  @override
  String get finest => 'grana più fine';
  @override
  String get mid => 'grana media';
  @override
  String get oneCharacteristic => 'una scala caratteristica';
}

// Path: xray.header
class _Translations$xray$header$it extends Translations$xray$header$en {
  _Translations$xray$header$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get dirtyBadge => 'sporco';
  @override
  String get machineChip => 'macchina';
  @override
  String get refresh => 'Aggiorna';
  @override
  String get refreshing => 'Aggiornamento...';
  @override
  String get title => 'X-Ray repo';
}

// Path: xray.hotspot
class _Translations$xray$hotspot$it extends Translations$xray$hotspot$en {
  _Translations$xray$hotspot$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get clusterPeers => 'vicini del cluster';
  @override
  String get coChangers => 'co-modificatori';
  @override
  String get keystone => 'pietra angolare';
  @override
  String keystoneScore({required Object score}) =>
      'pietra angolare  φ=${score}';
}

// Path: xray.inspector
class _Translations$xray$inspector$it extends Translations$xray$inspector$en {
  _Translations$xray$inspector$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get branchLabel => 'branch';
  @override
  String commitsHumanMachine({required Object n}) => 'umani · ${n} macchina';
  @override
  String get commitsLabel => 'commit';
  @override
  String get confidenceLabel => 'confidenza';
  @override
  String get curlLabel => 'curl';
  @override
  String get engineSection => 'motore';
  @override
  String get gradientLabel => 'gradiente';
  @override
  String get harmonicLabel => 'armonico';
  @override
  String get headLabel => 'head';
  @override
  String get hiddenRefsLabel => 'ref nascoste';
  @override
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} merge',
        other: '${n} merge',
      );
  @override
  String get noTags => 'nessun tag';
  @override
  String get notesLabel => 'note';
  @override
  String get openCommit => 'Apri commit';
  @override
  String get pathLabel => 'percorso';
  @override
  String remoteCount({required Object n}) => '${n} remoti';
  @override
  String get renamesLabel => 'rinomine';
  @override
  String scannedAt({required Object time}) => 'scansionato ${time}';
  @override
  String selectedCount({required Object n}) => '${n} selezionati';
  @override
  String get shapeLinear => 'lineare';
  @override
  String get shapeMergeHeavy => 'carico di merge';
  @override
  String get shapeMostlyLinear => 'quasi lineare';
  @override
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} stash',
        other: '${n} stash',
      );
  @override
  String get stressLabel => 'stress';
  @override
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} tag',
        other: '${n} tag',
      );
  @override
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} worktree',
        other: '${n} worktree',
      );
}

// Path: xray.loadingCard
class _Translations$xray$loadingCard$it
    extends Translations$xray$loadingCard$en {
  _Translations$xray$loadingCard$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get buildingMessage =>
      'Sondaggio di cronologia Git, ref, cadenza e hotspot.';
  @override
  String get buildingTitle => 'Costruzione della X-Ray repo';
  @override
  String get idleMessage =>
      'Riapri il pannello per sondare il repository corrente.';
  @override
  String get idleTitle => 'X-Ray repo';
  @override
  String get unavailableTitle => 'X-Ray repo non disponibile';
}

// Path: xray.metabolism
class _Translations$xray$metabolism$it extends Translations$xray$metabolism$en {
  _Translations$xray$metabolism$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String halfLife({required Object n}) => 'emivita ${n}g';
}

// Path: xray.multi
class _Translations$xray$multi$it extends Translations$xray$multi$en {
  _Translations$xray$multi$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} cluster',
        other: '${n} cluster',
      );
  @override
  String clusterSingle({required Object id}) => 'cluster ${id}';
  @override
  String couplingSuffix({required Object parts}) => 'coupling ${parts}';
  @override
  String externalCount({required Object n}) => '${n} esterni';
  @override
  String mutualCount({required Object n}) => '${n} reciproci';
}

// Path: xray.recency
class _Translations$xray$recency$it extends Translations$xray$recency$en {
  _Translations$xray$recency$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String days({required Object n}) => '${n}g';
  @override
  String months({required Object n}) => '${n}mes';
  @override
  String get today => 'oggi';
  @override
  String weeks({required Object n}) => '${n}sett';
  @override
  String years({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n}a',
        other: '${n}a',
      );
}

// Path: xray.rings
class _Translations$xray$rings$it extends Translations$xray$rings$en {
  _Translations$xray$rings$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get hintOneBlended => 'una struttura fusa';
  @override
  String get hintSelfSimilar => 'auto-simile';
  @override
  String get oneBlendedBody =>
      'Una struttura fusa — nessuna scala di moduli separabile si risolve ancora.';
  @override
  String get overHistory => 'Nel corso della cronologia';
  @override
  String get parts => 'parti';
  @override
  String get readingHint => 'lettura struttura…';
  @override
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} scala',
        other: '${n} scale',
      );
  @override
  String get scaleDissolved => 'una scala strutturale si è dissolta';
  @override
  String get scaleEmerged => 'è emersa una scala strutturale';
  @override
  String get scaleSpectrum => 'spettro delle scale';
  @override
  String get selfSimilarBody =>
      'Auto-simile — la struttura si ripete tra le scale, senza un unico livello caratteristico.';
  @override
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} spostamento nella cronologia',
        other: '${n} spostamenti nella cronologia',
      );
  @override
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} spostamento strutturale',
        other: '${n} spostamenti strutturali',
      );
  @override
  String get title => 'Anelli di crescita';
  @override
  String get unavailable => 'non disponibile';
}

// Path: xray.stats
class _Translations$xray$stats$it extends Translations$xray$stats$en {
  _Translations$xray$stats$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get alive => 'vivo';
  @override
  String get files => 'file';
  @override
  String get lastTouched => 'ultimo tocco';
  @override
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'proprietario',
        other: 'proprietari',
      );
  @override
  String get touches => 'tocchi';
}

// Path: xray.stratumLabel
class _Translations$xray$stratumLabel$it
    extends Translations$xray$stratumLabel$en {
  _Translations$xray$stratumLabel$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'corrente';
  @override
  String get legacy => 'legacy';
  @override
  String get zone => 'zona repo';
}

// Path: xray.summary
class _Translations$xray$summary$it extends Translations$xray$summary$en {
  _Translations$xray$summary$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String analysisFailed({required Object error}) =>
      'Analisi non riuscita: ${error}';
  @override
  String get analyze => 'Analizza';
  @override
  String get copied => 'Riepilogo copiato negli appunti.';
  @override
  String get directionHint => 'direzione';
  @override
  String get download => 'Scarica';
  @override
  String get emptyState =>
      'Avvia l\'analisi Logos per mappare la struttura e le regioni di questo repository.\n(tw: ciofeca adesso)';
  @override
  String get exit => 'Esci';
  @override
  String get generating => 'Lettura del repo e clustering delle feature…';
  @override
  String get noModel => 'Nessun modello AI configurato.';
  @override
  String get noModelConfigured => 'nessun modello AI configurato';
  @override
  String presentWith({required Object label}) => 'presenta con ${label}';
  @override
  String presentingWith({required Object label}) =>
      'presentazione con ${label}…';
  @override
  String get reanalyze => 'Rianalizza';
  @override
  String get saveDialogTitle => 'Salva il riepilogo del repository';
  @override
  String saveFailed({required Object error}) =>
      'Salvataggio non riuscito: ${error}';
  @override
  String get savePresentationDialogTitle => 'Salva la presentazione';
  @override
  String savedTo({required Object path}) => 'Salvato in ${path}';
}

// Path: xray.tabs
class _Translations$xray$tabs$it extends Translations$xray$tabs$en {
  _Translations$xray$tabs$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get map => 'Mappa';
  @override
  String get signals => 'Segnali';
  @override
  String get summary => 'Riepilogo';
  @override
  String get time => 'Tempo';
}

// Path: xray.trajectory
class _Translations$xray$trajectory$it extends Translations$xray$trajectory$en {
  _Translations$xray$trajectory$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get connectivity => 'connettività';
  @override
  String events({required Object n}) => '${n} eventi';
  @override
  String get openInOrrery => 'Apri nell\'Orrery';
  @override
  String get readingHint => 'lettura cronologia…';
  @override
  String snapshots({required Object n}) => '${n} snapshot';
  @override
  String get steady =>
      'Costante — nessun evento strutturale in questa finestra.';
  @override
  String get title => 'Traiettoria strutturale';
}

// Path: xray.verdict
class _Translations$xray$verdict$it extends Translations$xray$verdict$en {
  _Translations$xray$verdict$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String canonical({required Object pct}) => '${pct}% canonico';
  @override
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · ${canonical}% canonico · ${decisive}% decisivo';
}

// Path: changes.mergeEditor.trust
class _Translations$changes$mergeEditor$trust$it
    extends Translations$changes$mergeEditor$trust$en {
  _Translations$changes$mergeEditor$trust$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get manual => 'manuale';
  @override
  String get safe => 'sicuro';
  @override
  String get guided => 'guidato';
  @override
  String get assisted => 'assistito';
  @override
  String get full => 'pieno';
  @override
  String label({required Object label}) => 'fiducia: ${label}';
}

// Path: changes.mergeEditor.keyHints
class _Translations$changes$mergeEditor$keyHints$it
    extends Translations$changes$mergeEditor$keyHints$en {
  _Translations$changes$mergeEditor$keyHints$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get accept => 'accetta';
  @override
  String get other => 'altro';
  @override
  String get both => 'entrambi';
  @override
  String get navigate => 'naviga';
  @override
  String get jumpNext => 'salta al prossimo';
}

// Path: changes.mergeFlow.op
class _Translations$changes$mergeFlow$op$it
    extends Translations$changes$mergeFlow$op$en {
  _Translations$changes$mergeFlow$op$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'merge';
  @override
  String get cherryPick => 'cherry-pick';
  @override
  String get revert => 'revert';
  @override
  String get resolve => 'risolvi';
  @override
  String get switchOp => 'cambia';
  @override
  String get pull => 'pull';
  @override
  String get rebase => 'rebase';
  @override
  String rebaseOnto({required Object branch, required Object base}) =>
      'rebase di ${branch} su ${base}';
}

// Path: diff.pinned.tempo
class _Translations$diff$pinned$tempo$it
    extends Translations$diff$pinned$tempo$en {
  _Translations$diff$pinned$tempo$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get hotOwnerLane =>
      'Movimento recente con un proprietario forte nelle vicinanze.';
  @override
  String get activeSeam => 'Movimento recente da più mani nelle vicinanze.';
  @override
  String get stableOwnerLane =>
      'Corsia di lunga data con un unico proprietario dominante.';
  @override
  String get sharedLongLivedSeam =>
      'Giunzione condivisa che si è accumulata nel tempo.';
  @override
  String get sharedLane =>
      'Corsia condivisa senza un singolo proprietario dominante.';
  @override
  String get resolving =>
      'La cronologia si sta ancora definendo attorno a questa riga.';
}

// Path: diff.pinned.tone
class _Translations$diff$pinned$tone$it
    extends Translations$diff$pinned$tone$en {
  _Translations$diff$pinned$tone$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get hot => 'Caldo';
  @override
  String get novel => 'Nuovo';
  @override
  String get contested => 'Conteso';
  @override
  String get spreading => 'In diffusione';
  @override
  String get stable => 'Stabile';
}

// Path: diff.pinned.summary
class _Translations$diff$pinned$summary$it
    extends Translations$diff$pinned$summary$en {
  _Translations$diff$pinned$summary$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String livesIn({required Object concept}) => 'Vive in ${concept}';
  @override
  String get sitsInLocalSeam => 'Si trova in una giunzione locale';
  @override
  String workedMostlyBy({required Object owner}) =>
      'lavorato per lo più da ${owner} nelle vicinanze';
  @override
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'riecheggia in ${n} altro punto',
        other: 'riecheggia in ${n} altri punti',
      );
  @override
  String inspectNext({required Object path, required Object detail}) =>
      'ispeziona ${path} dopo${detail}';
  @override
  String inspectDetail({required Object reason}) => ' (${reason})';
}

// Path: diff.pinned.tightness
class _Translations$diff$pinned$tightness$it
    extends Translations$diff$pinned$tightness$en {
  _Translations$diff$pinned$tightness$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get tight => 'aderenza stretta';
  @override
  String get close => 'aderenza vicina';
  @override
  String get loose => 'aderenza lasca';
}

// Path: diff.pinned.witness
class _Translations$diff$pinned$witness$it
    extends Translations$diff$pinned$witness$en {
  _Translations$diff$pinned$witness$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String nearbySupport({required Object label}) =>
      'Supporto nelle vicinanze · ${label}';
  @override
  String localizedMove({required Object label}) =>
      'Movimento localizzato · ${label}';
  @override
  String surprisingMove({required Object label}) =>
      'Movimento sorprendente · ${label}';
}

// Path: diff.pinned.integrity
class _Translations$diff$pinned$integrity$it
    extends Translations$diff$pinned$integrity$en {
  _Translations$diff$pinned$integrity$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get stableStructure => 'Struttura stabile';
  @override
  String get conflictingSignals => 'Segnali contrastanti';
  @override
  String get novelShape => 'Forma nuova';
}

// Path: diff.pinned.related
class _Translations$diff$pinned$related$it
    extends Translations$diff$pinned$related$en {
  _Translations$diff$pinned$related$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get testMirror => 'Specchio di test';
  @override
  String get semanticHistorySibling => 'Fratello semantico + cronologia';
  @override
  String get recentCoChange => 'Co-change recente';
  @override
  String get semanticSibling => 'Fratello semantico';
  @override
  String get relatedStructure => 'Struttura correlata';
  @override
  String get tightlyBound => 'strettamente legato';
  @override
  String get orbiting => 'in orbita';
  @override
  String get weaklyCoupled => 'debolmente accoppiato';
  @override
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class _Translations$diff$pinned$axis$it
    extends Translations$diff$pinned$axis$en {
  _Translations$diff$pinned$axis$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get historyTrail => 'scia della cronologia';
  @override
  String get testMirrorLane => 'corsia specchio di test';
  @override
  String get structuralLane => 'corsia strutturale';
  @override
  String get semanticNeighbourhood => 'vicinato semantico';
}

// Path: history.commitLede.semantics
class _Translations$history$commitLede$semantics$it
    extends Translations$history$commitLede$semantics$en {
  _Translations$history$commitLede$semantics$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get importanceHigh => 'alta importanza';
  @override
  String get importanceModerate => 'importanza moderata';
  @override
  String get mostlyAdditions => 'per lo più aggiunte';
  @override
  String get mostlyDeletions => 'per lo più eliminazioni';
  @override
  String get tightlyCoupled => 'file strettamente accoppiati';
  @override
  String get overlapsWorkingTree => 'si sovrappone al tuo albero di lavoro';
}

// Path: onboarding.repo.doors
class _Translations$onboarding$repo$doors$it
    extends Translations$onboarding$repo$doors$en {
  _Translations$onboarding$repo$doors$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$repo$doors$open$it open =
      _Translations$onboarding$repo$doors$open$it._(_root);
  @override
  late final _Translations$onboarding$repo$doors$clone$it clone =
      _Translations$onboarding$repo$doors$clone$it._(_root);
  @override
  late final _Translations$onboarding$repo$doors$create$it create =
      _Translations$onboarding$repo$doors$create$it._(_root);
}

// Path: onboarding.repo.cloneForm
class _Translations$onboarding$repo$cloneForm$it
    extends Translations$onboarding$repo$cloneForm$en {
  _Translations$onboarding$repo$cloneForm$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Clona da URL';
  @override
  String get urlLabel => 'URL del repository';
  @override
  String get targetLabel => 'Cartella di destinazione';
  @override
  String get browse => 'Sfoglia…';
  @override
  String get clone => 'Clona';
  @override
  String get cloning => 'Clonazione…';
}

// Path: onboarding.repo.pickers
class _Translations$onboarding$repo$pickers$it
    extends Translations$onboarding$repo$pickers$en {
  _Translations$onboarding$repo$pickers$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get openRepository => 'Apri repository';
  @override
  String get createRepository => 'Crea repository';
  @override
  String get cloneTarget => 'Destinazione clone';
}

// Path: onboarding.repo.errors
class _Translations$onboarding$repo$errors$it
    extends Translations$onboarding$repo$errors$en {
  _Translations$onboarding$repo$errors$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get urlAndTargetRequired =>
      'URL e percorso di destinazione richiesti.';
  @override
  String get createFailed => 'Creazione del repository non riuscita.';
  @override
  String get cloneFailed => 'Clonazione del repository non riuscita.';
}

// Path: onboarding.preview.panels
class _Translations$onboarding$preview$panels$it
    extends Translations$onboarding$preview$panels$en {
  _Translations$onboarding$preview$panels$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get xray => 'X-Ray repo';
  @override
  String get settings => 'impostazioni';
}

// Path: onboarding.preview.sidebar
class _Translations$onboarding$preview$sidebar$it
    extends Translations$onboarding$preview$sidebar$en {
  _Translations$onboarding$preview$sidebar$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get projectsHeader => 'Progetti';
}

// Path: onboarding.preview.changes
class _Translations$onboarding$preview$changes$it
    extends Translations$onboarding$preview$changes$en {
  _Translations$onboarding$preview$changes$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String filesStagedCount({required Object staged, required Object total}) =>
      '${staged} di ${total} file';
  @override
  String stagedCount({required Object n}) => '${n} in stage';
  @override
  String get commitMessageHint => 'Messaggio di commit…';
  @override
  String get commitAndPush => 'Committa e push';
}

// Path: onboarding.preview.history
class _Translations$onboarding$preview$history$it
    extends Translations$onboarding$preview$history$en {
  _Translations$onboarding$preview$history$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'Cronologia';
  @override
  String get viewingLast => 'ultimi 20 commit';
  @override
  String get inFlight => 'IN VOLO';
  @override
  String get you => 'tu';
  @override
  String get commit1 => 'insegna alla volpe ad annusare prima di inghiottire';
  @override
  String get commit2 => 'ambra: trattieni il profumo per la notte';
  @override
  String get commit3 => 'ritira il cavolo a favore di ambra + spina';
  @override
  String get commit4 => 'la spina sorveglia il cancello';
}

// Path: onboarding.preview.branches
class _Translations$onboarding$preview$branches$it
    extends Translations$onboarding$preview$branches$en {
  _Translations$onboarding$preview$branches$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get lensBranches => 'BRANCH';
  @override
  String get lensPRs => 'PR';
  @override
  String get absorbed => 'assorbito';
  @override
  String get desk => 'Desk';
  @override
  String get head => 'HEAD';
  @override
  String tracking({required Object ref}) => '→ tracking: ${ref}';
}

// Path: onboarding.preview.diff
class _Translations$onboarding$preview$diff$it
    extends Translations$onboarding$preview$diff$en {
  _Translations$onboarding$preview$diff$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get readmeTagline => 'Il tuo Git client personale.';
}

// Path: releaseNotes.about.whyFlutter
class _Translations$releaseNotes$about$whyFlutter$it
    extends Translations$releaseNotes$about$whyFlutter$en {
  _Translations$releaseNotes$about$whyFlutter$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'PERCHÉ FLUTTER?';
  @override
  String get body =>
      'La prima versione di questo era un\'app Tauri (Rust + TypeScript). Sapevo già che sembrava lenta. Poi ho beccato uno streamer dire la stessa cosa in una live che di solito non guardo, e quella è stata la spinta a cambiare finalmente. Lui non ha suggerito Flutter; tutt\'altro. Dart l\'ho trovato da solo, ho buttato giù un prototipo, e l\'avvio è passato da circa 15 secondi a meno di uno. Come il giorno e la notte. Addio era Tauri.\n\nLa pipeline di rendering di Flutter è più vicina a un motore di gioco che a un DOM, e per un\'app desktop dove la UI è il prodotto questo è tutto. Dart si è rivelato anche un linguaggio davvero valido. La matematica dietro il motore spettrale è stata prototipata prima in Rust, quindi quel lavoro si è trasferito senza problemi.\n\nFlutter è cross-platform di default, il che è ottimo, ma è googloso di natura, quindi ci sono un po\' di stranezze.';
}

// Path: releaseNotes.about.spectralEngine
class _Translations$releaseNotes$about$spectralEngine$it
    extends Translations$releaseNotes$about$spectralEngine$en {
  _Translations$releaseNotes$about$spectralEngine$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'COS\'È IL MOTORE SPETTRALE?';
  @override
  String get body =>
      'Ogni volta che fai un commit, i file che modifichi insieme formano schemi nel tempo. Il motore spettrale legge il tuo grafo dei commit e scompone questi schemi di co-change in segnali: quali file sono accoppiati, quanto strettamente, e che ruolo strutturale hanno nel repo. In pratica analisi spettrale della tua cronologia di sviluppo. In un git client. Di proposito.\n\nLa matematica è nuova, quindi la tratto come il feel di un gioco: la regolo, la testo, la aggiusto, e vado avanti finché i segnali non sembrano corretti.\n\nQuei segnali alimentano tutto. Il sismografo nella cronologia, le barre dipinte sotto i titoli dei commit, il sistema di review, Muse, la costellazione dei file. L\'intera app ragiona da questo strato in giù, non al contrario.';
}

// Path: releaseNotes.about.whereGoing
class _Translations$releaseNotes$about$whereGoing$it
    extends Translations$releaseNotes$about$whereGoing$en {
  _Translations$releaseNotes$about$whereGoing$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'DOVE STA ANDANDO TUTTO QUESTO?';
  @override
  String get body =>
      'Il primo traguardo è la piena parità con GitHub Desktop, SourceTree e GitKraken. Un git client cross-platform che sembra veloce e gestisce i fondamentali meglio di qualsiasi altro. Ci siamo quasi. Il motore spettrale ci dà già un vantaggio per le operazioni che gli altri client ti fanno ragionare a mano.\n\nOltre a questo, l\'obiettivo è superare ogni altro git client in velocità, accessibilità, intelligenza e UX complessiva. C\'è più roba in cantiere di quanto annunciato qui.';
}

// Path: settings.commitPreview.title
class _Translations$settings$commitPreview$title$it
    extends Translations$settings$commitPreview$title$en {
  _Translations$settings$commitPreview$title$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$verbLed$it verbLed =
      _Translations$settings$commitPreview$title$verbLed$it._(_root);
  @override
  late final _Translations$settings$commitPreview$title$descriptive$it
  descriptive = _Translations$settings$commitPreview$title$descriptive$it._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$title$narrative$it narrative =
      _Translations$settings$commitPreview$title$narrative$it._(_root);
}

// Path: settings.commitPreview.base
class _Translations$settings$commitPreview$base$it
    extends Translations$settings$commitPreview$base$en {
  _Translations$settings$commitPreview$base$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$base$verbLed$it verbLed =
      _Translations$settings$commitPreview$base$verbLed$it._(_root);
  @override
  late final _Translations$settings$commitPreview$base$descriptive$it
  descriptive = _Translations$settings$commitPreview$base$descriptive$it._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$base$narrative$it narrative =
      _Translations$settings$commitPreview$base$narrative$it._(_root);
}

// Path: settings.commitPreview.balancedSuffix
class _Translations$settings$commitPreview$balancedSuffix$it
    extends Translations$settings$commitPreview$balancedSuffix$en {
  _Translations$settings$commitPreview$balancedSuffix$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$verbLed$it
  verbLed = _Translations$settings$commitPreview$balancedSuffix$verbLed$it._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$descriptive$it
  descriptive =
      _Translations$settings$commitPreview$balancedSuffix$descriptive$it._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$narrative$it
  narrative =
      _Translations$settings$commitPreview$balancedSuffix$narrative$it._(_root);
}

// Path: settings.commitPreview.everythingSuffix
class _Translations$settings$commitPreview$everythingSuffix$it
    extends Translations$settings$commitPreview$everythingSuffix$en {
  _Translations$settings$commitPreview$everythingSuffix$it._(
    TranslationsIt root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$verbLed$it
  verbLed = _Translations$settings$commitPreview$everythingSuffix$verbLed$it._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$descriptive$it
  descriptive =
      _Translations$settings$commitPreview$everythingSuffix$descriptive$it._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$narrative$it
  narrative =
      _Translations$settings$commitPreview$everythingSuffix$narrative$it._(
        _root,
      );
}

// Path: xray.cards.branchModel
class _Translations$xray$cards$branchModel$it
    extends Translations$xray$cards$branchModel$en {
  _Translations$xray$cards$branchModel$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get broadClaim =>
      'Il repository ha abbastanza superficie di branch da premiare una navigazione branch-aware.';
  @override
  String get broadTitle => 'Il modello di branch ha superficie';
  @override
  String localBranchesDetail({required Object count}) =>
      '${count} branch locali.';
  @override
  String get localBranchesLabel => 'Branch locali';
  @override
  String remoteBranchesDetail({required Object count}) =>
      '${count} branch remoti.';
  @override
  String get remoteBranchesLabel => 'Branch remoti';
  @override
  String get simpleClaim => 'Il modello di branch visibile è ristretto.';
  @override
  String get simpleTitle => 'Modello di branch semplice';
}

// Path: xray.cards.bursty
class _Translations$xray$cards$bursty$it
    extends Translations$xray$cards$bursty$en {
  _Translations$xray$cards$bursty$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Il lavoro arriva in raffiche concentrate anziché in un ritmo quotidiano regolare.';
  @override
  String get title => 'Cadenza di sviluppo a raffiche';
}

// Path: xray.cards.hiddenRefs
class _Translations$xray$cards$hiddenRefs$it
    extends Translations$xray$cards$hiddenRefs$en {
  _Translations$xray$cards$hiddenRefs$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object count}) =>
      '${count} ref vivono al di fuori del normale spazio branch/tag.';
  @override
  String evidenceDetail({required Object count}) =>
      '${count} ref al di fuori di heads/remotes/tags.';
  @override
  String get evidenceLabel => 'Ref nascoste';
  @override
  String get namespacesLabel => 'Namespace';
  @override
  String get title => 'Namespace Git nascosti';
}

// Path: xray.cards.keystone
class _Translations$xray$cards$keystone$it
    extends Translations$xray$cards$keystone$en {
  _Translations$xray$cards$keystone$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String claim({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
    n,
    one:
        'Un file porta un peso di co-change sproporzionato rispetto al suo numero di tocchi.',
    other:
        'Un piccolo insieme di file porta un peso di co-change sproporzionato rispetto ai loro numeri di tocchi.',
  );
  @override
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: '${n} tocco · pull φ=${score}',
        other: '${n} tocchi · pull φ=${score}',
      );
  @override
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(
        n,
        one: 'File-ponte pietra angolare',
        other: '${n} file-ponte pietra angolare',
      );
}

// Path: xray.cards.machineHistory
class _Translations$xray$cards$machineHistory$it
    extends Translations$xray$cards$machineHistory$en {
  _Translations$xray$cards$machineHistory$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'I commit in stile checkpoint distorcono in modo sostanziale le metriche ingenue della cronologia.';
  @override
  String machineCommitsDetail({required Object count}) =>
      '${count} commit corrispondono a pattern macchina/sessione.';
  @override
  String get machineCommitsLabel => 'Commit macchina';
  @override
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '${raw} commit grezzi contro ${filtered} commit filtrati.';
  @override
  String get rawVsFilteredLabel => 'Grezzi vs filtrati';
  @override
  String get title => 'La cronologia macchina domina le metriche grezze';
}

// Path: xray.cards.migration
class _Translations$xray$cards$migration$it
    extends Translations$xray$cards$migration$en {
  _Translations$xray$cards$migration$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object older, required Object newer}) =>
      'La cronologia si sposta da `${older}` a `${newer}`, suggerendo una transizione di stack o di superficie.';
  @override
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches} tocchi, ultima attività ${lastActive}.';
  @override
  String get title => 'Migrazione di architettura visibile';
}

// Path: xray.cards.narrowHotspot
class _Translations$xray$cards$narrowHotspot$it
    extends Translations$xray$cards$narrowHotspot$en {
  _Translations$xray$cards$narrowHotspot$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Un piccolo insieme di file e directory assorbe una quota sproporzionata di modifiche.';
  @override
  String get title => 'La concentrazione di hotspot è ristretta';
  @override
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path} rappresenta il ${pct}% dell\'insieme di hotspot visibile.';
  @override
  String get topHotspotLabel => 'Hotspot principale';
  @override
  String visibleAuthorsDetail({required Object count}) =>
      '${count} autori in questa fetta di cronologia.';
  @override
  String get visibleAuthorsLabel => 'Autori visibili';
}

// Path: xray.cards.noTags
class _Translations$xray$cards$noTags$it
    extends Translations$xray$cards$noTags$en {
  _Translations$xray$cards$noTags$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'I tag Git non vengono usati come strato visibile di release o milestone.';
  @override
  String remoteEndpointsDetail({required Object count}) =>
      '${count} endpoint remoti configurati.';
  @override
  String get remoteEndpointsLabel => 'Endpoint remoti';
  @override
  String get tagCountDetail => '0 tag trovati.';
  @override
  String get tagCountLabel => 'Numero di tag';
  @override
  String get title => 'Nessuna traccia formale di release/tag';
}

// Path: xray.cards.reflog
class _Translations$xray$cards$reflog$it
    extends Translations$xray$cards$reflog$en {
  _Translations$xray$cards$reflog$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Il volume del reflog suggerisce un\'iterazione locale concentrata oltre i commit pubblicati.';
  @override
  String get peakReflogDayLabel => 'Giorno di picco reflog';
  @override
  String get title => 'Sessioni di editing locale intense';
}

// Path: xray.cards.singleOwner
class _Translations$xray$cards$singleOwner$it
    extends Translations$xray$cards$singleOwner$en {
  _Translations$xray$cards$singleOwner$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object path, required Object kind}) =>
      '`${path}` è un ${kind} molto toccato con un unico autore visibile distinto.';
  @override
  String ownerCountDetail({required Object count}) =>
      '${count} autori distinti.';
  @override
  String get ownerCountLabel => 'Numero di proprietari';
  @override
  String get title => 'Hotspot a proprietario unico';
  @override
  String get touchCountLabel => 'Numero di tocchi';
  @override
  String touchDetailFiltered({required Object count}) =>
      '${count} tocchi nella cronologia filtrata.';
  @override
  String touchDetailRaw({required Object count}) =>
      '${count} tocchi nella cronologia grezza.';
}

// Path: onboarding.repo.doors.open
class _Translations$onboarding$repo$doors$open$it
    extends Translations$onboarding$repo$doors$open$en {
  _Translations$onboarding$repo$doors$open$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Apri';
  @override
  String get subtitle => 'esistente';
  @override
  String get hint => 'uno che hai già';
}

// Path: onboarding.repo.doors.clone
class _Translations$onboarding$repo$doors$clone$it
    extends Translations$onboarding$repo$doors$clone$en {
  _Translations$onboarding$repo$doors$clone$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Clona';
  @override
  String get subtitle => 'da URL';
  @override
  String get hint => 'incolla un URL remoto';
}

// Path: onboarding.repo.doors.create
class _Translations$onboarding$repo$doors$create$it
    extends Translations$onboarding$repo$doors$create$en {
  _Translations$onboarding$repo$doors$create$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Crea';
  @override
  String get subtitle => 'nuovo';
  @override
  String get hint => 'inizia qualcosa da zero';
}

// Path: settings.commitPreview.title.verbLed
class _Translations$settings$commitPreview$title$verbLed$it
    extends Translations$settings$commitPreview$title$verbLed$en {
  _Translations$settings$commitPreview$title$verbLed$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Fai saltare alla volpe i biscotti che puzzano';
  @override
  String get s2 =>
      'Addestra la volpe a rifiutare i biscotti manomessi prima di inghiottirli';
  @override
  String get s3 =>
      'Obbliga la volpe a esaminare forensicamente ogni biscotto al cancello';
  @override
  String get def => 'Insegna alla volpe a rifiutare i biscotti cattivi';
}

// Path: settings.commitPreview.title.descriptive
class _Translations$settings$commitPreview$title$descriptive$it
    extends Translations$settings$commitPreview$title$descriptive$en {
  _Translations$settings$commitPreview$title$descriptive$it._(
    TranslationsIt root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'ora è la volpe a scegliere i biscotti';
  @override
  String get s2 => 'Routine di ispezione dei biscotti, inculcata nella volpe';
  @override
  String get s3 =>
      'Forense di verifica dei biscotti, radicata nella volpe a forza di ripetizione';
  @override
  String get def => 'Protocollo annusa-biscotti, installato nella volpe';
}

// Path: settings.commitPreview.title.narrative
class _Translations$settings$commitPreview$title$narrative$it
    extends Translations$settings$commitPreview$title$narrative$en {
  _Translations$settings$commitPreview$title$narrative$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      'la volpe ha iniziato a saltare i biscotti dall\'odore sbagliato';
  @override
  String get s2 =>
      'Mi sono seduto con la volpe e abbiamo passato in rassegna quali biscotti rifiutare';
  @override
  String get s3 =>
      'Ho passato buona parte di un pomeriggio a convincere la volpe che non ogni biscotto offerto è, in buona fede, un biscotto';
  @override
  String get def =>
      'Ho chiesto alla volpe di annusare i biscotti prima di mangiarli';
}

// Path: settings.commitPreview.base.verbLed
class _Translations$settings$commitPreview$base$verbLed$it
    extends Translations$settings$commitPreview$base$verbLed$en {
  _Translations$settings$commitPreview$base$verbLed$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'La volpe dà un\'occhiata. Quello che puzza resta lì.';
  @override
  String get s2 =>
      'La volpe ispeziona ogni token, rifiuta tutto ciò che ha l\'odore sbagliato e annota il rifiuto sulla veranda.';
  @override
  String get s3 =>
      'La volpe gira attorno a ogni token, campiona l\'aria da tre angolazioni, rifiuta quelli che risultano sbagliati e aspetta un istante per assicurarsi che il rifiuto tenga.';
  @override
  String get def =>
      'Ora la volpe annusa ogni token e rifiuta con garbo quelli sospetti.';
}

// Path: settings.commitPreview.base.descriptive
class _Translations$settings$commitPreview$base$descriptive$it
    extends Translations$settings$commitPreview$base$descriptive$en {
  _Translations$settings$commitPreview$base$descriptive$it._(
    TranslationsIt root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Passaggio leggero su quelli strani, più o meno.';
  @override
  String get s2 =>
      'Un rifiuto documentato su ogni token dall\'odore sbagliato, emesso dalla veranda e annotato.';
  @override
  String get s3 =>
      'Un rifiuto autenticato per ogni token dall\'odore sbagliato, emesso dalla veranda con una zampa alzata, l\'altra ferma.';
  @override
  String get def =>
      'Un rifiuto garbato sui token sospetti, emesso dalla veranda.';
}

// Path: settings.commitPreview.base.narrative
class _Translations$settings$commitPreview$base$narrative$it
    extends Translations$settings$commitPreview$base$narrative$en {
  _Translations$settings$commitPreview$base$narrative$it._(TranslationsIt root)
    : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      'La volpe ha più o meno smesso di mangiare quelli strani. Facile.';
  @override
  String get s2 =>
      'Prima ogni token scendeva senza troppi pensieri; ora c\'è una pausa, un\'occhiata come si deve e un rifiuto per quelli che non convincono.';
  @override
  String get s3 =>
      'Prima ogni token scendeva senza pensarci. Ora: una pausa. L\'aria, inspirata. L\'aria, trattenuta. La volpe fissa le assi della veranda in cerca del piccolo sussulto che a volte hanno quando qualcosa non va, e solo allora prende la decisione.';
  @override
  String get def =>
      'Prima ogni token veniva inghiottito senza cerimonie; ora prima c\'è un\'annusata.';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class _Translations$settings$commitPreview$balancedSuffix$verbLed$it
    extends Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  _Translations$settings$commitPreview$balancedSuffix$verbLed$it._(
    TranslationsIt root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' La veranda va bene. Il cortile fa come gli pare.';
  @override
  String get s2 =>
      ' Veranda spazzata dopo ogni rifiuto; fango nel cortile consentito negli orari affissi.';
  @override
  String get s3 =>
      ' Veranda spazzata e rispazzata; fango del cortile catalogato per impronta e meteo, e la volpe indugia sulla soglia più a lungo di prima.';
  @override
  String get def =>
      ' La veranda resta pulita; il cortile mantiene i suoi diritti di fango.';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class _Translations$settings$commitPreview$balancedSuffix$descriptive$it
    extends Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  _Translations$settings$commitPreview$balancedSuffix$descriptive$it._(
    TranslationsIt root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Veranda okay. Il cortile fa cose da cortile.';
  @override
  String get s2 =>
      ' Veranda come zona pulita a prova di evidenza; cortile come zona fango designata, orari affissi.';
  @override
  String get s3 =>
      ' Veranda come camera bianca in qualità probatoria; cortile come archivio di fango catalogato; soglia come luogo dove la volpe si ferma e pensa troppo a lungo.';
  @override
  String get def => ' Veranda pulita; diritti di fango preservati nel cortile.';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class _Translations$settings$commitPreview$balancedSuffix$narrative$it
    extends Translations$settings$commitPreview$balancedSuffix$narrative$en {
  _Translations$settings$commitPreview$balancedSuffix$narrative$it._(
    TranslationsIt root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' La veranda andava bene. Il cortile, chissà.';
  @override
  String get s2 =>
      ' Dopo la veranda è stata tenuta pulita; la volpe si è ritirata nel cortile, che è dove avviene il pensare.';
  @override
  String get s3 =>
      ' Quella sera la veranda è stata strofinata due volte. La volpe ha camminato lenta per il cortile, si è fermata al solito palo dello steccato e ha guardato indietro verso la veranda come se la veranda le dovesse qualcosa.';
  @override
  String get def =>
      ' La veranda resta pulita, anche se il cortile vince ancora in dignità.';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class _Translations$settings$commitPreview$everythingSuffix$verbLed$it
    extends Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  _Translations$settings$commitPreview$everythingSuffix$verbLed$it._(
    TranslationsIt root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Ambra c\'è. Corrente scorre. Spina punge se deve. Per lo più niente.';
  @override
  String get s2 =>
      ' Ambra trattiene ogni odore per la revisione. Corrente porta l\'aria del giorno verso la spina del cancello, che segna ogni rifiuto per il conteggio serale.';
  @override
  String get s3 =>
      ' Ambra trattiene ogni odore e gli dà un peso diverso a seconda dell\'ora. Corrente attraversa la veranda con angolazioni che non dovrebbero contare ma contano. La spina del cancello punge una volta per i rifiuti e due per quelli che la volpe ha quasi mancato, e la volpe conosce la differenza anche quando nessun altro la coglie.';
  @override
  String get def =>
      ' Ambra trattiene l\'odore. Corrente lo sposta avanti. La spina del cancello ferma ciò che non deve passare.';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class _Translations$settings$commitPreview$everythingSuffix$descriptive$it
    extends
        Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  _Translations$settings$commitPreview$everythingSuffix$descriptive$it._(
    TranslationsIt root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Ambra sul palo. Corrente nell\'aria. Spina al cancello. Va bene.';
  @override
  String get s2 =>
      ' Ambra come testimone d\'odore designata; corrente come ambiente registrato; segni di spina come registro dei rifiuti del giorno, riconciliato all\'imbrunire.';
  @override
  String get s3 =>
      ' Ambra come testimone d\'odore il cui silenzio è già di per sé una lettura; corrente come ambiente a trama che si muove sbagliato nei giorni in cui qualcosa è sbagliato; spina come contabile del cancello, i cui segni la volpe controlla prima di dormire e di nuovo prima dell\'alba.';
  @override
  String get def =>
      ' Ambra come testimone d\'odore; corrente come contesto ambientale; spina come il silenzioso segno di rifiuto del cancello.';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class _Translations$settings$commitPreview$everythingSuffix$narrative$it
    extends Translations$settings$commitPreview$everythingSuffix$narrative$en {
  _Translations$settings$commitPreview$everythingSuffix$narrative$it._(
    TranslationsIt root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsIt _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Ambra era in giro. Corrente andava e veniva. Spina faceva le sue cose in silenzio. Vabbè, tutto tranquillo.';
  @override
  String get s2 =>
      ' Ambra ha tenuto il registro degli odori della giornata, la corrente è stata annotata per direzione e ora, e i segni della spina sono stati conteggiati e controfirmati dalla veranda.';
  @override
  String get s3 =>
      ' Ambra ha tenuto il registro degli odori, ma la volpe giura che certe mattine pesa di più. La corrente ha attraversato la veranda come fa sempre, cioè sbagliato nei giorni che contano. La spina del cancello ha segnato ogni rifiuto; la volpe è uscita alle prime luci a contarli, come si contano gli scalini che hai già contato.';
  @override
  String get def =>
      ' Ambra ha tenuto il registro degli odori, la corrente ha mosso l\'aria, e la spina del cancello ha fermato ciò che andava fermato.';
}
