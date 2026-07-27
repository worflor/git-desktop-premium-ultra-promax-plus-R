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
class TranslationsPtBr extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsPtBr({
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
             locale: AppLocale.ptBr,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <pt-BR>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final TranslationsPtBr _root = this; // ignore: unused_field

  @override
  TranslationsPtBr $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsPtBr(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$app$pt_BR app = _Translations$app$pt_BR._(_root);
  @override
  late final _Translations$backend$pt_BR backend =
      _Translations$backend$pt_BR._(_root);
  @override
  late final _Translations$branches$pt_BR branches =
      _Translations$branches$pt_BR._(_root);
  @override
  late final _Translations$changes$pt_BR changes =
      _Translations$changes$pt_BR._(_root);
  @override
  late final _Translations$common$pt_BR common = _Translations$common$pt_BR._(
    _root,
  );
  @override
  late final _Translations$diff$pt_BR diff = _Translations$diff$pt_BR._(_root);
  @override
  late final _Translations$filament$pt_BR filament =
      _Translations$filament$pt_BR._(_root);
  @override
  late final _Translations$history$pt_BR history =
      _Translations$history$pt_BR._(_root);
  @override
  late final _Translations$historySurgery$pt_BR historySurgery =
      _Translations$historySurgery$pt_BR._(_root);
  @override
  late final _Translations$onboarding$pt_BR onboarding =
      _Translations$onboarding$pt_BR._(_root);
  @override
  late final _Translations$orrery$pt_BR orrery = _Translations$orrery$pt_BR._(
    _root,
  );
  @override
  late final _Translations$palette$pt_BR palette =
      _Translations$palette$pt_BR._(_root);
  @override
  late final _Translations$releaseNotes$pt_BR releaseNotes =
      _Translations$releaseNotes$pt_BR._(_root);
  @override
  late final _Translations$repoSummary$pt_BR repoSummary =
      _Translations$repoSummary$pt_BR._(_root);
  @override
  late final _Translations$review$pt_BR review = _Translations$review$pt_BR._(
    _root,
  );
  @override
  late final _Translations$settings$pt_BR settings =
      _Translations$settings$pt_BR._(_root);
  @override
  late final _Translations$sync$pt_BR sync = _Translations$sync$pt_BR._(_root);
  @override
  late final _Translations$xray$pt_BR xray = _Translations$xray$pt_BR._(_root);
}

// Path: app
class _Translations$app$pt_BR extends Translations$app$en {
  _Translations$app$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get panelSettings => 'Configurações';
  @override
  String get panelReleaseNotes => 'Notas de Versão';
  @override
  String get panelFilamentFindings => 'Achados do Filament';
  @override
  String get filamentFindingsUpper => 'ACHADOS DO FILAMENT';
  @override
  late final _Translations$app$cheatsheet$pt_BR cheatsheet =
      _Translations$app$cheatsheet$pt_BR._(_root);
  @override
  String get commandPaletteTooltip => 'Paleta de comandos   /';
  @override
  String get newDeskFallback => 'nova Desk';
  @override
  String get deskFallback => 'Desk';
  @override
  String get currentDeskFallback => 'atual';
  @override
  String get noRepositoryOpen => 'Nenhum repositório aberto';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Não foi possível abrir como Desk: ${error}';
  @override
  String couldNotDetectForge({required Object error}) =>
      'Não foi possível detectar o forge: ${error}';
  @override
  String get cannotFetchPrNoForge =>
      'Não é possível buscar o PR: forge não detectado para este repo.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      'Sobrescrever ${ref} com o mais recente do remoto?';
  @override
  String get overwrite => 'Sobrescrever';
  @override
  String couldntFetchPr({required Object error}) =>
      'Não foi possível buscar o PR: ${error}';
  @override
  String get promoteDeskToPr => 'Promover Desk a PR';
  @override
  String get applyToMain => 'Aplicar na main';
  @override
  String updateDeskFrom({required Object target, required Object source}) =>
      'Atualizar ${target} a partir de ${source}';
  @override
  String bringChangesFromHere({required Object source}) =>
      'Trazer mudanças de ${source} para cá';
  @override
  String get editLocalPr => 'Editar PR local';
  @override
  String get discardLocalPr => 'Descartar PR local';
  @override
  String get closeDesk => 'Fechar Desk';
  @override
  String couldntPromote({required Object error}) =>
      'Não foi possível promover: ${error}';
  @override
  String get commitOrShelveBeforeApplying =>
      'Faça commit ou guarde na prateleira as mudanças da Desk antes de aplicar.';
  @override
  String get couldNotResolveMainWorktree =>
      'Não foi possível resolver o caminho do worktree principal.';
  @override
  String couldntPromoteDesk({required Object error}) =>
      'Não foi possível promover a Desk: ${error}';
  @override
  String get couldntDetermineBaseBranch =>
      'Não foi possível determinar o branch base desta Desk.';
  @override
  String prBaseHeadSame({required Object branch}) =>
      'A base e o head do PR são o mesmo branch (${branch}) — nada a aplicar.';
  @override
  String appliedBranchToBase({required Object branch, required Object base}) =>
      'Aplicado ${branch} em ${base}';
  @override
  String updatedDeskToDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
    n,
    one: '${target} atualizado para ${source} (${n} commit).',
    other: '${target} atualizado para ${source} (${n} commits).',
  );
  @override
  String get fastForwardFailedFallback =>
      'O fast-forward não conseguiu aterrissar limpo — mostrando uma prévia em patch.';
  @override
  String deskAheadOfDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
    n,
    one: '${target} está ${n} commit à frente de ${source}.',
    other: '${target} está ${n} commits à frente de ${source}.',
  );
  @override
  String deskUpToDate({required Object target, required Object source}) =>
      '${target} já está em dia com ${source}.';
  @override
  String uncommittedPreviewNotice({required Object target}) =>
      'Mudanças sem commit em ${target} — mostrando prévia como patch.';
  @override
  String updateDeskFromLower({
    required Object target,
    required Object source,
  }) => 'atualizar ${target} a partir de ${source}';
  @override
  String noUpdatesToBringFrom({required Object source}) =>
      'Nenhuma atualização a trazer de ${source}.';
  @override
  String get updatePrepFailed => 'Falha ao preparar a atualização';
  @override
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => 'trazer mudanças de ${source} para ${target}';
  @override
  String noPatchableChanges({required Object source, required Object target}) =>
      'Nenhuma mudança aplicável em patch para trazer de ${source} para ${target}.';
  @override
  String get patchPrepFailed => 'Falha ao preparar o patch';
  @override
  String failureWithError({required Object label, required Object error}) =>
      '${label}: ${error}';
  @override
  String get titleHint => 'título';
  @override
  String get bodyHint => 'corpo';
  @override
  String get bodyOptionalHint => 'corpo (opcional)';
  @override
  String get draftLower => 'rascunho';
  @override
  String get cancelLower => 'cancelar';
  @override
  String get saveLower => 'salvar';
  @override
  String couldntSave({required Object error}) =>
      'Não foi possível salvar: ${error}';
  @override
  String get stashedNoOtherDesk =>
      'Mudanças guardadas no stash — nenhuma outra Desk para aplicá-las. Use git stash pop para recuperar.';
  @override
  String get suggestedSource => 'origem sugerida';
  @override
  String tooltipModifiedCount({required Object n}) => '${n} modificados';
  @override
  String tooltipAheadCount({required Object n}) => '${n} à frente';
  @override
  String tooltipBehindCount({required Object n}) => '${n} atrás';
  @override
  String get focusedEdits => 'edições focadas';
  @override
  String get editsSpreadAcrossSubsystems =>
      'edições espalhadas por subsistemas';
  @override
  String get editsTouchingManySubsystems =>
      'edições tocando muitos subsistemas';
  @override
  String get focusedBranch => 'branch focado';
  @override
  String get branchSpansMultipleSubsystems =>
      'o branch abrange múltiplos subsistemas';
  @override
  String get structurallyDivergentFromMainline =>
      'estruturalmente divergente da linha principal';
  @override
  String get localPr => 'PR local';
  @override
  String lastTouched({required Object time}) => 'tocado por último ${time}';
  @override
  String driftGroupCount({required Object n, required Object dir}) =>
      '${n} em ${dir}';
  @override
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';
  @override
  String get uncommittedChanges => 'Mudanças sem commit';
  @override
  String get closeDeskQuestion => 'Fechar Desk?';
  @override
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} arquivo sem commit.',
        other: '${n} arquivos sem commit.',
      );
  @override
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} commit à frente da main.',
        other: '${n} commits à frente da main.',
      );
  @override
  String get willRemoveWorktreeDirectory =>
      'Isto vai remover o diretório do worktree.';
  @override
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} arquivo alterado',
        other: '${n} arquivos alterados',
      );
  @override
  String get shelveHere => 'Guardar aqui';
  @override
  String get discardAndClose => 'Descartar e fechar';
  @override
  String get noRepository => 'sem repositório';
  @override
  String get issuePromotedToRemote => 'Issue promovida para o remoto.';
  @override
  String get pushedToRemote => 'Push para o remoto feito.';
  @override
  String get pulledFromRemote => 'Pull do remoto feito.';
  @override
  String get remoteIssueNotFound => 'issue remota não encontrada';
  @override
  String importedIssueLocally({required Object id}) =>
      '#${id} importada localmente.';
  @override
  String get issueAbandoned => 'Issue abandonada.';
  @override
  String get abandonIssue => 'Abandonar issue';
  @override
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      'Remover permanentemente a issue local #${id}? Isto exclui sua ref e não pode ser desfeito.';
  @override
  String get abandon => 'Abandonar';
  @override
  String publishedBranch({required Object branch}) => '${branch} publicado.';
  @override
  String get publishingEllipsis => 'Publicando…';
  @override
  String get publish => 'Publicar';
  @override
  String get noRemoteConfigured =>
      'Nenhum remoto configurado para este repositório.';
  @override
  String get jumpToDesk => 'Ir para a Desk';
  @override
  String get arrowOpen => '→ abrir';
  @override
  String get openOnANewDesk => 'Abrir em uma nova Desk';
  @override
  String get plusDesk => '+ Desk';
  @override
  String get plusSpace => '+ ';
  @override
  String get newBranchNameHint => 'nome-do-novo-branch';
  @override
  String get escLower => 'esc';
  @override
  String get plusNewDesk => '+ nova Desk';
  @override
  String get fromHeadEllipsis => 'a partir do HEAD...';
  @override
  String get viewAllBranches => 'Ver todos os branches';
  @override
  String get issuesLower => 'issues';
  @override
  String get newIssueLower => 'nova issue';
  @override
  String get noneLinked => 'nenhuma vinculada';
  @override
  String get noOpenIssues => 'nenhuma issue aberta';
  @override
  String get createAndPushLower => 'criar + push';
  @override
  String get createLower => 'criar';
  @override
  String get remoteLower => 'remoto';
  @override
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';
  @override
  String get promoteToRemote => 'Promover para o remoto';
  @override
  String get pushToRemote => 'Push para o remoto';
  @override
  String get pullFromRemote => 'Pull do remoto';
  @override
  String get importLabel => 'Importar';
  @override
  String get failedToCreateRepository => 'Falha ao criar o repositório.';
  @override
  String get openRepositoryLower => 'abrir repositório';
  @override
  String get newRepositoryLower => 'novo repositório';
  @override
  String get back => 'Voltar';
  @override
  String get openRepositoryDialogTitle => 'Abrir Repositório';
  @override
  String get createRepositoryDialogTitle => 'Criar Repositório';
  @override
  String get cloneTargetDialogTitle => 'Destino do Clone';
  @override
  String get cloneToDialogTitle => 'Clonar para';
  @override
  String get exportToDialogTitle => 'Exportar para';
  @override
  String get createFromTemplateInDialogTitle => 'Criar a partir de template em';
  @override
  String get notAGitRepoInitConfirm =>
      'Não é um repositório git. Inicializar um aqui?';
  @override
  String get repositoryUrlRequired => 'URL do repositório obrigatória.';
  @override
  String get failedToCloneRepository => 'Falha ao clonar o repositório.';
  @override
  String cloningEllipsis({required Object name}) => 'Clonando ${name}...';
  @override
  String get cloneCancelled => 'Clone cancelado.';
  @override
  String get noProjectsYet => 'Nenhum projeto ainda';
  @override
  String get dissolveGroup => 'Dissolver grupo';
  @override
  String get projectsHeader => 'Projetos';
  @override
  String get cloneLabel => 'Clonar';
  @override
  String get createLabel => 'Criar';
  @override
  String get openLabel => 'Abrir';
  @override
  String get repositoryUrlPlaceholder => 'URL do repositório';
  @override
  String get projectNameOrFullPathPlaceholder =>
      'nome-do-projeto ou caminho completo';
  @override
  String get pathToProjectPlaceholder => '/caminho/do/projeto';
  @override
  String get cloneToFolderPathPlaceholder => 'Caminho da pasta para clonar';
  @override
  String get switchToCreateRepo => 'Mudar para Criar repo';
  @override
  String get explorer => 'Explorador';
  @override
  String get terminal => 'Terminal';
  @override
  String get cloneUrl => 'URL de clone';
  @override
  String get copyPath => 'Copiar caminho';
  @override
  String get export => 'Exportar';
  @override
  String get readme => 'README';
  @override
  String get duplicate => 'Duplicar';
  @override
  String get template => 'Template';
  @override
  String get forgetThisProject => 'Esquecer este projeto';
  @override
  String get aiKindCommitMessage => 'mensagem de commit';
  @override
  String get aiKindReview => 'review';
  @override
  String get aiKindMuse => 'muse';
  @override
  String get aiKindPresent => 'apresentar';
  @override
  String get aiKindDebug => 'debug';
  @override
  String aiStatusRunning({required Object kind}) => '${kind} rodando';
  @override
  String aiStatusFailedUnread({required Object kind}) =>
      '${kind} falhou (não lido)';
  @override
  String aiStatusReadyUnread({required Object kind}) =>
      '${kind} pronto (não lido)';
  @override
  String get filesLower => 'arquivos';
  @override
  String get commitsLower => 'commits';
  @override
  String get undoLabel => 'Desfazer';
  @override
  String get goLabel => 'vai';
  @override
  String countdownSeconds({required Object n}) => '${n}s';
  @override
  String get collapseGlyph => '▲ recolher';
  @override
  String moreLinesGlyph({required Object n}) => '▼ +${n} linhas';
}

// Path: backend
class _Translations$backend$pt_BR extends Translations$backend$en {
  _Translations$backend$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$backend$ops$pt_BR ops =
      _Translations$backend$ops$pt_BR._(_root);
  @override
  late final _Translations$backend$mergeOutcome$pt_BR mergeOutcome =
      _Translations$backend$mergeOutcome$pt_BR._(_root);
}

// Path: branches
class _Translations$branches$pt_BR extends Translations$branches$en {
  _Translations$branches$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get runningAiReview => 'Rodando review de AI…';
  @override
  String prNumberLabel({required Object number}) => 'PR #${number}';
  @override
  String get findings => 'ACHADOS';
  @override
  String get observations => 'OBSERVAÇÕES';
  @override
  String get renameEllipsis => 'Renomear…';
  @override
  String get publish => 'Publicar';
  @override
  String publishFailed({required Object error}) =>
      'Falha ao publicar: ${error}';
  @override
  String couldntOpenDesk({required Object error}) =>
      'Não foi possível abrir a Desk: ${error}';
  @override
  String syncFailed({required Object error}) =>
      'Falha na sincronização: ${error}';
  @override
  String get renameBranchTitle => 'Renomear branch';
  @override
  String get newNameHint => 'novo nome';
  @override
  String get rename => 'Renomear';
  @override
  String invalidBranchName({required Object name}) =>
      '\'${name}\' não é um nome de branch válido.';
  @override
  String renameFailed({required Object error}) => 'Falha ao renomear: ${error}';
  @override
  String deletingBranch({required Object name}) => 'Excluindo ${name}';
  @override
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '\'${name}\' está aberto na Desk \'${desk}\'.';
  @override
  String get openDesk => 'Abrir Desk';
  @override
  String openInDeskShort({required Object desk}) => 'abrir na Desk \'${desk}\'';
  @override
  String get couldNotPinBranch =>
      'não foi possível fixar a ponta do branch; exclusão ignorada';
  @override
  String get couldNotPinTag =>
      'não foi possível fixar a tag; exclusão ignorada';
  @override
  String deletingTag({required Object name}) => 'Excluindo tag ${name}';
  @override
  String get applyToActiveChanges => 'Aplicar às mudanças ativas…';
  @override
  String get couldNotLoadPrDiff => 'Não foi possível carregar o diff do PR.';
  @override
  String prSourceLabel({required Object number, required Object title}) =>
      'PR #${number}: ${title}';
  @override
  String mergeIntoDesk({required Object branch}) => 'Fazer merge em ${branch}…';
  @override
  String get checkoutThisPr => 'Checkout deste PR';
  @override
  String get mergeIntoNewDesk => 'Fazer merge em nova Desk…';
  @override
  String get pushToForge => 'Push para o forge';
  @override
  String get linkToIssue => 'Vincular a issue…';
  @override
  String get gitPatch => '↓ git patch';
  @override
  String get copyBranchName => 'Copiar nome do branch';
  @override
  String copiedRef({required Object ref}) => '"${ref}" copiado';
  @override
  String get reviewPr => 'Revisar PR';
  @override
  String get openInBrowser => 'Abrir no navegador';
  @override
  String get markAsRead => 'Marcar como lido';
  @override
  String get markAsUnread => 'Marcar como não lido';
  @override
  String get replaceLocalCommitsTitle => 'Substituir commits locais?';
  @override
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref} tem commits locais que não estão no head remoto do PR. Atualizá-lo vai substituí-los pelo mais recente do remoto.';
  @override
  String get update => 'Atualizar';
  @override
  String couldntFetchPr({required Object error}) =>
      'Não foi possível buscar o PR: ${error}';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Não foi possível abrir como Desk: ${error}';
  @override
  String couldntOpenInBrowser({required Object error}) =>
      'Não foi possível abrir no navegador: ${error}';
  @override
  String get noIssuesYetLocal =>
      'Nenhuma issue ainda. Abra uma no upstream, ou use "+ nova issue local" na lente de issues.';
  @override
  String get remotePrsLinkLocalOnly =>
      'PRs remotos só podem vincular a issues locais. Crie uma com "+ nova issue local".';
  @override
  String linkPrToIssues({required Object number}) =>
      'Vincular PR #${number} a issue(s)';
  @override
  String get noPrsYetLocal =>
      'Nenhum PR ainda. Abra um no upstream, ou promova uma Desk a PR.';
  @override
  String get remoteIssuesLinkLocalOnly =>
      'Issues remotas só podem vincular a PRs locais. Promova uma Desk a PR primeiro.';
  @override
  String linkIssueToPrs({required Object number}) =>
      'Vincular issue #${number} a PR(s)';
  @override
  String couldntToggleLink({required Object error}) =>
      'Não foi possível alternar o vínculo: ${error}';
  @override
  String get openPatchDialogTitle => 'Abrir patch (.patch / .diff)';
  @override
  String get clipboardNoText => 'A área de transferência não tem texto.';
  @override
  String get clipboardPatchLabel => 'clipboard.patch';
  @override
  String failedToOpenPatch({required Object error}) =>
      'Falha ao abrir o patch: ${error}';
  @override
  String get patchEmptyOrUnparseable =>
      'O patch está vazio ou não pode ser interpretado.';
  @override
  String get prPushedToForge => 'PR enviado para o forge.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      'Sobrescrever ${ref} com o mais recente do remoto?';
  @override
  String get overwrite => 'Sobrescrever';
  @override
  String get loadingBranchesTitle => 'Carregando branches';
  @override
  String get loadingBranchesMessage => 'Lendo branches e tags locais.';
  @override
  String get branchesUnavailableTitle => 'Branches indisponíveis';
  @override
  String get filterPullRequestsHint => 'filtrar pull requests…';
  @override
  String get filterIssuesHint => 'filtrar issues…';
  @override
  String get branchNameHint => 'nome do branch';
  @override
  String get tagsNewestFirst => 'tags, mais recentes primeiro';
  @override
  String get tagsOldestFirst => 'tags, mais antigas primeiro';
  @override
  String get flipSortDirection => 'inverter direção da ordenação';
  @override
  String get readingPullRequests => 'Lendo pull requests…';
  @override
  String get noOpenPullRequests => 'Nenhum pull request aberto';
  @override
  String get noPullRequestsHint =>
      'Abra um a partir de um branch, ou promova uma Desk.';
  @override
  String get noPrsMatchFilters => 'Nenhum PR bate com esses filtros';
  @override
  String get toggleFiltersRowAbove => 'Desligue os filtros na linha acima.';
  @override
  String get issuesNewestFirst => 'issues, mais recentes primeiro';
  @override
  String get issuesOldestFirst => 'issues, mais antigas primeiro';
  @override
  String get issuesHeading => 'ISSUES';
  @override
  String get readingIssuesLower => 'lendo issues…';
  @override
  String get noOpenIssues => 'Nenhuma issue aberta';
  @override
  String get noIssuesHint => '+ nova para acompanhar trabalho e bugs.';
  @override
  String get nothingMatches => 'Nada bate';
  @override
  String get toggleFiltersAbove => 'Desligue os filtros acima.';
  @override
  String get bucketFresh => 'FRESCO';
  @override
  String get bucketThisWeek => 'ESTA SEMANA';
  @override
  String get bucketStalled => 'PARADO';
  @override
  String get bucketOlder => 'MAIS ANTIGO';
  @override
  String get couldNotResolveMainWorktree =>
      'Não foi possível resolver o caminho do worktree principal.';
  @override
  String couldntSubmitReview({required Object error}) =>
      'Não foi possível enviar o review: ${error}';
  @override
  String get reviewAiNotAvailable =>
      'O review por AI ainda não está disponível.';
  @override
  String get noReviewModelConfigured => 'Nenhum modelo de review configurado.';
  @override
  String get deskFallback => 'Desk';
  @override
  String deskUncommittedChanges({
    required num n,
    required Object branch,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
    n,
    one:
        '${branch} tem ${n} mudança sem commit — faça commit ou stash primeiro.',
    other:
        '${branch} tem ${n} mudanças sem commit — faça commit ou stash primeiro.',
  );
  @override
  String get targetDeskNoBranch => 'A Desk de destino não tem branch.';
  @override
  String mergePrIntoDesk({required Object number, required Object branch}) =>
      'Fazer merge do PR #${number} em ${branch}';
  @override
  String get conflictCheckUnavailableVersion =>
      'Checagem de conflito indisponível — git 2.38+ necessário';
  @override
  String get conflictCheckUnavailable => 'Checagem de conflito indisponível';
  @override
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'VAI CONFLITAR · ${n} arquivo',
        other: 'VAI CONFLITAR · ${n} arquivos',
      );
  @override
  String plusMore({required Object n}) => '+${n} mais';
  @override
  String get rebase => 'Rebase';
  @override
  String get squash => 'Squash';
  @override
  String get mergeCommit => 'Commit de merge';
  @override
  String noDeskForBranch({required Object branch}) =>
      'Nenhuma Desk encontrada para o branch ${branch}';
  @override
  String get mergeAnyway => 'Fazer merge mesmo assim';
  @override
  String get readingIssues => 'Lendo issues…';
  @override
  String get openUpstreamOrLocal => 'Abra uma no upstream, ou abra uma local.';
  @override
  String get noIssuesMatchFilters => 'Nenhuma issue bate com esses filtros';
  @override
  String couldntCreateIssue({required Object error}) =>
      'Não foi possível criar a issue: ${error}';
  @override
  String get promoteToRemote => 'Promover para o remoto';
  @override
  String get pushToRemote => 'Push para o remoto';
  @override
  String get pullFromRemote => 'Pull do remoto';
  @override
  String get import => 'Importar';
  @override
  String get linkToPr => 'Vincular a PR…';
  @override
  String get abandon => 'Abandonar';
  @override
  String get issuePromotedToRemote => 'Issue promovida para o remoto.';
  @override
  String get issuePushedToRemote => 'Push para o remoto feito.';
  @override
  String get issuePulledFromRemote => 'Pull do remoto feito.';
  @override
  String issueImportedLocally({required Object number}) =>
      '#${number} importada localmente.';
  @override
  String get abandonIssueTitle => 'Abandonar issue';
  @override
  String abandonIssueMessage({required Object id}) =>
      'Remover permanentemente a issue local #${id}? Isto exclui sua ref e não pode ser desfeito.';
  @override
  String couldntAbandon({required Object error}) =>
      'Não foi possível abandonar: ${error}';
  @override
  String couldntPostComment({required Object error}) =>
      'Não foi possível postar o comentário: ${error}';
  @override
  String couldntCloseIssue({required Object error}) =>
      'Não foi possível fechar a issue: ${error}';
  @override
  String couldntAddLabel({required Object error}) =>
      'Não foi possível adicionar a label: ${error}';
  @override
  String get lensBranches => 'BRANCHES';
  @override
  String get lensPrs => 'PRs';
  @override
  String get patchUp => '↑ patch';
  @override
  String get syncRibbon => '⇅ sincronizar';
  @override
  String get kbHeading => 'TECLADO';
  @override
  String get kbNavigateRows => 'navegar linhas';
  @override
  String get kbExpandCollapse => 'expandir / recolher a linha em foco';
  @override
  String get kbCheckoutPr => 'checkout local do PR em foco';
  @override
  String get kbApproveReview => 'aprovar · review';
  @override
  String get kbRequestChanges => 'solicitar mudanças';
  @override
  String get kbFocusSearch => 'focar busca';
  @override
  String get kbSwitchLens => 'trocar lente (branches · prs)';
  @override
  String get kbToggleOverlay => 'alternar esta sobreposição';
  @override
  String get kbPressToDismiss => 'pressione em qualquer lugar para dispensar';
  @override
  String get overrideScarTooltip =>
      'mesclado com checagens falhando ou sem um review de aprovação — investigue primeiro na linha de fogo';
  @override
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} arquivo se sobrepõe ao seu trabalho sem commit',
        other: '${n} arquivos se sobrepõem ao seu trabalho sem commit',
      );
  @override
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '#${pr}  (${n} arquivo)',
        other: '#${pr}  (${n} arquivos)',
      );
  @override
  String get prStateDraft => 'RASCUNHO';
  @override
  String get localBadge => 'LOCAL';
  @override
  String get myReviewPending => 'seu review pendente';
  @override
  String get myReviewApproved => 'você ✓';
  @override
  String get myReviewChangesRequested => 'você ✗ solicitou mudanças';
  @override
  String get myReviewCommented => 'você comentou';
  @override
  String get myReviewDefault => 'você';
  @override
  String tailCommentsAuthor({required Object count}) =>
      '${count} comentários · último do autor mostrado';
  @override
  String get tailLastComment => 'último comentário';
  @override
  String tailLastReviewState({required Object state}) =>
      'último review · ${state}';
  @override
  String get tailLastReview => 'último review';
  @override
  String tailLastCheckState({required Object state}) =>
      'última checagem · ${state}';
  @override
  String get tailLastCommit => 'último commit';
  @override
  String get tailLastActivity => 'última atividade';
  @override
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'fecha ${n} issue — clique para pular',
        other: 'fecha ${n} issues — clique para pular',
      );
  @override
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'endereçada por ${n} PR — clique para pular',
        other: 'endereçada por ${n} PRs — clique para pular',
      );
  @override
  String get checksLabel => 'checagens';
  @override
  String get reviewersLabel => 'revisores';
  @override
  String get conflictsLabel => 'conflitos';
  @override
  String exportFailed({required Object error}) =>
      'Falha na exportação: ${error}';
  @override
  String get readingFiles => 'lendo arquivos…';
  @override
  String get noDetailAvailable => 'nenhum detalhe disponível';
  @override
  String get noFilesReported => 'nenhum arquivo reportado';
  @override
  String get readingGitHistory => 'lendo histórico do git…';
  @override
  String get knowsThisCode => 'conhece este código';
  @override
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} commit nesses arquivos no último ano',
        other: '${n} commits nesses arquivos no último ano',
      );
  @override
  String get willFight => 'VAI BRIGAR';
  @override
  String orbitalPartnerCos({required Object cos}) =>
      'parceiro orbital — cos ${cos}';
  @override
  String get orbitLabel => 'órbita';
  @override
  String get touchesYourLocalWork => 'TOCA SEU TRABALHO LOCAL';
  @override
  String get mergingWillConflict =>
      'o merge provavelmente vai conflitar com suas mudanças sem commit';
  @override
  String get closesHeading => 'FECHA';
  @override
  String get filesHeading => 'ARQUIVOS';
  @override
  String get orientAligned => 'alinhado';
  @override
  String get orientAdjacent => 'adjacente';
  @override
  String get orientOrthogonal => 'ortogonal';
  @override
  String shapeField({required Object v}) => 'campo ${v}';
  @override
  String shapeSource({required Object v}) => 'fonte ${v}';
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
  String shapeStress({required Object v}) => 'estresse ${v}';
  @override
  String shapeWit({required Object v}) => 'wit ${v}';
  @override
  String resonanceReadout({required Object v}) => 'ressonância ${v}';
  @override
  String ghostFileTooltip({required Object path}) =>
      'geralmente move junto com os arquivos deste PR\n(${path})';
  @override
  String get prStateDraftLower => 'rascunho';
  @override
  String get keystoneTooltip => 'pedra-chave — arquivo-ponte de todo o repo';
  @override
  String get reviewNoteHint => 'deixe uma nota (opcional)…';
  @override
  String get reviewComment => 'comentar';
  @override
  String get reviewRequestChanges => 'solicitar mudanças';
  @override
  String get reviewApprove => '✓ aprovar';
  @override
  String get actionPatchDown => '↓ patch';
  @override
  String get actionPrReview => '✦ review de pr';
  @override
  String get actionOpenAsDesk => '⊞ abrir como Desk';
  @override
  String get actionCheckout => '[c] checkout';
  @override
  String get actionMerge => '[m] merge ▾';
  @override
  String get mergeMenuMergeCommit => 'commit de merge';
  @override
  String get mergeMenuSquash => 'squash e merge';
  @override
  String get mergeMenuRebase => 'rebase e merge';
  @override
  String get deleteBranchAfter => 'excluir branch depois';
  @override
  String checkDurationSec({required Object n}) => '${n}s';
  @override
  String checkDurationMin({required Object m, required Object s}) =>
      '${m}m ${s}s';
  @override
  String assignedTo({required Object names}) => 'atribuído: ${names}';
  @override
  String issueConvLine({required Object n, required Object time}) =>
      '${n} conv · ${time}';
  @override
  String get readingThread => 'lendo thread…';
  @override
  String get addressedByHeading => 'ENDEREÇADA POR';
  @override
  String get descriptionHeading => 'DESCRIÇÃO';
  @override
  String get threadHeading => 'THREAD';
  @override
  String get replyHint => 'responder…';
  @override
  String get assignMe => 'atribuir a mim';
  @override
  String get closeLower => 'fechar';
  @override
  String get postReply => '↩ postar';
  @override
  String get remoteProviderUnavailable => 'Provedor remoto indisponível';
  @override
  String get noRecognisedRemoteHost =>
      'Nenhum host remoto reconhecido para este repo.';
  @override
  String get corpseGone => 'sumiu';
  @override
  String get corpseAbsorbed => 'absorvido';
  @override
  String get corpseSquashed => 'squashado';
  @override
  String absorbedDeliveredIn({required Object hash}) => 'entregue em ${hash}';
  @override
  String get absorbedNoChanges => 'o merge não adiciona mudanças';
  @override
  String get corpseTagUpstreamGone => 'upstream sumiu';
  @override
  String corpseTagAbsorbed({required Object receipt}) =>
      'absorvido, ${receipt}';
  @override
  String get corpseTagSquashed => 'squashado e mesclado';
  @override
  String semanticsCurrentBranch({required Object name}) =>
      '${name}, branch atual';
  @override
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}, rastreando ${upstream}';
  @override
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}, ${tag}';
  @override
  String semanticsWorktreeOpen({required Object label}) =>
      '${label}, worktree aberto';
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
  String get crossLinkPrDraft => 'PR · rascunho';
  @override
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} issue',
        other: '${n} issues',
      );
  @override
  String get headBadge => 'HEAD';
  @override
  String trackingLine({required Object upstream}) =>
      '→ rastreando: ${upstream}';
  @override
  String get checkoutButton => 'Checkout';
  @override
  String get createBranch => 'Criar branch';
  @override
  String get newBranchName => 'Nome do novo branch';
  @override
  String newBranchNameError({required Object error}) =>
      'Nome do novo branch — ${error}';
  @override
  String get forceDelete => 'Forçar?';
  @override
  String get annotated => 'anotada';
  @override
  String get applyCheckFailed => 'apply --check falhou';
  @override
  String get openPatchFrom => 'ABRIR PATCH DE';
  @override
  String get patchFromFile => 'de arquivo…';
  @override
  String get patchFromFileHint => '.patch / .diff';
  @override
  String get patchFromClipboard => 'da área de transferência';
  @override
  String get patchFromClipboardHint => 'colar texto';
  @override
  String get patchPreviewHeading => 'PRÉVIA DO PATCH';
  @override
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';
  @override
  String get stagedDone => 'em stage.';
  @override
  String get appliedDone => 'aplicado.';
  @override
  String get opening => 'abrindo…';
  @override
  String get mergeEditor => '⇋ editor de merge';
  @override
  String get staging => 'colocando em stage…';
  @override
  String get applying => 'aplicando…';
  @override
  String get stage => 'stage';
  @override
  String get apply => 'aplicar';
  @override
  String get refineHint =>
      'refinar… (ex.: "também remova as mudanças do logger")';
  @override
  String get reverseArmedTooltip =>
      'armado — o próximo apply vai REVERTER o patch (-R)';
  @override
  String get reverseDisarmedTooltip =>
      'armar reverso (-R) — desfazer em vez de aplicar';
  @override
  String get reverseArmedLabel => '⟲ reverso ✓';
  @override
  String get reverseLabel => '⟲ reverso';
  @override
  String get untouchedHeading => '⚠ INTOCADOS';
  @override
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${count} de ${n} arquivo fora do patch',
        other: '${count} de ${n} arquivos fora do patch',
      );
  @override
  String get staysConflicted =>
      'estes arquivos vão continuar em conflito — aplicar não vai colocá-los em stage';
  @override
  String get orWith => 'OU COM';
  @override
  String get noAiModelConfigured => 'nenhum modelo de AI configurado';
  @override
  String applyWithPatchFrom({required Object label}) =>
      'aplicar com patch de ${label}';
  @override
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => 'aplicar com patch de ${label}  ·  ${model}';
  @override
  String get patching => 'aplicando patch…';
  @override
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  aplicar com patch de ${label}';
  @override
  String get orWithAnotherModel => 'ou com outro modelo';
  @override
  String get applyCheckPassed =>
      'git apply --check passou — o patch vai aplicar limpo';
  @override
  String get gitApplyCheckFailed => 'git apply --check falhou';
  @override
  String get appliesClean => 'aplica limpo';
  @override
  String get willNotApply => 'não vai aplicar';
  @override
  String get newLocalIssue => 'nova issue local';
  @override
  String get filterHint => 'filtrar…';
  @override
  String get nothingToLink => 'Nada para vincular ainda.';
  @override
  String get nothingMatchesDot => 'Nada bate.';
  @override
  String get relevantHeading => 'RELEVANTE';
  @override
  String get allHeading => 'TUDO';
  @override
  String get doneLower => 'pronto';
  @override
  String get candidateRemote => 'R';
  @override
  String get candidateLocal => 'L';
  @override
  String get newLocalIssueTitle => 'Nova issue local';
  @override
  String get titleHint => 'título';
  @override
  String get bodyHint => 'corpo (markdown)';
  @override
  String get cancelLower => 'cancelar';
  @override
  String get createLower => 'criar';
  @override
  String get deleteFailed => 'exclusão falhou';
  @override
  String reviewFailed({required Object error}) => 'Review falhou: ${error}';
  @override
  String get resolutionFailed => 'resolução falhou';
  @override
  String get patchBlocksNoCover =>
      'o modelo retornou blocos de patch que não cobriram os arquivos com falha';
  @override
  String get applyFailed => 'apply falhou';
  @override
  String get emptyOrUnparseablePatch =>
      'o modelo retornou um patch vazio ou impossível de interpretar';
  @override
  String noModelConfiguredFor({required Object label}) =>
      'nenhum modelo configurado para "${label}"';
  @override
  String get checksHeading => 'VERIFICAÇÕES';
  @override
  String get peopleHeading => 'PESSOAS';
  @override
  String get conversationHeading => 'CONVERSA';
}

