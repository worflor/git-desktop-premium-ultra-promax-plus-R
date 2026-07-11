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
class TranslationsFr extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsFr({
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
             locale: AppLocale.fr,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <fr>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final TranslationsFr _root = this; // ignore: unused_field

  @override
  TranslationsFr $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsFr(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$app$fr app = _Translations$app$fr._(_root);
  @override
  late final _Translations$backend$fr backend = _Translations$backend$fr._(
    _root,
  );
  @override
  late final _Translations$branches$fr branches = _Translations$branches$fr._(
    _root,
  );
  @override
  late final _Translations$changes$fr changes = _Translations$changes$fr._(
    _root,
  );
  @override
  late final _Translations$common$fr common = _Translations$common$fr._(_root);
  @override
  late final _Translations$diff$fr diff = _Translations$diff$fr._(_root);
  @override
  late final _Translations$filament$fr filament = _Translations$filament$fr._(
    _root,
  );
  @override
  late final _Translations$history$fr history = _Translations$history$fr._(
    _root,
  );
  @override
  late final _Translations$historySurgery$fr historySurgery =
      _Translations$historySurgery$fr._(_root);
  @override
  late final _Translations$onboarding$fr onboarding =
      _Translations$onboarding$fr._(_root);
  @override
  late final _Translations$orrery$fr orrery = _Translations$orrery$fr._(_root);
  @override
  late final _Translations$palette$fr palette = _Translations$palette$fr._(
    _root,
  );
  @override
  late final _Translations$releaseNotes$fr releaseNotes =
      _Translations$releaseNotes$fr._(_root);
  @override
  late final _Translations$repoSummary$fr repoSummary =
      _Translations$repoSummary$fr._(_root);
  @override
  late final _Translations$settings$fr settings = _Translations$settings$fr._(
    _root,
  );
  @override
  late final _Translations$sync$fr sync = _Translations$sync$fr._(_root);
  @override
  late final _Translations$xray$fr xray = _Translations$xray$fr._(_root);
}

// Path: app
class _Translations$app$fr extends Translations$app$en {
  _Translations$app$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get panelSettings => 'Paramètres';
  @override
  String get panelReleaseNotes => 'Notes de version';
  @override
  String get panelFilamentFindings => 'Constats Filament';
  @override
  String get filamentFindingsUpper => 'CONSTATS FILAMENT';
  @override
  late final _Translations$app$cheatsheet$fr cheatsheet =
      _Translations$app$cheatsheet$fr._(_root);
  @override
  String get commandPaletteTooltip => 'Palette de commandes   /';
  @override
  String get newDeskFallback => 'nouveau bureau';
  @override
  String get deskFallback => 'bureau';
  @override
  String get currentDeskFallback => 'actuel';
  @override
  String get noRepositoryOpen => 'Aucun dépôt ouvert';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Impossible d\'ouvrir comme bureau : ${error}';
  @override
  String couldNotDetectForge({required Object error}) =>
      'Impossible de détecter la forge : ${error}';
  @override
  String get cannotFetchPrNoForge =>
      'Impossible de récupérer la PR : forge non détectée pour ce dépôt.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      'Écraser ${ref} avec la dernière version du distant ?';
  @override
  String get overwrite => 'Écraser';
  @override
  String couldntFetchPr({required Object error}) =>
      'Impossible de récupérer la PR : ${error}';
  @override
  String get promoteDeskToPr => 'Promouvoir le bureau en PR';
  @override
  String get applyToMain => 'Appliquer à main';
  @override
  String updateDeskFrom({required Object target, required Object source}) =>
      'Mettre à jour ${target} depuis ${source}';
  @override
  String bringChangesFromHere({required Object source}) =>
      'Amener les changements de ${source} ici';
  @override
  String get editLocalPr => 'Modifier la PR locale';
  @override
  String get discardLocalPr => 'Abandonner la PR locale';
  @override
  String get closeDesk => 'Fermer le bureau';
  @override
  String couldntPromote({required Object error}) =>
      'Impossible de promouvoir : ${error}';
  @override
  String get commitOrShelveBeforeApplying =>
      'Validez ou rangez les changements du bureau avant d\'appliquer.';
  @override
  String get couldNotResolveMainWorktree =>
      'Impossible de résoudre le chemin de l\'arbre de travail principal.';
  @override
  String couldntPromoteDesk({required Object error}) =>
      'Impossible de promouvoir le bureau : ${error}';
  @override
  String get couldntDetermineBaseBranch =>
      'Impossible de déterminer la branche de base pour ce bureau.';
  @override
  String prBaseHeadSame({required Object branch}) =>
      'La base et la pointe de la PR sont la même branche (${branch}) — rien à appliquer.';
  @override
  String appliedBranchToBase({required Object branch, required Object base}) =>
      '${branch} appliquée à ${base}';
  @override
  String updatedDeskToDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
    n,
    one: '${target} mis à jour vers ${source} (${n} commit).',
    other: '${target} mis à jour vers ${source} (${n} commits).',
  );
  @override
  String get fastForwardFailedFallback =>
      'L\'avance rapide n\'a pas pu s\'appliquer proprement — aperçu sous forme de patch à la place.';
  @override
  String deskAheadOfDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
    n,
    one: '${target} est en avance sur ${source} de ${n} commit.',
    other: '${target} est en avance sur ${source} de ${n} commits.',
  );
  @override
  String deskUpToDate({required Object target, required Object source}) =>
      '${target} est déjà à jour avec ${source}.';
  @override
  String uncommittedPreviewNotice({required Object target}) =>
      'Changements non validés dans ${target} — aperçu sous forme de patch à la place.';
  @override
  String updateDeskFromLower({
    required Object target,
    required Object source,
  }) => 'mettre à jour ${target} depuis ${source}';
  @override
  String noUpdatesToBringFrom({required Object source}) =>
      'Aucune mise à jour à amener depuis ${source}.';
  @override
  String get updatePrepFailed => 'Échec de la préparation de la mise à jour';
  @override
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => 'amener les changements de ${source} dans ${target}';
  @override
  String noPatchableChanges({required Object source, required Object target}) =>
      'Aucun changement applicable en patch à amener de ${source} dans ${target}.';
  @override
  String get patchPrepFailed => 'Échec de la préparation du patch';
  @override
  String failureWithError({required Object label, required Object error}) =>
      '${label} : ${error}';
  @override
  String get titleHint => 'titre';
  @override
  String get bodyHint => 'corps';
  @override
  String get bodyOptionalHint => 'corps (facultatif)';
  @override
  String get draftLower => 'brouillon';
  @override
  String get cancelLower => 'annuler';
  @override
  String get saveLower => 'enregistrer';
  @override
  String couldntSave({required Object error}) =>
      'Impossible d\'enregistrer : ${error}';
  @override
  String get stashedNoOtherDesk =>
      'Changements remisés — aucun autre bureau où les appliquer. Utilisez git stash pop pour les récupérer.';
  @override
  String get suggestedSource => 'source suggérée';
  @override
  String tooltipModifiedCount({required Object n}) => '${n} modifiés';
  @override
  String tooltipAheadCount({required Object n}) => '${n} en avance';
  @override
  String tooltipBehindCount({required Object n}) => '${n} en retard';
  @override
  String get focusedEdits => 'modifications ciblées';
  @override
  String get editsSpreadAcrossSubsystems =>
      'modifications réparties sur plusieurs sous-systèmes';
  @override
  String get editsTouchingManySubsystems =>
      'modifications touchant de nombreux sous-systèmes';
  @override
  String get focusedBranch => 'branche ciblée';
  @override
  String get branchSpansMultipleSubsystems =>
      'la branche couvre plusieurs sous-systèmes';
  @override
  String get structurallyDivergentFromMainline =>
      'structurellement divergente de la ligne principale';
  @override
  String get localPr => 'PR locale';
  @override
  String lastTouched({required Object time}) => 'dernière touche ${time}';
  @override
  String driftGroupCount({required Object n, required Object dir}) =>
      '${n} dans ${dir}';
  @override
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';
  @override
  String get uncommittedChanges => 'Changements non validés';
  @override
  String get closeDeskQuestion => 'Fermer le bureau ?';
  @override
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} fichier non validé.',
        other: '${n} fichiers non validés.',
      );
  @override
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} commit en avance sur main.',
        other: '${n} commits en avance sur main.',
      );
  @override
  String get willRemoveWorktreeDirectory =>
      'Ceci supprimera le répertoire de l\'arbre de travail.';
  @override
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} fichier modifié',
        other: '${n} fichiers modifiés',
      );
  @override
  String get shelveHere => 'Ranger ici';
  @override
  String get discardAndClose => 'Abandonner et fermer';
  @override
  String get noRepository => 'aucun dépôt';
  @override
  String get issuePromotedToRemote => 'Ticket promu vers le distant.';
  @override
  String get pushedToRemote => 'Poussé vers le distant.';
  @override
  String get pulledFromRemote => 'Tiré depuis le distant.';
  @override
  String get remoteIssueNotFound => 'ticket distant introuvable';
  @override
  String importedIssueLocally({required Object id}) =>
      '#${id} importé localement.';
  @override
  String get issueAbandoned => 'Ticket abandonné.';
  @override
  String get abandonIssue => 'Abandonner le ticket';
  @override
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      'Supprimer définitivement le ticket local #${id} ? Ceci supprime sa réf et est irréversible.';
  @override
  String get abandon => 'Abandonner';
  @override
  String publishedBranch({required Object branch}) => '${branch} publiée.';
  @override
  String get publishingEllipsis => 'Publication…';
  @override
  String get publish => 'Publier';
  @override
  String get noRemoteConfigured => 'Aucun distant configuré pour ce dépôt.';
  @override
  String get jumpToDesk => 'Aller au bureau';
  @override
  String get arrowOpen => '→ ouvrir';
  @override
  String get openOnANewDesk => 'Ouvrir sur un nouveau bureau';
  @override
  String get plusDesk => '+ bureau';
  @override
  String get plusSpace => '+ ';
  @override
  String get newBranchNameHint => 'nom-de-branche';
  @override
  String get escLower => 'échap';
  @override
  String get plusNewDesk => '+ nouveau bureau';
  @override
  String get fromHeadEllipsis => 'depuis HEAD...';
  @override
  String get viewAllBranches => 'Voir toutes les branches';
  @override
  String get issuesLower => 'tickets';
  @override
  String get newIssueLower => 'nouveau ticket';
  @override
  String get noneLinked => 'aucun lié';
  @override
  String get noOpenIssues => 'aucun ticket ouvert';
  @override
  String get createAndPushLower => 'créer + pousser';
  @override
  String get createLower => 'créer';
  @override
  String get remoteLower => 'distant';
  @override
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';
  @override
  String get promoteToRemote => 'Promouvoir vers le distant';
  @override
  String get pushToRemote => 'Pousser vers le distant';
  @override
  String get pullFromRemote => 'Tirer depuis le distant';
  @override
  String get importLabel => 'Importer';
  @override
  String get failedToCreateRepository => 'Échec de la création du dépôt.';
  @override
  String get openRepositoryLower => 'ouvrir un dépôt';
  @override
  String get newRepositoryLower => 'nouveau dépôt';
  @override
  String get back => 'Retour';
  @override
  String get openRepositoryDialogTitle => 'Ouvrir un dépôt';
  @override
  String get createRepositoryDialogTitle => 'Créer un dépôt';
  @override
  String get cloneTargetDialogTitle => 'Cible du clonage';
  @override
  String get cloneToDialogTitle => 'Cloner vers';
  @override
  String get exportToDialogTitle => 'Exporter vers';
  @override
  String get createFromTemplateInDialogTitle => 'Créer depuis un modèle dans';
  @override
  String get notAGitRepoInitConfirm =>
      'Ce n\'est pas un dépôt git. En initialiser un ici ?';
  @override
  String get repositoryUrlRequired => 'URL du dépôt requise.';
  @override
  String get failedToCloneRepository => 'Échec du clonage du dépôt.';
  @override
  String cloningEllipsis({required Object name}) => 'Clonage de ${name}...';
  @override
  String get cloneCancelled => 'Clonage annulé.';
  @override
  String get noProjectsYet => 'Aucun projet pour l\'instant';
  @override
  String get dissolveGroup => 'Dissoudre le groupe';
  @override
  String get projectsHeader => 'Projets';
  @override
  String get cloneLabel => 'Cloner';
  @override
  String get createLabel => 'Créer';
  @override
  String get openLabel => 'Ouvrir';
  @override
  String get repositoryUrlPlaceholder => 'URL du dépôt';
  @override
  String get projectNameOrFullPathPlaceholder =>
      'nom-du-projet ou chemin complet';
  @override
  String get pathToProjectPlaceholder => '/chemin/vers/le/projet';
  @override
  String get cloneToFolderPathPlaceholder => 'Chemin du dossier de clonage';
  @override
  String get switchToCreateRepo => 'Passer à Créer un dépôt';
  @override
  String get explorer => 'Explorateur';
  @override
  String get terminal => 'Terminal';
  @override
  String get cloneUrl => 'URL de clonage';
  @override
  String get copyPath => 'Copier le chemin';
  @override
  String get export => 'Exporter';
  @override
  String get readme => 'README';
  @override
  String get duplicate => 'Dupliquer';
  @override
  String get template => 'Modèle';
  @override
  String get forgetThisProject => 'Oublier ce projet';
  @override
  String get aiKindCommitMessage => 'message de commit';
  @override
  String get aiKindReview => 'revue';
  @override
  String get aiKindMuse => 'muse';
  @override
  String get aiKindPresent => 'présenter';
  @override
  String get aiKindDebug => 'débogage';
  @override
  String aiStatusRunning({required Object kind}) => '${kind} en cours';
  @override
  String aiStatusFailedUnread({required Object kind}) =>
      '${kind} échoué (non lu)';
  @override
  String aiStatusReadyUnread({required Object kind}) => '${kind} prêt (non lu)';
  @override
  String get filesLower => 'fichiers';
  @override
  String get commitsLower => 'commits';
  @override
  String get undoLabel => 'Annuler';
  @override
  String get goLabel => 'go';
  @override
  String countdownSeconds({required Object n}) => '${n}s';
  @override
  String get collapseGlyph => '▲ réduire';
  @override
  String moreLinesGlyph({required Object n}) => '▼ ${n} lignes de plus';
}

// Path: backend
class _Translations$backend$fr extends Translations$backend$en {
  _Translations$backend$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$backend$ops$fr ops = _Translations$backend$ops$fr._(
    _root,
  );
  @override
  late final _Translations$backend$mergeOutcome$fr mergeOutcome =
      _Translations$backend$mergeOutcome$fr._(_root);
}

// Path: branches
class _Translations$branches$fr extends Translations$branches$en {
  _Translations$branches$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get runningAiReview => 'Revue IA en cours…';
  @override
  String prNumberLabel({required Object number}) => 'PR n°${number}';
  @override
  String get findings => 'CONSTATS';
  @override
  String get observations => 'OBSERVATIONS';
  @override
  String get renameEllipsis => 'Renommer…';
  @override
  String get publish => 'Publier';
  @override
  String publishFailed({required Object error}) =>
      'Échec de la publication : ${error}';
  @override
  String couldntOpenDesk({required Object error}) =>
      'Impossible d\'ouvrir le bureau : ${error}';
  @override
  String syncFailed({required Object error}) =>
      'Échec de la synchronisation : ${error}';
  @override
  String get renameBranchTitle => 'Renommer la branche';
  @override
  String get newNameHint => 'nouveau nom';
  @override
  String get rename => 'Renommer';
  @override
  String invalidBranchName({required Object name}) =>
      '« ${name} » n\'est pas un nom de branche valide.';
  @override
  String renameFailed({required Object error}) =>
      'Échec du renommage : ${error}';
  @override
  String deletingBranch({required Object name}) => 'Suppression de ${name}';
  @override
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '« ${name} » est ouverte dans le bureau « ${desk} ».';
  @override
  String get openDesk => 'Ouvrir le bureau';
  @override
  String openInDeskShort({required Object desk}) =>
      'ouvrir dans le bureau « ${desk} »';
  @override
  String get couldNotPinBranch =>
      'impossible d\'épingler la pointe de la branche ; suppression ignorée';
  @override
  String get couldNotPinTag =>
      'impossible d\'épingler l\'étiquette ; suppression ignorée';
  @override
  String deletingTag({required Object name}) =>
      'Suppression de l\'étiquette ${name}';
  @override
  String get applyToActiveChanges => 'Appliquer aux modifications actives…';
  @override
  String get couldNotLoadPrDiff => 'Impossible de charger le diff de la PR.';
  @override
  String prSourceLabel({required Object number, required Object title}) =>
      'PR n°${number} : ${title}';
  @override
  String mergeIntoDesk({required Object branch}) => 'Fusionner dans ${branch}…';
  @override
  String get checkoutThisPr => 'Extraire cette PR';
  @override
  String get mergeIntoNewDesk => 'Fusionner dans un nouveau bureau…';
  @override
  String get pushToForge => 'Pousser vers la forge';
  @override
  String get linkToIssue => 'Lier à un ticket…';
  @override
  String get gitPatch => '↓ patch git';
  @override
  String get copyBranchName => 'Copier le nom de la branche';
  @override
  String copiedRef({required Object ref}) => '« ${ref} » copié';
  @override
  String get reviewPr => 'Relire la PR';
  @override
  String get openInBrowser => 'Ouvrir dans le navigateur';
  @override
  String get markAsRead => 'Marquer comme lu';
  @override
  String get markAsUnread => 'Marquer comme non lu';
  @override
  String get replaceLocalCommitsTitle => 'Remplacer les commits locaux ?';
  @override
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref} a des commits locaux absents de la pointe de la PR distante. La mettre à jour les remplacera par la dernière version du distant.';
  @override
  String get update => 'Mettre à jour';
  @override
  String couldntFetchPr({required Object error}) =>
      'Impossible de récupérer la PR : ${error}';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Impossible d\'ouvrir comme bureau : ${error}';
  @override
  String couldntOpenInBrowser({required Object error}) =>
      'Impossible d\'ouvrir dans le navigateur : ${error}';
  @override
  String get noIssuesYetLocal =>
      'Aucun ticket pour l\'instant. Ouvrez-en un en amont, ou utilisez « + nouveau ticket local » dans la vue tickets.';
  @override
  String get remotePrsLinkLocalOnly =>
      'Les PR distantes ne peuvent être liées qu\'à des tickets locaux. Créez-en un avec « + nouveau ticket local ».';
  @override
  String linkPrToIssues({required Object number}) =>
      'Lier la PR n°${number} à un/des ticket(s)';
  @override
  String get noPrsYetLocal =>
      'Aucune PR pour l\'instant. Ouvrez-en une en amont, ou promouvez un bureau en PR.';
  @override
  String get remoteIssuesLinkLocalOnly =>
      'Les tickets distants ne peuvent être liés qu\'à des PR locales. Promouvez d\'abord un bureau en PR.';
  @override
  String linkIssueToPrs({required Object number}) =>
      'Lier le ticket n°${number} à une/des PR';
  @override
  String couldntToggleLink({required Object error}) =>
      'Impossible de basculer le lien : ${error}';
  @override
  String get openPatchDialogTitle => 'Ouvrir un patch (.patch / .diff)';
  @override
  String get clipboardNoText => 'Le presse-papiers ne contient aucun texte.';
  @override
  String get clipboardPatchLabel => 'presse-papiers.patch';
  @override
  String failedToOpenPatch({required Object error}) =>
      'Échec de l\'ouverture du patch : ${error}';
  @override
  String get patchEmptyOrUnparseable =>
      'Le patch est vide ou impossible à analyser.';
  @override
  String get prPushedToForge => 'PR poussée vers la forge.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      'Écraser ${ref} avec la dernière version du distant ?';
  @override
  String get overwrite => 'Écraser';
  @override
  String get loadingBranchesTitle => 'Chargement des branches';
  @override
  String get loadingBranchesMessage =>
      'Lecture des branches et étiquettes locales.';
  @override
  String get branchesUnavailableTitle => 'Branches indisponibles';
  @override
  String get filterPullRequestsHint => 'filtrer les pull requests…';
  @override
  String get filterIssuesHint => 'filtrer les tickets…';
  @override
  String get branchNameHint => 'nom de branche';
  @override
  String get tagsNewestFirst => 'étiquettes, plus récentes d\'abord';
  @override
  String get tagsOldestFirst => 'étiquettes, plus anciennes d\'abord';
  @override
  String get flipSortDirection => 'inverser le sens du tri';
  @override
  String get readingPullRequests => 'Lecture des pull requests…';
  @override
  String get noOpenPullRequests => 'Aucune pull request ouverte';
  @override
  String get noPullRequestsHint =>
      'Ouvrez-en une depuis une branche, ou promouvez un bureau.';
  @override
  String get noPrsMatchFilters => 'Aucune PR ne correspond à ces filtres';
  @override
  String get toggleFiltersRowAbove =>
      'Désactivez les filtres dans la rangée ci-dessus.';
  @override
  String get issuesNewestFirst => 'tickets, plus récents d\'abord';
  @override
  String get issuesOldestFirst => 'tickets, plus anciens d\'abord';
  @override
  String get issuesHeading => 'TICKETS';
  @override
  String get readingIssuesLower => 'lecture des tickets…';
  @override
  String get noOpenIssues => 'Aucun ticket ouvert';
  @override
  String get noIssuesHint => '+ nouveau pour suivre travail et bugs.';
  @override
  String get nothingMatches => 'Rien ne correspond';
  @override
  String get toggleFiltersAbove => 'Désactivez les filtres ci-dessus.';
  @override
  String get bucketFresh => 'FRAIS';
  @override
  String get bucketThisWeek => 'CETTE SEMAINE';
  @override
  String get bucketStalled => 'AU POINT MORT';
  @override
  String get bucketOlder => 'PLUS ANCIEN';
  @override
  String get couldNotResolveMainWorktree =>
      'Impossible de résoudre le chemin de l\'arbre de travail principal.';
  @override
  String couldntSubmitReview({required Object error}) =>
      'Impossible de soumettre la revue : ${error}';
  @override
  String get reviewAiNotAvailable =>
      'L\'IA de revue n\'est pas encore disponible.';
  @override
  String get noReviewModelConfigured => 'Aucun modèle de revue configuré.';
  @override
  String get deskFallback => 'bureau';
  @override
  String deskUncommittedChanges({
    required num n,
    required Object branch,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
    n,
    one:
        '${branch} a ${n} changement non validé — validez ou remisez d\'abord.',
    other:
        '${branch} a ${n} changements non validés — validez ou remisez d\'abord.',
  );
  @override
  String get targetDeskNoBranch => 'Le bureau cible n\'a pas de branche.';
  @override
  String mergePrIntoDesk({required Object number, required Object branch}) =>
      'Fusionner la PR n°${number} dans ${branch}';
  @override
  String get conflictCheckUnavailableVersion =>
      'Vérification de conflit indisponible — git 2.38+ requis';
  @override
  String get conflictCheckUnavailable => 'Vérification de conflit indisponible';
  @override
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'EN CONFLIT · ${n} fichier',
        other: 'EN CONFLIT · ${n} fichiers',
      );
  @override
  String plusMore({required Object n}) => '+${n} de plus';
  @override
  String get rebase => 'Rebaser';
  @override
  String get squash => 'Écraser';
  @override
  String get mergeCommit => 'Commit de fusion';
  @override
  String noDeskForBranch({required Object branch}) =>
      'Aucun bureau trouvé pour la branche ${branch}';
  @override
  String get mergeAnyway => 'Fusionner quand même';
  @override
  String get readingIssues => 'Lecture des tickets…';
  @override
  String get openUpstreamOrLocal =>
      'Ouvrez-en un en amont, ou ouvrez-en un local.';
  @override
  String get noIssuesMatchFilters => 'Aucun ticket ne correspond à ces filtres';
  @override
  String couldntCreateIssue({required Object error}) =>
      'Impossible de créer le ticket : ${error}';
  @override
  String get promoteToRemote => 'Promouvoir vers le distant';
  @override
  String get pushToRemote => 'Pousser vers le distant';
  @override
  String get pullFromRemote => 'Tirer depuis le distant';
  @override
  String get import => 'Importer';
  @override
  String get linkToPr => 'Lier à une PR…';
  @override
  String get abandon => 'Abandonner';
  @override
  String get issuePromotedToRemote => 'Ticket promu vers le distant.';
  @override
  String get issuePushedToRemote => 'Poussé vers le distant.';
  @override
  String get issuePulledFromRemote => 'Tiré depuis le distant.';
  @override
  String issueImportedLocally({required Object number}) =>
      '#${number} importé localement.';
  @override
  String get abandonIssueTitle => 'Abandonner le ticket';
  @override
  String abandonIssueMessage({required Object id}) =>
      'Supprimer définitivement le ticket local #${id} ? Ceci supprime sa réf et est irréversible.';
  @override
  String couldntAbandon({required Object error}) =>
      'Impossible d\'abandonner : ${error}';
  @override
  String couldntPostComment({required Object error}) =>
      'Impossible de publier le commentaire : ${error}';
  @override
  String couldntCloseIssue({required Object error}) =>
      'Impossible de fermer le ticket : ${error}';
  @override
  String couldntAddLabel({required Object error}) =>
      'Impossible d\'ajouter le libellé : ${error}';
  @override
  String get lensBranches => 'BRANCHES';
  @override
  String get lensPrs => 'PR';
  @override
  String get patchUp => '↑ patch';
  @override
  String get syncRibbon => '⇅ sync';
  @override
  String get kbHeading => 'CLAVIER';
  @override
  String get kbNavigateRows => 'naviguer entre les rangées';
  @override
  String get kbExpandCollapse => 'développer / réduire la rangée ciblée';
  @override
  String get kbCheckoutPr => 'extraire la PR ciblée localement';
  @override
  String get kbApproveReview => 'approuver · revue';
  @override
  String get kbRequestChanges => 'demander des modifications';
  @override
  String get kbFocusSearch => 'focus recherche';
  @override
  String get kbSwitchLens => 'changer de vue (branches · pr)';
  @override
  String get kbToggleOverlay => 'basculer cette superposition';
  @override
  String get kbPressToDismiss => 'appuyez n\'importe où pour fermer';
  @override
  String get overrideScarTooltip =>
      'fusionnée avec des vérifications en échec ou sans revue approuvée — à examiner en priorité';
  @override
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} fichier recoupe votre travail non validé',
        other: '${n} fichiers recoupent votre travail non validé',
      );
  @override
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '#${pr}  (${n} fichier)',
        other: '#${pr}  (${n} fichiers)',
      );
  @override
  String get prStateDraft => 'BROUILLON';
  @override
  String get localBadge => 'LOCAL';
  @override
  String get myReviewPending => 'votre revue en attente';
  @override
  String get myReviewApproved => 'vous ✓';
  @override
  String get myReviewChangesRequested => 'vous ✗ modifications demandées';
  @override
  String get myReviewCommented => 'vous avez commenté';
  @override
  String get myReviewDefault => 'vous';
  @override
  String tailCommentsAuthor({required Object count}) =>
      '${count} commentaires · dernier de l\'auteur affiché';
  @override
  String get tailLastComment => 'dernier commentaire';
  @override
  String tailLastReviewState({required Object state}) =>
      'dernière revue · ${state}';
  @override
  String get tailLastReview => 'dernière revue';
  @override
  String tailLastCheckState({required Object state}) =>
      'dernière vérif · ${state}';
  @override
  String get tailLastCommit => 'dernier commit';
  @override
  String get tailLastActivity => 'dernière activité';
  @override
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'ferme ${n} ticket — cliquez pour y aller',
        other: 'ferme ${n} tickets — cliquez pour y aller',
      );
  @override
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'traité par ${n} PR — cliquez pour y aller',
        other: 'traité par ${n} PR — cliquez pour y aller',
      );
  @override
  String get checksLabel => 'vérifications';
  @override
  String get reviewersLabel => 'relecteurs';
  @override
  String get conflictsLabel => 'conflits';
  @override
  String exportFailed({required Object error}) =>
      'Échec de l\'export : ${error}';
  @override
  String get readingFiles => 'lecture des fichiers…';
  @override
  String get noDetailAvailable => 'aucun détail disponible';
  @override
  String get noFilesReported => 'aucun fichier signalé';
  @override
  String get readingGitHistory => 'lecture de l\'historique git…';
  @override
  String get knowsThisCode => 'connaît ce code';
  @override
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} commit sur ces fichiers l\'an dernier',
        other: '${n} commits sur ces fichiers l\'an dernier',
      );
  @override
  String get willFight => 'VA SE BATTRE';
  @override
  String orbitalPartnerCos({required Object cos}) =>
      'partenaire orbital — cos ${cos}';
  @override
  String get orbitLabel => 'orbite';
  @override
  String get touchesYourLocalWork => 'TOUCHE VOTRE TRAVAIL LOCAL';
  @override
  String get mergingWillConflict =>
      'la fusion entrera probablement en conflit avec vos changements non validés';
  @override
  String get closesHeading => 'FERME';
  @override
  String get filesHeading => 'FICHIERS';
  @override
  String get orientAligned => 'aligné';
  @override
  String get orientAdjacent => 'adjacent';
  @override
  String get orientOrthogonal => 'orthogonal';
  @override
  String shapeField({required Object v}) => 'champ ${v}';
  @override
  String shapeSource({required Object v}) => 'source ${v}';
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
  String shapeStress({required Object v}) => 'contrainte ${v}';
  @override
  String shapeWit({required Object v}) => 'wit ${v}';
  @override
  String resonanceReadout({required Object v}) => 'résonance ${v}';
  @override
  String ghostFileTooltip({required Object path}) =>
      'bouge habituellement avec les fichiers de cette PR\n(${path})';
  @override
  String get prStateDraftLower => 'brouillon';
  @override
  String get keystoneTooltip =>
      'clé de voûte — fichier-pont à l\'échelle du dépôt';
  @override
  String get reviewNoteHint => 'laissez une note (facultatif)…';
  @override
  String get reviewComment => 'commenter';
  @override
  String get reviewRequestChanges => 'demander des modifications';
  @override
  String get reviewApprove => '✓ approuver';
  @override
  String get actionPatchDown => '↓ patch';
  @override
  String get actionPrReview => '✦ revue pr';
  @override
  String get actionOpenAsDesk => '⊞ ouvrir comme bureau';
  @override
  String get actionCheckout => '[c] extraire';
  @override
  String get actionMerge => '[m] fusionner ▾';
  @override
  String get mergeMenuMergeCommit => 'commit de fusion';
  @override
  String get mergeMenuSquash => 'écraser et fusionner';
  @override
  String get mergeMenuRebase => 'rebaser et fusionner';
  @override
  String get deleteBranchAfter => 'supprimer la branche après';
  @override
  String checkDurationSec({required Object n}) => '${n}s';
  @override
  String checkDurationMin({required Object m, required Object s}) =>
      '${m}m ${s}s';
  @override
  String assignedTo({required Object names}) => 'assigné : ${names}';
  @override
  String issueConvLine({required Object n, required Object time}) =>
      '${n} conv · ${time}';
  @override
  String get readingThread => 'lecture du fil…';
  @override
  String get addressedByHeading => 'TRAITÉ PAR';
  @override
  String get descriptionHeading => 'DESCRIPTION';
  @override
  String get threadHeading => 'FIL';
  @override
  String get replyHint => 'répondre…';
  @override
  String get assignMe => 'm\'assigner';
  @override
  String get closeLower => 'fermer';
  @override
  String get postReply => '↩ publier';
  @override
  String get remoteProviderUnavailable => 'Fournisseur distant indisponible';
  @override
  String get noRecognisedRemoteHost =>
      'Aucun hôte distant reconnu pour ce dépôt.';
  @override
  String get corpseGone => 'partie';
  @override
  String get corpseAbsorbed => 'absorbée';
  @override
  String get corpseSquashed => 'écrasée';
  @override
  String absorbedDeliveredIn({required Object hash}) => 'livrée dans ${hash}';
  @override
  String get absorbedNoChanges => 'la fusion n\'ajoute aucun changement';
  @override
  String get corpseTagUpstreamGone => 'amont parti';
  @override
  String corpseTagAbsorbed({required Object receipt}) => 'absorbée, ${receipt}';
  @override
  String get corpseTagSquashed => 'écrasée et fusionnée';
  @override
  String semanticsCurrentBranch({required Object name}) =>
      '${name}, branche actuelle';
  @override
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}, suit ${upstream}';
  @override
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}, ${tag}';
  @override
  String semanticsWorktreeOpen({required Object label}) =>
      '${label}, arbre de travail ouvert';
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
  String get crossLinkDesk => 'bureau';
  @override
  String get crossLinkPr => 'PR';
  @override
  String get crossLinkPrDraft => 'PR · brouillon';
  @override
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} ticket',
        other: '${n} tickets',
      );
  @override
  String get headBadge => 'HEAD';
  @override
  String trackingLine({required Object upstream}) => '→ suivi : ${upstream}';
  @override
  String get checkoutButton => 'Extraire';
  @override
  String get createBranch => 'Créer une branche';
  @override
  String get newBranchName => 'Nom de la nouvelle branche';
  @override
  String newBranchNameError({required Object error}) =>
      'Nom de la nouvelle branche — ${error}';
  @override
  String get forceDelete => 'Forcer ?';
  @override
  String get annotated => 'annotée';
  @override
  String get applyCheckFailed => 'apply --check a échoué';
  @override
  String get openPatchFrom => 'OUVRIR UN PATCH DEPUIS';
  @override
  String get patchFromFile => 'depuis un fichier…';
  @override
  String get patchFromFileHint => '.patch / .diff';
  @override
  String get patchFromClipboard => 'depuis le presse-papiers';
  @override
  String get patchFromClipboardHint => 'coller le texte';
  @override
  String get patchPreviewHeading => 'APERÇU DU PATCH';
  @override
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';
  @override
  String get stagedDone => 'indexé.';
  @override
  String get appliedDone => 'appliqué.';
  @override
  String get opening => 'ouverture…';
  @override
  String get mergeEditor => '⇋ éditeur de fusion';
  @override
  String get staging => 'indexation…';
  @override
  String get applying => 'application…';
  @override
  String get stage => 'indexer';
  @override
  String get apply => 'appliquer';
  @override
  String get refineHint =>
      'affiner… (ex. « retire aussi les changements du logger »)';
  @override
  String get reverseArmedTooltip =>
      'armé — la prochaine application ANNULERA le patch (-R)';
  @override
  String get reverseDisarmedTooltip =>
      'armer l\'inversion (-R) — annuler au lieu d\'appliquer';
  @override
  String get reverseArmedLabel => '⟲ inverser ✓';
  @override
  String get reverseLabel => '⟲ inverser';
  @override
  String get untouchedHeading => '⚠ INTACTS';
  @override
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${count} sur ${n} fichier hors du patch',
        other: '${count} sur ${n} fichiers hors du patch',
      );
  @override
  String get staysConflicted =>
      'ces fichiers resteront en conflit — l\'application ne les indexera pas';
  @override
  String get orWith => 'OU AVEC';
  @override
  String get noAiModelConfigured => 'aucun modèle IA configuré';
  @override
  String applyWithPatchFrom({required Object label}) =>
      'appliquer avec le patch de ${label}';
  @override
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => 'appliquer avec le patch de ${label}  ·  ${model}';
  @override
  String get patching => 'application du patch…';
  @override
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  appliquer avec le patch de ${label}';
  @override
  String get orWithAnotherModel => 'ou avec un autre modèle';
  @override
  String get applyCheckPassed =>
      'git apply --check réussi — le patch s\'appliquera proprement';
  @override
  String get gitApplyCheckFailed => 'git apply --check a échoué';
  @override
  String get appliesClean => 's\'applique proprement';
  @override
  String get willNotApply => 'ne s\'appliquera pas';
  @override
  String get newLocalIssue => 'nouveau ticket local';
  @override
  String get filterHint => 'filtrer…';
  @override
  String get nothingToLink => 'Rien à lier pour l\'instant.';
  @override
  String get nothingMatchesDot => 'Rien ne correspond.';
  @override
  String get relevantHeading => 'PERTINENT';
  @override
  String get allHeading => 'TOUT';
  @override
  String get doneLower => 'terminé';
  @override
  String get candidateRemote => 'R';
  @override
  String get candidateLocal => 'L';
  @override
  String get newLocalIssueTitle => 'Nouveau ticket local';
  @override
  String get titleHint => 'titre';
  @override
  String get bodyHint => 'corps (markdown)';
  @override
  String get cancelLower => 'annuler';
  @override
  String get createLower => 'créer';
  @override
  String get deleteFailed => 'échec de la suppression';
  @override
  String reviewFailed({required Object error}) =>
      'Échec de la revue : ${error}';
  @override
  String get resolutionFailed => 'échec de la résolution';
  @override
  String get patchBlocksNoCover =>
      'le modèle a renvoyé des blocs de patch qui ne couvraient pas les fichiers en échec';
  @override
  String get applyFailed => 'échec de l\'application';
  @override
  String get emptyOrUnparseablePatch =>
      'le modèle a renvoyé un patch vide ou impossible à analyser';
  @override
  String noModelConfiguredFor({required Object label}) =>
      'aucun modèle configuré pour « ${label} »';
}

