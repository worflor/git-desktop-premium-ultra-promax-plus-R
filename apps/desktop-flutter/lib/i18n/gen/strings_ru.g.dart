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
class TranslationsRu extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsRu({
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
             locale: AppLocale.ru,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <ru>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final TranslationsRu _root = this; // ignore: unused_field

  @override
  TranslationsRu $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsRu(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$app$ru app = _Translations$app$ru._(_root);
  @override
  late final _Translations$backend$ru backend = _Translations$backend$ru._(
    _root,
  );
  @override
  late final _Translations$branches$ru branches = _Translations$branches$ru._(
    _root,
  );
  @override
  late final _Translations$changes$ru changes = _Translations$changes$ru._(
    _root,
  );
  @override
  late final _Translations$common$ru common = _Translations$common$ru._(_root);
  @override
  late final _Translations$diff$ru diff = _Translations$diff$ru._(_root);
  @override
  late final _Translations$filament$ru filament = _Translations$filament$ru._(
    _root,
  );
  @override
  late final _Translations$history$ru history = _Translations$history$ru._(
    _root,
  );
  @override
  late final _Translations$historySurgery$ru historySurgery =
      _Translations$historySurgery$ru._(_root);
  @override
  late final _Translations$onboarding$ru onboarding =
      _Translations$onboarding$ru._(_root);
  @override
  late final _Translations$orrery$ru orrery = _Translations$orrery$ru._(_root);
  @override
  late final _Translations$palette$ru palette = _Translations$palette$ru._(
    _root,
  );
  @override
  late final _Translations$releaseNotes$ru releaseNotes =
      _Translations$releaseNotes$ru._(_root);
  @override
  late final _Translations$repoSummary$ru repoSummary =
      _Translations$repoSummary$ru._(_root);
  @override
  late final _Translations$review$ru review = _Translations$review$ru._(_root);
  @override
  late final _Translations$settings$ru settings = _Translations$settings$ru._(
    _root,
  );
  @override
  late final _Translations$sync$ru sync = _Translations$sync$ru._(_root);
  @override
  late final _Translations$xray$ru xray = _Translations$xray$ru._(_root);
}

// Path: app
class _Translations$app$ru extends Translations$app$en {
  _Translations$app$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get panelSettings => 'Настройки';
  @override
  String get panelReleaseNotes => 'Заметки к релизу';
  @override
  String get panelFilamentFindings => 'Находки Filament';
  @override
  String get filamentFindingsUpper => 'НАХОДКИ FILAMENT';
  @override
  late final _Translations$app$cheatsheet$ru cheatsheet =
      _Translations$app$cheatsheet$ru._(_root);
  @override
  String get commandPaletteTooltip => 'Палитра команд   /';
  @override
  String get newDeskFallback => 'новый Desk';
  @override
  String get deskFallback => 'Desk';
  @override
  String get currentDeskFallback => 'текущий';
  @override
  String get noRepositoryOpen => 'Репозиторий не открыт';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Не удалось открыть как Desk: ${error}';
  @override
  String couldNotDetectForge({required Object error}) =>
      'Не удалось определить форж: ${error}';
  @override
  String get cannotFetchPrNoForge =>
      'Не удалось получить PR: форж для этого репозитория не определён.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      'Перезаписать ${ref} последней версией из удалённого?';
  @override
  String get overwrite => 'Перезаписать';
  @override
  String couldntFetchPr({required Object error}) =>
      'Не удалось получить PR: ${error}';
  @override
  String get promoteDeskToPr => 'Продвинуть Desk в PR';
  @override
  String get applyToMain => 'Применить к main';
  @override
  String updateDeskFrom({required Object target, required Object source}) =>
      'Обновить ${target} из ${source}';
  @override
  String bringChangesFromHere({required Object source}) =>
      'Принести изменения из ${source} сюда';
  @override
  String get editLocalPr => 'Редактировать локальный PR';
  @override
  String get discardLocalPr => 'Отбросить локальный PR';
  @override
  String get closeDesk => 'Закрыть Desk';
  @override
  String couldntPromote({required Object error}) =>
      'Не удалось продвинуть: ${error}';
  @override
  String get commitOrShelveBeforeApplying =>
      'Закоммитьте или отложите изменения Desk перед применением.';
  @override
  String get couldNotResolveMainWorktree =>
      'Не удалось определить путь главного рабочего каталога.';
  @override
  String couldntPromoteDesk({required Object error}) =>
      'Не удалось продвинуть Desk: ${error}';
  @override
  String get couldntDetermineBaseBranch =>
      'Не удалось определить базовую ветку для этого Desk.';
  @override
  String prBaseHeadSame({required Object branch}) =>
      'База и вершина PR — одна и та же ветка (${branch}) — применять нечего.';
  @override
  String appliedBranchToBase({required Object branch, required Object base}) =>
      '${branch} применена к ${base}';
  @override
  String updatedDeskToDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
    n,
    one: '${target} обновлён до ${source} (${n} коммит).',
    few: '${target} обновлён до ${source} (${n} коммита).',
    many: '${target} обновлён до ${source} (${n} коммитов).',
    other: '${target} обновлён до ${source} (${n} коммитов).',
  );
  @override
  String get fastForwardFailedFallback =>
      'Fast-forward не удалось применить чисто — вместо этого показываю превью патча.';
  @override
  String deskAheadOfDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
    n,
    one: '${target} впереди ${source} на ${n} коммит.',
    few: '${target} впереди ${source} на ${n} коммита.',
    many: '${target} впереди ${source} на ${n} коммитов.',
    other: '${target} впереди ${source} на ${n} коммитов.',
  );
  @override
  String deskUpToDate({required Object target, required Object source}) =>
      '${target} уже синхронизирован с ${source}.';
  @override
  String uncommittedPreviewNotice({required Object target}) =>
      'В ${target} есть незакоммиченные изменения — показываю как патч.';
  @override
  String updateDeskFromLower({
    required Object target,
    required Object source,
  }) => 'обновить ${target} из ${source}';
  @override
  String noUpdatesToBringFrom({required Object source}) =>
      'Нет обновлений, которые можно принести из ${source}.';
  @override
  String get updatePrepFailed => 'Не удалась подготовка обновления';
  @override
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => 'принести изменения из ${source} в ${target}';
  @override
  String noPatchableChanges({required Object source, required Object target}) =>
      'Нет патчируемых изменений, которые можно принести из ${source} в ${target}.';
  @override
  String get patchPrepFailed => 'Не удалась подготовка патча';
  @override
  String failureWithError({required Object label, required Object error}) =>
      '${label}: ${error}';
  @override
  String get titleHint => 'заголовок';
  @override
  String get bodyHint => 'текст';
  @override
  String get bodyOptionalHint => 'текст (необязательно)';
  @override
  String get draftLower => 'черновик';
  @override
  String get cancelLower => 'отмена';
  @override
  String get saveLower => 'сохранить';
  @override
  String couldntSave({required Object error}) =>
      'Не удалось сохранить: ${error}';
  @override
  String get stashedNoOtherDesk =>
      'Изменения спрятаны — нет другого Desk для их применения. Используйте git stash pop для восстановления.';
  @override
  String get suggestedSource => 'предложенный источник';
  @override
  String tooltipModifiedCount({required Object n}) => '${n} изменено';
  @override
  String tooltipAheadCount({required Object n}) => '${n} впереди';
  @override
  String tooltipBehindCount({required Object n}) => '${n} позади';
  @override
  String get focusedEdits => 'сфокусированные правки';
  @override
  String get editsSpreadAcrossSubsystems => 'правки разбросаны по подсистемам';
  @override
  String get editsTouchingManySubsystems => 'правки задевают много подсистем';
  @override
  String get focusedBranch => 'сфокусированная ветка';
  @override
  String get branchSpansMultipleSubsystems =>
      'ветка охватывает несколько подсистем';
  @override
  String get structurallyDivergentFromMainline =>
      'структурно расходится с основной линией';
  @override
  String get localPr => 'локальный PR';
  @override
  String lastTouched({required Object time}) => 'последнее касание ${time}';
  @override
  String driftGroupCount({required Object n, required Object dir}) =>
      '${n} в ${dir}';
  @override
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';
  @override
  String get uncommittedChanges => 'Незакоммиченные изменения';
  @override
  String get closeDeskQuestion => 'Закрыть Desk?';
  @override
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} незакоммиченный файл.',
        few: '${n} незакоммиченных файла.',
        many: '${n} незакоммиченных файлов.',
        other: '${n} незакоммиченных файлов.',
      );
  @override
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} коммит впереди main.',
        few: '${n} коммита впереди main.',
        many: '${n} коммитов впереди main.',
        other: '${n} коммитов впереди main.',
      );
  @override
  String get willRemoveWorktreeDirectory =>
      'Это удалит каталог рабочего дерева.';
  @override
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} файл изменён',
        few: '${n} файла изменено',
        many: '${n} файлов изменено',
        other: '${n} файлов изменено',
      );
  @override
  String get shelveHere => 'Отложить сюда';
  @override
  String get discardAndClose => 'Отбросить и закрыть';
  @override
  String get noRepository => 'нет репозитория';
  @override
  String get issuePromotedToRemote => 'Задача продвинута в удалённый.';
  @override
  String get pushedToRemote => 'Отправлено в удалённый.';
  @override
  String get pulledFromRemote => 'Забрано из удалённого.';
  @override
  String get remoteIssueNotFound => 'удалённая задача не найдена';
  @override
  String importedIssueLocally({required Object id}) =>
      'Импортирована #${id} локально.';
  @override
  String get issueAbandoned => 'Задача заброшена.';
  @override
  String get abandonIssue => 'Забросить задачу';
  @override
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      'Навсегда удалить локальную задачу #${id}? Это удалит её ссылку без возможности отмены.';
  @override
  String get abandon => 'Забросить';
  @override
  String publishedBranch({required Object branch}) => '${branch} опубликована.';
  @override
  String get publishingEllipsis => 'Публикация…';
  @override
  String get publish => 'Опубликовать';
  @override
  String get noRemoteConfigured =>
      'Для этого репозитория удалённый не настроен.';
  @override
  String get jumpToDesk => 'Перейти к Desk';
  @override
  String get arrowOpen => '→ открыть';
  @override
  String get openOnANewDesk => 'Открыть на новом Desk';
  @override
  String get plusDesk => '+ Desk';
  @override
  String get plusSpace => '+ ';
  @override
  String get newBranchNameHint => 'имя-новой-ветки';
  @override
  String get escLower => 'esc';
  @override
  String get plusNewDesk => '+ новый Desk';
  @override
  String get fromHeadEllipsis => 'от HEAD...';
  @override
  String get viewAllBranches => 'Показать все ветки';
  @override
  String get issuesLower => 'задачи';
  @override
  String get newIssueLower => 'новая задача';
  @override
  String get noneLinked => 'нет связанных';
  @override
  String get noOpenIssues => 'нет открытых задач';
  @override
  String get createAndPushLower => 'создать + отправить';
  @override
  String get createLower => 'создать';
  @override
  String get remoteLower => 'удалённый';
  @override
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';
  @override
  String get promoteToRemote => 'Продвинуть в удалённый';
  @override
  String get pushToRemote => 'Отправить в удалённый';
  @override
  String get pullFromRemote => 'Забрать из удалённого';
  @override
  String get importLabel => 'Импорт';
  @override
  String get failedToCreateRepository => 'Не удалось создать репозиторий.';
  @override
  String get openRepositoryLower => 'открыть репозиторий';
  @override
  String get newRepositoryLower => 'новый репозиторий';
  @override
  String get back => 'Назад';
  @override
  String get openRepositoryDialogTitle => 'Открыть репозиторий';
  @override
  String get createRepositoryDialogTitle => 'Создать репозиторий';
  @override
  String get cloneTargetDialogTitle => 'Цель клонирования';
  @override
  String get cloneToDialogTitle => 'Клонировать в';
  @override
  String get exportToDialogTitle => 'Экспортировать в';
  @override
  String get createFromTemplateInDialogTitle => 'Создать из шаблона в';
  @override
  String get notAGitRepoInitConfirm =>
      'Это не git-репозиторий. Инициализировать здесь?';
  @override
  String get repositoryUrlRequired => 'Требуется URL репозитория.';
  @override
  String get failedToCloneRepository => 'Не удалось клонировать репозиторий.';
  @override
  String cloningEllipsis({required Object name}) => 'Клонирую ${name}...';
  @override
  String get cloneCancelled => 'Клонирование отменено.';
  @override
  String get noProjectsYet => 'Пока нет проектов';
  @override
  String get dissolveGroup => 'Распустить группу';
  @override
  String get projectsHeader => 'Проекты';
  @override
  String get cloneLabel => 'Клонировать';
  @override
  String get createLabel => 'Создать';
  @override
  String get openLabel => 'Открыть';
  @override
  String get repositoryUrlPlaceholder => 'URL репозитория';
  @override
  String get projectNameOrFullPathPlaceholder => 'имя-проекта или полный путь';
  @override
  String get pathToProjectPlaceholder => '/путь/к/проекту';
  @override
  String get cloneToFolderPathPlaceholder => 'Путь к папке клонирования';
  @override
  String get switchToCreateRepo => 'Перейти к созданию репозитория';
  @override
  String get explorer => 'Проводник';
  @override
  String get terminal => 'Терминал';
  @override
  String get cloneUrl => 'URL клонирования';
  @override
  String get copyPath => 'Копировать путь';
  @override
  String get export => 'Экспорт';
  @override
  String get readme => 'README';
  @override
  String get duplicate => 'Дублировать';
  @override
  String get template => 'Шаблон';
  @override
  String get forgetThisProject => 'Забыть этот проект';
  @override
  String get aiKindCommitMessage => 'сообщение коммита';
  @override
  String get aiKindReview => 'ревью';
  @override
  String get aiKindMuse => 'muse';
  @override
  String get aiKindPresent => 'презентация';
  @override
  String get aiKindDebug => 'отладка';
  @override
  String aiStatusRunning({required Object kind}) => '${kind} выполняется';
  @override
  String aiStatusFailedUnread({required Object kind}) =>
      '${kind} — сбой (не прочитано)';
  @override
  String aiStatusReadyUnread({required Object kind}) =>
      '${kind} готово (не прочитано)';
  @override
  String get filesLower => 'файлы';
  @override
  String get commitsLower => 'коммиты';
  @override
  String get undoLabel => 'Отменить';
  @override
  String get goLabel => 'вперёд';
  @override
  String countdownSeconds({required Object n}) => '${n} с';
  @override
  String get collapseGlyph => '▲ свернуть';
  @override
  String moreLinesGlyph({required Object n}) => '▼ ещё ${n} строк';
}

// Path: backend
class _Translations$backend$ru extends Translations$backend$en {
  _Translations$backend$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$backend$ops$ru ops = _Translations$backend$ops$ru._(
    _root,
  );
  @override
  late final _Translations$backend$mergeOutcome$ru mergeOutcome =
      _Translations$backend$mergeOutcome$ru._(_root);
}

// Path: branches
class _Translations$branches$ru extends Translations$branches$en {
  _Translations$branches$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get runningAiReview => 'Выполняю AI-ревью…';
  @override
  String prNumberLabel({required Object number}) => 'PR #${number}';
  @override
  String get findings => 'НАХОДКИ';
  @override
  String get observations => 'НАБЛЮДЕНИЯ';
  @override
  String get renameEllipsis => 'Переименовать…';
  @override
  String get publish => 'Опубликовать';
  @override
  String publishFailed({required Object error}) =>
      'Не удалось опубликовать: ${error}';
  @override
  String couldntOpenDesk({required Object error}) =>
      'Не удалось открыть Desk: ${error}';
  @override
  String syncFailed({required Object error}) => 'Сбой синхронизации: ${error}';
  @override
  String get renameBranchTitle => 'Переименовать ветку';
  @override
  String get newNameHint => 'новое имя';
  @override
  String get rename => 'Переименовать';
  @override
  String invalidBranchName({required Object name}) =>
      '«${name}» — недопустимое имя ветки.';
  @override
  String renameFailed({required Object error}) =>
      'Не удалось переименовать: ${error}';
  @override
  String deletingBranch({required Object name}) => 'Удаляю ${name}';
  @override
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '«${name}» открыта на Desk «${desk}».';
  @override
  String get openDesk => 'Открыть Desk';
  @override
  String openInDeskShort({required Object desk}) => 'открыть на Desk «${desk}»';
  @override
  String get couldNotPinBranch =>
      'не удалось закрепить вершину ветки; удаление пропущено';
  @override
  String get couldNotPinTag => 'не удалось закрепить метку; удаление пропущено';
  @override
  String deletingTag({required Object name}) => 'Удаляю метку ${name}';
  @override
  String get applyToActiveChanges => 'Применить к активным изменениям…';
  @override
  String get couldNotLoadPrDiff => 'Не удалось загрузить diff PR.';
  @override
  String prSourceLabel({required Object number, required Object title}) =>
      'PR #${number}: ${title}';
  @override
  String mergeIntoDesk({required Object branch}) => 'Мёржить в ${branch}…';
  @override
  String get checkoutThisPr => 'Checkout этого PR';
  @override
  String get mergeIntoNewDesk => 'Мёржить в новый Desk…';
  @override
  String get pushToForge => 'Запушить в форж';
  @override
  String get linkToIssue => 'Связать с задачей…';
  @override
  String get gitPatch => '↓ git-патч';
  @override
  String get copyBranchName => 'Копировать имя ветки';
  @override
  String copiedRef({required Object ref}) => 'Скопировано «${ref}»';
  @override
  String get reviewPr => 'Ревью PR';
  @override
  String get openInBrowser => 'Открыть в браузере';
  @override
  String get markAsRead => 'Пометить прочитанным';
  @override
  String get markAsUnread => 'Пометить непрочитанным';
  @override
  String get replaceLocalCommitsTitle => 'Заменить локальные коммиты?';
  @override
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref} содержит локальные коммиты, которых нет в удалённой вершине PR. Обновление заменит их последней версией из удалённого.';
  @override
  String get update => 'Обновить';
  @override
  String couldntFetchPr({required Object error}) =>
      'Не удалось получить PR: ${error}';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Не удалось открыть как Desk: ${error}';
  @override
  String couldntOpenInBrowser({required Object error}) =>
      'Не удалось открыть в браузере: ${error}';
  @override
  String get noIssuesYetLocal =>
      'Пока нет задач. Откройте одну в upstream или используйте «+ новая локальная задача» в линзе задач.';
  @override
  String get remotePrsLinkLocalOnly =>
      'Удалённые PR могут связываться только с локальными задачами. Создайте одну через «+ новая локальная задача».';
  @override
  String linkPrToIssues({required Object number}) =>
      'Связать PR #${number} с задачей(ами)';
  @override
  String get noPrsYetLocal =>
      'Пока нет PR. Откройте один в upstream или продвиньте Desk в PR.';
  @override
  String get remoteIssuesLinkLocalOnly =>
      'Удалённые задачи могут связываться только с локальными PR. Сначала продвиньте Desk в PR.';
  @override
  String linkIssueToPrs({required Object number}) =>
      'Связать задачу #${number} с PR';
  @override
  String couldntToggleLink({required Object error}) =>
      'Не удалось переключить связь: ${error}';
  @override
  String get openPatchDialogTitle => 'Открыть патч (.patch / .diff)';
  @override
  String get clipboardNoText => 'В буфере обмена нет текста.';
  @override
  String get clipboardPatchLabel => 'clipboard.patch';
  @override
  String failedToOpenPatch({required Object error}) =>
      'Не удалось открыть патч: ${error}';
  @override
  String get patchEmptyOrUnparseable => 'Патч пуст или не разбирается.';
  @override
  String get prPushedToForge => 'PR отправлен в форж.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      'Перезаписать ${ref} последней версией из удалённого?';
  @override
  String get overwrite => 'Перезаписать';
  @override
  String get loadingBranchesTitle => 'Загрузка веток';
  @override
  String get loadingBranchesMessage => 'Читаю локальные ветки и метки.';
  @override
  String get branchesUnavailableTitle => 'Ветки недоступны';
  @override
  String get filterPullRequestsHint => 'фильтр pull request…';
  @override
  String get filterIssuesHint => 'фильтр задач…';
  @override
  String get branchNameHint => 'имя ветки';
  @override
  String get tagsNewestFirst => 'метки, сначала новые';
  @override
  String get tagsOldestFirst => 'метки, сначала старые';
  @override
  String get flipSortDirection => 'сменить направление сортировки';
  @override
  String get readingPullRequests => 'Читаю pull request…';
  @override
  String get noOpenPullRequests => 'Нет открытых pull request';
  @override
  String get noPullRequestsHint => 'Откройте из ветки или продвиньте Desk.';
  @override
  String get noPrsMatchFilters => 'Ни один PR не подходит под фильтры';
  @override
  String get toggleFiltersRowAbove => 'Отключите фильтры в строке выше.';
  @override
  String get issuesNewestFirst => 'задачи, сначала новые';
  @override
  String get issuesOldestFirst => 'задачи, сначала старые';
  @override
  String get issuesHeading => 'ЗАДАЧИ';
  @override
  String get readingIssuesLower => 'читаю задачи…';
  @override
  String get noOpenIssues => 'Нет открытых задач';
  @override
  String get noIssuesHint => '+ новая для отслеживания работы и багов.';
  @override
  String get nothingMatches => 'Ничего не подходит';
  @override
  String get toggleFiltersAbove => 'Отключите фильтры выше.';
  @override
  String get bucketFresh => 'СВЕЖЕЕ';
  @override
  String get bucketThisWeek => 'НА ЭТОЙ НЕДЕЛЕ';
  @override
  String get bucketStalled => 'ЗАСТОПОРИЛОСЬ';
  @override
  String get bucketOlder => 'СТАРЕЕ';
  @override
  String get couldNotResolveMainWorktree =>
      'Не удалось определить путь главного рабочего каталога.';
  @override
  String couldntSubmitReview({required Object error}) =>
      'Не удалось отправить ревью: ${error}';
  @override
  String get reviewAiNotAvailable => 'AI-ревью пока недоступно.';
  @override
  String get noReviewModelConfigured => 'Модель для ревью не настроена.';
  @override
  String get deskFallback => 'Desk';
  @override
  String deskUncommittedChanges({
    required num n,
    required Object branch,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
    n,
    one:
        '${branch} содержит ${n} незакоммиченное изменение — сначала закоммитьте или спрячьте.',
    few:
        '${branch} содержит ${n} незакоммиченных изменения — сначала закоммитьте или спрячьте.',
    many:
        '${branch} содержит ${n} незакоммиченных изменений — сначала закоммитьте или спрячьте.',
    other:
        '${branch} содержит ${n} незакоммиченных изменений — сначала закоммитьте или спрячьте.',
  );
  @override
  String get targetDeskNoBranch => 'У целевого Desk нет ветки.';
  @override
  String mergePrIntoDesk({required Object number, required Object branch}) =>
      'Мёржить PR #${number} в ${branch}';
  @override
  String get conflictCheckUnavailableVersion =>
      'Проверка конфликтов недоступна — нужен git 2.38+';
  @override
  String get conflictCheckUnavailable => 'Проверка конфликтов недоступна';
  @override
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'БУДЕТ КОНФЛИКТ · ${n} файл',
        few: 'БУДЕТ КОНФЛИКТ · ${n} файла',
        many: 'БУДЕТ КОНФЛИКТ · ${n} файлов',
        other: 'БУДЕТ КОНФЛИКТ · ${n} файлов',
      );
  @override
  String plusMore({required Object n}) => '+${n} ещё';
  @override
  String get rebase => 'Rebase';
  @override
  String get squash => 'Squash';
  @override
  String get mergeCommit => 'Мёрж-коммит';
  @override
  String noDeskForBranch({required Object branch}) =>
      'Для ветки ${branch} Desk не найден';
  @override
  String get mergeAnyway => 'Мёржить всё равно';
  @override
  String get readingIssues => 'Читаю задачи…';
  @override
  String get openUpstreamOrLocal =>
      'Откройте одну в upstream или откройте локальную.';
  @override
  String get noIssuesMatchFilters => 'Ни одна задача не подходит под фильтры';
  @override
  String couldntCreateIssue({required Object error}) =>
      'Не удалось создать задачу: ${error}';
  @override
  String get promoteToRemote => 'Продвинуть в удалённый';
  @override
  String get pushToRemote => 'Отправить в удалённый';
  @override
  String get pullFromRemote => 'Забрать из удалённого';
  @override
  String get import => 'Импорт';
  @override
  String get linkToPr => 'Связать с PR…';
  @override
  String get abandon => 'Забросить';
  @override
  String get issuePromotedToRemote => 'Задача продвинута в удалённый.';
  @override
  String get issuePushedToRemote => 'Отправлено в удалённый.';
  @override
  String get issuePulledFromRemote => 'Забрано из удалённого.';
  @override
  String issueImportedLocally({required Object number}) =>
      'Импортирована #${number} локально.';
  @override
  String get abandonIssueTitle => 'Забросить задачу';
  @override
  String abandonIssueMessage({required Object id}) =>
      'Навсегда удалить локальную задачу #${id}? Это удалит её ссылку без возможности отмены.';
  @override
  String couldntAbandon({required Object error}) =>
      'Не удалось забросить: ${error}';
  @override
  String couldntPostComment({required Object error}) =>
      'Не удалось отправить комментарий: ${error}';
  @override
  String couldntCloseIssue({required Object error}) =>
      'Не удалось закрыть задачу: ${error}';
  @override
  String couldntAddLabel({required Object error}) =>
      'Не удалось добавить метку: ${error}';
  @override
  String get lensBranches => 'ВЕТКИ';
  @override
  String get lensPrs => 'PR';
  @override
  String get patchUp => '↑ патч';
  @override
  String get syncRibbon => '⇅ синхр';
  @override
  String get kbHeading => 'КЛАВИАТУРА';
  @override
  String get kbNavigateRows => 'навигация по строкам';
  @override
  String get kbExpandCollapse => 'развернуть / свернуть строку в фокусе';
  @override
  String get kbCheckoutPr => 'checkout PR в фокусе локально';
  @override
  String get kbApproveReview => 'одобрить · ревью';
  @override
  String get kbRequestChanges => 'запросить правки';
  @override
  String get kbFocusSearch => 'фокус на поиск';
  @override
  String get kbSwitchLens => 'сменить линзу (ветки · pr)';
  @override
  String get kbToggleOverlay => 'переключить это наложение';
  @override
  String get kbPressToDismiss => 'нажмите где угодно, чтобы закрыть';
  @override
  String get overrideScarTooltip =>
      'слито с проваленными проверками или без одобряющего ревью — сначала разберитесь под огнём';
  @override
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} файл пересекается с вашей незакоммиченной работой',
        few: '${n} файла пересекаются с вашей незакоммиченной работой',
        many: '${n} файлов пересекаются с вашей незакоммиченной работой',
        other: '${n} файлов пересекаются с вашей незакоммиченной работой',
      );
  @override
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '#${pr}  (${n} файл)',
        few: '#${pr}  (${n} файла)',
        many: '#${pr}  (${n} файлов)',
        other: '#${pr}  (${n} файлов)',
      );
  @override
  String get prStateDraft => 'ЧЕРНОВИК';
  @override
  String get localBadge => 'ЛОКАЛЬНО';
  @override
  String get myReviewPending => 'ваше ревью в ожидании';
  @override
  String get myReviewApproved => 'вы ✓';
  @override
  String get myReviewChangesRequested => 'вы ✗ запросили правки';
  @override
  String get myReviewCommented => 'вы прокомментировали';
  @override
  String get myReviewDefault => 'вы';
  @override
  String tailCommentsAuthor({required Object count}) =>
      '${count} комментариев · показан последний от автора';
  @override
  String get tailLastComment => 'последний комментарий';
  @override
  String tailLastReviewState({required Object state}) =>
      'последнее ревью · ${state}';
  @override
  String get tailLastReview => 'последнее ревью';
  @override
  String tailLastCheckState({required Object state}) =>
      'последняя проверка · ${state}';
  @override
  String get tailLastCommit => 'последний коммит';
  @override
  String get tailLastActivity => 'последняя активность';
  @override
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'закрывает ${n} задачу — нажмите, чтобы перейти',
        few: 'закрывает ${n} задачи — нажмите, чтобы перейти',
        many: 'закрывает ${n} задач — нажмите, чтобы перейти',
        other: 'закрывает ${n} задач — нажмите, чтобы перейти',
      );
  @override
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'решается ${n} PR — нажмите, чтобы перейти',
        few: 'решается ${n} PR — нажмите, чтобы перейти',
        many: 'решается ${n} PR — нажмите, чтобы перейти',
        other: 'решается ${n} PR — нажмите, чтобы перейти',
      );
  @override
  String get checksLabel => 'проверки';
  @override
  String get reviewersLabel => 'ревьюеры';
  @override
  String get conflictsLabel => 'конфликты';
  @override
  String exportFailed({required Object error}) => 'Не удался экспорт: ${error}';
  @override
  String get readingFiles => 'читаю файлы…';
  @override
  String get noDetailAvailable => 'деталей нет';
  @override
  String get noFilesReported => 'файлы не заявлены';
  @override
  String get readingGitHistory => 'читаю историю git…';
  @override
  String get knowsThisCode => 'знает этот код';
  @override
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} коммит по этим файлам за последний год',
        few: '${n} коммита по этим файлам за последний год',
        many: '${n} коммитов по этим файлам за последний год',
        other: '${n} коммитов по этим файлам за последний год',
      );
  @override
  String get willFight => 'БУДЕТ БОРЬБА';
  @override
  String orbitalPartnerCos({required Object cos}) =>
      'орбитальный партнёр — cos ${cos}';
  @override
  String get orbitLabel => 'орбита';
  @override
  String get touchesYourLocalWork => 'ЗАДЕВАЕТ ВАШУ ЛОКАЛЬНУЮ РАБОТУ';
  @override
  String get mergingWillConflict =>
      'слияние, вероятно, конфликтнёт с вашими незакоммиченными изменениями';
  @override
  String get closesHeading => 'ЗАКРЫВАЕТ';
  @override
  String get filesHeading => 'ФАЙЛЫ';
  @override
  String get orientAligned => 'сонаправлен';
  @override
  String get orientAdjacent => 'смежный';
  @override
  String get orientOrthogonal => 'ортогональный';
  @override
  String shapeField({required Object v}) => 'поле ${v}';
  @override
  String shapeSource({required Object v}) => 'источник ${v}';
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
  String shapeStress({required Object v}) => 'напряжение ${v}';
  @override
  String shapeWit({required Object v}) => 'wit ${v}';
  @override
  String resonanceReadout({required Object v}) => 'резонанс ${v}';
  @override
  String ghostFileTooltip({required Object path}) =>
      'обычно движется с файлами этого PR\n(${path})';
  @override
  String get prStateDraftLower => 'черновик';
  @override
  String get keystoneTooltip =>
      'краеугольный — файл-мост уровня всего репозитория';
  @override
  String get reviewNoteHint => 'оставьте заметку (необязательно)…';
  @override
  String get reviewComment => 'комментарий';
  @override
  String get reviewRequestChanges => 'запросить правки';
  @override
  String get reviewApprove => '✓ одобрить';
  @override
  String get actionPatchDown => '↓ патч';
  @override
  String get actionPrReview => '✦ ревью pr';
  @override
  String get actionOpenAsDesk => '⊞ открыть как Desk';
  @override
  String get actionCheckout => '[c] checkout';
  @override
  String get actionMerge => '[m] мёрж ▾';
  @override
  String get mergeMenuMergeCommit => 'мёрж-коммит';
  @override
  String get mergeMenuSquash => 'squash и мёрж';
  @override
  String get mergeMenuRebase => 'rebase и мёрж';
  @override
  String get deleteBranchAfter => 'удалить ветку после';
  @override
  String checkDurationSec({required Object n}) => '${n} с';
  @override
  String checkDurationMin({required Object m, required Object s}) =>
      '${m} м ${s} с';
  @override
  String assignedTo({required Object names}) => 'назначено: ${names}';
  @override
  String issueConvLine({required Object n, required Object time}) =>
      '${n} обсужд · ${time}';
  @override
  String get readingThread => 'читаю обсуждение…';
  @override
  String get addressedByHeading => 'РЕШАЕТСЯ';
  @override
  String get descriptionHeading => 'ОПИСАНИЕ';
  @override
  String get threadHeading => 'ОБСУЖДЕНИЕ';
  @override
  String get replyHint => 'ответить…';
  @override
  String get assignMe => 'назначить меня';
  @override
  String get closeLower => 'закрыть';
  @override
  String get postReply => '↩ отправить';
  @override
  String get remoteProviderUnavailable => 'Удалённый провайдер недоступен';
  @override
  String get noRecognisedRemoteHost =>
      'Для этого репозитория нет распознанного удалённого хоста.';
  @override
  String get corpseGone => 'нет';
  @override
  String get corpseAbsorbed => 'поглощена';
  @override
  String get corpseSquashed => 'засквошена';
  @override
  String absorbedDeliveredIn({required Object hash}) => 'доставлено в ${hash}';
  @override
  String get absorbedNoChanges => 'слияние не добавляет изменений';
  @override
  String get corpseTagUpstreamGone => 'upstream пропал';
  @override
  String corpseTagAbsorbed({required Object receipt}) =>
      'поглощена, ${receipt}';
  @override
  String get corpseTagSquashed => 'засквошена и смёржена';
  @override
  String semanticsCurrentBranch({required Object name}) =>
      '${name}, текущая ветка';
  @override
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}, слежение за ${upstream}';
  @override
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}, ${tag}';
  @override
  String semanticsWorktreeOpen({required Object label}) =>
      '${label}, рабочий каталог открыт';
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
  String get crossLinkPrDraft => 'PR · черновик';
  @override
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} задача',
        few: '${n} задачи',
        many: '${n} задач',
        other: '${n} задач',
      );
  @override
  String get headBadge => 'HEAD';
  @override
  String trackingLine({required Object upstream}) => '→ слежение: ${upstream}';
  @override
  String get checkoutButton => 'Checkout';
  @override
  String get createBranch => 'Создать ветку';
  @override
  String get newBranchName => 'Имя новой ветки';
  @override
  String newBranchNameError({required Object error}) =>
      'Имя новой ветки — ${error}';
  @override
  String get forceDelete => 'Принудительно?';
  @override
  String get annotated => 'аннотированная';
  @override
  String get applyCheckFailed => 'apply --check не прошёл';
  @override
  String get openPatchFrom => 'ОТКРЫТЬ ПАТЧ ИЗ';
  @override
  String get patchFromFile => 'из файла…';
  @override
  String get patchFromFileHint => '.patch / .diff';
  @override
  String get patchFromClipboard => 'из буфера обмена';
  @override
  String get patchFromClipboardHint => 'вставить текст';
  @override
  String get patchPreviewHeading => 'ПРЕВЬЮ ПАТЧА';
  @override
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';
  @override
  String get stagedDone => 'проиндексировано.';
  @override
  String get appliedDone => 'применено.';
  @override
  String get opening => 'открываю…';
  @override
  String get mergeEditor => '⇋ редактор слияния';
  @override
  String get staging => 'индексация…';
  @override
  String get applying => 'применяю…';
  @override
  String get stage => 'в индекс';
  @override
  String get apply => 'применить';
  @override
  String get refineHint => 'уточните… (напр. «ещё убери правки логгера»)';
  @override
  String get reverseArmedTooltip =>
      'взведено — следующее применение ОТКАТИТ патч (-R)';
  @override
  String get reverseDisarmedTooltip =>
      'взвести реверс (-R) — отмена вместо применения';
  @override
  String get reverseArmedLabel => '⟲ реверс ✓';
  @override
  String get reverseLabel => '⟲ реверс';
  @override
  String get untouchedHeading => '⚠ НЕ ЗАТРОНУТО';
  @override
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${count} из ${n} файла нет в патче',
        few: '${count} из ${n} файлов нет в патче',
        many: '${count} из ${n} файлов нет в патче',
        other: '${count} из ${n} файлов нет в патче',
      );
  @override
  String get staysConflicted =>
      'эти файлы останутся в конфликте — применение не проиндексирует их';
  @override
  String get orWith => 'ИЛИ С';
  @override
  String get noAiModelConfigured => 'AI-модель не настроена';
  @override
  String applyWithPatchFrom({required Object label}) =>
      'применить с патчем от ${label}';
  @override
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => 'применить с патчем от ${label}  ·  ${model}';
  @override
  String get patching => 'патчу…';
  @override
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  применить с патчем от ${label}';
  @override
  String get orWithAnotherModel => 'или с другой моделью';
  @override
  String get applyCheckPassed =>
      'git apply --check прошёл — патч применится чисто';
  @override
  String get gitApplyCheckFailed => 'git apply --check не прошёл';
  @override
  String get appliesClean => 'применяется чисто';
  @override
  String get willNotApply => 'не применится';
  @override
  String get newLocalIssue => 'новая локальная задача';
  @override
  String get filterHint => 'фильтр…';
  @override
  String get nothingToLink => 'Пока нечего связывать.';
  @override
  String get nothingMatchesDot => 'Ничего не подходит.';
  @override
  String get relevantHeading => 'РЕЛЕВАНТНОЕ';
  @override
  String get allHeading => 'ВСЁ';
  @override
  String get doneLower => 'готово';
  @override
  String get candidateRemote => 'R';
  @override
  String get candidateLocal => 'L';
  @override
  String get newLocalIssueTitle => 'Новая локальная задача';
  @override
  String get titleHint => 'заголовок';
  @override
  String get bodyHint => 'текст (markdown)';
  @override
  String get cancelLower => 'отмена';
  @override
  String get createLower => 'создать';
  @override
  String get deleteFailed => 'не удалось удалить';
  @override
  String reviewFailed({required Object error}) => 'Сбой ревью: ${error}';
  @override
  String get resolutionFailed => 'не удалось устранить';
  @override
  String get patchBlocksNoCover =>
      'модель вернула блоки патча, не покрывающие проблемные файлы';
  @override
  String get applyFailed => 'не удалось применить';
  @override
  String get emptyOrUnparseablePatch =>
      'модель вернула пустой или неразбираемый патч';
  @override
  String noModelConfiguredFor({required Object label}) =>
      'для «${label}» модель не настроена';
  @override
  String get checksHeading => 'ПРОВЕРКИ';
  @override
  String get peopleHeading => 'УЧАСТНИКИ';
  @override
  String get conversationHeading => 'ОБСУЖДЕНИЕ';
}