// Path: changes
class _Translations$changes$pt_BR extends Translations$changes$en {
  _Translations$changes$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$usage$pt_BR usage =
      _Translations$changes$usage$pt_BR._(_root);
  @override
  late final _Translations$changes$tabs$pt_BR tabs =
      _Translations$changes$tabs$pt_BR._(_root);
  @override
  late final _Translations$changes$tabStrip$pt_BR tabStrip =
      _Translations$changes$tabStrip$pt_BR._(_root);
  @override
  late final _Translations$changes$select$pt_BR select =
      _Translations$changes$select$pt_BR._(_root);
  @override
  late final _Translations$changes$constellationToggle$pt_BR
  constellationToggle = _Translations$changes$constellationToggle$pt_BR._(
    _root,
  );
  @override
  late final _Translations$changes$nudgeChip$pt_BR nudgeChip =
      _Translations$changes$nudgeChip$pt_BR._(_root);
  @override
  late final _Translations$changes$minimap$pt_BR minimap =
      _Translations$changes$minimap$pt_BR._(_root);
  @override
  late final _Translations$changes$tagInput$pt_BR tagInput =
      _Translations$changes$tagInput$pt_BR._(_root);
  @override
  late final _Translations$changes$composer$pt_BR composer =
      _Translations$changes$composer$pt_BR._(_root);
  @override
  late final _Translations$changes$commit$pt_BR commit =
      _Translations$changes$commit$pt_BR._(_root);
  @override
  late final _Translations$changes$rebase$pt_BR rebase =
      _Translations$changes$rebase$pt_BR._(_root);
  @override
  late final _Translations$changes$editor$pt_BR editor =
      _Translations$changes$editor$pt_BR._(_root);
  @override
  late final _Translations$changes$editorTitles$pt_BR editorTitles =
      _Translations$changes$editorTitles$pt_BR._(_root);
  @override
  late final _Translations$changes$askHint$pt_BR askHint =
      _Translations$changes$askHint$pt_BR._(_root);
  @override
  late final _Translations$changes$fileMenu$pt_BR fileMenu =
      _Translations$changes$fileMenu$pt_BR._(_root);
  @override
  late final _Translations$changes$multiFileMenu$pt_BR multiFileMenu =
      _Translations$changes$multiFileMenu$pt_BR._(_root);
  @override
  late final _Translations$changes$ignoreMenu$pt_BR ignoreMenu =
      _Translations$changes$ignoreMenu$pt_BR._(_root);
  @override
  late final _Translations$changes$discard$pt_BR discard =
      _Translations$changes$discard$pt_BR._(_root);
  @override
  late final _Translations$changes$snack$pt_BR snack =
      _Translations$changes$snack$pt_BR._(_root);
  @override
  late final _Translations$changes$trace$pt_BR trace =
      _Translations$changes$trace$pt_BR._(_root);
  @override
  late final _Translations$changes$cleanTree$pt_BR cleanTree =
      _Translations$changes$cleanTree$pt_BR._(_root);
  @override
  late final _Translations$changes$guardrail$pt_BR guardrail =
      _Translations$changes$guardrail$pt_BR._(_root);
  @override
  late final _Translations$changes$dropHint$pt_BR dropHint =
      _Translations$changes$dropHint$pt_BR._(_root);
  @override
  late final _Translations$changes$diffEmpty$pt_BR diffEmpty =
      _Translations$changes$diffEmpty$pt_BR._(_root);
  @override
  late final _Translations$changes$shelvePill$pt_BR shelvePill =
      _Translations$changes$shelvePill$pt_BR._(_root);
  @override
  late final _Translations$changes$stashAction$pt_BR stashAction =
      _Translations$changes$stashAction$pt_BR._(_root);
  @override
  late final _Translations$changes$stashContents$pt_BR stashContents =
      _Translations$changes$stashContents$pt_BR._(_root);
  @override
  late final _Translations$changes$stashFile$pt_BR stashFile =
      _Translations$changes$stashFile$pt_BR._(_root);
  @override
  late final _Translations$changes$fileRow$pt_BR fileRow =
      _Translations$changes$fileRow$pt_BR._(_root);
  @override
  late final _Translations$changes$resolveStrip$pt_BR resolveStrip =
      _Translations$changes$resolveStrip$pt_BR._(_root);
  @override
  late final _Translations$changes$badge$pt_BR badge =
      _Translations$changes$badge$pt_BR._(_root);
  @override
  late final _Translations$changes$review$pt_BR review =
      _Translations$changes$review$pt_BR._(_root);
  @override
  late final _Translations$changes$commitBtn$pt_BR commitBtn =
      _Translations$changes$commitBtn$pt_BR._(_root);
  @override
  late final _Translations$changes$shapeBtn$pt_BR shapeBtn =
      _Translations$changes$shapeBtn$pt_BR._(_root);
  @override
  late final _Translations$changes$dejaVu$pt_BR dejaVu =
      _Translations$changes$dejaVu$pt_BR._(_root);
  @override
  late final _Translations$changes$identity$pt_BR identity =
      _Translations$changes$identity$pt_BR._(_root);
  @override
  late final _Translations$changes$staleScope$pt_BR staleScope =
      _Translations$changes$staleScope$pt_BR._(_root);
  @override
  late final _Translations$changes$finding$pt_BR finding =
      _Translations$changes$finding$pt_BR._(_root);
  @override
  late final _Translations$changes$muse$pt_BR muse =
      _Translations$changes$muse$pt_BR._(_root);
  @override
  late final _Translations$changes$debug$pt_BR debug =
      _Translations$changes$debug$pt_BR._(_root);
  @override
  late final _Translations$changes$includeSummary$pt_BR includeSummary =
      _Translations$changes$includeSummary$pt_BR._(_root);
  @override
  late final _Translations$changes$status$pt_BR status =
      _Translations$changes$status$pt_BR._(_root);
  @override
  late final _Translations$changes$stash$pt_BR stash =
      _Translations$changes$stash$pt_BR._(_root);
  @override
  late final _Translations$changes$tooltips$pt_BR tooltips =
      _Translations$changes$tooltips$pt_BR._(_root);
  @override
  late final _Translations$changes$mergeEditor$pt_BR mergeEditor =
      _Translations$changes$mergeEditor$pt_BR._(_root);
  @override
  late final _Translations$changes$conflictResolution$pt_BR conflictResolution =
      _Translations$changes$conflictResolution$pt_BR._(_root);
  @override
  late final _Translations$changes$mergeFlow$pt_BR mergeFlow =
      _Translations$changes$mergeFlow$pt_BR._(_root);
  @override
  late final _Translations$changes$constellation$pt_BR constellation =
      _Translations$changes$constellation$pt_BR._(_root);
}

// Path: common
class _Translations$common$pt_BR extends Translations$common$en {
  _Translations$common$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get listSeparator => ', ';
  @override
  String get cancel => 'Cancelar';
  @override
  String get close => 'Fechar';
  @override
  String get save => 'Salvar';
  @override
  String get delete => 'Excluir';
  @override
  String get retry => 'Tentar de novo';
  @override
  String get copy => 'Copiar';
  @override
  String get copied => 'Copiado';
  @override
  String get done => 'Pronto';
  @override
  String get loading => 'Carregando…';
  @override
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} arquivo',
        other: '${n} arquivos',
      );
  @override
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} commit',
        other: '${n} commits',
      );
  @override
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} branch',
        other: '${n} branches',
      );
  @override
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} commit local',
        other: '${n} commits locais',
      );
  @override
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} commit remoto',
        other: '${n} commits remotos',
      );
  @override
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} arquivo em conflito',
        other: '${n} arquivos em conflito',
      );
  @override
  late final _Translations$common$time$pt_BR time =
      _Translations$common$time$pt_BR._(_root);
  @override
  late final _Translations$common$size$pt_BR size =
      _Translations$common$size$pt_BR._(_root);
}

// Path: diff
class _Translations$diff$pt_BR extends Translations$diff$en {
  _Translations$diff$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$diff$status$pt_BR status =
      _Translations$diff$status$pt_BR._(_root);
  @override
  late final _Translations$diff$toolbar$pt_BR toolbar =
      _Translations$diff$toolbar$pt_BR._(_root);
  @override
  late final _Translations$diff$hunkDropdown$pt_BR hunkDropdown =
      _Translations$diff$hunkDropdown$pt_BR._(_root);
  @override
  String stagingFailed({required Object error}) =>
      'Falha no stage parcial: ${error}';
  @override
  late final _Translations$diff$trail$pt_BR trail =
      _Translations$diff$trail$pt_BR._(_root);
  @override
  late final _Translations$diff$pinned$pt_BR pinned =
      _Translations$diff$pinned$pt_BR._(_root);
  @override
  late final _Translations$diff$hunkHint$pt_BR hunkHint =
      _Translations$diff$hunkHint$pt_BR._(_root);
  @override
  late final _Translations$diff$binary$pt_BR binary =
      _Translations$diff$binary$pt_BR._(_root);
  @override
  late final _Translations$diff$media$pt_BR media =
      _Translations$diff$media$pt_BR._(_root);
}

// Path: filament
class _Translations$filament$pt_BR extends Translations$filament$en {
  _Translations$filament$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get noRepositoryOpen => 'Nenhum repositório aberto.';
  @override
  String scanningProgress({required Object scanned, required Object total}) =>
      'escaneando ${scanned} / ${total} arquivos…';
  @override
  String findingsAcrossFiles({required Object count, required Object files}) =>
      '${count} achados em ${files} arquivos';
  @override
  String copiedFindings({required Object count}) => '${count} achados copiados';
  @override
  String get copy => 'COPIAR';
  @override
  String get noFindings => 'Nenhum achado de fluxo de execução.';
  @override
  late final _Translations$filament$severity$pt_BR severity =
      _Translations$filament$severity$pt_BR._(_root);
  @override
  late final _Translations$filament$kind$pt_BR kind =
      _Translations$filament$kind$pt_BR._(_root);
  @override
  String lineLabel({required Object line}) => 'L${line}';
  @override
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class _Translations$history$pt_BR extends Translations$history$en {
  _Translations$history$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$pt_BR commitLede =
      _Translations$history$commitLede$pt_BR._(_root);
  @override
  late final _Translations$history$seismograph$pt_BR seismograph =
      _Translations$history$seismograph$pt_BR._(_root);
  @override
  late final _Translations$history$worldline$pt_BR worldline =
      _Translations$history$worldline$pt_BR._(_root);
  @override
  late final _Translations$history$contextMenu$pt_BR contextMenu =
      _Translations$history$contextMenu$pt_BR._(_root);
  @override
  late final _Translations$history$cherryPick$pt_BR cherryPick =
      _Translations$history$cherryPick$pt_BR._(_root);
  @override
  late final _Translations$history$revert$pt_BR revert =
      _Translations$history$revert$pt_BR._(_root);
  @override
  late final _Translations$history$reflog$pt_BR reflog =
      _Translations$history$reflog$pt_BR._(_root);
  @override
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'Esse commit está mais fundo que o ${n} commit carregado.',
        other: 'Esse commit está mais fundo que os ${n} commits carregados.',
      );
  @override
  String deleteTagFailed({required Object error}) =>
      'Falha ao excluir tag: ${error}';
  @override
  String get loadingTitle => 'Carregando histórico';
  @override
  String get loadingMessage => 'Lendo commits recentes.';
  @override
  String get unavailableTitle => 'Histórico indisponível';
  @override
  String get toggleWorldline => 'Alternar linha de mundo';
  @override
  String get pageTitle => 'Histórico';
  @override
  String get viewingLast => 'Vendo os últimos';
  @override
  String get commitsUnit => 'commits';
  @override
  String get noCommitSelectedTitle => 'Nenhum commit selecionado';
  @override
  String get noCommitSelectedMessage =>
      'Selecione um commit para inspecionar suas mudanças.';
  @override
  String get loadingCommitTitle => 'Carregando commit';
  @override
  String get loadingCommitMessage => 'Lendo detalhes do commit.';
  @override
  String get commitUnavailableTitle => 'Commit indisponível';
  @override
  String get couldNotLoadCommit => 'Não foi possível carregar o commit.';
  @override
  String get reflogDividerLabel => 'reflog';
  @override
  String get loadReflog => 'Carregar reflog';
  @override
  String get createTag => 'Criar tag';
  @override
  String get newTagName => 'Nome da nova tag';
  @override
  String newTagNameError({required Object error}) =>
      'Nome da nova tag — ${error}';
  @override
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} arquivo · todas as mudanças',
        other: '${n} arquivos · todas as mudanças',
      );
  @override
  String get allChangesLabel => 'todas as mudanças';
  @override
  late final _Translations$history$rebase$pt_BR rebase =
      _Translations$history$rebase$pt_BR._(_root);
  @override
  late final _Translations$history$inFlight$pt_BR inFlight =
      _Translations$history$inFlight$pt_BR._(_root);
}

// Path: historySurgery
class _Translations$historySurgery$pt_BR
    extends Translations$historySurgery$en {
  _Translations$historySurgery$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$historySurgery$chrome$pt_BR chrome =
      _Translations$historySurgery$chrome$pt_BR._(_root);
  @override
  late final _Translations$historySurgery$select$pt_BR select =
      _Translations$historySurgery$select$pt_BR._(_root);
  @override
  late final _Translations$historySurgery$understand$pt_BR understand =
      _Translations$historySurgery$understand$pt_BR._(_root);
  @override
  late final _Translations$historySurgery$confirm$pt_BR confirm =
      _Translations$historySurgery$confirm$pt_BR._(_root);
  @override
  late final _Translations$historySurgery$execute$pt_BR execute =
      _Translations$historySurgery$execute$pt_BR._(_root);
  @override
  late final _Translations$historySurgery$verify$pt_BR verify =
      _Translations$historySurgery$verify$pt_BR._(_root);
  @override
  late final _Translations$historySurgery$forcePush$pt_BR forcePush =
      _Translations$historySurgery$forcePush$pt_BR._(_root);
}

// Path: onboarding
class _Translations$onboarding$pt_BR extends Translations$onboarding$en {
  _Translations$onboarding$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$nav$pt_BR nav =
      _Translations$onboarding$nav$pt_BR._(_root);
  @override
  late final _Translations$onboarding$naming$pt_BR naming =
      _Translations$onboarding$naming$pt_BR._(_root);
  @override
  late final _Translations$onboarding$theme$pt_BR theme =
      _Translations$onboarding$theme$pt_BR._(_root);
  @override
  late final _Translations$onboarding$repo$pt_BR repo =
      _Translations$onboarding$repo$pt_BR._(_root);
  @override
  late final _Translations$onboarding$preview$pt_BR preview =
      _Translations$onboarding$preview$pt_BR._(_root);
}

// Path: orrery
class _Translations$orrery$pt_BR extends Translations$orrery$en {
  _Translations$orrery$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$orrery$header$pt_BR header =
      _Translations$orrery$header$pt_BR._(_root);
  @override
  late final _Translations$orrery$status$pt_BR status =
      _Translations$orrery$status$pt_BR._(_root);
  @override
  late final _Translations$orrery$legend$pt_BR legend =
      _Translations$orrery$legend$pt_BR._(_root);
  @override
  late final _Translations$orrery$node$pt_BR node =
      _Translations$orrery$node$pt_BR._(_root);
  @override
  late final _Translations$orrery$milestone$pt_BR milestone =
      _Translations$orrery$milestone$pt_BR._(_root);
  @override
  late final _Translations$orrery$structure$pt_BR structure =
      _Translations$orrery$structure$pt_BR._(_root);
  @override
  late final _Translations$orrery$rail$pt_BR rail =
      _Translations$orrery$rail$pt_BR._(_root);
  @override
  late final _Translations$orrery$selection$pt_BR selection =
      _Translations$orrery$selection$pt_BR._(_root);
  @override
  late final _Translations$orrery$findingKind$pt_BR findingKind =
      _Translations$orrery$findingKind$pt_BR._(_root);
  @override
  late final _Translations$orrery$findings$pt_BR findings =
      _Translations$orrery$findings$pt_BR._(_root);
  @override
  late final _Translations$orrery$anchor$pt_BR anchor =
      _Translations$orrery$anchor$pt_BR._(_root);
  @override
  late final _Translations$orrery$compare$pt_BR compare =
      _Translations$orrery$compare$pt_BR._(_root);
}

// Path: palette
class _Translations$palette$pt_BR extends Translations$palette$en {
  _Translations$palette$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get active => 'ativo';
  @override
  late final _Translations$palette$prefixes$pt_BR prefixes =
      _Translations$palette$prefixes$pt_BR._(_root);
  @override
  late final _Translations$palette$chips$pt_BR chips =
      _Translations$palette$chips$pt_BR._(_root);
  @override
  late final _Translations$palette$predictive$pt_BR predictive =
      _Translations$palette$predictive$pt_BR._(_root);
  @override
  late final _Translations$palette$topTouched$pt_BR topTouched =
      _Translations$palette$topTouched$pt_BR._(_root);
  @override
  late final _Translations$palette$coherence$pt_BR coherence =
      _Translations$palette$coherence$pt_BR._(_root);
  @override
  late final _Translations$palette$keystone$pt_BR keystone =
      _Translations$palette$keystone$pt_BR._(_root);
  @override
  late final _Translations$palette$repoSub$pt_BR repoSub =
      _Translations$palette$repoSub$pt_BR._(_root);
  @override
  late final _Translations$palette$desks$pt_BR desks =
      _Translations$palette$desks$pt_BR._(_root);
  @override
  late final _Translations$palette$actions$pt_BR actions =
      _Translations$palette$actions$pt_BR._(_root);
  @override
  late final _Translations$palette$tools$pt_BR tools =
      _Translations$palette$tools$pt_BR._(_root);
  @override
  late final _Translations$palette$gitCommands$pt_BR gitCommands =
      _Translations$palette$gitCommands$pt_BR._(_root);
  @override
  late final _Translations$palette$pr$pt_BR pr =
      _Translations$palette$pr$pt_BR._(_root);
  @override
  late final _Translations$palette$ai$pt_BR ai =
      _Translations$palette$ai$pt_BR._(_root);
  @override
  late final _Translations$palette$undo$pt_BR undo =
      _Translations$palette$undo$pt_BR._(_root);
  @override
  late final _Translations$palette$navigation$pt_BR navigation =
      _Translations$palette$navigation$pt_BR._(_root);
  @override
  late final _Translations$palette$settings$pt_BR settings =
      _Translations$palette$settings$pt_BR._(_root);
  @override
  late final _Translations$palette$info$pt_BR info =
      _Translations$palette$info$pt_BR._(_root);
  @override
  late final _Translations$palette$debug$pt_BR debug =
      _Translations$palette$debug$pt_BR._(_root);
  @override
  late final _Translations$palette$dev$pt_BR dev =
      _Translations$palette$dev$pt_BR._(_root);
  @override
  late final _Translations$palette$historySurgery$pt_BR historySurgery =
      _Translations$palette$historySurgery$pt_BR._(_root);
  @override
  late final _Translations$palette$orrery$pt_BR orrery =
      _Translations$palette$orrery$pt_BR._(_root);
  @override
  late final _Translations$palette$command$pt_BR command =
      _Translations$palette$command$pt_BR._(_root);
  @override
  late final _Translations$palette$search$pt_BR search =
      _Translations$palette$search$pt_BR._(_root);
  @override
  late final _Translations$palette$wick$pt_BR wick =
      _Translations$palette$wick$pt_BR._(_root);
  @override
  late final _Translations$palette$gitCache$pt_BR gitCache =
      _Translations$palette$gitCache$pt_BR._(_root);
}

// Path: releaseNotes
class _Translations$releaseNotes$pt_BR extends Translations$releaseNotes$en {
  _Translations$releaseNotes$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get versionFallback => 'dev';
  @override
  late final _Translations$releaseNotes$about$pt_BR about =
      _Translations$releaseNotes$about$pt_BR._(_root);
  @override
  late final _Translations$releaseNotes$legal$pt_BR legal =
      _Translations$releaseNotes$legal$pt_BR._(_root);
}

// Path: repoSummary
class _Translations$repoSummary$pt_BR extends Translations$repoSummary$en {
  _Translations$repoSummary$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$repoSummary$backbone$pt_BR backbone =
      _Translations$repoSummary$backbone$pt_BR._(_root);
  @override
  late final _Translations$repoSummary$glance$pt_BR glance =
      _Translations$repoSummary$glance$pt_BR._(_root);
  @override
  late final _Translations$repoSummary$heading$pt_BR heading =
      _Translations$repoSummary$heading$pt_BR._(_root);
  @override
  String get historyStarvedCaveat =>
      'A ordenação é limitada: o grafo de acoplamento não tinha arestas (clone recente ou poucos commits). A ordem dos arquivos reflete o tamanho, não a centralidade estrutural.';
  @override
  late final _Translations$repoSummary$pitch$pt_BR pitch =
      _Translations$repoSummary$pitch$pt_BR._(_root);
  @override
  late final _Translations$repoSummary$region$pt_BR region =
      _Translations$repoSummary$region$pt_BR._(_root);
  @override
  late final _Translations$repoSummary$shape$pt_BR shape =
      _Translations$repoSummary$shape$pt_BR._(_root);
}

