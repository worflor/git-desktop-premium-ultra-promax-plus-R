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
class TranslationsEs extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsEs({
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
             locale: AppLocale.es,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <es>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final TranslationsEs _root = this; // ignore: unused_field

  @override
  TranslationsEs $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsEs(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$app$es app = _Translations$app$es._(_root);
  @override
  late final _Translations$backend$es backend = _Translations$backend$es._(
    _root,
  );
  @override
  late final _Translations$branches$es branches = _Translations$branches$es._(
    _root,
  );
  @override
  late final _Translations$changes$es changes = _Translations$changes$es._(
    _root,
  );
  @override
  late final _Translations$common$es common = _Translations$common$es._(_root);
  @override
  late final _Translations$diff$es diff = _Translations$diff$es._(_root);
  @override
  late final _Translations$filament$es filament = _Translations$filament$es._(
    _root,
  );
  @override
  late final _Translations$history$es history = _Translations$history$es._(
    _root,
  );
  @override
  late final _Translations$historySurgery$es historySurgery =
      _Translations$historySurgery$es._(_root);
  @override
  late final _Translations$onboarding$es onboarding =
      _Translations$onboarding$es._(_root);
  @override
  late final _Translations$orrery$es orrery = _Translations$orrery$es._(_root);
  @override
  late final _Translations$palette$es palette = _Translations$palette$es._(
    _root,
  );
  @override
  late final _Translations$releaseNotes$es releaseNotes =
      _Translations$releaseNotes$es._(_root);
  @override
  late final _Translations$repoSummary$es repoSummary =
      _Translations$repoSummary$es._(_root);
  @override
  late final _Translations$review$es review = _Translations$review$es._(_root);
  @override
  late final _Translations$settings$es settings = _Translations$settings$es._(
    _root,
  );
  @override
  late final _Translations$sync$es sync = _Translations$sync$es._(_root);
  @override
  late final _Translations$xray$es xray = _Translations$xray$es._(_root);
}

// Path: app
class _Translations$app$es extends Translations$app$en {
  _Translations$app$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get panelSettings => 'Ajustes';
  @override
  String get panelReleaseNotes => 'Notas de la versión';
  @override
  String get panelFilamentFindings => 'Hallazgos de Filament';
  @override
  String get filamentFindingsUpper => 'HALLAZGOS DE FILAMENT';
  @override
  late final _Translations$app$cheatsheet$es cheatsheet =
      _Translations$app$cheatsheet$es._(_root);
  @override
  String get commandPaletteTooltip => 'Paleta de comandos   /';
  @override
  String get newDeskFallback => 'Desk nuevo';
  @override
  String get deskFallback => 'Desk';
  @override
  String get currentDeskFallback => 'actual';
  @override
  String get noRepositoryOpen => 'No hay ningún repositorio abierto';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'No se pudo abrir como Desk: ${error}';
  @override
  String couldNotDetectForge({required Object error}) =>
      'No se pudo detectar la forja: ${error}';
  @override
  String get cannotFetchPrNoForge =>
      'No se puede traer el PR: no se detectó una forja para este repo.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      '¿Sobrescribir ${ref} con lo más reciente del remoto?';
  @override
  String get overwrite => 'Sobrescribir';
  @override
  String couldntFetchPr({required Object error}) =>
      'No se pudo traer el PR: ${error}';
  @override
  String get promoteDeskToPr => 'Promover el Desk a PR';
  @override
  String get applyToMain => 'Aplicar a main';
  @override
  String updateDeskFrom({required Object target, required Object source}) =>
      'Actualizar ${target} desde ${source}';
  @override
  String bringChangesFromHere({required Object source}) =>
      'Traer los cambios de ${source} aquí';
  @override
  String get editLocalPr => 'Editar PR local';
  @override
  String get discardLocalPr => 'Descartar PR local';
  @override
  String get closeDesk => 'Cerrar Desk';
  @override
  String couldntPromote({required Object error}) =>
      'No se pudo promover: ${error}';
  @override
  String get commitOrShelveBeforeApplying =>
      'Haz commit o guarda en el estante los cambios del Desk antes de aplicar.';
  @override
  String get couldNotResolveMainWorktree =>
      'No se pudo resolver la ruta del árbol de trabajo principal.';
  @override
  String couldntPromoteDesk({required Object error}) =>
      'No se pudo promover el Desk: ${error}';
  @override
  String get couldntDetermineBaseBranch =>
      'No se pudo determinar la rama base de este Desk.';
  @override
  String prBaseHeadSame({required Object branch}) =>
      'La base y la punta del PR son la misma rama (${branch}) — no hay nada que aplicar.';
  @override
  String appliedBranchToBase({required Object branch, required Object base}) =>
      'Se aplicó ${branch} a ${base}';
  @override
  String updatedDeskToDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
    n,
    one: 'Se actualizó ${target} a ${source} (${n} commit).',
    other: 'Se actualizó ${target} a ${source} (${n} commits).',
  );
  @override
  String get fastForwardFailedFallback =>
      'El fast-forward no pudo aterrizar limpio — mostrando una vista previa de parche en su lugar.';
  @override
  String deskAheadOfDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
    n,
    one: '${target} está ${n} commit por delante de ${source}.',
    other: '${target} está ${n} commits por delante de ${source}.',
  );
  @override
  String deskUpToDate({required Object target, required Object source}) =>
      '${target} ya está al día con ${source}.';
  @override
  String uncommittedPreviewNotice({required Object target}) =>
      'Cambios sin commit en ${target} — previsualizando como parche en su lugar.';
  @override
  String updateDeskFromLower({
    required Object target,
    required Object source,
  }) => 'actualizar ${target} desde ${source}';
  @override
  String noUpdatesToBringFrom({required Object source}) =>
      'No hay actualizaciones que traer de ${source}.';
  @override
  String get updatePrepFailed => 'Falló la preparación de la actualización';
  @override
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => 'traer los cambios de ${source} a ${target}';
  @override
  String noPatchableChanges({required Object source, required Object target}) =>
      'No hay cambios aplicables como parche que traer de ${source} a ${target}.';
  @override
  String get patchPrepFailed => 'Falló la preparación del parche';
  @override
  String failureWithError({required Object label, required Object error}) =>
      '${label}: ${error}';
  @override
  String get titleHint => 'título';
  @override
  String get bodyHint => 'cuerpo';
  @override
  String get bodyOptionalHint => 'cuerpo (opcional)';
  @override
  String get draftLower => 'borrador';
  @override
  String get cancelLower => 'cancelar';
  @override
  String get saveLower => 'guardar';
  @override
  String couldntSave({required Object error}) => 'No se pudo guardar: ${error}';
  @override
  String get stashedNoOtherDesk =>
      'Cambios guardados en stash — no hay otro Desk donde aplicarlos. Usa git stash pop para recuperarlos.';
  @override
  String get suggestedSource => 'fuente sugerida';
  @override
  String tooltipModifiedCount({required Object n}) => '${n} modificados';
  @override
  String tooltipAheadCount({required Object n}) => '${n} por delante';
  @override
  String tooltipBehindCount({required Object n}) => '${n} por detrás';
  @override
  String get focusedEdits => 'ediciones enfocadas';
  @override
  String get editsSpreadAcrossSubsystems =>
      'ediciones repartidas por subsistemas';
  @override
  String get editsTouchingManySubsystems =>
      'ediciones que tocan muchos subsistemas';
  @override
  String get focusedBranch => 'rama enfocada';
  @override
  String get branchSpansMultipleSubsystems =>
      'la rama abarca varios subsistemas';
  @override
  String get structurallyDivergentFromMainline =>
      'estructuralmente divergente de la línea principal';
  @override
  String get localPr => 'PR local';
  @override
  String lastTouched({required Object time}) => 'tocado por última vez ${time}';
  @override
  String driftGroupCount({required Object n, required Object dir}) =>
      '${n} en ${dir}';
  @override
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';
  @override
  String get uncommittedChanges => 'Cambios sin commit';
  @override
  String get closeDeskQuestion => '¿Cerrar el Desk?';
  @override
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} archivo sin commit.',
        other: '${n} archivos sin commit.',
      );
  @override
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} commit por delante de main.',
        other: '${n} commits por delante de main.',
      );
  @override
  String get willRemoveWorktreeDirectory =>
      'Esto eliminará el directorio del árbol de trabajo.';
  @override
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} archivo modificado',
        other: '${n} archivos modificados',
      );
  @override
  String get shelveHere => 'Guardar en el estante aquí';
  @override
  String get discardAndClose => 'Descartar y cerrar';
  @override
  String get noRepository => 'sin repositorio';
  @override
  String get issuePromotedToRemote => 'Issue promovida al remoto.';
  @override
  String get pushedToRemote => 'Se hizo push al remoto.';
  @override
  String get pulledFromRemote => 'Se hizo pull desde el remoto.';
  @override
  String get remoteIssueNotFound => 'issue remota no encontrada';
  @override
  String importedIssueLocally({required Object id}) =>
      'Se importó #${id} localmente.';
  @override
  String get issueAbandoned => 'Issue abandonada.';
  @override
  String get abandonIssue => 'Abandonar issue';
  @override
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      '¿Eliminar permanentemente la issue local #${id}? Esto borra su ref y no se puede deshacer.';
  @override
  String get abandon => 'Abandonar';
  @override
  String publishedBranch({required Object branch}) => 'Se publicó ${branch}.';
  @override
  String get publishingEllipsis => 'Publicando…';
  @override
  String get publish => 'Publicar';
  @override
  String get noRemoteConfigured =>
      'No hay remoto configurado para este repositorio.';
  @override
  String get jumpToDesk => 'Saltar al Desk';
  @override
  String get arrowOpen => '→ abrir';
  @override
  String get openOnANewDesk => 'Abrir en un Desk nuevo';
  @override
  String get plusDesk => '+ Desk';
  @override
  String get plusSpace => '+ ';
  @override
  String get newBranchNameHint => 'nombre-de-rama-nueva';
  @override
  String get escLower => 'esc';
  @override
  String get plusNewDesk => '+ Desk nuevo';
  @override
  String get fromHeadEllipsis => 'desde HEAD...';
  @override
  String get viewAllBranches => 'Ver todas las ramas';
  @override
  String get issuesLower => 'issues';
  @override
  String get newIssueLower => 'nueva issue';
  @override
  String get noneLinked => 'ninguna vinculada';
  @override
  String get noOpenIssues => 'sin issues abiertas';
  @override
  String get createAndPushLower => 'crear + push';
  @override
  String get createLower => 'crear';
  @override
  String get remoteLower => 'remoto';
  @override
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';
  @override
  String get promoteToRemote => 'Promover al remoto';
  @override
  String get pushToRemote => 'Hacer push al remoto';
  @override
  String get pullFromRemote => 'Hacer pull desde el remoto';
  @override
  String get importLabel => 'Importar';
  @override
  String get failedToCreateRepository => 'No se pudo crear el repositorio.';
  @override
  String get openRepositoryLower => 'abrir repositorio';
  @override
  String get newRepositoryLower => 'repositorio nuevo';
  @override
  String get back => 'Atrás';
  @override
  String get openRepositoryDialogTitle => 'Abrir repositorio';
  @override
  String get createRepositoryDialogTitle => 'Crear repositorio';
  @override
  String get cloneTargetDialogTitle => 'Destino del clon';
  @override
  String get cloneToDialogTitle => 'Clonar en';
  @override
  String get exportToDialogTitle => 'Exportar a';
  @override
  String get createFromTemplateInDialogTitle => 'Crear desde plantilla en';
  @override
  String get notAGitRepoInitConfirm =>
      'No es un repositorio git. ¿Inicializar uno aquí?';
  @override
  String get repositoryUrlRequired => 'Se requiere la URL del repositorio.';
  @override
  String get failedToCloneRepository => 'No se pudo clonar el repositorio.';
  @override
  String cloningEllipsis({required Object name}) => 'Clonando ${name}...';
  @override
  String get cloneCancelled => 'Clon cancelado.';
  @override
  String get noProjectsYet => 'Aún no hay proyectos';
  @override
  String get dissolveGroup => 'Disolver grupo';
  @override
  String get projectsHeader => 'Proyectos';
  @override
  String get cloneLabel => 'Clonar';
  @override
  String get createLabel => 'Crear';
  @override
  String get openLabel => 'Abrir';
  @override
  String get repositoryUrlPlaceholder => 'URL del repositorio';
  @override
  String get projectNameOrFullPathPlaceholder =>
      'nombre-de-proyecto o ruta completa';
  @override
  String get pathToProjectPlaceholder => '/ruta/al/proyecto';
  @override
  String get cloneToFolderPathPlaceholder =>
      'Ruta de la carpeta de destino del clon';
  @override
  String get switchToCreateRepo => 'Cambiar a Crear repo';
  @override
  String get explorer => 'Explorador';
  @override
  String get terminal => 'Terminal';
  @override
  String get cloneUrl => 'Clonar URL';
  @override
  String get copyPath => 'Copiar ruta';
  @override
  String get export => 'Exportar';
  @override
  String get readme => 'README';
  @override
  String get duplicate => 'Duplicar';
  @override
  String get template => 'Plantilla';
  @override
  String get forgetThisProject => 'Olvidar este proyecto';
  @override
  String get aiKindCommitMessage => 'mensaje de commit';
  @override
  String get aiKindReview => 'revisión';
  @override
  String get aiKindMuse => 'muse';
  @override
  String get aiKindPresent => 'presentar';
  @override
  String get aiKindDebug => 'depurar';
  @override
  String aiStatusRunning({required Object kind}) => '${kind} en curso';
  @override
  String aiStatusFailedUnread({required Object kind}) =>
      '${kind} falló (sin leer)';
  @override
  String aiStatusReadyUnread({required Object kind}) =>
      '${kind} listo (sin leer)';
  @override
  String get filesLower => 'archivos';
  @override
  String get commitsLower => 'commits';
  @override
  String get undoLabel => 'Deshacer';
  @override
  String get goLabel => 'ir';
  @override
  String countdownSeconds({required Object n}) => '${n}s';
  @override
  String get collapseGlyph => '▲ contraer';
  @override
  String moreLinesGlyph({required Object n}) => '▼ ${n} líneas más';
}

// Path: backend
class _Translations$backend$es extends Translations$backend$en {
  _Translations$backend$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$backend$ops$es ops = _Translations$backend$ops$es._(
    _root,
  );
  @override
  late final _Translations$backend$mergeOutcome$es mergeOutcome =
      _Translations$backend$mergeOutcome$es._(_root);
}

// Path: branches
class _Translations$branches$es extends Translations$branches$en {
  _Translations$branches$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get runningAiReview => 'Ejecutando revisión con IA…';
  @override
  String prNumberLabel({required Object number}) => 'PR #${number}';
  @override
  String get findings => 'HALLAZGOS';
  @override
  String get observations => 'OBSERVACIONES';
  @override
  String get renameEllipsis => 'Renombrar…';
  @override
  String get publish => 'Publicar';
  @override
  String publishFailed({required Object error}) =>
      'Falló la publicación: ${error}';
  @override
  String couldntOpenDesk({required Object error}) =>
      'No se pudo abrir el Desk: ${error}';
  @override
  String syncFailed({required Object error}) =>
      'Falló la sincronización: ${error}';
  @override
  String get renameBranchTitle => 'Renombrar rama';
  @override
  String get newNameHint => 'nombre nuevo';
  @override
  String get rename => 'Renombrar';
  @override
  String invalidBranchName({required Object name}) =>
      '\'${name}\' no es un nombre de rama válido.';
  @override
  String renameFailed({required Object error}) =>
      'Falló el renombrado: ${error}';
  @override
  String deletingBranch({required Object name}) => 'Eliminando ${name}';
  @override
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '\'${name}\' está abierta en el Desk \'${desk}\'.';
  @override
  String get openDesk => 'Abrir Desk';
  @override
  String openInDeskShort({required Object desk}) =>
      'abrir en el Desk \'${desk}\'';
  @override
  String get couldNotPinBranch =>
      'no se pudo fijar la punta de la rama; se omitió la eliminación';
  @override
  String get couldNotPinTag =>
      'no se pudo fijar la etiqueta; se omitió la eliminación';
  @override
  String deletingTag({required Object name}) => 'Eliminando etiqueta ${name}';
  @override
  String get applyToActiveChanges => 'Aplicar a los cambios activos…';
  @override
  String get couldNotLoadPrDiff => 'No se pudo cargar el diff del PR.';
  @override
  String prSourceLabel({required Object number, required Object title}) =>
      'PR #${number}: ${title}';
  @override
  String mergeIntoDesk({required Object branch}) => 'Merge en ${branch}…';
  @override
  String get checkoutThisPr => 'Checkout de este PR';
  @override
  String get mergeIntoNewDesk => 'Merge en un Desk nuevo…';
  @override
  String get pushToForge => 'Hacer push a la forja';
  @override
  String get linkToIssue => 'Vincular a issue…';
  @override
  String get gitPatch => '↓ parche de git';
  @override
  String get copyBranchName => 'Copiar nombre de la rama';
  @override
  String copiedRef({required Object ref}) => 'Copiado "${ref}"';
  @override
  String get reviewPr => 'Revisar PR';
  @override
  String get openInBrowser => 'Abrir en el navegador';
  @override
  String get markAsRead => 'Marcar como leído';
  @override
  String get markAsUnread => 'Marcar como no leído';
  @override
  String get replaceLocalCommitsTitle => '¿Reemplazar los commits locales?';
  @override
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref} tiene commits locales que no están en la punta del PR remoto. Actualizarla los reemplazará con lo más reciente del remoto.';
  @override
  String get update => 'Actualizar';
  @override
  String couldntFetchPr({required Object error}) =>
      'No se pudo traer el PR: ${error}';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'No se pudo abrir como Desk: ${error}';
  @override
  String couldntOpenInBrowser({required Object error}) =>
      'No se pudo abrir en el navegador: ${error}';
  @override
  String get noIssuesYetLocal =>
      'Aún no hay issues. Abre una en el upstream, o usa "+ nueva issue local" en la lente de issues.';
  @override
  String get remotePrsLinkLocalOnly =>
      'Los PRs remotos solo pueden vincularse a issues locales. Crea una con "+ nueva issue local".';
  @override
  String linkPrToIssues({required Object number}) =>
      'Vincular el PR #${number} a issue(s)';
  @override
  String get noPrsYetLocal =>
      'Aún no hay PRs. Abre uno en el upstream, o promueve un Desk a PR.';
  @override
  String get remoteIssuesLinkLocalOnly =>
      'Las issues remotas solo pueden vincularse a PRs locales. Promueve primero un Desk a PR.';
  @override
  String linkIssueToPrs({required Object number}) =>
      'Vincular la issue #${number} a PR(s)';
  @override
  String couldntToggleLink({required Object error}) =>
      'No se pudo alternar el vínculo: ${error}';
  @override
  String get openPatchDialogTitle => 'Abrir parche (.patch / .diff)';
  @override
  String get clipboardNoText => 'El portapapeles no tiene texto.';
  @override
  String get clipboardPatchLabel => 'portapapeles.patch';
  @override
  String failedToOpenPatch({required Object error}) =>
      'No se pudo abrir el parche: ${error}';
  @override
  String get patchEmptyOrUnparseable =>
      'El parche está vacío o no se puede parsear.';
  @override
  String get prPushedToForge => 'PR enviado a la forja.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      '¿Sobrescribir ${ref} con lo más reciente del remoto?';
  @override
  String get overwrite => 'Sobrescribir';
  @override
  String get loadingBranchesTitle => 'Cargando ramas';
  @override
  String get loadingBranchesMessage => 'Leyendo las ramas y etiquetas locales.';
  @override
  String get branchesUnavailableTitle => 'Ramas no disponibles';
  @override
  String get filterPullRequestsHint => 'filtrar pull requests…';
  @override
  String get filterIssuesHint => 'filtrar issues…';
  @override
  String get branchNameHint => 'nombre de la rama';
  @override
  String get tagsNewestFirst => 'etiquetas, más recientes primero';
  @override
  String get tagsOldestFirst => 'etiquetas, más antiguas primero';
  @override
  String get flipSortDirection => 'invertir el sentido del orden';
  @override
  String get readingPullRequests => 'Leyendo pull requests…';
  @override
  String get noOpenPullRequests => 'Sin pull requests abiertos';
  @override
  String get noPullRequestsHint =>
      'Abre uno desde una rama, o promueve un Desk.';
  @override
  String get noPrsMatchFilters => 'Ningún PR coincide con estos filtros';
  @override
  String get toggleFiltersRowAbove =>
      'Desactiva los filtros en la fila de arriba.';
  @override
  String get issuesNewestFirst => 'issues, más recientes primero';
  @override
  String get issuesOldestFirst => 'issues, más antiguas primero';
  @override
  String get issuesHeading => 'ISSUES';
  @override
  String get readingIssuesLower => 'leyendo issues…';
  @override
  String get noOpenIssues => 'Sin issues abiertas';
  @override
  String get noIssuesHint =>
      '+ nueva para llevar el seguimiento de tareas y bugs.';
  @override
  String get nothingMatches => 'Nada coincide';
  @override
  String get toggleFiltersAbove => 'Desactiva los filtros arriba.';
  @override
  String get bucketFresh => 'FRESCO';
  @override
  String get bucketThisWeek => 'ESTA SEMANA';
  @override
  String get bucketStalled => 'ESTANCADO';
  @override
  String get bucketOlder => 'MÁS ANTIGUO';
  @override
  String get couldNotResolveMainWorktree =>
      'No se pudo resolver la ruta del árbol de trabajo principal.';
  @override
  String couldntSubmitReview({required Object error}) =>
      'No se pudo enviar la revisión: ${error}';
  @override
  String get reviewAiNotAvailable =>
      'La IA de revisión aún no está disponible.';
  @override
  String get noReviewModelConfigured =>
      'No hay ningún modelo de revisión configurado.';
  @override
  String get deskFallback => 'Desk';
  @override
  String deskUncommittedChanges({
    required num n,
    required Object branch,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
    n,
    one: '${branch} tiene ${n} cambio sin commit — haz commit o stash primero.',
    other:
        '${branch} tiene ${n} cambios sin commit — haz commit o stash primero.',
  );
  @override
  String get targetDeskNoBranch => 'El Desk de destino no tiene rama.';
  @override
  String mergePrIntoDesk({required Object number, required Object branch}) =>
      'Merge del PR #${number} en ${branch}';
  @override
  String get conflictCheckUnavailableVersion =>
      'Verificación de conflictos no disponible — se requiere git 2.38+';
  @override
  String get conflictCheckUnavailable =>
      'Verificación de conflictos no disponible';
  @override
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'HABRÁ CONFLICTO · ${n} archivo',
        other: 'HABRÁ CONFLICTO · ${n} archivos',
      );
  @override
  String plusMore({required Object n}) => '+${n} más';
  @override
  String get rebase => 'Rebase';
  @override
  String get squash => 'Squash';
  @override
  String get mergeCommit => 'Commit de merge';
  @override
  String noDeskForBranch({required Object branch}) =>
      'No se encontró Desk para la rama ${branch}';
  @override
  String get mergeAnyway => 'Merge de todos modos';
  @override
  String get readingIssues => 'Leyendo issues…';
  @override
  String get openUpstreamOrLocal =>
      'Abre una en el upstream, o abre una local.';
  @override
  String get noIssuesMatchFilters => 'Ninguna issue coincide con estos filtros';
  @override
  String couldntCreateIssue({required Object error}) =>
      'No se pudo crear la issue: ${error}';
  @override
  String get promoteToRemote => 'Promover al remoto';
  @override
  String get pushToRemote => 'Hacer push al remoto';
  @override
  String get pullFromRemote => 'Hacer pull desde el remoto';
  @override
  String get import => 'Importar';
  @override
  String get linkToPr => 'Vincular a PR…';
  @override
  String get abandon => 'Abandonar';
  @override
  String get issuePromotedToRemote => 'Issue promovida al remoto.';
  @override
  String get issuePushedToRemote => 'Se hizo push al remoto.';
  @override
  String get issuePulledFromRemote => 'Se hizo pull desde el remoto.';
  @override
  String issueImportedLocally({required Object number}) =>
      'Se importó #${number} localmente.';
  @override
  String get abandonIssueTitle => 'Abandonar issue';
  @override
  String abandonIssueMessage({required Object id}) =>
      '¿Eliminar permanentemente la issue local #${id}? Esto borra su ref y no se puede deshacer.';
  @override
  String couldntAbandon({required Object error}) =>
      'No se pudo abandonar: ${error}';
  @override
  String couldntPostComment({required Object error}) =>
      'No se pudo publicar el comentario: ${error}';
  @override
  String couldntCloseIssue({required Object error}) =>
      'No se pudo cerrar la issue: ${error}';
  @override
  String couldntAddLabel({required Object error}) =>
      'No se pudo añadir la etiqueta: ${error}';
  @override
  String get lensBranches => 'RAMAS';
  @override
  String get lensPrs => 'PRs';
  @override
  String get patchUp => '↑ parche';
  @override
  String get syncRibbon => '⇅ sincronizar';
  @override
  String get kbHeading => 'TECLADO';
  @override
  String get kbNavigateRows => 'navegar filas';
  @override
  String get kbExpandCollapse => 'expandir / contraer la fila enfocada';
  @override
  String get kbCheckoutPr => 'checkout local del PR enfocado';
  @override
  String get kbApproveReview => 'aprobar · revisar';
  @override
  String get kbRequestChanges => 'solicitar cambios';
  @override
  String get kbFocusSearch => 'enfocar la búsqueda';
  @override
  String get kbSwitchLens => 'cambiar de lente (ramas · prs)';
  @override
  String get kbToggleOverlay => 'alternar esta superposición';
  @override
  String get kbPressToDismiss => 'pulsa en cualquier parte para descartar';
  @override
  String get overrideScarTooltip =>
      'fusionado con checks fallidos o sin una revisión que apruebe — investiga primero bajo presión';
  @override
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} archivo se solapa con tu trabajo sin commit',
        other: '${n} archivos se solapan con tu trabajo sin commit',
      );
  @override
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '#${pr}  (${n} archivo)',
        other: '#${pr}  (${n} archivos)',
      );
  @override
  String get prStateDraft => 'BORRADOR';
  @override
  String get localBadge => 'LOCAL';
  @override
  String get myReviewPending => 'tu revisión pendiente';
  @override
  String get myReviewApproved => 'tú ✓';
  @override
  String get myReviewChangesRequested => 'tú ✗ solicitaste cambios';
  @override
  String get myReviewCommented => 'comentaste';
  @override
  String get myReviewDefault => 'tú';
  @override
  String tailCommentsAuthor({required Object count}) =>
      '${count} comentarios · se muestra el último del autor';
  @override
  String get tailLastComment => 'último comentario';
  @override
  String tailLastReviewState({required Object state}) =>
      'última revisión · ${state}';
  @override
  String get tailLastReview => 'última revisión';
  @override
  String tailLastCheckState({required Object state}) =>
      'último check · ${state}';
  @override
  String get tailLastCommit => 'último commit';
  @override
  String get tailLastActivity => 'última actividad';
  @override
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'cierra ${n} issue — clic para saltar',
        other: 'cierra ${n} issues — clic para saltar',
      );
  @override
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'abordada por ${n} PR — clic para saltar',
        other: 'abordada por ${n} PRs — clic para saltar',
      );
  @override
  String get checksLabel => 'checks';
  @override
  String get reviewersLabel => 'revisores';
  @override
  String get conflictsLabel => 'conflictos';
  @override
  String exportFailed({required Object error}) =>
      'Falló la exportación: ${error}';
  @override
  String get readingFiles => 'leyendo archivos…';
  @override
  String get noDetailAvailable => 'sin detalle disponible';
  @override
  String get noFilesReported => 'no se reportaron archivos';
  @override
  String get readingGitHistory => 'leyendo el historial de git…';
  @override
  String get knowsThisCode => 'conoce este código';
  @override
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} commit sobre estos archivos en el último año',
        other: '${n} commits sobre estos archivos en el último año',
      );
  @override
  String get willFight => 'SE PELEARÁN';
  @override
  String orbitalPartnerCos({required Object cos}) =>
      'compañero orbital — cos ${cos}';
  @override
  String get orbitLabel => 'órbita';
  @override
  String get touchesYourLocalWork => 'TOCA TU TRABAJO LOCAL';
  @override
  String get mergingWillConflict =>
      'el merge probablemente entrará en conflicto con tus cambios sin commit';
  @override
  String get closesHeading => 'CIERRA';
  @override
  String get filesHeading => 'ARCHIVOS';
  @override
  String get orientAligned => 'alineado';
  @override
  String get orientAdjacent => 'adyacente';
  @override
  String get orientOrthogonal => 'ortogonal';
  @override
  String shapeField({required Object v}) => 'campo ${v}';
  @override
  String shapeSource({required Object v}) => 'fuente ${v}';
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
  String shapeStress({required Object v}) => 'estrés ${v}';
  @override
  String shapeWit({required Object v}) => 'wit ${v}';
  @override
  String resonanceReadout({required Object v}) => 'resonancia ${v}';
  @override
  String ghostFileTooltip({required Object path}) =>
      'suele moverse con los archivos de este PR\n(${path})';
  @override
  String get prStateDraftLower => 'borrador';
  @override
  String get keystoneTooltip => 'clave — archivo puente de todo el repo';
  @override
  String get reviewNoteHint => 'deja una nota (opcional)…';
  @override
  String get reviewComment => 'comentar';
  @override
  String get reviewRequestChanges => 'solicitar cambios';
  @override
  String get reviewApprove => '✓ aprobar';
  @override
  String get actionPatchDown => '↓ parche';
  @override
  String get actionPrReview => '✦ revisar pr';
  @override
  String get actionOpenAsDesk => '⊞ abrir como Desk';
  @override
  String get actionCheckout => '[c] checkout';
  @override
  String get actionMerge => '[m] merge ▾';
  @override
  String get mergeMenuMergeCommit => 'commit de merge';
  @override
  String get mergeMenuSquash => 'squash y merge';
  @override
  String get mergeMenuRebase => 'rebase y merge';
  @override
  String get deleteBranchAfter => 'eliminar rama después';
  @override
  String checkDurationSec({required Object n}) => '${n}s';
  @override
  String checkDurationMin({required Object m, required Object s}) =>
      '${m}m ${s}s';
  @override
  String assignedTo({required Object names}) => 'asignada: ${names}';
  @override
  String issueConvLine({required Object n, required Object time}) =>
      '${n} conv · ${time}';
  @override
  String get readingThread => 'leyendo el hilo…';
  @override
  String get addressedByHeading => 'ABORDADA POR';
  @override
  String get descriptionHeading => 'DESCRIPCIÓN';
  @override
  String get threadHeading => 'HILO';
  @override
  String get replyHint => 'responder…';
  @override
  String get assignMe => 'asignarme';
  @override
  String get closeLower => 'cerrar';
  @override
  String get postReply => '↩ publicar';
  @override
  String get remoteProviderUnavailable => 'Proveedor remoto no disponible';
  @override
  String get noRecognisedRemoteHost =>
      'No se reconoce ningún host remoto para este repo.';
  @override
  String get corpseGone => 'ida';
  @override
  String get corpseAbsorbed => 'absorbida';
  @override
  String get corpseSquashed => 'aplastada';
  @override
  String absorbedDeliveredIn({required Object hash}) => 'entregada en ${hash}';
  @override
  String get absorbedNoChanges => 'el merge no añade cambios';
  @override
  String get corpseTagUpstreamGone => 'upstream ido';
  @override
  String corpseTagAbsorbed({required Object receipt}) =>
      'absorbida, ${receipt}';
  @override
  String get corpseTagSquashed => 'aplastada y fusionada';
  @override
  String semanticsCurrentBranch({required Object name}) =>
      '${name}, rama actual';
  @override
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}, siguiendo ${upstream}';
  @override
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}, ${tag}';
  @override
  String semanticsWorktreeOpen({required Object label}) =>
      '${label}, árbol de trabajo abierto';
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
  String get crossLinkPrDraft => 'PR · borrador';
  @override
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} issue',
        other: '${n} issues',
      );
  @override
  String get headBadge => 'HEAD';
  @override
  String trackingLine({required Object upstream}) => '→ siguiendo: ${upstream}';
  @override
  String get checkoutButton => 'Checkout';
  @override
  String get createBranch => 'Crear rama';
  @override
  String get newBranchName => 'Nombre de la rama nueva';
  @override
  String newBranchNameError({required Object error}) =>
      'Nombre de la rama nueva — ${error}';
  @override
  String get forceDelete => '¿Forzar?';
  @override
  String get annotated => 'anotada';
  @override
  String get applyCheckFailed => 'falló apply --check';
  @override
  String get openPatchFrom => 'ABRIR PARCHE DESDE';
  @override
  String get patchFromFile => 'desde archivo…';
  @override
  String get patchFromFileHint => '.patch / .diff';
  @override
  String get patchFromClipboard => 'desde el portapapeles';
  @override
  String get patchFromClipboardHint => 'pegar texto';
  @override
  String get patchPreviewHeading => 'VISTA PREVIA DEL PARCHE';
  @override
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';
  @override
  String get stagedDone => 'en stage.';
  @override
  String get appliedDone => 'aplicado.';
  @override
  String get opening => 'abriendo…';
  @override
  String get mergeEditor => '⇋ editor de merge';
  @override
  String get staging => 'poniendo en stage…';
  @override
  String get applying => 'aplicando…';
  @override
  String get stage => 'stage';
  @override
  String get apply => 'aplicar';
  @override
  String get refineHint =>
      'refinar… (p. ej. "quita también los cambios del logger")';
  @override
  String get reverseArmedTooltip =>
      'armado — el próximo apply REVERTIRÁ el parche (-R)';
  @override
  String get reverseDisarmedTooltip =>
      'armar reverso (-R) — deshacer en vez de aplicar';
  @override
  String get reverseArmedLabel => '⟲ reverso ✓';
  @override
  String get reverseLabel => '⟲ reverso';
  @override
  String get untouchedHeading => '⚠ SIN TOCAR';
  @override
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${count} de ${n} archivo no está en el parche',
        other: '${count} de ${n} archivos no están en el parche',
      );
  @override
  String get staysConflicted =>
      'estos archivos seguirán en conflicto — aplicar no los pondrá en stage';
  @override
  String get orWith => 'O CON';
  @override
  String get noAiModelConfigured => 'no hay modelo de IA configurado';
  @override
  String applyWithPatchFrom({required Object label}) =>
      'aplicar con parche de ${label}';
  @override
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => 'aplicar con parche de ${label}  ·  ${model}';
  @override
  String get patching => 'parcheando…';
  @override
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  aplicar con parche de ${label}';
  @override
  String get orWithAnotherModel => 'o con otro modelo';
  @override
  String get applyCheckPassed =>
      'git apply --check pasó — el parche se aplicará limpio';
  @override
  String get gitApplyCheckFailed => 'falló git apply --check';
  @override
  String get appliesClean => 'se aplica limpio';
  @override
  String get willNotApply => 'no se aplicará';
  @override
  String get newLocalIssue => 'nueva issue local';
  @override
  String get filterHint => 'filtrar…';
  @override
  String get nothingToLink => 'Aún no hay nada que vincular.';
  @override
  String get nothingMatchesDot => 'Nada coincide.';
  @override
  String get relevantHeading => 'RELEVANTE';
  @override
  String get allHeading => 'TODO';
  @override
  String get doneLower => 'listo';
  @override
  String get candidateRemote => 'R';
  @override
  String get candidateLocal => 'L';
  @override
  String get newLocalIssueTitle => 'Nueva issue local';
  @override
  String get titleHint => 'título';
  @override
  String get bodyHint => 'cuerpo (markdown)';
  @override
  String get cancelLower => 'cancelar';
  @override
  String get createLower => 'crear';
  @override
  String get deleteFailed => 'falló la eliminación';
  @override
  String reviewFailed({required Object error}) => 'Falló la revisión: ${error}';
  @override
  String get resolutionFailed => 'falló la resolución';
  @override
  String get patchBlocksNoCover =>
      'el modelo devolvió bloques de parche que no cubrían los archivos que fallaban';
  @override
  String get applyFailed => 'falló la aplicación';
  @override
  String get emptyOrUnparseablePatch =>
      'el modelo devolvió un parche vacío o que no se puede parsear';
  @override
  String noModelConfiguredFor({required Object label}) =>
      'no hay modelo configurado para "${label}"';
  @override
  String get checksHeading => 'COMPROBACIONES';
  @override
  String get peopleHeading => 'PERSONAS';
  @override
  String get conversationHeading => 'CONVERSACIÓN';
}