// Path: changes
class _Translations$changes$ru extends Translations$changes$en {
  _Translations$changes$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$usage$ru usage =
      _Translations$changes$usage$ru._(_root);
  @override
  late final _Translations$changes$tabs$ru tabs =
      _Translations$changes$tabs$ru._(_root);
  @override
  late final _Translations$changes$tabStrip$ru tabStrip =
      _Translations$changes$tabStrip$ru._(_root);
  @override
  late final _Translations$changes$select$ru select =
      _Translations$changes$select$ru._(_root);
  @override
  late final _Translations$changes$constellationToggle$ru constellationToggle =
      _Translations$changes$constellationToggle$ru._(_root);
  @override
  late final _Translations$changes$nudgeChip$ru nudgeChip =
      _Translations$changes$nudgeChip$ru._(_root);
  @override
  late final _Translations$changes$minimap$ru minimap =
      _Translations$changes$minimap$ru._(_root);
  @override
  late final _Translations$changes$tagInput$ru tagInput =
      _Translations$changes$tagInput$ru._(_root);
  @override
  late final _Translations$changes$composer$ru composer =
      _Translations$changes$composer$ru._(_root);
  @override
  late final _Translations$changes$commit$ru commit =
      _Translations$changes$commit$ru._(_root);
  @override
  late final _Translations$changes$rebase$ru rebase =
      _Translations$changes$rebase$ru._(_root);
  @override
  late final _Translations$changes$editor$ru editor =
      _Translations$changes$editor$ru._(_root);
  @override
  late final _Translations$changes$editorTitles$ru editorTitles =
      _Translations$changes$editorTitles$ru._(_root);
  @override
  late final _Translations$changes$askHint$ru askHint =
      _Translations$changes$askHint$ru._(_root);
  @override
  late final _Translations$changes$fileMenu$ru fileMenu =
      _Translations$changes$fileMenu$ru._(_root);
  @override
  late final _Translations$changes$multiFileMenu$ru multiFileMenu =
      _Translations$changes$multiFileMenu$ru._(_root);
  @override
  late final _Translations$changes$ignoreMenu$ru ignoreMenu =
      _Translations$changes$ignoreMenu$ru._(_root);
  @override
  late final _Translations$changes$discard$ru discard =
      _Translations$changes$discard$ru._(_root);
  @override
  late final _Translations$changes$snack$ru snack =
      _Translations$changes$snack$ru._(_root);
  @override
  late final _Translations$changes$trace$ru trace =
      _Translations$changes$trace$ru._(_root);
  @override
  late final _Translations$changes$cleanTree$ru cleanTree =
      _Translations$changes$cleanTree$ru._(_root);
  @override
  late final _Translations$changes$guardrail$ru guardrail =
      _Translations$changes$guardrail$ru._(_root);
  @override
  late final _Translations$changes$dropHint$ru dropHint =
      _Translations$changes$dropHint$ru._(_root);
  @override
  late final _Translations$changes$diffEmpty$ru diffEmpty =
      _Translations$changes$diffEmpty$ru._(_root);
  @override
  late final _Translations$changes$shelvePill$ru shelvePill =
      _Translations$changes$shelvePill$ru._(_root);
  @override
  late final _Translations$changes$stashAction$ru stashAction =
      _Translations$changes$stashAction$ru._(_root);
  @override
  late final _Translations$changes$stashContents$ru stashContents =
      _Translations$changes$stashContents$ru._(_root);
  @override
  late final _Translations$changes$stashFile$ru stashFile =
      _Translations$changes$stashFile$ru._(_root);
  @override
  late final _Translations$changes$fileRow$ru fileRow =
      _Translations$changes$fileRow$ru._(_root);
  @override
  late final _Translations$changes$resolveStrip$ru resolveStrip =
      _Translations$changes$resolveStrip$ru._(_root);
  @override
  late final _Translations$changes$badge$ru badge =
      _Translations$changes$badge$ru._(_root);
  @override
  late final _Translations$changes$review$ru review =
      _Translations$changes$review$ru._(_root);
  @override
  late final _Translations$changes$commitBtn$ru commitBtn =
      _Translations$changes$commitBtn$ru._(_root);
  @override
  late final _Translations$changes$shapeBtn$ru shapeBtn =
      _Translations$changes$shapeBtn$ru._(_root);
  @override
  late final _Translations$changes$dejaVu$ru dejaVu =
      _Translations$changes$dejaVu$ru._(_root);
  @override
  late final _Translations$changes$identity$ru identity =
      _Translations$changes$identity$ru._(_root);
  @override
  late final _Translations$changes$staleScope$ru staleScope =
      _Translations$changes$staleScope$ru._(_root);
  @override
  late final _Translations$changes$finding$ru finding =
      _Translations$changes$finding$ru._(_root);
  @override
  late final _Translations$changes$muse$ru muse =
      _Translations$changes$muse$ru._(_root);
  @override
  late final _Translations$changes$debug$ru debug =
      _Translations$changes$debug$ru._(_root);
  @override
  late final _Translations$changes$includeSummary$ru includeSummary =
      _Translations$changes$includeSummary$ru._(_root);
  @override
  late final _Translations$changes$status$ru status =
      _Translations$changes$status$ru._(_root);
  @override
  late final _Translations$changes$stash$ru stash =
      _Translations$changes$stash$ru._(_root);
  @override
  late final _Translations$changes$tooltips$ru tooltips =
      _Translations$changes$tooltips$ru._(_root);
  @override
  late final _Translations$changes$mergeEditor$ru mergeEditor =
      _Translations$changes$mergeEditor$ru._(_root);
  @override
  late final _Translations$changes$conflictResolution$ru conflictResolution =
      _Translations$changes$conflictResolution$ru._(_root);
  @override
  late final _Translations$changes$mergeFlow$ru mergeFlow =
      _Translations$changes$mergeFlow$ru._(_root);
  @override
  late final _Translations$changes$constellation$ru constellation =
      _Translations$changes$constellation$ru._(_root);
}

// Path: common
class _Translations$common$ru extends Translations$common$en {
  _Translations$common$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get listSeparator => ', ';
  @override
  String get cancel => 'Отмена';
  @override
  String get close => 'Закрыть';
  @override
  String get save => 'Сохранить';
  @override
  String get delete => 'Удалить';
  @override
  String get retry => 'Повторить';
  @override
  String get copy => 'Копировать';
  @override
  String get copied => 'Скопировано';
  @override
  String get done => 'Готово';
  @override
  String get loading => 'Загрузка…';
  @override
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} файл',
        few: '${n} файла',
        many: '${n} файлов',
        other: '${n} файлов',
      );
  @override
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} коммит',
        few: '${n} коммита',
        many: '${n} коммитов',
        other: '${n} коммитов',
      );
  @override
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} ветка',
        few: '${n} ветки',
        many: '${n} веток',
        other: '${n} веток',
      );
  @override
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} локальный коммит',
        few: '${n} локальных коммита',
        many: '${n} локальных коммитов',
        other: '${n} локальных коммитов',
      );
  @override
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} удалённый коммит',
        few: '${n} удалённых коммита',
        many: '${n} удалённых коммитов',
        other: '${n} удалённых коммитов',
      );
  @override
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} файл с конфликтом',
        few: '${n} файла с конфликтами',
        many: '${n} файлов с конфликтами',
        other: '${n} файлов с конфликтами',
      );
  @override
  late final _Translations$common$time$ru time = _Translations$common$time$ru._(
    _root,
  );
  @override
  late final _Translations$common$size$ru size = _Translations$common$size$ru._(
    _root,
  );
}

// Path: diff
class _Translations$diff$ru extends Translations$diff$en {
  _Translations$diff$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$diff$status$ru status =
      _Translations$diff$status$ru._(_root);
  @override
  late final _Translations$diff$toolbar$ru toolbar =
      _Translations$diff$toolbar$ru._(_root);
  @override
  late final _Translations$diff$hunkDropdown$ru hunkDropdown =
      _Translations$diff$hunkDropdown$ru._(_root);
  @override
  String stagingFailed({required Object error}) =>
      'Не удалось частично проиндексировать: ${error}';
  @override
  late final _Translations$diff$trail$ru trail = _Translations$diff$trail$ru._(
    _root,
  );
  @override
  late final _Translations$diff$pinned$ru pinned =
      _Translations$diff$pinned$ru._(_root);
  @override
  late final _Translations$diff$hunkHint$ru hunkHint =
      _Translations$diff$hunkHint$ru._(_root);
  @override
  late final _Translations$diff$binary$ru binary =
      _Translations$diff$binary$ru._(_root);
  @override
  late final _Translations$diff$media$ru media = _Translations$diff$media$ru._(
    _root,
  );
}

// Path: filament
class _Translations$filament$ru extends Translations$filament$en {
  _Translations$filament$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get noRepositoryOpen => 'Репозиторий не открыт.';
  @override
  String scanningProgress({required Object scanned, required Object total}) =>
      'сканирование ${scanned} / ${total} файлов…';
  @override
  String findingsAcrossFiles({required Object count, required Object files}) =>
      '${count} находок в ${files} файлах';
  @override
  String copiedFindings({required Object count}) =>
      'Скопировано находок: ${count}';
  @override
  String get copy => 'КОПИРОВАТЬ';
  @override
  String get noFindings => 'Находок по потоку выполнения нет.';
  @override
  late final _Translations$filament$severity$ru severity =
      _Translations$filament$severity$ru._(_root);
  @override
  late final _Translations$filament$kind$ru kind =
      _Translations$filament$kind$ru._(_root);
  @override
  String lineLabel({required Object line}) => 'стр. ${line}';
  @override
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class _Translations$history$ru extends Translations$history$en {
  _Translations$history$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$ru commitLede =
      _Translations$history$commitLede$ru._(_root);
  @override
  late final _Translations$history$seismograph$ru seismograph =
      _Translations$history$seismograph$ru._(_root);
  @override
  late final _Translations$history$worldline$ru worldline =
      _Translations$history$worldline$ru._(_root);
  @override
  late final _Translations$history$contextMenu$ru contextMenu =
      _Translations$history$contextMenu$ru._(_root);
  @override
  late final _Translations$history$cherryPick$ru cherryPick =
      _Translations$history$cherryPick$ru._(_root);
  @override
  late final _Translations$history$revert$ru revert =
      _Translations$history$revert$ru._(_root);
  @override
  late final _Translations$history$reflog$ru reflog =
      _Translations$history$reflog$ru._(_root);
  @override
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'Этот коммит глубже, чем ${n} загруженный коммит.',
        few: 'Этот коммит глубже, чем ${n} загруженных коммита.',
        many: 'Этот коммит глубже, чем ${n} загруженных коммитов.',
        other: 'Этот коммит глубже, чем ${n} загруженных коммитов.',
      );
  @override
  String deleteTagFailed({required Object error}) =>
      'Не удалось удалить метку: ${error}';
  @override
  String get loadingTitle => 'Загрузка истории';
  @override
  String get loadingMessage => 'Читаю недавние коммиты.';
  @override
  String get unavailableTitle => 'История недоступна';
  @override
  String get toggleWorldline => 'Переключить мировую линию';
  @override
  String get pageTitle => 'История';
  @override
  String get viewingLast => 'Показаны последние';
  @override
  String get commitsUnit => 'коммитов';
  @override
  String get noCommitSelectedTitle => 'Коммит не выбран';
  @override
  String get noCommitSelectedMessage =>
      'Выберите коммит, чтобы изучить его изменения.';
  @override
  String get loadingCommitTitle => 'Загрузка коммита';
  @override
  String get loadingCommitMessage => 'Читаю детали коммита.';
  @override
  String get commitUnavailableTitle => 'Коммит недоступен';
  @override
  String get couldNotLoadCommit => 'Не удалось загрузить коммит.';
  @override
  String get reflogDividerLabel => 'reflog';
  @override
  String get loadReflog => 'Загрузить reflog';
  @override
  String get createTag => 'Создать метку';
  @override
  String get newTagName => 'Имя новой метки';
  @override
  String newTagNameError({required Object error}) =>
      'Имя новой метки — ${error}';
  @override
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} файл · все изменения',
        few: '${n} файла · все изменения',
        many: '${n} файлов · все изменения',
        other: '${n} файлов · все изменения',
      );
  @override
  String get allChangesLabel => 'все изменения';
  @override
  late final _Translations$history$rebase$ru rebase =
      _Translations$history$rebase$ru._(_root);
  @override
  late final _Translations$history$inFlight$ru inFlight =
      _Translations$history$inFlight$ru._(_root);
}

// Path: historySurgery
class _Translations$historySurgery$ru extends Translations$historySurgery$en {
  _Translations$historySurgery$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$historySurgery$chrome$ru chrome =
      _Translations$historySurgery$chrome$ru._(_root);
  @override
  late final _Translations$historySurgery$select$ru select =
      _Translations$historySurgery$select$ru._(_root);
  @override
  late final _Translations$historySurgery$understand$ru understand =
      _Translations$historySurgery$understand$ru._(_root);
  @override
  late final _Translations$historySurgery$confirm$ru confirm =
      _Translations$historySurgery$confirm$ru._(_root);
  @override
  late final _Translations$historySurgery$execute$ru execute =
      _Translations$historySurgery$execute$ru._(_root);
  @override
  late final _Translations$historySurgery$verify$ru verify =
      _Translations$historySurgery$verify$ru._(_root);
  @override
  late final _Translations$historySurgery$forcePush$ru forcePush =
      _Translations$historySurgery$forcePush$ru._(_root);
}

// Path: onboarding
class _Translations$onboarding$ru extends Translations$onboarding$en {
  _Translations$onboarding$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$nav$ru nav =
      _Translations$onboarding$nav$ru._(_root);
  @override
  late final _Translations$onboarding$naming$ru naming =
      _Translations$onboarding$naming$ru._(_root);
  @override
  late final _Translations$onboarding$theme$ru theme =
      _Translations$onboarding$theme$ru._(_root);
  @override
  late final _Translations$onboarding$repo$ru repo =
      _Translations$onboarding$repo$ru._(_root);
  @override
  late final _Translations$onboarding$preview$ru preview =
      _Translations$onboarding$preview$ru._(_root);
}

// Path: orrery
class _Translations$orrery$ru extends Translations$orrery$en {
  _Translations$orrery$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$orrery$header$ru header =
      _Translations$orrery$header$ru._(_root);
  @override
  late final _Translations$orrery$status$ru status =
      _Translations$orrery$status$ru._(_root);
  @override
  late final _Translations$orrery$legend$ru legend =
      _Translations$orrery$legend$ru._(_root);
  @override
  late final _Translations$orrery$node$ru node = _Translations$orrery$node$ru._(
    _root,
  );
  @override
  late final _Translations$orrery$milestone$ru milestone =
      _Translations$orrery$milestone$ru._(_root);
  @override
  late final _Translations$orrery$structure$ru structure =
      _Translations$orrery$structure$ru._(_root);
  @override
  late final _Translations$orrery$rail$ru rail = _Translations$orrery$rail$ru._(
    _root,
  );
  @override
  late final _Translations$orrery$selection$ru selection =
      _Translations$orrery$selection$ru._(_root);
  @override
  late final _Translations$orrery$findingKind$ru findingKind =
      _Translations$orrery$findingKind$ru._(_root);
  @override
  late final _Translations$orrery$findings$ru findings =
      _Translations$orrery$findings$ru._(_root);
  @override
  late final _Translations$orrery$anchor$ru anchor =
      _Translations$orrery$anchor$ru._(_root);
  @override
  late final _Translations$orrery$compare$ru compare =
      _Translations$orrery$compare$ru._(_root);
}

// Path: palette
class _Translations$palette$ru extends Translations$palette$en {
  _Translations$palette$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get active => 'активно';
  @override
  late final _Translations$palette$prefixes$ru prefixes =
      _Translations$palette$prefixes$ru._(_root);
  @override
  late final _Translations$palette$chips$ru chips =
      _Translations$palette$chips$ru._(_root);
  @override
  late final _Translations$palette$predictive$ru predictive =
      _Translations$palette$predictive$ru._(_root);
  @override
  late final _Translations$palette$topTouched$ru topTouched =
      _Translations$palette$topTouched$ru._(_root);
  @override
  late final _Translations$palette$coherence$ru coherence =
      _Translations$palette$coherence$ru._(_root);
  @override
  late final _Translations$palette$keystone$ru keystone =
      _Translations$palette$keystone$ru._(_root);
  @override
  late final _Translations$palette$repoSub$ru repoSub =
      _Translations$palette$repoSub$ru._(_root);
  @override
  late final _Translations$palette$desks$ru desks =
      _Translations$palette$desks$ru._(_root);
  @override
  late final _Translations$palette$actions$ru actions =
      _Translations$palette$actions$ru._(_root);
  @override
  late final _Translations$palette$tools$ru tools =
      _Translations$palette$tools$ru._(_root);
  @override
  late final _Translations$palette$gitCommands$ru gitCommands =
      _Translations$palette$gitCommands$ru._(_root);
  @override
  late final _Translations$palette$pr$ru pr = _Translations$palette$pr$ru._(
    _root,
  );
  @override
  late final _Translations$palette$ai$ru ai = _Translations$palette$ai$ru._(
    _root,
  );
  @override
  late final _Translations$palette$undo$ru undo =
      _Translations$palette$undo$ru._(_root);
  @override
  late final _Translations$palette$navigation$ru navigation =
      _Translations$palette$navigation$ru._(_root);
  @override
  late final _Translations$palette$settings$ru settings =
      _Translations$palette$settings$ru._(_root);
  @override
  late final _Translations$palette$info$ru info =
      _Translations$palette$info$ru._(_root);
  @override
  late final _Translations$palette$debug$ru debug =
      _Translations$palette$debug$ru._(_root);
  @override
  late final _Translations$palette$dev$ru dev = _Translations$palette$dev$ru._(
    _root,
  );
  @override
  late final _Translations$palette$historySurgery$ru historySurgery =
      _Translations$palette$historySurgery$ru._(_root);
  @override
  late final _Translations$palette$orrery$ru orrery =
      _Translations$palette$orrery$ru._(_root);
  @override
  late final _Translations$palette$command$ru command =
      _Translations$palette$command$ru._(_root);
  @override
  late final _Translations$palette$search$ru search =
      _Translations$palette$search$ru._(_root);
  @override
  late final _Translations$palette$wick$ru wick =
      _Translations$palette$wick$ru._(_root);
  @override
  late final _Translations$palette$gitCache$ru gitCache =
      _Translations$palette$gitCache$ru._(_root);
}

// Path: releaseNotes
class _Translations$releaseNotes$ru extends Translations$releaseNotes$en {
  _Translations$releaseNotes$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get versionFallback => 'dev';
  @override
  late final _Translations$releaseNotes$about$ru about =
      _Translations$releaseNotes$about$ru._(_root);
  @override
  late final _Translations$releaseNotes$legal$ru legal =
      _Translations$releaseNotes$legal$ru._(_root);
}

// Path: repoSummary
class _Translations$repoSummary$ru extends Translations$repoSummary$en {
  _Translations$repoSummary$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$repoSummary$backbone$ru backbone =
      _Translations$repoSummary$backbone$ru._(_root);
  @override
  late final _Translations$repoSummary$glance$ru glance =
      _Translations$repoSummary$glance$ru._(_root);
  @override
  late final _Translations$repoSummary$heading$ru heading =
      _Translations$repoSummary$heading$ru._(_root);
  @override
  String get historyStarvedCaveat =>
      'Ранжирование ограничено: в графе связности не было рёбер (свежий клон или слишком мало коммитов). Порядок файлов отражает размер, а не структурную центральность.';
  @override
  late final _Translations$repoSummary$pitch$ru pitch =
      _Translations$repoSummary$pitch$ru._(_root);
  @override
  late final _Translations$repoSummary$region$ru region =
      _Translations$repoSummary$region$ru._(_root);
  @override
  late final _Translations$repoSummary$shape$ru shape =
      _Translations$repoSummary$shape$ru._(_root);
}