// Path: changes
class _Translations$changes$fr extends Translations$changes$en {
  _Translations$changes$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$usage$fr usage =
      _Translations$changes$usage$fr._(_root);
  @override
  late final _Translations$changes$tabs$fr tabs =
      _Translations$changes$tabs$fr._(_root);
  @override
  late final _Translations$changes$tabStrip$fr tabStrip =
      _Translations$changes$tabStrip$fr._(_root);
  @override
  late final _Translations$changes$select$fr select =
      _Translations$changes$select$fr._(_root);
  @override
  late final _Translations$changes$constellationToggle$fr constellationToggle =
      _Translations$changes$constellationToggle$fr._(_root);
  @override
  late final _Translations$changes$nudgeChip$fr nudgeChip =
      _Translations$changes$nudgeChip$fr._(_root);
  @override
  late final _Translations$changes$minimap$fr minimap =
      _Translations$changes$minimap$fr._(_root);
  @override
  late final _Translations$changes$tagInput$fr tagInput =
      _Translations$changes$tagInput$fr._(_root);
  @override
  late final _Translations$changes$composer$fr composer =
      _Translations$changes$composer$fr._(_root);
  @override
  late final _Translations$changes$commit$fr commit =
      _Translations$changes$commit$fr._(_root);
  @override
  late final _Translations$changes$rebase$fr rebase =
      _Translations$changes$rebase$fr._(_root);
  @override
  late final _Translations$changes$editor$fr editor =
      _Translations$changes$editor$fr._(_root);
  @override
  late final _Translations$changes$editorTitles$fr editorTitles =
      _Translations$changes$editorTitles$fr._(_root);
  @override
  late final _Translations$changes$askHint$fr askHint =
      _Translations$changes$askHint$fr._(_root);
  @override
  late final _Translations$changes$fileMenu$fr fileMenu =
      _Translations$changes$fileMenu$fr._(_root);
  @override
  late final _Translations$changes$multiFileMenu$fr multiFileMenu =
      _Translations$changes$multiFileMenu$fr._(_root);
  @override
  late final _Translations$changes$ignoreMenu$fr ignoreMenu =
      _Translations$changes$ignoreMenu$fr._(_root);
  @override
  late final _Translations$changes$discard$fr discard =
      _Translations$changes$discard$fr._(_root);
  @override
  late final _Translations$changes$snack$fr snack =
      _Translations$changes$snack$fr._(_root);
  @override
  late final _Translations$changes$trace$fr trace =
      _Translations$changes$trace$fr._(_root);
  @override
  late final _Translations$changes$cleanTree$fr cleanTree =
      _Translations$changes$cleanTree$fr._(_root);
  @override
  late final _Translations$changes$guardrail$fr guardrail =
      _Translations$changes$guardrail$fr._(_root);
  @override
  late final _Translations$changes$dropHint$fr dropHint =
      _Translations$changes$dropHint$fr._(_root);
  @override
  late final _Translations$changes$diffEmpty$fr diffEmpty =
      _Translations$changes$diffEmpty$fr._(_root);
  @override
  late final _Translations$changes$shelvePill$fr shelvePill =
      _Translations$changes$shelvePill$fr._(_root);
  @override
  late final _Translations$changes$stashAction$fr stashAction =
      _Translations$changes$stashAction$fr._(_root);
  @override
  late final _Translations$changes$stashContents$fr stashContents =
      _Translations$changes$stashContents$fr._(_root);
  @override
  late final _Translations$changes$stashFile$fr stashFile =
      _Translations$changes$stashFile$fr._(_root);
  @override
  late final _Translations$changes$fileRow$fr fileRow =
      _Translations$changes$fileRow$fr._(_root);
  @override
  late final _Translations$changes$resolveStrip$fr resolveStrip =
      _Translations$changes$resolveStrip$fr._(_root);
  @override
  late final _Translations$changes$badge$fr badge =
      _Translations$changes$badge$fr._(_root);
  @override
  late final _Translations$changes$review$fr review =
      _Translations$changes$review$fr._(_root);
  @override
  late final _Translations$changes$commitBtn$fr commitBtn =
      _Translations$changes$commitBtn$fr._(_root);
  @override
  late final _Translations$changes$shapeBtn$fr shapeBtn =
      _Translations$changes$shapeBtn$fr._(_root);
  @override
  late final _Translations$changes$dejaVu$fr dejaVu =
      _Translations$changes$dejaVu$fr._(_root);
  @override
  late final _Translations$changes$identity$fr identity =
      _Translations$changes$identity$fr._(_root);
  @override
  late final _Translations$changes$staleScope$fr staleScope =
      _Translations$changes$staleScope$fr._(_root);
  @override
  late final _Translations$changes$finding$fr finding =
      _Translations$changes$finding$fr._(_root);
  @override
  late final _Translations$changes$muse$fr muse =
      _Translations$changes$muse$fr._(_root);
  @override
  late final _Translations$changes$debug$fr debug =
      _Translations$changes$debug$fr._(_root);
  @override
  late final _Translations$changes$includeSummary$fr includeSummary =
      _Translations$changes$includeSummary$fr._(_root);
  @override
  late final _Translations$changes$status$fr status =
      _Translations$changes$status$fr._(_root);
  @override
  late final _Translations$changes$stash$fr stash =
      _Translations$changes$stash$fr._(_root);
  @override
  late final _Translations$changes$tooltips$fr tooltips =
      _Translations$changes$tooltips$fr._(_root);
  @override
  late final _Translations$changes$mergeEditor$fr mergeEditor =
      _Translations$changes$mergeEditor$fr._(_root);
  @override
  late final _Translations$changes$conflictResolution$fr conflictResolution =
      _Translations$changes$conflictResolution$fr._(_root);
  @override
  late final _Translations$changes$mergeFlow$fr mergeFlow =
      _Translations$changes$mergeFlow$fr._(_root);
  @override
  late final _Translations$changes$constellation$fr constellation =
      _Translations$changes$constellation$fr._(_root);
}

// Path: common
class _Translations$common$fr extends Translations$common$en {
  _Translations$common$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get listSeparator => ', ';
  @override
  String get cancel => 'Annuler';
  @override
  String get close => 'Fermer';
  @override
  String get save => 'Enregistrer';
  @override
  String get delete => 'Supprimer';
  @override
  String get retry => 'Réessayer';
  @override
  String get copy => 'Copier';
  @override
  String get copied => 'Copié';
  @override
  String get done => 'Terminé';
  @override
  String get loading => 'Chargement…';
  @override
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} fichier',
        other: '${n} fichiers',
      );
  @override
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} commit',
        other: '${n} commits',
      );
  @override
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} branche',
        other: '${n} branches',
      );
  @override
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} commit local',
        other: '${n} commits locaux',
      );
  @override
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} commit distant',
        other: '${n} commits distants',
      );
  @override
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} fichier en conflit',
        other: '${n} fichiers en conflit',
      );
  @override
  late final _Translations$common$time$fr time = _Translations$common$time$fr._(
    _root,
  );
  @override
  late final _Translations$common$size$fr size = _Translations$common$size$fr._(
    _root,
  );
}

// Path: diff
class _Translations$diff$fr extends Translations$diff$en {
  _Translations$diff$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$diff$status$fr status =
      _Translations$diff$status$fr._(_root);
  @override
  late final _Translations$diff$toolbar$fr toolbar =
      _Translations$diff$toolbar$fr._(_root);
  @override
  late final _Translations$diff$hunkDropdown$fr hunkDropdown =
      _Translations$diff$hunkDropdown$fr._(_root);
  @override
  String stagingFailed({required Object error}) =>
      'Échec de l\'indexation partielle : ${error}';
  @override
  late final _Translations$diff$trail$fr trail = _Translations$diff$trail$fr._(
    _root,
  );
  @override
  late final _Translations$diff$pinned$fr pinned =
      _Translations$diff$pinned$fr._(_root);
  @override
  late final _Translations$diff$hunkHint$fr hunkHint =
      _Translations$diff$hunkHint$fr._(_root);
  @override
  late final _Translations$diff$binary$fr binary =
      _Translations$diff$binary$fr._(_root);
  @override
  late final _Translations$diff$media$fr media = _Translations$diff$media$fr._(
    _root,
  );
}

// Path: filament
class _Translations$filament$fr extends Translations$filament$en {
  _Translations$filament$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get noRepositoryOpen => 'Aucun dépôt ouvert.';
  @override
  String scanningProgress({required Object scanned, required Object total}) =>
      'analyse de ${scanned} / ${total} fichiers…';
  @override
  String findingsAcrossFiles({required Object count, required Object files}) =>
      '${count} constats dans ${files} fichiers';
  @override
  String copiedFindings({required Object count}) => '${count} constats copiés';
  @override
  String get copy => 'COPIER';
  @override
  String get noFindings => 'Aucun constat de flux d\'exécution.';
  @override
  late final _Translations$filament$severity$fr severity =
      _Translations$filament$severity$fr._(_root);
  @override
  late final _Translations$filament$kind$fr kind =
      _Translations$filament$kind$fr._(_root);
  @override
  String lineLabel({required Object line}) => 'L${line}';
  @override
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class _Translations$history$fr extends Translations$history$en {
  _Translations$history$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$fr commitLede =
      _Translations$history$commitLede$fr._(_root);
  @override
  late final _Translations$history$seismograph$fr seismograph =
      _Translations$history$seismograph$fr._(_root);
  @override
  late final _Translations$history$worldline$fr worldline =
      _Translations$history$worldline$fr._(_root);
  @override
  late final _Translations$history$contextMenu$fr contextMenu =
      _Translations$history$contextMenu$fr._(_root);
  @override
  late final _Translations$history$cherryPick$fr cherryPick =
      _Translations$history$cherryPick$fr._(_root);
  @override
  late final _Translations$history$revert$fr revert =
      _Translations$history$revert$fr._(_root);
  @override
  late final _Translations$history$reflog$fr reflog =
      _Translations$history$reflog$fr._(_root);
  @override
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'Ce commit est plus profond que le ${n} commit chargé.',
        other: 'Ce commit est plus profond que les ${n} commits chargés.',
      );
  @override
  String deleteTagFailed({required Object error}) =>
      'Échec de la suppression de l\'étiquette : ${error}';
  @override
  String get loadingTitle => 'Chargement de l\'historique';
  @override
  String get loadingMessage => 'Lecture des commits récents.';
  @override
  String get unavailableTitle => 'Historique indisponible';
  @override
  String get toggleWorldline => 'Basculer la ligne d\'univers';
  @override
  String get pageTitle => 'Historique';
  @override
  String get viewingLast => 'Derniers';
  @override
  String get commitsUnit => 'commits';
  @override
  String get noCommitSelectedTitle => 'Aucun commit sélectionné';
  @override
  String get noCommitSelectedMessage =>
      'Sélectionnez un commit pour inspecter ses modifications.';
  @override
  String get loadingCommitTitle => 'Chargement du commit';
  @override
  String get loadingCommitMessage => 'Lecture des détails du commit.';
  @override
  String get commitUnavailableTitle => 'Commit indisponible';
  @override
  String get couldNotLoadCommit => 'Impossible de charger le commit.';
  @override
  String get reflogDividerLabel => 'reflog';
  @override
  String get loadReflog => 'Charger le reflog';
  @override
  String get createTag => 'Créer une étiquette';
  @override
  String get newTagName => 'Nom de la nouvelle étiquette';
  @override
  String newTagNameError({required Object error}) =>
      'Nom de la nouvelle étiquette — ${error}';
  @override
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} fichier · toutes modifications',
        other: '${n} fichiers · toutes modifications',
      );
  @override
  String get allChangesLabel => 'toutes modifications';
  @override
  late final _Translations$history$rebase$fr rebase =
      _Translations$history$rebase$fr._(_root);
  @override
  late final _Translations$history$inFlight$fr inFlight =
      _Translations$history$inFlight$fr._(_root);
}

// Path: historySurgery
class _Translations$historySurgery$fr extends Translations$historySurgery$en {
  _Translations$historySurgery$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$historySurgery$chrome$fr chrome =
      _Translations$historySurgery$chrome$fr._(_root);
  @override
  late final _Translations$historySurgery$select$fr select =
      _Translations$historySurgery$select$fr._(_root);
  @override
  late final _Translations$historySurgery$understand$fr understand =
      _Translations$historySurgery$understand$fr._(_root);
  @override
  late final _Translations$historySurgery$confirm$fr confirm =
      _Translations$historySurgery$confirm$fr._(_root);
  @override
  late final _Translations$historySurgery$execute$fr execute =
      _Translations$historySurgery$execute$fr._(_root);
  @override
  late final _Translations$historySurgery$verify$fr verify =
      _Translations$historySurgery$verify$fr._(_root);
  @override
  late final _Translations$historySurgery$forcePush$fr forcePush =
      _Translations$historySurgery$forcePush$fr._(_root);
}

// Path: onboarding
class _Translations$onboarding$fr extends Translations$onboarding$en {
  _Translations$onboarding$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$nav$fr nav =
      _Translations$onboarding$nav$fr._(_root);
  @override
  late final _Translations$onboarding$naming$fr naming =
      _Translations$onboarding$naming$fr._(_root);
  @override
  late final _Translations$onboarding$theme$fr theme =
      _Translations$onboarding$theme$fr._(_root);
  @override
  late final _Translations$onboarding$repo$fr repo =
      _Translations$onboarding$repo$fr._(_root);
  @override
  late final _Translations$onboarding$preview$fr preview =
      _Translations$onboarding$preview$fr._(_root);
}

// Path: orrery
class _Translations$orrery$fr extends Translations$orrery$en {
  _Translations$orrery$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$orrery$header$fr header =
      _Translations$orrery$header$fr._(_root);
  @override
  late final _Translations$orrery$status$fr status =
      _Translations$orrery$status$fr._(_root);
  @override
  late final _Translations$orrery$legend$fr legend =
      _Translations$orrery$legend$fr._(_root);
  @override
  late final _Translations$orrery$node$fr node = _Translations$orrery$node$fr._(
    _root,
  );
  @override
  late final _Translations$orrery$milestone$fr milestone =
      _Translations$orrery$milestone$fr._(_root);
  @override
  late final _Translations$orrery$structure$fr structure =
      _Translations$orrery$structure$fr._(_root);
  @override
  late final _Translations$orrery$rail$fr rail = _Translations$orrery$rail$fr._(
    _root,
  );
  @override
  late final _Translations$orrery$selection$fr selection =
      _Translations$orrery$selection$fr._(_root);
  @override
  late final _Translations$orrery$findingKind$fr findingKind =
      _Translations$orrery$findingKind$fr._(_root);
  @override
  late final _Translations$orrery$findings$fr findings =
      _Translations$orrery$findings$fr._(_root);
  @override
  late final _Translations$orrery$anchor$fr anchor =
      _Translations$orrery$anchor$fr._(_root);
  @override
  late final _Translations$orrery$compare$fr compare =
      _Translations$orrery$compare$fr._(_root);
}

// Path: palette
class _Translations$palette$fr extends Translations$palette$en {
  _Translations$palette$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get active => 'actif';
  @override
  late final _Translations$palette$prefixes$fr prefixes =
      _Translations$palette$prefixes$fr._(_root);
  @override
  late final _Translations$palette$chips$fr chips =
      _Translations$palette$chips$fr._(_root);
  @override
  late final _Translations$palette$predictive$fr predictive =
      _Translations$palette$predictive$fr._(_root);
  @override
  late final _Translations$palette$topTouched$fr topTouched =
      _Translations$palette$topTouched$fr._(_root);
  @override
  late final _Translations$palette$coherence$fr coherence =
      _Translations$palette$coherence$fr._(_root);
  @override
  late final _Translations$palette$keystone$fr keystone =
      _Translations$palette$keystone$fr._(_root);
  @override
  late final _Translations$palette$repoSub$fr repoSub =
      _Translations$palette$repoSub$fr._(_root);
  @override
  late final _Translations$palette$desks$fr desks =
      _Translations$palette$desks$fr._(_root);
  @override
  late final _Translations$palette$actions$fr actions =
      _Translations$palette$actions$fr._(_root);
  @override
  late final _Translations$palette$tools$fr tools =
      _Translations$palette$tools$fr._(_root);
  @override
  late final _Translations$palette$gitCommands$fr gitCommands =
      _Translations$palette$gitCommands$fr._(_root);
  @override
  late final _Translations$palette$pr$fr pr = _Translations$palette$pr$fr._(
    _root,
  );
  @override
  late final _Translations$palette$ai$fr ai = _Translations$palette$ai$fr._(
    _root,
  );
  @override
  late final _Translations$palette$undo$fr undo =
      _Translations$palette$undo$fr._(_root);
  @override
  late final _Translations$palette$navigation$fr navigation =
      _Translations$palette$navigation$fr._(_root);
  @override
  late final _Translations$palette$settings$fr settings =
      _Translations$palette$settings$fr._(_root);
  @override
  late final _Translations$palette$info$fr info =
      _Translations$palette$info$fr._(_root);
  @override
  late final _Translations$palette$debug$fr debug =
      _Translations$palette$debug$fr._(_root);
  @override
  late final _Translations$palette$dev$fr dev = _Translations$palette$dev$fr._(
    _root,
  );
  @override
  late final _Translations$palette$historySurgery$fr historySurgery =
      _Translations$palette$historySurgery$fr._(_root);
  @override
  late final _Translations$palette$orrery$fr orrery =
      _Translations$palette$orrery$fr._(_root);
  @override
  late final _Translations$palette$command$fr command =
      _Translations$palette$command$fr._(_root);
  @override
  late final _Translations$palette$search$fr search =
      _Translations$palette$search$fr._(_root);
  @override
  late final _Translations$palette$wick$fr wick =
      _Translations$palette$wick$fr._(_root);
  @override
  late final _Translations$palette$gitCache$fr gitCache =
      _Translations$palette$gitCache$fr._(_root);
}

// Path: releaseNotes
class _Translations$releaseNotes$fr extends Translations$releaseNotes$en {
  _Translations$releaseNotes$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get versionFallback => 'dev';
  @override
  late final _Translations$releaseNotes$about$fr about =
      _Translations$releaseNotes$about$fr._(_root);
}

// Path: repoSummary
class _Translations$repoSummary$fr extends Translations$repoSummary$en {
  _Translations$repoSummary$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$repoSummary$backbone$fr backbone =
      _Translations$repoSummary$backbone$fr._(_root);
  @override
  late final _Translations$repoSummary$glance$fr glance =
      _Translations$repoSummary$glance$fr._(_root);
  @override
  late final _Translations$repoSummary$heading$fr heading =
      _Translations$repoSummary$heading$fr._(_root);
  @override
  String get historyStarvedCaveat =>
      'Classement limité : le graphe de couplage n\'avait aucune arête (clone récent ou trop peu de commits). L\'ordre des fichiers reflète la taille, pas la centralité structurelle.';
  @override
  late final _Translations$repoSummary$pitch$fr pitch =
      _Translations$repoSummary$pitch$fr._(_root);
  @override
  late final _Translations$repoSummary$region$fr region =
      _Translations$repoSummary$region$fr._(_root);
  @override
  late final _Translations$repoSummary$shape$fr shape =
      _Translations$repoSummary$shape$fr._(_root);
}