// Path: review
class _Translations$review$pt_BR extends Translations$review$en {
  _Translations$review$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get unresolved => 'não resolvido';
  @override
  String get done => 'pronto';
  @override
  String get ack => 'anotado';
  @override
  String get reply => 'responder';
  @override
  String get pleaseFix => 'por favor, corrija';
  @override
  String get draft => 'rascunho';
  @override
  String get engine => 'motor';
  @override
  String get moved => 'movido';
  @override
  String get yourTurn => 'sua vez';
  @override
  String get drafts => 'rascunhos';
  @override
  String get publish => 'publicar';
  @override
  String get discard => 'descartar';
  @override
  String get saveDraft => 'salvar rascunho';
  @override
  String get cancel => 'cancelar';
  @override
  String get verdictApprove => 'aprovar';
  @override
  String get verdictRequestChanges => 'solicitar mudanças';
  @override
  String get verdictComment => 'comentar';
  @override
  String get caughtUp => 'em dia';
  @override
  String get sinceLastLook => 'desde sua última olhada';
  @override
  String get fullDiff => 'diff completo';
  @override
  String get commentHint => 'escreva um comentário';
  @override
  String outdatedLastSeen({required Object round}) =>
      'desatualizado · visto por último R${round}';
  @override
  String resolvedByFmt({required Object verb, required Object who}) =>
      '${verb} · ${who}';
  @override
  String waitingOnFmt({required Object who}) => 'aguardando ${who}';
  @override
  String roundChip({required Object round}) => 'R${round}';
  @override
  String filesSinceLastLook({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '1 arquivo desde sua última olhada',
        other: '${n} arquivos desde sua última olhada',
      );
  @override
  String unresolvedCountFmt({required Object n}) => '${n} não resolvidos';
  @override
  String draftCountFmt({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '1 rascunho',
        other: '${n} rascunhos',
      );
  @override
  String startReviewFailed({required Object error}) =>
      'Não foi possível iniciar a revisão: ${error}';
  @override
  String get anchorUnavailable =>
      'Essa linha não pode ser ancorada — o arquivo é muito grande ou está indisponível.';
  @override
  String reviewActionFailed({required Object error}) =>
      'A ação de revisão falhou: ${error}';
  @override
  String get lensTooLarge =>
      'Essa comparação é grande demais para mostrar aqui — ficamos no diff completo.';
  @override
  String get lensEmpty => 'Nada mudou entre esses snapshots.';
  @override
  String get reopen => 'reabrir';
  @override
  String get notBlocking => 'não esperem por mim';
  @override
  String get markReviewed => 'revisado';
  @override
  String newComments({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '1 novo comentário',
        other: '${n} novos comentários',
      );
  @override
  String get handTo => 'passar para';
  @override
  String get heading => 'REVISÃO';
  @override
  String get identityNeeded => 'Defina uma identidade git para revisar';
  @override
  String get fileUnreadable =>
      'Esse arquivo não pode ser lido aqui — é grande demais ou não existe nesta rodada.';
  @override
  String get timeNow => 'agora';
  @override
  String timeMinutesFmt({required Object n}) => '${n} min';
  @override
  String timeHoursFmt({required Object n}) => '${n} h';
  @override
  String timeDaysFmt({required Object n}) => '${n} d';
  @override
  String get standingApproved => 'aprovado';
  @override
  String get standingChangesRequested => 'alterações solicitadas';
}

// Path: settings
class _Translations$settings$pt_BR extends Translations$settings$en {
  _Translations$settings$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$language$pt_BR language =
      _Translations$settings$language$pt_BR._(_root);
  @override
  late final _Translations$settings$sectionLabels$pt_BR sectionLabels =
      _Translations$settings$sectionLabels$pt_BR._(_root);
  @override
  late final _Translations$settings$errors$pt_BR errors =
      _Translations$settings$errors$pt_BR._(_root);
  @override
  late final _Translations$settings$promptStatus$pt_BR promptStatus =
      _Translations$settings$promptStatus$pt_BR._(_root);
  @override
  late final _Translations$settings$clearData$pt_BR clearData =
      _Translations$settings$clearData$pt_BR._(_root);
  @override
  List<String> get guardrailStageLabels => [
    'Solto',
    'Equilibrado',
    'Rígido',
    'Paranoico',
  ];
  @override
  late final _Translations$settings$guardrailMacro$pt_BR guardrailMacro =
      _Translations$settings$guardrailMacro$pt_BR._(_root);
  @override
  late final _Translations$settings$guardrails$pt_BR guardrails =
      _Translations$settings$guardrails$pt_BR._(_root);
  @override
  late final _Translations$settings$appearance$pt_BR appearance =
      _Translations$settings$appearance$pt_BR._(_root);
  @override
  late final _Translations$settings$retention$pt_BR retention =
      _Translations$settings$retention$pt_BR._(_root);
  @override
  late final _Translations$settings$navigation$pt_BR navigation =
      _Translations$settings$navigation$pt_BR._(_root);
  @override
  late final _Translations$settings$behaviour$pt_BR behaviour =
      _Translations$settings$behaviour$pt_BR._(_root);
  @override
  late final _Translations$settings$retentionClear$pt_BR retentionClear =
      _Translations$settings$retentionClear$pt_BR._(_root);
  @override
  late final _Translations$settings$channels$pt_BR channels =
      _Translations$settings$channels$pt_BR._(_root);
  @override
  late final _Translations$settings$pollResult$pt_BR pollResult =
      _Translations$settings$pollResult$pt_BR._(_root);
  @override
  late final _Translations$settings$keybindingProfile$pt_BR keybindingProfile =
      _Translations$settings$keybindingProfile$pt_BR._(_root);
  @override
  late final _Translations$settings$apiKeys$pt_BR apiKeys =
      _Translations$settings$apiKeys$pt_BR._(_root);
  @override
  late final _Translations$settings$shortcuts$pt_BR shortcuts =
      _Translations$settings$shortcuts$pt_BR._(_root);
  @override
  late final _Translations$settings$toggles$pt_BR toggles =
      _Translations$settings$toggles$pt_BR._(_root);
  @override
  late final _Translations$settings$diffDiffability$pt_BR diffDiffability =
      _Translations$settings$diffDiffability$pt_BR._(_root);
  @override
  late final _Translations$settings$modelSlots$pt_BR modelSlots =
      _Translations$settings$modelSlots$pt_BR._(_root);
  @override
  late final _Translations$settings$modelPicker$pt_BR modelPicker =
      _Translations$settings$modelPicker$pt_BR._(_root);
  @override
  late final _Translations$settings$aiFeatures$pt_BR aiFeatures =
      _Translations$settings$aiFeatures$pt_BR._(_root);
  @override
  late final _Translations$settings$commitEditor$pt_BR commitEditor =
      _Translations$settings$commitEditor$pt_BR._(_root);
  @override
  late final _Translations$settings$review$pt_BR review =
      _Translations$settings$review$pt_BR._(_root);
  @override
  late final _Translations$settings$museHint$pt_BR museHint =
      _Translations$settings$museHint$pt_BR._(_root);
  @override
  late final _Translations$settings$museEditor$pt_BR museEditor =
      _Translations$settings$museEditor$pt_BR._(_root);
  @override
  late final _Translations$settings$museStage$pt_BR museStage =
      _Translations$settings$museStage$pt_BR._(_root);
  @override
  late final _Translations$settings$lensAxis$pt_BR lensAxis =
      _Translations$settings$lensAxis$pt_BR._(_root);
  @override
  late final _Translations$settings$logosLens$pt_BR logosLens =
      _Translations$settings$logosLens$pt_BR._(_root);
  @override
  late final _Translations$settings$sortGuide$pt_BR sortGuide =
      _Translations$settings$sortGuide$pt_BR._(_root);
  @override
  late final _Translations$settings$piggyback$pt_BR piggyback =
      _Translations$settings$piggyback$pt_BR._(_root);
  @override
  late final _Translations$settings$diffStage$pt_BR diffStage =
      _Translations$settings$diffStage$pt_BR._(_root);
  @override
  late final _Translations$settings$undoScope$pt_BR undoScope =
      _Translations$settings$undoScope$pt_BR._(_root);
  @override
  late final _Translations$settings$undoWindow$pt_BR undoWindow =
      _Translations$settings$undoWindow$pt_BR._(_root);
  @override
  late final _Translations$settings$guardrailPhrase$pt_BR guardrailPhrase =
      _Translations$settings$guardrailPhrase$pt_BR._(_root);
  @override
  late final _Translations$settings$reviewGuideHint$pt_BR reviewGuideHint =
      _Translations$settings$reviewGuideHint$pt_BR._(_root);
  @override
  late final _Translations$settings$commitFormat$pt_BR commitFormat =
      _Translations$settings$commitFormat$pt_BR._(_root);
  @override
  late final _Translations$settings$commitPreview$pt_BR commitPreview =
      _Translations$settings$commitPreview$pt_BR._(_root);
  @override
  late final _Translations$settings$externalTools$pt_BR externalTools =
      _Translations$settings$externalTools$pt_BR._(_root);
  @override
  late final _Translations$settings$apiUsage$pt_BR apiUsage =
      _Translations$settings$apiUsage$pt_BR._(_root);
  @override
  late final _Translations$settings$gitea$pt_BR gitea =
      _Translations$settings$gitea$pt_BR._(_root);
  @override
  late final _Translations$settings$wick$pt_BR wick =
      _Translations$settings$wick$pt_BR._(_root);
  @override
  late final _Translations$settings$integrations$pt_BR integrations =
      _Translations$settings$integrations$pt_BR._(_root);
  @override
  late final _Translations$settings$reduceMotion$pt_BR reduceMotion =
      _Translations$settings$reduceMotion$pt_BR._(_root);
  @override
  late final _Translations$settings$resetQuit$pt_BR resetQuit =
      _Translations$settings$resetQuit$pt_BR._(_root);
  @override
  late final _Translations$settings$diagnostics$pt_BR diagnostics =
      _Translations$settings$diagnostics$pt_BR._(_root);
  @override
  late final _Translations$settings$telemetry$pt_BR telemetry =
      _Translations$settings$telemetry$pt_BR._(_root);
  @override
  late final _Translations$settings$flowEngine$pt_BR flowEngine =
      _Translations$settings$flowEngine$pt_BR._(_root);
  @override
  late final _Translations$settings$museStrands$pt_BR museStrands =
      _Translations$settings$museStrands$pt_BR._(_root);
  @override
  late final _Translations$settings$cliPiggyback$pt_BR cliPiggyback =
      _Translations$settings$cliPiggyback$pt_BR._(_root);
  @override
  late final _Translations$settings$header$pt_BR header =
      _Translations$settings$header$pt_BR._(_root);
  @override
  late final _Translations$settings$diagnosticsPanel$pt_BR diagnosticsPanel =
      _Translations$settings$diagnosticsPanel$pt_BR._(_root);
  @override
  late final _Translations$settings$release$pt_BR release =
      _Translations$settings$release$pt_BR._(_root);
  @override
  late final _Translations$settings$providerStatus$pt_BR providerStatus =
      _Translations$settings$providerStatus$pt_BR._(_root);
  @override
  late final _Translations$settings$meridiem$pt_BR meridiem =
      _Translations$settings$meridiem$pt_BR._(_root);
  @override
  late final _Translations$settings$offenders$pt_BR offenders =
      _Translations$settings$offenders$pt_BR._(_root);
}

// Path: sync
class _Translations$sync$pt_BR extends Translations$sync$en {
  _Translations$sync$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$actions$pt_BR actions =
      _Translations$sync$actions$pt_BR._(_root);
  @override
  late final _Translations$sync$panel$pt_BR panel =
      _Translations$sync$panel$pt_BR._(_root);
  @override
  late final _Translations$sync$forcePush$pt_BR forcePush =
      _Translations$sync$forcePush$pt_BR._(_root);
}

// Path: xray
class _Translations$xray$pt_BR extends Translations$xray$en {
  _Translations$xray$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$board$pt_BR board =
      _Translations$xray$board$pt_BR._(_root);
  @override
  late final _Translations$xray$cadence$pt_BR cadence =
      _Translations$xray$cadence$pt_BR._(_root);
  @override
  late final _Translations$xray$cards$pt_BR cards =
      _Translations$xray$cards$pt_BR._(_root);
  @override
  late final _Translations$xray$cardTitle$pt_BR cardTitle =
      _Translations$xray$cardTitle$pt_BR._(_root);
  @override
  late final _Translations$xray$grain$pt_BR grain =
      _Translations$xray$grain$pt_BR._(_root);
  @override
  late final _Translations$xray$header$pt_BR header =
      _Translations$xray$header$pt_BR._(_root);
  @override
  late final _Translations$xray$hotspot$pt_BR hotspot =
      _Translations$xray$hotspot$pt_BR._(_root);
  @override
  late final _Translations$xray$inspector$pt_BR inspector =
      _Translations$xray$inspector$pt_BR._(_root);
  @override
  late final _Translations$xray$loadingCard$pt_BR loadingCard =
      _Translations$xray$loadingCard$pt_BR._(_root);
  @override
  late final _Translations$xray$metabolism$pt_BR metabolism =
      _Translations$xray$metabolism$pt_BR._(_root);
  @override
  late final _Translations$xray$multi$pt_BR multi =
      _Translations$xray$multi$pt_BR._(_root);
  @override
  late final _Translations$xray$recency$pt_BR recency =
      _Translations$xray$recency$pt_BR._(_root);
  @override
  late final _Translations$xray$rings$pt_BR rings =
      _Translations$xray$rings$pt_BR._(_root);
  @override
  late final _Translations$xray$stats$pt_BR stats =
      _Translations$xray$stats$pt_BR._(_root);
  @override
  late final _Translations$xray$stratumLabel$pt_BR stratumLabel =
      _Translations$xray$stratumLabel$pt_BR._(_root);
  @override
  late final _Translations$xray$summary$pt_BR summary =
      _Translations$xray$summary$pt_BR._(_root);
  @override
  late final _Translations$xray$tabs$pt_BR tabs =
      _Translations$xray$tabs$pt_BR._(_root);
  @override
  late final _Translations$xray$trajectory$pt_BR trajectory =
      _Translations$xray$trajectory$pt_BR._(_root);
  @override
  late final _Translations$xray$verdict$pt_BR verdict =
      _Translations$xray$verdict$pt_BR._(_root);
}

// Path: app.cheatsheet
class _Translations$app$cheatsheet$pt_BR
    extends Translations$app$cheatsheet$en {
  _Translations$app$cheatsheet$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Teclado';
  @override
  String get sectionNavigate => 'navegar';
  @override
  String get sectionStaging => 'stage';
  @override
  String get sectionBranchesPrs => 'branches e PRs';
  @override
  String get changes => 'Mudanças';
  @override
  String get history => 'Histórico';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Trocar (sempre)';
  @override
  String get commandPalette => 'Paleta de Comandos';
  @override
  String get elevatedPalette => 'Paleta Elevada';
  @override
  String get dismiss => 'Dispensar';
  @override
  String get refresh => 'Atualizar';
  @override
  String get nextPrevChange => 'Próxima / mudança anterior';
  @override
  String get toggleLine => 'Alternar linha';
  @override
  String get toggleHunk => 'Alternar hunk';
  @override
  String get toggleFile => 'Alternar arquivo';
  @override
  String get pinContext => 'Fixar contexto';
  @override
  String get commit => 'Commit';
  @override
  String get acceptAiHint => 'Aceitar dica da AI';
  @override
  String get undo => 'Desfazer';
  @override
  String get navigate => 'Navegar';
  @override
  String get expand => 'Expandir';
  @override
  String get checkoutPr => 'Checkout do PR';
  @override
  String get approve => 'Aprovar';
  @override
  String get requestChanges => 'Solicitar mudanças';
  @override
  String profileSwitchHint({required Object profile}) =>
      'perfil ${profile} · troque em Configurações';
}

// Path: backend.ops
class _Translations$backend$ops$pt_BR extends Translations$backend$ops$en {
  _Translations$backend$ops$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'Merge';
  @override
  String get pull => 'Pull';
  @override
  String get apply => 'Aplicar';
  @override
  String get switchOp => 'Trocar';
  @override
  String get sync => 'Sincronizar';
}

// Path: backend.mergeOutcome
class _Translations$backend$mergeOutcome$pt_BR
    extends Translations$backend$mergeOutcome$en {
  _Translations$backend$mergeOutcome$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String cancelled({required Object op}) => '${op} cancelado.';
  @override
  String complete({required Object op}) => '${op} concluído.';
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'Falta ${n} conflito — resolva na página de Mudanças.',
        other: 'Faltam ${n} conflitos — resolva na página de Mudanças.',
      );
  @override
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} conflito resolvido.',
        other: '${n} conflitos resolvidos.',
      );
  @override
  String uncommittedEdits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} arquivo tem edições sem commit — faça commit primeiro.',
        other: '${n} arquivos têm edições sem commit — faça commit primeiro.',
      );
}

// Path: changes.usage
class _Translations$changes$usage$pt_BR extends Translations$changes$usage$en {
  _Translations$changes$usage$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String caption({required Object input, required Object output}) =>
      '${input} entr · ${output} saíd';
  @override
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '${fresh} entr · ${cached} em cache · ${out} saíd';
  @override
  String get inWord => 'entr';
  @override
  String get cachedWord => 'cache';
  @override
  String get outWord => 'saíd';
  @override
  String tipIn({required Object value}) => '${value}  entrada';
  @override
  String tipCacheRead({required Object value}) => '${value}  leitura de cache';
  @override
  String tipCacheWrite({required Object value}) => '${value}  escrita de cache';
  @override
  String tipOut({required Object value}) => '${value}  saída';
  @override
  String tipReasoning({required Object value}) => '${value}  raciocínio';
  @override
  String tipWallClock({required Object value}) => '${value}s  tempo real';
}

// Path: changes.tabs
class _Translations$changes$tabs$pt_BR extends Translations$changes$tabs$en {
  _Translations$changes$tabs$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get defaultLabel => 'Mudanças';
  @override
  String get empty => 'Vazio';
}

// Path: changes.tabStrip
class _Translations$changes$tabStrip$pt_BR
    extends Translations$changes$tabStrip$en {
  _Translations$changes$tabStrip$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get newDiffTab => 'Nova Aba de Diff';
}

// Path: changes.select
class _Translations$changes$select$pt_BR
    extends Translations$changes$select$en {
  _Translations$changes$select$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get selectAll => 'Selecionar tudo';
  @override
  String get deselectAll => 'Desmarcar tudo';
}

// Path: changes.constellationToggle
class _Translations$changes$constellationToggle$pt_BR
    extends Translations$changes$constellationToggle$en {
  _Translations$changes$constellationToggle$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get backToList => 'voltar à lista';
  @override
  String get atlas => 'atlas, ver candidatos a commit';
}

// Path: changes.nudgeChip
class _Translations$changes$nudgeChip$pt_BR
    extends Translations$changes$nudgeChip$en {
  _Translations$changes$nudgeChip$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\nse acopla com ${anchor} · ${pct}%${receipts}';
}

// Path: changes.minimap
class _Translations$changes$minimap$pt_BR
    extends Translations$changes$minimap$en {
  _Translations$changes$minimap$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get roleNew => 'novo';
  @override
  String get roleBridge => 'ponte';
  @override
  String get roleHub => 'hub';
  @override
  String get roleLeaf => 'folha';
  @override
  String get roleConnected => 'conectado';
  @override
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';
  @override
  String changesWith({required Object name}) => 'muda junto com ${name}';
  @override
  String get newFile => 'arquivo novo';
  @override
  String nearOtherChanges({required Object count, required Object dir}) =>
      'perto de ${count} outras mudanças em ${dir}';
  @override
  String usuallyChangesWithFile({required Object name}) =>
      '${name} geralmente muda junto com este arquivo';
}

// Path: changes.tagInput
class _Translations$changes$tagInput$pt_BR
    extends Translations$changes$tagInput$en {
  _Translations$changes$tagInput$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get hint => 'tag...';
}

// Path: changes.composer
class _Translations$changes$composer$pt_BR
    extends Translations$changes$composer$en {
  _Translations$changes$composer$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get hintPlaceholder => 'mensagem do commit...';
  @override
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class _Translations$changes$commit$pt_BR
    extends Translations$changes$commit$en {
  _Translations$changes$commit$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get primaryCommitChanges => 'Fazer commit das mudanças';
  @override
  String get primaryCommitChangesDetail =>
      'HEAD desanexado: commit local sem sincronizar.';
  @override
  String get primaryPublish => 'Commit e publicar';
  @override
  String get primaryPublishDetail =>
      'Cria o commit e publica este branch de uma vez.';
  @override
  String get primarySync => 'Commit e sincronizar';
  @override
  String get primarySyncDetail =>
      'Cria o commit, depois reconcilia e despacha o branch.';
  @override
  String get primaryPush => 'Commit e push';
  @override
  String get primaryPushDetail => 'Cria o commit e faz push na hora.';
  @override
  String get amendLast => 'Emendar último commit';
  @override
  String amendAnd({required Object action}) => 'Emendar e ${action}';
  @override
  String get chooseFile =>
      'Escolha pelo menos um arquivo para o próximo commit.';
  @override
  String get writeMessage => 'Escreva uma mensagem de commit primeiro.';
  @override
  String get committing => 'Fazendo commit';
  @override
  String get committingSync => 'Fazendo commit e sincronizando';
  @override
  String get committed => 'Commit feito.';
  @override
  String get undoFailed => 'Falha ao desfazer.';
  @override
  String get working => 'Trabalhando…';
  @override
  String get commitOnly => 'Só commit';
  @override
  String get noRuntimeModels =>
      'Nenhum modelo descoberto em runtime está disponível para mensagens de commit.';
  @override
  String restoreFailedRetry({required Object err}) =>
      '${err}\nNão foi possível restaurar o stage dos arquivos excluídos; verifique o index antes de tentar de novo.';
  @override
  String committedSummary({required Object summary, required Object hash}) =>
      'Commit de ${summary} feito (${hash}).';
  @override
  String get restoreFailedSync =>
      'Não foi possível recolocar em stage as seleções dos arquivos excluídos; sincronização ignorada. Verifique o index antes de sincronizar.';
  @override
  String get noModelLabel => 'Nenhum modelo';
  @override
  String get chooseBeforeGenerate =>
      'Escolha pelo menos um arquivo antes de gerar.';
  @override
  String get aiUnavailable =>
      'A AI de mensagens de commit ainda não está disponível.';
  @override
  String get generateFailed => 'Falha ao gerar.';
  @override
  String get stageFailed => 'Falha ao colocar arquivos em stage.';
  @override
  String get commitFailed => 'Commit falhou.';
  @override
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => 'Commit de ${summary} feito (${hash}) e ${operation} executado.';
  @override
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
    n,
    one: 'Commit de ${summary} feito (${hash}); ${n} conflito resolvido.',
    other: 'Commit de ${summary} feito (${hash}); ${n} conflitos resolvidos.',
  );
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} conflito ainda a resolver.',
        other: '${n} conflitos ainda a resolver.',
      );
  @override
  String syncBlocked({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
    n,
    one:
        'Commit deu certo, mas a sincronização foi bloqueada por ${n} arquivo sem commit.',
    other:
        'Commit deu certo, mas a sincronização foi bloqueada por ${n} arquivos sem commit.',
  );
  @override
  String syncStalled({required Object message}) =>
      'Commit deu certo, mas a sincronização travou: ${message}';
  @override
  String syncFailed({required Object message}) =>
      'Commit deu certo, mas a sincronização falhou: ${message}';
}

// Path: changes.rebase
class _Translations$changes$rebase$pt_BR
    extends Translations$changes$rebase$en {
  _Translations$changes$rebase$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get continueFailed => 'Não foi possível continuar o rebase.';
}

// Path: changes.editor
class _Translations$changes$editor$pt_BR
    extends Translations$changes$editor$en {
  _Translations$changes$editor$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get closeBarrier => 'Fechar editor';
}

// Path: changes.editorTitles
class _Translations$changes$editorTitles$pt_BR
    extends Translations$changes$editorTitles$en {
  _Translations$changes$editorTitles$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  List<String> get any => [
    'querido git log',
    'per-git-oai-me, pai, pois com-mit-i…',
    'dê nome a este momento',
    'desembucha',
    'fala!',
    'sua mãe era uma dangling reference e seu pai cheirava a ponto-e-vírgula',
  ];
  @override
  List<String> get short => [
    'ah é?',
    'e aí:)',
    'aliás:',
    'duas palavrinhas',
    'a versão educada',
    'deixe um recado',
    'você dizia..?',
    'isso, põe pra fora',
  ];
  @override
  List<String> get mid => [
    'pro registro',
    'conta pro seu eu do futuro',
    'mas antes?',
    'como foi',
    'com suas próprias palavras',
    'você fez O QUÊ agora?',
    'devidamente anotado',
    'tem minha atenção',
  ];
  @override
  List<String> get long => [
    'seus sonhos, por favor',
    'diga algo bonito',
    '... e então eu disse:',
    'a posteridade aguarda',
    'escrever mais faz seus bugs sumirem',
    'uau',
    'os textos sagrados',
  ];
}

// Path: changes.askHint
class _Translations$changes$askHint$pt_BR
    extends Translations$changes$askHint$en {
  _Translations$changes$askHint$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String round({required Object n}) =>
      'rodada ${n} — refine ou adicione contexto.';
  @override
  String get symptom => 'descreva o sintoma.';
  @override
  String get broken => 'o que quebrou?';
  @override
  String get bug => 'descreva o bug.';
  @override
  String get error => 'cole o erro.';
}

// Path: changes.fileMenu
class _Translations$changes$fileMenu$pt_BR
    extends Translations$changes$fileMenu$en {
  _Translations$changes$fileMenu$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get ripple => 'Ondular';
  @override
  String get includeCoChanges => 'Incluir co-mudanças';
  @override
  String deleteFile({required Object name}) => 'Excluir ${name}…';
  @override
  String discardChangesTo({required Object name}) =>
      'Descartar mudanças em ${name}…';
  @override
  String get ignore => 'Ignorar';
  @override
  String get diffTabFromSelection => 'Aba de Diff da seleção';
  @override
  String addSelectedToTab({required Object name}) =>
      'Adicionar selecionados a ${name}';
  @override
  String diffTabFromFile({required Object name}) => 'Aba de Diff de ${name}';
  @override
  String addFileToTab({required Object file, required Object tab}) =>
      'Adicionar ${file} a ${tab}';
  @override
  String get copyFilePath => 'Copiar caminho do arquivo';
  @override
  String get showInExplorer => 'Mostrar no Explorador';
}

// Path: changes.multiFileMenu
class _Translations$changes$multiFileMenu$pt_BR
    extends Translations$changes$multiFileMenu$en {
  _Translations$changes$multiFileMenu$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get cohesionTight => 'fortemente acoplados';
  @override
  String get cohesionLoose => 'frouxamente relacionados';
  @override
  String get cohesionScattered => 'estruturalmente dispersos';
  @override
  String get clusterOne => 'todos em um cluster';
  @override
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      'abrange ${count} clusters (${parts} arquivos)';
  @override
  String clusterSpans({required Object count}) => 'abrange ${count} clusters';
  @override
  String roleLine({required Object count, required Object cohesion}) =>
      '${count} arquivos · ${cohesion}';
  @override
  String usuallyChangesWithGroup({required Object file}) =>
      '${file} geralmente muda junto com este grupo';
  @override
  String get splitToNewTab => 'Dividir em nova aba';
  @override
  String copyPaths({required Object count}) => 'Copiar ${count} caminhos';
}

// Path: changes.ignoreMenu
class _Translations$changes$ignoreMenu$pt_BR
    extends Translations$changes$ignoreMenu$en {
  _Translations$changes$ignoreMenu$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String extension({required Object ext}) => 'extensão .${ext}';
  @override
  String allSelected({required Object count}) =>
      'Todos os ${count} selecionados';
  @override
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'Se acopla com ${n} arquivo incluído',
        other: 'Se acopla com ${n} arquivos incluídos',
      );
  @override
  String get updateFailed => 'Falha ao atualizar o .gitignore.';
}

// Path: changes.discard
class _Translations$changes$discard$pt_BR
    extends Translations$changes$discard$en {
  _Translations$changes$discard$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String deleteTitle({required Object name}) => 'Excluir ${name}?';
  @override
  String discardTitle({required Object name}) =>
      'Descartar mudanças em ${name}?';
  @override
  String deleteBody({required Object path}) =>
      '${path} será removido do disco. Isso não pode ser desfeito de dentro do app.';
  @override
  String discardBody({required Object path}) =>
      'Todas as mudanças em ${path} serão revertidas ao estado no HEAD. Isso não pode ser desfeito.';
  @override
  String get discard => 'Descartar';
  @override
  String deletingFile({required Object name}) => 'Excluindo ${name}';
  @override
  String discardingFile({required Object name}) => 'Descartando ${name}';
  @override
  String get discardFailed => 'Falha ao descartar as mudanças.';
  @override
  String discardManyTitle({required Object count}) =>
      'Descartar mudanças em ${count} arquivos?';
  @override
  String get discardManyBody =>
      'Arquivos rastreados serão revertidos ao estado no HEAD; arquivos não rastreados serão removidos do disco. Isso não pode ser desfeito.';
  @override
  String discardManyConfirm({required Object count}) => 'Descartar ${count}';
  @override
  String discardingManyFiles({required Object count}) =>
      'Descartando ${count} arquivos';
  @override
  String failedOpenExplorer({required Object error}) =>
      'Falha ao abrir o explorador de arquivos: ${error}';
  @override
  String get someFailed => 'Alguns descartes falharam.';
}

// Path: changes.snack
class _Translations$changes$snack$pt_BR extends Translations$changes$snack$en {
  _Translations$changes$snack$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get sameWorktree => 'Mesmo worktree — nada para despejar.';
  @override
  String diffFailed({required Object error}) => 'Diff falhou: ${error}';
  @override
  String get deskEmpty => 'A Desk não tem nada à sua frente — despejo vazio.';
  @override
  String sourceDesk({required Object label}) => 'Desk ${label}';
  @override
  String shelfReadFailed({required Object error}) =>
      'Falha ao ler a prateleira: ${error}';
  @override
  String get shelfEmpty => 'Prateleira vazia — nada para despejar.';
  @override
  String sourceShelf({required Object label}) => 'prateleira ${label}';
  @override
  String noModelConfigured({required Object label}) =>
      'Nenhum modelo configurado para "${label}".';
  @override
  String fetchFailed({required Object error}) => 'Fetch falhou: ${error}';
}

// Path: changes.trace
class _Translations$changes$trace$pt_BR extends Translations$changes$trace$en {
  _Translations$changes$trace$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Rastro de verificação';
  @override
  String get draftReview => 'Rascunho de review';
}

// Path: changes.cleanTree
class _Translations$changes$cleanTree$pt_BR
    extends Translations$changes$cleanTree$en {
  _Translations$changes$cleanTree$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Árvore de trabalho limpa';
  @override
  String get subtitle => 'Nenhuma mudança em stage ou fora de stage detectada.';
  @override
  String get noUpstream => '  ·  sem upstream';
  @override
  String get ahead => ' à frente';
  @override
  String get behind => ' atrás';
  @override
  String get refreshing => 'Atualizando...';
  @override
  String get refresh => 'Atualizar';
  @override
  String get check => 'checar';
  @override
  String get checkTooltip => 'Fetch e atualização local.';
  @override
  String get sync => 'e sincronizar';
}