// Path: review
class _Translations$review$ru extends Translations$review$en {
  _Translations$review$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get unresolved => 'не решено';
  @override
  String get done => 'готово';
  @override
  String get ack => 'принято';
  @override
  String get reply => 'ответить';
  @override
  String get pleaseFix => 'нужно исправить';
  @override
  String get draft => 'черновик';
  @override
  String get engine => 'движок';
  @override
  String get moved => 'перемещено';
  @override
  String get yourTurn => 'ваш ход';
  @override
  String get drafts => 'черновики';
  @override
  String get publish => 'опубликовать';
  @override
  String get discard => 'отбросить';
  @override
  String get saveDraft => 'сохранить черновик';
  @override
  String get cancel => 'отмена';
  @override
  String get verdictApprove => 'одобрить';
  @override
  String get verdictRequestChanges => 'запросить правки';
  @override
  String get verdictComment => 'комментарий';
  @override
  String get caughtUp => 'актуально';
  @override
  String get sinceLastLook => 'с последнего просмотра';
  @override
  String get fullDiff => 'полный diff';
  @override
  String get commentHint => 'напишите комментарий';
  @override
  String outdatedLastSeen({required Object round}) =>
      'устарело · последний просмотр R${round}';
  @override
  String resolvedByFmt({required Object verb, required Object who}) =>
      '${verb} · ${who}';
  @override
  String waitingOnFmt({required Object who}) => 'ждём ${who}';
  @override
  String roundChip({required Object round}) => 'R${round}';
  @override
  String filesSinceLastLook({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '1 файл с последнего просмотра',
        other: '${n} файлов с последнего просмотра',
      );
  @override
  String unresolvedCountFmt({required Object n}) => '${n} не решено';
  @override
  String draftCountFmt({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '1 черновик',
        other: '${n} черновиков',
      );
  @override
  String startReviewFailed({required Object error}) =>
      'Не удалось начать ревью: ${error}';
  @override
  String get anchorUnavailable =>
      'Эту строку нельзя закрепить — файл слишком большой или недоступен.';
  @override
  String reviewActionFailed({required Object error}) =>
      'Не удалось выполнить действие ревью: ${error}';
  @override
  String get lensTooLarge =>
      'Это сравнение слишком большое, чтобы показать его здесь — остаёмся на полном diff.';
  @override
  String get lensEmpty => 'Между этими снимками ничего не изменилось.';
  @override
  String get reopen => 'переоткрыть';
  @override
  String get notBlocking => 'не ждите меня';
  @override
  String get markReviewed => 'прочитано';
  @override
  String newComments({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '1 новый комментарий',
        other: '${n} новых комментариев',
      );
  @override
  String get handTo => 'передать';
  @override
  String get heading => 'РЕВЬЮ';
  @override
  String get identityNeeded =>
      'Укажите git-идентификацию, чтобы оставлять ревью';
  @override
  String get fileUnreadable =>
      'Этот файл здесь не прочитать — он слишком большой или отсутствует в этом раунде.';
}

// Path: settings
class _Translations$settings$ru extends Translations$settings$en {
  _Translations$settings$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$language$ru language =
      _Translations$settings$language$ru._(_root);
  @override
  late final _Translations$settings$sectionLabels$ru sectionLabels =
      _Translations$settings$sectionLabels$ru._(_root);
  @override
  late final _Translations$settings$errors$ru errors =
      _Translations$settings$errors$ru._(_root);
  @override
  late final _Translations$settings$promptStatus$ru promptStatus =
      _Translations$settings$promptStatus$ru._(_root);
  @override
  late final _Translations$settings$clearData$ru clearData =
      _Translations$settings$clearData$ru._(_root);
  @override
  List<String> get guardrailStageLabels => [
    'Свободно',
    'Сбалансировано',
    'Строго',
    'Параноидально',
  ];
  @override
  late final _Translations$settings$guardrailMacro$ru guardrailMacro =
      _Translations$settings$guardrailMacro$ru._(_root);
  @override
  late final _Translations$settings$guardrails$ru guardrails =
      _Translations$settings$guardrails$ru._(_root);
  @override
  late final _Translations$settings$appearance$ru appearance =
      _Translations$settings$appearance$ru._(_root);
  @override
  late final _Translations$settings$retention$ru retention =
      _Translations$settings$retention$ru._(_root);
  @override
  late final _Translations$settings$navigation$ru navigation =
      _Translations$settings$navigation$ru._(_root);
  @override
  late final _Translations$settings$behaviour$ru behaviour =
      _Translations$settings$behaviour$ru._(_root);
  @override
  late final _Translations$settings$retentionClear$ru retentionClear =
      _Translations$settings$retentionClear$ru._(_root);
  @override
  late final _Translations$settings$channels$ru channels =
      _Translations$settings$channels$ru._(_root);
  @override
  late final _Translations$settings$pollResult$ru pollResult =
      _Translations$settings$pollResult$ru._(_root);
  @override
  late final _Translations$settings$keybindingProfile$ru keybindingProfile =
      _Translations$settings$keybindingProfile$ru._(_root);
  @override
  late final _Translations$settings$apiKeys$ru apiKeys =
      _Translations$settings$apiKeys$ru._(_root);
  @override
  late final _Translations$settings$shortcuts$ru shortcuts =
      _Translations$settings$shortcuts$ru._(_root);
  @override
  late final _Translations$settings$toggles$ru toggles =
      _Translations$settings$toggles$ru._(_root);
  @override
  late final _Translations$settings$diffDiffability$ru diffDiffability =
      _Translations$settings$diffDiffability$ru._(_root);
  @override
  late final _Translations$settings$modelSlots$ru modelSlots =
      _Translations$settings$modelSlots$ru._(_root);
  @override
  late final _Translations$settings$modelPicker$ru modelPicker =
      _Translations$settings$modelPicker$ru._(_root);
  @override
  late final _Translations$settings$aiFeatures$ru aiFeatures =
      _Translations$settings$aiFeatures$ru._(_root);
  @override
  late final _Translations$settings$commitEditor$ru commitEditor =
      _Translations$settings$commitEditor$ru._(_root);
  @override
  late final _Translations$settings$review$ru review =
      _Translations$settings$review$ru._(_root);
  @override
  late final _Translations$settings$museHint$ru museHint =
      _Translations$settings$museHint$ru._(_root);
  @override
  late final _Translations$settings$museEditor$ru museEditor =
      _Translations$settings$museEditor$ru._(_root);
  @override
  late final _Translations$settings$museStage$ru museStage =
      _Translations$settings$museStage$ru._(_root);
  @override
  late final _Translations$settings$lensAxis$ru lensAxis =
      _Translations$settings$lensAxis$ru._(_root);
  @override
  late final _Translations$settings$logosLens$ru logosLens =
      _Translations$settings$logosLens$ru._(_root);
  @override
  late final _Translations$settings$sortGuide$ru sortGuide =
      _Translations$settings$sortGuide$ru._(_root);
  @override
  late final _Translations$settings$piggyback$ru piggyback =
      _Translations$settings$piggyback$ru._(_root);
  @override
  late final _Translations$settings$diffStage$ru diffStage =
      _Translations$settings$diffStage$ru._(_root);
  @override
  late final _Translations$settings$undoScope$ru undoScope =
      _Translations$settings$undoScope$ru._(_root);
  @override
  late final _Translations$settings$undoWindow$ru undoWindow =
      _Translations$settings$undoWindow$ru._(_root);
  @override
  late final _Translations$settings$guardrailPhrase$ru guardrailPhrase =
      _Translations$settings$guardrailPhrase$ru._(_root);
  @override
  late final _Translations$settings$reviewGuideHint$ru reviewGuideHint =
      _Translations$settings$reviewGuideHint$ru._(_root);
  @override
  late final _Translations$settings$commitFormat$ru commitFormat =
      _Translations$settings$commitFormat$ru._(_root);
  @override
  late final _Translations$settings$commitPreview$ru commitPreview =
      _Translations$settings$commitPreview$ru._(_root);
  @override
  late final _Translations$settings$externalTools$ru externalTools =
      _Translations$settings$externalTools$ru._(_root);
  @override
  late final _Translations$settings$apiUsage$ru apiUsage =
      _Translations$settings$apiUsage$ru._(_root);
  @override
  late final _Translations$settings$gitea$ru gitea =
      _Translations$settings$gitea$ru._(_root);
  @override
  late final _Translations$settings$wick$ru wick =
      _Translations$settings$wick$ru._(_root);
  @override
  late final _Translations$settings$integrations$ru integrations =
      _Translations$settings$integrations$ru._(_root);
  @override
  late final _Translations$settings$reduceMotion$ru reduceMotion =
      _Translations$settings$reduceMotion$ru._(_root);
  @override
  late final _Translations$settings$resetQuit$ru resetQuit =
      _Translations$settings$resetQuit$ru._(_root);
  @override
  late final _Translations$settings$diagnostics$ru diagnostics =
      _Translations$settings$diagnostics$ru._(_root);
  @override
  late final _Translations$settings$telemetry$ru telemetry =
      _Translations$settings$telemetry$ru._(_root);
  @override
  late final _Translations$settings$flowEngine$ru flowEngine =
      _Translations$settings$flowEngine$ru._(_root);
  @override
  late final _Translations$settings$museStrands$ru museStrands =
      _Translations$settings$museStrands$ru._(_root);
  @override
  late final _Translations$settings$cliPiggyback$ru cliPiggyback =
      _Translations$settings$cliPiggyback$ru._(_root);
  @override
  late final _Translations$settings$header$ru header =
      _Translations$settings$header$ru._(_root);
  @override
  late final _Translations$settings$diagnosticsPanel$ru diagnosticsPanel =
      _Translations$settings$diagnosticsPanel$ru._(_root);
  @override
  late final _Translations$settings$release$ru release =
      _Translations$settings$release$ru._(_root);
  @override
  late final _Translations$settings$providerStatus$ru providerStatus =
      _Translations$settings$providerStatus$ru._(_root);
  @override
  late final _Translations$settings$meridiem$ru meridiem =
      _Translations$settings$meridiem$ru._(_root);
  @override
  late final _Translations$settings$offenders$ru offenders =
      _Translations$settings$offenders$ru._(_root);
}

// Path: sync
class _Translations$sync$ru extends Translations$sync$en {
  _Translations$sync$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$actions$ru actions =
      _Translations$sync$actions$ru._(_root);
  @override
  late final _Translations$sync$panel$ru panel = _Translations$sync$panel$ru._(
    _root,
  );
  @override
  late final _Translations$sync$forcePush$ru forcePush =
      _Translations$sync$forcePush$ru._(_root);
}

// Path: xray
class _Translations$xray$ru extends Translations$xray$en {
  _Translations$xray$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$board$ru board = _Translations$xray$board$ru._(
    _root,
  );
  @override
  late final _Translations$xray$cadence$ru cadence =
      _Translations$xray$cadence$ru._(_root);
  @override
  late final _Translations$xray$cards$ru cards = _Translations$xray$cards$ru._(
    _root,
  );
  @override
  late final _Translations$xray$cardTitle$ru cardTitle =
      _Translations$xray$cardTitle$ru._(_root);
  @override
  late final _Translations$xray$grain$ru grain = _Translations$xray$grain$ru._(
    _root,
  );
  @override
  late final _Translations$xray$header$ru header =
      _Translations$xray$header$ru._(_root);
  @override
  late final _Translations$xray$hotspot$ru hotspot =
      _Translations$xray$hotspot$ru._(_root);
  @override
  late final _Translations$xray$inspector$ru inspector =
      _Translations$xray$inspector$ru._(_root);
  @override
  late final _Translations$xray$loadingCard$ru loadingCard =
      _Translations$xray$loadingCard$ru._(_root);
  @override
  late final _Translations$xray$metabolism$ru metabolism =
      _Translations$xray$metabolism$ru._(_root);
  @override
  late final _Translations$xray$multi$ru multi = _Translations$xray$multi$ru._(
    _root,
  );
  @override
  late final _Translations$xray$recency$ru recency =
      _Translations$xray$recency$ru._(_root);
  @override
  late final _Translations$xray$rings$ru rings = _Translations$xray$rings$ru._(
    _root,
  );
  @override
  late final _Translations$xray$stats$ru stats = _Translations$xray$stats$ru._(
    _root,
  );
  @override
  late final _Translations$xray$stratumLabel$ru stratumLabel =
      _Translations$xray$stratumLabel$ru._(_root);
  @override
  late final _Translations$xray$summary$ru summary =
      _Translations$xray$summary$ru._(_root);
  @override
  late final _Translations$xray$tabs$ru tabs = _Translations$xray$tabs$ru._(
    _root,
  );
  @override
  late final _Translations$xray$trajectory$ru trajectory =
      _Translations$xray$trajectory$ru._(_root);
  @override
  late final _Translations$xray$verdict$ru verdict =
      _Translations$xray$verdict$ru._(_root);
}

// Path: app.cheatsheet
class _Translations$app$cheatsheet$ru extends Translations$app$cheatsheet$en {
  _Translations$app$cheatsheet$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Клавиатура';
  @override
  String get sectionNavigate => 'навигация';
  @override
  String get sectionStaging => 'индексация';
  @override
  String get sectionBranchesPrs => 'ветки и PR';
  @override
  String get changes => 'Изменения';
  @override
  String get history => 'История';
  @override
  String get branches => 'Ветки';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Переключить (всегда)';
  @override
  String get commandPalette => 'Палитра команд';
  @override
  String get elevatedPalette => 'Расширенная палитра';
  @override
  String get dismiss => 'Закрыть';
  @override
  String get refresh => 'Обновить';
  @override
  String get nextPrevChange => 'След. / пред. изменение';
  @override
  String get toggleLine => 'Переключить строку';
  @override
  String get toggleHunk => 'Переключить ханк';
  @override
  String get toggleFile => 'Переключить файл';
  @override
  String get pinContext => 'Закрепить контекст';
  @override
  String get commit => 'Коммит';
  @override
  String get acceptAiHint => 'Принять подсказку AI';
  @override
  String get undo => 'Отменить';
  @override
  String get navigate => 'Навигация';
  @override
  String get expand => 'Развернуть';
  @override
  String get checkoutPr => 'Checkout PR';
  @override
  String get approve => 'Одобрить';
  @override
  String get requestChanges => 'Запросить правки';
  @override
  String profileSwitchHint({required Object profile}) =>
      'профиль ${profile} · сменить в «Настройках»';
}

// Path: backend.ops
class _Translations$backend$ops$ru extends Translations$backend$ops$en {
  _Translations$backend$ops$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'Мёрж';
  @override
  String get pull => 'Пул';
  @override
  String get apply => 'Применить';
  @override
  String get switchOp => 'Переключить';
  @override
  String get sync => 'Синхр.';
}

// Path: backend.mergeOutcome
class _Translations$backend$mergeOutcome$ru
    extends Translations$backend$mergeOutcome$en {
  _Translations$backend$mergeOutcome$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String cancelled({required Object op}) => '${op} — отменено.';
  @override
  String complete({required Object op}) => '${op} — завершено.';
  @override
  String conflictsLeft({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
    n,
    one: 'Остался ${n} конфликт — устраните его на странице «Изменения».',
    few: 'Осталось ${n} конфликта — устраните их на странице «Изменения».',
    many: 'Осталось ${n} конфликтов — устраните их на странице «Изменения».',
    other: 'Осталось ${n} конфликтов — устраните их на странице «Изменения».',
  );
  @override
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'Устранён ${n} конфликт.',
        few: 'Устранено ${n} конфликта.',
        many: 'Устранено ${n} конфликтов.',
        other: 'Устранено ${n} конфликтов.',
      );
  @override
  String uncommittedEdits({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
    n,
    one: 'В ${n} файле есть незакоммиченные правки — сначала создайте коммит.',
    few: 'В ${n} файлах есть незакоммиченные правки — сначала создайте коммит.',
    many:
        'В ${n} файлах есть незакоммиченные правки — сначала создайте коммит.',
    other:
        'В ${n} файлах есть незакоммиченные правки — сначала создайте коммит.',
  );
}

// Path: changes.usage
class _Translations$changes$usage$ru extends Translations$changes$usage$en {
  _Translations$changes$usage$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String caption({required Object input, required Object output}) =>
      '${input} вход · ${output} выход';
  @override
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '${fresh} вход · ${cached} из кэша · ${out} выход';
  @override
  String get inWord => 'вход';
  @override
  String get cachedWord => 'из кэша';
  @override
  String get outWord => 'выход';
  @override
  String tipIn({required Object value}) => '${value}  вход';
  @override
  String tipCacheRead({required Object value}) => '${value}  чтение кэша';
  @override
  String tipCacheWrite({required Object value}) => '${value}  запись кэша';
  @override
  String tipOut({required Object value}) => '${value}  выход';
  @override
  String tipReasoning({required Object value}) => '${value}  рассуждение';
  @override
  String tipWallClock({required Object value}) => '${value} с  реальное время';
}

// Path: changes.tabs
class _Translations$changes$tabs$ru extends Translations$changes$tabs$en {
  _Translations$changes$tabs$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get defaultLabel => 'Изменения';
  @override
  String get empty => 'Пусто';
}

// Path: changes.tabStrip
class _Translations$changes$tabStrip$ru
    extends Translations$changes$tabStrip$en {
  _Translations$changes$tabStrip$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get newDiffTab => 'Новая вкладка diff';
}

// Path: changes.select
class _Translations$changes$select$ru extends Translations$changes$select$en {
  _Translations$changes$select$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get selectAll => 'Выбрать всё';
  @override
  String get deselectAll => 'Снять выбор';
}

// Path: changes.constellationToggle
class _Translations$changes$constellationToggle$ru
    extends Translations$changes$constellationToggle$en {
  _Translations$changes$constellationToggle$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get backToList => 'назад к списку';
  @override
  String get atlas => 'атлас, смотреть кандидатов на коммит';
}

// Path: changes.nudgeChip
class _Translations$changes$nudgeChip$ru
    extends Translations$changes$nudgeChip$en {
  _Translations$changes$nudgeChip$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\nсвязан с ${anchor} · ${pct}%${receipts}';
}

// Path: changes.minimap
class _Translations$changes$minimap$ru extends Translations$changes$minimap$en {
  _Translations$changes$minimap$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get roleNew => 'новый';
  @override
  String get roleBridge => 'мост';
  @override
  String get roleHub => 'узел';
  @override
  String get roleLeaf => 'лист';
  @override
  String get roleConnected => 'связан';
  @override
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';
  @override
  String changesWith({required Object name}) => 'меняется с ${name}';
  @override
  String get newFile => 'новый файл';
  @override
  String nearOtherChanges({required Object count, required Object dir}) =>
      'рядом с ${count} другими изменениями в ${dir}';
  @override
  String usuallyChangesWithFile({required Object name}) =>
      '${name} обычно меняется вместе с этим файлом';
}

// Path: changes.tagInput
class _Translations$changes$tagInput$ru
    extends Translations$changes$tagInput$en {
  _Translations$changes$tagInput$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get hint => 'метка...';
}

// Path: changes.composer
class _Translations$changes$composer$ru
    extends Translations$changes$composer$en {
  _Translations$changes$composer$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get hintPlaceholder => 'сообщение коммита...';
  @override
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class _Translations$changes$commit$ru extends Translations$changes$commit$en {
  _Translations$changes$commit$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get primaryCommitChanges => 'Закоммитить изменения';
  @override
  String get primaryCommitChangesDetail =>
      'Отсоединённый HEAD: коммит локально без синхронизации.';
  @override
  String get primaryPublish => 'Коммит и публикация';
  @override
  String get primaryPublishDetail =>
      'Создать коммит и опубликовать эту ветку за один шаг.';
  @override
  String get primarySync => 'Коммит и синхронизация';
  @override
  String get primarySyncDetail =>
      'Создать коммит, затем согласовать и отправить ветку.';
  @override
  String get primaryPush => 'Коммит и отправка';
  @override
  String get primaryPushDetail => 'Создать коммит и сразу его отправить.';
  @override
  String get amendLast => 'Дополнить последний коммит';
  @override
  String amendAnd({required Object action}) => 'Дополнить и ${action}';
  @override
  String get chooseFile => 'Выберите хотя бы один файл для следующего коммита.';
  @override
  String get writeMessage => 'Сначала напишите сообщение коммита.';
  @override
  String get committing => 'Коммичу';
  @override
  String get committingSync => 'Коммичу и синхронизирую';
  @override
  String get committed => 'Закоммичено.';
  @override
  String get undoFailed => 'Не удалось отменить.';
  @override
  String get working => 'Работаю…';
  @override
  String get commitOnly => 'Только коммит';
  @override
  String get noRuntimeModels =>
      'Для сообщений коммитов нет обнаруженных в рантайме моделей.';
  @override
  String restoreFailedRetry({required Object err}) =>
      '${err}\nНе удалось восстановить индексацию исключённых файлов; проверьте индекс перед повтором.';
  @override
  String committedSummary({required Object summary, required Object hash}) =>
      'Закоммичено ${summary} (${hash}).';
  @override
  String get restoreFailedSync =>
      'Не удалось переиндексировать выборки исключённых файлов; синхронизация пропущена. Проверьте индекс перед синхронизацией.';
  @override
  String get noModelLabel => 'Нет модели';
  @override
  String get chooseBeforeGenerate =>
      'Выберите хотя бы один файл перед генерацией.';
  @override
  String get aiUnavailable => 'AI для сообщений коммитов пока недоступен.';
  @override
  String get generateFailed => 'Не удалось сгенерировать.';
  @override
  String get stageFailed => 'Не удалось проиндексировать файлы.';
  @override
  String get commitFailed => 'Не удалось создать коммит.';
  @override
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => 'Закоммичено ${summary} (${hash}) и выполнено ${operation}.';
  @override
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
    n,
    one: 'Закоммичено ${summary} (${hash}); устранён ${n} конфликт.',
    few: 'Закоммичено ${summary} (${hash}); устранено ${n} конфликта.',
    many: 'Закоммичено ${summary} (${hash}); устранено ${n} конфликтов.',
    other: 'Закоммичено ${summary} (${hash}); устранено ${n} конфликтов.',
  );
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'Осталось устранить ${n} конфликт.',
        few: 'Осталось устранить ${n} конфликта.',
        many: 'Осталось устранить ${n} конфликтов.',
        other: 'Осталось устранить ${n} конфликтов.',
      );
  @override
  String syncBlocked({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
    n,
    one:
        'Коммит удался, но синхронизацию заблокировал ${n} незакоммиченный файл.',
    few:
        'Коммит удался, но синхронизацию заблокировали ${n} незакоммиченных файла.',
    many:
        'Коммит удался, но синхронизацию заблокировали ${n} незакоммиченных файлов.',
    other:
        'Коммит удался, но синхронизацию заблокировали ${n} незакоммиченных файлов.',
  );
  @override
  String syncStalled({required Object message}) =>
      'Коммит удался, но синхронизация застопорилась: ${message}';
  @override
  String syncFailed({required Object message}) =>
      'Коммит удался, но синхронизация не удалась: ${message}';
}

// Path: changes.rebase
class _Translations$changes$rebase$ru extends Translations$changes$rebase$en {
  _Translations$changes$rebase$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get continueFailed => 'Не удалось продолжить rebase.';
}

// Path: changes.editor
class _Translations$changes$editor$ru extends Translations$changes$editor$en {
  _Translations$changes$editor$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get closeBarrier => 'Закрыть редактор';
}

// Path: changes.editorTitles
class _Translations$changes$editorTitles$ru
    extends Translations$changes$editorTitles$en {
  _Translations$changes$editorTitles$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  List<String> get any => [
    'дорогой git log',
    'прости меня, git, ибо я согрешил…',
    'назовите этот момент',
    'болтай',
    'говори!',
    'твоя мать была висячей ссылкой, а отец пах точками с запятой',
  ];
  @override
  List<String> get short => [
    'о?',
    'привет:)',
    'кстати:',
    'пара слов',
    'вежливая версия',
    'оставьте записку',
    'вы говорили..?',
    'ну давай, выкладывай',
  ];
  @override
  List<String> get mid => [
    'для протокола',
    'расскажите себе будущему',
    'но сначала?',
    'как всё прошло',
    'своими словами',
    'ты сделал ЧТО?',
    'принято к сведению',
    'я весь внимание',
  ];
  @override
  List<String> get long => [
    'ваши мечты, пожалуйста',
    'скажите что-нибудь приятное',
    '…и тогда я сказал:',
    'потомки ждут',
    'чем больше пишешь, тем больше багов исчезает',
    'ого',
    'священные тексты',
  ];
}

// Path: changes.askHint
class _Translations$changes$askHint$ru extends Translations$changes$askHint$en {
  _Translations$changes$askHint$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String round({required Object n}) =>
      'раунд ${n} — уточните или добавьте контекст.';
  @override
  String get symptom => 'опишите симптом.';
  @override
  String get broken => 'что сломалось?';
  @override
  String get bug => 'опишите баг.';
  @override
  String get error => 'вставьте ошибку.';
}

// Path: changes.fileMenu
class _Translations$changes$fileMenu$ru
    extends Translations$changes$fileMenu$en {
  _Translations$changes$fileMenu$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get ripple => 'Рябь';
  @override
  String get includeCoChanges => 'Включить совместные изменения';
  @override
  String deleteFile({required Object name}) => 'Удалить ${name}…';
  @override
  String discardChangesTo({required Object name}) =>
      'Отбросить изменения в ${name}…';
  @override
  String get ignore => 'Игнорировать';
  @override
  String get diffTabFromSelection => 'Вкладка diff из выбора';
  @override
  String addSelectedToTab({required Object name}) =>
      'Добавить выбранное в ${name}';
  @override
  String diffTabFromFile({required Object name}) => 'Вкладка diff из ${name}';
  @override
  String addFileToTab({required Object file, required Object tab}) =>
      'Добавить ${file} в ${tab}';
  @override
  String get copyFilePath => 'Копировать путь файла';
  @override
  String get showInExplorer => 'Показать в проводнике';
}

// Path: changes.multiFileMenu
class _Translations$changes$multiFileMenu$ru
    extends Translations$changes$multiFileMenu$en {
  _Translations$changes$multiFileMenu$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get cohesionTight => 'тесно связаны';
  @override
  String get cohesionLoose => 'слабо связаны';
  @override
  String get cohesionScattered => 'структурно разрознены';
  @override
  String get clusterOne => 'всё в одном кластере';
  @override
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      'охватывает ${count} кластеров (${parts} файлов)';
  @override
  String clusterSpans({required Object count}) =>
      'охватывает ${count} кластеров';
  @override
  String roleLine({required Object count, required Object cohesion}) =>
      '${count} файлов · ${cohesion}';
  @override
  String usuallyChangesWithGroup({required Object file}) =>
      '${file} обычно меняется вместе с этой группой';
  @override
  String get splitToNewTab => 'Вынести в новую вкладку';
  @override
  String copyPaths({required Object count}) => 'Копировать ${count} путей';
}

// Path: changes.ignoreMenu
class _Translations$changes$ignoreMenu$ru
    extends Translations$changes$ignoreMenu$en {
  _Translations$changes$ignoreMenu$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String extension({required Object ext}) => 'расширение .${ext}';
  @override
  String allSelected({required Object count}) => 'Все ${count} выбранных';
  @override
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'Связан с ${n} включённым файлом',
        few: 'Связан с ${n} включёнными файлами',
        many: 'Связан с ${n} включёнными файлами',
        other: 'Связан с ${n} включёнными файлами',
      );
  @override
  String get updateFailed => 'Не удалось обновить .gitignore.';
}

// Path: changes.discard
class _Translations$changes$discard$ru extends Translations$changes$discard$en {
  _Translations$changes$discard$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String deleteTitle({required Object name}) => 'Удалить ${name}?';
  @override
  String discardTitle({required Object name}) =>
      'Отбросить изменения в ${name}?';
  @override
  String deleteBody({required Object path}) =>
      '${path} будет удалён с диска. Это нельзя отменить из приложения.';
  @override
  String discardBody({required Object path}) =>
      'Все изменения в ${path} будут возвращены к состоянию в HEAD. Это нельзя отменить.';
  @override
  String get discard => 'Отбросить';
  @override
  String deletingFile({required Object name}) => 'Удаляю ${name}';
  @override
  String discardingFile({required Object name}) => 'Отбрасываю ${name}';
  @override
  String get discardFailed => 'Не удалось отбросить изменения.';
  @override
  String discardManyTitle({required Object count}) =>
      'Отбросить изменения в ${count} файлах?';
  @override
  String get discardManyBody =>
      'Отслеживаемые файлы вернутся к состоянию в HEAD; неотслеживаемые будут удалены с диска. Это нельзя отменить.';
  @override
  String discardManyConfirm({required Object count}) => 'Отбросить ${count}';
  @override
  String discardingManyFiles({required Object count}) =>
      'Отбрасываю ${count} файлов';
  @override
  String failedOpenExplorer({required Object error}) =>
      'Не удалось открыть проводник: ${error}';
  @override
  String get someFailed => 'Некоторые отбрасывания не удались.';
}

// Path: changes.snack
class _Translations$changes$snack$ru extends Translations$changes$snack$en {
  _Translations$changes$snack$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get sameWorktree => 'Тот же рабочий каталог — сбрасывать нечего.';
  @override
  String diffFailed({required Object error}) => 'Сбой diff: ${error}';
  @override
  String get deskEmpty => 'У Desk нет ничего впереди вас — пустой сброс.';
  @override
  String sourceDesk({required Object label}) => 'Desk ${label}';
  @override
  String shelfReadFailed({required Object error}) =>
      'Не удалось прочитать полку: ${error}';
  @override
  String get shelfEmpty => 'Пустая полка — сбрасывать нечего.';
  @override
  String sourceShelf({required Object label}) => 'полка ${label}';
  @override
  String noModelConfigured({required Object label}) =>
      'Для «${label}» модель не настроена.';
  @override
  String fetchFailed({required Object error}) => 'Сбой фетча: ${error}';
}

// Path: changes.trace
class _Translations$changes$trace$ru extends Translations$changes$trace$en {
  _Translations$changes$trace$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'След верификации';
  @override
  String get draftReview => 'Черновое ревью';
}

// Path: changes.cleanTree
class _Translations$changes$cleanTree$ru
    extends Translations$changes$cleanTree$en {
  _Translations$changes$cleanTree$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Рабочий каталог чист';
  @override
  String get subtitle => 'Изменений в индексе и вне него не обнаружено.';
  @override
  String get noUpstream => '  ·  нет upstream';
  @override
  String get ahead => ' впереди';
  @override
  String get behind => ' позади';
  @override
  String get refreshing => 'Обновление...';
  @override
  String get refresh => 'Обновить';
  @override
  String get check => 'проверить';
  @override
  String get checkTooltip => 'Зафетчить и локально обновить.';
  @override
  String get sync => '& синхр';
}

// Path: changes.guardrail
class _Translations$changes$guardrail$ru
    extends Translations$changes$guardrail$en {
  _Translations$changes$guardrail$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'Свободно';
  @override
  String get balanced => 'Сбалансировано';
  @override
  String get strict => 'Строго';
  @override
  String get paranoid => 'Параноидально';
}

// Path: changes.dropHint
class _Translations$changes$dropHint$ru
    extends Translations$changes$dropHint$en {
  _Translations$changes$dropHint$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get fromShelf => 'бросьте, чтобы принести изменения с этой полки сюда';
  @override
  String get fromDesk => 'бросьте, чтобы принести изменения с этого Desk сюда';
}

// Path: changes.diffEmpty
class _Translations$changes$diffEmpty$ru
    extends Translations$changes$diffEmpty$en {
  _Translations$changes$diffEmpty$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Файл не выбран';
  @override
  String get message => 'Выберите изменённый файл, чтобы изучить его diff.';
}

// Path: changes.shelvePill
class _Translations$changes$shelvePill$ru
    extends Translations$changes$shelvePill$en {
  _Translations$changes$shelvePill$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String shelveN({required Object count}) => '↓ отложить ${count}';
  @override
  String get shelve => '↓ отложить';
  @override
  String shelvedCount({required Object count, required Object glyph}) =>
      '${count} отложено ${glyph}';
}

// Path: changes.stashAction
class _Translations$changes$stashAction$ru
    extends Translations$changes$stashAction$en {
  _Translations$changes$stashAction$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get pickUp => 'взять';
  @override
  String get peek => 'заглянуть';
  @override
  String get toss => 'выбросить';
}

// Path: changes.stashContents
class _Translations$changes$stashContents$ru
    extends Translations$changes$stashContents$en {
  _Translations$changes$stashContents$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get reading => 'читаю полку…';
  @override
  String get empty => 'пустая полка';
}

// Path: changes.stashFile
class _Translations$changes$stashFile$ru
    extends Translations$changes$stashFile$en {
  _Translations$changes$stashFile$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get binary => 'бин';
}

// Path: changes.fileRow
class _Translations$changes$fileRow$ru extends Translations$changes$fileRow$en {
  _Translations$changes$fileRow$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get stagedLinesOnly => 'коммитит только строки из индекса';
  @override
  String get doubleClickToggle => 'двойной клик: переключить всю группу';
  @override
  String get repoRoot => 'Корень репозитория';
}

// Path: changes.resolveStrip
class _Translations$changes$resolveStrip$ru
    extends Translations$changes$resolveStrip$en {
  _Translations$changes$resolveStrip$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'читаю ${n} файл · черновик решения…',
        few: 'читаю ${n} файла · черновик решения…',
        many: 'читаю ${n} файлов · черновик решения…',
        other: 'читаю ${n} файлов · черновик решения…',
      );
  @override
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} конфликт в ${files}',
        few: '${n} конфликта в ${files}',
        many: '${n} конфликтов в ${files}',
        other: '${n} конфликтов в ${files}',
      );
  @override
  String get resolve => 'Устранить';
  @override
  String get orWith => 'ИЛИ С';
  @override
  String resolveWith({required Object label}) => 'устранить с ${label}';
  @override
  String resolveWithModel({required Object label, required Object model}) =>
      'устранить с ${label}  ·  ${model}';
  @override
  String get resolving => 'устраняю…';
  @override
  String resolveWithGlyph({required Object label}) => '↵  устранить с ${label}';
  @override
  String get orWithAnother => 'или с другой моделью';
}