// Path: settings
class _Translations$settings$fr extends Translations$settings$en {
  _Translations$settings$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$language$fr language =
      _Translations$settings$language$fr._(_root);
  @override
  late final _Translations$settings$sectionLabels$fr sectionLabels =
      _Translations$settings$sectionLabels$fr._(_root);
  @override
  late final _Translations$settings$errors$fr errors =
      _Translations$settings$errors$fr._(_root);
  @override
  late final _Translations$settings$promptStatus$fr promptStatus =
      _Translations$settings$promptStatus$fr._(_root);
  @override
  late final _Translations$settings$clearData$fr clearData =
      _Translations$settings$clearData$fr._(_root);
  @override
  List<String> get guardrailStageLabels => [
    'Souple',
    'Équilibré',
    'Strict',
    'Paranoïaque',
  ];
  @override
  late final _Translations$settings$guardrailMacro$fr guardrailMacro =
      _Translations$settings$guardrailMacro$fr._(_root);
  @override
  late final _Translations$settings$guardrails$fr guardrails =
      _Translations$settings$guardrails$fr._(_root);
  @override
  late final _Translations$settings$appearance$fr appearance =
      _Translations$settings$appearance$fr._(_root);
  @override
  late final _Translations$settings$retention$fr retention =
      _Translations$settings$retention$fr._(_root);
  @override
  late final _Translations$settings$navigation$fr navigation =
      _Translations$settings$navigation$fr._(_root);
  @override
  late final _Translations$settings$behaviour$fr behaviour =
      _Translations$settings$behaviour$fr._(_root);
  @override
  late final _Translations$settings$retentionClear$fr retentionClear =
      _Translations$settings$retentionClear$fr._(_root);
  @override
  late final _Translations$settings$channels$fr channels =
      _Translations$settings$channels$fr._(_root);
  @override
  late final _Translations$settings$pollResult$fr pollResult =
      _Translations$settings$pollResult$fr._(_root);
  @override
  late final _Translations$settings$keybindingProfile$fr keybindingProfile =
      _Translations$settings$keybindingProfile$fr._(_root);
  @override
  late final _Translations$settings$apiKeys$fr apiKeys =
      _Translations$settings$apiKeys$fr._(_root);
  @override
  late final _Translations$settings$shortcuts$fr shortcuts =
      _Translations$settings$shortcuts$fr._(_root);
  @override
  late final _Translations$settings$toggles$fr toggles =
      _Translations$settings$toggles$fr._(_root);
  @override
  late final _Translations$settings$diffDiffability$fr diffDiffability =
      _Translations$settings$diffDiffability$fr._(_root);
  @override
  late final _Translations$settings$modelSlots$fr modelSlots =
      _Translations$settings$modelSlots$fr._(_root);
  @override
  late final _Translations$settings$modelPicker$fr modelPicker =
      _Translations$settings$modelPicker$fr._(_root);
  @override
  late final _Translations$settings$aiFeatures$fr aiFeatures =
      _Translations$settings$aiFeatures$fr._(_root);
  @override
  late final _Translations$settings$commitEditor$fr commitEditor =
      _Translations$settings$commitEditor$fr._(_root);
  @override
  late final _Translations$settings$review$fr review =
      _Translations$settings$review$fr._(_root);
  @override
  late final _Translations$settings$museHint$fr museHint =
      _Translations$settings$museHint$fr._(_root);
  @override
  late final _Translations$settings$museEditor$fr museEditor =
      _Translations$settings$museEditor$fr._(_root);
  @override
  late final _Translations$settings$museStage$fr museStage =
      _Translations$settings$museStage$fr._(_root);
  @override
  late final _Translations$settings$lensAxis$fr lensAxis =
      _Translations$settings$lensAxis$fr._(_root);
  @override
  late final _Translations$settings$logosLens$fr logosLens =
      _Translations$settings$logosLens$fr._(_root);
  @override
  late final _Translations$settings$sortGuide$fr sortGuide =
      _Translations$settings$sortGuide$fr._(_root);
  @override
  late final _Translations$settings$piggyback$fr piggyback =
      _Translations$settings$piggyback$fr._(_root);
  @override
  late final _Translations$settings$diffStage$fr diffStage =
      _Translations$settings$diffStage$fr._(_root);
  @override
  late final _Translations$settings$undoScope$fr undoScope =
      _Translations$settings$undoScope$fr._(_root);
  @override
  late final _Translations$settings$undoWindow$fr undoWindow =
      _Translations$settings$undoWindow$fr._(_root);
  @override
  late final _Translations$settings$guardrailPhrase$fr guardrailPhrase =
      _Translations$settings$guardrailPhrase$fr._(_root);
  @override
  late final _Translations$settings$reviewGuideHint$fr reviewGuideHint =
      _Translations$settings$reviewGuideHint$fr._(_root);
  @override
  late final _Translations$settings$commitFormat$fr commitFormat =
      _Translations$settings$commitFormat$fr._(_root);
  @override
  late final _Translations$settings$commitPreview$fr commitPreview =
      _Translations$settings$commitPreview$fr._(_root);
  @override
  late final _Translations$settings$externalTools$fr externalTools =
      _Translations$settings$externalTools$fr._(_root);
  @override
  late final _Translations$settings$apiUsage$fr apiUsage =
      _Translations$settings$apiUsage$fr._(_root);
  @override
  late final _Translations$settings$gitea$fr gitea =
      _Translations$settings$gitea$fr._(_root);
  @override
  late final _Translations$settings$wick$fr wick =
      _Translations$settings$wick$fr._(_root);
  @override
  late final _Translations$settings$integrations$fr integrations =
      _Translations$settings$integrations$fr._(_root);
  @override
  late final _Translations$settings$reduceMotion$fr reduceMotion =
      _Translations$settings$reduceMotion$fr._(_root);
  @override
  late final _Translations$settings$resetQuit$fr resetQuit =
      _Translations$settings$resetQuit$fr._(_root);
  @override
  late final _Translations$settings$diagnostics$fr diagnostics =
      _Translations$settings$diagnostics$fr._(_root);
  @override
  late final _Translations$settings$telemetry$fr telemetry =
      _Translations$settings$telemetry$fr._(_root);
  @override
  late final _Translations$settings$flowEngine$fr flowEngine =
      _Translations$settings$flowEngine$fr._(_root);
  @override
  late final _Translations$settings$museStrands$fr museStrands =
      _Translations$settings$museStrands$fr._(_root);
  @override
  late final _Translations$settings$cliPiggyback$fr cliPiggyback =
      _Translations$settings$cliPiggyback$fr._(_root);
  @override
  late final _Translations$settings$header$fr header =
      _Translations$settings$header$fr._(_root);
  @override
  late final _Translations$settings$diagnosticsPanel$fr diagnosticsPanel =
      _Translations$settings$diagnosticsPanel$fr._(_root);
  @override
  late final _Translations$settings$release$fr release =
      _Translations$settings$release$fr._(_root);
  @override
  late final _Translations$settings$providerStatus$fr providerStatus =
      _Translations$settings$providerStatus$fr._(_root);
  @override
  late final _Translations$settings$meridiem$fr meridiem =
      _Translations$settings$meridiem$fr._(_root);
  @override
  late final _Translations$settings$offenders$fr offenders =
      _Translations$settings$offenders$fr._(_root);
}

// Path: sync
class _Translations$sync$fr extends Translations$sync$en {
  _Translations$sync$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$actions$fr actions =
      _Translations$sync$actions$fr._(_root);
  @override
  late final _Translations$sync$panel$fr panel = _Translations$sync$panel$fr._(
    _root,
  );
  @override
  late final _Translations$sync$forcePush$fr forcePush =
      _Translations$sync$forcePush$fr._(_root);
}

// Path: xray
class _Translations$xray$fr extends Translations$xray$en {
  _Translations$xray$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$board$fr board = _Translations$xray$board$fr._(
    _root,
  );
  @override
  late final _Translations$xray$cadence$fr cadence =
      _Translations$xray$cadence$fr._(_root);
  @override
  late final _Translations$xray$cards$fr cards = _Translations$xray$cards$fr._(
    _root,
  );
  @override
  late final _Translations$xray$cardTitle$fr cardTitle =
      _Translations$xray$cardTitle$fr._(_root);
  @override
  late final _Translations$xray$grain$fr grain = _Translations$xray$grain$fr._(
    _root,
  );
  @override
  late final _Translations$xray$header$fr header =
      _Translations$xray$header$fr._(_root);
  @override
  late final _Translations$xray$hotspot$fr hotspot =
      _Translations$xray$hotspot$fr._(_root);
  @override
  late final _Translations$xray$inspector$fr inspector =
      _Translations$xray$inspector$fr._(_root);
  @override
  late final _Translations$xray$loadingCard$fr loadingCard =
      _Translations$xray$loadingCard$fr._(_root);
  @override
  late final _Translations$xray$metabolism$fr metabolism =
      _Translations$xray$metabolism$fr._(_root);
  @override
  late final _Translations$xray$multi$fr multi = _Translations$xray$multi$fr._(
    _root,
  );
  @override
  late final _Translations$xray$recency$fr recency =
      _Translations$xray$recency$fr._(_root);
  @override
  late final _Translations$xray$rings$fr rings = _Translations$xray$rings$fr._(
    _root,
  );
  @override
  late final _Translations$xray$stats$fr stats = _Translations$xray$stats$fr._(
    _root,
  );
  @override
  late final _Translations$xray$stratumLabel$fr stratumLabel =
      _Translations$xray$stratumLabel$fr._(_root);
  @override
  late final _Translations$xray$summary$fr summary =
      _Translations$xray$summary$fr._(_root);
  @override
  late final _Translations$xray$tabs$fr tabs = _Translations$xray$tabs$fr._(
    _root,
  );
  @override
  late final _Translations$xray$trajectory$fr trajectory =
      _Translations$xray$trajectory$fr._(_root);
  @override
  late final _Translations$xray$verdict$fr verdict =
      _Translations$xray$verdict$fr._(_root);
}

// Path: app.cheatsheet
class _Translations$app$cheatsheet$fr extends Translations$app$cheatsheet$en {
  _Translations$app$cheatsheet$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Clavier';
  @override
  String get sectionNavigate => 'naviguer';
  @override
  String get sectionStaging => 'indexation';
  @override
  String get sectionBranchesPrs => 'branches et PR';
  @override
  String get changes => 'Modifications';
  @override
  String get history => 'Historique';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Basculer (toujours)';
  @override
  String get commandPalette => 'Palette de commandes';
  @override
  String get elevatedPalette => 'Palette élevée';
  @override
  String get dismiss => 'Fermer';
  @override
  String get refresh => 'Actualiser';
  @override
  String get nextPrevChange => 'Modif. suiv. / préc.';
  @override
  String get toggleLine => 'Basculer la ligne';
  @override
  String get toggleHunk => 'Basculer la section';
  @override
  String get toggleFile => 'Basculer le fichier';
  @override
  String get pinContext => 'Épingler le contexte';
  @override
  String get commit => 'Valider';
  @override
  String get acceptAiHint => 'Accepter l\'indice IA';
  @override
  String get undo => 'Annuler';
  @override
  String get navigate => 'Naviguer';
  @override
  String get expand => 'Développer';
  @override
  String get checkoutPr => 'Extraire la PR';
  @override
  String get approve => 'Approuver';
  @override
  String get requestChanges => 'Demander des modifications';
  @override
  String profileSwitchHint({required Object profile}) =>
      'profil ${profile} · changez dans Paramètres';
}

// Path: backend.ops
class _Translations$backend$ops$fr extends Translations$backend$ops$en {
  _Translations$backend$ops$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'Fusion';
  @override
  String get pull => 'Tirage';
  @override
  String get apply => 'Application';
  @override
  String get switchOp => 'Bascule';
  @override
  String get sync => 'Synchronisation';
}

// Path: backend.mergeOutcome
class _Translations$backend$mergeOutcome$fr
    extends Translations$backend$mergeOutcome$en {
  _Translations$backend$mergeOutcome$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String cancelled({required Object op}) => '${op} : annulé.';
  @override
  String complete({required Object op}) => '${op} : terminé.';
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} conflit restant — résolvez-le sur la page Modifications.',
        other:
            '${n} conflits restants — résolvez-les sur la page Modifications.',
      );
  @override
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} conflit résolu.',
        other: '${n} conflits résolus.',
      );
  @override
  String uncommittedEdits({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
    n,
    one: '${n} fichier a des modifications non validées — validez-le d\'abord.',
    other:
        '${n} fichiers ont des modifications non validées — validez-les d\'abord.',
  );
}

// Path: changes.usage
class _Translations$changes$usage$fr extends Translations$changes$usage$en {
  _Translations$changes$usage$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String caption({required Object input, required Object output}) =>
      '${input} entrée · ${output} sortie';
  @override
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '${fresh} entrée · ${cached} en cache · ${out} sortie';
  @override
  String get inWord => 'entrée';
  @override
  String get cachedWord => 'cache';
  @override
  String get outWord => 'sortie';
  @override
  String tipIn({required Object value}) => '${value}  entrée';
  @override
  String tipCacheRead({required Object value}) => '${value}  lecture cache';
  @override
  String tipCacheWrite({required Object value}) => '${value}  écriture cache';
  @override
  String tipOut({required Object value}) => '${value}  sortie';
  @override
  String tipReasoning({required Object value}) => '${value}  raisonnement';
  @override
  String tipWallClock({required Object value}) => '${value}s  temps réel';
}

// Path: changes.tabs
class _Translations$changes$tabs$fr extends Translations$changes$tabs$en {
  _Translations$changes$tabs$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get defaultLabel => 'Modifications';
  @override
  String get empty => 'Vide';
}

// Path: changes.tabStrip
class _Translations$changes$tabStrip$fr
    extends Translations$changes$tabStrip$en {
  _Translations$changes$tabStrip$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get newDiffTab => 'Nouvel onglet de diff';
}

// Path: changes.select
class _Translations$changes$select$fr extends Translations$changes$select$en {
  _Translations$changes$select$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get selectAll => 'Tout sélectionner';
  @override
  String get deselectAll => 'Tout désélectionner';
}

// Path: changes.constellationToggle
class _Translations$changes$constellationToggle$fr
    extends Translations$changes$constellationToggle$en {
  _Translations$changes$constellationToggle$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get backToList => 'retour à la liste';
  @override
  String get atlas => 'atlas, voir les candidats au commit';
}

// Path: changes.nudgeChip
class _Translations$changes$nudgeChip$fr
    extends Translations$changes$nudgeChip$en {
  _Translations$changes$nudgeChip$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\nse couple avec ${anchor} · ${pct}%${receipts}';
}

// Path: changes.minimap
class _Translations$changes$minimap$fr extends Translations$changes$minimap$en {
  _Translations$changes$minimap$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get roleNew => 'nouveau';
  @override
  String get roleBridge => 'pont';
  @override
  String get roleHub => 'pivot';
  @override
  String get roleLeaf => 'feuille';
  @override
  String get roleConnected => 'connecté';
  @override
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';
  @override
  String changesWith({required Object name}) => 'change avec ${name}';
  @override
  String get newFile => 'nouveau fichier';
  @override
  String nearOtherChanges({required Object count, required Object dir}) =>
      'près de ${count} autres modifications dans ${dir}';
  @override
  String usuallyChangesWithFile({required Object name}) =>
      '${name} change habituellement avec ce fichier';
}

// Path: changes.tagInput
class _Translations$changes$tagInput$fr
    extends Translations$changes$tagInput$en {
  _Translations$changes$tagInput$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get hint => 'tag...';
}

// Path: changes.composer
class _Translations$changes$composer$fr
    extends Translations$changes$composer$en {
  _Translations$changes$composer$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get hintPlaceholder => 'message de commit...';
  @override
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class _Translations$changes$commit$fr extends Translations$changes$commit$en {
  _Translations$changes$commit$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get primaryCommitChanges => 'Valider les modifications';
  @override
  String get primaryCommitChangesDetail =>
      'HEAD détachée : validez localement sans synchroniser.';
  @override
  String get primaryPublish => 'Valider et publier';
  @override
  String get primaryPublishDetail =>
      'Créer le commit et publier cette branche d\'un coup.';
  @override
  String get primarySync => 'Valider et synchroniser';
  @override
  String get primarySyncDetail =>
      'Créer le commit, puis réconcilier et livrer la branche.';
  @override
  String get primaryPush => 'Valider et pousser';
  @override
  String get primaryPushDetail =>
      'Créer le commit et le pousser immédiatement.';
  @override
  String get amendLast => 'Amender le dernier commit';
  @override
  String amendAnd({required Object action}) => 'Amender et ${action}';
  @override
  String get chooseFile =>
      'Choisissez au moins un fichier pour le prochain commit.';
  @override
  String get writeMessage => 'Écrivez d\'abord un message de commit.';
  @override
  String get committing => 'Validation';
  @override
  String get committingSync => 'Validation et synchronisation';
  @override
  String get committed => 'Validé.';
  @override
  String get undoFailed => 'Échec de l\'annulation.';
  @override
  String get working => 'En cours…';
  @override
  String get commitOnly => 'Valider seulement';
  @override
  String get noRuntimeModels =>
      'Aucun modèle découvert à l\'exécution n\'est disponible pour les messages de commit.';
  @override
  String restoreFailedRetry({required Object err}) =>
      '${err}\nImpossible de restaurer l\'indexation des fichiers exclus ; vérifiez l\'index avant de réessayer.';
  @override
  String committedSummary({required Object summary, required Object hash}) =>
      'Validé ${summary} (${hash}).';
  @override
  String get restoreFailedSync =>
      'Impossible de réindexer les sélections des fichiers exclus ; synchronisation ignorée. Vérifiez l\'index avant de synchroniser.';
  @override
  String get noModelLabel => 'Aucun modèle';
  @override
  String get chooseBeforeGenerate =>
      'Choisissez au moins un fichier avant de générer.';
  @override
  String get aiUnavailable =>
      'L\'IA de message de commit n\'est pas encore disponible.';
  @override
  String get generateFailed => 'Échec de la génération.';
  @override
  String get stageFailed => 'Échec de l\'indexation des fichiers.';
  @override
  String get commitFailed => 'Échec de la validation.';
  @override
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => 'Validé ${summary} (${hash}) et exécuté ${operation}.';
  @override
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
    n,
    one: 'Validé ${summary} (${hash}) ; ${n} conflit résolu.',
    other: 'Validé ${summary} (${hash}) ; ${n} conflits résolus.',
  );
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} conflit restant à résoudre.',
        other: '${n} conflits restants à résoudre.',
      );
  @override
  String syncBlocked({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
    n,
    one:
        'Validation réussie, mais la synchronisation a été bloquée par ${n} fichier non validé.',
    other:
        'Validation réussie, mais la synchronisation a été bloquée par ${n} fichiers non validés.',
  );
  @override
  String syncStalled({required Object message}) =>
      'Validation réussie, mais la synchronisation a calé : ${message}';
  @override
  String syncFailed({required Object message}) =>
      'Validation réussie, mais la synchronisation a échoué : ${message}';
}

// Path: changes.rebase
class _Translations$changes$rebase$fr extends Translations$changes$rebase$en {
  _Translations$changes$rebase$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get continueFailed => 'Impossible de poursuivre le rebasage.';
}

// Path: changes.editor
class _Translations$changes$editor$fr extends Translations$changes$editor$en {
  _Translations$changes$editor$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get closeBarrier => 'Fermer l\'éditeur';
}

// Path: changes.editorTitles
class _Translations$changes$editorTitles$fr
    extends Translations$changes$editorTitles$en {
  _Translations$changes$editorTitles$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  List<String> get any => [
    'cher journal git',
    'par-git-donnez-moi car j\'ai fauté…',
    'nommez cet instant',
    'jactez',
    'parlez !',
    'ta mère était une référence pendante et ton père sentait le point-virgule',
  ];
  @override
  List<String> get short => [
    'oh ?',
    'bonjour :)',
    'au fait :',
    'quelques mots',
    'la version polie',
    'laissez une note',
    'vous disiez… ?',
    'allez, crachez le morceau',
  ];
  @override
  List<String> get mid => [
    'pour mémoire',
    'dites au vous du futur',
    'mais d\'abord ?',
    'comment ça s\'est passé',
    'dans vos propres mots',
    'vous avez fait QUOI ?',
    'bien noté',
    'vous avez toute mon attention',
  ];
  @override
  List<String> get long => [
    'vos rêves, s\'il vous plaît',
    'dites quelque chose de gentil',
    '... et là j\'ai dit :',
    'la postérité vous attend',
    'écrire plus fait disparaître vos bugs',
    'oh wow',
    'les textes sacrés',
  ];
}

// Path: changes.askHint
class _Translations$changes$askHint$fr extends Translations$changes$askHint$en {
  _Translations$changes$askHint$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String round({required Object n}) =>
      'manche ${n} — affinez ou ajoutez du contexte.';
  @override
  String get symptom => 'décrivez le symptôme.';
  @override
  String get broken => 'qu\'est-ce qui est cassé ?';
  @override
  String get bug => 'décrivez le bug.';
  @override
  String get error => 'collez l\'erreur.';
}

// Path: changes.fileMenu
class _Translations$changes$fileMenu$fr
    extends Translations$changes$fileMenu$en {
  _Translations$changes$fileMenu$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get ripple => 'Onde';
  @override
  String get includeCoChanges => 'Inclure les co-changements';
  @override
  String deleteFile({required Object name}) => 'Supprimer ${name}…';
  @override
  String discardChangesTo({required Object name}) =>
      'Abandonner les modifications de ${name}…';
  @override
  String get ignore => 'Ignorer';
  @override
  String get diffTabFromSelection => 'Onglet de diff depuis la sélection';
  @override
  String addSelectedToTab({required Object name}) =>
      'Ajouter la sélection à ${name}';
  @override
  String diffTabFromFile({required Object name}) =>
      'Onglet de diff depuis ${name}';
  @override
  String addFileToTab({required Object file, required Object tab}) =>
      'Ajouter ${file} à ${tab}';
  @override
  String get copyFilePath => 'Copier le chemin du fichier';
  @override
  String get showInExplorer => 'Afficher dans l\'explorateur';
}

// Path: changes.multiFileMenu
class _Translations$changes$multiFileMenu$fr
    extends Translations$changes$multiFileMenu$en {
  _Translations$changes$multiFileMenu$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get cohesionTight => 'fortement couplé';
  @override
  String get cohesionLoose => 'faiblement lié';
  @override
  String get cohesionScattered => 'structurellement dispersé';
  @override
  String get clusterOne => 'tout dans une grappe';
  @override
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      'couvre ${count} grappes (${parts} fichiers)';
  @override
  String clusterSpans({required Object count}) => 'couvre ${count} grappes';
  @override
  String roleLine({required Object count, required Object cohesion}) =>
      '${count} fichiers · ${cohesion}';
  @override
  String usuallyChangesWithGroup({required Object file}) =>
      '${file} change habituellement avec ce groupe';
  @override
  String get splitToNewTab => 'Scinder vers un nouvel onglet';
  @override
  String copyPaths({required Object count}) => 'Copier ${count} chemins';
}

// Path: changes.ignoreMenu
class _Translations$changes$ignoreMenu$fr
    extends Translations$changes$ignoreMenu$en {
  _Translations$changes$ignoreMenu$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String extension({required Object ext}) => 'extension .${ext}';
  @override
  String allSelected({required Object count}) =>
      'Tous les ${count} sélectionnés';
  @override
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'Se couple avec ${n} fichier inclus',
        other: 'Se couple avec ${n} fichiers inclus',
      );
  @override
  String get updateFailed => 'Échec de la mise à jour de .gitignore.';
}

// Path: changes.discard
class _Translations$changes$discard$fr extends Translations$changes$discard$en {
  _Translations$changes$discard$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String deleteTitle({required Object name}) => 'Supprimer ${name} ?';
  @override
  String discardTitle({required Object name}) =>
      'Abandonner les modifications de ${name} ?';
  @override
  String deleteBody({required Object path}) =>
      '${path} sera supprimé du disque. Ceci ne peut pas être annulé depuis l\'application.';
  @override
  String discardBody({required Object path}) =>
      'Toutes les modifications de ${path} seront ramenées à leur état dans HEAD. Ceci est irréversible.';
  @override
  String get discard => 'Abandonner';
  @override
  String deletingFile({required Object name}) => 'Suppression de ${name}';
  @override
  String discardingFile({required Object name}) => 'Abandon de ${name}';
  @override
  String get discardFailed => 'Échec de l\'abandon des modifications.';
  @override
  String discardManyTitle({required Object count}) =>
      'Abandonner les modifications de ${count} fichiers ?';
  @override
  String get discardManyBody =>
      'Les fichiers suivis seront ramenés à leur état dans HEAD ; les fichiers non suivis seront supprimés du disque. Ceci est irréversible.';
  @override
  String discardManyConfirm({required Object count}) => 'Abandonner ${count}';
  @override
  String discardingManyFiles({required Object count}) =>
      'Abandon de ${count} fichiers';
  @override
  String failedOpenExplorer({required Object error}) =>
      'Échec de l\'ouverture de l\'explorateur de fichiers : ${error}';
  @override
  String get someFailed => 'Certains abandons ont échoué.';
}

// Path: changes.snack
class _Translations$changes$snack$fr extends Translations$changes$snack$en {
  _Translations$changes$snack$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get sameWorktree => 'Même arbre de travail — rien à déverser.';
  @override
  String diffFailed({required Object error}) => 'Échec du diff : ${error}';
  @override
  String get deskEmpty =>
      'Le bureau n\'a rien en avance sur vous — déversement vide.';
  @override
  String sourceDesk({required Object label}) => 'bureau ${label}';
  @override
  String shelfReadFailed({required Object error}) =>
      'Échec de lecture de l\'étagère : ${error}';
  @override
  String get shelfEmpty => 'Étagère vide — rien à déverser.';
  @override
  String sourceShelf({required Object label}) => 'étagère ${label}';
  @override
  String noModelConfigured({required Object label}) =>
      'Aucun modèle configuré pour « ${label} ».';
  @override
  String fetchFailed({required Object error}) =>
      'Échec de la récupération : ${error}';
}

// Path: changes.trace
class _Translations$changes$trace$fr extends Translations$changes$trace$en {
  _Translations$changes$trace$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Trace de vérification';
  @override
  String get draftReview => 'Revue brouillon';
}

// Path: changes.cleanTree
class _Translations$changes$cleanTree$fr
    extends Translations$changes$cleanTree$en {
  _Translations$changes$cleanTree$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Arbre de travail propre';
  @override
  String get subtitle => 'Aucune modification indexée ou non indexée détectée.';
  @override
  String get noUpstream => '  ·  aucun amont';
  @override
  String get ahead => ' en avance';
  @override
  String get behind => ' en retard';
  @override
  String get refreshing => 'Actualisation...';
  @override
  String get refresh => 'Actualiser';
  @override
  String get check => 'vérifier';
  @override
  String get checkTooltip => 'Récupérer et actualiser en local.';
  @override
  String get sync => '& sync';
}

// Path: changes.guardrail
class _Translations$changes$guardrail$fr
    extends Translations$changes$guardrail$en {
  _Translations$changes$guardrail$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'Souple';
  @override
  String get balanced => 'Équilibré';
  @override
  String get strict => 'Strict';
  @override
  String get paranoid => 'Paranoïaque';
}

// Path: changes.dropHint
class _Translations$changes$dropHint$fr
    extends Translations$changes$dropHint$en {
  _Translations$changes$dropHint$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get fromShelf =>
      'déposez pour amener ici les changements de cette étagère';
  @override
  String get fromDesk => 'déposez pour amener ici les changements de ce bureau';
}

// Path: changes.diffEmpty
class _Translations$changes$diffEmpty$fr
    extends Translations$changes$diffEmpty$en {
  _Translations$changes$diffEmpty$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Aucun fichier sélectionné';
  @override
  String get message =>
      'Sélectionnez un fichier modifié pour inspecter son diff.';
}

// Path: changes.shelvePill
class _Translations$changes$shelvePill$fr
    extends Translations$changes$shelvePill$en {
  _Translations$changes$shelvePill$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String shelveN({required Object count}) => '↓ ranger ${count}';
  @override
  String get shelve => '↓ ranger';
  @override
  String shelvedCount({required Object count, required Object glyph}) =>
      '${count} rangés ${glyph}';
}

// Path: changes.stashAction
class _Translations$changes$stashAction$fr
    extends Translations$changes$stashAction$en {
  _Translations$changes$stashAction$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get pickUp => 'récupérer';
  @override
  String get peek => 'aperçu';
  @override
  String get toss => 'jeter';
}

// Path: changes.stashContents
class _Translations$changes$stashContents$fr
    extends Translations$changes$stashContents$en {
  _Translations$changes$stashContents$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get reading => 'lecture de l\'étagère…';
  @override
  String get empty => 'étagère vide';
}

// Path: changes.stashFile
class _Translations$changes$stashFile$fr
    extends Translations$changes$stashFile$en {
  _Translations$changes$stashFile$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get binary => 'bin';
}

// Path: changes.fileRow
class _Translations$changes$fileRow$fr extends Translations$changes$fileRow$en {
  _Translations$changes$fileRow$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get stagedLinesOnly => 'valide seulement les lignes indexées';
  @override
  String get doubleClickToggle => 'double-clic : basculer tout le groupe';
  @override
  String get repoRoot => 'Racine du dépôt';
}

// Path: changes.resolveStrip
class _Translations$changes$resolveStrip$fr
    extends Translations$changes$resolveStrip$en {
  _Translations$changes$resolveStrip$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'lecture de ${n} fichier · rédaction de la résolution…',
        other: 'lecture de ${n} fichiers · rédaction de la résolution…',
      );
  @override
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} conflit dans ${files}',
        other: '${n} conflits dans ${files}',
      );
  @override
  String get resolve => 'Résoudre';
  @override
  String get orWith => 'OU AVEC';
  @override
  String resolveWith({required Object label}) => 'résoudre avec ${label}';
  @override
  String resolveWithModel({required Object label, required Object model}) =>
      'résoudre avec ${label}  ·  ${model}';
  @override
  String get resolving => 'résolution…';
  @override
  String resolveWithGlyph({required Object label}) =>
      '↵  résoudre avec ${label}';
  @override
  String get orWithAnother => 'ou avec un autre modèle';
}

// Path: changes.badge
class _Translations$changes$badge$fr extends Translations$changes$badge$en {
  _Translations$changes$badge$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get stagedEdit => 'Modif. indexée';
  @override
  String get edited => 'Modifié';
  @override
  String get stagedAdd => 'Ajout indexé';
  @override
  String get added => 'Ajouté';
  @override
  String get stagedDelete => 'Suppr. indexée';
  @override
  String get deleted => 'Supprimé';
  @override
  String get stagedRename => 'Renommage indexé';
  @override
  String get renamed => 'Renommé';
  @override
  String get stagedCopy => 'Copie indexée';
  @override
  String get copied => 'Copié';
  @override
  String get conflict => 'Conflit';
  @override
  String get stagedTypeChange => 'Chgt de type indexé';
  @override
  String get typeChanged => 'Type changé';
  @override
  String get untracked => 'Non suivi';
}