// Path: changes
class _Translations$changes$es extends Translations$changes$en {
  _Translations$changes$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$usage$es usage =
      _Translations$changes$usage$es._(_root);
  @override
  late final _Translations$changes$tabs$es tabs =
      _Translations$changes$tabs$es._(_root);
  @override
  late final _Translations$changes$tabStrip$es tabStrip =
      _Translations$changes$tabStrip$es._(_root);
  @override
  late final _Translations$changes$select$es select =
      _Translations$changes$select$es._(_root);
  @override
  late final _Translations$changes$constellationToggle$es constellationToggle =
      _Translations$changes$constellationToggle$es._(_root);
  @override
  late final _Translations$changes$nudgeChip$es nudgeChip =
      _Translations$changes$nudgeChip$es._(_root);
  @override
  late final _Translations$changes$minimap$es minimap =
      _Translations$changes$minimap$es._(_root);
  @override
  late final _Translations$changes$tagInput$es tagInput =
      _Translations$changes$tagInput$es._(_root);
  @override
  late final _Translations$changes$composer$es composer =
      _Translations$changes$composer$es._(_root);
  @override
  late final _Translations$changes$commit$es commit =
      _Translations$changes$commit$es._(_root);
  @override
  late final _Translations$changes$rebase$es rebase =
      _Translations$changes$rebase$es._(_root);
  @override
  late final _Translations$changes$editor$es editor =
      _Translations$changes$editor$es._(_root);
  @override
  late final _Translations$changes$editorTitles$es editorTitles =
      _Translations$changes$editorTitles$es._(_root);
  @override
  late final _Translations$changes$askHint$es askHint =
      _Translations$changes$askHint$es._(_root);
  @override
  late final _Translations$changes$fileMenu$es fileMenu =
      _Translations$changes$fileMenu$es._(_root);
  @override
  late final _Translations$changes$multiFileMenu$es multiFileMenu =
      _Translations$changes$multiFileMenu$es._(_root);
  @override
  late final _Translations$changes$ignoreMenu$es ignoreMenu =
      _Translations$changes$ignoreMenu$es._(_root);
  @override
  late final _Translations$changes$discard$es discard =
      _Translations$changes$discard$es._(_root);
  @override
  late final _Translations$changes$snack$es snack =
      _Translations$changes$snack$es._(_root);
  @override
  late final _Translations$changes$trace$es trace =
      _Translations$changes$trace$es._(_root);
  @override
  late final _Translations$changes$cleanTree$es cleanTree =
      _Translations$changes$cleanTree$es._(_root);
  @override
  late final _Translations$changes$guardrail$es guardrail =
      _Translations$changes$guardrail$es._(_root);
  @override
  late final _Translations$changes$dropHint$es dropHint =
      _Translations$changes$dropHint$es._(_root);
  @override
  late final _Translations$changes$diffEmpty$es diffEmpty =
      _Translations$changes$diffEmpty$es._(_root);
  @override
  late final _Translations$changes$shelvePill$es shelvePill =
      _Translations$changes$shelvePill$es._(_root);
  @override
  late final _Translations$changes$stashAction$es stashAction =
      _Translations$changes$stashAction$es._(_root);
  @override
  late final _Translations$changes$stashContents$es stashContents =
      _Translations$changes$stashContents$es._(_root);
  @override
  late final _Translations$changes$stashFile$es stashFile =
      _Translations$changes$stashFile$es._(_root);
  @override
  late final _Translations$changes$fileRow$es fileRow =
      _Translations$changes$fileRow$es._(_root);
  @override
  late final _Translations$changes$resolveStrip$es resolveStrip =
      _Translations$changes$resolveStrip$es._(_root);
  @override
  late final _Translations$changes$badge$es badge =
      _Translations$changes$badge$es._(_root);
  @override
  late final _Translations$changes$review$es review =
      _Translations$changes$review$es._(_root);
  @override
  late final _Translations$changes$commitBtn$es commitBtn =
      _Translations$changes$commitBtn$es._(_root);
  @override
  late final _Translations$changes$shapeBtn$es shapeBtn =
      _Translations$changes$shapeBtn$es._(_root);
  @override
  late final _Translations$changes$dejaVu$es dejaVu =
      _Translations$changes$dejaVu$es._(_root);
  @override
  late final _Translations$changes$identity$es identity =
      _Translations$changes$identity$es._(_root);
  @override
  late final _Translations$changes$staleScope$es staleScope =
      _Translations$changes$staleScope$es._(_root);
  @override
  late final _Translations$changes$finding$es finding =
      _Translations$changes$finding$es._(_root);
  @override
  late final _Translations$changes$muse$es muse =
      _Translations$changes$muse$es._(_root);
  @override
  late final _Translations$changes$debug$es debug =
      _Translations$changes$debug$es._(_root);
  @override
  late final _Translations$changes$includeSummary$es includeSummary =
      _Translations$changes$includeSummary$es._(_root);
  @override
  late final _Translations$changes$status$es status =
      _Translations$changes$status$es._(_root);
  @override
  late final _Translations$changes$stash$es stash =
      _Translations$changes$stash$es._(_root);
  @override
  late final _Translations$changes$tooltips$es tooltips =
      _Translations$changes$tooltips$es._(_root);
  @override
  late final _Translations$changes$mergeEditor$es mergeEditor =
      _Translations$changes$mergeEditor$es._(_root);
  @override
  late final _Translations$changes$conflictResolution$es conflictResolution =
      _Translations$changes$conflictResolution$es._(_root);
  @override
  late final _Translations$changes$mergeFlow$es mergeFlow =
      _Translations$changes$mergeFlow$es._(_root);
  @override
  late final _Translations$changes$constellation$es constellation =
      _Translations$changes$constellation$es._(_root);
}

// Path: common
class _Translations$common$es extends Translations$common$en {
  _Translations$common$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get listSeparator => ', ';
  @override
  String get cancel => 'Cancelar';
  @override
  String get close => 'Cerrar';
  @override
  String get save => 'Guardar';
  @override
  String get delete => 'Eliminar';
  @override
  String get retry => 'Reintentar';
  @override
  String get copy => 'Copiar';
  @override
  String get copied => 'Copiado';
  @override
  String get done => 'Listo';
  @override
  String get loading => 'Cargando…';
  @override
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} archivo',
        other: '${n} archivos',
      );
  @override
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} commit',
        other: '${n} commits',
      );
  @override
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} rama',
        other: '${n} ramas',
      );
  @override
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} commit local',
        other: '${n} commits locales',
      );
  @override
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} commit remoto',
        other: '${n} commits remotos',
      );
  @override
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} archivo en conflicto',
        other: '${n} archivos en conflicto',
      );
  @override
  late final _Translations$common$time$es time = _Translations$common$time$es._(
    _root,
  );
  @override
  late final _Translations$common$size$es size = _Translations$common$size$es._(
    _root,
  );
}

// Path: diff
class _Translations$diff$es extends Translations$diff$en {
  _Translations$diff$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$diff$status$es status =
      _Translations$diff$status$es._(_root);
  @override
  late final _Translations$diff$toolbar$es toolbar =
      _Translations$diff$toolbar$es._(_root);
  @override
  late final _Translations$diff$hunkDropdown$es hunkDropdown =
      _Translations$diff$hunkDropdown$es._(_root);
  @override
  String stagingFailed({required Object error}) =>
      'Falló el stage parcial: ${error}';
  @override
  late final _Translations$diff$trail$es trail = _Translations$diff$trail$es._(
    _root,
  );
  @override
  late final _Translations$diff$pinned$es pinned =
      _Translations$diff$pinned$es._(_root);
  @override
  late final _Translations$diff$hunkHint$es hunkHint =
      _Translations$diff$hunkHint$es._(_root);
  @override
  late final _Translations$diff$binary$es binary =
      _Translations$diff$binary$es._(_root);
  @override
  late final _Translations$diff$media$es media = _Translations$diff$media$es._(
    _root,
  );
}

// Path: filament
class _Translations$filament$es extends Translations$filament$en {
  _Translations$filament$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get noRepositoryOpen => 'No hay ningún repositorio abierto.';
  @override
  String scanningProgress({required Object scanned, required Object total}) =>
      'escaneando ${scanned} / ${total} archivos…';
  @override
  String findingsAcrossFiles({required Object count, required Object files}) =>
      '${count} hallazgos en ${files} archivos';
  @override
  String copiedFindings({required Object count}) =>
      'Se copiaron ${count} hallazgos';
  @override
  String get copy => 'COPIAR';
  @override
  String get noFindings => 'Sin hallazgos de flujo de ejecución.';
  @override
  late final _Translations$filament$severity$es severity =
      _Translations$filament$severity$es._(_root);
  @override
  late final _Translations$filament$kind$es kind =
      _Translations$filament$kind$es._(_root);
  @override
  String lineLabel({required Object line}) => 'L${line}';
  @override
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class _Translations$history$es extends Translations$history$en {
  _Translations$history$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$es commitLede =
      _Translations$history$commitLede$es._(_root);
  @override
  late final _Translations$history$seismograph$es seismograph =
      _Translations$history$seismograph$es._(_root);
  @override
  late final _Translations$history$worldline$es worldline =
      _Translations$history$worldline$es._(_root);
  @override
  late final _Translations$history$contextMenu$es contextMenu =
      _Translations$history$contextMenu$es._(_root);
  @override
  late final _Translations$history$cherryPick$es cherryPick =
      _Translations$history$cherryPick$es._(_root);
  @override
  late final _Translations$history$revert$es revert =
      _Translations$history$revert$es._(_root);
  @override
  late final _Translations$history$reflog$es reflog =
      _Translations$history$reflog$es._(_root);
  @override
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'Ese commit está más allá de ${n} commit cargado.',
        other: 'Ese commit está más allá de los ${n} commits cargados.',
      );
  @override
  String deleteTagFailed({required Object error}) =>
      'No se pudo eliminar la etiqueta: ${error}';
  @override
  String get loadingTitle => 'Cargando historial';
  @override
  String get loadingMessage => 'Leyendo los commits recientes.';
  @override
  String get unavailableTitle => 'Historial no disponible';
  @override
  String get toggleWorldline => 'Alternar línea de mundo';
  @override
  String get pageTitle => 'Historial';
  @override
  String get viewingLast => 'Viendo los últimos';
  @override
  String get commitsUnit => 'commits';
  @override
  String get noCommitSelectedTitle => 'Ningún commit seleccionado';
  @override
  String get noCommitSelectedMessage =>
      'Selecciona un commit para inspeccionar sus cambios.';
  @override
  String get loadingCommitTitle => 'Cargando commit';
  @override
  String get loadingCommitMessage => 'Leyendo los detalles del commit.';
  @override
  String get commitUnavailableTitle => 'Commit no disponible';
  @override
  String get couldNotLoadCommit => 'No se pudo cargar el commit.';
  @override
  String get reflogDividerLabel => 'reflog';
  @override
  String get loadReflog => 'Cargar reflog';
  @override
  String get createTag => 'Crear etiqueta';
  @override
  String get newTagName => 'Nombre de la nueva etiqueta';
  @override
  String newTagNameError({required Object error}) =>
      'Nombre de la nueva etiqueta — ${error}';
  @override
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} archivo · todos los cambios',
        other: '${n} archivos · todos los cambios',
      );
  @override
  String get allChangesLabel => 'todos los cambios';
  @override
  late final _Translations$history$rebase$es rebase =
      _Translations$history$rebase$es._(_root);
  @override
  late final _Translations$history$inFlight$es inFlight =
      _Translations$history$inFlight$es._(_root);
}

// Path: historySurgery
class _Translations$historySurgery$es extends Translations$historySurgery$en {
  _Translations$historySurgery$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$historySurgery$chrome$es chrome =
      _Translations$historySurgery$chrome$es._(_root);
  @override
  late final _Translations$historySurgery$select$es select =
      _Translations$historySurgery$select$es._(_root);
  @override
  late final _Translations$historySurgery$understand$es understand =
      _Translations$historySurgery$understand$es._(_root);
  @override
  late final _Translations$historySurgery$confirm$es confirm =
      _Translations$historySurgery$confirm$es._(_root);
  @override
  late final _Translations$historySurgery$execute$es execute =
      _Translations$historySurgery$execute$es._(_root);
  @override
  late final _Translations$historySurgery$verify$es verify =
      _Translations$historySurgery$verify$es._(_root);
  @override
  late final _Translations$historySurgery$forcePush$es forcePush =
      _Translations$historySurgery$forcePush$es._(_root);
}

// Path: onboarding
class _Translations$onboarding$es extends Translations$onboarding$en {
  _Translations$onboarding$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$nav$es nav =
      _Translations$onboarding$nav$es._(_root);
  @override
  late final _Translations$onboarding$naming$es naming =
      _Translations$onboarding$naming$es._(_root);
  @override
  late final _Translations$onboarding$theme$es theme =
      _Translations$onboarding$theme$es._(_root);
  @override
  late final _Translations$onboarding$repo$es repo =
      _Translations$onboarding$repo$es._(_root);
  @override
  late final _Translations$onboarding$preview$es preview =
      _Translations$onboarding$preview$es._(_root);
}

// Path: orrery
class _Translations$orrery$es extends Translations$orrery$en {
  _Translations$orrery$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$orrery$header$es header =
      _Translations$orrery$header$es._(_root);
  @override
  late final _Translations$orrery$status$es status =
      _Translations$orrery$status$es._(_root);
  @override
  late final _Translations$orrery$legend$es legend =
      _Translations$orrery$legend$es._(_root);
  @override
  late final _Translations$orrery$node$es node = _Translations$orrery$node$es._(
    _root,
  );
  @override
  late final _Translations$orrery$milestone$es milestone =
      _Translations$orrery$milestone$es._(_root);
  @override
  late final _Translations$orrery$structure$es structure =
      _Translations$orrery$structure$es._(_root);
  @override
  late final _Translations$orrery$rail$es rail = _Translations$orrery$rail$es._(
    _root,
  );
  @override
  late final _Translations$orrery$selection$es selection =
      _Translations$orrery$selection$es._(_root);
  @override
  late final _Translations$orrery$findingKind$es findingKind =
      _Translations$orrery$findingKind$es._(_root);
  @override
  late final _Translations$orrery$findings$es findings =
      _Translations$orrery$findings$es._(_root);
  @override
  late final _Translations$orrery$anchor$es anchor =
      _Translations$orrery$anchor$es._(_root);
  @override
  late final _Translations$orrery$compare$es compare =
      _Translations$orrery$compare$es._(_root);
}

// Path: palette
class _Translations$palette$es extends Translations$palette$en {
  _Translations$palette$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get active => 'activo';
  @override
  late final _Translations$palette$prefixes$es prefixes =
      _Translations$palette$prefixes$es._(_root);
  @override
  late final _Translations$palette$chips$es chips =
      _Translations$palette$chips$es._(_root);
  @override
  late final _Translations$palette$predictive$es predictive =
      _Translations$palette$predictive$es._(_root);
  @override
  late final _Translations$palette$topTouched$es topTouched =
      _Translations$palette$topTouched$es._(_root);
  @override
  late final _Translations$palette$coherence$es coherence =
      _Translations$palette$coherence$es._(_root);
  @override
  late final _Translations$palette$keystone$es keystone =
      _Translations$palette$keystone$es._(_root);
  @override
  late final _Translations$palette$repoSub$es repoSub =
      _Translations$palette$repoSub$es._(_root);
  @override
  late final _Translations$palette$desks$es desks =
      _Translations$palette$desks$es._(_root);
  @override
  late final _Translations$palette$actions$es actions =
      _Translations$palette$actions$es._(_root);
  @override
  late final _Translations$palette$tools$es tools =
      _Translations$palette$tools$es._(_root);
  @override
  late final _Translations$palette$gitCommands$es gitCommands =
      _Translations$palette$gitCommands$es._(_root);
  @override
  late final _Translations$palette$pr$es pr = _Translations$palette$pr$es._(
    _root,
  );
  @override
  late final _Translations$palette$ai$es ai = _Translations$palette$ai$es._(
    _root,
  );
  @override
  late final _Translations$palette$undo$es undo =
      _Translations$palette$undo$es._(_root);
  @override
  late final _Translations$palette$navigation$es navigation =
      _Translations$palette$navigation$es._(_root);
  @override
  late final _Translations$palette$settings$es settings =
      _Translations$palette$settings$es._(_root);
  @override
  late final _Translations$palette$info$es info =
      _Translations$palette$info$es._(_root);
  @override
  late final _Translations$palette$debug$es debug =
      _Translations$palette$debug$es._(_root);
  @override
  late final _Translations$palette$dev$es dev = _Translations$palette$dev$es._(
    _root,
  );
  @override
  late final _Translations$palette$historySurgery$es historySurgery =
      _Translations$palette$historySurgery$es._(_root);
  @override
  late final _Translations$palette$orrery$es orrery =
      _Translations$palette$orrery$es._(_root);
  @override
  late final _Translations$palette$command$es command =
      _Translations$palette$command$es._(_root);
  @override
  late final _Translations$palette$search$es search =
      _Translations$palette$search$es._(_root);
  @override
  late final _Translations$palette$wick$es wick =
      _Translations$palette$wick$es._(_root);
  @override
  late final _Translations$palette$gitCache$es gitCache =
      _Translations$palette$gitCache$es._(_root);
}

// Path: releaseNotes
class _Translations$releaseNotes$es extends Translations$releaseNotes$en {
  _Translations$releaseNotes$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get versionFallback => 'dev';
  @override
  late final _Translations$releaseNotes$about$es about =
      _Translations$releaseNotes$about$es._(_root);
  @override
  late final _Translations$releaseNotes$legal$es legal =
      _Translations$releaseNotes$legal$es._(_root);
}

// Path: repoSummary
class _Translations$repoSummary$es extends Translations$repoSummary$en {
  _Translations$repoSummary$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$repoSummary$backbone$es backbone =
      _Translations$repoSummary$backbone$es._(_root);
  @override
  late final _Translations$repoSummary$glance$es glance =
      _Translations$repoSummary$glance$es._(_root);
  @override
  late final _Translations$repoSummary$heading$es heading =
      _Translations$repoSummary$heading$es._(_root);
  @override
  String get historyStarvedCaveat =>
      'El ranking es limitado: el grafo de acoplamiento no tenía aristas (clon reciente o muy pocos commits). El orden de archivos refleja el tamaño, no la centralidad estructural.';
  @override
  late final _Translations$repoSummary$pitch$es pitch =
      _Translations$repoSummary$pitch$es._(_root);
  @override
  late final _Translations$repoSummary$region$es region =
      _Translations$repoSummary$region$es._(_root);
  @override
  late final _Translations$repoSummary$shape$es shape =
      _Translations$repoSummary$shape$es._(_root);
}