// Path: changes.guardrail
class _Translations$changes$guardrail$pt_BR
    extends Translations$changes$guardrail$en {
  _Translations$changes$guardrail$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'Solto';
  @override
  String get balanced => 'Equilibrado';
  @override
  String get strict => 'Rígido';
  @override
  String get paranoid => 'Paranoico';
}

// Path: changes.dropHint
class _Translations$changes$dropHint$pt_BR
    extends Translations$changes$dropHint$en {
  _Translations$changes$dropHint$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get fromShelf =>
      'solte para trazer as mudanças desta prateleira para cá';
  @override
  String get fromDesk => 'solte para trazer as mudanças desta Desk para cá';
}

// Path: changes.diffEmpty
class _Translations$changes$diffEmpty$pt_BR
    extends Translations$changes$diffEmpty$en {
  _Translations$changes$diffEmpty$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Nenhum arquivo selecionado';
  @override
  String get message =>
      'Selecione um arquivo alterado para inspecionar o diff.';
}

// Path: changes.shelvePill
class _Translations$changes$shelvePill$pt_BR
    extends Translations$changes$shelvePill$en {
  _Translations$changes$shelvePill$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

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
class _Translations$changes$stashAction$pt_BR
    extends Translations$changes$stashAction$en {
  _Translations$changes$stashAction$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get pickUp => 'pegar';
  @override
  String get peek => 'espiar';
  @override
  String get toss => 'jogar fora';
}

// Path: changes.stashContents
class _Translations$changes$stashContents$pt_BR
    extends Translations$changes$stashContents$en {
  _Translations$changes$stashContents$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get reading => 'lendo prateleira…';
  @override
  String get empty => 'prateleira vazia';
}

// Path: changes.stashFile
class _Translations$changes$stashFile$pt_BR
    extends Translations$changes$stashFile$en {
  _Translations$changes$stashFile$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get binary => 'bin';
}

// Path: changes.fileRow
class _Translations$changes$fileRow$pt_BR
    extends Translations$changes$fileRow$en {
  _Translations$changes$fileRow$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get stagedLinesOnly => 'faz commit só das linhas em stage';
  @override
  String get doubleClickToggle => 'clique duplo: alterna o grupo inteiro';
  @override
  String get repoRoot => 'Raiz do repositório';
}

// Path: changes.resolveStrip
class _Translations$changes$resolveStrip$pt_BR
    extends Translations$changes$resolveStrip$en {
  _Translations$changes$resolveStrip$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'lendo ${n} arquivo · rascunhando resolução…',
        other: 'lendo ${n} arquivos · rascunhando resolução…',
      );
  @override
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} conflito em ${files}',
        other: '${n} conflitos em ${files}',
      );
  @override
  String get resolve => 'Resolver';
  @override
  String get orWith => 'OU COM';
  @override
  String resolveWith({required Object label}) => 'resolver com ${label}';
  @override
  String resolveWithModel({required Object label, required Object model}) =>
      'resolver com ${label}  ·  ${model}';
  @override
  String get resolving => 'resolvendo…';
  @override
  String resolveWithGlyph({required Object label}) =>
      '↵  resolver com ${label}';
  @override
  String get orWithAnother => 'ou com outro modelo';
}

// Path: changes.badge
class _Translations$changes$badge$pt_BR extends Translations$changes$badge$en {
  _Translations$changes$badge$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get stagedEdit => 'Edição em stage';
  @override
  String get edited => 'Editado';
  @override
  String get stagedAdd => 'Adição em stage';
  @override
  String get added => 'Adicionado';
  @override
  String get stagedDelete => 'Exclusão em stage';
  @override
  String get deleted => 'Excluído';
  @override
  String get stagedRename => 'Renomeação em stage';
  @override
  String get renamed => 'Renomeado';
  @override
  String get stagedCopy => 'Cópia em stage';
  @override
  String get copied => 'Copiado';
  @override
  String get conflict => 'Conflito';
  @override
  String get stagedTypeChange => 'Mudança de tipo em stage';
  @override
  String get typeChanged => 'Tipo alterado';
  @override
  String get untracked => 'Não rastreado';
}

// Path: changes.review
class _Translations$changes$review$pt_BR
    extends Translations$changes$review$en {
  _Translations$changes$review$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Code review';
  @override
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} arquivo incluído',
        other: '${n} arquivos incluídos',
      );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} hunk',
        other: '${n} hunks',
      );
  @override
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';
  @override
  String get unavailable => 'Review indisponível';
  @override
  String get backToDiff => 'Voltar ao diff';
  @override
  String get verified => 'Verificado';
  @override
  String get draftOnly => 'Só rascunho';
  @override
  String get runAgain => 'Rodar de novo';
  @override
  String draftShownBelow({required Object error}) =>
      '${error} O rascunho do review é mostrado abaixo.';
  @override
  String get hideTrace => 'Ocultar rastro';
  @override
  String get showTrace => 'Mostrar rastro';
  @override
  String get showVerificationTrace => 'Mostrar rastro de verificação';
  @override
  String get whyLanded => 'Por que este review parou aqui';
  @override
  String get noFindings => 'Nenhum achado';
  @override
  String get findings => 'Achados';
  @override
  String get noEvidenceIssues =>
      'Nenhum problema com evidência foi trazido à tona para este escopo de commit.';
  @override
  String get observations => 'Observações';
  @override
  String get chooseBeforeReview =>
      'Escolha pelo menos um arquivo antes de revisar.';
  @override
  String get aiUnavailable => 'A AI de review ainda não está disponível.';
  @override
  String get failed => 'Review falhou.';
  @override
  String get noRuntimeModels =>
      'Nenhum modelo descoberto em runtime está disponível para review de commit.';
}

// Path: changes.commitBtn
class _Translations$changes$commitBtn$pt_BR
    extends Translations$changes$commitBtn$en {
  _Translations$changes$commitBtn$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String switchTo({required Object label}) => 'Mudar para: ${label}\n';
}

// Path: changes.shapeBtn
class _Translations$changes$shapeBtn$pt_BR
    extends Translations$changes$shapeBtn$en {
  _Translations$changes$shapeBtn$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String askingWith({required Object cat}) => 'perguntando com ${cat}…';
  @override
  String askWith({required Object cat}) => 'perguntar com ${cat}';
  @override
  String get noModel => 'nenhum modelo de AI configurado';
  @override
  String nextTooltip({required Object cat}) =>
      'próximo: ${cat}  ·  shift-clique para o anterior';
  @override
  String get onlyOne => 'apenas uma categoria de AI configurada';
}

// Path: changes.dejaVu
class _Translations$changes$dejaVu$pt_BR
    extends Translations$changes$dejaVu$en {
  _Translations$changes$dejaVu$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required num n,
    required Object pct,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
    n,
    one:
        '${pct}% déjà vu — ${n} aresta fantasma de linhas do tempo descartadas toca este diff',
    other:
        '${pct}% déjà vu — ${n} arestas fantasmas de linhas do tempo descartadas tocam este diff',
  );
  @override
  String get label => 'déjà vu';
}

// Path: changes.identity
class _Translations$changes$identity$pt_BR
    extends Translations$changes$identity$en {
  _Translations$changes$identity$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'nenhuma identidade de commit configurada';
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
  String get firstCommit => '\nprimeiro commit neste repo';
  @override
  String get newToRepo => '\nnovato neste repo';
}

// Path: changes.staleScope
class _Translations$changes$staleScope$pt_BR
    extends Translations$changes$staleScope$en {
  _Translations$changes$staleScope$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get message => 'a seleção mudou desde que isto rodou';
  @override
  String get rerun => 'rodar de novo';
}

// Path: changes.finding
class _Translations$changes$finding$pt_BR
    extends Translations$changes$finding$en {
  _Translations$changes$finding$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get openDiff => 'Abrir diff';
  @override
  String get recorded => 'registrado';
  @override
  String get dismiss => 'Dispensar';
}

// Path: changes.muse
class _Translations$changes$muse$pt_BR extends Translations$changes$muse$en {
  _Translations$changes$muse$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Muse';
  @override
  String get youPulledThis => 'você puxou isto';
  @override
  String fromIdea({required Object text}) => 'da ideia: "${text}"';
  @override
  String get foothold => 'apoio — ';
  @override
  String get brainstormSpew => 'jorro de brainstorm';
  @override
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';
  @override
  String copyN({required Object count}) => 'Copiar ${count}';
  @override
  String get clear => 'Limpar';
  @override
  String get chooseBeforeMuse =>
      'Escolha pelo menos um arquivo antes de invocar a muse.';
  @override
  String get aiUnavailable => 'A AI da Muse ainda não está disponível.';
  @override
  String get failed => 'Muse falhou.';
  @override
  String get noRuntimeModels =>
      'Nenhum modelo descoberto em runtime está disponível para a muse.';
  @override
  String get needsModel =>
      'A Muse precisa de pelo menos um modelo configurado.';
  @override
  String get dreaming => 'a muse está sonhando...';
}

// Path: changes.debug
class _Translations$changes$debug$pt_BR extends Translations$changes$debug$en {
  _Translations$changes$debug$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Debug';
  @override
  String round({required Object n}) => '· rodada ${n}';
  @override
  String get clear => 'limpar';
  @override
  String get close => 'fechar';
  @override
  String get analyzing => 'analisando sintoma…';
  @override
  String get describeSymptom => 'descreva um sintoma, depois pressione debug.';
  @override
  String get evidenceFor => 'a favor';
  @override
  String get evidenceAgainst => 'mas';
  @override
  String get narrowDown => 'o que ajudaria a estreitar:';
  @override
  String get failed => 'Debug falhou.';
  @override
  String get refinementFailed => 'Refinamento do debug falhou.';
}

// Path: changes.includeSummary
class _Translations$changes$includeSummary$pt_BR
    extends Translations$changes$includeSummary$en {
  _Translations$changes$includeSummary$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'Nenhum';
  @override
  String stagedSuffix({required Object count}) => ' · ${count} em stage';
  @override
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'Todos os ${n} arquivo${staged}',
        other: 'Todos os ${n} arquivos${staged}',
      );
  @override
  String partial({
    required Object count,
    required Object n,
    required Object staged,
  }) => '${count} de ${n}${staged}';
  @override
  String shortAll({required Object n, required Object staged}) =>
      'Todos os ${n}${staged}';
}

// Path: changes.status
class _Translations$changes$status$pt_BR
    extends Translations$changes$status$en {
  _Translations$changes$status$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get unavailableTitle => 'Status do repositório indisponível';
  @override
  String get loadingTitle => 'Carregando status do repositório';
  @override
  String get loadingMessage => 'Lendo a árvore de trabalho.';
}

// Path: changes.stash
class _Translations$changes$stash$pt_BR extends Translations$changes$stash$en {
  _Translations$changes$stash$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get appliedWithConflicts =>
      'Stash aplicado com conflitos — resolva na página de Mudanças (a entrada do stash foi mantida).';
  @override
  String get couldNotPop => 'Não foi possível dar pop no stash.';
  @override
  String get listChanged =>
      'A lista de stash mudou; drop ignorado. Tente de novo.';
  @override
  String get droppingStash => 'Dando drop no stash';
}

// Path: changes.tooltips
class _Translations$changes$tooltips$pt_BR
    extends Translations$changes$tooltips$en {
  _Translations$changes$tooltips$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get commitGenerating => 'gerando mensagem de commit...';
  @override
  String get commitPreparing => 'preparando mensagem de commit...';
  @override
  String get commitSelectFile =>
      'selecione pelo menos um arquivo para gerar uma mensagem de commit.';
  @override
  String get commitConfigure =>
      'configure a mensagem de commit em Configurações > Dinâmicas Comportamentais > Mensagens de Commit.';
  @override
  String get fastFallback => 'rápido';
  @override
  String commitGenerateWith({required Object label}) =>
      'gerar mensagem de commit com o modelo ${label}';
  @override
  String get museConsulting => 'consultando a muse...';
  @override
  String get showMuse => 'mostrar muse';
  @override
  String get museSelectFile => 'selecione pelo menos um arquivo para a muse.';
  @override
  String get showMuseError => 'mostrar erro da muse';
  @override
  String get museAsk => 'peça uma direção à muse';
  @override
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => 'peça uma direção à muse\n${brainstorm} → ${synthesis}';
  @override
  String get qualityFallback => 'qualidade';
  @override
  String get reviewing => 'revisando...';
  @override
  String get showReview => 'mostrar review';
  @override
  String get reviewPreparing => 'preparando review do commit...';
  @override
  String get reviewSelectFile =>
      'selecione pelo menos um arquivo para revisar.';
  @override
  String get reviewConfigure => 'configure a AI de review nas configurações.';
  @override
  String get viewingReview => 'vendo review';
  @override
  String reviewWith({required Object guardrail, required Object label}) =>
      'review ${guardrail} com o modelo ${label}';
}

// Path: changes.mergeEditor
class _Translations$changes$mergeEditor$pt_BR
    extends Translations$changes$mergeEditor$en {
  _Translations$changes$mergeEditor$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get resolutionYours => 'seu';
  @override
  String get resolutionTheirs => 'deles';
  @override
  String get resolutionCustom => 'custom';
  @override
  String get keepBoth => 'manter os dois';
  @override
  late final _Translations$changes$mergeEditor$trust$pt_BR trust =
      _Translations$changes$mergeEditor$trust$pt_BR._(_root);
  @override
  String get allResolved => 'tudo resolvido';
  @override
  String get resolveEasy => 'resolver conflitos fáceis';
  @override
  String get base => 'base';
  @override
  String get cancel => 'cancelar';
  @override
  String get save => 'salvar';
  @override
  String get complete => 'concluir';
  @override
  String get nextFile => 'próximo arquivo';
  @override
  String get edit => 'editar';
  @override
  String get auto => 'auto';
  @override
  String get undo => 'desfazer';
  @override
  late final _Translations$changes$mergeEditor$keyHints$pt_BR keyHints =
      _Translations$changes$mergeEditor$keyHints$pt_BR._(_root);
  @override
  String get favoredTooltip =>
      'estruturalmente favorecido pela análise de acoplamento';
  @override
  String get newOnBothSides => '(novo dos dois lados)';
  @override
  String writeFailed({required Object error}) =>
      'Falha ao gravar os arquivos resolvidos: ${error}';
  @override
  String neighborsCoChanged({required Object changed, required Object total}) =>
      '${changed}/${total} vizinhos co-mudaram';
  @override
  String integrity({required Object pct}) => 'integridade ${pct}%';
  @override
  String reviewer({required Object name}) => 'revisor: ${name}';
}

// Path: changes.conflictResolution
class _Translations$changes$conflictResolution$pt_BR
    extends Translations$changes$conflictResolution$en {
  _Translations$changes$conflictResolution$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String noModelConfigured({required Object category}) =>
      'Nenhum modelo configurado para "${category}". Defina um em Configurações → AI.';
  @override
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} arquivo sensível ignorado — resolva na mão.',
        other: '${n} arquivos sensíveis ignorados — resolva na mão.',
      );
  @override
  String get couldNotReadFiles =>
      'Não foi possível ler nenhum arquivo em conflito.';
  @override
  String blockedSecret({required Object secret}) =>
      'Bloqueado — um arquivo em conflito parece conter um ${secret}. Resolva na mão.';
  @override
  String resolutionFailed({required Object error}) =>
      'Resolução falhou: ${error}';
  @override
  String mergeResolutionLabel({
    required Object resolved,
    required Object total,
    required Object category,
  }) => '◇ resolução de merge · ${resolved}/${total} arquivos · ${category}';
  @override
  String conflictSummary({
    required Object op,
    required Object conflicts,
    required Object files,
  }) => '${op} · ${conflicts} em ${files}';
  @override
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} conflito',
        other: '${n} conflitos',
      );
  @override
  String get mergeEditorButton => '⇋ editor de merge';
  @override
  String get noAiModel => 'nenhum modelo de AI';
  @override
  String get later => 'depois';
  @override
  String get discard => 'descartar';
  @override
  String get resolveWithAi => '◇ resolver com AI';
  @override
  String get otherModel => 'outro modelo';
  @override
  String withModel({required Object model}) => 'com ${model}';
}

// Path: changes.mergeFlow
class _Translations$changes$mergeFlow$pt_BR
    extends Translations$changes$mergeFlow$en {
  _Translations$changes$mergeFlow$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$mergeFlow$op$pt_BR op =
      _Translations$changes$mergeFlow$op$pt_BR._(_root);
  @override
  String get pushFailed => 'Push falhou';
  @override
  String get rebasedAndPushed => 'Rebase feito e push enviado.';
  @override
  String switchedTo({required Object name}) => 'Trocado para ${name}.';
  @override
  String get switchFailed => 'Falha ao trocar.';
  @override
  String switchedToCarried({required Object name}) =>
      'Trocado para ${name} (mudanças carregadas junto).';
  @override
  String get alreadyUpToDate => 'Já está em dia.';
  @override
  String merged({required Object upstream, required Object n}) =>
      'Merge de ${upstream} feito (${n} arquivos).';
  @override
  String get rebaseNotConverge =>
      'O rebase não convergiu — resolva manualmente.';
  @override
  String get rebased => 'Rebase feito.';
  @override
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'Rebase feito (${n} arquivo resolvido).',
        other: 'Rebase feito (${n} arquivos resolvidos).',
      );
  @override
  String get detachedHead =>
      'Não é possível sincronizar: estado de HEAD desanexado. Faça checkout de um branch primeiro.';
  @override
  String get publishFailed => 'Falha ao publicar.';
  @override
  String get noRemote =>
      'Nenhum remoto configurado. Adicione um para publicar este branch.';
  @override
  String get failed => 'falhou';
}

// Path: changes.constellation
class _Translations$changes$constellation$pt_BR
    extends Translations$changes$constellation$en {
  _Translations$changes$constellation$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get axisStructure => 'ESTRUTURA';
  @override
  String get axisCoChange => 'CO-MUDANÇA';
  @override
  String get axisSpectralProfile => 'PERFIL ESPECTRAL';
  @override
  String get axisPathSiblings => 'IRMÃOS DE CAMINHO';
  @override
  String get axisDiffStructure => 'ESTRUTURA DO DIFF';
  @override
  String get axisSpectral => 'ESPECTRAL';
  @override
  String get titleUnsorted => 'SEM ORDEM';
  @override
  String get titleSingleton => 'SOZINHO';
  @override
  String get titleMixed => 'MISTO';
  @override
  String get untie => 'desatar';
  @override
  String get bind => 'atar';
  @override
  String get emptyClusters => 'nenhum cluster ainda';
}

// Path: common.time
class _Translations$common$time$pt_BR extends Translations$common$time$en {
  _Translations$common$time$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get now => 'agora';
  @override
  String get justNow => 'agora mesmo';
  @override
  String get today => 'HOJE';
  @override
  String minutesAgo({required Object n}) => 'há ${n}min';
  @override
  String hoursAgo({required Object n}) => 'há ${n}h';
  @override
  String daysAgo({required Object n}) => 'há ${n}d';
  @override
  String weeksAgo({required Object n}) => 'há ${n}sem';
  @override
  String monthsAgo({required Object n}) => 'há ${n}mês';
  @override
  String yearsAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'há ${n}a',
        other: 'há ${n}a',
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
  String monthsShort({required Object n}) => '${n}mês';
  @override
  String yearsShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n}a',
        other: '${n}a',
      );
  @override
  String commitMonthsShort({required Object n}) => '${n}m';
  @override
  String get idle => 'parado';
  @override
  String idleDays({required Object n}) => 'parado há ${n} dias';
  @override
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'parado há ${n} ano',
        other: 'parado há ${n} anos',
      );
  @override
  List<String> get monthAbbrevs => [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];
}

// Path: common.size
class _Translations$common$size$pt_BR extends Translations$common$size$en {
  _Translations$common$size$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

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
class _Translations$diff$status$pt_BR extends Translations$diff$status$en {
  _Translations$diff$status$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Carregando diff';
  @override
  String get loadingMessage => 'Lendo as mudanças do arquivo.';
  @override
  String get unavailableTitle => 'Diff indisponível';
  @override
  String get noChangesTitle => 'Sem mudanças';
  @override
  String get noChangesMessage =>
      'Este arquivo não tem conteúdo de diff para exibir.';
}

// Path: diff.toolbar
class _Translations$diff$toolbar$pt_BR extends Translations$diff$toolbar$en {
  _Translations$diff$toolbar$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get searchHint => 'buscar no diff...';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} linha',
        other: '${n} linhas',
      );
  @override
  String get blameLoading => 'blame...';
  @override
  String get blame => 'blame';
  @override
  String get wearMapOn => 'desgaste · ligado';
  @override
  String get wearMapOnHint => 'mapa de desgaste ligado — clique para ocultar';
  @override
  String get wearMapOffHint =>
      'mostrar mapa de desgaste (heatmap de atividade)';
  @override
  String get trailBadge => '· trilha';
}

// Path: diff.hunkDropdown
class _Translations$diff$hunkDropdown$pt_BR
    extends Translations$diff$hunkDropdown$en {
  _Translations$diff$hunkDropdown$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip =>
      'Pular para o bloco de mudança. O git chama isso de hunks.';
  @override
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} mudança',
        other: '${n} mudanças',
      );
}

// Path: diff.trail
class _Translations$diff$trail$pt_BR extends Translations$diff$trail$en {
  _Translations$diff$trail$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'carregando trilha...';
  @override
  String get noHistory => 'nenhum histórico encontrado';
  @override
  String get nowWorkingCopy => 'agora · cópia de trabalho';
  @override
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class _Translations$diff$pinned$pt_BR extends Translations$diff$pinned$en {
  _Translations$diff$pinned$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get loadingContext => 'carregando contexto fixado';
  @override
  String get pageManifold => 'Manifold';
  @override
  String get pageSignals => 'Sinais';
  @override
  String get echoesTitle => 'Ecos';
  @override
  String get technicalLedger => 'Registro Técnico';
  @override
  String get noSecondaryCues => 'Nenhuma pista secundária detectada.';
  @override
  String get linkedPaths => 'Caminhos Vinculados';
  @override
  String moreCount({required Object n}) => '+${n} mais';
  @override
  String get localSeam => 'Costura local';
  @override
  String get sharedOwnership => 'propriedade compartilhada';
  @override
  String get historyWarmingUp => 'Histórico aquecendo';
  @override
  String echoesTotal({required Object n}) => '${n} NO TOTAL';
  @override
  String get noEchoes => 'Nenhum eco neste diff.';
  @override
  String openRelatedFile({required Object name}) =>
      'Abrir arquivo relacionado ${name}';
  @override
  String inspectFile({required Object name}) => 'inspecionar ${name}';
  @override
  String get jumpEcho => 'pular para o eco';
  @override
  String get copyLine => 'copiar linha';
  @override
  String get signalTempo => 'T';
  @override
  String get signalNovelty => 'N';
  @override
  String get signalReach => 'R';
  @override
  late final _Translations$diff$pinned$tempo$pt_BR tempo =
      _Translations$diff$pinned$tempo$pt_BR._(_root);
  @override
  late final _Translations$diff$pinned$tone$pt_BR tone =
      _Translations$diff$pinned$tone$pt_BR._(_root);
  @override
  late final _Translations$diff$pinned$summary$pt_BR summary =
      _Translations$diff$pinned$summary$pt_BR._(_root);
  @override
  late final _Translations$diff$pinned$tightness$pt_BR tightness =
      _Translations$diff$pinned$tightness$pt_BR._(_root);
  @override
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept} (${tightness})';
  @override
  String get storyWhyThisMatters => 'Por que isto importa';
  @override
  String get storyConfidence => 'Confiança';
  @override
  String get storySecondarySignal => 'Sinal secundário';
  @override
  String get storyNeighbourhood => 'Vizinhança';
  @override
  String neighbourhoodDetail({required Object name}) =>
      'Esta linha fica perto de ${name} no campo atual da base de código.';
  @override
  String get propagationLane => 'Faixa de propagação';
  @override
  String propagationLaneNamed({required Object lane}) =>
      'Faixa de propagação: ${lane}';
  @override
  late final _Translations$diff$pinned$witness$pt_BR witness =
      _Translations$diff$pinned$witness$pt_BR._(_root);
  @override
  late final _Translations$diff$pinned$integrity$pt_BR integrity =
      _Translations$diff$pinned$integrity$pt_BR._(_root);
  @override
  late final _Translations$diff$pinned$related$pt_BR related =
      _Translations$diff$pinned$related$pt_BR._(_root);
  @override
  late final _Translations$diff$pinned$axis$pt_BR axis =
      _Translations$diff$pinned$axis$pt_BR._(_root);
}

// Path: diff.hunkHint
class _Translations$diff$hunkHint$pt_BR extends Translations$diff$hunkHint$en {
  _Translations$diff$hunkHint$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String hiddenCount({required Object n}) => '${n} ocultos';
  @override
  String get landing => 'chegada';
}

// Path: diff.binary
class _Translations$diff$binary$pt_BR extends Translations$diff$binary$en {
  _Translations$diff$binary$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String tooLargeToPreview({required Object size}) =>
      '${size} MB (grande demais para prévia)';
  @override
  String get unableToLoadBlob => 'Não foi possível carregar o blob';
  @override
  String get omittedKindMedia => 'mídia';
  @override
  String get omittedKindBinary => 'binário';
  @override
  String omittedStub({required Object kind}) => '${kind} · oculto';
}

// Path: diff.media
class _Translations$diff$media$pt_BR extends Translations$diff$media$en {
  _Translations$diff$media$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get unableToDecodeImage => 'Não foi possível decodificar a imagem';
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
  String get stateAdded => 'adicionado';
  @override
  String get stateDeleted => 'removido';
  @override
  String get stateModified => 'modificado';
  @override
  String get fallbackFormatName => 'Binário';
}

// Path: filament.severity
class _Translations$filament$severity$pt_BR
    extends Translations$filament$severity$en {
  _Translations$filament$severity$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get critical => 'crítico';
  @override
  String get warn => 'alerta';
  @override
  String get info => 'info';
  @override
  String get joint => 'conjunto';
}

// Path: filament.kind
class _Translations$filament$kind$pt_BR extends Translations$filament$kind$en {
  _Translations$filament$kind$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get staleValue => 'valor obsoleto';
  @override
  String get temporalShift => 'deslocamento temporal';
  @override
  String get contextInversion => 'inversão de contexto';
  @override
  String get contradictoryFlow => 'fluxo contraditório';
}

// Path: history.commitLede
class _Translations$history$commitLede$pt_BR
    extends Translations$history$commitLede$en {
  _Translations$history$commitLede$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$semantics$pt_BR semantics =
      _Translations$history$commitLede$semantics$pt_BR._(_root);
}

// Path: history.seismograph
class _Translations$history$seismograph$pt_BR
    extends Translations$history$seismograph$en {
  _Translations$history$seismograph$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get rootTrackLabel => '(raiz)';
  @override
  String dirTrackLabel({required Object name}) => '(${name})';
  @override
  String moreLabel({required Object n}) => '+${n} mais';
  @override
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} arquivo em ${path}/',
        other: '${n} arquivos em ${path}/',
      );
  @override
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '+${n} arquivo',
        other: '+${n} arquivos',
      );
  @override
  String get breadcrumbAll => 'tudo';
  @override
  String breadcrumbCurrentFocus({required Object target}) =>
      'Foco atual: ${target}';
  @override
  String get breadcrumbViewAllChanges => 'Ver todas as mudanças deste commit';
  @override
  String breadcrumbDrillUpTo({required Object target}) => 'Subir até ${target}';
  @override
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
    n,
    one: '${n} arquivo  +${adds}  -${dels}',
    other: '${n} arquivos  +${adds}  -${dels}',
  );
  @override
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} subpasta',
        other: '${n} subpastas',
      );
  @override
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}, ${adds} adicionadas, ${dels} removidas';
  @override
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
    n,
    one: '${n} arquivo, ${adds} adicionadas, ${dels} removidas',
    other: '${n} arquivos, ${adds} adicionadas, ${dels} removidas',
  );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} hunk',
        other: '${n} hunks',
      );
  @override
  String get largestChangeInView => 'maior mudança nesta visão';
  @override
  String get conflictedTag => 'em conflito';
  @override
  String get dirtyTag => 'sujo';
  @override
  String get drillInTag => 'aprofundar';
  @override
  String get changeTypeRenamed => 'renomeado';
  @override
  String get changeTypeCopied => 'copiado';
  @override
  String get changeTypeTypechange => 'mudança de tipo';
  @override
  String get changeTypeConflict => 'conflito';
  @override
  String get coreFile => 'arquivo núcleo';
  @override
  String get staleFile => 'obsoleto';
  @override
  String get filterPathHint => 'filtrar caminho';
  @override
  String get escHint => 'esc';
}

// Path: history.worldline
class _Translations$history$worldline$pt_BR
    extends Translations$history$worldline$en {
  _Translations$history$worldline$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get closeWorldline => 'Fechar linha de mundo';
  @override
  String get dragToOpenWorldline => 'Arraste para abrir a linha de mundo';
}

// Path: history.contextMenu
class _Translations$history$contextMenu$pt_BR
    extends Translations$history$contextMenu$en {
  _Translations$history$contextMenu$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get currentBranchFallback => 'branch atual';
  @override
  String applyCommitOnto({required Object branch}) =>
      'Aplicar as mudanças do commit em ${branch}';
  @override
  String revertCommitOn({required Object branch}) =>
      'Reverter as mudanças do commit em ${branch}';
}