// Path: changes.review
class _Translations$changes$review$fr extends Translations$changes$review$en {
  _Translations$changes$review$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Revue de code';
  @override
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} fichier inclus',
        other: '${n} fichiers inclus',
      );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} section',
        other: '${n} sections',
      );
  @override
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';
  @override
  String get unavailable => 'Revue indisponible';
  @override
  String get backToDiff => 'Retour au diff';
  @override
  String get verified => 'Vérifiée';
  @override
  String get draftOnly => 'Brouillon seulement';
  @override
  String get runAgain => 'Relancer';
  @override
  String draftShownBelow({required Object error}) =>
      '${error} La revue brouillon est affichée ci-dessous.';
  @override
  String get hideTrace => 'Masquer la trace';
  @override
  String get showTrace => 'Afficher la trace';
  @override
  String get showVerificationTrace => 'Afficher la trace de vérification';
  @override
  String get whyLanded => 'Pourquoi cette revue a abouti ici';
  @override
  String get noFindings => 'Aucun constat';
  @override
  String get findings => 'Constats';
  @override
  String get noEvidenceIssues =>
      'Aucun problème étayé n\'a été relevé pour ce périmètre de commit.';
  @override
  String get observations => 'Observations';
  @override
  String get chooseBeforeReview =>
      'Choisissez au moins un fichier avant de relire.';
  @override
  String get aiUnavailable => 'L\'IA de revue n\'est pas encore disponible.';
  @override
  String get failed => 'Échec de la revue.';
  @override
  String get noRuntimeModels =>
      'Aucun modèle découvert à l\'exécution n\'est disponible pour la revue de commit.';
}

// Path: changes.commitBtn
class _Translations$changes$commitBtn$fr
    extends Translations$changes$commitBtn$en {
  _Translations$changes$commitBtn$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String switchTo({required Object label}) => 'Basculer vers : ${label}\n';
}

// Path: changes.shapeBtn
class _Translations$changes$shapeBtn$fr
    extends Translations$changes$shapeBtn$en {
  _Translations$changes$shapeBtn$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String askingWith({required Object cat}) => 'demande avec ${cat}…';
  @override
  String askWith({required Object cat}) => 'demander avec ${cat}';
  @override
  String get noModel => 'aucun modèle IA configuré';
  @override
  String nextTooltip({required Object cat}) =>
      'suivant : ${cat}  ·  maj-clic pour précédent';
  @override
  String get onlyOne => 'une seule catégorie IA configurée';
}

// Path: changes.dejaVu
class _Translations$changes$dejaVu$fr extends Translations$changes$dejaVu$en {
  _Translations$changes$dejaVu$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required num n,
    required Object pct,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
    n,
    one:
        '${pct}% déjà-vu — ${n} arête fantôme de chronologies écartées touche ce diff',
    other:
        '${pct}% déjà-vu — ${n} arêtes fantômes de chronologies écartées touchent ce diff',
  );
  @override
  String get label => 'déjà-vu';
}

// Path: changes.identity
class _Translations$changes$identity$fr
    extends Translations$changes$identity$en {
  _Translations$changes$identity$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'aucune identité de commit configurée';
  @override
  String asName({required Object name}) => 'en tant que ${name}';
  @override
  String asNameEmail({required Object name, required Object email}) =>
      'en tant que ${name} <${email}>';
  @override
  String asNameSpace({required Object name}) => 'en tant que ${name} ';
  @override
  String emailAngle({required Object email}) => '<${email}>';
  @override
  String get firstCommit => '\npremier commit dans ce dépôt';
  @override
  String get newToRepo => '\nnouveau dans ce dépôt';
}

// Path: changes.staleScope
class _Translations$changes$staleScope$fr
    extends Translations$changes$staleScope$en {
  _Translations$changes$staleScope$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get message => 'la sélection a changé depuis cette exécution';
  @override
  String get rerun => 'relancer';
}

// Path: changes.finding
class _Translations$changes$finding$fr extends Translations$changes$finding$en {
  _Translations$changes$finding$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get openDiff => 'Ouvrir le diff';
  @override
  String get recorded => 'enregistré';
  @override
  String get dismiss => 'Ignorer';
}

// Path: changes.muse
class _Translations$changes$muse$fr extends Translations$changes$muse$en {
  _Translations$changes$muse$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Muse';
  @override
  String get youPulledThis => 'vous avez tiré ceci';
  @override
  String fromIdea({required Object text}) => 'depuis l\'idée : « ${text} »';
  @override
  String get foothold => 'point d\'appui — ';
  @override
  String get brainstormSpew => 'jet de remue-méninges';
  @override
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';
  @override
  String copyN({required Object count}) => 'Copier ${count}';
  @override
  String get clear => 'Effacer';
  @override
  String get chooseBeforeMuse =>
      'Choisissez au moins un fichier avant d\'invoquer la muse.';
  @override
  String get aiUnavailable => 'L\'IA de la Muse n\'est pas encore disponible.';
  @override
  String get failed => 'Échec de la Muse.';
  @override
  String get noRuntimeModels =>
      'Aucun modèle découvert à l\'exécution n\'est disponible pour la muse.';
  @override
  String get needsModel => 'La Muse a besoin d\'au moins un modèle configuré.';
  @override
  String get dreaming => 'la muse rêve...';
}

// Path: changes.debug
class _Translations$changes$debug$fr extends Translations$changes$debug$en {
  _Translations$changes$debug$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Débogage';
  @override
  String round({required Object n}) => '· manche ${n}';
  @override
  String get clear => 'effacer';
  @override
  String get close => 'fermer';
  @override
  String get analyzing => 'analyse du symptôme…';
  @override
  String get describeSymptom =>
      'décrivez un symptôme, puis appuyez sur déboguer.';
  @override
  String get evidenceFor => 'pour';
  @override
  String get evidenceAgainst => 'mais';
  @override
  String get narrowDown => 'ce qui aiderait à cerner :';
  @override
  String get failed => 'Échec du débogage.';
  @override
  String get refinementFailed => 'Échec de l\'affinage du débogage.';
}

// Path: changes.includeSummary
class _Translations$changes$includeSummary$fr
    extends Translations$changes$includeSummary$en {
  _Translations$changes$includeSummary$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'Aucun';
  @override
  String stagedSuffix({required Object count}) => ' · ${count} indexés';
  @override
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'Tous les ${n} fichier${staged}',
        other: 'Tous les ${n} fichiers${staged}',
      );
  @override
  String partial({
    required Object count,
    required Object n,
    required Object staged,
  }) => '${count} sur ${n}${staged}';
  @override
  String shortAll({required Object n, required Object staged}) =>
      'Tous les ${n}${staged}';
}

// Path: changes.status
class _Translations$changes$status$fr extends Translations$changes$status$en {
  _Translations$changes$status$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get unavailableTitle => 'État du dépôt indisponible';
  @override
  String get loadingTitle => 'Chargement de l\'état du dépôt';
  @override
  String get loadingMessage => 'Lecture de l\'arbre de travail.';
}

// Path: changes.stash
class _Translations$changes$stash$fr extends Translations$changes$stash$en {
  _Translations$changes$stash$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get appliedWithConflicts =>
      'Remisage appliqué avec des conflits — résolvez-les sur la page Modifications (l\'entrée de remisage a été conservée).';
  @override
  String get couldNotPop => 'Impossible de dépiler le remisage.';
  @override
  String get listChanged =>
      'La liste des remisages a changé ; suppression ignorée. Réessayez.';
  @override
  String get droppingStash => 'Suppression du remisage';
}

// Path: changes.tooltips
class _Translations$changes$tooltips$fr
    extends Translations$changes$tooltips$en {
  _Translations$changes$tooltips$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get commitGenerating => 'génération du message de commit...';
  @override
  String get commitPreparing => 'préparation du message de commit...';
  @override
  String get commitSelectFile =>
      'sélectionnez au moins un fichier pour générer un message de commit.';
  @override
  String get commitConfigure =>
      'configurez le message de commit dans Paramètres > Dynamiques comportementales > Messages de commit.';
  @override
  String get fastFallback => 'rapide';
  @override
  String commitGenerateWith({required Object label}) =>
      'générer le message de commit avec le modèle ${label}';
  @override
  String get museConsulting => 'consultation de la muse...';
  @override
  String get showMuse => 'afficher la muse';
  @override
  String get museSelectFile => 'sélectionnez au moins un fichier pour la muse.';
  @override
  String get showMuseError => 'afficher l\'erreur de la muse';
  @override
  String get museAsk => 'demander une direction à la muse';
  @override
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => 'demander une direction à la muse\n${brainstorm} → ${synthesis}';
  @override
  String get qualityFallback => 'qualité';
  @override
  String get reviewing => 'revue en cours...';
  @override
  String get showReview => 'afficher la revue';
  @override
  String get reviewPreparing => 'préparation de la revue de commit...';
  @override
  String get reviewSelectFile => 'sélectionnez au moins un fichier à relire.';
  @override
  String get reviewConfigure =>
      'configurez l\'IA de revue dans les paramètres.';
  @override
  String get viewingReview => 'affichage de la revue';
  @override
  String reviewWith({required Object guardrail, required Object label}) =>
      'revue ${guardrail} avec le modèle ${label}';
}

// Path: changes.mergeEditor
class _Translations$changes$mergeEditor$fr
    extends Translations$changes$mergeEditor$en {
  _Translations$changes$mergeEditor$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get resolutionYours => 'vôtre';
  @override
  String get resolutionTheirs => 'leur';
  @override
  String get resolutionCustom => 'personnalisé';
  @override
  String get keepBoth => 'garder les deux';
  @override
  late final _Translations$changes$mergeEditor$trust$fr trust =
      _Translations$changes$mergeEditor$trust$fr._(_root);
  @override
  String get allResolved => 'tout résolu';
  @override
  String get resolveEasy => 'résoudre les conflits faciles';
  @override
  String get base => 'base';
  @override
  String get cancel => 'annuler';
  @override
  String get save => 'enregistrer';
  @override
  String get complete => 'terminer';
  @override
  String get nextFile => 'fichier suivant';
  @override
  String get edit => 'modifier';
  @override
  String get auto => 'auto';
  @override
  String get undo => 'annuler';
  @override
  late final _Translations$changes$mergeEditor$keyHints$fr keyHints =
      _Translations$changes$mergeEditor$keyHints$fr._(_root);
  @override
  String get favoredTooltip =>
      'structurellement favorisé par l\'analyse de couplage';
  @override
  String get newOnBothSides => '(nouveau des deux côtés)';
  @override
  String writeFailed({required Object error}) =>
      'Échec de l\'écriture des fichiers résolus : ${error}';
  @override
  String neighborsCoChanged({required Object changed, required Object total}) =>
      '${changed}/${total} voisins co-changés';
  @override
  String integrity({required Object pct}) => 'intégrité ${pct}%';
  @override
  String reviewer({required Object name}) => 'relecteur : ${name}';
}

// Path: changes.conflictResolution
class _Translations$changes$conflictResolution$fr
    extends Translations$changes$conflictResolution$en {
  _Translations$changes$conflictResolution$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String noModelConfigured({required Object category}) =>
      'Aucun modèle configuré pour « ${category} ». Définissez-en un dans Paramètres → IA.';
  @override
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} fichier sensible ignoré — résolvez à la main.',
        other: '${n} fichiers sensibles ignorés — résolvez à la main.',
      );
  @override
  String get couldNotReadFiles => 'Impossible de lire les fichiers en conflit.';
  @override
  String blockedSecret({required Object secret}) =>
      'Bloqué — un fichier en conflit semble contenir un ${secret}. Résolvez à la main.';
  @override
  String resolutionFailed({required Object error}) =>
      'Échec de la résolution : ${error}';
  @override
  String mergeResolutionLabel({
    required Object resolved,
    required Object total,
    required Object category,
  }) => '◇ résolution de fusion · ${resolved}/${total} fichiers · ${category}';
  @override
  String conflictSummary({
    required Object op,
    required Object conflicts,
    required Object files,
  }) => '${op} · ${conflicts} dans ${files}';
  @override
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} conflit',
        other: '${n} conflits',
      );
  @override
  String get mergeEditorButton => '⇋ éditeur de fusion';
  @override
  String get noAiModel => 'aucun modèle IA';
  @override
  String get later => 'plus tard';
  @override
  String get discard => 'abandonner';
  @override
  String get resolveWithAi => '◇ résoudre avec l\'IA';
  @override
  String get otherModel => 'autre modèle';
  @override
  String withModel({required Object model}) => 'avec ${model}';
}

// Path: changes.mergeFlow
class _Translations$changes$mergeFlow$fr
    extends Translations$changes$mergeFlow$en {
  _Translations$changes$mergeFlow$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$mergeFlow$op$fr op =
      _Translations$changes$mergeFlow$op$fr._(_root);
  @override
  String get pushFailed => 'Échec de la poussée';
  @override
  String get rebasedAndPushed => 'Rebasé et poussé.';
  @override
  String switchedTo({required Object name}) => 'Basculé vers ${name}.';
  @override
  String get switchFailed => 'Échec de la bascule.';
  @override
  String switchedToCarried({required Object name}) =>
      'Basculé vers ${name} (changements reportés).';
  @override
  String get alreadyUpToDate => 'Déjà à jour.';
  @override
  String merged({required Object upstream, required Object n}) =>
      '${upstream} fusionné (${n} fichiers).';
  @override
  String get rebaseNotConverge =>
      'Le rebasage n\'a pas convergé — résolvez manuellement.';
  @override
  String get rebased => 'Rebasé.';
  @override
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'Rebasé (résolu ${n} fichier).',
        other: 'Rebasé (résolu ${n} fichiers).',
      );
  @override
  String get detachedHead =>
      'Impossible de synchroniser : état HEAD détachée. Basculez d\'abord sur une branche.';
  @override
  String get publishFailed => 'Échec de la publication.';
  @override
  String get noRemote =>
      'Aucun distant configuré. Ajoutez-en un pour publier cette branche.';
  @override
  String get failed => 'échec';
}

// Path: changes.constellation
class _Translations$changes$constellation$fr
    extends Translations$changes$constellation$en {
  _Translations$changes$constellation$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get axisStructure => 'STRUCTURE';
  @override
  String get axisCoChange => 'CO-CHANGEMENT';
  @override
  String get axisSpectralProfile => 'PROFIL SPECTRAL';
  @override
  String get axisPathSiblings => 'FRÈRES DE CHEMIN';
  @override
  String get axisDiffStructure => 'STRUCTURE DU DIFF';
  @override
  String get axisSpectral => 'SPECTRAL';
  @override
  String get titleUnsorted => 'NON TRIÉ';
  @override
  String get titleSingleton => 'SINGLETON';
  @override
  String get titleMixed => 'MIXTE';
  @override
  String get untie => 'délier';
  @override
  String get bind => 'lier';
  @override
  String get emptyClusters => 'aucune grappe pour l\'instant';
}

// Path: common.time
class _Translations$common$time$fr extends Translations$common$time$en {
  _Translations$common$time$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get now => 'maintenant';
  @override
  String get justNow => 'à l\'instant';
  @override
  String get today => 'AUJOURD\'HUI';
  @override
  String minutesAgo({required Object n}) => 'il y a ${n} min';
  @override
  String hoursAgo({required Object n}) => 'il y a ${n} h';
  @override
  String daysAgo({required Object n}) => 'il y a ${n} j';
  @override
  String weeksAgo({required Object n}) => 'il y a ${n} sem';
  @override
  String monthsAgo({required Object n}) => 'il y a ${n} mois';
  @override
  String yearsAgo({required Object n}) => 'il y a ${n} an';
  @override
  String minutesShort({required Object n}) => '${n} min';
  @override
  String hoursShort({required Object n}) => '${n} h';
  @override
  String daysShort({required Object n}) => '${n} j';
  @override
  String weeksShort({required Object n}) => '${n} sem';
  @override
  String monthsShort({required Object n}) => '${n} mois';
  @override
  String yearsShort({required Object n}) => '${n} an';
  @override
  String commitMonthsShort({required Object n}) => '${n} mois';
  @override
  String get idle => 'inactif';
  @override
  String idleDays({required Object n}) => 'inactif ${n} j';
  @override
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'inactif ${n} an',
        other: 'inactif ${n} ans',
      );
  @override
  List<String> get monthAbbrevs => [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];
}

// Path: common.size
class _Translations$common$size$fr extends Translations$common$size$en {
  _Translations$common$size$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String bytes({required Object n}) => '${n} o';
  @override
  String kb({required Object n}) => '${n} Ko';
  @override
  String mb({required Object n}) => '${n} Mo';
  @override
  String gb({required Object n}) => '${n} Go';
}

// Path: diff.status
class _Translations$diff$status$fr extends Translations$diff$status$en {
  _Translations$diff$status$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Chargement du diff';
  @override
  String get loadingMessage => 'Lecture des modifications du fichier.';
  @override
  String get unavailableTitle => 'Diff indisponible';
  @override
  String get noChangesTitle => 'Aucune modification';
  @override
  String get noChangesMessage =>
      'Ce fichier n\'a aucun contenu de diff à afficher.';
}

// Path: diff.toolbar
class _Translations$diff$toolbar$fr extends Translations$diff$toolbar$en {
  _Translations$diff$toolbar$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get searchHint => 'rechercher dans le diff...';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} ligne',
        other: '${n} lignes',
      );
  @override
  String get blameLoading => 'blame...';
  @override
  String get blame => 'blame';
  @override
  String get wearMapOn => 'usure · activé';
  @override
  String get wearMapOnHint => 'carte d\'usure activée — cliquez pour masquer';
  @override
  String get wearMapOffHint =>
      'afficher la carte d\'usure (heatmap d\'activité)';
  @override
  String get trailBadge => '· trace';
}

// Path: diff.hunkDropdown
class _Translations$diff$hunkDropdown$fr
    extends Translations$diff$hunkDropdown$en {
  _Translations$diff$hunkDropdown$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip =>
      'Aller au bloc de modification. Git les appelle des sections (hunks).';
  @override
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} modification',
        other: '${n} modifications',
      );
}

// Path: diff.trail
class _Translations$diff$trail$fr extends Translations$diff$trail$en {
  _Translations$diff$trail$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'chargement de la trace...';
  @override
  String get noHistory => 'aucun historique trouvé';
  @override
  String get nowWorkingCopy => 'maintenant · copie de travail';
  @override
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class _Translations$diff$pinned$fr extends Translations$diff$pinned$en {
  _Translations$diff$pinned$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get loadingContext => 'chargement du contexte épinglé';
  @override
  String get pageManifold => 'Manifold';
  @override
  String get pageSignals => 'Signaux';
  @override
  String get echoesTitle => 'Échos';
  @override
  String get technicalLedger => 'Registre technique';
  @override
  String get noSecondaryCues => 'Aucun indice secondaire détecté.';
  @override
  String get linkedPaths => 'Chemins liés';
  @override
  String moreCount({required Object n}) => '+${n} de plus';
  @override
  String get localSeam => 'Couture locale';
  @override
  String get sharedOwnership => 'propriété partagée';
  @override
  String get historyWarmingUp => 'Historique en préchauffe';
  @override
  String echoesTotal({required Object n}) => '${n} AU TOTAL';
  @override
  String get noEchoes => 'Aucun écho dans ce diff.';
  @override
  String openRelatedFile({required Object name}) =>
      'Ouvrir le fichier lié ${name}';
  @override
  String inspectFile({required Object name}) => 'inspecter ${name}';
  @override
  String get jumpEcho => 'aller à l\'écho';
  @override
  String get copyLine => 'copier la ligne';
  @override
  String get signalTempo => 'T';
  @override
  String get signalNovelty => 'N';
  @override
  String get signalReach => 'P';
  @override
  late final _Translations$diff$pinned$tempo$fr tempo =
      _Translations$diff$pinned$tempo$fr._(_root);
  @override
  late final _Translations$diff$pinned$tone$fr tone =
      _Translations$diff$pinned$tone$fr._(_root);
  @override
  late final _Translations$diff$pinned$summary$fr summary =
      _Translations$diff$pinned$summary$fr._(_root);
  @override
  late final _Translations$diff$pinned$tightness$fr tightness =
      _Translations$diff$pinned$tightness$fr._(_root);
  @override
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept} (${tightness})';
  @override
  String get storyWhyThisMatters => 'Pourquoi c\'est important';
  @override
  String get storyConfidence => 'Confiance';
  @override
  String get storySecondarySignal => 'Signal secondaire';
  @override
  String get storyNeighbourhood => 'Voisinage';
  @override
  String neighbourhoodDetail({required Object name}) =>
      'Cette ligne est proche de ${name} dans le champ actuel de la base de code.';
  @override
  String get propagationLane => 'Voie de propagation';
  @override
  String propagationLaneNamed({required Object lane}) =>
      'Voie de propagation : ${lane}';
  @override
  late final _Translations$diff$pinned$witness$fr witness =
      _Translations$diff$pinned$witness$fr._(_root);
  @override
  late final _Translations$diff$pinned$integrity$fr integrity =
      _Translations$diff$pinned$integrity$fr._(_root);
  @override
  late final _Translations$diff$pinned$related$fr related =
      _Translations$diff$pinned$related$fr._(_root);
  @override
  late final _Translations$diff$pinned$axis$fr axis =
      _Translations$diff$pinned$axis$fr._(_root);
}

// Path: diff.hunkHint
class _Translations$diff$hunkHint$fr extends Translations$diff$hunkHint$en {
  _Translations$diff$hunkHint$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String hiddenCount({required Object n}) => '${n} masqués';
  @override
  String get landing => 'atterrissage';
}

// Path: diff.binary
class _Translations$diff$binary$fr extends Translations$diff$binary$en {
  _Translations$diff$binary$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String tooLargeToPreview({required Object size}) =>
      '${size} Mo (trop grand pour l\'aperçu)';
  @override
  String get unableToLoadBlob => 'Impossible de charger le blob';
  @override
  String get omittedKindMedia => 'média';
  @override
  String get omittedKindBinary => 'binaire';
  @override
  String omittedStub({required Object kind}) => '${kind} · masqué';
}

// Path: diff.media
class _Translations$diff$media$fr extends Translations$diff$media$en {
  _Translations$diff$media$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get unableToDecodeImage => 'Impossible de décoder l\'image';
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
  String get stateAdded => 'ajouté';
  @override
  String get stateDeleted => 'supprimé';
  @override
  String get stateModified => 'modifié';
  @override
  String get fallbackFormatName => 'Binaire';
}

// Path: filament.severity
class _Translations$filament$severity$fr
    extends Translations$filament$severity$en {
  _Translations$filament$severity$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get critical => 'critique';
  @override
  String get warn => 'alerte';
  @override
  String get info => 'info';
  @override
  String get joint => 'joint';
}

// Path: filament.kind
class _Translations$filament$kind$fr extends Translations$filament$kind$en {
  _Translations$filament$kind$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get staleValue => 'valeur périmée';
  @override
  String get temporalShift => 'décalage temporel';
  @override
  String get contextInversion => 'inversion de contexte';
  @override
  String get contradictoryFlow => 'flux contradictoire';
}

// Path: history.commitLede
class _Translations$history$commitLede$fr
    extends Translations$history$commitLede$en {
  _Translations$history$commitLede$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$semantics$fr semantics =
      _Translations$history$commitLede$semantics$fr._(_root);
}

// Path: history.seismograph
class _Translations$history$seismograph$fr
    extends Translations$history$seismograph$en {
  _Translations$history$seismograph$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get rootTrackLabel => '(racine)';
  @override
  String dirTrackLabel({required Object name}) => '(${name})';
  @override
  String moreLabel({required Object n}) => '+${n} de plus';
  @override
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} fichier dans ${path}/',
        other: '${n} fichiers dans ${path}/',
      );
  @override
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} fichier de plus',
        other: '${n} fichiers de plus',
      );
  @override
  String get breadcrumbAll => 'tout';
  @override
  String breadcrumbCurrentFocus({required Object target}) =>
      'Focus actuel : ${target}';
  @override
  String get breadcrumbViewAllChanges =>
      'Voir toutes les modifications de ce commit';
  @override
  String breadcrumbDrillUpTo({required Object target}) =>
      'Remonter vers ${target}';
  @override
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
    n,
    one: '${n} fichier  +${adds}  -${dels}',
    other: '${n} fichiers  +${adds}  -${dels}',
  );
  @override
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} sous-dossier',
        other: '${n} sous-dossiers',
      );
  @override
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}, ${adds} ajoutées, ${dels} supprimées';
  @override
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
    n,
    one: '${n} fichier, ${adds} ajoutées, ${dels} supprimées',
    other: '${n} fichiers, ${adds} ajoutées, ${dels} supprimées',
  );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} section',
        other: '${n} sections',
      );
  @override
  String get largestChangeInView => 'plus grande modification de cette vue';
  @override
  String get conflictedTag => 'en conflit';
  @override
  String get dirtyTag => 'sale';
  @override
  String get drillInTag => 'creuser';
  @override
  String get changeTypeRenamed => 'renommé';
  @override
  String get changeTypeCopied => 'copié';
  @override
  String get changeTypeTypechange => 'type changé';
  @override
  String get changeTypeConflict => 'conflit';
  @override
  String get coreFile => 'fichier cœur';
  @override
  String get staleFile => 'périmé';
  @override
  String get filterPathHint => 'filtrer le chemin';
  @override
  String get escHint => 'échap';
}

// Path: history.worldline
class _Translations$history$worldline$fr
    extends Translations$history$worldline$en {
  _Translations$history$worldline$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get closeWorldline => 'Fermer la ligne d\'univers';
  @override
  String get dragToOpenWorldline => 'Glisser pour ouvrir la ligne d\'univers';
}

// Path: history.contextMenu
class _Translations$history$contextMenu$fr
    extends Translations$history$contextMenu$en {
  _Translations$history$contextMenu$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get currentBranchFallback => 'branche actuelle';
  @override
  String applyCommitOnto({required Object branch}) =>
      'Appliquer les changements du commit sur ${branch}';
  @override
  String revertCommitOn({required Object branch}) =>
      'Annuler les changements du commit sur ${branch}';
}

// Path: history.cherryPick
class _Translations$history$cherryPick$fr
    extends Translations$history$cherryPick$en {
  _Translations$history$cherryPick$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Picorage en pause. Terminez les conflits restants sur la page Modifications.';
  @override
  String failed({required Object error}) => 'Échec du picorage : ${error}';
  @override
  String pickedResolved({required Object short}) =>
      'Picoré ${short} (conflits résolus)';
  @override
  String picked({required Object short}) => 'Picoré ${short}';
}

// Path: history.revert
class _Translations$history$revert$fr extends Translations$history$revert$en {
  _Translations$history$revert$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Annulation en pause. Terminez les conflits restants sur la page Modifications.';
  @override
  String failed({required Object error}) => 'Échec de l\'annulation : ${error}';
  @override
  String revertedResolved({required Object short}) =>
      'Annulé ${short} (conflits résolus)';
  @override
  String reverted({required Object short}) => 'Annulé ${short}';
}

// Path: history.reflog
class _Translations$history$reflog$fr extends Translations$history$reflog$en {
  _Translations$history$reflog$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get createBranchFromHere => 'Créer une branche à partir d\'ici…';
  @override
  String get copyCommitHash => 'Copier le hash du commit';
  @override
  String get createBranchDialogTitle =>
      'Créer une branche depuis l\'entrée du reflog';
  @override
  String anchorLine({required Object short, required Object summary}) =>
      'Ancre : ${short}  ·  ${summary}';
  @override
  String get branchNameHint => 'nom de branche';
  @override
  String get createAction => 'Créer';
  @override
  String createBranchFailed({required Object error}) =>
      'Échec de la création de la branche : ${error}';
  @override
  String branchCreatedAt({required Object name, required Object short}) =>
      'Branche « ${name} » créée à ${short}.';
}

// Path: history.rebase
class _Translations$history$rebase$fr extends Translations$history$rebase$en {
  _Translations$history$rebase$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String firstCommitCannotBe({required Object action}) =>
      'Le premier commit ne peut pas être ${action}';
  @override
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'Rebaser ${n} commit',
        other: 'Rebaser ${n} commits',
      );
  @override
  String get resetLabel => 'réinitialiser';
  @override
  String get dragToReorderHint =>
      'glissez pour réordonner, choisissez l\'action par commit';
  @override
  String get newMessageHint => 'nouveau message';
  @override
  String get runningEllipsis => '…';
  @override
  String get startRebase => 'Démarrer le rebasage';
}

// Path: history.inFlight
class _Translations$history$inFlight$fr
    extends Translations$history$inFlight$en {
  _Translations$history$inFlight$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'EN VOL';
  @override
  String get deskFallbackLabel => 'bureau';
}

// Path: historySurgery.chrome
class _Translations$historySurgery$chrome$fr
    extends Translations$historySurgery$chrome$en {
  _Translations$historySurgery$chrome$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chirurgie de l\'historique';
  @override
  String get alphaBadge => 'alpha';
  @override
  String get dryRunBadge => 'À BLANC';
}