// Path: changes.badge
class _Translations$changes$badge$ru extends Translations$changes$badge$en {
  _Translations$changes$badge$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get stagedEdit => 'Правка в индексе';
  @override
  String get edited => 'Изменён';
  @override
  String get stagedAdd => 'Добавление в индексе';
  @override
  String get added => 'Добавлен';
  @override
  String get stagedDelete => 'Удаление в индексе';
  @override
  String get deleted => 'Удалён';
  @override
  String get stagedRename => 'Переименование в индексе';
  @override
  String get renamed => 'Переименован';
  @override
  String get stagedCopy => 'Копия в индексе';
  @override
  String get copied => 'Скопирован';
  @override
  String get conflict => 'Конфликт';
  @override
  String get stagedTypeChange => 'Смена типа в индексе';
  @override
  String get typeChanged => 'Тип изменён';
  @override
  String get untracked => 'Не отслеживается';
}

// Path: changes.review
class _Translations$changes$review$ru extends Translations$changes$review$en {
  _Translations$changes$review$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Ревью кода';
  @override
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} включённый файл',
        few: '${n} включённых файла',
        many: '${n} включённых файлов',
        other: '${n} включённых файлов',
      );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} ханк',
        few: '${n} ханка',
        many: '${n} ханков',
        other: '${n} ханков',
      );
  @override
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';
  @override
  String get unavailable => 'Ревью недоступно';
  @override
  String get backToDiff => 'Назад к diff';
  @override
  String get verified => 'Проверено';
  @override
  String get draftOnly => 'Только черновик';
  @override
  String get runAgain => 'Запустить снова';
  @override
  String draftShownBelow({required Object error}) =>
      '${error} Черновое ревью показано ниже.';
  @override
  String get hideTrace => 'Скрыть след';
  @override
  String get showTrace => 'Показать след';
  @override
  String get showVerificationTrace => 'Показать след верификации';
  @override
  String get whyLanded => 'Почему это ревью пришло сюда';
  @override
  String get noFindings => 'Находок нет';
  @override
  String get findings => 'Находки';
  @override
  String get noEvidenceIssues =>
      'Для этого объёма коммита не всплыло проблем, подкреплённых доказательствами.';
  @override
  String get observations => 'Наблюдения';
  @override
  String get chooseBeforeReview => 'Выберите хотя бы один файл перед ревью.';
  @override
  String get aiUnavailable => 'AI-ревью пока недоступно.';
  @override
  String get failed => 'Сбой ревью.';
  @override
  String get noRuntimeModels =>
      'Для ревью коммитов нет обнаруженных в рантайме моделей.';
}

// Path: changes.commitBtn
class _Translations$changes$commitBtn$ru
    extends Translations$changes$commitBtn$en {
  _Translations$changes$commitBtn$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String switchTo({required Object label}) => 'Переключить на: ${label}\n';
}

// Path: changes.shapeBtn
class _Translations$changes$shapeBtn$ru
    extends Translations$changes$shapeBtn$en {
  _Translations$changes$shapeBtn$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String askingWith({required Object cat}) => 'спрашиваю через ${cat}…';
  @override
  String askWith({required Object cat}) => 'спросить через ${cat}';
  @override
  String get noModel => 'AI-модель не настроена';
  @override
  String nextTooltip({required Object cat}) =>
      'далее: ${cat}  ·  shift-клик для предыдущего';
  @override
  String get onlyOne => 'настроена лишь одна AI-категория';
}

// Path: changes.dejaVu
class _Translations$changes$dejaVu$ru extends Translations$changes$dejaVu$en {
  _Translations$changes$dejaVu$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required num n,
    required Object pct,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
    n,
    one:
        '${pct}% дежавю — ${n} призрачное ребро из отброшенных временных линий задевает этот diff',
    few:
        '${pct}% дежавю — ${n} призрачных ребра из отброшенных временных линий задевают этот diff',
    many:
        '${pct}% дежавю — ${n} призрачных рёбер из отброшенных временных линий задевают этот diff',
    other:
        '${pct}% дежавю — ${n} призрачных рёбер из отброшенных временных линий задевают этот diff',
  );
  @override
  String get label => 'дежавю';
}

// Path: changes.identity
class _Translations$changes$identity$ru
    extends Translations$changes$identity$en {
  _Translations$changes$identity$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'личность для коммита не настроена';
  @override
  String asName({required Object name}) => 'как ${name}';
  @override
  String asNameEmail({required Object name, required Object email}) =>
      'как ${name} <${email}>';
  @override
  String asNameSpace({required Object name}) => 'как ${name} ';
  @override
  String emailAngle({required Object email}) => '<${email}>';
  @override
  String get firstCommit => '\nпервый коммит в этом репозитории';
  @override
  String get newToRepo => '\nновичок в этом репозитории';
}

// Path: changes.staleScope
class _Translations$changes$staleScope$ru
    extends Translations$changes$staleScope$en {
  _Translations$changes$staleScope$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get message => 'выбор изменился с момента запуска';
  @override
  String get rerun => 'перезапустить';
}

// Path: changes.finding
class _Translations$changes$finding$ru extends Translations$changes$finding$en {
  _Translations$changes$finding$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get openDiff => 'Открыть diff';
  @override
  String get recorded => 'записано';
  @override
  String get dismiss => 'Отклонить';
}

// Path: changes.muse
class _Translations$changes$muse$ru extends Translations$changes$muse$en {
  _Translations$changes$muse$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Muse';
  @override
  String get youPulledThis => 'вы вытянули это';
  @override
  String fromIdea({required Object text}) => 'из идеи: «${text}»';
  @override
  String get foothold => 'опора — ';
  @override
  String get brainstormSpew => 'поток мозгового штурма';
  @override
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';
  @override
  String copyN({required Object count}) => 'Копировать ${count}';
  @override
  String get clear => 'Очистить';
  @override
  String get chooseBeforeMuse =>
      'Выберите хотя бы один файл перед вызовом музы.';
  @override
  String get aiUnavailable => 'AI для Muse пока недоступен.';
  @override
  String get failed => 'Сбой Muse.';
  @override
  String get noRuntimeModels => 'Для музы нет обнаруженных в рантайме моделей.';
  @override
  String get needsModel => 'Музе нужна хотя бы одна настроенная модель.';
  @override
  String get dreaming => 'муза грезит...';
}

// Path: changes.debug
class _Translations$changes$debug$ru extends Translations$changes$debug$en {
  _Translations$changes$debug$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Отладка';
  @override
  String round({required Object n}) => '· раунд ${n}';
  @override
  String get clear => 'очистить';
  @override
  String get close => 'закрыть';
  @override
  String get analyzing => 'анализирую симптом…';
  @override
  String get describeSymptom => 'опишите симптом, затем нажмите «отладка».';
  @override
  String get evidenceFor => 'за';
  @override
  String get evidenceAgainst => 'но';
  @override
  String get narrowDown => 'что помогло бы сузить круг:';
  @override
  String get failed => 'Сбой отладки.';
  @override
  String get refinementFailed => 'Не удалось уточнить отладку.';
}

// Path: changes.includeSummary
class _Translations$changes$includeSummary$ru
    extends Translations$changes$includeSummary$en {
  _Translations$changes$includeSummary$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'Ничего';
  @override
  String stagedSuffix({required Object count}) => ' · ${count} в индексе';
  @override
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'Все ${n} файл${staged}',
        few: 'Все ${n} файла${staged}',
        many: 'Все ${n} файлов${staged}',
        other: 'Все ${n} файлов${staged}',
      );
  @override
  String partial({
    required Object count,
    required Object n,
    required Object staged,
  }) => '${count} из ${n}${staged}';
  @override
  String shortAll({required Object n, required Object staged}) =>
      'Все ${n}${staged}';
}

// Path: changes.status
class _Translations$changes$status$ru extends Translations$changes$status$en {
  _Translations$changes$status$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get unavailableTitle => 'Статус репозитория недоступен';
  @override
  String get loadingTitle => 'Загрузка статуса репозитория';
  @override
  String get loadingMessage => 'Читаю рабочий каталог.';
}

// Path: changes.stash
class _Translations$changes$stash$ru extends Translations$changes$stash$en {
  _Translations$changes$stash$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get appliedWithConflicts =>
      'Стэш применён с конфликтами — устраните их на странице «Изменения» (запись стэша сохранена).';
  @override
  String get couldNotPop => 'Не удалось извлечь стэш.';
  @override
  String get listChanged =>
      'Список стэшей изменился; сброс пропущен. Попробуйте снова.';
  @override
  String get droppingStash => 'Сбрасываю стэш';
}

// Path: changes.tooltips
class _Translations$changes$tooltips$ru
    extends Translations$changes$tooltips$en {
  _Translations$changes$tooltips$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get commitGenerating => 'генерирую сообщение коммита...';
  @override
  String get commitPreparing => 'готовлю сообщение коммита...';
  @override
  String get commitSelectFile =>
      'выберите хотя бы один файл, чтобы сгенерировать сообщение коммита.';
  @override
  String get commitConfigure =>
      'настройте сообщения коммитов в «Настройки» > «Динамика поведения» > «Сообщения коммитов».';
  @override
  String get fastFallback => 'быстро';
  @override
  String commitGenerateWith({required Object label}) =>
      'сгенерировать сообщение коммита моделью ${label}';
  @override
  String get museConsulting => 'советуюсь с музой...';
  @override
  String get showMuse => 'показать музу';
  @override
  String get museSelectFile => 'выберите хотя бы один файл для музы.';
  @override
  String get showMuseError => 'показать ошибку музы';
  @override
  String get museAsk => 'спросить у музы направление';
  @override
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => 'спросить у музы направление\n${brainstorm} → ${synthesis}';
  @override
  String get qualityFallback => 'качество';
  @override
  String get reviewing => 'делаю ревью...';
  @override
  String get showReview => 'показать ревью';
  @override
  String get reviewPreparing => 'готовлю ревью коммита...';
  @override
  String get reviewSelectFile => 'выберите хотя бы один файл для ревью.';
  @override
  String get reviewConfigure => 'настройте AI-ревью в настройках.';
  @override
  String get viewingReview => 'просмотр ревью';
  @override
  String reviewWith({required Object guardrail, required Object label}) =>
      '${guardrail} ревью моделью ${label}';
}

// Path: changes.mergeEditor
class _Translations$changes$mergeEditor$ru
    extends Translations$changes$mergeEditor$en {
  _Translations$changes$mergeEditor$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get resolutionYours => 'ваши';
  @override
  String get resolutionTheirs => 'их';
  @override
  String get resolutionCustom => 'свой';
  @override
  String get keepBoth => 'оставить оба';
  @override
  late final _Translations$changes$mergeEditor$trust$ru trust =
      _Translations$changes$mergeEditor$trust$ru._(_root);
  @override
  String get allResolved => 'всё устранено';
  @override
  String get resolveEasy => 'устранить простые конфликты';
  @override
  String get base => 'база';
  @override
  String get cancel => 'отмена';
  @override
  String get save => 'сохранить';
  @override
  String get complete => 'завершить';
  @override
  String get nextFile => 'след. файл';
  @override
  String get edit => 'правка';
  @override
  String get auto => 'авто';
  @override
  String get undo => 'отмена';
  @override
  late final _Translations$changes$mergeEditor$keyHints$ru keyHints =
      _Translations$changes$mergeEditor$keyHints$ru._(_root);
  @override
  String get favoredTooltip => 'структурно предпочтён анализом связности';
  @override
  String get newOnBothSides => '(новое с обеих сторон)';
  @override
  String writeFailed({required Object error}) =>
      'Не удалось записать устранённые файлы: ${error}';
  @override
  String neighborsCoChanged({required Object changed, required Object total}) =>
      '${changed}/${total} соседей со-изменились';
  @override
  String integrity({required Object pct}) => 'целостность ${pct}%';
  @override
  String reviewer({required Object name}) => 'ревьюер: ${name}';
}

// Path: changes.conflictResolution
class _Translations$changes$conflictResolution$ru
    extends Translations$changes$conflictResolution$en {
  _Translations$changes$conflictResolution$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String noModelConfigured({required Object category}) =>
      'Для «${category}» модель не настроена. Задайте её в «Настройки» → «AI».';
  @override
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} чувствительный файл пропущен — устраните вручную.',
        few: '${n} чувствительных файла пропущено — устраните вручную.',
        many: '${n} чувствительных файлов пропущено — устраните вручную.',
        other: '${n} чувствительных файлов пропущено — устраните вручную.',
      );
  @override
  String get couldNotReadFiles =>
      'Не удалось прочитать ни один конфликтный файл.';
  @override
  String blockedSecret({required Object secret}) =>
      'Заблокировано — конфликтный файл, похоже, содержит ${secret}. Устраните вручную.';
  @override
  String resolutionFailed({required Object error}) =>
      'Не удалось устранить: ${error}';
  @override
  String mergeResolutionLabel({
    required Object resolved,
    required Object total,
    required Object category,
  }) => '◇ устранение слияния · ${resolved}/${total} файлов · ${category}';
  @override
  String conflictSummary({
    required Object op,
    required Object conflicts,
    required Object files,
  }) => '${op} · ${conflicts} в ${files}';
  @override
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} конфликт',
        few: '${n} конфликта',
        many: '${n} конфликтов',
        other: '${n} конфликтов',
      );
  @override
  String get mergeEditorButton => '⇋ редактор слияния';
  @override
  String get noAiModel => 'нет AI-модели';
  @override
  String get later => 'позже';
  @override
  String get discard => 'отбросить';
  @override
  String get resolveWithAi => '◇ устранить с AI';
  @override
  String get otherModel => 'другая модель';
  @override
  String withModel({required Object model}) => 'с ${model}';
}

// Path: changes.mergeFlow
class _Translations$changes$mergeFlow$ru
    extends Translations$changes$mergeFlow$en {
  _Translations$changes$mergeFlow$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$mergeFlow$op$ru op =
      _Translations$changes$mergeFlow$op$ru._(_root);
  @override
  String get pushFailed => 'Не удалось отправить';
  @override
  String get rebasedAndPushed => 'Сделан rebase и отправлено.';
  @override
  String switchedTo({required Object name}) => 'Переключено на ${name}.';
  @override
  String get switchFailed => 'Не удалось переключить.';
  @override
  String switchedToCarried({required Object name}) =>
      'Переключено на ${name} (изменения перенесены).';
  @override
  String get alreadyUpToDate => 'Уже актуально.';
  @override
  String merged({required Object upstream, required Object n}) =>
      'Слито ${upstream} (${n} файлов).';
  @override
  String get rebaseNotConverge => 'Rebase не сошёлся — устраните вручную.';
  @override
  String get rebased => 'Сделан rebase.';
  @override
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'Сделан rebase (устранён ${n} файл).',
        few: 'Сделан rebase (устранено ${n} файла).',
        many: 'Сделан rebase (устранено ${n} файлов).',
        other: 'Сделан rebase (устранено ${n} файлов).',
      );
  @override
  String get detachedHead =>
      'Синхронизация невозможна: отсоединённый HEAD. Сначала переключитесь на ветку.';
  @override
  String get publishFailed => 'Не удалось опубликовать.';
  @override
  String get noRemote =>
      'Удалённый не настроен. Добавьте один, чтобы опубликовать эту ветку.';
  @override
  String get failed => 'сбой';
}

// Path: changes.constellation
class _Translations$changes$constellation$ru
    extends Translations$changes$constellation$en {
  _Translations$changes$constellation$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get axisStructure => 'СТРУКТУРА';
  @override
  String get axisCoChange => 'СОВМ. ИЗМЕНЕНИЯ';
  @override
  String get axisSpectralProfile => 'СПЕКТРАЛЬНЫЙ ПРОФИЛЬ';
  @override
  String get axisPathSiblings => 'РОДИЧИ ПО ПУТИ';
  @override
  String get axisDiffStructure => 'СТРУКТУРА DIFF';
  @override
  String get axisSpectral => 'СПЕКТРАЛЬНЫЙ';
  @override
  String get titleUnsorted => 'БЕЗ СОРТИРОВКИ';
  @override
  String get titleSingleton => 'ОДИНОЧКА';
  @override
  String get titleMixed => 'СМЕШАННЫЙ';
  @override
  String get untie => 'развязать';
  @override
  String get bind => 'связать';
  @override
  String get emptyClusters => 'пока нет кластеров';
}

// Path: common.time
class _Translations$common$time$ru extends Translations$common$time$en {
  _Translations$common$time$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get now => 'сейчас';
  @override
  String get justNow => 'только что';
  @override
  String get today => 'СЕГОДНЯ';
  @override
  String minutesAgo({required Object n}) => '${n} мин назад';
  @override
  String hoursAgo({required Object n}) => '${n} ч назад';
  @override
  String daysAgo({required Object n}) => '${n} дн назад';
  @override
  String weeksAgo({required Object n}) => '${n} нед назад';
  @override
  String monthsAgo({required Object n}) => '${n} мес назад';
  @override
  String yearsAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} г назад',
        other: '${n} г назад',
      );
  @override
  String minutesShort({required Object n}) => '${n} мин';
  @override
  String hoursShort({required Object n}) => '${n} ч';
  @override
  String daysShort({required Object n}) => '${n} дн';
  @override
  String weeksShort({required Object n}) => '${n} нед';
  @override
  String monthsShort({required Object n}) => '${n} мес';
  @override
  String yearsShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} г',
        other: '${n} г',
      );
  @override
  String commitMonthsShort({required Object n}) => '${n} мес';
  @override
  String get idle => 'простой';
  @override
  String idleDays({required Object n}) => 'простой ${n} дн';
  @override
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'простой ${n} год',
        few: 'простой ${n} года',
        many: 'простой ${n} лет',
        other: 'простой ${n} лет',
      );
  @override
  List<String> get monthAbbrevs => [
    'янв',
    'фев',
    'мар',
    'апр',
    'май',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];
}

// Path: common.size
class _Translations$common$size$ru extends Translations$common$size$en {
  _Translations$common$size$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String bytes({required Object n}) => '${n} Б';
  @override
  String kb({required Object n}) => '${n} КБ';
  @override
  String mb({required Object n}) => '${n} МБ';
  @override
  String gb({required Object n}) => '${n} ГБ';
}

// Path: diff.status
class _Translations$diff$status$ru extends Translations$diff$status$en {
  _Translations$diff$status$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Загрузка diff';
  @override
  String get loadingMessage => 'Читаю изменения файла.';
  @override
  String get unavailableTitle => 'Diff недоступен';
  @override
  String get noChangesTitle => 'Нет изменений';
  @override
  String get noChangesMessage =>
      'У этого файла нет содержимого diff для показа.';
}

// Path: diff.toolbar
class _Translations$diff$toolbar$ru extends Translations$diff$toolbar$en {
  _Translations$diff$toolbar$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get searchHint => 'поиск по diff...';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} строка',
        few: '${n} строки',
        many: '${n} строк',
        other: '${n} строк',
      );
  @override
  String get blameLoading => 'blame...';
  @override
  String get blame => 'blame';
  @override
  String get wearMapOn => 'износ · вкл';
  @override
  String get wearMapOnHint => 'карта износа вкл — нажмите, чтобы скрыть';
  @override
  String get wearMapOffHint =>
      'показать карту износа (тепловая карта активности)';
  @override
  String get trailBadge => '· след';
}

// Path: diff.hunkDropdown
class _Translations$diff$hunkDropdown$ru
    extends Translations$diff$hunkDropdown$en {
  _Translations$diff$hunkDropdown$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip => 'Перейти к блоку изменений. Git называет их ханками.';
  @override
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} изменение',
        few: '${n} изменения',
        many: '${n} изменений',
        other: '${n} изменений',
      );
}

// Path: diff.trail
class _Translations$diff$trail$ru extends Translations$diff$trail$en {
  _Translations$diff$trail$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'загрузка следа...';
  @override
  String get noHistory => 'история не найдена';
  @override
  String get nowWorkingCopy => 'сейчас · рабочая копия';
  @override
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class _Translations$diff$pinned$ru extends Translations$diff$pinned$en {
  _Translations$diff$pinned$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get loadingContext => 'загрузка закреплённого контекста';
  @override
  String get pageManifold => 'Manifold';
  @override
  String get pageSignals => 'Сигналы';
  @override
  String get echoesTitle => 'Отголоски';
  @override
  String get technicalLedger => 'Технический реестр';
  @override
  String get noSecondaryCues => 'Вторичные признаки не обнаружены.';
  @override
  String get linkedPaths => 'Связанные пути';
  @override
  String moreCount({required Object n}) => '+${n} ещё';
  @override
  String get localSeam => 'Локальный шов';
  @override
  String get sharedOwnership => 'совместное владение';
  @override
  String get historyWarmingUp => 'История прогревается';
  @override
  String echoesTotal({required Object n}) => '${n} ВСЕГО';
  @override
  String get noEchoes => 'В этом diff отголосков нет.';
  @override
  String openRelatedFile({required Object name}) =>
      'Открыть связанный файл ${name}';
  @override
  String inspectFile({required Object name}) => 'изучить ${name}';
  @override
  String get jumpEcho => 'к отголоску';
  @override
  String get copyLine => 'копировать строку';
  @override
  String get signalTempo => 'Т';
  @override
  String get signalNovelty => 'Н';
  @override
  String get signalReach => 'О';
  @override
  late final _Translations$diff$pinned$tempo$ru tempo =
      _Translations$diff$pinned$tempo$ru._(_root);
  @override
  late final _Translations$diff$pinned$tone$ru tone =
      _Translations$diff$pinned$tone$ru._(_root);
  @override
  late final _Translations$diff$pinned$summary$ru summary =
      _Translations$diff$pinned$summary$ru._(_root);
  @override
  late final _Translations$diff$pinned$tightness$ru tightness =
      _Translations$diff$pinned$tightness$ru._(_root);
  @override
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept} (${tightness})';
  @override
  String get storyWhyThisMatters => 'Почему это важно';
  @override
  String get storyConfidence => 'Уверенность';
  @override
  String get storySecondarySignal => 'Вторичный сигнал';
  @override
  String get storyNeighbourhood => 'Окрестность';
  @override
  String neighbourhoodDetail({required Object name}) =>
      'Эта строка расположена близко к ${name} в текущем поле кодовой базы.';
  @override
  String get propagationLane => 'Дорожка распространения';
  @override
  String propagationLaneNamed({required Object lane}) =>
      'Дорожка распространения: ${lane}';
  @override
  late final _Translations$diff$pinned$witness$ru witness =
      _Translations$diff$pinned$witness$ru._(_root);
  @override
  late final _Translations$diff$pinned$integrity$ru integrity =
      _Translations$diff$pinned$integrity$ru._(_root);
  @override
  late final _Translations$diff$pinned$related$ru related =
      _Translations$diff$pinned$related$ru._(_root);
  @override
  late final _Translations$diff$pinned$axis$ru axis =
      _Translations$diff$pinned$axis$ru._(_root);
}

// Path: diff.hunkHint
class _Translations$diff$hunkHint$ru extends Translations$diff$hunkHint$en {
  _Translations$diff$hunkHint$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String hiddenCount({required Object n}) => '${n} скрыто';
  @override
  String get landing => 'посадка';
}

// Path: diff.binary
class _Translations$diff$binary$ru extends Translations$diff$binary$en {
  _Translations$diff$binary$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String tooLargeToPreview({required Object size}) =>
      '${size} МБ (слишком велик для превью)';
  @override
  String get unableToLoadBlob => 'Не удалось загрузить blob';
  @override
  String get omittedKindMedia => 'медиа';
  @override
  String get omittedKindBinary => 'бинарный';
  @override
  String omittedStub({required Object kind}) => '${kind} · скрыт';
}

// Path: diff.media
class _Translations$diff$media$ru extends Translations$diff$media$en {
  _Translations$diff$media$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get unableToDecodeImage => 'Не удалось декодировать изображение';
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
  String get stateAdded => 'добавлено';
  @override
  String get stateDeleted => 'удалено';
  @override
  String get stateModified => 'изменено';
  @override
  String get fallbackFormatName => 'Бинарный';
}

// Path: filament.severity
class _Translations$filament$severity$ru
    extends Translations$filament$severity$en {
  _Translations$filament$severity$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get critical => 'критично';
  @override
  String get warn => 'предупр.';
  @override
  String get info => 'инфо';
  @override
  String get joint => 'узел';
}

// Path: filament.kind
class _Translations$filament$kind$ru extends Translations$filament$kind$en {
  _Translations$filament$kind$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get staleValue => 'устаревшее значение';
  @override
  String get temporalShift => 'временной сдвиг';
  @override
  String get contextInversion => 'инверсия контекста';
  @override
  String get contradictoryFlow => 'противоречивый поток';
}

// Path: history.commitLede
class _Translations$history$commitLede$ru
    extends Translations$history$commitLede$en {
  _Translations$history$commitLede$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$semantics$ru semantics =
      _Translations$history$commitLede$semantics$ru._(_root);
}

// Path: history.seismograph
class _Translations$history$seismograph$ru
    extends Translations$history$seismograph$en {
  _Translations$history$seismograph$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get rootTrackLabel => '(корень)';
  @override
  String dirTrackLabel({required Object name}) => '(${name})';
  @override
  String moreLabel({required Object n}) => '+${n} ещё';
  @override
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} файл в ${path}/',
        few: '${n} файла в ${path}/',
        many: '${n} файлов в ${path}/',
        other: '${n} файлов в ${path}/',
      );
  @override
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'ещё ${n} файл',
        few: 'ещё ${n} файла',
        many: 'ещё ${n} файлов',
        other: 'ещё ${n} файлов',
      );
  @override
  String get breadcrumbAll => 'все';
  @override
  String breadcrumbCurrentFocus({required Object target}) =>
      'Текущий фокус: ${target}';
  @override
  String get breadcrumbViewAllChanges =>
      'Показать все изменения в этом коммите';
  @override
  String breadcrumbDrillUpTo({required Object target}) =>
      'Подняться до ${target}';
  @override
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
    n,
    one: '${n} файл  +${adds}  -${dels}',
    few: '${n} файла  +${adds}  -${dels}',
    many: '${n} файлов  +${adds}  -${dels}',
    other: '${n} файлов  +${adds}  -${dels}',
  );
  @override
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} подкаталог',
        few: '${n} подкаталога',
        many: '${n} подкаталогов',
        other: '${n} подкаталогов',
      );
  @override
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}, добавлено ${adds}, удалено ${dels}';
  @override
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
    n,
    one: '${n} файл, добавлено ${adds}, удалено ${dels}',
    few: '${n} файла, добавлено ${adds}, удалено ${dels}',
    many: '${n} файлов, добавлено ${adds}, удалено ${dels}',
    other: '${n} файлов, добавлено ${adds}, удалено ${dels}',
  );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} ханк',
        few: '${n} ханка',
        many: '${n} ханков',
        other: '${n} ханков',
      );
  @override
  String get largestChangeInView => 'крупнейшее изменение в этом виде';
  @override
  String get conflictedTag => 'конфликт';
  @override
  String get dirtyTag => 'грязный';
  @override
  String get drillInTag => 'углубиться';
  @override
  String get changeTypeRenamed => 'переименован';
  @override
  String get changeTypeCopied => 'скопирован';
  @override
  String get changeTypeTypechange => 'смена типа';
  @override
  String get changeTypeConflict => 'конфликт';
  @override
  String get coreFile => 'файл ядра';
  @override
  String get staleFile => 'устаревший';
  @override
  String get filterPathHint => 'фильтр по пути';
  @override
  String get escHint => 'esc';
}

// Path: history.worldline
class _Translations$history$worldline$ru
    extends Translations$history$worldline$en {
  _Translations$history$worldline$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get closeWorldline => 'Закрыть мировую линию';
  @override
  String get dragToOpenWorldline => 'Потяните, чтобы открыть мировую линию';
}

// Path: history.contextMenu
class _Translations$history$contextMenu$ru
    extends Translations$history$contextMenu$en {
  _Translations$history$contextMenu$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get currentBranchFallback => 'текущая ветка';
  @override
  String applyCommitOnto({required Object branch}) =>
      'Применить изменения коммита к ${branch}';
  @override
  String revertCommitOn({required Object branch}) =>
      'Откатить изменения коммита на ${branch}';
}

// Path: history.cherryPick
class _Translations$history$cherryPick$ru
    extends Translations$history$cherryPick$en {
  _Translations$history$cherryPick$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Cherry-pick приостановлен. Завершите оставшиеся конфликты на странице «Изменения».';
  @override
  String failed({required Object error}) => 'Сбой cherry-pick: ${error}';
  @override
  String pickedResolved({required Object short}) =>
      'Cherry-pick ${short} (конфликты устранены)';
  @override
  String picked({required Object short}) => 'Cherry-pick ${short}';
}