// Path: history.cherryPick
class _Translations$history$cherryPick$pt_BR
    extends Translations$history$cherryPick$en {
  _Translations$history$cherryPick$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Cherry-pick pausado. Termine os conflitos restantes na página de Mudanças.';
  @override
  String failed({required Object error}) => 'Cherry-pick falhou: ${error}';
  @override
  String pickedResolved({required Object short}) =>
      'Cherry-pick de ${short} (conflitos resolvidos)';
  @override
  String picked({required Object short}) => 'Cherry-pick de ${short}';
}

// Path: history.revert
class _Translations$history$revert$pt_BR
    extends Translations$history$revert$en {
  _Translations$history$revert$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Revert pausado. Termine os conflitos restantes na página de Mudanças.';
  @override
  String failed({required Object error}) => 'Revert falhou: ${error}';
  @override
  String revertedResolved({required Object short}) =>
      'Revertido ${short} (conflitos resolvidos)';
  @override
  String reverted({required Object short}) => 'Revertido ${short}';
}

// Path: history.reflog
class _Translations$history$reflog$pt_BR
    extends Translations$history$reflog$en {
  _Translations$history$reflog$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get createBranchFromHere => 'Criar branch a partir daqui…';
  @override
  String get copyCommitHash => 'Copiar hash do commit';
  @override
  String get createBranchDialogTitle =>
      'Criar branch a partir da entrada do reflog';
  @override
  String anchorLine({required Object short, required Object summary}) =>
      'Âncora: ${short}  ·  ${summary}';
  @override
  String get branchNameHint => 'nome do branch';
  @override
  String get createAction => 'Criar';
  @override
  String createBranchFailed({required Object error}) =>
      'Falha ao criar branch: ${error}';
  @override
  String branchCreatedAt({required Object name, required Object short}) =>
      'Branch "${name}" criado em ${short}.';
}

// Path: history.rebase
class _Translations$history$rebase$pt_BR
    extends Translations$history$rebase$en {
  _Translations$history$rebase$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String firstCommitCannotBe({required Object action}) =>
      'O primeiro commit não pode ser ${action}';
  @override
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'Rebase de ${n} commit',
        other: 'Rebase de ${n} commits',
      );
  @override
  String get resetLabel => 'resetar';
  @override
  String get dragToReorderHint =>
      'arraste para reordenar, escolha a ação por commit';
  @override
  String get newMessageHint => 'nova mensagem';
  @override
  String get runningEllipsis => '…';
  @override
  String get startRebase => 'Iniciar Rebase';
}

// Path: history.inFlight
class _Translations$history$inFlight$pt_BR
    extends Translations$history$inFlight$en {
  _Translations$history$inFlight$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'EM VOO';
  @override
  String get deskFallbackLabel => 'Desk';
}

// Path: historySurgery.chrome
class _Translations$historySurgery$chrome$pt_BR
    extends Translations$historySurgery$chrome$en {
  _Translations$historySurgery$chrome$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Cirurgia de Histórico';
  @override
  String get alphaBadge => 'alpha';
  @override
  String get dryRunBadge => 'DRY RUN';
}

// Path: historySurgery.select
class _Translations$historySurgery$select$pt_BR
    extends Translations$historySurgery$select$en {
  _Translations$historySurgery$select$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get prompt => 'Selecione arquivos para remover do histórico';
  @override
  String selectedCount({required Object n}) => '${n} selecionados';
  @override
  String get searchHint => 'buscar...';
  @override
  String get readingTree => 'lendo árvore...';
  @override
  String get continueDisabled => 'selecione arquivos para continuar';
  @override
  String get continueEnabled => 'continuar →';
  @override
  String toPurgeCount({required Object n}) => '${n} a expurgar';
  @override
  String get analyzing => 'analisando...';
  @override
  String get riskLow => 'risco baixo';
  @override
  String get riskModerate => 'risco moderado';
  @override
  String get riskHigh => 'risco alto';
  @override
  String get impactCommitsLabel => 'commits';
  @override
  String get impactBranchesLabel => 'branches';
  @override
  String get impactWorktreesLabel => 'worktrees';
  @override
  String get impactCouplingLabel => 'acoplamento';
  @override
  String get impactCouplingIsland => 'ilha';
  @override
  String impactCouplingNeighbors({required Object n}) => '${n} vizinhos';
  @override
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class _Translations$historySurgery$understand$pt_BR
    extends Translations$historySurgery$understand$en {
  _Translations$historySurgery$understand$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get heading => 'Como isto funciona';
  @override
  String get backupTitle => 'Backup';
  @override
  String get backupBody =>
      'Toda ref de branch e tag é copiada para um namespace de backup antes de qualquer mudança. Se algo der errado, um clique restaura o estado original.';
  @override
  String get rewriteTitle => 'Reescrita';
  @override
  String get rewriteBody =>
      'Cada commit é percorrido da raiz até a ponta. Para todo commit que contém os arquivos alvo, um novo commit é criado com esses arquivos removidos da árvore. As cadeias de pais são remapeadas para preservar a topologia. ';
  @override
  String rewriteSummary({required Object affected, required Object total}) =>
      '${affected} de ${total} commits serão reescritos.';
  @override
  String get updateRefsTitle => 'Atualizar refs';
  @override
  String get updateRefsBody =>
      'Os ponteiros de branch e tag são movidos para os novos SHAs de commit. Os objetos antigos ainda existem até o garbage collection. ';
  @override
  String worktreesNeedRecheckout({required Object n}) =>
      'Seus ${n} worktree(s) vão precisar de novo checkout.';
  @override
  String get noWorktreesAffected => 'Nenhum worktree é afetado.';
  @override
  String get forcePushTitle => 'Force-push';
  @override
  String get forcePushBody =>
      'Depois de verificar o expurgo, você escolhe quais branches receberão force-push. Usa --force-with-lease, então falha com segurança se outra pessoa tiver feito push nesse meio-tempo.';
  @override
  String get plumbingNote =>
      'Diferente do filter-repo ou do BFG, isto roda inteiramente por comandos plumbing do git (cat-file, mktree, commit-tree, update-ref). Sem dependências externas. O rastreamento de renomeações segue uma cadeia por arquivo — se um arquivo foi copiado e as duas cópias renomeadas de forma independente, verifique o resultado do expurgo após a execução.';
  @override
  String get back => '← Voltar';
  @override
  String get continueLabel => 'Entendi, continuar →';
}

// Path: historySurgery.confirm
class _Translations$historySurgery$confirm$pt_BR
    extends Translations$historySurgery$confirm$en {
  _Translations$historySurgery$confirm$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String commitsRewritten({required Object n}) =>
      '${n} commits serão reescritos';
  @override
  String get forcePushRequired =>
      'Force-push será necessário para branches remotos';
  @override
  String worktreesRecheckout({required Object n}) =>
      '${n} worktrees vão precisar de novo checkout';
  @override
  String stashesInvalid({required Object n}) =>
      '${n} stashes podem se tornar inválidos';
  @override
  String get heading => 'Esta operação reescreve o histórico do git';
  @override
  String get subheading =>
      'Não pode ser desfeita automaticamente após o force-push.';
  @override
  String typeHint({required Object word}) => 'digite ${word}';
  @override
  String get goBack => 'Voltar';
  @override
  String get begin => 'Iniciar Cirurgia';
}

// Path: historySurgery.execute
class _Translations$historySurgery$execute$pt_BR
    extends Translations$historySurgery$execute$en {
  _Translations$historySurgery$execute$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => 'Preparando...';
  @override
  String get backingUpRefs => 'Fazendo backup das refs...';
  @override
  String get rewritingCommits => 'Reescrevendo commits...';
  @override
  String get updatingRefs => 'Atualizando refs...';
}

// Path: historySurgery.verify
class _Translations$historySurgery$verify$pt_BR
    extends Translations$historySurgery$verify$en {
  _Translations$historySurgery$verify$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get complete => 'Cirurgia Concluída';
  @override
  String get failed => 'Cirurgia Falhou';
  @override
  String get commitsRewrittenLabel => 'Commits reescritos';
  @override
  String get refsUpdatedLabel => 'Refs atualizadas';
  @override
  String get oldHeadLabel => 'HEAD antigo';
  @override
  String get newHeadLabel => 'HEAD novo';
  @override
  String get purgeVerifiedLabel => 'Expurgo verificado';
  @override
  String get purgeClean => 'limpo';
  @override
  String get purgeTracesRemain => 'RESTAM VESTÍGIOS';
  @override
  String get displacedWorktrees => 'Worktrees Deslocados';
  @override
  String get undoSurgery => 'Desfazer Cirurgia';
  @override
  String get rolledBack => 'Revertido para as refs de backup.';
  @override
  String get done => 'Pronto';
}

// Path: historySurgery.forcePush
class _Translations$historySurgery$forcePush$pt_BR
    extends Translations$historySurgery$forcePush$en {
  _Translations$historySurgery$forcePush$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get pushing => 'fazendo push...';
  @override
  String get forcePushAll => 'Force Push em Todos';
  @override
  String get confirmPush => 'confirmar push';
  @override
  String get cancel => 'cancelar';
}

// Path: onboarding.nav
class _Translations$onboarding$nav$pt_BR
    extends Translations$onboarding$nav$en {
  _Translations$onboarding$nav$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get back => 'Voltar';
  @override
  String get continueLabel => 'Continuar';
  @override
  String get letsGo => 'Bora';
}

// Path: onboarding.naming
class _Translations$onboarding$naming$pt_BR
    extends Translations$onboarding$naming$en {
  _Translations$onboarding$naming$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'o que isto é pra você?';
  @override
  String get questionEmphasis => 'isto';
  @override
  String get iAmPrefix => 'Eu sou o ';
  @override
  String get iAmSuffix => ' , seu Cliente Git pessoal.';
}

// Path: onboarding.theme
class _Translations$onboarding$theme$pt_BR
    extends Translations$onboarding$theme$en {
  _Translations$onboarding$theme$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'vista o ${name}.';
  @override
  String get themesHeader => 'TEMAS';
  @override
  String get keybindingsHeader => 'ATALHOS';
  @override
  String get previewBadge => 'prévia';
  @override
  String get useDefaults => 'usar padrões';
}

// Path: onboarding.repo
class _Translations$onboarding$repo$pt_BR
    extends Translations$onboarding$repo$en {
  _Translations$onboarding$repo$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'aponte o ${name} pra algo.';
  @override
  String get later => 'faço isso depois';
  @override
  late final _Translations$onboarding$repo$doors$pt_BR doors =
      _Translations$onboarding$repo$doors$pt_BR._(_root);
  @override
  late final _Translations$onboarding$repo$cloneForm$pt_BR cloneForm =
      _Translations$onboarding$repo$cloneForm$pt_BR._(_root);
  @override
  late final _Translations$onboarding$repo$pickers$pt_BR pickers =
      _Translations$onboarding$repo$pickers$pt_BR._(_root);
  @override
  late final _Translations$onboarding$repo$errors$pt_BR errors =
      _Translations$onboarding$repo$errors$pt_BR._(_root);
}

// Path: onboarding.preview
class _Translations$onboarding$preview$pt_BR
    extends Translations$onboarding$preview$en {
  _Translations$onboarding$preview$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$preview$panels$pt_BR panels =
      _Translations$onboarding$preview$panels$pt_BR._(_root);
  @override
  late final _Translations$onboarding$preview$sidebar$pt_BR sidebar =
      _Translations$onboarding$preview$sidebar$pt_BR._(_root);
  @override
  late final _Translations$onboarding$preview$changes$pt_BR changes =
      _Translations$onboarding$preview$changes$pt_BR._(_root);
  @override
  late final _Translations$onboarding$preview$history$pt_BR history =
      _Translations$onboarding$preview$history$pt_BR._(_root);
  @override
  late final _Translations$onboarding$preview$branches$pt_BR branches =
      _Translations$onboarding$preview$branches$pt_BR._(_root);
  @override
  late final _Translations$onboarding$preview$diff$pt_BR diff =
      _Translations$onboarding$preview$diff$pt_BR._(_root);
}

// Path: orrery.header
class _Translations$orrery$header$pt_BR extends Translations$orrery$header$en {
  _Translations$orrery$header$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Orrery';
  @override
  String get modeScrub => 'Percorrer';
  @override
  String get modeCompare => 'Comparar';
  @override
  String get lodModules => 'Módulos';
  @override
  String get lodFiles => 'Arquivos';
}

// Path: orrery.status
class _Translations$orrery$status$pt_BR extends Translations$orrery$status$en {
  _Translations$orrery$status$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'Traçando o manifold através do histórico…';
  @override
  String get loadError => 'Não foi possível ler o histórico deste repo.';
  @override
  String get notEnoughHistory =>
      'Histórico ainda insuficiente para plotar uma trajetória.';
  @override
  String get notEnoughHistoryDetail =>
      'O Orrery precisa de alguns commits para desenhar.';
}

// Path: orrery.legend
class _Translations$orrery$legend$pt_BR extends Translations$orrery$legend$en {
  _Translations$orrery$legend$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get central => 'central';
  @override
  String get peripheral => 'periférico';
}

// Path: orrery.node
class _Translations$orrery$node$pt_BR extends Translations$orrery$node$en {
  _Translations$orrery$node$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get module => 'módulo';
  @override
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · ${n} arquivos';
  @override
  String fileFallback({required Object id}) => 'arquivo #${id}';
  @override
  String nodeFallback({required Object id}) => 'nó #${id}';
  @override
  String get rootModule => '(raiz)';
}

// Path: orrery.milestone
class _Translations$orrery$milestone$pt_BR
    extends Translations$orrery$milestone$en {
  _Translations$orrery$milestone$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get genesis => 'gênese';
  @override
  String get now => 'agora';
  @override
  String get reorganized => 'reorganizado';
  @override
  String becameArchetype({required Object archetype}) => 'virou ${archetype}';
  @override
  String get snapshot => 'snapshot';
}

// Path: orrery.structure
class _Translations$orrery$structure$pt_BR
    extends Translations$orrery$structure$en {
  _Translations$orrery$structure$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get forming => 'formando…';
  @override
  String get canonical => 'canônico';
  @override
  String get connectivity => 'conectividade';
  @override
  String get rigidity => 'rigidez';
  @override
  String get entropy => 'entropia';
}

// Path: orrery.rail
class _Translations$orrery$rail$pt_BR extends Translations$orrery$rail$en {
  _Translations$orrery$rail$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get structureLabel => 'ESTRUTURA';
  @override
  String get fieldLabel => 'CAMPO';
  @override
  String get findingsLabel => 'ACHADOS';
  @override
  String get selectedLabel => 'SELECIONADO';
  @override
  String get noFindings =>
      'Nenhum evento estrutural detectado neste histórico.';
}

// Path: orrery.selection
class _Translations$orrery$selection$pt_BR
    extends Translations$orrery$selection$en {
  _Translations$orrery$selection$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get notPresent => 'Não presente neste ponto do histórico.';
  @override
  String get roleCentral =>
      'Central no acoplamento — mudanças aqui repercutem por todo o sistema.';
  @override
  String get rolePeripheral =>
      'Periférico — frouxamente acoplado, muda quase sempre por conta própria.';
  @override
  String get roleMid => 'Estrutura intermediária — moderadamente acoplado.';
  @override
  String get driftOutward => ' Derivando para fora — desacoplando.';
  @override
  String get driftInward => ' Derivando para dentro — integrando.';
  @override
  String get driftHolding => ' Mantendo a posição.';
}

// Path: orrery.findingKind
class _Translations$orrery$findingKind$pt_BR
    extends Translations$orrery$findingKind$en {
  _Translations$orrery$findingKind$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get hub => 'HUB';
  @override
  String get driftOut => 'DERIVANDO PRA FORA';
  @override
  String get driftIn => 'DERIVANDO PRA DENTRO';
  @override
  String get tangle => 'EMARANHANDO';
  @override
  String get clarify => 'CLAREANDO';
  @override
  String get regime => 'REORG';
  @override
  String get thrash => 'DEBATENDO';
  @override
  String get reshuffle => 'REEMBARALHO';
  @override
  String get forecast => 'PREVISÃO';
}

// Path: orrery.findings
class _Translations$orrery$findings$pt_BR
    extends Translations$orrery$findings$en {
  _Translations$orrery$findings$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get forecastSplit =>
      'A conectividade vem caindo e está perto do mínimo — se isso se mantiver, a base de código caminha para se dividir em metades frouxamente acopladas. Decida agora se essa é a intenção.';
  @override
  String get forecastConsolidate =>
      'A conectividade vem subindo rumo ao pico — se isso se mantiver, a base de código está consolidando numa massa fortemente acoplada. Fique de olho para não endurecer num monólito.';
  @override
  String thrash({required Object name}) =>
      '${name} vive sendo reorganizado de um lado pro outro — muita agitação estrutural, pouco movimento líquido. Estabilize o acoplamento ou pare de mexer nele.';
  @override
  String get reshuffle =>
      'Este commit parecia rotineiro, mas mudou discretamente quais arquivos são centrais — a forma geral se manteve enquanto a estrutura se reembaralhava por baixo. Revise com atenção.';
  @override
  String hub({required Object name}) =>
      '${name} fica no núcleo estrutural — o sistema se reorganiza em torno dele. Trate mudanças aqui como de alto raio de explosão.';
  @override
  String driftOut({required Object name}) =>
      '${name} derivou do núcleo em direção à borda — está se desacoplando do sistema. Ou está sendo aposentado, ou apodrecendo em silêncio.';
  @override
  String driftIn({required Object name}) =>
      '${name} migrou em direção ao núcleo — está virando peça de sustentação. Garanta que esteja bem testado antes que mais coisas dependam dele.';
  @override
  String get regime =>
      'A base de código se reorganizou bruscamente aqui — a conectividade deu um salto. Revise o que se separou ou se fundiu.';
  @override
  String get tangleTrend =>
      'Ao longo do histórico, a base de código tendeu a uma estrutura mais emaranhada — a conectividade está ficando mais densa e menos modular.';
  @override
  String get clarifyTrend =>
      'Ao longo do histórico, a base de código tendeu a uma estrutura mais limpa — está se separando em módulos mais claros.';
}

// Path: orrery.anchor
class _Translations$orrery$anchor$pt_BR extends Translations$orrery$anchor$en {
  _Translations$orrery$anchor$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get core => 'núcleo';
  @override
  String get drift => 'deriva';
  @override
  String get trend => 'tendência';
  @override
  String get thrash => 'debate';
}

// Path: orrery.compare
class _Translations$orrery$compare$pt_BR
    extends Translations$orrery$compare$en {
  _Translations$orrery$compare$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'A → B';
  @override
  String get change => 'MUDANÇA';
  @override
  String get movers => 'QUEM SE MOVEU';
  @override
  String get noMovers => 'Nenhum arquivo se moveu entre esses quadros.';
  @override
  String get badgeA => 'A';
  @override
  String get badgeB => 'B';
  @override
  String get deltaFiles => 'arquivos';
  @override
  String get deltaConnectivity => 'conectividade';
  @override
  String get deltaRigidity => 'rigidez';
  @override
  String get deltaEntropy => 'entropia';
  @override
  String get wayOutward => 'para fora';
  @override
  String get wayInward => 'para dentro';
  @override
  String get wayShifted => 'deslocado';
}

// Path: palette.prefixes
class _Translations$palette$prefixes$pt_BR
    extends Translations$palette$prefixes$en {
  _Translations$palette$prefixes$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get askHint => 'ask: [pergunta]';
  @override
  String get nearHint => 'near: [arquivo]';
  @override
  String get whoHint => 'who: [arquivo]';
  @override
  String get logHint => 'log: [mensagem]';
  @override
  String get runHint => 'run: [ferramenta]';
  @override
  String askLabel({required Object name, required Object body}) =>
      'Perguntar ao ${name}: ${body}';
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
      '${path} · nenhum revisor registrado';
}

// Path: palette.chips
class _Translations$palette$chips$pt_BR extends Translations$palette$chips$en {
  _Translations$palette$chips$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get ai => 'AI';
  @override
  String get near => 'NEAR';
  @override
  String get who => 'WHO';
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
  String get desk => 'DESK';
  @override
  String get det => 'DET';
  @override
  String get main => 'MAIN';
  @override
  String get head => 'HEAD';
  @override
  String get gone => 'GONE';
  @override
  String get remote => 'REMOTE';
  @override
  String get local => 'LOCAL';
  @override
  String get an => 'AN';
  @override
  String get lw => 'LW';
}

// Path: palette.predictive
class _Translations$palette$predictive$pt_BR
    extends Translations$palette$predictive$en {
  _Translations$palette$predictive$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String momentumSuffix({required Object percent}) => '${percent}% de embalo';
}

// Path: palette.topTouched
class _Translations$palette$topTouched$pt_BR
    extends Translations$palette$topTouched$en {
  _Translations$palette$topTouched$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object count, required Object path}) =>
      '${count} toques · ${path}';
}

// Path: palette.coherence
class _Translations$palette$coherence$pt_BR
    extends Translations$palette$coherence$en {
  _Translations$palette$coherence$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String label({required Object percent}) => 'Coerência em stage: ${percent}%';
  @override
  String subtitle({required Object count}) => '${count} arquivos';
}

// Path: palette.keystone
class _Translations$palette$keystone$pt_BR
    extends Translations$palette$keystone$en {
  _Translations$palette$keystone$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object path, required Object score}) =>
      '${path} · pedra-chave ${score}';
}

// Path: palette.repoSub
class _Translations$palette$repoSub$pt_BR
    extends Translations$palette$repoSub$en {
  _Translations$palette$repoSub$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String changes({required Object name}) => 'Mudanças em ${name}';
  @override
  String history({required Object name}) => 'Histórico em ${name}';
  @override
  String branches({required Object name}) => 'Branches em ${name}';
  @override
  String terminal({required Object name}) => 'Terminal em ${name}';
  @override
  String generateCommit({required Object name}) => 'Gerar Commit · ${name}';
  @override
  String reviewChanges({required Object name}) => 'Revisar Mudanças em ${name}';
  @override
  String muse({required Object name}) => 'Muse em ${name}';
}

// Path: palette.desks
class _Translations$palette$desks$pt_BR extends Translations$palette$desks$en {
  _Translations$palette$desks$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get mainWorktree => 'worktree principal';
  @override
  String get detached => 'desanexado';
  @override
  String dirty({required Object count}) => '${count} sujos';
}

// Path: palette.actions
class _Translations$palette$actions$pt_BR
    extends Translations$palette$actions$en {
  _Translations$palette$actions$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get openInBrowser => 'Abrir no Navegador';
  @override
  String get terminal => 'Terminal';
  @override
  String get revealInFiles => 'Mostrar nos Arquivos';
  @override
  String get copyPath => 'Copiar Caminho';
  @override
  String get copyBranch => 'Copiar Branch';
}

// Path: palette.tools
class _Translations$palette$tools$pt_BR extends Translations$palette$tools$en {
  _Translations$palette$tools$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String launch({required Object label}) => 'Abrir ${label}';
}

// Path: palette.gitCommands
class _Translations$palette$gitCommands$pt_BR
    extends Translations$palette$gitCommands$en {
  _Translations$palette$gitCommands$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get fetch => 'Fetch';
  @override
  String get pull => 'Pull';
  @override
  String pullBehind({required Object count}) => '${count} atrás';
  @override
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';
  @override
  String get push => 'Push';
  @override
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} commit',
        other: '${n} commits',
      );
  @override
  String pushCommitsUpstream({
    required Object commits,
    required Object upstream,
  }) => '${commits} para ${upstream}';
  @override
  String get forcePush => 'Force Push';
  @override
  String forcePushNoUpstream({required Object branch}) =>
      'Não é possível fazer force-push: nenhum upstream definido para ${branch}.';
  @override
  String get commit => 'Commit';
  @override
  String get stageAll => 'Fazer Stage de Tudo';
  @override
  String get unstageAll => 'Tirar Tudo do Stage';
  @override
  String get discardAll => 'Descartar Tudo';
  @override
  String get createBranch => 'Criar Branch';
  @override
  String get deleteBranch => 'Excluir Branch';
  @override
  String get renameBranch => 'Renomear Branch';
  @override
  String get stash => 'Stash';
  @override
  String get stashPop => 'Stash Pop';
  @override
  String get stashApply => 'Stash Apply';
  @override
  String get stashDrop => 'Stash Drop';
  @override
  String get createTag => 'Criar Tag';
  @override
  String get cherryPick => 'Cherry-pick';
  @override
  String get revert => 'Revert';
  @override
  String get stashConflictMessage =>
      'Stash aplicado com conflitos. Resolva na página de Mudanças.';
}

// Path: palette.pr
class _Translations$palette$pr$pt_BR extends Translations$palette$pr$en {
  _Translations$palette$pr$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get create => 'Criar PR';
  @override
  String get merge => 'Fazer Merge do PR';
  @override
  String get markReady => 'Marcar PR como Pronto';
}

// Path: palette.ai
class _Translations$palette$ai$pt_BR extends Translations$palette$ai$en {
  _Translations$palette$ai$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get generateCommit => 'Gerar Commit';
  @override
  String get reviewChanges => 'Revisar Mudanças';
  @override
  String get runMuse => 'Rodar a Muse';
  @override
  String debugRepo({required Object name}) => 'Depurar ${name}';
  @override
  String get describeSymptom => 'descreva um sintoma';
  @override
  String viewResult({required Object kind}) => 'Ver ${kind}';
  @override
  String get unseenResult => 'resultado não visto';
  @override
  String runningResult({required Object kind}) => 'AI: ${kind}…';
  @override
  String get running => 'rodando';
  @override
  String get kindCommitMessage => 'Mensagem de Commit';
  @override
  String get kindCodeReview => 'Code Review';
  @override
  String get kindMuseResult => 'Resultado da Muse';
  @override
  String get kindPresentation => 'Apresentação';
  @override
  String get kindDebugResult => 'Resultado do Debug';
}

// Path: palette.undo
class _Translations$palette$undo$pt_BR extends Translations$palette$undo$en {
  _Translations$palette$undo$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String cancel({required Object label}) => 'Cancelar: ${label}';
}

// Path: palette.navigation
class _Translations$palette$navigation$pt_BR
    extends Translations$palette$navigation$en {
  _Translations$palette$navigation$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get changes => 'Mudanças';
  @override
  String get history => 'Histórico';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get settings => 'Configurações';
  @override
  String get refresh => 'Atualizar';
}

// Path: palette.settings
class _Translations$palette$settings$pt_BR
    extends Translations$palette$settings$en {
  _Translations$palette$settings$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get reduceMotion => 'Reduzir Movimento';
  @override
  String get animateLogoUnfocused => 'Animar Logo Fora de Foco';
  @override
  String get instantBlameHover => 'Blame Instantâneo no Hover';
  @override
  String get autoSelectChanges => 'Selecionar Mudanças Automaticamente';
  @override
  String get fetchOnlineIssues => 'Buscar Issues Online';
  @override
  String get rememberWip => 'Lembrar Trabalho em Andamento';
  @override
  String get hideAiFeatures => 'Ocultar Recursos de AI';
  @override
  String get crashReporting => 'Relatório de Falhas';
  @override
  String get aiReadOnly => 'AI Só Leitura';
  @override
  String get stashCabinetExpanded => 'Armário de Stash Expandido';
  @override
  String get fileSortInverted => 'Ordenação de Arquivos Invertida';
}