// Path: historySurgery.select
class _Translations$historySurgery$select$fr
    extends Translations$historySurgery$select$en {
  _Translations$historySurgery$select$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get prompt => 'Sélectionnez les fichiers à retirer de l\'historique';
  @override
  String selectedCount({required Object n}) => '${n} sélectionnés';
  @override
  String get searchHint => 'rechercher...';
  @override
  String get readingTree => 'lecture de l\'arbre...';
  @override
  String get continueDisabled => 'sélectionnez des fichiers pour continuer';
  @override
  String get continueEnabled => 'continuer →';
  @override
  String toPurgeCount({required Object n}) => '${n} à purger';
  @override
  String get analyzing => 'analyse...';
  @override
  String get riskLow => 'risque faible';
  @override
  String get riskModerate => 'risque modéré';
  @override
  String get riskHigh => 'risque élevé';
  @override
  String get impactCommitsLabel => 'commits';
  @override
  String get impactBranchesLabel => 'branches';
  @override
  String get impactWorktreesLabel => 'arbres de travail';
  @override
  String get impactCouplingLabel => 'couplage';
  @override
  String get impactCouplingIsland => 'îlot';
  @override
  String impactCouplingNeighbors({required Object n}) => '${n} voisins';
  @override
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class _Translations$historySurgery$understand$fr
    extends Translations$historySurgery$understand$en {
  _Translations$historySurgery$understand$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get heading => 'Comment ça marche';
  @override
  String get backupTitle => 'Sauvegarde';
  @override
  String get backupBody =>
      'Chaque réf de branche et d\'étiquette est copiée dans un espace de noms de sauvegarde avant tout changement. En cas de problème, un clic restaure l\'état d\'origine.';
  @override
  String get rewriteTitle => 'Réécriture';
  @override
  String get rewriteBody =>
      'Chaque commit est parcouru de la racine à la pointe. Pour chaque commit contenant les fichiers ciblés, un nouveau commit est créé avec ces fichiers retirés de l\'arbre. Les chaînes de parents sont remappées pour préserver la topologie. ';
  @override
  String rewriteSummary({required Object affected, required Object total}) =>
      '${affected} des ${total} commits seront réécrits.';
  @override
  String get updateRefsTitle => 'Mise à jour des réfs';
  @override
  String get updateRefsBody =>
      'Les pointeurs de branche et d\'étiquette sont déplacés vers les nouveaux SHA de commits. Les anciens objets subsistent jusqu\'au ramasse-miettes. ';
  @override
  String worktreesNeedRecheckout({required Object n}) =>
      'Vos ${n} arbre(s) de travail devront être re-extraits.';
  @override
  String get noWorktreesAffected => 'Aucun arbre de travail n\'est affecté.';
  @override
  String get forcePushTitle => 'Poussée forcée';
  @override
  String get forcePushBody =>
      'Après vérification de la purge, vous choisissez les branches à forcer. Utilise --force-with-lease pour échouer sans risque si quelqu\'un d\'autre a poussé entre-temps.';
  @override
  String get plumbingNote =>
      'Contrairement à filter-repo ou BFG, ceci passe entièrement par les commandes de plomberie git (cat-file, mktree, commit-tree, update-ref). Aucune dépendance externe. Le suivi des renommages suit une chaîne par fichier — si un fichier a été copié et les deux copies renommées indépendamment, vérifiez le résultat de la purge après exécution.';
  @override
  String get back => '← Retour';
  @override
  String get continueLabel => 'J\'ai compris, continuer →';
}

// Path: historySurgery.confirm
class _Translations$historySurgery$confirm$fr
    extends Translations$historySurgery$confirm$en {
  _Translations$historySurgery$confirm$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String commitsRewritten({required Object n}) =>
      '${n} commits seront réécrits';
  @override
  String get forcePushRequired =>
      'Une poussée forcée sera nécessaire pour les branches distantes';
  @override
  String worktreesRecheckout({required Object n}) =>
      '${n} arbres de travail devront être re-extraits';
  @override
  String stashesInvalid({required Object n}) =>
      '${n} remisages peuvent devenir invalides';
  @override
  String get heading => 'Cette opération réécrit l\'historique git';
  @override
  String get subheading =>
      'Elle ne peut pas être annulée automatiquement après une poussée forcée.';
  @override
  String typeHint({required Object word}) => 'tapez ${word}';
  @override
  String get goBack => 'Revenir';
  @override
  String get begin => 'Commencer la chirurgie';
}

// Path: historySurgery.execute
class _Translations$historySurgery$execute$fr
    extends Translations$historySurgery$execute$en {
  _Translations$historySurgery$execute$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => 'Préparation...';
  @override
  String get backingUpRefs => 'Sauvegarde des réfs...';
  @override
  String get rewritingCommits => 'Réécriture des commits...';
  @override
  String get updatingRefs => 'Mise à jour des réfs...';
}

// Path: historySurgery.verify
class _Translations$historySurgery$verify$fr
    extends Translations$historySurgery$verify$en {
  _Translations$historySurgery$verify$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get complete => 'Chirurgie terminée';
  @override
  String get failed => 'Chirurgie échouée';
  @override
  String get commitsRewrittenLabel => 'Commits réécrits';
  @override
  String get refsUpdatedLabel => 'Réfs mises à jour';
  @override
  String get oldHeadLabel => 'Ancien HEAD';
  @override
  String get newHeadLabel => 'Nouveau HEAD';
  @override
  String get purgeVerifiedLabel => 'Purge vérifiée';
  @override
  String get purgeClean => 'propre';
  @override
  String get purgeTracesRemain => 'DES TRACES SUBSISTENT';
  @override
  String get displacedWorktrees => 'Arbres de travail déplacés';
  @override
  String get undoSurgery => 'Annuler la chirurgie';
  @override
  String get rolledBack => 'Retour aux réfs de sauvegarde effectué.';
  @override
  String get done => 'Terminé';
}

// Path: historySurgery.forcePush
class _Translations$historySurgery$forcePush$fr
    extends Translations$historySurgery$forcePush$en {
  _Translations$historySurgery$forcePush$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get pushing => 'poussée...';
  @override
  String get forcePushAll => 'Tout forcer';
  @override
  String get confirmPush => 'confirmer la poussée';
  @override
  String get cancel => 'annuler';
}

// Path: onboarding.nav
class _Translations$onboarding$nav$fr extends Translations$onboarding$nav$en {
  _Translations$onboarding$nav$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get back => 'Retour';
  @override
  String get continueLabel => 'Continuer';
  @override
  String get letsGo => 'C\'est parti';
}

// Path: onboarding.naming
class _Translations$onboarding$naming$fr
    extends Translations$onboarding$naming$en {
  _Translations$onboarding$naming$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'qu\'est-ce que ça représente pour vous ?';
  @override
  String get questionEmphasis => 'ça';
  @override
  String get iAmPrefix => 'Je suis ';
  @override
  String get iAmSuffix => ' , votre client Git personnel.';
}

// Path: onboarding.theme
class _Translations$onboarding$theme$fr
    extends Translations$onboarding$theme$en {
  _Translations$onboarding$theme$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'habillez ${name}.';
  @override
  String get themesHeader => 'THÈMES';
  @override
  String get keybindingsHeader => 'RACCOURCIS';
  @override
  String get previewBadge => 'aperçu';
  @override
  String get useDefaults => 'valeurs par défaut';
}

// Path: onboarding.repo
class _Translations$onboarding$repo$fr extends Translations$onboarding$repo$en {
  _Translations$onboarding$repo$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'pointez ${name} vers quelque chose.';
  @override
  String get later => 'je ferai ça plus tard';
  @override
  late final _Translations$onboarding$repo$doors$fr doors =
      _Translations$onboarding$repo$doors$fr._(_root);
  @override
  late final _Translations$onboarding$repo$cloneForm$fr cloneForm =
      _Translations$onboarding$repo$cloneForm$fr._(_root);
  @override
  late final _Translations$onboarding$repo$pickers$fr pickers =
      _Translations$onboarding$repo$pickers$fr._(_root);
  @override
  late final _Translations$onboarding$repo$errors$fr errors =
      _Translations$onboarding$repo$errors$fr._(_root);
}

// Path: onboarding.preview
class _Translations$onboarding$preview$fr
    extends Translations$onboarding$preview$en {
  _Translations$onboarding$preview$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$preview$panels$fr panels =
      _Translations$onboarding$preview$panels$fr._(_root);
  @override
  late final _Translations$onboarding$preview$sidebar$fr sidebar =
      _Translations$onboarding$preview$sidebar$fr._(_root);
  @override
  late final _Translations$onboarding$preview$changes$fr changes =
      _Translations$onboarding$preview$changes$fr._(_root);
  @override
  late final _Translations$onboarding$preview$history$fr history =
      _Translations$onboarding$preview$history$fr._(_root);
  @override
  late final _Translations$onboarding$preview$branches$fr branches =
      _Translations$onboarding$preview$branches$fr._(_root);
  @override
  late final _Translations$onboarding$preview$diff$fr diff =
      _Translations$onboarding$preview$diff$fr._(_root);
}

// Path: orrery.header
class _Translations$orrery$header$fr extends Translations$orrery$header$en {
  _Translations$orrery$header$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Orrery';
  @override
  String get modeScrub => 'Défiler';
  @override
  String get modeCompare => 'Comparer';
  @override
  String get lodModules => 'Modules';
  @override
  String get lodFiles => 'Fichiers';
}

// Path: orrery.status
class _Translations$orrery$status$fr extends Translations$orrery$status$en {
  _Translations$orrery$status$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'Traçage du manifold à travers l\'historique…';
  @override
  String get loadError => 'Impossible de lire l\'historique de ce dépôt.';
  @override
  String get notEnoughHistory =>
      'Pas encore assez d\'historique pour tracer une trajectoire.';
  @override
  String get notEnoughHistoryDetail =>
      'L\'Orrery a besoin de quelques commits pour tracer.';
}

// Path: orrery.legend
class _Translations$orrery$legend$fr extends Translations$orrery$legend$en {
  _Translations$orrery$legend$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get central => 'central';
  @override
  String get peripheral => 'périphérique';
}

// Path: orrery.node
class _Translations$orrery$node$fr extends Translations$orrery$node$en {
  _Translations$orrery$node$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get module => 'module';
  @override
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · ${n} fichiers';
  @override
  String fileFallback({required Object id}) => 'fichier n°${id}';
  @override
  String nodeFallback({required Object id}) => 'nœud n°${id}';
  @override
  String get rootModule => '(racine)';
}

// Path: orrery.milestone
class _Translations$orrery$milestone$fr
    extends Translations$orrery$milestone$en {
  _Translations$orrery$milestone$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get genesis => 'genèse';
  @override
  String get now => 'maintenant';
  @override
  String get reorganized => 'réorganisé';
  @override
  String becameArchetype({required Object archetype}) => 'devenu ${archetype}';
  @override
  String get snapshot => 'instantané';
}

// Path: orrery.structure
class _Translations$orrery$structure$fr
    extends Translations$orrery$structure$en {
  _Translations$orrery$structure$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get forming => 'en formation…';
  @override
  String get canonical => 'canonique';
  @override
  String get connectivity => 'connectivité';
  @override
  String get rigidity => 'rigidité';
  @override
  String get entropy => 'entropie';
}

// Path: orrery.rail
class _Translations$orrery$rail$fr extends Translations$orrery$rail$en {
  _Translations$orrery$rail$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get structureLabel => 'STRUCTURE';
  @override
  String get fieldLabel => 'CHAMP';
  @override
  String get findingsLabel => 'CONSTATS';
  @override
  String get selectedLabel => 'SÉLECTION';
  @override
  String get noFindings =>
      'Aucun événement structurel détecté dans cet historique.';
}

// Path: orrery.selection
class _Translations$orrery$selection$fr
    extends Translations$orrery$selection$en {
  _Translations$orrery$selection$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get notPresent => 'Absent à ce point de l\'historique.';
  @override
  String get roleCentral =>
      'Central au couplage — les changements ici se propagent à tout le système.';
  @override
  String get rolePeripheral =>
      'Périphérique — faiblement couplé, change surtout de son côté.';
  @override
  String get roleMid => 'Structure intermédiaire — modérément couplé.';
  @override
  String get driftOutward => ' Dérive vers l\'extérieur — découplage.';
  @override
  String get driftInward => ' Dérive vers l\'intérieur — intégration.';
  @override
  String get driftHolding => ' Maintient sa position.';
}

// Path: orrery.findingKind
class _Translations$orrery$findingKind$fr
    extends Translations$orrery$findingKind$en {
  _Translations$orrery$findingKind$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get hub => 'PIVOT';
  @override
  String get driftOut => 'DÉRIVE SORTANTE';
  @override
  String get driftIn => 'DÉRIVE ENTRANTE';
  @override
  String get tangle => 'EMMÊLEMENT';
  @override
  String get clarify => 'CLARIFICATION';
  @override
  String get regime => 'RÉORG';
  @override
  String get thrash => 'AGITATION';
  @override
  String get reshuffle => 'REMANIEMENT';
  @override
  String get forecast => 'PRÉVISION';
}

// Path: orrery.findings
class _Translations$orrery$findings$fr extends Translations$orrery$findings$en {
  _Translations$orrery$findings$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get forecastSplit =>
      'La connectivité baisse depuis un moment et frôle son minimum — si ça continue, la base de code s\'achemine vers une scission en deux moitiés faiblement couplées. Décidez maintenant si c\'est bien l\'intention.';
  @override
  String get forecastConsolidate =>
      'La connectivité grimpe vers son sommet — si ça continue, la base de code se consolide en une masse fortement couplée. Surveillez qu\'elle ne se fige pas en monolithe.';
  @override
  String thrash({required Object name}) =>
      '${name} n\'arrête pas d\'être réorganisé dans un sens puis dans l\'autre — beaucoup de remous structurels, peu de mouvement net. Fixez son couplage ou cessez d\'y toucher.';
  @override
  String get reshuffle =>
      'Ce commit semblait ordinaire mais a discrètement déplacé quels fichiers sont centraux — la forme d\'ensemble a tenu pendant que la structure se remaniait en dessous. À revoir attentivement.';
  @override
  String hub({required Object name}) =>
      '${name} occupe le cœur structurel — le système se réorganise autour de lui. Traitez les changements ici comme à fort rayon d\'impact.';
  @override
  String driftOut({required Object name}) =>
      '${name} a dérivé du cœur vers le bord — il se découple du système. Soit on le retire, soit il pourrit en silence.';
  @override
  String driftIn({required Object name}) =>
      '${name} a migré vers le cœur — il devient porteur. Assurez-vous qu\'il est bien testé avant que d\'autres n\'en dépendent.';
  @override
  String get regime =>
      'La base de code s\'est fortement réorganisée ici — sa connectivité a bondi. Voyez ce qui s\'est séparé ou fusionné.';
  @override
  String get tangleTrend =>
      'Au fil de son histoire, la base de code a tendu vers une structure plus emmêlée — sa connectivité se densifie et se fait moins modulaire.';
  @override
  String get clarifyTrend =>
      'Au fil de son histoire, la base de code a tendu vers une structure plus nette — elle se sépare en modules plus clairs.';
}

// Path: orrery.anchor
class _Translations$orrery$anchor$fr extends Translations$orrery$anchor$en {
  _Translations$orrery$anchor$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get core => 'cœur';
  @override
  String get drift => 'dérive';
  @override
  String get trend => 'tendance';
  @override
  String get thrash => 'agitation';
}

// Path: orrery.compare
class _Translations$orrery$compare$fr extends Translations$orrery$compare$en {
  _Translations$orrery$compare$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'A → B';
  @override
  String get change => 'CHANGEMENT';
  @override
  String get movers => 'MOUVEMENTS';
  @override
  String get noMovers => 'Aucun fichier n\'a bougé entre ces images.';
  @override
  String get badgeA => 'A';
  @override
  String get badgeB => 'B';
  @override
  String get deltaFiles => 'fichiers';
  @override
  String get deltaConnectivity => 'connectivité';
  @override
  String get deltaRigidity => 'rigidité';
  @override
  String get deltaEntropy => 'entropie';
  @override
  String get wayOutward => 'sortant';
  @override
  String get wayInward => 'entrant';
  @override
  String get wayShifted => 'déplacé';
}

// Path: palette.prefixes
class _Translations$palette$prefixes$fr
    extends Translations$palette$prefixes$en {
  _Translations$palette$prefixes$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get askHint => 'ask : [question]';
  @override
  String get nearHint => 'near : [fichier]';
  @override
  String get whoHint => 'who : [fichier]';
  @override
  String get logHint => 'log : [message]';
  @override
  String get runHint => 'run : [outil]';
  @override
  String askLabel({required Object name, required Object body}) =>
      'Demander à ${name} : ${body}';
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
  }) => '${path} · ${count} relecteurs · ${touches} touches';
  @override
  String whoTouchesLabel({required Object name, required Object touches}) =>
      '${name} — ${touches} touches';
  @override
  String whoTouchesSubtitle({required Object path}) =>
      '${path} · aucun relecteur enregistré';
}

// Path: palette.chips
class _Translations$palette$chips$fr extends Translations$palette$chips$en {
  _Translations$palette$chips$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get ai => 'IA';
  @override
  String get near => 'PROCHE';
  @override
  String get who => 'QUI';
  @override
  String get term => 'TERM';
  @override
  String get gui => 'GUI';
  @override
  String get dev => 'DEV';
  @override
  String get debug => 'DÉBOG';
  @override
  String get alpha => 'ALPHA';
  @override
  String get hot => 'CHAUD';
  @override
  String get key => 'CLÉ';
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
  String get draft => 'BROUILLON';
  @override
  String get undo => 'ANNULER';
  @override
  String get thm => 'THM';
  @override
  String get ver => 'VER';
  @override
  String get desk => 'BUREAU';
  @override
  String get det => 'DÉT';
  @override
  String get main => 'MAIN';
  @override
  String get head => 'HEAD';
  @override
  String get gone => 'PARTIE';
  @override
  String get remote => 'DISTANT';
  @override
  String get local => 'LOCAL';
  @override
  String get an => 'AN';
  @override
  String get lw => 'LW';
}

// Path: palette.predictive
class _Translations$palette$predictive$fr
    extends Translations$palette$predictive$en {
  _Translations$palette$predictive$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String momentumSuffix({required Object percent}) => '${percent}% d\'élan';
}

// Path: palette.topTouched
class _Translations$palette$topTouched$fr
    extends Translations$palette$topTouched$en {
  _Translations$palette$topTouched$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object count, required Object path}) =>
      '${count} touches · ${path}';
}

// Path: palette.coherence
class _Translations$palette$coherence$fr
    extends Translations$palette$coherence$en {
  _Translations$palette$coherence$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String label({required Object percent}) => 'Cohérence indexée : ${percent}%';
  @override
  String subtitle({required Object count}) => '${count} fichiers';
}

// Path: palette.keystone
class _Translations$palette$keystone$fr
    extends Translations$palette$keystone$en {
  _Translations$palette$keystone$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object path, required Object score}) =>
      '${path} · clé de voûte ${score}';
}

// Path: palette.repoSub
class _Translations$palette$repoSub$fr extends Translations$palette$repoSub$en {
  _Translations$palette$repoSub$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String changes({required Object name}) => 'Modifications dans ${name}';
  @override
  String history({required Object name}) => 'Historique dans ${name}';
  @override
  String branches({required Object name}) => 'Branches dans ${name}';
  @override
  String terminal({required Object name}) => 'Terminal dans ${name}';
  @override
  String generateCommit({required Object name}) =>
      'Générer un commit · ${name}';
  @override
  String reviewChanges({required Object name}) =>
      'Relire les modifications dans ${name}';
  @override
  String muse({required Object name}) => 'Muse dans ${name}';
}

// Path: palette.desks
class _Translations$palette$desks$fr extends Translations$palette$desks$en {
  _Translations$palette$desks$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get mainWorktree => 'arbre de travail principal';
  @override
  String get detached => 'détachée';
  @override
  String dirty({required Object count}) => '${count} sales';
}

// Path: palette.actions
class _Translations$palette$actions$fr extends Translations$palette$actions$en {
  _Translations$palette$actions$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get openInBrowser => 'Ouvrir dans le navigateur';
  @override
  String get terminal => 'Terminal';
  @override
  String get revealInFiles => 'Afficher dans les fichiers';
  @override
  String get copyPath => 'Copier le chemin';
  @override
  String get copyBranch => 'Copier la branche';
}

// Path: palette.tools
class _Translations$palette$tools$fr extends Translations$palette$tools$en {
  _Translations$palette$tools$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String launch({required Object label}) => 'Lancer ${label}';
}

// Path: palette.gitCommands
class _Translations$palette$gitCommands$fr
    extends Translations$palette$gitCommands$en {
  _Translations$palette$gitCommands$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get fetch => 'Récupérer';
  @override
  String get pull => 'Tirer';
  @override
  String pullBehind({required Object count}) => '${count} en retard';
  @override
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';
  @override
  String get push => 'Pousser';
  @override
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} commit',
        other: '${n} commits',
      );
  @override
  String pushCommitsUpstream({
    required Object commits,
    required Object upstream,
  }) => '${commits} vers ${upstream}';
  @override
  String get forcePush => 'Poussée forcée';
  @override
  String forcePushNoUpstream({required Object branch}) =>
      'Impossible de forcer la poussée : aucun amont défini pour ${branch}.';
  @override
  String get commit => 'Valider';
  @override
  String get stageAll => 'Tout indexer';
  @override
  String get unstageAll => 'Tout désindexer';
  @override
  String get discardAll => 'Tout abandonner';
  @override
  String get createBranch => 'Créer une branche';
  @override
  String get deleteBranch => 'Supprimer la branche';
  @override
  String get renameBranch => 'Renommer la branche';
  @override
  String get stash => 'Remiser';
  @override
  String get stashPop => 'Dépiler le remisage';
  @override
  String get stashApply => 'Appliquer le remisage';
  @override
  String get stashDrop => 'Supprimer le remisage';
  @override
  String get createTag => 'Créer une étiquette';
  @override
  String get cherryPick => 'Picorer';
  @override
  String get revert => 'Annuler';
  @override
  String get stashConflictMessage =>
      'Remisage appliqué avec des conflits. Résolvez-les sur la page Modifications.';
}

// Path: palette.pr
class _Translations$palette$pr$fr extends Translations$palette$pr$en {
  _Translations$palette$pr$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get create => 'Créer une PR';
  @override
  String get merge => 'Fusionner la PR';
  @override
  String get markReady => 'Marquer la PR prête';
}

// Path: palette.ai
class _Translations$palette$ai$fr extends Translations$palette$ai$en {
  _Translations$palette$ai$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get generateCommit => 'Générer un commit';
  @override
  String get reviewChanges => 'Relire les modifications';
  @override
  String get runMuse => 'Lancer la Muse';
  @override
  String debugRepo({required Object name}) => 'Déboguer ${name}';
  @override
  String get describeSymptom => 'décrivez un symptôme';
  @override
  String viewResult({required Object kind}) => 'Voir ${kind}';
  @override
  String get unseenResult => 'résultat non vu';
  @override
  String runningResult({required Object kind}) => 'IA : ${kind}…';
  @override
  String get running => 'en cours';
  @override
  String get kindCommitMessage => 'Message de commit';
  @override
  String get kindCodeReview => 'Revue de code';
  @override
  String get kindMuseResult => 'Résultat de la Muse';
  @override
  String get kindPresentation => 'Présentation';
  @override
  String get kindDebugResult => 'Résultat du débogage';
}

// Path: palette.undo
class _Translations$palette$undo$fr extends Translations$palette$undo$en {
  _Translations$palette$undo$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String cancel({required Object label}) => 'Annuler : ${label}';
}

// Path: palette.navigation
class _Translations$palette$navigation$fr
    extends Translations$palette$navigation$en {
  _Translations$palette$navigation$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get changes => 'Modifications';
  @override
  String get history => 'Historique';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get settings => 'Paramètres';
  @override
  String get refresh => 'Actualiser';
}

// Path: palette.settings
class _Translations$palette$settings$fr
    extends Translations$palette$settings$en {
  _Translations$palette$settings$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get reduceMotion => 'Réduire les animations';
  @override
  String get animateLogoUnfocused => 'Animer le logo hors focus';
  @override
  String get instantBlameHover => 'Survol blame instantané';
  @override
  String get autoSelectChanges => 'Sélection auto des modifications';
  @override
  String get fetchOnlineIssues => 'Récupérer les tickets en ligne';
  @override
  String get rememberWip => 'Mémoriser le travail en cours';
  @override
  String get hideAiFeatures => 'Masquer les fonctions IA';
  @override
  String get crashReporting => 'Rapports de plantage';
  @override
  String get aiReadOnly => 'IA en lecture seule';
  @override
  String get stashCabinetExpanded => 'Armoire de remisage déployée';
  @override
  String get fileSortInverted => 'Tri des fichiers inversé';
}