// Path: history.revert
class _Translations$history$revert$ru extends Translations$history$revert$en {
  _Translations$history$revert$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Откат приостановлен. Завершите оставшиеся конфликты на странице «Изменения».';
  @override
  String failed({required Object error}) => 'Сбой отката: ${error}';
  @override
  String revertedResolved({required Object short}) =>
      'Откачен ${short} (конфликты устранены)';
  @override
  String reverted({required Object short}) => 'Откачен ${short}';
}

// Path: history.reflog
class _Translations$history$reflog$ru extends Translations$history$reflog$en {
  _Translations$history$reflog$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get createBranchFromHere => 'Создать ветку отсюда…';
  @override
  String get copyCommitHash => 'Копировать хеш коммита';
  @override
  String get createBranchDialogTitle => 'Создать ветку из записи reflog';
  @override
  String anchorLine({required Object short, required Object summary}) =>
      'Якорь: ${short}  ·  ${summary}';
  @override
  String get branchNameHint => 'имя ветки';
  @override
  String get createAction => 'Создать';
  @override
  String createBranchFailed({required Object error}) =>
      'Не удалось создать ветку: ${error}';
  @override
  String branchCreatedAt({required Object name, required Object short}) =>
      'Ветка «${name}» создана на ${short}.';
}

// Path: history.rebase
class _Translations$history$rebase$ru extends Translations$history$rebase$en {
  _Translations$history$rebase$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String firstCommitCannotBe({required Object action}) =>
      'Первый коммит не может быть ${action}';
  @override
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'Rebase ${n} коммит',
        few: 'Rebase ${n} коммита',
        many: 'Rebase ${n} коммитов',
        other: 'Rebase ${n} коммитов',
      );
  @override
  String get resetLabel => 'сброс';
  @override
  String get dragToReorderHint =>
      'перетаскивайте для порядка, действие для каждого коммита';
  @override
  String get newMessageHint => 'новое сообщение';
  @override
  String get runningEllipsis => '…';
  @override
  String get startRebase => 'Начать rebase';
}

// Path: history.inFlight
class _Translations$history$inFlight$ru
    extends Translations$history$inFlight$en {
  _Translations$history$inFlight$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'В РАБОТЕ';
  @override
  String get deskFallbackLabel => 'Desk';
}

// Path: historySurgery.chrome
class _Translations$historySurgery$chrome$ru
    extends Translations$historySurgery$chrome$en {
  _Translations$historySurgery$chrome$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Хирургия истории';
  @override
  String get alphaBadge => 'alpha';
  @override
  String get dryRunBadge => 'СУХОЙ ПРОГОН';
}

// Path: historySurgery.select
class _Translations$historySurgery$select$ru
    extends Translations$historySurgery$select$en {
  _Translations$historySurgery$select$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get prompt => 'Выберите файлы для удаления из истории';
  @override
  String selectedCount({required Object n}) => '${n} выбрано';
  @override
  String get searchHint => 'поиск...';
  @override
  String get readingTree => 'читаю дерево...';
  @override
  String get continueDisabled => 'выберите файлы, чтобы продолжить';
  @override
  String get continueEnabled => 'продолжить →';
  @override
  String toPurgeCount({required Object n}) => '${n} к вычистке';
  @override
  String get analyzing => 'анализирую...';
  @override
  String get riskLow => 'низкий риск';
  @override
  String get riskModerate => 'умеренный риск';
  @override
  String get riskHigh => 'высокий риск';
  @override
  String get impactCommitsLabel => 'коммиты';
  @override
  String get impactBranchesLabel => 'ветки';
  @override
  String get impactWorktreesLabel => 'рабочие каталоги';
  @override
  String get impactCouplingLabel => 'связность';
  @override
  String get impactCouplingIsland => 'остров';
  @override
  String impactCouplingNeighbors({required Object n}) => '${n} соседей';
  @override
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class _Translations$historySurgery$understand$ru
    extends Translations$historySurgery$understand$en {
  _Translations$historySurgery$understand$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get heading => 'Как это работает';
  @override
  String get backupTitle => 'Резервная копия';
  @override
  String get backupBody =>
      'Каждая ссылка ветки и метки копируется в резервное пространство имён до любых изменений. Если что-то пойдёт не так, один клик восстановит исходное состояние.';
  @override
  String get rewriteTitle => 'Перезапись';
  @override
  String get rewriteBody =>
      'Каждый коммит обходится от корня к вершине. Для каждого коммита, содержащего целевые файлы, создаётся новый коммит с удалёнными из дерева файлами. Цепочки родителей переотображаются для сохранения топологии. ';
  @override
  String rewriteSummary({required Object affected, required Object total}) =>
      'Будет перезаписано ${affected} из ${total} коммитов.';
  @override
  String get updateRefsTitle => 'Обновление ссылок';
  @override
  String get updateRefsBody =>
      'Указатели веток и меток переводятся на новые SHA коммитов. Старые объекты существуют до сборки мусора. ';
  @override
  String worktreesNeedRecheckout({required Object n}) =>
      'Вашим рабочим каталогам (${n} шт.) потребуется повторный checkout.';
  @override
  String get noWorktreesAffected => 'Рабочие каталоги не затронуты.';
  @override
  String get forcePushTitle => 'Форс-пуш';
  @override
  String get forcePushBody =>
      'После проверки вычистки вы выбираете, какие ветки сделать форс-пушем. Используется --force-with-lease, поэтому операция безопасно прервётся, если кто-то запушил в это время.';
  @override
  String get plumbingNote =>
      'В отличие от filter-repo или BFG, это работает целиком через plumbing-команды git (cat-file, mktree, commit-tree, update-ref). Без внешних зависимостей. Отслеживание переименований идёт по одной цепочке на файл — если файл был скопирован, а обе копии переименованы независимо, проверьте результат вычистки после выполнения.';
  @override
  String get back => '← Назад';
  @override
  String get continueLabel => 'Понимаю, продолжить →';
}

// Path: historySurgery.confirm
class _Translations$historySurgery$confirm$ru
    extends Translations$historySurgery$confirm$en {
  _Translations$historySurgery$confirm$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String commitsRewritten({required Object n}) =>
      'Будет перезаписано ${n} коммитов';
  @override
  String get forcePushRequired => 'Для удалённых веток потребуется форс-пуш';
  @override
  String worktreesRecheckout({required Object n}) =>
      '${n} рабочим каталогам потребуется повторный checkout';
  @override
  String stashesInvalid({required Object n}) =>
      '${n} стэшей могут стать недействительными';
  @override
  String get heading => 'Эта операция переписывает историю git';
  @override
  String get subheading => 'Её нельзя автоматически отменить после форс-пуша.';
  @override
  String typeHint({required Object word}) => 'введите ${word}';
  @override
  String get goBack => 'Назад';
  @override
  String get begin => 'Начать операцию';
}

// Path: historySurgery.execute
class _Translations$historySurgery$execute$ru
    extends Translations$historySurgery$execute$en {
  _Translations$historySurgery$execute$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => 'Подготовка...';
  @override
  String get backingUpRefs => 'Резервирую ссылки...';
  @override
  String get rewritingCommits => 'Переписываю коммиты...';
  @override
  String get updatingRefs => 'Обновляю ссылки...';
}

// Path: historySurgery.verify
class _Translations$historySurgery$verify$ru
    extends Translations$historySurgery$verify$en {
  _Translations$historySurgery$verify$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get complete => 'Операция завершена';
  @override
  String get failed => 'Операция не удалась';
  @override
  String get commitsRewrittenLabel => 'Коммитов переписано';
  @override
  String get refsUpdatedLabel => 'Ссылок обновлено';
  @override
  String get oldHeadLabel => 'Старый HEAD';
  @override
  String get newHeadLabel => 'Новый HEAD';
  @override
  String get purgeVerifiedLabel => 'Вычистка проверена';
  @override
  String get purgeClean => 'чисто';
  @override
  String get purgeTracesRemain => 'ОСТАЛИСЬ СЛЕДЫ';
  @override
  String get displacedWorktrees => 'Смещённые рабочие каталоги';
  @override
  String get undoSurgery => 'Отменить операцию';
  @override
  String get rolledBack => 'Откачено к резервным ссылкам.';
  @override
  String get done => 'Готово';
}

// Path: historySurgery.forcePush
class _Translations$historySurgery$forcePush$ru
    extends Translations$historySurgery$forcePush$en {
  _Translations$historySurgery$forcePush$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get pushing => 'пуш...';
  @override
  String get forcePushAll => 'Форс-пуш всего';
  @override
  String get confirmPush => 'подтвердить пуш';
  @override
  String get cancel => 'отмена';
}

// Path: onboarding.nav
class _Translations$onboarding$nav$ru extends Translations$onboarding$nav$en {
  _Translations$onboarding$nav$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get back => 'Назад';
  @override
  String get continueLabel => 'Продолжить';
  @override
  String get letsGo => 'Поехали';
}

// Path: onboarding.naming
class _Translations$onboarding$naming$ru
    extends Translations$onboarding$naming$en {
  _Translations$onboarding$naming$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'чем это станет для вас?';
  @override
  String get questionEmphasis => 'это';
  @override
  String get iAmPrefix => 'Я — ';
  @override
  String get iAmSuffix => ' , ваш личный git-клиент.';
}

// Path: onboarding.theme
class _Translations$onboarding$theme$ru
    extends Translations$onboarding$theme$en {
  _Translations$onboarding$theme$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'приоденьте ${name}.';
  @override
  String get themesHeader => 'ТЕМЫ';
  @override
  String get keybindingsHeader => 'ГОРЯЧИЕ КЛАВИШИ';
  @override
  String get previewBadge => 'превью';
  @override
  String get useDefaults => 'по умолчанию';
}

// Path: onboarding.repo
class _Translations$onboarding$repo$ru extends Translations$onboarding$repo$en {
  _Translations$onboarding$repo$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'наведите ${name} на что-нибудь.';
  @override
  String get later => 'сделаю это позже';
  @override
  late final _Translations$onboarding$repo$doors$ru doors =
      _Translations$onboarding$repo$doors$ru._(_root);
  @override
  late final _Translations$onboarding$repo$cloneForm$ru cloneForm =
      _Translations$onboarding$repo$cloneForm$ru._(_root);
  @override
  late final _Translations$onboarding$repo$pickers$ru pickers =
      _Translations$onboarding$repo$pickers$ru._(_root);
  @override
  late final _Translations$onboarding$repo$errors$ru errors =
      _Translations$onboarding$repo$errors$ru._(_root);
}

// Path: onboarding.preview
class _Translations$onboarding$preview$ru
    extends Translations$onboarding$preview$en {
  _Translations$onboarding$preview$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$preview$panels$ru panels =
      _Translations$onboarding$preview$panels$ru._(_root);
  @override
  late final _Translations$onboarding$preview$sidebar$ru sidebar =
      _Translations$onboarding$preview$sidebar$ru._(_root);
  @override
  late final _Translations$onboarding$preview$changes$ru changes =
      _Translations$onboarding$preview$changes$ru._(_root);
  @override
  late final _Translations$onboarding$preview$history$ru history =
      _Translations$onboarding$preview$history$ru._(_root);
  @override
  late final _Translations$onboarding$preview$branches$ru branches =
      _Translations$onboarding$preview$branches$ru._(_root);
  @override
  late final _Translations$onboarding$preview$diff$ru diff =
      _Translations$onboarding$preview$diff$ru._(_root);
}

// Path: orrery.header
class _Translations$orrery$header$ru extends Translations$orrery$header$en {
  _Translations$orrery$header$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Orrery';
  @override
  String get modeScrub => 'Прокрутка';
  @override
  String get modeCompare => 'Сравнение';
  @override
  String get lodModules => 'Модули';
  @override
  String get lodFiles => 'Файлы';
}

// Path: orrery.status
class _Translations$orrery$status$ru extends Translations$orrery$status$en {
  _Translations$orrery$status$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'Прослеживаю manifold сквозь историю…';
  @override
  String get loadError => 'Не удалось прочитать историю этого репозитория.';
  @override
  String get notEnoughHistory =>
      'Пока недостаточно истории, чтобы построить траекторию.';
  @override
  String get notEnoughHistoryDetail =>
      'Orrery нужно несколько коммитов, чтобы начертить.';
}

// Path: orrery.legend
class _Translations$orrery$legend$ru extends Translations$orrery$legend$en {
  _Translations$orrery$legend$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get central => 'центральный';
  @override
  String get peripheral => 'периферийный';
}

// Path: orrery.node
class _Translations$orrery$node$ru extends Translations$orrery$node$en {
  _Translations$orrery$node$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get module => 'модуль';
  @override
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · ${n} файлов';
  @override
  String fileFallback({required Object id}) => 'файл #${id}';
  @override
  String nodeFallback({required Object id}) => 'узел #${id}';
  @override
  String get rootModule => '(корень)';
}

// Path: orrery.milestone
class _Translations$orrery$milestone$ru
    extends Translations$orrery$milestone$en {
  _Translations$orrery$milestone$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get genesis => 'начало';
  @override
  String get now => 'сейчас';
  @override
  String get reorganized => 'реорганизован';
  @override
  String becameArchetype({required Object archetype}) => 'стал ${archetype}';
  @override
  String get snapshot => 'снимок';
}

// Path: orrery.structure
class _Translations$orrery$structure$ru
    extends Translations$orrery$structure$en {
  _Translations$orrery$structure$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get forming => 'формируется…';
  @override
  String get canonical => 'канонический';
  @override
  String get connectivity => 'связность';
  @override
  String get rigidity => 'жёсткость';
  @override
  String get entropy => 'энтропия';
}

// Path: orrery.rail
class _Translations$orrery$rail$ru extends Translations$orrery$rail$en {
  _Translations$orrery$rail$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get structureLabel => 'СТРУКТУРА';
  @override
  String get fieldLabel => 'ПОЛЕ';
  @override
  String get findingsLabel => 'НАХОДКИ';
  @override
  String get selectedLabel => 'ВЫБРАНО';
  @override
  String get noFindings => 'В этой истории структурных событий не обнаружено.';
}

// Path: orrery.selection
class _Translations$orrery$selection$ru
    extends Translations$orrery$selection$en {
  _Translations$orrery$selection$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get notPresent => 'Отсутствует в этой точке истории.';
  @override
  String get roleCentral =>
      'Центр связности — изменения здесь расходятся по всей системе.';
  @override
  String get rolePeripheral =>
      'Периферия — слабо связан, меняется в основном сам по себе.';
  @override
  String get roleMid => 'Средняя структура — умеренно связан.';
  @override
  String get driftOutward => ' Дрейфует наружу — расцепляется.';
  @override
  String get driftInward => ' Дрейфует внутрь — интегрируется.';
  @override
  String get driftHolding => ' Держит позицию.';
}

// Path: orrery.findingKind
class _Translations$orrery$findingKind$ru
    extends Translations$orrery$findingKind$en {
  _Translations$orrery$findingKind$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get hub => 'УЗЕЛ';
  @override
  String get driftOut => 'ДРЕЙФ НАРУЖУ';
  @override
  String get driftIn => 'ДРЕЙФ ВНУТРЬ';
  @override
  String get tangle => 'ЗАПУТЫВАНИЕ';
  @override
  String get clarify => 'ПРОЯСНЕНИЕ';
  @override
  String get regime => 'РЕОРГ';
  @override
  String get thrash => 'МЕТАНИЕ';
  @override
  String get reshuffle => 'ПЕРЕТАСОВКА';
  @override
  String get forecast => 'ПРОГНОЗ';
}

// Path: orrery.findings
class _Translations$orrery$findings$ru extends Translations$orrery$findings$en {
  _Translations$orrery$findings$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get forecastSplit =>
      'Связность падала и близка к минимуму — если так продолжится, кодовая база движется к расколу на две слабо связанные половины. Решите сейчас, был ли это замысел.';
  @override
  String get forecastConsolidate =>
      'Связность росла к пику — если так продолжится, кодовая база консолидируется в одну тесно связанную массу. Следите, чтобы она не затвердела в монолит.';
  @override
  String thrash({required Object name}) =>
      '${name} постоянно реорганизуется туда-обратно — много структурной суеты, мало чистого движения. Устаканьте его связность или перестаньте его трогать.';
  @override
  String get reshuffle =>
      'Этот коммит выглядел рутинным, но тихо сместил, какие файлы центральны — общая форма сохранилась, а структура под ней перетасовалась. Проверьте его внимательно.';
  @override
  String hub({required Object name}) =>
      '${name} сидит в структурном ядре — система реорганизуется вокруг него. Считайте изменения здесь высокорадиусными по последствиям.';
  @override
  String driftOut({required Object name}) =>
      '${name} сдрейфовал от ядра к краю — расцепляется с системой. Либо его выводят из обращения, либо он тихо гниёт.';
  @override
  String driftIn({required Object name}) =>
      '${name} мигрировал к ядру — становится несущим. Убедитесь, что он хорошо покрыт тестами, прежде чем от него зависит больше.';
  @override
  String get regime =>
      'Кодовая база резко реорганизовалась здесь — её связность скакнула. Проверьте, что откололось или слилось.';
  @override
  String get tangleTrend =>
      'За свою историю кодовая база тяготела к более запутанной структуре — её связность становится плотнее и менее модульной.';
  @override
  String get clarifyTrend =>
      'За свою историю кодовая база тяготела к более чистой структуре — она разделяется на более ясные модули.';
}

// Path: orrery.anchor
class _Translations$orrery$anchor$ru extends Translations$orrery$anchor$en {
  _Translations$orrery$anchor$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get core => 'ядро';
  @override
  String get drift => 'дрейф';
  @override
  String get trend => 'тренд';
  @override
  String get thrash => 'метание';
}

// Path: orrery.compare
class _Translations$orrery$compare$ru extends Translations$orrery$compare$en {
  _Translations$orrery$compare$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'A → B';
  @override
  String get change => 'ИЗМЕНЕНИЕ';
  @override
  String get movers => 'СДВИГИ';
  @override
  String get noMovers => 'Между этими кадрами файлы не сдвинулись.';
  @override
  String get badgeA => 'A';
  @override
  String get badgeB => 'B';
  @override
  String get deltaFiles => 'файлы';
  @override
  String get deltaConnectivity => 'связность';
  @override
  String get deltaRigidity => 'жёсткость';
  @override
  String get deltaEntropy => 'энтропия';
  @override
  String get wayOutward => 'наружу';
  @override
  String get wayInward => 'внутрь';
  @override
  String get wayShifted => 'сдвинут';
}

// Path: palette.prefixes
class _Translations$palette$prefixes$ru
    extends Translations$palette$prefixes$en {
  _Translations$palette$prefixes$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get askHint => 'ask: [вопрос]';
  @override
  String get nearHint => 'near: [файл]';
  @override
  String get whoHint => 'who: [файл]';
  @override
  String get logHint => 'log: [сообщение]';
  @override
  String get runHint => 'run: [инструмент]';
  @override
  String askLabel({required Object name, required Object body}) =>
      'Спросить ${name}: ${body}';
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
  }) => '${path} · ${count} ревьюеров · ${touches} касаний';
  @override
  String whoTouchesLabel({required Object name, required Object touches}) =>
      '${name} — ${touches} касаний';
  @override
  String whoTouchesSubtitle({required Object path}) =>
      '${path} · ревьюеры не записаны';
}

// Path: palette.chips
class _Translations$palette$chips$ru extends Translations$palette$chips$en {
  _Translations$palette$chips$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get ai => 'AI';
  @override
  String get near => 'РЯДОМ';
  @override
  String get who => 'КТО';
  @override
  String get term => 'ТЕРМ';
  @override
  String get gui => 'GUI';
  @override
  String get dev => 'DEV';
  @override
  String get debug => 'ОТЛАДКА';
  @override
  String get alpha => 'ALPHA';
  @override
  String get hot => 'ГОР';
  @override
  String get key => 'КЛАВ';
  @override
  String get web => 'WEB';
  @override
  String get sys => 'СИС';
  @override
  String get clip => 'БУФЕР';
  @override
  String get sync => 'СИНХР';
  @override
  String get force => 'ФОРС';
  @override
  String get pr => 'PR';
  @override
  String get draft => 'ЧЕРН';
  @override
  String get undo => 'ОТМЕНА';
  @override
  String get thm => 'ТЕМА';
  @override
  String get ver => 'ВЕР';
  @override
  String get desk => 'DESK';
  @override
  String get det => 'ОТСЦ';
  @override
  String get main => 'MAIN';
  @override
  String get head => 'HEAD';
  @override
  String get gone => 'НЕТ';
  @override
  String get remote => 'УДАЛ';
  @override
  String get local => 'ЛОК';
  @override
  String get an => 'AN';
  @override
  String get lw => 'LW';
}

// Path: palette.predictive
class _Translations$palette$predictive$ru
    extends Translations$palette$predictive$en {
  _Translations$palette$predictive$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String momentumSuffix({required Object percent}) => '${percent}% импульса';
}

// Path: palette.topTouched
class _Translations$palette$topTouched$ru
    extends Translations$palette$topTouched$en {
  _Translations$palette$topTouched$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object count, required Object path}) =>
      '${count} касаний · ${path}';
}

// Path: palette.coherence
class _Translations$palette$coherence$ru
    extends Translations$palette$coherence$en {
  _Translations$palette$coherence$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String label({required Object percent}) => 'Связность индекса: ${percent}%';
  @override
  String subtitle({required Object count}) => '${count} файлов';
}

// Path: palette.keystone
class _Translations$palette$keystone$ru
    extends Translations$palette$keystone$en {
  _Translations$palette$keystone$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object path, required Object score}) =>
      '${path} · краеугольный ${score}';
}

// Path: palette.repoSub
class _Translations$palette$repoSub$ru extends Translations$palette$repoSub$en {
  _Translations$palette$repoSub$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String changes({required Object name}) => 'Изменения в ${name}';
  @override
  String history({required Object name}) => 'История в ${name}';
  @override
  String branches({required Object name}) => 'Ветки в ${name}';
  @override
  String terminal({required Object name}) => 'Терминал в ${name}';
  @override
  String generateCommit({required Object name}) =>
      'Сгенерировать коммит · ${name}';
  @override
  String reviewChanges({required Object name}) => 'Ревью изменений в ${name}';
  @override
  String muse({required Object name}) => 'Muse в ${name}';
}

// Path: palette.desks
class _Translations$palette$desks$ru extends Translations$palette$desks$en {
  _Translations$palette$desks$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get mainWorktree => 'главный рабочий каталог';
  @override
  String get detached => 'отсоединён';
  @override
  String dirty({required Object count}) => '${count} грязных';
}

// Path: palette.actions
class _Translations$palette$actions$ru extends Translations$palette$actions$en {
  _Translations$palette$actions$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get openInBrowser => 'Открыть в браузере';
  @override
  String get terminal => 'Терминал';
  @override
  String get revealInFiles => 'Показать в проводнике';
  @override
  String get copyPath => 'Копировать путь';
  @override
  String get copyBranch => 'Копировать ветку';
}

// Path: palette.tools
class _Translations$palette$tools$ru extends Translations$palette$tools$en {
  _Translations$palette$tools$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String launch({required Object label}) => 'Запустить ${label}';
}

// Path: palette.gitCommands
class _Translations$palette$gitCommands$ru
    extends Translations$palette$gitCommands$en {
  _Translations$palette$gitCommands$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get fetch => 'Фетч';
  @override
  String get pull => 'Пул';
  @override
  String pullBehind({required Object count}) => '${count} позади';
  @override
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';
  @override
  String get push => 'Пуш';
  @override
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} коммит',
        few: '${n} коммита',
        many: '${n} коммитов',
        other: '${n} коммитов',
      );
  @override
  String pushCommitsUpstream({
    required Object commits,
    required Object upstream,
  }) => '${commits} в ${upstream}';
  @override
  String get forcePush => 'Форс-пуш';
  @override
  String forcePushNoUpstream({required Object branch}) =>
      'Форс-пуш невозможен: для ${branch} не задан upstream.';
  @override
  String get commit => 'Коммит';
  @override
  String get stageAll => 'Всё в индекс';
  @override
  String get unstageAll => 'Всё из индекса';
  @override
  String get discardAll => 'Отбросить всё';
  @override
  String get createBranch => 'Создать ветку';
  @override
  String get deleteBranch => 'Удалить ветку';
  @override
  String get renameBranch => 'Переименовать ветку';
  @override
  String get stash => 'Спрятать';
  @override
  String get stashPop => 'Извлечь стэш';
  @override
  String get stashApply => 'Применить стэш';
  @override
  String get stashDrop => 'Сбросить стэш';
  @override
  String get createTag => 'Создать метку';
  @override
  String get cherryPick => 'Cherry-pick';
  @override
  String get revert => 'Ревёрт';
  @override
  String get stashConflictMessage =>
      'Стэш применён с конфликтами. Устраните их на странице «Изменения».';
}

// Path: palette.pr
class _Translations$palette$pr$ru extends Translations$palette$pr$en {
  _Translations$palette$pr$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get create => 'Создать PR';
  @override
  String get merge => 'Мёржить PR';
  @override
  String get markReady => 'Пометить PR готовым';
}

// Path: palette.ai
class _Translations$palette$ai$ru extends Translations$palette$ai$en {
  _Translations$palette$ai$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get generateCommit => 'Сгенерировать коммит';
  @override
  String get reviewChanges => 'Ревью изменений';
  @override
  String get runMuse => 'Запустить Muse';
  @override
  String debugRepo({required Object name}) => 'Отладить ${name}';
  @override
  String get describeSymptom => 'опишите симптом';
  @override
  String viewResult({required Object kind}) => 'Смотреть ${kind}';
  @override
  String get unseenResult => 'непросмотренный результат';
  @override
  String runningResult({required Object kind}) => 'AI: ${kind}…';
  @override
  String get running => 'выполняется';
  @override
  String get kindCommitMessage => 'Сообщение коммита';
  @override
  String get kindCodeReview => 'Ревью кода';
  @override
  String get kindMuseResult => 'Результат Muse';
  @override
  String get kindPresentation => 'Презентация';
  @override
  String get kindDebugResult => 'Результат отладки';
}

// Path: palette.undo
class _Translations$palette$undo$ru extends Translations$palette$undo$en {
  _Translations$palette$undo$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String cancel({required Object label}) => 'Отмена: ${label}';
}

// Path: palette.navigation
class _Translations$palette$navigation$ru
    extends Translations$palette$navigation$en {
  _Translations$palette$navigation$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get changes => 'Изменения';
  @override
  String get history => 'История';
  @override
  String get branches => 'Ветки';
  @override
  String get xray => 'X-Ray';
  @override
  String get settings => 'Настройки';
  @override
  String get refresh => 'Обновить';
}

// Path: palette.settings
class _Translations$palette$settings$ru
    extends Translations$palette$settings$en {
  _Translations$palette$settings$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get reduceMotion => 'Меньше движения';
  @override
  String get animateLogoUnfocused => 'Анимация логотипа вне фокуса';
  @override
  String get instantBlameHover => 'Мгновенный blame при наведении';
  @override
  String get autoSelectChanges => 'Автовыбор изменений';
  @override
  String get fetchOnlineIssues => 'Загружать онлайн-задачи';
  @override
  String get rememberWip => 'Помнить незавершённую работу';
  @override
  String get hideAiFeatures => 'Скрыть AI-функции';
  @override
  String get crashReporting => 'Отчёты о сбоях';
  @override
  String get aiReadOnly => 'AI только для чтения';
  @override
  String get stashCabinetExpanded => 'Шкаф стэшей раскрыт';
  @override
  String get fileSortInverted => 'Сортировка файлов обратная';
}