// Path: review
class _Translations$review$es extends Translations$review$en {
  _Translations$review$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get unresolved => 'sin resolver';
  @override
  String get done => 'listo';
  @override
  String get ack => 'anotado';
  @override
  String get reply => 'responder';
  @override
  String get pleaseFix => 'por favor, corrige';
  @override
  String get draft => 'borrador';
  @override
  String get engine => 'motor';
  @override
  String get moved => 'movido';
  @override
  String get yourTurn => 'tu turno';
  @override
  String get drafts => 'borradores';
  @override
  String get publish => 'publicar';
  @override
  String get discard => 'descartar';
  @override
  String get saveDraft => 'guardar borrador';
  @override
  String get cancel => 'cancelar';
  @override
  String get verdictApprove => 'aprobar';
  @override
  String get verdictRequestChanges => 'solicitar cambios';
  @override
  String get verdictComment => 'comentar';
  @override
  String get caughtUp => 'al día';
  @override
  String get sinceLastLook => 'desde tu última mirada';
  @override
  String get fullDiff => 'diff completo';
  @override
  String get commentHint => 'escribe un comentario';
  @override
  String outdatedLastSeen({required Object round}) =>
      'desactualizado · visto por última vez R${round}';
  @override
  String resolvedByFmt({required Object verb, required Object who}) =>
      '${verb} · ${who}';
  @override
  String waitingOnFmt({required Object who}) => 'esperando a ${who}';
  @override
  String roundChip({required Object round}) => 'R${round}';
  @override
  String filesSinceLastLook({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '1 archivo desde tu última mirada',
        other: '${n} archivos desde tu última mirada',
      );
  @override
  String unresolvedCountFmt({required Object n}) => '${n} sin resolver';
  @override
  String draftCountFmt({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '1 borrador',
        other: '${n} borradores',
      );
  @override
  String startReviewFailed({required Object error}) =>
      'No se pudo iniciar la revisión: ${error}';
  @override
  String get anchorUnavailable =>
      'Esa línea no se puede anclar — el archivo es demasiado grande o no está disponible.';
  @override
  String reviewActionFailed({required Object error}) =>
      'La acción de revisión falló: ${error}';
  @override
  String get lensTooLarge =>
      'Esa comparación es demasiado grande para mostrarla aquí — nos quedamos en el diff completo.';
  @override
  String get lensEmpty => 'Nada cambió entre estas instantáneas.';
  @override
  String get reopen => 'reabrir';
  @override
  String get notBlocking => 'no me esperen';
  @override
  String get markReviewed => 'revisado';
  @override
  String newComments({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '1 comentario nuevo',
        other: '${n} comentarios nuevos',
      );
  @override
  String get handTo => 'pasar a';
  @override
  String get heading => 'REVISIÓN';
  @override
  String get identityNeeded => 'Configura una identidad de git para revisar';
  @override
  String get fileUnreadable =>
      'Ese archivo no se puede leer aquí — es demasiado grande o no existe en esta ronda.';
}

// Path: settings
class _Translations$settings$es extends Translations$settings$en {
  _Translations$settings$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$language$es language =
      _Translations$settings$language$es._(_root);
  @override
  late final _Translations$settings$sectionLabels$es sectionLabels =
      _Translations$settings$sectionLabels$es._(_root);
  @override
  late final _Translations$settings$errors$es errors =
      _Translations$settings$errors$es._(_root);
  @override
  late final _Translations$settings$promptStatus$es promptStatus =
      _Translations$settings$promptStatus$es._(_root);
  @override
  late final _Translations$settings$clearData$es clearData =
      _Translations$settings$clearData$es._(_root);
  @override
  List<String> get guardrailStageLabels => [
    'Relajado',
    'Equilibrado',
    'Estricto',
    'Paranoico',
  ];
  @override
  late final _Translations$settings$guardrailMacro$es guardrailMacro =
      _Translations$settings$guardrailMacro$es._(_root);
  @override
  late final _Translations$settings$guardrails$es guardrails =
      _Translations$settings$guardrails$es._(_root);
  @override
  late final _Translations$settings$appearance$es appearance =
      _Translations$settings$appearance$es._(_root);
  @override
  late final _Translations$settings$retention$es retention =
      _Translations$settings$retention$es._(_root);
  @override
  late final _Translations$settings$navigation$es navigation =
      _Translations$settings$navigation$es._(_root);
  @override
  late final _Translations$settings$behaviour$es behaviour =
      _Translations$settings$behaviour$es._(_root);
  @override
  late final _Translations$settings$retentionClear$es retentionClear =
      _Translations$settings$retentionClear$es._(_root);
  @override
  late final _Translations$settings$channels$es channels =
      _Translations$settings$channels$es._(_root);
  @override
  late final _Translations$settings$pollResult$es pollResult =
      _Translations$settings$pollResult$es._(_root);
  @override
  late final _Translations$settings$keybindingProfile$es keybindingProfile =
      _Translations$settings$keybindingProfile$es._(_root);
  @override
  late final _Translations$settings$apiKeys$es apiKeys =
      _Translations$settings$apiKeys$es._(_root);
  @override
  late final _Translations$settings$shortcuts$es shortcuts =
      _Translations$settings$shortcuts$es._(_root);
  @override
  late final _Translations$settings$toggles$es toggles =
      _Translations$settings$toggles$es._(_root);
  @override
  late final _Translations$settings$diffDiffability$es diffDiffability =
      _Translations$settings$diffDiffability$es._(_root);
  @override
  late final _Translations$settings$modelSlots$es modelSlots =
      _Translations$settings$modelSlots$es._(_root);
  @override
  late final _Translations$settings$modelPicker$es modelPicker =
      _Translations$settings$modelPicker$es._(_root);
  @override
  late final _Translations$settings$aiFeatures$es aiFeatures =
      _Translations$settings$aiFeatures$es._(_root);
  @override
  late final _Translations$settings$commitEditor$es commitEditor =
      _Translations$settings$commitEditor$es._(_root);
  @override
  late final _Translations$settings$review$es review =
      _Translations$settings$review$es._(_root);
  @override
  late final _Translations$settings$museHint$es museHint =
      _Translations$settings$museHint$es._(_root);
  @override
  late final _Translations$settings$museEditor$es museEditor =
      _Translations$settings$museEditor$es._(_root);
  @override
  late final _Translations$settings$museStage$es museStage =
      _Translations$settings$museStage$es._(_root);
  @override
  late final _Translations$settings$lensAxis$es lensAxis =
      _Translations$settings$lensAxis$es._(_root);
  @override
  late final _Translations$settings$logosLens$es logosLens =
      _Translations$settings$logosLens$es._(_root);
  @override
  late final _Translations$settings$sortGuide$es sortGuide =
      _Translations$settings$sortGuide$es._(_root);
  @override
  late final _Translations$settings$piggyback$es piggyback =
      _Translations$settings$piggyback$es._(_root);
  @override
  late final _Translations$settings$diffStage$es diffStage =
      _Translations$settings$diffStage$es._(_root);
  @override
  late final _Translations$settings$undoScope$es undoScope =
      _Translations$settings$undoScope$es._(_root);
  @override
  late final _Translations$settings$undoWindow$es undoWindow =
      _Translations$settings$undoWindow$es._(_root);
  @override
  late final _Translations$settings$guardrailPhrase$es guardrailPhrase =
      _Translations$settings$guardrailPhrase$es._(_root);
  @override
  late final _Translations$settings$reviewGuideHint$es reviewGuideHint =
      _Translations$settings$reviewGuideHint$es._(_root);
  @override
  late final _Translations$settings$commitFormat$es commitFormat =
      _Translations$settings$commitFormat$es._(_root);
  @override
  late final _Translations$settings$commitPreview$es commitPreview =
      _Translations$settings$commitPreview$es._(_root);
  @override
  late final _Translations$settings$externalTools$es externalTools =
      _Translations$settings$externalTools$es._(_root);
  @override
  late final _Translations$settings$apiUsage$es apiUsage =
      _Translations$settings$apiUsage$es._(_root);
  @override
  late final _Translations$settings$gitea$es gitea =
      _Translations$settings$gitea$es._(_root);
  @override
  late final _Translations$settings$wick$es wick =
      _Translations$settings$wick$es._(_root);
  @override
  late final _Translations$settings$integrations$es integrations =
      _Translations$settings$integrations$es._(_root);
  @override
  late final _Translations$settings$reduceMotion$es reduceMotion =
      _Translations$settings$reduceMotion$es._(_root);
  @override
  late final _Translations$settings$resetQuit$es resetQuit =
      _Translations$settings$resetQuit$es._(_root);
  @override
  late final _Translations$settings$diagnostics$es diagnostics =
      _Translations$settings$diagnostics$es._(_root);
  @override
  late final _Translations$settings$telemetry$es telemetry =
      _Translations$settings$telemetry$es._(_root);
  @override
  late final _Translations$settings$flowEngine$es flowEngine =
      _Translations$settings$flowEngine$es._(_root);
  @override
  late final _Translations$settings$museStrands$es museStrands =
      _Translations$settings$museStrands$es._(_root);
  @override
  late final _Translations$settings$cliPiggyback$es cliPiggyback =
      _Translations$settings$cliPiggyback$es._(_root);
  @override
  late final _Translations$settings$header$es header =
      _Translations$settings$header$es._(_root);
  @override
  late final _Translations$settings$diagnosticsPanel$es diagnosticsPanel =
      _Translations$settings$diagnosticsPanel$es._(_root);
  @override
  late final _Translations$settings$release$es release =
      _Translations$settings$release$es._(_root);
  @override
  late final _Translations$settings$providerStatus$es providerStatus =
      _Translations$settings$providerStatus$es._(_root);
  @override
  late final _Translations$settings$meridiem$es meridiem =
      _Translations$settings$meridiem$es._(_root);
  @override
  late final _Translations$settings$offenders$es offenders =
      _Translations$settings$offenders$es._(_root);
}

// Path: sync
class _Translations$sync$es extends Translations$sync$en {
  _Translations$sync$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$actions$es actions =
      _Translations$sync$actions$es._(_root);
  @override
  late final _Translations$sync$panel$es panel = _Translations$sync$panel$es._(
    _root,
  );
  @override
  late final _Translations$sync$forcePush$es forcePush =
      _Translations$sync$forcePush$es._(_root);
}

// Path: xray
class _Translations$xray$es extends Translations$xray$en {
  _Translations$xray$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$board$es board = _Translations$xray$board$es._(
    _root,
  );
  @override
  late final _Translations$xray$cadence$es cadence =
      _Translations$xray$cadence$es._(_root);
  @override
  late final _Translations$xray$cards$es cards = _Translations$xray$cards$es._(
    _root,
  );
  @override
  late final _Translations$xray$cardTitle$es cardTitle =
      _Translations$xray$cardTitle$es._(_root);
  @override
  late final _Translations$xray$grain$es grain = _Translations$xray$grain$es._(
    _root,
  );
  @override
  late final _Translations$xray$header$es header =
      _Translations$xray$header$es._(_root);
  @override
  late final _Translations$xray$hotspot$es hotspot =
      _Translations$xray$hotspot$es._(_root);
  @override
  late final _Translations$xray$inspector$es inspector =
      _Translations$xray$inspector$es._(_root);
  @override
  late final _Translations$xray$loadingCard$es loadingCard =
      _Translations$xray$loadingCard$es._(_root);
  @override
  late final _Translations$xray$metabolism$es metabolism =
      _Translations$xray$metabolism$es._(_root);
  @override
  late final _Translations$xray$multi$es multi = _Translations$xray$multi$es._(
    _root,
  );
  @override
  late final _Translations$xray$recency$es recency =
      _Translations$xray$recency$es._(_root);
  @override
  late final _Translations$xray$rings$es rings = _Translations$xray$rings$es._(
    _root,
  );
  @override
  late final _Translations$xray$stats$es stats = _Translations$xray$stats$es._(
    _root,
  );
  @override
  late final _Translations$xray$stratumLabel$es stratumLabel =
      _Translations$xray$stratumLabel$es._(_root);
  @override
  late final _Translations$xray$summary$es summary =
      _Translations$xray$summary$es._(_root);
  @override
  late final _Translations$xray$tabs$es tabs = _Translations$xray$tabs$es._(
    _root,
  );
  @override
  late final _Translations$xray$trajectory$es trajectory =
      _Translations$xray$trajectory$es._(_root);
  @override
  late final _Translations$xray$verdict$es verdict =
      _Translations$xray$verdict$es._(_root);
}

// Path: app.cheatsheet
class _Translations$app$cheatsheet$es extends Translations$app$cheatsheet$en {
  _Translations$app$cheatsheet$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Teclado';
  @override
  String get sectionNavigate => 'navegar';
  @override
  String get sectionStaging => 'stage';
  @override
  String get sectionBranchesPrs => 'ramas y PRs';
  @override
  String get changes => 'Cambios';
  @override
  String get history => 'Historial';
  @override
  String get branches => 'Ramas';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Cambiar (siempre)';
  @override
  String get commandPalette => 'Paleta de comandos';
  @override
  String get elevatedPalette => 'Paleta elevada';
  @override
  String get dismiss => 'Descartar';
  @override
  String get refresh => 'Actualizar';
  @override
  String get nextPrevChange => 'Cambio siguiente / anterior';
  @override
  String get toggleLine => 'Alternar línea';
  @override
  String get toggleHunk => 'Alternar hunk';
  @override
  String get toggleFile => 'Alternar archivo';
  @override
  String get pinContext => 'Fijar contexto';
  @override
  String get commit => 'Commit';
  @override
  String get acceptAiHint => 'Aceptar sugerencia de IA';
  @override
  String get undo => 'Deshacer';
  @override
  String get navigate => 'Navegar';
  @override
  String get expand => 'Expandir';
  @override
  String get checkoutPr => 'Checkout del PR';
  @override
  String get approve => 'Aprobar';
  @override
  String get requestChanges => 'Solicitar cambios';
  @override
  String profileSwitchHint({required Object profile}) =>
      'perfil ${profile} · cámbialo en Ajustes';
}

// Path: backend.ops
class _Translations$backend$ops$es extends Translations$backend$ops$en {
  _Translations$backend$ops$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'Merge';
  @override
  String get pull => 'Pull';
  @override
  String get apply => 'Aplicar';
  @override
  String get switchOp => 'Cambiar';
  @override
  String get sync => 'Sincronizar';
}

// Path: backend.mergeOutcome
class _Translations$backend$mergeOutcome$es
    extends Translations$backend$mergeOutcome$en {
  _Translations$backend$mergeOutcome$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String cancelled({required Object op}) => '${op} cancelado.';
  @override
  String complete({required Object op}) => '${op} completado.';
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'queda ${n} conflicto — resuélvelo en la página de Cambios.',
        other: 'quedan ${n} conflictos — resuélvelos en la página de Cambios.',
      );
  @override
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'Se resolvió ${n} conflicto.',
        other: 'Se resolvieron ${n} conflictos.',
      );
  @override
  String uncommittedEdits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} archivo tiene cambios sin commit — haz commit primero.',
        other: '${n} archivos tienen cambios sin commit — haz commit primero.',
      );
}

// Path: changes.usage
class _Translations$changes$usage$es extends Translations$changes$usage$en {
  _Translations$changes$usage$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String caption({required Object input, required Object output}) =>
      '${input} entrada · ${output} salida';
  @override
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '${fresh} entrada · ${cached} en caché · ${out} salida';
  @override
  String get inWord => 'entrada';
  @override
  String get cachedWord => 'en caché';
  @override
  String get outWord => 'salida';
  @override
  String tipIn({required Object value}) => '${value}  entrada';
  @override
  String tipCacheRead({required Object value}) => '${value}  lectura de caché';
  @override
  String tipCacheWrite({required Object value}) =>
      '${value}  escritura de caché';
  @override
  String tipOut({required Object value}) => '${value}  salida';
  @override
  String tipReasoning({required Object value}) => '${value}  razonamiento';
  @override
  String tipWallClock({required Object value}) => '${value}s  tiempo real';
}

// Path: changes.tabs
class _Translations$changes$tabs$es extends Translations$changes$tabs$en {
  _Translations$changes$tabs$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get defaultLabel => 'Cambios';
  @override
  String get empty => 'Vacío';
}

// Path: changes.tabStrip
class _Translations$changes$tabStrip$es
    extends Translations$changes$tabStrip$en {
  _Translations$changes$tabStrip$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get newDiffTab => 'Nueva pestaña de diff';
}

// Path: changes.select
class _Translations$changes$select$es extends Translations$changes$select$en {
  _Translations$changes$select$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get selectAll => 'Seleccionar todo';
  @override
  String get deselectAll => 'Deseleccionar todo';
}

// Path: changes.constellationToggle
class _Translations$changes$constellationToggle$es
    extends Translations$changes$constellationToggle$en {
  _Translations$changes$constellationToggle$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get backToList => 'volver a la lista';
  @override
  String get atlas => 'atlas, ver candidatos a commit';
}

// Path: changes.nudgeChip
class _Translations$changes$nudgeChip$es
    extends Translations$changes$nudgeChip$en {
  _Translations$changes$nudgeChip$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\nse acopla con ${anchor} · ${pct}%${receipts}';
}

// Path: changes.minimap
class _Translations$changes$minimap$es extends Translations$changes$minimap$en {
  _Translations$changes$minimap$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get roleNew => 'nuevo';
  @override
  String get roleBridge => 'puente';
  @override
  String get roleHub => 'hub';
  @override
  String get roleLeaf => 'hoja';
  @override
  String get roleConnected => 'conectado';
  @override
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';
  @override
  String changesWith({required Object name}) => 'cambia con ${name}';
  @override
  String get newFile => 'archivo nuevo';
  @override
  String nearOtherChanges({required Object count, required Object dir}) =>
      'cerca de ${count} otros cambios en ${dir}';
  @override
  String usuallyChangesWithFile({required Object name}) =>
      '${name} suele cambiar con este archivo';
}

// Path: changes.tagInput
class _Translations$changes$tagInput$es
    extends Translations$changes$tagInput$en {
  _Translations$changes$tagInput$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get hint => 'etiqueta...';
}

// Path: changes.composer
class _Translations$changes$composer$es
    extends Translations$changes$composer$en {
  _Translations$changes$composer$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get hintPlaceholder => 'mensaje de commit...';
  @override
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class _Translations$changes$commit$es extends Translations$changes$commit$en {
  _Translations$changes$commit$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get primaryCommitChanges => 'Hacer commit de los cambios';
  @override
  String get primaryCommitChangesDetail =>
      'HEAD desacoplado: haz commit localmente sin sincronizar.';
  @override
  String get primaryPublish => 'Commit y publicar';
  @override
  String get primaryPublishDetail =>
      'Crea el commit y publica esta rama en un solo paso.';
  @override
  String get primarySync => 'Commit y sincronizar';
  @override
  String get primarySyncDetail =>
      'Crea el commit, luego reconcilia y envía la rama.';
  @override
  String get primaryPush => 'Commit y push';
  @override
  String get primaryPushDetail => 'Crea el commit y hazle push de inmediato.';
  @override
  String get amendLast => 'Enmendar el último commit';
  @override
  String amendAnd({required Object action}) => 'Enmendar y ${action}';
  @override
  String get chooseFile =>
      'Elige al menos un archivo para el siguiente commit.';
  @override
  String get writeMessage => 'Escribe primero un mensaje de commit.';
  @override
  String get committing => 'Haciendo commit';
  @override
  String get committingSync => 'Haciendo commit y sincronizando';
  @override
  String get committed => 'Commit hecho.';
  @override
  String get undoFailed => 'Falló el deshacer.';
  @override
  String get working => 'Trabajando…';
  @override
  String get commitOnly => 'Solo commit';
  @override
  String get noRuntimeModels =>
      'No hay modelos descubiertos en tiempo de ejecución disponibles para mensajes de commit.';
  @override
  String restoreFailedRetry({required Object err}) =>
      '${err}\nNo se pudo restaurar el stage de los archivos excluidos; revisa el índice antes de reintentar.';
  @override
  String committedSummary({required Object summary, required Object hash}) =>
      'Commit de ${summary} (${hash}).';
  @override
  String get restoreFailedSync =>
      'No se pudo volver a poner en stage las selecciones de los archivos excluidos; se omitió la sincronización. Revisa el índice antes de sincronizar.';
  @override
  String get noModelLabel => 'Sin modelo';
  @override
  String get chooseBeforeGenerate =>
      'Elige al menos un archivo antes de generar.';
  @override
  String get aiUnavailable =>
      'La IA de mensajes de commit aún no está disponible.';
  @override
  String get generateFailed => 'Falló la generación.';
  @override
  String get stageFailed => 'No se pudieron poner los archivos en stage.';
  @override
  String get commitFailed => 'Falló el commit.';
  @override
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => 'Commit de ${summary} (${hash}) y se ejecutó ${operation}.';
  @override
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
    n,
    one: 'Commit de ${summary} (${hash}); se resolvió ${n} conflicto.',
    other: 'Commit de ${summary} (${hash}); se resolvieron ${n} conflictos.',
  );
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'queda ${n} conflicto por resolver.',
        other: 'quedan ${n} conflictos por resolver.',
      );
  @override
  String syncBlocked({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
    n,
    one:
        'El commit se hizo, pero la sincronización quedó bloqueada por ${n} archivo sin commit.',
    other:
        'El commit se hizo, pero la sincronización quedó bloqueada por ${n} archivos sin commit.',
  );
  @override
  String syncStalled({required Object message}) =>
      'El commit se hizo, pero la sincronización se estancó: ${message}';
  @override
  String syncFailed({required Object message}) =>
      'El commit se hizo, pero la sincronización falló: ${message}';
}

// Path: changes.rebase
class _Translations$changes$rebase$es extends Translations$changes$rebase$en {
  _Translations$changes$rebase$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get continueFailed => 'No se pudo continuar el rebase.';
}

// Path: changes.editor
class _Translations$changes$editor$es extends Translations$changes$editor$en {
  _Translations$changes$editor$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get closeBarrier => 'Cerrar editor';
}

// Path: changes.editorTitles
class _Translations$changes$editorTitles$es
    extends Translations$changes$editorTitles$en {
  _Translations$changes$editorTitles$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  List<String> get any => [
    'querido git log',
    'for-git me, cielos, que he pecado…',
    'ponle nombre a este momento',
    'suéltalo ya',
    '¡habla!',
    'tu madre era una referencia colgante y tu padre olía a puntos y comas',
  ];
  @override
  List<String> get short => [
    '¿ah?',
    'hola qué tal :)',
    'por cierto:',
    'unas palabras',
    'la versión educada',
    'deja una nota',
    '¿decías..?',
    'eso, suéltalo',
  ];
  @override
  List<String> get mid => [
    'para que conste',
    'díselo al tú del futuro',
    'pero antes…',
    'cómo salió',
    'con tus propias palabras',
    '¿que hiciste QUÉ?',
    'debidamente anotado',
    'tienes mi atención',
  ];
  @override
  List<String> get long => [
    'tus sueños, por favor',
    'di algo bonito',
    '... y entonces dije:',
    'la posteridad espera',
    'escribir más hace desaparecer tus bugs',
    'vaya, vaya',
    'los textos sagrados',
  ];
}

// Path: changes.askHint
class _Translations$changes$askHint$es extends Translations$changes$askHint$en {
  _Translations$changes$askHint$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String round({required Object n}) => 'ronda ${n} — refina o añade contexto.';
  @override
  String get symptom => 'describe el síntoma.';
  @override
  String get broken => '¿qué está roto?';
  @override
  String get bug => 'describe el bug.';
  @override
  String get error => 'pega el error.';
}

// Path: changes.fileMenu
class _Translations$changes$fileMenu$es
    extends Translations$changes$fileMenu$en {
  _Translations$changes$fileMenu$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get ripple => 'Onda';
  @override
  String get includeCoChanges => 'Incluir co-cambios';
  @override
  String deleteFile({required Object name}) => 'Eliminar ${name}…';
  @override
  String discardChangesTo({required Object name}) =>
      'Descartar cambios en ${name}…';
  @override
  String get ignore => 'Ignorar';
  @override
  String get diffTabFromSelection => 'Pestaña de diff desde la selección';
  @override
  String addSelectedToTab({required Object name}) =>
      'Añadir seleccionados a ${name}';
  @override
  String diffTabFromFile({required Object name}) =>
      'Pestaña de diff desde ${name}';
  @override
  String addFileToTab({required Object file, required Object tab}) =>
      'Añadir ${file} a ${tab}';
  @override
  String get copyFilePath => 'Copiar ruta del archivo';
  @override
  String get showInExplorer => 'Mostrar en el explorador';
}

// Path: changes.multiFileMenu
class _Translations$changes$multiFileMenu$es
    extends Translations$changes$multiFileMenu$en {
  _Translations$changes$multiFileMenu$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get cohesionTight => 'fuertemente acoplados';
  @override
  String get cohesionLoose => 'poco relacionados';
  @override
  String get cohesionScattered => 'estructuralmente dispersos';
  @override
  String get clusterOne => 'todos en un clúster';
  @override
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      'abarca ${count} clústeres (${parts} archivos)';
  @override
  String clusterSpans({required Object count}) => 'abarca ${count} clústeres';
  @override
  String roleLine({required Object count, required Object cohesion}) =>
      '${count} archivos · ${cohesion}';
  @override
  String usuallyChangesWithGroup({required Object file}) =>
      '${file} suele cambiar con este grupo';
  @override
  String get splitToNewTab => 'Dividir en una pestaña nueva';
  @override
  String copyPaths({required Object count}) => 'Copiar ${count} rutas';
}

// Path: changes.ignoreMenu
class _Translations$changes$ignoreMenu$es
    extends Translations$changes$ignoreMenu$en {
  _Translations$changes$ignoreMenu$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String extension({required Object ext}) => 'extensión .${ext}';
  @override
  String allSelected({required Object count}) => 'Los ${count} seleccionados';
  @override
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'Se acopla con ${n} archivo incluido',
        other: 'Se acopla con ${n} archivos incluidos',
      );
  @override
  String get updateFailed => 'No se pudo actualizar el .gitignore.';
}

// Path: changes.discard
class _Translations$changes$discard$es extends Translations$changes$discard$en {
  _Translations$changes$discard$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String deleteTitle({required Object name}) => '¿Eliminar ${name}?';
  @override
  String discardTitle({required Object name}) =>
      '¿Descartar los cambios en ${name}?';
  @override
  String deleteBody({required Object path}) =>
      '${path} se eliminará del disco. Esto no se puede deshacer desde dentro de la app.';
  @override
  String discardBody({required Object path}) =>
      'Todos los cambios en ${path} se revertirán a su estado en HEAD. Esto no se puede deshacer.';
  @override
  String get discard => 'Descartar';
  @override
  String deletingFile({required Object name}) => 'Eliminando ${name}';
  @override
  String discardingFile({required Object name}) => 'Descartando ${name}';
  @override
  String get discardFailed => 'No se pudieron descartar los cambios.';
  @override
  String discardManyTitle({required Object count}) =>
      '¿Descartar los cambios en ${count} archivos?';
  @override
  String get discardManyBody =>
      'Los archivos rastreados se revertirán a su estado en HEAD; los no rastreados se eliminarán del disco. Esto no se puede deshacer.';
  @override
  String discardManyConfirm({required Object count}) => 'Descartar ${count}';
  @override
  String discardingManyFiles({required Object count}) =>
      'Descartando ${count} archivos';
  @override
  String failedOpenExplorer({required Object error}) =>
      'No se pudo abrir el explorador de archivos: ${error}';
  @override
  String get someFailed => 'Algunos descartes fallaron.';
}

// Path: changes.snack
class _Translations$changes$snack$es extends Translations$changes$snack$en {
  _Translations$changes$snack$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get sameWorktree => 'Mismo árbol de trabajo — no hay nada que volcar.';
  @override
  String diffFailed({required Object error}) => 'Falló el diff: ${error}';
  @override
  String get deskEmpty =>
      'El Desk no tiene nada por delante de ti — volcado vacío.';
  @override
  String sourceDesk({required Object label}) => 'Desk ${label}';
  @override
  String shelfReadFailed({required Object error}) =>
      'Falló la lectura del estante: ${error}';
  @override
  String get shelfEmpty => 'Estante vacío — no hay nada que volcar.';
  @override
  String sourceShelf({required Object label}) => 'estante ${label}';
  @override
  String noModelConfigured({required Object label}) =>
      'No hay modelo configurado para "${label}".';
  @override
  String fetchFailed({required Object error}) => 'Falló el fetch: ${error}';
}

// Path: changes.trace
class _Translations$changes$trace$es extends Translations$changes$trace$en {
  _Translations$changes$trace$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Traza de verificación';
  @override
  String get draftReview => 'Borrador de revisión';
}

// Path: changes.cleanTree
class _Translations$changes$cleanTree$es
    extends Translations$changes$cleanTree$en {
  _Translations$changes$cleanTree$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Árbol de trabajo limpio';
  @override
  String get subtitle => 'No se detectaron cambios en stage ni fuera de él.';
  @override
  String get noUpstream => '  ·  sin upstream';
  @override
  String get ahead => ' por delante';
  @override
  String get behind => ' por detrás';
  @override
  String get refreshing => 'Actualizando...';
  @override
  String get refresh => 'Actualizar';
  @override
  String get check => 'comprobar';
  @override
  String get checkTooltip => 'Fetch y actualización local.';
  @override
  String get sync => '& sincronizar';
}

// Path: changes.guardrail
class _Translations$changes$guardrail$es
    extends Translations$changes$guardrail$en {
  _Translations$changes$guardrail$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'Relajado';
  @override
  String get balanced => 'Equilibrado';
  @override
  String get strict => 'Estricto';
  @override
  String get paranoid => 'Paranoico';
}

// Path: changes.dropHint
class _Translations$changes$dropHint$es
    extends Translations$changes$dropHint$en {
  _Translations$changes$dropHint$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get fromShelf => 'suelta para traer los cambios de este estante aquí';
  @override
  String get fromDesk => 'suelta para traer los cambios de este Desk aquí';
}

// Path: changes.diffEmpty
class _Translations$changes$diffEmpty$es
    extends Translations$changes$diffEmpty$en {
  _Translations$changes$diffEmpty$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Ningún archivo seleccionado';
  @override
  String get message =>
      'Selecciona un archivo modificado para inspeccionar su diff.';
}

// Path: changes.shelvePill
class _Translations$changes$shelvePill$es
    extends Translations$changes$shelvePill$en {
  _Translations$changes$shelvePill$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String shelveN({required Object count}) => '↓ guardar ${count}';
  @override
  String get shelve => '↓ guardar';
  @override
  String shelvedCount({required Object count, required Object glyph}) =>
      '${count} guardados ${glyph}';
}

// Path: changes.stashAction
class _Translations$changes$stashAction$es
    extends Translations$changes$stashAction$en {
  _Translations$changes$stashAction$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get pickUp => 'recoger';
  @override
  String get peek => 'asomar';
  @override
  String get toss => 'tirar';
}

// Path: changes.stashContents
class _Translations$changes$stashContents$es
    extends Translations$changes$stashContents$en {
  _Translations$changes$stashContents$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get reading => 'leyendo el estante…';
  @override
  String get empty => 'estante vacío';
}

// Path: changes.stashFile
class _Translations$changes$stashFile$es
    extends Translations$changes$stashFile$en {
  _Translations$changes$stashFile$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get binary => 'bin';
}

// Path: changes.fileRow
class _Translations$changes$fileRow$es extends Translations$changes$fileRow$en {
  _Translations$changes$fileRow$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get stagedLinesOnly => 'hace commit solo de las líneas en stage';
  @override
  String get doubleClickToggle => 'doble clic: alternar todo el grupo';
  @override
  String get repoRoot => 'Raíz del repositorio';
}