// Path: palette.info
class _Translations$palette$info$fr extends Translations$palette$info$en {
  _Translations$palette$info$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class _Translations$palette$debug$fr extends Translations$palette$debug$en {
  _Translations$palette$debug$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get engineStatus => 'État du moteur';
  @override
  String get engineStatusSubtitle => 'Diagnostics du moteur spectral LogosGit';
  @override
  String get fileCoupling => 'Couplage de fichiers';
  @override
  String get fileCouplingSubtitle =>
      'Voisins de co-changement les plus proches pour les fichiers indexés';
  @override
  String get themeSpecimen => 'Spécimen de thème';
  @override
  String get themeSpecimenSubtitle =>
      'Toutes les couleurs, icônes, niveaux de texte et géométrie';
}

// Path: palette.dev
class _Translations$palette$dev$fr extends Translations$palette$dev$en {
  _Translations$palette$dev$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get testMergeEditor => 'Tester l\'éditeur de fusion';
  @override
  String get testHistorySurgery => 'Tester la chirurgie de l\'historique';
  @override
  String get back => 'retour';
  @override
  String get cancel => 'annuler';
  @override
  String get buildingConflicts =>
      'construction de conflits de test à partir de l\'historique…';
}

// Path: palette.historySurgery
class _Translations$palette$historySurgery$fr
    extends Translations$palette$historySurgery$en {
  _Translations$palette$historySurgery$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Chirurgie de l\'historique';
  @override
  String get subtitle =>
      'Réécrire l\'historique pour supprimer définitivement des fichiers';
}

// Path: palette.orrery
class _Translations$palette$orrery$fr extends Translations$palette$orrery$en {
  _Translations$palette$orrery$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Orrery';
  @override
  String get subtitle =>
      'Parcourir l\'histoire structurelle du dépôt à travers le manifold';
}

// Path: palette.command
class _Translations$palette$command$fr extends Translations$palette$command$en {
  _Translations$palette$command$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String complete({required Object label}) => '${label} terminé';
  @override
  String failed({required Object label, required Object message}) =>
      '${label} échoué : ${message}';
  @override
  String get copy => 'Copier';
}

// Path: palette.search
class _Translations$palette$search$fr extends Translations$palette$search$en {
  _Translations$palette$search$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get hintDefault => 'tout rechercher...';
  @override
  String get hintElevated => 'élevé — toutes les actions';
  @override
  String get emptyTypeToSearch => 'tapez pour rechercher';
  @override
  String get emptyNoResults => 'aucun résultat';
}

// Path: palette.wick
class _Translations$palette$wick$fr extends Translations$palette$wick$en {
  _Translations$palette$wick$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'wick';
  @override
  String get coupledFallback => 'couplé';
}

// Path: palette.gitCache
class _Translations$palette$gitCache$fr
    extends Translations$palette$gitCache$en {
  _Translations$palette$gitCache$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'actuel';
  @override
  String get staged => 'indexé';
  @override
  String get modified => 'modifié';
}

// Path: releaseNotes.about
class _Translations$releaseNotes$about$fr
    extends Translations$releaseNotes$about$en {
  _Translations$releaseNotes$about$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$releaseNotes$about$whyFlutter$fr whyFlutter =
      _Translations$releaseNotes$about$whyFlutter$fr._(_root);
  @override
  late final _Translations$releaseNotes$about$spectralEngine$fr spectralEngine =
      _Translations$releaseNotes$about$spectralEngine$fr._(_root);
  @override
  late final _Translations$releaseNotes$about$whereGoing$fr whereGoing =
      _Translations$releaseNotes$about$whereGoing$fr._(_root);
}

// Path: repoSummary.backbone
class _Translations$repoSummary$backbone$fr
    extends Translations$repoSummary$backbone$en {
  _Translations$repoSummary$backbone$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}` (${lines}) — ${region}';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} ligne',
        other: '${n} lignes',
      );
  @override
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class _Translations$repoSummary$glance$fr
    extends Translations$repoSummary$glance$en {
  _Translations$repoSummary$glance$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} fichier.',
        other: '${n} fichiers.',
      );
  @override
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} ligne (${bytes}).',
        other: '${n} lignes (${bytes}).',
      );
  @override
  String roles({required Object parts}) => 'Rôles — ${parts}.';
  @override
  String showingNofM({required Object active, required Object total}) =>
      'Affichage de ${active} sur ${total} fichiers, classés par centralité structurelle.';
}

// Path: repoSummary.heading
class _Translations$repoSummary$heading$fr
    extends Translations$repoSummary$heading$en {
  _Translations$repoSummary$heading$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get atAGlance => 'En un coup d\'œil';
  @override
  String get core => 'Cœur';
  @override
  String get gettingStarted => 'Pour commencer';
  @override
  String get regions => 'Régions';
  @override
  String get shape => 'Forme';
}

// Path: repoSummary.pitch
class _Translations$repoSummary$pitch$fr
    extends Translations$repoSummary$pitch$en {
  _Translations$repoSummary$pitch$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String empty({required Object detail}) =>
      'Un dépôt sans fichier texte lisible${detail}.';
  @override
  String emptyBinary({required Object n}) => '${n} binaire';
  @override
  String emptyUnreadable({required Object n}) => '${n} illisible';
  @override
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'Un dépôt de ${n} fichier actif.',
        other: 'Un dépôt de ${n} fichiers actifs.',
      );
  @override
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'Un dépôt de ${n} fichier actif — ${regions}.',
        other: 'Un dépôt de ${n} fichiers actifs — ${regions}.',
      );
}

// Path: repoSummary.region
class _Translations$repoSummary$region$fr
    extends Translations$repoSummary$region$en {
  _Translations$repoSummary$region$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String bodyCommonDir({required Object dir}) => 'Tous sous `${dir}`.';
  @override
  String get bodyCommonDirSeparator => ' ';
  @override
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '1 cœur',
        other: '${n} cœurs',
      );
  @override
  String get bodyCoreSeparator => ', ';
  @override
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'Un fichier',
        other: '${n} fichiers',
      );
  @override
  String connectsTo({required Object linked}) => 'Se connecte à : ${linked}.';
  @override
  String get filesLabel => 'Fichiers :';
}

// Path: repoSummary.shape
class _Translations$repoSummary$shape$fr
    extends Translations$repoSummary$shape$en {
  _Translations$repoSummary$shape$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get bulk =>
      'Base de code densément interconnectée : la plupart des fichiers participent à un grand voisinage de changements partagés.';
  @override
  String get crystalline =>
      'Base de code en réseau : couplage uniforme et régulier entre fichiers, avec une structure locale prévisible.';
  @override
  String get goe =>
      'Base de code richement interconnectée : les couplages s\'étalent sur les fichiers sans épine dorsale dominante.';
  @override
  String get modular =>
      'Base de code modulaire : plusieurs régions cohésives à couplage croisé limité. Travailler dans une région perturbe rarement une autre.';
  @override
  String get poisson =>
      'Base de code faiblement couplée : les fichiers évoluent surtout seuls, avec des changements partagés occasionnels.';
  @override
  String get tree =>
      'Base de code en arbre : une épine dorsale dominante avec des branches dépendantes. Le changement se propage généralement du cœur vers l\'extérieur.';
}

// Path: settings.language
class _Translations$settings$language$fr
    extends Translations$settings$language$en {
  _Translations$settings$language$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Langue';
  @override
  String get summary =>
      'Langue de l\'interface pour cette application. La sortie git, les journaux et les diagnostics restent en anglais pour que les rapports de bug restent trouvables.';
  @override
  String get label => 'LANGUE D\'AFFICHAGE';
  @override
  String get systemDefault => 'Défaut du système';
  @override
  String systemDefaultDetail({required Object resolved}) =>
      'Suit la langue de votre OS (${resolved})';
  @override
  String get disclosureSource => 'Langue source, écrite par les développeurs.';
  @override
  String disclosureAi({required Object model}) =>
      'Traduit automatiquement par ${model}, pas encore relu par un humain. Corrections bienvenues.';
  @override
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) => 'Traduit automatiquement par ${model}. ${percent}% relu par un humain.';
  @override
  String get disclosureHuman =>
      'Traduction humaine, maintenue par la communauté.';
  @override
  String reviewedBy({required Object names}) => 'Relu par ${names}.';
}

// Path: settings.sectionLabels
class _Translations$settings$sectionLabels$fr
    extends Translations$settings$sectionLabels$en {
  _Translations$settings$sectionLabels$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get preferences => 'Préférences';
  @override
  String get shortcuts => 'Raccourcis';
  @override
  String get behaviour => 'Comportement';
  @override
  String get aiProviders => 'Fournisseurs IA';
  @override
  String get modelSlots => 'Emplacements de modèles';
  @override
  String get tools => 'Outils';
  @override
  String get diagnostics => 'Diagnostics';
  @override
  String get offenders => 'Fautifs';
  @override
  String get release => 'Version';
}

// Path: settings.errors
class _Translations$settings$errors$fr extends Translations$settings$errors$en {
  _Translations$settings$errors$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get saveGuardrailProfile =>
      'Échec de l\'enregistrement du profil de garde-fous.';
  @override
  String get saveRetentionPolicy =>
      'Échec de l\'enregistrement de la politique de rétention.';
  @override
  String get saveUpdateChannel =>
      'Échec de l\'enregistrement du canal de mise à jour.';
  @override
  String get saveModelSelection =>
      'Échec de l\'enregistrement de la sélection du modèle IA.';
  @override
  String get saveModelAlias =>
      'Échec de l\'enregistrement de l\'alias du modèle.';
  @override
  String get saveCommitMessageModelSlot =>
      'Échec de l\'enregistrement de l\'emplacement du modèle de message de commit.';
  @override
  String get saveReviewModelSlot =>
      'Échec de l\'enregistrement de l\'emplacement du modèle de revue.';
  @override
  String get saveCommitMessageCustomPrompt =>
      'Échec de l\'enregistrement de l\'invite personnalisée de message de commit.';
  @override
  String get saveReviewGuide => 'Échec de l\'enregistrement du guide de revue.';
  @override
  String get saveMuseNotes =>
      'Échec de l\'enregistrement des notes de la muse.';
  @override
  String get saveReviewDoubleCheck =>
      'Échec de l\'enregistrement du mode double-vérification de revue.';
  @override
  String get saveApiPiggybackCli =>
      'Échec de l\'enregistrement du CLI de relais API.';
  @override
  String clearLocalData({required Object error}) =>
      'Impossible d\'effacer les données locales : ${error}';
}

// Path: settings.promptStatus
class _Translations$settings$promptStatus$fr
    extends Translations$settings$promptStatus$en {
  _Translations$settings$promptStatus$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get editing => 'Édition';
  @override
  String get saving => 'Enregistrement';
  @override
  String get saveFailed => 'Échec de l\'enregistrement';
}

// Path: settings.clearData
class _Translations$settings$clearData$fr
    extends Translations$settings$clearData$en {
  _Translations$settings$clearData$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => 'Effacer les données locales';
  @override
  String get clear => 'Effacer';
  @override
  String get confirmDiagnostics =>
      'Effacer les échantillons de diagnostic locaux et les mesures de performance ?';
  @override
  String get confirmAudit =>
      'Effacer les enregistrements de métadonnées d\'audit IA locaux ?';
  @override
  String get confirmAll =>
      'Effacer tous les échantillons de diagnostic locaux et les enregistrements de métadonnées d\'audit IA ?';
  @override
  String get confirmWipeAll =>
      'Effacer toutes les données locales de l\'application — y compris la liste des dépôts récents — et quitter ? Vos dépôts git réels sur le disque ne sont pas touchés.';
  @override
  String get confirmReset =>
      'Réinitialiser les données locales de l\'application et quitter ?\n\nLes paramètres, le thème, l\'accueil, les préférences IA, la télémétrie et les caches d\'engrammes sont effacés. Votre liste de dépôts récents est conservée.';
}

// Path: settings.guardrailMacro
class _Translations$settings$guardrailMacro$fr
    extends Translations$settings$guardrailMacro$en {
  _Translations$settings$guardrailMacro$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'souple';
  @override
  String get balanced => 'équilibré';
  @override
  String get strict => 'strict';
  @override
  String get paranoid => 'paranoïaque';
}

// Path: settings.guardrails
class _Translations$settings$guardrails$fr
    extends Translations$settings$guardrails$en {
  _Translations$settings$guardrails$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Garde-fous';
  @override
  String get summary =>
      'À quel point l\'automatisation est attentive dans toute l\'expérience.';
}

// Path: settings.appearance
class _Translations$settings$appearance$fr
    extends Translations$settings$appearance$en {
  _Translations$settings$appearance$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Apparence';
  @override
  String get summary => 'Ambiance et atmosphère globales de l\'interface.';
}

// Path: settings.retention
class _Translations$settings$retention$fr
    extends Translations$settings$retention$en {
  _Translations$settings$retention$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Rétention des données locales';
  @override
  String get summaryDiagnostics => 'Politique de rétention des diagnostics.';
  @override
  String get summaryWithAudit =>
      'Politique de rétention des diagnostics et de l\'audit IA.';
  @override
  String get unitDays => 'jours';
  @override
  String get unitMb => 'Mo';
  @override
  String get includesNote =>
      'Inclut les diagnostics, les mesures de performance et les métadonnées.';
}

// Path: settings.navigation
class _Translations$settings$navigation$fr
    extends Translations$settings$navigation$en {
  _Translations$settings$navigation$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Navigation et dynamique';
  @override
  String get summaryShortcuts => 'Raccourcis et comportement de l\'interface.';
  @override
  String get summaryWithAi =>
      'Raccourcis, comportement de l\'interface et routage IA.';
}

// Path: settings.behaviour
class _Translations$settings$behaviour$fr
    extends Translations$settings$behaviour$en {
  _Translations$settings$behaviour$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Dynamiques comportementales';
}

// Path: settings.retentionClear
class _Translations$settings$retentionClear$fr
    extends Translations$settings$retentionClear$en {
  _Translations$settings$retentionClear$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get diag => 'Diag';
  @override
  String get audit => 'Audit';
  @override
  String get all => 'Tout';
  @override
  String get clearsHint => '<-- efface';
}

// Path: settings.channels
class _Translations$settings$channels$fr
    extends Translations$settings$channels$en {
  _Translations$settings$channels$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get stable => 'STABLE';
  @override
  String get beta => 'BÊTA';
  @override
  String get dev => 'DEV';
}

// Path: settings.pollResult
class _Translations$settings$pollResult$fr
    extends Translations$settings$pollResult$en {
  _Translations$settings$pollResult$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get upToDate => 'à jour';
  @override
  String updateAvailable({required Object version}) => '${version} disponible';
  @override
  String get notConfigured => 'aucun serveur de mise à jour';
  @override
  String notFound({required Object channel}) => 'aucune version ${channel}';
  @override
  String get unreachable => 'injoignable';
  @override
  String get badManifest => 'manifeste invalide';
}

// Path: settings.keybindingProfile
class _Translations$settings$keybindingProfile$fr
    extends Translations$settings$keybindingProfile$en {
  _Translations$settings$keybindingProfile$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Profil de raccourcis';
  @override
  String get porcelain => 'Porcelaine';
  @override
  String get numeric => 'Numérique';
  @override
  String get porcelainDescription => 'Raccourcis en accords (G puis C, H, B…).';
  @override
  String get numericDescription =>
      'Raccourcis numériques à une touche (1, 2, 3…).';
}

// Path: settings.apiKeys
class _Translations$settings$apiKeys$fr
    extends Translations$settings$apiKeys$en {
  _Translations$settings$apiKeys$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get keyHintDefault => 'clé api';
  @override
  String get endpointHint => 'point de terminaison';
  @override
  String get test => 'Tester';
  @override
  String get hide => 'Masquer';
  @override
  String get show => 'Afficher';
}

// Path: settings.shortcuts
class _Translations$settings$shortcuts$fr
    extends Translations$settings$shortcuts$en {
  _Translations$settings$shortcuts$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get navigate => 'naviguer';
  @override
  String get staging => 'indexation';
  @override
  String get branchesPrs => 'branches et PR';
  @override
  String get modifiers => 'modificateurs';
  @override
  String get changes => 'Modifications';
  @override
  String get history => 'Historique';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Basculer (toujours)';
  @override
  String get search => 'Rechercher';
  @override
  String get dismiss => 'Fermer';
  @override
  String get refresh => 'Actualiser';
  @override
  String get shortcuts => 'Raccourcis';
  @override
  String get nextChange => 'Modif. suivante';
  @override
  String get prevChange => 'Modif. précédente';
  @override
  String get toggleLine => 'Basculer la ligne';
  @override
  String get toggleHunk => 'Basculer la section';
  @override
  String get toggleFile => 'Basculer le fichier';
  @override
  String get pinContext => 'Épingler le contexte';
  @override
  String get commit => 'Valider';
  @override
  String get acceptHint => 'Accepter l\'indice';
  @override
  String get undo => 'Annuler';
  @override
  String get navigateRow => 'Naviguer';
  @override
  String get expand => 'Développer';
  @override
  String get checkout => 'Extraire';
  @override
  String get approve => 'Approuver';
  @override
  String get requestChanges => 'Demander des modifications';
  @override
  String get selectRange => 'Sélectionner une plage';
  @override
  String get extendedMenu => 'Menu étendu';
}

// Path: settings.toggles
class _Translations$settings$toggles$fr
    extends Translations$settings$toggles$en {
  _Translations$settings$toggles$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get aiReadOnlyLabel => 'Mode IA en lecture seule';
  @override
  String get aiReadOnlyDescription =>
      'Empêche l\'IA d\'écrire ou d\'indexer des changements automatiquement.';
  @override
  String get logoMotionLabel => 'Le logo s\'anime en arrière-plan';
  @override
  String get logoMotionDescriptionEnabled =>
      'Il est conçu pour être efficace, ne froissez pas ses sentiments';
  @override
  String get logoMotionDescriptionDisabled => ':(';
  @override
  String get rememberWipLabel => 'Mémoriser le travail en cours';
  @override
  String get rememberWipDescription =>
      'Conserve vos brouillons de commit et votre sélection de fichiers entre les sessions.';
  @override
  String get stashCabinetLabel => 'L\'armoire de remisage démarre déployée';
  @override
  String get stashCabinetDescription =>
      'Affiche le tiroir de l\'armoire ouvert par défaut quand un dépôt a des étagères.';
  @override
  String get instantBlameLabel => 'Survol blame instantané';
  @override
  String get instantBlameDescription =>
      'Passe le délai de 180 ms avant l\'affichage du blame sur une ligne de diff.';
  @override
  String get autoSelectLabel => 'Sélection auto des nouvelles modifications';
  @override
  String get autoSelectDescription =>
      'Les fichiers nouvellement suivis ou modifiés sont ajoutés automatiquement à la sélection de commit.';
  @override
  String get fetchIssuesLabel =>
      'Récupérer les tickets en ligne au chargement des branches';
  @override
  String get fetchIssuesDescription =>
      'Récupère en arrière-plan les détails des PR et tickets depuis votre fournisseur git à l\'ouverture de la page des branches.';
  @override
  String get hateAiLabel => 'Je déteste l\'IA';
  @override
  String get hateAiDescription =>
      'Bannit toutes les fonctions basées sur les LLM. Logos continue de tourner car ce ne sont que des maths spectrales.';
}

// Path: settings.diffDiffability
class _Translations$settings$diffDiffability$fr
    extends Translations$settings$diffDiffability$en {
  _Translations$settings$diffDiffability$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'diff diff-abilité';
}

// Path: settings.modelSlots
class _Translations$settings$modelSlots$fr
    extends Translations$settings$modelSlots$en {
  _Translations$settings$modelSlots$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get loadingProviders => 'Chargement des fournisseurs...';
  @override
  String get refreshingProviders =>
      'Actualisation des diagnostics des fournisseurs...';
  @override
  String get routeDescription =>
      'Renommez et routez les configurations vers n\'importe quel modèle de fournisseur détecté.';
  @override
  String get loadingCategories => 'Chargement des catégories de modèles...';
  @override
  String get noOptions =>
      'Aucune option de modèle disponible pour l\'instant. Détectez d\'abord un CLI IA local compatible.';
  @override
  String get slotsAppearWhenAvailable =>
      'Les paramètres d\'emplacement de modèle apparaîtront ici une fois les modèles de fournisseur disponibles.';
  @override
  String get effortDefault => 'défaut';
  @override
  String get noModelsForSlot => 'Aucun modèle détecté pour cet emplacement.';
  @override
  String viaProvider({required Object provider}) => 'via ${provider}';
  @override
  String get customModelId => 'id de modèle personnalisé';
}

// Path: settings.modelPicker
class _Translations$settings$modelPicker$fr
    extends Translations$settings$modelPicker$en {
  _Translations$settings$modelPicker$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String noMatch({required Object query}) =>
      'aucun modèle ne correspond à « ${query} »';
  @override
  String get noModels => 'aucun modèle disponible';
  @override
  String get filterHint => 'filtrer les modèles...';
  @override
  String get warming => 'préchauffe…';
  @override
  String get detailsUnavailable => 'détails indisponibles';
  @override
  String get free => 'gratuit';
}

// Path: settings.aiFeatures
class _Translations$settings$aiFeatures$fr
    extends Translations$settings$aiFeatures$en {
  _Translations$settings$aiFeatures$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get commitDescription =>
      'Rédige des messages de commit à partir des changements indexés selon vos préférences de structure, de voix et de couverture.';
  @override
  String get reviewDescription =>
      'Relit le périmètre du commit actuel avant que vous ne validiez.';
  @override
  String get museDescription =>
      'Oracle en trois phases qui remue-méninge puis synthétise une direction à suivre pour le diff.';
}

// Path: settings.commitEditor
class _Translations$settings$commitEditor$fr
    extends Translations$settings$commitEditor$en {
  _Translations$settings$commitEditor$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get styleGuide => 'Guide de style';
  @override
  String get styleGuideHint =>
      'Facultatif. Voix / ton / interdits. Le format ci-dessus gère le squelette.';
}

// Path: settings.review
class _Translations$settings$review$fr extends Translations$settings$review$en {
  _Translations$settings$review$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Notes supplémentaires pour la revue';
  @override
  String get doubleCheckLabel => 'Double-vérification de la revue';
  @override
  String get doubleCheckDescription =>
      'Effectue une deuxième passe de vérification avant d\'afficher le rapport final.';
}

// Path: settings.museHint
class _Translations$settings$museHint$fr
    extends Translations$settings$museHint$en {
  _Translations$settings$museHint$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get loose =>
      'quelque chose vers quoi orienter en douceur ? l\'humeur est clémente aujourd\'hui.';
  @override
  String get balanced => 'sur quoi s\'attarder, quoi sauter. honnête, pas dur.';
  @override
  String get strict =>
      'les standards. les interdits. ce que la muse ne laissera pas passer.';
  @override
  String get paranoid =>
      'réglez la lentille. sur quelles fréquences le manifold doit-il vibrer ?';
}

// Path: settings.museEditor
class _Translations$settings$museEditor$fr
    extends Translations$settings$museEditor$en {
  _Translations$settings$museEditor$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Notes supplémentaires pour la muse';
}

// Path: settings.museStage
class _Translations$settings$museStage$fr
    extends Translations$settings$museStage$en {
  _Translations$settings$museStage$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get brainstorm => 'REMUE-MÉNINGES';
  @override
  String get synthesize => 'SYNTHÈSE';
  @override
  String get slot => 'emplacement';
  @override
  String get ideaCountLoose => '~12 idées';
  @override
  String get ideaCountBalanced => '~16 idées';
  @override
  String get ideaCountStrict => '~20 idées';
  @override
  String get ideaCountParanoid => '~24 idées';
  @override
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  garde-fou : ${macro}';
}

// Path: settings.lensAxis
class _Translations$settings$lensAxis$fr
    extends Translations$settings$lensAxis$en {
  _Translations$settings$lensAxis$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get folder => 'DOSSIER';
  @override
  String get history => 'HISTORIQUE';
  @override
  String get far => 'LOIN';
  @override
  String get near => 'PROCHE';
}

// Path: settings.logosLens
class _Translations$settings$logosLens$fr
    extends Translations$settings$logosLens$en {
  _Translations$settings$logosLens$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get moduleMap => 'carte des modules';
  @override
  String get repoCenters => 'centres du dépôt';
  @override
  String get neighbors => 'voisins';
  @override
  String get toTouch => 'quoi toucher ensuite';
  @override
  String get relevanceEngine => 'moteur de pertinence';
  @override
  String get description =>
      'lit comment les fichiers bougent ensemble à travers la structure, l\'histoire et le rythme, pour que Manifold sache ce qui compte, pas seulement ce qui a changé.';
  @override
  String get withinReach => 'à portée';
  @override
  String get gate => 'seuil';
  @override
  String get nearest => 'le plus proche';
  @override
  String get warming => 'préchauffe';
  @override
  String get emptyOpenRepo =>
      'ouvrez un dépôt pour\nvoir la lentille en direct';
  @override
  String get emptyNoFiles =>
      'aucun fichier à\nportée — glissez\nvers HISTORIQUE';
}

// Path: settings.sortGuide
class _Translations$settings$sortGuide$fr
    extends Translations$settings$sortGuide$en {
  _Translations$settings$sortGuide$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Guide de tri des modifications';
  @override
  String get related =>
      'Les fichiers qui changent ensemble se regroupent. Le sujet d\'abord ; le contexte suit.';
  @override
  String get relatedInverted =>
      'Les changements isolés d\'abord. Les grappes fortement couplées coulent au fond.';
  @override
  String get alphabetical =>
      'Simple A → Z par chemin. Insensible à la casse, nombres ordonnés naturellement.';
  @override
  String get alphabeticalInverted =>
      'Simple Z → A par chemin. Insensible à la casse, nombres ordonnés naturellement.';
  @override
  String get impact =>
      'Les changements les plus lourds en premier. Le brassage est pondéré ; les binaires et nouveaux fichiers sont mis en avant.';
  @override
  String get impactInverted =>
      'Les changements les plus légers en premier. Les gains rapides en haut ; les gros efforts attendent.';
  @override
  String get nearRelated => 'proche lié';
  @override
  String get alphabeticalShort => 'alphabétique';
  @override
  String get byImpact => 'par impact';
  @override
  String get flipped => 'inversé';
  @override
  String get peek => 'aperçu';
}

// Path: settings.piggyback
class _Translations$settings$piggyback$fr
    extends Translations$settings$piggyback$en {
  _Translations$settings$piggyback$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get apiModelsUse => 'les modèles API utilisent';
  @override
  String get codexNotDetected => 'codex non détecté';
  @override
  String get dormant => 'DORMANT';
}

// Path: settings.diffStage
class _Translations$settings$diffStage$fr
    extends Translations$settings$diffStage$en {
  _Translations$settings$diffStage$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get viewer => 'visionneuse';
  @override
  String get media => 'média';
  @override
  String get binary => 'binaire';
  @override
  String get hidden => 'masqué';
}

// Path: settings.undoScope
class _Translations$settings$undoScope$fr
    extends Translations$settings$undoScope$en {
  _Translations$settings$undoScope$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get destructiveActions => 'actions destructrices';
  @override
  String get discards => 'abandons';
  @override
  String get commits => 'commits';
  @override
  String get commitPush => 'commit + push';
  @override
  String get all => 'tout';
}

// Path: settings.undoWindow
class _Translations$settings$undoWindow$fr
    extends Translations$settings$undoWindow$en {
  _Translations$settings$undoWindow$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Fenêtre d\'annulation';
  @override
  String get off => 'Désactivée';
  @override
  String descriptionInstant({required Object scope}) =>
      '${scope} se finalisent instantanément.';
  @override
  String descriptionDelayed({required Object seconds, required Object scope}) =>
      '${seconds}s avant que ${scope} ne se finalisent.';
  @override
  String get cycleScopeTooltip =>
      'Cliquez pour faire défiler la portée · glissez aussi vers le haut/bas sur le curseur';
  @override
  String get resetTooltip =>
      'Réinitialiser chaque action pour utiliser la fenêtre par défaut';
}

// Path: settings.guardrailPhrase
class _Translations$settings$guardrailPhrase$fr
    extends Translations$settings$guardrailPhrase$en {
  _Translations$settings$guardrailPhrase$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get probablyFine => 'Probablement bon veut dire bon';
  @override
  String get proper =>
      'Une vraie lecture, la logique, l\'intégration, les patterns';
  @override
  String get lookAgain => 'Regardez encore. Quelque chose se cache peut-être';
  @override
  String get assumeWrong => 'Supposez que quelque chose cloche. Trouvez-le';
}

// Path: settings.reviewGuideHint
class _Translations$settings$reviewGuideHint$fr
    extends Translations$settings$reviewGuideHint$en {
  _Translations$settings$reviewGuideHint$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get focusHigh =>
      'ex. Concentrez-vous sur la logique de haut niveau et les bugs majeurs. Soyez bref et indulgent.';
  @override
  String get surfaceBugs =>
      'ex. Faites ressortir les bugs potentiels, les incohérences architecturales et les cas limites.';
  @override
  String get scrutinize =>
      'ex. Scrutez chaque ligne pour l\'optimisation, la sécurité et le respect des patterns.';
  @override
  String get trustNothing =>
      'ex. Ne faites confiance à rien. Questionnez chaque effet de bord. Traitez chaque ligne comme une défaillance potentielle.';
  @override
  String get optional =>
      'Conseils facultatifs sur ce dont la revue devrait se soucier.';
}

// Path: settings.commitFormat
class _Translations$settings$commitFormat$fr
    extends Translations$settings$commitFormat$en {
  _Translations$settings$commitFormat$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Format';
  @override
  String get peek => 'aperçu';
  @override
  String get structure => 'Structure';
  @override
  String get voice => 'Voix';
  @override
  String get coverage => 'Couverture';
  @override
  String get structureTitleBody => 'titre + corps';
  @override
  String get structureTitleOnly => 'titre seul';
  @override
  String get structureFreeform => 'libre';
  @override
  String get voiceVerbLed => 'orienté action';
  @override
  String get voiceDescriptive => 'descriptif';
  @override
  String get voiceNarrative => 'narratif';
  @override
  String get coverageEssentials => 'essentiels';
  @override
  String get coverageBalanced => 'équilibré';
  @override
  String get coverageEverything => 'tout';
}

// Path: settings.commitPreview
class _Translations$settings$commitPreview$fr
    extends Translations$settings$commitPreview$en {
  _Translations$settings$commitPreview$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$fr title =
      _Translations$settings$commitPreview$title$fr._(_root);
  @override
  late final _Translations$settings$commitPreview$base$fr base =
      _Translations$settings$commitPreview$base$fr._(_root);
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$fr
  balancedSuffix = _Translations$settings$commitPreview$balancedSuffix$fr._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$fr
  everythingSuffix = _Translations$settings$commitPreview$everythingSuffix$fr._(
    _root,
  );
}

// Path: settings.externalTools
class _Translations$settings$externalTools$fr
    extends Translations$settings$externalTools$en {
  _Translations$settings$externalTools$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Outils externes';
  @override
  String get summary =>
      'Clic droit sur un projet dans la barre latérale pour l\'ouvrir avec l\'un d\'eux. Les arguments utilisent {path} pour le dossier du projet.';
  @override
  String get detecting => 'Détection des outils installés…';
  @override
  String get allPresetsAdded =>
      'Tous les préréglages connus sont déjà ajoutés. Utilisez « + Personnalisé » pour en ajouter.';
  @override
  String get noToolsConfigured =>
      'Aucun outil configuré pour l\'instant. Ajoutez-en un ci-dessus.';
  @override
  String get categoryAi => 'ia';
  @override
  String get categoryEditors => 'éditeurs';
  @override
  String get categoryExplore => 'explorer';
  @override
  String get categoryOps => 'ops';
  @override
  String get categoryGitOps => 'git ops';
  @override
  String get nameHint => 'Nom';
  @override
  String get commandHint => 'commande';
  @override
  String get test => 'tester';
  @override
  String get removeTool => 'Retirer l\'outil';
  @override
  String get modeTerminal => 'terminal';
  @override
  String get modeDetached => 'détaché';
}

// Path: settings.apiUsage
class _Translations$settings$apiUsage$fr
    extends Translations$settings$apiUsage$en {
  _Translations$settings$apiUsage$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String thisMonth({required Object used, required Object limit}) =>
      '${used}${limit} ce mois-ci';
}

// Path: settings.gitea
class _Translations$settings$gitea$fr extends Translations$settings$gitea$en {
  _Translations$settings$gitea$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Jetons Gitea';
  @override
  String get hostHint => 'hôte';
  @override
  String get tokenHint => 'jeton';
  @override
  String get save => 'enregistrer';
}

// Path: settings.wick
class _Translations$settings$wick$fr extends Translations$settings$wick$en {
  _Translations$settings$wick$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get selectExecutable => 'Sélectionner l\'exécutable wick';
  @override
  String get connected => 'wick · connecté';
  @override
  String get pathToExecutable => 'wick · chemin de l\'exécutable';
}

// Path: settings.integrations
class _Translations$settings$integrations$fr
    extends Translations$settings$integrations$en {
  _Translations$settings$integrations$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => '& Intégrations';
  @override
  String get alpha => 'alpha';
  @override
  String get planned => 'prévu';
  @override
  String get lspComingSoon => 'lsp · bientôt';
  @override
  String get alphaMathConnected => 'alpha-math · connecté';
  @override
  String get alphaMathComingSoon => 'alpha-math · bientôt';
}

// Path: settings.reduceMotion
class _Translations$settings$reduceMotion$fr
    extends Translations$settings$reduceMotion$en {
  _Translations$settings$reduceMotion$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Réduire les animations';
  @override
  String get subtitleStill => 'Immobile… comme la glace ?';
  @override
  String get subtitleFlow => 'Fluide comme l\'eau.';
}

// Path: settings.resetQuit
class _Translations$settings$resetQuit$fr
    extends Translations$settings$resetQuit$en {
  _Translations$settings$resetQuit$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get resetAndQuit => 'RÉINITIALISER & QUITTER';
  @override
  String get keepRepos => 'GARDER LES DÉPÔTS';
  @override
  String get wipeAll => 'TOUT EFFACER';
}

// Path: settings.diagnostics
class _Translations$settings$diagnostics$fr
    extends Translations$settings$diagnostics$en {
  _Translations$settings$diagnostics$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get commandDiagnostics => 'Diagnostics des commandes';
  @override
  String get networkFlowTelemetry => 'Télémétrie du flux réseau';
  @override
  String get clearSamples => 'Effacer les échantillons';
  @override
  String get clearMetrics => 'Effacer les métriques';
  @override
  String get clearTimings => 'Effacer les mesures';
  @override
  String get recalibrate => 'RECALIBRER';
  @override
  String get ok => 'ok';
  @override
  String get noCommandTimings =>
      'Aucune mesure de commande capturée pour l\'instant. Effectuez des actions normales pour peupler les diagnostics.';
  @override
  String get noBackendSamples =>
      'Aucun échantillon de commande backend capturé pour l\'instant. Effectuez des actions git et paramètres pour peupler ce journal.';
  @override
  String get noDiffSessions =>
      'Aucune session de rendu de diff capturée pour l\'instant. Ouvrez et faites défiler des diffs de fichiers pour peupler ce panneau.';
  @override
  String get noUiSessions =>
      'Aucune session de mesure UI capturée pour l\'instant. Ouvrez des panneaux et naviguez pour peupler ce panneau.';
  @override
  String get recentOperations => 'Opérations récentes';
  @override
  String get recentBackendOperations => 'Opérations backend récentes';
  @override
  String get recentDiffSessions => 'Sessions de diff récentes';
  @override
  String get recentUiTimings => 'Mesures UI récentes';
  @override
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} commande unique',
        other: '${n} commandes uniques',
      );
  @override
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} commande cadrée',
        other: '${n} commandes cadrées',
      );
  @override
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} événement instrumenté',
        other: '${n} événements instrumentés',
      );
  @override
  String summaryCommand({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryBackend({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryDiff({required Object sessions, required Object jank}) =>
      '${sessions} | à-coups ${jank}%';
  @override
  String summaryUi({required Object samples, required Object events}) =>
      '${samples} | ${events}';
  @override
  List<String> get headersCommand => ['commande', 'p50', 'fiabilité', 'plage'];
  @override
  List<String> get headersBackend => ['portée', 'p50', 'p95', 'échecs'];
  @override
  List<String> get headersDiff => [
    'moteur de rendu',
    'premier rendu',
    'trame p95',
    'raster p95',
    'à-coups',
  ];
  @override
  List<String> get headersUi => ['événement', 'p50', 'échecs', 'plage'];
}

// Path: settings.telemetry
class _Translations$settings$telemetry$fr
    extends Translations$settings$telemetry$en {
  _Translations$settings$telemetry$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} échantillon',
        other: '${n} échantillons',
      );
  @override
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} commande',
        other: '${n} commandes',
      );
  @override
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} session',
        other: '${n} sessions',
      );
  @override
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} événement',
        other: '${n} événements',
      );
  @override
  String stability({required Object pct}) => '${pct}% de stabilité';
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
class _Translations$settings$flowEngine$fr
    extends Translations$settings$flowEngine$en {
  _Translations$settings$flowEngine$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get executionFlow => 'flux-d\'exécution';
  @override
  String get description =>
      'simule des oscillateurs sur le code. fait ressortir les chemins d\'exécution fragiles avant qu\'ils ne se cristallisent en bugs.';
  @override
  String get idle => 'au repos';
  @override
  String get emptyOpenRepo => 'ouvrez un dépôt pour\nvoir l\'analyse de flux';
  @override
  String get scanning => 'analyse';
  @override
  String get analysing => 'analyse des fichiers\ndans la lentille…';
  @override
  String get fragility => 'fragilité';
  @override
  String get findings => 'constats';
  @override
  String get gap => 'écart';
  @override
  String get clean => 'propre';
  @override
  String get severity => 'sévérité';
  @override
  String get critical => 'critique';
  @override
  String get warn => 'alerte';
  @override
  String get info => 'info';
}

// Path: settings.museStrands
class _Translations$settings$museStrands$fr
    extends Translations$settings$museStrands$en {
  _Translations$settings$museStrands$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get spark => 'étincelle d\'inspiration · la toute prochaine étape';
  @override
  String get current => 'courant dans l\'eau · extensions au présent';
  @override
  String get horizon => 'regarder par-delà l\'horizon · directions à atteindre';
  @override
  String get fever => 's\'éveiller d\'un rêve fiévreux · provocations';
  @override
  String get echo => 'un écho à travers le canyon · analogues ailleurs';
  @override
  String get vertigo => 'vertige au bord de la falaise · risques adjacents';
  @override
  String get ghost => 'le fantôme de ce qui fut · contexte historique';
  @override
  String get mirror => 'un miroir sur l\'eau calme · inversions';
}

// Path: settings.cliPiggyback
class _Translations$settings$cliPiggyback$fr
    extends Translations$settings$cliPiggyback$en {
  _Translations$settings$cliPiggyback$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Relais CLI';
  @override
  String get clearCacheLabel => 'Vider le cache';
  @override
  String get clearCacheTooltip =>
      'Efface les modèles en cache et re-sonde. Retire ceux qu\'un fournisseur a abandonnés.';
  @override
  String get refreshLabel => 'Actualiser les fournisseurs';
  @override
  String get refreshTooltip => 'Re-sonder chaque fournisseur maintenant.';
  @override
  String get body =>
      'Redirige directement les messages de l\'interface vers les binaires des fournisseurs locaux.';
}

// Path: settings.header
class _Translations$settings$header$fr extends Translations$settings$header$en {
  _Translations$settings$header$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Préférences de l\'espace de travail';
  @override
  String get subtitle =>
      'Configurez l\'esthétique globale, la dynamique de l\'interface et les garde-fous opérationnels de base pour tout l\'espace de travail.';
  @override
  String get releaseNotesTooltip => 'Notes de version';
  @override
  String get replayOnboardingTooltip => 'Rejouer l\'accueil';
}

// Path: settings.diagnosticsPanel
class _Translations$settings$diagnosticsPanel$fr
    extends Translations$settings$diagnosticsPanel$en {
  _Translations$settings$diagnosticsPanel$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Diagnostics de performance';
  @override
  String get copyTrace => 'Copier la trace';
  @override
  String get offenderRanking => 'Classement des fautifs';
  @override
  String get offenderRankingSubtitle =>
      'Facteurs de latence à travers les flux.';
  @override
  String get noOffenders =>
      'Aucun classement de fautifs pour l\'instant. Capturez de l\'activité de diagnostic pour peupler cette liste.';
}

// Path: settings.release
class _Translations$settings$release$fr
    extends Translations$settings$release$en {
  _Translations$settings$release$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Déploiement de version';
  @override
  String get summary => 'Paramètres liés aux mises à jour.';
  @override
  String get deploymentChannel => 'CANAL DE DÉPLOIEMENT';
  @override
  String get captureCrashDiagnostics => 'Capturer les diagnostics de plantage';
  @override
  String get comingSoon => 'Bientôt.';
  @override
  String get checking => 'VÉRIFICATION…';
  @override
  String get pollForUpdates => 'RECHERCHER DES MISES À JOUR';
}

// Path: settings.providerStatus
class _Translations$settings$providerStatus$fr
    extends Translations$settings$providerStatus$en {
  _Translations$settings$providerStatus$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get detecting => 'Détection...';
  @override
  String get ready => 'Prêt';
  @override
  String get notDetected => 'Non détecté';
  @override
  String configured({required Object count}) => '${count} configurés';
  @override
  String get notConfigured => 'Non configuré';
  @override
  String get cliManaged => 'Géré par CLI';
  @override
  String get connected => 'Connecté';
  @override
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} modèle',
        other: '${n} modèles',
      );
  @override
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} fournisseur',
        other: '${n} fournisseurs',
      );
}

// Path: settings.meridiem
class _Translations$settings$meridiem$fr
    extends Translations$settings$meridiem$en {
  _Translations$settings$meridiem$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get am => 'AM';
  @override
  String get pm => 'PM';
}

// Path: settings.offenders
class _Translations$settings$offenders$fr
    extends Translations$settings$offenders$en {
  _Translations$settings$offenders$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get commandStream => 'Commande';
  @override
  String get diffStream => 'Rendu de diff';
  @override
  String get uiStream => 'Mesure UI';
  @override
  String rendererName({required Object mode}) => 'moteur ${mode}';
  @override
  String latencyFailMetric({required Object p95, required Object fail}) =>
      '${p95}ms p95 | ${fail}% échec';
  @override
  String jankFrameMetric({required Object jank, required Object frame}) =>
      '${jank}% à-coups | ${frame}ms trame p95';
  @override
  String inStream({required Object stream}) => 'dans ${stream}';
}

// Path: sync.actions
class _Translations$sync$actions$fr extends Translations$sync$actions$en {
  _Translations$sync$actions$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get syncLabel => 'Synchroniser';
  @override
  String get syncOpenRepoDetail =>
      'Ouvrez un dépôt pour gérer les opérations pousser et tirer.';
  @override
  String get detachedHeadLabel => 'HEAD détachée';
  @override
  String get detachedHeadDetail =>
      'Basculez sur une branche avant de pousser ou tirer.';
  @override
  String get publishBranchLabel => 'Publier la branche';
  @override
  String publishBranchDetail({required Object branch}) =>
      'Pousser ${branch} et définir sa branche de suivi amont.';
  @override
  String get publishButtonLabel => 'Publier';
  @override
  String get syncBranchLabel => 'Synchroniser la branche';
  @override
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => 'Tirer ${behindCount} en rebasant, puis pousser ${aheadCount}.';
  @override
  String get syncBranchButtonLabel => 'Tirer (rebaser) puis pousser';
  @override
  String get pushBranchLabel => 'Pousser la branche';
  @override
  String pushBranchDetail({required Object count, required Object upstream}) =>
      'Pousser ${count} vers ${upstream}.';
  @override
  String get pushBranchButtonLabel => 'Pousser les commits';
  @override
  String get pullUpdatesLabel => 'Tirer les mises à jour';
  @override
  String pullUpdatesDetail({required Object count, required Object upstream}) =>
      'Tirer ${count} depuis ${upstream}.';
  @override
  String syncUpToDateDetail({required Object upstream}) =>
      'Récupérer depuis ${upstream} et actualiser l\'état amont.';
}

// Path: sync.panel
class _Translations$sync$panel$fr extends Translations$sync$panel$en {
  _Translations$sync$panel$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Chargement de l\'état distant';
  @override
  String get loadingMessage =>
      'Vérification des informations de suivi de branche.';
  @override
  String get remoteStatusUnavailable => 'État distant indisponible';
  @override
  String get noUpstream => 'aucun amont';
  @override
  String get aheadLabel => 'En avance';
  @override
  String get behindLabel => 'En retard';
  @override
  String get treeLabel => 'Arbre';
  @override
  String get runningSync => 'Synchronisation en cours…';
  @override
  String get fetching => 'Récupération…';
  @override
  String get fetchOnly => 'Récupérer seulement';
  @override
  String get syncFailed => 'Échec de la synchronisation';
  @override
  String get forcePushRecoveryLabel => 'Poussée forcée (avec bail)';
  @override
  String get conflictsToResolveTitle => 'Conflits à résoudre';
  @override
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} à résoudre : ${list}';
  @override
  String get resolveConflicts => 'Résoudre les conflits';
  @override
  String get workingEllipsis => 'En cours…';
  @override
  String lastActivity({required Object operation}) =>
      'Dernière activité : ${operation}';
  @override
  String get noOutput => 'Aucune sortie.';
  @override
  String resolvedConflicts({required Object count}) => '${count} résolus.';
  @override
  String get cancelledUnchanged => 'Annulé, arbre de travail inchangé.';
  @override
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) =>
      '${count} ont des modifications non validées, validez-les d\'abord pour synchroniser par rebasage (${list}).';
  @override
  String noUpstreamForForcePush({required Object branch}) =>
      'Impossible de forcer la poussée : aucun amont n\'est configuré pour « ${branch} ».';
}

// Path: sync.forcePush
class _Translations$sync$forcePush$fr extends Translations$sync$forcePush$en {
  _Translations$sync$forcePush$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get confirmTitle => 'Forcer la poussée (avec bail) ?';
  @override
  String target({required Object remote, required Object branch}) =>
      'Cible : ${remote}/${branch}';
  @override
  String get warning =>
      'Ceci réécrit la branche distante avec votre historique local. Avec bail, l\'opération s\'interrompt si quelqu\'un a poussé sur le distant après votre dernière récupération, mais les changements déjà récupérés seront tout de même écrasés. À n\'utiliser que lorsque vous avez volontairement rebasé ou amendé au point de faire diverger la branche.';
  @override
  String get confirmButton => 'Forcer la poussée';
}

// Path: xray.board
class _Translations$xray$board$fr extends Translations$xray$board$en {
  _Translations$xray$board$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get movesWithModule => 'bouge avec un autre module';
  @override
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} relecteur',
        other: '${n} relecteurs',
      );
  @override
  String get territory => 'Territoire';
  @override
  String get unreviewed => 'non relu';
}

// Path: xray.cadence
class _Translations$xray$cadence$fr extends Translations$xray$cadence$en {
  _Translations$xray$cadence$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '${sum} commits · ${days} jours\n${lines}';
  @override
  String burstTooltipSingle({required Object n, required Object label}) =>
      '${n} commits le ${label}';
  @override
  String gapTooltip({required Object n, required Object label}) =>
      'écart de ${n} jours · ${label}';
  @override
  String reflogTooltip({required Object n, required Object label}) =>
      '${n} événements reflog le ${label}';
}

// Path: xray.cards
class _Translations$xray$cards$fr extends Translations$xray$cards$en {
  _Translations$xray$cards$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$cards$branchModel$fr branchModel =
      _Translations$xray$cards$branchModel$fr._(_root);
  @override
  late final _Translations$xray$cards$bursty$fr bursty =
      _Translations$xray$cards$bursty$fr._(_root);
  @override
  late final _Translations$xray$cards$hiddenRefs$fr hiddenRefs =
      _Translations$xray$cards$hiddenRefs$fr._(_root);
  @override
  late final _Translations$xray$cards$keystone$fr keystone =
      _Translations$xray$cards$keystone$fr._(_root);
  @override
  late final _Translations$xray$cards$machineHistory$fr machineHistory =
      _Translations$xray$cards$machineHistory$fr._(_root);
  @override
  late final _Translations$xray$cards$migration$fr migration =
      _Translations$xray$cards$migration$fr._(_root);
  @override
  late final _Translations$xray$cards$narrowHotspot$fr narrowHotspot =
      _Translations$xray$cards$narrowHotspot$fr._(_root);
  @override
  late final _Translations$xray$cards$noTags$fr noTags =
      _Translations$xray$cards$noTags$fr._(_root);
  @override
  late final _Translations$xray$cards$reflog$fr reflog =
      _Translations$xray$cards$reflog$fr._(_root);
  @override
  late final _Translations$xray$cards$singleOwner$fr singleOwner =
      _Translations$xray$cards$singleOwner$fr._(_root);
}

// Path: xray.cardTitle
class _Translations$xray$cardTitle$fr extends Translations$xray$cardTitle$en {
  _Translations$xray$cardTitle$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get branches => 'branches';
  @override
  String get bursty => 'par rafales';
  @override
  String get hiddenRefs => 'réfs cachées';
  @override
  String get machineHeavy => 'machine-lourd';
  @override
  String get migration => 'migration';
  @override
  String get narrowHotspot => 'point chaud étroit';
  @override
  String get noTags => 'aucune étiquette';
  @override
  String get reflog => 'reflog';
  @override
  String get singleOwner => 'propriétaire unique';
}

// Path: xray.grain
class _Translations$xray$grain$fr extends Translations$xray$grain$en {
  _Translations$xray$grain$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get coarsest => 'le plus grossier — modules de premier niveau';
  @override
  String get finest => 'grain le plus fin';
  @override
  String get mid => 'grain moyen';
  @override
  String get oneCharacteristic => 'une échelle caractéristique';
}

// Path: xray.header
class _Translations$xray$header$fr extends Translations$xray$header$en {
  _Translations$xray$header$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get dirtyBadge => 'sale';
  @override
  String get machineChip => 'machine';
  @override
  String get refresh => 'Actualiser';
  @override
  String get refreshing => 'Actualisation...';
  @override
  String get title => 'Radiographie du dépôt';
}

// Path: xray.hotspot
class _Translations$xray$hotspot$fr extends Translations$xray$hotspot$en {
  _Translations$xray$hotspot$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get clusterPeers => 'pairs de grappe';
  @override
  String get coChangers => 'co-changeurs';
  @override
  String get keystone => 'clé de voûte';
  @override
  String keystoneScore({required Object score}) => 'clé de voûte  φ=${score}';
}

// Path: xray.inspector
class _Translations$xray$inspector$fr extends Translations$xray$inspector$en {
  _Translations$xray$inspector$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get branchLabel => 'branche';
  @override
  String commitsHumanMachine({required Object n}) => 'humains · ${n} machine';
  @override
  String get commitsLabel => 'commits';
  @override
  String get confidenceLabel => 'confiance';
  @override
  String get curlLabel => 'curl';
  @override
  String get engineSection => 'moteur';
  @override
  String get gradientLabel => 'gradient';
  @override
  String get harmonicLabel => 'harmonique';
  @override
  String get headLabel => 'head';
  @override
  String get hiddenRefsLabel => 'réfs cachées';
  @override
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} fusion',
        other: '${n} fusions',
      );
  @override
  String get noTags => 'aucune étiquette';
  @override
  String get notesLabel => 'notes';
  @override
  String get openCommit => 'Ouvrir le commit';
  @override
  String get pathLabel => 'chemin';
  @override
  String remoteCount({required Object n}) => '${n} distant';
  @override
  String get renamesLabel => 'renommages';
  @override
  String scannedAt({required Object time}) => 'scanné ${time}';
  @override
  String selectedCount({required Object n}) => '${n} sélectionnés';
  @override
  String get shapeLinear => 'linéaire';
  @override
  String get shapeMergeHeavy => 'riche en fusions';
  @override
  String get shapeMostlyLinear => 'quasi linéaire';
  @override
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} remisage',
        other: '${n} remisages',
      );
  @override
  String get stressLabel => 'contrainte';
  @override
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} étiquette',
        other: '${n} étiquettes',
      );
  @override
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} arbre de travail',
        other: '${n} arbres de travail',
      );
}

// Path: xray.loadingCard
class _Translations$xray$loadingCard$fr
    extends Translations$xray$loadingCard$en {
  _Translations$xray$loadingCard$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get buildingMessage =>
      'Sondage de l\'historique Git, des réfs, de la cadence et des points chauds.';
  @override
  String get buildingTitle => 'Construction de la radiographie du dépôt';
  @override
  String get idleMessage => 'Rouvrez le panneau pour sonder le dépôt actuel.';
  @override
  String get idleTitle => 'Radiographie du dépôt';
  @override
  String get unavailableTitle => 'Radiographie du dépôt indisponible';
}

// Path: xray.metabolism
class _Translations$xray$metabolism$fr extends Translations$xray$metabolism$en {
  _Translations$xray$metabolism$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String halfLife({required Object n}) => 'demi-vie de ${n} j';
}

// Path: xray.multi
class _Translations$xray$multi$fr extends Translations$xray$multi$en {
  _Translations$xray$multi$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} grappe',
        other: '${n} grappes',
      );
  @override
  String clusterSingle({required Object id}) => 'grappe ${id}';
  @override
  String couplingSuffix({required Object parts}) => 'couplage ${parts}';
  @override
  String externalCount({required Object n}) => '${n} externe';
  @override
  String mutualCount({required Object n}) => '${n} mutuel';
}

// Path: xray.recency
class _Translations$xray$recency$fr extends Translations$xray$recency$en {
  _Translations$xray$recency$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String days({required Object n}) => '${n} j';
  @override
  String months({required Object n}) => '${n} mois';
  @override
  String get today => 'aujourd\'hui';
  @override
  String weeks({required Object n}) => '${n} sem';
  @override
  String years({required Object n}) => '${n} an';
}

// Path: xray.rings
class _Translations$xray$rings$fr extends Translations$xray$rings$en {
  _Translations$xray$rings$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get hintOneBlended => 'une structure fondue';
  @override
  String get hintSelfSimilar => 'auto-similaire';
  @override
  String get oneBlendedBody =>
      'Une structure fondue — aucune échelle de module séparable ne se distingue encore.';
  @override
  String get overHistory => 'Au fil de l\'histoire';
  @override
  String get parts => 'parties';
  @override
  String get readingHint => 'lecture de la structure…';
  @override
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} échelle',
        other: '${n} échelles',
      );
  @override
  String get scaleDissolved => 'une échelle structurelle s\'est dissoute';
  @override
  String get scaleEmerged => 'une échelle structurelle a émergé';
  @override
  String get scaleSpectrum => 'spectre d\'échelles';
  @override
  String get selfSimilarBody =>
      'Auto-similaire — la structure se répète à travers les échelles, sans niveau caractéristique unique.';
  @override
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} basculement dans l\'histoire',
        other: '${n} basculements dans l\'histoire',
      );
  @override
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} basculement structurel',
        other: '${n} basculements structurels',
      );
  @override
  String get title => 'Anneaux de croissance';
  @override
  String get unavailable => 'indisponible';
}

// Path: xray.stats
class _Translations$xray$stats$fr extends Translations$xray$stats$en {
  _Translations$xray$stats$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get alive => 'vivant';
  @override
  String get files => 'fichiers';
  @override
  String get lastTouched => 'dernière touche';
  @override
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'propriétaire',
        other: 'propriétaires',
      );
  @override
  String get touches => 'touches';
}

// Path: xray.stratumLabel
class _Translations$xray$stratumLabel$fr
    extends Translations$xray$stratumLabel$en {
  _Translations$xray$stratumLabel$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'actuel';
  @override
  String get legacy => 'hérité';
  @override
  String get zone => 'zone du dépôt';
}

// Path: xray.summary
class _Translations$xray$summary$fr extends Translations$xray$summary$en {
  _Translations$xray$summary$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String analysisFailed({required Object error}) =>
      'Échec de l\'analyse : ${error}';
  @override
  String get analyze => 'Analyser';
  @override
  String get copied => 'Résumé copié dans le presse-papiers.';
  @override
  String get directionHint => 'direction';
  @override
  String get download => 'Télécharger';
  @override
  String get emptyState =>
      'Lancez l\'analyse Logos pour cartographier la structure et les régions de ce dépôt.\n(tw : de la bouillie pour l\'instant)';
  @override
  String get exit => 'Quitter';
  @override
  String get generating =>
      'Lecture du dépôt et regroupement des caractéristiques…';
  @override
  String get noModel => 'Aucun modèle IA configuré.';
  @override
  String get noModelConfigured => 'aucun modèle IA configuré';
  @override
  String presentWith({required Object label}) => 'présenter avec ${label}';
  @override
  String presentingWith({required Object label}) =>
      'présentation avec ${label}…';
  @override
  String get reanalyze => 'Ré-analyser';
  @override
  String get saveDialogTitle => 'Enregistrer le résumé du dépôt';
  @override
  String saveFailed({required Object error}) =>
      'Échec de l\'enregistrement : ${error}';
  @override
  String get savePresentationDialogTitle => 'Enregistrer la présentation';
  @override
  String savedTo({required Object path}) => 'Enregistré dans ${path}';
}

// Path: xray.tabs
class _Translations$xray$tabs$fr extends Translations$xray$tabs$en {
  _Translations$xray$tabs$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get map => 'Carte';
  @override
  String get signals => 'Signaux';
  @override
  String get summary => 'Résumé';
  @override
  String get time => 'Temps';
}

// Path: xray.trajectory
class _Translations$xray$trajectory$fr extends Translations$xray$trajectory$en {
  _Translations$xray$trajectory$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get connectivity => 'connectivité';
  @override
  String events({required Object n}) => '${n} événements';
  @override
  String get openInOrrery => 'Ouvrir dans l\'Orrery';
  @override
  String get readingHint => 'lecture de l\'historique…';
  @override
  String snapshots({required Object n}) => '${n} instantanés';
  @override
  String get steady =>
      'Stable — aucun événement structurel dans cette fenêtre.';
  @override
  String get title => 'Trajectoire structurelle';
}

// Path: xray.verdict
class _Translations$xray$verdict$fr extends Translations$xray$verdict$en {
  _Translations$xray$verdict$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String canonical({required Object pct}) => '${pct}% canonique';
  @override
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · ${canonical}% canonique · ${decisive}% décisif';
}

// Path: changes.mergeEditor.trust
class _Translations$changes$mergeEditor$trust$fr
    extends Translations$changes$mergeEditor$trust$en {
  _Translations$changes$mergeEditor$trust$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get manual => 'manuel';
  @override
  String get safe => 'sûr';
  @override
  String get guided => 'guidé';
  @override
  String get assisted => 'assisté';
  @override
  String get full => 'complet';
  @override
  String label({required Object label}) => 'confiance : ${label}';
}

// Path: changes.mergeEditor.keyHints
class _Translations$changes$mergeEditor$keyHints$fr
    extends Translations$changes$mergeEditor$keyHints$en {
  _Translations$changes$mergeEditor$keyHints$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get accept => 'accepter';
  @override
  String get other => 'autre';
  @override
  String get both => 'les deux';
  @override
  String get navigate => 'naviguer';
  @override
  String get jumpNext => 'aller au suivant';
}

// Path: changes.mergeFlow.op
class _Translations$changes$mergeFlow$op$fr
    extends Translations$changes$mergeFlow$op$en {
  _Translations$changes$mergeFlow$op$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'fusion';
  @override
  String get cherryPick => 'picorage';
  @override
  String get revert => 'annulation';
  @override
  String get resolve => 'résolution';
  @override
  String get switchOp => 'bascule';
  @override
  String get pull => 'tirage';
  @override
  String get rebase => 'rebasage';
  @override
  String rebaseOnto({required Object branch, required Object base}) =>
      'rebaser ${branch} sur ${base}';
}

// Path: diff.pinned.tempo
class _Translations$diff$pinned$tempo$fr
    extends Translations$diff$pinned$tempo$en {
  _Translations$diff$pinned$tempo$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get hotOwnerLane =>
      'Mouvement récent avec un propriétaire fort à proximité.';
  @override
  String get activeSeam => 'Mouvement récent de plusieurs mains à proximité.';
  @override
  String get stableOwnerLane =>
      'Voie de longue date avec un propriétaire dominant.';
  @override
  String get sharedLongLivedSeam =>
      'Couture partagée qui s\'est accumulée avec le temps.';
  @override
  String get sharedLane => 'Voie partagée sans propriétaire dominant unique.';
  @override
  String get resolving =>
      'L\'historique se précise encore autour de cette ligne.';
}

// Path: diff.pinned.tone
class _Translations$diff$pinned$tone$fr
    extends Translations$diff$pinned$tone$en {
  _Translations$diff$pinned$tone$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get hot => 'Chaud';
  @override
  String get novel => 'Nouveau';
  @override
  String get contested => 'Disputé';
  @override
  String get spreading => 'En diffusion';
  @override
  String get stable => 'Stable';
}

// Path: diff.pinned.summary
class _Translations$diff$pinned$summary$fr
    extends Translations$diff$pinned$summary$en {
  _Translations$diff$pinned$summary$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String livesIn({required Object concept}) => 'Vit dans ${concept}';
  @override
  String get sitsInLocalSeam => 'Situé dans une couture locale';
  @override
  String workedMostlyBy({required Object owner}) =>
      'travaillé surtout par ${owner} à proximité';
  @override
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'résonne dans ${n} autre endroit',
        other: 'résonne dans ${n} autres endroits',
      );
  @override
  String inspectNext({required Object path, required Object detail}) =>
      'inspecter ${path} ensuite${detail}';
  @override
  String inspectDetail({required Object reason}) => ' (${reason})';
}

// Path: diff.pinned.tightness
class _Translations$diff$pinned$tightness$fr
    extends Translations$diff$pinned$tightness$en {
  _Translations$diff$pinned$tightness$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get tight => 'ajustement serré';
  @override
  String get close => 'ajustement proche';
  @override
  String get loose => 'ajustement lâche';
}

// Path: diff.pinned.witness
class _Translations$diff$pinned$witness$fr
    extends Translations$diff$pinned$witness$en {
  _Translations$diff$pinned$witness$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String nearbySupport({required Object label}) =>
      'Appui à proximité · ${label}';
  @override
  String localizedMove({required Object label}) =>
      'Mouvement localisé · ${label}';
  @override
  String surprisingMove({required Object label}) =>
      'Mouvement surprenant · ${label}';
}

// Path: diff.pinned.integrity
class _Translations$diff$pinned$integrity$fr
    extends Translations$diff$pinned$integrity$en {
  _Translations$diff$pinned$integrity$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get stableStructure => 'Structure stable';
  @override
  String get conflictingSignals => 'Signaux contradictoires';
  @override
  String get novelShape => 'Forme nouvelle';
}

// Path: diff.pinned.related
class _Translations$diff$pinned$related$fr
    extends Translations$diff$pinned$related$en {
  _Translations$diff$pinned$related$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get testMirror => 'Miroir de test';
  @override
  String get semanticHistorySibling => 'Frère sémantique + historique';
  @override
  String get recentCoChange => 'Co-changement récent';
  @override
  String get semanticSibling => 'Frère sémantique';
  @override
  String get relatedStructure => 'Structure liée';
  @override
  String get tightlyBound => 'fortement lié';
  @override
  String get orbiting => 'en orbite';
  @override
  String get weaklyCoupled => 'faiblement couplé';
  @override
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class _Translations$diff$pinned$axis$fr
    extends Translations$diff$pinned$axis$en {
  _Translations$diff$pinned$axis$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get historyTrail => 'trace d\'historique';
  @override
  String get testMirrorLane => 'voie miroir de test';
  @override
  String get structuralLane => 'voie structurelle';
  @override
  String get semanticNeighbourhood => 'voisinage sémantique';
}

// Path: history.commitLede.semantics
class _Translations$history$commitLede$semantics$fr
    extends Translations$history$commitLede$semantics$en {
  _Translations$history$commitLede$semantics$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get importanceHigh => 'importance élevée';
  @override
  String get importanceModerate => 'importance modérée';
  @override
  String get mostlyAdditions => 'surtout des ajouts';
  @override
  String get mostlyDeletions => 'surtout des suppressions';
  @override
  String get tightlyCoupled => 'fichiers fortement couplés';
  @override
  String get overlapsWorkingTree => 'recoupe votre arbre de travail';
}

// Path: onboarding.repo.doors
class _Translations$onboarding$repo$doors$fr
    extends Translations$onboarding$repo$doors$en {
  _Translations$onboarding$repo$doors$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$repo$doors$open$fr open =
      _Translations$onboarding$repo$doors$open$fr._(_root);
  @override
  late final _Translations$onboarding$repo$doors$clone$fr clone =
      _Translations$onboarding$repo$doors$clone$fr._(_root);
  @override
  late final _Translations$onboarding$repo$doors$create$fr create =
      _Translations$onboarding$repo$doors$create$fr._(_root);
}

// Path: onboarding.repo.cloneForm
class _Translations$onboarding$repo$cloneForm$fr
    extends Translations$onboarding$repo$cloneForm$en {
  _Translations$onboarding$repo$cloneForm$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Cloner depuis une URL';
  @override
  String get urlLabel => 'URL du dépôt';
  @override
  String get targetLabel => 'Dossier cible';
  @override
  String get browse => 'Parcourir…';
  @override
  String get clone => 'Cloner';
  @override
  String get cloning => 'Clonage…';
}

// Path: onboarding.repo.pickers
class _Translations$onboarding$repo$pickers$fr
    extends Translations$onboarding$repo$pickers$en {
  _Translations$onboarding$repo$pickers$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get openRepository => 'Ouvrir un dépôt';
  @override
  String get createRepository => 'Créer un dépôt';
  @override
  String get cloneTarget => 'Cible du clonage';
}

// Path: onboarding.repo.errors
class _Translations$onboarding$repo$errors$fr
    extends Translations$onboarding$repo$errors$en {
  _Translations$onboarding$repo$errors$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get urlAndTargetRequired => 'URL et chemin cible requis.';
  @override
  String get createFailed => 'Échec de la création du dépôt.';
  @override
  String get cloneFailed => 'Échec du clonage du dépôt.';
}

// Path: onboarding.preview.panels
class _Translations$onboarding$preview$panels$fr
    extends Translations$onboarding$preview$panels$en {
  _Translations$onboarding$preview$panels$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get xray => 'radiographie du dépôt';
  @override
  String get settings => 'paramètres';
}

// Path: onboarding.preview.sidebar
class _Translations$onboarding$preview$sidebar$fr
    extends Translations$onboarding$preview$sidebar$en {
  _Translations$onboarding$preview$sidebar$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get projectsHeader => 'Projets';
}

// Path: onboarding.preview.changes
class _Translations$onboarding$preview$changes$fr
    extends Translations$onboarding$preview$changes$en {
  _Translations$onboarding$preview$changes$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String filesStagedCount({required Object staged, required Object total}) =>
      '${staged} sur ${total} fichiers';
  @override
  String stagedCount({required Object n}) => '${n} indexés';
  @override
  String get commitMessageHint => 'Message de commit…';
  @override
  String get commitAndPush => 'Valider et pousser';
}

// Path: onboarding.preview.history
class _Translations$onboarding$preview$history$fr
    extends Translations$onboarding$preview$history$en {
  _Translations$onboarding$preview$history$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'Historique';
  @override
  String get viewingLast => '20 derniers commits affichés';
  @override
  String get inFlight => 'EN VOL';
  @override
  String get you => 'vous';
  @override
  String get commit1 => 'apprendre au renard à flairer avant d\'avaler';
  @override
  String get commit2 => 'ambre : retenir l\'odeur jusqu\'au matin';
  @override
  String get commit3 => 'retirer le chou au profit de l\'ambre + l\'épine';
  @override
  String get commit4 => 'l\'épine garde le portail';
}

// Path: onboarding.preview.branches
class _Translations$onboarding$preview$branches$fr
    extends Translations$onboarding$preview$branches$en {
  _Translations$onboarding$preview$branches$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get lensBranches => 'BRANCHES';
  @override
  String get lensPRs => 'PR';
  @override
  String get absorbed => 'absorbée';
  @override
  String get desk => 'bureau';
  @override
  String get head => 'HEAD';
  @override
  String tracking({required Object ref}) => '→ suivi : ${ref}';
}

// Path: onboarding.preview.diff
class _Translations$onboarding$preview$diff$fr
    extends Translations$onboarding$preview$diff$en {
  _Translations$onboarding$preview$diff$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get readmeTagline => 'Votre client Git personnel.';
}

// Path: releaseNotes.about.whyFlutter
class _Translations$releaseNotes$about$whyFlutter$fr
    extends Translations$releaseNotes$about$whyFlutter$en {
  _Translations$releaseNotes$about$whyFlutter$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'POURQUOI FLUTTER ?';
  @override
  String get body =>
      'La première version était une application Tauri (Rust + TypeScript). Je la trouvais déjà lente. Puis j\'ai entendu un streamer dire exactement la même chose, sur un stream que je ne regarde pas d\'habitude, et ça a été le déclic pour enfin changer. Il ne suggérait pas Flutter, loin de là. J\'ai découvert Dart de mon côté, bricolé un prototype, et le démarrage est passé d\'environ 15 secondes à moins d\'une seconde. Le jour et la nuit. Adieu l\'ère Tauri.\n\nLe pipeline de rendu de Flutter tient plus du moteur de jeu que du DOM, et pour une application de bureau où l\'interface est le produit, c\'est tout ce qui compte. Dart s\'est aussi révélé être un très bon langage. Les maths derrière le moteur spectral avaient d\'abord été prototypées en Rust, donc ce travail s\'est reporté sans souci.\n\nFlutter est multiplateforme par défaut, ce qui est génial, mais c\'est du Google dans l\'âme, alors il y a quelques bizarreries.';
}

// Path: releaseNotes.about.spectralEngine
class _Translations$releaseNotes$about$spectralEngine$fr
    extends Translations$releaseNotes$about$spectralEngine$en {
  _Translations$releaseNotes$about$spectralEngine$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'QU\'EST-CE QUE LE MOTEUR SPECTRAL ?';
  @override
  String get body =>
      'Chaque fois que vous validez, les fichiers que vous modifiez ensemble forment des motifs au fil du temps. Le moteur spectral lit votre graphe de commits et décompose ces motifs de co-changement en signaux : quels fichiers sont couplés, à quel point, et quel rôle structurel ils jouent dans le dépôt. En gros, de l\'analyse spectrale sur votre historique de développement. Dans un client git. Volontairement.\n\nLes maths sont nouvelles, alors je les traite comme le game feel : régler, tester, ajuster, et continuer jusqu\'à ce que les signaux sonnent juste.\n\nCes signaux alimentent tout. Le sismographe dans l\'historique, les barres peintes sous les intitulés de commits, le système de revue, la Muse, la constellation de fichiers. Toute l\'application raisonne depuis cette couche vers le haut, jamais l\'inverse.';
}

// Path: releaseNotes.about.whereGoing
class _Translations$releaseNotes$about$whereGoing$fr
    extends Translations$releaseNotes$about$whereGoing$en {
  _Translations$releaseNotes$about$whereGoing$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'OÙ EST-CE QUE ÇA VA ?';
  @override
  String get body =>
      'Le premier jalon, c\'est la parité complète avec GitHub Desktop, SourceTree et GitKraken. Un client git multiplateforme qui donne une impression de rapidité et gère les fondamentaux mieux que tout le reste. C\'est en grande partie fait. Le moteur spectral nous donne déjà un avantage sur les opérations que les autres clients vous forcent à réfléchir à la main.\n\nAu-delà, l\'objectif est de surpasser tous les autres clients git en vitesse, en accessibilité, en intelligence et en UX globale. Il y a plus dans les tuyaux que ce qui est annoncé ici.';
}

// Path: settings.commitPreview.title
class _Translations$settings$commitPreview$title$fr
    extends Translations$settings$commitPreview$title$en {
  _Translations$settings$commitPreview$title$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$verbLed$fr verbLed =
      _Translations$settings$commitPreview$title$verbLed$fr._(_root);
  @override
  late final _Translations$settings$commitPreview$title$descriptive$fr
  descriptive = _Translations$settings$commitPreview$title$descriptive$fr._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$title$narrative$fr narrative =
      _Translations$settings$commitPreview$title$narrative$fr._(_root);
}

// Path: settings.commitPreview.base
class _Translations$settings$commitPreview$base$fr
    extends Translations$settings$commitPreview$base$en {
  _Translations$settings$commitPreview$base$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$base$verbLed$fr verbLed =
      _Translations$settings$commitPreview$base$verbLed$fr._(_root);
  @override
  late final _Translations$settings$commitPreview$base$descriptive$fr
  descriptive = _Translations$settings$commitPreview$base$descriptive$fr._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$base$narrative$fr narrative =
      _Translations$settings$commitPreview$base$narrative$fr._(_root);
}

// Path: settings.commitPreview.balancedSuffix
class _Translations$settings$commitPreview$balancedSuffix$fr
    extends Translations$settings$commitPreview$balancedSuffix$en {
  _Translations$settings$commitPreview$balancedSuffix$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$verbLed$fr
  verbLed = _Translations$settings$commitPreview$balancedSuffix$verbLed$fr._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$descriptive$fr
  descriptive =
      _Translations$settings$commitPreview$balancedSuffix$descriptive$fr._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$narrative$fr
  narrative =
      _Translations$settings$commitPreview$balancedSuffix$narrative$fr._(_root);
}

// Path: settings.commitPreview.everythingSuffix
class _Translations$settings$commitPreview$everythingSuffix$fr
    extends Translations$settings$commitPreview$everythingSuffix$en {
  _Translations$settings$commitPreview$everythingSuffix$fr._(
    TranslationsFr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$verbLed$fr
  verbLed = _Translations$settings$commitPreview$everythingSuffix$verbLed$fr._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$descriptive$fr
  descriptive =
      _Translations$settings$commitPreview$everythingSuffix$descriptive$fr._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$narrative$fr
  narrative =
      _Translations$settings$commitPreview$everythingSuffix$narrative$fr._(
        _root,
      );
}

// Path: xray.cards.branchModel
class _Translations$xray$cards$branchModel$fr
    extends Translations$xray$cards$branchModel$en {
  _Translations$xray$cards$branchModel$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get broadClaim =>
      'Le dépôt a assez de surface de branches pour rendre la navigation par branche payante.';
  @override
  String get broadTitle => 'Le modèle de branches a de la surface';
  @override
  String localBranchesDetail({required Object count}) =>
      '${count} branches locales.';
  @override
  String get localBranchesLabel => 'Branches locales';
  @override
  String remoteBranchesDetail({required Object count}) =>
      '${count} branches distantes.';
  @override
  String get remoteBranchesLabel => 'Branches distantes';
  @override
  String get simpleClaim => 'Le modèle de branches visible est étroit.';
  @override
  String get simpleTitle => 'Modèle de branches simple';
}

// Path: xray.cards.bursty
class _Translations$xray$cards$bursty$fr
    extends Translations$xray$cards$bursty$en {
  _Translations$xray$cards$bursty$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Le travail arrive par rafales concentrées plutôt qu\'à un rythme quotidien régulier.';
  @override
  String get title => 'Cadence de développement par rafales';
}

// Path: xray.cards.hiddenRefs
class _Translations$xray$cards$hiddenRefs$fr
    extends Translations$xray$cards$hiddenRefs$en {
  _Translations$xray$cards$hiddenRefs$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object count}) =>
      '${count} réfs vivent hors de l\'espace normal branches/étiquettes.';
  @override
  String evidenceDetail({required Object count}) =>
      '${count} réfs hors heads/remotes/tags.';
  @override
  String get evidenceLabel => 'Réfs cachées';
  @override
  String get namespacesLabel => 'Espaces de noms';
  @override
  String get title => 'Espaces de noms Git cachés';
}

// Path: xray.cards.keystone
class _Translations$xray$cards$keystone$fr
    extends Translations$xray$cards$keystone$en {
  _Translations$xray$cards$keystone$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String claim({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
    n,
    one:
        'Un fichier porte un poids de co-changement disproportionné par rapport à son nombre de touches.',
    other:
        'Un petit ensemble de fichiers porte un poids de co-changement disproportionné par rapport à leur nombre de touches.',
  );
  @override
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: '${n} touche · attraction φ=${score}',
        other: '${n} touches · attraction φ=${score}',
      );
  @override
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(
        n,
        one: 'Fichier-pont clé de voûte',
        other: '${n} fichiers-ponts clés de voûte',
      );
}

// Path: xray.cards.machineHistory
class _Translations$xray$cards$machineHistory$fr
    extends Translations$xray$cards$machineHistory$en {
  _Translations$xray$cards$machineHistory$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Les commits de type point de contrôle faussent matériellement les métriques d\'historique naïves.';
  @override
  String machineCommitsDetail({required Object count}) =>
      '${count} commits correspondaient à des motifs machine/session.';
  @override
  String get machineCommitsLabel => 'Commits machine';
  @override
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '${raw} commits bruts contre ${filtered} commits filtrés.';
  @override
  String get rawVsFilteredLabel => 'Bruts vs filtrés';
  @override
  String get title => 'L\'historique machine domine les métriques brutes';
}

// Path: xray.cards.migration
class _Translations$xray$cards$migration$fr
    extends Translations$xray$cards$migration$en {
  _Translations$xray$cards$migration$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object older, required Object newer}) =>
      'L\'historique glisse de `${older}` vers `${newer}`, ce qui suggère une transition de pile ou de surface.';
  @override
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches} touches, dernière activité ${lastActive}.';
  @override
  String get title => 'Migration d\'architecture visible';
}

// Path: xray.cards.narrowHotspot
class _Translations$xray$cards$narrowHotspot$fr
    extends Translations$xray$cards$narrowHotspot$en {
  _Translations$xray$cards$narrowHotspot$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Un petit ensemble de fichiers et de dossiers absorbe une part disproportionnée des changements.';
  @override
  String get title => 'La concentration des points chauds est étroite';
  @override
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path} représente ${pct}% de l\'ensemble des points chauds visibles.';
  @override
  String get topHotspotLabel => 'Point chaud principal';
  @override
  String visibleAuthorsDetail({required Object count}) =>
      '${count} auteurs dans cette tranche d\'historique.';
  @override
  String get visibleAuthorsLabel => 'Auteurs visibles';
}

// Path: xray.cards.noTags
class _Translations$xray$cards$noTags$fr
    extends Translations$xray$cards$noTags$en {
  _Translations$xray$cards$noTags$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Les étiquettes Git ne servent pas de couche visible de version ou de jalon.';
  @override
  String remoteEndpointsDetail({required Object count}) =>
      '${count} points de terminaison distants configurés.';
  @override
  String get remoteEndpointsLabel => 'Points de terminaison distants';
  @override
  String get tagCountDetail => '0 étiquette trouvée.';
  @override
  String get tagCountLabel => 'Nombre d\'étiquettes';
  @override
  String get title => 'Aucune piste formelle de version/étiquette';
}

// Path: xray.cards.reflog
class _Translations$xray$cards$reflog$fr
    extends Translations$xray$cards$reflog$en {
  _Translations$xray$cards$reflog$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Le volume du reflog suggère une itération locale concentrée au-delà des commits publiés.';
  @override
  String get peakReflogDayLabel => 'Jour de pic du reflog';
  @override
  String get title => 'Sessions d\'édition locale intenses';
}

// Path: xray.cards.singleOwner
class _Translations$xray$cards$singleOwner$fr
    extends Translations$xray$cards$singleOwner$en {
  _Translations$xray$cards$singleOwner$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object path, required Object kind}) =>
      '`${path}` est un ${kind} fortement touché avec un seul auteur visible distinct.';
  @override
  String ownerCountDetail({required Object count}) =>
      '${count} auteurs distincts.';
  @override
  String get ownerCountLabel => 'Nombre de propriétaires';
  @override
  String get title => 'Point chaud à propriétaire unique';
  @override
  String get touchCountLabel => 'Nombre de touches';
  @override
  String touchDetailFiltered({required Object count}) =>
      '${count} touches dans l\'historique filtré.';
  @override
  String touchDetailRaw({required Object count}) =>
      '${count} touches dans l\'historique brut.';
}

// Path: onboarding.repo.doors.open
class _Translations$onboarding$repo$doors$open$fr
    extends Translations$onboarding$repo$doors$open$en {
  _Translations$onboarding$repo$doors$open$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Ouvrir';
  @override
  String get subtitle => 'existant';
  @override
  String get hint => 'un dépôt que vous avez déjà';
}

// Path: onboarding.repo.doors.clone
class _Translations$onboarding$repo$doors$clone$fr
    extends Translations$onboarding$repo$doors$clone$en {
  _Translations$onboarding$repo$doors$clone$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Cloner';
  @override
  String get subtitle => 'depuis une URL';
  @override
  String get hint => 'collez une URL distante';
}

// Path: onboarding.repo.doors.create
class _Translations$onboarding$repo$doors$create$fr
    extends Translations$onboarding$repo$doors$create$en {
  _Translations$onboarding$repo$doors$create$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Créer';
  @override
  String get subtitle => 'nouveau';
  @override
  String get hint => 'démarrez quelque chose de neuf';
}

// Path: settings.commitPreview.title.verbLed
class _Translations$settings$commitPreview$title$verbLed$fr
    extends Translations$settings$commitPreview$title$verbLed$en {
  _Translations$settings$commitPreview$title$verbLed$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Laisser le renard sauter les biscuits qui sentent mauvais';
  @override
  String get s2 =>
      'Dresser le renard à refuser les biscuits trafiqués avant de les avaler';
  @override
  String get s3 =>
      'Contraindre le renard à examiner chaque biscuit au portail comme une scène de crime';
  @override
  String get def => 'Apprendre au renard à refuser les mauvais biscuits';
}

// Path: settings.commitPreview.title.descriptive
class _Translations$settings$commitPreview$title$descriptive$fr
    extends Translations$settings$commitPreview$title$descriptive$en {
  _Translations$settings$commitPreview$title$descriptive$fr._(
    TranslationsFr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'le renard trie désormais les biscuits';
  @override
  String get s2 => 'Routine d\'inspection des biscuits, inculquée au renard';
  @override
  String get s3 =>
      'Expertise médico-légale du biscuit, ancrée dans le renard à force de répétition';
  @override
  String get def =>
      'Protocole de reniflage des biscuits, installé dans le renard';
}

// Path: settings.commitPreview.title.narrative
class _Translations$settings$commitPreview$title$narrative$fr
    extends Translations$settings$commitPreview$title$narrative$en {
  _Translations$settings$commitPreview$title$narrative$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      'le renard s\'est mis à laisser les biscuits qui sentaient bizarre';
  @override
  String get s2 =>
      'Assis avec le renard, on a passé en revue quels biscuits refuser';
  @override
  String get s3 =>
      'Passé une bonne partie d\'un après-midi à convaincre le renard que tout biscuit offert n\'est pas, de bonne foi, un biscuit';
  @override
  String get def =>
      'Demandé au renard de flairer les biscuits avant de les manger';
}

// Path: settings.commitPreview.base.verbLed
class _Translations$settings$commitPreview$base$verbLed$fr
    extends Translations$settings$commitPreview$base$verbLed$en {
  _Translations$settings$commitPreview$base$verbLed$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Le renard jette un œil. Tout ce qui cloche, il laisse.';
  @override
  String get s2 =>
      'Le renard inspecte chaque jeton, décline tout ce qui sent mauvais, et note le refus sur le perron.';
  @override
  String get s3 =>
      'Le renard tourne autour de chaque jeton, hume l\'air sous trois angles, refuse ceux qui sentent le faux, et attend un instant pour être sûr que le refus tienne.';
  @override
  String get def =>
      'Le renard flaire désormais chaque jeton et décline poliment les suspects.';
}

// Path: settings.commitPreview.base.descriptive
class _Translations$settings$commitPreview$base$descriptive$fr
    extends Translations$settings$commitPreview$base$descriptive$en {
  _Translations$settings$commitPreview$base$descriptive$fr._(
    TranslationsFr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Léger passage sur les bizarres, surtout.';
  @override
  String get s2 =>
      'Un refus documenté sur chaque jeton à l\'odeur suspecte, prononcé depuis le perron et consigné.';
  @override
  String get s3 =>
      'Un refus notarié par jeton à l\'odeur suspecte, prononcé depuis le perron une patte levée, l\'autre immobile.';
  @override
  String get def =>
      'Un refus poli sur les jetons suspects, prononcé depuis le perron.';
}

// Path: settings.commitPreview.base.narrative
class _Translations$settings$commitPreview$base$narrative$fr
    extends Translations$settings$commitPreview$base$narrative$en {
  _Translations$settings$commitPreview$base$narrative$fr._(TranslationsFr root)
    : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Le renard a en gros arrêté de manger les bizarres. Facile.';
  @override
  String get s2 =>
      'Chaque jeton passait avant sans trop réfléchir ; maintenant il y a une pause, un vrai coup d\'œil, et un refus pour ceux qui ne sentent pas bon.';
  @override
  String get s3 =>
      'Chaque jeton passait avant sans réfléchir. Maintenant : une pause. L\'air, inspiré. L\'air, retenu. Le renard guette sur les planches du perron le petit tressaillement qu\'elles ont parfois quand quelque chose cloche, et alors seulement la décision tombe.';
  @override
  String get def =>
      'Chaque jeton se faisait avaler sans cérémonie ; maintenant, on renifle d\'abord.';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class _Translations$settings$commitPreview$balancedSuffix$verbLed$fr
    extends Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  _Translations$settings$commitPreview$balancedSuffix$verbLed$fr._(
    TranslationsFr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Le perron, ça va. L\'arrière-cour, on verra.';
  @override
  String get s2 =>
      ' Perron balayé après chaque refus ; boue de l\'arrière-cour tolérée aux heures affichées.';
  @override
  String get s3 =>
      ' Perron balayé et rebalayé ; boue de l\'arrière-cour cataloguée par empreinte et par météo, et le renard s\'attarde au seuil plus longtemps qu\'avant.';
  @override
  String get def =>
      ' Le perron reste propre ; l\'arrière-cour garde ses droits à la boue.';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class _Translations$settings$commitPreview$balancedSuffix$descriptive$fr
    extends Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  _Translations$settings$commitPreview$balancedSuffix$descriptive$fr._(
    TranslationsFr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Perron ok. L\'arrière-cour fait des trucs d\'arrière-cour.';
  @override
  String get s2 =>
      ' Perron comme zone propre de niveau preuve ; arrière-cour comme zone de boue désignée, horaires affichés.';
  @override
  String get s3 =>
      ' Perron comme salle blanche de niveau preuve ; arrière-cour comme archive de boue cataloguée ; seuil comme l\'endroit où le renard reste planté à réfléchir trop longtemps.';
  @override
  String get def =>
      ' Perron propre ; droits à la boue préservés dans l\'arrière-cour.';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class _Translations$settings$commitPreview$balancedSuffix$narrative$fr
    extends Translations$settings$commitPreview$balancedSuffix$narrative$en {
  _Translations$settings$commitPreview$balancedSuffix$narrative$fr._(
    TranslationsFr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Le perron, ça allait. L\'arrière-cour, qui sait.';
  @override
  String get s2 =>
      ' Le perron était tenu propre ensuite ; le renard se retirait dans l\'arrière-cour, là où se fait la réflexion.';
  @override
  String get s3 =>
      ' Le perron a été récuré deux fois ce soir-là. Le renard a arpenté l\'arrière-cour lentement, s\'est arrêté au même piquet de clôture que d\'habitude, et a regardé le perron comme s\'il lui devait quelque chose.';
  @override
  String get def =>
      ' Le perron reste propre, même si l\'arrière-cour l\'emporte encore en dignité.';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class _Translations$settings$commitPreview$everythingSuffix$verbLed$fr
    extends Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  _Translations$settings$commitPreview$everythingSuffix$verbLed$fr._(
    TranslationsFr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Ambre est là. La dérive dérive. L\'épine pique s\'il le faut. La plupart du temps, rien.';
  @override
  String get s2 =>
      ' Ambre retient chaque odeur pour examen. La dérive porte l\'air du jour vers l\'épine du portail, qui marque chaque refus pour le décompte du soir.';
  @override
  String get s3 =>
      ' Ambre retient chaque odeur et lui donne un poids différent selon l\'heure. La dérive traverse le perron sous des angles qui ne devraient pas compter mais comptent. L\'épine du portail pique une fois pour les refus et deux fois pour ceux que le renard a failli manquer, et le renard fait la différence même quand personne d\'autre ne la voit.';
  @override
  String get def =>
      ' Ambre retient l\'odeur. La dérive la fait circuler. L\'épine du portail attrape ce qui ne devrait pas passer.';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class _Translations$settings$commitPreview$everythingSuffix$descriptive$fr
    extends
        Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  _Translations$settings$commitPreview$everythingSuffix$descriptive$fr._(
    TranslationsFr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Ambre sur le piquet. La dérive dans l\'air. L\'épine au portail. Ça va.';
  @override
  String get s2 =>
      ' Ambre comme témoin d\'odeur désigné ; la dérive comme ambiance consignée ; les marques d\'épine comme le relevé des refus du jour, réconcilié au crépuscule.';
  @override
  String get s3 =>
      ' Ambre comme témoin d\'odeur dont le silence est déjà une lecture ; la dérive comme ambiance à motif qui bouge de travers les jours où quelque chose cloche ; l\'épine comme teneuse de comptes du portail, dont le renard vérifie les marques avant de dormir et de nouveau avant l\'aube.';
  @override
  String get def =>
      ' Ambre comme témoin d\'odeur ; la dérive comme contexte ambiant ; l\'épine comme la marque de refus silencieuse du portail.';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class _Translations$settings$commitPreview$everythingSuffix$narrative$fr
    extends Translations$settings$commitPreview$everythingSuffix$narrative$en {
  _Translations$settings$commitPreview$everythingSuffix$narrative$fr._(
    TranslationsFr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsFr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Ambre traînait dans le coin. La dérive allait et venait. L\'épine faisait son petit truc tranquille. Bref, c\'était peinard.';
  @override
  String get s2 =>
      ' Ambre a tenu le relevé des odeurs du jour, la dérive était notée par direction et par heure, et les marques de l\'épine ont été décomptées et contresignées par le perron.';
  @override
  String get s3 =>
      ' Ambre a tenu le relevé des odeurs, mais le renard jure qu\'il pèse plus lourd certains matins. La dérive a traversé le perron comme toujours, c\'est-à-dire de travers les jours qui comptent. L\'épine du portail a marqué chaque refus ; le renard est sorti aux premières lueurs pour les compter, comme on compte des marches qu\'on a déjà comptées.';
  @override
  String get def =>
      ' Ambre a tenu le relevé des odeurs, la dérive a fait circuler l\'air, et l\'épine du portail a attrapé ce qu\'il fallait attraper.';
}