// Path: palette.info
class _Translations$palette$info$ru extends Translations$palette$info$en {
  _Translations$palette$info$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class _Translations$palette$debug$ru extends Translations$palette$debug$en {
  _Translations$palette$debug$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get engineStatus => 'Статус движка';
  @override
  String get engineStatusSubtitle =>
      'Диагностика спектрального движка LogosGit';
  @override
  String get fileCoupling => 'Связность файлов';
  @override
  String get fileCouplingSubtitle =>
      'Ближайшие соседи по совместным изменениям для файлов в индексе';
  @override
  String get themeSpecimen => 'Образец темы';
  @override
  String get themeSpecimenSubtitle =>
      'Все цвета, иконки, уровни текста и геометрия';
}

// Path: palette.dev
class _Translations$palette$dev$ru extends Translations$palette$dev$en {
  _Translations$palette$dev$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get testMergeEditor => 'Тест редактора слияния';
  @override
  String get testHistorySurgery => 'Тест хирургии истории';
  @override
  String get back => 'назад';
  @override
  String get cancel => 'отмена';
  @override
  String get buildingConflicts => 'строю тестовые конфликты из истории…';
}

// Path: palette.historySurgery
class _Translations$palette$historySurgery$ru
    extends Translations$palette$historySurgery$en {
  _Translations$palette$historySurgery$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Хирургия истории';
  @override
  String get subtitle => 'Переписать историю, чтобы навсегда удалить файлы';
}

// Path: palette.orrery
class _Translations$palette$orrery$ru extends Translations$palette$orrery$en {
  _Translations$palette$orrery$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Orrery';
  @override
  String get subtitle =>
      'Прокрутите структурную историю репозитория сквозь manifold';
}

// Path: palette.command
class _Translations$palette$command$ru extends Translations$palette$command$en {
  _Translations$palette$command$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String complete({required Object label}) => '${label} — завершено';
  @override
  String failed({required Object label, required Object message}) =>
      '${label} — сбой: ${message}';
  @override
  String get copy => 'Копировать';
}

// Path: palette.search
class _Translations$palette$search$ru extends Translations$palette$search$en {
  _Translations$palette$search$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get hintDefault => 'искать везде...';
  @override
  String get hintElevated => 'расширенно — все действия';
  @override
  String get emptyTypeToSearch => 'печатайте для поиска';
  @override
  String get emptyNoResults => 'ничего не найдено';
}

// Path: palette.wick
class _Translations$palette$wick$ru extends Translations$palette$wick$en {
  _Translations$palette$wick$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'wick';
  @override
  String get coupledFallback => 'связан';
}

// Path: palette.gitCache
class _Translations$palette$gitCache$ru
    extends Translations$palette$gitCache$en {
  _Translations$palette$gitCache$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'текущий';
  @override
  String get staged => 'в индексе';
  @override
  String get modified => 'изменён';
}

// Path: releaseNotes.about
class _Translations$releaseNotes$about$ru
    extends Translations$releaseNotes$about$en {
  _Translations$releaseNotes$about$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$releaseNotes$about$whyFlutter$ru whyFlutter =
      _Translations$releaseNotes$about$whyFlutter$ru._(_root);
  @override
  late final _Translations$releaseNotes$about$spectralEngine$ru spectralEngine =
      _Translations$releaseNotes$about$spectralEngine$ru._(_root);
  @override
  late final _Translations$releaseNotes$about$whereGoing$ru whereGoing =
      _Translations$releaseNotes$about$whereGoing$ru._(_root);
}

// Path: releaseNotes.legal
class _Translations$releaseNotes$legal$ru
    extends Translations$releaseNotes$legal$en {
  _Translations$releaseNotes$legal$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get copyright => '© 2026 Woflo Labs';
  @override
  String get license =>
      'GPL-3.0-or-later · исследовательское ядро WLCSL (community-source) · без гарантий';
}

// Path: repoSummary.backbone
class _Translations$repoSummary$backbone$ru
    extends Translations$repoSummary$backbone$en {
  _Translations$repoSummary$backbone$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}` (${lines}) — ${region}';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} строка',
        few: '${n} строки',
        many: '${n} строк',
        other: '${n} строк',
      );
  @override
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class _Translations$repoSummary$glance$ru
    extends Translations$repoSummary$glance$en {
  _Translations$repoSummary$glance$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} файл.',
        few: '${n} файла.',
        many: '${n} файлов.',
        other: '${n} файлов.',
      );
  @override
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} строка (${bytes}).',
        few: '${n} строки (${bytes}).',
        many: '${n} строк (${bytes}).',
        other: '${n} строк (${bytes}).',
      );
  @override
  String roles({required Object parts}) => 'Роли — ${parts}.';
  @override
  String showingNofM({required Object active, required Object total}) =>
      'Показано ${active} из ${total} файлов, по структурной центральности.';
}

// Path: repoSummary.heading
class _Translations$repoSummary$heading$ru
    extends Translations$repoSummary$heading$en {
  _Translations$repoSummary$heading$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get atAGlance => 'С первого взгляда';
  @override
  String get core => 'Ядро';
  @override
  String get gettingStarted => 'С чего начать';
  @override
  String get regions => 'Регионы';
  @override
  String get shape => 'Форма';
}

// Path: repoSummary.pitch
class _Translations$repoSummary$pitch$ru
    extends Translations$repoSummary$pitch$en {
  _Translations$repoSummary$pitch$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String empty({required Object detail}) =>
      'Репозиторий без читаемых текстовых файлов${detail}.';
  @override
  String emptyBinary({required Object n}) => '${n} бинарных';
  @override
  String emptyUnreadable({required Object n}) => '${n} нечитаемых';
  @override
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'Репозиторий из ${n} активного файла.',
        few: 'Репозиторий из ${n} активных файлов.',
        many: 'Репозиторий из ${n} активных файлов.',
        other: 'Репозиторий из ${n} активных файлов.',
      );
  @override
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'Репозиторий из ${n} активного файла — ${regions}.',
        few: 'Репозиторий из ${n} активных файлов — ${regions}.',
        many: 'Репозиторий из ${n} активных файлов — ${regions}.',
        other: 'Репозиторий из ${n} активных файлов — ${regions}.',
      );
}

// Path: repoSummary.region
class _Translations$repoSummary$region$ru
    extends Translations$repoSummary$region$en {
  _Translations$repoSummary$region$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String bodyCommonDir({required Object dir}) => 'Всё в `${dir}`.';
  @override
  String get bodyCommonDirSeparator => ' ';
  @override
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '1 в ядре',
        few: '${n} в ядре',
        many: '${n} в ядре',
        other: '${n} в ядре',
      );
  @override
  String get bodyCoreSeparator => ', ';
  @override
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'Один файл',
        few: '${n} файла',
        many: '${n} файлов',
        other: '${n} файлов',
      );
  @override
  String connectsTo({required Object linked}) => 'Связан с: ${linked}.';
  @override
  String get filesLabel => 'Файлы:';
}

// Path: repoSummary.shape
class _Translations$repoSummary$shape$ru
    extends Translations$repoSummary$shape$en {
  _Translations$repoSummary$shape$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get bulk =>
      'Плотно связанная кодовая база: большинство файлов входит в одну крупную окрестность совместных изменений.';
  @override
  String get crystalline =>
      'Кодовая база в форме решётки: однородная, регулярная связность между файлами с предсказуемой локальной структурой.';
  @override
  String get goe =>
      'Богато связанная кодовая база: связи разбросаны по файлам без доминирующего хребта.';
  @override
  String get modular =>
      'Модульная кодовая база: несколько цельных регионов с ограниченной перекрёстной связностью. Работа в одном регионе редко задевает другой.';
  @override
  String get poisson =>
      'Слабо связанная кодовая база: файлы развиваются в основном по отдельности, с редкими совместными изменениями.';
  @override
  String get tree =>
      'Древовидная кодовая база: один доминирующий хребет с зависимыми ветвями. Изменения обычно расходятся от ядра наружу.';
}

// Path: settings.language
class _Translations$settings$language$ru
    extends Translations$settings$language$en {
  _Translations$settings$language$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Язык';
  @override
  String get summary =>
      'Язык интерфейса этого приложения. Вывод git, логи и диагностика остаются на английском, чтобы отчёты о багах были доступны для поиска.';
  @override
  String get label => 'ЯЗЫК ИНТЕРФЕЙСА';
  @override
  String get systemDefault => 'Системный по умолчанию';
  @override
  String systemDefaultDetail({required Object resolved}) =>
      'Следует за языком ОС (${resolved})';
  @override
  String get disclosureSource => 'Исходный язык — написан разработчиками.';
  @override
  String disclosureAi({required Object model}) =>
      'Машинный перевод от ${model} — ещё не проверен человеком. Правки приветствуются.';
  @override
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) => 'Машинный перевод от ${model} — ${percent}% проверено человеком.';
  @override
  String get disclosureHuman =>
      'Человеческий перевод, поддерживается сообществом.';
  @override
  String reviewedBy({required Object names}) => 'Проверили: ${names}.';
}

// Path: settings.sectionLabels
class _Translations$settings$sectionLabels$ru
    extends Translations$settings$sectionLabels$en {
  _Translations$settings$sectionLabels$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get preferences => 'Предпочтения';
  @override
  String get shortcuts => 'Горячие клавиши';
  @override
  String get behaviour => 'Поведение';
  @override
  String get aiProviders => 'AI-провайдеры';
  @override
  String get modelSlots => 'Слоты моделей';
  @override
  String get tools => 'Инструменты';
  @override
  String get diagnostics => 'Диагностика';
  @override
  String get offenders => 'Нарушители';
  @override
  String get release => 'Релиз';
}

// Path: settings.errors
class _Translations$settings$errors$ru extends Translations$settings$errors$en {
  _Translations$settings$errors$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get saveGuardrailProfile => 'Не удалось сохранить профиль ограждений.';
  @override
  String get saveRetentionPolicy => 'Не удалось сохранить политику хранения.';
  @override
  String get saveUpdateChannel => 'Не удалось сохранить канал обновлений.';
  @override
  String get saveModelSelection => 'Не удалось сохранить выбор AI-модели.';
  @override
  String get saveModelAlias => 'Не удалось сохранить псевдоним модели.';
  @override
  String get saveCommitMessageModelSlot =>
      'Не удалось сохранить слот модели сообщений коммитов.';
  @override
  String get saveReviewModelSlot => 'Не удалось сохранить слот модели ревью.';
  @override
  String get saveCommitMessageCustomPrompt =>
      'Не удалось сохранить свой промпт для сообщений коммитов.';
  @override
  String get saveReviewGuide => 'Не удалось сохранить руководство по ревью.';
  @override
  String get saveMuseNotes => 'Не удалось сохранить заметки музы.';
  @override
  String get saveReviewDoubleCheck =>
      'Не удалось сохранить режим двойной проверки ревью.';
  @override
  String get saveApiPiggybackCli =>
      'Не удалось сохранить CLI для API-пиггибэка.';
  @override
  String get saveCliTimeout => 'Не удалось сохранить тайм-аут CLI.';
  @override
  String get stopAllCli => 'Не удалось остановить запущенные сессии CLI.';
  @override
  String clearLocalData({required Object error}) =>
      'Не удалось очистить локальные данные: ${error}';
}

// Path: settings.promptStatus
class _Translations$settings$promptStatus$ru
    extends Translations$settings$promptStatus$en {
  _Translations$settings$promptStatus$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get editing => 'Редактирование';
  @override
  String get saving => 'Сохранение';
  @override
  String get saveFailed => 'Сбой сохранения';
}

// Path: settings.clearData
class _Translations$settings$clearData$ru
    extends Translations$settings$clearData$en {
  _Translations$settings$clearData$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => 'Очистить локальные данные';
  @override
  String get clear => 'Очистить';
  @override
  String get confirmDiagnostics =>
      'Очистить локальные образцы диагностики и замеры производительности?';
  @override
  String get confirmAudit => 'Очистить локальные записи метаданных аудита AI?';
  @override
  String get confirmAll =>
      'Очистить все локальные образцы диагностики и записи метаданных аудита AI?';
  @override
  String get confirmWipeAll =>
      'Стереть все локальные данные приложения — включая список недавних репозиториев — и выйти? Ваши реальные git-репозитории на диске не затрагиваются.';
  @override
  String get confirmReset =>
      'Сбросить локальные данные приложения и выйти?\n\nНастройки, тема, онбординг, AI-предпочтения, телеметрия и кэши энграмм будут очищены. Список недавних репозиториев сохранится.';
}

// Path: settings.guardrailMacro
class _Translations$settings$guardrailMacro$ru
    extends Translations$settings$guardrailMacro$en {
  _Translations$settings$guardrailMacro$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'свободно';
  @override
  String get balanced => 'сбалансировано';
  @override
  String get strict => 'строго';
  @override
  String get paranoid => 'параноидально';
}

// Path: settings.guardrails
class _Translations$settings$guardrails$ru
    extends Translations$settings$guardrails$en {
  _Translations$settings$guardrails$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Ограждения';
  @override
  String get summary => 'Насколько внимательна автоматика по всему приложению.';
}

// Path: settings.appearance
class _Translations$settings$appearance$ru
    extends Translations$settings$appearance$en {
  _Translations$settings$appearance$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Внешний вид';
  @override
  String get summary => 'Глобальное настроение и атмосфера интерфейса.';
}

// Path: settings.retention
class _Translations$settings$retention$ru
    extends Translations$settings$retention$en {
  _Translations$settings$retention$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Хранение локальных данных';
  @override
  String get summaryDiagnostics => 'Политика хранения диагностики.';
  @override
  String get summaryWithAudit => 'Политика хранения диагностики и аудита AI.';
  @override
  String get unitDays => 'дней';
  @override
  String get unitMb => 'МБ';
  @override
  String get includesNote =>
      'Включает диагностику, замеры производительности и метаданные.';
}

// Path: settings.navigation
class _Translations$settings$navigation$ru
    extends Translations$settings$navigation$en {
  _Translations$settings$navigation$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Навигация и динамика';
  @override
  String get summaryShortcuts => 'Горячие клавиши и поведение интерфейса.';
  @override
  String get summaryWithAi =>
      'Горячие клавиши, поведение интерфейса и маршрутизация AI.';
}

// Path: settings.behaviour
class _Translations$settings$behaviour$ru
    extends Translations$settings$behaviour$en {
  _Translations$settings$behaviour$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Динамика поведения';
}

// Path: settings.retentionClear
class _Translations$settings$retentionClear$ru
    extends Translations$settings$retentionClear$en {
  _Translations$settings$retentionClear$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get diag => 'Диаг';
  @override
  String get audit => 'Аудит';
  @override
  String get all => 'Всё';
  @override
  String get clearsHint => '<-- очищает';
}

// Path: settings.channels
class _Translations$settings$channels$ru
    extends Translations$settings$channels$en {
  _Translations$settings$channels$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get stable => 'STABLE';
  @override
  String get beta => 'BETA';
  @override
  String get dev => 'DEV';
}

// Path: settings.pollResult
class _Translations$settings$pollResult$ru
    extends Translations$settings$pollResult$en {
  _Translations$settings$pollResult$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get upToDate => 'актуально';
  @override
  String updateAvailable({required Object version}) => 'доступна ${version}';
  @override
  String get notConfigured => 'нет сервера обновлений';
  @override
  String notFound({required Object channel}) => 'нет релизов ${channel}';
  @override
  String get unreachable => 'недоступно';
  @override
  String get badManifest => 'плохой манифест';
}

// Path: settings.keybindingProfile
class _Translations$settings$keybindingProfile$ru
    extends Translations$settings$keybindingProfile$en {
  _Translations$settings$keybindingProfile$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Профиль горячих клавиш';
  @override
  String get porcelain => 'Porcelain';
  @override
  String get numeric => 'Цифровой';
  @override
  String get porcelainDescription => 'Аккордные сочетания (G, затем C, H, B…).';
  @override
  String get numericDescription =>
      'Цифровые сочетания одной клавишей (1, 2, 3…).';
}

// Path: settings.apiKeys
class _Translations$settings$apiKeys$ru
    extends Translations$settings$apiKeys$en {
  _Translations$settings$apiKeys$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get keyHintDefault => 'api-ключ';
  @override
  String get endpointHint => 'эндпоинт';
  @override
  String get test => 'Тест';
  @override
  String get hide => 'Скрыть';
  @override
  String get show => 'Показать';
}

// Path: settings.shortcuts
class _Translations$settings$shortcuts$ru
    extends Translations$settings$shortcuts$en {
  _Translations$settings$shortcuts$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get navigate => 'навигация';
  @override
  String get staging => 'индексация';
  @override
  String get branchesPrs => 'ветки и PR';
  @override
  String get modifiers => 'модификаторы';
  @override
  String get changes => 'Изменения';
  @override
  String get history => 'История';
  @override
  String get branches => 'Ветки';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Переключить (всегда)';
  @override
  String get search => 'Поиск';
  @override
  String get dismiss => 'Закрыть';
  @override
  String get refresh => 'Обновить';
  @override
  String get shortcuts => 'Горячие клавиши';
  @override
  String get nextChange => 'След. изменение';
  @override
  String get prevChange => 'Пред. изменение';
  @override
  String get toggleLine => 'Переключить строку';
  @override
  String get toggleHunk => 'Переключить ханк';
  @override
  String get toggleFile => 'Переключить файл';
  @override
  String get pinContext => 'Закрепить контекст';
  @override
  String get commit => 'Коммит';
  @override
  String get acceptHint => 'Принять подсказку';
  @override
  String get undo => 'Отменить';
  @override
  String get navigateRow => 'Навигация';
  @override
  String get expand => 'Развернуть';
  @override
  String get checkout => 'Checkout';
  @override
  String get approve => 'Одобрить';
  @override
  String get requestChanges => 'Запросить правки';
  @override
  String get selectRange => 'Выбрать диапазон';
  @override
  String get extendedMenu => 'Расширенное меню';
}

// Path: settings.toggles
class _Translations$settings$toggles$ru
    extends Translations$settings$toggles$en {
  _Translations$settings$toggles$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get aiReadOnlyLabel => 'Режим AI только для чтения';
  @override
  String get aiReadOnlyDescription =>
      'Запрещает AI автоматически писать или индексировать изменения.';
  @override
  String get logoMotionLabel => 'Логотип анимируется вне активной вкладки';
  @override
  String get logoMotionDescriptionEnabled =>
      'Он сделан эффективным, не задевайте его чувства';
  @override
  String get logoMotionDescriptionDisabled => ':(';
  @override
  String get rememberWipLabel => 'Помнить незавершённую работу';
  @override
  String get rememberWipDescription =>
      'Сохранять черновики коммитов и выбор файлов между сессиями.';
  @override
  String get stashCabinetLabel => 'Шкаф стэшей открыт при старте';
  @override
  String get stashCabinetDescription =>
      'Показывать ящик картотеки открытым по умолчанию, когда у репозитория есть полки.';
  @override
  String get instantBlameLabel => 'Мгновенный blame при наведении';
  @override
  String get instantBlameDescription =>
      'Пропустить задержку 180 мс перед показом blame на строке diff.';
  @override
  String get autoSelectLabel => 'Автовыбор новых изменений';
  @override
  String get autoSelectDescription =>
      'Новые отслеживаемые или изменённые файлы автоматически добавляются в выбор для коммита.';
  @override
  String get changeIdLabel => 'Записывать заголовки change-id';
  @override
  String get changeIdDescription =>
      'Добавляет новым коммитам заголовок идентичности change-id (соглашение Jujutsu, GitButler и Gerrit). Каждый коммит переписывается один раз сразу после создания.';
  @override
  String get fetchIssuesLabel => 'Загружать онлайн-задачи при открытии веток';
  @override
  String get fetchIssuesDescription =>
      'Подтягивать детали PR и задач от вашего git-провайдера в фоне при открытии страницы веток.';
  @override
  String get hateAiLabel => 'Ненавижу AI';
  @override
  String get hateAiDescription =>
      'Изгнать все функции на базе LLM. Logos продолжает работать, потому что это просто спектральная математика.';
}

// Path: settings.diffDiffability
class _Translations$settings$diffDiffability$ru
    extends Translations$settings$diffDiffability$en {
  _Translations$settings$diffDiffability$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'diff-абельность diff';
}

// Path: settings.modelSlots
class _Translations$settings$modelSlots$ru
    extends Translations$settings$modelSlots$en {
  _Translations$settings$modelSlots$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get loadingProviders => 'Загрузка провайдеров...';
  @override
  String get refreshingProviders => 'Обновляю диагностику провайдеров...';
  @override
  String get routeDescription =>
      'Переименуйте и направьте конфигурации на любую обнаруженную модель провайдера.';
  @override
  String get loadingCategories => 'Загрузка категорий моделей...';
  @override
  String get noOptions =>
      'Пока нет доступных вариантов моделей. Сначала обнаружьте совместимый локальный AI CLI.';
  @override
  String get slotsAppearWhenAvailable =>
      'Настройки слотов моделей появятся здесь, как только станут доступны модели провайдеров.';
  @override
  String get effortDefault => 'по умолчанию';
  @override
  String get noModelsForSlot => 'Для этого слота модели не обнаружены.';
  @override
  String viaProvider({required Object provider}) => 'через ${provider}';
  @override
  String get customModelId => 'свой id модели';
}

// Path: settings.modelPicker
class _Translations$settings$modelPicker$ru
    extends Translations$settings$modelPicker$en {
  _Translations$settings$modelPicker$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String noMatch({required Object query}) =>
      'нет моделей по запросу «${query}»';
  @override
  String get noModels => 'нет доступных моделей';
  @override
  String get filterHint => 'фильтр моделей...';
  @override
  String get warming => 'прогрев…';
  @override
  String get detailsUnavailable => 'детали недоступны';
  @override
  String get free => 'бесплатно';
}

// Path: settings.aiFeatures
class _Translations$settings$aiFeatures$ru
    extends Translations$settings$aiFeatures$en {
  _Translations$settings$aiFeatures$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get commitDescription =>
      'Черновики сообщений коммитов из проиндексированных изменений с учётом вашей структуры, голоса и предпочтений по охвату.';
  @override
  String get reviewDescription =>
      'Ревью текущего объёма коммита перед тем, как вы его создадите.';
  @override
  String get museDescription =>
      'Трёхфазный оракул: сначала мозговой штурм, затем синтез направления вперёд для diff.';
}

// Path: settings.commitEditor
class _Translations$settings$commitEditor$ru
    extends Translations$settings$commitEditor$en {
  _Translations$settings$commitEditor$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get styleGuide => 'Руководство по стилю';
  @override
  String get styleGuideHint =>
      'Необязательно. Голос / тон / запреты. Формат выше задаёт скелет.';
}

// Path: settings.review
class _Translations$settings$review$ru extends Translations$settings$review$en {
  _Translations$settings$review$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Дополнительные заметки для ревью';
  @override
  String get doubleCheckLabel => 'Двойная проверка ревью';
  @override
  String get doubleCheckDescription =>
      'Запустить второй проход верификации перед показом итогового отчёта.';
}

// Path: settings.museHint
class _Translations$settings$museHint$ru
    extends Translations$settings$museHint$en {
  _Translations$settings$museHint$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'к чему мягко подтолкнуть? настроение сегодня доброе.';
  @override
  String get balanced =>
      'на чём задержаться, что пропустить. честно, но не жёстко.';
  @override
  String get strict => 'стандарты. запреты. что муза не спустит.';
  @override
  String get paranoid =>
      'настройте линзу. на каких частотах должен гудеть manifold?';
}

// Path: settings.museEditor
class _Translations$settings$museEditor$ru
    extends Translations$settings$museEditor$en {
  _Translations$settings$museEditor$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Дополнительные заметки для музы';
}

// Path: settings.museStage
class _Translations$settings$museStage$ru
    extends Translations$settings$museStage$en {
  _Translations$settings$museStage$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get brainstorm => 'МОЗГОВОЙ ШТУРМ';
  @override
  String get synthesize => 'СИНТЕЗ';
  @override
  String get slot => 'слот';
  @override
  String get ideaCountLoose => '~12 идей';
  @override
  String get ideaCountBalanced => '~16 идей';
  @override
  String get ideaCountStrict => '~20 идей';
  @override
  String get ideaCountParanoid => '~24 идеи';
  @override
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  ограждение: ${macro}';
}

// Path: settings.lensAxis
class _Translations$settings$lensAxis$ru
    extends Translations$settings$lensAxis$en {
  _Translations$settings$lensAxis$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get folder => 'ПАПКА';
  @override
  String get history => 'ИСТОРИЯ';
  @override
  String get far => 'ДАЛЕКО';
  @override
  String get near => 'БЛИЗКО';
}

// Path: settings.logosLens
class _Translations$settings$logosLens$ru
    extends Translations$settings$logosLens$en {
  _Translations$settings$logosLens$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get moduleMap => 'карта модулей';
  @override
  String get repoCenters => 'центры репозитория';
  @override
  String get neighbors => 'соседи';
  @override
  String get toTouch => 'что тронуть дальше';
  @override
  String get relevanceEngine => 'движок релевантности';
  @override
  String get description =>
      'читает, как файлы движутся вместе сквозь структуру, историю и ритм, чтобы Manifold знал, что важно, а не только что изменилось.';
  @override
  String get withinReach => 'в пределах досягаемости';
  @override
  String get gate => 'порог';
  @override
  String get nearest => 'ближайший';
  @override
  String get warming => 'прогрев';
  @override
  String get emptyOpenRepo =>
      'откройте репозиторий,\nчтобы увидеть линзу вживую';
  @override
  String get emptyNoFiles => 'нет файлов в\nдосягаемости — тяните\nк ИСТОРИИ';
}

// Path: settings.sortGuide
class _Translations$settings$sortGuide$ru
    extends Translations$settings$sortGuide$en {
  _Translations$settings$sortGuide$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Руководство по сортировке изменений';
  @override
  String get related =>
      'Файлы, меняющиеся вместе, группируются вместе. Сначала суть, потом контекст.';
  @override
  String get relatedInverted =>
      'Сначала изолированные изменения. Тесно связанные кластеры оседают внизу.';
  @override
  String get alphabetical =>
      'Просто А → Я по пути. Без учёта регистра, числа в естественном порядке.';
  @override
  String get alphabeticalInverted =>
      'Просто Я → А по пути. Без учёта регистра, числа в естественном порядке.';
  @override
  String get impact =>
      'Сначала всплывают самые тяжёлые изменения. Оборот взвешивается; бинарники и новые файлы получают буст.';
  @override
  String get impactInverted =>
      'Сначала всплывают самые лёгкие изменения. Быстрые победы сверху; тяжёлое ждёт.';
  @override
  String get nearRelated => 'по связности';
  @override
  String get alphabeticalShort => 'по алфавиту';
  @override
  String get byImpact => 'по влиянию';
  @override
  String get flipped => 'перевёрнуто';
  @override
  String get peek => 'заглянуть';
}

// Path: settings.piggyback
class _Translations$settings$piggyback$ru
    extends Translations$settings$piggyback$en {
  _Translations$settings$piggyback$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get apiModelsUse => 'API-модели используют';
  @override
  String get codexNotDetected => 'codex не обнаружен';
  @override
  String get dormant => 'СПИТ';
}

// Path: settings.diffStage
class _Translations$settings$diffStage$ru
    extends Translations$settings$diffStage$en {
  _Translations$settings$diffStage$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get viewer => 'просмотр';
  @override
  String get media => 'медиа';
  @override
  String get binary => 'бинарный';
  @override
  String get hidden => 'скрытый';
}

// Path: settings.undoScope
class _Translations$settings$undoScope$ru
    extends Translations$settings$undoScope$en {
  _Translations$settings$undoScope$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get destructiveActions => 'разрушительные действия';
  @override
  String get discards => 'отбрасывания';
  @override
  String get commits => 'коммиты';
  @override
  String get commitPush => 'коммит + отправка';
  @override
  String get all => 'всё';
}

// Path: settings.undoWindow
class _Translations$settings$undoWindow$ru
    extends Translations$settings$undoWindow$en {
  _Translations$settings$undoWindow$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Окно отмены';
  @override
  String get off => 'Выкл';
  @override
  String descriptionInstant({required Object scope}) =>
      '${scope} завершаются мгновенно.';
  @override
  String descriptionDelayed({required Object seconds, required Object scope}) =>
      '${seconds} с до завершения: ${scope}.';
  @override
  String get cycleScopeTooltip =>
      'Нажмите, чтобы переключить область · или тяните вверх/вниз по слайдеру';
  @override
  String get resetTooltip => 'Сбросить все действия на окно по умолчанию';
}

// Path: settings.guardrailPhrase
class _Translations$settings$guardrailPhrase$ru
    extends Translations$settings$guardrailPhrase$en {
  _Translations$settings$guardrailPhrase$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get probablyFine => '«Наверное, нормально» значит нормально';
  @override
  String get proper => 'Настоящее чтение, логика, интеграция, паттерны';
  @override
  String get lookAgain => 'Посмотрите ещё раз. Что-то может прятаться';
  @override
  String get assumeWrong => 'Предположите, что что-то не так. Найдите это';
}

// Path: settings.reviewGuideHint
class _Translations$settings$reviewGuideHint$ru
    extends Translations$settings$reviewGuideHint$en {
  _Translations$settings$reviewGuideHint$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get focusHigh =>
      'напр. Сосредоточьтесь на высокоуровневой логике и крупных багах. Кратко и снисходительно.';
  @override
  String get surfaceBugs =>
      'напр. Выявляйте возможные баги, архитектурные нестыковки и провалы на краевых случаях.';
  @override
  String get scrutinize =>
      'напр. Изучайте каждую строку на оптимизацию, безопасность и соответствие паттернам.';
  @override
  String get trustNothing =>
      'напр. Не доверяйте ничему. Ставьте под вопрос каждый побочный эффект. Считайте каждую строку потенциальным провалом.';
  @override
  String get optional =>
      'Необязательное указание, о чём должно заботиться ревью.';
}

// Path: settings.commitFormat
class _Translations$settings$commitFormat$ru
    extends Translations$settings$commitFormat$en {
  _Translations$settings$commitFormat$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Формат';
  @override
  String get peek => 'заглянуть';
  @override
  String get structure => 'Структура';
  @override
  String get voice => 'Голос';
  @override
  String get coverage => 'Охват';
  @override
  String get structureTitleBody => 'заголовок + текст';
  @override
  String get structureTitleOnly => 'только заголовок';
  @override
  String get structureFreeform => 'свободная форма';
  @override
  String get voiceVerbLed => 'с уклоном в действие';
  @override
  String get voiceDescriptive => 'описательный';
  @override
  String get voiceNarrative => 'повествовательный';
  @override
  String get coverageEssentials => 'суть';
  @override
  String get coverageBalanced => 'сбалансированно';
  @override
  String get coverageEverything => 'всё';
}

// Path: settings.commitPreview
class _Translations$settings$commitPreview$ru
    extends Translations$settings$commitPreview$en {
  _Translations$settings$commitPreview$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$ru title =
      _Translations$settings$commitPreview$title$ru._(_root);
  @override
  late final _Translations$settings$commitPreview$base$ru base =
      _Translations$settings$commitPreview$base$ru._(_root);
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$ru
  balancedSuffix = _Translations$settings$commitPreview$balancedSuffix$ru._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$ru
  everythingSuffix = _Translations$settings$commitPreview$everythingSuffix$ru._(
    _root,
  );
}

// Path: settings.externalTools
class _Translations$settings$externalTools$ru
    extends Translations$settings$externalTools$en {
  _Translations$settings$externalTools$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Внешние инструменты';
  @override
  String get summary =>
      'Щёлкните проект в боковой панели правой кнопкой, чтобы открыть его одним из них. Аргументы используют {path} для папки проекта.';
  @override
  String get detecting => 'Обнаруживаю установленные инструменты…';
  @override
  String get allPresetsAdded =>
      'Все известные пресеты уже добавлены. Используйте «+ Свой», чтобы добавить ещё.';
  @override
  String get noToolsConfigured =>
      'Инструменты ещё не настроены. Добавьте один выше.';
  @override
  String get categoryAi => 'ai';
  @override
  String get categoryEditors => 'редакторы';
  @override
  String get categoryExplore => 'обзор';
  @override
  String get categoryOps => 'операции';
  @override
  String get categoryGitOps => 'git-операции';
  @override
  String get nameHint => 'Имя';
  @override
  String get commandHint => 'команда';
  @override
  String get test => 'тест';
  @override
  String get removeTool => 'Удалить инструмент';
  @override
  String get modeTerminal => 'терминал';
  @override
  String get modeDetached => 'отсоединён';
}

// Path: settings.apiUsage
class _Translations$settings$apiUsage$ru
    extends Translations$settings$apiUsage$en {
  _Translations$settings$apiUsage$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String thisMonth({required Object used, required Object limit}) =>
      '${used}${limit} за этот месяц';
}

// Path: settings.gitea
class _Translations$settings$gitea$ru extends Translations$settings$gitea$en {
  _Translations$settings$gitea$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Токены Gitea';
  @override
  String get hostHint => 'хост';
  @override
  String get tokenHint => 'токен';
  @override
  String get save => 'сохранить';
}

// Path: settings.wick
class _Translations$settings$wick$ru extends Translations$settings$wick$en {
  _Translations$settings$wick$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get selectExecutable => 'Выберите исполняемый файл wick';
  @override
  String get connected => 'wick · подключён';
  @override
  String get pathToExecutable => 'wick · путь к исполняемому файлу';
  @override
  String get off => 'выкл.';
  @override
  String get disableHint => 'Выключить интеграцию wick';
  @override
  String get enableHint => 'Включить интеграцию wick';
}

// Path: settings.integrations
class _Translations$settings$integrations$ru
    extends Translations$settings$integrations$en {
  _Translations$settings$integrations$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'и интеграции';
  @override
  String get alpha => 'alpha';
  @override
  String get planned => 'в планах';
  @override
  String get lspComingSoon => 'lsp · скоро';
  @override
  String get alphaMathConnected => 'alpha-math · подключён';
  @override
  String get alphaMathComingSoon => 'alpha-math · скоро';
}

// Path: settings.reduceMotion
class _Translations$settings$reduceMotion$ru
    extends Translations$settings$reduceMotion$en {
  _Translations$settings$reduceMotion$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Меньше движения';
  @override
  String get subtitleStill => 'Неподвижно… как лёд?';
  @override
  String get subtitleFlow => 'Течёт как вода.';
}

// Path: settings.resetQuit
class _Translations$settings$resetQuit$ru
    extends Translations$settings$resetQuit$en {
  _Translations$settings$resetQuit$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get resetAndQuit => 'СБРОС И ВЫХОД';
  @override
  String get keepRepos => 'ОСТАВИТЬ РЕПОЗИТОРИИ';
  @override
  String get wipeAll => 'СТЕРЕТЬ ВСЁ';
}

// Path: settings.diagnostics
class _Translations$settings$diagnostics$ru
    extends Translations$settings$diagnostics$en {
  _Translations$settings$diagnostics$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get commandDiagnostics => 'Диагностика команд';
  @override
  String get networkFlowTelemetry => 'Телеметрия сетевого потока';
  @override
  String get clearSamples => 'Очистить образцы';
  @override
  String get clearMetrics => 'Очистить метрики';
  @override
  String get clearTimings => 'Очистить замеры';
  @override
  String get recalibrate => 'ПЕРЕКАЛИБРОВАТЬ';
  @override
  String get ok => 'ок';
  @override
  String get noCommandTimings =>
      'Замеров команд пока нет. Выполняйте обычные действия, чтобы наполнить диагностику.';
  @override
  String get noBackendSamples =>
      'Образцов бэкенд-команд пока нет. Выполняйте действия git и настроек, чтобы наполнить этот лог.';
  @override
  String get noDiffSessions =>
      'Сессий отрисовки diff пока нет. Открывайте и прокручивайте diff файлов, чтобы наполнить эту панель.';
  @override
  String get noUiSessions =>
      'Сессий замеров UI пока нет. Открывайте панели и переходите по маршрутам, чтобы наполнить эту панель.';
  @override
  String get recentOperations => 'Недавние операции';
  @override
  String get recentBackendOperations => 'Недавние бэкенд-операции';
  @override
  String get recentDiffSessions => 'Недавние сессии diff';
  @override
  String get recentUiTimings => 'Недавние замеры UI';
  @override
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} уникальная команда',
        few: '${n} уникальные команды',
        many: '${n} уникальных команд',
        other: '${n} уникальных команд',
      );
  @override
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} команда с областью',
        few: '${n} команды с областью',
        many: '${n} команд с областью',
        other: '${n} команд с областью',
      );
  @override
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} инструментированное событие',
        few: '${n} инструментированных события',
        many: '${n} инструментированных событий',
        other: '${n} инструментированных событий',
      );
  @override
  String summaryCommand({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryBackend({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryDiff({required Object sessions, required Object jank}) =>
      '${sessions} | джанк ${jank}%';
  @override
  String summaryUi({required Object samples, required Object events}) =>
      '${samples} | ${events}';
  @override
  List<String> get headersCommand => [
    'команда',
    'p50',
    'надёжность',
    'диапазон',
  ];
  @override
  List<String> get headersBackend => ['область', 'p50', 'p95', 'сбои'];
  @override
  List<String> get headersDiff => [
    'рендерер',
    'первая отрисовка',
    'кадр p95',
    'растр p95',
    'джанк',
  ];
  @override
  List<String> get headersUi => ['событие', 'p50', 'сбои', 'диапазон'];
}

// Path: settings.telemetry
class _Translations$settings$telemetry$ru
    extends Translations$settings$telemetry$en {
  _Translations$settings$telemetry$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} образец',
        few: '${n} образца',
        many: '${n} образцов',
        other: '${n} образцов',
      );
  @override
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} команда',
        few: '${n} команды',
        many: '${n} команд',
        other: '${n} команд',
      );
  @override
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} сессия',
        few: '${n} сессии',
        many: '${n} сессий',
        other: '${n} сессий',
      );
  @override
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} событие',
        few: '${n} события',
        many: '${n} событий',
        other: '${n} событий',
      );
  @override
  String stability({required Object pct}) => '${pct}% стабильности';
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
class _Translations$settings$flowEngine$ru
    extends Translations$settings$flowEngine$en {
  _Translations$settings$flowEngine$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get executionFlow => 'поток выполнения';
  @override
  String get description =>
      'симулирует осцилляторы на коде, выявляя хрупкие пути выполнения до того, как они кристаллизуются в баги.';
  @override
  String get idle => 'простой';
  @override
  String get emptyOpenRepo =>
      'откройте репозиторий,\nчтобы увидеть анализ потока';
  @override
  String get scanning => 'сканирование';
  @override
  String get analysing => 'анализирую файлы\nв линзе…';
  @override
  String get fragility => 'хрупкость';
  @override
  String get findings => 'находки';
  @override
  String get gap => 'разрыв';
  @override
  String get clean => 'чисто';
  @override
  String get severity => 'серьёзность';
  @override
  String get critical => 'критично';
  @override
  String get warn => 'предупр.';
  @override
  String get info => 'инфо';
}

// Path: settings.museStrands
class _Translations$settings$museStrands$ru
    extends Translations$settings$museStrands$en {
  _Translations$settings$museStrands$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get spark => 'искра вдохновения · сразу следующий шаг';
  @override
  String get current => 'течение в воде · расширения в настоящем времени';
  @override
  String get horizon => 'взгляд за горизонт · дотягивающиеся направления';
  @override
  String get fever => 'пробуждение от горячечного сна · провокации';
  @override
  String get echo => 'эхо через каньон · аналоги в другом месте';
  @override
  String get vertigo => 'головокружение на краю обрыва · смежные риски';
  @override
  String get ghost => 'призрак того, что было · исторический контекст';
  @override
  String get mirror => 'зеркало на тихой воде · инверсии';
}

// Path: settings.cliPiggyback
class _Translations$settings$cliPiggyback$ru
    extends Translations$settings$cliPiggyback$en {
  _Translations$settings$cliPiggyback$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Пиггибэкинг CLI';
  @override
  String get clearCacheLabel => 'Очистить кэш';
  @override
  String get clearCacheTooltip =>
      'Стереть кэшированные модели и перепрозондировать. Убирает те, что провайдер отбросил.';
  @override
  String get refreshLabel => 'Обновить провайдеров';
  @override
  String get refreshTooltip => 'Перепрозондировать каждого провайдера сейчас.';
  @override
  String get body =>
      'Напрямую передавать сообщения интерфейса локальным бинарникам провайдеров.';
  @override
  String get cliTimeoutLabel => 'Тайм-аут на запуск';
  @override
  String get cliTimeoutUnitMinutes => 'минуты';
  @override
  String get cliTimeoutUnitMinute => 'минута';
  @override
  String get forceStopLabel => 'Остановить все сессии';
  @override
  String get forceStopTooltip =>
      'Принудительно завершить каждый запущенный процесс CLI.';
  @override
  String get forceStopConfirmTitle => 'Остановить запущенные сессии CLI?';
  @override
  String forceStopConfirmBody({required Object count}) =>
      'Это принудительно завершит запущенные процессы CLI (${count}). Их вывод будет потерян.';
  @override
  String get forceStopConfirmAction => 'Остановить все';
  @override
  String get forceStopNoneRunning => 'Нет запущенных сессий CLI';
  @override
  String get forceStopRecordError =>
      'Остановлено — сессии CLI были принудительно завершены.';
}

// Path: settings.header
class _Translations$settings$header$ru extends Translations$settings$header$en {
  _Translations$settings$header$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Предпочтения рабочего пространства';
  @override
  String get subtitle =>
      'Настройте глобальную эстетику, динамику интерфейса и ключевые операционные предохранители для всего рабочего пространства.';
  @override
  String get releaseNotesTooltip => 'Заметки к релизу';
  @override
  String get replayOnboardingTooltip => 'Повторить онбординг';
}

// Path: settings.diagnosticsPanel
class _Translations$settings$diagnosticsPanel$ru
    extends Translations$settings$diagnosticsPanel$en {
  _Translations$settings$diagnosticsPanel$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Диагностика производительности';
  @override
  String get copyTrace => 'Копировать след';
  @override
  String get offenderRanking => 'Рейтинг нарушителей';
  @override
  String get offenderRankingSubtitle => 'Драйверы задержки по всем потокам.';
  @override
  String get noOffenders =>
      'Рейтинга нарушителей пока нет. Соберите диагностическую активность, чтобы наполнить этот список.';
}

// Path: settings.release
class _Translations$settings$release$ru
    extends Translations$settings$release$en {
  _Translations$settings$release$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Развёртывание релиза';
  @override
  String get summary => 'Настройки, связанные с обновлениями.';
  @override
  String get deploymentChannel => 'КАНАЛ РАЗВЁРТЫВАНИЯ';
  @override
  String get captureCrashDiagnostics => 'Собирать диагностику сбоев';
  @override
  String get comingSoon => 'Скоро.';
  @override
  String get checking => 'ПРОВЕРКА…';
  @override
  String get pollForUpdates => 'ПРОВЕРИТЬ ОБНОВЛЕНИЯ';
}

// Path: settings.providerStatus
class _Translations$settings$providerStatus$ru
    extends Translations$settings$providerStatus$en {
  _Translations$settings$providerStatus$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get detecting => 'Обнаружение...';
  @override
  String get ready => 'Готов';
  @override
  String get notDetected => 'Не обнаружен';
  @override
  String configured({required Object count}) => '${count} настроено';
  @override
  String get notConfigured => 'Не настроен';
  @override
  String get cliManaged => 'Под управлением CLI';
  @override
  String get connected => 'Подключён';
  @override
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} модель',
        few: '${n} модели',
        many: '${n} моделей',
        other: '${n} моделей',
      );
  @override
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} провайдер',
        few: '${n} провайдера',
        many: '${n} провайдеров',
        other: '${n} провайдеров',
      );
}

// Path: settings.meridiem
class _Translations$settings$meridiem$ru
    extends Translations$settings$meridiem$en {
  _Translations$settings$meridiem$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get am => 'AM';
  @override
  String get pm => 'PM';
}

// Path: settings.offenders
class _Translations$settings$offenders$ru
    extends Translations$settings$offenders$en {
  _Translations$settings$offenders$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get commandStream => 'Команда';
  @override
  String get diffStream => 'Отрисовка diff';
  @override
  String get uiStream => 'Замер UI';
  @override
  String rendererName({required Object mode}) => 'рендерер ${mode}';
  @override
  String latencyFailMetric({required Object p95, required Object fail}) =>
      '${p95} мс p95 | ${fail}% сбоев';
  @override
  String jankFrameMetric({required Object jank, required Object frame}) =>
      '${jank}% джанка | ${frame} мс кадр p95';
  @override
  String inStream({required Object stream}) => 'в ${stream}';
}

// Path: sync.actions
class _Translations$sync$actions$ru extends Translations$sync$actions$en {
  _Translations$sync$actions$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get syncLabel => 'Синхронизировать';
  @override
  String get syncOpenRepoDetail =>
      'Откройте репозиторий, чтобы управлять пушем и пулом.';
  @override
  String get detachedHeadLabel => 'Отсоединённый HEAD';
  @override
  String get detachedHeadDetail =>
      'Переключитесь на ветку перед пушем или пулом.';
  @override
  String get publishBranchLabel => 'Опубликовать ветку';
  @override
  String publishBranchDetail({required Object branch}) =>
      'Запушить ${branch} и задать её upstream-ветку слежения.';
  @override
  String get publishButtonLabel => 'Опубликовать';
  @override
  String get syncBranchLabel => 'Синхронизировать ветку';
  @override
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => 'Запулить ${behindCount} с rebase, затем запушить ${aheadCount}.';
  @override
  String get syncBranchButtonLabel => 'Запулить (rebase), затем запушить';
  @override
  String get pushBranchLabel => 'Запушить ветку';
  @override
  String pushBranchDetail({required Object count, required Object upstream}) =>
      'Запушить ${count} в ${upstream}.';
  @override
  String get pushBranchButtonLabel => 'Запушить коммиты';
  @override
  String get pullUpdatesLabel => 'Запулить обновления';
  @override
  String pullUpdatesDetail({required Object count, required Object upstream}) =>
      'Запулить ${count} из ${upstream}.';
  @override
  String syncUpToDateDetail({required Object upstream}) =>
      'Зафетчить из ${upstream} и обновить статус upstream.';
}

// Path: sync.panel
class _Translations$sync$panel$ru extends Translations$sync$panel$en {
  _Translations$sync$panel$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Загрузка статуса удалённого';
  @override
  String get loadingMessage => 'Проверка данных слежения за веткой.';
  @override
  String get remoteStatusUnavailable => 'Статус удалённого недоступен';
  @override
  String get noUpstream => 'нет upstream';
  @override
  String get aheadLabel => 'Впереди';
  @override
  String get behindLabel => 'Позади';
  @override
  String get treeLabel => 'Дерево';
  @override
  String get runningSync => 'Синхронизация…';
  @override
  String get fetching => 'Фетч…';
  @override
  String get fetchOnly => 'Только фетч';
  @override
  String get syncFailed => 'Сбой синхронизации';
  @override
  String get forcePushRecoveryLabel => 'Форс-пуш (with lease)';
  @override
  String get conflictsToResolveTitle => 'Конфликты к устранению';
  @override
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} требуют устранения: ${list}';
  @override
  String get resolveConflicts => 'Устранить конфликты';
  @override
  String get workingEllipsis => 'Работаю…';
  @override
  String lastActivity({required Object operation}) =>
      'Последнее действие: ${operation}';
  @override
  String get noOutput => 'Нет вывода.';
  @override
  String resolvedConflicts({required Object count}) => 'Устранено: ${count}.';
  @override
  String get cancelledUnchanged => 'Отменено, рабочий каталог без изменений.';
  @override
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) =>
      '${count} с незакоммиченными правками, сначала закоммитьте их для rebase-синхронизации (${list}).';
  @override
  String noUpstreamForForcePush({required Object branch}) =>
      'Форс-пуш невозможен: для «${branch}» не настроен upstream.';
}

// Path: sync.forcePush
class _Translations$sync$forcePush$ru extends Translations$sync$forcePush$en {
  _Translations$sync$forcePush$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get confirmTitle => 'Форс-пуш (with lease)?';
  @override
  String target({required Object remote, required Object branch}) =>
      'Цель: ${remote}/${branch}';
  @override
  String get warning =>
      'Это перезапишет удалённую ветку вашей локальной историей. Режим with lease прервётся, если кто-то запушил в удалённый после вашего последнего fetch, но уже полученные изменения всё равно будут перезаписаны. Используйте только когда вы намеренно сделали rebase или amend, разошедшийся с веткой.';
  @override
  String get confirmButton => 'Форс-пуш';
}

// Path: xray.board
class _Translations$xray$board$ru extends Translations$xray$board$en {
  _Translations$xray$board$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get movesWithModule => 'движется с другим модулем';
  @override
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} ревьюер',
        few: '${n} ревьюера',
        many: '${n} ревьюеров',
        other: '${n} ревьюеров',
      );
  @override
  String get territory => 'Территория';
  @override
  String get unreviewed => 'без ревью';
}

// Path: xray.cadence
class _Translations$xray$cadence$ru extends Translations$xray$cadence$en {
  _Translations$xray$cadence$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '${sum} коммитов · ${days} дней\n${lines}';
  @override
  String burstTooltipSingle({required Object n, required Object label}) =>
      '${n} коммитов ${label}';
  @override
  String gapTooltip({required Object n, required Object label}) =>
      'разрыв ${n} дн · ${label}';
  @override
  String reflogTooltip({required Object n, required Object label}) =>
      '${n} событий reflog ${label}';
}

// Path: xray.cards
class _Translations$xray$cards$ru extends Translations$xray$cards$en {
  _Translations$xray$cards$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$cards$branchModel$ru branchModel =
      _Translations$xray$cards$branchModel$ru._(_root);
  @override
  late final _Translations$xray$cards$bursty$ru bursty =
      _Translations$xray$cards$bursty$ru._(_root);
  @override
  late final _Translations$xray$cards$hiddenRefs$ru hiddenRefs =
      _Translations$xray$cards$hiddenRefs$ru._(_root);
  @override
  late final _Translations$xray$cards$keystone$ru keystone =
      _Translations$xray$cards$keystone$ru._(_root);
  @override
  late final _Translations$xray$cards$machineHistory$ru machineHistory =
      _Translations$xray$cards$machineHistory$ru._(_root);
  @override
  late final _Translations$xray$cards$migration$ru migration =
      _Translations$xray$cards$migration$ru._(_root);
  @override
  late final _Translations$xray$cards$narrowHotspot$ru narrowHotspot =
      _Translations$xray$cards$narrowHotspot$ru._(_root);
  @override
  late final _Translations$xray$cards$noTags$ru noTags =
      _Translations$xray$cards$noTags$ru._(_root);
  @override
  late final _Translations$xray$cards$reflog$ru reflog =
      _Translations$xray$cards$reflog$ru._(_root);
  @override
  late final _Translations$xray$cards$singleOwner$ru singleOwner =
      _Translations$xray$cards$singleOwner$ru._(_root);
}

// Path: xray.cardTitle
class _Translations$xray$cardTitle$ru extends Translations$xray$cardTitle$en {
  _Translations$xray$cardTitle$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get branches => 'ветки';
  @override
  String get bursty => 'всплесковый';
  @override
  String get hiddenRefs => 'скрытые ссылки';
  @override
  String get machineHeavy => 'машинно-тяжёлый';
  @override
  String get migration => 'миграция';
  @override
  String get narrowHotspot => 'узкая горячая точка';
  @override
  String get noTags => 'нет меток';
  @override
  String get reflog => 'reflog';
  @override
  String get singleOwner => 'один владелец';
}

// Path: xray.grain
class _Translations$xray$grain$ru extends Translations$xray$grain$en {
  _Translations$xray$grain$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get coarsest => 'крупнейшая — модули верхнего уровня';
  @override
  String get finest => 'мельчайшая зернистость';
  @override
  String get mid => 'средняя зернистость';
  @override
  String get oneCharacteristic => 'один характерный масштаб';
}

// Path: xray.header
class _Translations$xray$header$ru extends Translations$xray$header$en {
  _Translations$xray$header$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get dirtyBadge => 'грязный';
  @override
  String get machineChip => 'машинный';
  @override
  String get refresh => 'Обновить';
  @override
  String get refreshing => 'Обновление...';
  @override
  String get title => 'X-Ray репозитория';
}

// Path: xray.hotspot
class _Translations$xray$hotspot$ru extends Translations$xray$hotspot$en {
  _Translations$xray$hotspot$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get clusterPeers => 'соседи по кластеру';
  @override
  String get coChangers => 'со-изменители';
  @override
  String get keystone => 'краеугольный';
  @override
  String keystoneScore({required Object score}) => 'краеугольный  φ=${score}';
}

// Path: xray.inspector
class _Translations$xray$inspector$ru extends Translations$xray$inspector$en {
  _Translations$xray$inspector$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get branchLabel => 'ветка';
  @override
  String commitsHumanMachine({required Object n}) => 'человек · ${n} машина';
  @override
  String get commitsLabel => 'коммиты';
  @override
  String get confidenceLabel => 'уверенность';
  @override
  String get curlLabel => 'curl';
  @override
  String get engineSection => 'движок';
  @override
  String get gradientLabel => 'градиент';
  @override
  String get harmonicLabel => 'гармоника';
  @override
  String get headLabel => 'head';
  @override
  String get hiddenRefsLabel => 'скрытые ссылки';
  @override
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} слияние',
        few: '${n} слияния',
        many: '${n} слияний',
        other: '${n} слияний',
      );
  @override
  String get noTags => 'нет меток';
  @override
  String get notesLabel => 'заметки';
  @override
  String get openCommit => 'Открыть коммит';
  @override
  String get pathLabel => 'путь';
  @override
  String remoteCount({required Object n}) => '${n} удалённых';
  @override
  String get renamesLabel => 'переименования';
  @override
  String scannedAt({required Object time}) => 'просканировано ${time}';
  @override
  String selectedCount({required Object n}) => '${n} выбрано';
  @override
  String get shapeLinear => 'линейный';
  @override
  String get shapeMergeHeavy => 'много слияний';
  @override
  String get shapeMostlyLinear => 'в основном линейный';
  @override
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} стэш',
        few: '${n} стэша',
        many: '${n} стэшей',
        other: '${n} стэшей',
      );
  @override
  String get stressLabel => 'напряжение';
  @override
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} метка',
        few: '${n} метки',
        many: '${n} меток',
        other: '${n} меток',
      );
  @override
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} рабочий каталог',
        few: '${n} рабочих каталога',
        many: '${n} рабочих каталогов',
        other: '${n} рабочих каталогов',
      );
}

// Path: xray.loadingCard
class _Translations$xray$loadingCard$ru
    extends Translations$xray$loadingCard$en {
  _Translations$xray$loadingCard$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get buildingMessage =>
      'Зондирую историю Git, ссылки, ритм и горячие точки.';
  @override
  String get buildingTitle => 'Строю рентген репозитория';
  @override
  String get idleMessage =>
      'Откройте панель снова, чтобы прозондировать текущий репозиторий.';
  @override
  String get idleTitle => 'X-Ray репозитория';
  @override
  String get unavailableTitle => 'X-Ray репозитория недоступен';
}

// Path: xray.metabolism
class _Translations$xray$metabolism$ru extends Translations$xray$metabolism$en {
  _Translations$xray$metabolism$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String halfLife({required Object n}) => 'период полураспада ${n} дн';
}

// Path: xray.multi
class _Translations$xray$multi$ru extends Translations$xray$multi$en {
  _Translations$xray$multi$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} кластер',
        few: '${n} кластера',
        many: '${n} кластеров',
        other: '${n} кластеров',
      );
  @override
  String clusterSingle({required Object id}) => 'кластер ${id}';
  @override
  String couplingSuffix({required Object parts}) => 'связность ${parts}';
  @override
  String externalCount({required Object n}) => '${n} внешних';
  @override
  String mutualCount({required Object n}) => '${n} взаимных';
}

// Path: xray.recency
class _Translations$xray$recency$ru extends Translations$xray$recency$en {
  _Translations$xray$recency$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String days({required Object n}) => '${n} дн';
  @override
  String months({required Object n}) => '${n} мес';
  @override
  String get today => 'сегодня';
  @override
  String weeks({required Object n}) => '${n} нед';
  @override
  String years({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} г',
        other: '${n} г',
      );
}

// Path: xray.rings
class _Translations$xray$rings$ru extends Translations$xray$rings$en {
  _Translations$xray$rings$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get hintOneBlended => 'одна смешанная структура';
  @override
  String get hintSelfSimilar => 'самоподобная';
  @override
  String get oneBlendedBody =>
      'Одна смешанная структура — отдельные масштабы модулей пока не разрешаются.';
  @override
  String get overHistory => 'За историю';
  @override
  String get parts => 'части';
  @override
  String get readingHint => 'читаю структуру…';
  @override
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} масштаб',
        few: '${n} масштаба',
        many: '${n} масштабов',
        other: '${n} масштабов',
      );
  @override
  String get scaleDissolved => 'структурный масштаб растворился';
  @override
  String get scaleEmerged => 'структурный масштаб проявился';
  @override
  String get scaleSpectrum => 'спектр масштабов';
  @override
  String get selfSimilarBody =>
      'Самоподобная — структура повторяется на всех масштабах, без единственного характерного уровня.';
  @override
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} сдвиг в истории',
        few: '${n} сдвига в истории',
        many: '${n} сдвигов в истории',
        other: '${n} сдвигов в истории',
      );
  @override
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} структурный сдвиг',
        few: '${n} структурных сдвига',
        many: '${n} структурных сдвигов',
        other: '${n} структурных сдвигов',
      );
  @override
  String get title => 'Кольца роста';
  @override
  String get unavailable => 'недоступно';
}

// Path: xray.stats
class _Translations$xray$stats$ru extends Translations$xray$stats$en {
  _Translations$xray$stats$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get alive => 'живой';
  @override
  String get files => 'файлы';
  @override
  String get lastTouched => 'последнее касание';
  @override
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'владелец',
        few: 'владельца',
        many: 'владельцев',
        other: 'владельцев',
      );
  @override
  String get touches => 'касания';
}

// Path: xray.stratumLabel
class _Translations$xray$stratumLabel$ru
    extends Translations$xray$stratumLabel$en {
  _Translations$xray$stratumLabel$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'текущий';
  @override
  String get legacy => 'легаси';
  @override
  String get zone => 'зона репозитория';
}

// Path: xray.summary
class _Translations$xray$summary$ru extends Translations$xray$summary$en {
  _Translations$xray$summary$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String analysisFailed({required Object error}) =>
      'Анализ не удался: ${error}';
  @override
  String get analyze => 'Анализ';
  @override
  String get copied => 'Сводка скопирована в буфер обмена.';
  @override
  String get directionHint => 'направление';
  @override
  String get download => 'Скачать';
  @override
  String get emptyState =>
      'Запустите анализ Logos, чтобы отобразить структуру и регионы этого репозитория.\n(tw: пока сыровато)';
  @override
  String get exit => 'Выход';
  @override
  String get generating => 'Читаю репозиторий и кластеризую признаки…';
  @override
  String get noModel => 'AI-модель не настроена.';
  @override
  String get noModelConfigured => 'AI-модель не настроена';
  @override
  String presentWith({required Object label}) => 'презентовать с ${label}';
  @override
  String presentingWith({required Object label}) => 'презентую с ${label}…';
  @override
  String get reanalyze => 'Переанализировать';
  @override
  String get saveDialogTitle => 'Сохранить сводку репозитория';
  @override
  String saveFailed({required Object error}) =>
      'Не удалось сохранить: ${error}';
  @override
  String get savePresentationDialogTitle => 'Сохранить презентацию';
  @override
  String savedTo({required Object path}) => 'Сохранено в ${path}';
}

// Path: xray.tabs
class _Translations$xray$tabs$ru extends Translations$xray$tabs$en {
  _Translations$xray$tabs$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get map => 'Карта';
  @override
  String get signals => 'Сигналы';
  @override
  String get summary => 'Сводка';
  @override
  String get time => 'Время';
}

// Path: xray.trajectory
class _Translations$xray$trajectory$ru extends Translations$xray$trajectory$en {
  _Translations$xray$trajectory$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get connectivity => 'связность';
  @override
  String events({required Object n}) => '${n} событий';
  @override
  String get openInOrrery => 'Открыть в Orrery';
  @override
  String get readingHint => 'читаю историю…';
  @override
  String snapshots({required Object n}) => '${n} снимков';
  @override
  String get steady => 'Ровно — структурных событий в этом окне нет.';
  @override
  String get title => 'Структурная траектория';
}

// Path: xray.verdict
class _Translations$xray$verdict$ru extends Translations$xray$verdict$en {
  _Translations$xray$verdict$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String canonical({required Object pct}) => '${pct}% канонично';
  @override
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · ${canonical}% канонично · ${decisive}% решительно';
}

// Path: changes.mergeEditor.trust
class _Translations$changes$mergeEditor$trust$ru
    extends Translations$changes$mergeEditor$trust$en {
  _Translations$changes$mergeEditor$trust$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get manual => 'вручную';
  @override
  String get safe => 'безопасно';
  @override
  String get guided => 'с подсказками';
  @override
  String get assisted => 'с помощью';
  @override
  String get full => 'полное';
  @override
  String label({required Object label}) => 'доверие: ${label}';
}

// Path: changes.mergeEditor.keyHints
class _Translations$changes$mergeEditor$keyHints$ru
    extends Translations$changes$mergeEditor$keyHints$en {
  _Translations$changes$mergeEditor$keyHints$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get accept => 'принять';
  @override
  String get other => 'другой';
  @override
  String get both => 'оба';
  @override
  String get navigate => 'навигация';
  @override
  String get jumpNext => 'к следующему';
}

// Path: changes.mergeFlow.op
class _Translations$changes$mergeFlow$op$ru
    extends Translations$changes$mergeFlow$op$en {
  _Translations$changes$mergeFlow$op$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'слияние';
  @override
  String get cherryPick => 'cherry-pick';
  @override
  String get revert => 'откат';
  @override
  String get resolve => 'устранение';
  @override
  String get switchOp => 'переключение';
  @override
  String get pull => 'получение';
  @override
  String get rebase => 'rebase';
  @override
  String rebaseOnto({required Object branch, required Object base}) =>
      'rebase ${branch} на ${base}';
}

// Path: diff.pinned.tempo
class _Translations$diff$pinned$tempo$ru
    extends Translations$diff$pinned$tempo$en {
  _Translations$diff$pinned$tempo$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get hotOwnerLane =>
      'Недавнее движение с одним сильным владельцем поблизости.';
  @override
  String get activeSeam => 'Недавнее движение от нескольких рук поблизости.';
  @override
  String get stableOwnerLane =>
      'Долгоживущая дорожка с одним доминирующим владельцем.';
  @override
  String get sharedLongLivedSeam => 'Общий шов, накопившийся со временем.';
  @override
  String get sharedLane =>
      'Общая дорожка без единственного доминирующего владельца.';
  @override
  String get resolving => 'История вокруг этой строки ещё проясняется.';
}

// Path: diff.pinned.tone
class _Translations$diff$pinned$tone$ru
    extends Translations$diff$pinned$tone$en {
  _Translations$diff$pinned$tone$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get hot => 'Горячо';
  @override
  String get novel => 'Ново';
  @override
  String get contested => 'Спорно';
  @override
  String get spreading => 'Расходится';
  @override
  String get stable => 'Стабильно';
}

// Path: diff.pinned.summary
class _Translations$diff$pinned$summary$ru
    extends Translations$diff$pinned$summary$en {
  _Translations$diff$pinned$summary$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String livesIn({required Object concept}) => 'Живёт в ${concept}';
  @override
  String get sitsInLocalSeam => 'Расположен в локальном шве';
  @override
  String workedMostlyBy({required Object owner}) =>
      'в основном правил ${owner} поблизости';
  @override
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'отголосок в ${n} другом месте',
        few: 'отголоски в ${n} других местах',
        many: 'отголоски в ${n} других местах',
        other: 'отголоски в ${n} других местах',
      );
  @override
  String inspectNext({required Object path, required Object detail}) =>
      'далее изучить ${path}${detail}';
  @override
  String inspectDetail({required Object reason}) => ' (${reason})';
}

// Path: diff.pinned.tightness
class _Translations$diff$pinned$tightness$ru
    extends Translations$diff$pinned$tightness$en {
  _Translations$diff$pinned$tightness$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get tight => 'плотная посадка';
  @override
  String get close => 'тесная посадка';
  @override
  String get loose => 'свободная посадка';
}

// Path: diff.pinned.witness
class _Translations$diff$pinned$witness$ru
    extends Translations$diff$pinned$witness$en {
  _Translations$diff$pinned$witness$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String nearbySupport({required Object label}) => 'Поддержка рядом · ${label}';
  @override
  String localizedMove({required Object label}) =>
      'Локальное движение · ${label}';
  @override
  String surprisingMove({required Object label}) =>
      'Неожиданное движение · ${label}';
}

// Path: diff.pinned.integrity
class _Translations$diff$pinned$integrity$ru
    extends Translations$diff$pinned$integrity$en {
  _Translations$diff$pinned$integrity$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get stableStructure => 'Стабильная структура';
  @override
  String get conflictingSignals => 'Противоречивые сигналы';
  @override
  String get novelShape => 'Новая форма';
}

// Path: diff.pinned.related
class _Translations$diff$pinned$related$ru
    extends Translations$diff$pinned$related$en {
  _Translations$diff$pinned$related$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get testMirror => 'Тест-зеркало';
  @override
  String get semanticHistorySibling => 'Семантический и исторический родич';
  @override
  String get recentCoChange => 'Недавнее совместное изменение';
  @override
  String get semanticSibling => 'Семантический родич';
  @override
  String get relatedStructure => 'Связанная структура';
  @override
  String get tightlyBound => 'тесно связан';
  @override
  String get orbiting => 'на орбите';
  @override
  String get weaklyCoupled => 'слабо связан';
  @override
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class _Translations$diff$pinned$axis$ru
    extends Translations$diff$pinned$axis$en {
  _Translations$diff$pinned$axis$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get historyTrail => 'след истории';
  @override
  String get testMirrorLane => 'дорожка тест-зеркала';
  @override
  String get structuralLane => 'структурная дорожка';
  @override
  String get semanticNeighbourhood => 'семантическая окрестность';
}

// Path: history.commitLede.semantics
class _Translations$history$commitLede$semantics$ru
    extends Translations$history$commitLede$semantics$en {
  _Translations$history$commitLede$semantics$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get importanceHigh => 'высокая важность';
  @override
  String get importanceModerate => 'умеренная важность';
  @override
  String get mostlyAdditions => 'в основном добавления';
  @override
  String get mostlyDeletions => 'в основном удаления';
  @override
  String get tightlyCoupled => 'тесно связанные файлы';
  @override
  String get overlapsWorkingTree => 'пересекается с рабочим каталогом';
}

// Path: onboarding.repo.doors
class _Translations$onboarding$repo$doors$ru
    extends Translations$onboarding$repo$doors$en {
  _Translations$onboarding$repo$doors$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$repo$doors$open$ru open =
      _Translations$onboarding$repo$doors$open$ru._(_root);
  @override
  late final _Translations$onboarding$repo$doors$clone$ru clone =
      _Translations$onboarding$repo$doors$clone$ru._(_root);
  @override
  late final _Translations$onboarding$repo$doors$create$ru create =
      _Translations$onboarding$repo$doors$create$ru._(_root);
}

// Path: onboarding.repo.cloneForm
class _Translations$onboarding$repo$cloneForm$ru
    extends Translations$onboarding$repo$cloneForm$en {
  _Translations$onboarding$repo$cloneForm$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Клонировать из URL';
  @override
  String get urlLabel => 'URL репозитория';
  @override
  String get targetLabel => 'Целевая папка';
  @override
  String get browse => 'Обзор…';
  @override
  String get clone => 'Клонировать';
  @override
  String get cloning => 'Клонирование…';
}

// Path: onboarding.repo.pickers
class _Translations$onboarding$repo$pickers$ru
    extends Translations$onboarding$repo$pickers$en {
  _Translations$onboarding$repo$pickers$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get openRepository => 'Открыть репозиторий';
  @override
  String get createRepository => 'Создать репозиторий';
  @override
  String get cloneTarget => 'Цель клонирования';
}

// Path: onboarding.repo.errors
class _Translations$onboarding$repo$errors$ru
    extends Translations$onboarding$repo$errors$en {
  _Translations$onboarding$repo$errors$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get urlAndTargetRequired => 'Нужны URL и целевой путь.';
  @override
  String get createFailed => 'Не удалось создать репозиторий.';
  @override
  String get cloneFailed => 'Не удалось клонировать репозиторий.';
}

// Path: onboarding.preview.panels
class _Translations$onboarding$preview$panels$ru
    extends Translations$onboarding$preview$panels$en {
  _Translations$onboarding$preview$panels$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get xray => 'рентген репозитория';
  @override
  String get settings => 'настройки';
}

// Path: onboarding.preview.sidebar
class _Translations$onboarding$preview$sidebar$ru
    extends Translations$onboarding$preview$sidebar$en {
  _Translations$onboarding$preview$sidebar$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get projectsHeader => 'Проекты';
}

// Path: onboarding.preview.changes
class _Translations$onboarding$preview$changes$ru
    extends Translations$onboarding$preview$changes$en {
  _Translations$onboarding$preview$changes$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String filesStagedCount({required Object staged, required Object total}) =>
      '${staged} из ${total} файлов';
  @override
  String stagedCount({required Object n}) => '${n} в индексе';
  @override
  String get commitMessageHint => 'Сообщение коммита…';
  @override
  String get commitAndPush => 'Коммит и отправка';
}

// Path: onboarding.preview.history
class _Translations$onboarding$preview$history$ru
    extends Translations$onboarding$preview$history$en {
  _Translations$onboarding$preview$history$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'История';
  @override
  String get viewingLast => 'показаны последние 20 коммитов';
  @override
  String get inFlight => 'В РАБОТЕ';
  @override
  String get you => 'вы';
  @override
  String get commit1 => 'научить лиса принюхиваться, прежде чем глотать';
  @override
  String get commit2 => 'янтарь: держать запах всю ночь';
  @override
  String get commit3 => 'заменить капусту на янтарь и шип';
  @override
  String get commit4 => 'шип стережёт вход';
}

// Path: onboarding.preview.branches
class _Translations$onboarding$preview$branches$ru
    extends Translations$onboarding$preview$branches$en {
  _Translations$onboarding$preview$branches$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get lensBranches => 'ВЕТКИ';
  @override
  String get lensPRs => 'PR';
  @override
  String get absorbed => 'поглощена';
  @override
  String get desk => 'Desk';
  @override
  String get head => 'HEAD';
  @override
  String tracking({required Object ref}) => '→ слежение: ${ref}';
}

// Path: onboarding.preview.diff
class _Translations$onboarding$preview$diff$ru
    extends Translations$onboarding$preview$diff$en {
  _Translations$onboarding$preview$diff$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get readmeTagline => 'Ваш личный git-клиент.';
}

// Path: releaseNotes.about.whyFlutter
class _Translations$releaseNotes$about$whyFlutter$ru
    extends Translations$releaseNotes$about$whyFlutter$en {
  _Translations$releaseNotes$about$whyFlutter$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'ПОЧЕМУ FLUTTER?';
  @override
  String get body =>
      'Первая версия была приложением на Tauri (Rust + TypeScript). Я и сам уже чувствовал, что оно медленное. Потом поймал стримера, который говорил ровно то же самое на стриме, который я обычно не смотрю, — и это стало толчком наконец сменить стек. Flutter он не советовал, скорее наоборот. Dart я нашёл сам, накидал прототип, и запуск сократился примерно с 15 секунд до менее чем одной. Небо и земля. Прощай, эпоха Tauri.\n\nКонвейер отрисовки во Flutter ближе к игровому движку, чем к DOM, а для настольного приложения, где интерфейс и есть продукт, это решает всё. Dart вдобавок оказался по-настоящему хорошим языком. Математику спектрального движка сперва прототипировали на Rust, так что та работа перенеслась без потерь.\n\nFlutter кроссплатформенный по умолчанию, и это здорово, но по натуре он гугловый, так что пара причуд есть.';
}

// Path: releaseNotes.about.spectralEngine
class _Translations$releaseNotes$about$spectralEngine$ru
    extends Translations$releaseNotes$about$spectralEngine$en {
  _Translations$releaseNotes$about$spectralEngine$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'ЧТО ТАКОЕ СПЕКТРАЛЬНЫЙ ДВИЖОК?';
  @override
  String get body =>
      'Каждый раз, когда вы делаете коммит, файлы, которые вы меняете вместе, со временем складываются в узоры. Спектральный движок читает ваш граф коммитов и раскладывает эти узоры совместных изменений на сигналы: какие файлы связаны, насколько тесно и какую структурную роль они играют в репозитории. По сути, спектральный анализ вашей истории разработки. В git-клиенте. Намеренно.\n\nМатематика тут новая, так что я отношусь к ней как к геймфилу: настраиваю, проверяю, корректирую и продолжаю, пока сигналы не начнут ощущаться правильными.\n\nЭти сигналы питают всё. Сейсмограф в истории, крашеные полоски под темами коммитов, систему ревью, Muse, созвездие файлов. Всё приложение рассуждает от этого слоя вниз, а не наоборот.';
}

// Path: releaseNotes.about.whereGoing
class _Translations$releaseNotes$about$whereGoing$ru
    extends Translations$releaseNotes$about$whereGoing$en {
  _Translations$releaseNotes$about$whereGoing$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'КУДА ЭТО ВСЁ ДВИЖЕТСЯ?';
  @override
  String get body =>
      'Первая веха — полный паритет с GitHub Desktop, SourceTree и GitKraken. Кроссплатформенный git-клиент, который ощущается быстрым и справляется с базовыми вещами лучше всех остальных. Это по большей части уже есть. Спектральный движок уже даёт нам преимущество в операциях, которые другие клиенты заставляют продумывать вручную.\n\nДальше цель — превзойти все прочие git-клиенты по скорости, доступности, интеллекту и общему UX. В работе есть больше, чем объявлено здесь.';
}

// Path: settings.commitPreview.title
class _Translations$settings$commitPreview$title$ru
    extends Translations$settings$commitPreview$title$en {
  _Translations$settings$commitPreview$title$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$verbLed$ru verbLed =
      _Translations$settings$commitPreview$title$verbLed$ru._(_root);
  @override
  late final _Translations$settings$commitPreview$title$descriptive$ru
  descriptive = _Translations$settings$commitPreview$title$descriptive$ru._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$title$narrative$ru narrative =
      _Translations$settings$commitPreview$title$narrative$ru._(_root);
}

// Path: settings.commitPreview.base
class _Translations$settings$commitPreview$base$ru
    extends Translations$settings$commitPreview$base$en {
  _Translations$settings$commitPreview$base$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$base$verbLed$ru verbLed =
      _Translations$settings$commitPreview$base$verbLed$ru._(_root);
  @override
  late final _Translations$settings$commitPreview$base$descriptive$ru
  descriptive = _Translations$settings$commitPreview$base$descriptive$ru._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$base$narrative$ru narrative =
      _Translations$settings$commitPreview$base$narrative$ru._(_root);
}

// Path: settings.commitPreview.balancedSuffix
class _Translations$settings$commitPreview$balancedSuffix$ru
    extends Translations$settings$commitPreview$balancedSuffix$en {
  _Translations$settings$commitPreview$balancedSuffix$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$verbLed$ru
  verbLed = _Translations$settings$commitPreview$balancedSuffix$verbLed$ru._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$descriptive$ru
  descriptive =
      _Translations$settings$commitPreview$balancedSuffix$descriptive$ru._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$narrative$ru
  narrative =
      _Translations$settings$commitPreview$balancedSuffix$narrative$ru._(_root);
}

// Path: settings.commitPreview.everythingSuffix
class _Translations$settings$commitPreview$everythingSuffix$ru
    extends Translations$settings$commitPreview$everythingSuffix$en {
  _Translations$settings$commitPreview$everythingSuffix$ru._(
    TranslationsRu root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$verbLed$ru
  verbLed = _Translations$settings$commitPreview$everythingSuffix$verbLed$ru._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$descriptive$ru
  descriptive =
      _Translations$settings$commitPreview$everythingSuffix$descriptive$ru._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$narrative$ru
  narrative =
      _Translations$settings$commitPreview$everythingSuffix$narrative$ru._(
        _root,
      );
}

// Path: xray.cards.branchModel
class _Translations$xray$cards$branchModel$ru
    extends Translations$xray$cards$branchModel$en {
  _Translations$xray$cards$branchModel$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get broadClaim =>
      'У репозитория достаточно ветвевой поверхности, чтобы навигация с учётом веток окупалась.';
  @override
  String get broadTitle => 'У модели веток есть площадь';
  @override
  String localBranchesDetail({required Object count}) =>
      '${count} локальных веток.';
  @override
  String get localBranchesLabel => 'Локальные ветки';
  @override
  String remoteBranchesDetail({required Object count}) =>
      '${count} удалённых веток.';
  @override
  String get remoteBranchesLabel => 'Удалённые ветки';
  @override
  String get simpleClaim => 'Видимая модель веток узкая.';
  @override
  String get simpleTitle => 'Простая модель веток';
}

// Path: xray.cards.bursty
class _Translations$xray$cards$bursty$ru
    extends Translations$xray$cards$bursty$en {
  _Translations$xray$cards$bursty$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Работа приходит концентрированными всплесками, а не ровным дневным ритмом.';
  @override
  String get title => 'Всплесковый ритм разработки';
}

// Path: xray.cards.hiddenRefs
class _Translations$xray$cards$hiddenRefs$ru
    extends Translations$xray$cards$hiddenRefs$en {
  _Translations$xray$cards$hiddenRefs$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object count}) =>
      '${count} ссылок живут вне обычного пространства веток/меток.';
  @override
  String evidenceDetail({required Object count}) =>
      '${count} ссылок вне heads/remotes/tags.';
  @override
  String get evidenceLabel => 'Скрытые ссылки';
  @override
  String get namespacesLabel => 'Пространства имён';
  @override
  String get title => 'Скрытые пространства имён Git';
}

// Path: xray.cards.keystone
class _Translations$xray$cards$keystone$ru
    extends Translations$xray$cards$keystone$en {
  _Translations$xray$cards$keystone$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String claim({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
    n,
    one:
        'Один файл несёт непропорциональный вес совместных изменений относительно числа касаний.',
    few:
        'Небольшой набор файлов несёт непропорциональный вес совместных изменений относительно числа касаний.',
    many:
        'Небольшой набор файлов несёт непропорциональный вес совместных изменений относительно числа касаний.',
    other:
        'Небольшой набор файлов несёт непропорциональный вес совместных изменений относительно числа касаний.',
  );
  @override
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: '${n} касание · тяга φ=${score}',
        few: '${n} касания · тяга φ=${score}',
        many: '${n} касаний · тяга φ=${score}',
        other: '${n} касаний · тяга φ=${score}',
      );
  @override
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ru'))(
        n,
        one: 'Краеугольный файл-мост',
        few: '${n} краеугольных файла-моста',
        many: '${n} краеугольных файлов-мостов',
        other: '${n} краеугольных файлов-мостов',
      );
}

// Path: xray.cards.machineHistory
class _Translations$xray$cards$machineHistory$ru
    extends Translations$xray$cards$machineHistory$en {
  _Translations$xray$cards$machineHistory$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Коммиты-контрольные точки существенно искажают наивные метрики истории.';
  @override
  String machineCommitsDetail({required Object count}) =>
      '${count} коммитов совпали с машинными/сессионными паттернами.';
  @override
  String get machineCommitsLabel => 'Машинные коммиты';
  @override
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '${raw} сырых коммитов против ${filtered} отфильтрованных.';
  @override
  String get rawVsFilteredLabel => 'Сырые против отфильтрованных';
  @override
  String get title => 'Машинная история доминирует в сырых метриках';
}

// Path: xray.cards.migration
class _Translations$xray$cards$migration$ru
    extends Translations$xray$cards$migration$en {
  _Translations$xray$cards$migration$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object older, required Object newer}) =>
      'История смещается с `${older}` на `${newer}`, что указывает на переход стека или поверхности.';
  @override
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches} касаний, последняя активность ${lastActive}.';
  @override
  String get title => 'Видна миграция архитектуры';
}

// Path: xray.cards.narrowHotspot
class _Translations$xray$cards$narrowHotspot$ru
    extends Translations$xray$cards$narrowHotspot$en {
  _Translations$xray$cards$narrowHotspot$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Небольшой набор файлов и каталогов поглощает непропорциональную долю изменений.';
  @override
  String get title => 'Концентрация горячих точек узкая';
  @override
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path} составляет ${pct}% видимого набора горячих точек.';
  @override
  String get topHotspotLabel => 'Главная горячая точка';
  @override
  String visibleAuthorsDetail({required Object count}) =>
      '${count} авторов в этом срезе истории.';
  @override
  String get visibleAuthorsLabel => 'Видимые авторы';
}

// Path: xray.cards.noTags
class _Translations$xray$cards$noTags$ru
    extends Translations$xray$cards$noTags$en {
  _Translations$xray$cards$noTags$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Метки git не используются как видимый слой релизов или вех.';
  @override
  String remoteEndpointsDetail({required Object count}) =>
      '${count} удалённых точек настроено.';
  @override
  String get remoteEndpointsLabel => 'Удалённые точки';
  @override
  String get tagCountDetail => 'Найдено 0 меток.';
  @override
  String get tagCountLabel => 'Число меток';
  @override
  String get title => 'Нет формального следа релизов/меток';
}

// Path: xray.cards.reflog
class _Translations$xray$cards$reflog$ru
    extends Translations$xray$cards$reflog$en {
  _Translations$xray$cards$reflog$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Объём reflog указывает на концентрированную локальную итерацию сверх опубликованных коммитов.';
  @override
  String get peakReflogDayLabel => 'Пиковый день reflog';
  @override
  String get title => 'Интенсивные сессии локальной правки';
}

// Path: xray.cards.singleOwner
class _Translations$xray$cards$singleOwner$ru
    extends Translations$xray$cards$singleOwner$en {
  _Translations$xray$cards$singleOwner$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object path, required Object kind}) =>
      '`${path}` — активно правимый ${kind} с одним отчётливым видимым автором.';
  @override
  String ownerCountDetail({required Object count}) =>
      '${count} отчётливых авторов.';
  @override
  String get ownerCountLabel => 'Число владельцев';
  @override
  String get title => 'Горячая точка одного владельца';
  @override
  String get touchCountLabel => 'Число касаний';
  @override
  String touchDetailFiltered({required Object count}) =>
      '${count} касаний в отфильтрованной истории.';
  @override
  String touchDetailRaw({required Object count}) =>
      '${count} касаний в сырой истории.';
}

// Path: onboarding.repo.doors.open
class _Translations$onboarding$repo$doors$open$ru
    extends Translations$onboarding$repo$doors$open$en {
  _Translations$onboarding$repo$doors$open$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Открыть';
  @override
  String get subtitle => 'существующий';
  @override
  String get hint => 'тот, что у вас уже есть';
}

// Path: onboarding.repo.doors.clone
class _Translations$onboarding$repo$doors$clone$ru
    extends Translations$onboarding$repo$doors$clone$en {
  _Translations$onboarding$repo$doors$clone$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Клонировать';
  @override
  String get subtitle => 'из URL';
  @override
  String get hint => 'вставьте удалённый URL';
}

// Path: onboarding.repo.doors.create
class _Translations$onboarding$repo$doors$create$ru
    extends Translations$onboarding$repo$doors$create$en {
  _Translations$onboarding$repo$doors$create$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Создать';
  @override
  String get subtitle => 'новый';
  @override
  String get hint => 'начните с чистого листа';
}

// Path: settings.commitPreview.title.verbLed
class _Translations$settings$commitPreview$title$verbLed$ru
    extends Translations$settings$commitPreview$title$verbLed$en {
  _Translations$settings$commitPreview$title$verbLed$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Пусть лис пропускает печенье, что пахнет не так';
  @override
  String get s2 =>
      'Научить лиса отвергать подделанное печенье до того, как проглотит';
  @override
  String get s3 =>
      'Заставить лиса криминалистически проверять каждое печенье у входа';
  @override
  String get def => 'Научить лиса отказываться от плохого печенья';
}

// Path: settings.commitPreview.title.descriptive
class _Translations$settings$commitPreview$title$descriptive$ru
    extends Translations$settings$commitPreview$title$descriptive$en {
  _Translations$settings$commitPreview$title$descriptive$ru._(
    TranslationsRu root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'теперь печенье выбирает лис';
  @override
  String get s2 => 'Процедура досмотра печенья, вбитая в лиса';
  @override
  String get s3 =>
      'Криминалистика проверки печенья, вживлённая в лиса повторением';
  @override
  String get def => 'Протокол принюхивания к печенью, установленный в лиса';
}

// Path: settings.commitPreview.title.narrative
class _Translations$settings$commitPreview$title$narrative$ru
    extends Translations$settings$commitPreview$title$narrative$en {
  _Translations$settings$commitPreview$title$narrative$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'лис начал пропускать печенье, что пахло не так';
  @override
  String get s2 => 'Сели с лисом и разобрали, какое печенье отвергать';
  @override
  String get s3 =>
      'Полдня убеждал лиса, что не всякое предложенное печенье — добросовестно печенье';
  @override
  String get def => 'Попросил лиса нюхать печенье, прежде чем есть';
}

// Path: settings.commitPreview.base.verbLed
class _Translations$settings$commitPreview$base$verbLed$ru
    extends Translations$settings$commitPreview$base$verbLed$en {
  _Translations$settings$commitPreview$base$verbLed$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Лис глянул. Что не так — оставляет.';
  @override
  String get s2 =>
      'Лис осматривает каждый токен, отклоняет всё с неправильным запахом и отмечает отказ на крыльце.';
  @override
  String get s3 =>
      'Лис обходит каждый токен, пробует воздух под тремя углами, отвергает всё, что читается не так, и выжидает миг, убеждаясь, что отказ закрепился.';
  @override
  String get def =>
      'Лис теперь нюхает каждый токен и вежливо отклоняет подозрительные.';
}

// Path: settings.commitPreview.base.descriptive
class _Translations$settings$commitPreview$base$descriptive$ru
    extends Translations$settings$commitPreview$base$descriptive$en {
  _Translations$settings$commitPreview$base$descriptive$ru._(
    TranslationsRu root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Мягкий пропуск странных, в основном.';
  @override
  String get s2 =>
      'Задокументированный отказ по каждому токену с неправильным запахом, вынесенный с крыльца и отмеченный.';
  @override
  String get s3 =>
      'Нотариально заверенный отказ по каждому пахнущему не так токену, вынесенный с крыльца с одной поднятой лапой, другая недвижима.';
  @override
  String get def =>
      'Вежливый отказ по подозрительным токенам, вынесенный с крыльца.';
}

// Path: settings.commitPreview.base.narrative
class _Translations$settings$commitPreview$base$narrative$ru
    extends Translations$settings$commitPreview$base$narrative$en {
  _Translations$settings$commitPreview$base$narrative$ru._(TranslationsRu root)
    : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Лис просто как-то перестал есть странные. Легко.';
  @override
  String get s2 =>
      'Раньше всякий токен проглатывался без раздумий; теперь есть пауза, надлежащий взгляд и отказ для тех, что сидят неладно.';
  @override
  String get s3 =>
      'Раньше всякий токен проглатывался без раздумий. Теперь: пауза. Воздух втянут. Воздух задержан. Лис следит за досками крыльца, за той мелкой дрожью, что бывает, когда что-то не так, и лишь тогда выносит решение.';
  @override
  String get def =>
      'Раньше всякий токен глотался без церемоний; теперь сперва — нюх.';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class _Translations$settings$commitPreview$balancedSuffix$verbLed$ru
    extends Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  _Translations$settings$commitPreview$balancedSuffix$verbLed$ru._(
    TranslationsRu root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Крыльцо в порядке. На задний двор всё равно.';
  @override
  String get s2 =>
      ' Крыльцо подметено после каждого отказа; грязь на заднем дворе допускается в объявленные часы.';
  @override
  String get s3 =>
      ' Крыльцо выметено и вымётено вновь; грязь на заднем дворе занесена в каталог по отпечаткам лап и погоде, и лис задерживается на пороге дольше прежнего.';
  @override
  String get def =>
      ' Крыльцо остаётся чистым; задний двор сохраняет права на грязь.';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class _Translations$settings$commitPreview$balancedSuffix$descriptive$ru
    extends Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  _Translations$settings$commitPreview$balancedSuffix$descriptive$ru._(
    TranslationsRu root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Крыльцо норм. Задний двор делает свои задворные дела.';
  @override
  String get s2 =>
      ' Крыльцо как зона, чистая от улик; задний двор как отведённая зона грязи, часы объявлены.';
  @override
  String get s3 =>
      ' Крыльцо как чистая комната уровня улик; задний двор как каталогизированный архив грязи; порог как место, где лис стоит и думает слишком долго.';
  @override
  String get def =>
      ' Чистое крыльцо; права на грязь сохранены на заднем дворе.';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class _Translations$settings$commitPreview$balancedSuffix$narrative$ru
    extends Translations$settings$commitPreview$balancedSuffix$narrative$en {
  _Translations$settings$commitPreview$balancedSuffix$narrative$ru._(
    TranslationsRu root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Крыльцо было в порядке. Задний двор — кто знает.';
  @override
  String get s2 =>
      ' Крыльцо после держали чистым; лис отступил на задний двор, где и происходит думанье.';
  @override
  String get s3 =>
      ' Крыльцо тем вечером отдраили дважды. Лис медленно обошёл задний двор, замер у того же столба забора, что и всегда, и оглянулся на крыльцо так, будто оно что-то задолжало.';
  @override
  String get def =>
      ' Крыльцо остаётся чистым, хотя задний двор всё же берёт достоинством.';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class _Translations$settings$commitPreview$everythingSuffix$verbLed$ru
    extends Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  _Translations$settings$commitPreview$everythingSuffix$verbLed$ru._(
    TranslationsRu root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Янтарь на месте. Дрейф дрейфует. Шип колет, если надо. В основном ничего.';
  @override
  String get s2 =>
      ' Янтарь держит каждый запах на проверку. Дрейф несёт дневной воздух к шипу у входа, что метит каждый отказ для вечернего подсчёта.';
  @override
  String get s3 =>
      ' Янтарь держит каждый запах и придаёт разный вес в зависимости от часа. Дрейф движется по крыльцу под углами, которые не должны иметь значения, но имеют. Шип у входа колет раз за отказы и дважды за те, что лис едва не пропустил, и лис знает разницу, даже когда её не знает никто.';
  @override
  String get def =>
      ' Янтарь держит запах. Дрейф несёт его дальше. Шип у входа ловит то, что не должно пройти.';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class _Translations$settings$commitPreview$everythingSuffix$descriptive$ru
    extends
        Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  _Translations$settings$commitPreview$everythingSuffix$descriptive$ru._(
    TranslationsRu root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Янтарь на столбе. Дрейф в воздухе. Шип у входа. Норм.';
  @override
  String get s2 =>
      ' Янтарь как назначенный свидетель запаха; дрейф как залогированный фон; отметки шипа как дневной реестр отказов, сверенный в сумерках.';
  @override
  String get s3 =>
      ' Янтарь как свидетель запаха, чьё молчание само есть показание; дрейф как узорчатый фон, движущийся не так в те дни, когда что-то не так; шип как счетовод входа, чьи отметки лис проверяет перед сном и снова перед рассветом.';
  @override
  String get def =>
      ' Янтарь как свидетель запаха; дрейф как фоновый контекст; шип как тихая метка отказа у входа.';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class _Translations$settings$commitPreview$everythingSuffix$narrative$ru
    extends Translations$settings$commitPreview$everythingSuffix$narrative$en {
  _Translations$settings$commitPreview$everythingSuffix$narrative$ru._(
    TranslationsRu root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsRu _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Янтарь был рядом. Дрейф приходил и уходил. Шип делал своё тихое дело. Да ладно, всё было спокойно.';
  @override
  String get s2 =>
      ' Янтарь вёл реестр запахов за день, дрейф отмечали по направлению и часу, а отметки шипа подсчитали и заверили с крыльца.';
  @override
  String get s3 =>
      ' Янтарь вёл реестр запахов, но лис клянётся, что в иные утра он тяжелее. Дрейф двигался по крыльцу как всегда, то есть не так в те дни, что важны. Шип у входа метил каждый отказ; лис выходил на первый свет их считать, как считают ступени, уже сосчитанные.';
  @override
  String get def =>
      ' Янтарь держал реестр запахов, дрейф двигал воздух, а шип у входа ловил то, что нужно было поймать.';
}