// Path: changes.resolveStrip
class _Translations$changes$resolveStrip$es
    extends Translations$changes$resolveStrip$en {
  _Translations$changes$resolveStrip$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'leyendo ${n} archivo · redactando resolución…',
        other: 'leyendo ${n} archivos · redactando resolución…',
      );
  @override
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} conflicto en ${files}',
        other: '${n} conflictos en ${files}',
      );
  @override
  String get resolve => 'Resolver';
  @override
  String get orWith => 'O CON';
  @override
  String resolveWith({required Object label}) => 'resolver con ${label}';
  @override
  String resolveWithModel({required Object label, required Object model}) =>
      'resolver con ${label}  ·  ${model}';
  @override
  String get resolving => 'resolviendo…';
  @override
  String resolveWithGlyph({required Object label}) =>
      '↵  resolver con ${label}';
  @override
  String get orWithAnother => 'o con otro modelo';
}

// Path: changes.badge
class _Translations$changes$badge$es extends Translations$changes$badge$en {
  _Translations$changes$badge$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get stagedEdit => 'Edición en stage';
  @override
  String get edited => 'Editado';
  @override
  String get stagedAdd => 'Adición en stage';
  @override
  String get added => 'Añadido';
  @override
  String get stagedDelete => 'Eliminación en stage';
  @override
  String get deleted => 'Eliminado';
  @override
  String get stagedRename => 'Renombrado en stage';
  @override
  String get renamed => 'Renombrado';
  @override
  String get stagedCopy => 'Copia en stage';
  @override
  String get copied => 'Copiado';
  @override
  String get conflict => 'Conflicto';
  @override
  String get stagedTypeChange => 'Cambio de tipo en stage';
  @override
  String get typeChanged => 'Tipo cambiado';
  @override
  String get untracked => 'Sin rastrear';
}

// Path: changes.review
class _Translations$changes$review$es extends Translations$changes$review$en {
  _Translations$changes$review$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Revisión de código';
  @override
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} archivo incluido',
        other: '${n} archivos incluidos',
      );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} hunk',
        other: '${n} hunks',
      );
  @override
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';
  @override
  String get unavailable => 'Revisión no disponible';
  @override
  String get backToDiff => 'Volver al diff';
  @override
  String get verified => 'Verificado';
  @override
  String get draftOnly => 'Solo borrador';
  @override
  String get runAgain => 'Ejecutar de nuevo';
  @override
  String draftShownBelow({required Object error}) =>
      '${error} El borrador de revisión se muestra abajo.';
  @override
  String get hideTrace => 'Ocultar traza';
  @override
  String get showTrace => 'Mostrar traza';
  @override
  String get showVerificationTrace => 'Mostrar traza de verificación';
  @override
  String get whyLanded => 'Por qué esta revisión aterrizó aquí';
  @override
  String get noFindings => 'Sin hallazgos';
  @override
  String get findings => 'Hallazgos';
  @override
  String get noEvidenceIssues =>
      'No se detectaron problemas respaldados por evidencia en el alcance de este commit.';
  @override
  String get observations => 'Observaciones';
  @override
  String get chooseBeforeReview =>
      'Elige al menos un archivo antes de revisar.';
  @override
  String get aiUnavailable => 'La IA de revisión aún no está disponible.';
  @override
  String get failed => 'Falló la revisión.';
  @override
  String get noRuntimeModels =>
      'No hay modelos descubiertos en tiempo de ejecución disponibles para la revisión de commits.';
}

// Path: changes.commitBtn
class _Translations$changes$commitBtn$es
    extends Translations$changes$commitBtn$en {
  _Translations$changes$commitBtn$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String switchTo({required Object label}) => 'Cambiar a: ${label}\n';
}

// Path: changes.shapeBtn
class _Translations$changes$shapeBtn$es
    extends Translations$changes$shapeBtn$en {
  _Translations$changes$shapeBtn$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String askingWith({required Object cat}) => 'preguntando con ${cat}…';
  @override
  String askWith({required Object cat}) => 'preguntar con ${cat}';
  @override
  String get noModel => 'no hay modelo de IA configurado';
  @override
  String nextTooltip({required Object cat}) =>
      'siguiente: ${cat}  ·  shift-clic para el anterior';
  @override
  String get onlyOne => 'solo hay una categoría de IA configurada';
}

// Path: changes.dejaVu
class _Translations$changes$dejaVu$es extends Translations$changes$dejaVu$en {
  _Translations$changes$dejaVu$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required num n,
    required Object pct,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
    n,
    one:
        '${pct}% déjà vu — ${n} arista fantasma de líneas temporales descartadas toca este diff',
    other:
        '${pct}% déjà vu — ${n} aristas fantasma de líneas temporales descartadas tocan este diff',
  );
  @override
  String get label => 'déjà vu';
}

// Path: changes.identity
class _Translations$changes$identity$es
    extends Translations$changes$identity$en {
  _Translations$changes$identity$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'no hay identidad de commit configurada';
  @override
  String asName({required Object name}) => 'como ${name}';
  @override
  String asNameEmail({required Object name, required Object email}) =>
      'como ${name} <${email}>';
  @override
  String asNameSpace({required Object name}) => 'como ${name} ';
  @override
  String emailAngle({required Object email}) => '<${email}>';
  @override
  String get firstCommit => '\nprimer commit en este repo';
  @override
  String get newToRepo => '\nnuevo en este repo';
}

// Path: changes.staleScope
class _Translations$changes$staleScope$es
    extends Translations$changes$staleScope$en {
  _Translations$changes$staleScope$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get message => 'la selección cambió desde que esto se ejecutó';
  @override
  String get rerun => 'reejecutar';
}

// Path: changes.finding
class _Translations$changes$finding$es extends Translations$changes$finding$en {
  _Translations$changes$finding$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get openDiff => 'Abrir diff';
  @override
  String get recorded => 'registrado';
  @override
  String get dismiss => 'Descartar';
}

// Path: changes.muse
class _Translations$changes$muse$es extends Translations$changes$muse$en {
  _Translations$changes$muse$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Muse';
  @override
  String get youPulledThis => 'tú sacaste esto';
  @override
  String fromIdea({required Object text}) => 'de la idea: "${text}"';
  @override
  String get foothold => 'punto de apoyo — ';
  @override
  String get brainstormSpew => 'chorro de lluvia de ideas';
  @override
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';
  @override
  String copyN({required Object count}) => 'Copiar ${count}';
  @override
  String get clear => 'Limpiar';
  @override
  String get chooseBeforeMuse =>
      'Elige al menos un archivo antes de invocar a la muse.';
  @override
  String get aiUnavailable => 'La IA de la muse aún no está disponible.';
  @override
  String get failed => 'Falló la muse.';
  @override
  String get noRuntimeModels =>
      'No hay modelos descubiertos en tiempo de ejecución disponibles para la muse.';
  @override
  String get needsModel => 'La muse necesita al menos un modelo configurado.';
  @override
  String get dreaming => 'la muse está soñando...';
}

// Path: changes.debug
class _Translations$changes$debug$es extends Translations$changes$debug$en {
  _Translations$changes$debug$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Depurar';
  @override
  String round({required Object n}) => '· ronda ${n}';
  @override
  String get clear => 'limpiar';
  @override
  String get close => 'cerrar';
  @override
  String get analyzing => 'analizando el síntoma…';
  @override
  String get describeSymptom => 'describe un síntoma, luego pulsa depurar.';
  @override
  String get evidenceFor => 'a favor';
  @override
  String get evidenceAgainst => 'pero';
  @override
  String get narrowDown => 'qué ayudaría a acotarlo:';
  @override
  String get failed => 'Falló la depuración.';
  @override
  String get refinementFailed => 'Falló el refinamiento de la depuración.';
}

// Path: changes.includeSummary
class _Translations$changes$includeSummary$es
    extends Translations$changes$includeSummary$en {
  _Translations$changes$includeSummary$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'Ninguno';
  @override
  String stagedSuffix({required Object count}) => ' · ${count} en stage';
  @override
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'Los ${n} archivo${staged}',
        other: 'Los ${n} archivos${staged}',
      );
  @override
  String partial({
    required Object count,
    required Object n,
    required Object staged,
  }) => '${count} de ${n}${staged}';
  @override
  String shortAll({required Object n, required Object staged}) =>
      'Los ${n}${staged}';
}

// Path: changes.status
class _Translations$changes$status$es extends Translations$changes$status$en {
  _Translations$changes$status$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get unavailableTitle => 'Estado del repositorio no disponible';
  @override
  String get loadingTitle => 'Cargando el estado del repositorio';
  @override
  String get loadingMessage => 'Leyendo el árbol de trabajo.';
}

// Path: changes.stash
class _Translations$changes$stash$es extends Translations$changes$stash$en {
  _Translations$changes$stash$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get appliedWithConflicts =>
      'Stash aplicado con conflictos — resuélvelos en la página de Cambios (la entrada del stash se conservó).';
  @override
  String get couldNotPop => 'No se pudo hacer pop del stash.';
  @override
  String get listChanged =>
      'La lista de stash cambió; se omitió el drop. Inténtalo de nuevo.';
  @override
  String get droppingStash => 'Haciendo drop del stash';
}

// Path: changes.tooltips
class _Translations$changes$tooltips$es
    extends Translations$changes$tooltips$en {
  _Translations$changes$tooltips$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get commitGenerating => 'generando el mensaje de commit...';
  @override
  String get commitPreparing => 'preparando el mensaje de commit...';
  @override
  String get commitSelectFile =>
      'selecciona al menos un archivo para generar un mensaje de commit.';
  @override
  String get commitConfigure =>
      'configura los mensajes de commit en Ajustes > Dinámicas de comportamiento > Mensajes de commit.';
  @override
  String get fastFallback => 'rápido';
  @override
  String commitGenerateWith({required Object label}) =>
      'generar el mensaje de commit con el modelo ${label}';
  @override
  String get museConsulting => 'consultando a la muse...';
  @override
  String get showMuse => 'mostrar la muse';
  @override
  String get museSelectFile => 'selecciona al menos un archivo para la muse.';
  @override
  String get showMuseError => 'mostrar error de la muse';
  @override
  String get museAsk => 'pide dirección a la muse';
  @override
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => 'pide dirección a la muse\n${brainstorm} → ${synthesis}';
  @override
  String get qualityFallback => 'calidad';
  @override
  String get reviewing => 'revisando...';
  @override
  String get showReview => 'mostrar la revisión';
  @override
  String get reviewPreparing => 'preparando la revisión del commit...';
  @override
  String get reviewSelectFile => 'selecciona al menos un archivo para revisar.';
  @override
  String get reviewConfigure => 'configura la IA de revisión en los ajustes.';
  @override
  String get viewingReview => 'viendo la revisión';
  @override
  String reviewWith({required Object guardrail, required Object label}) =>
      'revisión ${guardrail} con el modelo ${label}';
}

// Path: changes.mergeEditor
class _Translations$changes$mergeEditor$es
    extends Translations$changes$mergeEditor$en {
  _Translations$changes$mergeEditor$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get resolutionYours => 'los tuyos';
  @override
  String get resolutionTheirs => 'los suyos';
  @override
  String get resolutionCustom => 'personalizado';
  @override
  String get keepBoth => 'conservar ambos';
  @override
  late final _Translations$changes$mergeEditor$trust$es trust =
      _Translations$changes$mergeEditor$trust$es._(_root);
  @override
  String get allResolved => 'todo resuelto';
  @override
  String get resolveEasy => 'resolver los conflictos fáciles';
  @override
  String get base => 'base';
  @override
  String get cancel => 'cancelar';
  @override
  String get save => 'guardar';
  @override
  String get complete => 'completar';
  @override
  String get nextFile => 'siguiente archivo';
  @override
  String get edit => 'editar';
  @override
  String get auto => 'auto';
  @override
  String get undo => 'deshacer';
  @override
  late final _Translations$changes$mergeEditor$keyHints$es keyHints =
      _Translations$changes$mergeEditor$keyHints$es._(_root);
  @override
  String get favoredTooltip =>
      'favorecido estructuralmente por el análisis de acoplamiento';
  @override
  String get newOnBothSides => '(nuevo en ambos lados)';
  @override
  String writeFailed({required Object error}) =>
      'No se pudieron escribir los archivos resueltos: ${error}';
  @override
  String neighborsCoChanged({required Object changed, required Object total}) =>
      '${changed}/${total} vecinos co-cambiaron';
  @override
  String integrity({required Object pct}) => 'integridad ${pct}%';
  @override
  String reviewer({required Object name}) => 'revisor: ${name}';
}

// Path: changes.conflictResolution
class _Translations$changes$conflictResolution$es
    extends Translations$changes$conflictResolution$en {
  _Translations$changes$conflictResolution$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String noModelConfigured({required Object category}) =>
      'No hay modelo configurado para "${category}". Define uno en Ajustes → IA.';
  @override
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} archivo sensible omitido — resuélvelo a mano.',
        other: '${n} archivos sensibles omitidos — resuélvelos a mano.',
      );
  @override
  String get couldNotReadFiles =>
      'No se pudo leer ningún archivo en conflicto.';
  @override
  String blockedSecret({required Object secret}) =>
      'Bloqueado — un archivo en conflicto parece contener un ${secret}. Resuélvelo a mano.';
  @override
  String resolutionFailed({required Object error}) =>
      'Falló la resolución: ${error}';
  @override
  String mergeResolutionLabel({
    required Object resolved,
    required Object total,
    required Object category,
  }) => '◇ resolución de merge · ${resolved}/${total} archivos · ${category}';
  @override
  String conflictSummary({
    required Object op,
    required Object conflicts,
    required Object files,
  }) => '${op} · ${conflicts} en ${files}';
  @override
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} conflicto',
        other: '${n} conflictos',
      );
  @override
  String get mergeEditorButton => '⇋ editor de merge';
  @override
  String get noAiModel => 'sin modelo de IA';
  @override
  String get later => 'más tarde';
  @override
  String get discard => 'descartar';
  @override
  String get resolveWithAi => '◇ resolver con IA';
  @override
  String get otherModel => 'otro modelo';
  @override
  String withModel({required Object model}) => 'con ${model}';
}

// Path: changes.mergeFlow
class _Translations$changes$mergeFlow$es
    extends Translations$changes$mergeFlow$en {
  _Translations$changes$mergeFlow$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$mergeFlow$op$es op =
      _Translations$changes$mergeFlow$op$es._(_root);
  @override
  String get pushFailed => 'Falló el push';
  @override
  String get rebasedAndPushed => 'Rebasado y con push.';
  @override
  String switchedTo({required Object name}) => 'Cambiado a ${name}.';
  @override
  String get switchFailed => 'Falló el cambio.';
  @override
  String switchedToCarried({required Object name}) =>
      'Cambiado a ${name} (los cambios se llevaron consigo).';
  @override
  String get alreadyUpToDate => 'Ya está al día.';
  @override
  String merged({required Object upstream, required Object n}) =>
      'Fusionado ${upstream} (${n} archivos).';
  @override
  String get rebaseNotConverge =>
      'El rebase no convergió — resuélvelo manualmente.';
  @override
  String get rebased => 'Rebasado.';
  @override
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'Rebasado (se resolvió ${n} archivo).',
        other: 'Rebasado (se resolvieron ${n} archivos).',
      );
  @override
  String get detachedHead =>
      'No se puede sincronizar: estado de HEAD desacoplado. Cambia a una rama primero.';
  @override
  String get publishFailed => 'Falló la publicación.';
  @override
  String get noRemote =>
      'No hay remoto configurado. Añade uno para publicar esta rama.';
  @override
  String get failed => 'falló';
}

// Path: changes.constellation
class _Translations$changes$constellation$es
    extends Translations$changes$constellation$en {
  _Translations$changes$constellation$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get axisStructure => 'ESTRUCTURA';
  @override
  String get axisCoChange => 'CO-CAMBIO';
  @override
  String get axisSpectralProfile => 'PERFIL ESPECTRAL';
  @override
  String get axisPathSiblings => 'HERMANOS DE RUTA';
  @override
  String get axisDiffStructure => 'ESTRUCTURA DEL DIFF';
  @override
  String get axisSpectral => 'ESPECTRAL';
  @override
  String get titleUnsorted => 'SIN ORDENAR';
  @override
  String get titleSingleton => 'SINGLETÓN';
  @override
  String get titleMixed => 'MIXTO';
  @override
  String get untie => 'desatar';
  @override
  String get bind => 'atar';
  @override
  String get emptyClusters => 'aún no hay clústeres';
}

// Path: common.time
class _Translations$common$time$es extends Translations$common$time$en {
  _Translations$common$time$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get now => 'ahora';
  @override
  String get justNow => 'recién';
  @override
  String get today => 'HOY';
  @override
  String minutesAgo({required Object n}) => 'hace ${n}min';
  @override
  String hoursAgo({required Object n}) => 'hace ${n}h';
  @override
  String daysAgo({required Object n}) => 'hace ${n}d';
  @override
  String weeksAgo({required Object n}) => 'hace ${n}sem';
  @override
  String monthsAgo({required Object n}) => 'hace ${n}mes';
  @override
  String yearsAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'hace ${n}a',
        other: 'hace ${n}a',
      );
  @override
  String minutesShort({required Object n}) => '${n}min';
  @override
  String hoursShort({required Object n}) => '${n}h';
  @override
  String daysShort({required Object n}) => '${n}d';
  @override
  String weeksShort({required Object n}) => '${n}sem';
  @override
  String monthsShort({required Object n}) => '${n}mes';
  @override
  String yearsShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n}a',
        other: '${n}a',
      );
  @override
  String commitMonthsShort({required Object n}) => '${n}mes';
  @override
  String get idle => 'inactivo';
  @override
  String idleDays({required Object n}) => 'inactivo ${n} días';
  @override
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'inactivo ${n} año',
        other: 'inactivo ${n} años',
      );
  @override
  List<String> get monthAbbrevs => [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
}

// Path: common.size
class _Translations$common$size$es extends Translations$common$size$en {
  _Translations$common$size$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

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
class _Translations$diff$status$es extends Translations$diff$status$en {
  _Translations$diff$status$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Cargando diff';
  @override
  String get loadingMessage => 'Leyendo los cambios del archivo.';
  @override
  String get unavailableTitle => 'Diff no disponible';
  @override
  String get noChangesTitle => 'Sin cambios';
  @override
  String get noChangesMessage =>
      'Este archivo no tiene contenido de diff para mostrar.';
}

// Path: diff.toolbar
class _Translations$diff$toolbar$es extends Translations$diff$toolbar$en {
  _Translations$diff$toolbar$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get searchHint => 'buscar en el diff...';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} línea',
        other: '${n} líneas',
      );
  @override
  String get blameLoading => 'blame...';
  @override
  String get blame => 'blame';
  @override
  String get wearMapOn => 'desgaste · on';
  @override
  String get wearMapOnHint => 'mapa de desgaste activo — clic para ocultar';
  @override
  String get wearMapOffHint =>
      'mostrar mapa de desgaste (mapa de calor de actividad)';
  @override
  String get trailBadge => '· rastro';
}

// Path: diff.hunkDropdown
class _Translations$diff$hunkDropdown$es
    extends Translations$diff$hunkDropdown$en {
  _Translations$diff$hunkDropdown$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip => 'Salta al bloque de cambios. Git los llama hunks.';
  @override
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} cambio',
        other: '${n} cambios',
      );
}

// Path: diff.trail
class _Translations$diff$trail$es extends Translations$diff$trail$en {
  _Translations$diff$trail$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'cargando rastro...';
  @override
  String get noHistory => 'no se encontró historial';
  @override
  String get nowWorkingCopy => 'ahora · copia de trabajo';
  @override
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class _Translations$diff$pinned$es extends Translations$diff$pinned$en {
  _Translations$diff$pinned$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get loadingContext => 'cargando contexto fijado';
  @override
  String get pageManifold => 'Manifold';
  @override
  String get pageSignals => 'Señales';
  @override
  String get echoesTitle => 'Ecos';
  @override
  String get technicalLedger => 'Registro técnico';
  @override
  String get noSecondaryCues => 'No se detectaron señales secundarias.';
  @override
  String get linkedPaths => 'Rutas vinculadas';
  @override
  String moreCount({required Object n}) => '+${n} más';
  @override
  String get localSeam => 'Costura local';
  @override
  String get sharedOwnership => 'propiedad compartida';
  @override
  String get historyWarmingUp => 'El historial se está calentando';
  @override
  String echoesTotal({required Object n}) => '${n} EN TOTAL';
  @override
  String get noEchoes => 'Sin ecos en este diff.';
  @override
  String openRelatedFile({required Object name}) =>
      'Abrir archivo relacionado ${name}';
  @override
  String inspectFile({required Object name}) => 'inspeccionar ${name}';
  @override
  String get jumpEcho => 'saltar al eco';
  @override
  String get copyLine => 'copiar línea';
  @override
  String get signalTempo => 'T';
  @override
  String get signalNovelty => 'N';
  @override
  String get signalReach => 'A';
  @override
  late final _Translations$diff$pinned$tempo$es tempo =
      _Translations$diff$pinned$tempo$es._(_root);
  @override
  late final _Translations$diff$pinned$tone$es tone =
      _Translations$diff$pinned$tone$es._(_root);
  @override
  late final _Translations$diff$pinned$summary$es summary =
      _Translations$diff$pinned$summary$es._(_root);
  @override
  late final _Translations$diff$pinned$tightness$es tightness =
      _Translations$diff$pinned$tightness$es._(_root);
  @override
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept} (${tightness})';
  @override
  String get storyWhyThisMatters => 'Por qué importa';
  @override
  String get storyConfidence => 'Confianza';
  @override
  String get storySecondarySignal => 'Señal secundaria';
  @override
  String get storyNeighbourhood => 'Vecindario';
  @override
  String neighbourhoodDetail({required Object name}) =>
      'Esta línea se ubica cerca de ${name} en el campo actual del código.';
  @override
  String get propagationLane => 'Carril de propagación';
  @override
  String propagationLaneNamed({required Object lane}) =>
      'Carril de propagación: ${lane}';
  @override
  late final _Translations$diff$pinned$witness$es witness =
      _Translations$diff$pinned$witness$es._(_root);
  @override
  late final _Translations$diff$pinned$integrity$es integrity =
      _Translations$diff$pinned$integrity$es._(_root);
  @override
  late final _Translations$diff$pinned$related$es related =
      _Translations$diff$pinned$related$es._(_root);
  @override
  late final _Translations$diff$pinned$axis$es axis =
      _Translations$diff$pinned$axis$es._(_root);
}

// Path: diff.hunkHint
class _Translations$diff$hunkHint$es extends Translations$diff$hunkHint$en {
  _Translations$diff$hunkHint$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String hiddenCount({required Object n}) => '${n} oculto';
  @override
  String get landing => 'aterrizando';
}

// Path: diff.binary
class _Translations$diff$binary$es extends Translations$diff$binary$en {
  _Translations$diff$binary$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String tooLargeToPreview({required Object size}) =>
      '${size} MB (demasiado grande para previsualizar)';
  @override
  String get unableToLoadBlob => 'No se pudo cargar el blob';
  @override
  String get omittedKindMedia => 'media';
  @override
  String get omittedKindBinary => 'binario';
  @override
  String omittedStub({required Object kind}) => '${kind} · oculto';
}

// Path: diff.media
class _Translations$diff$media$es extends Translations$diff$media$en {
  _Translations$diff$media$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get unableToDecodeImage => 'No se pudo decodificar la imagen';
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
  String get stateAdded => 'añadido';
  @override
  String get stateDeleted => 'eliminado';
  @override
  String get stateModified => 'modificado';
  @override
  String get fallbackFormatName => 'Binario';
}

// Path: filament.severity
class _Translations$filament$severity$es
    extends Translations$filament$severity$en {
  _Translations$filament$severity$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get critical => 'crítico';
  @override
  String get warn => 'aviso';
  @override
  String get info => 'info';
  @override
  String get joint => 'conjunto';
}

// Path: filament.kind
class _Translations$filament$kind$es extends Translations$filament$kind$en {
  _Translations$filament$kind$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get staleValue => 'valor obsoleto';
  @override
  String get temporalShift => 'desfase temporal';
  @override
  String get contextInversion => 'inversión de contexto';
  @override
  String get contradictoryFlow => 'flujo contradictorio';
}

// Path: history.commitLede
class _Translations$history$commitLede$es
    extends Translations$history$commitLede$en {
  _Translations$history$commitLede$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$semantics$es semantics =
      _Translations$history$commitLede$semantics$es._(_root);
}

// Path: history.seismograph
class _Translations$history$seismograph$es
    extends Translations$history$seismograph$en {
  _Translations$history$seismograph$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get rootTrackLabel => '(raíz)';
  @override
  String dirTrackLabel({required Object name}) => '(${name})';
  @override
  String moreLabel({required Object n}) => '+${n} más';
  @override
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} archivo en ${path}/',
        other: '${n} archivos en ${path}/',
      );
  @override
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} archivo más',
        other: '${n} archivos más',
      );
  @override
  String get breadcrumbAll => 'todo';
  @override
  String breadcrumbCurrentFocus({required Object target}) =>
      'Enfoque actual: ${target}';
  @override
  String get breadcrumbViewAllChanges => 'Ver todos los cambios de este commit';
  @override
  String breadcrumbDrillUpTo({required Object target}) => 'Subir a ${target}';
  @override
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
    n,
    one: '${n} archivo  +${adds}  -${dels}',
    other: '${n} archivos  +${adds}  -${dels}',
  );
  @override
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} subdir',
        other: '${n} subdirs',
      );
  @override
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}, ${adds} añadidas, ${dels} eliminadas';
  @override
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
    n,
    one: '${n} archivo, ${adds} añadidas, ${dels} eliminadas',
    other: '${n} archivos, ${adds} añadidas, ${dels} eliminadas',
  );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} hunk',
        other: '${n} hunks',
      );
  @override
  String get largestChangeInView => 'el mayor cambio en esta vista';
  @override
  String get conflictedTag => 'en conflicto';
  @override
  String get dirtyTag => 'sucio';
  @override
  String get drillInTag => 'profundizar';
  @override
  String get changeTypeRenamed => 'renombrado';
  @override
  String get changeTypeCopied => 'copiado';
  @override
  String get changeTypeTypechange => 'cambio de tipo';
  @override
  String get changeTypeConflict => 'conflicto';
  @override
  String get coreFile => 'archivo central';
  @override
  String get staleFile => 'obsoleto';
  @override
  String get filterPathHint => 'filtrar ruta';
  @override
  String get escHint => 'esc';
}

// Path: history.worldline
class _Translations$history$worldline$es
    extends Translations$history$worldline$en {
  _Translations$history$worldline$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get closeWorldline => 'Cerrar línea de mundo';
  @override
  String get dragToOpenWorldline => 'Arrastra para abrir la línea de mundo';
}

// Path: history.contextMenu
class _Translations$history$contextMenu$es
    extends Translations$history$contextMenu$en {
  _Translations$history$contextMenu$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get currentBranchFallback => 'rama actual';
  @override
  String applyCommitOnto({required Object branch}) =>
      'Aplicar los cambios del commit sobre ${branch}';
  @override
  String revertCommitOn({required Object branch}) =>
      'Revertir los cambios del commit en ${branch}';
}

// Path: history.cherryPick
class _Translations$history$cherryPick$es
    extends Translations$history$cherryPick$en {
  _Translations$history$cherryPick$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Cherry-pick en pausa. Termina de resolver los conflictos restantes en la página de Cambios.';
  @override
  String failed({required Object error}) => 'Falló el cherry-pick: ${error}';
  @override
  String pickedResolved({required Object short}) =>
      'Cherry-pick de ${short} (conflictos resueltos)';
  @override
  String picked({required Object short}) => 'Cherry-pick de ${short}';
}

// Path: history.revert
class _Translations$history$revert$es extends Translations$history$revert$en {
  _Translations$history$revert$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Revert en pausa. Termina de resolver los conflictos restantes en la página de Cambios.';
  @override
  String failed({required Object error}) => 'Falló el revert: ${error}';
  @override
  String revertedResolved({required Object short}) =>
      'Revertido ${short} (conflictos resueltos)';
  @override
  String reverted({required Object short}) => 'Revertido ${short}';
}

// Path: history.reflog
class _Translations$history$reflog$es extends Translations$history$reflog$en {
  _Translations$history$reflog$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get createBranchFromHere => 'Crear rama desde aquí…';
  @override
  String get copyCommitHash => 'Copiar hash del commit';
  @override
  String get createBranchDialogTitle =>
      'Crear rama desde una entrada del reflog';
  @override
  String anchorLine({required Object short, required Object summary}) =>
      'Ancla: ${short}  ·  ${summary}';
  @override
  String get branchNameHint => 'nombre de la rama';
  @override
  String get createAction => 'Crear';
  @override
  String createBranchFailed({required Object error}) =>
      'No se pudo crear la rama: ${error}';
  @override
  String branchCreatedAt({required Object name, required Object short}) =>
      'Rama "${name}" creada en ${short}.';
}