// Path: palette.info
class _Translations$palette$info$pt_BR extends Translations$palette$info$en {
  _Translations$palette$info$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class _Translations$palette$debug$pt_BR extends Translations$palette$debug$en {
  _Translations$palette$debug$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get engineStatus => 'Status do Motor';
  @override
  String get engineStatusSubtitle => 'Diagnóstico do motor espectral LogosGit';
  @override
  String get fileCoupling => 'Acoplamento de Arquivos';
  @override
  String get fileCouplingSubtitle =>
      'Vizinhos de co-mudança mais próximos dos arquivos em stage';
  @override
  String get themeSpecimen => 'Amostra de Tema';
  @override
  String get themeSpecimenSubtitle =>
      'Todas as cores, ícones, níveis de texto e geometria';
}

// Path: palette.dev
class _Translations$palette$dev$pt_BR extends Translations$palette$dev$en {
  _Translations$palette$dev$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get testMergeEditor => 'Testar Editor de Merge';
  @override
  String get testHistorySurgery => 'Testar Cirurgia de Histórico';
  @override
  String get back => 'voltar';
  @override
  String get cancel => 'cancelar';
  @override
  String get buildingConflicts =>
      'montando conflitos de teste a partir do histórico…';
}

// Path: palette.historySurgery
class _Translations$palette$historySurgery$pt_BR
    extends Translations$palette$historySurgery$en {
  _Translations$palette$historySurgery$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Cirurgia de Histórico';
  @override
  String get subtitle =>
      'Reescreve o histórico para remover arquivos permanentemente';
}

// Path: palette.orrery
class _Translations$palette$orrery$pt_BR
    extends Translations$palette$orrery$en {
  _Translations$palette$orrery$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Orrery';
  @override
  String get subtitle =>
      'Percorra o histórico estrutural do repo pelo manifold';
}

// Path: palette.command
class _Translations$palette$command$pt_BR
    extends Translations$palette$command$en {
  _Translations$palette$command$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String complete({required Object label}) => '${label} concluído';
  @override
  String failed({required Object label, required Object message}) =>
      '${label} falhou: ${message}';
  @override
  String get copy => 'Copiar';
}

// Path: palette.search
class _Translations$palette$search$pt_BR
    extends Translations$palette$search$en {
  _Translations$palette$search$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get hintDefault => 'buscar tudo...';
  @override
  String get hintElevated => 'elevado — todas as ações';
  @override
  String get emptyTypeToSearch => 'digite para buscar';
  @override
  String get emptyNoResults => 'sem resultados';
}

// Path: palette.wick
class _Translations$palette$wick$pt_BR extends Translations$palette$wick$en {
  _Translations$palette$wick$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'wick';
  @override
  String get coupledFallback => 'acoplado';
}

// Path: palette.gitCache
class _Translations$palette$gitCache$pt_BR
    extends Translations$palette$gitCache$en {
  _Translations$palette$gitCache$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'atual';
  @override
  String get staged => 'em stage';
  @override
  String get modified => 'modificado';
}

// Path: releaseNotes.about
class _Translations$releaseNotes$about$pt_BR
    extends Translations$releaseNotes$about$en {
  _Translations$releaseNotes$about$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$releaseNotes$about$whyFlutter$pt_BR whyFlutter =
      _Translations$releaseNotes$about$whyFlutter$pt_BR._(_root);
  @override
  late final _Translations$releaseNotes$about$spectralEngine$pt_BR
  spectralEngine = _Translations$releaseNotes$about$spectralEngine$pt_BR._(
    _root,
  );
  @override
  late final _Translations$releaseNotes$about$whereGoing$pt_BR whereGoing =
      _Translations$releaseNotes$about$whereGoing$pt_BR._(_root);
}

// Path: releaseNotes.legal
class _Translations$releaseNotes$legal$pt_BR
    extends Translations$releaseNotes$legal$en {
  _Translations$releaseNotes$legal$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get copyright => '© 2026 Woflo Labs';
  @override
  String get license =>
      'GPL-3.0-or-later · núcleo de pesquisa community-source WLCSL · sem garantia';
}

// Path: repoSummary.backbone
class _Translations$repoSummary$backbone$pt_BR
    extends Translations$repoSummary$backbone$en {
  _Translations$repoSummary$backbone$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}` (${lines}) — ${region}';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} linha',
        other: '${n} linhas',
      );
  @override
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class _Translations$repoSummary$glance$pt_BR
    extends Translations$repoSummary$glance$en {
  _Translations$repoSummary$glance$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} arquivo.',
        other: '${n} arquivos.',
      );
  @override
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} linha (${bytes}).',
        other: '${n} linhas (${bytes}).',
      );
  @override
  String roles({required Object parts}) => 'Papéis — ${parts}.';
  @override
  String showingNofM({required Object active, required Object total}) =>
      'Mostrando ${active} de ${total} arquivos, ordenados por centralidade estrutural.';
}

// Path: repoSummary.heading
class _Translations$repoSummary$heading$pt_BR
    extends Translations$repoSummary$heading$en {
  _Translations$repoSummary$heading$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get atAGlance => 'Num relance';
  @override
  String get core => 'Núcleo';
  @override
  String get gettingStarted => 'Primeiros passos';
  @override
  String get regions => 'Regiões';
  @override
  String get shape => 'Forma';
}

// Path: repoSummary.pitch
class _Translations$repoSummary$pitch$pt_BR
    extends Translations$repoSummary$pitch$en {
  _Translations$repoSummary$pitch$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String empty({required Object detail}) =>
      'Um repositório sem arquivos de texto legíveis${detail}.';
  @override
  String emptyBinary({required Object n}) => '${n} binário';
  @override
  String emptyUnreadable({required Object n}) => '${n} ilegível';
  @override
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'Um repositório de ${n} arquivo ativo.',
        other: 'Um repositório de ${n} arquivos ativos.',
      );
  @override
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'Um repositório de ${n} arquivo ativo — ${regions}.',
        other: 'Um repositório de ${n} arquivos ativos — ${regions}.',
      );
}

// Path: repoSummary.region
class _Translations$repoSummary$region$pt_BR
    extends Translations$repoSummary$region$en {
  _Translations$repoSummary$region$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String bodyCommonDir({required Object dir}) => 'Tudo em `${dir}`.';
  @override
  String get bodyCommonDirSeparator => ' ';
  @override
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '1 núcleo',
        other: '${n} núcleo',
      );
  @override
  String get bodyCoreSeparator => ', ';
  @override
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'Um arquivo',
        other: '${n} arquivos',
      );
  @override
  String connectsTo({required Object linked}) => 'Conecta a: ${linked}.';
  @override
  String get filesLabel => 'Arquivos:';
}

// Path: repoSummary.shape
class _Translations$repoSummary$shape$pt_BR
    extends Translations$repoSummary$shape$en {
  _Translations$repoSummary$shape$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get bulk =>
      'Base de código densamente interconectada: a maioria dos arquivos participa de uma grande vizinhança de mudança compartilhada.';
  @override
  String get crystalline =>
      'Base de código em forma de rede: acoplamento uniforme e regular entre arquivos, com estrutura local previsível.';
  @override
  String get goe =>
      'Base de código ricamente interconectada: acoplamentos espalhados pelos arquivos sem uma espinha dominante.';
  @override
  String get modular =>
      'Base de código modular: várias regiões coesas com acoplamento cruzado limitado. Trabalhar numa região raramente perturba outra.';
  @override
  String get poisson =>
      'Base de código frouxamente acoplada: os arquivos evoluem em grande parte por conta própria, com mudança compartilhada ocasional.';
  @override
  String get tree =>
      'Base de código em forma de árvore: uma espinha dominante com branches dependentes. A mudança normalmente se propaga do núcleo para fora.';
}

// Path: settings.language
class _Translations$settings$language$pt_BR
    extends Translations$settings$language$en {
  _Translations$settings$language$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Idioma';
  @override
  String get summary =>
      'Idioma da interface deste app. Saídas do Git, logs e diagnósticos permanecem em inglês para que relatórios de bug continuem pesquisáveis.';
  @override
  String get label => 'IDIOMA DE EXIBIÇÃO';
  @override
  String get systemDefault => 'Padrão do sistema';
  @override
  String systemDefaultDetail({required Object resolved}) =>
      'Segue o idioma do seu SO (${resolved})';
  @override
  String get disclosureSource =>
      'Idioma de origem, escrito pelos desenvolvedores.';
  @override
  String disclosureAi({required Object model}) =>
      'Traduzido por máquina via ${model}, ainda sem revisão humana. Correções são bem-vindas.';
  @override
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) => 'Traduzido por máquina via ${model}. ${percent}% revisado por humanos.';
  @override
  String get disclosureHuman => 'Tradução humana, mantida pela comunidade.';
  @override
  String reviewedBy({required Object names}) => 'Revisado por ${names}.';
}

// Path: settings.sectionLabels
class _Translations$settings$sectionLabels$pt_BR
    extends Translations$settings$sectionLabels$en {
  _Translations$settings$sectionLabels$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get preferences => 'Preferências';
  @override
  String get shortcuts => 'Atalhos';
  @override
  String get behaviour => 'Comportamento';
  @override
  String get aiProviders => 'Provedores de AI';
  @override
  String get modelSlots => 'Slots de Modelo';
  @override
  String get tools => 'Ferramentas';
  @override
  String get diagnostics => 'Diagnósticos';
  @override
  String get offenders => 'Culpados';
  @override
  String get release => 'Versão';
}

// Path: settings.errors
class _Translations$settings$errors$pt_BR
    extends Translations$settings$errors$en {
  _Translations$settings$errors$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get saveGuardrailProfile => 'Falha ao salvar o perfil de guardrail.';
  @override
  String get saveRetentionPolicy => 'Falha ao salvar a política de retenção.';
  @override
  String get saveUpdateChannel => 'Falha ao salvar o canal de atualização.';
  @override
  String get saveModelSelection => 'Falha ao salvar a seleção de modelo de AI.';
  @override
  String get saveModelAlias => 'Falha ao salvar o apelido do modelo.';
  @override
  String get saveCommitMessageModelSlot =>
      'Falha ao salvar o slot de modelo de mensagem de commit.';
  @override
  String get saveReviewModelSlot =>
      'Falha ao salvar o slot de modelo de review.';
  @override
  String get saveCommitMessageCustomPrompt =>
      'Falha ao salvar o prompt personalizado de mensagem de commit.';
  @override
  String get saveReviewGuide => 'Falha ao salvar o guia de review.';
  @override
  String get saveMuseNotes => 'Falha ao salvar as notas da muse.';
  @override
  String get saveReviewDoubleCheck =>
      'Falha ao salvar o modo de dupla checagem do review.';
  @override
  String get saveApiPiggybackCli =>
      'Falha ao salvar a CLI de piggyback da API.';
  @override
  String get saveCliTimeout => 'Falha ao salvar o tempo limite da CLI.';
  @override
  String get stopAllCli =>
      'Não foi possível parar as sessões de CLI em andamento.';
  @override
  String clearLocalData({required Object error}) =>
      'Não foi possível limpar os dados locais: ${error}';
}

// Path: settings.promptStatus
class _Translations$settings$promptStatus$pt_BR
    extends Translations$settings$promptStatus$en {
  _Translations$settings$promptStatus$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get editing => 'Editando';
  @override
  String get saving => 'Salvando';
  @override
  String get saveFailed => 'Falha ao salvar';
}

// Path: settings.clearData
class _Translations$settings$clearData$pt_BR
    extends Translations$settings$clearData$en {
  _Translations$settings$clearData$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => 'Limpar dados locais';
  @override
  String get clear => 'Limpar';
  @override
  String get confirmDiagnostics =>
      'Limpar amostras de diagnóstico locais e medições de desempenho?';
  @override
  String get confirmAudit =>
      'Limpar registros locais de metadados de auditoria de AI?';
  @override
  String get confirmAll =>
      'Limpar todas as amostras de diagnóstico locais e registros de metadados de auditoria de AI?';
  @override
  String get confirmWipeAll =>
      'Apagar todos os dados locais do app — incluindo a lista de repos recentes — e sair? Seus repositórios git de verdade no disco não são tocados.';
  @override
  String get confirmReset =>
      'Resetar os dados locais do app e sair?\n\nConfigurações, tema, onboarding, preferências de AI, telemetria e caches de engram são limpos. Sua lista de repos recentes sobrevive.';
}

// Path: settings.guardrailMacro
class _Translations$settings$guardrailMacro$pt_BR
    extends Translations$settings$guardrailMacro$en {
  _Translations$settings$guardrailMacro$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'solto';
  @override
  String get balanced => 'equilibrado';
  @override
  String get strict => 'rígido';
  @override
  String get paranoid => 'paranoico';
}

// Path: settings.guardrails
class _Translations$settings$guardrails$pt_BR
    extends Translations$settings$guardrails$en {
  _Translations$settings$guardrails$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Guardrails';
  @override
  String get summary => 'Quão atenta é a automação em toda a experiência.';
}

// Path: settings.appearance
class _Translations$settings$appearance$pt_BR
    extends Translations$settings$appearance$en {
  _Translations$settings$appearance$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Aparência';
  @override
  String get summary => 'Clima e atmosfera globais da interface.';
}

// Path: settings.retention
class _Translations$settings$retention$pt_BR
    extends Translations$settings$retention$en {
  _Translations$settings$retention$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Retenção de Dados Locais';
  @override
  String get summaryDiagnostics => 'Política de retenção de diagnósticos.';
  @override
  String get summaryWithAudit =>
      'Política de retenção de diagnósticos e auditoria de AI.';
  @override
  String get unitDays => 'dias';
  @override
  String get unitMb => 'MB';
  @override
  String get includesNote =>
      'Inclui diagnósticos, medições de desempenho e metadados.';
}

// Path: settings.navigation
class _Translations$settings$navigation$pt_BR
    extends Translations$settings$navigation$en {
  _Translations$settings$navigation$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Navegação e Dinâmicas';
  @override
  String get summaryShortcuts => 'Atalhos e comportamento da interface.';
  @override
  String get summaryWithAi =>
      'Atalhos, comportamento da interface e roteamento de AI.';
}

// Path: settings.behaviour
class _Translations$settings$behaviour$pt_BR
    extends Translations$settings$behaviour$en {
  _Translations$settings$behaviour$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Dinâmicas Comportamentais';
}

// Path: settings.retentionClear
class _Translations$settings$retentionClear$pt_BR
    extends Translations$settings$retentionClear$en {
  _Translations$settings$retentionClear$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get diag => 'Diag';
  @override
  String get audit => 'Auditoria';
  @override
  String get all => 'Tudo';
  @override
  String get clearsHint => '<-- limpa';
}

// Path: settings.channels
class _Translations$settings$channels$pt_BR
    extends Translations$settings$channels$en {
  _Translations$settings$channels$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get stable => 'STABLE';
  @override
  String get beta => 'BETA';
  @override
  String get dev => 'DEV';
}

// Path: settings.pollResult
class _Translations$settings$pollResult$pt_BR
    extends Translations$settings$pollResult$en {
  _Translations$settings$pollResult$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get upToDate => 'em dia';
  @override
  String updateAvailable({required Object version}) => '${version} disponível';
  @override
  String get notConfigured => 'sem servidor de atualização';
  @override
  String notFound({required Object channel}) => 'nenhuma release ${channel}';
  @override
  String get unreachable => 'inacessível';
  @override
  String get badManifest => 'manifesto inválido';
}

// Path: settings.keybindingProfile
class _Translations$settings$keybindingProfile$pt_BR
    extends Translations$settings$keybindingProfile$en {
  _Translations$settings$keybindingProfile$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Perfil de atalhos';
  @override
  String get porcelain => 'Porcelain';
  @override
  String get numeric => 'Numérico';
  @override
  String get porcelainDescription =>
      'Atalhos encadeados (G e depois C, H, B…).';
  @override
  String get numericDescription => 'Atalhos numéricos de uma tecla (1, 2, 3…).';
}

// Path: settings.apiKeys
class _Translations$settings$apiKeys$pt_BR
    extends Translations$settings$apiKeys$en {
  _Translations$settings$apiKeys$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get keyHintDefault => 'chave de api';
  @override
  String get endpointHint => 'endpoint';
  @override
  String get test => 'Testar';
  @override
  String get hide => 'Ocultar';
  @override
  String get show => 'Mostrar';
}

// Path: settings.shortcuts
class _Translations$settings$shortcuts$pt_BR
    extends Translations$settings$shortcuts$en {
  _Translations$settings$shortcuts$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get navigate => 'navegar';
  @override
  String get staging => 'stage';
  @override
  String get branchesPrs => 'branches e PRs';
  @override
  String get modifiers => 'modificadores';
  @override
  String get changes => 'Mudanças';
  @override
  String get history => 'Histórico';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Trocar (sempre)';
  @override
  String get search => 'Buscar';
  @override
  String get dismiss => 'Dispensar';
  @override
  String get refresh => 'Atualizar';
  @override
  String get shortcuts => 'Atalhos';
  @override
  String get nextChange => 'Próxima mudança';
  @override
  String get prevChange => 'Mudança anterior';
  @override
  String get toggleLine => 'Alternar linha';
  @override
  String get toggleHunk => 'Alternar hunk';
  @override
  String get toggleFile => 'Alternar arquivo';
  @override
  String get pinContext => 'Fixar contexto';
  @override
  String get commit => 'Commit';
  @override
  String get acceptHint => 'Aceitar dica';
  @override
  String get undo => 'Desfazer';
  @override
  String get navigateRow => 'Navegar';
  @override
  String get expand => 'Expandir';
  @override
  String get checkout => 'Checkout';
  @override
  String get approve => 'Aprovar';
  @override
  String get requestChanges => 'Solicitar mudanças';
  @override
  String get selectRange => 'Selecionar intervalo';
  @override
  String get extendedMenu => 'Menu estendido';
}

// Path: settings.toggles
class _Translations$settings$toggles$pt_BR
    extends Translations$settings$toggles$en {
  _Translations$settings$toggles$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get aiReadOnlyLabel => 'Modo AI só leitura';
  @override
  String get aiReadOnlyDescription =>
      'Impede que a AI escreva ou coloque mudanças em stage automaticamente.';
  @override
  String get logoMotionLabel => 'O logo anima quando fora da aba';
  @override
  String get logoMotionDescriptionEnabled =>
      'Ele é feito pra ser eficiente, não magoe os sentimentos dele';
  @override
  String get logoMotionDescriptionDisabled => ':(';
  @override
  String get rememberWipLabel => 'Lembrar trabalho em andamento';
  @override
  String get rememberWipDescription =>
      'Mantenha seus rascunhos de commit e a seleção de arquivos entre sessões.';
  @override
  String get stashCabinetLabel => 'O armário de stash começa expandido';
  @override
  String get stashCabinetDescription =>
      'Mostra a gaveta do arquivo aberta por padrão quando um repo tem prateleiras.';
  @override
  String get instantBlameLabel => 'Blame instantâneo no hover';
  @override
  String get instantBlameDescription =>
      'Pula o atraso de 180ms antes de o blame aparecer numa linha do diff.';
  @override
  String get autoSelectLabel => 'Selecionar novas mudanças automaticamente';
  @override
  String get autoSelectDescription =>
      'Arquivos recém-rastreados ou alterados são adicionados à seleção de commit automaticamente.';
  @override
  String get changeIdLabel => 'Gravar cabeçalhos change-id';
  @override
  String get changeIdDescription =>
      'Adiciona aos novos commits um cabeçalho de identidade change-id (a convenção do Jujutsu, GitButler e Gerrit). Cada commit é reescrito uma vez logo após ser criado.';
  @override
  String get fetchIssuesLabel => 'Buscar issues online ao carregar branches';
  @override
  String get fetchIssuesDescription =>
      'Puxa detalhes de PRs e issues do seu provedor git em segundo plano quando a página de branches abre.';
  @override
  String get hateAiLabel => 'Eu odeio AI';
  @override
  String get hateAiDescription =>
      'Bane todos os recursos apoiados em LLM. O Logos continua rodando porque é só matemática espectral.';
}

// Path: settings.diffDiffability
class _Translations$settings$diffDiffability$pt_BR
    extends Translations$settings$diffDiffability$en {
  _Translations$settings$diffDiffability$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'diff-abilidade do diff';
}

// Path: settings.modelSlots
class _Translations$settings$modelSlots$pt_BR
    extends Translations$settings$modelSlots$en {
  _Translations$settings$modelSlots$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get loadingProviders => 'Carregando provedores...';
  @override
  String get refreshingProviders => 'Atualizando diagnósticos de provedor...';
  @override
  String get routeDescription =>
      'Renomeie e roteie configurações para qualquer modelo de provedor detectado.';
  @override
  String get loadingCategories => 'Carregando categorias de modelo...';
  @override
  String get noOptions =>
      'Ainda não há opções de modelo disponíveis. Detecte primeiro uma CLI de AI local compatível.';
  @override
  String get slotsAppearWhenAvailable =>
      'As configurações de slot de modelo aparecerão aqui assim que houver modelos de provedor disponíveis.';
  @override
  String get effortDefault => 'padrão';
  @override
  String get noModelsForSlot => 'Nenhum modelo detectado para este slot.';
  @override
  String viaProvider({required Object provider}) => 'via ${provider}';
  @override
  String get customModelId => 'id de modelo personalizado';
}

// Path: settings.modelPicker
class _Translations$settings$modelPicker$pt_BR
    extends Translations$settings$modelPicker$en {
  _Translations$settings$modelPicker$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String noMatch({required Object query}) =>
      'nenhum modelo bate com "${query}"';
  @override
  String get noModels => 'nenhum modelo disponível';
  @override
  String get filterHint => 'filtrar modelos...';
  @override
  String get warming => 'aquecendo…';
  @override
  String get detailsUnavailable => 'detalhes indisponíveis';
  @override
  String get free => 'grátis';
}

// Path: settings.aiFeatures
class _Translations$settings$aiFeatures$pt_BR
    extends Translations$settings$aiFeatures$en {
  _Translations$settings$aiFeatures$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get commitDescription =>
      'Rascunha mensagens de commit a partir das mudanças em stage usando suas preferências de estrutura, voz e cobertura.';
  @override
  String get reviewDescription =>
      'Revisa o escopo atual do commit antes de você fazer o commit.';
  @override
  String get museDescription =>
      'Oráculo de três fases que faz brainstorm e depois sintetiza uma direção adiante para o diff.';
}

// Path: settings.commitEditor
class _Translations$settings$commitEditor$pt_BR
    extends Translations$settings$commitEditor$en {
  _Translations$settings$commitEditor$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get styleGuide => 'Guia de Estilo';
  @override
  String get styleGuideHint =>
      'Opcional. Voz / tom / proibições. O formato acima cuida do esqueleto.';
}

// Path: settings.review
class _Translations$settings$review$pt_BR
    extends Translations$settings$review$en {
  _Translations$settings$review$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Notas adicionais para revisar junto';
  @override
  String get doubleCheckLabel => 'Dupla checagem do review';
  @override
  String get doubleCheckDescription =>
      'Roda uma segunda passada de verificação antes de mostrar o relatório final.';
}

// Path: settings.museHint
class _Translations$settings$museHint$pt_BR
    extends Translations$settings$museHint$en {
  _Translations$settings$museHint$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'algo pra guiar de leve? o humor tá bom hoje.';
  @override
  String get balanced => 'no que se deter, o que pular. honesto, não duro.';
  @override
  String get strict =>
      'os padrões. as proibições. o que a muse não deixa passar.';
  @override
  String get paranoid =>
      'afine a lente. em que frequências o manifold deve vibrar?';
}

// Path: settings.museEditor
class _Translations$settings$museEditor$pt_BR
    extends Translations$settings$museEditor$en {
  _Translations$settings$museEditor$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Notas adicionais para a muse';
}

// Path: settings.museStage
class _Translations$settings$museStage$pt_BR
    extends Translations$settings$museStage$en {
  _Translations$settings$museStage$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get brainstorm => 'BRAINSTORM';
  @override
  String get synthesize => 'SINTETIZAR';
  @override
  String get slot => 'slot';
  @override
  String get ideaCountLoose => '~12 ideias';
  @override
  String get ideaCountBalanced => '~16 ideias';
  @override
  String get ideaCountStrict => '~20 ideias';
  @override
  String get ideaCountParanoid => '~24 ideias';
  @override
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  guardrail: ${macro}';
}

// Path: settings.lensAxis
class _Translations$settings$lensAxis$pt_BR
    extends Translations$settings$lensAxis$en {
  _Translations$settings$lensAxis$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get folder => 'PASTA';
  @override
  String get history => 'HISTÓRICO';
  @override
  String get far => 'LONGE';
  @override
  String get near => 'PERTO';
}

// Path: settings.logosLens
class _Translations$settings$logosLens$pt_BR
    extends Translations$settings$logosLens$en {
  _Translations$settings$logosLens$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get moduleMap => 'mapa de módulos';
  @override
  String get repoCenters => 'centros do repo';
  @override
  String get neighbors => 'vizinhos';
  @override
  String get toTouch => 'no que mexer a seguir';
  @override
  String get relevanceEngine => 'motor de relevância';
  @override
  String get description =>
      'lê como os arquivos se movem juntos ao longo de estrutura, histórico e ritmo, pra que o Manifold saiba o que importa, não só o que mudou.';
  @override
  String get withinReach => 'ao alcance';
  @override
  String get gate => 'portão';
  @override
  String get nearest => 'mais próximo';
  @override
  String get warming => 'aquecendo';
  @override
  String get emptyOpenRepo => 'abra um repo pra\nver a lente ao vivo';
  @override
  String get emptyNoFiles =>
      'nenhum arquivo ao\nalcance — arraste\nrumo a HISTÓRICO';
}

// Path: settings.sortGuide
class _Translations$settings$sortGuide$pt_BR
    extends Translations$settings$sortGuide$en {
  _Translations$settings$sortGuide$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Guia de ordenação de mudanças';
  @override
  String get related =>
      'Arquivos que mudam juntos ficam agrupados. A questão principal vem primeiro; o contexto segue.';
  @override
  String get relatedInverted =>
      'Mudanças isoladas vêm primeiro. Clusters fortemente acoplados afundam para o fim.';
  @override
  String get alphabetical =>
      'Simples A → Z por caminho. Sem diferenciar maiúsculas, números em ordem natural.';
  @override
  String get alphabeticalInverted =>
      'Simples Z → A por caminho. Sem diferenciar maiúsculas, números em ordem natural.';
  @override
  String get impact =>
      'As mudanças mais pesadas vêm à tona primeiro. O churn é ponderado; binários e arquivos novos ganham impulso.';
  @override
  String get impactInverted =>
      'As mudanças mais leves vêm à tona primeiro. Vitórias rápidas no topo; os pesos-pesados esperam.';
  @override
  String get nearRelated => 'por relação';
  @override
  String get alphabeticalShort => 'alfabética';
  @override
  String get byImpact => 'por impacto';
  @override
  String get flipped => 'invertida';
  @override
  String get peek => 'espiar';
}

// Path: settings.piggyback
class _Translations$settings$piggyback$pt_BR
    extends Translations$settings$piggyback$en {
  _Translations$settings$piggyback$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get apiModelsUse => 'Modelos de API usam';
  @override
  String get codexNotDetected => 'codex não detectado';
  @override
  String get dormant => 'DORMENTE';
}

// Path: settings.diffStage
class _Translations$settings$diffStage$pt_BR
    extends Translations$settings$diffStage$en {
  _Translations$settings$diffStage$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get viewer => 'visualizador';
  @override
  String get media => 'mídia';
  @override
  String get binary => 'binário';
  @override
  String get hidden => 'oculto';
}

// Path: settings.undoScope
class _Translations$settings$undoScope$pt_BR
    extends Translations$settings$undoScope$en {
  _Translations$settings$undoScope$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get destructiveActions => 'ações destrutivas';
  @override
  String get discards => 'descartes';
  @override
  String get commits => 'commits';
  @override
  String get commitPush => 'commit + push';
  @override
  String get all => 'tudo';
}

// Path: settings.undoWindow
class _Translations$settings$undoWindow$pt_BR
    extends Translations$settings$undoWindow$en {
  _Translations$settings$undoWindow$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Janela de desfazer';
  @override
  String get off => 'Desligado';
  @override
  String descriptionInstant({required Object scope}) =>
      '${scope} são finalizados na hora.';
  @override
  String descriptionDelayed({required Object seconds, required Object scope}) =>
      '${seconds}s antes de ${scope} serem finalizados.';
  @override
  String get cycleScopeTooltip =>
      'Clique para alternar o escopo · também arraste pra cima/baixo no slider';
  @override
  String get resetTooltip =>
      'Redefine todas as ações para usar a janela padrão';
}

// Path: settings.guardrailPhrase
class _Translations$settings$guardrailPhrase$pt_BR
    extends Translations$settings$guardrailPhrase$en {
  _Translations$settings$guardrailPhrase$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get probablyFine => 'Provavelmente ok significa ok';
  @override
  String get proper => 'Uma leitura de verdade, lógica, integração, padrões';
  @override
  String get lookAgain => 'Olhe de novo. Algo pode estar se escondendo';
  @override
  String get assumeWrong => 'Presuma que algo está errado. Ache.';
}

// Path: settings.reviewGuideHint
class _Translations$settings$reviewGuideHint$pt_BR
    extends Translations$settings$reviewGuideHint$en {
  _Translations$settings$reviewGuideHint$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get focusHigh =>
      'ex.: Foque na lógica de alto nível e nos bugs maiores. Seja breve e tolerante.';
  @override
  String get surfaceBugs =>
      'ex.: Traga à tona bugs potenciais, inconsistências arquiteturais e falhas de casos extremos.';
  @override
  String get scrutinize =>
      'ex.: Escrutine cada linha em busca de otimização, segurança e conformidade com padrões.';
  @override
  String get trustNothing =>
      'ex.: Não confie em nada. Questione todo efeito colateral. Trate cada linha como uma falha em potencial.';
  @override
  String get optional =>
      'Orientação opcional sobre com o que o review deve se importar.';
}

// Path: settings.commitFormat
class _Translations$settings$commitFormat$pt_BR
    extends Translations$settings$commitFormat$en {
  _Translations$settings$commitFormat$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Formato';
  @override
  String get peek => 'espiar';
  @override
  String get structure => 'Estrutura';
  @override
  String get voice => 'Voz';
  @override
  String get coverage => 'Cobertura';
  @override
  String get structureTitleBody => 'título + corpo';
  @override
  String get structureTitleOnly => 'só título';
  @override
  String get structureFreeform => 'livre';
  @override
  String get voiceVerbLed => 'orientada à ação';
  @override
  String get voiceDescriptive => 'descritiva';
  @override
  String get voiceNarrative => 'narrativa';
  @override
  String get coverageEssentials => 'essencial';
  @override
  String get coverageBalanced => 'equilibrada';
  @override
  String get coverageEverything => 'tudo';
}

// Path: settings.commitPreview
class _Translations$settings$commitPreview$pt_BR
    extends Translations$settings$commitPreview$en {
  _Translations$settings$commitPreview$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$pt_BR title =
      _Translations$settings$commitPreview$title$pt_BR._(_root);
  @override
  late final _Translations$settings$commitPreview$base$pt_BR base =
      _Translations$settings$commitPreview$base$pt_BR._(_root);
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$pt_BR
  balancedSuffix = _Translations$settings$commitPreview$balancedSuffix$pt_BR._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$pt_BR
  everythingSuffix =
      _Translations$settings$commitPreview$everythingSuffix$pt_BR._(_root);
}

// Path: settings.externalTools
class _Translations$settings$externalTools$pt_BR
    extends Translations$settings$externalTools$en {
  _Translations$settings$externalTools$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Ferramentas Externas';
  @override
  String get summary =>
      'Clique com o botão direito num projeto na barra lateral para abri-lo com uma destas. Os args usam {path} para a pasta do projeto.';
  @override
  String get detecting => 'Detectando ferramentas instaladas…';
  @override
  String get allPresetsAdded =>
      'Todos os presets conhecidos já foram adicionados. Use “+ Personalizado” para adicionar mais.';
  @override
  String get noToolsConfigured =>
      'Nenhuma ferramenta configurada ainda. Adicione uma acima.';
  @override
  String get categoryAi => 'ai';
  @override
  String get categoryEditors => 'editores';
  @override
  String get categoryExplore => 'explorar';
  @override
  String get categoryOps => 'ops';
  @override
  String get categoryGitOps => 'git ops';
  @override
  String get nameHint => 'Nome';
  @override
  String get commandHint => 'comando';
  @override
  String get test => 'testar';
  @override
  String get removeTool => 'Remover ferramenta';
  @override
  String get modeTerminal => 'terminal';
  @override
  String get modeDetached => 'desanexado';
}

// Path: settings.apiUsage
class _Translations$settings$apiUsage$pt_BR
    extends Translations$settings$apiUsage$en {
  _Translations$settings$apiUsage$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String thisMonth({required Object used, required Object limit}) =>
      '${used}${limit} este mês';
}

// Path: settings.gitea
class _Translations$settings$gitea$pt_BR
    extends Translations$settings$gitea$en {
  _Translations$settings$gitea$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Tokens do Gitea';
  @override
  String get hostHint => 'host';
  @override
  String get tokenHint => 'token';
  @override
  String get save => 'salvar';
}

// Path: settings.wick
class _Translations$settings$wick$pt_BR extends Translations$settings$wick$en {
  _Translations$settings$wick$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get selectExecutable => 'Selecionar executável do wick';
  @override
  String get connected => 'wick · conectado';
  @override
  String get pathToExecutable => 'wick · caminho do executável';
  @override
  String get off => 'off';
  @override
  String get disableHint => 'Desativar a integração do wick';
  @override
  String get enableHint => 'Ativar a integração do wick';
}

// Path: settings.integrations
class _Translations$settings$integrations$pt_BR
    extends Translations$settings$integrations$en {
  _Translations$settings$integrations$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'e Integrações';
  @override
  String get alpha => 'alpha';
  @override
  String get planned => 'planejado';
  @override
  String get lspComingSoon => 'lsp · em breve';
  @override
  String get alphaMathConnected => 'alpha-math · conectado';
  @override
  String get alphaMathComingSoon => 'alpha-math · em breve';
}

// Path: settings.reduceMotion
class _Translations$settings$reduceMotion$pt_BR
    extends Translations$settings$reduceMotion$en {
  _Translations$settings$reduceMotion$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Reduzir movimento';
  @override
  String get subtitleStill => 'Parado… feito gelo?';
  @override
  String get subtitleFlow => 'Fluir como água.';
}

// Path: settings.resetQuit
class _Translations$settings$resetQuit$pt_BR
    extends Translations$settings$resetQuit$en {
  _Translations$settings$resetQuit$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get resetAndQuit => 'RESETAR E SAIR';
  @override
  String get keepRepos => 'MANTER REPOS';
  @override
  String get wipeAll => 'APAGAR TUDO';
}

// Path: settings.diagnostics
class _Translations$settings$diagnostics$pt_BR
    extends Translations$settings$diagnostics$en {
  _Translations$settings$diagnostics$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get commandDiagnostics => 'Diagnóstico de Comandos';
  @override
  String get networkFlowTelemetry => 'Telemetria de Fluxo de Rede';
  @override
  String get clearSamples => 'Limpar Amostras';
  @override
  String get clearMetrics => 'Limpar Métricas';
  @override
  String get clearTimings => 'Limpar Medições';
  @override
  String get recalibrate => 'RECALIBRAR';
  @override
  String get ok => 'ok';
  @override
  String get noCommandTimings =>
      'Nenhuma medição de comando capturada ainda. Rode ações normais para popular os diagnósticos.';
  @override
  String get noBackendSamples =>
      'Nenhuma amostra de comando de backend capturada ainda. Rode ações de git e de configurações para popular este log.';
  @override
  String get noDiffSessions =>
      'Nenhuma sessão de renderização de diff capturada ainda. Abra e role diffs de arquivo para popular este painel.';
  @override
  String get noUiSessions =>
      'Nenhuma sessão de medição de UI capturada ainda. Abra painéis e navegue por rotas para popular este painel.';
  @override
  String get recentOperations => 'Operações Recentes';
  @override
  String get recentBackendOperations => 'Operações Recentes de Backend';
  @override
  String get recentDiffSessions => 'Sessões Recentes de Diff';
  @override
  String get recentUiTimings => 'Medições Recentes de UI';
  @override
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} comando único',
        other: '${n} comandos únicos',
      );
  @override
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} comando com escopo',
        other: '${n} comandos com escopo',
      );
  @override
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
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
  List<String> get headersCommand => [
    'comando',
    'p50',
    'confiabilidade',
    'faixa',
  ];
  @override
  List<String> get headersBackend => ['escopo', 'p50', 'p95', 'falhas'];
  @override
  List<String> get headersDiff => [
    'renderizador',
    'primeiro paint',
    'frame p95',
    'raster p95',
    'jank',
  ];
  @override
  List<String> get headersUi => ['evento', 'p50', 'falhas', 'faixa'];
}

// Path: settings.telemetry
class _Translations$settings$telemetry$pt_BR
    extends Translations$settings$telemetry$en {
  _Translations$settings$telemetry$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} amostra',
        other: '${n} amostras',
      );
  @override
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} comando',
        other: '${n} comandos',
      );
  @override
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} sessão',
        other: '${n} sessões',
      );
  @override
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} evento',
        other: '${n} eventos',
      );
  @override
  String stability({required Object pct}) => '${pct}% de estabilidade';
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
class _Translations$settings$flowEngine$pt_BR
    extends Translations$settings$flowEngine$en {
  _Translations$settings$flowEngine$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get executionFlow => 'fluxo-de-execução';
  @override
  String get description =>
      'simula osciladores no código. traz à tona caminhos de execução frágeis antes que cristalizem em bugs.';
  @override
  String get idle => 'parado';
  @override
  String get emptyOpenRepo => 'abra um repo pra\nver a análise de fluxo';
  @override
  String get scanning => 'escaneando';
  @override
  String get analysing => 'analisando arquivos\nna lente…';
  @override
  String get fragility => 'fragilidade';
  @override
  String get findings => 'achados';
  @override
  String get gap => 'lacuna';
  @override
  String get clean => 'limpo';
  @override
  String get severity => 'severidade';
  @override
  String get critical => 'crítico';
  @override
  String get warn => 'alerta';
  @override
  String get info => 'info';
}

// Path: settings.museStrands
class _Translations$settings$museStrands$pt_BR
    extends Translations$settings$museStrands$en {
  _Translations$settings$museStrands$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get spark => 'faísca de inspiração · o passo imediatamente seguinte';
  @override
  String get current => 'correnteza na água · extensões no presente';
  @override
  String get horizon => 'olhar além do horizonte · direções que se estendem';
  @override
  String get fever => 'acordar de um sonho febril · provocações';
  @override
  String get echo => 'um eco pelo cânion · análogos em outros lugares';
  @override
  String get vertigo => 'vertigem na beira do penhasco · riscos adjacentes';
  @override
  String get ghost => 'o fantasma do que foi · contexto histórico';
  @override
  String get mirror => 'um espelho em água parada · inversões';
}

// Path: settings.cliPiggyback
class _Translations$settings$cliPiggyback$pt_BR
    extends Translations$settings$cliPiggyback$en {
  _Translations$settings$cliPiggyback$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Piggyback de CLI';
  @override
  String get clearCacheLabel => 'Limpar cache';
  @override
  String get clearCacheTooltip =>
      'Apaga os modelos em cache e re-sonda. Remove os que um provedor descartou.';
  @override
  String get refreshLabel => 'Atualizar provedores';
  @override
  String get refreshTooltip => 'Re-sonda todos os provedores agora.';
  @override
  String get body =>
      'Encaminha mensagens da interface direto para os binários de provedor locais.';
  @override
  String get cliTimeoutLabel => 'Tempo limite por execução';
  @override
  String get cliTimeoutUnitMinutes => 'minutos';
  @override
  String get cliTimeoutUnitMinute => 'minuto';
  @override
  String get forceStopLabel => 'Parar todas as sessões';
  @override
  String get forceStopTooltip =>
      'Força o encerramento de cada execução de CLI em andamento.';
  @override
  String get forceStopConfirmTitle => 'Parar as sessões de CLI em andamento?';
  @override
  String forceStopConfirmBody({required Object count}) =>
      'Isso força o encerramento de ${count} execuções de CLI em andamento. A saída delas será perdida.';
  @override
  String get forceStopConfirmAction => 'Parar todas';
  @override
  String get forceStopNoneRunning => 'Nenhuma sessão de CLI em andamento';
  @override
  String get forceStopRecordError =>
      'Interrompido — as sessões de CLI foram encerradas à força.';
}

// Path: settings.header
class _Translations$settings$header$pt_BR
    extends Translations$settings$header$en {
  _Translations$settings$header$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Preferências do Workspace';
  @override
  String get subtitle =>
      'Configure a estética global, as dinâmicas da interface e as salvaguardas operacionais centrais para todo o workspace.';
  @override
  String get releaseNotesTooltip => 'Notas de versão';
  @override
  String get replayOnboardingTooltip => 'Repetir onboarding';
}

// Path: settings.diagnosticsPanel
class _Translations$settings$diagnosticsPanel$pt_BR
    extends Translations$settings$diagnosticsPanel$en {
  _Translations$settings$diagnosticsPanel$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Diagnóstico de Desempenho';
  @override
  String get copyTrace => 'Copiar Rastro';
  @override
  String get offenderRanking => 'Ranking de Culpados';
  @override
  String get offenderRankingSubtitle =>
      'Causadores de latência entre os fluxos.';
  @override
  String get noOffenders =>
      'Nenhum ranking de culpados ainda. Capture atividade de diagnóstico para popular esta lista.';
}

// Path: settings.release
class _Translations$settings$release$pt_BR
    extends Translations$settings$release$en {
  _Translations$settings$release$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Implantação de Versão';
  @override
  String get summary => 'Configurações relacionadas a atualização.';
  @override
  String get deploymentChannel => 'CANAL DE IMPLANTAÇÃO';
  @override
  String get captureCrashDiagnostics => 'Capturar diagnósticos de falha';
  @override
  String get comingSoon => 'Em breve.';
  @override
  String get checking => 'VERIFICANDO…';
  @override
  String get pollForUpdates => 'VERIFICAR ATUALIZAÇÕES';
}

// Path: settings.providerStatus
class _Translations$settings$providerStatus$pt_BR
    extends Translations$settings$providerStatus$en {
  _Translations$settings$providerStatus$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get detecting => 'Detectando...';
  @override
  String get ready => 'Pronto';
  @override
  String get notDetected => 'Não detectado';
  @override
  String configured({required Object count}) => '${count} configurados';
  @override
  String get notConfigured => 'Não configurado';
  @override
  String get cliManaged => 'Gerenciado por CLI';
  @override
  String get connected => 'Conectado';
  @override
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} modelo',
        other: '${n} modelos',
      );
  @override
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} provedor',
        other: '${n} provedores',
      );
}

// Path: settings.meridiem
class _Translations$settings$meridiem$pt_BR
    extends Translations$settings$meridiem$en {
  _Translations$settings$meridiem$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get am => 'AM';
  @override
  String get pm => 'PM';
}

// Path: settings.offenders
class _Translations$settings$offenders$pt_BR
    extends Translations$settings$offenders$en {
  _Translations$settings$offenders$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get commandStream => 'Comando';
  @override
  String get diffStream => 'Renderização de Diff';
  @override
  String get uiStream => 'Medição de UI';
  @override
  String rendererName({required Object mode}) => 'renderizador ${mode}';
  @override
  String latencyFailMetric({required Object p95, required Object fail}) =>
      '${p95}ms p95 | ${fail}% falha';
  @override
  String jankFrameMetric({required Object jank, required Object frame}) =>
      '${jank}% jank | ${frame}ms frame p95';
  @override
  String inStream({required Object stream}) => 'em ${stream}';
}

// Path: sync.actions
class _Translations$sync$actions$pt_BR extends Translations$sync$actions$en {
  _Translations$sync$actions$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get syncLabel => 'Sincronizar';
  @override
  String get syncOpenRepoDetail =>
      'Abra um repositório para gerenciar operações de push e pull.';
  @override
  String get detachedHeadLabel => 'HEAD desanexado';
  @override
  String get detachedHeadDetail =>
      'Faça checkout de um branch antes de push ou pull.';
  @override
  String get publishBranchLabel => 'Publicar branch';
  @override
  String publishBranchDetail({required Object branch}) =>
      'Faz push de ${branch} e define o branch de rastreamento upstream.';
  @override
  String get publishButtonLabel => 'Publicar';
  @override
  String get syncBranchLabel => 'Sincronizar branch';
  @override
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => 'Puxa ${behindCount} com rebase, depois faz push de ${aheadCount}.';
  @override
  String get syncBranchButtonLabel => 'Pull (rebase) e push';
  @override
  String get pushBranchLabel => 'Push do branch';
  @override
  String pushBranchDetail({required Object count, required Object upstream}) =>
      'Faz push de ${count} para ${upstream}.';
  @override
  String get pushBranchButtonLabel => 'Push dos commits';
  @override
  String get pullUpdatesLabel => 'Puxar atualizações';
  @override
  String pullUpdatesDetail({required Object count, required Object upstream}) =>
      'Puxa ${count} de ${upstream}.';
  @override
  String syncUpToDateDetail({required Object upstream}) =>
      'Busca de ${upstream} e atualiza o status do upstream.';
}

// Path: sync.panel
class _Translations$sync$panel$pt_BR extends Translations$sync$panel$en {
  _Translations$sync$panel$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Carregando status remoto';
  @override
  String get loadingMessage =>
      'Verificando informações de rastreamento do branch.';
  @override
  String get remoteStatusUnavailable => 'Status remoto indisponível';
  @override
  String get noUpstream => 'sem upstream';
  @override
  String get aheadLabel => 'À frente';
  @override
  String get behindLabel => 'Atrás';
  @override
  String get treeLabel => 'Árvore';
  @override
  String get runningSync => 'Sincronizando…';
  @override
  String get fetching => 'Buscando…';
  @override
  String get fetchOnly => 'Só buscar';
  @override
  String get syncFailed => 'Falha na sincronização';
  @override
  String get forcePushRecoveryLabel => 'Force push (com lease)';
  @override
  String get conflictsToResolveTitle => 'Conflitos a resolver';
  @override
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} precisam de resolução: ${list}';
  @override
  String get resolveConflicts => 'Resolver conflitos';
  @override
  String get workingEllipsis => 'Trabalhando…';
  @override
  String lastActivity({required Object operation}) =>
      'Última atividade: ${operation}';
  @override
  String get noOutput => 'Sem saída.';
  @override
  String resolvedConflicts({required Object count}) => '${count} resolvidos.';
  @override
  String get cancelledUnchanged => 'Cancelado, árvore de trabalho inalterada.';
  @override
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) =>
      '${count} têm edições sem commit; faça commit primeiro para sincronizar com rebase (${list}).';
  @override
  String noUpstreamForForcePush({required Object branch}) =>
      'Não é possível fazer force-push: nenhum upstream configurado para "${branch}".';
}

// Path: sync.forcePush
class _Translations$sync$forcePush$pt_BR
    extends Translations$sync$forcePush$en {
  _Translations$sync$forcePush$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get confirmTitle => 'Force push (com lease)?';
  @override
  String target({required Object remote, required Object branch}) =>
      'Destino: ${remote}/${branch}';
  @override
  String get warning =>
      'Isto reescreve o branch remoto com o seu histórico local. Com lease, aborta se alguém fez push para o remoto depois do seu último fetch, mas mudanças já buscadas ainda serão sobrescritas. Use só quando você pretendia um rebase ou amend que divergiu o branch.';
  @override
  String get confirmButton => 'Force push';
}

// Path: xray.board
class _Translations$xray$board$pt_BR extends Translations$xray$board$en {
  _Translations$xray$board$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get movesWithModule => 'move junto com outro módulo';
  @override
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} revisor',
        other: '${n} revisores',
      );
  @override
  String get territory => 'Território';
  @override
  String get unreviewed => 'sem review';
}

// Path: xray.cadence
class _Translations$xray$cadence$pt_BR extends Translations$xray$cadence$en {
  _Translations$xray$cadence$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '${sum} commits · ${days} dias\n${lines}';
  @override
  String burstTooltipSingle({required Object n, required Object label}) =>
      '${n} commits em ${label}';
  @override
  String gapTooltip({required Object n, required Object label}) =>
      'intervalo de ${n} dias · ${label}';
  @override
  String reflogTooltip({required Object n, required Object label}) =>
      '${n} eventos de reflog em ${label}';
}

// Path: xray.cards
class _Translations$xray$cards$pt_BR extends Translations$xray$cards$en {
  _Translations$xray$cards$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$cards$branchModel$pt_BR branchModel =
      _Translations$xray$cards$branchModel$pt_BR._(_root);
  @override
  late final _Translations$xray$cards$bursty$pt_BR bursty =
      _Translations$xray$cards$bursty$pt_BR._(_root);
  @override
  late final _Translations$xray$cards$hiddenRefs$pt_BR hiddenRefs =
      _Translations$xray$cards$hiddenRefs$pt_BR._(_root);
  @override
  late final _Translations$xray$cards$keystone$pt_BR keystone =
      _Translations$xray$cards$keystone$pt_BR._(_root);
  @override
  late final _Translations$xray$cards$machineHistory$pt_BR machineHistory =
      _Translations$xray$cards$machineHistory$pt_BR._(_root);
  @override
  late final _Translations$xray$cards$migration$pt_BR migration =
      _Translations$xray$cards$migration$pt_BR._(_root);
  @override
  late final _Translations$xray$cards$narrowHotspot$pt_BR narrowHotspot =
      _Translations$xray$cards$narrowHotspot$pt_BR._(_root);
  @override
  late final _Translations$xray$cards$noTags$pt_BR noTags =
      _Translations$xray$cards$noTags$pt_BR._(_root);
  @override
  late final _Translations$xray$cards$reflog$pt_BR reflog =
      _Translations$xray$cards$reflog$pt_BR._(_root);
  @override
  late final _Translations$xray$cards$singleOwner$pt_BR singleOwner =
      _Translations$xray$cards$singleOwner$pt_BR._(_root);
}

// Path: xray.cardTitle
class _Translations$xray$cardTitle$pt_BR
    extends Translations$xray$cardTitle$en {
  _Translations$xray$cardTitle$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get branches => 'branches';
  @override
  String get bursty => 'em rajadas';
  @override
  String get hiddenRefs => 'refs ocultas';
  @override
  String get machineHeavy => 'carregado de máquina';
  @override
  String get migration => 'migração';
  @override
  String get narrowHotspot => 'hotspot estreito';
  @override
  String get noTags => 'sem tags';
  @override
  String get reflog => 'reflog';
  @override
  String get singleOwner => 'dono único';
}

// Path: xray.grain
class _Translations$xray$grain$pt_BR extends Translations$xray$grain$en {
  _Translations$xray$grain$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get coarsest => 'mais grosso — módulos de nível superior';
  @override
  String get finest => 'grão mais fino';
  @override
  String get mid => 'grão médio';
  @override
  String get oneCharacteristic => 'uma escala característica';
}

// Path: xray.header
class _Translations$xray$header$pt_BR extends Translations$xray$header$en {
  _Translations$xray$header$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get dirtyBadge => 'sujo';
  @override
  String get machineChip => 'máquina';
  @override
  String get refresh => 'Atualizar';
  @override
  String get refreshing => 'Atualizando...';
  @override
  String get title => 'X-Ray do Repo';
}

// Path: xray.hotspot
class _Translations$xray$hotspot$pt_BR extends Translations$xray$hotspot$en {
  _Translations$xray$hotspot$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get clusterPeers => 'pares do cluster';
  @override
  String get coChangers => 'co-mudadores';
  @override
  String get keystone => 'pedra-chave';
  @override
  String keystoneScore({required Object score}) => 'pedra-chave  φ=${score}';
}

// Path: xray.inspector
class _Translations$xray$inspector$pt_BR
    extends Translations$xray$inspector$en {
  _Translations$xray$inspector$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get branchLabel => 'branch';
  @override
  String commitsHumanMachine({required Object n}) => 'humano · ${n} de máquina';
  @override
  String get commitsLabel => 'commits';
  @override
  String get confidenceLabel => 'confiança';
  @override
  String get curlLabel => 'curl';
  @override
  String get engineSection => 'motor';
  @override
  String get gradientLabel => 'gradiente';
  @override
  String get harmonicLabel => 'harmônico';
  @override
  String get headLabel => 'head';
  @override
  String get hiddenRefsLabel => 'refs ocultas';
  @override
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} merge',
        other: '${n} merges',
      );
  @override
  String get noTags => 'sem tags';
  @override
  String get notesLabel => 'notas';
  @override
  String get openCommit => 'Abrir commit';
  @override
  String get pathLabel => 'caminho';
  @override
  String remoteCount({required Object n}) => '${n} remoto';
  @override
  String get renamesLabel => 'renomeações';
  @override
  String scannedAt({required Object time}) => 'escaneado ${time}';
  @override
  String selectedCount({required Object n}) => '${n} selecionados';
  @override
  String get shapeLinear => 'linear';
  @override
  String get shapeMergeHeavy => 'carregado de merges';
  @override
  String get shapeMostlyLinear => 'quase linear';
  @override
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} stash',
        other: '${n} stashes',
      );
  @override
  String get stressLabel => 'estresse';
  @override
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} tag',
        other: '${n} tags',
      );
  @override
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} worktree',
        other: '${n} worktrees',
      );
}

// Path: xray.loadingCard
class _Translations$xray$loadingCard$pt_BR
    extends Translations$xray$loadingCard$en {
  _Translations$xray$loadingCard$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get buildingMessage =>
      'Sondando histórico do Git, refs, cadência e hotspots.';
  @override
  String get buildingTitle => 'Montando o X-Ray do Repo';
  @override
  String get idleMessage =>
      'Abra o painel de novo para sondar o repositório atual.';
  @override
  String get idleTitle => 'X-Ray do Repo';
  @override
  String get unavailableTitle => 'X-Ray do Repo indisponível';
}

// Path: xray.metabolism
class _Translations$xray$metabolism$pt_BR
    extends Translations$xray$metabolism$en {
  _Translations$xray$metabolism$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String halfLife({required Object n}) => 'meia-vida de ${n}d';
}

// Path: xray.multi
class _Translations$xray$multi$pt_BR extends Translations$xray$multi$en {
  _Translations$xray$multi$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} cluster',
        other: '${n} clusters',
      );
  @override
  String clusterSingle({required Object id}) => 'cluster ${id}';
  @override
  String couplingSuffix({required Object parts}) => 'acoplamento ${parts}';
  @override
  String externalCount({required Object n}) => '${n} externo';
  @override
  String mutualCount({required Object n}) => '${n} mútuo';
}

// Path: xray.recency
class _Translations$xray$recency$pt_BR extends Translations$xray$recency$en {
  _Translations$xray$recency$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String days({required Object n}) => '${n}d';
  @override
  String months({required Object n}) => '${n}mês';
  @override
  String get today => 'hoje';
  @override
  String weeks({required Object n}) => '${n}sem';
  @override
  String years({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n}a',
        other: '${n}a',
      );
}

// Path: xray.rings
class _Translations$xray$rings$pt_BR extends Translations$xray$rings$en {
  _Translations$xray$rings$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get hintOneBlended => 'uma estrutura mesclada';
  @override
  String get hintSelfSimilar => 'autossimilar';
  @override
  String get oneBlendedBody =>
      'Uma estrutura mesclada — nenhuma escala de módulo separável se resolve ainda.';
  @override
  String get overHistory => 'Ao longo do histórico';
  @override
  String get parts => 'partes';
  @override
  String get readingHint => 'lendo estrutura…';
  @override
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} escala',
        other: '${n} escalas',
      );
  @override
  String get scaleDissolved => 'uma escala estrutural se dissolveu';
  @override
  String get scaleEmerged => 'uma escala estrutural emergiu';
  @override
  String get scaleSpectrum => 'espectro de escalas';
  @override
  String get selfSimilarBody =>
      'Autossimilar — a estrutura se repete pelas escalas, sem um único nível característico.';
  @override
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} mudança no histórico',
        other: '${n} mudanças no histórico',
      );
  @override
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} mudança estrutural',
        other: '${n} mudanças estruturais',
      );
  @override
  String get title => 'Anéis de crescimento';
  @override
  String get unavailable => 'indisponível';
}

// Path: xray.stats
class _Translations$xray$stats$pt_BR extends Translations$xray$stats$en {
  _Translations$xray$stats$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get alive => 'vivo';
  @override
  String get files => 'arquivos';
  @override
  String get lastTouched => 'tocado por último';
  @override
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'dono',
        other: 'donos',
      );
  @override
  String get touches => 'toques';
}

// Path: xray.stratumLabel
class _Translations$xray$stratumLabel$pt_BR
    extends Translations$xray$stratumLabel$en {
  _Translations$xray$stratumLabel$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'atual';
  @override
  String get legacy => 'legado';
  @override
  String get zone => 'zona do repo';
}

// Path: xray.summary
class _Translations$xray$summary$pt_BR extends Translations$xray$summary$en {
  _Translations$xray$summary$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String analysisFailed({required Object error}) => 'Análise falhou: ${error}';
  @override
  String get analyze => 'Analisar';
  @override
  String get copied => 'Resumo copiado para a área de transferência.';
  @override
  String get directionHint => 'direção';
  @override
  String get download => 'Baixar';
  @override
  String get emptyState =>
      'Rode a análise do Logos para mapear a estrutura e as regiões deste repositório.\n(tw: slop rn)';
  @override
  String get exit => 'Sair';
  @override
  String get generating => 'Lendo o repo e agrupando features…';
  @override
  String get noModel => 'Nenhum modelo de AI configurado.';
  @override
  String get noModelConfigured => 'nenhum modelo de AI configurado';
  @override
  String presentWith({required Object label}) => 'apresentar com ${label}';
  @override
  String presentingWith({required Object label}) =>
      'apresentando com ${label}…';
  @override
  String get reanalyze => 'Reanalisar';
  @override
  String get saveDialogTitle => 'Salvar resumo do repositório';
  @override
  String saveFailed({required Object error}) => 'Falha ao salvar: ${error}';
  @override
  String get savePresentationDialogTitle => 'Salvar apresentação';
  @override
  String savedTo({required Object path}) => 'Salvo em ${path}';
}

// Path: xray.tabs
class _Translations$xray$tabs$pt_BR extends Translations$xray$tabs$en {
  _Translations$xray$tabs$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get map => 'Mapa';
  @override
  String get signals => 'Sinais';
  @override
  String get summary => 'Resumo';
  @override
  String get time => 'Tempo';
}

// Path: xray.trajectory
class _Translations$xray$trajectory$pt_BR
    extends Translations$xray$trajectory$en {
  _Translations$xray$trajectory$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get connectivity => 'conectividade';
  @override
  String events({required Object n}) => '${n} eventos';
  @override
  String get openInOrrery => 'Abrir no Orrery';
  @override
  String get readingHint => 'lendo histórico…';
  @override
  String snapshots({required Object n}) => '${n} snapshots';
  @override
  String get steady => 'Estável — nenhum evento estrutural nesta janela.';
  @override
  String get title => 'Trajetória estrutural';
}

// Path: xray.verdict
class _Translations$xray$verdict$pt_BR extends Translations$xray$verdict$en {
  _Translations$xray$verdict$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String canonical({required Object pct}) => '${pct}% canônico';
  @override
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · ${canonical}% canônico · ${decisive}% decisivo';
}

// Path: changes.mergeEditor.trust
class _Translations$changes$mergeEditor$trust$pt_BR
    extends Translations$changes$mergeEditor$trust$en {
  _Translations$changes$mergeEditor$trust$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get manual => 'manual';
  @override
  String get safe => 'seguro';
  @override
  String get guided => 'guiado';
  @override
  String get assisted => 'assistido';
  @override
  String get full => 'total';
  @override
  String label({required Object label}) => 'confiança: ${label}';
}

// Path: changes.mergeEditor.keyHints
class _Translations$changes$mergeEditor$keyHints$pt_BR
    extends Translations$changes$mergeEditor$keyHints$en {
  _Translations$changes$mergeEditor$keyHints$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get accept => 'aceitar';
  @override
  String get other => 'outro';
  @override
  String get both => 'ambos';
  @override
  String get navigate => 'navegar';
  @override
  String get jumpNext => 'pular ao próximo';
}

// Path: changes.mergeFlow.op
class _Translations$changes$mergeFlow$op$pt_BR
    extends Translations$changes$mergeFlow$op$en {
  _Translations$changes$mergeFlow$op$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

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
  String get switchOp => 'trocar';
  @override
  String get pull => 'pull';
  @override
  String get rebase => 'rebase';
  @override
  String rebaseOnto({required Object branch, required Object base}) =>
      'rebase de ${branch} sobre ${base}';
}

// Path: diff.pinned.tempo
class _Translations$diff$pinned$tempo$pt_BR
    extends Translations$diff$pinned$tempo$en {
  _Translations$diff$pinned$tempo$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get hotOwnerLane => 'Movimento recente com um dono forte por perto.';
  @override
  String get activeSeam => 'Movimento recente de várias mãos por perto.';
  @override
  String get stableOwnerLane => 'Faixa de vida longa com um dono dominante.';
  @override
  String get sharedLongLivedSeam =>
      'Costura compartilhada que se acumulou ao longo do tempo.';
  @override
  String get sharedLane => 'Faixa compartilhada sem um único dono dominante.';
  @override
  String get resolving =>
      'O histórico ainda está se resolvendo em torno desta linha.';
}

// Path: diff.pinned.tone
class _Translations$diff$pinned$tone$pt_BR
    extends Translations$diff$pinned$tone$en {
  _Translations$diff$pinned$tone$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get hot => 'Quente';
  @override
  String get novel => 'Novo';
  @override
  String get contested => 'Disputado';
  @override
  String get spreading => 'Espalhando';
  @override
  String get stable => 'Estável';
}

// Path: diff.pinned.summary
class _Translations$diff$pinned$summary$pt_BR
    extends Translations$diff$pinned$summary$en {
  _Translations$diff$pinned$summary$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String livesIn({required Object concept}) => 'Mora em ${concept}';
  @override
  String get sitsInLocalSeam => 'Fica numa costura local';
  @override
  String workedMostlyBy({required Object owner}) =>
      'trabalhado principalmente por ${owner} por perto';
  @override
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'ecoa em ${n} outro ponto',
        other: 'ecoa em ${n} outros pontos',
      );
  @override
  String inspectNext({required Object path, required Object detail}) =>
      'inspecionar ${path} a seguir${detail}';
  @override
  String inspectDetail({required Object reason}) => ' (${reason})';
}

// Path: diff.pinned.tightness
class _Translations$diff$pinned$tightness$pt_BR
    extends Translations$diff$pinned$tightness$en {
  _Translations$diff$pinned$tightness$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get tight => 'encaixe apertado';
  @override
  String get close => 'encaixe próximo';
  @override
  String get loose => 'encaixe frouxo';
}

// Path: diff.pinned.witness
class _Translations$diff$pinned$witness$pt_BR
    extends Translations$diff$pinned$witness$en {
  _Translations$diff$pinned$witness$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String nearbySupport({required Object label}) => 'Apoio por perto · ${label}';
  @override
  String localizedMove({required Object label}) =>
      'Movimento localizado · ${label}';
  @override
  String surprisingMove({required Object label}) =>
      'Movimento surpreendente · ${label}';
}

// Path: diff.pinned.integrity
class _Translations$diff$pinned$integrity$pt_BR
    extends Translations$diff$pinned$integrity$en {
  _Translations$diff$pinned$integrity$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get stableStructure => 'Estrutura estável';
  @override
  String get conflictingSignals => 'Sinais conflitantes';
  @override
  String get novelShape => 'Forma inédita';
}

// Path: diff.pinned.related
class _Translations$diff$pinned$related$pt_BR
    extends Translations$diff$pinned$related$en {
  _Translations$diff$pinned$related$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get testMirror => 'Espelho de teste';
  @override
  String get semanticHistorySibling => 'Irmão semântico + de histórico';
  @override
  String get recentCoChange => 'Co-mudança recente';
  @override
  String get semanticSibling => 'Irmão semântico';
  @override
  String get relatedStructure => 'Estrutura relacionada';
  @override
  String get tightlyBound => 'fortemente ligado';
  @override
  String get orbiting => 'orbitando';
  @override
  String get weaklyCoupled => 'fracamente acoplado';
  @override
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class _Translations$diff$pinned$axis$pt_BR
    extends Translations$diff$pinned$axis$en {
  _Translations$diff$pinned$axis$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get historyTrail => 'trilha de histórico';
  @override
  String get testMirrorLane => 'faixa de espelho de teste';
  @override
  String get structuralLane => 'faixa estrutural';
  @override
  String get semanticNeighbourhood => 'vizinhança semântica';
}

// Path: history.commitLede.semantics
class _Translations$history$commitLede$semantics$pt_BR
    extends Translations$history$commitLede$semantics$en {
  _Translations$history$commitLede$semantics$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get importanceHigh => 'importância alta';
  @override
  String get importanceModerate => 'importância moderada';
  @override
  String get mostlyAdditions => 'quase só adições';
  @override
  String get mostlyDeletions => 'quase só remoções';
  @override
  String get tightlyCoupled => 'arquivos fortemente acoplados';
  @override
  String get overlapsWorkingTree => 'sobrepõe sua árvore de trabalho';
}

// Path: onboarding.repo.doors
class _Translations$onboarding$repo$doors$pt_BR
    extends Translations$onboarding$repo$doors$en {
  _Translations$onboarding$repo$doors$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$repo$doors$open$pt_BR open =
      _Translations$onboarding$repo$doors$open$pt_BR._(_root);
  @override
  late final _Translations$onboarding$repo$doors$clone$pt_BR clone =
      _Translations$onboarding$repo$doors$clone$pt_BR._(_root);
  @override
  late final _Translations$onboarding$repo$doors$create$pt_BR create =
      _Translations$onboarding$repo$doors$create$pt_BR._(_root);
}

// Path: onboarding.repo.cloneForm
class _Translations$onboarding$repo$cloneForm$pt_BR
    extends Translations$onboarding$repo$cloneForm$en {
  _Translations$onboarding$repo$cloneForm$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Clonar de uma URL';
  @override
  String get urlLabel => 'URL do repositório';
  @override
  String get targetLabel => 'Pasta de destino';
  @override
  String get browse => 'Procurar…';
  @override
  String get clone => 'Clonar';
  @override
  String get cloning => 'Clonando…';
}

// Path: onboarding.repo.pickers
class _Translations$onboarding$repo$pickers$pt_BR
    extends Translations$onboarding$repo$pickers$en {
  _Translations$onboarding$repo$pickers$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get openRepository => 'Abrir Repositório';
  @override
  String get createRepository => 'Criar Repositório';
  @override
  String get cloneTarget => 'Destino do Clone';
}

// Path: onboarding.repo.errors
class _Translations$onboarding$repo$errors$pt_BR
    extends Translations$onboarding$repo$errors$en {
  _Translations$onboarding$repo$errors$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get urlAndTargetRequired => 'URL e caminho de destino obrigatórios.';
  @override
  String get createFailed => 'Falha ao criar o repositório.';
  @override
  String get cloneFailed => 'Falha ao clonar o repositório.';
}

// Path: onboarding.preview.panels
class _Translations$onboarding$preview$panels$pt_BR
    extends Translations$onboarding$preview$panels$en {
  _Translations$onboarding$preview$panels$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get xray => 'raio-x do repo';
  @override
  String get settings => 'configurações';
}

// Path: onboarding.preview.sidebar
class _Translations$onboarding$preview$sidebar$pt_BR
    extends Translations$onboarding$preview$sidebar$en {
  _Translations$onboarding$preview$sidebar$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get projectsHeader => 'Projetos';
}

// Path: onboarding.preview.changes
class _Translations$onboarding$preview$changes$pt_BR
    extends Translations$onboarding$preview$changes$en {
  _Translations$onboarding$preview$changes$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String filesStagedCount({required Object staged, required Object total}) =>
      '${staged} de ${total} arquivos';
  @override
  String stagedCount({required Object n}) => '${n} em stage';
  @override
  String get commitMessageHint => 'Mensagem do commit…';
  @override
  String get commitAndPush => 'Commit e push';
}

// Path: onboarding.preview.history
class _Translations$onboarding$preview$history$pt_BR
    extends Translations$onboarding$preview$history$en {
  _Translations$onboarding$preview$history$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'Histórico';
  @override
  String get viewingLast => 'vendo os últimos 20 commits';
  @override
  String get inFlight => 'EM VOO';
  @override
  String get you => 'você';
  @override
  String get commit1 => 'ensinar a raposa a farejar antes de engolir';
  @override
  String get commit2 => 'âmbar: segurar o cheiro durante a noite';
  @override
  String get commit3 => 'aposentar o repolho em favor de âmbar + espinho';
  @override
  String get commit4 => 'o espinho guarda o portão';
}

// Path: onboarding.preview.branches
class _Translations$onboarding$preview$branches$pt_BR
    extends Translations$onboarding$preview$branches$en {
  _Translations$onboarding$preview$branches$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get lensBranches => 'BRANCHES';
  @override
  String get lensPRs => 'PRs';
  @override
  String get absorbed => 'absorvido';
  @override
  String get desk => 'Desk';
  @override
  String get head => 'HEAD';
  @override
  String tracking({required Object ref}) => '→ rastreando: ${ref}';
}

// Path: onboarding.preview.diff
class _Translations$onboarding$preview$diff$pt_BR
    extends Translations$onboarding$preview$diff$en {
  _Translations$onboarding$preview$diff$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get readmeTagline => 'Seu cliente Git pessoal.';
}

// Path: releaseNotes.about.whyFlutter
class _Translations$releaseNotes$about$whyFlutter$pt_BR
    extends Translations$releaseNotes$about$whyFlutter$en {
  _Translations$releaseNotes$about$whyFlutter$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'POR QUE FLUTTER?';
  @override
  String get body =>
      'A primeira versão disto era um app em Tauri (Rust + TypeScript). Eu já sentia que era lento. Aí peguei um streamer dizendo a mesma coisa numa live que eu nem costumo assistir, e foi o empurrão que faltava pra finalmente trocar. Ele não sugeriu Flutter; muito pelo contrário. Achei o Dart por conta própria, montei um protótipo às pressas, e o tempo de inicialização caiu de uns 15 segundos pra menos de um. Do dia pra noite. Adeus era Tauri.\n\nO pipeline de renderização do Flutter é mais parecido com uma game engine do que com um DOM, e pra um app de desktop em que a UI é o produto, isso é tudo. O Dart também se mostrou uma linguagem genuinamente boa. A matemática por trás do motor espectral foi prototipada primeiro em Rust, então esse trabalho veio junto sem problema.\n\nO Flutter é multiplataforma por padrão, o que é ótimo, mas tem uma cara meio Google, então rolam algumas manias.';
}

// Path: releaseNotes.about.spectralEngine
class _Translations$releaseNotes$about$spectralEngine$pt_BR
    extends Translations$releaseNotes$about$spectralEngine$en {
  _Translations$releaseNotes$about$spectralEngine$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'O QUE É O MOTOR ESPECTRAL?';
  @override
  String get body =>
      'Toda vez que você faz um commit, os arquivos que muda juntos formam padrões ao longo do tempo. O motor espectral lê o seu grafo de commits e decompõe esses padrões de co-mudança em sinais: quais arquivos estão acoplados, quão fortemente, e que papel estrutural cumprem no repositório. Basicamente análise espectral sobre o seu histórico de desenvolvimento. Num cliente git. De propósito.\n\nA matemática é nova, então trato ela como game feel: ajusto, testo, calibro e sigo até os sinais parecerem certos.\n\nEsses sinais alimentam tudo. O sismógrafo no histórico, as barras pintadas sob os títulos dos commits, o sistema de review, a Muse, a constelação de arquivos. O app inteiro raciocina a partir dessa camada pra cima, não o contrário.';
}

// Path: releaseNotes.about.whereGoing
class _Translations$releaseNotes$about$whereGoing$pt_BR
    extends Translations$releaseNotes$about$whereGoing$en {
  _Translations$releaseNotes$about$whereGoing$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'PARA ONDE ISSO VAI?';
  @override
  String get body =>
      'O primeiro marco é paridade total com GitHub Desktop, SourceTree e GitKraken. Um cliente git multiplataforma que parece rápido e lida com o básico melhor do que qualquer outro. Isso já está quase todo aqui. O motor espectral já nos dá vantagem em operações que outros clientes te obrigam a pensar na mão.\n\nDaí pra frente, a meta é superar todos os outros clientes git em velocidade, acessibilidade, inteligência e UX no geral. Tem mais coisa no forno do que o que está anunciado aqui.';
}

// Path: settings.commitPreview.title
class _Translations$settings$commitPreview$title$pt_BR
    extends Translations$settings$commitPreview$title$en {
  _Translations$settings$commitPreview$title$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$verbLed$pt_BR verbLed =
      _Translations$settings$commitPreview$title$verbLed$pt_BR._(_root);
  @override
  late final _Translations$settings$commitPreview$title$descriptive$pt_BR
  descriptive = _Translations$settings$commitPreview$title$descriptive$pt_BR._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$title$narrative$pt_BR
  narrative = _Translations$settings$commitPreview$title$narrative$pt_BR._(
    _root,
  );
}

// Path: settings.commitPreview.base
class _Translations$settings$commitPreview$base$pt_BR
    extends Translations$settings$commitPreview$base$en {
  _Translations$settings$commitPreview$base$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$base$verbLed$pt_BR verbLed =
      _Translations$settings$commitPreview$base$verbLed$pt_BR._(_root);
  @override
  late final _Translations$settings$commitPreview$base$descriptive$pt_BR
  descriptive = _Translations$settings$commitPreview$base$descriptive$pt_BR._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$base$narrative$pt_BR
  narrative = _Translations$settings$commitPreview$base$narrative$pt_BR._(
    _root,
  );
}

// Path: settings.commitPreview.balancedSuffix
class _Translations$settings$commitPreview$balancedSuffix$pt_BR
    extends Translations$settings$commitPreview$balancedSuffix$en {
  _Translations$settings$commitPreview$balancedSuffix$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$verbLed$pt_BR
  verbLed = _Translations$settings$commitPreview$balancedSuffix$verbLed$pt_BR._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$descriptive$pt_BR
  descriptive =
      _Translations$settings$commitPreview$balancedSuffix$descriptive$pt_BR._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$narrative$pt_BR
  narrative =
      _Translations$settings$commitPreview$balancedSuffix$narrative$pt_BR._(
        _root,
      );
}

// Path: settings.commitPreview.everythingSuffix
class _Translations$settings$commitPreview$everythingSuffix$pt_BR
    extends Translations$settings$commitPreview$everythingSuffix$en {
  _Translations$settings$commitPreview$everythingSuffix$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$verbLed$pt_BR
  verbLed =
      _Translations$settings$commitPreview$everythingSuffix$verbLed$pt_BR._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$descriptive$pt_BR
  descriptive =
      _Translations$settings$commitPreview$everythingSuffix$descriptive$pt_BR._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$narrative$pt_BR
  narrative =
      _Translations$settings$commitPreview$everythingSuffix$narrative$pt_BR._(
        _root,
      );
}

// Path: xray.cards.branchModel
class _Translations$xray$cards$branchModel$pt_BR
    extends Translations$xray$cards$branchModel$en {
  _Translations$xray$cards$branchModel$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get broadClaim =>
      'O repositório tem superfície de branches suficiente para recompensar a navegação orientada a branches.';
  @override
  String get broadTitle => 'O modelo de branches tem área de superfície';
  @override
  String localBranchesDetail({required Object count}) =>
      '${count} branches locais.';
  @override
  String get localBranchesLabel => 'Branches locais';
  @override
  String remoteBranchesDetail({required Object count}) =>
      '${count} branches remotos.';
  @override
  String get remoteBranchesLabel => 'Branches remotos';
  @override
  String get simpleClaim => 'O modelo de branches visível é estreito.';
  @override
  String get simpleTitle => 'Modelo de branches simples';
}

// Path: xray.cards.bursty
class _Translations$xray$cards$bursty$pt_BR
    extends Translations$xray$cards$bursty$en {
  _Translations$xray$cards$bursty$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'O trabalho chega em rajadas concentradas, e não num ritmo diário constante.';
  @override
  String get title => 'Cadência de desenvolvimento em rajadas';
}

// Path: xray.cards.hiddenRefs
class _Translations$xray$cards$hiddenRefs$pt_BR
    extends Translations$xray$cards$hiddenRefs$en {
  _Translations$xray$cards$hiddenRefs$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object count}) =>
      '${count} refs vivem fora do espaço normal de branch/tag.';
  @override
  String evidenceDetail({required Object count}) =>
      '${count} refs fora de heads/remotes/tags.';
  @override
  String get evidenceLabel => 'Refs ocultas';
  @override
  String get namespacesLabel => 'Namespaces';
  @override
  String get title => 'Namespaces ocultos do Git';
}

// Path: xray.cards.keystone
class _Translations$xray$cards$keystone$pt_BR
    extends Translations$xray$cards$keystone$en {
  _Translations$xray$cards$keystone$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String claim({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
    n,
    one:
        'Um arquivo carrega um peso de co-mudança desproporcional em relação à sua contagem de toques.',
    other:
        'Um pequeno conjunto de arquivos carrega um peso de co-mudança desproporcional em relação às suas contagens de toques.',
  );
  @override
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: '${n} toque · pull φ=${score}',
        other: '${n} toques · pull φ=${score}',
      );
  @override
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(
        n,
        one: 'Arquivo-ponte pedra-chave',
        other: '${n} arquivos-ponte pedra-chave',
      );
}

// Path: xray.cards.machineHistory
class _Translations$xray$cards$machineHistory$pt_BR
    extends Translations$xray$cards$machineHistory$en {
  _Translations$xray$cards$machineHistory$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Commits em estilo checkpoint distorcem materialmente métricas ingênuas de histórico.';
  @override
  String machineCommitsDetail({required Object count}) =>
      '${count} commits bateram com padrões de máquina/sessão.';
  @override
  String get machineCommitsLabel => 'Commits de máquina';
  @override
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '${raw} commits brutos vs ${filtered} commits filtrados.';
  @override
  String get rawVsFilteredLabel => 'Brutos vs filtrados';
  @override
  String get title => 'Histórico de máquina domina as métricas brutas';
}

// Path: xray.cards.migration
class _Translations$xray$cards$migration$pt_BR
    extends Translations$xray$cards$migration$en {
  _Translations$xray$cards$migration$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object older, required Object newer}) =>
      'O histórico migra de `${older}` para `${newer}`, sugerindo uma transição de stack ou de superfície.';
  @override
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches} toques, ativo por último ${lastActive}.';
  @override
  String get title => 'Migração de arquitetura visível';
}

// Path: xray.cards.narrowHotspot
class _Translations$xray$cards$narrowHotspot$pt_BR
    extends Translations$xray$cards$narrowHotspot$en {
  _Translations$xray$cards$narrowHotspot$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Um pequeno conjunto de arquivos e diretórios absorve uma fatia desproporcional das mudanças.';
  @override
  String get title => 'A concentração de hotspots é estreita';
  @override
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path} responde por ${pct}% do conjunto de hotspots visível.';
  @override
  String get topHotspotLabel => 'Maior hotspot';
  @override
  String visibleAuthorsDetail({required Object count}) =>
      '${count} autores nesta fatia do histórico.';
  @override
  String get visibleAuthorsLabel => 'Autores visíveis';
}

// Path: xray.cards.noTags
class _Translations$xray$cards$noTags$pt_BR
    extends Translations$xray$cards$noTags$en {
  _Translations$xray$cards$noTags$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'As tags do Git não estão sendo usadas como uma camada visível de release ou marco.';
  @override
  String remoteEndpointsDetail({required Object count}) =>
      '${count} endpoints remotos configurados.';
  @override
  String get remoteEndpointsLabel => 'Endpoints remotos';
  @override
  String get tagCountDetail => '0 tags encontradas.';
  @override
  String get tagCountLabel => 'Contagem de tags';
  @override
  String get title => 'Sem trilha formal de release/tag';
}

// Path: xray.cards.reflog
class _Translations$xray$cards$reflog$pt_BR
    extends Translations$xray$cards$reflog$en {
  _Translations$xray$cards$reflog$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'O volume de reflog sugere iteração local concentrada além dos commits publicados.';
  @override
  String get peakReflogDayLabel => 'Dia de pico de reflog';
  @override
  String get title => 'Sessões intensas de edição local';
}

// Path: xray.cards.singleOwner
class _Translations$xray$cards$singleOwner$pt_BR
    extends Translations$xray$cards$singleOwner$en {
  _Translations$xray$cards$singleOwner$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object path, required Object kind}) =>
      '`${path}` é um ${kind} muito tocado com um único autor visível distinto.';
  @override
  String ownerCountDetail({required Object count}) =>
      '${count} autores distintos.';
  @override
  String get ownerCountLabel => 'Contagem de donos';
  @override
  String get title => 'Hotspot de dono único';
  @override
  String get touchCountLabel => 'Contagem de toques';
  @override
  String touchDetailFiltered({required Object count}) =>
      '${count} toques no histórico filtrado.';
  @override
  String touchDetailRaw({required Object count}) =>
      '${count} toques no histórico bruto.';
}

// Path: onboarding.repo.doors.open
class _Translations$onboarding$repo$doors$open$pt_BR
    extends Translations$onboarding$repo$doors$open$en {
  _Translations$onboarding$repo$doors$open$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Abrir';
  @override
  String get subtitle => 'existente';
  @override
  String get hint => 'um que você já tem';
}

// Path: onboarding.repo.doors.clone
class _Translations$onboarding$repo$doors$clone$pt_BR
    extends Translations$onboarding$repo$doors$clone$en {
  _Translations$onboarding$repo$doors$clone$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Clonar';
  @override
  String get subtitle => 'de uma URL';
  @override
  String get hint => 'cole uma URL remota';
}

// Path: onboarding.repo.doors.create
class _Translations$onboarding$repo$doors$create$pt_BR
    extends Translations$onboarding$repo$doors$create$en {
  _Translations$onboarding$repo$doors$create$pt_BR._(TranslationsPtBr root)
    : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Criar';
  @override
  String get subtitle => 'novo';
  @override
  String get hint => 'comece algo do zero';
}

// Path: settings.commitPreview.title.verbLed
class _Translations$settings$commitPreview$title$verbLed$pt_BR
    extends Translations$settings$commitPreview$title$verbLed$en {
  _Translations$settings$commitPreview$title$verbLed$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Deixar a raposa pular biscoitos com cheiro estranho';
  @override
  String get s2 =>
      'Treinar a raposa a recusar biscoitos adulterados antes de engolir';
  @override
  String get s3 =>
      'Obrigar a raposa a vistoriar forensicamente cada biscoito no portão';
  @override
  String get def => 'Ensinar a raposa a recusar biscoitos ruins';
}

// Path: settings.commitPreview.title.descriptive
class _Translations$settings$commitPreview$title$descriptive$pt_BR
    extends Translations$settings$commitPreview$title$descriptive$en {
  _Translations$settings$commitPreview$title$descriptive$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'a raposa agora escolhe os biscoitos';
  @override
  String get s2 => 'Rotina de inspeção de biscoitos, treinada na raposa';
  @override
  String get s3 =>
      'Perícia de vistoria de biscoitos, gravada na raposa pela repetição';
  @override
  String get def => 'Protocolo de fareja-biscoito, instalado na raposa';
}

// Path: settings.commitPreview.title.narrative
class _Translations$settings$commitPreview$title$narrative$pt_BR
    extends Translations$settings$commitPreview$title$narrative$en {
  _Translations$settings$commitPreview$title$narrative$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'a raposa começou a pular os biscoitos que cheiravam errado';
  @override
  String get s2 => 'Sentei com a raposa e fomos vendo quais biscoitos recusar';
  @override
  String get s3 =>
      'Passei boa parte de uma tarde convencendo a raposa de que nem todo biscoito oferecido é, de boa-fé, um biscoito';
  @override
  String get def => 'Pedi pra raposa farejar os biscoitos antes de comê-los';
}

// Path: settings.commitPreview.base.verbLed
class _Translations$settings$commitPreview$base$verbLed$pt_BR
    extends Translations$settings$commitPreview$base$verbLed$en {
  _Translations$settings$commitPreview$base$verbLed$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      'A raposa dá uma olhada. O que estiver estranho fica pra trás.';
  @override
  String get s2 =>
      'A raposa inspeciona cada token, recusa qualquer um com cheiro esquisito e anota a recusa na varanda.';
  @override
  String get s3 =>
      'A raposa rodeia cada token, prova o ar em três ângulos, recusa qualquer um que soe errado e espera um instante pra garantir que a recusa pegou.';
  @override
  String get def =>
      'A raposa agora fareja cada token e recusa educadamente os suspeitos.';
}

// Path: settings.commitPreview.base.descriptive
class _Translations$settings$commitPreview$base$descriptive$pt_BR
    extends Translations$settings$commitPreview$base$descriptive$en {
  _Translations$settings$commitPreview$base$descriptive$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Um passe leve nos esquisitos, na maioria.';
  @override
  String get s2 =>
      'Uma recusa documentada em cada token de cheiro estranho, emitida da varanda e anotada.';
  @override
  String get s3 =>
      'Uma recusa lavrada em cartório por token de cheiro estranho, emitida da varanda com uma pata erguida, a outra imóvel.';
  @override
  String get def =>
      'Uma recusa educada nos tokens suspeitos, emitida da varanda.';
}

// Path: settings.commitPreview.base.narrative
class _Translations$settings$commitPreview$base$narrative$pt_BR
    extends Translations$settings$commitPreview$base$narrative$en {
  _Translations$settings$commitPreview$base$narrative$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      'A raposa meio que só parou de comer os esquisitos. Tranquilo.';
  @override
  String get s2 =>
      'Todo token descia sem muito pensar; agora tem uma pausa, um olhar de verdade, e uma recusa pros que não assentam bem.';
  @override
  String get s3 =>
      'Todo token descia sem pensar. Agora: uma pausa. O ar, inspirado. O ar, retido. A raposa observa as tábuas da varanda em busca do pequeno tremor que às vezes têm quando algo está errado, e só então a decisão é tomada.';
  @override
  String get def =>
      'Todo token era engolido sem cerimônia; agora tem uma fungada antes.';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class _Translations$settings$commitPreview$balancedSuffix$verbLed$pt_BR
    extends Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  _Translations$settings$commitPreview$balancedSuffix$verbLed$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' A varanda tá de boa. O quintal é o que for.';
  @override
  String get s2 =>
      ' Varanda varrida após cada recusa; lama no quintal permitida dentro do horário afixado.';
  @override
  String get s3 =>
      ' Varanda varrida e re-varrida; lama do quintal catalogada por pegada e clima, e a raposa demora mais na soleira do que antes.';
  @override
  String get def =>
      ' A varanda fica limpa; o quintal mantém seus direitos de lama.';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class _Translations$settings$commitPreview$balancedSuffix$descriptive$pt_BR
    extends Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  _Translations$settings$commitPreview$balancedSuffix$descriptive$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Varanda ok. O quintal faz coisas de quintal.';
  @override
  String get s2 =>
      ' Varanda como zona limpa de evidências; quintal como zona de lama designada, horários afixados.';
  @override
  String get s3 =>
      ' Varanda como sala limpa nível-evidência; quintal como arquivo de lama catalogado; soleira como o lugar onde a raposa fica parada pensando tempo demais.';
  @override
  String get def => ' Varanda limpa; direitos de lama preservados no quintal.';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class _Translations$settings$commitPreview$balancedSuffix$narrative$pt_BR
    extends Translations$settings$commitPreview$balancedSuffix$narrative$en {
  _Translations$settings$commitPreview$balancedSuffix$narrative$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' A varanda tava de boa. O quintal, sei lá.';
  @override
  String get s2 =>
      ' A varanda foi mantida limpa depois; a raposa recuou pro quintal, que é onde o pensamento acontece.';
  @override
  String get s3 =>
      ' A varanda foi esfregada duas vezes naquela noite. A raposa andou pelo quintal devagar, parou no mesmo mourão de sempre, e olhou de volta pra varanda como se a varanda devesse alguma coisa.';
  @override
  String get def =>
      ' A varanda fica limpa, embora o quintal ainda ganhe em dignidade.';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class _Translations$settings$commitPreview$everythingSuffix$verbLed$pt_BR
    extends Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  _Translations$settings$commitPreview$everythingSuffix$verbLed$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' O Âmbar tá lá. A Brisa vai à deriva. O Espinho pica se precisar. Quase sempre nada.';
  @override
  String get s2 =>
      ' O Âmbar segura cada cheiro pra revisão. A Brisa leva o ar do dia até o espinho do portão, que marca cada recusa pra contagem da noite.';
  @override
  String get s3 =>
      ' O Âmbar segura cada cheiro e dá um peso diferente conforme a hora. A Brisa se move pela varanda em ângulos que não deveriam importar mas importam. O espinho do portão pica uma vez pras recusas e duas pras que a raposa quase deixou passar, e a raposa sabe a diferença mesmo quando ninguém mais sabe.';
  @override
  String get def =>
      ' O Âmbar segura o cheiro. A Brisa o leva adiante. O espinho do portão pega o que não devia passar.';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class _Translations$settings$commitPreview$everythingSuffix$descriptive$pt_BR
    extends
        Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  _Translations$settings$commitPreview$everythingSuffix$descriptive$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Âmbar no poste. Brisa no ar. Espinho no portão. Beleza.';
  @override
  String get s2 =>
      ' Âmbar como testemunha-de-cheiro designada; brisa como ambiente registrado; marcas de espinho como o registro de recusas do dia, reconciliado ao anoitecer.';
  @override
  String get s3 =>
      ' Âmbar como testemunha-de-cheiro cujo silêncio já é uma leitura; brisa como ambiente padronizado que se move errado nos dias em que algo está errado; espinho como o guarda-contas do portão, cujas marcas a raposa confere antes de dormir e de novo antes do amanhecer.';
  @override
  String get def =>
      ' Âmbar como testemunha-de-cheiro; brisa como contexto ambiente; espinho como a marca-de-recusa silenciosa do portão.';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class _Translations$settings$commitPreview$everythingSuffix$narrative$pt_BR
    extends Translations$settings$commitPreview$everythingSuffix$narrative$en {
  _Translations$settings$commitPreview$everythingSuffix$narrative$pt_BR._(
    TranslationsPtBr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsPtBr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' O Âmbar tava por perto. A Brisa foi e voltou. O Espinho fez sua coisa quieta. Enfim, foi tranquilo.';
  @override
  String get s2 =>
      ' O Âmbar guardou o registro de cheiros do dia, a brisa foi anotada por direção e hora, e as marcas do espinho foram contadas e referendadas pela varanda.';
  @override
  String get s3 =>
      ' O Âmbar guardou o registro de cheiros, mas a raposa jura que ele pesa mais em certas manhãs. A Brisa se moveu pela varanda do jeito que sempre faz, ou seja, errado nos dias que importam. O espinho do portão marcou cada recusa; a raposa saiu à primeira luz pra contá-las, do jeito que se contam degraus que já se contou.';
  @override
  String get def =>
      ' O Âmbar guardou o registro de cheiros, a brisa moveu o ar, e o espinho do portão pegou o que precisava ser pego.';
}