// Path: history.rebase
class _Translations$history$rebase$es extends Translations$history$rebase$en {
  _Translations$history$rebase$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String firstCommitCannotBe({required Object action}) =>
      'El primer commit no puede ser ${action}';
  @override
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'Rebasar ${n} commit',
        other: 'Rebasar ${n} commits',
      );
  @override
  String get resetLabel => 'reiniciar';
  @override
  String get dragToReorderHint =>
      'arrastra para reordenar, elige una acción por commit';
  @override
  String get newMessageHint => 'mensaje nuevo';
  @override
  String get runningEllipsis => '…';
  @override
  String get startRebase => 'Iniciar rebase';
}

// Path: history.inFlight
class _Translations$history$inFlight$es
    extends Translations$history$inFlight$en {
  _Translations$history$inFlight$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'EN VUELO';
  @override
  String get deskFallbackLabel => 'Desk';
}

// Path: historySurgery.chrome
class _Translations$historySurgery$chrome$es
    extends Translations$historySurgery$chrome$en {
  _Translations$historySurgery$chrome$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Cirugía de historial';
  @override
  String get alphaBadge => 'alpha';
  @override
  String get dryRunBadge => 'SIMULACIÓN';
}

// Path: historySurgery.select
class _Translations$historySurgery$select$es
    extends Translations$historySurgery$select$en {
  _Translations$historySurgery$select$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get prompt => 'Selecciona los archivos a eliminar del historial';
  @override
  String selectedCount({required Object n}) => '${n} seleccionados';
  @override
  String get searchHint => 'buscar...';
  @override
  String get readingTree => 'leyendo el árbol...';
  @override
  String get continueDisabled => 'selecciona archivos para continuar';
  @override
  String get continueEnabled => 'continuar →';
  @override
  String toPurgeCount({required Object n}) => '${n} para purgar';
  @override
  String get analyzing => 'analizando...';
  @override
  String get riskLow => 'riesgo bajo';
  @override
  String get riskModerate => 'riesgo moderado';
  @override
  String get riskHigh => 'riesgo alto';
  @override
  String get impactCommitsLabel => 'commits';
  @override
  String get impactBranchesLabel => 'ramas';
  @override
  String get impactWorktreesLabel => 'árboles de trabajo';
  @override
  String get impactCouplingLabel => 'acoplamiento';
  @override
  String get impactCouplingIsland => 'isla';
  @override
  String impactCouplingNeighbors({required Object n}) => '${n} vecinos';
  @override
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class _Translations$historySurgery$understand$es
    extends Translations$historySurgery$understand$en {
  _Translations$historySurgery$understand$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get heading => 'Cómo funciona';
  @override
  String get backupTitle => 'Copia de seguridad';
  @override
  String get backupBody =>
      'Cada ref de rama y etiqueta se copia a un espacio de nombres de respaldo antes de cambiar nada. Si algo sale mal, un clic restaura el estado original.';
  @override
  String get rewriteTitle => 'Reescritura';
  @override
  String get rewriteBody =>
      'Cada commit se recorre desde la raíz hasta la punta. Por cada commit que contenga los archivos objetivo, se crea un commit nuevo con esos archivos eliminados del árbol. Las cadenas de padres se remapean para preservar la topología. ';
  @override
  String rewriteSummary({required Object affected, required Object total}) =>
      'Se reescribirán ${affected} de ${total} commits.';
  @override
  String get updateRefsTitle => 'Actualizar refs';
  @override
  String get updateRefsBody =>
      'Los punteros de ramas y etiquetas se mueven a los nuevos SHA de commit. Los objetos antiguos siguen existiendo hasta la recolección de basura. ';
  @override
  String worktreesNeedRecheckout({required Object n}) =>
      'Tus ${n} árbol(es) de trabajo necesitarán un nuevo checkout.';
  @override
  String get noWorktreesAffected => 'No hay árboles de trabajo afectados.';
  @override
  String get forcePushTitle => 'Push forzado';
  @override
  String get forcePushBody =>
      'Tras verificar la purga, eliges qué ramas hacer push forzado. Usa --force-with-lease para que falle de forma segura si alguien más hizo push mientras tanto.';
  @override
  String get plumbingNote =>
      'A diferencia de filter-repo o BFG, esto corre por completo mediante comandos de plumbing de git (cat-file, mktree, commit-tree, update-ref). Sin dependencias externas. El seguimiento de renombres sigue una cadena por archivo — si un archivo se copió y ambas copias se renombraron por separado, verifica el resultado de la purga tras la ejecución.';
  @override
  String get back => '← Atrás';
  @override
  String get continueLabel => 'Entiendo, continuar →';
}

// Path: historySurgery.confirm
class _Translations$historySurgery$confirm$es
    extends Translations$historySurgery$confirm$en {
  _Translations$historySurgery$confirm$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String commitsRewritten({required Object n}) =>
      'Se reescribirán ${n} commits';
  @override
  String get forcePushRequired =>
      'Se requerirá push forzado para las ramas remotas';
  @override
  String worktreesRecheckout({required Object n}) =>
      '${n} árboles de trabajo necesitarán un nuevo checkout';
  @override
  String stashesInvalid({required Object n}) =>
      '${n} stashes podrían volverse inválidos';
  @override
  String get heading => 'Esta operación reescribe el historial de git';
  @override
  String get subheading =>
      'No se puede deshacer automáticamente tras el push forzado.';
  @override
  String typeHint({required Object word}) => 'escribe ${word}';
  @override
  String get goBack => 'Volver';
  @override
  String get begin => 'Comenzar cirugía';
}

// Path: historySurgery.execute
class _Translations$historySurgery$execute$es
    extends Translations$historySurgery$execute$en {
  _Translations$historySurgery$execute$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => 'Preparando...';
  @override
  String get backingUpRefs => 'Respaldando refs...';
  @override
  String get rewritingCommits => 'Reescribiendo commits...';
  @override
  String get updatingRefs => 'Actualizando refs...';
}

// Path: historySurgery.verify
class _Translations$historySurgery$verify$es
    extends Translations$historySurgery$verify$en {
  _Translations$historySurgery$verify$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get complete => 'Cirugía completada';
  @override
  String get failed => 'Cirugía fallida';
  @override
  String get commitsRewrittenLabel => 'Commits reescritos';
  @override
  String get refsUpdatedLabel => 'Refs actualizadas';
  @override
  String get oldHeadLabel => 'HEAD anterior';
  @override
  String get newHeadLabel => 'HEAD nuevo';
  @override
  String get purgeVerifiedLabel => 'Purga verificada';
  @override
  String get purgeClean => 'limpio';
  @override
  String get purgeTracesRemain => 'QUEDAN RASTROS';
  @override
  String get displacedWorktrees => 'Árboles de trabajo desplazados';
  @override
  String get undoSurgery => 'Deshacer cirugía';
  @override
  String get rolledBack => 'Revertido a las refs de respaldo.';
  @override
  String get done => 'Listo';
}

// Path: historySurgery.forcePush
class _Translations$historySurgery$forcePush$es
    extends Translations$historySurgery$forcePush$en {
  _Translations$historySurgery$forcePush$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get pushing => 'haciendo push...';
  @override
  String get forcePushAll => 'Push forzado a todo';
  @override
  String get confirmPush => 'confirmar push';
  @override
  String get cancel => 'cancelar';
}

// Path: onboarding.nav
class _Translations$onboarding$nav$es extends Translations$onboarding$nav$en {
  _Translations$onboarding$nav$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get back => 'Atrás';
  @override
  String get continueLabel => 'Continuar';
  @override
  String get letsGo => 'Vamos';
}

// Path: onboarding.naming
class _Translations$onboarding$naming$es
    extends Translations$onboarding$naming$en {
  _Translations$onboarding$naming$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get question => '¿qué es esto para ti?';
  @override
  String get questionEmphasis => 'esto';
  @override
  String get iAmPrefix => 'Soy ';
  @override
  String get iAmSuffix => ' , tu cliente de Git personal.';
}

// Path: onboarding.theme
class _Translations$onboarding$theme$es
    extends Translations$onboarding$theme$en {
  _Translations$onboarding$theme$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'viste a ${name}.';
  @override
  String get themesHeader => 'TEMAS';
  @override
  String get keybindingsHeader => 'ATAJOS DE TECLADO';
  @override
  String get previewBadge => 'vista previa';
  @override
  String get useDefaults => 'usar valores predeterminados';
}

// Path: onboarding.repo
class _Translations$onboarding$repo$es extends Translations$onboarding$repo$en {
  _Translations$onboarding$repo$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'apunta a ${name} hacia algo.';
  @override
  String get later => 'lo haré más tarde';
  @override
  late final _Translations$onboarding$repo$doors$es doors =
      _Translations$onboarding$repo$doors$es._(_root);
  @override
  late final _Translations$onboarding$repo$cloneForm$es cloneForm =
      _Translations$onboarding$repo$cloneForm$es._(_root);
  @override
  late final _Translations$onboarding$repo$pickers$es pickers =
      _Translations$onboarding$repo$pickers$es._(_root);
  @override
  late final _Translations$onboarding$repo$errors$es errors =
      _Translations$onboarding$repo$errors$es._(_root);
}

// Path: onboarding.preview
class _Translations$onboarding$preview$es
    extends Translations$onboarding$preview$en {
  _Translations$onboarding$preview$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$preview$panels$es panels =
      _Translations$onboarding$preview$panels$es._(_root);
  @override
  late final _Translations$onboarding$preview$sidebar$es sidebar =
      _Translations$onboarding$preview$sidebar$es._(_root);
  @override
  late final _Translations$onboarding$preview$changes$es changes =
      _Translations$onboarding$preview$changes$es._(_root);
  @override
  late final _Translations$onboarding$preview$history$es history =
      _Translations$onboarding$preview$history$es._(_root);
  @override
  late final _Translations$onboarding$preview$branches$es branches =
      _Translations$onboarding$preview$branches$es._(_root);
  @override
  late final _Translations$onboarding$preview$diff$es diff =
      _Translations$onboarding$preview$diff$es._(_root);
}

// Path: orrery.header
class _Translations$orrery$header$es extends Translations$orrery$header$en {
  _Translations$orrery$header$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Orrery';
  @override
  String get modeScrub => 'Recorrer';
  @override
  String get modeCompare => 'Comparar';
  @override
  String get lodModules => 'Módulos';
  @override
  String get lodFiles => 'Archivos';
}

// Path: orrery.status
class _Translations$orrery$status$es extends Translations$orrery$status$en {
  _Translations$orrery$status$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'Trazando el manifold a través del historial…';
  @override
  String get loadError => 'No se pudo leer el historial de este repo.';
  @override
  String get notEnoughHistory =>
      'Aún no hay suficiente historial para trazar una trayectoria.';
  @override
  String get notEnoughHistoryDetail =>
      'El Orrery necesita unos cuantos commits para graficar.';
}

// Path: orrery.legend
class _Translations$orrery$legend$es extends Translations$orrery$legend$en {
  _Translations$orrery$legend$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get central => 'central';
  @override
  String get peripheral => 'periférico';
}

// Path: orrery.node
class _Translations$orrery$node$es extends Translations$orrery$node$en {
  _Translations$orrery$node$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get module => 'módulo';
  @override
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · ${n} archivos';
  @override
  String fileFallback({required Object id}) => 'archivo #${id}';
  @override
  String nodeFallback({required Object id}) => 'nodo #${id}';
  @override
  String get rootModule => '(raíz)';
}

// Path: orrery.milestone
class _Translations$orrery$milestone$es
    extends Translations$orrery$milestone$en {
  _Translations$orrery$milestone$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get genesis => 'génesis';
  @override
  String get now => 'ahora';
  @override
  String get reorganized => 'reorganizado';
  @override
  String becameArchetype({required Object archetype}) =>
      'se volvió ${archetype}';
  @override
  String get snapshot => 'instantánea';
}

// Path: orrery.structure
class _Translations$orrery$structure$es
    extends Translations$orrery$structure$en {
  _Translations$orrery$structure$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get forming => 'formándose…';
  @override
  String get canonical => 'canónico';
  @override
  String get connectivity => 'conectividad';
  @override
  String get rigidity => 'rigidez';
  @override
  String get entropy => 'entropía';
}

// Path: orrery.rail
class _Translations$orrery$rail$es extends Translations$orrery$rail$en {
  _Translations$orrery$rail$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get structureLabel => 'ESTRUCTURA';
  @override
  String get fieldLabel => 'CAMPO';
  @override
  String get findingsLabel => 'HALLAZGOS';
  @override
  String get selectedLabel => 'SELECCIONADO';
  @override
  String get noFindings =>
      'No se detectaron eventos estructurales en este historial.';
}

// Path: orrery.selection
class _Translations$orrery$selection$es
    extends Translations$orrery$selection$en {
  _Translations$orrery$selection$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get notPresent => 'No presente en este punto del historial.';
  @override
  String get roleCentral =>
      'Central en acoplamiento — los cambios aquí se propagan por todo el sistema.';
  @override
  String get rolePeripheral =>
      'Periférico — poco acoplado, cambia sobre todo por su cuenta.';
  @override
  String get roleMid => 'Estructura intermedia — moderadamente acoplado.';
  @override
  String get driftOutward => ' Derivando hacia afuera — desacoplándose.';
  @override
  String get driftInward => ' Derivando hacia adentro — integrándose.';
  @override
  String get driftHolding => ' Manteniendo su posición.';
}

// Path: orrery.findingKind
class _Translations$orrery$findingKind$es
    extends Translations$orrery$findingKind$en {
  _Translations$orrery$findingKind$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get hub => 'HUB';
  @override
  String get driftOut => 'DERIVANDO AFUERA';
  @override
  String get driftIn => 'DERIVANDO ADENTRO';
  @override
  String get tangle => 'ENREDÁNDOSE';
  @override
  String get clarify => 'ACLARÁNDOSE';
  @override
  String get regime => 'REORG';
  @override
  String get thrash => 'OSCILANDO';
  @override
  String get reshuffle => 'REBARAJEO';
  @override
  String get forecast => 'PRONÓSTICO';
}

// Path: orrery.findings
class _Translations$orrery$findings$es extends Translations$orrery$findings$en {
  _Translations$orrery$findings$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get forecastSplit =>
      'La conectividad ha ido cayendo y está cerca de su mínimo — si se mantiene, el código va camino a partirse en mitades poco acopladas. Decide ahora si esa es la intención.';
  @override
  String get forecastConsolidate =>
      'La conectividad ha ido subiendo hacia su pico — si se mantiene, el código se está consolidando en una masa fuertemente acoplada. Atento a que se endurezca en un monolito.';
  @override
  String thrash({required Object name}) =>
      '${name} se reorganiza una y otra vez de un lado a otro — mucha agitación estructural, poco movimiento neto. Estabiliza su acoplamiento o deja de tocarlo.';
  @override
  String get reshuffle =>
      'Este commit parecía rutinario pero cambió en silencio qué archivos son centrales — la forma general se mantuvo mientras la estructura se rebarajeaba por debajo. Revísalo con cuidado.';
  @override
  String hub({required Object name}) =>
      '${name} está en el núcleo estructural — el sistema se reorganiza a su alrededor. Trata los cambios aquí como de alto radio de impacto.';
  @override
  String driftOut({required Object name}) =>
      '${name} ha derivado del núcleo hacia el borde — se está desacoplando del sistema. O lo están retirando, o se está pudriendo en silencio.';
  @override
  String driftIn({required Object name}) =>
      '${name} ha migrado hacia el núcleo — se está volviendo estructural. Asegúrate de que esté bien probado antes de que más cosas dependan de él.';
  @override
  String get regime =>
      'El código se reorganizó bruscamente aquí — su conectividad dio un salto. Revisa qué se separó o se fusionó.';
  @override
  String get tangleTrend =>
      'A lo largo de su historia el código ha tendido hacia una estructura más enredada — su conectividad se vuelve más densa y menos modular.';
  @override
  String get clarifyTrend =>
      'A lo largo de su historia el código ha tendido hacia una estructura más limpia — se está separando en módulos más claros.';
}

// Path: orrery.anchor
class _Translations$orrery$anchor$es extends Translations$orrery$anchor$en {
  _Translations$orrery$anchor$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get core => 'núcleo';
  @override
  String get drift => 'deriva';
  @override
  String get trend => 'tendencia';
  @override
  String get thrash => 'oscilación';
}

// Path: orrery.compare
class _Translations$orrery$compare$es extends Translations$orrery$compare$en {
  _Translations$orrery$compare$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'A → B';
  @override
  String get change => 'CAMBIO';
  @override
  String get movers => 'EN MOVIMIENTO';
  @override
  String get noMovers => 'Ningún archivo se movió entre estos fotogramas.';
  @override
  String get badgeA => 'A';
  @override
  String get badgeB => 'B';
  @override
  String get deltaFiles => 'archivos';
  @override
  String get deltaConnectivity => 'conectividad';
  @override
  String get deltaRigidity => 'rigidez';
  @override
  String get deltaEntropy => 'entropía';
  @override
  String get wayOutward => 'hacia afuera';
  @override
  String get wayInward => 'hacia adentro';
  @override
  String get wayShifted => 'desplazado';
}

// Path: palette.prefixes
class _Translations$palette$prefixes$es
    extends Translations$palette$prefixes$en {
  _Translations$palette$prefixes$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get askHint => 'preguntar: [pregunta]';
  @override
  String get nearHint => 'cerca: [archivo]';
  @override
  String get whoHint => 'quién: [archivo]';
  @override
  String get logHint => 'log: [mensaje]';
  @override
  String get runHint => 'ejecutar: [herramienta]';
  @override
  String askLabel({required Object name, required Object body}) =>
      'Preguntar a ${name}: ${body}';
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
  }) => '${path} · ${count} revisores · ${touches} toques';
  @override
  String whoTouchesLabel({required Object name, required Object touches}) =>
      '${name} — ${touches} toques';
  @override
  String whoTouchesSubtitle({required Object path}) =>
      '${path} · sin revisores registrados';
}

// Path: palette.chips
class _Translations$palette$chips$es extends Translations$palette$chips$en {
  _Translations$palette$chips$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get ai => 'IA';
  @override
  String get near => 'CERCA';
  @override
  String get who => 'QUIÉN';
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
  String get hot => 'HOT';
  @override
  String get key => 'CLAVE';
  @override
  String get web => 'WEB';
  @override
  String get sys => 'SIS';
  @override
  String get clip => 'CLIP';
  @override
  String get sync => 'SYNC';
  @override
  String get force => 'FORZAR';
  @override
  String get pr => 'PR';
  @override
  String get draft => 'BORRADOR';
  @override
  String get undo => 'DESHACER';
  @override
  String get thm => 'TEMA';
  @override
  String get ver => 'VER';
  @override
  String get desk => 'ESCR';
  @override
  String get det => 'DET';
  @override
  String get main => 'MAIN';
  @override
  String get head => 'HEAD';
  @override
  String get gone => 'IDA';
  @override
  String get remote => 'REMOTO';
  @override
  String get local => 'LOCAL';
  @override
  String get an => 'AN';
  @override
  String get lw => 'LW';
}

// Path: palette.predictive
class _Translations$palette$predictive$es
    extends Translations$palette$predictive$en {
  _Translations$palette$predictive$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String momentumSuffix({required Object percent}) => '${percent}% de impulso';
}

// Path: palette.topTouched
class _Translations$palette$topTouched$es
    extends Translations$palette$topTouched$en {
  _Translations$palette$topTouched$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object count, required Object path}) =>
      '${count} toques · ${path}';
}

// Path: palette.coherence
class _Translations$palette$coherence$es
    extends Translations$palette$coherence$en {
  _Translations$palette$coherence$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String label({required Object percent}) => 'Coherencia en stage: ${percent}%';
  @override
  String subtitle({required Object count}) => '${count} archivos';
}

// Path: palette.keystone
class _Translations$palette$keystone$es
    extends Translations$palette$keystone$en {
  _Translations$palette$keystone$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object path, required Object score}) =>
      '${path} · clave ${score}';
}

// Path: palette.repoSub
class _Translations$palette$repoSub$es extends Translations$palette$repoSub$en {
  _Translations$palette$repoSub$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String changes({required Object name}) => 'Cambios en ${name}';
  @override
  String history({required Object name}) => 'Historial en ${name}';
  @override
  String branches({required Object name}) => 'Ramas en ${name}';
  @override
  String terminal({required Object name}) => 'Terminal en ${name}';
  @override
  String generateCommit({required Object name}) => 'Generar commit · ${name}';
  @override
  String reviewChanges({required Object name}) => 'Revisar cambios en ${name}';
  @override
  String muse({required Object name}) => 'Muse en ${name}';
}

// Path: palette.desks
class _Translations$palette$desks$es extends Translations$palette$desks$en {
  _Translations$palette$desks$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get mainWorktree => 'árbol de trabajo principal';
  @override
  String get detached => 'desacoplado';
  @override
  String dirty({required Object count}) => '${count} sucios';
}

// Path: palette.actions
class _Translations$palette$actions$es extends Translations$palette$actions$en {
  _Translations$palette$actions$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get openInBrowser => 'Abrir en el navegador';
  @override
  String get terminal => 'Terminal';
  @override
  String get revealInFiles => 'Mostrar en el explorador';
  @override
  String get copyPath => 'Copiar ruta';
  @override
  String get copyBranch => 'Copiar rama';
}

// Path: palette.tools
class _Translations$palette$tools$es extends Translations$palette$tools$en {
  _Translations$palette$tools$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String launch({required Object label}) => 'Lanzar ${label}';
}

// Path: palette.gitCommands
class _Translations$palette$gitCommands$es
    extends Translations$palette$gitCommands$en {
  _Translations$palette$gitCommands$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get fetch => 'Fetch';
  @override
  String get pull => 'Pull';
  @override
  String pullBehind({required Object count}) => '${count} por detrás';
  @override
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';
  @override
  String get push => 'Push';
  @override
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} commit',
        other: '${n} commits',
      );
  @override
  String pushCommitsUpstream({
    required Object commits,
    required Object upstream,
  }) => '${commits} a ${upstream}';
  @override
  String get forcePush => 'Push forzado';
  @override
  String forcePushNoUpstream({required Object branch}) =>
      'No se puede hacer push forzado: no hay upstream configurado para ${branch}.';
  @override
  String get commit => 'Commit';
  @override
  String get stageAll => 'Poner todo en stage';
  @override
  String get unstageAll => 'Quitar todo del stage';
  @override
  String get discardAll => 'Descartar todo';
  @override
  String get createBranch => 'Crear rama';
  @override
  String get deleteBranch => 'Eliminar rama';
  @override
  String get renameBranch => 'Renombrar rama';
  @override
  String get stash => 'Stash';
  @override
  String get stashPop => 'Stash pop';
  @override
  String get stashApply => 'Stash apply';
  @override
  String get stashDrop => 'Stash drop';
  @override
  String get createTag => 'Crear etiqueta';
  @override
  String get cherryPick => 'Cherry-pick';
  @override
  String get revert => 'Revertir';
  @override
  String get stashConflictMessage =>
      'Stash aplicado con conflictos. Resuélvelos en la página de Cambios.';
}

// Path: palette.pr
class _Translations$palette$pr$es extends Translations$palette$pr$en {
  _Translations$palette$pr$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get create => 'Crear PR';
  @override
  String get merge => 'Merge del PR';
  @override
  String get markReady => 'Marcar PR como listo';
}

// Path: palette.ai
class _Translations$palette$ai$es extends Translations$palette$ai$en {
  _Translations$palette$ai$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get generateCommit => 'Generar commit';
  @override
  String get reviewChanges => 'Revisar cambios';
  @override
  String get runMuse => 'Invocar Muse';
  @override
  String debugRepo({required Object name}) => 'Depurar ${name}';
  @override
  String get describeSymptom => 'describe un síntoma';
  @override
  String viewResult({required Object kind}) => 'Ver ${kind}';
  @override
  String get unseenResult => 'resultado sin ver';
  @override
  String runningResult({required Object kind}) => 'IA: ${kind}…';
  @override
  String get running => 'en curso';
  @override
  String get kindCommitMessage => 'Mensaje de commit';
  @override
  String get kindCodeReview => 'Revisión de código';
  @override
  String get kindMuseResult => 'Resultado de Muse';
  @override
  String get kindPresentation => 'Presentación';
  @override
  String get kindDebugResult => 'Resultado de depuración';
}

// Path: palette.undo
class _Translations$palette$undo$es extends Translations$palette$undo$en {
  _Translations$palette$undo$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String cancel({required Object label}) => 'Cancelar: ${label}';
}

// Path: palette.navigation
class _Translations$palette$navigation$es
    extends Translations$palette$navigation$en {
  _Translations$palette$navigation$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get changes => 'Cambios';
  @override
  String get history => 'Historial';
  @override
  String get branches => 'Ramas';
  @override
  String get xray => 'X-Ray';
  @override
  String get settings => 'Ajustes';
  @override
  String get refresh => 'Actualizar';
}

// Path: palette.settings
class _Translations$palette$settings$es
    extends Translations$palette$settings$en {
  _Translations$palette$settings$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get reduceMotion => 'Reducir movimiento';
  @override
  String get animateLogoUnfocused => 'Animar el logo sin foco';
  @override
  String get instantBlameHover => 'Blame instantáneo al pasar el cursor';
  @override
  String get autoSelectChanges => 'Autoseleccionar cambios';
  @override
  String get fetchOnlineIssues => 'Traer issues en línea';
  @override
  String get rememberWip => 'Recordar trabajo en curso';
  @override
  String get hideAiFeatures => 'Ocultar funciones de IA';
  @override
  String get crashReporting => 'Reporte de fallos';
  @override
  String get aiReadOnly => 'IA de solo lectura';
  @override
  String get stashCabinetExpanded => 'Gabinete de stash expandido';
  @override
  String get fileSortInverted => 'Orden de archivos invertido';
}

// Path: palette.info
class _Translations$palette$info$es extends Translations$palette$info$en {
  _Translations$palette$info$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class _Translations$palette$debug$es extends Translations$palette$debug$en {
  _Translations$palette$debug$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get engineStatus => 'Estado del motor';
  @override
  String get engineStatusSubtitle => 'Diagnóstico del motor espectral LogosGit';
  @override
  String get fileCoupling => 'Acoplamiento de archivos';
  @override
  String get fileCouplingSubtitle =>
      'Vecinos de co-cambio más cercanos para los archivos en stage';
  @override
  String get themeSpecimen => 'Muestra del tema';
  @override
  String get themeSpecimenSubtitle =>
      'Todos los colores, iconos, niveles de texto y geometría';
}

// Path: palette.dev
class _Translations$palette$dev$es extends Translations$palette$dev$en {
  _Translations$palette$dev$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get testMergeEditor => 'Probar el editor de merge';
  @override
  String get testHistorySurgery => 'Probar la cirugía de historial';
  @override
  String get back => 'atrás';
  @override
  String get cancel => 'cancelar';
  @override
  String get buildingConflicts =>
      'construyendo conflictos de prueba desde el historial…';
}

// Path: palette.historySurgery
class _Translations$palette$historySurgery$es
    extends Translations$palette$historySurgery$en {
  _Translations$palette$historySurgery$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Cirugía de historial';
  @override
  String get subtitle =>
      'Reescribe el historial para eliminar archivos de forma permanente';
}

// Path: palette.orrery
class _Translations$palette$orrery$es extends Translations$palette$orrery$en {
  _Translations$palette$orrery$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Orrery';
  @override
  String get subtitle =>
      'Recorre la historia estructural del repo a través del manifold';
}

// Path: palette.command
class _Translations$palette$command$es extends Translations$palette$command$en {
  _Translations$palette$command$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String complete({required Object label}) => '${label} completado';
  @override
  String failed({required Object label, required Object message}) =>
      '${label} falló: ${message}';
  @override
  String get copy => 'Copiar';
}

// Path: palette.search
class _Translations$palette$search$es extends Translations$palette$search$en {
  _Translations$palette$search$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get hintDefault => 'buscar en todo...';
  @override
  String get hintElevated => 'elevado — todas las acciones';
  @override
  String get emptyTypeToSearch => 'escribe para buscar';
  @override
  String get emptyNoResults => 'sin resultados';
}

// Path: palette.wick
class _Translations$palette$wick$es extends Translations$palette$wick$en {
  _Translations$palette$wick$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'wick';
  @override
  String get coupledFallback => 'acoplado';
}

// Path: palette.gitCache
class _Translations$palette$gitCache$es
    extends Translations$palette$gitCache$en {
  _Translations$palette$gitCache$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'actual';
  @override
  String get staged => 'en stage';
  @override
  String get modified => 'modificado';
}

// Path: releaseNotes.about
class _Translations$releaseNotes$about$es
    extends Translations$releaseNotes$about$en {
  _Translations$releaseNotes$about$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$releaseNotes$about$whyFlutter$es whyFlutter =
      _Translations$releaseNotes$about$whyFlutter$es._(_root);
  @override
  late final _Translations$releaseNotes$about$spectralEngine$es spectralEngine =
      _Translations$releaseNotes$about$spectralEngine$es._(_root);
  @override
  late final _Translations$releaseNotes$about$whereGoing$es whereGoing =
      _Translations$releaseNotes$about$whereGoing$es._(_root);
}

// Path: releaseNotes.legal
class _Translations$releaseNotes$legal$es
    extends Translations$releaseNotes$legal$en {
  _Translations$releaseNotes$legal$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get copyright => '© 2026 Woflo Labs';
  @override
  String get license =>
      'GPL-3.0-or-later · núcleo de investigación community-source WLCSL · sin garantía';
}

// Path: repoSummary.backbone
class _Translations$repoSummary$backbone$es
    extends Translations$repoSummary$backbone$en {
  _Translations$repoSummary$backbone$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}` (${lines}) — ${region}';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} línea',
        other: '${n} líneas',
      );
  @override
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class _Translations$repoSummary$glance$es
    extends Translations$repoSummary$glance$en {
  _Translations$repoSummary$glance$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} archivo.',
        other: '${n} archivos.',
      );
  @override
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} línea (${bytes}).',
        other: '${n} líneas (${bytes}).',
      );
  @override
  String roles({required Object parts}) => 'Roles — ${parts}.';
  @override
  String showingNofM({required Object active, required Object total}) =>
      'Mostrando ${active} de ${total} archivos, ordenados por centralidad estructural.';
}

// Path: repoSummary.heading
class _Translations$repoSummary$heading$es
    extends Translations$repoSummary$heading$en {
  _Translations$repoSummary$heading$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get atAGlance => 'De un vistazo';
  @override
  String get core => 'Núcleo';
  @override
  String get gettingStarted => 'Primeros pasos';
  @override
  String get regions => 'Regiones';
  @override
  String get shape => 'Forma';
}

// Path: repoSummary.pitch
class _Translations$repoSummary$pitch$es
    extends Translations$repoSummary$pitch$en {
  _Translations$repoSummary$pitch$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String empty({required Object detail}) =>
      'Un repositorio sin archivos de texto legibles${detail}.';
  @override
  String emptyBinary({required Object n}) => '${n} binario';
  @override
  String emptyUnreadable({required Object n}) => '${n} ilegible';
  @override
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'Un repositorio de ${n} archivo activo.',
        other: 'Un repositorio de ${n} archivos activos.',
      );
  @override
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'Un repositorio de ${n} archivo activo — ${regions}.',
        other: 'Un repositorio de ${n} archivos activos — ${regions}.',
      );
}

// Path: repoSummary.region
class _Translations$repoSummary$region$es
    extends Translations$repoSummary$region$en {
  _Translations$repoSummary$region$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String bodyCommonDir({required Object dir}) => 'Todo bajo `${dir}`.';
  @override
  String get bodyCommonDirSeparator => ' ';
  @override
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '1 central',
        other: '${n} centrales',
      );
  @override
  String get bodyCoreSeparator => ', ';
  @override
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'Un archivo',
        other: '${n} archivos',
      );
  @override
  String connectsTo({required Object linked}) => 'Se conecta con: ${linked}.';
  @override
  String get filesLabel => 'Archivos:';
}

// Path: repoSummary.shape
class _Translations$repoSummary$shape$es
    extends Translations$repoSummary$shape$en {
  _Translations$repoSummary$shape$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get bulk =>
      'Código densamente interconectado: la mayoría de los archivos participan en un gran vecindario de cambios compartidos.';
  @override
  String get crystalline =>
      'Código en forma de retícula: acoplamiento uniforme y regular entre archivos con estructura local predecible.';
  @override
  String get goe =>
      'Código ricamente interconectado: los acoplamientos se reparten entre archivos sin una espina dominante.';
  @override
  String get modular =>
      'Código modular: varias regiones cohesivas con acoplamiento cruzado limitado. Trabajar en una región rara vez perturba otra.';
  @override
  String get poisson =>
      'Código débilmente acoplado: los archivos evolucionan mayormente por su cuenta, con cambios compartidos ocasionales.';
  @override
  String get tree =>
      'Código en forma de árbol: una espina dominante con ramas dependientes. El cambio suele propagarse hacia afuera desde el núcleo.';
}

// Path: settings.language
class _Translations$settings$language$es
    extends Translations$settings$language$en {
  _Translations$settings$language$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Idioma';
  @override
  String get summary =>
      'Idioma de la interfaz de esta app. La salida de git, los logs y los diagnósticos se mantienen en inglés para que los reportes de bugs sigan siendo buscables.';
  @override
  String get label => 'IDIOMA DE PANTALLA';
  @override
  String get systemDefault => 'Predeterminado del sistema';
  @override
  String systemDefaultDetail({required Object resolved}) =>
      'Sigue el idioma de tu SO (${resolved})';
  @override
  String get disclosureSource =>
      'Idioma de origen, escrito por los desarrolladores.';
  @override
  String disclosureAi({required Object model}) =>
      'Traducido a máquina por ${model}, aún sin revisión humana. Se agradecen las correcciones.';
  @override
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) => 'Traducido a máquina por ${model}. ${percent}% revisado por humanos.';
  @override
  String get disclosureHuman =>
      'Traducción humana, mantenida por la comunidad.';
  @override
  String reviewedBy({required Object names}) => 'Revisado por ${names}.';
}

// Path: settings.sectionLabels
class _Translations$settings$sectionLabels$es
    extends Translations$settings$sectionLabels$en {
  _Translations$settings$sectionLabels$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get preferences => 'Preferencias';
  @override
  String get shortcuts => 'Atajos';
  @override
  String get behaviour => 'Comportamiento';
  @override
  String get aiProviders => 'Proveedores de IA';
  @override
  String get modelSlots => 'Ranuras de modelo';
  @override
  String get tools => 'Herramientas';
  @override
  String get diagnostics => 'Diagnóstico';
  @override
  String get offenders => 'Infractores';
  @override
  String get release => 'Versión';
}

// Path: settings.errors
class _Translations$settings$errors$es extends Translations$settings$errors$en {
  _Translations$settings$errors$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get saveGuardrailProfile =>
      'No se pudo guardar el perfil de barandillas.';
  @override
  String get saveRetentionPolicy =>
      'No se pudo guardar la política de retención.';
  @override
  String get saveUpdateChannel =>
      'No se pudo guardar el canal de actualización.';
  @override
  String get saveModelSelection =>
      'No se pudo guardar la selección de modelo de IA.';
  @override
  String get saveModelAlias => 'No se pudo guardar el alias del modelo.';
  @override
  String get saveCommitMessageModelSlot =>
      'No se pudo guardar la ranura del modelo de mensaje de commit.';
  @override
  String get saveReviewModelSlot =>
      'No se pudo guardar la ranura del modelo de revisión.';
  @override
  String get saveCommitMessageCustomPrompt =>
      'No se pudo guardar el prompt personalizado de mensaje de commit.';
  @override
  String get saveReviewGuide => 'No se pudo guardar la guía de revisión.';
  @override
  String get saveMuseNotes => 'No se pudieron guardar las notas de la muse.';
  @override
  String get saveReviewDoubleCheck =>
      'No se pudo guardar el modo de doble verificación de la revisión.';
  @override
  String get saveApiPiggybackCli =>
      'No se pudo guardar la CLI de piggyback de API.';
  @override
  String get saveCliTimeout => 'No se pudo guardar el tiempo límite de la CLI.';
  @override
  String get stopAllCli =>
      'No se pudieron detener las sesiones de CLI en curso.';
  @override
  String clearLocalData({required Object error}) =>
      'No se pudieron limpiar los datos locales: ${error}';
}

// Path: settings.promptStatus
class _Translations$settings$promptStatus$es
    extends Translations$settings$promptStatus$en {
  _Translations$settings$promptStatus$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get editing => 'Editando';
  @override
  String get saving => 'Guardando';
  @override
  String get saveFailed => 'Falló el guardado';
}

// Path: settings.clearData
class _Translations$settings$clearData$es
    extends Translations$settings$clearData$en {
  _Translations$settings$clearData$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => 'Limpiar datos locales';
  @override
  String get clear => 'Limpiar';
  @override
  String get confirmDiagnostics =>
      '¿Limpiar las muestras de diagnóstico locales y los tiempos de rendimiento?';
  @override
  String get confirmAudit =>
      '¿Limpiar los registros de metadatos de auditoría de IA locales?';
  @override
  String get confirmAll =>
      '¿Limpiar todas las muestras de diagnóstico locales y los registros de metadatos de auditoría de IA?';
  @override
  String get confirmWipeAll =>
      '¿Borrar todos los datos locales de la app —incluida la lista de repos recientes— y salir? Tus repos de git reales en disco no se tocan.';
  @override
  String get confirmReset =>
      '¿Restablecer los datos locales de la app y salir?\n\nSe limpian los ajustes, el tema, el onboarding, las preferencias de IA, la telemetría y las cachés de engram. Tu lista de repos recientes se conserva.';
}

// Path: settings.guardrailMacro
class _Translations$settings$guardrailMacro$es
    extends Translations$settings$guardrailMacro$en {
  _Translations$settings$guardrailMacro$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'relajado';
  @override
  String get balanced => 'equilibrado';
  @override
  String get strict => 'estricto';
  @override
  String get paranoid => 'paranoico';
}

// Path: settings.guardrails
class _Translations$settings$guardrails$es
    extends Translations$settings$guardrails$en {
  _Translations$settings$guardrails$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Barandillas';
  @override
  String get summary =>
      'Qué tan atenta es la automatización en toda la experiencia.';
}

// Path: settings.appearance
class _Translations$settings$appearance$es
    extends Translations$settings$appearance$en {
  _Translations$settings$appearance$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Apariencia';
  @override
  String get summary => 'Ánimo y atmósfera global de la interfaz.';
}

// Path: settings.retention
class _Translations$settings$retention$es
    extends Translations$settings$retention$en {
  _Translations$settings$retention$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Retención de datos locales';
  @override
  String get summaryDiagnostics => 'Política de retención de diagnósticos.';
  @override
  String get summaryWithAudit =>
      'Política de retención de diagnósticos y de auditoría de IA.';
  @override
  String get unitDays => 'días';
  @override
  String get unitMb => 'MB';
  @override
  String get includesNote =>
      'Incluye diagnósticos, tiempos de rendimiento y metadatos.';
}

// Path: settings.navigation
class _Translations$settings$navigation$es
    extends Translations$settings$navigation$en {
  _Translations$settings$navigation$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Navegación y dinámicas';
  @override
  String get summaryShortcuts => 'Atajos y comportamiento de la interfaz.';
  @override
  String get summaryWithAi =>
      'Atajos, comportamiento de la interfaz y enrutamiento de IA.';
}

// Path: settings.behaviour
class _Translations$settings$behaviour$es
    extends Translations$settings$behaviour$en {
  _Translations$settings$behaviour$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Dinámicas de comportamiento';
}

// Path: settings.retentionClear
class _Translations$settings$retentionClear$es
    extends Translations$settings$retentionClear$en {
  _Translations$settings$retentionClear$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get diag => 'Diag';
  @override
  String get audit => 'Auditoría';
  @override
  String get all => 'Todo';
  @override
  String get clearsHint => '<-- limpia';
}

// Path: settings.channels
class _Translations$settings$channels$es
    extends Translations$settings$channels$en {
  _Translations$settings$channels$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get stable => 'ESTABLE';
  @override
  String get beta => 'BETA';
  @override
  String get dev => 'DEV';
}

// Path: settings.pollResult
class _Translations$settings$pollResult$es
    extends Translations$settings$pollResult$en {
  _Translations$settings$pollResult$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get upToDate => 'al día';
  @override
  String updateAvailable({required Object version}) => '${version} disponible';
  @override
  String get notConfigured => 'sin servidor de actualización';
  @override
  String notFound({required Object channel}) => 'sin versiones ${channel}';
  @override
  String get unreachable => 'inalcanzable';
  @override
  String get badManifest => 'manifiesto inválido';
}

// Path: settings.keybindingProfile
class _Translations$settings$keybindingProfile$es
    extends Translations$settings$keybindingProfile$en {
  _Translations$settings$keybindingProfile$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Perfil de atajos';
  @override
  String get porcelain => 'Porcelain';
  @override
  String get numeric => 'Numérico';
  @override
  String get porcelainDescription => 'Atajos encadenados (G y luego C, H, B…).';
  @override
  String get numericDescription => 'Atajos numéricos de una tecla (1, 2, 3…).';
}

// Path: settings.apiKeys
class _Translations$settings$apiKeys$es
    extends Translations$settings$apiKeys$en {
  _Translations$settings$apiKeys$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get keyHintDefault => 'clave de api';
  @override
  String get endpointHint => 'endpoint';
  @override
  String get test => 'Probar';
  @override
  String get hide => 'Ocultar';
  @override
  String get show => 'Mostrar';
}

// Path: settings.shortcuts
class _Translations$settings$shortcuts$es
    extends Translations$settings$shortcuts$en {
  _Translations$settings$shortcuts$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get navigate => 'navegar';
  @override
  String get staging => 'stage';
  @override
  String get branchesPrs => 'ramas y PRs';
  @override
  String get modifiers => 'modificadores';
  @override
  String get changes => 'Cambios';
  @override
  String get history => 'Historial';
  @override
  String get branches => 'Ramas';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Cambiar (siempre)';
  @override
  String get search => 'Buscar';
  @override
  String get dismiss => 'Descartar';
  @override
  String get refresh => 'Actualizar';
  @override
  String get shortcuts => 'Atajos';
  @override
  String get nextChange => 'Cambio siguiente';
  @override
  String get prevChange => 'Cambio anterior';
  @override
  String get toggleLine => 'Alternar línea';
  @override
  String get toggleHunk => 'Alternar hunk';
  @override
  String get toggleFile => 'Alternar archivo';
  @override
  String get pinContext => 'Fijar contexto';
  @override
  String get commit => 'Commit';
  @override
  String get acceptHint => 'Aceptar sugerencia';
  @override
  String get undo => 'Deshacer';
  @override
  String get navigateRow => 'Navegar';
  @override
  String get expand => 'Expandir';
  @override
  String get checkout => 'Checkout';
  @override
  String get approve => 'Aprobar';
  @override
  String get requestChanges => 'Solicitar cambios';
  @override
  String get selectRange => 'Seleccionar rango';
  @override
  String get extendedMenu => 'Menú extendido';
}

// Path: settings.toggles
class _Translations$settings$toggles$es
    extends Translations$settings$toggles$en {
  _Translations$settings$toggles$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get aiReadOnlyLabel => 'Modo de IA de solo lectura';
  @override
  String get aiReadOnlyDescription =>
      'Evita que la IA escriba o ponga cambios en stage automáticamente.';
  @override
  String get logoMotionLabel => 'El logo se anima cuando cambias de pestaña';
  @override
  String get logoMotionDescriptionEnabled =>
      'Está diseñado para ser eficiente, no le hieras los sentimientos';
  @override
  String get logoMotionDescriptionDisabled => ':(';
  @override
  String get rememberWipLabel => 'Recordar el trabajo en curso';
  @override
  String get rememberWipDescription =>
      'Conserva tus borradores de commit y tu selección de archivos entre sesiones.';
  @override
  String get stashCabinetLabel => 'El gabinete de stash arranca expandido';
  @override
  String get stashCabinetDescription =>
      'Muestra el cajón del archivador abierto por defecto cuando un repo tiene estantes.';
  @override
  String get instantBlameLabel => 'Blame instantáneo al pasar el cursor';
  @override
  String get instantBlameDescription =>
      'Omite el retardo de 180ms antes de que la info de blame se muestre en una línea del diff.';
  @override
  String get autoSelectLabel => 'Autoseleccionar cambios nuevos';
  @override
  String get autoSelectDescription =>
      'Los archivos recién rastreados o modificados se añaden a la selección de commit automáticamente.';
  @override
  String get changeIdLabel => 'Escribir cabeceras change-id';
  @override
  String get changeIdDescription =>
      'Añade a los commits nuevos una cabecera de identidad change-id (la convención de Jujutsu, GitButler y Gerrit). Cada commit se reescribe una vez justo después de crearse.';
  @override
  String get fetchIssuesLabel => 'Traer issues en línea al cargar las ramas';
  @override
  String get fetchIssuesDescription =>
      'Trae los detalles de PRs e issues de tu proveedor de git en segundo plano cuando se abre la página de ramas.';
  @override
  String get hateAiLabel => 'Odio la IA';
  @override
  String get hateAiDescription =>
      'Destierra todas las funciones respaldadas por LLM. Logos sigue funcionando porque es pura matemática espectral.';
}

// Path: settings.diffDiffability
class _Translations$settings$diffDiffability$es
    extends Translations$settings$diffDiffability$en {
  _Translations$settings$diffDiffability$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'diff-eabilidad del diff';
}

// Path: settings.modelSlots
class _Translations$settings$modelSlots$es
    extends Translations$settings$modelSlots$en {
  _Translations$settings$modelSlots$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get loadingProviders => 'Cargando proveedores...';
  @override
  String get refreshingProviders =>
      'Actualizando el diagnóstico de proveedores...';
  @override
  String get routeDescription =>
      'Renombra y enruta configuraciones a cualquier modelo de proveedor detectado.';
  @override
  String get loadingCategories => 'Cargando categorías de modelo...';
  @override
  String get noOptions =>
      'Aún no hay opciones de modelo disponibles. Detecta primero una CLI de IA local compatible.';
  @override
  String get slotsAppearWhenAvailable =>
      'Los ajustes de ranuras de modelo aparecerán aquí cuando haya modelos de proveedor disponibles.';
  @override
  String get effortDefault => 'predeterminado';
  @override
  String get noModelsForSlot => 'No se detectaron modelos para esta ranura.';
  @override
  String viaProvider({required Object provider}) => 'vía ${provider}';
  @override
  String get customModelId => 'id de modelo personalizado';
}

// Path: settings.modelPicker
class _Translations$settings$modelPicker$es
    extends Translations$settings$modelPicker$en {
  _Translations$settings$modelPicker$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String noMatch({required Object query}) =>
      'ningún modelo coincide con "${query}"';
  @override
  String get noModels => 'no hay modelos disponibles';
  @override
  String get filterHint => 'filtrar modelos...';
  @override
  String get warming => 'calentando…';
  @override
  String get detailsUnavailable => 'detalles no disponibles';
  @override
  String get free => 'gratis';
}

// Path: settings.aiFeatures
class _Translations$settings$aiFeatures$es
    extends Translations$settings$aiFeatures$en {
  _Translations$settings$aiFeatures$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get commitDescription =>
      'Redacta mensajes de commit a partir de los cambios en stage usando tu estructura, voz y preferencias de cobertura.';
  @override
  String get reviewDescription =>
      'Revisa el alcance del commit actual antes de hacer commit.';
  @override
  String get museDescription =>
      'Oráculo de tres fases que hace lluvia de ideas y luego sintetiza una dirección hacia delante para el diff.';
}

// Path: settings.commitEditor
class _Translations$settings$commitEditor$es
    extends Translations$settings$commitEditor$en {
  _Translations$settings$commitEditor$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get styleGuide => 'Guía de estilo';
  @override
  String get styleGuideHint =>
      'Opcional. Voz / tono / prohibiciones. El formato de arriba se encarga del esqueleto.';
}

// Path: settings.review
class _Translations$settings$review$es extends Translations$settings$review$en {
  _Translations$settings$review$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Notas adicionales para revisar';
  @override
  String get doubleCheckLabel => 'Doble verificación de la revisión';
  @override
  String get doubleCheckDescription =>
      'Ejecuta una segunda pasada de verificación antes de mostrar el informe final.';
}

// Path: settings.museHint
class _Translations$settings$museHint$es
    extends Translations$settings$museHint$en {
  _Translations$settings$museHint$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get loose =>
      '¿algo hacia lo que orientar con suavidad? hoy el ánimo es amable.';
  @override
  String get balanced => 'en qué detenerse, qué saltar. honesto, no áspero.';
  @override
  String get strict =>
      'los estándares. las prohibiciones. lo que la muse no dejará pasar.';
  @override
  String get paranoid =>
      'ajusta la lente. ¿a qué frecuencias debería vibrar el manifold?';
}

// Path: settings.museEditor
class _Translations$settings$museEditor$es
    extends Translations$settings$museEditor$en {
  _Translations$settings$museEditor$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Notas adicionales para la muse';
}

// Path: settings.museStage
class _Translations$settings$museStage$es
    extends Translations$settings$museStage$en {
  _Translations$settings$museStage$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get brainstorm => 'LLUVIA DE IDEAS';
  @override
  String get synthesize => 'SINTETIZAR';
  @override
  String get slot => 'ranura';
  @override
  String get ideaCountLoose => '~12 ideas';
  @override
  String get ideaCountBalanced => '~16 ideas';
  @override
  String get ideaCountStrict => '~20 ideas';
  @override
  String get ideaCountParanoid => '~24 ideas';
  @override
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  barandilla: ${macro}';
}

// Path: settings.lensAxis
class _Translations$settings$lensAxis$es
    extends Translations$settings$lensAxis$en {
  _Translations$settings$lensAxis$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get folder => 'CARPETA';
  @override
  String get history => 'HISTORIAL';
  @override
  String get far => 'LEJOS';
  @override
  String get near => 'CERCA';
}

// Path: settings.logosLens
class _Translations$settings$logosLens$es
    extends Translations$settings$logosLens$en {
  _Translations$settings$logosLens$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get moduleMap => 'mapa de módulos';
  @override
  String get repoCenters => 'centros del repo';
  @override
  String get neighbors => 'vecinos';
  @override
  String get toTouch => 'qué tocar a continuación';
  @override
  String get relevanceEngine => 'motor de relevancia';
  @override
  String get description =>
      'lee cómo se mueven los archivos juntos a través de la estructura, el historial y el ritmo, para que Manifold sepa qué importa, no solo qué cambió.';
  @override
  String get withinReach => 'al alcance';
  @override
  String get gate => 'compuerta';
  @override
  String get nearest => 'más cercano';
  @override
  String get warming => 'calentando';
  @override
  String get emptyOpenRepo => 'abre un repo para\nver la lente en vivo';
  @override
  String get emptyNoFiles =>
      'no hay archivos al\nalcance — arrastra\nhacia HISTORIAL';
}

// Path: settings.sortGuide
class _Translations$settings$sortGuide$es
    extends Translations$settings$sortGuide$en {
  _Translations$settings$sortGuide$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Guía de orden de cambios';
  @override
  String get related =>
      'Los archivos que cambian juntos se agrupan juntos. Primero va el asunto; el contexto sigue.';
  @override
  String get relatedInverted =>
      'Los cambios aislados van primero. Los clústeres fuertemente acoplados se hunden al fondo.';
  @override
  String get alphabetical =>
      'Simple A → Z por ruta. Sin distinguir mayúsculas, con números ordenados de forma natural.';
  @override
  String get alphabeticalInverted =>
      'Simple Z → A por ruta. Sin distinguir mayúsculas, con números ordenados de forma natural.';
  @override
  String get impact =>
      'Los cambios más pesados salen primero. La agitación se pondera; los binarios y los archivos nuevos reciben un impulso.';
  @override
  String get impactInverted =>
      'Los cambios más ligeros salen primero. Las victorias rápidas arriba; el trabajo pesado espera.';
  @override
  String get nearRelated => 'cercano relacionado';
  @override
  String get alphabeticalShort => 'alfabético';
  @override
  String get byImpact => 'por impacto';
  @override
  String get flipped => 'invertido';
  @override
  String get peek => 'asomar';
}

// Path: settings.piggyback
class _Translations$settings$piggyback$es
    extends Translations$settings$piggyback$en {
  _Translations$settings$piggyback$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get apiModelsUse => 'Los modelos de API usan';
  @override
  String get codexNotDetected => 'codex no detectado';
  @override
  String get dormant => 'INACTIVO';
}

// Path: settings.diffStage
class _Translations$settings$diffStage$es
    extends Translations$settings$diffStage$en {
  _Translations$settings$diffStage$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get viewer => 'visor';
  @override
  String get media => 'media';
  @override
  String get binary => 'binario';
  @override
  String get hidden => 'oculto';
}

// Path: settings.undoScope
class _Translations$settings$undoScope$es
    extends Translations$settings$undoScope$en {
  _Translations$settings$undoScope$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get destructiveActions => 'acciones destructivas';
  @override
  String get discards => 'descartes';
  @override
  String get commits => 'commits';
  @override
  String get commitPush => 'commit + push';
  @override
  String get all => 'todo';
}

// Path: settings.undoWindow
class _Translations$settings$undoWindow$es
    extends Translations$settings$undoWindow$en {
  _Translations$settings$undoWindow$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Ventana de deshacer';
  @override
  String get off => 'Apagado';
  @override
  String descriptionInstant({required Object scope}) =>
      '${scope} se finalizan al instante.';
  @override
  String descriptionDelayed({required Object seconds, required Object scope}) =>
      '${seconds}s antes de que ${scope} se finalicen.';
  @override
  String get cycleScopeTooltip =>
      'Clic para ciclar el alcance · también puedes arrastrar arriba/abajo en el control';
  @override
  String get resetTooltip =>
      'Restablece cada acción para usar la ventana predeterminada';
}

// Path: settings.guardrailPhrase
class _Translations$settings$guardrailPhrase$es
    extends Translations$settings$guardrailPhrase$en {
  _Translations$settings$guardrailPhrase$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get probablyFine => 'Probablemente bien significa bien';
  @override
  String get proper =>
      'Una lectura como es debido: lógica, integración, patrones';
  @override
  String get lookAgain => 'Mira de nuevo. Algo podría estar escondido';
  @override
  String get assumeWrong => 'Asume que algo está mal. Encuéntralo';
}

// Path: settings.reviewGuideHint
class _Translations$settings$reviewGuideHint$es
    extends Translations$settings$reviewGuideHint$en {
  _Translations$settings$reviewGuideHint$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get focusHigh =>
      'p. ej. Céntrate en la lógica de alto nivel y los bugs mayores. Sé breve e indulgente.';
  @override
  String get surfaceBugs =>
      'p. ej. Saca a la luz posibles bugs, inconsistencias arquitectónicas y fallos en casos límite.';
  @override
  String get scrutinize =>
      'p. ej. Escruta cada línea en busca de optimización, seguridad y cumplimiento de patrones.';
  @override
  String get trustNothing =>
      'p. ej. No confíes en nada. Cuestiona cada efecto secundario. Trata cada línea como un posible fallo.';
  @override
  String get optional =>
      'Guía opcional sobre qué debería importarle a la revisión.';
}

// Path: settings.commitFormat
class _Translations$settings$commitFormat$es
    extends Translations$settings$commitFormat$en {
  _Translations$settings$commitFormat$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Formato';
  @override
  String get peek => 'asomar';
  @override
  String get structure => 'Estructura';
  @override
  String get voice => 'Voz';
  @override
  String get coverage => 'Cobertura';
  @override
  String get structureTitleBody => 'título + cuerpo';
  @override
  String get structureTitleOnly => 'solo título';
  @override
  String get structureFreeform => 'libre';
  @override
  String get voiceVerbLed => 'orientada a la acción';
  @override
  String get voiceDescriptive => 'descriptiva';
  @override
  String get voiceNarrative => 'narrativa';
  @override
  String get coverageEssentials => 'lo esencial';
  @override
  String get coverageBalanced => 'equilibrada';
  @override
  String get coverageEverything => 'todo';
}

// Path: settings.commitPreview
class _Translations$settings$commitPreview$es
    extends Translations$settings$commitPreview$en {
  _Translations$settings$commitPreview$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$es title =
      _Translations$settings$commitPreview$title$es._(_root);
  @override
  late final _Translations$settings$commitPreview$base$es base =
      _Translations$settings$commitPreview$base$es._(_root);
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$es
  balancedSuffix = _Translations$settings$commitPreview$balancedSuffix$es._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$es
  everythingSuffix = _Translations$settings$commitPreview$everythingSuffix$es._(
    _root,
  );
}

// Path: settings.externalTools
class _Translations$settings$externalTools$es
    extends Translations$settings$externalTools$en {
  _Translations$settings$externalTools$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Herramientas externas';
  @override
  String get summary =>
      'Haz clic derecho en un proyecto de la barra lateral para abrirlo con una de estas. Los argumentos usan {path} para la carpeta del proyecto.';
  @override
  String get detecting => 'Detectando herramientas instaladas…';
  @override
  String get allPresetsAdded =>
      'Todos los presets conocidos ya están añadidos. Usa “+ Personalizado” para añadir más.';
  @override
  String get noToolsConfigured =>
      'Aún no hay herramientas configuradas. Añade una arriba.';
  @override
  String get categoryAi => 'ia';
  @override
  String get categoryEditors => 'editores';
  @override
  String get categoryExplore => 'explorar';
  @override
  String get categoryOps => 'ops';
  @override
  String get categoryGitOps => 'git ops';
  @override
  String get nameHint => 'Nombre';
  @override
  String get commandHint => 'comando';
  @override
  String get test => 'probar';
  @override
  String get removeTool => 'Quitar herramienta';
  @override
  String get modeTerminal => 'terminal';
  @override
  String get modeDetached => 'separado';
}

// Path: settings.apiUsage
class _Translations$settings$apiUsage$es
    extends Translations$settings$apiUsage$en {
  _Translations$settings$apiUsage$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String thisMonth({required Object used, required Object limit}) =>
      '${used}${limit} este mes';
}

// Path: settings.gitea
class _Translations$settings$gitea$es extends Translations$settings$gitea$en {
  _Translations$settings$gitea$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Tokens de Gitea';
  @override
  String get hostHint => 'host';
  @override
  String get tokenHint => 'token';
  @override
  String get save => 'guardar';
}

// Path: settings.wick
class _Translations$settings$wick$es extends Translations$settings$wick$en {
  _Translations$settings$wick$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get selectExecutable => 'Selecciona el ejecutable de wick';
  @override
  String get connected => 'wick · conectado';
  @override
  String get pathToExecutable => 'wick · ruta al ejecutable';
  @override
  String get off => 'off';
  @override
  String get disableHint => 'Desactivar la integración de wick';
  @override
  String get enableHint => 'Activar la integración de wick';
}

// Path: settings.integrations
class _Translations$settings$integrations$es
    extends Translations$settings$integrations$en {
  _Translations$settings$integrations$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'e integraciones';
  @override
  String get alpha => 'alpha';
  @override
  String get planned => 'planeado';
  @override
  String get lspComingSoon => 'lsp · próximamente';
  @override
  String get alphaMathConnected => 'alpha-math · conectado';
  @override
  String get alphaMathComingSoon => 'alpha-math · próximamente';
}

// Path: settings.reduceMotion
class _Translations$settings$reduceMotion$es
    extends Translations$settings$reduceMotion$en {
  _Translations$settings$reduceMotion$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Reducir movimiento';
  @override
  String get subtitleStill => 'Quieto… ¿como el hielo?';
  @override
  String get subtitleFlow => 'Fluye como el agua.';
}

// Path: settings.resetQuit
class _Translations$settings$resetQuit$es
    extends Translations$settings$resetQuit$en {
  _Translations$settings$resetQuit$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get resetAndQuit => 'RESTABLECER Y SALIR';
  @override
  String get keepRepos => 'CONSERVAR REPOS';
  @override
  String get wipeAll => 'BORRAR TODO';
}

// Path: settings.diagnostics
class _Translations$settings$diagnostics$es
    extends Translations$settings$diagnostics$en {
  _Translations$settings$diagnostics$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get commandDiagnostics => 'Diagnóstico de comandos';
  @override
  String get networkFlowTelemetry => 'Telemetría de flujo de red';
  @override
  String get clearSamples => 'Limpiar muestras';
  @override
  String get clearMetrics => 'Limpiar métricas';
  @override
  String get clearTimings => 'Limpiar tiempos';
  @override
  String get recalibrate => 'RECALIBRAR';
  @override
  String get ok => 'ok';
  @override
  String get noCommandTimings =>
      'Aún no se han capturado tiempos de comandos. Ejecuta acciones normales para poblar el diagnóstico.';
  @override
  String get noBackendSamples =>
      'Aún no se han capturado muestras de comandos del backend. Ejecuta acciones de git y de ajustes para poblar este log.';
  @override
  String get noDiffSessions =>
      'Aún no se han capturado sesiones de renderizado de diff. Abre y desplaza diffs de archivos para poblar este panel.';
  @override
  String get noUiSessions =>
      'Aún no se han capturado sesiones de tiempo de UI. Abre paneles y navega rutas para poblar este panel.';
  @override
  String get recentOperations => 'Operaciones recientes';
  @override
  String get recentBackendOperations => 'Operaciones recientes del backend';
  @override
  String get recentDiffSessions => 'Sesiones de diff recientes';
  @override
  String get recentUiTimings => 'Tiempos de UI recientes';
  @override
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} comando único',
        other: '${n} comandos únicos',
      );
  @override
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} comando con alcance',
        other: '${n} comandos con alcance',
      );
  @override
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} evento instrumentado',
        other: '${n} eventos instrumentados',
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
  List<String> get headersCommand => ['comando', 'p50', 'fiabilidad', 'rango'];
  @override
  List<String> get headersBackend => ['alcance', 'p50', 'p95', 'fallos'];
  @override
  List<String> get headersDiff => [
    'renderizador',
    'primer pintado',
    'frame p95',
    'raster p95',
    'jank',
  ];
  @override
  List<String> get headersUi => ['evento', 'p50', 'fallos', 'rango'];
}

// Path: settings.telemetry
class _Translations$settings$telemetry$es
    extends Translations$settings$telemetry$en {
  _Translations$settings$telemetry$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} muestra',
        other: '${n} muestras',
      );
  @override
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} comando',
        other: '${n} comandos',
      );
  @override
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} sesión',
        other: '${n} sesiones',
      );
  @override
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} evento',
        other: '${n} eventos',
      );
  @override
  String stability({required Object pct}) => '${pct}% de estabilidad';
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
class _Translations$settings$flowEngine$es
    extends Translations$settings$flowEngine$en {
  _Translations$settings$flowEngine$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get executionFlow => 'flujo-de-ejecución';
  @override
  String get description =>
      'simula osciladores sobre el código. saca a la luz rutas de ejecución frágiles antes de que cristalicen como bugs.';
  @override
  String get idle => 'inactivo';
  @override
  String get emptyOpenRepo => 'abre un repo para\nver el análisis de flujo';
  @override
  String get scanning => 'escaneando';
  @override
  String get analysing => 'analizando archivos\nen la lente…';
  @override
  String get fragility => 'fragilidad';
  @override
  String get findings => 'hallazgos';
  @override
  String get gap => 'brecha';
  @override
  String get clean => 'limpio';
  @override
  String get severity => 'severidad';
  @override
  String get critical => 'crítico';
  @override
  String get warn => 'aviso';
  @override
  String get info => 'info';
}

// Path: settings.museStrands
class _Translations$settings$museStrands$es
    extends Translations$settings$museStrands$en {
  _Translations$settings$museStrands$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get spark =>
      'chispa de inspiración · el paso inmediatamente siguiente';
  @override
  String get current => 'corriente en el agua · extensiones en tiempo presente';
  @override
  String get horizon =>
      'mirar sobre el horizonte · direcciones que se alcanzan';
  @override
  String get fever => 'despertar de un sueño febril · provocaciones';
  @override
  String get echo => 'un eco a través del cañón · análogos en otros lugares';
  @override
  String get vertigo => 'vértigo al borde del acantilado · riesgos adyacentes';
  @override
  String get ghost => 'el fantasma de lo que fue · contexto histórico';
  @override
  String get mirror => 'un espejo en agua quieta · inversiones';
}

// Path: settings.cliPiggyback
class _Translations$settings$cliPiggyback$es
    extends Translations$settings$cliPiggyback$en {
  _Translations$settings$cliPiggyback$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Piggyback de CLI';
  @override
  String get clearCacheLabel => 'Limpiar caché';
  @override
  String get clearCacheTooltip =>
      'Borra los modelos en caché y vuelve a sondear. Limpia los que un proveedor dejó caer.';
  @override
  String get refreshLabel => 'Actualizar proveedores';
  @override
  String get refreshTooltip => 'Vuelve a sondear cada proveedor ahora.';
  @override
  String get body =>
      'Canaliza directamente los mensajes de la interfaz a los binarios de proveedores locales.';
  @override
  String get cliTimeoutLabel => 'Tiempo límite por ejecución';
  @override
  String get cliTimeoutUnitMinutes => 'minutos';
  @override
  String get cliTimeoutUnitMinute => 'minuto';
  @override
  String get forceStopLabel => 'Detener todas las sesiones';
  @override
  String get forceStopTooltip =>
      'Forzar el cierre de cada ejecución de CLI en curso.';
  @override
  String get forceStopConfirmTitle => '¿Detener las sesiones de CLI en curso?';
  @override
  String forceStopConfirmBody({required Object count}) =>
      'Esto fuerza el cierre de ${count} ejecuciones de CLI en curso. Se perderá su salida.';
  @override
  String get forceStopConfirmAction => 'Detener todas';
  @override
  String get forceStopNoneRunning => 'No hay sesiones de CLI en curso';
  @override
  String get forceStopRecordError =>
      'Detenido — las sesiones de CLI se cerraron a la fuerza.';
}

// Path: settings.header
class _Translations$settings$header$es extends Translations$settings$header$en {
  _Translations$settings$header$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Preferencias del espacio de trabajo';
  @override
  String get subtitle =>
      'Configura la estética global, las dinámicas de la interfaz y las salvaguardas operativas centrales de todo el espacio de trabajo.';
  @override
  String get releaseNotesTooltip => 'Notas de la versión';
  @override
  String get replayOnboardingTooltip => 'Repetir el onboarding';
}

// Path: settings.diagnosticsPanel
class _Translations$settings$diagnosticsPanel$es
    extends Translations$settings$diagnosticsPanel$en {
  _Translations$settings$diagnosticsPanel$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Diagnóstico de rendimiento';
  @override
  String get copyTrace => 'Copiar traza';
  @override
  String get offenderRanking => 'Ranking de infractores';
  @override
  String get offenderRankingSubtitle => 'Impulsores de latencia entre flujos.';
  @override
  String get noOffenders =>
      'Aún no hay ranking de infractores. Captura actividad de diagnóstico para poblar esta lista.';
}

// Path: settings.release
class _Translations$settings$release$es
    extends Translations$settings$release$en {
  _Translations$settings$release$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Despliegue de versiones';
  @override
  String get summary => 'Ajustes relacionados con las actualizaciones.';
  @override
  String get deploymentChannel => 'CANAL DE DESPLIEGUE';
  @override
  String get captureCrashDiagnostics => 'Capturar diagnósticos de fallos';
  @override
  String get comingSoon => 'Próximamente.';
  @override
  String get checking => 'COMPROBANDO…';
  @override
  String get pollForUpdates => 'BUSCAR ACTUALIZACIONES';
}

// Path: settings.providerStatus
class _Translations$settings$providerStatus$es
    extends Translations$settings$providerStatus$en {
  _Translations$settings$providerStatus$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get detecting => 'Detectando...';
  @override
  String get ready => 'Listo';
  @override
  String get notDetected => 'No detectado';
  @override
  String configured({required Object count}) => '${count} configurados';
  @override
  String get notConfigured => 'No configurado';
  @override
  String get cliManaged => 'Gestionado por CLI';
  @override
  String get connected => 'Conectado';
  @override
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} modelo',
        other: '${n} modelos',
      );
  @override
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} proveedor',
        other: '${n} proveedores',
      );
}

// Path: settings.meridiem
class _Translations$settings$meridiem$es
    extends Translations$settings$meridiem$en {
  _Translations$settings$meridiem$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get am => 'AM';
  @override
  String get pm => 'PM';
}

// Path: settings.offenders
class _Translations$settings$offenders$es
    extends Translations$settings$offenders$en {
  _Translations$settings$offenders$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get commandStream => 'Comando';
  @override
  String get diffStream => 'Renderizado de diff';
  @override
  String get uiStream => 'Tiempo de UI';
  @override
  String rendererName({required Object mode}) => 'renderizador ${mode}';
  @override
  String latencyFailMetric({required Object p95, required Object fail}) =>
      '${p95}ms p95 | ${fail}% fallo';
  @override
  String jankFrameMetric({required Object jank, required Object frame}) =>
      '${jank}% jank | ${frame}ms frame p95';
  @override
  String inStream({required Object stream}) => 'en ${stream}';
}

// Path: sync.actions
class _Translations$sync$actions$es extends Translations$sync$actions$en {
  _Translations$sync$actions$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get syncLabel => 'Sincronizar';
  @override
  String get syncOpenRepoDetail =>
      'Abre un repositorio para gestionar operaciones de push y pull.';
  @override
  String get detachedHeadLabel => 'HEAD desacoplado';
  @override
  String get detachedHeadDetail =>
      'Cambia a una rama antes de hacer push o pull.';
  @override
  String get publishBranchLabel => 'Publicar rama';
  @override
  String publishBranchDetail({required Object branch}) =>
      'Haz push de ${branch} y define su rama de seguimiento upstream.';
  @override
  String get publishButtonLabel => 'Publicar';
  @override
  String get syncBranchLabel => 'Sincronizar rama';
  @override
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => 'Haz pull de ${behindCount} con rebase, luego push de ${aheadCount}.';
  @override
  String get syncBranchButtonLabel => 'Pull (rebase) y luego push';
  @override
  String get pushBranchLabel => 'Hacer push de la rama';
  @override
  String pushBranchDetail({required Object count, required Object upstream}) =>
      'Haz push de ${count} a ${upstream}.';
  @override
  String get pushBranchButtonLabel => 'Hacer push de los commits';
  @override
  String get pullUpdatesLabel => 'Traer actualizaciones';
  @override
  String pullUpdatesDetail({required Object count, required Object upstream}) =>
      'Haz pull de ${count} desde ${upstream}.';
  @override
  String syncUpToDateDetail({required Object upstream}) =>
      'Haz fetch desde ${upstream} y actualiza el estado del upstream.';
}

// Path: sync.panel
class _Translations$sync$panel$es extends Translations$sync$panel$en {
  _Translations$sync$panel$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Cargando estado remoto';
  @override
  String get loadingMessage =>
      'Verificando la información de seguimiento de la rama.';
  @override
  String get remoteStatusUnavailable => 'Estado remoto no disponible';
  @override
  String get noUpstream => 'sin upstream';
  @override
  String get aheadLabel => 'Adelante';
  @override
  String get behindLabel => 'Atrás';
  @override
  String get treeLabel => 'Árbol';
  @override
  String get runningSync => 'Sincronizando…';
  @override
  String get fetching => 'Haciendo fetch…';
  @override
  String get fetchOnly => 'Solo fetch';
  @override
  String get syncFailed => 'Falló la sincronización';
  @override
  String get forcePushRecoveryLabel => 'Push forzado (con lease)';
  @override
  String get conflictsToResolveTitle => 'Conflictos por resolver';
  @override
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} necesitan resolverse: ${list}';
  @override
  String get resolveConflicts => 'Resolver conflictos';
  @override
  String get workingEllipsis => 'Trabajando…';
  @override
  String lastActivity({required Object operation}) =>
      'Última actividad: ${operation}';
  @override
  String get noOutput => 'Sin salida.';
  @override
  String resolvedConflicts({required Object count}) =>
      'Se resolvieron ${count}.';
  @override
  String get cancelledUnchanged => 'Cancelado, árbol de trabajo sin cambios.';
  @override
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) =>
      '${count} tienen cambios sin commit, haz commit primero para sincronizar con rebase (${list}).';
  @override
  String noUpstreamForForcePush({required Object branch}) =>
      'No se puede hacer push forzado: no hay upstream configurado para "${branch}".';
}

// Path: sync.forcePush
class _Translations$sync$forcePush$es extends Translations$sync$forcePush$en {
  _Translations$sync$forcePush$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get confirmTitle => '¿Push forzado (con lease)?';
  @override
  String target({required Object remote, required Object branch}) =>
      'Destino: ${remote}/${branch}';
  @override
  String get warning =>
      'Esto reescribe la rama remota con tu historial local. Con lease se aborta si alguien hizo push al remoto después de tu último fetch, pero los cambios ya traídos igual se sobrescribirán. Úsalo solo cuando hayas hecho un rebase o amend a propósito que divergió la rama.';
  @override
  String get confirmButton => 'Push forzado';
}

// Path: xray.board
class _Translations$xray$board$es extends Translations$xray$board$en {
  _Translations$xray$board$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get movesWithModule => 'se mueve con otro módulo';
  @override
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} revisor',
        other: '${n} revisores',
      );
  @override
  String get territory => 'Territorio';
  @override
  String get unreviewed => 'sin revisar';
}

// Path: xray.cadence
class _Translations$xray$cadence$es extends Translations$xray$cadence$en {
  _Translations$xray$cadence$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '${sum} commits · ${days} días\n${lines}';
  @override
  String burstTooltipSingle({required Object n, required Object label}) =>
      '${n} commits el ${label}';
  @override
  String gapTooltip({required Object n, required Object label}) =>
      'brecha de ${n} días · ${label}';
  @override
  String reflogTooltip({required Object n, required Object label}) =>
      '${n} eventos de reflog el ${label}';
}

// Path: xray.cards
class _Translations$xray$cards$es extends Translations$xray$cards$en {
  _Translations$xray$cards$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$cards$branchModel$es branchModel =
      _Translations$xray$cards$branchModel$es._(_root);
  @override
  late final _Translations$xray$cards$bursty$es bursty =
      _Translations$xray$cards$bursty$es._(_root);
  @override
  late final _Translations$xray$cards$hiddenRefs$es hiddenRefs =
      _Translations$xray$cards$hiddenRefs$es._(_root);
  @override
  late final _Translations$xray$cards$keystone$es keystone =
      _Translations$xray$cards$keystone$es._(_root);
  @override
  late final _Translations$xray$cards$machineHistory$es machineHistory =
      _Translations$xray$cards$machineHistory$es._(_root);
  @override
  late final _Translations$xray$cards$migration$es migration =
      _Translations$xray$cards$migration$es._(_root);
  @override
  late final _Translations$xray$cards$narrowHotspot$es narrowHotspot =
      _Translations$xray$cards$narrowHotspot$es._(_root);
  @override
  late final _Translations$xray$cards$noTags$es noTags =
      _Translations$xray$cards$noTags$es._(_root);
  @override
  late final _Translations$xray$cards$reflog$es reflog =
      _Translations$xray$cards$reflog$es._(_root);
  @override
  late final _Translations$xray$cards$singleOwner$es singleOwner =
      _Translations$xray$cards$singleOwner$es._(_root);
}

// Path: xray.cardTitle
class _Translations$xray$cardTitle$es extends Translations$xray$cardTitle$en {
  _Translations$xray$cardTitle$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get branches => 'ramas';
  @override
  String get bursty => 'a ráfagas';
  @override
  String get hiddenRefs => 'refs ocultas';
  @override
  String get machineHeavy => 'carga de máquina';
  @override
  String get migration => 'migración';
  @override
  String get narrowHotspot => 'punto caliente estrecho';
  @override
  String get noTags => 'sin etiquetas';
  @override
  String get reflog => 'reflog';
  @override
  String get singleOwner => 'un solo dueño';
}

// Path: xray.grain
class _Translations$xray$grain$es extends Translations$xray$grain$en {
  _Translations$xray$grain$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get coarsest => 'el más grueso — módulos de nivel superior';
  @override
  String get finest => 'grano más fino';
  @override
  String get mid => 'grano medio';
  @override
  String get oneCharacteristic => 'una escala característica';
}

// Path: xray.header
class _Translations$xray$header$es extends Translations$xray$header$en {
  _Translations$xray$header$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get dirtyBadge => 'sucio';
  @override
  String get machineChip => 'máquina';
  @override
  String get refresh => 'Actualizar';
  @override
  String get refreshing => 'Actualizando...';
  @override
  String get title => 'X-Ray del repo';
}

// Path: xray.hotspot
class _Translations$xray$hotspot$es extends Translations$xray$hotspot$en {
  _Translations$xray$hotspot$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get clusterPeers => 'pares del clúster';
  @override
  String get coChangers => 'co-modificadores';
  @override
  String get keystone => 'clave';
  @override
  String keystoneScore({required Object score}) => 'clave  φ=${score}';
}

// Path: xray.inspector
class _Translations$xray$inspector$es extends Translations$xray$inspector$en {
  _Translations$xray$inspector$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get branchLabel => 'rama';
  @override
  String commitsHumanMachine({required Object n}) => 'humano · ${n} de máquina';
  @override
  String get commitsLabel => 'commits';
  @override
  String get confidenceLabel => 'confianza';
  @override
  String get curlLabel => 'curl';
  @override
  String get engineSection => 'motor';
  @override
  String get gradientLabel => 'gradiente';
  @override
  String get harmonicLabel => 'armónico';
  @override
  String get headLabel => 'head';
  @override
  String get hiddenRefsLabel => 'refs ocultas';
  @override
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} merge',
        other: '${n} merges',
      );
  @override
  String get noTags => 'sin etiquetas';
  @override
  String get notesLabel => 'notas';
  @override
  String get openCommit => 'Abrir commit';
  @override
  String get pathLabel => 'ruta';
  @override
  String remoteCount({required Object n}) => '${n} remoto';
  @override
  String get renamesLabel => 'renombres';
  @override
  String scannedAt({required Object time}) => 'escaneado ${time}';
  @override
  String selectedCount({required Object n}) => '${n} seleccionados';
  @override
  String get shapeLinear => 'lineal';
  @override
  String get shapeMergeHeavy => 'con muchos merges';
  @override
  String get shapeMostlyLinear => 'en su mayoría lineal';
  @override
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} stash',
        other: '${n} stashes',
      );
  @override
  String get stressLabel => 'estrés';
  @override
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} etiqueta',
        other: '${n} etiquetas',
      );
  @override
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} árbol de trabajo',
        other: '${n} árboles de trabajo',
      );
}

// Path: xray.loadingCard
class _Translations$xray$loadingCard$es
    extends Translations$xray$loadingCard$en {
  _Translations$xray$loadingCard$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get buildingMessage =>
      'Sondeando el historial de Git, refs, cadencia y puntos calientes.';
  @override
  String get buildingTitle => 'Construyendo el X-Ray del repo';
  @override
  String get idleMessage =>
      'Abre el panel de nuevo para sondear el repositorio actual.';
  @override
  String get idleTitle => 'X-Ray del repo';
  @override
  String get unavailableTitle => 'X-Ray del repo no disponible';
}

// Path: xray.metabolism
class _Translations$xray$metabolism$es extends Translations$xray$metabolism$en {
  _Translations$xray$metabolism$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String halfLife({required Object n}) => 'vida media de ${n}d';
}

// Path: xray.multi
class _Translations$xray$multi$es extends Translations$xray$multi$en {
  _Translations$xray$multi$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} clúster',
        other: '${n} clústeres',
      );
  @override
  String clusterSingle({required Object id}) => 'clúster ${id}';
  @override
  String couplingSuffix({required Object parts}) => 'acoplamiento ${parts}';
  @override
  String externalCount({required Object n}) => '${n} externo';
  @override
  String mutualCount({required Object n}) => '${n} mutuo';
}

// Path: xray.recency
class _Translations$xray$recency$es extends Translations$xray$recency$en {
  _Translations$xray$recency$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String days({required Object n}) => '${n}d';
  @override
  String months({required Object n}) => '${n}mes';
  @override
  String get today => 'hoy';
  @override
  String weeks({required Object n}) => '${n}sem';
  @override
  String years({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n}a',
        other: '${n}a',
      );
}

// Path: xray.rings
class _Translations$xray$rings$es extends Translations$xray$rings$en {
  _Translations$xray$rings$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get hintOneBlended => 'una estructura mezclada';
  @override
  String get hintSelfSimilar => 'autosimilar';
  @override
  String get oneBlendedBody =>
      'Una estructura mezclada — aún no se resuelven escalas de módulos separables.';
  @override
  String get overHistory => 'A lo largo del historial';
  @override
  String get parts => 'partes';
  @override
  String get readingHint => 'leyendo la estructura…';
  @override
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} escala',
        other: '${n} escalas',
      );
  @override
  String get scaleDissolved => 'una escala estructural se disolvió';
  @override
  String get scaleEmerged => 'una escala estructural emergió';
  @override
  String get scaleSpectrum => 'espectro de escalas';
  @override
  String get selfSimilarBody =>
      'Autosimilar — la estructura se repite entre escalas, sin un único nivel característico.';
  @override
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} cambio en el historial',
        other: '${n} cambios en el historial',
      );
  @override
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} cambio estructural',
        other: '${n} cambios estructurales',
      );
  @override
  String get title => 'Anillos de crecimiento';
  @override
  String get unavailable => 'no disponible';
}

// Path: xray.stats
class _Translations$xray$stats$es extends Translations$xray$stats$en {
  _Translations$xray$stats$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get alive => 'vivo';
  @override
  String get files => 'archivos';
  @override
  String get lastTouched => 'último toque';
  @override
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'dueño',
        other: 'dueños',
      );
  @override
  String get touches => 'toques';
}

// Path: xray.stratumLabel
class _Translations$xray$stratumLabel$es
    extends Translations$xray$stratumLabel$en {
  _Translations$xray$stratumLabel$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'actual';
  @override
  String get legacy => 'heredado';
  @override
  String get zone => 'zona del repo';
}

// Path: xray.summary
class _Translations$xray$summary$es extends Translations$xray$summary$en {
  _Translations$xray$summary$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String analysisFailed({required Object error}) =>
      'Falló el análisis: ${error}';
  @override
  String get analyze => 'Analizar';
  @override
  String get copied => 'Resumen copiado al portapapeles.';
  @override
  String get directionHint => 'dirección';
  @override
  String get download => 'Descargar';
  @override
  String get emptyState =>
      'Ejecuta el análisis de Logos para mapear la estructura y las regiones de este repositorio.\n(av: puro slop rn)';
  @override
  String get exit => 'Salir';
  @override
  String get generating => 'Leyendo el repo y agrupando características…';
  @override
  String get noModel => 'No hay ningún modelo de IA configurado.';
  @override
  String get noModelConfigured => 'no hay modelo de IA configurado';
  @override
  String presentWith({required Object label}) => 'presentar con ${label}';
  @override
  String presentingWith({required Object label}) => 'presentando con ${label}…';
  @override
  String get reanalyze => 'Reanalizar';
  @override
  String get saveDialogTitle => 'Guardar resumen del repositorio';
  @override
  String saveFailed({required Object error}) => 'Falló el guardado: ${error}';
  @override
  String get savePresentationDialogTitle => 'Guardar presentación';
  @override
  String savedTo({required Object path}) => 'Guardado en ${path}';
}

// Path: xray.tabs
class _Translations$xray$tabs$es extends Translations$xray$tabs$en {
  _Translations$xray$tabs$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get map => 'Mapa';
  @override
  String get signals => 'Señales';
  @override
  String get summary => 'Resumen';
  @override
  String get time => 'Tiempo';
}

// Path: xray.trajectory
class _Translations$xray$trajectory$es extends Translations$xray$trajectory$en {
  _Translations$xray$trajectory$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get connectivity => 'conectividad';
  @override
  String events({required Object n}) => '${n} eventos';
  @override
  String get openInOrrery => 'Abrir en el Orrery';
  @override
  String get readingHint => 'leyendo el historial…';
  @override
  String snapshots({required Object n}) => '${n} instantáneas';
  @override
  String get steady => 'Estable — sin eventos estructurales en esta ventana.';
  @override
  String get title => 'Trayectoria estructural';
}

// Path: xray.verdict
class _Translations$xray$verdict$es extends Translations$xray$verdict$en {
  _Translations$xray$verdict$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String canonical({required Object pct}) => '${pct}% canónico';
  @override
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · ${canonical}% canónico · ${decisive}% decisivo';
}

// Path: changes.mergeEditor.trust
class _Translations$changes$mergeEditor$trust$es
    extends Translations$changes$mergeEditor$trust$en {
  _Translations$changes$mergeEditor$trust$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get manual => 'manual';
  @override
  String get safe => 'seguro';
  @override
  String get guided => 'guiado';
  @override
  String get assisted => 'asistido';
  @override
  String get full => 'total';
  @override
  String label({required Object label}) => 'confianza: ${label}';
}

// Path: changes.mergeEditor.keyHints
class _Translations$changes$mergeEditor$keyHints$es
    extends Translations$changes$mergeEditor$keyHints$en {
  _Translations$changes$mergeEditor$keyHints$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get accept => 'aceptar';
  @override
  String get other => 'otro';
  @override
  String get both => 'ambos';
  @override
  String get navigate => 'navegar';
  @override
  String get jumpNext => 'saltar al siguiente';
}

// Path: changes.mergeFlow.op
class _Translations$changes$mergeFlow$op$es
    extends Translations$changes$mergeFlow$op$en {
  _Translations$changes$mergeFlow$op$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'merge';
  @override
  String get cherryPick => 'cherry-pick';
  @override
  String get revert => 'revert';
  @override
  String get resolve => 'resolver';
  @override
  String get switchOp => 'cambiar';
  @override
  String get pull => 'pull';
  @override
  String get rebase => 'rebase';
  @override
  String rebaseOnto({required Object branch, required Object base}) =>
      'rebasar ${branch} sobre ${base}';
}

// Path: diff.pinned.tempo
class _Translations$diff$pinned$tempo$es
    extends Translations$diff$pinned$tempo$en {
  _Translations$diff$pinned$tempo$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get hotOwnerLane => 'Movimiento reciente con un dueño fuerte cerca.';
  @override
  String get activeSeam => 'Movimiento reciente de varias manos cerca.';
  @override
  String get stableOwnerLane => 'Carril duradero con un dueño dominante.';
  @override
  String get sharedLongLivedSeam =>
      'Costura compartida acumulada con el tiempo.';
  @override
  String get sharedLane => 'Carril compartido sin un dueño dominante.';
  @override
  String get resolving =>
      'El historial aún se está resolviendo en torno a esta línea.';
}

// Path: diff.pinned.tone
class _Translations$diff$pinned$tone$es
    extends Translations$diff$pinned$tone$en {
  _Translations$diff$pinned$tone$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get hot => 'Caliente';
  @override
  String get novel => 'Novedoso';
  @override
  String get contested => 'Disputado';
  @override
  String get spreading => 'Expandiéndose';
  @override
  String get stable => 'Estable';
}

// Path: diff.pinned.summary
class _Translations$diff$pinned$summary$es
    extends Translations$diff$pinned$summary$en {
  _Translations$diff$pinned$summary$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String livesIn({required Object concept}) => 'Vive en ${concept}';
  @override
  String get sitsInLocalSeam => 'Se ubica en una costura local';
  @override
  String workedMostlyBy({required Object owner}) =>
      'trabajado sobre todo por ${owner} cerca';
  @override
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'resuena en ${n} otro punto',
        other: 'resuena en ${n} otros puntos',
      );
  @override
  String inspectNext({required Object path, required Object detail}) =>
      'inspecciona ${path} a continuación${detail}';
  @override
  String inspectDetail({required Object reason}) => ' (${reason})';
}

// Path: diff.pinned.tightness
class _Translations$diff$pinned$tightness$es
    extends Translations$diff$pinned$tightness$en {
  _Translations$diff$pinned$tightness$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get tight => 'ajuste apretado';
  @override
  String get close => 'ajuste cercano';
  @override
  String get loose => 'ajuste holgado';
}

// Path: diff.pinned.witness
class _Translations$diff$pinned$witness$es
    extends Translations$diff$pinned$witness$en {
  _Translations$diff$pinned$witness$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String nearbySupport({required Object label}) => 'Apoyo cercano · ${label}';
  @override
  String localizedMove({required Object label}) =>
      'Movimiento localizado · ${label}';
  @override
  String surprisingMove({required Object label}) =>
      'Movimiento sorprendente · ${label}';
}

// Path: diff.pinned.integrity
class _Translations$diff$pinned$integrity$es
    extends Translations$diff$pinned$integrity$en {
  _Translations$diff$pinned$integrity$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get stableStructure => 'Estructura estable';
  @override
  String get conflictingSignals => 'Señales en conflicto';
  @override
  String get novelShape => 'Forma novedosa';
}

// Path: diff.pinned.related
class _Translations$diff$pinned$related$es
    extends Translations$diff$pinned$related$en {
  _Translations$diff$pinned$related$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get testMirror => 'Espejo de test';
  @override
  String get semanticHistorySibling => 'Hermano semántico + de historial';
  @override
  String get recentCoChange => 'Co-cambio reciente';
  @override
  String get semanticSibling => 'Hermano semántico';
  @override
  String get relatedStructure => 'Estructura relacionada';
  @override
  String get tightlyBound => 'fuertemente ligado';
  @override
  String get orbiting => 'en órbita';
  @override
  String get weaklyCoupled => 'débilmente acoplado';
  @override
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class _Translations$diff$pinned$axis$es
    extends Translations$diff$pinned$axis$en {
  _Translations$diff$pinned$axis$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get historyTrail => 'rastro de historial';
  @override
  String get testMirrorLane => 'carril de espejo de test';
  @override
  String get structuralLane => 'carril estructural';
  @override
  String get semanticNeighbourhood => 'vecindario semántico';
}

// Path: history.commitLede.semantics
class _Translations$history$commitLede$semantics$es
    extends Translations$history$commitLede$semantics$en {
  _Translations$history$commitLede$semantics$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get importanceHigh => 'importancia alta';
  @override
  String get importanceModerate => 'importancia moderada';
  @override
  String get mostlyAdditions => 'en su mayoría adiciones';
  @override
  String get mostlyDeletions => 'en su mayoría eliminaciones';
  @override
  String get tightlyCoupled => 'archivos fuertemente acoplados';
  @override
  String get overlapsWorkingTree => 'se solapa con tu árbol de trabajo';
}

// Path: onboarding.repo.doors
class _Translations$onboarding$repo$doors$es
    extends Translations$onboarding$repo$doors$en {
  _Translations$onboarding$repo$doors$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$repo$doors$open$es open =
      _Translations$onboarding$repo$doors$open$es._(_root);
  @override
  late final _Translations$onboarding$repo$doors$clone$es clone =
      _Translations$onboarding$repo$doors$clone$es._(_root);
  @override
  late final _Translations$onboarding$repo$doors$create$es create =
      _Translations$onboarding$repo$doors$create$es._(_root);
}

// Path: onboarding.repo.cloneForm
class _Translations$onboarding$repo$cloneForm$es
    extends Translations$onboarding$repo$cloneForm$en {
  _Translations$onboarding$repo$cloneForm$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Clonar desde URL';
  @override
  String get urlLabel => 'URL del repositorio';
  @override
  String get targetLabel => 'Carpeta de destino';
  @override
  String get browse => 'Explorar…';
  @override
  String get clone => 'Clonar';
  @override
  String get cloning => 'Clonando…';
}

// Path: onboarding.repo.pickers
class _Translations$onboarding$repo$pickers$es
    extends Translations$onboarding$repo$pickers$en {
  _Translations$onboarding$repo$pickers$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get openRepository => 'Abrir repositorio';
  @override
  String get createRepository => 'Crear repositorio';
  @override
  String get cloneTarget => 'Destino del clon';
}

// Path: onboarding.repo.errors
class _Translations$onboarding$repo$errors$es
    extends Translations$onboarding$repo$errors$en {
  _Translations$onboarding$repo$errors$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get urlAndTargetRequired =>
      'Se requieren la URL y la ruta de destino.';
  @override
  String get createFailed => 'No se pudo crear el repositorio.';
  @override
  String get cloneFailed => 'No se pudo clonar el repositorio.';
}

// Path: onboarding.preview.panels
class _Translations$onboarding$preview$panels$es
    extends Translations$onboarding$preview$panels$en {
  _Translations$onboarding$preview$panels$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get xray => 'X-Ray del repo';
  @override
  String get settings => 'ajustes';
}

// Path: onboarding.preview.sidebar
class _Translations$onboarding$preview$sidebar$es
    extends Translations$onboarding$preview$sidebar$en {
  _Translations$onboarding$preview$sidebar$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get projectsHeader => 'Proyectos';
}

// Path: onboarding.preview.changes
class _Translations$onboarding$preview$changes$es
    extends Translations$onboarding$preview$changes$en {
  _Translations$onboarding$preview$changes$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String filesStagedCount({required Object staged, required Object total}) =>
      '${staged} de ${total} archivos';
  @override
  String stagedCount({required Object n}) => '${n} en stage';
  @override
  String get commitMessageHint => 'Mensaje de commit…';
  @override
  String get commitAndPush => 'Commit y push';
}

// Path: onboarding.preview.history
class _Translations$onboarding$preview$history$es
    extends Translations$onboarding$preview$history$en {
  _Translations$onboarding$preview$history$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'Historial';
  @override
  String get viewingLast => 'viendo los últimos 20 commits';
  @override
  String get inFlight => 'EN VUELO';
  @override
  String get you => 'tú';
  @override
  String get commit1 => 'enseñar al zorro a olfatear antes de tragar';
  @override
  String get commit2 => 'ámbar: retener el aroma toda la noche';
  @override
  String get commit3 => 'retirar la col en favor de ámbar + espina';
  @override
  String get commit4 => 'la espina guarda la puerta';
}

// Path: onboarding.preview.branches
class _Translations$onboarding$preview$branches$es
    extends Translations$onboarding$preview$branches$en {
  _Translations$onboarding$preview$branches$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get lensBranches => 'RAMAS';
  @override
  String get lensPRs => 'PRs';
  @override
  String get absorbed => 'absorbida';
  @override
  String get desk => 'Desk';
  @override
  String get head => 'HEAD';
  @override
  String tracking({required Object ref}) => '→ siguiendo: ${ref}';
}

// Path: onboarding.preview.diff
class _Translations$onboarding$preview$diff$es
    extends Translations$onboarding$preview$diff$en {
  _Translations$onboarding$preview$diff$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get readmeTagline => 'Tu cliente de Git personal.';
}

// Path: releaseNotes.about.whyFlutter
class _Translations$releaseNotes$about$whyFlutter$es
    extends Translations$releaseNotes$about$whyFlutter$en {
  _Translations$releaseNotes$about$whyFlutter$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get question => '¿POR QUÉ FLUTTER?';
  @override
  String get body =>
      'La primera versión de esto fue una app de Tauri (Rust + TypeScript). Ya sentía que iba lenta. Luego pillé a un streamer diciendo lo mismo en un directo que no suelo ver, y ese fue el empujón para por fin cambiar. Él no sugirió Flutter; para nada. Encontré Dart por mi cuenta, armé un prototipo, y el arranque pasó de unos 15 segundos a menos de uno. Del cielo a la tierra. Adiós a la era Tauri.\n\nEl pipeline de renderizado de Flutter se parece más a un motor de juego que a un DOM, y para una app de escritorio donde la UI es el producto, eso lo es todo. Dart resultó ser también un lenguaje genuinamente bueno. La matemática detrás del motor espectral se prototipó primero en Rust, así que ese trabajo se trasladó sin problemas.\n\nFlutter es multiplataforma por defecto, lo cual es genial, pero tiene un aire muy Google, así que hay unas cuantas rarezas.';
}

// Path: releaseNotes.about.spectralEngine
class _Translations$releaseNotes$about$spectralEngine$es
    extends Translations$releaseNotes$about$spectralEngine$en {
  _Translations$releaseNotes$about$spectralEngine$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get question => '¿QUÉ ES EL MOTOR ESPECTRAL?';
  @override
  String get body =>
      'Cada vez que haces commit, los archivos que cambias juntos forman patrones a lo largo del tiempo. El motor espectral lee tu grafo de commits y descompone esos patrones de co-cambio en señales: qué archivos están acoplados, con qué fuerza, y qué rol estructural juegan en el repo. Básicamente análisis espectral sobre tu historial de desarrollo. En un cliente de git. A propósito.\n\nLa matemática es nueva, así que la trato como el feel de un juego: la ajusto, la pruebo, la retoco, y sigo hasta que las señales se sienten correctas.\n\nEsas señales alimentan todo. El sismógrafo en el historial, las barras pintadas bajo los asuntos de los commits, el sistema de revisión, Muse, la constelación de archivos. La app entera razona desde esta capa hacia abajo, no al revés.';
}

// Path: releaseNotes.about.whereGoing
class _Translations$releaseNotes$about$whereGoing$es
    extends Translations$releaseNotes$about$whereGoing$en {
  _Translations$releaseNotes$about$whereGoing$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get question => '¿HACIA DÓNDE VA ESTO?';
  @override
  String get body =>
      'El primer hito es la paridad completa con GitHub Desktop, SourceTree y GitKraken. Un cliente de git multiplataforma que se siente rápido y maneja lo fundamental mejor que cualquier otra cosa. Eso ya está casi listo. El motor espectral ya nos da ventaja en operaciones que otros clientes te hacen razonar a mano.\n\nMás allá de eso, la meta es superar a todos los demás clientes de git en velocidad, accesibilidad, inteligencia y UX en general. Hay más en camino de lo que se anuncia aquí.';
}

// Path: settings.commitPreview.title
class _Translations$settings$commitPreview$title$es
    extends Translations$settings$commitPreview$title$en {
  _Translations$settings$commitPreview$title$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$verbLed$es verbLed =
      _Translations$settings$commitPreview$title$verbLed$es._(_root);
  @override
  late final _Translations$settings$commitPreview$title$descriptive$es
  descriptive = _Translations$settings$commitPreview$title$descriptive$es._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$title$narrative$es narrative =
      _Translations$settings$commitPreview$title$narrative$es._(_root);
}

// Path: settings.commitPreview.base
class _Translations$settings$commitPreview$base$es
    extends Translations$settings$commitPreview$base$en {
  _Translations$settings$commitPreview$base$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$base$verbLed$es verbLed =
      _Translations$settings$commitPreview$base$verbLed$es._(_root);
  @override
  late final _Translations$settings$commitPreview$base$descriptive$es
  descriptive = _Translations$settings$commitPreview$base$descriptive$es._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$base$narrative$es narrative =
      _Translations$settings$commitPreview$base$narrative$es._(_root);
}

// Path: settings.commitPreview.balancedSuffix
class _Translations$settings$commitPreview$balancedSuffix$es
    extends Translations$settings$commitPreview$balancedSuffix$en {
  _Translations$settings$commitPreview$balancedSuffix$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$verbLed$es
  verbLed = _Translations$settings$commitPreview$balancedSuffix$verbLed$es._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$descriptive$es
  descriptive =
      _Translations$settings$commitPreview$balancedSuffix$descriptive$es._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$narrative$es
  narrative =
      _Translations$settings$commitPreview$balancedSuffix$narrative$es._(_root);
}

// Path: settings.commitPreview.everythingSuffix
class _Translations$settings$commitPreview$everythingSuffix$es
    extends Translations$settings$commitPreview$everythingSuffix$en {
  _Translations$settings$commitPreview$everythingSuffix$es._(
    TranslationsEs root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$verbLed$es
  verbLed = _Translations$settings$commitPreview$everythingSuffix$verbLed$es._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$descriptive$es
  descriptive =
      _Translations$settings$commitPreview$everythingSuffix$descriptive$es._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$narrative$es
  narrative =
      _Translations$settings$commitPreview$everythingSuffix$narrative$es._(
        _root,
      );
}

// Path: xray.cards.branchModel
class _Translations$xray$cards$branchModel$es
    extends Translations$xray$cards$branchModel$en {
  _Translations$xray$cards$branchModel$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get broadClaim =>
      'El repositorio tiene suficiente superficie de ramas para que valga la pena navegar con conciencia de ramas.';
  @override
  String get broadTitle => 'El modelo de ramas tiene superficie';
  @override
  String localBranchesDetail({required Object count}) =>
      '${count} ramas locales.';
  @override
  String get localBranchesLabel => 'Ramas locales';
  @override
  String remoteBranchesDetail({required Object count}) =>
      '${count} ramas remotas.';
  @override
  String get remoteBranchesLabel => 'Ramas remotas';
  @override
  String get simpleClaim => 'El modelo de ramas visible es estrecho.';
  @override
  String get simpleTitle => 'Modelo de ramas simple';
}

// Path: xray.cards.bursty
class _Translations$xray$cards$bursty$es
    extends Translations$xray$cards$bursty$en {
  _Translations$xray$cards$bursty$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'El trabajo llega en ráfagas concentradas en lugar de un ritmo diario constante.';
  @override
  String get title => 'Cadencia de desarrollo a ráfagas';
}

// Path: xray.cards.hiddenRefs
class _Translations$xray$cards$hiddenRefs$es
    extends Translations$xray$cards$hiddenRefs$en {
  _Translations$xray$cards$hiddenRefs$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object count}) =>
      '${count} refs viven fuera del espacio normal de ramas/etiquetas.';
  @override
  String evidenceDetail({required Object count}) =>
      '${count} refs fuera de heads/remotes/tags.';
  @override
  String get evidenceLabel => 'Refs ocultas';
  @override
  String get namespacesLabel => 'Espacios de nombres';
  @override
  String get title => 'Espacios de nombres ocultos de Git';
}

// Path: xray.cards.keystone
class _Translations$xray$cards$keystone$es
    extends Translations$xray$cards$keystone$en {
  _Translations$xray$cards$keystone$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String claim({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
    n,
    one:
        'Un archivo carga un peso de co-cambio desproporcionado respecto a su número de toques.',
    other:
        'Un pequeño conjunto de archivos carga un peso de co-cambio desproporcionado respecto a sus números de toques.',
  );
  @override
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: '${n} toque · atracción φ=${score}',
        other: '${n} toques · atracción φ=${score}',
      );
  @override
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(
        n,
        one: 'Archivo puente clave',
        other: '${n} archivos puente clave',
      );
}

// Path: xray.cards.machineHistory
class _Translations$xray$cards$machineHistory$es
    extends Translations$xray$cards$machineHistory$en {
  _Translations$xray$cards$machineHistory$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Los commits estilo checkpoint distorsionan de forma material las métricas ingenuas del historial.';
  @override
  String machineCommitsDetail({required Object count}) =>
      '${count} commits coincidieron con patrones de máquina/sesión.';
  @override
  String get machineCommitsLabel => 'Commits de máquina';
  @override
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '${raw} commits en bruto vs ${filtered} commits filtrados.';
  @override
  String get rawVsFilteredLabel => 'En bruto vs filtrado';
  @override
  String get title => 'El historial de máquina domina las métricas en bruto';
}

// Path: xray.cards.migration
class _Translations$xray$cards$migration$es
    extends Translations$xray$cards$migration$en {
  _Translations$xray$cards$migration$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object older, required Object newer}) =>
      'El historial pasa de `${older}` a `${newer}`, lo que sugiere una transición de stack o de superficie.';
  @override
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches} toques, última actividad ${lastActive}.';
  @override
  String get title => 'Migración de arquitectura visible';
}

// Path: xray.cards.narrowHotspot
class _Translations$xray$cards$narrowHotspot$es
    extends Translations$xray$cards$narrowHotspot$en {
  _Translations$xray$cards$narrowHotspot$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Un pequeño conjunto de archivos y directorios absorbe una parte desproporcionada de los cambios.';
  @override
  String get title => 'La concentración de puntos calientes es estrecha';
  @override
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path} representa el ${pct}% del conjunto de puntos calientes visible.';
  @override
  String get topHotspotLabel => 'Punto caliente principal';
  @override
  String visibleAuthorsDetail({required Object count}) =>
      '${count} autores en este tramo del historial.';
  @override
  String get visibleAuthorsLabel => 'Autores visibles';
}

// Path: xray.cards.noTags
class _Translations$xray$cards$noTags$es
    extends Translations$xray$cards$noTags$en {
  _Translations$xray$cards$noTags$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Las etiquetas de Git no se usan como capa visible de versiones o hitos.';
  @override
  String remoteEndpointsDetail({required Object count}) =>
      '${count} endpoints remotos configurados.';
  @override
  String get remoteEndpointsLabel => 'Endpoints remotos';
  @override
  String get tagCountDetail => 'Se encontraron 0 etiquetas.';
  @override
  String get tagCountLabel => 'Número de etiquetas';
  @override
  String get title => 'Sin rastro formal de versiones/etiquetas';
}

// Path: xray.cards.reflog
class _Translations$xray$cards$reflog$es
    extends Translations$xray$cards$reflog$en {
  _Translations$xray$cards$reflog$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'El volumen del reflog sugiere iteración local concentrada más allá de los commits publicados.';
  @override
  String get peakReflogDayLabel => 'Día pico de reflog';
  @override
  String get title => 'Sesiones intensas de edición local';
}

// Path: xray.cards.singleOwner
class _Translations$xray$cards$singleOwner$es
    extends Translations$xray$cards$singleOwner$en {
  _Translations$xray$cards$singleOwner$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object path, required Object kind}) =>
      '`${path}` es un ${kind} muy tocado con un único autor visible distintivo.';
  @override
  String ownerCountDetail({required Object count}) =>
      '${count} autores distintos.';
  @override
  String get ownerCountLabel => 'Número de dueños';
  @override
  String get title => 'Punto caliente de un solo dueño';
  @override
  String get touchCountLabel => 'Número de toques';
  @override
  String touchDetailFiltered({required Object count}) =>
      '${count} toques en el historial filtrado.';
  @override
  String touchDetailRaw({required Object count}) =>
      '${count} toques en el historial en bruto.';
}

// Path: onboarding.repo.doors.open
class _Translations$onboarding$repo$doors$open$es
    extends Translations$onboarding$repo$doors$open$en {
  _Translations$onboarding$repo$doors$open$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Abrir';
  @override
  String get subtitle => 'existente';
  @override
  String get hint => 'uno que ya tienes';
}

// Path: onboarding.repo.doors.clone
class _Translations$onboarding$repo$doors$clone$es
    extends Translations$onboarding$repo$doors$clone$en {
  _Translations$onboarding$repo$doors$clone$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Clonar';
  @override
  String get subtitle => 'desde URL';
  @override
  String get hint => 'pega una URL remota';
}

// Path: onboarding.repo.doors.create
class _Translations$onboarding$repo$doors$create$es
    extends Translations$onboarding$repo$doors$create$en {
  _Translations$onboarding$repo$doors$create$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Crear';
  @override
  String get subtitle => 'nuevo';
  @override
  String get hint => 'empieza algo desde cero';
}

// Path: settings.commitPreview.title.verbLed
class _Translations$settings$commitPreview$title$verbLed$es
    extends Translations$settings$commitPreview$title$verbLed$en {
  _Translations$settings$commitPreview$title$verbLed$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Deja que el zorro se salte las galletas que huelen raro';
  @override
  String get s2 =>
      'Entrena al zorro para rechazar galletas manipuladas antes de tragar';
  @override
  String get s3 =>
      'Obliga al zorro a examinar forensemente cada galleta en la puerta';
  @override
  String get def => 'Enseña al zorro a rechazar las galletas malas';
}

// Path: settings.commitPreview.title.descriptive
class _Translations$settings$commitPreview$title$descriptive$es
    extends Translations$settings$commitPreview$title$descriptive$en {
  _Translations$settings$commitPreview$title$descriptive$es._(
    TranslationsEs root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'el zorro ahora elige las galletas';
  @override
  String get s2 => 'Rutina de inspección de galletas, grabada en el zorro';
  @override
  String get s3 =>
      'Forense de escrutinio de galletas, incrustada en el zorro por repetición';
  @override
  String get def => 'Protocolo de olfateo de galletas, instalado en el zorro';
}

// Path: settings.commitPreview.title.narrative
class _Translations$settings$commitPreview$title$narrative$es
    extends Translations$settings$commitPreview$title$narrative$en {
  _Translations$settings$commitPreview$title$narrative$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'el zorro empezó a saltarse las galletas que olían mal';
  @override
  String get s2 => 'Me senté con el zorro y repasamos qué galletas rechazar';
  @override
  String get s3 =>
      'Pasé buena parte de una tarde convenciendo al zorro de que no toda galleta ofrecida es, de buena fe, una galleta';
  @override
  String get def =>
      'Le pedí al zorro que olfateara las galletas antes de comérselas';
}

// Path: settings.commitPreview.base.verbLed
class _Translations$settings$commitPreview$base$verbLed$es
    extends Translations$settings$commitPreview$base$verbLed$en {
  _Translations$settings$commitPreview$base$verbLed$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'El zorro echa un vistazo. Lo que huele raro se queda.';
  @override
  String get s2 =>
      'El zorro inspecciona cada token, rechaza lo que huele mal y anota el rechazo en el porche.';
  @override
  String get s3 =>
      'El zorro rodea cada token, olfatea el aire desde tres ángulos, rechaza los que huelen mal y espera un momento para asegurarse de que el rechazo se sostiene.';
  @override
  String get def =>
      'El zorro ahora olfatea cada token y rechaza con cortesía los sospechosos.';
}

// Path: settings.commitPreview.base.descriptive
class _Translations$settings$commitPreview$base$descriptive$es
    extends Translations$settings$commitPreview$base$descriptive$en {
  _Translations$settings$commitPreview$base$descriptive$es._(
    TranslationsEs root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Un pase suave sobre los raros, más o menos.';
  @override
  String get s2 =>
      'Un rechazo documentado en cada token de mal olor, emitido desde el porche y anotado.';
  @override
  String get s3 =>
      'Un rechazo notariado por cada token de mal olor, emitido desde el porche con una pata levantada y la otra quieta.';
  @override
  String get def =>
      'Un rechazo cortés a los tokens sospechosos, emitido desde el porche.';
}

// Path: settings.commitPreview.base.narrative
class _Translations$settings$commitPreview$base$narrative$es
    extends Translations$settings$commitPreview$base$narrative$en {
  _Translations$settings$commitPreview$base$narrative$es._(TranslationsEs root)
    : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'El zorro simplemente dejó de comerse los raros. Fácil.';
  @override
  String get s2 =>
      'Antes cada token pasaba sin mucho pensarlo; ahora hay una pausa, un vistazo como es debido y un rechazo para los que no encajan.';
  @override
  String get s3 =>
      'Antes cada token pasaba sin pensarlo. Ahora: una pausa. El aire, aspirado. El aire, retenido. El zorro observa las tablas del porche por si tienen ese pequeño temblor que a veces aparece cuando algo va mal, y solo entonces toma la decisión.';
  @override
  String get def =>
      'Antes cada token se tragaba sin ceremonia; ahora primero hay un olfateo.';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class _Translations$settings$commitPreview$balancedSuffix$verbLed$es
    extends Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  _Translations$settings$commitPreview$balancedSuffix$verbLed$es._(
    TranslationsEs root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' El porche está bien. El patio, lo que sea.';
  @override
  String get s2 =>
      ' El porche se barre tras cada rechazo; el barro del patio se permite dentro del horario publicado.';
  @override
  String get s3 =>
      ' El porche se barre y se rebarre; el barro del patio se cataloga por huella y clima, y el zorro se queda en el umbral más rato que antes.';
  @override
  String get def =>
      ' El porche se mantiene limpio; el patio conserva sus derechos de barro.';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class _Translations$settings$commitPreview$balancedSuffix$descriptive$es
    extends Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  _Translations$settings$commitPreview$balancedSuffix$descriptive$es._(
    TranslationsEs root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' El porche bien. El patio hace cosas de patio.';
  @override
  String get s2 =>
      ' El porche como zona limpia de evidencia; el patio como zona de barro designada, con horario publicado.';
  @override
  String get s3 =>
      ' El porche como sala limpia con grado de evidencia; el patio como archivo de barro catalogado; el umbral como el lugar donde el zorro se para y piensa demasiado.';
  @override
  String get def =>
      ' Porche limpio; derechos de barro preservados en el patio.';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class _Translations$settings$commitPreview$balancedSuffix$narrative$es
    extends Translations$settings$commitPreview$balancedSuffix$narrative$en {
  _Translations$settings$commitPreview$balancedSuffix$narrative$es._(
    TranslationsEs root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' El porche estaba bien. El patio, quién sabe.';
  @override
  String get s2 =>
      ' El porche se mantuvo limpio después; el zorro se retiró al patio, que es donde ocurre el pensar.';
  @override
  String get s3 =>
      ' El porche se fregó dos veces esa noche. El zorro recorrió el patio despacio, se detuvo en el mismo poste de la cerca de siempre y miró hacia el porche como si el porche le debiera algo.';
  @override
  String get def =>
      ' El porche se mantiene limpio, aunque el patio sigue ganando en dignidad.';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class _Translations$settings$commitPreview$everythingSuffix$verbLed$es
    extends Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  _Translations$settings$commitPreview$everythingSuffix$verbLed$es._(
    TranslationsEs root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Ámbar está ahí. La deriva deriva. La espina pincha si hace falta. Casi siempre nada.';
  @override
  String get s2 =>
      ' Ámbar retiene cada aroma para revisión. La deriva lleva el aire del día hacia la espina de la puerta, que marca cada rechazo para el recuento de la tarde.';
  @override
  String get s3 =>
      ' Ámbar retiene cada aroma y le da un peso distinto según la hora. La deriva atraviesa el porche en ángulos que no deberían importar pero importan. La espina de la puerta pincha una vez por los rechazos y dos veces por los que el zorro casi pasa por alto, y el zorro nota la diferencia aunque nadie más lo haga.';
  @override
  String get def =>
      ' Ámbar retiene el aroma. La deriva lo mueve. La espina de la puerta atrapa lo que no debería pasar.';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class _Translations$settings$commitPreview$everythingSuffix$descriptive$es
    extends
        Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  _Translations$settings$commitPreview$everythingSuffix$descriptive$es._(
    TranslationsEs root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Ámbar en el poste. Deriva en el aire. Espina en la puerta. Bien.';
  @override
  String get s2 =>
      ' Ámbar como testigo de aroma designado; la deriva como ambiente registrado; las marcas de la espina como el registro de rechazos del día, cuadrado al anochecer.';
  @override
  String get s3 =>
      ' Ámbar como testigo de aroma cuyo silencio es en sí mismo una lectura; la deriva como un ambiente con patrón que se mueve mal los días en que algo va mal; la espina como contadora de la puerta, cuyas marcas el zorro revisa antes de dormir y de nuevo antes del alba.';
  @override
  String get def =>
      ' Ámbar como testigo de aroma; la deriva como contexto ambiental; la espina como la marca callada de rechazo de la puerta.';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class _Translations$settings$commitPreview$everythingSuffix$narrative$es
    extends Translations$settings$commitPreview$everythingSuffix$narrative$en {
  _Translations$settings$commitPreview$everythingSuffix$narrative$es._(
    TranslationsEs root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsEs _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Ámbar andaba por ahí. La deriva iba y venía. La espina hizo su cosa callada. Da igual, todo tranquilo.';
  @override
  String get s2 =>
      ' Ámbar llevó el registro de aromas del día, la deriva se anotó por dirección y hora, y las marcas de la espina se contaron y refrendaron desde el porche.';
  @override
  String get s3 =>
      ' Ámbar llevó el registro de aromas, pero el zorro jura que pesa más ciertas mañanas. La deriva atravesó el porche como siempre lo hace, es decir, mal los días que importan. La espina de la puerta marcó cada rechazo; el zorro salió al primer rayo de luz a contarlos, como se cuentan los escalones que ya has contado.';
  @override
  String get def =>
      ' Ámbar guardó el registro de aromas, la deriva movió el aire, y la espina de la puerta atrapó lo que había que atrapar.';
}
